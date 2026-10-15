// Duyuru kitlesi (DB'siz): günlük sınır ortam değişkeni, e-posta sayaçları, hedef SQL'i, anlık görüntü adımları ve sınırları.
// SQL'in ANLAMI (hangi kişi kitleye girer, adres seçimi, tekilleştirme) gerçek-PG betiğinde sınanır.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import {
  assertTargetBelongsToSite,
  emailCountsFromRows,
  emailDailyLimit,
  emptyEmailCounts,
  previewAudience,
  snapshotRecipients,
  targetClause,
} from '../src/modules/announcement_recipients.js';

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

describe('snapshotRecipients', () => {
  const insertRegex = /^WITH audience AS .* INSERT INTO announcement_recipients/;

  it('e-posta istenmediyse: günlük kullanım okunmaz, tekilleştirme/sınır sorguları yok, tek INSERT', async () => {
    const db = fakeDb([[insertRegex, () => ok([], 12)]]);
    const result = await snapshotRecipients(db, { announcementId: 3, siteCode: 5, target: { type: 'site', blockIds: [], apartmentIds: [] }, importance: 'normal', sendEmail: false, enforceEmailLimit: true });
    assert.equal(result.total, 12);
    assert.equal(db.log.length, 1);
    assert.deepEqual(db.log[0].params, [5, 3, false, 'normal']);
  });

  it('kitle 0: tek INSERT, e-posta adımları atlanır', async () => {
    const db = fakeDb([[/FROM announcement_recipients r INNER JOIN announcements a/, () => ok([{ used: 0 }])], [insertRegex, () => ok([], 0)]]);
    const result = await snapshotRecipients(db, { announcementId: 3, siteCode: 5, target: { type: 'site', blockIds: [], apartmentIds: [] }, importance: 'normal', sendEmail: true, enforceEmailLimit: true });
    assert.equal(result.total, 0);
    assert.equal(db.log.filter((q) => /duplicate|capped/.test(q.sql)).length, 0);
  });

  it('günlük kullanım sınırı: allowance = min(1000, günlük - kullanılan); 0\'ın altına inmez; fazlası capped', async () => {
    const run = async ({ dailyLimit, used, pending }) => {
      const db = fakeDb([
        [/FROM announcement_recipients r INNER JOIN announcements a/, () => ok([{ used }])],
        [insertRegex, () => ok([], pending)],
        [/^UPDATE announcement_recipients r SET email_status = 'duplicate'/, () => ok([], 0)],
        [/^SELECT COUNT\(\*\)::INTEGER AS n FROM announcement_recipients WHERE announcement_id = \$1 AND email_status = 'pending'$/, () => ok([{ n: pending }])],
        [/^UPDATE announcement_recipients r SET email_status = 'capped'/, () => ok([], 0)],
        [/^SELECT email_status, COUNT/, () => ok([{ email_status: 'pending', n: 1 }])],
      ]);
      await snapshotRecipients(db, { announcementId: 8, siteCode: 5, target: { type: 'site', blockIds: [], apartmentIds: [] }, importance: 'normal', sendEmail: true, enforceEmailLimit: false, dailyLimit });
      return db.log.find((q) => /SET email_status = 'capped'/.test(q.sql))?.params ?? null;
    };
    assert.deepEqual(await run({ dailyLimit: 500, used: 0, pending: 600 }), [8, 500]);
    assert.deepEqual(await run({ dailyLimit: 500, used: 450, pending: 600 }), [8, 50]);
    assert.deepEqual(await run({ dailyLimit: 500, used: 900, pending: 10 }), [8, 0], 'kota doldu -> hepsi capped');
    assert.deepEqual(await run({ dailyLimit: 5000, used: 0, pending: 1500 }), [8, 1000], 'tek yayın üst sınırı 1000');
    assert.equal(await run({ dailyLimit: 500, used: 0, pending: 40 }), null, 'sınır altında kırpma yok');
  });

  it('yönetici yayınında (enforceEmailLimit) 1000\'den fazla teslim edilecek adres 400 ANNOUNCEMENT_EMAIL_LIMIT; zamanlayıcıda hata yok', async () => {
    const responders = (pending) => [
      [/FROM announcement_recipients r INNER JOIN announcements a/, () => ok([{ used: 0 }])],
      [insertRegex, () => ok([], pending)],
      [/^UPDATE announcement_recipients r SET email_status = 'duplicate'/, () => ok([], 0)],
      [/^SELECT COUNT\(\*\)::INTEGER AS n FROM announcement_recipients WHERE announcement_id = \$1 AND email_status = 'pending'$/, () => ok([{ n: pending }])],
      [/^UPDATE announcement_recipients r SET email_status = 'capped'/, () => ok([], 0)],
      [/^SELECT email_status, COUNT/, () => ok([])],
    ];
    const args = { announcementId: 1, siteCode: 5, target: { type: 'site', blockIds: [], apartmentIds: [] }, importance: 'normal', sendEmail: true };
    await assert.rejects(() => snapshotRecipients(fakeDb(responders(1001)), { ...args, enforceEmailLimit: true }), (e) => e.code === 'ANNOUNCEMENT_EMAIL_LIMIT' && e.statusCode === 400);
    await snapshotRecipients(fakeDb(responders(1000)), { ...args, enforceEmailLimit: true });
    await snapshotRecipients(fakeDb(responders(5000)), { ...args, enforceEmailLimit: false });
  });
});
