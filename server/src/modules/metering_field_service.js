// Sayac saha okumasi (gorevli) servisi: blok/durum bilgili sayac listesi, sicrama uyarili okuma ekleme ve YENIDEN CEKIM.
// Sozlesme: docs/PLATFORM_SAYAC.md "Saha akisi ve sicrama uyarisi" (P1-6, P1-7, karar K12). Yonetici ekraninin okuma ekleme yolu
// (metering_service.addReading) DEGISMEZ; bu dosya yalniz saha uclari icindir.
//
// Okuma yazimlari site basina `metering:<site>` danisma kilidi altinda, tek islemde yapilir (metering_service.inTransaction).
// Denetim kaydi (audit) yalniz kimlik / sayi tasir; okunan DEGER YOK (sicrama onayinda yalniz K ve medyana orani yuzde olarak).

import { pool } from '../db.js';
import { actorFromAuthUser } from './audit_service.js';
import { PlatformError } from './errors.js';
import { today } from './finance_common.js';
import { parsePositiveId } from './people_common.js';
import { invalid, meterInactive, meterNotFound, milliOf, objectOf, parseDate, parseKind, parseReadingValue, readingExists } from './metering_common.js';
import { JUMP_HISTORY_READINGS, JUMP_HISTORY_SQL, evaluateJump, jumpBaseline, jumpBaselineView, readingJump, siteJumpFactor } from './metering_jump.js';
import { METER_SELECT, audit, checkOrder, dateOnly, inTransaction, mapMeter } from './metering_service.js';

/** Yeniden cekim yalniz bugunun ve dunun okumasi icin (cihaz saati / Istanbul tarihi arasindaki gun farki dahil). */
export const RETAKE_MAX_DAYS = 1;

export const retakeWindow = () => new PlatformError(409, 'RETAKE_WINDOW', 'Yeniden çekim yalnızca bugünkü ve dünkü okumalar için yapılabilir. Eski okumayı yönetici düzeltir.');
export const retakeLocked = () =>
  new PlatformError(409, 'READING_RETAKE_LOCKED', 'Bu okuma bir faturalandırma dönemine dahil olduğu için değiştirilemez. Yönetici ile görüşün.');

const addDays = (iso, days) => new Date(Date.parse(`${iso}T00:00:00Z`) + days * 86_400_000).toISOString().slice(0, 10);

/** true/false ya da yok (undefined); baska her sey 400. */
function parseFlag(raw, field) {
  if (raw === undefined || raw === null) return undefined;
  if (typeof raw !== 'boolean') throw invalid(`${field} true ya da false olmalıdır.`, field);
  return raw;
}

// Her etkin sayac icin `tarih`ten ONCEKI en yeni 4 okuma (sicrama tabani + onceki okuma). Dizin: uq_meter_readings_meter_date.
// Tarih metin olarak (to_char) alinir: pg DATE'i yerel gece yarisi Date'e cevirir, sunucu saat dilimi UTC degilse toISOString bir gun geri kayar.
const FIELD_HISTORY_SQL = `
  SELECT m.id AS meter_id, h.value::TEXT AS value, to_char(h.reading_date, 'YYYY-MM-DD') AS reading_date
  FROM meters m
  CROSS JOIN LATERAL (
    SELECT r.value, r.reading_date FROM meter_readings r
    WHERE r.meter_id = m.id AND r.reading_date < $2::DATE
    ORDER BY r.reading_date DESC LIMIT ${JUMP_HISTORY_READINGS}
  ) h
  WHERE m.site_code = $1 AND m.is_active = TRUE AND ($3::TEXT IS NULL OR m.kind = $3::TEXT)
  ORDER BY m.id, h.reading_date DESC
`;

/**
 * Saha sayac listesi (etkin sayaclar, daire sirasiyla). Her kayit `listMeters` ile ayni alanlar + (yeni, istege bagli):
 *  - block_name, unit_label: blok suzgeci icin;
 *  - previous_reading { value, date }: `date`ten ONCEKI son okuma (bugunku okuma varsa ondan onceki: yeniden cekimin tabani);
 *  - jump { median, limit, factor }: son 3 donem tuketim tabani (yeterli veri yoksa / medyan 0 ise null). Cihaz bununla okumadan once uyarabilir.
 * `date` (YYYY-AA-GG) yoksa Istanbul bugunu. Ust duzeyde `jump_factor` (site esigi) ve `date` doner.
 */
export async function listFieldMeters(siteCode, query = {}, { now = new Date(), db = pool } = {}) {
  const kind = parseKind(query.kind, { required: false });
  const date = query.date === undefined || query.date === null || query.date === '' ? today(now) : parseDate(query.date, 'Tarih', 'date');
  const factor = await siteJumpFactor(db, siteCode);
  const params = [siteCode];
  let where = 'WHERE m.site_code = $1 AND m.is_active = TRUE';
  if (kind) {
    params.push(kind);
    where += ` AND m.kind = $${params.length}`;
  }
  const meters = await db.query(`${METER_SELECT} ${where} ORDER BY b.sort_order, a.sort_order, m.kind, m.id LIMIT 5000`, params);
  const history = await db.query(FIELD_HISTORY_SQL, [siteCode, date, kind]);
  const byMeter = new Map();
  for (const row of history.rows) {
    const id = Number(row.meter_id);
    if (!byMeter.has(id)) byMeter.set(id, []);
    byMeter.get(id).push({ text: row.value, milli: milliOf(row.value), date: dateOnly(row.reading_date) });
  }
  const items = meters.rows.map((row) => {
    const readings = byMeter.get(Number(row.id)) ?? [];
    const baseline = jumpBaseline(
      readings.map((r) => r.milli),
      factor,
    );
    return {
      ...mapMeter(row),
      block_name: row.block_name,
      unit_label: row.unit_label,
      previous_reading: readings[0] ? { value: readings[0].text, date: readings[0].date } : null,
      jump: jumpBaselineView(baseline),
    };
  });
  return { items, jump_factor: factor, date };
}

