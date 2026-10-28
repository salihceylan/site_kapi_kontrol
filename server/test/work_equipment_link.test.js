// İş kaydı <-> ekipman bağı ve fotoğraf önce/sonra etiketi (096), DB'siz KATI sahte veritabanıyla:
//  - şema: migration 096 <-> work_equipment_schema.js aynı SQL, ekleyici / idempotent, db.js sırası, katalog kontrolü (her şey varsa DDL yok), 55P03 yeniden deneme;
//  - girdi: PATCH equipment_id, ek etiketi (phase), yanıt eşleyicileri (equipment, phase, equipment_changed olayı);
//  - servis: ekipman bağı yazma (olay + denetim + ekipman doğrulaması + sakin okunmamış işareti DOKUNULMAZ), kapalı talep, görevli kapsamı;
//  - ek kaydı: etiket INSERT'e gider, yükleme tamamlanınca olay / denetim dosya kimliğini (ek no, etiket, sha256) taşır;
//  - servis geçmişi ucu: kapsam (görevli), kurul, modül kapalı, sayfalama, 404/400/403.
// Gerçek PostgreSQL doğrulaması bu ortamda yapılamaz (PG yok): SQL metni migration <-> modül eşitliği ve katı sahte ile sınanır; canlı provada 096 iki kez çalıştırılmalıdır.
import { describe, it, before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import express from 'express';
import { pool } from '../src/db.js';
import { authRequired } from '../src/middlewares/auth_middleware.js';
import { DEFAULT_MIGRATIONS_DIR, findUnsafeStatements } from '../scripts/migrate.js';
import {
  ATTACHMENT_PHASES,
  EVENT_TYPES_WITH_EQUIPMENT,
  WORK_EQUIPMENT_STEPS,
  WORK_EQUIPMENT_STEP_IDS,
  ensureWorkEquipmentSchema,
  workEquipmentMigrationSql,
  workEquipmentSchemaHooks,
} from '../src/modules/work_equipment_schema.js';
import { EVENT_TYPES_WITH_ATTACHMENTS } from '../src/modules/work_attachments_schema.js';
import { mapAttachment, parseAttachmentInput, parseAttachmentPhase } from '../src/modules/work_attachments_common.js';
import { DELETED_EQUIPMENT_LABEL, mapEvent, mapManagerItem, parsePatchInput } from '../src/modules/work_tracking_common.js';
import { updateWorkItem } from '../src/modules/work_tracking_service.js';
import { createAttachment, completeAttachmentUpload, managerScope } from '../src/modules/work_attachments_service.js';
import { listEquipmentWorkHistory, mapHistoryItem } from '../src/modules/work_equipment_history.js';
import { equipmentRouter } from '../src/modules/equipment_routes.js';

workEquipmentSchemaHooks.sleep = async () => {};

const here = path.dirname(fileURLToPath(import.meta.url));
const MIGRATION = readFileSync(path.join(DEFAULT_MIGRATIONS_DIR, '096_work_equipment_link.sql'), 'utf8').replace(/\r\n/g, '\n');
const DB_SOURCE = readFileSync(path.join(here, '..', 'src', 'db.js'), 'utf8').replace(/\r\n/g, '\n');
const norm = (text) => String(text).replace(/\/\*[\s\S]*?\*\//g, ' ').replace(/--.*$/gm, ' ').replace(/\s+/g, ' ').trim();
const ok = (rows = []) => ({ rows, rowCount: rows.length });

const SITE = 1000000001;
const OTHER_SITE = 1000000002;

// --- Şema --------------------------------------------------------------------------------------------------------------------------

describe('096 şeması: migration <-> modül, ekleyici, katalog kontrollü', () => {
  it('migration 096 gövdesi adımların birleşimidir (aynı SQL, aynı sıra)', () => {
    assert.ok(norm(MIGRATION).includes(norm(workEquipmentMigrationSql())));
    const positions = WORK_EQUIPMENT_STEPS.map((step) => norm(MIGRATION).indexOf(norm(step.sql)));
    assert.ok(positions.every((position) => position >= 0));
    assert.deepEqual(positions, [...positions].sort((a, b) => a - b), 'adımlar migration içinde aynı sırada');
  });

  it('ekleyici ve idempotent: tablo / satır silme ve güncelleme YOK, tek DROP olay türü kısıtının yeniden kurulumudur, migration çalıştırıcı için güvenli', () => {
    for (const step of WORK_EQUIPMENT_STEPS) {
      assert.doesNotMatch(step.sql, /\b(DROP TABLE|DROP COLUMN|TRUNCATE|DELETE FROM|UPDATE |INSERT INTO)\b/i, step.id);
      assert.match(step.sql, /IF NOT EXISTS/, step.id);
    }
    const drops = WORK_EQUIPMENT_STEPS.filter((step) => /\bDROP\b/i.test(step.sql));
    assert.deepEqual(drops.map((step) => step.id), ['events:type_check']);
    assert.match(drops[0].sql, /DROP CONSTRAINT IF EXISTS chk_work_item_events_type;\s*ALTER TABLE work_item_events ADD CONSTRAINT chk_work_item_events_type/, 'DROP + ADD aynı DO bloğunda (kısıtsız pencere yok)');
    assert.deepEqual(findUnsafeStatements(MIGRATION), []);
    assert.doesNotMatch(MIGRATION, /CONCURRENTLY/);
  });

  it('olay türü kümesi: 047 kümesi + equipment_changed; kısıt SQL\'i tüm türleri içerir; etiket kümesi before / after', () => {
    assert.deepEqual(EVENT_TYPES_WITH_EQUIPMENT, [...EVENT_TYPES_WITH_ATTACHMENTS, 'equipment_changed']);
    const typeStep = WORK_EQUIPMENT_STEPS.find((step) => step.id === 'events:type_check');
    for (const type of EVENT_TYPES_WITH_EQUIPMENT) assert.ok(typeStep.sql.includes(`'${type}'`), type);
    assert.deepEqual(ATTACHMENT_PHASES, ['before', 'after']);
    const phaseStep = WORK_EQUIPMENT_STEPS.find((step) => step.id === 'attachments:phase_check');
    assert.ok(phaseStep.sql.includes("phase IS NULL OR phase IN ('before', 'after')"));
  });

  it('sütunlar boş (NULL) başlar: varsayılansız, NOT NULL değil; FK ON DELETE SET NULL; kısmi indeks yalnız bağlı kayıtlar için', () => {
    const sql = (id) => WORK_EQUIPMENT_STEPS.find((step) => step.id === id).sql;
    assert.equal(sql('items:equipment_column'), 'ALTER TABLE work_items ADD COLUMN IF NOT EXISTS equipment_id BIGINT;');
    assert.equal(sql('attachments:phase_column'), 'ALTER TABLE work_item_attachments ADD COLUMN IF NOT EXISTS phase TEXT;');
    assert.match(sql('items:equipment_fk'), /FOREIGN KEY \(equipment_id\) REFERENCES equipment_items\(id\) ON DELETE SET NULL/);
    assert.match(sql('items:equipment_index'), /WHERE equipment_id IS NOT NULL/);
  });

  it('db.js ensureWorkEquipmentSchema\'yı 042 / 047 / 068 kurulumlarından SONRA çağırır', () => {
    const at = (needle) => DB_SOURCE.indexOf(needle);
    assert.ok(at('await ensureWorkEquipmentSchema(client)') > 0);
    assert.ok(at('await ensureWorkEquipmentSchema(client)') > at('await ensureWorkTrackingSchema(client)'));
    assert.ok(at('await ensureWorkEquipmentSchema(client)') > at('await ensureWorkAttachmentsSchema(client)'));
    assert.ok(at('await ensureWorkEquipmentSchema(client)') > at('await ensureEquipmentSchema(client)'));
  });

  function fakeClient({ done = [], missingTables = [], failures = {} } = {}) {
    const sent = [];
    return {
      sent,
      async query(sql) {
        if (/^SELECT .* AS g_work_items/.test(norm(sql))) {
          const row = {};
          for (const table of ['work_items', 'work_item_attachments', 'work_item_events', 'equipment_items']) row[`g_${table}`] = !missingTables.includes(table);
          WORK_EQUIPMENT_STEPS.forEach((step, index) => {
            row[`s${index}`] = done.includes(step.id);
          });
          return ok([row]);
        }
        sent.push(norm(sql));
        const failure = Object.entries(failures).find(([needle]) => norm(sql).includes(needle));
        if (failure && failure[1].length > 0) {
          const code = failure[1].shift();
          throw Object.assign(new Error(`sahte ${code}`), { code });
        }
        return ok();
      },
    };
  }

  it('her şey varsa hiçbir DDL / kilit ayarı gönderilmez (normal açılış)', async () => {
    const client = fakeClient({ done: WORK_EQUIPMENT_STEP_IDS });
    assert.deepEqual(await ensureWorkEquipmentSchema(client), []);
    assert.deepEqual(client.sent, []);
  });

  it('eksik adımlar sırayla ve kendi ifadeleriyle uygulanır; lock_timeout ayarlanıp sıfırlanır', async () => {
    const client = fakeClient({ done: ['items:equipment_column', 'items:equipment_fk', 'items:equipment_index'] });
    assert.deepEqual(await ensureWorkEquipmentSchema(client), ['attachments:phase_column', 'attachments:phase_check', 'events:type_check']);
    assert.equal(client.sent[0], "SET lock_timeout = '2s'");
    assert.equal(client.sent.at(-1), 'RESET lock_timeout');
    assert.equal(client.sent.length, 5);
    const everything = await ensureWorkEquipmentSchema(fakeClient());
    assert.deepEqual(everything, WORK_EQUIPMENT_STEP_IDS);
  });

  it('dayanılan tablo yoksa yalnız o adım atlanır (ekipman tablosu yokken FK adımı); hata açılışı durdurmaz', async () => {
    const client = fakeClient({ missingTables: ['equipment_items'] });
    const applied = await ensureWorkEquipmentSchema(client);
    assert.ok(!applied.includes('items:equipment_fk'));
    assert.deepEqual(applied, WORK_EQUIPMENT_STEP_IDS.filter((id) => id !== 'items:equipment_fk'));
    const none = await ensureWorkEquipmentSchema(fakeClient({ missingTables: ['work_items', 'work_item_attachments', 'work_item_events', 'equipment_items'] }));
    assert.deepEqual(none, []);
  });

  it('55P03 / 40P01\'de adım yeniden denenir (en çok 6); başka hata fırlatılır ve lock_timeout yine sıfırlanır', async () => {
    const retry = fakeClient({ done: WORK_EQUIPMENT_STEP_IDS.filter((id) => id !== 'items:equipment_index'), failures: { 'CREATE INDEX': ['55P03', '40P01'] } });
    assert.deepEqual(await ensureWorkEquipmentSchema(retry), ['items:equipment_index']);
    assert.equal(retry.sent.filter((sql) => sql.startsWith('CREATE INDEX')).length, 3);
    const fatal = fakeClient({ done: WORK_EQUIPMENT_STEP_IDS.filter((id) => id !== 'items:equipment_index'), failures: { 'CREATE INDEX': ['42501'] } });
    await assert.rejects(ensureWorkEquipmentSchema(fatal), { code: '42501' });
    assert.equal(fatal.sent.at(-1), 'RESET lock_timeout');
    const endless = fakeClient({ done: WORK_EQUIPMENT_STEP_IDS.filter((id) => id !== 'items:equipment_index'), failures: { 'CREATE INDEX': ['55P03', '55P03', '55P03', '55P03', '55P03', '55P03'] } });
    await assert.rejects(ensureWorkEquipmentSchema(endless), { code: '55P03' });
  });
});

// --- Girdi ve eşleyiciler ------------------------------------------------------------------------------------------------------------

describe('girdi doğrulama ve yanıt eşleyicileri', () => {
  it('PATCH equipment_id: pozitif tam sayı (metin olarak da) ya da null (bağı kaldırır); diğer her değer 400 INVALID_BODY', () => {
    assert.deepEqual(parsePatchInput({ equipment_id: 5 }), { equipmentId: 5 });
    assert.deepEqual(parsePatchInput({ equipment_id: '12' }), { equipmentId: 12 });
    assert.deepEqual(parsePatchInput({ equipment_id: null }), { equipmentId: null });
    assert.deepEqual(parsePatchInput({ equipment_id: 3, priority: 'acil' }), { priority: 'acil', equipmentId: 3 });
    for (const bad of [0, -1, 1.5, 'abc', '12abc', '', true, [], {}, 2 ** 60]) {
      assert.throws(() => parsePatchInput({ equipment_id: bad }), (error) => error.statusCode === 400 && error.code === 'INVALID_BODY', JSON.stringify(bad));
    }
    assert.throws(() => parsePatchInput({}), { code: 'INVALID_BODY' }, 'alan yok');
  });

  it('ek etiketi: before / after (büyük harf ve boşluk toleranslı), yok / null / boş = etiketsiz; başka değer 400 INVALID_BODY; sonuçta phase yalnız etiket varsa bulunur', () => {
    assert.equal(parseAttachmentPhase(undefined), null);
    assert.equal(parseAttachmentPhase(null), null);
    assert.equal(parseAttachmentPhase(''), null);
    assert.equal(parseAttachmentPhase(' BEFORE '), 'before');
    assert.equal(parseAttachmentPhase('after'), 'after');
    for (const bad of ['during', 'once', 5, true, {}, []]) {
      assert.throws(() => parseAttachmentPhase(bad), (error) => error.statusCode === 400 && error.code === 'INVALID_BODY', JSON.stringify(bad));
    }
    const base = { file_name: 'a.jpg', mime_type: 'image/jpeg', size_bytes: 10 };
    assert.deepEqual(parseAttachmentInput(base), { fileName: 'a.jpg', mimeType: 'image/jpeg', sizeBytes: 10 });
    assert.deepEqual(parseAttachmentInput({ ...base, phase: 'after' }), { fileName: 'a.jpg', mimeType: 'image/jpeg', sizeBytes: 10, phase: 'after' });
    assert.deepEqual(parseAttachmentInput({ ...base, phase: null }), { fileName: 'a.jpg', mimeType: 'image/jpeg', sizeBytes: 10 });
    assert.throws(() => parseAttachmentInput({ ...base, phase: 'bogus' }), { code: 'INVALID_BODY' });
  });

  it('mapAttachment phase: geçerli etiket aynen, eski kayıt (sütun yok / boş) ve bilinmeyen değer null', () => {
    const row = { id: '7', work_item_id: '5', file_name: 'a.jpg', mime_type: 'image/jpeg', size_bytes: '1', status: 'ready', uploaded_by: 12, uploaded_by_name: 'Ada', uploaded_by_resident: true };
    assert.equal(mapAttachment({ ...row, phase: 'before' }).phase, 'before');
    assert.equal(mapAttachment({ ...row, phase: 'after' }, { residentView: true }).phase, 'after', 'sakin görünümünde de etiket görünür');
    assert.equal(mapAttachment(row).phase, null);
    assert.equal(mapAttachment({ ...row, phase: null }).phase, null);
    assert.equal(mapAttachment({ ...row, phase: 'x' }).phase, null);
  });

  it('mapManagerItem equipment: bağlıysa { id, name, kind, is_active }, değilse null; silinmiş sütun / eski satır null', () => {
    const base = { id: '1', site_code: '1000000001', category: 'ariza', location_type: 'ortak_alan', title: 'T', description: 'D', status: 'yeni', priority: 'normal', resident_urgent: false, created_by: 1, requester_name: 'A' };
    assert.equal(mapManagerItem(base, { kind: 'manager' }).equipment, null);
    assert.equal(mapManagerItem({ ...base, equipment_id: null }, { kind: 'manager' }).equipment, null);
    assert.deepEqual(mapManagerItem({ ...base, equipment_id: '9', equipment_name: 'Asansör A', equipment_kind: 'asansor', equipment_active: true }, { kind: 'manager' }).equipment, { id: 9, name: 'Asansör A', kind: 'asansor', is_active: true });
    assert.equal(mapManagerItem({ ...base, equipment_id: '9', equipment_name: 'Eski', equipment_kind: 'kazan', equipment_active: false }, { kind: 'board' }).equipment.is_active, false);
  });

  it('mapEvent equipment_changed: yönetim görünümünde ad etiketleri (silinmişte "Silinmiş ekipman"), boş taraf null; sade görünümde etiket yok', () => {
    const row = { id: '3', event_type: 'equipment_changed', visibility: 'internal', actor_kind: 'manager', actor_user_code: 1, actor_name: 'Y', from_value: '4', to_value: '9', created_at: new Date('2026-01-01T00:00:00Z') };
    const equipmentLabels = new Map([['4', 'Asansör A'], ['9', 'Hidrofor']]);
    const detailed = mapEvent(row, { detailed: true, equipmentLabels });
    assert.deepEqual([detailed.type, detailed.from, detailed.to, detailed.from_label, detailed.to_label], ['equipment_changed', '4', '9', 'Asansör A', 'Hidrofor']);
    assert.equal(mapEvent({ ...row, from_value: null }, { detailed: true, equipmentLabels }).from_label, null);
    assert.equal(mapEvent({ ...row, to_value: '77' }, { detailed: true, equipmentLabels }).to_label, DELETED_EQUIPMENT_LABEL);
    assert.equal('from_label' in mapEvent(row, { detailed: false, equipmentLabels }), false);
  });

  it('mapHistoryItem: talep eden bilgisi yok, sayılar tam sayı, tarihler ISO', () => {
    const mapped = mapHistoryItem({ id: '8', title: 'Kapı', category: 'ariza', status: 'cozuldu', priority: 'acil', created_at: new Date('2026-01-01T00:00:00Z'), updated_at: new Date('2026-01-02T00:00:00Z'), closed_at: null, resolved_at: new Date('2026-01-02T00:00:00Z'), attachment_count: 3, before_count: '1', after_count: 1, created_by: 5, requester_name: 'X' });
    assert.deepEqual(mapped, { id: 8, title: 'Kapı', category: 'ariza', status: 'cozuldu', priority: 'acil', created_at: '2026-01-01T00:00:00.000Z', updated_at: '2026-01-02T00:00:00.000Z', closed_at: null, resolved_at: '2026-01-02T00:00:00.000Z', attachment_count: 3, before_count: 1, after_count: 1 });
  });
});

// --- Servis: ekipman bağını yazma ----------------------------------------------------------------------------------------------

describe('PATCH ekipman bağı (sahte işlem)', () => {
  let state;
  let log;

  beforeEach(() => {
    log = [];
    state = { status: 'islemde', equipmentId: null, equipment: new Map([[5, { id: 5, name: 'Asansör A', kind: 'asansor', is_active: true, site_code: SITE }], [6, { id: 6, name: 'Eski kazan', kind: 'kazan', is_active: false, site_code: SITE }], [7, { id: 7, name: 'Başka site', kind: 'asansor', is_active: true, site_code: OTHER_SITE }]]) };
    const run = async (text, params = []) => {
      const sql = norm(text);
      log.push({ sql, params });
      if (/^SELECT site_code FROM sites WHERE site_code = \$1 FOR KEY SHARE$/.test(sql)) return ok([{ site_code: String(params[0]) }]);
      if (/^SELECT user_code FROM users WHERE user_code = \$1 AND deleted_at IS NULL FOR KEY SHARE$/.test(sql)) return ok([{ user_code: params[0] }]);
      if (/^SELECT w\.id, w\.status, w\.priority, w\.assigned_to, w\.equipment_id, /.test(sql) && /FOR UPDATE OF w$/.test(sql)) {
        return ok([{ id: '5', status: state.status, priority: 'normal', assigned_to: null, equipment_id: state.equipmentId, due_date: null }]);
      }
      if (/^SELECT id, is_active FROM equipment_items WHERE id = \$1 AND site_code = \$2 FOR KEY SHARE$/.test(sql)) {
        const row = state.equipment.get(Number(params[0]));
        return ok(row && row.site_code === Number(params[1]) ? [{ id: String(row.id), is_active: row.is_active }] : []);
      }
      if (/^UPDATE work_items SET /.test(sql)) {
        const match = /equipment_id = \$(\d+)/.exec(sql);
        if (match) state.equipmentId = params[Number(match[1]) - 1];
        return ok();
      }
      if (/^INSERT INTO work_item_events/.test(sql)) return ok([{ id: '901' }]);
      if (/^(BEGIN|COMMIT|ROLLBACK|SAVEPOINT audit_insert|RELEASE SAVEPOINT audit_insert)$/.test(sql)) return ok();
      if (/^INSERT INTO audit_log/.test(sql)) return ok();
      // getWorkItemDetail (havuz)
      if (/^SELECT w\.id, w\.site_code, w\.category, .* FROM work_items w LEFT JOIN apartments a/.test(sql)) {
        const eq = state.equipmentId === null ? null : state.equipment.get(state.equipmentId);
        return ok([{ id: '5', site_code: String(SITE), category: 'ariza', location_type: 'ortak_alan', title: 'Kapı', description: 'D', status: state.status, priority: 'normal', resident_urgent: false, created_by: 4001, requester_name: 'Ayşe', equipment_id: eq ? String(eq.id) : null, equipment_name: eq?.name ?? null, equipment_kind: eq?.kind ?? null, equipment_active: eq?.is_active ?? null, created_at: new Date('2026-01-01T00:00:00Z'), updated_at: new Date('2026-01-01T00:00:00Z'), attachment_count: 0 }]);
      }
      if (/^SELECT e\.id, e\.event_type, e\.visibility, /.test(sql)) {
        const events = log.filter((entry) => /^INSERT INTO work_item_events/.test(entry.sql)).map((entry, index) => ({ id: String(901 + index), event_type: entry.params[2], visibility: entry.params[3], actor_user_code: entry.params[4], actor_kind: entry.params[5], from_value: entry.params[6], to_value: entry.params[7], body: null, created_at: new Date('2026-01-02T00:00:00Z'), actor_name: 'Yönetici' }));
        return ok(events.reverse());
      }
      if (/^SELECT id, name FROM equipment_items WHERE id = ANY\(\$1::BIGINT\[\]\) AND site_code = \$2$/.test(sql)) {
        return ok([...state.equipment.values()].filter((row) => params[0].includes(row.id) && row.site_code === Number(params[1])).map((row) => ({ id: String(row.id), name: row.name })));
      }
      if (/^SELECT a\.id, a\.work_item_id/.test(sql)) return ok();
      throw new Error(`BEKLENMEYEN SQL (sahte DB katı): ${sql.slice(0, 220)}`);
    };
    pool.connect = async () => ({ query: (text, params) => run(text, params), release() {} });
    pool.query = async (text, params) => run(text, params);
  });
  after(() => {
    delete pool.query;
    delete pool.connect;
  });

  const actor = { user_code: 20001, role: 'site_manager', full_name: 'Yönetici' };
  const manager = { kind: 'manager', userCode: 20001, siteCode: SITE, canManage: true };
  const staff = { kind: 'staff', userCode: 20005, siteCode: SITE, canManage: false };
  const board = { kind: 'board', userCode: 20006, siteCode: SITE, canManage: false };
  const patch = (body, access = manager) => updateWorkItem({ siteCode: SITE, rawId: '5', actor, access, body });
  const sqls = () => log.map((entry) => entry.sql);
  const audits = () => log.filter((entry) => /^INSERT INTO audit_log/.test(entry.sql)).map((entry) => ({ action: entry.params[3], targetType: entry.params[5], targetId: entry.params[6], details: JSON.parse(entry.params[7]) }));
  const eventInserts = () => log.filter((entry) => /^INSERT INTO work_item_events/.test(entry.sql));

  it('ekipman bağlanır: ekipman doğrulanır (aynı site, aktif), UPDATE equipment_id yazar, iç olay + denetim yazılır; yanıt ekipmanı ve olay etiketlerini taşır', async () => {
    const detail = await patch({ equipment_id: 5 });
    const update = log.find((entry) => /^UPDATE work_items SET /.test(entry.sql));
    assert.ok(update, 'UPDATE gitti');
    assert.match(update.sql, /equipment_id = \$3/);
    assert.equal(update.params[2], 5);
    assert.doesNotMatch(update.sql, /resident_updated_at/, 'ekipman bağı sakinin okunmamış işaretini tetiklemez');
    const lookup = log.find((entry) => /FROM equipment_items WHERE id = \$1 AND site_code = \$2 FOR KEY SHARE/.test(entry.sql));
    assert.deepEqual(lookup.params, [5, SITE], 'ekipman site kapsamıyla aranır');
    const order = (pattern) => log.findIndex((entry) => pattern.test(entry.sql));
    assert.ok(order(/FOR UPDATE OF w$/) < order(/FROM equipment_items WHERE id = \$1/) && order(/FROM equipment_items WHERE id = \$1/) < order(/^UPDATE work_items/), 'kilit sırası: talep -> ekipman -> yazma');
    const [event] = eventInserts();
    assert.deepEqual(event.params.slice(0, 8), [5, SITE, 'equipment_changed', 'internal', 20001, 'manager', null, '5']);
    assert.deepEqual(audits(), [{ action: 'work_item.updated', targetType: 'work_item', targetId: '5', details: { field: 'equipment', from: null, to: 5 } }]);
    assert.deepEqual(detail.item.equipment, { id: 5, name: 'Asansör A', kind: 'asansor', is_active: true });
    const eventInDetail = detail.events.find((e) => e.type === 'equipment_changed');
    assert.deepEqual([eventInDetail.from_label, eventInDetail.to_label, eventInDetail.visibility], [null, 'Asansör A', 'internal']);
  });

  it('değişiklik yoksa (aynı ekipman) hiçbir şey yazılmaz: ekipman aranmaz, UPDATE / olay / denetim yok', async () => {
    state.equipmentId = 5;
    const detail = await patch({ equipment_id: 5 });
    assert.ok(!sqls().some((sql) => /^UPDATE work_items/.test(sql) || /^INSERT INTO work_item_events/.test(sql) || /^INSERT INTO audit_log/.test(sql) || /FROM equipment_items WHERE id = \$1 AND site_code/.test(sql)));
    assert.equal(detail.item.equipment.id, 5);
  });

  it('bağ kaldırma (null): ekipman aranmaz, olay to = null, ekipman değişince eski ekipman from olur', async () => {
    state.equipmentId = 5;
    const cleared = await patch({ equipment_id: null });
    assert.ok(!sqls().some((sql) => /FROM equipment_items WHERE id = \$1 AND site_code/.test(sql)));
    const [clearEvent] = eventInserts();
    assert.deepEqual(clearEvent.params.slice(2, 8), ['equipment_changed', 'internal', 20001, 'manager', '5', null]);
    assert.equal(cleared.item.equipment, null);
    assert.deepEqual(audits().at(-1).details, { field: 'equipment', from: 5, to: null });
    log.length = 0;
    state.equipmentId = 5;
    state.equipment.set(8, { id: 8, name: 'Hidrofor', kind: 'hidrofor', is_active: true, site_code: SITE });
    await patch({ equipment_id: 8 });
    assert.deepEqual(eventInserts()[0].params.slice(6, 8), ['5', '8']);
  });

  it('başka sitenin / olmayan / pasif ekipmanı 400 INVALID_EQUIPMENT; işlem geri alınır, UPDATE ve olay yok', async () => {
    for (const [id, message] of [[7, /bu siteye ait değil/], [999, /bu siteye ait değil/], [6, /Pasif ekipman/]]) {
      log.length = 0;
      await assert.rejects(patch({ equipment_id: id }), (error) => error.statusCode === 400 && error.code === 'INVALID_EQUIPMENT' && message.test(error.message), `ekipman ${id}`);
      assert.ok(sqls().includes('ROLLBACK'));
      assert.ok(!sqls().some((sql) => /^UPDATE work_items|^INSERT INTO work_item_events|^INSERT INTO audit_log/.test(sql)));
    }
    assert.equal(state.equipmentId, null);
  });

  it('kapanmış / iptal talepte ekipman değişmez (409 WORK_ITEM_CLOSED, ekipman aranmaz); aynı değer yine sessiz 200', async () => {
    state.status = 'kapandi';
    await assert.rejects(patch({ equipment_id: 5 }), { statusCode: 409, code: 'WORK_ITEM_CLOSED' });
    assert.ok(!sqls().some((sql) => /FROM equipment_items WHERE id = \$1 AND site_code/.test(sql)));
    log.length = 0;
    state.equipmentId = 5;
    const same = await patch({ equipment_id: 5 });
    assert.equal(same.item.equipment.id, 5);
  });

  it('durum + ekipman birlikte: her alan ayrı olay / denetim yazar; görevli de bağlayabilir (kapsam sorgunun içinde)', async () => {
    const detail = await patch({ status: 'cozuldu', equipment_id: 5 }, staff);
    assert.deepEqual(eventInserts().map((entry) => entry.params[2]), ['status_changed', 'equipment_changed']);
    assert.deepEqual(audits().map((entry) => entry.action), ['work_item.status_changed', 'work_item.updated']);
    const forUpdate = log.find((entry) => /FOR UPDATE OF w$/.test(entry.sql));
    assert.match(forUpdate.sql, /w\.assigned_to IS NULL OR w\.assigned_to = \$3/, 'görevli kapsamı kilit sorgusunda');
    assert.equal(detail.item.equipment.id, 5);
    assert.equal(eventInserts()[1].params[5], 'staff');
  });

  it('kurul yazamaz (403 FORBIDDEN_ROLE) ve veritabanına hiç gidilmez', async () => {
    await assert.rejects(patch({ equipment_id: 5 }, board), { statusCode: 403, code: 'FORBIDDEN_ROLE' });
    assert.deepEqual(log, []);
  });

  it('geçersiz gövde veritabanına gitmeden 400 döner', async () => {
    await assert.rejects(patch({ equipment_id: 'abc' }), { statusCode: 400, code: 'INVALID_BODY' });
    assert.deepEqual(log, []);
  });
});

// --- Fotoğraf eki: etiket ve dosya kimliği izi ------------------------------------------------------------------------------------

describe('fotoğraf etiketi (sahte işlem)', () => {
  let log;
  beforeEach(() => {
    log = [];
    const run = async (text, params = []) => {
      const sql = norm(text);
      log.push({ sql, params });
      if (/^SELECT site_code FROM sites WHERE site_code = \$1 FOR KEY SHARE$/.test(sql)) return ok([{ site_code: String(params[0]) }]);
      if (/^SELECT user_code FROM users WHERE user_code = \$1 AND deleted_at IS NULL FOR KEY SHARE$/.test(sql)) return ok([{ user_code: params[0] }]);
      if (/^SELECT w\.id, w\.site_code, w\.status FROM work_items w WHERE .* FOR UPDATE OF w$/.test(sql)) return ok([{ id: '5', site_code: String(SITE), status: 'islemde' }]);
      if (/^SELECT COUNT\(\*\)::INTEGER AS n FROM work_item_attachments/.test(sql)) return ok([{ n: 0 }]);
      if (/^SELECT COALESCE\(SUM\(a\.size_bytes\)/.test(sql)) return ok([{ used: '0' }]);
      if (/^INSERT INTO work_item_attachments/.test(sql)) return ok([{ id: '77' }]);
      if (/^SELECT id, status, storage_key, mime_type, size_bytes, \(created_at/.test(sql)) return ok([{ id: '77', status: 'uploading', storage_key: 'k', mime_type: 'image/jpeg', size_bytes: '100', expired: false }]);
      if (/^UPDATE work_item_attachments SET status = 'ready'/.test(sql)) return ok();
      if (/^UPDATE work_items SET updated_at/.test(sql)) return ok();
      if (/^INSERT INTO work_item_events/.test(sql)) return ok([{ id: '901' }]);
      if (/^(BEGIN|COMMIT|ROLLBACK|SAVEPOINT audit_insert|RELEASE SAVEPOINT audit_insert)$/.test(sql)) return ok();
      if (/^INSERT INTO audit_log/.test(sql)) return ok();
      if (/^SELECT pg_advisory_xact_lock/.test(sql)) return ok();
      if (/^SELECT a\.id, a\.work_item_id/.test(sql)) {
        return ok([{ id: '77', work_item_id: '5', site_code: String(SITE), uploaded_by: 20001, file_name: 'f.jpg', mime_type: 'image/jpeg', size_bytes: '100', status: 'ready', phase: 'after', uploaded_by_name: 'Y', uploaded_by_resident: false, created_at: new Date(), ready_at: new Date() }]);
      }
      throw new Error(`BEKLENMEYEN SQL (sahte DB katı): ${sql.slice(0, 220)}`);
    };
    pool.connect = async () => ({ query: (text, params) => run(text, params), release() {} });
    pool.query = async (text, params) => run(text, params);
  });
  after(() => {
    delete pool.query;
    delete pool.connect;
  });

  const actor = { user_code: 20001, role: 'site_manager' };
  const scope = managerScope({ kind: 'manager', userCode: 20001, siteCode: SITE, canManage: true });
  const BODY = { file_name: 'f.jpg', mime_type: 'image/jpeg', size_bytes: 100 };

  it('kayıt açılırken etiket INSERT\'e gider (etiketsizse null) ve yanıt etiketi taşır', async () => {
    await createAttachment({ scope, rawId: '5', actor, body: { ...BODY, phase: 'before' } });
    const insert = log.find((entry) => /^INSERT INTO work_item_attachments/.test(entry.sql));
    assert.match(insert.sql, /\(work_item_id, site_code, uploaded_by, file_name, mime_type, size_bytes, status, storage_key, phase\)/);
    assert.equal(insert.params.at(-1), 'before');
    log.length = 0;
    const plain = await createAttachment({ scope, rawId: '5', actor, body: BODY });
    assert.equal(log.find((entry) => /^INSERT INTO work_item_attachments/.test(entry.sql)).params.at(-1), null);
    assert.ok('phase' in plain.attachment);
  });

  it('geçersiz etiket 400 INVALID_BODY: veritabanına hiç gidilmez', async () => {
    await assert.rejects(createAttachment({ scope, rawId: '5', actor, body: { ...BODY, phase: 'sonra' } }), { statusCode: 400, code: 'INVALID_BODY' });
    assert.deepEqual(log, []);
  });

  it('yükleme tamamlanınca olay etiketi (from) + ek no (to), denetim ek no / etiket / sha256 taşır; dosya adı yazılmaz', async () => {
    const sha = 'a'.repeat(64);
    const target = { attId: 77, itemId: 5, siteCode: SITE, storageKey: 'k', sizeBytes: 100, mimeType: 'image/jpeg', fileName: 'gizli-ad.jpg', phase: 'after' };
    await completeAttachmentUpload({ scope, target, actor, sha256: sha });
    const event = log.find((entry) => /^INSERT INTO work_item_events/.test(entry.sql));
    assert.deepEqual(event.params.slice(2, 9), ['attachment_added', 'public', 20001, 'manager', 'after', '77', null]);
    const audit = log.find((entry) => /^INSERT INTO audit_log/.test(entry.sql));
    assert.equal(audit.params[3], 'work_item.attachment_added');
    assert.equal(audit.params[5], 'work_item');
    assert.equal(audit.params[6], '5', 'kaynak iş kaydı kimliği denetim hedefidir');
    assert.deepEqual(JSON.parse(audit.params[7]), { attachment_id: 77, mime_type: 'image/jpeg', size_bytes: 100, by: 'management', phase: 'after', sha256: sha });
    assert.ok(!audit.params[7].includes('gizli-ad'), 'dosya adı yazılmaz');
    log.length = 0;
    await completeAttachmentUpload({ scope, target: { ...target, phase: null }, actor, sha256: sha });
    assert.equal(log.find((entry) => /^INSERT INTO work_item_events/.test(entry.sql)).params[6], null, 'etiketsiz ek: from null (eski olaylarla aynı)');
  });
});

// --- Servis geçmişi --------------------------------------------------------------------------------------------------------------

function historyDb({ equipment = { id: '5', kind: 'asansor', name: 'Asansör A', is_active: true }, moduleEnabled = true, rows = [], totals = { total: 0, open: 0 } } = {}) {
  const calls = [];
  return {
    calls,
    async query(text, params = []) {
      const sql = norm(text);
      calls.push({ sql, params });
      if (/^SELECT id, kind, name, is_active FROM equipment_items WHERE id = \$1 AND site_code = \$2$/.test(sql)) {
        return ok(equipment && Number(params[0]) === Number(equipment.id) && Number(params[1]) === SITE ? [equipment] : []);
      }
      if (/^SELECT enabled FROM site_modules WHERE site_code = \$1 AND module_code = \$2 LIMIT 1$/.test(sql)) return ok(params[1] === 'work_tracking' ? [{ enabled: moduleEnabled }] : []);
      if (/^SELECT w\.id, w\.title, w\.category, w\.status/.test(sql)) return ok(rows);
      if (/^SELECT COUNT\(\*\)::INTEGER AS total/.test(sql)) return ok([totals]);
      throw new Error(`BEKLENMEYEN SQL (sahte DB katı): ${sql.slice(0, 220)}`);
    },
  };
}

const historyRow = (id, extra = {}) => ({ id: String(id), title: `İş ${id}`, category: 'ariza', status: 'cozuldu', priority: 'normal', created_at: new Date('2026-01-01T00:00:00Z'), updated_at: new Date('2026-01-02T00:00:00Z'), closed_at: null, resolved_at: new Date('2026-01-02T00:00:00Z'), attachment_count: 2, before_count: 1, after_count: 1, ...extra });

describe('servis geçmişi (listEquipmentWorkHistory)', () => {
  const manager = { kind: 'manager', userCode: 20001 };
  const call = (db, overrides = {}) => listEquipmentWorkHistory({ siteCode: SITE, rawEquipmentId: '5', query: {}, access: manager, ...overrides }, db);

  it('ekipmanın bağlı işleri id azalan; sayfalama limit + 1 ile (next_before_id), sayaçlar kapsamla; sorgular site + ekipman kapsamlı', async () => {
    const db = historyDb({ rows: [historyRow(30), historyRow(20), historyRow(10)], totals: { total: 3, open: 1 } });
    const page = await call(db, { query: { limit: '2' } });
    assert.equal(page.work_tracking_enabled, true);
    assert.deepEqual(page.equipment, { id: 5, kind: 'asansor', name: 'Asansör A', is_active: true });
    assert.deepEqual(page.items.map((item) => item.id), [30, 20]);
    assert.equal(page.next_before_id, 20);
    assert.deepEqual(page.counts, { total: 3, open: 1 });
    const list = db.calls.find((entry) => /^SELECT w\.id, w\.title/.test(entry.sql));
    assert.match(list.sql, /WHERE w\.site_code = \$1 AND w\.equipment_id = \$2 ORDER BY w\.id DESC LIMIT \$3$/);
    assert.deepEqual(list.params, [SITE, 5, 3]);
    assert.doesNotMatch(list.sql, /staff|assigned_to/, 'yönetici kapsamı yok');
    assert.ok(!/created_by|requester|phone/.test(list.sql), 'talep eden bilgisi sorgulanmaz');
  });

  it('son sayfada next_before_id null; before_id imleci SQL\'e gider', async () => {
    const db = historyDb({ rows: [historyRow(10)] });
    const page = await call(db, { query: { before_id: '20', limit: '5' } });
    assert.equal(page.next_before_id, null);
    const list = db.calls.find((entry) => /^SELECT w\.id, w\.title/.test(entry.sql));
    assert.match(list.sql, /AND w\.id < \$3 ORDER BY w\.id DESC LIMIT \$4$/);
    assert.deepEqual(list.params, [SITE, 5, 20, 6]);
  });

  it('görevli yalnız kendine atanmış / atanmamış / yetim atamalı işleri görür (kapsam hem liste hem sayaçta)', async () => {
    const db = historyDb({ rows: [historyRow(10)], totals: { total: 1, open: 0 } });
    await call(db, { access: { kind: 'staff', userCode: 20005 } });
    for (const entry of db.calls.filter((c) => /FROM work_items w/.test(c.sql))) {
      assert.match(entry.sql, /\(w\.assigned_to IS NULL OR w\.assigned_to = \$3 OR NOT EXISTS/, entry.sql.slice(0, 80));
      assert.equal(entry.params[2], 20005);
    }
  });

  it('kurul ve süper de okur (kapsam yok); bilinmeyen / başka site / geçersiz kimlikli ekipman 404 NOT_FOUND', async () => {
    for (const kind of ['board', 'super']) {
      const db = historyDb({ rows: [historyRow(10)] });
      const page = await call(db, { access: { kind, userCode: 1 } });
      assert.equal(page.items.length, 1);
      assert.doesNotMatch(db.calls.find((entry) => /^SELECT w\.id, w\.title/.test(entry.sql)).sql, /assigned_to/);
    }
    for (const rawEquipmentId of ['999', 'abc', '0', '-3', '5; DROP TABLE x']) {
      await assert.rejects(call(historyDb(), { rawEquipmentId }), (error) => error.statusCode === 404 && error.code === 'NOT_FOUND', rawEquipmentId);
    }
    await assert.rejects(call(historyDb({ equipment: null })), { statusCode: 404, code: 'NOT_FOUND' });
  });

  it('iş takibi modülü kapalıysa 403 değil boş liste + work_tracking_enabled=false (iş tablosuna hiç gidilmez)', async () => {
    const db = historyDb({ moduleEnabled: false });
    const page = await call(db);
    assert.deepEqual([page.work_tracking_enabled, page.items, page.next_before_id, page.counts], [false, [], null, { total: 0, open: 0 }]);
    assert.equal(page.equipment.name, 'Asansör A');
    assert.ok(!db.calls.some((entry) => /FROM work_items/.test(entry.sql)));
  });

  it('geçersiz sayfalama 400 INVALID_QUERY (veritabanına gitmeden)', async () => {
    for (const query of [{ before_id: 'x' }, { limit: '0' }, { limit: 'abc' }]) {
      const db = historyDb();
      await assert.rejects(call(db, { query }), { statusCode: 400, code: 'INVALID_QUERY' }, JSON.stringify(query));
      assert.deepEqual(db.calls, []);
    }
  });
});

// --- HTTP: rota ve yetki kapıları ---------------------------------------------------------------------------------------------------

describe('GET /manager/sites/:siteCode/equipment/:id/work-history (HTTP)', () => {
  const mk = (id, role) => ({ id, user_code: id, userCode: id, role, full_name: `K${id}`, email: `u${id}@example.com` });
  const users = {
    superUser: mk(1, 'super_user'),
    manager: mk(20001, 'site_manager'),
    otherManager: mk(20002, 'site_manager'),
    resident: mk(20004, 'apartment_owner'),
    staff: mk(20005, 'individual'),
    board: mk(20006, 'individual'),
    outsider: mk(20008, 'individual'),
  };
  let server;
  let baseUrl;
  let state;
  let log;

  function fakeQuery(text, params = []) {
    const sql = norm(text);
    log.push({ sql, params });
    if (/^SELECT 1 FROM site_manager_sites WHERE site_code = \$1 AND manager_user_code = \$2 LIMIT 1$/.test(sql)) {
      return ok([{ site_code: SITE, manager_user_code: 20001 }].filter((l) => l.site_code === Number(params[0]) && l.manager_user_code === Number(params[1])).map(() => ({ x: 1 })));
    }
    if (/^SELECT 1 FROM site_memberships WHERE site_code = \$1 AND user_code = \$2 AND role IN \('SITE_OWNER', 'SITE_ADMIN'\) AND is_active = TRUE LIMIT 1$/.test(sql)) return ok();
    if (/^SELECT EXISTS \( SELECT 1 FROM site_memberships WHERE site_code = \$1 AND user_code = \$2 AND role = 'BOARD_MEMBER'/.test(sql)) {
      const board = Number(params[1]) === 20006 && Number(params[0]) === SITE;
      const otherRole = [20002, 20006].includes(Number(params[1]));
      return ok([{ is_board_here: board, is_member_here: board, has_other_role: otherRole }]);
    }
    if (/^SELECT 1 FROM site_memberships WHERE site_code = \$1 AND user_code = \$2 AND role = 'STAFF' AND is_active = TRUE LIMIT 1$/.test(sql)) {
      return ok(Number(params[1]) === 20005 && Number(params[0]) === SITE ? [{ x: 1 }] : []);
    }
    if (/^SELECT site_code FROM sites WHERE site_code = \$1 LIMIT 1$/.test(sql)) return ok(Number(params[0]) === SITE ? [{ site_code: String(SITE) }] : []);
    if (/^SELECT enabled FROM site_modules WHERE site_code = \$1 AND module_code = \$2 LIMIT 1$/.test(sql)) return ok(params[1] === 'work_tracking' ? [{ enabled: state.workModule }] : []);
    if (/^SELECT id, kind, name, is_active FROM equipment_items WHERE id = \$1 AND site_code = \$2$/.test(sql)) {
      return ok(Number(params[0]) === 5 && Number(params[1]) === SITE ? [{ id: '5', kind: 'asansor', name: 'Asansör A', is_active: true }] : []);
    }
    if (/^SELECT w\.id, w\.title, w\.category, w\.status/.test(sql)) return ok(state.rows);
    if (/^SELECT COUNT\(\*\)::INTEGER AS total/.test(sql)) return ok([{ total: state.rows.length, open: 0 }]);
    throw new Error(`BEKLENMEYEN SQL (sahte DB katı): ${sql.slice(0, 200)}`);
  }

  const ORIGINAL = equipmentRouter.stack.filter((layer) => layer.route).map((layer) => ({ path: layer.route.path, method: Object.keys(layer.route.methods)[0], handlers: layer.route.stack.map((entry) => entry.handle) }));

  before(async () => {
    for (const layer of equipmentRouter.stack) {
      if (!layer.route) continue;
      layer.route.stack[0].handle = (req, _res, next) => {
        req.authUser = JSON.parse(decodeURIComponent(req.headers['x-test-user']));
        next();
      };
      layer.route.stack[1].handle = (_req, _res, next) => next();
    }
    const app = express();
    app.use(express.json({ limit: '1mb' }));
    app.use(equipmentRouter);
    await new Promise((resolve) => {
      server = app.listen(0, '127.0.0.1', resolve);
    });
    baseUrl = `http://127.0.0.1:${server.address().port}`;
  });
  after(async () => {
    server.closeAllConnections?.();
    await new Promise((resolve) => server.close(resolve));
    delete pool.query;
    delete pool.connect;
  });
  beforeEach(() => {
    state = { workModule: true, rows: [historyRow(30), historyRow(20)] };
    log = [];
    pool.query = async (text, params) => fakeQuery(text, params);
    pool.connect = async () => {
      throw new Error('işlem açılmamalıydı (okuma ucu)');
    };
  });

  async function get(urlPath, user) {
    const res = await fetch(`${baseUrl}${urlPath}`, { headers: user ? { 'x-test-user': encodeURIComponent(JSON.stringify(user)) } : {} });
    let body = null;
    try {
      body = await res.json();
    } catch (_error) {
      // gövdesiz
    }
    return { status: res.status, body };
  }
  const url = (id = 5, site = SITE, query = '') => `/manager/sites/${site}/equipment/${id}/work-history${query}`;

  it('uç tanımlıdır: authRequired ile başlar, okuma sınırlayıcısı ikinci halka; /:id\'den sonra gelen ayrı yoldur', () => {
    const route = ORIGINAL.find((entry) => entry.path === '/manager/sites/:siteCode/equipment/:id/work-history');
    assert.ok(route, 'rota var');
    assert.equal(route.method, 'get');
    assert.equal(route.handlers[0], authRequired);
  });

  it('yönetici 200: ekipman + işler; yanıtta talep eden bilgisi yok', async () => {
    const res = await get(url(), users.manager);
    assert.equal(res.status, 200);
    assert.equal(res.body.equipment.name, 'Asansör A');
    assert.deepEqual(res.body.items.map((item) => item.id), [30, 20]);
    assert.ok(!JSON.stringify(res.body).includes('phone') && !JSON.stringify(res.body).includes('requester'));
  });

  it('süper, kurul ve görevli okur; sakin ve ilgisiz 403 FORBIDDEN_ROLE; başka sitenin yöneticisi 403 FORBIDDEN_SITE', async () => {
    for (const user of [users.superUser, users.board, users.staff]) {
      const res = await get(url(), user);
      assert.equal(res.status, 200, user.role + user.user_code);
    }
    for (const user of [users.resident, users.outsider]) {
      const res = await get(url(), user);
      assert.deepEqual([res.status, res.body.code], [403, 'FORBIDDEN_ROLE']);
    }
    const other = await get(url(), users.otherManager);
    assert.deepEqual([other.status, other.body.code], [403, 'FORBIDDEN_SITE']);
  });

  it('görevli için kapsam sorgusu uygulanır; kurul için uygulanmaz', async () => {
    await get(url(), users.staff);
    assert.ok(log.some((entry) => /FROM work_items w/.test(entry.sql) && /w\.assigned_to IS NULL OR w\.assigned_to = \$3/.test(entry.sql)));
    log.length = 0;
    await get(url(), users.board);
    assert.ok(!log.some((entry) => /w\.assigned_to/.test(entry.sql)));
  });

  it('site yok 404 SITE_NOT_FOUND; ekipman yok / geçersiz 404 NOT_FOUND; geçersiz imleç 400 INVALID_QUERY', async () => {
    assert.equal((await get(url(5, OTHER_SITE), users.superUser)).status, 404);
    for (const id of [999, 'abc']) {
      const res = await get(url(id), users.manager);
      assert.deepEqual([res.status, res.body.code], [404, 'NOT_FOUND'], String(id));
    }
    const bad = await get(url(5, SITE, '?before_id=x'), users.manager);
    assert.deepEqual([bad.status, bad.body.code], [400, 'INVALID_QUERY']);
  });

  it('iş takibi modülü kapalıyken 200 + boş liste + work_tracking_enabled=false (ekipman kartı bozulmaz)', async () => {
    state.workModule = false;
    const res = await get(url(), users.manager);
    assert.equal(res.status, 200);
    assert.deepEqual([res.body.work_tracking_enabled, res.body.items], [false, []]);
  });
});
