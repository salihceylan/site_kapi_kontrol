// Dekont bildirimi (geçici kabul) şeması: 066. migrations/066_payment_notices.sql ile AYNI ifadeler, AYNI sırada (test: payment_notices).
// Tek yeni tablo (ekleyici): payment_notices. Tablo FK'SIZ oluşturulur; FK'ler yalnız tablo bu çağrıda oluşturulduysa ayrı, katalog korumalı ALTER ile eklenir
// (açılış deadlock dersi: bkz. device_integrations_schema.js). Tetikleyici: onay/ret/geri çekme sonrası satır DEĞİŞTİRİLEMEZ (yalnız resident_seen_at) ve yalnız
// izinli durum geçişlerine izin verilir. Onaylı bildirimin defter satırı ledger_entries FK'siyle (RESTRICT) korunur. Bu dosya db.js'i İÇE AKTARMAZ.

function fk(table, column, parent, parentColumn, onDelete) {
  const name = `${table}_${column}_fkey`;
  const action = onDelete ? ` ON DELETE ${onDelete}` : '';
  return `
    DO $$
    BEGIN
      IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = '${name}' AND conrelid = '${table}'::regclass) THEN
        ALTER TABLE ${table} ADD CONSTRAINT ${name} FOREIGN KEY (${column}) REFERENCES ${parent}(${parentColumn})${action};
      END IF;
    END $$
  `;
}

/** Sıra BAĞLAYICIDIR (migration ile aynı). */
export const PAYMENT_NOTICES_DDL = Object.freeze({
  table: `
    CREATE TABLE IF NOT EXISTS payment_notices (
      id BIGSERIAL PRIMARY KEY,
      site_code BIGINT NOT NULL,
      apartment_id BIGINT NOT NULL,
      account_party TEXT NOT NULL,
      origin TEXT NOT NULL,
      submitted_by INTEGER,
      amount_minor BIGINT NOT NULL,
      paid_on DATE NOT NULL,
      method TEXT NOT NULL DEFAULT 'transfer',
      sender_name TEXT,
      sender_iban TEXT,
      description TEXT,
      note TEXT,
      status TEXT NOT NULL DEFAULT 'uploading',
      file_required BOOLEAN NOT NULL DEFAULT TRUE,
      storage_key TEXT,
      display_name TEXT,
      mime_type TEXT,
      size_bytes BIGINT,
      sha256 TEXT,
      file_completed_at TIMESTAMPTZ,
      submitted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      decided_by INTEGER,
      decided_at TIMESTAMPTZ,
      reject_reason_code TEXT,
      reject_note TEXT,
      ledger_entry_id BIGINT,
      linked_existing BOOLEAN NOT NULL DEFAULT FALSE,
      resident_seen_at TIMESTAMPTZ,
      idempotency_key TEXT,
      request_fingerprint TEXT,
      CONSTRAINT chk_payment_notices_party CHECK (account_party IN ('owner', 'tenant')),
      CONSTRAINT chk_payment_notices_origin CHECK (origin IN ('resident_app', 'resident_share', 'manager')),
      CONSTRAINT chk_payment_notices_amount CHECK (amount_minor > 0),
      CONSTRAINT chk_payment_notices_method CHECK (method IN ('transfer', 'cash', 'cheque')),
      CONSTRAINT chk_payment_notices_status CHECK (status IN ('uploading', 'pending', 'approved', 'rejected', 'withdrawn')),
      CONSTRAINT chk_payment_notices_iban CHECK (sender_iban IS NULL OR sender_iban ~ '^TR[0-9]{24}$'),
      CONSTRAINT chk_payment_notices_mime CHECK (mime_type IS NULL OR mime_type IN ('application/pdf', 'image/jpeg', 'image/png')),
      CONSTRAINT chk_payment_notices_size CHECK (size_bytes IS NULL OR size_bytes BETWEEN 1 AND 10485760),
      CONSTRAINT chk_payment_notices_sha256 CHECK (sha256 IS NULL OR sha256 ~ '^[0-9a-f]{64}$'),
      CONSTRAINT chk_payment_notices_text CHECK (
        (sender_name IS NULL OR char_length(sender_name) <= 80) AND (description IS NULL OR char_length(description) <= 200)
        AND (note IS NULL OR char_length(note) <= 300) AND (reject_note IS NULL OR char_length(reject_note) <= 300)
      ),
      CONSTRAINT chk_payment_notices_reason CHECK (
        reject_reason_code IS NULL OR reject_reason_code IN ('not_received', 'amount_mismatch', 'wrong_apartment', 'duplicate', 'unreadable', 'other')
      ),
      CONSTRAINT chk_payment_notices_approved CHECK (status <> 'approved' OR ledger_entry_id IS NOT NULL),
      CONSTRAINT chk_payment_notices_rejected CHECK (status <> 'rejected' OR reject_reason_code IS NOT NULL),
      CONSTRAINT chk_payment_notices_file CHECK (NOT file_required OR status IN ('uploading', 'withdrawn') OR file_completed_at IS NOT NULL)
    )
  `,
  siteFk: fk('payment_notices', 'site_code', 'sites', 'site_code', 'CASCADE'),
  apartmentFk: fk('payment_notices', 'apartment_id', 'apartments', 'id', 'CASCADE'),
  submitterFk: fk('payment_notices', 'submitted_by', 'users', 'user_code', 'SET NULL'),
  deciderFk: fk('payment_notices', 'decided_by', 'users', 'user_code', 'SET NULL'),
  ledgerFk: fk('payment_notices', 'ledger_entry_id', 'ledger_entries', 'id', null),
  siteStatusIndex: `CREATE INDEX IF NOT EXISTS idx_payment_notices_site_status ON payment_notices (site_code, status, id DESC)`,
  apartmentIndex: `CREATE INDEX IF NOT EXISTS idx_payment_notices_apartment ON payment_notices (apartment_id, status)`,
  submitterIndex: `CREATE INDEX IF NOT EXISTS idx_payment_notices_submitter ON payment_notices (submitted_by, id DESC) WHERE submitted_by IS NOT NULL`,
  shaIndex: `CREATE INDEX IF NOT EXISTS idx_payment_notices_sha ON payment_notices (site_code, sha256) WHERE sha256 IS NOT NULL`,
  storageKeyIndex: `CREATE UNIQUE INDEX IF NOT EXISTS uq_payment_notices_storage_key ON payment_notices (storage_key) WHERE storage_key IS NOT NULL`,
  ledgerIndex: `CREATE UNIQUE INDEX IF NOT EXISTS uq_payment_notices_ledger ON payment_notices (ledger_entry_id) WHERE ledger_entry_id IS NOT NULL`,
  idempotencyIndex: `CREATE UNIQUE INDEX IF NOT EXISTS uq_payment_notices_idempotency ON payment_notices (site_code, apartment_id, idempotency_key) WHERE idempotency_key IS NOT NULL`,
  guardFunction: `
    CREATE OR REPLACE FUNCTION trg_payment_notices_guard() RETURNS trigger AS $$
    BEGIN
      IF NEW.site_code <> OLD.site_code OR NEW.apartment_id <> OLD.apartment_id OR NEW.amount_minor <> OLD.amount_minor
         OR NEW.paid_on <> OLD.paid_on OR NEW.origin <> OLD.origin THEN
        RAISE EXCEPTION 'payment_notices: daire, tutar, tarih ve kaynak degistirilemez' USING ERRCODE = '23514';
      END IF;
      IF OLD.status IN ('approved', 'rejected', 'withdrawn') THEN
        IF (to_jsonb(NEW) - 'resident_seen_at' - 'submitted_by' - 'decided_by') IS DISTINCT FROM (to_jsonb(OLD) - 'resident_seen_at' - 'submitted_by' - 'decided_by') THEN
          RAISE EXCEPTION 'payment_notices: karara baglanmis bildirim degistirilemez' USING ERRCODE = '23514';
        END IF;
      ELSIF NEW.status <> OLD.status THEN
        IF NOT ((OLD.status = 'uploading' AND NEW.status IN ('pending', 'withdrawn'))
             OR (OLD.status = 'pending' AND NEW.status IN ('approved', 'rejected', 'withdrawn'))) THEN
          RAISE EXCEPTION 'payment_notices: gecersiz durum gecisi' USING ERRCODE = '23514';
        END IF;
      END IF;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql
  `,
  guardTrigger: `
    DO $$
    BEGIN
      IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_payment_notices_guard' AND tgrelid = 'payment_notices'::regclass) THEN
        CREATE TRIGGER trg_payment_notices_guard BEFORE UPDATE ON payment_notices FOR EACH ROW EXECUTE FUNCTION trg_payment_notices_guard();
      END IF;
    END $$
  `,
});

