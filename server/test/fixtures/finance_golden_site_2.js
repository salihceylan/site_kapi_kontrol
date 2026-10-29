// ALTIN VERİ SETİ 2 (Dalga B finans kuralları; docs/PLATFORM_FINANS.md "Altın veri seti 2"). Birinci set (finance_golden_site.js) dağıtım / gecikme / mahsup
// çekirdeğini sınar; bu set Dalga B'nin KURALLARINI küçük bir sitede uçtan uca sınar: eşit dışı dağıtım tabanları (kategori, daire başı sabit, arsa payı),
// kiracı borcunun malike devri + geri alma (K1), gecikmede devir önerisi ve "kiracı vermezse malik öder" (K17), onaylı alacak iadesi (K4), alacaklı
// açılış bakiyesi (K16) ve bunların gecikme tazminatına etkisi.
//
// BEKLENEN DEĞERLERİN HİÇBİRİ KOD ÇALIŞTIRILARAK ÜRETİLMEDİ: hepsi aşağıdaki yorumlarda elle hesaplandı. Sapma çıkarsa önce buradaki elle hesap iki kez
// yeniden yapılır; hesap doğruysa hata raporlanır, hesap kodu fikstüre uydurulmaz.
//
// SAF VERİ: içe aktarma yok (saf test, gerçek PostgreSQL betiği ve demo tohumu aynı kaynağı kullanır). PARA kuruştur (tamsayı).
// SABİT SAAT: bütün servis çağrıları `now = GOLDEN2_CLOCK.nowIso` ile yapılır; defter tarihleri mutlaktır. Böylece sonuçlar çalıştırma gününden BAĞIMSIZDIR.
//
// SİTE: 1 blok ("A Blok"), 6 daire, karma malik / kiracı.
//
//   Daire  Kategori  Arsa payı  Oturan      Aidat hesabı (oturan)
//   A-1    1+1       12/100     malik       Ev sahibi
//   A-2    2+1       14/100     kiracı      Kiracı  (malik dışarıda; sorumlu = kiracı)
//   A-3    2+1       16/100     malik       Ev sahibi
//   A-4    3+1       18/100     kiracı      Kiracı
//   A-5    3+1       20/100     malik       Ev sahibi
//   A-6    3+1       20/100     kiracı      Kiracı
//
// TANIMLAR (üç farklı dağıtım tabanı; "eşit" bilerek yok, o birinci sette):
//   Aylık Aidat        aylık, KATEGORİ: 1+1 = 120.000, 2+1 = 150.000, 3+1 = 180.000; vade günü 5; dönemler 2026-09 ve 2026-10; kim öder = oturan.
//                      Dönem toplamı = 120.000 + 2 x 150.000 + 3 x 180.000 = 960.000.
//   Asansör Bakım Payı tek seferlik, DAİRE BAŞI SABİT 25.000 (toplam 150.000); kim öder = oturan; vade 2026-11-10 (GELECEK: devredilmez, gecikmez).
//   Çatı Onarımı       tek seferlik, ARSA PAYI, toplam 1.000.003 (10.000,03 TL); kim öder = ev sahibi (Fon); vade 2026-11-20 (GELECEK).
//        pay = taban(1.000.003 x w / 100), w = arsa payı payı (ortak payda 100):
//          A-1 12 -> 12.000.036 / 100 = 120.000 kalan 36;  A-2 14 -> 14.000.042 / 100 = 140.000 kalan 42;  A-3 16 -> 16.000.048 / 100 = 160.000 kalan 48;
//          A-4 18 -> 18.000.054 / 100 = 180.000 kalan 54;  A-5 20 -> 20.000.060 / 100 = 200.000 kalan 60;  A-6 20 -> 200.000 kalan 60.
//          taban toplamı = 120 + 140 + 160 + 180 + 200 + 200 = 1.000.000 -> artan 3 kuruş; en büyük kalanlar: A-5 (60), A-6 (60), A-4 (54)
//          (A-5 / A-6 eşit kalanda kimliği küçük önce; ikisi de alır) -> A-4 180.001, A-5 200.001, A-6 200.001. Toplam 1.000.003. Kuruş artığı kiracılı daireye de
//          gider (A-4, A-6): çatı HER ZAMAN ev sahibi hesabındadır.
//
// SAAT: 2026-10-20 (GOLDEN2_CLOCK). Devir alacağı (K16): A-5 için 2026-09-01'de -500,00 TL (= -50.000 kuruş), ev sahibi hesabı, vadesiz.
//
// ÖDEMELER (tarih, hesap, tutar):
//   A-1 ev sahibi  Kasa  09-04  120.000  ve  10-04  120.000       (aidatlar vadesinden ÖNCE)
//   A-2 kiracı     Kasa  09-20  200.000                           (Eylül 150.000 tam + Ekim'e 50.000)
//   A-3 ev sahibi  Kasa  10-10  600.000                           (borcun 115.000 FAZLASI: alacak)
//   A-4 kiracı     -     hiç ödemedi
//   A-5 ev sahibi  Kasa  10-08  400.000
//   A-6 kiracı     Kasa  09-05  180.000  ve  10-05  180.000       (vadesinde)
//   A-4 ev sahibi  Banka 10-20  360.000 (İşletme) + 180.001 (Fon)  (devirden SONRA, aşağıda; hesap seçimi K3 zorunlu: iki türde de açık borç var)
//
// SIRA (gerçek takvim): devir alacağı -> iki aylık aidat -> ödemeler (09-04 .. 10-10) -> asansör ve çatı (tek seferlik borç YALNIZ bugünün tarihiyle yazılır: 10-20)
// -> adaylar -> A-2 devir + geri alma -> A-4 devir (+ eksik hesap seçimi 400, bayat toplam 409) + malik ödemesi -> A-3 iade -> gecikme tazminatı planı.
// Ödemeler çatıdan ÖNCE geldiği için hesap seçimi gerektirmez (yalnız İşletme borcu açık); A-3 ve A-5'in fazlası genel avans olur, sonra gelen asansör / çatı borçlarını
// vade sırasıyla kapatır (M1 ile aynı sonuç).
//
// ÖZET: ayrıntılı elle hesaplar GOLDEN2_EXPECTED içindedir.

