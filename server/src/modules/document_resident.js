// Belgeler (Faz 3b-A): sakin tarafı (liste, ayrıntı, indirme çözümlemesi) ve duyuru eki indirme çözümlemesi.
//
// Sözleşme: docs/PLATFORM_BELGELER.md A6/A7/A12. Sakin kuralı CANLI değerlendirilir (anlık görüntü ALINMAZ): çağıranın `site_people` kaydı AKTİF ve aynı sitede
// AKTİF bir dairede GÜNCEL (`is_current`) ilişkisi var; hedef `site` ise yeter, `blocks` ise dairenin `block_id`si hedef dizide, `apartments` ise `apartments.id`
// hedef dizide. Site `approved`, `documents` modülü AÇIK olmalı. Tek bir SQL parçası (`documentVisibleToUserSql`) liste + ayrıntı + indirme yolunda kullanılır.
// BOARD_MEMBER, sitesinin `residents` belgelerini hedefe bakılmaksızın görür (A6). Hesapsız kişi indiremez (kimliksiz uç yok). Başkasının satırına ASLA erişilmez.

import { pool } from '../db.js';
import { escapeLike, foldSql, foldText } from './people_common.js';
import { syncSitePeopleSafe } from './people_sync.js';
import { documentNotFound, mapResidentRow, parsePositiveId, parseResidentQuery } from './document_common.js';

const INT32_MAX = 2147483647;

function userCodeOf(authUser) {
  return parsePositiveId(authUser?.user_code ?? authUser?.userCode ?? authUser?.id, INT32_MAX);
}

/**
 * Çağıranın KENDİ güncel daireleri (CTE, bir kez hesaplanır): AKTİF site_people kaydı -> GÜNCEL (`is_current`) ilişki -> AKTİF daire. Belge başına alt sorgu
 * yerine bu küçük küme (genelde 1-3 satır) kullanılır: 3000 daireli sitede "belge başına apartments taraması" (27 milyon indeks araması, ölçüldü) olmaz.
 * Kullanan her sorgu `WITH ${myApartmentsCte('$1')}` ile başlar.
 */
export function myApartmentsCte(user = '$1') {
  return `my_apts AS MATERIALIZED (
    SELECT ap.id, ap.block_id, ap.site_code
    FROM site_people sp
    INNER JOIN apartment_residencies r ON r.person_id = sp.id AND r.is_current = TRUE
    INNER JOIN apartments ap ON ap.id = r.apartment_id AND ap.is_active = TRUE AND ap.site_code = sp.site_code
    WHERE sp.user_code = ${user} AND sp.is_active = TRUE
  )`;
}

/**
 * Belgeyi çağıranın görüp göremeyeceği (WHERE parçası; `my_apts` CTE'si gerekir). `d`: belge tablosu takma adı, `user`: kullanıcı kodu parametresi ($n).
 * İlk koşul (`d.site_code IN (...)`) sorguyu çağıranın KENDİ sitelerinden başlatır (documents üzerinde sıralı tarama olmasın).
 */
export function documentVisibleToUserSql(d = 'd', user = '$1') {
  return `(
    ${d}.site_code IN (
      SELECT sp0.site_code FROM site_people sp0 WHERE sp0.user_code = ${user} AND sp0.is_active = TRUE
      UNION
      SELECT sm0.site_code FROM site_memberships sm0 WHERE sm0.user_code = ${user} AND sm0.role = 'BOARD_MEMBER' AND sm0.is_active = TRUE
    )
    AND (
      EXISTS (
        SELECT 1
        FROM my_apts m
        WHERE m.site_code = ${d}.site_code
          AND (
            ${d}.target_type = 'site'
            OR (${d}.target_type = 'blocks' AND m.block_id = ANY(${d}.target_block_ids))
            OR (${d}.target_type = 'apartments' AND m.id = ANY(${d}.target_apartment_ids))
          )
      )
      OR EXISTS (
        SELECT 1 FROM site_memberships sm
        WHERE sm.site_code = ${d}.site_code AND sm.user_code = ${user} AND sm.role = 'BOARD_MEMBER' AND sm.is_active = TRUE
      )
    )
  )`;
}

/**
 * Duyuru eki için kullanıcı-site ilişkisi (R16 P2-5): `documentVisibleToUserSql`'in HEDEF (blok / daire) koşulu OLMAYAN hâli. Çağıranın belgenin sitesinde hâlâ AKTİF bir
 * daire ilişkisi (`my_apts`) ya da aktif BOARD_MEMBER üyeliği olmalı: taşınan / pasifleştirilen sakin eski duyurunun eki üzerinden belgenin YENİ sürümünü indiremez
 * (A6 "taşınan anında kaybeder"); hedef daraltması ise ek erişimini etkilemez (A12). `my_apts` CTE'si gerekir.
 */
