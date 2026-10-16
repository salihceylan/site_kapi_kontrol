// Kayıt akışlarında yasal belge onayı (DB'siz, sahte pool / client):
//  - /auth/register-individual: zorunluluk (CONSENT_REQUIRED) ve onayın BEKLEYEN KAYITTA saklanması;
//  - e-posta kodu doğrulanınca hesap GERÇEKTEN oluşurken onayların user_consents'a AYNI işlemde yazılması (atomik);
//  - eski doğrulanmamış hesap yolu; bozuk saklı veri hesap açılışını bozmaz;
//  - POST /membership/site-applications: onay denetimi / yazımı başvuruyla aynı işlemde.
import { describe, it, before, after, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import bcrypt from 'bcryptjs';
import express from 'express';
import nodemailer from 'nodemailer';
import { pool } from '../src/db.js';

process.env.JWT_SECRET = process.env.JWT_SECRET || 'test-secret-for-consent-registration-0123456789abcdef';

const { registerIndividualUser, verifyIndividualEmailCode } = await import('../src/services/membership_service.js');
const { authRouter } = await import('../src/routes/auth_routes.js');
const { createSiteApplication, siteApplicationHooks } = await import('../src/modules/site_application_service.js');
const { siteApplicationConsents } = await import('../src/modules/legal_consent_service.js');
const { clearLegalCache } = await import('../src/modules/legal_documents.js');
const { registerLimiter } = await import('../src/middlewares/rate_limiters.js');

const here = path.dirname(fileURLToPath(import.meta.url));
const FIXTURES = path.join(here, 'fixtures', 'legal');

const flat = (text) => String(text).replace(/\s+/g, ' ').trim();
const PENDING_HASH = bcrypt.hashSync('abcdef12', 4);
const CODE = '123456';
const CODE_HASH = bcrypt.hashSync(CODE, 4);

const FULL_SETTINGS = {
  'legal.company_name': 'Örnek A.Ş.',
  'legal.company_address': 'Ankara',
  'legal.mersis_no': '0123456789012345',
  'legal.kep_address': 'ornek@hs01.kep.tr',
  'legal.contact_email': 'info@example.com',
  'legal.contact_phone': '+90 312 000 00 00',
};

const baseInput = { firstName: 'Ali', lastName: 'Veli', email: 'ali@example.com', password: 'abcdef12' };
const REGISTER_DOCS = [
  { id: 'terms', version: '2026-10-01' },
  { id: 'privacy', version: '2026-10-16' },
  { id: 'kvkk_notice', version: '2026-10-16' },
];

function userRow(overrides = {}) {
  return {
    id: 77,
    user_code: 77,
    full_name: 'Ali Veli',
    email: 'ali@example.com',
    login_name: null,
    role: 'individual',
    is_active: true,
    email_verified: true,
    approval_status: 'approved',
    phone_number: null,
    created_at: new Date('2026-10-02T00:00:00Z'),
    password_hash: PENDING_HASH,
    ...overrides,
  };
}

const original = { query: pool.query, connect: pool.connect, createTransport: nodemailer.createTransport };
let log;
let state;

function settingsRows() {
  return Object.entries(state.settings).map(([key, value]) => ({ key, value }));
}

/** Her iki bağlantı (pool ve client) için ortak sahte: kayıt, doğrulama ve onay tabloları. */
async function handle(via, text, params = []) {
  const sql = flat(text);
  log.push({ via, sql, params });
  if (/^(BEGIN|COMMIT|ROLLBACK)$/.test(sql)) return { rows: [], rowCount: 0 };
  if (sql.startsWith('SELECT pg_advisory_xact_lock')) return { rows: [], rowCount: 1 };
  if (/FROM platform_settings WHERE key = ANY/.test(sql)) return { rows: settingsRows(), rowCount: 1 };
  if (/^SELECT user_code, email, email_verified, role FROM users/.test(sql)) {
    return { rows: state.existingUser ? [state.existingUser] : [], rowCount: state.existingUser ? 1 : 0 };
  }
  if (sql.includes('AS seconds_since_last')) return { rows: [{ seconds_since_last: null, codes_last_hour: 0 }], rowCount: 1 };
  if (/^INSERT INTO email_verifications/.test(sql)) return { rows: [{ id: 501 }], rowCount: 1 };
  if (/^INSERT INTO pending_registrations/.test(sql)) return { rows: [], rowCount: 1 };
  if (/^UPDATE users SET full_name/.test(sql)) return { rows: [], rowCount: state.legacyUpdateRows };
  if (/^UPDATE email_verifications SET is_verified = TRUE WHERE LOWER\(email\) = LOWER\(\$1\) AND is_verified = FALSE AND id < \$2/.test(sql)) {
    return { rows: [], rowCount: 1 };
  }
  if (/^UPDATE email_verifications SET is_verified = TRUE WHERE LOWER\(email\)/.test(sql)) return { rows: [], rowCount: 0 };
  if (sql.includes('attempt_count = ev.attempt_count + 1')) return { rows: [{ id: 501, code_hash: CODE_HASH }], rowCount: 1 };
  if (/^UPDATE email_verifications SET is_verified = TRUE, verified_at = NOW\(\)/.test(sql)) return { rows: [{ id: 501 }], rowCount: 1 };
  if (/^UPDATE users SET email_verified = TRUE/.test(sql)) {
    return { rows: state.verifiedUserRows, rowCount: state.verifiedUserRows.length };
  }
  if (/^DELETE FROM pending_registrations/.test(sql)) return { rows: state.pendingTaken, rowCount: state.pendingTaken.length };
  if (/^INSERT INTO users/.test(sql)) return { rows: [userRow()], rowCount: 1 };
  if (/^INSERT INTO user_consents/.test(sql)) {
    if (state.consentInsertError) throw state.consentInsertError;
    return { rows: [], rowCount: params[1].length };
  }
  if (sql.includes('FROM site_manager_invitations')) return { rows: [], rowCount: 0 };
  throw new Error(`beklenmeyen ${via} sorgusu: ${sql}`);
}

before(() => {
  process.env.LEGAL_DIR = FIXTURES;
});
after(() => {
  delete process.env.LEGAL_DIR;
});

beforeEach(() => {
  log = [];
  state = {
    settings: { ...FULL_SETTINGS },
    existingUser: null,
    legacyUpdateRows: 1,
    verifiedUserRows: [],
    pendingTaken: [],
    consentInsertError: null,
  };
  clearLegalCache();
  process.env.SMTP_HOST = 'smtp.invalid';
  process.env.SMTP_USER = 'user@example.invalid';
  process.env.SMTP_PASSWORD = 'test-only';
  process.env.SMTP_FROM = 'AHBU <noreply@example.invalid>';
  pool.query = (text, params) => handle('pool', text, params);
  pool.connect = async () => ({ query: (text, params) => handle('client', text, params), release() {} });
  nodemailer.createTransport = () => ({ sendMail: async () => {} });
  mock.method(console, 'error', () => {});
});

afterEach(() => {
  pool.query = original.query;
  pool.connect = original.connect;
  nodemailer.createTransport = original.createTransport;
  mock.restoreAll();
  registerLimiter.reset();
});

const queryOf = (re) => log.find((entry) => re.test(entry.sql));
const has = (re) => log.some((entry) => re.test(entry.sql));
const indexOf = (re) => log.findIndex((entry) => re.test(entry.sql));

describe('registerIndividualUser: onaylar bekleyen kayıtla saklanır', () => {
  it('onaylı kayıt: upsert $5 = [{id, version, accepted_at}] JSON; users ve user_consents satırı HENÜZ yok', async () => {
    await registerIndividualUser({ ...baseInput, acceptedDocuments: REGISTER_DOCS });
    const upsert = queryOf(/^INSERT INTO pending_registrations/);
    assert.equal(upsert.params.length, 5);
    const stored = JSON.parse(upsert.params[4]);
    assert.deepEqual(stored.map((d) => [d.id, d.version]), REGISTER_DOCS.map((d) => [d.id, d.version]));
    for (const entry of stored) assert.ok(!Number.isNaN(new Date(entry.accepted_at).getTime()));
    assert.equal(has(/^INSERT INTO users/), false);
    assert.equal(has(/^INSERT INTO user_consents/), false, 'hesap oluşmadan onay satırı yazılmaz');
  });

  it('onay verilmeyen kayıt: $5 = null (tekrar kayıt eski onayı SİLER; en son deneme geçerli)', async () => {
    await registerIndividualUser(baseInput);
    assert.equal(queryOf(/^INSERT INTO pending_registrations/).params[4], null);
    log = [];
    await registerIndividualUser({ ...baseInput, acceptedDocuments: [] });
    assert.equal(queryOf(/^INSERT INTO pending_registrations/).params[4], null);
  });

  it('ESKİ doğrulanmamış hesap yolu: kimlik bilgileri güncellenince onaylar o hesaba yazılır (source=register); bayat denemede yazılmaz', async () => {
    state.existingUser = { user_code: 9, email: 'ali@example.com', email_verified: false, role: 'individual' };
    await registerIndividualUser({ ...baseInput, acceptedDocuments: REGISTER_DOCS });
    const insert = queryOf(/^INSERT INTO user_consents/);
    assert.ok(insert);
    assert.equal(insert.via, 'pool');
    assert.equal(insert.params[0], 9);
    assert.deepEqual(insert.params[1], ['terms', 'privacy', 'kvkk_notice']);
    assert.equal(insert.params[4], 'register');
    assert.ok(indexOf(/^UPDATE users SET full_name/) < indexOf(/^INSERT INTO user_consents/));
    assert.equal(has(/^INSERT INTO pending_registrations/), false);

    log = [];
    state.legacyUpdateRows = 0;
    await registerIndividualUser({ ...baseInput, acceptedDocuments: REGISTER_DOCS });
    assert.equal(has(/^INSERT INTO user_consents/), false, 'güncelleme 0 satır (bayat) ise onay yazılmaz');

    log = [];
    state.legacyUpdateRows = 1;
    await registerIndividualUser(baseInput);
    assert.equal(has(/^INSERT INTO user_consents/), false, 'onay yoksa ek sorgu yok');
  });
});

describe('verifyIndividualEmailCode: hesapla birlikte, AYNI işlemde', () => {
  const pendingWith = (documents) => [{ full_name: 'Ali Veli', password_hash: PENDING_HASH, accepted_documents: documents }];

  it('hesap oluşunca onaylar users INSERT\'inden sonra, COMMIT\'ten önce, aynı client ile yazılır', async () => {
    state.pendingTaken = pendingWith([
      { id: 'terms', version: '2026-10-01', accepted_at: new Date(Date.now() - 60000).toISOString() },
      { id: 'privacy', version: '2026-10-16', accepted_at: new Date(Date.now() - 60000).toISOString() },
    ]);
    const result = await verifyIndividualEmailCode({ email: 'ali@example.com', code: CODE });
    assert.equal(result.ok, true);
    const consent = queryOf(/^INSERT INTO user_consents/);
    assert.ok(consent);
    assert.equal(consent.via, 'client', 'hesap açan işlemin istemcisi');
    assert.equal(consent.params[0], 77, 'yeni hesabın user_code değeri');
    assert.deepEqual(consent.params[1], ['terms', 'privacy']);
    assert.deepEqual(consent.params[2], ['2026-10-01', '2026-10-16']);
    assert.equal(consent.params[4], 'register');
    assert.ok(indexOf(/^INSERT INTO users/) < indexOf(/^INSERT INTO user_consents/));
    assert.ok(indexOf(/^INSERT INTO user_consents/) < indexOf(/^COMMIT$/));
    assert.equal(log.filter((e) => e.via === 'pool' && /user_consents/.test(e.sql)).length, 0);
  });

  it('ATOMİKLİK: onay yazımı başarısızsa işlem ROLLBACK olur, COMMIT yok, hata yukarı gider (hesap da açılmaz)', async () => {
    state.pendingTaken = pendingWith([{ id: 'terms', version: '2026-10-01', accepted_at: new Date().toISOString() }]);
    state.consentInsertError = Object.assign(new Error('SECRET_DB_DETAIL'), { code: 'XX000' });
    await assert.rejects(verifyIndividualEmailCode({ email: 'ali@example.com', code: CODE }), /SECRET_DB_DETAIL/);
    assert.ok(has(/^ROLLBACK$/));
    assert.equal(has(/^COMMIT$/) && indexOf(/^COMMIT$/) > indexOf(/^INSERT INTO user_consents/), false);
    assert.ok(indexOf(/^ROLLBACK$/) > indexOf(/^INSERT INTO user_consents/));
  });

  it('onay yoksa (null) ya da saklı veri bozuksa ek sorgu YOK ve hesap yine açılır', async () => {
    for (const stored of [null, undefined, 'bozuk', {}, [{ id: 'BOZUK!', version: 'v1' }], [null, 5, 'x']]) {
      log = [];
      state.pendingTaken = pendingWith(stored);
      const result = await verifyIndividualEmailCode({ email: 'ali@example.com', code: CODE });
      assert.equal(result.ok, true, JSON.stringify(stored));
      assert.ok(has(/^INSERT INTO users/), JSON.stringify(stored));
      assert.equal(has(/^INSERT INTO user_consents/), false, JSON.stringify(stored));
    }
  });

  it('gelecekteki / çok eski accepted_at "şimdi" olur (saklı zamana körü körüne güvenilmez)', async () => {
    state.pendingTaken = pendingWith([{ id: 'terms', version: '2026-10-01', accepted_at: '2099-01-01T00:00:00.000Z' }]);
    const before = Date.now();
    await verifyIndividualEmailCode({ email: 'ali@example.com', code: CODE });
    const at = new Date(queryOf(/^INSERT INTO user_consents/).params[3][0]).getTime();
    assert.ok(at >= before - 1000 && at <= Date.now() + 1000);
  });

  it('ESKİ hesap doğrulama yolu (users satırı zaten var): bekleyen kayda ve onay tablosuna dokunulmaz', async () => {
    state.verifiedUserRows = [userRow()];
    const result = await verifyIndividualEmailCode({ email: 'ali@example.com', code: CODE });
    assert.equal(result.ok, true);
    assert.equal(has(/^DELETE FROM pending_registrations/), false);
    assert.equal(has(/^INSERT INTO user_consents/), false);
  });
});

describe('POST /auth/register-individual (HTTP)', () => {
  let server;
  let baseUrl;

  before(async () => {
    const app = express();
    app.use(express.json());
    app.use(authRouter);
    await new Promise((resolve) => {
      server = app.listen(0, '127.0.0.1', resolve);
    });
    baseUrl = `http://127.0.0.1:${server.address().port}`;
  });

  after(async () => {
    server.closeAllConnections?.();
    await new Promise((resolve) => server.close(resolve));
  });

  const register = async (extra = {}) => {
    const response = await fetch(`${baseUrl}/auth/register-individual`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ first_name: 'Ali', last_name: 'Veli', email: 'ali@example.com', password: 'abcdef12', ...extra }),
    });
    return { status: response.status, json: await response.json() };
  };

  it('zorunluluk KAPALI (varsayılan): onaysız kayıt eskisi gibi 201; onaylı kayıt bekleyen kayıtla saklanır', async () => {
    let res = await register();
    assert.equal(res.status, 201);
    assert.equal(queryOf(/^INSERT INTO pending_registrations/).params[4], null);
    log = [];
    res = await register({ accepted_documents: REGISTER_DOCS });
    assert.equal(res.status, 201);
    assert.equal(JSON.parse(queryOf(/^INSERT INTO pending_registrations/).params[4]).length, 3);
  });

  it('zorunluluk AÇIK: eksik / eski onay 400 { code: CONSENT_REQUIRED, missing }; kayıt işlemi HİÇ başlamaz (e-posta / kod / kayıt sorgusu yok)', async () => {
    state.settings['legal.enforce_consents'] = true;
    let res = await register();
    assert.equal(res.status, 400);
    assert.equal(res.json.code, 'CONSENT_REQUIRED');
    assert.deepEqual(res.json.missing, ['terms', 'privacy', 'kvkk_notice']);
    assert.ok(typeof res.json.error === 'string');
    res = await register({ accepted_documents: [{ id: 'terms', version: 'ESKI' }, { id: 'privacy', version: '2026-10-16' }, { id: 'kvkk_notice', version: '2026-10-16' }] });
    assert.equal(res.status, 400);
    assert.deepEqual(res.json.missing, ['terms']);
    assert.equal(has(/email_verifications|pending_registrations|FROM users/), false);
  });

  it('zorunluluk AÇIK + tüm güncel onaylar: 201 ve onaylar bekleyen kayıtta', async () => {
    state.settings['legal.enforce_consents'] = true;
    const res = await register({ accepted_documents: REGISTER_DOCS });
    assert.equal(res.status, 201);
    assert.deepEqual(JSON.parse(queryOf(/^INSERT INTO pending_registrations/).params[4]).map((d) => d.id), ['terms', 'privacy', 'kvkk_notice']);
  });

  it('biçimsiz accepted_documents 400 INVALID_ACCEPTED_DOCUMENTS (zorunluluk kapalıyken de)', async () => {
    for (const bad of ['terms', { id: 'terms' }, [{ id: 'terms' }], [1]]) {
      const res = await register({ accepted_documents: bad });
      assert.equal(res.status, 400, JSON.stringify(bad));
      assert.equal(res.json.code, 'INVALID_ACCEPTED_DOCUMENTS');
    }
  });

  it('kapatılmış (410) uçlar onay gövdesini hiç okumaz: /auth/register ve /auth/site-manager/register', async () => {
    for (const urlPath of ['/auth/register', '/auth/site-manager/register']) {
      const response = await fetch(`${baseUrl}${urlPath}`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ accepted_documents: REGISTER_DOCS }),
      });
      assert.equal(response.status, 410, urlPath);
    }
    assert.equal(log.length, 0);
  });
});

