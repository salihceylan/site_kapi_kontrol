import 'package:flutter/material.dart';

/// Güde Teknoloji logosunun TEMAYA BAĞLI renkleri (yapraklar SVG'deki gradyanlarla iki temada da aynı çizilir).
/// Değerler gudeteknoloji.com sitesindeki `AppColors.logo` ile birebir aynıdır.
@immutable
class LogoPalette {
  const LogoPalette({
    required this.wordStart,
    required this.wordMid,
    required this.wordEnd,
    required this.wordOutline,
    required this.tagline,
    required this.taglineEdge,
    required this.shadow,
  });

  /// "Güde Teknoloji" harf yüzlerinin soldan sağa gradyanı.
  final Color wordStart;
  final Color wordMid;
  final Color wordEnd;

  /// Harflerin koyu kenarı.
  final Color wordOutline;

  /// Slogan ("gelecek sizin elinizde"): dolgu ve kenar. Koyu zeminde kenar koyu olamaz (kaybolur, ince harfler cılız kalır);
  /// bu yüzden koyu temada kenar loş altın, açıkta koyu kahverengidir.
  final Color tagline;
  final Color taglineEdge;

  /// Yaprakların ve yazının altındaki yumuşak gölge (alfa içinde); koyu zeminde görünmez.
  final Color shadow;

  /// Koyu zemin üstünde (koyu tema, uygulama ikonu).
  static const dark = LogoPalette(
    wordStart: Color(0xFFC98A5B),
    wordMid: Color(0xFFF1B987),
    wordEnd: Color(0xFFFFF3E6),
    wordOutline: Color(0xFF1B2433),
    tagline: Color(0xFFF3D6A4),
    taglineEdge: Color(0xFFA9783C),
    shadow: Color(0x00000000),
  );

  /// Açık zemin üstünde (açık tema).
  static const light = LogoPalette(
    wordStart: Color(0xFFB4743F),
    wordMid: Color(0xFFD99A5F),
    wordEnd: Color(0xFFF0CFA6),
    wordOutline: Color(0xFF1B2433),
    tagline: Color(0xFFB98A45),
    taglineEdge: Color(0xFF3A2410),
    shadow: Color(0x40404858),
  );

  /// Etkin temanın parlaklığına göre palet.
  static LogoPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LogoPalette &&
          wordStart == other.wordStart &&
          wordMid == other.wordMid &&
          wordEnd == other.wordEnd &&
          wordOutline == other.wordOutline &&
          tagline == other.tagline &&
          taglineEdge == other.taglineEdge &&
          shadow == other.shadow;

  @override
  int get hashCode => Object.hash(wordStart, wordMid, wordEnd, wordOutline, tagline, taglineEdge, shadow);
}
