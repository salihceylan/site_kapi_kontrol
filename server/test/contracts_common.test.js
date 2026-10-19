// Firma ve Sözleşme Takibi ortak mantık (DB'siz): sabitler, girdi doğrulayıcıları (400 INVALID_FIELD { field }), tutar biçimi, durum (state) hesabı ve
// İstanbul takvim sınırı, fesih bildirimi son günü, opak sayfa imleci, yanıt eşleyicileri, kaynak düzeyi gizlilik (audit / günlükte kişisel veri yok).
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  CATEGORIES,
  CONTRACTS_MODULE,
  CONTRACT_LIMIT_PER_SITE,
  LIST_DEFAULT_LIMIT,
  LIST_MAX_LIMIT,
  PERIODS,
  STATES,
  STATUSES,
  VENDOR_LIMIT_PER_SITE,
  contractLimitReached,
  contractState,
  daysLeft,
  decodeCursor,
  encodeCursor,
  isValidDate,
  istanbulToday,
  mapContract,
  mapVendor,
  moduleDisabled,
  normalizeAmount,
  normalizeTaxNo,
  normalizeVendorEmail,
  normalizeVendorPhone,
  noticeDeadline,
  parseContractCreate,
  parseContractListQuery,
  parseContractPatch,
  parseVendorCreate,
  parseVendorListQuery,
  parseVendorPatch,
  stateSql,
  vendorLimitReached,
} from '../src/modules/contracts_common.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const src = (name) => readFileSync(path.join(here, '..', 'src', 'modules', name), 'utf8').replace(/\r\n/g, '\n');
const invalid = (fn, field) =>
  assert.throws(fn, (error) => error.statusCode === 400 && error.code === 'INVALID_FIELD' && error.extra?.field === field && typeof error.message === 'string');

describe('sabitler', () => {
  it('modül kodu, kategori / dönem / durum / state kümeleri, sınırlar', () => {
    assert.equal(CONTRACTS_MODULE, 'contracts');
    assert.deepEqual([...CATEGORIES], ['asansor', 'guvenlik', 'temizlik', 'bahce', 'havuz', 'teknik_bakim', 'yazilim', 'sigorta', 'diger']);
    assert.deepEqual([...PERIODS], ['aylik', 'yillik', 'tek_sefer', 'diger']);
    assert.deepEqual([...STATUSES], ['aktif', 'feshedildi']);
    assert.deepEqual([...STATES], ['aktif', 'yaklasiyor', 'sona_erdi', 'feshedildi']);
    assert.equal(VENDOR_LIMIT_PER_SITE, 500);
    assert.equal(CONTRACT_LIMIT_PER_SITE, 2000);
    assert.equal(LIST_DEFAULT_LIMIT, 50);
    assert.equal(LIST_MAX_LIMIT, 200);
  });

  it('hata gövdeleri: MODULE_DISABLED { module }, LIMIT_REACHED { limit } (409)', () => {
    const off = moduleDisabled();
    assert.equal(off.statusCode, 403);
    assert.equal(off.code, 'MODULE_DISABLED');
    assert.deepEqual(off.extra, { module: 'contracts' });
    for (const [error, limit] of [[vendorLimitReached(), 500], [contractLimitReached(), 2000]]) {
      assert.equal(error.statusCode, 409);
      assert.equal(error.code, 'LIMIT_REACHED');
      assert.deepEqual(error.extra, { limit });
    }
  });
});

