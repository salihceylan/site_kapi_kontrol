// Belgeler (Faz 3b-A) bakım işi (DB'siz, KATI sahte istemci + gerçek geçici dosya sistemi): tek çalışan kilidi, sıra, DB yokken HİÇBİR şey silmeme, yetim süpürme sınırı,
// bayat yükleme / süresi dolan belge temizliği, hata toleransı, başlat / durdur. Gerçek PostgreSQL doğrulaması: qa_platform_pg.mjs "documents" (I bölümü).
import { describe, it, before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import { EventEmitter } from 'node:events';
import { promises as fsp } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { pool } from '../src/db.js';
import {
  BATCH_LIMIT,
  MAINTENANCE_LOCK,
  runDocumentsMaintenanceOnce,
  startDocumentsMaintenance,
  stopDocumentsMaintenance,
} from '../src/modules/document_maintenance.js';
import { checkStorage, ensureSiteDir, pathForKey, resetStorageCheck } from '../src/modules/document_storage.js';

const SITE = 1000000001;
const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
const ok = (rows = [], rowCount = rows.length) => ({ rows, rowCount });
const uuid = () => crypto.randomUUID();
const OLD = new Date(Date.now() - 30 * 3600_000);
const keyOf = (name) => `${SITE}/${name}`;

let root;
let handlers;
let log;
let released;
let releases; // her release çağrısının `destroy` argümanı
let clients; // bu testte verilen sahte istemciler
let lockResult;
let connectError;
// durumlu sahte DB parçaları (depolama kimliği, var olan siteler, gider belgesi tablosu)
let settingsStore;
let aliveSites;
let expenseTable;
let expenseKeys;
let siteRecords;
let readyKeys;
const IDENTITY = '11111111-2222-4333-8444-555555555555';

function install() {
  const run = async (text, params = []) => {
    const sql = norm(text);
    log.push({ sql, params });
    for (const [pattern, fn] of handlers) {
      if (pattern.test(sql)) return typeof fn === 'function' ? fn(sql, params) : fn;
    }
    if (/^SELECT pg_try_advisory_lock/.test(sql)) return ok([{ locked: lockResult }]);
    if (/^SELECT pg_advisory_unlock/.test(sql)) return ok();
    if (/^(BEGIN|COMMIT|ROLLBACK)$/.test(sql) || /^INSERT INTO audit_log/.test(sql) || /^(SAVEPOINT|RELEASE SAVEPOINT|ROLLBACK TO SAVEPOINT) /.test(sql)) return ok();
    if (/^SELECT site_code FROM sites WHERE site_code = \$1 FOR KEY SHARE$/.test(sql)) return ok([{ site_code: String(params[0]) }]);
    if (/^SELECT value FROM platform_settings WHERE key = \$1 LIMIT 1$/.test(sql)) return ok(settingsStore.has(params[0]) ? [{ value: settingsStore.get(params[0]) }] : []);
    if (/^INSERT INTO platform_settings \(key, value\) VALUES \(\$1, \$2::jsonb\) ON CONFLICT \(key\) DO NOTHING$/.test(sql)) {
      if (!settingsStore.has(params[0])) settingsStore.set(params[0], JSON.parse(params[1]));
      return ok();
    }
    if (/^SELECT site_code FROM sites WHERE site_code = ANY\(\$1::BIGINT\[\]\)$/.test(sql)) return ok(params[0].filter((code) => aliveSites.has(Number(code))).map((code) => ({ site_code: String(code) })));
    if (/^SELECT COUNT\(\*\)::INTEGER AS n FROM sites$/.test(sql)) return ok([{ n: aliveSites.size }]);
    if (/^SELECT to_regclass\('public\.expense_documents'\) IS NOT NULL AS present$/.test(sql)) return ok([{ present: expenseTable }]);
    if (/^SELECT to_regclass\('public\.payment_notices'\) IS NOT NULL AS present$/.test(sql)) return ok([{ present: false }]); // dekont bildirimi (066)
    if (/^SELECT storage_key FROM expense_documents WHERE storage_key = ANY\(\$1::TEXT\[\]\)$/.test(sql)) return ok(params[0].filter((key) => expenseKeys.has(key)).map((storage_key) => ({ storage_key })));
    if (/^SELECT 1 FROM (document_versions|expense_documents) WHERE site_code = \$1 LIMIT 1$/.test(sql)) return ok(siteRecords.has(Number(params[0])) ? [{ x: 1 }] : []);
    if (/^SELECT storage_key FROM (document_versions|expense_documents) WHERE status = 'ready'( AND server_copy = TRUE)? ORDER BY id DESC LIMIT 20$/.test(sql)) return ok(readyKeys.map((storage_key) => ({ storage_key })));
    // varsayılan: boş sonuç (temizlenecek bir şey yok)
    if (/^(SELECT|DELETE)/.test(sql)) return ok();
    throw new Error(`BEKLENMEYEN SQL (sahte DB katı): ${sql.slice(0, 240)}`);
  };
  pool.connect = async () => {
    if (connectError) throw connectError;
    // gerçek pg istemcisi gibi EventEmitter: dinleyicisiz 'error' yayını FIRLATIR (uncaughtException benzetimi)
    const client = Object.assign(new EventEmitter(), {
      query: (text, params) => run(text, params),
      release(destroy) {
        released += 1;
        releases.push(destroy === true);
      },
    });
    clients.push(client);
    return client;
  };
  pool.query = async (text, params) => run(text, params);
}

before(async () => {
  root = await fsp.mkdtemp(path.join(os.tmpdir(), 'doc-maintenance-'));
  process.env.DOCUMENTS_DIR = root;
  process.env.DOCUMENTS_MIN_FREE_BYTES = '0';
  resetStorageCheck();
  assert.equal((await checkStorage({ DOCUMENTS_DIR: root }, { force: true })).ok, true);
  await ensureSiteDir(root, SITE);
});

after(async () => {
  delete pool.query;
  delete pool.connect;
  delete process.env.DOCUMENTS_DIR;
  delete process.env.DOCUMENTS_MIN_FREE_BYTES;
  await fsp.rm(root, { recursive: true, force: true });
});

beforeEach(async () => {
  handlers = [];
  log = [];
  released = 0;
  releases = [];
  clients = [];
  lockResult = true;
  connectError = null;
  settingsStore = new Map([['documents.storage_id', { id: IDENTITY }]]);
  aliveSites = new Set([SITE]);
  expenseTable = false;
  expenseKeys = new Set();
  siteRecords = new Set();
  readyKeys = [];
  install();
  for (const name of await fsp.readdir(path.join(root, 'sites'))) await fsp.rm(path.join(root, 'sites', name), { force: true, recursive: true });
  await ensureSiteDir(root, SITE);
  for (const name of await fsp.readdir(path.join(root, '_tmp'))) await fsp.rm(path.join(root, '_tmp', name), { force: true });
  await fsp.writeFile(path.join(root, '.instance'), `${IDENTITY}\n`);
  await fsp.rm(path.join(root, '_orphans'), { recursive: true, force: true }); // karantina testlerden testlere taşınmasın
});

const files = async () => (await fsp.readdir(path.join(root, 'sites', String(SITE)))).sort();
async function plantOrphans(count, { age = OLD } = {}) {
  const names = [];
  for (let i = 0; i < count; i += 1) {
    const name = uuid();
    const full = pathForKey(root, keyOf(name));
    await fsp.writeFile(full, 'yetim');
    await fsp.utimes(full, age, age);
    names.push(name);
  }
  return names;
}
const knownKeysHandler = (known = []) => [/^SELECT storage_key FROM document_versions WHERE storage_key = ANY\(\$1::TEXT\[\]\)$/, (_sql, params) => ok(params[0].filter((key) => known.includes(key)).map((storage_key) => ({ storage_key })))];

describe('tek çalışan ve bağlantı', () => {
  it('kilit session advisory (0x444F4353, 1) ile alınır ve BIRAKILIR; bağlantı havuza geri verilir', async () => {
    const result = await runDocumentsMaintenanceOnce();
    assert.equal(result.skipped, false);
    assert.deepEqual(MAINTENANCE_LOCK, [0x444f4353, 1]);
    const lock = log.find((entry) => /pg_try_advisory_lock/.test(entry.sql));
    assert.deepEqual(lock.params, MAINTENANCE_LOCK);
    assert.deepEqual(log.find((entry) => /pg_advisory_unlock/.test(entry.sql)).params, MAINTENANCE_LOCK);
    assert.equal(released, 1);
  });

  it('kilit başka oturumdaysa tur ATLANIR (busy) ve hiçbir iş sorgusu gitmez; DB\'ye bağlanılamıyorsa atlanır (db) ve hata fırlatılmaz', async () => {
    lockResult = false;
    const busy = await runDocumentsMaintenanceOnce();
    assert.deepEqual({ skipped: busy.skipped, reason: busy.reason }, { skipped: true, reason: 'busy' });
    assert.equal(log.length, 1, 'yalnız kilit denemesi');
    assert.equal(released, 1);
    connectError = new Error('bağlantı yok');
    const down = await runDocumentsMaintenanceOnce();
    assert.deepEqual({ skipped: down.skipped, reason: down.reason }, { skipped: true, reason: 'db' });
  });
});

describe('yetim dosya süpürmesi', () => {
  it('diskte olup DB\'de olmayan ve 24 saatten ESKİ dosyalar silinir; genç yetim ve DB\'de kayıtlı dosya KORUNUR', async () => {
    const [orphan] = await plantOrphans(1);
    const [young] = await plantOrphans(1, { age: new Date() });
    const [known] = await plantOrphans(1);
    handlers.push(knownKeysHandler([keyOf(known)]));
    const result = await runDocumentsMaintenanceOnce();
    assert.equal(result.summary.orphan_files, 1);
    assert.deepEqual(await files(), [known, young].sort());
    assert.ok(!(await files()).includes(orphan));
  });

  it(`tur başına en çok ${BATCH_LIMIT} dosya silinir; kalanı sonraki turda`, async () => {
    // 400 kayıtlı (eski) dosya + 205 yetim: yetim oranı %34 -> oran koruması tetiklenmez
    const known = await plantOrphans(400);
    const names = await plantOrphans(BATCH_LIMIT + 5);
    handlers.push(knownKeysHandler(known.map(keyOf)));
    const first = await runDocumentsMaintenanceOnce();
    assert.equal(first.summary.orphan_files, BATCH_LIMIT);
    assert.equal(first.summary.guard_trips, 0);
    assert.equal((await files()).length, 400 + 5);
    const second = await runDocumentsMaintenanceOnce();
    assert.equal(second.summary.orphan_files, 5);
    assert.deepEqual(await files(), [...known].sort());
    assert.equal(names.length, BATCH_LIMIT + 5);
  });

  it('ORAN KORUMASI: yetim > 20 ve taranan eski dosyaların %50\'sinden fazlası ise HİÇBİRİ silinmez, uyarılır (yanlış / boş DB belirtisi); 20 ve altı ya da %50 altı silinir', async () => {
    const lines = [];
    const realError = console.error;
    console.error = (...args) => lines.push(args.join(' '));
    try {
      const known = await plantOrphans(5);
      const orphans = await plantOrphans(25);
      handlers.push(knownKeysHandler(known.map(keyOf)));
      const tripped = await runDocumentsMaintenanceOnce();
      assert.equal(tripped.summary.guard_trips, 1);
      assert.equal(tripped.summary.orphan_files, 0);
      assert.equal((await files()).length, 30, 'hiçbir dosya silinmedi');
      assert.ok(lines.some((line) => /ORAN KORUMASI: 25\/30/.test(line)), lines.join('\n'));
      // tam sınır: 20 yetim (20 > 20 DEĞİL) silinir
      for (const name of orphans.slice(0, 5)) await fsp.rm(pathForKey(root, keyOf(name)));
      const boundary = await runDocumentsMaintenanceOnce();
      assert.equal(boundary.summary.guard_trips, 0);
      assert.equal(boundary.summary.orphan_files, 20);
      assert.deepEqual(await files(), [...known].sort());
    } finally {
      console.error = realError;
    }
  });

  it('KAYITLI gider belgesi (expense_documents) dosyası YETİM SAYILMAZ ve silinmez; tablo yoksa sorgu atlanır (hata yok)', async () => {
    const expense = await plantOrphans(2);
    const orphan = await plantOrphans(1);
    expenseTable = true;
    expenseKeys = new Set(expense.map(keyOf));
    handlers.push(knownKeysHandler([]));
    const result = await runDocumentsMaintenanceOnce();
    assert.equal(result.summary.orphan_files, 1);
    assert.deepEqual(await files(), [...expense].sort());
    assert.ok(!(await files()).includes(orphan[0]));
    assert.ok(log.some((entry) => /^SELECT storage_key FROM expense_documents/.test(entry.sql)));
    // tablo henüz yok: gider sorgusu hiç gitmez, süpürme çalışır
    expenseTable = false;
    log.length = 0;
    const again = await plantOrphans(1);
    const second = await runDocumentsMaintenanceOnce();
    assert.equal(second.summary.orphan_files, 3, 'tablo yokken gider dosyaları da yetim görünür (dikiş bağlı DEĞİL)');
    assert.ok(!log.some((entry) => /FROM expense_documents/.test(entry.sql)));
    assert.equal(again.length, 1);
  });

  it('R11 F8 regresyon: HAZIR gider belgesi + 25 saatlik dosya yetim süpürmesinde SİLİNMEZ (gider dikişi henüz bağlı olmasa bile: süpürme yalnız expense_documents anahtarlarına bakar); document_versions kaydı olmayan gider dosyası da korunur', async () => {
    const SOME_HOURS = new Date(Date.now() - 25 * 3600_000);
    const [expenseReady, expenseUploading, version, trueOrphan] = await plantOrphans(4, { age: SOME_HOURS });
    expenseTable = true;
    expenseKeys = new Set([keyOf(expenseReady), keyOf(expenseUploading)]); // status ne olursa olsun (ready / uploading) kayıtlı anahtar korunur
    handlers.push(knownKeysHandler([keyOf(version)]));
    const result = await runDocumentsMaintenanceOnce();
    assert.equal(result.summary.orphan_files, 1, 'yalnız gerçek yetim silinir');
    assert.equal(result.summary.guard_trips, 0);
    assert.deepEqual(await files(), [expenseReady, expenseUploading, version].sort());
    assert.ok(!(await files()).includes(trueOrphan));
    assert.ok(
      log.every((entry) => !/\bFROM expenses\b|finance_|ledger_entries/.test(entry.sql)),
      'süpürme finans tablolarına (expense_documents dışında) bağımlı değildir',
    );
  });

  it('DB\'ye ulaşılamıyorsa (kayıtlı anahtar sorgusu hata verir) HİÇBİR dosya silinmez; hata sayılır; sunucu düşmez', async () => {
    const names = await plantOrphans(3);
    handlers.push([/^SELECT storage_key FROM document_versions WHERE storage_key = ANY/, () => { throw Object.assign(new Error('bağlantı koptu'), { code: '57P01' }); }]);
    const lines = [];
    const realError = console.error;
    console.error = (...args) => lines.push(args.join(' '));
    let result;
    try {
      result = await runDocumentsMaintenanceOnce();
    } finally {
      console.error = realError;
    }
    assert.equal(result.summary.orphan_files, 0);
    assert.ok(result.summary.errors >= 1);
    assert.deepEqual(await files(), [...names].sort(), 'hiçbir dosya silinmedi');
    assert.ok(lines.some((line) => line.includes('57P01')), 'günlükte yalnız hata KODU');
  });

  it('geçersiz adlı dosyalara (uuid olmayan) ve dizinlere dokunulmaz', async () => {
    const dir = path.join(root, 'sites', String(SITE));
    await fsp.writeFile(path.join(dir, 'README.txt'), 'x');
    await fsp.utimes(path.join(dir, 'README.txt'), OLD, OLD);
    await fsp.mkdir(path.join(dir, uuid()));
    handlers.push(knownKeysHandler([]));
    await runDocumentsMaintenanceOnce();
    assert.ok((await fsp.readdir(dir)).includes('README.txt'));
  });
});

describe('bayat yükleme ve süresi dolan belge', () => {
  it('bayat `uploading` sürümün SATIRI ÖNCE silinir (RETURNING anahtar), dosyası SONRA; sürümsüz pending belge kaldırılır; `_tmp` eski kalıntı silinir, yenisi korunur', async () => {
    const [stale] = await plantOrphans(1, { age: new Date() });
    let fileAtRowDelete = null;
    handlers.push(
      [/^SELECT id, document_id, storage_key FROM document_versions WHERE status = 'uploading' AND created_at < NOW\(\) - make_interval\(mins => \$1::INTEGER\)/, ok([{ id: '5', document_id: '9', storage_key: keyOf(stale) }])],
      [
        /^DELETE FROM document_versions WHERE id = \$1 AND status = 'uploading' AND created_at < NOW\(\) - make_interval\(mins => \$2::INTEGER\) RETURNING storage_key$/,
        async () => {
          fileAtRowDelete = (await files()).includes(stale);
          return ok([{ storage_key: keyOf(stale) }], 1);
        },
      ],
      [/^DELETE FROM documents d WHERE d\.status = 'pending'/, ok([], 2)],
    );
    const oldTmp = path.join(root, '_tmp', `${uuid()}.part`);
    const newTmp = path.join(root, '_tmp', `${uuid()}.part`);
    await fsp.writeFile(oldTmp, 'x');
    await fsp.writeFile(newTmp, 'x');
    await fsp.utimes(oldTmp, new Date(Date.now() - 3 * 3600_000), new Date(Date.now() - 3 * 3600_000));
    const result = await runDocumentsMaintenanceOnce();
    assert.equal(result.summary.stale_uploads, 1);
    assert.equal(result.summary.pending_documents, 2);
    assert.equal(result.summary.temp_files, 1);
    assert.equal(fileAtRowDelete, true, 'satır silinirken dosya HENÜZ yerinde: sıra satır -> dosya');
    assert.ok(!(await files()).includes(stale));
    await assert.rejects(fsp.stat(oldTmp), { code: 'ENOENT' });
    await fsp.stat(newTmp);
    const stalePut = log.find((entry) => /^DELETE FROM document_versions/.test(entry.sql));
    assert.deepEqual(stalePut.params, ['5', 120], 'süre koşulu DELETE\'te TEKRAR sınanır (TTL 120 dk)');
  });

  it('R16 P1-1 YARIŞ: seçimden sonra satırı geç gelen PUT `ready` yaptıysa (DELETE 0 satır) DOSYAYA DOKUNULMAZ ve sayaç artmaz; hata sayılmaz', async () => {
    const [raced] = await plantOrphans(1, { age: new Date() });
    handlers.push(
      [/^SELECT id, document_id, storage_key FROM document_versions WHERE status = 'uploading' AND created_at/, ok([{ id: '5', document_id: '9', storage_key: keyOf(raced) }])],
      [/^DELETE FROM document_versions WHERE id = \$1 AND status = 'uploading'/, ok([], 0)],
    );
    const result = await runDocumentsMaintenanceOnce();
    assert.equal(result.summary.stale_uploads, 0, 'sayaç rowCount\'a göre');
    assert.equal(result.summary.errors, 0);
    assert.ok((await files()).includes(raced), 'ready sürümün dosyası silinmedi');
  });

  it('satır silindi ama dosya silinemezse: sayaç artar, hata sayılır (dosya yetim süpürmesine kalır); satır geri gelmez', async () => {
    const stuck = uuid();
    await fsp.mkdir(pathForKey(root, keyOf(stuck))); // dosya yerine dizin
    handlers.push(
      [/^SELECT id, document_id, storage_key FROM document_versions WHERE status = 'uploading'/, ok([{ id: '5', document_id: '9', storage_key: keyOf(stuck) }])],
      [/^DELETE FROM document_versions WHERE id = \$1 AND status = 'uploading'/, ok([{ storage_key: keyOf(stuck) }], 1)],
    );
    const realError = console.error;
    console.error = () => {};
    let result;
    try {
      result = await runDocumentsMaintenanceOnce();
    } finally {
      console.error = realError;
    }
    assert.equal(result.summary.stale_uploads, 1);
    assert.ok(result.summary.errors >= 1);
    await fsp.rmdir(pathForKey(root, keyOf(stuck)));
  });

  it('süresi dolan silinmiş belge: satır FOR UPDATE SKIP LOCKED ile kilitlenir (başkası tutuyorsa atlanır), dosyalar silinir, satır silinir, audit actor Sistem auto:true', async () => {
    const [target] = await plantOrphans(1, { age: new Date() });
    handlers.push(
      [/^SELECT id, site_code FROM documents WHERE status = 'deleted' AND deleted_at < NOW\(\) - make_interval\(days => \$1::INTEGER\)/, ok([{ id: '9', site_code: String(SITE) }, { id: '10', site_code: String(SITE) }])],
      [/^SELECT id, category, audience FROM documents WHERE id = \$1 AND status = 'deleted' .* FOR UPDATE SKIP LOCKED$/, (_sql, params) => (Number(params[0]) === 9 ? ok([{ id: '9', category: 'minutes', audience: 'board' }]) : ok())],
      [/^SELECT storage_key, size_bytes FROM document_versions WHERE document_id = \$1$/, ok([{ storage_key: keyOf(target), size_bytes: '5' }])],
      [/^DELETE FROM documents WHERE id = \$1$/, ok()],
    );
    const result = await runDocumentsMaintenanceOnce();
    assert.equal(result.summary.purged_documents, 1, 'kilitli (10) atlandı');
    assert.ok(!(await files()).includes(target));
    const audit = log.find((entry) => /^INSERT INTO audit_log/.test(entry.sql));
    assert.equal(audit.params[1], 'Sistem');
    assert.equal(audit.params[3], 'document.purged');
    assert.deepEqual(JSON.parse(audit.params[7]), { auto: true, category: 'minutes', audience: 'board', version_count: 1, size_bytes: 5 });
  });

  it('dosya silinemeyen belge: satır COMMIT ile gitmiştir (purged sayılır), dosya yetim kalır; hata sayılır; günlükte dosya yolu / adı yok (R11 F7: dosya COMMIT SONRASI silinir)', async () => {
    const stuck = uuid();
    await fsp.mkdir(pathForKey(root, keyOf(stuck)));
    handlers.push(
      [/^SELECT id, site_code FROM documents WHERE status = 'deleted'/, ok([{ id: '9', site_code: String(SITE) }])],
      [/^SELECT id, category, audience FROM documents WHERE id = \$1 AND status = 'deleted'/, ok([{ id: '9', category: 'other', audience: 'managers' }])],
      [/^SELECT storage_key, size_bytes FROM document_versions WHERE document_id = \$1$/, ok([{ storage_key: keyOf(stuck), size_bytes: '5' }])],
    );
    const lines = [];
    const realError = console.error;
    console.error = (...args) => lines.push(args.join(' '));
    let result;
    try {
      result = await runDocumentsMaintenanceOnce();
    } finally {
      console.error = realError;
    }
    assert.equal(result.summary.purged_documents, 1);
    assert.ok(result.summary.errors >= 1);
    assert.ok(log.some((entry) => /^DELETE FROM documents WHERE id = \$1$/.test(entry.sql)) && log.some((entry) => entry.sql === 'COMMIT') && !log.some((entry) => entry.sql === 'ROLLBACK'));
    assert.ok(!lines.join('\n').includes(stuck), 'günlükte dosya yolu / adı yok');
    await fsp.rmdir(pathForKey(root, keyOf(stuck)));
  });

  it('R11 F7: COMMIT başarısızsa süresi dolan belgenin DOSYASI SİLİNMEZ (satır geri alındı), purged sayılmaz, hata sayılır', async () => {
    const [target] = await plantOrphans(1, { age: new Date() });
    handlers.push(
      [/^SELECT id, site_code FROM documents WHERE status = 'deleted'/, ok([{ id: '9', site_code: String(SITE) }])],
      [/^SELECT id, category, audience FROM documents WHERE id = \$1 AND status = 'deleted'/, ok([{ id: '9', category: 'other', audience: 'managers' }])],
      [/^SELECT storage_key, size_bytes FROM document_versions WHERE document_id = \$1$/, ok([{ storage_key: keyOf(target), size_bytes: '5' }])],
      [/^COMMIT$/, () => { throw Object.assign(new Error('Connection terminated'), { code: '57P01' }); }],
    );
    handlers.push(knownKeysHandler([keyOf(target)]));
    const realError = console.error;
    console.error = () => {};
    let result;
    try {
      result = await runDocumentsMaintenanceOnce();
    } finally {
      console.error = realError;
    }
    assert.equal(result.summary.purged_documents, 0);
    assert.ok(result.summary.errors >= 1);
    assert.ok((await files()).includes(target), 'dosya yerinde');
    assert.ok(log.some((entry) => entry.sql === 'ROLLBACK'));
  });
});

describe('depolama kullanılamıyorsa ve başlat / durdur', () => {
  it('kök dizin depo içindeyse dosya turları ÇALIŞMAZ (dosya silinmez); yalnız sürümsüz pending belgeler DB\'den kaldırılır', async () => {
    const saved = process.env.DOCUMENTS_DIR;
    const inside = path.join(path.resolve(import.meta.dirname, '..', '..'), 'build', 'web', 'asla-olusmamali-bakim');
    handlers.push([/^DELETE FROM documents d WHERE d\.status = 'pending'/, ok([], 3)]);
    resetStorageCheck();
    const result = await runDocumentsMaintenanceOnce({ env: { ...process.env, DOCUMENTS_DIR: inside } });
    process.env.DOCUMENTS_DIR = saved;
    resetStorageCheck();
    assert.equal(result.summary.pending_documents, 3);
    assert.equal(result.summary.stale_uploads + result.summary.purged_documents + result.summary.orphan_files, 0);
    assert.ok(!log.some((entry) => /^SELECT id, document_id, storage_key FROM document_versions|^SELECT id, site_code FROM documents WHERE status = 'deleted'|storage_key = ANY/.test(entry.sql)), 'dosya gerektiren turların sorguları hiç gitmez');
  });

  it('DOCUMENTS_MAINTENANCE_DISABLED=1 ile başlamaz; açıkken ikinci başlatma yok sayılır; durdurma süren turu bekler', async () => {
    assert.equal(startDocumentsMaintenance({ env: { DOCUMENTS_MAINTENANCE_DISABLED: '1' } }), false);
    assert.equal(startDocumentsMaintenance({ env: { ...process.env, DOCUMENTS_MAINTENANCE_DISABLED: '' }, firstDelayMs: 3_600_000, intervalMs: 3_600_000 }), true);
    assert.equal(startDocumentsMaintenance({ env: { ...process.env }, firstDelayMs: 3_600_000 }), false);
    await stopDocumentsMaintenance();
    assert.equal(startDocumentsMaintenance({ env: { ...process.env }, firstDelayMs: 3_600_000, intervalMs: 3_600_000 }), true, 'durdurma sonrası yeniden başlatılabilir');
    await stopDocumentsMaintenance();
  });
});

describe('depolama kimliği (yanlış / boş / eski DB koruması)', () => {
  const blockedRun = async () => {
    const lines = [];
    const realError = console.error;
    console.error = (...args) => lines.push(args.join(' '));
    try {
      return { result: await runDocumentsMaintenanceOnce(), lines };
    } finally {
      console.error = realError;
    }
  };

  it('kimlik UYUŞMUYORSA (başka DB / başka dizin) yetim dosya ve site dizini SİLİNMEZ; günlükte durum yazılır; DB\'den-gelen turlar (bayat yükleme) çalışmaya devam eder', async () => {
    const orphans = await plantOrphans(2);
    const ghost = path.join(root, 'sites', '1999999999');
    await fsp.mkdir(ghost);
    const ghostFile = path.join(ghost, uuid());
    await fsp.writeFile(ghostFile, 'x');
    const eightDays = new Date(Date.now() - 8 * 86400_000);
    await fsp.utimes(ghostFile, eightDays, eightDays);
    await fsp.utimes(ghost, eightDays, eightDays);
    settingsStore.set('documents.storage_id', { id: '99999999-2222-4333-8444-555555555555' });
    handlers.push(knownKeysHandler([]));
    const { result, lines } = await blockedRun();
    assert.equal(result.summary.identity_blocked, 1);
    assert.equal(result.summary.orphan_files + result.summary.site_dirs, 0);
    assert.deepEqual(await files(), [...orphans].sort());
    await fsp.stat(ghostFile);
    assert.ok(lines.some((line) => /durum=mismatch/.test(line) && /DURDURULDU/.test(line)), lines.join('\n'));
    assert.ok(!lines.join('\n').includes(IDENTITY), 'kimlik değeri günlüğe yazılmaz');
    assert.ok(log.some((entry) => /FROM document_versions WHERE status = 'uploading'/.test(entry.sql)), 'DB\'den-gelen tur çalıştı');
    assert.ok(!log.some((entry) => /storage_key = ANY/.test(entry.sql)), 'bilinen anahtar sorgusu bile gitmedi');
  });

  it('dizinde kimlik dosyası YOK ve dizinde dosya var -> reddedilir (file_identity_missing); bozuk kimlik dosyası -> reddedilir', async () => {
    await plantOrphans(1);
    await fsp.rm(path.join(root, '.instance'));
    let { result, lines } = await blockedRun();
    assert.equal(result.summary.identity_blocked, 1);
    assert.ok(lines.some((line) => /durum=file_identity_missing/.test(line)));
    await fsp.writeFile(path.join(root, '.instance'), 'bozuk');
    ({ result, lines } = await blockedRun());
    assert.equal(result.summary.identity_blocked, 1);
    assert.ok(lines.some((line) => /durum=file_identity_invalid/.test(line)));
  });

  it('DB\'de kimlik YOK (yanlış / boş / eski DB) ve dizinde dosya var -> reddedilir (db_identity_missing); dizinde dosya yoksa DB\'ye yazılır (adopted_db)', async () => {
    const [kept] = await plantOrphans(1);
    settingsStore.clear();
    const { result, lines } = await blockedRun();
    assert.equal(result.summary.identity_blocked, 1);
    assert.ok(lines.some((line) => /durum=db_identity_missing/.test(line)));
    assert.deepEqual(await files(), [kept]);
    await fsp.rm(pathForKey(root, keyOf(kept)));
    const ok2 = await runDocumentsMaintenanceOnce();
    assert.equal(ok2.summary.identity_blocked, 0);
    assert.deepEqual(settingsStore.get('documents.storage_id'), { id: IDENTITY }, 'dizindeki kimlik DB\'ye yazıldı');
  });

  it('ilk kullanım (ikisi de yok): dizin boşsa kimlik üretilir ve HER İKİSİNE yazılır; dizinde dosya var ama DB bunları tanımıyorsa reddedilir (unverified_state); DB\'nin bildiği dosyalardan biri diskteyse üretilir', async () => {
    await fsp.rm(path.join(root, '.instance'));
    settingsStore.clear();
    const first = await runDocumentsMaintenanceOnce();
    assert.equal(first.summary.identity_blocked, 0);
    const written = (await fsp.readFile(path.join(root, '.instance'), 'utf8')).trim();
    assert.match(written, /^[0-9a-f-]{36}$/);
    assert.deepEqual(settingsStore.get('documents.storage_id'), { id: written });
    // dizinde tanınmayan dosyalar, DB boş
    await fsp.rm(path.join(root, '.instance'));
    settingsStore.clear();
    await plantOrphans(2);
    const second = await blockedRun();
    assert.equal(second.result.summary.identity_blocked, 1);
    assert.ok(second.lines.some((line) => /durum=unverified_state/.test(line)));
    // DB'nin bildiği (ready) bir dosya diskte VAR -> aynı DB / aynı dizin kanıtı
    const [known] = await plantOrphans(1);
    readyKeys = [keyOf(known)];
    handlers.push(knownKeysHandler([keyOf(known)]));
    const third = await runDocumentsMaintenanceOnce();
    assert.equal(third.summary.identity_blocked, 0);
    assert.ok(settingsStore.has('documents.storage_id'));
  });

  it('eşleşen kimlikle her tur "verified": yazma yok, kimlik değişmez', async () => {
    await runDocumentsMaintenanceOnce();
    assert.ok(!log.some((entry) => /^INSERT INTO platform_settings/.test(entry.sql)));
    assert.equal((await fsp.readFile(path.join(root, '.instance'), 'utf8')).trim(), IDENTITY);
  });
});

describe('silinmiş site dizinleri: koruma', () => {
  const eightDays = new Date(Date.now() - 8 * 86400_000);
  async function plantSiteDir(code, { old = true, files: count = 1 } = {}) {
    const dir = path.join(root, 'sites', String(code));
    await fsp.mkdir(dir, { recursive: true });
    for (let i = 0; i < count; i += 1) {
      const file = path.join(dir, uuid());
      await fsp.writeFile(file, 'x');
      if (old) await fsp.utimes(file, eightDays, eightDays);
    }
    if (old) await fsp.utimes(dir, eightDays, eightDays);
    return dir;
  }
  const exists = (dir) => fsp.stat(dir).then(() => true, () => false);

  it('DB\'de olmayan site dizini: içindekiler de 7 günden eskiyse silinir; yenisi, yakın dosyası olanı ve KAYDI (belge sürümü / gider belgesi) kalanı korunur', async () => {
    const stale = await plantSiteDir(1999999990);
    const recent = await plantSiteDir(1999999991, { old: false });
    const withRecord = await plantSiteDir(1999999992);
    const mixed = await plantSiteDir(1999999993);
    await fsp.writeFile(path.join(mixed, uuid()), 'yeni dosya');
    siteRecords.add(1999999992);
    for (let i = 0; i < 5; i += 1) {
      aliveSites.add(1000000100 + i); // 4 dizinden yalnız 1'i silinebilir: oran koruması tetiklenmez
      await ensureSiteDir(root, 1000000100 + i);
    }
    const result = await runDocumentsMaintenanceOnce();
    assert.equal(result.summary.site_dirs, 1);
    assert.equal(result.summary.guard_trips, 0);
    assert.equal(await exists(stale), false);
    assert.equal(await exists(recent), true);
    assert.equal(await exists(withRecord), true, 'kaydı kalan siteye dokunulmaz');
    assert.equal(await exists(mixed), true, 'yakın zamanda dosya yazılmış dizine dokunulmaz');
  });

  it('YETİM süpürmesi silinmiş sitenin dizinine DOKUNMAZ (o dizini 7 günlük kural ele alır)', async () => {
    const dir = await plantSiteDir(1999999994);
    const [file] = await fsp.readdir(dir);
    const old = new Date(Date.now() - 30 * 3600_000);
    await fsp.utimes(path.join(dir, file), old, old);
    await fsp.utimes(dir, new Date(), new Date());
    handlers.push(knownKeysHandler([]));
    const result = await runDocumentsMaintenanceOnce();
    assert.equal(result.summary.orphan_files, 0);
    assert.deepEqual(await fsp.readdir(dir), [file]);
  });

  it('ORAN KORUMASI: dizinlerin yarısından fazlası (>= 2) silinmiş görünürken ve DB\'de HİÇ site yokken HİÇBİRİ silinmez', async () => {
    const lines = [];
    const realError = console.error;
    console.error = (...args) => lines.push(args.join(' '));
    try {
      const a = await plantSiteDir(1999999980);
      const b = await plantSiteDir(1999999981);
      const c = await plantSiteDir(1999999982);
      // SITE (yaşayan) + 3 silinmiş: 3/4 > %50 ve >= 2
      const tripped = await runDocumentsMaintenanceOnce();
      assert.equal(tripped.summary.guard_trips, 1);
      assert.equal(tripped.summary.site_dirs, 0);
      for (const dir of [a, b, c]) assert.equal(await exists(dir), true);
      assert.ok(lines.some((line) => /ORAN KORUMASI: 3\/4 site dizini/.test(line)), lines.join('\n'));
      // DB'de hiç site yok (boş DB): TEK dizin bile silinmez
      await fsp.rm(b, { recursive: true });
      await fsp.rm(c, { recursive: true });
      aliveSites.clear();
      await fsp.rm(path.join(root, 'sites', String(SITE)), { recursive: true });
      const empty = await runDocumentsMaintenanceOnce();
      assert.equal(empty.summary.guard_trips, 1);
      assert.equal(empty.summary.site_dirs, 0);
      assert.equal(await exists(a), true);
    } finally {
      console.error = realError;
    }
  });
});

describe('bakım bağlantısı: hata dinleyicisi ve kilit güvenliği (R11 F5)', () => {
  const lastClient = () => clients[clients.length - 1];

  it('ödünç alınan bağlantıda \'error\' dinleyicisi VARDIR: bakım sırasında bağlantı koparsa süreç düşmez (uncaughtException yok); dinleyici havuza dönmeden sökülür', async () => {
    const lines = [];
    const realError = console.error;
    console.error = (...args) => lines.push(args.join(' '));
    try {
      handlers.push([/^SELECT storage_key FROM document_versions WHERE status = 'uploading'|FROM document_versions WHERE status = 'uploading'/, () => {
        // bakım sürerken bağlantı kopuyor: dinleyici yoksa EventEmitter 'error' fırlatır
        lastClient().emit('error', Object.assign(new Error('terminating connection'), { code: '57P01' }));
        return ok();
      }]);
      const result = await runDocumentsMaintenanceOnce();
      assert.equal(result.skipped, false);
    } finally {
      console.error = realError;
    }
    assert.ok(lines.some((line) => line.includes('57P01') && line.includes('kilit duser')), lines.join('\n'));
    assert.ok(!lines.join('\n').includes('terminating connection'), 'ayrıntı değil yalnız hata kodu günlüğe yazılır');
    assert.equal(lastClient().listenerCount('error'), 0, 'havuza dönen istemcide dinleyici kalmaz (birikmez)');
    assert.deepEqual(releases, [false], 'normal bitişte bağlantı havuza geri verilir');
  });

  it('kilit AÇILAMAZSA bağlantı havuza geri verilmez, YOK EDİLİR (release(true)); aksi halde kilidi tutan bağlantı havuzda asılı kalırdı', async () => {
    handlers.push([/^SELECT pg_advisory_unlock/, () => { throw Object.assign(new Error('Connection terminated'), { code: '57P01' }); }]);
    const result = await runDocumentsMaintenanceOnce();
    assert.equal(result.skipped, false);
    assert.deepEqual(releases, [true]);
    assert.ok(lastClient().listenerCount('error') >= 1, 'yok edilen istemcide dinleyici KALIR (geç gelen error süreci düşürmesin)');
  });

  it('kilit SORGUSU hata verirse (kilit durumu belirsiz) bağlantı yok edilir ve hata fırlatılmaz', async () => {
    handlers.push([/^SELECT pg_try_advisory_lock/, () => { throw Object.assign(new Error('Connection terminated unexpectedly'), { code: '57P01' }); }]);
    const lines = [];
    const realError = console.error;
    console.error = (...args) => lines.push(args.join(' '));
    let result;
    try {
      result = await runDocumentsMaintenanceOnce();
    } finally {
      console.error = realError;
    }
    assert.equal(result.skipped, false);
    assert.equal(result.summary.errors, 1);
    assert.deepEqual(releases, [true]);
    assert.ok(lines.some((line) => line.includes('bakim hatasi') && line.includes('57P01')));
    assert.ok(!log.some((entry) => /pg_advisory_unlock/.test(entry.sql)), 'kilit hiç alınmadıysa açma denenmez');
  });

  it('kilit başka oturumdaysa (busy) bağlantı NORMAL iade edilir ve dinleyici sökülür', async () => {
    lockResult = false;
    const result = await runDocumentsMaintenanceOnce();
    assert.equal(result.reason, 'busy');
    assert.deepEqual(releases, [false]);
    assert.equal(lastClient().listenerCount('error'), 0);
  });
});

describe('yetim KARANTİNASI (R16 P2-4): aynı DB\'nin eski dökümü geri yüklenirse dosyalar silinmez', () => {
  const quarantineDir = () => path.join(root, '_orphans', String(SITE));
  const quarantined = async () => (await fsp.readdir(quarantineDir()).catch(() => [])).sort();

  it('yetim dosya SİLİNMEZ: _orphans/<site>/ altına taşınır (içerik korunur); genç yetim ve kayıtlı dosya yerinde kalır', async () => {
    const [orphan] = await plantOrphans(1);
    const [young] = await plantOrphans(1, { age: new Date() });
    const [known] = await plantOrphans(1);
    handlers.push(knownKeysHandler([keyOf(known)]));
    const result = await runDocumentsMaintenanceOnce();
    assert.equal(result.summary.orphan_files, 1, 'karantinaya alınan sayısı');
    assert.deepEqual(await files(), [known, young].sort());
    assert.deepEqual(await quarantined(), [orphan]);
    assert.equal(await fsp.readFile(path.join(quarantineDir(), orphan), 'utf8'), 'yetim', 'içerik aynen duruyor');
  });

  it('"eski yedek" senaryosu: satırı kaybolmuş ama dosyası duran 12 belge, bakım turundan sonra da kurtarılabilir (karantinada); DB satırı geri gelince geri konabilir', async () => {
    const names = await plantOrphans(12);
    handlers.push(knownKeysHandler([]));
    const result = await runDocumentsMaintenanceOnce();
    assert.equal(result.summary.orphan_files, 12);
    assert.deepEqual(await files(), []);
    assert.deepEqual(await quarantined(), [...names].sort());
  });

  it('karantina N günü (varsayılan 14) doldurunca silinir; env ile kısaltılabilir; dolmayan dosya kalır', async () => {
    await fsp.mkdir(quarantineDir(), { recursive: true });
    const old = uuid();
    const recent = uuid();
    await fsp.writeFile(path.join(quarantineDir(), old), 'a');
    await fsp.writeFile(path.join(quarantineDir(), recent), 'b');
    await fsp.utimes(path.join(quarantineDir(), old), new Date(Date.now() - 15 * 86400_000), new Date(Date.now() - 15 * 86400_000));
    await fsp.utimes(path.join(quarantineDir(), recent), new Date(Date.now() - 5 * 86400_000), new Date(Date.now() - 5 * 86400_000));
    const first = await runDocumentsMaintenanceOnce();
    assert.equal(first.summary.quarantine_purged, 1);
    assert.deepEqual(await quarantined(), [recent]);
    const short = await runDocumentsMaintenanceOnce({ env: { ...process.env, DOCUMENTS_ORPHAN_QUARANTINE_DAYS: '3' } });
    assert.equal(short.summary.quarantine_purged, 1, 'DOCUMENTS_ORPHAN_QUARANTINE_DAYS=3: 5 günlük dosya da silinir');
    assert.deepEqual(await quarantined(), []);
  });

  it('depolama kimliği DOĞRULANAMAZSA yetim taşıma YAPILMAZ ama süresi dolan karantina yine temizlenir (zaman tabanlı, DB\'ye bağlı değil)', async () => {
    settingsStore.set('documents.storage_id', { id: '99999999-2222-4333-8444-555555555555' });
    const [orphan] = await plantOrphans(1);
    await fsp.mkdir(quarantineDir(), { recursive: true });
    const expired = uuid();
    await fsp.writeFile(path.join(quarantineDir(), expired), 'x');
    await fsp.utimes(path.join(quarantineDir(), expired), new Date(Date.now() - 30 * 86400_000), new Date(Date.now() - 30 * 86400_000));
    const realError = console.error;
    console.error = () => {};
    let result;
    try {
      result = await runDocumentsMaintenanceOnce();
    } finally {
      console.error = realError;
    }
    assert.equal(result.summary.identity_blocked, 1);
    assert.equal(result.summary.orphan_files, 0);
    assert.deepEqual(await files(), [orphan]);
    assert.equal(result.summary.quarantine_purged, 1);
  });

  it('ORAN KORUMASI tetiklenirse hiçbir dosya karantinaya da girmez', async () => {
    const names = await plantOrphans(25);
    const realError = console.error;
    console.error = () => {};
    let result;
    try {
      result = await runDocumentsMaintenanceOnce();
    } finally {
      console.error = realError;
    }
    assert.equal(result.summary.guard_trips, 1);
    assert.equal(result.summary.orphan_files, 0);
    assert.deepEqual(await files(), [...names].sort());
    assert.deepEqual(await quarantined(), []);
  });
});
