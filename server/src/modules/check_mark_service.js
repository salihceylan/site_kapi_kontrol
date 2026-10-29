// Kontrol izi (110, P2-20): gider kaydı ve dekont bildirimi için "kontrol edildi (kim, ne zaman)" işareti. Muhasebeci ROLÜ açılmaz: işareti
// siteyi yöneten kullanıcı (yönetici / süper) koyar ve kaldırır; kurul salt okur. İz AYRI yan tablolardadır (check_mark_schema.js): gider satırı ve
// karara bağlanmış dekont satırı DEĞİŞMEZ; dekont onay / ret akışına dokunulmaz.
//
// Kurallar:
// - Koyma idempotenttir: işaret zaten varsa İLK işaret korunur (kim / ne zaman değişmez), yanıt replayed:true. Başkasının işaretini yenilemek için önce kaldırılır.
// - İptal edilmiş giderde yeni işaret konmaz (409 EXPENSE_ALREADY_VOIDED); yüklenen / geri çekilen dekontta konmaz (409 NOTICE_INVALID_STATE). Kaldırma her durumda açıktır.
// - Konu, işlemi yapanın sitesinde aranır (başka sitenin kaydı 404: kimlik tahmini ile iz konamaz / okunamaz).
// - Konulması ve kaldırılması denetim kaydındadır (target_type 'finance'; ayrıntıda yalnız kayıt kimliği).
// Sözleşme: docs/PLATFORM_FINANS_4B.md "Kontrol izi".

import { actorFromAuthUser } from './audit_service.js';
import { checkMarkFields } from './check_mark_common.js';
import { CHECK_MARK_TABLES } from './check_mark_schema.js';
import { expenseAlreadyVoided, expenseNotFound } from './finance_4b_common.js';
import { lockActorRow, recordFinanceAudit, withFinanceTransaction } from './finance_tx.js';
import { noticeInvalidState, noticeNotFound } from './payment_notice_common.js';
import { parsePositiveId } from './people_common.js';

const tableOf = (kind) => CHECK_MARK_TABLES.find((spec) => spec.kind === kind);

/** Konu türüne göre: tablo, konu sütunu, bulunamadı hatası, işaret konabilir mi, denetim eylemleri. */
const SUBJECTS = Object.freeze({
  expense: Object.freeze({
    ...tableOf('expense'),
    notFound: expenseNotFound,
    /** İptal edilmiş gider yeni işaret almaz. */
    async loadSubject(client, siteCode, id) {
      const found = await client.query(
        `SELECT e.id, (SELECT COUNT(*) FROM expense_voids v WHERE v.expense_id = e.id)::INTEGER AS voided FROM expenses e WHERE e.id = $1 AND e.site_code = $2`,
        [id, siteCode],
      );
      return found.rows?.[0] ?? null;
    },
    assertMarkable(row) {
      if (Number(row.voided) > 0) throw expenseAlreadyVoided();
    },
    actions: Object.freeze({ set: 'finance.expense.check_set', cleared: 'finance.expense.check_cleared' }),
  }),
  payment_notice: Object.freeze({
    ...tableOf('payment_notice'),
    notFound: noticeNotFound,
    async loadSubject(client, siteCode, id) {
      const found = await client.query(`SELECT n.id, n.status FROM payment_notices n WHERE n.id = $1 AND n.site_code = $2`, [id, siteCode]);
      return found.rows?.[0] ?? null;
    },
    assertMarkable(row) {
      if (!['pending', 'approved', 'rejected'].includes(row.status)) {
        throw noticeInvalidState('Yüklenmesi bitmeyen ya da geri çekilen bildirime kontrol işareti konamaz.');
      }
    },
    actions: Object.freeze({ set: 'finance.payment_notice.check_set', cleared: 'finance.payment_notice.check_cleared' }),
  }),
});

export const CHECK_MARK_KINDS = Object.freeze(Object.keys(SUBJECTS));

