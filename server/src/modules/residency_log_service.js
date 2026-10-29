// Daire sakini ADLI KAYDI: OKUMA ve disa aktarim (site yoneticisi / super kullanici). Sozlesme: docs/PLATFORM_ADLI_KAYIT.md.
//
//  - Erisim: YALNIZ site yoneticisi ve super kullanici (rota resolvePeopleAccess write:true); kurul, gorevli, daire admini, malik, kiraci, aile ve YENI kiraci GOREMEZ.
//  - Liste: apartment_residency_log (sayfali). Kayit henuz yazilmamis eski donemler icin salt okunur TUREYEN satirlar (kaynak: eski kayit) ayri `legacy_items` olarak doner.
//  - Dokum: gerekce kodu + kisa not ZORUNLU; dokum alma audit_log'a yazilir ve audit yazilamazsa dokum VERILMEZ (fail-closed).
//  - Iletisim bilgisi (telefon, e-posta, TCKN) hicbir yanitta ve dokumde yoktur.

import { pool } from '../db.js';
import { actorFromAuthUser, recordAudit } from './audit_service.js';
import { PlatformError } from './errors.js';
import { apartmentLabel, dateToIso, parsePage, parsePositiveId, toIso } from './people_common.js';
import { renderCsv, renderPdf } from './residency_log_export.js';

export const EVENT_LABELS = Object.freeze({
  moved_in: 'Taşındı (giriş)',
  moved_out: 'Taşındı (çıkış)',
  role_changed: 'Rol değişti',
  admin_changed: 'Daire yöneticisi değişti',
  link_cut_mutual: 'Karşılıklı bağ kesme',
  member_removed: 'Üye çıkarıldı',
  member_left: 'Kendi isteğiyle ayrıldı',
  access_suspended: 'Kapı erişimi askıya alındı',
  access_lifted: 'Kapı erişimi yeniden açıldı',
  handover: 'Yönetim devri',
});

export const REASON_LABELS = Object.freeze({
  moved_out: 'Taşınma',
  handover: 'Devir',
  mutual: 'Karşılıklı onay',
  site_manager: 'Site yönetimi işlemi',
  apartment_admin: 'Daire yöneticisi işlemi',
  self: 'Kişinin kendi işlemi',
  consent: 'Üyenin onayıyla',
  suspension: 'Askıya alma kararı',
  account_deleted: 'Hesap silindi',
  bulk_import: 'Toplu yükleme',
  sync: 'Sistem eşitlemesi',
  manual_add: 'Elle kayıt',
  invite_accepted: 'Davet kabul edildi',
  role_change: 'Rol değişikliği',
  admin_change: 'Yönetici değişikliği',
  owner_record: 'Malik kaydı',
  owner_default: 'Malik varsayılanı',
  co_owner_add: 'Ek malik kaydı',
  account_holder_change: 'Hesap muhatabı değişti',
  legacy: 'Eski kayıt',
});

export const RELATION_LABELS = Object.freeze({ owner: 'Malik', tenant: 'Kiracı', family_member: 'Aile üyesi', resident: 'Sakin' });
export const ACTOR_ROLE_LABELS = Object.freeze({
  system: 'Sistem',
  super_user: 'Süper kullanıcı',
  site_manager: 'Site yöneticisi',
  apartment_admin: 'Daire yöneticisi',
  owner: 'Malik',
  tenant: 'Kiracı',
  resident: 'Sakin',
});

/** Dokum gerekce kodlari (resmi talep / kolluk / mahkeme / diger). */
export const EXPORT_REASONS = Object.freeze({
  official_request: 'Resmî talep',
  law_enforcement: 'Kolluk',
  court: 'Mahkeme',
  other: 'Diğer',
});

export const EXPORT_FORMATS = Object.freeze(['pdf', 'csv']);
export const EXPORT_ROW_LIMIT = 5000;
const LEGACY_LIST_LIMIT = 100;
const NOTE_MIN = 5;
const NOTE_MAX = 200;
const SOURCE_LABEL_LEGACY = 'Eski kayıt';
const SOURCE_LABEL_LOG = 'Adli kayıt';

