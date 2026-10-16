// Duyuru kitlesi (DB'siz): günlük sınır ortam değişkeni, e-posta sayaçları, hedef SQL'i, anlık görüntü (TEK INSERT ... SELECT) ve sınırları.
// SQL'in ANLAMI (hangi kişi kitleye girer, adres seçimi, tekilleştirme, adres başına sınır) gerçek-PG betiğinde sınanır.
import { describe, it, mock } from 'node:test';
import assert from 'node:assert/strict';
import {
  assertDeliverableAddressLimit,
  assertTargetBelongsToSite,
  asciiLowerSql,
  canonicalEmailSql,
  deliverableEmailSql,
  emailCountsFromRows,
  emailDailyLimit,
  emailHashSql,
  emailUsageToday,
  emptyEmailCounts,
  previewAudience,
  snapshotRecipients,
  suppressedSql,
  targetClause,
} from '../src/modules/announcement_recipients.js';
import { hashEmail, emailHashSalt, emailHashSalts } from '../src/modules/announcement_email_security.js';
import { ANNOUNCEMENT_LOCK_CLASS, ANNOUNCEMENT_LOCK_JOBS } from '../src/modules/announcement_lock.js';
import { istanbulDayRange } from '../src/modules/announcement_common.js';

process.env.JWT_SECRET ||= 'unit-test-secret-0123456789abcdef';

const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
const ok = (rows = [], rowCount = rows.length) => ({ rows, rowCount });

function fakeDb(responders) {
  const log = [];
  return {
    log,
    async query(text, params) {
      const sql = norm(text);
      log.push({ sql, params: params ?? [] });
      for (const [pattern, handler] of responders) {
        if (pattern.test(sql)) return handler(sql, params ?? []);
      }
      throw new Error(`BEKLENMEYEN SQL: ${sql.slice(0, 160)}`);
    },
  };
}

describe('emailDailyLimit (ANNOUNCEMENT_EMAIL_MAX_PER_DAY_PER_SITE)', () => {
  it('varsayılan 500; geçerli tamsayı >= 0 kabul; geçersiz değer varsayılana döner', () => {
    assert.equal(emailDailyLimit({}), 500);
    assert.equal(emailDailyLimit({ ANNOUNCEMENT_EMAIL_MAX_PER_DAY_PER_SITE: '' }), 500);
    assert.equal(emailDailyLimit({ ANNOUNCEMENT_EMAIL_MAX_PER_DAY_PER_SITE: '120' }), 120);
    assert.equal(emailDailyLimit({ ANNOUNCEMENT_EMAIL_MAX_PER_DAY_PER_SITE: '0' }), 0);
    for (const bad of ['abc', '-5', '1.5', 'NaN']) {
      assert.equal(emailDailyLimit({ ANNOUNCEMENT_EMAIL_MAX_PER_DAY_PER_SITE: bad }), 500, bad);
    }
  });
});

describe('emailCountsFromRows', () => {
  it('durum sayıları toplanır; requested = e-posta istenen alıcılar (none hariç); bilinmeyen durum yok sayılır', () => {
    assert.deepEqual(emailCountsFromRows([]), emptyEmailCounts());
    assert.deepEqual(
      emailCountsFromRows([
        { email_status: 'none', n: 3 },
        { email_status: 'pending', n: 2 },
        { email_status: 'sent', n: '4' },
        { email_status: 'duplicate', n: 1 },
        { email_status: 'bilinmeyen', n: 9 },
      ]),
      { requested: 7, sent: 4, failed: 0, no_address: 0, skipped_pref: 0, capped: 0, duplicate: 1, pending: 2 },
    );
  });
});

