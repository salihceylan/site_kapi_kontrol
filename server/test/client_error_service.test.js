// İstemci hata raporu servisi (DB'siz): kişisel veri temizleme (+ ReDoS zaman sınırı), rapor doğrulaması / boyut sınırları, parmak izi,
// kayıt (upsert / satır tavanı), imleçli listeleme, 90 gün silme (tek çalışan kilidi) ve zamanlayıcı.
import { describe, it, afterEach, mock } from 'node:test';
import assert from 'node:assert/strict';
import {
  LIST_DEFAULT_LIMIT,
  LIST_MAX_LIMIT,
  PURGE_LOCK_CLASS,
  PURGE_LOCK_JOB,
  WRITE_LOCK_JOB,
  REPORT_LIMITS,
  RETENTION_DAYS,
  clampListLimit,
  createWriteGate,
  decodeCursor,
  encodeCursor,
  evictionBatch,
  fingerprintOf,
  listReports,
  maxRows,
  normalizeReport,
  purgeOldReports,
  scrubPersonalData,
  storeReport,
} from '../src/modules/client_error_service.js';
import { isPurgeDisabled, runClientErrorPurge, startClientErrorPurge, stopClientErrorPurge } from '../src/modules/client_error_purge.js';

const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
const ok = (rows = [], rowCount = rows.length) => ({ rows, rowCount });

const INSTALL = '3f2b8c1e-9a4d-4e2b-8f6a-1c2d3e4f5a6b';
const sample = (overrides = {}) => ({
  install_id: INSTALL,
  app_version: '1.0.0',
  build: '12',
  platform: 'android',
  os_version: '14',
  error_type: 'FlutterError',
  message: 'RenderFlex overflowed by 24 pixels',
  stack: '#0      RenderFlex.performLayout (package:flutter/src/rendering/flex.dart:1000:7)\n#1      main (package:site_kapi_kontrol/main.dart:42:7)',
  fatal: true,
  occurred_at: '2026-10-16T10:00:00.000Z',
  route: '/home',
  ...overrides,
});

afterEach(() => {
  mock.restoreAll();
});

describe('scrubPersonalData', () => {
  it('e-posta', () => {
    assert.equal(scrubPersonalData('user ali.veli+x@example.com.tr failed'), 'user [email] failed');
    assert.equal(scrubPersonalData('a@b.co, c_d@e-f.org'), '[email], [email]');
    assert.equal(scrubPersonalData('@ tek başına ve a@b ham'), '@ tek başına ve a@b ham');
  });

  it('JWT, Bearer ve URL kimlik bilgisi', () => {
    const jwt = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c';
    assert.equal(scrubPersonalData(`token ${jwt} bitti`), 'token [jwt] bitti');
    assert.equal(scrubPersonalData('Authorization: Bearer abc.def-ghi_jkl='), 'Authorization: Bearer [token]');
    assert.equal(scrubPersonalData('bearer SECRETVALUE'), 'Bearer [token]');
    assert.equal(scrubPersonalData('GET https://user:pa55@api.example.com/x'), 'GET https://[credentials]@api.example.com/x');
    assert.ok(!scrubPersonalData(`Bearer ${jwt}`).includes('eyJ'));
  });

  it('telefon: uluslararası ve Türkiye biçimleri', () => {
    for (const phone of ['+90 532 123 45 67', '+905321234567', '0090 532 123 45 67', '0532 123 45 67', '05321234567', '532 123 45 67', '(0212) 555 12 34', '0 (212) 555-12-34', '532-123-45-67', '+1 (415) 555-2671']) {
      assert.equal(scrubPersonalData(`ara: ${phone} tamam`), 'ara: [phone] tamam', phone);
    }
  });

  it('uzun sayı dizileri (TCKN, kart, IBAN rakamları, OTP) maskelenir; kısa sayılar (satır:sütun, port, durum kodu) korunur', () => {
    assert.equal(scrubPersonalData('tckn 12345678901 var'), 'tckn [num] var');
    assert.equal(scrubPersonalData('kart 4111 1111 1111 1111 ok'), 'kart [num] ok');
    assert.equal(scrubPersonalData('kart 4111-1111-1111-1111'), 'kart [num]');
    assert.equal(scrubPersonalData('otp 123456'), 'otp [num]');
    assert.equal(scrubPersonalData('epoch 1760608800000'), 'epoch [num]');
    for (const keep of ['main.dart:42:7', 'port 8080', 'HTTP 404', 'overflowed by 24 pixels', 'index 12345', 'v1.2.3', '#0      main (package:app/main.dart:42:7)']) {
      assert.equal(scrubPersonalData(keep), keep, keep);
    }
  });

  it('IPv4, sorgu dizesi gizlileri ve uzun belirteç / hex dizileri', () => {
    assert.equal(scrubPersonalData('bağlanamadı 192.168.1.20:8080'), 'bağlanamadı [ip]:8080');
    assert.equal(scrubPersonalData('GET /x?token=abc123&page=2'), 'GET /x?token=[redacted]&page=2');
    assert.equal(scrubPersonalData('url /a?x=1&access_token=Zm9vYmFy&y=2'), 'url /a?x=1&access_token=[redacted]&y=2');
    assert.equal(scrubPersonalData('giriş password=hunter2 denendi'), 'giriş password=[redacted] denendi');
    assert.equal(scrubPersonalData('?t=abcdef'), '?t=[redacted]');
    assert.equal(scrubPersonalData('format=json limit=5'), 'format=json limit=5', 'ilgisiz parametreler korunur');
    assert.equal(scrubPersonalData('anahtar KlMnOp0123456789KlMnOp0123456789KlMnOp0123 son'), 'anahtar [token] son');
    assert.equal(scrubPersonalData('md5 d41d8cd98f00b204e9800998ecf8427e son'), 'md5 [hex] son');
    const longSymbol = `_${'ABCDEFGHIJ'.repeat(6)}`;
    assert.equal(scrubPersonalData(longSymbol), longSymbol, 'yalnız harften oluşan uzun sembol korunur');
  });

  it('bir arada ve idempotent', () => {
    const text = 'ali@example.com 0532 123 45 67 Bearer abcdef 10.0.0.1 tckn 12345678901 ?token=zzz';
    const once = scrubPersonalData(text);
    assert.equal(once, '[email] [phone] Bearer [token] [ip] tckn [num] ?token=[redacted]');
    assert.equal(scrubPersonalData(once), once);
    assert.equal(scrubPersonalData(null), '');
    assert.equal(scrubPersonalData(undefined), '');
    assert.equal(scrubPersonalData(1234567), '[num]');
  });

  it('düşmanca büyük girdi doğrusal sürede biter (ReDoS yok)', () => {
    const N = 16000;
    const inputs = {
      'a...@': `${'a'.repeat(N)}@`,
      rakam: '1'.repeat(N),
      'rakam+boşluk': '1 '.repeat(N / 2),
      eyJ: 'eyJ'.repeat(N / 3),
      tire: '-'.repeat(N),
      'a-': 'a-'.repeat(N / 2),
      'a@': 'a@'.repeat(N / 2),
      'nokta+1': `${'.'.repeat(N)}1`,
      'a.a.': 'a.'.repeat(N / 2),
      '0 ': '0 '.repeat(N / 2),
      'Bearer ': 'Bearer '.repeat(N / 7),
      '//': '//a:'.repeat(N / 4),
      '?t=': '?t=a'.repeat(N / 4),
      '+90': '+90 '.repeat(N / 4),
      '1.': '1.'.repeat(N / 2),
    };
    for (const [name, input] of Object.entries(inputs)) {
      const start = Date.now();
      scrubPersonalData(input);
      const took = Date.now() - start;
      assert.ok(took < 400, `${name}: ${took} ms`);
    }
  });
});

