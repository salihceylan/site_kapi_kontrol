// ALTIN VERİ SETİ (karar F5; docs/PLATFORM_FINANS.md "Altın veri seti"): 24 daireli gerçekçi bir site ve ELLE hesaplanmış beklenen değerler.
//
// KURAL: Aşağıdaki beklenen tutarların HİÇBİRİ kod çalıştırılarak üretilmedi; her biri yorumdaki adımlarla elle hesaplandı ve iki kez kontrol edildi.
// Test (test/finance_golden_dataset.test.js) gerçek dağıtım / gecikme / mahsup kodunu çalıştırır; sonuç kuruşu kuruşuna tutmazsa test düşer.
// Bir sapma çıkarsa ÖNCE buradaki elle hesap iki kez yeniden kontrol edilir; hesap doğruysa hata raporlanır (hesap kodu bu fikstüre uydurulmaz).
// Para: tamsayı kuruş. 1 TL = 100 kuruş. Tarihler İstanbul takvim günü.
//
// ------------------------------------------------------------------------------------------------------------------------------------------
// SİTE: "Altın Veri Sitesi" — A Blok 12 daire (2 dükkan + 10 adet 3+1), B Blok 12 daire (4 adet 1+1 + 8 adet 2+1). Daire kimliği = sıra (A-1 = 1 ... B-12 = 24).
//
//  Daire   Kim.  Kategori  Brüt m²   Net m²    Arsa payı
//  A-1      1    Dükkan     85,50     68,75     50/1200
//  A-2      2    Dükkan     64,25     54,50     40/1200
//  A-3..7   3-7  3+1       120,00    100,00     62/1200 (her biri)
//  A-8..12  8-12 3+1       118,25     98,75     61/1200 (her biri)
//  B-1..4  13-16 1+1        62,40     52,00     54/2400 (her biri)
//  B-5..8  17-20 2+1       101,20     84,50     97/2400 (her biri)
//  B-9,10  21,22 2+1       101,15     84,25     96/2400 (her biri)
//  B-11,12 23,24 2+1       101,15     84,25     97/2400 (her biri)
//
//  Brüt toplam: 85,50 + 64,25 + 5x120,00 + 5x118,25 + 4x62,40 + 4x101,20 + 4x101,15
//             = 149,75 + 600,00 + 591,25 + 249,60 + 404,80 + 404,60 = 2.400,00 m²   (ağırlık = m² x 100 -> W = 240.000)
//  Net toplam:  68,75 + 54,50 + 5x100,00 + 5x98,75 + 4x52,00 + 4x84,50 + 4x84,25
//             = 123,25 + 500,00 + 493,75 + 208,00 + 338,00 + 337,00 = 2.000,00 m²   (W = 200.000)
//  Arsa payı ortak payda 2400 (1200'lük paylar x2): A-1 100, A-2 80, A-3..7 124, A-8..12 122, B-1..4 54, B-5..8 97, B-9,10 96, B-11,12 97
//             toplam 100 + 80 + 620 + 610 + 216 + 388 + 192 + 194 = 2.400 (= 2400/2400, tam arsa)
//
// DAĞITIM KURALI (docs/PLATFORM_FINANS.md "Dağıtım ve yuvarlama"): pay_i = taban(T x w_i / W); kalan kuruşlar (T - Σ taban) "en büyük kalan"
// (T x w_i mod W) sırasıyla birer birer dağıtılır; kalanlar eşitse kimliği küçük daire önce alır. Payların toplamı T'ye BİREBİR eşittir.
// ------------------------------------------------------------------------------------------------------------------------------------------

/** 24 daire (dağıtım kodunun beklediği biçim: m² x 100 metin, SQL çıktısı gibi). */
export const GOLDEN_SITE = Object.freeze(
  (() => {
    const rows = [
      // [blok, no, kategori, brüt x100, net x100, arsa pay, arsa payda]
      ['A', 1, 'Dükkan', 8550, 6875, 50, 1200],
      ['A', 2, 'Dükkan', 6425, 5450, 40, 1200],
      ...[3, 4, 5, 6, 7].map((n) => ['A', n, '3+1', 12000, 10000, 62, 1200]),
      ...[8, 9, 10, 11, 12].map((n) => ['A', n, '3+1', 11825, 9875, 61, 1200]),
      ...[1, 2, 3, 4].map((n) => ['B', n, '1+1', 6240, 5200, 54, 2400]),
      ...[5, 6, 7, 8].map((n) => ['B', n, '2+1', 10120, 8450, 97, 2400]),
      ['B', 9, '2+1', 10115, 8425, 96, 2400],
      ['B', 10, '2+1', 10115, 8425, 96, 2400],
      ['B', 11, '2+1', 10115, 8425, 97, 2400],
      ['B', 12, '2+1', 10115, 8425, 97, 2400],
    ];
    return rows.map(([block, n, category, gross, net, numerator, denominator], index) =>
      Object.freeze({
        id: index + 1,
        label: `${block}-${n}`,
        blockName: `${block} Blok`,
        blockSort: block === 'A' ? 1 : 2,
        aptSort: n,
        payerParty: 'owner',
        category,
        grossX100: String(gross),
        netX100: String(net),
        landNumerator: numerator,
        landDenominator: denominator,
      }),
    );
  })(),
);

