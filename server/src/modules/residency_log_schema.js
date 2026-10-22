// Daire sakini ADLI KAYDI (residency forensic log) şeması: 075. migrations/075_residency_log.sql ile AYNI ifadeler, AYNI sırayla (test: residency_log).
//
// Tek yeni tablo (ekleyici): apartment_residency_log. Mevcut tablolara sütun / indeks EKLENMEZ. Tek mevcut-tablo etkisi: users üzerinde KAYIT tetikleyicisi
// (trg_users_log_residencies; kullanıcı satırı fiziksel silinirken güncel daire bağlarını kayda geçirir, silmeyi ASLA engellemez).
//
// YALNIZ EKLEME (trg_apartment_residency_log_immutable): satır değişmez ve silinmez.
//  - UPDATE hiçbir koşulda yapılamaz (kullanıcı FK'sı yok: hesap silinse bile satır olduğu gibi kalır; sayılar ve ad anlık görüntüsüdür).
//  - DELETE yalnız üst sites satırı artık YOKSA serbesttir (site silme CASCADE). Daire silinirse satır KALIR (apartment_id FK'sızdır).
//  - TRUNCATE her durumda engellenir.
// Veri azaltma: iletişim bilgisi (telefon, e-posta, TCKN) sütunu YOKTUR; serbest not YOKTUR (yalnız kod alanları). `related` yalnız sayısal kimlikler ve
// kod değerleri taşır (JS tarafında beyaz listeyle süzülür; biçim CHECK'i metin uzunluğunu sınırlar).
// Açılış deadlock'u dersi (bkz. platform_rules_schema.js): ifadeler db.js'te dev ensureDbSchema bloğu BİTTİKTEN sonra, katalog kontrolüyle ve her biri kendi
// otomatik onaylı ifadesiyle yalnız EKSİK olanlar için çalışır; her şey varsa hiçbir tabloda kilit alınmaz.
// İşlev gövdeleri sürüm işareti taşır (RESIDENCY_LOG_MARKER). Bu dosya db.js'i İÇE AKTARMAZ (döngü olmasın).

/** İşlev gövdesine yazılan sürüm işareti (katalog `prosrc` aranır). */
export const RESIDENCY_LOG_MARKER = 'arl:1';

export const RESIDENCY_EVENT_TYPES = Object.freeze([
  'moved_in',
  'moved_out',
  'role_changed',
  'admin_changed',
  'link_cut_mutual',
  'member_removed',
  'member_left',
  'access_suspended',
  'access_lifted',
  'handover',
]);

export const RESIDENCY_ACTOR_ROLES = Object.freeze(['system', 'super_user', 'site_manager', 'apartment_admin', 'owner', 'tenant', 'resident']);
export const RESIDENCY_RELATIONS = Object.freeze(['owner', 'tenant', 'family_member', 'resident']);

const sqlList = (values) => values.map((value) => `'${value}'`).join(', ');

/** Tek yabancı anahtar: katalogda yoksa ekler (idempotent). */
function foreignKeySql(column, parent, parentColumn, onDelete) {
  const name = `apartment_residency_log_${column}_fkey`;
  return `
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = '${name}' AND conrelid = 'apartment_residency_log'::regclass
      ) THEN
        ALTER TABLE apartment_residency_log ADD CONSTRAINT ${name} FOREIGN KEY (${column}) REFERENCES ${parent}(${parentColumn}) ON DELETE ${onDelete};
      END IF;
    END $$
  `;
}

/** Tetikleyici: katalogda yoksa oluşturur (idempotent). */
function triggerSql(name, table, definition) {
  return `
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM pg_trigger WHERE tgname = '${name}' AND tgrelid = '${table}'::regclass AND NOT tgisinternal
      ) THEN
        CREATE TRIGGER ${name} ${definition};
      END IF;
    END $$
  `;
}

