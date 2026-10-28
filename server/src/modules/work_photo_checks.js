// İş Takibi fotoğraf yeniden kullanım uyarısı (P2-6): bir talepteki hazır fotoğrafın içerik özeti (sha256) AYNI sitedeki başka bir talepte de varsa yönetime uyarı verir.
//
// Sözleşme: docs/PLATFORM_IS_TAKIBI.md "Fotoğraf yeniden kullanım uyarısı (100)". YALNIZ UYARIDIR: yükleme, talep, durum geçişi hiçbir koşulda engellenmez; otomatik kabul / red yoktur.
// Dayanak YALNIZ sunucuda zaten tutulan veridir: sha256 (work_item_attachments, yükleme tamamlanırken sunucu hesaplar) + talebin konumu (ortak alan / daire / blok).
// Fotoğrafın içeriğinden daire etiketi OKUNMAZ (OCR yok) ve EXIF (çekim yeri / zamanı) KULLANILMAZ: istemci yüklemeden önce EXIF'i siler (gizlilik), sunucu görüntüyü çözmez.
// Kapsam: yalnız yönetim görünümü (yönetici / süper / görevli / kurul); SAKİNE hiçbir uyarı gitmez (başkasının talebinin varlığı sızmasın). Aynı site dışına BAKILMAZ.
// Görevli yalnız kendi kapsamındaki (kendine atanmış / atanmamış / yetim atamalı) taleplerin kimliğini ve konumunu görür; kapsam dışı eşleşme yalnız sayıya katılır.
// Sınır: bir taleple en çok 200 eşleşme satırı okunur, uyarı başına en çok 5 ilgili kayıt gösterilir. Aynı fotoğrafın yeniden kodlanmış hâli (kırpma, yeniden sıkıştırma) bulunmaz.

import { apartmentLabel, toIso } from './people_common.js';
import { staffScope } from './work_tracking_common.js';

export const PHOTO_WARNING_CODES = Object.freeze({
  reusedOtherLocation: 'photo_reused_other_location',
  reused: 'photo_reused',
  duplicateInItem: 'photo_duplicate_in_item',
});
export const PHOTO_WARNING_SEVERITY = Object.freeze({ warning: 'warning', info: 'info' });
export const PHOTO_MATCH_ROW_LIMIT = 200;
export const PHOTO_RELATED_LIMIT = 5;

/**
 * Talebin hazır fotoğrafları ile sitedeki BAŞKA hazır fotoğrafların sha256 eşleşmeleri. Parametreler: $1 talep, $2 site, [$3 görevli kullanıcı kodu], [son: fotoğraf].
 * Konum karşılaştırması: tür + daire + (talepteki blok YA DA dairenin bloğu) AYNI ise `same_location`. `visible`: görevli için kapsam, diğerleri için TRUE.
 */
export function photoMatchSql({ staff = false, single = false } = {}) {
  const visible = staff ? `(${staffScope('$3')})` : 'TRUE';
  const attachmentParam = staff ? '$4' : '$3';
  return `
    SELECT a.id AS attachment_id, o.id AS other_attachment_id, w.id AS other_item_id, w.created_at AS other_created_at,
           (w.id = cw.id) AS same_item,
           (cw.location_type = w.location_type
             AND cw.apartment_id IS NOT DISTINCT FROM w.apartment_id
             AND COALESCE(cw.block_id, cap.block_id) IS NOT DISTINCT FROM COALESCE(w.block_id, ap.block_id)) AS same_location,
           w.location_type AS other_location_type, bb.block_name AS other_block_name, ap.unit_label AS other_unit_label,
           ${visible} AS visible
    FROM work_items cw
    LEFT JOIN apartments cap ON cap.id = cw.apartment_id
    INNER JOIN work_item_attachments a ON a.work_item_id = cw.id AND a.site_code = cw.site_code AND a.status = 'ready' AND a.sha256 IS NOT NULL
    INNER JOIN work_item_attachments o ON o.site_code = a.site_code AND o.sha256 = a.sha256 AND o.status = 'ready' AND o.id <> a.id
    INNER JOIN work_items w ON w.id = o.work_item_id AND w.site_code = o.site_code
    LEFT JOIN apartments ap ON ap.id = w.apartment_id
    LEFT JOIN site_blocks bb ON bb.id = COALESCE(w.block_id, ap.block_id)
    WHERE cw.id = $1 AND cw.site_code = $2${single ? ` AND a.id = ${attachmentParam}` : ''}
    ORDER BY a.id, o.id
    LIMIT ${PHOTO_MATCH_ROW_LIMIT}
  `;
}

/** Eşleşen talebin konum özeti ("B Blok - Daire 5", "B Blok · Ortak alan", "Ortak alan"). */
export function relatedLocationLabel(row) {
  if (row.other_location_type === 'daire') {
    return apartmentLabel(row.other_block_name, row.other_unit_label) || 'Daire';
  }
  const block = String(row.other_block_name ?? '').trim();
  return block ? `${block} · Ortak alan` : 'Ortak alan';
}

const asBool = (value) => value === true || value === 't' || value === 'true';

/** Mesajdaki ilgili kayıt listesi: "#45 · B Blok - Daire 5, #41 · A Blok - Daire 2 ve 2 kayıt daha" (görünür kayıt yoksa boş). */
function describeRelated(shown, remaining, { withLocation }) {
  if (shown.length === 0) return '';
  const parts = shown.map((entry) => (withLocation ? `#${entry.work_item_id} · ${entry.location_label}` : `#${entry.work_item_id}`));
  return remaining > 0 ? `${parts.join(', ')} ve ${remaining} kayıt daha` : parts.join(', ');
}