/** Etiket listesi yardımcıları (beklenen değer tablolarını kısaltır). */
const A = (from, to) => Array.from({ length: to - from + 1 }, (_, i) => `A-${from + i}`);
const B = (from, to) => Array.from({ length: to - from + 1 }, (_, i) => `B-${from + i}`);
const each = (labels, amount) => Object.fromEntries(labels.map((label) => [label, amount]));

export const DISTRIBUTION_CASES = Object.freeze([
  // -------------------------------------------------------------------------------------------------------------------------------------
  // D1 EŞİT: aylık aidat toplamı 85.000,00 TL (T = 8.500.000 kuruş), 24 daire, ağırlık 1 (W = 24).
  //   taban = 8.500.000 / 24 = 354.166 (24 x 354.166 = 8.499.984); her dairenin kalanı 8.500.000 mod 24 = 16 (hepsi eşit).
  //   artan = 8.500.000 - 8.499.984 = 16 kuruş -> kalanlar eşit olduğundan kimliği küçük 16 daire (A-1..A-12, B-1..B-4) +1 kuruş.
  //   Sonuç: A-1..B-4 = 354.167; B-5..B-12 = 354.166. Kontrol: 16 x 354.167 + 8 x 354.166 = 5.666.672 + 2.833.328 = 8.500.000.
  {
    name: 'D1 eşit (85.000,00 TL aidat; 16 kuruş yuvarlama farkı küçük kimliklere)',
    definition: { distribution: 'equal', amountMinor: 8500000 },
    expected: { ...each([...A(1, 12), ...B(1, 4)], 354167), ...each(B(5, 12), 354166) },
  },
  // -------------------------------------------------------------------------------------------------------------------------------------
  // D2 BRÜT m²: ortak gider 10.000,00 TL (T = 1.000.000), W = 240.000 -> pay = w x 1.000.000 / 240.000 = w x 25 / 6.
  //   w      w x 25 / 6              taban    kalan (T x w mod W)   daireler
  //   8550   213.750 / 6 = 35.625      35.625         0             A-1
  //   6425   160.625 / 6 = 26.770,83   26.770   200.000             A-2
  //   12000  300.000 / 6 = 50.000      50.000         0             A-3..A-7
  //   11825  295.625 / 6 = 49.270,83   49.270   200.000             A-8..A-12
  //   6240   156.000 / 6 = 26.000      26.000         0             B-1..B-4
  //   10120  253.000 / 6 = 42.166,67   42.166   160.000             B-5..B-8
  //   10115  252.875 / 6 = 42.145,83   42.145   200.000             B-9..B-12
  //   Σ taban = 35.625 + 26.770 + 250.000 + 246.350 + 104.000 + 168.664 + 168.580 = 999.989 -> artan 11 kuruş.
  //   En büyük kalan 200.000: A-2, A-8..A-12, B-9..B-12 (10 daire) +1; sıradaki 160.000 grubundan (B-5..B-8) yalnız kimliği küçük B-5 +1.
  //   Kontrol: kesirler 10 x 0,8333 + 4 x 0,6667 = 11.
  {
    name: 'D2 brüt m² (10.000,00 TL; 11 kuruş farkın 10 kuruşu eşit kalanlı daireler, 1 kuruşu eşitlikte küçük kimlik B-5)',
    definition: { distribution: 'area', areaBasis: 'gross', amountMinor: 1000000 },
    expected: {
      'A-1': 35625,
      'A-2': 26771,
      ...each(A(3, 7), 50000),
      ...each(A(8, 12), 49271),
      ...each(B(1, 4), 26000),
      'B-5': 42167,
      ...each(B(6, 8), 42166),
      ...each(B(9, 12), 42146),
    },
  },
  // -------------------------------------------------------------------------------------------------------------------------------------
  // D3 NET m²: asansör bakımı 5.000,03 TL (T = 500.003), W = 200.000 -> pay = w x 2,500015.
  //   w      T x w                taban    kalan     daireler
  //   6875   3.437.520.625        17.187   120.625   A-1
  //   5450   2.725.016.350        13.625    16.350   A-2
  //   10000  5.000.030.000        25.000    30.000   A-3..A-7
  //   9875   4.937.529.625        24.687   129.625   A-8..A-12
  //   5200   2.600.015.600        13.000    15.600   B-1..B-4
  //   8450   4.225.025.350        21.125    25.350   B-5..B-8
  //   8425   4.212.525.275        21.062   125.275   B-9..B-12
  //   Σ taban = 17.187 + 13.625 + 125.000 + 123.435 + 52.000 + 84.500 + 84.248 = 499.995 -> artan 8 kuruş.
  //   Sıra: 129.625 (A-8..A-12, 5 daire) -> 125.275 (B-9..B-12; kalan 3 kuruş kimliği küçük B-9, B-10, B-11'e). B-12 ve A-1 (120.625) almaz.
  //   Kontrol: (5 x 129.625 + 4 x 125.275 + 120.625 + 5 x 30.000 + 4 x 25.350 + 16.350 + 4 x 15.600) / 200.000 = 1.600.000 / 200.000 = 8.
  {
    name: 'D3 net m² (5.000,03 TL; 8 kuruş fark, eşit kalanlı B grubunda B-12 almaz)',
    definition: { distribution: 'area', areaBasis: 'net', amountMinor: 500003 },
    expected: {
      'A-1': 17187,
      'A-2': 13625,
      ...each(A(3, 7), 25000),
      ...each(A(8, 12), 24688),
      ...each(B(1, 4), 13000),
      ...each(B(5, 8), 21125),
      'B-9': 21063,
      'B-10': 21063,
      'B-11': 21063,
      'B-12': 21062,
    },
  },
  // -------------------------------------------------------------------------------------------------------------------------------------
  // D4 ARSA PAYI (paydalar 1200 ve 2400; ortak payda 2400): çatı yalıtımı 36.000,19 TL (T = 3.600.019), W = 2.400.
  //   T x w = 3.600.000 x w + 19 x w -> taban = 1.500 x w (19 x w < 2.400 her ağırlıkta), kalan = 19 x w.
  //   w     taban     kalan (19 x w)   daireler
  //   100   150.000   1.900            A-1
  //   80    120.000   1.520            A-2
  //   124   186.000   2.356            A-3..A-7
  //   122   183.000   2.318            A-8..A-12
  //   54     81.000   1.026            B-1..B-4
  //   97    145.500   1.843            B-5..B-8, B-11, B-12
  //   96    144.000   1.824            B-9, B-10
  //   Σ taban = 1.500 x 2.400 = 3.600.000 -> artan 19 kuruş. Sıra: 2.356 (5) -> 2.318 (5) -> 1.900 (A-1) -> 1.843 (6) -> 1.824 (2) = 19.
  //   +1 ALMAYANLAR: A-2 (1.520) ve B-1..B-4 (1.026). Kontrol: (11.780 + 11.590 + 1.900 + 11.058 + 3.648 + 1.520 + 4.104) / 2.400 = 45.600 / 2.400 = 19.
  {
    name: 'D4 arsa payı (1200 ve 2400 paydaları; 36.000,19 TL; 19 kuruş fark)',
    definition: { distribution: 'land_share', amountMinor: 3600019 },
    expected: {
      'A-1': 150001,
      'A-2': 120000,
      ...each(A(3, 7), 186001),
      ...each(A(8, 12), 183001),
      ...each(B(1, 4), 81000),
      ...each(B(5, 8), 145501),
      'B-9': 144001,
      'B-10': 144001,
      'B-11': 145501,
      'B-12': 145501,
    },
  },
  // -------------------------------------------------------------------------------------------------------------------------------------
  // D5 KATEGORİ: daire başı tutar (yuvarlama yok). Haritadaki "DÜKKAN" yazımı dairelerdeki "Dükkan" ile eşleşir (Türkçe harf ve büyük/küçük harf
  //   duyarsız). Dükkan 1.500,00 TL; 3+1 1.250,00 TL; 2+1 1.000,00 TL; 1+1 750,00 TL.
  //   Toplam = 2 x 150.000 + 10 x 125.000 + 8 x 100.000 + 4 x 75.000 = 300.000 + 1.250.000 + 800.000 + 300.000 = 2.650.000.
  {
    name: 'D5 kategori (daire başı tutar; harf duyarsız eşleşme)',
    definition: { distribution: 'category', categoryAmounts: { 'DÜKKAN': 150000, '3+1': 125000, '2+1': 100000, '1+1': 75000 } },
    expected: { ...each(A(1, 2), 150000), ...each(A(3, 12), 125000), ...each(B(1, 4), 75000), ...each(B(5, 12), 100000) },
  },
  // -------------------------------------------------------------------------------------------------------------------------------------
  // D6 SABİT: her daireye 500,00 TL (T daire başı). Toplam 24 x 50.000 = 1.200.000.
  {
    name: 'D6 sabit (daire başı 500,00 TL)',
    definition: { distribution: 'fixed', amountMinor: 50000 },
    expected: each([...A(1, 12), ...B(1, 12)], 50000),
  },
]);

