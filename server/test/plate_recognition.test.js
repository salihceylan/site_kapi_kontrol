// Plaka Tanıma (073): plaka normalleştirme, karar motoru, otomatik açma planı, girdi doğrulayıcıları, migration <-> şema eşitliği, katalog (DB'siz).
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { DEFAULT_MIGRATIONS_DIR } from '../scripts/migrate.js';
import { PLATE_RECOGNITION_DDL, PLATE_RECOGNITION_DDL_ORDER, ensurePlateRecognitionSchema } from '../src/modules/plate_recognition_schema.js';
import {
  MAX_OPENS_PER_MINUTE,
  canonicalPlate,
  decidePlate,
  formatPlate,
  maskPlate,
  normalizeTrPlate,
  parseBlacklistInput,
  parseConfidence,
  parseGateSettings,
  parsePermitInput,
  permitStatus,
  planAutoOpen,
} from '../src/modules/plate_recognition_common.js';
import { getModuleDefinition, isToggleable } from '../src/modules/catalog.js';

process.env.JWT_SECRET ||= 'test-secret-test-secret-test-secret-123456';

const norm = (t) => t.replace(/--.*$/gm, ' ').replace(/\s+/g, ' ').trim();

describe('073 migration <-> şema', () => {
  it('aynı ifadeler, aynı sırada', () => {
    const sql = readFileSync(path.join(DEFAULT_MIGRATIONS_DIR, '073_plate_recognition.sql'), 'utf8').replace(/\r\n/g, '\n');
    const expected = PLATE_RECOGNITION_DDL_ORDER.map((n) => `${norm(PLATE_RECOGNITION_DDL[n])};`).join(' ');
    assert.equal(norm(sql), expected);
  });

  it('DDL ekleyici ve idempotent: yalnız CREATE ... IF NOT EXISTS (silme / değiştirme yok)', () => {
    for (const [name, ddl] of Object.entries(PLATE_RECOGNITION_DDL)) {
      assert.doesNotMatch(ddl, /DROP |TRUNCATE|DELETE FROM|ALTER TABLE (?!plate_)/i, name);
      assert.match(ddl, /IF NOT EXISTS|ADD CONSTRAINT/, name);
    }
    const sql = readFileSync(path.join(DEFAULT_MIGRATIONS_DIR, '073_plate_recognition.sql'), 'utf8');
    assert.ok(!sql.includes('\r'), 'LF olmalı');
  });

  it('6B tablolarına FK yok ve oto-açma varsayılanı KAPALI', () => {
    assert.doesNotMatch(PLATE_RECOGNITION_DDL.settingsTable, /REFERENCES/);
    assert.doesNotMatch(PLATE_RECOGNITION_DDL.decisionTable, /REFERENCES/);
    assert.match(PLATE_RECOGNITION_DDL.settingsTable, /auto_open BOOLEAN NOT NULL DEFAULT FALSE/);
    assert.match(PLATE_RECOGNITION_DDL.settingsTable, /min_confidence NUMERIC\(4, 3\) NOT NULL DEFAULT 0\.85/);
    assert.match(PLATE_RECOGNITION_DDL.settingsTable, /cooldown_seconds INTEGER NOT NULL DEFAULT 30/);
  });

  it('her şey varsa tek okuma sorgusu gider, DDL gitmez', async () => {
    const calls = [];
    const client = {
      async query(sql) {
        calls.push(sql);
        return {
          rows: [
            {
              tables: ['plate_guest_permits', 'plate_blacklist', 'plate_gate_settings', 'plate_decisions'],
              indexes: [
                'idx_plate_guest_permits_site',
                'idx_plate_guest_permits_plate',
                'idx_plate_guest_permits_creator',
                'uq_plate_blacklist_active',
                'uq_plate_gate_settings_device',
                'idx_plate_decisions_site',
                'idx_plate_decisions_open',
              ],
            },
          ],
        };
      },
    };
    await ensurePlateRecognitionSchema(client);
    assert.equal(calls.length, 1);
  });

  it('yalnız eksik tablo, FK ve indeksler oluşturulur', async () => {
    const calls = [];
    const client = {
      async query(sql) {
        calls.push(sql);
        return { rows: [{ tables: ['plate_guest_permits', 'plate_blacklist', 'plate_gate_settings'], indexes: ['idx_plate_guest_permits_site', 'idx_plate_guest_permits_plate', 'idx_plate_guest_permits_creator', 'uq_plate_blacklist_active', 'uq_plate_gate_settings_device'] }] };
      },
    };
    await ensurePlateRecognitionSchema(client);
    const ddl = calls.filter((s) => /CREATE TABLE|ADD CONSTRAINT|CREATE (UNIQUE )?INDEX/.test(s));
    assert.equal(ddl.length, 4); // plate_decisions: tablo + site FK + 2 indeks
    assert.match(ddl[0], /plate_decisions/);
  });
});

