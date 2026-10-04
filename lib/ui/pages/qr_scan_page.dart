import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:site_kapi_kontrol/styles/app_colors.dart';
import 'package:site_kapi_kontrol/ui/design/empty_state.dart';
import 'package:site_kapi_kontrol/ui/design/icon_orb.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

class QrScanPage extends StatefulWidget {
  const QrScanPage({
    super.key,
    this.accentColor,
    this.title = 'QR Kod Oku',
    this.instructionText = 'Cihazın QR kodunu kameraya gösterin.',
    this.preserveCase = false,
  });

  final Color? accentColor;
  final String title;
  final String instructionText;
  final bool preserveCase;

  @override
  State<QrScanPage> createState() => _QrScanPageState();
}

class _QrScanPageState extends State<QrScanPage> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
  );

  bool _handled = false;

  bool get _isSupportedPlatform {
    if (kIsWeb) {
      return true;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return true;
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return false;
    }
  }

  Future<void> _handleDetect(BarcodeCapture capture) async {
    if (_handled) {
      return;
    }

    final rawValue = capture.barcodes
        .map((barcode) => barcode.rawValue?.trim() ?? '')
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');

    if (rawValue.isEmpty) {
      return;
    }

    _handled = true;
    await _controller.stop();
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop(
      widget.preserveCase ? rawValue : rawValue.toUpperCase(),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = widget.accentColor ?? AppColors.primaryLight;
    // Çubuk rengi ve üstündeki başlık/ikon rengi: >= 4,5:1 (rol rengi üstünde tema ön planı bunu
    // vermez: mavi + koyu temada beyaz 3,7:1).
    final barColor = QrScanOverlay.barColorFor(accentColor);
    final onBar = QrScanOverlay.onBarColor(barColor);
    final titleStyle = (Theme.of(context).appBarTheme.titleTextStyle ??
            const TextStyle(fontWeight: FontWeight.w800))
        .copyWith(color: onBar);
    final appBar = AppBar(
      title: Text(widget.title),
      backgroundColor: barColor,
      foregroundColor: onBar,
      titleTextStyle: titleStyle,
    );

    if (!_isSupportedPlatform) {
      return Scaffold(
        appBar: appBar,
        body: const EmptyState(
          icon: Icons.qr_code_scanner_rounded,
          tone: AppTone.neutral,
          title:
              'Bu platformda kamera ile QR tarama desteklenmiyor. Şirket uygulamasını Android veya iPhone üzerinde kullanın.',
        ),
      );
    }

    return Scaffold(
      appBar: appBar,
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _handleDetect,
          ),
          // Tarama kılavuzu (yalnız boyama + metin): kamera/tarama mantığına dokunmaz.
          Positioned.fill(
            child: QrScanOverlay(
              accentColor: accentColor,
              instructionText: widget.instructionText,
            ),
          ),
        ],
      ),
    );
  }
}

/// Kamera önizlemesinin ÜSTÜNDEKİ tarama kılavuzu: üstte ipucu kapsülü ([IconOrb] + metin), ortada
/// dört köşe işaretli tarama çerçevesi.
///
/// Salt görüntüdür: kamera/tarama mantığı [QrScanPage]dedir. Dokunmayı yutmaz (`IgnorePointer`),
/// durağandır (sonsuz animasyon yok). Çerçeve genişliğin %65'idir (180-280 dp). İpucu metni yazı
/// ölçeğini izler ve satır sarar; tam metin ekran okuyucuya açıktır, çerçeve ve rozet dışlanır.
@visibleForTesting
class QrScanOverlay extends StatelessWidget {
  const QrScanOverlay({
    super.key,
    required this.accentColor,
    required this.instructionText,
  });

  final Color accentColor;
  final String instructionText;

  /// [accent] rengine karşılık gelen ton (token dışı renkte birincil).
  static AppTone toneFor(Color accent) {
    for (final tone in AppTone.values) {
      if (tone.hue == accent) return tone;
    }
    return AppTone.primary;
  }

  /// Rol rengi ([AppTone.hue]) üstünde başlık metni 4,5:1 vermez (mavi 3,7; zümrüt 2,5): ton
  /// eşleşirse koyu ucu ([AppTone.a]) kullanılır; bilinmeyen renk olduğu gibi kalır.
  static Color barColorFor(Color accent) {
    for (final tone in AppTone.values) {
      if (tone.hue == accent) return tone.a;
    }
    return accent;
  }

