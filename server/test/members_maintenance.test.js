// S2: bakım servisi artık kullanıcı silmez / tablo düşürmez; db.js şeması yalnızca additive (DB'siz, sahte db ile).
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runDatabaseCleanup } from '../src/services/maintenance_service.js';
import { mapDoorRow, mapSiteRow } from '../src/utils/helpers.js';

function createFakeDb({ failOn = null } = {}) {
  const queries = [];
  return {
    queries,
    async query(text) {
      const sql = String(text);
      queries.push(sql);
      if (failOn && failOn.test(sql)) {
        throw new Error('simulated db failure: connection string postgres://user:secret@host/db');
      }
      return { rowCount: 3, rows: [] };
    },
  };
}

describe('members: maintenance_service yıkıcı işlem yapmaz', () => {
  it('@ahbu.local kullanıcı silme ve DROP TABLE çalıştırılmaz', async () => {
    const db = createFakeDb();
    const result = await runDatabaseCleanup(db);

    assert.equal(result.success, true);
    for (const sql of db.queries) {
      assert.equal(/DELETE\s+FROM\s+users\b/i.test(sql), false, `users silme: ${sql}`);
      assert.equal(/DROP\s+TABLE/i.test(sql), false, `DROP TABLE: ${sql}`);
      assert.equal(/ahbu\.local/i.test(sql), false, `ahbu.local: ${sql}`);
      assert.equal(/\bTRUNCATE\b/i.test(sql), false);
    }
  });

  it('silinen tablolar yalnızca süresi dolmuş token/kod ve eski loglarla sınırlıdır', async () => {
    const db = createFakeDb();
    await runDatabaseCleanup(db);

    const deletes = db.queries
      .map((sql) => sql.replace(/\s+/g, ' ').trim())
      .filter((sql) => /^DELETE FROM/i.test(sql));
    const tables = deletes.map((sql) => sql.match(/^DELETE FROM (\w+)/i)[1]).sort();
    assert.deepEqual(tables, [
      'device_connectivity_logs',
      'door_access_logs',
      'email_verifications',
      'qr_access_tokens',
    ]);
    // her DELETE zaman koşulu taşır (koşulsuz toplu silme yok)
    for (const sql of deletes) {
      assert.match(sql, /WHERE .*(NOW\(\) - INTERVAL)/i);
    }
    // log saklama süresi 30 gün korunur
    const doorLogDelete = deletes.find((sql) => /door_access_logs/.test(sql));
    assert.match(doorLogDelete, /INTERVAL '30 days'/);
  });

  it('dönüş şekli geriye dönük uyumlu: stats alanları korunur, silinen kullanıcı/yetim sayısı 0', async () => {
    const result = await runDatabaseCleanup(createFakeDb());
    assert.deepEqual(Object.keys(result.stats).sort(), [
      'cleanedAt',
      'dummyUsersCleaned',
      'expiredEmailVerificationsCleaned',
      'expiredQrTokensCleaned',
      'oldConnectivityLogsCleaned',
      'oldDoorLogsCleaned',
      'orphanedMembershipsCleaned',
    ]);
    assert.equal(result.stats.dummyUsersCleaned, 0);
    assert.equal(result.stats.orphanedMembershipsCleaned, 0);
    assert.equal(result.totalCleaned, 3 * 4);
  });

  it('hata durumunda veritabanı hata metni sonuçta sızdırılmaz', async () => {
    const result = await runDatabaseCleanup(createFakeDb({ failOn: /door_access_logs/ }));
    assert.equal(result.success, false);
    assert.equal(/secret|postgres:\/\//i.test(JSON.stringify(result)), false);
  });
});

describe('members: db.js yalnızca additive şema değişikliği içerir', () => {
  const dbSource = readFileSync(new URL('../src/db.js', import.meta.url), 'utf8');

  it('tek seferlik DELETE FROM users / apartment_owner silme bloğu yok', () => {
    assert.equal(/DELETE\s+FROM\s+users/i.test(dbSource), false);
    assert.equal(/reset_apartment_residents_after_site_approval_flow_v1'/.test(dbSource.replace(/\/\/.*$/gm, '')), false);
    assert.equal(/DROP\s+TABLE/i.test(dbSource), false);
    assert.equal(/TRUNCATE/i.test(dbSource), false);
  });

  it('DELETE FROM ifadesi hiç yok; zayıf md5(random()) token üretimi kaldırılmış', () => {
    const noComments = dbSource.replace(/\/\/.*$/gm, '');
    assert.equal(/\bDELETE\s+FROM\b/i.test(noComments), false);
    assert.equal(/md5\s*\(\s*random/i.test(noComments), false);
  });

  it('users_role_check yalnızca koşullu DO bloğunda DROP/ADD edilir', () => {
    const noComments = dbSource.replace(/\/\/.*$/gm, '');
    const dropMatches = noComments.match(/DROP\s+CONSTRAINT[^;]*users_role_check/gi) || [];
    assert.equal(dropMatches.length, 1);
    const doBlock = noComments.match(/DO \$\$\s+DECLARE\s+current_def[\s\S]*?END \$\$;/);
    assert.ok(doBlock, 'koşullu DO bloğu bulunamadı');
    assert.match(doBlock[0], /pg_get_constraintdef/);
    assert.match(doBlock[0], /IF current_def IS NULL THEN/);
    assert.match(doBlock[0], /NOT LIKE '%individual%'/);
  });

  it('migration 025 (şifre sıfırlama) kolon ve indeksi, LOWER(email) indeksi idempotent eklenir', () => {
    assert.match(dbSource, /ADD COLUMN IF NOT EXISTS password_reset_token_hash TEXT/);
    assert.match(dbSource, /ADD COLUMN IF NOT EXISTS password_reset_expires_at TIMESTAMPTZ/);
    assert.match(dbSource, /CREATE INDEX IF NOT EXISTS idx_users_password_reset_token/);
    assert.match(dbSource, /CREATE INDEX IF NOT EXISTS idx_users_email_lower\s+ON users \(LOWER\(email\)\)/);
    assert.match(dbSource, /ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW\(\)/);
  });

  it('tüm CREATE TABLE / CREATE INDEX / ADD COLUMN ifadeleri IF NOT EXISTS içerir', () => {
    const noComments = dbSource.replace(/\/\/.*$/gm, '').replace(/--.*$/gm, '');
    const creates = noComments.match(/CREATE\s+(UNIQUE\s+)?(TABLE|INDEX)\s+(?!IF NOT EXISTS)/gi) || [];
    assert.deepEqual(creates, []);
    const addColumns = noComments.match(/ADD\s+COLUMN\s+(?!IF NOT EXISTS)/gi) || [];
    assert.deepEqual(addColumns, []);
  });
});

describe('members: mapSiteRow / mapDoorRow gizli anahtar sızdırmaz', () => {
  const secret = 'JBSWY3DPEHPK3PXP-gizli';

  it('mapSiteRow çıktısında qr_totp_secret yoktur', () => {
    const mapped = mapSiteRow({ id: 1, name: 'S', qr_totp_secret: secret, created_at: new Date() });
    assert.equal('qr_totp_secret' in mapped, false);
    assert.equal(JSON.stringify(mapped).includes(secret), false);
    // diğer alanlar korunur
    assert.equal(mapped.qr_rotation_seconds, 30);
    assert.equal(mapped.geofence_radius_meters, 100);
  });

  it('mapDoorRow çıktısında qr_totp_secret yoktur', () => {
    const mapped = mapDoorRow({ id: 2, site_code: 1, door_name: 'K', door_index: 1, qr_totp_secret: secret });
    assert.equal('qr_totp_secret' in mapped, false);
    assert.equal(JSON.stringify(mapped).includes(secret), false);
    assert.equal(mapped.qr_rotation_seconds, 30);
  });
});
