// qa_platform_pg.mjs "push" bolumu (Telefon bildirimi, Faz 3b-B; docs/PLATFORM_BELGELER.md Bolum B, B11 "Gercek PG"). GERCEK PostgreSQL + sahte
// Google (oauth2 + FCM HTTP v1, node:http; gercek Google'a / Firebase'e ASLA baglanilmaz) + crypto.generateKeyPairSync RSA anahtariyla uretilmis
// hizmet hesabi dosyasi. QA_ONLY=push ile ayri kosulur (qa_platform_pg.mjs bu dosyayi ice aktarir; ortak yardimcilari `ctx` ile verir). `npm test` ICINDE DEGILDIR.
//
// Kapsam: sema (CHECK / FK / CASCADE / FK'siz outbox.user_code, ensureDbSchema idempotans + eksik nesne tamamlama), cihaz kaydi (UPSERT, devir, 10 cihaz,
// ESZAMANLI ayni jeton farkli kullanici -> tek sahip, kayit x hesap silme yarisi), yayin isleminde outbox INSERT ... SELECT (3000 alicili sitede sure,
// PUSH_ENABLED=0 iken 0 satir, kural kumesi, acil tercih bypass, UNIQUE cift yazimda ciftlemez), kilit sirasi turlari (yayin x kayit / tercih / hesap
// silme / isci; 40P01 = 0), isci (sahte FCM ile uctan uca, iki isci yarisi: advisory kilit, SKIP LOCKED, bayat talep, olu jeton, gecici hata, sessiz saat,
// gunluk ust sinir, geri cekme, pasif kullanici), hesap silme kancasi, bakim silmeleri, tercihler (kismi PUT, CHECK), disa aktarma (jeton yok),
// yonetici durumu, HTTP (gercek authRequired), gunluk gizliligi (jeton / client_email / anahtar parcasi yok).
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import http from 'node:http';
import { TEST_CLIENT_EMAIL, privateKeyFragment, serviceAccountJson, startFakeGoogle, fcmError } from '../test/fixtures/push_fixtures.js';