describe('targetClause', () => {
  it('site: koşul yok; blocks / apartments: dizi parametresi verilen sıradan başlar', () => {
    assert.deepEqual(targetClause({ type: 'site', blockIds: [], apartmentIds: [] }, 2), { sql: 'TRUE', params: [] });
    assert.deepEqual(targetClause({ type: 'blocks', blockIds: [4, 5], apartmentIds: [] }, 2), { sql: 'a.block_id = ANY($2::BIGINT[])', params: [[4, 5]] });
    assert.deepEqual(targetClause({ type: 'apartments', blockIds: [], apartmentIds: [9] }, 3), { sql: 'a.id = ANY($3::BIGINT[])', params: [[9]] });
  });
});

describe('assertTargetBelongsToSite', () => {
  it('site hedefinde sorgu yok; blok / daire sayısı eşleşmezse 400 INVALID_TARGET (site kapsamlı sorgu)', async () => {
    const db = fakeDb([[/FROM site_blocks/, () => ok([{ n: 1 }])], [/FROM apartments/, () => ok([{ n: 2 }])]]);
    await assertTargetBelongsToSite(db, 1, { type: 'site', blockIds: [], apartmentIds: [] });
    assert.equal(db.log.length, 0);
    await assert.rejects(() => assertTargetBelongsToSite(db, 7, { type: 'blocks', blockIds: [1, 2], apartmentIds: [] }), (e) => e.code === 'INVALID_TARGET' && e.statusCode === 400);
    assert.deepEqual(db.log[0].params, [7, [1, 2]]);
    await assertTargetBelongsToSite(db, 7, { type: 'apartments', blockIds: [], apartmentIds: [3, 4] });
  });
});

describe('previewAudience', () => {
  it('hiçbir şey yazmaz; without_email = people - with_email; alan adları sözleşmeyle aynı', async () => {
    const db = fakeDb([
      [/^WITH audience AS .* SELECT COUNT\(\*\)::INTEGER AS people/, () => ok([{ people: 10, with_account: 4, with_email: 6 }])],
      [/^SELECT COUNT\(DISTINCT r\.apartment_id\)::INTEGER AS apartments/, () => ok([{ apartments: 7 }])],
    ]);
    const result = await previewAudience(db, 5, { type: 'blocks', blockIds: [2], apartmentIds: [] });
    assert.deepEqual(result, { people: 10, apartments: 7, with_account: 4, with_email: 6, without_email: 4 });
    assert.equal(db.log.length, 2);
    assert.deepEqual(db.log[0].params, [5, [2]]);
    assert.deepEqual(db.log[1].params, [5, [2]]);
    assert.equal(db.log.every((q) => !/^(INSERT|UPDATE|DELETE)/.test(q.sql)), true);
  });
});

describe('emailHashSql / adres özeti', () => {
  it('SQL özeti JS özetiyle AYNI tanımdır: sha256(tuz || ":" || küçük harfli adres) -> hex; tuz parametredir', () => {
    assert.equal(emailHashSql('$4', 'b.email'), "encode(sha256(convert_to($4::TEXT || ':' || b.email, 'UTF8')), 'hex')");
    assert.match(hashEmail('Sakin@Example.com'), /^[0-9a-f]{64}$/);
    assert.equal(hashEmail('Sakin@Example.com'), hashEmail('  sakin@example.COM '));
    assert.notEqual(hashEmail('a@example.com'), hashEmail('b@example.com'));
    assert.doesNotMatch(hashEmail('sakin@example.com'), /sakin/);
  });
});

