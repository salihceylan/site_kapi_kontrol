import express from 'express';
import crypto from 'crypto';
import { pool } from '../db.js';
import { authRequired } from '../middlewares/auth_middleware.js';
import { doorCommandRateLimiter } from '../middlewares/rate_limiters.js';
import { publishDoorPulse } from '../mqtt_bridge.js';
import { getAccessibleDoorForUser, recordDoorAccessLog } from '../services/door_service.js';
import { assertDoorOpenAllowed } from '../services/door_access_policy.js';
import { auditLog } from '../utils/helpers.js';
import { parseId } from '../utils/ids.js';
import {
  CLAIM_GUEST_PASS_SQL,
  GUEST_PASS_STATE_RESPONSES,
  RELEASE_GUEST_PASS_SQL,
  generateCspNonce,
  getGuestPassState,
  guestPageHeaders,
  isWellFormedGuestToken,
  normalizeGuestPassInput,
  renderGuestPassPage,
  renderInvalidGuestPassPage,
} from '../utils/guest_pass_utils.js';

export const guestPassesRouter = express.Router();

const GUEST_POLICY_MESSAGES = {
  GUEST_DISABLED: 'Bu sitede misafir gecisleri yonetim tarafindan devre disi birakilmistir.',
};
const GUEST_POLICY_FALLBACK = 'Bu kapi icin misafir gecisi su anda kullanilamiyor.';

function publicBaseUrl() {
  return String(
    process.env.PUBLIC_APP_URL ||
    process.env.PUBLIC_BASE_URL ||
    'https://api.gudeteknoloji.com.tr',
  ).replace(/\/+$/, '');
}

// Hata ayrintisi istemciye gitmez; yalnizca sunucu logunda (errorId ile) tutulur.
function respondServerError(res, context, error, publicMessage) {
  const errorId = crypto.randomUUID().slice(0, 8);
  console.error(`[guest_passes] ${context} (errorId=${errorId})`, error);
  return res.status(500).json({ error: publicMessage, error_id: errorId });
}

// POST /app/guest-passes
guestPassesRouter.post('/app/guest-passes', authRequired, async (req, res) => {
  const input = normalizeGuestPassInput(req.body);
  if (!input.ok) {
    return res.status(400).json({ error: input.error });
  }
  const { doorId, title, passType, durationMinutes, maxUses } = input.value;

  try {
    const door = await getAccessibleDoorForUser({
      authUser: req.authUser,
      doorId,
    });
    if (!door) {
      return res.status(404).json({ error: 'Kapi bulunamadi veya yetkiniz yok.' });
    }

    // Politika kapaliysa kimse (super user dahil) gecis olusturamaz: acma yolunda (public open) misafir kanalinda
    // istisna YOKTUR; super user'a uretilen link hicbir zaman calismazdi (olu link).
    if (door.feature_guest_pass_enabled === false) {
      return res.status(403).json({
        error: 'Bu sitede misafir/kurye gecis kodu olusturma kapalidir.',
        code: 'GUEST_DISABLED',
      });
    }

    const token = crypto.randomBytes(24).toString('hex');
    const expiresAt = new Date(Date.now() + durationMinutes * 60 * 1000);

    const insertResult = await pool.query(
      `
        INSERT INTO guest_passes (
          site_code,
          door_id,
          created_by_user_code,
          title,
          token,
          pass_type,
          expires_at,
          max_uses,
          used_count,
          is_active
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, 0, TRUE)
        RETURNING *
      `,
      [
        Number(door.site_code),
        doorId,
        Number(req.authUser.id),
        title,
        token,
        passType,
        expiresAt.toISOString(),
        maxUses,
      ],
    );

    const row = insertResult.rows[0];
    const webUrl = `${publicBaseUrl()}/guest/${token}`;

    auditLog('guest_pass_created', {
      user_code: Number(req.authUser.id),
      door_id: doorId,
      pass_id: Number(row.id),
      pass_type: passType,
      expires_at: expiresAt.toISOString(),
    });

    return res.status(201).json({
      ok: true,
      guest_pass: {
        id: Number(row.id),
        title: row.title,
        token: row.token,
        pass_type: row.pass_type,
        expires_at: row.expires_at,
        max_uses: Number(row.max_uses),
        used_count: Number(row.used_count),
        is_active: row.is_active,
        web_url: webUrl,
        door_name: door.door_name,
        site_name: door.site_name,
      },
    });
  } catch (error) {
    return respondServerError(res, 'create', error, 'Gecis olusturulamadi.');
  }
});

