import { pool } from '../db.js';
import { sendApartmentCredentialsEmail } from '../mailer.js';
import { createUser } from './user_service.js';
import { hashPassword } from '../security/password_hashing.js';
import { clearAccountLocks } from '../middlewares/login_throttle.js';
import { recordAudit } from '../modules/audit_service.js';
import { INTERNAL_EMAIL_SUFFIX } from '../modules/people_sync_sql.js';
import { deletePushDataForUser } from '../modules/push_devices.js';
import {
  apartmentBaseLoginName,
  apartmentResidentFullName,
  generateApartmentPin,
  generateInternalApartmentEmail,
} from '../utils/helpers.js';

// Daire PIN'i (KVKK m.12, migration 051): PIN yalnız users.password_hash'te bcrypt özeti olarak saklanır ve girişte YALNIZ o özetle doğrulanır.
// Okunabilir kopyası TUTULMAZ: PIN yalnız oluşturulduğu / sıfırlandığı yanıtta bir kez döner (`issued_pin_code` -> mapApartmentRow.resident_pin_code)
// ve sakinin e-posta adresi varsa bir kez e-postalanır. apartments.resident_pin_issued yalnız "göstergedeki hesabın parolası yönetimin verdiği
// PIN'dir" işaretidir (sırrın hiçbir türevini taşımaz); apartments.resident_pin_code eski uyumluluk için durur ama HER ZAMAN NULL'dır.

/** Daire satırının API'ye giden alanları (mapApartmentRow). Düz PIN sütunu SEÇİLMEZ; yalnız işaret ve "PIN sıfırlanabilir mi" (dahili hesap). */
export const APARTMENT_ROW_SELECT_SQL = `
  SELECT
    a.id,
    a.site_code,
    a.block_id,
    b.block_name,
    a.unit_label,
    a.sort_order,
    a.is_active,
    a.resident_user_code,
    u.full_name AS resident_full_name,
    u.login_name AS resident_login_name,
    a.resident_email,
    a.resident_pin_issued,
    (u.user_code IS NOT NULL AND u.deleted_at IS NULL AND LOWER(u.email) LIKE '%${INTERNAL_EMAIL_SUFFIX}') AS resident_pin_resettable,
    u.phone_number AS resident_phone_number,
    u.is_active AS resident_is_active,
    a.created_at
  FROM apartments a
  INNER JOIN site_blocks b ON b.id = a.block_id
  LEFT JOIN users u ON u.user_code = a.resident_user_code
`;

/** Eski "Bilgileri Gönder" ucu (send-credentials) için 409 iletisi: PIN artık sonradan okunup gönderilemez. */
export const APARTMENT_PIN_NOT_STORED_MESSAGE =
  "PIN güvenlik gereği saklanmaz; yalnız oluşturulurken bir kez gösterilir. Unutulduysa uygulamayı güncelleyip Daireler ekranından PIN'i sıfırlayın.";

/** PIN sıfırlamanın 409 iletileri (rota yanıtı yalnız bu sabitlerden kurulur; error.message istemciye taşınmaz). */
export const APARTMENT_PIN_ERROR_MESSAGES = Object.freeze({
  APARTMENT_PIN_NO_ACCOUNT: 'Bu dairede daire hesabı yok; önce sakini ekleyin.',
  APARTMENT_PIN_RESET_NEEDS_SUPER:
    'Sakin şifresini kendisi belirlemiş ve dairede kayıtlı e-posta adresi yok. Bu durumda PIN\'i yalnız süper kullanıcı sıfırlayabilir.',
  APARTMENT_PIN_NOT_RESETTABLE:
    'Bu dairenin sakini kendi hesabıyla giriş yapıyor; şifresini yönetici değiştiremez. Sakin giriş ekranındaki "Şifremi Unuttum?" bağlantısıyla yenileyebilir.',
});

function apartmentPinError(code) {
  const error = new Error(APARTMENT_PIN_ERROR_MESSAGES[code]);
  error.statusCode = 409;
  error.code = code;
  error.expose = true;
  return error;
}

export async function ensureUniqueLoginName({
  db,
  desiredLoginName,
  siteCode,
  excludeUserCode = null,
}) {
  let attempt = 0;

  while (attempt < 100) {
    const candidate = attempt === 0
      ? desiredLoginName
      : `${desiredLoginName}_${attempt + 1}`;
    const existing = await db.query(
      `
        SELECT user_code
        FROM users
        WHERE LOWER(login_name) = LOWER($1)
        LIMIT 1
      `,
      [candidate],
    );
    if (
      existing.rowCount === 0 ||
      (
        excludeUserCode != null &&
        Number(existing.rows[0]?.user_code ?? 0) === Number(excludeUserCode)
      )
    ) {
      return candidate;
    }
    attempt += 1;
  }

  throw new Error('APARTMENT_LOGIN_GENERATION_FAILED');
}

