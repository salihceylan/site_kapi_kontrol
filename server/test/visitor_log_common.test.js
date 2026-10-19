// Ziyaretçi ve Kargo ortak mantık (DB'siz): sabitler, geçiş tablosu, girdi doğrulayıcıları, liste sorgusu, yanıt eşleyicileri (sakin gizliliği), kaynak düzeyi gizlilik.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  INITIAL_STATUS,
  KINDS,
  LIST_DEFAULT_LIMIT,
  LIST_MAX_LIMIT,
  MAX_BODY_BYTES,
  OPEN_STATUSES,
  STATUSES,
  TERMINAL_STATUSES,
  TRANSITIONS,
  VISITOR_LOG_MODULE,
  assertTransition,
  mapEntry,
  moduleDisabled,
  nextStatuses,
  normalizeCompany,
  normalizeNote,
  normalizeVisitorName,
  parseCreateInput,
  parseDateBound,
  parseListQuery,
  parsePatchInput,
  parseResidentListQuery,
  visitorEntriesKeepNote,
} from '../src/modules/visitor_log_common.js';
import { apartmentLabel } from '../src/modules/people_common.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const src = (name) => readFileSync(path.join(here, '..', 'src', 'modules', name), 'utf8');
const invalid = (fn, code = 'INVALID_BODY', status = 400) => assert.throws(fn, (error) => error.statusCode === status && error.code === code);

describe('sabitler ve geçiş tablosu', () => {
  it('türler, durumlar, açık / sonlanmış kümeleri, modül kodu, liste ve gövde sınırları', () => {
    assert.deepEqual([...KINDS], ['visitor', 'cargo']);
    assert.deepEqual([...STATUSES], ['bekliyor', 'iceride', 'teslim_edildi', 'ayrildi', 'iptal']);
    assert.deepEqual([...OPEN_STATUSES], ['bekliyor', 'iceride']);
    assert.deepEqual([...TERMINAL_STATUSES], ['teslim_edildi', 'ayrildi', 'iptal']);
    assert.equal(VISITOR_LOG_MODULE, 'visitor_log');
    assert.deepEqual([LIST_DEFAULT_LIMIT, LIST_MAX_LIMIT, MAX_BODY_BYTES], [50, 200, 8192]);
  });

  it('başlangıç durumu türe göre: cargo -> bekliyor, visitor -> iceride', () => {
    assert.deepEqual({ ...INITIAL_STATUS }, { visitor: 'iceride', cargo: 'bekliyor' });
  });

  it('geçişler: bekliyor -> teslim_edildi|iptal; iceride -> ayrildi|iptal; teslim_edildi / ayrildi / iptal SONDUR; her hedef geçerli durumdur', () => {
    assert.deepEqual(
      Object.fromEntries(Object.entries(TRANSITIONS).map(([from, to]) => [from, [...to]])),
      { bekliyor: ['teslim_edildi', 'iptal'], iceride: ['ayrildi', 'iptal'], teslim_edildi: [], ayrildi: [], iptal: [] },
    );
    for (const from of STATUSES) {
      for (const to of TRANSITIONS[from]) assert.ok(STATUSES.includes(to), `${from} -> ${to}`);
      if (TERMINAL_STATUSES.includes(from)) assert.deepEqual(nextStatuses(from), []);
    }
    assert.deepEqual(nextStatuses('bekliyor'), ['teslim_edildi', 'iptal']);
    assert.deepEqual(nextStatuses('bilinmeyen'), []);
  });

  it('assertTransition: aynı durum false (değişiklik yok); izinli true; izinsiz / sonlanmış 409 INVALID_TRANSITION { from, to }', () => {
    assert.equal(assertTransition('bekliyor', 'bekliyor'), false);
    assert.equal(assertTransition('teslim_edildi', 'teslim_edildi'), false);
    assert.equal(assertTransition('bekliyor', 'teslim_edildi'), true);
    assert.equal(assertTransition('iceride', 'ayrildi'), true);
    assert.equal(assertTransition('iceride', 'iptal'), true);
    for (const [from, to] of [['bekliyor', 'ayrildi'], ['iceride', 'teslim_edildi'], ['bekliyor', 'iceride'], ['teslim_edildi', 'iptal'], ['ayrildi', 'iceride'], ['iptal', 'bekliyor']]) {
      assert.throws(
        () => assertTransition(from, to),
        (error) => error.statusCode === 409 && error.code === 'INVALID_TRANSITION' && error.extra.from === from && error.extra.to === to,
        `${from} -> ${to}`,
      );
    }
  });

  it('moduleDisabled 403 MODULE_DISABLED { module: visitor_log }', () => {
    const error = moduleDisabled();
    assert.deepEqual([error.statusCode, error.code, error.extra], [403, 'MODULE_DISABLED', { module: 'visitor_log' }]);
  });
});

