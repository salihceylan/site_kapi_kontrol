// Site yöneticisi bağının kaynağı (site_manager_sites.link_source) ve anlık kurulum kapısı (DB'siz, sıkı sahte istemci).
// Karar: anlık site kurulumu (setup-site) yalnız onaylı bir sitede 'invited' OLMAYAN en az bir bağı (sahip bağı) olan yöneticiye ve süper
// kullanıcıya açıktır; bireysel / daire sahibi ve sahip bağı olmayan yönetici (davetle yönetici olan, sitesi olmayan) site için BAŞVURUR.
// Kapı girdi doğrulamasından ÖNCE çalışır: kapalı kullanıcıya her gövdede 409 APPLICATION_REQUIRED döner (400 değil).
import { describe, it, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { pool } from '../src/db.js';
import { setupSiteWithClaimedDevice } from '../src/services/membership_service.js';
import { inviteSiteManager } from '../src/services/site_service.js';
import { createSiteWithStructure, userHasOwnerLink } from '../src/services/site_setup_core.js';

const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
const ok = (rows = []) => ({ rows, rowCount: rows.length });
const readSrc = (relative) => readFileSync(path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'src', relative), 'utf8').replace(/\r\n/g, '\n');

/**
 * poolRole: ön kapının (pool.query) gördüğü rol; txRole: transaction içinde okunan rol (varsayılan aynı); ownerLink: sahip bağı var mı.
 */
function install({ poolRole = 'site_manager', txRole = poolRole, ownerLink = false } = {}) {
  const poolLog = [];
  const clientLog = [];
  const answer = (log, roleOf) => async (text, params = []) => {
    const sql = norm(text);
    log.push({ sql, params });
    if (/^(BEGIN|COMMIT|ROLLBACK)$/.test(sql) || /^SELECT pg_advisory_xact_lock/.test(sql)) return ok();
    if (/^SELECT role FROM users WHERE user_code = \$1 LIMIT 1$/.test(sql)) return ok(roleOf() ? [{ role: roleOf() }] : []);
    if (/^SELECT 1 FROM site_manager_sites m INNER JOIN sites s/.test(sql)) return ok(ownerLink ? [{ x: 1 }] : []);
    if (/^SELECT id, user_code, role, full_name, email FROM users/.test(sql)) {
      return txRole ? ok([{ id: 7, user_code: 48213, role: txRole, full_name: 'A', email: 'a@example.com' }]) : ok();
    }
    if (/^SELECT \* FROM devices/.test(sql)) return ok();
    // rol güncellemesi `deleted_at IS NULL` ister: satır dönmezse (silinmiş hesap) kurulum geri alınır; burada hesap var -> 1 satır
    if (/^UPDATE users SET role = 'site_manager' WHERE id = \$1 AND deleted_at IS NULL$/.test(sql)) return { rows: [], rowCount: 1 };
    if (/^INSERT INTO sites/.test(sql)) return ok([{ id: 900, name: params[0], management_type: params[8] }]);
    if (/^INSERT INTO site_blocks/.test(sql)) return ok([{ id: 31, site_code: 900, block_name: 'A Blok', sort_order: 1 }]);
    if (/^INSERT INTO site_doors/.test(sql)) return ok([{ id: 41, site_code: 900, door_name: 'Kapı 1', door_index: 1, is_active: true }]);
    return ok();
  };
  pool.query = answer(poolLog, () => poolRole);
  let connects = 0;
  const client = { released: false, query: answer(clientLog, () => txRole), release() { client.released = true; } };
  pool.connect = async () => {
    connects += 1;
    return client;
  };
  return { poolLog, clientLog, connects: () => connects, client };
}

afterEach(() => {
  delete pool.query;
  delete pool.connect;
});

const base = { userCode: 48213, name: 'Yeni Site', city: 'Ankara' };
const has = (log, regex) => log.some((entry) => regex.test(entry.sql));
const requiredError = (error) =>
  error.statusCode === 409 && error.code === 'APPLICATION_REQUIRED' && error.message === 'Site kurmak için başvuru yapmalısınız.' && error.expose === true;

const INVALID_BODIES = [
  ['boş site adı', { name: '   ' }],
  ['bilinmeyen yönetim türü', { managementType: 'otel' }],
  ['101 blok', { blocks: Array.from({ length: 101 }, (_, i) => ({ name: `B${i}`, apartmentCount: 1 })) }],
  ['5001 daire', { blocks: [{ name: 'A', apartmentCount: 5001 }] }],
  ['101 kapı', { doors: undefined, doorCount: 101 }],
];

