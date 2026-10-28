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
import { ACCOUNT_KINDS, attachPlanAccounts, loadTakenOverrides } from './bulk_import_accounts.js';
import { checkLoginName } from './bulk_import_login_names.js';
import { loadBlocksAndApartments, loadSnapshot } from './bulk_import_snapshot.js';
import { KIND_MODULE, SPEC_VERSION, isImportDisabled } from './bulk_import_spec.js';
import {
  ENTITY_CHUNK,
  applyApartmentOps,
  applyOpeningOps,
  applyPeopleOps,
  collectAccountPasswords,
  hashAccountPasswords,
  insertAudits,
  provisionImportedResidents,
} from './bulk_import_writer.js';
import { ensureTenantIsAdmin } from './apartment_tenant_admin.js';
import { todayIso } from './people_common.js';
import { peopleLockKey } from './people_sync.js';
import { runSyncSteps } from './people_sync_sql.js';

export const bulkImportLockKey = (siteCode) => `bulk_import:${Number(siteCode)}`;

const LOCK_TIMEOUT = '8s';
/** Kişi eşitlemesi (CRM) gereken türler; finans kilidi gereken türler; daire satırı yazan türler. */
const SYNC_KINDS = new Set(['people', 'vehicles', 'all_in_one']);
const FINANCE_LOCK_KINDS = new Set(['apartments', 'all_in_one', 'opening_balances']);
const APARTMENT_WRITE_KINDS = new Set(['apartments', 'all_in_one']);
const totalError = (plan, expected, expectedCredit = 0) =>
  new PlatformError(409, 'TOTAL_MISMATCH', 'Toplam tutar onaylanan tutarla uyuşmuyor. Önizleme yenilendi, tekrar inceleyin.', {
    totals: plan.totals,
    plan: plan.counts,
    preview_hash: plan.previewHash,
    expected_total_minor: expected,
    expected_credit_total_minor: expectedCredit,
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
// Plan (önizleme, öneri, commit ortak)
// ---------------------------------------------------------------------------------------------------------------

/** Anlık görüntü + (hesap açan türlerde) dosyada yönetici tarafından seçilmiş kullanıcı adlarından sistemde ZATEN kayıtlı olanlar. */
async function loadPlanSnapshot(db, siteCode, kind, parsed) {
  const snapshot = await loadSnapshot(db, siteCode, kind, parsed.options);
  if (ACCOUNT_KINDS.has(kind)) {
    snapshot.takenLoginNames = await loadTakenOverrides(db, parsed.rows);
  }
  return snapshot;
}

/**
 * Planı hesaplar ve (hesap açan türlerde) hesap bölümünü çözümler: yeni hesaplar için kullanıcı adı önerisi (sistemde ve dosyada boşta ilk ad),
 * mevcut hesaba bağlanacaklar (salt okunur). Çözümlenen adlar `preview_hash`'e katılır; hesap açılmayan yüklemede hash değişmez.
 */
async function buildPlan(db, { siteCode, kind, parsed, snapshot, today }) {
  const plan = computePlan({ kind, rows: parsed.rows, snapshot, allowOverwrite: parsed.allowOverwrite, today, options: parsed.options });
  if (ACCOUNT_KINDS.has(kind)) {
    await attachPlanAccounts(db, { siteCode, plan });
  }
  return plan;
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
 * POST imports/:kind/accounts: önizleme tablosundaki «Kullanıcı Adı» sütunu için hesap önerileri (yalnız people / all_in_one). YAZMAZ ve CRM eşitlemesi
 * YAPMAZ (tabloda sık yenilenir; öneri bilgilendiricidir, kesin sonuç önizleme/commit'tir). Hız sınırı önizlemeden ayrıdır (tablo düzenlemeleri sıktır).
 * @returns {Promise<{ kind: string, spec_version: number, accounts: object[] }>}
 */
export async function previewAccounts({ siteCode, kind, body, env = process.env }) {
  if (isImportDisabled(env)) throw importDisabled();
  if (!ACCOUNT_KINDS.has(kind)) {
    throw new PlatformError(404, 'IMPORT_KIND_NOT_FOUND', 'Bu yükleme türünde hesap açılmaz.');
  }
  const parsed = validateImportBody(body, kind, { commit: false, env });
  if (gauge.previews >= MAX_CONCURRENT_PREVIEWS) throw serverBusy();
  gauge.previews += 1;
  try {
    const client = await pool.connect();
    let began = false;
    try {
      await client.query('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY');
      began = true;
      const exists = await client.query(`SELECT 1 FROM sites WHERE site_code = $1`, [siteCode]);
      if (!exists.rows[0]) throw siteNotFound();
      const snapshot = await loadPlanSnapshot(client, siteCode, kind, parsed);
      const plan = await buildPlan(client, { siteCode, kind, parsed, snapshot, today: todayIso() });
      await client.query('COMMIT');
      began = false;
      return { kind, spec_version: SPEC_VERSION, accounts: plan.view.accounts ?? [] };
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

/**
 * POST imports/login-names/check: yöneticinin tabloya yazdığı kullanıcı adının biçimi ve sistemdeki (her site, her şehir) kullanılabilirliği.
 * `{ ok, login_name, code, message, suggestion }`. Tek hafif sorgu; yazmaz.
 */
export async function checkImportLoginName({ body, env = process.env }) {
  if (isImportDisabled(env)) throw importDisabled();
  const raw = body && typeof body === 'object' && !Array.isArray(body) ? body.login_name : undefined;
  if (typeof raw !== 'string' || Array.from(raw).length > 200) {
    throw new PlatformError(400, 'INVALID_BODY', 'login_name metin olmalıdır.');
  }
  return checkLoginName(pool, raw);
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
      const snapshot = await loadPlanSnapshot(client, siteCode, kind, parsed);
      // plan ve hesap çözümlemesi AYNI anlık görüntü işleminde (kullanıcı adı denetimleri kişi verisiyle tutarlı) hesaplanır
      const plan = await buildPlan(client, { siteCode, kind, parsed, snapshot, today: todayIso() });
      await client.query('COMMIT');
      began = false;
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

/**
 * Hesap açacak yüklemelerde şifre özetlerini (bcrypt) TRANSACTION ÖNCESİ, sınırlı eşzamanlılıkla hesaplar: 1500 kişilik dosyada özetler
 * kilitleri tutan transaction'da sıralı çalışsaydı dakikalar sürerdi. Plan kilitsiz bir anlık görüntüde YAKLAŞIK hesaplanır (yalnız hangi kişilerin
 * hesap alacağını ve şifrelerini bulmak için); transaction içindeki gerçek plan farklı çıkarsa eksik/değişen özetler yerinde hesaplanır.
 * Tekrar oynatma, bayat önizleme ya da hata durumunda boş döner (özet gerekmez / sonra hesaplanır).
 */
async function prehashAccounts({ siteCode, kind, parsed }) {
  if (!ACCOUNT_KINDS.has(kind)) return new Map();
  try {
    const replay = await pool.query(`SELECT 1 FROM bulk_import_runs WHERE site_code = $1 AND idempotency_key = $2`, [siteCode, parsed.idempotencyKey]);
    if (replay.rows[0]) return new Map();
    const client = await pool.connect();
    let snapshot;
    let plan;
    try {
      await client.query('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY');
      snapshot = await loadPlanSnapshot(client, siteCode, kind, parsed);
      plan = await buildPlan(client, { siteCode, kind, parsed, snapshot, today: todayIso() });
      await client.query('COMMIT');
    } catch (error) {
      await rollbackQuietly(client);
      throw error;
    } finally {
      client.release();
    }
    if (plan.previewHash !== parsed.expectedHash || !(plan.counts.account_create > 0)) return new Map();
    return await hashAccountPasswords(collectAccountPasswords(plan.ops));
  } catch (_error) {
    return new Map();
  }
}

async function commitOnce({ siteCode, kind, parsed, fingerprint, actor, hashes = new Map() }) {
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
    const snapshot = await loadPlanSnapshot(client, siteCode, kind, parsed);
    const today = todayIso();
    const plan = await buildPlan(client, { siteCode, kind, parsed, snapshot, today });
    if (plan.previewHash !== parsed.expectedHash) {
      throw new PlatformError(409, 'PREVIEW_STALE', 'Veriler değişti. Önizleme yenilendi, tekrar inceleyin.', {
        totals: plan.totals,
        plan: plan.counts,
        preview_hash: plan.previewHash,
      });
    }
    // Devir toplamları: BORÇ toplamı ve ALACAK toplamı AYRI ayrı onaylanır (K16): ikisi de uyuşmazsa hiçbir şey yazılmaz.
    if (
      kind === 'opening_balances' &&
      (plan.counts.total_minor !== parsed.options.expected_total_minor ||
        (plan.counts.credit_total_minor ?? 0) !== (parsed.options.expected_credit_total_minor ?? 0))
    ) {
      throw totalError(plan, parsed.options.expected_total_minor, parsed.options.expected_credit_total_minor ?? 0);
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
    let accounts = null;
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
        details: {
          run_id: runId,
          rows: plan.counts.opening_add,
          total_minor: written.total,
          credit_rows: plan.counts.opening_credit_add ?? 0,
          credit_total_minor: written.creditTotal ?? 0,
          cutover_date: parsed.options.cutover_date,
        },
      });
    } else {
      if (APARTMENT_WRITE_KINDS.has(kind)) {
        audits = audits.concat(await applyApartmentOps(client, { siteCode, ops: plan.ops, runId }));
      }
      if (kind !== 'apartments') {
        const peopleOps = plan.ops.filter((op) => op.t !== 'au');
        const written = await applyPeopleOps(client, { siteCode, ops: peopleOps, runId, today, actorUserCode: actorInfo.userCode });
        audits = audits.concat(written.audits);
        if (ACCOUNT_KINDS.has(kind)) {
          // yalnız BU yüklemede daire ilişkisi eklenen kişilere hesap (kapsam sınırı); sitedeki diğer hesapsız sakinlere dokunulmaz
          accounts = await provisionImportedResidents(client, {
            siteCode,
            runId,
            accountCandidates: written.accountCandidates,
            hashes,
            // önizlemede gösterilen (hash'e girmiş) kullanıcı adları; yarışta başkası alırsa yazıcı sıradaki boş adı verir ve sonuçta bildirir
            expected: plan.accounts?.expected ?? new Map(),
          });
          audits = audits.concat(accounts.audits);
        }
        // Kiracı HER ZAMAN daire admini (kullanıcı kararı 2026-10-26; admin önceliği kiracı > malik > diğerleri): dosyada kiracı eklenen / kiracıya yükseltilen
        // dairelerde, hesaplar açıldıktan SONRA, mevcut admin malik olsa bile yönetim kiracıya geçer (hesapsız / üyeliksiz kiracıda hesap bağlanınca geçer).
        if ((written.tenantApartmentIds ?? []).length > 0) {
          await ensureTenantIsAdmin(client, { apartmentIds: written.tenantApartmentIds, overrideManager: true, via: 'bulk_import', actor });
        }
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
        counts: {
          ...rows,
          with_warnings: plan.totals.with_warnings,
          ...plan.counts,
          ...(accounts ? { accounts_created: accounts.created, accounts_linked: accounts.linked, accounts_skipped: accounts.skipped, accounts_renamed: accounts.renamed } : {}),
        },
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
        result: {
          rows,
          counts: plan.counts,
          issues: plan.view.issues,
          issues_truncated: plan.view.issues_truncated,
          // açılan / bağlanan hesaplar: satır no + NİHAİ kullanıcı adı (çakışmada sunucu ek koyabilir); atlananlar neden iletisiyle
          ...(accounts
            ? { accounts: { created: accounts.created, linked: accounts.linked, skipped: accounts.skipped, renamed: accounts.renamed, items: accounts.items, skipped_items: accounts.skipped_items } }
            : {}),
        },
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
    const hashes = await prehashAccounts({ siteCode, kind, parsed });
    try {
      return await commitOnce({ siteCode, kind, parsed, fingerprint, actor, hashes });
    } catch (error) {
      if (error?.code === '40P01') {
        return await commitOnce({ siteCode, kind, parsed, fingerprint, actor, hashes }).catch((retryError) => {
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
