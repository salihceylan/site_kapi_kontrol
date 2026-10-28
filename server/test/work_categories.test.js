// İş Takibi kategorileri (100; DB'siz): anahtar / ad kuralları, migration 100 <-> work_categories_schema.js aynı DDL (ekleyici, idempotent), katalog kontrollü ensure,
// CRUD hizmeti (bellek içi sahte veritabanı: ekle / yeniden adlandır / pasife al / sil, KULLANILMIŞ kategori silinmez PASİFE alınır, son etkin kategori korunur,
// varsayılan kategori silinmez, ad tekilliği, 40 sınırı), talep açarken kullanılabilirlik denetimi, sakin listesi, rapor / eşleyicilerde kategori adı.
// Gerçek PostgreSQL doğrulaması: scripts/qa_work_categories_pg.mjs (C bölümü: CRUD, yetki, kısıtlar, yarış) + scripts/qa_platform_pg.mjs "chain" (şema eşitliği), "work_tracking", "account" (FK politika katalogu).
import { describe, it, before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { DEFAULT_MIGRATIONS_DIR, findUnsafeStatements, listMigrations } from '../scripts/migrate.js';
import { pool } from '../src/db.js';
import { WORK_CATEGORIES_DDL, WORK_CATEGORIES_DDL_ORDER, ensureWorkCategoriesSchema, schemaTuning } from '../src/modules/work_categories_schema.js';
import {
  CATEGORY_LABEL_MAX,
  CUSTOM_KEY_PATTERN,
  DEFAULT_CATEGORY_KEYS,
  DEFAULT_WORK_CATEGORIES,
  WORK_CATEGORY_LIMIT,
  categoryLabelOf,
  foldLabel,
  isCategoryKey,
  mapWorkCategory,
  nextSortOrder,
  normalizeCategoryLabel,
  parseActiveFilter,
  parseCategoryCreateBody,
  parseCategoryPatchBody,
  pickCategoryKey,
  slugOfLabel,
} from '../src/modules/work_categories_common.js';
import { assertWorkCategoryUsable, ensureDefaultWorkCategories, listMyWorkCategories, listWorkCategories } from '../src/modules/work_categories_read.js';
import { createWorkCategory, deleteWorkCategory, updateWorkCategory } from '../src/modules/work_categories_service.js';
import { CATEGORIES, mapManagerItem, mapResidentItem, parseCreateInput, parseListQuery } from '../src/modules/work_tracking_common.js';
import { assembleReport } from '../src/modules/work_tracking_report.js';

schemaTuning.retryDelayMs = 1;

const here = path.dirname(fileURLToPath(import.meta.url));
const read = (...parts) => readFileSync(path.join(here, '..', ...parts), 'utf8').replace(/\r\n/g, '\n');
const MIGRATION = readFileSync(path.join(DEFAULT_MIGRATIONS_DIR, '100_work_categories.sql'), 'utf8').replace(/\r\n/g, '\n');
const DB_SOURCE = read('src', 'db.js');
const norm = (text) => String(text).replace(/\s+/g, ' ').trim();

function normalizeSql(text) {
  return text.replace(/\/\*[\s\S]*?\*\//g, ' ').replace(/--.*$/gm, ' ').replace(/\s+/g, ' ').trim();
}

/** Migration metnini üst düzey ifadelere böler ($$ gövdelerindeki ';' sayılmaz). */
function splitStatements(sqlText) {
  const text = sqlText.replace(/--.*$/gm, ' ');
  const statements = [];
  let current = '';
  let inDollar = false;
  for (let i = 0; i < text.length; i += 1) {
    if (text.startsWith('$$', i)) {
      inDollar = !inDollar;
      current += '$$';
      i += 1;
      continue;
    }
    if (text[i] === ';' && !inDollar) {
      if (current.trim() !== '') statements.push(normalizeSql(current));
      current = '';
      continue;
    }
    current += text[i];
  }
  if (current.trim() !== '') statements.push(normalizeSql(current));
  return statements;
}

const SITE = 1000000001;
const OTHER_SITE = 1000000002;
const manager = { id: 20001, user_code: 20001, userCode: 20001, role: 'site_manager', full_name: 'Yönetici', email: 'u20001@example.com' };

async function rejectsWith(promise, statusCode, code) {
  await assert.rejects(promise, (error) => {
    assert.equal(error.statusCode, statusCode, `${error.code}: ${error.message}`);
    assert.equal(error.code, code);
    return true;
  });
}

// --- Anahtar ve ad kuralları ------------------------------------------------------------------------------------------

describe('kategori anahtarı ve adı', () => {
  it('dört varsayılan anahtar eski kısıttaki beyaz listeyle AYNI; CATEGORIES onlardır', () => {
    assert.deepEqual([...DEFAULT_CATEGORY_KEYS], ['ariza', 'bakim', 'sikayet_oneri', 'diger']);
    assert.deepEqual([...CATEGORIES], [...DEFAULT_CATEGORY_KEYS]);
    assert.deepEqual(DEFAULT_WORK_CATEGORIES.map((c) => c.label), ['Arıza', 'Bakım', 'Şikayet / Öneri', 'Diğer']);
  });

  it('isCategoryKey: varsayılan anahtarlar ve k_<ad> geçerli; tek harf, büyük harf, boşluk, uzun, k_ tek başına geçersiz', () => {
    for (const ok of ['ariza', 'bakim', 'sikayet_oneri', 'diger', 'k_su_kacagi', 'k_a', `k_${'a'.repeat(38)}`, 'k_2_x']) assert.equal(isCategoryKey(ok), true, ok);
    for (const bad of ['x', 'K_su', 'k_', 'k_Su', 'k_su kacagi', `k_${'a'.repeat(39)}`, 'su_kacagi', '', null, undefined, 5, ['ariza'], 'ariza ', ' ariza']) assert.equal(isCategoryKey(bad), false, String(bad));
    assert.equal(CUSTOM_KEY_PATTERN.test('k_su'), true);
  });

  it('normalizeCategoryLabel: boşluklar sadeleşir, satır sonu / görünmez karakter atılır, 1..60 karakter, metin zorunlu', () => {
    assert.equal(normalizeCategoryLabel('  Su   kaçağı \n'), 'Su kaçağı');
    assert.equal(normalizeCategoryLabel('Çatı\tonarım'), 'Çatı onarım');
    assert.equal(normalizeCategoryLabel(`A${String.fromCodePoint(0x200b)}B`), 'AB');
    assert.equal(Array.from(normalizeCategoryLabel('ş'.repeat(CATEGORY_LABEL_MAX))).length, CATEGORY_LABEL_MAX);
    for (const bad of ['', '   ', 'a'.repeat(CATEGORY_LABEL_MAX + 1), null, undefined, 5, {}]) {
      assert.throws(() => normalizeCategoryLabel(bad), (error) => error.statusCode === 400 && error.code === 'INVALID_BODY', String(bad));
    }
  });

  it('foldLabel / slugOfLabel: Türkçe karakter ve büyük/küçük harf duyarsız; anahtar gövdesi ASCII, en çok 30 karakter, boş kalırsa "kategori"', () => {
    assert.equal(foldLabel('ARIZA'), foldLabel('Arıza'));
    assert.equal(foldLabel('Arıza'), foldLabel('ariza'));
    assert.equal(foldLabel('  Çatı   İşleri '), 'cati isleri');
    assert.equal(slugOfLabel('Su Kaçağı'), 'su_kacagi');
    assert.equal(slugOfLabel('Çatı / Teras (acil)!'), 'cati_teras_acil');
    assert.equal(slugOfLabel('!!!'), 'kategori');
    assert.equal(slugOfLabel('é'), 'kategori');
    assert.ok(slugOfLabel('a'.repeat(80)).length <= 30);
    assert.ok(!slugOfLabel('abc'.repeat(20)).endsWith('_'));
  });

  it('pickCategoryKey: k_<ad>; çakışırsa _2, _3 ...; üretilen anahtar HER ZAMAN geçerli biçimde (CHECK ile aynı)', () => {
    assert.equal(pickCategoryKey('Su kaçağı', new Set()), 'k_su_kacagi');
    assert.equal(pickCategoryKey('Su kaçağı', new Set(['k_su_kacagi'])), 'k_su_kacagi_2');
    assert.equal(pickCategoryKey('Su kaçağı', new Set(['k_su_kacagi', 'k_su_kacagi_2'])), 'k_su_kacagi_3');
    for (const label of ['Su kaçağı', 'a'.repeat(60), '!!!', 'İşler 2. kat', 'ÇĞİÖŞÜ']) {
      assert.equal(CUSTOM_KEY_PATTERN.test(pickCategoryKey(label, new Set())), true, label);
      assert.equal(CUSTOM_KEY_PATTERN.test(pickCategoryKey(label, new Set([pickCategoryKey(label, new Set())]))), true, label);
    }
    const taken = new Set(['k_x', ...Array.from({ length: 98 }, (_, n) => `k_x_${n + 2}`)]);
    assert.throws(() => pickCategoryKey('x', taken), (error) => error.statusCode === 409 && error.code === 'LIMIT_REACHED');
  });

  it('girdi ayrıştırıcıları: oluşturma yalnız { label }; güncelleme en az bir alan, anahtar DEĞİŞTİRİLEMEZ (gönderilse bile yok sayılır), sıra 0..100000 tam sayı', () => {
    assert.deepEqual(parseCategoryCreateBody({ label: ' Asansör ' }), { label: 'Asansör' });
    for (const bad of [null, [], 'x', {}, { label: '' }, { label: 5 }]) assert.throws(() => parseCategoryCreateBody(bad), (e) => e.code === 'INVALID_BODY', JSON.stringify(bad));
    assert.deepEqual(parseCategoryPatchBody({ label: 'Yeni ad', is_active: false, sort_order: 7 }), { label: 'Yeni ad', isActive: false, sortOrder: 7 });
    assert.deepEqual(parseCategoryPatchBody({ key: 'k_hack', is_active: true }), { isActive: true });
    for (const bad of [{}, { key: 'k_x' }, { is_active: 'evet' }, { is_active: 1 }, { sort_order: -1 }, { sort_order: 1.5 }, { sort_order: 100001 }, { sort_order: '5' }, { label: '' }, null]) {
      assert.throws(() => parseCategoryPatchBody(bad), (e) => e.statusCode === 400 && e.code === 'INVALID_BODY', JSON.stringify(bad));
    }
  });

  it('?active= süzgeci: yok / boş -> null (hepsi); true|1 / false|0; geçersiz -> undefined', () => {
    assert.deepEqual([undefined, '', '  ', null].map(parseActiveFilter), [null, null, null, null]);
    assert.deepEqual(['true', '1', 'TRUE'].map(parseActiveFilter), [true, true, true]);
    assert.deepEqual(['false', '0'].map(parseActiveFilter), [false, false]);
    assert.equal(parseActiveFilter('belki'), undefined);
  });

  it('nextSortOrder, mapWorkCategory ve categoryLabelOf', () => {
    assert.equal(nextSortOrder([]), 10);
    assert.equal(nextSortOrder([10, 20, '40']), 50);
    assert.equal(nextSortOrder([100000]), 100000);
    const row = { id: '3', key: 'k_x', label: 'X', is_system: false, is_active: true, sort_order: '50', item_count: '4' };
    assert.deepEqual(mapWorkCategory(row), { id: 3, key: 'k_x', label: 'X', is_system: false, is_active: true, sort_order: 50 });
    assert.deepEqual(mapWorkCategory(row, { withCount: true }), { id: 3, key: 'k_x', label: 'X', is_system: false, is_active: true, sort_order: 50, item_count: 4 });
    assert.equal(categoryLabelOf('ariza', 'Teknik arıza'), 'Teknik arıza');
    assert.equal(categoryLabelOf('ariza', null), 'Arıza');
    assert.equal(categoryLabelOf('k_x', undefined), 'k_x');
    assert.equal(categoryLabelOf('k_x', ''), 'k_x');
  });
});

describe('talep girdisi ve eşleyiciler (kategori)', () => {
  const base = { site_code: SITE, category: 'ariza', location_type: 'ortak_alan', title: 'Başlık', description: 'Açıklama', idempotency_key: 'abc-12345-xyz' };

  it('parseCreateInput: varsayılan anahtarlar ve k_<ad> biçimi geçer; tek harf / büyük harf / bilinmeyen kalıp 400 INVALID_BODY (sitede varlık serviste denetlenir)', () => {
    for (const category of [...CATEGORIES, 'k_su_kacagi']) assert.equal(parseCreateInput({ ...base, category }).category, category);
    for (const category of ['x', 'K_su', 'su_kacagi', 'k_', '', null, 5, undefined]) {
      assert.throws(() => parseCreateInput({ ...base, category }), (error) => error.statusCode === 400 && error.code === 'INVALID_BODY', String(category));
    }
  });

  it('parseListQuery: ?category= varsayılan ya da k_<ad>; geçersiz biçim 400 INVALID_QUERY; boş yok sayılır', () => {
    assert.equal(parseListQuery({ category: 'k_su_kacagi' }).category, 'k_su_kacagi');
    assert.equal(parseListQuery({ category: 'bakim' }).category, 'bakim');
    assert.equal(parseListQuery({ category: '' }).category, null);
    assert.equal(parseListQuery({}).category, null);
    for (const category of ['x', 'K_su', 'k_']) assert.throws(() => parseListQuery({ category }), (error) => error.code === 'INVALID_QUERY', category);
  });

  const row = {
    id: '5', site_code: String(SITE), category: 'k_su_kacagi', location_type: 'ortak_alan', title: 'T', description: 'D', status: 'yeni', priority: 'normal', resident_urgent: false,
    due_date: null, created_at: new Date('2026-01-01T00:00:00Z'), updated_at: new Date('2026-01-02T00:00:00Z'), closed_at: null, created_by: 12, assigned_to: null,
    apartment_id: null, block_id: null, requester_name: 'Ada', requester_phone: null, site_name: 'Gül', unread: false,
  };

  it('yönetim ve sakin görünümü: category anahtarı DEĞİŞMEZ, category_label sitedeki ad -> varsayılan ad -> anahtar', () => {
    assert.deepEqual([mapManagerItem({ ...row, category_label: 'Su kaçağı' }, { kind: 'manager' }).category, mapManagerItem({ ...row, category_label: 'Su kaçağı' }, { kind: 'manager' }).category_label], ['k_su_kacagi', 'Su kaçağı']);
    assert.equal(mapManagerItem({ ...row, category: 'ariza' }, { kind: 'staff' }).category_label, 'Arıza');
    assert.equal(mapManagerItem({ ...row, category: 'ariza', category_label: 'Teknik arıza' }, { kind: 'board' }).category_label, 'Teknik arıza');
    assert.equal(mapManagerItem(row, { kind: 'manager' }).category_label, 'k_su_kacagi');
    assert.equal(mapResidentItem({ ...row, category_label: 'Su kaçağı' }).category_label, 'Su kaçağı');
    assert.equal(mapResidentItem({ ...row, category: 'diger' }).category_label, 'Diğer');
  });
});

// --- Migration 100 ve şema ------------------------------------------------------------------------------------------------

describe('migration 100: iş takibi kategorileri', () => {
  it('100 var, çalıştırıcı için güvenli (üst düzey BEGIN/COMMIT yok), numara yinelenmez', () => {
    const list = listMigrations(DEFAULT_MIGRATIONS_DIR);
    const entry = list.find((m) => m.number === 100);
    assert.ok(entry, '100 numaralı migration yok');
    assert.equal(entry.file, '100_work_categories.sql');
    assert.equal(list.filter((m) => m.number === 100).length, 1);
    assert.deepEqual(findUnsafeStatements(MIGRATION), []);
  });

  it('WORK_CATEGORIES_DDL migration 100 ile AYNI ifadeleri taşır (yorumlar ve boşluklar dışında birebir, AYNI sırayla)', () => {
    const fromMigration = splitStatements(MIGRATION);
    assert.equal(fromMigration.length, 8);
    assert.deepEqual(fromMigration, WORK_CATEGORIES_DDL_ORDER.map((name) => normalizeSql(WORK_CATEGORIES_DDL[name])));
    assert.deepEqual(Object.keys(WORK_CATEGORIES_DDL), [...WORK_CATEGORIES_DDL_ORDER]);
  });

  it('EKLEMELİ ve idempotent: yeni tablo + IF NOT EXISTS dizinler + katalog korumalı FK + TEK kısıt değişimi (yalnız chk_work_items_category); veri YAZMAZ / SİLMEZ', () => {
    const allowed = [
      /^CREATE TABLE IF NOT EXISTS work_categories \(/,
      /^CREATE (UNIQUE )?INDEX IF NOT EXISTS (uq_work_categories_site_key|uq_work_categories_site_label|idx_work_items_site_category|idx_work_item_attachments_site_sha256) ON /,
      /^DO \$\$ BEGIN IF NOT EXISTS \( SELECT 1 FROM pg_constraint WHERE conname = 'work_categories_(site_code|created_by)_fkey' AND conrelid = 'work_categories'::regclass \) THEN ALTER TABLE work_categories ADD CONSTRAINT work_categories_(site_code|created_by)_fkey FOREIGN KEY /,
      /^DO \$\$ BEGIN IF EXISTS \( SELECT 1 FROM pg_constraint WHERE conname = 'chk_work_items_category' AND conrelid = 'work_items'::regclass \) THEN ALTER TABLE work_items DROP CONSTRAINT chk_work_items_category; END IF; IF NOT EXISTS \( SELECT 1 FROM pg_constraint WHERE conname = 'chk_work_items_category_key' AND conrelid = 'work_items'::regclass \) THEN ALTER TABLE work_items ADD CONSTRAINT chk_work_items_category_key CHECK/,
    ];
    for (const statement of splitStatements(MIGRATION)) {
      assert.ok(allowed.some((pattern) => pattern.test(statement)), statement.slice(0, 120));
    }
    const all = normalizeSql(MIGRATION);
    assert.ok(!/\b(TRUNCATE|UPDATE|DELETE FROM|INSERT INTO|DROP TABLE|DROP INDEX)\b/i.test(all));
    assert.equal((all.match(/DROP CONSTRAINT/g) ?? []).length, 1);
    assert.ok(!/CONCURRENTLY/i.test(all));
  });

  it('yeni kısıt: dört varsayılan anahtar YA DA k_<ad> (eski kodun yazdığı tüm değerler geçer); tablo kısıtları ve sistem anahtarı tutarlılığı', () => {
    const check = normalizeSql(WORK_CATEGORIES_DDL.itemsCategoryCheck);
    assert.ok(check.includes("CHECK (category IN ('ariza', 'bakim', 'sikayet_oneri', 'diger') OR category ~ '^k_[a-z0-9_]{1,38}$')"));
    const table = normalizeSql(WORK_CATEGORIES_DDL.categoriesTable);
    for (const fragment of [
      'id BIGSERIAL PRIMARY KEY',
      'is_system BOOLEAN NOT NULL DEFAULT FALSE',
      'is_active BOOLEAN NOT NULL DEFAULT TRUE',
      "key IN ('ariza', 'bakim', 'sikayet_oneri', 'diger') OR key ~ '^k_[a-z0-9_]{1,38}$'",
      'char_length(label) BETWEEN 1 AND 60',
      'sort_order BETWEEN 0 AND 100000',
      "is_system = (key IN ('ariza', 'bakim', 'sikayet_oneri', 'diger'))",
    ]) {
      assert.ok(table.includes(fragment), fragment);
    }
    // JS kalıbı DB kalıbıyla aynı
    assert.equal(CUSTOM_KEY_PATTERN.source, '^k_[a-z0-9_]{1,38}$');
    assert.equal(normalizeSql(WORK_CATEGORIES_DDL.categoriesSiteLabelIndex), 'CREATE UNIQUE INDEX IF NOT EXISTS uq_work_categories_site_label ON work_categories (site_code, lower(label))');
    assert.ok(normalizeSql(WORK_CATEGORIES_DDL.attachmentsSha256Index).endsWith('(site_code, sha256) WHERE sha256 IS NOT NULL'));
  });

  it('AÇILIŞ 40P01 dersi: DDL dev blokta DEĞİL; db.js yalnız ensureWorkCategoriesSchema(client) çağırır, 042 ve 047 şemalarından SONRA, people_v1\'den ÖNCE', () => {
    const normalizedDb = normalizeSql(DB_SOURCE);
    for (const name of WORK_CATEGORIES_DDL_ORDER) {
      assert.equal(normalizedDb.includes(normalizeSql(WORK_CATEGORIES_DDL[name])), false, `${name} db.js içinde olmamalı`);
    }
    assert.equal(/CREATE TABLE IF NOT EXISTS work_categories\b/.test(DB_SOURCE), false);
    assert.match(DB_SOURCE, /import \{ ensureWorkCategoriesSchema \} from '\.\/modules\/work_categories_schema\.js';/);
    const calls = [...DB_SOURCE.matchAll(/await ensureWorkCategoriesSchema\(client\);/g)];
    assert.equal(calls.length, 1);
    assert.ok(calls[0].index > DB_SOURCE.indexOf('await ensureWorkTrackingSchema(client);'));
    assert.ok(calls[0].index > DB_SOURCE.indexOf('await ensureWorkAttachmentsSchema(client);'));
    assert.ok(calls[0].index < DB_SOURCE.indexOf('await runPeopleBackfill(client);'));
  });
});

describe('ensureWorkCategoriesSchema (katalog kontrollü, sahte istemci)', () => {
  const ALL_PRESENT = {
    tables: ['work_categories', 'work_items', 'work_item_attachments'],
    indexes: ['uq_work_categories_site_key', 'uq_work_categories_site_label', 'idx_work_items_site_category', 'idx_work_item_attachments_site_sha256'],
    fks: ['work_categories.work_categories_site_code_fkey', 'work_categories.work_categories_created_by_fkey'],
    old_check_present: false,
    new_check_present: true,
  };

  function fakeClient(found, { failures = [] } = {}) {
    const sent = [];
    const queue = [...failures];
    return {
      sent,
      async query(text) {
        const sql = norm(text);
        if (/^SELECT\s+ARRAY\(/.test(sql)) return { rows: [found] };
        sent.push(sql);
        if (queue.length > 0 && !/^(SET|RESET) lock_timeout/.test(sql)) {
          const code = queue.shift();
          if (code) throw Object.assign(new Error('kilit'), { code });
        }
        return { rows: [] };
      },
    };
  }

  it('her şey varsa HİÇBİR ifade gönderilmez (kilit yok): normal açılış tek katalog sorgusudur', async () => {
    const client = fakeClient(ALL_PRESENT);
    await ensureWorkCategoriesSchema(client);
    assert.deepEqual(client.sent, []);
  });

  it('üretim benzeri durum (eski kısıt var, yeni nesneler yok): 8 ifade AYNI sırayla, lock_timeout içinde; kısıt değişimi EN SON', async () => {
    const client = fakeClient({ tables: ['work_items', 'work_item_attachments'], indexes: [], fks: [], old_check_present: true, new_check_present: false });
    await ensureWorkCategoriesSchema(client);
    assert.equal(client.sent[0], "SET lock_timeout = '2s'");
    assert.equal(client.sent.at(-1), 'RESET lock_timeout');
    assert.deepEqual(client.sent.slice(1, -1), WORK_CATEGORIES_DDL_ORDER.map((name) => norm(WORK_CATEGORIES_DDL[name])));
    assert.equal(WORK_CATEGORIES_DDL_ORDER.at(-1), 'itemsCategoryCheck');
  });

  it('yalnız eski kısıt varsa (yeni nesneler hazır) yalnız kısıt değişimi gider', async () => {
    const client = fakeClient({ ...ALL_PRESENT, old_check_present: true, new_check_present: false });
    await ensureWorkCategoriesSchema(client);
    assert.deepEqual(client.sent.slice(1, -1), [norm(WORK_CATEGORIES_DDL.itemsCategoryCheck)]);
  });

  it('work_items / work_item_attachments yoksa (042 / 047 kurulmamış) yalnız work_categories tablosu + kendi FK / dizinleri; diğer tablolara dokunan adım atlanır', async () => {
    const client = fakeClient({ tables: [], indexes: [], fks: [], old_check_present: false, new_check_present: false });
    await ensureWorkCategoriesSchema(client);
    const statements = client.sent.slice(1, -1);
    assert.deepEqual(statements, ['categoriesTable', 'categoriesSiteFk', 'categoriesCreatedByFk', 'categoriesSiteKeyIndex', 'categoriesSiteLabelIndex'].map((name) => norm(WORK_CATEGORIES_DDL[name])));
    assert.ok(!statements.some((statement) => /idx_work_items_site_category|idx_work_item_attachments_site_sha256|chk_work_items_category/.test(statement)));
  });

  it('kilit zaman aşımı (55P03) / deadlock (40P01) yeniden denenir; başka hata fırlatılır', async () => {
    const found = { ...ALL_PRESENT, indexes: ALL_PRESENT.indexes.filter((name) => name !== 'idx_work_items_site_category') };
    const retried = fakeClient(found, { failures: ['55P03', '40P01'] });
    await ensureWorkCategoriesSchema(retried);
    assert.equal(retried.sent.filter((sql) => /idx_work_items_site_category/.test(sql)).length, 3);
    const broken = fakeClient(found, { failures: ['23505'] });
    await assert.rejects(ensureWorkCategoriesSchema(broken), { code: '23505' });
    assert.equal(broken.sent.at(-1), 'RESET lock_timeout');
  });
});

// --- Hizmet (bellek içi sahte veritabanı) -------------------------------------------------------------------------------------

/**
 * work_categories + work_items için bellek içi sahte veritabanı. Hizmetin gönderdiği ifadelerin HEPSİNİ tanır (aksi hata fırlatır = katı).
 * `state.sql` gönderilen normalize ifadeleri taşır.
 */
function createFake() {
  const state = { categories: [], items: [], audit: [], sql: [], nextId: 1, sites: new Set([SITE, OTHER_SITE]), users: new Set([20001]), moduleEnabled: true, resident: true, approved: true, failNext: null };
  const pick = (row) => ({ id: row.id, key: row.key, label: row.label, is_system: row.is_system, is_active: row.is_active, sort_order: row.sort_order });
  const find = (id, site) => state.categories.find((c) => c.id === Number(id) && c.site_code === Number(site));
  const ok = (rows = [], rowCount = rows.length) => ({ rows, rowCount });

  async function query(text, params = []) {
    const sql = norm(text);
    state.sql.push(sql);
    if (state.failNext && state.failNext.test(sql)) {
      const error = Object.assign(new Error('enjekte'), { code: '23505' });
      state.failNext = null;
      throw error;
    }
    if (/^(BEGIN|COMMIT|ROLLBACK)$/.test(sql)) return ok();
    if (/^SAVEPOINT|^RELEASE SAVEPOINT|^ROLLBACK TO SAVEPOINT/.test(sql)) return ok();
    if (sql === 'SELECT site_code FROM sites WHERE site_code = $1 FOR KEY SHARE') return ok(state.sites.has(Number(params[0])) ? [{ site_code: params[0] }] : []);
    if (sql === 'SELECT user_code FROM users WHERE user_code = $1 AND deleted_at IS NULL FOR KEY SHARE') return ok(state.users.has(Number(params[0])) ? [{ user_code: params[0] }] : []);
    if (sql === 'SELECT pg_advisory_xact_lock(hashtext($1))') return ok([{}]);
    if (sql === 'SELECT COUNT(*)::INTEGER AS n FROM work_categories WHERE site_code = $1 AND is_system = TRUE') {
      return ok([{ n: state.categories.filter((c) => c.site_code === Number(params[0]) && c.is_system).length }]);
    }
    if (/^INSERT INTO work_categories \(site_code, key, label, is_system, sort_order\) SELECT \$1, t\.key, t\.label, TRUE, \(t\.ord \* 10\)::INTEGER FROM unnest\(\$2::TEXT\[\], \$3::TEXT\[\]\) WITH ORDINALITY AS t\(key, label, ord\) ORDER BY t\.ord ON CONFLICT DO NOTHING$/.test(sql)) {
      const [site, keys, labels] = params;
      keys.forEach((key, index) => {
        if (state.categories.some((c) => c.site_code === site && (c.key === key || c.label.toLowerCase() === labels[index].toLowerCase()))) return;
        state.categories.push({ id: state.nextId++, site_code: site, key, label: labels[index], is_system: true, is_active: true, sort_order: (index + 1) * 10, created_by: null });
      });
      return ok();
    }
    if (sql === 'SELECT key, label, sort_order FROM work_categories WHERE site_code = $1') return ok(state.categories.filter((c) => c.site_code === Number(params[0])).map((c) => ({ key: c.key, label: c.label, sort_order: c.sort_order })));
    if (sql === 'SELECT id, label FROM work_categories WHERE site_code = $1') return ok(state.categories.filter((c) => c.site_code === Number(params[0])).map((c) => ({ id: c.id, label: c.label })));
    if (/^INSERT INTO work_categories \(site_code, key, label, is_system, sort_order, created_by\) VALUES \(\$1, \$2, \$3, FALSE, \$4, \$5\) RETURNING id, key, label, is_system, is_active, sort_order$/.test(sql)) {
      const [site, key, label, sortOrder, createdBy] = params;
      if (state.categories.some((c) => c.site_code === site && (c.key === key || c.label.toLowerCase() === label.toLowerCase()))) throw Object.assign(new Error('tekil'), { code: '23505' });
      const row = { id: state.nextId++, site_code: site, key, label, is_system: false, is_active: true, sort_order: sortOrder, created_by: createdBy };
      state.categories.push(row);
      return ok([pick(row)]);
    }
    if (sql === 'SELECT id, key, label, is_system, is_active, sort_order FROM work_categories WHERE id = $1 AND site_code = $2 FOR UPDATE') {
      const row = find(params[0], params[1]);
      return ok(row ? [pick(row)] : []);
    }
    if (sql === 'SELECT COUNT(*)::INTEGER AS n FROM work_items WHERE site_code = $1 AND category = $2') {
      return ok([{ n: state.items.filter((i) => i.site_code === Number(params[0]) && i.category === params[1]).length }]);
    }
    if (sql === 'SELECT 1 FROM work_categories WHERE site_code = $1 AND is_active = TRUE AND id <> $2 LIMIT 1') {
      return ok(state.categories.filter((c) => c.site_code === Number(params[0]) && c.is_active && c.id !== Number(params[1])).slice(0, 1).map(() => ({ x: 1 })));
    }
    if (/^UPDATE work_categories SET label = \$3, is_active = \$4, sort_order = \$5, updated_at = NOW\(\) WHERE id = \$1 AND site_code = \$2 RETURNING /.test(sql)) {
      const row = find(params[0], params[1]);
      Object.assign(row, { label: params[2], is_active: params[3], sort_order: params[4] });
      return ok([pick(row)]);
    }
    if (/^UPDATE work_categories SET is_active = FALSE, updated_at = NOW\(\) WHERE id = \$1 AND site_code = \$2 RETURNING /.test(sql)) {
      const row = find(params[0], params[1]);
      row.is_active = false;
      return ok([pick(row)]);
    }
    if (sql === 'DELETE FROM work_categories WHERE id = $1 AND site_code = $2') {
      const index = state.categories.findIndex((c) => c.id === Number(params[0]) && c.site_code === Number(params[1]));
      if (index >= 0) state.categories.splice(index, 1);
      return ok([], index >= 0 ? 1 : 0);
    }
    if (/^INSERT INTO audit_log \(/.test(sql)) {
      state.audit.push({ action: params[3], site_code: params[4], target_type: params[5], target_id: params[6], details: JSON.parse(params[7]) });
      return ok();
    }
    if (sql === 'SELECT is_active FROM work_categories WHERE site_code = $1 AND key = $2 FOR SHARE') {
      const row = state.categories.find((c) => c.site_code === Number(params[0]) && c.key === params[1]);
      return ok(row ? [{ is_active: row.is_active }] : []);
    }
    if (/^SELECT c\.id, c\.key, c\.label, c\.is_system, c\.is_active, c\.sort_order(, \(SELECT COUNT\(\*\)::INTEGER FROM work_items w WHERE w\.site_code = c\.site_code AND w\.category = c\.key\) AS item_count)? FROM work_categories c WHERE c\.site_code = \$1 AND \(\$2::BOOLEAN IS NULL OR c\.is_active = \$2\) ORDER BY c\.sort_order, c\.id$/.test(sql)) {
      const withCount = /AS item_count/.test(sql);
      const rows = state.categories
        .filter((c) => c.site_code === Number(params[0]) && (params[1] === null || c.is_active === params[1]))
        .sort((a, b) => a.sort_order - b.sort_order || a.id - b.id)
        .map((c) => (withCount ? { ...pick(c), item_count: state.items.filter((i) => i.site_code === c.site_code && i.category === c.key).length } : pick(c)));
      return ok(rows);
    }
    if (sql === "SELECT 1 FROM sites WHERE site_code = $1 AND approval_status = 'approved'") return ok(state.sites.has(Number(params[0])) && state.approved ? [{ x: 1 }] : []);
    if (sql === 'SELECT enabled FROM site_modules WHERE site_code = $1 AND module_code = $2 LIMIT 1') return ok(params[1] === 'work_tracking' ? [{ enabled: state.moduleEnabled }] : []);
    if (/^WITH my_apts AS MATERIALIZED \(.*\) SELECT 1 FROM my_apts WHERE site_code = \$2 LIMIT 1$/.test(sql)) return ok(state.resident ? [{ x: 1 }] : []);
    throw new Error(`BEKLENMEYEN SQL (sahte DB katı): ${sql.slice(0, 220)}`);
  }

  return { state, query };
}

let fake;
before(() => {
  pool.connect = async () => ({ query: (...args) => fake.query(...args), release() {} });
  pool.query = (...args) => fake.query(...args);
});
after(() => {
  delete pool.connect;
  delete pool.query;
});
beforeEach(() => {
  fake = createFake();
});

describe('varsayılan kategoriler (tohum)', () => {
  it('ilk kullanımda dört varsayılan kategori eklenir (sistem, etkin, 10/20/30/40); ikinci çağrı YAZMAZ; eksik biri yeniden tamamlanır', async () => {
    await ensureDefaultWorkCategories(pool, SITE);
    assert.deepEqual(fake.state.categories.map((c) => [c.key, c.label, c.is_system, c.is_active, c.sort_order]), [
      ['ariza', 'Arıza', true, true, 10],
      ['bakim', 'Bakım', true, true, 20],
      ['sikayet_oneri', 'Şikayet / Öneri', true, true, 30],
      ['diger', 'Diğer', true, true, 40],
    ]);
    const writes = () => fake.state.sql.filter((sql) => /^INSERT INTO work_categories/.test(sql)).length;
    assert.equal(writes(), 1);
    await ensureDefaultWorkCategories(pool, SITE);
    assert.equal(writes(), 1);
    fake.state.categories.splice(fake.state.categories.findIndex((c) => c.key === 'bakim'), 1);
    await ensureDefaultWorkCategories(pool, SITE);
    assert.equal(fake.state.categories.length, 4);
    assert.equal(writes(), 2);
  });

  it('yeniden adlandırılmış / pasife alınmış varsayılan kategori yeniden eklenmez ve adı ezilmez; başka sitenin kategorilerine dokunulmaz', async () => {
    await ensureDefaultWorkCategories(pool, SITE);
    Object.assign(fake.state.categories.find((c) => c.key === 'ariza'), { label: 'Teknik arıza', is_active: false });
    await ensureDefaultWorkCategories(pool, SITE);
    await ensureDefaultWorkCategories(pool, OTHER_SITE);
    const ariza = fake.state.categories.filter((c) => c.key === 'ariza');
    assert.deepEqual(ariza.map((c) => [c.site_code, c.label, c.is_active]), [[SITE, 'Teknik arıza', false], [OTHER_SITE, 'Arıza', true]]);
  });
});

describe('kategori listesi', () => {
  it('yönetim listesi: sıralı, kullanım sayısıyla; ?active=true yalnız etkinler; geçersiz ?active= 400 INVALID_QUERY', async () => {
    fake.state.items.push({ site_code: SITE, category: 'ariza' }, { site_code: SITE, category: 'ariza' }, { site_code: SITE, category: 'bakim' }, { site_code: OTHER_SITE, category: 'ariza' });
    await createWorkCategory({ siteCode: SITE, actor: manager, body: { label: 'Asansör' } });
    const all = await listWorkCategories(SITE, {}, { withCount: true });
    assert.deepEqual(all.items.map((c) => [c.key, c.item_count]), [['ariza', 2], ['bakim', 1], ['sikayet_oneri', 0], ['diger', 0], ['k_asansor', 0]]);
    fake.state.categories.find((c) => c.key === 'bakim').is_active = false;
    assert.deepEqual((await listWorkCategories(SITE, { active: 'true' }, { withCount: false })).items.map((c) => c.key), ['ariza', 'sikayet_oneri', 'diger', 'k_asansor']);
    assert.deepEqual((await listWorkCategories(SITE, { active: 'false' })).items.map((c) => c.key), ['bakim']);
    assert.equal('item_count' in (await listWorkCategories(SITE, {}, { withCount: false })).items[0], false);
    await assert.rejects(listWorkCategories(SITE, { active: 'belki' }), { statusCode: 400, code: 'INVALID_QUERY' });
  });
});

describe('kategori ekleme', () => {
  it('varsayılanlar tohumlanır, k_<ad> anahtarı üretilir, sıra sona eklenir, audit YALNIZ anahtar taşır (ad yazılmaz)', async () => {
    const { category } = await createWorkCategory({ siteCode: SITE, actor: manager, body: { label: '  Su   kaçağı ' } });
    assert.deepEqual(category, { id: 5, key: 'k_su_kacagi', label: 'Su kaçağı', is_system: false, is_active: true, sort_order: 50, item_count: 0 });
    assert.equal(fake.state.categories.length, 5);
    assert.equal(fake.state.categories.find((c) => c.key === 'k_su_kacagi').created_by, 20001);
    assert.deepEqual(fake.state.audit.map((a) => [a.action, a.site_code, a.target_type, a.target_id, a.details]), [['work_category.created', SITE, 'work_category', '5', { key: 'k_su_kacagi' }]]);
    assert.ok(!JSON.stringify(fake.state.audit).includes('Su kaçağı'));
  });

  it('aynı ad (büyük/küçük harf + Türkçe karakter duyarsız, varsayılanlar dahil) 409 WORK_CATEGORY_NAME_TAKEN; başka sitede aynı ad serbest', async () => {
    await createWorkCategory({ siteCode: SITE, actor: manager, body: { label: 'Asansör' } });
    for (const label of ['asansör', 'ASANSÖR', 'Asansor', 'ARIZA', 'arıza', 'Ariza', 'şikayet / öneri', 'DİĞER']) {
      await rejectsWith(createWorkCategory({ siteCode: SITE, actor: manager, body: { label } }), 409, 'WORK_CATEGORY_NAME_TAKEN');
    }
    const other = await createWorkCategory({ siteCode: OTHER_SITE, actor: manager, body: { label: 'Asansör' } });
    assert.equal(other.category.key, 'k_asansor');
  });

  it('farklı adların slug çakışması anahtarı sayıyla ayırır (k_a_b, k_a_b_2); anahtar HER ZAMAN k_ ile başlar', async () => {
    const first = await createWorkCategory({ siteCode: SITE, actor: manager, body: { label: 'A b' } });
    const second = await createWorkCategory({ siteCode: SITE, actor: manager, body: { label: 'A-b' } });
    assert.deepEqual([first.category.key, second.category.key], ['k_a_b', 'k_a_b_2']);
  });

  it('site başına en çok 40 kategori (varsayılanlar ve pasifler dahil): 409 LIMIT_REACHED { category_limit }', async () => {
    for (let n = 1; n <= WORK_CATEGORY_LIMIT - DEFAULT_WORK_CATEGORIES.length; n += 1) {
      await createWorkCategory({ siteCode: SITE, actor: manager, body: { label: `Kategori ${n}` } });
    }
    assert.equal(fake.state.categories.length, WORK_CATEGORY_LIMIT);
    await assert.rejects(createWorkCategory({ siteCode: SITE, actor: manager, body: { label: 'Fazla' } }), (error) => {
      assert.deepEqual([error.statusCode, error.code, error.extra.category_limit], [409, 'LIMIT_REACHED', WORK_CATEGORY_LIMIT]);
      return true;
    });
  });

  it('doğrulama hataları işlem açmadan 400; silinmiş / olmayan site ve hesap hataları iş mantığından önce döner; DB tekil ihlali (23505) 409 WORK_CATEGORY_NAME_TAKEN\'e çevrilir', async () => {
    for (const body of [null, {}, { label: '' }, { label: 'x'.repeat(61) }, []]) {
      await rejectsWith(createWorkCategory({ siteCode: SITE, actor: manager, body }), 400, 'INVALID_BODY');
    }
    assert.equal(fake.state.sql.length, 0);
    await rejectsWith(createWorkCategory({ siteCode: 1999999999, actor: manager, body: { label: 'Yeni' } }), 404, 'SITE_NOT_FOUND');
    fake.state.users.clear();
    await rejectsWith(createWorkCategory({ siteCode: SITE, actor: manager, body: { label: 'Yeni' } }), 401, 'ACCOUNT_DELETED');
    fake.state.users.add(20001);
    fake.state.failNext = /^INSERT INTO work_categories \(site_code, key, label, is_system, sort_order, created_by\)/;
    await rejectsWith(createWorkCategory({ siteCode: SITE, actor: manager, body: { label: 'Yeni' } }), 409, 'WORK_CATEGORY_NAME_TAKEN');
  });

  it('kilit sırası: site FOR KEY SHARE -> kullanıcı FOR KEY SHARE -> work_categories_site advisory -> satır sorguları', async () => {
    await createWorkCategory({ siteCode: SITE, actor: manager, body: { label: 'Asansör' } });
    const order = fake.state.sql.map((sql) => (sql.includes('FROM sites') ? 'site' : sql.includes('FROM users') ? 'user' : sql.includes('advisory') ? 'advisory' : sql.includes('work_categories') ? 'kategori' : 'diger'));
    assert.deepEqual(order.slice(0, 4), ['diger', 'site', 'user', 'advisory']);
    assert.ok(order.indexOf('kategori') > order.indexOf('advisory'));
  });
});

describe('kategori güncelleme (yeniden adlandır / pasife al / sırala)', () => {
  async function seeded() {
    const { category } = await createWorkCategory({ siteCode: SITE, actor: manager, body: { label: 'Asansör' } });
    return category;
  }
  const update = (id, body, site = SITE) => updateWorkCategory({ siteCode: site, rawId: String(id), actor: manager, body });

  it('yeniden adlandırma: ANAHTAR DEĞİŞMEZ; yalnız ad değişir; kullanım sayısı yanıtta; audit alan adlarını taşır (adı değil)', async () => {
    const created = await seeded();
    fake.state.items.push({ site_code: SITE, category: 'k_asansor' });
    const { category } = await update(created.id, { label: 'Asansör bakımı' });
    assert.deepEqual(category, { id: created.id, key: 'k_asansor', label: 'Asansör bakımı', is_system: false, is_active: true, sort_order: 50, item_count: 1 });
    const last = fake.state.audit.at(-1);
    assert.deepEqual([last.action, last.details.fields, last.details.key], ['work_category.updated', ['label'], 'k_asansor']);
    assert.ok(!JSON.stringify(last).includes('Asansör bakımı'));
  });

  it('varsayılan (sistem) kategori de yeniden adlandırılır / pasife alınır ama anahtarı ve sistem işareti kalır', async () => {
    await seeded();
    const ariza = fake.state.categories.find((c) => c.key === 'ariza');
    const { category } = await update(ariza.id, { label: 'Teknik arıza' });
    assert.deepEqual([category.key, category.label, category.is_system], ['ariza', 'Teknik arıza', true]);
    const passive = await update(ariza.id, { is_active: false });
    assert.equal(passive.category.is_active, false);
  });

  it('ad çakışması 409 (kendi adının büyük/küçük harf değişimi serbest); değişiklik yoksa HİÇBİR yazma yok', async () => {
    const created = await seeded();
    await rejectsWith(update(created.id, { label: 'arıza' }), 409, 'WORK_CATEGORY_NAME_TAKEN');
    const recased = await update(created.id, { label: 'ASANSÖR' });
    assert.equal(recased.category.label, 'ASANSÖR');
    const before = fake.state.sql.length;
    const same = await update(created.id, { label: 'ASANSÖR', is_active: true });
    assert.equal(same.category.label, 'ASANSÖR');
    assert.equal(fake.state.sql.slice(before).filter((sql) => /^(UPDATE|INSERT|DELETE)/.test(sql)).length, 0);
  });

  it('KULLANILMIŞ kategori pasife alınabilir (kayıtlar eski kategorisiyle kalır), yeniden etkinleştirilebilir; sıra değişir', async () => {
    const created = await seeded();
    fake.state.items.push({ site_code: SITE, category: 'k_asansor' }, { site_code: SITE, category: 'k_asansor' });
    const off = await update(created.id, { is_active: false });
    assert.deepEqual([off.category.is_active, off.category.item_count], [false, 2]);
    assert.equal(fake.state.items.length, 2);
    const on = await update(created.id, { is_active: true, sort_order: 5 });
    assert.deepEqual([on.category.is_active, on.category.sort_order], [true, 5]);
  });

  it('SON etkin kategori pasife alınamaz (409 WORK_CATEGORY_LAST_ACTIVE); başka etkin varken alınabilir', async () => {
    const created = await seeded();
    for (const category of fake.state.categories.filter((c) => c.id !== created.id)) await update(category.id, { is_active: false });
    assert.deepEqual(fake.state.categories.filter((c) => c.is_active).map((c) => c.key), ['k_asansor']);
    await rejectsWith(update(created.id, { is_active: false }), 409, 'WORK_CATEGORY_LAST_ACTIVE');
    assert.equal(fake.state.categories.find((c) => c.id === created.id).is_active, true);
  });

  it('başka sitenin kategorisi / olmayan / geçersiz kimlik 404 WORK_CATEGORY_NOT_FOUND (IDOR yok); doğrulama hataları 400', async () => {
    const created = await seeded();
    await rejectsWith(update(created.id, { label: 'Ele geçirme' }, OTHER_SITE), 404, 'WORK_CATEGORY_NOT_FOUND');
    await rejectsWith(update(9999, { label: 'Yok' }), 404, 'WORK_CATEGORY_NOT_FOUND');
    for (const raw of ['abc', '0', '-1', '1.5', '']) await rejectsWith(updateWorkCategory({ siteCode: SITE, rawId: raw, actor: manager, body: { label: 'x' } }), 404, 'WORK_CATEGORY_NOT_FOUND');
    await rejectsWith(update(created.id, {}), 400, 'INVALID_BODY');
    await rejectsWith(update(created.id, { is_active: 'evet' }), 400, 'INVALID_BODY');
    assert.equal(fake.state.categories.find((c) => c.id === created.id).label, 'Asansör');
  });
});

describe('kategori silme: kullanılmış kategori silinmez, pasife alınır', () => {
  const remove = (id, site = SITE) => deleteWorkCategory({ siteCode: site, rawId: String(id), actor: manager });
  const add = async (label) => (await createWorkCategory({ siteCode: SITE, actor: manager, body: { label } })).category;

  it('KULLANILMAMIŞ özel kategori silinir -> { deleted: true }; satır gider; audit yalnız anahtar', async () => {
    const created = await add('Asansör');
    assert.deepEqual(await remove(created.id), { deleted: true });
    assert.equal(fake.state.categories.some((c) => c.key === 'k_asansor'), false);
    assert.deepEqual(fake.state.audit.at(-1), { action: 'work_category.deleted', site_code: SITE, target_type: 'work_category', target_id: String(created.id), details: { key: 'k_asansor' } });
  });

  it('KULLANILMIŞ kategori SİLİNMEZ, PASİFE alınır -> { deleted: false, deactivated: true, category }; talepler eski kategorisiyle kalır; ikinci DELETE aynı yanıt ve yazma yok', async () => {
    const created = await add('Asansör');
    fake.state.items.push({ site_code: SITE, category: 'k_asansor' }, { site_code: SITE, category: 'k_asansor' }, { site_code: SITE, category: 'k_asansor' });
    const first = await remove(created.id);
    assert.deepEqual([first.deleted, first.deactivated, first.category.key, first.category.is_active, first.category.item_count], [false, true, 'k_asansor', false, 3]);
    assert.ok(fake.state.categories.some((c) => c.key === 'k_asansor' && c.is_active === false));
    assert.equal(fake.state.items.length, 3);
    assert.equal(fake.state.audit.at(-1).action, 'work_category.deactivated');
    assert.deepEqual([fake.state.audit.at(-1).details.reason, fake.state.audit.at(-1).details.item_count], ['in_use', 3]);
    const writes = fake.state.sql.filter((sql) => /^(UPDATE|DELETE)/.test(sql)).length;
    const second = await remove(created.id);
    assert.deepEqual([second.deleted, second.deactivated, second.category.is_active], [false, true, false]);
    assert.equal(fake.state.sql.filter((sql) => /^(UPDATE|DELETE)/.test(sql)).length, writes);
  });

  it('başka sitedeki aynı anahtarlı kayıtlar KULLANIM sayılmaz (site kapsamı)', async () => {
    const created = await add('Asansör');
    fake.state.items.push({ site_code: OTHER_SITE, category: 'k_asansor' });
    assert.deepEqual(await remove(created.id), { deleted: true });
  });

  it('varsayılan (sistem) kategori SİLİNEMEZ: 409 WORK_CATEGORY_SYSTEM (kullanılmamış olsa da); satır kalır', async () => {
    await add('Asansör');
    const diger = fake.state.categories.find((c) => c.key === 'diger');
    await rejectsWith(remove(diger.id), 409, 'WORK_CATEGORY_SYSTEM');
    assert.ok(fake.state.categories.some((c) => c.key === 'diger'));
  });

  it('SON etkin kategori ne silinir ne pasife alınır (409 WORK_CATEGORY_LAST_ACTIVE) - kullanılmış da kullanılmamış da', async () => {
    const created = await add('Asansör');
    for (const category of fake.state.categories.filter((c) => c.id !== created.id)) category.is_active = false;
    await rejectsWith(remove(created.id), 409, 'WORK_CATEGORY_LAST_ACTIVE');
    fake.state.items.push({ site_code: SITE, category: 'k_asansor' });
    await rejectsWith(remove(created.id), 409, 'WORK_CATEGORY_LAST_ACTIVE');
    assert.equal(fake.state.categories.find((c) => c.id === created.id).is_active, true);
  });

  it('PASİF ve kullanılmamış özel kategori silinir (son etkin kuralı etkin olanlar içindir)', async () => {
    const created = await add('Asansör');
    await updateWorkCategory({ siteCode: SITE, rawId: String(created.id), actor: manager, body: { is_active: false } });
    assert.deepEqual(await remove(created.id), { deleted: true });
  });

  it('başka sitenin / olmayan / geçersiz kimlik 404 WORK_CATEGORY_NOT_FOUND', async () => {
    const created = await add('Asansör');
    await rejectsWith(remove(created.id, OTHER_SITE), 404, 'WORK_CATEGORY_NOT_FOUND');
    await rejectsWith(remove(9999), 404, 'WORK_CATEGORY_NOT_FOUND');
    for (const raw of ['abc', '0', '-3']) await rejectsWith(deleteWorkCategory({ siteCode: SITE, rawId: raw, actor: manager }), 404, 'WORK_CATEGORY_NOT_FOUND');
    assert.ok(fake.state.categories.some((c) => c.id === created.id));
  });
});

describe('talep açarken kategori denetimi (assertWorkCategoryUsable)', () => {
  it('varsayılan ve etkin özel kategori geçer; satır FOR SHARE ile kilitlenir; varsayılanlar tohumlanır', async () => {
    const created = (await createWorkCategory({ siteCode: SITE, actor: manager, body: { label: 'Asansör' } })).category;
    await assertWorkCategoryUsable(pool, SITE, 'ariza');
    await assertWorkCategoryUsable(pool, SITE, created.key);
    assert.ok(fake.state.sql.some((sql) => sql === 'SELECT is_active FROM work_categories WHERE site_code = $1 AND key = $2 FOR SHARE'));
    fake = createFake();
    await assertWorkCategoryUsable(pool, SITE, 'diger');
    assert.equal(fake.state.categories.length, 4);
  });

  it('sitede olmayan anahtar 400 INVALID_BODY (başka sitenin özel kategorisi dahil); PASİF kategori 409 WORK_CATEGORY_INACTIVE', async () => {
    const created = (await createWorkCategory({ siteCode: SITE, actor: manager, body: { label: 'Asansör' } })).category;
    await rejectsWith(assertWorkCategoryUsable(pool, SITE, 'k_yok'), 400, 'INVALID_BODY');
    await rejectsWith(assertWorkCategoryUsable(pool, OTHER_SITE, created.key), 400, 'INVALID_BODY');
    await updateWorkCategory({ siteCode: SITE, rawId: String(created.id), actor: manager, body: { is_active: false } });
    await rejectsWith(assertWorkCategoryUsable(pool, SITE, created.key), 409, 'WORK_CATEGORY_INACTIVE');
    await assertWorkCategoryUsable(pool, SITE, 'ariza');
  });

  it('kaynak düzeyi: createWorkItem denetimi idempotans tekrarından SONRA, konum doğrulamasından SONRA ve INSERT\'ten ÖNCE yapar', () => {
    const source = read('src', 'modules', 'work_tracking_resident.js');
    const replay = source.indexOf('return { id: Number(same.id), replayed: true };');
    const location = source.indexOf("throw invalidLocation('Seçilen blok bu siteye ait değil.');");
    const check = source.indexOf('await assertWorkCategoryUsable(client, siteCode, input.category);');
    const insert = source.indexOf('INSERT INTO work_items (site_code, category,');
    assert.ok(replay > 0 && location > replay && check > location && insert > check, `${replay} ${location} ${check} ${insert}`);
    assert.match(source, /import \{ assertWorkCategoryUsable \} from '\.\/work_categories_read\.js';/);
    // eski sabit kontrol kalmadı
    assert.ok(!/CATEGORIES\.includes\(/.test(read('src', 'modules', 'work_tracking_common.js')));
  });
});

describe('sakin kategori listesi (GET /app/work-categories)', () => {
  const resident = { id: 20004, user_code: 20004, userCode: 20004, role: 'apartment_owner', full_name: 'Sakin' };

  it('yalnız ETKİN kategoriler, kullanım sayısı YOK; modül açık + aktif sakin olmalı', async () => {
    await createWorkCategory({ siteCode: SITE, actor: manager, body: { label: 'Asansör' } });
    fake.state.categories.find((c) => c.key === 'bakim').is_active = false;
    const result = await listMyWorkCategories(resident, { site_code: String(SITE) });
    assert.deepEqual(result.items.map((c) => c.key), ['ariza', 'sikayet_oneri', 'diger', 'k_asansor']);
    assert.ok(result.items.every((c) => !('item_count' in c) && c.is_active === true));
  });

  it('site_code zorunlu (400), onaysız / olmayan site 404, modül kapalı 403 MODULE_DISABLED, sakin değil 403 NOT_A_RESIDENT, hesap yok 401', async () => {
    await rejectsWith(listMyWorkCategories(resident, {}), 400, 'INVALID_BODY');
    await rejectsWith(listMyWorkCategories(resident, { site_code: 'x' }), 400, 'INVALID_BODY');
    await rejectsWith(listMyWorkCategories(resident, { site_code: '1999999999' }), 404, 'SITE_NOT_FOUND');
    fake.state.approved = false;
    await rejectsWith(listMyWorkCategories(resident, { site_code: String(SITE) }), 404, 'SITE_NOT_FOUND');
    fake.state.approved = true;
    fake.state.moduleEnabled = false;
    await rejectsWith(listMyWorkCategories(resident, { site_code: String(SITE) }), 403, 'MODULE_DISABLED');
    fake.state.moduleEnabled = true;
    fake.state.resident = false;
    await rejectsWith(listMyWorkCategories(resident, { site_code: String(SITE) }), 403, 'NOT_A_RESIDENT');
    await rejectsWith(listMyWorkCategories({}, { site_code: String(SITE) }), 401, 'ACCOUNT_DELETED');
    assert.equal(fake.state.categories.length, 0, 'yetkisiz sakin için tohumlama bile yapılmaz');
  });
});

describe('rapor: kategori adı ve sitenin eklediği kategoriler', () => {
  const generatedAt = new Date('2026-10-19T12:00:00Z');
  const total = { category: null, is_total: 1, opened: '5', closed: '0', cancelled: '0', open_now: '5', overdue_now: '0' };

  it('dört varsayılan sabit sırada (sıfır dolgulu), sonra sitenin kategorileri ada göre; ad = sitedeki ad (yeniden adlandırılmış varsayılan dahil); anahtar DEĞİŞMEZ', () => {
    const report = assembleReport({
      from: '2026-09-20',
      to: '2026-10-19',
      generatedAt,
      itemRows: [
        { category: 'ariza', category_label: 'Teknik arıza', is_total: 0, opened: '2', closed: '0', cancelled: '0', open_now: '2', overdue_now: '0' },
        { category: 'k_su_kacagi', category_label: 'Su kaçağı', is_total: 0, opened: '2', closed: '0', cancelled: '0', open_now: '2', overdue_now: '0' },
        { category: 'k_asansor', category_label: 'Asansör', is_total: 0, opened: '1', closed: '0', cancelled: '0', open_now: '1', overdue_now: '0' },
        total,
      ],
      resolvedRows: [
        { category: 'k_su_kacagi', is_total: 0, resolved: '1', avg_hours: '3', median_hours: '3' },
        { category: null, is_total: 1, resolved: '1', avg_hours: '3', median_hours: '3' },
      ],
      assigneeRows: [],
    });
    assert.deepEqual(report.by_category, [
      { category: 'ariza', category_label: 'Teknik arıza', opened: 2, resolved: 0 },
      { category: 'bakim', category_label: 'Bakım', opened: 0, resolved: 0 },
      { category: 'sikayet_oneri', category_label: 'Şikayet / Öneri', opened: 0, resolved: 0 },
      { category: 'diger', category_label: 'Diğer', opened: 0, resolved: 0 },
      { category: 'k_asansor', category_label: 'Asansör', opened: 1, resolved: 0 },
      { category: 'k_su_kacagi', category_label: 'Su kaçağı', opened: 2, resolved: 1 },
    ]);
  });

  it('kaynak düzeyi: rapor ve yıllık rapor sorguları kategori adını JOIN ile alır (ek sorgu yok); sütun adı category_label', () => {
    const report = read('src', 'modules', 'work_tracking_report.js');
    assert.ok(report.includes('MAX(wc.label) AS category_label'));
    assert.ok(report.includes('LEFT JOIN work_categories wc ON wc.site_code = w.site_code AND wc.key = w.category'));
    const annual = read('src', 'modules', 'annual_report_service.js');
    assert.ok(annual.includes('MAX(wc.label) AS category_label'));
    assert.ok(annual.includes('categoryLabelOf(r.category, r.category_label)'));
    for (const file of ['work_tracking_service.js', 'work_tracking_resident.js']) {
      const source = read('src', 'modules', file);
      assert.ok(source.includes('wc.label AS category_label'), file);
      assert.ok(source.includes('LEFT JOIN work_categories wc ON wc.site_code = w.site_code AND wc.key = w.category'), file);
    }
  });
});