export async function sectionPush(ctx) {
  const { check, sleep, childEnv, finishChild, installPoolHooks, serverErrors } = ctx;
  await childEnv();
  Object.assign(process.env, {
    ANNOUNCEMENT_SCHEDULER_DISABLED: '1',
    ANNOUNCEMENT_MAX_PER_DAY_PER_SITE: '100000',
    ANNOUNCEMENT_URGENT_EMAIL_MAX_PER_DAY_PER_SITE: '100000',
    ANNOUNCEMENT_EMAIL_PUBLISH_MAX_PER_HOUR_PER_USER: '100000',
    DB_STATEMENT_TIMEOUT_MS: process.env.DB_STATEMENT_TIMEOUT_MS || '120000',
  });
  // gunluk gizliligi: console.log / warn da toplanir (console.error childEnv'de toplanir)
  const logLines = [];
  const realLog = console.log;
  console.warn = (...args) => { logLines.push(args.map(String).join(' ')); };
  console.log = (...args) => {
    const line = args.map(String).join(' ');
    if (!/^(PASS|FAIL)\s/.test(line)) logLines.push(line);
    realLog(...args);
  };
  process.on('exit', (code) => { if (code !== 0) for (const line of serverErrors.slice(-8)) realLog(`  [cikis oncesi sunucu hatasi] ${line.slice(0, 400)}`); });

  const { pool, ensureDbSchema } = await import('../src/db.js');
  const q = (sql, params = []) => pool.query(sql, params);
  const hooks = installPoolHooks(pool);
  const { loadPushRuntime } = await import('../src/modules/push_credentials.js');
  const { fcmHooks } = await import('../src/modules/push_fcm.js');
  const worker = await import('../src/modules/push_worker.js');
  const outbox = await import('../src/modules/push_outbox.js');
  const devicesMod = await import('../src/modules/push_devices.js');
  const { ensurePushSchema } = await import('../src/modules/push_schema.js');
  const inbox = await import('../src/modules/announcement_inbox.js');
  const annSvc = await import('../src/modules/announcement_service.js');
  const { syncSitePeople } = await import('../src/modules/people_sync.js');
  const { performAccountDeletion, accountHooks } = await import('../src/modules/account_deletion_service.js');
  const { collectPersonalData } = await import('../src/modules/account_export_service.js');
  const { istanbulMinuteOfDay } = await import('../src/modules/push_common.js');
  accountHooks.background = () => {};
  accountHooks.rotateTokensForSite = async () => {};
  accountHooks.rotateTokensForDevices = async () => {};
  accountHooks.sendDeletedEmail = async () => {};
  accountHooks.smtpConfigured = () => false;
  Object.assign(worker.pushQueueHooks, { sleep: async () => {} });

  // --- sahte Google + hizmet hesabi dosyasi (gecici dizin, 0600) ---------------------------------------------------
  const google = await startFakeGoogle();
  Object.assign(fcmHooks, { tokenUrl: google.tokenUrl, apiBase: google.apiBase, timeoutMs: 3000 });
  const saDir = fs.mkdtempSync(path.join(os.tmpdir(), 'qa-push-sa-'));
  const saFile = path.join(saDir, 'fcm-service-account.json');
  fs.writeFileSync(saFile, JSON.stringify(serviceAccountJson()), { mode: 0o600 });
  const pushOn = () => loadPushRuntime({ PUSH_ENABLED: '1', FCM_SERVICE_ACCOUNT_FILE: saFile });
  const pushOff = () => loadPushRuntime({ PUSH_ENABLED: '0', FCM_SERVICE_ACCOUNT_FILE: saFile });
  const fcmBodies = () => google.state.sendRequests.map((r) => r.body?.message);
  const resetGoogle = () => {
    google.state.send = null;
    google.state.token = null;
    google.state.sendRequests.length = 0;
    google.state.sendCount = 0;
  };

  // --- tohum yardimcilari -------------------------------------------------------------------------------------------
  const superActor = { ...(await q(`SELECT user_code, full_name, role, email FROM users WHERE user_code = 10001`)).rows[0] };
  superActor.id = superActor.user_code;
  superActor.userCode = superActor.user_code;
  let nextUser = 40000;
  let nextSite = 1000000301;
  async function mkSite(count, name = 'Push Sitesi') {
    const code = nextSite;
    nextSite += 1;
    await q(`INSERT INTO sites (site_code, name, approval_status, approved_at) VALUES ($1, $2, 'approved', NOW())`, [code, name]);
    const block = Number((await q(`INSERT INTO site_blocks (site_code, block_name, sort_order) VALUES ($1, 'A Blok', 1) RETURNING id`, [code])).rows[0].id);
    await q(`INSERT INTO apartments (site_code, block_id, unit_label, sort_order) SELECT $1::bigint, $2::bigint, 'Daire ' || g, g FROM generate_series(1, $3::int) g`, [code, block, count]);
    const first = nextUser;
    nextUser += count;
    await q(
      `INSERT INTO users (user_code, full_name, email, role, password_hash, is_active, email_verified, approval_status)
       SELECT $1::int + g - 1, 'Push Sakin ' || ($1::int + g - 1), 'push' || ($1::int + g - 1) || '@example.com', 'apartment_owner', 'x', TRUE, TRUE, 'approved'
       FROM generate_series(1, $2::int) g`,
      [first, count],
    );
    await q(
      `INSERT INTO apartment_memberships (apartment_id, user_code, role)
       SELECT a.id, $2::int + a.sort_order - 1, 'FAMILY_MEMBER' FROM apartments a WHERE a.site_code = $1::bigint`,
      [code, first],
    );
    await syncSitePeople(code);
    return { code, users: Array.from({ length: count }, (_, i) => first + i) };
  }
  const tokenOf = (userCode, n = 1) => `fcm-qa-jeton-${userCode}-${n}-${'x'.repeat(40)}`;
  const installOf = (userCode, n = 1) => `qa-kurulum-${String(userCode).padStart(8, '0')}-${n}`;
  const register = (userCode, n = 1, extra = {}) =>
    devicesMod.registerPushDevice({ user_code: userCode }, { install_id: installOf(userCode, n), platform: 'android', token: tokenOf(userCode, n), app_version: '1.0.0', ...extra });
  async function bulkDevices(userCodes, { enabled = true, platform = 'android' } = {}) {
    if (userCodes.length === 0) return;
    await q(
      `INSERT INTO push_devices (user_code, install_id, platform, fcm_token, notifications_enabled)
       SELECT u, 'qa-kurulum-' || lpad(u::text, 8, '0') || '-1', $2, 'fcm-qa-jeton-' || u || '-1-' || repeat('x', 40), $3
       FROM unnest($1::int[]) AS u
       ON CONFLICT DO NOTHING`,
      [userCodes, platform, enabled],
    );
  }
  let titleSeq = 0;
  const publish = (siteCode, importance = 'normal', extra = {}) => {
    titleSeq += 1;
    return annSvc.createAnnouncement({
      siteCode,
      body: { title: `QA push duyurusu ${titleSeq}`, body: 'Metin', target: { type: 'site' }, publish: 'now', importance, ...extra },
      actor: superActor,
    });
  };
  const outboxOf = async (announcementId) =>
    (await q(`SELECT id, user_code, status, skip_reason, attempts, importance, not_before, expires_at, claimed_at, sent_device_count, last_error_code, sent_at, created_at FROM push_outbox WHERE announcement_id = $1 ORDER BY user_code`, [announcementId])).rows;
  const countBy = (rows, key) => rows.reduce((acc, row) => ({ ...acc, [row[key] ?? 'null']: (acc[row[key] ?? 'null'] ?? 0) + 1 }), {});
  const deadlocksBefore = () => hooks.deadlocks;

  // ============================================================================================================
  // A. Sema
  // ============================================================================================================
  console.log('--- A. sema ---');
  const cols = (await q(`SELECT column_name, data_type, is_nullable, column_default FROM information_schema.columns WHERE table_name = 'notification_preferences' AND column_name LIKE 'push_%' ORDER BY column_name`)).rows;
  check('A1: notification_preferences push_* sutunlari (EKLEMELI, NOT NULL, varsayilanlar 1380/420/false)',
    cols.length === 5 && cols.find((c) => c.column_name === 'push_quiet_start')?.column_default === '1380' && cols.find((c) => c.column_name === 'push_quiet_end')?.column_default === '420' && cols.find((c) => c.column_name === 'push_show_preview')?.column_default === 'false', cols);
  const quietCheck = (await q(`SELECT convalidated FROM pg_constraint WHERE conname = 'chk_notification_preferences_push_quiet'`)).rows[0];
  check('A2: sessiz saat CHECK var ve NOT VALID (sonradan eklenen CHECK; 3a karar 25)', quietCheck && quietCheck.convalidated === false, quietCheck);
  const fkRows = (await q(`SELECT conrelid::regclass::text AS tbl, confrelid::regclass::text AS ref, confdeltype FROM pg_constraint WHERE contype = 'f' AND conrelid::regclass::text IN ('push_devices', 'push_outbox') ORDER BY 1, 2`)).rows;
  check('A3: FK: push_devices -> users CASCADE; push_outbox -> sites / announcements CASCADE; push_outbox.user_code FK YOK (K15)',
    JSON.stringify(fkRows) === JSON.stringify([
      { tbl: 'push_devices', ref: 'users', confdeltype: 'c' },
      { tbl: 'push_outbox', ref: 'announcements', confdeltype: 'c' },
      { tbl: 'push_outbox', ref: 'sites', confdeltype: 'c' },
    ]), fkRows);
  const violation = async (sql, params) => { try { await q(sql, params); return null; } catch (error) { return error.code; } };
  const sA = await mkSite(3, 'Sema Sitesi');
  check('A4: CHECK: platform / install_id / jeton uzunlugu; outbox status-skip_reason tutarliligi; sessiz saat baslangic = bitis',
    (await violation(`INSERT INTO push_devices (user_code, install_id, platform, fcm_token) VALUES ($1, 'kisa', 'android', $2)`, [sA.users[0], tokenOf(1)])) === '23514'
      && (await violation(`INSERT INTO push_devices (user_code, install_id, platform, fcm_token) VALUES ($1, $2, 'web', $3)`, [sA.users[0], installOf(1), tokenOf(1)])) === '23514'
      && (await violation(`INSERT INTO push_devices (user_code, install_id, platform, fcm_token) VALUES ($1, $2, 'android', 'kisa')`, [sA.users[0], installOf(1)])) === '23514'
      && (await violation(`INSERT INTO notification_preferences (user_code, push_quiet_start, push_quiet_end) VALUES ($1, 600, 600)`, [sA.users[0]])) === '23514'
      && (await violation(`INSERT INTO notification_preferences (user_code, push_quiet_start) VALUES ($1, 1440)`, [sA.users[0]])) === '23514');
  const ann0 = await publish(sA.code);
  check('A5: outbox: skipped iken skip_reason zorunlu; user_code FK YOK (olmayan kullanici yazilabilir, temizlik acik); UNIQUE (announcement_id, user_code)',
    (await violation(`INSERT INTO push_outbox (kind, site_code, announcement_id, user_code, importance, status, expires_at) VALUES ('announcement', $1, $2, 999999, 'normal', 'skipped', NOW())`, [sA.code, ann0.id])) === '23514'
      && (await violation(`INSERT INTO push_outbox (kind, site_code, announcement_id, user_code, importance, expires_at) VALUES ('announcement', $1, $2, 999999, 'normal', NOW())`, [sA.code, ann0.id])) === null
      && (await violation(`INSERT INTO push_outbox (kind, site_code, announcement_id, user_code, importance, expires_at) VALUES ('announcement', $1, $2, 999999, 'normal', NOW())`, [sA.code, ann0.id])) === '23505');
  await q(`DELETE FROM push_outbox WHERE user_code = 999999`);
  // ensureDbSchema idempotans + eksik nesne tamamlama (yalniz katalog sorgusu; eksikse yalniz o nesne)
  hooks.log = [];
  await ensureDbSchema();
  const pushDdl = hooks.log.filter((entry) => /push_(devices|outbox)|push_quiet|push_show_preview/.test(entry.text ?? '') && /^\s*(CREATE|ALTER|DO)/.test(entry.text ?? ''));
  hooks.log = null;
  check('A6: ikinci ensureDbSchema push nesnelerine HIC DDL gondermez (yalniz katalog sorgusu)', pushDdl.length === 0, pushDdl.map((e) => e.text.slice(0, 60)));
  await q(`DROP INDEX idx_push_outbox_created`);
  await q(`ALTER TABLE notification_preferences DROP CONSTRAINT chk_notification_preferences_push_quiet`);
  const client = await pool.connect();
  try {
    await ensurePushSchema(client);
  } finally {
    client.release();
  }
  const restored = (await q(`SELECT (SELECT COUNT(*)::int FROM pg_indexes WHERE indexname = 'idx_push_outbox_created') AS i, (SELECT COUNT(*)::int FROM pg_constraint WHERE conname = 'chk_notification_preferences_push_quiet') AS c`)).rows[0];
  check('A7: eksik indeks / CHECK ensurePushSchema ile tamamlanir', restored.i === 1 && restored.c === 1, restored);
  await q(`DELETE FROM users WHERE user_code = $1`, [sA.users[2]]).catch(() => {});

  // ============================================================================================================
  // B. Cihaz kaydi
  // ============================================================================================================
  console.log('--- B. cihaz kaydi ---');
  pushOff();
  const sB = await mkSite(14, 'Kayit Sitesi');
  const [u1, u2] = sB.users;
  const r1 = await register(u1);
  const r1b = await register(u1, 1, { token: tokenOf(u1, 99), notifications_enabled: false });
  let rows = (await q(`SELECT id, fcm_token, notifications_enabled, failure_count FROM push_devices WHERE user_code = $1`, [u1])).rows;
  check('B1: ayni kurulum yeniden kayit = UPSERT (tek satir, ayni id, jeton yenilendi, izin bilgisi yazildi); push kapaliyken de kaydeder (push_available:false)',
    rows.length === 1 && Number(rows[0].id) === r1.device_id && r1b.device_id === r1.device_id && rows[0].fcm_token === tokenOf(u1, 99) && rows[0].notifications_enabled === false && r1.push_available === false, rows);
  await register(u2, 1, { token: tokenOf(u1, 99) });
  rows = (await q(`SELECT user_code FROM push_devices WHERE fcm_token = $1`, [tokenOf(u1, 99)])).rows;
  check('B2: cihaz devri: ayni jeton B ile kaydolunca A\'nin satiri SILINIR, tek sahip B', rows.length === 1 && rows[0].user_code === u2 && (await q(`SELECT COUNT(*)::int AS n FROM push_devices WHERE user_code = $1`, [u1])).rows[0].n === 0, rows);
  for (let n = 1; n <= 12; n += 1) await register(sB.users[2], n);
  rows = (await q(`SELECT install_id FROM push_devices WHERE user_code = $1 ORDER BY install_id`, [sB.users[2]])).rows.map((r) => r.install_id);
  check('B3: kullanici basina en cok 10 cihaz; en eski iki kurulum dustu', rows.length === 10 && !rows.includes(installOf(sB.users[2], 1)) && !rows.includes(installOf(sB.users[2], 2)) && rows.includes(installOf(sB.users[2], 12)), rows);
  // ESZAMANLI ayni jeton farkli kullanici: 2'li yaris 20 tur -> hepsi basarili, tek sahip; 10'lu patlama -> tek sahip, yalniz 23505 (deadlock yok)
  let pairFailures = 0;
  let pairOwners = 0;
  const dl0 = deadlocksBefore();
  for (let round = 0; round < 20; round += 1) {
    const shared = `fcm-qa-ortak-jeton-${round}-${'y'.repeat(40)}`;
    const [a, b] = [sB.users[3 + (round % 4)], sB.users[8 + (round % 4)]];
    const settled = await Promise.allSettled([register(a, 50 + round, { token: shared }), register(b, 50 + round, { token: shared })]);
    pairFailures += settled.filter((s) => s.status === 'rejected').length;
    const owners = (await q(`SELECT user_code FROM push_devices WHERE fcm_token = $1`, [shared])).rows;
    if (owners.length === 1) pairOwners += 1;
  }
  check(`B4: eszamanli ayni jeton farkli kullanici (2'li, 20 tur): hepsi basarili (23505 tek yeniden deneme), her turda TEK sahip`, pairFailures === 0 && pairOwners === 20, { pairFailures, pairOwners });
  const burst = `fcm-qa-patlama-jetonu-${'z'.repeat(40)}`;
  const burstSettled = await Promise.allSettled(sB.users.slice(0, 10).map((user) => register(user, 77, { token: burst })));
  const burstErrors = burstSettled.filter((s) => s.status === 'rejected').map((s) => s.reason?.code);
  const burstOwners = (await q(`SELECT COUNT(*)::int AS n FROM push_devices WHERE fcm_token = $1`, [burst])).rows[0].n;
  check('B5: 10\'lu patlama ayni jeton: TEK sahip; hatalar yalniz 23505 (istemci yeniden dener), 40P01 YOK', burstOwners === 1 && burstErrors.every((code) => code === '23505') && hooks.deadlocks === dl0, { burstOwners, burstErrors });
  // kayit x hesap silme yarisi: silme commit ettiyse tombstone hesaba jeton YAZILMAZ
  let raceLeftovers = 0;
  let raceUnexpected = 0;
  const raceSite = await mkSite(10, 'Silme Yarisi');
  for (const user of raceSite.users) {
    const settled = await Promise.allSettled([register(user, 5), performAccountDeletion(user)]);
    for (const s of settled) if (s.status === 'rejected' && !['ACCOUNT_DELETED'].includes(s.reason?.code)) { raceUnexpected += 1; console.log(`   beklenmeyen: ${s.reason?.code} ${s.reason?.message}`); }
    raceLeftovers += (await q(`SELECT COUNT(*)::int AS n FROM push_devices WHERE user_code = $1`, [user])).rows[0].n;
  }
  check('B6: kayit x hesap silme (10 tur): silinen hesapta push_devices satiri KALMAZ; hata yalniz ACCOUNT_DELETED; 40P01 yok', raceLeftovers === 0 && raceUnexpected === 0 && hooks.deadlocks === dl0, { raceLeftovers, raceUnexpected });
  let deletedRegister = null;
  try { await register(raceSite.users[0], 9); } catch (error) { deletedRegister = error.code; }
  check('B7: silinmis hesaba kayit 401 ACCOUNT_DELETED', deletedRegister === 'ACCOUNT_DELETED', deletedRegister);
  const listed = await devicesMod.listPushDevices({ user_code: sB.users[2] });
  const ownCount = (await q(`SELECT COUNT(*)::int AS n FROM push_devices WHERE user_code = $1`, [sB.users[2]])).rows[0].n;
  check('B8: liste yalniz cagiranin cihazlari (B5 patlamasinda devredilen kurulum dahil degil); jeton YOK', listed.items.length === ownCount && ownCount >= 9 && !JSON.stringify(listed).includes('fcm-qa-jeton'), [listed.items.length, ownCount]);
  await devicesMod.deletePushDevice({ user_code: u1 }, installOf(sB.users[2], 12));
  const stillThere = (await q(`SELECT COUNT(*)::int AS n FROM push_devices WHERE user_code = $1 AND install_id = $2`, [sB.users[2], installOf(sB.users[2], 12)])).rows[0].n;
  await devicesMod.deletePushDevice({ user_code: sB.users[2] }, installOf(sB.users[2], 12));
  const gone = (await q(`SELECT COUNT(*)::int AS n FROM push_devices WHERE user_code = $1 AND install_id = $2`, [sB.users[2], installOf(sB.users[2], 12)])).rows[0].n;
  check('B9: IDOR yok: baskasinin install_id silmesi satira dokunmaz; sahibi silince gider (idempotent)', stillThere === 1 && gone === 0, { stillThere, gone });

  // ============================================================================================================
  // C. Yayin isleminde outbox (3000 alici)
  // ============================================================================================================
  console.log('--- C. yayin + outbox ---');
  const big = await mkSite(3000, 'Buyuk Push Sitesi');
  const bu = big.users;
  await bulkDevices(bu.slice(0, 2000));
  await bulkDevices(bu.slice(2000, 2500), { enabled: false });
  await q(`INSERT INTO notification_preferences (user_code, push_announcements) SELECT u, FALSE FROM unnest($1::int[]) AS u`, [bu.slice(0, 300)]);
  await q(`UPDATE users SET is_active = FALSE WHERE user_code = ANY($1::int[])`, [bu.slice(300, 400)]);
  await q('ANALYZE push_devices');
  pushOff();
  let started = Date.now();
  const offAnn = await publish(big.code);
  const offMs = Date.now() - started;
  const offRows = (await q(`SELECT COUNT(*)::int AS n FROM push_outbox WHERE announcement_id = $1`, [offAnn.id])).rows[0].n;
  check(`C1: PUSH_ENABLED=0 iken yayinda outbox'a HIC satir yazilmaz (alici ${offAnn.recipient_count}); ${offMs} ms`, offRows === 0 && offAnn.recipient_count === 3000, { offRows, recipients: offAnn.recipient_count });
  pushOn();
  started = Date.now();
  const onAnn = await publish(big.code);
  const onMs = Date.now() - started;
  const onRows = await outboxOf(onAnn.id);
  // beklenen: aktif + silinmemis + izinli cihazi var + tercih kapali degil -> 2000 cihazlidan ilk 300 tercih kapali ve 300-399 pasif: 2000 - 300 - 100 = 1600
  check(`C2: yayin isleminde outbox (normal): yalniz aktif + izinli cihazli + tercihi acik kullanicilar (1600); hepsi pending, expires_at = yayin + 24 sa; ${onMs} ms (< 15000)`,
    onRows.length === 1600 && onRows.every((r) => r.status === 'pending' && r.attempts === 0 && r.importance === 'normal')
      && Math.abs(new Date(onRows[0].expires_at).getTime() - new Date(onRows[0].created_at).getTime() - 24 * 3600000) < 60000 && onMs < 15000,
    { rows: onRows.length, onMs });
  console.log(`  bilgi: 3000 alicili yayin push kapali ${offMs} ms, acik ${onMs} ms (fark ${onMs - offMs} ms)`);
  const urgentAnn = await publish(big.code, 'urgent');
  const urgentRows = await outboxOf(urgentAnn.id);
  check('C3: ACIL duyuru push_announcements=false tercihini YOK SAYAR (1900 = 2000 cihazli - 100 pasif); expires_at = yayin + 48 sa',
    urgentRows.length === 1900 && Math.abs(new Date(urgentRows[0].expires_at).getTime() - new Date(urgentRows[0].created_at).getTime() - 48 * 3600000) < 60000, urgentRows.length);
  const tx = await pool.connect();
  let again;
  try {
    await tx.query('BEGIN');
    again = await outbox.enqueueAnnouncementPush(tx, { announcementId: onAnn.id, siteCode: big.code, importance: 'normal' });
    await tx.query('COMMIT');
  } finally {
    tx.release();
  }
  check('C4: UNIQUE (announcement_id, user_code): ayni duyuru icin ikinci yazim 0 satir (ciftlemez)', again === 0 && (await outboxOf(onAnn.id)).length === 1600, again);
  const explain = (await q(`EXPLAIN SELECT 1 FROM push_devices d WHERE d.user_code = $1 AND d.notifications_enabled`, [bu[5]])).rows.map((r) => r['QUERY PLAN']).join(' ');
  check('C5: cihaz varligi kontrolu kismi indeksle (idx_push_devices_user_enabled), Seq Scan yok', /idx_push_devices_user_enabled|uq_push_devices_user_install/.test(explain) && !/Seq Scan on push_devices/.test(explain), explain);
  await q(`DELETE FROM push_outbox WHERE announcement_id = ANY($1::bigint[])`, [[onAnn.id, urgentAnn.id]]);

  // kilit sirasi turlari: yayin x (kayit | tercih | hesap silme | isci) -> 40P01 = 0
  console.log('--- C. kilit sirasi turlari ---');
  const dlRace = deadlocksBefore();
  let raceErrors = [];
  google.state.send = () => ({ status: 200, json: {} });
  for (let round = 0; round < 15; round += 1) {
    const site = await mkSite(20, `Yaris ${round}`);
    await bulkDevices(site.users.slice(0, 15));
    const victim = site.users[19];
    const ops = [
      () => publish(site.code),
      () => register(site.users[16], 3),
      () => inbox.setNotificationPreferences({ user_code: site.users[2] }, { push_announcements: false, push_quiet_enabled: true }),
      () => performAccountDeletion(victim),
      () => worker.runPushQueue(),
      () => devicesMod.registerPushDevice({ user_code: site.users[1] }, { install_id: installOf(site.users[1], 1), platform: 'ios', token: tokenOf(site.users[1], 1) }),
    ];
    const settled = await Promise.allSettled(ops.map(async (op) => {
      await sleep(Math.floor(Math.random() * 4));
      return op();
    }));
    raceErrors = raceErrors.concat(settled.filter((s) => s.status === 'rejected').map((s) => `${s.reason?.code}:${String(s.reason?.message).slice(0, 80)}`));
    const leftover = (await q(`SELECT (SELECT COUNT(*)::int FROM push_devices WHERE user_code = $1) + (SELECT COUNT(*)::int FROM push_outbox WHERE user_code = $1) AS n`, [victim])).rows[0].n;
    if (leftover !== 0) raceErrors.push(`silinen hesapta push satiri kaldi: ${leftover}`);
  }
  check('C6: yayin x kayit x tercih x hesap silme x isci (15 tur): 40P01 = 0, beklenmeyen hata yok, silinen hesapta push satiri yok', hooks.deadlocks === dlRace && raceErrors.length === 0, { deadlocks: hooks.deadlocks - dlRace, raceErrors: raceErrors.slice(0, 5) });
  // yaris turlarindan kalan bekleyenler sonraki senaryolari etkilemesin
  await q(`DELETE FROM push_outbox`);

  // ============================================================================================================
  // D. Isci (sahte FCM, uctan uca)
  // ============================================================================================================
  console.log('--- D. isci ---');
  worker.resetPushQueueState();
  resetGoogle();
  const sD = await mkSite(12, 'Isci Sitesi');
  const du = sD.users;
  await bulkDevices(du.slice(0, 10));
  await q(`INSERT INTO push_devices (user_code, install_id, platform, fcm_token) VALUES ($1, $2, 'ios', $3)`, [du[0], installOf(du[0], 2), tokenOf(du[0], 2)]);
  await q(`INSERT INTO notification_preferences (user_code, push_show_preview) VALUES ($1, TRUE)`, [du[1]]);
  const annD = await publish(sD.code, 'normal', { title: 'Gizli QA basligi' });
  let summary = await worker.runPushQueue();
  let dRows = await outboxOf(annD.id);
  const bodies = fcmBodies();
  check('D1: uctan uca: 10 kullanici sent (11 cihaz istegi), sent_device_count, cihaz last_success_at; FCM proje + Bearer erisim jetonu',
    summary.sent === 10 && dRows.every((r) => r.status === 'sent' && r.sent_at) && dRows.find((r) => r.user_code === du[0]).sent_device_count === 2 && google.state.sendCount === 11
      && google.state.sendRequests.every((r) => r.project === 'siteyonetim-test1' && /^Bearer ya29\./.test(r.headers.authorization))
      && (await q(`SELECT COUNT(*)::int AS n FROM push_devices WHERE user_code = ANY($1::int[]) AND last_success_at IS NOT NULL`, [du])).rows[0].n === 11,
    { summary, sendCount: google.state.sendCount });
  check('D2: mesaj: varsayilan AYRINTISIZ (baslik site adi, sabit govde), push_show_preview acik kullanicida baslik; data yalniz izinli anahtarlar; collapse ann-<id>',
    bodies.filter((m) => m.notification.body === 'Yönetimden yeni bir duyuru var.').length === 10 && bodies.filter((m) => m.notification.body === 'Gizli QA basligi').length === 1
      && bodies.every((m) => m.notification.title === 'Isci Sitesi' && JSON.stringify(Object.keys(m.data).sort()) === JSON.stringify(['announcement_id', 'importance', 'site_code', 'type']) && m.android.collapse_key === `ann-${annD.id}` && !JSON.stringify(m.data).includes('Gizli')),
    bodies.slice(0, 2));
  const twice = await worker.runPushQueue();
  check('D3: ikinci tur bos (satir bir kez gonderilir)', twice.sent === 0 && google.state.sendCount === 11, twice);

  // iki isci yarisi + SKIP LOCKED + bayat talep
  resetGoogle();
  google.state.delayMs = 30;
  const annD2 = await publish(sD.code);
  const [w1, w2] = await Promise.all([worker.runPushQueue(), worker.runPushQueue()]);
  google.state.delayMs = 0;
  check('D4: iki isci ayni anda: biri advisory kilitle atlanir; her satir TEK kez gonderilir', [w1.skipped, w2.skipped].filter((s) => s === 'locked').length === 1 && google.state.sendCount === 11 && (await outboxOf(annD2.id)).every((r) => r.status === 'sent'), { w1, w2, sends: google.state.sendCount });
  resetGoogle();
  const annD3 = await publish(sD.code);
  const d3rows = await outboxOf(annD3.id);
  const holder = await pool.connect();
  await holder.query('BEGIN');
  await holder.query(`SELECT id FROM push_outbox WHERE id = ANY($1::bigint[]) FOR UPDATE`, [[d3rows[0].id, d3rows[1].id]]);
  summary = await worker.runPushQueue();
  const lockedStill = (await q(`SELECT status, claimed_at, attempts FROM push_outbox WHERE id = ANY($1::bigint[])`, [[d3rows[0].id, d3rows[1].id]])).rows;
  await holder.query('COMMIT');
  holder.release();
  const afterUnlock = await worker.runPushQueue();
  check('D5: FOR UPDATE SKIP LOCKED: baska islemin kilitledigi 2 satir atlanir (pending, talepsiz), digerleri gonderilir; kilit kalkinca gonderilir',
    summary.sent === 8 && lockedStill.every((r) => r.status === 'pending' && r.claimed_at === null && r.attempts === 0) && afterUnlock.sent === 2, { summary, afterUnlock, lockedStill });
  resetGoogle();
  const annD4 = await publish(sD.code);
  const d4rows = await outboxOf(annD4.id);
  await q(`UPDATE push_outbox SET claimed_at = NOW() - INTERVAL '11 minutes', attempts = 1 WHERE id = $1`, [d4rows[0].id]);
  await q(`UPDATE push_outbox SET claimed_at = NOW() - INTERVAL '2 minutes', attempts = 1 WHERE id = $1`, [d4rows[1].id]);
  await worker.runPushQueue();
  const stale = (await q(`SELECT id, status, attempts FROM push_outbox WHERE id = ANY($1::bigint[]) ORDER BY id`, [[d4rows[0].id, d4rows[1].id]])).rows;
  check('D6: bayat talep (10 dk) yeniden alinir; taze talepli satira dokunulmaz', stale.find((r) => r.id === d4rows[0].id).status === 'sent' && stale.find((r) => r.id === d4rows[0].id).attempts === 2 && stale.find((r) => r.id === d4rows[1].id).status === 'pending', stale);
  await q(`UPDATE push_outbox SET claimed_at = NULL WHERE id = $1`, [d4rows[1].id]);
  await worker.runPushQueue();

  // olu jeton / gecici hata / sessiz saat / ust sinir / geri cekme / pasif kullanici
  resetGoogle();
  const deadToken = tokenOf(du[2], 1);
  google.state.send = ({ body }) => {
    if (body?.message?.token === deadToken) return { status: 404, json: fcmError(404, 'NOT_FOUND', 'UNREGISTERED') };
    if (body?.message?.token === tokenOf(du[3], 1)) return { status: 503, json: fcmError(503, 'UNAVAILABLE', 'UNAVAILABLE') };
    return { status: 200, json: {} };
  };
  const minute = istanbulMinuteOfDay(Date.now());
  await q(`INSERT INTO notification_preferences (user_code, push_quiet_enabled, push_quiet_start, push_quiet_end) VALUES ($1, TRUE, $2, $3)
           ON CONFLICT (user_code) DO UPDATE SET push_quiet_enabled = TRUE, push_quiet_start = $2, push_quiet_end = $3`, [du[4], (minute + 1440 - 30) % 1440, (minute + 30) % 1440]);
  await q(`UPDATE users SET is_active = FALSE WHERE user_code = $1`, [du[5]]);
  const annD5 = await publish(sD.code);
  await q(`UPDATE users SET is_active = FALSE WHERE user_code = $1`, [du[6]]); // yayindan SONRA pasiflesen
  // gunluk ust sinir (varsayilan 8): du[7] bugun 4 duyuru aldi; baska duyurulara bagli 4 'sent' satiri daha eklenir -> 8 (diger kullanicilar 4'te kalir)
  for (const other of [ann0, offAnn, onAnn, urgentAnn]) {
    await q(`INSERT INTO push_outbox (kind, site_code, announcement_id, user_code, importance, status, sent_at, expires_at) SELECT 'announcement', site_code, id, $2, 'normal', 'sent', NOW(), NOW() + INTERVAL '1 day' FROM announcements WHERE id = $1`, [other.id, du[7]]);
  }
  const sentToday = (await q(`SELECT COUNT(*)::int AS n FROM push_outbox WHERE user_code = $1 AND status = 'sent' AND importance = 'normal'`, [du[7]])).rows[0].n;
  await worker.runPushQueue();
  const d5 = Object.fromEntries((await outboxOf(annD5.id)).map((r) => [r.user_code, r]));
  const quietRow = d5[du[4]];
  check('D7: olu jeton -> cihaz satiri SILINDI ve skipped/no_device', d5[du[2]].status === 'skipped' && d5[du[2]].skip_reason === 'no_device' && (await q(`SELECT COUNT(*)::int AS n FROM push_devices WHERE fcm_token = $1`, [deadToken])).rows[0].n === 0, d5[du[2]]);
  check('D8: gecici hata (503) -> pending, attempts 1, not_before ~ +60 sn, cihaz failure_count 1', d5[du[3]].status === 'pending' && d5[du[3]].attempts === 1 && Math.abs(new Date(d5[du[3]].not_before).getTime() - Date.now() - 60000) < 15000
    && (await q(`SELECT failure_count, last_error_code FROM push_devices WHERE fcm_token = $1`, [tokenOf(du[3], 1)])).rows[0].failure_count === 1, d5[du[3]]);
  check('D9: sessiz saat (Istanbul, simdi pencerede): pending kalir, deneme DUSMEZ, not_before = pencere sonu (~ +30 dk)', quietRow.status === 'pending' && quietRow.attempts === 0 && Math.abs(new Date(quietRow.not_before).getTime() - Date.now() - 30 * 60000) < 70000, quietRow);
  check('D10: yayindan once pasif -> outbox satiri hic yok; yayindan SONRA pasif -> skipped/inactive', d5[du[5]] === undefined && d5[du[6]].status === 'skipped' && d5[du[6]].skip_reason === 'inactive', [d5[du[5]], d5[du[6]]]);
  check(`D11: gunluk ust sinir (varsayilan 8, Istanbul gunu, bugun ${sentToday} sent) -> skipped/capped; sinirin altindaki kullanici gonderildi`,
    sentToday === 8 && d5[du[7]].status === 'skipped' && d5[du[7]].skip_reason === 'capped' && d5[du[8]].status === 'sent', [d5[du[7]], d5[du[8]]?.status]);
  const urgentD = await publish(sD.code, 'urgent');
  await worker.runPushQueue();
  const ud = Object.fromEntries((await outboxOf(urgentD.id)).map((r) => [r.user_code, r]));
  check('D12: ACIL sessiz saati ve ust siniri asar (gonderildi)', ud[du[4]]?.status === 'sent' && ud[du[7]]?.status === 'sent', [ud[du[4]], ud[du[7]]]);
  const annD6 = await publish(sD.code);
  await annSvc.withdrawAnnouncement({ siteCode: sD.code, id: annD6.id, actor: superActor });
  await worker.runPushQueue();
  const withdrawn = await outboxOf(annD6.id);
  check('D13: geri cekilen duyurunun bekleyenleri skipped/withdrawn', withdrawn.length > 0 && withdrawn.every((r) => r.status === 'skipped' && r.skip_reason === 'withdrawn'), countBy(withdrawn, 'status'));
  check('D14: sahte FCM\'e giden hicbir istekte duyuru basligi data icinde yok; badge yok', fcmBodies().every((m) => !JSON.stringify(m.data).includes('QA push') && !JSON.stringify(m).includes('badge')));

  // ============================================================================================================
  // E. Hesap silme kancasi, bakim, tercihler, disa aktarma, durum, HTTP
  // ============================================================================================================
  console.log('--- E. hesap silme / bakim / tercih / disa aktarma / durum / HTTP ---');
  const sE = await mkSite(6, 'Temizlik Sitesi');
  const eu = sE.users;
  await bulkDevices(eu);
  const annE = await publish(sE.code);
  const victimRows = (await q(`SELECT (SELECT COUNT(*)::int FROM push_devices WHERE user_code = $1) AS d, (SELECT COUNT(*)::int FROM push_outbox WHERE user_code = $1) AS o`, [eu[0]])).rows[0];
  await performAccountDeletion(eu[0]);
  const afterDelete = (await q(`SELECT (SELECT COUNT(*)::int FROM push_devices WHERE user_code = $1) AS d, (SELECT COUNT(*)::int FROM push_outbox WHERE user_code = $1) AS o`, [eu[0]])).rows[0];
  check('E1: hesap silme AYNI islemde push_devices + push_outbox satirlarini siler (CASCADE calismaz: kullanici satiri kalir)', victimRows.d === 1 && victimRows.o === 1 && afterDelete.d === 0 && afterDelete.o === 0, { victimRows, afterDelete });

  await q(`UPDATE push_outbox SET status = 'sent', sent_at = NOW(), created_at = NOW() - INTERVAL '15 days' WHERE announcement_id = $1 AND user_code = $2`, [annE.id, eu[1]]);
  await q(`UPDATE push_outbox SET expires_at = NOW() - INTERVAL '1 minute' WHERE announcement_id = $1 AND user_code = $2`, [annE.id, eu[2]]);
  await q(`INSERT INTO push_outbox (kind, site_code, announcement_id, user_code, importance, expires_at) VALUES ('announcement', $1, $2, 987654, 'normal', NOW() + INTERVAL '1 day')`, [sE.code, annE.id]);
  await q(`UPDATE push_devices SET last_seen_at = NOW() - INTERVAL '61 days' WHERE user_code = $1`, [eu[3]]);
  await q(`UPDATE push_devices SET failure_count = 5, last_success_at = NOW() - INTERVAL '31 days' WHERE user_code = $1`, [eu[4]]);
  await q(`UPDATE push_devices SET failure_count = 7, last_success_at = NOW() - INTERVAL '2 days' WHERE user_code = $1`, [eu[5]]);
  const maintenance = await worker.runPushMaintenanceOnce();
  const mOut = Object.fromEntries((await outboxOf(annE.id)).map((r) => [r.user_code, r]));
  const mDev = (await q(`SELECT user_code FROM push_devices WHERE user_code = ANY($1::int[]) ORDER BY user_code`, [eu])).rows.map((r) => r.user_code);
  check('E2: bakim: 14 gunluk biten satir silindi; suresi gecen pending -> expired; olmayan kullanicinin outbox satiri silindi',
    mOut[eu[1]] === undefined && mOut[eu[2]]?.status === 'expired' && mOut[987654] === undefined, { maintenance, keys: Object.keys(mOut) });
  check('E3: bakim: 60 gun hareketsiz ve kalici hatali (>= 5, 30 gundur basarisiz) cihazlar silindi; yakinda basarili hatali cihaz KALDI',
    !mDev.includes(eu[3]) && !mDev.includes(eu[4]) && mDev.includes(eu[5]) && mDev.includes(eu[1]), mDev);

  const prefUser = eu[1];
  const putBody = await inbox.setNotificationPreferences({ user_code: prefUser }, { push_quiet_enabled: true, push_quiet_start: '22:15', push_show_preview: true });
  const stored = (await q(`SELECT email_announcements, push_announcements, push_show_preview, push_quiet_enabled, push_quiet_start, push_quiet_end FROM notification_preferences WHERE user_code = $1`, [prefUser])).rows[0];
  let sameErr = null;
  try { await inbox.setNotificationPreferences({ user_code: prefUser }, { push_quiet_end: '22:15' }); } catch (error) { sameErr = error.code; }
  const legacy = await inbox.setNotificationPreferences({ user_code: prefUser }, { email_announcements: false });
  const storedAfter = (await q(`SELECT email_announcements, push_quiet_start, push_show_preview FROM notification_preferences WHERE user_code = $1`, [prefUser])).rows[0];
  const prefBody = await inbox.getNotificationPreferences({ user_code: prefUser });
  check('E4: tercihler KISMI (yalniz gonderilen push alanlari), "HH:MM" <-> dakika; bitis = saklı baslangic -> 400; eski istemci (yalniz e-posta) push alanlarini bozmaz; GET push_devices sayisi',
    stored.push_quiet_start === 1335 && stored.push_quiet_end === 420 && stored.push_show_preview === true && stored.email_announcements === true && sameErr === 'INVALID_BODY'
      && storedAfter.email_announcements === false && storedAfter.push_quiet_start === 1335 && storedAfter.push_show_preview === true
      && prefBody.push_quiet.start === '22:15' && prefBody.push_quiet.end === '07:00' && prefBody.push_devices === 1 && prefBody.push_available === true && legacy.push_quiet.enabled === true && putBody.push_quiet.start === '22:15' && putBody.push_show_preview === true,
    { stored, storedAfter, prefBody });

  const exportData = (await collectPersonalData(prefUser)).data;
  check('E5: kisisel veri disa aktarma: push_devices (platform, surum, tarihler) — jeton / kurulum kimligi YOK; excluded notu',
    Array.isArray(exportData.push_devices) && exportData.push_devices.length === 1 && exportData.push_devices[0].platform === 'android'
      && !JSON.stringify(exportData).includes('fcm-qa-jeton') && !JSON.stringify(exportData).includes('qa-kurulum') && exportData.excluded.some((line) => /bildirim jetonu/.test(line)),
    exportData.push_devices);

  const status = await worker.getPushStatus();
  check('E6: /admin/push/status: enabled/configured/project_id + sayilar; sir / e-posta / jeton yok',
    status.enabled === true && status.configured === true && status.project_id === 'siteyonetim-test1' && status.devices_total > 0 && status.sent_24h > 0
      && !JSON.stringify(status).includes(TEST_CLIENT_EMAIL) && !JSON.stringify(status).includes('fcm-qa'), status);

  // HTTP: gercek authRequired + gercek JWT (hiz sinirlayicilar devre disi; birim testlerinde sinanir)
  const express = (await import('express')).default;
  const { signAccessToken } = await import('../src/jwt.js');
  const { requireSuperUser } = await import('../src/middlewares/auth_middleware.js');
  const { pushRouter } = await import('../src/modules/push_routes.js');
  for (const layer of pushRouter.stack) {
    if (!layer.route) continue;
    const stack = layer.route.stack;
    for (let i = 1; i < stack.length - 1; i += 1) if (stack[i].handle !== requireSuperUser) stack[i].handle = (_req, _res, next) => next();
  }
  const app = express();
  app.use(express.json());
  app.use(pushRouter);
  const server = await new Promise((resolve) => { const s = http.createServer(app); s.listen(0, '127.0.0.1', () => resolve(s)); });
  const base = `http://127.0.0.1:${server.address().port}`;
  const tokenFor = async (userCode) => {
    const row = (await q(`SELECT user_code AS id, email, role, password_hash FROM users WHERE user_code = $1`, [userCode])).rows[0];
    return signAccessToken({ id: row.id, email: row.email, role: row.role }, { passwordHash: row.password_hash });
  };
  const call = async (method, urlPath, userCode, body) => {
    const response = await fetch(`${base}${urlPath}`, { method, headers: { 'content-type': 'application/json', authorization: `Bearer ${await tokenFor(userCode)}` }, body: body === undefined ? undefined : JSON.stringify(body) });
    const text = await response.text();
    return { status: response.status, body: text ? JSON.parse(text) : null, text };
  };
  const httpUser = eu[2];
  const put = await call('PUT', '/app/push/devices', httpUser, { install_id: installOf(httpUser, 7), platform: 'ios', token: tokenOf(httpUser, 7), app_version: '2.0.0' });
  const listRes = await call('GET', '/app/push/devices', httpUser);
  resetGoogle();
  const testRes = await call('POST', '/app/push/test', httpUser, {});
  const statusRes = await call('GET', '/admin/push/status', httpUser);
  const superStatus = await call('GET', '/admin/push/status', 10001);
  pushOff();
  const offTest = await call('POST', '/app/push/test', httpUser, {});
  check('E7: HTTP (gercek kimlik): kayit 200 { ok, device_id, push_available }, liste jetonsuz, test bildirimi { ok, sent, failed }, durum yalniz super, push kapaliyken test 503 PUSH_UNAVAILABLE',
    put.status === 200 && put.body.ok === true && Number.isInteger(put.body.device_id) && put.body.push_available === true
      && listRes.status === 200 && listRes.body.items.some((i) => i.install_id === installOf(httpUser, 7)) && !listRes.text.includes('fcm-qa')
      && testRes.status === 200 && testRes.body.ok === true && testRes.body.sent >= 1 && google.state.sendRequests.every((r) => r.body.message.data.type === 'test')
      && statusRes.status === 403 && superStatus.status === 200 && offTest.status === 503 && offTest.body.code === 'PUSH_UNAVAILABLE',
    { put: put.body, test: testRes.body, statusRes: statusRes.status, offTest: offTest.body });
  await performAccountDeletion(eu[3]).catch(() => {});
  const deletedCall = await call('PUT', '/app/push/devices', eu[3], { install_id: installOf(eu[3], 8), platform: 'android', token: tokenOf(eu[3], 8) });
  check('E8: silinmis hesap (gercek authRequired): 401 ACCOUNT_DELETED, satir yazilmaz', deletedCall.status === 401 && (await q(`SELECT COUNT(*)::int AS n FROM push_devices WHERE user_code = $1`, [eu[3]])).rows[0].n === 0, deletedCall.body);
  await new Promise((resolve) => server.close(resolve));

  // ============================================================================================================
  // G. Inceleme duzeltmeleri (iki bagimsiz inceleme): indeksler, jeton 2048, 10 cihaz yarisi, site acil siniri, ciplak 404, toplu olu jeton
  //    korumasi, 429 duraklamasi, zehirli satir, alici bagi, TTL, hesap silme x isci kilit sirasi
  // ============================================================================================================
  console.log('--- G. inceleme duzeltmeleri ---');
  pushOn();
  worker.resetPushQueueState();
  resetGoogle();

  // G1: (user_code) / (site_code) indeksleri; hesap silmedeki DELETE tablo taramaz
  const siteIdx = await mkSite(1, 'Indeks Sitesi');
  const idxAnn = await publish(siteIdx.code);
  await q(
    `INSERT INTO push_outbox (kind, site_code, announcement_id, user_code, importance, status, skip_reason, expires_at)
     SELECT 'announcement', $1, $2, 900000 + g, 'normal', 'skipped', 'pref', NOW() + INTERVAL '1 day' FROM generate_series(1, 20000) g`,
    [siteIdx.code, idxAnn.id],
  );
  await q('ANALYZE push_outbox');
  const idxNames = (await q(`SELECT indexname FROM pg_indexes WHERE tablename = 'push_outbox' AND indexname IN ('idx_push_outbox_user', 'idx_push_outbox_site', 'idx_push_outbox_urgent_site') ORDER BY 1`)).rows.map((r) => r.indexname);
  const delPlan = (await q(`EXPLAIN DELETE FROM push_outbox WHERE id IN (SELECT id FROM push_outbox WHERE user_code = 900123 ORDER BY id FOR UPDATE)`)).rows.map((r) => r['QUERY PLAN']).join(' | ');
  const urgentPlan = (await q(`EXPLAIN ${outbox.URGENT_SITE_COUNT_SQL}`, [siteIdx.code, idxAnn.id])).rows.map((r) => r['QUERY PLAN']).join(' | ');
  check('G1: push_outbox (user_code), (site_code) ve kismi acil (site_code, created_at) indeksleri var; hesap silmedeki DELETE ... WHERE user_code ve site acil sayimi indeksle (Seq Scan yok, 20 bin satir)',
    idxNames.length === 3 && /idx_push_outbox_user/.test(delPlan) && !/Seq Scan on push_outbox/.test(delPlan) && /idx_push_outbox_urgent_site/.test(urgentPlan) && !/Seq Scan on push_outbox/.test(urgentPlan),
    { idxNames, delPlan, urgentPlan });
  await q(`DELETE FROM push_outbox WHERE announcement_id = $1`, [idxAnn.id]);

  // G2: jeton uzunlugu 2048 (tekil btree satir siniri)
  const tokUser = siteIdx.users[0];
  const longErr = await violation(`INSERT INTO push_devices (user_code, install_id, platform, fcm_token) VALUES ($1, $2, 'android', $3)`, [tokUser, installOf(tokUser, 40), 'a'.repeat(2049)]);
  const okLong = await register(tokUser, 41, { token: 'b'.repeat(2048) });
  let tooLong = null;
  try { await register(tokUser, 42, { token: 'c'.repeat(2049) }); } catch (error) { tooLong = error.code; }
  check('G2: fcm_token CHECK 20-2048 (2049 -> 23514); 2048 karakterlik jeton tekil dizine sigar; dogrulayici 2049\'u 400 INVALID_BODY ile reddeder',
    longErr === '23514' && Number.isInteger(okLong.device_id) && tooLong === 'INVALID_BODY', { longErr, tooLong });

  // G3: 10 cihaz siniri yarisi (kullanici basina advisory kilit): 9 cihaz + 2 eszamanli yeni kurulum -> 10
  const raceUsers = (await mkSite(5, 'On Cihaz Yarisi')).users;
  const counts10 = [];
  for (const user of raceUsers) {
    for (let n = 1; n <= 9; n += 1) await register(user, n);
    await Promise.all([register(user, 10), register(user, 11)]);
    counts10.push((await q(`SELECT COUNT(*)::int AS n FROM push_devices WHERE user_code = $1`, [user])).rows[0].n);
  }
  check('G3: 9 cihaz + 2 eszamanli yeni kurulum (5 kullanici): her kullanicida TAM 10 cihaz (kullanici basina advisory kilit)', counts10.every((n) => n === 10), counts10);

  // G4: site basina acil siniri (varsayilan 3): 4. acil duyurunun satirlari NORMAL (tercih + 24 sa)
  const sG = await mkSite(6, 'Acil Sinir Sitesi');
  await bulkDevices(sG.users);
  await q(`INSERT INTO notification_preferences (user_code, push_announcements) VALUES ($1, FALSE)`, [sG.users[0]]);
  const urgentRuns = [];
  for (let i = 0; i < 4; i += 1) urgentRuns.push(await outboxOf((await publish(sG.code, 'urgent')).id));
  const lastUrgent = urgentRuns[3];
  check('G4: site basina gunluk ACIL siniri (3): ilk 3 acil duyuru acil (tercih yok sayilir, 6 satir, 48 sa); 4.\'su NORMAL yazilir (tercihi kapali kullanici dusulur, 5 satir, 24 sa)',
    urgentRuns.slice(0, 3).every((rows) => rows.length === 6 && rows.every((r) => r.importance === 'urgent'))
      && lastUrgent.length === 5 && lastUrgent.every((r) => r.importance === 'normal')
      && Math.abs(new Date(lastUrgent[0].expires_at).getTime() - new Date(lastUrgent[0].created_at).getTime() - 24 * 3600000) < 60000,
    urgentRuns.map((rows) => `${rows.length}:${[...new Set(rows.map((r) => r.importance))].join('/')}`));
  await q(`DELETE FROM push_outbox WHERE site_code = $1`, [sG.code]);

  // G5: ciplak 404 cihaz SILDIRMEZ (satir failed)
  resetGoogle();
  const s404 = await mkSite(2, 'Ciplak 404');
  await bulkDevices(s404.users);
  google.state.send = ({ body }) => (body?.message?.token === tokenOf(s404.users[0], 1) ? { status: 404, raw: '' } : { status: 200, json: {} });
  const ann404 = await publish(s404.code);
  await worker.runPushQueue();
  const rows404 = Object.fromEntries((await outboxOf(ann404.id)).map((r) => [r.user_code, r]));
  const kept404 = (await q(`SELECT COUNT(*)::int AS n FROM push_devices WHERE fcm_token = $1`, [tokenOf(s404.users[0], 1)])).rows[0].n;
  check('G5: govdesiz / kodsuz 404 olu jeton SAYILMAZ: cihaz KALIR, satir failed (HTTP_404); digeri sent', kept404 === 1 && rows404[s404.users[0]].status === 'failed' && rows404[s404.users[0]].last_error_code === 'HTTP_404' && rows404[s404.users[1]].status === 'sent', rows404[s404.users[0]]);

  // G6: toplu olu jeton korumasi (>= 20 gonderimin yarisindan fazlasi olu) -> silme YOK, devre kesici MASS_DEAD
  resetGoogle();
  worker.resetPushQueueState();
  const sMass = await mkSite(25, 'Toplu Olu');
  await bulkDevices(sMass.users);
  google.state.send = () => ({ status: 404, json: fcmError(404, 'NOT_FOUND', 'UNREGISTERED') });
  const annMass = await publish(sMass.code);
  const massSummary = await worker.runPushQueue();
  const massDevices = (await q(`SELECT COUNT(*)::int AS n FROM push_devices WHERE user_code = ANY($1::int[])`, [sMass.users])).rows[0].n;
  const massRows = await outboxOf(annMass.id);
  const massBlocked = await worker.runPushQueue();
  const massStatus = await worker.getPushStatus();
  check('G6: toplu olu jeton (25/25 UNREGISTERED): HICBIR cihaz silinmedi, satirlar pending + deneme iadesi (MASS_DEAD), devre kesici acildi (sonraki tur atlanir)',
    massSummary.massDead === true && massDevices === 25 && massRows.every((r) => r.status === 'pending' && r.attempts === 0 && r.last_error_code === 'MASS_DEAD')
      && massBlocked.skipped === 'breaker' && massStatus.last_error_code === 'MASS_DEAD',
    { massSummary, massDevices, massBlocked });
  worker.resetPushQueueState();
  google.state.send = () => ({ status: 200, json: {} });
  await q(`UPDATE push_outbox SET not_before = NOW() WHERE announcement_id = $1`, [annMass.id]);
  await worker.runPushQueue();
  check('G6b: devre kesici kapaninca (sorun giderildi) ayni satirlar gonderilir', (await outboxOf(annMass.id)).every((r) => r.status === 'sent'));

  // G7: 429 -> tur Retry-After kadar duraklar, satirlar deneme iadesiyle pending
  resetGoogle();
  worker.resetPushQueueState();
  const s429 = await mkSite(5, 'Kota Sitesi');
  await bulkDevices(s429.users);
  google.state.send = () => ({ status: 429, json: fcmError(429, 'RESOURCE_EXHAUSTED', 'QUOTA_EXCEEDED'), headers: { 'retry-after': '120' } });
  const ann429 = await publish(s429.code);
  const sum429 = await worker.runPushQueue({ concurrency: 1 });
  const rows429 = await outboxOf(ann429.id);
  const blocked429 = await worker.runPushQueue();
  check('G7: 429 + Retry-After 120: tek istekten sonra tur durdu, 5 satir pending, deneme 0, not_before ~ +120 sn; duraklama boyunca tur baslamaz',
    sum429.rateLimited === true && google.state.sendCount === 1 && rows429.length === 5 && rows429.every((r) => r.status === 'pending' && r.attempts === 0 && r.last_error_code === 'QUOTA_EXCEEDED' && Math.abs(new Date(r.not_before).getTime() - Date.now() - 120000) < 20000)
      && blocked429.skipped === 'breaker',
    { sum429, sends: google.state.sendCount, blocked429 });
  worker.resetPushQueueState();
  await q(`DELETE FROM push_outbox WHERE announcement_id = $1`, [ann429.id]);

  // G8 / G9 / G10: zehirli satir, alici bagi, TTL
  resetGoogle();
  google.state.send = () => ({ status: 200, json: {} });
  const sMix = await mkSite(4, 'Karma Sitesi');
  await bulkDevices(sMix.users);
  const annMix = await publish(sMix.code);
  const mix = Object.fromEntries((await outboxOf(annMix.id)).map((r) => [r.user_code, r]));
  await q(`UPDATE push_outbox SET attempts = 4 WHERE id = $1`, [mix[sMix.users[0]].id]);
  await q(`UPDATE site_people SET user_code = NULL WHERE user_code = $1 AND site_code = $2`, [sMix.users[1], sMix.code]);
  await q(`UPDATE push_outbox SET expires_at = NOW() + INTERVAL '30 minutes' WHERE id = $1`, [mix[sMix.users[2]].id]);
  await worker.runPushQueue();
  const mixAfter = Object.fromEntries((await outboxOf(annMix.id)).map((r) => [r.user_code, r]));
  const ttlMsg = fcmBodies().find((m) => m.token === tokenOf(sMix.users[2], 1));
  const ttlSeconds = Number(String(ttlMsg?.android?.ttl ?? '').replace('s', ''));
  check('G8: zehirli satir (attempts 4) talep aninda failed (MAX_ATTEMPTS), gonderilmez; kuyruk tikanmaz (digerleri gonderildi)',
    mixAfter[sMix.users[0]].status === 'failed' && mixAfter[sMix.users[0]].last_error_code === 'MAX_ATTEMPTS' && !fcmBodies().some((m) => m.token === tokenOf(sMix.users[0], 1)) && mixAfter[sMix.users[3]].status === 'sent', mixAfter[sMix.users[0]]);
  check('G9: kisi kaydindan ayrilan (alici bagi kalmayan) kullaniciya bekleyen push gitmez: skipped/withdrawn', mixAfter[sMix.users[1]].status === 'skipped' && mixAfter[sMix.users[1]].skip_reason === 'withdrawn', mixAfter[sMix.users[1]]);
  check(`G10: ttl = min(varsayilan, expires_at - simdi): 30 dk kalan satirin FCM ttl'i ${ttlSeconds} sn (1700-1800); apns-expiration ayni sureyle`,
    ttlSeconds >= 1700 && ttlSeconds <= 1800 && Math.abs(Number(ttlMsg.apns.headers['apns-expiration']) - Math.floor(Date.now() / 1000) - ttlSeconds) < 30, ttlMsg?.android);

  // G11: hesap silme x isci (sonuc yazimi / cihaz guncellemesi) kilit sirasi: 10 tur, 40P01 = 0
  const dlG = hooks.deadlocks;
  let g11Errors = [];
  let g11Left = 0;
  google.state.delayMs = 5;
  for (let round = 0; round < 10; round += 1) {
    worker.resetPushQueueState();
    const site = await mkSite(6, `Silme x Isci ${round}`);
    await bulkDevices(site.users);
    await q(
      `INSERT INTO push_devices (user_code, install_id, platform, fcm_token) SELECT u, 'qa-kurulum-ek-' || u, 'ios', 'fcm-qa-jeton-ek-' || u || '-' || repeat('w', 40) FROM unnest($1::int[]) AS u`,
      [site.users],
    );
    for (let i = 0; i < 3; i += 1) await publish(site.code);
    const settled = await Promise.allSettled([worker.runPushQueue(), performAccountDeletion(site.users[0]), performAccountDeletion(site.users[1])]);
    g11Errors = g11Errors.concat(settled.filter((s) => s.status === 'rejected').map((s) => `${s.reason?.code}:${String(s.reason?.message).slice(0, 60)}`));
    g11Left += (await q(`SELECT (SELECT COUNT(*)::int FROM push_devices WHERE user_code = ANY($1::int[])) + (SELECT COUNT(*)::int FROM push_outbox WHERE user_code = ANY($1::int[])) AS n`, [site.users.slice(0, 2)])).rows[0].n;
  }
  google.state.delayMs = 0;
  check('G11: hesap silme x isci (10 tur, kullanici basina 3 bekleyen + 2 cihaz): 40P01 = 0, hata yok, silinen hesaplarda push satiri yok (id sirali kilit)',
    hooks.deadlocks === dlG && g11Errors.length === 0 && g11Left === 0, { deadlocks: hooks.deadlocks - dlG, g11Errors: g11Errors.slice(0, 3), g11Left });
  worker.resetPushQueueState();

  // G12 (2. tur Y1): yanlis projenin hizmet hesabi. Hesap YENIDEN yuklenir (iz sifirlanir), her jetona SENDER_ID_MISMATCH: kucuk gruplar ve test
  // bildirimi cihaz SILDIRMEZ (failed / no_device degil, deneme iadesiyle pending); son basaridan beri 20 olu -> MASS_DEAD + devre kesici.
  pushOn();
  worker.resetPushQueueState();
  resetGoogle();
  google.state.send = () => ({ status: 403, json: fcmError(403, 'PERMISSION_DENIED', 'SENDER_ID_MISMATCH') });
  const wrongSites = [];
  let wrongMass = null;
  let firstWrongRun = null;
  for (let i = 0; i < 7 && !wrongMass; i += 1) {
    const site = await mkSite(4, `Yanlis Proje ${i}`);
    await bulkDevices(site.users);
    wrongSites.push(site);
    const ann = await publish(site.code);
    const result = await worker.runPushQueue();
    if (i === 0) {
      firstWrongRun = { result, rows: await outboxOf(ann.id) };
      const testRes = await devicesMod.sendTestPush({ user_code: site.users[0] });
      firstWrongRun.test = testRes;
    }
    if (result.massDead) wrongMass = result;
  }
  const wrongUsers = wrongSites.flatMap((site) => site.users);
  const wrongDevices = (await q(`SELECT COUNT(*)::int AS n, COALESCE(MAX(failure_count), 0)::int AS f FROM push_devices WHERE user_code = ANY($1::int[])`, [wrongUsers])).rows[0];
  const wrongBlocked = await worker.runPushQueue();
  check('G12: yanlis proje (her jetona SENDER_ID_MISMATCH, basari yok): ilk kucuk grup ve test bildirimi cihaz SILMEZ (satir pending + deneme iadesi, failure_count 0); son basaridan beri 20 olu -> MASS_DEAD + devre kesici; hicbir cihaz silinmedi',
    firstWrongRun.result.massDead === false && firstWrongRun.rows.every((r) => r.status === 'pending' && r.attempts === 0 && r.last_error_code === 'SENDER_ID_MISMATCH')
      && firstWrongRun.test.ok === false && firstWrongRun.test.failed === 1
      && wrongMass?.massDead === true && wrongMass?.breaker === true && wrongBlocked.skipped === 'breaker'
      && wrongDevices.n === wrongUsers.length && wrongDevices.f === 0,
    { first: firstWrongRun?.result, test: firstWrongRun?.test, wrongMass, wrongDevices, sites: wrongSites.length });
  // dogru hesaba gecildi (sorun giderildi): ayni satirlar gonderilir
  worker.resetPushQueueState();
  google.state.send = () => ({ status: 200, json: {} });
  await q(`UPDATE push_outbox SET not_before = NOW() WHERE user_code = ANY($1::int[]) AND status = 'pending'`, [wrongUsers]);
  await worker.runPushQueue();
  const wrongAfter = (await q(`SELECT status, COUNT(*)::int AS n FROM push_outbox WHERE user_code = ANY($1::int[]) GROUP BY status`, [wrongUsers])).rows;
  check('G12b: sorun giderilince bekleyen satirlarin hepsi gonderilir (cihazlar yerinde oldugu icin)', wrongAfter.length === 1 && wrongAfter[0].status === 'sent', wrongAfter);

  // G13 (2. tur Y2): gercek olu jetonlar basariyla karisik gelir (20 olu + 10 basari, %33): normal silme, devre kesici YOK
  resetGoogle();
  const sReal = await mkSite(30, 'Gercek Olu Jetonlar');
  await bulkDevices(sReal.users);
  const deadTokens = new Set(sReal.users.slice(0, 20).map((user) => tokenOf(user, 1)));
  google.state.send = ({ body }) => (deadTokens.has(body?.message?.token) ? { status: 404, json: fcmError(404, 'NOT_FOUND', 'UNREGISTERED') } : { status: 200, json: {} });
  const annReal = await publish(sReal.code);
  const realRun = await worker.runPushQueue();
  const realRows = await outboxOf(annReal.id);
  const realDevices = (await q(`SELECT COUNT(*)::int AS n FROM push_devices WHERE user_code = ANY($1::int[])`, [sReal.users])).rows[0].n;
  check('G13: 20 olu + 10 basari ayni grupta (basari orani %33 >= %5): 20 olu cihaz silindi, 20 satir skipped/no_device, 10 sent; MASS_DEAD / devre kesici YOK',
    realRun.massDead === false && realRun.breaker === false && realDevices === 10
      && realRows.filter((r) => r.status === 'skipped' && r.skip_reason === 'no_device').length === 20 && realRows.filter((r) => r.status === 'sent').length === 10,
    { realRun, realDevices });
  worker.resetPushQueueState();

  // ============================================================================================================
  // F. Gunluk gizliligi ve 40P01 toplami
  // ============================================================================================================
  const allLogs = [...serverErrors, ...logLines].join('\n');
  check('F1: sunucu gunlugunde kayit jetonu / client_email / ozel anahtar parcasi / erisim jetonu YOK',
    !allLogs.includes('fcm-qa-jeton') && !allLogs.includes('fcm-qa-ortak') && !allLogs.includes(TEST_CLIENT_EMAIL) && !allLogs.includes(privateKeyFragment()) && !allLogs.includes('ya29.'),
    allLogs.split('\n').filter((line) => /fcm-qa|ya29|iam\.gserviceaccount/.test(line)).slice(0, 3));
  check('F2: TUM kosuda 40P01 (deadlock) = 0', hooks.deadlocks === 0, hooks.deadlocks);

  await google.close();
  fs.rmSync(saDir, { recursive: true, force: true });
  await finishChild(pool);
}
