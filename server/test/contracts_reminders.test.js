// Firma ve Sözleşme Takibi hatırlatma işi (DB'siz): e-posta içeriği (konu, bölümler, gün ifadesi, TUTAR YOK, HTML kaçışı, başlık enjeksiyonu), zamanlayıcı
// açma / kapama (SMTP yoksa hiç başlamaz), tur akışı sahte veritabanıyla: saat kapısı, tek çalışan kilidi, talep -> gönderim -> sent_at, tamamen başarısız
// gönderimde talebin geri alınması, alıcı yoksa talep yazılmaması, alıcı başına AYRI e-posta. Gerçek PostgreSQL: scripts/qa_platform_pg.mjs "contracts" (R0-R10).
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

/** Sahte veritabanı: tek çalışan kilidi bağlantısı + turun sorguları. */
function fakeDb({ locked = true, sites = [], due = {}, recipients = {}, claimed = null } = {}) {
  const log = [];
  const state = { released: 0, destroyed: 0 };
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
      if (/^SELECT pg_try_advisory_lock\(\$1::int, \$2::int\) AS locked$/.test(sql)) {
        assert.deepEqual(params, [CONTRACTS_LOCK_CLASS, CONTRACTS_LOCK_JOBS.reminders]);
        return { rows: [{ locked }] };
      }
      if (/^SELECT pg_advisory_unlock/.test(sql)) return { rows: [{}] };
      if (/^DELETE FROM contract_reminders WHERE sent_at IS NULL$/.test(sql)) return { rows: [], rowCount: 0 };
      if (/^SELECT s\.site_code, s\.name FROM site_modules sm/.test(sql)) {
        assert.equal(params[0], 'contracts');
        return { rows: sites };
      }
      if (/^SELECT c\.id AS contract_id, .* CROSS JOIN LATERAL/.test(sql)) return { rows: due[params[0]] ?? [] };
      if (/^SELECT DISTINCT lower\(u\.email\) AS email FROM users u/.test(sql)) {
        assert.match(sql, /u\.is_active = TRUE AND u\.deleted_at IS NULL AND u\.email_verified = TRUE/);
        assert.match(sql, /role IN \('SITE_OWNER', 'SITE_ADMIN'\) AND is_active = TRUE/);
        return { rows: (recipients[params[0]] ?? []).map((email) => ({ email })) };
      }
      if (/^INSERT INTO contract_reminders .* ON CONFLICT \(contract_id, kind, due_date\) DO NOTHING RETURNING/.test(sql)) {
        const rows = params[1].map((contractId, index) => ({ id: String(900 + index), contract_id: String(contractId), kind: params[2][index], due_date: params[3][index] }));
        return { rows: claimed ? rows.filter((row) => claimed.includes(Number(row.contract_id))) : rows };
      }
      if (/^UPDATE contract_reminders SET sent_at = NOW\(\), recipients = \$2 WHERE id = ANY\(\$1::BIGINT\[\]\)$/.test(sql)) return { rows: [] };
      if (/^DELETE FROM contract_reminders WHERE id = ANY\(\$1::BIGINT\[\]\) AND sent_at IS NULL$/.test(sql)) return { rows: [] };
      throw new Error(`BEKLENMEYEN SQL: ${sql.slice(0, 160)}`);
    },
  };
  return { db: { connect: async () => client }, log, state };
}

const DAY = new Date('2026-10-19T07:00:00Z'); // İstanbul 10:00
const dueRow = (id, kind, due, end = due) => ({ contract_id: String(id), title: `Sözleşme ${id}`, vendor_name: `Firma ${id}`, kind, due_date: due, end_date: end });

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

  it('akış: yarım kalan talepler silinir -> siteler -> kalemler -> alıcılar -> talep -> alıcı başına AYRI e-posta -> sent_at + recipients; kilit açılır', async () => {
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
    const sqls = log.map(([sql]) => sql);
    assert.match(sqls[1], /^DELETE FROM contract_reminders WHERE sent_at IS NULL$/);
    const update = log.find(([sql]) => sql.startsWith('UPDATE contract_reminders'));
    assert.deepEqual(update[1], [[900, 901], 2]);
    // alıcısız sitede talep YAZILMAZ
    assert.equal(log.filter(([sql]) => sql.startsWith('INSERT INTO contract_reminders')).length, 1);
    assert.ok(sqls[sqls.length - 1].startsWith('SELECT pg_advisory_unlock'));
    assert.equal(state.released, 1);
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
    const none = fakeDb({ sites: [{ site_code: '1000000001', name: 'Gül' }], due: { 1000000001: [dueRow(11, 'bitis', '2026-10-30')] }, recipients: { 1000000001: ['a@example.com'] }, claimed: [] });
    const nothing = await runContractReminders({ now: DAY, db: none.db });
    assert.equal(nothing.emails, 0);
    assert.equal(sent.length, 1);
  });

  it('gönderim tamamen başarısızsa talep satırları silinir (sonraki tur yeniden dener); kısmi başarıda sent_at yazılır, recipients = başarılı sayı', async () => {
    contractReminderHooks.smtpConfigured = () => true;
    contractReminderHooks.send = async () => { throw new Error('SMTP'); };
    const site = { sites: [{ site_code: '1000000001', name: 'Gül' }], due: { 1000000001: [dueRow(11, 'bitis', '2026-10-30')] }, recipients: { 1000000001: ['a@example.com', 'b@example.com'] } };
    const failing = fakeDb(site);
    const result = await runContractReminders({ now: DAY, db: failing.db });
    assert.deepEqual([result.emails, result.failed_emails, result.reminders], [0, 2, 0]);
    assert.ok(failing.log.some(([sql, params]) => sql.startsWith('DELETE FROM contract_reminders WHERE id = ANY') && params[0][0] === 900));
    assert.ok(!failing.log.some(([sql]) => sql.startsWith('UPDATE contract_reminders')));
    let first = true;
    contractReminderHooks.send = async () => {
      if (first) {
        first = false;
        throw new Error('SMTP');
      }
    };
    const partial = fakeDb(site);
    const partialResult = await runContractReminders({ now: DAY, db: partial.db });
    assert.deepEqual([partialResult.emails, partialResult.failed_emails], [1, 1]);
    assert.deepEqual(partial.log.find(([sql]) => sql.startsWith('UPDATE contract_reminders'))[1], [[900], 1]);
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
