// İş Takibi fotoğraf ekleri (047; DB'siz): migration 047 <-> work_attachments_schema.js aynı DDL, ekleyici / idempotent, katalog kontrollü ensure, girdi doğrulama,
// içerik imzası kararı, depolama alt ağacı ilkelleri, rota zinciri (KATI sahte DB: yetki / doğrulama hataları veritabanına gitmeden döner), bakım turları
// (gerçek geçici dosya sistemi + katı sahte DB). Gerçek PostgreSQL doğrulaması (yarış, IDOR, yükleme akışı, silme / dışa aktarma): scripts/qa_platform_pg.mjs "work_tracking" K bölümü.
import { describe, it, before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import { EventEmitter } from 'node:events';
import express from 'express';
import http from 'node:http';
import { promises as fsp } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { DEFAULT_MIGRATIONS_DIR, findUnsafeStatements, listMigrations } from '../scripts/migrate.js';
import { pool } from '../src/db.js';
import { authRequired } from '../src/middlewares/auth_middleware.js';
import { EVENT_TYPES_WITH_ATTACHMENTS, WORK_ATTACHMENTS_DDL, WORK_ATTACHMENTS_DDL_ORDER, ensureWorkAttachmentsSchema, schemaTuning } from '../src/modules/work_attachments_schema.js';
import {
  ATTACHMENT_MAX_BYTES,
  ATTACHMENT_SUBTREE,
  ATTACHMENT_USER_QUOTA_WINDOW_DAYS,
  MANAGEMENT_UPLOADER_LABEL,
  MAX_ATTACHMENTS_PER_ITEM,
  MAX_IMAGE_PIXELS,
  MAX_IMAGE_SIDE,
  assertImageDimensions,
  assertImageHead,
  attachmentLimits,
  attachmentQuotaExceeded,
  attachmentsKeepNote,
  buildAttachmentFileName,
  detectImageMime,
  mapAttachment,
  parseAttachmentInput,
  readImageDimensions,
} from '../src/modules/work_attachments_common.js';
import { STORAGE_SUBTREES, checkStorage, ensureSiteDir, openStoredFile, pathForKey, removeStoredFile, resetStorageCheck } from '../src/modules/document_storage.js';
import { activeDownloadCount, contentDisposition, sendDocument } from '../src/modules/document_download.js';
import { attachmentSiteDirGuardTripped, runDocumentsMaintenanceOnce } from '../src/modules/document_maintenance.js';
import { workTrackingRouter } from '../src/modules/work_tracking_routes.js';
import { attachmentUploadState, flightKeyOf } from '../src/modules/work_attachments_upload.js';
import { createAttachment, deleteAttachment, managerScope, residentScope, siteAttachmentLockKey } from '../src/modules/work_attachments_service.js';

schemaTuning.retryDelayMs = 1;

const here = path.dirname(fileURLToPath(import.meta.url));
const MIGRATION = readFileSync(path.join(DEFAULT_MIGRATIONS_DIR, '047_work_attachments.sql'), 'utf8').replace(/\r\n/g, '\n');
const DB_SOURCE = readFileSync(path.join(here, '..', 'src', 'db.js'), 'utf8').replace(/\r\n/g, '\n');
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

const sql = (name) => normalizeSql(WORK_ATTACHMENTS_DDL[name]);
const FK_RE = /^DO \$\$ BEGIN IF NOT EXISTS \( SELECT 1 FROM pg_constraint WHERE conname = '(\w+_fkey)' AND conrelid = '(\w+)'::regclass \) THEN ALTER TABLE (\w+) ADD CONSTRAINT (\w+_fkey) FOREIGN KEY \((\w+)\) REFERENCES (\w+)\((\w+)\) ON DELETE (CASCADE|SET NULL); END IF; END \$\$$/;

describe('migration 047: iş takibi fotoğraf ekleri', () => {
  it('047 var, çalıştırıcı için güvenli (üst düzey BEGIN/COMMIT yok), numara yinelenmez', () => {
    const list = listMigrations(DEFAULT_MIGRATIONS_DIR);
    const entry = list.find((m) => m.number === 47);
    assert.ok(entry, '047 numaralı migration yok');
    assert.equal(entry.file, '047_work_attachments.sql');
    assert.equal(list.filter((m) => m.number === 47).length, 1);
    assert.deepEqual(findUnsafeStatements(MIGRATION), []);
  });

  it('WORK_ATTACHMENTS_DDL migration 047 ile AYNI ifadeleri taşır (yorumlar ve boşluklar dışında birebir, AYNI sırayla)', () => {
    const fromMigration = splitStatements(MIGRATION);
    assert.equal(fromMigration.length, 10);
    assert.deepEqual(fromMigration, WORK_ATTACHMENTS_DDL_ORDER.map((name) => normalizeSql(WORK_ATTACHMENTS_DDL[name])));
    assert.deepEqual(Object.keys(WORK_ATTACHMENTS_DDL), [...WORK_ATTACHMENTS_DDL_ORDER]);
  });

  it('EKLEMELİ ve idempotent: CREATE TABLE / INDEX IF NOT EXISTS, katalog korumalı FK; tek istisna olay türü CHECK kısıtının katalog korumalı genişletilmesi (DROP + ADD aynı DO içinde); DROP TABLE / UPDATE / DELETE / INSERT YOK', () => {
    const statements = splitStatements(MIGRATION);
    const widen = statements.filter((statement) => /chk_work_item_events_type/.test(statement));
    assert.equal(widen.length, 1);
    assert.match(
      widen[0],
      /^DO \$\$ BEGIN IF NOT EXISTS \( SELECT 1 FROM pg_constraint WHERE conname = 'chk_work_item_events_type' AND conrelid = 'work_item_events'::regclass AND pg_get_constraintdef\(oid\) LIKE '%attachment_added%' \) THEN ALTER TABLE work_item_events DROP CONSTRAINT IF EXISTS chk_work_item_events_type; ALTER TABLE work_item_events ADD CONSTRAINT chk_work_item_events_type CHECK \(event_type IN \('created', 'status_changed', 'assigned', 'priority_changed', 'due_date_changed', 'comment', 'attachment_added', 'attachment_removed'\)\); END IF; END \$\$$/,
    );
    for (const statement of statements) {
      if (statement === widen[0]) continue;
      assert.ok(/^CREATE (UNIQUE )?(TABLE|INDEX) IF NOT EXISTS /.test(statement) || FK_RE.test(statement), statement.slice(0, 120));
    }
    const all = normalizeSql(MIGRATION);
    assert.ok(!/\b(DROP TABLE|DROP INDEX|TRUNCATE|UPDATE|DELETE FROM|INSERT INTO)\b/i.test(all));
    assert.equal((all.match(/\bDROP\b/g) ?? []).length, 1, 'tek DROP: eski CHECK kısıtı (aynı DO içinde yenisi eklenir)');
    assert.deepEqual([...new Set(all.match(/ALTER TABLE (\w+)/g))].sort(), ['ALTER TABLE work_item_attachments', 'ALTER TABLE work_item_events']);
    assert.deepEqual(EVENT_TYPES_WITH_ATTACHMENTS.slice(-2), ['attachment_added', 'attachment_removed']);
  });

  it('AÇILIŞ 40P01 dersi: DDL dev blokta DEĞİL; db.js ensureWorkAttachmentsSchema(client) çağırır, iş takibi (042) ve rezervasyon (043) şemasından SONRA, people_v1\'den ÖNCE', () => {
    const normalizedDb = normalizeSql(DB_SOURCE);
    for (const name of WORK_ATTACHMENTS_DDL_ORDER) {
      assert.equal(normalizedDb.includes(normalizeSql(WORK_ATTACHMENTS_DDL[name])), false, `${name} db.js içinde olmamalı`);
    }
    assert.equal(/CREATE TABLE IF NOT EXISTS work_item_attachments\b/.test(DB_SOURCE), false);
    assert.match(DB_SOURCE, /import \{ ensureWorkAttachmentsSchema \} from '\.\/modules\/work_attachments_schema\.js';/);
    const calls = [...DB_SOURCE.matchAll(/await ensureWorkAttachmentsSchema\(client\);/g)];
    assert.equal(calls.length, 1);
    assert.ok(calls[0].index > DB_SOURCE.indexOf('await ensureWorkTrackingSchema(client);'));
    assert.ok(calls[0].index > DB_SOURCE.indexOf('await ensureReservationSchema(client);'));
    assert.ok(calls[0].index < DB_SOURCE.indexOf('await runPeopleBackfill(client);'));
  });

  it('work_item_attachments: sütunlar, CHECK kümeleri (ad 1-160, mime 3 tür, boyut 1..5 MB, durum, ready <-> ready_at, sha256 biçimi), varsayılan uploading; satır içi REFERENCES yok', () => {
    const table = sql('attachmentsTable');
    for (const fragment of [
      'id BIGSERIAL PRIMARY KEY',
      'work_item_id BIGINT NOT NULL',
      'site_code BIGINT NOT NULL',
      'uploaded_by INTEGER,',
      "status TEXT NOT NULL DEFAULT 'uploading'",
      'char_length(file_name) BETWEEN 1 AND 160',
      "mime_type IN ('image/jpeg', 'image/png', 'image/webp')",
      'size_bytes BETWEEN 1 AND 5242880',
      "status IN ('uploading', 'ready')",
      "(status = 'ready') = (ready_at IS NOT NULL)",
      "sha256 IS NULL OR sha256 ~ '^[0-9a-f]{64}$'",
    ]) {
      assert.ok(table.includes(fragment), fragment);
    }
    assert.ok(!/REFERENCES/i.test(table));
    assert.equal(ATTACHMENT_MAX_BYTES, 5242880);
    assert.equal(MAX_ATTACHMENTS_PER_ITEM, 4);
  });

  it("3 FK (talep CASCADE, site CASCADE, yükleyen SET NULL): ad <tablo>_<sütun>_fkey, katalog korumalı; tablodan HEMEN sonra, indekslerden ÖNCE; ifade başına tek sıcak üst tablo", () => {
    const fkSteps = WORK_ATTACHMENTS_DDL_ORDER.filter((name) => name.endsWith('Fk'));
    const parsed = fkSteps.map((name) => {
      const match = FK_RE.exec(sql(name));
      assert.ok(match, name);
      const [, guard, guardTable, table, constraint, column, parent, parentColumn, onDelete] = match;
      assert.equal(guard, constraint);
      assert.equal(guardTable, table);
      assert.equal(constraint, `${table}_${column}_fkey`);
      return [table, column, parent, parentColumn, onDelete];
    });
    assert.deepEqual(parsed, [
      ['work_item_attachments', 'work_item_id', 'work_items', 'id', 'CASCADE'],
      ['work_item_attachments', 'site_code', 'sites', 'site_code', 'CASCADE'],
      ['work_item_attachments', 'uploaded_by', 'users', 'user_code', 'SET NULL'],
    ]);
    const at = (name) => WORK_ATTACHMENTS_DDL_ORDER.indexOf(name);
    for (const fk of fkSteps) assert.ok(at('attachmentsTable') < at(fk) && at(fk) < at('attachmentsItemIndex'), fk);
    for (const name of WORK_ATTACHMENTS_DDL_ORDER) {
      const hot = new Set([...sql(name).matchAll(/REFERENCES (sites|users|work_items)\(/g)].map((match) => match[1]));
      assert.ok(hot.size <= 1, name);
    }
  });

  it('indeksler: (work_item_id), (site_code, created_at), yükleyen KISMİ, uploading KISMİ, storage_key TEKİL KISMİ', () => {
    assert.equal(sql('attachmentsItemIndex'), 'CREATE INDEX IF NOT EXISTS idx_work_item_attachments_item ON work_item_attachments (work_item_id)');
    assert.equal(sql('attachmentsSiteCreatedIndex'), 'CREATE INDEX IF NOT EXISTS idx_work_item_attachments_site_created ON work_item_attachments (site_code, created_at)');
    assert.ok(sql('attachmentsUploaderIndex').endsWith('WHERE uploaded_by IS NOT NULL'));
    assert.ok(sql('attachmentsUploadingIndex').endsWith("WHERE status = 'uploading'"));
    assert.ok(sql('attachmentsStorageKeyIndex').startsWith('CREATE UNIQUE INDEX') && sql('attachmentsStorageKeyIndex').endsWith('WHERE storage_key IS NOT NULL'));
  });
});

describe('ensureWorkAttachmentsSchema (katalog kontrolü + yeniden deneme)', () => {
  const ALL_INDEXES = WORK_ATTACHMENTS_DDL_ORDER.filter((n) => /Index$/.test(n)).map((n) => /INDEX IF NOT EXISTS (\w+)/.exec(sql(n))[1]);
  const ALL_FKS = ['work_item_attachments.work_item_attachments_work_item_id_fkey', 'work_item_attachments.work_item_attachments_site_code_fkey', 'work_item_attachments.work_item_attachments_uploaded_by_fkey'];
  const ALL_TABLES = ['work_item_attachments', 'work_items', 'work_item_events'];

  function fakeClient({ tables, indexes, fks = [], widened = true, failures = {} }) {
    const log = [];
    return {
      log,
      async query(text) {
        const statement = normalizeSql(text);
        log.push(statement);
        if (/^SELECT ARRAY/.test(statement)) return { rows: [{ tables, indexes, fks, events_type_widened: widened }] };
        if (/^SET lock_timeout|^RESET lock_timeout/.test(statement)) return { rows: [] };
        const key = Object.keys(failures).find((needle) => statement.includes(needle));
        if (key && failures[key].length > 0) throw Object.assign(new Error('enjekte'), { code: failures[key].shift() });
        return { rows: [] };
      },
    };
  }
  const ddlOf = (client) => client.log.filter((statement) => /^(CREATE|DO)/.test(statement));

  it('her şey varsa ve kısıt genişlemişse (normal açılış) YALNIZ katalog sorgusu gider: DDL yok, kilit ayarı yok', async () => {
    const client = fakeClient({ tables: ALL_TABLES, indexes: ALL_INDEXES, fks: ALL_FKS, widened: true });
    await ensureWorkAttachmentsSchema(client);
    assert.equal(client.log.length, 1);
    assert.match(client.log[0], /^SELECT ARRAY/);
    assert.match(client.log[0], /pg_get_constraintdef\(c\.oid\) LIKE '%attachment_added%'/);
  });

  it('hiçbiri yoksa (042 kurulu): lock_timeout, her ifade TEK ayrı sorgu olarak SIRAYLA (tablo, 3 FK, 5 indeks, kısıt genişletme), sonda RESET', async () => {
    const client = fakeClient({ tables: ['work_items', 'work_item_events'], indexes: [], widened: false });
    await ensureWorkAttachmentsSchema(client);
    assert.equal(client.log[1], "SET lock_timeout = '2s'");
    assert.equal(client.log[client.log.length - 1], 'RESET lock_timeout');
    assert.deepEqual(client.log.slice(2, -1), WORK_ATTACHMENTS_DDL_ORDER.map((name) => sql(name)));
  });

  it('yalnız kısıt genişlememişse yalnız o DO bloğu; yalnız eksik FK / indeks varsa yalnız o ifade', async () => {
    const onlyCheck = fakeClient({ tables: ALL_TABLES, indexes: ALL_INDEXES, fks: ALL_FKS, widened: false });
    await ensureWorkAttachmentsSchema(onlyCheck);
    assert.deepEqual(ddlOf(onlyCheck), [sql('eventsTypeCheck')]);
    const missingFk = fakeClient({ tables: ALL_TABLES, indexes: ALL_INDEXES, fks: ALL_FKS.filter((n) => !n.endsWith('uploaded_by_fkey')) });
    await ensureWorkAttachmentsSchema(missingFk);
    assert.deepEqual(ddlOf(missingFk), [sql('attachmentsUploaderFk')]);
    const missingIndex = fakeClient({ tables: ALL_TABLES, indexes: ALL_INDEXES.filter((n) => n !== 'idx_work_item_attachments_item'), fks: ALL_FKS });
    await ensureWorkAttachmentsSchema(missingIndex);
    assert.deepEqual(ddlOf(missingIndex), [sql('attachmentsItemIndex')]);
  });

  it('work_items / work_item_events henüz yoksa: tablo + sites / users FK\'leri + indeksler kurulur; talep FK\'si ve kısıt genişletme ATLANIR', async () => {
    const client = fakeClient({ tables: [], indexes: [], widened: false });
    await ensureWorkAttachmentsSchema(client);
    const sent = ddlOf(client);
    assert.ok(sent.includes(sql('attachmentsTable')) && sent.includes(sql('attachmentsSiteFk')) && sent.includes(sql('attachmentsUploaderFk')));
    assert.ok(!sent.includes(sql('attachmentsItemFk')) && !sent.includes(sql('eventsTypeCheck')));
    assert.equal(sent.filter((statement) => /^CREATE (UNIQUE )?INDEX/.test(statement)).length, 5);
  });

  it('40P01 / 55P03 geçici çakışmada yeniden dener; 6 denemeyi aşarsa fırlatır (RESET yine çalışır); başka hata ANINDA fırlar', async () => {
    const missing = { tables: ALL_TABLES, indexes: ALL_INDEXES, fks: ALL_FKS, widened: false };
    const retry = fakeClient({ ...missing, failures: { 'ADD CONSTRAINT chk_work_item_events_type': ['40P01', '55P03'] } });
    await ensureWorkAttachmentsSchema(retry);
    assert.equal(retry.log.filter((statement) => statement.includes('ADD CONSTRAINT chk_work_item_events_type')).length, 3);
    const hopeless = fakeClient({ ...missing, failures: { 'ADD CONSTRAINT chk_work_item_events_type': Array(10).fill('40P01') } });
    await assert.rejects(ensureWorkAttachmentsSchema(hopeless), { code: '40P01' });
    assert.equal(hopeless.log[hopeless.log.length - 1], 'RESET lock_timeout');
    const fatal = fakeClient({ ...missing, failures: { 'ADD CONSTRAINT chk_work_item_events_type': ['42501'] } });
    await assert.rejects(ensureWorkAttachmentsSchema(fatal), { code: '42501' });
  });
});

describe('girdi doğrulama, içerik imzası, eşleyiciler', () => {
  const jpegHead = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0, 0x10, 0x4a, 0x46, 0x49, 0x46, 0, 1, 1, 0, 0, 1]);
  const pngHead = Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 0x0d]), Buffer.from('IHDR')]);
  const webpHead = Buffer.concat([Buffer.from('RIFF'), Buffer.from([0x24, 0, 0, 0]), Buffer.from('WEBPVP8 ')]);

  it('parseAttachmentInput: uzantı bildirilen türden gelir (foto.png + image/jpeg -> foto.jpg), yol parçaları atılır, uzun ad 160\'a kesilir; boş ad fotograf', () => {
    assert.deepEqual(parseAttachmentInput({ file_name: 'C:\\Users\\x\\foto.png', mime_type: 'IMAGE/JPEG', size_bytes: 1000 }), { fileName: 'foto.jpg', mimeType: 'image/jpeg', sizeBytes: 1000 });
    assert.equal(parseAttachmentInput({ file_name: '../../etc/passwd', mime_type: 'image/webp', size_bytes: 1 }).fileName, 'passwd.webp');
    assert.equal(buildAttachmentFileName('   ', 'image/png'), 'fotograf.png');
    const long = parseAttachmentInput({ file_name: 'a'.repeat(300), mime_type: 'image/png', size_bytes: 5 }).fileName;
    assert.ok(Array.from(long).length <= 160 && long.endsWith('.png'));
  });

  it('parseAttachmentInput: tür dışı 415 ATTACHMENT_TYPE_NOT_ALLOWED; boş / geçersiz boyut 400 INVALID_BODY; 5 MB üstü 413 ATTACHMENT_TOO_LARGE; ad zorunlu', () => {
    const reject = (body, status, code) => assert.throws(() => parseAttachmentInput(body), (error) => error.statusCode === status && error.code === code, JSON.stringify(body));
    reject({ file_name: 'a.gif', mime_type: 'image/gif', size_bytes: 10 }, 415, 'ATTACHMENT_TYPE_NOT_ALLOWED');
    reject({ file_name: 'a.svg', mime_type: 'image/svg+xml', size_bytes: 10 }, 415, 'ATTACHMENT_TYPE_NOT_ALLOWED');
    reject({ file_name: 'a.jpg', mime_type: 'image/jpeg', size_bytes: 0 }, 400, 'INVALID_BODY');
    reject({ file_name: 'a.jpg', mime_type: 'image/jpeg', size_bytes: '10' }, 400, 'INVALID_BODY');
    reject({ file_name: 'a.jpg', mime_type: 'image/jpeg', size_bytes: ATTACHMENT_MAX_BYTES + 1 }, 413, 'ATTACHMENT_TOO_LARGE');
    reject({ mime_type: 'image/jpeg', size_bytes: 10 }, 400, 'INVALID_BODY');
    reject(null, 400, 'INVALID_BODY');
    assert.equal(parseAttachmentInput({ file_name: 'a.jpg', mime_type: 'image/jpeg', size_bytes: ATTACHMENT_MAX_BYTES }).sizeBytes, ATTACHMENT_MAX_BYTES);
  });

  it('detectImageMime: JPEG / PNG / WebP imzaları; PDF, GIF, HTML, SVG, boş -> null; assertImageHead: tanınmayan 415 TYPE_NOT_ALLOWED, uyuşmayan 415 CONTENT_MISMATCH', () => {
    assert.equal(detectImageMime(jpegHead), 'image/jpeg');
    assert.equal(detectImageMime(pngHead), 'image/png');
    assert.equal(detectImageMime(webpHead), 'image/webp');
    for (const bad of [Buffer.from('%PDF-1.4'), Buffer.from('GIF89a'), Buffer.from('<html>'), Buffer.from('<svg xmlns'), Buffer.alloc(0), Buffer.from('RIFF....WAVE'), 'string']) {
      assert.equal(detectImageMime(bad), null, String(bad));
    }
    assert.equal(assertImageHead(jpegHead, 'image/jpeg'), 'image/jpeg');
    assert.throws(() => assertImageHead(Buffer.from('%PDF-1.4'), 'image/jpeg'), { statusCode: 415, code: 'ATTACHMENT_TYPE_NOT_ALLOWED' });
    assert.throws(() => assertImageHead(pngHead, 'image/jpeg'), { statusCode: 415, code: 'ATTACHMENT_CONTENT_MISMATCH' });
  });

  it('mapAttachment: uploaded_by_kind (yükleyen talebi açan mı), uploaded_by_me, silinmiş yükleyen "Silinmiş Kullanıcı", sayılar / tarihler; silme önizleme notu birebir', () => {
    const row = { id: '7', work_item_id: '5', file_name: 'a.jpg', mime_type: 'image/jpeg', size_bytes: '1234', status: 'ready', uploaded_by: 12, uploaded_by_name: 'Ada', uploaded_by_resident: true, created_at: new Date('2026-01-01T00:00:00Z'), ready_at: new Date('2026-01-01T00:01:00Z') };
    const mine = mapAttachment(row, { userCode: 12 });
    assert.deepEqual(mine, { id: 7, work_item_id: 5, file_name: 'a.jpg', mime_type: 'image/jpeg', size_bytes: 1234, status: 'ready', phase: null, uploaded_by_kind: 'resident', uploaded_by_name: 'Ada', uploaded_by_me: true, created_at: '2026-01-01T00:00:00.000Z', ready_at: '2026-01-01T00:01:00.000Z' });
    assert.equal(mapAttachment(row, { userCode: 13 }).uploaded_by_me, false);
    assert.equal(mapAttachment({ ...row, uploaded_by_resident: false }, { userCode: 12 }).uploaded_by_kind, 'management');
    assert.equal(mapAttachment({ ...row, uploaded_by_resident: null }, { userCode: 12 }).uploaded_by_kind, 'management', 'bilinmiyorsa yönetim');
    assert.equal(mapAttachment({ ...row, uploaded_by: null, uploaded_by_name: null }, { userCode: 12 }).uploaded_by_name, 'Silinmiş Kullanıcı');
    assert.equal(attachmentsKeepNote(3), 'İş takibi taleplerine eklediğiniz fotoğraflar (3) taleple birlikte site yönetiminde kalır; yükleyen adı "Silinmiş Kullanıcı" görünür.');
    assert.ok(!JSON.stringify(mine).includes('storage_key') && !JSON.stringify(mine).includes('sha256'));
  });

  it('WA-SEC-1 sakin görünümü: kendi fotoğrafında gerçek ad; yönetimin (yönetici / görevli / silinmiş / satırı kalkmış) fotoğrafında ad "Yönetim" (null DEĞİL, "Silinmiş Kullanıcı" DEĞİL); yönetim görünümü değişmez', () => {
    const base = { id: '8', work_item_id: '5', file_name: 'b.jpg', mime_type: 'image/jpeg', size_bytes: '10', status: 'ready', created_at: new Date('2026-01-01T00:00:00Z'), ready_at: null };
    const residentOwn = mapAttachment({ ...base, uploaded_by: 12, uploaded_by_name: 'Ada Sakin', uploaded_by_resident: true }, { userCode: 12, residentView: true });
    assert.deepEqual([residentOwn.uploaded_by_name, residentOwn.uploaded_by_kind, residentOwn.uploaded_by_me], ['Ada Sakin', 'resident', true]);
    for (const uploader of [
      { uploaded_by: 99, uploaded_by_name: 'Mehmet Yönetici' },
      { uploaded_by: 98, uploaded_by_name: null }, // silinmiş hesap
      { uploaded_by: null, uploaded_by_name: null }, // kullanıcı satırı fiziksel silinmiş
    ]) {
      const masked = mapAttachment({ ...base, ...uploader, uploaded_by_resident: false }, { userCode: 12, residentView: true });
      assert.deepEqual([masked.uploaded_by_name, masked.uploaded_by_kind, masked.uploaded_by_me], [MANAGEMENT_UPLOADER_LABEL, 'management', false], JSON.stringify(uploader));
    }
    assert.equal(MANAGEMENT_UPLOADER_LABEL, 'Yönetim');
    const managerView = mapAttachment({ ...base, uploaded_by: 99, uploaded_by_name: 'Mehmet Yönetici', uploaded_by_resident: false }, { userCode: 20001 });
    assert.deepEqual([managerView.uploaded_by_name, managerView.uploaded_by_kind], ['Mehmet Yönetici', 'management']);
  });

  it('kota ayarları: varsayılan sakin 200 MB (30 günlük pencere) / site 10240 MB / yetim yaşı 30 gün; env ile değişir, geçersiz değer varsayılana döner; hata gövdesi { quota, quota_bytes, used_bytes (+ window_days: sakin) }', () => {
    const MB = 1048576;
    assert.deepEqual(attachmentLimits({}), { userQuotaBytes: 200 * MB, siteQuotaBytes: 10240 * MB, orphanMinAgeDays: 30 });
    assert.deepEqual(attachmentLimits({ WORK_ATTACHMENTS_USER_QUOTA_MB: '5', WORK_ATTACHMENTS_SITE_QUOTA_MB: '50', WORK_ATTACHMENTS_ORPHAN_MIN_AGE_DAYS: '7' }), { userQuotaBytes: 5 * MB, siteQuotaBytes: 50 * MB, orphanMinAgeDays: 7 });
    const realWarn = console.warn;
    console.warn = () => {};
    try {
      assert.deepEqual(attachmentLimits({ WORK_ATTACHMENTS_USER_QUOTA_MB: '0', WORK_ATTACHMENTS_SITE_QUOTA_MB: 'x', WORK_ATTACHMENTS_ORPHAN_MIN_AGE_DAYS: '-1' }), { userQuotaBytes: 200 * MB, siteQuotaBytes: 10240 * MB, orphanMinAgeDays: 30 });
    } finally {
      console.warn = realWarn;
    }
    assert.equal(ATTACHMENT_USER_QUOTA_WINDOW_DAYS, 30);
    const user = attachmentQuotaExceeded('user', 150 * MB, 200 * MB);
    assert.deepEqual([user.statusCode, user.code, user.extra], [409, 'ATTACHMENT_QUOTA_EXCEEDED', { quota: 'user', quota_bytes: 200 * MB, used_bytes: 150 * MB, window_days: 30 }]);
    assert.equal(user.message, 'Son 30 günde bu sitede yükleyebileceğiniz fotoğraf sınırına ulaştınız (en çok 200 MB); daha sonra yeniden deneyin ya da yönetime başvurun.');
    assert.match(attachmentQuotaExceeded('user', 1, 5 * MB).message, /\(en çok 5 MB\)/, 'sınır ayarlanan değeri söyler');
    const site = attachmentQuotaExceeded('site', 1, 2);
    assert.deepEqual([site.statusCode, site.code, site.extra, site.message], [409, 'ATTACHMENT_QUOTA_EXCEEDED', { quota: 'site', quota_bytes: 2, used_bytes: 1 }, 'Sitenin fotoğraf alanı doldu. Yönetimle iletişime geçin.']);
  });
});

