// Belgeler (Faz 3b-A) ortak sabitler, sınırlar, hata kodları, girdi doğrulayıcıları ve yanıt eşleyicileri (saf; DB'siz).
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import {
  AUDIENCES,
  CATEGORIES,
  documentLimits,
  mapResidentRow,
  mapSummaryRow,
  normalizeDescription,
  normalizeIdempotencyKey,
  normalizeNote,
  normalizeTitle,
  parseCreateInput,
  parseFileInput,
  parseListQuery,
  parsePatchInput,
  parseResidentQuery,
  parseVersionQuery,
  quotaExceeded,
  resolveTarget,
  tooLarge,
  usageBody,
} from '../src/modules/document_common.js';
import * as common from '../src/modules/document_common.js';

const limits = documentLimits({});
const rtlo = String.fromCodePoint(0x202e);
const zwsp = String.fromCodePoint(0x200b);
const code = (fn) => {
  try {
    fn();
    return null;
  } catch (error) {
    return `${error.statusCode}:${error.code}`;
  }
};

describe('sınırlar (ortam değişkenleri)', () => {
  it('varsayılanlar sözleşmedeki gibi: 10 MiB, 200 MiB, 2 GiB boş alan, 2000 belge, Office açık, 30 gün, 8 eşzamanlı yükleme, 14 gün yetim karantinası', () => {
    assert.deepEqual(limits, {
      maxFileBytes: 10485760,
      siteQuotaBytes: 209715200,
      minFreeBytes: 2147483648,
      maxPerSite: 2000,
      allowOffice: true,
      retentionDays: 30,
      uploadConcurrency: 8,
      orphanQuarantineDays: 14,
      downloadConcurrency: 32,
      maxVersions: 20,
      pendingPerUser: 5,
      uploadTtlMinutes: 120,
    });
  });

  it('geçerli değerler uygulanır; geçersiz / sınır dışı değer varsayılana DÖNER; 25 MiB üstü dosya sınırı YOK SAYILIR', () => {
    const custom = documentLimits({
      DOCUMENTS_MAX_FILE_BYTES: '5242880',
      DOCUMENTS_SITE_QUOTA_BYTES: '104857600',
      DOCUMENTS_MIN_FREE_BYTES: '0',
      DOCUMENTS_MAX_PER_SITE: '50',
      DOCUMENTS_RETENTION_DAYS: '7',
      DOCUMENTS_UPLOAD_CONCURRENCY: '2',
      DOCUMENTS_ORPHAN_QUARANTINE_DAYS: '30',
      DOCUMENTS_ALLOW_OFFICE: '0',
    });
    assert.equal(custom.orphanQuarantineDays, 30);
    assert.equal(custom.maxFileBytes, 5242880);
    assert.equal(custom.siteQuotaBytes, 104857600);
    assert.equal(custom.minFreeBytes, 0);
    assert.equal(custom.maxPerSite, 50);
    assert.equal(custom.retentionDays, 7);
    assert.equal(custom.uploadConcurrency, 2);
    assert.equal(custom.allowOffice, false);
    for (const [name, value] of [
      ['DOCUMENTS_MAX_FILE_BYTES', '26214401'],
      ['DOCUMENTS_MAX_FILE_BYTES', 'abc'],
      ['DOCUMENTS_MAX_FILE_BYTES', '-5'],
      ['DOCUMENTS_MAX_FILE_BYTES', '10.5'],
      ['DOCUMENTS_RETENTION_DAYS', '0'],
      ['DOCUMENTS_RETENTION_DAYS', '4000'],
      ['DOCUMENTS_ORPHAN_QUARANTINE_DAYS', '0'],
      ['DOCUMENTS_ORPHAN_QUARANTINE_DAYS', '4000'],
      ['DOCUMENTS_ORPHAN_QUARANTINE_DAYS', 'abc'],
      ['DOCUMENTS_UPLOAD_CONCURRENCY', '0'],
      ['DOCUMENTS_SITE_QUOTA_BYTES', '10'],
    ]) {
      const result = documentLimits({ [name]: value });
      assert.deepEqual(result, limits, `${name}=${value} varsayılana dönmeli`);
    }
    for (const value of ['off', 'false', 'no', '0']) assert.equal(documentLimits({ DOCUMENTS_ALLOW_OFFICE: value }).allowOffice, false, value);
    for (const value of ['1', 'true', '', undefined]) assert.equal(documentLimits({ DOCUMENTS_ALLOW_OFFICE: value }).allowOffice, true, String(value));
  });
});

