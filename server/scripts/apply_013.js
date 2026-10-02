import './_dev_guard.js';
import 'dotenv/config';
import { pool } from '../src/db.js';

async function run() {
  await pool.query(`
    ALTER TABLE qr_access_tokens
    ADD COLUMN IF NOT EXISTS used_at TIMESTAMPTZ;

    ALTER TABLE qr_access_tokens
    ADD COLUMN IF NOT EXISTS use_count INTEGER NOT NULL DEFAULT 0;

    CREATE INDEX IF NOT EXISTS idx_qr_access_tokens_used_at
    ON qr_access_tokens(used_at);
  `);
  console.log('MIGRATION_013_SUCCESS');
  process.exit(0);
}

run().catch((err) => {
  console.error('Migration error:', err);
  process.exit(1);
});
