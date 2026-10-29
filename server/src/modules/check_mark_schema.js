// Kontrol izi (110) şeması: tek kaynak. `migrations/110_check_marks.sql` bu adımların SQL'inin birleşimidir (test: check_mark).
//
// P2-20 sahip kararı: "muhasebeci" ROLÜ AÇILMAZ; yerine gider kaydında ve dekont bildiriminde "kontrol edildi (kim, ne zaman)" izi tutulur.
// İz AYRI yan tablolardadır: gider satırı değişmez (trg_finance_immutable) ve karara bağlanmış dekont satırı değiştirilemez (trg_payment_notices_guard);
// bu iki koruma GEVŞETİLMEZ. Satır yok = kontrolsüz (NULL değil); iz konulur ve kaldırılabilir (konulması ve kaldırılması denetim kaydındadır).
// Dekont onay / ret akışına dokunmaz: bu muhasebe kontrolüdür, karar değildir.
//
// Tablolar FK'SIZ oluşturulur, her FK ayrı ve katalog korumalıdır (ifade başına tek sıcak üst tablo; açılış 40P01 dersi). Normal açılışta tek katalog sorgusu.
// Silme politikası: gider / dekont silinirse iz CASCADE, site silinirse CASCADE, kontrol eden kullanıcı silinirse checked_by SET NULL.
// Bu dosya db.js'i İÇE AKTARMAZ.

/** İz tablosu tanımları (sıra bağlayıcıdır: önce gider, sonra dekont). */
export const CHECK_MARK_TABLES = Object.freeze([
  Object.freeze({ kind: 'expense', table: 'expense_check_marks', subject: 'expense_id', parent: 'expenses' }),
  Object.freeze({ kind: 'payment_notice', table: 'payment_notice_check_marks', subject: 'notice_id', parent: 'payment_notices' }),
]);

const fkSql = (table, column, parent, parentColumn, onDelete) => `DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = '${table}_${column}_fkey' AND conrelid = '${table}'::regclass
  ) THEN
    ALTER TABLE ${table} ADD CONSTRAINT ${table}_${column}_fkey FOREIGN KEY (${column}) REFERENCES ${parent}(${parentColumn}) ON DELETE ${onDelete};
  END IF;
END $$;`;

/** Bir iz tablosunun adım adım DDL'i. */
export function checkMarkDdl({ table, subject, parent }) {
  return Object.freeze({
    table: `CREATE TABLE IF NOT EXISTS ${table} (
  ${subject} BIGINT PRIMARY KEY,
  site_code BIGINT NOT NULL,
  checked_by INTEGER,
  checked_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);`,
    fk_subject: fkSql(table, subject, parent, 'id', 'CASCADE'),
    fk_site: fkSql(table, 'site_code', 'sites', 'site_code', 'CASCADE'),
    fk_user: fkSql(table, 'checked_by', 'users', 'user_code', 'SET NULL'),
    idx_site: `CREATE INDEX IF NOT EXISTS idx_${table}_site ON ${table} (site_code);`,
    idx_user: `CREATE INDEX IF NOT EXISTS idx_${table}_by ON ${table} (checked_by) WHERE checked_by IS NOT NULL;`,
  });
}

export const CHECK_MARK_STEP_ORDER = Object.freeze(['table', 'fk_subject', 'fk_site', 'fk_user', 'idx_site', 'idx_user']);

function stepName(spec, step) {
  switch (step) {
    case 'table':
      return spec.table;
    case 'fk_subject':
      return `${spec.table}_${spec.subject}_fkey`;
    case 'fk_site':
      return `${spec.table}_site_code_fkey`;
    case 'fk_user':
      return `${spec.table}_checked_by_fkey`;
    case 'idx_site':
      return `idx_${spec.table}_site`;
    default:
      return `idx_${spec.table}_by`;
  }
}

/** Sıralı adımlar: [{ table, step, sql, name, parent }]. */
export const CHECK_MARK_STEPS = Object.freeze(
  CHECK_MARK_TABLES.flatMap((spec) => {
    const ddl = checkMarkDdl(spec);
    return CHECK_MARK_STEP_ORDER.map((step) => Object.freeze({ table: spec.table, step, sql: ddl[step], name: stepName(spec, step), parent: spec.parent }));
  }),
);

/** Migration dosyasının gövdesi (DDL'lerin birleşimi). */
export const checkMarkMigrationBody = () => CHECK_MARK_STEPS.map((s) => s.sql).join('\n\n');

/** Eksik nesneler varsa sırayla uygular; hepsi varsa tek katalog sorgusundan sonra hiçbir ifade göndermez. */
export async function ensureCheckMarkSchema(client) {
  const relations = CHECK_MARK_STEPS.filter((s) => s.step === 'table' || s.step.startsWith('idx_')).map((s) => s.name);
  const foreignKeys = CHECK_MARK_STEPS.filter((s) => s.step.startsWith('fk_')).map((s) => s.name);
  const found = await client.query(
    `SELECT
       ARRAY(SELECT c.relname::TEXT FROM pg_class c WHERE c.relnamespace = 'public'::regnamespace AND c.relname = ANY($1::TEXT[])) AS relations,
       ARRAY(SELECT conname::TEXT FROM pg_constraint WHERE contype = 'f' AND conname = ANY($2::TEXT[])) AS fks,
       ARRAY(SELECT t FROM unnest($3::TEXT[]) AS t WHERE to_regclass('public.' || t) IS NOT NULL) AS parents`,
    [relations, foreignKeys, CHECK_MARK_TABLES.map((s) => s.parent)],
  );
  const row = found.rows[0] ?? {};
  const have = new Set([...(row.relations ?? []), ...(row.fks ?? [])]);
  const parents = new Set(row.parents ?? []);
  // Üst tablo (expenses / payment_notices) yoksa (kesilmiş şema) yabancı anahtar ertelenir; sonraki açılışta tamamlanır.
  const blocked = (s) => s.step === 'fk_subject' && !parents.has(s.parent);
  if (CHECK_MARK_STEPS.every((s) => have.has(s.name) || blocked(s))) {
    return;
  }
  await client.query("SET lock_timeout = '2s'");
  try {
    for (const s of CHECK_MARK_STEPS) {
      if (have.has(s.name) || blocked(s)) continue;
      for (let attempt = 1; ; attempt += 1) {
        try {
          await client.query(s.sql);
          break;
        } catch (error) {
          if ((error?.code !== '40P01' && error?.code !== '55P03') || attempt >= 6) throw error;
          await new Promise((resolve) => setTimeout(resolve, 300 * attempt));
        }
      }
    }
  } finally {
    await client.query('RESET lock_timeout').catch(() => {});
  }
}