/** Kayit tablosunda kapanisi temsil eden olaylar (eski donem turetmesinde "zaten kayitli" sayilir). */
const CLOSING_EVENTS = ['moved_out', 'member_removed', 'member_left', 'link_cut_mutual'];

const notFound = () => new PlatformError(404, 'APARTMENT_NOT_FOUND', 'Daire bulunamadı.');
const invalid = (code, message) => new PlatformError(400, code, message);

const numOrNull = (value) => (value === null || value === undefined ? null : Number(value));

function parseJson(value) {
  if (value && typeof value === 'object') return value;
  try {
    return JSON.parse(String(value));
  } catch (_error) {
    return {};
  }
}

/** Kayit satiri -> API ogesi (etiketlerle). */
export function mapLogRow(row) {
  const relation = row.subject_relation ?? null;
  const actorRole = row.actor_role ?? 'system';
  return {
    id: Number(row.id),
    source: 'log',
    source_label: SOURCE_LABEL_LOG,
    occurred_at: toIso(row.occurred_at),
    apartment_id: numOrNull(row.apartment_id),
    apartment_label: row.apartment_label ?? null,
    event_type: row.event_type,
    event_label: EVENT_LABELS[row.event_type] ?? row.event_type,
    reason_code: row.reason_code,
    reason_label: REASON_LABELS[row.reason_code] ?? row.reason_code,
    subject: {
      name: row.subject_name ?? null,
      relation,
      relation_label: relation ? RELATION_LABELS[relation] ?? null : null,
      person_id: numOrNull(row.subject_person_id),
      user_code: numOrNull(row.subject_user_code),
    },
    period: { start: dateToIso(row.period_start), end: dateToIso(row.period_end) },
    actor: {
      user_code: numOrNull(row.actor_user_code),
      name: row.actor_name ?? null,
      role: actorRole,
      role_label: ACTOR_ROLE_LABELS[actorRole] ?? actorRole,
    },
    related: parseJson(row.related),
  };
}

/** Eski ilişki kaydi (kayit tablosuna yazilmamis kapali donem) -> API ogesi; kaynak etiketi "Eski kayit". */
export function mapLegacyRow(row) {
  const relation = row.relation ?? null;
  const end = dateToIso(row.move_out_date);
  return {
    id: -Number(row.id),
    source: 'legacy',
    source_label: SOURCE_LABEL_LEGACY,
    occurred_at: end ? `${end}T00:00:00.000Z` : toIso(row.updated_at),
    apartment_id: numOrNull(row.apartment_id),
    apartment_label: apartmentLabel(row.block_name, row.unit_label) || null,
    event_type: 'moved_out',
    event_label: EVENT_LABELS.moved_out,
    reason_code: 'legacy',
    reason_label: REASON_LABELS.legacy,
    subject: {
      name: row.name ?? null,
      relation,
      relation_label: relation ? RELATION_LABELS[relation] ?? null : null,
      person_id: numOrNull(row.person_id),
      user_code: numOrNull(row.user_code),
    },
    period: { start: dateToIso(row.move_in_date), end },
    actor: { user_code: null, name: null, role: 'system', role_label: ACTOR_ROLE_LABELS.system },
    related: { residency_id: Number(row.id) },
  };
}

