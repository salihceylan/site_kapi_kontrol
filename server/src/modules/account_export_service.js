// Kişisel veri dışa aktarma (KVKK / GDPR erişim hakkı): POST /me/data-export.
//
// Sözleşme: docs/PLATFORM_SATISA_HAZIRLIK.md §1.5. Kapsam YALNIZ çağıranın KENDİ verisidir (kendi verdiği ve kendi adına üretilen): her sorgu çağıranın
// user_code'una bağlanır; başka kullanıcıların kişisel verisi (aynı dairedeki diğer sakinler), parola özeti, belirteçler / erişim kodları, cihaz sırları ve
// yönetici iç notları ASLA seçilmez (sütun listeleri AÇIKTIR; `SELECT *` yalnız başkasının sütun eklemesine açık olmayan user_consents için ve sonra beyaz listeyle).
// Finans: "Borcum" (finance_read_service.getMyFinance) görünürlük kuralları AYNEN yeniden kullanılır; yetki mantığı kopyalanmaz.
//
// TUTARLILIK: tüm okumalar tek REPEATABLE READ / READ ONLY işlemdedir (eşzamanlı bir değişiklik dosyada yarım görünmez); kilit almaz, kilit beklemez.
// BOYUT: bölüm başına satır üst sınırı + toplam gövde üst sınırı (EXPORT_MAX_BYTES); aşılırsa en büyük bölümler en yeni kayıtlarla kısaltılır,
// `truncated: true` + `truncated_sections` yazılır (sessiz kayıp yok).
// HIZ SINIRI: kullanıcı başına 24 saatte 3 (account_data_exports tablosu, kullanıcı başına advisory kilit altında sayılır; paralel istekler sınırı aşamaz).
// Üretim başarısız olursa hak iade edilir. GİZLİLİK: dosya içeriği ve kişisel veri log'a yazılmaz.

import { pool } from '../db.js';
import {
  EXPORT_MAX_BYTES,
  EXPORT_RATE_LIMIT,
  EXPORT_RATE_WINDOW_HOURS,
  EXPORT_ROW_LIMITS,
  accountDeleted,
  exportFileName,
  exportRateLimited,
  exportTooLarge,
  numOrNull,
  plainObject,
  userCodeOf,
} from './account_common.js';
import { maskCardUid } from './card_access_common.js';
import { verifyCurrentPassword } from './account_password_guard.js';
import { recordAudit } from './audit_service.js';
import { getMyFinance } from './finance_read_service.js';
import { listMyReceipts } from './finance_receipts.js';
import { syncUserPeopleSafe } from './people_sync.js';
import { formatHhmm } from './push_common.js';
import { PUSH_EXPORT_EXCLUDED_NOTE, exportPushDevices } from './push_devices.js';

export const EXPORT_FORMAT_VERSION = 1;

export const EXPORT_NOTICE =
  'Bu dosya, hesabınıza ait kişisel verilerin makine tarafından okunabilir bir kopyasıdır. Yalnızca sizin verdiğiniz ve sizin adınıza üretilen veriler yer alır; ' +
  'başkalarının kişisel verileri, güvenlik sırları ve yönetici iç notları dışarıda bırakılmıştır (bkz. "excluded").';