describe('katalog', () => {
  it('plate_recognition kullanılabilir, çekirdek değil, varsayılan KAPALI, açıklama değişmedi', () => {
    const def = getModuleDefinition('plate_recognition');
    assert.equal(def.status, 'available');
    assert.equal(def.core, false);
    assert.equal(def.defaultEnabled, false);
    assert.equal(isToggleable(def), true);
    assert.equal(def.description, 'Araç plakasını tanıyarak otopark kapısını açma; plaka kayıtları.');
  });
});

describe('plaka normalleştirme', () => {
  it('boşluk / tire / nokta atılır, büyük harf', () => {
    assert.equal(normalizeTrPlate('34 abc 123'), '34ABC123');
    assert.equal(normalizeTrPlate('34-ABC-123'), '34ABC123');
    assert.equal(normalizeTrPlate(' 06 a 1234 '), '06A1234');
    assert.equal(normalizeTrPlate('81.zz.12'), '81ZZ12');
    assert.equal(canonicalPlate('34 abc 123'), '34ABC123');
  });

  it('il kodu 01-81 dışı, biçim dışı ve metin olmayan girdi geçersiz', () => {
    for (const bad of ['00ABC123', '82ABC123', '99ABC123', '34ABCD123', '34A1', '34ABC1', '34ABC12345', 'ABC123', '3ABC123', '34 123 ABC', '', '   ', null, undefined, 34, {}, '3'.repeat(40)]) {
      assert.equal(normalizeTrPlate(bad), null, String(bad));
    }
  });

  it('Türkçe harfler ASCII\'ye iner (İ, Ş ...)', () => {
    assert.equal(canonicalPlate('34 şç 123'), '34SC123');
    assert.equal(canonicalPlate('34 ıİ 12'), '34II12');
  });

  it('biçimleme ve maskeleme', () => {
    assert.equal(formatPlate('34ABC123'), '34 ABC 123');
    assert.equal(formatPlate('XX'), 'XX');
    assert.equal(maskPlate('34ABC123'), '34***23');
    assert.equal(maskPlate('1234'), '***');
    assert.ok(!maskPlate('34ABC123').includes('ABC'));
  });

  it('okuma güveni: 0-1, yüzde ve geçersiz', () => {
    assert.equal(parseConfidence(0.9), 0.9);
    assert.equal(parseConfidence('0,87'), 0.87);
    assert.equal(parseConfidence(95), 0.95);
    assert.equal(parseConfidence('100'), 1);
    assert.equal(parseConfidence(1), 1);
    assert.equal(parseConfidence(150), null);
    assert.equal(parseConfidence(-1), null);
    assert.equal(parseConfidence('abc'), null);
    assert.equal(parseConfidence(undefined), null);
    assert.equal(parseConfidence(null), null);
  });
});

