// Duyuru ve Bildirim (Faz 3a) ortak doğrulayıcılar ve eşleyiciler (DB'siz): başlık/metin temizliği, hedef, zamanlama, sorgu
// parametreleri, kurul yanıtı temizliği.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import {
  BODY_HEAD_CHARS,
  BODY_MAX,
  BOARD_SMALL_TARGET_MIN,
  DUPLICATE_WINDOW_SECONDS,
  EMAIL_CLAIM_STALE_MINUTES,
  EMAIL_RETRY_DELAYS_SECONDS,
  MAX_EMAIL_ATTEMPTS,
  MAX_PUBLISH_ATTEMPTS,
  PREVIEW_MAX,
  TITLE_MAX,
  announcementLimits,
  attachLiveCount,
  dailyLimitReached,
  duplicateAnnouncement,
  hourlyLimitReached,
  idArray,
  istanbulDayRange,
  mapInboxRow,
  mapSummaryRow,
  normalizeBody,
  normalizeImportance,
  normalizeSendEmail,
  normalizeTitle,
  parseCreateInput,
  parseInboxQuery,
  parseListQuery,
  parsePatchInput,
  parsePublishMode,
  parseRecipientsQuery,
  parseScheduleInput,
  parseTargetInput,
  previewOf,
  redactForBoard,
} from '../src/modules/announcement_common.js';

const NOW = new Date('2026-10-16T10:00:00.000Z');
const rejects = (fn, code, status) => {
  assert.throws(fn, (error) => error.code === code && error.statusCode === status, `${code}/${status} bekleniyordu`);
};
const message = (fn) => {
  try {
    fn();
  } catch (error) {
    return error.message;
  }
  return null;
};

describe('duyuru: başlık ve metin temizliği', () => {
  it('başlık tek satır olur (CRLF/sekme/satır ayırıcıları boşluk), boşluklar tekleşir, kırpılır', () => {
    assert.equal(normalizeTitle('  Su\r\nkesintisi\t\tyarın  '), 'Su kesintisi yarın');
    assert.equal(normalizeTitle(`A${String.fromCodePoint(0x2028)}B${String.fromCodePoint(0x2029)}C`), 'A B C');
  });

  it('başlık: kontrol karakterleri ve yön denetim / sıfır genişlik karakterleri atılır; emoji birleştiricisi (ZWJ) korunur', () => {
    const bidi = String.fromCodePoint(0x202e);
    const zeroWidth = String.fromCodePoint(0x200b);
    const joiner = String.fromCodePoint(0x200d);
    assert.equal(normalizeTitle(`Ba${bidi}s${zeroWidth}lik${String.fromCharCode(7)}`), 'Baslik');
    assert.equal(normalizeTitle(`a${joiner}b`), `a${joiner}b`);
  });

  it('başlık: boş/sayı -> 400 INVALID_BODY; 120 karakter sınır; Türkçe etiketli mesaj (alan adı yok)', () => {
    rejects(() => normalizeTitle(''), 'INVALID_BODY', 400);
    rejects(() => normalizeTitle('   '), 'INVALID_BODY', 400);
    rejects(() => normalizeTitle(5), 'INVALID_BODY', 400);
    rejects(() => normalizeTitle('x'.repeat(TITLE_MAX + 1)), 'INVALID_BODY', 400);
    assert.equal(normalizeTitle('x'.repeat(TITLE_MAX)).length, TITLE_MAX);
    assert.match(message(() => normalizeTitle('')), /Başlık/);
    assert.doesNotMatch(message(() => normalizeTitle('x'.repeat(200))), /title|_/);
  });

  it('başlık uzunluğu kod noktası sayar (emoji tek karakter)', () => {
    assert.equal(Array.from(normalizeTitle('😀'.repeat(TITLE_MAX))).length, TITLE_MAX);
    rejects(() => normalizeTitle('😀'.repeat(TITLE_MAX + 1)), 'INVALID_BODY', 400);
  });

  it('metin: satır sonları LF, satır sonu boşlukları atılır, 4+ boş satır 2 boş satıra iner, kırpılır; HTML düz metin olarak kalır', () => {
    assert.equal(normalizeBody('  Satır 1  \r\nSatır 2\r\n\r\n\r\n\r\n\r\nSon  '), 'Satır 1\nSatır 2\n\n\nSon');
    assert.equal(normalizeBody('<b>kalın</b> & <script>x</script>'), '<b>kalın</b> & <script>x</script>');
  });

  it('metin: kontrol ve yön karakterleri atılır; 1-5000 karakter; boş/sayı reddedilir', () => {
    const bidi = String.fromCodePoint(0x202e);
    assert.equal(normalizeBody(`a${bidi}b${String.fromCharCode(0)}c${String.fromCharCode(7)}d`), 'abcd');
    assert.equal(normalizeBody('x'.repeat(BODY_MAX)).length, BODY_MAX);
    rejects(() => normalizeBody('x'.repeat(BODY_MAX + 1)), 'INVALID_BODY', 400);
    rejects(() => normalizeBody('   \n  '), 'INVALID_BODY', 400);
    rejects(() => normalizeBody(null), 'INVALID_BODY', 400);
    assert.match(message(() => normalizeBody('')), /Duyuru metni/);
  });

  it('önem ve e-posta seçeneği doğrulanır', () => {
    assert.equal(normalizeImportance('urgent'), 'urgent');
    rejects(() => normalizeImportance('kritik'), 'INVALID_BODY', 400);
    rejects(() => normalizeImportance(undefined), 'INVALID_BODY', 400);
    assert.equal(normalizeSendEmail(true), true);
    rejects(() => normalizeSendEmail('evet'), 'INVALID_BODY', 400);
    assert.doesNotMatch(message(() => normalizeSendEmail('evet')), /send_email|_/);
  });

  it('yayın türü: yok -> draft (yanlışlıkla yayınlamamak için güvenli varsayılan); geçersiz -> 400', () => {
    assert.equal(parsePublishMode(undefined), 'draft');
    assert.equal(parsePublishMode('now'), 'now');
    assert.equal(parsePublishMode('schedule'), 'schedule');
    rejects(() => parsePublishMode('yarın'), 'INVALID_BODY', 400);
  });
});

