// Coklu malik (104) saf kurallar ve kaynak denetimleri (DB'siz):
//  - rol cozumleme: owner = HESAP MUHATABI; digerleri coOwners; malik yetkisi yok (is_owner=false, can{} hepsi false, my_role co_owner)
//  - hizmet girdi ayristiricilari ve yeni muhatap secimi
//  - borc / tahakkuk tarafi muhataba bakar (finans sorgularinda muhatap suzgeci; kisinin hesabi); eski veri (tek malik) birebir ayni sonuc
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { adminSideOf, disconnectCounterpart, pickSigningHolder, resolveApartmentRoles, rolesOfUser } from '../src/modules/apartment_mgmt_rules.js';
import {
  OWNER_LIMIT,
  parseAddOwnerBody,
  parseRemoveOwnerBody,
  parseSetHolderBody,
  pickReplacementHolder,
} from '../src/modules/apartment_owners_service.js';
import { mapOwners, ownersOf } from '../src/modules/apartment_records_service.js';
import { resolvePersonParty } from '../src/modules/finance_parties.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const read = (relative) => readFileSync(path.join(here, '..', relative), 'utf8').replace(/\r\n/g, '\n');

const res = (id, person, user, relation, extra = {}) => ({ id, person_id: person, user_code: user, relation, name: `Kisi ${person}`, ...extra });
const members = (...codes) => codes.map((code, index) => ({ user_code: code, role: index === 0 ? 'APARTMENT_ADMIN' : 'FAMILY_MEMBER', is_active: true, created_at: `2026-01-0${index + 1}` }));

describe('resolveApartmentRoles: coklu malik', () => {
  it('owner = muhatap bayragi true olan malik (listede ikinci olsa bile); digerleri coOwners', () => {
    const roles = resolveApartmentRoles({
      members: members(101),
      residencies: [
        res(1, 10, 101, 'owner', { is_account_holder: false }),
        res(2, 11, 102, 'owner', { is_account_holder: true }),
        res(3, 12, null, 'owner', { is_account_holder: false }),
      ],
    });
    assert.equal(roles.owner.person_id, 11);
    assert.deepEqual(roles.coOwners.map((r) => r.person_id), [10, 12]);
  });

  it('bayrak bilgisi yoksa (eski kayit / test girdisi) ilk malik muhatap sayilir: ESKI davranis birebir', () => {
    const roles = resolveApartmentRoles({ members: members(101), residencies: [res(1, 10, 101, 'owner'), res(5, 20, 105, 'tenant')] });
    assert.equal(roles.owner.person_id, 10);
    assert.deepEqual(roles.coOwners, []);
    assert.equal(roles.tenant.person_id, 20);
  });

  it('hic muhatap bayragi yok ama birden cok malik (olmamasi gereken durum): ilk malik secilir, cokmez', () => {
    const roles = resolveApartmentRoles({
      members: [],
      residencies: [res(1, 10, null, 'owner', { is_account_holder: false }), res(2, 11, null, 'owner', { is_account_holder: false })],
    });
    assert.equal(roles.owner.person_id, 10);
    assert.equal(roles.coOwners.length, 1);
  });

  it('malik yok: owner null, coOwners []', () => {
    const roles = resolveApartmentRoles({ members: [], residencies: [res(1, 10, 101, 'tenant')] });
    assert.equal(roles.owner, null);
    assert.deepEqual(roles.coOwners, []);
  });

  it('yonetimi yapan diger malikse taraf etiketi "malik" (yetki degil): adminKind owner, adminSideOf owner', () => {
    const roles = resolveApartmentRoles({
      members: members(102),
      residencies: [res(1, 10, 101, 'owner', { is_account_holder: true }), res(2, 11, 102, 'owner', { is_account_holder: false })],
    });
    assert.equal(roles.adminUserCode, 102);
    assert.equal(roles.adminKind, 'owner');
    assert.equal(adminSideOf(roles), 'owner');
  });
});