/** Dışarıda bırakılanlar ve nedenleri (kullanıcıya gösterilir; şemadan türetilmiş, uydurma değil). */
export const EXPORT_EXCLUDED = Object.freeze([
  'Parola özeti, oturum ve parola sıfırlama belirteçleri, e-posta doğrulama kodu özetleri: güvenlik nedeniyle dışarıda bırakılmıştır.',
  'Aynı dairede veya sitede yaşayan diğer kişilerin kişisel bilgileri (ad, telefon, e-posta, araç): başkalarına ait olduğu için dışarıda bırakılmıştır.',
  'Site yönetiminin kişi kaydınıza, aracınıza, katılım talebinize, kapı iznine ve başvurunuza yazdığı iç notlar, karar ve ret gerekçeleri: yönetim kaydı olduğu için dışarıda bırakılmıştır.',
  'Misafir geçişi erişim kodları ve karekod belirteçleri: güvenlik nedeniyle dışarıda bırakılmıştır (yalnız geçişin kendisi ve oluşturma bilgileri yer alır). Misafir geçişiyle kapıyı açan kişinin IP adresi, o kişiye ait olduğu için kapı olaylarında boş bırakılmıştır.',
  'Cihazların bağlantı sırları (MQTT parolası, yerel kontrol anahtarı) ve envanter notları: güvenlik nedeniyle dışarıda bırakılmıştır.',
  'Yönetici olarak yaptığınız işlemlerin içeriği (duyuru, belge, finans kayıtları, tanımlar) ve sistem denetim günlükleri: site yönetiminin / platformun kaydı olduğu için dışarıda bırakılmıştır.',
  'Finans ekstresi "Borcum" ekranındaki görünümle aynıdır: her daire için son 30 hareket; yönetici açıklamaları ve işlemi yapan kişinin adı çıkarılmıştır. Tam defter site yönetiminin kaydıdır.',
  'Yüklediğiniz belgelerin dosya içerikleri, depolama anahtarları, içerik özetleri (hash), kitle / hedef bilgisi ve sürüm notları: site yönetiminin kaydı ve güvenlik nedeniyle dışarıda bırakılmıştır; yalnız sizin verdiğiniz kayıt bilgisi (dosya adı, tür, boyut, yükleme tarihi, sürüm no, kategori) "uploaded_documents" bölümünde yer alır. Belgenin başlığı ve durumu dosyaya konmaz: bunları site yöneticileri sonradan değiştirebilir ve başkasının yazdığı bilgi içerebilir.',
  'Makbuzlar ve tahsilat belgeleri: yalnız sizin görebildiğiniz dairelerin makbuz özeti (numara, tür, durum, tutar, tarih, daire) "receipts" bölümündedir; makbuzu düzenleyen yönetici adı, ödeyen kişinin adı (başkasına ait olabilir), doğrulama kodu ve belge anlık görüntüsü site yönetiminin resmi kaydı olduğu için dışarıda bırakılmıştır (makbuz belgeniz uygulamadaki makbuz ekranından alınır).',
  'Aidat hatırlatma e-postaları: yalnız size gönderilen hatırlatmaların geçmişi (tarih, ton, durum) "finance_reminders_received" bölümündedir; e-postanın metni, tutarlar, yönetici notu ve gönderim adresinin özeti yönetim / güvenlik kaydı olduğu için dışarıda bırakılmıştır.',
  PUSH_EXPORT_EXCLUDED_NOTE,
  'Rezervasyon ve konsiyerj: yalnız SİZİN yaptığınız rezervasyonların (alan adı, zaman, durum, notunuz) "reservations_made" bölümünde ve açtığınız konsiyerj taleplerinin (kategori, notunuz, istenen zaman, durum) "concierge_requests_made" bölümünde yer alır; yönetimin gerekçe ve kısa notları ile başkalarının rezervasyonları site yönetiminin kaydı olduğu için dışarıda bırakılmıştır.',
  'İş takibi talepleri: yalnız sizin açtığınız taleplerin başlığı, açıklaması, kategorisi, konumu, durumu ve tarihleri "work_items_created" bölümünde, yalnız SİZİN yazdığınız yorumlar "work_item_comments" bölümündedir; başkalarının yorumları, yönetimin diğer iç notları, öncelik, atanan görevli, hedef tarih ve durum geçmişi satırları site yönetiminin kaydı olduğu için dışarıda bırakılmıştır.',
  'Anket ve oylama: yalnız SİZİN kullandığınız oylar (anket başlığı, seçtiğiniz seçenek metni, oy zamanı) "survey_votes_cast" bölümündedir; başkalarının oyları, sonuç sayımları ve anketin hedef kitlesi site yönetiminin kaydı olduğu için dışarıda bırakılmıştır.',
  'Kartlı geçiş kartları: size tanımlı kartların etiketi, durumu ve numarasının yalnız son 4 karakteri "access_cards" bölümündedir; kart numarasının tamamı, kartı tanımlayan yönetici ve geçiş kayıtları site yönetiminin / güvenliğin kaydı olduğu için dışarıda bırakılmıştır.',
]);

// ---------------------------------------------------------------------------------------------------------------
// Hız sınırı (kullanıcı başına 24 saatte 3)
// ---------------------------------------------------------------------------------------------------------------

/** Kullanıcı satırını işlem sonuna dek KEY SHARE ile kilitler; silinmiş / olmayan hesapta 401 ACCOUNT_DELETED. */
async function lockLiveExportUser(client, userCode) {
  const user = await client.query('SELECT user_code FROM users WHERE user_code = $1 AND deleted_at IS NULL FOR KEY SHARE', [userCode]);
  if (!user.rows?.[0]) {
    throw accountDeleted();
  }
}

/**
 * Dışa aktarma denetimi (`account.data_exported`): KİM + ne zaman + boyut. Yazım, canlı kullanıcı kilidi (KEY SHARE) altında AYNI işlemde yapılır: hesap silme
 * dosya hazırlanırken commit ettiyse 401 ACCOUNT_DELETED (dosya DÖNMEZ, hak iade edilir) ve silinmiş hesap adına denetim satırı YAZILMAZ. Denetim satırının kendisi
 * başarısız olursa dışa aktarma bozulmaz (recordAudit hatayı yutar; SAVEPOINT).
 */
export async function recordExportAudit(userCode, details, db = pool) {
  const client = await db.connect();
  let began = false;
  try {
    await client.query('BEGIN');
    began = true;
    await lockLiveExportUser(client, userCode);
    await recordAudit(client, { actor: { userCode }, action: 'account.data_exported', targetType: 'user', targetId: String(userCode), details }, { inTransaction: true });
    await client.query('COMMIT');
    began = false;
  } finally {
    if (began) {
      try {
        await client.query('ROLLBACK');
      } catch (_rollbackError) {
        // bağlantı zaten kopmuş olabilir; asıl hata yukarıda fırlatılır
      }
    }
    client.release();
  }
}

/**
 * Bir dışa aktarma hakkı alır; sınır aşılmışsa 429 EXPORT_RATE_LIMITED. Sayım ve ekleme aynı kilit altında yapılır.
 * @returns {Promise<number>} hak kaydının kimliği (üretim başarısız olursa iade için)
 */