describe('hata kodları (sözleşme A9)', () => {
  const expected = {
    documentNotFound: [404, 'DOCUMENT_NOT_FOUND'],
    versionNotFound: [404, 'DOCUMENT_VERSION_NOT_FOUND'],
    siteNotFound: [404, 'SITE_NOT_FOUND'],
    moduleDisabled: [403, 'MODULE_DISABLED'],
    emptyFile: [400, 'DOCUMENT_EMPTY'],
    sizeMismatch: [400, 'DOCUMENT_SIZE_MISMATCH'],
    lengthRequired: [411, 'LENGTH_REQUIRED'],
    typeNotAllowed: [415, 'DOCUMENT_TYPE_NOT_ALLOWED'],
    contentMismatch: [415, 'DOCUMENT_CONTENT_MISMATCH'],
    activeContent: [415, 'DOCUMENT_ACTIVE_CONTENT'],
    invalidContentType: [415, 'INVALID_CONTENT_TYPE'],
    pendingLimitReached: [409, 'UPLOAD_PENDING_LIMIT'],
    uploadBusy: [503, 'UPLOAD_BUSY'],
    storageNotConfigured: [503, 'DOCUMENT_STORAGE_NOT_CONFIGURED'],
    storageFull: [503, 'DOCUMENT_STORAGE_FULL'],
    attachmentNotAllowed: [409, 'ATTACHMENT_NOT_ALLOWED'],
    uploadAlreadyCompleted: [409, 'UPLOAD_ALREADY_COMPLETED'],
    uploadExpired: [410, 'UPLOAD_EXPIRED'],
    confirmRequired: [400, 'CONFIRM_REQUIRED'],
    accountDeleted: [401, 'ACCOUNT_DELETED'],
  };

  it('durum kodu + makine kodu sözleşmedeki gibi; mesajlar Türkçe ve 140 karakterden kısa', () => {
    for (const [name, [status, errorCode]] of Object.entries(expected)) {
      const error = common[name]();
      assert.equal(error.statusCode, status, name);
      assert.equal(error.code, errorCode, name);
      assert.ok(error.message.length > 8 && error.message.length < 140, `${name}: ${error.message}`);
    }
    assert.equal(common.moduleDisabled().extra.module, 'documents');
  });

  it('DOCUMENT_ACTIVE_CONTENT mesajı NEDENE göre doğrudur (R16 P2-1): gömülü nesne "betik, makro" diye anılmaz; extra.reason makine okunur', () => {
    const reasons = { script: /betik/, macro: /Makro/, embedded: /Gömülü nesne/, external: /Uzak şablon/, executable: /Çalıştırılabilir/ };
    for (const [reason, pattern] of Object.entries(reasons)) {
      const error = common.activeContent(reason);
      assert.equal(error.code, 'DOCUMENT_ACTIVE_CONTENT');
      assert.equal(error.statusCode, 415);
      assert.equal(error.extra.reason, reason);
      assert.match(error.message, pattern, reason);
      assert.ok(error.message.length < 140, error.message);
    }
    assert.ok(!/betik|makro/i.test(common.activeContent('embedded').message));
    assert.equal(common.activeContent().extra.reason, 'script', 'varsayılan neden: betik');
    assert.equal(common.activeContent('bilinmeyen').message, common.activeContent('script').message);
  });

  it('413 DOCUMENT_TOO_LARGE mesajı "En fazla 10 MB"; kota hatası MB cinsinden kullanılan / kota ve baytları taşır', () => {
    const large = tooLarge(10485760);
    assert.equal(large.statusCode, 413);
    assert.match(large.message, /En fazla 10 MB yükleyebilirsiniz/);
    assert.equal(large.extra.max_bytes, 10485760);
    const quota = quotaExceeded(199 * 1048576, 200 * 1048576);
    assert.equal(quota.code, 'DOCUMENT_QUOTA_EXCEEDED');
    assert.match(quota.message, /199 MB \/ 200 MB/);
    assert.match(quota.message, /kalıcı olarak silin/);
    assert.deepEqual(quota.extra, { used_bytes: 199 * 1048576, quota_bytes: 200 * 1048576 });
    assert.equal(common.documentLimitReached(2000).extra.document_limit, 2000);
    assert.equal(common.documentInUse(3).extra.attachments_count, 3);
  });
});

