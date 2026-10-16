// Duyuru arka plan oturum kilidi (DB'siz): iki-int anahtar uzayı, tek çalışan, bağlantı hata dinleyicisi (D13), güvenli release.
import { describe, it, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { pool } from '../src/db.js';
import { ANNOUNCEMENT_LOCK_CLASS, ANNOUNCEMENT_LOCK_JOBS, acquireSessionLock } from '../src/modules/announcement_lock.js';

let client;
let queries;
let releases;
let locked;
let queryError;

function makeClient() {
  const emitter = new EventEmitter();
  emitter.query = async (text, params) => {
    queries.push({ sql: String(text).replace(/\s+/g, ' ').trim(), params });
    if (queryError && queryError.match.test(String(text))) {
      throw queryError.error;
    }
    if (/pg_try_advisory_lock/.test(text)) return { rows: [{ locked }] };
    return { rows: [{}] };
  };
  emitter.release = (destroy) => {
    releases.push(destroy === true ? 'destroy' : 'release');
  };
  return emitter;
}

beforeEach(() => {
  queries = [];
  releases = [];
  locked = true;
  queryError = null;
  client = makeClient();
  pool.connect = async () => client;
  mock.method(console, 'error', () => {});
});

afterEach(() => {
  delete pool.connect;
  mock.restoreAll();
});

describe('acquireSessionLock', () => {
  it('sabitler: sınıf "ANNC" (0x414E4E43), işler birbirinden ayrı (zamanlayıcı 1, e-posta kuyruğu 2, küresel e-posta 3); int4 aralığında', () => {
    assert.equal(ANNOUNCEMENT_LOCK_CLASS, 0x414e4e43);
    assert.ok(ANNOUNCEMENT_LOCK_CLASS > 0 && ANNOUNCEMENT_LOCK_CLASS < 2 ** 31);
    assert.deepEqual({ ...ANNOUNCEMENT_LOCK_JOBS }, { scheduler: 1, emailQueue: 2, emailGlobal: 3 });
    assert.equal(new Set(Object.values(ANNOUNCEMENT_LOCK_JOBS)).size, 3);
    assert.throws(() => {
      ANNOUNCEMENT_LOCK_JOBS.scheduler = 9;
    }, TypeError, 'dondurulmuş');
  });

  it('iki-int pg_try_advisory_lock($1::int, $2::int) (sınıf, iş) çağrılır; tek anahtarlı hashtext biçimi KULLANILMAZ', async () => {
    const lock = await acquireSessionLock(ANNOUNCEMENT_LOCK_JOBS.scheduler);
    assert.ok(lock);
    assert.equal(queries[0].sql, 'SELECT pg_try_advisory_lock($1::int, $2::int) AS locked');
    assert.deepEqual(queries[0].params, [ANNOUNCEMENT_LOCK_CLASS, ANNOUNCEMENT_LOCK_JOBS.scheduler]);
    assert.doesNotMatch(queries[0].sql, /hashtext/);
    await lock.release();
    assert.equal(queries[1].sql, 'SELECT pg_advisory_unlock($1::int, $2::int)');
    assert.deepEqual(queries[1].params, [ANNOUNCEMENT_LOCK_CLASS, ANNOUNCEMENT_LOCK_JOBS.scheduler]);
    assert.deepEqual(releases, ['release']);
  });

  it('kilit başka yerdeyse null döner; bağlantı havuza hemen iade edilir ve hata dinleyicisi KALMAZ', async () => {
    locked = false;
    assert.equal(await acquireSessionLock(ANNOUNCEMENT_LOCK_JOBS.emailQueue), null);
    assert.deepEqual(releases, ['release']);
    assert.equal(client.listenerCount('error'), 0);
  });

  it('D13 kilit tutulurken bağlantıya "error" dinleyicisi eklidir (yoksa uncaughtException ile süreç düşerdi); hata yalnız kodla loglanır, fırlatılmaz', async () => {
    const lock = await acquireSessionLock(ANNOUNCEMENT_LOCK_JOBS.scheduler);
    assert.equal(client.listenerCount('error'), 1);
    assert.doesNotThrow(() => client.emit('error', Object.assign(new Error('terminating connection a@b.com'), { code: '57P01' })));
    const logged = console.error.mock.calls.map((call) => call.arguments.join(' ')).join('\n');
    assert.match(logged, /57P01/);
    assert.ok(!logged.includes('@'), 'ileti metni (adres olabilir) loglanmaz');
    await lock.release();
    assert.equal(client.listenerCount('error'), 0, 'normal release dinleyiciyi kaldırır');
  });

  it('D13 bağlantı kopmuşken release() hata FIRLATMAZ: istemci yok edilir (release(true)); dinleyici yok edilen istemcide kalır (geç gelen hata süreci düşürmez)', async () => {
    const lock = await acquireSessionLock(ANNOUNCEMENT_LOCK_JOBS.scheduler);
    queryError = { match: /pg_advisory_unlock/, error: Object.assign(new Error('Client has encountered a connection error'), { code: '57P01' }) };
    await assert.doesNotReject(() => lock.release());
    assert.deepEqual(releases, ['destroy']);
    assert.equal(client.listenerCount('error'), 1);
    assert.doesNotThrow(() => client.emit('error', new Error('geç gelen hata')));
  });

  it('kilit sorgusu başarısız olursa bağlantı yok edilir ve hata yukarı çıkar (kilit havuzda asılı kalmaz)', async () => {
    queryError = { match: /pg_try_advisory_lock/, error: Object.assign(new Error('x'), { code: '57P01' }) };
    await assert.rejects(() => acquireSessionLock(ANNOUNCEMENT_LOCK_JOBS.scheduler), (e) => e.code === '57P01');
    assert.deepEqual(releases, ['destroy']);
  });
});
