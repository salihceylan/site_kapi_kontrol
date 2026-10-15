// Kisi ve Daire Kayitlari (Faz 2a) is akislari (DB'siz, betikli sahte veritabani): kisi ekleme (hesap baglama / mevcut daire sakini
// hesabi akisi), duzenleme, tasinma (kapi yetkisi kapanir), iliskiler, daire alanlari, araclar.
import { describe, it, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert/strict';
import nodemailer from 'nodemailer';
import { pool } from '../src/db.js';
import { updateApartment } from '../src/modules/apartment_records_service.js';
import {
  addResidency,
  createPerson,
  endResidency,
  parsePersonCreateInput,
  updatePerson,
  updateResidency,
} from '../src/modules/people_service.js';
import { createVehicle, removeVehicle } from '../src/modules/vehicle_service.js';

const SITE = 1000000001;
const actor = { id: 20001, user_code: 20001, userCode: 20001, role: 'site_manager', full_name: 'Ayşe Yönetici' };

const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
const ok = (rows = []) => ({ rows, rowCount: rows.length });

let log;
let handlers;
// PostgreSQL gibi: hata alan transaction'da ROLLBACK disinda sorgu calismaz (25P02).
let txAborted = false;

function install() {
  log = [];
  txAborted = false;
  const run = async (text, params, inTx) => {
    const sql = norm(text);
    log.push({ sql, params: params ?? [], inTx });
    if (txAborted && inTx && sql !== 'ROLLBACK') {
      throw Object.assign(new Error('current transaction is aborted, commands ignored until end of transaction block'), { code: '25P02' });
    }
    for (const [pattern, handler] of handlers) {
      if (pattern.test(sql)) {
        return typeof handler === 'function' ? handler(sql, params ?? []) : handler;
      }
    }
    return ok();
  };
  pool.query = (text, params) => run(text, params, false);
  pool.connect = async () => ({ query: (text, params) => run(text, params, true), release() {} });
}

const find = (regex) => log.find((q) => regex.test(q.sql));
const findAll = (regex) => log.filter((q) => regex.test(q.sql));
const has = (regex) => log.some((q) => regex.test(q.sql));
const auditActions = () => findAll(/^INSERT INTO audit_log/).map((q) => q.params[3]);
const auditDetails = (action) => JSON.parse(findAll(/^INSERT INTO audit_log/).find((q) => q.params[3] === action).params[7]);

const APARTMENT_ROW = { id: '9', site_code: String(SITE), unit_label: 'Daire 2', resident_user_code: null, block_name: 'A Blok' };

const APARTMENT_LOOKUP = /FROM apartments a INNER JOIN site_blocks b ON b\.id = a\.block_id WHERE a\.id = \$1 AND a\.site_code = \$2 LIMIT 1$/;
const PERSON_INSERT = /^INSERT INTO site_people/;

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

describe('createPerson: kayit, hesap baglama, mevcut daire sakini akisi', () => {
  const input = (body) => parsePersonCreateInput(body);

  it('yalniz ad: hesapsiz kisi + person.created; daire/hesap/uyelik islemi YOK; site kilidi altinda tek transaction', async () => {
    handlers.push([PERSON_INSERT, () => ok([{ id: '5' }])]);
    await createPerson({ siteCode: SITE, input: input({ full_name: 'Ali Veli', phone: '0555 111 22 33', note: 'not' }), actor });
    const insert = find(PERSON_INSERT);
    assert.deepEqual(insert.params, [SITE, null, 'Ali Veli', '+905551112233', null, 'not', 20001]);
    assert.deepEqual(auditActions(), ['person.created']);
    assert.deepEqual(auditDetails('person.created'), { has_account: false });
    assert.equal(has(/apartment_memberships|INSERT INTO users|apartment_residencies/), false);
    const sqls = log.map((q) => q.sql);
    assert.equal(sqls[0], 'BEGIN');
    assert.match(sqls[1], /^SELECT pg_advisory_xact_lock/);
    assert.equal(log[1].params[0], `people_sync:${SITE}`);
    assert.ok(sqls.includes('COMMIT'));
  });

  it('daire + iliski (e-postasiz): ilişki kaydi, giris tarihi varsayilan BUGUN; erisim uyeligi OLUSMAZ; residency.added', async () => {
    handlers.push([APARTMENT_LOOKUP, () => ok([APARTMENT_ROW])], [PERSON_INSERT, () => ok([{ id: '5' }])], [/^INSERT INTO apartment_residencies/, () => ok([{ id: '31' }])]);
    await createPerson({ siteCode: SITE, input: input({ full_name: 'Ali Veli', apartment_id: 9, relation: 'tenant' }), actor });
    const residency = find(/^INSERT INTO apartment_residencies/);
    assert.deepEqual(residency.params.slice(0, 4), [SITE, 9, 5, 'tenant']);
    assert.match(residency.params[4], /^\d{4}-\d{2}-\d{2}$/);
    assert.deepEqual(auditActions(), ['person.created', 'residency.added']);
    assert.deepEqual(auditDetails('residency.added'), { residency_id: 31, apartment_id: 9, relation: 'tenant' });
    assert.equal(has(/INSERT INTO apartment_memberships|INSERT INTO site_memberships|INSERT INTO users/), false);
  });

  it('girilen giris tarihi kullanilir', async () => {
    handlers.push([APARTMENT_LOOKUP, () => ok([APARTMENT_ROW])], [PERSON_INSERT, () => ok([{ id: '5' }])], [/^INSERT INTO apartment_residencies/, () => ok([{ id: '31' }])]);
    await createPerson({ siteCode: SITE, input: input({ full_name: 'Ali Veli', apartment_id: 9, move_in_date: '15.03.2025' }), actor });
    assert.equal(find(/^INSERT INTO apartment_residencies/).params[4], '2025-03-15');
  });

  it('baska sitenin dairesi / yok daire -> 404 APARTMENT_NOT_FOUND (sorgu site kapsamli), hicbir sey yazilmaz', async () => {
    await assert.rejects(
      () => createPerson({ siteCode: SITE, input: input({ full_name: 'Ali Veli', apartment_id: 77 }), actor }),
      (error) => error.code === 'APARTMENT_NOT_FOUND' && error.statusCode === 404,
    );
    assert.deepEqual(find(APARTMENT_LOOKUP).params, [77, SITE]);
    assert.equal(has(/^BEGIN/), false);
  });

  it('ayni sitede AKTIF ayni e-posta -> 409 PERSON_EXISTS + person_id; yazma yok', async () => {
    handlers.push([/FROM site_people sp LEFT JOIN users u ON u\.user_code = sp\.user_code WHERE sp\.site_code = \$1 AND \( \(sp\.user_code IS NULL AND lower\(sp\.email\) = \$2\)/, () => ok([{ id: '8', is_active: true, user_code: null }])]);
    await assert.rejects(
      () => createPerson({ siteCode: SITE, input: input({ full_name: 'Ali Veli', email: 'Ali@Example.com' }), actor }),
      (error) => error.code === 'PERSON_EXISTS' && error.statusCode === 409 && error.extra?.person_id === 8,
    );
    assert.equal(has(PERSON_INSERT), false);
    assert.equal(has(/^BEGIN/), false);
  });

  it('PASIF (tasinmis) ayni e-postali kisi YENIDEN KULLANILIR: yinelenen kisi acilmaz, gecmis korunur', async () => {
    handlers.push(
      [/FROM site_people sp LEFT JOIN users u ON u\.user_code = sp\.user_code WHERE sp\.site_code = \$1 AND \(/, () => ok([{ id: '8', is_active: false, user_code: null }])],
      [/^SELECT user_code FROM users WHERE lower\(email\) = \$1/, () => ok()],
    );
    await createPerson({ siteCode: SITE, input: input({ full_name: 'Ali Veli', email: 'ali@example.com' }), actor });
    assert.equal(has(PERSON_INSERT), false);
    const update = find(/^UPDATE site_people SET is_active = TRUE/);
    assert.ok(update);
    assert.equal(update.params[0], 8);
    assert.deepEqual(auditDetails('person.created'), { has_account: false, reactivated: true });
  });

  it('kayitli kullanicinin e-postasi: kisi o hesaba BAGLANIR; daire verildiyse apartment_memberships + site RESIDENT (onay gerekmez); yeni hesap OLUSMAZ', async () => {
    handlers.push(
      [/^SELECT user_code FROM users WHERE lower\(email\) = \$1/, () => ok([{ user_code: 30001 }])],
      [APARTMENT_LOOKUP, () => ok([APARTMENT_ROW])],
      [PERSON_INSERT, () => ok([{ id: '5' }])],
      [/^INSERT INTO apartment_residencies/, () => ok([{ id: '31' }])],
    );
    await createPerson({ siteCode: SITE, input: input({ full_name: 'Ali Veli', email: 'ali@example.com', apartment_id: 9, relation: 'owner' }), actor });
    const insert = find(PERSON_INSERT);
    assert.equal(insert.params[1], 30001, 'user_code baglandi');
    assert.equal(insert.params[4], null, 'hesapli kisinin e-postasi users\'tan okunur (CRM\'e kopyalanmaz)');
    const membership = find(/^INSERT INTO apartment_memberships/);
    assert.deepEqual(membership.params, [9, 30001]);
    assert.match(membership.sql, /VALUES \(\$1, \$2, 'FAMILY_MEMBER', TRUE\) ON CONFLICT \(apartment_id, user_code\) DO UPDATE SET is_active = TRUE/);
    const site = find(/^INSERT INTO site_memberships/);
    assert.deepEqual(site.params, [SITE, 30001]);
    assert.match(site.sql, /'RESIDENT', TRUE/);
    assert.equal(has(/INSERT INTO users/), false);
    assert.deepEqual(auditDetails('person.created'), { has_account: true });
    // tek transaction icinde
    assert.ok(log.filter((q) => /^INSERT INTO (apartment_memberships|site_memberships|apartment_residencies)/.test(q.sql)).every((q) => q.inTx));
  });

  it('kayitli kullanici + daire YOK: uyelik olusturulmaz (yalniz kayit)', async () => {
    handlers.push([/^SELECT user_code FROM users WHERE lower\(email\) = \$1/, () => ok([{ user_code: 30001 }])], [PERSON_INSERT, () => ok([{ id: '5' }])]);
    await createPerson({ siteCode: SITE, input: input({ full_name: 'Ali Veli', email: 'ali@example.com' }), actor });
    assert.equal(has(/apartment_memberships/), false);
  });

  describe('hesap yok + daire + e-posta: MEVCUT daire sakini hesabi akisi yeniden kullanilir', () => {
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
        [/^SELECT user_code FROM users WHERE lower\(email\) = \$1/, () => ok()],
        [APARTMENT_LOOKUP, () => ok([{ ...APARTMENT_ROW, resident_user_code: residentUserCode }])],
        [/^SELECT a\.id, a\.site_code, a\.resident_user_code, a\.resident_email, b\.block_name, a\.unit_label, a\.sort_order FROM apartments a/, () => ok([{ id: '9', site_code: String(SITE), resident_user_code: null, resident_email: null, block_name: 'A Blok', unit_label: 'Daire 2', sort_order: 2 }])],
        [/^SELECT user_code FROM users WHERE LOWER\(login_name\)/, () => ok()],
        [/^INSERT INTO users/, () => ok([{ id: 40001, full_name: 'Ali Veli', email: 'x@ahbu.local', login_name: 'ln', role: 'apartment_owner' }])],
        [/^SELECT a\.id, a\.site_code, a\.block_id, b\.block_name, a\.unit_label, a\.sort_order, a\.is_active, a\.resident_user_code/, () => ok([{ id: '9', site_code: String(SITE), resident_user_code: 40001 }])],
        [
          /^SELECT a\.id, a\.site_code, a\.unit_label, a\.resident_email, a\.resident_pin_code, b\.block_name, s\.name AS site_name/,
          () => ok([{ id: '9', site_code: String(SITE), unit_label: 'Daire 2', resident_email: 'ali@example.com', resident_pin_code: '4821', block_name: 'A Blok', site_name: 'Gül Sitesi', resident_full_name: 'Ali Veli', resident_login_name: 'a.blok.2' }]),
        ],
        [PERSON_INSERT, () => ok([{ id: '5' }])],
        [/^INSERT INTO apartment_residencies/, () => ok([{ id: '31' }])],
      );
    }

    it('daire sakini hesabi olusturulur, kisi o hesaba baglanir (iletisim e-postasi CRM\'de), kimlik bilgileri e-postayla gonderilir', async () => {
      provisionHandlers();
      await createPerson({ siteCode: SITE, input: parsePersonCreateInput({ full_name: 'Ali Veli', email: 'ali@example.com', phone: '0555 111 22 33', apartment_id: 9, relation: 'owner' }), actor });

      // mevcut akis: yeni hesap + dairenin sakini
      const userInsert = find(/^INSERT INTO users/);
      assert.equal(userInsert.params[1].endsWith('@ahbu.local'), true, 'dahili daire hesabi e-postasi');
      assert.equal(userInsert.params[3], 'apartment_owner');
      assert.equal(userInsert.params[7], '+905551112233');
      const aptUpdate = find(/^UPDATE apartments SET resident_user_code = \$1, resident_email = \$2, resident_pin_code = \$3, is_active = \$4 WHERE id = \$5$/);
      assert.equal(aptUpdate.params[0], 40001);
      assert.equal(aptUpdate.params[1], 'ali@example.com');
      assert.match(aptUpdate.params[2], /^\d{4}$/, '4 haneli PIN (mevcut akis)');

      // kisi -> yeni hesap; dahili hesapta iletisim e-postasi CRM'de tutulur
      const person = find(PERSON_INSERT);
      assert.equal(person.params[1], 40001);
      assert.equal(person.params[4], 'ali@example.com');
      assert.equal(has(/^INSERT INTO apartment_memberships/), false, 'eski model: erisim apartments.resident_user_code ile');

      // kimlik bilgisi e-postasi (sendApartmentCredentials)
      for (let i = 0; i < 6 && sent.length === 0; i += 1) await new Promise((resolve) => setImmediate(resolve));
      assert.equal(sent.length, 1);
      assert.equal(sent[0].to, 'ali@example.com');
      assert.match(sent[0].subject, /Daire giris bilgileriniz/);
      assert.match(sent[0].html, /a\.blok\.2/);
      assert.match(sent[0].html, /4821/);
    });

    it('dairenin ZATEN bir sakin hesabi varsa: yeni hesap acilmaz/mevcut sakin ezilmez, yalniz kayit tutulur (has_account false)', async () => {
      provisionHandlers({ residentUserCode: 55555 });
      await createPerson({ siteCode: SITE, input: parsePersonCreateInput({ full_name: 'Ali Veli', email: 'ali@example.com', apartment_id: 9 }), actor });
      assert.equal(has(/INSERT INTO users|UPDATE apartments/), false);
      const person = find(PERSON_INSERT);
      assert.equal(person.params[1], null);
      assert.equal(person.params[4], 'ali@example.com');
      assert.equal(sent.length, 0);
    });

    it('e-posta yoksa hesap acilmaz (yalniz kayit)', async () => {
      provisionHandlers();
      await createPerson({ siteCode: SITE, input: parsePersonCreateInput({ full_name: 'Ali Veli', apartment_id: 9 }), actor });
      assert.equal(has(/INSERT INTO users/), false);
      assert.equal(find(PERSON_INSERT).params[1], null);
    });

    it('iliski dolu (malik zaten var): hesap acilmadan ONCE 409 RELATION_TAKEN', async () => {
      provisionHandlers();
      handlers.unshift([/^SELECT id FROM apartment_residencies WHERE apartment_id = \$1 AND is_current = TRUE AND relation = \$2/, () => ok([{ id: '1' }])]);
      await assert.rejects(
        () => createPerson({ siteCode: SITE, input: parsePersonCreateInput({ full_name: 'Ali Veli', email: 'ali@example.com', apartment_id: 9, relation: 'owner' }), actor }),
        (error) => error.code === 'RELATION_TAKEN' && error.statusCode === 409,
      );
      assert.equal(has(/INSERT INTO users/), false);
      assert.equal(has(PERSON_INSERT), false);
    });

    it('e-posta gonderimi basarisiz olsa da kisi kaydi olusur (hata loglanir)', async () => {
      provisionHandlers();
      nodemailer.createTransport = () => ({
        sendMail: async () => {
          throw new Error('SMTP reddetti');
        },
      });
      const result = await createPerson({ siteCode: SITE, input: parsePersonCreateInput({ full_name: 'Ali Veli', email: 'ali@example.com', apartment_id: 9 }), actor });
      assert.equal(has(PERSON_INSERT), true);
      assert.equal(result, null, 'sahte DB kart sorgusuna bos doner; kayit yazildi');
      for (let i = 0; i < 6; i += 1) await new Promise((resolve) => setImmediate(resolve));
      assert.ok(console.error.mock.calls.some((c) => String(c.arguments[0]).includes('[people] daire sakini e-postasi gonderilemedi')));
    });
  });

  it('esitleme-yazma yarisi: kisi ekleme tekil indeks ihlali (23505) 409 PERSON_EXISTS olur', async () => {
    handlers.push([
      PERSON_INSERT,
      () => {
        throw Object.assign(new Error('duplicate key'), { code: '23505', constraint: 'uq_site_people_email' });
      },
    ]);
    await assert.rejects(
      () => createPerson({ siteCode: SITE, input: parsePersonCreateInput({ full_name: 'Ali Veli' }), actor }),
      (error) => error.code === 'PERSON_EXISTS',
    );
    assert.ok(has(/^ROLLBACK$/));
  });

  it('yarista kaybeden ekleme (23505): iptal edilmis transaction\'da sorgu CALISTIRILMAZ, mevcut kisi havuzdan bulunur (409 + person_id)', async () => {
    // Gercek PostgreSQL dogrulamasinda yakalanan hata: eszamanli 5 ayni e-posta eklemesinde 4 istek 500 donuyordu
    // ("current transaction is aborted") cunku mevcut kisi aranirken ayni transaction kullaniliyordu.
    let lookups = 0;
    handlers.push(
      [
        /FROM site_people sp LEFT JOIN users u ON u\.user_code = sp\.user_code WHERE sp\.site_code = \$1 AND \(/,
        () => {
          lookups += 1;
          return lookups === 1 ? ok() : ok([{ id: '8', is_active: true, user_code: null }]);
        },
      ],
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
    assert.ok(has(/^ROLLBACK$/));
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
        [PERSON_INSERT, () => ok([{ id: '5' }])],
        [
          /^INSERT INTO apartment_residencies/,
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
  const lock = /^SELECT id, user_code, full_name, phone, email, note, is_active FROM site_people WHERE id = \$1 AND site_code = \$2 FOR UPDATE$/;

  it('HESAPLI kisi: full_name/phone/email gonderilirse 409 PERSON_HAS_ACCOUNT (yazma yok); alan ESIT olsa bile', async () => {
    handlers.push([lock, () => ok([{ id: '5', user_code: 30001, full_name: null, phone: null, email: null, note: null, is_active: true }])]);
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

  it('HESAPLI kisi: note ve is_active her zaman degisir; audit person.updated details.changes [{field,from,to}]', async () => {
    handlers.push([lock, () => ok([{ id: '5', user_code: 30001, full_name: null, phone: null, email: null, note: 'eski', is_active: true }])]);
    await updatePerson({ siteCode: SITE, personId: 5, body: { note: 'yeni not' }, actor });
    const update = find(/^UPDATE site_people SET note = \$1, updated_at = NOW\(\) WHERE id = \$2 AND site_code = \$3$/);
    assert.deepEqual(update.params, ['yeni not', 5, SITE]);
    assert.deepEqual(auditDetails('person.updated'), { changes: [{ field: 'note', from: 'eski', to: 'yeni not' }] });
  });

  it('HESAPSIZ kisi: ad/telefon/e-posta/not guncellenir; yalniz DEGISEN alanlar audit\'e; degisiklik yoksa audit yok', async () => {
    handlers.push([lock, () => ok([{ id: '5', user_code: null, full_name: 'Ali Veli', phone: '+905551112233', email: null, note: null, is_active: true }])]);
    await updatePerson({ siteCode: SITE, personId: 5, body: { full_name: 'Ali Veli Kaya', phone: '0555 111 22 33', email: 'ali@example.com' }, actor });
    assert.deepEqual(auditDetails('person.updated').changes, [
      { field: 'full_name', from: 'Ali Veli', to: 'Ali Veli Kaya' },
      { field: 'email', from: null, to: 'ali@example.com' },
    ]);
    install();
    handlers.length = 0;
    handlers.push([lock, () => ok([{ id: '5', user_code: null, full_name: 'Ali Veli', phone: null, email: null, note: null, is_active: true }])]);
    await updatePerson({ siteCode: SITE, personId: 5, body: { full_name: 'Ali Veli' }, actor });
    assert.equal(has(/^INSERT INTO audit_log/), false);
  });

  it('e-posta baska AKTIF kisiye aitse 409 PERSON_EXISTS', async () => {
    handlers.push(
      [lock, () => ok([{ id: '5', user_code: null, full_name: 'Ali', phone: null, email: null, note: null, is_active: true }])],
      [/FROM site_people sp LEFT JOIN users u ON u\.user_code = sp\.user_code WHERE sp\.site_code = \$1 AND \(/, () => ok([{ id: '9', is_active: true, user_code: null }])],
    );
    await assert.rejects(
      () => updatePerson({ siteCode: SITE, personId: 5, body: { email: 'baska@example.com' }, actor }),
      (error) => error.code === 'PERSON_EXISTS' && error.extra?.person_id === 9,
    );
  });

  it('is_active:false -> HER guncel iliski biter; hesapliysa O DAIRELERDEKI uyelik kapanir; pasif; rotasyon', async () => {
    handlers.push(
      [lock, () => ok([{ id: '5', user_code: 30001, full_name: null, phone: null, email: null, note: null, is_active: true }])],
      [/^SELECT r\.id, r\.apartment_id, r\.person_id, r\.relation FROM apartment_residencies r WHERE r\.person_id = \$1 AND r\.is_current = TRUE ORDER BY r\.id FOR UPDATE$/, () => ok([{ id: '31', apartment_id: '9', person_id: '5', relation: 'owner' }, { id: '32', apartment_id: '10', person_id: '5', relation: 'resident' }])],
      [/^UPDATE apartment_residencies SET is_current = FALSE/, () => ok([{ id: '1' }])],
      [/^UPDATE apartment_memberships SET is_active = FALSE/, () => ok([{ id: '1' }])],
      [/^UPDATE site_people SET is_active = FALSE/, () => ok([{ id: '5' }])],
    );
    await updatePerson({ siteCode: SITE, personId: 5, body: { is_active: false }, actor });
    const memberships = findAll(/^UPDATE apartment_memberships SET is_active = FALSE/);
    assert.deepEqual(memberships.map((q) => q.params.map(Number)), [[9, 30001], [10, 30001]], 'her daire icin kullanici+daire kapsamli');
    assert.equal(findAll(/^UPDATE apartment_residencies SET is_current = FALSE/).length, 2);
    assert.equal(auditActions().filter((a) => a === 'residency.ended').length, 2);
    assert.ok(auditActions().includes('person.deactivated'));
    assert.equal(has(/DELETE FROM/), false, 'kayitlar silinmez');
    assert.ok(has(/^SELECT DISTINCT devices\.id FROM devices/), 'yerel kontrol anahtari donmesi tetiklendi');
  });

  it('hesapsiz kisi pasif: uyelik/kapi islemi ve anahtar donmesi YOK', async () => {
    handlers.push(
      [lock, () => ok([{ id: '5', user_code: null, full_name: 'Ali', phone: null, email: null, note: null, is_active: true }])],
      [/^SELECT r\.id, r\.apartment_id, r\.person_id, r\.relation FROM apartment_residencies r/, () => ok([{ id: '31', apartment_id: '9', person_id: '5', relation: 'resident' }])],
      [/^UPDATE apartment_residencies SET is_current = FALSE/, () => ok([{ id: '31' }])],
      [/^UPDATE site_people SET is_active = FALSE/, () => ok([{ id: '5' }])],
    );
    await updatePerson({ siteCode: SITE, personId: 5, body: { is_active: false }, actor });
    assert.equal(has(/apartment_memberships|UPDATE apartments/), false);
    assert.equal(has(/^SELECT DISTINCT devices\.id/), false);
  });

  it('is_active:true pasif kisiyi yeniden etkinlestirir (audit person.updated is_active false->true); kisi yok 404', async () => {
    handlers.push([lock, () => ok([{ id: '5', user_code: null, full_name: 'Ali', phone: null, email: null, note: null, is_active: false }])]);
    await updatePerson({ siteCode: SITE, personId: 5, body: { is_active: true }, actor });
    assert.ok(has(/^UPDATE site_people SET is_active = TRUE/));
    assert.deepEqual(auditDetails('person.updated'), { changes: [{ field: 'is_active', from: false, to: true }] });

    install();
    handlers.length = 0;
    await assert.rejects(() => updatePerson({ siteCode: SITE, personId: 5, body: { note: 'x' }, actor }), (e) => e.code === 'PERSON_NOT_FOUND');
    assert.deepEqual(find(lock).params, [5, SITE], 'site kapsamli kilit');
  });
});

// ---------------------------------------------------------------------------
// Iliskiler: ekle / guncelle / tasindi
// ---------------------------------------------------------------------------

describe('iliskiler', () => {
  const personLock = /^SELECT id, user_code, is_active FROM site_people WHERE id = \$1 AND site_code = \$2 FOR UPDATE$/;
  const residencyLookup = /FROM apartment_residencies r INNER JOIN site_people sp ON sp\.id = r\.person_id WHERE r\.id = \$1 AND sp\.site_code = \$2 LIMIT 1 FOR UPDATE OF r$/;

  it('addResidency: hesapliysa daire uyeligi acilir; pasif kisi yeniden etkinlesir; residency.added', async () => {
    handlers.push(
      [personLock, () => ok([{ id: '5', user_code: 30001, is_active: false }])],
      [APARTMENT_LOOKUP, () => ok([APARTMENT_ROW])],
      [/^INSERT INTO apartment_residencies/, () => ok([{ id: '31' }])],
    );
    await addResidency({ siteCode: SITE, personId: 5, body: { apartment_id: 9, relation: 'tenant', move_in_date: '2026-01-02' }, actor });
    assert.deepEqual(find(/^INSERT INTO apartment_residencies/).params, [SITE, 9, 5, 'tenant', '2026-01-02']);
    assert.ok(has(/^UPDATE site_people SET is_active = TRUE/));
    assert.deepEqual(find(/^INSERT INTO apartment_memberships/).params, [9, 30001]);
    assert.deepEqual(auditActions(), ['person.updated', 'residency.added']);
  });

  it('addResidency: ayni kisi/daire zaten guncel -> 409 RESIDENCY_EXISTS; dolu malik/kiraci -> 409 RELATION_TAKEN; baska sitenin dairesi 404', async () => {
    handlers.push([personLock, () => ok([{ id: '5', user_code: null, is_active: true }])], [APARTMENT_LOOKUP, () => ok([APARTMENT_ROW])]);
    handlers.unshift([/^SELECT id FROM apartment_residencies WHERE apartment_id = \$1 AND person_id = \$2 AND is_current = TRUE LIMIT 1$/, () => ok([{ id: '1' }])]);
    await assert.rejects(() => addResidency({ siteCode: SITE, personId: 5, body: { apartment_id: 9 }, actor }), (e) => e.code === 'RESIDENCY_EXISTS' && e.statusCode === 409);

    install();
    handlers.length = 0;
    handlers.push(
      [personLock, () => ok([{ id: '5', user_code: null, is_active: true }])],
      [APARTMENT_LOOKUP, () => ok([APARTMENT_ROW])],
      [/^SELECT id FROM apartment_residencies WHERE apartment_id = \$1 AND is_current = TRUE AND relation = \$2/, () => ok([{ id: '2' }])],
    );
    await assert.rejects(
      () => addResidency({ siteCode: SITE, personId: 5, body: { apartment_id: 9, relation: 'owner' }, actor }),
      (e) => e.code === 'RELATION_TAKEN' && e.message === 'Bu dairede bu ilişki için aktif bir kişi zaten var.',
    );

    install();
    handlers.length = 0;
    handlers.push([personLock, () => ok([{ id: '5', user_code: null, is_active: true }])]);
    await assert.rejects(() => addResidency({ siteCode: SITE, personId: 5, body: { apartment_id: 77 }, actor }), (e) => e.code === 'APARTMENT_NOT_FOUND');
  });

  it('updateResidency: relation degisimi RELATION_TAKEN kontrolunde KENDISINI haric tutar; audit residency.updated changes', async () => {
    handlers.push([residencyLookup, () => ok([{ id: '31', apartment_id: '9', person_id: '5', relation: 'resident', is_current: true, move_in_date: '2025-01-01', move_out_date: null, user_code: null }])]);
    await updateResidency({ siteCode: SITE, residencyId: 31, body: { relation: 'owner', move_in_date: '2025-02-01' }, actor });
    const availability = find(/^SELECT id FROM apartment_residencies WHERE apartment_id = \$1 AND is_current = TRUE AND relation = \$2 AND \(\$3::BIGINT IS NULL OR id <> \$3::BIGINT\)/);
    assert.deepEqual(availability.params, [9, 'owner', 31]);
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
    handlers.push([residencyLookup, () => ok([{ id: '31', apartment_id: '9', person_id: '5', relation: 'owner', is_current: false, move_in_date: '2025-01-01', move_out_date: '2025-06-30', user_code: null }])]);
    await updateResidency({ siteCode: SITE, residencyId: 31, body: { relation: 'owner' }, actor });
    assert.equal(has(/^INSERT INTO audit_log/), false);
    await assert.rejects(() => updateResidency({ siteCode: SITE, residencyId: 31, body: { move_in_date: '2025-07-01' }, actor }), (e) => e.code === 'INVALID_BODY' && /move_in_date/.test(e.message));
    install();
    handlers.length = 0;
    await assert.rejects(() => updateResidency({ siteCode: SITE, residencyId: 31, body: { relation: 'owner' }, actor }), (e) => e.code === 'RESIDENCY_NOT_FOUND');
    assert.deepEqual(find(residencyLookup).params, [31, SITE]);
  });

  describe('endResidency ("Tasindi")', () => {
    const current = (extra = {}) => ({ id: '31', apartment_id: '9', person_id: '5', relation: 'resident', is_current: true, move_in_date: '2025-01-01', move_out_date: null, user_code: 30001, ...extra });

    it('HESAPLI kisi: o dairedeki uyelik pasif + eski modelde resident_user_code bosalir (kapi yetkisi KAPANIR); satir silinmez; anahtar donmesi', async () => {
      handlers.push(
        [residencyLookup, () => ok([current()])],
        [/^UPDATE apartment_residencies SET is_current = FALSE/, () => ok([{ id: '31' }])],
        [/^UPDATE apartment_memberships SET is_active = FALSE/, () => ok([{ id: '1' }])],
        [/^UPDATE apartments SET resident_user_code = NULL/, () => ok([{ id: '9' }])],
        [/^UPDATE site_people SET is_active = FALSE/, () => ok([{ id: '5' }])],
      );
      await endResidency({ siteCode: SITE, residencyId: 31, body: { move_out_date: '2026-03-01' }, actor });
      assert.deepEqual(find(/^UPDATE apartment_residencies SET is_current = FALSE/).params.map(String), ['31', '2026-03-01']);
      const membership = find(/^UPDATE apartment_memberships SET is_active = FALSE/);
      assert.deepEqual(membership.params.map(Number), [9, 30001], 'yalniz O daire ve O kullanici');
      assert.match(membership.sql, /WHERE apartment_id = \$1 AND user_code = \$2 AND is_active = TRUE/);
      const legacy = find(/^UPDATE apartments SET resident_user_code = NULL/);
      assert.deepEqual(legacy.params.map(Number), [9, 30001]);
      assert.match(legacy.sql, /WHERE id = \$1 AND resident_user_code = \$2/);
      assert.equal(has(/DELETE FROM/), false);
      assert.deepEqual(auditActions(), ['residency.ended', 'person.deactivated']);
      assert.deepEqual(auditDetails('residency.ended'), { residency_id: 31, apartment_id: 9, relation: 'resident', move_out_date: '2026-03-01' });
      assert.ok(has(/^SELECT DISTINCT devices\.id FROM devices/), 'yerel kontrol anahtarlari dondurulur (mevcut yetki kaldirma akislariyla ayni)');
    });

    it('kisinin BASKA guncel iliskisi varsa kisi pasif OLMAZ (person.deactivated yok)', async () => {
      handlers.push(
        [residencyLookup, () => ok([current()])],
        [/^UPDATE apartment_residencies SET is_current = FALSE/, () => ok([{ id: '31' }])],
        [/^UPDATE apartment_memberships SET is_active = FALSE/, () => ok([{ id: '1' }])],
        [/^SELECT 1 FROM apartment_residencies WHERE person_id = \$1 AND is_current = TRUE LIMIT 1$/, () => ok([{ x: 1 }])],
      );
      await endResidency({ siteCode: SITE, residencyId: 31, body: {}, actor });
      assert.equal(has(/^UPDATE site_people SET is_active = FALSE/), false);
      assert.deepEqual(auditActions(), ['residency.ended']);
    });

    it('HESAPSIZ kisi: uyelik/kapi islemi ve anahtar donmesi YOK; varsayilan cikis tarihi bugun', async () => {
      handlers.push(
        [residencyLookup, () => ok([current({ user_code: null })])],
        [/^UPDATE apartment_residencies SET is_current = FALSE/, () => ok([{ id: '31' }])],
      );
      await endResidency({ siteCode: SITE, residencyId: 31, body: {}, actor });
      assert.equal(has(/apartment_memberships|UPDATE apartments/), false);
      assert.equal(has(/^SELECT DISTINCT devices\.id/), false);
      assert.match(find(/^UPDATE apartment_residencies SET is_current = FALSE/).params[1], /^\d{4}-\d{2}-\d{2}$/);
    });

    it('erisim zaten kapaliysa (uyelik pasif, sakin sifirlanmis) anahtar DONMEZ', async () => {
      handlers.push([residencyLookup, () => ok([current()])], [/^UPDATE apartment_residencies SET is_current = FALSE/, () => ok([{ id: '31' }])]);
      await endResidency({ siteCode: SITE, residencyId: 31, body: {}, actor });
      assert.equal(has(/^SELECT DISTINCT devices\.id/), false);
    });

    it('zaten sona ermis kayit 409 RESIDENCY_NOT_CURRENT; cikis tarihi giris tarihinden once 400; yok kayit 404', async () => {
      handlers.push([residencyLookup, () => ok([current({ is_current: false, move_out_date: '2025-05-01' })])]);
      await assert.rejects(() => endResidency({ siteCode: SITE, residencyId: 31, body: {}, actor }), (e) => e.code === 'RESIDENCY_NOT_CURRENT' && e.statusCode === 409);
      install();
      handlers.length = 0;
      handlers.push([residencyLookup, () => ok([current()])]);
      await assert.rejects(() => endResidency({ siteCode: SITE, residencyId: 31, body: { move_out_date: '2024-12-31' }, actor }), (e) => e.code === 'INVALID_BODY' && /move_out_date/.test(e.message));
      install();
      handlers.length = 0;
      await assert.rejects(() => endResidency({ siteCode: SITE, residencyId: 31, body: {}, actor }), (e) => e.code === 'RESIDENCY_NOT_FOUND');
    });
  });
});

// ---------------------------------------------------------------------------
// Daire alanlari
// ---------------------------------------------------------------------------

describe('updateApartment', () => {
  const lockApartment = /^SELECT floor, gross_area_m2, net_area_m2, land_share_numerator, land_share_denominator, category, responsible_party FROM apartments WHERE id = \$1 AND site_code = \$2 FOR UPDATE$/;
  const row = (extra = {}) => ({ floor: 2, gross_area_m2: '120.50', net_area_m2: null, land_share_numerator: null, land_share_denominator: null, category: null, responsible_party: 'both', ...extra });

  it('degisen alanlar UPDATE edilir, audit apartment.updated details.changes (from/to); mevcut unit_label/blok yapisina dokunulmaz', async () => {
    handlers.push([lockApartment, () => ok([row()])]);
    await updateApartment({ siteCode: SITE, apartmentId: 9, body: { floor: 3, gross_area_m2: 120.5, category: '3+1', land_share_numerator: 35, land_share_denominator: 1000 }, actor });
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
    handlers.push([lockApartment, () => ok([row({ land_share_numerator: 35, land_share_denominator: 1000 })])]);
    await updateApartment({ siteCode: SITE, apartmentId: 9, body: { floor: 2, responsible_party: 'both' }, actor });
    assert.equal(has(/^UPDATE apartments/), false);
    assert.equal(has(/^INSERT INTO audit_log/), false);
    // payda silinip pay kalamaz
    await assert.rejects(() => updateApartment({ siteCode: SITE, apartmentId: 9, body: { land_share_denominator: null }, actor }), (e) => e.code === 'INVALID_BODY' && /land_share/.test(e.message));
    install();
    handlers.length = 0;
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

  it('createVehicle: plaka normalize (34 abc 123 -> 34ABC123), vehicle.added audit, site kilidi altinda', async () => {
    handlers.push([personExists, () => ok([{ id: '5' }])], [/^INSERT INTO vehicles/, () => ok([{ id: '4' }])]);
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
    await assert.rejects(() => createVehicle({ siteCode: SITE, body: { person_id: 5, plate: '34ABC123' }, actor }), (e) => e.code === 'PERSON_NOT_FOUND');
    assert.deepEqual(find(personExists).params, [5, SITE], 'baska sitenin kisisine arac eklenemez');
    await assert.rejects(() => createVehicle({ siteCode: SITE, body: { person_id: 5, plate: '??' }, actor }), (e) => e.code === 'PLATE_INVALID');
  });

  it('removeVehicle: is_active=false (kayit KALIR), vehicle.removed audit; yok / zaten kaldirilmis 404', async () => {
    handlers.push([/^SELECT id, plate, person_id FROM vehicles WHERE id = \$1 AND site_code = \$2 AND is_active = TRUE FOR UPDATE$/, () => ok([{ id: '4', plate: '34ABC123', person_id: '5' }])]);
    assert.deepEqual(await removeVehicle({ siteCode: SITE, vehicleId: 4, actor }), { ok: true });
    assert.deepEqual(find(/^UPDATE vehicles SET is_active = FALSE WHERE id = \$1$/).params, [4]);
    assert.equal(has(/DELETE FROM vehicles/), false);
    assert.deepEqual(auditDetails('vehicle.removed'), { plate: '34ABC123', person_id: 5 });
    install();
    handlers.length = 0;
    await assert.rejects(() => removeVehicle({ siteCode: SITE, vehicleId: 4, actor }), (e) => e.code === 'VEHICLE_NOT_FOUND' && e.statusCode === 404);
  });
});
