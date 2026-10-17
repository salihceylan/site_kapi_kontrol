// Toplu yükleme (Faz 2b) planlayıcı girişi. Saf: DB/ağ bağımsız.

import { readText } from './bulk_import_parsers.js';
import { planApartments } from './bulk_import_plan_apartments.js';
import { buildLocator } from './bulk_import_plan_common.js';
import { planPeople, planVehicles } from './bulk_import_plan_people.js';

/** Türe göre planı hesaplar (önizleme ve commit AYNI fonksiyonu kullanır). */
export function computePlan({ kind, rows, snapshot, allowOverwrite = false, today }) {
  if (kind === 'apartments') {
    return planApartments({ rows, snapshot, allowOverwrite });
  }
  if (kind === 'people') {
    return planPeople({ rows, snapshot, today });
  }
  return planVehicles({ rows, snapshot, today });
}

/** Dosyadaki satırların başvurduğu dairelerin kimlikleri (artan, tekil): commit kilit sırası için. */
export function collectApartmentIds(rows, snapshot) {
  const locator = buildLocator(snapshot);
  const ids = new Set();
  for (const row of rows) {
    const block = readText(row.cells.blok, { forbidSigned: true, max: 60 });
    const number = readText(row.cells.daire_no, { max: 30 });
    if (block.value && number.value) {
      const resolved = locator.resolve(block.value, number.value);
      if (resolved.apartment) {
        ids.add(resolved.apartment.id);
      }
    }
  }
  return [...ids].sort((a, b) => a - b);
}
