// İş Takibi ortak mantık (DB'siz): geçiş tablosu, sınırlar (env), girdi doğrulayıcıları, yanıt eşleyicileri (kurul / sakin gizliliği), kaynak düzeyi gizlilik kontrolleri.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  CATEGORIES,
  RESIDENT_TRANSITIONS,
  STAFF_TRANSITIONS,
  STATUSES,
  TERMINAL_STATUSES,
  mapEvent,
  mapManagerItem,
  mapResidentItem,
  normalizeComment,
  normalizeDescription,
  normalizeDueDate,
  normalizeTitle,
  parseCommentInput,
  parseCreateInput,
  parseListQuery,
  parsePatchInput,
  parseResidentListQuery,
  workItemLimits,
  idempotencyConflict,
  notResident,
  userOpenLimitReached,
  workItemsKeepNote,
} from '../src/modules/work_tracking_common.js';
import { exportInternals } from '../src/modules/account_export_service.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const src = (name) => readFileSync(path.join(here, '..', 'src', 'modules', name), 'utf8');
const KEY = 'abc-12345-xyz';
const invalid = (fn, code = 'INVALID_BODY') => assert.throws(fn, (error) => error.statusCode === 400 && error.code === code);

describe('durum geçişleri', () => {
  it('kapandi ve iptal SONDUR; her hedef geçerli bir durumdur; cozuldu yeniden açılabilir; yeni -> kapandi YOK', () => {
    assert.deepEqual([...STATUSES], ['yeni', 'islemde', 'beklemede', 'cozuldu', 'kapandi', 'iptal']);
    for (const status of TERMINAL_STATUSES) assert.deepEqual([...STAFF_TRANSITIONS[status]], []);
    for (const [from, targets] of Object.entries(STAFF_TRANSITIONS)) {
      assert.ok(STATUSES.includes(from));
      for (const to of targets) assert.ok(STATUSES.includes(to) && to !== from, `${from} -> ${to}`);
    }
    assert.ok(STAFF_TRANSITIONS.cozuldu.includes('islemde') && STAFF_TRANSITIONS.cozuldu.includes('kapandi'));
    assert.ok(!STAFF_TRANSITIONS.yeni.includes('kapandi') && !STAFF_TRANSITIONS.islemde.includes('yeni'));
    assert.deepEqual(RESIDENT_TRANSITIONS, { yeni: ['iptal'] });
  });
});

describe('sınırlar (ortam değişkeni)', () => {
  it('varsayılan 2000 açık talep / 30 kişi başı açık talep / 20 talep saat / 100 sakin + 200 yönetim yorumu; geçerli değer okunur; geçersiz / aralık dışı varsayılana döner (uyarı değer yazmaz)', () => {
    assert.deepEqual(workItemLimits({}), { maxOpenPerSite: 2000, maxPerUserPerHour: 20, maxOpenPerUser: 30, maxComments: 200, maxResidentComments: 100 });
    assert.equal(workItemLimits({ WORK_ITEMS_MAX_OPEN_PER_USER: '4' }).maxOpenPerUser, 4);
    assert.equal(workItemLimits({ WORK_ITEMS_MAX_OPEN_PER_SITE: '50', WORK_ITEMS_MAX_PER_USER_PER_HOUR: '3' }).maxOpenPerSite, 50);
    const warnings = [];
    const original = console.warn;
    console.warn = (...args) => warnings.push(args.join(' '));
    try {
      const limits = workItemLimits({ WORK_ITEMS_MAX_OPEN_PER_SITE: 'abc', WORK_ITEMS_MAX_PER_USER_PER_HOUR: '99999' });
      assert.equal(limits.maxOpenPerSite, 2000);
      assert.equal(limits.maxPerUserPerHour, 20);
    } finally {
      console.warn = original;
    }
    assert.ok(warnings.every((line) => !line.includes('abc') && !line.includes('99999')));
  });
});

describe('metin doğrulama', () => {
  it('başlık: tek satır, görünmezler atılır, 120 karakter (emoji 1 sayılır), boş / metin değil reddedilir', () => {
    assert.equal(normalizeTitle('  Asansör \n  arızalı‮ '), 'Asansör arızalı');
    assert.equal(normalizeTitle('😀'.repeat(120)).length, 240);
    invalid(() => normalizeTitle('😀'.repeat(121)));
    invalid(() => normalizeTitle('   '));
    invalid(() => normalizeTitle(5));
  });

  it('açıklama / yorum: satır sonları korunur, 2000 / 1000 sınırı, boş reddedilir', () => {
    assert.equal(normalizeDescription('a\r\nb'), 'a\nb');
    invalid(() => normalizeDescription('x'.repeat(2001)));
    invalid(() => normalizeDescription(''));
    assert.equal(normalizeComment(' tamam '), 'tamam');
    invalid(() => normalizeComment('y'.repeat(1001)));
    invalid(() => normalizeComment(null));
  });

  it('hedef tarih gerçek bir takvim günü olmalı', () => {
    assert.equal(normalizeDueDate('2030-02-28'), '2030-02-28');
    for (const bad of ['2030-02-30', '30-02-2030', 'yarın', '1980-01-01', '2101-01-01', 5, null]) invalid(() => normalizeDueDate(bad));
  });
});

