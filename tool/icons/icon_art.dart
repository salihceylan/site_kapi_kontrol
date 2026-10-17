// Güde Teknoloji uygulama ikonu / açılış görseli çizimi (yalnızca araç; uygulamaya girmez).
// Kaynak: lib/brand (vektör yapraklar + tam logo). Renk/oran sözleşmesi: tool/icons/brand_spec.json.
// Bu dosya `render_icons_test.dart` ve `preview_collage_test.dart` tarafından kullanılır.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:site_kapi_kontrol/brand/gude_logo.dart';
import 'package:site_kapi_kontrol/brand/gude_logo_data.dart';
import 'package:site_kapi_kontrol/brand/logo_model.dart';
import 'package:site_kapi_kontrol/brand/logo_palette.dart';

/// brand_spec.json içeriği.
class BrandSpec {
  BrandSpec({
    required this.flatDark,
    required this.bgCenter,
    required this.bgMid,
    required this.bgEdge,
    required this.glow,
    required this.bloom,
    required this.bloomHot,
  });

  final ui.Color flatDark, bgCenter, bgMid, bgEdge, glow, bloom, bloomHot;

  static BrandSpec load([String path = 'tool/icons/brand_spec.json']) {
    final j = jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
    ui.Color c(String k) => ui.Color(0xFF000000 | int.parse((j[k] as String).substring(1), radix: 16));
    return BrandSpec(
      flatDark: c('flatDark'),
      bgCenter: c('bgCenter'),
      bgMid: c('bgMid'),
      bgEdge: c('bgEdge'),
      glow: c('glow'),
      bloom: c('bloom'),
      bloomHot: c('bloomHot'),
    );
  }
}

/// Yaprak geometrisi (logo çizim uzayında): çizilecek şekiller, birleşik siluet ve en küçük çevreleyen daire.
class LeafGeometry {
  LeafGeometry._() {
    ui.Path? union;
    final pts = <ui.Offset>[];
    for (final s in kLogoLeaves) {
      final p = parseLogoPath(s.d);
      faces.add((p, s));
      union = union == null ? p : ui.Path.combine(ui.PathOperation.union, union, p);
      for (final m in p.computeMetrics()) {
        for (double d = 0; d <= m.length; d += 6) {
          pts.add(m.getTangentForOffset(d)!.position);
        }
      }
    }
    silhouette = union!;
    // En küçük çevreleyen daire (Badoiu-Clarkson yinelemesi).
    var c = pts.first;
    for (var i = 1; i <= 4000; i++) {
      var far = pts.first;
      var best = -1.0;
      for (final p in pts) {
        final d = (p - c).distanceSquared;
        if (d > best) {
          best = d;
          far = p;
        }
      }
      c = c + (far - c) / (i + 1.0);
    }
    var r2 = 0.0;
    for (final p in pts) {
      r2 = math.max(r2, (p - c).distanceSquared);
    }
    center = c;
    radius = math.sqrt(r2);
  }

  static final LeafGeometry instance = LeafGeometry._();

  final List<(ui.Path, LogoShape)> faces = [];
  late final ui.Path silhouette;
  late final ui.Offset center;
  late final double radius;
}

/// Bir çizimin ayarları. Boyut sınıflarına göre (küçükte daha büyük, daha az süs) [Look.forSize] seçilir.
class Look {
  const Look({
    required this.diameter,
    this.bloom = 1.0,
    this.sheen = true,
    this.sparkle = true,
    this.rim = true,
  });

  /// Yaprak işaretinin çevreleyen dairesinin çapı (tuvalin kenarına oranı).
  final double diameter;

  /// Parlama (bloom) şiddeti çarpanı; 0 kapatır.
  final double bloom;

  /// Yapraklar üstünde yumuşak speküler tarama.
  final bool sheen;

  /// Ana yaprağın ucunda küçük ışıltı yıldızı.
  final bool sparkle;

  /// Yaprak kenarında ince altın ışık çizgisi.
  final bool rim;

  /// Tam çerçeveli (kare/yuvarlak plakalı) simgeler için boyuta göre görünüm.
  static Look forSize(int px, {double scale = 1.0}) {
    if (px <= 24) return Look(diameter: 0.90 * scale, bloom: 0.6, sheen: false, sparkle: false, rim: false);
    if (px <= 40) return Look(diameter: 0.86 * scale, bloom: 0.8, sheen: false, sparkle: false, rim: false);
    if (px <= 64) return Look(diameter: 0.82 * scale, bloom: 0.9, sheen: false, sparkle: false, rim: true);
    if (px <= 128) return Look(diameter: 0.78 * scale, sparkle: false);
    return Look(diameter: 0.76 * scale);
  }
}

