// Firma ve Sözleşme Takibi hatırlatma işi (DB'siz): e-posta içeriği (konu, bölümler, gün ifadesi, TUTAR YOK, HTML kaçışı, başlık enjeksiyonu), zamanlayıcı
// açma / kapama (SMTP yoksa hiç başlamaz), tur akışı sahte veritabanıyla: saat kapısı, tek çalışan kilidi, talep -> gönderim -> sent_at, tamamen başarısız
// gönderimde talebin geri alınması, alıcı yoksa talep yazılmaması, alıcı başına AYRI e-posta, İLK gönderimden hemen sonra sent_at (süreç ölümü), önceki günlerin
// yarıda kalan talepleri, her yazmanın site FOR KEY SHARE ile başlayan kısa işlemde olması, tur sırasında silinen site. Gerçek PostgreSQL: qa_platform_pg.mjs "contracts".
import { describe, it, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import {
  CONTRACTS_LOCK_CLASS,
  CONTRACTS_LOCK_JOBS,
  CONTRACT_REMINDER_HOUR,
  MAX_ITEMS_PER_EMAIL,
  buildContractReminderEmail,
  contractReminderHooks,
  isContractRemindersDisabled,
  runContractReminders,
  startContractReminders,
  stopContractReminders,
} from '../src/modules/contracts_reminders.js';

const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
const original = { ...contractReminderHooks };
afterEach(async () => {
  Object.assign(contractReminderHooks, original);
  await stopContractReminders();
});

const items = [
  { kind: 'bitis', vendorName: 'Kuzey <Asansör>', title: 'Bakım & onarım', endDate: '2026-10-30', dueDate: '2026-10-30' },
  { kind: 'fesih_bildirim', vendorName: 'Mavi Havuz', title: 'Havuz bakımı', endDate: '2026-12-31', dueDate: '2026-10-20' },
  { kind: 'bitis', vendorName: 'Güvenlik A.Ş.', title: 'Güvenlik hizmeti', endDate: '2026-10-19', dueDate: '2026-10-19' },
];

describe('e-posta içeriği', () => {
  it('konu "[Site] Sözleşme hatırlatması" (satır sonu temizlenir); fesih ve bitiş bölümleri; gün ifadesi (bugün / yarın / N gün sonra); GG.AA.YYYY', () => {
    const mail = buildContractReminderEmail({ to: 'yonetici@example.com', siteName: 'Gül\r\nBcc: x@y.z Sitesi', today: '2026-10-19', items });
    assert.equal(mail.to, 'yonetici@example.com');
    assert.equal(mail.subject, '[Gül Bcc: x@y.z Sitesi] Sözleşme hatırlatması');
    assert.ok(!/[\r\n]/.test(mail.subject));
    assert.ok(mail.text.includes('Fesih bildirimi süresi dolmak üzere (otomatik yenilenen sözleşmeler):'));
    assert.ok(mail.text.includes('Bitiş tarihi yaklaşan sözleşmeler:'));
    assert.ok(mail.text.includes('- Kuzey <Asansör> - Bakım & onarım: sözleşme 30.10.2026 tarihinde sona eriyor (11 gün sonra).'));
    assert.ok(mail.text.includes('- Mavi Havuz - Havuz bakımı: fesih bildirimi için son gün 20.10.2026 (yarın); sözleşme 31.12.2026 tarihinde kendiliğinden yenilenir.'));
    assert.ok(mail.text.includes('Güvenlik hizmeti: sözleşme 19.10.2026 tarihinde sona eriyor (bugün).'));
    assert.ok(mail.text.indexOf('Fesih bildirimi süresi') < mail.text.indexOf('Bitiş tarihi yaklaşan'));
    assert.ok(mail.text.includes('yalnız site yöneticilerine'));
    assert.ok(!/AHBU/i.test(mail.text + mail.html));
  });

  it('HTML kaçışlanır (firma / başlık / site adı); tutar alanı yoktur; fazla kalem notu', () => {
    const mail = buildContractReminderEmail({ to: 'y@example.com', siteName: 'A "B" <C>', today: '2026-10-19', items: [{ ...items[0], amount: '98765.43' }], extraCount: 3 });
    assert.ok(mail.html.includes('Kuzey &lt;Asansör&gt; - Bakım &amp; onarım'));
    assert.ok(mail.html.includes('A &quot;B&quot; &lt;C&gt;'));
    assert.ok(!mail.html.includes('<Asansör>'));
    assert.ok(!mail.text.includes('98765') && !mail.html.includes('98765'));
    assert.ok(mail.text.includes('Listede gösterilmeyen 3 hatırlatma daha var'));
    assert.ok(!('headers' in mail));
  });

  it('geçersiz / çoklu alıcı INVALID_RECIPIENT', () => {
    for (const to of ['', 'yok', 'a@b.com, c@d.com', 'a@b.com\r\nBcc: c@d.com', `${'x'.repeat(250)}@a.com`]) {
      assert.throws(() => buildContractReminderEmail({ to, siteName: 'S', today: '2026-10-19', items }), { code: 'INVALID_RECIPIENT' });
    }
  });
});

describe('zamanlayıcı', () => {
  it('CONTRACT_REMINDERS_DISABLED / ANNOUNCEMENT_SCHEDULER_DISABLED ile kapalı', () => {
    assert.equal(isContractRemindersDisabled({}), false);
    assert.equal(isContractRemindersDisabled({ CONTRACT_REMINDERS_DISABLED: '1' }), true);
    assert.equal(isContractRemindersDisabled({ ANNOUNCEMENT_SCHEDULER_DISABLED: 'true' }), true);
    assert.equal(startContractReminders({ env: { CONTRACT_REMINDERS_DISABLED: 'yes' } }), null);
  });

  it('SMTP yapılandırılmamışsa hiç başlamaz (null); yapılandırılmışsa saatlik başlar, ikinci çağrı null, durdurulur', async () => {
    contractReminderHooks.smtpConfigured = () => false;
    assert.equal(startContractReminders({ env: {} }), null);
    contractReminderHooks.smtpConfigured = () => true;
    const handle = startContractReminders({ env: {}, firstDelayMs: 10 * 60 * 1000 });
    assert.ok(handle);
    assert.equal(handle.intervalMs, 60 * 60 * 1000);
    assert.equal(startContractReminders({ env: {} }), null);
    await handle.stop();
  });
});

/**
 * Sahte veritabanı: tek çalışan kilidi bağlantısı + turun sorguları. İşlem durumu izlenir: contract_reminders'a yazan HER ifade bir işlemin içinde ve o işlemin
 * İLK ifadesi `sites ... FOR KEY SHARE` olmalıdır (aksi halde test hata verir). `failOn`: bu desene uyan ifade bir kez hata verir (süreç ölümü / DB hatası benzetimi).
 */
function fakeDb({ locked = true, sites = [], due = {}, recipients = {}, claimed = null, stale = [], goneSites = [], goneAfter = {}, failOn = null } = {}) {
  const log = [];
  const state = { released: 0, destroyed: 0, inTx: false, txSite: null, siteLocks: 0 };
  const gone = new Set(goneSites.map(Number));
  const writes = /^(INSERT INTO contract_reminders|UPDATE contract_reminders|DELETE FROM contract_reminders)/;
  let fail = failOn;
  const client = {
    on() {},
    off() {},
    release(destroy) {
      if (destroy) state.destroyed += 1;
      else state.released += 1;
    },
    async query(text, params = []) {
      const sql = norm(text);
      log.push([sql, params]);
      if (fail && fail.test(sql)) {
        fail = null;
        throw Object.assign(new Error('enjekte'), { code: '57P01' });
      }
      if (sql === 'BEGIN') {
        assert.equal(state.inTx, false, 'iç içe işlem');
        state.inTx = true;
        state.txSite = null;
        return { rows: [] };
      }
      if (sql === 'COMMIT' || sql === 'ROLLBACK') {
        state.inTx = false;
        return { rows: [] };
      }
      if (/^SELECT 1 FROM sites WHERE site_code = \$1 FOR KEY SHARE$/.test(sql)) {
        assert.equal(state.inTx, true, 'site kilidi işlem içinde alınır');
        assert.equal(log[log.length - 2][0], 'BEGIN', 'site kilidi işlemin İLK ifadesi');
        state.siteLocks += 1;
        const code = Number(params[0]);
        if (goneAfter[code] !== undefined) {
          goneAfter[code] -= 1;
          if (goneAfter[code] < 0) gone.add(code);
        }
        if (gone.has(code)) return { rows: [] };
        state.txSite = code;
        return { rows: [{ '?column?': 1 }] };
      }
      if (writes.test(sql)) {
        assert.equal(state.inTx, true, `yazma işlem dışında: ${sql.slice(0, 60)}`);
        assert.ok(state.txSite !== null, 'yazmadan önce site FOR KEY SHARE alınmalı');
      }
      if (/^SELECT pg_try_advisory_lock\(\$1::int, \$2::int\) AS locked$/.test(sql)) {
        assert.deepEqual(params, [CONTRACTS_LOCK_CLASS, CONTRACTS_LOCK_JOBS.reminders]);
        return { rows: [{ locked }] };
      }
      if (/^SELECT pg_advisory_unlock/.test(sql)) return { rows: [{}] };
      if (/^SELECT DISTINCT site_code FROM contract_reminders WHERE sent_at IS NULL AND claimed_at < \$1::TIMESTAMPTZ ORDER BY site_code$/.test(sql)) {
        return { rows: stale.map((code) => ({ site_code: String(code) })) };
      }
      if (/^DELETE FROM contract_reminders WHERE site_code = \$1 AND sent_at IS NULL AND claimed_at < \$2::TIMESTAMPTZ$/.test(sql)) {
        assert.equal(Number(params[0]), state.txSite, 'eski talep silme yalnız kilitlenen sitede');
        return { rows: [], rowCount: 1 };
      }
      if (/^SELECT s\.site_code, s\.name FROM site_modules sm/.test(sql)) {
        assert.equal(params[0], 'contracts');
        assert.match(sql, /COALESCE\(r\.sent_at, r\.claimed_at\) >= \$2::TIMESTAMPTZ/, 'bugünün yarıda kalan talebi de günde tek e-posta kuralına sayılır');
        return { rows: sites };
      }
      if (/^SELECT c\.id AS contract_id, .* CROSS JOIN LATERAL/.test(sql)) return { rows: due[params[0]] ?? [] };
      if (/^SELECT DISTINCT lower\(u\.email\) AS email FROM users u/.test(sql)) {
        assert.match(sql, /u\.is_active = TRUE AND u\.deleted_at IS NULL AND u\.email_verified = TRUE/);
        assert.match(sql, /role IN \('SITE_OWNER', 'SITE_ADMIN'\) AND is_active = TRUE/);
        return { rows: (recipients[params[0]] ?? []).map((email) => ({ email })) };
      }
      if (/^INSERT INTO contract_reminders .* ON CONFLICT \(contract_id, kind, due_date\) DO NOTHING RETURNING/.test(sql)) {
        assert.equal(Number(params[0]), state.txSite);
        assert.match(sql, /claimed_at\) SELECT x\.contract_id, \$1, x\.kind, x\.due_date, \$5::TIMESTAMPTZ/);
        assert.equal(params[4], DAY.toISOString(), 'claimed_at = tur saati (DB NOW() değil)');
        const rows = params[1].map((contractId, index) => ({ id: String(900 + index), contract_id: String(contractId), kind: params[2][index], due_date: params[3][index] }));
        return { rows: claimed ? rows.filter((row) => claimed.includes(Number(row.contract_id))) : rows };
      }
      if (/^UPDATE contract_reminders SET sent_at = \$2::TIMESTAMPTZ WHERE id = ANY\(\$1::BIGINT\[\]\) AND sent_at IS NULL$/.test(sql)) {
        assert.equal(params[1], DAY.toISOString(), 'sent_at = tur saati');
        return { rows: [] };
      }
      if (/^UPDATE contract_reminders SET recipients = \$2 WHERE id = ANY\(\$1::BIGINT\[\]\)$/.test(sql)) return { rows: [] };
      if (/^DELETE FROM contract_reminders WHERE id = ANY\(\$1::BIGINT\[\]\) AND sent_at IS NULL$/.test(sql)) return { rows: [] };
      throw new Error(`BEKLENMEYEN SQL: ${sql.slice(0, 160)}`);
    },
  };
  return { db: { connect: async () => client }, log, state };
}