describe('normalizeReport', () => {
  it('sözleşmedeki örnek gövde: alanlar normalleşir (installId yalnız bellek içi hız sınırı için taşınır, veritabanına yazılmaz)', () => {
    const { report, error } = normalizeReport(sample());
    assert.equal(error, undefined);
    assert.deepEqual(report, {
      installId: INSTALL,
      appVersion: '1.0.0',
      build: '12',
      platform: 'android',
      osVersion: '14',
      errorType: 'FlutterError',
      message: 'RenderFlex overflowed by 24 pixels',
      stack: '#0      RenderFlex.performLayout (package:flutter/src/rendering/flex.dart:1000:7)\n#1      main (package:site_kapi_kontrol/main.dart:42:7)',
      fatal: true,
      route: '/home',
    });
  });

  it('gövde nesne değilse / install_id geçersizse / app_version geçersizse / ikisi de boşsa hata', () => {
    for (const body of [null, undefined, 'x', 5, [], [sample()]]) assert.ok(normalizeReport(body).error, JSON.stringify(body));
    for (const install_id of [undefined, '', 'abc', '3f2b8c1e-9a4d-4e2b-8f6a-1c2d3e4f5a6', `${INSTALL}0`, 123, '3f2b8c1e-9a4d-4e2b-8f6a-1c2d3e4f5a6g']) {
      assert.ok(normalizeReport(sample({ install_id })).error, String(install_id));
    }
    for (const app_version of [undefined, '', ' ', '1 0', 'x'.repeat(33), '-1', '<b>', "1.0'--"]) {
      assert.ok(normalizeReport(sample({ app_version })).error, String(app_version));
    }
    assert.ok(normalizeReport(sample({ message: '', stack: '' })).error);
    assert.ok(normalizeReport(sample({ message: undefined, stack: undefined })).error);
    assert.ok(normalizeReport(sample({ message: '   ', stack: null })).error);
  });

  it('eksik isteğe bağlı alanlar: platform "other", hata türü "Error", mesaj yoksa yer tutucu, fatal yalnız boolean true', () => {
    const { report } = normalizeReport({ install_id: INSTALL, app_version: '1.0.0', stack: 'x' });
    assert.equal(report.platform, 'other');
    assert.equal(report.errorType, 'Error');
    assert.equal(report.message, '(mesaj yok)');
    assert.equal(report.fatal, false);
    assert.equal(report.build, null);
    assert.equal(report.osVersion, null);
    assert.equal(report.route, null);
    for (const fatal of ['true', 1, 'yes', {}]) assert.equal(normalizeReport(sample({ fatal })).report.fatal, false, String(fatal));
    assert.equal(normalizeReport(sample({ platform: ' IOS ' })).report.platform, 'ios');
    assert.equal(normalizeReport(sample({ platform: 'windows' })).report.platform, 'other');
    assert.equal(normalizeReport(sample({ platform: 5 })).report.platform, 'other');
  });

  it('BOYUT SINIRLARI: alanlar kısaltılır (message 500, stack 8000, error_type 100, route 200, os_version 40, build 20); aşırı girdi sınırlıdır', () => {
    const huge = sample({
      message: 'm'.repeat(100000),
      stack: `#0 ${'s'.repeat(50)}\n`.repeat(20000),
      error_type: 'T'.repeat(5000),
      route: `/${'r'.repeat(5000)}`,
      os_version: 'o'.repeat(5000),
      build: 'b'.repeat(5000),
    });
    const { report } = normalizeReport(huge);
    assert.ok(report.message.length <= REPORT_LIMITS.message);
    assert.ok(report.stack.length <= REPORT_LIMITS.stack);
    assert.ok(report.errorType.length <= REPORT_LIMITS.errorType);
    assert.ok(report.route.length <= REPORT_LIMITS.route);
    assert.ok(report.osVersion.length <= REPORT_LIMITS.osVersion);
    assert.ok(report.build.length <= REPORT_LIMITS.build);
    assert.equal(report.message.length, 500);
    assert.equal(report.stack.length, 8000);
  });

  it('KİŞİSEL VERİ TEMİZLENİR: message, stack, route, error_type, os_version, build', () => {
    const jwt = 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjMifQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c';
    const { report } = normalizeReport(
      sample({
        message: 'Giriş başarısız ali@example.com tel 0532 123 45 67 Bearer abcdef',
        stack: `#0 login (package:app/auth.dart:10:3)\n#1 jwt ${jwt}\n#2 tckn 12345678901`,
        route: '/profile/12345678901?email=ali@example.com&token=abc#frag',
        error_type: 'Exception(ali@example.com)',
        os_version: '14 (192.168.1.5)',
        build: '0532 123 45 67',
      }),
    );
    const everything = JSON.stringify(report);
    for (const leaked of ['ali@example.com', '0532 123', 'abcdef', 'eyJhbG', '12345678901', '192.168.1.5', 'frag', 'email=']) {
      assert.equal(everything.includes(leaked), false, leaked);
    }
    assert.equal(report.route, '/profile/[num]');
    assert.ok(report.message.includes('[email]') && report.message.includes('[phone]') && report.message.includes('Bearer [token]'));
    assert.ok(report.stack.includes('[jwt]') && report.stack.includes('tckn [num]'));
    assert.equal(report.stack.split('\n').length, 3, 'yığın satır yapısı korunur');
  });

  it('kontrol karakterleri temizlenir; mesaj tek satıra iner; yığın satırları korunur', () => {
    const { report } = normalizeReport(sample({ message: 'a\u0000b\nc\r\nd\te', stack: 'x\u0001y\r\nz   \n' }));
    assert.equal(report.message, 'a b c d e');
    assert.equal(report.stack, 'x y\nz');
  });
});

