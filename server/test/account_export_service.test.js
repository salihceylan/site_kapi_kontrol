// Kişisel veri dışa aktarma (DB'siz): sorgularda yasak sütun YOK (sızdırma), her sorgu çağıranın user_code'una bağlı, boyut sınırı / kısaltma,
// hız sınırı sayacı (24 saatte 3), istek sırası (parola -> hak -> üretim; başarısızlıkta iade), veri şekli. Gerçek PG: scripts/qa_platform_pg.mjs "account".
import { describe, it, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { pool } from '../src/db.js';
import {
  EXPORT_EXCLUDED,
  EXPORT_NOTICE,
  SHRINKABLE_SECTIONS,
  acquireExportSlot,
  collectHooks,
  collectPersonalData,
  exportDeps,
  exportInternals,
  exportMyData,
  recordExportAudit,
  releaseExportSlot,
  serializeWithinLimit,
} from '../src/modules/account_export_service.js';
import { EXPORT_MAX_BYTES } from '../src/modules/account_common.js';
import { PlatformError } from '../src/modules/errors.js';
import { resetPeopleSyncThrottle } from '../src/modules/people_sync.js';

const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
const ok = (rows = [], rowCount = rows.length) => ({ rows, rowCount });

describe('dışa aktarma sorguları: sızdırma koruması (kaynak düzeyi)', () => {
  const entries = Object.entries(exportInternals.SQL);

  it('her sorgu çağıranın user_code\'una ($1) bağlıdır ve sabit metindir (şablon enterpolasyonu yok)', () => {
    assert.ok(entries.length >= 15);
    for (const [name, sql] of entries) {
      assert.ok(sql.includes('$1'), `${name}: $1 bağlaması yok`);
      assert.equal(/\$\{/.test(sql), false, `${name}: enterpolasyon`);
      assert.equal(/SELECT\s+\*/i.test(sql), false, `${name}: SELECT *`);
    }
  });

  it('yasak sütunlar / takma adlar HİÇBİR sorguda seçilmez: parola özeti, belirteçler, erişim kodları, cihaz sırları, yönetici notları ve gerekçeleri, başkasının kimliği', () => {
    const forbidden = [
      /password_hash/i,
      /password_reset/i,
      /email_verification/i,
      /local_control_token/i,
      /mqtt_(username|password)/i,
      /inventory_notes/i,
      /defective_/i,
      /decision_note/i,
      /decision_source/i,
      /payment_/i,
      /rejection_reason/i,
      /reviewed_by/i,
      /granted_by/i,
      /decided_by/i,
      /created_by(?!_user_code)/i,
      /invited_by/i,
      /\b\w+\.token\b/i, // misafir geçişi / karekod / davet belirteçleri
      /\bsp\.note\b/i, // kişi kaydındaki yönetici iç notu
      /\bv\.note\b/i, // araç notu
      /\bdao\.notes\b/i, // kapı izni notu
      /\bqr_totp_secret\b/i,
      /\bresident_pin_code\b/i,
      /\bresident_email\b/i,
    ];
    for (const [name, sql] of entries) {
      // İş Takibi (042): sahiplik süzgeci `WHERE w.created_by = $1` çağıranın KENDİ kaydını seçer; sütun SEÇİLMEZ (başka kullanıcının kimliği çıkmaz). Başka her created_by kullanımı yine yasaktır.
      const checked = name === 'workItems' ? sql.replace('WHERE w.created_by = $1', 'WHERE w.OWNER_FILTER = $1') : sql;
      for (const pattern of forbidden) {
        assert.equal(pattern.test(checked), false, `${name}: yasak ifade ${pattern}`);
      }
    }
  });

  it('başkasının kişisel verisine join yok: users tablosu yalnız kendi satırı (user) ve cihaz sahipliği alt sorgusu için kullanılır', () => {
    for (const [name, sql] of entries) {
      if (name === 'user') continue;
      const usersJoins = sql.match(/(JOIN|FROM)\s+users\b/gi) ?? [];
      if (name === 'devices') {
        assert.equal(usersJoins.length, 1, 'devices: yalnız sahiplik alt sorgusu');
        assert.ok(/owner_user_id = \(SELECT id FROM users WHERE user_code = \$1\)/.test(norm(sql)));
      } else {
        assert.equal(usersJoins.length, 0, `${name}: users join'i`);
      }
    }
  });

  it('R6: misafir geçişiyle açılan kapı olayının IP adresi (kapıyı açan MİSAFİRİN adresi, üçüncü kişi verisi) dosyada boş; diğer tetikleyicilerin IP\'si kullanıcıya aittir ve kalır', () => {
    const sql = norm(exportInternals.SQL.doorEvents);
    assert.ok(sql.includes("CASE WHEN trigger_type = 'guest_pass' THEN NULL ELSE ip_address END AS ip_address"), sql);
    assert.equal(/,\s*ip_address\s+FROM/.test(sql), false, 'ham ip_address sütunu doğrudan seçilmez');
    // kullanıcının kendi olayları (user_code) süzgeci ve en yeni -> en eski sıra korunur
    assert.ok(sql.endsWith('FROM door_access_logs WHERE user_code = $1 ORDER BY opened_at DESC, id DESC'));
  });

  it('dışarıda bırakılanlar listesi dolu, Türkçe ve her biri bir NEDEN taşır', () => {
    assert.ok(EXPORT_EXCLUDED.length >= 6);
    for (const line of EXPORT_EXCLUDED) {
      assert.ok(line.length > 40 && /:/.test(line), line);
    }
    assert.ok(EXPORT_NOTICE.includes('excluded'));
  });
});

describe('dışa aktarma: boyut sınırı ve kısaltma', () => {
  const base = () => ({ format_version: 1, user: { user_code: 1 }, door_events: [], announcements_received: [], excluded: ['x'] });

  it('küçük gövde değişmeden serileştirilir: truncated:false, kısaltma alanı yok', () => {
    const data = base();
    data.door_events = [{ id: 1, door_name: 'Ana Kapı' }];
    const out = serializeWithinLimit(data);
    const parsed = JSON.parse(out.text);
    assert.equal(parsed.truncated, false);
    assert.equal('truncated_sections' in parsed, false);
    assert.equal(parsed.door_events.length, 1);
    assert.equal(out.truncated, false);
    assert.ok(out.bytes < 1000);
  });

  it('sınırı aşan gövde EN BÜYÜK bölümden kısaltılır (yeni kayıtlar kalır), truncated:true + truncated_sections + açıklama', () => {
    const data = base();
    data.door_events = Array.from({ length: 4000 }, (_, i) => ({ id: i, door_name: `Kapı ${i}`, user_name: 'Ada', ip_address: '10.0.0.1' }));
    data.announcements_received = Array.from({ length: 10 }, (_, i) => ({ id: i, title: 'Duyuru', body: 'x'.repeat(200) }));
    const limit = 120 * 1024;
    const out = serializeWithinLimit(data, [], limit);
    const parsed = JSON.parse(out.text);
    assert.ok(out.bytes <= limit, `${out.bytes} <= ${limit}`);
    assert.equal(parsed.truncated, true);
    assert.equal(out.truncated, true);
    const entry = parsed.truncated_sections.find((section) => section.section === 'door_events');
    assert.ok(entry && entry.reason === 'size_limit' && entry.included === parsed.door_events.length && entry.included < 4000);
    assert.equal(parsed.door_events[0].id, 0, 'en yeni (ilk) kayıtlar korunur');
    assert.equal(parsed.announcements_received.length, 10, 'küçük bölüm gereksiz kısaltılmaz');
    assert.ok(/kısaltıldı/.test(parsed.truncation_note));
  });

  it('satır sınırından gelen kısaltma kaydı korunur; boyutla da kısaltılırsa neden size_limit olur', () => {
    const data = base();
    data.door_events = Array.from({ length: 100 }, (_, i) => ({ id: i }));
    let out = serializeWithinLimit(data, [{ section: 'door_events', included: 100, reason: 'row_limit' }]);
    let parsed = JSON.parse(out.text);
    assert.equal(parsed.truncated, true);
    assert.deepEqual(parsed.truncated_sections, [{ section: 'door_events', included: 100, reason: 'row_limit' }]);

    const big = base();
    big.door_events = Array.from({ length: 3000 }, (_, i) => ({ id: i, pad: 'x'.repeat(100) }));
    out = serializeWithinLimit(big, [{ section: 'door_events', included: 3000, reason: 'row_limit' }], 50 * 1024);
    parsed = JSON.parse(out.text);
    assert.equal(parsed.truncated_sections.length, 1);
    assert.equal(parsed.truncated_sections[0].reason, 'size_limit');
  });

  it('kısaltılabilir bölüm kalmadan sığmıyorsa hata (sessiz taşma yok)', () => {
    const data = base();
    data.user = { huge: 'x'.repeat(3000) };
    assert.throws(
      () => serializeWithinLimit(data, [], 1000),
      (error) => error instanceof PlatformError && error.statusCode === 413 && error.code === 'EXPORT_TOO_LARGE' && /sığmayacak/.test(error.message),
    );
  });

  it('R2 F-10: kısaltılamayan bölüm (üyelikler) tek başına 5 MB\'ı aşarsa 413 EXPORT_TOO_LARGE; kısaltılabilir bölümler önce boşaltılır (kayıp bildirilir) ama sonuç yine hata', () => {
    const data = base();
    data.memberships = Array.from({ length: 200 }, (_, i) => ({ id: i, site_name: 'S'.repeat(400) }));
    data.door_events = Array.from({ length: 50 }, (_, i) => ({ id: i }));
    assert.throws(() => serializeWithinLimit(data, [], 20 * 1024), (error) => error.statusCode === 413 && error.code === 'EXPORT_TOO_LARGE');
    // varsayılan sınır gerçekten 5 MB: 5 MB + 1 baytlık kimlik bölümü de reddedilir, 5 MB altı kabul edilir
    const huge = base();
    huge.user = { filler: 'x'.repeat(EXPORT_MAX_BYTES + 10) };
    assert.throws(() => serializeWithinLimit(huge), (error) => error.code === 'EXPORT_TOO_LARGE');
    const fits = base();
    fits.user = { filler: 'x'.repeat(EXPORT_MAX_BYTES - 1024) };
    assert.equal(serializeWithinLimit(fits).truncated, false);
  });

  it('R2 F-10: kısaltma bölümün BAŞINDAN kayıt tutar; kişi kayıtları / araçlar / cihazlar sorguları en yeni -> en eski (id DESC) sıralıdır', () => {
    for (const name of ['people', 'vehicles', 'devices']) {
      assert.match(norm(exportInternals.SQL[name]), /ORDER BY \w+\.id DESC$/, `${name}: en yeni önce`);
    }
    const data = base();
    data.people_records = Array.from({ length: 400 }, (_, i) => ({ id: 400 - i, full_name: 'K'.repeat(120) }));
    const out = serializeWithinLimit(data, [], 20 * 1024);
    const parsed = JSON.parse(out.text);
    assert.equal(parsed.truncated_sections.find((entry) => entry.section === 'people_records').reason, 'size_limit');
    assert.equal(parsed.people_records[0].id, 400, 'en yeni kayıt (en büyük id) korunur');
    assert.ok(parsed.people_records.length < 400);
  });

  it('varsayılan sınır 5 MB ve kısaltılabilir bölümler beklenen kümedir (kişi / finans verisi dahil, kimlik bölümleri hariç)', () => {
    assert.equal(EXPORT_MAX_BYTES, 5 * 1024 * 1024);
    for (const name of ['door_events', 'announcements_received', 'qr_requests', 'finance_statements']) {
      assert.ok(SHRINKABLE_SECTIONS.includes(name), name);
    }
    for (const name of ['user', 'consents', 'excluded', 'notification_preferences']) {
      assert.equal(SHRINKABLE_SECTIONS.includes(name), false, name);
    }
  });
});

describe('dışa aktarma: hız sınırı sayacı (24 saatte 3)', () => {
  function fakeDb({ used = 0, retryAfter = 7200, user = { user_code: 12345 } } = {}) {
    const log = [];
    const client = {
      query: async (text, params) => {
        const sql = norm(text);
        log.push({ sql, params: params ?? [] });
        if (/^SELECT user_code FROM users WHERE user_code = \$1 AND deleted_at IS NULL FOR KEY SHARE$/.test(sql)) return ok(user ? [user] : []);
        if (/^SELECT COUNT\(\*\)::INTEGER AS used/.test(sql)) return ok([{ used, retry_after: retryAfter }]);
        if (/^INSERT INTO account_data_exports/.test(sql)) return ok([{ id: '901' }]);
        return ok();
      },
      release() {},
    };
    return { log, db: { connect: async () => client } };
  }

  it('sınır altında: kullanıcı başına advisory kilit ALTINDA sayılır ve eklenir; COMMIT; hak kimliği döner', async () => {
    const { log, db } = fakeDb({ used: 2 });
    const slot = await acquireExportSlot(12345, db);
    assert.equal(slot, 901);
    const sqls = log.map((entry) => entry.sql);
    assert.equal(sqls[0], 'BEGIN');
    assert.ok(/^SELECT pg_advisory_xact_lock\(hashtext\(\$1\)\)$/.test(sqls[1]));
    assert.equal(log[1].params[0], 'account_export:12345');
    // R16 P2-3: canlı kullanıcı kilidi (deleted_at IS NULL ... FOR KEY SHARE) sayım ve EKLEMEDEN önce, aynı işlemde
    const lockAt = sqls.findIndex((s) => /FOR KEY SHARE$/.test(s));
    assert.ok(lockAt > 1 && lockAt < sqls.findIndex((s) => /^SELECT COUNT/.test(s)), sqls.join(' | '));
    assert.deepEqual(log[lockAt].params, [12345]);
    assert.equal(sqls.some((s) => /^SELECT deleted_at FROM users/.test(s)), false, 'kilitsiz deleted_at okuması kalmadı');
    assert.ok(sqls.findIndex((s) => /^SELECT COUNT/.test(s)) < sqls.findIndex((s) => /^INSERT INTO/.test(s)), 'sayım ekleme öncesi (aynı kilit altında)');
    assert.equal(sqls.at(-1), 'COMMIT');
    const count = log.find((entry) => /^SELECT COUNT/.test(entry.sql));
    assert.deepEqual(count.params, [12345, 24]);
    assert.ok(log.some((entry) => /DELETE FROM account_data_exports WHERE user_code = \$1 AND requested_at < NOW\(\) - INTERVAL '7 days'/.test(entry.sql)));
  });

  it('3 kullanılmış: 429 EXPORT_RATE_LIMITED + retry_after_seconds, ekleme YOK, ROLLBACK', async () => {
    const { log, db } = fakeDb({ used: 3, retryAfter: 5400 });
    await assert.rejects(acquireExportSlot(12345, db), (error) => {
      assert.equal(error.statusCode, 429);
      assert.equal(error.code, 'EXPORT_RATE_LIMITED');
      assert.equal(error.extra.retry_after_seconds, 5400);
      return true;
    });
    assert.equal(log.some((entry) => /^INSERT/.test(entry.sql)), false);
    assert.equal(log.some((entry) => /^COMMIT$/.test(entry.sql)), false);
    assert.equal(log.at(-1).sql, 'ROLLBACK');
  });

  it('silinmiş / olmayan hesap: 401 ACCOUNT_DELETED, ekleme yok', async () => {
    // satır dönmez: kullanıcı yok YA DA silinmiş (sorgu deleted_at IS NULL ister; silme COMMIT'ini bekledikten sonra satır eşleşmez)
    const { log, db } = fakeDb({ user: null });
    await assert.rejects(acquireExportSlot(12345, db), (error) => error.code === 'ACCOUNT_DELETED' && error.statusCode === 401);
    assert.equal(log.some((entry) => /^INSERT/.test(entry.sql)), false);
    assert.equal(log.some((entry) => /^COMMIT$/.test(entry.sql)), false);
    assert.equal(log.at(-1).sql, 'ROLLBACK');
  });

  it('hak iadesi: belirli kaydı siler; veritabanı hatası yutulur ve yalnız kodla loglanır', async () => {
    const calls = [];
    await releaseExportSlot(901, { query: async (text, params) => calls.push([norm(text), params]) });
    assert.deepEqual(calls, [['DELETE FROM account_data_exports WHERE id = $1', [901]]]);

    const original = console.error;
    const logged = [];
    console.error = (...args) => logged.push(args.map(String).join(' '));
    try {
      await releaseExportSlot(901, {
        query: async () => {
          throw Object.assign(new Error('detail ada@example.com'), { code: '57014' });
        },
      });
    } finally {
      console.error = original;
    }
    assert.ok(logged.join('\n').includes('57014'));
    assert.equal(/ada@example/.test(logged.join('\n')), false);
  });
});

describe('dışa aktarma: istek akışı (parola -> hak -> üretim; başarısızlıkta iade)', () => {
  let saved;
  let order;
  beforeEach(() => {
    saved = { ...exportDeps };
    order = [];
    exportDeps.verifyPassword = async (input) => {
      order.push(['password', input.userCode, input.currentPassword]);
    };
    exportDeps.acquireSlot = async () => {
      order.push(['slot']);
      return 77;
    };
    exportDeps.releaseSlot = async (id) => {
      order.push(['release', id]);
    };
    exportDeps.audit = async (userCode, details) => {
      order.push(['audit', userCode, details]);
    };
    exportDeps.collect = async (userCode) => {
      order.push(['collect', userCode]);
      return { data: { format_version: 1, user: { user_code: userCode }, door_events: [], excluded: [] }, truncated: [] };
    };
  });
  afterEach(() => {
    Object.assign(exportDeps, saved);
  });

  it('başarı: sıra parola -> hak -> üretim; dosya adı sözleşmedeki biçim; gövde JSON', async () => {
    const out = await exportMyData({ authUser: { user_code: 12345 }, body: { current_password: 'Parola-1' } }, new Date('2026-10-16T10:00:00Z'));
    assert.deepEqual(order.map((entry) => entry[0]), ['password', 'slot', 'collect', 'audit']);
    assert.equal(order[0][2], 'Parola-1');
    assert.deepEqual(Object.keys(order[3][2]).sort(), ['bytes', 'truncated'], 'denetim yalnız boyut + kısaltma bayrağı taşır (ad / e-posta yok)');
    assert.equal(order[3][1], 12345);
    assert.equal(out.filename, 'kisisel-veri-12345-20261016.json');
    assert.equal(JSON.parse(out.text).format_version, 1);
    assert.equal(out.truncated, false);
  });

  it('parola hatası: hak ALINMAZ ve üretim çalışmaz', async () => {
    exportDeps.verifyPassword = async () => {
      throw Object.assign(new Error('x'), { code: 'CURRENT_PASSWORD_INVALID' });
    };
    await assert.rejects(exportMyData({ authUser: { user_code: 12345 }, body: {} }), (e) => e.code === 'CURRENT_PASSWORD_INVALID');
    assert.deepEqual(order, []);
  });

  it('hız sınırı: üretim çalışmaz', async () => {
    exportDeps.acquireSlot = async () => {
      order.push(['slot']);
      throw Object.assign(new Error('x'), { code: 'EXPORT_RATE_LIMITED' });
    };
    await assert.rejects(exportMyData({ authUser: { user_code: 12345 }, body: {} }), (e) => e.code === 'EXPORT_RATE_LIMITED');
    assert.deepEqual(order.map((entry) => entry[0]), ['password', 'slot']);
  });

  it('üretim hatası: hak İADE edilir ve hata yukarı çıkar', async () => {
    exportDeps.collect = async () => {
      order.push(['collect']);
      throw Object.assign(new Error('boom'), { code: 'XX000' });
    };
    await assert.rejects(exportMyData({ authUser: { user_code: 12345 }, body: {} }), (e) => e.code === 'XX000');
    assert.deepEqual(order.map((entry) => entry[0]), ['password', 'slot', 'collect', 'release'], 'başarısız üretimde denetim yazılmaz');
    assert.deepEqual(order.at(-1), ['release', 77]);
  });

  it('R16 P2-3: denetim sırasında hesap silinmişse 401 ACCOUNT_DELETED; dosya DÖNMEZ ve hak İADE edilir (üretimden SONRA silme yarışı)', async () => {
    exportDeps.audit = async () => {
      order.push(['audit']);
      throw Object.assign(new Error('Bu hesap silinmiş.'), { code: 'ACCOUNT_DELETED', statusCode: 401 });
    };
    await assert.rejects(exportMyData({ authUser: { user_code: 12345 }, body: { current_password: 'Parola-1' } }), (e) => e.code === 'ACCOUNT_DELETED' && e.statusCode === 401);
    assert.deepEqual(order.map((entry) => entry[0]), ['password', 'slot', 'collect', 'audit', 'release']);
    assert.deepEqual(order.at(-1), ['release', 77]);
  });

  it('kimlik çözülemezse 401 ACCOUNT_DELETED ve hiçbir adım çalışmaz', async () => {
    await assert.rejects(exportMyData({ authUser: {}, body: {} }), (e) => e.code === 'ACCOUNT_DELETED');
    assert.deepEqual(order, []);
  });

  it('R2 F-10: kısaltılamayan dev bölüm -> 413 EXPORT_TOO_LARGE; hak İADE edilir (77), denetim yazılmaz, gövde dosya değil', async () => {
    exportDeps.collect = async (userCode) => {
      order.push(['collect', userCode]);
      return {
        data: { format_version: 1, user: { user_code: userCode }, memberships: [{ id: 1, pad: 'x'.repeat(EXPORT_MAX_BYTES + 100) }], door_events: [], excluded: [] },
        truncated: [],
      };
    };
    await assert.rejects(
      exportMyData({ authUser: { user_code: 12345 }, body: { current_password: 'Parola-1' } }),
      (e) => e instanceof PlatformError && e.statusCode === 413 && e.code === 'EXPORT_TOO_LARGE',
    );
    assert.deepEqual(order.map((entry) => entry[0]), ['password', 'slot', 'collect', 'release']);
    assert.deepEqual(order.at(-1), ['release', 77]);
  });
});

describe('dışa aktarma denetimi: canlı kullanıcı kilidi altında (R16 P2-3)', () => {
  function fakeAuditDb({ live = true } = {}) {
    const log = [];
    const client = {
      query: async (text, params) => {
        const sql = norm(text);
        log.push({ sql, params: params ?? [] });
        if (/^SELECT user_code FROM users WHERE user_code = \$1 AND deleted_at IS NULL FOR KEY SHARE$/.test(sql)) return ok(live ? [{ user_code: params[0] }] : []);
        return ok();
      },
      release() {},
    };
    return { log, db: { connect: async () => client } };
  }

  it('canlı hesap: BEGIN -> kullanıcı satırı KEY SHARE -> audit INSERT (yalnız kullanıcı kodu + bayt + kısaltma) -> COMMIT', async () => {
    const { log, db } = fakeAuditDb();
    await recordExportAudit(12345, { bytes: 4096, truncated: false }, db);
    const sqls = log.map((entry) => entry.sql);
    const lock = sqls.findIndex((sql) => /FOR KEY SHARE$/.test(sql));
    const insert = sqls.findIndex((sql) => /^INSERT INTO audit_log/.test(sql));
    assert.ok(sqls[0] === 'BEGIN' && lock > 0 && lock < insert && insert < sqls.indexOf('COMMIT'), sqls.join(' | '));
    const audit = log[insert];
    assert.equal(audit.params[0], 12345, 'actor_user_code');
    assert.equal(audit.params[1], null, 'actor adı yok');
    assert.equal(audit.params[3], 'account.data_exported');
    assert.deepEqual(JSON.parse(audit.params[7]), { bytes: 4096, truncated: false });
  });

  it('silinmiş hesap: 401 ACCOUNT_DELETED, audit satırı YAZILMAZ, ROLLBACK (silinmiş hesap adına denetim kaydı oluşmaz)', async () => {
    const { log, db } = fakeAuditDb({ live: false });
    await assert.rejects(recordExportAudit(12345, { bytes: 1, truncated: false }, db), (e) => e.code === 'ACCOUNT_DELETED' && e.statusCode === 401);
    assert.equal(log.some((entry) => /^INSERT INTO audit_log/.test(entry.sql)), false);
    assert.equal(log.some((entry) => entry.sql === 'COMMIT'), false);
    assert.equal(log.at(-1).sql, 'ROLLBACK');
  });

  it('varsayılan exportDeps.audit bu işlevi kullanır (kilitsiz doğrudan recordAudit değil)', () => {
    assert.match(exportDeps.audit.toString(), /recordExportAudit/);
  });
});

describe('dışa aktarma: veri toplama şekli (sahte tutarlı görünüm)', () => {
  const SQLS = exportInternals.SQL;
  const startsWith = (sql, name) => norm(sql).startsWith(norm(SQLS[name]));
  let originalConnect;
  let originalQuery;
  let originalConsoleError;

  beforeEach(() => {
    resetPeopleSyncThrottle();
    // eşitleme (havuz) hatası yutulur: bağlantı kurulamıyor gibi davran
    originalConnect = pool.connect;
    originalQuery = pool.query;
    originalConsoleError = console.error;
    pool.connect = async () => {
      throw Object.assign(new Error('no pool in unit test'), { code: 'NOPOOL' });
    };
    console.error = () => {};
  });
  afterEach(() => {
    pool.connect = originalConnect;
    pool.query = originalQuery;
    console.error = originalConsoleError;
  });

  function fakeSnapshot(extra = {}) {
    const log = [];
    const rows = {
      user: [{ user_code: '12345', full_name: 'Ada Lovelace', email: 'ada@example.com', login_name: null, phone_number: '+905550000001', role: 'apartment_owner', is_active: true, email_verified: true, approval_status: 'approved', created_at: new Date('2026-01-01T00:00:00Z'), updated_at: new Date('2026-02-01T00:00:00Z') }],
      siteMemberships: [{ source: 'site_membership', site_code: '1000000001', site_name: 'Gül Sitesi', role: 'RESIDENT', is_active: true, created_at: new Date('2026-01-02T00:00:00Z'), updated_at: new Date('2026-01-02T00:00:00Z') }],
      apartmentMemberships: [{ source: 'membership', id: '5', apartment_id: '501', site_code: '1000000001', site_name: 'Gül Sitesi', block_name: 'A Blok', unit_label: 'Daire 1', role: 'APARTMENT_ADMIN', is_active: true, created_at: new Date('2026-01-02T00:00:00Z'), updated_at: new Date('2026-01-02T00:00:00Z') }],
      people: [{ id: '31', site_code: '1000000001', site_name: 'Gül Sitesi', full_name: null, phone: null, email: null, is_active: true, created_at: new Date('2026-01-03T00:00:00Z'), updated_at: new Date('2026-01-03T00:00:00Z') }],
      residencies: [{ id: '41', person_id: '31', apartment_id: '501', site_code: '1000000001', block_name: 'A Blok', unit_label: 'Daire 1', relation: 'owner', is_current: true, move_in_date: '2026-01-03', move_out_date: null, created_at: new Date('2026-01-03T00:00:00Z') }],
      vehicles: [{ id: '51', site_code: '1000000001', person_id: '31', plate_display: '34 ABC 123', plate: '34ABC123', is_active: true, created_at: new Date('2026-01-04T00:00:00Z') }],
      notificationPreferencesBase: [{ email_announcements: false, push_announcements: true, updated_at: new Date('2026-01-05T00:00:00Z') }],
      notificationPreferences: [{ email_announcements: false, email_finance_reminders: true, push_announcements: true, push_show_preview: true, push_quiet_enabled: true, push_quiet_start: 1350, push_quiet_end: 405, updated_at: new Date('2026-01-05T00:00:00Z') }],
      uploadedDocuments: [],
      financeReminders: [],
      announcements: [{ id: '61', site_code: '1000000001', site_name: 'Gül Sitesi', title: 'Su kesintisi', body: 'Yarın 10-12.', importance: 'normal', published_at: new Date('2026-01-06T00:00:00Z'), read_at: null }],
      siteApplications: [],
      guestPasses: [{ id: '71', site_code: '1000000001', door_name: 'Ana Kapı', title: 'Kargo', pass_type: 'single_use', expires_at: new Date('2026-01-07T00:00:00Z'), max_uses: 1, used_count: 0, is_active: true, created_at: new Date('2026-01-06T00:00:00Z') }],
      doorEvents: [{ id: '81', opened_at: new Date('2026-01-08T00:00:00Z'), site_code: '1000000001', door_name: 'Ana Kapı', trigger_type: 'qr', apartment_label: 'A Blok - Daire 1', user_name: 'Ada Lovelace', user_role: 'apartment_owner', ip_address: '10.0.0.1' }],
      joinRequests: [],
      doorPermissions: [],
      qrRequests: [{ id: '91', site_code: '1000000001', door_name: 'Ana Kapı', created_at: new Date('2026-01-09T00:00:00Z'), expires_at: null, revoked_at: null, request_latitude: '41.01', request_longitude: '28.97', request_accuracy: '12.5', is_mocked: false }],
      devices: [],
      ...extra,
    };
    const names = Object.keys(SQLS);
    const client = {
      query: async (text, params) => {
        const sql = norm(text);
        log.push({ sql, params: params ?? [] });
        if (/^(BEGIN|COMMIT|ROLLBACK)/.test(sql)) return ok();
        if (/^SELECT to_regclass\('public\.user_consents'\)/.test(sql)) return ok([{ t: extra.consentsTable === false ? null : 'user_consents' }]);
        // sonradan eklenen migration nesneleri (katalog bakışı; $1 yok): varsayılan hiçbiri yok -> eski şekil / boş bölümler
        if (/^SELECT \(SELECT COUNT\(\*\) FROM information_schema\.columns/.test(sql)) {
          return ok([{ has_preference_extras: false, has_documents: false, has_reminders: false, has_receipts: false, ...(extra.optional ?? {}) }]);
        }
        if (/^SELECT \* FROM user_consents WHERE user_code = \$1/.test(sql)) {
          return ok(extra.consentRows ?? [{ id: '1', user_code: 12345, document_id: 'terms', version: '2026-10-16', accepted_at: new Date('2026-01-01T00:00:00Z'), source: 'register', ip_address: '1.2.3.4' }]);
        }
        const name = names.find((candidate) => startsWith(sql, candidate));
        if (name) return ok(rows[name] ?? []);
        return ok();
      },
      release() {},
    };
    return { log, db: { connect: async () => client } };
  }

  it('sözleşmedeki üst düzey anahtarlar var; kimlikler sayıya çevrilir; kişi kaydına ilişkiler gömülür; tüm okumalar TEK salt okunur REPEATABLE READ işlemde', async () => {
    const { log, db } = fakeSnapshot();
    const { data, truncated } = await collectPersonalData(12345, { now: new Date('2026-10-16T10:00:00Z'), db });
    for (const key of ['format_version', 'generated_at', 'notice', 'user', 'memberships', 'apartment_memberships', 'people_records', 'vehicles', 'consents', 'notification_preferences', 'announcements_received', 'finance_statements', 'site_applications', 'guest_passes', 'door_events', 'excluded']) {
      assert.ok(key in data, key);
    }
    assert.equal(data.generated_at, '2026-10-16T10:00:00.000Z');
    assert.equal(data.user.user_code, 12345);
    assert.equal(data.people_records[0].id, 31);
    assert.equal(data.people_records[0].residencies.length, 1);
    assert.equal(data.people_records[0].residencies[0].apartment_id, 501);
    assert.equal('person_id' in data.people_records[0].residencies[0], false);
    assert.equal(data.apartment_memberships[0].apartment_id, 501);
    assert.equal(data.vehicles[0].person_id, 31);
    assert.equal(data.door_events[0].ip_address, '10.0.0.1', 'kendi IP adresi kendi dosyasında');
    assert.equal(data.qr_requests[0].request_latitude, 41.01);
    assert.deepEqual(data.notification_preferences.email_announcements, false);
    assert.deepEqual(data.finance_statements, []);
    assert.deepEqual(truncated, []);
    assert.equal(log[0].sql, 'BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY');
    assert.equal(log.at(-1).sql, 'COMMIT');
    assert.equal(log.filter((entry) => /^BEGIN/.test(entry.sql)).length, 1);
    assert.equal(log.some((entry) => /FOR UPDATE|FOR SHARE|^UPDATE|^INSERT|^DELETE/.test(entry.sql)), false, 'okuma kilit almaz ve yazmaz');
  });

  it('her sorgu çağıranın kodunu ($1) alır; başka kullanıcının kodu hiçbir sorguya girmez', async () => {
    const { log, db } = fakeSnapshot();
    await collectPersonalData(12345, { db });
    for (const entry of log) {
      if (/^(BEGIN|COMMIT|ROLLBACK)/.test(entry.sql)) continue;
      if (/FROM site_people sp|FROM user_consents|FROM users|FROM apartment|FROM site_|FROM guest|FROM door|FROM join|FROM qr|FROM devices|FROM notification|FROM vehicles|FROM announcement|FROM site_applications|FROM apartments|FROM ledger/.test(entry.sql)) {
        assert.equal(entry.params[0], 12345, entry.sql.slice(0, 90));
      }
    }
  });

  it('user_consents: yalnız beyaz listedeki alanlar (document_id, version, accepted_at, source); IP vb. ek sütun sızmaz; tablo yoksa boş', async () => {
    let snapshot = fakeSnapshot();
    let { data } = await collectPersonalData(12345, { db: snapshot.db });
    assert.deepEqual(Object.keys(data.consents[0]).sort(), ['accepted_at', 'document_id', 'source', 'version']);
    assert.equal(JSON.stringify(data.consents).includes('1.2.3.4'), false);

    snapshot = fakeSnapshot({ consentsTable: false });
    ({ data } = await collectPersonalData(12345, { db: snapshot.db }));
    assert.deepEqual(data.consents, []);
    assert.equal(snapshot.log.some((entry) => /FROM user_consents/.test(entry.sql)), false);
  });

  it('satır sınırı: fazladan satır gelirse bölüm kısaltılır ve truncated listesine row_limit olarak yazılır', async () => {
    const many = Array.from({ length: 5001 }, (_, i) => ({ id: String(i + 1), opened_at: new Date(), site_code: '1000000001', door_name: 'K', trigger_type: 'qr', apartment_label: null, user_name: 'Ada', user_role: null, ip_address: null }));
    const { db } = fakeSnapshot({ doorEvents: many });
    const { data, truncated } = await collectPersonalData(12345, { db });
    assert.equal(data.door_events.length, 5000);
    assert.deepEqual(truncated, [{ section: 'door_events', included: 5000, reason: 'row_limit' }]);
  });

  it('R10/bd: bildirim tercihleri TAMAMI dosyada (duyuru + aidat hatırlatma e-postası + telefon + başlık gösterme + sessiz saatler "SS:DD"); ek sütunlar yoksa eski şekil', async () => {
    let snapshot = fakeSnapshot({ optional: { has_preference_extras: true } });
    let { data } = await collectPersonalData(12345, { db: snapshot.db });
    assert.deepEqual(data.notification_preferences, {
      email_announcements: false,
      email_finance_reminders: true,
      push_announcements: true,
      push_show_preview: true,
      push_quiet: { enabled: true, start: '22:30', end: '06:45' },
      updated_at: new Date('2026-01-05T00:00:00Z'),
    });
    assert.ok(snapshot.log.some((entry) => entry.sql.startsWith('SELECT email_announcements, email_finance_reminders, push_announcements, push_show_preview')));
    snapshot = fakeSnapshot();
    ({ data } = await collectPersonalData(12345, { db: snapshot.db }));
    assert.deepEqual(Object.keys(data.notification_preferences), ['email_announcements', 'push_announcements', 'updated_at']);
    assert.equal(snapshot.log.some((entry) => entry.sql.startsWith('SELECT email_announcements, email_finance_reminders')), false, 'sütun yoksa eski sorgu');
  });

  it('R10: yüklenen belge KAYIT bilgisi, aidat hatırlatma geçmişi ve makbuz özeti dosyada; dosya içeriği / adres / ödeyen adı / hash YOK; sayılar sayıya çevrilir; tablolar yoksa bölümler boş ve sorgu çalışmaz', async () => {
    const savedHook = collectHooks.listReceipts;
    collectHooks.listReceipts = async (userCode) => ({
      items: [
        { id: 5, number: '2026-000012', kind: 'collection', status: 'valid', paid_on: '2026-09-01', issued_on: '2026-09-02', amount_minor: 150000, apartment: { id: 501, label: 'A Blok - Daire 1' }, payer_name: 'Baska Kisi' },
      ],
      next_before_id: userCode === 12345 ? 4 : null,
    });
    try {
      const snapshot = fakeSnapshot({
        optional: { has_documents: true, has_reminders: true, has_receipts: true },
        uploadedDocuments: [{ document_id: '7', version_no: 2, site_code: '1000000001', site_name: 'Gül Sitesi', category: 'regulation', file_name: 'plan.pdf', mime_type: 'application/pdf', size_bytes: '1048576', version_status: 'ready', recorded_at: new Date('2026-09-03T00:00:00Z'), completed_at: new Date('2026-09-03T00:00:05Z') }],
        financeReminders: [{ run_id: '9', site_code: '1000000001', site_name: 'Gül Sitesi', run_on: '2026-09-10', tone: 'friendly', with_amount: true, email_status: 'sent', sent_at: new Date('2026-09-10T08:00:00Z'), apartment_count: 1 }],
      });
      const { data, truncated } = await collectPersonalData(12345, { db: snapshot.db });
      assert.deepEqual(data.uploaded_documents[0], {
        document_id: 7, version_no: 2, site_code: 1000000001, site_name: 'Gül Sitesi', category: 'regulation',
        file_name: 'plan.pdf', mime_type: 'application/pdf', size_bytes: 1048576, version_status: 'ready', recorded_at: new Date('2026-09-03T00:00:00Z'), completed_at: new Date('2026-09-03T00:00:05Z'),
      });
      assert.equal('title' in data.uploaded_documents[0], false, 'belge başlığı dosyaya girmez (başkası sonradan değiştirebilir)');
      assert.equal(data.finance_reminders_received[0].run_id, 9);
      assert.equal(data.finance_reminders_received[0].email_status, 'sent');
      assert.deepEqual(data.receipts, [{ id: 5, number: '2026-000012', kind: 'collection', status: 'valid', paid_on: '2026-09-01', issued_on: '2026-09-02', amount_minor: 150000, apartment_id: 501, apartment_label: 'A Blok - Daire 1' }]);
      assert.equal(JSON.stringify(data).includes('Baska Kisi'), false, 'ödeyen adı dosyaya girmez');
      assert.deepEqual(truncated, [{ section: 'receipts', included: 1, reason: 'row_limit' }], 'makbuz sayfası doluysa kısaltma bildirilir');
      const text = serializeWithinLimit(data).text.toLowerCase();
      for (const word of ['storage_key', 'sha256', 'email_hash', 'token']) {
        assert.equal(text.includes(word), false, word);
      }
    } finally {
      collectHooks.listReceipts = savedHook;
    }
    const absent = fakeSnapshot();
    const { data } = await collectPersonalData(12345, { db: absent.db });
    assert.deepEqual([data.uploaded_documents, data.finance_reminders_received, data.receipts], [[], [], []]);
    assert.equal(absent.log.some((entry) => /FROM document_versions|FROM finance_reminder_items/.test(entry.sql)), false);
  });

  it('R10: yeni sorgular çağıranın kodunu ($1) alır ve yasak sütun seçmez (içerik / depolama anahtarı / hash / adres / not / kitle)', () => {
    for (const name of ['uploadedDocuments', 'financeReminders', 'notificationPreferences', 'notificationPreferencesBase']) {
      const sql = exportInternals.SQL[name];
      assert.ok(sql.includes('$1'), name);
      for (const pattern of [/storage_key/i, /sha256/i, /\bnote\b/i, /\bdescription\b/i, /\baudience\b/i, /target_/i, /declared_size/i, /\bi?\.?email\b/i, /email_hash/i, /\bparams\b/i, /uploaded_by,/i]) {
        assert.equal(pattern.test(sql), false, `${name}: ${pattern}`);
      }
    }
    assert.match(norm(exportInternals.SQL.uploadedDocuments), /WHERE v\.uploaded_by = \$1 ORDER BY v\.id DESC$/);
    // R16 P2-6: yalnız KULLANICININ verdiği alanlar (sürümün dosya adı / türü / boyutu / tarihi / sürüm no + kategori); başlık ve durum başkasının sonradan değiştirdiği alanlardır
    for (const pattern of [/\btitle\b/i, /document_status/i, /d\.status/i, /deleted_at/i, /deleted_by/i, /created_by/i]) {
      assert.equal(pattern.test(exportInternals.SQL.uploadedDocuments), false, String(pattern));
    }
    assert.ok(/v\.display_name AS file_name, v\.mime_type, v\.size_bytes/.test(norm(exportInternals.SQL.uploadedDocuments)));
    assert.match(norm(exportInternals.SQL.financeReminders), /INNER JOIN site_people sp ON sp\.id = i\.person_id AND sp\.user_code = \$1/);
    for (const name of ['receipts', 'finance_reminders_received', 'uploaded_documents']) {
      assert.ok(SHRINKABLE_SECTIONS.includes(name), `${name} boyut sınırında kısaltılabilir`);
    }
  });

  it('İş Takibi (042): "work_items_created" yalnız kullanıcının KENDİ talebi (başlık / açıklama / kategori / durum / tarih); tablo yoksa boş ve sorgu gitmez; bölüm kısaltılabilir; hariç tutulanlar anılır', async () => {
    const withTable = fakeSnapshot({
      optional: { has_work_items: true },
      workItems: [{ id: '8', site_code: '1000000001', site_name: 'Gül Sitesi', category: 'ariza', location_type: 'daire', title: 'Musluk', description: 'Damlıyor', status: 'islemde', created_at: new Date('2026-09-01T00:00:00Z'), updated_at: new Date('2026-09-02T00:00:00Z'), closed_at: null }],
    });
    const { data } = await collectPersonalData(12345, { db: withTable.db });
    assert.deepEqual(data.work_items_created, [{ id: 8, site_code: 1000000001, site_name: 'Gül Sitesi', category: 'ariza', location_type: 'daire', title: 'Musluk', description: 'Damlıyor', status: 'islemde', created_at: new Date('2026-09-01T00:00:00Z'), updated_at: new Date('2026-09-02T00:00:00Z'), closed_at: null }]);
    const sent = withTable.log.find((entry) => /FROM work_items w/.test(entry.sql));
    assert.equal(sent.params[0], 12345);
    const absent = fakeSnapshot();
    const empty = await collectPersonalData(12345, { db: absent.db });
    assert.deepEqual(empty.data.work_items_created, []);
    assert.equal(absent.log.some((entry) => /FROM work_items/.test(entry.sql)), false);
    assert.ok(SHRINKABLE_SECTIONS.includes('work_items_created'));
    assert.ok(EXPORT_EXCLUDED.some((line) => /^İş takibi talepleri:/.test(line) && /iç notları/.test(line)));
  });

  it('İş Takibi (P2): "work_item_comments" yalnız kullanıcının KENDİ yazdığı yorumlar (talep kimliği, zaman, metin, görünürlük); başlık / başkasının metni yok; tablo yoksa boş; kısaltılabilir; hariç tutulanlar "work_item_comments" bölümünü anar', async () => {
    const snapshot = fakeSnapshot({
      optional: { has_work_items: true },
      workItemComments: [{ id: '31', work_item_id: '8', site_code: '1000000001', created_at: new Date('2026-09-03T00:00:00Z'), body: 'Su kesildi, bakıyorum', visibility: 'public' }],
    });
    const { data } = await collectPersonalData(12345, { db: snapshot.db });
    assert.deepEqual(data.work_item_comments, [{ id: 31, work_item_id: 8, site_code: 1000000001, created_at: new Date('2026-09-03T00:00:00Z'), body: 'Su kesildi, bakıyorum', visibility: 'public' }]);
    const sent = snapshot.log.find((entry) => /FROM work_item_events e/.test(entry.sql));
    assert.equal(sent.params[0], 12345);
    assert.equal(/title|JOIN/.test(sent.sql), false);
    const absent = fakeSnapshot();
    assert.deepEqual((await collectPersonalData(12345, { db: absent.db })).data.work_item_comments, []);
    assert.equal(absent.log.some((entry) => /FROM work_item_events/.test(entry.sql)), false);
    assert.ok(SHRINKABLE_SECTIONS.includes('work_item_comments'));
    assert.ok(EXPORT_EXCLUDED.some((line) => /^İş takibi talepleri:/.test(line) && /"work_item_comments"/.test(line) && /SİZİN yazdığınız yorumlar/.test(line)));
  });

  it('İş Takibi fotoğrafları (047): "work_item_attachments_uploaded" yalnız kullanıcının KENDİ eklediği fotoğrafların kayıt bilgisi (içerik / depolama anahtarı / sha256 YOK); tablo yoksa boş ve sorgu gitmez; kısaltılabilir; hariç tutulanlar görüntünün dosyaya konmadığını söyler', async () => {
    const snapshot = fakeSnapshot({
      optional: { has_work_item_attachments: true },
      workItemAttachments: [{ id: '41', work_item_id: '8', site_code: '1000000001', file_name: 'musluk.jpg', mime_type: 'image/jpeg', size_bytes: '123456', status: 'ready', created_at: new Date('2026-09-04T00:00:00Z') }],
    });
    const { data } = await collectPersonalData(12345, { db: snapshot.db });
    assert.deepEqual(data.work_item_attachments_uploaded, [{ id: 41, work_item_id: 8, site_code: 1000000001, file_name: 'musluk.jpg', mime_type: 'image/jpeg', size_bytes: 123456, status: 'ready', created_at: new Date('2026-09-04T00:00:00Z') }]);
    const sent = snapshot.log.find((entry) => /FROM work_item_attachments a/.test(entry.sql));
    assert.equal(sent.params[0], 12345);
    assert.equal(/storage_key|sha256|JOIN/.test(sent.sql), false);
    assert.match(norm(exportInternals.SQL.workItemAttachments), /WHERE a\.uploaded_by = \$1 ORDER BY a\.id DESC$/);
    const absent = fakeSnapshot();
    assert.deepEqual((await collectPersonalData(12345, { db: absent.db })).data.work_item_attachments_uploaded, []);
    assert.equal(absent.log.some((entry) => /FROM work_item_attachments/.test(entry.sql)), false);
    assert.ok(SHRINKABLE_SECTIONS.includes('work_item_attachments_uploaded'));
    assert.ok(EXPORT_EXCLUDED.some((line) => /^İş takibi fotoğrafları:/.test(line) && /"work_item_attachments_uploaded"/.test(line) && /içeriği \(görüntü\)/.test(line)));
  });

  it('İade talepleri (088, K4): "refund_requests_made" yalnız kullanıcının KENDİ açtığı talepler (tutar kuruş sayı, durum, tarihler, kendi notu, makbuz no); ret gerekçesi / çıkış hesabı / geri alma nedeni / karar veren YOK; tablo yoksa boş ve sorgu gitmez; kısaltılabilir; hariç tutulanlar anılır', async () => {
    const snapshot = fakeSnapshot({
      optional: { has_refunds: true },
      refundRequestsMade: [
        { id: '9', site_code: '1000000001', site_name: 'Gül Sitesi', block_name: 'A Blok', unit_label: 'Daire 1', account_party: 'owner', amount_minor: '25000', status: 'approved', note: 'Fazla ödeme', requested_at: new Date('2026-10-20T08:00:00Z'), resolved_at: new Date('2026-10-21T08:00:00Z'), pay_date: '2026-10-21', receipt_number: 'IA-2026-000003' },
      ],
    });
    const { data } = await collectPersonalData(12345, { db: snapshot.db });
    assert.deepEqual(data.refund_requests_made, [
      { id: 9, site_code: 1000000001, site_name: 'Gül Sitesi', block_name: 'A Blok', unit_label: 'Daire 1', account_party: 'owner', amount_minor: 25000, status: 'approved', note: 'Fazla ödeme', requested_at: new Date('2026-10-20T08:00:00Z'), resolved_at: new Date('2026-10-21T08:00:00Z'), pay_date: '2026-10-21', receipt_number: 'IA-2026-000003' },
    ]);
    const sent = snapshot.log.find((entry) => /FROM finance_refunds r/.test(entry.sql));
    assert.equal(sent.params[0], 12345, 'çağıranın kodu');
    // yönetim kararının iç alanları ve başkasının kimliği seçilmez
    for (const pattern of [/reject_reason/i, /reversal_reason/i, /pay_account/i, /resolved_by/i, /reversed_by/i, /requested_by,/i, /receipt_snapshot/i, /receipt_code/i, /receipt_sha256/i, /decision_key/i, /idempotency_key/i, /JOIN\s+users/i]) {
      assert.equal(pattern.test(exportInternals.SQL.refundRequestsMade), false, String(pattern));
    }
    // yalnız sakinin kendi açtığı talepler; yönetici adına açılanlar girmez; en yeni önce
    assert.match(norm(exportInternals.SQL.refundRequestsMade), /WHERE r\.requested_by = \$1 AND r\.requested_by_kind = 'resident' ORDER BY r\.id DESC$/);
    const absent = fakeSnapshot();
    assert.deepEqual((await collectPersonalData(12345, { db: absent.db })).data.refund_requests_made, []);
    assert.equal(absent.log.some((entry) => /FROM finance_refunds/.test(entry.sql)), false, 'tablo yoksa sorgu gitmez');
    assert.ok(SHRINKABLE_SECTIONS.includes('refund_requests_made'));
    assert.ok(EXPORT_EXCLUDED.some((line) => /^İade talepleri:/.test(line) && /"refund_requests_made"/.test(line) && /ret gerekçesi/.test(line)));
  });

  it('kullanıcı satırı yoksa 401 ACCOUNT_DELETED ve işlem kapatılır', async () => {
    const { log, db } = fakeSnapshot({ user: [] });
    await assert.rejects(collectPersonalData(12345, { db }), (error) => error.code === 'ACCOUNT_DELETED');
    assert.equal(log.at(-1).sql, 'ROLLBACK');
  });

  it('serileştirilmiş çıktıda yasak ifade yok (parola özeti / belirteç alanı adları)', async () => {
    const { db } = fakeSnapshot();
    const { data } = await collectPersonalData(12345, { db });
    const text = serializeWithinLimit(data).text;
    for (const word of ['password_hash', 'token', 'secret', 'mqtt_password', 'local_control']) {
      assert.equal(text.toLowerCase().includes(word), false, word);
    }
  });
});
