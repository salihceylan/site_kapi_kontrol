# Uygulama ikonları ve açılış görselleri (Güde Teknoloji marka işareti)

Tüm platformların (Android, iOS, macOS, Windows, Web) uygulama ikonu ve açılış (splash) görselleri, `lib/brand` içindeki Güde Teknoloji
vektör yapraklarından (4 altın yaprak) **koddan** üretilir. Elle PNG düzenlenmez.

Tasarım: derin lacivert-siyah zemin + hafif radyal altın ışıma, ortada büyük parlak yapraklar (marka gradyanları, canlılık için doygunluk/parlaklık
yükseltilmiş), yaprak çevresinde yumuşak parlama (bloom), ince kenar ışığı, yapraklara kırpılmış speküler tarama ve en yüksek yaprakta küçük ışıltı yıldızı
(küçük boyutlarda süsler kapanır, işaret büyür). Küçük ikonda yazı yoktur; tam logo (yazılı) yalnız büyük açılış ekranlarındadır.

## Yeniden üretme

```
flutter test tool/icons/render_icons_test.dart     # 1) PNG'leri build/icon_render/ altına çizer (nihai yolları aynalar)
python tool/icons/apply_icons.py                   # 2) yerlerine kopyalar, ICO + Android vektörleri + web yükleme SVG'sini yazar, doğrular
python tool/icons/apply_icons.py --check           #    yalnız doğrulama (dosya yazmaz)
```

İsteğe bağlı görsel kontrol (depodaki gerçek dosyalardan tek kolaj; repoya yazılmaz):

```
ICON_PREVIEW_OUT=<yol>/icons_preview.png flutter test tool/icons/preview_collage_test.dart
```

Tasarımı değiştirmek için: renkler `brand_spec.json`, çizim `icon_art.dart` (`Look`, `paintBackground`, `paintMark`), hangi dosyanın hangi boyutta ve
hangi plakayla (kare/squircle/daire, alfa var/yok) üretileceği `render_icons_test.dart` içindedir. Logo değişirse önce `tool/logo` hattı
(`gude_logo.svg` → `lib/brand/gude_logo_data.dart`) çalıştırılır, sonra yukarıdaki iki komut.

## Dosyalar

| Dosya | Görev |
|---|---|
| `brand_spec.json` | Renk sözleşmesi (zemin, ışıma, parlama, düz koyu renk). Dart ve Python ikisi de okur. |
| `icon_art.dart` | Çizim: zemin/ışıma, yaprak işareti (bloom, kenar ışığı, tarama, ışıltı), tam logo açılış görseli, PNG kodlayıcı (opaklar alfa kanalsız RGB yazılır). |
| `render_icons_test.dart` | `flutter test` ile tüm PNG'leri üretir. Boyut listeleri MEVCUT dosyalardan (iOS/macOS adları, Android ic_launcher boyutları) okunur. |
| `apply_icons.py` | Dağıtım + ICO + Android vektörleri (monokrom, bildirim) + adaptive arka plan + web yükleme SVG'si + doğrulama. Yalnız Python standart kütüphanesi. |
| `preview_collage_test.dart` | Doğrulama kolajı. |

## Platform bazında ne üretilir

- **iOS** `ios/Runner/Assets.xcassets/AppIcon.appiconset/*.png`: Contents.json'daki tüm dosya adları/boyutları; **alfa kanalı yok** (RGB), kare tam çerçeve, köşe
  yuvarlatması yok (iOS maskeler). Açılış: `LaunchImage.imageset` (256/512/768 px, şeffaf zemin, ışıma + tam logo) + `LaunchScreen.storyboard` koyu zemin.
- **macOS** `macos/.../AppIcon.appiconset/app_icon_*.png`: %10 iç boşluk, squircle plaka, yumuşak gölge, şeffaf kenar (macOS ikona maske uygulamaz, şekli ikon taşır).
- **Android** `android/app/src/main/res`: `mipmap-anydpi-v26/ic_launcher(.round).xml` (adaptive: `drawable/ic_launcher_background.xml` + `mipmap-*/ic_launcher_foreground.png`,
  yapraklar 66dp güvenli daire içinde + `<monochrome>` = `drawable/ic_launcher_monochrome.xml`), eski cihazlar için `mipmap-*/ic_launcher.png` (squircle) ve
  `ic_launcher_round.png` (daire), bildirim `drawable/ic_stat_notification.xml` (beyaz yaprak silueti; Firebase varsayılan ikonu olarak `AndroidManifest.xml`'de kullanılır),
  açılış: Android 12+ `values-v31`/`values-night-v31` (`windowSplashScreenBackground` + statik `drawable-nodpi/ic_splash_mark.png`), Android 11 ve öncesi
  `drawable(-v21)/launch_background.xml` (koyu zemin + `drawable-*dpi/launch_logo.png` tam logo). Koyu zemin rengi `values/brand_colors.xml`.
- **Windows** `windows/runner/resources/app_icon.ico`: 16, 24, 32, 48, 64, 128, 256 px; hepsi PNG gömülü, squircle plaka.
- **Web** `web/favicon.png` (64, squircle), `web/icons/Icon-192/512.png` (opak kare), `Icon-maskable-192/512.png` (yapraklar %80 güvenli bölgede),
  `web/manifest.json` (tema/arka plan #06080B), `web/index.html` (theme-color meta + Flutter ilk kareyi çizene kadar koyu zeminde hafif yaprak yükleme görseli:
  satır içi SVG + CSS, `prefers-reduced-motion` ise animasyonsuz, `flutter-first-frame` olayında kaybolur; SVG `brand-loader:start/end` işaretçileri arasına yazılır).

## Doğrulama (`apply_icons.py`)

PNG boyutu = dosya adı, iOS ikonlarında alfa yok, ICO başlığı/katman boyutları/PNG imzaları, tüm Android XML'lerinin ayrıştırılması ve `@drawable`/`@mipmap`
başvurularının çözülmesi, vektör yapraklarının 66dp güvenli daire içinde olması, manifest/storyboard/index.html renklerinin `brand_spec.json` ile uyumu,
izlenen ikon PNG'lerinin tamamının yeniden üretilmiş olması (eksik/fazla dosya yok) ve eski AHBU görselinin kalmamış olması.
