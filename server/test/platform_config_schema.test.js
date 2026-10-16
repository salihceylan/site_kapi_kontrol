// Platform hizmetleri (satışa hazırlık) şeması ve kaynak korumaları (DB'siz): migration 035 <-> db.js aynı DDL, ekleyici / idempotent şema,
// tablo / kısıt / indeks ayrıntıları ve bağlama noktaları (server.js, kayıt akışı, site başvurusu). Sözleşme: docs/PLATFORM_SATISA_HAZIRLIK.md.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { DEFAULT_MIGRATIONS_DIR, findUnsafeStatements, listMigrations } from '../scripts/migrate.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const readRelative = (...parts) => readFileSync(path.join(here, '..', ...parts), 'utf8').replace(/\r\n/g, '\n');
const MIGRATION = readFileSync(path.join(DEFAULT_MIGRATIONS_DIR, '035_platform_services.sql'), 'utf8').replace(/\r\n/g, '\n');
const DB_SOURCE = readRelative('src', 'db.js');

function normalizeSql(text) {
  return text
    .replace(/\/\*[\s\S]*?\*\//g, ' ')
    .replace(/--.*$/gm, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

const SQL = normalizeSql(MIGRATION);
const tableBody = (name) => new RegExp(`CREATE TABLE IF NOT EXISTS ${name} \\(([\\s\\S]*?)\\);`).exec(SQL)?.[1];

describe('migration 035: platform hizmetleri', () => {
  it('035 var, ardışık numara ve çalıştırıcı için güvenli (üst düzey BEGIN/COMMIT, CONCURRENTLY yok)', () => {
    const list = listMigrations(DEFAULT_MIGRATIONS_DIR);
    const entry = list.find((m) => m.number === 35);
    assert.ok(entry, '035 numaralı migration yok');
    assert.equal(entry.file, '035_platform_services.sql');
    assert.equal(entry.version, '035_platform_services');
    assert.deepEqual(findUnsafeStatements(MIGRATION), []);
    assert.equal(list.filter((m) => m.number === 35).length, 1, 'numara tekrarlanmaz');
  });

  it('db.js ensureDbSchema AYNI DDL\'i içerir (yorumlar ve boşluklar dışında birebir); 034\'ten SONRA ve people_v1 aktarımından ÖNCE gelir', () => {
    const normalizedDb = normalizeSql(DB_SOURCE);
    assert.ok(SQL.length > 1500);
    // Migration'daki ALTER dev ensureDbSchema bloğunda DEĞİL, blok sonrası katalog kontrollü yardımcıdadır (açılış deadlock'u: bkz. aşağıdaki test);
    // geri kalanı (CREATE TABLE / INDEX) dev blokta birebir bulunur.
    const alterAt = SQL.indexOf('ALTER TABLE pending_registrations');
    assert.ok(alterAt > 0);
    const blockPart = SQL.slice(0, alterAt).trim();
    assert.ok(blockPart.endsWith(');') && blockPart.length > 1500);
    assert.ok(normalizedDb.includes(blockPart), 'migrations/035 ile db.js aynı DDL değil');
    const migration034 = normalizeSql(readFileSync(path.join(DEFAULT_MIGRATIONS_DIR, '034_finance.sql'), 'utf8'));
    assert.ok(normalizedDb.indexOf(migration034) < normalizedDb.indexOf(blockPart));
    assert.ok(normalizedDb.indexOf(blockPart) < normalizedDb.indexOf('await runPeopleBackfill(client)'));
    // platform şablonunun İÇİNDE (QA "legacy/live" kesme noktaları 031 başlığından kestiği için 035 de kesilir)
    assert.ok(DB_SOURCE.indexOf('-- 035: PLATFORM HIZMETLERI') > DB_SOURCE.indexOf('-- 034: AIDAT VE FINANS'));
    assert.ok(DB_SOURCE.indexOf('-- 035: PLATFORM HIZMETLERI') < DB_SOURCE.indexOf('await runPeopleBackfill(client)'));
  });

  it('user_consents: sütunlar, kullanıcıya FK (CASCADE), (kullanıcı, belge, sürüm) tekil, belge / sürüm / kaynak CHECK', () => {
    const table = tableBody('user_consents');
    assert.ok(table);
    for (const column of [
      'id BIGSERIAL PRIMARY KEY',
      'user_code INTEGER NOT NULL REFERENCES users\\(user_code\\) ON DELETE CASCADE',
      'document_id TEXT NOT NULL',
      'version TEXT NOT NULL',
      'accepted_at TIMESTAMPTZ NOT NULL DEFAULT NOW\\(\\)',
      "source TEXT NOT NULL DEFAULT 'in_app'",
    ]) {
      assert.match(table, new RegExp(column), column);
    }
    assert.match(table, /CONSTRAINT uq_user_consents_user_document_version UNIQUE \(user_code, document_id, version\)/);
    assert.match(table, /CHECK \(document_id ~ '\^\[a-z\]\[a-z0-9_\]\{1,39\}\$'\)/);
    assert.match(table, /CHECK \(char_length\(version\) BETWEEN 1 AND 40\)/);
    assert.match(table, /CHECK \(source ~ '\^\[a-z\]\[a-z_\]\{1,39\}\$'\)/);
  });

  it('client_error_reports: sözleşmedeki sütunlar; parmak izi tekil (64 hex); kullanıcı / IP / cihaz sütunu YOK; boyut CHECK\'leri', () => {
    const table = tableBody('client_error_reports');
    assert.ok(table);
    for (const column of [
      'id BIGSERIAL PRIMARY KEY',
      'fingerprint TEXT NOT NULL',
      'error_type TEXT NOT NULL',
      'message TEXT NOT NULL',
      'app_version TEXT NOT NULL',
      'build TEXT,',
      'platform TEXT NOT NULL',
      'os_version TEXT,',
      'route TEXT,',
      'fatal BOOLEAN NOT NULL DEFAULT FALSE',
      'count INTEGER NOT NULL DEFAULT 1',
      'first_seen TIMESTAMPTZ NOT NULL DEFAULT NOW\\(\\)',
      'last_seen TIMESTAMPTZ NOT NULL DEFAULT NOW\\(\\)',
      'sample_stack TEXT,',
    ]) {
      assert.match(table, new RegExp(column), column);
    }
    assert.match(table, /CONSTRAINT uq_client_error_reports_fingerprint UNIQUE \(fingerprint\)/);
    assert.match(table, /CHECK \(char_length\(fingerprint\) = 64\)/);
    assert.match(table, /CHECK \(platform IN \('android', 'ios', 'web', 'other'\)\)/);
    assert.match(table, /CHECK \(count >= 1\)/);
    assert.match(table, /char_length\(error_type\) <= 100 AND char_length\(message\) <= 500 AND \(sample_stack IS NULL OR char_length\(sample_stack\) <= 8000\)/);
    assert.equal(/user_code|user_id|install|device|\bip\b|email|phone/i.test(table), false, 'kişisel tanımlayıcı sütun yok');
    assert.equal(/REFERENCES/.test(table), false, 'başka tabloya bağ yok (kullanıcı silinince etkilenmez)');
  });

  it('client_error_reports indeksleri: (last_seen DESC, id DESC) listeleme, (first_seen) 90 gün silme', () => {
    assert.match(SQL, /CREATE INDEX IF NOT EXISTS idx_client_error_reports_last_seen ON client_error_reports \(last_seen DESC, id DESC\)/);
    assert.match(SQL, /CREATE INDEX IF NOT EXISTS idx_client_error_reports_first_seen ON client_error_reports \(first_seen\)/);
  });

  it('bekleyen kayıt: accepted_documents JSONB (yalnız dizi) — ALTER yalnız bu tek ifade; ADD COLUMN IF NOT EXISTS, varsayılan yok', () => {
    assert.deepEqual(SQL.match(/ALTER\s+TABLE[^;]*/gi), [
      "ALTER TABLE pending_registrations ADD COLUMN IF NOT EXISTS accepted_documents JSONB CHECK (accepted_documents IS NULL OR jsonb_typeof(accepted_documents) = 'array')",
    ]);
    assert.equal(/accepted_documents JSONB[^;]*DEFAULT/i.test(SQL), false);
    const earlier = listMigrations(DEFAULT_MIGRATIONS_DIR).filter((m) => m.number < 35).map((m) => m.sql).join('\n');
    assert.match(earlier, /CREATE TABLE IF NOT EXISTS pending_registrations\b/, 'ALTER edilen tablo daha önceki migration\'larda oluşur');
  });

  it('AÇILIŞ DEADLOCK\'U (R2 F-1): pending_registrations ALTER\'ı dev ensureDbSchema bloğunda DEĞİL; blok SONRASI, katalog kontrollü, ayrı otomatik onaylı ifade; migration ile aynı ifade', () => {
    const occurrences = DB_SOURCE.split('ALTER TABLE pending_registrations').length - 1;
    assert.equal(occurrences, 1, 'db.js\'te yalnız yardımcı sabitinde geçer (dev blokta yok)');
    const helper = /export const PENDING_CONSENTS_COLUMN_DDL = `([\s\S]*?)`;/.exec(DB_SOURCE)?.[1];
    assert.ok(helper);
    assert.equal(normalizeSql(helper), SQL.slice(SQL.indexOf('ALTER TABLE pending_registrations')).replace(/;\s*$/, ''), 'migration ve db.js ALTER ifadesi aynı');
    const fn = /async function ensurePendingConsentsColumn\(client\) \{([\s\S]*?)\n\}\n/.exec(DB_SOURCE)?.[1];
    assert.ok(fn);
    assert.match(fn, /pg_attribute/);
    assert.match(fn, /to_regclass\('public\.pending_registrations'\)/);
    assert.match(fn, /NOT attisdropped/);
    assert.match(fn, /if \(found\.rows\[0\]\?\.present !== true\) \{\s*await client\.query\(PENDING_CONSENTS_COLUMN_DDL\);/);
    const call = DB_SOURCE.indexOf('await ensurePendingConsentsColumn(client);');
    const blockEnd = DB_SOURCE.lastIndexOf('`);', DB_SOURCE.indexOf('await runPeopleBackfill(client)'));
    assert.ok(call > blockEnd && call < DB_SOURCE.indexOf('await runPeopleBackfill(client)'), 'dev bloktan SONRA, people_v1 aktarımından önce');
    // dev blok içinde bu tablo için ağır kilitli başka ifade yok
    const block = DB_SOURCE.slice(DB_SOURCE.indexOf('-- 035: PLATFORM HIZMETLERI'), DB_SOURCE.indexOf('-- 036:'));
    assert.equal(/ALTER\s+TABLE/i.test(block), false, '035 bölümü dev blokta ALTER içermez');
  });

  it('ekleyici ve idempotent: mevcut satırlara dokunmaz, veri yazmaz, yeni platform_settings anahtarı tohumlamaz', () => {
    assert.equal(/DROP\s|TRUNCATE|DELETE\s+FROM|\bUPDATE\s+\w+\s+SET|INSERT\s+INTO/i.test(SQL), false);
    for (const create of SQL.match(/CREATE (UNIQUE )?(TABLE|INDEX)[^(]*/g) ?? []) {
      assert.match(create, /IF NOT EXISTS/, create);
    }
    assert.equal((SQL.match(/CREATE TABLE/g) ?? []).length, 2);
  });

  it('başlıkta db.js ile aynı DDL olduğu ve sözleşme belgesi belirtilir', () => {
    const header = MIGRATION.split('\n').slice(0, 5).join('\n');
    assert.match(header, /db\.js/);
    assert.match(header, /PLATFORM_SATISA_HAZIRLIK\.md/);
    assert.match(header, /ekleyici/i);
  });
});

describe('bağlama noktaları (kaynak koruma)', () => {
  const server = readRelative('src', 'server.js');
  const rules = readRelative('src', 'services', 'membership_rules.js');
  const membership = readRelative('src', 'services', 'membership_service.js');
  const appService = readRelative('src', 'modules', 'site_application_service.js');
  const appRoutes = readRelative('src', 'modules', 'site_application_routes.js');
  const authRoutes = readRelative('src', 'routes', 'auth_routes.js');

  it('server.js: hizmet yönlendiricisi SPA yedek yolundan ÖNCE; hata raporu ayrıştırıcısı genel 1 MB ayrıştırıcıdan ÖNCE; silme zamanlayıcısı açılışta başlar, kapanışta durur', () => {
    const iParser = server.indexOf("app.post('/public/client-errors', clientErrorBodyParser)");
    const iGeneral = server.indexOf("app.use(express.json({ limit: '1mb' }))");
    assert.ok(iParser > 0 && iGeneral > 0 && iParser < iGeneral);
    const iMount = server.indexOf('app.use(platformServicesRouter)');
    const iFinance = server.indexOf('app.use(financeRouter)');
    const iSpa = server.indexOf('if (fs.existsSync(webBuildPath))');
    assert.ok(iFinance > 0 && iMount > iFinance && iMount < iSpa, '/legal/:id tarayıcıda HTML ister: SPA yedek yolundan önce bağlanmalı');
    assert.ok(server.indexOf('startClientErrorPurge();') > server.indexOf('startAnnouncementScheduler();'));
    assert.ok(server.indexOf('await stopClientErrorPurge();') > server.indexOf('await stopAnnouncementScheduler();'));
  });

  it('bekleyen kayıt: upsert accepted_documents ($5) yazar ve yeniler; alma onu geri döndürür', () => {
    assert.match(rules, /INSERT INTO pending_registrations \(email, full_name, password_hash, accepted_documents\)\s+SELECT \$1::text, \$2::text, \$3::text, \$5::jsonb/);
    assert.match(rules, /accepted_documents = EXCLUDED\.accepted_documents/);
    assert.match(rules, /RETURNING full_name, password_hash, accepted_documents/);
  });

  it('hesap açılışı: onaylar users INSERT\'inden SONRA, AYNI işlemde (COMMIT\'ten önce, aynı client) yazılır', () => {
    const start = membership.indexOf('export async function verifyIndividualEmailCode');
    const end = membership.indexOf('export async function resendIndividualVerificationCode');
    const body = membership.slice(start, end);
    const iInsertUser = body.indexOf("INSERT INTO users (full_name, email, role, is_active, email_verified, approval_status, password_hash)");
    const iRecord = body.indexOf("await recordConsents(client, userRes.rows[0].user_code, sanitizeStoredConsents(pending.rows[0].accepted_documents), 'register')");
    const iCommit = body.lastIndexOf("await client.query('COMMIT')");
    assert.ok(iInsertUser > 0 && iRecord > iInsertUser && iCommit > iRecord);
    assert.equal(body.includes('pool.query'), false, 'doğrulama işlemi yalnız TX istemcisini kullanır');
  });

  it('kayıt: /auth/register-individual onayları çözer (zorunluluk) ve hizmete geçirir; PlatformError gövdesi (missing) korunur', () => {
    const start = authRoutes.indexOf("authRouter.post('/auth/register-individual'");
    const end = authRoutes.indexOf("authRouter.post('/auth/verify-code'");
    const handler = authRoutes.slice(start, end);
    assert.match(handler, /accepted_documents/);
    assert.match(handler, /resolveAcceptedDocuments\(\{ raw: accepted_documents, context: 'register' \}\)/);
    assert.match(handler, /acceptedDocuments: consents\.records/);
    assert.match(handler, /isPlatformError\(error\)[\s\S]*\.\.\.\(error\.extra \?\? \{\}\)/);
    assert.ok(handler.indexOf('resolveAcceptedDocuments') < handler.indexOf('registerIndividualUser('), 'zorunluluk denetimi kayıt işleminden önce');
    // kapalı (410) uçlar onay kabul etmez: gövdeleri hiç okunmaz
    assert.match(authRoutes, /authRouter\.post\('\/auth\/register', async \(req, res\) => \{\s*return res\.status\(410\)/);
    assert.match(authRoutes, /authRouter\.post\('\/auth\/site-manager\/register', async \(req, res\) => \{\s*return res\.status\(410\)/);
  });

  it('site başvurusu: onay denetimi INSERT\'ten önce, yazım COMMIT\'ten önce ve aynı işlemde; rota kancayı verir', () => {
    const start = appService.indexOf('export async function createSiteApplication');
    const end = appService.indexOf('export async function listMyApplications') > 0 ? appService.indexOf('/**\n * GET /membership/site-applications/mine') : appService.length;
    const body = appService.slice(start, end > start ? end : appService.length);
    const iCheck = body.indexOf('consents.check(client, source.accepted_documents)');
    const iInsert = body.indexOf('INSERT INTO site_applications (');
    const iRecord = body.indexOf('consents.record(client, userCode, consentPlan)');
    const iCommit = body.indexOf("await client.query('COMMIT')");
    assert.ok(iCheck > 0 && iInsert > iCheck && iRecord > iInsert && iCommit > iRecord);
    assert.match(appRoutes, /createSiteApplication\(\{ actor: req\.authUser, body: bodyOf\(req\), consents: siteApplicationConsents \}\)/);
  });
});

describe('kaynak hijyeni', () => {
  const files = [
    ['src', 'modules', 'legal_documents.js'],
    ['src', 'modules', 'legal_consent_service.js'],
    ['src', 'modules', 'legal_routes.js'],
    ['src', 'modules', 'app_config_routes.js'],
    ['src', 'modules', 'platform_config_service.js'],
    ['src', 'modules', 'platform_config_routes.js'],
    ['src', 'modules', 'client_error_service.js'],
    ['src', 'modules', 'client_error_routes.js'],
    ['src', 'modules', 'client_error_purge.js'],
    ['migrations', '035_platform_services.sql'],
    ['test', 'legal_documents.test.js'],
    ['test', 'legal_consent_service.test.js'],
    ['test', 'legal_routes.test.js'],
    ['test', 'legal_consent_registration.test.js'],
    ['test', 'legal_real_documents.test.js'],
    ['test', 'app_config_routes.test.js'],
    ['test', 'platform_config_service.test.js'],
    ['test', 'platform_config_routes.test.js'],
    ['test', 'client_error_service.test.js'],
    ['test', 'client_error_routes.test.js'],
    ['test', 'platform_config_schema.test.js'],
  ];

  it('görünmez / yön karakteri içermez (kod noktaları SAYIYLA denetlenir; kaynakta \\u kaçışı çıplak harfe dönüşmüş olmasın)', () => {
    const isHidden = (code) =>
      (code < 32 && code !== 9 && code !== 10 && code !== 13) ||
      code === 127 ||
      (code >= 128 && code <= 159) ||
      code === 173 ||
      (code >= 8203 && code <= 8207) ||
      (code >= 8232 && code <= 8238) ||
      (code >= 8288 && code <= 8303) ||
      code === 65279;
    for (const parts of files) {
      const text = readRelative(...parts);
      for (let index = 0; index < text.length; index += 1) {
        assert.equal(isHidden(text.charCodeAt(index)), false, `${parts.join('/')} @${index}: U+${text.charCodeAt(index).toString(16)}`);
      }
    }
    for (const name of ['privacy', 'terms', 'kvkk_notice', 'dpa', 'draft', 'evil', 'broken']) {
      const text = readRelative('test', 'fixtures', 'legal', `${name}.md`);
      for (let index = 0; index < text.length; index += 1) {
        assert.equal(isHidden(text.charCodeAt(index)), false, `fixtures/legal/${name}.md @${index}`);
      }
    }
  });

  it('günlüğe yalnız hata KODU yazılır (kişisel veri / ham hata iletisi değil)', () => {
    for (const parts of files.filter(([dir]) => dir === 'src')) {
      const text = readRelative(...parts);
      for (const call of text.match(/console\.error\([^;]*\);/g) ?? []) {
        assert.equal(/req\.body|\.body\b|email|phone/i.test(call), false, `${parts.join('/')}: ${call}`);
        assert.equal(/error\.message|error\?\.message(?! \|\|)/.test(call.replace(/error\?\.code \|\| error\?\.message/g, '')), false, `${parts.join('/')}: ${call}`);
      }
    }
  });
});
