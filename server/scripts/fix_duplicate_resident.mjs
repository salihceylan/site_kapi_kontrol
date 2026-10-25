import { pool } from '../src/db.js';

async function fix() {
  const client = await pool.connect();
  try {
    const cols = await client.query(`
      SELECT column_name, data_type 
      FROM information_schema.columns 
      WHERE table_name = 'apartment_memberships'
    `);
    console.log('apartment_memberships columns:', cols.rows);

    await client.query('BEGIN');
    console.log('Cleaning up duplicate resident in apartment 1494...');

    // 1. Daire 1494'te mükerrer oluşturulmuş phantom residency ve person sil
    await client.query(`DELETE FROM apartment_residencies WHERE id = 1956 AND apartment_id = 1494`);
    await client.query(`DELETE FROM site_people WHERE id = 1959 AND site_code = 7534881652`);

    // 2. Asıl kişi kaydını bu kullanıcı hesabına bağla
    await client.query(`
      UPDATE site_people
      SET user_code = 46351, full_name = NULL, phone = NULL, email = NULL, updated_at = NOW()
      WHERE id = 1929 AND site_code = 7534881652
    `);

    // 3. apartment_memberships (apartment_id, user_code, role, is_active)
    await client.query(`
      INSERT INTO apartment_memberships (apartment_id, user_code, role, is_active)
      VALUES (1494, 46351, 'APARTMENT_ADMIN', TRUE)
      ON CONFLICT (apartment_id, user_code)
      DO UPDATE SET role = 'APARTMENT_ADMIN', is_active = TRUE, updated_at = NOW()
    `);

    await client.query('COMMIT');
    console.log('Cleanup committed successfully!');

    const check = await client.query(`
      SELECT 
        ar.id as residency_id,
        ar.apartment_id,
        ar.person_id,
        sp.user_code,
        COALESCE(NULLIF(u.full_name, ''), sp.full_name) as name,
        ar.relation,
        ar.is_current
      FROM apartment_residencies ar
      JOIN site_people sp ON sp.id = ar.person_id
      LEFT JOIN users u ON u.user_code = sp.user_code
      WHERE ar.apartment_id = 1494 AND ar.is_current = TRUE
    `);
    console.log('Active residents for apartment 1494:', check.rows);

  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Error during cleanup:', err);
  } finally {
    client.release();
    await pool.end();
  }
}
fix();
