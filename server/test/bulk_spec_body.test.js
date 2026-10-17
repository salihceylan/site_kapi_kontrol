// Toplu yükleme (Faz 2b) sütun sözleşmesi ve istek gövdesi doğrulaması (DB'siz).
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import {
  BULK_KINDS,
  MAX_BODY_BYTES,
  MAX_ROWS_LIMIT,
  RELATION_WORDS,
  RESPONSIBLE_WORDS,
  SPEC_VERSION,
  buildSpec,
  columnsOf,
  foldHeader,
  headerIndexOf,
  isImportDisabled,
  maxRows,
} from '../src/modules/bulk_import_spec.js';
import { foldText } from '../src/modules/people_common.js';
import { requestFingerprint, validateImportBody } from '../src/modules/bulk_import_body.js';
import { ERROR_CODES, MESSAGE_MAX_LENGTH, WARNING_CODES, issueMessage } from '../src/modules/bulk_import_messages.js';

const HASH = 'a'.repeat(64);
const row = (n, cells = { blok: 'A', daire_no: '1' }) => ({ n, cells });
const body = (over = {}) => ({ spec_version: 1, rows: [row(2)], ...over });
const commitBody = (over = {}) => body({ expected_hash: HASH, idempotency_key: 'qa-key-0001', acknowledged: true, ...over });

function fails(fn, status, code) {
  assert.throws(fn, (error) => error.statusCode === status && error.code === code, `${status} ${code} bekleniyordu`);
}

