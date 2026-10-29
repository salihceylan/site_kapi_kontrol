// Site basina SMS + WhatsApp baglantisi (117) servisi. Sozlesme: docs/MESAJ_SURUCU_REHBERI.md.
// Sirlar sifreli saklanir; yanitta yalniz maskeli ipucu doner. Telefon numarasi / mesaj metni burada islenmez ya da yazilmaz.

import { pool } from '../db.js';
import { recordAudit } from './audit_service.js';
import { PlatformError } from './errors.js';
import {
  CHANNEL_SMS,
  CHANNEL_WHATSAPP,
  SMS_DRIVERS,
  WHATSAPP_DRIVER,
  maskText,
  messagingKey,
  openSecrets,
  sealSecrets,
} from './messaging_common.js';
import { getSmsProvider, smsHooks } from './sms_provider.js';

const textOf = (value) => String(value ?? '').trim();

async function loadRow(db, siteCode, channel) {
  const result = await db.query(
    `SELECT provider, config, secret_enc, last_test_at, last_test_ok, last_test_code, updated_at
       FROM site_messaging_connections WHERE site_code = $1 AND channel = $2 LIMIT 1`,
    [siteCode, channel],
  );
  return result.rows?.[0] ?? null;
}

function viewOf(row) {
  if (!row) return null;
  return {
    provider: row.provider,
    config: row.config ?? {},
    last_test: row.last_test_at ? { at: row.last_test_at, ok: row.last_test_ok, code: row.last_test_code } : null,
    updated_at: row.updated_at,
  };
}

export async function getMessagingStatus(siteCode, { canWrite = false, db = pool, env = process.env } = {}) {
  let keyConfigured = true;
  try {
    messagingKey(env);
  } catch {
    keyConfigured = false;
  }
  const [sms, whatsapp] = await Promise.all([loadRow(db, siteCode, CHANNEL_SMS), loadRow(db, siteCode, CHANNEL_WHATSAPP)]);
  return {
    key_configured: keyConfigured,
    can_write: canWrite,
    sms: {
      drivers: Object.values(SMS_DRIVERS).map((d) => ({ id: d.id, label: d.label, secret_fields: d.secretFields, config_fields: d.configFields })),
      connection: viewOf(sms),
      global_fallback: getSmsProvider(env) !== null,
    },
    whatsapp: {
      driver: { id: WHATSAPP_DRIVER.id, label: WHATSAPP_DRIVER.label, active: WHATSAPP_DRIVER.active, note: WHATSAPP_DRIVER.note },
      connection: viewOf(whatsapp),
    },
  };
}

async function upsert(db, { siteCode, channel, provider, config, sealed, actor }) {
  const result = await db.query(
    `INSERT INTO site_messaging_connections (site_code, channel, provider, config, secret_enc, updated_by)
     VALUES ($1, $2, $3, $4::jsonb, $5, $6)
     ON CONFLICT (site_code, channel) DO UPDATE SET provider = EXCLUDED.provider, config = EXCLUDED.config, secret_enc = EXCLUDED.secret_enc,
       last_test_at = NULL, last_test_ok = NULL, last_test_code = NULL, updated_by = EXCLUDED.updated_by, updated_at = NOW()
     RETURNING provider, config, secret_enc, last_test_at, last_test_ok, last_test_code, updated_at`,
    [siteCode, channel, provider, JSON.stringify(config), sealed, actor?.userCode ?? null],
  );
  return result.rows[0];
}

export async function saveSmsConnection(siteCode, body, actor, { db = pool, env = process.env } = {}) {
  messagingKey(env);
  const driver = SMS_DRIVERS[textOf(body?.provider).toLowerCase()];
  if (!driver) throw new PlatformError(400, 'INVALID_PROVIDER', 'Bilinmeyen SMS sağlayıcısı.');
  const existing = await loadRow(db, siteCode, CHANNEL_SMS);
  // Bos birakilan sir alani, AYNI saglayicinin kayitli degerini korur (sifreyi her seferinde yeniden yazdirmamak icin).
  const kept = existing && existing.provider === driver.id ? openSecrets(existing.secret_enc, env) : {};
  const input = { ...body };
  for (const field of driver.secretFields) input[field] = textOf(body?.[field]) || kept[field] || '';
  const { config, secrets } = driver.validate(input);
  const row = await upsert(db, {
    siteCode, channel: CHANNEL_SMS, provider: driver.id,
    config: { ...config, secret_hint: maskText(secrets[driver.secretFields[0]]) },
    sealed: sealSecrets(secrets, env), actor,
  });
  await recordAudit(db, { actor, action: 'messaging.sms.save', siteCode, targetType: 'messaging', targetId: CHANNEL_SMS, details: { provider: driver.id } });
  return { connection: viewOf(row) };
}