export const GOLDEN2_CLOCK = Object.freeze({ nowIso: '2026-10-20T09:00:00+03:00', today: '2026-10-20' });
export const GOLDEN2_SITE_NAME = 'Altın Veri Sitesi 2';
export const GOLDEN2_BLOCK = 'A Blok';

/** tenant: dairede güncel kiracı var; responsible: apartments.responsible_party (kiracılı dairelerde 'tenant' -> oturanın borcu kiracı hesabına). */
export const GOLDEN2_APARTMENTS = Object.freeze([
  { label: 'A-1', unit: '1', category: '1+1', land: [12, 100], responsible: 'both', tenant: false },
  { label: 'A-2', unit: '2', category: '2+1', land: [14, 100], responsible: 'tenant', tenant: true },
  { label: 'A-3', unit: '3', category: '2+1', land: [16, 100], responsible: 'both', tenant: false },
  { label: 'A-4', unit: '4', category: '3+1', land: [18, 100], responsible: 'tenant', tenant: true },
  { label: 'A-5', unit: '5', category: '3+1', land: [20, 100], responsible: 'both', tenant: false },
  { label: 'A-6', unit: '6', category: '3+1', land: [20, 100], responsible: 'tenant', tenant: true },
]);
export const GOLDEN2_LABELS = Object.freeze(GOLDEN2_APARTMENTS.map((apt) => apt.label));

export const GOLDEN2_ACCOUNTS = Object.freeze([
  { key: 'kasa', name: 'Kasa', kind: 'cash', openingDate: '2026-09-01', openingBalanceMinor: 0 },
  { key: 'banka', name: 'Banka', kind: 'bank', openingDate: '2026-09-01', openingBalanceMinor: 0 },
]);

/** Devir alacağı (K16): Excel hücresi "-500,00" -> -50.000 kuruş; yalnız A-5. */
export const GOLDEN2_OPENING = Object.freeze({ cutoverDate: '2026-09-01', rows: [{ apartment: 'A-5', cell: '-500,00', minor: -50000 }] });

export const GOLDEN2_DEFINITIONS = Object.freeze({
  aidat: {
    name: 'Aylık Aidat',
    kind: 'recurring',
    distribution: 'category',
    categoryAmounts: { '1+1': 120000, '2+1': 150000, '3+1': 180000 },
    dueDay: 5,
    startPeriod: '2026-09',
    periods: ['2026-09', '2026-10'],
  },
  asansor: { name: 'Asansör Bakım Payı', distribution: 'fixed', amountMinor: 25000, chargeParty: 'occupant', dueDate: '2026-11-10' },
  cati: {
    name: 'Çatı Onarımı',
    distribution: 'land_share',
    amountMinor: 1000003,
    chargeParty: 'owner',
    dueDate: '2026-11-20',
    decisionReason: 'Genel kurul kararı (altın veri seti 2)',
  },
});

/** account: 'kasa' | 'banka'; party: ödemenin yazıldığı hesap (owner | tenant); method: cash | transfer. */
export const GOLDEN2_PAYMENTS = Object.freeze([
  { id: 'P1', apartment: 'A-1', party: 'owner', account: 'kasa', date: '2026-09-04', amountMinor: 120000, method: 'cash' },
  { id: 'P2', apartment: 'A-6', party: 'tenant', account: 'kasa', date: '2026-09-05', amountMinor: 180000, method: 'cash' },
  { id: 'P3', apartment: 'A-2', party: 'tenant', account: 'kasa', date: '2026-09-20', amountMinor: 200000, method: 'cash' },
  { id: 'P4', apartment: 'A-1', party: 'owner', account: 'kasa', date: '2026-10-04', amountMinor: 120000, method: 'cash' },
  { id: 'P5', apartment: 'A-6', party: 'tenant', account: 'kasa', date: '2026-10-05', amountMinor: 180000, method: 'cash' },
  { id: 'P6', apartment: 'A-5', party: 'owner', account: 'kasa', date: '2026-10-08', amountMinor: 400000, method: 'cash' },
  { id: 'P7', apartment: 'A-3', party: 'owner', account: 'kasa', date: '2026-10-10', amountMinor: 600000, method: 'cash' },
]);
/**
 * A-4 malikinin devirden sonraki ödemeleri (Banka, havale): devredilen 360.000 (İşletme: devir kasayı korur) + kendi çatı payı 180.001 (Fon). İki türün de açık borcu olduğundan
 * hesap seçimi ZORUNLUDUR (K3): seçimsiz ilk deneme 400 FUND_CHOICE_REQUIRED (açık: işletme 360.000, fon 180.001); sonra her ödeme kendi hesabına yazılır.
 */
