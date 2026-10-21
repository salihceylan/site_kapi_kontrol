// Toplu yükleme (Faz 2b): önizleme ve onay (commit) iş akışı.
//
// Sözleşme: docs/PLATFORM_TOPLU_ISLEMLER.md. İki adım zorunlu: önizleme YAZMAZ (REPEATABLE READ READ ONLY anlık görüntü); commit önizlemeyi kilit altında
// YENİDEN hesaplar ve `expected_hash` uyuşmazsa 409 PREVIEW_STALE (hiçbir şey yazılmaz). Dosya ve ham satırlar SAKLANMAZ; çalıştırma kaydı kişisel veri
// taşımaz. Kilit sırası (PLATFORM_KISILER madde 16 + PLATFORM_FINANS madde 6 ile uyumlu):
//   sites FOR KEY SHARE -> bulk_import:<site> (try-lock) -> people_sync:<site> -> [apartments türü: finance_post:<site>] -> apartments (id sırasıyla)
//   -> users (işlemi yapan, FOR KEY SHARE) -> CRM satırları -> bulk_import_runs / audit_log. Nadir 40P01'de TEK yeniden deneme.

import { pool } from '../db.js';
import { actorFromAuthUser } from './audit_service.js';
import { PlatformError } from './errors.js';
import { financeLockKey } from './finance_common.js';
import { assertFinanceEnabled } from './finance_access.js';
import { assertWritableDate } from './finance_4b_guard.js';
import { requestFingerprint, validateImportBody } from './bulk_import_body.js';
import { computePlan, collectApartmentIds } from './bulk_import_plan.js';
import { loadBlocksAndApartments, loadSnapshot } from './bulk_import_snapshot.js';
import { KIND_MODULE, SPEC_VERSION, isImportDisabled } from './bulk_import_spec.js';
import { ENTITY_CHUNK, applyApartmentOps, applyOpeningOps, applyPeopleOps, insertAudits } from './bulk_import_writer.js';
import { todayIso } from './people_common.js';
import { peopleLockKey } from './people_sync.js';
import { runSyncSteps } from './people_sync_sql.js';

export const bulkImportLockKey = (siteCode) => `bulk_import:${Number(siteCode)}`;

const LOCK_TIMEOUT = '8s';
/** Kişi eşitlemesi (CRM) gereken türler; finans kilidi gereken türler; daire satırı yazan türler. */
const SYNC_KINDS = new Set(['people', 'vehicles', 'all_in_one']);
const FINANCE_LOCK_KINDS = new Set(['apartments', 'all_in_one', 'opening_balances']);
const APARTMENT_WRITE_KINDS = new Set(['apartments', 'all_in_one']);
const totalError = (plan, expected) =>
  new PlatformError(409, 'TOTAL_MISMATCH', 'Toplam tutar onaylanan tutarla uyuşmuyor. Önizleme yenilendi, tekrar inceleyin.', {
    totals: plan.totals,
    plan: plan.counts,
    preview_hash: plan.previewHash,
    expected_total_minor: expected,
  });
const MAX_CONCURRENT_COMMITS = 2;
const MAX_CONCURRENT_PREVIEWS = 4;
const gauge = { commits: 0, previews: 0 };

export const siteBusy = () =>
  new PlatformError(409, 'SITE_BUSY', 'Site kayıtları şu an başka bir işlemde, biraz sonra tekrar deneyin.');
const importInProgress = () => new PlatformError(409, 'IMPORT_IN_PROGRESS', 'Bu site için başka bir yükleme sürüyor.');
const serverBusy = () => new PlatformError(409, 'IMPORT_IN_PROGRESS', 'Sunucuda başka yüklemeler sürüyor, biraz sonra tekrar deneyin.');
const siteNotFound = () => new PlatformError(404, 'SITE_NOT_FOUND', 'Site bulunamadı.');
const importDisabled = () => new PlatformError(503, 'IMPORT_DISABLED', 'Toplu işlemler geçici olarak kapalı.');

/** Test için sayaçları sıfırlar. */
export function resetBulkImportGauge() {
  gauge.commits = 0;
  gauge.previews = 0;
}

