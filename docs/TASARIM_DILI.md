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
  - sakin / kurul / görevli: üstte tek kart ("Güncel borcunuz" + "Borcum'a git", Borcum açık ve borç bilgisi alınabildiyse; yoksa selamlama; bilgi yokken ASLA "borç yok" denmez), altında hızlı işlemler (Kapıyı aç, Arıza bildir, Ziyaretçi kodu, Ziyaretçi ve kargo, Dosya Deposu; yalnız modülü açık olanlar).
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

### Panel: okunmamış duyuru kartı (N1)
Sakin vitrininde okunmamış duyuru varken `UnreadAnnouncementCard` hero (borç / selam) kartının ÜSTÜNDEdir (`ModuleShowcaseView.aboveHero`). "Bounded dikkat" istisnasıdır: gölgesiz 2 dp kenar + nokta soluktan ana eylem rengine 3 kez (4,8 sn, ~0,5 Hz) geçer, sonra durağan vurgulu kalır; sonsuz efekt yok (WCAG 2.2.2 ve 2.3.1). Hareket azaltmada doğrudan durağan. Duyuru kimliği değişince yeniden başlar.

### Gezinme: gruplu çekmece, Ayarlar paneli, site seçici, sakin alt çubuğu (İP-1D, karar G2 + G3)
Vitrinin kart listesi ve kuralları değişmedi; değişen, aynı öğe listesinin (`YanMenu.visibleItems`) çekmecede ve yeni yüzeylerde nasıl dizildiğidir. Görünürlük kuralı yine tek yerdedir: kapalı / yetkisiz öğe çekmecede, Ayarlar panelinde, vitrinde ve alt çubukta hiçbir koşulda yoktur (fail-closed).

- **Çekmece (soldan)**: rol gradyanlı başlık → **site satırı** (en üstte) → mod geçişi (çift modlu hesapta) → başlıklı gruplar → "Yardım ve Destek" → "Çıkış Yap". Başlıklar karar G2 sırasıyladır: **Ana sayfa · Daireler · Borçlar · Tahsilat · Giderler · İletişim · Raporlar · Site hizmetleri** (`SirketMenuGroup.drawerGroups`). Görünür öğesi olmayan başlık çizilmez (bugün Tahsilat, Giderler ve Raporlar hep boştur). Başlık küçük, kalın, sessiz renktir (`AppPalette.textMuted`, palet sözleşmesiyle >= 4,5:1) ve ekran okuyucuda başlık düğümüdür; öğeler ve rozetler eskisi gibidir (`_MenuTile`, >= 48 dp). Grup içinde menü sırası korunur. Sakin kapı komutları (`extraActions`) "Kapılar"ın hemen altındadır (Site hizmetleri). Açılışta ilk 8 satır sırayla belirir (site satırı ve başlıklar dahil).
- **Ayarlar paneli (sağdan, `Scaffold.endDrawer`)**: AppBar'ın en sağındaki **dişli** (ipucu "Ayarlar", 44 dp) açar. Ayarlar grubundaki öğeler buradadır, çekmecede değildir: Profilim, Eller Serbest, kullanıcı yönetimi ekranları, Modüller, Modül Talepleri, Site Başvuruları, cihaz ekranları, Bluetooth ile Wi-Fi Kur, Denetim Kaydı, Platform Ayarları, İstemci Hataları. Paneldeki öğelerin bekleyen sayılarının toplamı dişlide rozettir (`YanMenuAyarlar.badgeTotal`; ekran okuyucu "N bekleyen"). Sayfa seçmeyen ayar eylemi "Masaüstüne Widget Ekle" (yalnız mobilde, süper kullanıcı dışında) AppBar'dan panele taşındı: 320 dp × 2,0'da hap + tema + yenile + çıkış + dişli sığar.
- **Site seçici (çekmecenin en üstü)**: tek sitede site adı (bilgi satırı, dokunma eylemi yok); birden çok sitede, yönetici görünümünde (süper kullanıcı hariç) seçicidir: alt sayfada "Tüm siteler" ve siteler. Seçilen site `ModuleAccess` kapsamı olur: menü, vitrin kartları ve HomePage'in modül verisinden kurduğu site listeleri (Finans, Dosya Deposu, Talepler ... ekranlarına giden siteler, Kapılar panelinin siteleri) yalnız o siteyle çalışır; Site Yönetimi o siteyi seçer. Kendi site listesini sunucudan çeken ekranların (Kişiler / Duyurular yönetimi, Modüller) kendi seçicisi kalır. Seçim oturumluktur; Sakin / Yönetici modu değişince, rol değişince (örn. yöneticilik kalktı) ve çıkışta "Tüm siteler"e döner. Sakin görünümünde çok site varsa satır "ilk site +N site" der (seçici değil).
- **Sakin alt çubuğu (Material 3 `NavigationBar`, `ResidentBottomBar`)**: yalnız sakin kitlesinde (daire sakini, kurul / görevli bağı olan sakin rolü, sakin modundaki yönetici). Sekmeler: **Özet · Duyuru · Arıza · Kapı · Dosyalar**; her biri bir menü öğesidir (Panel, Duyurular, Taleplerim, Kapılar, Dosya Deposu) ve yalnız o öğe görünürse çizilir. **Kapı** ayrıca kapı yetkisinin olumlu kanıtını ister (kapı listesi dolu ya da modül verisinde kapı erişimli site; Geçiş Kontrol kapalıysa yok); yetkisizde PDF'teki dört sekme kalır. İki sekmeden azsa çubuk çizilmez; kısa pencerede (yükseklik < 480 dp, örn. yatay telefon: `HomePage.residentBarMinHeight`) da çizilmez, gezinme çekmeceyle yapılır (sabit AppBar + acil şerit + 80 dp çubuk büyük yazıda içeriğe yer bırakmazdı). Uygulama Özet'te (Panel vitrini, borç kartı üstte) açılır. Seçili sekme ekrandaki sayfadır; sekme olmayan sayfada (Borcum, Rezervasyon, Profilim ...) Özet seçili görünür. Sekmeye dokunmak çekmeceden seçmekle aynı yoldur (Kapı sekmesi kapıyı AÇMAZ, Kapılar sayfasını açar; giriş koruması aynen geçerlidir). Geri tuşu sekmeden Özet'e, Özet'ten uygulamadan çıkış (yukarıdaki kural). Duyuru sekmesinde okunmamış rozeti (çekmece rozetiyle aynı belirteç; ekran okuyucu "3 okunmamış"). Etiketler yazı ölçeğiyle büyümez (Material zaten 1,3 ile sınırlar; beş sekme 320 dp'de taşmasın diye 1,0): anlam simge + ekran okuyucu etiketindedir. Renkler palet belirteçleri: zemin `surface`, üst çizgi `border`, seçili gösterge rol tonunun açık zemini, etiket `text` / `textSecondary`.
- **Android widget / kısayol**: "Kapılar sayfasını aç" isteği soğuk açılışta modül verisinin ilk yüklemesini bekler (veri gelmeden Kapılar bir an açılıp vitrine düşmez; ilk yükleme hata verirse fail-open kuralıyla uygulanır; beklerken kullanıcı kendisi başka sayfaya geçerse (çekmece, sekme, vitrin, mod geçişi, acil duyuru şeridi, geri tuşu: hepsi `_requestMenuChange`) istek düşer); Kapılar açılınca alt çubukta Kapı sekmesi seçilir.

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
