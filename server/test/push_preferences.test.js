// Telefon bildirimi (Faz 3b-B): /app/notification-preferences EKLEMELİ genişleme (DB'siz, KATI sahte veritabanı). GET: push_available, push_show_preview,
// push_quiet { enabled, start, end } ("HH:MM"), push_devices. PUT KISMİ: bilinen anahtarlardan en az biri; bilinmeyen yok sayılır; hiç bilinen yoksa 400;
// yalnız email_announcements gönderen ESKİ istemci aynen çalışır (push yazımı yok); HH:MM doğrulaması; başlangıç = bitiş 400 (saklı değerle birleşik);
// kullanıcı satırı KEY SHARE kilidi (silinmiş hesaba yazmaz).
import { describe, it, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert/strict';
import { pool } from '../src/db.js';
import { getNotificationPreferences, setNotificationPreferences } from '../src/modules/announcement_inbox.js';
import { parsePushPreferenceInput, pushPreferenceHooks } from '../src/modules/push_preferences.js';

process.env.JWT_SECRET ||= 'unit-test-secret-0123456789abcdef';
const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
const ok = (rows = [], rowCount = rows.length) => ({ rows, rowCount });
const user = { id: 20004, user_code: 20004, userCode: 20004, role: 'apartment_owner' };

let db;
let savedAvailable;

function installFakeDb() {
  db = { log: [], live: true, stored: null, devices: 0, emailRow: { email_announcements: true, email_finance_reminders: true, push_announcements: true } };
  const run = async (text, params = []) => {
    const sql = norm(text);
    db.log.push({ sql, params });
    if (/^(BEGIN|COMMIT|ROLLBACK)$/.test(sql)) return ok();
    if (/^SELECT email_announcements, email_finance_reminders, push_announcements FROM notification_preferences WHERE user_code = \$1$/.test(sql)) return ok([db.emailRow]);
    if (/^SELECT EXISTS \( SELECT 1 FROM \( SELECT translate/.test(sql)) return ok([{ suppressed: false }]);
    if (/^INSERT INTO notification_preferences \(user_code, email_announcements, email_finance_reminders\)/.test(sql)) return ok([db.emailRow]);
    if (/^DELETE FROM announcement_email_suppressions/.test(sql)) return ok([], 0);
    if (/^SELECT user_code FROM users WHERE user_code = \$1 AND deleted_at IS NULL AND is_active = TRUE FOR KEY SHARE$/.test(sql)) return ok(db.live ? [{ user_code: params[0] }] : []);
    if (/^SELECT push_quiet_start, push_quiet_end FROM notification_preferences WHERE user_code = \$1 FOR UPDATE$/.test(sql)) return ok(db.stored ? [db.stored] : []);
    if (/^INSERT INTO notification_preferences \(user_code, push_announcements, push_show_preview, push_quiet_enabled, push_quiet_start, push_quiet_end\)/.test(sql)) {
      const [, announcements, preview, quiet, start, end] = params;
      db.stored = {
        push_announcements: announcements ?? db.stored?.push_announcements ?? true,
        push_show_preview: preview ?? db.stored?.push_show_preview ?? false,
        push_quiet_enabled: quiet ?? db.stored?.push_quiet_enabled ?? false,
        push_quiet_start: start,
        push_quiet_end: end,
      };
      db.emailRow = { ...db.emailRow, push_announcements: db.stored.push_announcements };
      return ok([], 1);
    }
    if (/^SELECT np\.push_show_preview, np\.push_quiet_enabled, np\.push_quiet_start, np\.push_quiet_end, \(SELECT COUNT\(\*\)::INTEGER FROM push_devices d WHERE d\.user_code = \$1\) AS device_count FROM \(SELECT \$1::INTEGER AS user_code\) me LEFT JOIN notification_preferences np ON np\.user_code = me\.user_code$/.test(sql)) {
      const row = db.stored ?? { push_show_preview: null, push_quiet_enabled: null, push_quiet_start: null, push_quiet_end: null };
      return ok([{ ...row, device_count: db.devices }]);
    }
    throw new Error(`BEKLENMEYEN SQL (sahte DB katı): ${sql.slice(0, 160)}`);
  };
  pool.query = async (text, params) => run(text, params);
  pool.connect = async () => ({ query: run, release() {} });
}

beforeEach(() => {
  installFakeDb();
  savedAvailable = pushPreferenceHooks.available;
  mock.method(console, 'error', () => {});
});

afterEach(() => {
  pushPreferenceHooks.available = savedAvailable;
  delete pool.query;
  delete pool.connect;
  mock.restoreAll();
});

const pushWrites = () => db.log.filter((q) => /^INSERT INTO notification_preferences \(user_code, push_announcements/.test(q.sql));

describe('GET /app/notification-preferences (EKLEMELİ push alanları)', () => {
  it('kayıt yok: push_show_preview false, push_quiet { false, "23:00", "07:00" }, push_devices sayısı, push_available gerçek durum', async () => {
    db.devices = 2;
    const body = await getNotificationPreferences(user);
    assert.deepEqual(body, {
      email_announcements: true,
      email_finance_reminders: true,
      push_announcements: true,
      push_available: false,
      email_suppressed: false,
      push_show_preview: false,
      push_quiet: { enabled: false, start: '23:00', end: '07:00' },
      push_devices: 2,
    });
    pushPreferenceHooks.available = () => true;
    assert.equal((await getNotificationPreferences(user)).push_available, true);
  });

  it('saklı değerler "HH:MM" olarak döner; kullanıcı kodu yoksa DB sorgusu yok', async () => {
    db.stored = { push_show_preview: true, push_quiet_enabled: true, push_quiet_start: 1350, push_quiet_end: 405 };
    const body = await getNotificationPreferences(user);
    assert.deepEqual([body.push_show_preview, body.push_quiet], [true, { enabled: true, start: '22:30', end: '06:45' }]);
    db.log.length = 0;
    assert.deepEqual((await getNotificationPreferences({})).push_quiet, { enabled: false, start: '23:00', end: '07:00' });
    assert.equal(db.log.length, 0);
  });
});

describe('PUT /app/notification-preferences (KISMİ)', () => {
  it('ESKİ istemci: yalnız email_announcements -> push yazımı YOK, yanıt yine push alanlarını taşır', async () => {
    const body = await setNotificationPreferences(user, { email_announcements: false });
    assert.equal(pushWrites().length, 0);
    // R7: e-posta tercihi de TEK işlemde ve kullanıcı satırı KEY SHARE kilidi altında yazılır (silinmiş hesaba tercih yazılmaz)
    const lock = db.log.findIndex((q) => /FOR KEY SHARE/.test(q.sql));
    const upsert = db.log.findIndex((q) => /^INSERT INTO notification_preferences \(user_code, email_announcements/.test(q.sql));
    const commit = db.log.findIndex((q) => q.sql === 'COMMIT');
    assert.ok(db.log[0].sql === 'BEGIN' && lock > 0 && lock < upsert && upsert < commit, db.log.map((q) => q.sql.slice(0, 24)).join(' | '));
    assert.ok('push_quiet' in body && 'push_devices' in body && 'push_show_preview' in body);
  });

  it('R7: e-posta + push KISMİ PUT TEK işlemdir: push tercihi ve e-posta UPSERT\'i AYNI BEGIN / COMMIT içinde (tek BEGIN); push yazımı kendi işlemini AÇMAZ', async () => {
    await setNotificationPreferences(user, { email_announcements: false, push_quiet_enabled: true, push_quiet_start: '22:00' });
    assert.equal(db.log.filter((q) => q.sql === 'BEGIN').length, 1);
    assert.equal(db.log.filter((q) => q.sql === 'COMMIT').length, 1);
    const begin = db.log.findIndex((q) => q.sql === 'BEGIN');
    const commit = db.log.findIndex((q) => q.sql === 'COMMIT');
    const pushAt = db.log.findIndex((q) => /^INSERT INTO notification_preferences \(user_code, push_announcements/.test(q.sql));
    const emailAt = db.log.findIndex((q) => /^INSERT INTO notification_preferences \(user_code, email_announcements/.test(q.sql));
    assert.ok(begin < pushAt && pushAt < emailAt && emailAt < commit);
  });

  it('R7: sessiz saat çakışması (başlangıç = bitiş) e-posta tercihini de GERİ ALIR: e-posta UPSERT\'i çalışmaz, ROLLBACK, COMMIT yok', async () => {
    await assert.rejects(() => setNotificationPreferences(user, { email_announcements: false, push_quiet_start: '07:00', push_quiet_end: '07:00' }), (e) => e.code === 'INVALID_BODY');
    db.log.length = 0;
    db.stored = { push_show_preview: false, push_quiet_enabled: true, push_quiet_start: 1380, push_quiet_end: 420 };
    await assert.rejects(() => setNotificationPreferences(user, { email_announcements: false, push_quiet_start: '07:00' }), (e) => e.code === 'INVALID_BODY' && /aynı olamaz/.test(e.message));
    assert.equal(db.log.some((q) => /^INSERT INTO notification_preferences/.test(q.sql)), false, 'kısmi yazım yok');
    assert.ok(db.log.some((q) => q.sql === 'ROLLBACK') && !db.log.some((q) => q.sql === 'COMMIT'));
  });

  it('R7: silinmiş / pasif hesap + SADECE e-posta anahtarı -> 401 ACCOUNT_DELETED, hiçbir tercih satırı yazılmaz', async () => {
    db.live = false;
    await assert.rejects(() => setNotificationPreferences(user, { email_announcements: false }), (e) => e.statusCode === 401 && e.code === 'ACCOUNT_DELETED');
    assert.equal(db.log.some((q) => /^INSERT INTO notification_preferences/.test(q.sql)), false);
  });

  it('yalnız push anahtarları geçerlidir (e-posta tercihi DEĞİŞMEZ); kilit: users KEY SHARE (deleted_at IS NULL) -> tercih satırı FOR UPDATE -> UPSERT', async () => {
    const body = await setNotificationPreferences(user, { push_show_preview: true, push_quiet_enabled: true, push_quiet_start: '22:00', bilinmeyen: 1 });
    const order = db.log.map((q) => q.sql.slice(0, 30));
    const lock = db.log.findIndex((q) => /FOR KEY SHARE/.test(q.sql));
    const read = db.log.findIndex((q) => /FOR UPDATE$/.test(q.sql));
    const write = db.log.findIndex((q) => /^INSERT INTO notification_preferences \(user_code, push_announcements/.test(q.sql));
    assert.ok(lock > 0 && lock < read && read < write, order.join(' | '));
    assert.deepEqual(pushWrites()[0].params, [20004, null, true, true, 1320, 420], 'gönderilmeyen alan null (COALESCE ile değişmez), bitiş saklı/varsayılan');
    assert.match(pushWrites()[0].sql, /push_announcements = COALESCE\(\$2::BOOLEAN, notification_preferences\.push_announcements\)/);
    assert.deepEqual(body.push_quiet, { enabled: true, start: '22:00', end: '07:00' });
    assert.equal(body.push_show_preview, true);
    const emailUpsert = db.log.find((q) => /^INSERT INTO notification_preferences \(user_code, email_announcements/.test(q.sql));
    assert.deepEqual(emailUpsert.params, [20004, null, null], 'e-posta tercihleri COALESCE ile korunur');
  });

  it('push_announcements false yazılır; e-posta + push birlikte gönderilebilir', async () => {
    const body = await setNotificationPreferences(user, { email_announcements: true, push_announcements: false });
    assert.deepEqual(pushWrites()[0].params.slice(0, 4), [20004, false, null, null]);
    assert.equal(body.push_announcements, false);
  });

  it('hiç bilinen anahtar yoksa 400 INVALID_BODY; push değerleri yanlış türdeyse 400 (Türkçe, alan adı yok) ve HİÇBİR şey yazılmaz', async () => {
    for (const body of [{}, { bilinmeyen: true }, { push_announcements: 'evet' }, { push_show_preview: 1 }, { push_quiet_enabled: null }, { push_quiet_start: '25:00' }, { push_quiet_end: 420 }, { push_quiet_start: '7:00' }]) {
      await assert.rejects(() => setNotificationPreferences(user, body), (e) => e.code === 'INVALID_BODY' && e.statusCode === 400 && !/push_|_/.test(e.message), JSON.stringify(body));
    }
    await assert.rejects(() => setNotificationPreferences(user, { email_announcements: false, push_quiet_start: 'x' }), (e) => e.code === 'INVALID_BODY');
    assert.equal(db.log.length, 0, 'doğrulama yazmadan ÖNCE');
  });

  it('sessiz saat başlangıcı = bitişi -> 400 (gövdede birlikte ya da SAKLI değerle birleşince)', async () => {
    await assert.rejects(() => setNotificationPreferences(user, { push_quiet_start: '07:00', push_quiet_end: '07:00' }), (e) => e.code === 'INVALID_BODY' && /aynı olamaz/.test(e.message));
    db.stored = { push_show_preview: false, push_quiet_enabled: true, push_quiet_start: 1380, push_quiet_end: 420 };
    await assert.rejects(() => setNotificationPreferences(user, { push_quiet_start: '07:00' }), (e) => e.code === 'INVALID_BODY' && /aynı olamaz/.test(e.message));
    assert.equal(pushWrites().length, 0);
    assert.ok(db.log.some((q) => q.sql === 'ROLLBACK'));
  });

  it('silinmiş / pasif hesap -> 401 ACCOUNT_DELETED, tercih yazılmaz', async () => {
    db.live = false;
    await assert.rejects(() => setNotificationPreferences(user, { push_announcements: false }), (e) => e.statusCode === 401 && e.code === 'ACCOUNT_DELETED');
    assert.equal(pushWrites().length, 0);
  });

  it('parsePushPreferenceInput: present bayrağı ve dakika değerleri', () => {
    assert.deepEqual(parsePushPreferenceInput({ email_announcements: true }), { present: false, values: {} });
    assert.deepEqual(parsePushPreferenceInput({ push_quiet_start: '00:00', push_quiet_end: '23:59' }), { present: true, values: { push_quiet_start: 0, push_quiet_end: 1439 } });
  });
});
