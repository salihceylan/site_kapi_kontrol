// Migration 051 (KVKK m.12): daire PIN'i düz metin SAKLANMAZ. PIN yalnız users.password_hash'te bcrypt özetidir (girişte yalnız o doğrular);
// oluşturma / sıfırlama yanıtında BİR KEZ döner ve e-posta varsa bir kez gönderilir; apartments.resident_pin_issued yalnız işarettir.
// Kapsam: migration = şema modülü (birebir, aynı sıra), açılış aktarımı (partili, SKIP LOCKED, idempotent, hatası açılışı durdurmaz), API biçimi
// (mapApartmentRow), oluşturma / sıfırlama / e-posta servisleri, HTTP uçları (reset-pin, eski send-credentials 409). Gerçek PG: qa_apartment_pin_section.mjs.
import { describe, it, before, after, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import bcrypt from 'bcryptjs';
import express from 'express';
import nodemailer from 'nodemailer';
import { pool } from '../src/db.js';
import {
  APARTMENT_PIN_BACKFILL_BATCH_SQL,
  APARTMENT_PIN_DDL,
  APARTMENT_PIN_DDL_ORDER,
  apartmentPinTuning,
  ensureApartmentPinSchema,
  runApartmentPinBackfill,
} from '../src/modules/apartment_pin_schema.js';
import {
  APARTMENT_PIN_ERROR_MESSAGES,
  APARTMENT_PIN_NOT_STORED_MESSAGE,
  apartmentPinMailTuning,
  apartmentPinResetBody,
  provisionApartmentResident,
  resetApartmentPin,
  sendApartmentCredentials,
  sendIssuedApartmentPin,
} from '../src/services/apartment_service.js';
import { mapApartmentRow } from '../src/utils/helpers.js';
import { BCRYPT_COST, bcryptCostOf } from '../src/security/password_hashing.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const serverRoot = path.join(here, '..');
const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
const read = (rel) => fs.readFileSync(path.join(serverRoot, rel), 'utf8');

/** Betikli sahte bağlantı: [regex, yanıt | (sql, params) => yanıt]; eşleşmeyen sorgu boş sonuç alır. Tüm sorgular günlüğe yazılır. */
function scriptedClient(handlers = []) {
  const log = [];
  return {
    log,
    async query(text, params = []) {
      const sql = norm(typeof text === 'string' ? text : text?.text);
      log.push({ sql, params });
      for (const [pattern, reply] of handlers) {
        if (pattern.test(sql)) {
          const result = typeof reply === 'function' ? await reply(sql, params) : reply;
          return { rowCount: result?.rows?.length ?? 0, rows: [], ...result };
        }
      }
      return { rowCount: 0, rows: [] };
    },
    release() {},
  };
}

const rowsOf = (rows) => ({ rowCount: rows.length, rows });

describe('051 şema: migration = apartment_pin_schema (birebir, aynı sıra)', () => {
  it('migration dosyasının ifadeleri APARTMENT_PIN_DDL ile aynı ve aynı sırada; ikinci özet sütunu YOK', () => {
    const sql = read('migrations/051_apartment_pin_hash.sql')
      .split(/\r?\n/)
      .filter((line) => !line.trim().startsWith('--'))
      .join('\n');
    const statements = sql.split(';').map(norm).filter(Boolean);
    assert.deepEqual(statements, APARTMENT_PIN_DDL_ORDER.map((name) => norm(APARTMENT_PIN_DDL[name])));
    assert.doesNotMatch(sql, /pin_hash|password_hash|crypt\(/i, 'aynı 4 haneli sırrın ikinci bir özeti tutulmaz');
  });

  it('sütun sabit varsayılanlı NOT NULL (PG 11+ yalnız katalog; tablo yeniden yazılmaz); aktarım düz kopyayı NULL yapar, işareti korur/kurar', () => {
    assert.equal(norm(APARTMENT_PIN_DDL.issuedColumn), 'ALTER TABLE apartments ADD COLUMN IF NOT EXISTS resident_pin_issued BOOLEAN NOT NULL DEFAULT FALSE');
    assert.match(APARTMENT_PIN_DDL.backfill, /resident_pin_code = NULL WHERE resident_pin_code IS NOT NULL$/);
    assert.match(APARTMENT_PIN_DDL.backfill, /resident_pin_issued = \(resident_pin_issued OR btrim\(resident_pin_code\) <> ''\)/);
  });

  it('partili aktarım: anahtar kümesi sırası, kilitli satırı ATLAR (FOR NO KEY UPDATE SKIP LOCKED), yalnız id döner (PIN okunmaz)', () => {
    const batch = norm(APARTMENT_PIN_BACKFILL_BATCH_SQL);
    assert.match(batch, /WHERE resident_pin_code IS NOT NULL AND id > \$2 ORDER BY id LIMIT \$1 FOR NO KEY UPDATE SKIP LOCKED/);
    assert.match(batch, /RETURNING a\.id$/);
    assert.match(batch, /SET resident_pin_issued = \(a\.resident_pin_issued OR btrim\(a\.resident_pin_code\) <> ''\), resident_pin_code = NULL/);
  });

  it('db.js 051 modülünü 050\'den SONRA çağırır', () => {
    const db = read('src/db.js');
    assert.ok(db.includes("import { ensureApartmentPinSchema } from './modules/apartment_pin_schema.js';"));
    assert.ok(db.indexOf('await ensureApartmentPinSchema(client);') > db.indexOf('await ensureDecisionBookSchema(client);'));
  });
});

describe('051 açılış: ensureApartmentPinSchema + runApartmentPinBackfill', () => {
  const saved = { ...apartmentPinTuning };
  let errors;
  const originalError = console.error;
  const originalLog = console.log;
  beforeEach(() => {
    Object.assign(apartmentPinTuning, { retryDelayMs: 1, passDelayMs: 1, batchSize: 2, maxPasses: 3 });
    errors = [];
    console.error = (...args) => errors.push(args.map(String).join(' '));
    console.log = () => {};
  });
  afterEach(() => {
    Object.assign(apartmentPinTuning, saved);
    console.error = originalError;
    console.log = originalLog;
  });

  const catalog = (state) => [/^SELECT to_regclass\('public\.apartments'\) IS NOT NULL AS has_table/, rowsOf([state])];

  it('normal açılış (sütun var, düz PIN yok): yalnız iki okuma; ALTER / UPDATE / lock_timeout YOK', async () => {
    const client = scriptedClient([
      catalog({ has_table: true, has_column: true, has_plain_column: true }),
      [/^SELECT EXISTS \(SELECT 1 FROM apartments WHERE resident_pin_code IS NOT NULL\) AS pending$/, rowsOf([{ pending: false }])],
    ]);
    await ensureApartmentPinSchema(client);
    assert.equal(client.log.length, 2, client.log.map((e) => e.sql).join(' | '));
    assert.equal(client.log.some((e) => /^(ALTER|UPDATE|SET)/.test(e.sql)), false);
  });

  it('ilk dağıtım: ALTER lock_timeout altında; düz PIN partilerle silinir, son id ilerler; RESET lock_timeout', async () => {
    const pending = [11, 12, 15, 20, 21];
    const client = scriptedClient([
      catalog({ has_table: true, has_column: false, has_plain_column: true }),
      [/^SELECT EXISTS/, () => rowsOf([{ pending: pending.length > 0 }])],
      [/^WITH batch AS/, (_sql, [limit, lastId]) => {
        const picked = pending.filter((id) => id > lastId).slice(0, limit);
        for (const id of picked) pending.splice(pending.indexOf(id), 1);
        return rowsOf(picked.map((id) => ({ id })));
      }],
    ]);
    await ensureApartmentPinSchema(client);
    const sqls = client.log.map((e) => e.sql);
    assert.equal(sqls[2], "SET lock_timeout = '2s'");
    assert.equal(sqls[3], norm(APARTMENT_PIN_DDL.issuedColumn));
    const batches = client.log.filter((e) => e.sql.startsWith('WITH batch AS'));
    assert.deepEqual(batches.map((e) => e.params), [[2, 0], [2, 12], [2, 20], [2, 21]]);
    assert.equal(pending.length, 0);
    assert.equal(sqls.at(-1), 'RESET lock_timeout');
    assert.deepEqual(errors, []);
  });

  it('ikinci çalıştırma no-op: düz PIN kalmadıysa hiçbir parti UPDATE\'i yok (idempotent)', async () => {
    const client = scriptedClient([[/^SELECT EXISTS/, rowsOf([{ pending: false }])]]);
    assert.deepEqual(await runApartmentPinBackfill(client), { converted: 0, remaining: false });
    assert.equal(client.log.some((e) => e.sql.startsWith('WITH batch AS')), false);
  });

  it('55P03 / 40P01 yeniden denenir; kilitli kalan satır "remaining" olarak bildirilir (sonraki açılışta tamamlanır)', async () => {
    let failures = 2;
    const client = scriptedClient([
      [/^SELECT EXISTS/, rowsOf([{ pending: true }])],
      [/^WITH batch AS/, () => {
        if (failures > 0) {
          failures -= 1;
          throw Object.assign(new Error('kilit'), { code: failures === 1 ? '55P03' : '40P01' });
        }
        return rowsOf([]);
      }],
    ]);
    const result = await runApartmentPinBackfill(client);
    assert.deepEqual(result, { converted: 0, remaining: true });
    assert.equal(client.log.filter((e) => e.sql.startsWith('WITH batch AS')).length, 2 + apartmentPinTuning.maxPasses);
  });

  it('aktarım hatası açılışı DURDURMAZ (günlüğe yalnız kod yazılır), lock_timeout yine sıfırlanır', async () => {
    const client = scriptedClient([
      catalog({ has_table: true, has_column: true, has_plain_column: true }),
      [/^SELECT EXISTS/, rowsOf([{ pending: true }])],
      [/^WITH batch AS/, () => { throw Object.assign(new Error('gizli ayrinti 4821'), { code: 'XX000' }); }],
    ]);
    await ensureApartmentPinSchema(client);
    assert.equal(client.log.at(-1).sql, 'RESET lock_timeout');
    assert.equal(errors.length, 1);
    assert.match(errors[0], /051 daire PIN aktarimi basarisiz.*XX000/);
    assert.doesNotMatch(errors[0], /4821/);
  });

  it('ALTER hatası (55P03 dışı) açılışı durdurur (diğer şema modülleriyle aynı)', async () => {
    const client = scriptedClient([
      catalog({ has_table: true, has_column: false, has_plain_column: true }),
      [/^SELECT EXISTS/, rowsOf([{ pending: false }])],
      [/^ALTER TABLE apartments/, () => { throw Object.assign(new Error('yetki'), { code: '42501' }); }],
    ]);
    await assert.rejects(() => ensureApartmentPinSchema(client), (error) => error.code === '42501');
    assert.equal(client.log.at(-1).sql, 'RESET lock_timeout');
  });
});

describe('API biçimi: mapApartmentRow', () => {
  const base = { id: '3', site_code: '101', block_id: '1', block_name: 'A Blok', unit_label: 'Daire 3', sort_order: 3, is_active: true, resident_user_code: 40001 };

  it('veritabanı sütunu resident_pin_code ASLA API\'ye gitmez (eski bir sürecin yazdığı kopya bile); yalnız bu yanıtta verilen PIN', () => {
    const listed = mapApartmentRow({ ...base, resident_pin_code: '4821', resident_pin_issued: true, resident_pin_resettable: true });
    assert.equal(listed.resident_pin_code, null);
    assert.equal(listed.resident_pin_issued, true);
    assert.equal(listed.resident_pin_resettable, true);
    const issued = mapApartmentRow({ ...base, issued_pin_code: '7305', resident_pin_issued: true });
    assert.equal(issued.resident_pin_code, '7305');
    assert.equal(issued.resident_pin_resettable, false);
  });

  it('eski istemci uyumu: alan adı korunur (null), yeni alanlar boolean', () => {
    const row = mapApartmentRow({ ...base });
    assert.ok(Object.hasOwn(row, 'resident_pin_code'));
    assert.equal(row.resident_pin_code, null);
    assert.equal(row.resident_pin_issued, false);
    assert.equal(row.resident_pin_resettable, false);
  });
});

describe('servisler: oluşturma / sıfırlama / e-posta', () => {
  const sent = [];
  const savedEnv = {};
  const originalCreateTransport = nodemailer.createTransport;
  const originalError = console.error;
  let client;

  beforeEach(() => {
    sent.length = 0;
    for (const name of ['SMTP_HOST', 'SMTP_USER', 'SMTP_PASSWORD', 'SMTP_FROM', 'SMTP_PORT']) savedEnv[name] = process.env[name];
    Object.assign(process.env, { SMTP_HOST: 'smtp.invalid', SMTP_USER: 'user@example.invalid', SMTP_PASSWORD: 'test-only', SMTP_FROM: 'Sistem <noreply@example.invalid>' });
    delete process.env.SMTP_PORT;
    nodemailer.createTransport = () => ({ sendMail: async (message) => void sent.push(message) });
    console.error = () => {};
  });
  afterEach(() => {
    nodemailer.createTransport = originalCreateTransport;
    for (const [name, value] of Object.entries(savedEnv)) {
      if (value === undefined) delete process.env[name];
      else process.env[name] = value;
    }
    console.error = originalError;
    delete pool.connect;
    delete pool.query;
  });

  const snapshotRow = { id: '3', site_code: '101', unit_label: 'Daire 3', resident_email: 'ayse@example.com', block_name: 'A Blok', site_name: 'Gül Sitesi', resident_full_name: 'Ayşe', resident_login_name: '101_A_Daire3' };
  const SNAPSHOT = /^SELECT a\.id, a\.site_code, a\.unit_label, a\.resident_email, b\.block_name, s\.name AS site_name/;

  it('yeni sakin: PIN users.password_hash\'e bcrypt (BCRYPT_COST) ile yazılır; daire satırına PIN YAZILMAZ; dönüşte bir kez issued_pin_code', async () => {
    client = scriptedClient([
      [/^SELECT a\.id, a\.site_code, a\.resident_user_code, a\.resident_email, b\.block_name/, rowsOf([{ id: 3, site_code: 101, resident_user_code: null, resident_email: null, block_name: 'A Blok', unit_label: 'Daire 3', sort_order: 3 }])],
      [/^INSERT INTO users/, rowsOf([{ id: 40001 }])],
      [/^SELECT a\.id, a\.site_code, a\.block_id, b\.block_name/, rowsOf([{ id: 3, site_code: 101, resident_user_code: 40001, resident_pin_issued: true, resident_pin_resettable: true }])],
    ]);
    pool.connect = async () => client;
    const row = await provisionApartmentResident({ apartmentId: 3, fullName: 'Ayşe', loginName: '', password: '5803', email: null, phoneNumber: null, isActive: true });
    assert.equal(row.issued_pin_code, '5803');
    const insert = client.log.find((e) => e.sql.startsWith('INSERT INTO users'));
    assert.equal(bcryptCostOf(insert.params[8]), BCRYPT_COST);
    assert.equal(await bcrypt.compare('5803', insert.params[8]), true, 'giriş özeti PIN\'i doğrular');
    const aptUpdate = client.log.find((e) => e.sql.startsWith('UPDATE apartments SET resident_user_code = $1'));
    assert.match(aptUpdate.sql, /resident_pin_issued = TRUE, resident_pin_code = NULL/);
    assert.equal(aptUpdate.params.includes('5803'), false, 'PIN daire satırına yazılmaz');
    const finalSelect = client.log.find((e) => e.sql.startsWith('SELECT a.id, a.site_code, a.block_id'));
    assert.doesNotMatch(finalSelect.sql, /resident_pin_code/);
    assert.equal(client.log.some((e) => e.params.includes('5803')), false, 'PIN hiçbir sorguya düz metin gitmez');
    const api = mapApartmentRow(row);
    assert.equal(api.resident_pin_code, '5803');
    assert.equal(api.resident_pin_issued, true);
  });

  it('mevcut sakin düzenlemesi: PIN verilmez (issued_pin_code null)', async () => {
    client = scriptedClient([
      [/^SELECT a\.id, a\.site_code, a\.resident_user_code, a\.resident_email, b\.block_name/, rowsOf([{ id: 3, site_code: 101, resident_user_code: 40001, resident_email: null, block_name: 'A Blok', unit_label: 'Daire 3', sort_order: 3 }])],
      [/^SELECT email FROM users WHERE user_code = \$1/, rowsOf([{ email: 'x.3.101@ahbu.local' }])],
      [/^SELECT a\.id, a\.site_code, a\.block_id, b\.block_name/, rowsOf([{ id: 3, site_code: 101, resident_user_code: 40001 }])],
    ]);
    pool.connect = async () => client;
    const row = await provisionApartmentResident({ apartmentId: 3, fullName: 'Ayşe', loginName: 'ayse', password: '', email: undefined, phoneNumber: null, isActive: true });
    assert.equal(row.issued_pin_code, null);
    assert.equal(mapApartmentRow(row).resident_pin_code, null);
  });

  const RESET_LOCK = /^SELECT id, site_code, resident_user_code, resident_email, resident_pin_issued FROM apartments WHERE id = \$1 LIMIT 1 FOR UPDATE$/;
  const RESET_USER = /^UPDATE users SET password_hash = \$1, updated_at = NOW\(\) WHERE user_code = \$2 AND deleted_at IS NULL AND LOWER\(email\) LIKE \$3/;
  const resetClient = ({ issued = true, email = 'ayse@example.com', internal = true } = {}) => scriptedClient([
    [RESET_LOCK, rowsOf([{ id: 3, site_code: 101, resident_user_code: 40001, resident_email: email, resident_pin_issued: issued }])],
    [RESET_USER, internal ? rowsOf([{ user_code: 40001, login_name: '101_A_Daire3', email: 'x.3.101@ahbu.local' }]) : rowsOf([])],
    [/^UPDATE guest_passes SET is_active = FALSE WHERE created_by_user_code = \$1 AND is_active = TRUE$/, { rowCount: 2, rows: [] }],
    [/^UPDATE qr_access_tokens SET is_active = FALSE, revoked_at = NOW\(\) WHERE user_code = \$1 AND is_active = TRUE AND revoked_at IS NULL$/, { rowCount: 1, rows: [] }],
    [/^SELECT to_regclass\('public\.push_devices'\)/, rowsOf([{ has_devices: true, has_outbox: true }])],
    [/^DELETE FROM push_devices WHERE id IN/, { rowCount: 3, rows: [] }],
    [/^DELETE FROM push_outbox WHERE id IN/, { rowCount: 4, rows: [] }],
    [/^SELECT a\.id, a\.site_code, a\.block_id, b\.block_name/, rowsOf([{ id: 3, site_code: 101, block_id: 1, block_name: 'A Blok', unit_label: 'Daire 3', sort_order: 3, resident_user_code: 40001, resident_email: email, resident_pin_issued: true, resident_pin_resettable: true }])],
  ]);
  const manager = { user_code: 7, role: 'site_manager', full_name: 'Yönetici' };
  const carriesPin = (log, pin) => log.some((e) => e.params.some((p) => new RegExp(`\\b${pin}\\b`).test(typeof p === 'string' ? p : JSON.stringify(p))));

  it('resetApartmentPin (yönetimin verdiği PIN): yeni 4 haneli PIN yalnız özet; işaret; JWT dışı erişim AYNI işlemde kapanır; audit PIN\'siz; kilit sırası', async () => {
    client = resetClient();
    pool.connect = async () => client;
    const { apartment, pinCode, delivery, revoked } = await resetApartmentPin(3, { actor: manager });
    assert.match(pinCode, /^[1-9]\d{3}$/);
    assert.equal(delivery, 'shown');
    const sqls = client.log.map((e) => e.sql);
    assert.equal(sqls[0], 'BEGIN');
    const at = (re) => sqls.findIndex((s) => re.test(s));
    const lockAt = at(RESET_LOCK);
    const userAt = at(RESET_USER);
    assert.ok(lockAt > 0 && lockAt < userAt, 'önce daire satırı kilitlenir');
    const userUpdate = client.log[userAt];
    assert.equal(bcryptCostOf(userUpdate.params[0]), BCRYPT_COST);
    assert.equal(await bcrypt.compare(pinCode, userUpdate.params[0]), true);
    assert.equal(userUpdate.params[2], '%@ahbu.local', 'yalnız dahili daire hesabı');
    assert.ok(sqls.includes('UPDATE apartments SET resident_pin_issued = TRUE, resident_pin_code = NULL WHERE id = $1'));
    // JWT dışı erişim: misafir geçişleri pasif, karekodlar iptal, bildirim cihaz/kuyruk kayıtları silinir; hepsi users'tan SONRA ve COMMIT'ten ÖNCE.
    const commitAt = sqls.lastIndexOf('COMMIT');
    for (const re of [/^UPDATE guest_passes SET is_active = FALSE/, /^UPDATE qr_access_tokens SET is_active = FALSE/, /^DELETE FROM push_devices/, /^DELETE FROM push_outbox/]) {
      const i = at(re);
      assert.ok(i > userAt && i < commitAt, `${re} aynı işlemde`);
      assert.deepEqual(client.log[i].params, [40001]);
    }
    assert.deepEqual(revoked, { guest_passes: 2, qr_tokens: 1, push_devices: 3, push_outbox: 4 });
    const auditInsert = client.log.find((e) => e.sql.startsWith('INSERT INTO audit_log'));
    assert.equal(auditInsert.params[3], 'apartment.pin_reset');
    assert.deepEqual(JSON.parse(auditInsert.params[7]), { delivery: 'shown', guest_passes: 2, qr_tokens: 1, push_devices: 3, push_outbox: 4 });
    assert.equal(sqls.at(-1), 'COMMIT');
    assert.equal(carriesPin(client.log, pinCode), false, 'PIN hiçbir sorguya / audit\'e düz metin gitmez');
    assert.equal(apartment.issued_pin_code, pinCode);
    assert.equal(mapApartmentRow(apartment).resident_pin_code, pinCode);
  });

  it('resetApartmentPin (sakin KENDİ parolasını belirlemiş, yönetici): PIN yalnız e-postaya (email_only), API satırında PIN YOK', async () => {
    client = resetClient({ issued: false });
    pool.connect = async () => client;
    const { apartment, pinCode, delivery } = await resetApartmentPin(3, { actor: manager });
    assert.equal(delivery, 'email_only');
    assert.match(pinCode, /^\d{4}$/, 'e-posta için servis içinde bilinir');
    assert.equal(apartment.issued_pin_code, null);
    assert.equal(mapApartmentRow(apartment).resident_pin_code, null);
    assert.equal(client.log.at(-1).sql, 'COMMIT');
    const auditInsert = client.log.find((e) => e.sql.startsWith('INSERT INTO audit_log'));
    assert.equal(JSON.parse(auditInsert.params[7]).delivery, 'email_only');
  });

  it('resetApartmentPin (sakin kendi parolası + e-posta YOK): yönetici 409 APARTMENT_PIN_RESET_NEEDS_SUPER (parola değişikliği geri alınır); süper kullanıcı PIN\'i görür', async () => {
    client = resetClient({ issued: false, email: null });
    pool.connect = async () => client;
    await assert.rejects(
      () => resetApartmentPin(3, { actor: manager }),
      (error) => error.statusCode === 409 && error.code === 'APARTMENT_PIN_RESET_NEEDS_SUPER' && error.message === APARTMENT_PIN_ERROR_MESSAGES.APARTMENT_PIN_RESET_NEEDS_SUPER,
    );
    assert.equal(client.log.at(-1).sql, 'ROLLBACK');
    assert.equal(client.log.some((e) => e.sql === 'COMMIT' || e.sql.startsWith('UPDATE guest_passes') || e.sql.startsWith('UPDATE apartments')), false);

    client = resetClient({ issued: false, email: '   ' });
    pool.connect = async () => client;
    await assert.rejects(() => resetApartmentPin(3, { actor: manager }), (error) => error.code === 'APARTMENT_PIN_RESET_NEEDS_SUPER', 'yalnız boşluk = adres yok');

    client = resetClient({ issued: false, email: null });
    pool.connect = async () => client;
    const asSuper = await resetApartmentPin(3, { actor: { user_code: 1, role: 'super_user' }, actorIsSuper: true });
    assert.equal(asSuper.delivery, 'shown');
    assert.equal(asSuper.apartment.issued_pin_code, asSuper.pinCode);
  });

  it('resetApartmentPin: kayıtlı (dahili olmayan) hesap 409 APARTMENT_PIN_NOT_RESETTABLE (e-posta kuralından ÖNCE); sakin yoksa 409 APARTMENT_PIN_NO_ACCOUNT; ROLLBACK', async () => {
    client = resetClient({ internal: false, issued: false, email: null });
    pool.connect = async () => client;
    await assert.rejects(() => resetApartmentPin(3, { actor: manager }), (error) => error.statusCode === 409 && error.code === 'APARTMENT_PIN_NOT_RESETTABLE' && error.message === APARTMENT_PIN_ERROR_MESSAGES.APARTMENT_PIN_NOT_RESETTABLE);
    assert.equal(client.log.at(-1).sql, 'ROLLBACK');
    assert.equal(client.log.some((e) => e.sql.startsWith('UPDATE apartments') || e.sql.startsWith('UPDATE guest_passes')), false);

    client = scriptedClient([[RESET_LOCK, rowsOf([{ id: 3, site_code: 101, resident_user_code: null }])]]);
    pool.connect = async () => client;
    await assert.rejects(() => resetApartmentPin(3), (error) => error.code === 'APARTMENT_PIN_NO_ACCOUNT');
    assert.equal(client.log.some((e) => e.sql.startsWith('UPDATE users')), false);

    client = scriptedClient();
    pool.connect = async () => client;
    await assert.rejects(() => resetApartmentPin(3), (error) => error.message === 'APARTMENT_NOT_FOUND');
  });

  it('apartmentPinResetBody: email_only -> pin_code null ve e-posta ZORUNLU (send_email:false yok sayılır); shown + send_email:false -> e-posta yok', async () => {
    pool.query = async (text) => (SNAPSHOT.test(norm(text)) ? rowsOf([snapshotRow]) : rowsOf([]));
    const emailOnly = await apartmentPinResetBody(3, { delivery: 'email_only', pinCode: '7305', apartment: {} }, { sendEmail: false });
    assert.deepEqual(emailOnly, { ok: true, pin_code: null, pin_delivery: 'email_only', credentials_sent: true, credentials_email: 'ayse@example.com' });
    assert.equal(sent.length, 1);
    assert.match(sent[0].html, /7305/);
    const shownNoMail = await apartmentPinResetBody(3, { delivery: 'shown', pinCode: '7305', apartment: {} }, { sendEmail: false });
    assert.deepEqual(shownNoMail, { ok: true, pin_code: '7305', pin_delivery: 'shown', credentials_sent: null, credentials_email: null });
    assert.equal(sent.length, 1);
  });

  it('sendApartmentCredentials: PIN verilmezse APARTMENT_PIN_NOT_STORED (PIN okunacak sütun yok); verilirse e-postada', async () => {
    const queries = [];
    pool.query = async (text) => {
      queries.push(norm(text));
      return SNAPSHOT.test(norm(text)) ? rowsOf([snapshotRow]) : rowsOf([]);
    };
    await assert.rejects(() => sendApartmentCredentials(3), (error) => error.message === 'APARTMENT_PIN_NOT_STORED');
    assert.equal(sent.length, 0);
    assert.doesNotMatch(queries[0], /resident_pin_code/);
    await sendApartmentCredentials(3, { pinCode: '6142' });
    assert.equal(sent.length, 1);
    assert.match(sent[0].html, /<strong>PIN:<\/strong> 6142/);
    assert.match(sent[0].text, /saklanmaz/);
    assert.doesNotMatch(`${sent[0].html} ${sent[0].text} ${sent[0].subject}`, /AHBU/i);
  });

  it('sendIssuedApartmentPin: {sent,to}; e-posta yok -> null/null, gönderildi -> true + adres, SMTP hatası -> false (PIN / adres günlüğe yazılmaz), PIN yok -> null', async () => {
    const logged = [];
    console.error = (...args) => logged.push(args.map(String).join(' '));
    let row = { ...snapshotRow, resident_email: null };
    pool.query = async (text) => (SNAPSHOT.test(norm(text)) ? rowsOf([row]) : rowsOf([]));
    assert.deepEqual(await sendIssuedApartmentPin(3, '6142'), { sent: null, to: null });
    row = snapshotRow;
    assert.deepEqual(await sendIssuedApartmentPin(3, '6142'), { sent: true, to: 'ayse@example.com' });
    nodemailer.createTransport = () => ({ sendMail: async () => { throw Object.assign(new Error('smtp 6142 ayse@example.com'), { code: 'ECONNECTION' }); } });
    assert.deepEqual(await sendIssuedApartmentPin(3, '6142'), { sent: false, to: 'ayse@example.com' });
    assert.deepEqual(await sendIssuedApartmentPin(3, null), { sent: null, to: null });
    assert.equal(logged.length, 1);
    assert.doesNotMatch(logged[0], /6142|ayse@example\.com/);
  });

  it('sendIssuedApartmentPin: SMTP süre sınırında bitmezse yanıt BEKLEMEZ ({sent: null, to}); gönderim arka planda sürer, geç hata yakalanır', async () => {
    pool.query = async (text) => (SNAPSHOT.test(norm(text)) ? rowsOf([snapshotRow]) : rowsOf([]));
    let finish;
    nodemailer.createTransport = () => ({ sendMail: () => new Promise((resolve, reject) => { finish = { resolve, reject }; }) });
    const started = Date.now();
    const result = await sendIssuedApartmentPin(3, '6142', { timeoutMs: 40 });
    assert.deepEqual(result, { sent: null, to: 'ayse@example.com' });
    assert.ok(Date.now() - started < 1000);
    const logged = [];
    console.error = (...args) => logged.push(args.map(String).join(' '));
    finish.reject(Object.assign(new Error('geç hata'), { code: 'ETIMEDOUT' }));
    await new Promise((resolve) => setImmediate(resolve));
    assert.equal(logged.length, 1, 'geç hata yakalanır (işlenmemiş ret yok)');
    assert.equal(apartmentPinMailTuning.timeoutMs, 8000, 'varsayılan ~8 sn');
  });

  it('yeni hesap: istekte e-posta yoksa dairede kalmış ESKİ sakin adresi kullanılmaz (PIN eski sakine gitmez)', async () => {
    client = scriptedClient([
      [/^SELECT a\.id, a\.site_code, a\.resident_user_code, a\.resident_email, b\.block_name/, rowsOf([{ id: 3, site_code: 101, resident_user_code: null, resident_email: 'eski.sakin@example.com', block_name: 'A Blok', unit_label: 'Daire 3', sort_order: 3 }])],
      [/^INSERT INTO users/, rowsOf([{ id: 40002 }])],
      [/^SELECT a\.id, a\.site_code, a\.block_id, b\.block_name/, rowsOf([{ id: 3, site_code: 101, resident_user_code: 40002 }])],
    ]);
    pool.connect = async () => client;
    await provisionApartmentResident({ apartmentId: 3, fullName: 'Yeni Sakin', loginName: 'yeni', password: '5803', email: undefined, phoneNumber: null, isActive: true });
    const aptUpdate = client.log.find((e) => e.sql.startsWith('UPDATE apartments SET resident_user_code = $1'));
    assert.equal(aptUpdate.params[1], null);
  });
});

describe('HTTP: POST /admin/apartments/:id/reset-pin ve eski send-credentials', () => {
  let server;
  let base;
  const sent = [];
  const savedEnv = {};
  const originalCreateTransport = nodemailer.createTransport;
  const originalError = console.error;

  before(async () => {
    const { adminRouter } = await import('../src/routes/admin_routes.js');
    // Yalnız bu iki uç: kimlik / rol / hız sınırlayıcı katmanları sabit süper kullanıcıyla değiştirilir (yetki matrisi gerçek PG QA'sında).
    for (const layer of adminRouter.stack) {
      const routePath = layer.route?.path ?? '';
      if (!routePath.endsWith('/reset-pin') && !routePath.endsWith('/send-credentials')) continue;
      const stack = layer.route.stack;
      for (let i = 0; i < stack.length - 1; i += 1) {
        stack[i].handle = (req, _res, next) => {
          req.authUser = { id: 1, user_code: 1, role: 'super_user', full_name: 'Süper' };
          next();
        };
      }
    }
    const app = express();
    app.use(express.json());
    app.use(adminRouter);
    await new Promise((resolve) => { server = app.listen(0, '127.0.0.1', resolve); });
    base = `http://127.0.0.1:${server.address().port}`;
  });
  after(() => new Promise((resolve) => { server.closeAllConnections?.(); server.close(resolve); }));

  beforeEach(() => {
    sent.length = 0;
    for (const name of ['SMTP_HOST', 'SMTP_USER', 'SMTP_PASSWORD', 'SMTP_FROM', 'SMTP_PORT']) savedEnv[name] = process.env[name];
    Object.assign(process.env, { SMTP_HOST: 'smtp.invalid', SMTP_USER: 'user@example.invalid', SMTP_PASSWORD: 'test-only', SMTP_FROM: 'Sistem <noreply@example.invalid>' });
    delete process.env.SMTP_PORT;
    nodemailer.createTransport = () => ({ sendMail: async (message) => void sent.push(message) });
    console.error = () => {};
    pool.query = async (text) => {
      const sql = norm(text);
      if (/^SELECT a\.id, a\.site_code, a\.unit_label, a\.resident_email, b\.block_name/.test(sql)) {
        return rowsOf([{ id: '3', site_code: '101', unit_label: 'Daire 3', resident_email: 'ayse@example.com', block_name: 'A Blok', site_name: 'Gül Sitesi', resident_full_name: 'Ayşe', resident_login_name: '101_A_Daire3' }]);
      }
      return rowsOf([]); // cihaz listesi (yerel kontrol belirteci yenileme) boş
    };
  });
  afterEach(() => {
    nodemailer.createTransport = originalCreateTransport;
    for (const [name, value] of Object.entries(savedEnv)) {
      if (value === undefined) delete process.env[name];
      else process.env[name] = value;
    }
    console.error = originalError;
    delete pool.connect;
    delete pool.query;
  });

  const post = async (url, body) => {
    const response = await fetch(`${base}${url}`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body ?? {}) });
    return { status: response.status, headers: response.headers, body: await response.json() };
  };

  it('200: pin_code BİR KEZ (apartment.resident_pin_code ile aynı), işaret true, e-posta gönderildi, Cache-Control: no-store', async () => {
    const client = scriptedClient([
      [/FOR UPDATE$/, rowsOf([{ id: 3, site_code: 101, resident_user_code: 40001 }])],
      [/^UPDATE users SET password_hash/, rowsOf([{ user_code: 40001, login_name: '101_A_Daire3', email: 'x.3.101@ahbu.local' }])],
      [/^SELECT a\.id, a\.site_code, a\.block_id, b\.block_name/, rowsOf([{ id: 3, site_code: 101, block_id: 1, block_name: 'A Blok', unit_label: 'Daire 3', sort_order: 3, is_active: true, resident_user_code: 40001, resident_email: 'ayse@example.com', resident_pin_issued: true, resident_pin_resettable: true }])],
    ]);
    pool.connect = async () => client;
    const res = await post('/admin/apartments/3/reset-pin');
    assert.equal(res.status, 200, JSON.stringify(res.body));
    assert.match(res.body.pin_code, /^\d{4}$/);
    assert.equal(res.body.apartment.resident_pin_code, res.body.pin_code);
    assert.equal(res.body.apartment.resident_pin_issued, true);
    assert.equal(res.body.apartment.resident_pin_resettable, true);
    assert.equal(res.body.credentials_sent, true);
    assert.equal(res.body.credentials_email, 'ayse@example.com', 'hedef adres istemcide gösterilir');
    assert.equal(res.body.pin_delivery, 'shown');
    assert.equal(res.headers.get('cache-control'), 'no-store');
    assert.equal(sent.length, 1);
    assert.ok(sent[0].html.includes(res.body.pin_code));
  });

  it('süper kullanıcı, sakinin kendi parolası ve e-posta YOK: sıfırlayabilir, PIN bir kez gösterilir', async () => {
    const client = scriptedClient([
      [/FOR UPDATE$/, rowsOf([{ id: 3, site_code: 101, resident_user_code: 40001, resident_email: null, resident_pin_issued: false }])],
      [/^UPDATE users SET password_hash/, rowsOf([{ user_code: 40001, login_name: 'l', email: 'x@ahbu.local' }])],
      [/^SELECT a\.id, a\.site_code, a\.block_id/, rowsOf([{ id: 3, site_code: 101, block_id: 1, sort_order: 3 }])],
    ]);
    pool.connect = async () => client;
    const res = await post('/admin/apartments/3/reset-pin');
    assert.equal(res.status, 200, JSON.stringify(res.body));
    assert.equal(res.body.pin_delivery, 'shown');
    assert.match(res.body.pin_code, /^\d{4}$/);
  });

  it('send_email:false -> e-posta gitmez (credentials_sent null)', async () => {
    const client = scriptedClient([
      [/FOR UPDATE$/, rowsOf([{ id: 3, site_code: 101, resident_user_code: 40001 }])],
      [/^UPDATE users SET password_hash/, rowsOf([{ user_code: 40001, login_name: 'l', email: 'x@ahbu.local' }])],
      [/^SELECT a\.id, a\.site_code, a\.block_id/, rowsOf([{ id: 3, site_code: 101, block_id: 1, sort_order: 3 }])],
    ]);
    pool.connect = async () => client;
    const res = await post('/admin/apartments/3/reset-pin', { send_email: false });
    assert.equal(res.status, 200);
    assert.equal(res.body.credentials_sent, null);
    assert.equal(sent.length, 0);
  });

  it('409: kayıtlı hesap -> sabit ileti + kod (error.message değil)', async () => {
    pool.connect = async () => scriptedClient([[/FOR UPDATE$/, rowsOf([{ id: 3, site_code: 101, resident_user_code: 40001 }])]]);
    const res = await post('/admin/apartments/3/reset-pin');
    assert.equal(res.status, 409);
    assert.deepEqual(res.body, { error: APARTMENT_PIN_ERROR_MESSAGES.APARTMENT_PIN_NOT_RESETTABLE, code: 'APARTMENT_PIN_NOT_RESETTABLE' });
  });

  it('eski "Bilgileri Gönder" (send-credentials): 409 APARTMENT_PIN_NOT_STORED, e-posta gitmez', async () => {
    const res = await post('/admin/apartments/3/send-credentials');
    assert.equal(res.status, 409);
    assert.deepEqual(res.body, { error: APARTMENT_PIN_NOT_STORED_MESSAGE, code: 'APARTMENT_PIN_NOT_STORED' });
    assert.equal(sent.length, 0);
  });
});