export const GOLDEN2_OWNER_PAYMENTS_A4 = Object.freeze([
  { id: 'P8a', apartment: 'A-4', party: 'owner', account: 'banka', date: '2026-10-20', amountMinor: 360000, method: 'transfer', fund: 'operating' },
  { id: 'P8b', apartment: 'A-4', party: 'owner', account: 'banka', date: '2026-10-20', amountMinor: 180001, method: 'transfer', fund: 'capital' },
]);
export const GOLDEN2_OWNER_PAYMENT_A4_TOTAL = GOLDEN2_OWNER_PAYMENTS_A4.reduce((acc, payment) => acc + payment.amountMinor, 0);

/** Gecikme tazminatı planı (Ekim 2026): oran 500 bp, daily_30, ek gün 0 (finance_settings anahtarlarıyla). */
export const GOLDEN2_LATE_FEE_SETTINGS = Object.freeze({
  period: '2026-10-01',
  settings: { late_fee_rate_bp: 500, late_fee_method: 'daily_30', late_fee_grace_days: 0, settings_version: 1 },
});

const byLabel = (entries) => Object.freeze(Object.fromEntries(entries));
const balances = (owner, tenant) => Object.freeze({ owner: byLabel(owner), tenant: byLabel(tenant) });

// ----------------------------------------------------------------------------------------------------------------------------------------------------
// BEKLENEN DEĞERLER (elle hesap)
// ----------------------------------------------------------------------------------------------------------------------------------------------------
//
// DAĞITIM / HESAP / KASA (her borçlandırmada daire -> { tutar, hesap, kasa }): kasa = 'operating' (aidat, asansör: oturan), 'capital' (çatı: ev sahibi Fon).
//
// BAKİYE 1 (devir alacağı + 2 aidat dönemi; ödemeden ÖNCE), hesap bazında:
//   Ev sahibi hesabı: A-1 2 x 120.000 = 240.000;  A-3 2 x 150.000 = 300.000;  A-5 2 x 180.000 - devir alacağı 50.000 = 310.000;  A-2, A-4, A-6 (kiracılı) = 0
//   Kiracı hesabı:    A-2 2 x 150.000 = 300.000;  A-4 2 x 180.000 = 360.000;  A-6 360.000;  A-1, A-3, A-5 kiracı yok = 0
//   Toplam = 850.000 + 1.020.000 = 1.870.000 = aidat 1.920.000 - devir alacağı 50.000.
//
// BAKİYE 2 (ödemelerden sonra, asansör ve çatıdan ÖNCE):
//   Ev sahibi: A-1 240.000 - 240.000 = 0;  A-3 300.000 - 600.000 = -300.000 (alacak);  A-5 310.000 - 400.000 = -90.000 (alacak);  diğerleri 0
//   Kiracı:    A-2 300.000 - 200.000 = 100.000;  A-4 360.000;  A-6 360.000 - 360.000 = 0
//
// BAKİYE 3 (asansör daire başı 25.000 -> oturanın hesabı; çatı -> ev sahibi hesabı; devirden ÖNCE):
//   Ev sahibi: A-1 0 + 25.000 + 120.000 = 145.000;  A-2 0 + 140.000 = 140.000;  A-3 -300.000 + 25.000 + 160.000 = -115.000;  A-4 0 + 180.001 = 180.001;
//              A-5 -90.000 + 25.000 + 200.001 = 135.001;  A-6 0 + 200.001 = 200.001
//   Kiracı:    A-2 100.000 + 25.000 = 125.000;  A-4 360.000 + 25.000 = 385.000;  A-6 0 + 25.000 = 25.000
//   Toplam = 685.003 + 535.000 = 1.220.003 ; kimlik: aidat 1.920.000 + asansör 150.000 + çatı 1.000.003 - devir alacağı 50.000 - ödemeler 1.800.000 = 1.220.003.
//
// MAHSUP (M1, vadesi en eski borçtan; ödemeler + devir alacağı alacak toplamıdır):
//   A-2 kiracı: ödeme 200.000: Eylül (vade 09-05) 150.000 -> 0 (kalan 50.000); Ekim (vade 10-05) 150.000 - 50.000 = 100.000 açık; asansör (11-10) 25.000 açık.
//   A-5 ev sahibi: alacak = devir alacağı 50.000 + ödeme 400.000 = 450.000: Eylül 180.000 -> 0 (270.000 kalır); Ekim 180.000 -> 0 (90.000 kalır);
//       asansör 25.000 -> 0 (65.000 kalır); çatı 200.001 - 65.000 = 135.001 açık. DEVİR ALACAĞI OLMASAYDI alacak 400.000: Eylül 0, Ekim 0 (40.000), asansör 0 (15.000),
//       çatı 200.001 - 15.000 = 185.001 açık (alacağın fazlası kadar 50.000 fark).
//
// K17 ADAYLARI (saat 2026-10-20; aday = kiracı hesabında vadesi bugün ve öncesi, M1 sonrası kalanı > 0, tazminat/iade olmayan kalem):
//   A-2: yalnız Ekim aidatı (kalan 100.000, vade 10-05; Eylül tam ödendi; asansör vadesi gelecek)  -> 1 kalem, 100.000, en eski vade 2026-10-05
//   A-4: Eylül 180.000 (vade 09-05) + Ekim 180.000 (10-05), hiç ödenmemiş                           -> 2 kalem, 360.000, en eski vade 2026-09-05
//   A-6: kiracı vadesinde ödedi; yalnız gelecek vadeli asansör açık (25.000) -> aday DEĞİL ("pozitif bakiye = gecikmiş" değildir)
//   A-1, A-3, A-5: kiracı yok -> aday değil.  Sıra: büyük tutar önce (A-4, A-2); toplam 460.000.
//
// A-2 DEVİR (100.000): kiracı hesabında Ekim aidatının (150.000) TERSİ -150.000; ödenmiş kısım için AYNI vadeyle yeni borç +50.000; ev sahibinde yeni borç +100.000.
//   Kiracı 125.000 - 100.000 = 25.000 (asansör); ev sahibi 140.000 + 100.000 = 240.000. Geri alma: ev sahibinde -100.000 ters, kiracıda ödenmiş kısım borcu ters -50.000,
//   kiracıya TAM tutar +150.000 yeniden yazılır -> kiracı 25.000 + 100.000 = 125.000, ev sahibi 140.000 (devirden önceki değerler). Defterde 3 + 3 = 6 devir satırı KALIR.
// A-4 DEVİR (360.000): kiracıda iki ters (-180.000 x 2), ödenmiş kısım yok, ev sahibinde iki yeni borç (+180.000 x 2). Kiracı 385.000 - 360.000 = 25.000;
//   ev sahibi 180.001 + 360.000 = 540.001. Ev sahibi 540.001 öder -> 0. Sonra geri alma 409 LIABILITY_TRANSFER_OWNER_PAID (ev sahibi devir borcunu ödedi).
//
// A-3 İADE: alacak = 115.000. 120.000 talebi alacağı aşar (409 REFUND_EXCEEDS_CREDIT). 100.000 iade onayı: ev sahibi hesabı -115.000 + 100.000 = -15.000 (kalan alacak
//   15.000); Kasa'dan 100.000 ÇIKIŞ: Kasa = tahsilatlar 240.000 + 200.000 + 600.000 + 400.000 + 360.000 = 1.800.000 - 100.000 = 1.700.000; Banka 540.001.
//
// GECİKME TAZMİNATI (Ekim 2026, 31 gün, oran 500 bp, daily_30 D = 30, ek gün 0; fee = taban((2 x S x 500 + 10.000 x 30) / (20.000 x 30)) = taban(S / 600 + 0,5)):
//   Kural: bir kalem max(vade, kayıt günü) gününü İZLEYEN günden başlayarak gecikir; ters kaydı olan kalem ters kayıt gününden itibaren sayılmaz.
//   A-1 ev sahibi: Ekim aidatı 10-04'te ödendi (vade 10-05): S = 0.
//   A-2 kiracı (devir + geri alma SONRASI): 10-01..10-05 gecikmiş tutar 0 (Eylül tam ödenmiş; Ekim vadesi 10-05 henüz geçmedi); 10-06..10-19 (14 gün) Ekim kalanı 100.000
//        -> 1.400.000. 10-20'de Ekim aidatı ters kayıtlanır ve yeniden yazılır (kayıt günü 10-20): yeni kalem 10-20'yi İZLEYEN günden gecikir; 10-20 günü hiçbir kalem
//        gecikmiş sayılmaz; 10-21..10-31 (11 gün) 100.000 -> 1.100.000. S = 2.500.000 -> 2.500.000 / 600 = 4.166,67 + 0,5 = 4.167,17 -> 4.167.
//        (Devir hiç yapılmasaydı: 26 gün x 100.000 = 2.600.000 -> 4.333,33 + 0,5 -> 4.333. Devir + geri alma 10-20 gününü tabandan düşürür: 100.000 x 1 gün.)
//   A-3 ev sahibi: ödeme 10-10. 10-01..10-05 (5 gün) Eylül 150.000 gecikmiş -> 750.000; 10-06..10-09 (4 gün) Eylül 150.000 + Ekim 150.000 -> 4 x 300.000 = 1.200.000.
//        10-10'dan sonra ödeme 600.000 tüm borcu kapatır. S = 1.950.000 -> 3.250,00 + 0,5 = 3.250,5 -> 3.250.
//   A-4 kiracı (devirden SONRA): 10-01..10-05 (5 gün) Eylül 180.000 -> 900.000; 10-06..10-19 (14 gün) 360.000 -> 5.040.000; 10-20'de iki kalem ters kayıtlanır:
//        sonrası 0. S = 5.940.000 -> 9.900,00 + 0,5 = 9.900,5 -> 9.900.  (Devir olmasaydı 57 gün x 180.000 = 10.260.000 -> 17.100.)
//   A-4 ev sahibi: devredilen kalemler 10-20'de yazıldı ve aynı gün 540.001 ödendi: S = 0 (tazminat satırı yok).
//   A-5 ev sahibi (devir alacağı VAR): alacak 10-01..10-07: 50.000, 10-08'den: 450.000. 10-01..10-05 (5 gün) Eylül açık 130.000 -> 650.000; 10-06 ve 10-07 (2 gün) Eylül 130.000
//        + Ekim 180.000 = 310.000 -> 620.000; 10-08'den sonra 0. S = 1.270.000 -> 2.116,67 + 0,5 = 2.117,17 -> 2.117.
//        (Devir alacağı olmasaydı: 5 x 180.000 + 2 x 360.000 = 1.620.000 -> 2.700,00 + 0,5 -> 2.700.)
//   A-6: kiracı vadesinde ödedi, ev sahibinin çatı borcu gelecek vadeli: S = 0.
//   Satırlar: A-2 kiracı 4.167, A-3 ev sahibi 3.250, A-4 kiracı 9.900, A-5 ev sahibi 2.117; toplam 19.434.
//
// SON DURUM (tüm adımlardan sonra): bkz. final.
export const GOLDEN2_EXPECTED = Object.freeze({
  runs: {
    'Aylık Aidat 2026-09': {
      total_minor: 960000,
      apartment_count: 6,
      rows: byLabel([
        ['A-1', { amount: 120000, account: 'owner', fund: 'operating' }],
        ['A-2', { amount: 150000, account: 'tenant', fund: 'operating' }],
        ['A-3', { amount: 150000, account: 'owner', fund: 'operating' }],
        ['A-4', { amount: 180000, account: 'tenant', fund: 'operating' }],
        ['A-5', { amount: 180000, account: 'owner', fund: 'operating' }],
        ['A-6', { amount: 180000, account: 'tenant', fund: 'operating' }],
      ]),
    },
    'Aylık Aidat 2026-10': {
      total_minor: 960000,
      apartment_count: 6,
      rows: byLabel([
        ['A-1', { amount: 120000, account: 'owner', fund: 'operating' }],
        ['A-2', { amount: 150000, account: 'tenant', fund: 'operating' }],
        ['A-3', { amount: 150000, account: 'owner', fund: 'operating' }],
        ['A-4', { amount: 180000, account: 'tenant', fund: 'operating' }],
        ['A-5', { amount: 180000, account: 'owner', fund: 'operating' }],
        ['A-6', { amount: 180000, account: 'tenant', fund: 'operating' }],
      ]),
    },
    'Asansör Bakım Payı': {
      total_minor: 150000,
      apartment_count: 6,
      rows: byLabel([
        ['A-1', { amount: 25000, account: 'owner', fund: 'operating' }],
        ['A-2', { amount: 25000, account: 'tenant', fund: 'operating' }],
        ['A-3', { amount: 25000, account: 'owner', fund: 'operating' }],
        ['A-4', { amount: 25000, account: 'tenant', fund: 'operating' }],
        ['A-5', { amount: 25000, account: 'owner', fund: 'operating' }],
        ['A-6', { amount: 25000, account: 'tenant', fund: 'operating' }],
      ]),
    },
    'Çatı Onarımı': {
      total_minor: 1000003,
      apartment_count: 6,
      rows: byLabel([
        ['A-1', { amount: 120000, account: 'owner', fund: 'capital' }],
        ['A-2', { amount: 140000, account: 'owner', fund: 'capital' }],
        ['A-3', { amount: 160000, account: 'owner', fund: 'capital' }],
        ['A-4', { amount: 180001, account: 'owner', fund: 'capital' }],
        ['A-5', { amount: 200001, account: 'owner', fund: 'capital' }],
        ['A-6', { amount: 200001, account: 'owner', fund: 'capital' }],
      ]),
    },
  },
  opening: { rowCount: 1, creditTotalMinor: 50000, entry: { apartment: 'A-5', kind: 'payment', amount: -50000, account: 'owner', source: 'opening', due: null } },
  balancesAfterAidat: balances(
    [['A-1', 240000], ['A-2', 0], ['A-3', 300000], ['A-4', 0], ['A-5', 310000], ['A-6', 0]],
    [['A-1', 0], ['A-2', 300000], ['A-3', 0], ['A-4', 360000], ['A-5', 0], ['A-6', 360000]],
  ),
  balancesAfterPayments: balances(
    [['A-1', 0], ['A-2', 0], ['A-3', -300000], ['A-4', 0], ['A-5', -90000], ['A-6', 0]],
    [['A-1', 0], ['A-2', 100000], ['A-3', 0], ['A-4', 360000], ['A-5', 0], ['A-6', 0]],
  ),
  balancesAfterOneTime: balances(
    [['A-1', 145000], ['A-2', 140000], ['A-3', -115000], ['A-4', 180001], ['A-5', 135001], ['A-6', 200001]],
    [['A-1', 0], ['A-2', 125000], ['A-3', 0], ['A-4', 385000], ['A-5', 0], ['A-6', 25000]],
  ),
  // [ad, vade, M1 sonrası kalan]; vade sırasıyla
  openItems: {
    'A-2 tenant': [['Aylık Aidat', '2026-09-05', 0], ['Aylık Aidat', '2026-10-05', 100000], ['Asansör Bakım Payı', '2026-11-10', 25000]],
    'A-5 owner': [['Aylık Aidat', '2026-09-05', 0], ['Aylık Aidat', '2026-10-05', 0], ['Asansör Bakım Payı', '2026-11-10', 0], ['Çatı Onarımı', '2026-11-20', 135001]],
    'A-5 owner (devir alacağı olmasaydı)': [['Aylık Aidat', '2026-09-05', 0], ['Aylık Aidat', '2026-10-05', 0], ['Asansör Bakım Payı', '2026-11-10', 0], ['Çatı Onarımı', '2026-11-20', 185001]],
  },
  candidatesBefore: {
    count: 2,
    total_minor: 460000,
    truncated: false,
    items: [
      { apartment: 'A-4', reason: 'overdue', tenant_present: true, has_owner: true, can_transfer: true, item_count: 2, total_minor: 360000, oldest_due_date: '2026-09-05' },
      { apartment: 'A-2', reason: 'overdue', tenant_present: true, has_owner: true, can_transfer: true, item_count: 1, total_minor: 100000, oldest_due_date: '2026-10-05' },
    ],
  },
  attentionBefore: { count: 2, total_minor: 460000 },
  a2: {
    preview: {
      has_owner: true,
      can_transfer: true,
      item_count: 1,
      total_minor: 100000,
      tenant_balance_minor: 125000,
      owner_balance_minor: 140000,
      items: [{ name: 'Aylık Aidat', due_date: '2026-10-05', original_minor: 150000, remaining_minor: 100000, paid_minor: 50000, fund: 'operating' }],
    },
    afterTransfer: {
      tenant: 25000,
      owner: 240000,
      writtenRows: 3,
      sums: { 'owner charge': 100000, 'tenant charge': 50000, 'tenant reversal': -150000 },
      candidates: [{ apartment: 'A-4', total_minor: 360000 }],
      reversible: true,
    },
    afterReverse: {
      tenant: 125000,
      owner: 140000,
      writtenRows: 6,
      sums: { 'owner charge': 100000, 'owner reversal': -100000, 'tenant charge': 200000, 'tenant reversal': -200000 },
      candidates: [{ apartment: 'A-4', total_minor: 360000 }, { apartment: 'A-2', total_minor: 100000 }],
      transferReversible: false,
    },
    reverseTwice: { status: 409, code: 'LIABILITY_TRANSFER_ALREADY_REVERSED' },
  },
  a4: {
    preview: {
      has_owner: true,
      can_transfer: true,
      item_count: 2,
      total_minor: 360000,
      tenant_balance_minor: 385000,
      owner_balance_minor: 180001,
      items: [
        { name: 'Aylık Aidat', due_date: '2026-09-05', original_minor: 180000, remaining_minor: 180000, paid_minor: 0, fund: 'operating' },
        { name: 'Aylık Aidat', due_date: '2026-10-05', original_minor: 180000, remaining_minor: 180000, paid_minor: 0, fund: 'operating' },
      ],
    },
    staleTotal: { status: 409, code: 'LIABILITY_TRANSFER_CHANGED' },
    // K3: devirden sonra ev sahibi hesabında İşletme (devredilen 360.000) VE Fon (çatı 180.001) borcu birlikte açık: seçimsiz ödeme reddedilir, hiçbir satır yazılmaz
    fundChoice: { status: 400, code: 'FUND_CHOICE_REQUIRED', open: { operating_minor: 360000, capital_minor: 180001 }, balanceUnchanged: 540001 },
    afterTransfer: {
      tenant: 25000,
      owner: 540001,
      writtenRows: 4,
      sums: { 'owner charge': 360000, 'tenant reversal': -360000 },
      candidates: [{ apartment: 'A-2', total_minor: 100000 }],
    },
    afterOwnerPayment: { tenant: 25000, owner: 0 },
    reverseBlocked: { status: 409, code: 'LIABILITY_TRANSFER_OWNER_PAID' },
    afterBlockedReverse: { tenant: 25000, owner: 0 },
  },
  attentionAfter: { count: 1, total_minor: 100000 },
  refund: {
    credit_before_minor: 115000,
    tooMuch: { status: 409, code: 'REFUND_EXCEEDS_CREDIT' },
    approved: { status: 'approved', amount_minor: 100000, method: 'cash', account: 'Kasa', receiptSeq: 1 },
    ownerBalanceAfter: -15000,
    creditAfter: 15000,
    approveTwice: { status: 409, code: 'REFUND_NOT_PENDING' },
    accountBalances: { Kasa: 1700000, Banka: 540001 },
  },
  lateFee: {
    total_minor: 19434,
    lines: [
      { apartment: 'A-2', account: 'tenant', base_day: 2500000, amount: 4167 },
      { apartment: 'A-3', account: 'owner', base_day: 1950000, amount: 3250 },
      { apartment: 'A-4', account: 'tenant', base_day: 5940000, amount: 9900 },
      { apartment: 'A-5', account: 'owner', base_day: 1270000, amount: 2117 },
    ],
  },
  final: {
    balances: balances(
      [['A-1', 145000], ['A-2', 140000], ['A-3', -15000], ['A-4', 0], ['A-5', 135001], ['A-6', 200001]],
      [['A-1', 0], ['A-2', 125000], ['A-3', 0], ['A-4', 25000], ['A-5', 0], ['A-6', 25000]],
    ),
    totals: { owner: 605002, tenant: 175000, all: 780002 },
    ledgerIdentity: { charged_minor: 3170003, credited_minor: 2390001, transfer_net_minor: 0 },
    // Kasa değişmezi (İşletme + Fon + avans = hesaplar toplamı):
    //   Fon (çatı) tahsilatı: A-3 çatı 160.000 (genel avanstan) + A-4 çatı 180.001 (P8b) + A-5 çatı 65.000 (genel avanstan: 90.000 - asansör 25.000) = 405.001
    //   (A-1, A-2, A-6 çatı payları ödenmedi). Devir alacağı tahsilat DEĞİLDİR (hesaba para girmedi).
    //   İşletme tahsilatı = gerçek tahsilatlar 2.340.001 - Fon 405.001 - iade 100.000 (avansı tüketir, kasaya tahsilat yazmaz) - kalan avans 15.000 = 1.820.000
    //   (kontrol: işletme borcu 1.920.000 + 150.000 = 2.070.000; ödenmemiş 200.000 = A-1 asansör 25.000 + A-2 Ekim 100.000 + asansör 25.000 + A-4 asansör 25.000 + A-6 asansör
    //    25.000; ödenen 1.870.000 = tahsilat 1.820.000 + devir alacağı 50.000)
    //   Hesaplar toplamı = Kasa 1.700.000 + Banka 540.001 = 2.240.001 = 1.820.000 + 405.001 + 15.000.
    funds: { operating_collections_minor: 1820000, capital_collections_minor: 405001, advance_minor: 15000, accounts_total_minor: 2240001, balanced: true },
  },
});
// Kimlik (son durum): kaynağı devir OLMAYAN borç satırları (aidat 1.920.000 + asansör 150.000 + çatı 1.000.003 + iade 100.000) = 3.170.003; alacak satırları (ödemeler
// 120.000 + 180.000 + 200.000 + 120.000 + 180.000 + 400.000 + 600.000 = 1.800.000, A-4 malikinin 540.001'i, devir alacağı 50.000) = 2.390.001; fark 780.002 = son durum toplamı.
// Devir ve geri alma satırlarının (source_kind = 'liability_transfer'; ters kayıtlar dahil) toplamı 0'dır: iki hesabın toplamı hiç değişmez.

