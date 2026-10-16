// Aidat ve Finans (Faz 4a) yazma transaction'ı.
//
// Sözleşme: docs/PLATFORM_FINANS.md ("İlkeler" madde 8). KİLİT SIRASI: sites FOR KEY SHARE (site silme ile sıra; sıradan UPDATE sites'ı bekletmez) ->
// pg_advisory_xact_lock(finance_post:<site>) -> apartments (id sırasıyla, FOR KEY SHARE) -> users(işlemi yapan; FOR KEY SHARE, `lockActorRow`) -> finans satırları.
// Kullanıcı satırı finans satırlarından ÖNCE kilitlenir: kullanıcı silme (apartments -> users -> ledger / fee_* SET NULL) ile ters sıra 40P01 verirdi
// (örn. tanım güncellerken audit FK'si kullanıcı satırını sonradan ister).
// Aynı site için TÜM finans yazmaları (borçlandırma, tahsilat, ters kayıt, dönem kapatma/açma, tanım değişikliği) bu kilitle sıraya girer; böylece
// "dönem kapalı mı" denetimi, (tanım, dönem) tekilliği, ters kayıt tekilliği ve idempotans yarışsız verilir. Daire azaltma da (site_service)
// AYNI kilidi ilk daire silmeden önce alır. Nadir 40P01'de işlem TEK SEFER baştan denenir; `work` yeniden çalışabilir olmalı.

import { pool } from '../db.js';
import { recordAudit } from './audit_service.js';
import { assertFinanceEnabled } from './finance_access.js';
import { financeLockKey, siteNotFound } from './finance_common.js';

async function runOnce(siteCode, work) {
  const client = await pool.connect();
  let began = false;
  try {
    await client.query('BEGIN');
    began = true;
    const site = await client.query(`SELECT site_code FROM sites WHERE site_code = $1 FOR KEY SHARE`, [siteCode]);
    if (!site.rows?.[0]) {
      throw siteNotFound();
    }
    await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', [financeLockKey(siteCode)]);
    // Modül yazma sırasında kapatılmış olabilir: kilit altında yeniden denetlenir.
    await assertFinanceEnabled(siteCode, client);
    const result = await work(client);
    await client.query('COMMIT');
    return result;
  } catch (error) {
    if (began) {
      try {
        await client.query('ROLLBACK');
      } catch (_rollbackError) {
        // bağlantı zaten kopmuş olabilir; asıl hata yukarıda fırlatılır
      }
    }
    throw error;
  } finally {
    client.release();
  }
}

/** Finans yazma transaction'ı (bkz. dosya başı). `work(client)` sonucunu döndürür; hata olursa ROLLBACK. */
export async function withFinanceTransaction(siteCode, work) {
  try {
    return await runOnce(siteCode, work);
  } catch (error) {
    if (error?.code === '40P01') {
      return runOnce(siteCode, work);
    }
    throw error;
  }
}

/**
 * Finans denetim kaydı (target_type 'finance'). `details` YALNIZ toplam / sayı / dönem / alan adı taşır: açıklama, neden metni, tanım adı ve kişi adı
 * ASLA yazılmaz. Kayıt, işlemle birlikte işlenir/geri alınır (başarısız INSERT ana işlemi bozmaz: audit_service SAVEPOINT kullanır).
 */
export async function recordFinanceAudit(client, actor, action, siteCode, targetId, details) {
  await recordAudit(
    client,
    { actor, action, siteCode, targetType: 'finance', targetId: String(targetId), details },
    { inTransaction: true },
  );
}

/**
 * İşlemi yapan kullanıcının satırını FOR KEY SHARE kilitler (created_by / posted_by / audit FK'leri için). Çağıran, daire kilitlerini (varsa) ÖNCE almış
 * olmalıdır: sıra apartments -> users(işlemi yapan) -> finans satırları (kullanıcı silme tetikleyicisinin sırası). Kullanıcı yoksa sessizce geçer.
 */
export async function lockActorRow(client, actorInfo) {
  if (actorInfo?.userCode === null || actorInfo?.userCode === undefined) {
    return;
  }
  await client.query('SELECT user_code FROM users WHERE user_code = $1 FOR KEY SHARE', [actorInfo.userCode]);
}

/**
 * Dönem KAPALI mı? Bir ay, ay <= MAX(kapalı dönem) ise kapalıdır: ilk kapatılan aydan önceki aylar da kapalı sayılır (geriye tarihli yazma yok).
 */
export async function isPeriodClosed(db, siteCode, periodIso) {
  const result = await db.query(
    `SELECT 1 FROM finance_period_closures WHERE site_code = $1 AND period >= $2::DATE LIMIT 1`,
    [siteCode, periodIso],
  );
  return Boolean(result.rows?.[0]);
}
