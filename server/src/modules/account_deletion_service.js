// Hesap silme (kimliksizleştirme) servisi: önizleme + tek işlemde silme.
//
// Sözleşme: docs/PLATFORM_SATISA_HAZIRLIK.md §1.6. Hesap SATIRI KALIR (yabancı anahtarlar bozulmasın): ad "Silinmiş Kullanıcı", e-posta
// `deleted-<user_code>@deleted.invalid`, telefon / kullanıcı adı NULL, parola özeti kullanılamaz rastgele değer, `is_active = FALSE`, `deleted_at` dolu.
// Hesabın ürettiği / yönetim kayıtları (denetim, finans, duyuru vb.) tombstone satırına bağlı kalır; kişisel iz (ad anlık görüntüleri, IP, konum, jeton,
// misafir adı, okundu, bekleyen e-posta) silinir ya da kimliksizleştirilir. FK politika tablosu: docs / rapor ("account_deletion" bölümü).
// Belgeler (Faz 3b-A): documents.created_by / documents.deleted_by / document_versions.uploaded_by tombstone satırına bağlı KALIR (belge siteye aittir, silinmez;
// yükleyen adı JOIN ile "Silinmiş Kullanıcı" görünür). Dosya adı / içeriği kişisel veri dışa aktarmaya GİRMEZ (kişinin kendi verisi değil; EXPORT_EXCLUDED).
//
// KİLİT SIRASI (deadlock olmaması için HEPSİ mevcut akışlarla AYNI yönde; ters sıra yok):
//   küresel advisory `account_deletion` (silmeleri sıraya sokar: çift silme, son-yönetici yarışı) ->
//   join_requests (kullanıcının, id sırası; onay akışı jr -> daire ile aynı yön) ->
//   advisory `people_sync:<site>` (kullanıcının siteleri, artan; CRM yazmaları / eşitleme / duyuru yayını ile ORTAK anahtar) ->
//   sites.deletion_requested_by_name (yapı düzenleme: people_sync -> UPDATE sites ile aynı yön) ->
//   apartments (id sırası, FOR UPDATE; users silme tetikleyicisiyle AYNI küme) ->
//   devices (id sırası; site başvurusu onayı: cihaz -> kullanıcı ile aynı yön) ->
//   site_manager_sites / site_memberships(sahip, yönetici) satırları (siteler artan; removeSiteManager ile aynı yön) ->
//   users (hesap satırı; anonimleştirme UPDATE'i) -> KALAN: kullanıcıya ait satırlar (üyelik, jeton, misafir geçişi, CRM kişi satırları, duyuru alıcıları,
//   modül talebi adları, başvuru). Kullanıcı satırından SONRA yalnız bu kullanıcıya özgü satırlar yazılır (başka işlemlerin uzun süre tuttuğu paylaşılan
//   satır YOK): site_applications (iptal akışıyla aynı yön: users -> başvuru) ve site_people / residencies / vehicles (silme tetikleyicisiyle aynı yön).
//   Kullanıcı satırı kilitlendikten sonra kapsam (daire / site / cihaz) YENİDEN okunur; kilitlenen kümeden büyümüşse (eşzamanlı onay / üyelik) işlem
//   geri alınıp baştan denenir (en çok 3 kez; sonra 409 ACCOUNT_DELETE_BUSY). Nadir 40P01'de TEK sefer baştan denenir.
//
// ENGELLER (409 ACCOUNT_DELETE_BLOCKED): SUPER_USER; LAST_SITE_MANAGER (yönetici olduğu sitede başka AKTİF yönetici yok VE sitede başka aktif
// hesaplı üye var). Engel kontrolü silme işleminin İÇİNDE, kilitler altında yapılır (iki yöneticinin birbirinden bağımsız silinmesiyle sitenin yönetimsiz
// kalması yarışı kapanır).
//
// GİZLİLİK: e-posta / ad / telefon / parola / belirteç log'a YAZILMAZ; audit `details` yalnız sayı ve rol taşır.

import crypto from 'crypto';
import { pool } from '../db.js';
import { isSmtpConfigured, sendAccountDeletedEmail } from '../mailer.js';
import { newErrorId } from '../middlewares/error_handler.js';
import { clearAccountLocks } from '../middlewares/login_throttle.js';
import { handOverApartmentResident } from '../services/membership_service.js';
import { rotateTokensForDevices, rotateTokensForSite } from '../services/local_token_service.js';
import {
  CRM_KEEP_NAME,
  DELETED_GUEST_PASS_TITLE,
  DELETED_USER_NAME,
  accountBusy,
  accountDeleted,
  confirmRequired,
  deleteBlocked,
  deletedEmailFor,
  isDeliverableEmail,
  isSubsetOf,
  lastSiteManagerBlocker,
  plainObject,
  superUserBlocker,
  userCodeOf,
} from './account_common.js';
import { verifyCurrentPassword } from './account_password_guard.js';
import { recordAudit } from './audit_service.js';
import { peopleLockKey } from './people_sync.js';
import { deletePushDataForUser } from './push_devices.js';
import { workItemsKeepNote } from './work_tracking_common.js';
import { releaseAssignedWorkItems } from './work_tracking_service.js';
import { reservationKeepNote, reservationRemoveNote } from './reservation_common.js';
import { releaseUserReservations } from './reservation_service.js';
import { surveyVotesKeepNote } from './survey_common.js';
import { anonymizeUserSurveyData, countUserSurveyVotes } from './survey_service.js';

const GLOBAL_LOCK_KEY = 'account_deletion';
const MAX_SCOPE_ATTEMPTS = 3;
const SYSTEM_ACTOR = Object.freeze({ name: 'Sistem', role: 'system' });