describe('kaynak düzeyi: düz PIN hiçbir sunucu kodunda okunmaz / yazılmaz', () => {
  function walk(dir) {
    return fs.readdirSync(dir).flatMap((name) => {
      const full = path.join(dir, name);
      return fs.statSync(full).isDirectory() ? walk(full) : name.endsWith('.js') ? [full] : [];
    });
  }

  it('resident_pin_code yalnız NULL\'lanır (SET ... = NULL) ya da şema / aktarımda geçer; SELECT ile okunmaz, değer yazılmaz', () => {
    const offenders = [];
    for (const file of walk(path.join(serverRoot, 'src'))) {
      const rel = path.relative(serverRoot, file).replace(/\\/g, '/');
      if (rel === 'src/modules/apartment_pin_schema.js' || rel === 'src/db.js') continue;
      const lines = fs.readFileSync(file, 'utf8').split(/\r?\n/);
      lines.forEach((line, index) => {
        if (!line.includes('resident_pin_code') || /^\s*(\/\/|\*)/.test(line)) return;
        const allowed = /resident_pin_code = NULL/.test(line) || /resident_pin_code IS NOT NULL/.test(line) || /resident_pin_code: row\.issued_pin_code/.test(line);
        if (!allowed) offenders.push(`${rel}:${index + 1}: ${line.trim()}`);
      });
    }
    assert.deepEqual(offenders, []);
  });

  it('reset-pin uçları: kimlik + rol + hız sınırlayıcı; manager ucu site yetkisini denetler', () => {
    const manager = read('src/routes/manager_routes.js');
    const admin = read('src/routes/admin_routes.js');
    assert.match(manager, /managerRouter\.post\('\/manager\/apartments\/:id\/reset-pin', authRequired, requireSiteManager, apartmentPinResetLimiter,/);
    assert.match(admin, /adminRouter\.post\('\/admin\/apartments\/:id\/reset-pin', authRequired, requireSuperUser, apartmentPinResetLimiter,/);
    const body = manager.slice(manager.indexOf("'/manager/apartments/:id/reset-pin'"));
    assert.ok(body.indexOf('hasSiteManagementAccess(req.authUser, siteCode)') < body.indexOf('resetApartmentPin('));
  });

  it('sakin kendi parolasını değiştirince (PATCH /me ve change-password) "PIN verildi" işareti kalkar', () => {
    const auth = read('src/routes/auth_routes.js');
    const patchMe = auth.slice(auth.indexOf("authRouter.patch('/me'"));
    assert.ok(patchMe.indexOf('UPDATE apartments SET resident_pin_issued = FALSE, resident_pin_code = NULL WHERE resident_user_code = $1') > patchMe.indexOf('updateUserByCode('));
    assert.ok(read('src/services/membership_service.js').includes('UPDATE apartments SET resident_pin_issued = FALSE, resident_pin_code = NULL WHERE id = $1'));
  });

  it('P2: gösterge temizlenen / başkasına geçen her yerde eski sakinin iletişim e-postası da silinir (keepPin hariç)', () => {
    const membership = norm(read('src/services/membership_service.js'));
    // handOverApartmentResident: devir (2 yer) + kimse yoksa temizleme; keepPin dalı göstergeyi ve e-postayı korur.
    assert.equal(membership.split('UPDATE apartments SET resident_user_code = $1, resident_pin_issued = FALSE, resident_pin_code = NULL, resident_email = NULL WHERE id = $2').length - 1, 2);
    assert.ok(membership.includes(': `UPDATE apartments SET resident_user_code = NULL, resident_pin_issued = FALSE, resident_pin_code = NULL, resident_email = NULL WHERE id = $1`'));
    assert.ok(membership.includes('? `UPDATE apartments SET resident_user_code = NULL WHERE id = $1`'), 'keepPin dalı değişmedi');
    // setApartmentPrimaryAdmin: gösterge başka kişiye geçerse e-posta ve işaret temizlenir.
    assert.ok(membership.includes('SET resident_email = CASE WHEN resident_user_code IS DISTINCT FROM $1 THEN NULL ELSE resident_email END'));
    assert.ok(membership.includes('resident_pin_issued = CASE WHEN resident_user_code IS DISTINCT FROM $1 THEN FALSE ELSE resident_pin_issued END'));
    // Yönetici kullanıcı silme (admin): göstergeyle birlikte e-posta ve işaret.
    assert.ok(norm(read('src/routes/admin_routes.js')).includes("'UPDATE apartments SET resident_user_code = NULL, resident_email = NULL, resident_pin_issued = FALSE, resident_pin_code = NULL WHERE resident_user_code = $1'"));
  });

  it('P4: SMTP ad çözümleme / bağlantı zaman aşımları kısa (yanıtı tutan tek kopya beklemesin)', () => {
    const mailer = read('src/mailer.js');
    assert.match(mailer, /dnsTimeout: 5_000/);
    assert.match(mailer, /connectionTimeout: 8_000/);
    assert.match(mailer, /greetingTimeout: 8_000/);
  });
});