describe('duyuru: hedef', () => {
  it('site: kimlik listeleri yoksayılır', () => {
    assert.deepEqual(parseTargetInput({ type: 'site', block_ids: [1], apartment_ids: [2] }), { type: 'site', blockIds: [], apartmentIds: [] });
  });

  it('blocks / apartments: kimlikler tekilleştirilir, sayıya çevrilir, diğer liste boşaltılır', () => {
    assert.deepEqual(parseTargetInput({ type: 'blocks', block_ids: [3, '4', 3], apartment_ids: [9] }), { type: 'blocks', blockIds: [3, 4], apartmentIds: [] });
    assert.deepEqual(parseTargetInput({ type: 'apartments', apartment_ids: [7, 7, 8] }), { type: 'apartments', blockIds: [], apartmentIds: [7, 8] });
  });

  it('kimlikler ARTAN sırada saklanır: aynı küme her zaman aynı dizi (çift POST koruması dizi eşitliğiyle karşılaştırır)', () => {
    assert.deepEqual(parseTargetInput({ type: 'apartments', apartment_ids: [8, 7, 10, 9] }).apartmentIds, [7, 8, 9, 10]);
    assert.deepEqual(parseTargetInput({ type: 'blocks', block_ids: ['12', 3, 12] }).blockIds, [3, 12]);
    assert.deepEqual(
      parseTargetInput({ type: 'apartments', apartment_ids: [3, 1, 2] }),
      parseTargetInput({ type: 'apartments', apartment_ids: [2, 3, 1] }),
    );
  });

  it('boş / geçersiz / çok kimlik -> 400 INVALID_TARGET; bilinmeyen tür veya biçim -> 400 INVALID_BODY', () => {
    rejects(() => parseTargetInput({ type: 'blocks', block_ids: [] }), 'INVALID_TARGET', 400);
    rejects(() => parseTargetInput({ type: 'blocks' }), 'INVALID_TARGET', 400);
    rejects(() => parseTargetInput({ type: 'apartments', apartment_ids: [0] }), 'INVALID_TARGET', 400);
    rejects(() => parseTargetInput({ type: 'apartments', apartment_ids: ['x'] }), 'INVALID_TARGET', 400);
    rejects(() => parseTargetInput({ type: 'apartments', apartment_ids: Array.from({ length: 501 }, (_, i) => i + 1) }), 'INVALID_TARGET', 400);
    assert.equal(parseTargetInput({ type: 'apartments', apartment_ids: Array.from({ length: 500 }, (_, i) => i + 1) }).apartmentIds.length, 500);
    rejects(() => parseTargetInput({ type: 'herkes' }), 'INVALID_BODY', 400);
    rejects(() => parseTargetInput(null), 'INVALID_BODY', 400);
    rejects(() => parseTargetInput([]), 'INVALID_BODY', 400);
    assert.doesNotMatch(message(() => parseTargetInput({ type: 'blocks', block_ids: [] })), /block_ids|_/);
  });
});

