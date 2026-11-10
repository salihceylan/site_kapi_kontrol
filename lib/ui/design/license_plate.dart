import 'package:flutter/material.dart';

/// Gerçekçi Türkiye Standartlarında Plaka (Standard Turkish License Plate) Görünümü:
/// - Türkiye Karayolları ve TŞOF standart ölçü oranı: 520 mm × 110 mm (~ 4.73 : 1)
/// - Asla ekranda yayılmaz veya kart boyunca uzamaz; sabit/oranlı standart ölçüde kalır.
/// - Beyaz zemin, siyah kabartmalı dış çerçeve
/// - Sol tarafta Avrupa Birliği / Karayolları standartlarında mavi TR bandı (`#003399`, beyaz "TR" yazısı)
/// - İl kodu ile harf grubu arasında resmi standart plaka hologram / mühür simgesi
/// - Karakteristik plaka yazı stili (kalın, siyah, dengeli harf ve rakam aralığı)
/// - Responsive & ergonomik: FittedBox ile her plaka içeriği taşmadan kusursuz oturur.
class LicensePlateBadge extends StatelessWidget {
  const LicensePlateBadge({
    super.key,
    required this.plate,
    this.fontSize = 14,
    this.compact = false,
    this.width,
    this.showSeal = true,
  });

  final String plate;
  final double fontSize;
  final bool compact;
  final double? width;
  final bool showSeal;

  static final RegExp _trRegex = RegExp(r'^(0[1-9]|[1-7][0-9]|8[01])([A-Z]{1,4})(\d{2,4})$');

  /// Ham plaka metnini standart boşluklu TR formatına dönüştürür (örn: "35 EA 8875").
  static String format(String raw) {
    final cleaned = raw.toUpperCase().replaceAll(RegExp(r'[\s\-._]'), '');
    final match = _trRegex.firstMatch(cleaned);
    if (match != null) {
      return '${match.group(1)} ${match.group(2)} ${match.group(3)}';
    }
    return raw.toUpperCase().trim();
  }

  /// Standart Türk plakasını (il, harfler, rakamlar) bileşenlerine ayırır.
  static TrPlateParts? parseTrPlate(String raw) {
    final cleaned = raw.toUpperCase().replaceAll(RegExp(r'[\s\-._]'), '');
    final match = _trRegex.firstMatch(cleaned);
    if (match != null) {
      return TrPlateParts(
        city: match.group(1)!,
        letters: match.group(2)!,
        digits: match.group(3)!,
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final h = compact ? 24.0 : 32.0;
    // Türkiye standart tek satır plaka en/boy oranı: 520 mm / 110 mm ≈ 4.727
    final w = width ?? (compact ? 114.0 : 152.0);
    final trWidth = compact ? 14.0 : 18.0;
    final fs = compact ? 11.5 : (fontSize > 14 ? 14.0 : fontSize);

    final parsed = parseTrPlate(plate);
    final formatted = format(plate);

    return Semantics(
      label: 'Plaka: $formatted',
      child: SizedBox(
        width: w,
        height: h,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(compact ? 3.0 : 4.0),
            border: Border.all(
              color: const Color(0xFF1B1E21),
              width: compact ? 1.2 : 1.5,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1F000000),
                blurRadius: 2.5,
                offset: Offset(0, 1),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Row(
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
                    fontSize: compact ? 7.5 : 9.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                    height: 1.0,
                  ),
                ),
              ),

              // Standart Türk Plaka İçeriği (Asla yayılmaz, tam oranlı oturur)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: compact ? 3.0 : 5.0),
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: parsed != null
                          ? Stack(
                              alignment: Alignment.center,
                              children: [
                                Opacity(
                                  opacity: 0,
                                  child: Text(
                                    formatted,
                                    style: const TextStyle(fontSize: 1),
                                  ),
                                ),
                                _buildStandardTrPlate(parsed, fs, compact, showSeal),
                              ],
                            )
                          : _buildGenericPlate(formatted, fs, compact),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStandardTrPlate(
    TrPlateParts parts,
    double fs,
    bool compact,
    bool showSeal,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // İl kodu (örn: 35 veya 06)
        Text(
          parts.city,
          style: TextStyle(
            color: const Color(0xFF111111),
            fontFamilyFallback: const ['DIN Alternate', 'DIN Condensed', 'Arial', 'Roboto', 'sans-serif'],
            fontSize: fs,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
            height: 1.0,
          ),
        ),
        SizedBox(width: compact ? 2.5 : 4.0),

        // Standart Plaka Hologram / Mühür simgesi (Kullanıcı görselindeki resmi mühür)
        if (showSeal) ...[
          Container(
            width: compact ? 6.5 : 8.5,
            height: compact ? 6.5 : 8.5,
            decoration: BoxDecoration(
              color: const Color(0xFFF1F3F5),
              border: Border.all(color: const Color(0xFFB0B8C1), width: 0.6),
              borderRadius: BorderRadius.circular(1.0),
            ),
            child: Icon(
              Icons.qr_code_2_rounded,
              size: compact ? 5.0 : 7.0,
              color: const Color(0xFF5A626A),
            ),
          ),
          SizedBox(width: compact ? 2.5 : 4.0),
        ],

        // Harf grubu (örn: EA, TEST)
        Text(
          parts.letters,
          style: TextStyle(
            color: const Color(0xFF111111),
            fontFamilyFallback: const ['DIN Alternate', 'DIN Condensed', 'Arial', 'Roboto', 'sans-serif'],
            fontSize: fs,
            fontWeight: FontWeight.w800,
            letterSpacing: compact ? 0.6 : 1.0,
            height: 1.0,
          ),
        ),
        SizedBox(width: compact ? 3.0 : 4.5),

        // Rakam grubu (örn: 8875, 001)
        Text(
          parts.digits,
          style: TextStyle(
            color: const Color(0xFF111111),
            fontFamilyFallback: const ['DIN Alternate', 'DIN Condensed', 'Arial', 'Roboto', 'sans-serif'],
            fontSize: fs,
            fontWeight: FontWeight.w800,
            letterSpacing: compact ? 0.6 : 1.0,
            height: 1.0,
          ),
        ),
      ],
    );
  }

  Widget _buildGenericPlate(String text, double fs, bool compact) {
    return Text(
      text,
      style: TextStyle(
        color: const Color(0xFF111111),
        fontFamilyFallback: const ['DIN Alternate', 'DIN Condensed', 'Arial', 'Roboto', 'sans-serif'],
        fontSize: fs,
        fontWeight: FontWeight.w800,
        letterSpacing: compact ? 0.8 : 1.2,
        height: 1.0,
      ),
    );
  }
}

/// Standart Türk Plakası parçaları: İl Kodu, Harfler ve Rakamlar.
class TrPlateParts {
  const TrPlateParts({
    required this.city,
    required this.letters,
    required this.digits,
  });

  final String city;
  final String letters;
  final String digits;
}
