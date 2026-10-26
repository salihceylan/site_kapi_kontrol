// Kisi ve Daire Kayitlari (Faz 2a) is akislari (DB'siz, KATI betikli sahte veritabani): kisi ekleme (hesap baglama / mevcut daire
// sakini hesabi akisi), duzenleme, iliskiler, daire alanlari, araclar.
//
// Sahte veritabani KATIDIR: tanimli bir isleyiciyle eslesmeyen sorgu (altyapi sorgulari haric) hata verir; bu yuzden her akisin
// calistirdigi SQL testte acikca bildirilir ve SQL'in ANLAMI (tek tek ifadeler) gercek-PG betigi (scripts/qa_platform_pg.mjs) ile sinanir.
import { describe, it, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert/strict';
import nodemailer from 'nodemailer';
import bcrypt from 'bcryptjs';
import { pool } from '../src/db.js';
import { updateApartment } from '../src/modules/apartment_records_service.js';
import {
  addResidency,
  createPerson,
  evaluateManagedAccount,
  parsePersonCreateInput,
  provisionPersonAccount,
  provisionResidentAndLinkPerson,
  resetPersonPinDirect,
  updatePerson,
  updateResidency,
} from '../src/modules/people_service.js';
import { SYNC_STEPS, siteTiePredicate } from '../src/modules/people_sync_sql.js';
import { createVehicle, removeVehicle } from '../src/modules/vehicle_service.js';

process.env.PEOPLE_SYNC_MIN_INTERVAL_MS = '0';

const SITE = 1000000001;
const actor = { id: 20001, user_code: 20001, userCode: 20001, role: 'site_manager', full_name: 'Ayşe Yönetici' };

const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
const ok = (rows = []) => ({ rows, rowCount: rows.length });

let log;
let handlers;
// PostgreSQL gibi: hata alan transaction'da ROLLBACK disinda sorgu calismaz (25P02).
let txAborted = false;

// Altyapi sorgulari: isleyici gerekmez (transaction kontrolu, kilit, savepoint, denetim yazimi).
const INFRA = [
  /^BEGIN$/,
  /^COMMIT$/,
  /^ROLLBACK$/,
  /^SELECT pg_advisory_xact_lock/,
  /^SAVEPOINT /,
  /^RELEASE SAVEPOINT /,
  /^ROLLBACK TO SAVEPOINT /,
  /^INSERT INTO audit_log/,
  /^INSERT INTO apartment_residency_log/,
  // Kiraci her zaman daire admini: grantApartmentAccess kancasi (ensureTenantIsAdmin) once YALNIZ aday var mi diye okur; bu testlerde aday yok.
  /^SELECT 1 FROM \(SELECT a\.id AS apartment_id/,
];

function install() {
  log = [];
  txAborted = false;
  const run = async (text, params, inTx) => {
    const sql = norm(text);
    log.push({ sql, params: params ?? [], inTx });
    // PostgreSQL gibi: SAVEPOINT'e donus (ROLLBACK TO SAVEPOINT) hata durumunu temizler.
    if (/^ROLLBACK TO SAVEPOINT /.test(sql)) {
      txAborted = false;
    }
    if (txAborted && inTx && sql !== 'ROLLBACK') {
      throw Object.assign(new Error('current transaction is aborted, commands ignored until end of transaction block'), { code: '25P02' });
    }
    for (const [pattern, handler] of handlers) {
      if (pattern.test(sql)) {
        return typeof handler === 'function' ? handler(sql, params ?? []) : handler;
      }
    }
    if (INFRA.some((pattern) => pattern.test(sql))) {
      return ok();
    }
    throw new Error(`BEKLENMEYEN SQL (sahte DB kati): ${sql.slice(0, 220)}`);
  };
  pool.query = (text, params) => run(text, params, false);
  pool.connect = async () => ({ query: (text, params) => run(text, params, true), release() {} });
}

const find = (regex) => log.find((q) => regex.test(q.sql));
const findAll = (regex) => log.filter((q) => regex.test(q.sql));
const has = (regex) => log.some((q) => regex.test(q.sql));
const indexOfQuery = (regex) => log.findIndex((q) => regex.test(q.sql));
const auditActions = () => findAll(/^INSERT INTO audit_log/).map((q) => q.params[3]);
const auditDetails = (action) => JSON.parse(findAll(/^INSERT INTO audit_log/).find((q) => q.params[3] === action).params[7]);

const APARTMENT_ROW = { id: '9', site_code: String(SITE), unit_label: 'Daire 2', resident_user_code: null, block_name: 'A Blok' };

const APARTMENT_LOOKUP = /FROM apartments a INNER JOIN site_blocks b ON b\.id = a\.block_id WHERE a\.id = \$1 AND a\.site_code = \$2 LIMIT 1$/;
const APARTMENT_LOCKED = /FROM apartments a INNER JOIN site_blocks b ON b\.id = a\.block_id WHERE a\.id = \$1 AND a\.site_code = \$2 LIMIT 1 FOR UPDATE OF a$/;
const PERSON_INSERT = /^INSERT INTO site_people/;
const EMAIL_LOOKUP = /FROM site_people sp LEFT JOIN users u ON u\.user_code = sp\.user_code WHERE sp\.site_code = \$1 AND \(/;
const SITE_USER_LOOKUP = /^SELECT u\.user_code FROM users u WHERE lower\(u\.email\) = \$1/;
const RELATION_CHECK = /^SELECT id FROM apartment_residencies WHERE apartment_id = \$1 AND is_current = TRUE AND relation = \$2/;
const RESIDENCY_INSERT = /^INSERT INTO apartment_residencies/;
const DETAIL_PERSON = /^SELECT sp\.id, sp\.user_code, sp\.is_active, sp\.note[\s\S]*WHERE sp\.site_code = \$1 AND sp\.id = \$2 LIMIT 1$/;
const DETAIL_RESIDENCIES = /FROM apartment_residencies r INNER JOIN apartments a ON a\.id = r\.apartment_id INNER JOIN site_blocks b ON b\.id = a\.block_id WHERE r\.person_id = \$1 ORDER BY/;
const DETAIL_VEHICLES = /FROM vehicles v LEFT JOIN site_people sp ON sp\.id = v\.person_id[\s\S]*WHERE v\.person_id = \$1 AND v\.is_active = TRUE ORDER BY v\.id$/;

const personRow = (overrides = {}) => ({
  id: '5',
  user_code: null,
  is_active: true,
  note: null,
  created_at: new Date('2026-10-14T08:00:00.000Z'),
  full_name: 'Ali Veli',
  phone: null,
  email: null,
  has_account: false,
  account_kind: 'none',
  ...overrides,
});

/** createPerson / updatePerson vb. sonunda yuklenen PersonDetail sorgulari icin varsayilan isleyiciler. */
function detailHandlers(rowOverrides = {}) {
  return [
    [DETAIL_PERSON, () => ok([personRow(rowOverrides)])],
    [DETAIL_RESIDENCIES, () => ok()],
    [DETAIL_VEHICLES, () => ok()],
  ];
}

beforeEach(() => {
  handlers = [];
  install();
  mock.method(console, 'error', () => {});
  mock.method(console, 'log', () => {});
});

afterEach(() => {
  delete pool.query;
  delete pool.connect;
  mock.restoreAll();
});

// ---------------------------------------------------------------------------
// createPerson
// ---------------------------------------------------------------------------

describe('createPerson: kayit, hesap baglama (yalniz bu sitede erisimi olan hesap), mevcut daire sakini akisi', () => {
  const input = (body) => parsePersonCreateInput(body);

  it('yalniz ad: hesapsiz kisi + person.created; daire/hesap/uyelik islemi YOK; site kilidi altinda tek transaction; credentials_sent null', async () => {
    handlers.push([PERSON_INSERT, () => ok([{ id: '5' }])], ...detailHandlers());
    const result = await createPerson({ siteCode: SITE, input: input({ full_name: 'Ali Veli', phone: '0555 111 22 33', note: 'not' }), actor });
    const insert = find(PERSON_INSERT);
    assert.deepEqual(insert.params, [SITE, null, 'Ali Veli', '+905551112233', null, 'not', 20001]);
    assert.deepEqual(auditActions(), ['person.created']);
    assert.deepEqual(auditDetails('person.created'), { has_account: false });
    assert.equal(has(/^(INSERT INTO|UPDATE) (apartment_memberships|users|apartment_residencies|site_memberships)/), false);
    assert.equal(result.credentials_sent, null, 'hesap acilmadi -> credentials_sent null');
    const sqls = log.map((q) => q.sql);
    assert.equal(sqls[0], 'BEGIN');
    assert.match(sqls[1], /^SELECT pg_advisory_xact_lock/);
    assert.equal(log[1].params[0], `people_sync:${SITE}`);
    assert.ok(sqls.includes('COMMIT'));
  });

  it('daire + iliski (e-postasiz): iliski kaydi, giris tarihi varsayilan BUGUN; erisim uyeligi OLUSMAZ; residency.added; daire kilit altinda okunur', async () => {
    handlers.push(
      [APARTMENT_LOOKUP, () => ok([APARTMENT_ROW])],
      [APARTMENT_LOCKED, () => ok([APARTMENT_ROW])],
      [RELATION_CHECK, () => ok()],
      [PERSON_INSERT, () => ok([{ id: '5' }])],
      [RESIDENCY_INSERT, () => ok([{ id: '31' }])],
      ...detailHandlers(),
    );
    await createPerson({ siteCode: SITE, input: input({ full_name: 'Ali Veli', apartment_id: 9, relation: 'tenant' }), actor });
    const residency = find(RESIDENCY_INSERT);
    assert.deepEqual(residency.params.slice(0, 4), [SITE, 9, 5, 'tenant']);
    assert.match(residency.params[4], /^\d{4}-\d{2}-\d{2}$/);
    assert.deepEqual(auditActions(), ['person.created', 'residency.added']);
    assert.deepEqual(auditDetails('residency.added'), { residency_id: 31, apartment_id: 9, relation: 'tenant' });
    assert.equal(has(/INSERT INTO apartment_memberships|INSERT INTO site_memberships|INSERT INTO users/), false);
    assert.ok(indexOfQuery(APARTMENT_LOCKED) < indexOfQuery(RESIDENCY_INSERT), 'daire satiri iliskiden once kilitlendi');
    // CRM'den eklenen iliski origin kolonunu belirtmez -> varsayilan manual (elle girilen; sessizce bitmez)
    assert.equal(/origin/.test(residency.sql), false);
  });

  it('girilen giris tarihi kullanilir', async () => {
    handlers.push(
      [APARTMENT_LOOKUP, () => ok([APARTMENT_ROW])],
      [APARTMENT_LOCKED, () => ok([APARTMENT_ROW])],
      [PERSON_INSERT, () => ok([{ id: '5' }])],
      [RESIDENCY_INSERT, () => ok([{ id: '31' }])],
      ...detailHandlers(),
    );
    await createPerson({ siteCode: SITE, input: input({ full_name: 'Ali Veli', apartment_id: 9, move_in_date: '15.03.2025' }), actor });
    assert.equal(find(RESIDENCY_INSERT).params[4], '2025-03-15');
  });

  it('baska sitenin dairesi / yok daire -> 404 APARTMENT_NOT_FOUND (sorgu site kapsamli), hicbir sey yazilmaz', async () => {
    handlers.push([APARTMENT_LOOKUP, () => ok()]);
    await assert.rejects(
      () => createPerson({ siteCode: SITE, input: input({ full_name: 'Ali Veli', apartment_id: 77 }), actor }),
      (error) => error.code === 'APARTMENT_NOT_FOUND' && error.statusCode === 404,
    );
    assert.deepEqual(find(APARTMENT_LOOKUP).params, [77, SITE]);
    assert.equal(has(/^BEGIN/), false);
  });

  it('ayni sitede AKTIF ayni e-posta -> 409 PERSON_EXISTS + person_id; yazma yok (kontrol kilit ALTINDA)', async () => {
    handlers.push([EMAIL_LOOKUP, () => ok([{ id: '8', is_active: true, user_code: null }])]);
    await assert.rejects(
      () => createPerson({ siteCode: SITE, input: input({ full_name: 'Ali Veli', email: 'Ali@Example.com' }), actor }),
      (error) => error.code === 'PERSON_EXISTS' && error.statusCode === 409 && error.extra?.person_id === 8,
    );
    assert.equal(has(PERSON_INSERT), false);
    assert.ok(has(/^ROLLBACK$/));
    assert.ok(log.find((q) => EMAIL_LOOKUP.test(q.sql)).inTx, 'tekrar kontrolu transaction (kilit) icinde');
  });

  it('PASIF (tasinmis) ayni e-postali kisi YENIDEN KULLANILIR: yinelenen kisi acilmaz, gecmis korunur', async () => {
    handlers.push(
      [EMAIL_LOOKUP, () => ok([{ id: '8', is_active: false, user_code: null }])],
      [SITE_USER_LOOKUP, () => ok()],
      [/^UPDATE site_people SET is_active = TRUE/, () => ok()],
      ...detailHandlers(),
    );
    await createPerson({ siteCode: SITE, input: input({ full_name: 'Ali Veli', email: 'ali@example.com' }), actor });
    assert.equal(has(PERSON_INSERT), false);
    const update = find(/^UPDATE site_people SET is_active = TRUE/);
    assert.equal(update.params[0], 8);
    assert.deepEqual(auditDetails('person.created'), { has_account: false, reactivated: true });
  });

  describe('H1: hesap bagi YALNIZ bu sitede zaten erisimi olan kullanicilarla', () => {
    it('S1: baglama sorgusu SITE KAPSAMLI ve YALNIZ aktif daire uyeligi / eski sakin gostergesi (eslemedeki "desired" ile ayni); STAFF/BOARD/RESIDENT site uyeligi ve yoneticilik BAG SAYILMAZ; dahili adresler haric', async () => {
      handlers.push([EMAIL_LOOKUP, () => ok()], [SITE_USER_LOOKUP, () => ok()], [PERSON_INSERT, () => ok([{ id: '5' }])], ...detailHandlers());
      await createPerson({ siteCode: SITE, input: input({ full_name: 'Ali Veli', email: 'ali@example.com' }), actor });
      const lookup = find(SITE_USER_LOOKUP);
      assert.deepEqual(lookup.params, ['ali@example.com', SITE]);
      assert.match(lookup.sql, /u\.email NOT LIKE '%@ahbu\.local'/);
      assert.match(lookup.sql, /u\.is_active = TRUE/, 'pasif hesaba baglanmaz');
      assert.match(lookup.sql, /SELECT tie_a\.site_code FROM apartment_memberships tie_am INNER JOIN apartments tie_a ON tie_a\.id = tie_am\.apartment_id WHERE tie_am\.user_code = u\.user_code AND tie_am\.is_active = TRUE AND tie_a\.is_active = TRUE/);
      assert.match(lookup.sql, /SELECT tie_r\.site_code FROM apartments tie_r WHERE tie_r\.resident_user_code = u\.user_code AND tie_r\.is_active = TRUE/);
      assert.match(lookup.sql, /EXISTS \(SELECT 1 FROM users tie_u WHERE tie_u\.user_code = u\.user_code AND tie_u\.is_active = TRUE\) AND \$2 IN \(/);
      assert.equal(/site_memberships|site_manager_sites/.test(lookup.sql), false, 'site_memberships (STAFF/BOARD_MEMBER/RESIDENT) ve yoneticilik TEK BASINA bag degildir');
      // eslemedeki LINK adimi AYNI yardimciyi kullanir (tek tanim)
      const link = SYNC_STEPS.find((step) => step.name === 'link_accountless').sql.replace(/\s+/g, ' ');
      assert.ok(link.includes(norm(siteTiePredicate('u.user_code', 'sp.site_code'))), 'LINK, ortak siteTiePredicate\'i kullanir');
    });

    it('baska sitenin kullanicisi: kisi HESAPSIZ kaydedilir (has_account false, alanlar CRM\'de), daire verilse bile uyelik/hesap bagi ACILMAZ, yanit sekli ayni', async () => {
      // dairenin sakin hesabi var -> hesap acma akisi da devreye girmez; e-posta baska sitenin kullanicisina ait olsa bile sonuc ayni
      handlers.push(
        [APARTMENT_LOOKUP, () => ok([{ ...APARTMENT_ROW, resident_user_code: 55555 }])],
        [APARTMENT_LOCKED, () => ok([{ ...APARTMENT_ROW, resident_user_code: 55555 }])],
        [RELATION_CHECK, () => ok()],
        [EMAIL_LOOKUP, () => ok()],
        [SITE_USER_LOOKUP, () => ok()], // baska sitenin kullanicisi: sorgu SITE KAPSAMLI oldugu icin donmez
        [PERSON_INSERT, () => ok([{ id: '5' }])],
        [RESIDENCY_INSERT, () => ok([{ id: '31' }])],
        ...detailHandlers(),
      );
      const result = await createPerson({ siteCode: SITE, input: input({ full_name: 'Ali Veli', email: 'baska.site@example.com', apartment_id: 9, relation: 'owner' }), actor });
      const insert = find(PERSON_INSERT);
      assert.equal(insert.params[1], null, 'user_code baglanmadi');
      assert.equal(insert.params[2], 'Ali Veli');
      assert.equal(insert.params[4], 'baska.site@example.com');
      assert.equal(has(/^INSERT INTO (apartment_memberships|site_memberships|users)/), false, 'baska siteden kullaniciya uyelik/hesap ACILMAZ');
      assert.equal(result.has_account, false);
      assert.equal(result.credentials_sent, null);
    });

    it('@ahbu.local (dahili) e-posta asla hesaba baglanmaz: kullanici sorgusu bile calismaz', async () => {
      handlers.push([EMAIL_LOOKUP, () => ok()], [PERSON_INSERT, () => ok([{ id: '5' }])], ...detailHandlers());
      await createPerson({ siteCode: SITE, input: input({ full_name: 'Ali Veli', email: 'daire5@ahbu.local' }), actor });
      assert.equal(has(SITE_USER_LOOKUP), false);
      assert.equal(find(PERSON_INSERT).params[1], null);
    });

    it('erisimi olan hesap: kisi o hesaba BAGLANIR; CRM ad/telefon/e-posta BOS (users\'tan okunur); daire verildiyse uyelik + site RESIDENT', async () => {
      handlers.push(
        [APARTMENT_LOOKUP, () => ok([APARTMENT_ROW])],
        [APARTMENT_LOCKED, () => ok([APARTMENT_ROW])],
        [RELATION_CHECK, () => ok()],
        [EMAIL_LOOKUP, () => ok()],
        [SITE_USER_LOOKUP, () => ok([{ user_code: 30001 }])],
        [PERSON_INSERT, () => ok([{ id: '5' }])],
        [RESIDENCY_INSERT, () => ok([{ id: '31' }])],
        [/^SELECT id FROM apartments WHERE id = \$1 FOR UPDATE$/, () => ok([{ id: '9' }])],
        [/^SELECT 1 FROM apartment_memberships WHERE apartment_id = \$1 AND role = 'APARTMENT_ADMIN'/, () => ok()],
        [/^INSERT INTO apartment_memberships/, () => ok()],
        [/^UPDATE apartments SET resident_user_code = \$1 WHERE id = \$2 AND resident_user_code IS NULL$/, () => ok()],
        [/^INSERT INTO site_memberships/, () => ok()],
        ...detailHandlers({ user_code: 30001, has_account: true, account_kind: 'registered', full_name: 'Ali Hesap' }),
      );
      await createPerson({ siteCode: SITE, input: input({ full_name: 'Ali Veli', phone: '0555 111 22 33', email: 'ali@example.com', apartment_id: 9, relation: 'owner' }), actor });
      const insert = find(PERSON_INSERT);
      assert.equal(insert.params[1], 30001, 'user_code baglandi');
      assert.equal(insert.params[2], null, 'ad CRM\'de bos (sozlesme)');
      assert.equal(insert.params[3], null, 'telefon CRM\'de bos');
      assert.equal(insert.params[4], null, 'hesapli kisinin e-postasi users\'tan okunur');
      const membership = find(/^INSERT INTO apartment_memberships/);
      assert.deepEqual(membership.params, [9, 30001, 'APARTMENT_ADMIN']);
      assert.equal(has(/INSERT INTO users/), false);
      assert.ok(log.filter((q) => /^INSERT INTO (apartment_memberships|site_memberships|apartment_residencies|site_people)/.test(q.sql)).every((q) => q.inTx));
    });
  });

  describe('H5: uyelik acarken APARTMENT_ADMIN kurali (mevcut onay akisiyla ayni)', () => {
    const wire = (otherAdmin) => [
      [APARTMENT_LOOKUP, () => ok([APARTMENT_ROW])],
      [APARTMENT_LOCKED, () => ok([APARTMENT_ROW])],
      [RELATION_CHECK, () => ok()],
      [EMAIL_LOOKUP, () => ok()],
      [SITE_USER_LOOKUP, () => ok([{ user_code: 30001 }])],
      [PERSON_INSERT, () => ok([{ id: '5' }])],
      [RESIDENCY_INSERT, () => ok([{ id: '31' }])],
      [/^SELECT id FROM apartments WHERE id = \$1 FOR UPDATE$/, () => ok([{ id: '9' }])],
      [/^SELECT 1 FROM apartment_memberships WHERE apartment_id = \$1 AND role = 'APARTMENT_ADMIN' AND is_active = TRUE AND user_code <> \$2/, () => (otherAdmin ? ok([{ x: 1 }]) : ok())],
      [/^INSERT INTO apartment_memberships/, () => ok()],
      [/^UPDATE apartments SET resident_user_code = \$1 WHERE id = \$2 AND resident_user_code IS NULL$/, () => ok()],
      [/^INSERT INTO site_memberships/, () => ok()],
      ...detailHandlers({ user_code: 30001, has_account: true, account_kind: 'registered' }),
    ];

    it('dairede aktif yonetici YOKSA: APARTMENT_ADMIN + gosterge (resident_user_code bossa) kisiye isaretlenir; daire satiri kilitlenir', async () => {
      handlers.push(...wire(false));
      await createPerson({ siteCode: SITE, input: input({ full_name: 'Ali Veli', email: 'ali@example.com', apartment_id: 9 }), actor });
      assert.deepEqual(find(/^INSERT INTO apartment_memberships/).params, [9, 30001, 'APARTMENT_ADMIN']);
      assert.deepEqual(find(/^UPDATE apartments SET resident_user_code = \$1 WHERE id = \$2 AND resident_user_code IS NULL$/).params, [30001, 9]);
      assert.deepEqual(find(/^SELECT 1 FROM apartment_memberships WHERE apartment_id = \$1 AND role = 'APARTMENT_ADMIN'/).params, [9, 30001]);
    });

    it('baska aktif yonetici VARSA: FAMILY_MEMBER (ikinci admin olusmaz, yeniden etkinlestirmede de rol ezilir)', async () => {
      handlers.push(...wire(true));
      await createPerson({ siteCode: SITE, input: input({ full_name: 'Ali Veli', email: 'ali@example.com', apartment_id: 9 }), actor });
      const membership = find(/^INSERT INTO apartment_memberships/);
      assert.deepEqual(membership.params, [9, 30001, 'FAMILY_MEMBER']);
      assert.match(membership.sql, /DO UPDATE SET role = \$3, is_active = TRUE/);
    });
  });

  it('kayitli ama BU SITEDE bagi olmayan kullanici + daire YOK: uyelik olusturulmaz (yalniz kayit)', async () => {
    handlers.push([EMAIL_LOOKUP, () => ok()], [SITE_USER_LOOKUP, () => ok()], [PERSON_INSERT, () => ok([{ id: '5' }])], ...detailHandlers());
    await createPerson({ siteCode: SITE, input: input({ full_name: 'Ali Veli', email: 'ali@example.com' }), actor });
    assert.equal(has(/^INSERT INTO apartment_memberships/), false);
  });

  describe('hesap yok + daire + e-posta: MEVCUT daire sakini hesabi akisi yeniden kullanilir (H9: ayni transaction)', () => {
    const sent = [];
    const savedEnv = {};
    const originalCreateTransport = nodemailer.createTransport;

    beforeEach(() => {
      sent.length = 0;
      for (const name of ['SMTP_HOST', 'SMTP_USER', 'SMTP_PASSWORD', 'SMTP_FROM', 'SMTP_PORT']) savedEnv[name] = process.env[name];
      process.env.SMTP_HOST = 'smtp.invalid';
      process.env.SMTP_USER = 'user@example.invalid';
      process.env.SMTP_PASSWORD = 'test-only';
      process.env.SMTP_FROM = 'Sistem <noreply@example.invalid>';
      delete process.env.SMTP_PORT;
      nodemailer.createTransport = () => ({ sendMail: async (message) => void sent.push(message) });
    });

    afterEach(() => {
      nodemailer.createTransport = originalCreateTransport;
      for (const [name, value] of Object.entries(savedEnv)) {
        if (value === undefined) delete process.env[name];
        else process.env[name] = value;
      }
    });

    function provisionHandlers({ residentUserCode = null } = {}) {
      handlers.push(
        [EMAIL_LOOKUP, () => ok()],
        [SITE_USER_LOOKUP, () => ok()],
        [APARTMENT_LOOKUP, () => ok([{ ...APARTMENT_ROW, resident_user_code: residentUserCode }])],
        [APARTMENT_LOCKED, () => ok([{ ...APARTMENT_ROW, resident_user_code: residentUserCode }])],
        [RELATION_CHECK, () => ok()],
        [/^SELECT a\.id, a\.site_code, a\.resident_user_code, a\.resident_email, b\.block_name, a\.unit_label, a\.sort_order FROM apartments a/, () => ok([{ id: '9', site_code: String(SITE), resident_user_code: null, resident_email: null, block_name: 'A Blok', unit_label: 'Daire 2', sort_order: 2 }])],
        [/^SELECT user_code FROM users WHERE LOWER\(login_name\)/, () => ok()],
        [/^INSERT INTO users/, () => ok([{ id: 40001, full_name: 'Ali Veli', email: 'x@ahbu.local', login_name: 'ln', role: 'apartment_owner' }])],
        [/^UPDATE apartments SET resident_user_code = \$1, resident_email = \$2, resident_pin_issued = TRUE, resident_pin_code = NULL, is_active = \$3 WHERE id = \$4$/, () => ok()],
        [/^SELECT a\.id, a\.site_code, a\.block_id, b\.block_name, a\.unit_label, a\.sort_order, a\.is_active, a\.resident_user_code/, () => ok([{ id: '9', site_code: String(SITE), resident_user_code: 40001 }])],
        [
          /^SELECT a\.id, a\.site_code, a\.unit_label, a\.resident_email, b\.block_name, s\.name AS site_name/,
          () => ok([{ id: '9', site_code: String(SITE), unit_label: 'Daire 2', resident_email: 'ali@example.com', block_name: 'A Blok', site_name: 'Gül Sitesi', resident_full_name: 'Ali Veli', resident_login_name: 'a.blok.2' }]),
        ],
        [PERSON_INSERT, () => ok([{ id: '5' }])],
        [RESIDENCY_INSERT, () => ok([{ id: '31' }])],
        ...detailHandlers({ user_code: 40001, has_account: true, account_kind: 'internal' }),
      );
    }

    it('hesap olusturulur, kisi o hesaba baglanir (iletisim e-postasi CRM\'de), hepsi TEK transaction; kimlik bilgileri gonderilir; credentials_sent true', async () => {
      provisionHandlers();
      const result = await createPerson({ siteCode: SITE, input: parsePersonCreateInput({ full_name: 'Ali Veli', email: 'ali@example.com', phone: '0555 111 22 33', apartment_id: 9, relation: 'owner' }), actor });

      const userInsert = find(/^INSERT INTO users/);
      assert.equal(userInsert.params[1].endsWith('@ahbu.local'), true, 'dahili daire hesabi e-postasi');
      assert.equal(userInsert.params[3], 'apartment_owner');
      assert.equal(userInsert.params[7], '+905551112233');
      assert.equal(userInsert.inTx, true, 'hesap, kisi kaydiyla AYNI transaction\'da');
      const aptUpdate = find(/^UPDATE apartments SET resident_user_code = \$1, resident_email = \$2/);
      assert.equal(aptUpdate.params[0], 40001);
      assert.equal(aptUpdate.params[1], 'ali@example.com');
      // Migration 051: PIN daire satirina YAZILMAZ (yalniz "PIN verildi" isareti); parametrelerde 4 haneli deger yok.
      assert.equal(aptUpdate.params.length, 4);
      assert.equal(aptUpdate.params.some((p) => /^\d{4}$/.test(String(p))), false, 'PIN duz metin saklanmaz');
      assert.equal(aptUpdate.inTx, true);
      assert.equal(log.filter((q) => q.sql === 'BEGIN').length, 1, 'tek BEGIN: provisionApartmentResident kendi transaction\'ini ACMAZ');
      assert.equal(log.filter((q) => q.sql === 'COMMIT').length, 1);

      const person = find(PERSON_INSERT);
      assert.equal(person.params[1], 40001);
      assert.equal(person.params[2], null, 'ad users\'ta');
      assert.equal(person.params[4], 'ali@example.com', 'dahili hesapta iletisim e-postasi yedek olarak CRM\'de');
      assert.equal(has(/^INSERT INTO apartment_memberships/), false, 'eski model: erisim apartments.resident_user_code ile');

      assert.equal(result.credentials_sent, true);
      assert.equal(result.credentials_email, 'ali@example.com');
      assert.equal(sent.length, 1);
      assert.equal(sent[0].to, 'ali@example.com');
      assert.match(sent[0].subject, /Daire giris bilgileriniz/);
      assert.match(sent[0].html, /a\.blok\.2/);
      // E-postadaki PIN, bu istekte uretilip yalniz users.password_hash'e (bcrypt) yazilan PIN'dir (veritabanindan okunmaz).
      const mailedPin = /<strong>PIN:<\/strong> (\d{4})/.exec(sent[0].html)?.[1];
      assert.match(String(mailedPin), /^\d{4}$/);
      assert.equal(await bcrypt.compare(mailedPin, userInsert.params[8]), true, 'e-postadaki PIN hesabin parola ozetiyle eslesir');
    });

    it('dairenin ZATEN bir sakin hesabi varsa: yeni hesap acilmaz/mevcut sakin ezilmez, yalniz kayit tutulur (has_account false)', async () => {
      provisionHandlers({ residentUserCode: 55555 });
      const result = await createPerson({ siteCode: SITE, input: parsePersonCreateInput({ full_name: 'Ali Veli', email: 'ali@example.com', apartment_id: 9 }), actor });
      assert.equal(has(/INSERT INTO users|^UPDATE apartments/), false);
      const person = find(PERSON_INSERT);
      assert.equal(person.params[1], null);
      assert.equal(person.params[4], 'ali@example.com');
      assert.equal(sent.length, 0);
      assert.equal(result.credentials_sent, null);
      assert.equal(result.credentials_email, null, 'hesap acilmadi');
    });

    it('e-posta yoksa hesap acilmaz (yalniz kayit)', async () => {
      provisionHandlers();
      await createPerson({ siteCode: SITE, input: parsePersonCreateInput({ full_name: 'Ali Veli', apartment_id: 9 }), actor });
      assert.equal(has(/INSERT INTO users/), false);
      assert.equal(find(PERSON_INSERT).params[1], null);
    });

    it('iliski dolu (malik zaten var): hesap acilmadan ONCE 409 RELATION_TAKEN', async () => {
      provisionHandlers();
      handlers.unshift([RELATION_CHECK, () => ok([{ id: '1' }])]);
      await assert.rejects(
        () => createPerson({ siteCode: SITE, input: parsePersonCreateInput({ full_name: 'Ali Veli', email: 'ali@example.com', apartment_id: 9, relation: 'owner' }), actor }),
        (error) => error.code === 'RELATION_TAKEN' && error.statusCode === 409,
      );
      assert.equal(has(/INSERT INTO users/), false);
      assert.equal(has(PERSON_INSERT), false);
    });

    it('H9: hesap actiktan SONRA bir adim dusarse (iliski 23505 yarisi) hesap da GERI ALINIR: COMMIT yok, ROLLBACK var, e-posta gitmez', async () => {
      provisionHandlers();
      handlers.unshift([
        RESIDENCY_INSERT,
        () => {
          throw Object.assign(new Error('duplicate key'), { code: '23505', constraint: 'uq_apartment_residencies_owner' });
        },
      ]);
      await assert.rejects(
        () => createPerson({ siteCode: SITE, input: parsePersonCreateInput({ full_name: 'Ali Veli', email: 'ali@example.com', apartment_id: 9, relation: 'owner' }), actor }),
        (error) => error.code === 'RELATION_TAKEN',
      );
      assert.ok(has(/^INSERT INTO users/), 'hesap transaction icinde olusturuldu');
      assert.equal(has(/^COMMIT$/), false);
      assert.ok(has(/^ROLLBACK$/), 'hesap + PIN + gosterge geri alinir');
      assert.equal(sent.length, 0, 'basarisiz islemde kimlik e-postasi gonderilmez');
    });

    it('e-posta gonderimi basarisiz olsa da kisi kaydi olusur; credentials_sent false (istemci bilgilendirilir)', async () => {
      provisionHandlers();
      nodemailer.createTransport = () => ({
        sendMail: async () => {
          throw new Error('SMTP reddetti');
        },
      });
      const result = await createPerson({ siteCode: SITE, input: parsePersonCreateInput({ full_name: 'Ali Veli', email: 'ali@example.com', apartment_id: 9 }), actor });
      assert.equal(has(PERSON_INSERT), true);
      assert.equal(result.credentials_sent, false);
      assert.equal(result.credentials_email, 'ali@example.com', 'gonderim denendi (hesap acildi)');
      // Gunluge yalniz kod yazilir (PIN / adres yok): sendIssuedApartmentPin.
      assert.ok(console.error.mock.calls.some((c) => String(c.arguments[0]).includes('[apartment] daire PIN e-postasi gonderilemedi')));
    });
  });

  it('yarista kaybeden ekleme (23505): iptal edilmis transaction\'da sorgu CALISTIRILMAZ, mevcut kisi havuzdan bulunur (409 + person_id)', async () => {
    let lookups = 0;
    handlers.push(
      [
        EMAIL_LOOKUP,
        () => {
          lookups += 1;
          return lookups === 1 ? ok() : ok([{ id: '8', is_active: true, user_code: null }]);
        },
      ],
      [SITE_USER_LOOKUP, () => ok()],
      [
        PERSON_INSERT,
        () => {
          txAborted = true;
          throw Object.assign(new Error('duplicate key'), { code: '23505', constraint: 'uq_site_people_email' });
        },
      ],
    );
    await assert.rejects(
      () => createPerson({ siteCode: SITE, input: parsePersonCreateInput({ full_name: 'Ali Veli', email: 'ali@example.com' }), actor }),
      (error) => error.code === 'PERSON_EXISTS' && error.statusCode === 409 && error.extra?.person_id === 8,
    );
    assert.equal(lookups, 2, 'ikinci arama ayri baglantidan (havuz) yapildi');
    assert.equal(log.filter((q) => EMAIL_LOOKUP.test(q.sql))[1].inTx, false);
    assert.ok(has(/^ROLLBACK$/));
  });

  it('H9: mevcut kisi bulunamazsa person_id:0 DONMEZ (genel 409, extra yok)', async () => {
    handlers.push(
      [EMAIL_LOOKUP, () => ok()],
      [SITE_USER_LOOKUP, () => ok()],
      [
        PERSON_INSERT,
        () => {
          txAborted = true;
          throw Object.assign(new Error('duplicate key'), { code: '23505', constraint: 'uq_site_people_email' });
        },
      ],
    );
    await assert.rejects(
      () => createPerson({ siteCode: SITE, input: parsePersonCreateInput({ full_name: 'Ali Veli', email: 'ali@example.com' }), actor }),
      (error) => error.code === 'PERSON_EXISTS' && error.extra === null,
    );
  });

  it('iliski tekil indeksi (malik/kiraci) 23505 -> 409 RELATION_TAKEN; ayni kisi/daire -> RESIDENCY_EXISTS', async () => {
    for (const [constraint, code] of [
      ['uq_apartment_residencies_owner', 'RELATION_TAKEN'],
      ['uq_apartment_residencies_tenant', 'RELATION_TAKEN'],
      ['uq_apartment_residencies_current', 'RESIDENCY_EXISTS'],
    ]) {
      install();
      handlers.length = 0;
      handlers.push(
        [APARTMENT_LOOKUP, () => ok([APARTMENT_ROW])],
        [APARTMENT_LOCKED, () => ok([APARTMENT_ROW])],
        [RELATION_CHECK, () => ok()],
        [PERSON_INSERT, () => ok([{ id: '5' }])],
        [
          RESIDENCY_INSERT,
          () => {
            throw Object.assign(new Error('duplicate key'), { code: '23505', constraint });
          },
        ],
      );
      await assert.rejects(
        () => createPerson({ siteCode: SITE, input: parsePersonCreateInput({ full_name: 'Ali Veli', apartment_id: 9, relation: 'owner' }), actor }),
        (error) => error.code === code,
        constraint,
      );
    }
  });
});

// ---------------------------------------------------------------------------
// updatePerson
// ---------------------------------------------------------------------------

describe('updatePerson', () => {
  const lock = /^SELECT sp\.id, sp\.user_code, sp\.full_name, sp\.phone, sp\.email, sp\.note, sp\.is_active, u\.email AS account_email, u\.is_active AS account_is_active, u\.full_name AS account_name, u\.phone_number AS account_phone FROM site_people sp LEFT JOIN users u ON u\.user_code = sp\.user_code WHERE sp\.id = \$1 AND sp\.site_code = \$2 FOR UPDATE OF sp$/;
  const accountRow = (extra = {}) => ({ id: '5', user_code: 30001, full_name: null, phone: null, email: null, note: null, is_active: true, account_email: 'ali@example.com', ...extra });
  const accountlessRow = (extra = {}) => ({ id: '5', user_code: null, full_name: 'Ali Veli', phone: '+905551112233', email: null, note: null, is_active: true, account_email: null, ...extra });

  it('GERCEK (e-postayla kayitli) hesapli kisi: full_name/phone/email gonderilirse 409 PERSON_HAS_ACCOUNT (yazma yok); alan ESIT olsa bile', async () => {
    handlers.push([lock, () => ok([accountRow()])]);
    for (const body of [{ full_name: 'Yeni Ad' }, { phone: '0555 111 22 33' }, { email: 'x@example.com' }, { full_name: 'A B', note: 'n' }]) {
      await assert.rejects(
        () => updatePerson({ siteCode: SITE, personId: 5, body, actor }),
        (error) => error.code === 'PERSON_HAS_ACCOUNT' && error.statusCode === 409 && error.message === 'Hesabı olan kişinin bilgileri kişinin kendi profilinden değişir.',
        JSON.stringify(body),
      );
    }
    assert.equal(has(/^UPDATE site_people/), false);
    assert.equal(has(/^INSERT INTO audit_log/), false);
  });

  it('H8: DAHILI (@ahbu.local) hesapta iletisim e-postasi DUZENLENEBILIR: apartments.resident_email + CRM kopyasi guncellenir; ad/telefon yine 409', async () => {
    handlers.push(
      [lock, () => ok([accountRow({ account_email: 'a-blok-2@ahbu.local', email: 'eski@example.com' })])],
      [/^SELECT resident_email FROM apartments WHERE resident_user_code = \$1 AND site_code = \$2 ORDER BY id LIMIT 1$/, () => ok([{ resident_email: 'guncel@example.com' }])],
      [EMAIL_LOOKUP, () => ok()],
      [/^UPDATE apartments SET resident_email = \$1 WHERE resident_user_code = \$2 AND site_code = \$3$/, () => ok()],
      [/^UPDATE site_people SET email = \$1, updated_at = NOW\(\) WHERE id = \$2 AND site_code = \$3$/, () => ok()],
      ...detailHandlers({ user_code: 30001, has_account: true, account_kind: 'internal' }),
    );
    await updatePerson({ siteCode: SITE, personId: 5, body: { email: 'yeni@example.com' }, actor });
    assert.deepEqual(find(/^UPDATE apartments SET resident_email/).params, ['yeni@example.com', 30001, SITE]);
    assert.deepEqual(find(/^UPDATE site_people SET email/).params, ['yeni@example.com', 5, SITE]);
    // gecmise DEGER yazilmaz (KVKK): yalniz degistigi
    assert.deepEqual(auditDetails('person.updated'), { changes: [{ field: 'email', changed: true }] });
    await assert.rejects(
      () => updatePerson({ siteCode: SITE, personId: 5, body: { full_name: 'Yeni Ad' }, actor }),
      (error) => error.code === 'PERSON_HAS_ACCOUNT',
    );
    await assert.rejects(
      () => updatePerson({ siteCode: SITE, personId: 5, body: { phone: '0555 111 22 33' }, actor }),
      (error) => error.code === 'PERSON_HAS_ACCOUNT',
    );
  });

  it('H8: dahili hesapta e-posta baska AKTIF kisiye aitse 409 PERSON_EXISTS; ayni e-posta degisiklik sayilmaz', async () => {
    handlers.push(
      [lock, () => ok([accountRow({ account_email: 'a-blok-2@ahbu.local' })])],
      [/^SELECT resident_email FROM apartments WHERE resident_user_code/, () => ok([{ resident_email: 'guncel@example.com' }])],
      [EMAIL_LOOKUP, () => ok([{ id: '9', is_active: true, user_code: null }])],
    );
    await assert.rejects(
      () => updatePerson({ siteCode: SITE, personId: 5, body: { email: 'baska@example.com' }, actor }),
      (error) => error.code === 'PERSON_EXISTS' && error.extra?.person_id === 9,
    );
  });

  it('T4: PASIF dahili (@ahbu.local) hesapli kisi HESAPSIZ davranir: once hesaptan koparilir (users ad/telefon + guncel iletisim e-postasi anlik kopyalanir), sonra ad/telefon duzenlenebilir (409 yok)', async () => {
    const dead = () => accountRow({ account_email: 'a-blok-2@ahbu.local', account_is_active: false, account_name: 'Ayse Sakin', account_phone: '+905551112233', email: 'eski@example.com' });
    const DETACH = /^UPDATE site_people SET user_code = NULL, full_name = \$2, phone = \$3, email = \$4, updated_at = NOW\(\) WHERE id = \$1$/;
    handlers.push(
      [lock, () => ok([dead()])],
      [/^SELECT resident_email FROM apartments WHERE resident_user_code = \$1 AND site_code = \$2 ORDER BY id LIMIT 1$/, () => ok([{ resident_email: 'guncel@example.com' }])],
      [DETACH, () => ok()],
      [/^UPDATE site_people SET full_name = \$1, phone = \$2, updated_at = NOW\(\) WHERE id = \$3 AND site_code = \$4$/, () => ok()],
      ...detailHandlers(),
    );
    await updatePerson({ siteCode: SITE, personId: 5, body: { full_name: 'Yeni Ad', phone: '0532 111 22 33' }, actor });
    assert.deepEqual(find(DETACH).params, ['5', 'Ayse Sakin', '+905551112233', 'guncel@example.com'], 'anlik kopya users + guncel iletisim e-postasi');
    assert.ok(indexOfQuery(DETACH) < indexOfQuery(/^UPDATE site_people SET full_name = \$1/), 'once koparma, sonra duzenleme');
    assert.deepEqual(auditDetails('person.updated').changes, [
      { field: 'full_name', from: 'Ayse Sakin', to: 'Yeni Ad' },
      { field: 'phone', changed: true },
    ]);
    assert.equal(has(/^UPDATE apartments SET resident_email/), false, 'hesapsiz kisi: iletisim e-postasi apartments uzerinden degil CRM kaydindan');

    // pasif GERCEK (e-postayla kayitli) hesap hesapsiz SAYILMAZ: hesabin kendisi sahip, 409
    install();
    handlers.length = 0;
    handlers.push([lock, () => ok([accountRow({ account_email: 'ali@example.com', account_is_active: false })])]);
    await assert.rejects(() => updatePerson({ siteCode: SITE, personId: 5, body: { full_name: 'Yeni Ad' }, actor }), (e) => e.code === 'PERSON_HAS_ACCOUNT');
    assert.equal(has(/^UPDATE site_people SET user_code = NULL/), false);

    // AKTIF dahili hesap hesapli kalir (ad/telefon 409)
    install();
    handlers.length = 0;
    handlers.push([lock, () => ok([accountRow({ account_email: 'a-blok-2@ahbu.local', account_is_active: true })])]);
    await assert.rejects(() => updatePerson({ siteCode: SITE, personId: 5, body: { phone: '0532 111 22 33' }, actor }), (e) => e.code === 'PERSON_HAS_ACCOUNT');
    assert.equal(has(/^UPDATE site_people SET user_code = NULL/), false);
  });

  it('HESAPLI kisi: note ve is_active her zaman degisir; audit person.updated details.changes (not icin yalniz changed:true, DEGER yok)', async () => {
    handlers.push([lock, () => ok([accountRow({ note: 'eski' })])], [/^UPDATE site_people SET note = \$1, updated_at = NOW\(\) WHERE id = \$2 AND site_code = \$3$/, () => ok()], ...detailHandlers());
    await updatePerson({ siteCode: SITE, personId: 5, body: { note: 'yeni not' }, actor });
    assert.deepEqual(find(/^UPDATE site_people SET note/).params, ['yeni not', 5, SITE]);
    assert.deepEqual(auditDetails('person.updated'), { changes: [{ field: 'note', changed: true }] });
  });

  it('H11: HESAPSIZ kisi: ad degeri from/to ile, telefon/e-posta/not yalniz changed:true (eski/yeni DEGER saklanmaz); degisiklik yoksa audit yok', async () => {
    handlers.push(
      [lock, () => ok([accountlessRow()])],
      [EMAIL_LOOKUP, () => ok()],
      [/^UPDATE site_people SET full_name = \$1, phone = \$2, email = \$3, note = \$4/, () => ok()],
      ...detailHandlers(),
    );
    await updatePerson({ siteCode: SITE, personId: 5, body: { full_name: 'Ali Veli Kaya', phone: '0532 111 22 33', email: 'ali@example.com', note: 'ozel' }, actor });
    assert.deepEqual(auditDetails('person.updated').changes, [
      { field: 'full_name', from: 'Ali Veli', to: 'Ali Veli Kaya' },
      { field: 'phone', changed: true },
      { field: 'email', changed: true },
      { field: 'note', changed: true },
    ]);
    const serialized = JSON.stringify(auditDetails('person.updated'));
    for (const secret of ['5321112233', '5551112233', 'ali@example.com', 'ozel']) {
      assert.equal(serialized.includes(secret), false, `${secret} gecmise yazilmamali`);
    }
    install();
    handlers.length = 0;
    handlers.push([lock, () => ok([accountlessRow()])], ...detailHandlers());
    await updatePerson({ siteCode: SITE, personId: 5, body: { full_name: 'Ali Veli' }, actor });
    assert.equal(has(/^INSERT INTO audit_log/), false);
  });

  it('e-posta baska AKTIF kisiye aitse 409 PERSON_EXISTS', async () => {
    handlers.push([lock, () => ok([accountlessRow()])], [EMAIL_LOOKUP, () => ok([{ id: '9', is_active: true, user_code: null }])]);
    await assert.rejects(
      () => updatePerson({ siteCode: SITE, personId: 5, body: { email: 'baska@example.com' }, actor }),
      (error) => error.code === 'PERSON_EXISTS' && error.extra?.person_id === 9,
    );
  });

  it('kisi yok 404 PERSON_NOT_FOUND (site kapsamli kilit)', async () => {
    handlers.push([lock, () => ok()]);
    await assert.rejects(() => updatePerson({ siteCode: SITE, personId: 5, body: { note: 'x' }, actor }), (e) => e.code === 'PERSON_NOT_FOUND');
    assert.deepEqual(find(lock).params, [5, SITE]);
  });

  it('is_active:true pasif kisiyi yeniden etkinlestirir (audit person.updated is_active false->true)', async () => {
    handlers.push([lock, () => ok([accountlessRow({ is_active: false })])], [/^UPDATE site_people SET is_active = TRUE, updated_at = NOW\(\) WHERE id = \$1$/, () => ok()], ...detailHandlers());
    await updatePerson({ siteCode: SITE, personId: 5, body: { is_active: true }, actor });
    assert.deepEqual(auditDetails('person.updated'), { changes: [{ field: 'is_active', from: false, to: true }] });
  });
});

// ---------------------------------------------------------------------------
// Iliskiler: ekle / guncelle
// ---------------------------------------------------------------------------

describe('iliskiler: ekle / guncelle', () => {
  const personLock = /^SELECT id, user_code, is_active, email FROM site_people WHERE id = \$1 AND site_code = \$2 FOR UPDATE$/;
  const residencyLookup = /FROM apartment_residencies r INNER JOIN site_people sp ON sp\.id = r\.person_id WHERE r\.id = \$1 AND sp\.site_code = \$2 LIMIT 1 FOR UPDATE OF r$/;
  const DUPLICATE = /^SELECT id FROM apartment_residencies WHERE apartment_id = \$1 AND person_id = \$2 AND is_current = TRUE LIMIT 1$/;
  const USABLE_TIE = /^SELECT u\.user_code FROM users u WHERE u\.user_code = \$1 AND u\.is_active = TRUE AND \(/;
  const ACTIVATE = /^UPDATE site_people SET is_active = TRUE, updated_at = NOW\(\) WHERE id = \$1$/;
  const apartmentHandlers = () => [
    [APARTMENT_LOOKUP, () => ok([APARTMENT_ROW])],
    [APARTMENT_LOCKED, () => ok([APARTMENT_ROW])],
  ];
  const grantHandlers = () => [
    [/^SELECT id FROM apartments WHERE id = \$1 FOR UPDATE$/, () => ok([{ id: '9' }])],
    [/^SELECT 1 FROM apartment_memberships WHERE apartment_id = \$1 AND role = 'APARTMENT_ADMIN'/, () => ok([{ x: 1 }])],
    [/^INSERT INTO apartment_memberships/, () => ok()],
    [/^UPDATE apartments SET resident_user_code = \$1 WHERE id = \$2 AND resident_user_code IS NULL$/, () => ok()],
    [/^INSERT INTO site_memberships/, () => ok()],
  ];

  it('addResidency: KILIT SIRASI daire satiri kisi satirindan ONCE; hesapli + sitede bagi olan kisiye daire uyeligi acilir (admin kurali); pasif kisi yeniden etkinlesir; residency.added', async () => {
    handlers.push(
      ...apartmentHandlers(),
      [personLock, () => ok([{ id: '5', user_code: 30001, is_active: false, email: null }])],
      [USABLE_TIE, () => ok([{ user_code: 30001 }])],
      [DUPLICATE, () => ok()],
      [RELATION_CHECK, () => ok()],
      [RESIDENCY_INSERT, () => ok([{ id: '31' }])],
      [ACTIVATE, () => ok()],
      ...grantHandlers(),
      ...detailHandlers({ user_code: 30001, has_account: true, account_kind: 'registered' }),
    );
    await addResidency({ siteCode: SITE, personId: 5, body: { apartment_id: 9, relation: 'tenant', move_in_date: '2026-01-02' }, actor });
    assert.ok(indexOfQuery(APARTMENT_LOCKED) < indexOfQuery(personLock), 'apartments -> site_people kilit sirasi');
    assert.deepEqual(find(RESIDENCY_INSERT).params, [SITE, 9, 5, 'tenant', '2026-01-02']);
    assert.deepEqual(find(/^INSERT INTO apartment_memberships/).params, [9, 30001, 'FAMILY_MEMBER']);
    assert.deepEqual(find(USABLE_TIE).params, [30001, SITE]);
    assert.deepEqual(auditActions(), ['person.updated', 'residency.added']);
  });

  it('S2a: hesaba bagli ama bu sitede BAGI OLMAYAN (veya hesabi pasif) kisi: iliski yalniz CRM kaydi olarak eklenir, ERISIM VERILMEZ (uyelik/gosterge/site uyeligi yok)', async () => {
    handlers.push(
      ...apartmentHandlers(),
      [personLock, () => ok([{ id: '5', user_code: 30001, is_active: true, email: null }])],
      [USABLE_TIE, () => ok()],
      [DUPLICATE, () => ok()],
      [RELATION_CHECK, () => ok()],
      [RESIDENCY_INSERT, () => ok([{ id: '31' }])],
      ...detailHandlers(),
    );
    await addResidency({ siteCode: SITE, personId: 5, body: { apartment_id: 9, relation: 'tenant' }, actor });
    assert.equal(has(/^INSERT INTO (apartment_memberships|site_memberships)/), false);
    assert.equal(has(/^UPDATE apartments/), false);
    assert.deepEqual(auditActions(), ['residency.added']);
  });

  it('S5: pasif kisi etkinlestirilirken e-postasi baska AKTIF kisiye aitse 409 PERSON_EXISTS (+ gercek person_id), ham 500 degil; 23505 de ayni sekilde eslenir', async () => {
    const base = () => [
      ...apartmentHandlers(),
      [personLock, () => ok([{ id: '5', user_code: null, is_active: false, email: 'ortak@example.com' }])],
      [DUPLICATE, () => ok()],
      [RELATION_CHECK, () => ok()],
      [RESIDENCY_INSERT, () => ok([{ id: '31' }])],
    ];
    handlers.push(...base(), [EMAIL_LOOKUP, () => ok([{ id: '9', is_active: true, user_code: null }])]);
    await assert.rejects(
      () => addResidency({ siteCode: SITE, personId: 5, body: { apartment_id: 9 }, actor }),
      (e) => e.code === 'PERSON_EXISTS' && e.statusCode === 409 && e.extra?.person_id === 9,
    );
    assert.equal(has(ACTIVATE), false, 'cakisma varken etkinlestirme denenmedi');

    // on kontrolu atlayan yaris: UPDATE 23505 verir -> yine 409 + havuzdan bulunan person_id
    install();
    handlers.length = 0;
    let lookups = 0;
    handlers.push(
      ...base(),
      [
        EMAIL_LOOKUP,
        () => {
          lookups += 1;
          return lookups === 1 ? ok() : ok([{ id: '9', is_active: true, user_code: null }]);
        },
      ],
      [
        ACTIVATE,
        () => {
          txAborted = true;
          throw Object.assign(new Error('duplicate key'), { code: '23505', constraint: 'uq_site_people_email' });
        },
      ],
    );
    await assert.rejects(
      () => addResidency({ siteCode: SITE, personId: 5, body: { apartment_id: 9 }, actor }),
      (e) => e.code === 'PERSON_EXISTS' && e.extra?.person_id === 9,
    );
  });

  it('addResidency: ayni kisi/daire zaten guncel -> 409 RESIDENCY_EXISTS; dolu malik/kiraci -> 409 RELATION_TAKEN; baska sitenin dairesi 404', async () => {
    handlers.push(...apartmentHandlers(), [personLock, () => ok([{ id: '5', user_code: null, is_active: true, email: null }])], [DUPLICATE, () => ok([{ id: '1' }])]);
    await assert.rejects(() => addResidency({ siteCode: SITE, personId: 5, body: { apartment_id: 9 }, actor }), (e) => e.code === 'RESIDENCY_EXISTS' && e.statusCode === 409);

    install();
    handlers.length = 0;
    handlers.push(...apartmentHandlers(), [personLock, () => ok([{ id: '5', user_code: null, is_active: true, email: null }])], [DUPLICATE, () => ok()], [RELATION_CHECK, () => ok([{ id: '2' }])]);
    await assert.rejects(
      () => addResidency({ siteCode: SITE, personId: 5, body: { apartment_id: 9, relation: 'owner' }, actor }),
      (e) => e.code === 'RELATION_TAKEN' && e.message === 'Bu dairede bu ilişki için aktif bir kişi zaten var.',
    );

    install();
    handlers.length = 0;
    handlers.push([APARTMENT_LOOKUP, () => ok()]);
    await assert.rejects(() => addResidency({ siteCode: SITE, personId: 5, body: { apartment_id: 77 }, actor }), (e) => e.code === 'APARTMENT_NOT_FOUND');
    assert.equal(has(/^BEGIN/), false, 'baska sitenin dairesi islem acmadan 404');
  });

  it('T7: addResidency kisi yok / baska sitenin kisisi / gecersiz id -> 404 PERSON_NOT_FOUND (daire kilidi sonrasi site kapsamli kisi kilidi; yazma yok)', async () => {
    handlers.push(...apartmentHandlers(), [personLock, () => ok()]);
    await assert.rejects(
      () => addResidency({ siteCode: SITE, personId: 5, body: { apartment_id: 9, relation: 'tenant' }, actor }),
      (e) => e.code === 'PERSON_NOT_FOUND' && e.statusCode === 404,
    );
    assert.deepEqual(find(personLock).params, [5, SITE], 'kisi YALNIZ bu sitenin kapsaminda aranir');
    assert.ok(indexOfQuery(APARTMENT_LOCKED) < indexOfQuery(personLock), 'apartments -> site_people kilit sirasi');
    assert.equal(has(/^INSERT INTO apartment_residencies/), false);
    assert.equal(has(/^INSERT INTO audit_log/), false);
    assert.equal(has(/^COMMIT/), false, 'hata varken islem onaylanmaz');

    // gecersiz kisi kimligi islem/sorgu acmadan 404
    install();
    handlers.length = 0;
    await assert.rejects(
      () => addResidency({ siteCode: SITE, personId: 'abc', body: { apartment_id: 9 }, actor }),
      (e) => e.code === 'PERSON_NOT_FOUND' && e.statusCode === 404,
    );
    assert.equal(has(/^BEGIN/), false);
  });

  it('updateResidency: relation degisimi RELATION_TAKEN kontrolunde KENDISINI haric tutar; audit residency.updated changes', async () => {
    handlers.push(
      [residencyLookup, () => ok([{ id: '31', apartment_id: '9', person_id: '5', relation: 'resident', is_current: true, move_in_date: '2025-01-01', move_out_date: null, user_code: null }])],
      [RELATION_CHECK, () => ok()],
      [/^UPDATE apartment_residencies SET relation = \$1, move_in_date = \$2, origin = 'manual', updated_at = NOW\(\) WHERE id = \$3$/, () => ok()],
      ...detailHandlers(),
    );
    await updateResidency({ siteCode: SITE, residencyId: 31, body: { relation: 'owner', move_in_date: '2025-02-01' }, actor });
    assert.deepEqual(find(RELATION_CHECK).params, [9, 'owner', 31]);
    assert.deepEqual(auditDetails('residency.updated'), {
      residency_id: 31,
      apartment_id: 9,
      changes: [
        { field: 'relation', from: 'resident', to: 'owner' },
        { field: 'move_in_date', from: '2025-01-01', to: '2025-02-01' },
      ],
    });
  });

  it('updateResidency: degisiklik yoksa audit yok; giris tarihi cikis tarihinden sonra 400; yok kayit 404', async () => {
    handlers.push(
      [residencyLookup, () => ok([{ id: '31', apartment_id: '9', person_id: '5', relation: 'owner', is_current: false, move_in_date: '2025-01-01', move_out_date: '2025-06-30', user_code: null }])],
      ...detailHandlers(),
    );
    await updateResidency({ siteCode: SITE, residencyId: 31, body: { relation: 'owner' }, actor });
    assert.equal(has(/^INSERT INTO audit_log/), false);
    await assert.rejects(() => updateResidency({ siteCode: SITE, residencyId: 31, body: { move_in_date: '2025-07-01' }, actor }), (e) => e.code === 'INVALID_BODY' && /move_in_date/.test(e.message));
    install();
    handlers.length = 0;
    handlers.push([residencyLookup, () => ok()]);
    await assert.rejects(() => updateResidency({ siteCode: SITE, residencyId: 31, body: { relation: 'owner' }, actor }), (e) => e.code === 'RESIDENCY_NOT_FOUND');
    assert.deepEqual(find(residencyLookup).params, [31, SITE]);
  });
});

// ---------------------------------------------------------------------------
// Daire alanlari
// ---------------------------------------------------------------------------

describe('updateApartment', () => {
  const lockApartment = /^SELECT floor, land_share_numerator, land_share_denominator, category, responsible_party FROM apartments WHERE id = \$1 AND site_code = \$2 FOR UPDATE$/;
  const row = (extra = {}) => ({ floor: 2, gross_area_m2: '120.50', net_area_m2: null, land_share_numerator: null, land_share_denominator: null, category: null, responsible_party: 'both', ...extra });
  // ApartmentDetail yuklemesi (yazma sonrasi donen yanit): acikca tanimli - kati sahte DB hicbir sorguyu sessizce yutmaz
  const detailHandlers = () => [
    [/^SELECT a\.id, a\.unit_label, a\.block_id, b\.block_name[\s\S]*WHERE a\.id = \$1 AND a\.site_code = \$2 LIMIT 1$/, () => ok([{ id: '9', unit_label: 'Daire 2', block_id: '3', block_name: 'A Blok', floor: 3, category: '3+1', gross_area_m2: '120.50', net_area_m2: null, land_share_numerator: 35, land_share_denominator: 1000, responsible_party: 'both' }])],
    [/FROM apartment_residencies r INNER JOIN site_people sp ON sp\.id = r\.person_id LEFT JOIN users u ON u\.user_code = sp\.user_code WHERE r\.apartment_id = ANY\(\$1::BIGINT\[\]\)/, () => ok()],
  ];

  it('degisen alanlar UPDATE edilir, audit apartment.updated details.changes (from/to); mevcut unit_label/blok yapisina dokunulmaz', async () => {
    handlers.push([lockApartment, () => ok([row()])], [/^UPDATE apartments SET floor/, () => ok()], ...detailHandlers());
    const result = await updateApartment({ siteCode: SITE, apartmentId: 9, body: { floor: 3, gross_area_m2: 120.5, category: '3+1', land_share_numerator: 35, land_share_denominator: 1000 }, actor });
    assert.equal(result.floor, 3);
    assert.deepEqual(result.land_share, { numerator: 35, denominator: 1000 });
    const update = find(/^UPDATE apartments SET/);
    assert.match(update.sql, /^UPDATE apartments SET floor = \$1, land_share_numerator = \$2, land_share_denominator = \$3, category = \$4 WHERE id = \$5$/);
    assert.deepEqual(update.params, [3, 35, 1000, '3+1', 9]);
    assert.equal(/unit_label|block_id|sort_order|is_active|resident_/.test(update.sql), false);
    assert.deepEqual(auditDetails('apartment.updated').changes, [
      { field: 'floor', from: 2, to: 3 },
      { field: 'land_share_numerator', from: null, to: 35 },
      { field: 'land_share_denominator', from: null, to: 1000 },
      { field: 'category', from: null, to: '3+1' },
    ]);
    const audit = findAll(/^INSERT INTO audit_log/)[0];
    assert.equal(audit.params[5], 'apartment');
    assert.equal(audit.params[6], '9');
    assert.equal(audit.params[4], SITE);
  });

  it('degisiklik yoksa UPDATE ve audit yok; yok / baska sitenin dairesi 404; tek yanli arsa payi 400', async () => {
    handlers.push([lockApartment, () => ok([row({ land_share_numerator: 35, land_share_denominator: 1000 })])], ...detailHandlers());
    await updateApartment({ siteCode: SITE, apartmentId: 9, body: { floor: 2, responsible_party: 'both' }, actor });
    assert.equal(has(/^UPDATE apartments/), false);
    assert.equal(has(/^INSERT INTO audit_log/), false);
    // payda silinip pay kalamaz
    await assert.rejects(() => updateApartment({ siteCode: SITE, apartmentId: 9, body: { land_share_denominator: null }, actor }), (e) => e.code === 'INVALID_BODY' && /land_share/.test(e.message));
    install();
    handlers.length = 0;
    handlers.push([lockApartment, () => ok()]);
    await assert.rejects(() => updateApartment({ siteCode: SITE, apartmentId: 77, body: { floor: 1 }, actor }), (e) => e.code === 'APARTMENT_NOT_FOUND');
    assert.deepEqual(find(lockApartment).params, [77, SITE]);
  });
});

// ---------------------------------------------------------------------------
// Araclar
// ---------------------------------------------------------------------------

describe('araclar', () => {
  const personExists = /^SELECT id FROM site_people WHERE id = \$1 AND site_code = \$2 LIMIT 1$/;
  const plateCheck = /^SELECT id FROM vehicles WHERE site_code = \$1 AND plate = \$2 AND is_active = TRUE LIMIT 1$/;
  const VEHICLE_ROW = /FROM vehicles v LEFT JOIN site_people sp ON sp\.id = v\.person_id[\s\S]*WHERE v\.id = \$1/;

  it('createVehicle: plaka normalize (34 abc 123 -> 34ABC123), vehicle.added audit, site kilidi altinda', async () => {
    handlers.push([personExists, () => ok([{ id: '5' }])], [plateCheck, () => ok()], [/^INSERT INTO vehicles/, () => ok([{ id: '4' }])], [VEHICLE_ROW, () => ok([{ id: '4', plate: '34ABC123', plate_display: '34 ABC 123', note: 'beyaz', person_id: '5', is_active: true, person_name: 'Ali Veli', block_name: null, unit_label: null }])]);
    await createVehicle({ siteCode: SITE, body: { person_id: 5, plate: '34 abc 123', note: ' beyaz ' }, actor });
    assert.deepEqual(find(/^INSERT INTO vehicles/).params, [SITE, 5, '34ABC123', '34 ABC 123', 'beyaz']);
    assert.deepEqual(auditDetails('vehicle.added'), { plate: '34ABC123', person_id: 5 });
    const audit = findAll(/^INSERT INTO audit_log/)[0];
    assert.equal(audit.params[5], 'vehicle');
    assert.equal(audit.params[6], '4');
    assert.equal(log[1].params[0], `people_sync:${SITE}`);
  });

  it('ayni sitede aktif ayni plaka 409 PLATE_EXISTS (on kontrol ve 23505 yarisi); kisi yok 404; plaka gecersiz 400 PLATE_INVALID', async () => {
    handlers.push([personExists, () => ok([{ id: '5' }])], [plateCheck, () => ok([{ id: '1' }])]);
    await assert.rejects(
      () => createVehicle({ siteCode: SITE, body: { person_id: 5, plate: '34ABC123' }, actor }),
      (e) => e.code === 'PLATE_EXISTS' && e.statusCode === 409 && e.message === 'Bu plaka bu sitede zaten kayıtlı.',
    );
    install();
    handlers.length = 0;
    handlers.push(
      [personExists, () => ok([{ id: '5' }])],
      [plateCheck, () => ok()],
      [
        /^INSERT INTO vehicles/,
        () => {
          throw Object.assign(new Error('duplicate'), { code: '23505' });
        },
      ],
    );
    await assert.rejects(() => createVehicle({ siteCode: SITE, body: { person_id: 5, plate: '34ABC123' }, actor }), (e) => e.code === 'PLATE_EXISTS');
    install();
    handlers.length = 0;
    handlers.push([personExists, () => ok()]);
    await assert.rejects(() => createVehicle({ siteCode: SITE, body: { person_id: 5, plate: '34ABC123' }, actor }), (e) => e.code === 'PERSON_NOT_FOUND');
    assert.deepEqual(find(personExists).params, [5, SITE], 'baska sitenin kisisine arac eklenemez');
    await assert.rejects(() => createVehicle({ siteCode: SITE, body: { person_id: 5, plate: '??' }, actor }), (e) => e.code === 'PLATE_INVALID');
  });

  it('removeVehicle: is_active=false (kayit KALIR), vehicle.removed audit; yok / zaten kaldirilmis 404', async () => {
    handlers.push(
      [/^SELECT id, plate, person_id FROM vehicles WHERE id = \$1 AND site_code = \$2 AND is_active = TRUE FOR UPDATE$/, () => ok([{ id: '4', plate: '34ABC123', person_id: '5' }])],
      [/^UPDATE vehicles SET is_active = FALSE WHERE id = \$1$/, () => ok()],
    );
    assert.deepEqual(await removeVehicle({ siteCode: SITE, vehicleId: 4, actor }), { ok: true });
    assert.deepEqual(find(/^UPDATE vehicles SET is_active = FALSE WHERE id = \$1$/).params, [4]);
    assert.equal(has(/DELETE FROM vehicles/), false);
    assert.deepEqual(auditDetails('vehicle.removed'), { plate: '34ABC123', person_id: 5 });
    install();
    handlers.length = 0;
    handlers.push([/^SELECT id, plate, person_id FROM vehicles WHERE id = \$1 AND site_code = \$2 AND is_active = TRUE FOR UPDATE$/, () => ok()]);
    await assert.rejects(() => removeVehicle({ siteCode: SITE, vehicleId: 4, actor }), (e) => e.code === 'VEHICLE_NOT_FOUND' && e.statusCode === 404);
  });
});

// ---------------------------------------------------------------------------
// provisionPersonAccount and resetPersonPinDirect
// ---------------------------------------------------------------------------

describe('evaluateManagedAccount: yonetimin sifre / kullanici adi degistirebilecegi hesap (SAF karar)', () => {
  const account = (extra = {}) => ({
    role: 'apartment_owner',
    email: 'sakin.5.1000000001@ahbu.local',
    deleted_at: null,
    must_change_password: false,
    pin_issued: true,
    is_manager: false,
    foreign_membership: false,
    foreign_apartment: false,
    foreign_person: false,
    ...extra,
  });

  it('yonetimce acilmis sakin hesabi (dahili e-posta + PIN verildi) izinli; yonetici de super de', () => {
    assert.equal(evaluateManagedAccount(account()), null);
    assert.equal(evaluateManagedAccount(account(), { actorIsSuper: true }), null);
  });

  it('gercek e-postali hesap yalniz verilmis parola hala degismediyse (must_change_password ya da PIN isareti) izinli', () => {
    assert.equal(evaluateManagedAccount(account({ email: 'ali@example.com', pin_issued: false, must_change_password: true })), null);
    assert.equal(evaluateManagedAccount(account({ email: 'ali@example.com', pin_issued: true, must_change_password: false })), null);
    // kendi kaydolan / parolasini kendi belirleyen gercek hesap: kimse (super dahil) sifirlayamaz -> "Sifremi unuttum"
    assert.equal(evaluateManagedAccount(account({ email: 'ali@example.com', pin_issued: false, must_change_password: false })), 'PERSON_ACCOUNT_NOT_MANAGEABLE');
    assert.equal(evaluateManagedAccount(account({ email: 'ali@example.com', pin_issued: false }), { actorIsSuper: true }), 'PERSON_ACCOUNT_NOT_MANAGEABLE');
  });

  it('dahili hesapta sakin parolasini kendisi belirlediyse (isaret yok) yalniz super kullanici sifirlar (resetApartmentPin kurali)', () => {
    const chosen = account({ pin_issued: false, must_change_password: false });
    assert.equal(evaluateManagedAccount(chosen), 'PERSON_ACCOUNT_RESET_NEEDS_SUPER');
    assert.equal(evaluateManagedAccount(chosen, { actorIsSuper: false }), 'PERSON_ACCOUNT_RESET_NEEDS_SUPER');
    assert.equal(evaluateManagedAccount(chosen, { actorIsSuper: true }), null);
  });

  it('rol apartment_owner disindaki hesap (yonetici / bireysel / super) ve silinmis ya da olmayan hesap ASLA', () => {
    for (const role of ['site_manager', 'individual', 'super_user']) {
      assert.equal(evaluateManagedAccount(account({ role }), { actorIsSuper: true }), 'PERSON_ACCOUNT_NOT_MANAGEABLE', role);
    }
    assert.equal(evaluateManagedAccount(account({ deleted_at: new Date() })), 'PERSON_ACCOUNT_NOT_MANAGEABLE');
    assert.equal(evaluateManagedAccount(null), 'PERSON_ACCOUNT_NOT_MANAGEABLE');
  });

  it('baska siteye ya da role bagli hesap (yoneticilik, RESIDENT disi rol / baska site uyeligi, baska sitede daire / kisi kaydi) ASLA', () => {
    for (const tie of ['is_manager', 'foreign_membership', 'foreign_apartment', 'foreign_person']) {
      assert.equal(evaluateManagedAccount(account({ [tie]: true }), { actorIsSuper: true }), 'PERSON_ACCOUNT_NOT_MANAGEABLE', tie);
    }
  });
});

describe('provisionPersonAccount and resetPersonPinDirect', () => {
  const personLock = /SELECT sp\.id, sp\.site_code, sp\.user_code, sp\.full_name/;
  const resetPersonLock = /SELECT sp\.id, sp\.user_code, u\.login_name FROM site_people sp/;
  const loginCheck = /^SELECT user_code FROM users WHERE LOWER\(login_name\) = LOWER/;
  const emailCheck = /^SELECT 1 FROM users WHERE LOWER\(email\) = \$1 LIMIT 1$/;
  const userInsert = /^INSERT INTO users/;
  const updatePersonSql = /^UPDATE site_people SET user_code =/;
  const currentApts = /^SELECT ar\.apartment_id FROM apartment_residencies ar WHERE ar\.person_id = \$1 AND ar\.is_current = TRUE ORDER BY/;
  const aptLock = /^SELECT id FROM apartments WHERE id = \$1 FOR UPDATE$/;
  const otherAdmin = /^SELECT 1 FROM apartment_memberships WHERE apartment_id = \$1 AND role = 'APARTMENT_ADMIN'/;
  const aptMembership = /^INSERT INTO apartment_memberships/;
  const aptIndicator = /^UPDATE apartments SET resident_user_code = \$1 WHERE id = \$2 AND resident_user_code IS NULL$/;
  const siteMembership = /^INSERT INTO site_memberships/;
  const aptPinMark = /^UPDATE apartments SET resident_pin_issued = TRUE, resident_pin_code = NULL, is_active = TRUE WHERE id = \$1 AND resident_user_code = \$2$/;
  const residentAptsLock = /^SELECT id FROM apartments WHERE resident_user_code = \$1 ORDER BY id FOR UPDATE$/;
  const accountLookup = /FROM users u WHERE u\.user_code = \$1 AND u\.deleted_at IS NULL FOR UPDATE OF u$/;
  const passwordUpdate = /^UPDATE users SET password_hash = \$1, login_name = COALESCE\(\$2, login_name\), must_change_password = TRUE, updated_at = NOW\(\) WHERE user_code = \$3 AND deleted_at IS NULL RETURNING user_code, login_name, email$/;
  const pinFlagMark = /^UPDATE apartments SET resident_pin_issued = TRUE, resident_pin_code = NULL WHERE resident_user_code = \$1$/;
  const guestPasses = /^UPDATE guest_passes SET is_active = FALSE WHERE created_by_user_code = \$1 AND is_active = TRUE$/;
  const qrTokens = /^UPDATE qr_access_tokens SET is_active = FALSE, revoked_at = NOW\(\)/;
  const pushTables = /^SELECT to_regclass\('public\.push_devices'\) IS NOT NULL AS has_devices/;
  const webPushTable = /^SELECT to_regclass\('public\.web_push_subscriptions'\) IS NOT NULL AS ok$/;

  const accountRow = (extra = {}) => ({
    user_code: 44001,
    role: 'apartment_owner',
    email: 'salih.ceylan.5.1000000001@ahbu.local',
    login_name: 'salih.ceylan',
    must_change_password: true,
    deleted_at: null,
    pin_issued: true,
    is_manager: false,
    foreign_membership: false,
    foreign_apartment: false,
    foreign_person: false,
    ...extra,
  });

  /** Yeni hesap akisi: kisi + (isteğe bagli) daire iliskileri. */
  function newAccountHandlers({ person = {}, apartments = ['9'], otherAdminExists = false, emailTaken = false } = {}) {
    handlers.push(
      [personLock, () => ok([{ id: '5', site_code: SITE, user_code: null, full_name: 'Salih Ceylan', phone: '05551112233', email: null, is_active: true, ...person }])],
      [loginCheck, () => ok([])],
      [emailCheck, () => (emailTaken ? ok([{ '?column?': 1 }]) : ok())],
      [userInsert, () => ok([{ user_code: '44001' }])],
      [updatePersonSql, () => ok()],
      [currentApts, () => ok(apartments.map((id) => ({ apartment_id: id })))],
      [aptLock, () => ok()],
      [otherAdmin, () => (otherAdminExists ? ok([{ '?column?': 1 }]) : ok())],
      [aptMembership, () => ok()],
      [aptIndicator, () => ok()],
      [siteMembership, () => ok()],
      [aptPinMark, () => ok()],
    );
  }

  /** Mevcut hesap akisi: hesap kilidi + parola yazimi + iptal adimlari. */
  function existingAccountHandlers({ account = accountRow(), qr = 0, passes = 0, withPersonLock = true } = {}) {
    if (withPersonLock) {
      handlers.push([personLock, () => ok([{ id: '5', site_code: SITE, user_code: 44001, full_name: null, phone: null, email: null, is_active: true, login_name: 'salih.ceylan', account_email: account?.email }])]);
    }
    handlers.push(
      [residentAptsLock, () => ok()],
      [accountLookup, () => ok(account ? [account] : [])],
      [loginCheck, () => ok([])],
      [passwordUpdate, (_sql, params) => ok([{ user_code: 44001, login_name: params[1] ?? 'salih.ceylan', email: account?.email ?? null }])],
      [pinFlagMark, () => ok()],
      [guestPasses, () => ({ rows: [], rowCount: passes })],
      [qrTokens, () => ({ rows: [], rowCount: qr })],
      [pushTables, () => ok([{ has_devices: false, has_outbox: false }])],
      [webPushTable, () => ok([{ ok: false }])],
      [/^SELECT DISTINCT devices\.id FROM devices/, () => ok()],
    );
  }

  it('provisionPersonAccount: hesapsiz kisiye yeni hesap acar (rol apartment_owner), site_people baglar; daire erisimi grantApartmentAccess kuraliyla APARTMENT_ADMIN', async () => {
    newAccountHandlers();
    const res = await provisionPersonAccount({
      siteCode: SITE,
      personId: 5,
      loginName: 'Salih.Ceylan',
      password: 'custompassword',
      actor,
    });

    assert.equal(res.ok, true);
    assert.equal(res.user_code, 44001);
    assert.equal(res.login_name, 'salih.ceylan', 'kullanici adi kirpilip kucuk harfe cevrilir');
    assert.equal(res.temp_password, 'custompassword');
    assert.equal(res.is_new, true);
    assert.equal(res.email_verification_required, false, 'e-posta verilmedi -> dahili adres, dogrulama gerekmez');
    assert.deepEqual(auditActions(), ['person.account_created']);

    const insert = find(userInsert);
    assert.match(insert.sql, /'apartment_owner'/, "users.role users_role_check'e uyar (APARTMENT_ADMIN yalniz apartment_memberships.role'de)");
    assert.equal(/APARTMENT_ADMIN/.test(insert.sql), false);
    assert.match(insert.params[1], /^salih\.ceylan\.5\.1000000001@ahbu\.local$/, 'dahili e-posta');
    assert.equal(insert.params[3], 'salih.ceylan');
    assert.equal(insert.params[5], true, 'dahili adres dogrulanmis sayilir');
    assert.equal(await bcrypt.compare('custompassword', insert.params[4]), true);

    assert.equal(find(aptMembership).params[2], 'APARTMENT_ADMIN', 'dairede aktif yonetici yok -> yonetici');
    assert.deepEqual(find(aptPinMark).params.map(Number), [9, 44001]);
    assert.ok(indexOfQuery(aptLock) < indexOfQuery(aptMembership), 'daire satiri kilitlendikten sonra uyelik yazilir');
  });

  it('dairede baska AKTIF yonetici varsa yeni hesap FAMILY_MEMBER olur (ikinci admin olusmaz)', async () => {
    newAccountHandlers({ otherAdminExists: true });
    await provisionPersonAccount({ siteCode: SITE, personId: 5, loginName: 'salih.ceylan', password: 'pass-1234-x', actor });
    assert.equal(find(aptMembership).params[2], 'FAMILY_MEMBER');
  });

  it('parola verilmezse varsayilan gecici parola 1234 (ekip karari) ve must_change_password TRUE', async () => {
    newAccountHandlers({ apartments: [] });
    const res = await provisionPersonAccount({ siteCode: SITE, personId: 5, actor });
    assert.equal(res.temp_password, '1234');
    assert.match(find(userInsert).sql, /must_change_password,[\s\S]*TRUE, TRUE/);
    assert.equal(await bcrypt.compare('1234', find(userInsert).params[4]), true);
    assert.equal(has(aptMembership), false, 'ilişkisi olmayan kisi: daire erisimi yok');
  });

  it('kullanici adi verilmezse ad soyaddan uretilir (a-z0-9 ve nokta, en az 3 karakter)', async () => {
    newAccountHandlers({ person: { full_name: 'Çağrı Öztürk' }, apartments: [] });
    const res = await provisionPersonAccount({ siteCode: SITE, personId: 5, actor });
    assert.equal(res.login_name, 'cagri.ozturk');
    handlers.length = 0;
    install();
    newAccountHandlers({ person: { full_name: 'Al' }, apartments: [] });
    const short = await provisionPersonAccount({ siteCode: SITE, personId: 5, actor });
    assert.equal(short.login_name, 'al.5', 'kisa ad: kisi kimligi eklenir (min 3)');
  });

  it("yonetici girisli e-posta: kirpilir + kucuk harf + bicim denetimi; users.email'e yazilir, hesap dogrulanmis acilir (aksi halde kullanici adi + gecici sifre girisi 403)", async () => {
    newAccountHandlers({ apartments: [] });
    const res = await provisionPersonAccount({ siteCode: SITE, personId: 5, loginName: 'salih.ceylan', email: '  Salih.Ceylan@Example.COM ', actor });
    const insert = find(userInsert);
    assert.equal(insert.params[1], 'salih.ceylan@example.com');
    assert.equal(insert.params[5], true, 'email_verified TRUE (giris must_change_password ile korunur)');
    assert.equal(res.email_verification_required, false);
    assert.deepEqual(find(emailCheck).params, ['salih.ceylan@example.com']);
  });

  it('kisi kaydindaki (CRM) e-posta da ayni kurallarla kullanilir; bozuk ya da dahili/sistem adresi yok sayilir (dahili adrese duser)', async () => {
    newAccountHandlers({ person: { email: 'Ali@Example.com' }, apartments: [] });
    await provisionPersonAccount({ siteCode: SITE, personId: 5, loginName: 'salih.ceylan', actor });
    assert.equal(find(userInsert).params[1], 'ali@example.com');
    assert.equal(find(userInsert).params[5], true);

    for (const stored of ['bozuk-adres', 'x@ahbu.local', 'x@deleted.invalid']) {
      handlers.length = 0;
      install();
      newAccountHandlers({ person: { email: stored }, apartments: [] });
      await provisionPersonAccount({ siteCode: SITE, personId: 5, loginName: 'salih.ceylan', actor });
      assert.match(find(userInsert).params[1], /@ahbu\.local$/, stored);
      assert.equal(find(userInsert).params[5], true, stored);
    }
  });

  it('e-posta baska bir hesapta kayitliysa KULLANILMAZ (dahili adrese duser): hesabin var oldugu yoneticiye sizmaz, 409 yok', async () => {
    newAccountHandlers({ emailTaken: true, apartments: [] });
    const res = await provisionPersonAccount({ siteCode: SITE, personId: 5, loginName: 'salih.ceylan', email: 'baskasi@example.com', actor });
    assert.match(find(userInsert).params[1], /@ahbu\.local$/);
    assert.equal(res.email_verification_required, false);
  });

  it('gecersiz girdi 400 INVALID_BODY ve kilit / sorgu ONCESINDE: kullanici adi ("@" yok), e-posta (dahili / sistem alan adi dahil), parola uzunlugu', async () => {
    const cases = [
      [{ loginName: 'ali@example.com' }, /login_name/],
      [{ loginName: 'ab' }, /login_name/],
      [{ loginName: 'ali veli' }, /login_name/],
      [{ email: 'bozuk' }, /email/],
      [{ email: 'x@ahbu.local' }, /email/],
      [{ email: 'x@deleted.invalid' }, /email/],
      [{ password: 'x'.repeat(129) }, /password/],
      [{ password: { a: 1 } }, /password/],
    ];
    for (const [extra, pattern] of cases) {
      await assert.rejects(
        () => provisionPersonAccount({ siteCode: SITE, personId: 5, actor, ...extra }),
        (error) => error.code === 'INVALID_BODY' && error.statusCode === 400 && pattern.test(error.message),
        JSON.stringify(extra),
      );
    }
    assert.equal(log.length, 0, 'dogrulama DB cagrilmadan once yapilir');
  });

  it('UNIQUE yarisi: kullanici adi yazimi 23505 (idx_users_login_name_unique) verirse SAVEPOINT\'e donulur ve yeni adayla yeniden denenir', async () => {
    let attempts = 0;
    newAccountHandlers({ apartments: [] });
    handlers.unshift([
      userInsert,
      () => {
        attempts += 1;
        if (attempts === 1) {
          txAborted = true;
          throw Object.assign(new Error('duplicate key'), { code: '23505', constraint: 'idx_users_login_name_unique' });
        }
        return ok([{ user_code: '44001' }]);
      },
    ]);
    const res = await provisionPersonAccount({ siteCode: SITE, personId: 5, loginName: 'salih.ceylan', actor });
    assert.equal(attempts, 2);
    assert.equal(res.ok, true);
    assert.equal(findAll(/^ROLLBACK TO SAVEPOINT login_name_write$/).length, 1);
    assert.equal(findAll(loginCheck).length, 2, 'her denemede benzersiz ad yeniden secilir');
  });

  it('mevcut hesap: yonetimce acilmis sakin hesabinin sifresi guncellenir; must_change_password TRUE + deleted_at korumasi AYNI UPDATE; PIN isareti; eski erisim iptali', async () => {
    existingAccountHandlers({ qr: 2, passes: 1 });
    const res = await provisionPersonAccount({ siteCode: SITE, personId: 5, password: 'yeni-gecici-1', actor });

    assert.deepEqual({ ok: res.ok, user_code: res.user_code, login_name: res.login_name, temp_password: res.temp_password, is_new: res.is_new }, {
      ok: true,
      user_code: 44001,
      login_name: 'salih.ceylan',
      temp_password: 'yeni-gecici-1',
      is_new: false,
    });
    const update = find(passwordUpdate);
    assert.equal(await bcrypt.compare('yeni-gecici-1', update.params[0]), true);
    assert.equal(update.params[1], null, 'kullanici adi istenmedi -> degismez');
    assert.equal(update.params[2], 44001);
    assert.ok(has(pinFlagMark), 'yonetimin verdigi PIN isareti kuruldu');
    assert.ok(has(guestPasses) && has(qrTokens) && has(pushTables), 'eski parolayla edinilmis misafir gecisi / karekod / bildirim kayitlari kapatilir');
    assert.ok(indexOfQuery(residentAptsLock) < indexOfQuery(accountLookup), 'kilit sirasi apartments -> users');
    assert.ok(indexOfQuery(accountLookup) < indexOfQuery(passwordUpdate));
    assert.ok(indexOfQuery(passwordUpdate) < indexOfQuery(qrTokens));
    assert.deepEqual(auditActions(), ['person.account_password_reset']);
    assert.deepEqual(auditDetails('person.account_password_reset'), { user_code: 44001, login_name: 'salih.ceylan', guest_passes: 1, qr_tokens: 2, push_devices: 0, push_outbox: 0 });
    assert.ok(has(/^SELECT DISTINCT devices\.id FROM devices/), 'karekod iptal edildi -> yerel kontrol anahtarlari yenilenir');
  });

  it('mevcut hesap: kullanici adi degisimi dogrulanir (bicim) ve benzersiz secilir', async () => {
    existingAccountHandlers();
    const res = await provisionPersonAccount({ siteCode: SITE, personId: 5, loginName: 'Yeni.Ad', actor });
    assert.equal(res.login_name, 'yeni.ad');
    assert.equal(find(passwordUpdate).params[1], 'yeni.ad');
    await assert.rejects(
      () => provisionPersonAccount({ siteCode: SITE, personId: 5, loginName: 'sakin@example.com', actor }),
      (error) => error.code === 'INVALID_BODY',
    );
  });

  it('mevcut hesap 409: yonetici / bireysel hesap, baska siteye bagli hesap ve kendi parolasini belirleyen gercek hesap DEGISTIRILEMEZ (sifre yazilmaz, iptal yok)', async () => {
    const blocked = [
      accountRow({ role: 'site_manager' }),
      accountRow({ role: 'individual', email: 'ali@example.com' }),
      accountRow({ is_manager: true }),
      accountRow({ foreign_membership: true }),
      accountRow({ foreign_apartment: true }),
      accountRow({ foreign_person: true }),
      accountRow({ email: 'ali@example.com', must_change_password: false, pin_issued: false }),
      null,
    ];
    for (const account of blocked) {
      handlers.length = 0;
      install();
      existingAccountHandlers({ account });
      await assert.rejects(
        () => provisionPersonAccount({ siteCode: SITE, personId: 5, password: 'yeni-gecici-1', actor }),
        (error) => error.statusCode === 409 && error.code === 'PERSON_ACCOUNT_NOT_MANAGEABLE',
        JSON.stringify(account && { role: account.role, is_manager: account.is_manager }),
      );
      assert.equal(has(passwordUpdate), false);
      assert.equal(has(qrTokens), false);
      assert.equal(auditActions().length, 0);
    }
  });

  it('mevcut hesap 409 PERSON_ACCOUNT_RESET_NEEDS_SUPER: sakin parolasini kendisi belirlemis dahili hesabi yonetici DEGISTIREMEZ; super kullanici degistirebilir', async () => {
    const chosen = accountRow({ must_change_password: false, pin_issued: false });
    existingAccountHandlers({ account: chosen });
    await assert.rejects(
      () => provisionPersonAccount({ siteCode: SITE, personId: 5, password: 'yeni-gecici-1', actor }),
      (error) => error.statusCode === 409 && error.code === 'PERSON_ACCOUNT_RESET_NEEDS_SUPER',
    );
    assert.equal(has(passwordUpdate), false);

    handlers.length = 0;
    install();
    existingAccountHandlers({ account: chosen });
    const res = await provisionPersonAccount({ siteCode: SITE, personId: 5, password: 'yeni-gecici-1', actor: { ...actor, role: 'super_user' } });
    assert.equal(res.ok, true);
    assert.ok(has(passwordUpdate));
  });

  it('mevcut hesap: hesap bu arada silindiyse (UPDATE satir donmez) tombstone\'a parola yazilmaz -> 409', async () => {
    existingAccountHandlers();
    handlers.unshift([passwordUpdate, () => ok()]);
    await assert.rejects(
      () => provisionPersonAccount({ siteCode: SITE, personId: 5, password: 'yeni-gecici-1', actor }),
      (error) => error.statusCode === 409 && error.code === 'PERSON_ACCOUNT_NOT_MANAGEABLE',
    );
    assert.equal(has(qrTokens), false);
  });

  it('resetPersonPinDirect: yonetimce acilmis hesabin PIN kodunu sifirlar; must_change_password TRUE + deleted_at korumasi; eski erisim iptali', async () => {
    handlers.push([resetPersonLock, () => ok([{ id: '5', user_code: 44001, login_name: 'salih.ceylan' }])]);
    existingAccountHandlers({ withPersonLock: false });

    const res = await resetPersonPinDirect({
      siteCode: SITE,
      personId: 5,
      actor,
    });

    assert.equal(res.ok, true);
    assert.equal(res.login_name, 'salih.ceylan');
    assert.match(res.pin_code, /^\d{4}$/);
    const update = find(passwordUpdate);
    assert.equal(await bcrypt.compare(res.pin_code, update.params[0]), true, 'yazilan ozet donen PIN\'e ait');
    assert.ok(has(pinFlagMark) && has(guestPasses) && has(qrTokens));
    assert.deepEqual(auditActions(), ['person.pin_reset']);
  });

  it('resetPersonPinDirect: hesabi olmayan kisi 400 PERSON_NO_ACCOUNT; yonetilemez hesap 409 (PIN yazilmaz)', async () => {
    handlers.push([resetPersonLock, () => ok([{ id: '5', user_code: null, login_name: null }])]);
    await assert.rejects(
      () => resetPersonPinDirect({ siteCode: SITE, personId: 5, actor }),
      (error) => error.statusCode === 400 && error.code === 'PERSON_NO_ACCOUNT',
    );

    handlers.length = 0;
    install();
    handlers.push([resetPersonLock, () => ok([{ id: '5', user_code: 44001, login_name: 'ali' }])]);
    existingAccountHandlers({ account: accountRow({ role: 'site_manager' }), withPersonLock: false });
    await assert.rejects(
      () => resetPersonPinDirect({ siteCode: SITE, personId: 5, actor }),
      (error) => error.statusCode === 409 && error.code === 'PERSON_ACCOUNT_NOT_MANAGEABLE',
    );
    assert.equal(has(passwordUpdate), false);
  });
});

describe('provisionResidentAndLinkPerson: daire sakini hesabi + (yalniz YENI hesapta) tek eslesen hesapsiz kisiye baglama', () => {
  const siteLookup = /^SELECT site_code FROM apartments WHERE id = \$1 LIMIT 1$/;
  const aptSelect = /^SELECT a\.id, a\.site_code, a\.resident_user_code, a\.resident_email, b\.block_name, a\.unit_label, a\.sort_order FROM apartments a/;
  const loginCheck = /^SELECT user_code FROM users WHERE LOWER\(login_name\) = LOWER/;
  const createUserInsert = /^INSERT INTO users \(/;
  const aptAccountUpdate = /^UPDATE apartments SET resident_user_code = \$1, resident_email = \$2, resident_pin_issued = TRUE/;
  const existingUserSelect = /^SELECT email FROM users WHERE user_code = \$1 AND deleted_at IS NULL LIMIT 1$/;
  const internalUserUpdate = /^UPDATE users SET full_name = \$1, email = \$2, login_name = \$3/;
  const aptEmailUpdate = /^UPDATE apartments SET resident_email = \$1, is_active = \$2 WHERE id = \$3$/;
  const finalSelect = /^SELECT a\.id, a\.site_code, a\.block_id, b\.block_name[\s\S]*WHERE a\.id = \$1$/;
  const aptLock = /^SELECT id FROM apartments WHERE id = \$1 FOR UPDATE$/;
  const otherAdmin = /^SELECT 1 FROM apartment_memberships WHERE apartment_id = \$1 AND role = 'APARTMENT_ADMIN'/;
  const aptMembership = /^INSERT INTO apartment_memberships/;
  const aptIndicator = /^UPDATE apartments SET resident_user_code = \$1 WHERE id = \$2 AND resident_user_code IS NULL$/;
  const siteMembership = /^INSERT INTO site_memberships/;
  const candidates = /^SELECT sp\.id, sp\.full_name, sp\.email FROM apartment_residencies ar INNER JOIN site_people sp ON sp\.id = ar\.person_id WHERE ar\.apartment_id = \$1/;
  const linkUpdate = /^UPDATE site_people SET user_code = \$1, full_name = NULL, phone = NULL, email = NULL, updated_at = NOW\(\) WHERE id = \$2 AND site_code = \$3 AND user_code IS NULL AND is_active = TRUE RETURNING id$/;

  const request = { apartmentId: 9, fullName: 'Ali Veli', loginName: 'ali.veli', password: '4321', email: undefined, phoneNumber: null, isActive: true };

  function baseHandlers({ residentUserCode = null, people = [] } = {}) {
    handlers.push(
      [siteLookup, () => ok([{ site_code: String(SITE) }])],
      [aptSelect, () => ok([{ id: '9', site_code: String(SITE), resident_user_code: residentUserCode, resident_email: null, block_name: 'A Blok', unit_label: 'Daire 2', sort_order: 2 }])],
      [loginCheck, () => ok()],
      [createUserInsert, () => ok([{ id: 777, user_code: 777 }])],
      [aptAccountUpdate, () => ok()],
      [existingUserSelect, () => ok([{ email: 'ali.veli.9.1000000001@ahbu.local' }])],
      [internalUserUpdate, () => ok()],
      [aptEmailUpdate, () => ok()],
      [finalSelect, () => ok([{ id: '9', site_code: String(SITE), resident_user_code: residentUserCode ?? 777 }])],
      [aptLock, () => ok()],
      [otherAdmin, () => ok()],
      [aptMembership, () => ok()],
      [aptIndicator, () => ok()],
      [siteMembership, () => ok()],
      [candidates, () => ok(people)],
      [linkUpdate, (_sql, params) => ok([{ id: String(params[1]) }])],
    );
  }

  it('YENI hesap: ayni transaction\'da (site kilidi altinda) dairenin erisimi verilir ve ad eslesen TEK hesapsiz kisi baglanir', async () => {
    baseHandlers({ people: [{ id: '5', full_name: '  ALİ   veli ', email: null }, { id: '6', full_name: 'Ayse Yilmaz', email: null }] });
    const apartment = await provisionResidentAndLinkPerson(request);
    assert.equal(apartment.issued_pin_code, '4321');
    assert.equal(Number(apartment.resident_user_code), 777);
    assert.ok(log.some((q) => q.sql === 'BEGIN' && q.inTx));
    assert.ok(log.some((q) => /^SELECT pg_advisory_xact_lock/.test(q.sql) && q.params[0] === `people_sync:${SITE}`), 'site kilidi');
    assert.equal(find(aptMembership).params[2], 'APARTMENT_ADMIN');
    assert.deepEqual(find(linkUpdate).params.map(Number), [777, 5, SITE]);
    assert.equal(findAll(linkUpdate).length, 1, 'yalniz TEK kisi');
    assert.ok(indexOfQuery(aptAccountUpdate) < indexOfQuery(aptMembership));
    assert.ok(indexOfQuery(candidates) < indexOfQuery(linkUpdate));
    assert.ok(log.filter((q) => /^(INSERT|UPDATE|SELECT)/.test(q.sql) && q.inTx !== true && !siteLookup.test(q.sql)).length === 0, 'tum sorgular transaction icinde');
    assert.ok(log.some((q) => q.sql === 'COMMIT'));
  });

  it('e-posta eslesmesi de kimlik sayilir (kisi adi farkli olsa bile)', async () => {
    baseHandlers({ people: [{ id: '5', full_name: 'Baska Ad', email: 'Ali@Example.com' }, { id: '6', full_name: 'Ayse', email: 'ayse@example.com' }] });
    await provisionResidentAndLinkPerson({ ...request, email: 'ali@example.com' });
    assert.deepEqual(find(linkUpdate).params.map(Number), [777, 5, SITE]);
  });

  it('kimligi eslesmeyen kisi ASLA baglanmaz (dairedeki tek hesapsiz kisi baska birini ifade ediyorsa)', async () => {
    baseHandlers({ people: [{ id: '6', full_name: 'Ayse Yilmaz', email: 'ayse@example.com' }] });
    await provisionResidentAndLinkPerson(request);
    assert.equal(has(linkUpdate), false);
    assert.ok(log.some((q) => q.sql === 'COMMIT'), 'hesap acma yine tamamlanir');
  });

  it('birden cok eslesen aday varsa baglanmaz (atlanir; 500/409 yok)', async () => {
    baseHandlers({ people: [{ id: '5', full_name: 'Ali Veli', email: null }, { id: '7', full_name: 'ali VELI', email: null }] });
    const apartment = await provisionResidentAndLinkPerson(request);
    assert.equal(has(linkUpdate), false);
    assert.equal(apartment.issued_pin_code, '4321');
  });

  it('baglama sirasinda cakisma (UNIQUE vb.) hesap acmayi geri ALMAZ: SAVEPOINT\'e donulur, atlanir', async () => {
    baseHandlers({ people: [{ id: '5', full_name: 'Ali Veli', email: null }] });
    handlers.unshift([
      linkUpdate,
      () => {
        txAborted = true;
        throw Object.assign(new Error('duplicate key'), { code: '23505' });
      },
    ]);
    const apartment = await provisionResidentAndLinkPerson(request);
    assert.equal(apartment.issued_pin_code, '4321');
    assert.equal(findAll(/^ROLLBACK TO SAVEPOINT resident_person_link$/).length, 1);
    assert.ok(log.some((q) => q.sql === 'COMMIT'));
  });

  it('MEVCUT hesabin duzenlenmesi (PIN verilmedi): kisi baglama ve uyelik yazimi HIC calismaz (eskiden her duzenlemede dairenin TUM hesapsiz kisileri baglanirdi)', async () => {
    baseHandlers({ residentUserCode: 555, people: [{ id: '5', full_name: 'Ali Veli', email: null }] });
    const apartment = await provisionResidentAndLinkPerson({ ...request, password: '' });
    assert.equal(apartment.issued_pin_code, null);
    assert.equal(has(candidates), false);
    assert.equal(has(linkUpdate), false);
    assert.equal(has(aptMembership), false);
    assert.equal(has(siteMembership), false);
  });

  it('daire yok: Error(APARTMENT_NOT_FOUND) (rotalar 404\'e cevirir); site kodu verilirse on sorgu yok', async () => {
    handlers.push([siteLookup, () => ok()]);
    await assert.rejects(() => provisionResidentAndLinkPerson(request), (error) => error.message === 'APARTMENT_NOT_FOUND');

    handlers.length = 0;
    install();
    baseHandlers();
    await provisionResidentAndLinkPerson({ ...request, siteCode: SITE });
    assert.equal(has(siteLookup), false);
  });
});
