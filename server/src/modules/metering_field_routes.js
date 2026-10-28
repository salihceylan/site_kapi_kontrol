// Sayac okuma saha uclari (gorevli fotografla okur). Sozlesme: docs/PLATFORM_SAYAC.md "Fotografla okuma".
//
//   GET  /sites/:siteCode/meter-field/meters?kind=             etkin sayaclar (daire sirasiyla) { items }
//   POST /sites/:siteCode/meter-field/readings                 { meter_id, date, value, photo_b64?, photo_mime? } -> { reading, replayed, photo }
//   GET  /sites/:siteCode/meter-field/photos/:id/content       sunucuda tutulan fotograf (yonetici / gorevli)
//
// Yetki: yonetici / super + o sitenin etkin STAFF'i; kurul uyesi, sakin ve ilgisiz 403 FORBIDDEN_ROLE; `metering` modulu kapaliysa 403 MODULE_DISABLED.
// Fotograf: Drive modulu acik ve bagliysa Drive'a (dosya adi OKM-<okuma no>_AB_D13_201026; Drive kaydi okumaya baglanir), degilse (ya da Drive bekleme alani doluysa)
// sunucudaki meter_reading_photos tablosuna. Tekrar gonderim (replayed) fotograf eklemez. Sunucu hicbir fotografi kendiliginden silmez; telefondaki kopya da silinmez (K6).

import crypto from 'node:crypto';
import express from 'express';
import { pool } from '../db.js';
import { authRequired } from '../middlewares/auth_middleware.js';
import { actorFromAuthUser } from './audit_service.js';
import { DRIVE_MIME_EXTENSIONS, cleanLabel, fileBaseName, folderNameFor, mimeMatchesContent, parseIsoDate } from './drive_common.js';
import { driveService } from './drive_service.js';
import { isModuleEnabled } from './module_service.js';
import { METERING_MODULE, moduleDisabled } from './metering_common.js';
import { meteringReadLimiter, meteringWriteLimiter } from './metering_routes.js';
import { addReading, listMeters } from './metering_service.js';
import { FORBIDDEN_ROLE_BODY, SITE_NOT_FOUND_BODY, getPeopleAccessKind } from './people_access.js';
import { respondError } from './route_helpers.js';
import { parseId } from '../utils/ids.js';

export const meteringFieldRouter = express.Router();

export const PHOTO_MAX_BYTES = 600 * 1024;
export const PHOTOS_PER_SITE = 5000;
const PHOTO_MIMES = new Set(['image/jpeg', 'image/png', 'image/webp']);
const DRIVE_KIND_OF = Object.freeze({ water: 'su', hot_water: 'su', electricity: 'elektrik', heat: 'isi' });

async function isActiveStaff(userCode, siteCode) {
  const found = await pool.query(
    `SELECT 1 FROM site_memberships WHERE site_code = $1 AND user_code = $2 AND role = 'STAFF' AND is_active = TRUE LIMIT 1`,
    [siteCode, userCode],
  );
  return Boolean(found.rows?.[0]);
}

/** Yetki + site + modul. Hata yanitini yazar ve null doner. */
export async function resolveFieldAccess(req, res) {
  const siteCode = parseId(req.params.siteCode);
  if (siteCode === null) {
    res.status(400).json({ error: 'Geçersiz site kodu.', code: 'INVALID_SITE_CODE' });
    return null;
  }
  const kind = await getPeopleAccessKind(req.authUser, siteCode);
  const userCode = Number(req.authUser?.userCode ?? req.authUser?.user_code ?? req.authUser?.id);
  const allowed = kind === 'super' || kind === 'manager' || (Number.isSafeInteger(userCode) && userCode > 0 && (await isActiveStaff(userCode, siteCode)));
  if (!allowed) {
    res.status(403).json(FORBIDDEN_ROLE_BODY);
    return null;
  }
  const exists = await pool.query(`SELECT 1 FROM sites WHERE site_code = $1 LIMIT 1`, [siteCode]);
  if (!exists.rows?.[0]) {
    res.status(404).json(SITE_NOT_FOUND_BODY);
    return null;
  }
  if (!(await isModuleEnabled(siteCode, METERING_MODULE))) {
    const error = moduleDisabled();
    res.status(error.statusCode).json({ error: error.message, code: error.code, ...(error.extra ?? {}) });
    return null;
  }
  return { siteCode, userCode: Number.isSafeInteger(userCode) ? userCode : null };
}

/** "A Blok" -> "A"; "Blok B" -> "B". */
export const blockLetter = (name) => cleanLabel(String(name ?? '').replace(/^\s*blok\s+/i, '').replace(/\s+blok\s*$/i, ''));
/** "Daire 13" -> "13". */
export const unitNumber = (label) => cleanLabel(String(label ?? '').replace(/^\s*daire\s*/i, ''));

/** Fotografi dogrular; gecersizse null (okuma yine kaydedilir). */
export function decodePhoto(b64, mime) {
  const type = String(mime ?? '').toLowerCase();
  if (!b64 || !PHOTO_MIMES.has(type) || typeof b64 !== 'string') return null;
  const data = Buffer.from(b64, 'base64');
  if (data.length === 0 || data.length > PHOTO_MAX_BYTES || !mimeMatchesContent(type, data)) return null;
  return { data, mime: type };
}

