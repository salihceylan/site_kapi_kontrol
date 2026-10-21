import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

// Beyaz etiket tema (G9, docs/PLATFORM_BEYAZ_ETIKET.md): yönetim firması ya da site başına 5 renk + logo + uygulamada görünen ad.
// 1C sade belirteçlerinin ÜSTÜNE biner: yalnız AÇIK temanın [AppPalette] değerleri değişir; koyu tema ve durum renkleri (zümrüt,
// kehribar, mercan) varsayılan Gude'de kalır. Kayıt yoksa ya da veri bozuksa/okunaksızsa [BrandTheme.tryParse] null verir (varsayılan tema).

/// WCAG göreli parlaklık oranı (1..21).
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// "#RRGGBB" -> Color; geçersizse null.
Color? parseHexColor(Object? value) {
  if (value is! String || !RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(value.trim())) return null;
  return Color(0xFF000000 | int.parse(value.trim().substring(1), radix: 16));
}

/// Color -> "#RRGGBB".
String hexOf(Color c) {
  final rgb = c.toARGB32() & 0xFFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

@immutable
class BrandTheme {
  const BrandTheme({
    required this.primary,
    required this.accent,
    required this.background,
    required this.surface,
    required this.text,
    this.displayName,
    this.logoData,
    this.source = 'site',
  });

  static const double minContrast = 4.5;

  final Color primary;
  final Color accent;
  final Color background;
  final Color surface;
  final Color text;
  final String? displayName;

  /// "data:image/...;base64,..." (png/jpeg/webp) ya da null.
  final String? logoData;

  /// 'site' | 'company' (temanın geldiği kapsam).
  final String source;

  /// Renk çiftleri okunaklı mı (sunucuyla aynı kural).
  bool get isReadable =>
      contrastRatio(text, background) >= minContrast &&
      contrastRatio(text, surface) >= minContrast &&
      contrastRatio(accent, surface) >= minContrast;

  /// Ana düğme üstündeki yazı: beyaz ya da koyu lacivert, hangisi daha karşıtsa (sunucudaki `on_primary` ile aynı).
  Color get onPrimary => contrastRatio(primary, Colors.white) >= contrastRatio(primary, const Color(0xFF0F172A))
      ? Colors.white
      : const Color(0xFF0F172A);

  /// Sunucu gövdesinden ayrıştırır; eksik/bozuk/okunaksız ise null (fail-closed: varsayılan Gude teması).
  static BrandTheme? tryParse(Object? json) {
    if (json is! Map) return null;
    final colors = json['colors'];
    if (colors is! Map) return null;
    final primary = parseHexColor(colors['primary']);
    final accent = parseHexColor(colors['accent']);
    final background = parseHexColor(colors['background']);
    final surface = parseHexColor(colors['surface']);
    final text = parseHexColor(colors['text']);
    if (primary == null || accent == null || background == null || surface == null || text == null) return null;
    final name = json['display_name'];
    final logo = json['logo_data'];
    final theme = BrandTheme(
      primary: primary,
      accent: accent,
      background: background,
      surface: surface,
      text: text,
      displayName: name is String && name.trim().isNotEmpty ? name.trim() : null,
      logoData: logo is String && logo.startsWith('data:image/') ? logo : null,
      source: json['source'] == 'company' ? 'company' : 'site',
    );
    return theme.isReadable ? theme : null;
  }

  /// Düzenleyicinin sunucuya gönderdiği gövde.
  Map<String, dynamic> toJson({bool includeLogo = false}) => <String, dynamic>{
        'display_name': displayName,
        'colors': <String, String>{
          'primary': hexOf(primary),
          'accent': hexOf(accent),
          'background': hexOf(background),
          'surface': hexOf(surface),
          'text': hexOf(text),
        },
        if (includeLogo) 'logo_data': logoData,
      };

  /// Logo baytları (bozuksa null; ekranda yedeğe düşülür).
  Uint8List? get logoBytes {
    final data = logoData;
    if (data == null) return null;
    final comma = data.indexOf(',');
    if (comma < 0) return null;
    try {
      return base64Decode(data.substring(comma + 1));
    } on FormatException {
      return null;
    }
  }

  /// Açık tema paleti: [base] (varsayılan Gude açık) üzerine 5 rengin türevleri. İkincil/soluk metin ve çerçeve, metin ile
  /// yüzey karışımından türetilir; okunaklılık sınırı (4,5:1) tutmazsa bir üst metin rengine düşülür.
  AppPalette lightPalette([AppPalette base = AppPalette.light]) {
    Color readable(double t, Color fallback) {
      final c = Color.lerp(text, surface, t)!;
      return contrastRatio(c, surface) >= minContrast && contrastRatio(c, background) >= minContrast ? c : fallback;
    }

    final secondary = readable(0.18, text);
    return base.copyWith(
      background: background,
      surface: surface,
      surfaceMuted: Color.lerp(surface, text, 0.05),
      border: Color.lerp(surface, text, 0.14),
      text: text,
      textSecondary: secondary,
      textMuted: readable(0.32, secondary),
      action: primary,
      onAction: onPrimary,
      link: accent,
      focusRing: accent,
      critical: primary,
      onCritical: onPrimary,
      criticalBorder: primary,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is BrandTheme &&
      other.primary == primary &&
      other.accent == accent &&
      other.background == background &&
      other.surface == surface &&
      other.text == text &&
      other.displayName == displayName &&
      other.logoData == logoData &&
      other.source == source;

  @override
  int get hashCode => Object.hash(primary, accent, background, surface, text, displayName, logoData, source);
}

/// Etkin marka temasını tutar (oturum açılınca yüklenir, kapanınca temizlenir). Null = varsayılan Gude teması.
class BrandThemeController extends ChangeNotifier {
  BrandTheme? _theme;

  BrandTheme? get theme => _theme;

  void set(BrandTheme? next) {
    if (next == _theme) return;
    _theme = next;
    notifyListeners();
  }
}
