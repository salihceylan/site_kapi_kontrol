// Devir bakiyesi (F4) ve hepsi bir arada (N6) toplu yükleme: ayrıştırıcılar, planlayıcılar, gövde doğrulaması (DB'siz).
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { computePlan } from '../src/modules/bulk_import_plan.js';
import { validateImportBody, requestFingerprint } from '../src/modules/bulk_import_body.js';
import { readAccount, readMoney } from '../src/modules/bulk_import_parsers.js';
import { BULK_KINDS, buildSpec, headerIndexOf, columnsOf } from '../src/modules/bulk_import_spec.js';

const TODAY = '2026-10-21';

function makeSnapshot() {
  const apartments = [1, 2, 3].map((n) => ({
    id: 100 + n, blockId: 1, label: `Daire ${n}`, floor: null, category: null, lsNum: null, lsDen: null, responsible: 'both', hasFinance: false,
  }));
  return {
    blocks: [{ id: 1, name: 'A Blok' }],
    apartments,
    people: [],
    residencies: [],
    vehicles: [],
    opening: { existing: new Map(), tenantApts: new Set([102]), inactive: new Set(), otherLedger: new Set(), cutoverClosed: false },
  };
}
const row = (n, cells) => ({ n, cells });

describe('readMoney / readAccount', () => {
  it('TR ve düz tutarları kuruşa çevirir', () => {
    for (const [input, minor] of [['1.250,50', 125050], ['1250.5', 125050], ['₺ 1.250', 125000], ['1250 TL', 125000], [1234.56, 123456], ['1,250.75', 125075]]) {
      assert.equal(readMoney(input).value, minor, String(input));
    }
  });
  it('geçersiz, eksi ve aşırı değerleri ayırır', () => {
    assert.equal(readMoney('abc').error, 'MONEY_INVALID');
    assert.equal(readMoney('1.2.3').error, 'MONEY_INVALID');
    assert.equal(readMoney('-300').value, -30000);
    assert.equal(readMoney('=1+1').error, 'FORMULA_LIKE');
    assert.equal(readMoney('99999999999999').error, 'MONEY_RANGE');
  });
  it('hesap sözcükleri', () => {
    assert.equal(readAccount('Kiracı').value, 'tenant');
    assert.equal(readAccount('Ev sahibi').value, 'owner');
    assert.equal(readAccount('Malik').value, 'owner');
    assert.equal(readAccount('xyz').error, 'ACCOUNT_INVALID');
    assert.equal(readAccount('').value, null);
  });
});

describe('spec ve gövde', () => {
  it('yeni türler spec içinde ve başlıklar çakışmaz', () => {
    const spec = buildSpec();
    assert.ok(BULK_KINDS.includes('opening_balances') && BULK_KINDS.includes('all_in_one'));
    assert.ok(spec.kinds.opening_balances && spec.kinds.all_in_one);
    for (const kind of ['opening_balances', 'all_in_one']) {
      const labels = columnsOf(kind).flatMap((c) => [c.label, ...c.aliases]);
      assert.equal(headerIndexOf(kind).size, new Set(headerIndexOf(kind).keys()).size);
      assert.ok(labels.length > 0);
    }
    assert.ok(columnsOf('all_in_one').some((c) => c.key === 'giris_tarihi' && c.label === 'Taşınma Tarihi'));
  });
  it('options yalnız devirde; devir tarihi zorunlu; all_in_one ACK ister', () => {
    const rows = [row(1, { blok: 'A', daire_no: '1', tutar: '100' })];
    assert.throws(() => validateImportBody({ spec_version: 1, rows }, 'opening_balances'), { code: 'INVALID_BODY' });
    assert.throws(() => validateImportBody({ spec_version: 1, rows, options: { cutover_date: '2010-01-01' } }, 'opening_balances'), { code: 'INVALID_BODY' });
    const ok = validateImportBody({ spec_version: 1, rows, options: { cutover_date: TODAY } }, 'opening_balances');
    assert.equal(ok.options.cutover_date, TODAY);
    assert.throws(() => validateImportBody({ spec_version: 1, rows: [row(1, { blok: 'A' })], options: { cutover_date: TODAY } }, 'apartments'), { code: 'INVALID_BODY' });
    const commit = { spec_version: 1, rows, expected_hash: 'a'.repeat(64), idempotency_key: 'abcdefgh1', options: { cutover_date: TODAY, expected_total_minor: 10000 } };
    assert.equal(validateImportBody(commit, 'opening_balances', { commit: true }).options.expected_total_minor, 10000);
    const aio = { spec_version: 1, rows: [row(1, { blok: 'A', daire_no: '1' })], expected_hash: 'a'.repeat(64), idempotency_key: 'abcdefgh1' };
    assert.throws(() => validateImportBody(aio, 'all_in_one', { commit: true }), { code: 'ACK_REQUIRED' });
    assert.equal(validateImportBody({ ...aio, acknowledged: true, allow_overwrite: true }, 'all_in_one', { commit: true }).allowOverwrite, true);
  });
  it('parmak izi seçenekleri kapsar', () => {
    const rows = [row(1, { blok: 'A', daire_no: '1' })];
    const a = requestFingerprint({ kind: 'opening_balances', rows, options: { cutover_date: '2026-10-01' } });
    const b = requestFingerprint({ kind: 'opening_balances', rows, options: { cutover_date: '2026-10-02' } });
    assert.notEqual(a, b);
  });
});