describe('setup-site kapısı: rol ve sahip bağı, doğrulamalardan ÖNCE', () => {
  it('bireysel / daire sahibi: GEÇERSİZ gövdede de 409 APPLICATION_REQUIRED (400 değil); bağlantı bile alınmaz', async () => {
    for (const role of ['individual', 'apartment_owner']) {
      for (const [label, extra] of [['geçerli gövde', {}], ...INVALID_BODIES]) {
        const db = install({ poolRole: role });
        await assert.rejects(() => setupSiteWithClaimedDevice({ ...base, ...extra }), requiredError, `${role} ${label}`);
        assert.equal(db.connects(), 0, `${role} ${label}: transaction açılmaz`);
        assert.equal(has(db.poolLog, /site_manager_sites/), false, 'rol yetmeyince bağ sorgusu yok');
      }
    }
  });

  it('sahip bağı OLMAYAN site yöneticisi (davetle yönetici olan, sitesi olmayan): her gövdede 409 APPLICATION_REQUIRED', async () => {
    for (const [label, extra] of [['geçerli gövde', {}], ...INVALID_BODIES]) {
      const db = install({ poolRole: 'site_manager', ownerLink: false });
      await assert.rejects(() => setupSiteWithClaimedDevice({ ...base, ...extra }), requiredError, label);
      assert.equal(db.connects(), 0, label);
      assert.equal(has(db.poolLog, /^INSERT INTO sites/), false);
    }
  });

  it('sahip bağı OLAN site yöneticisi: geçerli gövde 201, kurulum AYNEN; geçersiz gövde yine 400 (eski doğrulama sırası)', async () => {
    let db = install({ poolRole: 'site_manager', ownerLink: true });
    const result = await setupSiteWithClaimedDevice({ ...base });
    assert.equal(result.ok, true);
    assert.ok(has(db.clientLog, /^INSERT INTO sites/));
    assert.ok(has(db.clientLog, /^COMMIT/));
    for (const [label, extra] of INVALID_BODIES) {
      db = install({ poolRole: 'site_manager', ownerLink: true });
      await assert.rejects(
        () => setupSiteWithClaimedDevice({ ...base, ...extra }),
        (error) => error.statusCode === 400 && error.code !== 'APPLICATION_REQUIRED',
        label,
      );
      assert.equal(db.connects(), 0, `${label}: doğrulama hatası bağlantı almadan`);
    }
  });

  it('süper kullanıcı: bağ sorgusu YOK, kurulum AYNEN', async () => {
    const db = install({ poolRole: 'super_user', ownerLink: false });
    const result = await setupSiteWithClaimedDevice({ ...base });
    assert.equal(result.ok, true);
    assert.equal(has(db.poolLog, /site_manager_sites/), false);
    assert.equal(has(db.clientLog, /site_manager_sites m INNER JOIN/), false);
  });

  it('transaction içinde TAZE rol: ön kapıdan geçen ama arada bireysel olan / bağını yitiren kullanıcı yine 409; site kurulmaz, ROLLBACK', async () => {
    let db = install({ poolRole: 'site_manager', txRole: 'individual', ownerLink: true });
    await assert.rejects(() => setupSiteWithClaimedDevice({ ...base }), requiredError);
    assert.equal(has(db.clientLog, /^INSERT INTO sites/), false);
    assert.ok(has(db.clientLog, /^ROLLBACK/));
    assert.equal(has(db.clientLog, /^COMMIT/), false);
    assert.equal(db.client.released, true);

    // ön kapı bağı görür, transaction'da yöneticilik bağı kalmamıştır (ör. bağlı olduğu site silindi)
    let linkChecks = 0;
    db = install({ poolRole: 'site_manager', ownerLink: true });
    const original = pool.connect;
    pool.connect = async () => {
      const connected = await original();
      const query = connected.query;
      connected.query = async (text, params) => {
        if (/site_manager_sites m INNER JOIN/.test(norm(text))) {
          linkChecks += 1;
          return ok();
        }
        return query(text, params);
      };
      return connected;
    };
    await assert.rejects(() => setupSiteWithClaimedDevice({ ...base }), requiredError);
    assert.equal(linkChecks, 1, 'bağ transaction içinde yeniden denetlendi');
  });

  it('hesap yoksa ön kapı geçer ve eski davranış (404) korunur; oturum yoksa 401 (veritabanına dokunmaz)', async () => {
    const db = install({ poolRole: null });
    db.poolLog.length = 0;
    await assert.rejects(() => setupSiteWithClaimedDevice({ ...base }), (error) => error.statusCode === 404);
    const none = install();
    await assert.rejects(() => setupSiteWithClaimedDevice({ ...base, userCode: 'abc' }), (error) => error.statusCode === 401);
    assert.equal(none.poolLog.length, 0);
  });
});

describe('userHasOwnerLink', () => {
  it('SQL: yalnız onaylı sitedeki, link_source değeri "invited" OLMAYAN (NULL = eski kayıt dahil) bağ; parametreli', async () => {
    const calls = [];
    const db = { query: async (text, params) => { calls.push({ sql: norm(text), params }); return ok([{ x: 1 }]); } };
    assert.equal(await userHasOwnerLink(db, 48213), true);
    assert.deepEqual(calls[0].params, [48213]);
    assert.match(calls[0].sql, /m\.link_source IS DISTINCT FROM 'invited'/);
    assert.match(calls[0].sql, /s\.approval_status = 'approved'/);
    assert.match(calls[0].sql, /m\.manager_user_code = \$1/);
    assert.equal(await userHasOwnerLink({ query: async () => ok() }, 1), false);
  });
});

