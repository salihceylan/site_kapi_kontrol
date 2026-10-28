// Toplu yükleme commit akışı (DB'siz, bellek içi sahte havuz): hesap açma kapsamı, nihai kullanıcı adlarının yanıtta dönmesi, şifre özetlerinin
// TRANSACTION ÖNCESİ hesaplanması, kapsam dışı (hesapsız mevcut) sakinlere dokunulmaması. Önizleme / denetim SİTE kapsamlıdır (başka sitenin ad / e-postası
// görünmez, güvenlik denetimi 2026-10-28); yazım anı SİSTEM geneldir. Gerçek PostgreSQL: scripts/qa_platform_pg.mjs bölüm bulk_import.
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

/**
 * `siteLogins`: SITE yöneticisinin GÖREBİLDİĞİ hesapların kullanıcı adları (önizleme / denetim sorgusu bunları görür);
 * `takenLogins`: yalnız BAŞKA sitelerde kayıtlı adlar (yazım anındaki sistem geneli sorgu bunları da görür, önizleme görmez);
 * `emailUsers`: e-posta -> { user_code, login_name, linkable, sites? } (`sites`: hesabı görebilen siteler, varsayılan [SITE]; yazıcının tek e-posta sorgusu sistem geneldir).
 */
function freshDb({ existingPeople = [], existingResidencies = [] } = {}) {
  return { log: [], users: [], audits: [], nextUser: 900, existingPeople, existingResidencies, takenLogins: new Set(), siteLogins: new Set(), emailUsers: {}, lockedIds: null, failInsertFor: null, peopleRows: new Map() };
}

