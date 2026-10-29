// Dekont bildirimi / geçici kabul (066; DB'siz): migration <-> şema eşitliği, ensure, ayrıştırma, durum makinesi, uyarılar, dosya imzası.
// Gerçek PostgreSQL doğrulaması (onay tek işlemde defter + makbuz, eşzamanlı onay, tetikleyici, IDOR) kullanıcı denemesinde / QA'da yapılır.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { DEFAULT_MIGRATIONS_DIR, findUnsafeStatements } from '../scripts/migrate.js';
import { PAYMENT_NOTICES_DDL, PAYMENT_NOTICES_DDL_ORDER, ensurePaymentNoticesSchema } from '../src/modules/payment_notice_schema.js';
import {
  NOTICE_MAX_BYTES,
  canTransition,
  computeWarnings,
  fingerprintOf,
  mapNotice,
  nameMatches,
  parseApproveInput,
  parseIdList,
  parseNoticeInput,
  parseRejectInput,
} from '../src/modules/payment_notice_common.js';
import { assertNoticeHead } from '../src/modules/payment_notice_upload.js';

process.env.JWT_SECRET ||= 'test-secret-test-secret-test-secret-123456';

const norm = (t) => t.replace(/--.*$/gm, ' ').replace(/\s+/g, ' ').trim();
const NOW = new Date('2026-10-21T09:00:00Z');
const base = { apartment_id: 7, amount_minor: 125000, paid_on: '2026-10-20', idempotency_key: 'k1', file: { name: 'dekont.pdf', size: 1000, content_type: 'application/pdf' } };

describe('066 migration <-> şema', () => {
  const sql = readFileSync(path.join(DEFAULT_MIGRATIONS_DIR, '066_payment_notices.sql'), 'utf8').replace(/\r\n/g, '\n');

  it('aynı ifadeler, aynı sırada', () => {
    const expected = PAYMENT_NOTICES_DDL_ORDER.map((n) => `${norm(PAYMENT_NOTICES_DDL[n])};`).join(' ');
    assert.equal(norm(sql), expected);
  });

  it('güvenli (ekleyici) ifadeler', () => {
    assert.deepEqual(findUnsafeStatements(sql), []);
  });

  it('her şey varsa hiçbir DDL gönderilmez', async () => {
    const calls = [];
    const indexes = PAYMENT_NOTICES_DDL_ORDER.map((n) => /idx_|uq_/.exec(PAYMENT_NOTICES_DDL[n])?.[0]).filter(Boolean);
    const client = {
      async query(text) {
        calls.push(text);
        const names = [...text.matchAll(/(?:idx|uq)_payment_notices_\w+/g)].map((m) => m[0]);
        return { rows: [{ has_table: true, indexes: [...new Set([...names, ...Object.values(PAYMENT_NOTICES_DDL).flatMap((d) => [...d.matchAll(/(?:idx|uq)_payment_notices_\w+/g)].map((m) => m[0]))])] }] };
      },
    };
    await ensurePaymentNoticesSchema(client);
    assert.equal(calls.length, 1);
    assert.ok(indexes.length >= 0);
  });

  it('tablo yoksa tüm adımlar sırayla çalışır', async () => {
    const calls = [];
    const client = {
      async query(text) {
        calls.push(text);
        return { rows: [{ has_table: false, indexes: [] }] };
      },
    };
    await ensurePaymentNoticesSchema(client);
    const ddl = calls.filter((c) => /CREATE|DO \$\$/.test(c));
    assert.equal(ddl.length, PAYMENT_NOTICES_DDL_ORDER.length);
    assert.ok(calls.some((c) => c.includes('lock_timeout')));
  });
});

describe('durum makinesi', () => {
  it('izinli geçişler', () => {
    assert.ok(canTransition('uploading', 'pending'));
    assert.ok(canTransition('pending', 'approved'));
    assert.ok(canTransition('pending', 'rejected'));
    assert.ok(canTransition('pending', 'withdrawn'));
  });
  it('karara bağlanmış bildirim geri dönmez', () => {
    for (const from of ['approved', 'rejected', 'withdrawn']) {
      for (const to of ['pending', 'approved', 'rejected', 'withdrawn', 'uploading']) assert.equal(canTransition(from, to), false);
    }
    assert.equal(canTransition('uploading', 'approved'), false);
  });
});