// ------------------------------------------------------------------------------------------------------------------------------------------
// GECİKME TAZMİNATI (docs/PLATFORM_FINANS_4B.md Ö2): hesaplanan ay P'nin her günü d için L(d) = vadesi + ek gün geçmiş (eşik < d), tazminat OLMAYAN
// kalemlerin M1 kalanı. S = Σ L(d) (kuruş x gün). fee = taban((2 x S x R + 10.000 x D) / (20.000 x D)) (yarım yukarı); R = 500 baz puan (aylık %5),
// D = 30 (daily_30) ya da ayın gün sayısı (daily_actual). Ödeme günü gecikme sayılmaz (ödeme o gün tabandan düşer); vade günü de sayılmaz.
// Satır biçimi: { id, kind, amount (kuruş; borç +, ödeme -), entry (kayıt günü), due (vade), lateFee }.
// ------------------------------------------------------------------------------------------------------------------------------------------

export const LATE_FEE_CASES = Object.freeze([
  // L1 (A-3): Eylül aidatı 1.250,00 TL (vade 05.09.2026) hiç ödenmedi. P = Ekim 2026 (31 gün), ek gün 0.
  //   Ekim'in 31 gününün hepsinde L = 125.000 -> S = 31 x 125.000 = 3.875.000.
  //   daily_30:     (2 x 3.875.000 x 500 + 300.000) / 600.000 = 3.875.300.000 / 600.000 = 6.458,83 -> 6.458 (64,58 TL = %5 x 31/30)
  //   daily_actual: (3.875.000.000 + 310.000) / 620.000 = 6.250,5 -> 6.250 (62,50 TL = tam %5: ayın tamamı aylık %5'i aşmaz)
  {
    name: 'L1 tam ay ödenmemiş borç: daily_30 31 günlük ayda %5,17, daily_actual tam %5',
    apartment: 'A-3',
    period: '2026-10',
    graceDays: 0,
    rows: [{ id: 101, kind: 'charge', amount: 125000, entry: '2026-09-01', due: '2026-09-05' }],
    expected: {
      daily_30: { base: 3875000, fee: 6458 },
      daily_actual: { base: 3875000, fee: 6250 },
      peak: 125000,
      breakdown: [{ from: '2026-10-01', to: '2026-10-31', overdue: 125000 }],
    },
  },
  // L2 (A-4): Ağustos, Eylül, Ekim aidatları (her biri 1.250,00 TL; vadeler 05.08, 05.09, 05.10); ödemeler 20.09'da 1.500,00 TL, 15.10'da 1.000,00 TL.
  //   P = Ekim 2026, ek gün 0, daily_30. M1 (vadesi en eski önce):
  //   01-05 Ekim (5 gün): ödenen 150.000 -> Ağu 0, Eyl 100.000 (gecikmede), Eki 125.000 (vade 05.10 henüz geçmedi) -> L = 100.000 -> 500.000
  //   06-14 Ekim (9 gün): Eki aidatı da gecikmede -> L = 100.000 + 125.000 = 225.000 -> 2.025.000
  //   15-31 Ekim (17 gün): 15.10'daki ödeme O GÜN düşer -> ödenen 250.000 -> Ağu 0, Eyl 0, Eki 125.000 -> L = 125.000 -> 2.125.000
  //   S = 500.000 + 2.025.000 + 2.125.000 = 4.650.000; fee = (4.650.000.000 + 300.000) / 600.000 = 7.750,5 -> 7.750 (77,50 TL)
  {
    name: 'L2 kısmi ödemeler: en eski vadeden mahsup, ödeme günü gecikme sayılmaz, vade günü sayılmaz',
    apartment: 'A-4',
    period: '2026-10',
    graceDays: 0,
    rows: [
      { id: 201, kind: 'charge', amount: 125000, entry: '2026-08-01', due: '2026-08-05' },
      { id: 202, kind: 'charge', amount: 125000, entry: '2026-09-01', due: '2026-09-05' },
      { id: 203, kind: 'payment', amount: -150000, entry: '2026-09-20' },
      { id: 204, kind: 'charge', amount: 125000, entry: '2026-10-01', due: '2026-10-05' },
      { id: 205, kind: 'payment', amount: -100000, entry: '2026-10-15' },
    ],
    expected: {
      daily_30: { base: 4650000, fee: 7750 },
      peak: 225000,
      breakdown: [
        { from: '2026-10-01', to: '2026-10-05', overdue: 100000 },
        { from: '2026-10-06', to: '2026-10-14', overdue: 225000 },
        { from: '2026-10-15', to: '2026-10-31', overdue: 125000 },
      ],
    },
  },
  // L3 (B-5): Ekim aidatı 1.000,00 TL (vade 10.10.2026) + önceki ayın gecikme tazminatı kalemi 20,00 TL (01.10.2026; tazminat kalemi).
  //   Ödeme 25.10'da 500,00 TL. P = Ekim 2026, daily_30. "Yalnız ana borç": tazminat kalemi tabana GİRMEZ ama vadesi (01.10) daha eski olduğu için
  //   ödemeyi ÖNCE tüketir (M1): 25.10'da 2.000 tazminata, 48.000 aidata -> aidatın kalanı 52.000.
  //   Ek gün 5: eşik 10.10 + 5 = 15.10 -> gecikme 16.10'da başlar.
  //     16-24 Ekim (9 gün) L = 100.000 -> 900.000; 25-31 Ekim (7 gün) L = 52.000 -> 364.000; S = 1.264.000
  //     fee = (1.264.000.000 + 300.000) / 600.000 = 2.107,17 -> 2.107 (21,07 TL)
  //   Ek gün 0: gecikme 11.10'da başlar: 11-24 Ekim (14 gün) x 100.000 = 1.400.000; 25-31 Ekim 7 x 52.000 = 364.000; S = 1.764.000
  //     fee = (1.764.000.000 + 300.000) / 600.000 = 2.940,5 -> 2.940 (29,40 TL)
  {
    name: 'L3 ek gün, faiz üstüne faiz yok (tazminat kalemi tabanda değil ama önce mahsup edilir)',
    apartment: 'B-5',
    period: '2026-10',
    rows: [
      { id: 301, kind: 'charge', amount: 2000, entry: '2026-10-01', due: '2026-10-01', lateFee: true },
      { id: 302, kind: 'charge', amount: 100000, entry: '2026-10-01', due: '2026-10-10' },
      { id: 303, kind: 'payment', amount: -50000, entry: '2026-10-25' },
    ],
    graceDays: 5,
    expected: {
      daily_30: { base: 1264000, fee: 2107 },
      peak: 100000,
      breakdown: [
        { from: '2026-10-16', to: '2026-10-24', overdue: 100000 },
        { from: '2026-10-25', to: '2026-10-31', overdue: 52000 },
      ],
    },
    withoutGrace: {
      daily_30: { base: 1764000, fee: 2940 },
      breakdown: [
        { from: '2026-10-11', to: '2026-10-24', overdue: 100000 },
        { from: '2026-10-25', to: '2026-10-31', overdue: 52000 },
      ],
    },
  },
  // L4 (A-7): 1.000,00 TL borç (vade 05.01.2027) hiç ödenmedi; P = Şubat 2027 (28 gün). Ayın tamamı gecikmede: S = 28 x 100.000 = 2.800.000.
  //   daily_30:     (2.800.000.000 + 300.000) / 600.000 = 4.667,17 -> 4.667 (%4,67 = %5 x 28/30)
  //   daily_actual: (2.800.000.000 + 280.000) / 560.000 = 5.000,5 -> 5.000 (tam %5)
  {
    name: 'L4 Şubat (28 gün): daily_30 %4,67, daily_actual tam %5',
    apartment: 'A-7',
    period: '2027-02',
    graceDays: 0,
    rows: [{ id: 401, kind: 'charge', amount: 100000, entry: '2027-01-01', due: '2027-01-05' }],
    expected: {
      daily_30: { base: 2800000, fee: 4667 },
      daily_actual: { base: 2800000, fee: 5000 },
      peak: 100000,
      breakdown: [{ from: '2027-02-01', to: '2027-02-28', overdue: 100000 }],
    },
  },
]);

