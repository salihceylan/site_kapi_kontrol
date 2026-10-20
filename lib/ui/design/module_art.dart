// Modül vitrini görselleri (Panel'deki modül kartları).
//
// Sözleşme: vitrin (Panel) ve görsel çalışması paralel yürür. [ModuleArtKind] değerleri ve sırası,
// [ModuleArt] kurucusu ve [moduleArtAccent] imzası DEĞİŞMEZ; görsel çalışması yalnız bu dosyanın
// boyamasını değiştirir. Görsel dekoratiftir (anlamsal ağaçta yok): anlamı kartın başlığı taşır.
// Boyut sabit dp'dir, yazı ölçeğinden etkilenmez.
//
// Görsel dil (Güde Teknoloji tanıtım görselleriyle aynı aile): yumuşak tonlu yuvarlak kare rozet +
// iki tonlu (duotone) yuvarlak hatlı figür + küçük bir vurgu öğesi (durum noktası / dalga / parıltı).
//
// - Tek ızgara: figürler 48 birimlik bir ızgarada çizilir ve tuvale `boyut / 48` ile ölçeklenir; hiçbir
//   çizgi/yarıçap sabit piksel değildir (32-96 dp arasında keskin kalır).
// - Tek kalem: her çizgi 1,8 birim, yuvarlak uç ve yuvarlak köşe. Tek ışık yönü: sol-üst (rozet zemini
//   sol-üstten sağ-alta koyulaşır, sol-üstte beyaz ışıma).
// - Renk rolleri ([ModuleArtColors]): `ink` ana figür çizgisi (açıkta lacivert #0F2A4A, koyuda açık),
//   `paper` figür yüzeyi, `wash` ikinci ton (türün vurgusunun soluk hâli), `accent` küçük dolu vurgu,
//   `success` durum yeşili. Ana ton rozet zeminine karşı >= 3:1'dir (WCAG 1.4.11); `module_art_test.dart`
//   bunu her tür ve her tema için hesaplar.
// - Durağandır: animasyon ve ticker yok; boyama yalnız tür ya da renkler değişince yenilenir.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

/// Vitrin kartı görsel türü. Bir modül ya da Panel'den açılan bir sayfa için.
enum ModuleArtKind {
  /// Kapı / Geçiş Kontrol (SmartKeyPass): kapı açma, kapı durumu.
  door,

  /// Kartlı geçiş.
  accessCards,

  /// Kişiler ve daireler (CRM).
  people,

  /// Duyurular.
  announcements,

  /// Aidat ve Finans (yönetici).
  finance,

  /// Borcum (sakin).
  myDebt,

  /// Belgeler.
  documents,

  /// İş takibi: arıza, bakım, talep.
  workTracking,

  /// Rezervasyon ve konsiyerj.
  reservation,

  /// Anket ve oylama.
  survey,

  /// Ziyaretçi ve kargo.
  visitor,

  /// Firma ve sözleşme takibi.
  contracts,

  /// Karar defteri / kararlar.
  decisions,

  /// Site yönetimi.
  sites,

  /// Modüller (açma, talep).
  modules,

  /// Cihazlar.
  devices,

  /// Kullanıcı yönetimi.
  users,

  /// Raporlar.
  reports,

  /// Ayarlar / platform ayarları.
  settings,

  /// Yardım ve destek.
  help,

  /// Eşleşmeyen her şey.
  generic,
}

/// Türün vurgu rengi (kart üst çizgisi, durum noktası). Açık ve koyu temada okunur tonlar.
///
/// Mavi/camgöbeği ağırlıklıdır (marka dili); amber, mercan, zümrüt ve mor yalnız ayırt edicilik için.
/// Her renk, kendi tonundaki açık rozet zeminine karşı >= 3:1 verir (testle doğrulanır).
Color moduleArtAccent(ModuleArtKind kind) {
  switch (kind) {
    case ModuleArtKind.door:
    case ModuleArtKind.accessCards:
    case ModuleArtKind.devices:
    case ModuleArtKind.sites:
      return const Color(0xFF2563EB);
    case ModuleArtKind.finance:
    case ModuleArtKind.myDebt:
    case ModuleArtKind.reports:
      return const Color(0xFF059669);
    case ModuleArtKind.announcements:
    case ModuleArtKind.survey:
      return const Color(0xFFC2610A);
    case ModuleArtKind.workTracking:
    case ModuleArtKind.visitor:
      return const Color(0xFFE11D48);
    case ModuleArtKind.reservation:
    case ModuleArtKind.decisions:
    case ModuleArtKind.contracts:
      return const Color(0xFF7C3AED);
    case ModuleArtKind.people:
    case ModuleArtKind.documents:
    case ModuleArtKind.modules:
    case ModuleArtKind.users:
    case ModuleArtKind.settings:
    case ModuleArtKind.help:
    case ModuleArtKind.generic:
      return const Color(0xFF0D9488);
  }
}