// ----------------------------------------------------------------------------------------------------------------------------------------------------
// SAF TEST SATIRLARI (veritabanı yok): defterin DB'de nasıl durması gerektiğinin elle yazılmış hali. Tutarlar kuruş, tarihler mutlak.
// Biçim finance_golden_dataset.test.js'in `calcRows` girdisiyle aynıdır: { id, kind, amount, entry, due, lateFee, reversesId?, name, fund }.
// ----------------------------------------------------------------------------------------------------------------------------------------------------
const aidatRow = (id, amount, period) => ({ id, kind: 'charge', amount, entry: `${period}-01`, due: `${period}-05`, name: 'Aylık Aidat', fund: 'operating' });

export const GOLDEN2_PURE = Object.freeze({
  // A-2 kiracı hesabı, devir ÖNCESİ (ödemeden sonra)
  a2TenantBefore: [
    aidatRow(201, 150000, '2026-09'),
    aidatRow(202, 150000, '2026-10'),
    { id: 203, kind: 'charge', amount: 25000, entry: '2026-10-20', due: '2026-11-10', name: 'Asansör Bakım Payı', fund: 'operating' },
    { id: 204, kind: 'payment', amount: -200000, entry: '2026-09-20', due: null },
  ],
  // A-2 kiracı hesabı, devir + geri alma SONRASI (DB'de kalan tüm satırlar): 205 = devrin yazdığı "ödenmiş kısım" borcu, 206 = onun tersi (geri alma), 207 = TAM tutarlı yeni borç,
  // 208 = Ekim aidatının tersi (devir)
  a2TenantAfter: [
    aidatRow(201, 150000, '2026-09'),
    aidatRow(202, 150000, '2026-10'),
    { id: 203, kind: 'charge', amount: 25000, entry: '2026-10-20', due: '2026-11-10', name: 'Asansör Bakım Payı', fund: 'operating' },
    { id: 204, kind: 'payment', amount: -200000, entry: '2026-09-20', due: null },
    { id: 208, kind: 'reversal', amount: -150000, entry: '2026-10-20', due: null, reversesId: 202 },
    { id: 205, kind: 'charge', amount: 50000, entry: '2026-10-20', due: '2026-10-05', name: 'Aylık Aidat', fund: 'operating' },
    { id: 206, kind: 'reversal', amount: -50000, entry: '2026-10-20', due: null, reversesId: 205 },
    { id: 207, kind: 'charge', amount: 150000, entry: '2026-10-20', due: '2026-10-05', name: 'Aylık Aidat', fund: 'operating' },
  ],
  // A-4 kiracı hesabı, devir ÖNCESİ / SONRASI
  a4TenantBefore: [
    aidatRow(401, 180000, '2026-09'),
    aidatRow(402, 180000, '2026-10'),
    { id: 403, kind: 'charge', amount: 25000, entry: '2026-10-20', due: '2026-11-10', name: 'Asansör Bakım Payı', fund: 'operating' },
  ],
  a4TenantAfter: [
    aidatRow(401, 180000, '2026-09'),
    aidatRow(402, 180000, '2026-10'),
    { id: 403, kind: 'charge', amount: 25000, entry: '2026-10-20', due: '2026-11-10', name: 'Asansör Bakım Payı', fund: 'operating' },
    { id: 404, kind: 'reversal', amount: -180000, entry: '2026-10-20', due: null, reversesId: 401 },
    { id: 405, kind: 'reversal', amount: -180000, entry: '2026-10-20', due: null, reversesId: 402 },
  ],
  // A-4 ev sahibi hesabı, devirden sonra: çatı + devredilen iki kalem (kayıt günü 10-20, ORİJİNAL vade) + aynı gün ödeme
  a4OwnerAfter: [
    { id: 410, kind: 'charge', amount: 180001, entry: '2026-10-20', due: '2026-11-20', name: 'Çatı Onarımı', fund: 'capital' },
    { id: 406, kind: 'charge', amount: 180000, entry: '2026-10-20', due: '2026-09-05', name: 'Aylık Aidat', fund: 'operating' },
    { id: 407, kind: 'charge', amount: 180000, entry: '2026-10-20', due: '2026-10-05', name: 'Aylık Aidat', fund: 'operating' },
    { id: 411, kind: 'payment', amount: -540001, entry: '2026-10-20', due: null },
  ],
  // A-5 ev sahibi: devir alacağı (payment, vadesiz) + ödeme; "alacaksız" karşılaştırma için alacak satırı çıkarılabilir (id 501)
  a5Owner: [
    { id: 501, kind: 'payment', amount: -50000, entry: '2026-09-01', due: null },
    aidatRow(502, 180000, '2026-09'),
    aidatRow(503, 180000, '2026-10'),
    { id: 504, kind: 'charge', amount: 25000, entry: '2026-10-20', due: '2026-11-10', name: 'Asansör Bakım Payı', fund: 'operating' },
    { id: 505, kind: 'charge', amount: 200001, entry: '2026-10-20', due: '2026-11-20', name: 'Çatı Onarımı', fund: 'capital' },
    { id: 506, kind: 'payment', amount: -400000, entry: '2026-10-08', due: null },
  ],
  a5CreditId: 501,
  // A-3 ev sahibi (iade): borçlar + 600.000 ödeme; iade onayı 10-20'de "iade" kaynaklı borç satırı yazar
  a3Owner: [
    aidatRow(301, 150000, '2026-09'),
    aidatRow(302, 150000, '2026-10'),
    { id: 303, kind: 'charge', amount: 25000, entry: '2026-10-20', due: '2026-11-10', name: 'Asansör Bakım Payı', fund: 'operating' },
    { id: 304, kind: 'charge', amount: 160000, entry: '2026-10-20', due: '2026-11-20', name: 'Çatı Onarımı', fund: 'capital' },
    { id: 305, kind: 'payment', amount: -600000, entry: '2026-10-10', due: null },
  ],
  a3Refund: { id: 306, kind: 'charge', amount: 100000, entry: '2026-10-20', due: '2026-10-20', name: 'Alacak iadesi', fund: null, sourceKind: 'refund' },
});

