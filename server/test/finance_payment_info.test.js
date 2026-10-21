// Ödeme bilgisi servisi (sahte veritabanı): IBAN doğrulama, yalnız banka hesabı, sürümlü kayıt, maskeli denetim, önek çakışması, sürüm çakışması.
// Gerçek PostgreSQL ve HTTP yetki matrisi denemesi kullanıcıdadır.
import { describe, it, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { pool } from '../src/db.js';
import { putBankDetails, putPaymentSettings, getPaymentSettings } from '../src/modules/finance_payment_info.js';
import { makeTrIban } from './finance_iban.test.js';

const norm = (t) => String(t).replace(/\s+/g, ' ').trim();
const ok = (rows = []) => ({ rows, rowCount: rows.length });
const actor = { user_code: 20001, userCode: 20001, role: 'site_manager', full_name: 'Ayşe' };
let log;
let db;

function install() {
  const handle = async (text, params = []) => {
    const sql = norm(text);
    log.push({ sql, params });
    if (/^(BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE SAVEPOINT|ROLLBACK TO SAVEPOINT)\b/.test(sql)) return ok();
    if (/^SELECT pg_advisory_xact_lock/.test(sql)) return ok();
    if (/^SELECT site_code FROM sites/.test(sql)) return ok([{ site_code: 1 }]);
    if (/FROM site_modules/.test(sql)) return ok([{ enabled: true }]);
    if (/FROM users WHERE user_code/.test(sql)) return ok([{ user_code: 20001 }]);
    if (/^INSERT INTO audit_log/.test(sql)) return ok();
    if (/FROM finance_accounts WHERE id = \$1 AND site_code = \$2/.test(sql)) return ok(db.accounts[params[0]] ? [db.accounts[params[0]]] : []);
    if (/FROM finance_account_bank_details WHERE account_id = \$1 ORDER BY id DESC/.test(sql)) return ok(db.versions.slice(-1));
    if (/^INSERT INTO finance_account_bank_details/.test(sql)) {
      db.versions.push({ iban: params[2], payee_name: params[3] });
      return ok();
    }
    if (/FROM finance_payment_settings WHERE site_code = \$1 FOR UPDATE/.test(sql)) return ok(db.settings ? [db.settings] : []);
    if (/FROM finance_site_ref_prefixes WHERE site_code = \$1 AND is_current FOR UPDATE/.test(sql)) return ok(db.current ? [{ prefix: db.current }] : []);
    if (/FROM finance_site_ref_prefixes WHERE prefix = \$1 FOR UPDATE/.test(sql)) return ok(db.owners[params[0]] ? [{ site_code: db.owners[params[0]] }] : []);
    if (/^SELECT name FROM sites/.test(sql)) return ok([{ name: 'Gül Sitesi' }]);
    if (/^SELECT prefix FROM finance_site_ref_prefixes WHERE site_code <> \$1/.test(sql)) return ok(Object.keys(db.owners).map((prefix) => ({ prefix })));
    if (/^(INSERT INTO|UPDATE) finance_(site_ref_prefixes|payment_settings)/.test(sql)) {
      db.writes.push(sql);
      return ok();
    }
    throw new Error(`SAHTE VERITABANI: tanimsiz SQL: ${sql.slice(0, 140)}`);
  };
  pool.query = handle;
  pool.connect = async () => ({ query: handle, release() {} });
}

beforeEach(() => {
  log = [];
  db = { accounts: { 5: { id: 5, kind: 'bank' }, 6: { id: 6, kind: 'cash' } }, versions: [], settings: null, current: null, owners: {}, writes: [] };
  install();
});

describe('putBankDetails', () => {
  it('geçersiz IBAN 400 IBAN_INVALID; kasa hesabı 400; başka siteye ait hesap 404', async () => {
    await assert.rejects(putBankDetails({ siteCode: 1, rawId: '5', body: { iban: 'TR12', payee_name: 'Gül Sitesi' }, actor }), { code: 'IBAN_INVALID' });
    await assert.rejects(putBankDetails({ siteCode: 1, rawId: '6', body: { iban: makeTrIban(), payee_name: 'Gül Sitesi' }, actor }), { code: 'INVALID_BODY' });
    await assert.rejects(putBankDetails({ siteCode: 1, rawId: '99', body: { iban: makeTrIban(), payee_name: 'Gül Sitesi' }, actor }), { code: 'ACCOUNT_NOT_FOUND' });
    await assert.rejects(putBankDetails({ siteCode: 1, rawId: '5', body: { iban: makeTrIban(), payee_name: 'G' }, actor }), { code: 'INVALID_BODY' });
  });

  it('yeni sürüm eklenir; denetim kaydında açık IBAN yok; aynı değer tekrarı yeni satır yazmaz', async () => {
    const iban = makeTrIban();
    const first = await putBankDetails({ siteCode: 1, rawId: '5', body: { iban: ` ${iban.toLowerCase()} `, payee_name: ' Gül  Sitesi Yönetimi ' }, actor });
    assert.equal(first.replayed, false);
    assert.equal(db.versions.length, 1);
    assert.equal(db.versions[0].iban, iban);
    assert.equal(db.versions[0].payee_name, 'Gül Sitesi Yönetimi');
    const audit = log.filter((l) => /^INSERT INTO audit_log/.test(l.sql));
    assert.ok(audit.length >= 1);
    assert.ok(!JSON.stringify(audit).includes(iban));
    const again = await putBankDetails({ siteCode: 1, rawId: '5', body: { iban, payee_name: 'Gül Sitesi Yönetimi' }, actor });
    assert.equal(again.replayed, true);
    assert.equal(db.versions.length, 1);
  });
});

describe('putPaymentSettings', () => {
  it('geçersiz önek 400; boş gövde 400', async () => {
    await assert.rejects(putPaymentSettings({ siteCode: 1, body: { prefix: 'G1L' }, actor }), { code: 'INVALID_BODY' });
    await assert.rejects(putPaymentSettings({ siteCode: 1, body: {}, actor }), { code: 'INVALID_BODY' });
  });

  it('ayar satırı varken sürüm yoksa 400, farklıysa 409 SETTINGS_VERSION_CONFLICT', async () => {
    db.settings = { settings_version: 3, resident_account_id: null, notices_enabled: false };
    await assert.rejects(putPaymentSettings({ siteCode: 1, body: { notices_enabled: true }, actor }), { code: 'INVALID_BODY' });
    await assert.rejects(putPaymentSettings({ siteCode: 1, body: { notices_enabled: true, expected_settings_version: 2 }, actor }), {
      statusCode: 409,
      code: 'SETTINGS_VERSION_CONFLICT',
    });
  });

  it('önek başka sitedeyse 409 PREFIX_TAKEN ve öneri listesi döner', async () => {
    db.owners = { GUL: 2 };
    await assert.rejects(putPaymentSettings({ siteCode: 1, body: { prefix: 'Gül' }, actor }), (error) => {
      assert.equal(error.statusCode, 409);
      assert.equal(error.code, 'PREFIX_TAKEN');
      assert.ok(Array.isArray(error.extra.suggestions) && error.extra.suggestions.length > 0);
      assert.ok(!error.extra.suggestions.includes('GUL'));
      return true;
    });
  });

  it('banka hesabı doğrulanmadan (IBAN girilmemiş / başka site) ayar yazılmaz', async () => {
    pool.query = async () => ok();
    const base = pool.connect;
    pool.connect = async () => {
      const c = await base();
      const q = c.query;
      c.query = async (text, params) => (/SELECT a\.id FROM finance_accounts a/.test(norm(text)) ? ok() : q(text, params));
      return c;
    };
    await assert.rejects(putPaymentSettings({ siteCode: 1, body: { resident_account_id: 5 }, actor }), { code: 'INVALID_BODY' });
    assert.equal(db.writes.length, 0);
  });
});

describe('getPaymentSettings', () => {
  it('kurul maskeli görür: IBAN alanı null, iban_display maskeli', async () => {
    const iban = makeTrIban();
    pool.query = async (text) => {
      const sql = norm(text);
      if (/^SELECT name FROM sites/.test(sql)) return ok([{ name: 'Gül Sitesi' }]);
      if (/FROM finance_payment_settings/.test(sql)) return ok([{ resident_account_id: 5, notices_enabled: false, settings_version: 2 }]);
      if (/FROM finance_site_ref_prefixes WHERE site_code = \$1 ORDER/.test(sql)) return ok([{ prefix: 'GUL', is_current: true }, { prefix: 'ESK', is_current: false }]);
      if (/FROM finance_accounts a/.test(sql)) return ok([{ id: 5, name: 'Ana hesap', is_active: true, iban, payee_name: 'Gül Sitesi', created_at: new Date() }]);
      return ok();
    };
    const board = await getPaymentSettings(1, { full: false });
    assert.equal(board.prefix, 'GUL');
    assert.deepEqual(board.aliases, ['ESK']);
    assert.equal(board.bank_accounts[0].iban, null);
    assert.ok(board.bank_accounts[0].iban_display.startsWith('TR**'));
    assert.ok(!JSON.stringify(board).includes(iban));
    const manager = await getPaymentSettings(1, { full: true });
    assert.equal(manager.bank_accounts[0].iban, iban);
    assert.match(manager.sample_reference, /^GUL-A2-\d{4}$/);
  });
});
