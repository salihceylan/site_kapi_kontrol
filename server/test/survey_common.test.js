// Anket ve Oylama ortak mantık (DB'siz): durum geçişleri, PATCH alan kuralları, oy kuralları (SURVEY_CLOSED / NOT_ELIGIBLE / ALREADY_VOTED / APARTMENT_ALREADY_VOTED),
// hedef doğrulama, girdi doğrulayıcıları, sakin sonuç görünürlüğü, yanıt eşleyicileri, kaynak düzeyi gizlilik kontrolleri (audit'te oy içeriği / başlık YOK).
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  PATCHABLE_FIELDS,
  STATUSES,
  TARGET_TYPES,
  TRANSITIONS,
  assertOpenable,
  assertPatchAllowed,
  assertTransition,
  countsFromRows,
  decideVote,
  effectiveStatus,
  isVotable,
  mapDetail,
  mapResidentItem,
  mapSummary,
  mapVoter,
  moduleDisabled,
  normalizeClosesAt,
  normalizeOptions,
  normalizeQuestion,
  normalizeTitle,
  parseCreateInput,
  parseListQuery,
  parsePatchInput,
  parseResidentListQuery,
  parseTargetInput,
  parseVoteInput,
  residentCanSeeResults,
  surveyVotesKeepNote,
} from '../src/modules/survey_common.js';
import { MODULE_CATALOG, getModuleDefinition } from '../src/modules/catalog.js';
import { EXPORT_ROW_LIMITS } from '../src/modules/account_common.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const src = (name) => readFileSync(path.join(here, '..', 'src', 'modules', name), 'utf8');
const throwsCode = (fn, status, code) => assert.throws(fn, (error) => error.statusCode === status && error.code === code);
const NOW = new Date('2026-10-19T10:00:00.000Z');
const PAST = '2026-10-19T09:00:00.000Z';
const FUTURE = '2026-10-20T10:00:00.000Z';
const OPTIONS = ['Evet', 'Hayır', 'Çekimser'];
const survey = (over = {}) => ({ id: 7, status: 'open', closes_at: null, options: OPTIONS, one_vote_per_apartment: false, anonymous: true, ...over });

describe('katalog girişi', () => {
  it("survey online_payment'tan hemen sonra: core false, available, varsayılan KAPALI, Türkçe ad", () => {
    const definition = getModuleDefinition('survey');
    const codes = MODULE_CATALOG.map((m) => m.code);
    assert.equal(codes.indexOf('survey'), codes.indexOf('online_payment') + 1);
    assert.equal(definition.name, 'Anket ve Oylama');
    assert.deepEqual([definition.core, definition.status, definition.defaultEnabled], [false, 'available', false]);
    assert.deepEqual([moduleDisabled().statusCode, moduleDisabled().code, moduleDisabled().extra], [403, 'MODULE_DISABLED', { module: 'survey' }]);
    assert.equal(EXPORT_ROW_LIMITS.survey_votes_cast, 500);
  });
});