/** Sıra BAĞLAYICIDIR (migration ile aynı): tablo -> FK -> indeksler -> işlevler -> tetikleyiciler. */
export const RESIDENCY_LOG_DDL = Object.freeze({
  logTable: `
    CREATE TABLE IF NOT EXISTS apartment_residency_log (
      id BIGSERIAL PRIMARY KEY,
      site_code BIGINT NOT NULL,
      apartment_id BIGINT,
      apartment_label TEXT,
      event_type TEXT NOT NULL,
      reason_code TEXT NOT NULL,
      subject_name TEXT,
      subject_relation TEXT,
      subject_person_id BIGINT,
      subject_user_code INTEGER,
      period_start DATE,
      period_end DATE,
      actor_user_code INTEGER,
      actor_name TEXT,
      actor_role TEXT NOT NULL DEFAULT 'system',
      related JSONB NOT NULL DEFAULT '{}'::jsonb,
      occurred_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      CONSTRAINT chk_apartment_residency_log_event CHECK (event_type IN (${sqlList(RESIDENCY_EVENT_TYPES)})),
      CONSTRAINT chk_apartment_residency_log_reason CHECK (reason_code ~ '^[a-z][a-z0-9_]{1,39}$'),
      CONSTRAINT chk_apartment_residency_log_relation CHECK (subject_relation IS NULL OR subject_relation IN (${sqlList(RESIDENCY_RELATIONS)})),
      CONSTRAINT chk_apartment_residency_log_actor_role CHECK (actor_role IN (${sqlList(RESIDENCY_ACTOR_ROLES)})),
      CONSTRAINT chk_apartment_residency_log_subject_name CHECK (subject_name IS NULL OR char_length(subject_name) BETWEEN 1 AND 120),
      CONSTRAINT chk_apartment_residency_log_actor_name CHECK (actor_name IS NULL OR char_length(actor_name) BETWEEN 1 AND 120),
      CONSTRAINT chk_apartment_residency_log_label CHECK (apartment_label IS NULL OR char_length(apartment_label) BETWEEN 1 AND 80),
      CONSTRAINT chk_apartment_residency_log_period CHECK (period_start IS NULL OR period_end IS NULL OR period_end >= period_start),
      CONSTRAINT chk_apartment_residency_log_related CHECK (jsonb_typeof(related) = 'object' AND char_length(related::text) <= 600)
    )
  `,
  siteFk: foreignKeySql('site_code', 'sites', 'site_code', 'CASCADE'),
  apartmentIndex: `CREATE INDEX IF NOT EXISTS idx_apartment_residency_log_apartment ON apartment_residency_log (site_code, apartment_id, id DESC)`,
  siteIndex: `CREATE INDEX IF NOT EXISTS idx_apartment_residency_log_site ON apartment_residency_log (site_code, occurred_at DESC, id DESC)`,
  subjectIndex: `CREATE INDEX IF NOT EXISTS idx_apartment_residency_log_subject ON apartment_residency_log (subject_user_code) WHERE subject_user_code IS NOT NULL`,
  immutableFunction: `
    CREATE OR REPLACE FUNCTION trg_apartment_residency_log_immutable() RETURNS trigger AS $$
    -- ${RESIDENCY_LOG_MARKER}
    BEGIN
      IF TG_OP = 'DELETE' THEN
        IF NOT EXISTS (SELECT 1 FROM sites WHERE site_code = OLD.site_code) THEN
          RETURN OLD;
        END IF;
      END IF;
      RAISE EXCEPTION 'apartment residency log is append-only';
    END;
    $$ LANGUAGE plpgsql
  `,
  truncateFunction: `
    CREATE OR REPLACE FUNCTION trg_apartment_residency_log_block_truncate() RETURNS trigger AS $$
    -- ${RESIDENCY_LOG_MARKER}
    BEGIN
      RAISE EXCEPTION 'apartment residency log cannot be truncated';
    END;
    $$ LANGUAGE plpgsql
  `,
  // Kullanıcı satırı FİZİKSEL silinirken (süper kullanıcı hesap silme, daire sıfırlama) güncel daire bağlarını kayda geçirir. trg_users_preserve_site_people
  // ilişkileri kapatıp kişiyi hesaptan koparmadan ÖNCE çalışsın diye adı alfabetik olarak ondan önce gelir (l < p). Hata silmeyi ENGELLEMEZ (uyarı verir).
  usersFunction: `
    CREATE OR REPLACE FUNCTION trg_users_log_residencies() RETURNS trigger AS $$
    -- ${RESIDENCY_LOG_MARKER}
    BEGIN
      BEGIN
        INSERT INTO apartment_residency_log (
          site_code, apartment_id, apartment_label, event_type, reason_code, subject_name, subject_relation, subject_person_id,
          subject_user_code, period_start, period_end, actor_role, related
        )
        SELECT
          r.site_code,
          r.apartment_id,
          LEFT(btrim(CASE WHEN COALESCE(b.block_name, '') <> '' AND COALESCE(a.unit_label, '') <> '' THEN b.block_name || ' - ' || a.unit_label ELSE COALESCE(NULLIF(b.block_name, ''), a.unit_label, '') END), 80),
          'moved_out',
          'account_deleted',
          LEFT(NULLIF(btrim(COALESCE(NULLIF(OLD.full_name, ''), sp.full_name, '')), ''), 120),
          r.relation,
          sp.id,
          OLD.user_code,
          r.move_in_date,
          GREATEST(CURRENT_DATE, r.move_in_date),
          'system',
          jsonb_build_object('residency_id', r.id)
        FROM apartment_residencies r
        INNER JOIN site_people sp ON sp.id = r.person_id
        LEFT JOIN apartments a ON a.id = r.apartment_id
        LEFT JOIN site_blocks b ON b.id = a.block_id
        WHERE sp.user_code = OLD.user_code AND r.is_current;
      EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'apartment_residency_log yazilamadi: %', SQLERRM;
      END;
      RETURN OLD;
    END;
    $$ LANGUAGE plpgsql
  `,
  immutableTrigger: triggerSql(
    'trg_apartment_residency_log_immutable',
    'apartment_residency_log',
    'BEFORE UPDATE OR DELETE ON apartment_residency_log FOR EACH ROW EXECUTE PROCEDURE trg_apartment_residency_log_immutable()',
  ),
  truncateTrigger: triggerSql(
    'trg_apartment_residency_log_no_truncate',
    'apartment_residency_log',
    'BEFORE TRUNCATE ON apartment_residency_log FOR EACH STATEMENT EXECUTE PROCEDURE trg_apartment_residency_log_block_truncate()',
  ),
  usersTrigger: triggerSql(
    'trg_users_log_residencies',
    'users',
    'BEFORE DELETE ON users FOR EACH ROW EXECUTE PROCEDURE trg_users_log_residencies()',
  ),
});

