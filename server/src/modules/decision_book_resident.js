// Karar Defteri: sakin tarafı (liste / ayrıntı; salt okuma).
//
// Sözleşme: docs/PLATFORM_KARAR_DEFTERI.md. Sakin YALNIZ sitesinin KESİN ve görünürlüğü `sakinler` olan kararlarını görür; taslak ve `yonetim` kararları ASLA.
// "Sitenin sakini" (canlı değerlendirilir): o sitede AKTİF dairede aktif apartment_memberships, ya da AKTİF site_people kaydı + AKTİF dairede GÜNCEL ilişki
// (malik dahil: kat malikleri kurulu kararları malike de açıktır), ya da eski apartments.resident_user_code bağı, ya da aktif site_memberships RESIDENT kaydı.
// Site `approved` ve `decision_book` modülü AÇIK olmalı. Görünmeyen / yok / modül kapalı -> 404 DECISION_NOT_FOUND (varlık sızmaz).
// Liste: site_code verilmiş ve çağıran o sitenin sakini değilse boş liste (modül durumu yalnız sakine söylenir); sakini olduğu sitede modül kapalıysa 403 MODULE_DISABLED.
// Sakin görünümü: status, visibility, created_by_name YOK; superseded_by yalnız sakinlere de görünen kararları listeler (bkz. decision_book_common.mapDecision).

import { pool } from '../db.js';
import { actorFromAuthUser } from './audit_service.js';
import { isModuleEnabled } from './module_service.js';
import { parsePositiveId } from './people_common.js';
import {
  DECISION_BOOK_MODULE,
  ORDER_SQL,
  accountDeleted,
  afterKeySql,
  decisionNotFound,
  encodeCursor,
  moduleDisabled,
  parseResidentListQuery,
  sortKeyOf,
} from './decision_book_common.js';
import { DECISION_COLUMNS, DECISION_JOINS, mapRows } from './decision_book_service.js';

/** Çağıranın sakini olduğu ONAYLI siteler (CTE `my_sites`, bir kez hesaplanır). Kullanan her sorgu `WITH ${mySitesCte('$1')}` ile başlar. */
export function mySitesCte(user = '$1') {
  return `my_sites AS MATERIALIZED (
    SELECT u.site_code
    FROM (
      SELECT ap.site_code
      FROM apartment_memberships am
      INNER JOIN apartments ap ON ap.id = am.apartment_id AND ap.is_active = TRUE
      WHERE am.user_code = ${user} AND am.is_active = TRUE
      UNION
      SELECT ap.site_code
      FROM site_people sp
      INNER JOIN apartment_residencies r ON r.person_id = sp.id AND r.is_current = TRUE
      INNER JOIN apartments ap ON ap.id = r.apartment_id AND ap.is_active = TRUE AND ap.site_code = sp.site_code
      WHERE sp.user_code = ${user} AND sp.is_active = TRUE
      UNION
      SELECT ap.site_code FROM apartments ap WHERE ap.resident_user_code = ${user} AND ap.is_active = TRUE
      UNION
      SELECT sm.site_code FROM site_memberships sm WHERE sm.user_code = ${user} AND sm.is_active = TRUE AND sm.role = 'RESIDENT'
    ) u
    INNER JOIN sites s0 ON s0.site_code = u.site_code AND s0.approval_status = 'approved'
  )`;
}

/** `decision_book` modülü kararın sitesinde AÇIK mı (katalog varsayılanı KAPALI: satır yoksa kapalı). */
const MODULE_ON = `EXISTS (SELECT 1 FROM site_modules smod WHERE smod.site_code = d.site_code AND smod.module_code = '${DECISION_BOOK_MODULE}' AND smod.enabled = TRUE)`;

/** Sakine görünür karar (takma ad `d`; `my_sites` CTE'si gerekir). */
const VISIBLE_SQL = `d.status = 'kesin' AND d.visibility = 'sakinler' AND d.site_code IN (SELECT site_code FROM my_sites) AND ${MODULE_ON}`;

