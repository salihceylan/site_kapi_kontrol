// Toplu yükleme commit akışı (DB'siz, bellek içi sahte havuz): hesap açma kapsamı, nihai kullanıcı adlarının yanıtta dönmesi, şifre özetlerinin
// TRANSACTION ÖNCESİ hesaplanması, kapsam dışı (hesapsız mevcut) sakinlere dokunulmaması. Gerçek PostgreSQL: scripts/qa_platform_pg.mjs bölüm bulk_import.
import { describe, it, before, after, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert/strict';
import bcrypt from 'bcryptjs';
import { pool } from '../src/db.js';
import { commitImport, previewImport, resetBulkImportGauge } from '../src/modules/bulk_import_service.js';
import { SYNC_STEPS } from '../src/modules/people_sync_sql.js';

process.env.PEOPLE_SYNC_MIN_INTERVAL_MS = '0';

const SITE = 1000000001;
const ACTOR = { id: 20001, user_code: 20001, userCode: 20001, role: 'site_manager', full_name: 'Ayşe Yönetici', email: 'u20001@example.com' };
const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
const ok = (rows = [], rowCount = rows.length) => ({ rows, rowCount });
const STEP_SQLS = new Set(SYNC_STEPS.map((step) => norm(step.sql)));

const BLOCKS = [{ id: '1', block_name: 'A Blok' }];
const APARTMENTS = ['101', '102', '103'].map((id, i) => ({
  id, block_id: '1', unit_label: `Daire ${i + 1}`, floor: null, category: null, land_share_numerator: null, land_share_denominator: null, responsible_party: 'both', has_finance: false,
}));

let db;

function freshDb({ existingPeople = [], existingResidencies = [] } = {}) {
  return { log: [], users: [], audits: [], nextUser: 900, existingPeople, existingResidencies, takenLogins: new Set(), emailUsers: {}, lockedIds: null, failInsertFor: null, peopleRows: new Map() };
}

function handle(sql, params = []) {
  db.log.push({ sql, params });
  if (/^(BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE SAVEPOINT|ROLLBACK TO SAVEPOINT|SET LOCAL)/.test(sql) || /^SELECT pg_advisory_xact_lock/.test(sql) || STEP_SQLS.has(sql)) return ok();
  if (/^SELECT pg_try_advisory_xact_lock/.test(sql)) return ok([{ locked: true }]);
  if (/^SELECT 1 FROM sites WHERE site_code = \$1$/.test(sql)) return ok([{ x: 1 }]);
  if (/^SELECT site_code FROM sites WHERE site_code = \$1 FOR KEY SHARE$/.test(sql)) return ok([{ site_code: String(SITE) }]);
  if (/FROM bulk_import_runs/.test(sql)) return ok();
  if (/FROM site_blocks WHERE site_code = \$1 ORDER BY sort_order, id$/.test(sql)) return ok(BLOCKS);
  if (/^SELECT a\.id, a\.block_id, a\.unit_label/.test(sql)) return ok(APARTMENTS);
  if (/^SELECT sp\.id, sp\.user_code, sp\.is_active, sp\.full_name AS sp_name/.test(sql)) return ok(db.existingPeople);
  if (/^SELECT r\.id, r\.apartment_id, r\.person_id, r\.relation FROM apartment_residencies/.test(sql)) return ok(db.existingResidencies);
  if (/^SELECT id, person_id, plate FROM vehicles/.test(sql)) return ok();
  if (/^SELECT id FROM apartments WHERE id = ANY/.test(sql)) return ok();
  if (/^SELECT user_code FROM users WHERE user_code = \$1 AND deleted_at IS NULL FOR KEY SHARE/.test(sql)) return ok([{ user_code: ACTOR.user_code }]);
  if (/^INSERT INTO bulk_import_runs/.test(sql)) return ok([{ id: '55', kind: params[1], row_count: params[7], created_at: new Date('2026-10-26T10:00:00Z') }]);
  if (/^SELECT nextval/.test(sql)) return ok(Array.from({ length: Number(params[0]) }, (_, i) => ({ id: String(300 + i) })));
  if (/^INSERT INTO site_people/.test(sql)) {
    const rows = JSON.parse(params[0]);
    for (const r of rows) db.peopleRows.set(Number(r.id), r);
    return ok([], rows.length);
  }
  if (/^INSERT INTO apartment_residencies/.test(sql)) {
    const rows = JSON.parse(params[0]).map((e, i) => ({ id: String(700 + i), apartment_id: String(e.apartment_id), person_id: String(e.person_id), relation: e.relation }));
    return ok(rows);
  }
  if (/^INSERT INTO apartment_residency_log/.test(sql)) return ok();
  if (/^UPDATE site_people sp SET is_active/.test(sql)) return ok([], JSON.parse(params[0]).length);
  if (/^UPDATE apartments a SET/.test(sql)) return ok([], JSON.parse(params[0]).length);
  if (/^INSERT INTO audit_log/.test(sql)) {
    db.audits.push(...JSON.parse(params[0]));
    return ok();
  }
  // --- hesap açma
  if (/^SELECT sp\.id, sp\.full_name, sp\.email, sp\.phone FROM site_people sp/.test(sql)) {
    db.lockedIds = params[0];
    return ok(params[0].map((id) => ({ id: String(id), full_name: db.peopleRows.get(Number(id))?.full_name ?? null, email: db.peopleRows.get(Number(id))?.email ?? null, phone: db.peopleRows.get(Number(id))?.phone ?? null })));
  }
  if (/^SELECT a\.id, a\.unit_label, a\.sort_order, b\.block_name/.test(sql)) {
    return ok(params[0].map((id) => ({ id: String(id), unit_label: `Daire ${id}`, sort_order: 1, block_name: 'A Blok' })));
  }
  if (/FROM users u WHERE LOWER\(u\.email\) = \$1/.test(sql)) {
    const row = db.emailUsers[params[0]];
    return ok(row ? [row] : []);
  }
  if (/^SELECT user_code FROM users WHERE LOWER\(login_name\)/.test(sql)) return ok(db.takenLogins.has(String(params[0]).toLowerCase()) ? [{ user_code: 1 }] : []);
  if (/^INSERT INTO users/.test(sql)) {
    if (db.failInsertFor && db.failInsertFor === params[2]) throw Object.assign(new Error('enjekte'), { code: '23505' });
    db.nextUser += 1;
    db.takenLogins.add(String(params[2]).toLowerCase());
    db.users.push({ user_code: db.nextUser, login_name: params[2], email: params[1], password_hash: params[4], full_name: params[0] });
    return ok([{ user_code: db.nextUser }]);
  }
  if (/^UPDATE site_people sp SET user_code/.test(sql)) return ok([], 1);
  if (/^SELECT id FROM apartments WHERE id = \$1 FOR UPDATE/.test(sql)) return ok([{ id: params[0] }]);
  if (/^(INSERT|UPDATE|DELETE)\b/.test(sql)) return ok([], 0);
  return ok();
}

before(() => {
  pool.query = async (text, params) => handle(norm(text), params ?? []);
  pool.connect = async () => ({
    async query(text, params) {
      return handle(norm(text), params ?? []);
    },
    release() {},
  });
});
after(() => {
  delete pool.query;
  delete pool.connect;
});
beforeEach(() => {
  db = freshDb();
  resetBulkImportGauge();
  mock.method(console, 'error', () => {});
  mock.method(console, 'log', () => {});
});
afterEach(() => mock.restoreAll());

const row = (n, cells) => ({ n, cells });
const body = (rows, over = {}) => ({ spec_version: 1, rows, ...over });

async function previewAndCommit(kind, rows, key = 'accounts-test-0001') {
  const preview = await previewImport({ siteCode: SITE, kind, body: body(rows) });
  db.log.length = 0;
  const committed = await commitImport({
    siteCode: SITE,
    kind,
    actor: ACTOR,
    body: body(rows, { expected_hash: preview.preview_hash, idempotency_key: key, acknowledged: true }),
  });
  return { preview, committed };
}

const PEOPLE_ROWS = [
  row(2, { ad_soyad: 'Ali Veli', blok: 'A', daire_no: '1', iliski: 'Malik', sifre: 'özel-sifre-1' }),
  row(3, { ad_soyad: 'Ali Veli', blok: 'A', daire_no: '2', iliski: 'Kiracı' }),
  row(4, { ad_soyad: 'Dairesiz Kişi', e_posta: 'dairesiz@example.com' }),
];

describe('commit: hesap açma kapsamı ve yanıt', () => {
  it('önizleme "hesap açılacak kişi" sayısını verir (dairesiz kişi sayılmaz)', async () => {
    const preview = await previewImport({ siteCode: SITE, kind: 'people', body: body(PEOPLE_ROWS) });
    assert.equal(preview.plan.account_create, 2);
    assert.equal(preview.plan.people_create, 3);
  });

  it('yalnız bu yüklemede daire ilişkisi eklenen kişilere hesap açılır; yanıt NİHAİ kullanıcı adlarını satır no ile döner', async () => {
    const { preview, committed } = await previewAndCommit('people', PEOPLE_ROWS);
    assert.equal(committed.status, 201);
    const accounts = committed.body.result.accounts;
    assert.deepEqual([accounts.created, accounts.linked, accounts.skipped], [2, 0, 0]);
    // Admin önceliği kiracı > malik: aynı çalıştırmada KİRACI (satır 3) önce hesap alır; aynı adlı malik (satır 2) ikinci olur ve _2 eki alır.
    assert.deepEqual(accounts.items, [
      { n: 3, login_name: 'ali.veli', status: 'created' },
      { n: 2, login_name: 'ali.veli_2', status: 'created' },
    ]);
    assert.equal(db.users.length, 2, 'dairesiz kişiye hesap açılmaz');
    assert.equal(preview.plan.account_create, 2);
    // kilitlenen / hesaplanan kişi kümesi = bu yüklemede oluşan iki kişi (kimlik 300, 301); başka kimse değil
    assert.deepEqual(db.lockedIds, [300, 301]);
    // audit: kişi başına person.account_created (kullanıcı kodu, kişisel veri yok)
    const accountAudits = db.audits.filter((a) => a.action === 'person.account_created');
    assert.equal(accountAudits.length, 2);
    assert.ok(!/Ali|Veli|dairesiz/i.test(JSON.stringify(accountAudits)));
    assert.equal(db.audits.find((a) => a.action === 'import.committed').details.counts.accounts_created, 2);
  });

  it('ŞİFRE kişiye aittir: özel şifre kendi satırının hesabına, varsayılan 1234 öbürüne gider (ad aynı olsa da)', async () => {
    await previewAndCommit('people', PEOPLE_ROWS);
    // özel şifreli satır 2 (malik) kiracıdan sonra işlenir: ali.veli_2; kiracı (satır 3) varsayılan 1234 ile ali.veli
    const owner = db.users.find((u) => u.login_name === 'ali.veli_2');
    const tenant = db.users.find((u) => u.login_name === 'ali.veli');
    assert.equal(await bcrypt.compare('özel-sifre-1', owner.password_hash), true);
    assert.equal(await bcrypt.compare('1234', tenant.password_hash), true);
    assert.equal(await bcrypt.compare('1234', owner.password_hash), false);
  });

  it('özetler TRANSACTION ÖNCESİ hesaplanır: salt okunur anlık görüntü transaction\'ı yazma transaction\'ından önce; kullanıcı INSERT\'leri yazma transaction\'ında', async () => {
    await previewAndCommit('people', PEOPLE_ROWS);
    const begins = db.log.map((entry, index) => ({ sql: entry.sql, index })).filter((entry) => /^BEGIN/.test(entry.sql));
    assert.equal(begins.length, 2);
    assert.match(begins[0].sql, /READ ONLY/, 'önce özet hesabı için salt okunur anlık görüntü');
    assert.equal(begins[1].sql, 'BEGIN');
    const firstInsert = db.log.findIndex((entry) => /^INSERT INTO users/.test(entry.sql));
    assert.ok(firstInsert > begins[1].index);
  });

  it('KAPSAM: sitedeki HESAPSIZ mevcut sakine dokunulmaz (hesap açılmaz, kilitlenmez); yalnız yeni eklenen kişi hesap alır', async () => {
    db = freshDb({
      existingPeople: [{ id: '7', user_code: null, is_active: true, sp_name: 'Eski Sakin', sp_phone: null, sp_email: null, note: null }],
      existingResidencies: [{ id: '55', apartment_id: '103', person_id: '7', relation: 'resident' }],
    });
    const { committed } = await previewAndCommit('people', [row(2, { ad_soyad: 'Yeni Kişi', blok: 'A', daire_no: '1' })]);
    assert.equal(committed.body.result.accounts.created, 1);
    assert.deepEqual(db.users.map((u) => u.login_name), ['yeni.kisi']);
    assert.deepEqual(db.lockedIds, [300], 'eski hesapsız sakin (kimlik 7) kapsamda değil');
    assert.equal(db.log.some((entry) => entry.params?.some?.((value) => Array.isArray(value) && value.includes(7)) && /INSERT INTO users|SET user_code/.test(entry.sql)), false);
  });

  it('SAVEPOINT: bir kişinin hesabı veri hatasıyla düşerse commit yine tamamlanır, atlanan yanıtta açıklamayla bildirilir', async () => {
    db.failInsertFor = 'ali.veli_2';
    const { committed } = await previewAndCommit('people', PEOPLE_ROWS);
    assert.equal(committed.status, 201);
    const accounts = committed.body.result.accounts;
    assert.deepEqual([accounts.created, accounts.skipped], [1, 1]);
    // kiracı (satır 3) önce işlenip ali.veli alır; malik (satır 2) ali.veli_2'de düşer
    assert.deepEqual(accounts.skipped_items.map((i) => [i.n, i.code]), [[2, 'ACCOUNT_FAILED']]);
    assert.match(accounts.skipped_items[0].message, /hesap/i);
    assert.ok(db.log.some((entry) => /^ROLLBACK TO SAVEPOINT/.test(entry.sql)));
    assert.equal(db.log.some((entry) => /^ROLLBACK$/.test(entry.sql)), false, 'transaction geri alınmadı');
  });

  it('daire yüklemesi hesap açmaz ve yanıtta accounts alanı yoktur', async () => {
    const { committed } = await previewAndCommit('apartments', [row(2, { blok: 'A', daire_no: '1', kat: 3 })]);
    assert.equal(committed.status, 201);
    assert.equal('accounts' in committed.body.result, false);
    assert.equal(db.log.some((entry) => /INSERT INTO users|SAVEPOINT/.test(entry.sql)), false);
  });
});
