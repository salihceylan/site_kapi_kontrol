// Banka PDF ayrıştırıcı (saf): metin ögesi fikstürleriyle. Gerçek banka PDF örneği yoktur; düzenler yaygın TR ekstrelerine göre kuruldu.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { layoutLines, parseBankPdf, parseDate, parseMoney } from '../src/modules/bank_pdf_parser.js';

const H = 9;
const CW = 4.6;
const item = (x, y, str) => ({ str, x, y, w: str.length * CW, h: H });
const L = (x, str) => [x, str];
const R = (right, str) => [right - str.length * CW, str]; // sağa hizalı (tutar sütunları)
const row = (y, ...cells) => cells.map(([x, str]) => item(x, y, str));
const TODAY = '2026-10-21';
const parse = (items) => parseBankPdf([{ items }], { todayIso: TODAY });
const IBAN = 'TR33 0006 1005 1978 6457 8413 26';

describe('parseMoney', () => {
  it('Türk biçimleri ve işaretler', () => {
    assert.deepEqual(parseMoney('1.250,50'), { minor: 125050, sign: 0 });
    assert.deepEqual(parseMoney('250,5'), { minor: 25050, sign: 0 });
    assert.deepEqual(parseMoney('-1.250,50'), { minor: 125050, sign: -1 });
    assert.deepEqual(parseMoney('1.250,50-'), { minor: 125050, sign: -1 });
    assert.deepEqual(parseMoney('(1.250,50)'), { minor: 125050, sign: -1 });
    assert.deepEqual(parseMoney('+300,00 TL'), { minor: 30000, sign: 1 });
    assert.deepEqual(parseMoney('1.250,50 (B)'), { minor: 125050, sign: -1 });
    assert.deepEqual(parseMoney('1.250,50 A'), { minor: 125050, sign: 1 });
    assert.deepEqual(parseMoney('1250.50'), { minor: 125050, sign: 0 });
    assert.deepEqual(parseMoney('1 250,50'), { minor: 125050, sign: 0 });
  });
  it('tutar olmayanı reddeder; kuruşsuz sayı yalnız izinle', () => {
    for (const bad of ['', 'abc', '05.10.2026', '1.2', '12:30', 'TR33']) assert.equal(parseMoney(bad), null, bad);
    assert.equal(parseMoney('1250'), null);
    assert.deepEqual(parseMoney('1250', { allowInteger: true }), { minor: 125000, sign: 0 });
    assert.deepEqual(parseMoney('1.250', { allowInteger: true }), { minor: 125000, sign: 0 });
  });
});

describe('parseDate', () => {
  it('biçimler ve geçersiz tarih', () => {
    assert.equal(parseDate('05.10.2026'), '2026-10-05');
    assert.equal(parseDate('5/10/2026'), '2026-10-05');
    assert.equal(parseDate('05-10-2026 14:30'), '2026-10-05');
    assert.equal(parseDate('05.10.26'), '2026-10-05');
    assert.equal(parseDate('2026-10-05'), '2026-10-05');
    assert.equal(parseDate('31.02.2026'), null);
    assert.equal(parseDate('99.10.2026'), null);
    assert.equal(parseDate('abc'), null);
  });
});

describe('layoutLines', () => {
  it('aynı yükseklikteki ögeleri satırlaştırır, yakın ögeleri tek hücrede birleştirir, uzakları ayırır', () => {
    const lines = layoutLines([...row(700, L(50, '05.10.2026'), L(130, 'FAST'), L(152, 'GELEN'), R(410, '1.500,00')), ...row(688, L(130, 'devam'))]);
    assert.equal(lines.length, 2);
    assert.deepEqual(lines[0].cells.map((c) => c.text), ['05.10.2026', 'FAST GELEN', '1.500,00']);
    assert.deepEqual(lines[1].cells.map((c) => c.text), ['devam']);
  });
});

const headerRow = (y) => row(y, L(50, 'Tarih'), L(130, 'Açıklama'), R(410, 'Borç'), R(470, 'Alacak'), R(540, 'Bakiye'));

