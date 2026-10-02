import './_dev_guard.js';
import { pool } from '../src/db.js';

async function main() {
  const cleanUid = '00861A0D5020';
  const doorQuery = await pool.query(
    `SELECT d.id, d.site_code, d.door_name, d.door_index, d.is_active,
            devices.device_uid AS assigned_device_uid,
            s.name AS site_name, s.site_code AS parent_site_code,
            s.require_geofence,
            s.geofence_latitude AS site_lat, s.geofence_longitude AS site_lng, s.geofence_radius_meters AS site_radius
     FROM site_doors d
     JOIN sites s ON s.site_code = d.site_code
     JOIN devices ON devices.id = d.assigned_device_id
     WHERE REPLACE(UPPER(devices.device_uid), ':', '') = $1 AND d.is_active = true
     LIMIT 1`,
    [cleanUid],
  );
  console.log('DOOR MATCHED:', doorQuery.rows);
  await pool.end();
}

main();