describe('fingerprintOf', () => {
  const base = () => normalizeReport(sample()).report;

  it('64 hex; aynı hata (satır / sütun / sayı farkıyla) aynı parmak izi', () => {
    const a = fingerprintOf(base());
    assert.match(a, /^[0-9a-f]{64}$/);
    const shifted = normalizeReport(
      sample({
        message: 'RenderFlex overflowed by 31 pixels',
        stack: '#0      RenderFlex.performLayout (package:flutter/src/rendering/flex.dart:1042:9)\n#1      main (package:site_kapi_kontrol/main.dart:57:3)',
      }),
    ).report;
    assert.equal(fingerprintOf(shifted), a);
  });

  it('sürüm, platform, tür, mesaj metni veya ilk kareler değişirse farklı; 6. kareden sonrası etkisiz', () => {
    const a = fingerprintOf(base());
    for (const change of [{ app_version: '1.0.1' }, { platform: 'ios' }, { error_type: 'StateError' }, { message: 'Başka bir hata' }, { stack: '#0 baska (package:x/y.dart:1:1)' }]) {
      assert.notEqual(fingerprintOf(normalizeReport(sample(change)).report), a, JSON.stringify(change));
    }
    const frames = (n) => Array.from({ length: n }, (_, i) => `#${i} frame${i} (package:x/y.dart:${i}:1)`).join('\n');
    const withTail = (tail) => normalizeReport(sample({ stack: `${frames(5)}\n#5 ${tail}` })).report;
    assert.equal(fingerprintOf(withTail('a')), fingerprintOf(withTail('b')));
    // build, os_version, route, fatal parmak izini DEĞİŞTİRMEZ
    assert.equal(fingerprintOf(normalizeReport(sample({ build: '99', os_version: '15', route: '/x', fatal: false })).report), a);
  });
});

