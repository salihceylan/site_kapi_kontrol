// Faaliyet raporu şeması: 069. migrations/069_annual_report.sql ile AYNI ifade. Tablo varsa hiçbir ifade gönderilmez.
// db.js'i İÇE AKTARMAZ.

export const ANNUAL_REPORT_DDL = Object.freeze({
  table: `
    CREATE TABLE IF NOT EXISTS annual_reports (
      id BIGSERIAL PRIMARY KEY,
      site_code BIGINT NOT NULL REFERENCES sites(site_code) ON DELETE CASCADE,
      year INTEGER NOT NULL,
      edits JSONB NOT NULL DEFAULT '{}'::jsonb,
      growth_bp INTEGER NOT NULL DEFAULT 0,
      updated_by INTEGER REFERENCES users(user_code) ON DELETE SET NULL,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      CONSTRAINT chk_annual_reports_year CHECK (year BETWEEN 2000 AND 2100),
      CONSTRAINT chk_annual_reports_growth CHECK (growth_bp BETWEEN -5000 AND 50000),
      CONSTRAINT chk_annual_reports_edits CHECK (jsonb_typeof(edits) = 'object'),
      CONSTRAINT uq_annual_reports_site_year UNIQUE (site_code, year)
    )
  `,
});

export async function ensureAnnualReportSchema(client) {
  const found = await client.query(`SELECT to_regclass('public.annual_reports') IS NOT NULL AS ok`);
  if (found.rows[0]?.ok) {
    return;
  }
  await client.query("SET lock_timeout = '5s'");
  try {
    for (const sql of Object.values(ANNUAL_REPORT_DDL)) {
      await client.query(sql);
    }
  } finally {
    await client.query('RESET lock_timeout');
  }
}