describe('durum geçişleri ve PATCH alanları', () => {
  it('draft -> open -> closed; closed SONDUR; başka geçiş 409 INVALID_STATE { from, to }', () => {
    assert.deepEqual([...STATUSES], ['draft', 'open', 'closed']);
    assert.deepEqual(TRANSITIONS, { draft: ['open'], open: ['closed'], closed: [] });
    assertTransition('draft', 'open');
    assertTransition('open', 'closed');
    for (const [from, to] of [['draft', 'closed'], ['open', 'open'], ['closed', 'open'], ['closed', 'closed']]) {
      assert.throws(() => assertTransition(from, to), (error) => error.statusCode === 409 && error.code === 'INVALID_STATE' && error.extra.from === from && error.extra.to === to);
    }
  });

  it('draft: her alan; open: yalnız title ve closes_at (diğeri 409, fields listesi); closed: her PATCH 409', () => {
    assert.deepEqual(PATCHABLE_FIELDS.open, ['title', 'closes_at']);
    assert.deepEqual(assertPatchAllowed(survey({ status: 'draft' }), { title: 'x', options: OPTIONS, target: {}, anonymous: false }, NOW), ['title', 'options', 'target', 'anonymous']);
    assert.deepEqual(assertPatchAllowed(survey(), { title: 'x', closesAt: FUTURE }, NOW), ['title', 'closes_at']);
    assert.throws(() => assertPatchAllowed(survey(), { title: 'x', question: 'q', oneVotePerApartment: true }, NOW), (error) => error.code === 'INVALID_STATE' && error.statusCode === 409 && JSON.stringify(error.extra.fields) === '["question","one_vote_per_apartment"]');
    throwsCode(() => assertPatchAllowed(survey({ status: 'closed' }), { title: 'x' }, NOW), 409, 'INVALID_STATE');
    // closes_at geçmiş open anket okumada closed gibidir: PATCH de 409
    throwsCode(() => assertPatchAllowed(survey({ closes_at: PAST }), { title: 'x' }, NOW), 409, 'INVALID_STATE');
  });

  it('yayın ön koşulu: closes_at geçmiş / tam şimdi olan taslak açılamaz (409 INVALID_STATE, closes_at_passed); NULL / gelecek açılır; taslakta PATCH ile düzeltilebilir', () => {
    assertOpenable(survey({ status: 'draft' }), NOW);
    assertOpenable(survey({ status: 'draft', closes_at: FUTURE }), NOW);
    assertOpenable(survey({ status: 'draft', closes_at: new Date(FUTURE) }), NOW);
    for (const closesAt of [PAST, new Date(PAST), NOW.toISOString(), NOW]) {
      assert.throws(
        () => assertOpenable(survey({ status: 'draft', closes_at: closesAt }), NOW),
        (error) => error.statusCode === 409 && error.code === 'INVALID_STATE' && error.extra.from === 'draft' && error.extra.to === 'open' && error.extra.closes_at_passed === true,
        String(closesAt),
      );
    }
    // Çıkış yolu açık: taslakta effective durum 'draft' kalır, closes_at PATCH'i serbesttir (gelecek ya da NULL)
    assert.deepEqual(assertPatchAllowed(survey({ status: 'draft', closes_at: PAST }), { closesAt: FUTURE }, NOW), ['closes_at']);
    assert.deepEqual(assertPatchAllowed(survey({ status: 'draft', closes_at: PAST }), { closesAt: null }, NOW), ['closes_at']);
  });
});

describe('etkin durum (zamanlayıcı YOK)', () => {
  it("open + closes_at geçmiş => 'closed'; closes_at NULL / gelecek => 'open'; draft / closed değişmez", () => {
    assert.equal(effectiveStatus(survey({ closes_at: PAST }), NOW), 'closed');
    assert.equal(effectiveStatus(survey({ closes_at: new Date(PAST) }), NOW), 'closed');
    assert.equal(effectiveStatus(survey({ closes_at: FUTURE }), NOW), 'open');
    assert.equal(effectiveStatus(survey(), NOW), 'open');
    assert.equal(effectiveStatus(survey({ status: 'draft', closes_at: PAST }), NOW), 'draft');
    assert.equal(effectiveStatus(survey({ status: 'closed' }), NOW), 'closed');
    assert.equal(isVotable(survey({ closes_at: FUTURE }), NOW), true);
    assert.equal(isVotable(survey({ closes_at: PAST }), NOW), false);
    assert.equal(isVotable(survey({ status: 'draft' }), NOW), false);
  });
});