async function rollbackQuietly(client) {
  try {
    await client.query('ROLLBACK');
  } catch (_error) {
    // bağlantı zaten kopmuş olabilir; asıl hata yukarıda fırlatılır
  }
}

/** Kilit bekleme üst sınırı aşıldı (55P03) -> 409 SITE_BUSY. */
function mapLockTimeout(error) {
  if (error?.code === '55P03') {
    return siteBusy();
  }
  return error;
}

// ---------------------------------------------------------------------------------------------------------------
// Önizleme
// ---------------------------------------------------------------------------------------------------------------

/** Önizleme öncesi CRM'i erişim üyelikleriyle eşitler (kilit bekleme üst sınırı 8 sn; aşılırsa 409 SITE_BUSY). */
async function syncBeforePreview(siteCode) {
  const attempt = async () => {
    const client = await pool.connect();
    let began = false;
    try {
      await client.query('BEGIN');
      began = true;
      await client.query(`SET LOCAL lock_timeout = '${LOCK_TIMEOUT}'`);
      await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', [peopleLockKey(siteCode)]);
      await runSyncSteps(client, { siteCode, userCode: null });
      await client.query('COMMIT');
    } catch (error) {
      if (began) await rollbackQuietly(client);
      throw error;
    } finally {
      client.release();
    }
  };
  try {
    await attempt();
  } catch (error) {
    if (error?.code === '40P01') {
      try {
        await attempt();
      } catch (retryError) {
        throw mapLockTimeout(retryError);
      }
      return;
    }
    throw mapLockTimeout(error);
  }
}

/**
 * POST imports/:kind/preview. YAZMAZ (eşitleme adımı hariç: mevcut üyelikleri CRM'e yansıtan idempotent adım).
 * @returns {Promise<object>} önizleme gövdesi
 */
export async function previewImport({ siteCode, kind, body, env = process.env }) {
  if (isImportDisabled(env)) throw importDisabled();
  const parsed = validateImportBody(body, kind, { commit: false, env });
  if (gauge.previews >= MAX_CONCURRENT_PREVIEWS) throw serverBusy();
  gauge.previews += 1;
  try {
    if (KIND_MODULE[kind]) {
      await assertFinanceEnabled(siteCode, pool);
    }
    if (SYNC_KINDS.has(kind)) {
      await syncBeforePreview(siteCode);
    }
    const client = await pool.connect();
    let began = false;
    try {
      await client.query('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY');
      began = true;
      const exists = await client.query(`SELECT 1 FROM sites WHERE site_code = $1`, [siteCode]);
      if (!exists.rows[0]) throw siteNotFound();
      const snapshot = await loadSnapshot(client, siteCode, kind, parsed.options);
      await client.query('COMMIT');
      began = false;
      const plan = computePlan({ kind, rows: parsed.rows, snapshot, allowOverwrite: parsed.allowOverwrite, today: todayIso(), options: parsed.options });
      return { kind, spec_version: SPEC_VERSION, ...plan.view };
    } catch (error) {
      if (began) await rollbackQuietly(client);
      throw error;
    } finally {
      client.release();
    }
  } finally {
    gauge.previews -= 1;
  }
}

// ---------------------------------------------------------------------------------------------------------------
// Commit
// ---------------------------------------------------------------------------------------------------------------

function runView(row) {
  return {
    id: Number(row.id),
    kind: row.kind,
    created_at: row.created_at instanceof Date ? row.created_at.toISOString() : new Date(row.created_at).toISOString(),
    row_count: Number(row.row_count),
  };
}