/** Kapsam koşulu SQL'de yoksa sahte veritabanı sorguyu reddeder (kapsamsız sorgu gerçek veritabanında tüm sistemi sayardı). */
function assertScopedSql(sql) {
  for (const fragment of ['vis_sp.site_code = $2::BIGINT', 'vis_a.site_code = $2::BIGINT', 'vis_r.site_code = $2::BIGINT']) {
    assert.ok(sql.includes(fragment), `KAPSAMSIZ SORGU (sayım açığı): ${fragment} yok -> ${sql.slice(0, 160)}`);
  }
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
    // yazıcının tek e-posta sorgusu: SİSTEM geneli (users.email tekil), kapsam koşulu yok
    const row = db.emailUsers[params[0]];
    if (!row) return ok([]);
    const { sites: _sites, ...owner } = row;
    return ok([owner]);
  }
  // önizleme/commit hesap çözümlemesi: e-postası BU SİTENİN görebildiği bir hesaba ait mi (toplu, site kapsamlı)
  if (/FROM users u WHERE LOWER\(u\.email\) = ANY/.test(sql)) {
    assertScopedSql(sql);
    return ok(
      params[0]
        .filter((email) => db.emailUsers[email] && (db.emailUsers[email].sites ?? [SITE]).includes(Number(params[1])))
        .map((email) => {
          const { sites: _sites, ...owner } = db.emailUsers[email];
          return { email, ...owner };
        }),
    );
  }
  // önizleme / denetim: aday kullanıcı adlarından hangileri BU SİTENİN görebildiği hesaplarda alınmış (toplu, site kapsamlı)
  if (/^SELECT LOWER\(u\.login_name\) AS name FROM users u WHERE LOWER\(u\.login_name\) = ANY\(\$1::TEXT\[\]\) AND \(/.test(sql)) {
    assertScopedSql(sql);
    const visible = Number(params[1]) === SITE ? db.siteLogins : new Set();
    return ok(params[0].filter((name) => visible.has(String(name).toLowerCase())).map((name) => ({ name })));
  }
  // yazım anı: SİSTEM geneli (başka sitelerdeki adlar dahil)
  if (/^SELECT LOWER\(login_name\) AS name FROM users WHERE LOWER\(login_name\) = ANY\(\$1::TEXT\[\]\)$/.test(sql)) {
    const everywhere = (name) => db.takenLogins.has(String(name).toLowerCase()) || db.siteLogins.has(String(name).toLowerCase());
    return ok(params[0].filter(everywhere).map((name) => ({ name })));
  }
  if (/^INSERT INTO users/.test(sql)) {
    if (db.failInsertFor && db.failInsertFor === params[2]) throw Object.assign(new Error('enjekte'), { code: '23505' });
    db.nextUser += 1;
    // yeni hesap bu sitenin kişisine bağlanır: sonraki önizlemelerde bu sitenin yöneticisi de görür
    db.siteLogins.add(String(params[2]).toLowerCase());
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

  it('önizleme her yeni hesap için sistemin seçtiği kullanıcı adını satır no ile verir (aynı adlar dosyada _2 alır); dairesiz satırda hesap yok', async () => {
    const preview = await previewImport({ siteCode: SITE, kind: 'people', body: body(PEOPLE_ROWS) });
    assert.deepEqual(preview.accounts, [
      { n: 2, status: 'new', login_name: 'ali.veli', editable: true, custom: false },
      { n: 3, status: 'new', login_name: 'ali.veli_2', editable: true, custom: false },
    ]);
  });

  it('BU SİTEDE alınmış ad önizlemede atlanır: sıradaki boş varyasyon önerilir', async () => {
    db.siteLogins = new Set(['ali.veli', 'ali.veli_2']);
    const preview = await previewImport({ siteCode: SITE, kind: 'people', body: body(PEOPLE_ROWS) });
    assert.deepEqual(preview.accounts.map((a) => [a.n, a.login_name]), [[2, 'ali.veli_3'], [3, 'ali.veli_4']]);
  });

  it('SAYIM AÇIĞI KAPALI: BAŞKA sitede alınmış ad önizlemede GÖRÜNMEZ (taban önerilir); hiç alınmamış ad ile aynı önizleme gövdesi ve aynı hash', async () => {
    const baseline = await previewImport({ siteCode: SITE, kind: 'people', body: body(PEOPLE_ROWS) });
    db.takenLogins = new Set(['ali.veli', 'ali.veli_2', 'ali.veli_3']);
    const preview = await previewImport({ siteCode: SITE, kind: 'people', body: body(PEOPLE_ROWS) });
    assert.deepEqual(preview.accounts.map((a) => [a.n, a.login_name]), [[2, 'ali.veli'], [3, 'ali.veli_2']]);
    assert.deepEqual(preview, baseline, 'başka sitenin hesapları önizlemeyi hiçbir alanda değiştirmez');
    assert.equal(preview.preview_hash, baseline.preview_hash);
  });

  it('başka sitede alınmış ad ONAYDA sistem geneli denetlenir: kopya YAZILMAZ, sıradaki boş ad verilir ve sonuçta requested_login_name + renamed ile bildirilir (PREVIEW_STALE değil)', async () => {
    db.takenLogins = new Set(['ali.veli', 'ali.veli_2']); // yalnız başka sitelerde
    const { preview, committed } = await previewAndCommit('people', PEOPLE_ROWS);
    assert.deepEqual(preview.accounts.map((a) => [a.n, a.login_name]), [[2, 'ali.veli'], [3, 'ali.veli_2']], 'önizleme başka siteyi görmez');
    assert.equal(committed.status, 201);
    const accounts = committed.body.result.accounts;
    assert.deepEqual([accounts.created, accounts.skipped, accounts.renamed], [2, 0, 2]);
    const byN = Object.fromEntries(accounts.items.map((i) => [i.n, i]));
    // kiracı (satır 3) önce işlenir: istenen ali.veli_2 başka sitede alınmış -> ali.veli_3; malik (satır 2): istenen ali.veli alınmış, _2 kardeşe ayrılı, _3 az önce verildi -> ali.veli_4
    assert.deepEqual([byN[3].login_name, byN[3].requested_login_name], ['ali.veli_3', 'ali.veli_2']);
    assert.deepEqual([byN[2].login_name, byN[2].requested_login_name], ['ali.veli_4', 'ali.veli']);
    const written = db.users.map((u) => u.login_name.toLowerCase());
    assert.equal(new Set(written).size, written.length, 'kopya ad yok');
    assert.ok(written.every((name) => !db.takenLogins.has(name)), 'başka sitedeki hiçbir ad yazılmadı');
  });

  it('ÖNİZLEME HASH\'İ önerilen adlara bağlıdır: ad bu arada BU SİTEDE başkasına geçerse commit PREVIEW_STALE verir (gösterilmeyen ad yazılmaz)', async () => {
    const preview = await previewImport({ siteCode: SITE, kind: 'people', body: body(PEOPLE_ROWS) });
    db.siteLogins.add('ali.veli');
    await assert.rejects(
      () => commitImport({ siteCode: SITE, kind: 'people', actor: ACTOR, body: body(PEOPLE_ROWS, { expected_hash: preview.preview_hash, idempotency_key: 'stale-names-0001', acknowledged: true }) }),
      (error) => error.code === 'PREVIEW_STALE',
    );
    assert.equal(db.users.length, 0);
  });

  it('yönetici seçimi ad (giris_adi): boştaysa aynen önerilir ve üretilen adlar onunla çakışmaz; bu sitede alınmışsa satır hatası LOGIN_NAME_TAKEN; geçersizse LOGIN_NAME_INVALID', async () => {
    const rows = [
      row(2, { ad_soyad: 'Ali Veli', blok: 'A', daire_no: '1', iliski: 'Malik' }),
      row(3, { ad_soyad: 'Ali Veli', blok: 'A', daire_no: '2', iliski: 'Kiracı', giris_adi: 'Ali.Veli' }), // seçim: 'ali.veli' (normalleşir)
    ];
    const preview = await previewImport({ siteCode: SITE, kind: 'people', body: body(rows) });
    assert.deepEqual(preview.accounts.map((a) => [a.n, a.login_name, a.custom]), [[2, 'ali.veli_2', false], [3, 'ali.veli', true]]);

    // başka sitede kayıtlı seçim REDDEDİLMEZ (sayım açığı kapalı): önizleme boştaki ad gibi davranır
    db.takenLogins = new Set(['ali.veli']);
    const elsewhere = await previewImport({ siteCode: SITE, kind: 'people', body: body(rows) });
    assert.deepEqual(elsewhere, preview);
    db.takenLogins = new Set();

    db.siteLogins = new Set(['ali.veli']);
    const taken = await previewImport({ siteCode: SITE, kind: 'people', body: body(rows) });
    assert.deepEqual(taken.issues.filter((i) => i.n === 3).map((i) => i.code), ['LOGIN_NAME_TAKEN']);
    assert.equal(taken.totals.error, 1);
    assert.deepEqual(taken.accounts.map((a) => [a.n, a.status, a.login_name]), [[2, 'new', 'ali.veli_2'], [3, 'rejected', null]]);
    assert.equal(taken.accounts[1].code, 'LOGIN_NAME_TAKEN');
    assert.match(taken.accounts[1].message, /bu sitede başka bir hesapta kayıtlı/);
    assert.equal(taken.accounts[1].editable, true);

    const invalid = await previewImport({ siteCode: SITE, kind: 'people', body: body([row(2, { ad_soyad: 'Ali Veli', blok: 'A', daire_no: '1', giris_adi: 'a@b' })]) });
    assert.deepEqual(invalid.issues.map((i) => i.code), ['LOGIN_NAME_INVALID']);
  });

  it('dosyada aynı ad iki satıra seçilirse ikinci satır LOGIN_NAME_DUP_IN_FILE hatası alır', async () => {
    const rows = [
      row(2, { ad_soyad: 'Ali Veli', blok: 'A', daire_no: '1', giris_adi: 'ortak.ad' }),
      row(3, { ad_soyad: 'Veli Ali', blok: 'A', daire_no: '2', giris_adi: 'ORTAK.ad' }),
    ];
    const preview = await previewImport({ siteCode: SITE, kind: 'people', body: body(rows) });
    assert.deepEqual(preview.issues.map((i) => [i.n, i.code]), [[3, 'LOGIN_NAME_DUP_IN_FILE']]);
    assert.match(preview.issues[0].message, /satır 2/);
  });

  it('ESKİ dosya: kullanici_adi hücresi yok sayılır (400 değil), dosya başına TEK bilgi uyarısı; ad sistemden gelir', async () => {
    const rows = [
      row(2, { ad_soyad: 'Ali Veli', blok: 'A', daire_no: '1', kullanici_adi: 'benim.adim' }),
      row(3, { ad_soyad: 'Veli Ali', blok: 'A', daire_no: '2', kullanici_adi: 'baska.ad' }),
    ];
    const preview = await previewImport({ siteCode: SITE, kind: 'people', body: body(rows) });
    assert.deepEqual(preview.issues.map((i) => [i.n, i.severity, i.code]), [[2, 'warning', 'LOGIN_COLUMN_IGNORED']]);
    assert.deepEqual(preview.accounts.map((a) => a.login_name), ['ali.veli', 'veli.ali']);
  });

  it('kullanıcı adı denetim ucu servisi: biçim hatası, BU SİTEDE alınmış ad (öneri ile) ve boştaki ad', async () => {
    const { checkImportLoginName } = await import('../src/modules/bulk_import_service.js');
    db.siteLogins = new Set(['ali.veli', 'ali.veli_2']);
    assert.deepEqual(await checkImportLoginName({ siteCode: SITE, body: { login_name: 'Ali Veli' } }), {
      ok: false, login_name: 'ali.veli', code: 'TAKEN', message: 'Bu kullanıcı adı bu sitede başka bir hesapta kayıtlı.', suggestion: 'ali.veli_3',
    });
    assert.equal((await checkImportLoginName({ siteCode: SITE, body: { login_name: 'yeni.ad' } })).ok, true);
    assert.equal((await checkImportLoginName({ siteCode: SITE, body: { login_name: 'a@b' } })).code, 'CHARS');
    assert.equal((await checkImportLoginName({ siteCode: SITE, body: { login_name: 'ab' } })).code, 'TOO_SHORT');
    await assert.rejects(() => checkImportLoginName({ siteCode: SITE, body: { login_name: 5 } }), (error) => error.code === 'INVALID_BODY');
  });

  it('SAYIM AÇIĞI KAPALI (denetim ucu): başka sitede kayıtlı ad «kullanılabilir»; hiç olmayan ad ile birebir aynı yanıt; kendi sitesindeki çakışma yakalanır; site kodu zorunlu', async () => {
    const { checkImportLoginName } = await import('../src/modules/bulk_import_service.js');
    db.siteLogins = new Set(['kendi.sitem']);
    db.takenLogins = new Set(['baska.site']);
    const elsewhere = await checkImportLoginName({ siteCode: SITE, body: { login_name: 'baska.site' } });
    const nowhere = await checkImportLoginName({ siteCode: SITE, body: { login_name: 'hic.yok.boyle' } });
    assert.deepEqual(elsewhere, { ok: true, login_name: 'baska.site', code: 'OK', message: null, suggestion: null });
    assert.deepEqual({ ...elsewhere, login_name: null }, { ...nowhere, login_name: null }, 'yanıt şekli aynı');
    assert.equal((await checkImportLoginName({ siteCode: SITE, body: { login_name: 'kendi.sitem' } })).code, 'TAKEN');
    // başka sitenin yöneticisi için «kendi.sitem» görünmez (kapsam istek sahibinin sitesidir)
    assert.equal((await checkImportLoginName({ siteCode: SITE + 1, body: { login_name: 'kendi.sitem' } })).ok, true);
    await assert.rejects(() => checkImportLoginName({ body: { login_name: 'kendi.sitem' } }), TypeError);
  });

  it('SAYIM AÇIĞI KAPALI (e-posta): başka sitedeki hesabın e-postası önizlemede «yeni hesap»; onayda sistem geneli denetim hesabı AÇMAZ (EMAIL_IN_USE), kişi yazılır, kullanıcı adı harcanmaz', async () => {
    db.emailUsers = { 'baska.site@example.com': { user_code: 91, login_name: 'baska.sakin', linkable: false, sites: [SITE + 1] } };
    const rows = [row(2, { ad_soyad: 'Can Demir', blok: 'A', daire_no: '1', iliski: 'Malik', e_posta: 'baska.site@example.com' })];
    const baselineDb = freshDb();
    const preview = await previewImport({ siteCode: SITE, kind: 'people', body: body(rows) });
    assert.deepEqual(preview.accounts, [{ n: 2, status: 'new', login_name: 'can.demir', editable: true, custom: false }]);
    assert.equal(preview.plan.account_create, 1);
    // e-posta hiç kayıtlı olmasaydı önizleme AYNI olurdu
    const saved = db;
    db = baselineDb;
    const unknown = await previewImport({ siteCode: SITE, kind: 'people', body: body(rows) });
    db = saved;
    assert.deepEqual(preview, unknown);

    const { committed } = await previewAndCommit('people', rows);
    assert.equal(committed.status, 201);
    const accounts = committed.body.result.accounts;
    assert.deepEqual([accounts.created, accounts.linked, accounts.skipped], [0, 0, 1]);
    assert.deepEqual(accounts.skipped_items.map((item) => [item.n, item.code]), [[2, 'EMAIL_IN_USE']]);
    assert.equal(db.users.length, 0, 'başka sitenin e-postasıyla hesap AÇILMAZ');
    assert.equal(committed.body.result.rows.applied, 1, 'kişi kaydı yazıldı');
  });

  it('KENDİ sitesindeki gerçek e-posta çakışması önizlemede raporlanır: bağlanamayan hesap «email_in_use», bağlanabilir hesap «existing»', async () => {
    db.emailUsers = {
      'kendi.yonetici@example.com': { user_code: 55, login_name: 'yonetici', linkable: false },
      'komsu@example.com': { user_code: 77, login_name: 'komsu.hesabi', linkable: true },
    };
    const rows = [
      row(2, { ad_soyad: 'Veli Ali', blok: 'A', daire_no: '1', iliski: 'Malik', e_posta: 'kendi.yonetici@example.com' }),
      row(3, { ad_soyad: 'Can Demir', blok: 'A', daire_no: '2', iliski: 'Malik', e_posta: 'komsu@example.com' }),
    ];
    const preview = await previewImport({ siteCode: SITE, kind: 'people', body: body(rows) });
    assert.deepEqual(preview.accounts.map((a) => [a.n, a.status, a.login_name]), [[2, 'email_in_use', null], [3, 'existing', 'komsu.hesabi']]);
  });

  it('hesap önerisi servisi (tablo için): yalnız kişi türleri; yazmaz', async () => {
    const { previewAccounts } = await import('../src/modules/bulk_import_service.js');
    const suggested = await previewAccounts({ siteCode: SITE, kind: 'people', body: body(PEOPLE_ROWS) });
    assert.deepEqual(suggested.accounts.map((a) => [a.n, a.login_name]), [[2, 'ali.veli'], [3, 'ali.veli_2']]);
    assert.equal(db.log.some((entry) => /^(INSERT|UPDATE|DELETE)/.test(entry.sql)), false);
    await assert.rejects(() => previewAccounts({ siteCode: SITE, kind: 'vehicles', body: body([row(2, { plaka: '34 ABC 123', e_posta: 'a@b.com' })]) }), (error) => error.code === 'IMPORT_KIND_NOT_FOUND');
  });

  it('yalnız bu yüklemede daire ilişkisi eklenen kişilere hesap açılır; yanıt NİHAİ kullanıcı adlarını satır no ile döner', async () => {
    const { preview, committed } = await previewAndCommit('people', PEOPLE_ROWS);
    assert.equal(committed.status, 201);
    const accounts = committed.body.result.accounts;
    assert.deepEqual([accounts.created, accounts.linked, accounts.skipped], [2, 0, 0]);
    // Adlar önizlemede satır sırasıyla verilir (satır 2 ali.veli, satır 3 ali.veli_2) ve yazımda AYNEN korunur; admin önceliği (kiracı önce) yalnız işlem
    // sırasını belirler (sonuç listesi işlem sırasındadır), gösterilen adı değiştirmez.
    assert.deepEqual(accounts.items, [
      { n: 3, login_name: 'ali.veli_2', status: 'created' },
      { n: 2, login_name: 'ali.veli', status: 'created' },
    ]);
    assert.equal(accounts.renamed, 0);
    assert.deepEqual(preview.accounts.map((a) => [a.n, a.login_name]), [[2, 'ali.veli'], [3, 'ali.veli_2']], 'önizlemede gösterilen = yazılan');
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
    // özel şifreli satır 2 (malik): önizlemedeki adı ali.veli; kiracı (satır 3) varsayılan 1234 ile ali.veli_2
    const owner = db.users.find((u) => u.login_name === 'ali.veli');
    const tenant = db.users.find((u) => u.login_name === 'ali.veli_2');
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
    // kiracı (satır 3) önce işlenir ve önizlemedeki adı ali.veli_2'de (kopya olmayan veri hatası) düşer; malik (satır 2) ali.veli ile açılır
    assert.deepEqual(accounts.skipped_items.map((i) => [i.n, i.code]), [[3, 'ACCOUNT_FAILED']]);
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