describe('metin doğrulayıcıları', () => {
  it('ad: tek satıra indirir, boşlukları toplar, görünmez karakterleri atar; 1-120 karakter; metin değilse / boşsa 400', () => {
    assert.equal(normalizeVisitorName('  Ahmet\n\tYılmaz  '), 'Ahmet Yılmaz');
    assert.equal(normalizeVisitorName('Aras​Kargo'), 'ArasKargo');
    assert.equal(normalizeVisitorName('x'.repeat(120)), 'x'.repeat(120));
    invalid(() => normalizeVisitorName('x'.repeat(121)));
    invalid(() => normalizeVisitorName('   '));
    invalid(() => normalizeVisitorName(undefined));
    invalid(() => normalizeVisitorName(5));
  });

  it('firma: boş / null -> null; 120 üstü 400; metin değilse 400', () => {
    assert.equal(normalizeCompany(undefined), null);
    assert.equal(normalizeCompany(null), null);
    assert.equal(normalizeCompany('   '), null);
    assert.equal(normalizeCompany(' Yurtiçi  Kargo '), 'Yurtiçi Kargo');
    invalid(() => normalizeCompany('y'.repeat(121)));
    invalid(() => normalizeCompany({}));
  });

  it('not: çok satırlı, satır sonları korunur, kontrol karakterleri atılır, boş -> null, 500 üstü 400', () => {
    assert.equal(normalizeNote(undefined), null);
    assert.equal(normalizeNote(''), null);
    assert.equal(normalizeNote('Kapıya bırakıldı.\r\nİkinci satır\u0007'), 'Kapıya bırakıldı.\nİkinci satır');
    assert.equal(normalizeNote('n'.repeat(500)), 'n'.repeat(500));
    invalid(() => normalizeNote('n'.repeat(501)));
    invalid(() => normalizeNote([]));
  });
});