describe('girdi ayrıştırıcıları', () => {
  const base = { site_code: 1000000001, category: 'ariza', location_type: 'ortak_alan', title: 'Başlık', description: 'Açıklama', idempotency_key: KEY };

  it('talep açma: geçerli gövde; kategori / konum / anahtar / urgent / daire kuralları', () => {
    const input = parseCreateInput({ ...base, urgent: true, block_id: 7 });
    assert.deepEqual([input.siteCode, input.category, input.locationType, input.urgent, input.blockId, input.apartmentId], [1000000001, 'ariza', 'ortak_alan', true, 7, null]);
    assert.equal(parseCreateInput(base).urgent, false);
    for (const category of CATEGORIES) assert.equal(parseCreateInput({ ...base, category }).category, category);
    for (const over of [{ site_code: 'x' }, { category: 'x' }, { location_type: 'x' }, { idempotency_key: 'kisa' }, { idempotency_key: undefined }, { urgent: 'evet' }, { apartment_id: 5 }, { block_id: -1 }, { description: '' }]) {
      invalid(() => parseCreateInput({ ...base, ...over }));
    }
    invalid(() => parseCreateInput(null));
    invalid(() => parseCreateInput([]));
    assert.equal(parseCreateInput({ ...base, location_type: 'daire', apartment_id: '12' }).apartmentId, 12);
  });

  it('PATCH: en az bir alan; assigned_to kullanıcı kodu | "me" | null; öncelik / durum kümeleri', () => {
    assert.deepEqual(parsePatchInput({ status: 'islemde', priority: 'acil', assigned_to: 'me', due_date: '2030-01-05' }), { status: 'islemde', priority: 'acil', assignedTo: 'me', dueDate: '2030-01-05' });
    assert.deepEqual(parsePatchInput({ assigned_to: null, due_date: null }), { assignedTo: null, dueDate: null });
    assert.equal(parsePatchInput({ assigned_to: '42' }).assignedTo, 42);
    for (const body of [{}, { unknown: 1 }, { status: 'x' }, { priority: 'yuksek' }, { assigned_to: 'x' }, { assigned_to: 0 }, { due_date: 'x' }, []]) invalid(() => parsePatchInput(body));
  });

  it('yorum: anahtar zorunlu; yönetim görünürlüğü zorunlu; sakin yalnız public', () => {
    assert.deepEqual(parseCommentInput({ body: ' x ', visibility: 'internal', idempotency_key: KEY }), { body: 'x', visibility: 'internal', idempotencyKey: KEY });
    invalid(() => parseCommentInput({ body: 'x', idempotency_key: KEY }));
    invalid(() => parseCommentInput({ body: 'x', visibility: 'herkes', idempotency_key: KEY }));
    invalid(() => parseCommentInput({ body: 'x', visibility: 'public' }));
    assert.equal(parseCommentInput({ body: 'x', idempotency_key: KEY }, { resident: true }).visibility, 'public');
    invalid(() => parseCommentInput({ body: 'x', visibility: 'internal', idempotency_key: KEY }, { resident: true }));
  });

  it('liste sorguları: durum listesi + open takma adı, atanan, sayfalama; geçersiz değer 400 INVALID_QUERY', () => {
    const f = parseListQuery({ status: 'open,iptal', category: 'bakim', priority: 'acil', assigned: 'none', q: ' asansör ', before_id: '50', limit: '500' });
    assert.deepEqual(f.statuses.sort(), ['beklemede', 'cozuldu', 'iptal', 'islemde', 'yeni']);
    assert.deepEqual([f.category, f.priority, f.assigned, f.q, f.beforeId, f.limit], ['bakim', 'acil', 'none', 'asansör', 50, 100]);
    assert.equal(parseListQuery({ assigned: '77' }).assigned, 77);
    assert.equal(parseListQuery({}).limit, 30);
    for (const query of [{ status: 'x' }, { category: 'x' }, { assigned: 'x' }, { before_id: 'x' }, { limit: '0' }, { limit: 'x' }, { status: 'a,b,c,d,e,f,g' }]) invalid(() => parseListQuery(query), 'INVALID_QUERY');
    assert.deepEqual(parseResidentListQuery({ status: 'closed', site_code: '9' }), { siteCode: 9, status: 'closed', beforeId: null, limit: 30 });
    invalid(() => parseResidentListQuery({ status: 'x' }), 'INVALID_QUERY');
  });
});