/// Bir türün belirli bir temadaki renk rolleri. Boyama bu değerlerden başka renk kullanmaz;
/// kontrast testi de aynı değerleri ölçer.
@immutable
class ModuleArtColors {
  const ModuleArtColors({
    required this.badgeTop,
    required this.badgeBottom,
    required this.ring,
    required this.edge,
    required this.sheen,
    required this.ink,
    required this.paper,
    required this.wash,
    required this.accentSoft,
    required this.accent,
    required this.success,
  });

  /// Açık tema lacivert çizgi rengi (marka: #0F2A4A).
  static const Color inkLight = Color(0xFF0F2A4A);

  /// Koyu tema çizgi rengi (soğuk beyaz).
  static const Color inkDark = Color(0xFFE6EEF9);

  /// Rozet zemini, sol-üst (ışık tarafı).
  final Color badgeTop;

  /// Rozet zemini, sağ-alt.
  final Color badgeBottom;

  /// Rozet üstündeki küçük durum noktalarının etrafındaki halka (zemin rengi).
  final Color ring;

  /// Rozetin ince kenar çizgisi.
  final Color edge;

  /// Sol-üstteki ışıma (saydam beyaz).
  final Color sheen;

  /// Ana figür tonu: çizgi ve koyu dolgu.
  final Color ink;

  /// Figürün açık yüzeyi.
  final Color paper;

  /// İkinci ton: türün vurgusunun soluk, dolgu hâli.
  final Color wash;

  /// İkinci tonun orta şiddeti (çubuk, kapak, bant).
  final Color accentSoft;

  /// Küçük dolu vurgu öğeleri (nokta, dalga, çip, onay).
  final Color accent;

  /// Durum yeşili (kapı açık, onay).
  final Color success;

  /// [kind] türünün [p] paletine göre renkleri.
  factory ModuleArtColors.resolve(ModuleArtKind kind, AppPalette p) {
    final base = moduleArtAccent(kind);
    if (!p.isDark) {
      final top = Color.alphaBlend(base.withValues(alpha: 0.06), p.surface);
      final bottom = Color.alphaBlend(base.withValues(alpha: 0.16), p.surface);
      return ModuleArtColors(
        badgeTop: top,
        badgeBottom: bottom,
        ring: Color.lerp(top, bottom, 0.6)!,
        edge: base.withValues(alpha: 0.22),
        sheen: const Color(0xA6FFFFFF),
        ink: inkLight,
        paper: p.surface,
        wash: Color.alphaBlend(base.withValues(alpha: 0.30), p.surface),
        accentSoft: Color.alphaBlend(base.withValues(alpha: 0.55), p.surface),
        accent: base,
        success: const Color(0xFF058660),
      );
    }
    final lit = Color.lerp(base, const Color(0xFFFFFFFF), 0.5)!;
    final top = Color.alphaBlend(base.withValues(alpha: 0.20), p.surface);
    final bottom = Color.alphaBlend(base.withValues(alpha: 0.32), p.surface);
    return ModuleArtColors(
      badgeTop: top,
      badgeBottom: bottom,
      ring: Color.lerp(top, bottom, 0.6)!,
      edge: lit.withValues(alpha: 0.28),
      sheen: const Color(0x1AFFFFFF),
      ink: inkDark,
      paper: Color.alphaBlend(const Color(0x24FFFFFF), bottom),
      wash: Color.alphaBlend(lit.withValues(alpha: 0.34), bottom),
      accentSoft: Color.alphaBlend(lit.withValues(alpha: 0.42), bottom),
      accent: lit,
      success: const Color(0xFF34D399),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ModuleArtColors &&
      other.badgeTop == badgeTop &&
      other.badgeBottom == badgeBottom &&
      other.ring == ring &&
      other.edge == edge &&
      other.sheen == sheen &&
      other.ink == ink &&
      other.paper == paper &&
      other.wash == wash &&
      other.accentSoft == accentSoft &&
      other.accent == accent &&
      other.success == success;

  @override
  int get hashCode => Object.hash(
    badgeTop,
    badgeBottom,
    ring,
    edge,
    sheen,
    ink,
    paper,
    wash,
    accentSoft,
    accent,
    success,
  );
}

/// Modül kartı görseli. [size] kenar uzunluğu (dp), en az 32.
class ModuleArt extends StatelessWidget {
  const ModuleArt({super.key, required this.kind, this.size = 64})
    : assert(size >= 32, 'ModuleArt en az 32 dp olmalı');

  final ModuleArtKind kind;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = ModuleArtColors.resolve(kind, context.palette);
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: SizedBox.square(
          dimension: size,
          child: CustomPaint(
            painter: ModuleArtPainter(kind: kind, colors: colors),
            isComplex: true,
          ),
        ),
      ),
    );
  }
}