describe('başlıklı ekstre: Borç/Alacak sütunları', () => {
  const items = [
    ...row(800, L(50, 'HESAP EKSTRESİ')),
    ...row(780, L(50, `Hesap IBAN: ${IBAN}`)),
    ...headerRow(740),
    ...row(722, L(50, '01.10.2026'), L(130, 'Devir'), R(540, '10.000,00')),
    ...row(705, L(50, '05.10.2026'), L(130, 'FAST Gelen A BLOK 5 Ahmet Yılmaz'), R(470, '1.500,00'), R(540, '11.500,00')),
    ...row(694, L(130, 'ekim aidatı')),
    ...row(678, L(50, '07.10.2026'), L(130, 'Elektrik faturası'), R(410, '250,50'), R(540, '11.249,50')),
    ...row(662, L(50, '10.10.2026'), L(130, 'EFT Gelen D12 kasım'), R(470, '800,00'), R(540, '12.049,50')),
    ...row(640, L(130, 'Toplam'), R(410, '250,50'), R(470, '2.300,00')),
    ...row(60, L(250, 'Sayfa 1/1')),
  ];
  const r = parse(items);
  it('hareketleri, işaretleri ve çok satırlı açıklamayı doğru okur', () => {
    assert.equal(r.mode, 'header');
    assert.deepEqual(r.lines.map((l) => [l.n, l.value_date, l.amount_minor, l.balance_after_minor]), [
      [1, '2026-10-05', 150000, 1150000],
      [2, '2026-10-07', -25050, 1124950],
      [3, '2026-10-10', 80000, 1204950],
    ]);
    assert.equal(r.lines[0].description, 'FAST Gelen A BLOK 5 Ahmet Yılmaz ekim aidatı');
    assert.equal(r.lines[2].description, 'EFT Gelen D12 kasım');
  });
  it('devir satırını atar, toplam satırını saymaz, hesap IBAN ve dönemi bulur', () => {
    assert.equal(r.lines.length, 3);
    assert.equal(r.unreadable, 0);
    assert.equal(r.skipped, 1);
    assert.equal(r.accountIban, 'TR330006100519786457841326');
    assert.deepEqual(r.statement, { from: '2026-10-05', to: '2026-10-10' });
    assert.ok(r.lines.every((l) => l.confidence === 'high'));
  });
  it('sayfa altlığı önceki hareketin açıklamasına eklenmez', () => {
    assert.ok(!r.lines[2].description.includes('Sayfa'));
  });
});

describe('tek Tutar sütunu', () => {
  const head = row(740, L(50, 'Tarih'), L(130, 'Açıklama'), R(420, 'Tutar'), R(500, 'Bakiye'));
  it('işaretsiz tutar, bakiye zinciri yoksa okunamayan sayılır (yanlış yönde tahsilat yazılmaz)', () => {
    const r = parse([...head, ...row(720, L(50, '05.10.2026'), L(130, 'Havale'), R(420, '1.500,00')), ...row(705, L(50, '06.10.2026'), L(130, 'Su faturası'), R(420, '-300,00'))]);
    assert.deepEqual(r.lines.map((l) => l.amount_minor), [-30000]);
    assert.equal(r.unreadable, 1);
  });
  it('işaretsiz tutarın yönü bakiye farkından çıkar (orta güven)', () => {
    const r = parse([
      ...head,
      ...row(725, L(50, '01.10.2026'), L(130, 'Devir'), R(500, '1.000,00')),
      ...row(710, L(50, '05.10.2026'), L(130, 'Havale'), R(420, '1.500,00'), R(500, '2.500,00')),
      ...row(695, L(50, '06.10.2026'), L(130, 'Su faturası'), R(420, '300,00'), R(500, '2.200,00')),
    ]);
    assert.deepEqual(r.lines.map((l) => [l.amount_minor, l.confidence]), [[150000, 'medium'], [-30000, 'medium']]);
    assert.equal(r.unreadable, 0);
  });
  it('B/A gösterge sütunu', () => {
    const r = parse([
      ...row(740, L(50, 'Tarih'), L(130, 'Açıklama'), R(420, 'Tutar'), L(440, 'B/A')),
      ...row(720, L(50, '05.10.2026'), L(130, 'Havale'), R(420, '1.500,00'), L(440, 'A')),
      ...row(705, L(50, '06.10.2026'), L(130, 'Su'), R(420, '300,00'), L(440, 'B')),
    ]);
    assert.deepEqual(r.lines.map((l) => l.amount_minor), [150000, -30000]);
  });
});

describe('bakiye çelişkisi ve sıra', () => {
  it('açık işaret bakiye farkıyla çelişirse güven düşük', () => {
    const r = parse([
      ...headerRow(740),
      ...row(725, L(50, '01.10.2026'), L(130, 'Devir'), R(540, '1.000,00')),
      ...row(710, L(50, '05.10.2026'), L(130, 'Havale'), R(410, '500,00'), R(540, '1.500,00')), // borç denmiş ama bakiye arttı
    ]);
    assert.equal(r.lines[0].amount_minor, -50000);
    assert.equal(r.lines[0].confidence, 'low');
  });
  it('en yeni üstte (azalan) sıra desteklenir', () => {
    const r = parse([
      ...headerRow(740),
      ...row(720, L(50, '10.10.2026'), L(130, 'EFT'), R(470, '800,00'), R(540, '12.049,50')),
      ...row(705, L(50, '07.10.2026'), L(130, 'Fatura'), R(410, '250,50'), R(540, '11.249,50')),
      ...row(690, L(50, '05.10.2026'), L(130, 'Havale'), R(470, '1.500,00'), R(540, '11.500,00')),
      ...row(675, L(50, '01.10.2026'), L(130, 'Devir'), R(540, '10.000,00')),
    ]);
    assert.deepEqual(r.lines.map((l) => l.amount_minor), [80000, -25050, 150000]);
    assert.ok(r.lines.every((l) => l.confidence === 'high'));
  });
});