const LEGACY_SQL = `
  SELECT r.id, r.apartment_id, r.relation, r.move_in_date, r.move_out_date, r.updated_at, sp.id AS person_id, sp.user_code,
         COALESCE(NULLIF(u.full_name, ''), sp.full_name) AS name, a.unit_label, b.block_name
  FROM apartment_residencies r
  INNER JOIN site_people sp ON sp.id = r.person_id
  LEFT JOIN users u ON u.user_code = sp.user_code
  LEFT JOIN apartments a ON a.id = r.apartment_id
  LEFT JOIN site_blocks b ON b.id = a.block_id
  WHERE r.site_code = $1
    AND r.is_current = FALSE
    AND ($2::BIGINT IS NULL OR r.apartment_id = $2::BIGINT)
    AND ($4::DATE IS NULL OR COALESCE(r.move_out_date, r.updated_at::date) >= $4::DATE)
    AND ($5::DATE IS NULL OR COALESCE(r.move_out_date, r.updated_at::date) <= $5::DATE)
    AND NOT EXISTS (
      SELECT 1 FROM apartment_residency_log l
      WHERE l.site_code = r.site_code AND l.apartment_id = r.apartment_id
        AND l.related ->> 'residency_id' = r.id::text
        AND l.event_type = ANY($6::TEXT[])
    )
  ORDER BY COALESCE(r.move_out_date, r.updated_at::date) DESC, r.id DESC
  LIMIT $3
`;

async function apartmentOfSite(db, siteCode, apartmentId) {
  const result = await db.query(
    `SELECT a.id, a.unit_label, b.block_name
     FROM apartments a LEFT JOIN site_blocks b ON b.id = a.block_id
     WHERE a.id = $1 AND a.site_code = $2`,
    [apartmentId, siteCode],
  );
  return result.rows?.[0] ?? null;
}

/**
 * GET .../apartments/:id/residency-log: sayfali kayit (yeniden eskiye) + kayda yazilmamis eski donemler (yalniz ilk sayfada).
 * @returns {Promise<{ apartment_id: number, label: string, total: number, limit: number, offset: number, items: object[], legacy_items: object[] }>}
 */
export async function listApartmentResidencyLog({ siteCode, apartmentId, query = {}, db = pool }) {
  const aptId = parsePositiveId(apartmentId);
  if (aptId === null) throw notFound();
  const { limit, offset } = parsePage(query);
  const apartment = await apartmentOfSite(db, siteCode, aptId);
  const total = Number(
    (await db.query(`SELECT COUNT(*)::INTEGER AS total FROM apartment_residency_log WHERE site_code = $1 AND apartment_id = $2`, [siteCode, aptId])).rows?.[0]?.total ?? 0,
  );
  // Daire silinmis olabilir (kayit kalir); hem daire hem kayit yoksa 404.
  if (!apartment && total === 0) throw notFound();
  const page = await db.query(
    `SELECT * FROM apartment_residency_log WHERE site_code = $1 AND apartment_id = $2 ORDER BY id DESC LIMIT $3 OFFSET $4`,
    [siteCode, aptId, limit, offset],
  );
  const items = (page.rows ?? []).map(mapLogRow);
  let legacyItems = [];
  if (offset === 0) {
    const legacy = await db.query(LEGACY_SQL, [siteCode, aptId, LEGACY_LIST_LIMIT, null, null, CLOSING_EVENTS]);
    legacyItems = (legacy.rows ?? []).map(mapLegacyRow);
  }
  return {
    apartment_id: aptId,
    label: apartment ? apartmentLabel(apartment.block_name, apartment.unit_label) : items[0]?.apartment_label ?? '',
    total,
    limit,
    offset,
    items,
    legacy_items: legacyItems,
  };
}

// ---------------------------------------------------------------------------
// Adli bilgi dokumu
// ---------------------------------------------------------------------------

function parseIsoDate(value, field) {
  if (value === undefined || value === null || String(value).trim() === '') return null;
  const text = String(value).trim();
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(text);
  if (!match) throw invalid('INVALID_DATE', `${field} alanı YYYY-AA-GG biçiminde olmalıdır.`);
  const date = new Date(Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3])));
  if (Number.isNaN(date.getTime()) || date.toISOString().slice(0, 10) !== text) throw invalid('INVALID_DATE', `${field} geçerli bir tarih olmalıdır.`);
  return text;
}