export async function generateUniqueApartmentLoginName({
  db,
  blockName,
  sortOrder,
  siteCode,
  excludeUserCode = null,
}) {
  const baseLoginName = apartmentBaseLoginName({ siteCode, blockName, sortOrder });
  return ensureUniqueLoginName({
    db,
    desiredLoginName: baseLoginName,
    siteCode,
    excludeUserCode,
  });
}

export async function createApartmentResidentAccount({
  apartmentId,
  siteCode,
  blockName,
  unitLabel,
  sortOrder,
  db,
}) {
  const loginName = await generateUniqueApartmentLoginName({
    db,
    blockName,
    sortOrder,
    siteCode,
  });
  const pinCode = generateApartmentPin();
  const internalEmail = generateInternalApartmentEmail({
    loginName,
    apartmentId,
    siteCode,
  });
  const createdUser = await createUser({
    fullName: apartmentResidentFullName({ blockName, unitLabel }),
    email: internalEmail,
    loginName,
    role: 'apartment_owner',
    isActive: true,
    phoneNumber: null,
    password: pinCode,
    db,
  });

  // PIN düz metin SAKLANMAZ (yalnız users.password_hash); çağıran dönen PIN'i bir kez iletir.
  await db.query(
    `
      UPDATE apartments
      SET
        resident_user_code = $1,
        resident_pin_issued = TRUE,
        resident_pin_code = NULL,
        is_active = TRUE
      WHERE id = $2
    `,
    [Number(createdUser.id), apartmentId],
  );
  return { userCode: Number(createdUser.id), pinCode };
}

export async function ensureSiteApartmentResidents(_siteCode, _db = pool) {
  // ARTIK KUKLA/SAHTE KULLANICI OLUŞTURULMAZ.
  // Daireler boş olarak açılır; kullanıcılar üyelik sistemiyle eklenir veya atanır.
  return;
}