/**
 * Saha okumasi ekler (ya da yeniden cekimle degistirir). Govde: { date, value, confirm_jump?, replace? }.
 *  - Ayni sayac + tarih + AYNI deger: sessizce ayni kayit (replayed; cevrimdisi kuyruk guvenle yeniden dener, hicbir denetim / uyari yok).
 *  - Ayni sayac + tarih + FARKLI deger: `replace: true` ise YENIDEN CEKIM (deger degisir; yalniz bugun / dun, faturalandirilmamis donem), degilse 409 READING_EXISTS.
 *  - `confirm_jump` boolean ise (YENI istemci) sicrama denetimi yapilir: false -> tuketim esigi asiyorsa 409 READING_JUMP (kaydedilmez);
 *    true -> kaydedilir ve onay izi yazilir (metering.reading.jump_confirmed). Alan YOKSA (eski istemci) denetim yapilmaz; okuma eskisi gibi kaydolur.
 * `db`: baglanti havuzu (testlerde sahte).
 */
export async function addFieldReading({ siteCode, rawMeterId, actor, body, now = new Date(), db = pool }) {
  const meterId = parsePositiveId(rawMeterId);
  if (meterId === null) throw meterNotFound();
  const input = objectOf(body);
  const date = parseDate(input.date, 'Okuma tarihi', 'date');
  const todayText = today(now);
  if (date > todayText) throw invalid('Okuma tarihi gelecek bir tarih olamaz.', 'date');
  const parsed = parseReadingValue(input.value);
  if (!parsed) throw invalid('Okuma değeri en çok 3 ondalıklı, negatif olmayan bir sayı olmalıdır.', 'value');
  const confirm = parseFlag(input.confirm_jump, 'confirm_jump');
  const replace = parseFlag(input.replace, 'replace') === true;
  const actorInfo = actorFromAuthUser(actor);
  const factor = confirm === undefined ? null : await siteJumpFactor(db, siteCode);
  return inTransaction(
    siteCode,
    async (client) => {
      const meter = await client.query(`SELECT id, kind, is_active FROM meters WHERE id = $1 AND site_code = $2 FOR KEY SHARE`, [meterId, siteCode]);
      if (!meter.rows[0]) throw meterNotFound();
      if (meter.rows[0].is_active !== true) throw meterInactive();
      const found = await client.query(`SELECT id, value::TEXT AS value FROM meter_readings WHERE meter_id = $1 AND reading_date = $2::DATE FOR UPDATE`, [meterId, date]);
      const existing = found.rows[0] ?? null;
      if (existing && milliOf(existing.value) === parsed.milli) {
        return { reading: { id: Number(existing.id), date, value: parsed.text, source: 'manual' }, replayed: true, retaken: false, jump_confirmed: false };
      }
      if (existing) {
        if (!replace) throw readingExists();
        if (date < addDays(todayText, -RETAKE_MAX_DAYS)) throw retakeWindow();
        const locked = await client.query(`SELECT 1 FROM meter_billings WHERE site_code = $1 AND kind = $2 AND period_to >= $3::DATE LIMIT 1`, [
          siteCode,
          meter.rows[0].kind,
          date,
        ]);
        if (locked.rows[0]) throw retakeLocked();
      }
      await checkOrder(client, meterId, date, parsed.milli);
      let jump = null;
      if (confirm !== undefined) {
        const history = await client.query(JUMP_HISTORY_SQL, [meterId, date]);
        jump = evaluateJump(
          jumpBaseline(
            history.rows.map((r) => milliOf(r.value)),
            factor,
          ),
          parsed.milli,
        );
        if (jump && confirm !== true) throw readingJump(jump);
      }
      let id;
      if (existing) {
        id = Number(existing.id);
        await client.query(`UPDATE meter_readings SET value = $2::NUMERIC, source = 'manual', created_by = $3 WHERE id = $1`, [id, parsed.text, actorInfo.userCode]);
        await audit(client, actor, 'metering.reading.retaken', siteCode, id, { meter_id: meterId, source: 'field' });
      } else {
        const inserted = await client.query(
          `INSERT INTO meter_readings (site_code, meter_id, reading_date, value, source, created_by) VALUES ($1, $2, $3::DATE, $4::NUMERIC, 'manual', $5) RETURNING id`,
          [siteCode, meterId, date, parsed.text, actorInfo.userCode],
        );
        id = Number(inserted.rows[0].id);
        await audit(client, actor, 'metering.reading.added', siteCode, id, { meter_id: meterId, source: 'manual' });
      }
      const confirmed = jump !== null && confirm === true;
      if (confirmed) await audit(client, actor, 'metering.reading.jump_confirmed', siteCode, id, { meter_id: meterId, factor: jump.factor, ratio_pct: jump.ratioPct });
      return { reading: { id, date, value: parsed.text, source: 'manual' }, replayed: false, retaken: existing !== null, jump_confirmed: confirmed };
    },
    db,
  );
}