describe('firma girdisi', () => {
  it('oluşturma: ad tek satıra iner, kategori zorunlu, isteğe bağlı alanlar boşsa null; e-posta küçük harf', () => {
    const input = parseVendorCreate({ name: '  Kuzey\nAsansör  ', category: 'asansor', contact_name: '', phone: '0212 444 55 66', email: 'Servis@Kuzey.COM', tax_no: ' 1234567890 ', note: 'Satır 1\r\nSatır 2' });
    assert.deepEqual(input, {
      name: 'Kuzey Asansör',
      category: 'asansor',
      contactName: null,
      phone: '0212 444 55 66',
      email: 'servis@kuzey.com',
      taxNo: '1234567890',
      note: 'Satır 1\nSatır 2',
    });
  });

  it('hatalı alanlar alan adıyla 400 INVALID_FIELD', () => {
    invalid(() => parseVendorCreate(null), 'body');
    invalid(() => parseVendorCreate([]), 'body');
    invalid(() => parseVendorCreate({ category: 'asansor' }), 'name');
    invalid(() => parseVendorCreate({ name: '   ', category: 'asansor' }), 'name');
    invalid(() => parseVendorCreate({ name: 'x'.repeat(121), category: 'asansor' }), 'name');
    invalid(() => parseVendorCreate({ name: 'Firma' }), 'category');
    invalid(() => parseVendorCreate({ name: 'Firma', category: 'boya' }), 'category');
    invalid(() => parseVendorCreate({ name: 'Firma', category: 'diger', contact_name: 'y'.repeat(121) }), 'contact_name');
    invalid(() => parseVendorCreate({ name: 'Firma', category: 'diger', phone: 'abc' }), 'phone');
    invalid(() => parseVendorCreate({ name: 'Firma', category: 'diger', email: 'yok' }), 'email');
    invalid(() => parseVendorCreate({ name: 'Firma', category: 'diger', tax_no: '12;34' }), 'tax_no');
    invalid(() => parseVendorCreate({ name: 'Firma', category: 'diger', note: 'n'.repeat(1001) }), 'note');
  });

  it('telefon: santral / 444 / dahili biçimleri kabul; 3-20 rakam ve en çok 32 karakter', () => {
    assert.equal(normalizeVendorPhone('444 1 234'), '444 1 234');
    assert.equal(normalizeVendorPhone('+90 (532) 111-22-33'), '+90 (532) 111-22-33');
    assert.equal(normalizeVendorPhone('  '), null);
    assert.equal(normalizeVendorPhone(null), null);
    for (const bad of ['12', '1'.repeat(21), '0212 444 55 66 dahili 12', '0'.repeat(10) + ' -'.repeat(12), 5321112233]) {
      invalid(() => normalizeVendorPhone(bad), 'phone');
    }
  });

  it('e-posta ve vergi no biçimi', () => {
    assert.equal(normalizeVendorEmail(''), null);
    for (const bad of ['a@b', 'a b@c.com', 'a@b..com', 'a,b@c.com', `${'x'.repeat(250)}@a.com`]) invalid(() => normalizeVendorEmail(bad), 'email');
    assert.equal(normalizeTaxNo('TR-123 45'), 'TR-123 45');
    invalid(() => normalizeTaxNo('1'.repeat(21)), 'tax_no');
  });

  it('PATCH: en az bir alan; boş isteğe bağlı alan siler (null); is_active boolean; bilinmeyen alan yok sayılır', () => {
    assert.deepEqual(parseVendorPatch({ phone: '', is_active: false, ignored: 1 }), { phone: null, is_active: false });
    assert.deepEqual(parseVendorPatch({ name: 'Yeni Ad' }), { name: 'Yeni Ad' });
    invalid(() => parseVendorPatch({}), 'body');
    invalid(() => parseVendorPatch({ ignored: 1 }), 'body');
    invalid(() => parseVendorPatch({ is_active: 'false' }), 'is_active');
    invalid(() => parseVendorPatch({ category: null }), 'category');
    invalid(() => parseVendorPatch({ name: null }), 'name');
  });

  it('liste sorgusu: active all | 1 | 0 (varsayılan all), q kırpılır', () => {
    assert.deepEqual(parseVendorListQuery({}), { active: null, q: null });
    assert.deepEqual(parseVendorListQuery({ active: '1', q: '  asansör ' }), { active: true, q: 'asansör' });
    assert.deepEqual(parseVendorListQuery({ active: '0' }), { active: false, q: null });
    assert.deepEqual(parseVendorListQuery({ active: 'all' }), { active: null, q: null });
    invalid(() => parseVendorListQuery({ active: 'true' }), 'active');
  });
});