export async function provisionApartmentResident({
  apartmentId,
  fullName,
  loginName,
  password,
  email,
  phoneNumber,
  isActive,
  db = null,
}) {
  // db verilirse (çağıranın açık transaction'ı) BEGIN/COMMIT/release çağıranındır: böylece sakin hesabı açma, CRM kaydıyla AYNI
  // transaction'da yapılabilir (sonraki adım düşerse hesap da geri alınır). Verilmezse eski davranış (kendi bağlantısı/transaction'ı).
  const ownClient = db === null;
  const client = ownClient ? await pool.connect() : db;
  // Bu çağrıda yeni hesap açıldıysa verilen PIN (yanıtta BİR KEZ döner; saklanmaz). Mevcut sakin düzenlemesinde null.
  let issuedPinCode = null;
  try {
    if (ownClient) {
      await client.query('BEGIN');
    }
    const apartmentResult = await client.query(
      `
        SELECT
          a.id,
          a.site_code,
          a.resident_user_code,
          a.resident_email,
          b.block_name,
          a.unit_label,
          a.sort_order
        FROM apartments a
        INNER JOIN site_blocks b ON b.id = a.block_id
        WHERE a.id = $1
        LIMIT 1
      `,
      [apartmentId],
    );
    if (apartmentResult.rowCount === 0) {
      throw new Error('APARTMENT_NOT_FOUND');
    }

    const apartment = apartmentResult.rows[0];

    let userCode = apartment.resident_user_code == null
      ? null
      : Number(apartment.resident_user_code);
    const finalLoginName = loginName
      ? await ensureUniqueLoginName({
          db: client,
          desiredLoginName: loginName,
          siteCode: Number(apartment.site_code),
          excludeUserCode: userCode,
        })
      : await generateUniqueApartmentLoginName({
          db: client,
          blockName: apartment.block_name,
          sortOrder: Number(apartment.sort_order),
          siteCode: Number(apartment.site_code),
          excludeUserCode: userCode,
        });
    const internalEmail = generateInternalApartmentEmail({
      loginName: finalLoginName,
      apartmentId: Number(apartment.id),
      siteCode: Number(apartment.site_code),
    });
    const residentEmail = email === undefined
      ? apartment.resident_email
      : email;

    if (userCode == null) {
      // Yeni sakin olusturulurken 4 haneli sayisal sifre ZORUNLUDUR. (Mevcut sakin duzenlemede sifre bos
      // gelebilir ve "degistirme" sayilir; dogrulayici bu ayrimi bilemedigi icin kurali burada uygular.)
      if (!/^\d{4}$/.test(String(password ?? '').trim())) {
        const passwordError = new Error('Sifre 4 haneli sayisal olmali.');
        passwordError.statusCode = 400;
        passwordError.code = 'APARTMENT_PASSWORD_REQUIRED';
        throw passwordError;
      }
      const createdUser = await createUser({
        fullName: fullName || apartmentResidentFullName({
          blockName: apartment.block_name,
          unitLabel: apartment.unit_label,
        }),
        email: internalEmail,
        loginName: finalLoginName,
        role: 'apartment_owner',
        isActive,
        phoneNumber,
        password,
        db: client,
      });
      userCode = Number(createdUser.id);
      // PIN düz metin SAKLANMAZ (createUser onu users.password_hash'e bcrypt ile yazdı); yalnız "yönetimin verdiği PIN" işareti kurulur.
      await client.query(
        `
          UPDATE apartments
          SET
            resident_user_code = $1,
            resident_email = $2,
            resident_pin_issued = TRUE,
            resident_pin_code = NULL,
            is_active = $3
          WHERE id = $4
        `,
        // Yeni hesabın iletişim e-postası YALNIZ bu istekten gelir: dairede kalmış eski bir adres (önceki sakinin) kullanılmaz,
        // aksi halde yeni hesabın PIN'i eski sakine e-postalanırdı (inceleme P2).
        [userCode, email === undefined ? null : email, isActive, apartmentId],
      );
      issuedPinCode = String(password).trim();
    } else {
      // Kimlik (ad/e-posta/kullanici adi/aktiflik) YALNIZCA dahili (@ahbu.local) daire hesabinda guncellenir.
      // Uyelik sistemiyle gelen gercek kullanicinin (e-postayla kayitli) e-postasi/giris adi ezilmez;
      // onun icin yalnizca apartments.is_active / resident_email guncellenir.
      const existingUserRes = await client.query(
        `SELECT email FROM users WHERE user_code = $1 AND deleted_at IS NULL LIMIT 1`,
        [userCode],
      );
      const existingEmail = String(existingUserRes.rows?.[0]?.email ?? '').toLowerCase();
      const isInternalAccount = existingUserRes.rowCount > 0 && existingEmail.endsWith('@ahbu.local');
      if (isInternalAccount) {
        await client.query(
          `
            UPDATE users
            SET
              full_name = $1,
              email = $2,
              login_name = $3,
              phone_number = $4,
              is_active = $5
            WHERE user_code = $6 AND deleted_at IS NULL
          `,
          [fullName, internalEmail, finalLoginName, phoneNumber, isActive, userCode],
        );
      }
      await client.query(
        `
          UPDATE apartments
          SET
            resident_email = $1,
            is_active = $2
          WHERE id = $3
        `,
        [residentEmail, isActive, apartmentId],
      );
    }

    const finalResult = await client.query(`${APARTMENT_ROW_SELECT_SQL} WHERE a.id = $1`, [apartmentId]);

    if (ownClient) {
      await client.query('COMMIT');
    }
    const row = finalResult.rows[0];
    return row ? { ...row, issued_pin_code: issuedPinCode } : row;
  } catch (error) {
    if (ownClient) {
      await client.query('ROLLBACK');
    }
    throw error;
  } finally {
    if (ownClient) {
      client.release();
    }
  }
}

