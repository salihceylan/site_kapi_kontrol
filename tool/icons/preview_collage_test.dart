// Depodaki GERCEK ikon/acilis dosyalarindan tek bir onizleme kolaji uretir (dogrulama icin; repoya girmez).
//
//   ICON_PREVIEW_OUT=<cikti.png> flutter test tool/icons/preview_collage_test.dart
//
// Okunanlar: iOS/macOS/Android/Web PNG'leri, Windows ICO katmanlari (ICO'dan ayristirilir), Android vektorleri (XML pathData),
// adaptive arka plan (XML gradyan degerleri brand_spec.json ile ayni). Maskeler (daire/squircle/yuvarlak kare) simule edilir.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart' show TextPainter, TextSpan, TextStyle, TextDirection;
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/brand/logo_model.dart';

import 'icon_art.dart';

const _iosIcons = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
const _iosLaunch = 'ios/Runner/Assets.xcassets/LaunchImage.imageset';
const _macIcons = 'macos/Runner/Assets.xcassets/AppIcon.appiconset';
const _res = 'android/app/src/main/res';

Future<ui.Image> _png(String path) async {
  final codec = await ui.instantiateImageCodec(File(path).readAsBytesSync());
  return (await codec.getNextFrame()).image;
}

Future<ui.Image> _pngBytes(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  return (await codec.getNextFrame()).image;
}

/// ICO'dan katmanlari ayristirir (PNG gomulu).
Future<List<ui.Image>> _icoLayers(String path) async {
  final b = File(path).readAsBytesSync();
  final bd = ByteData.sublistView(b);
  final n = bd.getUint16(4, Endian.little);
  final out = <ui.Image>[];
  for (var i = 0; i < n; i++) {
    final e = 6 + 16 * i;
    final size = bd.getUint32(e + 8, Endian.little);
    final off = bd.getUint32(e + 12, Endian.little);
    out.add(await _pngBytes(Uint8List.sublistView(b, off, off + size)));
  }
  return out;
}