describe('duyuru: zamanlama (ISO 8601, >= 1 dk, <= 1 yıl)', () => {
  it('geçerli zaman: mutlak an (Z / ofset) ve saat dilimsiz değer Türkiye saati (+03:00) sayılır', () => {
    assert.equal(parseScheduleInput('2026-10-16T10:05:00Z', NOW).toISOString(), '2026-10-16T10:05:00.000Z');
    assert.equal(parseScheduleInput('2026-10-16T13:05:00+03:00', NOW).toISOString(), '2026-10-16T10:05:00.000Z');
    assert.equal(parseScheduleInput('2026-10-16T13:05:00+0300', NOW).toISOString(), '2026-10-16T10:05:00.000Z');
    assert.equal(parseScheduleInput('2026-10-16T13:05', NOW).toISOString(), '2026-10-16T10:05:00.000Z');
    assert.equal(parseScheduleInput('2026-10-16T13:05:30.5', NOW).toISOString(), '2026-10-16T10:05:30.500Z');
  });

  it('sınırlar: tam 1 dakika kabul, 59 sn red; 1 yıl kabul, 1 yıl + 1 sn red', () => {
    assert.doesNotThrow(() => parseScheduleInput('2026-10-16T10:01:00Z', NOW));
    rejects(() => parseScheduleInput('2026-10-16T10:00:59Z', NOW), 'INVALID_SCHEDULE', 400);
    rejects(() => parseScheduleInput('2026-10-16T09:00:00Z', NOW), 'INVALID_SCHEDULE', 400);
    assert.doesNotThrow(() => parseScheduleInput('2027-10-16T10:00:00Z', NOW));
    rejects(() => parseScheduleInput('2027-10-16T10:00:01Z', NOW), 'INVALID_SCHEDULE', 400);
  });

  it('ISO olmayan / olmayan tarih / sayı -> 400 INVALID_SCHEDULE', () => {
    for (const bad of ['yarın 10:00', '2026-02-30T10:00:00Z', '2026-13-01T10:00:00Z', '2026-10-16T25:00:00Z', '2026-10-16 10:05', '', 12345, null, undefined, {}]) {
      rejects(() => parseScheduleInput(bad, NOW), 'INVALID_SCHEDULE', 400);
    }
  });
});