/** İfade adı -> { tablo | fk | indeks | işlev | tetikleyici }. Sıra RESIDENCY_LOG_DDL ile aynıdır. */
const STEPS = Object.freeze([
  ['logTable', { table: 'apartment_residency_log' }],
  ['siteFk', { fk: 'apartment_residency_log_site_code_fkey', on: 'apartment_residency_log' }],
  ['apartmentIndex', { index: 'idx_apartment_residency_log_apartment', on: 'apartment_residency_log' }],
  ['siteIndex', { index: 'idx_apartment_residency_log_site', on: 'apartment_residency_log' }],
  ['subjectIndex', { index: 'idx_apartment_residency_log_subject', on: 'apartment_residency_log' }],
  ['immutableFunction', { fn: 'trg_apartment_residency_log_immutable' }],
  ['truncateFunction', { fn: 'trg_apartment_residency_log_block_truncate' }],
  ['usersFunction', { fn: 'trg_users_log_residencies' }],
  ['immutableTrigger', { trigger: 'trg_apartment_residency_log_immutable', on: 'apartment_residency_log' }],
  ['truncateTrigger', { trigger: 'trg_apartment_residency_log_no_truncate', on: 'apartment_residency_log' }],
  ['usersTrigger', { trigger: 'trg_users_log_residencies', on: 'users' }],
]);

export const RESIDENCY_LOG_DDL_ORDER = Object.freeze(STEPS.map(([name]) => name));

const RETRYABLE = new Set(['40P01', '55P03']);
/** Test ayarı: yeniden deneme beklemesi (ms) çarpanı. */
export const schemaTuning = { retryDelayMs: 300 };

/** Tek DDL ifadesi; 40P01 / 55P03'te (yalnız ilk dağıtım, yoğun yazma) en çok 6 deneme, artan bekleme. İfade tek başına otomatik onaylıdır. */
async function runDdl(client, statement) {
  for (let attempt = 1; ; attempt += 1) {
    try {
      await client.query(statement);
      return;
    } catch (error) {
      if (!RETRYABLE.has(error?.code) || attempt >= 6) throw error;
      await new Promise((resolve) => setTimeout(resolve, schemaTuning.retryDelayMs * attempt));
    }
  }
}

