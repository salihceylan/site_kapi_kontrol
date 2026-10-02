// SX2 duzeltmeleri (DB'siz): daire sakini sifre kilidi, site kurulumu cihaz sahipligi, pasife alma (toggle),
// katilim talebi yetki sirasi, sakin agaci hesap durumu ve daire sakini olusturma/duzenleme kurallari.
import { describe, it, before, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import bcrypt from 'bcryptjs';
import express from 'express';
import { pool } from '../src/db.js';
import { passwordChangeFailureTracker, passwordChangeThrottleKey } from '../src/middlewares/login_throttle.js';
import { membershipRouter, setupSiteLimiter } from '../src/routes/membership_routes.js';
import {
  approveJoinRequest,
  changeApartmentMemberPassword,
  getSiteResidentsTree,
  rejectJoinRequest,
  setupSiteWithClaimedDevice,
  toggleApartmentMemberStatus,
} from '../src/services/membership_service.js';
import { provisionApartmentResident } from '../src/services/apartment_service.js';
import { handleUserMutationError } from '../src/utils/validators.js';

process.env.JWT_SECRET = process.env.JWT_SECRET || 'test-secret-for-sx2-members-tests-0123456789abcdef';

const norm = (text) => String(text).replace(/\s+/g, ' ').trim();

// handlers: [[regex, (sql, params) => result], ...]; ilk eslesen kazanir; varsayilan { rowCount: 0, rows: [] }
function scripted(handlers) {
  const log = [];
  const run = async (text, params) => {
    const sql = norm(text);
    log.push({ sql, params });
    for (const [pattern, handler] of handlers) {
      if (pattern.test(sql)) {
        return typeof handler === 'function' ? handler(sql, params) : handler;
      }
    }
    return { rowCount: 0, rows: [] };
  };
  return { log, run };
}

function install({ poolHandlers = [], clientHandlers = [] } = {}) {
  const poolScript = scripted(poolHandlers);
  const clientScript = scripted(clientHandlers);
  pool.query = poolScript.run;
  const client = {
    released: false,
    query: clientScript.run,
    release() {
      client.released = true;
    },
  };
  pool.connect = async () => client;
  return { poolLog: poolScript.log, clientLog: clientScript.log, client };
}

const has = (log, regex) => log.some((entry) => regex.test(entry.sql));
const find = (log, regex) => log.find((entry) => regex.test(entry.sql));

afterEach(() => {
  delete pool.query;
  delete pool.connect;
  passwordChangeFailureTracker.reset();
  setupSiteLimiter.reset();
});

// ---------------------------------------------------------------------------
// change-password: PATCH /me ile ortak hesap bazli kilit + current_password trim
// ---------------------------------------------------------------------------
describe('changeApartmentMemberPassword: mevcut parola denemesi sinirli (429 CURRENT_PASSWORD_LOCKED)', () => {
  const PASSWORD = 'DogruParola';
  const HASH = bcrypt.hashSync(PASSWORD, 4);
  const self = { id: 20000, user_code: 20000, userCode: 20000 };
  let hashLookups;

  function setup() {
    hashLookups = 0;
    return install({
      poolHandlers: [
        [/^SELECT id, site_code, resident_user_code FROM apartments/, { rowCount: 1, rows: [{ id: 5, site_code: 101, resident_user_code: null }] }],
        [/^SELECT 1 FROM apartment_memberships WHERE apartment_id/, { rowCount: 1, rows: [{ '?column?': 1 }] }],
        [/^SELECT password_hash FROM users/, () => {
          hashLookups += 1;
          return { rowCount: 1, rows: [{ password_hash: HASH }] };
        }],
        [/^UPDATE users SET password_hash/, { rowCount: 1, rows: [{ id: 20000, email: 'a@example.com', role: 'individual' }] }],
      ],
    });
  }

  const attempt = (current, extra = {}) =>
    changeApartmentMemberPassword({
      apartmentId: 5,
      targetUserCode: 20000,
      newPassword: 'YeniParola1',
      currentPassword: current,
      authUser: self,
      ...extra,
    });

  it('yanlis parola 400 CURRENT_PASSWORD_INVALID; 5. hata 429 CURRENT_PASSWORD_LOCKED + retryAfterSeconds', async () => {
    setup();
    for (let i = 1; i <= 4; i += 1) {
      await assert.rejects(
        () => attempt(`yanlis-${i}`),
        (err) => err.statusCode === 400 && err.code === 'CURRENT_PASSWORD_INVALID' && /hatalı/.test(err.message),
        `${i}. deneme`,
      );
    }
    await assert.rejects(
      () => attempt('yanlis-5'),
      (err) => err.statusCode === 429 && err.code === 'CURRENT_PASSWORD_LOCKED' && err.retryAfterSeconds >= 800,
    );
  });

  it('kilitliyken DOGRU parola da reddedilir ve hash sorgusu/bcrypt calismaz', async () => {
    setup();
    for (let i = 0; i < 5; i += 1) {
      await attempt('yanlis').catch(() => {});
    }
    const lookupsBefore = hashLookups;
    await assert.rejects(
      () => attempt(PASSWORD),
      (err) => err.statusCode === 429 && err.code === 'CURRENT_PASSWORD_LOCKED',
    );
    assert.equal(hashLookups, lookupsBefore, 'kilitliyken hash okunmaz');
  });

  it('PATCH /me ile AYNI sayac: orada biriken hatalar burada kilitler (ve tersi)', async () => {
    setup();
    const key = passwordChangeThrottleKey(20000);
    assert.equal(key, 'u:20000');
    for (let i = 0; i < 5; i += 1) {
      passwordChangeFailureTracker.recordFailure(key);
    }
    await assert.rejects(
      () => attempt(PASSWORD),
      (err) => err.statusCode === 429 && err.code === 'CURRENT_PASSWORD_LOCKED',
    );

    passwordChangeFailureTracker.reset();
    for (let i = 0; i < 5; i += 1) {
      await attempt('yanlis').catch(() => {});
    }
    assert.equal(passwordChangeFailureTracker.check(key).locked, true, 'servis hatalari PATCH /me sayacina da yazilir');
  });

  it('basarili degisim sayaci sifirlar; mevcut parola trim edilir (girisle tutarli)', async () => {
    const { poolLog } = setup();
    for (let i = 0; i < 4; i += 1) {
      await attempt('yanlis').catch(() => {});
    }
    const ok = await attempt(`  ${PASSWORD} `);
    assert.equal(ok.ok, true);
    assert.ok(has(poolLog, /^UPDATE users SET password_hash/));
    assert.equal(passwordChangeFailureTracker.check('u:20000').locked, false);
    // sayac sifirlandi: 4 yeni hata daha kilitlemez
    for (let i = 0; i < 4; i += 1) {
      await assert.rejects(() => attempt('yanlis'), (err) => err.statusCode === 400);
    }
  });

  it('baska kullanicinin sifresi (403) ve eksik mevcut parola (400) sayaca YAZILMAZ', async () => {
    setup();
    await assert.rejects(() => attempt('x', { authUser: { id: 30000, user_code: 30000 } }), (err) => err.statusCode === 403);
    await assert.rejects(() => attempt('   '), (err) => err.statusCode === 400);
    assert.equal(passwordChangeFailureTracker.size(), 0);
  });

  it('HTTP: 429 yanitinda Retry-After basligi + retry_after_seconds + code', async () => {
    setup();
    const app = express();
    app.use(express.json());
    app.use(membershipRouter);
    for (const layer of membershipRouter.stack) {
      if (layer.route?.path?.endsWith('/change-password')) {
        layer.route.stack[0].handle = (req, _res, next) => {
          req.authUser = { id: 20000, user_code: 20000, userCode: 20000, role: 'individual' };
          next();
        };
      }
    }
    const server = await new Promise((resolve) => {
      const s = app.listen(0, '127.0.0.1', () => resolve(s));
    });
    try {
      const url = `http://127.0.0.1:${server.address().port}/membership/apartments/5/members/20000/change-password`;
      const post = (current) => fetch(url, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ new_password: 'YeniParola1', current_password: current }),
      });
      let last;
      for (let i = 1; i <= 5; i += 1) {
        last = await post(`yanlis-${i}`);
        if (i < 5) {
          assert.equal(last.status, 400);
          assert.equal((await last.json()).code, 'CURRENT_PASSWORD_INVALID');
        }
      }
      assert.equal(last.status, 429);
      assert.ok(Number(last.headers.get('retry-after')) >= 800);
      const body = await last.json();
      assert.equal(body.code, 'CURRENT_PASSWORD_LOCKED');
      assert.ok(body.retry_after_seconds >= 800);
    } finally {
      server.closeAllConnections?.();
      await new Promise((resolve) => server.close(resolve));
    }
  });
});

