import './_dev_guard.js';
import { pool } from '../src/db.js';
import { signAccessToken } from '../src/jwt.js';

const res = await pool.query("SELECT user_code AS id, email, role FROM users WHERE role = 'super_user' LIMIT 1");
const admin = res.rows[0];
const token = signAccessToken(admin);

// Create a temp test user
const createRes = await pool.query(`
  INSERT INTO users (user_code, full_name, email, password_hash, role, is_active, email_verified)
  VALUES (99991, 'Delete Test User', 'deletetest99991@example.com', 'dummyhash', 'individual', true, true)
  RETURNING user_code
`);
console.log("Created temp user:", createRes.rows[0].user_code);

// Test DELETE /admin/users/99991
const delResponse = await fetch('http://localhost:8080/admin/users/99991', {
  method: 'DELETE',
  headers: {
    'Authorization': `Bearer ${token}`
  }
});
console.log('Delete Response Status:', delResponse.status);
if (delResponse.status === 204) {
  console.log('SUCCESS: User deleted cleanly via API!');
} else {
  console.log('Delete response body:', await delResponse.text());
}

process.exit(0);
