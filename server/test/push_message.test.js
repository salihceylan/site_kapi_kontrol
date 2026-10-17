// Telefon bildirimi (Faz 3b-B): mesaj kurucu (B5) ve bildirim metni (B7): ayrıntısız varsayılan, push_show_preview açıkken tek satır / <= 80 karakter,
// acil alanları (HIGH, urgent kanalı, time-sensitive, 48 sa), `data` yalnız izinli anahtarlar, badge yok; saf yardımcılar (sessiz saat, HH:MM,
// İstanbul günü, geri çekilme, cihaz gövdesi doğrulaması).
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import {
  NORMAL_BODY,
  URGENT_TITLE,
  announcementTexts,
  buildAnnouncementMessage,
  buildTestMessage,
  singleLine,
} from '../src/modules/push_message.js';
import {
  QUIET_MAX_DEFER_MS,
  TOKEN_MAX_LENGTH,
  formatHhmm,
  isInQuietWindow,
  istanbulDayStartMs,
  istanbulMinuteOfDay,
  parseDeviceInput,
  parseHhmm,
  quietDecision,
  quietWindowEndMs,
  retryDelaySeconds,
  sanitizeErrorCode,
} from '../src/modules/push_common.js';

const TOKEN = 'fcm-kayit-jetonu-0123456789-abcdef';
const base = { token: TOKEN, announcementId: 123, siteCode: 1234567890, siteName: 'Gül Sitesi', title: 'Su kesintisi: A Blok 3 numara 1.250 TL', nowMs: 1_800_000_000_000 };
const ALLOWED_DATA_KEYS = ['announcement_id', 'importance', 'site_code', 'type'];

describe('bildirim metni (B7)', () => {
  it('normal varsayılan AYRINTISIZ: başlık site adı, gövde sabit; duyuru başlığı / tutar / daire GİTMEZ', () => {
    const msg = buildAnnouncementMessage({ ...base, importance: 'normal', showPreview: false });
    assert.deepEqual(msg.notification, { title: 'Gül Sitesi', body: NORMAL_BODY });
    assert.equal(NORMAL_BODY, 'Yönetimden yeni bir duyuru var.');
    assert.doesNotMatch(JSON.stringify(msg), /Su kesintisi|1\.250|A Blok/);
  });

  it('acil varsayılan: "Acil duyuru" + "{Site adı}: acil bir duyuru var. Ayrıntı için uygulamayı açın."', () => {
    const msg = buildAnnouncementMessage({ ...base, importance: 'urgent', showPreview: false });
    assert.deepEqual(msg.notification, { title: URGENT_TITLE, body: 'Gül Sitesi: acil bir duyuru var. Ayrıntı için uygulamayı açın.' });
  });

  it('push_show_preview açık: gövde = duyuru başlığı (tek satır, temiz, <= 80 karakter, "…" ile kısaltma)', () => {
    const long = `Satır bir\nsatır\tiki ${'ğ'.repeat(120)}`;
    const texts = announcementTexts({ siteName: 'Gül Sitesi', title: long, importance: 'normal', showPreview: true });
    assert.equal(texts.title, 'Gül Sitesi');
    assert.equal(Array.from(texts.body).length, 80);
    assert.ok(texts.body.endsWith('…'));
    assert.doesNotMatch(texts.body, /[\n\t]/);
    assert.ok(texts.body.startsWith('Satır bir satır iki ğ'));
    assert.equal(announcementTexts({ siteName: 'S', title: 'Kısa başlık', importance: 'urgent', showPreview: true }).body, 'Kısa başlık');
    assert.equal(announcementTexts({ siteName: 'S', title: 'Kısa başlık', importance: 'urgent', showPreview: true }).title, URGENT_TITLE);
  });

  it('site adı <= 40 karakter, tek satır; yoksa "Site Yönetimi"; görünmez / yön denetim karakterleri atılır', () => {
    const texts = announcementTexts({ siteName: `${'A'.repeat(50)}`, title: 'x', importance: 'normal', showPreview: false });
    assert.equal(Array.from(texts.title).length, 40);
    assert.equal(announcementTexts({ siteName: null, title: 'x', importance: 'normal' }).title, 'Site Yönetimi');
    assert.equal(singleLine(`a${String.fromCodePoint(0x202e)}b${String.fromCodePoint(0x200b)}c\r\nd`, 80), 'abc d');
    assert.equal(singleLine(42, 10), '');
  });
});

