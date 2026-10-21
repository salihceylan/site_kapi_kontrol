// Sayac okuma fotograflari semasi: 070. migrations/070_meter_reading_photos.sql ile AYNI ifadeler, AYNI sirayla (test: metering_field).
// Ekleyici ve idempotent; tablo varsa hicbir ifade gonderilmez. Bu dosya db.js'i ice aktarmaz.

function foreignKeySql(table, column, parent, parentColumn, onDelete) {
  const name = `${table}_${column}_fkey`;
  return `
    DO $$
    BEGIN
      IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = '${name}' AND conrelid = '${table}'::regclass) THEN
        ALTER TABLE ${table} ADD CONSTRAINT ${name} FOREIGN KEY (${column}) REFERENCES ${parent}(${parentColumn}) ON DELETE ${onDelete};
      END IF;
    END $$
  `;
}

export const METERING_FIELD_DDL = Object.freeze({
  photosTable: `
    CREATE TABLE IF NOT EXISTS meter_reading_photos (
      id BIGSERIAL PRIMARY KEY,
      site_code BIGINT NOT NULL,
      meter_id BIGINT NOT NULL,
      reading_id BIGINT NOT NULL,
      name TEXT NOT NULL,
      mime_type TEXT NOT NULL,
      size_bytes INTEGER NOT NULL,
      sha256 TEXT NOT NULL,
      data BYTEA NOT NULL,
      created_by INTEGER,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      CONSTRAINT chk_meter_reading_photos_size CHECK (size_bytes > 0 AND size_bytes <= 1048576)
    )
  `,
  photosSiteFk: foreignKeySql('meter_reading_photos', 'site_code', 'sites', 'site_code', 'CASCADE'),
  photosReadingFk: foreignKeySql('meter_reading_photos', 'reading_id', 'meter_readings', 'id', 'CASCADE'),
  photosIndex: `CREATE INDEX IF NOT EXISTS idx_meter_reading_photos_site ON meter_reading_photos (site_code, reading_id)`,
});

export const METERING_FIELD_DDL_ORDER = Object.freeze(['photosTable', 'photosSiteFk', 'photosReadingFk', 'photosIndex']);

/** Tablo yoksa 070'i sirayla uygular (meter_readings 061'den sonra calisir). */
export async function ensureMeteringFieldSchema(client) {
  const found = await client.query(
    `SELECT to_regclass('public.meter_reading_photos') IS NOT NULL AS present, to_regclass('public.meter_readings') IS NOT NULL AS parent`,
  );
  const row = found.rows[0] ?? {};
  if (row.present === true || row.parent !== true) return;
  for (const name of METERING_FIELD_DDL_ORDER) {
    await client.query(METERING_FIELD_DDL[name]);
  }
}