// ---------------------------------------------------------------------------
// setup-site: cihaz sahipligi dogrulanir; hiz siniri
// ---------------------------------------------------------------------------
describe('setupSiteWithClaimedDevice: cihaz sahipligi site kurulmadan ONCE dogrulanir', () => {
  const baseInput = { userCode: 48213, name: 'Yeni Site', city: 'Ankara', district: 'Cankaya', address: 'x' };

  function handlers({ role = 'individual', device = null } = {}) {
    return [
      [/^SELECT id, user_code, role, full_name, email FROM users/, { rowCount: 1, rows: [{ id: 7, user_code: 48213, role, full_name: 'A', email: 'a@example.com' }] }],
      [/^SELECT \* FROM devices/, () => (device ? { rowCount: 1, rows: [device] } : { rowCount: 0, rows: [] })],
      [/^INSERT INTO sites/, { rowCount: 1, rows: [{ id: 900, name: 'Yeni Site' }] }],
      [/^INSERT INTO site_blocks/, { rowCount: 1, rows: [{ id: 31, site_code: 900, block_name: 'A Blok', sort_order: 1 }] }],
      [/^INSERT INTO site_doors/, { rowCount: 1, rows: [{ id: 41, site_code: 900, door_name: 'Kapı 1', door_index: 1, is_active: true }] }],
    ];
  }

  const logHas = (clientLog, regex) => has(clientLog, regex);

  it('cihaz sahiplenmemis bireysel kullanici (cihaz belirtmeden): 400, site/blok/daire HIC olusturulmaz, ROLLBACK', async () => {
    const { clientLog, client } = install({ clientHandlers: handlers({ role: 'individual', device: null }) });
    await assert.rejects(
      () => setupSiteWithClaimedDevice({ ...baseInput }),
      (err) => err.statusCode === 400 && /cihaz sahiplenmelisiniz/.test(err.message),
    );
    assert.equal(logHas(clientLog, /^INSERT INTO sites/), false);
    assert.equal(logHas(clientLog, /^INSERT INTO apartments/), false);
    assert.ok(logHas(clientLog, /^ROLLBACK/));
    assert.equal(logHas(clientLog, /^COMMIT/), false);
    assert.equal(client.released, true);
  });

  it('belirtilen cihaz kullaniciya ait degil/bulunamadi: 404, site kurulmaz (artik sessizce cihazsiz kurulmaz)', async () => {
    for (const role of ['individual', 'site_manager']) {
      const { clientLog } = install({ clientHandlers: handlers({ role, device: null }) });
      await assert.rejects(
        () => setupSiteWithClaimedDevice({ ...baseInput, deviceUid: 'a0b1c2d3e4f5' }),
        (err) => err.statusCode === 404 && /cihaz hesabınıza ait değil/.test(err.message),
        role,
      );
      assert.equal(logHas(clientLog, /^INSERT INTO sites/), false);
      const lookup = find(clientLog, /^SELECT \* FROM devices WHERE UPPER\(device_uid\) = \$1/);
      assert.ok(lookup, 'cihaz sahiplik sorgusu calismali');
      assert.deepEqual(lookup.params, ['A0B1C2D3E4F5', 7, 48213], 'owner_user_id = users.id, assigned_user_code = user_code');
    }
  });

  it('sahip oldugu cihazla (belirtilen veya en son sahiplenilen) kurulum calisir ve cihaz 1. kapiya atanir', async () => {
    for (const deviceUid of ['A0B1C2D3E4F5', undefined]) {
      const { clientLog } = install({
        clientHandlers: handlers({ role: 'site_manager', device: { id: 77, device_uid: 'A0B1C2D3E4F5', hardware_type: 'esp32_wroom' } }),
      });
      const result = await setupSiteWithClaimedDevice({ ...baseInput, deviceUid });
      assert.equal(result.ok, true);
      assert.equal(result.site.assignedDevice.device_uid, 'A0B1C2D3E4F5');
      assert.ok(logHas(clientLog, /^COMMIT/));
      const assign = find(clientLog, /^UPDATE devices SET site_code/);
      assert.deepEqual(assign.params, [900, 'Kapı 1', 77]);
      // sahiplik sorgusu site olusturmadan ONCE
      const lookupAt = clientLog.findIndex((e) => /^SELECT \* FROM devices/.test(e.sql));
      const insertAt = clientLog.findIndex((e) => /^INSERT INTO sites/.test(e.sql));
      assert.ok(lookupAt >= 0 && lookupAt < insertAt);
    }
  });

  it('mevcut site yoneticisi ("Site Ekle", cihaz belirtmeden) ve super user cihazsiz kurulum yapabilir (bilincli ozellik korunur)', async () => {
    for (const role of ['site_manager', 'super_user']) {
      const { clientLog } = install({ clientHandlers: handlers({ role, device: null }) });
      const result = await setupSiteWithClaimedDevice({ ...baseInput });
      assert.equal(result.ok, true, role);
      assert.equal(result.site.assignedDevice, null);
      assert.ok(logHas(clientLog, /^INSERT INTO sites/));
      assert.ok(logHas(clientLog, /^COMMIT/));
    }
  });

  it('POST /membership/setup-site kullanici bazli hiz sinirlayiciyla korunur (authRequired sonrasi)', () => {
    const layer = membershipRouter.stack.find((l) => l.route?.path === '/membership/setup-site');
    assert.ok(layer);
    const handlers = layer.route.stack.map((entry) => entry.handle);
    assert.equal(handlers.length, 3, 'authRequired + setupSiteLimiter + isleyici');
    assert.equal(handlers[1], setupSiteLimiter);
  });

  it('setupSiteLimiter: ayni kullanici 10 istekten sonra 429 + Retry-After; baska kullanici etkilenmez', () => {
    const run = (code) => {
      const res = {
        statusCode: 200,
        headers: {},
        setHeader(name, value) { this.headers[name] = value; },
        status(code2) { this.statusCode = code2; return this; },
        json(body) { this.body = body; return this; },
      };
      let passed = false;
      setupSiteLimiter({ authUser: { id: code }, ip: '1.2.3.4', path: '/membership/setup-site' }, res, () => { passed = true; });
      return { res, passed };
    };
    for (let i = 0; i < 10; i += 1) {
      assert.equal(run(111).passed, true);
    }
    const blocked = run(111);
    assert.equal(blocked.passed, false);
    assert.equal(blocked.res.statusCode, 429);
    assert.ok(Number(blocked.res.headers['Retry-After']) > 0);
    assert.ok(blocked.res.body.retry_after_seconds > 0);
    assert.equal(run(222).passed, true);
  });
});