describe('oy kuralları (decideVote)', () => {
  const base = { now: NOW, eligibleApartmentIds: [12, 5], myVote: null, votedApartmentIds: [], optionIndex: 1 };

  it('etkin anket + kitlede + ilk oy: dairelerin en küçük kimliğine bağlanır', () => {
    assert.deepEqual(decideVote({ ...base, survey: survey() }), { apartmentId: 5 });
    assert.deepEqual(decideVote({ ...base, survey: survey({ one_vote_per_apartment: true }), votedApartmentIds: [12, 99] }), { apartmentId: 5 });
  });

  it('kapalı / taslak / süresi geçmiş: 409 SURVEY_CLOSED (kitle denetiminden ÖNCE)', () => {
    throwsCode(() => decideVote({ ...base, survey: survey({ status: 'closed' }) }), 409, 'SURVEY_CLOSED');
    throwsCode(() => decideVote({ ...base, survey: survey({ status: 'draft' }) }), 409, 'SURVEY_CLOSED');
    throwsCode(() => decideVote({ ...base, survey: survey({ closes_at: PAST }), eligibleApartmentIds: [] }), 409, 'SURVEY_CLOSED');
  });

  it('kitlede değil: 403 NOT_ELIGIBLE', () => {
    throwsCode(() => decideVote({ ...base, survey: survey(), eligibleApartmentIds: [] }), 403, 'NOT_ELIGIBLE');
    throwsCode(() => decideVote({ ...base, survey: survey(), eligibleApartmentIds: undefined }), 403, 'NOT_ELIGIBLE');
  });

  it('seçenek aralık dışı: 400 INVALID_BODY; ikinci oy: 409 ALREADY_VOTED (oy değiştirilemez)', () => {
    throwsCode(() => decideVote({ ...base, survey: survey(), optionIndex: 3 }), 400, 'INVALID_BODY');
    throwsCode(() => decideVote({ ...base, survey: survey(), optionIndex: -1 }), 400, 'INVALID_BODY');
    throwsCode(() => decideVote({ ...base, survey: survey(), myVote: 1 }), 409, 'ALREADY_VOTED');
    throwsCode(() => decideVote({ ...base, survey: survey(), myVote: 0, optionIndex: 0 }), 409, 'ALREADY_VOTED');
  });

  it('daire başına tek oy: aynı dairede başka hesap oy vermişse 409 APARTMENT_ALREADY_VOTED; kapalıysa daire kuralı uygulanmaz', () => {
    throwsCode(() => decideVote({ ...base, survey: survey({ one_vote_per_apartment: true }), votedApartmentIds: [5] }), 409, 'APARTMENT_ALREADY_VOTED');
    throwsCode(() => decideVote({ ...base, survey: survey({ one_vote_per_apartment: true }), votedApartmentIds: ['5'] }), 409, 'APARTMENT_ALREADY_VOTED');
    assert.deepEqual(decideVote({ ...base, survey: survey({ one_vote_per_apartment: false }), votedApartmentIds: [5] }), { apartmentId: 5 });
  });
});

describe('sakin sonuç görünürlüğü', () => {
  it('oy verdikten sonra ya da anket kapanınca görür; aksi hâlde results null', () => {
    assert.equal(residentCanSeeResults(survey(), null, NOW), false);
    assert.equal(residentCanSeeResults(survey(), 2, NOW), true);
    assert.equal(residentCanSeeResults(survey({ status: 'closed' }), null, NOW), true);
    assert.equal(residentCanSeeResults(survey({ closes_at: PAST }), null, NOW), true);
    const hidden = mapResidentItem({ ...survey(), site_code: 1, site_name: 'S', title: 'T', question: 'Q', my_vote: null, total_votes: 4 }, { counts: [1, 3, 0] }, NOW);
    assert.equal(hidden.results, null);
    assert.equal(hidden.my_vote, null);
    assert.equal(hidden.effective_status, 'open');
    const voted = mapResidentItem({ ...survey(), site_code: 1, site_name: 'S', title: 'T', question: 'Q', my_vote: '1', total_votes: '4' }, { counts: [1, 3, 0] }, NOW);
    assert.deepEqual(voted.results, { counts: [1, 3, 0], total_votes: 4 });
    assert.equal(voted.my_vote, 1);
    assert.deepEqual(Object.keys(voted), ['id', 'site_code', 'site_name', 'title', 'question', 'options', 'effective_status', 'closes_at', 'my_vote', 'results']);
    assert.ok(!('created_by_name' in voted) && !('target' in voted), 'sakin görünümünde açan kişi / hedef YOK');
  });

  it('countsFromRows: seçenek sayısı kadar, eksikler 0, aralık dışı yok sayılır', () => {
    assert.deepEqual(countsFromRows([{ option_index: '2', n: '5' }, { option_index: 9, n: 1 }], 3), [0, 0, 5]);
    assert.deepEqual(countsFromRows([], 2), [0, 0]);
  });
});