describe('FCM mesajı (B5)', () => {
  it('normal: data yalnız izinli anahtarlar (string), android NORMAL / announcements / 86400s / collapse ann-<id>, apns active, badge YOK', () => {
    const msg = buildAnnouncementMessage({ ...base, importance: 'normal', showPreview: false });
    assert.equal(msg.token, TOKEN);
    assert.deepEqual(Object.keys(msg.data).sort(), ALLOWED_DATA_KEYS);
    assert.deepEqual(msg.data, { type: 'announcement', announcement_id: '123', site_code: '1234567890', importance: 'normal' });
    assert.ok(Object.values(msg.data).every((value) => typeof value === 'string'));
    assert.deepEqual(msg.android, { priority: 'NORMAL', ttl: '86400s', collapse_key: 'ann-123', notification: { channel_id: 'announcements', tag: 'ann-123' } });
    assert.deepEqual(msg.apns.headers, { 'apns-priority': '10', 'apns-push-type': 'alert', 'apns-collapse-id': 'ann-123', 'apns-expiration': String(1_800_000_000 + 86400) });
    assert.deepEqual(msg.apns.payload, { aps: { sound: 'default', 'thread-id': 'site-1234567890', 'interruption-level': 'active' } });
    assert.doesNotMatch(JSON.stringify(msg), /badge/);
  });

  it('acil: HIGH + urgent kanalı + time-sensitive + 172800s; "critical" YOK; preview açıkken bile data başlık taşımaz', () => {
    const msg = buildAnnouncementMessage({ ...base, importance: 'urgent', showPreview: true });
    assert.equal(msg.android.priority, 'HIGH');
    assert.equal(msg.android.ttl, '172800s');
    assert.equal(msg.android.notification.channel_id, 'urgent');
    assert.equal(msg.apns.payload.aps['interruption-level'], 'time-sensitive');
    assert.equal(msg.apns.headers['apns-expiration'], String(1_800_000_000 + 172800));
    assert.equal(msg.data.importance, 'urgent');
    assert.deepEqual(Object.keys(msg.data).sort(), ALLOWED_DATA_KEYS);
    assert.doesNotMatch(JSON.stringify(msg.data), /Su kesintisi/);
    assert.doesNotMatch(JSON.stringify(msg), /critical|badge/);
  });

  it('inceleme: ttl = min(varsayılan, kalan ömür); apns-expiration aynı süreyle; geçersiz / verilmemiş kalan ömür varsayılan', () => {
    const short = buildAnnouncementMessage({ ...base, importance: 'normal', ttlSeconds: 1800.9 });
    assert.equal(short.android.ttl, '1800s');
    assert.equal(short.apns.headers['apns-expiration'], String(1_800_000_000 + 1800));
    assert.equal(buildAnnouncementMessage({ ...base, importance: 'urgent', ttlSeconds: 999999 }).android.ttl, '172800s');
    assert.equal(buildAnnouncementMessage({ ...base, importance: 'normal', ttlSeconds: 0.2 }).android.ttl, '1s', 'en az 1 sn (0 ise işçi zaten expired yapar)');
    assert.equal(buildAnnouncementMessage({ ...base, importance: 'normal' }).android.ttl, '86400s');
    assert.equal(buildAnnouncementMessage({ ...base, importance: 'normal', ttlSeconds: 'x' }).android.ttl, '86400s');
    assert.equal(TOKEN_MAX_LENGTH, 2048);
    assert.doesNotThrow(() => parseDeviceInput({ install_id: '3f2b8c1e-9a7d-4e21-b1aa-0c9d8e7f6a5b', platform: 'ios', token: 'a'.repeat(2048) }));
  });

  it('test bildirimi: genel metin, data yalnız type=test, duyuruya bağlı alan yok', () => {
    const msg = buildTestMessage({ token: TOKEN, nowMs: base.nowMs });
    assert.deepEqual(msg.notification, { title: 'Test bildirimi', body: 'Telefon bildirimleri bu cihazda çalışıyor.' });
    assert.deepEqual(msg.data, { type: 'test' });
    assert.doesNotMatch(JSON.stringify(msg), /badge|collapse/);
  });
});