// ---------------------------------------------------------------------------
// toggle (pasife alma / aktif etme)
// ---------------------------------------------------------------------------
describe('toggleApartmentMemberStatus: aile reisi pasife alinca tum daire pasiflesmez; hesap durumu bildirilir', () => {
  const superUser = { id: 1, role: 'super_user' };
  const aptRow = (resident) => ({ id: 3, site_code: 101, block_id: 1, unit_label: 'Daire 3', resident_user_code: resident, resident_pin_code: null });

  function setup({ resident, membershipRole = 'APARTMENT_ADMIN', membershipRows = 1, otherAdmin = null, remaining = null, accountActive = true }) {
    return install({
      poolHandlers: [
        [/^SELECT a\.id, a\.site_code, a\.block_id/, { rowCount: 1, rows: [aptRow(resident)] }],
        [/^SELECT is_active FROM users WHERE user_code/, { rowCount: 1, rows: [{ is_active: accountActive }] }],
      ],
      clientHandlers: [
        [/^SELECT id, site_code, resident_user_code FROM apartments/, { rowCount: 1, rows: [aptRow(resident)] }],
        [/^UPDATE apartment_memberships SET is_active/, { rowCount: membershipRows, rows: membershipRows ? [{ role: membershipRole }] : [] }],
        [/AND is_active = TRUE AND role = 'APARTMENT_ADMIN'/, { rowCount: otherAdmin ? 1 : 0, rows: otherAdmin ? [{ user_code: otherAdmin }] : [] }],
        [/^SELECT user_code FROM apartment_memberships WHERE apartment_id = \$1 AND user_code <> \$2 AND is_active = TRUE ORDER BY/, { rowCount: remaining ? 1 : 0, rows: remaining ? [{ user_code: remaining }] : [] }],
      ],
    });
  }

  const toggle = (isActive, target = 20000) =>
    toggleApartmentMemberStatus({ apartmentId: 3, targetUserCode: target, isActive, authUser: superUser });

  it('uyelik satiri olan aile reisi pasife alinir: daire is_active DEGISMEZ, gosterge baska aktif yoneticiye devredilir', async () => {
    const { clientLog } = setup({ resident: 20000, otherAdmin: 20001 });
    const result = await toggle(false);
    assert.equal(result.is_active, false);
    assert.match(result.message, /pasife alındı/);
    assert.equal(has(clientLog, /^UPDATE apartments SET is_active/), false, 'tum daire pasiflesmemeli');
    const handOver = find(clientLog, /^UPDATE apartments SET resident_user_code = \$1 WHERE id = \$2$/);
    assert.deepEqual(handOver.params, [20001, 3]);
    assert.ok(has(clientLog, /^COMMIT/));
  });

  it('tek uye olan aile reisi: gosterge temizlenir ama eski PIN gostergesi silinmez (geri alinabilir islem)', async () => {
    const { clientLog } = setup({ resident: 20000 });
    await toggle(false);
    const clear = find(clientLog, /^UPDATE apartments SET resident_user_code = NULL/);
    assert.ok(clear, 'gosterge temizlenmeli');
    assert.doesNotMatch(clear.sql, /resident_pin_code/);
    assert.equal(has(clientLog, /^UPDATE apartments SET is_active/), false);
  });

  it('SAF eski (legacy) sakin: eski davranis korunur (apartments.is_active senkronize edilir)', async () => {
    const { clientLog } = setup({ resident: 20000, membershipRows: 0 });
    await toggle(false);
    const sync = find(clientLog, /^UPDATE apartments SET is_active = \$1 WHERE id = \$2/);
    assert.deepEqual(sync.params, [false, 3]);
    assert.equal(has(clientLog, /resident_user_code = NULL/), false);
  });

  it('aktif etme: gosterge bossa aile reisine geri konur; hesap aktifse klasik mesaj + account_is_active true', async () => {
    const { clientLog } = setup({ resident: 20000, accountActive: true });
    const result = await toggle(true);
    assert.equal(result.is_active, true);
    assert.equal(result.account_is_active, true);
    assert.equal(result.message, 'Daire sakini başarıyla aktif edildi.');
    const restore = find(clientLog, /^UPDATE apartments SET resident_user_code = \$1 WHERE id = \$2 AND resident_user_code IS NULL/);
    assert.deepEqual(restore.params, [20000, 3]);
  });

  it('hesap sistem yoneticisince pasifse: aktif etme basarili GORUNMEZ, mesaj/alan durumu dogru soyler', async () => {
    setup({ resident: 20001, accountActive: false });
    const result = await toggle(true, 20000);
    assert.equal(result.ok, true);
    assert.equal(result.account_is_active, false);
    assert.match(result.message, /hesabı sistem yöneticisi tarafından pasife alınmış/);
  });

  it('global users.is_active ASLA guncellenmez', async () => {
    const { clientLog, poolLog } = setup({ resident: 20000 });
    await toggle(false);
    await toggle(true);
    for (const entry of [...clientLog, ...poolLog]) {
      assert.doesNotMatch(entry.sql, /^UPDATE users/);
    }
  });
});

