// Karar Defteri ortak mantık (DB'siz): sabitler, girdi doğrulayıcıları (400 INVALID_FIELD { field }), sorgu ayrıştırıcıları, opak imleç, yanıt eşleyicileri
// (yönetim / sakin görünümü), kaynak düzeyi gizlilik (audit'e başlık / metin yazılmaz).
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  ATTENDEES_MAX,
  BODY_MAX,
  DECISION_BOOK_MODULE,
  LIST_DEFAULT_LIMIT,
  LIST_MAX_LIMIT,
  MAX_BODY_BYTES,
  MAX_DECISIONS_PER_SITE,
  MEETING_TYPES,
  STATUSES,
  TITLE_MAX,
  VISIBILITIES,
  VOTE_RESULTS,
  afterKeySql,
  assertMeetingHeld,
  decisionFinal,
  decisionLimitReached,
  decisionNotFound,
  decodeCursor,
  encodeCursor,
  mapDecision,
  moduleDisabled,
  normalizeMeetingDate,
  numberLabel,
  parseCreateInput,
  parseListQuery,
  parseNumberLabel,
  parsePatchInput,
  parseResidentListQuery,
  sortKeyOf,
} from '../src/modules/decision_book_common.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const src = (name) => readFileSync(path.join(here, '..', 'src', 'modules', name), 'utf8').replace(/\r\n/g, '\n');
const fieldError = (fn, field) => assert.throws(fn, (error) => error.statusCode === 400 && error.code === 'INVALID_FIELD' && error.extra?.field === field);
const queryError = (fn) => assert.throws(fn, (error) => error.statusCode === 400 && error.code === 'INVALID_QUERY');
const NOW = new Date('2026-10-19T09:00:00Z');
const GOOD = { meeting_type: 'genel_kurul', meeting_date: '2026-05-10', title: 'Asansör bakımı', body: 'Asansör bakım firması değiştirilecektir.', vote_result: 'kabul' };

describe('sabitler ve hatalar', () => {
  it('kümeler, sınırlar, modül kodu', () => {
    assert.equal(DECISION_BOOK_MODULE, 'decision_book');
    assert.deepEqual([...MEETING_TYPES], ['yonetim_kurulu', 'genel_kurul', 'denetim_kurulu', 'diger']);
    assert.deepEqual([...VOTE_RESULTS], ['kabul', 'ret', 'ertelendi', 'bilgi']);
    assert.deepEqual([...VISIBILITIES], ['yonetim', 'sakinler']);
    assert.deepEqual([...STATUSES], ['taslak', 'kesin']);
    assert.deepEqual([TITLE_MAX, BODY_MAX, ATTENDEES_MAX, MAX_DECISIONS_PER_SITE], [160, 10000, 2000, 5000]);
    assert.deepEqual([LIST_DEFAULT_LIMIT, LIST_MAX_LIMIT, MAX_BODY_BYTES], [50, 200, 65536]);
  });

  it('hata kodları: 404 DECISION_NOT_FOUND, 409 DECISION_FINAL, 409 DECISION_LIMIT_REACHED { limit }, 403 MODULE_DISABLED { module }', () => {
    assert.deepEqual([decisionNotFound().statusCode, decisionNotFound().code], [404, 'DECISION_NOT_FOUND']);
    assert.deepEqual([decisionFinal().statusCode, decisionFinal().code], [409, 'DECISION_FINAL']);
    assert.deepEqual([decisionLimitReached().statusCode, decisionLimitReached().code, decisionLimitReached().extra], [409, 'DECISION_LIMIT_REACHED', { limit: 5000 }]);
    assert.deepEqual([moduleDisabled().statusCode, moduleDisabled().code, moduleDisabled().extra], [403, 'MODULE_DISABLED', { module: 'decision_book' }]);
  });

  it('kesinleştirme ön koşulu: toplantı tarihi bugünden (İstanbul) sonraysa 409 DECISION_MEETING_IN_FUTURE; bugün ve geçmiş geçer; gün sınırı İstanbul saatiyle', () => {
    const future = (fn) => assert.throws(fn, (error) => error.statusCode === 409 && error.code === 'DECISION_MEETING_IN_FUTURE' && error.message === 'Toplantı tarihi gelmemiş karar kesinleştirilemez.');
    assert.doesNotThrow(() => assertMeetingHeld('2026-10-19', NOW));
    assert.doesNotThrow(() => assertMeetingHeld('2020-01-01', NOW));
    future(() => assertMeetingHeld('2026-10-20', NOW));
    future(() => assertMeetingHeld('2027-10-20', NOW));
    // 2026-10-19T21:30Z = İstanbul 20 Ekim 00:30 -> 20 Ekim artık "bugün"
    assert.doesNotThrow(() => assertMeetingHeld('2026-10-20', new Date('2026-10-19T21:30:00Z')));
    future(() => assertMeetingHeld('2026-10-20', new Date('2026-10-19T20:30:00Z')));
  });
});

