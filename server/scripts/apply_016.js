import './_dev_guard.js';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { pool } from '../src/db.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

async function run() {
  const sqlPath = path.join(__dirname, '..', 'migrations', '016_membership_v2_schema.sql');
  const sql = fs.readFileSync(sqlPath, 'utf8');

  console.log('Uygulanıyor: 016_membership_v2_schema.sql');
  await pool.query(sql);

  // Tabloları doğrula
  const tablesRes = await pool.query(`
    SELECT table_name
    FROM information_schema.tables
    WHERE table_schema = 'public'
      AND table_name IN (
        'email_verifications',
        'site_memberships',
        'apartment_memberships',
        'site_join_tokens',
        'join_requests',
        'door_access_overrides'
      )
    ORDER BY table_name;
  `);

  console.log('Oluşturulan/Doğrulanan Tablolar:', tablesRes.rows.map((r) => r.table_name));

  const doorsColsRes = await pool.query(`
    SELECT column_name
    FROM information_schema.columns
    WHERE table_name = 'site_doors'
      AND column_name IN ('access_scope', 'block_id');
  `);
  console.log('site_doors Yeni Kolonlar:', doorsColsRes.rows.map((r) => r.column_name));

  console.log('MIGRATION_016_SUCCESS');
  await pool.end();
}

run().catch((err) => {
  console.error('MIGRATION_016_FAILED:', err);
  process.exit(1);
});