describe('rolesOfUser: diger malik malik YETKISI tasimaz', () => {
  const roles = resolveApartmentRoles({
    members: members(101, 102, 103),
    residencies: [
      res(1, 10, 101, 'owner', { is_account_holder: true }),
      res(2, 11, 102, 'owner', { is_account_holder: false }),
      res(3, 12, 103, 'tenant'),
    ],
  });

  it('muhatap: owner, kiraci ekleme / vekalet / kisi arama yetkileri eskisi gibi', () => {
    const me = rolesOfUser(roles, 101, { hasMembership: true });
    assert.equal(me.my_role, 'owner');
    assert.equal(me.is_owner, true);
    assert.equal(me.is_co_owner, false);
    assert.equal(me.can.request_disconnect, true);
    assert.equal(me.can.manage_proxy, true);
    assert.equal(me.can.search_people, true);
  });

  it('diger malik: my_role co_owner, is_owner=false, HICBIR yetki yok', () => {
    const me = rolesOfUser(roles, 102, { hasMembership: true });
    assert.equal(me.my_role, 'co_owner');
    assert.equal(me.is_owner, false);
    assert.equal(me.is_co_owner, true);
    assert.equal(me.is_family, false);
    assert.deepEqual(Object.values(me.can).filter(Boolean), []);
  });

  it('baglanti kesme karsi tarafi muhatap: kiraci acarsa onaylayan muhatap; diger malik onaylayici DEGIL', () => {
    assert.equal(disconnectCounterpart(roles, 103), 101);
    assert.equal(disconnectCounterpart(roles, 102), null);
  });

  it('imza hakki (vekil yoksa) hesap muhatabinda: pickSigningHolder tek kisi doner', () => {
    const holder = pickSigningHolder({ owner: { person_id: roles.owner.person_id, name: 'M1' }, proxies: [], today: '2026-10-28' });
    assert.equal(holder.kind, 'owner');
    assert.equal(holder.person_id, 10);
  });

  it('tek malikli eski dairede sonuc eskisiyle ayni: is_co_owner false, my_role owner', () => {
    const single = resolveApartmentRoles({ members: members(101), residencies: [res(1, 10, 101, 'owner')] });
    const me = rolesOfUser(single, 101, { hasMembership: true });
    assert.equal(me.my_role, 'owner');
    assert.equal(me.is_co_owner, false);
    assert.equal(rolesOfUser(single, 999, { hasMembership: false }).is_co_owner, false);
  });
});

describe('hizmet girdi ayristiricilari', () => {
  it('malik ekle: kayitli kisi YA DA yeni kisi; ikisi ya da hicbiri olmaz', () => {
    assert.deepEqual(parseAddOwnerBody({ person_id: '7' }), { personId: 7, person: null, makeAccountHolder: false, moveInDate: null });
    const created = parseAddOwnerBody({ person: { full_name: '  Ayse   Yilmaz ', phone: '0532 111 22 33', email: 'AYSE@Example.com' }, make_account_holder: true });
    assert.deepEqual(created.person, { fullName: 'Ayse Yilmaz', phone: '+905321112233', email: 'ayse@example.com' });
    assert.equal(created.makeAccountHolder, true);
    for (const bad of [{}, { person_id: 1, person: { full_name: 'Ali Veli' } }, { person_id: 0 }, { person: [] }, { person: { full_name: 'A' } }, { person_id: 3, make_account_holder: 1 }]) {
      assert.throws(() => parseAddOwnerBody(bad), (error) => error.statusCode === 400 && error.code === 'INVALID_BODY', JSON.stringify(bad));
    }
  });

  it('muhatap degistir ve cikar govdeleri', () => {
    assert.deepEqual(parseSetHolderBody({ residency_id: 12 }), { residencyId: 12 });
    assert.throws(() => parseSetHolderBody({}), (error) => error.code === 'INVALID_BODY');
    assert.deepEqual(parseRemoveOwnerBody({}), { newHolderResidencyId: null, moveOutDate: null });
    assert.deepEqual(parseRemoveOwnerBody({ new_account_holder_residency_id: '5', move_out_date: '2026-10-01' }), { newHolderResidencyId: 5, moveOutDate: '2026-10-01' });
    assert.throws(() => parseRemoveOwnerBody({ new_account_holder_residency_id: 'x' }), (error) => error.code === 'INVALID_BODY');
    assert.throws(() => parseRemoveOwnerBody({ move_out_date: '2026-13-40' }), (error) => error.code === 'INVALID_BODY');
  });

  it('yeni muhatap secimi: istenen baska bir malik olmali; istenmezse tek kalan otomatik; birden cok kalirsa secim zorunlu', () => {
    const owners = [
      { residency_id: 1, is_account_holder: true },
      { residency_id: 2, is_account_holder: false },
      { residency_id: 3, is_account_holder: false },
    ];
    assert.deepEqual(pickReplacementHolder(owners, 1, 3), { replacement: owners[2], error: null });
    assert.deepEqual(pickReplacementHolder(owners, 1, 1), { replacement: null, error: 'REPLACEMENT_INVALID' }, 'cikarilanin kendisi olamaz');
    assert.deepEqual(pickReplacementHolder(owners, 1, 99), { replacement: null, error: 'REPLACEMENT_INVALID' });
    assert.deepEqual(pickReplacementHolder(owners, 1, null), { replacement: null, error: 'ACCOUNT_HOLDER_REQUIRED' });
    assert.deepEqual(pickReplacementHolder(owners.slice(0, 2), 1, null), { replacement: owners[1], error: null });
    assert.deepEqual(pickReplacementHolder(owners.slice(0, 1), 1, null), { replacement: null, error: 'REPLACEMENT_INVALID' });
  });

  it('sinir 10', () => {
    assert.equal(OWNER_LIMIT, 10);
  });
});

