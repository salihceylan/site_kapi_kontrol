import './_dev_guard.js';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { pool } from '../src/db.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

async function run() {
  const sqlPath = path.join(__dirname, '..', 'migrations', '015_qr_single_use.sql');
  const sql = fs.readFileSync(sqlPath, 'utf8');

  console.log('Uygulanıyor: 015_qr_single_use.sql');
  await pool.query(sql);

  // Mevcut used_at dolu olanları is_used = true yap
  await pool.query(`UPDATE qr_access_tokens SET is_used = TRUE WHERE used_at IS NOT NULL OR use_count > 0;`);

  console.log('MIGRATION_015_SUCCESS');
  await pool.end();
}

run().catch((err) => {
  console.error('MIGRATION_015_FAILED:', err);
  process.exit(1);
});

