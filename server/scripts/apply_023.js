import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { pool } from '../src/db.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

async function apply() {
  try {
    const sqlPath = path.join(__dirname, '..', 'migrations', '023_site_manager_invitations.sql');
    const sql = fs.readFileSync(sqlPath, 'utf8');
    console.log('Migrasyon 023 uygulanıyor...');
    await pool.query(sql);
    console.log('Migrasyon 023 başarıyla uygulandı.');
  } catch (error) {
    console.error('Migrasyon 023 hatası:', error);
  } finally {
    await pool.end();
  }
}

apply();

