// Kiraci her zaman daire admini (kullanici karari 2026-10-26; migration 081): saf SQL metni / sarmalayici / kablolama testleri (DB'siz).
// SQL'in gercek anlami gercek PostgreSQL'de sinanir: scripts/qa_platform_pg.mjs bolum "tenant_admin" (scripts/qa_tenant_admin_section.mjs).
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  TENANT_ADMIN_BACKFILL_CHECK_SQL,
  TENANT_ADMIN_BACKFILL_PARAMS,
  TENANT_ADMIN_BACKFILL_SQL,
  TENANT_ADMIN_CHECK_SQL,
  TENANT_ADMIN_COUNT_INDEX,
  TENANT_ADMIN_STATEMENTS,
  ensureTenantAdminRule,
  inlineTenantAdminParams,
} from '../src/modules/apartment_tenant_admin_sql.js';
import { ensureTenantIsAdmin } from '../src/modules/apartment_tenant_admin.js';
import { ADMIN_SUCCESSOR_SQL, pickAdminSuccessor } from '../src/modules/apartment_admin_successor.js';
import { handOverApartmentResident } from '../src/services/membership_service.js';
import * as rules from '../src/modules/apartment_mgmt_rules.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const read = (rel) => fs.readFileSync(path.resolve(here, '..', rel), 'utf8').replace(/\r\n/g, '\n');
const norm = (text) => String(text).replace(/\s+/g, ' ').trim();

describe('migrations/081 = acilis adimi (aynı SQL)', () => {
  it('migration dosyası TENANT_ADMIN_BACKFILL_SQL ile biter; 081 numaralı tek dosya', () => {
    const migration = read('migrations/081_tenant_is_apartment_admin.sql');
    assert.ok(migration.endsWith(TENANT_ADMIN_BACKFILL_SQL), 'migration gövdesi TENANT_ADMIN_BACKFILL_SQL ile aynı olmalı');
    assert.match(migration, /^-- 081: Kiracı her zaman daire admini/);
    const files = fs.readdirSync(path.resolve(here, '..', 'migrations')).filter((name) => name.startsWith('081_'));
    assert.deepEqual(files, ['081_tenant_is_apartment_admin.sql']);
  });

  it('db.js açılışta tek çağrı yapar (hata açılışı durdurmaz); kural adımı db.js\'i içe aktarmaz', () => {
    const db = read('src/db.js');
    assert.match(db, /import \{ ensureTenantAdminRule \} from '\.\/modules\/apartment_tenant_admin_sql\.js';/);
    assert.equal((db.match(/ensureTenantAdminRule\(client\)/g) ?? []).length, 1);
    assert.match(db, /\[DB\] 081 kiraci admin kurali hatasi/);
    assert.doesNotMatch(read('src/modules/apartment_tenant_admin_sql.js'), /^import /m, 'SQL modülü hiçbir şeyi içe aktarmaz (db.js döngüsü olmasın)');
  });

  it('parametresiz metin: yer tutucu kalmadı, sistem adına, tüm daireler, site yöneticisi devri korunur', () => {
    assert.doesNotMatch(TENANT_ADMIN_BACKFILL_SQL, /\$[1-8]\b/);
    assert.doesNotMatch(TENANT_ADMIN_BACKFILL_CHECK_SQL, /\$[1-8]\b/);
    assert.deepEqual([...TENANT_ADMIN_BACKFILL_PARAMS], [null, null, false, 'backfill', null, 'Sistem', 'system', 'system']);
    assert.match(TENANT_ADMIN_BACKFILL_SQL, /NULL::BIGINT\[\] IS NULL/);
    assert.match(TENANT_ADMIN_BACKFILL_SQL, /FALSE::BOOLEAN OR NOT EXISTS/);
    assert.match(TENANT_ADMIN_BACKFILL_SQL, /'backfill'::TEXT AS via/);
    assert.equal(TENANT_ADMIN_BACKFILL_SQL.split(';\n\n').length, TENANT_ADMIN_STATEMENTS.length);
    assert.ok(TENANT_ADMIN_BACKFILL_SQL.endsWith(';\n'));
  });

  it('inlineTenantAdminParams: null / boolean / sayı / metin (tek tırnak kaçışlı)', () => {
    assert.equal(inlineTenantAdminParams('$1 $2 $3 $4 $5 $6 $7 $8', [null, true, false, 7, "it's", undefined, 'x', 'y']), "NULL TRUE FALSE 7 'it''s' NULL 'x' 'y'");
    assert.equal(inlineTenantAdminParams('$10', [1]), '$10', 'yalnız $1..$8');
  });
});

