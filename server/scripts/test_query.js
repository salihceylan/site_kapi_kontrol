import './_dev_guard.js';
import { pool } from '../src/db.js';

async function test() {
  const dev = await pool.query("SELECT * FROM devices WHERE device_uid = 'D4C771A172E0'");
  console.log("Device D4C771A172E0:", dev.rows[0]);
  const usr = await pool.query("SELECT id, user_code, full_name, role FROM users WHERE user_code = 36224 OR email = 'salih@gudeteknoloji.com.tr'");
  console.log("User:", usr.rows);
  const memberships = await pool.query("SELECT * FROM site_manager_sites WHERE manager_user_code = 36224 UNION SELECT * FROM site_memberships WHERE user_code = 36224");
  console.log("Memberships:", memberships.rows);
  await pool.end();
}

test();