describe('girdi doğrulayıcıları', () => {
  it('başlık 1-120, soru 1-1000, seçenek 2-10 x 1-80 ve birbirinden farklı (Türkçe büyük/küçük duyarsız)', () => {
    assert.equal(normalizeTitle('  Aidat   artışı \n'), 'Aidat artışı');
    throwsCode(() => normalizeTitle(''), 400, 'INVALID_BODY');
    throwsCode(() => normalizeTitle('x'.repeat(121)), 400, 'INVALID_BODY');
    throwsCode(() => normalizeQuestion('x'.repeat(1001)), 400, 'INVALID_BODY');
    assert.equal(normalizeQuestion('Satır 1\r\nSatır 2'), 'Satır 1\nSatır 2');
    assert.deepEqual(normalizeOptions([' Evet ', 'Hayır']), ['Evet', 'Hayır']);
    throwsCode(() => normalizeOptions(['Tek']), 400, 'INVALID_BODY');
    throwsCode(() => normalizeOptions(Array.from({ length: 11 }, (_v, i) => `S${i}`)), 400, 'INVALID_BODY');
    throwsCode(() => normalizeOptions(['Evet', 'EVET']), 400, 'INVALID_BODY');
    throwsCode(() => normalizeOptions(['Evet', 'x'.repeat(81)]), 400, 'INVALID_BODY');
    throwsCode(() => normalizeOptions(['Evet', '']), 400, 'INVALID_BODY');
    throwsCode(() => normalizeOptions('Evet,Hayır'), 400, 'INVALID_BODY');
  });

  it('closes_at: null süresiz; ISO gelecek; geçmiş / bozuk 400', () => {
    assert.equal(normalizeClosesAt(null, NOW), null);
    assert.equal(normalizeClosesAt(undefined, NOW), null);
    assert.equal(normalizeClosesAt(FUTURE, NOW), FUTURE);
    throwsCode(() => normalizeClosesAt(PAST, NOW), 400, 'INVALID_BODY');
    throwsCode(() => normalizeClosesAt('dün', NOW), 400, 'INVALID_BODY');
    throwsCode(() => normalizeClosesAt(123, NOW), 400, 'INVALID_BODY');
  });

  it('hedef: site / blocks (block_ids) / apartments (apartment_ids, en çok 500, tekilleştirilir); bozuk tür / boş liste 400', () => {
    assert.deepEqual([...TARGET_TYPES], ['site', 'blocks', 'apartments']);
    assert.deepEqual(parseTargetInput({ type: 'site', block_ids: [1] }), { type: 'site', blockIds: [], apartmentIds: [] });
    assert.deepEqual(parseTargetInput({ type: 'blocks', block_ids: [3, '3', 4] }), { type: 'blocks', blockIds: [3, 4], apartmentIds: [] });
    assert.deepEqual(parseTargetInput({ type: 'apartments', apartment_ids: [9] }), { type: 'apartments', blockIds: [], apartmentIds: [9] });
    throwsCode(() => parseTargetInput({ type: 'blocks', block_ids: [] }), 400, 'INVALID_BODY');
    throwsCode(() => parseTargetInput({ type: 'apartments', apartment_ids: [0] }), 400, 'INVALID_BODY');
    throwsCode(() => parseTargetInput({ type: 'apartments', apartment_ids: Array.from({ length: 501 }, (_v, i) => i + 1) }), 400, 'INVALID_BODY');
    throwsCode(() => parseTargetInput({ type: 'herkes' }), 400, 'INVALID_BODY');
    throwsCode(() => parseTargetInput(null), 400, 'INVALID_BODY');
  });

  it('POST gövdesi: varsayılanlar (anonim, daire başına tek oy kapalı, taslak); publish now; bozuk alanlar 400', () => {
    const parsed = parseCreateInput({ title: 'T', question: 'Q', options: OPTIONS, target: { type: 'site' } }, NOW);
    assert.deepEqual(parsed, { title: 'T', question: 'Q', options: OPTIONS, target: { type: 'site', blockIds: [], apartmentIds: [] }, anonymous: true, oneVotePerApartment: false, closesAt: null, publish: 'draft' });
    assert.equal(parseCreateInput({ title: 'T', question: 'Q', options: OPTIONS, target: { type: 'site' }, publish: 'now', anonymous: false, one_vote_per_apartment: true, closes_at: FUTURE }, NOW).publish, 'now');
    throwsCode(() => parseCreateInput({ title: 'T', question: 'Q', options: OPTIONS, target: { type: 'site' }, publish: 'later' }, NOW), 400, 'INVALID_BODY');
    throwsCode(() => parseCreateInput({ title: 'T', question: 'Q', options: OPTIONS, target: { type: 'site' }, anonymous: 'evet' }, NOW), 400, 'INVALID_BODY');
    throwsCode(() => parseCreateInput({ title: 'T', question: 'Q', options: OPTIONS }, NOW), 400, 'INVALID_BODY');
    throwsCode(() => parseCreateInput([], NOW), 400, 'INVALID_BODY');
  });

  it('PATCH gövdesi: en az bir alan; closes_at null kabul; oy gövdesi option_index tam sayı 0-9', () => {
    throwsCode(() => parsePatchInput({}, NOW), 400, 'INVALID_BODY');
    assert.deepEqual(parsePatchInput({ closes_at: null }, NOW), { closesAt: null });
    assert.deepEqual(parsePatchInput({ title: 'Yeni', one_vote_per_apartment: true }, NOW), { title: 'Yeni', oneVotePerApartment: true });
    assert.deepEqual(parseVoteInput({ option_index: 2 }), { optionIndex: 2 });
    assert.deepEqual(parseVoteInput({ option_index: '0' }), { optionIndex: 0 });
    for (const body of [{}, { option_index: -1 }, { option_index: 10 }, { option_index: 1.5 }, { option_index: 'a' }, null]) {
      throwsCode(() => parseVoteInput(body), 400, 'INVALID_BODY');
    }
  });

  it('liste sorguları: status süzgeci, limit 1-100 (varsayılan 30), offset; before_id imleci; bozuk 400 INVALID_QUERY', () => {
    assert.deepEqual(parseListQuery({}), { status: 'all', limit: 30, offset: 0 });
    assert.deepEqual(parseListQuery({ status: 'open', limit: '500', offset: '10' }), { status: 'open', limit: 100, offset: 10 });
    throwsCode(() => parseListQuery({ status: 'bogus' }), 400, 'INVALID_QUERY');
    throwsCode(() => parseListQuery({ limit: '0' }), 400, 'INVALID_QUERY');
    assert.deepEqual(parseResidentListQuery({ site_code: '5', before_id: '40' }), { siteCode: 5, beforeId: 40, limit: 30 });
  });
});