export async function acquireExportSlot(userCode, db = pool) {
  const client = await db.connect();
  let began = false;
  try {
    await client.query('BEGIN');
    began = true;
    await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', [`account_export:${userCode}`]);
    // CANLI KULLANICI KİLİDİ: `deleted_at IS NULL ... FOR KEY SHARE` (lockLiveUser kalıbı). Eskiden kilitsiz `SELECT deleted_at` + INSERT'in FK beklemesi, silmenin COMMIT'iyle
    // yarışınca SİLİNMİŞ hesaba hak satırı yazılıyordu (7 günlük temizlik de o satırı silmiyordu). Şimdi: devam eden silme varsa bu sorgu COMMIT'ini bekler ve satır
    // dönmez (401 ACCOUNT_DELETED); silme sonra gelirse `UPDATE users` bu işlem bitene dek bekler ve hak satırını (adım 16) kendisi siler.
    await lockLiveExportUser(client, userCode);
    await client.query(`DELETE FROM account_data_exports WHERE user_code = $1 AND requested_at < NOW() - INTERVAL '7 days'`, [userCode]);
    const usage = await client.query(
      `
        SELECT COUNT(*)::INTEGER AS used,
               GREATEST(1, CEIL(EXTRACT(EPOCH FROM (MIN(requested_at) + make_interval(hours => $2::INTEGER) - NOW()))))::INTEGER AS retry_after
        FROM account_data_exports
        WHERE user_code = $1 AND requested_at > NOW() - make_interval(hours => $2::INTEGER)
      `,
      [userCode, EXPORT_RATE_WINDOW_HOURS],
    );
    if (Number(usage.rows?.[0]?.used ?? 0) >= EXPORT_RATE_LIMIT) {
      throw exportRateLimited(usage.rows[0].retry_after);
    }
    const inserted = await client.query('INSERT INTO account_data_exports (user_code) VALUES ($1) RETURNING id', [userCode]);
    await client.query('COMMIT');
    began = false;
    return Number(inserted.rows[0].id);
  } finally {
    if (began) {
      try {
        await client.query('ROLLBACK');
      } catch (_rollbackError) {
        // bağlantı zaten kopmuş olabilir; asıl hata yukarıda fırlatılır
      }
    }
    client.release();
  }
}

/** Üretim başarısız olduysa hakkı iade eder (best-effort). */
export async function releaseExportSlot(slotId, db = pool) {
  try {
    await db.query('DELETE FROM account_data_exports WHERE id = $1', [slotId]);
  } catch (error) {
    // eslint-disable-next-line no-console
    console.error('[account] disa aktarma hakki iade edilemedi:', error?.code || error?.name || 'error');
  }
}

// ---------------------------------------------------------------------------------------------------------------
// Veri toplama
// ---------------------------------------------------------------------------------------------------------------

/** `limit + 1` satır ister; fazlası varsa kısaltılmış sayılır. */
async function limitedRows(client, sql, params, limit) {
  const result = await client.query(`${sql} LIMIT ${Number(limit) + 1}`, params);
  const rows = result.rows ?? [];
  return { rows: rows.slice(0, limit), more: rows.length > limit };
}

