// Belgeler (Faz 3b-A) sakin tarafı (DB'siz, KATI sahte veritabanı): CANLI görünürlük SQL'inin ZORUNLU koşulları, sayfalama, kimlik / IDOR kapıları, duyuru eki indirme
// koşulları (belgenin kendi hedefine BAKILMAZ), kısıtlı kişi eşitlemesi, indirme sayacı. Gerçek PostgreSQL doğrulaması: qa_platform_pg.mjs "documents" (G bölümü).
import { describe, it, beforeEach, after } from 'node:test';
import assert from 'node:assert/strict';
import { pool } from '../src/db.js';
import { SYNC_STEPS } from '../src/modules/people_sync_sql.js';
import { resetPeopleSyncThrottle } from '../src/modules/people_sync.js';
import {
  MODULE_ENABLED_SQL,
  bumpDownloadCount,
  documentVisibleToUserSql,
  getMyDocument,
  listMyDocuments,
  myApartmentsCte,
  resolveAnnouncementAttachmentDownload,
  resolveResidentDownload,
} from '../src/modules/document_resident.js';

process.env.PEOPLE_SYNC_MIN_INTERVAL_MS = '0';

const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
const ok = (rows = []) => ({ rows, rowCount: rows.length });
const STEP_SQLS = new Set(SYNC_STEPS.map((step) => norm(step.sql)));
const USER = { user_code: 20004, userCode: 20004, id: 20004, role: 'apartment_owner' };

let handlers;
let log;

beforeEach(() => {
  handlers = [];
  log = [];
  resetPeopleSyncThrottle();
  const run = async (text, params = []) => {
    const sql = norm(text);
    log.push({ sql, params });
    for (const [pattern, fn] of handlers) {
      if (pattern.test(sql)) return typeof fn === 'function' ? fn(sql, params) : fn;
    }
    if (/^SELECT DISTINCT a\.site_code FROM apartment_memberships am/.test(sql)) return ok();
    if (/^(BEGIN|COMMIT|ROLLBACK)$/.test(sql) || /^SELECT pg_advisory_xact_lock/.test(sql) || STEP_SQLS.has(sql)) return ok();
    if (/^SELECT pg_try_advisory_xact_lock/.test(sql)) return ok([{ locked: true }]);
    throw new Error(`BEKLENMEYEN SQL (sahte DB katı): ${sql.slice(0, 240)}`);
  };
  pool.query = async (text, params) => run(text, params);
  pool.connect = async () => ({ query: (text, params) => run(text, params), release() {} });
});

after(() => {
  delete pool.query;
  delete pool.connect;
});

const row = (id, over = {}) => ({
  id: String(id), site_code: '1000000001', site_name: 'Gül Sitesi', title: `Belge ${id}`, category: 'notice', description: 'açıklama', updated_at: new Date('2026-10-17T09:00:00Z'),
  cv_display_name: `belge-${id}.pdf`, cv_mime_type: 'application/pdf', cv_size_bytes: '2048', cv_version_no: 1, cv_completed_at: new Date('2026-10-17T10:00:00Z'), ...over,
});
const listQuery = () => log.find((entry) => /ORDER BY d\.id DESC LIMIT/.test(entry.sql));

