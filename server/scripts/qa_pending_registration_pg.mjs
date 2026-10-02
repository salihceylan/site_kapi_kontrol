#!/usr/bin/env node
// Bekleyen kayit akisini GERCEK PostgreSQL'e karsi uctan uca dogrular (e-posta sahte; ag yok).
//
//   cd server
//   DB_HOST=127.0.0.1 DB_PORT=55432 DB_NAME=kapi_qa DB_USER=postgres DB_PASSWORD=x \
//     QA_CONFIRM_DISPOSABLE_DB=yes node scripts/qa_pending_registration_pg.mjs
//
// ONCE `node scripts/migrate.js --apply --yes` ile bos bir yerel veritabani hazirlayin.
//
// GUVENLIK: betik tek kullanimlik YEREL veritabani icindir. DB_HOST yalnizca 127.0.0.1/localhost olabilir ve
// QA_CONFIRM_DISPOSABLE_DB=yes gerekir; aksi halde calismaz. Bakim adimi `pending_registrations` icindeki
// 2 gunden eski TUM satirlari siler; uretim veritabaninda ASLA calistirmayin. Hicbir ag/SMTP baglantisi kurulmaz.
import assert from 'node:assert/strict';
import bcrypt from 'bcryptjs';
import nodemailer from 'nodemailer';

if (!['127.0.0.1', 'localhost'].includes(String(process.env.DB_HOST || ''))) {
  console.error('REDDEDILDI: DB_HOST yalnizca 127.0.0.1 veya localhost olabilir (tek kullanimlik yerel veritabani).');
  process.exit(3);
}
if (process.env.QA_CONFIRM_DISPOSABLE_DB !== 'yes') {
  console.error('REDDEDILDI: veritabaninin tek kullanimlik oldugunu QA_CONFIRM_DISPOSABLE_DB=yes ile onaylayin.');
  process.exit(3);
}
process.env.JWT_SECRET ||= 'qa-integration-secret-0123456789abcdef-0123456789';
Object.assign(process.env, {
  SMTP_HOST: 'smtp.invalid',
  SMTP_USER: 'qa@example.invalid',
  SMTP_PASSWORD: 'qa',
  SMTP_FROM: 'AHBU QA <noreply@example.invalid>',
});

const { pool, ensureDbSchema } = await import('../src/db.js');
const svc = await import('../src/services/membership_service.js');
const { runDatabaseCleanup, getDatabaseHealth } = await import('../src/services/maintenance_service.js');

// --- sahte e-posta: gonderim sirasi/gecikmesi test tarafindan yonetilir
const mails = [];
let failMail = false;
let sendCalls = 0;
let holdFirstSend = null; // Promise: ilk gonderim bu promise cozulene dek bekler (sira disi tamamlanma)
const sentByCall = {};
nodemailer.createTransport = () => ({
  sendMail: async (message) => {
    const call = ++sendCalls;
    if (call === 1 && holdFirstSend) await holdFirstSend;
    if (failMail) throw Object.assign(new Error('simulated smtp failure'), { code: 'ETIMEDOUT' });
    mails.push(message);
    sentByCall[call] = message;
  },
});
console.error = () => {};

const q = (sql, params = []) => pool.query(sql, params);
const one = async (sql, params) => (await q(sql, params)).rows[0];
const countOf = async (table, email) =>
  Number((await one(`SELECT COUNT(*)::int AS c FROM ${table} WHERE LOWER(email) = LOWER($1)`, [email])).c);
const codeFrom = (message) => message.text.match(/\b(\d{6})\b/)[1];
const age = (email, seconds) =>
  q(`UPDATE email_verifications SET created_at = created_at - make_interval(secs => $2) WHERE LOWER(email) = LOWER($1)`, [email, seconds]);
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
async function waitFor(predicate, timeoutMs = 3000) {
  const start = Date.now();
  while (!(await predicate())) {
    if (Date.now() - start > timeoutMs) throw new Error('waitFor zaman asimi');
    await sleep(15);
  }
}
let step = 0;
const ok = (name) => console.log(`  OK ${String(++step).padStart(2, '0')}  ${name}`);

const suffix = Math.random().toString(36).slice(2, 8);
const mail = (n) => `qa-pending-${n}-${suffix}@example.com`;
const input = (email, extra = {}) => ({ firstName: 'Ali', lastName: 'Veli', email, password: 'abcdef12', ...extra });

await q(`DELETE FROM users WHERE email LIKE 'qa-pending-%@example.com'`);
await q(`DELETE FROM pending_registrations WHERE email LIKE 'qa-pending-%@example.com'`);
await q(`DELETE FROM email_verifications WHERE email LIKE 'qa-pending-%@example.com'`);