describe('POST gövdesi (parseCreateInput)', () => {
  it('zorunlu alanlar + varsayılanlar: visibility yonetim, isteğe bağlılar null, yıl toplantı tarihinden', () => {
    const input = parseCreateInput(GOOD, NOW);
    assert.deepEqual(input, {
      meetingType: 'genel_kurul',
      meetingDate: '2026-05-10',
      title: 'Asansör bakımı',
      body: 'Asansör bakım firması değiştirilecektir.',
      attendees: null,
      voteResult: 'kabul',
      votesFor: null,
      votesAgainst: null,
      votesAbstain: null,
      visibility: 'yonetim',
      supersedesId: null,
      year: 2026,
    });
  });

  it('eksik / hatalı her alan 400 INVALID_FIELD { field } (alan adı gövde anahtarıdır)', () => {
    for (const field of ['meeting_type', 'meeting_date', 'title', 'body', 'vote_result']) {
      const body = { ...GOOD };
      delete body[field];
      fieldError(() => parseCreateInput(body, NOW), field);
    }
    fieldError(() => parseCreateInput({ ...GOOD, meeting_type: 'kurul' }, NOW), 'meeting_type');
    fieldError(() => parseCreateInput({ ...GOOD, vote_result: 'evet' }, NOW), 'vote_result');
    fieldError(() => parseCreateInput({ ...GOOD, visibility: 'herkes' }, NOW), 'visibility');
    fieldError(() => parseCreateInput({ ...GOOD, title: '   ' }, NOW), 'title');
    fieldError(() => parseCreateInput({ ...GOOD, title: 'x'.repeat(161) }, NOW), 'title');
    fieldError(() => parseCreateInput({ ...GOOD, body: 'x'.repeat(10001) }, NOW), 'body');
    fieldError(() => parseCreateInput({ ...GOOD, attendees: 'x'.repeat(2001) }, NOW), 'attendees');
    fieldError(() => parseCreateInput({ ...GOOD, attendees: 5 }, NOW), 'attendees');
    fieldError(() => parseCreateInput({ ...GOOD, votes_for: -1 }, NOW), 'votes_for');
    fieldError(() => parseCreateInput({ ...GOOD, votes_against: 1.5 }, NOW), 'votes_against');
    fieldError(() => parseCreateInput({ ...GOOD, votes_abstain: 100001 }, NOW), 'votes_abstain');
    fieldError(() => parseCreateInput({ ...GOOD, supersedes_id: 'abc' }, NOW), 'supersedes_id');
    fieldError(() => parseCreateInput({ ...GOOD, supersedes_id: 0 }, NOW), 'supersedes_id');
    fieldError(() => parseCreateInput(null, NOW), 'meeting_type');
  });

  it('sınırda geçerli: başlık 160, metin 10000, katılımcılar 2000 (kod noktası), oylar 0 ve "12"; boş katılımcı null', () => {
    const input = parseCreateInput(
      { ...GOOD, title: 'ş'.repeat(160), body: '😀'.repeat(10000), attendees: 'a'.repeat(2000), votes_for: 0, votes_against: '12', votes_abstain: null, visibility: 'sakinler', supersedes_id: '7' },
      NOW,
    );
    assert.equal(Array.from(input.title).length, 160);
    assert.equal(Array.from(input.body).length, 10000);
    assert.deepEqual([input.votesFor, input.votesAgainst, input.votesAbstain, input.visibility, input.supersedesId], [0, 12, null, 'sakinler', 7]);
    assert.equal(parseCreateInput({ ...GOOD, attendees: '  \n ' }, NOW).attendees, null);
  });

  it('metin temizliği: başlık tek satır; metin satır sonlarını korur, görünmez / kontrol karakterleri atılır', () => {
    const input = parseCreateInput({ ...GOOD, title: ' Asansör\n bakımı​ ', body: 'Bir\r\nİki‮\n\n\n\n\nÜç\u0007' }, NOW);
    assert.equal(input.title, 'Asansör bakımı');
    assert.equal(input.body, 'Bir\nİki\n\n\nÜç');
  });

  it('toplantı tarihi: YYYY-AA-GG, gerçek gün, 1950 sonrası, en çok bugün + 366 gün', () => {
    assert.equal(normalizeMeetingDate('2024-02-29', NOW), '2024-02-29');
    assert.equal(normalizeMeetingDate('1950-01-01', NOW), '1950-01-01');
    assert.equal(normalizeMeetingDate('2027-10-20', NOW), '2027-10-20');
    for (const bad of ['2023-02-29', '2026-13-01', '19.10.2026', '2026-1-1', '1949-12-31', '2027-10-21', 20261019, '']) {
      fieldError(() => normalizeMeetingDate(bad, NOW), 'meeting_date');
    }
  });

  it('bilinmeyen alanlar (status, decision_no, site_code ...) YOK SAYILIR: istemci numara / durum yazamaz', () => {
    const input = parseCreateInput({ ...GOOD, status: 'kesin', decision_no: 9, site_code: 5, finalized_at: 'x' }, NOW);
    assert.ok(!('status' in input) && !('decisionNo' in input) && !('siteCode' in input));
  });
});