describe('CANLI görünürlük SQL parçası', () => {
  const cte = norm(myApartmentsCte('$1'));
  const visible = norm(documentVisibleToUserSql('d', '$1'));

  it('CTE: yalnız çağıranın AKTİF kişi kaydı -> GÜNCEL ilişki (is_current) -> AKTİF daire (aynı site); bir kez hesaplanır (MATERIALIZED)', () => {
    assert.match(cte, /^my_apts AS MATERIALIZED \(/);
    for (const fragment of [
      'FROM site_people sp',
      'INNER JOIN apartment_residencies r ON r.person_id = sp.id AND r.is_current = TRUE',
      'INNER JOIN apartments ap ON ap.id = r.apartment_id AND ap.is_active = TRUE AND ap.site_code = sp.site_code',
      'WHERE sp.user_code = $1 AND sp.is_active = TRUE',
    ]) {
      assert.ok(cte.includes(fragment), fragment);
    }
  });

  it('görünürlük: hedef site / blok (block_id = ANY) / daire (id = ANY) karşılaştırması KÜMEDE; BOARD_MEMBER sitesindeki residents belgelerini hedefe bakmadan görür; sorgu kullanıcının siteleriyle başlar', () => {
    assert.ok(visible.includes("d.site_code IN ( SELECT sp0.site_code FROM site_people sp0 WHERE sp0.user_code = $1 AND sp0.is_active = TRUE UNION SELECT sm0.site_code FROM site_memberships sm0 WHERE sm0.user_code = $1 AND sm0.role = 'BOARD_MEMBER' AND sm0.is_active = TRUE )"));
    assert.ok(visible.includes("d.target_type = 'site'"));
    assert.ok(visible.includes("d.target_type = 'blocks' AND m.block_id = ANY(d.target_block_ids)"));
    assert.ok(visible.includes("d.target_type = 'apartments' AND m.id = ANY(d.target_apartment_ids)"));
    assert.ok(visible.includes("sm.role = 'BOARD_MEMBER' AND sm.is_active = TRUE"));
    assert.ok(!/FROM apartments/.test(visible), 'belge başına apartments taraması YOK (ölçek: 3000 daire x belge)');
    assert.ok(!/FROM apartment_residencies/.test(visible));
  });

  it('modül kapısı: Dosya Deposu TEMEL modül (Kural 25) olduğundan site_modules satırı yoksa AÇIK sayılır (satır varsa enabled değeri)', () => {
    assert.match(norm(MODULE_ENABLED_SQL('d')), /^COALESCE\(\(SELECT smod\.enabled FROM site_modules smod WHERE smod\.site_code = d\.site_code AND smod\.module_code = 'drive_storage'\), TRUE\)$/);
  });
});

describe('GET /app/documents', () => {
  it('sorgu: WITH my_apts; yalnız active + residents; onaylı site; güncel READY sürüm; modül açık; id DESC; çağıranın kodu $1; hesapsız / geçersiz kullanıcıda sorgu YOK', async () => {
    handlers.push([/^WITH my_apts AS MATERIALIZED/, ok([row(9), row(7)])]);
    const result = await listMyDocuments(USER, {});
    assert.deepEqual(result.items.map((item) => item.id), [9, 7]);
    assert.equal(result.next_before_id, null);
    const query = listQuery();
    assert.equal(query.params[0], 20004);
    for (const fragment of [
      "d.status = 'active' AND d.audience = 'residents'",
      "INNER JOIN sites s ON s.site_code = d.site_code AND s.approval_status = 'approved'",
      "INNER JOIN document_versions cv ON cv.document_id = d.id AND cv.version_no = d.current_version_no AND cv.status = 'ready'",
      "smod.module_code = 'drive_storage'), TRUE)",
      'ORDER BY d.id DESC',
    ]) {
      assert.ok(query.sql.includes(fragment), fragment);
    }
    log.length = 0;
    assert.deepEqual(await listMyDocuments({ role: 'x' }, {}), { items: [], next_before_id: null });
    assert.equal(log.length, 0);
  });

  it('imeç sayfalama: limit + 1 satır istenir; fazlası varsa next_before_id son kayıt; before_id `d.id < $n`; süzgeçler parametreli', async () => {
    handlers.push([/^WITH my_apts AS MATERIALIZED/, ok([row(9), row(8), row(7)])]);
    const page = await listMyDocuments(USER, { limit: '2', before_id: '50', category: 'contract', site_code: '1000000001', q: 'Tutanak' });
    assert.deepEqual(page.items.map((item) => item.id), [9, 8]);
    assert.equal(page.next_before_id, 8);
    const query = listQuery();
    assert.equal(query.params[query.params.length - 1], 3, 'LIMIT limit+1');
    assert.ok(query.params.includes(50) && query.params.includes('contract') && query.params.includes(1000000001));
    assert.ok(/d\.id < \$\d+/.test(query.sql) && /d\.site_code = \$\d+/.test(query.sql) && /d\.category = \$\d+/.test(query.sql));
    assert.ok(query.params.some((param) => typeof param === 'string' && param === '%tutanak%'), 'arama Türkçe-duyarsız katlanmış');
    assert.ok(!query.sql.includes('Tutanak') && !query.sql.includes('tutanak'), 'arama metni SQL\'e gömülmez');
  });

  it('öğe alanları sözleşmedeki gibi (sakin): description, file_name, is_updated, updated_at = güncel sürüm tamamlanma zamanı', async () => {
    handlers.push([/^WITH my_apts AS MATERIALIZED/, ok([row(9, { cv_version_no: 3 })])]);
    const { items } = await listMyDocuments(USER, {});
    assert.deepEqual(Object.keys(items[0]), ['id', 'site_code', 'site_name', 'title', 'category', 'description', 'file_name', 'mime_type', 'size_bytes', 'version_no', 'is_updated', 'updated_at']);
    assert.equal(items[0].is_updated, true);
    assert.equal(items[0].updated_at, '2026-10-17T10:00:00.000Z');
    assert.equal(items[0].size_bytes, 2048);
  });

  it('hesabı olup kişi kaydı henüz olmayan yeni onaylı üye için KISITLI eşitleme: ilgili sitenin kişi kilidi try-lock ile alınır (okuma kilidi BEKLEMEZ)', async () => {
    handlers.push(
      [/^SELECT DISTINCT a\.site_code FROM apartment_memberships am/, ok([{ site_code: '1000000001' }])],
      [/^WITH my_apts AS MATERIALIZED/, ok([row(9)])],
    );
    await listMyDocuments(USER, {});
    const lock = log.find((entry) => /^SELECT pg_try_advisory_xact_lock/.test(entry.sql));
    assert.ok(lock, 'try-lock çağrıldı');
    assert.deepEqual(lock.params, ['people_sync:1000000001']);
    assert.ok(log.findIndex((entry) => /pg_try_advisory_xact_lock/.test(entry.sql)) < log.findIndex((entry) => /^WITH my_apts/.test(entry.sql)), 'eşitleme listeden ÖNCE');
  });
});

describe('ayrıntı ve indirme çözümleme', () => {
  it('ayrıntı: görünmeyen / yok / geçersiz kimlik 404 DOCUMENT_NOT_FOUND (varlık sızmaz); kullanıcı kodu ve belge kimliği parametreli', async () => {
    handlers.push([/^WITH my_apts AS MATERIALIZED/, ok()]);
    await assert.rejects(getMyDocument(USER, '55'), (error) => error.statusCode === 404 && error.code === 'DOCUMENT_NOT_FOUND');
    assert.deepEqual(log.find((entry) => /^WITH my_apts/.test(entry.sql)).params, [20004, 55]);
    for (const bad of ['abc', '0', '-1', undefined]) {
      await assert.rejects(getMyDocument(USER, bad), (error) => error.code === 'DOCUMENT_NOT_FOUND', String(bad));
    }
    handlers = [[/^WITH my_apts AS MATERIALIZED/, ok([row(55)])]];
    const detail = await getMyDocument(USER, '55');
    assert.equal(detail.description, 'açıklama');
  });

  it('indirme çözümleme: görünürlük SQL\'i + güncel sürüm; alanlar depolama anahtarı / boyut / ad / MIME', async () => {
    handlers.push([/^WITH my_apts AS MATERIALIZED/, ok([{ id: '55', version_id: '700', version_no: 2, storage_key: '1000000001/123e4567-e89b-42d3-a456-426614174000', size_bytes: '99', display_name: 'a.pdf', mime_type: 'application/pdf' }])]);
    const target = await resolveResidentDownload(USER, '55');
    assert.deepEqual(target, { documentId: 55, versionId: 700, versionNo: 2, storageKey: '1000000001/123e4567-e89b-42d3-a456-426614174000', sizeBytes: 99, displayName: 'a.pdf', mimeType: 'application/pdf' });
    const query = log.find((entry) => /^WITH my_apts/.test(entry.sql));
    assert.match(query.sql, /d\.status = 'active' AND d\.audience = 'residents'/);
    handlers = [[/^WITH my_apts AS MATERIALIZED/, ok()]];
    await assert.rejects(resolveResidentDownload(USER, '56'), { code: 'DOCUMENT_NOT_FOUND' });
  });

  it('duyuru eki indirme: ALICI olma (published duyuru + onaylı site + alıcı kişi = çağıran) + ekli + belge active + modül açık; belge active + kitlesi residents (hedef daire / blok BAKILMAZ) + çağıranın o sitede hâlâ AKTİF ilişkisi (R16 P2-5)', async () => {
    handlers.push([/^WITH my_apts AS MATERIALIZED .* SELECT d\.id, cv\.id AS version_id/, ok([{ id: '9', version_id: '700', version_no: 1, storage_key: '1000000001/123e4567-e89b-42d3-a456-426614174000', size_bytes: '10', display_name: 'ek.pdf', mime_type: 'application/pdf' }])]);
    const target = await resolveAnnouncementAttachmentDownload(USER, '41', '9');
    assert.equal(target.documentId, 9);
    const query = log[0];
    assert.deepEqual(query.params, [20004, 41, 9]);
    for (const fragment of [
      "INNER JOIN announcements a ON a.id = aa.announcement_id AND a.status = 'published'",
      "INNER JOIN sites s ON s.site_code = a.site_code AND s.approval_status = 'approved'",
      'INNER JOIN announcement_recipients r ON r.announcement_id = a.id',
      'INNER JOIN site_people sp ON sp.id = r.person_id AND sp.user_code = $1',
      "INNER JOIN documents d ON d.id = aa.document_id AND d.site_code = a.site_code AND d.status = 'active' AND d.audience = 'residents'",
      "smod.module_code = 'drive_storage'), TRUE)",
      // R16 P2-5: taşınan / pasifleştirilen sakin eski duyurunun eki üzerinden belgeyi indiremez (doğrudan indirmedeki my_apts / aktif ilişki koşuluyla AYNI parça, hedef koşulu YOK)
      'WITH my_apts AS MATERIALIZED (',
      'WHERE sp.user_code = $1 AND sp.is_active = TRUE',
      'EXISTS (SELECT 1 FROM my_apts m WHERE m.site_code = d.site_code)',
      "sm.role = 'BOARD_MEMBER' AND sm.is_active = TRUE",
    ]) {
      assert.ok(query.sql.includes(fragment), fragment);
    }
    assert.ok(!/target_type|target_block_ids/.test(query.sql), 'belgenin hedef daire / blok listesine bakılmaz (sözleşme A12); kitle residents olmalıdır (R9 F1)');
    handlers = [[/^WITH my_apts AS MATERIALIZED .* SELECT d\.id, cv\.id AS version_id/, ok()]];
    await assert.rejects(resolveAnnouncementAttachmentDownload(USER, '41', '9'), { code: 'DOCUMENT_NOT_FOUND' });
    await assert.rejects(resolveAnnouncementAttachmentDownload(USER, 'abc', '9'), { code: 'DOCUMENT_NOT_FOUND' });
    await assert.rejects(resolveAnnouncementAttachmentDownload(USER, '41', '0'), { code: 'DOCUMENT_NOT_FOUND' });
  });
});

describe('indirme sayacı', () => {
  it('fire-and-forget artırır; sayaç hatası indirmeyi ETKİLEMEZ (fırlatmaz, işlenmemiş ret üretmez)', async () => {
    bumpDownloadCount(9);
    await new Promise((resolve) => setImmediate(resolve));
    assert.deepEqual(log.find((entry) => /^UPDATE documents SET download_count = download_count \+ 1 WHERE id = \$1$/.test(entry.sql))?.params, [9]);
    let rejected = false;
    const onRejection = () => { rejected = true; };
    process.once('unhandledRejection', onRejection);
    bumpDownloadCount(9, { query: async () => { throw new Error('DB yok'); } });
    bumpDownloadCount(9, { query: () => { throw new Error('senkron hata'); } });
    await new Promise((resolve) => setTimeout(resolve, 20));
    process.off('unhandledRejection', onRejection);
    assert.equal(rejected, false);
  });
});
