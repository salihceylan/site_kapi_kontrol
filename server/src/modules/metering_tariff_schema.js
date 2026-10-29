// Sayac tarifesi semasi: 116. migrations/117_meter_tariffs.sql ile AYNI ifadeler, AYNI sirayla (test: metering.test.js).
// Tamamen idempotent (IF NOT EXISTS / katalog korumali); metering_schema.js (061) ensure'indan SONRA calisir (sites / users yukarida kurulu).

function foreignKeySql(table, column, parent, parentColumn, onDelete) {
  const name = `${table}_${column}_fkey`;
  return `
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = '${name}' AND conrelid = '${table}'::regclass
      ) THEN
        ALTER TABLE ${table} ADD CONSTRAINT ${name} FOREIGN KEY (${column}) REFERENCES ${parent}(${parentColumn}) ON DELETE ${onDelete};
      END IF;
    END $$
  `;
}

export const METER_TARIFF_DDL = Object.freeze({
  tariffsTable: `
    CREATE TABLE IF NOT EXISTS meter_tariffs (
      id BIGSERIAL PRIMARY KEY,
      site_code BIGINT NOT NULL,
      kind TEXT NOT NULL,
      unit_price_minor BIGINT NOT NULL,
      valid_from DATE NOT NULL,
      valid_to DATE,
      created_by INTEGER,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      CONSTRAINT chk_meter_tariffs_kind CHECK (kind IN ('water', 'electricity', 'heat', 'hot_water')),
      CONSTRAINT chk_meter_tariffs_price CHECK (unit_price_minor > 0),
      CONSTRAINT chk_meter_tariffs_range CHECK (valid_to IS NULL OR valid_to > valid_from)
    )
  `,
  tariffsSiteFk: foreignKeySql('meter_tariffs', 'site_code', 'sites', 'site_code', 'CASCADE'),
  tariffsCreatedByFk: foreignKeySql('meter_tariffs', 'created_by', 'users', 'user_code', 'SET NULL'),
  tariffsIndex: `CREATE UNIQUE INDEX IF NOT EXISTS uq_meter_tariffs_site_kind_from ON meter_tariffs (site_code, kind, valid_from)`,
});

/** 116'yi uygular (db.js, 061 ensure'inden sonra). Her ifade kendi otomatik onayli ifadesidir; hepsi idempotenttir. */
export async function ensureMeterTariffSchema(client) {
  const present = await client.query(`SELECT to_regclass('public.meter_tariffs') IS NOT NULL AS ok`);
  const hasTable = present.rows[0]?.ok === true;
  await client.query("SET lock_timeout = '2s'");
  try {
    for (const sql of Object.values(METER_TARIFF_DDL)) {
      if (hasTable && sql === METER_TARIFF_DDL.tariffsTable) continue;
      await client.query(sql);
    }
  } finally {
    await client.query('RESET lock_timeout').catch(() => {});
  }
}
