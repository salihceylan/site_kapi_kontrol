import 'package:flutter/material.dart';

/// Gerçekçi Türk Plaka (License Plate) Görünümü:
/// - Beyaz zemin, siyah kabartmalı çerçeve
/// - Sol tarafta mavi TR bandı (`#003399`, beyaz "TR" yazısı)
/// - Karakteristik plaka yazı stili (kalın, siyah, geniş harf aralığı)
/// - Responsive & ergonomik: Taşma yapmaz, kartlarda ve listelerde estetik görünür.
class LicensePlateBadge extends StatelessWidget {
  const LicensePlateBadge({
    super.key,
    required this.plate,
    this.fontSize = 14,
    this.compact = false,
  });

  final String plate;
  final double fontSize;
  final bool compact;

  static String format(String raw) {
    final cleaned = raw.toUpperCase().replaceAll(RegExp(r'[\s\-._]'), '');
    final match = RegExp(r'^(0[1-9]|[1-7][0-9]|8[01])([A-Z]{1,3})(\d{2,4})$').firstMatch(cleaned);
    if (match != null) {
      return '${match.group(1)} ${match.group(2)} ${match.group(3)}';
    }
    return raw.toUpperCase().trim();
  }

  @override
  Widget build(BuildContext context) {
    final formatted = format(plate);
    final h = compact ? 26.0 : 32.0;
    final fs = compact ? 12.0 : fontSize;
    final trWidth = compact ? 18.0 : 22.0;

    return Semantics(
      label: 'Plaka: $formatted',
      child: Container(
        height: h,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: const Color(0xFF1E2124), width: 1.5),
          boxShadow: const [
            BoxShadow(
              color: Color(0x24000000),
              blurRadius: 3,
              offset: Offset(0, 1.5),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Sol mavi TR bandı
            Container(
              width: trWidth,
              color: const Color(0xFF003399),
              alignment: Alignment.center,
              child: Text(
                'TR',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: compact ? 8 : 9.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                  height: 1.0,
                ),
              ),
            ),
            // Plaka metni
            Padding(
              padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 8),
              child: Center(
                child: Text(
                  formatted,
                  style: TextStyle(
                    color: const Color(0xFF111111),
                    fontFamily: 'monospace',
                    fontSize: fs,
                    fontWeight: FontWeight.w900,
                    letterSpacing: compact ? 1.0 : 1.5,
                    height: 1.0,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