describe('storeReport', () => {
  // Sahte client: tablo durumunu bellekte tutan küçük model (UPDATE / COUNT / DELETE / INSERT) + ifade günlüğü.
  function fakeDb({ rows = [], failOn = null } = {}) {
    const log = [];
    let nextId = rows.reduce((max, row) => Math.max(max, row.id ?? 0), 0) + 1;
    let tick = rows.reduce((max, row) => Math.max(max, row.last_seen ?? 0), 0) + 1;
    const state = { rows: rows.map((row) => ({ id: nextId++, last_seen: tick++, count: 1, ...row })), released: 0, connects: 0 };
    const client = {
      async query(text, params = []) {
        const sql = norm(text);
        log.push({ sql, params });
        if (failOn && failOn.test(sql)) throw Object.assign(new Error('SECRET_DB_DETAIL'), { code: 'XX000' });
        if (/^(BEGIN|COMMIT|ROLLBACK)$/.test(sql)) return ok();
        if (/^SELECT pg_advisory_xact_lock/.test(sql)) return ok();
        if (/^UPDATE client_error_reports/.test(sql)) {
          const row = state.rows.find((r) => r.fingerprint === params[0]);
          if (!row) return ok([], 0);
          row.count += 1;
          row.last_seen = tick++;
          return ok([], 1);
        }
        if (/^SELECT COUNT\(\*\)::int AS n FROM client_error_reports$/.test(sql)) return ok([{ n: state.rows.length }]);
        if (/^DELETE FROM client_error_reports/.test(sql)) {
          const victims = [...state.rows].sort((a, b) => a.count - b.count || a.last_seen - b.last_seen || a.id - b.id).slice(0, params[0]);
          state.rows = state.rows.filter((r) => !victims.includes(r));
          return ok([], victims.length);
        }
        if (/^INSERT INTO client_error_reports/.test(sql)) {
          state.rows.push({ id: nextId++, fingerprint: params[0], count: 1, last_seen: tick++ });
          return ok([], 1);
        }
        throw new Error(`SAHTE VERITABANI: tanimsiz SQL: ${sql}`);
      },
      release() {
        state.released += 1;
      },
    };
    return {
      log,
      state,
      connect: async () => {
        state.connects += 1;
        return client;
      },
      sqls: () => log.map((entry) => entry.sql),
    };
  }
  const reportOf = (n) => normalizeReport(sample({ message: `Hata ${String.fromCharCode(97 + (n % 26))}${'x'.repeat(Math.floor(n / 26))}`, stack: `#0 f_${n.toString(36)}_${'z'.repeat(n % 7)} (x.dart:1:1)` })).report;
  // Her n için farklı parmak izi üretmek için kelime farkı gerekir (rakamlar parmak izinde normalleştirilir).
  const distinct = (n) => normalizeReport(sample({ error_type: `Tip${'abcdefghij'[n % 10]}${'klmnopqrst'[Math.floor(n / 10) % 10]}${'uvwxyzabcd'[Math.floor(n / 100) % 10]}`, message: 'm', stack: null })).report;

  it('YENİ parmak izi, tavan altında: BEGIN -> kilit -> UPDATE (ıska) -> COUNT -> INSERT -> COMMIT; çıkarma YOK; kullanıcı / IP / install_id saklanmaz', async () => {
    const db = fakeDb();
    const report = reportOf(1);
    const result = await storeReport(report, { connect: db.connect, max: 100 });
    assert.deepEqual({ ...result, fingerprint: undefined }, { stored: true, inserted: true, evicted: 0, fingerprint: undefined });
    assert.equal(result.fingerprint, fingerprintOf(report));
    const sqls = db.sqls();
    assert.equal(sqls[0], 'BEGIN');
    assert.match(sqls[1], /^SELECT pg_advisory_xact_lock\(\$1::int, \$2::int\)$/);
    assert.deepEqual(db.log[1].params, [PURGE_LOCK_CLASS, WRITE_LOCK_JOB]);
    assert.match(sqls[2], /^UPDATE client_error_reports SET count = LEAST\(count, 2147483646\) \+ 1, last_seen = NOW\(\), fatal = fatal OR \$2, build = COALESCE\(\$3, build\), os_version = COALESCE\(\$4, os_version\), route = COALESCE\(\$5, route\) WHERE fingerprint = \$1$/);
    assert.match(sqls[3], /^SELECT COUNT\(\*\)::int AS n FROM client_error_reports$/);
    assert.match(sqls[4], /^INSERT INTO client_error_reports/);
    assert.equal(sqls.at(-1), 'COMMIT');
    assert.equal(sqls.some((s) => /^DELETE/.test(s)), false);
    const insert = db.log[4];
    assert.deepEqual(insert.params, [result.fingerprint, 'FlutterError', report.message, '1.0.0', '12', 'android', '14', '/home', true, report.stack]);
    assert.equal(JSON.stringify(db.log.map((e) => e.params)).includes(INSTALL), false, 'install_id veritabanına yazılmaz');
    assert.equal(db.state.released, 1);
  });

  it('VAR OLAN parmak izi: yalnız UPDATE (sayaç artar); COUNT / INSERT / DELETE yok — tavan dolu olsa da', async () => {
    const report = reportOf(2);
    const fingerprint = fingerprintOf(report);
    const db = fakeDb({ rows: [{ fingerprint, count: 4 }, { fingerprint: 'b'.repeat(64) }] });
    const result = await storeReport(report, { connect: db.connect, max: 2 });
    assert.deepEqual({ stored: result.stored, inserted: result.inserted, evicted: result.evicted }, { stored: true, inserted: false, evicted: 0 });
    assert.deepEqual(db.sqls().map((s) => s.split(' ')[0]), ['BEGIN', 'SELECT', 'UPDATE', 'COMMIT']);
    assert.equal(db.state.rows.find((r) => r.fingerprint === fingerprint).count, 5);
    assert.equal(db.state.rows.length, 2);
  });

  it('TAVAN DOLUYSA: yeni parmak izi REDDEDİLMEZ; en az görülen / en eski satırlar atılır (tavanın %5\'i + 1), sonra eklenir', async () => {
    const rows = Array.from({ length: 100 }, (_, i) => ({ fingerprint: `${String(i).padStart(2, '0')}`.repeat(32), count: i < 5 ? 50 : 1 }));
    const db = fakeDb({ rows });
    const result = await storeReport(reportOf(3), { connect: db.connect, max: 100 });
    assert.equal(result.inserted, true);
    assert.equal(result.evicted, evictionBatch(100));
    assert.equal(evictionBatch(100), 5);
    const del = db.log.find((e) => /^DELETE/.test(e.sql));
    assert.match(del.sql, /ORDER BY count ASC, last_seen ASC, id ASC LIMIT \$1\)$/);
    assert.deepEqual(del.params, [5], 'total (100) - max (100) + batch (5)');
    assert.ok(db.sqls().indexOf(del.sql) < db.sqls().findIndex((s) => /^INSERT/.test(s)), 'önce yer açılır, sonra eklenir');
    assert.equal(db.state.rows.length, 96);
    // tekrarlayan (count 50) satırlar KORUNDU; atılanlar count 1'lerin en eskileri (ilk 5 count=1 satırı: index 5..9)
    assert.equal(db.state.rows.filter((r) => r.count === 50).length, 5);
    for (let i = 5; i < 10; i += 1) assert.equal(db.state.rows.some((r) => r.fingerprint === `${String(i).padStart(2, '0')}`.repeat(32)), false, `eski tek seferlik satır ${i} atılmalı`);
  });

  it('çıkarma sırası: önce düşük sayaç, eşitlikte eski last_seen; yüksek sayaçlı eski kayıt, yeni tek seferlik kayıttan SONRA gider', async () => {
    // dizi sırası = last_seen sırası (ilk = en eski): a (eski, sayaç 9), c (sayaç 1, daha eski), b (sayaç 1, daha yeni)
    const db = fakeDb({ rows: [{ fingerprint: 'a'.repeat(64), count: 9 }, { fingerprint: 'c'.repeat(64), count: 1 }, { fingerprint: 'b'.repeat(64), count: 1 }] });
    await storeReport(reportOf(4), { connect: db.connect, max: 3 });
    const left = db.state.rows.map((r) => r.fingerprint[0]).sort();
    assert.deepEqual(left, ['a', 'b', String(fingerprintOf(reportOf(4))[0])].sort(), 'c (sayaç 1, en eski) atıldı; a (sayaç 9) ve b kaldı');
  });

  it('SÜREKLİ AKIŞ: tavan 5 iken 60 farklı rapor — tablo HİÇBİR ANDA tavanı aşmaz; yüksek sayaçlı gerçek çökme hep kalır', async () => {
    const real = reportOf(5);
    const db = fakeDb({ rows: [{ fingerprint: fingerprintOf(real), count: 40 }] });
    let peak = 0;
    for (let n = 0; n < 60; n += 1) {
      await storeReport(distinct(n), { connect: db.connect, max: 5 });
      peak = Math.max(peak, db.state.rows.length);
      assert.ok(db.state.rows.some((r) => r.fingerprint === fingerprintOf(real)), `${n}. rapordan sonra gerçek çökme silinmemeli`);
    }
    assert.ok(peak <= 5, `tavan aşıldı: ${peak}`);
  });

  it('hata: ROLLBACK, bağlantı iade, hata yukarı (rota yutar -> 202)', async () => {
    const db = fakeDb({ failOn: /^INSERT/ });
    await assert.rejects(storeReport(reportOf(6), { connect: db.connect, max: 10 }), /SECRET_DB_DETAIL/);
    assert.equal(db.sqls().at(-1), 'ROLLBACK');
    assert.equal(db.state.released, 1);
  });

  it('yazma kapısı: eşzamanlı yazıcı sayısı sınırlı; kuyruk dolunca rapor ATILIR ({ stored: false, dropped: true }), bağlantı hiç alınmaz', async () => {
    const gate = createWriteGate({ max: 3, queueLimit: 2 });
    let active = 0;
    let peak = 0;
    const release = [];
    const task = () =>
      new Promise((resolve) => {
        active += 1;
        peak = Math.max(peak, active);
        release.push(() => {
          active -= 1;
          resolve('ok');
        });
      });
    const runs = Array.from({ length: 7 }, () => gate.run(task));
    await new Promise((resolve) => setTimeout(resolve, 10));
    assert.deepEqual(gate.stats(), { active: 3, waiting: 2 });
    const results = [];
    // 3 çalışan + 2 bekleyen = 5 kabul; 2 rapor kuyruk doluyken atıldı
    while (release.length > 0) {
      release.shift()();
      await new Promise((resolve) => setTimeout(resolve, 5));
    }
    results.push(...(await Promise.all(runs)));
    assert.equal(results.filter((r) => r.dropped).length, 2);
    assert.equal(results.filter((r) => !r.dropped).length, 5);
    assert.ok(peak <= 3, `eşzamanlı yazıcı ${peak}`);
    assert.deepEqual(gate.stats(), { active: 0, waiting: 0 });

    const full = createWriteGate({ max: 1, queueLimit: 0 });
    let blocker;
    const first = full.run(() => new Promise((resolve) => { blocker = resolve; }));
    const db = fakeDb();
    const dropped = await storeReport(reportOf(7), { connect: db.connect, gate: full });
    assert.deepEqual({ stored: dropped.stored, dropped: dropped.dropped }, { stored: false, dropped: true });
    assert.equal(db.state.connects, 0);
    blocker();
    await first;
  });

  it('VARSAYILAN kapı TEK yazıcıdır (kilit bekleyen boş bağlantı yok): 50 eşzamanlı görev ARDIŞIK çalışır (en çok 1 eşzamanlı), FIFO; kuyruk sınırı 200', async () => {
    const gate = createWriteGate();
    let active = 0;
    let peak = 0;
    const order = [];
    const task = (n) => async () => {
      active += 1;
      peak = Math.max(peak, active);
      await new Promise((resolve) => setTimeout(resolve, 1));
      order.push(n);
      active -= 1;
    };
    const results = await Promise.all(Array.from({ length: 50 }, (_, n) => gate.run(task(n))));
    assert.equal(peak, 1, 'varsayılan kapıda aynı anda en çok 1 bağlantı kullanılır');
    assert.deepEqual(order, Array.from({ length: 50 }, (_, n) => n), 'FIFO');
    assert.ok(results.every((r) => r.dropped === false));

    // 1 çalışan + 200 bekleyen kabul; 202. ve sonrası atılır
    const full = createWriteGate();
    const releases = [];
    const blocked = () => new Promise((resolve) => releases.push(resolve));
    const runs = Array.from({ length: 205 }, () => full.run(blocked));
    await new Promise((resolve) => setTimeout(resolve, 10));
    assert.deepEqual(full.stats(), { active: 1, waiting: 200 });
    const dropped = (await Promise.all(runs.slice(201))).filter((r) => r.dropped).length;
    assert.equal(dropped, 4);
    while (releases.length > 0) {
      releases.shift()();
      await new Promise((resolve) => setImmediate(resolve));
    }
    const settled = await Promise.all(runs);
    assert.equal(settled.filter((r) => !r.dropped).length, 201);
    assert.deepEqual(full.stats(), { active: 0, waiting: 0 });
  });

  it('görev hatası kapıyı kilitlemez (slot iade edilir)', async () => {
    const gate = createWriteGate({ max: 1, queueLimit: 5 });
    await assert.rejects(gate.run(async () => { throw new Error('boom'); }), /boom/);
    assert.deepEqual(gate.stats(), { active: 0, waiting: 0 });
    assert.equal((await gate.run(async () => 7)).value, 7);
  });

  it('CLIENT_ERROR_MAX_ROWS tavanı ayarlar; geçersiz değerde varsayılan 20000; çıkarma payı tavanın %5\'i (en az 1)', () => {
    assert.equal(maxRows({}), 20000);
    assert.equal(maxRows({ CLIENT_ERROR_MAX_ROWS: '500' }), 500);
    for (const bad of ['0', '-5', 'abc', '1.5', '']) assert.equal(maxRows({ CLIENT_ERROR_MAX_ROWS: bad }), 20000, bad);
    assert.equal(evictionBatch(20000), 1000);
    assert.equal(evictionBatch(3), 1);
    assert.equal(evictionBatch(1), 1);
  });
});