describe('sözleşme girdisi', () => {
  const base = { vendor_id: 7, title: 'Asansör bakım sözleşmesi', start_date: '2026-01-01' };

  it('oluşturma: varsayılanlar (notice 30, remind 30, auto_renew false, kategori null = firmanınki), tutar metne çevrilir', () => {
    assert.deepEqual(parseContractCreate(base), {
      vendorId: 7,
      title: 'Asansör bakım sözleşmesi',
      category: null,
      startDate: '2026-01-01',
      endDate: null,
      noticeDays: 30,
      remindBeforeDays: 30,
      amount: null,
      period: null,
      autoRenew: false,
      note: null,
    });
    const full = parseContractCreate({ ...base, vendor_id: '7', category: 'asansor', end_date: '2026-12-31', notice_days: 60, remind_before_days: '45', amount: 1250.5, period: 'yillik', auto_renew: true, note: 'Not' });
    assert.equal(full.vendorId, 7);
    assert.equal(full.endDate, '2026-12-31');
    assert.equal(full.noticeDays, 60);
    assert.equal(full.remindBeforeDays, 45);
    assert.equal(full.amount, '1250.50');
    assert.equal(full.autoRenew, true);
  });

  it('hatalı alanlar alan adıyla 400 INVALID_FIELD; bitiş başlangıçtan önce olamaz', () => {
    invalid(() => parseContractCreate({ ...base, vendor_id: 'x' }), 'vendor_id');
    invalid(() => parseContractCreate({ ...base, vendor_id: 0 }), 'vendor_id');
    invalid(() => parseContractCreate({ ...base, title: '' }), 'title');
    invalid(() => parseContractCreate({ ...base, title: 't'.repeat(161) }), 'title');
    invalid(() => parseContractCreate({ ...base, category: 'boya' }), 'category');
    invalid(() => parseContractCreate({ ...base, start_date: undefined }), 'start_date');
    invalid(() => parseContractCreate({ ...base, start_date: '2026-02-30' }), 'start_date');
    invalid(() => parseContractCreate({ ...base, start_date: '01.01.2026' }), 'start_date');
    invalid(() => parseContractCreate({ ...base, end_date: '2025-12-31' }), 'end_date');
    invalid(() => parseContractCreate({ ...base, notice_days: 366 }), 'notice_days');
    invalid(() => parseContractCreate({ ...base, notice_days: -1 }), 'notice_days');
    invalid(() => parseContractCreate({ ...base, notice_days: 1.5 }), 'notice_days');
    invalid(() => parseContractCreate({ ...base, remind_before_days: 181 }), 'remind_before_days');
    invalid(() => parseContractCreate({ ...base, amount: -1 }), 'amount');
    invalid(() => parseContractCreate({ ...base, period: 'haftalik' }), 'period');
    invalid(() => parseContractCreate({ ...base, auto_renew: 'evet' }), 'auto_renew');
    invalid(() => parseContractCreate({ ...base, note: 'n'.repeat(2001) }), 'note');
    // aynı gün başlayıp biten sözleşme geçerlidir
    assert.equal(parseContractCreate({ ...base, end_date: '2026-01-01' }).endDate, '2026-01-01');
  });

  it('tutar: sayı ya da metin (virgül kabul); en çok 2 ondalık, 12 tam basamak; boş -> null', () => {
    assert.equal(normalizeAmount('1250'), '1250.00');
    assert.equal(normalizeAmount('1250,5'), '1250.50');
    assert.equal(normalizeAmount(0), '0.00');
    assert.equal(normalizeAmount('007.10'), '7.10');
    assert.equal(normalizeAmount(999999999999.99), '999999999999.99');
    assert.equal(normalizeAmount(''), null);
    assert.equal(normalizeAmount(null), null);
    for (const bad of ['1.234', 1.234, '1e3', 1e21, '-5', '1 000', '1000000000000', Number.NaN, Infinity, true, {}]) invalid(() => normalizeAmount(bad), 'amount');
  });

  it('PATCH: en az bir alan; end_date / amount / period / note null ile silinir; status aktif | feshedildi', () => {
    assert.deepEqual(parseContractPatch({ end_date: null, amount: null, period: null, note: '' }), { end_date: null, amount: null, period: null, note: null });
    assert.deepEqual(parseContractPatch({ status: 'feshedildi' }), { status: 'feshedildi' });
    assert.deepEqual(parseContractPatch({ vendor_id: '9', auto_renew: false }), { vendor_id: 9, auto_renew: false });
    invalid(() => parseContractPatch({}), 'body');
    invalid(() => parseContractPatch({ status: 'iptal' }), 'status');
    invalid(() => parseContractPatch({ start_date: null }), 'start_date');
    invalid(() => parseContractPatch({ category: null }), 'category');
    invalid(() => parseContractPatch({ notice_days: null }), 'notice_days');
  });

  it('liste sorgusu: state (all varsayılan), vendor_id, category, q, limit (50, en çok 200), cursor; hatalı değer alan adıyla 400', () => {
    assert.deepEqual(parseContractListQuery({}), { state: null, vendorId: null, category: null, q: null, cursor: null, limit: 50 });
    const parsed = parseContractListQuery({ state: 'yaklasiyor', vendor_id: '12', category: 'havuz', q: ' havuz ', limit: '999' });
    assert.deepEqual(parsed, { state: 'yaklasiyor', vendorId: 12, category: 'havuz', q: 'havuz', cursor: null, limit: 200 });
    invalid(() => parseContractListQuery({ state: 'iptal' }), 'state');
    invalid(() => parseContractListQuery({ vendor_id: 'abc' }), 'vendor_id');
    invalid(() => parseContractListQuery({ category: 'x' }), 'category');
    invalid(() => parseContractListQuery({ limit: '0' }), 'limit');
    invalid(() => parseContractListQuery({ cursor: 'bozuk!' }), 'cursor');
    invalid(() => parseContractListQuery({ before_id: '15' }), 'before_id');
    assert.equal(parseContractListQuery({ before_id: '' }).cursor, null);
  });
});

