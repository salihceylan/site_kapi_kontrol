// Anket ve Oylama şeması: 044. migrations/044_survey.sql ile AYNI ifadeler, AYNI sırayla (test: survey_schema).
//
// İki yeni tablo (ekleyici): surveys, survey_votes. Mevcut tablolara sütun/indeks EKLENMEZ.
// Açılış deadlock'u dersi (R2 F-1 / R11 F1, bkz. work_tracking_schema.js): ifadeler db.js'te dev ensureDbSchema bloğu BİTTİKTEN sonra, katalog kontrolüyle ve her biri
// kendi otomatik onaylı ifadesiyle yalnız EKSİK olanlar için çalışır; her şey varsa hiçbir tabloda kilit alınmaz. Tablolar FK'SIZ oluşturulur; her FK ayrı, katalog
// korumalı `ALTER TABLE ... ADD CONSTRAINT <tablo>_<sütun>_fkey` ifadesidir (ifade başına TEK üst tablo; sites / users sıcak tablolardır).
// Silme politikası: site silinince anket + oylar CASCADE; kullanıcı silinince SET NULL (oy kalır ve anonimleşir; anketi açan "Silinmiş Kullanıcı" görünür).
// survey_votes.apartment_id bilinçli olarak FK'sız: daire silinse de oy ve "daire başına tek oy" kaydı kalır.
// Bu dosya db.js'i İÇE AKTARMAZ (döngü olmasın).

/** Tek yabancı anahtar: katalogda yoksa ekler (idempotent). Ad = <tablo>_<sütun>_fkey. */
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

/** Sıra BAĞLAYICIDIR (migration ile aynı): önce tablo, sonra o tablonun FK'leri, sonra indeksleri. */
export const SURVEY_DDL = Object.freeze({
  surveysTable: `
    CREATE TABLE IF NOT EXISTS surveys (
      id BIGSERIAL PRIMARY KEY,
      site_code BIGINT NOT NULL,
      title TEXT NOT NULL,
      question TEXT NOT NULL,
      options JSONB NOT NULL,
      status TEXT NOT NULL DEFAULT 'draft',
      target_type TEXT NOT NULL DEFAULT 'site',
      target_block_ids BIGINT[] NOT NULL DEFAULT '{}',
      target_apartment_ids BIGINT[] NOT NULL DEFAULT '{}',
      anonymous BOOLEAN NOT NULL DEFAULT TRUE,
      one_vote_per_apartment BOOLEAN NOT NULL DEFAULT FALSE,
      closes_at TIMESTAMPTZ,
      opened_at TIMESTAMPTZ,
      closed_at TIMESTAMPTZ,
      created_by INTEGER,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      CONSTRAINT chk_surveys_title_length CHECK (char_length(title) BETWEEN 1 AND 120),
      CONSTRAINT chk_surveys_question_length CHECK (char_length(question) BETWEEN 1 AND 1000),
      CONSTRAINT chk_surveys_options CHECK (jsonb_typeof(options) = 'array' AND jsonb_array_length(options) BETWEEN 2 AND 10),
      CONSTRAINT chk_surveys_status CHECK (status IN ('draft', 'open', 'closed')),
      CONSTRAINT chk_surveys_target_type CHECK (target_type IN ('site', 'blocks', 'apartments')),
      CONSTRAINT chk_surveys_target_ids CHECK (cardinality(target_block_ids) <= 500 AND cardinality(target_apartment_ids) <= 500),
      CONSTRAINT chk_surveys_opened CHECK (status = 'draft' OR opened_at IS NOT NULL),
      CONSTRAINT chk_surveys_closed CHECK ((status = 'closed') = (closed_at IS NOT NULL))
    )
  `,
  surveysSiteFk: foreignKeySql('surveys', 'site_code', 'sites', 'site_code', 'CASCADE'),
  surveysCreatedByFk: foreignKeySql('surveys', 'created_by', 'users', 'user_code', 'SET NULL'),
  surveysSiteStatusIndex: `CREATE INDEX IF NOT EXISTS idx_surveys_site_status ON surveys (site_code, status, id DESC)`,
  votesTable: `
    CREATE TABLE IF NOT EXISTS survey_votes (
      id BIGSERIAL PRIMARY KEY,
      survey_id BIGINT NOT NULL,
      user_code INTEGER,
      apartment_id BIGINT,
      option_index SMALLINT NOT NULL,
      voted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      CONSTRAINT chk_survey_votes_option_index CHECK (option_index BETWEEN 0 AND 9)
    )
  `,
  votesSurveyFk: foreignKeySql('survey_votes', 'survey_id', 'surveys', 'id', 'CASCADE'),
  votesUserFk: foreignKeySql('survey_votes', 'user_code', 'users', 'user_code', 'SET NULL'),
  votesUserUniqueIndex: `CREATE UNIQUE INDEX IF NOT EXISTS uq_survey_votes_user ON survey_votes (survey_id, user_code) WHERE user_code IS NOT NULL`,
  votesApartmentIndex: `CREATE INDEX IF NOT EXISTS idx_survey_votes_apartment ON survey_votes (survey_id, apartment_id)`,
});

