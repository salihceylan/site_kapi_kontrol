import express from 'express';
import cors from 'cors';
import bcrypt from 'bcryptjs';
import dotenv from 'dotenv';

import { pool, checkDbConnection } from './db.js';
import { signAccessToken } from './jwt.js';

dotenv.config();

const app = express();
const port = Number(process.env.PORT || 8080);
const validRoles = new Set(['super_user', 'site_manager', 'apartment_owner']);

app.use(cors());
app.use(express.json());

app.get('/health', async (_req, res) => {
  try {
    await checkDbConnection();
    res.json({ ok: true, database: 'connected' });
  } catch (_e) {
    res.status(500).json({ ok: false, database: 'disconnected' });
  }
});

app.post('/auth/register', async (req, res) => {
  const fullName = String(req.body.full_name || '').trim();
  const email = String(req.body.email || '').trim().toLowerCase();
  const password = String(req.body.password || '').trim();
  const role = String(req.body.role || '').trim();

  if (fullName.length < 3) {
    return res.status(400).json({ error: 'full_name en az 3 karakter olmali.' });
  }
  if (!email.includes('@')) {
    return res.status(400).json({ error: 'Gecerli email girin.' });
  }
  if (password.length < 6) {
    return res.status(400).json({ error: 'Sifre en az 6 karakter olmali.' });
  }
  if (!validRoles.has(role)) {
    return res.status(400).json({ error: 'Gecersiz rol.' });
  }

  try {
    const passwordHash = await bcrypt.hash(password, 12);
    const result = await pool.query(
      `
      INSERT INTO users (full_name, email, role, password_hash)
      VALUES ($1, $2, $3, $4)
      RETURNING id, full_name, email, role
      `,
      [fullName, email, role, passwordHash],
    );

    const user = result.rows[0];
    const token = signAccessToken(user);
    return res.status(201).json({ token, user });
  } catch (error) {
    if (error?.code === '23505') {
      return res.status(409).json({ error: 'Bu e-posta zaten kayitli.' });
    }
    return res.status(500).json({ error: 'Kayit islemi basarisiz.' });
  }
});

app.post('/auth/login', async (req, res) => {
  const email = String(req.body.email || '').trim().toLowerCase();
  const password = String(req.body.password || '').trim();
  const role = String(req.body.role || '').trim();

  if (!email || !password || !role) {
    return res.status(400).json({ error: 'email, password, role zorunlu.' });
  }
  if (!validRoles.has(role)) {
    return res.status(400).json({ error: 'Gecersiz rol.' });
  }

  try {
    const result = await pool.query(
      `
      SELECT id, full_name, email, role, password_hash
      FROM users
      WHERE email = $1
      LIMIT 1
      `,
      [email],
    );

    if (result.rowCount === 0) {
      return res.status(401).json({ error: 'Giris bilgileri hatali.' });
    }

    const row = result.rows[0];
    const isPasswordMatch = await bcrypt.compare(password, row.password_hash);
    if (!isPasswordMatch) {
      return res.status(401).json({ error: 'Giris bilgileri hatali.' });
    }
    if (row.role !== role) {
      return res.status(403).json({ error: 'Kullanici rolu ile secilen rol uyusmuyor.' });
    }

    const user = {
      id: row.id,
      full_name: row.full_name,
      email: row.email,
      role: row.role,
    };
    const token = signAccessToken(user);

    return res.status(200).json({ token, user });
  } catch (_error) {
    return res.status(500).json({ error: 'Giris islemi basarisiz.' });
  }
});

app.use((_req, res) => {
  res.status(404).json({ error: 'Route bulunamadi.' });
});

app.listen(port, () => {
  // eslint-disable-next-line no-console
  console.log(`API started on http://localhost:${port}`);
});
