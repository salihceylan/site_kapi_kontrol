// Finans Faz 4b ayarlar + borç hatırlatma (saf): ayar yaması ayrıştırma, yasal kapı varsayılanları, uygunluk nedenleri, e-posta içeriği kuralları.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import {
  LATE_FEE_METHODS,
  SETTINGS_DEFAULTS,
  parseSettingsPatch,
  settingsBody,
} from '../src/modules/finance_settings.js';
import {
  REMINDER_ITEM_STATUSES,
  failingReason,
  parseReminderPreview,
  parseReminderSend,
  reminderDailyCap,
  reminderFingerprint,
  thresholdsOf,
} from '../src/modules/finance_reminders.js';
import { buildFinanceReminderEmail, cleanReminderNote, trDate } from '../src/modules/finance_reminder_mail.js';
import { dayNumber } from '../src/modules/finance_4b_common.js';

const NOW = new Date('2026-10-16T09:00:00Z');
const KEY = 'anahtar-12345';
const throws400 = (fn, label) => assert.throws(fn, (error) => error.statusCode === 400 && error.code === 'INVALID_BODY' && error.expose === true, label);

describe('ayar varsayılanları (yasal kapı: varsayılan KAPALI)', () => {
  it('tazminat ve hatırlatma kapalı, makbuz otomatik, oran tavanda (%5 = 500 bp), 30 günlük esas; yasal bayrak anahtarı', () => {
    assert.equal(SETTINGS_DEFAULTS.late_fee_enabled, false);
    assert.equal(SETTINGS_DEFAULTS.reminders_enabled, false);
    assert.equal(SETTINGS_DEFAULTS.receipts_auto_issue, true);
    assert.equal(SETTINGS_DEFAULTS.late_fee_rate_bp, 500);
    assert.equal(SETTINGS_DEFAULTS.late_fee_method, 'daily_30');
    assert.equal(SETTINGS_DEFAULTS.late_fee_start_period, null);
    assert.deepEqual([SETTINGS_DEFAULTS.reminder_min_overdue_minor, SETTINGS_DEFAULTS.reminder_min_days_overdue, SETTINGS_DEFAULTS.reminder_min_interval_days, SETTINGS_DEFAULTS.reminder_max_consecutive], [5000, 5, 14, 3]);
    assert.equal(SETTINGS_DEFAULTS.settings_version, 1);
    assert.deepEqual([...LATE_FEE_METHODS], ['daily_30', 'daily_actual']);
    assert.throws(() => { SETTINGS_DEFAULTS.late_fee_enabled = true; }, TypeError, 'donmuş');
  });

  it('GET gövdesi: dönem etiketi YYYY-AA, ek alanlar (max_rate_bp, next_period, smtp_configured); yasal bayrak yanıtta', () => {
    const body = settingsBody({ ...SETTINGS_DEFAULTS, late_fee_start_period: '2026-09-01' }, { nextPeriod: '2026-10-01', lastRunId: 4 }, { legalOk: false, smtpConfigured: true });
    assert.equal(body.legal_ok, false);
    assert.equal(body.late_fee.start_period, '2026-09');
    assert.equal(body.late_fee.next_period, '2026-10');
    assert.equal(body.late_fee.voidable_run_id, 4);
    assert.equal(body.late_fee.max_rate_bp, 500);
    assert.equal(body.reminders.smtp_configured, true);
    assert.equal(body.receipts.auto_issue, true);
    assert.equal(settingsBody(SETTINGS_DEFAULTS, { nextPeriod: null, lastRunId: null }, { legalOk: true, smtpConfigured: false }).late_fee.start_period, null);
  });
});