// ------------------------------------------------------------------------------------------------------------------------------------------
// MAHSUP (M1; TBK m.101-102): ödemeler toplamı, kalemlere VADESİ EN ESKİDEN başlayarak (vade eşitse kayıt kimliği küçük olan önce) dökülür.
// kalan_i = min(tutar_i, max(0, birikimli_i - ödenen)); artan ödeme alacaktır.
// ------------------------------------------------------------------------------------------------------------------------------------------

export const MAHSUP_CASES = Object.freeze([
  // M1 (A-5): Eylül aidatı 125.000 (vade 05.09), Ekim aidatı 125.000 (vade 05.10), çatı yalıtımı payı 186.001 (D4'teki A-5 payı; 02.10'da yazıldı
  //   ama vadesi 20.09). Toplam ödeme 200.000. Vade sırası: Eylül (05.09) -> Çatı (20.09) -> Ekim (05.10).
  //   Eylül: birikimli 125.000 - 200.000 < 0 -> 0
  //   Çatı:  birikimli 311.001 - 200.000 = 111.001 -> min(186.001, 111.001) = 111.001
  //   Ekim:  birikimli 436.001 - 200.000 = 236.001 -> min(125.000, 236.001) = 125.000
  //   Açık toplam 236.001 = 436.001 - 200.000; alacak 0.
  {
    name: 'M1 sonradan yazılan ama vadesi eski borç önce kapanır',
    apartment: 'A-5',
    charges: [
      { id: 501, amount: 125000, entry: '2026-09-01', due: '2026-09-05' },
      { id: 502, amount: 125000, entry: '2026-10-01', due: '2026-10-05' },
      { id: 503, amount: 186001, entry: '2026-10-02', due: '2026-09-20' },
    ],
    paid: 200000,
    expected: { remaining: { 501: 0, 503: 111001, 502: 125000 }, order: [501, 503, 502], credit: 0 },
  },
  // M2 (B-1): Eylül ve Ekim aidatı (75.000 + 75.000); ödeme 200.000 -> ikisi de kapanır, artan 200.000 - 150.000 = 50.000 alacak.
  {
    name: 'M2 fazla ödeme alacak olur',
    apartment: 'B-1',
    charges: [
      { id: 511, amount: 75000, entry: '2026-09-01', due: '2026-09-05' },
      { id: 512, amount: 75000, entry: '2026-10-01', due: '2026-10-05' },
    ],
    paid: 200000,
    expected: { remaining: { 511: 0, 512: 0 }, order: [511, 512], credit: 50000 },
  },
  // M3 (B-6): aynı vadeli iki borç (05.10): Ekim aidatı 100.000 (kimlik 601) ve D2'deki B-6 ortak gider payı 42.166 (kimlik 602). Ödeme 120.000.
  //   Vade eşit -> kimlik sırası: 601: 100.000 - 120.000 < 0 -> 0; 602: 142.166 - 120.000 = 22.166 -> min(42.166, 22.166) = 22.166.
  {
    name: 'M3 aynı vadede kayıt sırası',
    apartment: 'B-6',
    charges: [
      { id: 602, amount: 42166, entry: '2026-10-03', due: '2026-10-05' },
      { id: 601, amount: 100000, entry: '2026-10-01', due: '2026-10-05' },
    ],
    paid: 120000,
    expected: { remaining: { 601: 0, 602: 22166 }, order: [601, 602], credit: 0 },
  },
]);

