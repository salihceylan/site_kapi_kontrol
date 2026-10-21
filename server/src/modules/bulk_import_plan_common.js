// Toplu yükleme (Faz 2b) planlayıcıları için ortak yapılar. Saf: DB/ağ bağımsız.
//
// Plan = satır sonuçları + yazılacak işlemler (`ops`) + sayılar. Önizleme planı YAZMAZ; commit aynı planı kilit altında yeniden hesaplar ve
// `preview_hash` ile karşılaştırır. Hash yalnız KOD/KİMLİK/DEĞER özetini kapsar (ileti metinleri girmez).

import { apartmentLabel, foldText } from './people_common.js';
import { matchBlock, apartmentKey } from './bulk_import_parsers.js';
import { issueMessage, severityOf } from './bulk_import_messages.js';
import { labelOf } from './bulk_import_spec.js';
import { sha256 } from './bulk_import_body.js';

/** Önizleme yanıtındaki `issues` dizisi üst sınırı (yanıt <= 1 MB kalsın). Aşılırsa `issues_truncated: true`. */
export const MAX_ISSUES_IN_RESPONSE = 4000;
export const SAMPLES_PER_ACTION = 5;

/** Satır sonucu başlat. */
export function newRowResult(n) {
  return { n, issues: [], ops: [], status: 'unchanged', action: 'unchanged', summary: '', hasError: false, extraSig: '' };
}

/**
 * Sorun ekle. `severity` verilmezse koddan türetilir. `ctx`: iletiye giren bağlam (label/value/max/lead/line/blocks).
 */
export function addIssue(result, kind, code, field, ctx = {}, severity = null) {
  const level = severity ?? severityOf(code);
  result.issues.push({
    severity: level,
    field: field ?? null,
    code,
    message: issueMessage(code, { label: field ? labelOf(kind, field) : undefined, ...ctx, severity: level }),
  });
  if (level === 'error') {
    result.hasError = true;
  }
}

/** Blok + daire arama dizinleri. */
export function buildLocator(snapshot) {
  const blocks = snapshot.blocks.map((block) => ({ id: Number(block.id), name: block.name }));
  const byBlock = new Map();
  for (const apartment of snapshot.apartments) {
    const list = byBlock.get(apartment.blockId) ?? [];
    list.push({ key: apartmentKey(apartment.label), folded: foldText(apartment.label).replace(/\s+/g, ' ').trim(), apartment });
    byBlock.set(apartment.blockId, list);
  }
  const blockById = new Map(blocks.map((block) => [block.id, block]));
  return {
    blocks,
    blockNames: blocks.map((block) => block.name),
    /** @returns {{ apartment?: object, block?: object, error?: string }} */
    resolve(blockText, apartmentText) {
      const matched = matchBlock(blockText, blocks);
      if (matched.error) {
        return { error: matched.error };
      }
      const list = byBlock.get(matched.block.id) ?? [];
      const wanted = apartmentKey(apartmentText);
      const candidates = list.filter((entry) => entry.key === wanted);
      if (candidates.length === 1) {
        return { apartment: candidates[0].apartment, block: matched.block };
      }
      if (candidates.length > 1) {
        const folded = foldText(apartmentText).replace(/\s+/g, ' ').trim();
        const exact = candidates.filter((entry) => entry.folded === folded);
        if (exact.length === 1) {
          return { apartment: exact[0].apartment, block: matched.block };
        }
      }
      return { error: 'APARTMENT_NOT_FOUND', block: matched.block };
    },
    labelOfApartment(apartment) {
      return apartmentLabel(blockById.get(apartment.blockId)?.name ?? '', apartment.label);
    },
  };
}

/** Sorunlardan karma imzası: yalnız önem, alan ve kod (ileti yok). */
export function issueSignature(issues) {
  return issues
    .map((issue) => `${issue.severity[0]}:${issue.field ?? ''}:${issue.code}`)
    .sort()
    .join(',');
}

