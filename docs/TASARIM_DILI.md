# Tasarım Dili: Sade (karar G6 + G7)

Bu belge arayüzün görünüm **kurallarını ve bileşenlerini** anlatır. Yeni bir ekran ya da bileşen yazarken önce buraya
bakın; kod `lib/ui/design/` (bileşenler), `lib/ui/design/tokens.dart` (değerler) ve `lib/styles/app_theme.dart` (tema)
altındadır.

> Kısa özet (İP-1C, 2026-10-21): **%90 beyaz**: düz #F8FAFC zemin, beyaz kart + ince #E2E8F0 çerçeve, gölge yok.
> **Koyu #0F172A yalnız ana onay düğmesinde ve kritik uyarıda**, düz (cila, degrade, gölge yok). Durum **metnin
> solunda küçük nokta** (● #10B981 / #F59E0B / #E11D48); zemin boyanmaz. **Mavi yalnız bağlantı ve odak halkasında.**
> Koyu tema erişilebilirlik için kalır. **Kapı düğmesi bilinçli istisnadır**: görünüşü ve davranışı değişmedi.
>
> Kaynak: `docs/PLATFORM_YOL_HARITASI.md` → "Karar kaydı (2026-10-21)" G6, G7 (işverenin `komutlar.txt` Kural 1, renk
> tablosu, talimat 3). Önceki "Cilalı Safir" stilinin cila, aura, gölge ve ışıması sayfa içeriğinden kalktı; değişiklik
> tema ve bileşen düzeyindedir (ekran ekran renk yamalanmadı, ekran akışları ve yerleşim aynı).

## 1. Renkler (`AppPalette`, `context.palette`)

Açık temanın değerleri beyaz etiketin değişkenleridir (`AppShowcaseColors`: zemin, kart + kenar, metin, odak, durum
noktaları); `AppPalette.light` bunlardan okunur (tek kaynak, `test/design/sade_style_test.dart`). Düz hex yazmayın:
yalnız palet alanları ve `AppTone`.

| Alan | Açık | Koyu | Kullanım |
| --- | --- | --- | --- |
| `background` | #F8FAFC | #0F172A | Sayfa zemini: DÜZ renk, ışıma yok (`AppDecorations.pageBackground*`, uygulama kabuğu) |
| `surface` | #FFFFFF | #1E293B | Kart, diyalog, girdi, ikincil düğme zemini |
| `surfaceMuted` | #F1F5F9 | #0F172A | İç kutu, ikon rozeti, sayaç hapı, bilgi çipi |
| `border` | #E2E8F0 | beyaz %14 | Kart çerçevesi, ayırıcı, ikincil düğme çerçevesi |
| `text` | #0F172A | #F8FAFC | Başlık; ikincil ve metin düğmesinin metni |
| `textSecondary` | #475569 | #CBD5E1 | Gövde metni (varsayılan `bodyMedium`) ve "normal" ikon rengi |
| `textMuted` | #5F6F85 | #94A3B8 | Etiket, ipucu |
| `action` / `onAction` | #0F172A / #F8FAFC | #F8FAFC / #0F172A | Ana onay düğmesi ve üstündeki metin |
| `critical` / `onCritical` / `criticalBorder` | #0F172A / #F8FAFC / #1E293B | #172554 / #F8FAFC / #3B82F6 | Kritik uyarı kutusu (dikkat barı, ödenecek borç) |
| `link`, `focusRing` | #1D4ED8 | #93C5FD | Bağlantı metni ve klavye odak halkası (mavi yalnız burada; tek istisna koyu temada kritik kutunun kenarı, vitrin kararı: koyu zeminde kutuyu ayıran tek öğe) |
| `statusOk` / `statusWarn` / `statusCrit` | #10B981 / #F59E0B / #E11D48 | aynı | Durum noktaları |

**Koyu temada ana düğme** açık zemin + koyu metindir (#F8FAFC + #0F172A, 17,06:1): koyu sayfada en yüksek karşıtlık
(sayfaya 17,06:1, karta 13,98:1). Mavi (#2563EB, beyaz metinle 5,17:1) seçenek olarak elendi: mavi yalnız bağlantı ve
odakta kalır.

**Tehlike tonu** (`AppTone.danger`) mercan ailesidir: hue = dolgu = #E11D48, dolgu sonu ve açık ink #BE123C,
koyu ink #FDA4AF. **Durum tonu kuralı** (`AppTone.isStatus`): yalnız `success`, `warning`, `danger` renkli işaret
taşır (`AppTone.dot` nokta rengi, `AppTone.sign(p)` simge rengi); `primary`, `info`, `violet`, `neutral` nötrdür
(nokta #64748B, simge gövde metni rengi).

## 2. Kontrast tablosu (ölçüm)

WCAG 2.x oranı, Flutter `computeLuminance` ile aynı formül. Satırları `test/design/sade_style_test.dart` (metin,
bağlantı, odak, ana düğme, kritik kutu, kritik nokta, simge rengi) ve bileşen testleri (`status_dot_test`, `icon_orb_test`,
`app_snack_test`, `contrast_test`) denetler. Eşik: metin >= 4,5:1; düğme sınırı, odak halkası, ikon ve durum noktası >= 3:1.

**Açık tema**

| Ön plan / zemin | Oran |
| --- | --- |
| Başlık #0F172A / kart #FFFFFF · sayfa #F8FAFC | 17,85:1 · 17,06:1 |
| Gövde #475569 / kart · sayfa · soluk yüzey #F1F5F9 | 7,58:1 · 7,24:1 · 6,92:1 |
| Etiket #5F6F85 / kart · sayfa · soluk yüzey | 5,12:1 · 4,90:1 · 4,68:1 |
| Ana düğme metni #F8FAFC / ana düğme #0F172A | 17,06:1 |
| Ana düğme #0F172A / sayfa · kart (sınır) | 17,06:1 · 17,85:1 |
| İkincil düğme metni #0F172A / beyaz | 17,85:1 |
| İkincil düğme ve kart çerçevesi #E2E8F0 / beyaz · sayfa | 1,23:1 · 1,18:1 (çerçeve süstür: düğmeyi metni, kartı içeriği tanıtır) |
| Bağlantı ve odak halkası #1D4ED8 / kart · sayfa · soluk yüzey | 6,70:1 · 6,41:1 · 6,12:1 |
| Seçili kart kenarı #0F172A / kart | 17,85:1 |
| Kritik kutu metni #F8FAFC / #0F172A · kutu / sayfa | 17,06:1 · 17,06:1 |
| Nokta tamam #10B981 / kart | 2,54:1 → 1 dp kenar #047857: 5,48:1 |
| Nokta bekliyor #F59E0B / kart | 2,15:1 → 1 dp kenar #B45309: 5,02:1 |
| Nokta kritik #E11D48 / kart · soluk yüzey | 4,70:1 · 4,29:1 |
| Nötr nokta #64748B / kart | 4,76:1 |
| Beyaz / tehlike dolgusu #E11D48 · #BE123C | 4,70:1 · 6,29:1 |
| Tehlike metni #BE123C / kart · soluk yüzey | 6,29:1 · 5,74:1 |
| İkon rozeti: gövde #475569 · tehlike #BE123C · uyarı #92400E · tamam #065F46 / soluk yüzey | 6,92 · 5,74 · 6,47 · 7,01:1 |
| Girdi: odak kenarı #1D4ED8 · hata kenarı #E11D48 / beyaz | 6,70:1 · 4,70:1 |
| Bildirim çubuğu: beyaz metin / #0F172A | 17,85:1 |
| Bildirim simgeleri tamam #6EE7B7 · uyarı #FCD34D · hata #FDA4AF / #0F172A | 11,71 · 12,38 · 9,44:1 |

**Koyu tema**

| Ön plan / zemin | Oran |
| --- | --- |
| Başlık #F8FAFC / kart #1E293B · sayfa #0F172A | 13,98:1 · 17,06:1 |
| Gövde #CBD5E1 / kart · sayfa | 9,85:1 · 12,02:1 |
| Etiket #94A3B8 / kart · kart seviye 3 · sayfa | 5,71:1 · 4,76:1 · 6,96:1 |
| Ana düğme metni #0F172A / ana düğme #F8FAFC | 17,06:1 |
| Ana düğme #F8FAFC / sayfa · kart (sınır) | 17,06:1 · 13,98:1 |
| İkincil düğme metni / kart | 13,98:1 |
| Bağlantı ve odak halkası #93C5FD / kart · sayfa · girdi | 8,11:1 · 9,90:1 · 8,30:1 |
| Seçili kart kenarı #F8FAFC / kart | 13,98:1 |
| Kritik kutu metni #F8FAFC / #172554 · kenar #3B82F6 / kutu · sayfa | 14,04:1 · 4,00:1 · 4,85:1 |
| Nokta tamam · bekliyor · kritik / kart | 5,77 · 6,81 · 3,11:1 |
| Nokta kritik / sayfa · nötr nokta / kart · sayfa | 3,80:1 · 3,07:1 · 3,75:1 |
| Tehlike metni #FDA4AF / kart · kart + %16 ton | 7,74:1 · 7,13:1 |
| Girdi hata kenarı #E11D48 / girdi zemini | 3,19:1 |
| Bildirim simgeleri tamam · uyarı · hata / #1E293B | 9,60 · 10,15 · 7,74:1 |

## 3. Düğmeler

| Tür | Bileşen | Görünüm |
| --- | --- | --- |
| Ana onay | `ElevatedButton`, `FilledButton` (tema), `PrimaryActionButton(filled)`, `filledToneStyle(context)` | `action` zemin + `onAction` metin; düz: yükselti 0, gölge yok, cila / degrade yok. Kart ya da sayfa başına bir tane |
| Durum tonlu dolu | `PrimaryActionButton(filled, tone: danger/success/warning)`, `filledToneStyle(tone: …)` | Tonun `a` rengi + beyaz metin (ör. "Sil" #E11D48). Öteki tonlar (birincil, bilgi, mor) ana eylem rengidir: mavi dolu düğme yok |
| İkincil | `OutlinedButton` (tema), `PrimaryActionButton(tonal)`, `tonalActionStyle(context)`, `dialogTonalButtonStyle(context)` | Yüzey zemin + 1 px `border` + `text` (durum tonunda tonun `ink` rengi) |
| İkincil, zeminsiz | `PrimaryActionButton(outline)` | Yalnız 1 px `border` + metin |
| Yıkıcı ikincil | `dangerOutlineStyle(context)` | Tehlike `ink` metin + tehlike kenarı (%50) |
| Metin düğmesi | `TextButton` (tema; "Vazgeç", "Kapat", "İptal") | `text` renginde, zeminsiz |
| Devre dışı | hepsi | Soluk nötr zemin + ikincil metin (tıklanmaz) |

`PrimaryActionButton` durumları aynıdır: basılı (ölçek 0,97), yükleniyor (spinner, etiket ağaçta yok), başarı (zemin
200 ms'de başarı tonuna döner + onay işareti; cila süpürmesi kalktı). Dokunma hedefi >= 48 dp. Dalga ve vurgu rengi
düğmenin metin rengindedir (koyu temada açık zeminde de görünür).

## 4. Kartlar ve yüzeyler

- **`AppCard`**: `surfaceAt(level)` + 1 px `border`, GÖLGESİZ; cam ışığı, ton yıkaması ve şerit sızıntısı yoktur. Seviye
  (`level`) yalnız koyu temada yüzeyi bir kademe açar. `accentBar` 3 dp düz şerit olarak kalır. Seçili kart: 1,5 px
  `action` kenarı (mavi değil). `tone` verilirse zemin BOYANMAZ; durum tonlarında kenar tonun %50'si.
- **Tema kartı** (`Card`): yüzey + 1 px kenar, yükselti 0. `AppDecorations.glassCard / infoCard`: aynı, gölgesiz.
- **Sayfa zemini**: düz `background`; uygulama kabuğunda (`lib/app.dart`) ve tam ekran kapılarda aynı sabit.
- **Yüzen katmanlar** (diyalog, alt sayfa, açılır menü, bildirim çubuğu, ipucu) yükseltisini KORUR: sayfa içeriği
  değildir; açılır menü altındaki içerikten ancak gölgeyle ayrılır. Diyaloglar karartılmış perde üstündedir.
- **İkon rozeti** (`IconOrb`): `surfaceMuted` + 1 px `border` + ikon `AppTone.sign(p)` (durum tonunda `ink`, ötekinde
  gövde metni). Degrade, cila ve parıltı yok; `glow` parametresi geriye uyum için durur, etkisizdir.
- **Bölüm başlığı sayacı** (`SectionHeader.count`): nötr hap (`surfaceMuted` + gövde metni).

## 5. Durum gösterimi

- **`StatusDot`** (`lib/ui/design/status_dot.dart`, sözleşme 2.3): metnin solunda 8 dp nokta + metin (`bodySmall`
  kalın, gövde metni rengi); zemin ve çerçeve BOYANMAZ. Nokta rengi `AppTone.dot`: tamam #10B981, bekliyor #F59E0B,
  kritik #E11D48, öteki tonlar nötr gri #64748B. Açık temada noktası yüzeye 3:1'i tutmayan tonlarda (tamam 2,54:1,
  bekliyor 2,15:1) 1 dp koyu kenar (`StatusDot.edgeOf`: tonun `a` rengi) noktanın sınırını seçtirir; renk işverenin
  rengidir, anlam metindedir. Yeni ekranlar (dalga 2 ve sonrası) durum için bunu kullanır.
- **`StatusChip`**: aynı API, varsayılan görünümü `StatusDot`'tur; `icon` verilirse nokta yerine 14 dp ikon
  (`AppTone.sign`); `pulse` (3 tur nabız, sonra durur) kalır, LED parıltısı kalktı.
- **Vitrin rozeti ile uyum**: kritik durum noktası #E11D48 = `AppTone.danger.hue` = `AppTone.danger.a`. Panel vitrininde
  kart rozetinin noktası ve çekmecedeki sayı rozetinin dolgusu (vitrin kararı) `AppTone.danger.a`'dır: bekleyen /
  okunmamış sayısı çekmecede, Panel'de ve kritik durum noktasında aynı mercan renktir. Vitrinin öteki noktaları (borç
  kartı, dikkat barı) `AppShowcaseColors` renkleridir (aynı değerler).
- **`InfoChip`**: nötr kutu (`surfaceMuted` + kenar); ton yalnız metni renklendirir (`AppTone.sign`).
- **Büyük diyalog parçaları** (`lib/ui/dialogs/large_dialog_parts.dart`; finans ekranları da kullanır): `DialogMetaPill`
  `InfoChip` ile aynıdır (nötr kutu, ton yalnız metin ve simgede); `DialogPanel` zemini her tonda `surfaceMuted`, durum
  tonlarında yalnız kenar tonun %40'ı (bilgi / birincil / mor panel boyanmaz). `InitialAvatar` (`list_parts.dart`)
  `IconOrb` gibidir: `surfaceMuted` + kenar, harf `AppTone.sign`.
- **`InlineNotice`**: opak yüzey (zemin boyanmaz); durum tonlarında kenar tonun %40'ı ve ikon + metin `ink`, bilgi gibi
  öteki tonlarda palet kenarı + gövde metni.
- **`AppSnack`**: her tür tek koyu yüzeyde (tema: açıkta #0F172A, koyuda #1E293B + ince kenar); tür, simgesi ve simgenin
  rengiyle ayrılır (tamam #6EE7B7, uyarı #FCD34D, hata #FDA4AF, bilgi beyaz). Eylem rengi temadan (bağlantı mavisi).

## 6. Değişmez sözleşmeler

Bunlar testlerle kilitlidir; bozan değişiklik testi kırar.

| Sözleşme | Anlamı | Hakem |
| --- | --- | --- |
| **Sade stil** | Palet alanları, kontrast tablosu, düz tema düğmeleri, gölgesiz kart, düz zemin | `sade_style_test.dart`, `contrast_test.dart`, `app_shell_test.dart`, bileşen testleri |
| **Kapı düğmesi aynı** | `DoorOpenButton` görünüşü 4d754cf ile aynı (değer + Windows'ta piksel) | `door_open_button_unchanged_test.dart` (+ `goldens/`), davranış `door_open_button_test.dart` |
| **Taşma yok** | 320/360/412/820 dp × yazı ölçeği 1,0/1,5/2,0 × açık/koyu | `test/design/*` taşma matrisleri, `AGENTS.md` kural 6 |
| **Kararlı durumda ticker yok** | Boştayken hiçbir animasyon çalışmaz (`pumpAndSettle` biter, pil harcanmaz) | `transientCallbackCount == 0` testleri |
| **Hareket azaltma** | `MediaQuery.disableAnimations` açıkken efektler yok, geçişler anında | `AppMotion.of/reduced` |
| **Kontrast** | Metin >= 4,5:1, ikon/grafik >= 3:1 (gerçek piksel ölçümü kapı cilasında) | `sade_style_test.dart`, `contrast_test.dart`, `gloss_test.dart` |
| **Dokunma hedefi** | >= 44 dp (tercihen 48) | bileşen testleri |
| **Pahalı efekt yok** | `BackdropFilter`, `Opacity` ile büyük alan, `ShaderMask`, `ImageFiltered`, çift gölge, blur > 16 yasak | `gloss_test.dart` ve bileşen testleri |
| **Anlamsal ağaç** | Her etkileşimli öğe tek düğüm, etiket görünen metindir; süs katmanları dışlanır | Semantics testleri |

## 7. Hareket sözlüğü

Süre ve eğriler `AppMotion` (tokens.dart): `fast` 120 ms, `base` 200 ms, `slow` 320 ms;
`enter` easeOutCubic, `standard` fastOutSlowIn. Hepsi `AppMotion.of(context, d)` üzerinden geçer.

**Canlılık olaylarla gelir, sürekli döngüyle değil.** İzin verilen animasyon türleri:

1. **Basış geri bildirimi**: `PressableScale` (ölçek 0,96-0,97, 120 ms).
2. **Giriş**: `StaggeredEntry` (ilk 8 öğe), `PageEntry`, `Pop` (belirginleşme).
3. **Durum değişimi**: renk/zemin geçişi 200 ms (`AnimatedContainer`/`TweenAnimationBuilder`).
4. **Olay efekti (sonlu, ≤ 900 ms)**: yalnız kapı düğmesinde (halka dalgası, ışıltı süpürmesi, kıvılcım patlaması).
5. **İşlevsel gösterge**: yalnız iş sürerken dönen (spinner, sonar halkaları); iş bitince durur.
6. **Bounded dikkat**: `StatusChip.pulse` gibi N tur atıp duran vurgu.

**Yasak**: boştayken sonsuza dek dönen/nefes alan efekt, ekran açılışında kendiliğinden başlayan
süs animasyonu (sayfa girişi zaten var).

## 8. Bileşenler

### `DoorOpenButton` (`door_open_button.dart`): kapıyı aç (istisna, değişmez)
Karar G6/G7 gereği görünüşü ve davranışı aynıdır: cilalı yuvarlak (132-184 dp) ya da çubuk düğme; dört durum
(`ready/opening/offline/disabled`); yüzeyin altında renkli **aura**; olaylar:

| Olay | Efekt |
| --- | --- |
| Basış (`ready`) | çift halka dalgası (520 ms) + ölçek 0,96 + orta haptik |
| Komut sürüyor (`opening`) | sonar halkaları (yalnız sürerken döner) + merkezde spinner |
| Başarı (`successTick` artar) | success tonuna morph, onay işareti, ışıltı süpürmesi, patlama halkası, sekiz kıvılcım (900 ms) |
| Cihaz yeniden hazır (`offline/disabled → ready`) | ışıltı + yumuşak halka |
| `offline` dokunuşu | yatay titreme + `onBlocked` |

Çubuk varyantında halka yerine ışıltı süpürmesi oynar. Hareket azaltmada hiçbir efekt çalışmaz. Düğmenin okuduğu
belirteçler (birincil / uyarı / başarı tonları, palet yüzeyleri, `shadow(1)`, `Gloss`, `PressableScale`, ilerleme
göstergesi teması) bu yüzden değiştirilmez; kilit testi bunları ve pikseli denetler.

**Komut dili (P1-15, dürüst başarı)**: sunucunun komutu kabul etmesi (202) yalnız "komut gönderildi"dir. Cihazın yanıt vermesi ve
kapının fiziksel olarak açılması ayrı durumlardır; kanıt yoksa "açıldı" yazılmaz ve sesle okunmaz. Başarıda düğme `GÖNDERİLDİ`;
bildirim "Kapı açma komutu gönderildi." ya da "<Kapı adı> için açma komutu gönderildi."; sesli okuma aynı cümle; sesli pencere ve
banner "Komut Gönderildi"; QR penceresi "Gönderildi" + "Geçiş onaylandı"; Android widget "Komut gönderildi ✅"; misafir sayfası
"GONDERILDI" + "Kapi acma komutu gonderildi.". "Açık" / "açıldı" yalnız cihazın kendi bildirdiği durumda geçer (yönetici kartındaki
"Kapı Durumu", kapı ekranındaki "KAPI ACILDI"). Kaynakta `test/door_command_language_test.dart` ve `server/test/door_command_language.test.js`
denetler.

### `Gloss` (`gloss.dart`): yalnız kapı düğmesinin cilası
Bir yüzeyin ÜSTÜNE dört ince katman bindirir: sol-üst hacim ışığı, alt gölge, kenar ışığı, özel parıltı (daire) ya da
üst cila (dikdörtgen). Tek `CustomPaint` + `RepaintBoundary`; durağanken yeniden boyanmaz. İsteğe bağlı `sweep` (0→1)
tek seferlik ışıltı süpürmesi çizer. Yüksek karşıtlık modunda kapanır. **Şiddet kalibre edilmiştir**: etiket bölgesi
>= 4,5:1, ikon bölgesi >= 3:1 (`gloss_test.dart`). Sade stilde tema düğmeleri, `PrimaryActionButton` ve `IconOrb` cila
kullanmaz (`glossyButtonLayer` kaldırıldı).

### `PrimaryActionButton` (`buttons.dart`)
Bkz. §3. `filled` düz dolgudur; `tonal` ve `outline` ikincil eylemdir. Yardımcılar: `PrimaryActionButton.fillOf`,
`onFillOf`, `secondaryInkOf` (aynı kuralın tek kaynağı).

### `AppCard`, `SectionHeader`, `InlineNotice` (`app_card.dart`)
Bkz. §4 ve §5.

### Ortak bileşenler
- `AppDialog` başlığı: düz `IconOrb` (44 squircle). `EmptyState`: 72 dp düz daire rozet (kompakt: 44).
- `StatusChip` / `StatusDot`: bkz. §5. `AppSnack`: bkz. §5.
- Tema (`AppTheme`): ana düğmeler düz; ilerleme göstergeleri yuvarlak uçlu; açılır menü, ipucu ve alt sayfa
  yuvarlatılmış; girdi odak kenarı mavi (`focusRing`), hata kenarı mercan, ön ikon gövde metni renginde. Seçili çip
  (`ChoiceChip` / `FilterChip` varsayılanı), bölümlü düğme ve gezinme göstergesi dolgusu nötr gridir (renk şeması
  `secondaryContainer`: açıkta #E2E8F0, koyuda #334155; üstünde başlık metni 14,48:1 / 9,90:1); tohumdan türeyen açık
  mavi-mor kullanılmaz.

### Boş / hata / bağlı değil: `StateView` (`lib/ui/widgets/state_view.dart`, P2-21)
Liste ve bölüm durumlarının TEK bileşeni; üç durum üç ayrı görünür (anlam renkte değil ikon + metindedir):

| Durum | Ne zaman | Görünüm |
| --- | --- | --- |
| `StateView.empty` | kayıt yok | `EmptyCard`: nötr ikon rozeti + başlık (+ mesaj, + kartın içinde eylem) |
| `StateView.error` | sunucu YANIT verdi ama istek olmadı (durum kodu var: 400, 403, 500 ...) | `InlineNotice` mercan, hata ikonu, hizmetin mesajı OLDUĞU GİBİ + "Tekrar Dene" |
| `StateView.offline` | sunucuya ULAŞILAMIYOR (internet yok, DNS/TLS, zaman aşımı, 502-504, ara katman) | `InlineNotice` kehribar, bulut-yok ikonu + "Tekrar Dene"; hata değildir, korkutmaz |

- **Ayrım** `isConnectivityError` (`lib/ui/helpers/connectivity_error.dart`) ile yapılır: durum kodu varsa bağlantı vardır (502/503/504 hariç); durum kodsuz `ApiException`da hizmet katmanının bilinen taşıma metinlerine bakılır. Yükleyiciler (`PagedLoader`, `CursorLoader`) yakaladıkları hatayı bununla işaretler (`errorOffline`, `moreErrorOffline`); mesaj metni değişmez.
- **Satır içi görünüm** eski `EmptyCard` / `InlineNotice` ile AYNI tiplerdir (listeler ve testleri onlara bağlı). `prominent: true` ekranı kaplayan durumlar için ortalanmış büyük rozetli düzendir (`EmptyState`; başlıklar "Bir sorun oluştu" / "Sunucuya ulaşılamıyor").
- **Kullanım**: `CrmListBody` ve `CursorListBody` (≈30 liste: duyurular, talepler, ziyaretçi ve kargo, kişiler, belgeler, finans, rezervasyon ...) üçlüyü kendiliğinden bununla çizer; yeni liste bu gövdeleri kullanır, elle `InlineNotice` / `EmptyCard` dizmez.
- **Eski kayıtlar ekranda dururken** (yenileme hata verdi) bildirimin altında "Son güncelleme 14:32. Kayıtlar eski olabilir." yazar.

### Son güncelleme: `LastUpdatedCaption` (P2-26)
Listenin üstünde küçük sessiz altyazı: "Son güncelleme 14:32" (İstanbul saati; başka günse tarihle: "27.10.2026 14:32"). Veri yükleyicinin `lastLoadedAt` alanından gelir (yalnız BAŞARILI ilk sayfa yüklemesi; `reset` siler). Yenileme (aşağı çekme, "Yenile", "Tekrar Dene") sonrası güncellenir. `CrmListBody` / `CursorListBody`'de `showLastUpdated: true` ile açılır; seçici ve diyalog listelerinde kapalı kalır. Bugün açık olanlar: Duyurular (sakin + yönetim), Talepler (sakin + yönetim), Ziyaretçi ve Kargo (sakin + yönetim), Kişiler, Belgeler (sakin + yönetim).

### Bağlam şeridi: `ContextStrip` (`lib/ui/widgets/context_strip.dart`, P2-21)
Ekranın üstünde, AppBar'ın hemen altında küçük şerit: "Ay Sitesi · A Blok / 5 · Sakin" (site · daire · rol).
- **Yalnız karışabilecek kullanıcıda çıkar**: en az iki siteye ya da (yönetici kitlesi dışında) iki daireye bağlı olan. Tek site + tek dairede, süper kullanıcıda, modül verisi gelmeden ve kısa pencerede (< 480 dp) çizilmez.
- **Metin** (`composeContextStrip`, saf mantık): site = seçili site / tek site / "Tüm siteler (N)" (seçici varken) / "İlk site +N site"; daire = kapsamdaki tek dairenin adı ya da "N daire" (yönetici kitlesinde yok); rol = odaktaki sitedeki rol (Yönetim Kurulu, Görevli), yoksa kitle (Yönetici, Sakin, Bireysel).
- **Dokununca**: yönetici kitlesinde site seçici (çekmecedeki seçiciyle AYNI kapsam; `ModuleAccess.setScopeSiteCode`), sakin kitlesinde "Dairem" (tüm daireler orada). Değiştirilecek bir şey yoksa dokunma eylemi ve ok yoktur.
- Düz yüzey + 1 px kenar (sade stil), dokunma hedefi ≥ 44 dp, metin en çok 2 (büyük yazıda 3) satır + elips, ekran okuyucu tek düğüm ("Ay Sitesi, A Blok / 5, Sakin olarak görüntüleniyor"). Daireler `HomePage.loadContextApartments` ile (uygulama kökü `/membership/my-apartments` bağlar; verilmezse daire parçası çıkmaz) ilk açılışta ve her başarılı genel yenilemede okunur; hata şeridi bozmaz.

### Yenile ve Çıkış (P2-26)
- **Yenile belirgindir**: AppBar'da yuvarlak, 1 px çerçeveli soluk yüzey (`RefreshActionButton`, 44 dp; öteki çıplak simgelerden ayrışır). Yenileme sürerken ilerleme göstergesine döner ve pasif olur; aşağı çekme ile düğme AYNI yoldan geçer (`RefreshStatus`): sürerken ikinci tur başlamaz.
- **Çıkış AppBar'da DEĞİLDİR**: menünün dibinde ("Çıkış Yap", çekmecede "Yardım ve Destek"in altında) ve HER ZAMAN onaylıdır (`confirmLogout`: "Çıkış yapılsın mı?"); "Vazgeç" ya da dışarı dokunuş oturumu da çekmeceyi de yerinde bırakır.

### Kapı açma kartları (yuvarlak cilalı düğme hero'dur)
| Kart | Düzen |
| --- | --- |
| `ResidentDoorRemoteCard` (daire sakini) | kart (level 2), ortada 132-184 dp düğme |
| `AdminDoorStatusCard` (yönetici/süper) | durum bandı + ortada 132-184 dp düğme, altta misafir/QR eylemleri |
| `IndividualDoorCard` (bireysel) | geniş kartta solda 116 dp düğme + sağda bilgi; dar kart ya da yazı > 1,3x ise üstte ortalı |

Kartlar sade stildedir (gölgesiz, düz); içlerindeki kapı düğmesi değişmeden cilalıdır.

**Sade daire kullanıcısı ekranı** (`ResidentDoorRemoteCard(minimal: true)`, yalnız `UserRole.apartmentOwner`): açıklama, rozet, IP, saat ve ek düğme YOKTUR; yalnız kapı seçici (ya da tek kapı adı) + yuvarlak düğme. Kaldırılan komutlar `YanMenu.extraActions` ile çekmecede "Kapılar"ın (Site hizmetleri başlığında; o yoksa "Panel"in) altında toplanır (`Sesli Kapı Açma`, `Kapıya QR Göster`, `Kapı Ekranından QR Oku`, `Kurye / Misafir Geçiş Linki Oluştur`; yetki/cihaz yoksa görünmez). Mantık `ResidentDoorActions` yardımcısındadır (kart ve çekmece aynısını çağırır).

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
  - sakin / kurul / görevli: üstte tek kart ("Güncel borcunuz" + "Borcum'a git", Borcum açık ve borç bilgisi alınabildiyse; yoksa selamlama; bilgi yokken ASLA "borç yok" denmez), altında hızlı işlemler (Kapıyı aç, Arıza bildir, Ziyaretçi kodu, Ziyaretçi ve kargo, Dosya Deposu; yalnız modülü açık olanlar; en sonda sunucu yanıtı gelince "Yöneticiyi ara", bkz. "Dokun-ara").
    - "Arıza bildir" ve "Ziyaretçi ve kargo" yalnız daire bağı olabilen sitede (my-modules `door_access` true ve ilgili modül açık) çıkar: dairesiz kurul üyesi / görevli / yalnız site üyesi görmez. Kapı izni olan dairesiz kullanıcıyı da ayırmak için sunucuda ayrı bir "dairesi var" alanı gerekir.
    - "Ziyaretçi kodu" çekmecedeki "Kurye / Misafir Geçiş Linki Oluştur" ile aynı akış ve aynı koşuldur (daire sakini, Geçiş Kontrol açık, Kapılar erişilebilir, seçili kapıda misafir geçişi izni): süreli geçiş linki üretir, kapı AÇMAZ.
    - Hızlı işlemin ekran okuyucu ipucu dokununca olanı söyler ("Kapılar sayfasını açar; kapı orada açılır").
    - Borç özeti, alıcısı olunan ve Finans'ı açık sitelerle sınırlıdır; bu küme değişince (bir sitede Finans kapandı, siteden ayrılındı) eski tutar gösterilmez ve özet yeniden okunur.
    - Kartın altındaki "Yeni duyuru" kartı vitrinde gölgesiz ve nabızsızdır (`UnreadAnnouncementCard(flat: true)`); başka ekranlardaki görünümü değişmez.
  - bireysel: yalnız ızgara.
- **Görünüm** (renkler `AppShowcaseColors`, tokens.dart; uygulamanın paleti de bu değişkenlerden türer): açık temada sayfa zemini DÜZ #F8FAFC (İP-1C'den beri uygulamanın genel zemini de aynı düz renktir), kart saf beyaz + ince #E2E8F0 çerçeve, gölge yok, normal metin #475569. Koyu renk (#0F172A) YALNIZ eylem isteyen yerde: ödenecek borç varken sakin kartı, yöneticide dikkat barı ve ana düğmeler. Selamlama, "Borcunuz yok", "Alacağınız" ve "borç bilgisi alınamadı" hâli düz beyaz karttır (ana düğmesi koyu hap). Koyu temada odak kutusu zeminden ayrışan lacivert (#172554) + 1,5 dp mavi kenar (zemine ve kutuya ≥ 3:1). Durum noktaları #10B981 / #F59E0B / #E11D48 (arka planı boyamaz; anlam yanındaki metindedir); kart rozetinin noktası `AppTone.danger.a` (= #E11D48, §5). Izgara 2 sütun (telefon; 320 dp telefonda da yazı 1,0-1,15'te iki sütun, gerçek genişlik 288 dp), 3-4 sütun (geniş), büyük yazıda sütun azalır (`showcaseColumns`); satırdaki kartlar eşit yükseklikte, rozet sığmazsa görselin altına iner; hareket azaltmada giriş animasyonu yok.
- **Erişilebilirlik**: hap düğmeler ve "Hesap ve ayarlar" düğmeleri en az 48 dp; hap düğmede klavye odağı iki temada görünür (2 dp dışında 2 dp halka, yanındaki yüzeye ≥ 3:1). Borç kartının ekran okuyucu etiketi görünen TÜM satırları okur (site / daire, tutar, vadesi geçen, sıradaki vade, alacak; tutarlar `moneySemanticLabel` ile "üç bin iki yüz elli lira"); "Borcum'a git" ayrı düğmedir. Dikkat barı düğmesinin adı satırın bağlamlı etiketidir ("2 bekleyen site başvurusu. İncele"): birden çok "İncele" birbirinden ayrılır, satır metni ikinci kez okunmaz.
- **Kapı güvenliği**: vitrinde kapı AÇILMAZ (kazara dokunuşla kapı açılmasın); "Kapıyı aç" hızlı eylemi Kapılar sayfasına götürür, kapı açma mantığı değişmedi. Kapılar sayfası girişte `HomePage.doorEntryGuard` (500 ms: sayfa geçişi + pay) boyunca dokunuş almaz: karta / hızlı eyleme hızlı ikinci dokunuş henüz görünmeyen KAPIYI AÇ düğmesine düşmez. Geçiş Kontrol kapalıyken `SirketMenuItem.kapilar` gizlenir; daire sakini rolünde modül verisi yüklüyken kapı erişimli sitesi ve kapısı olmayan hesapta da (yalnız görevli / kurul / site üyeliği bağı) gizlenir (`hiddenMenuItemsFor`; bireysel, yönetici ve süper kullanıcı etkilenmez): kart, hızlı eylem, Eller Serbest ve çekmecedeki kapı komutları da yoktur. Android kapı widget'ı (`sitekapi://door_control`), uygulama kısayolları ve kapıyla ilgili derin bağlantılar Kapılar sayfasını açar (`DoorPanelRequests`; soğuk açılışta modül verisi beklenir, sakinde Kapı sekmesi seçilir): istek kapı AÇMAZ, kapı açan bağlantının doğrulama ve onay penceresi değişmedi. Durum yoklaması yalnız Kapılar sayfasındayken çalışır.
- Geri tuşu bir modül sayfasından Panel vitrinine döner (`PopScope`); vitrindeyken uygulamadan çıkar. Çekmece ya da sağdaki Ayarlar paneli açıkken geri tuşu önce onu kapatır (sayfa değişmez). Karar ekrandaki etkin sayfayla verilir: erişimi düşen sayfadan vitrine düşülünce ilk geri basışı boşa gitmez.
- Sayfa (menü ya da Sakin / Yönetici modu) değişince gövde kaydırması en üstten başlar. Vitrinde "Yenile" (AppBar düğmesi ya da aşağı çek) borç özetinin yanında kart rozetlerini (okunmamış duyuru, ziyaretçi / kargo) ve "Yeni duyuru" kartını da tazeler.

### Dokun-ara: 112 düğmesi ve "Yöneticiyi ara" (P2-23, karar K13)
- **İlke**: `tel:` adresi telefon uygulamasını numara yazılı AÇAR (Android arama ekranı, iOS onay penceresi); uygulama aramayı kendisi başlatmaz, kazara dokunuşla çağrı yapılmaz. Numara yalnız rakam, boşluk, `( ) - . /` ve baştaki `+` içerebilir (`dialableNumber`, 3-15 hane); harf, `*`, `#`, `;`, `,` ya da ortadaki `+` varsa hiçbir adres açılmaz (USSD / özel kod çevirtilmez). Saf mantık `lib/ui/helpers/dial_call.dart`, açıcı testlerde sahte verilir (`DialLauncher`).
- **Kuru mod** (`DialFallbackCard`, `widgets/dial_fallback.dart`): cihaz aramayı açamazsa (tablet, emülatör, masaüstü, web, arama uygulaması yok) numara büyük gösterilir ve "Numarayı kopyala" ile panoya alınır (kopyalanan aranabilir biçimdir; ekranda gruplu: "0532 123 45 67"). Hata gibi değil çözümle birlikte anlatılır; kart canlı bölgedir (ekran okuyucu "arama başlatılamadı" der). Zemin boyanmaz (uyarı kenarı + simge + metin).
- **`EmergencyCallButton`** (`widgets/emergency_call_button.dart`): acil durumlar bölümünün büyük 112 düğmesi. Şimdilik Dairem > "Güvenlik ve destek" bölümünün başındadır; yangın / asansör ayrı düğmeli acil yardım akışı gelince aynı bileşen onun içine konur. Mercan dolu düğme (`AppTone.danger.a` + beyaz metin, 4,70:1), düz, en az 72 dp; etiket "112 Acil Çağrı Merkezi'ni ara", ipucu "Telefon uygulamasını 112 numarasıyla açar"; tek düğüm; klavye odağında 2 dp halka. Dokununca orta haptik; arama açılamazsa düğmenin altında kuru mod kartı, sonraki başarılı dokunuş kartı kaldırır; uçuştaki arama tekrarlanmaz.
- **`ManagerCallTile`** (`widgets/manager_call_tile.dart`): sakin Panel'inin hızlı işlemlerinin SONUNDA "Yöneticiyi ara" (veri gelince eklenir, öteki kutuların yeri kaymaz; yükleme / hata / eski sunucu 404'ünde çizilmez, ASLA "numara yok" denmez; geçici hatada eldeki bilgi korunur). Tek sitede telefon kayıtlıysa alt satırda yönetici adı, dokununca arama ekranı yönetici numarasıyla açılır; telefon YOKSA kutu görünür kalır, alt satır "Telefon kayıtlı değil" der ve dokununca nedeni söyler (hiçbir şey aranmaz, ölü düğme yok); birden çok sitede alt satır "N site", dokununca siteler ve her birinin "Ara" düğmesi alt sayfada listelenir. Kendi sitesinin yöneticisi olan (sakin modundaki yönetici) satır çizilmez. Etiket "Yöneticiyi ara. {ad}", ipucu dokununca olanı söyler. Dokunuş mantığı `ManagerCallTile.activate` içindedir; Kolay görünümde (hızlı işlemler yok) aynı yol büyük düğmeden çağrılır.
- **`ManagerPhoneHint`**: yönetici Panel'inde, profilinde telefon yoksa "Telefon numaranızı ekleyin" ipucu ("Profilim'e git"); numaranın kimlere görüneceği (sitedeki sakinler, kurul üyeleri, görevliler) açıkça yazılır; Profilim ekranındaki telefon alanında da aynı bilgi vardır.
- **Veri**: `GET /app/manager-contact` (`team_service.js getResidentManagerContacts`): bağı olunan her site için `{ site_code, site_name, manager_name, manager_phone, is_self }`; telefon yöneticinin PROFİLİNDEKİ numaradır, yalnız o siteyle bağı olan oturuma gider; Rehber modülünden bağımsızdır (temel modüller gibi her sitede çalışır). Telefon kayıtlı değilse `manager_phone` null'dır.

### Panel: okunmamış duyuru kartı (N1)
Sakin vitrininde okunmamış duyuru varken `UnreadAnnouncementCard` hero (borç / selam) kartının ÜSTÜNDEdir (`ModuleShowcaseView.aboveHero`). "Bounded dikkat" istisnasıdır: gölgesiz 2 dp kenar + nokta soluktan ana eylem rengine 3 kez (4,8 sn, ~0,5 Hz) geçer, sonra durağan vurgulu kalır; sonsuz efekt yok (WCAG 2.2.2 ve 2.3.1). Hareket azaltmada doğrudan durağan. Duyuru kimliği değişince yeniden başlar.

### Acil durum ekranı (P2-24, karar K13; `emergency_view.dart`, `emergency_parts.dart`)
Çekmecede "Ana sayfa" başlığı altında, Panel'in yanında ("Acil durum", süper kullanıcı dışında herkeste, modül verisi gelmese de; modül değil çekirdek özelliktir). Üstten alta: (çok siteli kullanıcıda "Hangi site için?" seçici) → (kuru modda `InlineNotice` uyarı, kanal olabilen platformda "Tekrar Dene") → **112 kartı** (`AppCard(tone: danger)`, en az 72 dp `PrimaryActionButton(filled, danger)`: tek dokunuşla telefon uygulamasını açar) → iki hızlı düğme (**Yangın**, **Asansör arızası**: `AppCard(selected)` kutucukları; dar ekranda ya da yazı > 1,25'te alt alta; yeniden dokunmak kapatır) → seçili senaryonun kartları (yönlendirme + aranacak numara kartları + "Aramada söyleyin" bloğu: ilk cümle, site adı, adres, seçilip kopyalanabilir + çağrı merkezinin soracakları + "Bilgileri kopyala").
- **Kuru mod** (arama kanalı yok / başlatılamadı): 112 düğmesi yerine büyük numara + "Numarayı kopyala"; numara kartlarında yalnız kopyala; **hiçbir yerde "arandı" denmez** (telefon uygulaması açılınca "Telefon uygulaması açıldı. Aramayı orada başlatın."; açılamazsa "Arama başlatılamadı. 112 numarasını başka bir telefondan arayın."). Masaüstü ve web'de kanal yok sayılır.
- Renk: yalnız palet ve ton (112 ve yangın `danger`, asansör `warning` simgesi, bakım firması araması ana eylem rengi); degrade, gölge, sonsuz animasyon yok. Taşma matrisi 320 x 2,0 ve 360 x 1,5 açık / koyu (`test/screens/emergency_view_test.dart`).

### Gezinme: gruplu çekmece, Ayarlar paneli, site seçici, sakin alt çubuğu (İP-1D, karar G2 + G3)
Vitrinin kart listesi ve kuralları değişmedi; değişen, aynı öğe listesinin (`YanMenu.visibleItems`) çekmecede ve yeni yüzeylerde nasıl dizildiğidir. Görünürlük kuralı yine tek yerdedir: kapalı / yetkisiz öğe çekmecede, Ayarlar panelinde, vitrinde ve alt çubukta hiçbir koşulda yoktur (fail-closed).

- **Çekmece (soldan)**: rol gradyanlı başlık → **site satırı** (en üstte) → mod geçişi (çift modlu hesapta) → başlıklı gruplar → "Yardım ve Destek" → "Çıkış Yap". Başlıklar karar G2 sırasıyladır: **Ana sayfa · Daireler · Borçlar · Tahsilat · Giderler · İletişim · Raporlar · Site hizmetleri** (`SirketMenuGroup.drawerGroups`). Görünür öğesi olmayan başlık çizilmez (bugün Tahsilat, Giderler ve Raporlar hep boştur). Başlık küçük, kalın, sessiz renktir (`AppPalette.textMuted`, palet sözleşmesiyle >= 4,5:1) ve ekran okuyucuda başlık düğümüdür; öğeler ve rozetler eskisi gibidir (`_MenuTile`, >= 48 dp). Grup içinde menü sırası korunur. Sakin kapı komutları (`extraActions`) "Kapılar"ın hemen altındadır (Site hizmetleri). Açılışta ilk 8 satır sırayla belirir (site satırı ve başlıklar dahil).
- **Ayarlar paneli (sağdan, `Scaffold.endDrawer`)**: AppBar'ın en sağındaki **dişli** (ipucu "Ayarlar", 44 dp) açar. Ayarlar grubundaki öğeler buradadır, çekmecede değildir: Profilim, Eller Serbest, kullanıcı yönetimi ekranları, Modüller, Modül Talepleri, Site Başvuruları, cihaz ekranları, Bluetooth ile Wi-Fi Kur, Denetim Kaydı, Platform Ayarları, İstemci Hataları. Paneldeki öğelerin bekleyen sayılarının toplamı dişlide rozettir (`YanMenuAyarlar.badgeTotal`; ekran okuyucu "N bekleyen"). Sayfa seçmeyen ayar eylemi "Masaüstüne Widget Ekle" (yalnız mobilde, süper kullanıcı dışında) AppBar'dan panele taşındı: 320 dp × 2,0'da hap + tema + yenile + dişli sığar ("Çıkış Yap" da AppBar'dan menünün dibine taşındı: bkz. "Yenile ve Çıkış", P2-26).
- **Site seçici (çekmecenin en üstü)**: tek sitede site adı (bilgi satırı, dokunma eylemi yok); birden çok sitede, yönetici görünümünde (süper kullanıcı hariç) seçicidir: alt sayfada "Tüm siteler" ve siteler. Seçilen site `ModuleAccess` kapsamı olur: menü, vitrin kartları ve HomePage'in modül verisinden kurduğu site listeleri (Finans, Dosya Deposu, Talepler ... ekranlarına giden siteler, Kapılar panelinin siteleri) yalnız o siteyle çalışır; Site Yönetimi o siteyi seçer. Kendi site listesini sunucudan çeken ekranların (Kişiler / Duyurular yönetimi, Modüller) kendi seçicisi kalır. Seçim oturumluktur; Sakin / Yönetici modu değişince, rol değişince (örn. yöneticilik kalktı) ve çıkışta "Tüm siteler"e döner. Sakin görünümünde çok site varsa satır "ilk site +N site" der (seçici değil).
- **Sakin alt çubuğu (Material 3 `NavigationBar`, `ResidentBottomBar`)**: yalnız sakin kitlesinde (daire sakini, kurul / görevli bağı olan sakin rolü, sakin modundaki yönetici). Sekmeler: **Özet · Duyuru · Arıza · Kapı · Dosyalar**; her biri bir menü öğesidir (Panel, Duyurular, Taleplerim, Kapılar, Dosya Deposu) ve yalnız o öğe görünürse çizilir. **Kapı** ayrıca kapı yetkisinin olumlu kanıtını ister (kapı listesi dolu ya da modül verisinde kapı erişimli site; Geçiş Kontrol kapalıysa yok); yetkisizde PDF'teki dört sekme kalır. İki sekmeden azsa çubuk çizilmez; kısa pencerede (yükseklik < 480 dp, örn. yatay telefon: `HomePage.residentBarMinHeight`) da çizilmez, gezinme çekmeceyle yapılır (sabit AppBar + acil şerit + 80 dp çubuk büyük yazıda içeriğe yer bırakmazdı). Uygulama Özet'te (Panel vitrini, borç kartı üstte) açılır. Seçili sekme ekrandaki sayfadır; sekme olmayan sayfada (Borcum, Rezervasyon, Profilim ...) Özet seçili görünür. Sekmeye dokunmak çekmeceden seçmekle aynı yoldur (Kapı sekmesi kapıyı AÇMAZ, Kapılar sayfasını açar; giriş koruması aynen geçerlidir). Geri tuşu sekmeden Özet'e, Özet'ten uygulamadan çıkış (yukarıdaki kural). Duyuru sekmesinde okunmamış rozeti (çekmece rozetiyle aynı belirteç; ekran okuyucu "3 okunmamış"). Etiketler yazı ölçeğiyle büyümez (Material zaten 1,3 ile sınırlar; beş sekme 320 dp'de taşmasın diye 1,0): anlam simge + ekran okuyucu etiketindedir. Renkler palet belirteçleri: zemin `surface`, üst çizgi `border`, seçili gösterge rol tonunun açık zemini, etiket `text` / `textSecondary`.
- **"Ana sayfa" düğmesi (`HomeShortcutButton`, karşılaştırma raporu P1-13)**: iç ekranlardan tek dokunuşla Panel'e dönüş. Üst çubukta menü düğmesinin hemen yanında durur (iki düğme birlikte 96 dp: `homeShortcutLeadingWidth`); ipucu ve ekran okuyucu adı "Ana sayfa", dokunma hedefi >= 44 dp. Simge Panel'in çekmecedeki ve alt çubuktaki ("Özet") simgesidir (dört kare): aynı hedef, aynı simge; ev simgesi "Sakin Modu" hapına ayrılmıştır, ikisi karışmaz. Görünürlük kuralı tek yerdedir (`showsHomeShortcut`, `lib/ui/helpers/home_shortcut.dart`): Panel'in kendisinde YOK; sakin alt çubuğu çiziliyorsa YOK (çubuktaki "Özet" sekmesi aynı işi görür, Panel'e dönmek için ikinci bir yol üretilmez); çubuk yokken VAR (yönetici, süper kullanıcı, bireysel, ikiden az sekmeli sakin hesabı örneğin yalnız görevli bağı, yatay telefon). Sağdaki eylemlerle (yenile, dişli, tema, mod hapı; "Çıkış Yap" AppBar'dan kalktı ama bir düğmelik pay bilerek korunur, eşik değişmesin) üst üste binmeyecek kadar yer yoksa çizilmez: çift modlu hesap + tema düğmesi için 348 dp altı; 360 dp ve üstünde her hesapta vardır, çıkmadığında Panel'e menüden ya da geri tuşuyla dönülür. Dokunuş çekmeceden "Panel"i seçmekle AYNI korumalı yoldan geçer (`_openMenuItem`; Platform Ayarları'nda kaydedilmemiş değişiklik onayı dahil). Donanım geri tuşu, çekmece ve alt çubuk davranışı DEĞİŞMEZ; düğme ek bir yoldur. Düğme varken mod hapı (`Sakin Modu` / `Yönetici Paneli`) 480 dp altında yalnız ikondur (etiket iki düğme grubunun arasına sığmaz, "Sakin Mo…" diye kesilirdi; ipucu ve ekran okuyucu adı aynı kalır); Panel'de hap eskisi gibi 400 dp ve üstünde etiketlidir.
  - **Derin (yeni sayfa olarak açılan) ekranlar**: kendi üst çubuğunun `actions` listesine `HomeShortcutButton()` konur; düğme açık ekranların hepsini kapatıp (`PanelReturnRequests.returnToPanel`) ana kabuğa Panel'i seçtirir (aynı korumalı yol). Bugün Aidat ve Finans > Kasa > "Banka dosyası yükle" ile açılan "Banka dosyası" ve "Banka Ödemeleri ve Daire Onayları" ekranlarında ve "İşletme Projesi" ayrıntı ekranındadır. Konum bilerek ana kabuktakinden farklıdır: derin ekranlarda sol küme geri okuna ayrılır ve düğme SAĞDAKİ eylemlerdedir; "bir adım geri" ile "tüm ekranları kapat" yan yana iki 44 dp hedef olsaydı yanlış dokunuş bütün ekranları kapatırdı (kabukta yanındaki menü düğmesi zararsızdır). Kaydedilmemiş veri koruması (`PopScope`) ya da form taşıyan ekranlara (toplu yükleme sihirbazı, düzenleme) varsayılan düğme KONMAZ: `popUntil` korumayı atlar. Tek istisna kendi onayını veren ekrandır: `HomeShortcutButton(onPressed: ...)` ile kaydedilmemiş veri varken önce "Kaydedilmemiş değişiklikler" onayı sorar (İşletme Projesi ayrıntısı: taslakta yazılıp kaydedilmemiş kalem tutarı varken "Düzenlemeye Dön" / "Değişiklikleri Sil"; tutar yazılmamışsa ya da "Kalemleri kaydet" ile kaydedilmişse doğrudan Panel). Onay vermeyen bir form ekranına düğme konmaz. Ekranın kendi geri oku ve geri tuşu bir adım geri gitmeye devam eder; "Ana sayfa" yalnız ek yoldur (tekrarlı dönüş düğmeleri yok).
- **Kompakt menü + "Tüm işlemler" (K8, P1-16; ayrıntı `docs/PLATFORM_MENU_KATMANI.md`)**: yetenek (modül açık) ile menü yerleşimi ayrı katmandır. Site başına kompakt küme (`menu_layout`, yönetici ayarı; varsayılan yönetim türü önerilerinden türer) çekmecede VE Panel ızgarasında yalnız öne çıkan modülleri bırakır; Panel, Kapılar, Dairem, Site Yönetimi ve Ayarlar grubu (dişli) kümeden etkilenmez. Kümede olmayan işlem kaybolmaz: çekmecede başlıklı bölümlerin ardında HER ZAMAN **"Tüm işlemler"** girişi (rozeti gizlenen işlerin bekleyen sayıları toplamı) ve kompakt menü bir şeyi gizliyorsa Panel ızgarasının sonunda aynı adlı kart vardır; ekran görünür TÜM işlemleri kümeden bağımsız, kategorili ve aramalı listeler (`AllActionsView`; satır >= 48 dp, "Ana menüde" işareti, 320 dp x 2,0'da taşma yok). Yönetici "Ana menüyü düzenle"den (`MenuLayoutView`) kümeyi seçer; temel modüller kapatılamaz, yalnız öne çıkıp çıkmayacakları seçilir. Eski sunucuda (`menu_layout` yok) ve süper kullanıcıda kompakt menü yoktur: menü eskisi gibidir.
- **Android widget / kısayol**: "Kapılar sayfasını aç" isteği soğuk açılışta modül verisinin ilk yüklemesini bekler (veri gelmeden Kapılar bir an açılıp vitrine düşmez; ilk yükleme hata verirse fail-open kuralıyla uygulanır; beklerken kullanıcı kendisi başka sayfaya geçerse (çekmece, sekme, vitrin, mod geçişi, acil duyuru şeridi, geri tuşu: hepsi `_requestMenuChange`) istek düşer); Kapılar açılınca alt çubukta Kapı sekmesi seçilir.

### Liste ↔ kutucuk anahtarı (P2-22)
Uygun ana listelerde (şimdilik: **Panel "Modüller" bölümü**, **Kişiler → Daireler**, **Kişiler → Kişiler**) başlık satırındaki tek düğme görünümü değiştirir. Düğme, tema düğmesi gibi GEÇİLECEK kipi anlatır (listedeyken ızgara simgesi, ipucu ve ekran okuyucu etiketi "Kutucuk görünümüne geç"; kutucuktayken "Liste görünümüne geç"); 44 dp; geçişten sonra yeni kip ekran okuyucuya duyurulur.
- **Varsayılan görünüm değişmez**: Panel kutucuk, Daireler ve Kişiler liste (`ViewScreen.defaultMode`). Tercih hiç yapılmadıysa hiçbir ekran eskisinden farklı görünmez.
- **Kalıcı**: tercih ekran başına cihazda saklanır (`ViewModeService`, SharedPreferences `app_view_mode_modules|apartments|persons`: `list` / `tiles`), uygulama açılışında ilk kareden önce okunur (`lib/main.dart`), bozuk değer ekranın varsayılanına döner, depolama hatası uygulamayı bozmaz. Ekranlar birbirinden bağımsızdır. Hesap silinirken de korunur (hesaba bağlı olmayan cihaz görünümü ayarı, tema gibi: `LocalDataWiper`).
- **Kapsam**: `ViewModeScope` uygulama kökündedir (`lib/app.dart`); kapsam yoksa düğme çizilmez ve ekran varsayılan görünümünde kalır (kapsamsız kurulan ekranlar ve eski testler değişmez).
- **Panel**: kutucuk = mevcut ızgara (`_ModuleTile`); liste = `ShowcaseModuleRow` (görsel + başlık + açıklama + rozet + ok; aynı kart anahtarı `panel_kart_<öğe>`, aynı anlamsal düğüm). Kutucuk ve liste aynı `buildShowcaseModel` çıktısından türer: görünürlük kuralı iki kipte de aynıdır (fail-closed). Kompakt menü (K8) bir şeyi gizliyorsa "Tüm işlemler" kutucukta kart, listede satır olarak SON sırada durur (ikisinde de anahtar `panel_kart_tumIslemler`, aynı rozet, aynı geri çağrı).
- **Kişiler / Daireler**: `CrmListBody(viewMode, tileBuilder)`; kutucuk = `TileGrid` (`tileColumns`: telefonda 2, geniş ekranda 3-4, büyük yazıda azalır; satırdaki kutucuklar eşit yükseklikte) içinde `PersonCrmTile` / `ApartmentCrmTile`. Kutucukta aynı dokunma, anlamsal etiket ("Kişi kartı: Ad", "Daire kartı: …"), çoklu seçim onay kutusu ve işlem menüsü (`PersonActionsMenu`: kart ve kutucuk aynı menüyü kullanır) vardır; yazma yetkisi olmayana hiçbir yazma menüsü çıkmaz. Arama, süzgeç, "Daha fazla yükle", iskelet, hata ve boş durum iki kipte aynıdır.

### Kolay görünüm (P2-25)
Görme güçlüğü olan ya da yaşlı kullanıcı için tek anahtarla açılan görünüm: **büyük yazı + yüksek karşıtlık + büyük düğmeli sade ana ekran**. Anahtar sağ üstteki dişliden açılan **Ayarlar panelinin en üstündedir** (`EasyViewSwitchTile`, "Kolay görünüm"); satırın tamamı dokunma hedefidir (>= 56 dp), ekran okuyucu tek düğüm okur (etiket + açık / kapalı durumu), panel kapanmaz (etki hemen görülür). Varsayılan KAPALIdır.
- **Tema düzeyinde, ekran ekran değil**: `lib/app.dart` kolay görünüm açıkken `easyViewLightTheme` / `easyViewDarkTheme` (`lib/styles/easy_view_theme.dart`) temalarını verir ve yazı ölçeğini **en az 1,3** yapar (`EasyViewService.minTextScale`; cihazın yazı boyutu daha büyükse o geçerli, üst sınır 2,0 aynen kalır). Paletten renk okuyan her bileşen (kart, çip, girdi, düğme, durum noktası) kendiliğinden uyar; tek tek ekranlar yeniden çizilmez. Beyaz etiket (marka) paleti bu modda uygulanmaz: okunabilirlik markadan önce gelir. Açılıp kapanınca yalnız `MaterialApp` yeniden kurulur (sayfalar ve durumları korunur).
- **Panelde hızlı işlemler yoktur, gerekli girişler büyük düğmedir** (Dalga D birleşimi; `test/screens/dalga_d_birlesim_test.dart`): sakin için "Yöneticiyi ara" (`panel_kolay_yoneticiyiAra`; sunucu yanıtı gelince, kendi sitesinin yöneticisi olana ve veri yokken çizilmez; dokunuş hızlı işlemler kutusuyla AYNI yoldan geçer: `ManagerCallTile.activate`) ve kompakt menü (K8) bir şeyi gizliyorsa "Tüm işlemler" (`panel_kolay_tumIslemler`, rozetli) modüllerin sonunda durur; gizlenen iş Kolay görünümde de kaybolmaz.
- **Yüksek karşıtlık paleti** (`kEasyLightPalette`, `kEasyDarkPalette`; `test/design/easy_view_theme_test.dart` ölçer): metin >= 7:1 (AAA), kart / girdi kenarı >= 4,5:1, odak halkası >= 3:1.

| Alan | Açık | Koyu | Oran (yüzeyde) |
| --- | --- | --- | --- |
| `background` / `surface` | #FFFFFF / #FFFFFF | #0F172A / #1E293B | |
| `text` | #000000 | #FFFFFF | 21,00 · 14,63 |
| `textSecondary` | #1E293B | #F1F5F9 | 14,63 · 13,35 |
| `textMuted` | #334155 | #CBD5E1 | 10,35 · 9,85 |
| `border` | #475569 | #94A3B8 | 7,58 · 5,71 |
| `link`, `focusRing` | #1E40AF | #BFDBFE | 8,72 · 10,30 |
| `action` / `onAction` | #000000 / #FFFFFF | #FFFFFF / #000000 | 21,00 |
| durum noktaları (tamam, bekliyor, kritik) | #047857, #B45309, #BE123C | #10B981, #F59E0B, #E11D48 | 5,48 · 5,02 · 6,29 (açık) |

  Tema düzeyinde ayrıca: düğmeler (`ElevatedButton`, `FilledButton`, `OutlinedButton`, `TextButton`) en az **56 dp** yüksek (normalde 48), ikincil düğme ve girdi çerçevesi 1,5 px palet kenarı, girdi odak çerçevesi 2,5 px, girdi etiketi `textSecondary`, `ColorScheme.outline` palet kenarı.
- **Sadeleşmiş ana ekran (Panel vitrini)**: modüller **tek sütun büyük düğme** olur (`ShowcaseEasyButton`: tam genişlik, en az 72 dp, 48 dp modül görseli, `titleLarge` başlık, 2 px kenar, sağda ok; bekleyen sayı başlığın altında "3 okunmamış" biçiminde nokta işaretiyle yazılır). Kalkanlar: kutucuk ızgarası ve liste ↔ kutucuk anahtarı, kart açıklamaları (ekran okuyucuya ipucu olarak okunmaya devam eder), "Hızlı işlemler" (aynı sayfalar zaten büyük düğmedir), ikincil çipler (Profilim, Yardım ve Destek ... altta "Hesap ve ayarlar" başlığıyla büyük düğmedir), giriş animasyonu. **Kalanlar**: site başvurusu durumu, yönetici odak barı ve dikkat barı, sakin borç / selamlama kartı, "Yeni duyuru" kartı ve bekleyen davetler; "Ziyaretçi kodu" (verilmişse) Kapılar düğmesinin hemen altında büyük düğmedir.
- **Görünürlük ve güvenlik kuralları AYNI**: büyük düğmeler aynı `buildShowcaseModel` çıktısından türer (kapalı / yetkisiz modülün düğmesi yoktur); Kapılar düğmesi kapı AÇMAZ, Kapılar sayfasını açar (giriş koruması ve onay akışı değişmedi). Çekirdek 8 modül her sitede açık kalır; kolay görünüm modül erişimine dokunmaz.
- **Kalıcı**: `EasyViewService` (SharedPreferences `app_easy_view`, bool), açılışta ilk kareden önce okunur, hesap silinirken de korunur. Bozuk değer KAPALI sayılır.
- **Sınır**: yalnız Panel vitrini sadeleşir; öteki sayfalar kendi düzenlerinde kalır ve tema ile büyük yazıdan yararlanır. Bakım / zorunlu güncelleme engel ekranları (`AppGate`, kendi küçük `MaterialApp`i) kolay görünümü uygulamaz.

## 9. Ekran reçeteleri

- **Liste ekranı**: başlık `SectionHeader` (+ sayaç), öğeler `AppCard`, öğe başına `IconOrb` + durum için
  `StatusDot` / `StatusChip`, ilk 8 öğe `StaggeredEntry`, yüklenirken `Skeleton`, boşken `EmptyState`.
- **Eylem**: birincil `PrimaryActionButton(filled)` (sayfada / kartta bir tane), ikincil `tonal`; kapı açma her zaman
  `DoorOpenButton`.
- **Diyalog**: `AppDialog(icon, tone)`; iptal `TextButton`, onay dolu düğme (yıkıcı onay `filledToneStyle(tone: danger)`).
- **Geri bildirim**: `AppSnack`, formlarda `InlineNotice`.
- **Kritik uyarı**: yalnız eylem isteyen yerde `critical` kutusu (koyu); bilgi ve durum için düz kart + `StatusDot`.
- **Renk**: yalnız `AppPalette` ve `AppTone` (metin için `tone.ink(palette)`, simge için `tone.sign(palette)`, nokta için
  `tone.dot`); Panel vitrini `AppShowcaseColors` (aynı değerler). Düz hex yazmayın.
- **Yeni ekran incelemesi**: §12.3 listesi (boş / hata / bağlı değil üçlüsü + etiket kuralı + renk anlam kuralı) PR'dan
  önce işaretlenir.

## 10. Ne yapılmaz

- Yeni `fontSize` literali (tipografi ölçeği `Theme.of(context).textTheme`).
- Sabit genişlik/yükseklikli metin kutusu; dinamik metin daima `Flexible`/`Expanded`/`maxLines`.
- Sonsuz `AnimationController.repeat()` (iş sürerken dönen gösterge hariç).
- `BackdropFilter`, büyük alan `Opacity`, `ShaderMask`.
- Sayfa içeriğinde degrade, cila (`Gloss`), renkli gölge ya da ışıma (kapı düğmesi hariç).
- Bağlantı ve odak dışında mavi; durum için boyanmış zemin ya da renkli hap (nokta + metin kullanın).
- Çağrı yerinde düğme / kart rengi ezmek (`styleFrom(backgroundColor: AppColors.primary)` gibi): tema ve bileşen
  varsayılanını kullanın. Durum tonlu dolu düğme gerekiyorsa `filledToneStyle(context, tone: …)`. Zorunlu kalırsa
  `ElevatedButton` / `FilledButton` `styleFrom` zemini ve ön planı BİRLİKTE verir: tema ön planı beyaz değildir
  (açıkta #F8FAFC, koyuda #0F172A), yalnız zemin veren çağrı koyu temada renkli zemin üstüne koyu metin çizer
  (`sade_style_test.dart` kaynakta denetler).
- "Diğer" / "Çeşitli" gibi torba etiket: sığmayan işler "Tüm işlemler"e gider (bkz. §12).
- Anlamı yalnız renkle vermek: her durum metin ve/veya simgeyle de söylenir (bkz. §12).

## 11. Tema ile çözülmeyen, ekran düzeyinde kalanlar (İP-1C, 2026-10-21)

Kural gereği ekran ekran renk yamalanmadı (tek istisna, bağımsız incelemede: `individual_home_view.dart` "Üyeyi Çıkar"
onayındaki dolu düğmeye eksik ön plan verildi, kontrast düzeltmesi); aşağıdakiler kendi ekranlarının işidir (sonraki
dalgalarda ya da ilgili İP'de):

- **İP-1D dosyaları** (bu pakette dokunulmadı):
  - çekmece başlığının rol degradesi (`yan_menu.dart`, `role.tone.gradient`), ana sayfa başlığının rol tonlu yıkaması
    (`home_page.dart`, `flexibleSpace`); `AppTone` degradeleri kapı düğmesinde de kullanıldığından belirteç düzeyinde
    değiştirilemedi;
  - çekmecede seçili öğenin hapı (`yan_menu.dart` `_MenuTile`, `tone.tint`) ve sakin alt çubuğunun seçili göstergesi
    (`resident_bottom_bar.dart`, `indicatorColor: tone.tint(p)`; İP-1D) rol tonunun açık zeminidir (sakinde mor,
    sakin modundaki yöneticide yeşil); temanın nötr gezinme göstergesi kuralından sapma, ikisi birlikte ele alınmalı.
  - Dalga 1 tümleştirmesinde düzeltildi: `home_page.dart` içindeki silme onayları (`Colors.red` zemin, açıkta 3,52:1)
    `filledToneStyle(context, tone: AppTone.danger)` (#E11D48 + beyaz, 4,70:1), cihaz arıza onayı `AppTone.warning`,
    "Depoya Al" ana eylem rengi; `sade_style_test.dart` kaynak kuralı artık bu dosyayı da kapsar ve ham `Colors.red`
    zemini yasaklar.
- Çağrı yerinde mavi kalanlar: `all_users_view.dart` dolu düğmesi (`AppTone.primary.a`); anahtarların (`Switch`) etkin
  rengi (`all_users_view.dart`, `managed_user_card.dart`, `hands_free_settings_dialog.dart`); seçili `ChoiceChip`
  dolguları (`resident_door_remote_card.dart`, `replace_device_dialog.dart`, `site_residents_accordion_dialog.dart`);
  `AppTone.primary.ink` ile çizilen ikon ve metinler (ör. finans özet ikonları `finance_parts.dart`, kapı menüsü
  `door_card.dart`, `all_users_view.dart`, `site_approval_request_card.dart`, `create_guest_pass_dialog.dart`); duyuru
  listesinin okunmamış noktası (`announcement_parts.dart`, `AppTone.primary.a`); rol renkli etiketler (kullanıcı ve
  profil ekranları). `AppCard.accentBar` şeridi de çağıranın verdiği rol / durum rengindedir.
- Ton zeminli yerel parçalar: `ReservationUnreadBadge` (`reservation_parts.dart`), belge kitlesi seçeneği
  (`document_form_fields.dart`, seçili satır mavi tint), bireysel daire kartının başlık yıkaması
  (`individual_apartment_card.dart`).
- Degrade, gölge ve ışıma: `site_join_qr_dialog.dart` degrade + gölge, `voice_control_modal.dart`,
  `voice_live_banner.dart`, `digital_clock_widget.dart` degradeleri, `unread_announcement_card.dart` gölgesi,
  `dynamic_qr_pass_modal.dart` `shadow(1)` / `shadow(2)`; ekranlarda `IconOrb(glow: true)` (artık etkisiz).
- Finans ekranlarının yerel renkleri (İP-1A'nın alanı). Ortak `DialogMetaPill` / `DialogPanel` bileşenleri sade kurala
  bağlandığından finanstaki borç ve durum hapları artık zemin boyamaz (renk metin ve simgede).

## 12. Etiket kuralı ve renk anlam kuralı (karşılaştırma raporu P3, Ek C A2 / A15)

Bu iki kural yeni ekran ve metin yazarken ilk bakılacak yazılı ölçüttür; mevcut ekranlar bu kurala göre ekran ekran
yamalanmaz, dokunulan ekran kurala uyar. Dış paketin paleti ya da sözlüğü alınmaz: yalnız ilke alınır.

### 12.1 Etiket kuralı

1. **Eylem adı = sonuç adı.** Düğme ya da menü öğesinin adı, dokununca açılan ekranın başlığıyla (ya da işin sonucunu
   anlatan bildirimle) aynı sözcüklerle söylenir. Örnek: çekmecedeki "Tüm işlemler" girişi "Tüm işlemler" ekranını açar
   (`AllActionsView`); "Yöneticiyi ara" yönetici numarasıyla arama ekranını açar. Ad, sonucun kanıtlanmış olandan
   fazlasını vaat etmez: sunucunun kabul ettiği kapı komutu "Komut gönderildi"dir, "açıldı" değil (P1-15, dürüst başarı).
2. **"Diğer" yok.** Ana menüye (kompakt menü, K8) ya da bir gruba sığmayan işler "Diğer", "Çeşitli", "Genel" gibi torba
   bir başlığın altına atılmaz; yerleri **"Tüm işlemler"**dir (kategorili ve aramalı, hiçbir iş kaybolmaz).
3. **En çok 3 düzey.** Bir işe giden yol en çok üç düzeydir: (1) Panel ya da çekmece grubu, (2) modül ekranı / liste,
   (3) kayıt ya da eylem ayrıntısı. Daha derin bir yapı yeni gezinme düzeyi olmaz: ayrıntı ekranında bölüm, sekme ya da
   "Tüm işlemler" araması olur. Derin ekranlarda `HomeShortcutButton` kuralı geçerlidir (§8, Gezinme).
4. Terim: kullanıcı hesabı için ürün terimi **"Hesap"**tır; aynı şeye ekran ekran farklı ad (profil, üyelik, kullanıcı
   kaydı) verilmez.

### 12.2 Renk anlam kuralı

| Anlam | Renk (tek kaynak) | Not |
| --- | --- | --- |
| Acil, kritik, hata, tehlike | **Tek kırmızı ailesi**: mercan `AppTone.danger` (nokta / dolgu #E11D48, yazı #BE123C) | İkinci bir kırmızı, turuncu ya da ham `Colors.red` acil için eklenmez; 112 düğmesi, "Sil" onayı ve kritik nokta aynı ailedir |
| Deneme, uyarı, bekliyor | **Amber**: `AppTone.warning` (nokta #F59E0B, yazı / simge koyu amber) | Hata değildir, korkutmaz (ör. `StateView.offline`) |
| Tamam | Yeşil: `AppTone.success` (nokta #10B981) | |
| Bilgi, nötr | Nötr gri; mavi yalnız bağlantı ve odak halkasıdır | §1, §10 |

- **Renk tek başına anlam taşımaz.** Her durum metin ve/ya simgeyle de söylenir: durum noktası her zaman metnin yanındadır
  (`StatusDot`), boş / hata / bağlı değil üçü ikon + başlıkla ayrılır (`StateView`), ekran okuyucu etiketi durumu söyler.
  Rengi bilmeyen biri (renk körlüğü, gri tonlama, kolay görünüm) ekranı aynı doğrulukla okuyabilmelidir (WCAG 1.4.1).
- Renk yalnız `AppPalette` / `AppTone` belirteçlerinden gelir (§9 Renk); düz hex yazılmaz.

### 12.3 Yeni ekran inceleme listesi

Yeni ekran ya da ekran değişikliği birleşmeden önce işaretlenir:

- [ ] **Boş / hata / bağlı değil üçlüsü**: liste ve bölüm durumları `StateView` ile (liste için `CrmListBody` /
      `CursorListBody`); elle `InlineNotice` / `EmptyCard` dizilmez; hata (sunucu yanıt verdi) ile bağlı değil
      (sunucuya ulaşılamıyor, amber) karışmaz; "Tekrar Dene" vardır.
- [ ] **Etiket kuralı**: eylem adı = sonuç adı; "Diğer" yok (sığmayan iş "Tüm işlemler"de); yol en çok 3 düzey; "Hesap"
      terimi.
- [ ] **Renk anlam kuralı**: acil = tek kırmızı ailesi, deneme / uyarı = amber; her durumda metin ya da simge de var.
- [ ] Ortak ölçütler (§6): taşma matrisi (320 dp x 2,0), kontrast, dokunma hedefi >= 44 dp, ekran okuyucuda tek düğüm.