describe('spec', () => {
  it('sürüm 1, 5000 satır, 5 MB; üç tür; her sütun anahtar/etiket/zorunlu/tip/ipucu taşır', () => {
    const spec = buildSpec({});
    assert.equal(spec.spec_version, SPEC_VERSION);
    assert.equal(spec.spec_version, 1);
    assert.equal(spec.max_rows, 5000);
    assert.equal(spec.max_body_bytes, 5242880);
    assert.equal(MAX_BODY_BYTES, 5242880);
    assert.deepEqual(Object.keys(spec.kinds).sort(), [...BULK_KINDS].sort());
    for (const kind of BULK_KINDS) {
      for (const column of spec.kinds[kind].columns) {
        assert.ok(column.key && column.label && typeof column.required === 'boolean' && column.hint, `${kind}.${column.key}`);
        assert.ok(['text', 'number', 'date', 'enum'].includes(column.type), column.type);
        assert.ok(Array.isArray(column.aliases));
      }
    }
  });

  it('sözleşmedeki sütun anahtarları ve zorunlulukları', () => {
    const required = (kind) => columnsOf(kind).filter((c) => c.required).map((c) => c.key);
    assert.deepEqual(columnsOf('apartments').map((c) => c.key), ['blok', 'daire_no', 'kat', 'tip', 'brut_m2', 'net_m2', 'arsa_payi_pay', 'arsa_payi_payda', 'sorumlu']);
    assert.deepEqual(required('apartments'), ['blok', 'daire_no']);
    assert.deepEqual(columnsOf('people').map((c) => c.key), ['ad_soyad', 'telefon', 'e_posta', 'blok', 'daire_no', 'iliski', 'giris_tarihi', 'plaka', 'not']);
    assert.deepEqual(required('people'), ['ad_soyad']);
    assert.deepEqual(columnsOf('vehicles').map((c) => c.key), ['plaka', 'e_posta', 'blok', 'daire_no', 'ad_soyad', 'not']);
    assert.deepEqual(required('vehicles'), ['plaka']);
    const labels = Object.fromEntries(columnsOf('apartments').map((c) => [c.key, c.label]));
    assert.equal(labels.brut_m2, 'Brüt m²');
    assert.equal(labels.arsa_payi_pay, 'Arsa Payı (Pay)');
    assert.equal(labels.sorumlu, 'Borç Sorumlusu');
  });

  it('başlık katlaması: aynı katlamış başlık aynı türde İKİ sütuna düşmez; etiketler kendi anahtarına gider', () => {
    for (const kind of BULK_KINDS) {
      const seen = new Map();
      for (const column of columnsOf(kind)) {
        for (const text of [column.label, ...column.aliases]) {
          const folded = foldHeader(text);
          assert.ok(folded.length > 0, `${kind}: boş katlama ${text}`);
          assert.ok(!seen.has(folded) || seen.get(folded) === column.key, `${kind}: «${text}» (${folded}) iki sütuna düşüyor`);
          seen.set(folded, column.key);
        }
      }
      const index = headerIndexOf(kind);
      for (const column of columnsOf(kind)) {
        assert.equal(index.get(foldHeader(column.label)), column.key, `${kind}.${column.key}`);
      }
    }
  });

  it('dışa aktarılan salt okunur sütunlar (Hesap, Durum, Malik, Kiracı, Sakin Sayısı, İlişki[araç]) hiçbir sütunun takma adı DEĞİL (yok sayılır)', () => {
    const people = headerIndexOf('people');
    const apartments = headerIndexOf('apartments');
    const vehicles = headerIndexOf('vehicles');
    for (const readonly of ['Hesap', 'Durum']) assert.equal(people.has(foldHeader(readonly)), false, readonly);
    for (const readonly of ['Malik', 'Kiracı', 'Sakin Sayısı']) assert.equal(apartments.has(foldHeader(readonly)), false, readonly);
    assert.equal(vehicles.has(foldHeader('İlişki')), false);
  });

  it('foldHeader: Türkçe katlama, noktalama/boşluk sadeleştirme, m² -> m2; foldText ile uyumlu', () => {
    assert.equal(foldHeader('  Brüt  m² '), 'brut m2');
    assert.equal(foldHeader('E-posta'), 'e posta');
    assert.equal(foldHeader('Arsa Payı (Pay)'), 'arsa payi pay');
    assert.equal(foldHeader('İLİŞKİ'), 'iliski');
    assert.equal(foldHeader('Ş-Ğ-Ü-Ö-Ç'), 's g u o c');
    assert.equal(foldText('ÇĞİÖŞÜçğıöşü'), 'cgiosucgiosu');
  });

  it('ilişki ve sorumlu sözcükleri spec ile aynı kaynaktan', () => {
    const spec = buildSpec({});
    assert.deepEqual(spec.kinds.people.relation_words, JSON.parse(JSON.stringify(RELATION_WORDS)));
    assert.deepEqual(spec.kinds.apartments.responsible_words, JSON.parse(JSON.stringify(RESPONSIBLE_WORDS)));
    assert.deepEqual(spec.kinds.apartments.relation_words, {});
  });

  it('ortam anahtarları: BULK_IMPORT_MAX_ROWS (varsayılan ve üst sınır 5000), BULK_IMPORT_DISABLED', () => {
    assert.equal(maxRows({}), 5000);
    assert.equal(maxRows({ BULK_IMPORT_MAX_ROWS: '200' }), 200);
    assert.equal(maxRows({ BULK_IMPORT_MAX_ROWS: '99999' }), MAX_ROWS_LIMIT);
    assert.equal(maxRows({ BULK_IMPORT_MAX_ROWS: '0' }), 5000);
    assert.equal(maxRows({ BULK_IMPORT_MAX_ROWS: 'abc' }), 5000);
    assert.equal(buildSpec({ BULK_IMPORT_MAX_ROWS: '300' }).max_rows, 300);
    assert.equal(isImportDisabled({}), false);
    assert.equal(isImportDisabled({ BULK_IMPORT_DISABLED: '1' }), true);
    assert.equal(isImportDisabled({ BULK_IMPORT_DISABLED: '0' }), false);
  });
});