describe('takvim ve durum (state) hesabı', () => {
  it('istanbulToday: UTC 20:59 ve 21:00 sınırı (İstanbul +03: 23:59 / ertesi gün 00:00)', () => {
    assert.equal(istanbulToday(new Date('2026-10-19T20:59:59Z')), '2026-10-19');
    assert.equal(istanbulToday(new Date('2026-10-19T21:00:00Z')), '2026-10-20');
  });

  it('isValidDate: gerçek gün ve 1990-2100 aralığı', () => {
    assert.equal(isValidDate('2024-02-29'), true);
    assert.equal(isValidDate('2026-02-29'), false);
    assert.equal(isValidDate('1989-12-31'), false);
    assert.equal(isValidDate('2101-01-01'), false);
    assert.equal(isValidDate('2026-1-01'), false);
  });

  it('state: feshedildi > sona_erdi > yaklasiyor (sınır dahil) > aktif; bitişsiz -> aktif; days_left = end_date − bugün', () => {
    const today = '2026-10-19';
    const st = (over) => contractState({ status: 'aktif', endDate: '2026-11-18', remindBeforeDays: 30, ...over }, today);
    assert.equal(st({}), 'yaklasiyor', '30 gün kala (sınır dahil)');
    assert.equal(st({ endDate: '2026-11-19' }), 'aktif', '31 gün kala');
    assert.equal(st({ endDate: today }), 'yaklasiyor', 'bugün bitiyor');
    assert.equal(st({ endDate: '2026-10-18' }), 'sona_erdi', 'dün bitti');
    assert.equal(st({ endDate: null }), 'aktif');
    assert.equal(st({ status: 'feshedildi', endDate: '2020-01-01' }), 'feshedildi');
    assert.equal(st({ endDate: today, remindBeforeDays: 0 }), 'yaklasiyor', 'hatırlatma 0 gün: yalnız son gün');
    assert.equal(st({ endDate: '2026-10-20', remindBeforeDays: 0 }), 'aktif');
    assert.equal(daysLeft('2026-11-18', today), 30);
    assert.equal(daysLeft('2026-10-18', today), -1);
    assert.equal(daysLeft(null, today), null);
  });

  it('İstanbul gece yarısı sınırı: aynı an UTC tarihi farklı olsa da İstanbul gününe göre hesaplanır', () => {
    const lateUtc = new Date('2026-10-19T21:30:00Z'); // İstanbul: 20 Ekim 00:30
    const day = istanbulToday(lateUtc);
    assert.equal(day, '2026-10-20');
    assert.equal(contractState({ status: 'aktif', endDate: '2026-10-19', remindBeforeDays: 30 }, day), 'sona_erdi');
    assert.equal(daysLeft('2026-10-19', day), -1);
  });

  it('notice_deadline yalnız otomatik yenilenen ve bitişi olan sözleşmede: end_date − notice_days', () => {
    assert.equal(noticeDeadline({ autoRenew: true, endDate: '2026-12-31', noticeDays: 30 }), '2026-12-01');
    assert.equal(noticeDeadline({ autoRenew: true, endDate: '2026-03-01', noticeDays: 1 }), '2026-02-28');
    assert.equal(noticeDeadline({ autoRenew: true, endDate: '2026-12-31', noticeDays: 0 }), '2026-12-31');
    assert.equal(noticeDeadline({ autoRenew: false, endDate: '2026-12-31', noticeDays: 30 }), null);
    assert.equal(noticeDeadline({ autoRenew: true, endDate: null, noticeDays: 30 }), null);
  });

  it('stateSql: dört state ayrık SQL parçası; all / null süzgeçsiz; bugün parametresi kullanılır', () => {
    assert.equal(stateSql(null, '$2::DATE'), null);
    assert.equal(stateSql('feshedildi', '$2::DATE'), "c.status = 'feshedildi'");
    for (const state of ['sona_erdi', 'yaklasiyor', 'aktif']) {
      const fragment = stateSql(state, '$9::DATE');
      assert.ok(fragment.includes("c.status = 'aktif'"), state);
      assert.ok(fragment.includes('$9::DATE'), state);
    }
    assert.match(stateSql('yaklasiyor', '$2::DATE'), /c\.end_date - \$2::DATE <= c\.remind_before_days/);
    assert.match(stateSql('aktif', '$2::DATE'), /c\.end_date IS NULL OR c\.end_date - \$2::DATE > c\.remind_before_days/);
  });
});