// ---------------------------------------------------------------------------
// approve / reject: yetki kontrolu durum kontrolunden ONCE
// ---------------------------------------------------------------------------
describe('approveJoinRequest / rejectJoinRequest: yetkisiz yonetici talebin durumunu ogrenemez', () => {
  const foreignManager = { id: 555, user_code: 555, role: 'site_manager' };

  function setup(status) {
    return install({
      clientHandlers: [
        [/^SELECT jr\.\*, s\.name AS site_name/, { rowCount: 1, rows: [{ id: 9, status, site_code: 77, apartment_id: 4, user_code: 900, full_name: 'X', unit_label: 'D1', block_name: 'A' }] }],
        [/^SELECT \* FROM join_requests WHERE id = \$1 FOR UPDATE/, { rowCount: 1, rows: [{ id: 9, status, site_code: 77, user_code: 900 }] }],
      ],
    });
  }

  it('baska sitenin yoneticisi: islenmis talepte bile 409 DEGIL 403 (durum sizmaz)', async () => {
    for (const status of ['APPROVED', 'REJECTED', 'PENDING']) {
      setup(status);
      await assert.rejects(
        () => approveJoinRequest({ requestId: 9, authUser: foreignManager }),
        (err) => err.statusCode === 403,
        `approve ${status}`,
      );
      setup(status);
      await assert.rejects(
        () => rejectJoinRequest({ requestId: 9, authUser: foreignManager, reason: 'x' }),
        (err) => err.statusCode === 403,
        `reject ${status}`,
      );
    }
  });

  it('yetkili yonetici islenmis talepte hala 409 alir; super user yetkili sayilir', async () => {
    install({
      clientHandlers: [
        [/^SELECT jr\.\*, s\.name AS site_name/, { rowCount: 1, rows: [{ id: 9, status: 'APPROVED', site_code: 77, apartment_id: 4, user_code: 900 }] }],
        [/^SELECT 1 FROM site_manager_sites/, { rowCount: 1, rows: [{ '?column?': 1 }] }],
      ],
    });
    await assert.rejects(
      () => approveJoinRequest({ requestId: 9, authUser: foreignManager }),
      (err) => err.statusCode === 409 && /APPROVED/.test(err.message),
    );
    install({
      clientHandlers: [
        [/^SELECT \* FROM join_requests WHERE id = \$1 FOR UPDATE/, { rowCount: 1, rows: [{ id: 9, status: 'REJECTED', site_code: 77, user_code: 900 }] }],
      ],
    });
    await assert.rejects(
      () => rejectJoinRequest({ requestId: 9, authUser: { id: 1, role: 'super_user' } }),
      (err) => err.statusCode === 409,
    );
  });
});

