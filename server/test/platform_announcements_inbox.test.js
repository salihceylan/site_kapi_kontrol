// Duyuru ve Bildirim (Faz 3a) sakin tarafı (DB'siz): gelen kutusu, okundu, tümünü okundu yap, bildirim özeti, bildirim tercihleri.
// Her sorgu çağıranın user_code'u üzerinden bağlanır (başkasının satırına erişim yok); anlamı gerçek-PG betiğinde sınanır.
import { describe, it, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert/strict';
import { pool } from '../src/db.js';
import { emailHashSalts } from '../src/modules/announcement_email_security.js';
import {
  getMyAnnouncement,
  getNotificationPreferences,
  getNotificationSummary,
  listMyAnnouncements,
  markAllAnnouncementsRead,
  markAnnouncementRead,
  setNotificationPreferences,
} from '../src/modules/announcement_inbox.js';

process.env.JWT_SECRET ||= 'unit-test-secret-0123456789abcdef';
const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
const ok = (rows = [], rowCount = rows.length) => ({ rows, rowCount });
const user = { id: 20004, user_code: 20004, userCode: 20004, role: 'apartment_owner', full_name: 'Deniz Sakin' };

let log;
let handlers;

beforeEach(() => {
  log = [];
  handlers = [];
  pool.query = async (text, params) => {
    const sql = norm(text);
    log.push({ sql, params: params ?? [] });
    for (const [pattern, handler] of handlers) {
      if (pattern.test(sql)) return typeof handler === 'function' ? handler(sql, params ?? []) : handler;
    }
    throw new Error(`BEKLENMEYEN SQL (sahte DB katı): ${sql.slice(0, 200)}`);
  };
  mock.method(console, 'error', () => {});
});

afterEach(() => {
  delete pool.query;
  mock.restoreAll();
});

const row = (id, overrides = {}) => ({
  id: String(id),
  site_code: '1000000001',
  site_name: 'Gül Sitesi',
  title: `Duyuru ${id}`,
  body_head: 'Gövde',
  body_length: '5',
  importance: 'normal',
  published_at: new Date(`2026-10-16T0${id}:00:00.000Z`),
  edited_at: null,
  read_at: null,
  ...overrides,
});

describe('gelen kutusu: liste', () => {
  it('çağıranın user_code\'u, yayında + onaylı site filtresiyle; sıra published_at DESC, id DESC; limit + 1 satır çekilir', async () => {
    handlers.push([/^SELECT a\.id, a\.site_code, s\.name AS site_name/, () => ok([row(3), row(2), row(1)])]);
    const result = await listMyAnnouncements(user, { limit: '2' });
    const query = log[0];
    assert.deepEqual(query.params, [20004, 3]);
    assert.match(query.sql, /FROM site_people sp INNER JOIN announcement_recipients r ON r\.person_id = sp\.id INNER JOIN announcements a ON a\.id = r\.announcement_id AND a\.status = 'published' INNER JOIN sites s ON s\.site_code = a\.site_code AND s\.approval_status = 'approved'/);
    assert.match(query.sql, /WHERE sp\.user_code = \$1/);
    assert.match(query.sql, /ORDER BY a\.published_at DESC, a\.id DESC LIMIT \$2$/);
    assert.deepEqual(result.items.map((i) => i.id), [3, 2]);
    assert.equal(result.next_before_id, 2, 'sonraki sayfa imleci = son dönen kimlik');
    assert.equal(result.items[0].is_read, false);
    assert.equal(result.items[0].body_preview, 'Gövde');
  });

  it('son sayfa: fazla satır yoksa next_before_id null', async () => {
    handlers.push([/^SELECT a\.id/, () => ok([row(2), row(1)])]);
    const result = await listMyAnnouncements(user, { limit: '5' });
    assert.equal(result.items.length, 2);
    assert.equal(result.next_before_id, null);
  });

  it('before_id: imleç satırının (published_at, id) çiftinden küçükler (kimlik sırasından bağımsız); site_code süzgeci eklenir', async () => {
    handlers.push([/^SELECT a\.id/, () => ok()]);
    await listMyAnnouncements(user, { before_id: '42', site_code: '1000000007', limit: '10' });
    const query = log[0];
    assert.deepEqual(query.params, [20004, 1000000007, 42, 11]);
    assert.match(query.sql, /a\.site_code = \$2/);
    // D5: imleç satırı ÇAĞIRANIN alıcı olduğu duyuruya bağlıdır (başkasının / başka sitenin duyurusunun varlığı ve yayın zamanı sızmaz)
    assert.match(
      query.sql,
      /\(a\.published_at, a\.id\) < \( SELECT c\.published_at, c\.id FROM announcements c INNER JOIN announcement_recipients cr ON cr\.announcement_id = c\.id INNER JOIN site_people cs ON cs\.id = cr\.person_id AND cs\.user_code = \$1 WHERE c\.id = \$3 AND c\.status IN \('published', 'withdrawn'\) LIMIT 1 \)/,
    );
  });

  it('D5: imleç alt sorgusu çağıranın user_code\'una ($1) bağlıdır ve alt sorgu satırı bulamazsa karşılaştırma NULL olur (sayfa boş, varlık sızmaz)', async () => {
    handlers.push([/^SELECT a\.id/, () => ok()]);
    await listMyAnnouncements(user, { before_id: '999' });
    const cursor = /\(a\.published_at, a\.id\) < \( (SELECT c\.published_at.*?LIMIT 1) \)/.exec(log[0].sql)?.[1] ?? '';
    assert.match(cursor, /cs\.user_code = \$1/);
    assert.doesNotMatch(cursor, /^SELECT c\.published_at, c\.id FROM announcements c WHERE c\.id = \$\d$/);
    // geri çekilmiş kendi duyurusu imleç olarak geçerli kalır (sayfa dolaşımı kopmaz); taslak / zamanlanmış hiçbir zaman imleç olamaz
    assert.match(cursor, /c\.status IN \('published', 'withdrawn'\)/);
  });

  it('geçersiz imleç / site kodu -> 400 INVALID_QUERY ve DB yok; kullanıcı kodu yoksa boş', async () => {
    await assert.rejects(() => listMyAnnouncements(user, { before_id: 'abc' }), (e) => e.code === 'INVALID_QUERY');
    await assert.rejects(() => listMyAnnouncements(user, { site_code: '0' }), (e) => e.code === 'INVALID_QUERY');
    assert.equal(log.length, 0);
    assert.deepEqual(await listMyAnnouncements({}, {}), { items: [], next_before_id: null });
    assert.equal(log.length, 0);
  });
});

describe('gelen kutusu: ayrıntı ve okundu', () => {
  it('ayrıntı: tam metin + edited_at + is_read; OKUNDU YAZMAZ (yalnız SELECT)', async () => {
    handlers.push([/^SELECT a\.id, a\.site_code, s\.name AS site_name, a\.title, a\.body, a\.importance, a\.published_at, a\.edited_at, r\.read_at/, () => ok([{ ...row(2), body: 'Tam metin', body_head: undefined, edited_at: new Date('2026-10-16T09:00:00.000Z'), read_at: null }])]);
    const detail = await getMyAnnouncement(user, '2');
    assert.deepEqual(log[0].params, [20004, 2]);
    assert.match(log[0].sql, /WHERE sp\.user_code = \$1 AND a\.id = \$2 LIMIT 1$/);
    assert.equal(log.some((q) => /^(UPDATE|INSERT|DELETE)/.test(q.sql)), false);
    assert.equal(detail.body, 'Tam metin');
    assert.equal(detail.edited_at, '2026-10-16T09:00:00.000Z');
    assert.equal(detail.is_read, false);
    assert.equal(detail.read_at, null);
  });

  it('alıcı değil / yayında değil / geçersiz kimlik -> 404 ANNOUNCEMENT_NOT_FOUND', async () => {
    handlers.push([/^SELECT a\.id, a\.site_code/, () => ok()]);
    await assert.rejects(() => getMyAnnouncement(user, '2'), (e) => e.code === 'ANNOUNCEMENT_NOT_FOUND' && e.statusCode === 404);
    await assert.rejects(() => getMyAnnouncement(user, 'abc'), (e) => e.code === 'ANNOUNCEMENT_NOT_FOUND');
    await assert.rejects(() => getMyAnnouncement({}, '2'), (e) => e.code === 'ANNOUNCEMENT_NOT_FOUND');
  });

  it('okundu: UPDATE yalnız okunmamış + çağıranın satırı + yayında; ilk okuma zamanı döner', async () => {
    const readAt = new Date('2026-10-16T10:00:00.000Z');
    // D11: okundu da liste / ayrıntı / özet ile AYNI süzgeci uygular (yayında + onaylı site)
    handlers.push([/^UPDATE announcement_recipients r SET read_at = NOW\(\) FROM site_people sp, announcements a, sites s WHERE r\.announcement_id = \$1 AND sp\.id = r\.person_id AND sp\.user_code = \$2 AND a\.id = r\.announcement_id AND a\.status = 'published' AND s\.site_code = a\.site_code AND s\.approval_status = 'approved' AND r\.read_at IS NULL RETURNING r\.read_at$/, () => ok([{ read_at: readAt }])]);
    assert.deepEqual(await markAnnouncementRead(user, '7'), { ok: true, read_at: '2026-10-16T10:00:00.000Z' });
    assert.deepEqual(log[0].params, [7, 20004]);
  });

  it('okundu idempotent: zaten okunmuşsa UPDATE satır döndürmez, ilk okuma zamanı SELECT ile korunarak döner', async () => {
    const first = new Date('2026-10-15T08:00:00.000Z');
    handlers.push([/^UPDATE announcement_recipients r SET read_at/, () => ok()], [/^SELECT r\.read_at FROM site_people sp/, () => ok([{ read_at: first }])]);
    assert.deepEqual(await markAnnouncementRead(user, '7'), { ok: true, read_at: '2026-10-15T08:00:00.000Z' });
    assert.deepEqual(log[1].params, [20004, 7]);
  });

  it('okundu: alıcı olmayan / geri çekilmiş -> 404 (UPDATE de SELECT de boş)', async () => {
    handlers.push([/^UPDATE announcement_recipients r SET read_at/, () => ok()], [/^SELECT r\.read_at FROM site_people sp/, () => ok()]);
    await assert.rejects(() => markAnnouncementRead(user, '7'), (e) => e.code === 'ANNOUNCEMENT_NOT_FOUND' && e.statusCode === 404);
    await assert.rejects(() => markAnnouncementRead(user, 'x'), (e) => e.code === 'ANNOUNCEMENT_NOT_FOUND');
  });

  it('tümünü okundu yap: yalnız çağıranın okunmamış + yayındaki satırları; site_code isteğe bağlı; marked = etkilenen satır', async () => {
    handlers.push([/^UPDATE announcement_recipients r SET read_at = NOW\(\) FROM site_people sp, announcements a, sites s WHERE sp\.id = r\.person_id AND sp\.user_code = \$1 AND a\.id = r\.announcement_id AND a\.status = 'published' AND s\.site_code = a\.site_code AND s\.approval_status = 'approved' AND r\.read_at IS NULL AND \(\$2::BIGINT IS NULL OR a\.site_code = \$2::BIGINT\)$/, () => ok([], 4)]);
    assert.deepEqual(await markAllAnnouncementsRead(user, {}), { ok: true, marked: 4 });
    assert.deepEqual(log[0].params, [20004, null]);
    await markAllAnnouncementsRead(user, { site_code: '1000000001' });
    assert.deepEqual(log[1].params, [20004, 1000000001]);
  });

  it('tümünü okundu yap: geçersiz site_code -> 400 INVALID_BODY (Türkçe etiket); kullanıcı kodu yoksa 0 ve DB yok', async () => {
    await assert.rejects(() => markAllAnnouncementsRead(user, { site_code: 'abc' }), (e) => e.code === 'INVALID_BODY' && !/site_code/.test(e.message));
    assert.deepEqual(await markAllAnnouncementsRead({}, {}), { ok: true, marked: 0 });
    assert.equal(log.length, 0);
  });
});

describe('bildirim özeti', () => {
  it('tek hafif sorgu (CTE): okunmamış, okunmamış acil, en son yayın kimliği + zamanı, sunucu saati', async () => {
    handlers.push([/^WITH mine AS \(/, () => ok([{ unread: 3, unread_urgent: 1, latest_id: '12', latest_published_at: new Date('2026-10-16T08:00:00.000Z'), server_time: new Date('2026-10-16T09:00:00.000Z') }])]);
    const summary = await getNotificationSummary(user);
    assert.equal(log.length, 1, 'tek sorgu');
    assert.deepEqual(log[0].params, [20004]);
    assert.match(log[0].sql, /ORDER BY published_at DESC, id DESC LIMIT 1/);
    assert.deepEqual(summary, {
      unread_announcements: 3,
      unread_urgent: 1,
      latest_announcement_id: 12,
      latest_published_at: '2026-10-16T08:00:00.000Z',
      server_time: '2026-10-16T09:00:00.000Z',
    });
  });

  it('alıcısı olmayan hesap: 0 / 0 / null; kullanıcı kodu yoksa DB sorgusu yok', async () => {
    handlers.push([/^WITH mine AS/, () => ok([{ unread: 0, unread_urgent: 0, latest_id: null, latest_published_at: null, server_time: new Date('2026-10-16T09:00:00.000Z') }])]);
    const summary = await getNotificationSummary(user);
    assert.equal(summary.unread_announcements, 0);
    assert.equal(summary.latest_announcement_id, null);
    assert.equal(summary.latest_published_at, null);
    log.length = 0;
    assert.equal((await getNotificationSummary({})).unread_announcements, 0);
    assert.equal(log.length, 0);
  });
});

describe('bildirim tercihleri', () => {
  const PREF_SELECT = /^SELECT email_announcements, push_announcements FROM notification_preferences WHERE user_code = \$1$/;
  const UPSERT = /^INSERT INTO notification_preferences \(user_code, email_announcements\) VALUES \(\$1, \$2\) ON CONFLICT \(user_code\) DO UPDATE SET email_announcements = EXCLUDED\.email_announcements, updated_at = NOW\(\) RETURNING email_announcements, push_announcements$/;
  const SUPPRESSED = /^SELECT EXISTS \( SELECT 1 FROM \( SELECT translate\(btrim\(u\.email\), /;
  const DELETE_OWN = /^DELETE FROM announcement_email_suppressions s USING users u WHERE u\.user_code = \$1 AND /;
  const suppressedAnswer = (value) => [SUPPRESSED, () => ok([{ suppressed: value }])];

  it('kayıt yoksa varsayılan { email:true, push:true, push_available:false, email_suppressed:false }', async () => {
    handlers.push([PREF_SELECT, () => ok()], suppressedAnswer(false));
    assert.deepEqual(await getNotificationPreferences(user), { email_announcements: true, push_announcements: true, push_available: false, email_suppressed: false });
    assert.deepEqual(log[0].params, [20004]);
  });

  it('F2 GET ETKİN değer: saklanan tercih VE çağıranın kendi adreslerinden hiçbiri bastırılmamış; bastırılmışsa email_announcements false + email_suppressed true (saklanan değer true kalsa da)', async () => {
    handlers.push([PREF_SELECT, () => ok([{ email_announcements: true, push_announcements: true }])], suppressedAnswer(true));
    assert.deepEqual(await getNotificationPreferences(user), { email_announcements: false, push_announcements: true, push_available: false, email_suppressed: true });
    handlers.length = 0;
    handlers.push([PREF_SELECT, () => ok([{ email_announcements: false, push_announcements: true }])], suppressedAnswer(false));
    assert.deepEqual(await getNotificationPreferences(user), { email_announcements: false, push_announcements: true, push_available: false, email_suppressed: false }, 'saklanan false -> etkin false, bastırma yok');
    handlers.length = 0;
    handlers.push([PREF_SELECT, () => ok([{ email_announcements: true, push_announcements: true }])], suppressedAnswer(false));
    assert.equal((await getNotificationPreferences(user)).email_announcements, true);
  });

  it('F2 bastırma sorgusu yalnız ÇAĞIRANIN adreslerine bakar (hesap e-postası + kişi iletişim e-postası), kanonik özet, güncel + eski tuzlar; dahili adres atlanır', async () => {
    handlers.push([PREF_SELECT, () => ok()], suppressedAnswer(false));
    await getNotificationPreferences(user);
    const query = log.find((q) => SUPPRESSED.test(q.sql));
    assert.deepEqual(query.params[0], 20004);
    assert.deepEqual(query.params[1], emailHashSalts());
    assert.match(query.sql, /FROM users u WHERE u\.user_code = \$1 AND u\.email IS NOT NULL AND u\.email NOT LIKE '%@ahbu\.local' UNION ALL SELECT translate\(btrim\(/);
    assert.match(query.sql, /FROM site_people sp LEFT JOIN users u ON u\.user_code = sp\.user_code .* WHERE sp\.user_code = \$1 \) x/);
    assert.match(query.sql, /WHERE x\.address IS NOT NULL AND x\.address LIKE '%@%' AND x\.address NOT LIKE '%@ahbu\.local' AND EXISTS \(SELECT 1 FROM unnest\(\$2::TEXT\[\]\) AS salts\(salt\) INNER JOIN announcement_email_suppressions sup/);
    assert.doesNotMatch(query.sql, /DELETE|UPDATE|INSERT/);
  });

  it('PUT false: yalnız tercihi yazar (UPSERT); push_* ve bilinmeyen anahtarlar YOKSAYILIR; bastırma listesine DOKUNMAZ; yanıt etkin değer + email_suppressed', async () => {
    handlers.push([UPSERT, () => ok([{ email_announcements: false, push_announcements: true }])], suppressedAnswer(false));
    const result = await setNotificationPreferences(user, { email_announcements: false, push_announcements: false, baska: 1 });
    assert.deepEqual(log[0].params, [20004, false]);
    assert.deepEqual(result, { email_announcements: false, push_announcements: true, push_available: false, email_suppressed: false });
    assert.equal(log.some((q) => DELETE_OWN.test(q.sql)), false);
  });

  it('F1 PUT true YALNIZ doğrulanmış GERÇEK hesap e-postasının bastırmasını siler: tek DELETE, users.email_verified, dahili @ahbu.local değil, kanonik özet güncel + eski tuzlarla; iletişim e-postası kaynakları (resident_email, site_people.email) silme kaynağı DEĞİL', async () => {
    handlers.push([UPSERT, () => ok([{ email_announcements: true, push_announcements: true }])], [DELETE_OWN, () => ok([], 1)], suppressedAnswer(false));
    const result = await setNotificationPreferences(user, { email_announcements: true });
    assert.deepEqual(result, { email_announcements: true, push_announcements: true, push_available: false, email_suppressed: false });
    const removal = log.find((q) => DELETE_OWN.test(q.sql));
    assert.deepEqual(removal.params, [20004, emailHashSalts()], 'yalnız çağıranın kendi kullanıcı kodu ve tuzlar');
    assert.match(removal.sql, /u\.email IS NOT NULL AND u\.email_verified = TRUE AND u\.email NOT LIKE '%@ahbu\.local' AND s\.email_hash IN \( SELECT encode\(sha256\(convert_to\(t\.salt::TEXT \|\| ':' \|\| \(CASE WHEN split_part\(translate\(btrim\(u\.email\), /);
    assert.doesNotMatch(removal.sql, /resident_email|site_people|apartments|CONTACT/, 'iletişim e-postası kaynakları silme kaynağı değil');
    assert.equal(log.filter((q) => /^DELETE/.test(q.sql)).length, 1);
    // sıra: tercih -> silme -> etkin değer
    assert.ok(log.findIndex((q) => UPSERT.test(q.sql)) < log.findIndex((q) => DELETE_OWN.test(q.sql)) && log.findIndex((q) => DELETE_OWN.test(q.sql)) < log.findIndex((q) => SUPPRESSED.test(q.sql)));
  });

  it('F2 PUT true sonrası iletişim adresi hâlâ bastırılmışsa (dahili hesap; uygulamadan açılamaz) yanıt email_suppressed:true ve ETKİN email_announcements:false', async () => {
    handlers.push([UPSERT, () => ok([{ email_announcements: true, push_announcements: true }])], [DELETE_OWN, () => ok([], 0)], suppressedAnswer(true));
    const result = await setNotificationPreferences(user, { email_announcements: true });
    assert.deepEqual(result, { email_announcements: false, push_announcements: true, push_available: false, email_suppressed: true });
  });

  it('PUT: boolean olmayan / eksik değer -> 400 INVALID_BODY (alan adı yok); kullanıcı yoksa 401', async () => {
    for (const body of [{ email_announcements: 'hayır' }, {}, null, { email_announcements: 0 }]) {
      await assert.rejects(() => setNotificationPreferences(user, body), (e) => e.code === 'INVALID_BODY' && !/email_announcements|_/.test(e.message), JSON.stringify(body));
    }
    await assert.rejects(() => setNotificationPreferences({}, { email_announcements: true }), (e) => e.statusCode === 401);
    assert.equal(log.length, 0);
  });

  it('kullanıcı kodu yoksa GET varsayılan döner ve DB sorgusu yok', async () => {
    assert.deepEqual(await getNotificationPreferences({}), { email_announcements: true, push_announcements: true, push_available: false, email_suppressed: false });
    assert.equal(log.length, 0);
  });
});