/// [ModuleArt] boyayıcısı: rozet + tür figürü. Kare tuvale çizer (kısa kenar esas alınır).
class ModuleArtPainter extends CustomPainter {
  const ModuleArtPainter({required this.kind, required this.colors});

  final ModuleArtKind kind;
  final ModuleArtColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    if (s <= 0) return;
    final unit = s / _grid;
    final rect = Offset.zero & Size.square(s);
    final badge = RRect.fromRectAndRadius(rect, Radius.circular(s * 0.28));

    // Rozet zemini: sol-üstten sağ-alta tonlu gradyan, sol-üstte beyaz ışıma, ince kenar.
    canvas.drawRRect(
      badge,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[colors.badgeTop, colors.badgeBottom],
        ).createShader(rect),
    );
    canvas.drawRRect(
      badge,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.6, -0.75),
          radius: 0.95,
          colors: <Color>[colors.sheen, colors.sheen.withValues(alpha: 0)],
        ).createShader(rect),
    );
    canvas.drawRRect(
      badge.deflate(unit * 0.3),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = unit * 0.6
        ..color = colors.edge,
    );

    canvas.save();
    canvas.scale(unit);
    final brush = _Brush(canvas, colors, detailed: s >= 44);
    switch (kind) {
      case ModuleArtKind.door:
        _drawDoor(brush);
      case ModuleArtKind.accessCards:
        _drawAccessCards(brush);
      case ModuleArtKind.people:
        _drawPeople(brush);
      case ModuleArtKind.announcements:
        _drawAnnouncements(brush);
      case ModuleArtKind.finance:
        _drawFinance(brush);
      case ModuleArtKind.myDebt:
        _drawMyDebt(brush);
      case ModuleArtKind.documents:
        _drawDocuments(brush);
      case ModuleArtKind.workTracking:
        _drawWorkTracking(brush);
      case ModuleArtKind.reservation:
        _drawReservation(brush);
      case ModuleArtKind.survey:
        _drawSurvey(brush);
      case ModuleArtKind.visitor:
        _drawVisitor(brush);
      case ModuleArtKind.contracts:
        _drawContracts(brush);
      case ModuleArtKind.decisions:
        _drawDecisions(brush);
      case ModuleArtKind.sites:
        _drawSites(brush);
      case ModuleArtKind.modules:
        _drawModules(brush);
      case ModuleArtKind.devices:
        _drawDevices(brush);
      case ModuleArtKind.users:
        _drawUsers(brush);
      case ModuleArtKind.reports:
        _drawReports(brush);
      case ModuleArtKind.settings:
        _drawSettings(brush);
      case ModuleArtKind.help:
        _drawHelp(brush);
      case ModuleArtKind.generic:
        _drawGeneric(brush);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(ModuleArtPainter oldDelegate) =>
      oldDelegate.kind != kind || oldDelegate.colors != colors;
}

// ---------------------------------------------------------------------------------------------
// Çizim araçları (48 birimlik ızgara)
// ---------------------------------------------------------------------------------------------

/// Tasarım ızgarasının kenarı (birim). Tuval `boyut / 48` ile ölçeklenir.
const double _grid = 48;

/// Tek kalem kalınlığı (birim): tüm türlerde aynı.
const double _pen = 1.8;

double _rad(double degrees) => degrees * math.pi / 180;

Path _rr(double l, double t, double r, double b, double radius) =>
    Path()..addRRect(RRect.fromLTRBR(l, t, r, b, Radius.circular(radius)));

Path _oval(double cx, double cy, double rx, double ry) => Path()
  ..addOval(
    Rect.fromCenter(center: Offset(cx, cy), width: rx * 2, height: ry * 2),
  );

Path _circle(double cx, double cy, double r) => _oval(cx, cy, r, r);

/// Merkez (cx, cy), yarıçap r; [from] derece (0 = sağ, saat yönü artar), [sweep] derece.
Path _arc(double cx, double cy, double r, double from, double sweep) => Path()
  ..addArc(
    Rect.fromCircle(center: Offset(cx, cy), radius: r),
    _rad(from),
    _rad(sweep),
  );

/// Köşeleri [radius] ile yuvarlatılmış, verilen noktalardan geçen kapalı çokgen.
Path _poly(List<Offset> points) {
  final path = Path()..moveTo(points.first.dx, points.first.dy);
  for (final pt in points.skip(1)) {
    path.lineTo(pt.dx, pt.dy);
  }
  return path..close();
}