// --- 0) Sema: db.js DDL'i iki kez calisir (idempotent) ve tablo mevcut
await ensureDbSchema();
await ensureDbSchema();
assert.equal(
  Number((await one(`SELECT COUNT(*)::int AS c FROM information_schema.tables WHERE table_name = 'pending_registrations'`)).c),
  1,
);
ok('ensureDbSchema iki kez calisti (idempotent); pending_registrations mevcut');

// --- 1) Kayit: users YOK, pending VAR, kod e-postada
const E1 = mail(1);
const r1 = await svc.registerIndividualUser(input(E1));
assert.equal(r1.ok, true);
assert.equal(r1.expires_in_minutes, 30);
assert.equal(await countOf('users', E1), 0);
assert.equal(await countOf('pending_registrations', E1), 1);
const code1 = codeFrom(mails.at(-1));
const pend1 = await one(`SELECT * FROM pending_registrations WHERE LOWER(email) = LOWER($1)`, [E1]);
assert.equal(await bcrypt.compare('abcdef12', pend1.password_hash), true);
assert.equal(pend1.password_hash.includes('abcdef12'), false);
ok('kayit: users satiri YOK, bekleyen kayit VAR (parola ozeti), kod e-postada');

// --- 2) Bekleme suresi icinde tekrar kayit: 429 ve bekleyen kayit DEGISMEZ (reddedilen deneme veri ezemez)
const mailCountBefore = mails.length;
await assert.rejects(
  () => svc.registerIndividualUser(input(mail(1).toUpperCase(), { firstName: 'Ahmet', password: 'Zyxwvu98' })),
  (e) => e.statusCode === 429 && /saniye/.test(e.message),
);
assert.equal(await countOf('pending_registrations', E1), 1);
const pend2 = await one(`SELECT * FROM pending_registrations WHERE LOWER(email) = LOWER($1)`, [E1]);
assert.equal(pend2.full_name, 'Ali Veli', 'reddedilen deneme adi degistirmemeli');
assert.equal(await bcrypt.compare('abcdef12', pend2.password_hash), true, 'reddedilen deneme parolayi degistirmemeli');
assert.equal(mails.length, mailCountBefore);
ok('bekleme suresi: 429 + saniye; reddedilen deneme bekleyen kaydi ezmedi');

// --- 3) Bekleme gecince yeni kod: ON CONFLICT ((LOWER(email))) tek satirda gunceller; eski kod YENI gonderimden sonra kapanir
await age(E1, 40);
await svc.registerIndividualUser(input(E1.toUpperCase(), { firstName: 'Ahmet', password: 'Zyxwvu98' }));
assert.equal(await countOf('pending_registrations', E1), 1, 'buyuk/kucuk harf farkli ayni e-posta tek satir olmali');
const pend3 = await one(`SELECT * FROM pending_registrations WHERE LOWER(email) = LOWER($1)`, [E1]);
assert.equal(pend3.full_name, 'Ahmet Veli');
assert.equal(await bcrypt.compare('Zyxwvu98', pend3.password_hash), true);
const code2 = codeFrom(mails.at(-1));
const rows = (await q(`SELECT id, is_verified FROM email_verifications WHERE LOWER(email) = LOWER($1) ORDER BY id`, [E1])).rows;
assert.equal(rows.length, 2);
assert.equal(rows[0].is_verified, true, 'eski kod kapanmali');
assert.equal(rows[1].is_verified, false, 'yeni kod acik olmali');
ok('gonderim sonrasi: kimlik bilgileri guncellendi (tek satir, buyuk/kucuk harf duyarsiz); eski kod kapandi');

// --- 4) Eski kod gecersiz, yeni kod hesabi olusturur
if (code1 !== code2) {
  await assert.rejects(() => svc.verifyIndividualEmailCode({ email: E1, code: code1 }), (e) => e.statusCode === 400);
  ok('eski (kapanmis) kod reddedildi');
}
const v1 = await svc.verifyIndividualEmailCode({ email: E1, code: code2 });
assert.equal(v1.ok, true);
assert.ok(typeof v1.token === 'string' && v1.token.length > 20);
const user1 = await one(`SELECT * FROM users WHERE LOWER(email) = LOWER($1)`, [E1]);
assert.equal(user1.email_verified, true);
assert.equal(user1.role, 'individual');
assert.equal(user1.approval_status, 'approved');
assert.equal(user1.is_active, true);
assert.equal(user1.full_name, 'Ahmet Veli');
assert.equal(await bcrypt.compare('Zyxwvu98', user1.password_hash), true);
assert.equal(await countOf('pending_registrations', E1), 0);
ok('dogru kod: hesap SIMDI olustu (dogrulanmis, individual, approved), bekleyen kayit silindi, token dondu');