describe('yanıt eşleyicileri', () => {
  const row = {
    id: '3', site_code: '1', title: 'T', question: 'Q', options: OPTIONS, status: 'open', target_type: 'blocks', target_block_ids: ['4'], target_apartment_ids: [], anonymous: false,
    one_vote_per_apartment: true, closes_at: null, opened_at: new Date(PAST), closed_at: null, created_by: 9, created_by_name: 'Ali', created_at: new Date(PAST), total_votes: '2', eligible_count: '10',
  };

  it('Summary / Detail alanları; silinmiş açan "Silinmiş Kullanıcı"', () => {
    const summary = mapSummary(row, NOW);
    assert.deepEqual(Object.keys(summary), ['id', 'title', 'status', 'effective_status', 'target_type', 'anonymous', 'one_vote_per_apartment', 'closes_at', 'opened_at', 'closed_at', 'total_votes', 'eligible_count', 'created_at', 'created_by_name']);
    assert.deepEqual([summary.id, summary.total_votes, summary.eligible_count, summary.created_by_name, summary.opened_at], [3, 2, 10, 'Ali', PAST]);
    assert.equal(mapSummary({ ...row, created_by: null, created_by_name: null }, NOW).created_by_name, 'Silinmiş Kullanıcı');
    assert.equal(mapSummary({ ...row, created_by_name: null }, NOW).created_by_name, 'Silinmiş Kullanıcı');
    const detail = mapDetail(row, { counts: [1, 1, 0], labels: ['A Blok'] }, NOW);
    assert.deepEqual(detail.results, { counts: [1, 1, 0], total_votes: 2, eligible_count: 10 });
    assert.deepEqual(detail.target, { type: 'blocks', block_ids: [4], apartment_ids: [], labels: ['A Blok'] });
    assert.deepEqual(detail.options, OPTIONS);
  });

  it('oy veren satırı: ad, daire etiketi, seçenek, zaman; silinmiş hesap "Silinmiş Kullanıcı"', () => {
    assert.deepEqual(mapVoter({ user_code: '5', full_name: 'Ayşe', apartment_id: 7, block_name: 'A Blok', unit_label: 'Daire 3', option_index: '1', voted_at: new Date(PAST) }), {
      user_code: 5, full_name: 'Ayşe', apartment_label: 'A Blok - Daire 3', option_index: 1, voted_at: PAST,
    });
    const gone = mapVoter({ user_code: null, full_name: null, apartment_id: null, option_index: 0, voted_at: new Date(PAST) });
    assert.deepEqual([gone.user_code, gone.full_name, gone.apartment_label], [null, 'Silinmiş Kullanıcı', null]);
  });

  it('hesap silme notu oy sayısını taşır', () => {
    assert.match(surveyVotesKeepNote(3), /\(3\)/);
  });
});

