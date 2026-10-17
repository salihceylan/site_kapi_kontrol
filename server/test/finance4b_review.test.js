// Finans Faz 4b bağımsız R10 incelemesi düzeltmeleri (DB'siz): rapor yuvası sızıntısı, yuva bağımsızlığı, hesapsız tahsilat, dışa aktarma denetim anahtarları, not bağlantıları,
// gizli anahtar uyarısı, kaynak düzeyi korumalar (kuyruk kapıları, kilit sırası, kapsamlı aralık serbest bırakma). Gerçek PG sınamaları: scripts/qa_finance4b_review.mjs.
import { afterEach, describe, it, mock } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { reportConcurrency, withReportSnapshot } from '../src/modules/finance_reports.js';
import { resolvePaymentAccount } from '../src/modules/finance_accounts.js';
import { KNOWN_FILTER_KEYS, filterNamesOf } from '../src/modules/finance_export_tables.js';
import { buildFinanceReminderEmail, noteHasLink } from '../src/modules/finance_reminder_mail.js';
import { parseReminderSend } from '../src/modules/finance_reminders.js';
import { parsePostBody } from '../src/modules/finance_late_fee.js';
import { listAccounts } from '../src/modules/finance_accounts.js';
import { receiptSecret } from '../src/modules/finance_receipts.js';

const here = dirname(fileURLToPath(import.meta.url));
const MODULES = join(here, '..', 'src', 'modules');
const source = (name) => readFileSync(join(MODULES, `${name}.js`), 'utf8');
const KEY = 'anahtar-12345';

const fakeClient = (log = []) => ({
  log,
  async query(sql) {
    log.push(sql);
    return { rows: [{ ok: 1 }] };
  },
  release() {
    log.push('release');
  },
});

describe('P1-5: rapor yuvası bağlantı alınamazsa SIZMAZ', () => {
  it('connect 3 kez reddedilir: sayaç boş, ardından rapor çalışır (REPORT_BUSY değil); başarısız bağlantıda release çağrılmaz (istemci yok)', async () => {
    let attempts = 0;
    const client = fakeClient();
    const db = {
      connect: async () => {
        attempts += 1;
        if (attempts <= 3) throw new Error('timeout exceeded when trying to connect');
        return client;
      },
    };
    for (let i = 0; i < 3; i += 1) {
      await assert.rejects(() => withReportSnapshot(777, async () => 'x', db), /timeout exceeded/);
      assert.deepEqual(reportConcurrency(), {}, `deneme ${i + 1}: sayaç sızmadı`);
    }
    assert.equal(await withReportSnapshot(777, async () => 'sonuc', db), 'sonuc');
    assert.deepEqual(reportConcurrency(), {});
    assert.ok(client.log.includes('release'));
    assert.match(client.log[0], /^BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY$/);
  });

  it('iş (work) hata verirse ROLLBACK + release + sayaç düşer; BEGIN hata verirse de sayaç düşer', async () => {
    const client = fakeClient();
    await assert.rejects(() => withReportSnapshot(778, async () => { throw new Error('rapor hatasi'); }, { connect: async () => client }), /rapor hatasi/);
    assert.ok(client.log.includes('ROLLBACK') && client.log.includes('release'));
    assert.deepEqual(reportConcurrency(), {});
    const broken = { async query() { throw new Error('begin hatasi'); }, release() {} };
    await assert.rejects(() => withReportSnapshot(778, async () => 1, { connect: async () => broken }), /begin hatasi/);
    assert.deepEqual(reportConcurrency(), {});
  });

  it('yuvalar türe göre AYRI: rapor (2) doluyken önizleme ve sakin ekstresi çalışır; önizleme (2) dolunca REPORT_BUSY 503 + yönetici raporu etkilenmez', async () => {
    const holds = [];
    const hold = (siteCode, slot) => {
      let release;
      const gate = new Promise((resolve) => { release = resolve; });
      const running = withReportSnapshot(siteCode, () => gate, { connect: async () => fakeClient() }, { slot });
      holds.push(release);
      return running;
    };
    const reportA = hold(900, 'report');
    const reportB = hold(900, 'report');
    await assert.rejects(() => withReportSnapshot(900, async () => 1, { connect: async () => fakeClient() }), (error) => error.code === 'REPORT_BUSY' && error.statusCode === 503);
    assert.equal(await withReportSnapshot(900, async () => 'onizleme', { connect: async () => fakeClient() }, { slot: 'preview' }), 'onizleme');
    assert.equal(await withReportSnapshot(900, async () => 'sakin', { connect: async () => fakeClient() }, { slot: 'resident' }), 'sakin');
    const previewA = hold(900, 'preview');
    const previewB = hold(900, 'preview');
    await assert.rejects(() => withReportSnapshot(900, async () => 1, { connect: async () => fakeClient() }, { slot: 'preview' }), (error) => error.code === 'REPORT_BUSY');
    assert.equal(await withReportSnapshot(901, async () => 'baska-site', { connect: async () => fakeClient() }), 'baska-site');
    holds.forEach((release) => release());
    await Promise.all([reportA, reportB, previewA, previewB]);
    assert.deepEqual(reportConcurrency(), {});
  });
});