// ------------------------------------------------------------------------------------------------------------------------------------------
// İKİ HESAP (İP-1A, karar G12; docs/PLATFORM_FINANS.md "İki hesap" ve "Altın veri seti"): her dairenin Ev sahibi (owner) ve Kiracı (tenant)
// hesabı vardır; mahsup ve gecikme tazminatı HESAP BAZINDADIR (bir hesabın tahsilatı öteki hesabın borcunu kapatmaz).
// Borcun yazıldığı hesap (finance_parties.accountForCharge): "kim öder" = ev sahibi -> ev sahibi hesabı; "kim öder" = dairede oturan -> dairenin
// borç sorumlusu malik ise ev sahibi hesabı; kiracı ya da "malik ve kiracı" ise borç tarihinde dairede kiracı varsa kiracı hesabı, yoksa ev sahibi.
// Yukarıdaki tek hesaplı senaryolar (D1-D6, L1-L4, M1-M3) dairenin TEK hesabındadır; iki hesaplı kodla da AYNI sonucu verir (test bunu da sınar).
// ------------------------------------------------------------------------------------------------------------------------------------------

/**
 * Dairelerin "kim öder" durumu (elle seçildi; kuralın her dalı en az bir kez):
 *   Daireler      Sorumlu (responsible_party)  Kiracı  Oturanın borcu (aidat)                        Ev sahibine yazılan borç (çatı, demirbaş)
 *   A-1, A-2      tenant                       var     kiracı hesabı                                 ev sahibi hesabı
 *   A-3..A-7      owner                        yok     ev sahibi hesabı (sorumlu malik)              ev sahibi hesabı
 *   A-8..A-10     owner                        var     ev sahibi hesabı (malik aidatı kendisi öder)  ev sahibi hesabı
 *   A-11, A-12    both                         var     kiracı hesabı                                 ev sahibi hesabı
 *   B-1..B-4      tenant                       var     kiracı hesabı                                 ev sahibi hesabı
 *   B-5..B-8      tenant                       yok     ev sahibi hesabı (kiracı yok)                 ev sahibi hesabı
 *   B-9..B-12     both                         yok     ev sahibi hesabı (kiracı yok)                 ev sahibi hesabı
 */
