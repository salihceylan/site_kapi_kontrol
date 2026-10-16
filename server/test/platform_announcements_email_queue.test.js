// Duyuru e-posta kuyruğu (DB'siz): bellek içi sahte alıcı tablosu üzerinde grup boyutu, gruplar arası bekleme, talep (claim) işareti,
// deneme sayacı + geri çekilme, kalıcı/geçici SMTP hatası, talep anı denetimi (kişi etkin mi / adres aynı mı / bastırıldı mı), yayından
// kalkmış duyuru, bayat talep, SMTP yok -> failed, tek çalışan kilidi (iki-int), kapanış, log gizliliği. Gerçek SMTP'ye ASLA bağlanılmaz
// (gönderim kancası sahte). Sahte talep sorgusu gerçek koşulları UYGULAR (a.status = 'published', talep işareti, geri çekilme, deneme sınırı).
import { describe, it, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert/strict';
import { pool } from '../src/db.js';
import {
  EMAIL_BATCH_DELAY_MS,
  EMAIL_BATCH_SIZE,
  EMAIL_HASH_RETENTION_DAYS,
  EMAIL_QUEUE_LOCK_JOB,
  EMAIL_SEND_CONCURRENCY,
  emailQueueHooks,
  failStaleRows,
  hasPendingEmails,
  isPermanentSendError,
  kickEmailQueue,
  purgeStaleEmailHashes,
  resumeEmailQueue,
  runEmailQueue,
  stopEmailQueue,
} from '../src/modules/announcement_email_queue.js';
import { hashEmail } from '../src/modules/announcement_email_security.js';
import { ANNOUNCEMENT_LOCK_CLASS, ANNOUNCEMENT_LOCK_JOBS } from '../src/modules/announcement_lock.js';

process.env.JWT_SECRET ||= 'unit-test-secret-0123456789abcdef';

const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
const ok = (rows = [], rowCount = rows.length) => ({ rows, rowCount });

let rows; // sahte alıcı tablosu (aşağıdaki makeRows biçimi)
let log;
let lockHeldElsewhere;
let lockOps;
let lockParams;
let sent;
let sleeps;
let sendImpl;
let savedHooks;
let claimSalts;
let suppressionInserts;
const savedEnv = {};

const ENV_NAMES = ['SMTP_HOST', 'SMTP_USER', 'SMTP_PASSWORD', 'SMTP_FROM'];
const MINUTE = 60 * 1000;

function makeRows(count, { aid = 1, startPid = 1, annStatus = 'published' } = {}) {
  return Array.from({ length: count }, (_, i) => {
    const pid = startPid + i;
    const email = `kisi${pid}@example.com`;
    return {
      aid,
      pid,
      email,
      hash: hashEmail(email),
      attempts: 0,
      status: 'pending',
      claimedAt: null,
      nextAt: null,
      annStatus,
      personActive: true,
      currentEmail: email,
      suppressed: false,
      hasAccount: false,
    };
  });
}

const find = (aid, pid) => rows.find((r) => String(r.aid) === String(aid) && String(r.pid) === String(pid));
const staleBefore = (mins) => Date.now() - mins * MINUTE;
const isStale = (claimedAt, mins) => claimedAt !== null && claimedAt.getTime() < staleBefore(mins);

function emulate(sql, params) {
  if (/^SELECT pg_try_advisory_lock/.test(sql)) {
    lockOps.push('try');
    lockParams.push(params);
    return ok([{ locked: !lockHeldElsewhere }]);
  }
  if (/^SELECT pg_advisory_unlock/.test(sql)) {
    lockOps.push('unlock');
    return ok([{}]);
  }
  if (/^BEGIN$|^COMMIT$|^ROLLBACK$/.test(sql)) return ok();
  if (/^SELECT 1 FROM announcement_recipients r INNER JOIN announcements a ON a\.id = r\.announcement_id AND a\.status = 'published' WHERE r\.email_status = 'pending' AND \(r\.email_next_at IS NULL OR r\.email_next_at <= NOW\(\)\) AND \(r\.email_claimed_at IS NULL OR r\.email_claimed_at < NOW\(\) - make_interval\(mins => \$1::INTEGER\)\) LIMIT 1$/.test(sql)) {
    const work = rows.filter((r) => r.status === 'pending' && r.annStatus === 'published' && (r.nextAt === null || r.nextAt.getTime() <= Date.now()) && (r.claimedAt === null || isStale(r.claimedAt, params[0])));
    return ok(work.slice(0, 1).map(() => ({ '?column?': 1 })));
  }
  // failStaleRows (1): adresi olmayan + denemesi tükenmiş (taze talepler hariç)
  if (/^UPDATE announcement_recipients SET email_status = 'failed', email = NULL, email_claimed_at = NULL, email_next_at = NULL WHERE email_status = 'pending' AND \( email IS NULL OR \(email_attempts >= \$1 AND \(email_claimed_at IS NULL OR email_claimed_at < NOW\(\) - make_interval\(mins => \$2::INTEGER\)\)\) \)$/.test(sql)) {
    const [maxAttempts, staleMins] = params;
    const hit = rows.filter((r) => r.status === 'pending' && (r.email === null || (r.attempts >= maxAttempts && (r.claimedAt === null || isStale(r.claimedAt, staleMins)))));
    hit.forEach((r) => Object.assign(r, { status: 'failed', email: null, claimedAt: null, nextAt: null }));
    return ok([], hit.length);
  }
  // failStaleRows (2): yayından kalkmış duyurunun bayat talepleri
  if (/^UPDATE announcement_recipients r SET email_status = 'failed', email = NULL, email_hash = NULL, email_claimed_at = NULL, email_next_at = NULL FROM announcements a WHERE a\.id = r\.announcement_id AND a\.status <> 'published' AND r\.email_status = 'pending' AND \(r\.email_claimed_at IS NULL OR r\.email_claimed_at < NOW\(\) - make_interval\(mins => \$1::INTEGER\)\)$/.test(sql)) {
    const hit = rows.filter((r) => r.status === 'pending' && r.annStatus !== 'published' && (r.claimedAt === null || isStale(r.claimedAt, params[0])));
    hit.forEach((r) => Object.assign(r, { status: 'failed', email: null, hash: null, claimedAt: null, nextAt: null }));
    return ok([], hit.length);
  }
  // SMTP yapılandırılmamış: bekleyen her satır failed
  if (/^UPDATE announcement_recipients SET email_status = 'failed', email = NULL, email_claimed_at = NULL, email_next_at = NULL WHERE email_status = 'pending'$/.test(sql)) {
    const hit = rows.filter((r) => r.status === 'pending');
    hit.forEach((r) => Object.assign(r, { status: 'failed', email: null, claimedAt: null, nextAt: null }));
    return ok([], hit.length);
  }
  // talep sorgusu (GERÇEK koşullar uygulanır)
  if (/^SELECT r\.announcement_id, r\.person_id, r\.email, r\.email_hash, r\.email_attempts, a\.title, a\.body, a\.importance, s\.name AS site_name, pc\.person_active, pc\.has_account, pc\.current_email, \( EXISTS \(SELECT 1 FROM announcement_email_suppressions sup WHERE sup\.email_hash = r\.email_hash\) OR EXISTS \(SELECT 1 FROM unnest\(\$6::TEXT\[\]\) AS salts\(salt\) INNER JOIN announcement_email_suppressions sup ON sup\.email_hash = .* \) AS suppressed FROM announcement_recipients r/.test(sql)) {
    const [maxAttempts, doneA, doneP, limit, staleMins, salts] = params;
    claimSalts.push(salts);
    const done = new Set(doneA.map((a, i) => `${a}:${doneP[i]}`));
    const picked = rows
      .filter(
        (r) =>
          r.status === 'pending' &&
          r.email !== null &&
          r.attempts < maxAttempts &&
          r.annStatus === 'published' &&
          (r.claimedAt === null || isStale(r.claimedAt, staleMins)) &&
          (r.nextAt === null || r.nextAt.getTime() <= Date.now()) &&
          !done.has(`${r.aid}:${r.pid}`),
      )
      .sort((a, b) => a.aid - b.aid || a.pid - b.pid)
      .slice(0, limit);
    return ok(
      picked.map((r) => ({
        announcement_id: String(r.aid),
        person_id: String(r.pid),
        email: r.email,
        email_hash: r.hash,
        email_attempts: r.attempts,
        title: 'Başlık',
        body: 'Metin',
        importance: 'normal',
        site_name: 'Gül Sitesi',
        person_active: r.personActive,
        has_account: r.hasAccount,
        current_email: r.currentEmail,
        suppressed: r.suppressed,
      })),
    );
  }
  // talep anı: gönderilmeyecek satırlar (kişi pasif / adres değişti -> none; bastırılmış -> skipped_pref)
  if (/^UPDATE announcement_recipients r SET email_status = v\.st, email = NULL, email_hash = NULL, email_claimed_at = NULL, email_next_at = NULL FROM unnest\(\$1::BIGINT\[\], \$2::BIGINT\[\], \$3::TEXT\[\]\) AS v\(aid, pid, st\)/.test(sql)) {
    params[0].forEach((aid, i) => {
      const row = find(aid, params[1][i]);
      if (row) Object.assign(row, { status: params[2][i], email: null, hash: null, claimedAt: null, nextAt: null });
    });
    return ok([], params[0].length);
  }
  // talep işareti: deneme + 1, talep zamanı
  if (/^UPDATE announcement_recipients r SET email_attempts = r\.email_attempts \+ 1, email_claimed_at = NOW\(\), email_next_at = NULL FROM unnest\(\$1::BIGINT\[\], \$2::BIGINT\[\]\) AS v\(aid, pid\)/.test(sql)) {
    params[0].forEach((aid, i) => {
      const row = find(aid, params[1][i]);
      if (row) Object.assign(row, { attempts: row.attempts + 1, claimedAt: new Date(), nextAt: null });
    });
    return ok([], params[0].length);
  }
  // sonuç yazımı: yalnız hâlâ pending olan satırlar
  if (/^UPDATE announcement_recipients r SET email_status = x\.final_st, email = CASE WHEN x\.final_st = 'pending' THEN r\.email END, email_hash = CASE WHEN x\.orphaned THEN NULL ELSE r\.email_hash END, email_claimed_at = NULL, email_next_at = CASE WHEN x\.final_st = 'pending' THEN NOW\(\) \+ make_interval\(secs => v\.delay::DOUBLE PRECISION\) END FROM unnest\(\$1::BIGINT\[\], \$2::BIGINT\[\], \$3::TEXT\[\], \$4::INTEGER\[\]\) AS v\(aid, pid, st, delay\) INNER JOIN announcements a ON a\.id = v\.aid CROSS JOIN LATERAL \( SELECT CASE WHEN v\.st = 'pending' AND a\.status <> 'published' THEN 'failed' ELSE v\.st END AS final_st, \(v\.st = 'pending' AND a\.status <> 'published'\) AS orphaned \) x WHERE r\.announcement_id = v\.aid AND r\.person_id = v\.pid AND r\.email_status = 'pending'$/.test(sql)) {
    params[0].forEach((aid, i) => {
      const row = find(aid, params[1][i]);
      if (!row || row.status !== 'pending') return;
      const state = params[2][i];
      const orphaned = state === 'pending' && row.annStatus !== 'published';
      const finalState = orphaned ? 'failed' : state;
      Object.assign(row, {
        status: finalState,
        email: finalState === 'pending' ? row.email : null,
        hash: orphaned ? null : row.hash,
        claimedAt: null,
        nextAt: finalState === 'pending' ? new Date(Date.now() + params[3][i] * 1000) : null,
      });
    });
    return ok([], params[0].length);
  }
  // sessiz tuz geçişi (F3): bastırılmış adresin güncel tuzla özeti de listeye yazılır
  if (/^INSERT INTO announcement_email_suppressions \(email_hash\) SELECT unnest\(\$1::TEXT\[\]\) ON CONFLICT \(email_hash\) DO NOTHING$/.test(sql)) {
    suppressionInserts.push(...params[0]);
    return ok([], params[0].length);
  }
  // özet temizliği (gizlilik)
  if (/^UPDATE announcement_recipients r SET email_hash = NULL FROM announcements a WHERE a\.id = r\.announcement_id AND r\.email_hash IS NOT NULL AND r\.email_status <> 'pending' AND a\.published_at < NOW\(\) - make_interval\(days => \$1::INTEGER\)$/.test(sql)) {
    const hit = rows.filter((r) => r.hash !== null && r.status !== 'pending' && r.old === true);
    hit.forEach((r) => Object.assign(r, { hash: null }));
    return ok([], hit.length);
  }
  throw new Error(`BEKLENMEYEN SQL (sahte DB katı): ${sql.slice(0, 200)}`);
}

beforeEach(() => {
  rows = [];
  log = [];
  lockHeldElsewhere = false;
  lockOps = [];
  lockParams = [];
  sent = [];
  sleeps = [];
  claimSalts = [];
  suppressionInserts = [];
  sendImpl = async () => {};
  for (const name of ENV_NAMES) savedEnv[name] = process.env[name];
  Object.assign(process.env, { SMTP_HOST: 'smtp.invalid', SMTP_USER: 'u@example.invalid', SMTP_PASSWORD: 'x', SMTP_FROM: 'AHBU <n@example.invalid>' });
  savedHooks = { ...emailQueueHooks };
  emailQueueHooks.send = async (message) => {
    sent.push(message);
    return sendImpl(message);
  };
  emailQueueHooks.sleep = async (ms) => {
    sleeps.push(ms);
  };
  const run = (text, params) => {
    const sql = norm(text);
    log.push({ sql, params: params ?? [] });
    return emulate(sql, params ?? []);
  };
  pool.query = async (text, params) => run(text, params);
  pool.connect = async () => ({
    query: async (text, params) => run(text, params),
    on() {},
    off() {},
    release() {},
  });
  resumeEmailQueue();
  mock.method(console, 'error', () => {});
  mock.method(console, 'log', () => {});
});

afterEach(async () => {
  await stopEmailQueue();
  resumeEmailQueue();
  Object.assign(emailQueueHooks, savedHooks);
  for (const name of ENV_NAMES) {
    if (savedEnv[name] === undefined) delete process.env[name];
    else process.env[name] = savedEnv[name];
  }
  delete pool.query;
  delete pool.connect;
  mock.restoreAll();
});

describe('e-posta kuyruğu: gruplar, bekleme, sonuçlar', () => {
  it('sabitler: 20\'lik gruplar, gruplar arası >= 150 ms, paralellik 4, özet saklama 3 gün, kilit işi iki-int uzayında', () => {
    assert.equal(EMAIL_BATCH_SIZE, 20);
    assert.ok(EMAIL_BATCH_DELAY_MS >= 150);
    assert.equal(EMAIL_SEND_CONCURRENCY, 4);
    assert.equal(EMAIL_HASH_RETENTION_DAYS, 3);
    assert.equal(EMAIL_QUEUE_LOCK_JOB, ANNOUNCEMENT_LOCK_JOBS.emailQueue);
  });

  it('45 bekleyen satır -> 3 grup (20 + 20 + 5); her grup sonrası >= 150 ms bekleme; hepsi sent, email NULL, talep işareti kalkar; deneme sayısı 1', async () => {
    rows = makeRows(45);
    const summary = await runEmailQueue();
    assert.equal(summary.batches, 3);
    assert.equal(summary.sent, 45);
    assert.equal(sent.length, 45);
    assert.deepEqual(sleeps, [150, 150, 150]);
    assert.ok(rows.every((r) => r.status === 'sent' && r.email === null && r.attempts === 1 && r.claimedAt === null && r.nextAt === null));
    assert.ok(rows.every((r) => r.hash !== null), 'günlük adres sayımı için özet kalır');
    const claims = log.filter((q) => /^SELECT r\.announcement_id/.test(q.sql));
    assert.deepEqual(claims.slice(0, 3).map((q) => q.params[3]), [20, 20, 20]);
    assert.match(claims[0].sql, /FOR UPDATE OF r SKIP LOCKED/);
    assert.match(claims[0].sql, /a\.status = 'published'/);
    assert.match(claims[0].sql, /r\.email_attempts < \$1/);
    assert.match(claims[0].sql, /\(r\.email_claimed_at IS NULL OR r\.email_claimed_at < NOW\(\) - make_interval\(mins => \$5::INTEGER\)\)/);
    assert.match(claims[0].sql, /\(r\.email_next_at IS NULL OR r\.email_next_at <= NOW\(\)\)/);
    // bastırma: saklı özet VEYA adresin KANONİK özeti (güncel + eski tuzlar $6)
    assert.match(claims[0].sql, /EXISTS \(SELECT 1 FROM announcement_email_suppressions sup WHERE sup\.email_hash = r\.email_hash\) OR EXISTS \(SELECT 1 FROM unnest\(\$6::TEXT\[\]\) AS salts\(salt\)/);
    assert.match(claims[0].sql, /position\('\+' IN split_part\(r\.email, '@', 1\)\)/, 'kanonik adres: +etiket atılır');
    assert.match(claims[0].sql, /IN \('gmail\.com', 'googlemail\.com'\)/);
    assert.ok(Array.isArray(claims[0].params[5]) && claims[0].params[5].length >= 1 && claims[0].params[5].every((salt) => /^[0-9a-f]{64}$/.test(salt)));
    assert.equal(claims[0].params[0], 3);
    assert.equal(claims[0].params[4], 10);
  });

  it('gönderilen ileti: alıcı, site adı, başlık, metin, önem, hesap var mı ve abonelikten çık bağlantısı (adres ÖZETİNE bağlı) kancaya iletilir; paralellik en çok 4', async () => {
    rows = makeRows(8);
    rows[0].hasAccount = true;
    let active = 0;
    let peak = 0;
    sendImpl = async () => {
      active += 1;
      peak = Math.max(peak, active);
      await new Promise((resolve) => setImmediate(resolve));
      active -= 1;
    };
    await runEmailQueue();
    assert.deepEqual(Object.keys(sent[0]).sort(), ['body', 'hasAccount', 'importance', 'siteName', 'title', 'to', 'unsubscribeUrl']);
    assert.equal(sent[0].siteName, 'Gül Sitesi');
    assert.equal(sent[0].to, 'kisi1@example.com');
    assert.equal(sent[0].hasAccount, true);
    assert.equal(sent.find((m) => m.to === 'kisi2@example.com').hasAccount, false);
    const url = new URL(sent[0].unsubscribeUrl);
    assert.equal(url.pathname, '/public/announcement-unsubscribe');
    assert.ok(url.searchParams.get('t').startsWith(hashEmail('kisi1@example.com')));
    assert.ok(!sent[0].unsubscribeUrl.includes('kisi1'), 'bağlantıda düz adres yok');
    assert.ok(peak <= 4 && peak >= 2, `paralellik ${peak}`);
  });

  it('geçici SMTP hatası: satır pending kalır (adres korunur), deneme artar, 1 dk geri çekilme; AYNI turda ve geri çekilme dolmadan yeniden denenmez; 2. hata 5 dk; 3. hata failed + email NULL', async () => {
    rows = makeRows(3);
    sendImpl = async () => {
      throw Object.assign(new Error('adres a@b.com reddedildi'), { code: 'ECONNECTION' });
    };
    let summary = await runEmailQueue();
    assert.equal(sent.length, 3, 'her satır turda BİR kez denenir');
    assert.equal(summary.pendingRetry, 3);
    assert.ok(rows.every((r) => r.status === 'pending' && r.attempts === 1 && r.email !== null && r.claimedAt === null));
    const firstDelay = rows[0].nextAt.getTime() - Date.now();
    assert.ok(firstDelay > 55_000 && firstDelay <= 60_000, `1. geri çekilme ~60 sn: ${firstDelay}`);
    sent.length = 0;
    summary = await runEmailQueue();
    assert.equal(sent.length, 0, 'geri çekilme dolmadan yeniden denenmez (SMTP kesintisinde 3 deneme saniyeler içinde yanmaz)');
    assert.equal(summary.batches, 0);
    rows.forEach((r) => { r.nextAt = new Date(Date.now() - 1000); });
    await runEmailQueue();
    assert.ok(rows.every((r) => r.status === 'pending' && r.attempts === 2));
    const secondDelay = rows[0].nextAt.getTime() - Date.now();
    assert.ok(secondDelay > 295_000 && secondDelay <= 300_000, `2. geri çekilme ~300 sn: ${secondDelay}`);
    rows.forEach((r) => { r.nextAt = new Date(Date.now() - 1000); });
    summary = await runEmailQueue();
    assert.ok(rows.every((r) => r.status === 'failed' && r.attempts === 3 && r.email === null && r.nextAt === null));
    assert.equal(summary.failed, 3);
    sent.length = 0;
    await runEmailQueue();
    assert.equal(sent.length, 0, 'failed satırlar yeniden denenmez');
  });

  it('KALICI SMTP hatası (alıcı reddi / 5xx) tek denemede failed olur; geçici 4xx ve kimlik doğrulama hatası (EAUTH) yeniden denenir', async () => {
    for (const code of ['INVALID_RECIPIENT', 'EENVELOPE']) {
      rows = makeRows(2);
      sendImpl = async () => {
        throw Object.assign(new Error('x'), { code });
      };
      const summary = await runEmailQueue();
      assert.ok(rows.every((r) => r.status === 'failed' && r.email === null && r.attempts === 1), code);
      assert.equal(summary.failed, 2);
    }
    rows = makeRows(1);
    sendImpl = async () => {
      throw Object.assign(new Error('mailbox unavailable'), { code: 'EMESSAGE', responseCode: 550 });
    };
    await runEmailQueue();
    assert.equal(rows[0].status, 'failed');
    for (const error of [{ code: 'EMESSAGE', responseCode: 451 }, { code: 'EAUTH', responseCode: 535 }, { code: 'ETIMEDOUT' }, { code: 'ECONNECTION' }]) {
      rows = makeRows(1);
      sendImpl = async () => {
        throw Object.assign(new Error('x'), error);
      };
      await runEmailQueue();
      assert.equal(rows[0].status, 'pending', JSON.stringify(error));
      assert.equal(rows[0].attempts, 1);
    }
  });

  it('isPermanentSendError: INVALID_RECIPIENT, EENVELOPE ve 5xx kalıcı; EAUTH, 4xx, ağ hataları ve boş hata kalıcı DEĞİL', () => {
    assert.equal(isPermanentSendError({ code: 'INVALID_RECIPIENT' }), true);
    assert.equal(isPermanentSendError({ code: 'EENVELOPE' }), true);
    assert.equal(isPermanentSendError({ responseCode: 550 }), true);
    assert.equal(isPermanentSendError({ responseCode: 599 }), true);
    assert.equal(isPermanentSendError({ code: 'EAUTH', responseCode: 535 }), false);
    assert.equal(isPermanentSendError({ responseCode: 451 }), false);
    assert.equal(isPermanentSendError({ responseCode: 600 }), false);
    assert.equal(isPermanentSendError({ code: 'ETIMEDOUT' }), false);
    assert.equal(isPermanentSendError(null), false);
    assert.equal(isPermanentSendError(undefined), false);
  });

  it('karışık sonuç: başarılılar sent, başarısızlar pending (deneme 1, geri çekilmede); sonraki tur geri çekilme dolunca YALNIZ kalanları sürdürür', async () => {
    rows = makeRows(5);
    let calls = 0;
    sendImpl = async () => {
      calls += 1;
      if (calls > 2) throw Object.assign(new Error('x'), { code: 'ETIMEDOUT' });
    };
    await runEmailQueue();
    assert.deepEqual(rows.map((r) => r.status), ['sent', 'sent', 'pending', 'pending', 'pending']);
    sendImpl = async () => {};
    sent.length = 0;
    rows.forEach((r) => { r.nextAt = null; });
    await runEmailQueue();
    assert.deepEqual(rows.map((r) => r.status), ['sent', 'sent', 'sent', 'sent', 'sent']);
    assert.equal(sent.length, 3, 'yalnız kalan 3 satır gönderildi, ilk ikisi tekrarlanmadı');
  });

  it('talep anı denetimi (D8): kişi artık etkin değil -> none; iletişim adresi değişti -> none; adres bastırıldı -> skipped_pref; hiçbiri gönderilmez, adres + özet silinir', async () => {
    rows = makeRows(5);
    rows[0].personActive = false;
    rows[1].currentEmail = 'yeni.adres@example.com';
    rows[2].currentEmail = null;
    rows[3].suppressed = true;
    const summary = await runEmailQueue();
    assert.deepEqual(rows.map((r) => r.status), ['none', 'none', 'none', 'skipped_pref', 'sent']);
    assert.ok(rows.slice(0, 4).every((r) => r.email === null && r.hash === null && r.attempts === 0), 'gönderilmeyen satırlar adres ve özet taşımaz');
    assert.deepEqual(sent.map((m) => m.to), ['kisi5@example.com']);
    assert.equal(summary.sent, 1);
    assert.equal(summary.dropped, 4);
  });

  it('F3 sessiz tuz geçişi: PREVIOUS tanımlıyken bastırılmış satırın adresi GÜNCEL tuzla (kanonik) listeye de yazılır (talep işlemi içinde, ON CONFLICT DO NOTHING); PREVIOUS yokken yazılmaz', async () => {
    const saved = process.env.ANNOUNCEMENT_EMAIL_SECRET_PREVIOUS;
    try {
      delete process.env.ANNOUNCEMENT_EMAIL_SECRET_PREVIOUS;
      rows = makeRows(2);
      rows[0].suppressed = true;
      await runEmailQueue();
      assert.deepEqual(suppressionInserts, [], 'olağan durumda ek yazım yok');
      process.env.ANNOUNCEMENT_EMAIL_SECRET_PREVIOUS = 'eski-duyuru-sirri-0123456789';
      rows = makeRows(3, { startPid: 10 });
      rows[0].suppressed = true;
      rows[0].email = 'Eski.Adres+x@gmail.com'.toLowerCase();
      rows[0].currentEmail = rows[0].email;
      rows[1].suppressed = true;
      await runEmailQueue();
      assert.deepEqual(new Set(suppressionInserts), new Set([hashEmail('eski.adres+x@gmail.com'), hashEmail('kisi11@example.com')]));
      assert.ok(suppressionInserts.includes(hashEmail('eskiadres@gmail.com')), 'kanonik özet (gmail noktaları / +etiket)');
      assert.deepEqual(rows.map((r) => r.status), ['skipped_pref', 'skipped_pref', 'sent']);
      const insert = log.find((q) => /^INSERT INTO announcement_email_suppressions/.test(q.sql));
      const insertIndex = log.indexOf(insert);
      const closeIndex = log.findIndex((q, index) => index > insertIndex && /^UPDATE announcement_recipients r SET email_status = v\.st, email = NULL, email_hash = NULL/.test(q.sql));
      assert.ok(insertIndex >= 0 && closeIndex > insertIndex, 'bastırma yazımı satırlar kapatılmadan ÖNCE (aynı talep işleminde)');
    } finally {
      if (saved === undefined) delete process.env.ANNOUNCEMENT_EMAIL_SECRET_PREVIOUS;
      else process.env.ANNOUNCEMENT_EMAIL_SECRET_PREVIOUS = saved;
    }
  });

  it('sahte talep sorgusu gerçek koşulu uygular: yayında olmayan (geri çekilmiş) duyurunun satırları talep edilmez ve gönderilmez', async () => {
    rows = [...makeRows(2, { aid: 1 }), ...makeRows(3, { aid: 2, startPid: 10, annStatus: 'withdrawn' })];
    const summary = await runEmailQueue();
    assert.equal(summary.sent, 2);
    assert.deepEqual(sent.map((m) => m.to).sort(), ['kisi1@example.com', 'kisi2@example.com']);
    // E1: yayında olmayan duyurunun pending satırları tur başında KAPATILIR (düz adres DB'de kalmaz)
    assert.ok(rows.filter((r) => r.aid === 2).every((r) => r.status === 'failed' && r.email === null && r.hash === null && r.attempts === 0 && r.claimedAt === null));
  });

  it('E1 finalize: gönderim sürerken duyuru geri çekildi ve geçici hata (421/451) geldi -> satır pending KALMAZ: failed, adres ve özet NULL; bir daha talep edilmez', async () => {
    rows = makeRows(3);
    sendImpl = async () => {
      rows.forEach((r) => { r.annStatus = 'withdrawn'; }); // talep sonrası geri çekme (talep edilmiş satırlara dokunmaz)
      throw Object.assign(new Error('421 try again later'), { code: 'EMESSAGE', responseCode: 421 });
    };
    const summary = await runEmailQueue();
    assert.ok(rows.every((r) => r.status === 'failed' && r.email === null && r.hash === null && r.claimedAt === null && r.nextAt === null), JSON.stringify(rows.map((r) => [r.status, r.email, r.hash])));
    assert.equal(sent.length, 3, 'her satır turda bir kez denendi');
    assert.equal(summary.batches, 1);
    sent.length = 0;
    await runEmailQueue();
    assert.equal(sent.length, 0);
    assert.equal(await hasPendingEmails(), false, 'sonsuza dek pending satır kalmadı');
  });

  it('E1 finalize: geri çekme sırasında BAŞARILI gönderim sent olarak sonlanır (özet kota sayımı için kalır); yayında kalan duyurunun geçici hatası pending kalır', async () => {
    rows = [...makeRows(1, { aid: 1 }), ...makeRows(1, { aid: 2, startPid: 5 })];
    sendImpl = async (message) => {
      if (message.to === 'kisi1@example.com') {
        rows[0].annStatus = 'withdrawn';
        return;
      }
      throw Object.assign(new Error('x'), { code: 'ETIMEDOUT' });
    };
    await runEmailQueue();
    assert.equal(rows[0].status, 'sent');
    assert.notEqual(rows[0].hash, null);
    assert.equal(rows[1].status, 'pending');
    assert.notEqual(rows[1].email, null);
  });

  it('E1 hasPendingEmails: yayında olmayan duyurunun, geri çekilmesi dolmamış ve taze talepli satırları SAYILMAZ; işi olan satır sayılır', async () => {
    rows = makeRows(1, { annStatus: 'withdrawn' });
    assert.equal(await hasPendingEmails(), false, 'geri çekilmiş duyurunun satırı');
    rows = makeRows(1);
    rows[0].nextAt = new Date(Date.now() + 60_000);
    assert.equal(await hasPendingEmails(), false, 'geri çekilmesi dolmamış');
    rows[0].nextAt = null;
    rows[0].claimedAt = new Date();
    assert.equal(await hasPendingEmails(), false, 'başka işçinin taze talebi');
    rows[0].claimedAt = new Date(Date.now() - 11 * MINUTE);
    assert.equal(await hasPendingEmails(), true, 'bayat talep kurtarılmalı');
    rows[0].claimedAt = null;
    assert.equal(await hasPendingEmails(), true);
  });

  it('E1 failStaleRows: yayında olmayan duyurunun TALEP EDİLMEMİŞ pending satırı da kapatılır (adres + özet NULL); taze talepli olan işçi sonuç yazana dek korunur', async () => {
    rows = [
      { ...makeRows(1, { annStatus: 'withdrawn' })[0], attempts: 1 },
      { ...makeRows(1, { startPid: 2, annStatus: 'withdrawn' })[0], attempts: 1, claimedAt: new Date() },
      makeRows(1, { startPid: 3 })[0],
    ];
    const count = await failStaleRows(pool);
    assert.equal(count, 1);
    assert.deepEqual(rows.map((r) => r.status), ['failed', 'pending', 'pending']);
    assert.equal(rows[0].email, null);
    assert.equal(rows[0].hash, null);
  });

  it('talep işareti: yoldaki (taze talep edilmiş) satır başka tur tarafından ALINMAZ; 10 dk\'dan eski talep (süreç çökmüş) yeniden talep edilip gönderilir', async () => {
    rows = makeRows(3);
    rows[0].attempts = 1;
    rows[0].claimedAt = new Date();
    rows[1].attempts = 1;
    rows[1].claimedAt = new Date(Date.now() - 11 * MINUTE);
    const summary = await runEmailQueue();
    assert.deepEqual(rows.map((r) => r.status), ['pending', 'sent', 'sent']);
    assert.equal(rows[1].attempts, 2);
    assert.equal(summary.sent, 2);
    assert.equal(rows[0].attempts, 1, 'taze talep dokunulmadan kaldı');
  });

  it('sonuç yazımı yalnız hâlâ pending satırlara işler (geri çekme / başka yazım sonrası ezilmez)', async () => {
    rows = makeRows(2);
    sendImpl = async () => {
      rows[0].status = 'none'; // gönderim sürerken satır başka yoldan kapatıldı
      rows[0].email = null;
    };
    await runEmailQueue();
    assert.equal(rows[0].status, 'none');
    assert.equal(rows[1].status, 'sent');
  });

  it('failStaleRows: adresi olmayan ve denemesi tükenmiş (taze talep HARİÇ) bekleyenler failed; yayından kalkmış duyurunun bayat talepleri failed', async () => {
    rows = [
      ...makeRows(1),
      { ...makeRows(1, { startPid: 2 })[0], attempts: 3 }, // tükenmiş, talep yok
      { ...makeRows(1, { startPid: 3 })[0], attempts: 3, claimedAt: new Date() }, // tükenmiş ama yoldaki gönderim olabilir (taze)
      { ...makeRows(1, { startPid: 4 })[0], attempts: 3, claimedAt: new Date(Date.now() - 11 * MINUTE) }, // tükenmiş + bayat talep
      { ...makeRows(1, { startPid: 5 })[0], email: null },
      { ...makeRows(1, { startPid: 6, annStatus: 'withdrawn' })[0], attempts: 1, claimedAt: new Date(Date.now() - 11 * MINUTE) },
      { ...makeRows(1, { startPid: 7, annStatus: 'withdrawn' })[0], attempts: 1, claimedAt: new Date() },
    ];
    const count = await failStaleRows(pool);
    assert.deepEqual(rows.map((r) => r.status), ['pending', 'failed', 'pending', 'failed', 'failed', 'failed', 'pending']);
    assert.equal(count, 4);
    assert.ok(rows.filter((r) => r.status === 'failed').every((r) => r.email === null && r.claimedAt === null));
  });

  it('SMTP yapılandırılmamış: bekleyen satırlar failed olur (sessiz kayıp yok), hiçbir gönderim denenmez', async () => {
    delete process.env.SMTP_HOST;
    rows = makeRows(4);
    const summary = await runEmailQueue();
    assert.equal(summary.smtp, false);
    assert.equal(sent.length, 0);
    assert.ok(rows.every((r) => r.status === 'failed' && r.email === null));
    assert.equal(summary.failed, 4);
  });

  it('purgeStaleEmailHashes: 3 günden eski, pending olmayan satırların özeti silinir (sorgu saklama süresini parametre alır); sayı döner', async () => {
    rows = makeRows(3);
    rows.forEach((r) => Object.assign(r, { status: 'sent', email: null }));
    rows[0].old = true;
    rows[1].old = true;
    assert.equal(await purgeStaleEmailHashes(), 2);
    assert.deepEqual(rows.map((r) => r.hash === null), [true, true, false]);
    assert.deepEqual(log.at(-1).params, [EMAIL_HASH_RETENTION_DAYS]);
  });
});

describe('e-posta kuyruğu: tek çalışan, kick, kapanış', () => {
  it('kilit başka yerdeyse tur ATLANIR ({skipped:locked}); hiçbir satır okunmaz/yazılmaz; kilit denemesi bağlantıyı tutmaz', async () => {
    rows = makeRows(3);
    lockHeldElsewhere = true;
    const summary = await runEmailQueue();
    assert.deepEqual(summary, { skipped: 'locked' });
    assert.equal(sent.length, 0);
    assert.ok(rows.every((r) => r.status === 'pending'));
    assert.deepEqual(lockOps, ['try']);
    assert.equal(log.some((q) => /^UPDATE|^SELECT r\.announcement_id/.test(q.sql)), false);
  });

  it('kilit İKİ-int anahtardır (sınıf + iş); tur sonunda (hata olsa bile) kilit AÇILIR', async () => {
    rows = makeRows(2);
    await runEmailQueue();
    assert.deepEqual(lockOps, ['try', 'unlock']);
    assert.deepEqual(lockParams[0], [ANNOUNCEMENT_LOCK_CLASS, EMAIL_QUEUE_LOCK_JOB]);
    assert.match(log.find((q) => /pg_try_advisory_lock/.test(q.sql)).sql, /pg_try_advisory_lock\(\$1::int, \$2::int\)/);
    lockOps.length = 0;
    const realQuery = pool.query;
    pool.query = async (text, params) => {
      if (/email_attempts >= \$1/.test(text)) throw new Error('db kesildi');
      return realQuery(text, params);
    };
    await assert.rejects(() => runEmailQueue(), /db kesildi/);
    assert.deepEqual(lockOps, ['try', 'unlock'], 'hata sonrası da kilit açıldı');
  });

  it('kickEmailQueue: eşzamanlı çağrılar TEK turu paylaşır (çift gönderim yok); tur bitince yenisi başlayabilir', async () => {
    rows = makeRows(6);
    const [a, b, c] = [kickEmailQueue(), kickEmailQueue(), kickEmailQueue()];
    assert.equal(a, b);
    assert.equal(b, c);
    const summary = await a;
    assert.equal(summary.sent, 6);
    assert.equal(sent.length, 6);
    rows = makeRows(2, { startPid: 100 });
    const next = await kickEmailQueue();
    assert.equal(next.sent, 2);
  });

  it('kickEmailQueue hata FIRLATMAZ: DB hatası loglanır ({error}) ve log\'da e-posta adresi yoktur', async () => {
    pool.connect = async () => {
      throw Object.assign(new Error('bağlantı yok a@b.com'), { code: 'ECONNREFUSED' });
    };
    const result = await kickEmailQueue();
    assert.deepEqual(result, { error: 'ECONNREFUSED' });
    const logged = console.error.mock.calls.map((call) => call.arguments.join(' ')).join('\n');
    assert.match(logged, /ECONNREFUSED/);
    assert.ok(!logged.includes('@'), logged);
  });

  it('sonuç yazımı (finalize) başarısız olursa tur { error } ile biter, sunucu düşmez; satırlar talep edilmiş pending kalır ve taze talep OLDUĞU için hemen yeniden gönderilmez (çift e-posta yok)', async () => {
    rows = makeRows(3);
    const realQuery = pool.query;
    let failed = false;
    pool.query = async (text, params) => {
      if (!failed && /email_status = x\.final_st, email = CASE WHEN x\.final_st = 'pending'/.test(norm(text))) {
        failed = true;
        throw Object.assign(new Error('bağlantı koptu'), { code: '57P01' });
      }
      return realQuery(text, params);
    };
    const result = await kickEmailQueue();
    assert.deepEqual(result, { error: '57P01' });
    assert.equal(sent.length, 3, 'e-postalar gitti');
    assert.ok(rows.every((r) => r.status === 'pending' && r.attempts === 1 && r.claimedAt !== null));
    const again = await runEmailQueue();
    assert.equal(again.sent, 0);
    assert.equal(sent.length, 3, 'taze talep yeniden gönderilmez');
    rows.forEach((r) => { r.claimedAt = new Date(Date.now() - 11 * MINUTE); });
    const recovered = await runEmailQueue();
    assert.equal(recovered.sent, 3, 'bayatlayınca yeniden talep edilip gönderilir (en az bir kez teslim)');
    assert.ok(rows.every((r) => r.status === 'sent' && r.attempts === 2));
  });

  it('gönderim hatası logu yalnız kod içerir (adres / başlık yok)', async () => {
    rows = makeRows(2);
    sendImpl = async () => {
      throw Object.assign(new Error('RCPT kisi1@example.com reddedildi'), { code: 'EENVELOPE' });
    };
    await runEmailQueue();
    const logged = console.error.mock.calls.map((call) => call.arguments.join(' ')).join('\n');
    assert.match(logged, /EENVELOPE/);
    assert.ok(!logged.includes('@') && !logged.includes('Başlık'), logged);
  });

  it('stopEmailQueue: çalışan tur grup sonunda durur (kalanlar pending ve TALEP EDİLMEMİŞ kalır); durdurulmuşsa yeni tur başlamaz; resume ile devam', async () => {
    rows = makeRows(50);
    let calls = 0;
    sendImpl = async () => {
      calls += 1;
      if (calls === 1) void stopEmailQueue();
    };
    const run = kickEmailQueue();
    const summary = await run;
    assert.equal(summary.batches, 1, 'ilk gruptan sonra durdu');
    const waiting = rows.filter((r) => r.status === 'pending');
    assert.equal(waiting.length, 30);
    assert.ok(waiting.every((r) => r.claimedAt === null && r.attempts === 0), 'yarıda kalan (talep edilmiş) satır yok');
    assert.deepEqual(await kickEmailQueue(), { skipped: 'stopping' });
    resumeEmailQueue();
    const resumed = await kickEmailQueue();
    assert.equal(resumed.sent, 30);
  });

  it('süre sınırı: maxRunMs dolunca tur biter (kalanlar sonraki tikte)', async () => {
    rows = makeRows(60);
    let clock = 0;
    emailQueueHooks.now = () => clock;
    emailQueueHooks.sleep = async () => {
      clock += 400;
    };
    const summary = await runEmailQueue({ maxRunMs: 700 });
    assert.equal(summary.batches, 2);
    assert.equal(rows.filter((r) => r.status === 'pending').length, 20);
  });

  it('hasPendingEmails: kısmi indeksli hafif sorgu', async () => {
    assert.equal(await hasPendingEmails(), false);
    rows = makeRows(1);
    assert.equal(await hasPendingEmails(), true);
  });
});
