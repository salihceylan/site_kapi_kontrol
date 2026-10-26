// Site başvurusu servisi (DB'siz, sıkı sahte istemci): SQL sırası, kilit sırası, ROLLBACK, audit içeriği, e-posta kancaları, yetki kuralları.
// Gerçek PostgreSQL davranışı (yarışlar, kısıtlar, kalıntı bırakmama) scripts/qa_platform_pg.mjs `site_applications` bölümündedir.
import { describe, it, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { pool } from '../src/db.js';
import { isPlatformError } from '../src/modules/errors.js';
import {
  approveSiteApplication,
  assertMayApply,
  cancelMyApplication,
  createSiteApplication,
  getPendingSummary,
  getSiteOnboardingSettings,
  isApplicantUnavailable,
  listAdminApplications,
  listMyApplications,
  rejectSiteApplication,
  setSiteOnboardingMode,
  siteApplicationHooks,
} from '../src/modules/site_application_service.js';
import { setupSiteWithClaimedDevice } from '../src/services/membership_service.js';

const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
const ok = (rows = []) => ({ rows, rowCount: rows.length });

const individual = { id: 48213, user_code: 48213, userCode: 48213, role: 'individual', full_name: 'Ayşe Başvuran', email: 'ayse@example.com' };
const superUser = { id: 1, user_code: 1, userCode: 1, role: 'super_user', full_name: 'Root', email: 'root@example.com' };

const goodBody = {
  name: ' Gül Sitesi ',
  city: 'Ankara',
  district: 'Çankaya',
  address: 'Cadde 1',
  blocks: [{ name: 'A Blok', apartmentCount: 12 }, { name: 'B Blok', apartmentCount: 8 }],
  doors: [{ name: 'Ana Kapı' }, { name: 'Yan Kapı' }],
  note: '  Hızlı olursa sevinirim  ',
};

function storedRow(overrides = {}) {
  return {
    id: '41',
    applicant_user_code: 48213,
    status: 'pending',
    site_name: 'Gül Sitesi',
    city: 'Ankara',
    district: 'Çankaya',
    address: 'Cadde 1',
    management_type: 'apartment_site',
    blocks: [{ name: 'A Blok', apartmentCount: 12, sortOrder: 1 }, { name: 'B Blok', apartmentCount: 8, sortOrder: 2 }],
    doors: [{ name: 'Ana Kapı', doorIndex: 1 }, { name: 'Yan Kapı', doorIndex: 2 }],
    block_count: 2,
    apartment_count: 20,
    door_count: 2,
    device_uid: null,
    note: null,
    plan_code: null,
    payment_status: 'not_required',
    decided_at: null,
    decision_note: null,
    site_code: null,
    created_at: new Date('2026-10-16T07:00:00.000Z'),
    ...overrides,
  };
}

// Sıkı sahte istemci: tanınmayan SQL HATA verir (sessizce boş dönmez); her ifade günlüğe yazılır.
function install(config = {}) {
  const state = {
    role: 'individual',
    mode: 'approval',
    pending: null,
    dailyCount: 0,
    deviceOwned: true,
    ownerLink: false,
    reloadFails: false,
    row: storedRow(),
    applicant: { id: 7, user_code: 48213, role: 'individual', full_name: 'Ayşe Başvuran', email: 'ayse@example.com', is_active: true, email_verified: true, approval_status: 'approved' },
    device: { id: 77, device_uid: 'A0B1C2D3E4F5', hardware_type: 'esp32_wroom' },
    failOn: null,
    insertConflict: false,
    insertConflictConstraint: 'uq_site_applications_pending',
    siteNameExists: false,
    pendingNameExists: false,
    ...config,
  };
  const log = [];
  const poolLog = [];
  const handle = (target) => async (text, params = []) => {
    const sql = norm(text);
    target.push({ sql, params });
    if (state.failOn && state.failOn.test(sql)) {
      throw Object.assign(new Error('SECRET_DB_DETAIL'), { code: 'XX000' });
    }
    if (/^(BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE SAVEPOINT|ROLLBACK TO SAVEPOINT)\b/.test(sql)) return ok();
    if (/^SELECT pg_advisory_xact_lock/.test(sql)) return ok();
    // sahip bağı (userHasOwnerLink) ve mine'ın requires_application rol sorgusu
    if (/^SELECT 1 FROM site_manager_sites m INNER JOIN sites s/.test(sql)) return ok(state.ownerLink ? [{ x: 1 }] : []);
    if (/^SELECT role FROM users WHERE user_code = \$1 LIMIT 1$/.test(sql)) return ok([{ role: state.role }]);
    // başvuran satırı FOR KEY SHARE + deleted_at IS NULL ile okunur (hesap silme yarışı: silinmiş hesaba başvuru yazılmaz)
    if (/^SELECT id, user_code, role, full_name FROM users WHERE user_code = \$1 AND deleted_at IS NULL LIMIT 1 FOR KEY SHARE$/.test(sql)) {
      return ok([{ id: 7, user_code: Number(params[0]), role: state.role, full_name: 'Ayşe Başvuran' }]);
    }
    if (/FROM sites WHERE site_name_key\(name\) = site_name_key\(\$1\) AND approval_status IS DISTINCT FROM 'rejected' LIMIT 1$/.test(sql)) {
      return ok(state.siteNameExists ? [{ site_code: 1, name: params[0] }] : []);
    }
    if (/FROM site_applications WHERE status = 'pending' AND site_name_key\(site_name\) = site_name_key\(\$1\) LIMIT 1$/.test(sql)) {
      return ok(state.pendingNameExists ? [{ id: 1, site_name: params[0] }] : []);
    }
    if (/^SELECT value FROM platform_settings WHERE key = \$1 LIMIT 1$/.test(sql)) return ok([{ value: { mode: state.mode } }]);
    if (/WHERE a\.applicant_user_code = \$1 AND a\.status = 'pending' LIMIT 1$/.test(sql)) return ok(state.pending ? [state.pending] : []);
    if (/WHERE a\.applicant_user_code = \$1 ORDER BY a\.created_at DESC, a\.id DESC LIMIT 10$/.test(sql)) return ok([]);
    if (/^SELECT COUNT\(\*\)::INTEGER AS applied FROM site_applications/.test(sql)) return ok([{ applied: state.dailyCount }]);
    if (/^SELECT id FROM devices WHERE UPPER\(device_uid\) = \$1 AND \(owner_user_id = \$2 OR assigned_user_code = \$3\) LIMIT 1$/.test(sql)) {
      return ok(state.deviceOwned ? [{ id: 77 }] : []);
    }
    if (/^INSERT INTO site_applications /.test(sql)) {
      if (state.insertConflict) throw Object.assign(new Error('duplicate key'), { code: '23505', constraint: state.insertConflictConstraint });
      return ok([{ id: '41', created_at: new Date('2026-10-16T07:00:00.000Z') }]);
    }
    if (/^INSERT INTO audit_log/.test(sql)) return ok();
    // yükleme (sonuç görünümleri): COMMIT SONRASI yeniden okuma; reloadFails ile hata enjekte edilir
    if (state.reloadFails && /WHERE a\.id = \$1 LIMIT 1$/.test(sql)) {
      throw Object.assign(new Error('SECRET_RELOAD_DETAIL'), { code: 'XX000' });
    }
    if (/FROM site_applications a LEFT JOIN users u ON u\.user_code = a\.applicant_user_code LEFT JOIN users d ON d\.user_code = a\.decided_by WHERE a\.id = \$1 LIMIT 1$/.test(sql)) {
      return ok([{ ...state.row, status: 'approved', applicant_name: 'Ayşe Başvuran', applicant_email: 'ayse@example.com', applicant_phone: null, applicant_role: 'site_manager', decided_by_name: 'Root', decision_source: 'super_user', device_available: false }]);
    }
    if (/FROM site_applications a WHERE a\.id = \$1 LIMIT 1$/.test(sql)) return ok([state.row]);
    // onay
    if (/^SELECT applicant_user_code, device_uid FROM site_applications WHERE id = \$1$/.test(sql)) {
      return ok(state.row ? [{ applicant_user_code: state.row.applicant_user_code, device_uid: state.row.device_uid }] : []);
    }
    if (/^SELECT id, user_code FROM users WHERE user_code = \$1 LIMIT 1$/.test(sql)) return ok(state.applicant ? [{ id: 7, user_code: Number(params[0]) }] : []);
    if (/^SELECT \* FROM devices WHERE UPPER\(device_uid\) = \$1 .* AND site_code IS NULL LIMIT 1 FOR UPDATE$/.test(sql)) return ok(state.deviceOwned ? [state.device] : []);
    if (/FROM users WHERE user_code = \$1 LIMIT 1 FOR NO KEY UPDATE$/.test(sql)) return ok(state.applicant ? [state.applicant] : []);
    if (/FROM site_applications a WHERE a\.id = \$1 FOR UPDATE OF a$/.test(sql)) return ok(state.row ? [state.row] : []);
    if (/^INSERT INTO sites/.test(sql)) return ok([{ id: 900, name: params[0], address: params[1], city: params[2], district: params[3], block_count: params[4], apartment_count: params[5], door_count: params[6], approval_status: 'approved', management_type: params[8] }]);
    if (/^UPDATE users SET role/.test(sql)) return { rows: [], rowCount: 1 }; // `deleted_at IS NULL` ister: satır dönmezse (silinmiş hesap) kurulum geri alınır
    if (/^INSERT INTO site_manager_sites/.test(sql) || /^INSERT INTO site_memberships/.test(sql)) return ok();
    if (/^INSERT INTO site_blocks/.test(sql)) return ok([{ id: 30 + Number(params[2]), site_code: 900, block_name: params[1], sort_order: params[2] }]);
    if (/^INSERT INTO apartments/.test(sql)) return ok();
    if (/^INSERT INTO site_doors/.test(sql)) return ok([{ id: 40 + Number(params[2]), site_code: 900, door_name: params[1], door_index: params[2], is_active: true }]);
    if (/^UPDATE devices SET site_code/.test(sql) || /^UPDATE site_doors SET assigned_device_id/.test(sql)) return ok();
    if (/^INSERT INTO site_subscriptions/.test(sql)) return ok();
    if (/^INSERT INTO site_modules/.test(sql)) return ok();
    if (/^UPDATE site_applications SET/.test(sql)) return ok();
    if (/^SELECT full_name, email FROM users WHERE user_code = \$1 LIMIT 1$/.test(sql)) return ok([{ full_name: 'Ayşe Başvuran', email: 'ayse@example.com' }]);
    // iptal
    if (/FROM site_applications a WHERE a\.id = \$1 AND a\.applicant_user_code = \$2 FOR UPDATE OF a$/.test(sql)) {
      return ok(state.row && Number(params[1]) === Number(state.row.applicant_user_code) ? [state.row] : []);
    }
    // ayar
    if (/^SELECT value FROM platform_settings WHERE key = \$1 FOR UPDATE$/.test(sql)) return ok([{ value: { mode: 'approval' } }]);
    if (/^INSERT INTO platform_settings/.test(sql)) return ok();
    if (/FROM subscription_plans/.test(sql)) return ok([{ code: 'manual_approval', name: 'Elle Onaylı', is_active: true, price_minor: null, currency: 'TRY', billing_period: null }]);
    throw new Error(`SAHTE VERITABANI: tanimsiz SQL: ${sql}`);
  };
  const client = { released: false, query: handle(log), release() { client.released = true; } };
  let connects = 0;
  pool.query = handle(poolLog);
  pool.connect = async () => {
    connects += 1;
    return client;
  };
  return { state, log, poolLog, client, connects: () => connects };
}

const has = (log, regex) => log.some((entry) => regex.test(entry.sql));
const find = (log, regex) => log.find((entry) => regex.test(entry.sql));
const indexOfSql = (log, regex) => log.findIndex((entry) => regex.test(entry.sql));

const hooksBackup = { ...siteApplicationHooks };
afterEach(() => {
  delete pool.query;
  delete pool.connect;
  Object.assign(siteApplicationHooks, hooksBackup);
});

const settle = () => new Promise((resolve) => setImmediate(resolve));

async function rejectsWith(promise, status, code) {
  await assert.rejects(
    () => promise,
    (error) => isPlatformError(error) && error.statusCode === status && error.code === code,
    `${status} ${code}`,
  );
}

describe('assertMayApply / isApplicantUnavailable', () => {
  it('başvurabilen: bireysel / daire sahibi ve site yöneticisi; süper ve diğerleri 403 FORBIDDEN_ROLE', () => {
    assertMayApply('individual');
    assertMayApply('apartment_owner');
    assertMayApply('site_manager');
    for (const role of ['super_user', 'staff', undefined, null, '']) {
      assert.throws(() => assertMayApply(role), (e) => e.statusCode === 403 && e.code === 'FORBIDDEN_ROLE', String(role));
    }
  });

  it('başvuran kullanılamaz: yok / pasif / e-postası doğrulanmamış / abonelik onayı bekleyen ya da reddedilen', () => {
    const good = { is_active: true, email_verified: true, approval_status: 'approved' };
    assert.equal(isApplicantUnavailable(good), false);
    assert.equal(isApplicantUnavailable({ ...good, approval_status: null }), false);
    for (const bad of [undefined, null, { ...good, is_active: false }, { ...good, is_active: null }, { ...good, email_verified: false }, { ...good, approval_status: 'pending' }, { ...good, approval_status: 'rejected' }]) {
      assert.equal(isApplicantUnavailable(bad), true, JSON.stringify(bad));
    }
  });
});

describe('createSiteApplication', () => {
  it('rol ve girdi hataları transaction AÇMAZ (bağlantı alınmaz): süper 403, geçersiz girdi 400', async () => {
    const db = install();
    await rejectsWith(createSiteApplication({ actor: superUser, body: goodBody }), 403, 'FORBIDDEN_ROLE');
    await rejectsWith(createSiteApplication({ actor: { ...individual, role: 'staff' }, body: goodBody }), 403, 'FORBIDDEN_ROLE');
    await rejectsWith(createSiteApplication({ actor: individual, body: { ...goodBody, name: '   ' } }), 400, 'INVALID_BODY');
    await rejectsWith(createSiteApplication({ actor: individual, body: { ...goodBody, blocks: Array.from({ length: 101 }, (_, i) => ({ name: 'B' + i, apartmentCount: 1 })) } }), 400, 'INVALID_BODY');
    await rejectsWith(createSiteApplication({ actor: individual, body: { ...goodBody, doors: undefined, doorCount: 101 } }), 400, 'INVALID_BODY');
    await rejectsWith(createSiteApplication({ actor: individual, body: { ...goodBody, note: 'x'.repeat(501) } }), 400, 'INVALID_BODY');
    await rejectsWith(createSiteApplication({ actor: individual, body: { ...goodBody, note: 5 } }), 400, 'INVALID_BODY');
    await rejectsWith(createSiteApplication({ actor: individual, body: { ...goodBody, deviceUid: 'x'.repeat(65) } }), 400, 'INVALID_BODY');
    await rejectsWith(createSiteApplication({ actor: individual, body: { ...goodBody, management_type: 'otel' } }), 400, 'MANAGEMENT_TYPE_INVALID');
    assert.equal(db.connects(), 0);
    assert.equal(db.log.length, 0, 'transaction içinde hiçbir ifade yok');
    // yönetici de başvurur; geçersiz girdi yine bağlantı almadan 400
    await rejectsWith(createSiteApplication({ actor: { ...individual, role: 'site_manager' }, body: { ...goodBody, name: '' } }), 400, 'INVALID_BODY');
    assert.equal(db.connects(), 0);
  });

  it('site yöneticisi de yeni site için başvurur: 201; talep süper kullanıcı onayına düşer', async () => {
    const db = install({ role: 'site_manager' });
    siteApplicationHooks.notifyCreated = async () => {};
    const application = await createSiteApplication({ actor: { ...individual, role: 'site_manager' }, body: goodBody });
    assert.equal(application.id, 41);
    const roleAt = indexOfSql(db.log, /^SELECT id, user_code, role, full_name FROM users/);
    const insertAt = indexOfSql(db.log, /^INSERT INTO site_applications/);
    assert.ok(roleAt >= 0 && insertAt > roleAt, 'sıra: taze rol -> INSERT');
    assert.ok(has(db.log, /^COMMIT/));
  });

  it('güvenli normalizasyon: NUL, eşsiz vekil, yön / görünmez karakter ad / adres / şehirden atılır (JSONB 22P05 / metin 22021 ASLA); sonuç boşsa 400 INVALID_BODY', async () => {
    const lone = String.fromCharCode(0xd800);
    const rlo = String.fromCharCode(0x202e);
    const nul = String.fromCharCode(0);
    const db = install();
    siteApplicationHooks.notifyCreated = async () => {};
    await createSiteApplication({
      actor: individual,
      body: {
        ...goodBody,
        name: ' Gül' + nul + ' Sitesi' + rlo + ' ',
        city: 'Ankara' + lone,
        district: rlo,
        address: 'Cadde' + nul + ' 1\r\nKat 2',
        blocks: [{ name: 'A' + lone + ' Blok' + nul, apartmentCount: 5 }],
        doors: [{ name: 'Ana' + rlo + ' Kapı' }],
        note: 'Not' + nul + lone,
      },
    });
    const insert = find(db.log, /^INSERT INTO site_applications/);
    assert.equal(insert.params[1], 'Gül Sitesi');
    assert.equal(insert.params[2], 'Ankara');
    assert.equal(insert.params[3], null, 'yalnız yön karakterinden oluşan ilçe boş sayılır');
    assert.equal(insert.params[4], 'Cadde 1\nKat 2', 'adreste satır sonu korunur, NUL atılır');
    assert.deepEqual(JSON.parse(insert.params[6]), [{ name: 'A Blok', apartmentCount: 5, sortOrder: 1 }]);
    assert.deepEqual(JSON.parse(insert.params[7]), [{ name: 'Ana Kapı', doorIndex: 1 }]);
    assert.equal(insert.params[12], 'Not');
    // hiçbir parametrede geçersiz karakter kalmaz
    const flat = insert.params.filter((v) => typeof v === 'string').join('');
    assert.equal(Array.from(flat).some((ch) => [0, 0xd800, 0x202e].includes(ch.codePointAt(0))), false);
    const jsonText = insert.params[6] + insert.params[7];
    assert.equal(jsonText.includes('\\' + 'ud800') || jsonText.includes('\\' + 'u0000'), false, 'JSONB metninde geçersiz kaçış dizisi yok');

    for (const bad of [nul, rlo, lone + nul + rlo, '   ', nul + ' ' + nul]) {
      const none = install();
      await rejectsWith(createSiteApplication({ actor: individual, body: { ...goodBody, name: bad } }), 400, 'INVALID_BODY');
      assert.equal(none.connects(), 0, 'boş ad: veritabanına dokunulmaz');
    }
  });
  it('başarı: advisory kilit -> taze rol -> ödeme kipi -> bekleyen -> günlük sayım -> INSERT -> audit -> COMMIT; JSONB ve sayılar normalizeSetupSiteInput çıktısı', async () => {
    const db = install();
    const mailed = [];
    siteApplicationHooks.notifyCreated = async (payload) => { mailed.push(payload); };
    const application = await createSiteApplication({ actor: individual, body: goodBody });

    const order = [/^BEGIN/, /^SELECT pg_advisory_xact_lock/, /^SELECT id, user_code, role, full_name FROM users/, /^SELECT value FROM platform_settings/, /a\.status = 'pending' LIMIT 1$/, /FROM sites WHERE site_name_key\(name\)/, /FROM site_applications WHERE status = 'pending' AND site_name_key\(site_name\)/, /^SELECT COUNT\(\*\)::INTEGER AS applied/, /^INSERT INTO site_applications/, /^INSERT INTO audit_log/, /^COMMIT/];
    const positions = order.map((regex) => indexOfSql(db.log, regex));
    assert.ok(positions.every((p) => p >= 0), JSON.stringify(positions));
    assert.deepEqual([...positions].sort((a, b) => a - b), positions, 'sıra');
    assert.deepEqual(find(db.log, /^SELECT pg_advisory_xact_lock/).params, ['site_application:48213']);
    assert.equal(has(db.log, /FOR UPDATE/), false, 'başvuruda hiçbir satır (cihaz dahil) kilitlenmez');

    const insert = find(db.log, /^INSERT INTO site_applications/);
    assert.equal(insert.params[0], 48213);
    assert.equal(insert.params[1], 'Gül Sitesi', 'ad kırpıldı');
    assert.deepEqual(insert.params.slice(2, 6), ['Ankara', 'Çankaya', 'Cadde 1', 'apartment_site']);
    assert.deepEqual(JSON.parse(insert.params[6]), [{ name: 'A Blok', apartmentCount: 12, sortOrder: 1 }, { name: 'B Blok', apartmentCount: 8, sortOrder: 2 }]);
    assert.deepEqual(JSON.parse(insert.params[7]), [{ name: 'Ana Kapı', doorIndex: 1 }, { name: 'Yan Kapı', doorIndex: 2 }]);
    assert.deepEqual(insert.params.slice(8, 11), [2, 20, 2]);
    assert.equal(insert.params[11], null, 'cihaz verilmedi');
    assert.equal(insert.params[12], 'Hızlı olursa sevinirim', 'not kırpıldı');
    assert.ok(db.client.released);

    // audit: yalnız sayılar ve bayraklar (not / ad / e-posta YOK), site_code yok
    const audit = find(db.log, /^INSERT INTO audit_log/);
    assert.equal(audit.params[3], 'site_application.created');
    assert.equal(audit.params[4], null);
    assert.equal(audit.params[5], 'site_application');
    assert.equal(audit.params[6], '41');
    assert.deepEqual(JSON.parse(audit.params[7]), { block_count: 2, apartment_count: 20, door_count: 2, has_device: false, has_note: true });
    assert.equal(audit.params.join('|').includes('ayse@example.com'), false);
    assert.equal(audit.params.join('|').includes('Hızlı'), false);

    // yanıt: başvuran görünümü (karar kaynağı / veren / başvuran iletişimi yok)
    assert.equal(application.id, 41);
    for (const key of ['decision_source', 'decided_by', 'decided_by_name', 'applicant', 'device_available', 'payment_reference']) {
      assert.equal(key in application, false, key);
    }
    await settle();
    assert.equal(mailed.length, 1);
    assert.equal(mailed[0].applicant_name, 'Ayşe Başvuran');
    assert.equal(mailed[0].site_name, 'Gül Sitesi');
  });

  it('cihaz verilirse yalnız sahiplik doğrulanır (kilitsiz) ve BÜYÜK harfle saklanır; başkasının cihazı 404 DEVICE_NOT_FOUND', async () => {
    let db = install();
    await createSiteApplication({ actor: individual, body: { ...goodBody, deviceUid: ' a0b1c2d3e4f5 ' } });
    const lookup = find(db.log, /^SELECT id FROM devices/);
    assert.deepEqual(lookup.params, ['A0B1C2D3E4F5', 7, 48213]);
    assert.equal(find(db.log, /^INSERT INTO site_applications/).params[11], 'A0B1C2D3E4F5');
    assert.equal(JSON.parse(find(db.log, /^INSERT INTO audit_log/).params[7]).has_device, true);
    assert.equal(has(db.log, /UPDATE devices/), false, 'cihaz ayrılmaz');

    db = install({ deviceOwned: false });
    await rejectsWith(createSiteApplication({ actor: individual, body: { ...goodBody, deviceUid: 'A0B1C2D3E4F5' } }), 404, 'DEVICE_NOT_FOUND');
    assert.equal(has(db.log, /^INSERT INTO site_applications/), false);
    assert.ok(has(db.log, /^ROLLBACK/));
    assert.equal(has(db.log, /^COMMIT/), false);
  });

  it('aynı isimde onaylı/mevcut bir site varsa 409 SITE_NAME_EXISTS fırlatır', async () => {
    install({ siteNameExists: true });
    await assert.rejects(
      createSiteApplication({ actor: individual, body: goodBody }),
      (err) => err?.statusCode === 409 && err?.code === 'SITE_NAME_EXISTS' && /zaten mevcut/i.test(err?.message),
    );
  });

  it('aynı isimde onay bekleyen bir başvuru varsa 409 SITE_APPLICATION_NAME_PENDING fırlatır', async () => {
    install({ pendingNameExists: true });
    await assert.rejects(
      createSiteApplication({ actor: individual, body: goodBody }),
      (err) => err?.statusCode === 409 && err?.code === 'SITE_APPLICATION_NAME_PENDING' && /onay bekleyen/i.test(err?.message),
    );
  });

  it('ad denetimi site_name_key işleviyle yapılır (Türkçe harf / boşluk farkına dayanıklı) ve reddedilmiş siteleri saymaz; her iki sorgu da ham adı parametre alır', async () => {
    const db = install();
    siteApplicationHooks.notifyCreated = async () => {};
    await createSiteApplication({ actor: individual, body: { ...goodBody, name: '  İpek   Sitesi ' } });
    const siteCheck = find(db.log, /FROM sites WHERE site_name_key\(name\)/);
    assert.match(siteCheck.sql, /approval_status IS DISTINCT FROM 'rejected'/);
    // Ad JS'te katlanmaz (yalnız kırpılır); Türkçe harf / çoklu boşluk katlaması DB işlevi site_name_key'dedir.
    assert.deepEqual(siteCheck.params, ['İpek   Sitesi']);
    assert.deepEqual(find(db.log, /FROM site_applications WHERE status = 'pending' AND site_name_key\(site_name\)/).params, ['İpek   Sitesi']);
    assert.equal(has(db.log, /LOWER\(TRIM/), false, 'eski LOWER(TRIM(..)) karşılaştırması kalmadı');
  });

  it('P3: kullanıcının KENDİ bekleyen başvurusu ad denetimlerinden ÖNCE bakılır: aynı adla yeniden başvuran APPLICATION_PENDING alır (ad çakışması değil)', async () => {
    const db = install({ pending: storedRow(), siteNameExists: true, pendingNameExists: true });
    await assert.rejects(
      () => createSiteApplication({ actor: individual, body: goodBody }),
      (error) => error.statusCode === 409 && error.code === 'APPLICATION_PENDING' && error.extra.application.id === 41,
    );
    assert.equal(has(db.log, /FROM sites WHERE site_name_key/), false, 'bekleyen başvuru varken ad sorguları çalışmaz');
    assert.equal(has(db.log, /FROM site_applications WHERE status = 'pending' AND site_name_key/), false);
  });

  it('bekleyen başvuru varsa 409 APPLICATION_PENDING + mevcut başvuru (başvuran görünümü); INSERT yok', async () => {
    const db = install({ pending: storedRow() });
    await assert.rejects(
      () => createSiteApplication({ actor: individual, body: goodBody }),
      (error) => {
        assert.equal(error.statusCode, 409);
        assert.equal(error.code, 'APPLICATION_PENDING');
        assert.equal(error.extra.application.id, 41);
        assert.equal('decision_source' in error.extra.application, false);
        return true;
      },
    );
    assert.equal(has(db.log, /^INSERT INTO site_applications/), false);
    assert.ok(has(db.log, /^ROLLBACK/));
  });

  it('günlük sınır: 24 saatte 5 başvuru (iptal / ret dahil) dolunca 409 APPLICATION_DAILY_LIMIT; 4 iken geçer', async () => {
    let db = install({ dailyCount: 5 });
    await rejectsWith(createSiteApplication({ actor: individual, body: goodBody }), 409, 'APPLICATION_DAILY_LIMIT');
    assert.equal(has(db.log, /^INSERT INTO site_applications/), false);
    assert.match(find(db.log, /^SELECT COUNT/).sql, /created_at > NOW\(\) - INTERVAL '24 hours'/);
    assert.equal(/status/.test(find(db.log, /^SELECT COUNT/).sql), false, 'durumdan bağımsız sayılır');
    db = install({ dailyCount: 4 });
    await createSiteApplication({ actor: individual, body: goodBody });
    assert.ok(has(db.log, /^INSERT INTO site_applications/));
  });

  it('ödeme kipi (bugün olmaz) 409 PAYMENT_NOT_AVAILABLE; taze rol değişmişse: yönetici + sahip bağı 409 ALREADY_SITE_MANAGER, yönetici bağsız başvurabilir, süper 403', async () => {
    siteApplicationHooks.notifyCreated = async () => {};
    let db = install({ mode: 'payment' });
    await rejectsWith(createSiteApplication({ actor: individual, body: goodBody }), 409, 'PAYMENT_NOT_AVAILABLE');
    assert.equal(has(db.log, /^INSERT INTO site_applications/), false);
    db = install({ role: 'site_manager' });
    assert.equal((await createSiteApplication({ actor: individual, body: goodBody })).id, 41);
    db = install({ role: 'super_user' });
    await rejectsWith(createSiteApplication({ actor: individual, body: goodBody }), 403, 'FORBIDDEN_ROLE');
    assert.ok(db.client.released);
  });
  it('tekil indeks ihlali (23505, uq_site_applications_pending) bekleyen başvuru olarak yanıtlanır; ROLLBACK; bağlantı bırakılır', async () => {
    const db = install({ insertConflict: true, pending: null });
    await rejectsWith(createSiteApplication({ actor: individual, body: goodBody }), 409, 'APPLICATION_PENDING');
    assert.ok(has(db.log, /^ROLLBACK/));
    assert.equal(has(db.log, /^COMMIT/), false);
    assert.ok(db.client.released);
  });

  it('23505 error.constraint ile ayrılır: site adı indeksleri (yeni ve eski ad) SITE_NAME_EXISTS, bekleyen başvuru adı indeksleri SITE_APPLICATION_NAME_PENDING; bilinmeyen kısıt olduğu gibi yükselir', async () => {
    for (const constraint of ['uq_sites_name_key', 'idx_sites_unique_name']) {
      const db = install({ insertConflict: true, insertConflictConstraint: constraint });
      await rejectsWith(createSiteApplication({ actor: individual, body: goodBody }), 409, 'SITE_NAME_EXISTS');
      assert.ok(has(db.log, /^ROLLBACK/), constraint);
    }
    for (const constraint of ['uq_site_applications_pending_name_key', 'idx_site_applications_pending_unique_name']) {
      install({ insertConflict: true, insertConflictConstraint: constraint });
      await rejectsWith(createSiteApplication({ actor: individual, body: goodBody }), 409, 'SITE_APPLICATION_NAME_PENDING');
    }
    install({ insertConflict: true, insertConflictConstraint: 'baska_kisit' });
    await assert.rejects(
      createSiteApplication({ actor: individual, body: goodBody }),
      (error) => !isPlatformError(error) && error.code === '23505',
    );
  });

  it('başvuran hesabı eşzamanlı silinirse (FK 23503) 404 USER_NOT_FOUND; ayrıntı sızmaz', async () => {
    install({ failOn: /^INSERT INTO site_applications/ });
    pool.connect = async () => {
      const base = { released: false, release() { base.released = true; } };
      base.query = async (text, params = []) => {
        const sql = norm(text);
        if (/^INSERT INTO site_applications/.test(sql)) {
          throw Object.assign(new Error('insert violates foreign key constraint SECRET'), { code: '23503' });
        }
        if (/^SELECT id, user_code, role, full_name FROM users/.test(sql)) return ok([{ id: 7, user_code: Number(params[0]), role: 'individual', full_name: 'A' }]);
        if (/^SELECT value FROM platform_settings/.test(sql)) return ok([{ value: { mode: 'approval' } }]);
        if (/^SELECT COUNT/.test(sql)) return ok([{ applied: 0 }]);
        return ok();
      };
      return base;
    };
    await assert.rejects(
      () => createSiteApplication({ actor: individual, body: goodBody }),
      (error) => isPlatformError(error) && error.statusCode === 404 && error.code === 'USER_NOT_FOUND' && !/SECRET/.test(error.message),
    );
  });

  it('beklenmeyen DB hatası olduğu gibi yukarı çıkar (ROLLBACK, COMMIT yok)', async () => {
    const db = install({ failOn: /^INSERT INTO site_applications/ });
    await assert.rejects(() => createSiteApplication({ actor: individual, body: goodBody }), (e) => e.code === 'XX000');
    assert.ok(has(db.log, /^ROLLBACK/));
    assert.equal(has(db.log, /^COMMIT/), false);
    assert.ok(db.client.released);
  });

  it('e-posta kancası yavaş ya da hatalı olsa da istek BEKLEMEZ ve bozulmaz', async () => {
    install();
    const errors = [];
    const original = console.error;
    console.error = (...args) => errors.push(args.map(String).join(' '));
    try {
      siteApplicationHooks.notifyCreated = () => new Promise(() => {}); // asla bitmez
      const started = Date.now();
      const application = await createSiteApplication({ actor: individual, body: goodBody });
      assert.equal(application.id, 41);
      assert.ok(Date.now() - started < 1000);

      install();
      siteApplicationHooks.notifyCreated = async () => {
        throw Object.assign(new Error('550 <ali@example.com>: Recipient address rejected'), { code: 'EENVELOPE' });
      };
      assert.equal((await createSiteApplication({ actor: individual, body: goodBody })).id, 41);
      await settle();
      await settle();
      assert.ok(errors.some((line) => line.includes('EENVELOPE')));
      assert.equal(errors.join('\n').includes('ali@example.com'), false, 'adres log\'a yazılmaz');
    } finally {
      console.error = original;
    }
  });
});

describe('listMyApplications / cancelMyApplication', () => {
  it('mine: yalnız çağıranın kayıtları (WHERE applicant_user_code = $1), son 10; requires_application; geçersiz kullanıcı boş', async () => {
    const db = install();
    const result = await listMyApplications(48213);
    assert.deepEqual(result.items.length, 0);
    assert.equal(result.pending, null);
    assert.equal(result.requires_application, true, 'bireysel kullanıcı anlık kuramaz');
    const listQueries = db.poolLog.filter((entry) => /FROM site_applications a/.test(entry.sql));
    assert.equal(listQueries.length, 2);
    for (const entry of db.poolLog) {
      assert.deepEqual(entry.params, [48213]);
    }
    for (const entry of listQueries) {
      assert.match(entry.sql, /WHERE a\.applicant_user_code = \$1/);
    }
    assert.match(listQueries[0].sql, /ORDER BY a\.created_at DESC, a\.id DESC LIMIT 10$/);
    assert.deepEqual(await listMyApplications('abc'), { pending: null, items: [], requires_application: false });
  });

  it('mine.requires_application: super_user hariç tüm roller (site_manager dahil) true; super false', async () => {
    const cases = [
      ['individual', false, true],
      ['apartment_owner', false, true],
      ['site_manager', false, true],
      ['site_manager', true, true],
      ['super_user', false, false],
      ['super_user', true, false],
      ['staff', false, false],
      [undefined, false, false],
    ];
    for (const [role, ownerLink, expected] of cases) {
      const db = install({ role, ownerLink });
      const result = await listMyApplications(48213);
      assert.equal(result.requires_application, expected, role + ' ' + ownerLink);
      assert.deepEqual(Object.keys(result), ['pending', 'items', 'requires_application']);
    }
  });
  it('iptal: kendi bekleyen başvurusu cancelled olur (audit: yalnız sayılar); başkasının / olmayan 404; bekleyen değilse 409; ROLLBACK', async () => {
    let db = install({ row: storedRow() });
    const cancelled = await cancelMyApplication({ applicationId: 41, actor: individual });
    assert.equal(cancelled.id, 41);
    const select = find(db.log, /FROM site_applications a WHERE a\.id = \$1 AND a\.applicant_user_code = \$2 FOR UPDATE OF a$/);
    assert.deepEqual(select.params, [41, 48213], 'başvuran kodu sorguda: IDOR 404');
    assert.ok(
      indexOfSql(db.log, /FROM users WHERE user_code = \$1 LIMIT 1 FOR NO KEY UPDATE$/) < indexOfSql(db.log, /FROM site_applications a WHERE a\.id = \$1 AND a\.applicant_user_code = \$2 FOR UPDATE OF a$/),
      'kilit sırası: önce kullanıcı satırı, sonra başvuru satırı (hesap silme ile ters sıra deadlock\'u yok)',
    );
    assert.match(find(db.log, /^UPDATE site_applications SET status = 'cancelled'/).sql, /decided_at = NOW\(\)/);
    assert.equal(has(db.log, /decided_by|decision_source/), false, 'iptalde karar veren / kaynak yazılmaz');
    assert.deepEqual(JSON.parse(find(db.log, /^INSERT INTO audit_log/).params[7]), { block_count: 2, apartment_count: 20, door_count: 2 });
    assert.equal(find(db.log, /^INSERT INTO audit_log/).params[3], 'site_application.cancelled');

    db = install({ row: storedRow({ applicant_user_code: 99999 }) });
    await rejectsWith(cancelMyApplication({ applicationId: 41, actor: individual }), 404, 'APPLICATION_NOT_FOUND');
    assert.equal(has(db.log, /^UPDATE site_applications/), false);
    assert.ok(has(db.log, /^ROLLBACK/));

    db = install({ row: storedRow({ status: 'approved' }) });
    await rejectsWith(cancelMyApplication({ applicationId: 41, actor: individual }), 409, 'APPLICATION_NOT_PENDING');
    assert.equal(has(db.log, /^UPDATE site_applications/), false);

    db = install();
    await rejectsWith(cancelMyApplication({ applicationId: 'abc', actor: individual }), 404, 'APPLICATION_NOT_FOUND');
    assert.equal(db.connects(), 0);
  });
});

describe('approveSiteApplication', () => {
  it('KİLİT SIRASI: advisory -> cihaz FOR UPDATE -> başvuran FOR NO KEY UPDATE -> başvuru FOR UPDATE -> yeni site satırları -> COMMIT (gerçek hesap silme akışıyla aynı: cihaz önce)', async () => {
    const db = install({ row: storedRow({ device_uid: 'A0B1C2D3E4F5' }) });
    await approveSiteApplication({ applicationId: 41, note: 'Uygun', actor: superUser });
    const sequence = [
      /^BEGIN/,
      /^SELECT applicant_user_code, device_uid FROM site_applications WHERE id = \$1$/,
      /^SELECT pg_advisory_xact_lock/,
      /^SELECT id, user_code FROM users WHERE user_code = \$1 LIMIT 1$/,
      /^SELECT \* FROM devices .* FOR UPDATE$/,
      /FROM users WHERE user_code = \$1 LIMIT 1 FOR NO KEY UPDATE$/,
      /FROM site_applications a WHERE a\.id = \$1 FOR UPDATE OF a$/,
      /^INSERT INTO sites/,
      /^INSERT INTO site_manager_sites/,
      /^INSERT INTO site_memberships/,
      /^UPDATE users SET role = 'site_manager' WHERE id = \$1 AND deleted_at IS NULL$/,
      /^INSERT INTO site_blocks/,
      /^INSERT INTO apartments/,
      /^INSERT INTO site_doors/,
      /^UPDATE devices SET site_code/,
      /^UPDATE site_doors SET assigned_device_id/,
      /^INSERT INTO site_subscriptions/,
      /^UPDATE site_applications SET status = 'approved'/,
      /^INSERT INTO audit_log/,
      /^COMMIT/,
    ];
    const positions = sequence.map((regex) => indexOfSql(db.log, regex));
    assert.ok(positions.every((p) => p >= 0), JSON.stringify(positions));
    assert.deepEqual([...positions].sort((a, b) => a - b), positions);
    assert.deepEqual(find(db.log, /^SELECT pg_advisory_xact_lock/).params, ['site_application:48213'], 'oluşturma ile ORTAK anahtar');
    // cihaz sorgusu başvuranın (kilitsiz okunan) kimliklerini kullanır; kullanıcı satırı cihazdan SONRA kilitlenir
    assert.deepEqual(find(db.log, /^SELECT \* FROM devices/).params, ['A0B1C2D3E4F5', 7, 48213]);
    // yönetici bağı 'owner' (ortak çekirdek); abonelik satırı çekirdeğin son ifadesi
    assert.match(find(db.log, /^INSERT INTO site_manager_sites/).sql, /VALUES \(\$1, \$2, 'owner'\)/);
    assert.ok(db.client.released);
  });
  it('başarı: abonelik satırı, başvuru güncellemesi, audit (site_code dolu, details yalnız sayı / bayrak) ve yanıt', async () => {
    const mailed = [];
    install({ row: storedRow({ device_uid: 'A0B1C2D3E4F5' }) });
    siteApplicationHooks.notifyDecided = async (payload) => { mailed.push(payload); };
    const db = install({ row: storedRow({ device_uid: 'A0B1C2D3E4F5' }) });
    const result = await approveSiteApplication({ applicationId: 41, note: '  Uygun  ', actor: superUser });

    assert.deepEqual(find(db.log, /^INSERT INTO site_subscriptions/).params, [900, 'manual_approval', 'manual_approval', 41]);
    assert.match(find(db.log, /^INSERT INTO site_subscriptions/).sql, /VALUES \(\$1, \$2, 'active', \$3, \$4\)/);
    const update = find(db.log, /^UPDATE site_applications SET status = 'approved'/);
    assert.deepEqual(update.params, [41, 1, 'Uygun', 900]);
    assert.match(update.sql, /decision_source = 'super_user'/);
    const audit = find(db.log, /^INSERT INTO audit_log/);
    assert.equal(audit.params[3], 'site_application.approved');
    assert.equal(audit.params[4], 900, 'site_code dolu');
    assert.equal(audit.params[6], '41');
    assert.deepEqual(JSON.parse(audit.params[7]), { block_count: 2, apartment_count: 20, door_count: 2, device_attached: true });
    assert.equal(audit.params.join('|').includes('Uygun'), false, 'karar notu audit\'e yazılmaz');
    assert.equal(audit.params.join('|').includes('ayse@example.com'), false);

    assert.equal(result.device_attached, true);
    assert.equal(result.site.site_code, 900);
    assert.equal(result.site.device_attached, true);
    assert.equal(result.site.block_count, 2);
    assert.equal(result.site.apartment_count, 20);
    assert.deepEqual(result.site.assigned_device, { device_uid: 'A0B1C2D3E4F5', hardware_type: 'esp32_wroom' });
    assert.equal(result.application.id, 41);
    assert.equal(result.application.applicant.email, 'ayse@example.com', 'süper yanıtı başvuran iletişimini içerir');
    await settle();
  });

  it('onay e-postası başvurana gider (adres yalnız kancaya, log\'a değil) ve isteği beklemez', async () => {
    const mailed = [];
    install({ row: storedRow() });
    siteApplicationHooks.notifyDecided = (payload) => { mailed.push(payload); return new Promise(() => {}); };
    await approveSiteApplication({ applicationId: 41, actor: superUser });
    await settle();
    assert.equal(mailed.length, 1);
    assert.deepEqual(mailed[0], { to: 'ayse@example.com', fullName: 'Ayşe Başvuran', siteName: 'Gül Sitesi', approved: true, reason: null });
  });

  it('cihazsız başvuru: cihaz sorgusu / bağlama yok, device_attached false', async () => {
    const db = install({ row: storedRow({ device_uid: null }) });
    const result = await approveSiteApplication({ applicationId: 41, actor: superUser });
    assert.equal(has(db.log, /FROM devices/), false);
    assert.equal(has(db.log, /^UPDATE devices/), false);
    assert.equal(result.device_attached, false);
    assert.equal(result.site.device_attached, false);
    assert.equal(result.site.assigned_device, null);
    assert.deepEqual(JSON.parse(find(db.log, /^INSERT INTO audit_log/).params[7]).device_attached, false);
  });

  it('cihaz artık başvuranın değilse (ya da bir siteye bağlıysa) site cihazsız kurulur: 409 DEĞİL, device_attached false, cihaz güncellenmez', async () => {
    const db = install({ row: storedRow({ device_uid: 'A0B1C2D3E4F5' }), deviceOwned: false });
    const result = await approveSiteApplication({ applicationId: 41, actor: superUser });
    const lookup = find(db.log, /^SELECT \* FROM devices/);
    assert.deepEqual(lookup.params, ['A0B1C2D3E4F5', 7, 48213]);
    assert.match(lookup.sql, /site_code IS NULL/, 'başka siteye bağlı cihaz kapıdan koparılmaz');
    assert.equal(has(db.log, /^UPDATE devices/), false);
    assert.equal(has(db.log, /^UPDATE site_doors SET assigned_device_id/), false);
    assert.equal(result.device_attached, false);
    assert.ok(has(db.log, /^COMMIT/));
  });

  it('süper kullanıcı başvuran: rol güncellenmez (UPDATE users yok)', async () => {
    const db = install({ row: storedRow(), applicant: { id: 7, user_code: 48213, role: 'super_user', full_name: 'S', email: 's@example.com', is_active: true, email_verified: true, approval_status: 'approved' } });
    await approveSiteApplication({ applicationId: 41, actor: superUser });
    assert.equal(has(db.log, /^UPDATE users/), false);
    assert.ok(has(db.log, /^INSERT INTO site_manager_sites/));
  });

  it('bekleyen değilse 409 APPLICATION_NOT_PENDING: site kurulmaz, ROLLBACK (çift tıklama / yarış)', async () => {
    for (const status of ['approved', 'rejected', 'cancelled']) {
      const db = install({ row: storedRow({ status }) });
      await rejectsWith(approveSiteApplication({ applicationId: 41, actor: superUser }), 409, 'APPLICATION_NOT_PENDING');
      assert.equal(has(db.log, /^INSERT INTO sites/), false, status);
      assert.equal(has(db.log, /^INSERT INTO site_subscriptions/), false, status);
      assert.ok(has(db.log, /^ROLLBACK/));
      assert.equal(has(db.log, /^COMMIT/), false);
    }
  });

  it('olmayan başvuru 404; geçersiz kimlik 404 (veritabanına dokunmaz)', async () => {
    let db = install({ row: null });
    await rejectsWith(approveSiteApplication({ applicationId: 41, actor: superUser }), 404, 'APPLICATION_NOT_FOUND');
    assert.ok(has(db.log, /^ROLLBACK/));
    db = install();
    await rejectsWith(approveSiteApplication({ applicationId: 0, actor: superUser }), 404, 'APPLICATION_NOT_FOUND');
    assert.equal(db.connects(), 0);
  });

  it('başvuran silinmiş / pasif / doğrulanmamış: 409 APPLICANT_UNAVAILABLE, başvuru pending KALIR (ret edilebilir), site kurulmaz', async () => {
    const cases = {
      'hesap silinmiş': { applicant: null },
      'başvuran kodu NULL': { row: storedRow({ applicant_user_code: null }) },
      'pasif': { applicant: { id: 7, user_code: 48213, role: 'individual', is_active: false, email_verified: true, approval_status: 'approved' } },
      'e-posta doğrulanmamış': { applicant: { id: 7, user_code: 48213, role: 'individual', is_active: true, email_verified: false, approval_status: 'approved' } },
    };
    for (const [label, config] of Object.entries(cases)) {
      const db = install(config);
      await rejectsWith(approveSiteApplication({ applicationId: 41, actor: superUser }), 409, 'APPLICANT_UNAVAILABLE');
      assert.equal(has(db.log, /^INSERT INTO sites/), false, label);
      assert.equal(has(db.log, /^UPDATE site_applications/), false, label);
      assert.ok(has(db.log, /^ROLLBACK/), label);
    }
  });

  it('saklanan yapı bozuksa 422 APPLICATION_DATA_INVALID: site kurulmaz, ROLLBACK, başvuru pending kalır', async () => {
    const bad = [
      storedRow({ blocks: [] }),
      storedRow({ blocks: 'bozuk{' }),
      storedRow({ doors: null }),
      storedRow({ apartment_count: 99 }),
      storedRow({ blocks: [{ name: 'A', apartmentCount: 'on' }] }),
    ];
    for (const row of bad) {
      const db = install({ row });
      await rejectsWith(approveSiteApplication({ applicationId: 41, actor: superUser }), 422, 'APPLICATION_DATA_INVALID');
      assert.equal(has(db.log, /^INSERT INTO sites/), false);
      assert.equal(has(db.log, /^UPDATE site_applications/), false);
      assert.ok(has(db.log, /^ROLLBACK/));
      assert.equal(has(db.log, /^COMMIT/), false);
    }
  });

  it('yarıda hata (herhangi bir adımda): ROLLBACK, COMMIT YOK, bağlantı bırakılır, hata sızdırılmaz biçimde yukarı çıkar', async () => {
    const steps = [/^INSERT INTO sites/, /^INSERT INTO site_manager_sites/, /^INSERT INTO site_memberships/, /^UPDATE users SET role/, /^INSERT INTO site_blocks/, /^INSERT INTO apartments/, /^INSERT INTO site_doors/, /^UPDATE devices SET site_code/, /^INSERT INTO site_modules/, /^INSERT INTO site_subscriptions/, /^UPDATE site_applications SET status = 'approved'/];
    for (const failOn of steps) {
      const db = install({ row: storedRow({ device_uid: 'A0B1C2D3E4F5' }), failOn });
      await assert.rejects(() => approveSiteApplication({ applicationId: 41, actor: superUser }), (error) => error.code === 'XX000' && !isPlatformError(error), String(failOn));
      assert.ok(has(db.log, /^ROLLBACK/), String(failOn));
      assert.equal(has(db.log, /^COMMIT/), false, String(failOn));
      assert.ok(db.client.released, String(failOn));
    }
  });

  it('karar notu ≤ 300 karakter, metin olmalı: aksi 400 INVALID_BODY (veritabanına dokunmaz)', async () => {
    const db = install();
    await rejectsWith(approveSiteApplication({ applicationId: 41, note: 'x'.repeat(301), actor: superUser }), 400, 'INVALID_BODY');
    await rejectsWith(approveSiteApplication({ applicationId: 41, note: 7, actor: superUser }), 400, 'INVALID_BODY');
    assert.equal(db.connects(), 0);
  });

  it('ANLIK KURULUMLA AYNI çekirdek: site..kapı..cihaz..abonelik SQL ifadeleri ve parametreleri birebir aynı (yalnız abonelik kaynağı / başvuru kimliği farklı)', async () => {
    const coreRegex = /^(INSERT INTO sites|INSERT INTO site_manager_sites|INSERT INTO site_memberships|UPDATE users SET role|INSERT INTO site_blocks|INSERT INTO apartments|INSERT INTO site_doors|UPDATE devices SET site_code|UPDATE site_doors SET assigned_device_id|INSERT INTO site_modules|INSERT INTO site_subscriptions)/;
    const coreOf = (log) => log.filter((entry) => coreRegex.test(entry.sql)).map((entry) => ({ sql: entry.sql, params: entry.params }));

    const approved = install({ row: storedRow({ device_uid: 'A0B1C2D3E4F5' }), applicant: { id: 7, user_code: 48213, role: 'super_user', full_name: 'Ayşe Başvuran', email: 'ayse@example.com', is_active: true, email_verified: true, approval_status: 'approved' } });
    await approveSiteApplication({ applicationId: 41, actor: superUser });
    const fromApproval = coreOf(approved.log);

    // anlık yol: süper kullanıcı ve aynı girdi; cihaz sahibi
    pool.query = async (text) => {
      const sql = norm(text);
      if (/^SELECT role FROM users/.test(sql)) return ok([{ role: 'super_user' }]);
      if (/site_manager_sites m INNER JOIN/.test(sql)) return ok([{ x: 1 }]);
      return ok();
    };
    const instantLog = [];
    const instantClient = {
      released: false,
      release() { this.released = true; },
      query: async (text, params = []) => {
        const sql = norm(text);
        instantLog.push({ sql, params });
        if (/^SELECT id, user_code, role, full_name, email FROM users/.test(sql)) return ok([{ id: 7, user_code: 48213, role: 'super_user', full_name: 'A', email: 'a@example.com' }]);
        if (/site_manager_sites m INNER JOIN/.test(sql)) return ok([{ x: 1 }]);
        if (/^UPDATE users SET role/.test(sql)) return { rows: [], rowCount: 1 };
        if (/^SELECT \* FROM devices/.test(sql)) return ok([{ id: 77, device_uid: 'A0B1C2D3E4F5', hardware_type: 'esp32_wroom' }]);
        if (/^INSERT INTO sites/.test(sql)) return ok([{ id: 900, name: params[0], address: params[1], city: params[2], district: params[3], block_count: params[4], apartment_count: params[5], door_count: params[6], approval_status: 'approved', management_type: params[8] }]);
        if (/^INSERT INTO site_blocks/.test(sql)) return ok([{ id: 30 + Number(params[2]), site_code: 900, block_name: params[1], sort_order: params[2] }]);
        if (/^INSERT INTO site_doors/.test(sql)) return ok([{ id: 40 + Number(params[2]), site_code: 900, door_name: params[1], door_index: params[2], is_active: true }]);
        return ok();
      },
    };
    pool.connect = async () => instantClient;
    await setupSiteWithClaimedDevice({
      userCode: 48213,
      name: 'Gül Sitesi',
      city: 'Ankara',
      district: 'Çankaya',
      address: 'Cadde 1',
      blocks: [{ name: 'A Blok', apartmentCount: 12 }, { name: 'B Blok', apartmentCount: 8 }],
      doors: [{ name: 'Ana Kapı' }, { name: 'Yan Kapı' }],
      deviceUid: 'A0B1C2D3E4F5',
    });
    const fromInstant = coreOf(instantLog);
    assert.ok(fromInstant.length >= 10);
    const isSubscription = (entry) => /^INSERT INTO site_subscriptions/.test(entry.sql);
    assert.deepEqual(fromApproval.filter((entry) => !isSubscription(entry)), fromInstant.filter((entry) => !isSubscription(entry)));
    // abonelik: aynı SQL; anlık yolda source 'admin' ve application_id yok, onayda 'manual_approval' + başvuru kimliği
    const [approvalSubscription] = fromApproval.filter(isSubscription);
    const [instantSubscription] = fromInstant.filter(isSubscription);
    assert.equal(approvalSubscription.sql, instantSubscription.sql);
    assert.deepEqual(approvalSubscription.params, [900, 'manual_approval', 'manual_approval', 41]);
    assert.deepEqual(instantSubscription.params, [900, 'manual_approval', 'admin', null]);
  });
});

describe('rejectSiteApplication', () => {
  it('reddeder: gerekçe kırpılır ve kaydedilir; audit yalnız has_reason; başvurana e-posta kancası (gerekçeli)', async () => {
    const mailed = [];
    const db = install({ row: storedRow() });
    siteApplicationHooks.notifyDecided = async (payload) => { mailed.push(payload); };
    const application = await rejectSiteApplication({ applicationId: 41, reason: '  Eksik belge  ', actor: superUser });
    assert.equal(application.id, 41);
    const update = find(db.log, /^UPDATE site_applications SET status = 'rejected'/);
    assert.deepEqual(update.params, [41, 1, 'Eksik belge']);
    assert.match(update.sql, /decision_source = 'super_user'/);
    const audit = find(db.log, /^INSERT INTO audit_log/);
    assert.equal(audit.params[3], 'site_application.rejected');
    assert.equal(audit.params[4], null);
    assert.deepEqual(JSON.parse(audit.params[7]), { has_reason: true });
    assert.equal(audit.params.join('|').includes('Eksik belge'), false);
    assert.equal(has(db.log, /INSERT INTO sites|site_subscriptions/), false);
    await settle();
    assert.deepEqual(mailed, [{ to: 'ayse@example.com', fullName: 'Ayşe Başvuran', siteName: 'Gül Sitesi', approved: false, reason: 'Eksik belge' }]);
  });

  it('gerekçesiz ret (null), bekleyen değilse 409, olmayan 404, gerekçe > 300 -> 400', async () => {
    let db = install({ row: storedRow() });
    await rejectSiteApplication({ applicationId: 41, actor: superUser });
    assert.equal(find(db.log, /^UPDATE site_applications SET status = 'rejected'/).params[2], null);
    assert.equal(JSON.parse(find(db.log, /^INSERT INTO audit_log/).params[7]).has_reason, false);

    db = install({ row: storedRow({ status: 'approved' }) });
    await rejectsWith(rejectSiteApplication({ applicationId: 41, actor: superUser }), 409, 'APPLICATION_NOT_PENDING');
    assert.equal(has(db.log, /^UPDATE site_applications/), false);
    db = install({ row: null });
    await rejectsWith(rejectSiteApplication({ applicationId: 41, actor: superUser }), 404, 'APPLICATION_NOT_FOUND');
    db = install();
    await rejectsWith(rejectSiteApplication({ applicationId: 41, reason: 'x'.repeat(301), actor: superUser }), 400, 'INVALID_BODY');
    assert.equal(db.connects(), 0);
  });
});

describe('COMMIT sonrası yeniden okuma hatası işlemi BOZMAZ (asgari başarılı yanıt, bildirim okumaya bağlı değil)', () => {
  async function withSilencedErrors(run) {
    const original = console.error;
    const lines = [];
    console.error = (...args) => lines.push(args.map(String).join(' '));
    try {
      return { result: await run(), lines };
    } finally {
      console.error = original;
    }
  }

  it('oluşturma: yeniden okuma hatası 500 yapmaz; yanıt COMMIT edilen değerlerden hazırlanır; bildirim yine gider', async () => {
    const db = install({ reloadFails: true });
    const mailed = [];
    siteApplicationHooks.notifyCreated = async (payload) => { mailed.push(payload); };
    const { result, lines } = await withSilencedErrors(() => createSiteApplication({ actor: individual, body: goodBody }));
    assert.ok(has(db.log, /^COMMIT/));
    assert.equal(result.id, 41);
    assert.equal(result.status, 'pending');
    assert.equal(result.site_name, 'Gül Sitesi');
    assert.equal(result.created_at, '2026-10-16T07:00:00.000Z', 'created_at INSERT ... RETURNING değerinden');
    assert.deepEqual(result.blocks, [{ name: 'A Blok', apartment_count: 12 }, { name: 'B Blok', apartment_count: 8 }]);
    assert.equal(result.block_count + result.apartment_count + result.door_count, 24);
    for (const key of ['decision_source', 'decided_by', 'applicant', 'payment_reference', 'device_available']) {
      assert.equal(key in result, false, key);
    }
    await settle();
    assert.equal(mailed.length, 1, 'bildirim okuma başarısına bağlı değil');
    assert.equal(mailed[0].id, 41);
    assert.ok(lines.some((line) => line.includes('XX000')));
    assert.equal(lines.join('\n').includes('SECRET_RELOAD_DETAIL'), false, 'ayrıntı loga yazılmaz (yalnız kod)');
  });

  it('iptal: yeniden okuma hatasında cancelled asgari yanıt', async () => {
    const db = install({ row: storedRow(), reloadFails: true });
    const { result } = await withSilencedErrors(() => cancelMyApplication({ applicationId: 41, actor: individual }));
    assert.ok(has(db.log, /^COMMIT/));
    assert.equal(result.id, 41);
    assert.equal(result.status, 'cancelled');
    assert.ok(result.decided_at);
    assert.equal('decision_source' in result, false);
  });

  it('onay: yeniden okuma hatasında site + application asgari yanıtla 200 (device_attached dahil), e-posta gider', async () => {
    const mailed = [];
    const db = install({ row: storedRow({ device_uid: 'A0B1C2D3E4F5' }), reloadFails: true });
    siteApplicationHooks.notifyDecided = async (payload) => { mailed.push(payload); };
    const { result } = await withSilencedErrors(() => approveSiteApplication({ applicationId: 41, note: 'Tamam', actor: superUser }));
    assert.ok(has(db.log, /^COMMIT/));
    assert.equal(result.application.status, 'approved');
    assert.equal(result.application.site_code, 900);
    assert.equal(result.application.decision_source, 'super_user');
    assert.equal(result.application.decision_note, 'Tamam');
    assert.equal(result.application.decided_by_name, 'Root');
    assert.equal(result.application.applicant.email, 'ayse@example.com');
    assert.equal(result.site.site_code, 900);
    assert.equal(result.device_attached, true);
    await settle();
    assert.equal(mailed.length, 1);
    assert.equal(mailed[0].approved, true);
  });

  it('ret: yeniden okuma hatasında rejected asgari yanıt, e-posta gider', async () => {
    const mailed = [];
    const db = install({ row: storedRow(), reloadFails: true });
    siteApplicationHooks.notifyDecided = async (payload) => { mailed.push(payload); };
    const { result } = await withSilencedErrors(() => rejectSiteApplication({ applicationId: 41, reason: 'Eksik', actor: superUser }));
    assert.ok(has(db.log, /^COMMIT/));
    assert.equal(result.status, 'rejected');
    assert.equal(result.decision_note, 'Eksik');
    assert.equal(result.decision_source, 'super_user');
    await settle();
    assert.deepEqual(mailed.map((m) => m.approved), [false]);
  });
});

describe('süper kullanıcı listeleri ve ayar', () => {
  it('liste: varsayılan pending, 30, offset 0; q yalnız parametre (joker kaçışlı); geçersiz süzgeç 400 (veritabanına dokunmaz)', async () => {
    const db = install();
    // liste ve sayım sorguları tanımsız: yalnız parametreleri yakalamak için havuz sorgusunu değiştir
    const captured = [];
    pool.query = async (text, params = []) => {
      captured.push({ sql: norm(text), params });
      return /COUNT/.test(text) ? ok([{ total: 3 }]) : ok([]);
    };
    const page = await listAdminApplications({});
    assert.deepEqual(page, { items: [], total: 3 });
    assert.deepEqual(captured[0].params, ['pending', null, 30, 0]);
    assert.deepEqual(captured[1].params, ['pending', null]);
    assert.match(captured[0].sql, /ORDER BY a\.created_at DESC, a\.id DESC LIMIT \$3 OFFSET \$4$/);

    captured.length = 0;
    await listAdminApplications({ status: 'all', q: ' 100%_Gül ', limit: '500', offset: '60' });
    assert.deepEqual(captured[0].params, [null, '%100!%!_Gül%', 100, 60]);
    assert.match(captured[0].sql, /ILIKE \$2::TEXT ESCAPE '!'/);
    assert.equal(captured[0].sql.includes('100%'), false, 'q SQL metnine gömülmez');

    await rejectsWith(listAdminApplications({ status: 'x' }), 400, 'INVALID_QUERY');
    await rejectsWith(listAdminApplications({ offset: '-3' }), 400, 'INVALID_QUERY');
    assert.equal(db.connects(), 0);
  });

  it('özet: { pending } hafif tek sorgu, başvuranı silinmiş bekleyenleri SAYMAZ (rozet şişmez); ayar: payment_available false, planlar; PUT yalnız approval, payment 409, diğer 400', async () => {
    let db = install();
    const seen = [];
    pool.query = async (text) => { seen.push(norm(text)); return ok([{ pending: 4 }]); };
    assert.deepEqual(await getPendingSummary(), { pending: 4 });
    assert.equal(seen.length, 1);
    assert.match(seen[0], /WHERE status = 'pending' AND applicant_user_code IS NOT NULL$/);

    db = install();
    const settings = await getSiteOnboardingSettings();
    assert.equal(settings.mode, 'approval');
    assert.equal(settings.payment_available, false);
    assert.deepEqual(settings.plans, [{ code: 'manual_approval', name: 'Elle Onaylı', is_active: true, price_minor: null, currency: 'TRY', billing_period: null }]);

    db = install();
    const updated = await setSiteOnboardingMode({ mode: ' approval ', actor: superUser });
    assert.equal(updated.mode, 'approval');
    const audit = find(db.log, /^INSERT INTO audit_log/);
    assert.equal(audit.params[3], 'platform_settings.updated');
    assert.deepEqual(JSON.parse(audit.params[7]), { key: 'site_onboarding', mode: 'approval', previous_mode: 'approval' });
    assert.match(find(db.log, /^INSERT INTO platform_settings/).sql, /platform_settings\.value \|\| EXCLUDED\.value/);

    db = install();
    await assert.rejects(
      () => setSiteOnboardingMode({ mode: 'payment', actor: superUser }),
      (error) => error.statusCode === 409 && error.code === 'PAYMENT_NOT_AVAILABLE' && error.message === 'Ödeme sistemi Yakında…',
    );
    for (const bad of [undefined, null, 5, 'kapali', '', {}]) {
      await rejectsWith(setSiteOnboardingMode({ mode: bad, actor: superUser }), 400, 'INVALID_BODY');
    }
    assert.equal(db.connects(), 0);
  });
});