describe('ayar yaması', () => {
  it('geçerli yama: sütun adlarına eşlenir; anahtar listesi yalnız DEĞİŞEN alan adları (değer yok)', () => {
    const patch = parseSettingsPatch({
      expected_settings_version: 3,
      receipts: { auto_issue: false },
      late_fee: { enabled: true, rate_bp: 300, method: 'daily_actual', grace_days: 5, start_period: '2026-09' },
      reminders: { enabled: true, min_overdue_minor: 10000, min_days_overdue: 10, min_interval_days: 21, max_consecutive: 2 },
    }, NOW);
    assert.equal(patch.expectedVersion, 3);
    assert.deepEqual(patch.changes, {
      receipts_auto_issue: false, late_fee_enabled: true, late_fee_rate_bp: 300, late_fee_method: 'daily_actual', late_fee_grace_days: 5, late_fee_start_period: '2026-09-01',
      reminders_enabled: true, reminder_min_overdue_minor: 10000, reminder_min_days_overdue: 10, reminder_min_interval_days: 21, reminder_max_consecutive: 2,
    });
    assert.deepEqual(patch.keys, ['receipts.auto_issue', 'late_fee.enabled', 'late_fee.rate_bp', 'late_fee.method', 'late_fee.grace_days', 'late_fee.start_period', 'reminders.enabled', 'reminders.min_overdue_minor', 'reminders.min_days_overdue', 'reminders.min_interval_days', 'reminders.max_consecutive']);
    assert.equal(JSON.stringify(patch.keys).includes('300'), false);
  });

  it('sınırlar: oran en çok 500 bp (KMK tavanı), ek gün <= 90, başlangıç ayı en fazla 12 ay ileride ve 5 yıldan eski olamaz', () => {
    const v = (late_fee) => parseSettingsPatch({ expected_settings_version: 1, late_fee }, NOW);
    assert.equal(v({ rate_bp: 500 }).changes.late_fee_rate_bp, 500);
    assert.equal(v({ rate_bp: 0 }).changes.late_fee_rate_bp, 0);
    assert.equal(v({ grace_days: 90 }).changes.late_fee_grace_days, 90);
    assert.equal(v({ start_period: '2027-10' }).changes.late_fee_start_period, '2027-10-01');
    assert.equal(v({ start_period: '2026-09-01' }).changes.late_fee_start_period, '2026-09-01', 'ayın ilk günü biçimi de kabul');
    for (const bad of [{ rate_bp: 501 }, { rate_bp: -1 }, { rate_bp: 3.5 }, { rate_bp: '300' }, { grace_days: 91 }, { method: 'gercek' }, { enabled: 'evet' }, { start_period: '2027-11' }, { start_period: '2020-01' }, { start_period: '2026-13' }, { start_period: '2026-09-15' }, { yeni: 1 }]) {
      throws400(() => v(bad), JSON.stringify(bad));
    }
  });

  it('hatırlatma eşikleri: tutar >= 100 kuruş, gecikme 1-120 gün, aralık 7-90 gün, ardışık 1-6', () => {
    const v = (reminders) => parseSettingsPatch({ expected_settings_version: 1, reminders }, NOW);
    assert.equal(v({ min_interval_days: 7 }).changes.reminder_min_interval_days, 7);
    assert.equal(v({ max_consecutive: 6 }).changes.reminder_max_consecutive, 6);
    for (const bad of [{ min_overdue_minor: 99 }, { min_days_overdue: 0 }, { min_days_overdue: 121 }, { min_interval_days: 6 }, { min_interval_days: 91 }, { max_consecutive: 0 }, { max_consecutive: 7 }, { enabled: 1 }, { min_overdue_minor: 1e13 }]) {
      throws400(() => v(bad), JSON.stringify(bad));
    }
  });

  it('yapı: sürüm zorunlu (iyimser kilit), bilinmeyen kök / grup alanı ve boş yama reddedilir', () => {
    for (const bad of [
      {}, { receipts: { auto_issue: true } }, { expected_settings_version: 0, receipts: { auto_issue: true } }, { expected_settings_version: '1', receipts: { auto_issue: true } }, { expected_settings_version: 1 },
      { expected_settings_version: 1, receipts: {} }, { expected_settings_version: 1, bilinmeyen: 1 }, { expected_settings_version: 1, receipts: [] }, { expected_settings_version: 1, receipts: { baska: true } },
      { expected_settings_version: 1, late_fee: null }, null, [],
    ]) throws400(() => parseSettingsPatch(bad, NOW), JSON.stringify(bad));
  });
});