describe('yanıt eşleyicileri', () => {
  const row = {
    id: '5', site_code: '1000000001', category: 'ariza', location_type: 'daire', title: 'T', description: 'D', status: 'yeni', priority: 'acil', resident_urgent: true,
    due_date: '2030-01-05', created_at: new Date('2026-01-01T00:00:00Z'), updated_at: new Date('2026-01-02T00:00:00Z'), closed_at: null, created_by: 12, assigned_to: 99,
    apartment_id: '3', block_id: '2', block_name: 'A Blok', unit_label: 'Daire 3', requester_name: 'Ada', requester_phone: '+905550000001', assignee_name: 'Görevli', site_name: 'Gül', unread: true,
  };

  it('yönetim görünümü: telefon + kullanıcı kodu; KURUL görünümü: yalnız ad (telefon / kullanıcı kodu YOK)', () => {
    const manager = mapManagerItem(row, { kind: 'manager' });
    assert.deepEqual(manager.requester, { name: 'Ada', user_code: 12, phone: '+905550000001' });
    assert.deepEqual(manager.assigned_to, { user_code: 99, name: 'Görevli' });
    assert.deepEqual(manager.apartment, { id: 3, label: 'A Blok - Daire 3' });
    assert.deepEqual(mapManagerItem(row, { kind: 'board' }).requester, { name: 'Ada' });
    assert.equal(mapManagerItem({ ...row, requester_name: null, created_by: null, requester_phone: null }, { kind: 'staff' }).requester.name, 'Silinmiş Kullanıcı');
  });

  it('sakin görünümü: öncelik YOK, atanan adı YOK (has_assignee), unread / can_cancel / can_comment', () => {
    const mine = mapResidentItem(row);
    assert.equal(mine.priority, undefined);
    assert.equal(mine.assigned_to, undefined);
    assert.equal(mine.has_assignee, true);
    assert.deepEqual([mine.urgent, mine.unread, mine.can_cancel, mine.can_comment], [true, true, true, true]);
    const closed = mapResidentItem({ ...row, status: 'kapandi', assigned_to: null });
    assert.deepEqual([closed.has_assignee, closed.can_cancel, closed.can_comment], [false, false, false]);
    assert.ok(!JSON.stringify(mine).includes('Görevli') && !JSON.stringify(mine).includes('+90555'));
  });

  it('olay: yönetimde aktör + atama etiketleri; sakin / kurulda yalnız resident | management', () => {
    const event = { id: '9', event_type: 'assigned', visibility: 'internal', actor_user_code: 99, actor_kind: 'staff', actor_name: 'Görevli', from_value: null, to_value: '99', body: null, created_at: new Date('2026-01-01T00:00:00Z') };
    const detailed = mapEvent(event, { detailed: true, labels: new Map([['99', 'Görevli']]) });
    assert.deepEqual([detailed.actor, detailed.to_label, detailed.from_label], [{ user_code: 99, name: 'Görevli' }, 'Görevli', null]);
    const plain = mapEvent(event, { detailed: false });
    assert.equal(plain.actor, undefined);
    assert.equal(plain.actor_kind, 'management');
    assert.equal(mapEvent({ ...event, actor_kind: 'resident' }, { detailed: false }).actor_kind, 'resident');
  });

  it('hesap silme notu: talepler VE yazılan yorum metinleri kalır, "Silinmiş Kullanıcı"; süre / dayanak iddiası yok', () => {
    const both = workItemsKeepNote({ items: 3, comments: 5 });
    assert.match(both, /Açtığınız talepler \(3\), bu taleplerdeki durum geçmişi ve yazdığınız yorumların metinleri \(5\) site yönetiminde kalır/);
    const onlyItems = workItemsKeepNote({ items: 2, comments: 0 });
    assert.match(onlyItems, /^Açtığınız talepler \(2\) ve bu taleplerdeki durum geçmişi site yönetiminde kalır/);
    const onlyComments = workItemsKeepNote({ items: 0, comments: 4 });
    assert.match(onlyComments, /^Taleplere yazdığınız yorumların metinleri \(4\) site yönetiminde kalır/);
    for (const note of [both, onlyItems, onlyComments]) {
      assert.match(note, /Silinmiş Kullanıcı/);
      assert.equal(/\d+ (yıl|ay|gün)\b/.test(note), false);
    }
  });

  it('yeni hatalar: IDEMPOTENCY_CONFLICT 409, WORK_ITEM_USER_LIMIT 409 (user_open_limit), NOT_A_RESIDENT 403', () => {
    assert.deepEqual([idempotencyConflict().statusCode, idempotencyConflict().code], [409, 'IDEMPOTENCY_CONFLICT']);
    const limit = userOpenLimitReached(30);
    assert.deepEqual([limit.statusCode, limit.code, limit.extra.user_open_limit], [409, 'WORK_ITEM_USER_LIMIT', 30]);
    assert.deepEqual([notResident().statusCode, notResident().code], [403, 'NOT_A_RESIDENT']);
  });
});