/**
 * Eşleşme satırlarından (photoMatchSql) uyarılar. Fotoğraf başına: başka bir talepte yeniden kullanım (konum uyuşmuyorsa "photo_reused_other_location", uyuyorsa
 * "photo_reused") ve/veya aynı talepte yineleme ("photo_duplicate_in_item", yalnız SONRAKİ kopyada). Sıra fotoğraf kimliğine göredir.
 * @returns {Array<{ code: string, severity: string, attachment_id: number, message: string, related_count: number,
 *                   related: Array<{ work_item_id: number, location_label: string, same_location: boolean, created_at: string|null }> }>}
 */
export function buildPhotoWarnings(rows) {
  const byAttachment = new Map();
  for (const row of rows ?? []) {
    const id = Number(row.attachment_id);
    if (!byAttachment.has(id)) byAttachment.set(id, []);
    byAttachment.get(id).push(row);
  }
  const warnings = [];
  for (const [attachmentId, matches] of [...byAttachment.entries()].sort((a, b) => a[0] - b[0])) {
    // Aynı başka talep birden çok kopyayla eşleşebilir: talep başına tek giriş. Aynı talepteki kopya yalnız ESKİ kopyası olan (daha sonra eklenen) fotoğrafı işaretler.
    const others = new Map();
    let duplicatesInItem = 0;
    for (const row of matches) {
      if (asBool(row.same_item)) {
        if (Number(row.other_attachment_id) < attachmentId) duplicatesInItem += 1;
        continue;
      }
      const itemId = Number(row.other_item_id);
      if (!others.has(itemId)) others.set(itemId, row);
    }
    if (others.size > 0) {
      const entries = [...others.values()].map((row) => ({
        work_item_id: Number(row.other_item_id),
        location_label: relatedLocationLabel(row),
        same_location: asBool(row.same_location),
        created_at: toIso(row.other_created_at),
        visible: asBool(row.visible),
      }));
      const mismatch = entries.some((entry) => !entry.same_location);
      // Uyuşmazlık önce, sonra yeniden eskiye (kimlik büyükten küçüğe). Kapsam dışı kayıt (görevli) listede görünmez, yalnız sayıya katılır.
      const ordered = [...entries].sort((a, b) => Number(a.same_location) - Number(b.same_location) || b.work_item_id - a.work_item_id);
      const shown = ordered.filter((entry) => entry.visible).slice(0, PHOTO_RELATED_LIMIT);
      const list = describeRelated(shown, ordered.length - shown.length, { withLocation: mismatch });
      const where = list === '' ? '' : ` (${list})`;
      warnings.push({
        code: mismatch ? PHOTO_WARNING_CODES.reusedOtherLocation : PHOTO_WARNING_CODES.reused,
        severity: mismatch ? PHOTO_WARNING_SEVERITY.warning : PHOTO_WARNING_SEVERITY.info,
        attachment_id: attachmentId,
        message: mismatch
          ? `Bu fotoğraf farklı bir konuma ait başka bir kayıtta da kullanılmış${where}. Konum etiketiyle uyuşmuyor olabilir; fotoğrafı kontrol edin.`
          : `Bu fotoğraf aynı konumdaki başka bir kayıtta da kullanılmış${where}. Aynı sorunun tekrarı olabilir.`,
        related_count: ordered.length,
        related: shown.map((entry) => ({
          work_item_id: entry.work_item_id,
          location_label: entry.location_label,
          same_location: entry.same_location,
          created_at: entry.created_at,
        })),
      });
    }
    if (duplicatesInItem > 0) {
      warnings.push({
        code: PHOTO_WARNING_CODES.duplicateInItem,
        severity: PHOTO_WARNING_SEVERITY.info,
        attachment_id: attachmentId,
        message: 'Aynı fotoğraf bu kayıtta birden fazla kez eklenmiş.',
        related_count: 0,
        related: [],
      });
    }
  }
  return warnings;
}

/**
 * Talebin (ya da tek fotoğrafın) uyarıları. `scope`: { kind: 'super' | 'manager' | 'staff' | 'board', userCode }. Sakin kapsamında HİÇ çağrılmaz (çağıran sorumlu).
 * @param {{ query: Function }} db @param {{ siteCode: number, itemId: number, attachmentId?: number|null, scope: { kind: string, userCode: number|null } }} args
 */
export async function loadPhotoWarnings(db, { siteCode, itemId, attachmentId = null, scope }) {
  const staff = scope?.kind === 'staff';
  const params = [itemId, siteCode];
  if (staff) params.push(scope.userCode);
  if (attachmentId !== null) params.push(attachmentId);
  const result = await db.query(photoMatchSql({ staff, single: attachmentId !== null }), params);
  return buildPhotoWarnings(result.rows ?? []);
}

/**
 * loadPhotoWarnings + güvenlik ağı: uyarı İKİNCİL bir bilgidir, hesaplanamazsa talep ayrıntısı / yükleme yanıtı BOZULMAZ (boş liste; günlüğe yalnız hata kodu yazılır).
 * `hasReady: false` (talepte hazır fotoğraf yok) sorguyu hiç göndermez.
 */
export async function loadPhotoWarningsSafe(db, { hasReady = true, ...args }) {
  if (!hasReady) return [];
  try {
    return await loadPhotoWarnings(db, args);
  } catch (error) {
    // eslint-disable-next-line no-console
    console.error('[work_tracking] fotograf yeniden kullanim uyarisi hesaplanamadi (uyari atlandi):', error?.code || error?.name || 'error');
    return [];
  }
}