/**
 * Satır sonucunu tamamlar: durum (error | ok | unchanged) ve karma imzası. `targetSig` hedef kimlikleri (daire/kişi), ops işlemleri imzalar.
 */
export function completeRow(result, targetSig) {
  if (result.hasError) {
    result.status = 'error';
    result.ops = [];
  } else {
    result.status = result.ops.length > 0 ? 'ok' : 'unchanged';
  }
  const opsSig = result.hasError ? '' : result.ops.map((op) => JSON.stringify(opSignature(op))).join(';');
  result.sig = [result.n, result.status, targetSig ?? '', opsSig, issueSignature(result.issues), result.extraSig].join('|');
  return result;
}

/** İşlem imzası (sabit alan sırası). Değerler yalnız karma içinde kullanılır. */
export function opSignature(op) {
  switch (op.t) {
    case 'pc':
      return ['pc', op.ref, op.name, op.phone, op.email, op.note];
    case 'pf':
      return ['pf', op.ref, op.field, op.value];
    case 'pr':
      return ['pr', op.ref, op.name, op.phone];
    case 'ra':
      return ['ra', op.ref, op.aptId, op.relation, op.moveIn ?? 'T'];
    case 'ru':
      return ['ru', op.ref, op.aptId, op.residencyId, op.from, op.to];
    case 'va':
      return ['va', op.ref, op.plate, op.note];
    case 'au':
      return ['au', op.aptId, op.set];
    case 'ob':
      return ['ob', op.aptId, op.account, op.minor, op.due, op.desc];
    default:
      return [op.t];
  }
}

/**
 * Plan sonucu: toplamlar, sorun listesi, örnekler ve preview_hash.
 * @param {{ kind: string, results: object[], counts: object, checks?: object }} plan
 */
export function finalizePlan(plan) {
  const { kind, results } = plan;
  const totals = { rows: results.length, ok: 0, unchanged: 0, error: 0, with_warnings: 0 };
  const issues = [];
  const samples = [];
  const perAction = new Map();
  for (const result of results) {
    totals[result.status] += 1;
    if (!result.hasError && result.issues.some((issue) => issue.severity === 'warning')) {
      totals.with_warnings += 1;
    }
    for (const issue of result.issues) {
      issues.push({ n: result.n, severity: issue.severity, field: issue.field, code: issue.code, message: issue.message });
    }
    if (result.summary !== '') {
      const seen = perAction.get(result.action) ?? 0;
      if (seen < SAMPLES_PER_ACTION) {
        perAction.set(result.action, seen + 1);
        samples.push({ n: result.n, action: result.action, summary: result.summary });
      }
    }
  }
  const truncated = issues.length > MAX_ISSUES_IN_RESPONSE;
  // Hatalar önce korunur: kesilirse uyarılar atılır (satır sırası n korunur).
  let kept = issues;
  if (truncated) {
    const errors = issues.filter((issue) => issue.severity === 'error');
    const room = Math.max(0, MAX_ISSUES_IN_RESPONSE - errors.length);
    const warnings = issues.filter((issue) => issue.severity !== 'error').slice(0, room);
    kept = [...errors, ...warnings].sort((a, b) => a.n - b.n);
    kept = kept.slice(0, MAX_ISSUES_IN_RESPONSE);
  }
  const NL = String.fromCharCode(10);
  const salt = plan.hashSalt ? plan.hashSalt + NL : '';
  const previewHash = sha256(['v1', kind, salt + results.map((result) => result.sig).join(NL)].join(NL));
  return {
    // yanıt gövdesi (kişisel veri içerebilir: yalnız önizleme yanıtında döner, saklanmaz)
    view: {
      kind,
      totals,
      plan: plan.counts,
      issues: kept,
      issues_truncated: truncated,
      samples,
      checks: plan.checks ?? { land_share: null },
      preview_hash: previewHash,
    },
    // commit için: satır sonuçları ve yazılacak işlemler (hatalı satırların işlemi yoktur)
    results,
    ops: results.flatMap((result) => (result.hasError ? [] : result.ops)),
    counts: plan.counts,
    totals,
    previewHash,
  };
}
