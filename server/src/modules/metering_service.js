// Sayac kaydi, okuma kaydi ve dosyadan (CSV / Excel -> istemci satirlari) okuma aktarimi. Faturalandirma: metering_billing.js.
// Okuma yazimlari site basina `metering:<site>` danisma kilidi altinda, tek islemde yapilir. Denetim kaydi (audit) yalniz kimlik / sayi tasir (seri no, deger YOK).

import { pool } from '../db.js';
import { actorFromAuthUser, recordAudit } from './audit_service.js';
import { today } from './finance_common.js';
import { apartmentLabel, parsePositiveId } from './people_common.js';
import {
  IMPORT_CODE_MAX,
  IMPORT_MAX_ROWS,
  METERS_PER_SITE,
  apartmentNotFound,
  invalid,
  meterInactive,
  meterLimit,
  meterNotFound,
  milliOf,
  objectOf,
  parseDate,
  parseKind,
  parseReadingValue,
  parseSerial,
  readingExists,
  readingLocked,
  readingNotFound,
  readingOrder,
  serialTaken,
} from './metering_common.js';

const label = (row) => apartmentLabel(row.block_name, row.unit_label);

/** Site basina okuma/sayac yazma kilidi (islem icinde). */
export const meteringLockKey = (siteCode) => `metering:${Number(siteCode)}`;

/** `db`: baglanti havuzu (testlerde sahte). */
export async function inTransaction(siteCode, work, db = pool) {
  const client = await db.connect();
  try {
    await client.query('BEGIN');
    await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', [meteringLockKey(siteCode)]);
    const result = await work(client);
    await client.query('COMMIT');
    return result;
  } catch (error) {
    await client.query('ROLLBACK').catch(() => {});
    throw error;
  } finally {
    client.release();
  }
}

export const audit = (client, actor, action, siteCode, targetId, details) =>
  recordAudit(client, { actor, action, siteCode, targetType: 'metering', targetId: String(targetId), details }, { inTransaction: true });

/**
 * DATE sutunu -> 'YYYY-AA-GG'. pg, DATE'i YEREL gece yarisi Date'e cevirir; sunucu saat dilimi Europe/Istanbul oldugundan (db.js) toISOString() UTC'ye cevirip
 * tarihi bir gun GERI kaydirirdi (okuma 28.10 iken 27.10 gorunurdu, "bugun okundu" taninmazdi). Bu yuzden YEREL gun/ay/yil okunur.
 */
export const dateOnly = (value) => {
  if (value instanceof Date) {
    if (Number.isNaN(value.getTime())) return null;
    const two = (n) => String(n).padStart(2, '0');
    return `${value.getFullYear()}-${two(value.getMonth() + 1)}-${two(value.getDate())}`;
  }
  return value === null || value === undefined ? null : String(value).slice(0, 10);
};

export function mapMeter(row) {
  return {
    id: Number(row.id),
    kind: row.kind,
    serial_no: row.serial_no,
    is_active: row.is_active === true,
    apartment_id: Number(row.apartment_id),
    apartment_label: label(row),
    last_reading: row.last_value === null || row.last_value === undefined ? null : { value: row.last_value, date: dateOnly(row.last_date) },
    created_at: row.created_at instanceof Date ? row.created_at.toISOString() : row.created_at,
  };
}

export const METER_SELECT = `
  SELECT m.id, m.kind, m.serial_no, m.is_active, m.apartment_id, m.created_at, a.unit_label, b.block_name,
         lr.value::TEXT AS last_value, lr.reading_date AS last_date
  FROM meters m
  INNER JOIN apartments a ON a.id = m.apartment_id
  INNER JOIN site_blocks b ON b.id = a.block_id
  LEFT JOIN LATERAL (
    SELECT r.value, r.reading_date FROM meter_readings r WHERE r.meter_id = m.id ORDER BY r.reading_date DESC LIMIT 1
  ) lr ON TRUE
`;

export async function listApartments(siteCode) {
  const result = await pool.query(
    `
      SELECT a.id, a.unit_label, b.block_name, NULL::TEXT AS area
      FROM apartments a INNER JOIN site_blocks b ON b.id = a.block_id
      WHERE a.site_code = $1 AND a.is_active = TRUE
      ORDER BY b.sort_order, a.sort_order
    `,
    [siteCode],
  );
  // area_m2: m² sistemden kaldırıldı, HEP null (eski istemciler alanı okuyabilsin diye yalnız geriye uyum için döner). Isınma gideri alan payı artık
  // arsa payına ya da eşit paya göre dağıtılır (metering_calc.areaShareItems).
  return { items: result.rows.map((row) => ({ id: Number(row.id), label: label(row), area_m2: row.area })) };
}

