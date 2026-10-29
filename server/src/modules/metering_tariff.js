// Sayac tarifesi (birim fiyat, tur basina, gecerlilik tarihli). Sozlesme: docs/PLATFORM_SAYAC.md (Tarife).
// Yeni tarife, turdeki acik (valid_to bos) son tarifeyi kendi baslangic tarihinde kapatir; tarifeler degistirilmez / silinmez (duzeltme = yeni tarife).
// Gecmis faturalandirmalar etkilenmez: fiyat kayit aninda meter_billings.params'a dondurulur (metering_billing.computeBillingPlan).
// Para tamsayi kurus (BIGINT); float YOK.

import { actorFromAuthUser } from './audit_service.js';
import { pool } from '../db.js';
import { inTransaction, audit } from './metering_service.js';
import { objectOf, parseDate, parseKind, parseMoney, tariffOutOfOrder } from './metering_common.js';

const mapTariff = (row) => ({
  id: Number(row.id),
  kind: row.kind,
  unit_price_minor: Number(row.unit_price_minor),
  valid_from: row.valid_from,
  valid_to: row.valid_to ?? null,
});

const TARIFF_SELECT = `
  SELECT id, kind, unit_price_minor::TEXT AS unit_price_minor, to_char(valid_from, 'YYYY-MM-DD') AS valid_from, to_char(valid_to, 'YYYY-MM-DD') AS valid_to
  FROM meter_tariffs
`;

/** `date` tarihinde (period_to) gecerli tarife ya da null. Faturalandirma onizleme ve kayit ayni sorguyu kullanir (onizleme = tahakkuk birebir). */
export async function tariffOn(client, siteCode, kind, date) {
  const found = await client.query(
    `${TARIFF_SELECT} WHERE site_code = $1 AND kind = $2 AND valid_from <= $3::DATE AND (valid_to IS NULL OR valid_to > $3::DATE) ORDER BY valid_from DESC LIMIT 1`,
    [siteCode, kind, date],
  );
  return found.rows[0] ? mapTariff(found.rows[0]) : null;
}

export async function listTariffs(siteCode) {
  const result = await pool.query(`${TARIFF_SELECT} WHERE site_code = $1 ORDER BY kind, valid_from DESC LIMIT 500`, [siteCode]);
  return { items: result.rows.map(mapTariff) };
}

/** `db`: bağlantı havuzu (testlerde sahte). */
export async function createTariff({ siteCode, actor, body, db = pool }) {
  const input = objectOf(body);
  const kind = parseKind(input.kind);
  const price = parseMoney(input.unit_price_minor, 'unit_price_minor', 'Birim fiyat');
  const from = parseDate(input.valid_from, 'Geçerlilik başlangıcı', 'valid_from');
  const actorInfo = actorFromAuthUser(actor);
  return inTransaction(siteCode, async (client) => {
    const last = await client.query(
      `SELECT id, to_char(valid_from, 'YYYY-MM-DD') AS valid_from FROM meter_tariffs WHERE site_code = $1 AND kind = $2 ORDER BY valid_from DESC LIMIT 1 FOR UPDATE`,
      [siteCode, kind],
    );
    if (last.rows[0]) {
      if (from <= last.rows[0].valid_from) throw tariffOutOfOrder();
      await client.query(`UPDATE meter_tariffs SET valid_to = $2::DATE WHERE id = $1 AND valid_to IS NULL`, [last.rows[0].id, from]);
    }
    const inserted = await client.query(
      `INSERT INTO meter_tariffs (site_code, kind, unit_price_minor, valid_from, created_by) VALUES ($1, $2, $3::BIGINT, $4::DATE, $5) RETURNING id`,
      [siteCode, kind, String(price), from, actorInfo.userCode],
    );
    const id = Number(inserted.rows[0].id);
    await audit(client, actor, 'metering.tariff.created', siteCode, id, { kind, valid_from: from });
    const row = await client.query(`${TARIFF_SELECT} WHERE id = $1`, [id]);
    return { tariff: mapTariff(row.rows[0]) };
  }, db);
}