describe('opak sayfa imleci', () => {
  it('gidiş-dönüş: [end_date | null, id]', () => {
    assert.deepEqual(decodeCursor(encodeCursor('2026-12-31', 42)), { endDate: '2026-12-31', id: 42 });
    assert.deepEqual(decodeCursor(encodeCursor(null, '7')), { endDate: null, id: 7 });
    assert.equal(decodeCursor(''), null);
    assert.equal(decodeCursor(undefined), null);
  });

  it('bozuk / kurcalanmış imleç 400 INVALID_FIELD { field: cursor }', () => {
    const forge = (value) => Buffer.from(JSON.stringify(value)).toString('base64url');
    for (const bad of [forge({ a: 1 }), forge(['2026-13-01', 1]), forge(['2026-01-01', 0]), forge([null, 1.5]), forge([null, 1, 2]), 'x'.repeat(101), '%%%', 123]) {
      invalid(() => decodeCursor(bad), 'cursor');
    }
  });
});

describe('yanıt eşleyicileri', () => {
  it('mapVendor: sözleşmedeki alanlar ve tipler', () => {
    const vendor = mapVendor({
      id: '5', name: 'Kuzey Asansör', category: 'asansor', contact_name: null, phone: '444 1 234', email: null, tax_no: null, note: null,
      is_active: true, contract_count: '3', created_at: new Date('2026-10-01T08:00:00Z'), updated_at: new Date('2026-10-02T08:00:00Z'),
    });
    assert.deepEqual(Object.keys(vendor), ['id', 'name', 'category', 'contact_name', 'phone', 'email', 'tax_no', 'note', 'is_active', 'contract_count', 'created_at', 'updated_at']);
    assert.equal(vendor.id, 5);
    assert.equal(vendor.contract_count, 3);
    assert.equal(vendor.created_at, '2026-10-01T08:00:00.000Z');
  });

  it('mapContract: alan sırası, tutar METİN, state / days_left / notice_deadline hesaplanır; silinmiş oluşturan "Silinmiş Kullanıcı"', () => {
    const row = {
      id: '11', vendor_id: '5', vendor_name: 'Kuzey Asansör', title: 'Bakım', category: 'asansor', start_date: '2026-01-01', end_date: '2026-11-01',
      notice_days: 30, remind_before_days: 30, amount: '1250.00', currency: 'TRY', period: 'yillik', auto_renew: true, status: 'aktif', terminated_at: null,
      note: null, created_by_name: null, created_at: new Date('2026-01-01T09:00:00Z'), updated_at: new Date('2026-01-02T09:00:00Z'),
    };
    const contract = mapContract(row, '2026-10-19');
    assert.deepEqual(Object.keys(contract), [
      'id', 'vendor_id', 'vendor_name', 'title', 'category', 'start_date', 'end_date', 'notice_days', 'remind_before_days', 'amount', 'currency', 'period',
      'auto_renew', 'status', 'state', 'days_left', 'notice_deadline', 'terminated_at', 'note', 'created_by_name', 'created_at', 'updated_at',
    ]);
    assert.equal(contract.id, 11);
    assert.equal(contract.vendor_id, 5);
    assert.equal(contract.amount, '1250.00');
    assert.equal(contract.state, 'yaklasiyor');
    assert.equal(contract.days_left, 13);
    assert.equal(contract.notice_deadline, '2026-10-02');
    assert.equal(contract.created_by_name, 'Silinmiş Kullanıcı');
    const open = mapContract({ ...row, end_date: null, amount: null, auto_renew: false, created_by_name: 'Ali Veli' }, '2026-10-19');
    assert.equal(open.state, 'aktif');
    assert.equal(open.days_left, null);
    assert.equal(open.notice_deadline, null);
    assert.equal(open.amount, null);
    assert.equal(open.created_by_name, 'Ali Veli');
    const ended = mapContract({ ...row, status: 'feshedildi', terminated_at: new Date('2026-05-05T10:00:00Z') }, '2026-10-19');
    assert.equal(ended.state, 'feshedildi');
    assert.equal(ended.terminated_at, '2026-05-05T10:00:00.000Z');
  });
});