/** İfade adı -> { tablo | indeks | fk }. Sıra SURVEY_DDL ile aynıdır. `parent`: FK adımı için başvurulan tablo (sites / users her zaman vardır). */
const STEPS = Object.freeze([
  ['surveysTable', { table: 'surveys' }],
  ['surveysSiteFk', { fk: 'surveys_site_code_fkey', on: 'surveys', parent: 'sites' }],
  ['surveysCreatedByFk', { fk: 'surveys_created_by_fkey', on: 'surveys', parent: 'users' }],
  ['surveysSiteStatusIndex', { index: 'idx_surveys_site_status', on: 'surveys' }],
  ['votesTable', { table: 'survey_votes', needs: ['surveys'] }],
  ['votesSurveyFk', { fk: 'survey_votes_survey_id_fkey', on: 'survey_votes', parent: 'surveys' }],
  ['votesUserFk', { fk: 'survey_votes_user_code_fkey', on: 'survey_votes', parent: 'users' }],
  ['votesUserUniqueIndex', { index: 'uq_survey_votes_user', on: 'survey_votes' }],
  ['votesApartmentIndex', { index: 'idx_survey_votes_apartment', on: 'survey_votes' }],
]);

export const SURVEY_DDL_ORDER = Object.freeze(STEPS.map(([name]) => name));

const RETRYABLE = new Set(['40P01', '55P03']);
/** Test ayarı: yeniden deneme beklemesi (ms) çarpanı. */
export const schemaTuning = { retryDelayMs: 300 };

/** Tek DDL ifadesi; 40P01 / 55P03'te (yalnız ilk dağıtım, yoğun yazma) en çok 6 deneme, artan bekleme. İfade tek başına otomatik onaylıdır. */
async function runDdl(client, sql) {
  for (let attempt = 1; ; attempt += 1) {
    try {
      await client.query(sql);
      return;
    } catch (error) {
      if (!RETRYABLE.has(error?.code) || attempt >= 6) throw error;
      await new Promise((resolve) => setTimeout(resolve, schemaTuning.retryDelayMs * attempt));
    }
  }
}

/**
 * 044'ü uygular (db.js ensureDbSchema bloğu BİTTİKTEN sonra, ensureReservationSchema'dan SONRA çağrılır). Tek katalog sorgusuyla eksik nesneler belirlenir; yalnız
 * eksikler, sırayla ve kendi otomatik onaylı ifadeleriyle çalışır. Her şey varsa (normal açılış) hiçbir ifade gönderilmez.
 */
export async function ensureSurveySchema(client) {
  const tables = ['surveys', 'survey_votes'];
  const indexes = STEPS.filter(([, spec]) => spec.index).map(([, spec]) => spec.index);
  const foreignKeys = STEPS.filter(([, spec]) => spec.fk).map(([, spec]) => spec.fk);
  const found = await client.query(
    `
      SELECT
        ARRAY(SELECT t FROM unnest($1::TEXT[]) AS t WHERE to_regclass('public.' || t) IS NOT NULL) AS tables,
        ARRAY(SELECT indexname::TEXT FROM pg_indexes WHERE schemaname = 'public' AND indexname = ANY($2::TEXT[])) AS indexes,
        ARRAY(
          SELECT (SELECT r.relname::TEXT FROM pg_class r WHERE r.oid = c.conrelid) || '.' || c.conname::TEXT
          FROM pg_constraint c
          WHERE c.contype = 'f' AND c.connamespace = 'public'::regnamespace AND c.conname = ANY($3::TEXT[])
        ) AS fks
    `,
    [tables, indexes, foreignKeys],
  );
  const presentTables = new Set(found.rows[0]?.tables ?? []);
  const presentIndexes = new Set(found.rows[0]?.indexes ?? []);
  const presentFks = new Set(found.rows[0]?.fks ?? []);
  const hasParent = (parent) => parent === 'sites' || parent === 'users' || presentTables.has(parent);
  const fkPresent = (spec) => presentFks.has(`${spec.on}.${spec.fk}`);
  const pending = STEPS.filter(([, spec]) => {
    if (spec.table) return !presentTables.has(spec.table) && (spec.needs ?? []).every((dependency) => presentTables.has(dependency) || dependency === 'surveys');
    if (spec.fk) return presentTables.has(spec.on) && hasParent(spec.parent) && !fkPresent(spec);
    return !presentIndexes.has(spec.index);
  });
  // Eksik nesne yoksa (her normal açılış) hiçbir ifade gönderilmez: kilit alınmaz.
  if (pending.length === 0) {
    return;
  }
  // Kilit kuyruğunda sonsuza dek beklemesin: 2 sn sonra 55P03, runDdl yeniden dener.
  await client.query("SET lock_timeout = '2s'");
  try {
    for (const [name, spec] of STEPS) {
      if (spec.table) {
        if (presentTables.has(spec.table)) continue;
        if ((spec.needs ?? []).some((dependency) => !presentTables.has(dependency))) continue;
        await runDdl(client, SURVEY_DDL[name]);
        presentTables.add(spec.table);
      } else if (spec.fk) {
        if (!presentTables.has(spec.on) || !hasParent(spec.parent) || fkPresent(spec)) continue;
        await runDdl(client, SURVEY_DDL[name]);
        presentFks.add(`${spec.on}.${spec.fk}`);
      } else if (!presentIndexes.has(spec.index) && presentTables.has(spec.on)) {
        await runDdl(client, SURVEY_DDL[name]);
      }
    }
  } finally {
    await client.query('RESET lock_timeout').catch(() => {});
  }
}