// --- piksel boyutu (açılma bombası) ----------------------------------------------------------------------------------------------

const readerOf = (buffer) => async (position, length) => buffer.subarray(position, position + length);
const dims = (mime, buffer) => readImageDimensions(mime, readerOf(buffer), buffer.length);

function pngOf(width, height) {
  const buffer = Buffer.alloc(33 + 12);
  Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]).copy(buffer, 0);
  buffer.writeUInt32BE(13, 8);
  buffer.write('IHDR', 12, 'latin1');
  buffer.writeUInt32BE(width, 16);
  buffer.writeUInt32BE(height, 20);
  return buffer;
}

function webpOf(chunk, body) {
  const head = Buffer.alloc(20);
  head.write('RIFF', 0, 'latin1');
  head.writeUInt32LE(12 + body.length, 4);
  head.write('WEBP', 8, 'latin1');
  head.write(chunk, 12, 'latin1');
  head.writeUInt32LE(body.length, 16);
  return Buffer.concat([head, body, Buffer.alloc(16)]);
}
const vp8 = (width, height) => {
  const body = Buffer.alloc(10);
  body.set([0x9d, 0x01, 0x2a], 3);
  body.writeUInt16LE(width & 0x3fff, 6);
  body.writeUInt16LE(height & 0x3fff, 8);
  return webpOf('VP8 ', body);
};
const vp8l = (width, height) => {
  const body = Buffer.alloc(5);
  body[0] = 0x2f;
  body.writeUInt32LE(((width - 1) & 0x3fff) | (((height - 1) & 0x3fff) << 14), 1);
  return webpOf('VP8L', body);
};
const vp8x = (width, height) => {
  const body = Buffer.alloc(10);
  body.writeUIntLE(width - 1, 4, 3);
  body.writeUIntLE(height - 1, 7, 3);
  return webpOf('VP8X', body);
};

