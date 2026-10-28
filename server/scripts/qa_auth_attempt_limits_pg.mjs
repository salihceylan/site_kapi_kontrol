// Kalici deneme sinirlari (migrations/085 + security/attempt_limits.js + POST /auth/login PIN siniri) icin GERCEK PostgreSQL dogrulamasi.
// `npm test` ICINDE DEGILDIR. Kendi GECICI veritabanini (qa_attempt_limits_<pid>) olusturur ve sonunda siler; baska hicbir veritabanina dokunmaz.
//
//   QA_PG_URL=postgresql://postgres@127.0.0.1:55487/postgres node scripts/qa_auth_attempt_limits_pg.mjs
//
// Kapsam: migration idempotent; PIN ilkesi (5 yanlis -> 15 dk kilit, kilitliyken satira YAZILMAZ, sifirlama), artan kilit (15 -> 30 -> 60 dk, en cok 24 sa),
// pencere dolunca sayac yeniden baslar, sessiz sure sonrasi seviye sifirlanir, 30 paralel istekte tam 5 hata sayilir (atomiklik), kapsamlar birbirini
// etkilemez, e-posta/SMS ilkesi (15 yanlis -> 1 sa), bakim temizligi (kilitli satir korunur) ve GERCEK /auth/login rotasi (gercek SQL: pin_issued sutunu,
// 423 PIN_LOCKED, dogru PIN satiri siler, PIN'siz hesapta sinir tablosuna yazilmaz, paralel istek). Cikis kodu: 0 hepsi gecti, 1 en az bir kontrol dustu.
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import bcrypt from 'bcryptjs';
import pg from 'pg';

const url = process.env.QA_PG_URL;
if (!url) {
  console.error('QA_PG_URL gerekli (ornek: postgresql://postgres@127.0.0.1:55487/postgres).');
  process.exit(2);
}

// Gecici veritabani: uygulama havuzu (src/db.js) ortam degiskenlerinden kurulur; once ayarlanir, sonra ice aktarilir.
const admin = new pg.Client({ connectionString: url });
await admin.connect();
const tempDb = `qa_attempt_limits_${process.pid}`;
await admin.query(`DROP DATABASE IF EXISTS "${tempDb}"`);
await admin.query(`CREATE DATABASE "${tempDb}"`);
const parsed = new URL(url);
const tempUrl = new URL(url);
tempUrl.pathname = `/${tempDb}`;
Object.assign(process.env, {
  DB_HOST: parsed.hostname,
  DB_PORT: parsed.port || '5432',
  DB_NAME: tempDb,
  DB_USER: decodeURIComponent(parsed.username),
  DB_PASSWORD: decodeURIComponent(parsed.password),
  JWT_SECRET: 'qa-attempt-limits-only-secret-value-0123456789abcdef',
});

const here = path.dirname(fileURLToPath(import.meta.url));
const migrationSql = fs.readFileSync(path.join(here, '..', 'migrations', '085_auth_attempt_limits.sql'), 'utf8');
const limits = await import('../src/security/attempt_limits.js');
limits.attemptLimitHooks.onLock = () => {}; // betik cok sayida kilit koyar: izleme kancasi gurultu yapmasin
const { ATTEMPT_POLICIES, apartmentPinTarget, attemptTarget, emailCodeTarget } = limits;
const { AUTH_ATTEMPT_LIMITS_DDL, ensureAuthAttemptLimitsSchema } = await import('../src/modules/auth_attempt_limits_schema.js');
const { pool: appPool } = await import('../src/db.js');

const db = new pg.Pool({ connectionString: tempUrl.toString(), max: 12 });
// Tum islemler bu betigin kendi havuzuyla calisir.
const peekAttemptLock = (policy, target) => limits.peekAttemptLock(policy, target, db);
const registerAttemptFailure = (policy, target) => limits.registerAttemptFailure(policy, target, db);
const resetAttempts = (policy, target) => limits.resetAttempts(policy, target, db);
const purgeStaleAttemptLimits = () => limits.purgeStaleAttemptLimits(db);