export const ACCOUNT_PROFILE = Object.freeze({
  ...each(A(1, 2), Object.freeze({ responsibleParty: 'tenant', hasTenant: true })),
  ...each(A(3, 7), Object.freeze({ responsibleParty: 'owner', hasTenant: false })),
  ...each(A(8, 10), Object.freeze({ responsibleParty: 'owner', hasTenant: true })),
  ...each(A(11, 12), Object.freeze({ responsibleParty: 'both', hasTenant: true })),
  ...each(B(1, 4), Object.freeze({ responsibleParty: 'tenant', hasTenant: true })),
  ...each(B(5, 8), Object.freeze({ responsibleParty: 'tenant', hasTenant: false })),
  ...each(B(9, 12), Object.freeze({ responsibleParty: 'both', hasTenant: false })),
});

/** Oturanın borcunun hesabı (elle, yukarıdaki tablodan): 8 daire kiracı hesabı, 16 daire ev sahibi hesabı. */
export const OCCUPANT_ACCOUNTS = Object.freeze({
  ...each([...A(1, 2), ...A(11, 12), ...B(1, 4)], 'tenant'),
  ...each([...A(3, 10), ...B(5, 12)], 'owner'),
});

export const TWO_ACCOUNT_DISTRIBUTION_CASES = Object.freeze([
  // İD1: D1 aylık aidatı, "kim öder" = dairede oturan. Dağıtım hesaptan bağımsızdır: tutarlar D1 ile AYNI; her satır oturanın hesabını taşır.
  //   Kiracı hesabına yazılanlar A-1, A-2, A-11, A-12, B-1..B-4: kimlikleri 1, 2, 11, 12, 13..16; D1'de kimlik 1..16 354.167 aldı -> 8 x 354.167 = 2.833.336.
  //   Ev sahibi hesabına: A-3..A-10 (kimlik 3..10) 8 x 354.167 = 2.833.336 + B-5..B-12 (kimlik 17..24) 8 x 354.166 = 2.833.328 -> 5.666.664.
  //   Kontrol: 2.833.336 + 5.666.664 = 8.500.000 (D1 toplamı).
  {
    name: 'İD1 D1 aidatı "dairede oturan": tutarlar D1 ile aynı; kiracı hesabı 8 daire 2.833.336, ev sahibi hesabı 16 daire 5.666.664',
    base: 'D1',
    chargeParty: 'occupant',
    expectedAccounts: OCCUPANT_ACCOUNTS,
    totals: { owner: 5666664, tenant: 2833336 },
  },
  // İD2: D4 çatı yalıtımı (büyük onarım), "kim öder" = ev sahibi: 24 dairenin hepsi ev sahibi hesabı (kiracılı dairelerde de). Toplam D4 ile aynı 3.600.019.
  {
    name: 'İD2 D4 çatı yalıtımı "ev sahibi": 24 daire ev sahibi hesabı, toplam 3.600.019 (kiracılı dairede de kiracıya yazılmaz)',
    base: 'D4',
    chargeParty: 'owner',
    expectedAccounts: each([...A(1, 12), ...B(1, 12)], 'owner'),
    totals: { owner: 3600019, tenant: 0 },
  },
]);