describe('metin doğrulayıcıları', () => {
  it('başlık: tek satır, boşluklar tekleştirilir, görünmez / yön karakterleri atılır, 1-120 kod noktası; Türkçe ve emoji korunur', () => {
    assert.equal(normalizeTitle('  Toplantı   Tutanağı\n 2026 '), 'Toplantı Tutanağı 2026');
    assert.equal(normalizeTitle(`Ba${rtlo}şlık${zwsp}`), 'Başlık');
    assert.equal(normalizeTitle('Çalışma 😀'), 'Çalışma 😀');
    assert.equal(code(() => normalizeTitle('')), '400:INVALID_BODY');
    assert.equal(code(() => normalizeTitle('   ')), '400:INVALID_BODY');
    assert.equal(code(() => normalizeTitle(null)), '400:INVALID_BODY');
    assert.equal(code(() => normalizeTitle('x'.repeat(121))), '400:INVALID_BODY');
    assert.equal(normalizeTitle('x'.repeat(120)).length, 120);
  });

  it('açıklama: isteğe bağlı (boş = null), satır sonları korunur, kontrol karakterleri atılır, en çok 1000; not en çok 200 ve tek satır', () => {
    assert.equal(normalizeDescription(undefined), null);
    assert.equal(normalizeDescription('   '), null);
    assert.equal(normalizeDescription('Birinci satır\r\nİkinci satır'), 'Birinci satır\nİkinci satır');
    assert.equal(normalizeDescription(`A${rtlo}B\u0007C`), 'ABC');
    assert.equal(code(() => normalizeDescription('y'.repeat(1001))), '400:INVALID_BODY');
    assert.equal(code(() => normalizeDescription(5)), '400:INVALID_BODY');
    assert.equal(normalizeNote(null), null);
    assert.equal(normalizeNote('İlk\nsürüm  notu'), 'İlk sürüm notu');
    assert.equal(code(() => normalizeNote('n'.repeat(201))), '400:INVALID_BODY');
  });

  it('işlem anahtarı 8-64 karakter [A-Za-z0-9_.:-]; başka biçim reddedilir', () => {
    assert.equal(normalizeIdempotencyKey(' doc-key-0001 '), 'doc-key-0001');
    for (const bad of ['kisa', 'x'.repeat(65), 'boşluk iceren anahtar', 'a/b/c/d/e/f/g', undefined, 12345678]) {
      assert.equal(code(() => normalizeIdempotencyKey(bad)), '400:INVALID_BODY', String(bad));
    }
  });
});