/** JPEG: SOI + APP0 + dolgu baytı + DQT + DHT (C4, SOF DEĞİL) + SOFn + SOS. */
function jpegOf(width, height, { sof = 0xc0, sosFirst = false } = {}) {
  const app0 = Buffer.concat([Buffer.from([0xff, 0xe0, 0x00, 0x10]), Buffer.from('JFIF\0'), Buffer.alloc(9)]);
  const dqt = Buffer.from([0xff, 0xdb, 0x00, 0x04, 0x00, 0x01]);
  const dht = Buffer.from([0xff, 0xc4, 0x00, 0x04, 0x00, 0x00]);
  const sofSegment = Buffer.alloc(19);
  sofSegment.set([0xff, sof, 0x00, 0x11, 0x08], 0);
  sofSegment.writeUInt16BE(height, 5);
  sofSegment.writeUInt16BE(width, 7);
  const sos = Buffer.from([0xff, 0xda, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x3f, 0x00]);
  const parts = [Buffer.from([0xff, 0xd8]), app0, Buffer.from([0xff]), dqt, dht];
  if (sosFirst) parts.push(sos, sofSegment);
  else parts.push(sofSegment, sos);
  parts.push(Buffer.from([0x11, 0x22, 0xff, 0xd9]));
  return Buffer.concat(parts);
}