/// Plaka (zemin) şekli.
enum PlateShape { square, squircle, circle }

class IconArt {
  IconArt(this.spec);

  final BrandSpec spec;
  final LeafGeometry geo = LeafGeometry.instance;

  // ---------------------------------------------------------------------------------------------
  // Temel parçalar
  // ---------------------------------------------------------------------------------------------

  /// Apple "squircle"ına yakın süper-elips (n=5) yolu.
  static ui.Path squirclePath(ui.Rect r, {double n = 5.0}) {
    final path = ui.Path();
    const steps = 360;
    final a = r.width / 2, b = r.height / 2;
    for (var i = 0; i <= steps; i++) {
      final t = 2 * math.pi * i / steps;
      final ct = math.cos(t), st = math.sin(t);
      final x = a * (ct.sign) * math.pow(ct.abs(), 2 / n);
      final y = b * (st.sign) * math.pow(st.abs(), 2 / n);
      final p = ui.Offset(r.center.dx + x, r.center.dy + y);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    path.close();
    return path;
  }

  static ui.Path plateClip(PlateShape shape, ui.Rect r) {
    switch (shape) {
      case PlateShape.square:
        return ui.Path()..addRect(r);
      case PlateShape.squircle:
        return squirclePath(r);
      case PlateShape.circle:
        return ui.Path()..addOval(r);
    }
  }

  /// Koyu lacivert-siyah zemin + ortada altın radyal ışıma + üstte hafif parlak yüzey.
  void paintBackground(ui.Canvas canvas, ui.Rect r, {bool glow = true, bool sheen = true}) {
    final c = r.center;
    final s = r.width;
    canvas.drawRect(
      r,
      ui.Paint()
        ..shader = ui.Gradient.radial(
          c.translate(0, -s * 0.04),
          s * 0.78,
          [spec.bgCenter, spec.bgMid, spec.bgEdge],
          const [0.0, 0.52, 1.0],
        ),
    );
    if (glow) {
      canvas.drawRect(
        r,
        ui.Paint()
          ..blendMode = ui.BlendMode.plus
          ..shader = ui.Gradient.radial(
            c.translate(0, s * 0.01),
            s * 0.48,
            [spec.glow.withValues(alpha: 0.38), spec.glow.withValues(alpha: 0.13), spec.glow.withValues(alpha: 0.0)],
            const [0.0, 0.40, 1.0],
          ),
      );
    }
    if (sheen) {
      // Üst yarıda çok hafif beyaz-altın parlama (cam/cilalı yüzey hissi).
      canvas.drawRect(
        r,
        ui.Paint()
          ..shader = ui.Gradient.linear(
            r.topCenter,
            r.topCenter.translate(0, s * 0.55),
            [const ui.Color(0x14FFEFD0), const ui.Color(0x00FFEFD0)],
          ),
      );
    }
  }

  /// Yalnız altın ışıma (şeffaf zemin üstüne; açılış görselleri ve Android ön planı için).
  void paintGlowOnly(ui.Canvas canvas, ui.Offset center, double radius, {double strength = 1.0}) {
    final paint = ui.Paint()
      ..shader = ui.Gradient.radial(
        center,
        radius,
        [
          spec.glow.withValues(alpha: 0.46 * strength),
          spec.glow.withValues(alpha: 0.18 * strength),
          spec.glow.withValues(alpha: 0.0),
        ],
        const [0.0, 0.46, 1.0],
      );
    canvas.drawCircle(center, radius, paint);
  }

  /// Yaprak işaretini [center] etrafına, çevreleyen daire çapı [diameterPx] olacak biçimde çizer.
  void paintMark(ui.Canvas canvas, ui.Offset center, double diameterPx, Look look) {
    final k = diameterPx / (2 * geo.radius);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(k);
    canvas.translate(-geo.center.dx, -geo.center.dy);
    final unit = 2 * geo.radius; // çizim uzayında işaret çapı

    // 1) Parlama (bloom): geniş yumuşak + dar sıcak.
    if (look.bloom > 0) {
      final wide = ui.Paint()
        ..isAntiAlias = true
        ..blendMode = ui.BlendMode.plus
        ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, unit * 0.055)
        ..color = spec.bloom.withValues(alpha: 0.62 * look.bloom);
      canvas.drawPath(geo.silhouette, wide);
      final tight = ui.Paint()
        ..isAntiAlias = true
        ..blendMode = ui.BlendMode.plus
        ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, unit * 0.016)
        ..color = spec.bloomHot.withValues(alpha: 0.34 * look.bloom);
      canvas.drawPath(geo.silhouette, tight);
    }