describe('daire karti malik listesi (saf)', () => {
  const rows = [
    { residency_id: 5, person_id: 50, full_name: 'B', is_account_holder: false, has_account: false, move_in_date: '2024-01-01' },
    { residency_id: 4, person_id: 40, full_name: 'A', is_account_holder: true, has_account: true, move_in_date: null },
    { residency_id: 6, person_id: 60, full_name: 'T', relation: 'tenant' },
  ].map((r) => ({ relation: 'owner', ...r }));

  it('ownersOf: yalniz maliklar, muhatap basta, kalan kayit sirasi', () => {
    assert.deepEqual(ownersOf(rows.map((r) => ({ ...r, is_current: true }))).map((r) => r.residency_id), [4, 5]);
  });

  it('mapOwners: API bicimi; kullanici kodu / iletisim alani sizmaz', () => {
    const mapped = mapOwners(rows.map((r) => ({ ...r, user_code: 777, phone: '+905551112233' })));
    assert.deepEqual(mapped, [
      { residency_id: 4, person_id: 40, full_name: 'A', has_account: true, is_account_holder: true, move_in_date: null },
      { residency_id: 5, person_id: 50, full_name: 'B', has_account: false, is_account_holder: false, move_in_date: '2024-01-01' },
    ]);
  });
});