/// Dişli: [teeth] dişli, dış yarıçap [ro], diş dibi yarıçapı [ri].
Path _gear(double cx, double cy, double ro, double ri, int teeth) {
  final step = 2 * math.pi / teeth;
  Offset at(double angle, double r) =>
      Offset(cx + r * math.cos(angle), cy + r * math.sin(angle));
  final path = Path();
  for (var i = 0; i < teeth; i++) {
    final a = i * step - math.pi / 2;
    final base1 = at(a - step * 0.30, ri);
    final tip1 = at(a - step * 0.17, ro);
    final tip2 = at(a + step * 0.17, ro);
    final base2 = at(a + step * 0.30, ri);
    if (i == 0) {
      path.moveTo(base1.dx, base1.dy);
    } else {
      path.arcToPoint(base1, radius: Radius.circular(ri));
    }
    path
      ..lineTo(tip1.dx, tip1.dy)
      ..lineTo(tip2.dx, tip2.dy)
      ..lineTo(base2.dx, base2.dy);
  }
  path.arcToPoint(
    at(-math.pi / 2 - step * 0.30, ri),
    radius: Radius.circular(ri),
  );
  return path..close();
}

/// Dört uçlu parıltı.
Path _sparkle(double cx, double cy, double r) => Path()
  ..moveTo(cx, cy - r)
  ..quadraticBezierTo(cx + r * 0.12, cy - r * 0.12, cx + r, cy)
  ..quadraticBezierTo(cx + r * 0.12, cy + r * 0.12, cx, cy + r)
  ..quadraticBezierTo(cx - r * 0.12, cy + r * 0.12, cx - r, cy)
  ..quadraticBezierTo(cx - r * 0.12, cy - r * 0.12, cx, cy - r)
  ..close();

/// Omuzlu kişi büstü (baş + yuvarlak omuzlu gövde). [bottom] gövdenin düz tabanıdır.
class _Bust {
  const _Bust(
    this.cx,
    this.headY,
    this.headR,
    this.bodyW,
    this.bodyTop,
    this.bottom,
  );

  final double cx;
  final double headY;
  final double headR;
  final double bodyW;
  final double bodyTop;
  final double bottom;

  Path get head => _circle(cx, headY, headR);

  Path get body {
    final l = cx - bodyW / 2;
    final r = cx + bodyW / 2;
    final k = math.min(bodyW * 0.36, (bottom - bodyTop) * 0.8);
    return Path()
      ..moveTo(l, bottom)
      ..lineTo(l, bodyTop + k)
      ..quadraticBezierTo(l, bodyTop, l + k, bodyTop)
      ..lineTo(r - k, bodyTop)
      ..quadraticBezierTo(r, bodyTop, r, bodyTop + k)
      ..lineTo(r, bottom)
      ..close();
  }
}

/// Fırça: tüm türler aynı kalemle (ink, 2 birim, yuvarlak uç/köşe) çizer.
class _Brush {
  _Brush(this.canvas, this.c, {required this.detailed});

  final Canvas canvas;
  final ModuleArtColors c;

  /// Küçük (< 44 dp) boyutlarda ince ayrıntılar (kilit simgesi, minik noktalar) atlanır.
  final bool detailed;

  Paint _fill(Color color) => Paint()..color = color;

  Paint _line(Color color, double width) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..color = color;

  void fill(Path path, Color color) => canvas.drawPath(path, _fill(color));

  void stroke(Path path, {Color? color, double width = _pen}) =>
      canvas.drawPath(path, _line(color ?? c.ink, width));

  /// Dolgu + ink çizgi.
  void shape(Path path, Color color) {
    fill(path, color);
    stroke(path);
  }

  void paper(Path path) => shape(path, c.paper);

  void wash(Path path) => shape(path, c.wash);

  void soft(Path path) => shape(path, c.accentSoft);

  void dot(double x, double y, double r, Color color) =>
      canvas.drawCircle(Offset(x, y), r, _fill(color));

  /// Zemin renginde halkalı küçük dolu rozet (durum noktası).
  void badge(double cx, double cy, double r, Color color) {
    dot(cx, cy, r + 1.7, c.ring);
    dot(cx, cy, r, color);
  }

  /// Çizgiyi/şekli yerel koordinatlarda çizmek için: [origin] etrafında [degrees] döndürür.
  void rotated(Offset origin, double degrees, void Function() draw) {
    canvas
      ..save()
      ..translate(origin.dx, origin.dy)
      ..rotate(_rad(degrees));
    draw();
    canvas.restore();
  }

  /// Şekli [region] ile kırpar.
  void clipped(Path region, void Function() draw) {
    canvas
      ..save()
      ..clipPath(region);
    draw();
    canvas.restore();
  }
}

// ---------------------------------------------------------------------------------------------
// Türler
// ---------------------------------------------------------------------------------------------

