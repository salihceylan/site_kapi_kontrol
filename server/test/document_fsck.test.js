// scripts/documents_fsck.mjs (DB'siz, katı sahte veritabanı + gerçek geçici dizin): bilinen anahtarlar document_versions ∪ expense_documents (R9 F3),
// depolama kimliği + oran koruması + silinmiş site dizinleri (R9 F4), çıkış kodları.
import { describe, it, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import { promises as fsp } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { runFsck } from '../scripts/documents_fsck.mjs';
import { IDENTITY_FILE, IDENTITY_SETTING_KEY } from '../src/modules/document_integrity.js';

const ID = '11111111-2222-4333-8444-555555555555';
const OTHER_ID = '99999999-2222-4333-8444-555555555555';
const SITE = 1000000001;
const DEAD_SITE = 1999999999;
const DAY = 86_400_000;

const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
const ok = (rows = []) => ({ rows, rowCount: rows.length });
const uuid = (() => {
  let n = 0;
  return () => {
    n += 1;
    return `123e4567-e89b-42d3-a456-${String(n).padStart(12, '0')}`;
  };
})();

let root;
let state;

function makeState() {
  return {
    sites: new Set([SITE]),
    settings: new Map([[IDENTITY_SETTING_KEY, { id: ID }]]),
    versions: [], // { id, document_id, version_no, status, storage_key, size_bytes, sha256, created_at, site_code }
    expenseTable: true,
    expenses: [], // { id, status, storage_key, size_bytes, sha256, added_at, site_code }
  };
}

const db = {
  async query(text, params = []) {
    const sql = norm(text);
    if (/to_regclass\('public\.expense_documents'\)/.test(sql)) return ok([{ present: state.expenseTable }]);
    if (/to_regclass\('public\.work_item_attachments'\)/.test(sql)) return ok([{ present: false }]); // iş takibi fotoğrafları (047): fsck kapsamı dışında
    if (/^SELECT v\.id, v\.document_id, v\.version_no, v\.status, v\.storage_key, v\.size_bytes, v\.sha256, v\.created_at FROM document_versions v WHERE v\.id > \$1 ORDER BY v\.id LIMIT \$2$/.test(sql)) {
      return ok(state.versions.filter((row) => row.id > params[0]).sort((a, b) => a.id - b.id).slice(0, params[1]));
    }
    if (/^SELECT d\.id, d\.status, d\.storage_key, d\.size_bytes, d\.sha256, d\.added_at AS created_at FROM expense_documents d WHERE d\.id > \$1 ORDER BY d\.id LIMIT \$2$/.test(sql)) {
      return ok(state.expenses.filter((row) => row.id > params[0]).sort((a, b) => a.id - b.id).slice(0, params[1]).map((row) => ({ ...row, created_at: row.added_at })));
    }
    if (/^SELECT site_code FROM sites WHERE site_code = ANY\(\$1::BIGINT\[\]\)$/.test(sql)) {
      return ok(params[0].filter((code) => state.sites.has(Number(code))).map((code) => ({ site_code: String(code) })));
    }
    if (/^SELECT storage_key FROM document_versions WHERE storage_key = ANY\(\$1::TEXT\[\]\)$/.test(sql)) {
      return ok(state.versions.filter((row) => params[0].includes(row.storage_key)).map((row) => ({ storage_key: row.storage_key })));
    }
    if (/^SELECT storage_key FROM expense_documents WHERE storage_key = ANY\(\$1::TEXT\[\]\)$/.test(sql)) {
      return ok(state.expenses.filter((row) => params[0].includes(row.storage_key)).map((row) => ({ storage_key: row.storage_key })));
    }
    if (/^SELECT value FROM platform_settings WHERE key = \$1 LIMIT 1$/.test(sql)) {
      return ok(state.settings.has(params[0]) ? [{ value: state.settings.get(params[0]) }] : []);
    }
    if (/^INSERT INTO platform_settings \(key, value\) VALUES \(\$1, \$2::jsonb\) ON CONFLICT \(key\) DO NOTHING$/.test(sql)) {
      if (!state.settings.has(params[0])) state.settings.set(params[0], JSON.parse(params[1]));
      return ok();
    }
    if (/^SELECT storage_key FROM (document_versions|expense_documents) WHERE status = 'ready' ORDER BY id DESC LIMIT 20$/.test(sql)) {
      const source = /document_versions/.test(sql) ? state.versions : state.expenses;
      return ok(source.filter((row) => row.status === 'ready').map((row) => ({ storage_key: row.storage_key })));
    }
    throw new Error(`BEKLENMEYEN SQL (sahte DB katı): ${sql.slice(0, 200)}`);
  },
};

/** Diske dosya yazar (mtime `ageMs` kadar geride) ve anahtarını döndürür. */
async function plant({ site = SITE, content = 'icerik', ageMs = 3 * DAY } = {}) {
  const dir = path.join(root, 'sites', String(site));
  await fsp.mkdir(dir, { recursive: true });
  const name = uuid();
  const file = path.join(dir, name);
  await fsp.writeFile(file, content);
  const when = new Date(Date.now() - ageMs);
  await fsp.utimes(file, when, when);
  return { key: `${site}/${name}`, file, size: Buffer.byteLength(content), sha256: crypto.createHash('sha256').update(content).digest('hex') };
}

let nextId = 0;
const addVersion = (planted, over = {}) => {
  nextId += 1;
  state.versions.push({
    id: nextId, document_id: nextId, version_no: 1, status: 'ready', storage_key: planted.key, size_bytes: planted.size, sha256: planted.sha256,
    created_at: new Date(Date.now() - 5 * DAY), site_code: SITE, ...over,
  });
};
const addExpense = (planted, over = {}) => {
  nextId += 1;
  state.expenses.push({ id: nextId, status: 'ready', storage_key: planted.key, size_bytes: planted.size, sha256: planted.sha256, added_at: new Date(Date.now() - 5 * DAY), site_code: SITE, ...over });
};
const exists = (file) => fsp.stat(file).then(() => true, () => false);
const run = (options = {}) => runFsck({ root, db, ...options });

beforeEach(async () => {
  root = await fsp.mkdtemp(path.join(os.tmpdir(), 'doc-fsck-'));
  state = makeState();
  await fsp.writeFile(path.join(root, IDENTITY_FILE), `${ID}\n`);
});
afterEach(async () => {
  await fsp.rm(root, { recursive: true, force: true });
});

describe('documents_fsck: rapor', () => {
  it('temiz depo: sürümler + gider belgeleri doğrulanır, çıkış kodu 0, kimlik durumu "eşleşiyor" ve DEĞER içermez', async () => {
    addVersion(await plant());
    addExpense(await plant());
    const result = await run({ verifyHash: true });
    assert.equal(result.versions_checked, 1);
    assert.equal(result.expense_documents_checked, 1);
    assert.equal(result.hash_verified, 2);
    assert.equal(result.exit_code, 0);
    assert.deepEqual(result.identity, { file: 'present', db: 'present', match: true });
    assert.ok(!JSON.stringify(result).includes(ID));
  });

  it('R9 F3: gider belgesi dosyası (expense_documents) YETİM SAYILMAZ ve --fix-orphans onu SİLMEZ; document_versions kaydı olmasa da', async () => {
    const expense = await plant({ ageMs: 10 * DAY });
    addExpense(expense);
    const orphan = await plant({ ageMs: 10 * DAY });
    const report = await run();
    assert.deepEqual(report.orphans.map((entry) => entry.storage_key), [orphan.key]);
    const fixed = await run({ fixOrphans: true });
    assert.equal(fixed.orphans_removed, 1);
    assert.equal(await exists(expense.file), true, 'gider belgesi dosyasına dokunulmadı');
    assert.equal(await exists(orphan.file), false);
    assert.equal(fixed.exit_code, 0);
  });

  it('expense_documents tablosu yokken (Faz 4b öncesi) eski davranış: tablo sorgusu gönderilmez, rapor çalışır', async () => {
    state.expenseTable = false;
    addVersion(await plant());
    const result = await run();
    assert.equal(result.expense_documents_checked, 0);
    assert.equal(result.exit_code, 0);
  });

  it('gider belgesinin dosyası eksikse / boyutu farklıysa KRİTİK (çıkış kodu 2); alıntılanan alanlarda dosya adı ya da başlık yok', async () => {
    const gone = await plant();
    await fsp.rm(gone.file);
    addExpense(gone);
    const wrongSize = await plant({ content: 'abc' });
    addExpense(wrongSize, { size_bytes: 999 });
    const result = await run();
    assert.equal(result.exit_code, 2);
    assert.deepEqual(result.missing.map((entry) => Object.keys(entry).sort()), [['expense_document_id', 'reason', 'storage_key']]);
    assert.equal(result.size_mismatch.length, 1);
  });

  it('boyut / hash uyuşmazlığı ve bayat yükleme: 2 / 2 / 1', async () => {
    const planted = await plant({ content: 'dogru' });
    addVersion(planted, { sha256: 'a'.repeat(64) });
    const result = await run({ verifyHash: true });
    assert.equal(result.hash_mismatch.length, 1);
    assert.equal(result.exit_code, 2);
    state = makeState();
    addVersion({ key: `${SITE}/${uuid()}`, size: 1, sha256: null }, { status: 'uploading', created_at: new Date(Date.now() - 3 * 3_600_000) });
    addVersion({ key: `${SITE}/${uuid()}`, size: 1, sha256: null }, { status: 'uploading', created_at: new Date() });
    const stale = await run();
    assert.equal(stale.stale_uploading.length, 1);
    assert.equal(stale.exit_code, 1);
  });
});

describe('documents_fsck: --fix-orphans korumaları (R9 F4)', () => {
  it('genç yetim (24 saatten yeni) silinmez; yaşlı olanlar silinir; kalan yetim çıkış kodunu 1 yapar', async () => {
    const old1 = await plant();
    const old2 = await plant();
    const young = await plant({ ageMs: 3_600_000 });
    addVersion(await plant());
    const result = await run({ fixOrphans: true });
    assert.equal(result.orphans.length, 3);
    assert.equal(result.orphans_removed, 2);
    assert.equal(await exists(old1.file), false);
    assert.equal(await exists(old2.file), false);
    assert.equal(await exists(young.file), true);
    assert.equal(result.exit_code, 1);
  });

  it('kimlik UYUŞMUYORSA hiçbir şey silinmez, guard_tripped + çıkış kodu 1; --force kimlik korumasını AŞMAZ', async () => {
    state.settings.set(IDENTITY_SETTING_KEY, { id: OTHER_ID });
    const orphan = await plant();
    const result = await run({ fixOrphans: true });
    assert.equal(result.guard_tripped, true);
    assert.equal(result.orphans_removed, 0);
    assert.equal(result.identity.state, 'mismatch');
    assert.equal(result.exit_code, 1);
    const forced = await run({ fixOrphans: true, force: true });
    assert.equal(forced.orphans_removed, 0);
    assert.equal(await exists(orphan.file), true);
  });

  it('DB\'de kimlik yoksa (boş / yanlış DB) ve dizinde dosya varsa silme reddedilir (db_identity_missing)', async () => {
    state.settings.clear();
    const orphan = await plant();
    const result = await run({ fixOrphans: true });
    assert.equal(result.identity.state, 'db_identity_missing');
    assert.equal(result.orphans_removed, 0);
    assert.equal(await exists(orphan.file), true);
  });

  it('ORAN KORUMASI: yetim > 20 ve eski dosyaların >%50\'si ise silinmez; --force oran korumasını aşar (çalıştırma başına en çok 200)', async () => {
    for (let i = 0; i < 25; i += 1) await plant();
    for (let i = 0; i < 5; i += 1) addVersion(await plant());
    const guarded = await run({ fixOrphans: true });
    assert.equal(guarded.orphans.length, 25);
    assert.equal(guarded.guard_tripped, true);
    assert.equal(guarded.orphans_removed, 0);
    assert.equal(guarded.exit_code, 1);
    const forced = await run({ fixOrphans: true, force: true });
    assert.equal(forced.orphans_removed, 25);
    assert.equal(forced.guard_tripped, false);
    assert.equal(forced.exit_code, 0);
  });

  it('oran korumasının altı (25 yetim ama 100 bilinen dosya = %20) silinir', async () => {
    for (let i = 0; i < 25; i += 1) await plant();
    for (let i = 0; i < 100; i += 1) addVersion(await plant());
    const result = await run({ fixOrphans: true });
    assert.equal(result.guard_tripped, false);
    assert.equal(result.orphans_removed, 25);
  });

  it('silinmiş (DB\'de olmayan) sitenin dizini: yetimler RAPORLANIR ama --fix-orphans onlara dokunmaz', async () => {
    const ghost = await plant({ site: DEAD_SITE, ageMs: 30 * DAY });
    const result = await run({ fixOrphans: true });
    assert.equal(result.orphans.length, 1);
    assert.equal(result.orphans[0].site_exists, false);
    assert.equal(result.orphans_skipped_deleted_sites, 1);
    assert.equal(result.orphans_removed, 0);
    assert.equal(await exists(ghost.file), true);
    assert.equal(result.exit_code, 1);
  });

  it('salt okunur rapor (--fix-orphans yok) hiçbir şeyi silmez ve kimliğe yazmaz', async () => {
    state.settings.clear();
    const orphan = await plant();
    const result = await run();
    assert.equal(await exists(orphan.file), true);
    assert.equal(state.settings.size, 0);
    assert.deepEqual(result.identity, { file: 'present', db: 'absent', match: false });
  });
});

describe('documents_fsck: --adopt-storage-id', () => {
  it('dizinde var / DB\'de yok -> DB\'ye yazılır ve aynı çalıştırmadaki --fix-orphans artık çalışır', async () => {
    state.settings.clear();
    const orphan = await plant();
    const result = await run({ adoptStorageId: true, fixOrphans: true });
    assert.equal(result.identity.adopted, 'adopted_db');
    assert.deepEqual(state.settings.get(IDENTITY_SETTING_KEY), { id: ID });
    assert.equal(result.identity.ok, true);
    assert.equal(result.orphans_removed, 1);
    assert.equal(await exists(orphan.file), false);
  });

  it('DB\'de var / dizinde yok -> dizine yazılır', async () => {
    await fsp.rm(path.join(root, IDENTITY_FILE));
    const result = await run({ adoptStorageId: true });
    assert.equal(result.identity.adopted, 'adopted_file');
    assert.equal((await fsp.readFile(path.join(root, IDENTITY_FILE), 'utf8')).trim(), ID);
  });

  it('ikisi de var ve FARKLI -> hata fırlatır (elle karar); hiçbir şey değişmez', async () => {
    state.settings.set(IDENTITY_SETTING_KEY, { id: OTHER_ID });
    await assert.rejects(run({ adoptStorageId: true }), /FARKLI/);
    assert.deepEqual(state.settings.get(IDENTITY_SETTING_KEY), { id: OTHER_ID });
    assert.equal((await fsp.readFile(path.join(root, IDENTITY_FILE), 'utf8')).trim(), ID);
  });
});

describe('documents_fsck: yetim KARANTİNASI (R16 P2-4)', () => {
  const quarantineFiles = async () => {
    const entries = [];
    for (const site of await fsp.readdir(path.join(root, '_orphans')).catch(() => [])) {
      for (const name of await fsp.readdir(path.join(root, '_orphans', site))) entries.push(`${site}/${name}`);
    }
    return entries.sort();
  };

  it('--fix-orphans yetim dosyayı SİLMEZ, karantinaya alır (içerik korunur); sayı orphans_removed (karantinaya alınan) olarak raporlanır', async () => {
    const orphan = await plant({ content: 'kurtarilabilir' });
    const result = await run({ fixOrphans: true });
    assert.equal(result.orphans_removed, 1);
    assert.equal(await exists(orphan.file), false);
    assert.deepEqual(await quarantineFiles(), [orphan.key]);
    assert.equal(await fsp.readFile(path.join(root, '_orphans', orphan.key), 'utf8'), 'kurtarilabilir');
    assert.equal(result.exit_code, 0);
  });

  it('--report karantinayı HER ZAMAN gösterir: dosya sayısı, bayt, en eski yaş; kaydı DB\'de olanlar "geri alınabilir"', async () => {
    const orphan = await plant();
    const recoverable = await plant({ content: 'eski-yedek-belge' });
    await run({ fixOrphans: true });
    addVersion(recoverable); // eski dökümden sonra satır geri geldi
    const old = new Date(Date.now() - 5 * DAY);
    await fsp.utimes(path.join(root, '_orphans', orphan.key), old, old);
    const report = await run();
    assert.equal(report.quarantine.files, 2);
    assert.ok(report.quarantine.bytes > 0);
    assert.equal(report.quarantine.oldest_age_days, 5);
    assert.deepEqual(report.quarantine.restorable, [recoverable.key]);
    assert.equal(report.quarantine.restored, 0);
    assert.ok(report.missing.some((entry) => entry.storage_key === recoverable.key && entry.in_quarantine === true), 'eksik dosya karantinada olduğu için işaretlenir');
    assert.equal(report.exit_code, 2, 'eksik dosya hâlâ kritik');
  });

  it('--restore-quarantine: kaydı DB\'de olan karantina dosyalarını yerine koyar; kaydı olmayan karantinada kalır; yerinde dosya varsa dokunmaz', async () => {
    const orphan = await plant({ content: 'gercekten-yetim' });
    const recoverable = await plant({ content: 'geri-gelecek' });
    await run({ fixOrphans: true });
    addVersion(recoverable);
    const result = await run({ restoreQuarantine: true });
    assert.equal(result.quarantine.restored, 1);
    assert.deepEqual(result.quarantine.restorable, []);
    assert.equal(await fsp.readFile(recoverable.file, 'utf8'), 'geri-gelecek');
    assert.deepEqual(await quarantineFiles(), [orphan.key]);
    assert.equal(result.missing.length, 0);
    const again = await run({ restoreQuarantine: true });
    assert.equal(again.quarantine.restored, 0);
  });

  it('karantina yoksa quarantine alanı sıfırdır ve rapor temizdir', async () => {
    addVersion(await plant());
    const report = await run();
    assert.deepEqual(report.quarantine, { files: 0, bytes: 0, oldest_age_days: null, restorable: [], restored: 0 });
    assert.equal(report.exit_code, 0);
  });
});