const SQL = Object.freeze({
  user: `
    SELECT user_code, full_name, email, login_name, phone_number, role, is_active, email_verified, approval_status, created_at, updated_at
    FROM users WHERE user_code = $1 LIMIT 1
  `,
  siteMemberships: `
    SELECT 'site_membership' AS source, sm.site_code, s.name AS site_name, sm.role, sm.is_active, sm.created_at, sm.updated_at
    FROM site_memberships sm INNER JOIN sites s ON s.site_code = sm.site_code
    WHERE sm.user_code = $1
    UNION ALL
    SELECT 'site_manager', ms.site_code, s.name, 'SITE_MANAGER', TRUE, ms.created_at, NULL::TIMESTAMPTZ
    FROM site_manager_sites ms INNER JOIN sites s ON s.site_code = ms.site_code
    WHERE ms.manager_user_code = $1
    ORDER BY site_code, source
  `,
  apartmentMemberships: `
    SELECT 'membership' AS source, am.id, am.apartment_id, a.site_code, s.name AS site_name, b.block_name, a.unit_label, am.role, am.is_active, am.created_at, am.updated_at
    FROM apartment_memberships am
    INNER JOIN apartments a ON a.id = am.apartment_id
    INNER JOIN sites s ON s.site_code = a.site_code
    LEFT JOIN site_blocks b ON b.id = a.block_id
    WHERE am.user_code = $1
    UNION ALL
    SELECT 'resident_indicator', NULL::BIGINT, a.id, a.site_code, s.name, b.block_name, a.unit_label, NULL::TEXT, a.is_active, NULL::TIMESTAMPTZ, NULL::TIMESTAMPTZ
    FROM apartments a
    INNER JOIN sites s ON s.site_code = a.site_code
    LEFT JOIN site_blocks b ON b.id = a.block_id
    WHERE a.resident_user_code = $1
    ORDER BY site_code, apartment_id, source
  `,
  people: `
    SELECT sp.id, sp.site_code, s.name AS site_name, sp.full_name, sp.phone, sp.email, sp.is_active, sp.created_at, sp.updated_at
    FROM site_people sp INNER JOIN sites s ON s.site_code = sp.site_code
    WHERE sp.user_code = $1 ORDER BY sp.id DESC
  `,
  residencies: `
    SELECT r.id, r.person_id, r.apartment_id, a.site_code, b.block_name, a.unit_label, r.relation, r.is_current,
           to_char(r.move_in_date, 'YYYY-MM-DD') AS move_in_date, to_char(r.move_out_date, 'YYYY-MM-DD') AS move_out_date, r.created_at
    FROM apartment_residencies r
    INNER JOIN site_people sp ON sp.id = r.person_id AND sp.user_code = $1
    INNER JOIN apartments a ON a.id = r.apartment_id
    LEFT JOIN site_blocks b ON b.id = a.block_id
    ORDER BY r.id
  `,
  vehicles: `
    SELECT v.id, v.site_code, v.person_id, v.plate_display, v.plate, v.is_active, v.created_at
    FROM vehicles v INNER JOIN site_people sp ON sp.id = v.person_id AND sp.user_code = $1
    ORDER BY v.id DESC
  `,
  // Tercihlerin TAMAMI (duyuru + aidat hatırlatma e-postası + telefon bildirimi + başlık gösterme + sessiz saatler). Eklenen sütunlar sonraki migration'lardandır
  // (040: email_finance_reminders, 041: push_*); sütunlar yoksa notificationPreferencesBase kullanılır (OPTIONAL_OBJECTS_SQL bayrağı).
  notificationPreferences: `
    SELECT email_announcements, email_finance_reminders, push_announcements, push_show_preview, push_quiet_enabled, push_quiet_start, push_quiet_end, updated_at
    FROM notification_preferences WHERE user_code = $1 LIMIT 1
  `,
  notificationPreferencesBase: `
    SELECT email_announcements, push_announcements, updated_at FROM notification_preferences WHERE user_code = $1 LIMIT 1
  `,
  // Yüklediğiniz belgelerin KAYIT bilgisi (Faz 3b-A): YALNIZ sizin verdiğiniz / ürettiğiniz alanlar — sürümün dosya adı, türü, boyutu, yükleme tarihi, sürüm no ve kategori.
  // Belgenin BAŞLIĞI (documents.title), durumu ve silinme zamanı SEÇİLMEZ: bunları başka yöneticiler sonradan değiştirebilir (örn. başkasının yazdığı bir başlık, yönetici olmayan
  // kullanıcının dosyasına sızardı; R16 P2-6). Dosya içeriği, depolama anahtarı, içerik özeti (hash), kitle / hedef ve sürüm notu da seçilmez.
  uploadedDocuments: `
    SELECT d.id AS document_id, v.version_no, d.site_code, s.name AS site_name, d.category,
           v.display_name AS file_name, v.mime_type, v.size_bytes, v.status AS version_status, v.created_at AS recorded_at, v.completed_at
    FROM document_versions v
    INNER JOIN documents d ON d.id = v.document_id
    INNER JOIN sites s ON s.site_code = d.site_code
    WHERE v.uploaded_by = $1
    ORDER BY v.id DESC
  `,
  // Size gönderilen aidat hatırlatmalarının GEÇMİŞİ (Faz 4b): hesabınıza bağlı kişi kaydına eklenen kalemler. Gönderilen e-posta adresi / özeti, yönetici notu, tutar
  // ve daire kimlikleri seçilmez (adres zaten user.email; not ve tutar e-postanın içeriğidir ve yönetim kaydıdır).
  financeReminders: `
    SELECT r.id AS run_id, r.site_code, s.name AS site_name, r.run_on, r.tone, i.with_amount, i.email_status, i.sent_at, cardinality(i.apartment_ids) AS apartment_count
    FROM finance_reminder_items i
    INNER JOIN site_people sp ON sp.id = i.person_id AND sp.user_code = $1
    INNER JOIN finance_reminder_runs r ON r.id = i.run_id
    INNER JOIN sites s ON s.site_code = r.site_code
    ORDER BY r.id DESC
  `,
  // Açtığınız iş takibi talepleri (042): YALNIZ sizin yazdığınız alanlar + durum / tarihler. Öncelik, atanan, hedef tarih, olaylar / yorumlar (iç notlar dahil) SEÇİLMEZ.
  workItems: `
    SELECT w.id, w.site_code, s.name AS site_name, w.category, w.location_type, w.title, w.description, w.status, w.created_at, w.updated_at, w.closed_at
    FROM work_items w
    INNER JOIN sites s ON s.site_code = w.site_code
    WHERE w.created_by = $1
    ORDER BY w.id DESC
  `,
  // Yazdığınız iş takibi yorumları (042): YALNIZ sizin (actor_user_code = çağıran) yazdığınız yorum metni + görünürlük + zaman. Talebin başlığı / başkasının metni SEÇİLMEZ.
  workItemComments: `
    SELECT e.id, e.work_item_id, e.site_code, e.created_at, e.body, e.visibility
    FROM work_item_events e
    WHERE e.actor_user_code = $1 AND e.event_type = 'comment'
    ORDER BY e.id DESC
  `,
  // Kartlı geçiş kartlarınız (046): kendi kişi kaydınız (site_people.user_code = çağıran) üzerinden; etiket, durum ve UID (çıktıda maskelenir). Tanımlayan yönetici SEÇİLMEZ.
  accessCards: `
    SELECT c.id, c.label, c.card_uid, c.is_active
    FROM access_cards c
    INNER JOIN site_people sp ON sp.id = c.person_id AND sp.user_code = $1
    ORDER BY c.id DESC
  `,
  // Rezervasyonlarım (043): YALNIZ sizin yaptığınız kayıtlar; alan adı, zaman, durum ve kendi notunuz. Yönetim gerekçesi / kararı veren / daire SEÇİLMEZ.
  reservationsMade: `
    SELECT r.id, r.site_code, s.name AS site_name, a.name AS area_name, r.starts_at, r.ends_at, r.slot_count, r.status, r.note, r.cancelled_by_kind AS cancelled_by, r.cancelled_at, r.created_at
    FROM reservations r
    INNER JOIN reservation_areas a ON a.id = r.area_id
    INNER JOIN sites s ON s.site_code = r.site_code
    WHERE r.user_code = $1
    ORDER BY r.id DESC
  `,
  // Konsiyerj taleplerim (043): YALNIZ sizin açtığınız talepler (kategori, notunuz, istenen zaman, durum). Yönetimin kısa notu / daire SEÇİLMEZ.
  conciergeRequestsMade: `
    SELECT c.id, c.site_code, s.name AS site_name, c.category, c.note, c.requested_for, c.status, c.created_at, c.closed_at
    FROM concierge_requests c
    INNER JOIN sites s ON s.site_code = c.site_code
    WHERE c.user_code = $1
    ORDER BY c.id DESC
  `,
  // Kullandığınız anket oyları (044): YALNIZ sizin oylarınız; anket başlığı, seçtiğiniz seçenek metni, zaman. Başkalarının oyu / sayım / hedef kitle SEÇİLMEZ.
  surveyVotesCast: `
    SELECT s.title AS survey_title, (s.options ->> v.option_index::INTEGER) AS option_text, v.voted_at
    FROM survey_votes v
    INNER JOIN surveys s ON s.id = v.survey_id
    WHERE v.user_code = $1
    ORDER BY v.id DESC
  `,
  announcements: `
    SELECT a.id, a.site_code, s.name AS site_name, a.title, a.body, a.importance, a.published_at, r.read_at
    FROM site_people sp
    INNER JOIN announcement_recipients r ON r.person_id = sp.id
    INNER JOIN announcements a ON a.id = r.announcement_id AND a.status = 'published'
    INNER JOIN sites s ON s.site_code = a.site_code AND s.approval_status = 'approved'
    WHERE sp.user_code = $1
    ORDER BY a.published_at DESC, a.id DESC
  `,
  siteApplications: `
    SELECT id, status, site_name, city, district, address, management_type, blocks, doors, block_count, apartment_count, door_count,
           device_uid, note, plan_code, site_code, created_at, decided_at
    FROM site_applications WHERE applicant_user_code = $1 ORDER BY id DESC
  `,
  guestPasses: `
    SELECT g.id, g.site_code, d.door_name, g.title, g.pass_type, g.expires_at, g.max_uses, g.used_count, g.is_active, g.created_at
    FROM guest_passes g LEFT JOIN site_doors d ON d.id = g.door_id
    WHERE g.created_by_user_code = $1 ORDER BY g.id DESC
  `,
  // ip_address: misafir geçişiyle açılan kapıda kayıt, KAPIYI AÇAN MİSAFİRİN adresidir (üçüncü kişinin kişisel verisi) -> dosyada boş bırakılır (R6). Kendi karekod / uygulama açılışlarının IP'si kullanıcıya aittir.
  doorEvents: `
    SELECT id, opened_at, site_code, door_name, trigger_type, apartment_label, user_name, user_role,
           CASE WHEN trigger_type = 'guest_pass' THEN NULL ELSE ip_address END AS ip_address
    FROM door_access_logs WHERE user_code = $1 ORDER BY opened_at DESC, id DESC
  `,
  joinRequests: `
    SELECT jr.id, jr.site_code, s.name AS site_name, b.block_name, a.unit_label, jr.status, jr.notes, jr.created_at, jr.reviewed_at
    FROM join_requests jr
    INNER JOIN sites s ON s.site_code = jr.site_code
    INNER JOIN apartments a ON a.id = jr.apartment_id
    LEFT JOIN site_blocks b ON b.id = jr.block_id
    WHERE jr.user_code = $1 ORDER BY jr.id DESC
  `,
  doorPermissions: `
    SELECT dao.id, dao.site_code, d.door_name, dao.is_allowed, dao.created_at, dao.updated_at
    FROM door_access_overrides dao INNER JOIN site_doors d ON d.id = dao.door_id
    WHERE dao.user_code = $1 ORDER BY dao.id
  `,
  qrRequests: `
    SELECT q.id, q.site_code, d.door_name, q.created_at, q.expires_at, q.revoked_at, q.request_latitude, q.request_longitude, q.request_accuracy, q.is_mocked
    FROM qr_access_tokens q LEFT JOIN site_doors d ON d.id = q.door_id
    WHERE q.user_code = $1 ORDER BY q.id DESC
  `,
  devices: `
    SELECT d.id, d.device_uid, d.gate_name, d.hardware_type, d.site_code, d.claimed_at, d.created_at
    FROM devices d
    WHERE d.assigned_user_code = $1 OR d.owner_user_id = (SELECT id FROM users WHERE user_code = $1)
    ORDER BY d.id DESC
  `,
});