describe('karar motoru', () => {
  const plate = '34ABC123';
  it('sıra: geçersiz biçim -> düşük güven -> kara liste -> araç -> misafir -> bilinmiyor', () => {
    assert.deepEqual(decidePlate({ plate: null, confidence: 0.99 }), { decision: 'UNKNOWN', reason: 'invalid_plate' });
    assert.deepEqual(decidePlate({ plate: 'ABCDE', confidence: 0.99, vehicle: { id: 1 } }), { decision: 'UNKNOWN', reason: 'invalid_plate' });
    assert.deepEqual(decidePlate({ plate, confidence: 0.5, blacklisted: true, vehicle: { id: 1 } }), { decision: 'UNKNOWN', reason: 'low_confidence' });
    assert.deepEqual(decidePlate({ plate, confidence: 0.95, blacklisted: true, vehicle: { id: 1 }, permit: { id: 2 } }), { decision: 'DENIED', reason: 'blacklist' });
    assert.deepEqual(decidePlate({ plate, confidence: 0.95, vehicle: { id: 1 }, permit: { id: 2 } }), { decision: 'ALLOWED', reason: 'vehicle' });
    assert.deepEqual(decidePlate({ plate, confidence: 0.95, permit: { id: 2 } }), { decision: 'ALLOWED', reason: 'guest_permit' });
    assert.deepEqual(decidePlate({ plate, confidence: 0.95 }), { decision: 'UNKNOWN', reason: 'not_registered' });
  });

  it('eşik: varsayılan 0.85; tam eşik geçer, altı UNKNOWN; özel eşik uygulanır', () => {
    assert.equal(decidePlate({ plate, confidence: 0.85, vehicle: { id: 1 } }).decision, 'ALLOWED');
    assert.equal(decidePlate({ plate, confidence: 0.8499, vehicle: { id: 1 } }).reason, 'low_confidence');
    assert.equal(decidePlate({ plate, confidence: 0.9, minConfidence: 0.95, vehicle: { id: 1 } }).reason, 'low_confidence');
    assert.equal(decidePlate({ plate, confidence: 0.96, minConfidence: 0.95, vehicle: { id: 1 } }).decision, 'ALLOWED');
  });

  it('güven bilinmiyorsa (kamera göndermedi) liste kararı verilir ama otomatik açma planı none', () => {
    assert.equal(decidePlate({ plate, confidence: null, vehicle: { id: 1 } }).decision, 'ALLOWED');
    const settings = { door_id: 5, auto_open: true, min_confidence: 0.85, cooldown_seconds: 30 };
    assert.equal(planAutoOpen({ decision: 'ALLOWED', confidence: null, settings }), 'none');
  });
});

describe('otomatik açma planı (kapı AÇILMAZ; would_open yalnız kayıt)', () => {
  const settings = { door_id: 5, auto_open: true, min_confidence: 0.9, cooldown_seconds: 30 };
  it('ayar yok / kapalı / kapıya eşli değil -> none', () => {
    assert.equal(planAutoOpen({ decision: 'ALLOWED', confidence: 0.99, settings: null }), 'none');
    assert.equal(planAutoOpen({ decision: 'ALLOWED', confidence: 0.99, settings: { ...settings, auto_open: false } }), 'none');
    assert.equal(planAutoOpen({ decision: 'ALLOWED', confidence: 0.99, settings: { ...settings, door_id: 0 } }), 'none');
  });
  it('yalnız ALLOWED ve ayardaki eşik sağlanırsa would_open', () => {
    assert.equal(planAutoOpen({ decision: 'DENIED', confidence: 0.99, settings }), 'none');
    assert.equal(planAutoOpen({ decision: 'UNKNOWN', confidence: 0.99, settings }), 'none');
    assert.equal(planAutoOpen({ decision: 'ALLOWED', confidence: 0.89, settings }), 'none');
    assert.equal(planAutoOpen({ decision: 'ALLOWED', confidence: 0.9, settings }), 'would_open');
  });
  it('aynı plaka cooldown içinde tekrar açmaz; kapı dakikada en çok 6', () => {
    assert.equal(planAutoOpen({ decision: 'ALLOWED', confidence: 0.95, settings, samePlateRecent: 1 }), 'suppressed_cooldown');
    assert.equal(planAutoOpen({ decision: 'ALLOWED', confidence: 0.95, settings, doorOpensLastMinute: MAX_OPENS_PER_MINUTE - 1 }), 'would_open');
    assert.equal(planAutoOpen({ decision: 'ALLOWED', confidence: 0.95, settings, doorOpensLastMinute: MAX_OPENS_PER_MINUTE }), 'suppressed_rate');
    assert.equal(MAX_OPENS_PER_MINUTE, 6);
  });
});