describe('başlıksız sezgisel kip', () => {
  it('tarih + Türk tutarı + bakiye; GG/AA/YYYY ve GG.AA.YY; (B)/(A) göstergeli', () => {
    const r = parse([
      ...row(780, L(50, `IBAN ${IBAN}`)),
      ...row(720, L(50, '05/10/2026'), L(120, 'Gelen havale 5 nolu daire'), R(460, '1.500,00 (A)'), R(540, '11.500,00')),
      ...row(705, L(50, '06.10.26'), L(120, 'Su faturası'), R(460, '300,00 (B)'), R(540, '11.200,00')),
    ]);
    assert.equal(r.mode, 'heuristic');
    assert.deepEqual(r.lines.map((l) => [l.value_date, l.amount_minor, l.confidence]), [['2026-10-05', 150000, 'medium'], ['2026-10-06', -30000, 'medium']]);
    assert.equal(r.accountIban, 'TR330006100519786457841326');
  });
});

describe('ek durumlar', () => {
  it('iki satırlı başlık (İşlem / Tarihi)', () => {
    const r = parse([
      ...row(750, L(50, 'İşlem'), L(130, 'Açıklama'), R(420, 'Borç'), R(500, 'Alacak')),
      ...row(740, L(50, 'Tarihi'), R(420, 'Tutarı'), R(500, 'Tutarı')),
      ...row(720, L(50, '05.10.2026'), L(130, 'Havale'), R(500, '1.500,00')),
    ]);
    assert.equal(r.mode, 'header');
    assert.deepEqual(r.lines.map((l) => l.amount_minor), [150000]);
  });
  it('karşı IBAN ve gönderen adı açıklamadan ayıklanır; ayrı sütunlar da okunur', () => {
    const r = parse([
      ...row(740, L(50, 'Tarih'), L(110, 'Açıklama'), L(300, 'Gönderen'), R(470, 'Alacak'), R(540, 'Bakiye')),
      ...row(720, L(50, '05.10.2026'), L(110, 'FAST TR33 0006 1005 1978 6457 8413 26'), L(300, 'AHMET YILMAZ'), R(470, '1.500,00'), R(540, '2.500,00')),
    ]);
    assert.equal(r.lines[0].counterparty_name, 'AHMET YILMAZ');
    assert.equal(r.lines[0].counterparty_iban, 'TR330006100519786457841326');
    const g = parse([...headerRow(740), ...row(720, L(50, '05.10.2026'), L(130, 'FAST Gönderen: AYŞE KAYA Açıklama: aidat'), R(470, '1.500,00'))]);
    assert.equal(g.lines[0].counterparty_name, 'AYŞE KAYA');
  });
  it('gelecek tarih ve tarihli ama tutarsız satır okunamayan sayılır', () => {
    const r = parse([
      ...headerRow(740),
      ...row(720, L(50, '05.10.2026'), L(130, 'Havale'), R(470, '1.500,00')),
      ...row(705, L(50, '05.12.2026'), L(130, 'Gelecek'), R(470, '10,00')),
      ...row(690, L(50, '06.10.2026'), L(130, 'Tutarı okunamadı')),
    ]);
    assert.equal(r.lines.length, 1);
    assert.equal(r.unreadable, 2);
  });
  it('metin yoksa charCount 0 (taranmış PDF)', () => {
    const r = parseBankPdf([{ items: [] }, { items: [] }], { todayIso: TODAY });
    assert.equal(r.charCount, 0);
    assert.equal(r.lines.length, 0);
  });
  it('sonraki sayfada başlık tekrarlanır / tekrarlanmaz', () => {
    const page1 = [...headerRow(740), ...row(720, L(50, '05.10.2026'), L(130, 'Havale'), R(470, '1.500,00'), R(540, '1.500,00'))];
    const page2 = [...row(780, L(50, 'Sayfa 2')), ...row(720, L(50, '07.10.2026'), L(130, 'Fatura'), R(410, '250,50'), R(540, '1.249,50'))];
    const r = parseBankPdf([{ items: page1 }, { items: page2 }], { todayIso: TODAY });
    assert.deepEqual(r.lines.map((l) => l.amount_minor), [150000, -25050]);
  });
});
