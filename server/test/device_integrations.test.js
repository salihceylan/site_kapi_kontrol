// Kart ödemesi arayüzü (F6) + kamera/plaka (T8): saf yardımcılar, 065 migration <-> şema eşitliği, katalog (DB'siz).
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { DEFAULT_MIGRATIONS_DIR } from '../scripts/migrate.js';
import { DEVICE_INTEGRATIONS_DDL, DEVICE_INTEGRATIONS_DDL_ORDER, ensureDeviceIntegrationsSchema } from '../src/modules/device_integrations_schema.js';
import {
  decryptSecret,
  encryptSecret,
  mapCamera,
  parseCameraInput,
  parseDeviceToken,
  parsePlateEvent,
  recordPlateEvent,
  tokenMatches,
} from '../src/modules/device_integrations_service.js';
import { getModuleDefinition } from '../src/modules/catalog.js';
import { createHash } from 'node:crypto';
import path from 'node:path';

process.env.JWT_SECRET ||= 'test-secret-test-secret-test-secret-123456';

const norm = (t) => t.replace(/--.*$/gm, ' ').replace(/\s+/g, ' ').trim();

describe('065 migration <-> şema', () => {
  it('aynı ifadeler, aynı sırada', () => {
    const sql = readFileSync(path.join(DEFAULT_MIGRATIONS_DIR, '065_device_integrations.sql'), 'utf8').replace(/\r\n/g, '\n');
    const expected = DEVICE_INTEGRATIONS_DDL_ORDER.map((n) => `${norm(DEVICE_INTEGRATIONS_DDL[n])};`).join(' ');
    assert.equal(norm(sql), expected);
  });

  it('her şey varsa hiçbir DDL gönderilmez', async () => {
    const calls = [];
    const client = {
      async query(sql) {
        calls.push(sql);
        return { rows: [{ tables: ['payment_provider_settings', 'camera_devices', 'plate_events'], indexes: ['idx_camera_devices_site', 'idx_plate_events_site'] }] };
      },
    };
    await ensureDeviceIntegrationsSchema(client);
    assert.equal(calls.length, 1);
  });

  it('yalnız eksik tablo ve FK oluşturulur', async () => {
    const calls = [];
    const client = {
      async query(sql) {
        calls.push(sql);
        return { rows: [{ tables: ['payment_provider_settings', 'camera_devices'], indexes: ['idx_camera_devices_site'] }] };
      },
    };
    await ensureDeviceIntegrationsSchema(client);
    const ddl = calls.filter((s) => /CREATE TABLE|ADD CONSTRAINT|CREATE INDEX/.test(s));
    assert.equal(ddl.length, 3);
    assert.match(ddl[0], /plate_events/);
  });
});

describe('katalog', () => {
  it('iki modül varsayılan KAPALI, çekirdek değil', () => {
    for (const code of ['card_payments', 'plate_cameras']) {
      const def = getModuleDefinition(code);
      assert.equal(def.core, false);
      assert.equal(def.defaultEnabled, false);
    }
  });
});

describe('yardımcılar', () => {
  it('parola şifrelenir ve geri açılır', () => {
    const enc = encryptSecret('gizli-parola');
    assert.ok(!enc.includes('gizli-parola'));
    assert.equal(decryptSecret(enc), 'gizli-parola');
    assert.notEqual(encryptSecret('gizli-parola'), enc);
    assert.throws(() => decryptSecret(`${enc.slice(0, enc.lastIndexOf(":") + 1)}QUFBQUFBQUFB`));
  });

  it('belirteç biçimi ve karşılaştırma', () => {
    const secret = 'a'.repeat(48);
    assert.deepEqual(parseDeviceToken(`12.${secret}`), { id: 12, secret });
    assert.equal(parseDeviceToken('abc'), null);
    assert.equal(parseDeviceToken(undefined), null);
    const hash = createHash('sha256').update(secret).digest('hex');
    assert.equal(tokenMatches(secret, hash), true);
    assert.equal(tokenMatches('b'.repeat(48), hash), false);
    assert.equal(tokenMatches(secret, null), false);
  });

  it('kamera girdisi doğrulanır', () => {
    const ok = parseCameraInput({ brand: 'Hikvision', name: 'Giriş', host: '192.168.1.10', port: '8000', username: 'admin', password: 'x' });
    assert.equal(ok.brand, 'hikvision');
    assert.equal(ok.port, 8000);
    assert.throws(() => parseCameraInput({ brand: 'x', name: 'a', host: '1.1.1.1' }), { code: 'INVALID_BODY' });
    assert.throws(() => parseCameraInput({ brand: 'onvif', name: 'a', host: 'bad host!' }), { code: 'INVALID_BODY' });
    assert.throws(() => parseCameraInput({ brand: 'onvif', name: 'a', host: '1.1.1.1', port: 70000 }), { code: 'INVALID_BODY' });
    assert.throws(() => parseCameraInput({ brand: 'onvif', name: '', host: '1.1.1.1' }), { code: 'INVALID_BODY' });
  });

  it('plaka olayı normalize edilir; geçersiz plaka 400', () => {
    assert.equal(parsePlateEvent({ plate: '34 abc 123' }).plate, '34ABC123');
    assert.throws(() => parsePlateEvent({ plate: '!' }), { code: 'PLATE_INVALID' });
    assert.throws(() => parsePlateEvent({}), { code: 'PLATE_INVALID' });
  });

  it('kamera yanıtı parola / belirteç sızdırmaz', () => {
    const out = mapCamera({ id: '3', brand: 'onvif', name: 'k', host: 'h', port: null, username: 'u', password_enc: 'v1:x', is_active: true, last_event_at: null, created_at: new Date(), token_hash: 'zz' });
    assert.equal(out.has_password, true);
    assert.ok(!('password_enc' in out) && !('token_hash' in out) && !('password' in out));
  });

  it('geçersiz belirteçle olay ucu DB\'ye gitmeden 401', async () => {
    await assert.rejects(() => recordPlateEvent({ rawToken: 'kotu', body: { plate: '34ABC123' }, isModuleOn: async () => true }), { code: 'INVALID_DEVICE_TOKEN' });
  });
});