describe('gövde doğrulaması', () => {
  it('geçerli gövde: satırlar Object.create(null) hücreleriyle döner', () => {
    const parsed = validateImportBody(body({ rows: [row(2, { blok: 'A', daire_no: 5, kat: null })] }), 'apartments');
    assert.equal(parsed.rows.length, 1);
    assert.equal(Object.getPrototypeOf(parsed.rows[0].cells), null);
    assert.deepEqual({ ...parsed.rows[0].cells }, { blok: 'A', daire_no: 5, kat: null });
    assert.equal(parsed.allowOverwrite, false);
  });

  it('spec_version: yok 400 INVALID_BODY; farklı 409 IMPORT_SPEC_MISMATCH', () => {
    fails(() => validateImportBody({ rows: [row(2)] }, 'apartments'), 400, 'INVALID_BODY');
    fails(() => validateImportBody(body({ spec_version: 2 }), 'apartments'), 409, 'IMPORT_SPEC_MISMATCH');
    fails(() => validateImportBody(body({ spec_version: '1' }), 'apartments'), 409, 'IMPORT_SPEC_MISMATCH');
  });

  it('rows: dizi olmalı; boş IMPORT_EMPTY; 5001 IMPORT_TOO_MANY_ROWS; ortam sınırı', () => {
    fails(() => validateImportBody(body({ rows: 'x' }), 'apartments'), 400, 'INVALID_BODY');
    fails(() => validateImportBody(body({ rows: [] }), 'apartments'), 400, 'IMPORT_EMPTY');
    const many = Array.from({ length: 5001 }, (_, i) => row(i + 2));
    fails(() => validateImportBody(body({ rows: many }), 'apartments'), 400, 'IMPORT_TOO_MANY_ROWS');
    assert.equal(validateImportBody(body({ rows: many.slice(0, 5000) }), 'apartments').rows.length, 5000);
    fails(() => validateImportBody(body({ rows: many.slice(0, 11) }), 'apartments', { env: { BULK_IMPORT_MAX_ROWS: '10' } }), 400, 'IMPORT_TOO_MANY_ROWS');
  });

  it('gövde/satır biçimi: gövde nesne olmalı; satır nesne; n artan ve tekil, pozitif tam sayı; cells nesne', () => {
    fails(() => validateImportBody(null, 'apartments'), 400, 'INVALID_BODY');
    fails(() => validateImportBody([], 'apartments'), 400, 'INVALID_BODY');
    fails(() => validateImportBody(body({ rows: [1] }), 'apartments'), 400, 'INVALID_BODY');
    fails(() => validateImportBody(body({ rows: [{ cells: {} }] }), 'apartments'), 400, 'INVALID_BODY');
    for (const n of [0, -1, 1.5, '2', null, 1e12]) {
      fails(() => validateImportBody(body({ rows: [{ n, cells: {} }] }), 'apartments'), 400, 'INVALID_BODY');
    }
    fails(() => validateImportBody(body({ rows: [row(3), row(3)] }), 'apartments'), 400, 'INVALID_BODY');
    fails(() => validateImportBody(body({ rows: [row(5), row(3)] }), 'apartments'), 400, 'INVALID_BODY');
    fails(() => validateImportBody(body({ rows: [{ n: 2, cells: [] }] }), 'apartments'), 400, 'INVALID_BODY');
    fails(() => validateImportBody(body({ rows: [{ n: 2, cells: 'x' }] }), 'apartments'), 400, 'INVALID_BODY');
  });

  it('hücre anahtarları spec beyaz listesinden; __proto__ / constructor / başka türün sütunu reddedilir', () => {
    fails(() => validateImportBody(body({ rows: [{ n: 2, cells: { bilinmeyen: 'x' } }] }), 'apartments'), 400, 'INVALID_BODY');
    fails(() => validateImportBody(body({ rows: [{ n: 2, cells: JSON.parse('{"__proto__": "x"}') }] }), 'apartments'), 400, 'INVALID_BODY');
    fails(() => validateImportBody(body({ rows: [{ n: 2, cells: JSON.parse('{"constructor": "x"}') }] }), 'apartments'), 400, 'INVALID_BODY');
    fails(() => validateImportBody(body({ rows: [{ n: 2, cells: { ad_soyad: 'x' } }] }), 'apartments'), 400, 'INVALID_BODY'); // kişi sütunu daire türünde yok
    fails(() => validateImportBody(body({ rows: [{ n: 2, cells: { kat: '1' } }] }), 'people'), 400, 'INVALID_BODY');
    // prototip kirlenmesi olmadı
    assert.equal({}.polluted, undefined);
    assert.equal(Object.prototype.hasOwnProperty.call(Object.prototype, 'x'), false);
  });

  it('hücre değerleri: metin | sonlu sayı | null; boolean/nesne/dizi reddedilir; çok uzun metin reddedilir (601-5000 satır hatasıdır, gövde hatası değil)', () => {
    for (const bad of [true, false, {}, [], [1]]) {
      fails(() => validateImportBody(body({ rows: [{ n: 2, cells: { blok: bad } }] }), 'apartments'), 400, 'INVALID_BODY');
    }
    fails(() => validateImportBody(body({ rows: [{ n: 2, cells: { blok: 1e15 } }] }), 'apartments'), 400, 'INVALID_BODY');
    fails(() => validateImportBody(body({ rows: [{ n: 2, cells: { blok: 'x'.repeat(5001) } }] }), 'apartments'), 400, 'INVALID_BODY');
    assert.doesNotThrow(() => validateImportBody(body({ rows: [{ n: 2, cells: { blok: 'x'.repeat(5000) } }] }), 'apartments'));
    assert.doesNotThrow(() => validateImportBody(body({ rows: [{ n: 2, cells: { blok: 'x'.repeat(700), daire_no: -5, kat: 0.5, tip: null } }] }), 'apartments'));
  });

  it('allow_overwrite: boolean; true yalnız daire türünde', () => {
    assert.equal(validateImportBody(body({ allow_overwrite: true }), 'apartments').allowOverwrite, true);
    fails(() => validateImportBody(body({ allow_overwrite: true }), 'people'), 400, 'INVALID_BODY');
    fails(() => validateImportBody(body({ allow_overwrite: true }), 'vehicles'), 400, 'INVALID_BODY');
    fails(() => validateImportBody(body({ allow_overwrite: 'evet' }), 'apartments'), 400, 'INVALID_BODY');
    assert.equal(validateImportBody(body({ allow_overwrite: false }), 'people').allowOverwrite, false);
  });
});