describe('duyuru: oluşturma / düzenleme gövdesi', () => {
  const base = { title: ' Başlık ', body: 'Metin', target: { type: 'site' } };

  it('varsayılanlar: publish draft, importance normal, send_email false, publish_at yok sayılır (draft)', () => {
    const input = parseCreateInput({ ...base, publish_at: '2026-10-16T11:00:00Z' }, NOW);
    assert.deepEqual(input, {
      title: 'Başlık',
      body: 'Metin',
      importance: 'normal',
      target: { type: 'site', blockIds: [], apartmentIds: [] },
      sendEmail: false,
      publish: 'draft',
      publishAt: null,
    });
  });

  it('schedule: publish_at zorunlu ve doğrulanır; now: publish_at yoksayılır', () => {
    rejects(() => parseCreateInput({ ...base, publish: 'schedule' }, NOW), 'INVALID_SCHEDULE', 400);
    const scheduled = parseCreateInput({ ...base, publish: 'schedule', publish_at: '2026-10-16T11:00:00Z' }, NOW);
    assert.equal(scheduled.publishAt.toISOString(), '2026-10-16T11:00:00.000Z');
    assert.equal(parseCreateInput({ ...base, publish: 'now', publish_at: 'saçma' }, NOW).publishAt, null);
  });

  it('alan hataları 400 INVALID_BODY ve mesajda snake_case alan adı yoktur', () => {
    for (const patch of [{ title: '' }, { body: '' }, { importance: 'x' }, { send_email: 'e' }, { publish: 'x' }, { target: null }]) {
      const text = message(() => parseCreateInput({ ...base, ...patch }, NOW));
      assert.ok(text, JSON.stringify(patch));
      assert.doesNotMatch(text, /title|body|importance|send_email|publish|target|_/, text);
    }
  });

  it('PATCH: yalnız gönderilen alanlar; boş gövde 400; publish_at null zamanlamayı kaldırır', () => {
    rejects(() => parsePatchInput({}, NOW), 'INVALID_BODY', 400);
    rejects(() => parsePatchInput(null, NOW), 'INVALID_BODY', 400);
    const patch = parsePatchInput({ title: ' Yeni ', publish_at: null, send_email: true }, NOW);
    assert.equal(patch.title, 'Yeni');
    assert.equal(patch.publishAtProvided, true);
    assert.equal(patch.publishAt, null);
    assert.equal(patch.sendEmail, true);
    assert.equal(patch.body, undefined);
    assert.deepEqual(patch.keys.sort(), ['publish_at', 'send_email', 'title']);
    assert.equal(parsePatchInput({ publish_at: '2026-10-16T11:00:00Z' }, NOW).publishAt.toISOString(), '2026-10-16T11:00:00.000Z');
    rejects(() => parsePatchInput({ publish_at: '2026-10-16T10:00:10Z' }, NOW), 'INVALID_SCHEDULE', 400);
    assert.equal(parsePatchInput({ unknown: 1, title: 'x' }, NOW).keys.join(), 'title');
  });
});

describe('duyuru: sorgu parametreleri', () => {
  it('liste: varsayılan all/30/0; status, q, limit (1-100), offset', () => {
    assert.deepEqual(parseListQuery({}), { status: 'all', q: null, limit: 30, offset: 0 });
    assert.deepEqual(parseListQuery({ status: 'published', q: ' su ', limit: '500', offset: '10' }), { status: 'published', q: 'su', limit: 100, offset: 10 });
    assert.equal(parseListQuery({ limit: '0' }).limit, 1);
    rejects(() => parseListQuery({ status: 'zz' }), 'INVALID_QUERY', 400);
    rejects(() => parseListQuery({ offset: '-1' }), 'INVALID_QUERY', 400);
    assert.equal(parseListQuery({ q: 'x'.repeat(300) }).q.length, 100);
  });

  it('alıcılar: read all|true|false, limit 50 (en çok 200)', () => {
    assert.deepEqual(parseRecipientsQuery({}), { read: 'all', q: null, limit: 50, offset: 0 });
    assert.equal(parseRecipientsQuery({ read: 'false', limit: '999' }).limit, 200);
    rejects(() => parseRecipientsQuery({ read: 'belki' }), 'INVALID_QUERY', 400);
  });

  it('gelen kutusu: limit 30 (en çok 100), before_id ve site_code sayı olmalı', () => {
    assert.deepEqual(parseInboxQuery({}), { limit: 30, beforeId: null, siteCode: null });
    assert.deepEqual(parseInboxQuery({ limit: '5', before_id: '42', site_code: '1000000001' }), { limit: 5, beforeId: 42, siteCode: 1000000001 });
    rejects(() => parseInboxQuery({ before_id: 'abc' }), 'INVALID_QUERY', 400);
    rejects(() => parseInboxQuery({ site_code: '-1' }), 'INVALID_QUERY', 400);
  });
});