// --- 5) Ayni kod ikinci kez: hesap cogalmaz
await assert.rejects(() => svc.verifyIndividualEmailCode({ email: E1, code: code2 }), (e) => [404, 400].includes(e.statusCode));
assert.equal(await countOf('users', E1), 1);
ok('tek kullanimlik: ayni kod tekrar kullanilamaz, hesap cogalmadi');

// --- 6) Eszamanli iki dogrulama: tam olarak biri basarili
const E2 = mail(2);
await svc.registerIndividualUser(input(E2));
const code = codeFrom(mails.at(-1));
const settled = await Promise.allSettled([
  svc.verifyIndividualEmailCode({ email: E2, code }),
  svc.verifyIndividualEmailCode({ email: E2, code }),
]);
assert.equal(settled.filter((s) => s.status === 'fulfilled').length, 1);
assert.equal(await countOf('users', E2), 1);
assert.equal(await countOf('pending_registrations', E2), 0);
ok('eszamanli iki dogrulama: yalnizca biri basarili, tek hesap');

// --- 7) E-posta gonderilemezse: 503, kod satiri silinir, bekleyen kayit OLUSMAZ, ANINDA yeniden denenebilir
const E3 = mail(3);
failMail = true;
await assert.rejects(
  () => svc.registerIndividualUser(input(E3)),
  (e) => e.statusCode === 503 && e.code === 'EMAIL_DELIVERY_FAILED',
);
failMail = false;
assert.equal(await countOf('users', E3), 0);
assert.equal(await countOf('pending_registrations', E3), 0, 'gonderilemeyen denemede bekleyen kayit olusmamali');
assert.equal(await countOf('email_verifications', E3), 0, 'gonderilemeyen kod satiri silinmeli');
const mailsBefore = mails.length;
await svc.registerIndividualUser(input(E3));
assert.equal(mails.length, mailsBefore + 1, 'hemen yeniden deneme 429 olmamali');
ok('mail gitmedi: 503; bekleyen kayit ve kod satiri olusmadi; hemen yeniden denemek 429 vermedi');

// --- 8) Basarisiz "tekrar gonder", onceki gecerli (belki gec ulasan) kodu iptal etmez
const codeA = codeFrom(mails.at(-1));
await age(E3, 40);
failMail = true;
await svc.resendIndividualVerificationCode({ email: E3 });
await sleep(600);
failMail = false;
const openRows = (await q(`SELECT id FROM email_verifications WHERE LOWER(email) = LOWER($1) AND is_verified = FALSE`, [E3])).rows;
assert.equal(openRows.length, 1, 'onceki kod acik kalmali');
const v3 = await svc.verifyIndividualEmailCode({ email: E3, code: codeA });
assert.equal(v3.ok, true);
ok('basarisiz tekrar-gonder: onceki kod gecerli kaldi ve hesabi olusturdu');

// --- 9) SIRA DISI gonderim: yavas eski gonderim, daha yeni kodu iptal edemez ve yeni kimlik bilgilerini ezemez
const E6 = mail(6);
let releaseA;
holdFirstSend = new Promise((resolve) => {
  releaseA = resolve;
});
sendCalls = 0;
const pendingA = svc.registerIndividualUser(input(E6, { firstName: 'Ayse', password: 'Parola-A-1' }));
await waitFor(async () => (await countOf('email_verifications', E6)) === 1); // A'nin kod satiri yazildi, gonderim bekliyor
await age(E6, 40); // bekleme suresi gecmis say
const resultB = await svc.registerIndividualUser(input(E6, { firstName: 'Burak', password: 'Parola-B-2' }));
assert.equal(resultB.ok, true);
const codeB = codeFrom(sentByCall[2]);
releaseA(); // A'nin gonderimi artik (B'den sonra) tamamlanir
holdFirstSend = null;
await pendingA;
const open = (await q(`SELECT id FROM email_verifications WHERE LOWER(email) = LOWER($1) AND is_verified = FALSE`, [E6])).rows;
assert.equal(open.length, 1, 'yalnizca B kodu acik kalmali (A, B\'yi iptal etmemeli)');
const pendE6 = await one(`SELECT * FROM pending_registrations WHERE LOWER(email) = LOWER($1)`, [E6]);
assert.equal(pendE6.full_name, 'Burak Veli', 'gec biten A, B\'nin kimlik bilgilerini ezmemeli');
const v6 = await svc.verifyIndividualEmailCode({ email: E6, code: codeB });
assert.equal(v6.ok, true);
const user6 = await one(`SELECT * FROM users WHERE LOWER(email) = LOWER($1)`, [E6]);
assert.equal(await bcrypt.compare('Parola-B-2', user6.password_hash), true);
ok('sira disi gonderim: gec biten eski gonderim yeni kodu iptal etmedi ve yeni kimlik bilgilerini ezmedi');

