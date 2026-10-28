// Demirbaş / Fon tahakkukunun dayanağı (K2, P1-2): Karar Defteri modülü AÇIK sitede kesinleşmiş karar seçimi, KAPALI sitede serbest metin gerekçe ZORUNLUDUR.
//
// Sözleşme: docs/PLATFORM_FINANS_KARAR_BAGI.md.
//  - Zorunluluk YALNIZ Yatırım ve Demirbaş (Fon / capital) hesabına borç yazan tahakkukta (aylık borçlandırma ve ek borç) vardır; işletme (Aidat) hesabında dayanak isteğe bağlıdır (verilirse AYNI kurallarla doğrulanır).
//  - Modül AÇIK: `decision_id` zorunlu; karar bu sitenin KESİN kararı olmalı (başka site / olmayan 404 DECISION_NOT_FOUND, taslak 409 DECISION_NOT_FINAL). İsteğe bağlı `decision_reason` ayrıca saklanır.
//    Gerekçe tek başına yetmez (400 DECISION_REQUIRED).
//  - Modül KAPALI: `decision_reason` zorunlu (400 DECISION_REASON_REQUIRED); `decision_id` gönderilirse 400 DECISION_MODULE_OFF (sessizce yok sayılmaz).
//  - Denetim finans yazma işleminin İÇİNDE (advisory kilit altında) yapılır; karar satırı FOR KEY SHARE okunur (kesin karar zaten değişmez/silinmez; kullanıcı silme SET NULL'u KEY SHARE ile çakışmaz).
//  - Saf denetim kuralı `decideRunDecision` (DB'siz birim testi); `resolveRunDecision` yalnız modül durumunu ve karar satırını okur.

import { isModuleEnabled } from './module_service.js';
import { DECISION_BOOK_MODULE } from './decision_book_common.js';
import {
  RUN_DECISION_REASON_MAX,
  RUN_DECISION_REASON_MIN,
  decisionModuleOff,
  decisionReasonRequired,
  decisionRequired,
  runDecisionNotFinal,
  runDecisionNotFound,
} from './finance_common.js';

/** Dayanak istemeyen / vermeyen tahakkuk (işletme hesabı). */
export const NO_RUN_DECISION = Object.freeze({ decisionId: null, decisionReason: null, label: null });

/** Fon (capital) hesabına borç yazan tahakkukta dayanak zorunludur. */
export const decisionRequiredFor = (fund) => fund === 'capital';

/**
 * SAF kural: hangi dayanak istenir / kabul edilir? Girdi: fon, modül açık mı, gövdedeki `decisionId` / `decisionReason`.
 * @returns {{ kind: 'none' | 'reason' | 'decision' }} 'none': dayanak yok (zorunlu değil); 'reason': yalnız gerekçe saklanır; 'decision': karar doğrulanıp saklanır (gerekçe isteğe bağlı eşlik eder).
 * @throws PlatformError DECISION_REQUIRED | DECISION_REASON_REQUIRED | DECISION_MODULE_OFF
 */
export function decideRunDecision({ fund, moduleEnabled, decisionId, decisionReason }) {
  const required = decisionRequiredFor(fund);
  if (!required && decisionId === null && decisionReason === null) {
    return { kind: 'none' };
  }
  if (!moduleEnabled) {
    if (decisionId !== null) {
      throw decisionModuleOff();
    }
    if (decisionReason === null) {
      throw decisionReasonRequired();
    }
    return { kind: 'reason' };
  }
  if (decisionId === null) {
    if (required) {
      throw decisionRequired();
    }
    return { kind: 'reason' };
  }
  return { kind: 'decision' };
}

/**
 * Önizleme yanıtındaki `decision_requirement`: arayüz hangi girdiyi göstereceğini buradan öğrenir.
 * `mode`: 'decision' (modül açık, Fon hesabı: karar seç), 'reason' (modül kapalı, Fon hesabı: gerekçe yaz), 'none' (işletme hesabı: dayanak istenmez).
 */
export async function describeDecisionRequirement(db, siteCode, fund) {
  const moduleEnabled = await isModuleEnabled(siteCode, DECISION_BOOK_MODULE, db);
  const required = decisionRequiredFor(fund);
  return {
    required,
    mode: !required ? 'none' : moduleEnabled ? 'decision' : 'reason',
    module_enabled: moduleEnabled,
    reason_min: RUN_DECISION_REASON_MIN,
    reason_max: RUN_DECISION_REASON_MAX,
  };
}

/** Denetim kaydı ayrıntısı: yalnız karar kimliği ve "gerekçe verildi" bayrağı. Gerekçe METNİ denetime / günlüğe ASLA yazılmaz (finans denetim ilkesi). */
export function decisionAuditDetails(decision) {
  return {
    ...(decision.decisionId === null ? {} : { decision_id: decision.decisionId }),
    ...(decision.decisionReason === null ? {} : { decision_reason_given: true }),
  };
}

/**
 * Yazma işleminde dayanağı çözer ve doğrular. Dönüş: `{ decisionId, decisionReason, label }`; `label` yanıta konacak `run_decision_*` satır parçasıdır (`mapRunRow` / `decisionOfRow` okur;
 * dayanak yoksa null). İşlem (BEGIN) içinde ve finans advisory kilidi altında çağrılır.
 */
export async function resolveRunDecision(client, { siteCode, fund, decisionId = null, decisionReason = null }) {
  if (!decisionRequiredFor(fund) && decisionId === null && decisionReason === null) {
    return NO_RUN_DECISION;
  }
  const moduleEnabled = await isModuleEnabled(siteCode, DECISION_BOOK_MODULE, client);
  const decided = decideRunDecision({ fund, moduleEnabled, decisionId, decisionReason });
  if (decided.kind === 'none') {
    return NO_RUN_DECISION;
  }
  if (decided.kind === 'reason') {
    return { decisionId: null, decisionReason, label: { run_decision_id: null, run_decision_reason: decisionReason } };
  }
  // Her sorguda site_code vardır (IDOR yok): başka sitenin kararı ile olmayan karar AYNI yanıtı (404) verir.
  const found = await client.query(
    `SELECT id, year, decision_no, title, visibility, status FROM board_decisions WHERE site_code = $1 AND id = $2 FOR KEY SHARE`,
    [siteCode, decisionId],
  );
  const row = found.rows?.[0];
  if (!row) {
    throw runDecisionNotFound();
  }
  if (row.status !== 'kesin' || row.decision_no === null || row.decision_no === undefined) {
    throw runDecisionNotFinal();
  }
  return {
    decisionId,
    decisionReason,
    label: {
      run_decision_id: decisionId,
      run_decision_reason: decisionReason,
      run_decision_year: row.year,
      run_decision_no: row.decision_no,
      run_decision_title: row.title,
      run_decision_visibility: row.visibility,
    },
  };
}