// GET /app/guest-passes
guestPassesRouter.get('/app/guest-passes', authRequired, async (req, res) => {
  try {
    // Tek kullanimlik hak tuketimi is_active'i degistirmez; tukenmis linkler used_count ile elenir.
    const result = await pool.query(
      `
        SELECT
          gp.*,
          d.door_name,
          s.name AS site_name
        FROM guest_passes gp
        JOIN site_doors d ON d.id = gp.door_id
        JOIN sites s ON s.site_code = gp.site_code
        WHERE gp.created_by_user_code = $1
          AND gp.is_active = TRUE
          AND gp.used_count < gp.max_uses
          AND gp.expires_at > NOW()
        ORDER BY gp.created_at DESC
        LIMIT 50
      `,
      [Number(req.authUser.id)],
    );

    const baseUrl = publicBaseUrl();
    const passes = result.rows.map((row) => ({
      id: Number(row.id),
      title: row.title,
      token: row.token,
      pass_type: row.pass_type,
      expires_at: row.expires_at,
      max_uses: Number(row.max_uses),
      used_count: Number(row.used_count),
      is_active: row.is_active,
      web_url: `${baseUrl}/guest/${row.token}`,
      door_name: row.door_name,
      site_name: row.site_name,
    }));

    return res.status(200).json({ ok: true, passes });
  } catch (error) {
    return respondServerError(res, 'list', error, 'Gecisler alinamadi.');
  }
});

// DELETE /app/guest-passes/:id
guestPassesRouter.delete('/app/guest-passes/:id', authRequired, async (req, res) => {
  const passId = parseId(req.params.id);
  if (passId === null) {
    return res.status(400).json({ error: 'Gecersiz gecis id.' });
  }

  try {
    const result = await pool.query(
      `
        UPDATE guest_passes
        SET is_active = FALSE
        WHERE id = $1 AND created_by_user_code = $2
        RETURNING id
      `,
      [passId, Number(req.authUser.id)],
    );

    if (result.rowCount === 0) {
      return res.status(404).json({ error: 'Gecis bulunamadi veya yetkiniz yok.' });
    }

    return res.status(200).json({ ok: true, message: 'Gecis iptal edildi.' });
  } catch (error) {
    return respondServerError(res, 'revoke', error, 'Iptal edilemedi.');
  }
});