// --- 10) Hesap onceden varsa dogrulama cift hesap olusturmaz
const E4 = mail(4);
await svc.registerIndividualUser(input(E4));
const code4 = codeFrom(mails.at(-1));
await q(
  `INSERT INTO users (full_name, email, role, is_active, email_verified, approval_status, password_hash)
   VALUES ('Baska Kisi', $1, 'individual', TRUE, TRUE, 'approved', 'x')`,
  [E4],
);
const v4 = await svc.verifyIndividualEmailCode({ email: E4, code: code4 });
assert.equal(v4.ok, true);
assert.equal(await countOf('users', E4), 1);
ok('ayni e-postayla hesap onceden varsa tekrarlanmaz (cift hesap olusmaz)');

// --- 11) Eski model (dogrulanmamis users satiri) geriye uyumlu; kimlik bilgileri gonderimden sonra guncellenir
const E5 = mail(5);
await q(
  `INSERT INTO users (full_name, email, role, is_active, email_verified, approval_status, password_hash)
   VALUES ('Eski Kayit', $1, 'individual', TRUE, FALSE, 'approved', $2)`,
  [E5, await bcrypt.hash('eskiparola', 4)],
);
await svc.registerIndividualUser(input(E5, { firstName: 'Yeni', password: 'Yenipar0la' }));
assert.equal(await countOf('pending_registrations', E5), 0, 'eski hesap icin bekleyen kayit acilmamali');
const v5 = await svc.verifyIndividualEmailCode({ email: E5, code: codeFrom(mails.at(-1)) });
assert.equal(v5.ok, true);
const user5 = await one(`SELECT * FROM users WHERE LOWER(email) = LOWER($1)`, [E5]);
assert.equal(user5.email_verified, true);
assert.equal(await bcrypt.compare('Yenipar0la', user5.password_hash), true);
ok('eski dogrulanmamis hesap: UPDATE yoluyla calisti (geriye uyumlu)');

// --- 12) Bakim: 2 gunden eski bekleyen kayit silinir, yeni kalir, users'a dokunulmaz
const usersBefore = Number((await one('SELECT COUNT(*)::int AS c FROM users')).c);
await q(`INSERT INTO pending_registrations (email, full_name, password_hash, updated_at) VALUES ($1, 'E', 'h', NOW() - INTERVAL '3 days')`, [mail(7)]);
await q(`INSERT INTO pending_registrations (email, full_name, password_hash) VALUES ($1, 'T', 'h')`, [mail(8)]);
const health = await getDatabaseHealth(pool);
assert.ok(health.pendingCleanup.expiredPendingRegistrations >= 1);
const cleanup = await runDatabaseCleanup(pool);
assert.equal(cleanup.success, true);
assert.ok(cleanup.stats.expiredPendingRegistrationsCleaned >= 1);
assert.equal(await countOf('pending_registrations', mail(7)), 0);
assert.equal(await countOf('pending_registrations', mail(8)), 1);
assert.equal(Number((await one('SELECT COUNT(*)::int AS c FROM users')).c), usersBefore);
ok('bakim: eski bekleyen kayit silindi, taze kaldi; users sayisi degismedi; saglik sayaci dogru');

// --- 13) Dogrulanmis hesaba yeniden kayit: 409, bekleyen kayit olusmaz
await assert.rejects(() => svc.registerIndividualUser(input(E1)), (e) => e.statusCode === 409);
assert.equal(await countOf('pending_registrations', E1), 0);
ok('dogrulanmis hesaba kayit: 409, bekleyen kayit yok');

// temizlik
await q(`DELETE FROM users WHERE email LIKE 'qa-pending-%@example.com'`);
await q(`DELETE FROM pending_registrations WHERE email LIKE 'qa-pending-%@example.com'`);
await q(`DELETE FROM email_verifications WHERE email LIKE 'qa-pending-%@example.com'`);

console.log(`\nTUM ${step} ADIM GECTI (gercek PostgreSQL)`);
await pool.end();