describe('piksel boyutu: açılma bombası koruması (yalnız başlık okunur)', () => {
  it('sınırlar: kenar 12.000, toplam 40.000.000 piksel; tam sınır kabul, bir fazlası 415 ATTACHMENT_DIMENSIONS_TOO_LARGE (+ width / height / max_side / max_pixels)', () => {
    assert.deepEqual([MAX_IMAGE_SIDE, MAX_IMAGE_PIXELS], [12000, 40000000]);
    assert.deepEqual(assertImageDimensions({ width: 12000, height: 3333 }), { width: 12000, height: 3333 });
    assert.deepEqual(assertImageDimensions({ width: 8000, height: 5000 }), { width: 8000, height: 5000 }, 'tam 40 milyon');
    for (const [width, height] of [[12001, 10], [10, 12001], [8000, 5001], [7000, 7000]]) {
      assert.throws(() => assertImageDimensions({ width, height }), (error) => error.statusCode === 415 && error.code === 'ATTACHMENT_DIMENSIONS_TOO_LARGE' &&
        error.extra.width === width && error.extra.height === height && error.extra.max_side === 12000 && error.extra.max_pixels === 40000000, `${width}x${height}`);
    }
  });

  it('PNG: IHDR genişlik / yükleklik (büyük uçlu); 0 boyut ya da IHDR yoksa 415 ATTACHMENT_CONTENT_MISMATCH', async () => {
    assert.deepEqual(await dims('image/png', pngOf(4032, 3024)), { width: 4032, height: 3024 });
    assert.deepEqual(await dims('image/png', pngOf(60000, 60000)), { width: 60000, height: 60000 });
    assert.throws(() => assertImageDimensions({ width: 60000, height: 60000 }), { code: 'ATTACHMENT_DIMENSIONS_TOO_LARGE' });
    await assert.rejects(dims('image/png', pngOf(0, 10)), { statusCode: 415, code: 'ATTACHMENT_CONTENT_MISMATCH' });
    const broken = pngOf(10, 10);
    broken.write('XXXX', 12, 'latin1');
    await assert.rejects(dims('image/png', broken), { code: 'ATTACHMENT_CONTENT_MISMATCH' });
    await assert.rejects(dims('image/png', pngOf(10, 10).subarray(0, 20)), { code: 'ATTACHMENT_CONTENT_MISMATCH' }, 'kesik');
  });

  it('WebP: VP8 (14 bit), VP8L (14 + 14 bit, +1), VP8X (24 bit, +1); bozuk başlangıç kodu / imza / bilinmeyen parça 415 ATTACHMENT_CONTENT_MISMATCH', async () => {
    assert.deepEqual(await dims('image/webp', vp8(4000, 3000)), { width: 4000, height: 3000 });
    assert.deepEqual(await dims('image/webp', vp8(13000, 2)), { width: 13000, height: 2 });
    assert.deepEqual(await dims('image/webp', vp8l(100, 200)), { width: 100, height: 200 });
    assert.deepEqual(await dims('image/webp', vp8l(16384, 16384)), { width: 16384, height: 16384 });
    assert.deepEqual(await dims('image/webp', vp8x(20000, 20000)), { width: 20000, height: 20000 });
    assert.deepEqual(await dims('image/webp', vp8x(5000, 5000)), { width: 5000, height: 5000 });
    const badStart = vp8(10, 10);
    badStart[23] = 0x00;
    await assert.rejects(dims('image/webp', badStart), { code: 'ATTACHMENT_CONTENT_MISMATCH' });
    const badLossless = vp8l(10, 10);
    badLossless[20] = 0x00;
    await assert.rejects(dims('image/webp', badLossless), { code: 'ATTACHMENT_CONTENT_MISMATCH' });
    await assert.rejects(dims('image/webp', webpOf('ALPH', Buffer.alloc(12))), { code: 'ATTACHMENT_CONTENT_MISMATCH' });
  });

  it('JPEG: APP / dolgu baytı / DQT / DHT (C4 SOF değildir) atlanır, SOF0 ve SOF2 (progresif) okunur; SOFn\'den önce SOS ya da dosya sonu, 0 yükseklik 415 ATTACHMENT_CONTENT_MISMATCH', async () => {
    assert.deepEqual(await dims('image/jpeg', jpegOf(4032, 3024)), { width: 4032, height: 3024 });
    assert.deepEqual(await dims('image/jpeg', jpegOf(1200, 30000, { sof: 0xc2 })), { width: 1200, height: 30000 });
    await assert.rejects(dims('image/jpeg', jpegOf(100, 100, { sosFirst: true })), { code: 'ATTACHMENT_CONTENT_MISMATCH' });
    await assert.rejects(dims('image/jpeg', jpegOf(100, 0)), { code: 'ATTACHMENT_CONTENT_MISMATCH' });
    await assert.rejects(dims('image/jpeg', jpegOf(100, 100).subarray(0, 30)), { code: 'ATTACHMENT_CONTENT_MISMATCH' }, 'SOF yok (kesik)');
    await assert.rejects(dims('image/gif', Buffer.from('GIF89a')), { code: 'ATTACHMENT_TYPE_NOT_ALLOWED' });
  });
});

// --- servis: kota, süresi dolan kayıtlar, kapalı talepte silme (sahte işlem istemcisi) ------------------------------------------