/**
 * 075'i uygular (db.js ensureDbSchema bloğu BİTTİKTEN sonra çağrılır). Tek katalog sorgusuyla eksik nesneler belirlenir; yalnız eksikler, sırayla ve kendi
 * otomatik onaylı ifadeleriyle çalışır. Her şey varsa (normal açılış) hiçbir ifade gönderilmez: kilit alınmaz.
 */
export async function ensureResidencyLogSchema(client) {
  const indexes = STEPS.filter(([, spec]) => spec.index).map(([, spec]) => spec.index);
  const foreignKeys = STEPS.filter(([, spec]) => spec.fk).map(([, spec]) => spec.fk);
  const functions = STEPS.filter(([, spec]) => spec.fn).map(([, spec]) => spec.fn);
  const triggers = STEPS.filter(([, spec]) => spec.trigger).map(([, spec]) => spec.trigger);
  const found = await client.query(
    `
      SELECT
        ARRAY(SELECT t FROM unnest($1::TEXT[]) AS t WHERE to_regclass('public.' || t) IS NOT NULL) AS tables,
        ARRAY(SELECT indexname::TEXT FROM pg_indexes WHERE schemaname = 'public' AND indexname = ANY($2::TEXT[])) AS indexes,
        ARRAY(
          SELECT (SELECT r.relname::TEXT FROM pg_class r WHERE r.oid = c.conrelid) || '.' || c.conname::TEXT
          FROM pg_constraint c
          WHERE c.contype = 'f' AND c.connamespace = 'public'::regnamespace AND c.conname = ANY($3::TEXT[])
        ) AS fks,
        ARRAY(
          SELECT p.proname::TEXT FROM pg_proc p
          WHERE p.pronamespace = 'public'::regnamespace AND p.proname = ANY($4::TEXT[]) AND p.prosrc LIKE '%' || $6 || '%'
        ) AS functions,
        ARRAY(
          SELECT g.tgname::TEXT FROM pg_trigger g
          WHERE NOT g.tgisinternal AND g.tgname = ANY($5::TEXT[])
        ) AS triggers
    `,
    [['apartment_residency_log', 'users'], indexes, foreignKeys, functions, triggers, RESIDENCY_LOG_MARKER],
  );
  const row = found.rows[0] ?? {};
  const presentTables = new Set(row.tables ?? []);
  const presentIndexes = new Set(row.indexes ?? []);
  const presentFks = new Set(row.fks ?? []);
  const presentFunctions = new Set(row.functions ?? []);
  const presentTriggers = new Set(row.triggers ?? []);
  const isPending = (spec) => {
    if (spec.table) return !presentTables.has(spec.table);
    if (spec.fk) return !presentFks.has(`${spec.on}.${spec.fk}`);
    if (spec.index) return !presentIndexes.has(spec.index);
    if (spec.fn) return !presentFunctions.has(spec.fn);
    return !presentTriggers.has(spec.trigger);
  };
  // Eksik nesne yoksa (her normal açılış) hiçbir ifade gönderilmez: kilit alınmaz.
  if (!STEPS.some(([, spec]) => isPending(spec))) {
    return;
  }
  // Kilit kuyruğunda sonsuza dek beklemesin: 2 sn sonra 55P03, runDdl yeniden dener.
  await client.query("SET lock_timeout = '2s'");
  try {
    for (const [name, spec] of STEPS) {
      if (!isPending(spec)) continue;
      if ((spec.fk || spec.index || spec.trigger) && !presentTables.has(spec.on)) continue;
      await runDdl(client, RESIDENCY_LOG_DDL[name]);
      if (spec.table) presentTables.add(spec.table);
      else if (spec.fk) presentFks.add(`${spec.on}.${spec.fk}`);
      else if (spec.index) presentIndexes.add(spec.index);
      else if (spec.fn) presentFunctions.add(spec.fn);
      else presentTriggers.add(spec.trigger);
    }
  } finally {
    await client.query('RESET lock_timeout').catch(() => {});
  }
}