/**
 * Sonradan eklenen migration'ların nesneleri (kullanıcı koduna BAĞLI DEĞİL; katalog bakışı): yoksa ilgili bölüm boş / eski şekil. 040: aidat hatırlatma + makbuz,
 * 039: belgeler, 041: bildirim tercihi push_* sütunları. Tek sorgu, aynı salt okunur işlemde, kilit almaz.
 */
const OPTIONAL_OBJECTS_SQL = `
  SELECT
    (SELECT COUNT(*) FROM information_schema.columns
       WHERE table_schema = 'public' AND table_name = 'notification_preferences'
         AND column_name IN ('email_finance_reminders', 'push_show_preview', 'push_quiet_enabled', 'push_quiet_start', 'push_quiet_end')) = 5 AS has_preference_extras,
    (to_regclass('public.documents') IS NOT NULL AND to_regclass('public.document_versions') IS NOT NULL) AS has_documents,
    (to_regclass('public.finance_reminder_items') IS NOT NULL AND to_regclass('public.finance_reminder_runs') IS NOT NULL) AS has_reminders,
    (to_regclass('public.receipts') IS NOT NULL) AS has_receipts,
    (to_regclass('public.work_items') IS NOT NULL) AS has_work_items,
    (to_regclass('public.reservations') IS NOT NULL) AS has_reservations,
    (to_regclass('public.survey_votes') IS NOT NULL) AS has_surveys
`;

const CONSENT_KEYS = ['id', 'document_id', 'version', 'accepted_at', 'source'];

