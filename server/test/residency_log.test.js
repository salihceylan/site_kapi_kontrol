// Daire sakini ADLI KAYDI (075; DB'siz): sema <-> migration birebir esitlik, yalniz-ekleme tetikleyicisi, olay turleri ve kanca kapsami, anlik goruntu gizliligi
// (iletisim bilgisi YOK), erisim matrisi (yalniz site yoneticisi / super), adli bilgi dokumu (gerekce zorunlu, audit zorunlu, CSV / PDF), eski donem turetmesi.
// Gercek PostgreSQL davranisi (tetikleyici, CASCADE) bu testte DEGIL; SQL metni burada dogrulanir.
import { describe, it, before, after, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync, readdirSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import express from 'express';
import { pool } from '../src/db.js';
import { DEFAULT_MIGRATIONS_DIR, findUnsafeStatements, listMigrations } from '../scripts/migrate.js';
import { authRequired } from '../src/middlewares/auth_middleware.js';
import {
  RESIDENCY_ACTOR_ROLES,
  RESIDENCY_EVENT_TYPES,
  RESIDENCY_LOG_DDL,
  RESIDENCY_LOG_DDL_ORDER,
  RESIDENCY_LOG_MARKER,
  RESIDENCY_RELATIONS,
  ensureResidencyLogSchema,
  schemaTuning,
} from '../src/modules/residency_log_schema.js';
import {
  RESIDENCY_LOG_BULK_INSERT_SQL,
  RESIDENCY_LOG_INSERT_SQL,
  actorForLog,
  closeLogFor,
  logResidenciesBulk,
  logResidencyEvent,
  sanitizeRelated,
} from '../src/modules/residency_log.js';
import { csvCell, renderCsv, renderPdf } from '../src/modules/residency_log_export.js';
import { EXPORT_REASONS, mapLegacyRow, mapLogRow, parseExportRequest } from '../src/modules/residency_log_service.js';
import { exportLimiter, residencyLogRouter } from '../src/modules/residency_log_routes.js';
import { closeResidency, insertResidency } from '../src/modules/people_service.js';
import { applyApartmentPrimaryAdmin, handOverApartmentResident } from '../src/services/membership_service.js';
import { SYNC_STEPS } from '../src/modules/people_sync_sql.js';
import { RULES } from '../src/modules/platform_rules.js';

schemaTuning.retryDelayMs = 1;
process.env.JWT_SECRET ||= 'residency-log-test-secret';

const here = path.dirname(fileURLToPath(import.meta.url));
const SRC = path.join(here, '..', 'src');
const MIGRATION = readFileSync(path.join(DEFAULT_MIGRATIONS_DIR, '075_residency_log.sql'), 'utf8').replace(/\r\n/g, '\n');
const DB_SOURCE = readFileSync(path.join(SRC, 'db.js'), 'utf8').replace(/\r\n/g, '\n');
const SERVER_SOURCE = readFileSync(path.join(SRC, 'server.js'), 'utf8').replace(/\r\n/g, '\n');
const readSrc = (relative) => readFileSync(path.join(SRC, relative), 'utf8').replace(/\r\n/g, '\n');

const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
const ok = (rows = []) => ({ rows, rowCount: rows.length });

function normalizeSql(text) {
  return text.replace(/\/\*[\s\S]*?\*\//g, ' ').replace(/--.*$/gm, ' ').replace(/\s+/g, ' ').trim();
}

/** Migration metnini ust duzey ifadelere boler ($$ govdelerindeki ';' sayilmaz). */
function splitStatements(sqlText) {
  const text = sqlText.replace(/--.*$/gm, ' ');
  const statements = [];
  let current = '';
  let inDollar = false;
  for (let i = 0; i < text.length; i += 1) {
    if (text.startsWith('$$', i)) {
      inDollar = !inDollar;
      current += '$$';
      i += 1;
      continue;
    }
    if (text[i] === ';' && !inDollar) {
      if (current.trim() !== '') statements.push(normalizeSql(current));
      current = '';
      continue;
    }
    current += text[i];
  }
  if (current.trim() !== '') statements.push(normalizeSql(current));
  return statements;
}

const sql = (name) => normalizeSql(RESIDENCY_LOG_DDL[name]);
const CONTACT = /phone|telefon|e_?mail|tckn|tc_kimlik|identity_no|kimlik_no/i;

// ---------------------------------------------------------------------------
// Sema ve migration
// ---------------------------------------------------------------------------

describe('migration 075: adli kayit tablosu', () => {
  it('075 var, calistirici icin guvenli, numara yinelenmez', () => {
    const list = listMigrations(DEFAULT_MIGRATIONS_DIR);
    const entry = list.find((m) => m.number === 75);
    assert.ok(entry, '075 numarali migration yok');
    assert.equal(entry.file, '075_residency_log.sql');
    assert.equal(list.filter((m) => m.number === 75).length, 1);
    assert.deepEqual(findUnsafeStatements(MIGRATION), []);
  });

  it('RESIDENCY_LOG_DDL migration 075 ile AYNI ifadeleri tasir (yorum ve bosluk disinda birebir, AYNI sirayla)', () => {
    const fromMigration = splitStatements(MIGRATION);
    assert.equal(fromMigration.length, 11);
    assert.deepEqual(fromMigration, RESIDENCY_LOG_DDL_ORDER.map((name) => normalizeSql(RESIDENCY_LOG_DDL[name])));
    assert.deepEqual(Object.keys(RESIDENCY_LOG_DDL), [...RESIDENCY_LOG_DDL_ORDER]);
    assert.equal(/\\/.test(MIGRATION), false, 'ters egik cizgi yok (JS sablonu ile SQL arasinda kacis farki olmasin)');
  });

  it('islev govdeleri surum isaretini tasir (migration metninde de)', () => {
    assert.equal(RESIDENCY_LOG_MARKER, 'arl:1');
    for (const name of ['immutableFunction', 'truncateFunction', 'usersFunction']) {
      assert.ok(RESIDENCY_LOG_DDL[name].includes(`-- ${RESIDENCY_LOG_MARKER}`), name);
    }
    assert.equal((MIGRATION.match(/-- arl:1/g) ?? []).length, 3);
  });

  it('EKLEMELI ve idempotent: IF NOT EXISTS / CREATE OR REPLACE / katalog korumali FK ve tetikleyici; mevcut tabloya ALTER yok, DROP / UPDATE / DELETE YOK', () => {
    for (const statement of splitStatements(MIGRATION)) {
      assert.match(
        statement,
        /^(CREATE (UNIQUE )?(TABLE|INDEX) IF NOT EXISTS |CREATE OR REPLACE FUNCTION trg_(apartment_residency_log|users_log_residencies)\w*\(\) RETURNS trigger AS \$\$|DO \$\$ BEGIN IF NOT EXISTS \( SELECT 1 FROM pg_(constraint WHERE conname = '\w+_fkey'|trigger WHERE tgname = 'trg_\w+') AND (conrelid|tgrelid) = '(apartment_residency_log|users)'::regclass( AND NOT tgisinternal)? \) THEN (ALTER TABLE apartment_residency_log ADD CONSTRAINT|CREATE TRIGGER) )/,
      );
    }
    const all = normalizeSql(MIGRATION);
    assert.ok(!/\b(DROP|DELETE FROM|TRUNCATE TABLE)\b/i.test(all));
    assert.ok(!/UPDATE apartment_residency_log/i.test(all));
    assert.deepEqual([...new Set(all.match(/ALTER TABLE \w+/g))], ['ALTER TABLE apartment_residency_log']);
  });

  it('db.js ensureResidencyLogSchema(client) cagirir (ensureApartmentMgmtSchema SONRA, people_v1 ONCE); DDL dev blokta DEGIL; server.js router kaydeder', () => {
    const normalizedDb = normalizeSql(DB_SOURCE);
    for (const name of RESIDENCY_LOG_DDL_ORDER) {
      assert.equal(normalizedDb.includes(normalizeSql(RESIDENCY_LOG_DDL[name])), false, `${name} db.js icinde olmamali`);
    }
    assert.equal(/CREATE TABLE IF NOT EXISTS apartment_residency_log\b/.test(DB_SOURCE), false);
    assert.match(DB_SOURCE, /import \{ ensureResidencyLogSchema \} from '\.\/modules\/residency_log_schema\.js';/);
    const calls = [...DB_SOURCE.matchAll(/await ensureResidencyLogSchema\(client\);/g)];
    assert.equal(calls.length, 1);
    assert.ok(calls[0].index > DB_SOURCE.indexOf('await ensureApartmentMgmtSchema(client)'));
    assert.ok(calls[0].index < DB_SOURCE.indexOf('await runPeopleBackfill(client);'));
    assert.match(SERVER_SOURCE, /app\.use\(residencyLogRouter\);/);
  });
});

describe('sema ayrintilari', () => {
  it('tablo: kod alanlari, iletisim sutunu ve serbest not YOK; kullanici / daire FK\'si YOK (hesap silinse de kayit kalir); yalniz site FK (CASCADE)', () => {
    const table = sql('logTable');
    const columns = [...table.matchAll(/(?:\(| )(\w+) (?:BIGSERIAL|BIGINT|INTEGER|TEXT|DATE|JSONB|TIMESTAMPTZ)\b/g)].map((m) => m[1]);
    for (const name of ['site_code', 'apartment_id', 'apartment_label', 'event_type', 'reason_code', 'subject_name', 'subject_relation', 'subject_person_id', 'subject_user_code', 'period_start', 'period_end', 'actor_user_code', 'actor_name', 'actor_role', 'related', 'occurred_at']) {
      assert.ok(columns.includes(name), name);
    }
    for (const name of columns) assert.doesNotMatch(name, CONTACT, `iletisim sutunu olmamali: ${name}`);
    assert.ok(!/\bnote\b|\bnotes\b|comment|description/.test(columns.join(' ')), 'serbest not sutunu YOK');
    assert.ok(!/REFERENCES/i.test(table), 'tablo FK tasimaz');
    assert.match(sql('siteFk'), /FOREIGN KEY \(site_code\) REFERENCES sites\(site_code\) ON DELETE CASCADE/);
    assert.ok(!/users\(|apartments\(|site_people\(/.test(RESIDENCY_LOG_DDL.siteFk));
  });

  it('CHECK kumeleri: 10 olay turu, kod bicimi, iliski, rol, uzunluklar, donem, related sinirli', () => {
    const table = sql('logTable');
    assert.deepEqual(RESIDENCY_EVENT_TYPES, ['moved_in', 'moved_out', 'role_changed', 'admin_changed', 'link_cut_mutual', 'member_removed', 'member_left', 'access_suspended', 'access_lifted', 'handover']);
    for (const type of RESIDENCY_EVENT_TYPES) assert.ok(table.includes(`'${type}'`), type);
    assert.deepEqual(RESIDENCY_RELATIONS, ['owner', 'tenant', 'family_member', 'resident']);
    assert.deepEqual(RESIDENCY_ACTOR_ROLES, ['system', 'super_user', 'site_manager', 'apartment_admin', 'owner', 'tenant', 'resident']);
    for (const fragment of [
      "reason_code ~ '^[a-z][a-z0-9_]{1,39}$'",
      'char_length(subject_name) BETWEEN 1 AND 120',
      'char_length(actor_name) BETWEEN 1 AND 120',
      'char_length(apartment_label) BETWEEN 1 AND 80',
      'period_end >= period_start',
      "jsonb_typeof(related) = 'object' AND char_length(related::text) <= 600",
    ]) {
      assert.ok(table.includes(fragment), fragment);
    }
  });

  it('yalniz-ekleme islevi: UPDATE hic yapilamaz; DELETE yalniz sites satiri YOKSA (site silme CASCADE); TRUNCATE engelli', () => {
    const fn = sql('immutableFunction');
    assert.match(fn, /IF TG_OP = 'DELETE' THEN IF NOT EXISTS \(SELECT 1 FROM sites WHERE site_code = OLD\.site_code\) THEN RETURN OLD; END IF; END IF;/);
    assert.ok(!/RETURN NEW/.test(fn), 'UPDATE icin serbest yol yok');
    assert.match(fn, /RAISE EXCEPTION 'apartment residency log is append-only'; END; \$\$ LANGUAGE plpgsql$/);
    assert.match(sql('truncateFunction'), /RAISE EXCEPTION 'apartment residency log cannot be truncated';/);
    assert.match(sql('immutableTrigger'), /CREATE TRIGGER trg_apartment_residency_log_immutable BEFORE UPDATE OR DELETE ON apartment_residency_log FOR EACH ROW/);
    assert.match(sql('truncateTrigger'), /CREATE TRIGGER trg_apartment_residency_log_no_truncate BEFORE TRUNCATE ON apartment_residency_log FOR EACH STATEMENT/);
  });

  it('users kayit tetikleyicisi: silmeyi ENGELLEMEZ (hata uyariya cevrilir), iletisim bilgisi yazmaz, preserve tetikleyicisinden ONCE calisir (alfabetik)', () => {
    const fn = sql('usersFunction');
    assert.match(fn, /EXCEPTION WHEN OTHERS THEN RAISE WARNING/);
    assert.match(fn, /RETURN OLD;/);
    assert.doesNotMatch(fn, /phone|e_?mail|tckn/i);
    assert.match(sql('usersTrigger'), /CREATE TRIGGER trg_users_log_residencies BEFORE DELETE ON users FOR EACH ROW/);
    assert.ok('trg_users_log_residencies' < 'trg_users_preserve_site_people');
  });

  it('ensure: her sey varsa HICBIR DDL gonderilmez; eksikse yalniz eksikler sirayla calisir; users tetikleyicisi users var iken kurulur', async () => {
    const mk = (present, sent = []) => ({
      sent,
      async query(text) {
        if (/unnest/.test(text)) {
          return {
            rows: [
              {
                tables: present.tables ?? [],
                indexes: present.indexes ?? [],
                fks: present.fks ?? [],
                functions: present.functions ?? [],
                triggers: present.triggers ?? [],
              },
            ],
          };
        }
        sent.push(String(text));
        return { rows: [] };
      },
    });
    const full = {
      tables: ['apartment_residency_log', 'users'],
      indexes: ['idx_apartment_residency_log_apartment', 'idx_apartment_residency_log_site', 'idx_apartment_residency_log_subject'],
      fks: ['apartment_residency_log.apartment_residency_log_site_code_fkey'],
      functions: ['trg_apartment_residency_log_immutable', 'trg_apartment_residency_log_block_truncate', 'trg_users_log_residencies'],
      triggers: ['trg_apartment_residency_log_immutable', 'trg_apartment_residency_log_no_truncate', 'trg_users_log_residencies'],
    };
    const complete = mk(full);
    await ensureResidencyLogSchema(complete);
    assert.deepEqual(complete.sent, []);
    const partial = mk({ ...full, tables: ['users'], indexes: [], fks: [], functions: [], triggers: [] });
    await ensureResidencyLogSchema(partial);
    const ddl = partial.sent.filter((entry) => !/lock_timeout/.test(entry)).map(normalizeSql);
    assert.equal(ddl.length, 11);
    assert.deepEqual(ddl, RESIDENCY_LOG_DDL_ORDER.map((name) => normalizeSql(RESIDENCY_LOG_DDL[name])));
    const onlyUsersTrigger = mk({ ...full, triggers: ['trg_apartment_residency_log_immutable', 'trg_apartment_residency_log_no_truncate'] });
    await ensureResidencyLogSchema(onlyUsersTrigger);
    assert.equal(onlyUsersTrigger.sent.filter((entry) => /CREATE TRIGGER trg_users_log_residencies/.test(entry)).length, 1);
    assert.equal(onlyUsersTrigger.sent.filter((entry) => /CREATE (TABLE|INDEX)/.test(entry)).length, 0);
  });
});

// ---------------------------------------------------------------------------
// Yazma yardimcilari: olay turleri, anlik goruntu, gizlilik
// ---------------------------------------------------------------------------

function recordingClient(script = []) {
  const log = [];
  return {
    log,
    async query(text, params) {
      const statement = norm(text);
      log.push({ sql: statement, params: params ?? [] });
      for (const [pattern, result] of script) {
        if (pattern.test(statement)) return typeof result === 'function' ? result(statement, params) : result;
      }
      return ok();
    },
  };
}
const logInserts = (client) => client.log.filter((q) => /^INSERT INTO apartment_residency_log/.test(q.sql));
// INSERT_SQL parametreleri: 0 site, 1 daire, 2 olay, 3 neden, 4 iliski kaydi, 5 kisi, 6 kullanici, 7 iliski, 8 baslangic, 9 bitis, 10 ad, 11 yapan kodu, 12 yapan adi, 13 yapan rol, 14 related
const P = { site: 0, apartment: 1, event: 2, reason: 3, residency: 4, person: 5, user: 6, relation: 7, start: 8, end: 9, name: 10, actorCode: 11, actorName: 12, actorRole: 13, related: 14 };

describe('anlik goruntu gizliligi', () => {
  it('yazma SQL\'leri (tekil, toplu, esitleme CTE, hesap silme tetikleyicisi) iletisim sutununa DOKUNMAZ; ad yalniz full_name', () => {
    const syncLogs = SYNC_STEPS.map((step) => step.sql).flatMap((text) => [...text.matchAll(/INSERT INTO apartment_residency_log \(([^)]*)\)([\s\S]*?)RETURNING id/g)].map((m) => `${m[1]} ${m[2]}`));
    assert.equal(syncLogs.length, 3, 'insert_residencies + end_unbacked + deactivate_orphans');
    for (const text of [RESIDENCY_LOG_INSERT_SQL, RESIDENCY_LOG_BULK_INSERT_SQL, RESIDENCY_LOG_DDL.usersFunction, ...syncLogs]) {
      assert.doesNotMatch(text, /phone|e_?mail|tckn|tc_kimlik|identity|password|token/i);
    }
    assert.match(RESIDENCY_LOG_INSERT_SQL, /full_name/);
    // Donem bitisi NULL guvenli: acik (hala guncel) ilişki icin period_end NULL kalir, CHECK (period_end >= period_start) hicbir zaman ihlal edilmez.
    assert.match(RESIDENCY_LOG_INSERT_SQL, /CASE WHEN per\.pe IS NULL OR per\.ps IS NULL OR per\.pe >= per\.ps THEN per\.pe ELSE per\.ps END/);
    assert.match(RESIDENCY_LOG_BULK_INSERT_SQL, /CASE WHEN r\.move_out_date IS NULL OR r\.move_in_date IS NULL OR r\.move_out_date >= r\.move_in_date THEN r\.move_out_date ELSE r\.move_in_date END/);
  });

  it('sanitizeRelated: yalniz beyaz liste anahtarlari; sayi, boolean ve kisa kod kabul edilir; serbest metin / e-posta sizmaz', () => {
    assert.deepEqual(
      sanitizeRelated({ residency_id: 5, from_relation: 'tenant', to_relation: 'owner', auto: true, note: 'serbest', email: 'a@b.c', request_id: 'x y z', from_user_code: 'ali@example.com', to_user_code: 7 }),
      { residency_id: 5, from_relation: 'tenant', to_relation: 'owner', auto: true, to_user_code: 7 },
    );
    assert.deepEqual(sanitizeRelated(null), {});
  });

  it('logResidencyEvent: gecersiz olay / neden kodu reddedilir; iliski kumesi disi deger dusurulur; yapan yoksa SISTEM; related suzulur', async () => {
    const client = recordingClient();
    await assert.rejects(() => logResidencyEvent(client, { siteCode: 1, eventType: 'hacked', reasonCode: 'moved_out' }), /gecersiz olay/);
    await assert.rejects(() => logResidencyEvent(client, { siteCode: 1, eventType: 'moved_out', reasonCode: 'Serbest Metin!' }), /gecersiz neden/);
    await assert.rejects(() => logResidencyEvent(client, { eventType: 'moved_out', reasonCode: 'moved_out' }), /siteCode ya da apartmentId/);
    assert.equal(client.log.length, 0);
    await logResidencyEvent(client, { siteCode: 1000000001, apartmentId: 9, eventType: 'moved_out', reasonCode: 'moved_out', residencyId: 31, relation: 'ev_sahibi', related: { residency_id: 31, email: 'x@y.z' } });
    const [insert] = logInserts(client);
    assert.equal(insert.params[P.site], 1000000001);
    assert.equal(insert.params[P.relation], null);
    assert.equal(insert.params[P.actorRole], 'system');
    assert.equal(insert.params[P.actorCode], null);
    assert.equal(insert.params[P.related], JSON.stringify({ residency_id: 31 }));
  });

  it('actorForLog: sistem / super / site yoneticisi / bagiamdan rol; super kullanici her baglamda super_user', () => {
    assert.deepEqual(actorForLog(null), { userCode: null, name: null, role: 'system' });
    assert.equal(actorForLog({ id: 5, role: 'super_user', full_name: 'Süper' }, 'owner').role, 'super_user');
    assert.equal(actorForLog({ id: 6, role: 'site_manager', full_name: 'Ayşe Yönetici' }).role, 'site_manager');
    assert.deepEqual(actorForLog({ id: 7, role: 'apartment_owner', full_name: 'Can' }, 'tenant'), { userCode: 7, name: 'Can', role: 'tenant' });
    assert.equal(actorForLog({ id: 8, role: 'individual' }).role, 'resident');
  });

  it('logResidenciesBulk: tek kumesel ifade; bos liste ifade gondermez; gecersiz olay reddedilir', async () => {
    const client = recordingClient();
    await logResidenciesBulk(client, { ids: [], eventType: 'moved_in' });
    assert.equal(client.log.length, 0);
    await logResidenciesBulk(client, { ids: [4, 5, 'x'], eventType: 'moved_in', actorUserCode: 20001 });
    assert.equal(client.log.length, 1);
    assert.deepEqual(client.log[0].params, [[4, 5], 'moved_in', 'bulk_import', 20001, 'site_manager']);
    await assert.rejects(() => logResidenciesBulk(client, { ids: [1], eventType: 'nope' }), /gecersiz toplu olay/);
  });
});

describe('olay turleri ve neden kodlari', () => {
  it('closeLogFor: tum cikis yollarinin olay turu ve neden kodu', () => {
    assert.deepEqual(closeLogFor(null), { eventType: 'moved_out', reasonCode: 'moved_out' });
    assert.deepEqual(closeLogFor('person_deactivated'), { eventType: 'moved_out', reasonCode: 'site_manager' });
    assert.deepEqual(closeLogFor('tenant_exit'), { eventType: 'moved_out', reasonCode: 'handover' });
    assert.deepEqual(closeLogFor('tenant_left'), { eventType: 'member_left', reasonCode: 'self' });
    assert.deepEqual(closeLogFor('member_left'), { eventType: 'member_left', reasonCode: 'self' });
    assert.deepEqual(closeLogFor('disconnect_approved'), { eventType: 'link_cut_mutual', reasonCode: 'mutual' });
    assert.deepEqual(closeLogFor('family_removed_by_admin'), { eventType: 'member_removed', reasonCode: 'apartment_admin' });
    assert.deepEqual(closeLogFor('member_removal_consented'), { eventType: 'member_removed', reasonCode: 'consent' });
    assert.deepEqual(closeLogFor('bilinmeyen'), { eventType: 'moved_out', reasonCode: 'moved_out' });
  });

  it('closeResidency (merkezi kapatma): AYNI transaction\'da log satiri; kisi hesaptan koparilmadan ONCE; yapan ve neden kodu', async () => {
    const actor = { id: 20001, role: 'site_manager', full_name: 'Ayşe Yönetici' };
    for (const [reason, event, code] of [
      [null, 'moved_out', 'moved_out'],
      ['tenant_exit', 'moved_out', 'handover'],
      ['disconnect_approved', 'link_cut_mutual', 'mutual'],
      ['member_left', 'member_left', 'self'],
      ['family_removed_by_admin', 'member_removed', 'apartment_admin'],
    ]) {
      const client = recordingClient([
        [/^SELECT id, site_code, resident_user_code, resident_email FROM apartments/, ok([{ id: 9, resident_user_code: null, resident_email: null }])],
        [/^UPDATE apartment_residencies SET is_current = FALSE/, ok([{ id: 31 }])],
        [/^SELECT 1 FROM apartment_residencies WHERE person_id/, ok([{ x: 1 }])],
      ]);
      await closeResidency(client, {
        siteCode: 1000000001,
        residency: { id: 31, person_id: 5, apartment_id: 9, relation: 'tenant' },
        userCode: null,
        moveOutDate: '2026-10-22',
        actor,
        reason,
        actorRole: reason === 'member_left' ? 'tenant' : null,
      });
      const [insert] = logInserts(client);
      assert.ok(insert, `log satiri yazilmali (${reason})`);
      assert.equal(insert.params[P.event], event, String(reason));
      assert.equal(insert.params[P.reason], code, String(reason));
      assert.equal(insert.params[P.residency], 31);
      assert.equal(insert.params[P.apartment], 9);
      assert.equal(insert.params[P.end], '2026-10-22');
      assert.equal(insert.params[P.actorCode], 20001);
      assert.equal(insert.params[P.actorRole], reason === 'member_left' ? 'tenant' : 'site_manager');
      const order = client.log.map((q) => q.sql);
      assert.ok(order.findIndex((s) => /^UPDATE apartment_residencies/.test(s)) < order.findIndex((s) => /^INSERT INTO apartment_residency_log/.test(s)));
    }
  });

  it('closeResidency: kayit zaten bitmisse (409) log yazilmaz', async () => {
    const client = recordingClient([
      [/^SELECT id, site_code, resident_user_code, resident_email FROM apartments/, ok([{ id: 9 }])],
      [/^UPDATE apartment_residencies SET is_current = FALSE/, ok([])],
    ]);
    await assert.rejects(() => closeResidency(client, { siteCode: 1, residency: { id: 1, person_id: 2, apartment_id: 9, relation: 'resident' }, userCode: null, moveOutDate: '2026-10-22', actor: null }), (error) => error.code === 'RESIDENCY_NOT_CURRENT');
    assert.equal(logInserts(client).length, 0);
  });

  it('insertResidency (moved_in): kayit eklenince AYNI transaction\'da log; neden / yapan / rol', async () => {
    const client = recordingClient([[/^INSERT INTO apartment_residencies/, ok([{ id: '77' }])]]);
    const id = await insertResidency(client, { siteCode: 1000000001, apartmentId: 9, personId: 5, relation: 'tenant', moveInDate: '2026-10-22', actor: { id: 20003, role: 'apartment_owner', full_name: 'Can Sahip' }, actorRole: 'owner', reasonCode: 'invite_accepted' });
    assert.equal(id, 77);
    const [insert] = logInserts(client);
    assert.equal(insert.params[P.event], 'moved_in');
    assert.equal(insert.params[P.reason], 'invite_accepted');
    assert.equal(insert.params[P.residency], 77);
    assert.equal(insert.params[P.actorRole], 'owner');
  });

  it('applyApartmentPrimaryAdmin (admin_changed): eski yonetici kullanici kodu olay bagina yazilir; handOver (handover): eski ve yeni kod', async () => {
    const client = recordingClient([[/^UPDATE apartment_memberships SET role = 'FAMILY_MEMBER'/, ok([{ user_code: 20000 }])]]);
    await applyApartmentPrimaryAdmin(client, { apartmentId: 3, userCode: 20001, actor: { id: 1, role: 'super_user' }, reasonCode: 'site_manager' });
    const [admin] = logInserts(client);
    assert.equal(admin.params[P.event], 'admin_changed');
    assert.equal(admin.params[P.reason], 'site_manager');
    assert.equal(admin.params[P.user], 20001);
    assert.deepEqual(JSON.parse(admin.params[P.related]), { from_user_code: 20000, to_user_code: 20001 });
    assert.equal(admin.params[P.actorRole], 'super_user');

    const handover = recordingClient([[/AND is_active = TRUE AND role = 'APARTMENT_ADMIN'/, ok([{ user_code: 20002 }])]]);
    await handOverApartmentResident(handover, 3, 20000);
    const [row] = logInserts(handover);
    assert.equal(row.params[P.event], 'handover');
    assert.equal(row.params[P.reason], 'handover');
    assert.deepEqual(JSON.parse(row.params[P.related]), { from_user_code: 20000, to_user_code: 20002 });
  });

  it('10 olay turunun HEPSI bir kanca noktasinda uretilir (kapsam)', () => {
    const files = [
      'modules/residency_log.js',
      'modules/people_service.js',
      'modules/people_records.js',
      'modules/people_sync_sql.js',
      'modules/apartment_mgmt_service.js',
      'services/membership_service.js',
      'modules/account_deletion_service.js',
      'modules/bulk_import_writer.js',
      'modules/residency_log_schema.js',
    ].map(readSrc);
    const text = files.join('\n');
    for (const type of RESIDENCY_EVENT_TYPES) {
      assert.ok(new RegExp(`['"]${type}['"]`).test(files.filter((_, i) => i !== files.length - 1).join('\n')), `${type} icin kanca yok`);
    }
    assert.ok(text.includes('logResidencyEvent'));
  });

  it('kanca kapsami: cikis yollarinin her biri log yazar (kaynak)', () => {
    const people = readSrc('modules/people_service.js');
    assert.match(people, /async function closeResidency[\s\S]*?logResidencyEvent\(client, \{[\s\S]*?\.\.\.closeLogFor\(reason\)/);
    assert.match(people, /async function insertResidency[\s\S]*?eventType: 'moved_in'/);
    assert.match(people, /eventType: 'role_changed'/);
    const records = readSrc('modules/people_records.js');
    assert.match(records, /eventType: 'member_removed'/);
    const apt = readSrc('modules/apartment_mgmt_service.js');
    for (const reason of ['tenant_exit', 'tenant_left', 'member_left', 'disconnect_approved', 'family_removed_by_admin', 'member_removal_consented']) {
      assert.ok(apt.includes(`'${reason}'`) || apt.includes(`reason`), reason);
    }
    assert.match(apt, /eventType: 'member_left'[\s\S]*?reasonCode: 'self'/, 'malik / eski kayit kendi uyeligini kapatinca da log');
    const membership = readSrc('services/membership_service.js');
    assert.match(membership, /eventType: activeBool \? 'access_lifted' : 'access_suspended'/);
    assert.match(membership, /eventType: 'admin_changed'/);
    assert.match(membership, /eventType: 'handover'/);
    assert.match(membership, /endResidenciesForMemberRemoval\(client, \{[\s\S]*?logReason:/);
    const safety = readSrc('modules/apartment_mgmt_safety.js');
    assert.equal((safety.match(/reasonCode: 'suspension'/g) ?? []).length, 2, 'askiya alma ve kaldirma neden kodu suspension');
    const account = readSrc('modules/account_deletion_service.js');
    assert.match(account, /reasonCode: 'account_deleted'[\s\S]*?subjectName: loggedName/);
    const sync = SYNC_STEPS.find((step) => step.name === 'insert_residencies').sql;
    assert.match(sync, /INSERT INTO apartment_residency_log[\s\S]*'moved_in', 'sync'/);
    assert.match(SYNC_STEPS.find((step) => step.name === 'end_unbacked').sql, /INSERT INTO apartment_residency_log[\s\S]*'moved_out', 'sync'/);
    assert.match(SYNC_STEPS.find((step) => step.name === 'deactivate_orphans').sql, /INSERT INTO apartment_residency_log[\s\S]*'moved_out', 'account_deleted'/);
    const bulk = readSrc('modules/bulk_import_writer.js');
    assert.match(bulk, /logResidenciesBulk\(client, \{ ids: part\.map[\s\S]*?'role_changed'/);
    assert.match(bulk, /logResidenciesBulk\(client, \{ ids: inserted\.rows\.map[\s\S]*?'moved_in'/);
  });

  it('kapi / MQTT / BLE / firmware kodu adli kayit moduluyle ILGILI DEGIL (dokunulmadi)', () => {
    const touched = ['residency_log.js', 'residency_log_schema.js', 'residency_log_service.js', 'residency_log_routes.js', 'residency_log_export.js'];
    for (const name of touched) {
      const text = readSrc(`modules/${name}`).replace(/^\s*(\/\/|\*|\/\*).*$/gm, '');
      assert.doesNotMatch(text, /mqtt|firmware|door_guard|bluetooth|\.publish\(/i, name);
    }
    for (const dir of ['services', 'routes']) {
      for (const file of readdirSync(path.join(SRC, dir))) {
        if (/mqtt|door|firmware|device/i.test(file)) {
          assert.equal(readSrc(`${dir}/${file}`).includes('residency_log'), false, `${dir}/${file} adli kayit icermemeli`);
        }
      }
    }
  });
});

// ---------------------------------------------------------------------------
// Saklama anahtari
// ---------------------------------------------------------------------------

describe('saklama kurali', () => {
  it('retention.residency_log_days: 3650 gun varsayilan, sinirli, sitede degismez; otomatik silme kilidi (retention.enforce) aynen', () => {
    const rule = RULES['retention.residency_log_days'];
    assert.ok(rule);
    assert.equal(rule.defaultValue, 3650);
    assert.equal(rule.unit, 'days');
    assert.ok(rule.min <= 3650 && rule.max >= 3650);
    assert.equal(rule.siteOverridable, false);
    assert.match(rule.legalNote, /AVUKAT DOĞRULASIN/);
    assert.match(rule.legalNote, /KVKK m\.4\/2-d/);
    assert.equal(RULES['retention.enforce'].editable, false);
    assert.equal(RULES['retention.enforce'].defaultValue, false);
  });

  it('docs: PLATFORM_ADLI_KAYIT.md, PLATFORM_KURALLAR.md ve saklama taslagi anahtari anar; yasal sablonlara (server/legal) dokunulmadi', () => {
    const docs = path.join(here, '..', '..', 'docs');
    const adli = readFileSync(path.join(docs, 'PLATFORM_ADLI_KAYIT.md'), 'utf8');
    assert.match(adli, /apartment_residency_log/);
    assert.match(adli, /retention\.residency_log_days/);
    assert.match(readFileSync(path.join(docs, 'PLATFORM_KURALLAR.md'), 'utf8'), /retention\.residency_log_days/);
    const taslak = readFileSync(path.join(docs, 'yasal', 'SAKLAMA_SURELERI_TASLAGI.md'), 'utf8');
    assert.match(taslak, /retention\.residency_log_days/);
    assert.match(taslak, /AVUKAT DOĞRULASIN/);
    assert.equal(existsSync(path.join(here, '..', 'legal')), true);
  });
});

// ---------------------------------------------------------------------------
// Dokum olusturuculari
// ---------------------------------------------------------------------------

describe('adli bilgi dokumu: CSV ve PDF', () => {
  const doc = {
    title: 'Adli bilgi dökümü',
    meta: [
      ['Site', 'Güneş Sitesi'],
      ['Gerekçe', 'Mahkeme - dosya 2026/15'],
    ],
    columns: ['Tarih', 'Olay', 'Daire', 'Kişi', 'İlişki', 'Dönem', 'Neden', 'İşlemi yapan', 'Kaynak'],
    rows: [['2026-10-22 10:00', 'Taşındı (çıkış)', 'A Blok - 5', 'Şükrü Ağaç', 'Kiracı', '2025-01-01 - 2026-10-22', 'Devir', 'Site yöneticisi', 'Adli kayıt']],
  };

  it('csvCell: formul enjeksiyonu etkisiz, ayirici / tirnak kacislanir', () => {
    assert.equal(csvCell('=HYPERLINK("x")'), '"\'=HYPERLINK(""x"")"');
    assert.equal(csvCell('+90'), "'+90");
    assert.equal(csvCell('a;b'), '"a;b"');
    assert.equal(csvCell(null), '');
  });

  it('renderCsv: UTF-8 BOM, ust bilgi satirlari, sutun basliklari; iletisim bilgisi YOK', () => {
    const body = renderCsv(doc);
    assert.deepEqual([...body.subarray(0, 3)], [0xef, 0xbb, 0xbf]);
    const text = body.toString('utf8');
    assert.match(text, /Site;Güneş Sitesi/);
    assert.match(text, /Tarih;Olay;Daire;Kişi;İlişki;Dönem;Neden;İşlemi yapan;Kaynak/);
    assert.match(text, /Şükrü Ağaç/);
    assert.doesNotMatch(text, /@|telefon|tckn/i);
  });

  it('renderPdf: gecerli PDF (xref ofsetleri dogru), Turkce harfler /Differences ile eslenir, cok sayfa', () => {
    const pdf = renderPdf({ ...doc, rows: Array.from({ length: 80 }, (_, i) => [`2026-10-${String((i % 28) + 1).padStart(2, '0')} 10:00`, 'Taşındı (çıkış)', 'A Blok - 5', `Kişi ${i} Şükrü`, 'Kiracı', '', 'Devir', '', 'Adli kayıt']), footer: 'Alt not' });
    const text = pdf.toString('latin1');
    assert.ok(text.startsWith('%PDF-1.4'));
    assert.ok(text.trimEnd().endsWith('%%EOF'));
    assert.match(text, /\/Differences \[208 \/Gbreve 240 \/gbreve 222 \/Scedilla 254 \/scedilla 221 \/Idotaccent 253 \/dotlessi\]/);
    assert.ok(pdf.includes(Buffer.from([0xde])), 'Ş -> 0xDE'); // "Şükrü"
    const pages = (text.match(/\/Type \/Page /g) ?? []).length;
    assert.ok(pages >= 2, 'cok sayfa');
    const startxref = Number(/startxref\n(\d+)\n/.exec(text)[1]);
    assert.equal(text.slice(startxref, startxref + 4), 'xref');
    const entries = [...text.slice(startxref).matchAll(/^(\d{10}) 00000 n $/gm)].map((m) => Number(m[1]));
    entries.forEach((offset, index) => assert.equal(text.slice(offset, offset + `${index + 1} 0 obj`.length), `${index + 1} 0 obj`));
    assert.doesNotMatch(text, /@/);
  });

  it('parseExportRequest: gerekce kodu ve not ZORUNLU, bicim / tarih / daire dogrulanir', () => {
    const base = { reason_code: 'court', note: 'Mahkeme yazisi 2026/15' };
    assert.deepEqual(parseExportRequest(base), { format: 'pdf', reasonCode: 'court', note: 'Mahkeme yazisi 2026/15', apartmentId: null, from: null, to: null });
    assert.deepEqual(Object.keys(EXPORT_REASONS), ['official_request', 'law_enforcement', 'court', 'other']);
    const fails = (input, code) => assert.throws(() => parseExportRequest(input), (error) => error.code === code, JSON.stringify(input));
    fails({ note: 'yeterince uzun not' }, 'REASON_REQUIRED');
    fails({ reason_code: 'merak', note: 'yeterince uzun not' }, 'REASON_REQUIRED');
    fails({ reason_code: 'court' }, 'REASON_NOTE_REQUIRED');
    fails({ reason_code: 'court', note: 'kisa' }, 'REASON_NOTE_REQUIRED');
    fails({ ...base, note: 'x'.repeat(201) }, 'REASON_NOTE_REQUIRED');
    fails({ ...base, format: 'xlsx' }, 'INVALID_FORMAT');
    fails({ ...base, from: '2026-13-01' }, 'INVALID_DATE');
    fails({ ...base, from: '2026-10-05', to: '2026-10-01' }, 'INVALID_DATE_RANGE');
    fails({ ...base, apartment_id: 'abc' }, 'INVALID_APARTMENT');
    assert.equal(parseExportRequest({ ...base, format: 'CSV', apartment_id: '9', from: '2026-01-01', to: '2026-12-31' }).apartmentId, 9);
  });

  it('mapLogRow / mapLegacyRow: etiketli, kaynak etiketi (eski kayit), iletisim alani YOK', () => {
    const item = mapLogRow({ id: '4', occurred_at: new Date('2026-10-22T07:00:00Z'), apartment_id: '9', apartment_label: 'A Blok - 5', event_type: 'link_cut_mutual', reason_code: 'mutual', subject_name: 'Ali Veli', subject_relation: 'tenant', subject_person_id: '5', subject_user_code: 30001, period_start: '2025-01-01', period_end: '2026-10-22', actor_user_code: 20001, actor_name: 'Ayşe Yönetici', actor_role: 'site_manager', related: { residency_id: 31 } });
    assert.equal(item.event_label, 'Karşılıklı bağ kesme');
    assert.equal(item.reason_label, 'Karşılıklı onay');
    assert.equal(item.subject.relation_label, 'Kiracı');
    assert.equal(item.actor.role_label, 'Site yöneticisi');
    assert.equal(item.source, 'log');
    assert.doesNotMatch(JSON.stringify(item), /phone|email|tckn/i);
    const legacy = mapLegacyRow({ id: '31', apartment_id: '9', relation: 'owner', move_in_date: '2020-01-01', move_out_date: '2024-05-01', updated_at: new Date('2024-05-01T00:00:00Z'), person_id: '5', user_code: null, name: 'Eski Malik', unit_label: '5', block_name: 'A Blok' });
    assert.equal(legacy.source, 'legacy');
    assert.equal(legacy.source_label, 'Eski kayıt');
    assert.equal(legacy.apartment_label, 'A Blok - 5');
    assert.equal(legacy.period.end, '2024-05-01');
    assert.equal(legacy.id, -31);
  });
});

// ---------------------------------------------------------------------------
// Uclar: erisim matrisi, gerekce, audit
// ---------------------------------------------------------------------------

const SITE_1 = 1000000001;
const SITE_2 = 1000000002;
const mkUser = (id, role, name) => ({ id, user_code: id, userCode: id, role, full_name: name });
const users = {
  superUser: mkUser(1, 'super_user', 'Süper Kullanıcı'),
  mgrA: mkUser(20001, 'site_manager', 'Ayşe Yönetici'),
  mgrB: mkUser(20002, 'site_manager', 'Bora Yönetici'),
  resident: mkUser(20004, 'apartment_owner', 'Deniz Sakin'),
  newTenant: mkUser(20009, 'individual', 'Yeni Kiracı'),
  staff: mkUser(20005, 'individual', 'Ece Görevli'),
  board: mkUser(20006, 'individual', 'Fatma Kurul'),
  outsider: mkUser(20008, 'individual', 'Hakan İlgisiz'),
};

let db;
let server;
let baseUrl;

function makeDb() {
  return {
    sites: new Map([[SITE_1, 'Güneş Sitesi'], [SITE_2, 'Ay Sitesi']]),
    managers: [[SITE_1, 20001], [SITE_2, 20002]],
    memberships: [
      [SITE_1, 20005, 'STAFF'],
      [SITE_1, 20004, 'RESIDENT'],
      [SITE_1, 20009, 'RESIDENT'],
      [SITE_1, 20006, 'BOARD_MEMBER'],
    ],
    logRows: [
      { id: '12', site_code: SITE_1, occurred_at: new Date('2026-10-20T09:00:00Z'), apartment_id: '9', apartment_label: 'A Blok - 5', event_type: 'moved_out', reason_code: 'handover', subject_name: 'Eski Kiracı', subject_relation: 'tenant', subject_person_id: '5', subject_user_code: 30001, period_start: '2025-01-01', period_end: '2026-10-20', actor_user_code: 30001, actor_name: 'Eski Kiracı', actor_role: 'tenant', related: { residency_id: 31 } },
    ],
    legacyRows: [],
    auditFails: false,
    queries: [],
    audits: [],
  };
}

function handle(text, params) {
  const statement = norm(text);
  db.queries.push({ sql: statement, params });
  if (/^SELECT 1 FROM site_manager_sites WHERE site_code = \$1 AND manager_user_code = \$2 LIMIT 1$/.test(statement)) {
    return ok(db.managers.filter(([s, u]) => s === Number(params[0]) && u === Number(params[1])).map(() => ({ x: 1 })));
  }
  if (/^SELECT 1 FROM site_memberships WHERE site_code = \$1 AND user_code = \$2 AND role IN \('SITE_OWNER', 'SITE_ADMIN'\)/.test(statement)) return ok();
  if (/^SELECT EXISTS \( SELECT 1 FROM site_memberships WHERE site_code = \$1 AND user_code = \$2 AND role = 'BOARD_MEMBER'/.test(statement)) {
    const [site, user] = params.map(Number);
    const here = db.memberships.filter(([s, u]) => s === site && u === user);
    const otherRole = db.managers.some(([, u]) => u === user) || db.memberships.some(([, u, r]) => u === user && r === 'BOARD_MEMBER');
    return ok([{ is_board_here: here.some(([, , r]) => r === 'BOARD_MEMBER'), is_member_here: here.length > 0, has_other_role: otherRole }]);
  }
  if (/^SELECT site_code FROM sites WHERE site_code = \$1 LIMIT 1$/.test(statement)) return ok(db.sites.has(Number(params[0])) ? [{ site_code: String(params[0]) }] : []);
  if (/^SELECT name FROM sites WHERE site_code = \$1$/.test(statement)) return ok(db.sites.has(Number(params[0])) ? [{ name: db.sites.get(Number(params[0])) }] : []);
  if (/^SELECT a\.id, a\.unit_label, b\.block_name FROM apartments a/.test(statement)) {
    return Number(params[0]) === 9 && Number(params[1]) === SITE_1 ? ok([{ id: '9', unit_label: '5', block_name: 'A Blok' }]) : ok();
  }
  if (/^SELECT COUNT\(\*\)::INTEGER AS total FROM apartment_residency_log/.test(statement)) return ok([{ total: db.logRows.length }]);
  if (/^SELECT \* FROM apartment_residency_log/.test(statement)) return ok(db.logRows);
  if (/FROM apartment_residencies r INNER JOIN site_people sp ON sp\.id = r\.person_id LEFT JOIN users u/.test(statement)) return ok(db.legacyRows);
  if (/^INSERT INTO audit_log/.test(statement)) {
    if (db.auditFails) throw new Error('audit yazilamadi');
    db.audits.push({ params });
    return ok();
  }
  throw new Error(`BEKLENMEYEN SQL (sahte DB kati): ${statement.slice(0, 200)}`);
}

const ORIGINAL_ROUTES = residencyLogRouter.stack.filter((layer) => layer.route).map((layer) => ({
  path: layer.route.path,
  method: Object.keys(layer.route.methods)[0],
  handlers: layer.route.stack.map((entry) => entry.handle),
}));

before(async () => {
  for (const layer of residencyLogRouter.stack) {
    if (!layer.route) continue;
    layer.route.stack[0].handle = (req, _res, next) => {
      req.authUser = JSON.parse(decodeURIComponent(req.headers['x-test-user']));
      next();
    };
    layer.route.stack[1].handle = (_req, _res, next) => next();
  }
  const app = express();
  app.use(express.json());
  app.use(residencyLogRouter);
  await new Promise((resolve) => {
    server = app.listen(0, '127.0.0.1', resolve);
  });
  baseUrl = `http://127.0.0.1:${server.address().port}`;
});

after(async () => {
  server.closeAllConnections?.();
  await new Promise((resolve) => server.close(resolve));
  delete pool.query;
  delete pool.connect;
});

beforeEach(() => {
  db = makeDb();
  pool.query = async (text, params) => handle(text, params ?? []);
  mock.method(console, 'error', () => {});
});

afterEach(() => {
  mock.restoreAll();
});

async function call(method, urlPath, { user = users.mgrA, body } = {}) {
  const response = await fetch(`${baseUrl}${urlPath}`, {
    method,
    headers: { 'content-type': 'application/json', 'x-test-user': encodeURIComponent(JSON.stringify(user)) },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const buffer = Buffer.from(await response.arrayBuffer());
  let json = null;
  if ((response.headers.get('content-type') ?? '').includes('json')) json = JSON.parse(buffer.toString('utf8'));
  return { status: response.status, headers: response.headers, buffer, body: json };
}

const listPath = (site = SITE_1, apt = 9) => `/manager/sites/${site}/apartments/${apt}/residency-log`;
const exportPath = (site = SITE_1) => `/manager/sites/${site}/residency-log/export`;
const VALID = { reason_code: 'court', note: 'Mahkeme yazisi 2026/15 sayili dosya' };

describe('adli kayit uclari: zincir', () => {
  it('3 rota; hepsi authRequired + hiz siniri; dokum ucu GET ve POST, ozel dokum siniri (10/saat)', () => {
    const summary = ORIGINAL_ROUTES.map((r) => `${r.method.toUpperCase()} ${r.path}`).sort();
    assert.deepEqual(summary, [
      'GET /manager/sites/:siteCode/apartments/:apartmentId/residency-log',
      'GET /manager/sites/:siteCode/residency-log/export',
      'POST /manager/sites/:siteCode/residency-log/export',
    ]);
    for (const route of ORIGINAL_ROUTES) {
      assert.equal(route.handlers[0], authRequired);
      if (route.path.endsWith('/export')) assert.equal(route.handlers[1], exportLimiter);
    }
    assert.equal(typeof exportLimiter, 'function');
  });
});

describe('adli kayit uclari: erisim (YALNIZ site yoneticisi ve super kullanici)', () => {
  it('site yoneticisi ve super kullanici gorur; kayit etiketli, iletisim bilgisi YOK', async () => {
    for (const user of [users.mgrA, users.superUser]) {
      const res = await call('GET', listPath(), { user });
      assert.equal(res.status, 200, res.buffer.toString());
      assert.equal(res.headers.get('cache-control'), 'no-store');
      assert.equal(res.body.total, 1);
      assert.equal(res.body.label, 'A Blok - 5');
      assert.equal(res.body.items[0].event_label, 'Taşındı (çıkış)');
      assert.equal(res.body.items[0].subject.name, 'Eski Kiracı');
      assert.doesNotMatch(JSON.stringify(res.body), /phone|e_?mail|tckn|@/i);
    }
    assert.ok(db.audits.length >= 1, 'goruntuleme izi (residency_log.viewed)');
    assert.equal(db.audits[0].params[3], 'residency_log.viewed');
  });

  it('kurul, gorevli, sakin, YENI kiraci, ilgisiz kullanici ve BASKA sitenin yoneticisi 403 (liste ve dokum)', async () => {
    for (const [name, user] of Object.entries({ board: users.board, staff: users.staff, resident: users.resident, newTenant: users.newTenant, outsider: users.outsider, mgrB: users.mgrB })) {
      const list = await call('GET', listPath(), { user });
      assert.equal(list.status, 403, `liste ${name}`);
      assert.match(list.body.code, /^FORBIDDEN_(ROLE|SITE)$/);
      const exp = await call('POST', exportPath(), { user, body: { ...VALID, format: 'csv' } });
      assert.equal(exp.status, 403, `dokum ${name}`);
    }
    assert.equal((await call('GET', listPath(), { user: users.mgrB })).body.code, 'FORBIDDEN_SITE');
    assert.equal(db.audits.length, 0, 'yetkisiz istek audit/dokum uretmez');
  });

  it('baska sitenin dairesi: 404 APARTMENT_NOT_FOUND (varligi sizdirilmaz); kayit yok + daire yok', async () => {
    db.logRows = [];
    const res = await call('GET', listPath(SITE_1, 77));
    assert.equal(res.status, 404);
    assert.equal(res.body.code, 'APARTMENT_NOT_FOUND');
    assert.equal((await call('GET', listPath(1000000099, 9), { user: users.superUser })).status, 404);
  });

  it('log bos ise eski donem satirlari TUREYEN salt okunur satir olarak gorunur (kaynak: eski kayit)', async () => {
    db.logRows = [];
    db.legacyRows = [{ id: '31', apartment_id: '9', relation: 'owner', move_in_date: '2020-01-01', move_out_date: '2024-05-01', updated_at: new Date('2024-05-01T00:00:00Z'), person_id: '5', user_code: null, name: 'Eski Malik', unit_label: '5', block_name: 'A Blok' }];
    const res = await call('GET', listPath());
    assert.equal(res.status, 200);
    assert.equal(res.body.total, 0);
    assert.equal(res.body.items.length, 0);
    assert.equal(res.body.legacy_items.length, 1);
    assert.equal(res.body.legacy_items[0].source_label, 'Eski kayıt');
    assert.equal(res.body.legacy_items[0].subject.name, 'Eski Malik');
    // turetme sorgusu yalniz kapali iliskileri alir ve kayitli kapanislari tekrar etmez
    const legacy = db.queries.find((q) => /FROM apartment_residencies r INNER JOIN site_people sp/.test(q.sql));
    assert.match(legacy.sql, /r\.is_current = FALSE/);
    assert.match(legacy.sql, /NOT EXISTS \( SELECT 1 FROM apartment_residency_log l/);
    assert.doesNotMatch(legacy.sql, /sp\.phone|sp\.email|u\.email|phone_number/);
  });
});

describe('adli bilgi dokumu uclari', () => {
  it('gerekce kodu ya da not yoksa 400; kayit okunmaz, audit yazilmaz', async () => {
    for (const [body, code] of [
      [{ format: 'csv' }, 'REASON_REQUIRED'],
      [{ format: 'csv', reason_code: 'court' }, 'REASON_NOTE_REQUIRED'],
      [{ format: 'csv', reason_code: 'court', note: 'kisa' }, 'REASON_NOTE_REQUIRED'],
      [{ format: 'csv', reason_code: 'merak', note: 'yeterince uzun bir not' }, 'REASON_REQUIRED'],
    ]) {
      const res = await call('POST', exportPath(), { body });
      assert.equal(res.status, 400);
      assert.equal(res.body.code, code);
    }
    assert.equal(db.audits.length, 0);
    assert.equal(db.queries.filter((q) => /apartment_residency_log/.test(q.sql)).length, 0);
  });

  it('CSV: dosya + Content-Disposition; audit (kim, hangi daire, gerekce kodu + not, kayit sayisi) YAZILIR; iletisim bilgisi yok', async () => {
    const res = await call('POST', exportPath(), { body: { ...VALID, format: 'csv', apartment_id: 9 } });
    assert.equal(res.status, 200, res.buffer.toString());
    assert.match(res.headers.get('content-type'), /^text\/csv/);
    assert.match(res.headers.get('content-disposition'), /^attachment; filename="adli-bilgi-dokumu-1000000001-d9-\d{8}\.csv"$/);
    assert.equal(res.headers.get('x-content-type-options'), 'nosniff');
    assert.equal(res.headers.get('x-row-count'), '1');
    const text = res.buffer.toString('utf8');
    assert.match(text, /Daire;A Blok - 5/);
    assert.match(text, /Eski Kiracı/);
    assert.match(text, /Mahkeme - Mahkeme yazisi/);
    assert.doesNotMatch(text.split('\r\n').filter((line) => !line.startsWith('Not;')).join('\n'), /@|phone|telefon|e-posta|\d{10}/i);
    const audit = db.audits.find((a) => a.params[3] === 'residency_log.exported');
    assert.ok(audit, 'dokum audit satiri');
    assert.equal(audit.params[0], 20001, 'dokumu alan kullanici kodu');
    assert.equal(audit.params[4], SITE_1);
    assert.equal(audit.params[5], 'apartment');
    assert.equal(audit.params[6], '9');
    const details = JSON.parse(audit.params[7]);
    assert.deepEqual({ ...details, note: undefined }, { format: 'csv', reason_code: 'court', note: undefined, apartment_id: 9, from: null, to: null, row_count: 1, truncated: false });
    assert.match(details.note, /Mahkeme yazisi/);
  });

  it('PDF (varsayilan) ve GET sorgu dizesi de calisir; tum daireler icin hedef site', async () => {
    const res = await call('GET', `${exportPath()}?reason_code=law_enforcement&note=${encodeURIComponent('Kolluk yazisi no 44')}`, { user: users.superUser });
    assert.equal(res.status, 200, res.buffer.toString());
    assert.equal(res.headers.get('content-type'), 'application/pdf');
    assert.ok(res.buffer.subarray(0, 5).toString('latin1') === '%PDF-');
    const audit = db.audits.find((a) => a.params[3] === 'residency_log.exported');
    assert.equal(audit.params[5], 'site');
    assert.equal(audit.params[6], String(SITE_1));
  });

  it('audit yazilamazsa dokum VERILMEZ (503 AUDIT_UNAVAILABLE, govde dosya degil)', async () => {
    db.auditFails = true;
    const res = await call('POST', exportPath(), { body: { ...VALID, format: 'csv' } });
    assert.equal(res.status, 503);
    assert.equal(res.body.code, 'AUDIT_UNAVAILABLE');
    assert.ok(!res.buffer.toString('utf8').includes('Eski Kiracı'));
  });
});