describe('PATCH gövdesi (parsePatchInput)', () => {
  it('yalnız gönderilen alanlar; boş gövde {} (değişiklik yok); toplantı tarihi değişirse yıl da', () => {
    assert.deepEqual(parsePatchInput({}, NOW), {});
    assert.deepEqual(parsePatchInput(null, NOW), {});
    assert.deepEqual(parsePatchInput({ title: 'Yeni' }, NOW), { title: 'Yeni' });
    assert.deepEqual(parsePatchInput({ meeting_date: '2025-12-31' }, NOW), { meetingDate: '2025-12-31', year: 2025 });
  });

  it('isteğe bağlılar null ile temizlenir; zorunlular null olamaz (visibility dahil)', () => {
    assert.deepEqual(parsePatchInput({ attendees: null, votes_for: null, supersedes_id: null }, NOW), { attendees: null, votesFor: null, supersedesId: null });
    fieldError(() => parsePatchInput({ title: null }, NOW), 'title');
    fieldError(() => parsePatchInput({ body: null }, NOW), 'body');
    fieldError(() => parsePatchInput({ visibility: null }, NOW), 'visibility');
    fieldError(() => parsePatchInput({ meeting_type: null }, NOW), 'meeting_type');
    fieldError(() => parsePatchInput({ vote_result: null }, NOW), 'vote_result');
    fieldError(() => parsePatchInput({ meeting_date: null }, NOW), 'meeting_date');
  });
});