describe('finans: borc hesabi MUHATABA bakar (kaynak ve davranis)', () => {
  it('resolvePersonParty: muhatap owner; diger malik null (borc hesabi yok); bayrak bilgisi olmayan eski satir owner (eski davranis)', async () => {
    const fake = (row) => ({ query: async () => ({ rows: row ? [row] : [] }) });
    const args = { siteCode: 1, apartmentId: 2, userCode: 3 };
    assert.equal(await resolvePersonParty(fake({ relation: 'owner', is_account_holder: true, has_tenant: false }), args), 'owner');
    assert.equal(await resolvePersonParty(fake({ relation: 'owner', is_account_holder: false, has_tenant: false }), args), null);
    assert.equal(await resolvePersonParty(fake({ relation: 'owner', has_tenant: false }), args), 'owner', 'bayrak alani yoksa eski sonuc');
    assert.equal(await resolvePersonParty(fake({ relation: 'tenant', is_account_holder: false, has_tenant: true }), args), 'tenant');
    assert.equal(await resolvePersonParty(fake({ relation: 'resident', has_tenant: true }), args), 'tenant');
    assert.equal(await resolvePersonParty(fake({ relation: 'family_member', has_tenant: false }), args), null);
    assert.equal(await resolvePersonParty(fake(null), args), null);
  });

  it('sakin gorunumu, hatirlatma alicilari, ekstre / makbuz / rapor adlari, bakiye listesi: muhatap suzgeci ya da muhatap-ilk siralama', () => {
    const readService = read('src/modules/finance_read_service.js');
    assert.match(readService, /AND r\.relation <> 'family_member'\s+AND \(r\.relation <> 'owner' OR r\.is_account_holder = TRUE\)/, 'Borcum gorunumu (loadVisibleAccounts)');
    assert.match(readService, /WHERE r\.apartment_id = f\.apartment_id AND r\.is_current = TRUE AND r\.relation = '\$\{relation\}'\s+ORDER BY r\.is_account_holder DESC, r\.id/, 'bakiye listesi malik adi');
    assert.match(read('src/modules/finance_reminders.js'), /AND rr\.relation <> 'family_member'\s+AND \(rr\.relation <> 'owner' OR rr\.is_account_holder = TRUE\)/, 'hatirlatma alicilari');
    assert.match(read('src/modules/finance_receipts.js'), /AND r\.relation = \$2\s+ORDER BY r\.is_account_holder DESC, r\.id/, 'makbuz odeyen adi');
    assert.match(read('src/modules/finance_reports.js'), /ORDER BY r\.apartment_id, r\.is_account_holder DESC, r\.id/, 'rapor adlari');
    assert.match(read('src/modules/bulk_import_export.js'), /ORDER BY r\.is_account_holder DESC, r\.id/, 'disa aktarma malik sutunu');
    assert.match(read('src/services/apartment_service.js'), /ar\.is_account_holder DESC,\s+ar\.id ASC/, 'daire listesi sakin adi');
  });

  it('borc / tahakkuk / tahsilat YAZIMI is_account_holder\'a bagli DEGIL: finans dosyalarinda bayragi yalniz 5 OKUMA dosyasi kullanir (hesap daireye baglidir)', () => {
    // Tahakkuk, tahsilat ve defter yazimi kisi degil daire + hesap (owner / tenant, ledger_entries.account_party) uzerinden yapilir;
    // muhatap yalniz "bu hesap kime hitap eder" (ekstre / makbuz adi, hatirlatma alicisi, sakin "Borcum" gorunumu, kisinin hesabi) bilgisidir.
    const dir = path.join(here, '..', 'src', 'modules');
    const using = readdirSync(dir)
      .filter((file) => /^(finance_|payment_notice|bank_|metering)/.test(file) && file.endsWith('.js'))
      .filter((file) => /is_account_holder/.test(readFileSync(path.join(dir, file), 'utf8')))
      .sort();
    assert.deepEqual(using, ['finance_parties.js', 'finance_read_service.js', 'finance_receipts.js', 'finance_reminders.js', 'finance_reports.js']);
    for (const writer of ['finance_ledger_service.js', 'finance_accounts.js', 'finance_service.js']) {
      assert.ok(readdirSync(dir).includes(writer), `${writer} var (yazma tarafi taranmali)`);
      assert.doesNotMatch(read(`src/modules/${writer}`), /is_account_holder/);
    }
  });

  it('CRM / yonetim sorgulari muhatap bayragini okur: rol cozumleme, halk, imza listesi, yonetici adaylari', () => {
    assert.match(read('src/modules/apartment_mgmt_core.js'), /SELECT r\.id, r\.person_id, r\.relation, r\.is_account_holder,/);
    assert.match(read('src/modules/apartment_mgmt_household.js'), /SELECT r\.id, r\.person_id, r\.relation, r\.is_account_holder,/);
    assert.match(read('src/modules/apartment_mgmt_proxy.js'), /r\.person_id, r\.is_account_holder,/);
    assert.match(read('src/modules/apartment_mgmt_service.js'), /r\.relation = 'owner' AND r\.is_account_holder = TRUE AND sp\.user_code = \$1/);
  });
});