describe('planOpening', () => {
  const options = { cutover_date: '2026-10-01' };
  const plan = (rows, snapshot = makeSnapshot(), opts = options) => computePlan({ kind: 'opening_balances', rows, snapshot, today: TODAY, options: opts });

  it('geçerli satırlar defter işlemi üretir; toplam kuruş', () => {
    const result = plan([
      row(1, { blok: 'A', daire_no: '1', tutar: '1.250,50' }),
      row(2, { blok: 'A', daire_no: '2', hesap: 'Kiracı', tutar: '300', vade: '15.09.2026', aciklama: 'Eski borç' }),
    ]);
    assert.equal(result.totals.ok, 2);
    assert.equal(result.counts.total_minor, 125050 + 30000);
    assert.deepEqual(result.ops[0], { t: 'ob', aptId: 101, account: 'owner', minor: 125050, due: '2026-10-01', desc: null });
    assert.equal(result.ops[1].account, 'tenant');
    assert.equal(result.ops[1].due, '2026-09-15');
  });
  it('eksi tutar, sıfır, tekrar ve kiracısız uyarısı', () => {
    const result = plan([
      row(1, { blok: 'A', daire_no: '1', tutar: '-50' }),
      row(2, { blok: 'A', daire_no: '2', tutar: '0' }),
      row(3, { blok: 'A', daire_no: '3', tutar: '10' }),
      row(4, { blok: 'A', daire_no: '3', tutar: '20' }),
      row(5, { blok: 'A', daire_no: '3', hesap: 'Kiracı', tutar: '20' }),
    ]);
    const codes = result.view.issues.map((i) => `${i.n}:${i.code}`);
    assert.ok(codes.includes('1:OPENING_CREDIT_UNSUPPORTED'));
    assert.ok(codes.includes('2:OPENING_ZERO'));
    assert.ok(codes.includes('4:DUPLICATE_IN_FILE'));
    assert.ok(codes.includes('5:NO_TENANT'));
    assert.equal(result.counts.total_minor, 3000);
  });
  it('etkin devir: aynı değer değişiklik yok, farklı değer hata', () => {
    const snapshot = makeSnapshot();
    snapshot.opening.existing.set('101:owner', { minor: 10000, due: '2026-10-01', desc: null });
    const same = plan([row(1, { blok: 'A', daire_no: '1', tutar: '100' })], snapshot);
    assert.equal(same.totals.unchanged, 1);
    assert.equal(same.ops.length, 0);
    const diff = plan([row(1, { blok: 'A', daire_no: '1', tutar: '101' })], snapshot);
    assert.equal(diff.totals.error, 1);
    assert.equal(diff.view.issues[0].code, 'OPENING_EXISTS');
  });
  it('kapalı ay ve devir tarihi hash kapsamındadır', () => {
    const snapshot = makeSnapshot();
    snapshot.opening.cutoverClosed = true;
    assert.equal(plan([row(1, { blok: 'A', daire_no: '1', tutar: '5' })], snapshot).totals.error, 1);
    const rows = [row(1, { blok: 'A', daire_no: '1', tutar: '5' })];
    assert.notEqual(plan(rows).previewHash, plan(rows, makeSnapshot(), { cutover_date: '2026-09-01' }).previewHash);
    assert.equal(plan(rows).previewHash, plan(rows).previewHash);
  });
});