    // 2) Yapraklar: marka gradyanları; canlılık için doygunluk/parlaklık yükseltilir.
    final boost = ui.Paint()..colorFilter = ui.ColorFilter.matrix(_vividMatrix(saturation: 1.12, gain: 1.10, lift: 3));
    canvas.saveLayer(geo.silhouette.getBounds().inflate(unit * 0.02), boost);
    for (final (path, shape) in geo.faces) {
      final paint = ui.Paint()..isAntiAlias = true;
      final fill = shape.fill;
      if (fill is LogoSolid) {
        paint.color = fill.color.withValues(alpha: fill.color.a * shape.opacity);
      } else {
        paint.shader = fill.shader(shape.opacity);
      }
      canvas.drawPath(path, paint);
    }
    canvas.restore();

    // 3) Kenar ışığı: siluet boyunca ince, sıcak altın çizgi (koyu zeminde yaprak formunu belirgin tutar).
    if (look.rim) {
      final rim = ui.Paint()
        ..isAntiAlias = true
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = unit * 0.0045
        ..strokeJoin = ui.StrokeJoin.round
        ..blendMode = ui.BlendMode.plus
        ..shader = ui.Gradient.linear(
          ui.Offset(geo.center.dx - geo.radius, geo.center.dy - geo.radius * 0.5),
          ui.Offset(geo.center.dx + geo.radius, geo.center.dy + geo.radius * 0.5),
          [spec.bloomHot.withValues(alpha: 0.55), spec.bloom.withValues(alpha: 0.40), spec.bloomHot.withValues(alpha: 0.60)],
          const [0.0, 0.5, 1.0],
        );
      canvas.drawPath(geo.silhouette, rim);
    }

    // 4) Speküler tarama: yaprak siluetine kırpılmış diyagonal yumuşak şerit + sıcak nokta.
    if (look.sheen) {
      final b = geo.silhouette.getBounds();
      canvas.saveLayer(b.inflate(unit * 0.02), ui.Paint()..blendMode = ui.BlendMode.plus);
      canvas.drawPath(geo.silhouette, ui.Paint()..color = const ui.Color(0xFFFFFFFF));
      final sweep = ui.Paint()
        ..blendMode = ui.BlendMode.srcIn
        ..shader = ui.Gradient.linear(
          ui.Offset(b.left + b.width * 0.18, b.top - b.height * 0.1),
          ui.Offset(b.left + b.width * 0.62, b.bottom + b.height * 0.1),
          [
            const ui.Color(0x00FFF2C8),
            const ui.Color(0x00FFF2C8),
            const ui.Color(0x55FFF2C8),
            const ui.Color(0x00FFF2C8),
            const ui.Color(0x00FFF2C8),
          ],
          const [0.0, 0.30, 0.48, 0.66, 1.0],
        );
      canvas.drawRect(b.inflate(unit), sweep);
      canvas.restore();
    }