export const TWO_ACCOUNT_LATE_FEE_CASES = Object.freeze([
  // İL1 (B-2, kimlik 14; sorumlu kiracı, kiracı var): ev sahibi hesabında çatı yalıtımı payı 81.000 (D4'teki B-2 payı; "kim öder" ev sahibi;
  //   15.09'da yazıldı, vade 20.09) ödenmedi. Kiracı hesabında Ekim aidatı 75.000 (D5'teki 1+1 tutarı; vade 05.10) kiracı tarafından 03.10'da tam ödendi.
  //   P = Ekim 2026 (31 gün), ek gün 0, oran 500 bp.
  //   İKİ HESAP: ev sahibi hesabı: Ekim'in 31 gününün hepsinde L = 81.000 (vade 20.09 geçti, ödeme yok) -> S = 31 x 81.000 = 2.511.000
  //     daily_30:     (2 x 2.511.000 x 500 + 10.000 x 30) / (20.000 x 30) = 2.511.300.000 / 600.000 = 4.185,5 -> 4.185 (41,85 TL)
  //     daily_actual: (2.511.000.000 + 10.000 x 31) / (20.000 x 31) = 2.511.310.000 / 620.000 = 4.050,5 -> 4.050 (= 81.000 x %5)
  //   kiracı hesabı: aidat vadesinden (05.10) önce ödendi -> hiçbir gün gecikme yok, S = 0 -> tazminat satırı YOK.
  //   KARŞILAŞTIRMA (tek hesap, 052 öncesi gibi): 03.10 ödemesi vadesi en eski çatı payına düşer (kalan 81.000 - 75.000 = 6.000), zamanında ödenen
  //   aidat 06.10'dan itibaren gecikmiş sayılır: 01-02 Ekim 2 x 81.000 = 162.000; 03-05 Ekim 3 x 6.000 = 18.000; 06-31 Ekim 26 x (6.000 + 75.000)
  //   = 2.106.000; S = 2.286.000; daily_30: (2.286.000.000 + 300.000) / 600.000 = 3.810,5 -> 3.810 (kiracının zamanında ödemesine rağmen tazminat).
  {
    name: 'İL1 kiracı aidatı zamanında ödedi, ev sahibinin çatı payı ödenmedi: tazminat YALNIZ ev sahibi hesabına (kiracı hesabında satır yok)',
    apartment: 'B-2',
    apartmentId: 14,
    responsibleParty: 'tenant',
    period: '2026-10',
    graceDays: 0,
    rows: [
      { id: 701, kind: 'charge', amount: 81000, entry: '2026-09-15', due: '2026-09-20', account: 'owner' },
      { id: 702, kind: 'charge', amount: 75000, entry: '2026-10-01', due: '2026-10-05', account: 'tenant' },
      { id: 703, kind: 'payment', amount: -75000, entry: '2026-10-03', account: 'tenant' },
    ],
    expected: {
      owner: {
        daily_30: { base: 2511000, fee: 4185 },
        daily_actual: { base: 2511000, fee: 4050 },
        peak: 81000,
        breakdown: [{ from: '2026-10-01', to: '2026-10-31', overdue: 81000 }],
      },
      tenant: null,
    },
    mixed: {
      daily_30: { base: 2286000, fee: 3810 },
      peak: 81000,
      breakdown: [
        { from: '2026-10-01', to: '2026-10-02', overdue: 81000 },
        { from: '2026-10-03', to: '2026-10-05', overdue: 6000 },
        { from: '2026-10-06', to: '2026-10-31', overdue: 81000 },
      ],
    },
  },
]);

