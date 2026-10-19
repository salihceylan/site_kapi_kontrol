// Kartlı Geçiş: cihaz yolu için kart doğrulama yardımcısı. MQTT'ye / door_access_policy'ye BAĞLI DEĞİLDİR (firmware ve köprü bağlantısı SONRAKİ adım,
// bkz. docs/PLATFORM_GECIS_GENISLEME.md "Cihaz protokolü önerisi").
//
// Karar (saf, `decideCardVerification`): modül kapalı -> module_disabled; kart yok -> card_unknown; kart iptal -> card_revoked;
// kişi pasif ya da sitede güncel dairesi / üyeliği yok -> person_inactive; aksi halde ok.
// `verifyCardForDoor` yalnız SALT OKUNUR iki sorgu atar (modül + kart/kişi), kilit almaz, yazmaz; `db` enjekte edilebilir (test / QA).

import { pool } from '../db.js';
import { CARD_ACCESS_MODULE, normalizeCardUid } from './card_access_common.js';

export const VERIFY_REASONS = Object.freeze(['module_disabled', 'card_unknown', 'card_revoked', 'person_inactive']);

/**
 * Saf karar.
 * @param {{ moduleEnabled: boolean, card: { id?: number, person_id?: number|string, is_active?: boolean } | null, personActive: boolean }} input
 * @returns {{ ok: boolean, reason: string|null, person_id: number|null }}
 */
export function decideCardVerification({ moduleEnabled, card, personActive }) {
  if (moduleEnabled !== true) return { ok: false, reason: 'module_disabled', person_id: null };
  if (!card) return { ok: false, reason: 'card_unknown', person_id: null };
  const personId = card.person_id === null || card.person_id === undefined ? null : Number(card.person_id);
  if (card.is_active !== true) return { ok: false, reason: 'card_revoked', person_id: personId };
  if (personActive !== true) return { ok: false, reason: 'person_inactive', person_id: personId };
  return { ok: true, reason: null, person_id: personId };
}

/** Site + UID için en anlamlı kart (önce aktif, sonra en son iptal edilen) ve kişinin o sitedeki güncel durumu. */
const CARD_SQL = `
  SELECT c.id, c.person_id, c.is_active,
    (
      sp.is_active = TRUE AND sp.site_code = c.site_code AND (
        EXISTS (SELECT 1 FROM apartment_residencies ar WHERE ar.person_id = sp.id AND ar.site_code = c.site_code AND ar.is_current = TRUE)
        OR (sp.user_code IS NOT NULL AND EXISTS (
          SELECT 1 FROM apartment_memberships am
          INNER JOIN apartments ap ON ap.id = am.apartment_id
          WHERE am.user_code = sp.user_code AND am.is_active = TRUE AND ap.site_code = c.site_code
        ))
      )
    ) AS person_active
  FROM access_cards c
  INNER JOIN site_people sp ON sp.id = c.person_id
  WHERE c.site_code = $1 AND c.card_uid = $2
  ORDER BY c.is_active DESC, c.id DESC
  LIMIT 1
`;

const MODULE_SQL = `SELECT enabled FROM site_modules WHERE site_code = $1 AND module_code = $2 LIMIT 1`;

/**
 * Okuyucudan gelen kart için geçiş kararı.
 * @param {{ siteCode: number|string, cardUid: string, now?: Date, db?: { query: Function } }} input
 * @returns {Promise<{ ok: boolean, reason: string|null, person_id: number|null }>}
 */
export async function verifyCardForDoor({ siteCode, cardUid, now = new Date(), db = pool }) {
  void now; // zaman damgası ileride geçerlilik aralığı için ayrılmıştır; karar şimdilik zaman bağımsızdır
  const site = Number(siteCode);
  const uid = normalizeCardUid(cardUid);
  if (!Number.isSafeInteger(site) || site <= 0) return { ok: false, reason: 'module_disabled', person_id: null };
  // card_access katalogda varsayılan KAPALI: satır yoksa kapalı sayılır (computeModuleEnabled ile aynı sonuç, ek katalog bağımlılığı yok).
  const moduleRow = (await db.query(MODULE_SQL, [site, CARD_ACCESS_MODULE])).rows?.[0] ?? null;
  const moduleEnabled = moduleRow?.enabled === true;
  if (!moduleEnabled) return decideCardVerification({ moduleEnabled: false, card: null, personActive: false });
  if (uid === null) return decideCardVerification({ moduleEnabled: true, card: null, personActive: false });
  const row = (await db.query(CARD_SQL, [site, uid])).rows?.[0] ?? null;
  return decideCardVerification({ moduleEnabled: true, card: row, personActive: row?.person_active === true });
}