/// Kapı + yeşil "açık kilit" noktası.
void _drawDoor(_Brush p) {
  final c = p.c;
  p.paper(_rr(10, 8, 30, 39.5, 2.6));
  p.fill(_rr(13.6, 11.6, 24.4, 22.2, 1.2), c.wash);
  p.fill(_rr(13.6, 25.4, 24.4, 36, 1.2), c.wash);
  p.dot(27.1, 24, 1.25, c.ink);
  p.badge(34, 31.6, 6.4, c.success);
  if (p.detailed) {
    p.fill(_rr(31.2, 31.1, 36.8, 35.5, 1.1), const Color(0xFFFFFFFF));
    p.stroke(
      Path()
        ..moveTo(32.8, 31.1)
        ..lineTo(32.8, 29.3)
        ..arcToPoint(
          const Offset(36.2, 29.3),
          radius: const Radius.circular(1.7),
        ),
      color: const Color(0xFFFFFFFF),
      width: 1.5,
    );
  }
}

/// Arkada soluk kart, önde çipli kart ve temassız dalga.
void _drawAccessCards(_Brush p) {
  final c = p.c;
  p.wash(_rr(13, 9.5, 40, 28.5, 3.2));
  p.paper(_rr(8, 17.5, 35, 36.5, 3.2));
  p.fill(_rr(12, 22, 18.5, 28.2, 1.4), c.accent);
  p.stroke(
    Path()
      ..moveTo(12, 32)
      ..lineTo(19.5, 32),
  );
  for (final r in const <double>[3.6, 6.8, 10]) {
    p.stroke(_arc(21.5, 27, r, -42, 84), color: c.accent);
  }
}

/// Ev siluetinin içinde iki kişi.
void _drawPeople(_Brush p) {
  final c = p.c;
  p.wash(
    _poly(const <Offset>[
      Offset(8.5, 20.5),
      Offset(24, 7.5),
      Offset(39.5, 20.5),
      Offset(39.5, 39.5),
      Offset(8.5, 39.5),
    ]),
  );
  const back = _Bust(29.6, 25.6, 3.9, 12.4, 31.4, 39.5);
  const front = _Bust(18.4, 25.6, 3.9, 12.4, 31.4, 39.5);
  p.shape(back.body, c.accentSoft);
  p.shape(back.head, c.accentSoft);
  p.paper(front.body);
  p.paper(front.head);
}

/// Megafon + ses dalgaları.
void _drawAnnouncements(_Brush p) {
  final c = p.c;
  // sap
  p.paper(
    Path()
      ..moveTo(13.8, 28.5)
      ..lineTo(15.8, 36.4)
      ..quadraticBezierTo(16.1, 37.5, 17.3, 37.5)
      ..lineTo(18.4, 37.5)
      ..quadraticBezierTo(19.6, 37.5, 19.4, 36.3)
      ..lineTo(18.2, 28.5),
  );
  // boru
  final horn = Path()
    ..moveTo(14.5, 19.2)
    ..lineTo(26.4, 11.6)
    ..quadraticBezierTo(28.4, 10.4, 28.4, 12.7)
    ..lineTo(28.4, 35.3)
    ..quadraticBezierTo(28.4, 37.6, 26.4, 36.4)
    ..lineTo(14.5, 28.8)
    ..close();
  p.wash(horn);
  p.paper(_rr(7.6, 19.2, 14.6, 28.8, 2.4));
  for (final r in const <double>[5.6, 10]) {
    p.stroke(_arc(29.2, 24, r, -38, 76), color: c.accent);
  }
}

/// Madeni para yığını + yükselen çubuklar.
void _drawFinance(_Brush p) {
  final c = p.c;
  const rx = 7.0;
  const ry = 3.0;
  const thick = 3.8;
  const shifts = <double>[0, 1.5, -0.7];
  for (var i = 0; i < 3; i++) {
    final cx = 14.6 + shifts[i];
    final topY = 31.8 - i * 4.6;
    final silhouette = ui.Path.combine(
      ui.PathOperation.union,
      ui.Path.combine(
        ui.PathOperation.union,
        _oval(cx, topY, rx, ry),
        _oval(cx, topY + thick, rx, ry),
      ),
      Path()..addRect(Rect.fromLTRB(cx - rx, topY, cx + rx, topY + thick)),
    );
    p.paper(silhouette);
    p.shape(_oval(cx, topY, rx, ry), i == 2 ? c.accentSoft : c.wash);
    if (i == 2) {
      p.stroke(_oval(cx, topY, rx * 0.5, ry * 0.42), color: c.accent);
    }
  }
  p.fill(_rr(26.4, 30.5, 29.8, 38.5, 1.3), c.accentSoft);
  p.fill(_rr(31.5, 24.5, 34.9, 38.5, 1.3), c.accent);
  p.fill(_rr(36.6, 17.5, 40, 38.5, 1.3), c.ink);
}

