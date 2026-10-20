# Tasarım Dili: "Cilalı Safir" Premium

Bu belge arayüzün modern/premium görünümünün **kurallarını ve bileşenlerini** anlatır. Yeni bir ekran ya
da bileşen yazarken önce buraya bakın; kod örnekleri `lib/ui/design/` altındadır.

> Kısa özet: **derinlik** (cila, aura, gölge) + **canlılık** (olay-güdümlü, sonlu animasyon) +
> **okunaklılık** (ölçülmüş kontrast) + **hız** (kararlı durumda sıfır ticker).
>
> **İki stil (G6 kararına kadar):** **Panel (modül vitrini)** işverenin "sade" stilindedir (komutlar.txt): düz beyaz
> kart + ince çerçeve, gölge ve cila YOK, koyu renk yalnız eylem isteyen yerde, renkler 5 değişkenden
> (`AppShowcaseColors`). Uygulamanın geri kalanı "Cilalı Safir"dir (derinlik: cila, aura, gölge). Bu belgedeki
> "derinlik / gölge" kuralları (`AppCard` gölgesi, cila) Panel vitrinine uygulanmaz; vitrin kuralları §3 "Panel"
> bölümündedir. İkisi çelişmez: vitrin bilinçli istisnadır, G6 kararıyla tüm uygulama tek stile geçebilir.

## 1. Değişmez sözleşmeler

Bunlar testlerle kilitlidir; bozan değişiklik testi kırar.

| Sözleşme | Anlamı | Hakem |
|---|---|---|
| **Taşma yok** | 320/360/412/820 dp × yazı ölçeği 1,0/1,5/2,0 × açık/koyu | `test/design/*` taşma matrisleri, `AGENTS.md` kural 6 |
| **Kararlı durumda ticker yok** | Boştayken hiçbir animasyon çalışmaz (`pumpAndSettle` biter, pil harcanmaz) | `transientCallbackCount == 0` testleri |
| **Hareket azaltma** | `MediaQuery.disableAnimations` açıkken efektler yok, geçişler anında | `AppMotion.of/reduced` |
| **Kontrast** | Metin ≥ 4,5:1, ikon/grafik ≥ 3:1 (cila dahil, gerçek piksel ölçümü) | `contrast_test.dart`, `gloss_test.dart` |
| **Dokunma hedefi** | ≥ 44 dp (tercihen 48) | bileşen testleri |
| **Pahalı efekt yok** | `BackdropFilter`, `Opacity` ile büyük alan, `ShaderMask`, `ImageFiltered`, çift gölge, blur > 16 yasak | `gloss_test.dart` ve bileşen testleri |
| **Anlamsal ağaç** | Her etkileşimli öğe tek düğüm, etiket görünen metindir; süs katmanları dışlanır | Semantics testleri |

## 2. Hareket sözlüğü

Süre ve eğriler `AppMotion` (tokens.dart): `fast` 120 ms, `base` 200 ms, `slow` 320 ms;
`enter` easeOutCubic, `standard` fastOutSlowIn. Hepsi `AppMotion.of(context, d)` üzerinden geçer.

**Canlılık olaylarla gelir, sürekli döngüyle değil.** İzin verilen animasyon türleri:

1. **Basış geri bildirimi**: `PressableScale` (ölçek 0,96-0,97, 120 ms).
2. **Giriş**: `StaggeredEntry` (ilk 8 öğe), `PageEntry`, `Pop` (belirginleşme).
3. **Durum değişimi**: renk/zemin morph 200 ms (`AnimatedContainer`/`TweenAnimationBuilder`).
4. **Olay efekti (sonlu, ≤ 900 ms)**: halka dalgası, ışıltı süpürmesi, kıvılcım patlaması.
5. **İşlevsel gösterge**: yalnız iş sürerken dönen (spinner, sonar halkaları); iş bitince durur.
6. **Bounded dikkat**: `StatusChip.pulse` gibi N tur atıp duran vurgu.

**Yasak**: boştayken sonsuza dek dönen/nefes alan efekt, ekran açılışında kendiliğinden başlayan
süs animasyonu (sayfa girişi zaten var).

## 3. Bileşenler

