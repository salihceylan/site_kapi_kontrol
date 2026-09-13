import bcrypt from 'bcryptjs';
import { pool } from '../db.js';
import { signAccessToken } from '../jwt.js';
import { sendIndividualVerificationEmail } from '../mailer.js';
import { mapUserRow, normalizeEmail } from '../utils/helpers.js';

/**
 * 4 haneli rastgele sayısal doğrulama kodu üretir (1000 - 9999).
 */
function generate4DigitCode() {
  return Math.floor(1000 + Math.random() * 9000).toString();
}

/**
 * Yeni Bireysel Kullanıcı Kaydı (Self-Service)
 * - Ad, Soyad, E-posta, Şifre alır.
 * - E-posta doğrulanana kadar email_verified = FALSE kalır.
 * - 4 haneli kod üretip kullanıcının e-postasına gönderir.
 */
export async function registerIndividualUser({
  firstName,
  lastName,
  email,
  password,
}) {
  const cleanFirstName = String(firstName || '').trim();
  const cleanLastName = String(lastName || '').trim();
  const cleanEmail = normalizeEmail(email);
  const cleanPassword = String(password || '').trim();

  if (!cleanFirstName || !cleanLastName) {
    throw new Error('Ad ve soyad alanları zorunludur.');
  }
  if (!cleanEmail || !cleanEmail.includes('@')) {
    throw new Error('Geçerli bir e-posta adresi giriniz.');
  }
  if (cleanPassword.length < 6) {
    throw new Error('Şifre en az 6 karakter olmalıdır.');
  }

  const fullName = `${cleanFirstName} ${cleanLastName}`;

  // Mevcut kullanıcı kontrolü
  const existingRes = await pool.query(
    `SELECT user_code, email, email_verified FROM users WHERE LOWER(email) = LOWER($1) LIMIT 1`,
    [cleanEmail],
  );

  let userCode;

  if (existingRes.rowCount > 0) {
    const existing = existingRes.rows[0];
    if (existing.email_verified) {
      const err = new Error('Bu e-posta adresiyle zaten kayıtlı ve doğrulanmış bir hesap bulunmaktadır.');
      err.statusCode = 409;
      throw err;
    }
    // Henüz doğrulanmamışsa şifresini ve adını güncelle
    userCode = existing.user_code;
    const passwordHash = await bcrypt.hash(cleanPassword, 10);
    await pool.query(
      `UPDATE users SET full_name = $1, password_hash = $2, is_active = TRUE, updated_at = NOW() WHERE user_code = $3`,
      [fullName, passwordHash, userCode],
    );
  } else {
    // Yeni kullanıcı oluştur
    const passwordHash = await bcrypt.hash(cleanPassword, 10);
    const insertRes = await pool.query(
      `
        INSERT INTO users (
          full_name,
          email,
          role,
          is_active,
          email_verified,
          approval_status,
          password_hash
        )
        VALUES ($1, $2, 'individual', TRUE, FALSE, 'approved', $3)
        RETURNING user_code
      `,
      [fullName, cleanEmail, passwordHash],
    );
    userCode = insertRes.rows[0].user_code;
  }

  // 4 Haneli Doğrulama Kodu Üret ve Kaydet
  const code = generate4DigitCode();
  const codeHash = await bcrypt.hash(code, 10);

  // Varsa önceki kullanılmamış kodları pasife çek
  await pool.query(
    `UPDATE email_verifications SET is_verified = TRUE WHERE LOWER(email) = LOWER($1) AND is_verified = FALSE`,
    [cleanEmail],
  );

  await pool.query(
    `
      INSERT INTO email_verifications (email, code_hash, attempt_count, is_verified)
      VALUES ($1, $2, 0, FALSE)
    `,
    [cleanEmail, codeHash],
  );

  // E-postayı gönder
  try {
    await sendIndividualVerificationEmail({
      to: cleanEmail,
      fullName,
      code,
    });
  } catch (mailError) {
    console.error('[Mail Gönderim Hatası]:', mailError.message);
    // Mail sunucusu geçici hata verse bile kullanıcı oluşturulur, kullanıcı 'Tekrar Kod Gönder' yapabilir.
  }

  return {
    ok: true,
    message: 'Kayıt başarılı. 4 haneli doğrulama kodunuz e-posta adresinize gönderildi.',
    email: cleanEmail,
  };
}

/**
 * 4 Haneli E-posta Doğrulama Kodu Onaylama
 */
export async function verifyIndividualEmailCode({ email, code }) {
  const cleanEmail = normalizeEmail(email);
  const cleanCode = String(code || '').trim();

  if (!cleanEmail || !cleanCode) {
    throw new Error('E-posta ve doğrulama kodu zorunludur.');
  }
  if (!/^\d{4}$/.test(cleanCode)) {
    throw new Error('Doğrulama kodu 4 haneli sayı olmalıdır.');
  }

  // En son oluşturulan doğrulanmamış kodu bul
  const verifyRes = await pool.query(
    `
      SELECT id, code_hash, attempt_count
      FROM email_verifications
      WHERE LOWER(email) = LOWER($1) AND is_verified = FALSE
      ORDER BY created_at DESC
      LIMIT 1
    `,
    [cleanEmail],
  );

  if (verifyRes.rowCount === 0) {
    const err = new Error('Aktif bir doğrulama kodu bulunamadı. Lütfen yeni kod talep ediniz.');
    err.statusCode = 404;
    throw err;
  }

  const record = verifyRes.rows[0];

  if (record.attempt_count >= 5) {
    const err = new Error('Çok fazla hatalı deneme yapıldı. Güvenliğiniz için lütfen yeni bir kod isteyiniz.');
    err.statusCode = 429;
    throw err;
  }

  const isMatch = await bcrypt.compare(cleanCode, record.code_hash);
  if (!isMatch) {
    await pool.query(
      `UPDATE email_verifications SET attempt_count = attempt_count + 1 WHERE id = $1`,
      [record.id],
    );
    const err = new Error('Girdiğiniz 4 haneli kod hatalıdır.');
    err.statusCode = 400;
    throw err;
  }

  // Kodu doğrulanmış olarak işaretle
  await pool.query(
    `UPDATE email_verifications SET is_verified = TRUE, verified_at = NOW() WHERE id = $1`,
    [record.id],
  );

  // Kullanıcıyı email_verified = TRUE yap
  const userRes = await pool.query(
    `
      UPDATE users
      SET email_verified = TRUE
      WHERE LOWER(email) = LOWER($1)
      RETURNING
        user_code AS id,
        full_name,
        email,
        login_name,
        role,
        is_active,
        email_verified,
        approval_status,
        phone_number,
        created_at
    `,
    [cleanEmail],
  );

  if (userRes.rowCount === 0) {
    const err = new Error('Kullanıcı hesabı bulunamadı.');
    err.statusCode = 404;
    throw err;
  }

  const user = userRes.rows[0];
  const token = signAccessToken(user);

  return {
    ok: true,
    message: 'E-posta adresiniz başarıyla doğrulandı. Hesabınız aktif!',
    token,
    user: mapUserRow(user),
  };
}

/**
 * 4 Haneli E-posta Doğrulama Kodunu Tekrar Gönder
 */
export async function resendIndividualVerificationCode({ email }) {
  const cleanEmail = normalizeEmail(email);
  if (!cleanEmail) {
    throw new Error('E-posta adresi gereklidir.');
  }

  const userRes = await pool.query(
    `SELECT user_code, full_name, email_verified FROM users WHERE LOWER(email) = LOWER($1) LIMIT 1`,
    [cleanEmail],
  );

  if (userRes.rowCount === 0) {
    const err = new Error('Bu e-posta adresine ait bir hesap bulunamadı.');
    err.statusCode = 404;
    throw err;
  }

  const user = userRes.rows[0];
  if (user.email_verified) {
    return {
      ok: true,
      already_verified: true,
      message: 'E-posta adresiniz zaten doğrulanmış. Giriş yapabilirsiniz.',
    };
  }

  // Yeni 4 haneli kod üret
  const code = generate4DigitCode();
  const codeHash = await bcrypt.hash(code, 10);

  // Eski kodları pasife çek
  await pool.query(
    `UPDATE email_verifications SET is_verified = TRUE WHERE LOWER(email) = LOWER($1) AND is_verified = FALSE`,
    [cleanEmail],
  );

  await pool.query(
    `INSERT INTO email_verifications (email, code_hash, attempt_count, is_verified) VALUES ($1, $2, 0, FALSE)`,
    [cleanEmail, codeHash],
  );

  await sendIndividualVerificationEmail({
    to: cleanEmail,
    fullName: user.full_name,
    code,
  });

  return {
    ok: true,
    message: 'Yeni 4 haneli doğrulama kodunuz e-posta adresinize gönderildi.',
  };
}

/**
 * Cihaz Ambalaj Kutusundaki QR Kod / Seri No / UID ile Cihaz Sahiplenme
 */