// İL2 (İP-1A x İP-1B; karar G11 + G12; ikinci inceleme): İL1'in AYNI satırları, ama kurallar tablosunda aylık üst sınır
//   (finance.late_fee.monthly_bp_max) 300 bp (%3) ve sitenin saklı oranı 500 bp. Etkin oran = min(saklı 500, kural 300, yasal 500) = 300
//   (finance_settings.loadEffectiveSettings, tazminat açıkken). Tazminat yine YALNIZ ev sahibi hesabına; S değişmez (31 x 81.000 = 2.511.000).
//   daily_30:     (2 x 2.511.000 x 300 + 10.000 x 30) / (20.000 x 30) = (1.506.600.000 + 300.000) / 600.000 = 2.511,5 -> 2.511 (25,11 TL)
//   daily_actual: (2 x 2.511.000 x 300 + 10.000 x 31) / (20.000 x 31) = (1.506.600.000 + 310.000) / 620.000 = 2.430,5 -> 2.430 (= 81.000 x %3)
export const TWO_ACCOUNT_RULE_CAP_CASE = Object.freeze({
  name: 'İL2 kural üst sınırı 300 bp, saklı oran 500 bp: B-2 ev sahibi hesabının tazminatı kırpılmış oranla (%3); kiracı hesabında satır yok',
  base: 'B-2',
  storedRateBp: 500,
  ruleCapBp: 300,
  expected: {
    daily_30: { base: 2511000, fee: 2511 },
    daily_actual: { base: 2511000, fee: 2430 },
  },
});

export const TWO_ACCOUNT_MAHSUP_CASES = Object.freeze([
  // İM1 (B-3; sorumlu kiracı, kiracı var): ev sahibi hesabı: çatı payı 81.000 (vade 20.09; kimlik 711), ödeme yok.
  //   Kiracı hesabı: Eylül aidatı 75.000 (vade 05.09; 712), Ekim aidatı 75.000 (vade 05.10; 713); kiracı toplam 100.000 ödedi.
  //   İKİ HESAP: kiracı: 712 -> 75.000 - 100.000 < 0 -> 0; 713 -> 150.000 - 100.000 = 50.000 -> min(75.000, 50.000) = 50.000; alacak 0.
  //              ev sahibi: 711 -> 81.000 - 0 = 81.000; alacak 0. Kontrol: açık 50.000 + 81.000 = 231.000 - 100.000.
  //   KARŞILAŞTIRMA (tek hesap): vade sırası 712 (05.09), 711 (20.09), 713 (05.10): 712 -> 0; 711 -> 156.000 - 100.000 = 56.000;
  //   713 -> 231.000 - 100.000 = 131.000 -> min(75.000, 131.000) = 75.000: kiracının 25.000'i ev sahibinin borcunu kapatırdı.
  {
    name: 'İM1 kiracının ödemesi yalnız kiracı hesabının borcunu kapatır (ev sahibinin çatı payı açık kalır)',
    apartment: 'B-3',
    charges: [
      { id: 711, amount: 81000, entry: '2026-09-15', due: '2026-09-20', account: 'owner' },
      { id: 712, amount: 75000, entry: '2026-09-01', due: '2026-09-05', account: 'tenant' },
      { id: 713, amount: 75000, entry: '2026-10-01', due: '2026-10-05', account: 'tenant' },
    ],
    paid: { owner: 0, tenant: 100000 },
    expected: {
      owner: { order: [711], remaining: { 711: 81000 }, credit: 0 },
      tenant: { order: [712, 713], remaining: { 712: 0, 713: 50000 }, credit: 0 },
    },
    mixed: { order: [712, 711, 713], remaining: { 712: 0, 711: 56000, 713: 75000 }, credit: 0 },
  },
]);
