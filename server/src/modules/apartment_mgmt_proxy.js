// Vekalet (toplanti imzasi, kurul uyeligi) ve Karar Defteri imza hakki sahibi cozumleme. Sozlesme: docs/PLATFORM_DAIRE_YONETIMI.md.
//
//  - Vekalet IC KAYITTIR: resmi genel kurulda yazili vekaletname gerekebilir [AVUKAT DOGRULASIN: KMK m.29].
//  - Vekil, dairenin GUNCEL kiracisidir; kiraci cikinca vekalet iptal olur. Vekalet yoksa imza hakki MALIKTEDIR; ayni daire icin tek kisi.

import { pool } from '../db.js';
import { PlatformError } from './errors.js';
import { SCOPES, pickSigningHolder, proxyIsActive, resolveProxyWindow, signingLabel } from './apartment_mgmt_rules.js';
import { auditApartment, ensureOwnerRecord, withApartment } from './apartment_mgmt_service.js';
import { apartmentLabel, dateToIso, invalidBody, parsePositiveId, todayIso } from './people_common.js';

const forbidden = (message) => new PlatformError(403, 'FORBIDDEN_ROLE', message);

/** POST /app/apartments/:id/proxies  { scope, valid_from?, valid_until? } (yalniz malik; vekil = guncel kiraci) */
export async function createProxy({ authUser, apartmentId, body }) {
  const scope = body?.scope;
  if (!SCOPES.includes(scope)) {
    throw invalidBody('scope', 'Vekalet kapsamı "toplanti_imza" ya da "kurul_uyeligi" olmalı.');
  }
  const today = todayIso();
  const window = resolveProxyWindow({
    validFrom: body?.valid_from === undefined || body?.valid_from === null || body?.valid_from === '' ? undefined : body.valid_from,
    validUntil: body?.valid_until === undefined || body?.valid_until === null || body?.valid_until === '' ? undefined : body.valid_until,
    today,
  });
  if (window.error) {
    throw invalidBody(window.error, window.message);
  }
  return withApartment(authUser, apartmentId, async ({ client, state, me, uc, siteCode }) => {
    if (!me.is_owner) {
      throw forbidden('Vekaleti yalnızca dairenin maliki verebilir.');
    }
    const tenant = state.roles.tenant;
    if (!tenant) {
      throw new PlatformError(409, 'NO_TENANT', 'Vekalet kiracıya verilir; bu dairede kiracı yok.');
    }
    const ownerPersonId = await ensureOwnerRecord(client, authUser, state, me, uc);
    // Suresi dolmus acik vekaleti kapat (yeni vekalete yer ac); gecerli olan varsa reddet.
    await client.query(
      `UPDATE apartment_proxies SET revoked_at = NOW(), revoked_reason = 'expired'
       WHERE apartment_id = $1 AND scope = $2 AND revoked_at IS NULL AND valid_until < $3::date`,
      [state.apartment.id, scope, today],
    );
    const open = await client.query(
      `SELECT id FROM apartment_proxies WHERE apartment_id = $1 AND scope = $2 AND revoked_at IS NULL LIMIT 1`,
      [state.apartment.id, scope],
    );
    if (open.rows?.[0]) {
      throw new PlatformError(409, 'PROXY_EXISTS', 'Bu kapsam için geçerli bir vekalet var. Önce onu iptal edin.');
    }
    const inserted = await client.query(
      `INSERT INTO apartment_proxies (site_code, apartment_id, owner_person_id, proxy_person_id, scope, valid_from, valid_until, created_by)
       VALUES ($1, $2, $3, $4, $5, $6::date, $7::date, $8) RETURNING id`,
      [siteCode, state.apartment.id, ownerPersonId, tenant.person_id, scope, window.valid_from, window.valid_until, uc],
    );
    await auditApartment(client, authUser, 'apartment_mgmt.proxy_created', state, {
      proxy_id: Number(inserted.rows[0].id),
      scope,
      proxy_person_id: tenant.person_id,
      valid_from: window.valid_from,
      valid_until: window.valid_until,
    });
    return { ok: true, id: Number(inserted.rows[0].id), valid_from: window.valid_from, valid_until: window.valid_until };
  });
}

/** DELETE /app/apartments/:id/proxies/:proxyId  (malik iptal eder; vekil de vekaletten cekilebilir) */
export async function revokeProxy({ authUser, apartmentId, proxyId }) {
  const pid = parsePositiveId(proxyId);
  return withApartment(authUser, apartmentId, async ({ client, state, me, uc }) => {
    const proxy = (await client.query(
      `SELECT id, scope, proxy_person_id, revoked_at FROM apartment_proxies WHERE id = $1 AND apartment_id = $2 FOR UPDATE`,
      [pid, state.apartment.id],
    )).rows?.[0];
    if (!proxy || proxy.revoked_at) {
      throw new PlatformError(404, 'PROXY_NOT_FOUND', 'Vekalet bulunamadı ya da zaten iptal edilmiş.');
    }
    const isHolder = state.roles.tenant && Number(state.roles.tenant.person_id) === Number(proxy.proxy_person_id) && me.is_tenant;
    if (!me.is_owner && !isHolder) {
      throw forbidden('Vekaleti yalnızca malik iptal edebilir ya da vekil çekilebilir.');
    }
    await client.query(
      `UPDATE apartment_proxies SET revoked_at = NOW(), revoked_by = $2, revoked_reason = $3 WHERE id = $1`,
      [proxy.id, uc, me.is_owner ? 'owner' : 'proxy_resigned'],
    );
    await auditApartment(client, authUser, 'apartment_mgmt.proxy_revoked', state, {
      proxy_id: Number(proxy.id),
      scope: proxy.scope,
      by: me.is_owner ? 'owner' : 'proxy',
    });
    return { ok: true };
  });
}