function userCodeOf(authUser) {
  const userCode = actorFromAuthUser(authUser).userCode;
  if (userCode === null) {
    throw accountDeleted();
  }
  return userCode;
}

const emptyPage = (years = []) => ({ items: [], next_before_id: null, next_cursor: null, years });

/**
 * GET /app/decisions -> { items, next_before_id, next_cursor, years }. Sıra yıl ve karar numarası azalan (birden çok sitede kimlik azalan). Sayfa: `cursor` (önerilen)
 * ya da `before_id`. `years`: görünür kararların yılları (yıl süzgecinden bağımsız; site_code verilmişse o site).
 */
export async function listMyDecisions(authUser, query = {}, db = pool) {
  const filters = parseResidentListQuery(query);
  const userCode = userCodeOf(authUser);
  if (filters.siteCode !== null) {
    const related = await db.query(`WITH ${mySitesCte('$1')} SELECT EXISTS (SELECT 1 FROM my_sites WHERE site_code = $2) AS related`, [userCode, filters.siteCode]);
    if (related.rows?.[0]?.related !== true) {
      return emptyPage();
    }
    if (!(await isModuleEnabled(filters.siteCode, DECISION_BOOK_MODULE, db))) {
      throw moduleDisabled();
    }
  }
  const params = [userCode];
  const base = [VISIBLE_SQL];
  if (filters.siteCode !== null) {
    params.push(filters.siteCode);
    base.push(`d.site_code = $${params.length}`);
  }
  const yearsResult = await db.query(`WITH ${mySitesCte('$1')} SELECT DISTINCT d.year FROM board_decisions d WHERE ${base.join(' AND ')} ORDER BY d.year DESC`, params);
  const years = (yearsResult.rows ?? []).map((row) => Number(row.year));
  const clauses = [...base];
  if (filters.year !== null) {
    params.push(filters.year);
    clauses.push(`d.year = $${params.length}`);
  }
  let key = filters.cursor;
  if (key === null && filters.beforeId !== null) {
    const anchor = await db.query(
      `WITH ${mySitesCte('$1')} SELECT d.id, d.status, d.year, d.decision_no FROM board_decisions d WHERE d.id = $2 AND ${VISIBLE_SQL} LIMIT 1`,
      [userCode, filters.beforeId],
    );
    if (!anchor.rows?.[0]) {
      return emptyPage(years);
    }
    key = sortKeyOf(anchor.rows[0]);
  }
  if (key !== null) {
    clauses.push(afterKeySql(key, params));
  }
  params.push(filters.limit + 1);
  const result = await db.query(
    `WITH ${mySitesCte('$1')} SELECT ${DECISION_COLUMNS} FROM board_decisions d ${DECISION_JOINS} WHERE ${clauses.join(' AND ')} ORDER BY ${ORDER_SQL('d')} LIMIT $${params.length}`,
    params,
  );
  const rows = result.rows ?? [];
  const hasMore = rows.length > filters.limit;
  const page = rows.slice(0, filters.limit);
  const last = page[page.length - 1];
  return {
    items: await mapRows(db, page, { resident: true }),
    next_before_id: hasMore && last ? Number(last.id) : null,
    next_cursor: hasMore && last ? encodeCursor(sortKeyOf(last)) : null,
    years,
  };
}

/** GET /app/decisions/:id -> { decision } (sakin görünümü). Görünmeyen / yok / taslak / yonetim / modül kapalı -> 404. */
export async function getMyDecision(authUser, rawId, db = pool) {
  const userCode = userCodeOf(authUser);
  const id = parsePositiveId(rawId);
  if (id === null) {
    throw decisionNotFound();
  }
  const result = await db.query(
    `WITH ${mySitesCte('$1')} SELECT ${DECISION_COLUMNS} FROM board_decisions d ${DECISION_JOINS} WHERE d.id = $2 AND ${VISIBLE_SQL} LIMIT 1`,
    [userCode, id],
  );
  const row = result.rows?.[0];
  if (!row) {
    throw decisionNotFound();
  }
  const [decision] = await mapRows(db, [row], { resident: true });
  return { decision };
}