async function storePhoto({ siteCode, userCode, authUser, meterId, readingId, date, photo }) {
  const meter = await pool.query(
    `SELECT m.kind, a.unit_label, b.block_name FROM meters m INNER JOIN apartments a ON a.id = m.apartment_id INNER JOIN site_blocks b ON b.id = a.block_id WHERE m.id = $1 AND m.site_code = $2`,
    [meterId, siteCode],
  );
  const row = meter.rows[0];
  if (!row) return { storage: 'none' };
  const driveKind = DRIVE_KIND_OF[row.kind];
  const block = blockLetter(row.block_name);
  const apartment = unitNumber(row.unit_label);
  // P1-11: dosya adi okuma kimligini tasir (OKM-<okuma no>_AB_D13_201026) ve Drive kaydi bu okumaya baglanir.
  const source = { type: 'meter_reading', id: readingId };
  let driveReason = null;
  if (await isModuleEnabled(siteCode, 'drive_storage')) {
    try {
      const out = await driveService.upload({
        siteCode,
        actor: actorFromAuthUser(authUser),
        query: { kind: driveKind, date, block, apartment, mime: photo.mime },
        data: photo.data,
        source,
      });
      return { storage: 'drive', name: out.file.name, folder: out.file.folder, status: out.file.status };
    } catch (error) {
      // Drive bagli degil, bekleme alani dolu (K6: yeni yukleme reddedilir) ya da hata verdi: okuma bozulmaz, fotograf sunucuda tutulur (kaybolmaz).
      driveReason = typeof error?.code === 'string' ? error.code : 'DRIVE_FAILED';
    }
  }
  const count = await pool.query(`SELECT COUNT(*)::INT AS n FROM meter_reading_photos WHERE site_code = $1`, [siteCode]);
  if (count.rows[0].n >= PHOTOS_PER_SITE) return { storage: 'none', reason: 'PHOTO_LIMIT' };
  const parsed = parseIsoDate(date);
  const name = `${fileBaseName({ kind: driveKind, block, apartment, date: parsed, source })}.${DRIVE_MIME_EXTENSIONS[photo.mime]}`;
  await pool.query(
    `INSERT INTO meter_reading_photos (site_code, meter_id, reading_id, name, mime_type, size_bytes, sha256, data, created_by)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)`,
    [siteCode, meterId, readingId, name, photo.mime, photo.data.length, crypto.createHash('sha256').update(photo.data).digest('hex'), photo.data, userCode],
  );
  return { storage: 'server', name, folder: folderNameFor(driveKind, parsed), ...(driveReason ? { drive_reason: driveReason } : {}) };
}

function guarded({ context, fallback }, run) {
  return async (req, res) => {
    try {
      res.setHeader('Cache-Control', 'no-store');
      const access = await resolveFieldAccess(req, res);
      if (!access) return undefined;
      const out = await run({ req, res, access });
      if (out === undefined) return undefined;
      return res.status(out.status ?? 200).json(out.body);
    } catch (error) {
      return respondError(res, context, error, fallback);
    }
  };
}

const BASE = '/sites/:siteCode/meter-field';

meteringFieldRouter.get(
  `${BASE}/meters`,
  authRequired,
  meteringReadLimiter,
  guarded({ context: 'meter_field_meters', fallback: 'Sayaçlar yüklenemedi.' }, async ({ req, access }) => ({
    body: await listMeters(access.siteCode, { kind: req.query.kind, active: '1' }),
  })),
);

meteringFieldRouter.post(
  `${BASE}/readings`,
  authRequired,
  meteringWriteLimiter,
  guarded({ context: 'meter_field_reading', fallback: 'Okuma kaydedilemedi.' }, async ({ req, access }) => {
    const body = req.body && typeof req.body === 'object' ? req.body : {};
    const result = await addReading({
      siteCode: access.siteCode,
      rawMeterId: body.meter_id,
      actor: req.authUser,
      body: { date: body.date, value: body.value },
    });
    let photo = { storage: 'none' };
    if (!result.replayed && body.photo_b64) {
      const decoded = decodePhoto(body.photo_b64, body.photo_mime);
      if (decoded) {
        photo = await storePhoto({
          siteCode: access.siteCode,
          userCode: access.userCode,
          authUser: req.authUser,
          meterId: Number(body.meter_id),
          readingId: result.reading.id,
          date: result.reading.date,
          photo: decoded,
        }).catch(() => ({ storage: 'none', reason: 'PHOTO_FAILED' }));
      } else {
        photo = { storage: 'none', reason: 'PHOTO_INVALID' };
      }
    }
    return { status: result.replayed ? 200 : 201, body: { ...result, photo } };
  }),
);

meteringFieldRouter.get(
  `${BASE}/photos/:id/content`,
  authRequired,
  meteringReadLimiter,
  guarded({ context: 'meter_field_photo', fallback: 'Fotoğraf açılamadı.' }, async ({ req, res, access }) => {
    const id = parseId(req.params.id);
    const found = id === null ? null : await pool.query(`SELECT name, mime_type, data FROM meter_reading_photos WHERE id = $1 AND site_code = $2`, [id, access.siteCode]);
    const row = found?.rows?.[0];
    if (!row) return { status: 404, body: { error: 'Fotoğraf bulunamadı.', code: 'PHOTO_NOT_FOUND' } };
    res.setHeader('Content-Type', row.mime_type);
    res.setHeader('X-Content-Type-Options', 'nosniff');
    res.setHeader('Content-Disposition', `inline; filename="${String(row.name).replace(/[^A-Za-z0-9._-]/g, '_')}"`);
    res.status(200).end(row.data);
    return undefined;
  }),
);
