// Site yöneticisi olma (site başvurusu): migration 033 <-> db.js aynı DDL, ekleyici şema, sözleşmedeki tablo / kısıt / indeks / tohum
// ayrıntıları ve kaynak koruma testleri (DB'siz). Sözleşme: docs/PLATFORM_SITE_BASVURUSU.md.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { DEFAULT_MIGRATIONS_DIR, findUnsafeStatements, listMigrations } from '../scripts/migrate.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const readSrc = (relative) => readFileSync(path.join(here, '..', 'src', relative), 'utf8').replace(/\r\n/g, '\n');
const MIGRATION = readFileSync(path.join(DEFAULT_MIGRATIONS_DIR, '033_site_applications.sql'), 'utf8').replace(/\r\n/g, '\n');
const DB_SOURCE = readSrc('db.js');

function normalizeSql(text) {
  return text
    .replace(/\/\*[\s\S]*?\*\//g, ' ')
    .replace(/--.*$/gm, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

const SQL = normalizeSql(MIGRATION);
const tableBody = (name) => new RegExp(`CREATE TABLE IF NOT EXISTS ${name} \\(([\\s\\S]*?)\\);`).exec(SQL)?.[1];

describe('migration 033: site başvurusu', () => {
  it('033 var, 33. sırada (ardışık) ve çalıştırıcı için güvenli (üst düzey BEGIN/COMMIT yok)', () => {
    const list = listMigrations(DEFAULT_MIGRATIONS_DIR);
    assert.ok(list.length >= 33, `en az 33 migration beklenir: ${list.length}`);
    const entry = list.find((m) => m.number === 33);
    assert.ok(entry, '033 numaralı migration yok');
    assert.equal(entry.file, '033_site_applications.sql');
    assert.equal(entry.version, '033_site_applications');
    assert.equal(list[32], entry);
    assert.deepEqual(findUnsafeStatements(MIGRATION), []);
  });

  it('db.js ensureDbSchema AYNI DDL\'i içerir (yorumlar ve boşluklar dışında birebir); 032\'den SONRA ve people_v1 aktarımından ÖNCE gelir', () => {
    const normalizedDb = normalizeSql(DB_SOURCE);
    assert.ok(SQL.length > 2500);
    assert.ok(normalizedDb.includes(SQL), 'migrations/033 ile db.js aynı DDL değil');
    const migration032 = normalizeSql(readFileSync(path.join(DEFAULT_MIGRATIONS_DIR, '032_announcements.sql'), 'utf8'));
    assert.ok(normalizedDb.indexOf(migration032) < normalizedDb.indexOf(SQL));
    assert.ok(normalizedDb.indexOf(SQL) < normalizedDb.indexOf('await runPeopleBackfill(client)'));
    // platform şablonunun İÇİNDE (QA "legacy/live" kesme noktaları 031 başlığından kestiği için 033 de kesilir)
    assert.ok(DB_SOURCE.indexOf('-- 033: SITE YONETICISI OLMA') > DB_SOURCE.indexOf('-- 032: DUYURU VE BILDIRIM'));
    assert.ok(DB_SOURCE.indexOf('-- 033: SITE YONETICISI OLMA') < DB_SOURCE.indexOf('await runPeopleBackfill(client)'));
  });

  it('subscription_plans: sözleşmedeki sütunlar, fiyat / dönem kısıtları ve idempotent tohum (manual_approval açık, standard kapalı, fiyatsız)', () => {
    const table = tableBody('subscription_plans');
    assert.ok(table);
    for (const column of [
      'code TEXT PRIMARY KEY',
      'name TEXT NOT NULL',
      'description TEXT',
      'is_active BOOLEAN NOT NULL DEFAULT FALSE',
      'price_minor INTEGER',
      "currency TEXT NOT NULL DEFAULT 'TRY'",
      'billing_period TEXT',
      'created_at TIMESTAMPTZ NOT NULL DEFAULT NOW\\(\\)',
    ]) {
      assert.match(table, new RegExp(column), column);
    }
    assert.match(table, /CHECK \(price_minor IS NULL OR price_minor >= 0\)/);
    assert.match(table, /CHECK \(billing_period IS NULL OR billing_period IN \('monthly', 'yearly'\)\)/);
    assert.match(SQL, /INSERT INTO subscription_plans \(code, name, description, is_active\) VALUES \('manual_approval', 'Elle Onaylı', '[^']+', TRUE\), \('standard', 'Standart', 'Yakında…', FALSE\) ON CONFLICT \(code\) DO NOTHING/);
    assert.equal(/price_minor\)\s*VALUES/.test(SQL), false, 'tohum fiyat içermez');
  });

  it('site_subscriptions: site başına tek satır (UNIQUE + CASCADE FK), plan FK, durum / kaynak CHECK, application_id FK DEĞİL', () => {
    const table = tableBody('site_subscriptions');
    assert.ok(table);
    for (const column of [
      'id BIGSERIAL PRIMARY KEY',
      'site_code BIGINT NOT NULL UNIQUE REFERENCES sites\\(site_code\\) ON DELETE CASCADE',
      'plan_code TEXT NOT NULL REFERENCES subscription_plans\\(code\\)',
      'status TEXT NOT NULL',
      'source TEXT NOT NULL',
      'application_id BIGINT,',
      'started_at TIMESTAMPTZ NOT NULL DEFAULT NOW\\(\\)',
      'expires_at TIMESTAMPTZ,',
      'created_at TIMESTAMPTZ NOT NULL DEFAULT NOW\\(\\)',
      'updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW\\(\\)',
    ]) {
      assert.match(table, new RegExp(column), column);
    }
    assert.match(table, /CHECK \(status IN \('active', 'trial', 'past_due', 'cancelled', 'expired'\)\)/);
    assert.match(table, /CHECK \(source IN \('manual_approval', 'payment', 'admin'\)\)/);
    assert.equal(/application_id BIGINT[^,]*REFERENCES/.test(table), false, 'application_id site_applications\'a FK olmamalı (döngüsel bağımlılık yok)');
  });

  it('platform_settings: anahtar / JSONB değer / updated_by SET NULL; tohum site_onboarding = approval (üzerine YAZMAZ)', () => {
    const table = tableBody('platform_settings');
    assert.ok(table);
    assert.match(table, /key TEXT PRIMARY KEY/);
    assert.match(table, /value JSONB NOT NULL/);
    assert.match(table, /updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW\(\)/);
    assert.match(table, /updated_by INTEGER REFERENCES users\(user_code\) ON DELETE SET NULL/);
    assert.match(SQL, /INSERT INTO platform_settings \(key, value\) VALUES \('site_onboarding', '\{"mode":"approval"\}'::jsonb\) ON CONFLICT \(key\) DO NOTHING/);
  });

  it('site_applications: sözleşmedeki sütunlar, varsayılanlar ve FK davranışları', () => {
    const table = tableBody('site_applications');
    assert.ok(table);
    for (const column of [
      'id BIGSERIAL PRIMARY KEY',
      'applicant_user_code INTEGER REFERENCES users\\(user_code\\) ON DELETE SET NULL',
      "status TEXT NOT NULL DEFAULT 'pending'",
      'site_name TEXT NOT NULL',
      'city TEXT,',
      'district TEXT,',
      'address TEXT,',
      "management_type TEXT NOT NULL DEFAULT 'apartment_site'",
      'blocks JSONB NOT NULL',
      'doors JSONB NOT NULL',
      'block_count INTEGER NOT NULL',
      'apartment_count INTEGER NOT NULL',
      'door_count INTEGER NOT NULL',
      'device_uid TEXT,',
      'note TEXT,',
      'plan_code TEXT REFERENCES subscription_plans\\(code\\)',
      "payment_status TEXT NOT NULL DEFAULT 'not_required'",
      'payment_reference TEXT,',
      'decision_source TEXT,',
      'decided_by INTEGER REFERENCES users\\(user_code\\) ON DELETE SET NULL',
      'decided_at TIMESTAMPTZ,',
      'decision_note TEXT,',
      'site_code BIGINT REFERENCES sites\\(site_code\\) ON DELETE SET NULL',
      'created_at TIMESTAMPTZ NOT NULL DEFAULT NOW\\(\\)',
      'updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW\\(\\)',
    ]) {
      assert.match(table, new RegExp(column), column);
    }
    // cihaz başvuruda KİLİTLENMEZ: devices'a yabancı anahtar yok
    assert.equal(/REFERENCES devices/.test(table), false);
  });

  it('site_applications: CHECK kısıtları (durum, ödeme durumu, karar kaynağı)', () => {
    assert.match(SQL, /CHECK \(status IN \('pending', 'approved', 'rejected', 'cancelled'\)\)/);
    assert.match(SQL, /CHECK \(payment_status IN \('not_required', 'pending', 'paid', 'failed', 'refunded'\)\)/);
    assert.match(SQL, /CHECK \(decision_source IS NULL OR decision_source IN \('super_user', 'payment', 'system'\)\)/);
  });

  it('site_applications indeksleri: kişi başına tek BEKLEYEN başvuru (kısmi tekil), (durum, tarih DESC), (başvuran, tarih DESC)', () => {
    assert.match(SQL, /CREATE UNIQUE INDEX IF NOT EXISTS uq_site_applications_pending ON site_applications \(applicant_user_code\) WHERE status = 'pending'/);
    assert.match(SQL, /CREATE INDEX IF NOT EXISTS idx_site_applications_status_created ON site_applications \(status, created_at DESC\)/);
    assert.match(SQL, /CREATE INDEX IF NOT EXISTS idx_site_applications_applicant_created ON site_applications \(applicant_user_code, created_at DESC\)/);
  });

  it('ekleyici ve idempotent: mevcut tabloya dokunmaz; abonelik / başvuru satırı YAZMAZ (backfill yok); yalnız iki tohum', () => {
    assert.equal(/DROP\s|TRUNCATE|DELETE\s+FROM|\bUPDATE\s+\w+\s+SET|ALTER\s+TABLE/i.test(SQL), false);
    assert.equal(/INSERT INTO site_subscriptions|INSERT INTO site_applications/i.test(SQL), false, 'mevcut sitelere abonelik satırı eklenmez');
    const inserts = SQL.match(/INSERT INTO \w+/g) ?? [];
    assert.deepEqual(inserts, ['INSERT INTO subscription_plans', 'INSERT INTO platform_settings']);
    // her INSERT çakışmada hiçbir şey yapmaz (yeniden çalıştırma yönetici değişikliğini ezmez)
    assert.equal((SQL.match(/ON CONFLICT \([a-z_]+\) DO NOTHING/g) ?? []).length, 2);
    for (const create of SQL.match(/CREATE (UNIQUE )?(TABLE|INDEX)[^(]*/g) ?? []) {
      assert.match(create, /IF NOT EXISTS/, create);
    }
  });

  it('başlıkta db.js ile aynı DDL olduğu ve sözleşme belgesi belirtilir', () => {
    const header = MIGRATION.split('\n').slice(0, 6).join('\n');
    assert.match(header, /db\.js/);
    assert.match(header, /PLATFORM_SITE_BASVURUSU\.md/);
    assert.match(header, /ekleyici/i);
  });
});

describe('site başvurusu: kaynak koruma', () => {
  const sources = {
    service: readSrc('modules/site_application_service.js'),
    routes: readSrc('modules/site_application_routes.js'),
    common: readSrc('modules/site_application_common.js'),
    core: readSrc('services/site_setup_core.js'),
  };

  it('görünmez / yön karakteri içermez (kaynakta Unicode kaçışı da yok)', () => {
    // Kod noktalari SAYIYLA denetlenir: kaynakta \u kacisi yazilirsa arac zinciri onu gercek gorunmez karaktere cevirebilir.
    const isHidden = (code) =>
      (code < 32 && code !== 9 && code !== 10 && code !== 13) ||
      code === 127 ||
      code === 173 ||
      (code >= 8203 && code <= 8207) ||
      (code >= 8232 && code <= 8238) ||
      (code >= 8288 && code <= 8303) ||
      code === 65279;
    const hasHidden = (text) => Array.from(text).some((ch) => isHidden(ch.codePointAt(0)));
    for (const [name, text] of Object.entries(sources)) {
      assert.equal(hasHidden(text), false, name);
      assert.equal(/\\u[0-9a-fA-F]{4}/.test(text), false, `${name}: Unicode kacis dizisi`);
    }
    assert.equal(hasHidden(MIGRATION), false, 'migration');
  });

  it('audit details not / gerekçe / e-posta metni TAŞIMAZ; e-posta adresi log\'a yazılmaz', () => {
    const detailBlocks = [...sources.service.matchAll(/details: \{([^}]*)\}/g)].map((m) => m[1]);
    assert.ok(detailBlocks.length >= 5, 'created, cancelled, approved, rejected, platform_settings');
    for (const block of detailBlocks) {
      assert.equal(/\b(note|reason|email|decision_note|phone)\b\s*[,:}]|\b(note|reason|email)\b$/.test(block), false, block);
    }
    for (const call of sources.service.matchAll(/console\.error\(([^)]*)\)/g)) {
      assert.equal(/message|email|\.to\b/.test(call[1]), false, `log ifadesi: ${call[1]}`);
    }
  });

  it('yetkisiz alanlar başvuran görünümüne SELECT edilmez (decision_source / decided_by yalnız süper görünümde)', () => {
    const applicantColumns = /const APPLICANT_COLUMNS = `([\s\S]*?)`;/.exec(sources.service)?.[1] ?? '';
    assert.ok(applicantColumns.includes('a.id'));
    assert.equal(/decision_source|decided_by|payment_reference|applicant_name|applicant_email|phone/.test(applicantColumns), false);
    const withoutComments = (text) => text.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '');
    for (const text of [sources.common, sources.service, sources.routes]) {
      assert.equal(/payment_reference/.test(withoutComments(text)), false, 'payment_reference hiçbir yanıtta / sorguda yok');
    }
  });

  it('server.js yeni yönlendiriciyi kaydeder (moduleRequestRouter\'dan sonra)', () => {
    const server = readSrc('server.js');
    assert.match(server, /import \{ siteApplicationRouter \} from '\.\/modules\/site_application_routes\.js';/);
    assert.ok(server.indexOf('app.use(siteApplicationRouter);') > server.indexOf('app.use(moduleRequestRouter);'));
    assert.ok(server.indexOf('app.use(siteApplicationRouter);') < server.indexOf('app.use(notFoundHandler);'));
  });
});