describe('bağ kaynağı yazımı', () => {
  it("ortak çekirdek (başvuru onayı + anlık kurulum) bağı 'owner' yazar ve her yeni siteye abonelik satırı ekler", async () => {
    const log = [];
    const client = {
      query: async (text, params = []) => {
        const sql = norm(text);
        log.push({ sql, params });
        if (/^INSERT INTO sites/.test(sql)) return ok([{ id: 900, name: 'S', management_type: 'apartment_site' }]);
        if (/^UPDATE users SET role/.test(sql)) return { rows: [], rowCount: 1 };
        if (/^INSERT INTO site_blocks/.test(sql)) return ok([{ id: 31, site_code: 900, block_name: 'A', sort_order: 1 }]);
        if (/^INSERT INTO site_doors/.test(sql)) return ok([{ id: 41, site_code: 900, door_name: 'K', door_index: 1, is_active: true }]);
        return ok();
      },
    };
    const input = { siteName: 'S', address: null, city: null, district: null, blocks: [{ name: 'A', apartmentCount: 2, sortOrder: 1 }], doors: [{ name: 'K', doorIndex: 1 }], totalBlockCount: 1, totalApartmentCount: 2, totalDoorCount: 1, blockApartmentCounts: [2] };
    await createSiteWithStructure(client, { user: { id: 7, user_code: 48213, role: 'site_manager' }, input, managementType: 'apartment_site' });
    const link = log.find((e) => /^INSERT INTO site_manager_sites/.test(e.sql));
    assert.match(link.sql, /VALUES \(\$1, \$2, 'owner'\)/);
    const subscription = log.find((e) => /^INSERT INTO site_subscriptions/.test(e.sql));
    assert.deepEqual(subscription.params, [900, 'manual_approval', 'admin', null], 'anlık yol: source admin, application_id yok');
    assert.match(subscription.sql, /VALUES \(\$1, \$2, 'active', \$3, \$4\)/);

    log.length = 0;
    await createSiteWithStructure(client, { user: { id: 7, user_code: 48213, role: 'individual' }, input, managementType: 'apartment_site', subscription: { source: 'manual_approval', applicationId: 41 } });
    assert.deepEqual(log.find((e) => /^INSERT INTO site_subscriptions/.test(e.sql)).params, [900, 'manual_approval', 'manual_approval', 41]);
    // abonelik satırı çekirdeğin SON ifadesidir (kurulum yarıda kalırsa satır da kalmaz: tek transaction)
    // (Y2: ardından deneme süresi SAVEPOINT / UPDATE ifadeleri gelebilir; başka INSERT gelmez)
    const subscriptionAt = log.findLastIndex((e) => /^INSERT INTO site_subscriptions/.test(e.sql));
    assert.ok(subscriptionAt >= 0 && log.slice(subscriptionAt + 1).every((e) => !/^INSERT /.test(e.sql)));
  });

  it("davet kabulü (e-posta doğrulama) ve ortak yönetici ataması yeni bağları 'invited' yazar; başka yolda 'invited' YAZILMAZ", () => {
    const membership = readSrc('services/membership_service.js');
    const acceptance = /INSERT INTO site_manager_sites \(site_code, manager_user_code, link_source\) VALUES \(\$1, \$2, 'invited'\) ON CONFLICT DO NOTHING/;
    assert.match(membership, acceptance);
    const inviteSource = inviteSiteManager.toString();
    assert.match(inviteSource, /INSERT INTO site_manager_sites \(site_code, manager_user_code, link_source\)\s+VALUES \(\$1, \$2, 'invited'\)/);
    for (const name of ['modules/site_application_service.js', 'services/site_setup_core.js', 'routes/admin_routes.js', 'routes/manager_routes.js']) {
      assert.equal(/'invited'\)/.test(readSrc(name).replace(/IS DISTINCT FROM 'invited'/g, '')), false, name);
    }
  });

  it('site_service.createSiteWithStructure (admin / bekleyen site) de abonelik satırı yazar; mevcut sitelere satır eklenmez (backfill yok)', () => {
    const siteService = readSrc('services/site_service.js');
    assert.match(siteService, /INSERT INTO site_subscriptions \(site_code, plan_code, status, source\)\s+VALUES \(\$1, 'manual_approval', 'active', 'admin'\)/);
    const migration = readFileSync(path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'migrations', '033_site_applications.sql'), 'utf8');
    assert.equal(/INSERT INTO site_subscriptions/i.test(migration), false);
  });
});
