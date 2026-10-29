// 106 deneme erişim kodu şeması: db.js ifadeleri migration ile birebir aynı, idempotent, mevcut tablolara ALTER yok, ensure davranışı.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { TRIAL_ACCESS_DDL, TRIAL_ACCESS_TABLES, ensureTrialAccessSchema } from '../src/modules/trial_access_schema.js';

const norm = (s) => s.replace(/--.*$/gm, '').replace(/\s+/g, ' ').replace(/ ?\( ?/g, '(').replace(/ ?\) ?/g, ')').replace(/ ?, ?/g, ',').trim();
const dir = path.join(path.dirname(fileURLToPath(import.meta.url)), '..');
const migration = readFileSync(path.join(dir, 'migrations', '106_trial_access_codes.sql'), 'utf8');
const dbSource = readFileSync(path.join(dir, 'src', 'db.js'), 'utf8');

describe('106 deneme erişim kodu DDL', () => {
  it('her db.js ifadesi migration içinde birebir bulunur ve idempotenttir', () => {
    const all = norm(migration);
    assert.ok(TRIAL_ACCESS_DDL.length >= 4);
    for (const sql of TRIAL_ACCESS_DDL) {
      assert.match(sql, /IF NOT EXISTS/);
      assert.ok(all.includes(norm(sql)), `migration ile ayni degil: ${sql.slice(0, 70)}`);
    }
    // migration'da db.js'te olmayan ifade yok (iki yön)
    const statements = norm(migration).split(';').map((s) => s.trim()).filter(Boolean);
    assert.equal(statements.length, TRIAL_ACCESS_DDL.length);
  });

  it('mevcut tablolara ALTER yok (users / sites sıcak tablolarına kilit yok); yalnız yeni tablo ve indeksler', () => {
    const code = migration.replace(/--.*$/gm, '').replace(/ON DELETE (CASCADE|SET NULL)/gi, '');
    assert.equal(/\bALTER\s+TABLE\b/i.test(code), false);
    assert.equal(/\bDROP\b/i.test(code), false);
    assert.equal(/\b(DELETE|UPDATE|INSERT)\b/i.test(code), false);
    assert.deepEqual([...TRIAL_ACCESS_TABLES], ['trial_access_codes']);
  });

  it('tablo: kod YALNIZ özet olarak saklanır (düz kod sütunu yok), tek kullanım için kısıtlar var', () => {
    const table = norm(TRIAL_ACCESS_DDL[0]);
    assert.match(table, /code_hash TEXT NOT NULL/);
    assert.match(table, /UNIQUE\(code_hash\)/);
    assert.equal(/\bcode TEXT\b/.test(table), false);
    assert.match(table, /created_by INTEGER REFERENCES users\(user_code\) ?ON DELETE SET NULL/);
    assert.match(table, /used_by INTEGER REFERENCES users\(user_code\) ?ON DELETE SET NULL/);
    assert.match(table, /site_code BIGINT NOT NULL REFERENCES sites\(site_code\) ?ON DELETE CASCADE/);
    assert.match(table, /expires_at TIMESTAMPTZ NOT NULL/);
    assert.match(table, /used_at TIMESTAMPTZ/);
    assert.match(table, /CHECK\(\(used_at IS NULL\)=\(session_expires_at IS NULL\)\)/);
    // bir hesap en çok bir kodun kullanıcısıdır
    assert.ok(TRIAL_ACCESS_DDL.some((sql) => /UNIQUE INDEX IF NOT EXISTS uq_trial_access_codes_used_by ON trial_access_codes \(used_by\) WHERE used_by IS NOT NULL/.test(sql)));
  });

  it('ensure: tablo varsa HİÇ DDL gönderilmez; yoksa tüm ifadeler sırayla gönderilir', async () => {
    const sent = [];
    const makeClient = (present) => ({
      async query(sql) {
        sent.push(String(sql));
        if (/to_regclass/.test(sql)) return { rows: [{ n: present ? 1 : 0 }] };
        return { rows: [] };
      },
    });
    await ensureTrialAccessSchema(makeClient(true));
    assert.equal(sent.length, 1, 'yalnız katalog sorgusu');
    sent.length = 0;
    await ensureTrialAccessSchema(makeClient(false));
    assert.equal(sent.length, 1 + TRIAL_ACCESS_DDL.length);
    assert.deepEqual(sent.slice(1), [...TRIAL_ACCESS_DDL]);
  });

  it('db.js ensureDbSchema zincirinde çağrılır (sites ve users sonrası)', () => {
    assert.match(dbSource, /import \{ ensureTrialAccessSchema \} from '\.\/modules\/trial_access_schema\.js'/);
    const call = dbSource.indexOf('await ensureTrialAccessSchema(client)');
    assert.ok(call > 0);
    assert.ok(call > dbSource.indexOf('CREATE TABLE IF NOT EXISTS sites ('), 'sites tablosundan sonra');
    assert.ok(call > dbSource.indexOf('await ensureFinanceFundsSchema(client)'));
  });
});
