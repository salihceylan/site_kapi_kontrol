import express from 'express';
import crypto from 'crypto';
import { pool } from '../db.js';
import { authRequired } from '../middlewares/auth_middleware.js';
import { doorCommandRateLimiter } from '../middlewares/rate_limiters.js';
import { publishDoorPulse } from '../mqtt_bridge.js';
import { getAccessibleDoorForUser, recordDoorAccessLog } from '../services/door_service.js';
import { auditLog } from '../utils/helpers.js';

export const guestPassesRouter = express.Router();

// POST /app/guest-passes
guestPassesRouter.post('/app/guest-passes', authRequired, async (req, res) => {
  const doorId = Number(req.body.door_id);
  const title = String(req.body.title || 'Misafir / Kurye').trim();
  const passType = String(req.body.pass_type || 'single_use').trim();
  const durationMinutes = Number(req.body.duration_minutes || (passType === 'single_use' ? 30 : 120));

  if (!Number.isInteger(doorId) || doorId <= 0) {
    return res.status(400).json({ error: 'Gecerli bir kapi secin.' });
  }

  try {
    const door = await getAccessibleDoorForUser({
      authUser: req.authUser,
      doorId,
    });
    if (!door) {
      return res.status(404).json({ error: 'Kapi bulunamadi veya yetkiniz yok.' });
    }

    if (door.feature_guest_pass_enabled === false && req.authUser.role !== 'super_user') {
      return res.status(403).json({ error: 'Bu sitede misafir/kurye gecis kodu olusturma kapalidir.' });
    }

    const token = crypto.randomBytes(24).toString('hex');
    const expiresAt = new Date(Date.now() + Math.max(5, Math.min(1440, durationMinutes)) * 60 * 1000);
    const maxUses = passType === 'single_use' ? 1 : Math.max(1, Number(req.body.max_uses || 10));

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
    const baseUrl = String(
      process.env.PUBLIC_APP_URL ||
      process.env.PUBLIC_BASE_URL ||
      'https://api.gudeteknoloji.com.tr',
    ).replace(/\/+$/, '');
    const webUrl = `${baseUrl}/guest/${token}`;

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
    return res.status(500).json({ error: `Gecis olusturulamadi: ${error.message}` });
  }
});

// GET /app/guest-passes
guestPassesRouter.get('/app/guest-passes', authRequired, async (req, res) => {
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
        WHERE gp.created_by_user_code = $1
          AND gp.is_active = TRUE
          AND gp.expires_at > NOW()
        ORDER BY gp.created_at DESC
        LIMIT 50
      `,
      [Number(req.authUser.id)],
    );

    const baseUrl = String(
      process.env.PUBLIC_APP_URL ||
      process.env.PUBLIC_BASE_URL ||
      'https://api.gudeteknoloji.com.tr',
    ).replace(/\/+$/, '');
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
    return res.status(500).json({ error: `Gecisler alinamadi: ${error.message}` });
  }
});

// DELETE /app/guest-passes/:id
guestPassesRouter.delete('/app/guest-passes/:id', authRequired, async (req, res) => {
  const passId = Number(req.params.id);
  if (!Number.isInteger(passId)) {
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
    return res.status(500).json({ error: `Iptal edilemedi: ${error.message}` });
  }
});

// POST /public/guest-pass/:token/open
guestPassesRouter.post('/public/guest-pass/:token/open', doorCommandRateLimiter, async (req, res) => {
  const token = String(req.params.token || '').trim();
  if (!token || token.length < 16) {
    return res.status(400).json({ error: 'Gecersiz gecis kodu.' });
  }

  try {
    const result = await pool.query(
      `
        SELECT
          gp.*,
          d.door_name,
          d.assigned_device_id,
          dev.device_uid,
          s.name AS site_name,
          s.feature_guest_pass_enabled
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
      return res.status(403).json({ error: 'Bu sitede misafir gecisleri yonetim tarafindan devre disi birakilmistir.' });
    }

    if (!pass.is_active) {
      return res.status(410).json({ error: 'Bu gecis linki iptal edilmis.' });
    }

    if (new Date(pass.expires_at) < new Date()) {
      return res.status(410).json({ error: 'Bu gecis linkinin suresi dolmus.' });
    }

    if (pass.used_count >= pass.max_uses) {
      return res.status(410).json({ error: 'Bu tek kullanimlik gecis linki daha once kullanilmis.' });
    }

    if (!pass.device_uid) {
      return res.status(409).json({ error: 'Bu kapiya cihaz atanmamis.' });
    }

    await publishDoorPulse({
      deviceUid: pass.device_uid,
      requestedBy: `guest_pass:${pass.title}`,
      doorId: Number(pass.door_id),
      siteCode: Number(pass.site_code),
    });

    const newUsedCount = Number(pass.used_count) + 1;
    const shouldDeactivate = pass.pass_type === 'single_use' || newUsedCount >= Number(pass.max_uses);

    await pool.query(
      `
        UPDATE guest_passes
        SET
          used_count = $1,
          is_active = CASE WHEN $2 = TRUE THEN FALSE ELSE is_active END
        WHERE id = $3
      `,
      [newUsedCount, shouldDeactivate, Number(pass.id)],
    );

    auditLog('guest_pass_opened', {
      pass_id: Number(pass.id),
      door_id: Number(pass.door_id),
      device_uid: pass.device_uid,
      used_count: newUsedCount,
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
    return res.status(500).json({ error: `Kapi acilamadi: ${error.message}` });
  }
});