export function userInDocumentSiteSql(d = 'd', user = '$1') {
  return `(
    EXISTS (SELECT 1 FROM my_apts m WHERE m.site_code = ${d}.site_code)
    OR EXISTS (SELECT 1 FROM site_memberships sm WHERE sm.site_code = ${d}.site_code AND sm.user_code = ${user} AND sm.role = 'BOARD_MEMBER' AND sm.is_active = TRUE)
  )`;
}

/** `documents` modülü bu belgenin sitesinde AÇIK mı (katalog varsayılanı KAPALI: satır yoksa kapalı). */
export const MODULE_ENABLED_SQL = (d = 'd') =>
  `EXISTS (SELECT 1 FROM site_modules smod WHERE smod.site_code = ${d}.site_code AND smod.module_code = 'drive_storage' AND smod.enabled = TRUE)`;

const RESIDENT_FROM = `
  FROM documents d
  INNER JOIN sites s ON s.site_code = d.site_code AND s.approval_status = 'approved'
  INNER JOIN document_versions cv ON cv.document_id = d.id AND cv.version_no = d.current_version_no AND cv.status = 'ready'
`;

const RESIDENT_COLUMNS = `
  d.id, d.site_code, s.name AS site_name, d.title, d.category, d.description, d.updated_at,
  cv.display_name AS cv_display_name, cv.mime_type AS cv_mime_type, cv.size_bytes AS cv_size_bytes,
  cv.version_no AS cv_version_no, cv.completed_at AS cv_completed_at
`;

const residentWhere = (userParam = '$1') =>
  `d.status = 'active' AND d.audience = 'residents' AND ${MODULE_ENABLED_SQL('d')} AND ${documentVisibleToUserSql('d', userParam)}`;

/**
 * Hesabı olup `site_people` satırı henüz olmayan (yeni onaylanan) üye "belge yok" görmesin: ilgili sitelerde KISITLI eşitleme (try-lock, 5 sn
 * kısıtlama; hata okumayı engellemez).
 */
async function syncMissingPeople(userCode, db) {
  const missing = await db.query(
    `
      SELECT DISTINCT a.site_code
      FROM apartment_memberships am
      INNER JOIN apartments a ON a.id = am.apartment_id AND a.is_active = TRUE
      WHERE am.user_code = $1 AND am.is_active = TRUE
        AND NOT EXISTS (SELECT 1 FROM site_people sp WHERE sp.site_code = a.site_code AND sp.user_code = am.user_code)
      LIMIT 5
    `,
    [userCode],
  );
  for (const row of missing.rows ?? []) {
    await syncSitePeopleSafe(Number(row.site_code));
  }
}

/** GET /app/documents -> { items, next_before_id }. Sıra id DESC; imleç saf anahtar-kümesi (`id < before_id`). */
export async function listMyDocuments(authUser, query = {}, db = pool) {
  const filters = parseResidentQuery(query);
  const userCode = userCodeOf(authUser);
  if (userCode === null) {
    return { items: [], next_before_id: null };
  }
  await syncMissingPeople(userCode, db);
  const params = [userCode];
  const clauses = [residentWhere('$1')];
  if (filters.siteCode !== null) {
    params.push(filters.siteCode);
    clauses.push(`d.site_code = $${params.length}`);
  }
  if (filters.category) {
    params.push(filters.category);
    clauses.push(`d.category = $${params.length}`);
  }
  if (filters.beforeId !== null) {
    params.push(filters.beforeId);
    clauses.push(`d.id < $${params.length}`);
  }
  if (filters.q) {
    params.push(`%${escapeLike(foldText(filters.q))}%`);
    const term = `$${params.length}`;
    clauses.push(
      `(${foldSql('d.title')} LIKE ${term} ESCAPE '\\' OR ${foldSql('d.description')} LIKE ${term} ESCAPE '\\' OR ${foldSql('cv.display_name')} LIKE ${term} ESCAPE '\\')`,
    );
  }
  params.push(filters.limit + 1);
  const result = await db.query(
    `
      WITH ${myApartmentsCte('$1')}
      SELECT ${RESIDENT_COLUMNS}
      ${RESIDENT_FROM}
      WHERE ${clauses.join(' AND ')}
      ORDER BY d.id DESC
      LIMIT $${params.length}
    `,
    params,
  );
  const rows = result.rows ?? [];
  const hasMore = rows.length > filters.limit;
  const items = rows.slice(0, filters.limit).map((row) => mapResidentRow(row));
  return { items, next_before_id: hasMore && items.length > 0 ? items[items.length - 1].id : null };
}