  /// [bar] üstünde daha okunur olan ön plan: beyaz ya da koyu slate.
  static Color onBarColor(Color bar) {
    const Color light = Colors.white;
    const Color dark = AppColors.textDark;
    double ratio(Color a, Color b) {
      final double l1 = a.computeLuminance();
      final double l2 = b.computeLuminance();
      return (math.max(l1, l2) + 0.05) / (math.min(l1, l2) + 0.05);
    }

    return ratio(light, bar) >= ratio(dark, bar) ? light : dark;
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scanBoxSize = (constraints.maxWidth * 0.65).clamp(180.0, 280.0);
          return Stack(
            children: [
              Align(
                alignment: Alignment.topCenter,
                child: QrScanHint(
                  text: instructionText,
                  tone: toneFor(accentColor),
                ),
              ),
              Center(child: QrScanFrame(size: scanBoxSize, color: accentColor)),
            ],
          );
        },
      ),
    );
  }
}

/// Üstteki ipucu kapsülü: yarı saydam koyu zemin (kamera görüntüsü üstünde >= 4,5:1 beyaz metin) +
/// ton gradyanlı küçük [IconOrb] + metin. Metin sarar (kırpılmaz); rozet dekoratiftir.
@visibleForTesting
class QrScanHint extends StatelessWidget {
  const QrScanHint({super.key, required this.text, required this.tone});

  final String text;
  final AppTone tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(AppSpace.lg),
      padding: const EdgeInsets.fromLTRB(
        AppSpace.sm,
        AppSpace.sm,
        AppSpace.lg,
        AppSpace.sm,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconOrb(icon: Icons.qr_code_scanner_rounded, tone: tone, size: 32),
          const SizedBox(width: AppSpace.md),
          Flexible(
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tarama çerçevesi: ince yarı saydam pencere çizgisi + dört kalın köşe işareti ([color]).
///
/// Köşe işaretlerinin altında ince koyu bir iz vardır: açık ya da koyu kamera görüntüsünde de
/// seçilir. Tek `CustomPaint`, kendi `RepaintBoundary`sinde, durağan; anlamsal düğüm yok.
@visibleForTesting
class QrScanFrame extends StatelessWidget {
  const QrScanFrame({super.key, required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: RepaintBoundary(
          child: CustomPaint(painter: QrScanFramePainter(color: color)),
        ),
      ),
    );
  }
}

@visibleForTesting
class QrScanFramePainter extends CustomPainter {
  const QrScanFramePainter({required this.color});

  final Color color;

  /// Köşe işareti kalınlığı ve köşe yarıçapı (dp).
  static const double stroke = 4;
  static const double radius = AppRadius.xl;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // 1) Pencere çizgisi: ince, yarı saydam beyaz.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        rect.deflate(0.75),
        const Radius.circular(radius),
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.white.withValues(alpha: 0.30),
    );

    // 2) Köşe işaretleri: çerçeve köşesini izleyen "L" kolları (kalın, yuvarlak uçlu).
    const inset = stroke / 2;
    final arm = math.max(size.shortestSide * 0.22, radius + 12);
    final l = rect.left + inset;
    final t = rect.top + inset;
    final r = rect.right - inset;
    final b = rect.bottom - inset;
    const rad = Radius.circular(radius - inset);
    final corners = Path()
      // sol üst
      ..moveTo(l, t + arm)
      ..lineTo(l, t + radius)
      ..arcToPoint(Offset(l + radius, t), radius: rad)
      ..lineTo(l + arm, t)
      // sağ üst
      ..moveTo(r - arm, t)
      ..lineTo(r - radius, t)
      ..arcToPoint(Offset(r, t + radius), radius: rad)
      ..lineTo(r, t + arm)
      // sağ alt
      ..moveTo(r, b - arm)
      ..lineTo(r, b - radius)
      ..arcToPoint(Offset(r - radius, b), radius: rad)
      ..lineTo(r - arm, b)
      // sol alt
      ..moveTo(l + arm, b)
      ..lineTo(l + radius, b)
      ..arcToPoint(Offset(l, b - radius), radius: rad)
      ..lineTo(l, b - arm);

    // Koyu iz (okunaklılık), sonra ton rengi.
    canvas.drawPath(
      corners,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = stroke + 2
        ..color = Colors.black.withValues(alpha: 0.30),
    );
    canvas.drawPath(
      corners,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = stroke
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(QrScanFramePainter old) => old.color != color;
}