describe('P2-4: tüm hesaplar pasifken hesapsız tahsilat', () => {
  const clientWith = (row) => ({ async query() { return { rows: row ? [row] : [] }; } });
  it('tarihte açık etkin hesap -> ACCOUNT_REQUIRED; hesaplar var ama HEPSİ pasif -> 409 ACCOUNT_INACTIVE (ay kapatma engeline düşmesin); hesap hiç yok -> null (4a)', async () => {
    await assert.rejects(() => resolvePaymentAccount(clientWith({ has_active: true }), 1, { accountId: null, entryDate: '2026-10-10' }), (error) => error.code === 'ACCOUNT_REQUIRED');
    await assert.rejects(() => resolvePaymentAccount(clientWith({ has_active: false }), 1, { accountId: null, entryDate: '2026-10-10' }), (error) => error.code === 'ACCOUNT_INACTIVE' && /pasif/.test(error.message));
    assert.equal(await resolvePaymentAccount(clientWith(null), 1, { accountId: null, entryDate: '2026-10-10' }), null);
  });
});

describe('P2-12: dışa aktarma denetim anahtarları', () => {
  it('yalnız BİLİNEN süzgeç anahtarları yazılır; bilinmeyen anahtar adı (serbest metin taşıyabilir), format ve q yazılmaz; boş değerler atlanır', () => {
    assert.deepEqual(filterNamesOf({ from: '2026-01', to: '2026-10', status: 'all', q: 'gizli arama', format: 'csv', 'Ali Veli borcu': '1', apartment_id: '5', limit: '' }), ['apartment_id', 'from', 'status', 'to']);
    assert.deepEqual(filterNamesOf(undefined), []);
    assert.ok(KNOWN_FILTER_KEYS.every((key) => /^[a-z_]+$/.test(key)));
  });
});

describe('P2-16: hatırlatma notu bağlantı / alan adı / e-posta içeremez', () => {
  const body = (note) => ({ tone: 'friendly', note, expected_apartment_count: 1, expected_person_count: 1, expected_hash: 'a'.repeat(64), idempotency_key: KEY });
  it('ayrıştırıcı reddeder (400 INVALID_BODY); düz metin geçer', () => {
    for (const bad of ['Odeme icin https://ornek.example/ode', 'bkz www.ornek.com', 'iban icin bana yazin: x@y.com', 'ornek.com.tr uzerinden ode', 'ftp://x', 'sayfa: bit.ly/abc']) {
      assert.throws(() => parseReminderSend(body(bad)), (error) => error.statusCode === 400 && error.code === 'INVALID_BODY', bad);
    }
    assert.equal(parseReminderSend(body('Odemeyi bu hafta yapabilirseniz seviniriz.')).note, 'Odemeyi bu hafta yapabilirseniz seviniriz.');
    assert.equal(noteHasLink(null), false);
    assert.equal(noteHasLink('www.x.com'), true);
  });

  it('savunma: eski kayıtta bağlantılı not varsa ileti NOTSUZ gider (not metni e-postaya girmez)', () => {
    const mail = buildFinanceReminderEmail({ to: 'a@b.com', siteName: 'Gül Sitesi', tone: 'friendly', note: 'bkz https://kotu.example', apartments: [{ label: 'A - 1' }], withAmount: false, hasAccount: false });
    assert.equal(/kotu\.example|Yönetim notu/.test(mail.text + mail.html), false);
  });
});