describe('listeleme ve imleç', () => {
  const row = (id, lastSeen) => ({
    id: String(id),
    fingerprint: 'f'.repeat(64),
    error_type: 'FlutterError',
    message: 'mesaj',
    app_version: '1.0.0',
    platform: 'android',
    fatal: false,
    count: 3,
    first_seen: new Date('2026-10-01T00:00:00.000Z'),
    last_seen: new Date(lastSeen),
    sample_stack: null,
    last_seen_text: `${new Date(lastSeen).toISOString().slice(0, -1)}123Z`,
  });

  it('clampListLimit: varsayılan 50, en çok 200, en az 1', () => {
    assert.equal(LIST_DEFAULT_LIMIT, 50);
    assert.equal(LIST_MAX_LIMIT, 200);
    assert.equal(clampListLimit(undefined), 50);
    assert.equal(clampListLimit(''), 50);
    assert.equal(clampListLimit('abc'), 50);
    assert.equal(clampListLimit('7'), 7);
    assert.equal(clampListLimit('5000'), 200);
    assert.equal(clampListLimit('0'), 1);
    assert.equal(clampListLimit('-9'), 1);
    assert.equal(clampListLimit('3.9'), 3);
  });

  it('imleç gidiş-dönüş; biçimsiz imleç null', () => {
    const cursor = encodeCursor('2026-10-16T10:00:00.123456Z', '77');
    assert.deepEqual(decodeCursor(cursor), { lastSeen: '2026-10-16T10:00:00.123456Z', id: '77' });
    for (const bad of ['', 'abc', 'e30', Buffer.from('["x","1"]').toString('base64url'), Buffer.from('["2026-10-16T10:00:00.123456Z","1; DROP"]').toString('base64url'), Buffer.from('{"a":1}').toString('base64url')]) {
      assert.equal(decodeCursor(bad), null, bad);
    }
  });

  it('limit + 1 satır çekilir; fazlası varsa next_cursor son SAYFA satırından; yoksa null', async () => {
    const seen = [];
    const rows = [row(30, '2026-10-16T10:00:03Z'), row(20, '2026-10-16T10:00:02Z'), row(10, '2026-10-16T10:00:01Z')];
    const db = {
      async query(text, params) {
        seen.push({ sql: norm(text), params });
        return ok(rows);
      },
    };
    const page = await listReports({ limit: '2' }, db);
    assert.deepEqual(seen[0].params, [null, null, 3]);
    assert.match(seen[0].sql, /ORDER BY last_seen DESC, id DESC LIMIT \$3$/);
    assert.match(seen[0].sql, /\(\$1::timestamptz IS NULL OR \(last_seen, id\) < \(\$1::timestamptz, \$2::bigint\)\)/);
    assert.equal(page.items.length, 2);
    assert.deepEqual(Object.keys(page.items[0]), ['fingerprint', 'error_type', 'message', 'app_version', 'platform', 'fatal', 'count', 'first_seen', 'last_seen', 'sample_stack']);
    assert.equal(page.items[0].last_seen, '2026-10-16T10:00:03.000Z');
    assert.equal(page.items[0].count, 3);
    assert.deepEqual(decodeCursor(page.next_cursor), { lastSeen: '2026-10-16T10:00:02.000123Z', id: '20' });

    const last = await listReports({ limit: '3' }, db);
    assert.equal(last.next_cursor, null);
    assert.equal(last.items.length, 3);

    const next = await listReports({ limit: '2', cursor: page.next_cursor }, db);
    assert.deepEqual(seen.at(-1).params, ['2026-10-16T10:00:02.000123Z', '20', 3]);
    assert.ok(next.items.length > 0);
  });

  it('geçersiz imleç 400 INVALID_CURSOR (veritabanına gitmeden)', async () => {
    let touched = false;
    await assert.rejects(
      listReports({ cursor: 'bozuk' }, { query: async () => { touched = true; return ok(); } }),
      (error) => error.statusCode === 400 && error.code === 'INVALID_CURSOR',
    );
    assert.equal(touched, false);
  });
});