const STEPS = Object.freeze([
  ['table', { table: 'payment_notices' }],
  ['siteFk', { fkOf: 'payment_notices' }],
  ['apartmentFk', { fkOf: 'payment_notices' }],
  ['submitterFk', { fkOf: 'payment_notices' }],
  ['deciderFk', { fkOf: 'payment_notices' }],
  ['ledgerFk', { fkOf: 'payment_notices' }],
  ['siteStatusIndex', { index: 'idx_payment_notices_site_status' }],
  ['apartmentIndex', { index: 'idx_payment_notices_apartment' }],
  ['submitterIndex', { index: 'idx_payment_notices_submitter' }],
  ['shaIndex', { index: 'idx_payment_notices_sha' }],
  ['storageKeyIndex', { index: 'uq_payment_notices_storage_key' }],
  ['ledgerIndex', { index: 'uq_payment_notices_ledger' }],
  ['idempotencyIndex', { index: 'uq_payment_notices_idempotency' }],
  ['guardFunction', { fkOf: 'payment_notices' }],
  ['guardTrigger', { fkOf: 'payment_notices' }],
]);

export const PAYMENT_NOTICES_DDL_ORDER = Object.freeze(STEPS.map(([name]) => name));

/** Eksik nesneleri sırayla, her biri kendi otomatik onaylı ifadesiyle oluşturur; her şey varsa hiçbir ifade gönderilmez. */
export async function ensurePaymentNoticesSchema(client) {
  const indexes = STEPS.filter(([, s]) => s.index).map(([, s]) => s.index);
  const found = await client.query(
    `SELECT
       to_regclass('public.payment_notices') IS NOT NULL AS has_table,
       ARRAY(SELECT indexname::TEXT FROM pg_indexes WHERE schemaname = 'public' AND indexname = ANY($1::TEXT[])) AS indexes`,
    [indexes],
  );
  const hadTable = found.rows[0]?.has_table === true;
  const hadIndexes = new Set(found.rows[0]?.indexes ?? []);
  if (hadTable && indexes.every((i) => hadIndexes.has(i))) return;
  await client.query("SET lock_timeout = '2s'");
  try {
    let created = false;
    for (const [name, spec] of STEPS) {
      if (spec.table) {
        if (hadTable) continue;
        await client.query(PAYMENT_NOTICES_DDL[name]);
        created = true;
      } else if (spec.fkOf) {
        if (created) await client.query(PAYMENT_NOTICES_DDL[name]);
      } else if (!hadIndexes.has(spec.index)) {
        await client.query(PAYMENT_NOTICES_DDL[name]);
      }
    }
  } finally {
    await client.query('RESET lock_timeout').catch(() => {});
  }
}
