// Karar Defteri şeması: 050. migrations/050_decision_book.sql ile AYNI ifadeler, AYNI sırayla (test: decision_book_schema).
//
// Tek yeni tablo (ekleyici): board_decisions. Mevcut tablolara sütun/indeks EKLENMEZ.
// Açılış deadlock'u dersi (R2 F-1 / R11 F1, bkz. document_schema.js / work_tracking_schema.js): ifadeler db.js'te dev ensureDbSchema bloğu BİTTİKTEN sonra, katalog
// kontrolüyle ve her biri kendi otomatik onaylı ifadesiyle yalnız EKSİK olanlar için çalışır; her şey varsa hiçbir tabloda kilit alınmaz. Tablo FK'SIZ oluşturulur;
// her FK ayrı, katalog korumalı `ALTER TABLE ... ADD CONSTRAINT <tablo>_<sütun>_fkey` ifadesidir (ifade başına TEK üst tablo; sites / users sıcaktır).
// Silme politikası: site silinince kararlar CASCADE (kesin kararlar dahil); kullanıcı silinince created_by / finalized_by SET NULL (karar kalır; ad "Silinmiş Kullanıcı").
// supersedes_id: (site_code, supersedes_id) -> (site_code, id) BİLEŞİK FK; değiştirilen karar AYNI sitede olmak zorundadır (veritabanı düzeyinde de).
//
// DEĞİŞMEZLİK (trg_board_decisions_immutable, finans değişmez tablolarıyla aynı yaklaşım, bkz. finance_4b_schema.js trg_finance_immutable):
//  - 'kesin' satır UPDATE edilemez; TEK istisna: created_by / finalized_by sütunlarından BİRİ NULL'a iner, o kullanıcı artık YOKTUR ve başka hiçbir sütun değişmez
//    (users satırı silinince ON DELETE SET NULL eylemi).
//  - 'kesin' satır DELETE edilemez; TEK istisna: üst sites satırı artık YOK (site silme CASCADE). Taslaklar serbestçe değiştirilir / silinir.
//  - TRUNCATE her durumda engellenir (trg_board_decisions_no_truncate).
// İşlev gövdeleri sürüm işareti taşır (DECISION_BOOK_MARKER): işaret değişirse ensure işlevi yeniler (CREATE OR REPLACE).
// Bu dosya db.js'i İÇE AKTARMAZ (döngü olmasın).

/** İşlev gövdesine yazılan sürüm işareti (katalog `prosrc` aranır). */
export const DECISION_BOOK_MARKER = 'dbk:1';

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