### `Gloss` (`gloss.dart`): cilalı yüzey katmanı
Bir yüzeyin ÜSTÜNE dört ince katman bindirir: sol-üst hacim ışığı, alt gölge, kenar ışığı, özel parıltı
(daire) ya da üst cila (dikdörtgen). Tek `CustomPaint` + `RepaintBoundary`; durağanken yeniden
boyanmaz. İsteğe bağlı `sweep` (0→1) tek seferlik ışıltı süpürmesi çizer. Yüksek karşıtlık modunda
kapanır. `Stack` içinde `Positioned.fill(child: Gloss(...))` olarak kullanılır; içerik ve mürekkep
dalgası cilanın ÜSTÜNDE durur. **Şiddet kalibre edilmiştir**: etiket bölgesi ≥ 4,5:1, ikon bölgesi ≥ 3:1.

`glossyButtonLayer`: aynı katmanın `ButtonStyle.backgroundBuilder` biçimi. `AppTheme` bunu
`ElevatedButton` ve `FilledButton` stillerine bağlar: **tüm standart dolu düğmeler otomatik cilalıdır**
(devre dışı düğme düz kalır). `OutlinedButton`/`TextButton` bilerek düzdür (hiyerarşi).

### `DoorOpenButton` (`door_open_button.dart`): kapıyı aç
Cilalı yuvarlak (132-184 dp) ya da çubuk düğme; dört durum (`ready/opening/offline/disabled`).
Yüzeyin altında renkli **aura**; olaylar:

| Olay | Efekt |
|---|---|
| Basış (`ready`) | çift halka dalgası (520 ms) + ölçek 0,96 + orta haptik |
| Komut sürüyor (`opening`) | sonar halkaları (yalnız sürerken döner) + merkezde spinner |
| Başarı (`successTick` artar) | success tonuna morph, onay işareti, ışıltı süpürmesi, patlama halkası, sekiz kıvılcım (900 ms) |
| Cihaz yeniden hazır (`offline/disabled → ready`) | ışıltı + yumuşak halka |
| `offline` dokunuşu | yatay titreme + `onBlocked` |

Çubuk varyantında halka yerine ışıltı süpürmesi oynar. Hareket azaltmada hiçbir efekt çalışmaz.

### `IconOrb` (`icon_orb.dart`): ikon rozeti
Düz renkli ikon kutularının yerine: ton gradyanı + cila + beyaz ikon (+ isteğe bağlı `glow`).
`size` ≥ 24, ikon boyutun yarısı; `shape`: daire ya da squircle. Dekoratiftir (anlamsal ağaçta yok);
tek başına anlam taşıyorsa `semanticLabel` verin. Listelerde onlarca rozet olabileceğinden cila katmansız
çizilir (`Gloss.isolate: false`).

### `PrimaryActionButton` (`buttons.dart`)
`filled` görünüm cilalıdır; `success` true olunca üzerinden tek seferlik ışıltı geçer. `tonal` ve
`outline` ikincil eylemdir, düz kalır.

### `AppCard` (`app_card.dart`)
Opak Material yüzey + tek katman gölge korunur. Üstüne: koyu temada cam gibi üst ışık; `level ≥ 2`
(hero) kartlarda tonun sol-üst yıkaması; `accentBar` altında ışık sızıntısı. Statik gradyanlardır.

### Kendiliğinden premium olan ortak bileşenler
- `AppDialog` başlığı: `IconOrb` (44 squircle, glow). `EmptyState`: 72 dp glow'lu daire rozet (kompakt: 44).
- `StatusChip`: `pulse` noktası parlayan LED (3 tur nabız atıp durur). `AppSnack`: simge cam daire rozette.
- Tema (`AppTheme`): `ElevatedButton`/`FilledButton` cilalı; ilerleme göstergeleri yuvarlak uçlu; açılır menü,
  ipucu ve alt sayfa yuvarlatılmış/koyu yumuşak; sayfa zemininde ikinci, çok hafif mor ışıma (sol-alt).
- Ana sayfa başlığı: rol tonlu hafif gradyan + 34 dp avatar rozeti (yükseklik bütçesi değişmez).