export async function listMeters(siteCode, query = {}) {
  const kind = parseKind(query.kind, { required: false });
  const params = [siteCode];
  let where = 'WHERE m.site_code = $1';
  if (kind) {
    params.push(kind);
    where += ` AND m.kind = $${params.length}`;
  }
  if (query.active === '1') where += ' AND m.is_active = TRUE';
  const result = await pool.query(`${METER_SELECT} ${where} ORDER BY b.sort_order, a.sort_order, m.kind, m.id LIMIT 5000`, params);
  return { items: result.rows.map(mapMeter) };
}

export async function createMeter({ siteCode, actor, body }) {
  const input = objectOf(body);
  const kind = parseKind(input.kind);
  const serial = parseSerial(input.serial_no);
  const apartmentId = parsePositiveId(input.apartment_id);
  if (apartmentId === null) throw invalid('Daire seçilmelidir.', 'apartment_id');
  const actorInfo = actorFromAuthUser(actor);
  return inTransaction(siteCode, async (client) => {
    const apartment = await client.query(`SELECT id FROM apartments WHERE id = $1 AND site_code = $2 FOR KEY SHARE`, [apartmentId, siteCode]);
    if (!apartment.rows[0]) throw apartmentNotFound();
    const count = await client.query(`SELECT COUNT(*)::INT AS n FROM meters WHERE site_code = $1`, [siteCode]);
    if (count.rows[0].n >= METERS_PER_SITE) throw meterLimit();
    const dup = await client.query(`SELECT 1 FROM meters WHERE site_code = $1 AND kind = $2 AND lower(serial_no) = lower($3)`, [siteCode, kind, serial]);
    if (dup.rows[0]) throw serialTaken();
    const inserted = await client.query(
      `INSERT INTO meters (site_code, apartment_id, kind, serial_no, created_by) VALUES ($1, $2, $3, $4, $5) RETURNING id`,
      [siteCode, apartmentId, kind, serial, actorInfo.userCode],
    );
    const id = Number(inserted.rows[0].id);
    await audit(client, actor, 'metering.meter.created', siteCode, id, { kind, apartment_id: apartmentId });
    const row = await client.query(`${METER_SELECT} WHERE m.id = $1`, [id]);
    return { meter: mapMeter(row.rows[0]) };
  });
}

export async function updateMeter({ siteCode, rawId, actor, body }) {
  const id = parsePositiveId(rawId);
  if (id === null) throw meterNotFound();
  const input = objectOf(body);
  const serial = input.serial_no === undefined ? null : parseSerial(input.serial_no);
  if (input.is_active !== undefined && typeof input.is_active !== 'boolean') throw invalid('is_active true/false olmalıdır.', 'is_active');
  if (serial === null && input.is_active === undefined) throw invalid('Değiştirilecek alan yok.');
  return inTransaction(siteCode, async (client) => {
    const found = await client.query(`SELECT id, kind FROM meters WHERE id = $1 AND site_code = $2 FOR UPDATE`, [id, siteCode]);
    if (!found.rows[0]) throw meterNotFound();
    if (serial !== null) {
      const dup = await client.query(
        `SELECT 1 FROM meters WHERE site_code = $1 AND kind = $2 AND lower(serial_no) = lower($3) AND id <> $4`,
        [siteCode, found.rows[0].kind, serial, id],
      );
      if (dup.rows[0]) throw serialTaken();
    }
    await client.query(`UPDATE meters SET serial_no = COALESCE($2, serial_no), is_active = COALESCE($3, is_active) WHERE id = $1`, [id, serial, input.is_active ?? null]);
    await audit(client, actor, 'metering.meter.updated', siteCode, id, { fields: [serial !== null ? 'serial_no' : null, input.is_active !== undefined ? 'is_active' : null].filter(Boolean) });
    const row = await client.query(`${METER_SELECT} WHERE m.id = $1`, [id]);
    return { meter: mapMeter(row.rows[0]) };
  });
}

// --- Okumalar ----------------------------------------------------------------------------------------------------

export async function listReadings(siteCode, rawMeterId) {
  const id = parsePositiveId(rawMeterId);
  if (id === null) throw meterNotFound();
  const meter = await pool.query(`${METER_SELECT} WHERE m.id = $1 AND m.site_code = $2`, [id, siteCode]);
  if (!meter.rows[0]) throw meterNotFound();
  const readings = await pool.query(
    `SELECT id, reading_date, value::TEXT AS value, source FROM meter_readings WHERE meter_id = $1 ORDER BY reading_date DESC, id DESC LIMIT 200`,
    [id],
  );
  return {
    meter: mapMeter(meter.rows[0]),
    items: readings.rows.map((r) => ({ id: Number(r.id), date: dateOnly(r.reading_date), value: r.value, source: r.source })),
  };
}