/// Makbuz (tırtıklı alt kenar) + ₺ işareti.
void _drawMyDebt(_Brush p) {
  final c = p.c;
  final receipt = Path()
    ..moveTo(12.5, 10)
    ..quadraticBezierTo(12.5, 7.5, 15, 7.5)
    ..lineTo(33, 7.5)
    ..quadraticBezierTo(35.5, 7.5, 35.5, 10)
    ..lineTo(35.5, 39.5)
    ..lineTo(31.7, 36.4)
    ..lineTo(27.9, 39.5)
    ..lineTo(24.1, 36.4)
    ..lineTo(20.3, 39.5)
    ..lineTo(16.5, 36.4)
    ..lineTo(12.5, 39.5)
    ..close();
  p.paper(receipt);
  p.stroke(
    Path()
      ..moveTo(17.5, 12.8)
      ..lineTo(30.5, 12.8),
  );
  p.canvas
    ..save()
    ..translate(24, 25);
  p.stroke(
    Path()
      ..moveTo(-2.6, -6)
      ..lineTo(-2.6, 2.6)
      ..quadraticBezierTo(-2.6, 6.6, 1.6, 6.6)
      ..lineTo(3.2, 6.6),
    color: c.accent,
  );
  p.stroke(
    Path()
      ..moveTo(-5.8, -0.8)
      ..lineTo(5.6, -4.4)
      ..moveTo(-5.8, 2.4)
      ..lineTo(5.6, -1.2),
    color: c.accent,
  );
  p.canvas.restore();
}

/// Klasör + dışarı çıkan belge.
void _drawDocuments(_Brush p) {
  p.wash(
    Path()
      ..moveTo(8, 13.5)
      ..quadraticBezierTo(8, 10.5, 11, 10.5)
      ..lineTo(18.6, 10.5)
      ..lineTo(22, 14.6)
      ..lineTo(37, 14.6)
      ..quadraticBezierTo(40, 14.6, 40, 17.6)
      ..lineTo(40, 34.6)
      ..quadraticBezierTo(40, 38, 37, 38)
      ..lineTo(11, 38)
      ..quadraticBezierTo(8, 38, 8, 34.6)
      ..close(),
  );
  p.paper(_rr(13, 7.6, 31, 27, 1.8));
  p.stroke(
    Path()
      ..moveTo(17.2, 13.2)
      ..lineTo(26.8, 13.2)
      ..moveTo(17.2, 18)
      ..lineTo(23.6, 18),
  );
  p.soft(
    Path()
      ..moveTo(8, 27)
      ..quadraticBezierTo(8, 24, 11, 24)
      ..lineTo(37, 24)
      ..quadraticBezierTo(40, 24, 40, 27)
      ..lineTo(40, 35)
      ..quadraticBezierTo(40, 38, 37, 38)
      ..lineTo(11, 38)
      ..quadraticBezierTo(8, 38, 8, 35)
      ..close(),
  );
}

/// İngiliz anahtarı + dişli.
void _drawWorkTracking(_Brush p) {
  final c = p.c;
  var wrench = ui.Path.combine(
    ui.PathOperation.union,
    _circle(0, -10.2, 6.6),
    _rr(-2.8, -6, 2.8, 13.5, 2.8),
  );
  wrench = ui.Path.combine(
    ui.PathOperation.difference,
    wrench,
    _rr(-2.6, -21, 2.6, -11.6, 1.3),
  );
  p.rotated(const Offset(22.5, 25), 45, () => p.paper(wrench));
  p.shape(_gear(33.4, 33.4, 7.3, 5.5, 8), c.accentSoft);
  p.shape(_circle(33.4, 33.4, 2.3), c.paper);
}

/// Takvim + onay.
void _drawReservation(_Brush p) {
  final c = p.c;
  final body = _rr(8.5, 11, 39.5, 39.5, 4.5);
  p.fill(body, c.paper);
  p.clipped(body, () => p.fill(_rr(8, 10, 40, 20.5, 0), c.accentSoft));
  p.stroke(body);
  p.stroke(
    Path()
      ..moveTo(16.5, 7.4)
      ..lineTo(16.5, 14)
      ..moveTo(31.5, 7.4)
      ..lineTo(31.5, 14),
  );
  if (p.detailed) {
    for (final y in const <double>[26.2, 32.4]) {
      for (final x in const <double>[14.4, 20.4]) {
        p.dot(x, y, 1.3, c.ink);
      }
    }
  }
  p.badge(31.6, 31.4, 7, c.success);
  p.stroke(
    Path()
      ..moveTo(28, 31.6)
      ..lineTo(30.6, 34.2)
      ..lineTo(35.4, 28.4),
    color: const Color(0xFFFFFFFF),
    width: 1.8,
  );
}