// POST /public/guest-pass/:token/open
guestPassesRouter.post('/public/guest-pass/:token/open', doorCommandRateLimiter, async (req, res) => {
  const token = String(req.params.token || '').trim();
  if (!isWellFormedGuestToken(token)) {
    return res.status(400).json({ error: 'Gecersiz gecis kodu.' });
  }

  try {
    const result = await pool.query(
      `
        SELECT
          gp.*,
          d.door_name,
          d.is_active AS door_is_active,
          d.access_scope,
          d.block_id,
          d.assigned_device_id,
          dev.device_uid,
          dev.hardware_type AS assigned_device_hardware_type,
          s.name AS site_name,
          s.mqtt_site_id,
          s.feature_guest_pass_enabled,
          s.feature_remote_open_enabled,
          s.feature_qr_enabled,
          s.feature_local_udp_enabled,
          s.qr_entry_active,
          s.require_geofence,
          s.geofence_latitude,
          s.geofence_longitude,
          s.geofence_radius_meters
        FROM guest_passes gp
        JOIN site_doors d ON d.id = gp.door_id
        JOIN sites s ON s.site_code = gp.site_code
        LEFT JOIN devices dev ON dev.id = d.assigned_device_id
        WHERE gp.token = $1
        LIMIT 1
      `,
      [token],
    );

    if (result.rowCount === 0) {
      return res.status(404).json({ error: 'Gecis baglantisi bulunamadi veya silinmis.' });
    }

    const pass = result.rows[0];

    if (pass.feature_guest_pass_enabled === false) {
      return res.status(403).json({
        error: 'Bu sitede misafir gecisleri yonetim tarafindan devre disi birakilmistir.',
        code: 'GUEST_DISABLED',
      });
    }

    const state = getGuestPassState(pass);
    if (state !== 'ok') {
      const stateResponse = GUEST_PASS_STATE_RESPONSES[state];
      return res.status(stateResponse.status).json({ error: stateResponse.error });
    }

    if (!pass.device_uid) {
      return res.status(409).json({ error: 'Bu kapiya cihaz atanmamis.' });
    }

    // Gecisi olusturan kullanici hala aktif ve kapiya yetkili olmali.
    const creatorResult = await pool.query(
      `
        SELECT
          id AS db_id,
          user_code AS id,
          user_code,
          full_name,
          email,
          login_name,
          role,
          is_active,
          email_verified,
          approval_status
        FROM users
        WHERE user_code = $1
        LIMIT 1
      `,
      [Number(pass.created_by_user_code)],
    );
    const creator = creatorResult.rows[0] || null;
    const creatorUsable = Boolean(
      creator &&
      creator.is_active &&
      creator.email_verified &&
      creator.approval_status !== 'pending' &&
      creator.approval_status !== 'rejected',
    );
    if (!creatorUsable) {
      return res.status(403).json({
        error: 'Bu gecisi olusturan kullanicinin yetkisi kalmamis.',
        code: 'GUEST_PASS_OWNER_INACTIVE',
      });
    }
    creator.userCode = creator.user_code;
    creator.userId = creator.db_id;

    const accessibleDoor = await getAccessibleDoorForUser({
      authUser: creator,
      doorId: Number(pass.door_id),
    });
    if (!accessibleDoor) {
      return res.status(403).json({
        error: 'Bu gecisi olusturan kullanicinin kapiya yetkisi kalmamis.',
        code: 'GUEST_PASS_OWNER_NO_ACCESS',
      });
    }

    // C2: kapi acma politikasi (kanal: misafir)
    try {
      assertDoorOpenAllowed({
        door: {
          id: Number(pass.door_id),
          site_code: Number(pass.site_code),
          door_name: pass.door_name,
          is_active: pass.door_is_active,
          access_scope: pass.access_scope,
          block_id: pass.block_id,
          assigned_device_id: pass.assigned_device_id,
          assigned_device_uid: pass.device_uid,
          assigned_device_hardware_type: pass.assigned_device_hardware_type,
          mqtt_site_id: pass.mqtt_site_id,
          feature_guest_pass_enabled: pass.feature_guest_pass_enabled,
          feature_remote_open_enabled: pass.feature_remote_open_enabled,
          feature_qr_enabled: pass.feature_qr_enabled,
          feature_local_udp_enabled: pass.feature_local_udp_enabled,
          qr_entry_active: pass.qr_entry_active,
          require_geofence: pass.require_geofence,
          geofence_latitude: pass.geofence_latitude,
          geofence_longitude: pass.geofence_longitude,
          geofence_radius_meters: pass.geofence_radius_meters,
          ...accessibleDoor,
        },
        channel: 'guest',
        authUser: creator,
      });
    } catch (policyError) {
      if (policyError?.statusCode === 403) {
        const code = typeof policyError.code === 'string' ? policyError.code : undefined;
        return res.status(403).json({
          error: GUEST_POLICY_MESSAGES[code] || GUEST_POLICY_FALLBACK,
          ...(code ? { code } : {}),
        });
      }
      throw policyError;
    }

    // Hakki ATOMIK tuket: iptal/sure/limit kosullari UPDATE icinde; kazanamayan istek kapiyi acmaz.
    const claim = await pool.query(CLAIM_GUEST_PASS_SQL, [Number(pass.id)]);
    if (claim.rowCount === 0) {
      const latest = await pool.query(
        `SELECT is_active, expires_at, used_count, max_uses FROM guest_passes WHERE id = $1 LIMIT 1`,
        [Number(pass.id)],
      );
      const latestState = latest.rowCount > 0 ? getGuestPassState(latest.rows[0]) : 'revoked';
      if (latestState === 'ok') {
        // Eszamanli baska bir istek hakki az once tuketip iade etmis olabilir.
        return res.status(409).json({ error: 'Gecis baglantisi su an baska bir istekle kullaniliyor. Lutfen tekrar deneyin.' });
      }
      const stateResponse = GUEST_PASS_STATE_RESPONSES[latestState];
      return res.status(stateResponse.status).json({ error: stateResponse.error });
    }
    const usedCount = Number(claim.rows[0].used_count);

    try {
      await publishDoorPulse({
        deviceUid: pass.device_uid,
        requestedBy: `guest_pass:${String(pass.title || '').slice(0, 48)}`,
        doorId: Number(pass.door_id),
        siteCode: Number(pass.site_code),
      });
    } catch (pulseError) {
      // Kapi acilamadi: tuketilen hakki geri ver.
      try {
        await pool.query(RELEASE_GUEST_PASS_SQL, [Number(pass.id)]);
      } catch (releaseError) {
        console.error('[guest_passes] hak iadesi basarisiz', { pass_id: Number(pass.id), message: releaseError?.message });
      }
      throw pulseError;
    }

    // Kapi acildi; asagidaki kayit islemleri basarisiz olsa da istemciye basari donulur.
    try {
      auditLog('guest_pass_opened', {
        pass_id: Number(pass.id),
        door_id: Number(pass.door_id),
        device_uid: pass.device_uid,
        used_count: usedCount,
        ip: req.ip,
      });

      let apartmentLabel = null;
      if (pass.created_by_user_code) {
        const aptRes = await pool.query(
          `
            SELECT b.block_name, a.unit_label
            FROM apartments a
            JOIN site_blocks b ON b.id = a.block_id
            WHERE a.resident_user_code = $1
            LIMIT 1
          `,
          [Number(pass.created_by_user_code)],
        );
        if (aptRes.rowCount > 0) {
          apartmentLabel = `${aptRes.rows[0].block_name} - ${aptRes.rows[0].unit_label}`;
        }
      }

      await recordDoorAccessLog({
        siteCode: Number(pass.site_code),
        doorId: Number(pass.door_id),
        doorName: pass.door_name || 'Site Kapisi',
        userCode: pass.created_by_user_code ? Number(pass.created_by_user_code) : null,
        userName: `${pass.title || 'Misafir'} (Gecis Linki)`,
        userRole: 'guest_pass',
        apartmentLabel,
        triggerType: 'guest_pass',
        openedAt: new Date(),
        ipAddress: req.ip,
      });
    } catch (bookkeepingError) {
      console.error('[guest_passes] acilis kaydi yazilamadi', {
        pass_id: Number(pass.id),
        message: bookkeepingError?.message,
      });
    }

    return res.status(200).json({
      ok: true,
      message: `${pass.door_name} aciliyor.`,
      door_name: pass.door_name,
      site_name: pass.site_name,
    });
  } catch (error) {
    if (error?.code === 'MQTT_BRIDGE_NOT_CONNECTED' || error?.code === 'DEVICE_OFFLINE') {
      return res.status(503).json({ error: 'Kapi cihazi su anda bagli degil.' });
    }
    return respondServerError(res, 'public_open', error, 'Kapi acilamadi.');
  }
});

