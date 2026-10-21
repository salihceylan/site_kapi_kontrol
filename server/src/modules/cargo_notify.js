// Kargo geldi bildirimi: kargo kaydi (kind=cargo, daire dolu) olusunca dairenin guncel sakinlerine e-posta + (varsa) telefon (FCM) ve tarayici bildirimi.
// En iyi caba: hata kayit olusturmayi ASLA bozmaz. entry_id basina TEK bildirim (cargo_notify_log PK). Metinde kargo firmasi/ad YOK (yalniz "kargo geldi").
import { pool } from '../db.js';
import { sendCargoArrivedEmail } from '../mailer.js';
import { pushDeviceHooks } from './push_devices.js';
import { sendWebPushToUsers } from './web_push.js';

export const CARGO_TITLE = 'Kargo geldi';
export const cargoBody = (label) => `${label} için bir kargo geldi. Teslim almak için görevliye uğrayın.`;

/** Dairenin guncel sakin kullanicilari (uyelik + CRM iliskisi; kiraciliyken malik dahil degil). */
export const CARGO_RECIPIENTS_SQL = `
  SELECT DISTINCT u.user_code, u.email, u.full_name FROM users u WHERE u.is_active = TRUE AND u.user_code IN (
    SELECT am.user_code FROM apartment_memberships am WHERE am.apartment_id = $1 AND am.is_active = TRUE
    UNION
    SELECT sp.user_code FROM site_people sp
      JOIN apartment_residencies r ON r.person_id = sp.id AND r.is_current = TRUE AND r.apartment_id = $1
      WHERE sp.is_active = TRUE AND sp.user_code IS NOT NULL
        AND NOT (r.relation = 'owner' AND EXISTS (SELECT 1 FROM apartment_residencies t WHERE t.apartment_id = r.apartment_id AND t.relation = 'tenant' AND t.is_current = TRUE))
  )`;

export async function notifyCargoArrived({ siteCode, entryId, apartmentId }, db = pool) {
  try {
    const first = await db.query(`INSERT INTO cargo_notify_log (entry_id) VALUES ($1) ON CONFLICT DO NOTHING RETURNING entry_id`, [entryId]);
    if (!first.rows?.length) return { skipped: true };
    const info = (
      await db.query(
        `SELECT s.name AS site_name, a.unit_label, b.block_name FROM apartments a JOIN sites s ON s.site_code = a.site_code
         JOIN site_blocks b ON b.id = a.block_id WHERE a.id = $1 AND a.site_code = $2`,
        [apartmentId, siteCode],
      )
    ).rows?.[0];
    if (!info) return { skipped: true };
    const label = `${info.block_name ? `${info.block_name} ` : ''}Daire ${info.unit_label ?? ''}`.trim();
    const people = (await db.query(CARGO_RECIPIENTS_SQL, [apartmentId])).rows ?? [];
    const codes = people.map((p) => Number(p.user_code));
    let emails = 0;
    for (const person of people) {
      if (!person.email) continue;
      try {
        await sendCargoArrivedEmail({ to: person.email, name: person.full_name, siteName: info.site_name, apartmentLabel: label });
        emails += 1;
      } catch (_e) {
        // SMTP yok / hata: sessizce gec
      }
    }
    let pushes = 0;
    try {
      pushes += await sendWebPushToUsers(codes, { title: CARGO_TITLE, body: cargoBody(label), url: '/' }, db);
    } catch (_e) {
      // en iyi caba
    }
    try {
      const client = codes.length && pushDeviceHooks.available() ? pushDeviceHooks.client() : null;
      if (client) {
        const devices = (await db.query(`SELECT fcm_token FROM push_devices WHERE user_code = ANY($1::int[]) AND notifications_enabled`, [codes])).rows ?? [];
        for (const d of devices) {
          const r = await client.send({
            token: d.fcm_token,
            notification: { title: CARGO_TITLE, body: cargoBody(label) },
            data: { type: 'cargo', site_code: String(Number(siteCode)) },
            android: { priority: 'NORMAL', ttl: '86400s', notification: { channel_id: 'announcements' } },
          });
          if (r?.kind === 'ok') pushes += 1;
        }
      }
    } catch (_e) {
      // en iyi caba
    }
    await db.query(`UPDATE cargo_notify_log SET email_count = $2, push_count = $3 WHERE entry_id = $1`, [entryId, emails, pushes]);
    return { emails, pushes };
  } catch (error) {
    console.error('[cargo_notify] hata:', error?.code || error?.message);
    return { error: true };
  }
}