/** Test / QA için değiştirilebilir bağımlılık: makbuz listesi (sakin ucunun işlevi; yetki mantığı kopyalanmaz). */
export const collectHooks = {
  listReceipts: (userCode, client) => listMyReceipts({ user_code: userCode }, { limit: EXPORT_ROW_LIMITS.receipts }, client),
};

/** Makbuz özeti -> dosya şekli: numara, tür, durum, tarihler, tutar (kuruş), daire. Ödeyen adı / yönetici adı / doğrulama kodu / anlık görüntü YOK. */
function mapReceiptForExport(item) {
  return {
    id: numOrNull(item.id),
    number: item.number ?? null,
    kind: item.kind ?? null,
    status: item.status ?? null,
    paid_on: item.paid_on ?? null,
    issued_on: item.issued_on ?? null,
    amount_minor: numOrNull(item.amount_minor),
    apartment_id: numOrNull(item.apartment?.id),
    apartment_label: item.apartment?.label ?? null,
  };
}

/** Bildirim tercihi satırı -> dosya şekli (sessiz saatler API'deki gibi "SS:DD"). Eski şemada (ek sütunlar yok) yalnız eski alanlar. */
function mapPreferences(row) {
  if (!row) {
    return {};
  }
  const out = { email_announcements: row.email_announcements };
  if ('email_finance_reminders' in row) {
    out.email_finance_reminders = row.email_finance_reminders;
  }
  out.push_announcements = row.push_announcements;
  if ('push_show_preview' in row) {
    out.push_show_preview = row.push_show_preview === true;
    out.push_quiet = {
      enabled: row.push_quiet_enabled === true,
      start: formatHhmm(Number(row.push_quiet_start), 1380),
      end: formatHhmm(Number(row.push_quiet_end), 420),
    };
  }
  out.updated_at = row.updated_at;
  return out;
}

/**
 * Tek tutarlı görünümden (REPEATABLE READ, salt okunur) çağıranın verisini toplar.
 * @returns {Promise<{ data: object, truncated: Array<{ section: string, included: number, reason: string }> }>}
 */
