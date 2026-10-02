import './_dev_guard.js';
import pg from 'pg';
import dotenv from 'dotenv';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

dotenv.config({ path: path.join(__dirname, '../.env') });

const { Pool } = pg;
const pool = new Pool({
  host: process.env.DB_HOST,
  port: Number(process.env.DB_PORT || 5432),
  database: process.env.DB_NAME,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
});

async function main() {
  const sqlPath = path.join(__dirname, '../migrations/019_join_requests_notes.sql');
  const sql = fs.readFileSync(sqlPath, 'utf8');
  console.log('Applying migration 019...');
  await pool.query(sql);
  console.log('MIGRATION_019_SUCCESS');
  await pool.end();
}

main().catch(err => {
  console.error('Migration 019 failed:', err);
  process.exit(1);
});

