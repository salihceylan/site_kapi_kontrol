import bcrypt from 'bcryptjs';
import { pool } from '../db.js';
import { sendApartmentCredentialsEmail } from '../mailer.js';
import { createUser } from './user_service.js';
import {
  apartmentBaseLoginName,
  apartmentResidentFullName,
  generateApartmentPin,
  generateInternalApartmentEmail,
} from '../utils/helpers.js';

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

  await db.query(
    `
      UPDATE apartments
      SET
        resident_user_code = $1,
        resident_pin_code = $2,
        is_active = TRUE
      WHERE id = $3
    `,
    [Number(createdUser.id), pinCode, apartmentId],
  );
}

export async function ensureSiteApartmentResidents(siteCode, db = pool) {
  const apartmentsResult = await db.query(
    `
      SELECT
        a.id,
        a.site_code,
        a.unit_label,
        a.sort_order,
        a.resident_user_code,
        u.user_code AS existing_resident_user_code,
        b.block_name
      FROM apartments a
      INNER JOIN site_blocks b ON b.id = a.block_id
      LEFT JOIN users u
        ON u.user_code = a.resident_user_code
       AND u.role = 'apartment_owner'
      WHERE a.site_code = $1
      ORDER BY b.sort_order ASC, a.sort_order ASC
    `,
    [siteCode],
  );

  for (const apartment of apartmentsResult.rows) {
    if (
      apartment.resident_user_code != null &&
      apartment.existing_resident_user_code != null
    ) {
      continue;
    }
    await createApartmentResidentAccount({
      apartmentId: Number(apartment.id),
      siteCode: Number(apartment.site_code),
      blockName: apartment.block_name,
      unitLabel: apartment.unit_label,
      sortOrder: Number(apartment.sort_order),
      db,
    });
  }
}

export async function provisionApartmentResident({
  apartmentId,
  fullName,
  loginName,
  password,
  email,
  phoneNumber,
  isActive,
}) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
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
      await client.query(
        `
          UPDATE apartments
          SET
            resident_user_code = $1,
            resident_email = $2,
            resident_pin_code = $3,
            is_active = $4
          WHERE id = $5
        `,
        [userCode, residentEmail, password, isActive, apartmentId],
      );
    } else {
      const passwordHash = await bcrypt.hash(password, 12);
      await client.query(
        `
          UPDATE users
          SET
            full_name = $1,
            email = $2,
            login_name = $3,
            phone_number = $4,
            password_hash = $5,
            is_active = $6
          WHERE user_code = $7
        `,
        [fullName, internalEmail, finalLoginName, phoneNumber, passwordHash, isActive, userCode],
      );
      await client.query(
        `
          UPDATE apartments
          SET
            resident_email = $1,
            resident_pin_code = $2,
            is_active = $3
          WHERE id = $4
        `,
        [residentEmail, password, isActive, apartmentId],
      );
    }

    const finalResult = await client.query(
      `
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
          a.resident_pin_code,
          u.phone_number AS resident_phone_number,
          u.is_active AS resident_is_active,
          a.created_at
        FROM apartments a
        INNER JOIN site_blocks b ON b.id = a.block_id
        LEFT JOIN users u ON u.user_code = a.resident_user_code
        WHERE a.id = $1
      `,
      [apartmentId],
    );

    await client.query('COMMIT');
    return finalResult.rows[0];
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
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
      `SELECT * FROM apartments WHERE id = $1 LIMIT 1`,
      [apartmentId],
    );
    if (aptResult.rowCount === 0) {
      throw new Error('APARTMENT_NOT_FOUND');
    }
    const apt = aptResult.rows[0];

    if (apt.resident_user_code) {
      await client.query(
        `DELETE FROM users WHERE user_code = $1 AND role = 'apartment_owner'`,
        [apt.resident_user_code],
      );
    }

    const updated = await client.query(
      `
        UPDATE apartments
        SET
          resident_user_code = NULL,
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
        a.resident_pin_code,
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

export async function sendApartmentCredentials(apartmentId) {
  const snapshot = await getApartmentCredentialSnapshot(apartmentId);
  if (!snapshot) {
    throw new Error('APARTMENT_NOT_FOUND');
  }
  if (!snapshot.resident_email) {
    throw new Error('APARTMENT_EMAIL_REQUIRED');
  }
  if (!snapshot.resident_login_name || !snapshot.resident_pin_code) {
    throw new Error('APARTMENT_CREDENTIALS_NOT_READY');
  }

  await sendApartmentCredentialsEmail({
    to: snapshot.resident_email,
    residentName: snapshot.resident_full_name || `${snapshot.block_name} ${snapshot.unit_label}`,
    apartmentLabel: `${snapshot.block_name} / ${snapshot.unit_label}`,
    siteName: snapshot.site_name,
    loginName: snapshot.resident_login_name,
    pinCode: snapshot.resident_pin_code,
  });
}