describe('duyuru: yanıt eşleyicileri', () => {
  it('önizleme: boşluklar tekleşir; 160 karakteri aşarsa 159 + "…"; kısa metin aynen', () => {
    assert.equal(previewOf('Merhaba\n\n  dünya  '), 'Merhaba dünya');
    const long = previewOf('x'.repeat(500));
    assert.equal(Array.from(long).length, PREVIEW_MAX);
    assert.ok(long.endsWith('…'));
    assert.equal(previewOf('x'.repeat(PREVIEW_MAX)), 'x'.repeat(PREVIEW_MAX));
    assert.equal(previewOf('kısa', { truncated: true }), 'kısa…');
    assert.equal(previewOf(null), '');
  });

  it('mapSummaryRow: sözleşme alanları ve türleri; id/sayılar Number, tarihler ISO, created_by_name', () => {
    const row = {
      id: '12',
      title: 'T',
      body_head: 'Gövde',
      body_length: '5',
      importance: 'urgent',
      status: 'published',
      target_type: 'blocks',
      publish_at: null,
      published_at: new Date('2026-10-16T08:00:00.000Z'),
      edited_at: null,
      send_email: true,
      recipient_count: 3,
      read_count: '1',
      created_at: new Date('2026-10-15T08:00:00.000Z'),
      created_by_name: 'Ayşe',
    };
    assert.deepEqual(mapSummaryRow(row), {
      id: 12,
      title: 'T',
      body_preview: 'Gövde',
      importance: 'urgent',
      status: 'published',
      target_type: 'blocks',
      publish_at: null,
      published_at: '2026-10-16T08:00:00.000Z',
      edited_at: null,
      send_email: true,
      recipient_count: 3,
      read_count: 1,
      created_at: '2026-10-15T08:00:00.000Z',
      created_by_name: 'Ayşe',
    });
    assert.equal(mapSummaryRow({ ...row, body_length: String(BODY_HEAD_CHARS + 1), body_head: 'Kısa' }).body_preview, 'Kısa…');
    assert.ok(!('created_by' in mapSummaryRow({ ...row, created_by: 5 })), 'ham kullanıcı kodu yanıta girmez');
  });

  it('mapInboxRow: is_read read_at\'ten türetilir', () => {
    const row = { id: '1', site_code: '1000000001', site_name: 'Gül', title: 'T', body: 'B', importance: 'normal', published_at: new Date('2026-10-16T08:00:00.000Z'), edited_at: null, read_at: null };
    assert.equal(mapInboxRow(row).is_read, false);
    assert.equal(mapInboxRow({ ...row, read_at: new Date() }).is_read, true);
    assert.equal(mapInboxRow(row).site_code, 1000000001);
  });

  it('idArray: pg BIGINT[] (metin dizisi) sayı dizisine çevrilir', () => {
    assert.deepEqual(idArray(['1', '22']), [1, 22]);
    assert.deepEqual(idArray(null), []);
  });

  it('redactForBoard: kullanıcı kodu alanları ÇIKARILIR, created_by_name null olur (iç içe dahil); diğer alanlar korunur; girdi değişmez', () => {
    const input = {
      items: [{ id: 1, created_by: 5, created_by_name: 'Yönetici', title: 'T', nested: { user_code: 9, actor_user_code: 3, created_by_name: 'X' } }],
      total: 1,
    };
    const snapshot = JSON.stringify(input);
    const out = redactForBoard(input);
    assert.deepEqual(out, { items: [{ id: 1, created_by_name: null, title: 'T', nested: { created_by_name: null } }], total: 1 });
    assert.equal(JSON.stringify(input), snapshot);
  });

  it('redactForBoard (D6): 1-4 alıcılı hedefte okunma / okunmamış / e-posta sayıları NULL (anahtarlar kalır), recipients sayısı ve büyük hedefler aynen', () => {
    const emailStats = { requested: 2, sent: 1, failed: 0, no_address: 1, skipped_pref: 0, capped: 0, duplicate: 0, pending: 0 };
    const detail = (count) => ({ id: 1, recipient_count: count, read_count: 1, stats: { recipients: count, read: 1, unread: count - 1, email: { ...emailStats } } });
    const small = redactForBoard(detail(2));
    assert.deepEqual(small, {
      id: 1,
      recipient_count: 2,
      read_count: null,
      stats: { recipients: 2, read: null, unread: null, email: Object.fromEntries(Object.keys(emailStats).map((key) => [key, null])) },
    });
    // liste satırı (read_count)
    assert.deepEqual(redactForBoard({ items: [{ id: 3, recipient_count: 4, read_count: 2 }, { id: 4, recipient_count: 5, read_count: 2 }] }), {
      items: [{ id: 3, recipient_count: 4, read_count: null }, { id: 4, recipient_count: 5, read_count: 2 }],
    });
    const big = detail(BOARD_SMALL_TARGET_MIN);
    assert.deepEqual(redactForBoard(big), big);
    // alıcı yok (0): kişisel veri yok, sayılar aynen
    const none = detail(0);
    assert.deepEqual(redactForBoard({ ...none, stats: { ...none.stats, read: 0, unread: 0 } }).stats.read, 0);
    assert.equal(BOARD_SMALL_TARGET_MIN, 5);
  });
});

