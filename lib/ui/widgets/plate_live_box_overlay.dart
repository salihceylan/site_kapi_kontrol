import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/services/plate_recognition_engine.dart';
import 'package:site_kapi_kontrol/ui/design/license_plate.dart';

/// Canlı RTSP / JPEG kamera görüntüsü üzerinde ONNX plaka dedektörünün bulduğu
/// sınırlayıcı kutuyu (`BoxFit.cover` geometrisine tam hizalı) ve okunan plaka etiketini çizer.
class PlateLiveBoxOverlay extends StatelessWidget {
  const PlateLiveBoxOverlay({
    super.key,
    required this.overlay,
    this.decisionType,
  });

  final PlateLiveOverlay overlay;
  final PlateDecisionType? decisionType;

  Color get _accentColor => switch (decisionType) {
        PlateDecisionType.acildi => const Color(0xFF10B981),
        PlateDecisionType.karaListe => const Color(0xFFEF4444),
        PlateDecisionType.red => const Color(0xFFF97316),
        PlateDecisionType.tanimsiz => const Color(0xFFF59E0B),
        null => const Color(0xFF10B981),
      };

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cw = constraints.maxWidth;
          final ch = constraints.maxHeight;
          if (!cw.isFinite || !ch.isFinite || cw < 40 || ch < 30) {
            return const SizedBox.shrink();
          }

          final sa = overlay.sourceAspectRatio > 0.2 ? overlay.sourceAspectRatio : (16.0 / 9.0);
          final ca = cw / ch;

          final double rw;
          final double rh;
          final double ox;
          final double oy;
          if (ca > sa) {
            rw = cw;
            rh = cw / sa;
            ox = 0.0;
            oy = (ch - rh) * 0.5;
          } else {
            rh = ch;
            rw = ch * sa;
            ox = (cw - rw) * 0.5;
            oy = 0.0;
          }

          final nb = overlay.normalizedBox;
          final left = (ox + nb.left * rw).clamp(2.0, math.max(2.0, cw - 16.0)).toDouble();
          final top = (oy + nb.top * rh).clamp(2.0, math.max(2.0, ch - 14.0)).toDouble();
          final right = (ox + nb.right * rw).clamp(left + 14.0, math.max(left + 14.0, cw - 2.0)).toDouble();
          final bottom = (oy + nb.bottom * rh).clamp(top + 10.0, math.max(top + 10.0, ch - 2.0)).toDouble();

          final rect = Rect.fromLTRB(left, top, right, bottom);
          final accent = _accentColor;
          final confPct = (overlay.confidence * 100).round().clamp(1, 99);
          final formattedPlate = LicensePlateBadge.format(overlay.plate);

          final placeAbove = top >= 30.0;
          final pillTop = placeAbove ? (top - 26.0) : math.min(bottom + 4.0, ch - 26.0);
          final pillLeft = left.clamp(4.0, math.max(4.0, cw - 150.0)).toDouble();

          return Stack(
            fit: StackFit.expand,
            children: <Widget>[
              CustomPaint(
                painter: _PlateBoxPainter(rect: rect, color: accent),
              ),
              Positioned(
                left: pillLeft,
                top: pillTop.clamp(2.0, math.max(2.0, ch - 24.0)).toDouble(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: math.max(60.0, cw - pillLeft - 4.0)),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A).withValues(alpha: 0.90),
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(color: accent, width: 1.4),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.45),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFF003399),
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: const Text(
                            'TR',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 8.5,
                              fontWeight: FontWeight.w900,
                              height: 1.1,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            '$formattedPlate  %$confPct',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.4,
                              height: 1.1,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PlateBoxPainter extends CustomPainter {
  const _PlateBoxPainter({required this.rect, required this.color});

  final Rect rect;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final fillPaint = Paint()
      ..color = color.withValues(alpha: 0.14)
      ..style = PaintingStyle.fill;

    final thinBorderPaint = Paint()
      ..color = color.withValues(alpha: 0.65)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;

    final cornerPaint = Paint()
      ..color = color
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(4));
    canvas.drawRRect(rrect, fillPaint);
    canvas.drawRRect(rrect, thinBorderPaint);

    final cornerW = math.min(16.0, rect.width * 0.28);
    final cornerH = math.min(12.0, rect.height * 0.35);

    // Sol üst
    canvas.drawLine(Offset(rect.left, rect.top + cornerH), rect.topLeft, cornerPaint);
    canvas.drawLine(rect.topLeft, Offset(rect.left + cornerW, rect.top), cornerPaint);

    // Sağ üst
    canvas.drawLine(Offset(rect.right - cornerW, rect.top), rect.topRight, cornerPaint);
    canvas.drawLine(rect.topRight, Offset(rect.right, rect.top + cornerH), cornerPaint);

    // Sol alt
    canvas.drawLine(Offset(rect.left, rect.bottom - cornerH), rect.bottomLeft, cornerPaint);
    canvas.drawLine(rect.bottomLeft, Offset(rect.left + cornerW, rect.bottom), cornerPaint);

    // Sağ alt
    canvas.drawLine(Offset(rect.right - cornerW, rect.bottom), rect.bottomRight, cornerPaint);
    canvas.drawLine(rect.bottomRight, Offset(rect.right, rect.bottom - cornerH), cornerPaint);
  }

  @override
  bool shouldRepaint(covariant _PlateBoxPainter oldDelegate) =>
      oldDelegate.rect != rect || oldDelegate.color != color;
}