export async function claimDevice({ userCode, deviceInput }) {
  const code = Number(userCode);
  if (!code || !Number.isInteger(code)) {
    const err = new Error('Kullanıcı oturumu gereklidir.');
    err.statusCode = 401;
    throw err;
  }

  const rawInput = String(deviceInput || '').trim();
  if (!rawInput) {
    const err = new Error('Cihaz QR kodu veya seri numarası boş olamaz.');
    err.statusCode = 400;
    throw err;
  }

  // Kutu QR içeriğini normalize et: örn: "GD-C3-00861A0D5020" -> "00861A0D5020" veya "00:86:1A:0D:50:20" -> "00861A0D5020"
  let cleanUid = rawInput
    .trim()
    .replace(/^https?:\/\/[^\/]+\/(?:device\/)?/i, '')
    .replace(/^GD-[A-Z0-9]+-/i, '')
    .replace(/^DEVICE:/i, '')
    .replace(/[:-]/g, '')
    .trim()
    .toUpperCase();

  // Kullanıcıyı doğrula (user_code veya id ile)
  const userRes = await pool.query(
    `SELECT id, user_code, full_name, email, email_verified FROM users WHERE user_code = $1 OR id = $1 LIMIT 1`,
    [code],
  );
  if (userRes.rowCount === 0) {
    const err = new Error('Kullanıcı bulunamadı.');
    err.statusCode = 404;
    throw err;
  }
  const user = userRes.rows[0];
  if (!user.email_verified) {
    const err = new Error('Cihaz sahiplenmek için önce e-posta adresinizi doğrulamanız gerekmektedir.');
    err.statusCode = 403;
    throw err;
  }

  // Cihazı veritabanında ara
  let devRes = await pool.query(
    `SELECT id, device_uid, hardware_type, gate_name, site_code, owner_user_id, claimed_at
     FROM devices
     WHERE UPPER(device_uid) = $1 
        OR UPPER(device_uid) = $2 
        OR UPPER(REPLACE(REPLACE(device_uid, ':', ''), '-', '')) = $1
     LIMIT 1`,
    [cleanUid, rawInput.toUpperCase()],
  );

  let deviceRow;

  if (devRes.rowCount === 0) {
    // Cihaz veritabanında henüz kayıtlı değilse yeni kayıt oluştur ve sahiplendir
    let detectedHardware = 'esp32_wroom';
    if (rawInput.toUpperCase().includes('C3') || rawInput.toUpperCase().includes('MINI')) {
      detectedHardware = 'esp32_c3';
    }
    const insertDev = await pool.query(
      `INSERT INTO devices (device_uid, hardware_type, owner_user_id, assigned_user_code, claimed_at, qr_reader_enabled)
       VALUES ($1, $2, $3, $4, NOW(), TRUE)
       RETURNING id, device_uid, hardware_type, gate_name, site_code, owner_user_id, claimed_at`,
      [cleanUid, detectedHardware, user.id, user.user_code],
    );
    deviceRow = insertDev.rows[0];
  } else {
    deviceRow = devRes.rows[0];

    // Cihaz başka bir kullanıcı tarafından sahiplenilmiş mi?
    if (deviceRow.owner_user_id && String(deviceRow.owner_user_id) !== String(user.id)) {
      const err = new Error('Bu cihaz zaten başka bir kullanıcı hesabı tarafından sahiplenilmiş. Cihazı devralmak için mevcut sahibinin cihazı serbest bırakması gerekir.');
      err.statusCode = 409;
      throw err;
    }

    if (deviceRow.owner_user_id && String(deviceRow.owner_user_id) === String(user.id)) {
      if (user.role === 'individual' || user.role === 'apartment_owner') {
        await pool.query(
          `UPDATE users SET role = 'site_manager' WHERE id = $1`,
          [user.id],
        );
        user.role = 'site_manager';
      }
      return {
        ok: true,
        role: user.role,
        already_owned: true,
        message: 'Bu cihaz zaten hesabınıza tanımlı.',
        device: deviceRow,
      };
    }

    // Cihazı bu kullanıcıya ata
    const updateRes = await pool.query(
      `UPDATE devices
       SET owner_user_id = $1, assigned_user_code = $2, claimed_at = NOW()
       WHERE id = $3
       RETURNING id, device_uid, hardware_type, gate_name, site_code, owner_user_id, claimed_at`,
      [user.id, user.user_code, deviceRow.id],
    );
    deviceRow = updateRes.rows[0];
  }

  // Cihaz ekleyen/sahiplenen kullanıcı artık Site Yöneticisidir
  if (user.role === 'individual' || user.role === 'apartment_owner') {
    await pool.query(
      `UPDATE users SET role = 'site_manager' WHERE id = $1`,
      [user.id],
    );
    user.role = 'site_manager';
  }

  return {
    ok: true,
    role: user.role,
    message: `Cihaz (${deviceRow.device_uid}) başarıyla hesabınıza bağlandı! Artık bu cihaz ile site ve kapı kurulumu yapabilirsiniz.`,
    device: deviceRow,
  };
}

/**
 * Kullanıcının Sahiplendiği Cihazları Listele
 */
export async function getMyClaimedDevices(userCode) {
  const code = Number(userCode);
  if (!code || !Number.isInteger(code)) {
    return { ok: true, role: 'individual', devices: [] };
  }
  const userRes = await pool.query(
    `SELECT id, user_code, role FROM users WHERE user_code = $1 OR id = $1 LIMIT 1`,
    [code],
  );
  if (userRes.rowCount === 0) {
    return { ok: true, role: 'individual', devices: [] };
  }
  const user = userRes.rows[0];

  const devicesRes = await pool.query(
    `SELECT id, device_uid, hardware_type, gate_name, site_code, owner_user_id, claimed_at, created_at
     FROM devices
     WHERE owner_user_id = $1 OR assigned_user_code = $2
     ORDER BY claimed_at DESC NULLS LAST, id DESC`,
    [user.id, user.user_code],
  );

  // Eğer kullanıcının sahiplendiği cihaz varsa ve rolü individual ise site_manager yap
  if (devicesRes.rowCount > 0 && (user.role === 'individual' || user.role === 'apartment_owner')) {
    await pool.query(
      `UPDATE users SET role = 'site_manager' WHERE id = $1`,
      [user.id],
    );
    user.role = 'site_manager';
  }

  return {
    ok: true,
    role: user.role,
    devices: devicesRes.rows,
  };
}

/**
 * ÜYELİK SİSTEMİ AŞAMA 4: Dinamik Site, Blok ve Daire Kurulumu (Site Sahibi / SITE_OWNER)
 */
