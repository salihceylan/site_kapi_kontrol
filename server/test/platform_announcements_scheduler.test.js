// Duyuru zamanlayıcısı (DB'siz): kapatma ortam değişkeni, tek çalışan kilidi, tik başına 20, hata yalıtımı, e-posta kuyruğunu sürme,
// setInterval sızıntısı yok (unref + stop).
import { describe, it, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert/strict';
import { pool } from '../src/db.js';
import {
  MAX_PUBLISH_PER_TICK,
  SCHEDULER_INTERVAL_MS,
  SCHEDULER_LOCK_KEY,
  isSchedulerDisabled,
  resetSchedulerState,
  runSchedulerTick,
  schedulerHooks,
  startAnnouncementScheduler,
  stopAnnouncementScheduler,
} from '../src/modules/announcement_scheduler.js';

const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
const ok = (rows = [], rowCount = rows.length) => ({ rows, rowCount });

let log;
let due;
let lockBusy;
let lockOps;
let savedHooks;
let published;
let kicks;
let pendingEmails;

beforeEach(() => {
  resetSchedulerState();
  log = [];
  due = [];
  lockBusy = false;
  lockOps = [];
  published = [];
  kicks = 0;
  pendingEmails = false;
  savedHooks = { ...schedulerHooks };
  schedulerHooks.publishDue = async (args) => {
    published.push(args);
    return { published: true, recipientCount: 1, email: {} };
  };
  schedulerHooks.hasPendingEmails = async () => pendingEmails;
  schedulerHooks.kickEmailQueue = () => {
    kicks += 1;
    return new Promise(() => {}); // asla bitmeyen kuyruk turu: tik BEKLEMEMELİ
  };
  const run = (text, params) => {
    const sql = norm(text);
    log.push({ sql, params: params ?? [] });
    if (/^SELECT pg_try_advisory_lock/.test(sql)) {
      lockOps.push('try');
      return ok([{ locked: !lockBusy }]);
    }
    if (/^SELECT pg_advisory_unlock/.test(sql)) {
      lockOps.push('unlock');
      return ok([{}]);
    }
    if (/^SELECT id, site_code FROM announcements WHERE status = 'scheduled' AND publish_at <= NOW\(\) ORDER BY publish_at, id LIMIT \$1$/.test(sql)) {
      return ok(due);
    }
    throw new Error(`BEKLENMEYEN SQL (sahte DB katı): ${sql.slice(0, 200)}`);
  };
  pool.query = async (text, params) => run(text, params);
  pool.connect = async () => ({ query: async (text, params) => run(text, params), release() {} });
  mock.method(console, 'error', () => {});
  mock.method(console, 'log', () => {});
});

afterEach(async () => {
  await stopAnnouncementScheduler({ timeoutMs: 50 });
  Object.assign(schedulerHooks, savedHooks);
  delete pool.query;
  delete pool.connect;
  mock.restoreAll();
});

describe('zamanlayıcı: kapatma ve sabitler', () => {
  it('ANNOUNCEMENT_SCHEDULER_DISABLED (1 / true / yes) ile hiç başlamaz (null)', () => {
    for (const value of ['1', 'true', 'TRUE', 'yes']) {
      assert.equal(isSchedulerDisabled({ ANNOUNCEMENT_SCHEDULER_DISABLED: value }), true, value);
      assert.equal(startAnnouncementScheduler({ env: { ANNOUNCEMENT_SCHEDULER_DISABLED: value } }), null);
    }
    for (const value of [undefined, '', '0', 'false', 'hayır']) {
      assert.equal(isSchedulerDisabled({ ANNOUNCEMENT_SCHEDULER_DISABLED: value }), false, String(value));
    }
  });

  it('sözleşme sabitleri: 30 sn aralık, tik başına en çok 20', () => {
    assert.equal(SCHEDULER_INTERVAL_MS, 30_000);
    assert.equal(MAX_PUBLISH_PER_TICK, 20);
    assert.equal(SCHEDULER_LOCK_KEY, 'announcement_scheduler');
  });
});

describe('zamanlayıcı: tik', () => {
  it('zamanı gelen duyuruları (en çok 20, publish_at sırasıyla) yayınlar; kilit alınır ve tik sonunda AÇILIR', async () => {
    due = [{ id: '5', site_code: '1000000001' }, { id: '6', site_code: '1000000002' }];
    const summary = await runSchedulerTick();
    assert.deepEqual(summary, { locked: false, published: 2, skipped: 0, failed: 0 });
    assert.deepEqual(published, [{ id: 5, siteCode: 1000000001 }, { id: 6, siteCode: 1000000002 }]);
    assert.deepEqual(lockOps, ['try', 'unlock']);
    assert.equal(log.find((q) => /pg_try_advisory_lock/.test(q.sql)).params[0], SCHEDULER_LOCK_KEY);
    assert.deepEqual(log.find((q) => /^SELECT id, site_code FROM announcements/.test(q.sql)).params, [20]);
  });

  it('kilit başka yerdeyse (ikinci sunucu) tik ATLANIR: duyuru sorgusu da yayın da yok', async () => {
    lockBusy = true;
    due = [{ id: '5', site_code: '1000000001' }];
    const summary = await runSchedulerTick();
    assert.equal(summary.locked, true);
    assert.equal(published.length, 0);
    assert.equal(log.some((q) => /FROM announcements/.test(q.sql)), false);
    assert.deepEqual(lockOps, ['try']);
  });

  it('bir duyurunun yayını hata verirse tik DÜŞMEZ: hata sayılır, sıradaki yayınlanır, log yalnız kimlik + kod içerir', async () => {
    due = [{ id: '5', site_code: '1' }, { id: '6', site_code: '1' }, { id: '7', site_code: '1' }];
    schedulerHooks.publishDue = async (args) => {
      published.push(args);
      if (args.id === 6) throw Object.assign(new Error('veri: gizli başlık a@b.com'), { code: '23503' });
      return args.id === 7 ? { skipped: true, status: 'published' } : { published: true };
    };
    const summary = await runSchedulerTick();
    assert.deepEqual(summary, { locked: false, published: 1, skipped: 1, failed: 1 });
    assert.equal(published.length, 3);
    const logged = console.error.mock.calls.map((call) => call.arguments.join(' ')).join('\n');
    assert.match(logged, /id=6/);
    assert.match(logged, /23503/);
    assert.ok(!logged.includes('@') && !logged.includes('gizli'), logged);
    assert.deepEqual(lockOps, ['try', 'unlock']);
  });

  it('DB hatası (duyuru sorgusu) tiki düşürmez; kilit yine açılır', async () => {
    const realQuery = pool.query;
    pool.query = async (text, params) => {
      if (/FROM announcements/.test(text)) throw Object.assign(new Error('db kesildi'), { code: '57P01' });
      return realQuery(text, params);
    };
    const summary = await runSchedulerTick();
    assert.equal(summary.failed, 1);
    assert.deepEqual(lockOps, ['try', 'unlock']);
  });

  it('tik sonunda bekleyen e-posta varsa kuyruk ARKA PLANDA tetiklenir (tik beklemez); yoksa tetiklenmez', async () => {
    pendingEmails = true;
    await runSchedulerTick();
    assert.equal(kicks, 1);
    pendingEmails = false;
    await runSchedulerTick();
    assert.equal(kicks, 1);
  });

  it('kilit alınamayan tikte kuyruk TETİKLENMEZ (kilidin sahibi olan örnek sürer; e-posta kuyruğunun ayrıca kendi tek-çalışan kilidi vardır)', async () => {
    lockBusy = true;
    pendingEmails = true;
    await runSchedulerTick();
    assert.equal(kicks, 0);
  });

  it('çakışan tik çağrıları AYNI tiki paylaşır (çift yayın denemesi yok)', async () => {
    due = [{ id: '5', site_code: '1' }];
    const [a, b] = [runSchedulerTick(), runSchedulerTick()];
    assert.equal(a, b);
    await a;
    assert.equal(published.length, 1);
  });
});

describe('zamanlayıcı: yaşam döngüsü (sızıntı yok)', () => {
  it('start -> tek setInterval (unref\'li) + ilk tik zamanlayıcısı (unref\'li); tekrar start ikinci zamanlayıcı KURMAZ; stop ikisini de temizler', async () => {
    const realSetInterval = globalThis.setInterval;
    const realClearInterval = globalThis.clearInterval;
    const realSetTimeout = globalThis.setTimeout;
    const intervals = [];
    const cleared = [];
    globalThis.setInterval = (fn, ms) => {
      const timer = realSetInterval(fn, ms);
      const entry = { timer, ms, unref: false };
      const unref = timer.unref.bind(timer);
      timer.unref = () => {
        entry.unref = true;
        return unref();
      };
      intervals.push(entry);
      return timer;
    };
    globalThis.clearInterval = (timer) => {
      cleared.push(timer);
      return realClearInterval(timer);
    };
    try {
      const first = startAnnouncementScheduler({ intervalMs: 60_000, env: {} });
      const second = startAnnouncementScheduler({ intervalMs: 60_000, env: {} });
      assert.equal(intervals.length, 1, 'tek interval');
      assert.equal(intervals[0].ms, 60_000);
      assert.equal(intervals[0].unref, true, 'interval unref\'li (süreci açık tutmaz)');
      assert.equal(typeof first.stop, 'function');
      assert.equal(typeof second.stop, 'function');
      await first.stop();
      assert.equal(cleared.includes(intervals[0].timer), true, 'stop interval\'i temizledi');
    } finally {
      globalThis.setInterval = realSetInterval;
      globalThis.clearInterval = realClearInterval;
      globalThis.setTimeout = realSetTimeout;
    }
  });

  it('interval çalışır (tik kancası çağrılır) ve stop() sonrası DURUR', async () => {
    let ticks = 0;
    schedulerHooks.hasPendingEmails = async () => {
      ticks += 1;
      return false;
    };
    const handle = startAnnouncementScheduler({ intervalMs: 20, env: {} });
    await new Promise((resolve) => setTimeout(resolve, 120));
    const running = ticks;
    await handle.stop();
    const atStop = ticks;
    await new Promise((resolve) => setTimeout(resolve, 100));
    assert.ok(running >= 1, `tik sayısı ${running}`);
    assert.equal(ticks, atStop, 'stop sonrası tik yok');
  });

  it('stop(): çalışan tikin bitmesini bekler (zaman aşımına kadar); tik yayını sürerken yeni duyuru işlemez', async () => {
    due = [{ id: '5', site_code: '1' }, { id: '6', site_code: '1' }];
    let release;
    schedulerHooks.publishDue = async (args) => {
      published.push(args);
      await new Promise((resolve) => {
        release = resolve;
      });
      return { published: true };
    };
    const tick = runSchedulerTick();
    await new Promise((resolve) => setImmediate(resolve));
    const stopping = stopAnnouncementScheduler({ timeoutMs: 2000 });
    release();
    await stopping;
    await tick;
    assert.equal(published.length, 1, 'durdurma isteğinden sonra ikinci duyuruya geçilmez');
  });
});