describe('E7 kurul temizliği: canlı alıcı sayısı', () => {
  const emailStats = { requested: 4, sent: 3, failed: 0, no_address: 1, skipped_pref: 0, capped: 0, duplicate: 0, pending: 0 };
  const detail = (stored, live) =>
    attachLiveCount({ id: 1, recipient_count: stored, read_count: 2, stats: { recipients: live, read: 2, unread: live - 2, email: { ...emailStats } } }, live);

  it('küçük hedef kararı min(yayın anı sayısı, canlı satır sayısı) ile verilir: 6 alıcı yayınlandı, kişiler silinip 3 kaldı -> kurul için NULL', () => {
    const redacted = redactForBoard(detail(6, 3));
    assert.equal(redacted.read_count, null);
    assert.equal(redacted.stats.read, null);
    assert.equal(redacted.stats.unread, null);
    assert.ok(Object.values(redacted.stats.email).every((value) => value === null));
    assert.equal(redacted.recipient_count, 6, 'yayın anındaki sayı aynen');
    assert.equal(redacted.stats.recipients, 3);
  });

  it('canlı sayı 5 ve üstüyse (yayın anı da) görünür; canlı 0 ise (kişisel veri kalmadı) sayılar olduğu gibi (null DEĞİL); canlı bilinmiyorsa yayın anı sayısı kullanılır', () => {
    const big = redactForBoard(detail(6, 5));
    assert.equal(big.read_count, 2);
    assert.equal(big.stats.read, 2);
    const none = redactForBoard(attachLiveCount({ id: 1, recipient_count: 3, read_count: 0, stats: { recipients: 0, read: 0, unread: 0, email: { ...emailStats } } }, 0));
    assert.equal(none.stats.read, 0);
    assert.equal(none.read_count, 0);
    const unknown = redactForBoard({ id: 1, recipient_count: 2, read_count: 1, stats: { recipients: 2, read: 1, unread: 1, email: { ...emailStats } } });
    assert.equal(unknown.read_count, null);
    assert.equal(unknown.stats.read, null);
    const smallStoredBigLive = redactForBoard(detail(3, 9));
    assert.equal(smallStoredBigLive.read_count, null, 'yayın anında küçükse canlı büyük görünse de gizli');
  });

  it('canlı sayı yanıta GİRMEZ: numaralanamaz özelliktir (JSON, Object.keys, spread, redactForBoard çıktısında yok); liste satırlarında da', () => {
    const entry = detail(6, 3);
    assert.equal(entry.live_recipient_count, 3);
    assert.equal(JSON.stringify(entry).includes('live_recipient_count'), false);
    assert.equal(Object.keys(entry).includes('live_recipient_count'), false);
    assert.equal('live_recipient_count' in { ...entry }, false);
    assert.equal('live_recipient_count' in redactForBoard(entry), false);
    const row = mapSummaryRow({ id: '5', title: 'T', body_head: 'B', body_length: '1', importance: 'normal', status: 'published', target_type: 'site', send_email: false, recipient_count: 6, read_count: 1, live_count: 3, created_at: new Date() });
    assert.equal(row.live_recipient_count, 3);
    assert.equal(JSON.stringify(row).includes('live_'), false);
    assert.equal(redactForBoard({ items: [row] }).items[0].read_count, null);
    assert.equal(attachLiveCount({}, undefined).live_recipient_count, undefined);
    assert.equal(attachLiveCount({}, null).live_recipient_count, undefined);
  });
});