export async function collectPersonalData(userCode, { now = new Date(), db = pool } = {}) {
  // Borcum ile aynı kaynak: kişi kayıtları (CRM) üyeliklerden eşitlenir. Anlık görüntüden ÖNCE çalışır ki dosyaya yansısın (hata yutulur).
  await syncUserPeopleSafe(userCode);

  const client = await db.connect();
  let began = false;
  try {
    await client.query('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY');
    began = true;
    const q = async (sql) => (await client.query(sql, [userCode])).rows ?? [];
    const truncated = [];
    const bounded = async (section, sql, limit) => {
      const { rows, more } = await limitedRows(client, sql, [userCode], limit);
      if (more) {
        truncated.push({ section, included: limit, reason: 'row_limit' });
      }
      return rows;
    };

    const userRow = (await q(SQL.user))[0];
    if (!userRow) {
      throw accountDeleted();
    }
    const siteMemberships = await q(SQL.siteMemberships);
    const apartmentMemberships = await q(SQL.apartmentMemberships);
    const people = await q(SQL.people);
    const residencies = await q(SQL.residencies);
    const vehicles = await q(SQL.vehicles);
    // Sonradan eklenen migration nesneleri (yoksa ilgili bölüm boş): tercih sütunları, belgeler, aidat hatırlatma, makbuz.
    const optional = (await client.query(OPTIONAL_OBJECTS_SQL)).rows?.[0] ?? {};
    const notificationRow = (await q(optional.has_preference_extras === true ? SQL.notificationPreferences : SQL.notificationPreferencesBase))[0] ?? null;
    const announcements = await bounded('announcements_received', SQL.announcements, EXPORT_ROW_LIMITS.announcements_received);
    const applications = await bounded('site_applications', SQL.siteApplications, EXPORT_ROW_LIMITS.site_applications);
    const guestPasses = await bounded('guest_passes', SQL.guestPasses, EXPORT_ROW_LIMITS.guest_passes);
    const doorEvents = await bounded('door_events', SQL.doorEvents, EXPORT_ROW_LIMITS.door_events);
    const joinRequests = await bounded('join_requests', SQL.joinRequests, EXPORT_ROW_LIMITS.join_requests);
    const doorPermissions = await q(SQL.doorPermissions);
    const qrRequests = await bounded('qr_requests', SQL.qrRequests, EXPORT_ROW_LIMITS.qr_requests);
    const devices = await q(SQL.devices);
    // Telefon bildirimi cihaz kayıtları (Faz 3b-B): platform, sürüm, tarihler; jeton / kurulum kimliği HARİÇ. Tablo yoksa boş.
    const pushDevices = await exportPushDevices(client, userCode);
    // Yüklediğiniz belgelerin kayıt bilgisi (Faz 3b-A) ve aidat hatırlatma geçmişiniz (Faz 4b). Dosya içeriği / adres / not HARİÇ (sorgu açıklamaları).
    const uploadedDocuments = optional.has_documents === true ? await bounded('uploaded_documents', SQL.uploadedDocuments, EXPORT_ROW_LIMITS.uploaded_documents) : [];
    const financeReminders = optional.has_reminders === true ? await bounded('finance_reminders_received', SQL.financeReminders, EXPORT_ROW_LIMITS.finance_reminders_received) : [];
    const workItems = optional.has_work_items === true ? await bounded('work_items_created', SQL.workItems, EXPORT_ROW_LIMITS.work_items_created) : [];
    const workItemComments = optional.has_work_items === true ? await bounded('work_item_comments', SQL.workItemComments, EXPORT_ROW_LIMITS.work_item_comments) : [];
    const reservationsMade = optional.has_reservations === true ? await bounded('reservations_made', SQL.reservationsMade, EXPORT_ROW_LIMITS.reservations_made) : [];
    const conciergeRequestsMade = optional.has_reservations === true ? await bounded('concierge_requests_made', SQL.conciergeRequestsMade, EXPORT_ROW_LIMITS.concierge_requests_made) : [];
    const surveyVotesCast = optional.has_surveys === true ? await bounded('survey_votes_cast', SQL.surveyVotesCast, EXPORT_ROW_LIMITS.survey_votes_cast) : [];
    // Kartlı geçiş kartlarınız (046): kendi kişi kaydınız üzerinden; UID maskeli (maskCardUid). Tablo yoksa boş.
    const hasAccessCards = (await client.query(`SELECT (to_regclass('public.access_cards') IS NOT NULL) AS has_access_cards`)).rows?.[0]?.has_access_cards === true;
    const accessCards = hasAccessCards ? await bounded('access_cards', SQL.accessCards, 200) : [];
    // Makbuzlar: sakin ucunun (GET /app/my-finance/receipts) görünürlük kuralları AYNEN yeniden kullanılır (yetki mantığı kopyalanmaz; aynı bağlantı = aynı anlık görüntü).
    // Yanıt özetidir; ödeyen adı (başkasına ait olabilir) dosyaya KONMAZ (mapReceiptForExport).
    let receipts = [];
    if (optional.has_receipts === true) {
      const page = await collectHooks.listReceipts(userCode, client);
      receipts = page.items ?? [];
      if (page.next_before_id !== null && page.next_before_id !== undefined) {
        truncated.push({ section: 'receipts', included: receipts.length, reason: 'row_limit' });
      }
    }

    // user_consents (migration 035, S-B): tablo yoksa atlanır; sütunlar beyaz listeyle seçilir.
    let consents = [];
    const consentTable = (await client.query(`SELECT to_regclass('public.user_consents') AS t`)).rows?.[0]?.t;
    if (consentTable) {
      const rows = (await client.query('SELECT * FROM user_consents WHERE user_code = $1', [userCode])).rows ?? [];
      consents = rows
        .map((row) => Object.fromEntries(CONSENT_KEYS.filter((key) => key in row).map((key) => [key, row[key]])))
        .sort((a, b) => new Date(a.accepted_at ?? 0) - new Date(b.accepted_at ?? 0) || Number(a.id ?? 0) - Number(b.id ?? 0));
      consents = consents.map(({ id: _id, ...rest }) => rest);
    }

    // Finans: Borcum'un kendi görünürlük kuralları (aynı bağlantı = aynı anlık görüntü).
    const finance = await getMyFinance({ user_code: userCode }, now, client);

    await client.query('COMMIT');
    began = false;

    const residenciesByPerson = new Map();
    for (const row of residencies) {
      const key = String(row.person_id);
      if (!residenciesByPerson.has(key)) residenciesByPerson.set(key, []);
      const { person_id: _personId, ...rest } = row;
      residenciesByPerson.get(key).push({ ...rest, id: numOrNull(rest.id), apartment_id: numOrNull(rest.apartment_id), site_code: numOrNull(rest.site_code) });
    }
    const withIds = (rows, keys = ['id', 'site_code']) =>
      rows.map((row) => {
        const copy = { ...row };
        for (const key of keys) {
          if (key in copy) copy[key] = numOrNull(copy[key]);
        }
        return copy;
      });

    const data = {
      format_version: EXPORT_FORMAT_VERSION,
      generated_at: now.toISOString(),
      notice: EXPORT_NOTICE,
      user: { ...userRow, user_code: numOrNull(userRow.user_code) },
      memberships: withIds(siteMemberships, ['site_code']),
      apartment_memberships: withIds(apartmentMemberships, ['id', 'apartment_id', 'site_code']),
      people_records: people.map((row) => ({
        ...withIds([row])[0],
        residencies: residenciesByPerson.get(String(row.id)) ?? [],
      })),
      vehicles: withIds(vehicles, ['id', 'site_code', 'person_id']),
      consents,
      notification_preferences: mapPreferences(notificationRow),
      announcements_received: withIds(announcements),
      finance_statements: finance.items ?? [],
      receipts: receipts.map(mapReceiptForExport),
      finance_reminders_received: withIds(financeReminders, ['run_id', 'site_code']),
      uploaded_documents: withIds(uploadedDocuments, ['document_id', 'site_code']).map((row) => ({
        ...row,
        version_no: numOrNull(row.version_no),
        size_bytes: numOrNull(row.size_bytes),
      })),
      work_items_created: withIds(workItems),
      work_item_comments: withIds(workItemComments, ['id', 'work_item_id', 'site_code']),
      reservations_made: withIds(reservationsMade),
      concierge_requests_made: withIds(conciergeRequestsMade),
      survey_votes_cast: surveyVotesCast.map((row) => ({ survey_title: row.survey_title, option_text: row.option_text ?? null, voted_at: row.voted_at })),
      site_applications: withIds(applications),
      guest_passes: withIds(guestPasses),
      door_events: withIds(doorEvents),
      join_requests: withIds(joinRequests),
      door_permissions: withIds(doorPermissions),
      qr_requests: withIds(qrRequests).map((row) => ({
        ...row,
        request_latitude: numOrNull(row.request_latitude),
        request_longitude: numOrNull(row.request_longitude),
        request_accuracy: numOrNull(row.request_accuracy),
      })),
      devices: withIds(devices),
      push_devices: pushDevices,
      access_cards: accessCards.map((row) => ({ label: row.label ?? null, masked_uid: maskCardUid(row.card_uid), is_active: row.is_active === true })),
      excluded: [...EXPORT_EXCLUDED],
    };
    return { data, truncated };
  } finally {
    if (began) {
      try {
        await client.query('ROLLBACK');
      } catch (_rollbackError) {
        // bağlantı zaten kopmuş olabilir; asıl hata yukarıda fırlatılır
      }
    }
    client.release();
  }
}

