// Duyuru ve Bildirim (Faz 3a): migration 032 <-> db.js aynı DDL, ekleyici şema, sözleşmedeki tablo/kısıt/indeks ayrıntıları, sunucu bağlantısı
// ve kaynak koruma testleri (DB'siz).
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { DEFAULT_MIGRATIONS_DIR, blankSqlNoise, findUnsafeStatements, listMigrations } from '../scripts/migrate.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const readSrc = (relative) => readFileSync(path.join(here, '..', 'src', relative), 'utf8').replace(/\r\n/g, '\n');
const MIGRATION = readFileSync(path.join(DEFAULT_MIGRATIONS_DIR, '032_announcements.sql'), 'utf8').replace(/\r\n/g, '\n');
const DB_SOURCE = readSrc('db.js');

function normalizeSql(text) {
  return text
    .replace(/\/\*[\s\S]*?\*\//g, ' ')
    .replace(/--.*$/gm, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

describe('migration 032: duyuru ve bildirim', () => {
  it('032 var, 32. sırada (ardışık) ve çalıştırıcı için güvenli (üst düzey BEGIN/COMMIT yok)', () => {
    const list = listMigrations(DEFAULT_MIGRATIONS_DIR);
    const entry = list.find((m) => m.number === 32);
    assert.ok(entry, '032 numaralı migration yok');
    assert.equal(entry.file, '032_announcements.sql');
    assert.equal(list[31], entry);
    assert.deepEqual(findUnsafeStatements(MIGRATION), []);
  });

  it('db.js ensureDbSchema AYNI DDL\'i içerir (yorumlar ve boşluklar dışında birebir); 031\'den SONRA ve people_v1 aktarımından ÖNCE gelir', () => {
    const normalizedDb = normalizeSql(DB_SOURCE);
    const migration = normalizeSql(MIGRATION);
    assert.ok(migration.length > 1500);
    assert.ok(normalizedDb.includes(migration), 'migrations/032 ile db.js aynı DDL değil');
    const migration031 = normalizeSql(readFileSync(path.join(DEFAULT_MIGRATIONS_DIR, '031_people_and_apartments.sql'), 'utf8'));
    assert.ok(normalizedDb.indexOf(migration031) < normalizedDb.indexOf(migration));
    assert.ok(normalizedDb.indexOf(migration) < normalizedDb.indexOf('await runPeopleBackfill(client)'));
    // platform şablonunun İÇİNDE (QA "legacy/live" kesme noktaları 031 başlığından kestiği için 032 de kesilir)
    assert.ok(DB_SOURCE.indexOf('-- 032: DUYURU VE BILDIRIM') > DB_SOURCE.indexOf('-- 031: KISI VE DAIRE KAYITLARI'));
  });

  it('announcements: sözleşmedeki sütunlar, varsayılanlar ve FK davranışları', () => {
    const sql = normalizeSql(MIGRATION);
    const table = /CREATE TABLE IF NOT EXISTS announcements \(([\s\S]*?)\);/.exec(sql)?.[1];
    assert.ok(table);
    for (const column of [
      'id BIGSERIAL PRIMARY KEY',
      'site_code BIGINT NOT NULL REFERENCES sites\\(site_code\\) ON DELETE CASCADE',
      'title TEXT NOT NULL',
      'body TEXT NOT NULL',
      "importance TEXT NOT NULL DEFAULT 'normal'",
      "status TEXT NOT NULL DEFAULT 'draft'",
      "target_type TEXT NOT NULL DEFAULT 'site'",
      "target_block_ids BIGINT\\[\\] NOT NULL DEFAULT '\\{\\}'",
      "target_apartment_ids BIGINT\\[\\] NOT NULL DEFAULT '\\{\\}'",
      'send_email BOOLEAN NOT NULL DEFAULT FALSE',
      'publish_at TIMESTAMPTZ',
      'published_at TIMESTAMPTZ',
      'withdrawn_at TIMESTAMPTZ',
      'edited_at TIMESTAMPTZ',
      'edit_count INTEGER NOT NULL DEFAULT 0',
      'recipient_count INTEGER NOT NULL DEFAULT 0',
      'created_by INTEGER REFERENCES users\\(user_code\\) ON DELETE SET NULL',
      'created_at TIMESTAMPTZ NOT NULL DEFAULT NOW\\(\\)',
      'updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW\\(\\)',
    ]) {
      assert.match(table, new RegExp(column), column);
    }
  });

  it('announcements: CHECK kısıtları (önem, durum, hedef türü, başlık 1-120, metin 1-5000, zamanlanmışsa publish_at dolu)', () => {
    const sql = normalizeSql(MIGRATION);
    assert.match(sql, /CHECK \(importance IN \('normal', 'urgent'\)\)/);
    assert.match(sql, /CHECK \(status IN \('draft', 'scheduled', 'published', 'withdrawn'\)\)/);
    assert.match(sql, /CHECK \(target_type IN \('site', 'blocks', 'apartments'\)\)/);
    assert.match(sql, /CHECK \(char_length\(title\) BETWEEN 1 AND 120\)/);
    assert.match(sql, /CHECK \(char_length\(body\) BETWEEN 1 AND 5000\)/);
    assert.match(sql, /CHECK \(status <> 'scheduled' OR publish_at IS NOT NULL\)/);
  });

  it('announcements indeksleri: (site_code, status, published_at DESC, id DESC) ve (publish_at) WHERE scheduled', () => {
    const sql = normalizeSql(MIGRATION);
    assert.match(sql, /CREATE INDEX IF NOT EXISTS idx_announcements_site_status ON announcements \(site_code, status, published_at DESC, id DESC\)/);
    assert.match(sql, /CREATE INDEX IF NOT EXISTS idx_announcements_due ON announcements \(publish_at\) WHERE status = 'scheduled'/);
  });

  it('announcement_recipients: PK (duyuru, kişi), CASCADE FK\'ler, e-posta durumları, deneme sayacı, okundu; indeksler', () => {
    const sql = normalizeSql(MIGRATION);
    const table = /CREATE TABLE IF NOT EXISTS announcement_recipients \(([\s\S]*?)\);\s*CREATE INDEX/.exec(sql)?.[1];
    assert.ok(table);
    assert.match(table, /announcement_id BIGINT NOT NULL REFERENCES announcements\(id\) ON DELETE CASCADE/);
    assert.match(table, /person_id BIGINT NOT NULL REFERENCES site_people\(id\) ON DELETE CASCADE/);
    assert.match(table, /email TEXT,/);
    assert.match(table, /email_status TEXT NOT NULL DEFAULT 'none'/);
    assert.match(table, /email_attempts INTEGER NOT NULL DEFAULT 0/);
    assert.match(table, /read_at TIMESTAMPTZ,/);
    assert.match(table, /PRIMARY KEY \(announcement_id, person_id\)/);
    assert.match(table, /email_status IN \('none', 'pending', 'sent', 'failed', 'no_address', 'skipped_pref', 'capped', 'duplicate'\)/);
    assert.match(sql, /idx_announcement_recipients_person ON announcement_recipients \(person_id, announcement_id DESC\)/);
    assert.match(sql, /idx_announcement_recipients_unread ON announcement_recipients \(announcement_id\) WHERE read_at IS NULL/);
    assert.match(sql, /idx_announcement_recipients_pending ON announcement_recipients \(email_status\) WHERE email_status = 'pending'/);
  });

  it('notification_preferences: kullanıcı başına, CASCADE, e-posta/itme varsayılan açık', () => {
    const sql = normalizeSql(MIGRATION);
    const table = /CREATE TABLE IF NOT EXISTS notification_preferences \(([\s\S]*?)\);/.exec(sql)?.[1];
    assert.ok(table);
    assert.match(table, /user_code INTEGER PRIMARY KEY REFERENCES users\(user_code\) ON DELETE CASCADE/);
    assert.match(table, /email_announcements BOOLEAN NOT NULL DEFAULT TRUE/);
    assert.match(table, /push_announcements BOOLEAN NOT NULL DEFAULT TRUE/);
    assert.match(table, /updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW\(\)/);
  });

  it('ekleyici: silme/düşürme/veri yazma yok, mevcut tabloya ALTER yok; her CREATE IF NOT EXISTS ile', () => {
    const sql = normalizeSql(blankSqlNoise(MIGRATION));
    assert.equal(/DROP\s|TRUNCATE|DELETE\s+FROM|\bUPDATE\s+\w+\s+SET|\bINSERT\s+INTO|\bALTER\s+TABLE/i.test(sql), false);
    const full = normalizeSql(MIGRATION);
    assert.deepEqual(full.match(/CREATE\s+(UNIQUE\s+)?(TABLE|INDEX)\s+(?!IF NOT EXISTS)/gi) || [], []);
    assert.equal((full.match(/CREATE TABLE IF NOT EXISTS/g) || []).length, 3);
  });

  it('migration numaraları tekrarlanmaz', () => {
    const numbers = readdirSync(DEFAULT_MIGRATIONS_DIR).filter((f) => /^\d{3}_.+\.sql$/.test(f)).map((f) => f.slice(0, 3));
    assert.equal(new Set(numbers).size, numbers.length);
  });
});

describe('sunucu bağlantısı ve kaynak korumaları', () => {
  it('server.js announcementRouter\'ı kaydeder (peopleRouter\'dan sonra, SPA statik servisinden önce)', () => {
    const server = readSrc('server.js');
    assert.match(server, /import \{ announcementRouter \} from '\.\/modules\/announcement_routes\.js';/);
    const mount = server.indexOf('app.use(announcementRouter);');
    assert.ok(mount > server.indexOf('app.use(peopleRouter);'));
    assert.ok(mount < server.indexOf('webBuildPath, { maxAge'));
  });

  it('server.js zamanlayıcıyı şema hazır olduktan SONRA başlatır ve kapanışta, havuz kapanmadan ÖNCE durdurur', () => {
    const server = readSrc('server.js');
    assert.match(server, /import \{ startAnnouncementScheduler, stopAnnouncementScheduler \} from '\.\/modules\/announcement_scheduler\.js';/);
    assert.ok(server.indexOf('startAnnouncementScheduler();') > server.indexOf('await ensureDbSchema();'));
    assert.ok(server.indexOf('await stopAnnouncementScheduler();') > 0);
    assert.ok(server.indexOf('await stopAnnouncementScheduler();') < server.indexOf('await pool.end();'));
  });

  it('katalog: announcements çekirdek + available (hep açık); docs tablosu güncel', () => {
    const catalog = readSrc('modules/catalog.js');
    assert.match(catalog, /code: 'announcements',[\s\S]*?core: true,\s*status: MODULE_STATUS_AVAILABLE,/);
    const docs = readFileSync(path.join(here, '..', '..', 'docs', 'PLATFORM_MODUL_SISTEMI.md'), 'utf8');
    assert.match(docs, /\| `announcements` \| Duyuru ve Bildirim \| evet \| `available`/);
    assert.match(docs, /\| `people` \| Kişi ve Daire Kayıtları \| evet \| `available`/);
  });

  it('nodemailer\'a YALNIZ mailer.js erişir (duyuru modülleri e-postayı mailer üzerinden gönderir)', () => {
    for (const file of readdirSync(path.join(here, '..', 'src', 'modules')).filter((f) => f.startsWith('announcement_'))) {
      assert.doesNotMatch(readSrc(`modules/${file}`), /from 'nodemailer'/, file);
    }
  });

  it('log satırlarına e-posta adresi / alıcı yazılmaz (announcement_* modüllerindeki console çağrıları)', () => {
    for (const file of readdirSync(path.join(here, '..', 'src', 'modules')).filter((f) => f.startsWith('announcement_'))) {
      const source = readSrc(`modules/${file}`);
      for (const match of source.matchAll(/console\.(?:log|error|warn|info)\([^;]*\);/g)) {
        assert.doesNotMatch(match[0], /\.email\b|row\.to\b|recipient|\bto\b:/, `${file}: ${match[0]}`);
      }
    }
  });

  it('IDOR koruması (kaynak): announcement_service.js\'teki her announcements sorgusu site_code ile bağlıdır (yalnız sahibi olunan satırın kendi işlem içi güncellemesi hariç)', () => {
    const source = readSrc('modules/announcement_service.js');
    // Yorumlardaki geri tirnaklar elenir: gercek sorgular parametre ($N) ya da sablon ifadesi icerir.
    const sqls = [...source.matchAll(/`([^`]*)`/g)]
      .map((m) => m[1])
      .filter((sql) => /\b(FROM|UPDATE|DELETE FROM|INTO)\s+announcements\b/.test(sql) && /\$\d|\$\{/.test(sql));
    assert.ok(sqls.length >= 8, `beklenenden az sorgu: ${sqls.length}`);
    // liste sorgularinin kosulu listWhere() ile kurulur; site_code kosulu orada ilk maddedir
    assert.match(source, /const clauses = \['a\.site_code = \$1'\];/);
    for (const sql of sqls) {
      const flat = sql.replace(/\s+/g, ' ');
      const ownRowUpdate = /UPDATE announcements SET recipient_count = \$2, published_at = clock_timestamp\(\) WHERE id = \$1/.test(flat);
      const viaListWhere = flat.includes('${where.sql}');
      assert.ok(/site_code/.test(flat) || ownRowUpdate || viaListWhere, flat.slice(0, 140));
    }
  });
});
