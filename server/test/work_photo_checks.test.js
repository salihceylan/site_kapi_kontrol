// İş Takibi fotoğraf yeniden kullanım uyarısı (100, P2-6; DB'siz): eşleşme satırlarından uyarı üretimi (aynı konum / farklı konum / aynı talepte yineleme), görevli kapsamı
// (kapsam dışı kayıt kimlik ve konum vermeden yalnız sayıya katılır), SQL iskeleti (sha256 + site sınırı + hazır fotoğraf), güvenli sarmalayıcı (hata uyarıyı atlar, ayrıntıyı bozmaz),
// talep ayrıntısı ve yükleme yanıtına bağlanma (sahte veritabanı + kaynak düzeyi). Uyarı ASLA engel değildir.
// Gerçek PostgreSQL doğrulaması (konum eşitliği, görevli kapsamı, site sınırı, indeks planı): scripts/qa_work_categories_pg.mjs (P bölümü; kendi tek kullanımlık veritabanını açar).
import { describe, it, before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { pool } from '../src/db.js';
import {
  PHOTO_MATCH_ROW_LIMIT,
  PHOTO_RELATED_LIMIT,
  PHOTO_WARNING_CODES,
  buildPhotoWarnings,
  loadPhotoWarnings,
  loadPhotoWarningsSafe,
  photoMatchSql,
  relatedLocationLabel,
} from '../src/modules/work_photo_checks.js';
import { getWorkItemDetail } from '../src/modules/work_tracking_service.js';
import { completeAttachmentUpload, managerScope, residentScope } from '../src/modules/work_attachments_service.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const read = (...parts) => readFileSync(path.join(here, '..', ...parts), 'utf8').replace(/\r\n/g, '\n');
const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
const SITE = 1000000001;

/** Eşleşme satırı fabrikası (photoMatchSql sütunları). */
function match(over = {}) {
  return {
    attachment_id: 10,
    other_attachment_id: 20,
    other_item_id: 45,
    other_created_at: new Date('2026-10-20T08:00:00Z'),
    same_item: false,
    same_location: false,
    other_location_type: 'daire',
    other_block_name: 'B Blok',
    other_unit_label: 'Daire 5',
    visible: true,
    ...over,
  };
}

describe('buildPhotoWarnings: uyarı koşulları', () => {
  it('eşleşme yoksa uyarı YOK', () => {
    assert.deepEqual(buildPhotoWarnings([]), []);
    assert.deepEqual(buildPhotoWarnings(undefined), []);
  });

  it('FARKLI konumdaki başka kayıtta aynı fotoğraf -> photo_reused_other_location (warning); mesajda kayıt kimliği ve konum; related ayrıntılı', () => {
    const [warning, ...rest] = buildPhotoWarnings([match()]);
    assert.equal(rest.length, 0);
    assert.deepEqual(
      [warning.code, warning.severity, warning.attachment_id, warning.related_count],
      [PHOTO_WARNING_CODES.reusedOtherLocation, 'warning', 10, 1],
    );
    assert.equal(
      warning.message,
      'Bu fotoğraf farklı bir konuma ait başka bir kayıtta da kullanılmış (#45 · B Blok - Daire 5). Konum etiketiyle uyuşmuyor olabilir; fotoğrafı kontrol edin.',
    );
    assert.deepEqual(warning.related, [{ work_item_id: 45, location_label: 'B Blok - Daire 5', same_location: false, created_at: '2026-10-20T08:00:00.000Z' }]);
  });

  it('AYNI konumdaki başka kayıtta aynı fotoğraf -> photo_reused (info), konumsuz daha yumuşak mesaj', () => {
    const [warning] = buildPhotoWarnings([match({ same_location: true })]);
    assert.deepEqual([warning.code, warning.severity], [PHOTO_WARNING_CODES.reused, 'info']);
    assert.equal(warning.message, 'Bu fotoğraf aynı konumdaki başka bir kayıtta da kullanılmış (#45). Aynı sorunun tekrarı olabilir.');
    assert.equal(warning.related[0].same_location, true);
  });

  it('birden çok kayıttan biri bile farklı konumdaysa UYUŞMAZLIK uyarısı; uyuşmayanlar önce, sonra yeniden eskiye; aynı talep tek giriş', () => {
    const rows = [
      match({ other_item_id: 30, same_location: true }),
      match({ other_attachment_id: 21, other_item_id: 30, same_location: true }), // aynı talepte iki kopya: tek giriş
      match({ other_item_id: 41, same_location: false, other_block_name: 'A Blok', other_unit_label: 'Daire 2' }),
      match({ other_item_id: 50, same_location: true }),
    ];
    const [warning] = buildPhotoWarnings(rows);
    assert.equal(warning.code, PHOTO_WARNING_CODES.reusedOtherLocation);
    assert.deepEqual(warning.related.map((entry) => entry.work_item_id), [41, 50, 30]);
    assert.equal(warning.related_count, 3);
    assert.ok(warning.message.includes('#41 · A Blok - Daire 2, #50 · B Blok - Daire 5, #30 · B Blok - Daire 5'));
  });

  it('en çok 5 kayıt gösterilir, kalanı "ve N kayıt daha"; related_count TOPLAM', () => {
    const rows = Array.from({ length: 8 }, (_, index) => match({ other_item_id: 100 + index }));
    const [warning] = buildPhotoWarnings(rows);
    assert.equal(warning.related.length, PHOTO_RELATED_LIMIT);
    assert.equal(warning.related_count, 8);
    assert.ok(warning.message.includes('ve 3 kayıt daha'));
  });

  it('AYNI talepte yineleme: yalnız SONRAKİ kopya (eski kopyası olan fotoğraf) işaretlenir; eski kopya işaretlenmez', () => {
    const rows = [
      match({ attachment_id: 10, other_attachment_id: 11, same_item: true, other_item_id: 7 }), // 10'un eşi 11: 11 daha yeni -> 10 işaretlenmez
      match({ attachment_id: 11, other_attachment_id: 10, same_item: true, other_item_id: 7 }), // 11'in eşi 10: 10 daha eski -> 11 işaretlenir
    ];
    const warnings = buildPhotoWarnings(rows);
    assert.deepEqual(warnings.map((w) => [w.code, w.attachment_id]), [[PHOTO_WARNING_CODES.duplicateInItem, 11]]);
    assert.equal(warnings[0].message, 'Aynı fotoğraf bu kayıtta birden fazla kez eklenmiş.');
    assert.deepEqual([warnings[0].related, warnings[0].related_count], [[], 0]);
  });

  it('aynı fotoğraf hem başka kayıtta hem aynı talepte -> iki ayrı uyarı; fotoğraflar kimlik sırasıyla', () => {
    const rows = [
      match({ attachment_id: 12, other_attachment_id: 5, same_item: true, other_item_id: 7 }),
      match({ attachment_id: 12, other_attachment_id: 30, other_item_id: 60, same_location: true }),
      match({ attachment_id: 3, other_attachment_id: 31, other_item_id: 61 }),
    ];
    assert.deepEqual(buildPhotoWarnings(rows).map((w) => [w.attachment_id, w.code]), [
      [3, PHOTO_WARNING_CODES.reusedOtherLocation],
      [12, PHOTO_WARNING_CODES.reused],
      [12, PHOTO_WARNING_CODES.duplicateInItem],
    ]);
  });

  it('GÖREVLİ kapsamı: kapsam dışı (visible false) kayıt kimlik / konum vermez, yalnız related_count\'a girer; hiç görünür kayıt yoksa mesajda "#" yok', () => {
    const [hidden] = buildPhotoWarnings([match({ visible: false }), match({ other_item_id: 46, visible: false })]);
    assert.deepEqual([hidden.related, hidden.related_count], [[], 2]);
    assert.equal(hidden.code, PHOTO_WARNING_CODES.reusedOtherLocation);
    assert.ok(!/#\d/.test(hidden.message));
    assert.equal(hidden.message, 'Bu fotoğraf farklı bir konuma ait başka bir kayıtta da kullanılmış. Konum etiketiyle uyuşmuyor olabilir; fotoğrafı kontrol edin.');
    const [mixed] = buildPhotoWarnings([match({ other_item_id: 45, visible: true }), match({ other_item_id: 46, visible: false })]);
    assert.deepEqual(mixed.related.map((entry) => entry.work_item_id), [45]);
    assert.equal(mixed.related_count, 2);
    assert.ok(mixed.message.includes('(#45 · B Blok - Daire 5 ve 1 kayıt daha)'));
    assert.ok(!JSON.stringify(mixed).includes('46'));
  });

  it('boolean alanlar pg metin biçiminde de ("t" / "true") doğru okunur; created_at metin de olabilir; sakin yanıtında kullanılacak alan (visible) dışarı SIZMAZ', () => {
    const [warning] = buildPhotoWarnings([match({ same_item: 'f', same_location: 't', visible: 't', other_created_at: '2026-10-21T10:00:00Z' })]);
    assert.equal(warning.code, PHOTO_WARNING_CODES.reused);
    assert.equal(warning.related[0].created_at, '2026-10-21T10:00:00.000Z');
    assert.ok(!('visible' in warning.related[0]));
  });

  it('relatedLocationLabel: daire "Blok - Daire", blok adlı ortak alan "Blok · Ortak alan", blok yoksa "Ortak alan"', () => {
    assert.equal(relatedLocationLabel({ other_location_type: 'daire', other_block_name: 'A Blok', other_unit_label: 'Daire 1' }), 'A Blok - Daire 1');
    assert.equal(relatedLocationLabel({ other_location_type: 'daire', other_block_name: null, other_unit_label: null }), 'Daire');
    assert.equal(relatedLocationLabel({ other_location_type: 'ortak_alan', other_block_name: 'A Blok' }), 'A Blok · Ortak alan');
    assert.equal(relatedLocationLabel({ other_location_type: 'ortak_alan', other_block_name: ' ' }), 'Ortak alan');
  });
});

describe('photoMatchSql: sorgu iskeleti', () => {
  it('yalnız HAZIR fotoğraf ve sha256 DOLU; AYNI site (site_code eşitliği iki taraf); kendisiyle eşleşmez; konum eşitliği daire + dairenin bloğunu da katar; satır sınırı', () => {
    const sql = norm(photoMatchSql());
    for (const fragment of [
      "a.status = 'ready' AND a.sha256 IS NOT NULL",
      "o.site_code = a.site_code AND o.sha256 = a.sha256 AND o.status = 'ready' AND o.id <> a.id",
      'w.id = o.work_item_id AND w.site_code = o.site_code',
      'WHERE cw.id = $1 AND cw.site_code = $2',
      'cw.location_type = w.location_type AND cw.apartment_id IS NOT DISTINCT FROM w.apartment_id AND COALESCE(cw.block_id, cap.block_id) IS NOT DISTINCT FROM COALESCE(w.block_id, ap.block_id)',
      `ORDER BY a.id, o.id LIMIT ${PHOTO_MATCH_ROW_LIMIT}`,
    ]) {
      assert.ok(sql.includes(fragment), fragment);
    }
    assert.ok(sql.includes('TRUE AS visible'));
    assert.ok(!sql.includes('AND a.id = $'));
  });

  it('görevli: kapsam koşulu ilgili kayda ($3 kullanıcı) uygulanır; tek fotoğraf: son parametre', () => {
    const staff = norm(photoMatchSql({ staff: true }));
    assert.ok(staff.includes('(w.assigned_to IS NULL OR w.assigned_to = $3 OR NOT EXISTS ('));
    assert.ok(staff.includes('AS visible'));
    assert.ok(norm(photoMatchSql({ staff: true, single: true })).includes('AND a.id = $4'));
    assert.ok(norm(photoMatchSql({ single: true })).includes('AND a.id = $3'));
  });
});

describe('loadPhotoWarnings / loadPhotoWarningsSafe', () => {
  function fakeDb(rows, { fail = null } = {}) {
    const calls = [];
    return {
      calls,
      async query(text, params) {
        calls.push({ sql: norm(text), params });
        if (fail) throw fail;
        return { rows };
      },
    };
  }

  it('parametreler: [talep, site] (+ görevli kullanıcı) (+ fotoğraf); sonuç uyarılara çevrilir', async () => {
    const db = fakeDb([match()]);
    const warnings = await loadPhotoWarnings(db, { siteCode: SITE, itemId: 5, scope: { kind: 'manager', userCode: 9 } });
    assert.equal(warnings.length, 1);
    assert.deepEqual(db.calls[0].params, [5, SITE]);
    await loadPhotoWarnings(db, { siteCode: SITE, itemId: 5, scope: { kind: 'staff', userCode: 9 } });
    assert.deepEqual(db.calls[1].params, [5, SITE, 9]);
    await loadPhotoWarnings(db, { siteCode: SITE, itemId: 5, attachmentId: 77, scope: { kind: 'staff', userCode: 9 } });
    assert.deepEqual(db.calls[2].params, [5, SITE, 9, 77]);
    await loadPhotoWarnings(db, { siteCode: SITE, itemId: 5, attachmentId: 77, scope: { kind: 'super', userCode: 1 } });
    assert.deepEqual(db.calls[3].params, [5, SITE, 77]);
  });

  it('hazır fotoğraf yoksa sorgu HİÇ gitmez; sorgu hatası uyarıyı atlar (boş liste), günlüğe yalnız kod yazılır', async () => {
    const quiet = fakeDb([match()]);
    assert.deepEqual(await loadPhotoWarningsSafe(quiet, { hasReady: false, siteCode: SITE, itemId: 5, scope: { kind: 'manager', userCode: 1 } }), []);
    assert.equal(quiet.calls.length, 0);
    const original = console.error;
    const logged = [];
    console.error = (...args) => logged.push(args.join(' '));
    try {
      const broken = fakeDb([], { fail: Object.assign(new Error('GIZLI-SQL-DETAYI'), { code: '42P01' }) });
      assert.deepEqual(await loadPhotoWarningsSafe(broken, { siteCode: SITE, itemId: 5, scope: { kind: 'manager', userCode: 1 } }), []);
    } finally {
      console.error = original;
    }
    assert.equal(logged.length, 1);
    assert.ok(logged[0].includes('42P01'));
    assert.ok(!logged[0].includes('GIZLI-SQL-DETAYI'));
  });
});

// --- Bağlantı noktaları -------------------------------------------------------------------------------------------------------

describe('talep ayrıntısına bağlanma (getWorkItemDetail)', () => {
  let queries;
  let warningRows;
  let readyAttachment;

  before(() => {
    pool.connect = async () => {
      throw new Error('işlem açılmamalıydı');
    };
  });
  after(() => {
    delete pool.connect;
  });
  beforeEach(() => {
    queries = [];
    warningRows = [];
    readyAttachment = true;
  });

  const itemRow = {
    id: '5', site_code: String(SITE), category: 'ariza', location_type: 'ortak_alan', title: 'T', description: 'D', status: 'yeni', priority: 'normal', resident_urgent: false,
    due_date: null, created_at: new Date('2026-10-01T00:00:00Z'), updated_at: new Date('2026-10-01T00:00:00Z'), closed_at: null, created_by: 12, assigned_to: null,
    apartment_id: null, block_id: null, requester_name: 'Ada', requester_phone: null, attachment_count: 1,
  };
  const db = {
    async query(text, params) {
      const sql = norm(text);
      queries.push(sql);
      if (/FROM work_items w LEFT JOIN work_categories wc/.test(sql)) return { rows: [itemRow] };
      if (/FROM work_item_events e/.test(sql)) return { rows: [] };
      if (/FROM work_item_attachments a LEFT JOIN users u/.test(sql)) {
        return {
          rows: readyAttachment
            ? [{ id: 31, work_item_id: 5, site_code: SITE, uploaded_by: 12, file_name: 'f.jpg', mime_type: 'image/jpeg', size_bytes: 10, status: 'ready', created_at: new Date(), ready_at: new Date(), uploaded_by_name: 'Ada', uploaded_by_resident: true }]
            : [],
        };
      }
      if (/FROM work_items cw LEFT JOIN apartments cap/.test(sql)) {
        assert.deepEqual(params.slice(0, 2), [5, SITE]);
        return { rows: warningRows };
      }
      throw new Error(`BEKLENMEYEN SQL: ${sql.slice(0, 160)}`);
    },
  };
  const access = { kind: 'manager', userCode: 20001, canManage: true };

  it('yanıt photo_warnings taşır (eşleşme yoksa boş dizi); hazır fotoğraf yoksa uyarı sorgusu gitmez', async () => {
    const empty = await getWorkItemDetail(SITE, '5', access, db);
    assert.deepEqual(empty.photo_warnings, []);
    warningRows = [match({ attachment_id: 31 })];
    const warned = await getWorkItemDetail(SITE, '5', access, db);
    assert.deepEqual(warned.photo_warnings.map((w) => [w.code, w.attachment_id]), [[PHOTO_WARNING_CODES.reusedOtherLocation, 31]]);
    assert.equal(warned.attachments.length, 1);
    queries.length = 0;
    readyAttachment = false;
    const none = await getWorkItemDetail(SITE, '5', access, db);
    assert.deepEqual(none.photo_warnings, []);
    assert.ok(!queries.some((sql) => /FROM work_items cw/.test(sql)));
  });

  it('uyarı sorgusu patlarsa ayrıntı YİNE döner (photo_warnings boş)', async () => {
    const original = console.error;
    console.error = () => {};
    try {
      const failing = { async query(text, params) { if (/FROM work_items cw/.test(norm(text))) throw Object.assign(new Error('x'), { code: '57014' }); return db.query(text, params); } };
      const detail = await getWorkItemDetail(SITE, '5', access, failing);
      assert.deepEqual(detail.photo_warnings, []);
      assert.equal(detail.item.id, 5);
    } finally {
      console.error = original;
    }
  });

  it('sakin ayrıntısı (work_tracking_resident.js) uyarı ÜRETMEZ: modül photo_checks içe aktarmaz, yanıtta photo_warnings alanı yok', () => {
    const resident = read('src', 'modules', 'work_tracking_resident.js');
    assert.ok(!/work_photo_checks|photo_warnings|loadPhotoWarnings/.test(resident));
  });
});

describe('yükleme tamamlama yanıtı (completeAttachmentUpload)', () => {
  it('kaynak düzeyi: uyarı YALNIZ yönetim kapsamında, işlem KESİNLEŞTİKTEN sonra ve güvenli sarmalayıcıyla; yalnız uyarı varsa alan eklenir; sakin yanıtında yok', () => {
    const source = read('src', 'modules', 'work_attachments_service.js');
    const commit = source.indexOf('return actorCode;\n  });');
    const response = source.indexOf('const response = await attachmentResponse(target.attId, userCode, scope);');
    const guard = source.indexOf("if (scope.kind !== 'resident') {", response);
    const call = source.indexOf('await loadPhotoWarningsSafe(pool, { siteCode: target.siteCode, itemId: target.itemId, attachmentId: target.attId, scope });', guard);
    const assign = source.indexOf('response.photo_warnings = warnings;', call);
    assert.ok(commit > 0 && response > commit && guard > response && call > guard && assign > call, `${commit} ${response} ${guard} ${call} ${assign}`);
    assert.ok(source.includes('if (warnings.length > 0) {'));
    assert.match(source, /import \{ loadPhotoWarningsSafe \} from '\.\/work_photo_checks\.js';/);
  });

  it('kapsam yardımcıları: managerScope yönetimi, residentScope sakini ayırır (uyarı kararı scope.kind\'a bağlı)', () => {
    assert.equal(managerScope({ kind: 'staff', userCode: 9, siteCode: SITE, canManage: false }).kind, 'staff');
    assert.equal(residentScope({ user_code: 12 }).kind, 'resident');
    assert.equal(typeof completeAttachmentUpload, 'function');
  });
});

describe('migration 100 dizini', () => {
  it('(site_code, sha256) kısmi dizini var: sha256 DOLU satırlar; sorgu iskeleti her iki tarafı site + özetle birleştirir', () => {
    const migration = read('migrations', '100_work_categories.sql');
    assert.ok(/CREATE INDEX IF NOT EXISTS idx_work_item_attachments_site_sha256 ON work_item_attachments \(site_code, sha256\) WHERE sha256 IS NOT NULL;/.test(migration));
  });
});
