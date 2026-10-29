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
      'apartment_notices',
      // 085: 30 gundur dokunulmamis ve kilidi bitmis kalici deneme siniri satirlari (sure dolmus sayac; kilitli satira dokunulmaz).
      'auth_attempt_limits',
      'device_connectivity_logs',
      'door_access_logs',
      'email_verifications',
      'pending_registrations',
      'qr_access_tokens',
      // 106 (kapanis): bitmis deneme erisim kodu satirlari 90 gun sonra; kullanilmis ama kapanmamis satira dokunulmaz.
      'trial_access_codes',
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
      'expiredPendingRegistrationsCleaned',
      'expiredQrTokensCleaned',
      'oldConnectivityLogsCleaned',
      'oldDoorLogsCleaned',
      'orphanedMembershipsCleaned',
    ]);
    assert.equal(result.stats.dummyUsersCleaned, 0);
    assert.equal(result.stats.orphanedMembershipsCleaned, 0);
    assert.equal(result.totalCleaned, 3 * 5);
  });

  it('deneme erişim kodu: 90 gün koşulu, açık oturuma dokunmaz, silinen sayı işlem izine yazılır, stats sözleşmesi aynı', async () => {
    const calls = [];
    const db = {
      async query(text, params) {
        const sql = String(text).replace(/\s+/g, ' ').trim();
        calls.push({ sql, params });
        return { rowCount: /^DELETE FROM trial_access_codes/i.test(sql) ? 4 : 3, rows: [] };
      },
    };
    const result = await runDatabaseCleanup(db);
    assert.equal(result.success, true);
    const del = calls.find((c) => /^DELETE FROM trial_access_codes/i.test(c.sql));
    assert.ok(del, 'trial_access_codes silme sorgusu var');
    assert.match(del.sql, /INTERVAL '90 days'/);
    assert.doesNotMatch(del.sql, /INTERVAL '(?!90 days)/);
    // kullanilmis ve KAPANMAMIS (used_by dolu) satir hicbir dalda silinmez: used_at IS NOT NULL dallari closed_at ya da used_by NULL sart kosar
    assert.match(del.sql, /used_at IS NOT NULL AND closed_at IS NOT NULL AND closed_at < NOW\(\) - INTERVAL '90 days'/);
    assert.match(del.sql, /used_at IS NOT NULL AND used_by IS NULL AND closed_at IS NULL AND session_expires_at < NOW\(\) - INTERVAL '90 days'/);
    assert.match(del.sql, /used_at IS NULL AND LEAST\(expires_at, COALESCE\(revoked_at, expires_at\)\) < NOW\(\) - INTERVAL '90 days'/);
    // islem izi sayiyla
    const audit = calls.find((c) => /INSERT INTO audit_log/i.test(c.sql));
    assert.ok(audit, 'audit_log kaydi yazildi');
    assert.equal(audit.params[3], 'maintenance.trial_access_codes_purged');
    assert.deepEqual(JSON.parse(audit.params[7]), { deleted: 4, retention_days: 90 });
    assert.equal('trialAccessCodesCleaned' in result.stats, false);
  });

  it('deneme erişim kodu silinmediyse (0 satır) işlem izi yazılmaz; tablo hatası temizliği durdurmaz', async () => {
    const calls = [];
    const db = {
      async query(text) {
        const sql = String(text).replace(/\s+/g, ' ').trim();
        calls.push(sql);
        if (/trial_access_codes/.test(sql)) {
          const err = new Error('relation missing');
          err.code = '42P01';
          throw err;
        }
        return { rowCount: 1, rows: [] };
      },
    };
    const result = await runDatabaseCleanup(db);
    assert.equal(result.success, true);
    assert.equal(calls.some((sql) => /INSERT INTO audit_log/i.test(sql)), false);
    assert.ok(calls.some((sql) => /app_maintenance_runs/.test(sql)), 'temizlik sonuna kadar calisti');
  });

  it('bekleyen kayıt (hesap DEĞİL) 2 gün sonra silinir; users tablosuna dokunulmaz', async () => {
    const db = createFakeDb();
    const result = await runDatabaseCleanup(db);
    const pendingDelete = db.queries
      .map((sql) => sql.replace(/\s+/g, ' ').trim())
      .find((sql) => /^DELETE FROM pending_registrations/i.test(sql));
    assert.match(pendingDelete, /WHERE updated_at < NOW\(\) - INTERVAL '2 days'/);
    assert.equal(result.stats.expiredPendingRegistrationsCleaned, 3);
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
    // 034 (finans defteri): BEFORE TRUNCATE tetikleyicileri TRUNCATE'i ENGELLER (koruma, veri silme degil). Yalniz bu iki kalip ve tetikleyici adlari muaf;
    // gercek bir TRUNCATE ifadesi hala hata verir.
    const withoutLedgerGuards = dbSource.replace(/BEFORE\s+TRUNCATE\s+ON\s+(ledger_entries|fee_runs)\b/gi, '').replace(/\btrg_[a-z_]*truncate\b/gi, '');
    assert.equal(/TRUNCATE/i.test(withoutLedgerGuards), false);
    assert.equal((dbSource.match(/BEFORE\s+TRUNCATE\s+ON\b/gi) || []).length, 2);
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

  it('bekleyen kayıt tablosu ve e-postaya (küçük harf) göre tekil indeks idempotent eklenir', () => {
    assert.match(dbSource, /CREATE TABLE IF NOT EXISTS pending_registrations/);
    assert.match(dbSource, /CREATE UNIQUE INDEX IF NOT EXISTS uq_pending_registrations_email\s+ON pending_registrations \(LOWER\(email\)\)/);
    const migration = readFileSync(new URL('../migrations/028_pending_registrations.sql', import.meta.url), 'utf8');
    assert.match(migration, /CREATE TABLE IF NOT EXISTS pending_registrations/);
    assert.match(migration, /CREATE UNIQUE INDEX IF NOT EXISTS uq_pending_registrations_email/);
    // parola düz metin tutulmaz: yalnızca özet kolonu vardır
    assert.match(migration, /password_hash TEXT NOT NULL/);
    assert.equal(/\bpassword\s+TEXT/i.test(migration), false);
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