let failed = 0;
function check(name, ok, detail = '') {
  if (!ok) failed += 1;
  console.log(`${ok ? 'PASS' : 'FAIL'} ${name}${ok ? '' : ` ${detail}`}`);
}
const row = async (policy, target) =>
  (await db.query('SELECT * FROM auth_attempt_limits WHERE scope = $1 AND target = $2', [policy.scope, target])).rows[0];
const PIN = ATTEMPT_POLICIES.apartmentPin;
let loginServer = null;

try {
  // 1) Migration idempotent + sema modulu ayni sonucu verir
  await db.query(migrationSql);
  await db.query(migrationSql);
  check('migration 085 iki kez calisir (idempotent)', true);
  await db.query('DROP TABLE auth_attempt_limits');
  const client = await db.connect();
  try {
    await ensureAuthAttemptLimitsSchema(client);
    await ensureAuthAttemptLimitsSchema(client);
  } finally {
    client.release();
  }
  const exists = (await db.query(`SELECT to_regclass('public.auth_attempt_limits') IS NOT NULL AS ok`)).rows[0].ok;
  check('ensureAuthAttemptLimitsSchema tabloyu kurar, ikinci cagri hicbir sey yapmaz', exists === true && AUTH_ATTEMPT_LIMITS_DDL.length === 2);

  // 2) PIN ilkesi: 5 yanlis -> 15 dk
  const t1 = apartmentPinTarget(101, '$2a$10$ornekozet.ornekozet.ornekozet.ornekozet.ornekozet.orn');
  const seen = [];
  for (let i = 0; i < 4; i += 1) seen.push(await registerAttemptFailure(PIN, t1));
  check('ilk 4 yanlis kilitlemez, sayac 1..4', seen.every((r, i) => !r.blocked && !r.locked && r.failures === i + 1), JSON.stringify(seen));
  const fifth = await registerAttemptFailure(PIN, t1);
  check('5. yanlis 15 dk kilit koyar (bu cagri blocked DEGIL, locked)', !fifth.blocked && fifth.locked && fifth.retryAfterSeconds > 14 * 60 && fifth.retryAfterSeconds <= 15 * 60, JSON.stringify(fifth));
  const locked1 = await row(PIN, t1);
  check('kilit satiri: sayac 0, seviye 1, locked_until ileride', locked1.fail_count === 0 && locked1.lock_level === 1 && new Date(locked1.locked_until) > new Date(), JSON.stringify(locked1));
  const sixth = await registerAttemptFailure(PIN, t1);
  const after6 = await row(PIN, t1);
  check('kilitliyken blocked: satir DEGISMEZ (yazma yok)', sixth.blocked && sixth.locked && sixth.retryAfterSeconds > 0 && String(after6.updated_at) === String(locked1.updated_at) && after6.fail_count === 0, JSON.stringify([sixth, after6]));
  check('peek kilitli satiri gorur', (await peekAttemptLock(PIN, t1)).locked === true);
  await resetAttempts(PIN, t1);
  check('dogru dogrulama (reset) satiri siler, kilit kalkar', (await row(PIN, t1)) === undefined && (await peekAttemptLock(PIN, t1)).locked === false);
  for (let i = 0; i < 4; i += 1) await registerAttemptFailure(PIN, t1);
  const again = await registerAttemptFailure(PIN, t1);
  check('reset sonrasi seviye de sifirlanir: yine 15 dk', again.locked && again.retryAfterSeconds <= 15 * 60, JSON.stringify(again));

  // 3) Artan kilit: sure dolunca 5 yanlis -> 30 dk, sonra 60 dk
  await db.query(`UPDATE auth_attempt_limits SET locked_until = NOW() - INTERVAL '1 second' WHERE scope = $1 AND target = $2`, [PIN.scope, t1]);
  check('sure dolan kilit peek ile kilitli gorunmez', (await peekAttemptLock(PIN, t1)).locked === false);
  for (let i = 0; i < 4; i += 1) await registerAttemptFailure(PIN, t1);
  const second = await registerAttemptFailure(PIN, t1);
  check('2. kilit 30 dk', second.locked && second.retryAfterSeconds > 29 * 60 && second.retryAfterSeconds <= 30 * 60, JSON.stringify(second));
  await db.query(`UPDATE auth_attempt_limits SET locked_until = NOW() - INTERVAL '1 second' WHERE scope = $1 AND target = $2`, [PIN.scope, t1]);
  for (let i = 0; i < 4; i += 1) await registerAttemptFailure(PIN, t1);
  const third = await registerAttemptFailure(PIN, t1);
  check('3. kilit 60 dk', third.locked && third.retryAfterSeconds > 59 * 60 && third.retryAfterSeconds <= 60 * 60, JSON.stringify(third));

  // 4) En cok 24 saat
  await db.query(`UPDATE auth_attempt_limits SET locked_until = NOW() - INTERVAL '1 second', lock_level = 12 WHERE scope = $1 AND target = $2`, [PIN.scope, t1]);
  for (let i = 0; i < 4; i += 1) await registerAttemptFailure(PIN, t1);
  const capped = await registerAttemptFailure(PIN, t1);
  check('kilit suresi 24 saati asmaz', capped.locked && capped.retryAfterSeconds > 23 * 3600 && capped.retryAfterSeconds <= 24 * 3600, JSON.stringify(capped));

  // 5) Pencere dolunca sayac yeniden baslar; sessiz sure sonrasi seviye sifirlanir
  const t2 = apartmentPinTarget(102, 'baska-ozet');
  for (let i = 0; i < 4; i += 1) await registerAttemptFailure(PIN, t2);
  await db.query(`UPDATE auth_attempt_limits SET window_started_at = NOW() - INTERVAL '25 hours' WHERE scope = $1 AND target = $2`, [PIN.scope, t2]);
  const fresh = await registerAttemptFailure(PIN, t2);
  check('24 saati asan pencere: sayac 1den baslar, kilit yok', !fresh.locked && fresh.failures === 1, JSON.stringify(fresh));
  await db.query(
    `UPDATE auth_attempt_limits SET updated_at = NOW() - INTERVAL '25 hours', locked_until = NOW() - INTERVAL '25 hours', lock_level = 4, window_started_at = NOW() - INTERVAL '25 hours'
       WHERE scope = $1 AND target = $2`,
    [PIN.scope, t2],
  );
  await registerAttemptFailure(PIN, t2);
  const quiet = await row(PIN, t2);
  check('24 saat sessizlik: kilit seviyesi sifirlanir', quiet.lock_level === 0 && quiet.fail_count === 1 && quiet.locked_until === null, JSON.stringify(quiet));
  await db.query(`UPDATE auth_attempt_limits SET updated_at = NOW() - INTERVAL '2 hours', locked_until = NOW() - INTERVAL '1 hour', lock_level = 4, fail_count = 0 WHERE scope = $1 AND target = $2`, [PIN.scope, t2]);
  await registerAttemptFailure(PIN, t2);
  const notQuiet = await row(PIN, t2);
  check('kilit bitiminden 24 saat gecmediyse seviye KORUNUR', notQuiet.lock_level === 4, JSON.stringify(notQuiet));

  // 6) Atomiklik: 30 paralel yanlis -> tam 1 kilit koyan + 4 sayilan + 25 blocked
  const t3 = apartmentPinTarget(103, 'paralel-ozet');
  const burst = await Promise.all(Array.from({ length: 30 }, () => registerAttemptFailure(PIN, t3)));
  const tripped = burst.filter((r) => !r.blocked && r.locked).length;
  const counted = burst.filter((r) => !r.blocked && !r.locked).length;
  const blocked = burst.filter((r) => r.blocked).length;
  check('30 paralel istek: 4 sayilan + 1 kilitleyen + 25 blocked (karsilastirmaya en cok 5 istek ulasir)', tripped === 1 && counted === 4 && blocked === 25, JSON.stringify({ tripped, counted, blocked }));

  // 7) Kapsamlar birbirini etkilemez
  const other = { ...PIN, scope: 'baska_kapsam' };
  check('ayni hedef baska kapsamda kilitli degil', (await peekAttemptLock(other, t3)).locked === false);

  // 8) E-posta / SMS ilkesi: 15 yanlis -> 1 saat
  const EMAIL = ATTEMPT_POLICIES.emailCode;
  const mail = emailCodeTarget('Kisi@Example.com');
  check('e-posta hedefi buyuk/kucuk harf duyarsiz', mail === emailCodeTarget('kisi@example.com') && mail !== attemptTarget('sms_code', 'kisi@example.com'));
  const mails = [];
  for (let i = 0; i < 14; i += 1) mails.push(await registerAttemptFailure(EMAIL, mail));
  check('e-posta kodu: ilk 14 yanlis kilitlemez', mails.every((r) => !r.locked && !r.blocked));
  const mailLock = await registerAttemptFailure(EMAIL, mail);
  check('e-posta kodu: 15. yanlis 1 saat kilit', mailLock.locked && mailLock.retryAfterSeconds > 59 * 60 && mailLock.retryAfterSeconds <= 3600, JSON.stringify(mailLock));

  // 9) Bakim temizligi
  await db.query(`UPDATE auth_attempt_limits SET updated_at = NOW() - INTERVAL '40 days', locked_until = NOW() - INTERVAL '39 days' WHERE scope = $1 AND target = $2`, [PIN.scope, t2]);
  await db.query(`UPDATE auth_attempt_limits SET updated_at = NOW() - INTERVAL '40 days' WHERE scope = $1 AND target = $2`, [PIN.scope, t3]);
  await purgeStaleAttemptLimits();
  check('bakim: eski ve kilidi bitmis satir silinir', (await row(PIN, t2)) === undefined);
  check('bakim: hala kilitli satir (eski olsa da) korunur', (await row(PIN, t3)) !== undefined);

  // 10) GERCEK /auth/login rotasi (gercek SQL + gercek sinir tablosu). Asgari users / apartments / pending_registrations tablolari.
  await db.query(`
    CREATE TABLE users (
      user_code INTEGER PRIMARY KEY, full_name TEXT NOT NULL, email TEXT, login_name TEXT, role TEXT NOT NULL,
      is_active BOOLEAN NOT NULL DEFAULT TRUE, email_verified BOOLEAN NOT NULL DEFAULT TRUE, approval_status TEXT NOT NULL DEFAULT 'approved',
      phone_number TEXT, created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), password_hash TEXT NOT NULL, must_change_password BOOLEAN NOT NULL DEFAULT FALSE);
    CREATE TABLE apartments (id BIGSERIAL PRIMARY KEY, resident_user_code INTEGER, resident_pin_issued BOOLEAN NOT NULL DEFAULT FALSE);
    CREATE TABLE pending_registrations (email TEXT, password_hash TEXT);`);
  const pinHash = bcrypt.hashSync('4821', 4);
  const plainHash = bcrypt.hashSync('Mavi-Kapi-77-Ruzgar', 4);
  await db.query(
    `INSERT INTO users (user_code, full_name, email, login_name, role, password_hash, must_change_password) VALUES
       (1, 'Daire 12', '1000_ablok_daire12@ahbu.local', '1000_ABlok_Daire12', 'apartment_owner', $1, TRUE),
       (2, 'Ali Test', 'ali@example.com', 'ali.k', 'individual', $2, FALSE)`,
    [pinHash, plainHash],
  );
  await db.query(`INSERT INTO apartments (resident_user_code, resident_pin_issued) VALUES (1, TRUE)`);

  const { default: express } = await import('express');
  await import('../src/utils/async_errors.js');
  const { authRouter } = await import('../src/routes/auth_routes.js');
  const { createErrorHandler } = await import('../src/middlewares/error_handler.js');
  const { resolveTrustProxy } = await import('../src/security/trust_proxy.js');
  const app = express();
  app.set('trust proxy', resolveTrustProxy({}).value);
  app.use(express.json());
  app.use(authRouter);
  app.use(createErrorHandler({ logger: { error: () => {}, log: () => {}, warn: () => {} } }));
  loginServer = await new Promise((resolve) => {
    const server = http.createServer(app);
    server.listen(0, '127.0.0.1', () => resolve(server));
  });
  const base = `http://127.0.0.1:${loginServer.address().port}`;
  let ipCounter = 0;
  const login = (identifier, password) =>
    fetch(`${base}/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'X-Forwarded-For': `198.51.100.${(ipCounter += 1) % 250 + 1}` },
      body: JSON.stringify({ login: identifier, password }),
    });
  const pinRows = async () => (await db.query(`SELECT * FROM auth_attempt_limits WHERE scope = 'apartment_pin'`)).rows;
  await db.query(`DELETE FROM auth_attempt_limits`);

  const statuses = [];
  for (let i = 0; i < 4; i += 1) statuses.push((await login('1000_ABlok_Daire12', `000${i}`)).status);
  check('gercek rota: 4 yanlis PIN 401', statuses.join() === '401,401,401,401', statuses.join());
  const lockResponse = await login('1000_ABlok_Daire12', '0004');
  const lockBody = await lockResponse.json();
  check('gercek rota: 5. yanlis 423 PIN_LOCKED + Retry-After 900 + Turkce mesaj', lockResponse.status === 423 && lockBody.code === 'PIN_LOCKED' && lockResponse.headers.get('retry-after') === '900' && /15 dakika/.test(lockBody.error), JSON.stringify([lockResponse.status, lockBody]));
  const heldRows = await pinRows();
  check('gercek rota: tek satir, sayac 0, seviye 1, kilitli', heldRows.length === 1 && heldRows[0].fail_count === 0 && heldRows[0].lock_level === 1 && new Date(heldRows[0].locked_until) > new Date(), JSON.stringify(heldRows));
  const lockedCorrect = await login('1000_ablok_daire12@ahbu.local', '4821');
  check('gercek rota: kilitliyken DOGRU PIN bile 423 (e-posta tanimlayicisiyla da, baska IP)', lockedCorrect.status === 423);
  await db.query(`UPDATE auth_attempt_limits SET locked_until = NOW() - INTERVAL '1 second' WHERE scope = 'apartment_pin'`);
  const okResponse = await login('1000_ABlok_Daire12', '4821');
  const okBody = await okResponse.json();
  check('gercek rota: sure dolunca dogru PIN 200, must_change_password true, sayac satiri silinir', okResponse.status === 200 && okBody.user?.must_change_password === true && (await pinRows()).length === 0, JSON.stringify([okResponse.status, okBody]));

  const plainStatuses = [];
  for (let i = 0; i < 6; i += 1) plainStatuses.push((await login('ali.k', `yanlis-${i}`)).status);
  check('gercek rota: PIN\'siz hesap ve olmayan hesap sinir tablosuna HIC yazmaz', plainStatuses.every((s) => s === 401) && (await login('hic-yok', 'x1234567')).status === 401 && (await db.query('SELECT COUNT(*)::int AS n FROM auth_attempt_limits')).rows[0].n === 0);
  check('gercek rota: PIN\'siz hesap dogru parolayla girer', (await login('ali.k', 'Mavi-Kapi-77-Ruzgar')).status === 200);

  await db.query(`DELETE FROM auth_attempt_limits`);
  const parallel = await Promise.all(Array.from({ length: 12 }, (_, i) => login('1000_ABlok_Daire12', `99${i}`)));
  const codes = parallel.map((r) => r.status).sort();
  check('gercek rota: 12 paralel yanlis istek -> 4 x 401 + 8 x 423 (en cok 5 karsilastirma)', codes.join() === '401,401,401,401,423,423,423,423,423,423,423,423', codes.join());
} catch (error) {
  failed += 1;
  console.log(`FAIL beklenmeyen hata: ${error?.stack || error}`);
} finally {
  if (loginServer) await new Promise((resolve) => loginServer.close(resolve));
  await appPool.end().catch(() => {});
  await db.end().catch(() => {});
  await admin.query(`DROP DATABASE IF EXISTS "${tempDb}" WITH (FORCE)`).catch((error) => console.log(`UYARI: gecici veritabani silinemedi: ${error?.message}`));
  await admin.end().catch(() => {});
}

console.log(failed === 0 ? 'TUMU GECTI' : `${failed} KONTROL DUSTU`);
process.exit(failed === 0 ? 0 : 1);
