import './_dev_guard.js';
import 'dotenv/config';
import { pool } from '../src/db.js';

async function run() {
  await pool.query(`
    ALTER TABLE qr_access_tokens
    ADD COLUMN IF NOT EXISTS last_denial_reason TEXT;

    ALTER TABLE qr_access_tokens
    ADD COLUMN IF NOT EXISTS last_denied_at TIMESTAMPTZ;

    ALTER TABLE qr_access_tokens
    ADD COLUMN IF NOT EXISTS denied_door_name TEXT;
  `);
  console.log('MIGRATION_014_SUCCESS');
  process.exit(0);
}

run().catch((err) => {
  console.error('Migration error:', err);
  process.exit(1);
});