describe('girdi doğrulayıcıları', () => {
  const now = new Date('2026-10-22T10:00:00Z');
  it('misafir izni süreleri: 1 gün, 1 hafta, özel 1-30 gün', () => {
    assert.equal(parsePermitInput({ plate: '34 abc 123', duration: 'day' }, now).validUntil.toISOString(), '2026-10-23T10:00:00.000Z');
    assert.equal(parsePermitInput({ plate: '34ABC123', duration: 'week' }, now).validUntil.toISOString(), '2026-10-29T10:00:00.000Z');
    assert.equal(parsePermitInput({ plate: '34ABC123', duration: 'custom', days: 30 }, now).validUntil.toISOString(), '2026-11-21T10:00:00.000Z');
    assert.equal(parsePermitInput({ plate: '34ABC123' }, now).days, 1, 'süre verilmezse 1 gün');
    assert.throws(() => parsePermitInput({ plate: '34ABC123', duration: 'custom', days: 31 }, now), { code: 'INVALID_BODY' });
    assert.throws(() => parsePermitInput({ plate: '34ABC123', duration: 'custom', days: 0 }, now), { code: 'INVALID_BODY' });
    assert.throws(() => parsePermitInput({ plate: '34ABC123', duration: 'custom', days: 1.5 }, now), { code: 'INVALID_BODY' });
    assert.throws(() => parsePermitInput({ plate: '34ABC123', duration: 'year' }, now), { code: 'INVALID_BODY' });
    assert.throws(() => parsePermitInput({ plate: 'kotu', duration: 'day' }, now), { code: 'PLATE_INVALID' });
  });

  it('not kırpılır, uzun not reddedilir', () => {
    assert.equal(parsePermitInput({ plate: '34ABC123', note: '  Ali   amca  ' }, now).note, 'Ali amca');
    assert.equal(parsePermitInput({ plate: '34ABC123', note: '   ' }, now).note, null);
    assert.throws(() => parsePermitInput({ plate: '34ABC123', note: 'x'.repeat(121) }, now), { code: 'INVALID_BODY' });
  });

  it('kara liste girdisi', () => {
    assert.deepEqual(parseBlacklistInput({ plate: '34-abc-123', reason: ' Kavga ' }), { plate: '34ABC123', reason: 'Kavga' });
    assert.equal(parseBlacklistInput({ plate: '34ABC123' }).reason, null);
    assert.throws(() => parseBlacklistInput({ plate: '00AA11' }), { code: 'PLATE_INVALID' });
    assert.throws(() => parseBlacklistInput({ plate: '34ABC123', reason: 'x'.repeat(201) }), { code: 'INVALID_BODY' });
  });

  it('kapı ayarı: auto_open yalnız true ile; açarken kamera + risk onayı şart', () => {
    assert.deepEqual(parseGateSettings({}), { autoOpen: false, deviceId: null, minConfidence: 0.85, cooldownSeconds: 30 });
    assert.equal(parseGateSettings({ auto_open: 'true', device_id: 3 }).autoOpen, false, 'metin true sayılmaz');
    assert.equal(parseGateSettings({ auto_open: true, device_id: 3, confirm_risk: true }).autoOpen, true);
    assert.throws(() => parseGateSettings({ auto_open: true, device_id: 3 }), { code: 'RISK_CONFIRM_REQUIRED' });
    assert.throws(() => parseGateSettings({ auto_open: true, device_id: 3, confirm_risk: 'evet' }), { code: 'RISK_CONFIRM_REQUIRED' });
    assert.throws(() => parseGateSettings({ auto_open: true, confirm_risk: true }), { code: 'INVALID_BODY' });
    assert.equal(parseGateSettings({ auto_open: false, device_id: 3 }).deviceId, 3);
    assert.equal(parseGateSettings({ min_confidence: 90, cooldown_seconds: 60 }).minConfidence, 0.9);
    assert.throws(() => parseGateSettings({ min_confidence: 0.3 }), { code: 'INVALID_BODY' });
    assert.throws(() => parseGateSettings({ min_confidence: 'x' }), { code: 'INVALID_BODY' });
    assert.throws(() => parseGateSettings({ cooldown_seconds: 2 }), { code: 'INVALID_BODY' });
    assert.throws(() => parseGateSettings({ cooldown_seconds: 601 }), { code: 'INVALID_BODY' });
    assert.throws(() => parseGateSettings({ device_id: -1 }), { code: 'INVALID_BODY' });
  });

  it('izin durumu', () => {
    const base = { valid_until: '2026-10-23T10:00:00Z', revoked_at: null };
    assert.equal(permitStatus(base, now), 'active');
    assert.equal(permitStatus({ ...base, valid_until: '2026-10-22T09:00:00Z' }, now), 'expired');
    assert.equal(permitStatus({ ...base, revoked_at: '2026-10-22T09:30:00Z' }, now), 'revoked');
  });
});