// GET /guest/:token (Mobile Web Interface)
guestPassesRouter.get('/guest/:token', async (req, res) => {
  const token = String(req.params.token || '').trim();
  const nonce = generateCspNonce();
  const sendPage = (status, html) => {
    for (const [name, value] of Object.entries(guestPageHeaders(nonce))) {
      res.setHeader(name, value);
    }
    return res.status(status).send(html);
  };

  if (!isWellFormedGuestToken(token)) {
    return sendPage(404, renderInvalidGuestPassPage({ nonce }));
  }

  try {
    const result = await pool.query(
      `
        SELECT
          gp.*,
          d.door_name,
          s.name AS site_name
        FROM guest_passes gp
        JOIN site_doors d ON d.id = gp.door_id
        JOIN sites s ON s.site_code = gp.site_code
        WHERE gp.token = $1
        LIMIT 1
      `,
      [token],
    );

    if (result.rowCount === 0) {
      return sendPage(404, renderInvalidGuestPassPage({ nonce }));
    }

    return sendPage(200, renderGuestPassPage({ pass: result.rows[0], nonce }));
  } catch (error) {
    const errorId = crypto.randomUUID().slice(0, 8);
    console.error(`[guest_passes] page (errorId=${errorId})`, error);
    return sendPage(500, `Sunucu hatasi olustu. Referans: ${errorId}`);
  }
});