/// Oy sandığı + onaylı oy pusulası.
void _drawSurvey(_Brush p) {
  final c = p.c;
  p.paper(_rr(15.5, 6.5, 32.5, 28, 2));
  p.stroke(
    Path()
      ..moveTo(19.6, 13.6)
      ..lineTo(22.2, 16.2)
      ..lineTo(27.6, 10.8),
    color: c.accent,
  );
  p.stroke(
    Path()
      ..moveTo(19.6, 21)
      ..lineTo(28.4, 21),
  );
  p.wash(_rr(8, 24.5, 40, 40, 3.2));
  p.fill(_rr(17.5, 28.3, 30.5, 36.2, 1.8), c.paper);
  p.stroke(
    Path()
      ..moveTo(20.6, 32.4)
      ..lineTo(27.4, 32.4),
  );
}

/// Kargo kutusu + kişi.
void _drawVisitor(_Brush p) {
  final c = p.c;
  const person = _Bust(33.5, 16.5, 4.6, 14, 23.4, 39);
  p.paper(person.body);
  p.paper(person.head);
  p.paper(_rr(7.5, 23.5, 28.5, 39.5, 1.8));
  p.fill(_rr(14.2, 23.5, 21.8, 31.5, 0), c.accent);
  p.wash(_rr(6, 18, 30, 25.2, 1.8));
  p.fill(_rr(14.2, 18.9, 21.8, 24.3, 0), c.accent);
}

/// İmzalı sözleşme + kalem.
void _drawContracts(_Brush p) {
  final c = p.c;
  final doc = Path()
    ..moveTo(10, 10)
    ..quadraticBezierTo(10, 7.5, 12.5, 7.5)
    ..lineTo(24, 7.5)
    ..lineTo(32, 15.5)
    ..lineTo(32, 37)
    ..quadraticBezierTo(32, 39.5, 29.5, 39.5)
    ..lineTo(12.5, 39.5)
    ..quadraticBezierTo(10, 39.5, 10, 37)
    ..close();
  p.paper(doc);
  p.soft(
    Path()
      ..moveTo(24, 7.5)
      ..lineTo(24, 13)
      ..quadraticBezierTo(24, 15.5, 26.5, 15.5)
      ..lineTo(32, 15.5)
      ..close(),
  );
  p.stroke(
    Path()
      ..moveTo(14.6, 20.4)
      ..lineTo(27.4, 20.4)
      ..moveTo(14.6, 25)
      ..lineTo(22.6, 25),
  );
  p.stroke(
    Path()
      ..moveTo(14.4, 34)
      ..cubicTo(16, 29.6, 17.6, 36.2, 19.4, 32)
      ..cubicTo(20.4, 29.8, 21.8, 33.6, 24, 32),
    color: c.accent,
  );
  p.rotated(const Offset(33.6, 27.5), 45, () {
    p.shape(_rr(-2.6, -10.5, 2.6, 4.6, 1.2), c.accent);
    p.paper(
      _poly(const <Offset>[
        Offset(-2.6, 4.6),
        Offset(2.6, 4.6),
        Offset(0, 9.4),
      ]),
    );
  });
}

/// Karar defteri (açık defter) + tokmak.
void _drawDecisions(_Brush p) {
  final c = p.c;
  final book = Path()
    ..moveTo(7.5, 31.5)
    ..quadraticBezierTo(15.8, 29.4, 24, 32.6)
    ..quadraticBezierTo(32.2, 29.4, 40.5, 31.5)
    ..lineTo(40.5, 38.8)
    ..quadraticBezierTo(32.2, 36.8, 24, 40)
    ..quadraticBezierTo(15.8, 36.8, 7.5, 38.8)
    ..close();
  p.wash(book);
  p.stroke(
    Path()
      ..moveTo(24, 32.6)
      ..lineTo(24, 40),
  );
  p.rotated(const Offset(25.5, 14.5), -45, () {
    p.paper(_rr(-1.8, 4, 1.8, 15.2, 1.8));
    p.paper(_rr(-9.2, -4.6, 9.2, 4.6, 2));
    p.fill(_rr(-3.1, -4.6, 3.1, 4.6, 0), c.accent);
    p.stroke(
      Path()
        ..moveTo(-3.1, -4.6)
        ..lineTo(-3.1, 4.6)
        ..moveTo(3.1, -4.6)
        ..lineTo(3.1, 4.6),
    );
  });
}

/// Apartman blokları.
void _drawSites(_Brush p) {
  final c = p.c;
  p.wash(_rr(7, 19, 17, 39.5, 1.8));
  p.wash(_rr(31, 23, 41, 39.5, 1.8));
  p.paper(_rr(16, 8, 32, 39.5, 1.8));
  for (final y in const <double>[12.2, 17.8, 23.4, 29]) {
    for (final x in const <double>[19.6, 25.6]) {
      p.fill(_rr(x, y, x + 2.8, y + 3, 0.7), c.accent);
    }
  }
  p.fill(_rr(21.6, 33.6, 26.4, 39.5, 0.8), c.ink);
  for (final y in const <double>[23.5, 29.5]) {
    p.fill(_rr(10.6, y, 13.4, y + 3, 0.7), c.accent);
  }
  for (final y in const <double>[27.5, 33.5]) {
    p.fill(_rr(34.6, y, 37.4, y + 3, 0.7), c.accent);
  }
}