describe('commit gövdesi', () => {
  it('expected_hash (64 hex) ve idempotency_key (8-64, [a-z0-9-]) zorunlu', () => {
    assert.doesNotThrow(() => validateImportBody(commitBody(), 'people', { commit: true }));
    fails(() => validateImportBody(commitBody({ expected_hash: undefined }), 'people', { commit: true }), 400, 'INVALID_BODY');
    fails(() => validateImportBody(commitBody({ expected_hash: 'xyz' }), 'people', { commit: true }), 400, 'INVALID_BODY');
    fails(() => validateImportBody(commitBody({ expected_hash: 'A'.repeat(64) }), 'people', { commit: true }), 400, 'INVALID_BODY');
    fails(() => validateImportBody(commitBody({ idempotency_key: undefined }), 'people', { commit: true }), 400, 'INVALID_BODY');
    for (const bad of ['kisa', 'BÜYÜK-HARF-KEY', 'bosluk var key', 'x'.repeat(65), 'a_b_c_d_e_f_g']) {
      fails(() => validateImportBody(commitBody({ idempotency_key: bad }), 'people', { commit: true }), 400, 'INVALID_BODY');
    }
    assert.doesNotThrow(() => validateImportBody(commitBody({ idempotency_key: 'x'.repeat(64) }), 'people', { commit: true }));
    assert.doesNotThrow(() => validateImportBody(commitBody({ idempotency_key: '12345678' }), 'people', { commit: true }));
  });

  it('acknowledged: people/vehicles için ZORUNLU true (ACK_REQUIRED); daire için gerekmez', () => {
    fails(() => validateImportBody(commitBody({ acknowledged: false }), 'people', { commit: true }), 400, 'ACK_REQUIRED');
    fails(() => validateImportBody(commitBody({ acknowledged: undefined }), 'vehicles', { commit: true }), 400, 'ACK_REQUIRED');
    assert.doesNotThrow(() => validateImportBody(commitBody({ acknowledged: undefined }), 'apartments', { commit: true }));
    fails(() => validateImportBody(commitBody({ acknowledged: 'yes' }), 'people', { commit: true }), 400, 'INVALID_BODY');
    fails(() => validateImportBody(commitBody({ strict: 'x' }), 'apartments', { commit: true }), 400, 'INVALID_BODY');
    assert.equal(validateImportBody(commitBody({ strict: true }), 'apartments', { commit: true }).strict, true);
    assert.equal(validateImportBody(commitBody(), 'apartments', { commit: true }).strict, false);
  });

  it('önizleme gövdesi commit alanlarını İSTEMEZ', () => {
    assert.doesNotThrow(() => validateImportBody(body(), 'people', { commit: false }));
  });
});