/** Dokum istegi: gerekce kodu + kisa not zorunlu; bicim pdf | csv (varsayilan pdf); isteğe bagli daire ve tarih araligi. */
export function parseExportRequest(input = {}) {
  const format = input.format === undefined || input.format === null || input.format === '' ? 'pdf' : String(input.format).toLowerCase();
  if (!EXPORT_FORMATS.includes(format)) throw invalid('INVALID_FORMAT', 'Biçim pdf ya da csv olmalıdır.');
  const reasonCode = typeof input.reason_code === 'string' ? input.reason_code.trim() : '';
  if (!Object.hasOwn(EXPORT_REASONS, reasonCode)) {
    throw invalid('REASON_REQUIRED', 'Gerekçe seçin: resmî talep, kolluk, mahkeme ya da diğer.');
  }
  const note = typeof input.note === 'string' ? input.note.replace(/\p{C}+/gu, ' ').replace(/\s+/g, ' ').trim() : '';
  if (note.length < NOTE_MIN || note.length > NOTE_MAX) {
    throw invalid('REASON_NOTE_REQUIRED', `Gerekçe notu ${NOTE_MIN} ile ${NOTE_MAX} karakter arasında olmalıdır.`);
  }
  let apartmentId = null;
  if (input.apartment_id !== undefined && input.apartment_id !== null && String(input.apartment_id).trim() !== '') {
    apartmentId = parsePositiveId(input.apartment_id);
    if (apartmentId === null) throw invalid('INVALID_APARTMENT', 'apartment_id geçersiz.');
  }
  const from = parseIsoDate(input.from, 'from');
  const to = parseIsoDate(input.to, 'to');
  if (from && to && to < from) throw invalid('INVALID_DATE_RANGE', 'Bitiş tarihi başlangıçtan önce olamaz.');
  return { format, reasonCode, note, apartmentId, from, to };
}

const istanbulStamp = (value) => {
  const date = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(date.getTime())) return '';
  return new Intl.DateTimeFormat('sv-SE', { timeZone: 'Europe/Istanbul', dateStyle: 'short', timeStyle: 'short' }).format(date);
};

function rowOfItem(item) {
  const period = [item.period.start, item.period.end].filter(Boolean).join(' - ');
  const actor = item.source === 'legacy' ? '' : [item.actor.name, item.actor.role_label].filter(Boolean).join(' / ');
  return [
    item.occurred_at ? istanbulStamp(item.occurred_at) : '',
    item.event_label,
    item.apartment_label ?? '',
    item.subject.name ?? 'Adı kayıtlı değil',
    item.subject.relation_label ?? '',
    period,
    item.reason_label,
    actor,
    item.source_label,
  ];
}

const DOC_COLUMNS = ['Tarih', 'Olay', 'Daire', 'Kişi', 'İlişki', 'Dönem', 'Neden', 'İşlemi yapan', 'Kaynak'];

/**
 * GET|POST .../residency-log/export: adli bilgi dokumu. Sira: dogrulama -> kayitlari oku -> audit (ZORUNLU) -> dosya.
 * @returns {Promise<{ filename: string, contentType: string, body: Buffer, rowCount: number }>}
 */