describe('ayrıştırma', () => {
  it('geçerli sakin bildirimi', () => {
    const input = parseNoticeInput(base, { now: NOW });
    assert.equal(input.amountMinor, 125000);
    assert.equal(input.origin, 'resident_app');
    assert.equal(input.method, 'transfer');
    assert.equal(input.file.type, 'application/pdf');
  });
  it('sakin: dosya zorunlu, gelecek tarih ve 1 yıldan eski tarih reddedilir', () => {
    assert.throws(() => parseNoticeInput({ ...base, file: undefined }, { now: NOW }), /Dekont dosyası zorunludur/);
    assert.throws(() => parseNoticeInput({ ...base, paid_on: '2026-10-22' }, { now: NOW }), /Gelecek tarihli/);
    assert.throws(() => parseNoticeInput({ ...base, paid_on: '2025-01-01' }, { now: NOW }), /1 yıl/);
  });
  it('tutar kuruş tamsayı ve pozitif', () => {
    assert.throws(() => parseNoticeInput({ ...base, amount_minor: 12.5 }, { now: NOW }));
    assert.throws(() => parseNoticeInput({ ...base, amount_minor: 0 }, { now: NOW }));
    assert.throws(() => parseNoticeInput({ ...base, amount_minor: '1250' }, { now: NOW }));
  });
  it('dosya türü ve boyutu', () => {
    assert.throws(() => parseNoticeInput({ ...base, file: { name: 'a.exe', size: 10, content_type: 'application/x-msdownload' } }, { now: NOW }), /PDF, JPEG ve PNG/);
    assert.throws(() => parseNoticeInput({ ...base, file: { name: 'a.pdf', size: NOTICE_MAX_BYTES + 1, content_type: 'application/pdf' } }, { now: NOW }), /10 MB/);
    assert.throws(() => parseNoticeInput({ ...base, file: { name: 'a.pdf', size: 0, content_type: 'application/pdf' } }, { now: NOW }));
  });
  it('IBAN: geçerli TR kabul, bozuk ret', () => {
    assert.equal(parseNoticeInput({ ...base, sender_iban: 'TR33 0006 1005 1978 6457 8413 26' }, { now: NOW }).senderIban, 'TR330006100519786457841326');
    assert.throws(() => parseNoticeInput({ ...base, sender_iban: 'TR00 1234' }, { now: NOW }), /IBAN/);
  });
  it('yönetici girişi: dosya isteğe bağlı, yöntem seçilebilir', () => {
    const input = parseNoticeInput({ ...base, file: undefined, method: 'cash', account_party: 'tenant' }, { manager: true, now: NOW });
    assert.equal(input.file, null);
    assert.equal(input.method, 'cash');
    assert.equal(input.origin, 'manager');
    assert.equal(input.accountParty, 'tenant');
    assert.throws(() => parseNoticeInput({ ...base, method: 'bitcoin' }, { manager: true, now: NOW }), /yöntemi/);
  });
  it('işlem anahtarı zorunlu; parmak izi içeriğe bağlı', () => {
    assert.throws(() => parseNoticeInput({ ...base, idempotency_key: undefined }, { now: NOW }), /idempotency_key/);
    const a = fingerprintOf(parseNoticeInput(base, { now: NOW }));
    const b = fingerprintOf(parseNoticeInput({ ...base, amount_minor: 99 }, { now: NOW }));
    assert.notEqual(a, b);
  });
  it('ret nedeni listede olmalı; onay gövdesi; toplu liste sınırı', () => {
    assert.throws(() => parseRejectInput({ reason_code: 'xx' }), /neden/);
    assert.equal(parseRejectInput({ reason_code: 'duplicate', note: ' Aynısı ' }).note, 'Aynısı');
    const approve = parseApproveInput({ account_id: 3, book_in_open_period: true, acknowledged: ['POSSIBLE_DUPLICATE', 5] });
    assert.deepEqual([approve.accountId, approve.bookInOpenPeriod, approve.acknowledged], [3, true, ['POSSIBLE_DUPLICATE']]);
    assert.throws(() => parseApproveInput({ account_id: 'x' }));
    // K3: İşletme / Fon hesabı seçimi (isteğe bağlı; geçersiz değer 400)
    assert.equal(approve.fund, null);
    assert.equal(parseApproveInput({ fund: 'capital' }).fund, 'capital');
    assert.equal(parseApproveInput({ fund: 'operating' }).fund, 'operating');
    assert.equal(parseApproveInput({ fund: null }).fund, null);
    assert.throws(() => parseApproveInput({ fund: 'kasa' }), (e) => e.statusCode === 400 && e.code === 'INVALID_BODY');
    assert.deepEqual(parseIdList({ ids: [1, '2', 2] }), [1, 2]);
    assert.throws(() => parseIdList({ ids: [] }));
    assert.throws(() => parseIdList({ ids: Array.from({ length: 51 }, (_, i) => i + 1) }));
  });
});

