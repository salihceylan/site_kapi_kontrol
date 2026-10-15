// Duyuru e-posta kuyruğu (DB'siz): bellek içi sahte alıcı tablosu üzerinde grup boyutu, gruplar arası bekleme, deneme sayacı, 3 denemede
// failed, SMTP yok -> failed, tek çalışan kilidi, kapanış, log gizliliği. Gerçek SMTP'ye ASLA bağlanılmaz (gönderim kancası sahte).
import { describe, it, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert/strict';
import { pool } from '../src/db.js';
import {
  EMAIL_BATCH_DELAY_MS,
  EMAIL_BATCH_SIZE,
  EMAIL_QUEUE_LOCK_KEY,
  emailQueueHooks,
  hasPendingEmails,
  kickEmailQueue,
  resumeEmailQueue,
  runEmailQueue,
  stopEmailQueue,
} from '../src/modules/announcement_email_queue.js';

const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
const ok = (rows = [], rowCount = rows.length) => ({ rows, rowCount });

let rows; // { aid, pid, email, attempts, status }
let log;
let lockHeldElsewhere;
let lockOps;
let sent;
let sleeps;
let sendImpl;
let savedHooks;
const savedEnv = {};

const ENV_NAMES = ['SMTP_HOST', 'SMTP_USER', 'SMTP_PASSWORD', 'SMTP_FROM'];

function makeRows(count, { aid = 1, startPid = 1 } = {}) {
  return Array.from({ length: count }, (_, i) => ({ aid, pid: startPid + i, email: `kisi${startPid + i}@example.com`, attempts: 0, status: 'pending' }));
}

function emulate(sql, params) {
  if (/^SELECT pg_try_advisory_lock/.test(sql)) {
    lockOps.push('try');
    return ok([{ locked: !lockHeldElsewhere }]);
  }
  if (/^SELECT pg_advisory_unlock/.test(sql)) {
    lockOps.push('unlock');
    return ok([{}]);
  }
  if (/^BEGIN$|^COMMIT$|^ROLLBACK$/.test(sql)) return ok();
  if (/^SELECT 1 FROM announcement_recipients WHERE email_status = 'pending' LIMIT 1$/.test(sql)) {
    return ok(rows.filter((r) => r.status === 'pending').slice(0, 1).map(() => ({ '?column?': 1 })));
  }
  if (/^UPDATE announcement_recipients SET email_status = 'failed', email = NULL WHERE email_status = 'pending' AND \(email_attempts >= \$1 OR email IS NULL\)$/.test(sql)) {
    const hit = rows.filter((r) => r.status === 'pending' && (r.attempts >= params[0] || r.email === null));
    hit.forEach((r) => Object.assign(r, { status: 'failed', email: null }));
    return ok([], hit.length);
  }
  if (/^UPDATE announcement_recipients SET email_status = 'failed', email = NULL WHERE email_status = 'pending'$/.test(sql)) {
    const hit = rows.filter((r) => r.status === 'pending');
    hit.forEach((r) => Object.assign(r, { status: 'failed', email: null }));
    return ok([], hit.length);
  }
  if (/^SELECT r\.announcement_id, r\.person_id, r\.email, r\.email_attempts, a\.title, a\.body, a\.importance, s\.name AS site_name FROM announcement_recipients r/.test(sql)) {
    const [maxAttempts, doneA, doneP, limit] = params;
    const done = new Set(doneA.map((a, i) => `${a}:${doneP[i]}`));
    const picked = rows
      .filter((r) => r.status === 'pending' && r.email !== null && r.attempts < maxAttempts && !done.has(`${r.aid}:${r.pid}`))
      .sort((a, b) => a.aid - b.aid || a.pid - b.pid)
      .slice(0, limit);
    return ok(picked.map((r) => ({ announcement_id: String(r.aid), person_id: String(r.pid), email: r.email, email_attempts: r.attempts, title: 'Başlık', body: 'Metin', importance: 'normal', site_name: 'Gül Sitesi' })));
  }
  if (/^UPDATE announcement_recipients r SET email_attempts = r\.email_attempts \+ 1 FROM unnest/.test(sql)) {
    params[0].forEach((aid, i) => {
      const row = rows.find((r) => String(r.aid) === String(aid) && String(r.pid) === String(params[1][i]));
      if (row) row.attempts += 1;
    });
    return ok([], params[0].length);
  }
  if (/^UPDATE announcement_recipients r SET email_status = v\.st, email = NULL FROM unnest/.test(sql)) {
    params[0].forEach((aid, i) => {
      const row = rows.find((r) => String(r.aid) === String(aid) && String(r.pid) === String(params[1][i]) && r.status === 'pending');
      if (row) Object.assign(row, { status: params[2][i], email: null });
    });
    return ok([], params[0].length);
  }
  throw new Error(`BEKLENMEYEN SQL (sahte DB katı): ${sql.slice(0, 200)}`);
}

beforeEach(() => {
  rows = [];
  log = [];
  lockHeldElsewhere = false;
  lockOps = [];
  sent = [];
  sleeps = [];
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
  it('sabitler: 20\'lik gruplar, gruplar arası >= 150 ms', () => {
    assert.equal(EMAIL_BATCH_SIZE, 20);
    assert.ok(EMAIL_BATCH_DELAY_MS >= 150);
  });

  it('45 bekleyen satır -> 3 grup (20 + 20 + 5); her grup sonrası >= 150 ms bekleme; hepsi sent ve email NULL; deneme sayısı 1', async () => {
    rows = makeRows(45);
    const summary = await runEmailQueue();
    assert.equal(summary.batches, 3);
    assert.equal(summary.sent, 45);
    assert.equal(sent.length, 45);
    assert.deepEqual(sleeps, [150, 150, 150]);
    assert.ok(rows.every((r) => r.status === 'sent' && r.email === null && r.attempts === 1));
    const claims = log.filter((q) => /^SELECT r\.announcement_id/.test(q.sql));
    assert.deepEqual(claims.slice(0, 3).map((q) => q.params[3]), [20, 20, 20]);
    assert.match(claims[0].sql, /FOR UPDATE OF r SKIP LOCKED/);
    assert.match(claims[0].sql, /a\.status = 'published'/);
    assert.match(claims[0].sql, /r\.email_attempts < \$1/);
    assert.equal(claims[0].params[0], 3);
  });

  it('gönderilen ileti: alıcı, site adı, başlık, metin, önem kancaya iletilir; paralellik en çok 4', async () => {
    rows = makeRows(8);
    let active = 0;
    let peak = 0;
    sendImpl = async () => {
      active += 1;
      peak = Math.max(peak, active);
      await new Promise((resolve) => setImmediate(resolve));
      active -= 1;
    };
    await runEmailQueue();
    assert.deepEqual(Object.keys(sent[0]).sort(), ['body', 'importance', 'siteName', 'title', 'to']);
    assert.equal(sent[0].siteName, 'Gül Sitesi');
    assert.equal(sent[0].to, 'kisi1@example.com');
    assert.ok(peak <= 4 && peak >= 2, `paralellik ${peak}`);
  });

  it('SMTP hatası: satır pending kalır (adres korunur), deneme artar; AYNI turda yeniden denenmez; 3. turda failed + email NULL', async () => {
    rows = makeRows(3);
    sendImpl = async () => {
      throw Object.assign(new Error('adres a@b.com reddedildi'), { code: 'ECONNECTION' });
    };
    let summary = await runEmailQueue();
    assert.equal(sent.length, 3, 'her satır turda BİR kez denenir');
    assert.equal(summary.pendingRetry, 3);
    assert.ok(rows.every((r) => r.status === 'pending' && r.attempts === 1 && r.email !== null));
    await runEmailQueue();
    assert.ok(rows.every((r) => r.status === 'pending' && r.attempts === 2));
    summary = await runEmailQueue();
    assert.ok(rows.every((r) => r.status === 'failed' && r.attempts === 3 && r.email === null));
    assert.equal(summary.failed, 3);
    sent.length = 0;
    await runEmailQueue();
    assert.equal(sent.length, 0, 'failed satırlar yeniden denenmez');
  });

  it('geçersiz alıcı adresi (INVALID_RECIPIENT) beklemeden failed olur', async () => {
    rows = makeRows(2);
    sendImpl = async () => {
      throw Object.assign(new Error('x'), { code: 'INVALID_RECIPIENT' });
    };
    const summary = await runEmailQueue();
    assert.ok(rows.every((r) => r.status === 'failed' && r.email === null));
    assert.equal(summary.failed, 2);
  });

  it('karışık sonuç: başarılılar sent, başarısızlar pending (deneme 1); sonraki tur yalnız kalanları sürdürür (yeniden başlama)', async () => {
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
    // süreç bir grubu talep edip öldü: deneme artmış ama sonuç yok
    rows[2].attempts += 1;
    await runEmailQueue();
    assert.deepEqual(rows.map((r) => r.status), ['sent', 'sent', 'sent', 'sent', 'sent']);
    assert.equal(sent.length, 3, 'yalnız kalan 3 satır gönderildi, ilk ikisi tekrarlanmadı');
  });

  it('denemesi tükenmiş (çökme artığı) ve adresi olmayan bekleyen satırlar tur başında failed yapılır', async () => {
    rows = [...makeRows(1), { aid: 1, pid: 9, email: 'x@example.com', attempts: 3, status: 'pending' }, { aid: 1, pid: 10, email: null, attempts: 0, status: 'pending' }];
    await runEmailQueue();
    assert.deepEqual(rows.map((r) => r.status), ['sent', 'failed', 'failed']);
    assert.ok(rows.every((r) => r.email === null));
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

  it('kilit anahtarı sabit; tur sonunda (hata olsa bile) kilit AÇILIR', async () => {
    assert.equal(EMAIL_QUEUE_LOCK_KEY, 'announcement_email_queue');
    rows = makeRows(2);
    await runEmailQueue();
    assert.deepEqual(lockOps, ['try', 'unlock']);
    assert.equal(log.find((q) => /pg_try_advisory_lock/.test(q.sql)).params[0], EMAIL_QUEUE_LOCK_KEY);
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

  it('stopEmailQueue: çalışan tur grup sonunda durur (kalanlar pending kalır); durdurulmuşsa yeni tur başlamaz; resume ile devam', async () => {
    rows = makeRows(50);
    let calls = 0;
    sendImpl = async () => {
      calls += 1;
      if (calls === 1) void stopEmailQueue();
    };
    const run = kickEmailQueue();
    const summary = await run;
    assert.equal(summary.batches, 1, 'ilk gruptan sonra durdu');
    assert.equal(rows.filter((r) => r.status === 'pending').length, 30);
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