describe('hatırlatma gövdeleri ve uygunluk', () => {
  it('önizleme: ton zorunlu (friendly | standard)', () => {
    assert.deepEqual(parseReminderPreview({ tone: 'friendly' }), { tone: 'friendly' });
    for (const bad of [{}, { tone: 'sert' }, { tone: null }]) throws400(() => parseReminderPreview(bad), JSON.stringify(bad));
  });

  it('gönderim: beklenen sayılar + 64 hex özet + anahtar zorunlu; not 300 karaktere kadar', () => {
    const ok = { tone: 'standard', note: ' yarın son gün ', expected_apartment_count: 4, expected_person_count: 6, expected_hash: 'b'.repeat(64), idempotency_key: KEY };
    assert.deepEqual(parseReminderSend(ok), { tone: 'standard', note: 'yarın son gün', expectedHash: 'b'.repeat(64), expectedApartmentCount: 4, expectedPersonCount: 6, idempotencyKey: KEY });
    for (const change of [{ expected_apartment_count: -1 }, { expected_person_count: '6' }, { expected_hash: 'kisa' }, { expected_hash: 'B'.repeat(64) }, { idempotency_key: undefined }, { tone: 'x' }, { note: 'x'.repeat(301) }, { expected_apartment_count: 100001 }]) {
      throws400(() => parseReminderSend({ ...ok, ...change }), JSON.stringify(change));
    }
  });

  it('parmak izi: ton ya da temizlenmiş not değişince değişir, anahtar / sayılar değişince DEĞİŞMEZ', () => {
    const base = parseReminderSend({ tone: 'standard', note: 'a', expected_apartment_count: 1, expected_person_count: 1, expected_hash: 'c'.repeat(64), idempotency_key: KEY });
    const other = parseReminderSend({ tone: 'standard', note: ' a ', expected_apartment_count: 9, expected_person_count: 9, expected_hash: 'd'.repeat(64), idempotency_key: 'baska-anahtar-1' });
    assert.equal(reminderFingerprint(other), reminderFingerprint(base));
    assert.notEqual(reminderFingerprint({ ...base, tone: 'friendly' }), reminderFingerprint(base));
    assert.notEqual(reminderFingerprint({ ...base, note: 'b' }), reminderFingerprint(base));
  });

  it('günlük sınır: ortamdan; geçersiz / boş -> 300; 0 geçerli (gönderim kapalı)', () => {
    assert.equal(reminderDailyCap({}), 300);
    assert.equal(reminderDailyCap({ FINANCE_REMINDER_MAX_PER_DAY_PER_SITE: '50' }), 50);
    assert.equal(reminderDailyCap({ FINANCE_REMINDER_MAX_PER_DAY_PER_SITE: '0' }), 0);
    assert.equal(reminderDailyCap({ FINANCE_REMINDER_MAX_PER_DAY_PER_SITE: '' }), 300);
    assert.equal(reminderDailyCap({ FINANCE_REMINDER_MAX_PER_DAY_PER_SITE: '-5' }), 300);
    assert.equal(reminderDailyCap({ FINANCE_REMINDER_MAX_PER_DAY_PER_SITE: 'x' }), 300);
  });

  it('uygunluk nedeni sırası: muaf > tutar > gün > aralık > ardışık (elden takip); hepsi geçerse null', () => {
    const today = dayNumber('2026-10-16');
    const thresholds = thresholdsOf({ ...SETTINGS_DEFAULTS });
    assert.deepEqual(thresholds, { min_overdue_minor: 5000, min_days_overdue: 5, min_interval_days: 14, max_consecutive: 3 });
    const good = { excluded: false, overdue: 10000n, oldestDue: '2026-09-01', lastDay: null, consecutive: 0 };
    assert.equal(failingReason(good, thresholds, today), null);
    assert.equal(failingReason({ ...good, excluded: true, overdue: 1n }, thresholds, today), 'exclusion');
    assert.equal(failingReason({ ...good, overdue: 4999n }, thresholds, today), 'amount');
    assert.equal(failingReason({ ...good, overdue: 5000n }, thresholds, today), null, 'eşik dahil');
    assert.equal(failingReason({ ...good, oldestDue: '2026-10-12' }, thresholds, today), 'days');
    assert.equal(failingReason({ ...good, oldestDue: '2026-10-11' }, thresholds, today), null, '5. gün dahil');
    assert.equal(failingReason({ ...good, oldestDue: null }, thresholds, today), 'days');
    assert.equal(failingReason({ ...good, lastDay: today - 13 }, thresholds, today), 'interval');
    assert.equal(failingReason({ ...good, lastDay: today - 14 }, thresholds, today), null, '14. gün dahil');
    assert.equal(failingReason({ ...good, consecutive: 3 }, thresholds, today), 'consecutive');
    assert.equal(failingReason({ ...good, consecutive: 2 }, thresholds, today), null);
    assert.ok(REMINDER_ITEM_STATUSES.includes('no_address') && REMINDER_ITEM_STATUSES.includes('skipped_pref') && REMINDER_ITEM_STATUSES.includes('capped'));
  });
});