// ---------------------------------------------------------------------------
// sakin agaci: hesap durumu ayri alan (geriye uyumlu)
// ---------------------------------------------------------------------------
describe('getSiteResidentsTree: is_active (uyelik+hesap) yaninda account_is_active', () => {
  it('global pasif hesap account_is_active=false; uyelik pasif/hesap aktif ayirt edilir', async () => {
    const memberships = [
      { apartment_id: 3, user_code: 20000, role: 'APARTMENT_ADMIN', joined_at: null, full_name: 'Ali', email: 'a@x.com', phone_number: null, login_name: null, is_active: false, account_is_active: false },
      { apartment_id: 3, user_code: 20001, role: 'FAMILY_MEMBER', joined_at: null, full_name: 'Veli', email: 'v@x.com', phone_number: null, login_name: null, is_active: false, account_is_active: true },
      { apartment_id: 3, user_code: 20002, role: 'FAMILY_MEMBER', joined_at: null, full_name: 'Ayse', email: 'y@x.com', phone_number: null, login_name: null, is_active: true, account_is_active: true },
    ];
    const { poolLog } = install({
      poolHandlers: [
        [/^SELECT site_code AS id, name, city, district/, { rowCount: 1, rows: [{ id: 101, name: 'S', city: 'c', district: 'd' }] }],
        [/^SELECT id, site_code, block_name, sort_order FROM site_blocks/, { rowCount: 1, rows: [{ id: 1, site_code: 101, block_name: 'A', sort_order: 1 }] }],
        [/^SELECT id, block_id, unit_label, sort_order, resident_pin_code FROM apartments/, { rowCount: 1, rows: [{ id: 3, block_id: 1, unit_label: 'Daire 3', sort_order: 3, resident_pin_code: null }] }],
        [/FROM apartment_memberships am INNER JOIN apartments a/, { rowCount: 3, rows: memberships }],
      ],
    });
    const tree = await getSiteResidentsTree({ siteCode: 101, authUser: { id: 1, role: 'super_user' } });
    const residents = tree.blocks[0].apartments[0].residents;
    assert.deepEqual(residents.map((r) => [r.user_code, r.is_active, r.account_is_active]), [
      [20000, false, false],
      [20001, false, true],
      [20002, true, true],
    ]);
    assert.ok(find(poolLog, /FROM apartment_memberships am INNER JOIN apartments a/).sql.includes('u.is_active AS account_is_active'));
    assert.ok(find(poolLog, /FROM apartments a INNER JOIN users u ON u\.user_code = a\.resident_user_code/).sql.includes('u.is_active AS account_is_active'));
  });
});