/** Sıra BAĞLAYICIDIR (migration ile aynı): tablo -> FK'ler -> indeksler -> işlevler -> tetikleyiciler. */
export const DECISION_BOOK_DDL = Object.freeze({
  decisionsTable: `
    CREATE TABLE IF NOT EXISTS board_decisions (
      id BIGSERIAL PRIMARY KEY,
      site_code BIGINT NOT NULL,
      year INTEGER NOT NULL,
      decision_no INTEGER,
      meeting_type TEXT NOT NULL,
      meeting_date DATE NOT NULL,
      title TEXT NOT NULL,
      body TEXT NOT NULL,
      attendees TEXT,
      vote_result TEXT NOT NULL,
      votes_for INTEGER,
      votes_against INTEGER,
      votes_abstain INTEGER,
      visibility TEXT NOT NULL DEFAULT 'yonetim',
      status TEXT NOT NULL DEFAULT 'taslak',
      finalized_at TIMESTAMPTZ,
      finalized_by INTEGER,
      supersedes_id BIGINT,
      created_by INTEGER,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      CONSTRAINT uq_board_decisions_site_id UNIQUE (site_code, id),
      CONSTRAINT chk_board_decisions_meeting_type CHECK (meeting_type IN ('yonetim_kurulu', 'genel_kurul', 'denetim_kurulu', 'diger')),
      CONSTRAINT chk_board_decisions_vote_result CHECK (vote_result IN ('kabul', 'ret', 'ertelendi', 'bilgi')),
      CONSTRAINT chk_board_decisions_visibility CHECK (visibility IN ('yonetim', 'sakinler')),
      CONSTRAINT chk_board_decisions_status CHECK (status IN ('taslak', 'kesin')),
      CONSTRAINT chk_board_decisions_title_length CHECK (char_length(title) BETWEEN 1 AND 160),
      CONSTRAINT chk_board_decisions_body_length CHECK (char_length(body) BETWEEN 1 AND 10000),
      CONSTRAINT chk_board_decisions_attendees_length CHECK (attendees IS NULL OR char_length(attendees) BETWEEN 1 AND 2000),
      CONSTRAINT chk_board_decisions_votes CHECK ((votes_for IS NULL OR votes_for >= 0) AND (votes_against IS NULL OR votes_against >= 0) AND (votes_abstain IS NULL OR votes_abstain >= 0)),
      CONSTRAINT chk_board_decisions_year CHECK (year BETWEEN 1900 AND 2200 AND year = EXTRACT(YEAR FROM meeting_date)),
      CONSTRAINT chk_board_decisions_decision_no CHECK (decision_no IS NULL OR decision_no > 0),
      CONSTRAINT chk_board_decisions_final CHECK ((status = 'kesin') = (decision_no IS NOT NULL) AND (status = 'kesin') = (finalized_at IS NOT NULL)),
      CONSTRAINT chk_board_decisions_supersedes_self CHECK (supersedes_id IS NULL OR supersedes_id <> id)
    )
  `,
  decisionsSiteFk: foreignKeySql('board_decisions', 'site_code', 'sites', 'site_code', 'CASCADE'),
  decisionsCreatedByFk: foreignKeySql('board_decisions', 'created_by', 'users', 'user_code', 'SET NULL'),
  decisionsFinalizedByFk: foreignKeySql('board_decisions', 'finalized_by', 'users', 'user_code', 'SET NULL'),
  // Bileşik öz-başvuru: değiştirilen karar aynı sitede olmalı. NO ACTION: kesin karar zaten silinemez; site silmede tüm satırlar aynı ifadede gider.
  decisionsSupersedesFk: `
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'board_decisions_supersedes_id_fkey' AND conrelid = 'board_decisions'::regclass
      ) THEN
        ALTER TABLE board_decisions ADD CONSTRAINT board_decisions_supersedes_id_fkey FOREIGN KEY (site_code, supersedes_id) REFERENCES board_decisions(site_code, id) ON DELETE NO ACTION;
      END IF;
    END $$
  `,
  decisionsNumberIndex: `CREATE UNIQUE INDEX IF NOT EXISTS uq_board_decisions_number ON board_decisions (site_code, year, decision_no) WHERE decision_no IS NOT NULL`,
  decisionsDraftsIndex: `CREATE INDEX IF NOT EXISTS idx_board_decisions_drafts ON board_decisions (site_code, year DESC, id DESC) WHERE status = 'taslak'`,
  decisionsSupersedesIndex: `CREATE INDEX IF NOT EXISTS idx_board_decisions_supersedes ON board_decisions (site_code, supersedes_id) WHERE supersedes_id IS NOT NULL`,
  decisionsCreatedByIndex: `CREATE INDEX IF NOT EXISTS idx_board_decisions_created_by ON board_decisions (created_by) WHERE created_by IS NOT NULL`,
  decisionsFinalizedByIndex: `CREATE INDEX IF NOT EXISTS idx_board_decisions_finalized_by ON board_decisions (finalized_by) WHERE finalized_by IS NOT NULL`,
  immutableFunction: `
    CREATE OR REPLACE FUNCTION trg_board_decisions_immutable() RETURNS trigger AS $$
    -- ${DECISION_BOOK_MARKER}
    DECLARE
      col TEXT;
      old_json JSONB;
      new_json JSONB;
    BEGIN
      IF OLD.status <> 'kesin' THEN
        IF TG_OP = 'DELETE' THEN
          RETURN OLD;
        END IF;
        RETURN NEW;
      END IF;
      IF TG_OP = 'DELETE' THEN
        IF NOT EXISTS (SELECT 1 FROM sites WHERE site_code = OLD.site_code) THEN
          RETURN OLD;
        END IF;
      ELSIF TG_OP = 'UPDATE' THEN
        old_json := to_jsonb(OLD);
        new_json := to_jsonb(NEW);
        FOREACH col IN ARRAY ARRAY['created_by', 'finalized_by'] LOOP
          IF (old_json ->> col) IS NOT NULL AND (new_json ->> col) IS NULL
             AND NOT EXISTS (SELECT 1 FROM users WHERE user_code = (old_json ->> col)::INTEGER)
             AND (new_json - col) = (old_json - col) THEN
            RETURN NEW;
          END IF;
        END LOOP;
      END IF;
      RAISE EXCEPTION 'final board decisions are immutable';
    END;
    $$ LANGUAGE plpgsql
  `,
  truncateFunction: `
    CREATE OR REPLACE FUNCTION trg_board_decisions_block_truncate() RETURNS trigger AS $$
    -- ${DECISION_BOOK_MARKER}
    BEGIN
      RAISE EXCEPTION 'board decisions cannot be truncated';
    END;
    $$ LANGUAGE plpgsql
  `,
  immutableTrigger: triggerSql(
    'trg_board_decisions_immutable',
    'board_decisions',
    'BEFORE UPDATE OR DELETE ON board_decisions FOR EACH ROW EXECUTE PROCEDURE trg_board_decisions_immutable()',
  ),
  truncateTrigger: triggerSql(
    'trg_board_decisions_no_truncate',
    'board_decisions',
    'BEFORE TRUNCATE ON board_decisions FOR EACH STATEMENT EXECUTE PROCEDURE trg_board_decisions_block_truncate()',
  ),
});