describe('planAllInOne', () => {
  const run = (rows, snapshot = makeSnapshot()) => computePlan({ kind: 'all_in_one', rows, snapshot, allowOverwrite: false, today: TODAY });

  it('aynı dairede 3 kişi tek daire güncellemesi üretir', () => {
    const result = run([
      row(1, { blok: 'A', daire_no: '1', kat: '2', tip: '3+1', ad_soyad: 'Ali Yılmaz', iliski: 'Malik', telefon: '5551234567' }),
      row(2, { blok: 'A', daire_no: '1', ad_soyad: 'Ayşe Yılmaz', iliski: 'Aile' }),
      row(3, { blok: 'A', daire_no: '1', kat: '2', ad_soyad: 'Can Yılmaz', iliski: 'Aile', plaka: '34 ABC 123' }),
    ]);
    assert.equal(result.totals.error, 0);
    assert.equal(result.ops.filter((op) => op.t === 'au').length, 1);
    assert.equal(result.ops.filter((op) => op.t === 'pc').length, 3);
    assert.equal(result.ops.filter((op) => op.t === 'va').length, 1);
  });
  it('farklı daire değeri APARTMENT_VALUES_CONFLICT', () => {
    const result = run([
      row(1, { blok: 'A', daire_no: '1', kat: '2', ad_soyad: 'Ali Yılmaz' }),
      row(2, { blok: 'A', daire_no: '1', kat: '3', ad_soyad: 'Ayşe Yılmaz', iliski: 'Aile' }),
    ]);
    assert.equal(result.totals.error, 1);
    assert.equal(result.view.issues.find((i) => i.code === 'APARTMENT_VALUES_CONFLICT').n, 2);
    assert.equal(result.ops.filter((op) => op.t === 'pc').length, 1);
  });
  it('satır atomik: kişi bölümü hatalıysa daire işlemi de düşer', () => {
    const result = run([row(1, { blok: 'A', daire_no: '2', kat: '1', ad_soyad: 'X' })]);
    assert.equal(result.totals.error, 1);
    assert.equal(result.ops.length, 0);
  });
  it('yalnız daire bilgisi (kişisiz) satırı çalışır; bilinmeyen daire hata', () => {
    const result = run([row(1, { blok: 'A', daire_no: '3', kat: '4' }), row(2, { blok: 'A', daire_no: '9', ad_soyad: 'Veli Kaya' })]);
    assert.equal(result.ops.filter((op) => op.t === 'au').length, 1);
    assert.equal(result.view.issues.find((i) => i.n === 2).code, 'APARTMENT_NOT_FOUND');
  });

  const codes = (result, n) => result.view.issues.filter((issue) => issue.n === n).map((issue) => `${issue.severity[0]}:${issue.code}`);

  it('daire alanı hatası KAYNAK satıra yazılır; taşıyıcı (ilk satır) kişisiyle normal işlenir ve "daire uygulanmadı" uyarısı alır', () => {
    const result = run([
      row(1, { blok: 'A', daire_no: '1', kat: '2', ad_soyad: 'Ali Yılmaz', iliski: 'Malik' }),
      row(2, { blok: 'A', daire_no: '1', tip: 'x'.repeat(41), ad_soyad: 'Ayşe Yılmaz', iliski: 'Aile' }),
      row(3, { blok: 'A', daire_no: '1', ad_soyad: 'Can Yılmaz', iliski: 'Aile' }),
    ]);
    assert.deepEqual(codes(result, 2), ['e:TOO_LONG'], 'hata değeri yazan satırda');
    assert.deepEqual(codes(result, 1), ['w:APARTMENT_NOT_APPLIED'], 'taşıyıcıda hata YOK, yalnız açıklayıcı uyarı');
    assert.match(result.view.issues.find((i) => i.n === 1).message, /satır 2/);
    assert.deepEqual(codes(result, 3), []);
    assert.equal(result.ops.filter((op) => op.t === 'au').length, 0, 'dairenin birleşik hücrelerinden biri hatalı: daire işlemi düşer (tutarlı)');
    // taşıyıcının kişisi ve hatasız satırın kişisi işlenir; hatalı satırın kişisi işlenmez
    assert.deepEqual(result.ops.filter((op) => op.t === 'pc').map((op) => op.name), ['Ali Yılmaz', 'Can Yılmaz']);
    assert.equal(result.totals.error, 1);
    assert.equal(result.results.find((r) => r.n === 1).status, 'ok');
    assert.equal(result.results.find((r) => r.n === 2).status, 'error');
  });

  it('taşıyıcının KENDİ daire hücresi hatalıysa taşıyıcı hatalı sayılır (kişisi işlenmez); diğer satırların kişileri işlenir', () => {
    const result = run([
      row(1, { blok: 'A', daire_no: '1', kat: 'yedinci', ad_soyad: 'Ali Yılmaz' }),
      row(2, { blok: 'A', daire_no: '1', ad_soyad: 'Ayşe Yılmaz', iliski: 'Aile' }),
    ]);
    assert.deepEqual(codes(result, 1), ['e:FLOOR_INVALID']);
    assert.deepEqual(codes(result, 2), []);
    assert.equal(result.ops.filter((op) => op.t === 'au').length, 0);
    assert.deepEqual(result.ops.filter((op) => op.t === 'pc').map((op) => op.name), ['Ayşe Yılmaz']);
  });

  it('arsa payı çifti farklı satırlardaysa LAND_SHARE_INVALID pay hücresini yazan satıra gider', () => {
    const result = run([
      row(1, { blok: 'A', daire_no: '1', ad_soyad: 'Ali Yılmaz' }),
      row(2, { blok: 'A', daire_no: '1', arsa_payi_pay: 50, ad_soyad: 'Ayşe Yılmaz', iliski: 'Aile' }), // payda yok -> geçersiz
    ]);
    assert.deepEqual(codes(result, 2), ['e:LAND_SHARE_INVALID']);
    assert.deepEqual(codes(result, 1), ['w:APARTMENT_NOT_APPLIED']);
  });

  it('ESKİ m² SÜTUNLARI: gövde kabul eder, yok sayar, dosya başına tek uyarı verir; daire işlemi m² içermez', () => {
    const body = { spec_version: 1, acknowledged: true, rows: [
      { n: 2, cells: { blok: 'A', daire_no: '1', kat: '2', brut_m2: '120', net_m2: 100, ad_soyad: 'Ali Yılmaz' } },
      { n: 3, cells: { blok: 'A', daire_no: '2', brut_m2: '90', ad_soyad: 'Veli Kaya' } },
    ] };
    const rows = validateImportBody(body, 'all_in_one').rows;
    const result = run(rows);
    assert.deepEqual(codes(result, 2), ['w:AREA_COLUMN_IGNORED']);
    assert.deepEqual(codes(result, 3), []);
    assert.equal(result.totals.error, 0);
    assert.deepEqual(result.ops.filter((op) => op.t === 'au').map((op) => op.set), [{ floor: 2 }]);
    // yalnız eski anahtarlar kabul edilir: başka tanımsız anahtar hâlâ 400
    assert.throws(() => validateImportBody({ spec_version: 1, rows: [{ n: 2, cells: { blok: 'A', daire_no: '1', alan_m2: 5 } }] }, 'all_in_one'), (error) => error.code === 'INVALID_BODY');
    // spec/şablonda m² sütunu yok
    assert.equal(buildSpec().kinds.all_in_one.columns.some((c) => /m2$/.test(c.key)), false);
    assert.equal(buildSpec().kinds.apartments.columns.some((c) => /m2$/.test(c.key)), false);
  });

  it('hesap açılacak kişi sayısı (account_create): yalnız daire ilişkisi eklenen kişiler; dairesiz ve daire-yalnız satırlar sayılmaz', () => {
    const result = run([
      row(1, { blok: 'A', daire_no: '1', kat: '2', ad_soyad: 'Ali Yılmaz', iliski: 'Malik' }),
      row(2, { blok: 'A', daire_no: '1', ad_soyad: 'Ayşe Yılmaz', iliski: 'Aile' }),
      row(3, { blok: 'A', daire_no: '3', kat: '4' }),
      row(4, { ad_soyad: 'Dairesiz Kişi', e_posta: 'd@example.com' }),
    ]);
    assert.equal(result.counts.account_create, 2);
  });
});
