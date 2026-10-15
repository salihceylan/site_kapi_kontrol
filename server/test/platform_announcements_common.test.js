// Duyuru ve Bildirim (Faz 3a) ortak doğrulayıcılar ve eşleyiciler (DB'siz): başlık/metin temizliği, hedef, zamanlama, sorgu
// parametreleri, kurul yanıtı temizliği.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import {
  BODY_HEAD_CHARS,
  BODY_MAX,
  PREVIEW_MAX,
  TITLE_MAX,
  idArray,
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
});