export async function resetApartmentResident(apartmentId, db = pool) {
  const client = db === pool ? await pool.connect() : db;
  const isDedicatedClient = db === pool;
  try {
    if (isDedicatedClient) {
      await client.query('BEGIN');
    }

    const aptResult = await client.query(
      // Daire satiri DELETE users'tan ONCE kilitlenir (kilit sirasi: apartments -> users -> CRM kisi kayitlari; 40P01 onleme).
      `SELECT * FROM apartments WHERE id = $1 LIMIT 1 FOR UPDATE`,
      [apartmentId],
    );
    if (aptResult.rowCount === 0) {
      throw new Error('APARTMENT_NOT_FOUND');
    }
    const apt = aptResult.rows[0];

    if (apt.resident_user_code) {
      const userRes = await client.query(
        `SELECT email FROM users WHERE user_code = $1`,
        [apt.resident_user_code],
      );
      if (userRes.rowCount > 0 && userRes.rows[0].email?.endsWith('@ahbu.local')) {
        await client.query(
          `DELETE FROM users WHERE user_code = $1`,
          [apt.resident_user_code],
        );
      }
    }

    const updated = await client.query(
      `
        UPDATE apartments
        SET
          resident_user_code = NULL,
          resident_pin_issued = FALSE,
          resident_pin_code = NULL,
          resident_email = NULL,
          is_active = TRUE
        WHERE id = $1
        RETURNING *
      `,
      [apartmentId],
    );

    if (isDedicatedClient) {
      await client.query('COMMIT');
    }
    return updated.rows[0];
  } catch (error) {
    if (isDedicatedClient) {
      await client.query('ROLLBACK');
    }
    throw error;
  } finally {
    if (isDedicatedClient) {
      client.release();
    }
  }
}

export async function getApartmentCredentialSnapshot(apartmentId) {
  const result = await pool.query(
    `
      SELECT
        a.id,
        a.site_code,
        a.unit_label,
        a.resident_email,
        b.block_name,
        s.name AS site_name,
        u.full_name AS resident_full_name,
        u.login_name AS resident_login_name
      FROM apartments a
      INNER JOIN site_blocks b ON b.id = a.block_id
      INNER JOIN sites s ON s.site_code = a.site_code
      LEFT JOIN users u ON u.user_code = a.resident_user_code
      WHERE a.id = $1
      LIMIT 1
    `,
    [apartmentId],
  );
  return result.rows[0] || null;
}

/**
 * Giriş bilgisi e-postası. PIN SAKLANMADIĞI için yalnız oluşturma / sıfırlama anında, o an üretilen PIN'le (pinCode) gönderilebilir;
 * pinCode verilmezse (eski "Bilgileri Gönder" ucu) APARTMENT_PIN_NOT_STORED fırlatılır: PIN artık sonradan okunup yeniden gönderilemez.
 */
export async function sendApartmentCredentials(apartmentId, { pinCode = null } = {}) {
  const snapshot = await getApartmentCredentialSnapshot(apartmentId);
  if (!snapshot) {
    throw new Error('APARTMENT_NOT_FOUND');
  }
  if (!snapshot.resident_email) {
    throw new Error('APARTMENT_EMAIL_REQUIRED');
  }
  if (!snapshot.resident_login_name) {
    throw new Error('APARTMENT_CREDENTIALS_NOT_READY');
  }
  const pin = String(pinCode ?? '').trim();
  if (!pin) {
    throw new Error('APARTMENT_PIN_NOT_STORED');
  }

  await sendApartmentCredentialsEmail({
    to: snapshot.resident_email,
    residentName: snapshot.resident_full_name || `${snapshot.block_name} ${snapshot.unit_label}`,
    apartmentLabel: `${snapshot.block_name} / ${snapshot.unit_label}`,
    siteName: snapshot.site_name,
    loginName: snapshot.resident_login_name,
    pinCode: pin,
  });
}

/** Test ayarı: PIN e-postasının yanıtı bekletebileceği en uzun süre (ms). Süre dolarsa gönderim arka planda sürer, yanıt beklemez. */
export const apartmentPinMailTuning = { timeoutMs: 8000 };

/**
 * Az önce verilen PIN'i (oluşturma / sıfırlama) sakinin e-posta adresine BİR KEZ gönderir. Dönüş { sent, to }:
 *  - sent true: gönderildi; false: gönderilemedi (SMTP vb.; işlem geri alınmaz); null: e-posta adresi yok (to null) YA DA gönderim
 *    [timeoutMs] içinde bitmedi ve arka planda sürüyor (to dolu; "gönderim sürüyor"). SMTP yavaşken PIN'in tek kopyası yanıtı bekletmez.
 *  - to: gönderimin hedefi (dairenin kayıtlı iletişim e-postası) ya da null.
 * PIN, e-posta adresi ve hata ayrıntısı günlüğe YAZILMAZ (yalnız hata kodu).
 */