describe('purgeOldReports (90 gün, tek çalışan)', () => {
  function fakeConnect({ locked = true, batches = [0], failOn = null } = {}) {
    const log = [];
    let released = 0;
    let deletes = 0;
    const client = {
      async query(text, params = []) {
        const sql = norm(text);
        log.push({ sql, params });
        if (failOn && failOn.test(sql)) throw Object.assign(new Error('SECRET_DB_DETAIL'), { code: 'XX000' });
        if (/^(BEGIN|COMMIT|ROLLBACK)$/.test(sql)) return ok();
        if (/^SELECT pg_try_advisory_xact_lock/.test(sql)) return ok([{ locked }]);
        if (/^DELETE FROM client_error_reports/.test(sql)) {
          const count = batches[Math.min(deletes, batches.length - 1)];
          deletes += 1;
          return ok([], count);
        }
        throw new Error(`SAHTE VERITABANI: tanimsiz SQL: ${sql}`);
      },
      release() {
        released += 1;
      },
    };
    return { log, connect: async () => client, released: () => released };
  }

  it('kilit alınamazsa ATLANIR (çift çalışma yok): silme yok, ROLLBACK, bağlantı iade', async () => {
    const f = fakeConnect({ locked: false });
    const result = await purgeOldReports({ connect: f.connect });
    assert.deepEqual(result, { skipped: true, deleted: 0 });
    assert.equal(f.log.some((e) => /^DELETE/.test(e.sql)), false);
    assert.equal(f.log.at(-1).sql, 'ROLLBACK');
    assert.equal(f.released(), 1);
    assert.deepEqual(f.log[1].params, [PURGE_LOCK_CLASS, PURGE_LOCK_JOB]);
  });

  it('kilit alınınca BEGIN -> kilit -> parti parti DELETE (parti dolmadıkça devam) -> COMMIT; 90 gün first_seen', async () => {
    const f = fakeConnect({ batches: [2000, 2000, 150] });
    const result = await purgeOldReports({ connect: f.connect });
    assert.deepEqual(result, { skipped: false, deleted: 4150 });
    const sqls = f.log.map((e) => e.sql);
    assert.equal(sqls[0], 'BEGIN');
    assert.match(sqls[1], /^SELECT pg_try_advisory_xact_lock\(\$1::int, \$2::int\) AS locked$/);
    assert.equal(sqls.filter((s) => /^DELETE/.test(s)).length, 3);
    assert.equal(sqls.at(-1), 'COMMIT');
    const del = f.log.find((e) => /^DELETE/.test(e.sql));
    assert.match(del.sql, /WHERE first_seen < NOW\(\) - make_interval\(days => \$1::int\)/);
    assert.deepEqual(del.params, [RETENTION_DAYS]);
    assert.equal(RETENTION_DAYS, 90);
    assert.equal(f.released(), 1);
  });

  it('silinecek satır yoksa tek DELETE ile biter', async () => {
    const f = fakeConnect({ batches: [0] });
    assert.deepEqual(await purgeOldReports({ connect: f.connect }), { skipped: false, deleted: 0 });
    assert.equal(f.log.filter((e) => /^DELETE/.test(e.sql)).length, 1);
  });

  it('hata: ROLLBACK, bağlantı iade, hata yukarı', async () => {
    const f = fakeConnect({ failOn: /^DELETE/ });
    await assert.rejects(purgeOldReports({ connect: f.connect }), /SECRET_DB_DETAIL/);
    assert.equal(f.log.at(-1).sql, 'ROLLBACK');
    assert.equal(f.released(), 1);
  });
});