/** Test / QA için değiştirilebilir bağımlılıklar (gerçek SMTP / MQTT'ye bağlanmadan). */
export const accountHooks = {
  rotateTokensForSite,
  rotateTokensForDevices,
  // Anahtar döndürme başarısız olursa (DB / yük anı) yeniden deneme: ilk deneme + bu bekleme süreleriyle 3 yeniden deneme (1 / 5 / 20 sn). Testler süreleri kısaltır.
  rotationBackoffMs: [1000, 5000, 20000],
  sleep: (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
  // Tüm denemeler tükenince KİMLİKSİZ denetim satırı (yalnız sayılar).
  recordRotationFailure: (userCode, details) =>
    recordAudit(pool, { actor: SYSTEM_ACTOR, action: 'account.key_rotation_failed', targetType: 'user', targetId: String(userCode), details }),
  sendDeletedEmail: sendAccountDeletedEmail,
  smtpConfigured: () => isSmtpConfigured(),
  // Silme sonrası işler (anahtar döndürme, e-posta) yanıtı BEKLETMEZ; hata yutulur (kod log'a). QA bunu satır içi çalışacak şekilde değiştirebilir.
  background: (task) => {
    void Promise.resolve()
      .then(task)
      .catch((error) => {
        // eslint-disable-next-line no-console
        console.error('[account] silme sonrasi islem basarisiz:', error?.code || error?.name || 'error');
      });
  },
};

const num = (value) => Number(value);

/**
 * Tombstone e-postası: `deleted-<kod>@deleted.invalid`; başka bir satır (ya da büyük/küçük harf farkıyla) aynı adresi almışsa `deleted-<kod>-<rastgele>@...`.
 * Çakışma kontrolü kullanıcı kodunu dışlar (kendi satırı zaten bu adreste olamaz). Rastgele sonek CSPRNG'den gelir; en çok 5 deneme.
 */
export async function pickDeletedEmail(client, userCode, randomSuffix = () => crypto.randomBytes(5).toString('hex')) {
  let candidate = deletedEmailFor(userCode);
  for (let attempt = 0; attempt < 5; attempt += 1) {
    const taken = await client.query('SELECT 1 FROM users WHERE LOWER(email) = LOWER($1) AND user_code <> $2 LIMIT 1', [candidate, userCode]);
    if (!taken.rows?.[0]) {
      return candidate;
    }
    candidate = deletedEmailFor(userCode, randomSuffix());
  }
  throw accountBusy();
}

/**
 * Kullanıcının hesabına bağlı kişi kayıtlarının aidat hatırlatma kalemlerini (finance_reminder_items) temizler: e-posta adresi ve özeti NULL, bekleyen kalem 'resolved' (kuyruk
 * işçisinin "kişi artık geçerli değil" sonucuyla aynı durum), claim / sonraki deneme alanları temizlenir. Satırlar (run_id, person_id) sırasıyla kilitlenir (işçinin
 * `FOR UPDATE SKIP LOCKED` sırasıyla aynı -> kilitlenme yok). Tablo yoksa (040 öncesi şema) atlanır. Kalem satırları silinmez (çalıştırma sayaçları / geçmiş).
 *
 * DAİRE ARALIK KAYITLARI (finance_reminder_apartments): çalıştırma, daireleri "hatırlatıldı" diye kaydeder; sonraki planlar bu kayıtla asgari aralık / art arda sayısını hesaplar
 * (finance_reminders.loadCandidateApartments -> hist). Bekleyen kalemi burada 'resolved' yapınca GÖNDERİM OLMADAN kalan kayıt, o dairenin başka sorumlusuna hatırlatmayı
 * (aralık) geciktirirdi; kuyruğun kendi yolu (RELEASE_INTERVALS_SQL) bunu serbest bırakır, burada aynı mantık AYNI işlemde yinelenir: etkilenen çalıştırmalarda, hiçbir
 * 'sent' / 'pending' kalemin kapsamadığı ve en az bir gönderilmemiş (failed / resolved / skipped_pref / cancelled) kalemin kapsadığı daire kayıtları silinir. Kilit sırası:
 * kalemler (run_id, person_id) -> aralık kayıtları (run_id, apartment_id).
 * @returns {Promise<number>} güncellenen kalem sayısı
 */
export async function clearReminderItems(client, userCode) {
  const present = (await client.query(`SELECT to_regclass('public.finance_reminder_items') IS NOT NULL AS present`)).rows?.[0]?.present === true;
  if (!present) {
    return 0;
  }
  const result = await client.query(
    `
      UPDATE finance_reminder_items i
      SET email = NULL, email_hash = NULL, email_claimed_at = NULL, email_next_at = NULL,
          email_status = CASE WHEN i.email_status = 'pending' THEN 'resolved' ELSE i.email_status END
      WHERE (i.run_id, i.person_id) IN (
        SELECT i2.run_id, i2.person_id
        FROM finance_reminder_items i2
        INNER JOIN site_people sp ON sp.id = i2.person_id AND sp.user_code = $1
        WHERE i2.email IS NOT NULL OR i2.email_hash IS NOT NULL OR i2.email_status = 'pending'
        ORDER BY i2.run_id, i2.person_id
        FOR UPDATE OF i2
      )
      RETURNING i.run_id
    `,
    [userCode],
  );
  const runIds = [...new Set((result.rows ?? []).map((row) => Number(row.run_id)))].sort((a, b) => a - b);
  if (runIds.length > 0) {
    await client.query(
      `
        DELETE FROM finance_reminder_apartments fa
        WHERE (fa.apartment_id, fa.run_id) IN (
          SELECT fa2.apartment_id, fa2.run_id
          FROM finance_reminder_apartments fa2
          WHERE fa2.run_id = ANY($1::BIGINT[])
            AND EXISTS (
              SELECT 1 FROM finance_reminder_items gone
              WHERE gone.run_id = fa2.run_id AND fa2.apartment_id = ANY(gone.apartment_ids)
                AND gone.email_status IN ('failed', 'resolved', 'skipped_pref', 'cancelled')
            )
            AND NOT EXISTS (
              SELECT 1 FROM finance_reminder_items keep
              WHERE keep.run_id = fa2.run_id AND keep.email_status IN ('sent', 'pending') AND fa2.apartment_id = ANY(keep.apartment_ids)
            )
          ORDER BY fa2.run_id, fa2.apartment_id
          FOR UPDATE OF fa2
        )
      `,
      [runIds],
    );
  }
  return Number(result.rowCount ?? 0);
}

async function bestEffort(client, name, work) {
  // SAVEPOINT: yardımcı adımın hatası (ör. denetim satırı) silmeyi bozmaz ve işlemi "aborted" durumuna sokmaz.
  const savepoint = `acct_${name}`;
  await client.query(`SAVEPOINT ${savepoint}`);
  try {
    const result = await work();
    await client.query(`RELEASE SAVEPOINT ${savepoint}`);
    return result;
  } catch (error) {
    await client.query(`ROLLBACK TO SAVEPOINT ${savepoint}`);
    await client.query(`RELEASE SAVEPOINT ${savepoint}`);
    // eslint-disable-next-line no-console
    console.error(`[account] ${name} adimi atlandi:`, error?.code || error?.name || 'error');
    return null;
  }
}

// ---------------------------------------------------------------------------------------------------------------
// Engeller
// ---------------------------------------------------------------------------------------------------------------

const MANAGED_SITES_CTE = `
  managed AS (
    SELECT site_code FROM site_manager_sites WHERE manager_user_code = $1
    UNION
    SELECT site_code FROM site_memberships WHERE user_code = $1 AND role IN ('SITE_OWNER', 'SITE_ADMIN') AND is_active = TRUE
  )
`;

/**
 * Kullanıcının yönettiği siteler içinde "son yönetici" olduğu ve sitede başka aktif hesaplı üye bulunan siteler. Tek küme sorgusu.
 * "Başka aktif yönetici": site_manager_sites bağı VEYA aktif SITE_OWNER / SITE_ADMIN üyeliği olan, aktif ve silinmemiş başka hesap.
 * "Aktif üye": başka aktif hesabın aktif dairede aktif daire üyeliği / sakin göstergesi ya da yönetici olmayan aktif site üyeliği (RESIDENT, kurul, görevli).
 * @returns {Promise<Array<{ site_code: number, name: string }>>}
 */
export async function findLastManagerSites(db, userCode) {
  const result = await db.query(
    `
      WITH ${MANAGED_SITES_CTE}
      SELECT s.site_code, s.name
      FROM sites s
      WHERE s.site_code IN (SELECT site_code FROM managed)
        AND NOT (
          EXISTS (
            SELECT 1 FROM site_manager_sites ms
            INNER JOIN users mu ON mu.user_code = ms.manager_user_code
            WHERE ms.site_code = s.site_code AND ms.manager_user_code <> $1 AND mu.is_active = TRUE AND mu.deleted_at IS NULL
          )
          OR EXISTS (
            SELECT 1 FROM site_memberships sm
            INNER JOIN users mu ON mu.user_code = sm.user_code
            WHERE sm.site_code = s.site_code AND sm.user_code <> $1 AND sm.role IN ('SITE_OWNER', 'SITE_ADMIN') AND sm.is_active = TRUE
              AND mu.is_active = TRUE AND mu.deleted_at IS NULL
          )
        )
        AND (
          EXISTS (
            SELECT 1 FROM apartment_memberships am
            INNER JOIN apartments a ON a.id = am.apartment_id
            INNER JOIN users mu ON mu.user_code = am.user_code
            WHERE a.site_code = s.site_code AND a.is_active = TRUE AND am.is_active = TRUE AND am.user_code <> $1
              AND mu.is_active = TRUE AND mu.deleted_at IS NULL
          )
          OR EXISTS (
            SELECT 1 FROM apartments a
            INNER JOIN users mu ON mu.user_code = a.resident_user_code
            WHERE a.site_code = s.site_code AND a.is_active = TRUE AND a.resident_user_code <> $1 AND mu.is_active = TRUE AND mu.deleted_at IS NULL
          )
          OR EXISTS (
            SELECT 1 FROM site_memberships sm
            INNER JOIN users mu ON mu.user_code = sm.user_code
            WHERE sm.site_code = s.site_code AND sm.user_code <> $1 AND sm.is_active = TRUE AND sm.role NOT IN ('SITE_OWNER', 'SITE_ADMIN')
              AND mu.is_active = TRUE AND mu.deleted_at IS NULL
          )
        )
      ORDER BY s.site_code
    `,
    [userCode],
  );
  return (result.rows ?? []).map((row) => ({ site_code: num(row.site_code), name: row.name ?? null }));
}

// ---------------------------------------------------------------------------------------------------------------
// Önizleme
// ---------------------------------------------------------------------------------------------------------------

/**
 * Önizleme sayıları: isteğe bağlı (sonradan eklenen migration) tablolar katalog kontrolüyle; tablo yoksa 0. Yalnız çağıranın kendi kayıtları.
 * @returns {Promise<{ pushDevices: number, uploadedDocuments: number, pendingReminders: number }>}
 */
async function previewOptionalCounts(db, userCode) {
  const out = { pushDevices: 0, uploadedDocuments: 0, pendingReminders: 0, workItems: 0, workItemComments: 0, upcomingReservations: 0, reservationRecords: 0, openRequests: 0, requestRecords: 0 };
  const flags = (
    await db.query(
      `
        SELECT (to_regclass('public.push_devices') IS NOT NULL) AS has_push_devices,
               (to_regclass('public.document_versions') IS NOT NULL) AS has_documents,
               (to_regclass('public.finance_reminder_items') IS NOT NULL) AS has_reminders,
               (to_regclass('public.work_items') IS NOT NULL) AS has_work_items,
               (to_regclass('public.reservations') IS NOT NULL) AS has_reservations
      `,
    )
  ).rows?.[0];
  const count = async (sql) => num((await db.query(sql, [userCode])).rows?.[0]?.n ?? 0);
  if (flags?.has_push_devices === true) {
    out.pushDevices = await count('SELECT COUNT(*)::INTEGER AS n FROM push_devices WHERE user_code = $1');
  }
  if (flags?.has_documents === true) {
    out.uploadedDocuments = await count('SELECT COUNT(*)::INTEGER AS n FROM document_versions WHERE uploaded_by = $1');
  }
  if (flags?.has_work_items === true) {
    out.workItems = await count('SELECT COUNT(*)::INTEGER AS n FROM work_items WHERE created_by = $1');
    out.workItemComments = await count("SELECT COUNT(*)::INTEGER AS n FROM work_item_events WHERE actor_user_code = $1 AND event_type = 'comment'");
  }
  if (flags?.has_reservations === true) {
    out.upcomingReservations = await count("SELECT COUNT(*)::INTEGER AS n FROM reservations WHERE user_code = $1 AND status IN ('beklemede', 'onaylandi') AND ends_at > NOW()");
    out.reservationRecords = await count('SELECT COUNT(*)::INTEGER AS n FROM reservations WHERE user_code = $1');
    out.openRequests = await count("SELECT COUNT(*)::INTEGER AS n FROM concierge_requests WHERE user_code = $1 AND status IN ('yeni', 'hazirlaniyor')");
    out.requestRecords = await count('SELECT COUNT(*)::INTEGER AS n FROM concierge_requests WHERE user_code = $1');
  }
  if (flags?.has_reminders === true) {
    out.pendingReminders = await count(
      `SELECT COUNT(*)::INTEGER AS n FROM finance_reminder_items i INNER JOIN site_people sp ON sp.id = i.person_id AND sp.user_code = $1 WHERE i.email_status = 'pending' AND i.email IS NOT NULL`,
    );
  }
  // Anket ve oylama (044): oylar KALIR ve anonimleşir; yalnız sayı (tablo yoksa 0).
  out.surveyVotes = await countUserSurveyVotes(db, userCode);
  return out;
}

/**
 * POST /me/account-deletion/preview -> { can_delete, blockers, will_remove, will_keep }.
 * Yazma yapmaz, kilit almaz. Sayılar yalnız çağıranın KENDİ kayıtlarındandır.
 */
export async function previewAccountDeletion(authUser, db = pool) {
  const userCode = userCodeOf(authUser);
  if (userCode === null) {
    throw accountDeleted();
  }
  const found = await db.query('SELECT id, role, deleted_at FROM users WHERE user_code = $1 LIMIT 1', [userCode]);
  const user = found.rows?.[0];
  if (!user || user.deleted_at) {
    throw accountDeleted();
  }
  const blockers = [];
  if (user.role === 'super_user') {
    blockers.push(superUserBlocker());
  } else {
    for (const site of await findLastManagerSites(db, userCode)) {
      blockers.push(lastSiteManagerBlocker(site));
    }
  }

  const counts = (
    await db.query(
      `
        SELECT
          (SELECT COUNT(*) FROM apartment_memberships WHERE user_code = $1)::INTEGER AS apartment_links,
          ((SELECT COUNT(*) FROM site_memberships WHERE user_code = $1) + (SELECT COUNT(*) FROM site_manager_sites WHERE manager_user_code = $1))::INTEGER AS site_links,
          (SELECT COUNT(*) FROM guest_passes WHERE created_by_user_code = $1 AND is_active = TRUE AND expires_at > NOW())::INTEGER AS active_passes,
          (SELECT COUNT(*) FROM qr_access_tokens WHERE user_code = $1 AND is_active = TRUE AND revoked_at IS NULL AND (expires_at IS NULL OR expires_at > NOW()))::INTEGER AS active_qr,
          (SELECT COUNT(*) FROM site_applications WHERE applicant_user_code = $1 AND status = 'pending')::INTEGER AS pending_applications,
          (SELECT COUNT(*) FROM site_applications WHERE applicant_user_code = $1 AND status <> 'pending')::INTEGER AS closed_applications,
          (SELECT COUNT(*) FROM devices WHERE assigned_user_code = $1 OR owner_user_id = $2)::INTEGER AS devices,
          (to_regclass('public.user_consents') IS NOT NULL) AS has_consents
      `,
      [userCode, user.id],
    )
  ).rows[0];

  // Sonradan eklenen migration tabloları (yoksa 0): telefon bildirimi cihazları (041), yüklenen belgeler (039), bekleyen aidat hatırlatma kalemleri (040).
  const optionalCounts = await previewOptionalCounts(db, userCode);

  // Metinler server/legal/account_deletion.md (§2 "Silinen veya kimliksizleştirilen veriler", §3 "Saklanan veriler") ile TUTARLI tutulur: biri değişirse diğeri de
  // değişmelidir (test/account_deletion_service.test.js bu metinlerin yasal belgeyle aynı maddeleri taşıdığını sınar). Süre / dayanak iddiası yazılmaz (belge kararları bekliyor).
  const willRemove = [
    'Hesabınız: adınız "Silinmiş Kullanıcı" olarak değiştirilir; e-posta adresiniz, telefon numaranız, kullanıcı adınız ve parolanız hesaptan kaldırılır; tüm oturumlarınız kapanır ve hesap bir daha etkinleştirilemez.',
    num(counts.apartment_links) + num(counts.site_links) > 0
      ? `Site ve daire üyelikleriniz (${num(counts.apartment_links) + num(counts.site_links)}) ile yönetici, kurul veya görevli rolleriniz ve kapı erişim yetkileriniz kaldırılır.`
      : 'Varsa site ve daire üyelikleriniz, rolleriniz ve kapı erişim yetkileriniz kaldırılır.',
    num(counts.active_passes) + num(counts.active_qr) > 0
      ? `Etkin misafir geçişleriniz (${num(counts.active_passes)}) ve karekod belirteçleriniz (${num(counts.active_qr)}) iptal edilir; misafir geçişlerinin başlıkları "Silinmiş kullanıcının geçişi" olur.`
      : 'Misafir geçişleriniz ve karekod belirteçleriniz iptal edilir; misafir geçişlerinin başlıkları "Silinmiş kullanıcının geçişi" olur.',
    'Katılım başvurularınız ve gönderdiğiniz yönetici davetleri silinir.',
    'Bildirim tercihleriniz, duyuru okundu kayıtlarınız ve bekleyen duyuru e-postalarınız silinir.',
    'Hesabınıza bağlı kapı geçiş kayıtlarındaki adınız "Silinmiş Kullanıcı" ile değiştirilir ve IP adresiniz silinir; modül talebi kayıtlarındaki adınız da "Silinmiş Kullanıcı" olur.',
    'Bu e-posta adresine ait doğrulama kodu ve bekleyen kayıt kayıtları silinir.',
  ];
  if (num(counts.pending_applications) > 0) {
    willRemove.push('Bekleyen site başvurunuz geri çekilir.');
  }
  if (num(counts.devices) > 0) {
    willRemove.push(`Hesabınıza bağlı cihazların (${num(counts.devices)}) sahiplik bilginiz kaldırılır.`);
  }
  if (optionalCounts.pushDevices > 0) {
    willRemove.push(`Telefon bildirimi için kayıtlı cihazlarınız (${optionalCounts.pushDevices}) ve bunların bildirim jetonları ile bekleyen telefon bildirimleriniz silinir.`);
  }
  if (optionalCounts.pendingReminders > 0) {
    willRemove.push(`Size gönderilmek üzere bekleyen aidat hatırlatma e-postalarının (${optionalCounts.pendingReminders}) kayıtlarındaki e-posta adresiniz silinir; bu hatırlatmalar gönderilmez.`);
  }

  if (optionalCounts.upcomingReservations > 0 || optionalCounts.openRequests > 0) {
    willRemove.push(reservationRemoveNote({ upcoming: optionalCounts.upcomingReservations, openRequests: optionalCounts.openRequests }));
  }

  const willKeep = [
    CRM_KEEP_NAME
      ? 'Site Yönetiminin tuttuğu kayıtlar yasal saklama gerekçesiyle kalır: adınız, dairedeki ilişki geçmişiniz, pasif hâle getirilmiş araç kaydınız (plaka) ile yönetimin kişi kaydınıza girdiği telefon numarası ve notlar ve araç kaydınıza girdiği not. Bu kayıtlar hesabınızdan ayrılır (e-posta adresiniz ve hesap bağlantınız kaldırılır; hesabınızdaki telefon numarası kopyalanmaz) ve sorumlusu Site Yönetimidir.'
      : 'Site Yönetiminin tuttuğu kişi, daire geçmişi ve araç kayıtları adınız olmadan, yasal saklama gerekçesiyle kalır; yönetimin girdiği telefon numarası ve notlar da bu kayıtlarla birlikte kalır. Bu kayıtlar hesabınızdan ayrılır ve sorumlusu Site Yönetimidir.',
    'Aidat, borç ve ekstre kayıtları daireye bağlı olarak site yönetiminde kalır.',
    'Yönetim işlem (denetim) kayıtları güvenlik ve hesap verebilirlik amacıyla, işlemi yapan kişi olarak adınız DEĞİŞTİRİLMEDEN saklanır. Bu kayıtları platform yöneticisi okur; kişi, daire ve araç kayıtlarına ilişkin geçmiş kısmını ilgili sitenin yöneticisi ve kurul üyeleri de geçmiş ekranında görebilir. Ayrıntılarda hesabı olmayan kişilerin eski ve yeni adları, araç plakaları ve silinen dairelerin geçmiş sakinlerinin adları ile tarihleri bulunabilir.',
    'Kapı geçiş kayıtları kimliksizleştirilmiş olarak 30 gün sonra otomatik silinir; kapı cihazından senkronlanan çevrimdışı geçiş kayıtları hesabınıza bağlı olmadan yalnız adla saklandığı için bu kayıtlardaki ad 30 günlük süre dolana kadar kalabilir.',
    '"Silinmiş Kullanıcı" adlı, ad, e-posta veya telefon içermeyen bir hesap kaydı (kullanıcı kodu ve oluşturulma tarihi) kayıtların bütünlüğü için kalır.',
    'Duyuru e-postalarından çıktıysanız, çıkış tercihinizin korunması için e-posta adresinizin geri döndürülemez özeti listede kalır.',
    'Sunucu günlükleri ve yedeklerdeki kopyalar kendi saklama döngüleri dolana kadar kalır, sonra yok edilir.',
  ];
  if (optionalCounts.uploadedDocuments > 0) {
    willKeep.push(`Yüklediğiniz belgeler (${optionalCounts.uploadedDocuments} dosya sürümü) site yönetiminde kalır (belgeler siteye aittir); yükleyen adı "Silinmiş Kullanıcı" olarak görünür.`);
  }
  if (optionalCounts.workItems > 0 || optionalCounts.workItemComments > 0) {
    willKeep.push(workItemsKeepNote({ items: optionalCounts.workItems, comments: optionalCounts.workItemComments }));
  }
  if (optionalCounts.reservationRecords > 0 || optionalCounts.requestRecords > 0) {
    willKeep.push(reservationKeepNote({ reservations: optionalCounts.reservationRecords, requests: optionalCounts.requestRecords }));
  }
  if (optionalCounts.surveyVotes > 0) {
    willKeep.push(surveyVotesKeepNote(optionalCounts.surveyVotes));
  }
  if (num(counts.apartment_links) + num(counts.site_links) > 0) {
    willKeep.push('Makbuz ve tahsilat kayıtları (düzenleyen yönetici ve ödeyen adını içeren makbuz anlık görüntüsü dahil) yasal mali kayıt saklama yükümlülükleri gereği DEĞİŞTİRİLMEDEN saklanır; makbuz anlık görüntüsündeki ad anonimleştirilmez.');
  }
  if (num(counts.closed_applications) > 0) {
    willKeep.push('Daha önce sonuçlanmış (onaylanmış veya reddedilmiş) site başvurularınızdaki site bilgileri ve notlar, kimliksizleştirilmiş hesaba bağlı olarak kalır.');
  }
  if (counts.has_consents === true) {
    willKeep.push('Verdiğiniz yasal onayların kaydı, kimliksizleştirilmiş hesaba bağlı olarak yasal saklama süresince tutulur.');
  }

  return { can_delete: blockers.length === 0, blockers, will_remove: willRemove, will_keep: willKeep };
}

// ---------------------------------------------------------------------------------------------------------------
// Silme
// ---------------------------------------------------------------------------------------------------------------

/** Kullanıcının kapsamı (kilit kümeleri). `userDbId`: users.id (devices.owner_user_id bunu tutar). */
async function readScope(client, userCode, userDbId) {
  const apartments = await client.query(
    `
      SELECT a.id, a.site_code, a.resident_user_code
      FROM apartments a
      WHERE a.resident_user_code = $1
         OR a.id IN (SELECT am.apartment_id FROM apartment_memberships am WHERE am.user_code = $1)
         OR a.id IN (
           SELECT r.apartment_id FROM apartment_residencies r
           INNER JOIN site_people sp ON sp.id = r.person_id
           WHERE sp.user_code = $1 AND r.is_current
         )
      ORDER BY a.id
    `,
    [userCode],
  );
  const sites = await client.query(
    `
      SELECT site_code FROM site_manager_sites WHERE manager_user_code = $1
      UNION SELECT site_code FROM site_memberships WHERE user_code = $1
      UNION SELECT site_code FROM site_people WHERE user_code = $1
      ORDER BY 1
    `,
    [userCode],
  );
  const managed = await client.query(
    `
      SELECT site_code FROM site_manager_sites WHERE manager_user_code = $1
      UNION SELECT site_code FROM site_memberships WHERE user_code = $1 AND role IN ('SITE_OWNER', 'SITE_ADMIN') AND is_active = TRUE
      ORDER BY 1
    `,
    [userCode],
  );
  const devices = await client.query(
    'SELECT id FROM devices WHERE assigned_user_code = $1 OR owner_user_id = $2 ORDER BY id',
    [userCode, userDbId],
  );
  const apartmentRows = (apartments.rows ?? []).map((row) => ({
    id: num(row.id),
    site_code: num(row.site_code),
    resident_user_code: row.resident_user_code === null || row.resident_user_code === undefined ? null : num(row.resident_user_code),
  }));
  const siteCodes = [...new Set([...(sites.rows ?? []).map((row) => num(row.site_code)), ...apartmentRows.map((row) => row.site_code)])].sort((a, b) => a - b);
  return {
    apartments: apartmentRows,
    apartmentIds: apartmentRows.map((row) => row.id),
    siteCodes,
    managedSiteCodes: (managed.rows ?? []).map((row) => num(row.site_code)),
    deviceIds: (devices.rows ?? []).map((row) => num(row.id)),
  };
}

/**
 * Yönettiği sitelerdeki DİĞER yöneticilerin `users` satırlarını `FOR SHARE` ile, user_code SIRASIYLA kilitler (R2 F-4).
 *
 * Neden: "başka aktif yönetici var" kararı o yöneticinin `users.is_active / deleted_at` değerine dayanır. Yönetici B'nin hesabını eşzamanlı
 * pasifleştiren (admin PATCH) ya da kalıcı silen (admin DELETE) işlem COMMIT olmadan, yönetici A'nın silmesi B'yi hâlâ aktif görür; ikisi de
 * tamamlanınca site yönetimsiz kalırdı. FOR SHARE, B'nin devam eden UPDATE/DELETE'ini BEKLER (READ COMMITTED: bir sonraki engel sorgusu sonucu görür) ve
 * sonrasında B'yi aktif tutar (B'nin pasifleştirme UPDATE'i bu işlem bitene dek bekler). Küresel silme kilidi sayesinde iki silme birbirini kilitlemez; kilit
 * sırası (site satırları -> kendi users satırı -> eş yöneticilerin users satırları, artan user_code) başka hiçbir akışta TERS yönde alınmaz
 * (removeSiteManager yalnız hedefin users satırını NO KEY UPDATE ile alır; admin PATCH tek users satırı yazar).
 */
async function lockPeerManagerUsers(client, userCode, managedSiteCodes) {
  if (!Array.isArray(managedSiteCodes) || managedSiteCodes.length === 0) {
    return;
  }
  await client.query(
    `
      SELECT u.user_code
      FROM users u
      WHERE u.user_code <> $1
        AND u.user_code IN (
          SELECT manager_user_code FROM site_manager_sites WHERE site_code = ANY($2::BIGINT[])
          UNION
          SELECT user_code FROM site_memberships WHERE site_code = ANY($2::BIGINT[]) AND role IN ('SITE_OWNER', 'SITE_ADMIN') AND is_active = TRUE
        )
      ORDER BY u.user_code
      FOR SHARE OF u
    `,
    [userCode, managedSiteCodes],
  );
}

const scopeGrew = (after, locked) =>
  !isSubsetOf(after.apartmentIds, locked.apartmentIds) ||
  !isSubsetOf(after.siteCodes, locked.siteCodes) ||
  !isSubsetOf(after.deviceIds, locked.deviceIds);

/** Anonimleştirilmiş hesabın parola özeti: biçimi geçerli bir bcrypt özeti OLMADIĞI için hiçbir parola eşleşmez (bcrypt.compare yanlış döner). */
export const unusablePasswordHash = () => `!${crypto.randomBytes(48).toString('hex')}`;

async function runAttempt(userCode) {
  const client = await pool.connect();
  let began = false;
  let committed = false;
  try {
    await client.query('BEGIN');
    began = true;
    // 0. Küresel sıra: silmeler birbirini bekler (çift silme / "son yönetici" yarışı); başka akışlar bu anahtarı ALMAZ.
    await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', [GLOBAL_LOCK_KEY]);

    const found = await client.query(
      'SELECT id, user_code, full_name, email, login_name, role, is_active, deleted_at FROM users WHERE user_code = $1 LIMIT 1',
      [userCode],
    );
    const user = found.rows?.[0];
    if (!user || user.deleted_at) {
      throw accountDeleted();
    }
    if (user.role === 'super_user') {
      throw deleteBlocked([superUserBlocker()]);
    }

    // 1. Katılım talepleri (onay akışı: talep -> daire yönünde kilitler).
    await client.query('SELECT id FROM join_requests WHERE user_code = $1 ORDER BY id FOR UPDATE', [userCode]);

    // 2. Kapsam + site advisory kilitleri (CRM yazmaları / eşitleme / duyuru yayını ile ortak anahtar; artan sıra).
    const scope = await readScope(client, userCode, user.id);
    for (const siteCode of scope.siteCodes) {
      await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', [peopleLockKey(siteCode)]);
    }
    // Site silme talebindeki ad anlık görüntüsü (yapı düzenleme akışıyla aynı yön: people_sync -> UPDATE sites).
    await client.query(
      'UPDATE sites SET deletion_requested_by_name = $2 WHERE deletion_requested_by_user_code = $1 AND deletion_requested_by_name IS DISTINCT FROM $2',
      [userCode, DELETED_USER_NAME],
    );

    // 3. Daireler (users silme tetikleyicisiyle AYNI küme, id sırası).
    if (scope.apartmentIds.length > 0) {
      await client.query('SELECT id FROM apartments WHERE id = ANY($1::BIGINT[]) ORDER BY id FOR UPDATE', [scope.apartmentIds]);
    }
    // 4. Cihazlar (kullanıcıdan ÖNCE: site başvurusu onayı cihaz -> kullanıcı sırasını kullanır).
    if (scope.deviceIds.length > 0) {
      await client.query('SELECT id FROM devices WHERE id = ANY($1::BIGINT[]) ORDER BY id FOR UPDATE', [scope.deviceIds]);
      await client.query(
        `
          UPDATE devices
          SET assigned_user_code = CASE WHEN assigned_user_code = $2 THEN NULL ELSE assigned_user_code END,
              owner_user_id = CASE WHEN owner_user_id = $3 THEN NULL ELSE owner_user_id END
          WHERE id = ANY($1::BIGINT[])
        `,
        [scope.deviceIds, userCode, user.id],
      );
    }
    // 5. Yönetici satırları (removeSiteManager ile aynı yön: site_manager_sites -> site_memberships -> users).
    if (scope.managedSiteCodes.length > 0) {
      await client.query(
        'SELECT site_code FROM site_manager_sites WHERE site_code = ANY($1::BIGINT[]) ORDER BY site_code, manager_user_code FOR UPDATE',
        [scope.managedSiteCodes],
      );
      await client.query(
        `
          SELECT site_code FROM site_memberships
          WHERE site_code = ANY($1::BIGINT[]) AND role IN ('SITE_OWNER', 'SITE_ADMIN') AND is_active = TRUE
          ORDER BY site_code, user_code FOR UPDATE
        `,
        [scope.managedSiteCodes],
      );
    }

    // 6. Hesap satırı: anonimleştirme (satır FOR UPDATE ile kilitlenir; bundan sonra bu kullanıcıya yeni FK satırı eklenemez, mevcutlar görünür).
    // Tombstone e-postası REZERVE DEĞİLDİR (alan adı kayıtta yeni reddedilir ama eski satırlar olabilir): başka bir satırca alınmışsa users.email UNIQUE
    // ihlali (23505 -> 500) yerine rastgele sonekli adres kullanılır. Küresel silme kilidi + kullanıcı satırı kilidi altında; yeni kayıtlar bu alan adını almaz.
    const deletedEmail = await pickDeletedEmail(client, userCode);
    const anonymized = await client.query(
      `
        UPDATE users
        SET full_name = $2, email = $3, login_name = NULL, phone_number = NULL, password_hash = $4,
            email_verification_code_hash = NULL, email_verification_expires_at = NULL,
            password_reset_token_hash = NULL, password_reset_expires_at = NULL,
            is_active = FALSE, role = 'individual', deleted_at = NOW(), updated_at = NOW()
        WHERE user_code = $1 AND deleted_at IS NULL AND role <> 'super_user'
        RETURNING user_code
      `,
      [userCode, DELETED_USER_NAME, deletedEmail, unusablePasswordHash()],
    );
    if (!anonymized.rows?.[0]) {
      // Satır bu arada silindi / süper kullanıcı oldu.
      const again = await client.query('SELECT role, deleted_at FROM users WHERE user_code = $1', [userCode]);
      if (again.rows?.[0]?.role === 'super_user') {
        throw deleteBlocked([superUserBlocker()]);
      }
      throw accountDeleted();
    }

    // 7. Kapsam YENİDEN okunur: kilitler alınırken biri eklendiyse (eşzamanlı onay / üyelik) baştan denenir.
    const after = await readScope(client, userCode, user.id);
    if (scopeGrew(after, scope)) {
      return { retry: true };
    }

    // 8. Engeller (kilitler altında). Önce eş yöneticilerin hesap satırları paylaşımlı kilitlenir (devam eden pasifleştirme / silme sonucu beklenir).
    await lockPeerManagerUsers(client, userCode, after.managedSiteCodes);
    const lastManagerSites = await findLastManagerSites(client, userCode);
    if (lastManagerSites.length > 0) {
      throw deleteBlocked(lastManagerSites.map(lastSiteManagerBlocker));
    }

    const summary = {};

    // 9. Daire üyelikleri + yönetici devri (deleteApartmentMember ile aynı kurallar: gösterge / daire yöneticisi devri, PIN temizliği).
    const removedMemberships = await client.query('DELETE FROM apartment_memberships WHERE user_code = $1 RETURNING apartment_id, role', [userCode]);
    const roleByApartment = new Map((removedMemberships.rows ?? []).map((row) => [num(row.apartment_id), row.role]));
    const legacyApartmentIds = [];
    for (const apartment of after.apartments) {
      const legacy = apartment.resident_user_code === userCode;
      if (legacy) {
        legacyApartmentIds.push(apartment.id);
      }
      if (legacy || roleByApartment.get(apartment.id) === 'APARTMENT_ADMIN') {
        await handOverApartmentResident(client, apartment.id, userCode, { indicatorOwnedByRemoved: legacy });
      }
    }
    if (legacyApartmentIds.length > 0) {
      // Eski tekil sakin göstergesinin iletişim e-postası bu kullanıcıya aitti.
      await client.query('UPDATE apartments SET resident_email = NULL WHERE id = ANY($1::BIGINT[])', [legacyApartmentIds]);
    }
    summary.apartment_memberships = removedMemberships.rowCount ?? 0;

    // 10. Site yöneticiliği ve site üyelikleri.
    const removedManagerLinks = await client.query('DELETE FROM site_manager_sites WHERE manager_user_code = $1', [userCode]);
    const removedSiteMemberships = await client.query('DELETE FROM site_memberships WHERE user_code = $1', [userCode]);
    summary.site_links = (removedManagerLinks.rowCount ?? 0) + (removedSiteMemberships.rowCount ?? 0);

    // 11. Katılım talepleri, davet jetonları, yönetici davetleri.
    await client.query('DELETE FROM join_requests WHERE user_code = $1', [userCode]);
    await client.query(
      'UPDATE site_join_tokens SET is_active = FALSE, revoked_at = COALESCE(revoked_at, NOW()) WHERE created_by_user_code = $1 AND is_active = TRUE',
      [userCode],
    );
    await client.query('DELETE FROM site_manager_invitations WHERE invited_by_user_code = $1', [userCode]);
    // Bu kullanıcının ESKİ adresine gelen davetler: adres tombstone adresiyle değişir, bekleyenler iptal edilir (yeniden kayıtta eski davet kullanılamaz).
    await client.query(
      `
        UPDATE site_manager_invitations
        SET email = $2, full_name = NULL, status = CASE WHEN status = 'PENDING' THEN 'REVOKED' ELSE status END
        WHERE LOWER(email) = LOWER($1)
      `,
      [user.email, deletedEmail],
    );

    // 12. Karekod / misafir geçişi / kapı izinleri / geçiş kayıtları.
    const removedQr = await client.query('DELETE FROM qr_access_tokens WHERE user_code = $1', [userCode]);
    const passes = await client.query(
      'UPDATE guest_passes SET is_active = FALSE, title = $2 WHERE created_by_user_code = $1 RETURNING is_active',
      [userCode, DELETED_GUEST_PASS_TITLE],
    );
    await client.query('DELETE FROM door_access_overrides WHERE user_code = $1', [userCode]);
    await client.query(
      'UPDATE door_access_logs SET user_name = $2, ip_address = NULL WHERE user_code = $1',
      [userCode, DELETED_USER_NAME],
    );
    summary.qr_tokens = removedQr.rowCount ?? 0;
    summary.guest_passes = passes.rowCount ?? 0;

    // 13. Duyuru: okundu kayıtları, bekleyen e-posta kuyruğu girdileri ve adres özetleri (kişi hesaptan kopmadan ÖNCE: user_code ile bağlanır).
    const recipients = await client.query(
      `
        UPDATE announcement_recipients r
        SET read_at = NULL, email = NULL, email_hash = NULL, email_next_at = NULL,
            email_status = CASE WHEN r.email_status = 'pending' THEN 'none' ELSE r.email_status END,
            email_claimed_at = CASE WHEN r.email_status = 'pending' THEN NULL ELSE r.email_claimed_at END
        FROM site_people sp
        WHERE sp.id = r.person_id AND sp.user_code = $1
          AND (r.read_at IS NOT NULL OR r.email IS NOT NULL OR r.email_hash IS NOT NULL OR r.email_status = 'pending')
      `,
      [userCode],
    );
    await client.query('DELETE FROM notification_preferences WHERE user_code = $1', [userCode]);
    summary.announcement_rows = recipients.rowCount ?? 0;
    // Telefon bildirimi (Faz 3b-B): cihaz jetonları + bildirim kuyruğu satırları AYNI işlemde (satır kimliksizleştiği için CASCADE çalışmaz; tablo yoksa atlanır).
    const pushSummary = await deletePushDataForUser(client, userCode);
    summary.push_devices = num(pushSummary?.devices ?? 0);
    summary.push_outbox = num(pushSummary?.outbox ?? 0);
    // İş takibi (042): kullanıcıya atanmış AÇIK talepler atamasız kalır (+ iç olay); talepler / yorumlar silinmez, kullanıcı satırı tombstone olarak kalır. Tablo yoksa atlanır.
    const releasedWorkItems = await releaseAssignedWorkItems(client, userCode);
    if (releasedWorkItems > 0) summary.work_items_released = releasedWorkItems;
    // Rezervasyon ve konsiyerj (043): gelecekteki beklemede / onaylandi rezervasyonlar ve acik konsiyerj talepleri AYNI islemde iptal edilir (gecmis kayitlar kalir). Tablo yoksa atlanir.
    const releasedReservations = await releaseUserReservations(client, userCode);
    if (releasedReservations.reservations > 0) summary.reservations_cancelled = releasedReservations.reservations;
    if (releasedReservations.requests > 0) summary.concierge_cancelled = releasedReservations.requests;
    // Anket ve oylama (044): oylar KALIR, hesap bagi koparilir (anonimlesir); actigi anketlerde created_by NULL. Kullanici satiri tombstone oldugu icin FK SET NULL kendiliginden calismaz. Tablo yoksa atlanir.
    const surveyData = await anonymizeUserSurveyData(client, userCode);
    if (surveyData.votes > 0) summary.survey_votes_anonymized = surveyData.votes;
    if (surveyData.surveys > 0) summary.surveys_unlinked = surveyData.surveys;
    // Aidat hatırlatma kuyruğu (Faz 4b): kişiye bağlı kalemlerdeki düz e-posta adresi + özet silinir, bekleyenler 'resolved' olur (gönderilmez). Kişi satırının hesap bağlantısı
    // (site_people.user_code) bu adımdan SONRA (15) kopar; bu yüzden burada eşleşir.
    summary.reminder_rows = await clearReminderItems(client, userCode);

    // 14. Açık site başvurusu geri çekilir (iptal akışıyla aynı yön: kullanıcı satırı elde -> başvuru satırı).
    const pending = await client.query(
      `SELECT id, block_count, apartment_count, door_count FROM site_applications WHERE applicant_user_code = $1 AND status = 'pending' ORDER BY id FOR UPDATE`,
      [userCode],
    );
    for (const application of pending.rows ?? []) {
      await client.query(
        `UPDATE site_applications SET status = 'cancelled', decided_at = NOW(), updated_at = NOW() WHERE id = $1`,
        [application.id],
      );
      await recordAudit(
        client,
        {
          actor: SYSTEM_ACTOR,
          action: 'site_application.cancelled',
          targetType: 'site_application',
          targetId: String(application.id),
          details: {
            block_count: num(application.block_count),
            apartment_count: num(application.apartment_count),
            door_count: num(application.door_count),
            reason: 'account_deleted',
          },
        },
        { inTransaction: true },
      );
    }
    summary.applications_cancelled = (pending.rows ?? []).length;

    // 15. CRM kişi kayıtları (silme tetikleyicisiyle aynı yön ve aynı sonuç): kişi pasifleşir, hesaptan kopar, güncel ilişkiler biter, araçlar pasifleşir.
    // Hesaptaki telefon / e-posta KOPYALANMAZ (yalnız ad; CRM_KEEP_NAME). Kayıtlar silinmez (yasal saklama; hukuk onayına tabi).
    await bestEffort(client, 'person_audit', () =>
      client.query(
        `
          INSERT INTO audit_log (actor_name, actor_role, action, site_code, target_type, target_id, details)
          SELECT 'Sistem', 'system', 'person.deactivated', sp.site_code, 'person', sp.id::text,
                 jsonb_build_object('reason', 'account_deleted', 'auto', TRUE)
          FROM site_people sp
          WHERE sp.user_code = $1 AND sp.is_active
        `,
        [userCode],
      ),
    );
    await client.query(
      `
        UPDATE apartment_residencies r
        SET is_current = FALSE, move_out_date = COALESCE(r.move_out_date, CURRENT_DATE), updated_at = NOW()
        FROM site_people sp
        WHERE r.person_id = sp.id AND sp.user_code = $1 AND r.is_current
      `,
      [userCode],
    );
    await client.query(
      'UPDATE vehicles v SET is_active = FALSE FROM site_people sp WHERE v.person_id = sp.id AND sp.user_code = $1 AND v.is_active',
      [userCode],
    );
    const keepName = CRM_KEEP_NAME && typeof user.full_name === 'string' && user.full_name.trim() !== '' ? user.full_name : DELETED_USER_NAME;
    const people = await client.query(
      `
        UPDATE site_people
        SET full_name = ${CRM_KEEP_NAME ? "COALESCE(NULLIF(btrim(full_name), ''), $2)" : '$2'},
            email = NULL, is_active = FALSE, user_code = NULL, updated_at = NOW()
        WHERE user_code = $1
      `,
      [userCode, keepName],
    );
    summary.people_unlinked = people.rowCount ?? 0;

    // 16. Ad / e-posta anlık görüntüleri ve adres tabanlı kayıtlar.
    await client.query('DELETE FROM email_verifications WHERE LOWER(email) = LOWER($1)', [user.email]);
    await client.query('DELETE FROM pending_registrations WHERE LOWER(email) = LOWER($1)', [user.email]);
    // audit_log'a DOKUNULMAZ: denetim kaydı yalnızca EKLENİR (platform değişmezi; bkz. audit_service.js ve test/platform_schema.test.js). Eski
    // satırlardaki actor_name anlık görüntüsü güvenlik / yasal saklama gerekçesiyle kalır ve YALNIZ süper kullanıcı okur (GET /admin/audit-log).
    // module_requests ise site yöneticilerinin de gördüğü bir listedir: oradaki ad anlık görüntüleri kimliksizleştirilir.
    await client.query('UPDATE module_requests SET requested_by_name = $2 WHERE requested_by = $1 AND requested_by_name IS DISTINCT FROM $2', [userCode, DELETED_USER_NAME]);
    await client.query('UPDATE module_requests SET decided_by_name = $2 WHERE decided_by = $1 AND decided_by_name IS DISTINCT FROM $2', [userCode, DELETED_USER_NAME]);
    await client.query('UPDATE ota_update_jobs SET requested_by_email = NULL WHERE requested_by_user_code = $1 AND requested_by_email IS NOT NULL', [userCode]);
    await client.query('DELETE FROM account_data_exports WHERE user_code = $1', [userCode]);

    // 17. Kimliksiz denetim kaydı (ad / e-posta / telefon YOK; yalnız önceki rol ve sayılar).
    await recordAudit(
      client,
      {
        actor: SYSTEM_ACTOR,
        action: 'account.deleted',
        targetType: 'user',
        targetId: String(userCode),
        details: { previous_role: user.role, ...summary },
      },
      { inTransaction: true },
    );

    await client.query('COMMIT');
    committed = true;
    return {
      done: {
        userCode,
        previousEmail: user.email,
        previousName: user.full_name,
        previousLoginName: user.login_name,
        siteCodes: after.siteCodes,
        deviceIds: scope.deviceIds,
        summary,
      },
    };
  } finally {
    if (began && !committed) {
      try {
        await client.query('ROLLBACK');
      } catch (_rollbackError) {
        // bağlantı zaten kopmuş olabilir; asıl hata yukarıda fırlatılır
      }
    }
    client.release();
  }
}

const isRetryableDbError = (error) => error?.code === '40P01' || error?.code === '40001';

/**
 * Hesabı tek işlemde kimliksizleştirir (parola doğrulaması ÇAĞIRANDA yapılır). Eşzamanlı çift silme: ikincisi küresel kilidi bekler, sonra
 * 401 ACCOUNT_DELETED alır. Dönen nesne silme sonrası işler içindir (e-posta, anahtar döndürme); istemciye gitmez.
 */
export async function performAccountDeletion(userCode) {
  let deadlockRetried = false;
  for (let attempt = 1; attempt <= MAX_SCOPE_ATTEMPTS; ) {
    try {
      const outcome = await runAttempt(userCode);
      if (outcome.done) {
        return outcome.done;
      }
      attempt += 1; // kapsam büyüdü: baştan
    } catch (error) {
      if (isRetryableDbError(error) && !deadlockRetried) {
        deadlockRetried = true; // nadir 40P01: TEK sefer baştan (sayaç artmaz)
        continue;
      }
      throw error;
    }
  }
  throw accountBusy();
}

/**
 * Silinen kullanıcının önbellekteki yerel kontrol anahtarı kapıyı açmaya devam etmesin diye cihaz ve site anahtarlarını döndürür; BAŞARISIZ olanlar
 * turlar halinde yeniden denenir (ilk tur hemen, sonra accountHooks.rotationBackoffMs kadar bekleyerek: 1 / 5 / 20 sn -> en çok 4 deneme, toplam <= 26 sn bekleme).
 * Tüm turlar tükenip hâlâ döndürülemeyen hedef varsa: kimliksiz denetim satırı `account.key_rotation_failed` (yalnız cihaz / site SAYILARI) + errorId'li hata günlüğü
 * (yönetici o kullanıcıya ait anahtarın geçerli kalabildiğini görsün). Asla fırlatmaz (silme zaten tamamlanmıştır). @returns {Promise<{ failedDevices: number, failedSites: number }>}
 */
export async function rotateKeysWithRetry(done, hooks = accountHooks) {
  const targets = [];
  if (done.deviceIds.length > 0) {
    targets.push({ kind: 'device', count: done.deviceIds.length, run: () => hooks.rotateTokensForDevices({ deviceIds: done.deviceIds, reason: 'account_deleted', throwOnError: true }) });
  }
  for (const siteCode of done.siteCodes) {
    targets.push({ kind: 'site', count: 1, run: () => hooks.rotateTokensForSite({ siteCode, reason: 'account_deleted', throwOnError: true }) });
  }
  const delays = Array.isArray(hooks.rotationBackoffMs) ? hooks.rotationBackoffMs : [];
  let pending = targets;
  for (let round = 0; round <= delays.length && pending.length > 0; round += 1) {
    if (round > 0) {
      await hooks.sleep(delays[round - 1]);
    }
    const failed = [];
    for (const target of pending) {
      try {
        await target.run();
      } catch (_error) {
        failed.push(target); // asıl hata ayrıntısı döndürücünün kendi günlüğünde (yalnız kod); burada kişisel veri / ileti yok
      }
    }
    pending = failed;
  }
  if (pending.length === 0) {
    return { failedDevices: 0, failedSites: 0 };
  }
  const failedDevices = pending.filter((target) => target.kind === 'device').reduce((sum, target) => sum + target.count, 0);
  const failedSites = pending.filter((target) => target.kind === 'site').length;
  const errorId = newErrorId();
  // eslint-disable-next-line no-console
  console.error(`[account] yerel kontrol anahtari dondurulemedi (errorId=${errorId}) cihaz=${failedDevices} site=${failedSites} deneme=${delays.length + 1}`);
  try {
    await hooks.recordRotationFailure(done.userCode, { failed_device_count: failedDevices, failed_site_count: failedSites, attempts: delays.length + 1, error_id: errorId });
  } catch (error) {
    // eslint-disable-next-line no-console
    console.error('[account] anahtar dondurme denetim satiri yazilamadi:', error?.code || error?.name || 'error');
  }
  return { failedDevices, failedSites };
}

function scheduleAfterDeletion(done) {
  const hooks = accountHooks;
  hooks.background(async () => {
    clearAccountLocks({ email: done.previousEmail, loginName: done.previousLoginName, userCode: done.userCode });
    // Erişimi sona eren kullanıcının önbellekteki yerel kontrol anahtarıyla açma yapamaması için ilgili cihazların anahtarı döndürülür (yeniden denemeli; asla fırlatmaz).
    await rotateKeysWithRetry(done, hooks);
    // Eski adrese bilgilendirme: silme bu gönderimden bağımsızdır; adres / ad log'a yazılmaz.
    if (isDeliverableEmail(done.previousEmail) && hooks.smtpConfigured()) {
      try {
        await hooks.sendDeletedEmail({ to: done.previousEmail, fullName: done.previousName, deletedAt: new Date() });
      } catch (error) {
        // eslint-disable-next-line no-console
        console.error('[account] silme bildirimi gonderilemedi:', error?.code || error?.name || 'error');
      }
    }
  });
}

/**
 * POST /me/account-deletion gövde { current_password, confirm: true } -> { deleted: true }.
 * Sıra: onay (400) -> parola (400/429) -> silme (409 engel / 401 zaten silinmiş).
 */
export async function requestAccountDeletion({ authUser, body }) {
  const userCode = userCodeOf(authUser);
  if (userCode === null) {
    throw accountDeleted();
  }
  const input = plainObject(body);
  if (input.confirm !== true) {
    throw confirmRequired();
  }
  await verifyCurrentPassword({ userCode, currentPassword: input.current_password });
  const done = await performAccountDeletion(userCode);
  scheduleAfterDeletion(done);
  return { deleted: true };
}
