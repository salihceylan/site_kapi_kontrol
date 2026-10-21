// Belgeler (Faz 3b-A) depolama bütünlüğü yardımcıları (DB'siz, katı sahte veritabanı + gerçek geçici dizin):
// bilinen anahtarlar (document_versions ∪ expense_documents), oran korumaları, depolama kimliği durum makinesi (R9 F3 + F4).
import { describe, it, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { promises as fsp } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {
  IDENTITY_FILE,
  IDENTITY_SETTING_KEY,
  adoptStorageIdentity,
  ensureStorageIdentity,
  expenseTableExists,
  inspectStorageIdentity,
  loadKnownKeys,
  orphanGuardTripped,
  siteHasRecords,
  siteDirGuardTripped,
} from '../src/modules/document_integrity.js';

const ID_A = '11111111-2222-4333-8444-555555555555';
const ID_B = '99999999-2222-4333-8444-555555555555';
const SITE = '1000000001';
const KEY = (n) => `${SITE}/123e4567-e89b-42d3-a456-4266141740${String(n).padStart(2, '0')}`;

const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
const ok = (rows = []) => ({ rows, rowCount: rows.length });

/** Katı sahte DB: bilinmeyen SQL hata verir. */
function fakeDb({ settings = new Map(), versions = [], expenseTable = true, expenses = [], attachmentTable = false, attachments = [], racer = null, failWith = null } = {}) {
  const log = [];
  return {
    log,
    settings,
    async query(text, params = []) {
      const sql = norm(text);
      log.push({ sql, params });
      if (failWith) throw failWith;
      if (/to_regclass\('public\.expense_documents'\)/.test(sql)) return ok([{ present: expenseTable }]);
      if (/to_regclass\('public\.payment_notices'\)/.test(sql)) return ok([{ present: false }]); // dekont bildirimi (066): bu testlerde yok
      // iş takibi fotoğrafları (047): kimlik örneklemesi work_attachments/ alt ağacını da tanır
      if (/to_regclass\('public\.work_item_attachments'\)/.test(sql)) return ok([{ present: attachmentTable }]);
      if (/^SELECT storage_key FROM work_item_attachments WHERE status = 'ready' ORDER BY id DESC LIMIT 20$/.test(sql)) {
        return ok(attachments.filter((row) => row.status === 'ready').map((row) => ({ storage_key: row.storage_key })));
      }
      if (/^SELECT value FROM platform_settings WHERE key = \$1 LIMIT 1$/.test(sql)) {
        return ok(settings.has(params[0]) ? [{ value: settings.get(params[0]) }] : []);
      }
      if (/^INSERT INTO platform_settings \(key, value\) VALUES \(\$1, \$2::jsonb\) ON CONFLICT \(key\) DO NOTHING$/.test(sql)) {
        if (!settings.has(params[0])) settings.set(params[0], racer ? { id: racer } : JSON.parse(params[1]));
        return ok();
      }
      if (/^SELECT storage_key FROM document_versions WHERE storage_key = ANY\(\$1::TEXT\[\]\)$/.test(sql)) {
        return ok(versions.filter((row) => params[0].includes(row.storage_key)).map((row) => ({ storage_key: row.storage_key })));
      }
      if (/^SELECT storage_key FROM expense_documents WHERE storage_key = ANY\(\$1::TEXT\[\]\)$/.test(sql)) {
        return ok(expenses.filter((row) => params[0].includes(row.storage_key)).map((row) => ({ storage_key: row.storage_key })));
      }
      if (/^SELECT storage_key FROM document_versions WHERE status = 'ready' ORDER BY id DESC LIMIT 20$/.test(sql)) {
        return ok(versions.filter((row) => row.status === 'ready').map((row) => ({ storage_key: row.storage_key })));
      }
      if (/^SELECT storage_key FROM expense_documents WHERE status = 'ready' ORDER BY id DESC LIMIT 20$/.test(sql)) {
        return ok(expenses.filter((row) => row.status === 'ready').map((row) => ({ storage_key: row.storage_key })));
      }
      if (/^SELECT 1 FROM document_versions WHERE site_code = \$1 LIMIT 1$/.test(sql)) {
        return ok(versions.some((row) => String(row.site_code) === String(params[0])) ? [{ x: 1 }] : []);
      }
      if (/^SELECT 1 FROM expense_documents WHERE site_code = \$1 LIMIT 1$/.test(sql)) {
        return ok(expenses.some((row) => String(row.site_code) === String(params[0])) ? [{ x: 1 }] : []);
      }
      throw new Error(`BEKLENMEYEN SQL (sahte DB katı): ${sql.slice(0, 200)}`);
    },
  };
}

describe('bilinen anahtarlar: document_versions ∪ expense_documents (R9 F3)', () => {
  it('expenseTableExists: to_regclass sonucunu yansıtır', async () => {
    assert.equal(await expenseTableExists(fakeDb({ expenseTable: true })), true);
    assert.equal(await expenseTableExists(fakeDb({ expenseTable: false })), false);
  });

  it('iki tablodaki anahtarlar birleşir; tablo yoksa gider sorgusu HİÇ gönderilmez', async () => {
    const db = fakeDb({ versions: [{ storage_key: KEY(1) }], expenses: [{ storage_key: KEY(2) }] });
    assert.deepEqual([...(await loadKnownKeys(db, [KEY(1), KEY(2), KEY(3)]))].sort(), [KEY(1), KEY(2)]);
    const noExpense = fakeDb({ versions: [{ storage_key: KEY(1) }], expenses: [{ storage_key: KEY(2) }], expenseTable: false });
    assert.deepEqual([...(await loadKnownKeys(noExpense, [KEY(1), KEY(2)]))], [KEY(1)]);
    assert.ok(!noExpense.log.some((entry) => /FROM expense_documents/.test(entry.sql)));
  });

  it('boş anahtar listesi sorgu atmaz; sorgu hatası YUTULMAZ (çağıran hiçbir şey silmemeli)', async () => {
    const db = fakeDb();
    assert.equal((await loadKnownKeys(db, [])).size, 0);
    assert.equal(db.log.length, 0);
    await assert.rejects(loadKnownKeys(fakeDb({ failWith: Object.assign(new Error('x'), { code: '57014' }) }), [KEY(1)]), { code: '57014' });
  });

  it('siteHasRecords: belge sürümü ya da gider belgesi olan siteye "kayıt var" der', async () => {
    const db = fakeDb({ versions: [{ site_code: 1000000001 }], expenses: [{ site_code: 1000000002 }] });
    assert.equal(await siteHasRecords(db, 1000000001), true);
    assert.equal(await siteHasRecords(db, 1000000002), true);
    assert.equal(await siteHasRecords(db, 1000000003), false);
    assert.equal(await siteHasRecords(fakeDb({ expenses: [{ site_code: 1000000002 }], expenseTable: false }), 1000000002), false);
  });
});

describe('oran korumaları (R9 F4)', () => {
  it('yetim: sayı > 20 VE oran > %50 gerekir; sınırlar dahil değildir', () => {
    assert.equal(orphanGuardTripped({ orphans: 20, scanned: 20 }), false, '20 yetim: sayı sınırı aşılmadı');
    assert.equal(orphanGuardTripped({ orphans: 21, scanned: 21 }), true);
    assert.equal(orphanGuardTripped({ orphans: 21, scanned: 42 }), false, 'tam %50: aşılmadı');
    assert.equal(orphanGuardTripped({ orphans: 22, scanned: 43 }), true);
    assert.equal(orphanGuardTripped({ orphans: 21, scanned: 60 }), false, '%35');
    assert.equal(orphanGuardTripped({ orphans: 21, scanned: 0 }), true, 'taranan 0 ise oran 1 sayılır');
    assert.equal(orphanGuardTripped({ orphans: 0, scanned: 0 }), false);
  });

  it('site dizini: kaldırılacak yoksa false; DB\'de hiç site yokken kaldırma true; >= 2 ve >%50 ise true', () => {
    assert.equal(siteDirGuardTripped({ removable: 0, totalDirs: 5, siteCount: 0 }), false);
    assert.equal(siteDirGuardTripped({ removable: 1, totalDirs: 1, siteCount: 0 }), true, 'boş DB: tek dizin bile silinmez');
    assert.equal(siteDirGuardTripped({ removable: 1, totalDirs: 1, siteCount: 3 }), false, 'tek silinmiş site olağan durum');
    assert.equal(siteDirGuardTripped({ removable: 1, totalDirs: 10, siteCount: 9 }), false);
    assert.equal(siteDirGuardTripped({ removable: 2, totalDirs: 4, siteCount: 2 }), false, 'tam %50');
    assert.equal(siteDirGuardTripped({ removable: 3, totalDirs: 4, siteCount: 1 }), true);
    assert.equal(siteDirGuardTripped({ removable: 2, totalDirs: 3, siteCount: 1 }), true);
  });
});

describe('depolama kimliği durum makinesi (R9 F4)', () => {
  let root;
  beforeEach(async () => {
    root = await fsp.mkdtemp(path.join(os.tmpdir(), 'doc-integrity-'));
  });
  afterEach(async () => {
    await fsp.rm(root, { recursive: true, force: true });
  });

  const writeIdentity = (id) => fsp.writeFile(path.join(root, IDENTITY_FILE), `${id}\n`);
  const readIdentity = async () => (await fsp.readFile(path.join(root, IDENTITY_FILE), 'utf8').catch(() => null))?.trim() ?? null;
  const plantFile = async (n) => {
    await fsp.mkdir(path.join(root, 'sites', SITE), { recursive: true });
    await fsp.writeFile(path.join(root, 'sites', KEY(n)), 'x');
    return KEY(n);
  };
  const settingsOf = (id) => new Map(id ? [[IDENTITY_SETTING_KEY, { id }]] : []);

  it('dosya + DB eşit -> verified (yazma yok); farklı -> mismatch; bozuk dosya -> file_identity_invalid', async () => {
    await writeIdentity(ID_A);
    const db = fakeDb({ settings: settingsOf(ID_A) });
    assert.deepEqual(await ensureStorageIdentity(db, root), { ok: true, state: 'verified' });
    assert.ok(!db.log.some((entry) => /^INSERT/.test(entry.sql)));
    assert.deepEqual(await ensureStorageIdentity(fakeDb({ settings: settingsOf(ID_B) }), root), { ok: false, state: 'mismatch' });
    await fsp.writeFile(path.join(root, IDENTITY_FILE), 'bozuk-icerik');
    assert.deepEqual(await ensureStorageIdentity(fakeDb({ settings: settingsOf(ID_A) }), root), { ok: false, state: 'file_identity_invalid' });
  });

  it('DB değeri bozuksa (uuid değil / nesne değil) kimlik YOK sayılır ve üzerine yazılmaz: doğrulama başarısız kalır (silme yapılmaz)', async () => {
    await writeIdentity(ID_A);
    for (const value of [{ id: 'uuid-degil' }, { id: 42 }, 'metin', null]) {
      const db = fakeDb({ settings: new Map([[IDENTITY_SETTING_KEY, value]]) });
      const result = await ensureStorageIdentity(db, root);
      assert.equal(result.ok, false, JSON.stringify(value));
      assert.deepEqual(db.settings.get(IDENTITY_SETTING_KEY), value, 'var olan satır ezilmez (ON CONFLICT DO NOTHING)');
    }
  });

  it('ikisi de yok: dizin boşsa kimlik üretilir ve HER İKİSİNE yazılır (initialized)', async () => {
    const db = fakeDb();
    const result = await ensureStorageIdentity(db, root);
    assert.deepEqual(result, { ok: true, state: 'initialized' });
    const id = await readIdentity();
    assert.match(id, /^[0-9a-f-]{36}$/);
    assert.deepEqual(db.settings.get(IDENTITY_SETTING_KEY), { id });
    assert.deepEqual(await ensureStorageIdentity(db, root), { ok: true, state: 'verified' });
  });

  it('ikisi de yok + dizinde dosyalar var: DB bunları TANIMIYORSA reddedilir (unverified_state); DB\'nin bildiği bir dosya diskteyse (document_versions ya da expense_documents) başlatılır', async () => {
    const key = await plantFile(1);
    await plantFile(2);
    assert.deepEqual(await ensureStorageIdentity(fakeDb(), root), { ok: false, state: 'unverified_state' });
    assert.equal(await readIdentity(), null, 'reddedilen durumda dosya yazılmaz');
    assert.deepEqual(await ensureStorageIdentity(fakeDb({ versions: [{ storage_key: key, status: 'ready' }] }), root), { ok: true, state: 'initialized' });
    await fsp.rm(path.join(root, IDENTITY_FILE));
    assert.deepEqual(await ensureStorageIdentity(fakeDb({ expenses: [{ storage_key: key, status: 'ready' }] }), root), { ok: true, state: 'initialized' });
    await fsp.rm(path.join(root, IDENTITY_FILE));
    assert.deepEqual(await ensureStorageIdentity(fakeDb({ versions: [{ storage_key: KEY(9), status: 'ready' }] }), root), { ok: false, state: 'unverified_state' }, 'DB başka bir kuruluma ait');
  });

  it('iş takibi fotoğrafları (047): YALNIZ work_attachments/ altında dosya varken de dizin "dolu" sayılır (yanlış / boş DB kimliği benimseyemez); DB\'nin bildiği hazır fotoğraf diskteyse kimlik başlatılır', async () => {
    await fsp.mkdir(path.join(root, 'work_attachments', SITE), { recursive: true });
    const key = KEY(7);
    await fsp.writeFile(path.join(root, 'work_attachments', key), 'foto');
    assert.deepEqual(await ensureStorageIdentity(fakeDb(), root), { ok: false, state: 'unverified_state' }, 'fotoğraf ağacı dolu, DB tanımıyor');
    assert.deepEqual(await ensureStorageIdentity(fakeDb({ attachmentTable: true, attachments: [{ storage_key: KEY(8), status: 'ready' }] }), root), { ok: false, state: 'unverified_state' });
    assert.equal(await readIdentity(), null, 'reddedilen durumda dosya yazılmaz');
    assert.deepEqual(await ensureStorageIdentity(fakeDb({ attachmentTable: true, attachments: [{ storage_key: key, status: 'ready' }] }), root), { ok: true, state: 'initialized' });
    await fsp.rm(path.join(root, IDENTITY_FILE));
    await writeIdentity(ID_A);
    assert.deepEqual(await ensureStorageIdentity(fakeDb(), root), { ok: false, state: 'db_identity_missing' }, 'yalnız dosya kimliği + fotoğraf var: DB benimsenmez');
  });

  it('yalnız dosya var: dizinde dosya yoksa DB\'ye yazılır (adopted_db); dosya varsa reddedilir (db_identity_missing: yanlış / boş / eski DB)', async () => {
    await writeIdentity(ID_A);
    const db = fakeDb();
    assert.deepEqual(await ensureStorageIdentity(db, root), { ok: true, state: 'adopted_db' });
    assert.deepEqual(db.settings.get(IDENTITY_SETTING_KEY), { id: ID_A });
    await plantFile(1);
    assert.deepEqual(await ensureStorageIdentity(fakeDb(), root), { ok: false, state: 'db_identity_missing' });
  });

  it('yalnız DB var: dizinde dosya yoksa dosyaya yazılır (adopted_file); dosya varsa reddedilir (file_identity_missing: başka dizin)', async () => {
    assert.deepEqual(await ensureStorageIdentity(fakeDb({ settings: settingsOf(ID_B) }), root), { ok: true, state: 'adopted_file' });
    assert.equal(await readIdentity(), ID_B);
    await fsp.rm(path.join(root, IDENTITY_FILE));
    await plantFile(1);
    assert.deepEqual(await ensureStorageIdentity(fakeDb({ settings: settingsOf(ID_B) }), root), { ok: false, state: 'file_identity_missing' });
    assert.equal(await readIdentity(), null);
  });

  it('eşzamanlı başlatma yarışı: DB\'ye başka kimlik yazılmışsa bizim dosya geri alınır ve reddedilir (race)', async () => {
    const db = fakeDb({ racer: ID_B });
    assert.deepEqual(await ensureStorageIdentity(db, root), { ok: false, state: 'race' });
    assert.equal(await readIdentity(), null);
  });

  it('DB hatası FIRLAR (çağıran silme yapmamalı); durum çıktısında kimlik değeri yoktur', async () => {
    await writeIdentity(ID_A);
    await assert.rejects(ensureStorageIdentity(fakeDb({ failWith: Object.assign(new Error('baglanti yok'), { code: 'ECONNREFUSED' }) }), root), { code: 'ECONNREFUSED' });
    const inspected = await inspectStorageIdentity(fakeDb({ settings: settingsOf(ID_A) }), root);
    assert.deepEqual(inspected, { file: 'present', db: 'present', match: true });
    assert.ok(!JSON.stringify(inspected).includes(ID_A));
    assert.deepEqual(await inspectStorageIdentity(fakeDb({ settings: settingsOf(ID_B) }), root), { file: 'present', db: 'present', match: false });
    assert.deepEqual(await inspectStorageIdentity(fakeDb(), root), { file: 'present', db: 'absent', match: false });
  });

  it('adoptStorageIdentity (operatör): güvenli yönleri yapar; iki kimlik FARKLIysa ya da dosya bozuksa fırlatır', async () => {
    const empty = fakeDb();
    assert.equal(await adoptStorageIdentity(empty, root), 'initialized');
    const id = await readIdentity();
    assert.equal(await adoptStorageIdentity(empty, root), 'already');
    await fsp.rm(path.join(root, IDENTITY_FILE));
    assert.equal(await adoptStorageIdentity(empty, root), 'adopted_file');
    assert.equal(await readIdentity(), id);
    const noDb = fakeDb();
    assert.equal(await adoptStorageIdentity(noDb, root), 'adopted_db');
    assert.deepEqual(noDb.settings.get(IDENTITY_SETTING_KEY), { id });
    await assert.rejects(adoptStorageIdentity(fakeDb({ settings: settingsOf(ID_B) }), root), /FARKLI/);
    await fsp.writeFile(path.join(root, IDENTITY_FILE), 'bozuk');
    await assert.rejects(adoptStorageIdentity(fakeDb(), root), /bozuk/);
  });
});