describe('E3 canonicalEmailSql / E2 suppressedSql', () => {
  it('canonicalEmailSql: +etiket atılır, gmail / googlemail noktaları silinir ve alan adı gmail.com olur; boş kalacak yerel kısma dokunulmaz (JS canonicalAddress ile aynı kural; PG\'de değer eşliği sınanır)', () => {
    const sql = canonicalEmailSql('b.email');
    assert.match(sql, /position\('\+' IN split_part\(b\.email, '@', 1\)\) > 1 THEN left\(split_part\(b\.email, '@', 1\), position\('\+' IN split_part\(b\.email, '@', 1\)\) - 1\)/);
    assert.match(sql, /split_part\(b\.email, '@', 2\) IN \('gmail\.com', 'googlemail\.com'\)/);
    assert.match(sql, /COALESCE\(NULLIF\(replace\(.*, '\.', ''\), ''\), .*\) \|\| '@gmail\.com'/);
    assert.match(sql, /\|\| '@' \|\| split_part\(b\.email, '@', 2\) END\)$/);
  });

  it('suppressedSql: güncel + eski tuzların (dizi parametresi) HEPSİYLE kanonik özet hesaplanıp bastırma listesinde aranır', () => {
    const sql = suppressedSql('r.email', '$6');
    assert.match(sql, /^EXISTS \(SELECT 1 FROM unnest\(\$6::TEXT\[\]\) AS salts\(salt\) INNER JOIN announcement_email_suppressions sup ON sup\.email_hash = encode\(sha256\(convert_to\(salts\.salt::TEXT \|\| ':' \|\| /);
    assert.ok(sql.includes(canonicalEmailSql('r.email')));
    assert.match(sql, /'UTF8'\)\), 'hex'\)\)$/);
  });
});