describe('hatırlatma e-postası (içerik kuralları)', () => {
  const apartments = [{ label: 'A Blok - 5', overdueMinor: 123456n, oldestDue: '2026-08-01' }, { label: 'B Blok - 2', overdueMinor: 5000, oldestDue: '2026-09-15' }];
  const input = { to: 'sakin@example.com', siteName: 'Gül Sitesi', tone: 'friendly', apartments, withAmount: true, hasAccount: true, unsubscribeUrl: 'https://api.example.com/unsubscribe?t=abc' };

  it('konu: tutar / ad / daire YOK; tutar yalnız withAmount ile gövdede; vade tarihi GG.AA.YYYY; Türkçe biçim', () => {
    const mail = buildFinanceReminderEmail(input);
    assert.equal(mail.subject, '[Gül Sitesi] Ödeme hatırlatması');
    assert.equal(/\d|Blok|₺/.test(mail.subject), false);
    assert.match(mail.text, /A Blok - 5: 1\.234,56 ₺ \(en eski vade: 01\.08\.2026\)/);
    assert.match(mail.text, /B Blok - 2: 50,00 ₺/);
    assert.match(mail.html, /1\.234,56 ₺/);
    assert.equal(trDate('2026-01-09'), '09.01.2026');
  });

  it('withAmount false (doğrulanmamış / CRM adresi): tutar sızmaz; "Borcum" yönlendirmesi', () => {
    const mail = buildFinanceReminderEmail({ ...input, withAmount: false, hasAccount: false });
    assert.equal(/₺|1\.234|50,00/.test(mail.text + mail.html), false);
    assert.match(mail.text, /"Borcum"/);
    assert.equal(/Bildirim Tercihleri/.test(mail.text), false, 'hesabı olmayan alıcıya uygulama ipucu verilmez');
  });

  it('tek daire sözcüğü, çok daire listesi; resmî ton "Sayın site sakini,", nazik ton "Merhaba,"; adla hitap yok', () => {
    const single = buildFinanceReminderEmail({ ...input, apartments: [apartments[0]] });
    assert.match(single.text, /A Blok - 5 dairesine/);
    assert.match(single.text, /Vadesi geçmiş tutar: 1\.234,56 ₺/);
    assert.match(buildFinanceReminderEmail(input).text, /A Blok - 5, B Blok - 2 dairelerine/);
    assert.match(buildFinanceReminderEmail({ ...input, tone: 'standard' }).text, /^Sayın site sakini,/);
    assert.match(buildFinanceReminderEmail(input).text, /^Merhaba,/);
  });

  it('yasaklı dil yok (icra / dava / ihtar / tehdit / kampanya / indirim); altbilgi: gönderen + "tanıtım iletisi değildir" + abonelikten çık + List-Unsubscribe', () => {
    for (const tone of ['friendly', 'standard']) {
      const mail = buildFinanceReminderEmail({ ...input, tone });
      assert.equal(/icra|dava|ihtar|tehdit|haciz|kampanya|indirim|fırsat/i.test(mail.text + mail.html), false, tone);
      assert.match(mail.text, /tanıtım iletisi değildir/);
      assert.match(mail.text, /Gül Sitesi site yönetimi tarafından gönderildi/);
      assert.match(mail.text, /https:\/\/api\.example\.com\/unsubscribe\?t=abc/);
      assert.match(mail.html, /Abonelikten çık/);
    }
    const mail = buildFinanceReminderEmail(input);
    assert.deepEqual(mail.headers, { 'List-Unsubscribe': '<https://api.example.com/unsubscribe?t=abc>', 'List-Unsubscribe-Post': 'List-Unsubscribe=One-Click' });
    const bare = buildFinanceReminderEmail({ ...input, unsubscribeUrl: null });
    assert.equal(bare.headers, undefined);
    assert.match(bare.text, /Bildirim tercihlerinizi uygulamadan değiştirebilirsiniz/);
    assert.equal(buildFinanceReminderEmail({ ...input, unsubscribeUrl: 'javascript:alert(1)' }).headers, undefined, 'güvensiz bağlantı kullanılmaz');
  });

  it('yönetici notu düz metindir: HTML kaçışlanır, satır başı enjeksiyonu ve kontrol karakterleri temizlenir, 300 karakter', () => {
    const mail = buildFinanceReminderEmail({ ...input, note: '<script>alert(1)</script>\r\nBcc: kurban\u0000' });
    assert.equal(mail.html.includes('<script>'), false);
    assert.match(mail.html, /&lt;script&gt;/);
    assert.equal(/\r|\n.*Bcc:/.test(mail.text.split('Yönetim notu: ')[1].split('\n')[0]), false);
    assert.equal(mail.text.includes('\u0000'), false);
    assert.equal(cleanReminderNote('  a \n\n b  '), 'a b');
    assert.equal(cleanReminderNote('   '), null);
    assert.equal(cleanReminderNote(null), null);
    assert.equal(cleanReminderNote('x'.repeat(400)).length, 300);
    assert.equal(buildFinanceReminderEmail({ ...input, note: null }).text.includes('Yönetim notu'), false);
  });

  it('konu satırı başlık enjeksiyonuna kapalı (site adındaki satır sonu); geçersiz alıcı INVALID_RECIPIENT', () => {
    const mail = buildFinanceReminderEmail({ ...input, siteName: 'Gül\r\nBcc: x@y.com Sitesi' });
    assert.equal(/[\r\n]/.test(mail.subject), false);
    for (const to of ['', 'yok', 'a@b', 'a b@c.com', 'a@b.com, c@d.com', '<a@b.com>', `${'x'.repeat(250)}@b.com`, null]) {
      assert.throws(() => buildFinanceReminderEmail({ ...input, to }), (error) => error.code === 'INVALID_RECIPIENT', String(to).slice(0, 20));
    }
  });
});