/** GET /app/documents/:id (görünmeyen / yok / başka site / modül kapalı -> 404 DOCUMENT_NOT_FOUND). */
export async function getMyDocument(authUser, rawId, db = pool) {
  const id = parsePositiveId(rawId);
  const userCode = userCodeOf(authUser);
  if (id === null || userCode === null) {
    throw documentNotFound();
  }
  await syncMissingPeople(userCode, db);
  const result = await db.query(
    `
      WITH ${myApartmentsCte('$1')}
      SELECT ${RESIDENT_COLUMNS}
      ${RESIDENT_FROM}
      WHERE d.id = $2 AND ${residentWhere('$1')}
      LIMIT 1
    `,
    [userCode, id],
  );
  const row = result.rows?.[0];
  if (!row) {
    throw documentNotFound();
  }
  return mapResidentRow(row, { withDescription: true });
}

/** GET /app/documents/:id/download için güncel sürüm. Görünmeyen -> 404. */
export async function resolveResidentDownload(authUser, rawId, db = pool) {
  const id = parsePositiveId(rawId);
  const userCode = userCodeOf(authUser);
  if (id === null || userCode === null) {
    throw documentNotFound();
  }
  const result = await db.query(
    `
      WITH ${myApartmentsCte('$1')}
      SELECT d.id, cv.id AS version_id, cv.version_no, cv.storage_key, cv.size_bytes, cv.display_name, cv.mime_type
      ${RESIDENT_FROM}
      WHERE d.id = $2 AND ${residentWhere('$1')}
      LIMIT 1
    `,
    [userCode, id],
  );
  return downloadRow(result.rows?.[0]);
}

/**
 * GET /app/announcements/:id/attachments/:documentId/download — yetki ÇAĞIRANIN o duyurunun alıcısı olması (3a MINE_FROM ile aynı: `published`, onaylı site)
 * + belgenin o duyuruya ekli, `active`, kitlesi hâlâ `residents` ve `documents` AÇIK olmasıdır; belgenin kendi `target`ına (blok/daire) BAKILMAZ ama KİTLESİNE bakılır:
 * kitle yöneticilere/kurula çevrilen belge yayındaki duyuruda da ANINDA indirilemez (A7 "kitle değişikliği ANINDA geçerlidir"; yeni sürümü de sızmaz). Geri çekilen duyuruda 404.
 * R16 P2-5: ÇAĞIRANIN belgenin sitesinde hâlâ AKTİF ilişkisi de şarttır (`userInDocumentSiteSql`): taşınan / pasifleştirilen sakin eski duyurunun eki üzerinden artık indiremez.
 */
export async function resolveAnnouncementAttachmentDownload(authUser, rawAnnouncementId, rawDocumentId, db = pool) {
  const announcementId = parsePositiveId(rawAnnouncementId);
  const documentId = parsePositiveId(rawDocumentId);
  const userCode = userCodeOf(authUser);
  if (announcementId === null || documentId === null || userCode === null) {
    throw documentNotFound();
  }
  const result = await db.query(
    `
      WITH ${myApartmentsCte('$1')}
      SELECT d.id, cv.id AS version_id, cv.version_no, cv.storage_key, cv.size_bytes, cv.display_name, cv.mime_type
      FROM announcement_attachments aa
      INNER JOIN announcements a ON a.id = aa.announcement_id AND a.status = 'published'
      INNER JOIN sites s ON s.site_code = a.site_code AND s.approval_status = 'approved'
      INNER JOIN announcement_recipients r ON r.announcement_id = a.id
      INNER JOIN site_people sp ON sp.id = r.person_id AND sp.user_code = $1
      INNER JOIN documents d ON d.id = aa.document_id AND d.site_code = a.site_code AND d.status = 'active' AND d.audience = 'residents'
      INNER JOIN document_versions cv ON cv.document_id = d.id AND cv.version_no = d.current_version_no AND cv.status = 'ready'
      WHERE aa.announcement_id = $2 AND aa.document_id = $3 AND ${MODULE_ENABLED_SQL('d')} AND ${userInDocumentSiteSql('d', '$1')}
      LIMIT 1
    `,
    [userCode, announcementId, documentId],
  );
  return downloadRow(result.rows?.[0]);
}

function downloadRow(row) {
  if (!row) {
    throw documentNotFound();
  }
  return {
    documentId: Number(row.id),
    versionId: Number(row.version_id),
    versionNo: Number(row.version_no),
    storageKey: row.storage_key,
    sizeBytes: Number(row.size_bytes),
    displayName: row.display_name,
    mimeType: row.mime_type,
  };
}

/** Sakin indirmesi başladı: sayaç fire-and-forget artırılır (yaklaşık sayaç; aynı kişinin tekrarı da sayılır). */
export function bumpDownloadCount(documentId, db = pool) {
  try {
    void Promise.resolve(db.query(`UPDATE documents SET download_count = download_count + 1 WHERE id = $1`, [documentId])).catch(() => {});
  } catch (_error) {
    // sayaç hatası indirmeyi etkilemez
  }
}