describe('oluşturma girdisi', () => {
  const body = (over = {}) => ({ title: 'Yönetmelik', category: 'regulation', audience: 'residents', file: { name: 'a.pdf', size: 1000 }, idempotency_key: 'create-key-0001', ...over });

  it('geçerli gövde ayrıştırılır; kitle ZORUNLU ve VARSAYILANSIZ; hedef verilmezse tüm site', () => {
    const input = parseCreateInput(body(), limits);
    assert.equal(input.audience, 'residents');
    assert.deepEqual(input.target, { type: 'site', blockIds: [], apartmentIds: [] });
    assert.deepEqual(input.file, { name: 'a.pdf', size: 1000, contentType: null });
    assert.equal(code(() => parseCreateInput(body({ audience: undefined }), limits)), '400:INVALID_BODY');
    assert.equal(code(() => parseCreateInput(body({ audience: 'public' }), limits)), '400:INVALID_BODY');
    assert.deepEqual([...AUDIENCES], ['residents', 'board', 'managers']);
    assert.deepEqual([...CATEGORIES], ['regulation', 'minutes', 'contract', 'notice', 'other']);
  });

  it('hedef: blok / daire kimlikleri artan sırada tekilleştirilir; yalnız sakin kitlesinde (aksi 400 INVALID_TARGET); geçersiz kimlik 400 INVALID_TARGET', () => {
    const blocks = parseCreateInput(body({ target: { type: 'blocks', block_ids: [9, 3, 3, '5'] } }), limits);
    assert.deepEqual(blocks.target, { type: 'blocks', blockIds: [3, 5, 9], apartmentIds: [] });
    assert.equal(code(() => parseCreateInput(body({ audience: 'board', target: { type: 'blocks', block_ids: [1] } }), limits)), '400:INVALID_TARGET');
    assert.equal(code(() => parseCreateInput(body({ audience: 'managers', target: { type: 'apartments', apartment_ids: [1] } }), limits)), '400:INVALID_TARGET');
    assert.deepEqual(parseCreateInput(body({ audience: 'board', target: { type: 'site' } }), limits).target.type, 'site');
    assert.equal(code(() => parseCreateInput(body({ target: { type: 'blocks', block_ids: [] } }), limits)), '400:INVALID_TARGET');
    assert.equal(code(() => parseCreateInput(body({ target: { type: 'blocks', block_ids: [0] } }), limits)), '400:INVALID_TARGET');
    assert.equal(code(() => parseCreateInput(body({ target: { type: 'apartments', apartment_ids: Array.from({ length: 501 }, (_, i) => i + 1) } }), limits)), '400:INVALID_TARGET');
    assert.equal(code(() => resolveTarget('board', { type: 'blocks', block_ids: [1] })), '400:INVALID_TARGET');
  });

  it('dosya bildirimi: ad zorunlu, boyut güvenli tamsayı; 0 -> 400 DOCUMENT_EMPTY; > sınır -> 413; metin boyut reddedilir; content_type yalnız ipucu', () => {
    assert.deepEqual(parseFileInput({ name: 'a.pdf', size: 10485760, content_type: ' Application/PDF ' }, limits), { name: 'a.pdf', size: 10485760, contentType: 'application/pdf' });
    assert.equal(code(() => parseFileInput({ name: 'a.pdf', size: 0 }, limits)), '400:DOCUMENT_EMPTY');
    assert.equal(code(() => parseFileInput({ name: 'a.pdf', size: 10485761 }, limits)), '413:DOCUMENT_TOO_LARGE');
    for (const bad of [{ name: '', size: 10 }, { name: 'a.pdf', size: '10' }, { name: 'a.pdf', size: -1 }, { name: 'a.pdf', size: 1.5 }, { name: 'a.pdf' }, { size: 10 }, null, 'metin', { name: 'x'.repeat(1001), size: 1 }]) {
      assert.equal(code(() => parseFileInput(bad, limits)), '400:INVALID_BODY', JSON.stringify(bad));
    }
  });

  it('PATCH: en az bir alan; yalnız bilinen alanlar; description null temizler; target null reddedilir; confirm yalnız true', () => {
    assert.equal(code(() => parsePatchInput({})), '400:INVALID_BODY');
    assert.equal(code(() => parsePatchInput({ dosya: 'x' })), '400:INVALID_BODY');
    const patch = parsePatchInput({ title: 'Yeni', description: null, category: 'minutes', confirm: true });
    assert.deepEqual(patch.keys, ['title', 'description', 'category']);
    assert.equal(patch.description, null);
    assert.equal(patch.confirm, true);
    assert.equal(parsePatchInput({ title: 'Yeni', confirm: 'true' }).confirm, false);
    assert.equal(code(() => parsePatchInput({ target: null })), '400:INVALID_BODY');
  });
});