const DAY = new Date('2026-10-19T07:00:00Z'); // İstanbul 10:00
const dueRow = (id, kind, due, end = due) => ({ contract_id: String(id), title: `Sözleşme ${id}`, vendor_name: `Firma ${id}`, kind, due_date: due, end_date: end });
const sqlsOf = (log) => log.map(([sql]) => sql);
const one = { sites: [{ site_code: '1000000001', name: 'Gül' }], due: { 1000000001: [dueRow(11, 'bitis', '2026-10-30')] }, recipients: { 1000000001: ['a@example.com', 'b@example.com', 'c@example.com'] } };

describe('hatırlatma turu (sahte veritabanı)', () => {
  it(`saat kapısı: İstanbul ${CONTRACT_REMINDER_HOUR}:00 öncesi skipped hour (veritabanına gidilmez); SMTP yoksa skipped smtp`, async () => {
    contractReminderHooks.smtpConfigured = () => true;
    const { db, log } = fakeDb();
    const early = await runContractReminders({ now: new Date('2026-10-19T05:59:00Z'), db });
    assert.equal(early.skipped, 'hour');
    assert.equal(log.length, 0);
    contractReminderHooks.smtpConfigured = () => false;
    const noSmtp = await runContractReminders({ now: DAY, db });
    assert.equal(noSmtp.skipped, 'smtp');
    assert.equal(log.length, 0);
  });

  it('kilit başka süreçteyse skipped locked; bağlantı iade edilir', async () => {
    contractReminderHooks.smtpConfigured = () => true;
    const { db, state, log } = fakeDb({ locked: false });
    const result = await runContractReminders({ now: DAY, db });
    assert.equal(result.skipped, 'locked');
    assert.equal(state.released, 1);
    assert.equal(log.length, 1);
  });

  it('akış: önceki günlerin talepleri -> siteler -> kalemler -> alıcılar -> talep (işlem) -> e-posta -> İLK gönderimde sent_at (işlem) -> recipients (işlem); kilit açılır', async () => {
    contractReminderHooks.smtpConfigured = () => true;
    const sent = [];
    contractReminderHooks.send = async (message) => { sent.push(message); };
    const { db, log, state } = fakeDb({
      sites: [{ site_code: '1000000001', name: 'Gül Sitesi' }, { site_code: '1000000002', name: 'Alıcısız Site' }, { site_code: '1000000003', name: 'Boş Site' }],
      due: { 1000000001: [dueRow(11, 'bitis', '2026-10-30'), dueRow(12, 'fesih_bildirim', '2026-10-22', '2026-12-31')], 1000000002: [dueRow(21, 'bitis', '2026-10-25')] },
      recipients: { 1000000001: ['a@example.com', 'b@example.com'], 1000000002: [] },
    });
    const result = await runContractReminders({ now: DAY, db });
    assert.deepEqual(result, { skipped: null, sites: 1, emails: 2, failed_emails: 0, reminders: 2, errors: 0 });
    assert.deepEqual(sent.map((m) => m.to), ['a@example.com', 'b@example.com']);
    assert.ok(sent.every((m) => m.subject === '[Gül Sitesi] Sözleşme hatırlatması' && m.text.includes('Firma 11 - Sözleşme 11') && m.text.includes('Firma 12 - Sözleşme 12')));
    const sqls = sqlsOf(log);
    assert.match(sqls[1], /^SELECT DISTINCT site_code FROM contract_reminders WHERE sent_at IS NULL AND claimed_at </);
    assert.ok(!sqls.includes('DELETE FROM contract_reminders WHERE sent_at IS NULL'), 'bugünün talepleri toptan SİLİNMEZ');
    // sent_at TEK kez (ilk gönderimden sonra), recipients tur sonunda
    assert.equal(sqls.filter((sql) => sql.startsWith('UPDATE contract_reminders SET sent_at')).length, 1);
    const markAt = sqls.findIndex((sql) => sql.startsWith('UPDATE contract_reminders SET sent_at'));
    const recipientsAt = sqls.findIndex((sql) => sql.startsWith('UPDATE contract_reminders SET recipients'));
    assert.ok(markAt > 0 && recipientsAt > markAt);
    assert.deepEqual(log[recipientsAt][1], [[900, 901], 2]);
    // her yazma: BEGIN -> sites FOR KEY SHARE -> yazma -> COMMIT
    for (const at of [sqls.findIndex((sql) => sql.startsWith('INSERT INTO contract_reminders')), markAt, recipientsAt]) {
      assert.deepEqual([sqls[at - 2], sqls[at - 1].slice(0, 25), sqls[at + 1]], ['BEGIN', 'SELECT 1 FROM sites WHERE', 'COMMIT']);
    }
    assert.equal(log.filter(([sql]) => sql.startsWith('INSERT INTO contract_reminders')).length, 1, 'alıcısız sitede talep YAZILMAZ');
    assert.ok(sqls[sqls.length - 1].startsWith('SELECT pg_advisory_unlock'));
    assert.equal(state.released, 1);
    assert.equal(state.inTx, false);
  });

  it('önceki günlerden kalan gönderilmemiş talepler site başına kendi işleminde (site kilidiyle) silinir; silinmiş site atlanır', async () => {
    contractReminderHooks.smtpConfigured = () => true;
    const { db, log } = fakeDb({ stale: [1000000005, 1000000006], goneSites: [1000000006] });
    const result = await runContractReminders({ now: DAY, db });
    assert.equal(result.errors, 0);
    const deletes = log.filter(([sql]) => sql.startsWith('DELETE FROM contract_reminders WHERE site_code'));
    assert.equal(deletes.length, 1);
    assert.equal(deletes[0][1][0], 1000000005);
    assert.equal(deletes[0][1][1], '2026-10-18T21:00:00.000Z', 'eşik: bugünün İstanbul gece yarısı');
  });

  it('başka turun gönderdiği kalem (ON CONFLICT) tekrar gönderilmez; hiçbir kalem talep edilemezse e-posta yok', async () => {
    contractReminderHooks.smtpConfigured = () => true;
    const sent = [];
    contractReminderHooks.send = async (message) => { sent.push(message); };
    const { db } = fakeDb({
      sites: [{ site_code: '1000000001', name: 'Gül Sitesi' }],
      due: { 1000000001: [dueRow(11, 'bitis', '2026-10-30'), dueRow(12, 'bitis', '2026-10-31')] },
      recipients: { 1000000001: ['a@example.com'] },
      claimed: [12],
    });
    const result = await runContractReminders({ now: DAY, db });
    assert.equal(result.reminders, 1);
    assert.ok(!sent[0].text.includes('Sözleşme 11') && sent[0].text.includes('Sözleşme 12'));
    const none = fakeDb({ ...one, claimed: [] });
    const nothing = await runContractReminders({ now: DAY, db: none.db });
    assert.equal(nothing.emails, 0);
    assert.equal(sent.length, 1);
  });

  it('gönderim tamamen başarısızsa talep satırları silinir (sonraki tik yeniden dener, sent_at yazılmaz); kısmi başarıda sent_at ilk başarıdan sonra, recipients = başarılı sayı', async () => {
    contractReminderHooks.smtpConfigured = () => true;
    contractReminderHooks.send = async () => { throw new Error('SMTP'); };
    const failing = fakeDb(one);
    const result = await runContractReminders({ now: DAY, db: failing.db });
    assert.deepEqual([result.emails, result.failed_emails, result.reminders], [0, 3, 0]);
    assert.ok(failing.log.some(([sql, params]) => sql.startsWith('DELETE FROM contract_reminders WHERE id = ANY') && params[0][0] === 900));
    assert.ok(!failing.log.some(([sql]) => sql.startsWith('UPDATE contract_reminders')));
    const order = [];
    contractReminderHooks.send = async (message) => {
      order.push(`send:${message.to}`);
      if (message.to === 'a@example.com') throw new Error('SMTP');
    };
    const partial = fakeDb(one);
    const partialResult = await runContractReminders({ now: DAY, db: partial.db });
    assert.deepEqual([partialResult.emails, partialResult.failed_emails], [2, 1]);
    const sqls = sqlsOf(partial.log);
    assert.deepEqual(partial.log.find(([sql]) => sql.startsWith('UPDATE contract_reminders SET recipients'))[1], [[900], 2]);
    assert.equal(sqls.filter((sql) => sql.startsWith('UPDATE contract_reminders SET sent_at')).length, 1);
    assert.deepEqual(order, ['send:a@example.com', 'send:b@example.com', 'send:c@example.com']);
  });

  it('süreç ölümü benzetimi (gönderim ile kayıt arası): sent_at yazılamazsa kalan yöneticilere GÖNDERİLMEZ, talep SİLİNMEZ (bugün "gönderilmiş olabilir"); recipients yazılamazsa sent_at zaten yazılıdır', async () => {
    contractReminderHooks.smtpConfigured = () => true;
    const sent = [];
    contractReminderHooks.send = async (message) => { sent.push(message.to); };
    const killed = fakeDb({ ...one, failOn: /^UPDATE contract_reminders SET sent_at/ });
    const result = await runContractReminders({ now: DAY, db: killed.db });
    assert.deepEqual(sent, ['a@example.com'], 'ilk gönderimden sonra kayıt yazılamadı: tur bu sitede durur');
    assert.equal(result.errors, 1);
    assert.ok(!killed.log.some(([sql]) => sql.startsWith('DELETE FROM contract_reminders WHERE id = ANY')), 'talep silinmez: sonraki tik aynı gün yeniden GÖNDERMEZ');
    assert.equal(killed.state.inTx, false, 'hata sonrası işlem geri alındı');
    sent.length = 0;
    const lateKill = fakeDb({ ...one, failOn: /^UPDATE contract_reminders SET recipients/ });
    const late = await runContractReminders({ now: DAY, db: lateKill.db });
    assert.deepEqual(sent, ['a@example.com', 'b@example.com', 'c@example.com']);
    assert.equal(late.errors, 1);
    assert.ok(sqlsOf(lateKill.log).some((sql) => sql.startsWith('UPDATE contract_reminders SET sent_at')));
  });

  it('tur sırasında site silinirse (site FOR KEY SHARE satır döndürmez) kalan yöneticilere gönderilmez, hata sayılmaz', async () => {
    contractReminderHooks.smtpConfigured = () => true;
    const sent = [];
    contractReminderHooks.send = async (message) => { sent.push(message.to); };
    // 1. site kilidi (talep) başarılı, 2. (ilk gönderim sonrası sent_at) site silinmiş
    const { db, log } = fakeDb({ ...one, goneAfter: { 1000000001: 1 } });
    const result = await runContractReminders({ now: DAY, db });
    assert.deepEqual(sent, ['a@example.com']);
    assert.equal(result.errors, 0);
    assert.equal(result.sites, 0);
    assert.ok(!sqlsOf(log).some((sql) => /^UPDATE contract_reminders|^DELETE FROM contract_reminders WHERE id/.test(sql)));
    const goneBefore = fakeDb({ ...one, goneSites: [1000000001] });
    const before = await runContractReminders({ now: DAY, db: goneBefore.db });
    assert.deepEqual([before.emails, before.errors], [0, 0]);
    assert.ok(!sqlsOf(goneBefore.log).some((sql) => sql.startsWith('INSERT INTO contract_reminders')));
  });

  it(`bir e-postada en çok ${MAX_ITEMS_PER_EMAIL} kalem listelenir; fazlası sayıyla belirtilir, hepsi gönderilmiş sayılır`, async () => {
    contractReminderHooks.smtpConfigured = () => true;
    const sent = [];
    contractReminderHooks.send = async (message) => { sent.push(message); };
    const many = Array.from({ length: MAX_ITEMS_PER_EMAIL + 5 }, (_, i) => dueRow(100 + i, 'bitis', '2026-10-30'));
    const { db } = fakeDb({ sites: [{ site_code: '1000000001', name: 'Gül' }], due: { 1000000001: many }, recipients: { 1000000001: ['a@example.com'] } });
    const result = await runContractReminders({ now: DAY, db });
    assert.equal(result.reminders, MAX_ITEMS_PER_EMAIL + 5);
    assert.equal((sent[0].text.match(/^- /gm) ?? []).length, MAX_ITEMS_PER_EMAIL);
    assert.ok(sent[0].text.includes('Listede gösterilmeyen 5 hatırlatma daha var'));
  });
});