export async function sendIssuedApartmentPin(apartmentId, pinCode, { timeoutMs = apartmentPinMailTuning.timeoutMs } = {}) {
  const pin = String(pinCode ?? '').trim();
  if (!pin) {
    return { sent: null, to: null };
  }
  let snapshot;
  try {
    snapshot = await getApartmentCredentialSnapshot(apartmentId);
  } catch (error) {
    // eslint-disable-next-line no-console
    console.error('[apartment] daire PIN e-postasi hazirlanamadi:', error?.code || 'hata');
    return { sent: false, to: null };
  }
  if (!snapshot?.resident_email || !snapshot.resident_login_name) {
    return { sent: null, to: null };
  }
  const sending = sendApartmentCredentialsEmail({
    to: snapshot.resident_email,
    residentName: snapshot.resident_full_name || `${snapshot.block_name} ${snapshot.unit_label}`,
    apartmentLabel: `${snapshot.block_name} / ${snapshot.unit_label}`,
    siteName: snapshot.site_name,
    loginName: snapshot.resident_login_name,
    pinCode: pin,
  }).then(
    () => true,
    (error) => {
      // eslint-disable-next-line no-console
      console.error('[apartment] daire PIN e-postasi gonderilemedi:', error?.code || error?.responseCode || 'hata');
      return false;
    },
  );
  let timer = null;
  const timeout = new Promise((resolve) => {
    timer = setTimeout(() => resolve(null), timeoutMs);
    timer.unref?.();
  });
  const sent = await Promise.race([sending, timeout]);
  clearTimeout(timer);
  return { sent, to: snapshot.resident_email };
}

/**
 * reset-pin yanıt gövdesi (admin ve yönetici uçlarında AYNI; `apartment` alanını rota mapApartmentRow ile ekler).
 *  - delivery 'shown': pin_code yanıtta BİR KEZ; e-posta [sendEmail] ise bir kez gönderilir.
 *  - delivery 'email_only' (sakinin kendi belirlediği parola, yönetici): pin_code YOK (null); e-posta ZORUNLU ([sendEmail]=false yok sayılır).
 * credentials_sent: true gönderildi / false gönderilemedi / null (credentials_email doluysa gönderim sürüyor, boşsa e-posta adresi yok ya da istenmedi).
 */
export async function apartmentPinResetBody(apartmentId, reset, { sendEmail = true } = {}) {
  const emailOnly = reset.delivery === 'email_only';
  const mail = sendEmail || emailOnly ? await sendIssuedApartmentPin(apartmentId, reset.pinCode) : { sent: null, to: null };
  return {
    ok: true,
    pin_code: emailOnly ? null : reset.pinCode,
    pin_delivery: reset.delivery,
    credentials_sent: mail.sent,
    credentials_email: mail.to,
  };
}

/**
 * Daire hesabının PIN'ini sıfırlar (yönetici / süper kullanıcı; "unutulduysa yenileyin"). YALNIZ dahili (@ahbu.local) daire hesabında: kayıtlı
 * kullanıcının (kendi e-postasıyla üye olan sakin) parolasını yönetici değiştiremez (membership_service.changeApartmentMemberPassword ilkesi).
 * Yeni PIN CSPRNG ile üretilir, yalnız users.password_hash'e (BCRYPT_COST) yazılır ve dönüşte BİR KEZ verilir; düz kopyası saklanmaz.
 * Parola özeti değiştiği için hesabın açık oturumları (JWT pv) ve güvenilir cihaz belirteçleri geçersizleşir; giriş kilitleri açılır.
 * Eski PIN'le edinilmiş JWT DIŞI erişim de AYNI işlemde kapanır: hesabın oluşturduğu misafir geçişleri pasif, kapı karekod belirteçleri iptal,
 * telefon bildirimi cihaz kayıtları / kuyruğu silinir (deletePushDataForUser).
 *
 * Teslim kuralı (inceleme P3): PIN'i SAKİN KENDİSİ belirlemişse (resident_pin_issued FALSE) yönetici PIN'i GÖREMEZ: yeni PIN yalnız dairenin
 * kayıtlı iletişim e-postasına gönderilir (delivery 'email_only'; yanıtta PIN yok); e-posta adresi yoksa yalnız süper kullanıcı sıfırlayabilir
 * (yöneticiye 409 APARTMENT_PIN_RESET_NEEDS_SUPER). Yönetimin verdiği PIN (TRUE) ya da süper kullanıcı: PIN bir kez gösterilir ('shown').
 * Kilit sırası: apartments -> users -> misafir geçişi / karekod / bildirim (resetApartmentResident ve yönetici devriyle aynı başlangıç; 40P01 önleme).
 * bcrypt özeti kilit ALINMADAN hesaplanır.
 * @returns {Promise<{ apartment: object, pinCode: string, delivery: 'shown'|'email_only', revoked: object }>}
 */