    // 5) Işıltı yıldızı: en yüksek yaprağın ucunda.
    if (look.sparkle) {
      final tip = _topTip();
      _sparkle(canvas, tip, unit * 0.065);
    }
    canvas.restore();
  }

  /// En yüksek (en küçük y) yaprak noktası.
  ui.Offset _topTip() {
    ui.Offset best = geo.center;
    var by = double.infinity;
    for (final m in geo.silhouette.computeMetrics()) {
      for (double d = 0; d <= m.length; d += 2) {
        final p = m.getTangentForOffset(d)!.position;
        if (p.dy < by) {
          by = p.dy;
          best = p;
        }
      }
    }
    return best;
  }

  void _sparkle(ui.Canvas canvas, ui.Offset c, double size) {
    // Yumuşak halo
    canvas.drawCircle(
      c,
      size * 0.9,
      ui.Paint()
        ..blendMode = ui.BlendMode.plus
        ..shader = ui.Gradient.radial(c, size * 0.9, [const ui.Color(0x66FFE9B8), const ui.Color(0x00FFE6A8)]),
    );
    // Dört uçlu ince yıldız
    final star = ui.Path();
    final long = size * 1.15;
    final short = size * 0.13;
    star.moveTo(c.dx, c.dy - long);
    star.quadraticBezierTo(c.dx + short, c.dy - short, c.dx + long * 0.8, c.dy);
    star.quadraticBezierTo(c.dx + short, c.dy + short, c.dx, c.dy + long);
    star.quadraticBezierTo(c.dx - short, c.dy + short, c.dx - long * 0.8, c.dy);
    star.quadraticBezierTo(c.dx - short, c.dy - short, c.dx, c.dy - long);
    star.close();
    canvas.drawPath(
      star,
      ui.Paint()
        ..isAntiAlias = true
        ..blendMode = ui.BlendMode.plus
        ..color = const ui.Color(0xB3FFF1CF),
    );
  }

  static List<double> _vividMatrix({required double saturation, required double gain, required double lift}) {
    const lr = 0.2126, lg = 0.7152, lb = 0.0722;
    final s = saturation;
    final a = (1 - s) * lr, b = (1 - s) * lg, c = (1 - s) * lb;
    return [
      (a + s) * gain, b * gain, c * gain, 0, lift,
      a * gain, (b + s) * gain, c * gain, 0, lift,
      a * gain, b * gain, (c + s) * gain, 0, lift,
      0, 0, 0, 1, 0,
    ];
  }

  // ---------------------------------------------------------------------------------------------
  // Hazır simgeler (her biri [px] x [px] RGBA döndürür)
  // ---------------------------------------------------------------------------------------------

  /// Koyu plakalı simge. [shape]: kare (tam çerçeve), squircle ya da daire. [inset]: kenardan boşluk (kenarın oranı).
  /// [shadow]: macOS tarzı alt gölge. Plaka dışı şeffaftır (kare+inset 0 ise tamamen opaktır).
  Future<ui.Image> plate(
    int px, {
    PlateShape shape = PlateShape.square,
    double inset = 0.0,
    bool shadow = false,
    Look? look,
    double diameterScale = 1.0,
  }) async {
    final rec = ui.PictureRecorder();
    final canvas = ui.Canvas(rec);
    final s = px.toDouble();
    final plateRect = ui.Rect.fromLTWH(s * inset, s * inset, s * (1 - 2 * inset), s * (1 - 2 * inset));
    final clip = plateClip(shape, plateRect);
    if (shadow) {
      canvas.drawPath(
        clip.shift(ui.Offset(0, s * 0.012)),
        ui.Paint()
          ..color = const ui.Color(0x66000000)
          ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, s * 0.014),
      );
    }
    canvas.save();
    canvas.clipPath(clip, doAntiAlias: true);
    paintBackground(canvas, plateRect, sheen: px > 40);
    final l = look ?? Look.forSize(px, scale: diameterScale);
    // Boyut ölçüsü plaka genişliğine göre.
    paintMark(canvas, plateRect.center.translate(0, plateRect.height * 0.004), plateRect.width * l.diameter, l);
    canvas.restore();
    return rec.endRecording().toImage(px, px);
  }

  /// Şeffaf zeminli "ön plan": yapraklar + ışıma. [look].diameter tuval oranı; [glowRadius] tuval oranı (0 = ışıma yok).
  Future<ui.Image> foreground(int px, {required Look look, double glowRadius = 0.5, double glowStrength = 1.0}) async {
    final rec = ui.PictureRecorder();
    final canvas = ui.Canvas(rec);
    final s = px.toDouble();
    final c = ui.Offset(s / 2, s / 2);
    if (glowRadius > 0) paintGlowOnly(canvas, c, s * glowRadius, strength: glowStrength);
    paintMark(canvas, c, s * look.diameter, look);
    return rec.endRecording().toImage(px, px);
  }

  /// Şeffaf zeminli açılış görseli: tam logo (yapraklar + yazı) ve arkasında ışıma. Tuval kare.
  Future<ui.Image> splashLogo(int px, {double logoWidth = 0.80}) async {
    final rec = ui.PictureRecorder();
    final canvas = ui.Canvas(rec);
    final s = px.toDouble();
    final w = s * logoWidth;
    final h = w * kLogoViewHeight / kLogoViewWidth;
    final left = (s - w) / 2;
    final top = (s - h) / 2;
    // Işıma yaprak bölgesinin (logonun üst-orta kısmı) arkasında.
    final k = w / kLogoViewWidth;
    final leafCenter = ui.Offset(left + geo.center.dx * k, top + geo.center.dy * k);
    // Işıma tuval kenarına değmeden sönmeli (aksi halde kare bir kenar görünür).
    final glowR = [leafCenter.dx, s - leafCenter.dx, leafCenter.dy, s - leafCenter.dy].reduce(math.min);
    paintGlowOnly(canvas, leafCenter, glowR, strength: 0.9);
    // Yaprak parlaması (bloom) için aynı yapraklar tam logonun üstüne çizilir; tam logo yazıyı da getirir.
    canvas.save();
    canvas.translate(left, top);
    // Bloom yalnız yapraklar için: işareti tam logo koordinatında çiz.
    canvas.save();
    canvas.scale(k);
    final unit = 2 * geo.radius;
    canvas.drawPath(
      geo.silhouette,
      ui.Paint()
        ..isAntiAlias = true
        ..blendMode = ui.BlendMode.plus
        ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, unit * 0.055)
        ..color = spec.bloom.withValues(alpha: 0.55),
    );
    canvas.restore();
    GudeLogoPainter(LogoPalette.dark).paint(canvas, ui.Size(w, h));
    canvas.restore();
    return rec.endRecording().toImage(px, px);
  }
}