/// Izgara bloklar + eklenen yeni blok.
void _drawModules(_Brush p) {
  p.wash(_rr(8, 8, 22, 22, 3.4));
  p.paper(_rr(26, 8, 40, 22, 3.4));
  p.paper(_rr(8, 26, 22, 40, 3.4));
  p.shape(_rr(26, 26, 40, 40, 3.4), p.c.accent);
  p.stroke(
    Path()
      ..moveTo(33, 29.6)
      ..lineTo(33, 36.4)
      ..moveTo(29.6, 33)
      ..lineTo(36.4, 33),
    color: const Color(0xFFFFFFFF),
  );
}

/// Yönlendirici/cihaz + kablosuz dalga.
void _drawDevices(_Brush p) {
  final c = p.c;
  p.paper(_rr(8.5, 29.5, 39.5, 40, 3.4));
  p.dot(14.8, 34.8, 1.5, c.accent);
  p.dot(20, 34.8, 1.5, c.success);
  p.stroke(
    Path()
      ..moveTo(28, 34.8)
      ..lineTo(34.2, 34.8),
  );
  p.dot(24, 24.5, 2.1, c.ink);
  for (final r in const <double>[6.6, 11.6]) {
    p.stroke(_arc(24, 24.5, r, -135, 90), color: c.accent);
  }
}

/// Kişi + dişli.
void _drawUsers(_Brush p) {
  final c = p.c;
  const bust = _Bust(19.5, 17, 5.6, 21, 26.4, 39);
  p.paper(bust.body);
  p.paper(bust.head);
  p.shape(_gear(33.6, 32.8, 7.6, 5.8, 8), c.accentSoft);
  p.shape(_circle(33.6, 32.8, 2.4), c.paper);
}

/// Grafik kartı: çubuklar + eğilim çizgisi.
void _drawReports(_Brush p) {
  final c = p.c;
  p.paper(_rr(8, 8, 40, 40, 4));
  p.fill(_rr(12.4, 28, 17, 35.5, 1.2), c.accentSoft);
  p.fill(_rr(19, 24, 23.6, 35.5, 1.2), c.accentSoft);
  p.fill(_rr(25.6, 26.4, 30.2, 35.5, 1.2), c.accentSoft);
  p.fill(_rr(32.2, 20.5, 36.8, 35.5, 1.2), c.accent);
  p.stroke(
    Path()
      ..moveTo(14.7, 22.5)
      ..lineTo(21.3, 17.5)
      ..lineTo(27.9, 20)
      ..lineTo(34.5, 13.6),
  );
}

/// Dişli.
void _drawSettings(_Brush p) {
  final c = p.c;
  p.paper(_gear(24, 24, 15.2, 11.8, 8));
  p.shape(_circle(24, 24, 5.2), c.accentSoft);
}

/// Konuşma balonu + soru işareti.
void _drawHelp(_Brush p) {
  final c = p.c;
  final bubble = Path()
    ..moveTo(14, 8.5)
    ..lineTo(34, 8.5)
    ..quadraticBezierTo(40, 8.5, 40, 14.5)
    ..lineTo(40, 26)
    ..quadraticBezierTo(40, 32, 34, 32)
    ..lineTo(21, 32)
    ..lineTo(14.2, 38.8)
    ..quadraticBezierTo(13, 40, 13, 38.3)
    ..lineTo(13, 32)
    ..quadraticBezierTo(8, 31.2, 8, 26)
    ..lineTo(8, 14.5)
    ..quadraticBezierTo(8, 8.5, 14, 8.5)
    ..close();
  p.paper(bubble);
  p.stroke(
    Path()
      ..moveTo(19.6, 18.4)
      ..cubicTo(19.6, 12.6, 28.4, 12.6, 28.4, 18.2)
      ..cubicTo(28.4, 21.6, 24, 21.6, 24, 25),
    color: c.accent,
  );
  p.dot(24, 28.6, 1.4, c.accent);
}

/// Izgara + parıltı (eşleşmeyen her şey için nötr, canlı bir görsel).
void _drawGeneric(_Brush p) {
  final c = p.c;
  p.soft(_rr(8, 8, 22, 22, 3.4));
  p.paper(_rr(26, 8, 40, 22, 3.4));
  p.paper(_rr(8, 26, 22, 40, 3.4));
  p.paper(_rr(26, 26, 40, 40, 3.4));
  final spark = _sparkle(36.8, 11.2, 5.2);
  p.stroke(spark, color: c.ring, width: 3.6);
  p.fill(spark, c.accent);
}