describe('uyarılar', () => {
  const notice = { amount_minor: '125000', paid_on: '2026-10-20', sender_name: 'Ayşe Yılmaz' };
  const facts = { notice, otherApartmentRef: false, sameFileCount: 0, duplicateCount: 0, peopleNames: ['Ayşe Yılmaz'], accountBalanceMinor: 125000, now: NOW };
  it('temiz bildirimde uyarı yok', () => {
    assert.deepEqual(computeWarnings(facts), []);
  });
  it('önemli uyarılar', () => {
    const codes = computeWarnings({ ...facts, otherApartmentRef: true, sameFileCount: 1, duplicateCount: 2 }).map((w) => `${w.code}:${w.level}`);
    assert.deepEqual(codes, ['REFERENCE_OTHER_APARTMENT:strong', 'SAME_FILE_OTHER_NOTICE:strong', 'POSSIBLE_DUPLICATE:strong']);
  });
  it('bilgi uyarıları: ad uyuşmazlığı, fazla ödeme, eski tarih', () => {
    const out = computeWarnings({ ...facts, notice: { ...notice, sender_name: 'Mehmet Kaya', paid_on: '2026-07-01' }, accountBalanceMinor: 50000 });
    assert.deepEqual(out.map((w) => w.code), ['NAME_MISMATCH', 'OVERPAYMENT', 'OLD_DATE']);
    assert.ok(out.every((w) => w.level === 'info'));
  });
  it('ad eşleşmesi Türkçe karakter ve büyük/küçük harf duyarsız', () => {
    assert.ok(nameMatches('AYSE YILMAZ', ['Ayşe Yılmaz']));
    assert.ok(nameMatches('ahmet', ['Mehmet Ahmet Öz']));
    assert.equal(nameMatches('Mehmet Kaya', ['Ayşe Yılmaz']), false);
  });
});

describe('dosya imzası', () => {
  const pdf = Buffer.from('%PDF-1.7\n....');
  const jpeg = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0, 0x10, 0x4a, 0x46]);
  const png = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0]);
  it('doğru tür kabul', () => {
    assertNoticeHead(pdf, 'application/pdf');
    assertNoticeHead(jpeg, 'image/jpeg');
    assertNoticeHead(png, 'image/png');
  });
  it('uyuşmayan ya da tanınmayan tür 415', () => {
    assert.throws(() => assertNoticeHead(pdf, 'image/png'), (e) => e.statusCode === 415 && e.code === 'NOTICE_CONTENT_MISMATCH');
    assert.throws(() => assertNoticeHead(Buffer.from('<html>'), 'application/pdf'), (e) => e.statusCode === 415 && e.code === 'NOTICE_TYPE_NOT_ALLOWED');
    assert.throws(() => assertNoticeHead(Buffer.alloc(0), 'image/png'), (e) => e.statusCode === 415);
  });
});

describe('çıktı', () => {
  it('sakine karar notu ve görülmemiş işareti', () => {
    const out = mapNotice({
      id: '5', site_code: '1', apartment_id: '7', account_party: 'owner', origin: 'resident_app', status: 'rejected', amount_minor: '125000', paid_on: '2026-10-20',
      method: 'transfer', submitted_at: NOW, reject_reason_code: 'duplicate', file_required: true, storage_key: 'k', file_completed_at: NOW,
    });
    assert.equal(out.unseen_decision, true);
    assert.equal(out.has_file, true);
    assert.match(out.reject_reason_text, /daha önce/);
  });
});