describe('parmak izi', () => {
  const base = { kind: 'people', strict: false, allowOverwrite: false, rows: [row(2, { ad_soyad: 'Ali', e_posta: 'a@b.com' })] };
  it('kararlı: hücre anahtar sırasından bağımsız; ayrıntı değişirse değişir; expected_hash girmez', () => {
    const a = requestFingerprint(base);
    assert.match(a, /^[0-9a-f]{64}$/);
    const reordered = requestFingerprint({ ...base, rows: [{ n: 2, cells: Object.assign(Object.create(null), { e_posta: 'a@b.com', ad_soyad: 'Ali' }) }] });
    assert.equal(a, reordered);
    assert.notEqual(a, requestFingerprint({ ...base, strict: true }));
    assert.notEqual(a, requestFingerprint({ ...base, allowOverwrite: true }));
    assert.notEqual(a, requestFingerprint({ ...base, kind: 'vehicles' }));
    assert.notEqual(a, requestFingerprint({ ...base, rows: [row(3, { ad_soyad: 'Ali', e_posta: 'a@b.com' })] }));
    assert.notEqual(a, requestFingerprint({ ...base, rows: [row(2, { ad_soyad: 'Ali', e_posta: 'a@b.org' })] }));
  });
});

describe('iletiler', () => {
  it('her hata ve uyarı kodunun iletisi var, Türkçe, < 140 karakter, teknik ifade (SQL, kod adı, "undefined") yok', () => {
    const ctx = { label: 'Brüt m²', value: 'x'.repeat(200), max: 40, lead: '=', line: 7, blocks: ['A Blok', 'B Blok'], severity: 'error' };
    for (const code of [...ERROR_CODES, ...WARNING_CODES]) {
      const text = issueMessage(code, ctx);
      assert.ok(text.length <= MESSAGE_MAX_LENGTH, `${code} ${text.length}`);
      assert.ok(text.length > 5, code);
      assert.ok(!/undefined|null|\bSQL\b|Error|NaN|\[object/.test(text), `${code}: ${text}`);
      assert.ok(!text.includes('x'.repeat(41)), `${code} 40+ karakter yankılar`);
    }
    for (const severity of ['warning', 'error']) {
      assert.ok(issueMessage('DUPLICATE_IN_FILE', { line: 4, severity }).includes('4'));
    }
  });

  it('hücre değeri en çok 40 karakter yankılanır', () => {
    const text = issueMessage('EMAIL_INVALID', { value: `${'a'.repeat(100)}@` });
    assert.ok(text.includes('a'.repeat(39)) && !text.includes('a'.repeat(41)));
  });
});