describe('girdi ayrıştırıcıları', () => {
  it('parseCreateInput: durum türe göre hesaplanır (istemciden alınmaz); daire isteğe bağlı; tür / ad / daire geçersizse 400', () => {
    assert.deepEqual(parseCreateInput({ kind: 'cargo', visitor_name: 'Aras Kargo', status: 'ayrildi' }), {
      kind: 'cargo', apartmentId: null, visitorName: 'Aras Kargo', company: null, note: null, status: 'bekliyor',
    });
    assert.deepEqual(parseCreateInput({ kind: 'visitor', apartment_id: '12', visitor_name: 'Ayşe', company: 'X A.Ş.', note: 'tanıdık' }), {
      kind: 'visitor', apartmentId: 12, visitorName: 'Ayşe', company: 'X A.Ş.', note: 'tanıdık', status: 'iceride',
    });
    for (const body of [null, [], 'x', {}, { kind: 'paket', visitor_name: 'a' }, { kind: 'cargo' }, { kind: 'cargo', visitor_name: '' }]) {
      invalid(() => parseCreateInput(body), 'INVALID_BODY');
    }
    for (const apartmentId of ['x', 0, -1, 1.5, '1e3', {}]) invalid(() => parseCreateInput({ kind: 'cargo', visitor_name: 'a', apartment_id: apartmentId }));
  });

  it('parsePatchInput: en az bir alan; durum geçerli kümeden; note null / boş -> notu siler', () => {
    assert.deepEqual(parsePatchInput({ status: 'teslim_edildi' }), { status: 'teslim_edildi' });
    assert.deepEqual(parsePatchInput({ note: null }), { note: null });
    assert.deepEqual(parsePatchInput({ note: '  ' }), { note: null });
    assert.deepEqual(parsePatchInput({ status: 'iptal', note: 'yanlış daire' }), { status: 'iptal', note: 'yanlış daire' });
    for (const body of [{}, null, { status: 'bitti' }, { status: 5 }, { visitor_name: 'x' }, { note: 'n'.repeat(501) }]) invalid(() => parsePatchInput(body));
  });

  it('parseListQuery: varsayılanlar (limit 50, offset 0), limit 200 ile kırpılır, status tek / open / closed, geçersiz değerler 400 INVALID_QUERY', () => {
    assert.deepEqual(parseListQuery({}), { kind: null, statuses: null, apartmentId: null, q: null, from: null, to: null, limit: 50, offset: 0 });
    assert.equal(parseListQuery({ limit: '999' }).limit, 200);
    assert.deepEqual(parseListQuery({ status: 'open' }).statuses, ['bekliyor', 'iceride']);
    assert.deepEqual(parseListQuery({ status: 'closed' }).statuses, ['teslim_edildi', 'ayrildi', 'iptal']);
    assert.deepEqual(parseListQuery({ status: 'iptal' }).statuses, ['iptal']);
    const parsed = parseListQuery({ kind: 'cargo', apartment_id: '7', q: ' Aras ', from: '2026-10-01', to: '2026-10-19', limit: '10', offset: '20' });
    assert.equal(parsed.kind, 'cargo');
    assert.equal(parsed.apartmentId, 7);
    assert.equal(parsed.q, 'Aras');
    assert.deepEqual(parsed.from, { value: '2026-10-01', dateOnly: true });
    assert.deepEqual(parsed.to, { value: '2026-10-19', dateOnly: true });
    assert.deepEqual([parsed.limit, parsed.offset], [10, 20]);
    for (const query of [{ status: 'bogus' }, { kind: 'paket' }, { limit: '0' }, { limit: 'x' }, { offset: '-1' }, { offset: '100001' }, { from: '2026-02-30' }, { to: 'dün' }]) {
      invalid(() => parseListQuery(query), 'INVALID_QUERY');
    }
  });

  it('parseDateBound: gün (YYYY-MM-DD) ya da ISO tarih-saat; boş -> null', () => {
    assert.equal(parseDateBound(''), null);
    assert.equal(parseDateBound(undefined), null);
    assert.deepEqual(parseDateBound('2026-10-19'), { value: '2026-10-19', dateOnly: true });
    assert.deepEqual(parseDateBound('2026-10-19T08:30:00.000Z'), { value: '2026-10-19T08:30:00.000Z', dateOnly: false });
    invalid(() => parseDateBound('19.10.2026'), 'INVALID_QUERY');
    invalid(() => parseDateBound('2026-13-01'), 'INVALID_QUERY');
  });

  it('parseResidentListQuery: site_code / before_id isteğe bağlı, limit 50 varsayılan', () => {
    assert.deepEqual(parseResidentListQuery({}), { siteCode: null, beforeId: null, limit: 50 });
    assert.deepEqual(parseResidentListQuery({ site_code: '1000000001', before_id: '99', limit: '5' }), { siteCode: 1000000001, beforeId: 99, limit: 5 });
  });
});