### Kapı açma kartları (yuvarlak cilalı düğme hero'dur)
| Kart | Düzen |
|---|---|
| `ResidentDoorRemoteCard` (daire sakini) | hero kart (level 2), ortada 132-184 dp düğme |
| `AdminDoorStatusCard` (yönetici/süper) | durum bandı + ortada 132-184 dp düğme, altta misafir/QR eylemleri |
| `IndividualDoorCard` (bireysel) | geniş kartta solda 116 dp düğme + sağda bilgi; dar kart ya da yazı > 1,3x ise üstte ortalı |

**Sade daire kullanıcısı ekranı** (`ResidentDoorRemoteCard(minimal: true)`, yalnız `UserRole.apartmentOwner`): açıklama, rozet, IP, saat ve ek düğme YOKTUR; yalnız kapı seçici (ya da tek kapı adı) + yuvarlak düğme. Kaldırılan komutlar `YanMenu.extraActions` ile çekmecede "Kapılar"ın (o yoksa "Panel"in) altında toplanır (`Sesli Kapı Açma`, `Kapıya QR Göster`, `Kapı Ekranından QR Oku`, `Kurye / Misafir Geçiş Linki Oluştur`; yetki/cihaz yoksa görünmez). Mantık `ResidentDoorActions` yardımcısındadır (kart ve çekmece aynısını çağırır).

Etiketler büyük harf ve kısadır (`KAPI AÇ`, `KAPIYI AÇ`, `UZAKTAN AÇ`, `YEREL AĞDAN AÇ`, `ÇEVRİMDIŞI`;
açılırken `AÇILIYOR`, başarıda `GÖNDERİLDİ`). e2e testleri metni `foldText` (küçük harf + aksansız) ile
karşılaştırdığından büyük harf güvenlidir; YÖNETİCİ etiketi bilerek `KAPI AÇ`tır (katlanmış hâli
`kapi ac`, eski "Kapı Aç" ile aynı).

### Panel: modül vitrini (`module_showcase_view.dart`, `helpers/module_showcase.dart`)
Girişten sonra açılan **Panel** kapı paneli değil, kullanıcıya tanımlı modüllerin kart vitrinidir (kapı paneli "Kapılar" kartının arkasındadır, bir dokunuş).
- **Tek kaynak**: kartlar `YanMenu.visibleItems` (çekmecenin hesapladığı öğe listesi) çıktısından türer; görünürlük kuralı vitrinde kopyalanmaz. Kapalı / yetkisiz modülün kartı hiçbir koşulda çizilmez (fail-closed); modül sonradan kapanınca kart da kalkar.
- **Kart**: `ModuleArt(kind: ...)` görseli (`moduleArtKindFor`: bilinmeyen öğe `generic`) + menüdeki başlık + tek satır açıklama + varsa rozet (çekmecedeki sayılar; durum noktası + sayı). Etiket = başlık + rozet, ipucu = açıklama; dokunma çekmecede öğeyi seçmekle aynı gezinmedir.
- **İkincil satır kuralı**: hesap / ayar / sistem öğeleri (`showcaseSecondaryItems`: Profilim, Eller Serbest, Bluetooth ile Wi-Fi Kur, Denetim Kaydı, Platform Ayarları, İstemci Hataları) ızgarada kart olmaz, altta küçük "Hesap ve ayarlar" düğmeleri olarak durur (+ "Yardım ve Destek").
- **Kitle** (`showcaseAudience`):
  - yönetici / süper kullanıcı: üstte koyu "Dikkat edilmesi gereken N iş var" barı, altında ızgara. Bar YALNIZ çekmecedeki bekleyen / okunmamış sayılar > 0 iken çıkar (yeni veri kaynağı yok; satır başına tek düğme). **Bugün yönetim tarafındaki bu sayılar yalnız süper kullanıcıda vardır** (bekleyen modül talepleri, site başvuruları). Yönetici modundaki site yöneticisinde çekmecede rozet olmadığından bar **hiç çıkmaz**; yönetici için (yeni arıza talepleri, karar bekleyen rezervasyonlar, onay bekleyen dekontlar) tek bir sunucu sayaç ucu gerekir, henüz yazılmadı.
  - sakin / kurul / görevli: üstte tek kart ("Güncel borcunuz" + "Borcum'a git", Borcum açık ve borç bilgisi alınabildiyse; yoksa selamlama; bilgi yokken ASLA "borç yok" denmez), altında hızlı işlemler (Kapıyı aç, Arıza bildir, Ziyaretçi ve kargo, Belgeler; yalnız modülü açık olanlar).
  - bireysel: yalnız ızgara.