describe('P2-13: kısa FINANCE_RECEIPT_SECRET uyarısı', () => {
  afterEach(() => mock.restoreAll());
  it('16 karakterden kısa anahtar yok sayılır, JWT türevine düşülür ve BİR KEZ uyarılır (değer yazdırılmaz)', () => {
    const warn = mock.method(console, 'warn', () => {});
    const derived = receiptSecret({ FINANCE_RECEIPT_SECRET: 'kisa-sir', JWT_SECRET: 'jwt-sirrim' });
    receiptSecret({ FINANCE_RECEIPT_SECRET: 'kisa-sir', JWT_SECRET: 'jwt-sirrim' });
    assert.match(derived, /^[0-9a-f]{64}$/);
    assert.equal(warn.mock.calls.length <= 1, true, 'en çok bir uyarı');
    assert.equal(warn.mock.calls.map((call) => call.arguments.join(' ')).join('').includes('kisa-sir'), false, 'sır değeri yazdırılmaz');
  });
});

describe('kaynak düzeyi korumalar (R10)', () => {
  it('P1-1/P1-2: kuyruk talebi legal_ok + modül + hatırlatma ayarını ve alıcı ilişkisini / muafiyeti / gün eşiğini GÖNDERİM ANINDA yeniden denetler', () => {
    const queue = source('finance_reminder_queue');
    assert.match(queue, /readLegalOk\(client\)/);
    assert.match(queue, /FROM site_modules m WHERE m\.site_code = r\.site_code AND m\.module_code = 'finance'/);
    assert.match(queue, /fs\.reminders_enabled FROM finance_settings fs WHERE fs\.site_code = r\.site_code/);
    assert.match(queue, /mark\(row, 'cancelled'\)/);
    assert.match(queue, /loadRecipientRows\(client, siteCode, unique\)/);
    assert.match(queue, /apartment\.excluded !== true/);
    assert.match(queue, /allowed\.has\(id\)/);
    assert.match(queue, /gate: gateCode/);
    // satır gönderilmek üzere seçilmeden ÖNCE kapı denetlenir
    assert.ok(queue.indexOf("mark(row, 'cancelled')") < queue.indexOf('send.push('));
  });

  it('P2-17: aralık serbest bırakma çalıştırma kapsamlı (global tarama yalnız toplu yollarda null ile)', () => {
    const queue = source('finance_reminder_queue');
    assert.match(queue, /\$1::BIGINT\[\] IS NULL OR fa\.run_id = ANY\(\$1::BIGINT\[\]\)/);
    assert.equal((queue.match(/query\(RELEASE_INTERVALS_SQL\)/g) ?? []).length, 0, 'parametresiz çağrı yok');
    assert.equal((queue.match(/RELEASE_INTERVALS_SQL, \[/g) ?? []).length >= 4, true);
  });

  it('P2-15: kilit sırası: reverseEntry hesabı makbuz iptalinden ÖNCE kilitler; correctExpense iki hesabı iptalden ÖNCE tek seferde id sırasıyla kilitler', () => {
    const ledger = source('finance_ledger_service');
    const reverse = ledger.slice(ledger.indexOf('export async function reverseEntry'));
    assert.ok(reverse.indexOf('lockAccountRows(client, siteCode, [Number(collection.account_id)])') < reverse.indexOf("reasonCode: 'payment_reversed'"));
    const expenses = source('finance_expenses');
    const correct = expenses.slice(expenses.indexOf('export async function correctExpense'));
    assert.ok(correct.indexOf('lockAccountRows(client, siteCode, [Number(row.account_id), input.accountId]') < correct.indexOf('await voidExpenseRow('));
  });

  it('P1-5/P2-9: yuva ve bağlantı try içinde; önizlemeler yuva + anlık görüntü içinde; sakin ekstresi ayrı yuva', () => {
    const reports = source('finance_reports');
    const snapshot = reports.slice(reports.indexOf('export async function withReportSnapshot'), reports.indexOf('/** Test yardımcısı'));
    assert.ok(snapshot.indexOf('try {') < snapshot.indexOf('client = await db.connect()'));
    assert.match(snapshot, /client\?\.release\(\)/);
    assert.match(reports, /\{ slot: 'resident' \}/);
    assert.match(source('finance_late_fee'), /\{ slot: 'preview' \}/);
    assert.match(source('finance_reminders'), /\{ slot: 'preview' \}/);
  });

  it('P1-3: hesaplanan bakiye, as_of_date >= asOf olan önceki mutabakatların düzeltmelerini içerir; düzeltme bugünün AÇIK ayına yazılır', () => {
    const accounts = source('finance_accounts');
    assert.match(accounts, /r\.adjustment_movement_id = m\.id AND r\.as_of_date <= \$3::DATE/);
    const reconcile = accounts.slice(accounts.indexOf('export async function createReconciliation'));
    assert.match(reconcile, /resolveOpenPeriod\(client, siteCode, now\)/);
    assert.equal(/assertWritableDate\(client, siteCode, todayIsoDate/.test(reconcile), false);
  });

  it('P1-6: belge dikişi açılış koşulu (süpürme expense_documents UNION) adaptör ve belge modülü başlığında yazılı; document_*.js dosyalarına dokunulmadı', () => {
    assert.match(source('finance_documents_adapter'), /AÇILIŞ KOŞULU[\s\S]*document_versions UNION expense_documents/);
    assert.match(source('finance_expense_documents'), /UNION[\s\S]*DOCUMENTS_NOT_AVAILABLE/);
    assert.equal(/documents_fsck\) toplar/.test(source('finance_expense_documents')), false, 'eski "fsck toplar" varsayımı kalmadı');
  });
});

describe('P1-4: bos ay isaret calistirmasi (record_empty)', () => {
  const body = (over = {}) => ({ period: '2026-08', expected_total_minor: 0, expected_apartment_count: 0, expected_hash: 'a'.repeat(64), idempotency_key: KEY, ...over });
  it('record_empty varsayilan false; yalniz boolean kabul edilir (true / false); baska tur 400', () => {
    assert.equal(parsePostBody(body()).recordEmpty, false);
    assert.equal(parsePostBody(body({ record_empty: null })).recordEmpty, false);
    assert.equal(parsePostBody(body({ record_empty: true })).recordEmpty, true);
    assert.equal(parsePostBody(body({ record_empty: false })).recordEmpty, false);
    for (const bad of ['true', 1, 0, 'evet', {}]) {
      assert.throws(() => parsePostBody(body({ record_empty: bad })), (error) => error.statusCode === 400 && error.code === 'INVALID_BODY', String(bad));
    }
  });

  it('kaynak: onizleme bos plani empty:true ile bildirir (NOTHING_TO_POST engeli yok); onay isaret calistirmasini yalniz record_empty ile yazar ve defter / satir YAZMAZ', () => {
    const lateFee = source('finance_late_fee');
    assert.equal(/blockers\.push\('NOTHING_TO_POST'\)/.test(lateFee), false);
    assert.match(lateFee, /empty: plan\.lines\.length === 0/);
    assert.match(lateFee, /if \(marker && !input\.recordEmpty\) \{\s*throw nothingToPost\(\)/);
    assert.match(lateFee, /if \(!marker && input\.recordEmpty\) \{[\s\S]*?previewStale/);
    const post = lateFee.slice(lateFee.indexOf('export async function postLateFee'), lateFee.indexOf('async function findRunById'));
    assert.ok(post.indexOf('if (marker) {') < post.indexOf('INSERT INTO ledger_entries'), 'isaret dali defter yazmadan once doner');
  });
});

describe('R11 F10: hatırlatma satırları tüm yollarda AYNI sırada kilitlenir', () => {
  it('iptal, işçi sonuç yazımı, bayat kapatma, pasif kişi taraması ve toplu kapatma: ORDER BY run_id, person_id FOR UPDATE', () => {
    const queue = source('finance_reminder_queue');
    const reminders = source('finance_reminders');
    assert.equal((queue.match(/ORDER BY (?:i\.)?run_id, (?:i\.)?person_id\s+FOR UPDATE/g) ?? []).length >= 4, true, 'kuyruk: finalize + stale + scrub + failAll');
    assert.match(reminders, /ORDER BY run_id, person_id\s+FOR UPDATE\s+\)\s+UPDATE finance_reminder_items i SET email_status = 'cancelled'/);
    // talep sorgusu zaten aynı sırayla kilitler
    assert.match(queue, /ORDER BY i\.run_id, i\.person_id\s+LIMIT \$4\s+FOR UPDATE OF i SKIP LOCKED/);
    // sırasız çok satırlı UPDATE kalmadı: unnest'ten doğrudan UPDATE ... FROM yok
    assert.equal(/UPDATE finance_reminder_items i\s+SET email_status = v\.st[\s\S]{0,400}FROM unnest\(\$1::BIGINT\[\], \$2::BIGINT\[\], \$3::TEXT\[\], \$4::INTEGER\[\]\) AS v/.test(queue), false);
  });
});

describe('hesap listesi: last_reconciliation.adjusted', () => {
  const row = (over = {}) => ({ id: '1', name: 'Kasa', kind: 'cash', note: null, opening_balance_minor: '0', opening_date: '2026-01-01', balance: '1000', is_active: true, sort_order: 0, rec_as_of: null, rec_difference: null, rec_adjusted: null, ...over });
  const dbWith = (rows) => ({
    async query(sql) {
      if (/FROM finance_accounts a/.test(sql)) return { rows };
      if (/FROM finance_accounts WHERE site_code/.test(sql)) return { rows: [{ total: '1', active: '1', earliest: null }] };
      return { rows: [{ n: 0, total: '0' }] };
    },
  });
  it('mutabakat yoksa null; fark düzeltmeyle kapatılmışsa adjusted true; düzeltilmemişse false; gösterilen fark değişmez', async () => {
    const none = await listAccounts(1, dbWith([row()]));
    assert.equal(none.items[0].last_reconciliation, null);
    const adjusted = await listAccounts(1, dbWith([row({ rec_as_of: '2026-10-15', rec_difference: '10000', rec_adjusted: true })]));
    assert.deepEqual(adjusted.items[0].last_reconciliation, { as_of_date: '2026-10-15', difference_minor: 10000, adjusted: true });
    const open = await listAccounts(1, dbWith([row({ rec_as_of: '2026-10-15', rec_difference: '-250', rec_adjusted: false })]));
    assert.deepEqual(open.items[0].last_reconciliation, { as_of_date: '2026-10-15', difference_minor: -250, adjusted: false });
    const legacy = await listAccounts(1, dbWith([row({ rec_as_of: '2026-10-15', rec_difference: '0', rec_adjusted: undefined })]));
    assert.equal(legacy.items[0].last_reconciliation.adjusted, false, 'alan yoksa false (null değil)');
  });

  it('kaynak: liste sorgusu adjustment_movement_id IS NOT NULL döndürür; kurul özeti kasa bölümü adjusted taşır', () => {
    assert.match(source('finance_accounts'), /\(r\.adjustment_movement_id IS NOT NULL\) AS adjusted/);
    assert.match(source('finance_reports'), /last_reconciliation: a\.last_reconciliation \? \{ as_of_date: a\.last_reconciliation\.as_of_date, difference_minor: [^}]*adjusted: a\.last_reconciliation\.adjusted === true/);
  });
});

describe('R15 P2-3: hatırlatma notu bağlantı süzgeci (NFKC + listesiz alan adı deseni)', () => {
  const REJECT = [
    'odeme-yap.online', 'aidat-ode.shop', 'yonetim.app', 'ornek.com', 'ORNEK.COM', 'ornek.com.tr', 'a1.xyz', 'sub.alan.org/yol', 'ödeme-yap.online', 'tiny.cc/abc',
    'Ödeme için bkz: odeme-yap.online.', '(yonetim.app)', 'https://x.example', 'HTTP://X', 'www.ornek', 'a@b.c', 'ad.soyad@firma.com.tr',
    'ｏｄｅｍｅ．ｃｏｍ', 'ornek。com', 'ornek．com', 'Ornek.Com/ode', 'x.Com?id=1', 'alan.adı.com', 'ornek.com:8080/yol',
  ];
  const ACCEPT = [
    'teşekkürler.Tr ekibi', 'Sayın sakinimiz.Lütfen ödemeyi yapın', 'Saat 14.30 gibi', '3.5 ay', 'Sn. Yönetici', 'vs. gibi', 'No.5 daire', 'Ödemeyi yaptıysanız bu iletiyi dikkate almayın.',
    'Teşekkürler. Hoşça kalın', '1.250,00 TL', 'Ödeme yapılmıştır.Bilgi için yönetime ulaşın', 'Yönetim.', 'ocak.Şubat aidatı',
  ];
  it('bağlantı / alan adı / e-posta REDDEDİLİR (kapalı TLD listesi yok: yeni TLD\'ler, tire, Unicode, tam genişlikli ve ideografik nokta, yol / sorgu / port)', () => {
    for (const note of REJECT) assert.equal(noteHasLink(note), true, note);
  });
  it('yaygın Türkçe cümle sonları KABUL edilir: boşluksuz yeni cümle (Başharfi büyük, yalnız harfli etiket), saat / ondalık / kısaltma', () => {
    for (const note of ACCEPT) assert.equal(noteHasLink(note), false, note);
  });
  it('bilinen sezgisel boşluk (belgelenmiş): yalnız harfli etiket + Başharfi büyük "TLD" ve yol YOK ("ornek.Com") cümle sonu sayılır; yol / küçük harf / rakam / tire varsa reddedilir', () => {
    assert.equal(noteHasLink('ornek.Com'), false);
    assert.equal(noteHasLink('ornek.Com/ode'), true);
    assert.equal(noteHasLink('ornek.com'), true);
    assert.equal(noteHasLink('ornek1.Com'), true);
    assert.equal(noteHasLink('or-nek.Com'), true);
  });
  it('ayrıştırıcı bu notları 400 ile reddeder, kabul edilenleri geçirir', () => {
    const body = (note) => ({ tone: 'friendly', note, expected_apartment_count: 1, expected_person_count: 1, expected_hash: 'a'.repeat(64), idempotency_key: KEY });
    for (const note of ['odeme-yap.online', 'aidat-ode.shop', 'yonetim.app']) {
      assert.throws(() => parseReminderSend(body(note)), (error) => error.statusCode === 400 && error.code === 'INVALID_BODY', note);
    }
    assert.equal(parseReminderSend(body('teşekkürler.Tr ekibi')).note, 'teşekkürler.Tr ekibi');
  });
});

describe('R15 P2-7 / P2-5 / P1-A: kaynak düzeyi', () => {
  it('P2-7: adres özeti temizliği satırları (run_id, person_id) sırasıyla kilitler', () => {
    const queue = source('finance_reminder_queue');
    const purge = queue.slice(queue.indexOf('export async function purgeStaleReminderHashes'));
    assert.match(purge, /ORDER BY run_id, person_id\s+FOR UPDATE/);
  });

  it('P2-5: belge dikişi AÇILIŞ KOŞULU kota maddesini de içerir (kota ve süpürme expense_documents\'i bilmeden dikiş açılmaz)', () => {
    for (const name of ['finance_documents_adapter', 'finance_expense_documents']) {
      const text = source(name);
      assert.match(text, /AÇILIŞ KOŞULU[\s\S]{0,1200}kota/i, name);
      assert.match(text, /document_service\.js/, `${name}: kota yeri`);
    }
  });

  it('P1-A: hesaplanan bakiye düzeltme hareketini KENDİ mutabakatının as_of tarihinde sayar; daha yeni tarihli düzeltilmiş mutabakat varken eski tarihe düzeltme RECONCILIATION_ORDER', () => {
    const accounts = source('finance_accounts');
    assert.match(accounts, /r\.adjustment_movement_id = m\.id AND r\.as_of_date <= \$3::DATE/);
    assert.match(accounts, /NOT EXISTS \(SELECT 1 FROM account_reconciliations r WHERE r\.adjustment_movement_id = m\.id\)/);
    assert.match(accounts, /throw reconciliationOrder\(\)/);
    assert.equal(/as_of_date >= \$3/.test(accounts), false, 'eski "as_of >= istenen" formülü kalmadı');
  });
});
