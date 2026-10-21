// Gider türü (R1): "rutin / beklenmedik". Tür yan tabloda (expense_natures) tutulur; gider satırı değişmez.
//
// Öneri sırası (saf `suggestExpenseNature`): (a) tedarikçi adı aktif sözleşmeli bir firmayla eşleşiyor -> rutin 'contract';
// (b) aynı kategori + tedarikçide son 3 ayın en az 2'sinde iptal edilmemiş gider -> rutin 'recurring'; (c) sistem kategorisi (aşağıdaki liste) -> rutin 'category';
// (d) diğer hepsi -> beklenmedik 'default'. Tür kaydı olmayan eski gider OKUMADA yalnız (c)/(d) kuralıyla türetilir (`nature_source: 'derived'`), yazılmaz.
// Sözleşme: docs/PLATFORM_FINANS_4B.md "Gider analizi ve tahmin (R1)".

import { pool } from '../db.js';
import { actorFromAuthUser } from './audit_service.js';
import { expenseAlreadyVoided, expenseNotFound, optionalId } from './finance_4b_common.js';
import { invalidBody, parseIsoDate } from './finance_common.js';
import { lockActorRow, recordFinanceAudit, withFinanceTransaction } from './finance_tx.js';
import { foldSql, foldText, parsePositiveId } from './people_common.js';

export const EXPENSE_NATURES = Object.freeze(['routine', 'unexpected']);

/** Varsayılan olarak rutin sayılan sistem kategorileri (finance_expenses.js DEFAULT_EXPENSE_CATEGORIES alt kümesi). */
export const ROUTINE_CATEGORY_NAMES = Object.freeze([
  'Personel',
  'Elektrik',
  'Su',
  'Doğalgaz/Yakıt',
  'Asansör bakım',
  'Temizlik malzemesi',
  'Sigorta',
  'Yönetici aylığı',
  'Vergi/harç',
  'Banka/noter masrafı',
]);

export const NATURE_REASON_TEXT = Object.freeze({
  contract: 'Bu firmayla aktif sözleşme var.',
  recurring: 'Son 3 ayın en az 2’sinde aynı gider var.',
  category: 'Bu kategori genellikle düzenli bir giderdir.',
  default: 'Bu kategori genellikle düzensiz bir giderdir.',
});

/** Kategori adına göre varsayılan tür (kural c/d): okuma anında türetme de bunu kullanır. */
export function categoryDefaultNature(categoryName) {
  const folded = foldText(categoryName);
  return ROUTINE_CATEGORY_NAMES.some((name) => foldText(name) === folded) ? 'routine' : 'unexpected';
}

/** SQL: tür kaydı olmayan giderin okuma anında türetilen türü (categoryDefaultNature ile aynı kural). `alias`: expenses takma adı. */
export const derivedNatureSql = (alias) =>
  `CASE WHEN ${foldSql(`${alias}.category_name`)} IN (${ROUTINE_CATEGORY_NAMES.map((name) => `'${foldText(name)}'`).join(', ')}) THEN 'routine' ELSE 'unexpected' END`;

/** SQL: giderin geçerli türü (kayıt varsa o, yoksa türetilen). */
export const effectiveNatureSql = (alias, natureAlias) => `COALESCE(${natureAlias}.nature, ${derivedNatureSql(alias)})`;

/**
 * Saf öneri. facts: { activeContract: boolean, recurringMonths: number (son 3 ayda gider olan ay sayısı), categoryName: string }.
 * @returns {{ nature: 'routine'|'unexpected', reason: 'contract'|'recurring'|'category'|'default' }}
 */
export function suggestExpenseNature(facts) {
  if (facts.activeContract === true) return { nature: 'routine', reason: 'contract' };
  if (Number(facts.recurringMonths) >= 2) return { nature: 'routine', reason: 'recurring' };
  if (categoryDefaultNature(facts.categoryName) === 'routine') return { nature: 'routine', reason: 'category' };
  return { nature: 'unexpected', reason: 'default' };
}

/** İstekteki tür: yoksa null; geçersizse 400. */
export function parseNature(value) {
  if (value === undefined || value === null || value === '') return null;
  if (!EXPENSE_NATURES.includes(value)) {
    throw invalidBody('Gider türü geçersiz (rutin ya da beklenmedik olmalıdır).');
  }
  return value;
}

