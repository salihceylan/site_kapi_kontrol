// Güde Teknoloji uygulama ikonlarını ve açılış görsellerini PNG olarak üretir.
//
//   flutter test tool/icons/render_icons_test.dart
//
// Çıktı: build/icon_render/ (ICON_RENDER_OUT ortam değişkeniyle değiştirilebilir). Dosyalar, depo köküne göre nihai yollarını
// aynalar (ör. build/icon_render/ios/Runner/Assets.xcassets/AppIcon.appiconset/180.png); Windows ICO için kaynaklar `_ico/` altındadır.
// Üretilenleri yerlerine dağıtmak, ICO/XML yazmak ve doğrulamak için: python tool/icons/apply_icons.py
//
// Boyut listeleri MEVCUT dosyalardan okunur (iOS/macOS/Android PNG adları ve boyutları), bu yüzden eksik/fazla dosya kalmaz.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import 'icon_art.dart';

const _iosIcons = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
const _iosLaunch = 'ios/Runner/Assets.xcassets/LaunchImage.imageset';
const _macIcons = 'macos/Runner/Assets.xcassets/AppIcon.appiconset';
const _androidRes = 'android/app/src/main/res';

/// Android yoğunlukları: klasör soneki -> ölçek (mdpi = 1).
const _densities = <String, double>{'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4};

/// Windows ICO katmanları.
const _icoSizes = [16, 24, 32, 48, 64, 128, 256];

int _pngWidth(File f) {
  final b = f.readAsBytesSync();
  return ByteData.sublistView(b).getUint32(16);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('uygulama ikonlari ve acilis gorselleri uretilir', () async {
    final root = Platform.environment['ICON_RENDER_OUT'] ?? 'build/icon_render';
    final outDir = Directory(root);
    if (outDir.existsSync()) outDir.deleteSync(recursive: true);
    outDir.createSync(recursive: true);

    final art = IconArt(BrandSpec.load());
    final report = <Map<String, Object>>[];

    Future<void> save(String rel, ui.Image img, {required bool alpha, required String role}) async {
      final f = File('$root/$rel');
      f.parent.createSync(recursive: true);
      f.writeAsBytesSync(await encodePng(img, alpha: alpha));
      report.add({'path': rel, 'px': img.width, 'alpha': alpha, 'role': role});
    }

    List<int> sizesIn(String dir, RegExp name) {
      final out = <int>[];
      for (final e in Directory(dir).listSync()) {
        if (e is File) {
          final base = e.uri.pathSegments.last;
          final m = name.firstMatch(base);
          if (m != null) out.add(int.parse(m.group(1)!));
        }
      }
      out.sort();
      return out;
    }

    // --- iOS: alfa kanalsız (RGB), kare tam çerçeve; iOS kendi köşe maskesini uygular. ---
    final iosSizes = sizesIn(_iosIcons, RegExp(r'^(\d+)\.png$'));
    expect(iosSizes, isNotEmpty);
    for (final px in iosSizes) {
      await save('$_iosIcons/$px.png', await art.plate(px), alpha: false, role: 'ios-icon');
    }

    // --- macOS: kendi şeklini taşır (macOS maskelemez): %10 iç boşluklu squircle + yumuşak gölge, şeffaf kenar. ---
    final macSizes = sizesIn(_macIcons, RegExp(r'^app_icon_(\d+)\.png$'));
    expect(macSizes, isNotEmpty);
    for (final px in macSizes) {
      await save(
        '$_macIcons/app_icon_$px.png',
        await art.plate(px, shape: PlateShape.squircle, inset: 0.1, shadow: px >= 64, diameterScale: 0.94),
        alpha: true,
        role: 'macos-icon',
      );
    }

    // --- Android ---
    for (final entry in _densities.entries) {
      final dpi = entry.key;
      final scale = entry.value;
      final legacy = (48 * scale).round();
      final f = File('$_androidRes/mipmap-$dpi/ic_launcher.png');
      if (f.existsSync()) expect(_pngWidth(f), legacy, reason: 'mevcut ic_launcher.png boyutu $dpi icin beklenenden farkli');
      // Eski cihazlar (API < 26): squircle ve daire.
      await save('$_androidRes/mipmap-$dpi/ic_launcher.png', await art.plate(legacy, shape: PlateShape.squircle, inset: 0.02), alpha: true, role: 'android-legacy');
      await save('$_androidRes/mipmap-$dpi/ic_launcher_round.png', await art.plate(legacy, shape: PlateShape.circle), alpha: true, role: 'android-legacy-round');
      // Adaptive ön plan: 108dp tuval; yapraklar 66dp güvenli daireye sığar (işaret çapı 0.58 x tuval = 62.6dp).
      final fg = (108 * scale).round();
      await save(
        '$_androidRes/mipmap-$dpi/ic_launcher_foreground.png',
        await art.foreground(fg, look: Look(diameter: 0.58, sparkle: fg >= 216), glowRadius: 0.5, glowStrength: 0.75),
        alpha: true,
        role: 'android-adaptive-foreground',
      );
      // Android 12 öncesi açılış: şeffaf zemin üstünde tam logo + ışıma (256dp kare tuval).
      final splash = (256 * scale).round();
      await save('$_androidRes/drawable-$dpi/launch_logo.png', await art.splashLogo(splash, logoWidth: 0.82), alpha: true, role: 'android-launch-logo');
    }
    // Android 12+ açılış simgesi: 288dp tuval (xxhdpi karşılığı 864 px), yalnız yapraklar + ışıma.
    await save(
      '$_androidRes/drawable-nodpi/ic_splash_mark.png',
      await art.foreground(864, look: const Look(diameter: 0.60), glowRadius: 0.5, glowStrength: 0.9),
      alpha: true,
      role: 'android-splash-icon',
    );

    // --- iOS açılış görseli (LaunchImage): şeffaf zemin, tam logo + ışıma (256 pt kare tuval; zemin storyboard'da koyu). ---
    await save('$_iosLaunch/LaunchImage.png', await art.splashLogo(256, logoWidth: 0.82), alpha: true, role: 'ios-launch');
    await save('$_iosLaunch/LaunchImage@2x.png', await art.splashLogo(512, logoWidth: 0.82), alpha: true, role: 'ios-launch');
    await save('$_iosLaunch/LaunchImage@3x.png', await art.splashLogo(768, logoWidth: 0.82), alpha: true, role: 'ios-launch');

    // --- Web ---
    // Sekme simgesi: squircle plaka (açık/koyu sekme çubuğunda da görünür), şeffaf köşe.
    await save('web/favicon.png', await art.plate(64, shape: PlateShape.squircle), alpha: true, role: 'web-favicon');
    // Ana ekran / apple-touch: kare tam çerçeve, opak (iOS ve tarayıcılar kendi maskesini uygular).
    for (final px in const [192, 512]) {
      await save('web/icons/Icon-$px.png', await art.plate(px), alpha: false, role: 'web-icon');
      // Maskable: yapraklar merkezdeki %80 güvenli daireye (işaret çapı 0.66) sığar.
      await save('web/icons/Icon-maskable-$px.png', await art.plate(px, look: Look(diameter: 0.66, sparkle: px >= 192)), alpha: false, role: 'web-maskable');
    }

    // --- Windows ICO kaynakları ---
    for (final px in _icoSizes) {
      await save('_ico/windows_$px.png', await art.plate(px, shape: PlateShape.squircle), alpha: true, role: 'windows-ico-layer');
    }

    File('$root/_render_report.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
    stdout.writeln('${report.length} PNG uretildi -> $root');
  }, timeout: const Timeout(Duration(minutes: 10)));
}