export async function resetApartmentPin(apartmentId, { actor = null, actorIsSuper = false } = {}) {
  const pinCode = generateApartmentPin();
  const passwordHash = await hashPassword(pinCode);
  const client = await pool.connect();
  let user;
  let row;
  let delivery = 'shown';
  const revoked = { guest_passes: 0, qr_tokens: 0, push_devices: 0, push_outbox: 0 };
  try {
    await client.query('BEGIN');
    const aptRes = await client.query(
      `SELECT id, site_code, resident_user_code, resident_email, resident_pin_issued FROM apartments WHERE id = $1 LIMIT 1 FOR UPDATE`,
      [apartmentId],
    );
    if (aptRes.rowCount === 0) {
      throw new Error('APARTMENT_NOT_FOUND');
    }
    const apt = aptRes.rows[0];
    if (apt.resident_user_code === null || apt.resident_user_code === undefined) {
      throw apartmentPinError('APARTMENT_PIN_NO_ACCOUNT');
    }
    // deleted_at IS NULL: kimliksizleştirilmiş (silinmiş) hesaba gerçek parola özeti yazılmaz (account_users_writers değişmezi).
    const userRes = await client.query(
      `
        UPDATE users
        SET password_hash = $1, updated_at = NOW()
        WHERE user_code = $2 AND deleted_at IS NULL AND LOWER(email) LIKE $3
        RETURNING user_code, login_name, email
      `,
      [passwordHash, Number(apt.resident_user_code), `%${INTERNAL_EMAIL_SUFFIX}`],
    );
    if (userRes.rowCount === 0) {
      throw apartmentPinError('APARTMENT_PIN_NOT_RESETTABLE');
    }
    user = userRes.rows[0];
    // Sakin parolasını kendisi belirlemiş: yönetici yeni PIN'i göremez (yalnız sakinin e-postasına); e-posta yoksa yalnız süper kullanıcı.
    // (Hata fırlarsa ROLLBACK yukarıdaki parola değişikliğini de geri alır.)
    if (apt.resident_pin_issued !== true && !actorIsSuper) {
      if (!String(apt.resident_email ?? '').trim()) {
        throw apartmentPinError('APARTMENT_PIN_RESET_NEEDS_SUPER');
      }
      delivery = 'email_only';
    }
    const userCode = Number(user.user_code);
    await client.query(
      `UPDATE apartments SET resident_pin_issued = TRUE, resident_pin_code = NULL WHERE id = $1`,
      [apartmentId],
    );
    // Eski PIN'le edinilmiş JWT dışı erişim: misafir geçişleri, kapı karekodları, telefon bildirimi kayıtları.
    revoked.guest_passes = Number(
      (await client.query(`UPDATE guest_passes SET is_active = FALSE WHERE created_by_user_code = $1 AND is_active = TRUE`, [userCode])).rowCount ?? 0,
    );
    revoked.qr_tokens = Number(
      (await client.query(
        `UPDATE qr_access_tokens SET is_active = FALSE, revoked_at = NOW() WHERE user_code = $1 AND is_active = TRUE AND revoked_at IS NULL`,
        [userCode],
      )).rowCount ?? 0,
    );
    const push = await deletePushDataForUser(client, userCode);
    revoked.push_devices = push.devices;
    revoked.push_outbox = push.outbox;
    // Kim, hangi dairenin PIN'ini sıfırladı; teslim biçimi ve kapanan erişim SAYILARI (PIN / e-posta YAZILMAZ).
    await recordAudit(
      client,
      {
        actor,
        action: 'apartment.pin_reset',
        siteCode: apt.site_code,
        targetType: 'apartment',
        targetId: apt.id,
        details: { delivery, ...revoked },
      },
      { inTransaction: true },
    );
    row = (await client.query(`${APARTMENT_ROW_SELECT_SQL} WHERE a.id = $1`, [apartmentId])).rows[0];
    await client.query('COMMIT');
  } catch (error) {
    await client.query('ROLLBACK').catch(() => {});
    throw error;
  } finally {
    client.release();
  }
  // Yetkili yeni PIN verdi: hesabın giriş / mevcut parola kilitleri açılır (şifre sıfırlama bağlantısıyla aynı).
  clearAccountLocks({ email: user.email, loginName: user.login_name, userCode: user.user_code });
  // 'email_only': PIN yalnız e-postaya gider; API satırında (resident_pin_code) da YOKTUR.
  return { apartment: { ...row, issued_pin_code: delivery === 'shown' ? pinCode : null }, pinCode, delivery, revoked };
}