export async function setupSiteWithClaimedDevice({
  userCode,
  name,
  city,
  district,
  address,
  blocks,
  doors,
  doorCount = 1,
  deviceUid,
}) {
  const code = Number(userCode);
  if (!code || !Number.isInteger(code)) {
    const err = new Error('Kullanıcı oturumu gereklidir.');
    err.statusCode = 401;
    throw err;
  }

  const siteName = String(name || '').trim();
  if (!siteName) {
    const err = new Error('Site adı zorunludur.');
    err.statusCode = 400;
    throw err;
  }

  // Blok listesini doğrula ve normalize et
  let blockList = Array.isArray(blocks) ? blocks : [];
  if (blockList.length === 0) {
    blockList = [{ name: 'A Blok', apartmentCount: 10 }];
  }

  const normalizedBlocks = blockList.map((b, idx) => {
    const bName = String(b.name || `Blok ${idx + 1}`).trim();
    const aptCount = Math.max(1, parseInt(b.apartmentCount, 10) || 10);
    return {
      name: bName || `Blok ${idx + 1}`,
      apartmentCount: aptCount,
      sortOrder: idx + 1,
    };
  });

  const totalBlockCount = normalizedBlocks.length;
  const totalApartmentCount = normalizedBlocks.reduce((sum, b) => sum + b.apartmentCount, 0);
  const blockApartmentCounts = normalizedBlocks.map(b => b.apartmentCount);

  // Kapı listesini doğrula ve normalize et
  let doorList = [];
  if (Array.isArray(doors) && doors.length > 0) {
    doorList = doors.map((d, idx) => {
      const dName = typeof d === 'object' ? String(d.name || '').trim() : String(d || '').trim();
      return {
        name: dName || `Kapı ${idx + 1}`,
        doorIndex: idx + 1,
      };
    });
  } else {
    const count = Math.max(1, parseInt(doorCount, 10) || 1);
    for (let i = 1; i <= count; i++) {
      doorList.push({ name: `Kapı ${i}`, doorIndex: i });
    }
  }
  const totalDoorCount = doorList.length;

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    // 1. Kullanıcıyı bul
    const userRes = await client.query(
      `SELECT id, user_code, role, full_name, email FROM users WHERE user_code = $1 OR id = $1 LIMIT 1`,
      [code],
    );
    if (userRes.rowCount === 0) {
      const err = new Error('Kullanıcı hesabı bulunamadı.');
      err.statusCode = 404;
      throw err;
    }
    const user = userRes.rows[0];

    // 2. Yeni Siteyi oluştur (Bireysel site sahibi için anında onaylı)
    const siteRes = await client.query(
      `
        INSERT INTO sites (
          name,
          address,
          city,
          district,
          block_count,
          apartment_count,
          door_count,
          block_apartment_counts,
          mqtt_site_id,
          approval_status,
          approved_at,
          feature_qr_enabled,
          feature_remote_open_enabled,
          feature_local_udp_enabled,
          feature_guest_pass_enabled,
          qr_entry_active
        )
        VALUES (
          $1, $2, $3, $4, $5, $6, $7, $8, generate_unique_mqtt_site_id(), 'approved', NOW(),
          TRUE, TRUE, TRUE, TRUE, TRUE
        )
        RETURNING
          site_code AS id,
          name,
          address,
          city,
          district,
          block_count,
          apartment_count,
          door_count,
          approval_status,
          approved_at,
          mqtt_site_id,
          created_at
      `,
      [
        siteName,
        address ? String(address).trim() : null,
        city ? String(city).trim() : null,
        district ? String(district).trim() : null,
        totalBlockCount,
        totalApartmentCount,
        totalDoorCount,
        blockApartmentCounts,
      ],
    );
    const site = siteRes.rows[0];
    const siteCode = Number(site.id);

    // 3. Kullanıcıyı site yöneticisi olarak ekle
    await client.query(
      `
        INSERT INTO site_manager_sites (site_code, manager_user_code)
        VALUES ($1, $2)
        ON CONFLICT (site_code, manager_user_code) DO NOTHING
      `,
      [siteCode, user.user_code],
    );

    // 4. Kullanıcıyı SITE_OWNER rolüyle site_memberships tablosuna ekle
    await client.query(
      `
        INSERT INTO site_memberships (site_code, user_code, role, is_active)
        VALUES ($1, $2, 'SITE_OWNER', TRUE)
        ON CONFLICT (site_code, user_code)
        DO UPDATE SET role = 'SITE_OWNER', is_active = TRUE, updated_at = NOW()
      `,
      [siteCode, user.user_code],
    );

    // 5. Kullanıcının genel rolünü site_manager olarak güncelle
    if (user.role !== 'super_user') {
      await client.query(
        `UPDATE users SET role = 'site_manager' WHERE id = $1`,
        [user.id],
      );
    }

    // 6. Dinamik Blokları ve altındaki Daireleri optimize (bulk) oluştur
    const createdBlocks = [];
    for (const b of normalizedBlocks) {
      const blockRes = await client.query(
        `
          INSERT INTO site_blocks (site_code, block_name, sort_order)
          VALUES ($1, $2, $3)
          RETURNING id, site_code, block_name, sort_order
        `,
        [siteCode, b.name, b.sortOrder],
      );
      const blockRow = blockRes.rows[0];
      const blockId = Number(blockRow.id);

      // Bloğun tüm dairelerini PostgreSQL generate_series ile tek sorguda mikrosaniyeler içinde oluştur
      await client.query(
        `
          INSERT INTO apartments (site_code, block_id, unit_label, sort_order, is_active)
          SELECT $1, $2, ('Daire ' || s.i), s.i, TRUE
          FROM generate_series(1, $3::int) AS s(i)
        `,
        [siteCode, blockId, b.apartmentCount],
      );

      createdBlocks.push({
        ...blockRow,
        apartmentCount: b.apartmentCount,
      });
    }

    // 7. Kapıları oluştur
    const createdDoors = [];
    for (const d of doorList) {
      const doorRes = await client.query(
        `
          INSERT INTO site_doors (site_code, door_name, door_index, is_active)
          VALUES ($1, $2, $3, TRUE)
          RETURNING id, site_code, door_name, door_index, is_active
        `,
        [siteCode, d.name, d.doorIndex],
      );
      createdDoors.push(doorRes.rows[0]);
    }

    // 8. Cihazı bu siteye ve 1. kapıya ata
    let assignedDevice = null;
    let targetDeviceUid = deviceUid ? String(deviceUid).trim().toUpperCase() : null;

    let devQuery;
    let devParams;
    if (targetDeviceUid) {
      devQuery = `SELECT * FROM devices WHERE UPPER(device_uid) = $1 AND (owner_user_id = $2 OR assigned_user_code = $3) LIMIT 1`;
      devParams = [targetDeviceUid, user.id, user.user_code];
    } else {
      devQuery = `SELECT * FROM devices WHERE (owner_user_id = $1 OR assigned_user_code = $2) ORDER BY claimed_at DESC NULLS LAST LIMIT 1`;
      devParams = [user.id, user.user_code];
    }

    const devRes = await client.query(devQuery, devParams);
    if (devRes.rowCount > 0) {
      const dev = devRes.rows[0];
      // Cihazı bu siteye bağla
      await client.query(
        `UPDATE devices SET site_code = $1, gate_name = $2 WHERE id = $3`,
        [siteCode, createdDoors[0]?.door_name || 'Kapı 1', dev.id],
      );
      // 1. Kapıya bu cihazı bağla
      if (createdDoors.length > 0) {
        await client.query(
          `UPDATE site_doors SET assigned_device_id = $1 WHERE id = $2`,
          [dev.id, createdDoors[0].id],
        );
        createdDoors[0].assigned_device_id = dev.id;
      }
      assignedDevice = {
        id: dev.id,
        device_uid: dev.device_uid,
        hardware_type: dev.hardware_type,
      };
    }

    await client.query('COMMIT');

    return {
      ok: true,
      message: `"${site.name}" sitesi, ${createdBlocks.length} blok ve ${totalApartmentCount} daire ile başarıyla kuruldu!`,
      site: {
        ...site,
        blocks: createdBlocks,
        doors: createdDoors,
        assignedDevice,
      },
    };
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

/**
 * Bireysel Kullanıcı: Site Katılım Başvurusu Oluşturma
 */
export async function createJoinRequest({
  userCode,
  token,
  blockId,
  apartmentId,
  notes,
}) {
  const cleanToken = String(token || '').replace(/^SITE_JOIN:/i, '').trim().toUpperCase();
  if (!cleanToken) {
    throw new Error('Geçersiz katılım tokeni.');
  }

  // Kullanıcıyı ve e-posta doğrulama durumunu kontrol et
  const userRes = await pool.query(
    `SELECT user_code, full_name, email, email_verified, is_active FROM users WHERE user_code = $1 LIMIT 1`,
    [Number(userCode)],
  );
  if (userRes.rowCount === 0) {
    throw new Error('Kullanıcı hesabı bulunamadı.');
  }
  const user = userRes.rows[0];
  if (!user.email_verified) {
    const err = new Error('Siteye katılım başvurusu yapabilmek için e-posta adresinizi doğrulamanız gerekmektedir.');
    err.statusCode = 403;
    throw err;
  }

  // Tokenı ve siteyi doğrula
  const tokenRes = await pool.query(
    `SELECT t.site_code, s.name AS site_name
     FROM site_join_tokens t
     JOIN sites s ON s.site_code = t.site_code
     WHERE UPPER(t.token) = $1 AND t.is_active = TRUE
     LIMIT 1`,
    [cleanToken],
  );
  if (tokenRes.rowCount === 0) {
    const err = new Error('Bu site katılım QR kodu geçersiz veya iptal edilmiş.');
    err.statusCode = 404;
    throw err;
  }
  const siteCode = Number(tokenRes.rows[0].site_code);
  const siteName = tokenRes.rows[0].site_name;

  // Blok ve daireyi doğrula
  const aptRes = await pool.query(
    `SELECT a.id, a.site_code, a.block_id, a.unit_label, b.block_name
     FROM apartments a
     LEFT JOIN site_blocks b ON b.id = a.block_id
     WHERE a.id = $1 AND a.site_code = $2 AND a.is_active = TRUE
     LIMIT 1`,
    [Number(apartmentId), siteCode],
  );
  if (aptRes.rowCount === 0) {
    throw new Error('Seçilen daire bulunamadı veya bu siteye ait değil.');
  }
  const apt = aptRes.rows[0];
  if (blockId && Number(apt.block_id) !== Number(blockId)) {
    throw new Error('Seçilen daire belirtilen bloğa ait değil.');
  }

  // Kullanıcı zaten bu dairenin sakini mi?
  const existingMemberRes = await pool.query(
    `SELECT role FROM apartment_memberships WHERE apartment_id = $1 AND user_code = $2 AND is_active = TRUE LIMIT 1`,
    [Number(apartmentId), user.user_code],
  );
  if (existingMemberRes.rowCount > 0) {
    const err = new Error(`Zaten bu dairenin aktif bir sakinisisiniz (${existingMemberRes.rows[0].role}).`);
    err.statusCode = 409;
    throw err;
  }

  // Kullanıcının bu site veya daire için bekleyen başvurusu var mı?
  const pendingReqRes = await pool.query(
    `SELECT id, status FROM join_requests WHERE site_code = $1 AND user_code = $2 AND status = 'PENDING' LIMIT 1`,
    [siteCode, user.user_code],
  );
  if (pendingReqRes.rowCount > 0) {
    const err = new Error('Bu site için zaten onay bekleyen bir katılım başvurunuz bulunmaktadır.');
    err.statusCode = 409;
    throw err;
  }

  const cleanNotes = notes ? String(notes).trim().slice(0, 500) : null;

  const insertRes = await pool.query(
    `
      INSERT INTO join_requests (
        site_code,
        block_id,
        apartment_id,
        user_code,
        status,
        notes
      )
      VALUES ($1, $2, $3, $4, 'PENDING', $5)
      RETURNING id, site_code, block_id, apartment_id, user_code, status, notes, created_at
    `,
    [siteCode, Number(apt.block_id), Number(apartmentId), user.user_code, cleanNotes],
  );

  return {
    ok: true,
    message: `"${siteName}" sitesi ${apt.block_name || ''} ${apt.unit_label} için katılım başvurunuz başarıyla oluşturuldu. Site yöneticisinin onayı bekleniyor.`,
    request: {
      id: Number(insertRes.rows[0].id),
      siteCode,
      siteName,
      blockName: apt.block_name || '',
      unitLabel: apt.unit_label,
      status: 'PENDING',
      createdAt: insertRes.rows[0].created_at,
    },
  };
}

/**
 * Bireysel Kullanıcı: Kendi katılım başvurularını listele
 */
export async function getMyJoinRequests(userCode) {
  const result = await pool.query(
    `
      SELECT
        jr.id,
        jr.site_code,
        s.name AS site_name,
        s.city,
        s.district,
        jr.block_id,
        b.block_name,
        jr.apartment_id,
        a.unit_label,
        jr.status,
        jr.notes,
        jr.rejection_reason,
        jr.created_at,
        jr.reviewed_at
      FROM join_requests jr
      JOIN sites s ON s.site_code = jr.site_code
      LEFT JOIN site_blocks b ON b.id = jr.block_id
      LEFT JOIN apartments a ON a.id = jr.apartment_id
      WHERE jr.user_code = $1
      ORDER BY jr.created_at DESC
    `,
    [Number(userCode)],
  );

  return {
    ok: true,
    requests: result.rows.map((r) => ({
      id: Number(r.id),
      siteCode: Number(r.site_code),
      siteName: r.site_name,
      city: r.city,
      district: r.district,
      blockId: r.block_id ? Number(r.block_id) : null,
      blockName: r.block_name,
      apartmentId: Number(r.apartment_id),
      unitLabel: r.unit_label,
      status: r.status,
      notes: r.notes,
      rejectionReason: r.rejection_reason,
      createdAt: r.created_at,
      reviewedAt: r.reviewed_at,
    })),
  };
}

/**
 * Site Yöneticisi: Sitedeki katılım başvurularını listele
 */
export async function getSiteJoinRequests({ siteCode, authUser, status }) {
  const parsedSiteCode = Number(siteCode);

  // Yetki kontrolü: super_user veya o sitenin yöneticisi
  if (authUser.role !== 'super_user') {
    const isManagerRes = await pool.query(
      `SELECT 1 FROM site_manager_sites WHERE site_code = $1 AND manager_user_code = $2 LIMIT 1`,
      [parsedSiteCode, Number(authUser.id)],
    );
    if (isManagerRes.rowCount === 0) {
      const isOwnerRes = await pool.query(
        `SELECT 1 FROM site_memberships WHERE site_code = $1 AND user_code = $2 AND role IN ('SITE_OWNER', 'SITE_ADMIN') AND is_active = TRUE LIMIT 1`,
        [parsedSiteCode, Number(authUser.id)],
      );
      if (isOwnerRes.rowCount === 0) {
        const err = new Error('Bu sitenin katılım taleplerini görme yetkiniz bulunmamaktadır.');
        err.statusCode = 403;
        throw err;
      }
    }
  }

  const queryStatus = status ? String(status).toUpperCase() : null;

  const result = await pool.query(
    `
      SELECT
        jr.id,
        jr.site_code,
        jr.user_code,
        u.full_name,
        u.email,
        u.phone_number,
        jr.block_id,
        b.block_name,
        jr.apartment_id,
        a.unit_label,
        jr.status,
        jr.notes,
        jr.rejection_reason,
        jr.created_at,
        jr.reviewed_at,
        reviewer.full_name AS reviewed_by_name
      FROM join_requests jr
      JOIN users u ON u.user_code = jr.user_code
      LEFT JOIN site_blocks b ON b.id = jr.block_id
      LEFT JOIN apartments a ON a.id = jr.apartment_id
      LEFT JOIN users reviewer ON reviewer.user_code = jr.reviewed_by_user_code
      WHERE jr.site_code = $1
        ${queryStatus ? 'AND jr.status = $2' : ''}
      ORDER BY
        CASE WHEN jr.status = 'PENDING' THEN 1 ELSE 2 END,
        jr.created_at DESC
    `,
    queryStatus ? [parsedSiteCode, queryStatus] : [parsedSiteCode],
  );

  return {
    ok: true,
    requests: result.rows.map((r) => ({
      id: Number(r.id),
      siteCode: Number(r.site_code),
      userCode: Number(r.user_code),
      fullName: r.full_name,
      email: r.email,
      phoneNumber: r.phone_number,
      blockId: r.block_id ? Number(r.block_id) : null,
      blockName: r.block_name,
      apartmentId: Number(r.apartment_id),
      unitLabel: r.unit_label,
      status: r.status,
      notes: r.notes,
      rejectionReason: r.rejection_reason,
      createdAt: r.created_at,
      reviewedAt: r.reviewed_at,
      reviewedByName: r.reviewed_by_name,
    })),
  };
}

/**
 * Site Yöneticisi: Katılım Başvurusunu Onayla
 */
export async function approveJoinRequest({ requestId, authUser }) {
  const reqId = Number(requestId);
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    // Talebi bul
    const reqRes = await client.query(
      `
        SELECT jr.*, s.name AS site_name, a.unit_label, b.block_name, u.full_name, u.email
        FROM join_requests jr
        JOIN sites s ON s.site_code = jr.site_code
        JOIN apartments a ON a.id = jr.apartment_id
        LEFT JOIN site_blocks b ON b.id = jr.block_id
        JOIN users u ON u.user_code = jr.user_code
        WHERE jr.id = $1
        FOR UPDATE OF jr
      `,
      [reqId],
    );
    if (reqRes.rowCount === 0) {
      throw new Error('Katılım talebi bulunamadı.');
    }
    const req = reqRes.rows[0];
    if (req.status !== 'PENDING') {
      throw new Error(`Bu talep zaten "${req.status}" durumunda, tekrar işlem yapılamaz.`);
    }

    // Yetki kontrolü
    if (authUser.role !== 'super_user') {
      const isManagerRes = await client.query(
        `SELECT 1 FROM site_manager_sites WHERE site_code = $1 AND manager_user_code = $2 LIMIT 1`,
        [Number(req.site_code), Number(authUser.id)],
      );
      if (isManagerRes.rowCount === 0) {
        const isOwnerRes = await client.query(
          `SELECT 1 FROM site_memberships WHERE site_code = $1 AND user_code = $2 AND role IN ('SITE_OWNER', 'SITE_ADMIN') AND is_active = TRUE LIMIT 1`,
          [Number(req.site_code), Number(authUser.id)],
        );
        if (isOwnerRes.rowCount === 0) {
          const err = new Error('Bu talebi onaylama yetkiniz bulunmamaktadır.');
          err.statusCode = 403;
          throw err;
        }
      }
    }

    // Aşama 9 Hiyerarşisi: Dairede daha önce aktif APARTMENT_ADMIN var mı?
    const adminCheckRes = await client.query(
      `SELECT 1 FROM apartment_memberships WHERE apartment_id = $1 AND role = 'APARTMENT_ADMIN' AND is_active = TRUE LIMIT 1`,
      [Number(req.apartment_id)],
    );
    const assignedRole = adminCheckRes.rowCount === 0 ? 'APARTMENT_ADMIN' : 'FAMILY_MEMBER';

    // 1. Daire üyeliği oluştur / güncelle
    await client.query(
      `
        INSERT INTO apartment_memberships (apartment_id, user_code, role, is_active)
        VALUES ($1, $2, $3, TRUE)
        ON CONFLICT (apartment_id, user_code)
        DO UPDATE SET role = $3, is_active = TRUE, updated_at = NOW()
      `,
      [Number(req.apartment_id), Number(req.user_code), assignedRole],
    );

    // 2. Site üyeliği oluştur / güncelle (Rol: RESIDENT)
    await client.query(
      `
        INSERT INTO site_memberships (site_code, user_code, role, is_active)
        VALUES ($1, $2, 'RESIDENT', TRUE)
        ON CONFLICT (site_code, user_code)
        DO UPDATE SET is_active = TRUE, updated_at = NOW()
      `,
      [Number(req.site_code), Number(req.user_code)],
    );

    // 3. Geriye dönük uyumluluk: apartments tablosunda resident_user_code boşsa ilk sakin ata
    await client.query(
      `UPDATE apartments SET resident_user_code = $1 WHERE id = $2 AND resident_user_code IS NULL`,
      [Number(req.user_code), Number(req.apartment_id)],
    );

    // 4. Talebi APPROVED olarak işaretle
    const reviewerUserCode = Number(authUser.id);
    await client.query(
      `
        UPDATE join_requests
        SET status = 'APPROVED',
            reviewed_by_user_code = $1,
            reviewed_at = NOW(),
            updated_at = NOW()
        WHERE id = $2
      `,
      [reviewerUserCode, reqId],
    );

    await client.query('COMMIT');

    return {
      ok: true,
      message: `${req.full_name} sakini, "${req.block_name || ''} ${req.unit_label}" dairesine ${assignedRole === 'APARTMENT_ADMIN' ? 'Daire Yöneticisi' : 'Aile Üyesi'} olarak başarıyla onaylandı.`,
      assignedRole,
    };
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

/**
 * Site Yöneticisi: Katılım Başvurusunu Reddet
 */
export async function rejectJoinRequest({ requestId, authUser, reason }) {
  const reqId = Number(requestId);
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const reqRes = await client.query(
      `SELECT * FROM join_requests WHERE id = $1 FOR UPDATE`,
      [reqId],
    );
    if (reqRes.rowCount === 0) {
      throw new Error('Katılım talebi bulunamadı.');
    }
    const req = reqRes.rows[0];
    if (req.status !== 'PENDING') {
      throw new Error(`Bu talep zaten "${req.status}" durumunda, tekrar işlem yapılamaz.`);
    }

    // Yetki kontrolü
    if (authUser.role !== 'super_user') {
      const isManagerRes = await client.query(
        `SELECT 1 FROM site_manager_sites WHERE site_code = $1 AND manager_user_code = $2 LIMIT 1`,
        [Number(req.site_code), Number(authUser.id)],
      );
      if (isManagerRes.rowCount === 0) {
        const isOwnerRes = await client.query(
          `SELECT 1 FROM site_memberships WHERE site_code = $1 AND user_code = $2 AND role IN ('SITE_OWNER', 'SITE_ADMIN') AND is_active = TRUE LIMIT 1`,
          [Number(req.site_code), Number(authUser.id)],
        );
        if (isOwnerRes.rowCount === 0) {
          const err = new Error('Bu talebi reddetme yetkiniz bulunmamaktadır.');
          err.statusCode = 403;
          throw err;
        }
      }
    }

    const cleanReason = reason ? String(reason).trim().slice(0, 500) : 'Yönetici tarafından uygun görülmedi.';
    const reviewerUserCode = Number(authUser.id);

    await client.query(
      `
        UPDATE join_requests
        SET status = 'REJECTED',
            rejection_reason = $1,
            reviewed_by_user_code = $2,
            reviewed_at = NOW(),
            updated_at = NOW()
        WHERE id = $3
      `,
      [cleanReason, reviewerUserCode, reqId],
    );

    await client.query('COMMIT');

    return {
      ok: true,
      message: 'Katılım başvurusu reddedildi.',
    };
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

/**
 * Bireysel / Daire Sakini: Kendi Onaylı Dairelerini ve Daire Üyelerini Getir
 */
export async function getMyApartments(userCode) {
  const uCode = Number(userCode);
  if (!Number.isInteger(uCode) || uCode <= 0) {
    throw new Error('Geçersiz kullanıcı kodu.');
  }

  // Kullanıcının üyesi olduğu aktif daireler
  const aptsRes = await pool.query(
    `
      SELECT
        am.id AS membership_id,
        am.apartment_id,
        am.role AS apartment_role,
        am.created_at AS joined_at,
        a.unit_label,
        a.block_id,
        a.sort_order,
        b.block_name,
        s.site_code,
        s.name AS site_name,
        s.city,
        s.district
      FROM apartment_memberships am
      JOIN apartments a ON a.id = am.apartment_id
      LEFT JOIN site_blocks b ON b.id = a.block_id
      JOIN sites s ON s.site_code = a.site_code
      WHERE am.user_code = $1 AND am.is_active = TRUE AND a.is_active = TRUE
      ORDER BY s.name ASC, b.block_name ASC, a.sort_order ASC, a.id ASC
    `,
    [uCode],
  );

  const apartments = [];

  for (const aptRow of aptsRes.rows) {
    const aptId = Number(aptRow.apartment_id);

    // Dairedeki tüm aktif üyeleri getir
    const membersRes = await pool.query(
      `
        SELECT
          am.id AS membership_id,
          am.user_code,
          am.role,
          am.is_active,
          am.created_at AS joined_at,
          u.full_name,
          u.email,
          u.phone_number
        FROM apartment_memberships am
        JOIN users u ON u.user_code = am.user_code
        WHERE am.apartment_id = $1 AND am.is_active = TRUE
        ORDER BY (CASE WHEN am.role = 'APARTMENT_ADMIN' THEN 0 ELSE 1 END), am.created_at ASC
      `,
      [aptId],
    );

    apartments.push({
      apartment_id: aptId,
      unit_label: aptRow.unit_label,
      block_id: aptRow.block_id != null ? Number(aptRow.block_id) : null,
      block_name: aptRow.block_name || '',
      site_code: Number(aptRow.site_code),
      site_name: aptRow.site_name,
      city: aptRow.city || '',
      district: aptRow.district || '',
      apartment_role: aptRow.apartment_role,
      joined_at: aptRow.joined_at,
      members: membersRes.rows.map((m) => ({
        membership_id: Number(m.membership_id),
        user_code: Number(m.user_code),
        full_name: m.full_name,
        email: m.email,
        phone_number: m.phone_number || '',
        role: m.role,
        is_current_user: Number(m.user_code) === uCode,
        is_apartment_admin: m.role === 'APARTMENT_ADMIN',
        joined_at: m.joined_at,
      })),
    });
  }

  return {
    ok: true,
    apartments,
  };
}

/**
 * Daire yönetim yetkisi kontrolü
 * (super_user, site_manager_sites yöneticisi, site_memberships OWNER/ADMIN veya ilgili dairenin APARTMENT_ADMIN'i)
 */
export async function checkApartmentManagementAccess(authUser, apartmentId) {
  const aptId = Number(apartmentId);
  if (!Number.isInteger(aptId)) {
    const err = new Error('Geçersiz daire kimliği.');
    err.statusCode = 400;
    throw err;
  }

  const aptRes = await pool.query(
    `SELECT a.id, a.site_code, a.block_id, a.unit_label, a.resident_user_code, a.resident_pin_code
     FROM apartments a
     WHERE a.id = $1 LIMIT 1`,
    [aptId],
  );
  if (aptRes.rowCount === 0) {
    const err = new Error('Daire bulunamadı.');
    err.statusCode = 404;
    throw err;
  }
  const apt = aptRes.rows[0];

  if (authUser?.role === 'super_user') {
    return { apt, isSuperUser: true, isSiteManager: true, isAptAdmin: true };
  }

  const userCode = Number(authUser?.userCode || authUser?.user_code || authUser?.id);

  // 1. Site Yöneticisi mi? (site_manager_sites)
  const mgrRes = await pool.query(
    `SELECT 1 FROM site_manager_sites WHERE site_code = $1 AND manager_user_code = $2 LIMIT 1`,
    [apt.site_code, userCode],
  );
  if (mgrRes.rowCount > 0) {
    return { apt, isSuperUser: false, isSiteManager: true, isAptAdmin: false };
  }

  // 2. Site Sahibi veya Yöneticisi mi? (site_memberships)
  const siteMemRes = await pool.query(
    `SELECT 1 FROM site_memberships WHERE site_code = $1 AND user_code = $2 AND role IN ('SITE_OWNER', 'SITE_ADMIN') AND is_active = TRUE LIMIT 1`,
    [apt.site_code, userCode],
  );
  if (siteMemRes.rowCount > 0) {
    return { apt, isSuperUser: false, isSiteManager: true, isAptAdmin: false };
  }

  // 3. Daire Yöneticisi mi? (APARTMENT_ADMIN)
  const aptAdminRes = await pool.query(
    `SELECT 1 FROM apartment_memberships WHERE apartment_id = $1 AND user_code = $2 AND role = 'APARTMENT_ADMIN' AND is_active = TRUE LIMIT 1`,
    [aptId, userCode],
  );
  if (aptAdminRes.rowCount > 0 || Number(apt.resident_user_code) === userCode) {
    return { apt, isSuperUser: false, isSiteManager: false, isAptAdmin: true };
  }

  const err = new Error('Bu daireyi yönetme yetkiniz bulunmamaktadır.');
  err.statusCode = 403;
  throw err;
}

/**
 * Daire Üyesini Pasife Al / Çıkar
 * (Süper Kullanıcı, Site Yöneticisi veya Daire Yöneticisi)
 */
export async function removeApartmentMember({ apartmentId, targetUserCode, authUser }) {
  const { apt, isSuperUser, isSiteManager } = await checkApartmentManagementAccess(authUser, apartmentId);
  const tUserCode = Number(targetUserCode);
  const reviewerUserCode = Number(authUser?.userCode || authUser?.user_code || authUser?.id);

  // Daire yöneticisi kendisini çıkaramaz (süper kullanıcı veya site yöneticisi çıkarabilir)
  if (!isSuperUser && !isSiteManager && tUserCode === reviewerUserCode) {
    throw new Error('Daire yöneticisi kendi kendisini daireden çıkaramaz.');
  }

  // Üyeliği pasife al
  await pool.query(
    `UPDATE apartment_memberships SET is_active = FALSE, updated_at = NOW() WHERE apartment_id = $1 AND user_code = $2`,
    [apt.id, tUserCode],
  );

  // Kapı istisnalarını temizle
  await pool.query(
    `DELETE FROM door_access_overrides WHERE site_code = $1 AND user_code = $2`,
    [apt.site_code, tUserCode],
  );

  return {
    ok: true,
    message: 'Üye daireden başarıyla çıkarıldı.',
  };
}

/**
 * Daire Sakini Aktif / Pasif Durumunu Değiştir
 * (Süper Kullanıcı, Site Yöneticisi veya Daire Yöneticisi)
 */
export async function toggleApartmentMemberStatus({ apartmentId, targetUserCode, isActive, authUser }) {
  const { apt, isSuperUser, isSiteManager } = await checkApartmentManagementAccess(authUser, apartmentId);
  const tUserCode = Number(targetUserCode);
  const reviewerUserCode = Number(authUser?.userCode || authUser?.user_code || authUser?.id);

  if (!Number.isInteger(tUserCode)) {
    const err = new Error('Geçersiz kullanıcı kimliği.');
    err.statusCode = 400;
    throw err;
  }

  if (!isSuperUser && !isSiteManager && tUserCode === reviewerUserCode) {
    const err = new Error('Daire yöneticisi kendi durumunu pasife alamaz.');
    err.statusCode = 400;
    throw err;
  }

  const activeBool = Boolean(isActive);

  // 1. apartment_memberships tablosunda güncelle
  const memUpdate = await pool.query(
    `UPDATE apartment_memberships
     SET is_active = $1, updated_at = NOW()
     WHERE apartment_id = $2 AND user_code = $3
     RETURNING role`,
    [activeBool, apt.id, tUserCode],
  );

  // 2. users tablosunda is_active durumunu güncelle
  await pool.query(
    `UPDATE users
     SET is_active = $1, updated_at = NOW()
     WHERE user_code = $2`,
    [activeBool, tUserCode],
  );

  // 3. Eğer legacy tekil daire sakini ise apartments tablosunu da senkronize et
  if (Number(apt.resident_user_code) === tUserCode) {
    await pool.query(
      `UPDATE apartments SET is_active = $1 WHERE id = $2`,
      [activeBool, apt.id],
    );
  }

  return {
    ok: true,
    is_active: activeBool,
    message: activeBool ? 'Daire sakini başarıyla aktif edildi.' : 'Daire sakini pasife alındı (erişimi durduruldu).',
  };
}

/**
 * Daire Sakinini Tamamen Sil
 * (Süper Kullanıcı ve Site Yöneticileri yetkilidir)
 */
export async function deleteApartmentMember({ apartmentId, targetUserCode, authUser }) {
  const { apt, isSuperUser, isSiteManager } = await checkApartmentManagementAccess(authUser, apartmentId);
  const tUserCode = Number(targetUserCode);

  if (!Number.isInteger(tUserCode)) {
    const err = new Error('Geçersiz kullanıcı kimliği.');
    err.statusCode = 400;
    throw err;
  }

  // 1. Daire üyeliğini sil
  await pool.query(
    `DELETE FROM apartment_memberships WHERE apartment_id = $1 AND user_code = $2`,
    [apt.id, tUserCode],
  );

  // 2. Kapı istisnalarını temizle
  await pool.query(
    `DELETE FROM door_access_overrides WHERE site_code = $1 AND user_code = $2`,
    [apt.site_code, tUserCode],
  );

  // 3. Eğer silinen kişi apartments.resident_user_code ise:
  if (Number(apt.resident_user_code) === tUserCode) {
    // Dairede kalan başka bir üye varsa onu otomatik APARTMENT_ADMIN yap
    const remainingRes = await pool.query(
      `SELECT user_code FROM apartment_memberships WHERE apartment_id = $1 ORDER BY created_at ASC LIMIT 1`,
      [apt.id],
    );
    if (remainingRes.rowCount > 0) {
      const newAdminCode = Number(remainingRes.rows[0].user_code);
      await pool.query(
        `UPDATE apartment_memberships SET role = 'APARTMENT_ADMIN' WHERE apartment_id = $1 AND user_code = $2`,
        [apt.id, newAdminCode],
      );
      await pool.query(
        `UPDATE apartments SET resident_user_code = $1 WHERE id = $2`,
        [newAdminCode, apt.id],
      );
    } else {
      await pool.query(
        `UPDATE apartments SET resident_user_code = NULL, resident_pin_code = NULL WHERE id = $1`,
        [apt.id],
      );
    }
  }

  return {
    ok: true,
    message: 'Sakin daireden başarıyla silindi.',
  };
}

/**
 * Daire Sakininin Şifresini Değiştir
 * (Süper Kullanıcı ve Site Yöneticileri yetkilidir)
 */
export async function changeApartmentMemberPassword({ apartmentId, targetUserCode, newPassword, authUser }) {
  const { apt, isSuperUser, isSiteManager } = await checkApartmentManagementAccess(authUser, apartmentId);
  const tUserCode = Number(targetUserCode);

  if (!isSuperUser && !isSiteManager) {
    const err = new Error('Daire sakinlerinin şifresini sadece site yöneticileri ve süper kullanıcı değiştirebilir.');
    err.statusCode = 403;
    throw err;
  }

  const cleanPass = String(newPassword || '').trim();
  if (cleanPass.length < 4) {
    const err = new Error('Şifre en az 4 karakter uzunluğunda olmalıdır.');
    err.statusCode = 400;
    throw err;
  }

  // Kullanıcının bu dairede kayıtlı olduğunu doğrula
  const memberCheck = await pool.query(
    `SELECT 1 FROM apartment_memberships WHERE apartment_id = $1 AND user_code = $2
     UNION
     SELECT 1 FROM apartments WHERE id = $1 AND resident_user_code = $2`,
    [apt.id, tUserCode],
  );
  if (memberCheck.rowCount === 0) {
    const err = new Error('Kullanıcı bu daireye ait değil.');
    err.statusCode = 404;
    throw err;
  }

  const passwordHash = await bcrypt.hash(cleanPass, 10);

  // users tablosunu güncelle
  await pool.query(
    `UPDATE users SET password_hash = $1, updated_at = NOW() WHERE user_code = $2`,
    [passwordHash, tUserCode],
  );

  // Eğer legacy kolonu varsa apartments tablosunda da pin kodunu güncelle
  if (Number(apt.resident_user_code) === tUserCode) {
    await pool.query(
      `UPDATE apartments SET resident_pin_code = $1 WHERE id = $2`,
      [cleanPass, apt.id],
    );
  }

  return {
    ok: true,
    message: 'Daire sakininin şifresi başarıyla güncellendi.',
  };
}

/**
 * Aile Reisini Değiştir (Yeni Daire Yöneticisi / APARTMENT_ADMIN Ata)
 * (Süper Kullanıcı, Site Yöneticisi ve Daire Yöneticisi yetkilidir)
 */
export async function setApartmentPrimaryAdmin({ apartmentId, targetUserCode, authUser }) {
  const { apt } = await checkApartmentManagementAccess(authUser, apartmentId);
  const tUserCode = Number(targetUserCode);

  if (!Number.isInteger(tUserCode)) {
    const err = new Error('Geçersiz kullanıcı kimliği.');
    err.statusCode = 400;
    throw err;
  }

  // Kullanıcının bu dairede kayıtlı olduğunu doğrula
  const memberRes = await pool.query(
    `SELECT role FROM apartment_memberships WHERE apartment_id = $1 AND user_code = $2`,
    [apt.id, tUserCode],
  );

  if (memberRes.rowCount === 0) {
    if (Number(apt.resident_user_code) === tUserCode) {
      return { ok: true, message: 'Bu kullanıcı zaten daire yöneticisidir.' };
    }
    const err = new Error('Kullanıcı bu dairede kayıtlı değil.');
    err.statusCode = 404;
    throw err;
  }

  if (memberRes.rows[0].role === 'APARTMENT_ADMIN') {
    return { ok: true, message: 'Bu kullanıcı zaten dairenin Aile Reisidir (Daire Yöneticisi).' };
  }

  // 1. Mevcut tüm APARTMENT_ADMIN'leri FAMILY_MEMBER yap
  await pool.query(
    `UPDATE apartment_memberships SET role = 'FAMILY_MEMBER', updated_at = NOW()
     WHERE apartment_id = $1 AND role = 'APARTMENT_ADMIN'`,
    [apt.id],
  );

  // 2. Hedef kullanıcıyı APARTMENT_ADMIN yap ve aktif et
  await pool.query(
    `UPDATE apartment_memberships SET role = 'APARTMENT_ADMIN', is_active = TRUE, updated_at = NOW()
     WHERE apartment_id = $1 AND user_code = $2`,
    [apt.id, tUserCode],
  );

  // 3. apartments.resident_user_code kolonunu güncelle
  await pool.query(
    `UPDATE apartments SET resident_user_code = $1 WHERE id = $2`,
    [tUserCode, apt.id],
  );

  return {
    ok: true,
    message: 'Aile Reisi (Daire Yöneticisi) başarıyla değiştirildi.',
  };
}

/**
 * ÜYELİK SİSTEMİ AŞAMA 11: Ek Kapı Yetkileri ve Toplu Yetkilendirme Servisi
 */

/**
 * Kapı yönetim yetkisi doğrulayıcı (Süper Kullanıcı, Site Yöneticisi veya Site Sahibi / Admini)
 */
export async function checkDoorManagementAccess(authUser, doorId) {
  const doorRes = await pool.query(
    `SELECT d.*, s.name AS site_name, sb.block_name
     FROM site_doors d
     JOIN sites s ON s.site_code = d.site_code
     LEFT JOIN site_blocks sb ON sb.id = d.block_id
     WHERE d.id = $1 LIMIT 1`,
    [Number(doorId)],
  );
  if (doorRes.rowCount === 0) {
    const err = new Error('Kapı bulunamadı.');
    err.statusCode = 404;
    throw err;
  }
  const door = doorRes.rows[0];

  if (authUser?.role === 'super_user') {
    return door;
  }

  const userCode = Number(authUser?.userCode || authUser?.user_code || authUser?.id);

  // 1. site_manager_sites kontrolü
  const isManagerRes = await pool.query(
    `SELECT 1 FROM site_manager_sites WHERE site_code = $1 AND manager_user_code = $2 LIMIT 1`,
    [door.site_code, userCode],
  );
  if (isManagerRes.rowCount > 0) {
    return door;
  }

  // 2. site_memberships (SITE_OWNER veya SITE_ADMIN) kontrolü
  const isOwnerRes = await pool.query(
    `SELECT 1 FROM site_memberships WHERE site_code = $1 AND user_code = $2 AND role IN ('SITE_OWNER', 'SITE_ADMIN') AND is_active = TRUE LIMIT 1`,
    [door.site_code, userCode],
  );
  if (isOwnerRes.rowCount > 0) {
    return door;
  }

  const err = new Error('Bu kapının yetkilerini yönetme yetkiniz bulunmamaktadır.');
  err.statusCode = 403;
  throw err;
}

/**
 * Belirli bir kapı için sitenin tüm blok, daire ve sakinlerini yetki durumuyla birlikte hiyerarşik listeler
 */
export async function getDoorPermissions({ doorId, authUser }) {
  const door = await checkDoorManagementAccess(authUser, doorId);
  const siteCode = Number(door.site_code);

  // 1. Sitenin tüm bloklarını çek
  const blocksRes = await pool.query(
    `SELECT id, site_code, block_name, sort_order
     FROM site_blocks
     WHERE site_code = $1
     ORDER BY sort_order ASC, id ASC`,
    [siteCode],
  );

  // 2. Sitedeki aktif daireleri ve sakinlerini çek
  const residentsRes = await pool.query(
    `SELECT
       a.id AS apartment_id,
       a.block_id,
       a.unit_label,
       a.sort_order AS apt_sort_order,
       u.user_code,
       u.full_name,
       u.email,
       COALESCE(am.role, 'APARTMENT_ADMIN') AS role
     FROM apartments a
     LEFT JOIN apartment_memberships am ON am.apartment_id = a.id AND am.is_active = TRUE
     LEFT JOIN users u ON u.user_code = COALESCE(am.user_code, a.resident_user_code)
     WHERE a.site_code = $1 AND a.is_active = TRUE AND u.user_code IS NOT NULL
     ORDER BY a.sort_order ASC, u.full_name ASC`,
    [siteCode],
  );

  // 3. Bu kapıya ait mevcut manuel yetki kayıtlarını (overrides) çek
  const overridesRes = await pool.query(
    `SELECT id, user_code, is_allowed, notes, updated_at
     FROM door_access_overrides
     WHERE door_id = $1`,
    [Number(door.id)],
  );
  const overrideMap = new Map();
  for (const row of overridesRes.rows) {
    overrideMap.set(Number(row.user_code), row);
  }

  // Daire sakinlerini grupla (blockId -> apartmentId -> residents)
  const aptResidentsMap = new Map(); // apartmentId -> list
  const aptInfoMap = new Map(); // apartmentId -> { id, block_id, unit_label, sort_order }

  for (const row of residentsRes.rows) {
    const aptId = Number(row.apartment_id);
    if (!aptInfoMap.has(aptId)) {
      aptInfoMap.set(aptId, {
        id: aptId,
        block_id: Number(row.block_id),
        unit_label: row.unit_label,
        sort_order: row.apt_sort_order,
      });
    }

    if (!aptResidentsMap.has(aptId)) {
      aptResidentsMap.set(aptId, []);
    }

    const uCode = Number(row.user_code);
    const override = overrideMap.get(uCode);

    let hasAccess = false;
    let accessSource = 'NO_ACCESS';

    if (override) {
      if (override.is_allowed === true) {
        hasAccess = true;
        accessSource = 'OVERRIDE_ALLOWED';
      } else {
        hasAccess = false;
        accessSource = 'OVERRIDE_DENIED';
      }
    } else {
      if (door.access_scope === 'SITE_COMMON') {
        hasAccess = true;
        accessSource = 'SITE_COMMON';
      } else if (door.access_scope === 'BLOCK' && door.block_id && Number(door.block_id) === Number(row.block_id)) {
        hasAccess = true;
        accessSource = 'BLOCK_DEFAULT';
      } else {
        hasAccess = false;
        accessSource = 'NO_ACCESS';
      }
    }

    aptResidentsMap.get(aptId).push({
      user_code: uCode,
      full_name: row.full_name,
      email: row.email,
      role: row.role,
      has_access: hasAccess,
      access_source: accessSource,
      override: override
        ? {
            id: Number(override.id),
            is_allowed: Boolean(override.is_allowed),
            notes: override.notes || null,
            updated_at: override.updated_at,
          }
        : null,
    });
  }

  // Blok bazlı ağacı oluştur
  let totalSiteResidents = 0;
  let totalSiteAuthorized = 0;

  const blocksTree = blocksRes.rows.map((blk) => {
    const blkId = Number(blk.id);
    const isDoorBlock = door.block_id ? Number(door.block_id) === blkId : false;

    // Bu bloğa ait daireleri filtrele
    const blkApartments = [];
    let blkResidentsCount = 0;
    let blkAuthorizedCount = 0;

    for (const [aptId, apt] of aptInfoMap.entries()) {
      if (apt.block_id === blkId) {
        const residents = aptResidentsMap.get(aptId) || [];
        blkResidentsCount += residents.length;
        const authorizedInApt = residents.filter((r) => r.has_access).length;
        blkAuthorizedCount += authorizedInApt;

        blkApartments.push({
          id: apt.id,
          unit_label: apt.unit_label,
          sort_order: apt.sort_order,
          residents,
          resident_count: residents.length,
          authorized_count: authorizedInApt,
        });
      }
    }

    totalSiteResidents += blkResidentsCount;
    totalSiteAuthorized += blkAuthorizedCount;

    return {
      id: blkId,
      block_name: blk.block_name,
      sort_order: blk.sort_order,
      is_door_block: isDoorBlock,
      total_residents: blkResidentsCount,
      authorized_count: blkAuthorizedCount,
      apartments: blkApartments,
    };
  });

  return {
    ok: true,
    door: {
      id: Number(door.id),
      site_code: siteCode,
      site_name: door.site_name,
      door_name: door.door_name,
      access_scope: door.access_scope,
      block_id: door.block_id ? Number(door.block_id) : null,
      block_name: door.block_name || null,
    },
    blocks: blocksTree,
    total_residents: totalSiteResidents,
    total_authorized: totalSiteAuthorized,
  };
}

/**
 * Tekil kullanıcı için kapı yetkisi tanımlar veya kaldırır (UPSERT / DELETE)
 */
export async function setDoorAccessOverride({
  doorId,
  userCode,
  isAllowed,
  notes = null,
  authUser,
}) {
  const door = await checkDoorManagementAccess(authUser, doorId);
  const targetUserCode = Number(userCode);
  const reviewerCode = Number(authUser?.userCode || authUser?.user_code || authUser?.id);

  // isAllowed null veya undefined ise yetki sıfırlanır (varsayılana döner)
  if (isAllowed === null || isAllowed === undefined) {
    await pool.query(
      `DELETE FROM door_access_overrides WHERE door_id = $1 AND user_code = $2`,
      [Number(door.id), targetUserCode],
    );
    return {
      ok: true,
      action: 'RESET',
      message: 'Kapı yetkisi varsayılan ayarlara döndürüldü.',
    };
  }

  const boolAllowed = Boolean(isAllowed);
  const cleanNotes = notes ? String(notes).trim() : null;

  const result = await pool.query(
    `INSERT INTO door_access_overrides (site_code, door_id, user_code, is_allowed, granted_by_user_code, notes, updated_at)
     VALUES ($1, $2, $3, $4, $5, $6, NOW())
     ON CONFLICT (door_id, user_code)
     DO UPDATE SET is_allowed = $4, granted_by_user_code = $5, notes = $6, updated_at = NOW()
     RETURNING id, site_code, door_id, user_code, is_allowed, notes, updated_at`,
    [Number(door.site_code), Number(door.id), targetUserCode, boolAllowed, reviewerCode, cleanNotes],
  );

  return {
    ok: true,
    action: boolAllowed ? 'GRANTED' : 'DENIED',
    override: result.rows[0],
    message: boolAllowed ? 'Ek kapı yetkisi başarıyla verildi.' : 'Kapı erişimi engellendi.',
  };
}

/**
 * Tüm bloğa, daireye veya kullanıcı listesine toplu yetki tanımlar veya kaldırır
 */
export async function setBulkDoorAccessOverride({
  doorId,
  blockId = null,
  apartmentId = null,
  userCodes = null,
  isAllowed,
  notes = null,
  authUser,
}) {
  const door = await checkDoorManagementAccess(authUser, doorId);
  const reviewerCode = Number(authUser?.userCode || authUser?.user_code || authUser?.id);

  let targetUserCodes = [];

  if (Array.isArray(userCodes) && userCodes.length > 0) {
    targetUserCodes = userCodes.map(Number).filter((n) => Number.isInteger(n));
  } else if (apartmentId) {
    const aptRes = await pool.query(
      `SELECT DISTINCT u.user_code
       FROM apartments a
       LEFT JOIN apartment_memberships am ON am.apartment_id = a.id AND am.is_active = TRUE
       LEFT JOIN users u ON u.user_code = COALESCE(am.user_code, a.resident_user_code)
       WHERE a.id = $1 AND u.user_code IS NOT NULL`,
      [Number(apartmentId)],
    );
    targetUserCodes = aptRes.rows.map((r) => Number(r.user_code));
  } else if (blockId) {
    const blkRes = await pool.query(
      `SELECT DISTINCT u.user_code
       FROM apartments a
       LEFT JOIN apartment_memberships am ON am.apartment_id = a.id AND am.is_active = TRUE
       LEFT JOIN users u ON u.user_code = COALESCE(am.user_code, a.resident_user_code)
       WHERE a.block_id = $1 AND a.is_active = TRUE AND u.user_code IS NOT NULL`,
      [Number(blockId)],
    );
    targetUserCodes = blkRes.rows.map((r) => Number(r.user_code));
  } else {
    const err = new Error('Toplu yetkilendirme için blok, daire veya kullanıcı listesi belirtilmelidir.');
    err.statusCode = 400;
    throw err;
  }

  if (targetUserCodes.length === 0) {
    return {
      ok: true,
      count: 0,
      message: 'Seçilen alanda aktif sakin bulunamadı.',
    };
  }

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    if (isAllowed === null || isAllowed === undefined) {
      await client.query(
        `DELETE FROM door_access_overrides
         WHERE door_id = $1 AND user_code = ANY($2::int[])`,
        [Number(door.id), targetUserCodes],
      );
    } else {
      const boolAllowed = Boolean(isAllowed);
      const cleanNotes = notes ? String(notes).trim() : null;

      for (const uCode of targetUserCodes) {
        await client.query(
          `INSERT INTO door_access_overrides (site_code, door_id, user_code, is_allowed, granted_by_user_code, notes, updated_at)
           VALUES ($1, $2, $3, $4, $5, $6, NOW())
           ON CONFLICT (door_id, user_code)
           DO UPDATE SET is_allowed = $4, granted_by_user_code = $5, notes = $6, updated_at = NOW()`,
          [Number(door.site_code), Number(door.id), uCode, boolAllowed, reviewerCode, cleanNotes],
        );
      }
    }

    await client.query('COMMIT');

    const actionText = isAllowed === null || isAllowed === undefined
      ? 'varsayılan ayarlara döndürüldü'
      : (isAllowed ? 'ek yetki verildi' : 'erişim engellendi');

    return {
      ok: true,
      count: targetUserCodes.length,
      message: `${targetUserCodes.length} sakin için kapı yetkisi ${actionText}.`,
    };
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

/**
 * Site yönetim yetkisi kontrolü (super_user, site_manager_sites veya site_memberships OWNER/ADMIN)
 */
export async function checkSiteManagementAccess(authUser, siteCode) {
  const siteRes = await pool.query(
    `SELECT site_code AS id, name, city, district, block_count, apartment_count, approval_status
     FROM sites
     WHERE site_code = $1
     LIMIT 1`,
    [Number(siteCode)],
  );
  if (siteRes.rowCount === 0) {
    const err = new Error('Site bulunamadı.');
    err.statusCode = 404;
    throw err;
  }
  const site = siteRes.rows[0];

  if (authUser?.role === 'super_user') {
    return site;
  }

  const userCode = Number(authUser?.userCode || authUser?.user_code || authUser?.id);

  // 1. site_manager_sites kontrolü
  const isManagerRes = await pool.query(
    `SELECT 1 FROM site_manager_sites WHERE site_code = $1 AND manager_user_code = $2 LIMIT 1`,
    [site.id, userCode],
  );
  if (isManagerRes.rowCount > 0) {
    return site;
  }

  // 2. site_memberships (SITE_OWNER veya SITE_ADMIN) kontrolü
  const isOwnerRes = await pool.query(
    `SELECT 1 FROM site_memberships WHERE site_code = $1 AND user_code = $2 AND role IN ('SITE_OWNER', 'SITE_ADMIN') AND is_active = TRUE LIMIT 1`,
    [site.id, userCode],
  );
  if (isOwnerRes.rowCount > 0) {
    return site;
  }

  const err = new Error('Bu sitenin sakinlerini görüntüleme yetkiniz bulunmamaktadır.');
  err.statusCode = 403;
  throw err;
}

/**
 * Aşama 12: Sitenin tüm blok, daire ve sakinlerini hiyerarşik akordiyon ağacı olarak döndürür
 */
export async function getSiteResidentsTree({ siteCode, authUser }) {
  const site = await checkSiteManagementAccess(authUser, siteCode);
  const sCode = Number(site.id);

  // 1. Blokları çek
  const blocksRes = await pool.query(
    `SELECT id, site_code, block_name, sort_order
     FROM site_blocks
     WHERE site_code = $1
     ORDER BY sort_order ASC, id ASC`,
    [sCode],
  );

  // 2. Daireleri çek
  const aptsRes = await pool.query(
    `SELECT id, block_id, unit_label, sort_order, resident_pin_code
     FROM apartments
     WHERE site_code = $1 AND is_active = TRUE
     ORDER BY sort_order ASC, id ASC`,
    [sCode],
  );

  // 3. Sakinleri çek (yeni üyelikler)
  const membershipsRes = await pool.query(
    `SELECT
       am.apartment_id,
       am.user_code,
       am.role,
       am.created_at AS joined_at,
       u.full_name,
       u.email,
       u.phone_number,
       u.login_name,
       (am.is_active = TRUE AND u.is_active = TRUE) AS is_active
     FROM apartment_memberships am
     INNER JOIN apartments a ON a.id = am.apartment_id
     INNER JOIN users u ON u.user_code = am.user_code
     WHERE a.site_code = $1
     ORDER BY (CASE WHEN am.role = 'APARTMENT_ADMIN' THEN 0 ELSE 1 END), am.created_at ASC`,
    [sCode],
  );

  // 4. Legacy sakinler (eski sistemde eklenip henüz yeni membership kaydı olmayanlar)
  const legacyRes = await pool.query(
    `SELECT
       a.id AS apartment_id,
       a.resident_user_code AS user_code,
       'APARTMENT_ADMIN' AS role,
       a.created_at AS joined_at,
       u.full_name,
       u.email,
       u.phone_number,
       u.login_name,
       (a.is_active = TRUE AND u.is_active = TRUE) AS is_active
     FROM apartments a
     INNER JOIN users u ON u.user_code = a.resident_user_code
     WHERE a.site_code = $1 AND a.resident_user_code IS NOT NULL
       AND NOT EXISTS (
         SELECT 1 FROM apartment_memberships am
         WHERE am.apartment_id = a.id AND am.user_code = a.resident_user_code AND am.is_active = TRUE
       )`,
    [sCode],
  );

  // Daire -> sakinler haritası
  const aptResidentsMap = new Map();
  for (const r of [...membershipsRes.rows, ...legacyRes.rows]) {
    const aptId = Number(r.apartment_id);
    if (!aptResidentsMap.has(aptId)) {
      aptResidentsMap.set(aptId, []);
    }
    aptResidentsMap.get(aptId).push({
      user_code: Number(r.user_code),
      full_name: r.full_name,
      email: r.email || null,
      phone_number: r.phone_number || null,
      login_name: r.login_name || null,
      role: r.role,
      joined_at: r.joined_at,
      is_active: r.is_active !== false,
    });
  }

  let totalSiteResidents = 0;
  let emptyApartmentsCount = 0;

  // Daireleri bloklara grupla
  const blockAptsMap = new Map();
  for (const apt of aptsRes.rows) {
    const bId = Number(apt.block_id);
    if (!blockAptsMap.has(bId)) {
      blockAptsMap.set(bId, []);
    }
    const aptId = Number(apt.id);
    const residents = aptResidentsMap.get(aptId) || [];
    if (residents.length === 0) {
      emptyApartmentsCount++;
    }
    totalSiteResidents += residents.length;

    blockAptsMap.get(bId).push({
      id: aptId,
      block_id: bId,
      unit_label: apt.unit_label,
      sort_order: apt.sort_order,
      resident_pin_code: apt.resident_pin_code || null,
      total_residents: residents.length,
      residents,
    });
  }

  const blocksTree = blocksRes.rows.map((blk) => {
    const bId = Number(blk.id);
    const apartments = blockAptsMap.get(bId) || [];
    const blkResidents = apartments.reduce((sum, a) => sum + a.total_residents, 0);

    return {
      id: bId,
      block_name: blk.block_name,
      sort_order: blk.sort_order,
      total_apartments: apartments.length,
      total_residents: blkResidents,
      apartments,
    };
  });

  return {
    ok: true,
    site: {
      id: sCode,
      name: site.name,
      city: site.city,
      district: site.district,
      total_blocks: blocksRes.rowCount,
      total_apartments: aptsRes.rowCount,
      total_residents: totalSiteResidents,
      empty_apartments_count: emptyApartmentsCount,
    },
    blocks: blocksTree,
  };
}





