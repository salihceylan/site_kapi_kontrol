// Duyuru gizleme / yumuşak silme (057) şeması (DB'siz): migration <-> announcement_hide_schema.js aynı DDL (aynı sıra), ekleyici / idempotent,
// db.js'te dev ensureDbSchema bloğu dışında çağrılır, katalog kontrolüyle yalnız eksikler çalışır. Gerçek PG: scripts/qa_platform_pg.mjs.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { DEFAULT_MIGRATIONS_DIR, findUnsafeStatements, listMigrations } from '../scripts/migrate.js';
import {
  ANNOUNCEMENT_HIDE_DDL,
  ANNOUNCEMENT_HIDE_DDL_ORDER,
  announcementHideTuning,
  ensureAnnouncementHideSchema,
} from '../src/modules/announcement_hide_schema.js';

announcementHideTuning.retryDelayMs = 1;
const here = path.dirname(fileURLToPath(import.meta.url));
const MIGRATION = readFileSync(path.join(DEFAULT_MIGRATIONS_DIR, '057_announcement_hide_delete.sql'), 'utf8').replace(/\r\n/g, '\n');
const DB_SOURCE = readFileSync(path.join(here, '..', 'src', 'db.js'), 'utf8').replace(/\r\n/g, '\n');
const norm = (text) => text.replace(/--.*$/gm, ' ').replace(/\s+/g, ' ').trim();

function fakeClient(state, failures = []) {
  const sent = [];
  return {
    sent,
    async query(sql) {
      const text = norm(sql);
      sent.push(text);
      if (/^SELECT /.test(text)) return { rows: [state] };
      const failure = /^(ALTER|DO)/.test(text) ? failures.shift() : undefined;
      if (failure) throw Object.assign(new Error('x'), { code: failure });
      return { rows: [], rowCount: 0 };
    },
  };
}

describe('migration 057: duyuru gizleme ve yumuşak silme', () => {
  it('057 var, güvenli (üst düzey BEGIN/COMMIT yok), numara yinelenmez', () => {
    const list = listMigrations(DEFAULT_MIGRATIONS_DIR);
    assert.equal(list.filter((m) => m.number === 57).length, 1);
    assert.equal(list.find((m) => m.number === 57).file, '057_announcement_hide_delete.sql');
    assert.deepEqual(findUnsafeStatements(MIGRATION), []);
  });

  it('migration metni DDL ile birebir aynı ifadeler, aynı sırada; ekleyici (DROP / DELETE yok)', () => {
    const body = norm(MIGRATION);
    let at = -1;
    for (const name of ANNOUNCEMENT_HIDE_DDL_ORDER) {
      const idx = body.indexOf(norm(ANNOUNCEMENT_HIDE_DDL[name]));
      assert.ok(idx > at, `${name} migration'da yok ya da sırası farklı`);
      at = idx;
    }
    assert.doesNotMatch(body, /\b(DROP|DELETE|TRUNCATE)\b/i);
    assert.match(body, /ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ/);
    assert.match(body, /ADD COLUMN IF NOT EXISTS hidden_at TIMESTAMPTZ/);
    assert.match(body, /CHECK \(deleted_at IS NULL OR status = 'withdrawn'\) NOT VALID/);
  });

  it('db.js ensure çağrısı dev ensureDbSchema bloğundan SONRA; ALTER dev blokta yok', () => {
    assert.ok(DB_SOURCE.includes('await ensureAnnouncementHideSchema(client);'));
    assert.ok(DB_SOURCE.indexOf('await ensureAnnouncementHideSchema(client);') > DB_SOURCE.indexOf('await ensurePlatformRulesSchema(client);'));
    assert.equal(/ADD COLUMN IF NOT EXISTS hidden_at/.test(DB_SOURCE), false);
  });

  it('ensure: her şey varsa tek katalog sorgusu (ALTER yok, kilit yok)', async () => {
    const client = fakeClient({ has_tables: true, has_deleted: true, has_hidden: true, has_check: true });
    await ensureAnnouncementHideSchema(client);
    assert.equal(client.sent.length, 1);
  });

  it('ensure: eksikse yalnız eksikleri sırayla, lock_timeout içinde çalıştırır; 40P01 yeniden denenir', async () => {
    const client = fakeClient({ has_tables: true, has_deleted: false, has_hidden: true, has_check: false }, ['40P01']);
    await ensureAnnouncementHideSchema(client);
    const ddl = client.sent.filter((t) => /^(ALTER|DO)/.test(t));
    assert.equal(ddl.length, 3); // deleted_at (1 başarısız + 1 başarılı) + check
    assert.match(ddl[0], /deleted_at/);
    assert.match(ddl[2], /chk_announcements_deleted_withdrawn/);
    assert.equal(client.sent.some((t) => /^ALTER/.test(t) && /hidden_at/.test(t)), false);
    assert.ok(client.sent.includes("SET lock_timeout = '2s'"));
    assert.ok(client.sent.includes('RESET lock_timeout'));
  });

  it('ensure: tablolar yoksa (boş DB) hiçbir şey yapmaz', async () => {
    const client = fakeClient({ has_tables: false });
    await ensureAnnouncementHideSchema(client);
    assert.equal(client.sent.length, 1);
  });
});