describe('saf yardımcılar', () => {
  // 2026-10-17 00:00 İstanbul = 2026-10-16T21:00:00Z
  const istanbul = (hh, mm, dayOffset = 0) => Date.UTC(2026, 9, 16, 21, 0, 0) + dayOffset * 86400000 + (hh * 60 + mm) * 60000;

  it('HH:MM ayrıştırma / biçimlendirme; İstanbul gün içi dakika ve gün başı (UTC+3, yaz saati yok)', () => {
    assert.equal(parseHhmm('23:00'), 1380);
    assert.equal(parseHhmm('07:05'), 425);
    for (const bad of ['24:00', '7:00', '23:60', '', null, 1380, '23:00:00']) assert.equal(parseHhmm(bad), null, String(bad));
    assert.equal(formatHhmm(420), '07:00');
    assert.equal(formatHhmm(5000, 1380), '23:00');
    assert.equal(istanbulMinuteOfDay(istanbul(23, 30)), 1410);
    assert.equal(istanbulDayStartMs(istanbul(0, 10)), istanbul(0, 0));
    assert.equal(istanbulDayStartMs(istanbul(23, 59)), istanbul(0, 0));
  });

  it('sessiz pencere gece yarısını aşar (23:00-07:00): başlangıç dahil, bitiş hariç; gün içi pencere (12:00-14:00)', () => {
    assert.equal(isInQuietWindow(1380, 1380, 420), true);
    assert.equal(isInQuietWindow(0, 1380, 420), true);
    assert.equal(isInQuietWindow(419, 1380, 420), true);
    assert.equal(isInQuietWindow(420, 1380, 420), false);
    assert.equal(isInQuietWindow(720, 1380, 420), false);
    assert.equal(isInQuietWindow(780, 720, 840), true);
    assert.equal(isInQuietWindow(840, 720, 840), false);
    assert.equal(isInQuietWindow(100, 100, 100), false, 'başlangıç = bitiş: pencere yok');
  });

  it('quietDecision: pencere içinde -> erteleme pencere sonuna (ertesi gün 07:00); dışında / kapalıyken erteleme yok', () => {
    const now = istanbul(23, 30);
    const decision = quietDecision({ nowMs: now, enabled: true, start: 1380, end: 420, expiresAtMs: now + 24 * 3600000 });
    assert.deepEqual(decision, { defer: true, untilMs: istanbul(7, 0, 1) });
    assert.equal(quietWindowEndMs(istanbul(2, 0, 1), 420), istanbul(7, 0, 1), 'gece yarısından sonra aynı günün 07:00\'si');
    assert.deepEqual(quietDecision({ nowMs: istanbul(12, 0), enabled: true, start: 1380, end: 420, expiresAtMs: Infinity }), { defer: false });
    assert.deepEqual(quietDecision({ nowMs: now, enabled: false, start: 1380, end: 420, expiresAtMs: Infinity }), { defer: false });
  });

  it('12 saat üst sınırı: 12 saatten uzun erteleme ya da geçerlilik sonunu aşan erteleme -> expire', () => {
    const now = istanbul(18, 30);
    // 18:00-07:00 penceresi: 18:30'da 12,5 saat ertelenirdi
    assert.deepEqual(quietDecision({ nowMs: now, enabled: true, start: 1080, end: 420, expiresAtMs: Infinity }), { expire: true });
    assert.ok(istanbul(7, 0, 1) - now > QUIET_MAX_DEFER_MS);
    // tam 12 saat: ertelenir
    assert.equal(quietDecision({ nowMs: istanbul(19, 0), enabled: true, start: 1080, end: 420, expiresAtMs: Infinity }).defer, true);
    // geçerlilik pencere sonundan önce bitiyor
    const late = istanbul(23, 30);
    assert.deepEqual(quietDecision({ nowMs: late, enabled: true, start: 1380, end: 420, expiresAtMs: istanbul(6, 0, 1) }), { expire: true });
  });

  it('geri çekilme 60 / 300 / 1200 sn; hata kodu temizliği', () => {
    assert.deepEqual([1, 2, 3, 4, 0].map(retryDelaySeconds), [60, 300, 1200, 1200, 60]);
    assert.equal(sanitizeErrorCode('quota-exceeded <b>'), 'QUOTA_EXCEEDED_B');
    assert.equal(sanitizeErrorCode(''), 'ERROR');
    assert.equal(sanitizeErrorCode('x'.repeat(100)).length, 64);
  });

  it('cihaz gövdesi: install_id 16-64, platform android|ios, jeton 20-4096 yazdırılabilir ASCII, app_version <= 32; mesajlarda alan adı / jeton yok', () => {
    const good = { install_id: '3f2b8c1e-9a7d-4e21-b1aa-0c9d8e7f6a5b', platform: 'android', token: TOKEN, app_version: '1.2.3+45', notifications_enabled: false };
    assert.deepEqual(parseDeviceInput(good), { installId: good.install_id, platform: 'android', token: TOKEN, appVersion: '1.2.3+45', notificationsEnabled: false });
    assert.deepEqual(parseDeviceInput({ ...good, app_version: undefined, notifications_enabled: undefined }).notificationsEnabled, null);
    const bad = [
      { ...good, install_id: 'kisa' },
      { ...good, install_id: 'x'.repeat(65) },
      { ...good, install_id: 'boşluklu kimlik 1234567890' },
      { ...good, platform: 'web' },
      { ...good, token: 'kisa-jeton' },
      { ...good, token: `${'a'.repeat(30)} bosluk` },
      { ...good, token: 'a'.repeat(2049) }, // inceleme: 2048 (tekil btree satır sınırı; sözleşmedeki 4096'dan sapma)
      { ...good, app_version: 'x'.repeat(33) },
      { ...good, notifications_enabled: 'evet' },
      null,
      [],
    ];
    for (const body of bad) {
      assert.throws(
        () => parseDeviceInput(body),
        (error) => error.code === 'INVALID_BODY' && error.statusCode === 400 && !/_|install|token/.test(error.message) && !error.message.includes(TOKEN),
        JSON.stringify(body)?.slice(0, 80),
      );
    }
  });
});
