// Cihaz sahiplenme (POST /membership/claim-device) kişiyi site yöneticisi YAPMAZ (ürün kararı, docs/PLATFORM_SITE_BASVURUSU.md):
// onaysız yöneticilik hiçbir yoldan olmaz; yönetici olmanın yolu site başvurusu + süper kullanıcı onayıdır. (DB'siz, sıkı sahte istemci.)
import { describe, it, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { pool } from '../src/db.js';
import { claimDevice } from '../src/services/membership_service.js';

const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
const ok = (rows = []) => ({ rows, rowCount: rows.length });

function install({ role = 'site_manager', device = {}, claimRows = 'claimed', managedSite = true } = {}) {
  const log = [];
  const deviceRow = {
    id: 77,
    device_uid: '00861A0D5020',
    hardware_type: 'esp32_wroom',
    gate_name: null,
    site_code: null,
    owner_user_id: null,
    claimed_at: null,
    is_defective: false,
    defective_reason: null,
    ...device,
  };
  const client = {
    released: false,
    release() {
      client.released = true;
    },
    query: async (text, params = []) => {
      const sql = norm(text);
      log.push({ sql, params });
      if (/^(BEGIN|COMMIT|ROLLBACK)$/.test(sql)) return ok();
      if (/^SELECT id, user_code, full_name, email, email_verified, role FROM users/.test(sql)) {
        return ok([{ id: 7, user_code: 48213, full_name: 'Ayse', email: 'a@example.com', email_verified: true, role }]);
      }
      // Cihaz ekleme yetkisi: Geçiş Kontrol modülü açık bir sitenin yöneticisi (satır dönerse izin var).
      if (/^SELECT s\.site_code FROM sites s WHERE s\.approval_status = 'approved'/.test(sql)) return ok(managedSite ? [{ site_code: 5 }] : []);
      if (/FROM devices WHERE UPPER\(device_uid\)/.test(sql)) return ok([deviceRow]);
      if (/^UPDATE devices SET owner_user_id/.test(sql)) {
        if (claimRows === 'claimed') return ok([{ ...deviceRow, owner_user_id: 7, claimed_at: new Date() }]);
        return ok();
      }
      if (/^SELECT owner_user_id, is_defective FROM devices/.test(sql)) return ok([{ owner_user_id: 7, is_defective: false }]);
      throw new Error(`SAHTE VERITABANI: tanimsiz SQL: ${sql}`);
    },
  };
  pool.connect = async () => client;
  return { log, client };
}

afterEach(() => {
  delete pool.connect;
});

const writesUsers = (log) => log.some((entry) => /^(UPDATE|INSERT INTO|DELETE FROM)\s+users\b/i.test(entry.sql));

describe('claimDevice: rol DEĞİŞMEZ', () => {
  it('site yöneticisi (door_control açık site) sahiplenir: cihaz kullanıcıya atanır, users tablosuna HİÇ yazılmaz, rol aynı kalır', async () => {
    const { log, client } = install({ role: 'site_manager' });
    const result = await claimDevice({ userCode: 48213, deviceInput: 'GD-C3-00861A0D5020' });
    assert.equal(result.ok, true);
    assert.equal(result.role, 'site_manager', 'rol değişmedi');
    assert.equal(result.already_owned, undefined);
    assert.equal(result.device.owner_user_id, 7, 'cihaz kullanıcıya atandı');
    assert.ok(log.some((entry) => /^UPDATE devices SET owner_user_id/.test(entry.sql)), 'atomik sahiplenme çalıştı');
    assert.equal(writesUsers(log), false, 'users tablosuna yazılmadı');
    assert.ok(log.some((entry) => entry.sql === 'COMMIT'));
    assert.equal(client.released, true);
  });

  it('bireysel / daire sahibi / yönetici olmayan kullanıcı cihaz EKLEYEMEZ: 403, cihaz sorgusu ve yazım yok', async () => {
    for (const role of ['individual', 'apartment_owner', 'site_manager']) {
      const { log, client } = install({ role, managedSite: false });
      await assert.rejects(
        () => claimDevice({ userCode: 48213, deviceInput: '00861A0D5020' }),
        (e) => e.statusCode === 403 && e.code === 'DEVICE_ADD_FORBIDDEN' && /yalnız site yöneticisi, Geçiş Kontrol modülü açıkken/.test(e.message),
        `${role}: 403`,
      );
      assert.equal(log.some((entry) => /FROM devices/.test(entry.sql)), false, `${role}: cihaz sorgulanmadı (varlık sızmaz)`);
      assert.equal(log.some((entry) => /^UPDATE devices/.test(entry.sql)), false, `${role}: cihaz atanmadı`);
      assert.equal(writesUsers(log), false);
      assert.ok(log.some((entry) => entry.sql === 'ROLLBACK'));
      assert.equal(client.released, true);
    }
  });

  it('yetki sorgusu: yalnız onaylı site + yönetici bağı + door_control açık (satır yoksa varsayılan AÇIK); süper kullanıcıda sorgu yapılmaz', async () => {
    const { log } = install({ role: 'site_manager' });
    await claimDevice({ userCode: 48213, deviceInput: '00861A0D5020' });
    const check = log.find((entry) => /^SELECT s\.site_code FROM sites s/.test(entry.sql));
    assert.ok(check, 'yetki sorgusu çalıştı');
    assert.deepEqual(check.params, [48213], 'users.user_code ile');
    assert.match(check.sql, /site_manager_sites/);
    assert.match(check.sql, /SITE_OWNER', 'SITE_ADMIN/);
    assert.match(check.sql, /module_code = 'door_control'/);
    assert.match(check.sql, /TRUE \) = TRUE|TRUE\) = TRUE/);
    const superDb = install({ role: 'super_user', managedSite: false });
    const result = await claimDevice({ userCode: 48213, deviceInput: '00861A0D5020' });
    assert.equal(result.ok, true);
    assert.equal(superDb.log.some((entry) => /^SELECT s\.site_code FROM sites s/.test(entry.sql)), false, 'süper kullanıcı mevcut davranışı korur');
  });

  it('zaten sahip olunan cihazı yeniden okutmak (idempotent) da rolü yükseltmez', async () => {
    const { log } = install({ role: 'site_manager', device: { owner_user_id: 7 } });
    const result = await claimDevice({ userCode: 48213, deviceInput: '00861A0D5020' });
    assert.equal(result.already_owned, true);
    assert.equal(result.role, 'site_manager');
    assert.equal(writesUsers(log), false);
    assert.equal(log.some((entry) => /^UPDATE devices/.test(entry.sql)), false, 'yeniden atama yapılmaz');
  });

  it('eşzamanlı yarışta (atomik güncelleme 0 satır, kontrolde artık kendi cihazı) rol yükseltilmez', async () => {
    const { log } = install({ role: 'site_manager', claimRows: 'raced' });
    const result = await claimDevice({ userCode: 48213, deviceInput: '00861A0D5020' });
    assert.equal(result.already_owned, true);
    assert.equal(result.role, 'site_manager');
    assert.equal(writesUsers(log), false);
  });

  it('site yöneticisi / süper kullanıcı sahiplenmesi AYNEN çalışır: rol değişmez; mesaj kapıya bağlamayı söyler, site kurulumu vaat etmez', async () => {
    for (const role of ['site_manager', 'super_user']) {
      const { log } = install({ role });
      const result = await claimDevice({ userCode: 48213, deviceInput: '00861A0D5020' });
      assert.equal(result.role, role);
      assert.equal(writesUsers(log), false);
      assert.match(result.message, /Kayıtlı Cihazlar ekranından sitenizin bir kapısına bağlayabilirsiniz/);
      assert.doesNotMatch(result.message, /site .*kurulumu/);
    }
  });

  it('diğer doğrulamalar değişmedi: arızalı cihaz 400, başkasının cihazı 409, doğrulanmamış e-posta 403 (hiçbirinde users yazımı yok)', async () => {
    let db = install({ device: { is_defective: true, defective_reason: 'kırık' } });
    await assert.rejects(() => claimDevice({ userCode: 48213, deviceInput: '00861A0D5020' }), (e) => e.statusCode === 400 && /arızalı/.test(e.message));
    assert.equal(writesUsers(db.log), false);
    db = install({ device: { owner_user_id: 99 } });
    await assert.rejects(() => claimDevice({ userCode: 48213, deviceInput: '00861A0D5020' }), (e) => e.statusCode === 409);
    assert.equal(writesUsers(db.log), false);
    assert.ok(db.log.some((entry) => entry.sql === 'ROLLBACK'));
  });
});