describe('sorgu ayrıştırıcıları ve imleç', () => {
  it('yönetim listesi: varsayılanlar, süzgeçler, limit tavanı, hatalı değer 400 INVALID_QUERY', () => {
    assert.deepEqual(parseListQuery({}), { year: null, status: 'all', meetingType: null, q: null, cursor: null, beforeId: null, limit: 50 });
    const parsed = parseListQuery({ year: '2026', status: 'kesin', meeting_type: 'genel_kurul', q: ' asansör ', before_id: '12', limit: '500' });
    assert.deepEqual(parsed, { year: 2026, status: 'kesin', meetingType: 'genel_kurul', q: 'asansör', cursor: null, beforeId: 12, limit: 200 });
    for (const bad of [{ year: '26' }, { year: '1899' }, { status: 'iptal' }, { meeting_type: 'x' }, { limit: '0' }, { limit: 'a' }, { before_id: '-1' }, { cursor: 'bozuk' }]) {
      queryError(() => parseListQuery(bad));
    }
  });

  it('sakin listesi: site_code, year, cursor | before_id, limit', () => {
    assert.deepEqual(parseResidentListQuery({ site_code: '1000000001', year: '2025', limit: '10' }), { siteCode: 1000000001, year: 2025, cursor: null, beforeId: null, limit: 10 });
    queryError(() => parseResidentListQuery({ site_code: 'x' }));
  });

  it('opak imleç gidiş-dönüş; sıralama anahtarı taslak r=0 / kesin r=1, numarasız n=0', () => {
    const draft = sortKeyOf({ id: '41', status: 'taslak', year: 2026, decision_no: null });
    const final = sortKeyOf({ id: '7', status: 'kesin', year: 2025, decision_no: 12 });
    assert.deepEqual(draft, { r: 0, year: 2026, n: 0, id: 41 });
    assert.deepEqual(final, { r: 1, year: 2025, n: 12, id: 7 });
    assert.deepEqual(decodeCursor(encodeCursor(final)), final);
    assert.deepEqual(parseListQuery({ cursor: encodeCursor(draft) }).cursor, draft);
    queryError(() => decodeCursor(Buffer.from('2.2026.1.1').toString('base64url')));
    queryError(() => decodeCursor(Buffer.from('1.2026.1.0').toString('base64url')));
  });

  it('anahtardan sonrası: önce sıra grubu (taslak -> kesin), grup içinde (yıl, numara, id) azalan; parametreler eklenir', () => {
    const params = ['site'];
    const where = afterKeySql({ r: 0, year: 2026, n: 0, id: 41 }, params);
    assert.deepEqual(params, ['site', 0, 2026, 0, 41]);
    assert.match(where, /> \$2 OR \(.*= \$2 AND \(d\.year, COALESCE\(d\.decision_no, 0\), d\.id\) < \(\$3::INTEGER, \$4::INTEGER, \$5::BIGINT\)\)/);
  });

  it('karar numarası araması: "2026/3" ve " 2026 / 3 " tanınır; başka metin null', () => {
    assert.deepEqual(parseNumberLabel('2026/3'), { year: 2026, no: 3 });
    assert.deepEqual(parseNumberLabel(' 2026 / 3 '), { year: 2026, no: 3 });
    assert.equal(parseNumberLabel('asansör'), null);
    assert.equal(numberLabel(2026, 3), '2026/3');
    assert.equal(numberLabel(2026, null), null);
  });
});