async function commitOnce({ siteCode, kind, parsed, fingerprint, actor }) {
  const actorInfo = actorFromAuthUser(actor);
  const client = await pool.connect();
  let began = false;
  try {
    await client.query('BEGIN');
    began = true;
    await client.query(`SET LOCAL lock_timeout = '${LOCK_TIMEOUT}'`);

    const site = await client.query(`SELECT site_code FROM sites WHERE site_code = $1 FOR KEY SHARE`, [siteCode]);
    if (!site.rows[0]) throw siteNotFound();
    const locked = await client.query('SELECT pg_try_advisory_xact_lock(hashtext($1)) AS locked', [bulkImportLockKey(siteCode)]);
    if (locked.rows[0]?.locked !== true) throw importInProgress();
    await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', [peopleLockKey(siteCode)]);
    if (FINANCE_LOCK_KINDS.has(kind)) {
      await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', [financeLockKey(siteCode)]);
    }
    if (KIND_MODULE[kind]) {
      // modül kilit altında yeniden denetlenir (yükleme sırasında kapatılmış olabilir)
      await assertFinanceEnabled(siteCode, client);
    }

    // idempotans: aynı anahtar + aynı parmak izi = tekrar (yazım yok); farklı parmak izi = çakışma
    const existing = await client.query(
      `SELECT id, kind, request_fingerprint, row_count, counts, created_at FROM bulk_import_runs WHERE site_code = $1 AND idempotency_key = $2`,
      [siteCode, parsed.idempotencyKey],
    );
    if (existing.rows[0]) {
      const row = existing.rows[0];
      if (row.request_fingerprint !== fingerprint || row.kind !== kind) {
        throw new PlatformError(409, 'IDEMPOTENCY_CONFLICT', 'Bu işlem anahtarı farklı bir yükleme için kullanılmış.');
      }
      await client.query('COMMIT');
      began = false;
      const stored = row.counts && typeof row.counts === 'object' ? row.counts : {};
      return {
        status: 200,
        body: {
          replayed: true,
          run: runView(row),
          result: { rows: stored.rows ?? { applied: 0, unchanged: 0, skipped: 0 }, counts: stored.plan ?? {}, issues: null },
        },
      };
    }

    // daireler id sırasıyla (apartments: FOR NO KEY UPDATE; kişiler/araçlar: FOR KEY SHARE), sonra işlemi yapan kullanıcı
    const light = await loadBlocksAndApartments(client, siteCode);
    const apartmentIds = collectApartmentIds(parsed.rows, light);
    if (apartmentIds.length > 0) {
      await client.query(
        `SELECT id FROM apartments WHERE id = ANY($1::BIGINT[]) AND site_code = $2 ORDER BY id ${APARTMENT_WRITE_KINDS.has(kind) ? 'FOR NO KEY UPDATE' : 'FOR KEY SHARE'}`,
        [apartmentIds, siteCode],
      );
    }
    if (actorInfo.userCode !== null) {
      const user = await client.query(`SELECT user_code FROM users WHERE user_code = $1 AND deleted_at IS NULL FOR KEY SHARE`, [actorInfo.userCode]);
      if (!user.rows[0]) {
        throw new PlatformError(401, 'ACCOUNT_DELETED', 'Bu hesap silinmiş.');
      }
    }

    // eşleşmeden ÖNCE üyelikleri CRM'e yansıt (aksi halde sonradan LINK edilecek hesaplı kişi için ikinci, hayalet kayıt doğardı)
    if (SYNC_KINDS.has(kind)) {
      await runSyncSteps(client, { siteCode, userCode: null });
    }
    if (kind === 'opening_balances') {
      await assertWritableDate(client, siteCode, parsed.options.cutover_date, 'Devir tarihi');
    }
    const snapshot = await loadSnapshot(client, siteCode, kind, parsed.options);
    const today = todayIso();
    const plan = computePlan({ kind, rows: parsed.rows, snapshot, allowOverwrite: parsed.allowOverwrite, today, options: parsed.options });
    if (plan.previewHash !== parsed.expectedHash) {
      throw new PlatformError(409, 'PREVIEW_STALE', 'Veriler değişti. Önizleme yenilendi, tekrar inceleyin.', {
        totals: plan.totals,
        plan: plan.counts,
        preview_hash: plan.previewHash,
      });
    }
    if (kind === 'opening_balances' && plan.counts.total_minor !== parsed.options.expected_total_minor) {
      throw totalError(plan, parsed.options.expected_total_minor);
    }
    if (parsed.strict && plan.totals.error > 0) {
      throw new PlatformError(409, 'IMPORT_HAS_ERRORS', 'Hatalı satırlar var. Düzeltip yeniden yükleyin.', {
        totals: plan.totals,
        plan: plan.counts,
      });
    }

    const rows = { applied: plan.totals.ok, unchanged: plan.totals.unchanged, skipped: plan.totals.error };
    const counts = {
      rows,
      with_warnings: plan.totals.with_warnings,
      plan: plan.counts,
      ...(parsed.options ? { cutover_date: parsed.options.cutover_date } : {}),
    };
    const inserted = await client.query(
      `
        INSERT INTO bulk_import_runs
          (site_code, kind, idempotency_key, request_fingerprint, preview_hash, strict, allow_overwrite, row_count, counts, created_by)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9::jsonb, $10)
        RETURNING id, kind, row_count, created_at
      `,
      [
        siteCode,
        kind,
        parsed.idempotencyKey,
        fingerprint,
        plan.previewHash,
        parsed.strict,
        parsed.allowOverwrite,
        parsed.rows.length,
        JSON.stringify(counts),
        actorInfo.userCode,
      ],
    );
    const run = inserted.rows[0];
    const runId = Number(run.id);

    let audits = [];
    if (kind === 'opening_balances') {
      const written = await applyOpeningOps(client, {
        siteCode,
        ops: plan.ops,
        runId,
        cutoverDate: parsed.options.cutover_date,
        actorUserCode: actorInfo.userCode,
      });
      audits.push({
        action: 'finance.opening.imported',
        target_type: 'finance',
        target_id: String(runId),
        details: { run_id: runId, rows: plan.counts.opening_add, total_minor: written.total, cutover_date: parsed.options.cutover_date },
      });
    } else {
      if (APARTMENT_WRITE_KINDS.has(kind)) {
        audits = audits.concat(await applyApartmentOps(client, { siteCode, ops: plan.ops, runId }));
      }
      if (kind !== 'apartments') {
        const peopleOps = plan.ops.filter((op) => op.t !== 'au');
        audits = audits.concat(await applyPeopleOps(client, { siteCode, ops: peopleOps, runId, today, actorUserCode: actorInfo.userCode }));
      }
    }
    audits.push({
      action: 'import.committed',
      target_type: 'import',
      target_id: String(runId),
      details: {
        kind,
        run_id: runId,
        rows: parsed.rows.length,
        counts: { ...rows, with_warnings: plan.totals.with_warnings, ...plan.counts },
        strict: parsed.strict,
        allow_overwrite: parsed.allowOverwrite,
        acknowledged: parsed.acknowledged,
        preview_hash: plan.previewHash,
      },
    });
    await insertAudits(client, { siteCode, actor: actorInfo, rows: audits });
    await client.query('COMMIT');
    began = false;

    return {
      status: 201,
      body: {
        replayed: false,
        run: runView(run),
        result: { rows, counts: plan.counts, issues: plan.view.issues, issues_truncated: plan.view.issues_truncated },
      },
    };
  } catch (error) {
    if (began) await rollbackQuietly(client);
    throw error;
  } finally {
    client.release();
  }
}

/**
 * POST imports/:kind/commit. Tek transaction; 40P01'de TEK yeniden deneme. `env` yalnız testler içindir.
 * @returns {Promise<{ status: 200|201, body: object }>}
 */
export async function commitImport({ siteCode, kind, body, actor, env = process.env }) {
  if (isImportDisabled(env)) throw importDisabled();
  const parsed = validateImportBody(body, kind, { commit: true, env });
  const fingerprint = requestFingerprint({ kind, strict: parsed.strict, allowOverwrite: parsed.allowOverwrite, rows: parsed.rows, options: parsed.options });
  if (gauge.commits >= MAX_CONCURRENT_COMMITS) throw serverBusy();
  gauge.commits += 1;
  try {
    try {
      return await commitOnce({ siteCode, kind, parsed, fingerprint, actor });
    } catch (error) {
      if (error?.code === '40P01') {
        return await commitOnce({ siteCode, kind, parsed, fingerprint, actor }).catch((retryError) => {
          throw mapLockTimeout(retryError);
        });
      }
      throw mapLockTimeout(error);
    }
  } finally {
    gauge.commits -= 1;
  }
}

export { ENTITY_CHUNK };