describe('kaynak düzeyi gizlilik', () => {
  it("audit details yalnız kimlik / kategori / alan adları / durum taşır: ad, telefon, e-posta, vergi no, tutar, not YAZILMAZ", () => {
    const service = src('contracts_service.js');
    const calls = service.split('await audit(client, actor, ').slice(1).map((chunk) => chunk.slice(0, chunk.indexOf(');')));
    assert.deepEqual(calls.map((call) => /^'([\w.]+)'/.exec(call)[1]), ['contract_vendor.created', 'contract_vendor.updated', 'contract.created', 'contract.updated']);
    for (const call of calls) {
      assert.ok(!/\b(name|phone|email|tax_no|amount|note|title|contact_name)\s*:/.test(call), call);
    }
    assert.ok(/details = \{ fields: changed \}/.test(service), 'güncelleme yalnız alan adlarını yazar');
    const assigned = [...new Set([...service.matchAll(/details\.(\w+) = /g)].map((match) => match[1]))].sort();
    assert.deepEqual(assigned, ['category', 'from', 'is_active', 'to', 'vendor_id']);
  });

  it('hatırlatma e-postası şablonunda tutar alanı kullanılmaz; günlüğe yalnız sayılar / kodlar', () => {
    const reminders = src('contracts_reminders.js');
    assert.ok(!/amount/.test(reminders.replace(/TUTAR YOK/g, '')));
    const logCalls = reminders.match(/console\.(log|error)\([^;]*\);/g) ?? [];
    assert.ok(logCalls.length >= 4);
    for (const call of logCalls) {
      for (const [, expression] of call.matchAll(/\$\{([^}]*)\}/g)) assert.match(expression, /^summary\.\w+$/, call);
      const code = call.replace(/'[^']*'/g, "''").replace(/`[^`]*`/g, '``');
      assert.ok(!/\b(to|email|recipients|site|item|items|vendor)\b/.test(code), call);
    }
  });
});