/** Siralama kurali: onceki tarihli okumadan kucuk, sonraki tarihli okumadan buyuk olamaz. */
export async function checkOrder(client, meterId, date, milli) {
  const prev = await client.query(
    `SELECT value::TEXT AS value FROM meter_readings WHERE meter_id = $1 AND reading_date < $2::DATE ORDER BY reading_date DESC LIMIT 1`,
    [meterId, date],
  );
  if (prev.rows[0] && milliOf(prev.rows[0].value) > milli) {
    throw readingOrder(`Okuma, önceki okumadan (${prev.rows[0].value}) küçük olamaz.`);
  }
  const next = await client.query(
    `SELECT value::TEXT AS value FROM meter_readings WHERE meter_id = $1 AND reading_date > $2::DATE ORDER BY reading_date ASC LIMIT 1`,
    [meterId, date],
  );
  if (next.rows[0] && milliOf(next.rows[0].value) < milli) {
    throw readingOrder(`Okuma, sonraki tarihli okumadan (${next.rows[0].value}) büyük olamaz.`);
  }
}

/** Tek okuma ekler. Ayni sayac+tarih+ayni deger: sessizce ayni kayit (replayed). Farkli deger: 409 READING_EXISTS. */
async function insertReading(client, { siteCode, meterId, date, parsed, source, userCode }) {
  const existing = await client.query(`SELECT id, value::TEXT AS value FROM meter_readings WHERE meter_id = $1 AND reading_date = $2::DATE`, [meterId, date]);
  if (existing.rows[0]) {
    if (milliOf(existing.rows[0].value) === parsed.milli) return { id: Number(existing.rows[0].id), replayed: true };
    throw readingExists();
  }
  await checkOrder(client, meterId, date, parsed.milli);
  const inserted = await client.query(
    `INSERT INTO meter_readings (site_code, meter_id, reading_date, value, source, created_by) VALUES ($1, $2, $3::DATE, $4::NUMERIC, $5, $6) RETURNING id`,
    [siteCode, meterId, date, parsed.text, source, userCode],
  );
  return { id: Number(inserted.rows[0].id), replayed: false };
}

export async function addReading({ siteCode, rawMeterId, actor, body, now = new Date() }) {
  const meterId = parsePositiveId(rawMeterId);
  if (meterId === null) throw meterNotFound();
  const input = objectOf(body);
  const date = parseDate(input.date, 'Okuma tarihi', 'date');
  if (date > today(now)) throw invalid('Okuma tarihi gelecek bir tarih olamaz.', 'date');
  const parsed = parseReadingValue(input.value);
  if (!parsed) throw invalid('Okuma değeri en çok 3 ondalıklı, negatif olmayan bir sayı olmalıdır.', 'value');
  const actorInfo = actorFromAuthUser(actor);
  return inTransaction(siteCode, async (client) => {
    const meter = await client.query(`SELECT id, is_active FROM meters WHERE id = $1 AND site_code = $2 FOR KEY SHARE`, [meterId, siteCode]);
    if (!meter.rows[0]) throw meterNotFound();
    if (meter.rows[0].is_active !== true) throw meterInactive();
    const result = await insertReading(client, { siteCode, meterId, date, parsed, source: 'manual', userCode: actorInfo.userCode });
    if (!result.replayed) await audit(client, actor, 'metering.reading.added', siteCode, result.id, { meter_id: meterId, source: 'manual' });
    return { reading: { id: result.id, date, value: parsed.text, source: 'manual' }, replayed: result.replayed };
  });
}

export async function deleteReading({ siteCode, rawMeterId, rawReadingId, actor }) {
  const meterId = parsePositiveId(rawMeterId);
  const readingId = parsePositiveId(rawReadingId);
  if (meterId === null || readingId === null) throw readingNotFound();
  return inTransaction(siteCode, async (client) => {
    const found = await client.query(
      `
        SELECT r.id, r.reading_date, m.kind FROM meter_readings r INNER JOIN meters m ON m.id = r.meter_id
        WHERE r.id = $1 AND r.meter_id = $2 AND r.site_code = $3 FOR UPDATE OF r
      `,
      [readingId, meterId, siteCode],
    );
    if (!found.rows[0]) throw readingNotFound();
    const locked = await client.query(
      `SELECT 1 FROM meter_billings WHERE site_code = $1 AND kind = $2 AND period_to >= $3::DATE LIMIT 1`,
      [siteCode, found.rows[0].kind, dateOnly(found.rows[0].reading_date)],
    );
    if (locked.rows[0]) throw readingLocked();
    await client.query(`DELETE FROM meter_readings WHERE id = $1`, [readingId]);
    await audit(client, actor, 'metering.reading.deleted', siteCode, readingId, { meter_id: meterId });
    return { deleted: true };
  });
}