describe('yanıt eşleyicileri', () => {
  const ROW = {
    id: '5',
    site_code: '1000000001',
    year: 2026,
    decision_no: 3,
    meeting_type: 'genel_kurul',
    meeting_date: '2026-05-10',
    title: 'Asansör',
    body: 'Metin',
    attendees: null,
    vote_result: 'kabul',
    votes_for: 12,
    votes_against: 1,
    votes_abstain: null,
    visibility: 'sakinler',
    status: 'kesin',
    supersedes_id: '2',
    sup_year: 2025,
    sup_no: 7,
    sup_status: 'kesin',
    sup_visibility: 'yonetim',
    created_by: 20001,
    created_by_full_name: 'Yönetici',
    created_by_deleted: false,
    finalized_by: 20001,
    finalized_by_full_name: 'Yönetici',
    finalized_by_deleted: false,
    finalized_at: new Date('2026-05-11T10:00:00Z'),
    created_at: new Date('2026-05-10T10:00:00Z'),
    updated_at: new Date('2026-05-11T10:00:00Z'),
  };

  it('yönetim görünümü: sözleşmedeki TÜM alanlar, number_label, supersedes_label, superseded_by [{ id, number_label }]', () => {
    const out = mapDecision(ROW, { supersededBy: [{ id: '9', year: 2026, decision_no: 8 }] });
    assert.deepEqual(Object.keys(out), [
      'id', 'site_code', 'year', 'decision_no', 'number_label', 'meeting_type', 'meeting_date', 'title', 'body', 'attendees', 'vote_result', 'votes_for',
      'votes_against', 'votes_abstain', 'visibility', 'status', 'supersedes_id', 'supersedes_label', 'superseded_by', 'created_by_name', 'finalized_by_name',
      'finalized_at', 'created_at', 'updated_at',
    ]);
    assert.equal(out.id, 5);
    assert.equal(out.site_code, 1000000001);
    assert.equal(out.number_label, '2026/3');
    assert.equal(out.supersedes_id, 2);
    assert.equal(out.supersedes_label, '2025/7');
    assert.deepEqual(out.superseded_by, [{ id: 9, number_label: '2026/8' }]);
    assert.equal(out.created_by_name, 'Yönetici');
    assert.equal(out.finalized_by_name, 'Yönetici');
    assert.equal(out.finalized_at, '2026-05-11T10:00:00.000Z');
  });

  it('taslak: numara / etiket / kesinleştiren / zaman null; silinmiş ya da bağı kopmuş kullanıcı "Silinmiş Kullanıcı"', () => {
    const out = mapDecision({ ...ROW, status: 'taslak', decision_no: null, finalized_at: null, finalized_by: null, created_by: null, supersedes_id: null });
    assert.deepEqual([out.decision_no, out.number_label, out.finalized_by_name, out.finalized_at, out.supersedes_id, out.supersedes_label], [null, null, null, null, null, null]);
    assert.equal(out.created_by_name, 'Silinmiş Kullanıcı');
    assert.equal(mapDecision({ ...ROW, finalized_by_deleted: true }).finalized_by_name, 'Silinmiş Kullanıcı');
  });

  it('sakin görünümü: status / visibility / created_by_name YOK; değiştirilen karar sakinlere görünmüyorsa supersedes_id ve etiketi null', () => {
    const out = mapDecision(ROW, { resident: true });
    assert.ok(!('status' in out) && !('visibility' in out) && !('created_by_name' in out));
    assert.equal(out.finalized_by_name, 'Yönetici');
    assert.deepEqual([out.supersedes_id, out.supersedes_label], [null, null]);
    const visible = mapDecision({ ...ROW, sup_visibility: 'sakinler' }, { resident: true });
    assert.deepEqual([visible.supersedes_id, visible.supersedes_label], [2, '2025/7']);
  });
});

describe('kaynak düzeyi gizlilik', () => {
  it("audit details'e başlık / metin / katılımcı yazılmaz (servis yalnız durum, yıl, numara, alan adları gönderir)", () => {
    const service = src('decision_book_service.js');
    const audits = [...service.matchAll(/await audit\(client, actor, '[\w.]+', siteCode, \w+, ([\s\S]*?)\);\n/g)].map((match) => match[1]);
    assert.equal(audits.length, 4);
    for (const details of audits) {
      assert.ok(!/input\.(title|body|attendees)|row\.(title|body|attendees)/.test(details), details);
    }
    assert.ok(!/console\.(log|info|warn)/.test(service));
  });
});