// ---------------------------------------------------------------------------------------------------------------
// Boyut sınırı + serileştirme
// ---------------------------------------------------------------------------------------------------------------

/**
 * Büyük olabilecek bölümler. Kısaltma bölümün BAŞINDAN kayıt tutar (`slice(0, n)`), bu yüzden sorgular en yeni -> en eski sıralıdır (id / tarih DESC) ve en yeni kayıtlar kalır.
 * İstisna: `finance_statements` daire başına BİR öğedir (her öğe kendi son 30 hareketini taşır); kısaltma sondaki daireleri düşürür, hareketleri değil.
 * Kimlik / üyelik / izin bölümleri kısaltılmaz; tek başına sınırı aşarsa dosya üretilemez (413 EXPORT_TOO_LARGE, hak iade edilir).
 */
export const SHRINKABLE_SECTIONS = Object.freeze([
  'door_events',
  'announcements_received',
  'qr_requests',
  'join_requests',
  'guest_passes',
  'site_applications',
  'finance_statements',
  'receipts',
  'finance_reminders_received',
  'uploaded_documents',
  'work_items_created',
  'work_item_comments',
  'reservations_made',
  'concierge_requests_made',
  'people_records',
  'vehicles',
  'devices',
  'survey_votes_cast',
]);

/**
 * Gövdeyi `maxBytes` altına sığdırır: sığmıyorsa en büyük bölümü yarıya indirir (yinelemeli). Kısaltma `truncated_sections` ile açıkça bildirilir.
 * @returns {{ text: string, truncated: boolean, bytes: number }}
 */
export function serializeWithinLimit(data, truncatedSections = [], maxBytes = EXPORT_MAX_BYTES) {
  const sections = new Map(truncatedSections.map((entry) => [entry.section, { ...entry }]));
  const render = () => {
    const body = { ...data };
    if (sections.size > 0) {
      body.truncated = true;
      body.truncated_sections = [...sections.values()];
      body.truncation_note =
        'Dosya boyutu (5 MB) veya kayıt sınırı nedeniyle bazı bölümler en yeni kayıtlarla kısaltıldı (bkz. "truncated_sections"). Tamamı için destek ekibiyle iletişime geçebilirsiniz.';
    } else {
      body.truncated = false;
    }
    return JSON.stringify(body, null, 2);
  };
  let text = render();
  let guard = 0;
  while (Buffer.byteLength(text, 'utf8') > maxBytes && guard < 64) {
    guard += 1;
    let target = null;
    let targetSize = 0;
    for (const name of SHRINKABLE_SECTIONS) {
      const value = data[name];
      if (Array.isArray(value) && value.length > 0) {
        const size = JSON.stringify(value).length;
        if (size > targetSize) {
          target = name;
          targetSize = size;
        }
      }
    }
    if (target === null) {
      break;
    }
    const kept = Math.floor(data[target].length / 2);
    data[target] = data[target].slice(0, kept);
    sections.set(target, { section: target, included: kept, reason: 'size_limit' });
    text = render();
  }
  const bytes = Buffer.byteLength(text, 'utf8');
  if (bytes > maxBytes) {
    // Kısaltılabilir bölüm kalmadı ve gövde hâlâ sınırı aşıyor: sessiz taşma YOK; istemciye açık 413 (hak exportMyData içinde iade edilir).
    throw exportTooLarge();
  }
  return { text, truncated: sections.size > 0, bytes };
}

/** Test / QA için değiştirilebilir adımlar (sahte parola doğrulaması / veri toplama vb.). */
export const exportDeps = {
  verifyPassword: (input) => verifyCurrentPassword(input),
  acquireSlot: (userCode) => acquireExportSlot(userCode),
  releaseSlot: (slotId) => releaseExportSlot(slotId),
  collect: (userCode, options) => collectPersonalData(userCode, options),
  // Denetim: KİM + ne zaman + boyut; ad / e-posta yazılmaz (yalnız user_code; audit_log değişmezdir, kişisel veri biriktirilmez). Canlı kullanıcı kilidi altında (recordExportAudit).
  audit: (userCode, details) => recordExportAudit(userCode, details),
};

/**
 * POST /me/data-export gövde { current_password } -> { filename, text, truncated }.
 * Sıra: parola (400/429/401) -> hız sınırı (429) -> üretim (başarısızsa hak iade edilir).
 */
export async function exportMyData({ authUser, body }, now = new Date()) {
  const userCode = userCodeOf(authUser);
  if (userCode === null) {
    throw accountDeleted();
  }
  const input = plainObject(body);
  await exportDeps.verifyPassword({ userCode, currentPassword: input.current_password });
  const slotId = await exportDeps.acquireSlot(userCode);
  try {
    const { data, truncated } = await exportDeps.collect(userCode, { now });
    const serialized = serializeWithinLimit(data, truncated);
    await exportDeps.audit(userCode, { bytes: serialized.bytes, truncated: serialized.truncated });
    return { filename: exportFileName(userCode, now), text: serialized.text, truncated: serialized.truncated };
  } catch (error) {
    await exportDeps.releaseSlot(slotId);
    throw error;
  }
}

/** Test yardımcısı. */
export const exportInternals = { limitedRows, SQL };