describe('ifade yapısı ve güvenlik koşulları', () => {
  it('8 ifade: 0 yalnız kilit (id sırasıyla FOR UPDATE), 1 denetim, son ifade rol güncellemesi; kilit yalnız 0. ifadede', () => {
    assert.equal(TENANT_ADMIN_STATEMENTS.length, 8);
    assert.match(TENANT_ADMIN_STATEMENTS[0], /^SELECT a\.id FROM apartments a\nWHERE a\.id IN \(SELECT c\.apartment_id FROM \(/);
    assert.match(TENANT_ADMIN_STATEMENTS[0], /ORDER BY a\.id\nFOR UPDATE OF a$/);
    assert.equal(TENANT_ADMIN_COUNT_INDEX, 1);
    assert.match(TENANT_ADMIN_STATEMENTS[TENANT_ADMIN_COUNT_INDEX], /^INSERT INTO audit_log .*'apartment\.admin_tenant_enforced'/s);
    assert.match(TENANT_ADMIN_STATEMENTS[7], /^UPDATE apartment_memberships m\nSET role = CASE WHEN m\.user_code = c\.tenant_user_code THEN 'APARTMENT_ADMIN' ELSE 'FAMILY_MEMBER' END/);
    assert.deepEqual(TENANT_ADMIN_STATEMENTS.map((sql) => /FOR UPDATE/.test(sql)), [true, false, false, false, false, false, false, false]);
    assert.doesNotMatch(TENANT_ADMIN_CHECK_SQL, /FOR UPDATE/, 'aday kontrolü kilitsiz okumadır');
  });

  it('her ifade ve kontrol sorgusu $1..$8 parametrelerinin HEPSİNİ kullanır (pg: parametre sayısı ifadeyle eşleşmeli)', () => {
    for (const sql of [...TENANT_ADMIN_STATEMENTS, TENANT_ADMIN_CHECK_SQL]) {
      for (let index = 1; index <= 8; index += 1) {
        assert.match(sql, new RegExp(`\\$${index}(?![0-9])`), `$${index} eksik: ${norm(sql).slice(0, 70)}`);
      }
    }
  });

  it('aday koşulları: hesaplı + aktif + silinmemiş kiracı, AKTİF üyelik, askıda değil, aktif daire, site yöneticisi devri korunur (yetkiyi genişletmez)', () => {
    const check = norm(TENANT_ADMIN_CHECK_SQL);
    assert.match(check, /r\.is_current = TRUE AND r\.relation = 'tenant'/);
    assert.match(check, /sp\.is_active = TRUE AND sp\.user_code IS NOT NULL/);
    assert.match(check, /u\.deleted_at IS NULL AND u\.is_active = TRUE/);
    assert.match(check, /tm\.user_code = sp\.user_code AND tm\.is_active = TRUE/);
    assert.match(check, /a\.is_active = TRUE/);
    assert.match(check, /apartment_access_suspensions s WHERE s\.apartment_id = a\.id AND s\.user_code = sp\.user_code AND s\.lifted_at IS NULL/);
    assert.match(check, /\$3::BOOLEAN OR NOT EXISTS \( SELECT 1 FROM apartment_admin_delegations d WHERE d\.apartment_id = a\.id AND d\.ended_at IS NULL AND d\.source = 'manager'/);
    assert.match(check, /tm\.role <> 'APARTMENT_ADMIN' OR EXISTS \( SELECT 1 FROM apartment_memberships x WHERE x\.apartment_id = a\.id AND x\.role = 'APARTMENT_ADMIN' AND x\.is_active = TRUE AND x\.user_code <> sp\.user_code/);
  });

  it('kapı / MQTT / üyelik varlığı DEĞİŞMEZ: SQL kapı tablolarına, site üyeliklerine yazmaz; apartment_memberships\'e yalnız rol + updated_at yazılır', () => {
    const all = TENANT_ADMIN_STATEMENTS.join('\n');
    assert.doesNotMatch(all, /door_access_overrides|site_memberships|site_doors|devices|qr_access|DELETE FROM|INSERT INTO apartment_memberships/);
    const membershipWrites = TENANT_ADMIN_STATEMENTS.filter((sql) => /UPDATE apartment_memberships/.test(sql));
    assert.equal(membershipWrites.length, 1);
    assert.doesNotMatch(norm(membershipWrites[0]), /is_active = (TRUE|FALSE),|SET is_active/, 'is_active bayrağı yazılmaz');
    const writeTargets = TENANT_ADMIN_STATEMENTS.flatMap((sql) => [...sql.matchAll(/(?:INSERT INTO|UPDATE) ([a-z_]+)/g)].map((m) => m[1]));
    assert.deepEqual([...new Set(writeTargets)].sort(), ['apartment_admin_delegations', 'apartment_memberships', 'apartment_notices', 'apartment_residency_log', 'apartments', 'audit_log']);
  });

  it('eski sakin göstergesi applyApartmentPrimaryAdmin ile AYNI kural: başka kişiye geçiyorsa e-posta ve PIN verildi işareti temizlenir, PIN kopyası NULL', () => {
    const indicator = norm(TENANT_ADMIN_STATEMENTS[6]);
    assert.match(indicator, /resident_email = CASE WHEN a\.resident_user_code IS DISTINCT FROM c\.tenant_user_code THEN NULL ELSE a\.resident_email END/);
    assert.match(indicator, /resident_pin_issued = CASE WHEN a\.resident_user_code IS DISTINCT FROM c\.tenant_user_code THEN FALSE ELSE a\.resident_pin_issued END/);
    assert.match(indicator, /resident_pin_code = NULL, resident_user_code = c\.tenant_user_code/);
    const membership = read('src/services/membership_service.js');
    assert.match(membership, /resident_email = CASE WHEN resident_user_code IS DISTINCT FROM \$1 THEN NULL ELSE resident_email END/);
  });

  it('denetim ayrıntısı kişisel veri taşımaz (yalnız kimlikler ve yol etiketi); adli kayıt iletişim sütunu yazmaz; bildirim metni ad içermez', () => {
    // aday alt sorgusu (FROM ( ... ) c) ad sutununu okur ama YAZILAN kisim (SELECT listesi) kisisel veri tasimaz
    const head = (sql) => norm(sql).split(" FROM (")[0];
    const audit = head(TENANT_ADMIN_STATEMENTS[1]);
    assert.match(audit, /jsonb_build_object\('via', c\.via, 'tenant_person_id', c\.tenant_person_id, 'from_user_code', c\.prev_admin_user_code, 'to_user_code', c\.tenant_user_code\)/);
    assert.doesNotMatch(audit, /full_name|tenant_name|phone|email/);
    const log = head(TENANT_ADMIN_STATEMENTS[2]);
    assert.doesNotMatch(log, /phone|email|tckn/i);
    assert.match(log, /'admin_changed', 'handover'/);
    const notice = head(TENANT_ADMIN_STATEMENTS[5]);
    assert.doesNotMatch(notice, /tenant_name|full_name/);
    assert.match(norm(TENANT_ADMIN_STATEMENTS[5]), /t\.user_code IS DISTINCT FROM c\.actor_user_code/);
  });

  it('yeni devir: kiracı için tenant_delegated/active; önce açık devir "replaced" ile kapanır (açık devir tekilliği)', () => {
    const end = norm(TENANT_ADMIN_STATEMENTS[3]);
    const start = norm(TENANT_ADMIN_STATEMENTS[4]);
    assert.match(end, /SET state = 'ended', ended_at = NOW\(\), end_reason = 'replaced'/);
    assert.match(start, /'tenant_delegated', 'active'/);
    assert.ok(TENANT_ADMIN_STATEMENTS.indexOf(TENANT_ADMIN_STATEMENTS[3]) < TENANT_ADMIN_STATEMENTS.indexOf(TENANT_ADMIN_STATEMENTS[4]));
  });
});

/** Betikli sahte istemci: ifadeleri kaydeder; verilen eşleşmelere göre satır döner. */
function fakeClient(handlers = []) {
  const log = [];
  return {
    log,
    async query(text, params = []) {
      const sql = norm(text);
      log.push({ sql, params });
      for (const [pattern, result] of handlers) {
        if (pattern.test(sql)) return typeof result === 'function' ? result(sql, params) : result;
      }
      return { rows: [], rowCount: 0 };
    },
  };
}

describe('ensureTenantIsAdmin (çalışma anı sarmalayıcısı)', () => {
  it('aday yoksa YALNIZ aday kontrolü çalışır (8 parametre); 0 değişiklik', async () => {
    const client = fakeClient();
    const result = await ensureTenantIsAdmin(client, { apartmentIds: [9], via: 'access_granted' });
    assert.deepEqual(result, { changed: 0 });
    assert.equal(client.log.length, 1);
    assert.equal(client.log[0].sql, norm(TENANT_ADMIN_CHECK_SQL));
    assert.deepEqual(client.log[0].params, [[9], null, false, 'access_granted', null, 'Sistem', 'system', 'system']);
  });

  it('aday varsa kontrol + 8 ifade SIRAYLA, aynı parametrelerle; değişen daire sayısı denetim ifadesinin satır sayısıdır', async () => {
    const client = fakeClient([
      [/^SELECT 1 FROM \(/, { rows: [{ '?column?': 1 }], rowCount: 1 }],
      [/^INSERT INTO audit_log/, { rows: [], rowCount: 3 }],
    ]);
    const result = await ensureTenantIsAdmin(client, { apartmentIds: [4, 5, 5, 6, 'x', -1, 0], userCode: 77, overrideManager: true, via: 'bulk_import' });
    assert.deepEqual(result, { changed: 3 });
    assert.equal(client.log.length, 1 + TENANT_ADMIN_STATEMENTS.length);
    assert.deepEqual(client.log.slice(1).map((entry) => entry.sql), TENANT_ADMIN_STATEMENTS.map(norm));
    for (const entry of client.log) {
      assert.deepEqual(entry.params, [[4, 5, 6], 77, true, 'bulk_import', null, 'Sistem', 'system', 'system'], 'çift / geçersiz kimlikler elenir; hepsi aynı parametre');
    }
  });

  it('işlemi yapan verilirse denetimde kendi kodu / adı / rolü, adli kayıtta bağlamdan bilinen rol yazılır (sistem değil)', async () => {
    const client = fakeClient([[/^SELECT 1 FROM \(/, { rows: [{ x: 1 }], rowCount: 1 }]]);
    const actor = { id: 20001, user_code: 20001, role: 'site_manager', full_name: 'Ayşe Yönetici' };
    await ensureTenantIsAdmin(client, { apartmentIds: 9, actor, actorRole: 'site_manager', via: 'person_created' });
    assert.deepEqual(client.log[1].params, [[9], null, false, 'person_created', 20001, 'Ayşe Yönetici', 'site_manager', 'site_manager']);
    const sup = fakeClient([[/^SELECT 1 FROM \(/, { rows: [{ x: 1 }], rowCount: 1 }]]);
    await ensureTenantIsAdmin(sup, { apartmentIds: 9, actor: { id: 1, user_code: 1, role: 'super_user', full_name: 'Süper' }, actorRole: 'tenant' });
    assert.equal(sup.log[1].params[7], 'super_user', 'süper kullanıcı her bağlamda süper kullanıcı olarak kaydedilir');
  });

  it('kimlik yok / hepsi geçersiz: hiçbir sorgu çalışmaz', async () => {
    const client = fakeClient();
    assert.deepEqual(await ensureTenantIsAdmin(client, { apartmentIds: [] }), { changed: 0 });
    assert.deepEqual(await ensureTenantIsAdmin(client, { apartmentIds: [null, 'a'] }), { changed: 0 });
    assert.deepEqual(await ensureTenantIsAdmin(client, {}), { changed: 0 });
    assert.equal(client.log.length, 0);
  });

  it('ensureTenantAdminRule (açılış): aday yoksa TEK okuma; varsa parametresiz çok ifadeli metin tek sorguda', async () => {
    const none = fakeClient();
    assert.equal(await ensureTenantAdminRule(none), 0);
    assert.deepEqual(none.log.map((entry) => entry.sql), [norm(TENANT_ADMIN_BACKFILL_CHECK_SQL)]);
    assert.deepEqual(none.log[0].params, []);

    const results = TENANT_ADMIN_STATEMENTS.map((_, index) => ({ rows: [], rowCount: index === TENANT_ADMIN_COUNT_INDEX ? 5 : 0 }));
    const some = fakeClient([
      [/^SELECT 1 FROM \(/, { rows: [{ x: 1 }], rowCount: 1 }],
      [/^SELECT a\.id FROM apartments a WHERE a\.id IN/, results],
    ]);
    assert.equal(await ensureTenantAdminRule(some), 5);
    assert.equal(some.log.length, 2);
    assert.equal(some.log[1].sql, norm(TENANT_ADMIN_BACKFILL_SQL));
  });
});

describe('yönetim devri önceliği: güncel kiracı > güncel malik > en eski aktif üye (apartment_admin_successor.js)', () => {
  const OTHER_ADMIN = /AND is_active = TRUE AND role = 'APARTMENT_ADMIN'/;

  it('sorgu: eski "en eski aktif üye" sorgusunun öneki aynen, yalnız ORDER BY\'a kiracı / malik sırası eklendi; kalan üye = aktif üyelik, ayrılan kişi hariç', () => {
    const sql = norm(ADMIN_SUCCESSOR_SQL);
    assert.match(sql, /^SELECT user_code FROM apartment_memberships WHERE apartment_id = \$1 AND user_code <> \$2 AND is_active = TRUE ORDER BY CASE WHEN EXISTS/);
    assert.match(sql, /THEN 0 WHEN EXISTS .* THEN 1 ELSE 2 END, created_at ASC, id ASC LIMIT 1$/);
    assert.deepEqual([...sql.matchAll(/r\.relation = '([a-z_]+)'/g)].map((m) => m[1]), ['tenant', 'owner'], 'sıra: önce kiracı sonra malik');
  });

  it('kiracı / malik adayı: aktif kişi kaydı + silinmemiş aktif hesap + GÜNCEL ilişki + askıda değil (askıdaki kişi ust sıraya yükselmez)', () => {
    const sql = norm(ADMIN_SUCCESSOR_SQL);
    assert.equal((sql.match(/sp\.is_active = TRUE/g) ?? []).length, 2);
    assert.equal((sql.match(/u\.deleted_at IS NULL AND u\.is_active = TRUE/g) ?? []).length, 2);
    assert.equal((sql.match(/r\.is_current = TRUE/g) ?? []).length, 2);
    assert.equal((sql.match(/sp\.user_code = apartment_memberships\.user_code/g) ?? []).length, 2);
    assert.equal((sql.match(/apartment_access_suspensions s WHERE s\.apartment_id = apartment_memberships\.apartment_id AND s\.user_code = apartment_memberships\.user_code AND s\.lifted_at IS NULL/g) ?? []).length, 2);
    assert.doesNotMatch(sql, /UPDATE|INSERT|DELETE/);
  });

  it('pickAdminSuccessor: tek sorgu, [daire, ayrılan]; satır yoksa null; kullanıcı kodu sayı', async () => {
    const some = fakeClient([[/^SELECT user_code FROM apartment_memberships/, { rows: [{ user_code: '30002' }], rowCount: 1 }]]);
    assert.equal(await pickAdminSuccessor(some, 9, 30001), 30002);
    assert.equal(some.log.length, 1);
    assert.deepEqual(some.log[0].params, [9, 30001]);
    assert.equal(some.log[0].sql, norm(ADMIN_SUCCESSOR_SQL));
    assert.equal(await pickAdminSuccessor(fakeClient(), 9, 30001), null);
  });

  it('handOverApartmentResident: başka aktif admin yoksa seçimi pickAdminSuccessor yapar (rol + gösterge + PIN işareti temizliği mevcut kuralla); seçim yoksa gösterge temizlenir', async () => {
    const client = fakeClient([[/^SELECT user_code FROM apartment_memberships WHERE apartment_id = \$1 AND user_code <> \$2 AND is_active = TRUE ORDER BY CASE/, { rows: [{ user_code: 30002 }], rowCount: 1 }]]);
    await handOverApartmentResident(client, 9, 30001);
    const order = client.log.map((entry) => entry.sql.slice(0, 40));
    assert.ok(order[0].startsWith('SELECT user_code FROM apartment_membe'), 'önce başka aktif admin aranır');
    assert.match(client.log[0].sql, OTHER_ADMIN);
    const picked = client.log.find((entry) => /ORDER BY CASE/.test(entry.sql));
    assert.deepEqual(picked.params, [9, 30001]);
    const promote = client.log.find((entry) => /^UPDATE apartment_memberships SET role = 'APARTMENT_ADMIN', updated_at = NOW\(\) WHERE apartment_id = \$1 AND user_code = \$2$/.test(entry.sql));
    assert.deepEqual(promote.params.map(Number), [9, 30002]);
    const indicator = client.log.find((entry) => /^UPDATE apartments SET resident_user_code = \$1, resident_pin_issued = FALSE/.test(entry.sql));
    assert.deepEqual(indicator.params.map(Number), [30002, 9]);

    const none = fakeClient();
    await handOverApartmentResident(none, 9, 30001);
    assert.ok(none.log.some((entry) => /^UPDATE apartments SET resident_user_code = NULL/.test(entry.sql)), 'kimse kalmadı: gösterge temizlenir');
    assert.equal(none.log.some((entry) => /^UPDATE apartment_memberships SET role/.test(entry.sql)), false);
  });

  it('başka aktif admin VARSA seçim yapılmaz (gösterge ona taşınır; kiracı önceliği yalnız admin kalmadığında geçerli)', async () => {
    const client = fakeClient([[OTHER_ADMIN, { rows: [{ user_code: 30009 }], rowCount: 1 }]]);
    await handOverApartmentResident(client, 9, 30001);
    assert.equal(client.log.some((entry) => /ORDER BY CASE/.test(entry.sql)), false);
  });

  it('tek yardımcı: membership_service seçimi bu modülden yapar (eski satır içi "en eski aktif üye" sorgusu kalmadı); closeResidency ayrı bir geri verme yardımcısı çağırmaz', () => {
    const membership = read('src/services/membership_service.js');
    assert.match(membership, /import \{ pickAdminSuccessor \} from '\.\.\/modules\/apartment_admin_successor\.js';/);
    assert.match(membership, /const successorCode = await pickAdminSuccessor\(client, apartmentId, removedUserCode\);/);
    assert.doesNotMatch(membership, /remainingRes/);
    assert.doesNotMatch(read('src/modules/people_service.js'), /handBackAdminToOwner/);
    assert.doesNotMatch(read('src/modules/apartment_tenant_admin.js'), /handBackAdminToOwner/);
    assert.doesNotMatch(read('src/modules/apartment_admin_successor.js'), /^import /m, 'yaprak modül: içe aktarma yok (membership_service döngüsü olmasın)');
  });
});

describe('kablolama: kiracı ilişkisi oluşan TÜM yollar kiracıyı admin yapar', () => {
  const people = read('src/modules/people_service.js');
  const mgmt = read('src/modules/apartment_mgmt_service.js');

  it('grantApartmentAccess kancası: erişim verilen kişi güncel kiracıysa (hesap sonradan bağlanan dahil) admin olur; site yöneticisi devri korunur', () => {
    assert.match(people, /await ensureTenantIsAdmin\(client, \{ apartmentIds: \[apartmentId\], userCode, via: 'access_granted' \}\);/);
  });

  it('createPerson / addResidency / updateResidency: kiracı ilişkisi eklenince / kiracıya çevrilince admin (yeni kiracı site yöneticisi devrini ezer)', () => {
    assert.match(people, /if \(input\.relation === 'tenant'\) \{[\s\S]*?ensureTenantIsAdmin\(client, \{ apartmentIds: \[Number\(apartment\.id\)\], overrideManager: true, via: 'person_created', actor \}\)/);
    assert.match(people, /if \(relation === 'tenant'\) \{[\s\S]*?ensureTenantIsAdmin\(client, \{ apartmentIds: \[apartmentId\], overrideManager: true, via: 'residency_added', actor \}\)/);
    assert.match(people, /if \(relation === 'tenant' && row\.is_current === true\) \{[\s\S]*?via: 'residency_changed'/);
    // kilit sırası: daire, ilişki satırından ÖNCE (updateResidency kiracıya çevirirken)
    assert.match(people, /if \(relation === 'tenant'\) \{\n      \/\/ Kiracıya çevirme daire adminini değiştirebilir[\s\S]*?FOR UPDATE`, \[Number\(pre\.rows\[0\]\.apartment_id\)\]\);\n      \}\n    \}\n    const row = await loadResidencyForSite/);
  });

  it('provisionResidentAndLinkPerson (hesap hesapsız kiracıya bağlanır), toplu yükleme (commit sonu)', () => {
    assert.match(people, /via: 'account_linked'/);
    const service = read('src/modules/bulk_import_service.js');
    assert.match(service, /written\.tenantApartmentIds/);
    assert.match(service, /ensureTenantIsAdmin\(client, \{ apartmentIds: written\.tenantApartmentIds, overrideManager: true, via: 'bulk_import', actor \}\)/);
    const writer = read('src/modules/bulk_import_writer.js');
    assert.match(writer, /export const RELATION_RANK = Object\.freeze\(\{ tenant: 0, owner: 1, resident: 2, family_member: 3 \}\);/);
    assert.match(writer, /tenantApartmentIds/);
  });

  it('malikin "Kiracı ekle"si: delegate_management gelse de (false dahil) yok sayılır; hesapsız kiracıda bekleyen devir HER ZAMAN yazılır; davet kabulünde kanca + açık ezme', () => {
    assert.doesNotMatch(mgmt, /body\?\.delegate_management !== false/);
    assert.match(mgmt, /const delegate = true;/);
    assert.doesNotMatch(mgmt, /if \(delegate\) \{\n      await recordDelegation/);
    assert.match(mgmt, /state: 'pending_account',/);
    assert.doesNotMatch(mgmt, /request\.payload\?\.delegate_management === true/);
    assert.match(mgmt, /ensureTenantIsAdmin\(client, \{ apartmentIds: \[state\.apartment\.id\], userCode: uc, overrideManager: true, via: 'tenant_invite_accepted'/);
  });

  it('yaşayan sistem: günlük bakım (açılışta ve 24 saatte bir) kuralı da çalıştırır; hata temizliği durdurmaz', () => {
    const maintenance = read('src/services/maintenance_service.js');
    assert.match(maintenance, /import \{ ensureTenantAdminRule \} from '\.\.\/modules\/apartment_tenant_admin_sql\.js';/);
    assert.match(maintenance, /try \{\n\s+await ensureTenantAdminRule\(db\);\n\s+\} catch \(error\) \{/);
  });

  it('yanıt alanları: davetlerde delegate_management kiracı davetinde true (eski istemci metinleri); hesapsız kiracıda delegation_pending türetilir', () => {
    assert.match(mgmt, /delegate_management: row\.kind === 'tenant_invite'/);
    assert.match(mgmt, /delegate_management: r\.kind === 'tenant_invite'/);
    assert.match(mgmt, /delegation_pending: delegation\?\.state === 'pending_account' \|\| \(Boolean\(roles\.tenant\) && roles\.tenant\.user_code === null && roles\.adminKind !== 'tenant'\)/);
  });
});

describe('kurallar: rolesOfUser', () => {
  const member = (user_code, role) => ({ user_code, role, is_active: true, created_at: '2026-01-01' });
  const res = (id, person_id, user_code, relation) => ({ id, person_id, user_code, relation, name: `K${person_id}` });

  it('can.delegate_management her durumda false (devret seçeneği kalktı); kiracı admin: yönetim kiracıda, malik yalnız vekalet / bağ kesme', () => {
    for (const adminCode of [1, 2]) {
      const roles = rules.resolveApartmentRoles({
        members: [member(1, adminCode === 1 ? 'APARTMENT_ADMIN' : 'FAMILY_MEMBER'), member(2, adminCode === 2 ? 'APARTMENT_ADMIN' : 'FAMILY_MEMBER')],
        residencies: [res(10, 100, 1, 'owner'), res(11, 101, 2, 'tenant')],
      });
      assert.equal(rules.rolesOfUser(roles, 1).can.delegate_management, false);
      assert.equal(rules.rolesOfUser(roles, 2).can.delegate_management, false);
    }
    const roles = rules.resolveApartmentRoles({
      members: [member(1, 'FAMILY_MEMBER'), member(2, 'APARTMENT_ADMIN')],
      residencies: [res(10, 100, 1, 'owner'), res(11, 101, 2, 'tenant')],
    });
    const owner = rules.rolesOfUser(roles, 1);
    const tenant = rules.rolesOfUser(roles, 2);
    assert.deepEqual([owner.is_admin, owner.is_owner, tenant.is_admin, tenant.is_tenant], [false, true, true, true]);
    assert.equal(owner.can.manage_family, false);
    assert.equal(tenant.can.manage_family, true);
    assert.equal(owner.can.manage_proxy, true, 'malik vekalet verebilir');
    assert.equal(rules.adminSideOf(roles), 'tenant');
  });

  it('hesap yokken varsayılan admin kiracıdır (kiracı > malik > ilk sakin)', () => {
    const roles = rules.resolveApartmentRoles({ members: [], residencies: [res(10, 100, null, 'owner'), res(11, 101, null, 'tenant')] });
    assert.equal(roles.adminPersonId, 101);
    assert.equal(roles.adminSource, 'default_resident');
  });
});
