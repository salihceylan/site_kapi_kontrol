// S2: cihaz sahiplenme (claim) koşulu, salt-okunur my-devices ve site kurulumu girdi sınırları (DB'siz).
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import {
  SQL_CLAIM_DEVICE_ATOMIC,
  normalizeClaimDeviceInput,
  normalizeSetupSiteInput,
  parseBoundedInteger,
  shouldPromoteToSiteManager,
} from '../src/services/membership_rules.js';
import { SITE_LIMITS } from '../src/utils/validators.js';

process.env.JWT_SECRET = process.env.JWT_SECRET || 'test-secret-for-members-tests-0123456789abcdef';

describe('members: claimDevice atomik koşulu', () => {
  const sql = SQL_CLAIM_DEVICE_ATOMIC.replace(/\s+/g, ' ').trim();

  it('UPDATE yalnızca sahibi olmayan cihaza uygulanır ve RETURNING kullanır (0 satır -> 409)', () => {
    assert.match(sql, /^UPDATE devices SET owner_user_id = \$1, assigned_user_code = \$2, claimed_at = NOW\(\)/);
    assert.match(sql, /WHERE id = \$3 AND owner_user_id IS NULL/);
    assert.match(sql, /RETURNING id, device_uid/);
  });

  it('arızalı cihaz koşulu da atomik UPDATE içindedir', () => {
    assert.match(sql, /COALESCE\(is_defective, FALSE\) = FALSE/);
  });

  it('rol yükseltme yalnızca individual/apartment_owner için geçerlidir', () => {
    assert.equal(shouldPromoteToSiteManager('individual'), true);
    assert.equal(shouldPromoteToSiteManager('apartment_owner'), true);
    assert.equal(shouldPromoteToSiteManager('site_manager'), false);
    assert.equal(shouldPromoteToSiteManager('super_user'), false);
    assert.equal(shouldPromoteToSiteManager(undefined), false);
  });

  it('kutu QR içeriği UID\'ye normalize edilir', () => {
    assert.equal(normalizeClaimDeviceInput('GD-C3-00861A0D5020').cleanUid, '00861A0D5020');
    assert.equal(normalizeClaimDeviceInput('00:86:1a:0d:50:20').cleanUid, '00861A0D5020');
    assert.equal(normalizeClaimDeviceInput('DEVICE:00861a0d5020').cleanUid, '00861A0D5020');
    assert.equal(normalizeClaimDeviceInput('https://x.example/device/00861A0D5020').cleanUid, '00861A0D5020');
  });

  it('boş veya aşırı uzun giriş 400 ile reddedilir', () => {
    assert.throws(() => normalizeClaimDeviceInput('   '), (err) => err.statusCode === 400);
    assert.throws(() => normalizeClaimDeviceInput(undefined), (err) => err.statusCode === 400);
    assert.throws(() => normalizeClaimDeviceInput('A'.repeat(500)), (err) => err.statusCode === 400);
  });
});

describe('members: getMyClaimedDevices salt-okunur, rol yükseltme yalnız claim anında', () => {
  it('getMyClaimedDevices kaynağında UPDATE yoktur', async () => {
    const { getMyClaimedDevices, claimDevice } = await import('../src/services/membership_service.js');
    const readOnlySource = getMyClaimedDevices.toString();
    assert.equal(/UPDATE\s+users/i.test(readOnlySource), false);
    assert.equal(/\bUPDATE\b/i.test(readOnlySource), false);
    assert.equal(/\bINSERT\b|\bDELETE\b/i.test(readOnlySource), false);
    // rol yükseltme claim akışında yapılır
    assert.match(claimDevice.toString(), /site_manager/);
  });

  it('claimDevice oturum kodu geçersizse DB\'ye gitmeden 401 verir', async () => {
    const { claimDevice } = await import('../src/services/membership_service.js');
    await assert.rejects(
      () => claimDevice({ userCode: 'abc', deviceInput: '00861A0D5020' }),
      (err) => err.statusCode === 401,
    );
    await assert.rejects(
      () => claimDevice({ userCode: 99999999999, deviceInput: '00861A0D5020' }),
      (err) => err.statusCode === 401,
    );
  });

  it('kaynak kodda users.id ile user_code karıştıran OR kalıbı kalmamıştır', async () => {
    const { readFileSync } = await import('node:fs');
    const text = readFileSync(new URL('../src/services/membership_service.js', import.meta.url), 'utf8');
    assert.equal(/user_code\s*=\s*\$1\s+OR\s+id\s*=\s*\$1/i.test(text), false);
  });
});