export async function testSmsConnection(siteCode, actor, { db = pool, env = process.env, fetchImpl = fetch } = {}) {
  const row = await loadRow(db, siteCode, CHANNEL_SMS);
  if (!row) throw new PlatformError(404, 'NOT_CONNECTED', 'Bu sitede SMS bağlantısı tanımlı değil.');
  const driver = SMS_DRIVERS[row.provider];
  const secrets = openSecrets(row.secret_enc, env);
  let result;
  try {
    // Yalniz kimlik / bakiye sorgusu; GERCEK SMS GONDERILMEZ.
    result = await driver.check({ config: row.config, secrets }, fetchImpl);
  } catch {
    result = { ok: false, code: 'NETWORK', message: 'Sağlayıcıya ulaşılamadı. Biraz sonra tekrar deneyin.' };
  }
  await db.query(
    `UPDATE site_messaging_connections SET last_test_at = NOW(), last_test_ok = $3, last_test_code = $4 WHERE site_code = $1 AND channel = $2`,
    [siteCode, CHANNEL_SMS, result.ok === true, result.code],
  );
  await recordAudit(db, { actor, action: 'messaging.sms.test', siteCode, targetType: 'messaging', targetId: CHANNEL_SMS, details: { provider: driver.id, ok: result.ok === true, code: result.code } });
  return result;
}

export async function saveWhatsappConnection(siteCode, body, actor, { db = pool, env = process.env } = {}) {
  messagingKey(env);
  const existing = await loadRow(db, siteCode, CHANNEL_WHATSAPP);
  const kept = existing ? openSecrets(existing.secret_enc, env) : {};
  const token = textOf(body?.access_token) || kept.access_token || '';
  WHATSAPP_DRIVER.validateToken(token);
  const { config } = WHATSAPP_DRIVER.validate(body ?? {});
  const row = await upsert(db, {
    siteCode, channel: CHANNEL_WHATSAPP, provider: WHATSAPP_DRIVER.id, config,
    sealed: sealSecrets({ access_token: token }, env), actor,
  });
  await recordAudit(db, { actor, action: 'messaging.whatsapp.save', siteCode, targetType: 'messaging', targetId: CHANNEL_WHATSAPP, details: { provider: WHATSAPP_DRIVER.id } });
  return { connection: viewOf(row) };
}

/** Dogrulama modu: kayitli alanlar gecerli mi? GERCEK baglanti / gonderim YOK; sonuc dürüstçe "bağlı değil". */
export async function testWhatsappConnection(siteCode, actor, { db = pool } = {}) {
  const row = await loadRow(db, siteCode, CHANNEL_WHATSAPP);
  if (!row) throw new PlatformError(404, 'NOT_CONNECTED', 'Bu sitede WhatsApp bağlantısı tanımlı değil.');
  let validated = true;
  try {
    WHATSAPP_DRIVER.validate(row.config ?? {});
  } catch {
    validated = false;
  }
  const code = 'VALIDATION_ONLY';
  await db.query(
    `UPDATE site_messaging_connections SET last_test_at = NOW(), last_test_ok = NULL, last_test_code = $3 WHERE site_code = $1 AND channel = $2`,
    [siteCode, CHANNEL_WHATSAPP, code],
  );
  await recordAudit(db, { actor, action: 'messaging.whatsapp.test', siteCode, targetType: 'messaging', targetId: CHANNEL_WHATSAPP, details: { validated } });
  return { validated, connected: false, code, message: WHATSAPP_DRIVER.note };
}

export async function removeConnection(siteCode, channel, { confirm = false } = {}, actor, { db = pool } = {}) {
  if (confirm !== true) throw new PlatformError(400, 'CONFIRM_REQUIRED', 'Bağlantıyı kaldırmak için onay gerekli.');
  const result = await db.query(`DELETE FROM site_messaging_connections WHERE site_code = $1 AND channel = $2`, [siteCode, channel]);
  if (!result.rowCount) throw new PlatformError(404, 'NOT_CONNECTED', 'Kaldırılacak bağlantı yok.');
  await recordAudit(db, { actor, action: `messaging.${channel}.remove`, siteCode, targetType: 'messaging', targetId: channel, details: {} });
  return { removed: true };
}

/**
 * SMS gonderen kodun kullanacagi saglayici: ONCE site ayari, yoksa global .env (geri uyumluluk; mevcut davranis bozulmaz).
 * Site ayari VAR ama cozulemiyorsa (anahtar eksik / bozuk) null doner: baska hesaptan (global) ucretlendirmemek icin KAPALI basarisiz olur.
 */
export async function getSiteSmsProvider(siteCode, { db = pool, env = process.env, fetchImpl = fetch, fallback = () => smsHooks.provider() } = {}) {
  let row = null;
  try {
    row = siteCode ? await loadRow(db, siteCode, CHANNEL_SMS) : null;
  } catch (error) {
    console.error('[messaging] site SMS ayari okunamadi, global kullanilacak:', error?.code || error?.message);
  }
  if (!row) return fallback();
  try {
    const driver = SMS_DRIVERS[row.provider];
    return driver.createAdapter({ config: row.config, secrets: openSecrets(row.secret_enc, env) }, fetchImpl);
  } catch {
    console.error(`[messaging] site ${siteCode} SMS ayari cozulemedi; gonderim kapali.`);
    return null;
  }
}