// ---------------------------------------------------------------------------
// daire sakini olusturma / duzenleme (membership#3)
// ---------------------------------------------------------------------------
describe('provisionApartmentResident: mevcut sakin duzenlemede sifre bos olabilir; kimlik yalniz dahili hesapta guncellenir', () => {
  const aptRow = (resident) => ({ id: 3, site_code: 101, resident_user_code: resident, resident_email: null, block_name: 'A Blok', unit_label: 'Daire 3', sort_order: 3 });
  const input = { apartmentId: 3, fullName: 'Mehmet Kaya', loginName: 'mehmet.k', password: '', email: undefined, phoneNumber: '05551234567', isActive: true };

  function setup({ resident, userEmail }) {
    return install({
      clientHandlers: [
        [/^SELECT a\.id, a\.site_code, a\.resident_user_code/, { rowCount: 1, rows: [aptRow(resident)] }],
        [/^SELECT email FROM users WHERE user_code = \$1/, userEmail === undefined ? { rowCount: 0, rows: [] } : { rowCount: 1, rows: [{ email: userEmail }] }],
        [/^SELECT a\.id, a\.site_code, a\.block_id, b\.block_name/, { rowCount: 1, rows: [{ id: 3, resident_user_code: resident }] }],
      ],
    });
  }

  it('YENI sakin + bos sifre: 400 APARTMENT_PASSWORD_REQUIRED (kullanici olusturulmaz, ROLLBACK)', async () => {
    const { clientLog } = setup({ resident: null });
    await assert.rejects(
      () => provisionApartmentResident(input),
      (err) => err.statusCode === 400 && err.code === 'APARTMENT_PASSWORD_REQUIRED' && /4 haneli/.test(err.message),
    );
    assert.equal(has(clientLog, /^INSERT INTO users/), false);
    assert.ok(has(clientLog, /^ROLLBACK/));
  });

  it('hata mesajlari: yonetici ve admin rotalari 400 + ayni mesaj doner (500 DEGIL)', async () => {
    let status = null;
    let body = null;
    const res = { status(code) { status = code; return this; }, json(payload) { body = payload; return this; } };
    const error = Object.assign(new Error('Sifre 4 haneli sayisal olmali.'), { statusCode: 400, code: 'APARTMENT_PASSWORD_REQUIRED' });
    handleUserMutationError(error, res, 'Daire kullanicisi kaydedilemedi.');
    assert.equal(status, 400);
    assert.deepEqual(body, { error: 'Sifre 4 haneli sayisal olmali.' });
    // beklenmeyen hata hala 500 + genel mesaj
    const log = console.error;
    console.error = () => {};
    try {
      handleUserMutationError(new Error('SECRET'), res, 'Genel');
    } finally {
      console.error = log;
    }
    assert.equal(status, 500);
    assert.equal(body.error, 'Genel');
  });

  it('mevcut DAHILI (@ahbu.local) sakin: sifre bos olsa da duzenleme calisir, users satiri guncellenir', async () => {
    const { clientLog } = setup({ resident: 20000, userEmail: 'a1.3.101@ahbu.local' });
    await provisionApartmentResident(input);
    assert.ok(has(clientLog, /^UPDATE users SET full_name/), 'dahili hesapta kimlik guncellenir');
    assert.ok(has(clientLog, /^UPDATE apartments SET resident_email/));
    assert.ok(has(clientLog, /^COMMIT/));
  });

  it('mevcut GERCEK (e-postayla kayitli uyelik) sakin: e-posta/giris adi EZILMEZ; yalniz daire satiri guncellenir', async () => {
    const { clientLog } = setup({ resident: 20000, userEmail: 'ali@example.com' });
    await provisionApartmentResident(input);
    assert.equal(has(clientLog, /^UPDATE users/), false, 'gercek kullanicinin users satiri degismemeli');
    const aptUpdate = find(clientLog, /^UPDATE apartments SET resident_email/);
    assert.ok(aptUpdate);
    assert.ok(has(clientLog, /^COMMIT/));
  });
});

before(() => {
  // modullerin yan etkisi yok; yalnizca JWT_SECRET tanimli olmali (signAccessToken)
  assert.ok(process.env.JWT_SECRET);
});
