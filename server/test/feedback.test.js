// Geri bildirim (103; sayfa bağlamlı, K11; DB'siz): migration 103 <-> feedback_schema.js aynı DDL, ekleyici / idempotent, katalog kontrollü ensure, girdi doğrulama
// (adet / dosya / toplam sınırları 400), rota zinciri (KATI sahte DB: ekran bağlamı kayda girer, rol sunucuda türetilir, yetkisiz listeleme 403), ham gövde yükleme +
// indirme (gerçek geçici dosya sistemi) ve bakım turu. Gerçek PostgreSQL doğrulaması bu pakette yapılmadı (bkz. teslim notu).
import { describe, it, before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import express from 'express';
import { promises as fsp, readFileSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { DEFAULT_MIGRATIONS_DIR, findUnsafeStatements, listMigrations } from '../scripts/migrate.js';
import { pool } from '../src/db.js';
import { FEEDBACK_DDL, FEEDBACK_DDL_ORDER, ensureFeedbackSchema, schemaTuning } from '../src/modules/feedback_schema.js';
import {
  FEEDBACK_ATTACHMENT_MAX_BYTES,
  FEEDBACK_MAX_ATTACHMENTS,
  FEEDBACK_MESSAGE_MAX,
  FEEDBACK_SUBTREE,
  FEEDBACK_TOTAL_MAX_BYTES,
  mapFeedback,
  parseDeclaredAttachments,
  parseFeedbackInput,
  parseListQuery,
} from '../src/modules/feedback_common.js';
import { feedbackRouter } from '../src/modules/feedback_routes.js';
import { feedbackUploadState } from '../src/modules/feedback_upload.js';
import { cleanStaleFeedbackUploads } from '../src/modules/feedback_maintenance.js';
import { runDocumentsMaintenanceOnce } from '../src/modules/document_maintenance.js';
import { pathForKey, resetStorageCheck } from '../src/modules/document_storage.js';

schemaTuning.retryDelayMs = 1;

const here = path.dirname(fileURLToPath(import.meta.url));
const MIGRATION = readFileSync(path.join(DEFAULT_MIGRATIONS_DIR, '103_feedback.sql'), 'utf8').replace(/\r\n/g, '\n');
const DB_SOURCE = readFileSync(path.join(here, '..', 'src', 'db.js'), 'utf8').replace(/\r\n/g, '\n');
const MB = 1048576;

function normalizeSql(text) {
  return text.replace(/\/\*[\s\S]*?\*\//g, ' ').replace(/--.*$/gm, ' ').replace(/\s+/g, ' ').trim();
}

/** Migration metnini üst düzey ifadelere böler ($$ gövdelerindeki ';' sayılmaz). */
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

const FK_RE = /^DO \$\$ BEGIN IF NOT EXISTS \( SELECT 1 FROM pg_constraint WHERE conname = '(\w+_fkey)' AND conrelid = '(\w+)'::regclass \) THEN ALTER TABLE (\w+) ADD CONSTRAINT (\w+_fkey) FOREIGN KEY \((\w+)\) REFERENCES (\w+)\((\w+)\) ON DELETE (CASCADE|SET NULL); END IF; END \$\$$/;

// --- migration ve şema --------------------------------------------------------------------------------------------------

describe('migration 103: geri bildirim', () => {
  it('103 var, çalıştırıcı için güvenli (üst düzey BEGIN/COMMIT yok), numara yinelenmez', () => {
    const list = listMigrations(DEFAULT_MIGRATIONS_DIR);
    const entry = list.find((m) => m.number === 103);
    assert.ok(entry, '103 numaralı migration yok');
    assert.equal(entry.file, '103_feedback.sql');
    assert.equal(list.filter((m) => m.number === 103).length, 1);
    assert.deepEqual(findUnsafeStatements(MIGRATION), []);
  });

  it('FEEDBACK_DDL migration 103 ile AYNI ifadeleri taşır (yorumlar ve boşluklar dışında birebir, AYNI sırayla)', () => {
    const fromMigration = splitStatements(MIGRATION);
    assert.equal(fromMigration.length, 10);
    assert.deepEqual(fromMigration, FEEDBACK_DDL_ORDER.map((name) => normalizeSql(FEEDBACK_DDL[name])));
    assert.deepEqual(Object.keys(FEEDBACK_DDL), [...FEEDBACK_DDL_ORDER]);
  });

  it('EKLEMELİ ve idempotent: CREATE TABLE / INDEX IF NOT EXISTS ve katalog korumalı FK; DROP / UPDATE / DELETE / INSERT YOK; ALTER yalnız iki yeni tabloya', () => {
    const statements = splitStatements(MIGRATION);
    for (const statement of statements) {
      assert.ok(/^CREATE (UNIQUE )?(TABLE|INDEX) IF NOT EXISTS /.test(statement) || FK_RE.test(statement), statement.slice(0, 120));
    }
    const all = normalizeSql(MIGRATION);
    assert.ok(!/\b(DROP|TRUNCATE|UPDATE|DELETE FROM|INSERT INTO)\b/i.test(all));
    assert.deepEqual([...new Set(all.match(/ALTER TABLE (\w+)/g))].sort(), ['ALTER TABLE feedback_attachments', 'ALTER TABLE feedback_reports']);
  });

  it('tablolar: ekran bağlamı sütunları, rol, CHECK kümeleri (5 MB dosya, 3 mime, durum <-> ready_at); satır içi REFERENCES yok; FK silme politikaları', () => {
    const reports = normalizeSql(FEEDBACK_DDL.reportsTable);
    for (const fragment of ['site_code BIGINT,', 'user_code INTEGER,', 'role TEXT NOT NULL', 'screen_name TEXT NOT NULL', 'screen_route TEXT NOT NULL', 'message TEXT NOT NULL', 'BETWEEN 1 AND 2000']) {
      assert.ok(reports.includes(fragment), fragment);
    }
    assert.equal(/REFERENCES/.test(reports), false);
    const attachments = normalizeSql(FEEDBACK_DDL.attachmentsTable);
    for (const fragment of ["mime_type IN ('image/jpeg', 'image/png', 'image/webp')", 'size_bytes BETWEEN 1 AND 5242880', "status IN ('uploading', 'ready')", "(status = 'ready') = (ready_at IS NOT NULL)", "status TEXT NOT NULL DEFAULT 'uploading'"]) {
      assert.ok(attachments.includes(fragment), fragment);
    }
    assert.equal(/REFERENCES/.test(attachments), false);
    const fks = splitStatements(MIGRATION).filter((s) => FK_RE.test(s)).map((s) => s.match(FK_RE));
    assert.deepEqual(
      fks.map((m) => `${m[3]}.${m[5]}->${m[6]}(${m[7]}) ${m[8]}`),
      ['feedback_reports.site_code->sites(site_code) CASCADE', 'feedback_reports.user_code->users(user_code) SET NULL', 'feedback_attachments.feedback_id->feedback_reports(id) CASCADE'],
    );
  });

  it('AÇILIŞ 40P01 dersi: DDL dev blokta DEĞİL; db.js ensureFeedbackSchema(client) çağırır, ensureFinanceFundsSchema\'dan SONRA, people_v1\'den ÖNCE', () => {
    const normalizedDb = normalizeSql(DB_SOURCE);
    for (const name of FEEDBACK_DDL_ORDER) {
      assert.equal(normalizedDb.includes(normalizeSql(FEEDBACK_DDL[name])), false, `${name} db.js içinde olmamalı`);
    }
    assert.equal(/CREATE TABLE IF NOT EXISTS feedback_reports\b/.test(DB_SOURCE), false);
    assert.match(DB_SOURCE, /import \{ ensureFeedbackSchema \} from '\.\/modules\/feedback_schema\.js';/);
    const calls = [...DB_SOURCE.matchAll(/await ensureFeedbackSchema\(client\);/g)];
    assert.equal(calls.length, 1);
    assert.ok(calls[0].index > DB_SOURCE.indexOf('await ensureFinanceFundsSchema(client);'));
    assert.ok(calls[0].index < DB_SOURCE.indexOf('await runPeopleBackfill(client);'));
  });
});

describe('ensureFeedbackSchema (sahte istemci): katalog kontrolü', () => {
  function client(catalog) {
    const log = [];
    return {
      log,
      query: async (text) => {
        const sql = normalizeSql(text);
        log.push(sql);
        if (/^SELECT ARRAY\(/.test(sql)) return { rows: [catalog] };
        return { rows: [] };
      },
    };
  }

  it('her şey varsa HİÇ DDL gitmez (normal açılış: tek katalog sorgusu, kilit yok)', async () => {
    const present = {
      tables: ['feedback_reports', 'feedback_attachments'],
      indexes: ['idx_feedback_reports_site', 'idx_feedback_reports_user_created', 'idx_feedback_attachments_feedback', 'idx_feedback_attachments_uploading', 'uq_feedback_attachments_storage_key'],
      fks: ['feedback_reports.feedback_reports_site_code_fkey', 'feedback_reports.feedback_reports_user_code_fkey', 'feedback_attachments.feedback_attachments_feedback_id_fkey'],
    };
    const c = client(present);
    await ensureFeedbackSchema(c);
    assert.equal(c.log.length, 1);
  });

  it('boş veritabanında 10 ifade AYNI sırayla çalışır (lock_timeout sarmalıyla)', async () => {
    const c = client({ tables: [], indexes: [], fks: [] });
    await ensureFeedbackSchema(c);
    const ddl = c.log.slice(1).filter((sql) => !/lock_timeout/i.test(sql));
    assert.deepEqual(ddl, FEEDBACK_DDL_ORDER.map((name) => normalizeSql(FEEDBACK_DDL[name])));
    assert.ok(c.log.some((sql) => /SET lock_timeout/.test(sql)));
    assert.ok(c.log.some((sql) => /RESET lock_timeout/.test(sql)));
  });

  it('yalnız eksikler çalışır: tablolar varsa tablo ifadesi gitmez, eksik indeks eklenir', async () => {
    const c = client({
      tables: ['feedback_reports', 'feedback_attachments'],
      indexes: ['idx_feedback_reports_site'],
      fks: ['feedback_reports.feedback_reports_site_code_fkey', 'feedback_reports.feedback_reports_user_code_fkey', 'feedback_attachments.feedback_attachments_feedback_id_fkey'],
    });
    await ensureFeedbackSchema(c);
    const ddl = c.log.slice(1).filter((sql) => !/lock_timeout/i.test(sql));
    assert.equal(ddl.length, 4);
    assert.ok(ddl.every((sql) => /^CREATE (UNIQUE )?INDEX IF NOT EXISTS /.test(sql)));
  });
});

// --- saf doğrulama --------------------------------------------------------------------------------------------------------

const att = (size, overrides = {}) => ({ file_name: 'ekran.jpg', mime_type: 'image/jpeg', size_bytes: size, ...overrides });
const validBody = (overrides = {}) => ({ message: 'Menü karışık görünüyor.', screen_name: 'Talepler', screen_route: 'menu/talepler', ...overrides });

describe('girdi doğrulama: K11 sınırları (4 dosya x 5 MB, toplam 20 MB) ve ekran bağlamı', () => {
  it('sınırlar K11 ile aynı ve birbiriyle tutarlı: 4 dosya, dosya başı 5 MB, toplam 20 MB', () => {
    assert.equal(FEEDBACK_MAX_ATTACHMENTS, 4);
    assert.equal(FEEDBACK_ATTACHMENT_MAX_BYTES, 5 * MB);
    assert.equal(FEEDBACK_TOTAL_MAX_BYTES, 20 * MB);
    assert.equal(FEEDBACK_MAX_ATTACHMENTS * FEEDBACK_ATTACHMENT_MAX_BYTES, FEEDBACK_TOTAL_MAX_BYTES);
  });

  it('5 dosya 400 FEEDBACK_TOO_MANY_ATTACHMENTS; tam 4 dosya kabul', () => {
    assert.throws(() => parseDeclaredAttachments([att(1), att(1), att(1), att(1), att(1)]), { statusCode: 400, code: 'FEEDBACK_TOO_MANY_ATTACHMENTS' });
    assert.equal(parseDeclaredAttachments([att(1), att(1), att(1), att(1)]).length, 4);
  });

  it('dosya 5 MB + 1 bayt 400 FEEDBACK_ATTACHMENT_TOO_LARGE; tam 5 MB kabul; dört tam 5 MB (toplam tam 20 MB) kabul', () => {
    assert.throws(() => parseDeclaredAttachments([att(5 * MB + 1)]), { statusCode: 400, code: 'FEEDBACK_ATTACHMENT_TOO_LARGE' });
    assert.equal(parseDeclaredAttachments([att(5 * MB)]).length, 1);
    const four = parseDeclaredAttachments([att(5 * MB), att(5 * MB), att(5 * MB), att(5 * MB)]);
    assert.equal(four.reduce((sum, item) => sum + item.sizeBytes, 0), 20 * MB);
  });

  it('tür dışı 400 FEEDBACK_ATTACHMENT_TYPE_NOT_ALLOWED; boş / negatif / kesirli boyut 400 INVALID_BODY; liste değil 400; ad zorunlu; uzantı bildirilen türden gelir', () => {
    assert.throws(() => parseDeclaredAttachments([att(10, { mime_type: 'application/pdf' })]), { statusCode: 400, code: 'FEEDBACK_ATTACHMENT_TYPE_NOT_ALLOWED' });
    for (const size of [0, -5, 1.5, '12', null]) {
      assert.throws(() => parseDeclaredAttachments([att(size)]), { statusCode: 400, code: 'INVALID_BODY' }, String(size));
    }
    assert.throws(() => parseDeclaredAttachments('x'), { statusCode: 400, code: 'INVALID_BODY' });
    assert.throws(() => parseDeclaredAttachments([att(5, { file_name: '   ' })]), { statusCode: 400, code: 'INVALID_BODY' });
    const [one] = parseDeclaredAttachments([att(5, { file_name: 'foto.png', mime_type: 'image/jpeg' })]);
    assert.equal(one.fileName, 'foto.jpg');
    assert.deepEqual(parseDeclaredAttachments(undefined), []);
  });

  it('parseFeedbackInput: ekran adı + rota zorunlu ve kayda girer; metin temizlenir; site_code / sürüm / platform isteğe bağlı', () => {
    const input = parseFeedbackInput(validBody({ site_code: 1000000001, app_version: '1.2.3+4', platform: 'Android', message: '  Merhaba​ dünya  ' }));
    assert.deepEqual(
      { message: input.message, screenName: input.screenName, screenRoute: input.screenRoute, siteCode: input.siteCode, appVersion: input.appVersion, platform: input.platform },
      { message: 'Merhaba dünya', screenName: 'Talepler', screenRoute: 'menu/talepler', siteCode: 1000000001, appVersion: '1.2.3+4', platform: 'android' },
    );
    assert.equal(parseFeedbackInput(validBody({ platform: 'playstation' })).platform, null, 'bilinmeyen platform atılır');
    assert.equal(parseFeedbackInput(validBody()).siteCode, null);
  });

  it('metin / ekran / site hataları 400 INVALID_BODY', () => {
    const bad = [
      validBody({ message: '' }),
      validBody({ message: '   ' }),
      validBody({ message: 5 }),
      validBody({ message: 'a'.repeat(FEEDBACK_MESSAGE_MAX + 1) }),
      validBody({ screen_name: '' }),
      validBody({ screen_name: undefined }),
      validBody({ screen_route: 'menu talepler' }),
      validBody({ screen_route: '' }),
      validBody({ screen_route: 'x'.repeat(121) }),
      validBody({ site_code: 'abc' }),
      validBody({ site_code: -3 }),
      null,
      [],
    ];
    for (const body of bad) {
      assert.throws(() => parseFeedbackInput(body), { statusCode: 400, code: 'INVALID_BODY' }, JSON.stringify(body)?.slice(0, 60));
    }
    assert.equal(parseFeedbackInput(validBody({ message: 'a'.repeat(FEEDBACK_MESSAGE_MAX) })).message.length, FEEDBACK_MESSAGE_MAX);
  });

  it('parseListQuery: varsayılan 30, en çok 100, cursor / site_code pozitif tam sayı', () => {
    assert.deepEqual(parseListQuery({}), { limit: 30, cursor: null, siteCode: null });
    assert.deepEqual(parseListQuery({ limit: '100', cursor: '55', site_code: '1000000002' }), { limit: 100, cursor: 55, siteCode: 1000000002 });
    for (const query of [{ limit: '0' }, { limit: '101' }, { limit: 'x' }, { cursor: '-1' }, { site_code: 'q' }]) {
      assert.throws(() => parseListQuery(query), { statusCode: 400 }, JSON.stringify(query));
    }
  });

  it('mapFeedback: silinmiş gönderen "Silinmiş Kullanıcı"; platform sahibi görünümünde site adı', () => {
    const row = { id: '7', site_code: '1000000001', user_code: 5, user_name: null, role: 'resident', screen_name: 'Panel', screen_route: 'menu/dashboard', message: 'm', created_at: new Date('2026-10-28T10:00:00Z') };
    const mapped = mapFeedback(row, []);
    assert.equal(mapped.user_name, 'Silinmiş Kullanıcı');
    assert.equal(mapped.id, 7);
    assert.equal(mapped.created_at, '2026-10-28T10:00:00.000Z');
    assert.equal('site_name' in mapped, false);
    assert.equal(mapFeedback({ ...row, site_name: 'Güneş' }, [], { includeSite: true }).site_name, 'Güneş');
  });
});

// --- rota zinciri (KATI sahte DB) ------------------------------------------------------------------------------------

const SITE = 1000000001;
const OTHER_SITE = 1000000002;
const mk = (id, role, name) => ({ id, user_code: id, userCode: id, role, full_name: name, email: `u${id}@example.com` });
const users = {
  superUser: mk(1, 'super_user', 'Süper'),
  manager: mk(20001, 'site_manager', 'Yönetici'),
  otherManager: mk(20002, 'site_manager', 'Başka Yönetici'),
  resident: mk(20004, 'apartment_owner', 'Sakin'),
  board: mk(20006, 'individual', 'Kurul'),
  staff: mk(20005, 'individual', 'Görevli'),
  outsider: mk(20008, 'individual', 'İlgisiz'),
  individual: mk(20009, 'individual', 'Bireysel'),
};

const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
const ok = (rows = []) => ({ rows, rowCount: rows.length });
let state;
let log;

function makeState() {
  return {
    sites: new Map([[SITE, 'Güneş Sitesi'], [OTHER_SITE, 'Ay Sitesi']]),
    managerLinks: [{ site_code: SITE, user_code: 20001 }, { site_code: OTHER_SITE, user_code: 20002 }],
    memberships: [
      { site_code: SITE, user_code: 20006, role: 'BOARD_MEMBER', is_active: true },
      { site_code: SITE, user_code: 20005, role: 'STAFF', is_active: true },
    ],
    people: [{ site_code: SITE, user_code: 20004 }],
    users: new Map(Object.values(users).map((u) => [u.user_code, u.full_name])),
    deletedUsers: new Set(),
    reports: [],
    attachments: [],
    audit: [],
    nextReportId: 1,
    nextAttId: 1,
    hourly: 0,
    dailyBytes: 0,
    inserts: [],
  };
}

function listRows(sql, params) {
  const siteMatch = sql.match(/r\.site_code = \$(\d+)/);
  const cursorMatch = sql.match(/r\.id < \$(\d+)/);
  const limit = Number(params[params.length - 1]);
  let rows = [...state.reports];
  if (siteMatch) rows = rows.filter((r) => Number(r.site_code) === Number(params[Number(siteMatch[1]) - 1]));
  if (cursorMatch) rows = rows.filter((r) => r.id < Number(params[Number(cursorMatch[1]) - 1]));
  rows.sort((a, b) => b.id - a.id);
  return rows.slice(0, limit).map((r) => ({
    ...r,
    user_name: r.user_code !== null && state.users.has(r.user_code) && !state.deletedUsers.has(r.user_code) ? state.users.get(r.user_code) : null,
    site_name: r.site_code === null ? null : state.sites.get(Number(r.site_code)) ?? null,
  }));
}

function fakeQuery(text, params = []) {
  const sql = norm(text);
  log.push(sql);
  if (sql === 'BEGIN' || sql === 'COMMIT' || sql === 'ROLLBACK' || /^(SAVEPOINT|RELEASE SAVEPOINT|ROLLBACK TO SAVEPOINT) /.test(sql)) return ok();
  if (/^SELECT pg_advisory_xact_lock\(hashtext\(\$1\)\)$/.test(sql)) return ok([{}]);
  if (/^SELECT 1 FROM site_manager_sites WHERE site_code = \$1 AND manager_user_code = \$2 LIMIT 1$/.test(sql)) {
    return ok(state.managerLinks.filter((l) => l.site_code === Number(params[0]) && l.user_code === Number(params[1])).map(() => ({ x: 1 })));
  }
  if (/^SELECT 1 FROM site_memberships WHERE site_code = \$1 AND user_code = \$2 AND role IN \('SITE_OWNER', 'SITE_ADMIN'\) AND is_active = TRUE LIMIT 1$/.test(sql)) {
    return ok(state.memberships.filter((m) => m.site_code === Number(params[0]) && m.user_code === Number(params[1]) && ['SITE_OWNER', 'SITE_ADMIN'].includes(m.role) && m.is_active).map(() => ({ x: 1 })));
  }
  if (/^SELECT user_code, full_name FROM users WHERE user_code = \$1 AND deleted_at IS NULL FOR KEY SHARE$/.test(sql)) {
    const code = Number(params[0]);
    return ok(state.users.has(code) && !state.deletedUsers.has(code) ? [{ user_code: code, full_name: state.users.get(code) }] : []);
  }
  if (/^SELECT user_code FROM users WHERE user_code = \$1 AND deleted_at IS NULL FOR KEY SHARE$/.test(sql)) {
    const code = Number(params[0]);
    return ok(state.users.has(code) && !state.deletedUsers.has(code) ? [{ user_code: code }] : []);
  }
  if (/^SELECT EXISTS \(SELECT 1 FROM site_manager_sites WHERE site_code = \$1 AND manager_user_code = \$2\) AS is_manager,/.test(sql)) {
    const [site, user] = params.map(Number);
    const member = state.memberships.find((m) => m.site_code === site && m.user_code === user && m.is_active);
    return ok([
      {
        is_manager: state.managerLinks.some((l) => l.site_code === site && l.user_code === user),
        member_role: member ? member.role : null,
        is_person: state.people.some((p) => p.site_code === site && p.user_code === user),
      },
    ]);
  }
  if (/^SELECT site_code FROM sites WHERE site_code = \$1 FOR KEY SHARE$/.test(sql)) {
    return ok(state.sites.has(Number(params[0])) ? [{ site_code: String(params[0]) }] : []);
  }
  if (/^SELECT COUNT\(\*\)::INTEGER AS n FROM feedback_reports WHERE user_code = \$1 AND created_at > NOW\(\) - INTERVAL '1 hour'$/.test(sql)) return ok([{ n: state.hourly }]);
  if (/^SELECT COALESCE\(SUM\(a\.size_bytes\), 0\)::BIGINT AS used FROM feedback_attachments a INNER JOIN feedback_reports r ON r\.id = a\.feedback_id WHERE r\.user_code = \$1/.test(sql)) {
    return ok([{ used: state.dailyBytes }]);
  }
  if (/^INSERT INTO feedback_reports \(site_code, user_code, role, screen_name, screen_route, message, app_version, platform\) VALUES/.test(sql)) {
    const [site_code, user_code, role, screen_name, screen_route, message, app_version, platform] = params;
    const row = { id: state.nextReportId, site_code, user_code, role, screen_name, screen_route, message, app_version, platform, created_at: new Date('2026-10-28T12:00:00Z') };
    state.nextReportId += 1;
    state.reports.push(row);
    state.inserts.push({ table: 'feedback_reports', params: [...params] });
    return ok([{ id: row.id, created_at: row.created_at }]);
  }
  if (/^INSERT INTO feedback_attachments \(feedback_id, file_name, mime_type, size_bytes, status, storage_key\) VALUES/.test(sql)) {
    const [feedback_id, file_name, mime_type, size_bytes, storage_key] = params;
    const row = { id: state.nextAttId, feedback_id, file_name, mime_type, size_bytes, status: 'uploading', storage_key, sha256: null, ready_at: null, created_at: new Date(), expired: false };
    state.nextAttId += 1;
    state.attachments.push(row);
    state.inserts.push({ table: 'feedback_attachments', params: [...params] });
    return ok([{ id: row.id }]);
  }
  if (/^INSERT INTO audit_log /.test(sql)) {
    state.audit.push({ action: params[3], site_code: params[4], target_id: params[6], details: JSON.parse(params[7]) });
    return ok();
  }
  if (/^SELECT r\.id, r\.site_code, r\.user_code, r\.role, r\.screen_name, r\.screen_route, r\.message, r\.app_version, r\.platform, r\.created_at, CASE WHEN u\.user_code IS NULL/.test(sql)) {
    return ok(listRows(sql, params));
  }
  if (/^SELECT id, feedback_id, file_name, mime_type, size_bytes, status FROM feedback_attachments WHERE feedback_id = ANY\(\$1::BIGINT\[\]\) AND status = 'ready' ORDER BY id$/.test(sql)) {
    const ids = params[0].map(Number);
    return ok(state.attachments.filter((a) => ids.includes(a.feedback_id) && a.status === 'ready'));
  }
  if (/^SELECT a\.id, a\.status, a\.storage_key, a\.size_bytes, a\.mime_type, a\.file_name, r\.site_code, r\.user_code, \(a\.created_at < NOW\(\) - make_interval\(mins => \$3::INTEGER\)\) AS expired FROM feedback_attachments a INNER JOIN feedback_reports r ON r\.id = a\.feedback_id WHERE a\.id = \$1 AND a\.feedback_id = \$2 LIMIT 1$/.test(sql)) {
    const a = state.attachments.find((x) => x.id === Number(params[0]) && x.feedback_id === Number(params[1]));
    if (!a) return ok();
    const r = state.reports.find((x) => x.id === a.feedback_id);
    return ok([{ ...a, site_code: r.site_code, user_code: r.user_code }]);
  }
  if (/^SELECT id, feedback_id, file_name, mime_type, size_bytes, status, storage_key, \(created_at < NOW\(\) - make_interval\(mins => \$3::INTEGER\)\) AS expired FROM feedback_attachments WHERE id = \$1 AND feedback_id = \$2 FOR UPDATE$/.test(sql)) {
    const a = state.attachments.find((x) => x.id === Number(params[0]) && x.feedback_id === Number(params[1]));
    return ok(a ? [{ ...a }] : []);
  }
  if (/^UPDATE feedback_attachments SET status = 'ready', sha256 = \$2, ready_at = NOW\(\) WHERE id = \$1$/.test(sql)) {
    const a = state.attachments.find((x) => x.id === Number(params[0]));
    a.status = 'ready';
    a.sha256 = params[1];
    a.ready_at = new Date();
    return ok();
  }
  if (/^SELECT status, storage_key FROM feedback_attachments WHERE id = \$1$/.test(sql)) {
    const a = state.attachments.find((x) => x.id === Number(params[0]));
    return ok(a ? [{ status: a.status, storage_key: a.storage_key }] : []);
  }
  if (/^SELECT a\.id, a\.feedback_id, a\.storage_key, a\.size_bytes, a\.mime_type, a\.file_name, r\.site_code FROM feedback_attachments a INNER JOIN feedback_reports r ON r\.id = a\.feedback_id WHERE a\.id = \$1 AND a\.feedback_id = \$2 AND a\.status = 'ready'/.test(sql)) {
    const a = state.attachments.find((x) => x.id === Number(params[0]) && x.feedback_id === Number(params[1]) && x.status === 'ready');
    if (!a) return ok();
    const r = state.reports.find((x) => x.id === a.feedback_id);
    if (/r\.site_code = \$3/.test(sql) && Number(r.site_code) !== Number(params[2])) return ok();
    return ok([{ ...a, site_code: r.site_code }]);
  }
  if (/^SELECT 1 FROM feedback_attachments WHERE id = \$1 AND status = 'ready' LIMIT 1$/.test(sql)) {
    return ok(state.attachments.filter((x) => x.id === Number(params[0]) && x.status === 'ready').map(() => ({ x: 1 })));
  }
  throw new Error(`BEKLENMEYEN SQL (sahte DB katı): ${sql.slice(0, 220)}`);
}

let server;
let baseUrl;
let tmpRoot;
const saved = {};

before(async () => {
  for (const layer of feedbackRouter.stack) {
    if (!layer.route) continue;
    const handlers = layer.route.stack;
    handlers[0].handle = (req, _res, next) => {
      const header = req.headers['x-test-user'];
      if (!header) return _res.status(401).json({ error: 'Yetkisiz erisim.' });
      req.authUser = JSON.parse(decodeURIComponent(header));
      return next();
    };
    // hız sınırlayıcılar ayrı testte sınanır (createRuleLimiter ara katmanı `.reset` taşır)
    for (const entry of handlers) {
      if (typeof entry.handle.reset === 'function') entry.handle = (_req, _res, next) => next();
    }
  }
  const app = express();
  app.use(express.json({ limit: '1mb' }));
  app.use(feedbackRouter);
  await new Promise((resolve) => {
    server = app.listen(0, '127.0.0.1', resolve);
  });
  baseUrl = `http://127.0.0.1:${server.address().port}`;
  tmpRoot = await fsp.mkdtemp(path.join(os.tmpdir(), 'fb-test-'));
  saved.dir = process.env.DOCUMENTS_DIR;
  saved.free = process.env.DOCUMENTS_MIN_FREE_BYTES;
  process.env.DOCUMENTS_DIR = tmpRoot;
  process.env.DOCUMENTS_MIN_FREE_BYTES = '0';
  resetStorageCheck();
});

after(async () => {
  server.closeAllConnections?.();
  await new Promise((resolve) => server.close(resolve));
  delete pool.query;
  delete pool.connect;
  if (saved.dir === undefined) delete process.env.DOCUMENTS_DIR; else process.env.DOCUMENTS_DIR = saved.dir;
  if (saved.free === undefined) delete process.env.DOCUMENTS_MIN_FREE_BYTES; else process.env.DOCUMENTS_MIN_FREE_BYTES = saved.free;
  resetStorageCheck();
  await fsp.rm(tmpRoot, { recursive: true, force: true });
});

beforeEach(() => {
  state = makeState();
  log = [];
  pool.query = async (text, params) => fakeQuery(text, params);
  pool.connect = async () => ({ query: async (text, params) => fakeQuery(text, params), release() {} });
});

/** Gerçek HTTP isteği; gövde JSON ise ayrıştırılır, değilse Buffer döner. */
function raw({ method, urlPath, user = null, headers = {}, body }) {
  return new Promise((resolve, reject) => {
    const allHeaders = { ...headers };
    if (user) allHeaders['x-test-user'] = encodeURIComponent(JSON.stringify(user));
    const req = http.request(`${baseUrl}${urlPath}`, { method, headers: allHeaders }, (res) => {
      const chunks = [];
      res.on('data', (chunk) => chunks.push(chunk));
      res.on('end', () => {
        const buffer = Buffer.concat(chunks);
        let parsed = buffer;
        if (String(res.headers['content-type'] ?? '').startsWith('application/json')) {
          try {
            parsed = JSON.parse(buffer.toString('utf8'));
          } catch (_error) {
            parsed = buffer;
          }
        }
        resolve({ status: res.statusCode, body: parsed, headers: res.headers });
      });
    });
    req.on('error', reject);
    if (body !== undefined) req.write(body);
    req.end();
  });
}

const call = (method, urlPath, { user = null, body } = {}) =>
  raw({
    method,
    urlPath,
    user,
    headers: body === undefined ? {} : { 'content-type': 'application/json' },
    body: body === undefined ? undefined : typeof body === 'string' ? body : JSON.stringify(body),
  });

const post = (user, body) => call('POST', '/app/feedback', { user, body });

/** SOI + JFIF APP0 + SOF0 (genişlik x yükseklik) + EOI: sunucunun başlık okuyucusunun geçtiği en küçük JPEG. */
function jpegOf(width, height, pad = 0) {
  const app0 = Buffer.from([0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00]);
  const sof = Buffer.from([0xff, 0xc0, 0x00, 0x11, 0x08, (height >> 8) & 0xff, height & 0xff, (width >> 8) & 0xff, width & 0xff, 0x03, 0x01, 0x22, 0x00, 0x02, 0x11, 0x01, 0x03, 0x11, 0x01]);
  return Buffer.concat([Buffer.from([0xff, 0xd8]), app0, sof, Buffer.alloc(pad, 0x00), Buffer.from([0xff, 0xd9])]);
}

describe('POST /app/feedback: ekran bağlamı kayda girer, rol sunucuda türetilir', () => {
  it('201: ekran adı + rota + site + rol kayda girer; ek kayıtları `uploading` ve depolama anahtarı sunucuda üretilir', async () => {
    const res = await post(users.manager, validBody({ site_code: SITE, app_version: '1.0.0+1', platform: 'android', attachments: [att(1000), att(2000, { mime_type: 'image/png', file_name: 'b.png' })] }));
    assert.equal(res.status, 201, JSON.stringify(res.body));
    const fb = res.body.feedback;
    assert.deepEqual(
      { id: fb.id, site_code: fb.site_code, role: fb.role, screen_name: fb.screen_name, screen_route: fb.screen_route, message: fb.message, platform: fb.platform, user_name: fb.user_name },
      { id: 1, site_code: SITE, role: 'site_manager', screen_name: 'Talepler', screen_route: 'menu/talepler', message: 'Menü karışık görünüyor.', platform: 'android', user_name: 'Yönetici' },
    );
    assert.deepEqual(fb.attachments.map((a) => [a.id, a.file_name, a.mime_type, a.size_bytes, a.status]), [[1, 'ekran.jpg', 'image/jpeg', 1000, 'uploading'], [2, 'b.png', 'image/png', 2000, 'uploading']]);
    // veritabanına giden değerler (ekran bağlamı sütunlara yazılır)
    const report = state.inserts.find((i) => i.table === 'feedback_reports');
    assert.deepEqual(report.params, [SITE, 20001, 'site_manager', 'Talepler', 'menu/talepler', 'Menü karışık görünüyor.', '1.0.0+1', 'android']);
    const keys = state.inserts.filter((i) => i.table === 'feedback_attachments').map((i) => i.params[4]);
    assert.equal(keys.length, 2);
    for (const key of keys) assert.match(key, new RegExp(`^${SITE}/[0-9a-f-]{36}$`));
    assert.notEqual(keys[0], keys[1]);
  });

  it('audit: kimlik / rota / sayı yazılır; metin ve dosya adı YAZILMAZ', async () => {
    const res = await post(users.resident, validBody({ site_code: SITE, message: 'GİZLİ-METİN-123', attachments: [att(500, { file_name: 'gizli-ad.jpg' })] }));
    assert.equal(res.status, 201);
    const created = state.audit.find((a) => a.action === 'feedback.created');
    assert.ok(created);
    assert.equal(created.target_id, '1');
    assert.deepEqual(created.details, { role: 'resident', screen_route: 'menu/talepler', attachments: 1, attachment_bytes: 500 });
    assert.equal(JSON.stringify(state.audit).includes('GİZLİ-METİN-123'), false);
    assert.equal(JSON.stringify(state.audit).includes('gizli-ad'), false);
  });

  it('rol sunucuda türetilir: yönetici bağı site_manager, kurul board_member, görevli staff, CRM kişisi resident, süper kullanıcı super_user; site yoksa hesap rolü', async () => {
    const expected = [
      [users.manager, SITE, 'site_manager'],
      [users.board, SITE, 'board_member'],
      [users.staff, SITE, 'staff'],
      [users.resident, SITE, 'resident'],
      [users.superUser, OTHER_SITE, 'super_user'],
      [users.individual, null, 'individual'],
      [users.resident, null, 'apartment_owner'],
    ];
    for (const [user, site, role] of expected) {
      const res = await post(user, validBody(site === null ? {} : { site_code: site }));
      assert.equal(res.status, 201, `${user.full_name}: ${JSON.stringify(res.body)}`);
      assert.equal(res.body.feedback.role, role, user.full_name);
      assert.equal(res.body.feedback.site_code, site);
    }
  });

  it('istemcinin bildirdiği rol alanı DİNLENMEZ', async () => {
    const res = await post(users.resident, { ...validBody({ site_code: SITE }), role: 'super_user', user_code: 1 });
    assert.equal(res.status, 201);
    assert.equal(res.body.feedback.role, 'resident');
    assert.equal(res.body.feedback.user_code, 20004);
  });

  it('ilgisiz kullanıcı başka sitenin adına gönderemez: 403 FORBIDDEN_SITE; olmayan site (süper) 404 SITE_NOT_FOUND; kayıt açılmaz', async () => {
    const forbidden = await post(users.outsider, validBody({ site_code: SITE }));
    assert.deepEqual([forbidden.status, forbidden.body.code], [403, 'FORBIDDEN_SITE']);
    const otherSite = await post(users.manager, validBody({ site_code: OTHER_SITE }));
    assert.deepEqual([otherSite.status, otherSite.body.code], [403, 'FORBIDDEN_SITE']);
    const missing = await post(users.superUser, validBody({ site_code: 1999999999 }));
    assert.deepEqual([missing.status, missing.body.code], [404, 'SITE_NOT_FOUND']);
    assert.equal(state.reports.length, 0);
  });

  it('KİMLİKSİZ istek 401; silinmiş hesap 401 ACCOUNT_DELETED', async () => {
    const anon = await call('POST', '/app/feedback', { body: validBody() });
    assert.equal(anon.status, 401);
    state.deletedUsers.add(20004);
    const deleted = await post(users.resident, validBody());
    assert.deepEqual([deleted.status, deleted.body.code], [401, 'ACCOUNT_DELETED']);
    assert.equal(state.reports.length, 0);
  });

  it('SINIR AŞIMLARI 400 ve veritabanına HİÇ gitmez: 5 dosya, dosya 5 MB + 1, tür dışı, boş metin, kötü rota', async () => {
    pool.connect = async () => {
      throw new Error('işlem açılmamalıydı (doğrulama hatası veritabanına gitmeden dönmeli)');
    };
    const cases = [
      [validBody({ attachments: [att(1), att(1), att(1), att(1), att(1)] }), 'FEEDBACK_TOO_MANY_ATTACHMENTS'],
      [validBody({ attachments: [att(5 * MB + 1)] }), 'FEEDBACK_ATTACHMENT_TOO_LARGE'],
      [validBody({ attachments: [att(1), att(6 * MB)] }), 'FEEDBACK_ATTACHMENT_TOO_LARGE'],
      [validBody({ attachments: [att(10, { mime_type: 'application/x-msdownload' })] }), 'FEEDBACK_ATTACHMENT_TYPE_NOT_ALLOWED'],
      [validBody({ message: '' }), 'INVALID_BODY'],
      [validBody({ screen_route: 'a b' }), 'INVALID_BODY'],
      [validBody({ screen_name: '' }), 'INVALID_BODY'],
    ];
    for (const [body, code] of cases) {
      const res = await post(users.resident, body);
      assert.deepEqual([res.status, res.body.code], [400, code], JSON.stringify(body).slice(0, 80));
    }
    assert.equal(state.reports.length, 0);
    assert.equal(log.length, 0, 'veritabanına hiç sorgu gitmedi');
  });

  it('tam sınırda (4 dosya x 5 MB = 20 MB) kabul edilir', async () => {
    const res = await post(users.manager, validBody({ site_code: SITE, attachments: [att(5 * MB), att(5 * MB), att(5 * MB), att(5 * MB)] }));
    assert.equal(res.status, 201, JSON.stringify(res.body));
    assert.equal(res.body.feedback.attachments.length, 4);
  });

  it('saatlik sınır 429 FEEDBACK_RATE_LIMITED (+ Retry-After); günlük 100 MB ek kotası 429 FEEDBACK_QUOTA_EXCEEDED; ikisinde de INSERT yok', async () => {
    state.hourly = 5;
    const hourly = await post(users.resident, validBody());
    assert.deepEqual([hourly.status, hourly.body.code], [429, 'FEEDBACK_RATE_LIMITED']);
    assert.equal(hourly.headers['retry-after'], '3600');
    state.hourly = 0;
    state.dailyBytes = 99 * MB;
    const daily = await post(users.resident, validBody({ attachments: [att(2 * MB)] }));
    assert.deepEqual([daily.status, daily.body.code], [429, 'FEEDBACK_QUOTA_EXCEEDED']);
    const withoutFiles = await post(users.resident, validBody());
    assert.equal(withoutFiles.status, 201, 'dosyasız gönderim kotaya takılmaz');
    assert.equal(state.reports.length, 1);
  });
});

describe('listeleme: yönetici / sahip; yetkisiz 403', () => {
  async function seed() {
    await post(users.resident, validBody({ site_code: SITE, message: 'Birinci', screen_name: 'Panel', screen_route: 'menu/dashboard', attachments: [att(100)] }));
    await post(users.manager, validBody({ site_code: SITE, message: 'İkinci', screen_name: 'Finans', screen_route: 'menu/finans' }));
    await post(users.otherManager, validBody({ site_code: OTHER_SITE, message: 'Başka site' }));
    await post(users.individual, validBody({ message: 'Sitesiz' }));
  }

  it('yetkisiz listeleme 403: sakin, kurul, görevli, ilgisiz, başka sitenin yöneticisi (FORBIDDEN_SITE); kimliksiz 401; /admin için yönetici ve sakin 403', async () => {
    await seed();
    for (const user of [users.resident, users.board, users.staff, users.outsider, users.otherManager]) {
      const res = await call('GET', `/manager/sites/${SITE}/feedback`, { user });
      assert.deepEqual([res.status, res.body.code], [403, 'FORBIDDEN_SITE'], user.full_name);
    }
    assert.equal((await call('GET', `/manager/sites/${SITE}/feedback`)).status, 401);
    for (const user of [users.manager, users.resident, users.board, users.otherManager]) {
      const res = await call('GET', '/admin/feedback', { user });
      assert.equal(res.status, 403, user.full_name);
      assert.equal(res.body.error, 'Bu islem icin super user yetkisi gerekir.');
    }
    assert.equal((await call('GET', '/manager/sites/abc/feedback', { user: users.manager })).status, 400);
  });

  it('site yöneticisi KENDİ sitesinin kayıtlarını görür (ekran bağlamı dahil, yeniden eskiye); başka siteyi / sitesizi görmez; yalnız hazır ekler listelenir', async () => {
    await seed();
    state.attachments[0].status = 'ready';
    const res = await call('GET', `/manager/sites/${SITE}/feedback`, { user: users.manager });
    assert.equal(res.status, 200, JSON.stringify(res.body));
    assert.deepEqual(res.body.items.map((i) => i.message), ['İkinci', 'Birinci']);
    const second = res.body.items[1];
    assert.deepEqual(
      { screen_name: second.screen_name, screen_route: second.screen_route, role: second.role, user_name: second.user_name, site_code: second.site_code },
      { screen_name: 'Panel', screen_route: 'menu/dashboard', role: 'resident', user_name: 'Sakin', site_code: SITE },
    );
    assert.deepEqual(second.attachments.map((a) => [a.id, a.status]), [[1, 'ready']]);
    assert.equal('site_name' in second, false);
    assert.equal(res.body.next_cursor, null);
    assert.equal(res.headers['cache-control'], 'no-store');
    const other = await call('GET', `/manager/sites/${OTHER_SITE}/feedback`, { user: users.manager });
    assert.equal(other.status, 403);
  });

  it('süper kullanıcı her sitenin kaydını görür; /admin/feedback tüm kayıtlar (sitesiz dahil) + site adı; ?site_code süzer; sayfalama cursor ile', async () => {
    await seed();
    const asSuper = await call('GET', `/manager/sites/${OTHER_SITE}/feedback`, { user: users.superUser });
    assert.equal(asSuper.status, 200);
    assert.deepEqual(asSuper.body.items.map((i) => i.message), ['Başka site']);
    const all = await call('GET', '/admin/feedback', { user: users.superUser });
    assert.equal(all.status, 200);
    assert.deepEqual(all.body.items.map((i) => [i.message, i.site_name ?? null]), [['Sitesiz', null], ['Başka site', 'Ay Sitesi'], ['İkinci', 'Güneş Sitesi'], ['Birinci', 'Güneş Sitesi']]);
    const filtered = await call('GET', `/admin/feedback?site_code=${SITE}`, { user: users.superUser });
    assert.deepEqual(filtered.body.items.map((i) => i.message), ['İkinci', 'Birinci']);
    const page1 = await call('GET', '/admin/feedback?limit=2', { user: users.superUser });
    assert.deepEqual(page1.body.items.map((i) => i.message), ['Sitesiz', 'Başka site']);
    assert.equal(page1.body.next_cursor, 3);
    const page2 = await call('GET', `/admin/feedback?limit=2&cursor=${page1.body.next_cursor}`, { user: users.superUser });
    assert.deepEqual(page2.body.items.map((i) => i.message), ['İkinci', 'Birinci']);
    assert.equal(page2.body.next_cursor, null);
    assert.equal((await call('GET', '/admin/feedback?limit=500', { user: users.superUser })).status, 400);
  });

  it('silinmiş gönderen listede "Silinmiş Kullanıcı" görünür', async () => {
    await seed();
    state.deletedUsers.add(20004);
    const res = await call('GET', `/manager/sites/${SITE}/feedback`, { user: users.manager });
    assert.equal(res.body.items.find((i) => i.message === 'Birinci').user_name, 'Silinmiş Kullanıcı');
  });
});

describe('ek yükleme (PUT) ve indirme (GET): gerçek geçici dosya sistemi', () => {
  const octet = (length) => ({ 'content-type': 'application/octet-stream', 'content-length': String(length) });

  async function createWithOneAttachment(user, site, file) {
    const res = await post(user, validBody({ site_code: site, attachments: [att(file.length, { file_name: 'ekran.jpg' })] }));
    assert.equal(res.status, 201, JSON.stringify(res.body));
    return { feedbackId: res.body.feedback.id, attId: res.body.feedback.attachments[0].id };
  }

  it('akış: kayıt aç -> PUT içerik -> ready; dosya feedback_attachments alt ağacında; ikinci PUT 409; indirme yönetici / sahip için, yabancı site 403', async () => {
    const file = jpegOf(640, 480, 64);
    const { feedbackId, attId } = await createWithOneAttachment(users.resident, SITE, file);
    const url = `/app/feedback/${feedbackId}/attachments/${attId}/content`;

    const put = await raw({ method: 'PUT', urlPath: url, user: users.resident, headers: octet(file.length), body: file });
    assert.equal(put.status, 200, JSON.stringify(put.body));
    assert.deepEqual([put.body.attachment.id, put.body.attachment.status, put.body.attachment.size_bytes, put.body.attachment.mime_type], [attId, 'ready', file.length, 'image/jpeg']);
    const key = state.attachments[0].storage_key;
    const onDisk = await fsp.readFile(pathForKey(tmpRoot, key, FEEDBACK_SUBTREE));
    assert.ok(onDisk.equals(file), 'dosya feedback_attachments/<site>/<uuid> altında ve bayt bayt aynı');
    assert.match(state.attachments[0].sha256, /^[0-9a-f]{64}$/);
    assert.ok(state.audit.some((a) => a.action === 'feedback.attachment_added' && a.details.size_bytes === file.length));
    assert.equal(feedbackUploadState.inFlight(), 0);
    assert.equal(feedbackUploadState.active(), 0);

    const again = await raw({ method: 'PUT', urlPath: url, user: users.resident, headers: octet(file.length), body: file });
    assert.deepEqual([again.status, again.body.code], [409, 'UPLOAD_ALREADY_COMPLETED']);

    const download = await raw({ method: 'GET', urlPath: `/manager/sites/${SITE}/feedback/${feedbackId}/attachments/${attId}/content`, user: users.manager });
    assert.equal(download.status, 200);
    assert.ok(Buffer.isBuffer(download.body) && download.body.equals(file));
    assert.equal(download.headers['content-type'], 'image/jpeg');
    assert.match(download.headers['content-disposition'], /^inline/);
    assert.equal(download.headers['x-content-type-options'], 'nosniff');
    assert.equal(download.headers['cache-control'], 'private, no-store');

    const adminDownload = await raw({ method: 'GET', urlPath: `/admin/feedback/${feedbackId}/attachments/${attId}/content`, user: users.superUser });
    assert.equal(adminDownload.status, 200);
    const foreign = await raw({ method: 'GET', urlPath: `/manager/sites/${SITE}/feedback/${feedbackId}/attachments/${attId}/content`, user: users.otherManager });
    assert.equal(foreign.status, 403, 'başka sitenin yöneticisi bu sitenin ekini indiremez');
    const foreignViaOwnSite = await raw({ method: 'GET', urlPath: `/manager/sites/${OTHER_SITE}/feedback/${feedbackId}/attachments/${attId}/content`, user: users.otherManager });
    assert.deepEqual([foreignViaOwnSite.status, foreignViaOwnSite.body.code], [404, 'FEEDBACK_ATTACHMENT_NOT_FOUND'], 'kendi sitesinin yolundan yabancı siteyi dolaşamaz (IDOR yok)');
    const wrongSite = await raw({ method: 'GET', urlPath: `/manager/sites/${OTHER_SITE}/feedback/${feedbackId}/attachments/${attId}/content`, user: users.superUser });
    assert.deepEqual([wrongSite.status, wrongSite.body.code], [404, 'FEEDBACK_ATTACHMENT_NOT_FOUND'], 'ek başka sitenin kaydı: varlık sızmaz');
    const residentDownload = await raw({ method: 'GET', urlPath: `/admin/feedback/${feedbackId}/attachments/${attId}/content`, user: users.resident });
    assert.equal(residentDownload.status, 403);
  });

  it('hazır olmayan ek indirilemez (404); başkası PUT atarsa 404 (varlık sızmaz); yanlış Content-Type 415; Content-Length yok 411; 0 bayt ve 5 MB + 1 → 400', async () => {
    const file = jpegOf(10, 10);
    const { feedbackId, attId } = await createWithOneAttachment(users.resident, SITE, file);
    const url = `/app/feedback/${feedbackId}/attachments/${attId}/content`;

    const notReady = await raw({ method: 'GET', urlPath: `/manager/sites/${SITE}/feedback/${feedbackId}/attachments/${attId}/content`, user: users.manager });
    assert.deepEqual([notReady.status, notReady.body.code], [404, 'FEEDBACK_ATTACHMENT_NOT_FOUND']);

    const stranger = await raw({ method: 'PUT', urlPath: url, user: users.outsider, headers: octet(file.length), body: file });
    assert.deepEqual([stranger.status, stranger.body.code], [404, 'FEEDBACK_ATTACHMENT_NOT_FOUND']);
    const managerPut = await raw({ method: 'PUT', urlPath: url, user: users.manager, headers: octet(file.length), body: file });
    assert.deepEqual([managerPut.status, managerPut.body.code], [404, 'FEEDBACK_ATTACHMENT_NOT_FOUND'], 'yükleme hakkı yalnız kaydı açandadır');

    const wrongType = await raw({ method: 'PUT', urlPath: url, user: users.resident, headers: { 'content-type': 'image/jpeg', 'content-length': String(file.length) }, body: file });
    assert.equal(wrongType.status, 415);
    const noLength = await raw({ method: 'PUT', urlPath: url, user: users.resident, headers: { 'content-type': 'application/octet-stream', 'transfer-encoding': 'chunked' }, body: file });
    assert.equal(noLength.status, 411);
    const empty = await raw({ method: 'PUT', urlPath: url, user: users.resident, headers: octet(0), body: Buffer.alloc(0) });
    assert.deepEqual([empty.status, empty.body.code], [400, 'FEEDBACK_ATTACHMENT_SIZE_MISMATCH']);
    const huge = await raw({ method: 'PUT', urlPath: url, user: users.resident, headers: octet(5 * MB + 1), body: Buffer.alloc(0) });
    assert.deepEqual([huge.status, huge.body.code], [400, 'FEEDBACK_ATTACHMENT_TOO_LARGE']);
    assert.equal(feedbackUploadState.inFlight(), 0);
    assert.equal(feedbackUploadState.active(), 0);
  });

  it('bildirilenden farklı boyut 400 FEEDBACK_ATTACHMENT_SIZE_MISMATCH; içerik imzası uyuşmazsa 415 (dosya yazılmaz, kayıt uploading kalır); geçersiz kimlik 404', async () => {
    const file = jpegOf(10, 10);
    const { feedbackId, attId } = await createWithOneAttachment(users.resident, SITE, file);
    const url = `/app/feedback/${feedbackId}/attachments/${attId}/content`;
    const other = Buffer.concat([file, Buffer.from([0])]);
    const mismatch = await raw({ method: 'PUT', urlPath: url, user: users.resident, headers: octet(other.length), body: other });
    assert.deepEqual([mismatch.status, mismatch.body.code], [400, 'FEEDBACK_ATTACHMENT_SIZE_MISMATCH']);
    const fake = Buffer.alloc(file.length, 0x41); // metin: JPEG imzası yok
    const content = await raw({ method: 'PUT', urlPath: url, user: users.resident, headers: octet(fake.length), body: fake });
    assert.deepEqual([content.status, content.body.code], [415, 'ATTACHMENT_TYPE_NOT_ALLOWED']);
    assert.equal(state.attachments[0].status, 'uploading');
    const bad = await raw({ method: 'PUT', urlPath: '/app/feedback/abc/attachments/1/content', user: users.resident, headers: octet(3), body: Buffer.from('abc') });
    assert.deepEqual([bad.status, bad.body.code], [404, 'FEEDBACK_NOT_FOUND']);
    const badAtt = await raw({ method: 'PUT', urlPath: `/app/feedback/${feedbackId}/attachments/zzz/content`, user: users.resident, headers: octet(3), body: Buffer.from('abc') });
    assert.deepEqual([badAtt.status, badAtt.body.code], [404, 'FEEDBACK_ATTACHMENT_NOT_FOUND']);
  });

  it('piksel boyutu açılma bombası koruması: 20.000 x 20.000 başlıklı küçük JPEG 415 ATTACHMENT_DIMENSIONS_TOO_LARGE', async () => {
    const file = jpegOf(20000, 20000);
    const { feedbackId, attId } = await createWithOneAttachment(users.resident, SITE, file);
    const put = await raw({ method: 'PUT', urlPath: `/app/feedback/${feedbackId}/attachments/${attId}/content`, user: users.resident, headers: octet(file.length), body: file });
    assert.deepEqual([put.status, put.body.code], [415, 'ATTACHMENT_DIMENSIONS_TOO_LARGE']);
    assert.equal(state.attachments[0].status, 'uploading');
  });
});

describe('bakım: bayat geri bildirim eki yüklemeleri', () => {
  it('2 saati aşan `uploading` satır ÖNCE silinir (RETURNING), SONRA dosyası; DELETE 0 satırsa dosyaya dokunulmaz; tablo yoksa hiçbir şey yapılmaz', async () => {
    const root = await fsp.mkdtemp(path.join(os.tmpdir(), 'fb-maint-'));
    try {
      const siteDir = path.join(root, FEEDBACK_SUBTREE, String(SITE));
      await fsp.mkdir(siteDir, { recursive: true });
      const keyA = `${SITE}/11111111-1111-4111-8111-111111111111`;
      const keyB = `${SITE}/22222222-2222-4222-8222-222222222222`;
      await fsp.writeFile(path.join(root, FEEDBACK_SUBTREE, keyA), 'a');
      await fsp.writeFile(path.join(root, FEEDBACK_SUBTREE, keyB), 'b');
      const queries = [];
      const db = {
        query: async (text, params) => {
          const sql = norm(text);
          queries.push(sql);
          if (/to_regclass\('public\.feedback_attachments'\)/.test(sql)) return { rows: [{ present: true }] };
          if (/^SELECT id, storage_key FROM feedback_attachments WHERE status = 'uploading'/.test(sql)) return { rows: [{ id: 1, storage_key: keyA }, { id: 2, storage_key: keyB }] };
          if (/^DELETE FROM feedback_attachments WHERE id = \$1 AND status = 'uploading'/.test(sql)) {
            return params[0] === 1 ? { rowCount: 1, rows: [{ storage_key: keyA }] } : { rowCount: 0, rows: [] };
          }
          throw new Error(`beklenmeyen sql: ${sql}`);
        },
      };
      const summary = { feedback_stale_uploads: 0, errors: 0 };
      await cleanStaleFeedbackUploads(root, summary, db);
      assert.deepEqual(summary, { feedback_stale_uploads: 1, errors: 0 });
      await assert.rejects(fsp.stat(path.join(root, FEEDBACK_SUBTREE, keyA)), { code: 'ENOENT' });
      assert.equal((await fsp.readFile(path.join(root, FEEDBACK_SUBTREE, keyB), 'utf8')), 'b', 'geç gelen PUT satırı ready yaptıysa dosya korunur');

      const absent = { query: async () => ({ rows: [{ present: false }] }) };
      const summary2 = { feedback_stale_uploads: 0, errors: 0 };
      await cleanStaleFeedbackUploads(root, summary2, absent);
      assert.deepEqual(summary2, { feedback_stale_uploads: 0, errors: 0 });
    } finally {
      await fsp.rm(root, { recursive: true, force: true });
    }
  });

  it('bakım turu özetinde feedback_stale_uploads alanı var ve tur hata vermez (katı sahte DB: tablo katalog sorgusu)', async () => {
    pool.query = async (text) => {
      const sql = norm(text);
      if (/to_regclass/.test(sql)) return { rows: [{ present: false }] };
      return { rows: [], rowCount: 0 };
    };
    pool.connect = async () => ({
      query: async (text) => {
        const sql = norm(text);
        if (/pg_try_advisory_lock/.test(sql)) return { rows: [{ locked: true }] };
        if (/to_regclass/.test(sql)) return { rows: [{ present: false }] };
        return { rows: [], rowCount: 0 };
      },
      on() {},
      off() {},
      release() {},
    });
    const result = await runDocumentsMaintenanceOnce({ env: { ...process.env, DOCUMENTS_DIR: tmpRoot, DOCUMENTS_MIN_FREE_BYTES: '0' } });
    assert.equal(result.skipped, false);
    assert.equal(result.summary.feedback_stale_uploads, 0);
  });
});
