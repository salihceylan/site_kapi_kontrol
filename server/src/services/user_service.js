import bcrypt from 'bcryptjs';
import { pool } from '../db.js';

export async function createUser({
  fullName,
  email,
  loginName = null,
  role,
  isActive,
  phoneNumber,
  password,
  emailVerified = true,
  approvalStatus = 'approved',
  verificationCodeHash = null,
  verificationCodeExpiresAt = null,
  db = pool,
}) {
  const passwordHash = await bcrypt.hash(password, 10);
  const result = await db.query(
    `
      INSERT INTO users (
        full_name,
        email,
        login_name,
        role,
        is_active,
        email_verified,
        approval_status,
        phone_number,
        password_hash,
        email_verification_code_hash,
        email_verification_expires_at
      )
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
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
    [
      fullName,
      email,
      loginName,
      role,
      isActive,
      emailVerified,
      approvalStatus,
      phoneNumber,
      passwordHash,
      verificationCodeHash,
      verificationCodeExpiresAt,
    ],
  );
  return result.rows[0];
}

export async function updateUserByCode({
  userCode,
  fullName,
  email,
  loginName,
  phoneNumber,
  password,
  isActive,
  db = pool,
}) {
  const sets = [];
  const values = [];

  if (fullName !== undefined) {
    values.push(fullName);
    sets.push(`full_name = $${values.length}`);
  }
  if (email !== undefined) {
    values.push(email);
    sets.push(`email = $${values.length}`);
  }
  if (loginName !== undefined) {
    values.push(loginName);
    sets.push(`login_name = $${values.length}`);
  }
  if (phoneNumber !== undefined) {
    values.push(phoneNumber);
    sets.push(`phone_number = $${values.length}`);
  }
  if (password !== undefined) {
    values.push(await bcrypt.hash(password, 12));
    sets.push(`password_hash = $${values.length}`);
  }
  if (isActive !== undefined) {
    values.push(isActive);
    sets.push(`is_active = $${values.length}`);
  }

  if (sets.length === 0) {
    return null;
  }

  values.push(userCode);
  const result = await db.query(
    `
      UPDATE users
      SET ${sets.join(', ')}
      WHERE user_code = $${values.length}
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
    values,
  );
  return result.rows[0] || null;
}

export async function setUserEmailVerificationCode({
  userCode,
  code,
}) {
  const codeHash = await bcrypt.hash(code, 10);
  const expiresAt = new Date(Date.now() + 10 * 60 * 1000);
  await pool.query(
    `
      UPDATE users
      SET
        email_verification_code_hash = $1,
        email_verification_expires_at = $2,
        email_verified = FALSE
      WHERE user_code = $3
    `,
    [codeHash, expiresAt, userCode],
  );
}

export async function userExists(userCode) {
  if (userCode == null) {
    return true;
  }

  const result = await pool.query(
    `SELECT 1 FROM users WHERE user_code = $1 LIMIT 1`,
    [userCode],
  );
  return result.rowCount > 0;
}