describe('duyuru: kötüye kullanım sınırları ve İstanbul günü', () => {
  it('announcementLimits: varsayılanlar 30 / 3 / 10 / 3; ortamdan ayarlanır; geçersiz ya da < 1 değer varsayılana döner', () => {
    assert.deepEqual(announcementLimits({}), { siteDailyTotal: 30, siteDailyUrgentEmail: 3, managerHourlyEmail: 10, perAddressDaily: 3 });
    assert.deepEqual(
      announcementLimits({
        ANNOUNCEMENT_MAX_PER_DAY_PER_SITE: '5',
        ANNOUNCEMENT_URGENT_EMAIL_MAX_PER_DAY_PER_SITE: '2',
        ANNOUNCEMENT_EMAIL_PUBLISH_MAX_PER_HOUR_PER_USER: '7',
        ANNOUNCEMENT_EMAIL_MAX_PER_DAY_PER_ADDRESS: '1',
      }),
      { siteDailyTotal: 5, siteDailyUrgentEmail: 2, managerHourlyEmail: 7, perAddressDaily: 1 },
    );
    for (const bad of ['0', '-4', 'abc', '1.5', '', '  ', 'Infinity']) {
      assert.deepEqual(announcementLimits({ ANNOUNCEMENT_MAX_PER_DAY_PER_SITE: bad, ANNOUNCEMENT_EMAIL_MAX_PER_DAY_PER_ADDRESS: bad }), {
        siteDailyTotal: 30,
        siteDailyUrgentEmail: 3,
        managerHourlyEmail: 10,
        perAddressDaily: 3,
      }, `değer ${JSON.stringify(bad)}`);
    }
  });

  it('istanbulDayRange: gün UTC+3 gece yarısında başlar ve biter ([başlangıç, bitiş) 24 saat); 20:59:59.999Z önceki, 21:00:00Z yeni gün', () => {
    const before = istanbulDayRange(new Date('2026-10-16T20:59:59.999Z'));
    const after = istanbulDayRange(new Date('2026-10-16T21:00:00.000Z'));
    assert.equal(before.start.toISOString(), '2026-10-15T21:00:00.000Z');
    assert.equal(before.end.toISOString(), '2026-10-16T21:00:00.000Z');
    assert.equal(after.start.toISOString(), '2026-10-16T21:00:00.000Z');
    assert.equal(before.end.getTime(), after.start.getTime());
    assert.equal(after.end.getTime() - after.start.getTime(), 24 * 60 * 60 * 1000);
    const noon = istanbulDayRange(new Date('2026-10-16T09:00:00.000Z'));
    assert.equal(noon.start.toISOString(), '2026-10-15T21:00:00.000Z');
    // yıl başı: 31 Aralık 23:59:59 İstanbul = 20:59:59Z aynı gün, 1 Ocak 00:00 İstanbul = 21:00:00Z
    assert.equal(istanbulDayRange(new Date('2026-12-31T21:00:00.000Z')).start.toISOString(), '2026-12-31T21:00:00.000Z');
  });

  it('yeni hata kodları: ANNOUNCEMENT_DAILY_LIMIT / ANNOUNCEMENT_HOURLY_LIMIT / DUPLICATE_ANNOUNCEMENT -> 409, Türkçe mesaj (alan adı yok)', () => {
    const daily = dailyLimitReached();
    assert.equal(daily.statusCode, 409);
    assert.equal(daily.code, 'ANNOUNCEMENT_DAILY_LIMIT');
    assert.match(daily.message, /günlük/);
    assert.equal(dailyLimitReached('Özel mesaj.').message, 'Özel mesaj.');
    const hourly = hourlyLimitReached();
    assert.equal(hourly.statusCode, 409);
    assert.equal(hourly.code, 'ANNOUNCEMENT_HOURLY_LIMIT');
    assert.match(hourly.message, /saat/);
    const duplicate = duplicateAnnouncement();
    assert.equal(duplicate.statusCode, 409);
    assert.equal(duplicate.code, 'DUPLICATE_ANNOUNCEMENT');
    assert.match(duplicate.message, /az önce/);
    for (const error of [daily, hourly, duplicate]) {
      assert.doesNotMatch(error.message, /[a-z]+_[a-z_]+/, error.message);
    }
  });

  it('sabitler: çift POST penceresi 60 sn; e-posta denemesi 3, geri çekilme 1/5/20 dk, talep bayatlığı 10 dk; yayın denemesi 10', () => {
    assert.equal(DUPLICATE_WINDOW_SECONDS, 60);
    assert.equal(MAX_EMAIL_ATTEMPTS, 3);
    assert.deepEqual([...EMAIL_RETRY_DELAYS_SECONDS], [60, 300, 1200]);
    assert.equal(EMAIL_RETRY_DELAYS_SECONDS.length, MAX_EMAIL_ATTEMPTS);
    assert.equal(EMAIL_CLAIM_STALE_MINUTES, 10);
    assert.equal(MAX_PUBLISH_ATTEMPTS, 10);
  });
});