// ---------------------------------------------------------------------------------------------
// PNG kodlayıcı (alfa kanalı isteğe bağlı: opak simgeler RGB, alfa kanalsız yazılır)
// ---------------------------------------------------------------------------------------------

Future<Uint8List> encodePng(ui.Image image, {required bool alpha}) async {
  final w = image.width, h = image.height;
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba))!;
  final rgba = data.buffer.asUint8List();
  final bpp = alpha ? 4 : 3;
  final stride = w * bpp;
  final px = Uint8List(stride * h);
  if (alpha) {
    px.setAll(0, rgba);
  } else {
    var o = 0;
    for (var i = 0; i < w * h; i++) {
      final a = rgba[i * 4 + 3];
      if (a != 255) {
        throw StateError('Opak simgede saydam piksel var (alfa=$a, piksel=$i).');
      }
      px[o++] = rgba[i * 4];
      px[o++] = rgba[i * 4 + 1];
      px[o++] = rgba[i * 4 + 2];
    }
  }
  // Satır filtresi: her satır için en küçük mutlak toplamı veren filtre.
  final raw = BytesBuilder();
  final cand = List.generate(5, (_) => Uint8List(stride));
  for (var y = 0; y < h; y++) {
    final row = y * stride;
    for (var x = 0; x < stride; x++) {
      final cur = px[row + x];
      final left = x >= bpp ? px[row + x - bpp] : 0;
      final up = y > 0 ? px[row - stride + x] : 0;
      final ul = (y > 0 && x >= bpp) ? px[row - stride + x - bpp] : 0;
      cand[0][x] = cur;
      cand[1][x] = (cur - left) & 0xFF;
      cand[2][x] = (cur - up) & 0xFF;
      cand[3][x] = (cur - ((left + up) >> 1)) & 0xFF;
      final p = left + up - ul;
      final pa = (p - left).abs(), pb = (p - up).abs(), pc = (p - ul).abs();
      final pred = (pa <= pb && pa <= pc) ? left : (pb <= pc ? up : ul);
      cand[4][x] = (cur - pred) & 0xFF;
    }
    var bestF = 0;
    var bestSum = 1 << 60;
    for (var f = 0; f < 5; f++) {
      var sum = 0;
      final c = cand[f];
      for (var x = 0; x < stride; x++) {
        final v = c[x];
        sum += v < 128 ? v : 256 - v;
      }
      if (sum < bestSum) {
        bestSum = sum;
        bestF = f;
      }
    }
    raw.addByte(bestF);
    raw.add(cand[bestF]);
  }
  final idat = ZLibEncoder(level: 9).convert(raw.takeBytes());
  final out = BytesBuilder();
  out.add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  void chunk(String type, List<int> body) {
    final t = type.codeUnits;
    final len = ByteData(4)..setUint32(0, body.length);
    out.add(len.buffer.asUint8List());
    final tb = [...t, ...body];
    out.add(tb);
    final crc = ByteData(4)..setUint32(0, _crc32(tb));
    out.add(crc.buffer.asUint8List());
  }

  final ihdr = ByteData(13)
    ..setUint32(0, w)
    ..setUint32(4, h)
    ..setUint8(8, 8)
    ..setUint8(9, alpha ? 6 : 2)
    ..setUint8(10, 0)
    ..setUint8(11, 0)
    ..setUint8(12, 0);
  chunk('IHDR', ihdr.buffer.asUint8List());
  chunk('IDAT', idat);
  chunk('IEND', const []);
  return out.takeBytes();
}

final List<int> _crcTable = () {
  final t = List<int>.filled(256, 0);
  for (var n = 0; n < 256; n++) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
    }
    t[n] = c;
  }
  return t;
}();

int _crc32(List<int> bytes) {
  var c = 0xFFFFFFFF;
  for (final b in bytes) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
  }
  return c ^ 0xFFFFFFFF;
}