describe('yanıt eşleyicileri', () => {
  const arrived = new Date('2026-10-19T07:00:00.000Z');
  const row = {
    id: '41', site_code: '1000000001', site_name: 'Deneme Sitesi', kind: 'cargo', apartment_id: '12', block_name: 'A Blok', unit_label: 'Daire 3',
    visitor_name: 'Aras Kargo', company: null, note: 'kapıcıda', status: 'bekliyor', arrived_at: arrived, completed_at: null, resident_seen_at: null,
    recorded_by: 20005, completed_by: null, recorded_by_name: 'Görevli', completed_by_name: null,
  };

  it('yönetim görünümü: kimlikler sayı, daire etiketi, next_statuses hazır, kaydeden adı; açık kayıtta completed_by_name null', () => {
    assert.deepEqual(mapEntry(row), {
      id: 41, kind: 'cargo', apartment_id: 12, apartment_label: apartmentLabel('A Blok', 'Daire 3'), block_name: 'A Blok', visitor_name: 'Aras Kargo', company: null,
      note: 'kapıcıda', status: 'bekliyor', next_statuses: ['teslim_edildi', 'iptal'], arrived_at: '2026-10-19T07:00:00.000Z', completed_at: null,
      resident_seen_at: null, recorded_by_name: 'Görevli', completed_by_name: null,
    });
  });

  it('silinmiş / NULL kaydeden ve sonlandıran "Silinmiş Kullanıcı"; dairesiz kayıtta etiket ve blok null; sonlanmış kayıtta next_statuses boş', () => {
    const done = mapEntry({ ...row, apartment_id: null, block_name: null, unit_label: null, status: 'teslim_edildi', completed_at: arrived, recorded_by_name: null, completed_by_name: null });
    assert.equal(done.recorded_by_name, 'Silinmiş Kullanıcı');
    assert.equal(done.completed_by_name, 'Silinmiş Kullanıcı');
    assert.deepEqual([done.apartment_id, done.apartment_label, done.block_name, done.next_statuses, done.completed_at], [null, null, null, [], '2026-10-19T07:00:00.000Z']);
  });

  it('sakin görünümü: kaydeden / sonlandıran adı YOK; site_code, site_name, unread eklenir; next_statuses boş', () => {
    const mine = mapEntry(row, { resident: true });
    assert.ok(!('recorded_by_name' in mine) && !('completed_by_name' in mine) && !('recorded_by' in mine) && !('completed_by' in mine));
    assert.deepEqual([mine.site_code, mine.site_name, mine.unread, mine.next_statuses, mine.visitor_name], [1000000001, 'Deneme Sitesi', true, [], 'Aras Kargo']);
    assert.equal(mapEntry({ ...row, resident_seen_at: arrived }, { resident: true }).unread, false);
  });

  it('hesap silme notu sayıyı ve "Silinmiş Kullanıcı" ifadesini taşır', () => {
    const note = visitorEntriesKeepNote('7');
    assert.ok(note.includes('(7)') && note.includes('Silinmiş Kullanıcı') && note.includes('site yönetiminde kalır'));
  });
});

describe('kaynak düzeyi gizlilik ve sözleşme kontrolleri', () => {
  it('sakin modülü görevli adını ve kullanıcı kodunu SEÇMEZ; yalnız kendi daireleri (apartment_memberships VEYA apartment_residencies) ile birleşir', () => {
    const resident = src('visitor_log_resident.js');
    assert.ok(!/full_name|recorded_by_name|completed_by_name/.test(resident));
    assert.ok(resident.includes('INNER JOIN my_apts ma ON ma.id = v.apartment_id'));
    assert.ok(resident.includes('apartment_memberships') && resident.includes('apartment_residencies'));
    assert.ok(resident.includes("smod.module_code = '${VISITOR_LOG_MODULE}' AND smod.enabled = TRUE"), 'modülü kapalı sitelerin kayıtları sakine gelmez');
  });

  it('audit details yalnız kimlik / tür / durum taşır (ziyaretçi adı, firma, not YOK); DELETE ucu yok; her sorguda site_code', () => {
    const service = src('visitor_log_service.js');
    assert.match(service, /'visitor_entry\.created', siteCode, entryId, \{ kind: input\.kind, apartment_id: input\.apartmentId, status: input\.status \}/);
    assert.ok(service.includes('details.note_changed = true') && !/details\.note = /.test(service) && !/details\.visitor_name/.test(service));
    assert.ok(service.includes('FOR UPDATE OF v') && service.includes('WHERE v.id = $1 AND v.site_code = $2'));
    assert.ok(service.includes('SELECT id FROM apartments WHERE id = $1 AND site_code = $2 AND is_active = TRUE LIMIT 1'), 'daire bu siteye ait ve etkin olmalı');
    const routes = src('visitor_log_routes.js');
    assert.ok(!/visitorLogRouter\.delete\(/.test(routes), 'DELETE yok');
    assert.ok(routes.includes('max: 240, key: userKey') && routes.includes('max: 1200, key: userKey'));
  });
});