describe('F6b ASCII küçük harf (JS ile aynı) / deliverableEmailSql', () => {
  it('asciiLowerSql yalnız A-Z\'yi küçültür (translate); lower() KULLANILMAZ - Türkçe İ / ı veritabanı yerel ayarına göre ayrışmaz', () => {
    assert.equal(asciiLowerSql('x'), "translate(x, 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'abcdefghijklmnopqrstuvwxyz')");
    const sql = deliverableEmailSql('raw_email');
    assert.doesNotMatch(sql, /\blower\(/);
    assert.match(sql, /translate\(btrim\(raw_email\), 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'abcdefghijklmnopqrstuvwxyz'\) LIKE '%@ahbu\.local' THEN NULL/);
    assert.match(sql, /ELSE translate\(btrim\(raw_email\), 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'abcdefghijklmnopqrstuvwxyz'\)\s+END/);
    assert.match(sql, /char_length\(btrim\(raw_email\)\) > 254 THEN NULL/);
  });
});

describe('F3 sessiz tuz geçişi (snapshotRecipients)', () => {
  const insertRegex = /^WITH audience AS .* INSERT INTO announcement_recipients/;
  const lockRegex = /^SELECT pg_advisory_xact_lock\(\$1::int, \$2::int\)$/;
  const usageRegex = /^SELECT COUNT\(\*\)::INTEGER AS used FROM announcement_recipients r/;
  const countsRegex = /^SELECT email_status, COUNT\(\*\)::INTEGER AS n FROM announcement_recipients WHERE announcement_id = \$1 GROUP BY email_status$/;
  const siteTarget = { type: 'site', blockIds: [], apartmentIds: [] };
  const run = async (sendEmail) => {
    const db = fakeDb([[lockRegex, () => ok()], [usageRegex, () => ok([{ used: 0 }])], [insertRegex, () => ok([], 1)], [countsRegex, () => ok([{ email_status: 'pending', n: 1 }])]]);
    await snapshotRecipients(db, { announcementId: 3, siteCode: 5, target: siteTarget, importance: 'normal', sendEmail, enforceEmailLimit: false, now: new Date('2026-10-16T10:00:00.000Z') });
    return db.log.find((q) => insertRegex.test(q.sql));
  };

  it('PREVIOUS tanımlıyken e-postalı yayın: veri değiştiren CTE eski tuzla eşleşen bastırmayı GÜNCEL tuzla da ekler (ON CONFLICT DO NOTHING); yalnız güncel tuzda zaten olmayanlar', async () => {
    const saved = process.env.ANNOUNCEMENT_EMAIL_SECRET_PREVIOUS;
    process.env.ANNOUNCEMENT_EMAIL_SECRET_PREVIOUS = 'eski-duyuru-sirri-0123456789';
    try {
      const insert = await run(true);
      assert.match(insert.sql, /, migrated AS \( INSERT INTO announcement_email_suppressions \(email_hash\) SELECT DISTINCT h\.email_hash FROM hashed h WHERE \$\d+::BOOLEAN AND h\.email IS NOT NULL AND NOT EXISTS \(SELECT 1 FROM announcement_email_suppressions cur WHERE cur\.email_hash = h\.email_hash\) AND EXISTS \(SELECT 1 FROM unnest\(\$\d+::TEXT\[\]\) AS salts\(salt\)/);
      assert.match(insert.sql, /ON CONFLICT \(email_hash\) DO NOTHING RETURNING 1 \), classified AS/);
      assert.equal(insert.params.at(-1).length, 2, 'güncel + 1 eski tuz');
      assert.deepEqual(insert.params.at(-1), emailHashSalts());
    } finally {
      if (saved === undefined) delete process.env.ANNOUNCEMENT_EMAIL_SECRET_PREVIOUS;
      else process.env.ANNOUNCEMENT_EMAIL_SECRET_PREVIOUS = saved;
    }
  });

  it('eski sır yokken (olağan durum) ve e-postasız yayında geçiş CTE\'si EKLENMEZ (ek maliyet yok)', async () => {
    const saved = process.env.ANNOUNCEMENT_EMAIL_SECRET_PREVIOUS;
    delete process.env.ANNOUNCEMENT_EMAIL_SECRET_PREVIOUS;
    try {
      assert.doesNotMatch((await run(true)).sql, /migrated AS|INSERT INTO announcement_email_suppressions/);
      process.env.ANNOUNCEMENT_EMAIL_SECRET_PREVIOUS = 'eski-duyuru-sirri-0123456789';
      assert.doesNotMatch((await run(false)).sql, /migrated AS|INSERT INTO announcement_email_suppressions/);
    } finally {
      if (saved === undefined) delete process.env.ANNOUNCEMENT_EMAIL_SECRET_PREVIOUS;
      else process.env.ANNOUNCEMENT_EMAIL_SECRET_PREVIOUS = saved;
    }
  });
});

describe('emailUsageToday', () => {
  it('pending + sent sayılır, failed ve none SAYILMAZ; site kapsamlı; gün başlangıcı İstanbul takvim günüdür', async () => {
    const db = fakeDb([[/^SELECT COUNT\(\*\)::INTEGER AS used FROM announcement_recipients r/, () => ok([{ used: 7 }])]]);
    const now = new Date('2026-10-16T21:30:00.000Z'); // İstanbul 17 Ekim 00:30
    assert.equal(await emailUsageToday(db, 5, now), 7);
    assert.match(db.log[0].sql, /WHERE a\.site_code = \$1 AND a\.published_at >= \$2::TIMESTAMPTZ AND r\.email_status IN \('pending', 'sent'\)$/);
    assert.doesNotMatch(db.log[0].sql, /failed|'none'/);
    assert.deepEqual(db.log[0].params, [5, istanbulDayRange(now).start.toISOString()]);
    assert.equal(db.log[0].params[1], '2026-10-16T21:00:00.000Z');
  });
});

describe('assertDeliverableAddressLimit (kilitsiz erken kapı)', () => {
  const target = { type: 'site', blockIds: [], apartmentIds: [] };

  it('teslim edilecek TEKİL adres > 1000 ise 400 ANNOUNCEMENT_EMAIL_LIMIT; <= 1000 ise sayıyı döner; yalnız SELECT (kilit ve yazma yok)', async () => {
    const make = (n) => fakeDb([[/^WITH audience AS .* SELECT COUNT\(DISTINCT h\.email_hash\)::INTEGER AS n FROM hashed h/, () => ok([{ n }])]]);
    const db = make(1000);
    assert.equal(await assertDeliverableAddressLimit(db, 5, target, 'normal'), 1000);
    assert.equal(db.log.length, 1);
    assert.doesNotMatch(db.log[0].sql, /pg_advisory|INSERT|UPDATE|FOR (SHARE|UPDATE)/);
    await assert.rejects(() => assertDeliverableAddressLimit(make(1001), 5, target, 'normal'), (e) => e.code === 'ANNOUNCEMENT_EMAIL_LIMIT' && e.statusCode === 400);
  });

  it('bastırılmış adresler ve (normal duyuruda) tercihi kapalı hesaplılar sayılmaz; parametreler: site, tuz, önem', async () => {
    const db = fakeDb([[/^WITH audience AS/, () => ok([{ n: 3 }])]]);
    await assertDeliverableAddressLimit(db, 5, { type: 'blocks', blockIds: [2], apartmentIds: [] }, 'urgent');
    // E2/E3: bastırma KANONİK adresin özetiyle, güncel + eski tuzlarla ($5) aranır; özet de kanonik adresten hesaplanır
    assert.match(db.log[0].sql, /AND NOT EXISTS \(SELECT 1 FROM unnest\(\$5::TEXT\[\]\) AS salts\(salt\) INNER JOIN announcement_email_suppressions sup ON sup\.email_hash = encode\(sha256\(convert_to\(salts\.salt::TEXT \|\| ':' \|\|/);
    assert.doesNotMatch(db.log[0].sql, /LEFT JOIN announcement_email_suppressions/);
    assert.match(db.log[0].sql, /NOT \(h\.has_account AND h\.email_pref = FALSE AND \$4::TEXT = 'normal'\)/);
    assert.match(db.log[0].sql, /encode\(sha256\(convert_to\(\$3::TEXT \|\| ':' \|\| \(CASE WHEN split_part\(b\.email, '@', 2\) IN \('gmail\.com', 'googlemail\.com'\)/);
    assert.deepEqual(db.log[0].params, [5, [2], emailHashSalt(), 'urgent', emailHashSalts()]);
  });
});

describe('snapshotRecipients', () => {
  const insertRegex = /^WITH audience AS .* INSERT INTO announcement_recipients/;
  const lockRegex = /^SELECT pg_advisory_xact_lock\(\$1::int, \$2::int\)$/;
  const usageRegex = /^SELECT COUNT\(\*\)::INTEGER AS used FROM announcement_recipients r/;
  const countsRegex = /^SELECT email_status, COUNT\(\*\)::INTEGER AS n FROM announcement_recipients WHERE announcement_id = \$1 GROUP BY email_status$/;
  const siteTarget = { type: 'site', blockIds: [], apartmentIds: [] };
  const NOW = new Date('2026-10-16T10:00:00.000Z');
  const DAY_START = '2026-10-15T21:00:00.000Z';

  it('e-posta istenmediyse: kilit YOK, günlük kullanım okunmaz, tek INSERT (TEK ifade; tüm durumlar none); özet sorgusu yok', async () => {
    const db = fakeDb([[insertRegex, () => ok([], 12)]]);
    const result = await snapshotRecipients(db, { announcementId: 3, siteCode: 5, target: siteTarget, importance: 'normal', sendEmail: false, enforceEmailLimit: true, now: NOW });
    assert.equal(result.total, 12);
    assert.deepEqual(result.email, emptyEmailCounts());
    assert.equal(db.log.length, 1);
    assert.deepEqual(db.log[0].params, [5, 3, false, 'normal', '', DAY_START, 3, 0, []]);
  });

  it('E2 tuz YALNIZ e-posta gerektiğinde hesaplanır: sır eksik / kısa olsa bile e-postasız yayın bozulmaz (500 yok); e-postalı yayın net hata verir', async () => {
    const savedJwt = process.env.JWT_SECRET;
    const savedOwn = process.env.ANNOUNCEMENT_EMAIL_SECRET;
    delete process.env.JWT_SECRET;
    process.env.ANNOUNCEMENT_EMAIL_SECRET = 'kisa';
    const warn = mock.method(console, 'warn', () => {});
    try {
      const db = fakeDb([[insertRegex, () => ok([], 4)]]);
      const result = await snapshotRecipients(db, { announcementId: 3, siteCode: 5, target: siteTarget, importance: 'normal', sendEmail: false, enforceEmailLimit: true, now: NOW });
      assert.equal(result.total, 4);
      assert.deepEqual(db.log[0].params.slice(-5, -4), [''], 'tuz parametresi boş (hiç türetilmedi)');
      assert.deepEqual(db.log[0].params.at(-1), []);
      assert.equal(warn.mock.calls.length, 0, 'e-postasız yayında sır hiç okunmadı');
      await assert.rejects(
        () => snapshotRecipients(fakeDb([[lockRegex, () => ok()], [usageRegex, () => ok([{ used: 0 }])]]), { announcementId: 3, siteCode: 5, target: siteTarget, importance: 'normal', sendEmail: true, enforceEmailLimit: true, now: NOW }),
        /tanimli degil/,
      );
    } finally {
      process.env.JWT_SECRET = savedJwt;
      if (savedOwn === undefined) delete process.env.ANNOUNCEMENT_EMAIL_SECRET;
      else process.env.ANNOUNCEMENT_EMAIL_SECRET = savedOwn;
    }
  });

  it('hedef parametreleri site kodundan hemen sonra gelir (blocks: $2); duyuru kimliği ve diğer parametreler onları izler', async () => {
    const db = fakeDb([[insertRegex, () => ok([], 2)]]);
    await snapshotRecipients(db, { announcementId: 3, siteCode: 5, target: { type: 'blocks', blockIds: [7, 9], apartmentIds: [] }, importance: 'urgent', sendEmail: false, enforceEmailLimit: false, now: NOW });
    assert.deepEqual(db.log[0].params, [5, [7, 9], 3, false, 'urgent', '', DAY_START, 3, 0, []]);
    assert.match(db.log[0].sql, /a\.block_id = ANY\(\$2::BIGINT\[\]\)/);
    assert.match(db.log[0].sql, /\$3::BIGINT, f\.person_id/);
  });

  it('e-postalı yayın: ÖNCE küresel iki-int işlem kilidi, SONRA günlük kullanım, SONRA tek INSERT, en sonda durum özeti', async () => {
    const db = fakeDb([[lockRegex, () => ok()], [usageRegex, () => ok([{ used: 120 }])], [insertRegex, () => ok([], 4)], [countsRegex, () => ok([{ email_status: 'pending', n: 3 }, { email_status: 'no_address', n: 1 }])]]);
    const result = await snapshotRecipients(db, { announcementId: 8, siteCode: 5, target: siteTarget, importance: 'normal', sendEmail: true, enforceEmailLimit: true, dailyLimit: 500, now: NOW });
    const kind = (sql) => [['lock', lockRegex], ['usage', usageRegex], ['insert', insertRegex], ['counts', countsRegex]].find(([, pattern]) => pattern.test(sql))?.[0] ?? '?';
    assert.deepEqual(db.log.map((q) => kind(q.sql)), ['lock', 'usage', 'insert', 'counts']);
    assert.deepEqual(db.log[0].params, [ANNOUNCEMENT_LOCK_CLASS, ANNOUNCEMENT_LOCK_JOBS.emailGlobal]);
    assert.deepEqual(db.log[1].params, [5, DAY_START]);
    assert.deepEqual(db.log[2].params, [5, 8, true, 'normal', emailHashSalt(), DAY_START, 3, 380, emailHashSalts()]);
    assert.equal(result.total, 4);
    assert.equal(result.email.pending, 3);
    assert.equal(result.email.no_address, 1);
    assert.equal(result.email.requested, 4);
  });

  it('INSERT tek ifadedir: UPDATE yok; pencere fonksiyonlarıyla tekilleştirme + adres başına sınır + site kotası; failed sayıma girmez; bastırma listesi; acil yalnız KİŞİ tercihini atlar', async () => {
    const db = fakeDb([[lockRegex, () => ok()], [usageRegex, () => ok([{ used: 0 }])], [insertRegex, () => ok([], 1)], [countsRegex, () => ok([{ email_status: 'pending', n: 1 }])]]);
    await snapshotRecipients(db, { announcementId: 8, siteCode: 5, target: siteTarget, importance: 'normal', sendEmail: true, enforceEmailLimit: false, now: NOW });
    const insert = db.log.find((q) => insertRegex.test(q.sql)).sql;
    assert.equal(db.log.filter((q) => /^UPDATE/.test(q.sql)).length, 0, 'karesel UPDATE ... FROM (ROW_NUMBER) kalıbı yok');
    assert.match(insert, /ROW_NUMBER\(\) OVER \(PARTITION BY CASE WHEN c\.st = 'eligible' THEN c\.email_hash END ORDER BY c\.person_id\) AS addr_rn/);
    assert.match(insert, /ROW_NUMBER\(\) OVER \(PARTITION BY f\.in_quota ORDER BY f\.person_id\) AS cap_rn/);
    // bastırma: KANONİK adres özeti, güncel + eski tuzlar ($n TEXT[]); acil dahil skipped_pref
    assert.doesNotMatch(insert, /LEFT JOIN announcement_email_suppressions/);
    assert.match(insert, /WHEN EXISTS \(SELECT 1 FROM unnest\(\$\d+::TEXT\[\]\) AS salts\(salt\) INNER JOIN announcement_email_suppressions sup ON sup\.email_hash = encode\(sha256\(convert_to\(salts\.salt::TEXT \|\| ':' \|\| \(CASE WHEN split_part\(h\.email, '@', 2\)[^]*?\)\) THEN 'skipped_pref'/);
    // özet kanonik adresten (+etiket atılır, gmail noktaları silinir); düz adres saklanmaz
    assert.match(insert, /ELSE encode\(sha256\(convert_to\(\$\d+::TEXT \|\| ':' \|\| \(CASE WHEN split_part\(b\.email, '@', 2\) IN \('gmail\.com', 'googlemail\.com'\) THEN COALESCE\(NULLIF\(replace\(/);
    assert.match(insert, /WHEN h\.has_account AND h\.email_pref = FALSE AND \$\d+::TEXT = 'normal' THEN 'skipped_pref'/);
    // adres başına günlük sayım: indeks yoklayan ilişkili alt sorgu (karesel plan riski yok); yalnız pending + sent; İstanbul günü
    assert.match(insert, /SELECT COUNT\(\*\) FROM announcement_recipients r WHERE r\.email_hash = k\.email_hash AND r\.email_status IN \('pending', 'sent'\) AND \(SELECT an\.published_at FROM announcements an WHERE an\.id = r\.announcement_id\) >= \$\d+::TIMESTAMPTZ/);
    assert.doesNotMatch(insert, /'failed'/);
    // yalnız pending satırlara adres + özet yazılır; kalanlarda NULL
    assert.match(insert, /CASE WHEN f\.final_status = 'pending' THEN f\.email END, CASE WHEN f\.final_status = 'pending' THEN f\.email_hash END, f\.final_status/);
    assert.match(insert, /WHEN n\.addr_rn > 1 THEN 'duplicate' WHEN NOT n\.in_quota THEN 'capped' WHEN n\.cap_rn <= \$\d+::INTEGER THEN 'pending' ELSE 'capped'/);
  });

  it('kitle 0: INSERT 0 satır -> özet sorgusu atlanır', async () => {
    const db = fakeDb([[lockRegex, () => ok()], [usageRegex, () => ok([{ used: 0 }])], [insertRegex, () => ok([], 0)]]);
    const result = await snapshotRecipients(db, { announcementId: 3, siteCode: 5, target: siteTarget, importance: 'normal', sendEmail: true, enforceEmailLimit: true, now: NOW });
    assert.equal(result.total, 0);
    assert.deepEqual(result.email, emptyEmailCounts());
    assert.equal(db.log.filter((q) => countsRegex.test(q.sql)).length, 0);
  });

  it('günlük kullanım sınırı: allowance = min(1000, günlük - kullanılan); 0\'ın altına inmez; parametre olarak INSERT\'e verilir', async () => {
    const run = async ({ dailyLimit, used }) => {
      const db = fakeDb([[lockRegex, () => ok()], [usageRegex, () => ok([{ used }])], [insertRegex, () => ok([], 1)], [countsRegex, () => ok([{ email_status: 'pending', n: 1 }])]]);
      await snapshotRecipients(db, { announcementId: 8, siteCode: 5, target: siteTarget, importance: 'normal', sendEmail: true, enforceEmailLimit: false, dailyLimit, now: NOW });
      return db.log.find((q) => insertRegex.test(q.sql)).params.at(-2);
    };
    assert.equal(await run({ dailyLimit: 500, used: 0 }), 500);
    assert.equal(await run({ dailyLimit: 500, used: 450 }), 50);
    assert.equal(await run({ dailyLimit: 500, used: 900 }), 0, 'kota doldu -> hepsi capped');
    assert.equal(await run({ dailyLimit: 5000, used: 0 }), 1000, 'tek yayın üst sınırı 1000');
    assert.equal(await run({ dailyLimit: 0, used: 0 }), 0);
  });

  it('adres başına sınır parametresi verilir (varsayılan ortamdan 3; açıkça verilirse o)', async () => {
    const run = async (perAddressLimit) => {
      const db = fakeDb([[lockRegex, () => ok()], [usageRegex, () => ok([{ used: 0 }])], [insertRegex, () => ok([], 1)], [countsRegex, () => ok([{ email_status: 'pending', n: 1 }])]]);
      await snapshotRecipients(db, { announcementId: 8, siteCode: 5, target: siteTarget, importance: 'normal', sendEmail: true, enforceEmailLimit: false, now: NOW, ...(perAddressLimit === undefined ? {} : { perAddressLimit }) });
      return db.log.find((q) => insertRegex.test(q.sql)).params.at(-3);
    };
    assert.equal(await run(undefined), 3);
    assert.equal(await run(1), 1);
  });

  it('yönetici yayınında (enforceEmailLimit) pending + capped > 1000 ise 400 ANNOUNCEMENT_EMAIL_LIMIT; 1000 geçer; zamanlayıcıda hata yok', async () => {
    const responders = (pending, capped = 0) => [
      [lockRegex, () => ok()],
      [usageRegex, () => ok([{ used: 0 }])],
      [insertRegex, () => ok([], pending + capped)],
      [countsRegex, () => ok([{ email_status: 'pending', n: pending }, { email_status: 'capped', n: capped }])],
    ];
    const args = { announcementId: 1, siteCode: 5, target: siteTarget, importance: 'normal', sendEmail: true, now: NOW };
    await assert.rejects(() => snapshotRecipients(fakeDb(responders(1001)), { ...args, enforceEmailLimit: true }), (e) => e.code === 'ANNOUNCEMENT_EMAIL_LIMIT' && e.statusCode === 400);
    await assert.rejects(() => snapshotRecipients(fakeDb(responders(900, 101)), { ...args, enforceEmailLimit: true }), (e) => e.code === 'ANNOUNCEMENT_EMAIL_LIMIT');
    await snapshotRecipients(fakeDb(responders(1000)), { ...args, enforceEmailLimit: true });
    await snapshotRecipients(fakeDb(responders(5000)), { ...args, enforceEmailLimit: false });
  });
});
