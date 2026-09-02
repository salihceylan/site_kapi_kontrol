import express from 'express';
import { pool } from '../db.js';
import { auditLog } from '../utils/helpers.js';
import { publishDoorPulse } from '../mqtt_bridge.js';

export const publicGuestRouter = express.Router();

async function recordDoorAccessLog({
  siteCode,
  doorId = null,
  doorName,
  userCode = null,
  userName,
  userRole = null,
  apartmentLabel = null,
  triggerType = 'cloud_app',
  openedAt = new Date(),
  ipAddress = null,
}) {
  try {
    await pool.query(
      `
        INSERT INTO door_access_logs (
          site_code,
          door_id,
          door_name,
          user_code,
          user_name,
          user_role,
          apartment_label,
          trigger_type,
          opened_at,
          ip_address
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
      `,
      [
        siteCode,
        doorId,
        doorName,
        userCode,
        userName,
        userRole,
        apartmentLabel,
        triggerType,
        openedAt,
        ipAddress,
      ],
    );
  } catch (err) {
    console.error('Error recording door access log:', err);
  }
}

// POST /public/guest-pass/:token/open
publicGuestRouter.post('/public/guest-pass/:token/open', async (req, res) => {
  const token = String(req.params.token || '').trim();
  if (!token) {
    return res.status(400).json({ error: 'Gecersiz gecis tokeni.' });
  }

  try {
    const result = await pool.query(
      `
        SELECT
          gp.*,
          d.door_name,
          d.assigned_device_id,
          dev.device_uid,
          s.name AS site_name
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
      doorName: pass.door_name || 'Site Kapısı',
      userCode: pass.created_by_user_code ? Number(pass.created_by_user_code) : null,
      userName: `${pass.title || 'Misafir'} (Geçiş Linki)`,
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
publicGuestRouter.get('/guest/:token', async (req, res) => {
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
            <h2>⚠️ Geçersiz Link</h2>
            <p>Bu geçiş bağlantısı bulunamadı veya süresi dolmuş.</p>
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
        <title>${pass.site_name} - ${pass.door_name} Geçiş</title>
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
          <div class="badge">AHBU Akıllı Geçiş</div>
          <h1>${pass.site_name}</h1>
          <div class="door-title">🚪 ${pass.door_name}</div>

          <button id="openBtn" class="trigger-btn" ${!isUsable ? 'disabled' : ''} onclick="triggerDoor()">
            <span class="icon">🔓</span>
            <span>KAPIYI AÇ</span>
          </button>

          <div id="statusText" class="status-msg ${!isUsable ? 'error' : ''}">
            ${!isUsable ? (isExpired ? 'Süresi Doldu' : 'Geçiş Kullanıldı') : 'Kapıyı açmak için dokunun'}
          </div>

          <div class="info-box">
            Geçiş Türü: <b>${pass.pass_type === 'single_use' ? 'Tek Kullanımlık' : 'Süreli Geçiş'}</b><br>
            Son Geçerlilik: <b>${new Date(pass.expires_at).toLocaleTimeString('tr-TR', { hour: '2-digit', minute: '2-digit', day: '2-digit', month: '2-digit' })}</b>
          </div>
        </div>

        <script>
          let busy = false;
          async function triggerDoor() {
            if (busy) return;
            busy = true;
            const btn = document.getElementById('openBtn');
            const status = document.getElementById('statusText');
            btn.disabled = true;
            status.className = 'status-msg';
            status.innerText = 'Kapı açılıyor, lütfen bekleyin...';

            try {
              const res = await fetch('/public/guest-pass/${token}/open', { method: 'POST' });
              const data = await res.json();
              if (res.ok && data.ok) {
                status.className = 'status-msg success';
                status.innerText = '✅ Kapı Açıldı! Hoş Geldiniz.';
                btn.innerHTML = '<span class="icon">✅</span><span>AÇILDI</span>';
              } else {
                status.className = 'status-msg error';
                status.innerText = '❌ ' + (data.error || 'Açılamadı.');
                btn.disabled = false;
                busy = false;
              }
            } catch (err) {
              status.className = 'status-msg error';
              status.innerText = '❌ Bağlantı hatası oluştu.';
              btn.disabled = false;
              busy = false;
            }
          }
        </script>
      </body>
      </html>
    `);
  } catch (error) {
    return res.status(500).send('Sunucu hatasi.');
  }
});