// --- Dosyadan aktarim ----------------------------------------------------------------------------------------------

const norm = (text) => String(text ?? '').trim().toLowerCase().replace(/\s+/g, ' ');

/**
 * Satirlar [{ code, value }]: kod = sayac seri no'su YA DA daire kodu (`Blok - No` ya da yalniz kapi no; dairenin bu turde TEK etkin sayaci olmali).
 * dry_run: hicbir sey yazmaz, satir sonuclarini dondurur. Gercek aktarimda hatasiz satirlar yazilir, hatali satirlar atlanir ve raporlanir.
 * Satir durumu: ok | same (ayni deger zaten kayitli) | error (reason).
 */
export async function importReadings({ siteCode, actor, body, now = new Date() }) {
  const input = objectOf(body);
  const kind = parseKind(input.kind);
  const date = parseDate(input.reading_date, 'Okuma tarihi', 'reading_date');
  if (date > today(now)) throw invalid('Okuma tarihi gelecek bir tarih olamaz.', 'reading_date');
  const rows = input.rows;
  if (!Array.isArray(rows) || rows.length === 0) throw invalid('Aktarılacak satır yok.', 'rows');
  if (rows.length > IMPORT_MAX_ROWS) throw invalid(`Bir seferde en çok ${IMPORT_MAX_ROWS} satır aktarılabilir.`, 'rows');
  const dryRun = input.dry_run === true;
  const actorInfo = actorFromAuthUser(actor);
  const work = async (client) => {
    const meters = await client.query(`${METER_SELECT} WHERE m.site_code = $1 AND m.kind = $2 AND m.is_active = TRUE`, [siteCode, kind]);
    const bySerial = new Map();
    const byLabel = new Map();
    for (const row of meters.rows) {
      bySerial.set(norm(row.serial_no), row);
      for (const key of new Set([norm(label(row)), norm(row.unit_label)])) {
        byLabel.set(key, [...(byLabel.get(key) ?? []), row]);
      }
    }
    const results = [];
    const seen = new Set();
    let written = 0;
    for (let index = 0; index < rows.length; index += 1) {
      const raw = objectOf(rows[index]);
      const code = typeof raw.code === 'string' ? raw.code.trim().slice(0, IMPORT_CODE_MAX) : '';
      const out = { n: Number.isSafeInteger(raw.n) ? raw.n : index + 1, code, status: 'error', reason: null, meter_id: null, value: null };
      results.push(out);
      const parsed = parseReadingValue(raw.value);
      if (code === '') {
        out.reason = 'CODE_MISSING';
        continue;
      }
      if (!parsed) {
        out.reason = 'VALUE_INVALID';
        continue;
      }
      let meter = bySerial.get(norm(code)) ?? null;
      if (!meter) {
        const matches = byLabel.get(norm(code)) ?? [];
        if (matches.length === 1) [meter] = matches;
        else if (matches.length > 1) {
          out.reason = 'CODE_AMBIGUOUS';
          continue;
        }
      }
      if (!meter) {
        out.reason = 'METER_NOT_FOUND';
        continue;
      }
      const meterId = Number(meter.id);
      out.meter_id = meterId;
      out.value = parsed.text;
      if (seen.has(meterId)) {
        out.reason = 'DUPLICATE_IN_FILE';
        continue;
      }
      seen.add(meterId);
      try {
        await client.query('SAVEPOINT imp');
        if (dryRun) {
          const existing = await client.query(`SELECT value::TEXT AS value FROM meter_readings WHERE meter_id = $1 AND reading_date = $2::DATE`, [meterId, date]);
          if (existing.rows[0]) {
            if (milliOf(existing.rows[0].value) !== parsed.milli) throw readingExists();
            out.status = 'same';
          } else {
            await checkOrder(client, meterId, date, parsed.milli);
            out.status = 'ok';
          }
        } else {
          const result = await insertReading(client, { siteCode, meterId, date, parsed, source: 'file', userCode: actorInfo.userCode });
          out.status = result.replayed ? 'same' : 'ok';
          if (!result.replayed) written += 1;
        }
        await client.query('RELEASE SAVEPOINT imp');
      } catch (error) {
        await client.query('ROLLBACK TO SAVEPOINT imp');
        if (!error?.code || typeof error.statusCode !== 'number') throw error;
        out.reason = error.code;
      }
    }
    if (!dryRun && written > 0) await audit(client, actor, 'metering.reading.imported', siteCode, siteCode, { kind, written, total: rows.length });
    const count = (status) => results.filter((r) => r.status === status).length;
    return { dry_run: dryRun, kind, reading_date: date, ok_count: count('ok'), same_count: count('same'), error_count: count('error'), rows: results };
  };
  return inTransaction(siteCode, work);
}