describe('createSiteApplication: onaylar başvuruyla aynı işlemde', () => {
  const actor = { id: 48213, user_code: 48213, userCode: 48213, role: 'individual', full_name: 'Ayşe Başvuran', email: 'ayse@example.com' };
  const body = { name: 'Gül Sitesi', city: 'Ankara', blocks: [{ name: 'A', apartmentCount: 5 }] };
  const stored = {
    id: '41',
    applicant_user_code: 48213,
    status: 'pending',
    site_name: 'Gül Sitesi',
    city: 'Ankara',
    district: null,
    address: null,
    management_type: 'apartment_site',
    blocks: [{ name: 'A', apartmentCount: 5, sortOrder: 1 }],
    doors: [{ name: 'Kapı 1', doorIndex: 1 }],
    block_count: 1,
    apartment_count: 5,
    door_count: 1,
    device_uid: null,
    note: null,
    plan_code: null,
    payment_status: 'not_required',
    decided_at: null,
    decision_note: null,
    site_code: null,
    created_at: new Date('2026-10-16T07:00:00.000Z'),
  };
  let originalNotify;

  beforeEach(() => {
    originalNotify = siteApplicationHooks.notifyCreated;
    siteApplicationHooks.notifyCreated = async () => {};
    const dispatch = async (via, text, params = []) => {
      const sql = flat(text);
      if (/^SELECT role FROM users WHERE user_code = \$1 LIMIT 1$/.test(sql)) return { rows: [{ role: 'individual' }], rowCount: 1 };
      if (/^SELECT id, user_code, role, full_name FROM users/.test(sql)) return { rows: [{ id: 7, user_code: 48213, role: 'individual', full_name: 'Ayşe Başvuran' }], rowCount: 1 };
      if (/^SELECT value FROM platform_settings WHERE key = \$1 LIMIT 1$/.test(sql)) return { rows: [{ value: { mode: 'approval' } }], rowCount: 1 };
      if (/a\.status = 'pending' LIMIT 1$/.test(sql)) return { rows: [], rowCount: 0 };
      if (/^SELECT COUNT\(\*\)::INTEGER AS applied/.test(sql)) return { rows: [{ applied: 0 }], rowCount: 1 };
      if (/^INSERT INTO site_applications/.test(sql)) {
        log.push({ via, sql, params });
        return { rows: [{ id: '41', created_at: stored.created_at }], rowCount: 1 };
      }
      if (/^INSERT INTO audit_log/.test(sql)) return { rows: [], rowCount: 1 };
      if (/^(SAVEPOINT|RELEASE SAVEPOINT)/.test(sql)) return { rows: [], rowCount: 0 };
      if (/WHERE a\.id = \$1 LIMIT 1$/.test(sql)) return { rows: [stored], rowCount: 1 };
      return handle(via, text, params);
    };
    pool.query = (text, params) => dispatch('pool', text, params);
    pool.connect = async () => ({ query: (text, params) => dispatch('client', text, params), release() {} });
  });

  afterEach(() => {
    siteApplicationHooks.notifyCreated = originalNotify;
  });

  const SITE_DOCS = [{ id: 'terms', version: '2026-10-01' }, { id: 'dpa', version: '2026-10-05' }];

  it('kanca verilmezse (eski çağrı biçimi) onay sorgusu YOK', async () => {
    await createSiteApplication({ actor, body: { ...body, accepted_documents: SITE_DOCS } });
    assert.equal(has(/platform_settings WHERE key = ANY/), false);
    assert.equal(has(/^INSERT INTO user_consents/), false);
  });

  it('kanca ile: denetim INSERT\'ten önce, onay yazımı audit\'ten sonra ve COMMIT\'ten önce, aynı client; source=site_application', async () => {
    await createSiteApplication({ actor, body: { ...body, accepted_documents: SITE_DOCS }, consents: siteApplicationConsents });
    const iCheck = indexOf(/platform_settings WHERE key = ANY/);
    const iInsert = indexOf(/^INSERT INTO site_applications/);
    const iConsent = indexOf(/^INSERT INTO user_consents/);
    const iCommit = indexOf(/^COMMIT$/);
    assert.ok(iCheck >= 0 && iCheck < iInsert && iInsert < iConsent && iConsent < iCommit);
    const consent = log[iConsent];
    assert.equal(consent.via, 'client');
    assert.equal(consent.params[0], 48213);
    assert.deepEqual(consent.params[1], ['terms', 'dpa']);
    assert.equal(consent.params[4], 'site_application');
  });

  it('zorunluluk AÇIK + eksik onay: 400 CONSENT_REQUIRED { missing }, ROLLBACK, başvuru ve onay satırı YOK', async () => {
    state.settings['legal.enforce_consents'] = true;
    await assert.rejects(
      createSiteApplication({ actor, body, consents: siteApplicationConsents }),
      (error) => error.statusCode === 400 && error.code === 'CONSENT_REQUIRED' && JSON.stringify(error.extra) === JSON.stringify({ missing: ['terms', 'dpa'] }),
    );
    assert.equal(has(/^INSERT INTO site_applications/), false);
    assert.equal(has(/^INSERT INTO user_consents/), false);
    assert.ok(has(/^ROLLBACK$/));
    assert.equal(has(/^COMMIT$/), false);
  });

  it('zorunluluk AÇIK + tam güncel onay: başvuru + onaylar birlikte COMMIT', async () => {
    state.settings['legal.enforce_consents'] = true;
    const application = await createSiteApplication({ actor, body: { ...body, accepted_documents: SITE_DOCS }, consents: siteApplicationConsents });
    assert.equal(application.status, 'pending');
    assert.ok(has(/^INSERT INTO user_consents/) && has(/^COMMIT$/));
  });

  it('onay yazımı başarısızsa başvuru da geri alınır (tek işlem)', async () => {
    state.consentInsertError = Object.assign(new Error('SECRET_DB_DETAIL'), { code: 'XX000' });
    await assert.rejects(createSiteApplication({ actor, body: { ...body, accepted_documents: SITE_DOCS }, consents: siteApplicationConsents }), /SECRET_DB_DETAIL/);
    assert.ok(has(/^ROLLBACK$/));
    assert.equal(has(/^COMMIT$/), false);
  });
});
