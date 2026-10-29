// Dikkat kaydı: modüllerin "yönetici bir şey yapmalı" sayaçlarını tek bir özet ucuna eklemesi için kayıt defteri.
//
// Bir kaynak `registerAttentionSource({ key, module, run })` ile kaydolur. `run(db, siteCode)` -> `{ count, total_minor?, at_least? } | null` döner
// (null ya da count 0: gösterilecek bir şey yok; at_least true: sayı kesilmiş bir listeden çıktı, "en az" değerdir). Modülü site için kapalıysa kaynak çalıştırılmaz. Bir kaynağın hatası diğerlerini ve özeti
// bozmaz; o kaynak listeden düşer. Bugün yalnız finans kaynağı var; sonradan eklenenler (dekont, banka satırı, bütçe...) kendi satırını ekler.

import { pool } from '../db.js';
import { isModuleEnabled } from './module_service.js';

const sources = new Map();

/** Kaynak ekler (aynı anahtar yeniden kaydolursa üzerine yazar). */
export function registerAttentionSource({ key, module, run }) {
  if (!key || typeof run !== 'function') {
    throw new Error('attention source: key ve run zorunlu');
  }
  sources.set(key, { key, module: module ?? null, run });
}

export const attentionSourceKeys = () => [...sources.keys()];

/** Siteye ait dikkat satırları: [{ key, module, count, total_minor? }] (yalnız count > 0). */
export async function collectAttention(siteCode, db = pool) {
  const items = [];
  for (const source of sources.values()) {
    try {
      if (source.module && !(await isModuleEnabled(siteCode, source.module))) {
        continue;
      }
      const result = await source.run(db, siteCode);
      const count = Number(result?.count ?? 0);
      if (count > 0) {
        items.push({
          key: source.key,
          module: source.module,
          count,
          ...(result.total_minor === undefined ? {} : { total_minor: result.total_minor }),
          // Kaynak sayıyı kesilmiş bir listeden çıkardıysa (at_least) sayı "en az" değerdir; istemci bunu açıkça yazar.
          ...(result.at_least === true ? { at_least: true } : {}),
        });
      }
    } catch (_error) {
      // tek kaynağın hatası özeti bozmaz
    }
  }
  return items;
}