ui.Path _vectorPath(String xmlPath, double viewport, double px) {
  final xml = File(xmlPath).readAsStringSync();
  final data = RegExp(r'android:pathData="([^"]+)"').firstMatch(xml)!.group(1)!;
  final path = parseLogoPath(data);
  return path.transform(Float64List.fromList([px / viewport, 0, 0, 0, 0, px / viewport, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('onizleme kolaji', () async {
    final outPath = Platform.environment['ICON_PREVIEW_OUT'] ?? 'build/icon_render/icons_preview.png';
    final spec = BrandSpec.load();

    // Etiket yazı tipi (yalnız önizleme; yoksa kutular çıkar ama kolaj yine üretilir).
    var family = 'Ahem';
    for (final f in const ['C:/Windows/Fonts/segoeui.ttf', 'C:/Windows/Fonts/arial.ttf']) {
      if (File(f).existsSync()) {
        final loader = FontLoader('PreviewFont')..addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
        await loader.load();
        family = 'PreviewFont';
        break;
      }
    }

    const w = 1900.0, h = 2420.0;
    final rec = ui.PictureRecorder();
    final c = ui.Canvas(rec);
    c.drawRect(const ui.Rect.fromLTWH(0, 0, w, h), ui.Paint()..color = const ui.Color(0xFF3B414C));

    void label(String t, double x, double y, {double size = 18, ui.Color color = const ui.Color(0xFFFFFFFF)}) {
      final tp = TextPainter(
        text: TextSpan(text: t, style: TextStyle(fontFamily: family, fontSize: size, color: color)),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: w - x - 20);
      tp.paint(c, ui.Offset(x, y));
    }

    // Maskeli yerleştirme (maske: null = ham).
    void put(ui.Image img, double x, double y, double size, {PlateShape? mask, double radiusFrac = 0.2237}) {
      final dst = ui.Rect.fromLTWH(x, y, size, size);
      c.save();
      if (mask != null) {
        if (mask == PlateShape.squircle) {
          c.clipPath(IconArt.squirclePath(dst), doAntiAlias: true);
        } else if (mask == PlateShape.circle) {
          c.clipPath(ui.Path()..addOval(dst), doAntiAlias: true);
        } else {
          c.clipRRect(ui.RRect.fromRectAndRadius(dst, ui.Radius.circular(size * radiusFrac)), doAntiAlias: true);
        }
      }
      c.drawImageRect(
        img,
        ui.Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        dst,
        ui.Paint()..filterQuality = size < img.width ? ui.FilterQuality.high : ui.FilterQuality.none,
      );
      c.restore();
    }

    double y = 20;
    label('Güde Teknoloji uygulama ikonları – önizleme (depodaki gerçek dosyalar; maskeler simüle)', 20, y, size: 26);
    y += 52;

    // ---- iOS ----
    label('iOS  (alfa kanalı YOK; iOS kendi köşe maskesini uygular: burada squircle ile simüle) – 1024 (kırpılmış), 180, 120, 80, 60, 40, 29 px (1:1)', 20, y);
    y += 30;
    var x = 20.0;
    put(await _png('$_iosIcons/1024.png'), x, y, 230, mask: PlateShape.squircle);
    x += 250;
    for (final px in const [180, 120, 80, 60, 40, 29]) {
      put(await _png('$_iosIcons/$px.png'), x, y, px.toDouble(), mask: PlateShape.squircle);
      x += px + 24;
    }
    // Ham 1024 (maskesiz, köşeler kare görünür): alfa kontrolü
    put(await _png('$_iosIcons/1024.png'), x + 20, y, 230);
    label('ham 1024 (maskesiz)', x + 20, y + 236, size: 14);
    y += 270;

    // ---- macOS ----
    label('macOS  (%10 iç boşluk + squircle + yumuşak gölge; şeffaf köşe) – 512 (1:1), 256, 128, 64, 32, 16', 20, y);
    y += 30;
    x = 20;
    put(await _png('$_macIcons/app_icon_512.png'), x, y, 300);
    x += 320;
    for (final px in const [256, 128, 64, 32, 16]) {
      put(await _png('$_macIcons/app_icon_$px.png'), x, y, px.toDouble());
      x += px + 24;
    }
    y += 320;

    // ---- Android adaptive ----
    label('Android adaptive (108dp tuval; görünür maske 72dp): daire, squircle, yuvarlak kare + güvenli bölge çemberi (66dp) · tema (monokrom) · eski PNG (kare/yuvarlak)', 20, y);
    y += 30;
    final fg = await _png('$_res/mipmap-xxxhdpi/ic_launcher_foreground.png');
    const unit = 2.6; // 1dp = 2.6 px önizleme
    Future<void> adaptive(double ax, double ay, PlateShape? shape, {double radiusFrac = 0.22, bool safe = false}) async {
      final full = ui.Rect.fromLTWH(ax, ay, 108 * unit, 108 * unit);
      final vis = ui.Rect.fromCenter(center: full.center, width: 72 * unit, height: 72 * unit);
      c.save();
      final clip = shape == PlateShape.circle
          ? (ui.Path()..addOval(vis))
          : shape == PlateShape.squircle
              ? IconArt.squirclePath(vis)
              : (ui.Path()..addRRect(ui.RRect.fromRectAndRadius(vis, ui.Radius.circular(72 * unit * radiusFrac))));
      c.clipPath(clip, doAntiAlias: true);
      // arka plan: ic_launcher_background.xml ile aynı radyal gradyan (merkez 0.5/0.46, yarıçap %54)
      c.drawRect(
        full,
        ui.Paint()
          ..shader = ui.Gradient.radial(
            ui.Offset(full.left + full.width * 0.5, full.top + full.height * 0.46),
            full.width * 0.54,
            [spec.bgCenter, spec.bgMid, spec.bgEdge],
            const [0.0, 0.5, 1.0],
          ),
      );
      c.drawImageRect(fg, ui.Rect.fromLTWH(0, 0, fg.width.toDouble(), fg.height.toDouble()), full, ui.Paint()..filterQuality = ui.FilterQuality.high);
      c.restore();
      if (safe) {
        c.drawCircle(full.center, 33 * unit, ui.Paint()..style = ui.PaintingStyle.stroke..strokeWidth = 1.5..color = const ui.Color(0xAA7CF2B0));
      }
    }

    x = 20;
    await adaptive(x, y, PlateShape.circle, safe: true);
    x += 108 * unit + 6;
    await adaptive(x, y, PlateShape.squircle);
    x += 108 * unit + 6;
    await adaptive(x, y, PlateShape.square);
    x += 108 * unit + 6;
    // Tema (monokrom) simgesi: Android 13 açık mavi ton zemin üstünde koyu yaprak
    {
      final full = ui.Rect.fromLTWH(x, y, 108 * unit, 108 * unit);
      final vis = ui.Rect.fromCenter(center: full.center, width: 72 * unit, height: 72 * unit);
      c.save();
      c.clipPath(ui.Path()..addOval(vis), doAntiAlias: true);
      c.drawRect(full, ui.Paint()..color = const ui.Color(0xFFD3E3FD));
      final mono = _vectorPath('$_res/drawable/ic_launcher_monochrome.xml', 108, 108 * unit).shift(full.topLeft);
      c.drawPath(mono, ui.Paint()..color = const ui.Color(0xFF0B3A6F)..isAntiAlias = true);
      c.restore();
      label('tema (monokrom)', x + 10, y + 108 * unit + 4, size: 14);
    }
    x += 108 * unit + 16;
    final l192 = await _png('$_res/mipmap-xxxhdpi/ic_launcher.png');
    final r192 = await _png('$_res/mipmap-xxxhdpi/ic_launcher_round.png');
    put(l192, x, y + 10, 192);
    put(r192, x, y + 10 + 202, 192);
    label('eski cihaz PNG (192)', x, y + 10 + 202 + 196, size: 14);
    x += 212;
    for (final dpi in const ['xxhdpi', 'xhdpi', 'hdpi', 'mdpi']) {
      final im = await _png('$_res/mipmap-$dpi/ic_launcher.png');
      put(im, x, y + 10, im.width.toDouble());
      x += im.width + 14;
    }
    y += 440;

    // ---- Web ----
    label('Web  favicon 64 (1:1 ve 2x), Icon-192, Icon-512 (192 gösterim), maskable-192 (daire maske + %80 güvenli bölge çemberi)', 20, y);
    y += 30;
    x = 20;
    final fav = await _png('web/favicon.png');
    // sekme çubuğu simülasyonu: koyu ve açık
    c.drawRect(ui.Rect.fromLTWH(x - 6, y - 6, 100, 46), ui.Paint()..color = const ui.Color(0xFFF1F3F4));
    put(fav, x, y, 16);
    c.drawRect(ui.Rect.fromLTWH(x + 100, y - 6, 100, 46), ui.Paint()..color = const ui.Color(0xFF202124));
    put(fav, x + 106, y, 16);
    put(fav, x, y + 50, 64);
    put(fav, x + 80, y + 50, 128);
    x += 230;
    put(await _png('web/icons/Icon-192.png'), x, y, 192);
    x += 212;
    put(await _png('web/icons/Icon-512.png'), x, y, 192);
    x += 212;
    final mk = await _png('web/icons/Icon-maskable-192.png');
    put(mk, x, y, 192, mask: PlateShape.circle);
    c.drawCircle(ui.Offset(x + 96, y + 96), 96 * 0.8, ui.Paint()..style = ui.PaintingStyle.stroke..strokeWidth = 1.5..color = const ui.Color(0xAA7CF2B0));
    x += 212;
    put(mk, x, y, 192, mask: PlateShape.squircle);
    x += 212;
    put(mk, x, y, 192);
    label('maskable ham', x, y + 196, size: 14);
    y += 270;

    // ---- Windows ----
    label('Windows  app_icon.ico katmanları (ICO dosyasından ayrıştırıldı): 16, 24, 32, 48, 64, 128, 256 (1:1) + açık/koyu görev çubuğu', 20, y);
    y += 30;
    x = 20;
    final layers = await _icoLayers('windows/runner/resources/app_icon.ico');
    for (final im in layers) {
      put(im, x, y, im.width.toDouble());
      x += im.width + 20;
    }
    // görev çubuğu
    c.drawRect(ui.Rect.fromLTWH(x + 10, y - 6, 140, 52), ui.Paint()..color = const ui.Color(0xFF202020));
    put(layers[2], x + 24, y + 4, 32);
    put(layers[3], x + 80, y - 2, 48);
    c.drawRect(ui.Rect.fromLTWH(x + 170, y - 6, 140, 52), ui.Paint()..color = const ui.Color(0xFFF3F3F3));
    put(layers[2], x + 184, y + 4, 32);
    put(layers[3], x + 240, y - 2, 48);
    y += 280;

    // ---- Açılış ekranları ----
    label('Açılış ekranları: Android 12+ (sistem splash: koyu zemin + ic_splash_mark) · Android ≤11 (launch_background: koyu zemin + launch_logo) · iOS (LaunchImage + koyu storyboard zemini)', 20, y);
    y += 30;
    const phoneW = 300.0, phoneH = 560.0;
    final flat = spec.flatDark;
    Future<void> phone(double px0, ui.Image logo, double logoDp, double dpToPx) async {
      c.save();
      final r = ui.Rect.fromLTWH(px0, y, phoneW, phoneH);
      c.clipRRect(ui.RRect.fromRectAndRadius(r, const ui.Radius.circular(28)));
      c.drawRect(r, ui.Paint()..color = flat);
      final s = logoDp * dpToPx;
      put(logo, r.center.dx - s / 2, r.center.dy - s / 2, s);
      c.restore();
    }

    x = 20;
    await phone(x, await _png('$_res/drawable-nodpi/ic_splash_mark.png'), 288, 0.9);
    x += phoneW + 30;
    await phone(x, await _png('$_res/drawable-xxxhdpi/launch_logo.png'), 256, 0.9);
    x += phoneW + 30;
    await phone(x, await _png('$_iosLaunch/LaunchImage@3x.png'), 256, 1.0);
    x += phoneW + 30;
    // bildirim simgesi
    c.drawRect(ui.Rect.fromLTWH(x, y, 420, 40), ui.Paint()..color = const ui.Color(0xFF101418));
    final stat = _vectorPath('$_res/drawable/ic_stat_notification.xml', 24, 24).shift(ui.Offset(x + 14, y + 8));
    c.save();
    c.translate(0, 0);
    c.drawPath(stat, ui.Paint()..color = const ui.Color(0xFFFFFFFF)..isAntiAlias = true);
    c.restore();
    label('durum çubuğu 24px', x + 50, y + 8, size: 14);
    final stat4 = _vectorPath('$_res/drawable/ic_stat_notification.xml', 24, 24 * 6).shift(ui.Offset(x, y + 60));
    c.drawRect(ui.Rect.fromLTWH(x, y + 60, 144, 144), ui.Paint()..color = const ui.Color(0xFF101418));
    c.drawPath(stat4, ui.Paint()..color = const ui.Color(0xFFFFFFFF)..isAntiAlias = true);
    label('bildirim ikonu 6x', x + 156, y + 120, size: 14);
    // tam logo koyu zeminde (açılış metni)
    y += phoneH + 20;

    final pic = rec.endRecording();
    final img = await pic.toImage(w.toInt(), h.toInt());
    final bytes = await encodePng(img, alpha: false);
    File(outPath).parent.createSync(recursive: true);
    File(outPath).writeAsBytesSync(bytes);
    stdout.writeln('onizleme: $outPath  (icerik yuksekligi ~${y.toStringAsFixed(0)} / $h)');
    expect(File(outPath).existsSync(), isTrue);
  }, timeout: const Timeout(Duration(minutes: 5)));
}