describe('kaynak düzeyi gizlilik', () => {
  it('sakin SQL\'i öncelik / iç olay / atanan adı SEÇMEZ; yalnız public olaylar ve created_by = çağıran', () => {
    const resident = src('work_tracking_resident.js');
    assert.ok(!/w\.priority|assignee_name|visibility = 'internal'/.test(resident));
    assert.match(resident, /e\.visibility = 'public'/);
    assert.match(resident, /w\.created_by = \$1/);
    assert.match(resident, /\$\{MODULE_ON\}/);
  });

  it('yönetim SQL\'inde her sorgu site_code taşır (IDOR yok); kurul yalnız public olay okur; audit details başlık / açıklama / yorum taşımaz', () => {
    const service = src('work_tracking_service.js');
    assert.match(service, /w\.site_code = \$1 AND w\.id = \$2/);
    assert.match(service, /w\.id = \$1 AND w\.site_code = \$2/);
    assert.match(service, /detailed \? '' : `AND e\.visibility = 'public'`/);
    for (const file of ['work_tracking_service.js', 'work_tracking_resident.js']) {
      const code = src(file);
      for (const match of code.matchAll(/await audit\([^;]*;/g)) {
        assert.ok(!/title|description|input\.body|body:/.test(match[0].replace(/location_type|resident/g, '')), match[0]);
      }
    }
  });

  it('P2: sakin yorum sayımı actor_kind = resident, yönetim sayımı <> resident; yazma yollarında canlı sakin şartı; replay içerik karşılaştırması; kullanıcı kilidi site kilidinden SONRA; yetim atama kapsamı; silmede atama bırakılır', () => {
    const resident = src('work_tracking_resident.js');
    const service = src('work_tracking_service.js');
    assert.match(resident, /event_type = 'comment' AND actor_kind = 'resident'/);
    assert.match(service, /event_type = 'comment' AND actor_kind <> 'resident'/);
    assert.equal((resident.match(/await assertStillResident\(client, userCode, siteCode\);/g) ?? []).length, 2, 'iptal + yorum');
    assert.ok(resident.indexOf('siteLockKey(siteCode)') < resident.indexOf('userLockKey(userCode)'));
    assert.equal((resident.match(/throw idempotencyConflict\(\)/g) ?? []).length, 2, 'talep + yorum');
    assert.match(service, /throw idempotencyConflict\(\)/);
    assert.match(service, /NOT EXISTS \(\$\{ASSIGNEE_ACTIVE_SQL\}\)/);
    assert.match(service, /users WHERE user_code = \$1 AND deleted_at IS NULL FOR KEY SHARE/);
    assert.match(service, /UPDATE work_items SET assigned_to = NULL/);
    assert.match(src('account_deletion_service.js'), /await releaseAssignedWorkItems\(client, userCode\)/);
  });

  it('dışa aktarma yorum SQL\'i yalnız KENDİ yorumları (actor_user_code = $1, event_type = comment): talep başlığı, başkasının metni, atama / öncelik olayı seçilmez', () => {
    const text = exportInternals.SQL.workItemComments.replace(/\s+/g, ' ').trim();
    assert.match(text, /WHERE e\.actor_user_code = \$1 AND e\.event_type = 'comment' ORDER BY e\.id DESC$/);
    assert.ok(/e\.work_item_id, e\.site_code, e\.created_at, e\.body, e\.visibility/.test(text));
    for (const forbidden of [/title/, /JOIN/, /from_value/, /to_value/, /idempotency/]) assert.equal(forbidden.test(text), false, String(forbidden));
  });

  it('dışa aktarma SQL\'i yalnız kullanıcının KENDİ talepleri: öncelik, atanan, hedef tarih, olay / yorum seçilmez', () => {
    const text = exportInternals.SQL.workItems.replace(/\s+/g, ' ').trim();
    assert.match(text, /WHERE w\.created_by = \$1 ORDER BY w\.id DESC$/);
    for (const forbidden of [/priority/, /assigned_to/, /due_date/, /work_item_events/, /body/, /created_by,/, /phone/]) assert.equal(forbidden.test(text), false, String(forbidden));
    assert.ok(/w\.title, w\.description, w\.status, w\.created_at/.test(text));
  });
});