describe('silme zamanlayıcısı', () => {
  afterEach(async () => {
    await stopClientErrorPurge();
  });

  it('CLIENT_ERROR_PURGE_DISABLED ile kapalı; açıkken tek kez başlar ve durdurulabilir', async () => {
    for (const value of ['1', 'true', 'YES']) assert.equal(isPurgeDisabled({ CLIENT_ERROR_PURGE_DISABLED: value }), true, value);
    for (const value of ['', '0', 'false', undefined]) assert.equal(isPurgeDisabled({ CLIENT_ERROR_PURGE_DISABLED: value }), false, String(value));
    assert.equal(startClientErrorPurge({ env: { CLIENT_ERROR_PURGE_DISABLED: '1' } }), null);
    let runs = 0;
    const handle = startClientErrorPurge({ env: {}, intervalMs: 1_000_000, firstDelayMs: 5, purge: async () => { runs += 1; return { skipped: false, deleted: 0 }; } });
    assert.ok(handle);
    assert.equal(startClientErrorPurge({ env: {}, purge: async () => ({}) }), null, 'ikinci başlatma yok sayılır');
    await new Promise((resolve) => setTimeout(resolve, 60));
    assert.equal(runs, 1);
    await stopClientErrorPurge();
    assert.ok(startClientErrorPurge({ env: {}, intervalMs: 1_000_000, firstDelayMs: 1_000_000, purge: async () => ({}) }), 'durdurulduktan sonra yeniden başlatılabilir');
  });

  it('runClientErrorPurge hata fırlatmaz (yalnız koda günlük); eşzamanlı çağrılar aynı turu paylaşır', async () => {
    const errors = mock.method(console, 'error', () => {});
    const failed = await runClientErrorPurge(async () => {
      throw Object.assign(new Error('SECRET_DB_DETAIL'), { code: 'XX000' });
    });
    assert.equal(failed.failed, true);
    assert.ok(errors.mock.calls[0].arguments.join(' ').includes('XX000'));
    assert.equal(errors.mock.calls[0].arguments.join(' ').includes('SECRET_DB_DETAIL'), false);

    let calls = 0;
    const slow = async () => {
      calls += 1;
      await new Promise((resolve) => setTimeout(resolve, 20));
      return { skipped: false, deleted: 0 };
    };
    await Promise.all([runClientErrorPurge(slow), runClientErrorPurge(slow), runClientErrorPurge(slow)]);
    assert.equal(calls, 1);
  });
});
