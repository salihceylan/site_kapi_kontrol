import './_dev_guard.js';
import { pool } from '../src/db.js';

async function check() {
  const devs = await pool.query('SELECT * FROM device_runtime_status');
  console.log('RUNTIME STATUS:', devs.rows);
  const doors = await pool.query(`
    SELECT d.id, d.door_name, d.assigned_device_id, dev.device_uid, dev.is_online
    FROM site_doors d
    LEFT JOIN devices dev ON dev.id = d.assigned_device_id
  `);
  console.log('DOORS:', doors.rows);
  await pool.end();
}

check();