// ---------------------------------------------------------------------------
// Karar Defteri: imza hakki sahibi listesi
// ---------------------------------------------------------------------------

const ROSTER_LIMIT = 3000;

/**
 * GET /manager/sites/:siteCode/signing-roster?date=YYYY-MM-DD  (varsayilan bugun; gecmis tarih yok, en cok 366 gun ileri)
 * Her aktif daire icin imza hakki sahibi: aktif vekil varsa vekil, yoksa malik. Kurul uyeligi vekaleti ayrica `board_proxy`.
 * Tarih yalniz GELECEKTEKI bir toplanti icin vekalet penceresini degerlendirir; gecmise donuk durum yeniden kurulamaz.
 */
export async function signingRoster({ siteCode, date }) {
  const today = todayIso();
  const on = date ?? today;
  const w = resolveProxyWindow({ validFrom: on, validUntil: on, today });
  if (w.error) {
    throw invalidBody('date', 'Tarih bugün ya da sonrası olmalı (en fazla bir yıl ileri).');
  }
  const apartments = (await pool.query(
    `SELECT a.id, a.unit_label, b.block_name
     FROM apartments a LEFT JOIN site_blocks b ON b.id = a.block_id
     WHERE a.site_code = $1 AND a.is_active = TRUE
     ORDER BY b.block_name NULLS FIRST, a.sort_order, a.id
     LIMIT ${ROSTER_LIMIT}`,
    [siteCode],
  )).rows ?? [];
  const residencies = (await pool.query(
    `SELECT r.apartment_id, r.relation, r.person_id,
            COALESCE(NULLIF(u.full_name, ''), sp.full_name) AS name
     FROM apartment_residencies r
     INNER JOIN site_people sp ON sp.id = r.person_id
     LEFT JOIN users u ON u.user_code = sp.user_code
     WHERE r.site_code = $1 AND r.is_current = TRUE AND r.relation IN ('owner', 'tenant')`,
    [siteCode],
  )).rows ?? [];
  const proxies = (await pool.query(
    `SELECT p.id, p.apartment_id, p.scope, p.valid_from, p.valid_until, p.revoked_at, p.proxy_person_id,
            COALESCE(NULLIF(pu.full_name, ''), pp.full_name) AS proxy_name
     FROM apartment_proxies p
     INNER JOIN site_people pp ON pp.id = p.proxy_person_id
     LEFT JOIN users pu ON pu.user_code = pp.user_code
     WHERE p.site_code = $1 AND p.revoked_at IS NULL`,
    [siteCode],
  )).rows ?? [];

  const byApartment = new Map();
  for (const r of residencies) {
    const entry = byApartment.get(Number(r.apartment_id)) ?? {};
    entry[r.relation] = { person_id: Number(r.person_id), name: r.name ?? '' };
    byApartment.set(Number(r.apartment_id), entry);
  }
  const proxiesByApartment = new Map();
  for (const p of proxies) {
    const list = proxiesByApartment.get(Number(p.apartment_id)) ?? [];
    list.push(p);
    proxiesByApartment.set(Number(p.apartment_id), list);
  }

  const items = apartments.map((a) => {
    const id = Number(a.id);
    const roles = byApartment.get(id) ?? {};
    const mine = (proxiesByApartment.get(id) ?? []).map((p) => ({
      id: Number(p.id),
      scope: p.scope,
      valid_from: dateToIso(p.valid_from),
      valid_until: dateToIso(p.valid_until),
      revoked_at: p.revoked_at,
      proxy_person_id: Number(p.proxy_person_id),
      proxy_name: p.proxy_name ?? '',
      // Vekil hala dairenin guncel kiracisi degilse vekalet yok sayilir.
      holder_ok: roles.tenant ? roles.tenant.person_id === Number(p.proxy_person_id) : false,
    }));
    const holder = pickSigningHolder({ owner: roles.owner ?? null, proxies: mine, today: on });
    const boardProxy = mine.find((p) => p.scope === 'kurul_uyeligi' && p.holder_ok && proxyIsActive(p, on)) ?? null;
    const label = apartmentLabel(a.block_name, a.unit_label);
    return {
      apartment_id: id,
      label,
      holder_kind: holder.kind,
      holder_name: holder.name || null,
      owner_name: roles.owner?.name ?? null,
      proxy_valid_until: holder.kind === 'proxy' ? holder.valid_until : null,
      board_proxy_name: boardProxy ? boardProxy.proxy_name : null,
      label_text: signingLabel(label, holder),
    };
  });
  return { date: on, items, truncated: apartments.length >= ROSTER_LIMIT };
}
