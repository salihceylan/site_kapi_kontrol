// Yerel test yardimcisi: uygulamanin ensureDbSchema()'sini calistirir. Kullanim: node ensure_schema.mjs <db.js dosya URL'si> (DB_* ortam degiskenleriyle)
const { pool, ensureDbSchema } = await import(process.argv[2]);
await ensureDbSchema();
console.log('ensureDbSchema OK');
await pool.end();