- **Görünüm** (renkler `AppShowcaseColors`, tokens.dart): açık temada sayfa zemini DÜZ #F8FAFC (yalnız vitrin; uygulamanın genel gradyan zemini değişmez, gradyanın alt tonu kart çerçevesiyle aynı olduğundan vitrinde kullanılmaz), kart saf beyaz + ince #E2E8F0 çerçeve, gölge yok, normal metin #475569. Koyu renk (#0F172A) YALNIZ eylem isteyen yerde: ödenecek borç varken sakin kartı, yöneticide dikkat barı ve ana düğmeler. Selamlama, "Borcunuz yok", "Alacağınız" ve "borç bilgisi alınamadı" hâli düz beyaz karttır (ana düğmesi koyu hap). Koyu temada odak kutusu zeminden ayrışan lacivert (#172554) + 1,5 dp mavi kenar (zemine ve kutuya ≥ 3:1). Durum noktaları #10B981 / #F59E0B / #E11D48 (arka planı boyamaz; anlam yanındaki metindedir). Izgara 2 sütun (telefon; 320 dp telefonda da yazı 1,0-1,15'te iki sütun, gerçek genişlik 288 dp), 3-4 sütun (geniş), büyük yazıda sütun azalır (`showcaseColumns`); satırdaki kartlar eşit yükseklikte, rozet sığmazsa görselin altına iner; hareket azaltmada giriş animasyonu yok.
- **Erişilebilirlik**: hap düğmeler ve "Hesap ve ayarlar" düğmeleri en az 48 dp; hap düğmede klavye odağı iki temada görünür (2 dp dışında 2 dp halka, yanındaki yüzeye ≥ 3:1). Borç kartının ekran okuyucu etiketi görünen TÜM satırları okur (site / daire, tutar, vadesi geçen, sıradaki vade, alacak; tutarlar `moneySemanticLabel` ile "üç bin iki yüz elli lira"); "Borcum'a git" ayrı düğmedir. Dikkat barı düğmesinin adı satırın bağlamlı etiketidir ("2 bekleyen site başvurusu. İncele"): birden çok "İncele" birbirinden ayrılır, satır metni ikinci kez okunmaz.
- **Kapı güvenliği**: vitrinde kapı AÇILMAZ (kazara dokunuşla kapı açılmasın); "Kapıyı aç" hızlı eylemi Kapılar sayfasına götürür, kapı açma mantığı değişmedi. Geçiş Kontrol kapalıyken `SirketMenuItem.kapilar` gizlenir: kart ve hızlı eylem de yoktur. Durum yoklaması yalnız Kapılar sayfasındayken çalışır.
- Geri tuşu bir modül sayfasından Panel vitrinine döner (`PopScope`); vitrindeyken uygulamadan çıkar.

## 4. Ekran reçeteleri

- **Liste ekranı**: başlık `SectionHeader` (+ sayaç), öğeler `AppCard`, öğe başına `IconOrb` +
  `StatusChip`, ilk 8 öğe `StaggeredEntry`, yüklenirken `Skeleton`, boşken `EmptyState`.
- **Eylem**: birincil `PrimaryActionButton(filled)`, ikincil `tonal`; kapı açma her zaman `DoorOpenButton`.
- **Diyalog**: `AppDialog(icon, tone)`; iptal `TextButton`, onay dolu düğme.
- **Geri bildirim**: `AppSnack`, formlarda `InlineNotice`.
- **Renk**: yalnız `AppTone` / `AppPalette` (metin için `tone.ink(palette)`); Panel vitrini `AppShowcaseColors`
  (beyaz etiket için 5 renk değişkeni: zemin, kart + kenar, metin, odak, durum noktaları). Düz hex yazmayın.

## 5. Ne yapılmaz

- Yeni `fontSize` literali (tipografi ölçeği `Theme.of(context).textTheme`).
- Sabit genişlik/yükseklikli metin kutusu; dinamik metin daima `Flexible`/`Expanded`/`maxLines`.
- Sonsuz `AnimationController.repeat()` (iş sürerken dönen gösterge hariç).
- `BackdropFilter`, büyük alan `Opacity`, `ShaderMask`.