/** Öneri için veritabanı olguları (okuma). expenseDate 'YYYY-MM-DD'. */
export async function loadSuggestionFacts(db, siteCode, { categoryId, supplierId, expenseDate }) {
  const category = await db.query(`SELECT name FROM expense_categories WHERE id = $1 AND site_code = $2`, [categoryId, siteCode]);
  if (!category.rows?.[0]) {
    throw invalidBody('Kategori bulunamadı.');
  }
  let activeContract = false;
  if (supplierId !== null && supplierId !== undefined) {
    const supplier = await db.query(`SELECT name FROM finance_suppliers WHERE id = $1 AND site_code = $2`, [supplierId, siteCode]);
    if (supplier.rows?.[0]) {
      const match = await db.query(
        `
          SELECT 1 FROM site_contracts c INNER JOIN contract_vendors v ON v.id = c.vendor_id
          WHERE c.site_code = $1 AND c.status = 'aktif' AND c.period IN ('aylik', 'yillik')
            AND c.start_date <= $2::DATE AND (c.end_date IS NULL OR c.end_date >= $2::DATE) AND ${foldSql('v.name')} = $3
          LIMIT 1
        `,
        [siteCode, expenseDate, foldText(supplier.rows[0].name)],
      );
      activeContract = Boolean(match.rows?.[0]);
    }
  }
  const recent = await db.query(
    `
      SELECT COUNT(DISTINCT date_trunc('month', e.expense_date))::INTEGER AS months
      FROM expenses e
      WHERE e.site_code = $1 AND e.category_id = $2 AND e.supplier_id IS NOT DISTINCT FROM $3::BIGINT
        AND e.expense_date >= ($4::DATE - INTERVAL '3 months') AND e.expense_date < date_trunc('month', $4::DATE)::DATE
        AND NOT EXISTS (SELECT 1 FROM expense_voids v WHERE v.expense_id = e.id)
    `,
    [siteCode, categoryId, supplierId ?? null, expenseDate],
  );
  return { activeContract, recurringMonths: Number(recent.rows?.[0]?.months ?? 0), categoryName: category.rows[0].name };
}

/** GET expenses/nature-suggestion?category_id&supplier_id&expense_date -> { nature, reason, reason_text }. */
export async function getNatureSuggestion(siteCode, query = {}, db = pool) {
  const categoryId = optionalId(query.category_id, 'Kategori');
  if (categoryId === null) {
    throw invalidBody('Kategori seçin.');
  }
  const supplierId = optionalId(query.supplier_id, 'Tedarikçi');
  const expenseDate = parseIsoDate(query.expense_date, 'Gider tarihi');
  const suggestion = suggestExpenseNature(await loadSuggestionFacts(db, siteCode, { categoryId, supplierId, expenseDate }));
  return { ...suggestion, reason_text: NATURE_REASON_TEXT[suggestion.reason] };
}

/** Gider yazımı içinde çağrılır (işlem açık): tür kaydını yazar. nature verilmediyse öneri 'suggested' olarak yazılır. */
export async function writeExpenseNature(client, { siteCode, expenseId, nature, actorUserCode, facts }) {
  const manual = nature !== null && nature !== undefined;
  const value = manual ? nature : suggestExpenseNature(facts).nature;
  await client.query(
    `INSERT INTO expense_natures (expense_id, site_code, nature, source, set_by) VALUES ($1, $2, $3, $4, $5) ON CONFLICT (expense_id) DO NOTHING`,
    [expenseId, siteCode, value, manual ? 'manual' : 'suggested', actorUserCode ?? null],
  );
  return value;
}

/** PUT expenses/:id/nature { nature } -> { expense_id, nature, nature_source }. İptal edilmiş giderde 409. */
export async function setExpenseNature({ siteCode, rawId, body, actor }) {
  const id = parsePositiveId(rawId);
  if (id === null) {
    throw expenseNotFound();
  }
  const nature = parseNature(body?.nature);
  if (nature === null) {
    throw invalidBody('Gider türünü seçin.');
  }
  const actorInfo = actorFromAuthUser(actor);
  return withFinanceTransaction(siteCode, async (client) => {
    await lockActorRow(client, actorInfo);
    const found = await client.query(
      `SELECT e.id, (SELECT COUNT(*) FROM expense_voids v WHERE v.expense_id = e.id)::INTEGER AS voided FROM expenses e WHERE e.id = $1 AND e.site_code = $2`,
      [id, siteCode],
    );
    if (!found.rows?.[0]) {
      throw expenseNotFound();
    }
    if (Number(found.rows[0].voided) > 0) {
      throw expenseAlreadyVoided();
    }
    await client.query(
      `
        INSERT INTO expense_natures (expense_id, site_code, nature, source, set_by) VALUES ($1, $2, $3, 'manual', $4)
        ON CONFLICT (expense_id) DO UPDATE SET nature = EXCLUDED.nature, source = 'manual', set_by = EXCLUDED.set_by, set_at = NOW()
      `,
      [id, siteCode, nature, actorInfo.userCode ?? null],
    );
    await recordFinanceAudit(client, actor, 'finance.expense.nature_set', siteCode, id, { expense_id: id, nature });
    return { expense_id: id, nature, nature_source: 'manual' };
  });
}
