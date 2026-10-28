// Sakin "Yoneticiyi ara" ucu (GET /app/manager-contact -> getResidentManagerContacts): profil telefonu yalniz site bagi olan
// oturuma doner, telefon yoksa null (uydurma numara yok), kendi sitesinin yoneticisi is_self ile numarasiz doner, birden cok
// yoneticide telefonu olan ILK yonetici secilir, kisisel alan (e-posta, kullanici kodu) sizmaz, Rehber modulunden bagimsizdir.
// DB gerektirmez (SQL metnini taklit eden sahte havuz).
import { describe, it, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { pool } from '../src/db.js';
import { dialablePhone, getResidentManagerContacts } from '../src/modules/team_service.js';

const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
const SITE_A = 1000000001;
const SITE_B = 1000000002;

let sitesOfUser;
let managerRows;
let log;

beforeEach(() => {
  sitesOfUser = [{ site_code: String(SITE_A), site_name: 'Gul Sitesi' }];
  managerRows = [];
  log = [];
  pool.query = async (text, params) => {
    const sql = norm(text);
    log.push({ sql, params });
    if (/^SELECT s\.site_code, s\.name AS site_name FROM sites s/.test(sql)) return { rows: sitesOfUser, rowCount: sitesOfUser.length };
    if (/FROM site_manager_sites WHERE site_code = ANY\(\$1::bigint\[\]\)/.test(sql)) {
      const wanted = new Set(params[0].map(Number));
      const rows = managerRows.filter((row) => wanted.has(Number(row.site_code)));
      return { rows, rowCount: rows.length };
    }
    throw new Error(`BEKLENMEYEN SQL (sahte DB kati): ${sql.slice(0, 160)}`);
  };
});

afterEach(() => {
  delete pool.query;
});

const resident = { user_code: 501, role: 'apartment_owner', full_name: 'Sakin Kisi' };
const manager = (user, name, phone, site = SITE_A) => ({ site_code: String(site), user_code: user, full_name: name, phone_number: phone });

describe('dialablePhone (saf)', () => {
  it('bosluk, parantez ve tireyi atar; bastaki + korunur', () => {
    assert.equal(dialablePhone('0532 123 45 67'), '05321234567');
    assert.equal(dialablePhone('+90 (532) 123-45-67'), '+905321234567');
    assert.equal(dialablePhone('  0212.555.12.34 '), '02125551234');
  });

  it('harf, yildiz, diyez, kisa / uzun / bos degerleri reddeder (ozel kod aratmaz)', () => {
    for (const bad of ['abc', '*123#', '0532 123 45 6x', '123456', '1234567890123456', '', '   ', null, undefined, 5321234567]) {
      assert.equal(dialablePhone(bad), null, `${String(bad)} reddedilmeli`);
    }
    assert.equal(dialablePhone('12345 + 678'), null, 'ortadaki + gecersiz');
  });
});

describe('GET /app/manager-contact servisi', () => {
  it('telefonu kayitli yoneticiyi dondurur; yalniz ad ve numara (e-posta / kullanici kodu yok)', async () => {
    managerRows = [manager(900, 'Ali Yonetici', '0532 123 45 67')];
    const out = await getResidentManagerContacts(resident);
    assert.deepEqual(out, {
      sites: [{ site_code: SITE_A, site_name: 'Gul Sitesi', manager_name: 'Ali Yonetici', manager_phone: '05321234567', is_self: false }],
    });
    const managerSql = log.find((entry) => /FROM site_manager_sites/.test(entry.sql)).sql;
    assert.match(managerSql, /SELECT m\.site_code, u\.user_code, u\.full_name, u\.phone_number FROM/);
    assert.doesNotMatch(managerSql, /u\.email|password|login_name/i, 'kisisel alan secilmemeli');
    assert.match(managerSql, /u\.deleted_at IS NULL AND u\.is_active = TRUE/, 'silinmis / pasif yonetici sayilmaz');
    assert.match(managerSql, /role IN \('SITE_OWNER', 'SITE_ADMIN'\) AND is_active = TRUE/);
  });

  it('telefon kayitli degilse manager_phone null (ad yine gelir); hicbir yonetici yoksa ikisi de null', async () => {
    managerRows = [manager(900, 'Ali Yonetici', null)];
    let out = await getResidentManagerContacts(resident);
    assert.equal(out.sites[0].manager_name, 'Ali Yonetici');
    assert.equal(out.sites[0].manager_phone, null);
    assert.equal(out.sites[0].is_self, false);

    managerRows = [];
    out = await getResidentManagerContacts(resident);
    assert.equal(out.sites[0].manager_name, null);
    assert.equal(out.sites[0].manager_phone, null);
  });

  it('gecersiz (harfli / cok kisa) profil telefonu numara sayilmaz', async () => {
    managerRows = [manager(900, 'Ali Yonetici', 'yok'), manager(901, 'Veli Yonetici', '123')];
    const out = await getResidentManagerContacts(resident);
    assert.equal(out.sites[0].manager_phone, null);
    assert.equal(out.sites[0].manager_name, 'Ali Yonetici', 'telefon yoksa ilk yoneticinin adi');
  });

  it('birden cok yoneticide telefonu olan ILK yonetici secilir; ayni kisi iki kaynakta olsa tekrarlanmaz', async () => {
    managerRows = [
      manager(900, 'Ali Yonetici', null),
      manager(901, 'Veli Yonetici', '+90 212 555 12 34'),
      manager(901, 'Veli Yonetici', '+90 212 555 12 34'),
      manager(902, 'Ayse Yonetici', '0533 000 00 00'),
    ];
    const out = await getResidentManagerContacts(resident);
    assert.equal(out.sites[0].manager_name, 'Veli Yonetici');
    assert.equal(out.sites[0].manager_phone, '+902125551234');
  });

  it('cagiran o sitenin yoneticisiyse is_self true, numara ve ad donmez', async () => {
    managerRows = [manager(501, 'Sakin Kisi', '0532 111 11 11'), manager(900, 'Ali Yonetici', '0532 123 45 67')];
    const out = await getResidentManagerContacts(resident);
    assert.deepEqual(out.sites[0], { site_code: SITE_A, site_name: 'Gul Sitesi', manager_name: null, manager_phone: null, is_self: true });
  });

  it('birden cok sitede her site kendi yoneticisini alir', async () => {
    sitesOfUser = [
      { site_code: String(SITE_A), site_name: 'Gul Sitesi' },
      { site_code: String(SITE_B), site_name: 'Lale Sitesi' },
    ];
    managerRows = [manager(900, 'Ali Yonetici', '0532 123 45 67', SITE_A), manager(950, 'Can Yonetici', null, SITE_B)];
    const out = await getResidentManagerContacts(resident);
    assert.deepEqual(
      out.sites.map((s) => [s.site_code, s.manager_name, s.manager_phone]),
      [
        [SITE_A, 'Ali Yonetici', '05321234567'],
        [SITE_B, 'Can Yonetici', null],
      ],
    );
    const call = log.find((entry) => /FROM site_manager_sites/.test(entry.sql));
    assert.deepEqual(call.params[0], [SITE_A, SITE_B]);
  });

  it('siteye bagi olmayan sakine bos liste doner ve yonetici sorgusu hic calismaz', async () => {
    sitesOfUser = [];
    const out = await getResidentManagerContacts(resident);
    assert.deepEqual(out, { sites: [] });
    assert.equal(log.some((entry) => /site_manager_sites/.test(entry.sql)), false);
  });

  it('kimliksiz (user_code yok) cagri bos liste doner, DB sorgulanmaz', async () => {
    const out = await getResidentManagerContacts({ role: 'apartment_owner' });
    assert.deepEqual(out, { sites: [] });
    assert.equal(log.length, 0);
  });

  it('kapsam getResidentDirectory ile ayni: daire uyeligi + kurul / gorevli uyeligi; Rehber modulu sorgulanmaz', async () => {
    managerRows = [manager(900, 'Ali Yonetici', '0532 123 45 67')];
    await getResidentManagerContacts(resident);
    const sitesSql = log[0].sql;
    assert.match(sitesSql, /FROM apartment_memberships am INNER JOIN apartments a ON a\.id = am\.apartment_id/);
    assert.match(sitesSql, /m\.role IN \('BOARD_MEMBER', 'STAFF'\)/);
    assert.deepEqual(log[0].params, [501]);
    assert.equal(log.some((entry) => /site_modules|directory/i.test(entry.sql)), false, 'modul kapisi yok');
  });
});