describe('kaynak düzeyi gizlilik', () => {
  it("audit details'e başlık / soru / seçenek / oy içeriği yazılmaz; oy için audit satırı YOK; sakin tarafı hedef / oy veren sızdırmaz", () => {
    const service = src('survey_service.js');
    const resident = src('survey_resident.js');
    for (const line of service.split('\n').filter((entry) => /await audit\(/.test(entry))) {
      assert.ok(!/title|question|options:|input\.options\b(?!\.length)/.test(line.replace('input.options.length', '')), line);
    }
    assert.equal(/await audit\(/.test(resident), false, 'oy için audit satırı yazılmaz (anonim ankette kimin oy verdiğini sızdırır)');
    assert.ok(/surveyNotFound\(\)/.test(resident) && !/forbiddenRole/.test(resident), 'sakin tarafında başkasının / görünmeyen anket 404 (varlık sızmaz)');
    assert.ok(/s\.status IN \('open', 'closed'\)/.test(resident), 'draft sakine ASLA görünmez');
    assert.ok(/FOR UPDATE OF s/.test(resident), 'oy anket satırı kilitli yazılır (daire başına tek oy yarışı)');
  });

  it('hesap silme / dışa aktarma: oylar kalır (anonimleşir), created_by NULL; export yalnız kendi oyları (başlık, seçenek metni, zaman)', () => {
    const deletion = src('account_deletion_service.js');
    const exportSource = src('account_export_service.js');
    assert.ok(/anonymizeUserSurveyData\(client, userCode\)/.test(deletion));
    assert.ok(/surveyVotesKeepNote\(/.test(deletion));
    assert.ok(/survey_votes_cast/.test(exportSource));
    assert.ok(/WHERE v\.user_code = \$1/.test(exportSource.slice(exportSource.indexOf('surveyVotesCast'))));
    const service = src('survey_service.js');
    assert.ok(/UPDATE survey_votes SET user_code = NULL WHERE user_code = \$1/.test(service));
    assert.ok(/UPDATE surveys SET created_by = NULL WHERE created_by = \$1/.test(service));
    assert.ok(!/DELETE FROM survey_votes/.test(service), 'oylar silinmez');
  });
});