describe('members: setup-site girdi sınırları', () => {
  it('varsayılanlar: blok verilmezse A Blok / 10 daire, kapı sayısı 1', () => {
    const out = normalizeSetupSiteInput({ name: ' Site ', blocks: undefined, doors: undefined });
    assert.equal(out.siteName, 'Site');
    assert.deepEqual(out.blocks, [{ name: 'A Blok', apartmentCount: 10, sortOrder: 1 }]);
    assert.equal(out.totalApartmentCount, 10);
    assert.deepEqual(out.doors, [{ name: 'Kapı 1', doorIndex: 1 }]);
    assert.deepEqual(out.blockApartmentCounts, [10]);
  });

  it('sınırlar admin uçlarıyla aynı sabitlerdir (blok 100, daire 5000, kapı 100)', () => {
    assert.deepEqual({ ...SITE_LIMITS }, { maxBlocks: 100, maxApartments: 5000, maxDoors: 100 });
  });

  it('blok sayısı üst sınırı aşılırsa 400', () => {
    const blocks = Array.from({ length: SITE_LIMITS.maxBlocks + 1 }, (_, i) => ({
      name: `B${i}`,
      apartmentCount: 1,
    }));
    assert.throws(() => normalizeSetupSiteInput({ name: 'S', blocks }), (err) => err.statusCode === 400);
  });

  it('toplam daire sayısı 5000\'i aşarsa 400; tam 5000 kabul edilir', () => {
    assert.throws(
      () =>
        normalizeSetupSiteInput({
          name: 'S',
          blocks: [
            { name: 'A', apartmentCount: 3000 },
            { name: 'B', apartmentCount: 2001 },
          ],
        }),
      (err) => err.statusCode === 400,
    );
    const ok = normalizeSetupSiteInput({
      name: 'S',
      blocks: [
        { name: 'A', apartmentCount: 3000 },
        { name: 'B', apartmentCount: 2000 },
      ],
    });
    assert.equal(ok.totalApartmentCount, 5000);
  });

  it('kapı listesi ve doorCount üst sınırı uygulanır', () => {
    const doors = Array.from({ length: SITE_LIMITS.maxDoors + 1 }, (_, i) => ({ name: `K${i}` }));
    assert.throws(() => normalizeSetupSiteInput({ name: 'S', doors }), (err) => err.statusCode === 400);
    assert.throws(() => normalizeSetupSiteInput({ name: 'S', doorCount: 101 }), (err) => err.statusCode === 400);
    assert.throws(() => normalizeSetupSiteInput({ name: 'S', doorCount: '5; DROP' }), (err) => err.statusCode === 400);
    const out = normalizeSetupSiteInput({ name: 'S', doorCount: '3' });
    assert.equal(out.totalDoorCount, 3);
    assert.deepEqual(out.doors.map((d) => d.name), ['Kapı 1', 'Kapı 2', 'Kapı 3']);
  });

  it('parseInt-güvenli: "12abc", ondalık, negatif, 0 ve devasa sayı reddedilir', () => {
    const opts = { min: 1, max: 5000, defaultValue: 10, label: 'Daire sayısı' };
    assert.equal(parseBoundedInteger(undefined, opts), 10);
    assert.equal(parseBoundedInteger('', opts), 10);
    assert.equal(parseBoundedInteger('25', opts), 25);
    assert.equal(parseBoundedInteger(25, opts), 25);
    for (const bad of ['12abc', 12.5, -3, 0, '0', 1e21, '9999999999999', 'abc', {}, [], true]) {
      assert.throws(() => parseBoundedInteger(bad, opts), (err) => err.statusCode === 400, String(bad));
    }
  });

  it('yinelenen blok adı ve boş site adı 400; uzun adlar sınırlanır', () => {
    assert.throws(
      () =>
        normalizeSetupSiteInput({
          name: 'S',
          blocks: [{ name: 'A Blok', apartmentCount: 2 }, { name: 'a blok', apartmentCount: 3 }],
        }),
      (err) => err.statusCode === 400,
    );
    assert.throws(() => normalizeSetupSiteInput({ name: '   ' }), (err) => err.statusCode === 400);
    assert.throws(() => normalizeSetupSiteInput({ name: 'x'.repeat(121) }), (err) => err.statusCode === 400);
    const out = normalizeSetupSiteInput({
      name: 'S',
      city: 'c'.repeat(500),
      blocks: [{ name: 'b'.repeat(200), apartmentCount: 1 }],
    });
    assert.equal(out.city.length, 200);
    assert.equal(out.blocks[0].name.length, 60);
  });

  it('boş blok adı sıra numarasıyla doldurulur; blok dizisinde null öğe çökmeye yol açmaz', () => {
    const out = normalizeSetupSiteInput({
      name: 'S',
      blocks: [{ name: '', apartmentCount: 4 }, null],
    });
    assert.equal(out.blocks[0].name, 'Blok 1');
    assert.equal(out.blocks[1].name, 'Blok 2');
    assert.equal(out.blocks[1].apartmentCount, 10);
  });
});