// PURE beklentiler (elle; yukarıdaki yorumlarla aynı):
export const GOLDEN2_PURE_EXPECTED = Object.freeze({
  // gecikme tazminatı, Ekim 2026, daily_30, ek gün 0: S (kuruş x gün) ve tazminat
  lateFee: {
    a2TenantBefore: { base: 2600000, fee: 4333, peak: 100000 },
    a2TenantAfter: { base: 2500000, fee: 4167, peak: 100000 },
    a4TenantBefore: { base: 10260000, fee: 17100, peak: 360000 },
    a4TenantAfter: { base: 5940000, fee: 9900, peak: 360000 },
    a4OwnerAfter: { base: 0, fee: 0, peak: 0 },
    a5OwnerWithCredit: { base: 1270000, fee: 2117, peak: 310000 },
    a5OwnerWithoutCredit: { base: 1620000, fee: 2700, peak: 360000 },
    a3Owner: { base: 1950000, fee: 3250, peak: 300000 },
  },
  // devir planı (devredilebilir kalem kimlikleri ve kalanlar), saat 2026-10-20
  transferPlan: {
    a2TenantBefore: { total: 100000, items: [{ entryId: 202, remaining: 100000, paid: 50000, original: 150000, due: '2026-10-05' }] },
    a4TenantBefore: {
      total: 360000,
      items: [
        { entryId: 401, remaining: 180000, paid: 0, original: 180000, due: '2026-09-05' },
        { entryId: 402, remaining: 180000, paid: 0, original: 180000, due: '2026-10-05' },
      ],
    },
    a4TenantAfter: { total: 0, items: [] },
    // devirden sonra A-2 kiracı: 207 (TAM tutar, vade 10-05) yeniden aday; kalan 100.000 (200.000 ödeme önce Eylül 150.000'i, kalan 50.000 yeni Ekim kalemini kapatır)
    a2TenantAfter: { total: 100000, items: [{ entryId: 207, remaining: 100000, paid: 50000, original: 150000, due: '2026-10-05' }] },
  },
  // devir yazma planı
  transferWrites: {
    a2: { reversals: [202], tenantCharges: [{ entryId: 202, amountMinor: 50000 }], ownerCharges: [{ entryId: 202, amountMinor: 100000 }] },
    a4: { reversals: [401, 402], tenantCharges: [], ownerCharges: [{ entryId: 401, amountMinor: 180000 }, { entryId: 402, amountMinor: 180000 }] },
  },
});