describe('onaysız site yöneticisi terfisi: kaynak taraması', () => {
  const here = path.dirname(fileURLToPath(import.meta.url));
  const srcDir = path.join(here, '..', 'src');
  const files = [];
  (function walk(dir) {
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) walk(full);
      else if (entry.name.endsWith('.js')) files.push(full);
    }
  })(srcDir);
  const sources = new Map(files.map((file) => [path.relative(srcDir, file).replace(/\\/g, '/'), readFileSync(file, 'utf8')]));

  it("`role = 'site_manager'` atayan UPDATE'ler yalnızca bilinen, onaylı yollardadır (başvuru onayı, davet / ortak yönetici ataması, davet kabulü)", () => {
    const allowed = new Map([
      ['modules/oauth_login.js', 1], // OAuth ile giriş yapan kullanıcının bekleyen yönetici daveti kabulü
      ['services/site_setup_core.js', 1], // başvuru onayı + anlık kurulum (site yöneticisi / süper)
      ['services/membership_service.js', 1], // bekleyen yönetici DAVETİ olan e-posta doğrulanınca (davet = mevcut yönetici kararı)
      ['services/site_service.js', 1], // mevcut yöneticinin / süperin siteye ortak yönetici ataması (addSiteManager)
    ]);
    const found = new Map();
    for (const [name, text] of sources) {
      const count = (text.match(/UPDATE\s+users\s+SET\s+role\s*=\s*'site_manager'/g) ?? []).length;
      if (count > 0) found.set(name, count);
    }
    assert.deepEqual([...found.entries()].sort(), [...allowed.entries()].sort());
  });

  it('cihaz sahiplenme ve site başvurusu kodu rolü site_manager yapan ifade içermez (yalnız ortak çekirdek yapar)', () => {
    for (const name of ['modules/site_application_service.js', 'modules/site_application_routes.js', 'modules/site_application_common.js', 'routes/membership_routes.js']) {
      assert.equal(/UPDATE\s+users\s+SET\s+role/i.test(sources.get(name)), false, name);
    }
  });
});