describe('servis (sahte işlem): kota, etkin kayıt sayımı, kapalı talepte silme', () => {
  const MB = 1048576;
  const SITE_CODE = 1000000001;
  let state;
  let log;
  let root;

  before(async () => {
    root = await fsp.mkdtemp(path.join(os.tmpdir(), 'wa-service-'));
    process.env.DOCUMENTS_DIR = root;
  });
  after(async () => {
    delete pool.query;
    delete pool.connect;
    delete process.env.DOCUMENTS_DIR;
    delete process.env.WORK_ATTACHMENTS_USER_QUOTA_MB;
    delete process.env.WORK_ATTACHMENTS_SITE_QUOTA_MB;
    await fsp.rm(root, { recursive: true, force: true });
  });

  beforeEach(() => {
    log = [];
    state = { itemStatus: 'islemde', hourly: 0, itemCount: 0, userUsed: 0, siteUsed: 0, attachment: null };
    const run = async (text, params = []) => {
      const sql = norm(text);
      log.push({ sql, params });
      if (/^SELECT site_code FROM sites WHERE site_code = \$1 FOR KEY SHARE$/.test(sql)) return ok([{ site_code: String(params[0]) }]);
      if (/^SELECT user_code FROM users WHERE user_code = \$1 AND deleted_at IS NULL FOR KEY SHARE$/.test(sql)) return ok([{ user_code: params[0] }]);
      if (/^SELECT site_code FROM work_items WHERE id = \$2 AND created_by = \$1$/.test(sql)) return ok([{ site_code: String(SITE_CODE) }]);
      if (/^SELECT w\.id, w\.site_code, w\.status FROM work_items w WHERE .* FOR UPDATE OF w$/.test(sql)) return ok([{ id: '5', site_code: String(SITE_CODE), status: state.itemStatus }]);
      if (/^WITH my_apts AS/.test(sql) || /my_apts/.test(sql)) return ok([{ x: 1 }]);
      if (/^SELECT COUNT\(\*\)::INTEGER AS n FROM work_item_attachments WHERE uploaded_by = \$1 AND created_at > NOW\(\) - INTERVAL '1 hour'$/.test(sql)) return ok([{ n: state.hourly }]);
      if (/^SELECT COUNT\(\*\)::INTEGER AS n FROM work_item_attachments a WHERE a\.work_item_id = \$1 AND/.test(sql)) return ok([{ n: state.itemCount }]);
      if (/^SELECT COALESCE\(SUM\(a\.size_bytes\), 0\)::BIGINT AS used FROM work_item_attachments a WHERE a\.uploaded_by = \$2 AND a\.created_at > NOW\(\) - make_interval\(days => \$4::INTEGER\) AND a\.site_code = \$1 AND \(/.test(sql)) return ok([{ used: String(state.userUsed) }]);
      if (/^SELECT COALESCE\(SUM\(a\.size_bytes\), 0\)::BIGINT AS used FROM work_item_attachments a WHERE a\.site_code = \$1 AND \(/.test(sql)) return ok([{ used: String(state.siteUsed) }]);
      if (/^INSERT INTO work_item_attachments/.test(sql)) return ok([{ id: '77' }]);
      if (/^SELECT id, uploaded_by, status, storage_key, mime_type, size_bytes FROM work_item_attachments WHERE id = \$1 AND work_item_id = \$2 FOR UPDATE$/.test(sql)) return ok(state.attachment ? [state.attachment] : []);
      if (/^INSERT INTO work_item_events/.test(sql)) return ok([{ id: '901' }]);
      if (/^SELECT a\.id, a\.work_item_id/.test(sql)) {
        return ok([{ id: '77', work_item_id: '5', site_code: String(SITE_CODE), uploaded_by: params[0] === 77 ? 20004 : null, file_name: 'f.jpg', mime_type: 'image/jpeg', size_bytes: '100', status: 'uploading', uploaded_by_name: 'Sakin', uploaded_by_resident: true, created_at: new Date(), ready_at: null }]);
      }
      return ok();
    };
    pool.connect = async () => ({ query: (text, params) => run(text, params), release() {} });
    pool.query = async (text, params) => run(text, params);
  });

  const BODY = { file_name: 'f.jpg', mime_type: 'image/jpeg', size_bytes: 100 };
  const resident = residentScope({ user_code: 20004 });
  const staff = managerScope({ kind: 'staff', userCode: 20005, siteCode: SITE_CODE, canManage: false });
  const manager = managerScope({ kind: 'manager', userCode: 20001, siteCode: SITE_CODE, canManage: true });
  const actorOf = (userCode) => ({ user_code: userCode, role: 'individual' });
  const sqls = () => log.map((entry) => entry.sql);

  it('sakin kotası (R2-2; YALNIZ sakin, son 30 gün, yalnız SAKİN olarak kendi taleplerine yüklenenler): kullanılan + gelen > 200 MB -> 409 ATTACHMENT_QUOTA_EXCEEDED { quota: user, window_days: 30 }; INSERT yok, ROLLBACK; sorgu pencereli', async () => {
    log.length = 0;
    state.userUsed = 200 * MB - 50;
    await assert.rejects(createAttachment({ scope: resident, rawId: '5', actor: actorOf(20004), body: BODY }), (error) =>
      error.statusCode === 409 && error.code === 'ATTACHMENT_QUOTA_EXCEEDED' && error.extra.quota === 'user' && error.extra.quota_bytes === 200 * MB && error.extra.used_bytes === 200 * MB - 50 &&
      error.extra.window_days === 30);
    assert.ok(!sqls().some((sql) => /^INSERT INTO work_item_attachments/.test(sql)));
    assert.ok(sqls().includes('ROLLBACK'));
    const windowQuery = log.find((entry) => /a\.uploaded_by = \$2/.test(entry.sql));
    assert.ok(windowQuery.sql.includes('a.created_at > NOW() - make_interval(days => $4::INTEGER)'), windowQuery.sql);
    // çift rol (inceleme 4. tur): aynı kişinin görevli / yönetici olarak BAŞKA taleplere yükledikleri sakin penceresine girmez
    assert.ok(windowQuery.sql.endsWith('AND EXISTS (SELECT 1 FROM work_items w WHERE w.id = a.work_item_id AND w.created_by = a.uploaded_by)'), windowQuery.sql);
    assert.deepEqual(windowQuery.params, [SITE_CODE, 20004, 120, ATTACHMENT_USER_QUOTA_WINDOW_DAYS], '(site, sakin, yükleme ömrü dk, pencere gün)');
    state.userUsed = 200 * MB - 100; // tam sınır kabul
    const okResult = await createAttachment({ scope: resident, rawId: '5', actor: actorOf(20004), body: BODY });
    assert.equal(okResult.attachment.id, 77);
  });

  it('görevli / yönetici / süper sakin kotasına TABİ DEĞİL (sorgusu bile gitmez; kapanan talepteki silemedikleri fotoğraflar onları kilitlemez); site kotası herkese: kullanılan + gelen > 10240 MB -> { quota: site }', async () => {
    state.userUsed = 10 ** 12;
    for (const [scope, userCode] of [[manager, 20001], [staff, 20005]]) {
      log.length = 0;
      const created = await createAttachment({ scope, rawId: '5', actor: actorOf(userCode), body: BODY });
      assert.equal(created.attachment.id, 77);
      assert.ok(!sqls().some((sql) => /a\.uploaded_by = \$2/.test(sql)), `${scope.kind}: kişi toplamı sorgusu gitmedi`);
    }
    for (const [scope, userCode] of [[manager, 20001], [staff, 20005], [resident, 20004]]) {
      state.userUsed = 0;
      state.siteUsed = 10240 * MB;
      await assert.rejects(createAttachment({ scope, rawId: '5', actor: actorOf(userCode), body: BODY }), (error) => error.code === 'ATTACHMENT_QUOTA_EXCEEDED' && error.extra.quota === 'site');
    }
    process.env.WORK_ATTACHMENTS_SITE_QUOTA_MB = '20000';
    try {
      await createAttachment({ scope: manager, rawId: '5', actor: actorOf(20001), body: BODY });
    } finally {
      delete process.env.WORK_ATTACHMENTS_SITE_QUOTA_MB;
    }
  });

  it('kilit sırası: kullanıcı kilidi -> site fotoğraf kilidi -> talep satırı; sınır / kota sayımları yalnız ETKİN kayıtları sayar (hazır ya da süresi DOLMAMIŞ yükleme; 120 dk)', async () => {
    await createAttachment({ scope: resident, rawId: '5', actor: actorOf(20004), body: BODY });
    const advisory = log.filter((entry) => /^SELECT pg_advisory_xact_lock/.test(entry.sql)).map((entry) => entry.params[0]);
    assert.deepEqual(advisory, ['work_items_user:20004', siteAttachmentLockKey(SITE_CODE)]);
    const at = (pattern) => log.findIndex((entry) => pattern.test(entry.sql));
    assert.ok(at(/work_attachments_site|pg_advisory_xact_lock/) < at(/FOR UPDATE OF w$/));
    assert.ok(log.findIndex((entry) => entry.params[0] === siteAttachmentLockKey(SITE_CODE)) < at(/FOR UPDATE OF w$/));
    const active = "(a.status = 'ready' OR (a.status = 'uploading' AND a.created_at >= NOW() - make_interval(mins =>";
    for (const [pattern, ttlIndex] of [
      [/^SELECT COUNT\(\*\)::INTEGER AS n FROM work_item_attachments a WHERE a\.work_item_id/, 1],
      [/a\.uploaded_by = \$2/, 2],
      [/^SELECT COALESCE\(SUM\(a\.size_bytes\), 0\)::BIGINT AS used FROM work_item_attachments a WHERE a\.site_code = \$1 AND \(/, 1],
    ]) {
      const entry = log.find((candidate) => pattern.test(candidate.sql));
      assert.ok(entry, String(pattern));
      assert.ok(entry.sql.includes(active), entry.sql);
      assert.equal(entry.params[ttlIndex], 120, 'süre parametresi (dk)');
    }
    state.itemCount = MAX_ATTACHMENTS_PER_ITEM;
    await assert.rejects(createAttachment({ scope: resident, rawId: '5', actor: actorOf(20004), body: BODY }), { code: 'LIMIT_REACHED' });
  });

  it('WA-SEC-2: KAPALI talepte yönetici fotoğraf siler (200, attachment_removed olayı + audit closed_item true); görevli / sakin kendi fotoğrafında 409 INVALID_STATE; açık talepte herkes kendi fotoğrafını siler', async () => {
    state.itemStatus = 'kapandi';
    state.attachment = { id: '3', uploaded_by: 20004, status: 'ready', storage_key: `${SITE_CODE}/123e4567-e89b-42d3-a456-426614174000`, mime_type: 'image/jpeg', size_bytes: '10' };
    assert.deepEqual(await deleteAttachment({ scope: manager, rawId: '5', rawAttId: '3', actor: actorOf(20001) }), { deleted: true });
    assert.ok(sqls().some((sql) => /^DELETE FROM work_item_attachments WHERE id = \$1$/.test(sql)));
    const event = log.find((entry) => /^INSERT INTO work_item_events/.test(entry.sql));
    assert.equal(event.params[2], 'attachment_removed');
    const auditRow = log.find((entry) => /^INSERT INTO audit_log/.test(entry.sql));
    assert.equal(auditRow.params[3], 'work_item.attachment_removed');
    assert.deepEqual(JSON.parse(auditRow.params[7]), { attachment_id: 3, status: 'ready', mime_type: 'image/jpeg', size_bytes: 10, by: 'management', own: false, closed_item: true });
    for (const [scope, userCode] of [[staff, 20005], [resident, 20004]]) {
      log.length = 0;
      state.attachment = { ...state.attachment, uploaded_by: userCode };
      await assert.rejects(deleteAttachment({ scope, rawId: '5', rawAttId: '3', actor: actorOf(userCode) }), (error) => error.statusCode === 409 && error.code === 'INVALID_STATE' && /yalnız yönetici/.test(error.message));
      assert.ok(!sqls().some((sql) => /^DELETE FROM work_item_attachments/.test(sql)));
    }
    state.itemStatus = 'islemde';
    assert.deepEqual(await deleteAttachment({ scope: resident, rawId: '5', rawAttId: '3', actor: actorOf(20004) }), { deleted: true });
  });
});

describe('indirme yuvaları ayrı (WA-SEC-4) ve uçuş anahtarı kullanıcı başına (WA-SEC-5)', () => {
  const fakeRes = () => {
    const out = { headers: {}, statusCode: null, body: null };
    out.setHeader = (key, value) => { out.headers[key] = value; };
    out.status = (code) => { out.statusCode = code; return { json: (body) => { out.body = body; return out; } }; };
    return out;
  };

  it('sendDocument `slots` verilirse belge sayacına dokunmaz; dolu fotoğraf yuvası belge yuvasını etkilemez; varsayılan belge sayacı', async () => {
    const slots = { active: 0 };
    let during = null;
    await sendDocument({ method: 'GET' }, fakeRes(), {
      root: os.tmpdir(),
      version: { storageKey: '1000000001/123e4567-e89b-42d3-a456-426614174000', sizeBytes: 3, displayName: 'a.jpg', mimeType: 'image/jpeg' },
      limit: 1,
      slots,
      subtree: ATTACHMENT_SUBTREE,
      onMissing: async () => {
        during = [slots.active, activeDownloadCount()];
        return Object.assign(new Error('yok'), { code: 'X' });
      },
    }).catch(() => {});
    assert.deepEqual(during, [1, 0], 'fotoğraf yuvası sayıldı, belge sayacı 0');
    assert.equal(slots.active, 0, 'bitince geri verildi');
    const busy = fakeRes();
    await sendDocument({ method: 'GET' }, busy, { root: os.tmpdir(), version: {}, limit: 1, slots: { active: 1 }, onMissing: async () => new Error('x') });
    assert.deepEqual([busy.statusCode, busy.body.code, busy.headers['Retry-After']], [503, 'DOWNLOAD_BUSY', '5']);
    assert.equal(activeDownloadCount(), 0);
    assert.equal(attachmentUploadState.downloads(), 0);
  });

  it('uçuş anahtarı (kullanıcı, ek): farklı kullanıcının aynı eke PUT\'u sahibininkini engellemez', () => {
    assert.equal(flightKeyOf(20004, 3), 'wa:20004:3');
    assert.notEqual(flightKeyOf(20004, 3), flightKeyOf(20009, 3));
    assert.equal(flightKeyOf(null, 3), 'wa:0:3');
  });
});

describe('depolama alt ağacı ilkelleri (belgelerle AYNI anahtar / traversal kuralları, AYRI dizin)', () => {
  const KEY = '1000000001/123e4567-e89b-42d3-a456-426614174000';
  let base;
  before(async () => {
    base = await fsp.mkdtemp(path.join(os.tmpdir(), 'wa-storage-'));
  });
  after(async () => {
    await fsp.rm(base, { recursive: true, force: true });
  });

  it('pathForKey(subtree): work_attachments/<site>/<uuid>; varsayılan sites; bilinmeyen alt ağaç ve kötü anahtar reddedilir', () => {
    assert.deepEqual([...STORAGE_SUBTREES], ['sites', 'work_attachments']);
    assert.equal(ATTACHMENT_SUBTREE, 'work_attachments');
    assert.equal(pathForKey(base, KEY, ATTACHMENT_SUBTREE), path.join(base, 'work_attachments', '1000000001', '123e4567-e89b-42d3-a456-426614174000'));
    assert.equal(pathForKey(base, KEY), path.join(base, 'sites', '1000000001', '123e4567-e89b-42d3-a456-426614174000'));
    assert.throws(() => pathForKey(base, KEY, '../sites'), /gecersiz depolama alt agaci/);
    assert.throws(() => pathForKey(base, '1000000001/../../x', ATTACHMENT_SUBTREE), /gecersiz depolama anahtari/);
  });

  it('ensureSiteDir / removeStoredFile / openStoredFile alt ağaçla çalışır; belge ağacına dokunmaz', async () => {
    await ensureSiteDir(base, 1000000001, ATTACHMENT_SUBTREE);
    const full = pathForKey(base, KEY, ATTACHMENT_SUBTREE);
    await fsp.writeFile(full, 'abc');
    assert.deepEqual(await openStoredFile(base, KEY, 3), { error: 'missing' }, 'belge ağacında yok');
    const opened = await openStoredFile(base, KEY, 3, ATTACHMENT_SUBTREE);
    assert.equal(opened.size, 3);
    await opened.handle.close();
    assert.deepEqual(await openStoredFile(base, KEY, 4, ATTACHMENT_SUBTREE), { error: 'mismatch' });
    assert.equal(await removeStoredFile(base, KEY), false);
    assert.equal(await removeStoredFile(base, KEY, ATTACHMENT_SUBTREE), true);
    assert.equal(await removeStoredFile(base, KEY, ATTACHMENT_SUBTREE), false);
  });

  it('contentDisposition: belge attachment (varsayılan), fotoğraf inline; başka değer attachment sayılır', () => {
    assert.ok(contentDisposition('a.pdf').startsWith('attachment; '));
    assert.ok(contentDisposition('foto ş.jpg', 'inline').startsWith('inline; filename="foto s.jpg"; filename*=UTF-8\'\''));
    assert.ok(contentDisposition('a.pdf', 'weird').startsWith('attachment; '));
  });
});

// --- rota zinciri (KATI sahte DB) ----------------------------------------------------------------------------------------------

const SITE = 1000000001;
const mk = (id, role, name) => ({ id, user_code: id, userCode: id, role, full_name: name, email: `u${id}@example.com` });
const users = {
  manager: mk(20001, 'site_manager', 'Yönetici'),
  resident: mk(20004, 'apartment_owner', 'Sakin'),
  staff: mk(20005, 'individual', 'Görevli'),
  board: mk(20006, 'individual', 'Kurul'),
};
const ok = (rows = [], rowCount = rows.length) => ({ rows, rowCount });

describe('rota zinciri: yetki / doğrulama hataları veritabanına gitmeden döner', () => {
  let server;
  let baseUrl;
  let log;
  let reportToday;
  let visibleGate = null;

  function fakeQuery(text, params = []) {
    const text1 = norm(text);
    log.push(text1);
    if (/^SELECT 1 FROM site_manager_sites WHERE site_code = \$1 AND manager_user_code = \$2 LIMIT 1$/.test(text1)) {
      return ok(Number(params[0]) === SITE && Number(params[1]) === 20001 ? [{ x: 1 }] : []);
    }
    if (/^SELECT 1 FROM site_memberships WHERE site_code = \$1 AND user_code = \$2 AND role IN \('SITE_OWNER', 'SITE_ADMIN'\) AND is_active = TRUE LIMIT 1$/.test(text1)) return ok();
    if (/^SELECT EXISTS \( SELECT 1 FROM site_memberships WHERE site_code = \$1 AND user_code = \$2 AND role = 'BOARD_MEMBER'/.test(text1)) {
      const board = Number(params[1]) === 20006;
      return ok([{ is_board_here: board, is_member_here: board || Number(params[1]) === 20005, has_other_role: board }]);
    }
    if (/^SELECT 1 FROM site_memberships WHERE site_code = \$1 AND user_code = \$2 AND role = 'STAFF' AND is_active = TRUE LIMIT 1$/.test(text1)) {
      return ok(Number(params[1]) === 20005 ? [{ x: 1 }] : []);
    }
    if (/^SELECT site_code FROM sites WHERE site_code = \$1 LIMIT 1$/.test(text1)) return ok(Number(params[0]) === SITE ? [{ site_code: String(SITE) }] : []);
    if (/^SELECT enabled FROM site_modules WHERE site_code = \$1 AND module_code = \$2 LIMIT 1$/.test(text1)) return ok([{ enabled: true }]);
    if (/::date::text AS today$/.test(text1)) return ok([{ today: reportToday }]);
    // PUT hedef sorgusu (uçuş anahtarı testi): kapı açılana dek bekletilen kullanıcı; diğerleri hemen "yok"
    if (/^SELECT a\.id, a\.work_item_id, .* INNER JOIN work_items w ON w\.id = a\.work_item_id/.test(text1)) {
      if (visibleGate && params.includes(visibleGate.userCode)) {
        visibleGate.hit = true;
        return visibleGate.promise.then(() => ok([]));
      }
      return ok([]);
    }
    if (/GROUPING\(w\.category\)/.test(text1) || /GROUPING\(category\) AS is_total, COUNT\(\*\)::INTEGER AS resolved/.test(text1) || /FULL OUTER JOIN res_stats/.test(text1)) {
      assert.deepEqual(params.slice(0, 1), [SITE]);
      return ok([]);
    }
    throw new Error(`BEKLENMEYEN SQL (sahte DB katı): ${text1.slice(0, 200)}`);
  }

  before(async () => {
    for (const layer of workTrackingRouter.stack) {
      if (!layer.route) continue;
      layer.route.stack[0].handle = (req, _res, next) => {
        req.authUser = JSON.parse(decodeURIComponent(req.headers['x-test-user']));
        next();
      };
      layer.route.stack[1].handle = (_req, _res, next) => next();
    }
    const app = express();
    app.use(express.json({ limit: '1mb' }));
    app.use(workTrackingRouter);
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
    log = [];
    reportToday = '2026-10-19';
    pool.query = async (text, params) => fakeQuery(text, params);
    pool.connect = async () => {
      throw new Error('işlem açılmamalıydı (doğrulama / yetki hatası veritabanına gitmeden dönmeli)');
    };
  });

  const userHeader = (user) => encodeURIComponent(JSON.stringify(user));

  async function call(method, urlPath, { user, body, headers = {} } = {}) {
    const init = { method, headers: { 'x-test-user': userHeader(user), ...headers } };
    if (body !== undefined) {
      init.body = Buffer.isBuffer(body) ? body : JSON.stringify(body);
      if (!Buffer.isBuffer(body)) init.headers['content-type'] = 'application/json';
    }
    const res = await fetch(`${baseUrl}${urlPath}`, init);
    let json = null;
    try {
      json = await res.json();
    } catch (_error) {
      // gövdesiz
    }
    return { status: res.status, body: json, headers: res.headers };
  }

  /** Başlıkları elle kurulan ham istek (Content-Length iddiası gövdeden bağımsız). */
  function raw({ method, urlPath, user, headers, body = null }) {
    return new Promise((resolve, reject) => {
      const req = http.request(`${baseUrl}${urlPath}`, { method, headers: { 'x-test-user': userHeader(user), ...headers } }, (res) => {
        let text = '';
        res.on('data', (chunk) => { text += chunk; });
        res.on('end', () => {
          let json = null;
          try { json = JSON.parse(text); } catch (_error) { /* gövdesiz */ }
          resolve({ status: res.statusCode, body: json, headers: res.headers });
        });
      });
      req.on('error', (error) => (error.code === 'EPIPE' || error.code === 'ECONNRESET' ? undefined : reject(error)));
      if (body) req.write(body);
      req.end();
    });
  }

  const M = (suffix) => `/manager/sites/${SITE}/work-items${suffix}`;
  const GOOD = { file_name: 'foto.jpg', mime_type: 'image/jpeg', size_bytes: 100 };

  it('kurul: POST / DELETE ek 403 FORBIDDEN_ROLE (yazma kapısı, iş mantığına girmeden); sakin yönetim yolundan 403', async () => {
    const post = await call('POST', M('/5/attachments'), { user: users.board, body: GOOD });
    const del = await call('DELETE', M('/5/attachments/3'), { user: users.board });
    const resident = await call('POST', M('/5/attachments'), { user: users.resident, body: GOOD });
    for (const res of [post, del, resident]) assert.deepEqual([res.status, res.body.code], [403, 'FORBIDDEN_ROLE']);
  });

  it('doğrulama (yönetici + sakin): tür dışı 415, boş boyut 400, 5 MB üstü 413; geçersiz talep / ek kimliği 404; hiçbiri işlem açmaz', async () => {
    for (const user of [users.manager, users.resident]) {
      const base = user === users.manager ? M('/5/attachments') : '/app/work-items/5/attachments';
      assert.deepEqual([(await call('POST', base, { user, body: { ...GOOD, mime_type: 'image/gif' } })).body.code], ['ATTACHMENT_TYPE_NOT_ALLOWED']);
      assert.equal((await call('POST', base, { user, body: { ...GOOD, size_bytes: 0 } })).status, 400);
      const large = await call('POST', base, { user, body: { ...GOOD, size_bytes: ATTACHMENT_MAX_BYTES + 1 } });
      assert.deepEqual([large.status, large.body.code], [413, 'ATTACHMENT_TOO_LARGE']);
      const badItem = await call('POST', base.replace('/5/', '/abc/'), { user, body: GOOD });
      assert.deepEqual([badItem.status, badItem.body.code], [404, 'WORK_ITEM_NOT_FOUND']);
      const badAtt = await call('DELETE', `${base}/xyz`, { user });
      assert.deepEqual([badAtt.status, badAtt.body.code], [404, 'WORK_ATTACHMENT_NOT_FOUND']);
      const badGet = await call('GET', `${base}/xyz/content`, { user });
      assert.deepEqual([badGet.status, badGet.body.code], [404, 'WORK_ATTACHMENT_NOT_FOUND']);
    }
  });

  it('PUT içerik: Content-Type octet-stream değil 415 INVALID_CONTENT_TYPE; chunked / Content-Length yok 411; 0 bayt 400 ATTACHMENT_SIZE_MISMATCH; 5 MB üstü iddia 413 + Connection: close; geçersiz ek 404; uçuş sayacı sıfıra döner', async () => {
    for (const user of [users.manager, users.resident]) {
      const urlPath = user === users.manager ? M('/5/attachments/3/content') : '/app/work-items/5/attachments/3/content';
      const wrongType = await raw({ method: 'PUT', urlPath, user, headers: { 'content-type': 'application/json', 'content-length': '2' }, body: '{}' });
      assert.deepEqual([wrongType.status, wrongType.body.code], [415, 'INVALID_CONTENT_TYPE']);
      const chunked = await raw({ method: 'PUT', urlPath, user, headers: { 'content-type': 'application/octet-stream', 'transfer-encoding': 'chunked' }, body: 'abc' });
      assert.deepEqual([chunked.status, chunked.body.code], [411, 'LENGTH_REQUIRED']);
      const empty = await raw({ method: 'PUT', urlPath, user, headers: { 'content-type': 'application/octet-stream', 'content-length': '0' } });
      assert.deepEqual([empty.status, empty.body.code], [400, 'ATTACHMENT_SIZE_MISMATCH']);
      const huge = await raw({ method: 'PUT', urlPath, user, headers: { 'content-type': 'application/octet-stream', 'content-length': String(ATTACHMENT_MAX_BYTES + 1) } });
      assert.deepEqual([huge.status, huge.body.code, huge.headers.connection], [413, 'ATTACHMENT_TOO_LARGE', 'close']);
      const badAtt = await raw({ method: 'PUT', urlPath: urlPath.replace('/3/', '/abc/'), user, headers: { 'content-type': 'application/octet-stream', 'content-length': '3' }, body: 'abc' });
      assert.deepEqual([badAtt.status, badAtt.body.code], [404, 'WORK_ATTACHMENT_NOT_FOUND']);
    }
    assert.equal(attachmentUploadState.inFlight(), 0);
    assert.equal(attachmentUploadState.active(), 0);
  });

  it('WA-SEC-5 (HTTP): A\'nın yüklemesi sürerken B aynı eke PUT atarsa 409 DEĞİL hedef denetiminde 404 alır; A\'nın ikinci PUT\'u 409 UPLOAD_IN_PROGRESS; sonunda uçuş kümesi boş', async () => {
    const tmpRoot = await fsp.mkdtemp(path.join(os.tmpdir(), 'wa-flight-'));
    const saved = { dir: process.env.DOCUMENTS_DIR, free: process.env.DOCUMENTS_MIN_FREE_BYTES };
    process.env.DOCUMENTS_DIR = tmpRoot;
    process.env.DOCUMENTS_MIN_FREE_BYTES = '0';
    resetStorageCheck();
    let release;
    visibleGate = { userCode: 20004, hit: false, promise: new Promise((resolve) => { release = resolve; }) };
    const other = mk(20009, 'apartment_owner', 'Başka Sakin');
    const urlPath = '/app/work-items/5/attachments/3/content';
    const headers = { 'content-type': 'application/octet-stream', 'content-length': '3' };
    try {
      const first = raw({ method: 'PUT', urlPath, user: users.resident, headers, body: 'abc' });
      for (let i = 0; i < 200 && !visibleGate.hit; i += 1) await new Promise((resolve) => setTimeout(resolve, 5));
      assert.equal(visibleGate.hit, true, 'A hedef sorgusunda bekliyor');
      assert.equal(attachmentUploadState.inFlight(), 1);
      const byOther = await raw({ method: 'PUT', urlPath, user: other, headers, body: 'abc' });
      assert.deepEqual([byOther.status, byOther.body.code], [404, 'WORK_ATTACHMENT_NOT_FOUND'], 'B sahibini engellemez, kendi hedefi yok');
      const again = await raw({ method: 'PUT', urlPath, user: users.resident, headers, body: 'abc' });
      assert.deepEqual([again.status, again.body.code], [409, 'UPLOAD_IN_PROGRESS']);
      release();
      const done = await first;
      assert.deepEqual([done.status, done.body.code], [404, 'WORK_ATTACHMENT_NOT_FOUND']);
      assert.equal(attachmentUploadState.inFlight(), 0);
      assert.equal(attachmentUploadState.active(), 0);
    } finally {
      visibleGate = null;
      if (saved.dir === undefined) delete process.env.DOCUMENTS_DIR; else process.env.DOCUMENTS_DIR = saved.dir;
      if (saved.free === undefined) delete process.env.DOCUMENTS_MIN_FREE_BYTES; else process.env.DOCUMENTS_MIN_FREE_BYTES = saved.free;
      resetStorageCheck();
      await fsp.rm(tmpRoot, { recursive: true, force: true });
    }
  });

  it('rapor: görevli 403 FORBIDDEN_ROLE (rapor sorgusu gitmez); kurul / yönetici 200 (boş sitede sıfırlar, 4 kategori, varsayılan 30 gün); geçersiz tarih 400 INVALID_FIELD', async () => {
    const staff = await call('GET', M('/report'), { user: users.staff });
    assert.deepEqual([staff.status, staff.body.code], [403, 'FORBIDDEN_ROLE']);
    assert.ok(!log.some((entry) => /GROUPING/.test(entry)));
    for (const user of [users.board, users.manager]) {
      const res = await call('GET', M('/report'), { user });
      assert.equal(res.status, 200, JSON.stringify(res.body));
      assert.deepEqual([res.body.from, res.body.to], ['2026-09-20', '2026-10-19']);
      assert.deepEqual(res.body.totals, { opened: 0, resolved: 0, closed: 0, cancelled: 0, open_now: 0, overdue_now: 0, avg_resolution_hours: null, median_resolution_hours: null });
      assert.deepEqual(res.body.by_category.map((row) => row.category), ['ariza', 'bakim', 'sikayet_oneri', 'diger']);
      assert.deepEqual(res.body.by_assignee, []);
    }
    const bad = await call('GET', M('/report?from=2026-13-01'), { user: users.manager });
    assert.deepEqual([bad.status, bad.body.code], [400, 'INVALID_FIELD']);
    const reversed = await call('GET', M('/report?from=2026-10-20&to=2026-10-19'), { user: users.manager });
    assert.deepEqual([reversed.status, reversed.body.code], [400, 'INVALID_FIELD']);
    const tooLong = await call('GET', M('/report?from=2025-01-01&to=2026-10-19'), { user: users.manager });
    assert.deepEqual([tooLong.status, tooLong.body.code], [400, 'INVALID_FIELD']);
  });
});

// --- bakım turları (gerçek geçici dosya sistemi + katı sahte DB) -------------------------------------------------------------------

describe('bakım: work_attachments alt ağacı (bayat yükleme, yetim dosya, silinmiş site dizini)', () => {
  // yetim fotoğraf eşiği 30 gün (WORK_ATTACHMENTS_ORPHAN_MIN_AGE_DAYS): "eski" = 31 gün
  const OLD = new Date(Date.now() - 31 * 86400_000);
  const IDENTITY = '11111111-2222-4333-8444-555555555555';
  let root;
  let handlers;
  let log;
  let settingsStore;
  let aliveSites;
  let tablePresent;
  let knownKeys;
  let siteRecords;
  const keyOf = (name) => `${SITE}/${name}`;
  const uuid = () => crypto.randomUUID();

  function install() {
    const run = async (text, params = []) => {
      const text1 = norm(text);
      log.push({ sql: text1, params });
      for (const [pattern, fn] of handlers) {
        if (pattern.test(text1)) return typeof fn === 'function' ? fn(text1, params) : fn;
      }
      if (/^SELECT pg_try_advisory_lock/.test(text1)) return ok([{ locked: true }]);
      if (/^SELECT pg_advisory_unlock/.test(text1)) return ok();
      if (/^(BEGIN|COMMIT|ROLLBACK)$/.test(text1)) return ok();
      if (/^SELECT value FROM platform_settings WHERE key = \$1 LIMIT 1$/.test(text1)) return ok(settingsStore.has(params[0]) ? [{ value: settingsStore.get(params[0]) }] : []);
      if (/^SELECT site_code FROM sites WHERE site_code = ANY\(\$1::BIGINT\[\]\)$/.test(text1)) return ok(params[0].filter((code) => aliveSites.has(Number(code))).map((code) => ({ site_code: String(code) })));
      if (/^SELECT COUNT\(\*\)::INTEGER AS n FROM sites$/.test(text1)) return ok([{ n: aliveSites.size }]);
      if (/^SELECT to_regclass\('public\.work_item_attachments'\) IS NOT NULL AS present$/.test(text1)) return ok([{ present: tablePresent }]);
      if (/^SELECT storage_key FROM work_item_attachments WHERE storage_key = ANY\(\$1::TEXT\[\]\)$/.test(text1)) return ok(params[0].filter((key) => knownKeys.has(key)).map((storage_key) => ({ storage_key })));
      if (/^SELECT 1 FROM work_item_attachments WHERE site_code = \$1 LIMIT 1$/.test(text1)) return ok(siteRecords.has(Number(params[0])) ? [{ x: 1 }] : []);
      if (/^SELECT to_regclass\('public\.expense_documents'\)/.test(text1)) return ok([{ present: false }]);
      if (/^(SELECT|DELETE)/.test(text1)) return ok();
      throw new Error(`BEKLENMEYEN SQL (sahte DB katı): ${text1.slice(0, 240)}`);
    };
    pool.connect = async () => Object.assign(new EventEmitter(), { query: (text, params) => run(text, params), release() {} });
    pool.query = async (text, params) => run(text, params);
  }

  before(async () => {
    root = await fsp.mkdtemp(path.join(os.tmpdir(), 'wa-maintenance-'));
    process.env.DOCUMENTS_DIR = root;
    process.env.DOCUMENTS_MIN_FREE_BYTES = '0';
    resetStorageCheck();
    assert.equal((await checkStorage({ DOCUMENTS_DIR: root }, { force: true })).ok, true);
  });

  after(async () => {
    delete pool.query;
    delete pool.connect;
    delete process.env.DOCUMENTS_DIR;
    delete process.env.DOCUMENTS_MIN_FREE_BYTES;
    resetStorageCheck();
    await fsp.rm(root, { recursive: true, force: true });
  });

  beforeEach(async () => {
    handlers = [];
    log = [];
    settingsStore = new Map([['documents.storage_id', { id: IDENTITY }]]);
    aliveSites = new Set([SITE]);
    tablePresent = true;
    knownKeys = new Set();
    siteRecords = new Set();
    install();
    await fsp.rm(path.join(root, ATTACHMENT_SUBTREE), { recursive: true, force: true });
    await fsp.rm(path.join(root, '_orphans'), { recursive: true, force: true });
    await ensureSiteDir(root, SITE, ATTACHMENT_SUBTREE);
    await fsp.writeFile(path.join(root, '.instance'), `${IDENTITY}\n`);
  });

  const files = async () => (await fsp.readdir(path.join(root, ATTACHMENT_SUBTREE, String(SITE)))).sort();
  async function plant(count, { age = OLD } = {}) {
    const names = [];
    for (let i = 0; i < count; i += 1) {
      const name = uuid();
      const full = pathForKey(root, keyOf(name), ATTACHMENT_SUBTREE);
      await fsp.writeFile(full, 'yetim');
      await fsp.utimes(full, age, age);
      names.push(name);
    }
    return names;
  }

  it('yetim (30 günden eski, DB\'de satırsız) fotoğraf SİLİNİR (karantina yok); 25 günlük ve genç yetim, kayıtlı dosya KORUNUR; belge karantinasına girmez; eşik env ile değişir', async () => {
    const [orphan] = await plant(1);
    const [young] = await plant(1, { age: new Date() });
    const [recent] = await plant(1, { age: new Date(Date.now() - 25 * 86400_000) });
    const [known] = await plant(1);
    knownKeys.add(keyOf(known));
    const result = await runDocumentsMaintenanceOnce();
    assert.equal(result.summary.attachment_orphans, 1);
    assert.equal(result.summary.orphan_files, 0, 'belge sayacı artmaz');
    assert.deepEqual(await files(), [known, recent, young].sort());
    assert.ok(!(await files()).includes(orphan));
    await assert.rejects(fsp.stat(path.join(root, '_orphans')), { code: 'ENOENT' });
    const shorter = await runDocumentsMaintenanceOnce({ env: { ...process.env, WORK_ATTACHMENTS_ORPHAN_MIN_AGE_DAYS: '20' } });
    assert.equal(shorter.summary.attachment_orphans, 1, 'WORK_ATTACHMENTS_ORPHAN_MIN_AGE_DAYS=20: 25 günlük de silinir');
    assert.deepEqual(await files(), [known, young].sort());
  });

  it('tablo yoksa (047 kurulmamış) HİÇBİR fotoğraf dosyasına dokunulmaz; DB sorgusu hata verirse hiçbiri silinmez', async () => {
    const names = await plant(3);
    tablePresent = false;
    let result = await runDocumentsMaintenanceOnce();
    assert.equal(result.summary.attachment_orphans, 0);
    assert.deepEqual(await files(), [...names].sort());
    tablePresent = true;
    handlers.push([/^SELECT storage_key FROM work_item_attachments WHERE storage_key = ANY/, () => { throw Object.assign(new Error('koptu'), { code: '57P01' }); }]);
    const realError = console.error;
    console.error = () => {};
    try {
      result = await runDocumentsMaintenanceOnce();
    } finally {
      console.error = realError;
    }
    assert.equal(result.summary.attachment_orphans, 0);
    assert.ok(result.summary.errors >= 1);
    assert.deepEqual(await files(), [...names].sort());
  });

  it('ORAN KORUMASI: yetim > 20 ve > %50 ise hiçbiri silinmez; depolama kimliği uyuşmazsa süpürme çalışmaz ama bayat satır turu çalışır', async () => {
    const known = await plant(5);
    await plant(25);
    for (const name of known) knownKeys.add(keyOf(name));
    const realError = console.error;
    const lines = [];
    console.error = (...args) => lines.push(args.join(' '));
    let result;
    try {
      result = await runDocumentsMaintenanceOnce();
      assert.equal(result.summary.attachment_orphans, 0);
      assert.ok(result.summary.guard_trips >= 1);
      assert.equal((await files()).length, 30);
      assert.ok(lines.some((line) => /fotograf dosyasi yetim gorunuyor/.test(line)));
      settingsStore.set('documents.storage_id', { id: '99999999-2222-4333-8444-555555555555' });
      log.length = 0;
      result = await runDocumentsMaintenanceOnce();
    } finally {
      console.error = realError;
    }
    assert.equal(result.summary.identity_blocked, 1);
    assert.equal((await files()).length, 30);
    assert.ok(log.some((entry) => /FROM work_item_attachments WHERE status = 'uploading'/.test(entry.sql)), 'DB\'den-gelen tur çalıştı');
    assert.ok(!log.some((entry) => /storage_key = ANY/.test(entry.sql)));
  });

  it('bayat `uploading` satır: ÖNCE SATIR (RETURNING), silindiyse SONRA dosya (work_attachments alt ağacından); DELETE 0 satırsa dosyaya dokunulmaz', async () => {
    const [stale] = await plant(1, { age: new Date() });
    const [raced] = await plant(1, { age: new Date() });
    let fileAtRowDelete = null;
    handlers.push(
      [/^SELECT id, storage_key FROM work_item_attachments WHERE status = 'uploading' AND created_at < NOW\(\) - make_interval\(mins => \$1::INTEGER\)/, ok([{ id: '5', storage_key: keyOf(stale) }, { id: '6', storage_key: keyOf(raced) }])],
      [
        /^DELETE FROM work_item_attachments WHERE id = \$1 AND status = 'uploading' AND created_at < NOW\(\) - make_interval\(mins => \$2::INTEGER\) RETURNING storage_key$/,
        async (_sql, params) => {
          if (Number(params[0]) === 6) return ok([], 0);
          fileAtRowDelete = (await files()).includes(stale);
          return ok([{ storage_key: keyOf(stale) }], 1);
        },
      ],
    );
    const result = await runDocumentsMaintenanceOnce();
    assert.equal(result.summary.attachment_stale_uploads, 1);
    assert.equal(fileAtRowDelete, true, 'satır silinirken dosya HENÜZ yerinde');
    assert.deepEqual(await files(), [raced]);
    const del = log.find((entry) => /^DELETE FROM work_item_attachments/.test(entry.sql));
    assert.deepEqual(del.params, ['5', 120], 'TTL 120 dk DELETE\'te tekrar sınanır');
  });

  it('silinmiş sitenin work_attachments/<kod> dizini 7 gün sonra silinir (kaydı kalmamışsa); yaşayan / yeni / kayıtlı siteye dokunulmaz; DB\'de hiç site yokken silinmez', async () => {
    const eightDays = new Date(Date.now() - 8 * 86400_000);
    const plantSiteDir = async (code, { old = true } = {}) => {
      await ensureSiteDir(root, code, ATTACHMENT_SUBTREE);
      const dir = path.join(root, ATTACHMENT_SUBTREE, String(code));
      const file = path.join(dir, uuid());
      await fsp.writeFile(file, 'x');
      if (old) {
        await fsp.utimes(file, eightDays, eightDays);
        await fsp.utimes(dir, eightDays, eightDays);
      }
      return dir;
    };
    const exists = (dir) => fsp.stat(dir).then(() => true, () => false);
    const stale = await plantSiteDir(1999999990);
    const recent = await plantSiteDir(1999999991, { old: false });
    const withRecord = await plantSiteDir(1999999992);
    siteRecords.add(1999999992);
    for (let i = 0; i < 5; i += 1) {
      aliveSites.add(1000000100 + i);
      await ensureSiteDir(root, 1000000100 + i, ATTACHMENT_SUBTREE);
    }
    const result = await runDocumentsMaintenanceOnce();
    assert.equal(result.summary.attachment_site_dirs, 1);
    assert.equal(await exists(stale), false);
    assert.equal(await exists(recent), true);
    assert.equal(await exists(withRecord), true);
    assert.equal(await exists(path.join(root, ATTACHMENT_SUBTREE, String(SITE))), true);
    const ghost = await plantSiteDir(1999999993);
    aliveSites.clear();
    const realError = console.error;
    console.error = () => {};
    let empty;
    try {
      empty = await runDocumentsMaintenanceOnce();
    } finally {
      console.error = realError;
    }
    assert.ok(empty.summary.guard_trips >= 1);
    assert.equal(await exists(ghost), true);
  });

  it('seyrek alt ağaç koruması: 3 fotoğraf site dizininden 2\'si silinmiş siteye aitse KALDIRILIR (belge kuralı durdururdu); > 5 VE > %50 durdurur; boş DB her zaman durdurur', async () => {
    assert.equal(attachmentSiteDirGuardTripped({ removable: 2, totalDirs: 3, siteCount: 10 }), false);
    assert.equal(attachmentSiteDirGuardTripped({ removable: 5, totalDirs: 6, siteCount: 10 }), false, 'tam 5: aşılmadı');
    assert.equal(attachmentSiteDirGuardTripped({ removable: 6, totalDirs: 8, siteCount: 10 }), true);
    assert.equal(attachmentSiteDirGuardTripped({ removable: 6, totalDirs: 20, siteCount: 10 }), false, '%30');
    assert.equal(attachmentSiteDirGuardTripped({ removable: 1, totalDirs: 1, siteCount: 0 }), true, 'boş DB');
    assert.equal(attachmentSiteDirGuardTripped({ removable: 0, totalDirs: 3, siteCount: 0 }), false);
    const eightDays = new Date(Date.now() - 8 * 86400_000);
    const exists = (dir) => fsp.stat(dir).then(() => true, () => false);
    const dirs = [];
    for (const code of [1999999970, 1999999971]) {
      await ensureSiteDir(root, code, ATTACHMENT_SUBTREE);
      const dir = path.join(root, ATTACHMENT_SUBTREE, String(code));
      const file = path.join(dir, uuid());
      await fsp.writeFile(file, 'x');
      await fsp.utimes(file, eightDays, eightDays);
      await fsp.utimes(dir, eightDays, eightDays);
      dirs.push(dir);
    }
    const result = await runDocumentsMaintenanceOnce();
    assert.equal(result.summary.attachment_site_dirs, 2, '2 / 3 silinmiş dizin kaldırıldı');
    assert.equal(result.summary.guard_trips, 0);
    for (const dir of dirs) assert.equal(await exists(dir), false);
  });
});
