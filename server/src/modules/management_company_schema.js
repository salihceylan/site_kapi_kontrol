// 062 (yönetim firması, Y1/Y2): migrations/062_management_companies.sql ile AYNI DDL. Ekleyici ve idempotent.
// db.js ensureDbSchema bloğu bittikten sonra çağrılır; her şey varsa yalnız tek katalog sorgusu gider (kilit alınmaz).

export const MANAGEMENT_COMPANY_DDL = Object.freeze({
  companies: `
    CREATE TABLE IF NOT EXISTS management_companies (
      id BIGSERIAL PRIMARY KEY,
      name TEXT NOT NULL,
      partner_share_bp INTEGER NOT NULL DEFAULT 0,
      is_active BOOLEAN NOT NULL DEFAULT TRUE,
      created_by INTEGER REFERENCES users(user_code) ON DELETE SET NULL,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      CONSTRAINT chk_management_companies_name CHECK (char_length(name) BETWEEN 2 AND 120),
      CONSTRAINT chk_management_companies_share CHECK (partner_share_bp BETWEEN 0 AND 10000)
    )`,
  members: `
    CREATE TABLE IF NOT EXISTS management_company_members (
      company_id BIGINT NOT NULL REFERENCES management_companies(id) ON DELETE CASCADE,
      user_code INTEGER NOT NULL REFERENCES users(user_code) ON DELETE CASCADE,
      role TEXT NOT NULL,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      PRIMARY KEY (company_id, user_code),
      CONSTRAINT chk_management_company_members_role CHECK (role IN ('owner', 'staff'))
    )`,
  membersIndex: 'CREATE INDEX IF NOT EXISTS idx_management_company_members_user ON management_company_members(user_code)',
  sites: `
    CREATE TABLE IF NOT EXISTS management_company_sites (
      site_code BIGINT PRIMARY KEY REFERENCES sites(site_code) ON DELETE CASCADE,
      company_id BIGINT NOT NULL REFERENCES management_companies(id) ON DELETE CASCADE,
      monthly_fee_minor BIGINT,
      linked_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      CONSTRAINT chk_management_company_sites_fee CHECK (monthly_fee_minor IS NULL OR monthly_fee_minor BETWEEN 0 AND 1000000000000)
    )`,
  sitesIndex: 'CREATE INDEX IF NOT EXISTS idx_management_company_sites_company ON management_company_sites(company_id)',
  trialColumn: 'ALTER TABLE site_subscriptions ADD COLUMN IF NOT EXISTS trial_ends_at TIMESTAMPTZ',
  trialSeed: `
    INSERT INTO platform_settings (key, value) VALUES ('subscription.trial_days', '{"days":60}'::jsonb)
    ON CONFLICT (key) DO NOTHING`,
});

export async function ensureManagementCompanySchema(client) {
  const found = await client.query(
    `SELECT
       to_regclass('public.management_companies') IS NOT NULL AS companies,
       to_regclass('public.management_company_members') IS NOT NULL AS members,
       to_regclass('public.management_company_sites') IS NOT NULL AS sites,
       EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'site_subscriptions' AND column_name = 'trial_ends_at') AS trial_col`,
  );
  const row = found.rows[0] ?? {};
  await client.query("SET lock_timeout = '2s'");
  try {
    if (!row.companies) await client.query(MANAGEMENT_COMPANY_DDL.companies);
    if (!row.members) {
      await client.query(MANAGEMENT_COMPANY_DDL.members);
      await client.query(MANAGEMENT_COMPANY_DDL.membersIndex);
    }
    if (!row.sites) {
      await client.query(MANAGEMENT_COMPANY_DDL.sites);
      await client.query(MANAGEMENT_COMPANY_DDL.sitesIndex);
    }
    if (!row.trial_col) await client.query(MANAGEMENT_COMPANY_DDL.trialColumn);
    await client.query(MANAGEMENT_COMPANY_DDL.trialSeed);
  } finally {
    await client.query('RESET lock_timeout').catch(() => {});
  }
}