export async function buildForensicExport({ siteCode, input, authUser, db = pool, now = new Date() }) {
  const request = parseExportRequest(input);
  const site = (await db.query(`SELECT name FROM sites WHERE site_code = $1`, [siteCode])).rows?.[0];
  if (!site) throw new PlatformError(404, 'SITE_NOT_FOUND', 'Site bulunamadı.');
  let apartmentLabelText = 'Tüm daireler';
  if (request.apartmentId !== null) {
    const apartment = await apartmentOfSite(db, siteCode, request.apartmentId);
    const any = apartment
      ? null
      : (await db.query(`SELECT apartment_label FROM apartment_residency_log WHERE site_code = $1 AND apartment_id = $2 LIMIT 1`, [siteCode, request.apartmentId])).rows?.[0];
    if (!apartment && !any) throw notFound();
    apartmentLabelText = apartment ? apartmentLabel(apartment.block_name, apartment.unit_label) : any.apartment_label ?? `Daire ${request.apartmentId}`;
  }
  const logRows = (
    await db.query(
      `SELECT * FROM apartment_residency_log
       WHERE site_code = $1
         AND ($2::BIGINT IS NULL OR apartment_id = $2::BIGINT)
         AND ($3::DATE IS NULL OR occurred_at >= $3::DATE)
         AND ($4::DATE IS NULL OR occurred_at < ($4::DATE + 1))
       ORDER BY occurred_at ASC, id ASC
       LIMIT $5`,
      [siteCode, request.apartmentId, request.from, request.to, EXPORT_ROW_LIMIT + 1],
    )
  ).rows ?? [];
  const items = logRows.slice(0, EXPORT_ROW_LIMIT).map(mapLogRow);
  let truncated = logRows.length > EXPORT_ROW_LIMIT;
  const room = EXPORT_ROW_LIMIT - items.length;
  if (room > 0) {
    const legacyRows = (await db.query(LEGACY_SQL, [siteCode, request.apartmentId, room + 1, request.from, request.to, CLOSING_EVENTS])).rows ?? [];
    if (legacyRows.length > room) truncated = true;
    items.push(...legacyRows.slice(0, room).map(mapLegacyRow));
  } else {
    truncated = true;
  }

  const actor = actorFromAuthUser(authUser);
  // ZORUNLU denetim: kim, ne zaman, hangi daire, hangi gerekce. Yazilamazsa dokum VERILMEZ.
  const audited = await recordAudit(db, {
    actor: authUser,
    action: 'residency_log.exported',
    siteCode,
    targetType: request.apartmentId === null ? 'site' : 'apartment',
    targetId: String(request.apartmentId ?? siteCode),
    details: {
      format: request.format,
      reason_code: request.reasonCode,
      note: request.note,
      apartment_id: request.apartmentId,
      from: request.from,
      to: request.to,
      row_count: items.length,
      truncated,
    },
  });
  if (!audited) {
    throw new PlatformError(503, 'AUDIT_UNAVAILABLE', 'Döküm denetim kaydına yazılamadığı için verilemedi. Biraz sonra tekrar deneyin.');
  }

  const range = request.from || request.to ? `${request.from ?? '...'} - ${request.to ?? '...'}` : 'Tümü';
  const requester = [actor.name, actor.userCode ? `kod ${actor.userCode}` : null].filter(Boolean).join(', ');
  const meta = [
    ['Belge', 'Adli bilgi dökümü (daire sakini kayıtları)'],
    ['Site', site.name ?? String(siteCode)],
    ['Daire', apartmentLabelText],
    ['Tarih aralığı', range],
    ['Oluşturulma', istanbulStamp(now)],
    ['Dökümü alan', requester || 'Bilinmiyor'],
    ['Gerekçe', `${EXPORT_REASONS[request.reasonCode]} - ${request.note}`],
    ['Kayıt sayısı', `${items.length}${truncated ? ` (üst sınır ${EXPORT_ROW_LIMIT}; kayıtlar kesildi, tarih aralığını daraltın)` : ''}`],
  ];
  const rows = items.map(rowOfItem);
  const stamp = istanbulStamp(now).slice(0, 10).replace(/-/g, '');
  const base = `adli-bilgi-dokumu-${siteCode}${request.apartmentId ? `-d${request.apartmentId}` : ''}-${stamp}`;
  const footer =
    'Bu döküm yalnız resmî talep halinde bilgi amaçlıdır; iletişim bilgisi (telefon, e-posta, kimlik numarası) içermez. Dökümü alma işlemi denetim kaydına yazılmıştır.';
  if (request.format === 'csv') {
    return { filename: `${base}.csv`, contentType: 'text/csv; charset=utf-8', body: renderCsv({ meta: [...meta, ['Not', footer]], columns: DOC_COLUMNS, rows }), rowCount: items.length };
  }
  return {
    filename: `${base}.pdf`,
    contentType: 'application/pdf',
    body: renderPdf({ title: 'Adli bilgi dökümü', meta, columns: DOC_COLUMNS, rows, footer }),
    rowCount: items.length,
  };
}