describe('sorgu parametreleri', () => {
  it('yönetici listesi: varsayılan status=active, limit 30 (1-100), offset >= 0; geçersiz süzgeç 400 INVALID_QUERY', () => {
    const query = parseListQuery({});
    assert.deepEqual({ ...query }, { category: null, status: 'active', audience: null, q: null, limit: 30, offset: 0 });
    assert.equal(parseListQuery({ limit: '500' }).limit, 100);
    assert.equal(parseListQuery({ limit: '0' }).limit, 1);
    assert.equal(parseListQuery({ status: 'all', category: 'contract', audience: 'board', q: '  tutanak ' }).q, 'tutanak');
    for (const bad of [{ status: 'x' }, { category: 'yok' }, { audience: 'herkes' }, { offset: '-1' }]) {
      assert.equal(code(() => parseListQuery(bad)), '400:INVALID_QUERY', JSON.stringify(bad));
    }
  });

  it('sakin listesi: site_code / category / q / before_id / limit; geçersiz kimlik 400 INVALID_QUERY', () => {
    assert.deepEqual({ ...parseResidentQuery({}) }, { siteCode: null, category: null, q: null, beforeId: null, limit: 30 });
    assert.deepEqual({ ...parseResidentQuery({ site_code: '1000000001', before_id: '55', limit: '10', category: 'notice' }) }, { siteCode: 1000000001, category: 'notice', q: null, beforeId: 55, limit: 10 });
    assert.equal(code(() => parseResidentQuery({ before_id: 'abc' })), '400:INVALID_QUERY');
    assert.equal(code(() => parseResidentQuery({ site_code: '-1' })), '400:INVALID_QUERY');
  });

  it('?version= : yok = güncel (null); geçersiz 404 DOCUMENT_VERSION_NOT_FOUND', () => {
    assert.equal(parseVersionQuery(undefined), null);
    assert.equal(parseVersionQuery('3'), 3);
    assert.equal(code(() => parseVersionQuery('abc')), '404:DOCUMENT_VERSION_NOT_FOUND');
    assert.equal(code(() => parseVersionQuery('0')), '404:DOCUMENT_VERSION_NOT_FOUND');
  });
});

describe('yanıt eşleyicileri', () => {
  const row = {
    id: '12', title: 'Başlık', category: 'minutes', audience: 'board', target_type: 'site', status: 'active', version_count: 2, download_count: '7',
    created_at: new Date('2026-10-17T10:00:00Z'), updated_at: new Date('2026-10-17T11:00:00Z'), deleted_at: null, days_until_purge: null,
    cv_version_no: 2, cv_display_name: 'tutanak.pdf', cv_mime_type: 'application/pdf', cv_size_bytes: '2048', cv_completed_at: new Date('2026-10-17T10:30:00Z'), uploaded_by_name: 'Ayşe Yönetici',
  };

  it('DocumentSummary alanları sözleşmedeki gibi; kurul yanıtında uploaded_by_name ANAHTARI da yoktur', () => {
    const manager = mapSummaryRow(row);
    assert.deepEqual(Object.keys(manager), ['id', 'title', 'category', 'audience', 'target_type', 'target_labels', 'status', 'version_count', 'download_count', 'current_version', 'created_at', 'updated_at', 'deleted_at', 'days_until_purge', 'uploaded_by_name']);
    assert.deepEqual(manager.current_version, { version_no: 2, file_name: 'tutanak.pdf', mime_type: 'application/pdf', size_bytes: 2048, completed_at: '2026-10-17T10:30:00.000Z' });
    assert.equal(manager.download_count, 7);
    const board = mapSummaryRow(row, { canSeeUploader: false });
    assert.ok(!('uploaded_by_name' in board));
    assert.equal(mapSummaryRow({ ...row, cv_version_no: null }).current_version, null);
  });

  it('sakin satırı: is_updated (v > 1), updated_at = güncel sürümün tamamlanma zamanı; ayrıntıda description', () => {
    const resident = mapResidentRow({ ...row, site_code: '1000000001', site_name: 'Gül', description: 'açıklama' }, { withDescription: true });
    assert.deepEqual(Object.keys(resident), ['id', 'site_code', 'site_name', 'title', 'category', 'description', 'file_name', 'mime_type', 'size_bytes', 'version_no', 'is_updated', 'updated_at']);
    assert.equal(resident.is_updated, true);
    assert.equal(resident.updated_at, '2026-10-17T10:30:00.000Z');
    assert.equal(mapResidentRow({ ...row, cv_version_no: 1, site_code: 1, description: null }).is_updated, false);
  });

  it('usage gövdesi kota / sayı sınırlarını verilen limitlerden alır', () => {
    assert.deepEqual(usageBody({ used_bytes: '1048576', document_count: 3 }, limits), { used_bytes: 1048576, quota_bytes: 209715200, document_count: 3, document_limit: 2000 });
    assert.deepEqual(usageBody(undefined, limits), { used_bytes: 0, quota_bytes: 209715200, document_count: 0, document_limit: 2000 });
  });
});