// GET /guest/:token (Mobile Web Interface)
guestPassesRouter.get('/guest/:token', async (req, res) => {
  const token = String(req.params.token || '').trim();
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
      return res.status(404).send(`
        <!DOCTYPE html>
        <html lang="tr">
        <head>
          <meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">
          <title>Gecersiz Gecis Linki</title>
          <style>
            body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;background:#f1f5f9;display:flex;align-items:center;justify-content:center;height:100vh;margin:0;padding:16px;}
            .card{background:#fff;border-radius:24px;padding:32px;text-align:center;box-shadow:0 10px 30px rgba(0,0,0,0.08);max-width:400px;width:100%;}
            h2{color:#e11d48;margin:0 0 8px;}
            p{color:#64748b;font-size:15px;line-height:1.5;}
          </style>
        </head>
        <body>
          <div class="card">
            <h2>⚠️ Gecersiz Link</h2>
            <p>Bu gecis baglantisi bulunamadi veya suresi dolmus.</p>
          </div>
        </body>
        </html>
      `);
    }

    const pass = result.rows[0];
    const isExpired = new Date(pass.expires_at) < new Date();
    const isExhausted = pass.used_count >= pass.max_uses;
    const isUsable = pass.is_active && !isExpired && !isExhausted;

    res.setHeader('Content-Type', 'text/html; charset=utf-8');
    return res.status(200).send(`
      <!DOCTYPE html>
      <html lang="tr">
      <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
        <title>${pass.site_name} - ${pass.door_name} Gecis</title>
        <style>
          * { box-sizing: border-box; margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", Roboto, sans-serif; }
          body { background: linear-gradient(145deg, #0f172a, #1e293b); min-height: 100vh; display: flex; align-items: center; justify-content: center; padding: 20px; color: #fff; }
          .pass-container { background: rgba(255, 255, 255, 0.08); backdrop-filter: blur(20px); border: 1px solid rgba(255, 255, 255, 0.15); border-radius: 28px; width: 100%; max-width: 420px; padding: 36px 24px; text-align: center; box-shadow: 0 20px 50px rgba(0,0,0,0.3); }
          .badge { display: inline-block; padding: 6px 14px; border-radius: 999px; background: rgba(59, 130, 246, 0.2); border: 1px solid rgba(59, 130, 246, 0.4); color: #93c5fd; font-size: 13px; font-weight: 600; margin-bottom: 20px; text-transform: uppercase; letter-spacing: 0.5px; }
          h1 { font-size: 24px; font-weight: 800; margin-bottom: 6px; color: #f8fafc; }
          .door-title { font-size: 17px; color: #94a3b8; margin-bottom: 30px; }
          .trigger-btn { width: 180px; height: 180px; border-radius: 50%; border: none; background: linear-gradient(135deg, #2563eb, #1d4ed8); color: #fff; font-size: 18px; font-weight: 700; cursor: pointer; box-shadow: 0 10px 30px rgba(37, 99, 235, 0.4), inset 0 2px 4px rgba(255, 255, 255, 0.3); transition: all 0.2s ease; display: inline-flex; flex-direction: column; align-items: center; justify-content: center; gap: 8px; margin: 10px 0 24px; }
          .trigger-btn:active { transform: scale(0.95); }
          .trigger-btn:disabled { background: #475569; box-shadow: none; cursor: not-allowed; opacity: 0.7; }
          .icon { font-size: 38px; }
          .status-msg { min-height: 28px; font-size: 15px; font-weight: 600; margin-top: 10px; }
          .success { color: #4ade80; }
          .error { color: #f87171; }
          .info-box { margin-top: 24px; padding: 12px; background: rgba(0,0,0,0.2); border-radius: 14px; font-size: 12px; color: #94a3b8; }
        </style>
      </head>
      <body>
        <div class="pass-container">
          <div class="badge">${pass.pass_type === 'single_use' ? 'Tek Kullanimlik' : 'Sureli Gecis'}</div>
          <h1>${pass.site_name}</h1>
          <div class="door-title">${pass.door_name}</div>
          
          <button id="openBtn" class="trigger-btn" ${!isUsable ? 'disabled' : ''} onclick="openDoor()">
            <span class="icon">🚪</span>
            <span>KAPIYI AC</span>
          </button>
          
          <div id="statusMsg" class="status-msg">
            ${!pass.is_active ? '<span class="error">Bu baglanti iptal edilmis.</span>' : ''}
            ${isExpired ? '<span class="error">Baglantinin gecerlilik suresi dolmus.</span>' : ''}
            ${isExhausted ? '<span class="error">Kullanim limiti dolmus.</span>' : ''}
          </div>

          <div class="info-box">
            Bu link <b>${pass.title || 'Misafir'}</b> adina olusturulmustur.<br>
            Kalan Kullanim: <b>${Math.max(0, pass.max_uses - pass.used_count)}</b> / ${pass.max_uses}
          </div>
        </div>

        <script>
          let loading = false;
          async function openDoor() {
            if (loading) return;
            const btn = document.getElementById('openBtn');
            const msg = document.getElementById('statusMsg');
            loading = true;
            btn.disabled = true;
            btn.innerHTML = '<span class="icon">⏳</span><span>ACILIYOR...</span>';
            msg.innerHTML = '';

            try {
              const res = await fetch('/public/guest-pass/${token}/open', { method: 'POST' });
              const data = await res.json();
              if (res.ok) {
                btn.innerHTML = '<span class="icon">✅</span><span>ACILDI</span>';
                msg.innerHTML = '<span class="success">Kapi acildi, gecebilirsiniz!</span>';
                setTimeout(() => {
                  ${pass.pass_type === 'single_use' ? 'btn.disabled = true;' : 'btn.disabled = false; btn.innerHTML = \'<span class="icon">🚪</span><span>KAPIYI AC</span>\'; loading = false;'}
                }, 3000);
              } else {
                throw new Error(data.error || 'Islem basarisiz.');
              }
            } catch (err) {
              btn.innerHTML = '<span class="icon">❌</span><span>HATA</span>';
              msg.innerHTML = '<span class="error">' + err.message + '</span>';
              setTimeout(() => {
                btn.disabled = false;
                btn.innerHTML = '<span class="icon">🚪</span><span>TEKRAR DENE</span>';
                loading = false;
              }, 2500);
            }
          }
        </script>
      </body>
      </html>
    `);
  } catch (error) {
    return res.status(500).send('Sunucu hatasi olustu: ' + error.message);
  }
});
