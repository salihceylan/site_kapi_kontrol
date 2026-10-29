// İş kaydı <-> firma (taşeron) yönlendirmesi (111), DB'siz KATI sahte veritabanıyla:
//  - şema: migration 111 <-> work_vendor_schema.js aynı SQL, ekleyici / idempotent, db.js sırası, katalog kontrolü (her şey varsa DDL yok);
//  - girdi: firma alanı doğrulaması (ad, yetkili, telefon, kuruş tutarı), durum geçiş kuralları, yanıt eşleyicisi (yönetim görünümünde var, sakinde yok);
//  - servis: "Firmaya yönlendir" (durum firmada + firma tek PATCH'te), yetki (görevli kapsamı, kurul 403), firmasız firmada 400, firmadaki işin firması silinemez 409.
// Gerçek PostgreSQL doğrulaması bu ortamda yapılamaz: SQL metni migration <-> modül eşitliği ve katı sahte ile sınanır; canlı provada 111 iki kez çalıştırılmalıdır.
import { describe, it, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { pool } from '../src/db.js';
import { DEFAULT_MIGRATIONS_DIR, findUnsafeStatements } from '../scripts/migrate.js';
import {
  STATUSES_WITH_VENDOR,
  WORK_VENDOR_STEPS,
  WORK_VENDOR_STEP_IDS,
  ensureWorkVendorSchema,
  workVendorMigrationSql,
  workVendorSchemaHooks,
} from '../src/modules/work_vendor_schema.js';
import {
  STAFF_TRANSITIONS,
  STATUSES,
  VENDOR_REFERRAL_FROM,
  isStaffTransitionAllowed,
  mapManagerItem,
  mapResidentItem,
  parsePatchInput,
  parseVendorInput,
} from '../src/modules/work_tracking_common.js';
import { updateWorkItem } from '../src/modules/work_tracking_service.js';

workVendorSchemaHooks.sleep = async () => {};

const here = path.dirname(fileURLToPath(import.meta.url));
const MIGRATION = readFileSync(path.join(DEFAULT_MIGRATIONS_DIR, '111_work_vendor_referral.sql'), 'utf8').replace(/\r\n/g, '\n');
const DB_SOURCE = readFileSync(path.join(here, '..', 'src', 'db.js'), 'utf8').replace(/\r\n/g, '\n');
const norm = (text) => String(text).replace(/\/\*[\s\S]*?\*\//g, ' ').replace(/--.*$/gm, ' ').replace(/\s+/g, ' ').trim();
const ok = (rows = []) => ({ rows, rowCount: rows.length });
const SITE = 1000000001;

// --- Şema --------------------------------------------------------------------------------------------------------------------------

describe('111 şeması: migration <-> modül, ekleyici, katalog kontrollü', () => {
  it('migration 111 gövdesi adımların birleşimidir (aynı SQL, aynı sıra); ekleyici ve idempotent; olay türü kısıtına dokunulmaz', () => {
    assert.ok(norm(MIGRATION).includes(norm(workVendorMigrationSql())));
    const positions = WORK_VENDOR_STEPS.map((step) => norm(MIGRATION).indexOf(norm(step.sql)));
    assert.ok(positions.every((position) => position >= 0));
    assert.deepEqual(positions, [...positions].sort((a, b) => a - b), 'adımlar migration içinde aynı sırada');
    for (const step of WORK_VENDOR_STEPS) {
      assert.doesNotMatch(step.sql, /\b(DROP TABLE|DROP COLUMN|TRUNCATE|DELETE FROM|UPDATE |INSERT INTO)\b/i, step.id);
      assert.match(step.sql, /IF NOT EXISTS/, step.id);
    }
    const drops = WORK_VENDOR_STEPS.filter((step) => /\bDROP\b/i.test(step.sql));
    assert.deepEqual(drops.map((step) => step.id), ['items:status_check']);
    assert.match(drops[0].sql, /DROP CONSTRAINT IF EXISTS chk_work_items_status;\s*ALTER TABLE work_items ADD CONSTRAINT chk_work_items_status/, 'DROP + ADD aynı DO bloğunda');
    assert.doesNotMatch(norm(MIGRATION), /chk_work_item_events_type/);
    assert.deepEqual(findUnsafeStatements(MIGRATION), []);
    assert.doesNotMatch(MIGRATION, /CONCURRENTLY/);
  });

  it('durum kümesi: DB kısıtı, STATUSES ile aynı; vendor CHECK NULL-güvenli (ad yoksa öteki alanlar boş); firmada ise ad dolu', () => {
    assert.deepEqual([...STATUSES_WITH_VENDOR], [...STATUSES]);
    const statusStep = WORK_VENDOR_STEPS.find((step) => step.id === 'items:status_check');
    for (const status of STATUSES) assert.ok(statusStep.sql.includes(`'${status}'`), status);
    const vendorStep = WORK_VENDOR_STEPS.find((step) => step.id === 'items:vendor_check');
    assert.match(vendorStep.sql, /vendor_name IS NOT NULL AND char_length\(vendor_name\) BETWEEN 2 AND 80/);
    assert.match(vendorStep.sql, /vendor_amount_kurus BETWEEN 0 AND 1000000000000/);
    const firmadaStep = WORK_VENDOR_STEPS.find((step) => step.id === 'items:firmada_vendor_check');
    assert.match(firmadaStep.sql, /CHECK \(status <> 'firmada' OR vendor_name IS NOT NULL\)/);
    const columns = WORK_VENDOR_STEPS.find((step) => step.id === 'items:vendor_columns').sql;
    for (const column of ['vendor_name TEXT', 'vendor_contact TEXT', 'vendor_phone TEXT', 'vendor_amount_kurus BIGINT', 'vendor_referred_at TIMESTAMPTZ']) {
      assert.ok(columns.includes(`ADD COLUMN IF NOT EXISTS ${column}`), column);
    }
    assert.doesNotMatch(columns, /NOT NULL|DEFAULT/, 'sütunlar boş başlar');
  });

  it('db.js ensureWorkVendorSchema\'yı 042 / 096 kurulumlarından SONRA çağırır', () => {
    const at = (needle) => DB_SOURCE.indexOf(needle);
    assert.ok(at('await ensureWorkVendorSchema(client)') > at('await ensureWorkTrackingSchema(client)'));
    assert.ok(at('await ensureWorkVendorSchema(client)') > at('await ensureWorkEquipmentSchema(client)'));
  });

  function fakeClient({ done = [], missingTables = [] } = {}) {
    const sent = [];
    return {
      sent,
      async query(sql) {
        if (/^SELECT .* AS g_work_items/.test(norm(sql))) {
          const row = { g_work_items: !missingTables.includes('work_items') };
          WORK_VENDOR_STEPS.forEach((step, index) => {
            row[`s${index}`] = done.includes(step.id);
          });
          return ok([row]);
        }
        sent.push(norm(sql));
        return ok();
      },
    };
  }

  it('her şey varsa hiçbir DDL / kilit ayarı gönderilmez; eksik adımlar sırayla uygulanır; tablo yoksa atlanır', async () => {
    const full = fakeClient({ done: WORK_VENDOR_STEP_IDS });
    assert.deepEqual(await ensureWorkVendorSchema(full), []);
    assert.deepEqual(full.sent, []);
    const partial = fakeClient({ done: ['items:vendor_columns', 'items:vendor_check'] });
    assert.deepEqual(await ensureWorkVendorSchema(partial), ['items:status_check', 'items:firmada_vendor_check']);
    assert.equal(partial.sent[0], "SET lock_timeout = '2s'");
    assert.equal(partial.sent.at(-1), 'RESET lock_timeout');
    assert.deepEqual(await ensureWorkVendorSchema(fakeClient()), WORK_VENDOR_STEP_IDS);
    assert.deepEqual(await ensureWorkVendorSchema(fakeClient({ missingTables: ['work_items'] })), []);
  });
});

// --- Girdi ve eşleyiciler ------------------------------------------------------------------------------------------------------------

describe('firma alanı doğrulaması ve durum kuralları', () => {
  const invalid = (fn) => assert.throws(fn, (error) => error.statusCode === 400 && error.code === 'INVALID_BODY');

  it('geçerli firma: ad kırpılır / tek satıra indirilir, yetkili ve telefon isteğe bağlı, tutar kuruş tam sayı; null firmayı kaldırır', () => {
    assert.deepEqual(parseVendorInput({ name: '  Ak   Asansör\nLtd. ', contact: ' Ali Bey ', phone: '0 (212) 555-12-34', amount_kurus: 125050 }), {
      name: 'Ak Asansör Ltd.',
      contact: 'Ali Bey',
      phone: '0 (212) 555-12-34',
      amountKurus: 125050,
    });
    assert.deepEqual(parseVendorInput({ name: 'Ak Asansör', contact: '  ', phone: '', amount_kurus: null }), { name: 'Ak Asansör', contact: null, phone: null, amountKurus: null });
    assert.equal(parseVendorInput({ name: 'Ak Asansör', amount_kurus: 0 }).amountKurus, 0);
    assert.equal(parseVendorInput(null), null);
    assert.deepEqual(parsePatchInput({ vendor: null }), { vendor: null });
    assert.deepEqual(parsePatchInput({ status: 'firmada', vendor: { name: 'Ak Asansör' } }).vendor.name, 'Ak Asansör');
  });

  it('geçersiz firma: ad yok / kısa / uzun, yetkili uzun, telefon harfli, tutar negatif / kesirli / metin / sınır üstü, nesne değil', () => {
    for (const bad of ['Ak', {}, { name: 5 }, { name: 'A' }, { name: 'x'.repeat(81) }, { name: 'Ak Asansör', contact: 'y'.repeat(81) }, { name: 'Ak Asansör', contact: 7 },
      { name: 'Ak Asansör', phone: 'arayın' }, { name: 'Ak Asansör', phone: '12' }, { name: 'Ak Asansör', phone: '1'.repeat(33) },
      { name: 'Ak Asansör', amount_kurus: -1 }, { name: 'Ak Asansör', amount_kurus: 10.5 }, { name: 'Ak Asansör', amount_kurus: '1000' }, { name: 'Ak Asansör', amount_kurus: 1_000_000_000_001 }, []]) {
      invalid(() => parseVendorInput(bad));
    }
    invalid(() => parsePatchInput({ vendor: 'Ak Asansör' }));
  });

  it('firmada yalnız yeni / işlemde / beklemede durumlarından girilir; çıkışları işlemde, beklemede, çözüldü, iptal; düz durum seçicisinde (STAFF_TRANSITIONS) firmada hedefi YOK', () => {
    assert.deepEqual([...VENDOR_REFERRAL_FROM], ['yeni', 'islemde', 'beklemede']);
    for (const from of VENDOR_REFERRAL_FROM) assert.equal(isStaffTransitionAllowed(from, 'firmada'), true, from);
    for (const from of ['cozuldu', 'kapandi', 'iptal']) assert.equal(isStaffTransitionAllowed(from, 'firmada'), false, from);
    assert.deepEqual([...STAFF_TRANSITIONS.firmada], ['islemde', 'beklemede', 'cozuldu', 'iptal']);
    for (const targets of Object.values(STAFF_TRANSITIONS)) assert.ok(!targets.includes('firmada'));
    assert.equal(isStaffTransitionAllowed('firmada', 'kapandi'), false, 'kapanış çözülmeden olmaz');
    assert.equal(isStaffTransitionAllowed('islemde', 'cozuldu'), true);
  });

  it('yanıt: yönetim görünümü firmayı taşır (yoksa null), sakin görünümü firmayı HİÇ taşımaz', () => {
    const base = { id: '5', site_code: String(SITE), category: 'ariza', location_type: 'ortak_alan', title: 'Kapı', description: 'D', status: 'firmada', priority: 'normal', created_at: new Date('2026-01-01T00:00:00Z') };
    const withVendor = mapManagerItem({ ...base, vendor_name: 'Ak Asansör', vendor_contact: 'Ali Bey', vendor_phone: '0212 555 12 34', vendor_amount_kurus: '125050', vendor_referred_at: new Date('2026-01-02T10:00:00Z') }, { kind: 'manager' });
    assert.deepEqual(withVendor.vendor, { name: 'Ak Asansör', contact: 'Ali Bey', phone: '0212 555 12 34', amount_kurus: 125050, referred_at: '2026-01-02T10:00:00.000Z' });
    assert.equal(mapManagerItem(base, { kind: 'board' }).vendor, null);
    const resident = mapResidentItem({ ...base, vendor_name: 'Ak Asansör', vendor_phone: '0212 555 12 34' });
    assert.equal(resident.status, 'firmada');
    assert.ok(!('vendor' in resident));
    assert.doesNotMatch(JSON.stringify(resident), /Ak Asansör|555/);
  });
});

// --- Servis: Firmaya yönlendir -------------------------------------------------------------------------------------------------------

describe('PATCH firmaya yönlendirme (sahte işlem)', () => {
  let state;
  let log;

  beforeEach(() => {
    log = [];
    state = { status: 'islemde', vendor: null, referredAt: null };
    const run = async (text, params = []) => {
      const sql = norm(text);
      log.push({ sql, params });
      if (/^SELECT site_code FROM sites WHERE site_code = \$1 FOR KEY SHARE$/.test(sql)) return ok([{ site_code: String(params[0]) }]);
      if (/^SELECT user_code FROM users WHERE user_code = \$1 AND deleted_at IS NULL FOR KEY SHARE$/.test(sql)) return ok([{ user_code: params[0] }]);
      if (/^SELECT w\.id, w\.status, w\.priority, w\.assigned_to, w\.equipment_id, /.test(sql) && /FOR UPDATE OF w$/.test(sql)) {
        const v = state.vendor;
        return ok([{ id: '5', status: state.status, priority: 'normal', assigned_to: null, equipment_id: null, due_date: null,
          vendor_name: v?.name ?? null, vendor_contact: v?.contact ?? null, vendor_phone: v?.phone ?? null, vendor_amount_kurus: v?.amountKurus === null || v === null ? null : String(v.amountKurus) }]);
      }
      if (/^UPDATE work_items SET /.test(sql)) {
        const value = (column) => {
          const match = new RegExp(`${column} = \\$(\\d+)`).exec(sql);
          return match ? params[Number(match[1]) - 1] : undefined;
        };
        if (value('status') !== undefined) state.status = value('status');
        if (value('vendor_name') !== undefined) {
          state.vendor = value('vendor_name') === null ? null : { name: value('vendor_name'), contact: value('vendor_contact'), phone: value('vendor_phone'), amountKurus: value('vendor_amount_kurus') };
        }
        if (/vendor_referred_at = NOW\(\)/.test(sql)) state.referredAt = new Date('2026-01-03T09:00:00Z');
        if (/vendor_referred_at = NULL/.test(sql)) state.referredAt = null;
        return ok();
      }
      if (/^INSERT INTO work_item_events/.test(sql)) return ok([{ id: '901' }]);
      if (/^(BEGIN|COMMIT|ROLLBACK|SAVEPOINT audit_insert|RELEASE SAVEPOINT audit_insert)$/.test(sql)) return ok();
      if (/^INSERT INTO audit_log/.test(sql)) return ok();
      if (/^SELECT w\.id, w\.site_code, w\.category, .* FROM work_items w (?:LEFT JOIN work_categories wc .* )?LEFT JOIN apartments a/.test(sql)) {
        const v = state.vendor;
        return ok([{ id: '5', site_code: String(SITE), category: 'ariza', location_type: 'ortak_alan', title: 'Kapı', description: 'D', status: state.status, priority: 'normal', resident_urgent: false, created_by: 4001, requester_name: 'Ayşe',
          vendor_name: v?.name ?? null, vendor_contact: v?.contact ?? null, vendor_phone: v?.phone ?? null, vendor_amount_kurus: v?.amountKurus ?? null, vendor_referred_at: state.referredAt,
          created_at: new Date('2026-01-01T00:00:00Z'), updated_at: new Date('2026-01-01T00:00:00Z'), attachment_count: 0 }]);
      }
      if (/^SELECT e\.id, e\.event_type, e\.visibility, /.test(sql)) {
        const events = log.filter((entry) => /^INSERT INTO work_item_events/.test(entry.sql)).map((entry, index) => ({ id: String(901 + index), event_type: entry.params[2], visibility: entry.params[3], actor_user_code: entry.params[4], actor_kind: entry.params[5], from_value: entry.params[6], to_value: entry.params[7], body: null, created_at: new Date('2026-01-02T00:00:00Z'), actor_name: 'Yönetici' }));
        return ok(events.reverse());
      }
      if (/^SELECT a\.id, a\.work_item_id/.test(sql)) return ok();
      throw new Error(`BEKLENMEYEN SQL (sahte DB katı): ${sql.slice(0, 220)}`);
    };
    pool.connect = async () => ({ query: (text, params) => run(text, params), release() {} });
    pool.query = async (text, params) => run(text, params);
  });
  after(() => {
    delete pool.query;
    delete pool.connect;
  });

  const actor = { user_code: 20001, role: 'site_manager', full_name: 'Yönetici' };
  const manager = { kind: 'manager', userCode: 20001, siteCode: SITE, canManage: true };
  const staff = { kind: 'staff', userCode: 20005, siteCode: SITE, canManage: false };
  const board = { kind: 'board', userCode: 20006, siteCode: SITE, canManage: false };
  const patch = (body, access = manager) => updateWorkItem({ siteCode: SITE, rawId: '5', actor, access, body });
  const sqls = () => log.map((entry) => entry.sql);
  const writes = () => sqls().filter((sql) => /^UPDATE work_items|^INSERT INTO work_item_events|^INSERT INTO audit_log/.test(sql));
  const audits = () => log.filter((entry) => /^INSERT INTO audit_log/.test(entry.sql)).map((entry) => ({ action: entry.params[3], details: JSON.parse(entry.params[7]) }));
  const eventInserts = () => log.filter((entry) => /^INSERT INTO work_item_events/.test(entry.sql));
  const vendorBody = { name: 'Ak Asansör', contact: 'Ali Bey', phone: '0212 555 12 34', amount_kurus: 125050 };

  it('Firmaya yönlendir: durum firmada + firma tek PATCH\'te yazılır; sakin okunmamış işaretlenir; status_changed olayı + iki denetim satırı; denetim firma bilgisi TAŞIMAZ', async () => {
    const detail = await patch({ status: 'firmada', vendor: vendorBody });
    const update = log.find((entry) => /^UPDATE work_items SET /.test(entry.sql));
    assert.match(update.sql, /status = \$3/);
    assert.match(update.sql, /vendor_name = \$\d+, vendor_contact = \$\d+, vendor_phone = \$\d+, vendor_amount_kurus = \$\d+/);
    assert.match(update.sql, /vendor_referred_at = NOW\(\)/);
    assert.match(update.sql, /resident_updated_at/);
    assert.deepEqual(eventInserts().map((entry) => entry.params.slice(2, 8)), [['status_changed', 'public', 20001, 'manager', 'islemde', 'firmada']]);
    assert.deepEqual(audits().map((entry) => entry.action), ['work_item.status_changed', 'work_item.updated']);
    assert.deepEqual(audits()[1].details, { field: 'vendor', change: 'set' });
    assert.doesNotMatch(JSON.stringify(audits()), /Ak Asans|0212|125050/);
    assert.equal(detail.item.status, 'firmada');
    assert.deepEqual(detail.item.vendor, { name: 'Ak Asansör', contact: 'Ali Bey', phone: '0212 555 12 34', amount_kurus: 125050, referred_at: '2026-01-03T09:00:00.000Z' });
    assert.deepEqual(detail.next_statuses, ['islemde', 'beklemede', 'cozuldu', 'iptal'], 'firmadan çıkış seçenekleri; düz seçicide firmada hedefi yok');
  });

  it('firmasız firmaya yönlendirme 400 INVALID_BODY: işlem geri alınır, hiçbir şey yazılmaz', async () => {
    await assert.rejects(patch({ status: 'firmada' }), (error) => error.statusCode === 400 && error.code === 'INVALID_BODY' && /firma adını girin/.test(error.message));
    assert.ok(sqls().includes('ROLLBACK'));
    assert.deepEqual(writes(), []);
    assert.equal(state.status, 'islemde');
  });

  it('işte zaten firma varsa (ör. firmadan dönen iş) firma gönderilmeden yeniden yönlendirilir; yönlendirme zamanı yenilenir', async () => {
    state.status = 'beklemede';
    state.vendor = { name: 'Ak Asansör', contact: null, phone: null, amountKurus: null };
    const detail = await patch({ status: 'firmada' });
    assert.equal(detail.item.status, 'firmada');
    assert.equal(detail.item.vendor.name, 'Ak Asansör');
    const update = log.find((entry) => /^UPDATE work_items SET /.test(entry.sql));
    assert.doesNotMatch(update.sql, /vendor_name =/, 'firma aynı: yeniden yazılmaz');
    assert.match(update.sql, /vendor_referred_at = NOW\(\)/);
  });

  it('çözülmüş / kapanmış iş firmaya yönlendirilemez: cozuldu 409 INVALID_TRANSITION, kapandi 409 WORK_ITEM_CLOSED', async () => {
    state.status = 'cozuldu';
    await assert.rejects(patch({ status: 'firmada', vendor: vendorBody }), { statusCode: 409, code: 'INVALID_TRANSITION' });
    state.status = 'kapandi';
    await assert.rejects(patch({ status: 'firmada', vendor: vendorBody }), { statusCode: 409, code: 'WORK_ITEM_CLOSED' });
    assert.deepEqual(writes(), []);
  });

  it('firmadaki işin firması silinemez (409 WORK_ITEM_VENDOR_REQUIRED); durumla birlikte kaldırılabilir; firmadan çıkışta firma kayıt olarak kalır', async () => {
    state.status = 'firmada';
    state.vendor = { name: 'Ak Asansör', contact: null, phone: null, amountKurus: null };
    await assert.rejects(patch({ vendor: null }), { statusCode: 409, code: 'WORK_ITEM_VENDOR_REQUIRED' });
    assert.deepEqual(writes(), []);
    const out = await patch({ status: 'cozuldu' });
    assert.equal(out.item.status, 'cozuldu');
    assert.equal(out.item.vendor.name, 'Ak Asansör', 'çıkışta firma kaydı kalır');
    log.length = 0;
    state.status = 'firmada';
    const cleared = await patch({ status: 'islemde', vendor: null });
    assert.equal(cleared.item.vendor, null);
    const update = log.find((entry) => /^UPDATE work_items SET /.test(entry.sql));
    assert.match(update.sql, /vendor_referred_at = NULL/);
  });

  it('yalnız firma bilgisi değişirse (tutar girildi): olay yazılmaz, sakin okunmamış işaretlenmez, denetim türü "updated"; aynı bilgi sessiz 200', async () => {
    state.status = 'firmada';
    state.vendor = { name: 'Ak Asansör', contact: null, phone: null, amountKurus: null };
    const detail = await patch({ vendor: { name: 'Ak Asansör', amount_kurus: 99900 } });
    const update = log.find((entry) => /^UPDATE work_items SET /.test(entry.sql));
    assert.doesNotMatch(update.sql, /resident_updated_at|status =|vendor_referred_at/);
    assert.deepEqual(eventInserts(), []);
    assert.deepEqual(audits(), [{ action: 'work_item.updated', details: { field: 'vendor', change: 'updated' } }]);
    assert.equal(detail.item.vendor.amount_kurus, 99900);
    log.length = 0;
    await patch({ vendor: { name: 'Ak Asansör', amount_kurus: 99900 } });
    assert.deepEqual(writes(), []);
  });

  it('görevli de yönlendirebilir (kapsam kilit sorgusunun içinde); kurul 403 ve veritabanına hiç gidilmez; geçersiz firma 400 ve veritabanına gidilmez', async () => {
    const detail = await patch({ status: 'firmada', vendor: vendorBody }, staff);
    assert.equal(detail.item.status, 'firmada');
    assert.equal(eventInserts()[0].params[5], 'staff');
    assert.match(log.find((entry) => /FOR UPDATE OF w$/.test(entry.sql)).sql, /w\.assigned_to IS NULL OR w\.assigned_to = \$3/);
    log.length = 0;
    await assert.rejects(patch({ status: 'firmada', vendor: vendorBody }, board), { statusCode: 403, code: 'FORBIDDEN_ROLE' });
    await assert.rejects(patch({ status: 'firmada', vendor: { name: 'A' } }), { statusCode: 400, code: 'INVALID_BODY' });
    assert.deepEqual(log, []);
  });
});
