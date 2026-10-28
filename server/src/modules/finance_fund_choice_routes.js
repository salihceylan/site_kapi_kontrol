// Tahsilat hesap seçimi (K3, karşılaştırma raporu P1-3) ucu (ayrı router; server.js `app.use(financeFundChoiceRouter)`).
//
//   GET /manager/sites/:siteCode/finance/payments/fund-choice?apartment_id=&account_party=&amount_minor=&paid_on=
//     -> { apartment_id, account_party, open: { operating_minor, capital_minor }, advance_minor, choice_required, suggested_fund, proposal }
//
// Tahsilat formlarının (elle tahsilat, dekont onayı, banka satırı) "hangi hesaba işlensin" bölümü bu uçla beslenir: iki türün de (İşletme / Fon) açık borcu varsa
// `choice_required` true'dur ve seçim ZORUNLUDUR (sunucu seçimsiz kaydı 400 FUND_CHOICE_REQUIRED ile reddeder); tek türün açık borcu varsa `suggested_fund` o hesaptır
// (form seçili getirir, yönetici değiştirebilir). `proposal` (tutar verilmişse) otomatik dağıtımın ne yapacağını yalnız BİLGİ olarak gösterir; hiçbir şey yazılmaz.
// `account_party` verilmezse tahsilat hesabı postPayment ile aynı kuralla çözülür (vadesi en eski açık borcu olan hesap).
// Yetki: yazma yetkisi (yönetici / süper); kurul, görevli ve sakin 403. Bu uç yazmaz.

import express from 'express';
import { authRequired } from '../middlewares/auth_middleware.js';
import { pool } from '../db.js';
import { apartmentNotFound, invalidQuery, parseAccountPartyQuery, parseIsoDate, today } from './finance_common.js';
import { fundChoiceBody, loadFundChoice } from './finance_fund_choice.js';
import { parseMinor } from './finance_money.js';
import { defaultPaymentParty } from './finance_parties.js';
import { BASE, financeReadLimiter, managerHandler } from './finance_routes.js';
import { parsePositiveId } from './people_common.js';

export const financeFundChoiceRouter = express.Router();

function parseAmountQuery(raw) {
  if (raw === undefined || raw === null || String(raw).trim() === '') {
    return null;
  }
  const text = String(raw).trim();
  if (!/^\d{1,15}$/.test(text)) {
    throw invalidQuery();
  }
  const amount = parseMinor(Number(text));
  if (amount === null) {
    throw invalidQuery();
  }
  return amount;
}

function parsePaidOnQuery(raw, now) {
  if (raw === undefined || raw === null || String(raw).trim() === '') {
    return today(now);
  }
  return parseIsoDate(String(raw), 'Tahsilat tarihi');
}

/**
 * GET payments/fund-choice gövdesi. `db`: havuz ya da bağlantı (testlerde sahte). Daire bu sitede yoksa 404 APARTMENT_NOT_FOUND.
 */
export async function previewFundChoice(siteCode, query = {}, { db = pool, now = new Date() } = {}) {
  const apartmentId = parsePositiveId(query.apartment_id);
  if (apartmentId === null) {
    throw invalidQuery();
  }
  const requestedParty = parseAccountPartyQuery(query.account_party);
  const amountMinor = parseAmountQuery(query.amount_minor);
  const paidOn = parsePaidOnQuery(query.paid_on, now);
  const apartment = await db.query(`SELECT id FROM apartments WHERE id = $1 AND site_code = $2`, [apartmentId, siteCode]);
  if (!apartment.rows?.[0]) {
    throw apartmentNotFound();
  }
  const accountParty = requestedParty ?? (await defaultPaymentParty(db, { siteCode, apartmentId, onDate: paidOn }));
  const { choice, proposal } = await loadFundChoice(db, { siteCode, apartmentId, accountParty, amountMinor, paidOn });
  return fundChoiceBody(choice, { apartmentId, accountParty, proposal });
}

financeFundChoiceRouter.get(
  `${BASE}/payments/fund-choice`,
  authRequired,
  financeReadLimiter,
  managerHandler({ context: 'finance_fund_choice', fallback: 'Hesap bilgisi yüklenemedi.', write: true }, async ({ req, access }) => ({
    body: await previewFundChoice(access.siteCode, req.query ?? {}),
  })),
);