async function loadMark(db, spec, siteCode, id) {
  const result = await db.query(
    `SELECT m.checked_at, u.full_name AS checked_by_name FROM ${spec.table} m LEFT JOIN users u ON u.user_code = m.checked_by WHERE m.${spec.subject} = $1 AND m.site_code = $2`,
    [id, siteCode],
  );
  return result.rows?.[0] ?? null;
}

function subjectOf(kind) {
  const spec = SUBJECTS[kind];
  if (!spec) throw new Error(`Bilinmeyen kontrol izi türü: ${kind}`);
  return spec;
}

/**
 * İşareti koyar. Dönüş { id, checked_at, checked_by_name, replayed }.
 * @param {{ siteCode: number, kind: 'expense'|'payment_notice', rawId: unknown, actor: object }} input
 */
export async function setCheckMark({ siteCode, kind, rawId, actor }) {
  const spec = subjectOf(kind);
  const id = parsePositiveId(rawId);
  if (id === null) throw spec.notFound();
  const actorInfo = actorFromAuthUser(actor);
  return withFinanceTransaction(siteCode, async (client) => {
    await lockActorRow(client, actorInfo);
    const subject = await spec.loadSubject(client, siteCode, id);
    if (!subject) throw spec.notFound();
    const existing = await loadMark(client, spec, siteCode, id);
    if (existing) return { id, ...checkMarkFields(existing), replayed: true };
    spec.assertMarkable(subject);
    await client.query(`INSERT INTO ${spec.table} (${spec.subject}, site_code, checked_by) VALUES ($1, $2, $3) ON CONFLICT (${spec.subject}) DO NOTHING`, [id, siteCode, actorInfo.userCode ?? null]);
    const mark = await loadMark(client, spec, siteCode, id);
    await recordFinanceAudit(client, actor, spec.actions.set, siteCode, id, { [spec.subject]: id });
    return { id, ...checkMarkFields(mark), replayed: false };
  });
}

/** İşareti kaldırır (iptal edilmiş gider dahil). İz yoksa replayed:true. Dönüş { id, checked_at: null, checked_by_name: null, replayed }. */
export async function clearCheckMark({ siteCode, kind, rawId, actor }) {
  const spec = subjectOf(kind);
  const id = parsePositiveId(rawId);
  if (id === null) throw spec.notFound();
  const actorInfo = actorFromAuthUser(actor);
  return withFinanceTransaction(siteCode, async (client) => {
    await lockActorRow(client, actorInfo);
    const subject = await spec.loadSubject(client, siteCode, id);
    if (!subject) throw spec.notFound();
    const removed = await client.query(`DELETE FROM ${spec.table} WHERE ${spec.subject} = $1 AND site_code = $2`, [id, siteCode]);
    const didRemove = (removed.rowCount ?? 0) > 0;
    if (didRemove) {
      await recordFinanceAudit(client, actor, spec.actions.cleared, siteCode, id, { [spec.subject]: id });
    }
    return { id, ...checkMarkFields(null), replayed: !didRemove };
  });
}

/**
 * Dekont listesine / ayrıntısına iz alanlarını ekler (tek sorgu). Girdi değişmez; her öğeye checked_at ve checked_by_name eklenir.
 * Yalnız yönetici yanıtlarında kullanılır (sakin yanıtları muhasebe izini taşımaz).
 */
export async function attachNoticeCheckMarks(db, siteCode, notices) {
  if (!Array.isArray(notices) || notices.length === 0) return notices ?? [];
  const spec = SUBJECTS.payment_notice;
  const ids = notices.map((notice) => Number(notice.id));
  const result = await db.query(
    `SELECT m.${spec.subject} AS id, m.checked_at, u.full_name AS checked_by_name FROM ${spec.table} m LEFT JOIN users u ON u.user_code = m.checked_by WHERE m.site_code = $1 AND m.${spec.subject} = ANY($2::BIGINT[])`,
    [siteCode, ids],
  );
  const byId = new Map((result.rows ?? []).map((row) => [Number(row.id), row]));
  return notices.map((notice) => ({ ...notice, ...checkMarkFields(byId.get(Number(notice.id))) }));
}
