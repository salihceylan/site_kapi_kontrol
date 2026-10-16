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
import { verifyCurrentPassword } from './account_password_guard.js';
import { recordAudit } from './audit_service.js';
import { getMyFinance } from './finance_read_service.js';
import { syncUserPeopleSafe } from './people_sync.js';

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
  'Yönetici olarak yaptığınız işlemlerin içeriği (duyuru, finans kayıtları, tanımlar) ve sistem denetim günlükleri: site yönetiminin / platformun kaydı olduğu için dışarıda bırakılmıştır.',
  'Finans ekstresi "Borcum" ekranındaki görünümle aynıdır: her daire için son 30 hareket; yönetici açıklamaları ve işlemi yapan kişinin adı çıkarılmıştır. Tam defter site yönetiminin kaydıdır.',
]);

// ---------------------------------------------------------------------------------------------------------------
// Hız sınırı (kullanıcı başına 24 saatte 3)
// ---------------------------------------------------------------------------------------------------------------

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
    const user = await client.query('SELECT deleted_at FROM users WHERE user_code = $1 LIMIT 1', [userCode]);
    if (!user.rows?.[0] || user.rows[0].deleted_at) {
      throw accountDeleted();
    }
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
  notificationPreferences: `
    SELECT email_announcements, push_announcements, updated_at FROM notification_preferences WHERE user_code = $1 LIMIT 1
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

const CONSENT_KEYS = ['id', 'document_id', 'version', 'accepted_at', 'source'];

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
    const notificationRow = (await q(SQL.notificationPreferences))[0] ?? null;
    const announcements = await bounded('announcements_received', SQL.announcements, EXPORT_ROW_LIMITS.announcements_received);
    const applications = await bounded('site_applications', SQL.siteApplications, EXPORT_ROW_LIMITS.site_applications);
    const guestPasses = await bounded('guest_passes', SQL.guestPasses, EXPORT_ROW_LIMITS.guest_passes);
    const doorEvents = await bounded('door_events', SQL.doorEvents, EXPORT_ROW_LIMITS.door_events);
    const joinRequests = await bounded('join_requests', SQL.joinRequests, EXPORT_ROW_LIMITS.join_requests);
    const doorPermissions = await q(SQL.doorPermissions);
    const qrRequests = await bounded('qr_requests', SQL.qrRequests, EXPORT_ROW_LIMITS.qr_requests);
    const devices = await q(SQL.devices);

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
      notification_preferences: notificationRow
        ? {
            email_announcements: notificationRow.email_announcements,
            push_announcements: notificationRow.push_announcements,
            updated_at: notificationRow.updated_at,
          }
        : {},
      announcements_received: withIds(announcements),
      finance_statements: finance.items ?? [],
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
  'people_records',
  'vehicles',
  'devices',
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
  // Denetim: KİM + ne zaman + boyut; ad / e-posta yazılmaz (yalnız user_code; audit_log değişmezdir, kişisel veri biriktirilmez). Hata dışa aktarmayı bozmaz.
  audit: (userCode, details) =>
    recordAudit(pool, { actor: { userCode }, action: 'account.data_exported', targetType: 'user', targetId: String(userCode), details }),
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