/**
 * İfade adı -> { tablo | fk | indeks | işlev | tetikleyici }. Sıra DECISION_BOOK_DDL ile aynıdır. `parent`: FK adımı için başvurulan tablo (sites / users her zaman
 * vardır; öz-başvuru tablonun kendisidir).
 */
const STEPS = Object.freeze([
  ['decisionsTable', { table: 'board_decisions' }],
  ['decisionsSiteFk', { fk: 'board_decisions_site_code_fkey', on: 'board_decisions', parent: 'sites' }],
  ['decisionsCreatedByFk', { fk: 'board_decisions_created_by_fkey', on: 'board_decisions', parent: 'users' }],
  ['decisionsFinalizedByFk', { fk: 'board_decisions_finalized_by_fkey', on: 'board_decisions', parent: 'users' }],
  ['decisionsSupersedesFk', { fk: 'board_decisions_supersedes_id_fkey', on: 'board_decisions', parent: 'board_decisions' }],
  ['decisionsNumberIndex', { index: 'uq_board_decisions_number', on: 'board_decisions' }],
  ['decisionsDraftsIndex', { index: 'idx_board_decisions_drafts', on: 'board_decisions' }],
  ['decisionsSupersedesIndex', { index: 'idx_board_decisions_supersedes', on: 'board_decisions' }],
  ['decisionsCreatedByIndex', { index: 'idx_board_decisions_created_by', on: 'board_decisions' }],
  ['decisionsFinalizedByIndex', { index: 'idx_board_decisions_finalized_by', on: 'board_decisions' }],
  ['immutableFunction', { fn: 'trg_board_decisions_immutable' }],
  ['truncateFunction', { fn: 'trg_board_decisions_block_truncate' }],
  ['immutableTrigger', { trigger: 'trg_board_decisions_immutable', on: 'board_decisions' }],
  ['truncateTrigger', { trigger: 'trg_board_decisions_no_truncate', on: 'board_decisions' }],
]);

export const DECISION_BOOK_DDL_ORDER = Object.freeze(STEPS.map(([name]) => name));

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
 * 050'yi uygular (db.js ensureDbSchema bloğu BİTTİKTEN sonra çağrılır). Tek katalog sorgusuyla eksik nesneler (tablo, FK, indeks, işaretli işlev, tetikleyici)
 * belirlenir; yalnız eksikler, sırayla ve kendi otomatik onaylı ifadeleriyle çalışır. Her şey varsa (normal açılış) hiçbir ifade gönderilmez: kilit alınmaz.
 */
export async function ensureDecisionBookSchema(client) {
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
          WHERE NOT g.tgisinternal AND g.tgrelid = to_regclass('public.board_decisions') AND g.tgname = ANY($5::TEXT[])
        ) AS triggers
    `,
    [['board_decisions'], indexes, foreignKeys, functions, triggers, DECISION_BOOK_MARKER],
  );
  const row = found.rows[0] ?? {};
  const presentTables = new Set(row.tables ?? []);
  const presentIndexes = new Set(row.indexes ?? []);
  const presentFks = new Set(row.fks ?? []);
  const presentFunctions = new Set(row.functions ?? []);
  const presentTriggers = new Set(row.triggers ?? []);
  const hasParent = (parent) => parent === 'sites' || parent === 'users' || presentTables.has(parent);
  const fkPresent = (spec) => presentFks.has(`${spec.on}.${spec.fk}`);
  const isPending = (spec) => {
    if (spec.table) return !presentTables.has(spec.table);
    if (spec.fk) return !fkPresent(spec);
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
      if (spec.fk && (!presentTables.has(spec.on) || !hasParent(spec.parent))) continue;
      if ((spec.index || spec.trigger) && !presentTables.has(spec.on)) continue;
      await runDdl(client, DECISION_BOOK_DDL[name]);
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
