// CSV baytlarını metne çevirir (Platform Faz 2b).
//
// Sıra (docs/PLATFORM_TOPLU_ISLEMLER.md "Okuyucular"): BOM varsa uygula (UTF-8, UTF-16LE/BE; Excel "Unicode Metin"
// sekmeli UTF-16LE üretir); yoksa KATI UTF-8 dene; olmazsa Windows-1254 (Türkçe Excel'in "CSV (Noktalı virgülle
// ayrılmış)" çıktısı). Kodlama sonucu kullanıcıya bildirilir.
import 'dart:convert';
import 'dart:typed_data';

import 'package:site_kapi_kontrol/services/bulk_sheet_types.dart';

class DecodedText {
  const DecodedText(this.text, this.label, {this.fallback = false});

  final String text;

  /// "UTF-8", "UTF-8 (BOM'lu)", "UTF-16", "Windows-1254".
  final String label;

  /// Windows-1254 yedeğine düşüldü (kullanıcıya açıkça söylenir).
  final bool fallback;

  /// Kullanıcıya gösterilen not.
  String get note => fallback ? 'Windows-1254 olarak okundu' : '$label olarak okundu';
}

/// Windows-1254 0x80..0x9F tablosu (tanımsız baytlar U+FFFD olur).
const List<int> _cp1254High = <int>[
  0x20AC, 0xFFFD, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, //
  0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0xFFFD, 0xFFFD, 0xFFFD,
  0xFFFD, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
  0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0xFFFD, 0xFFFD, 0x0178,
];

/// Latin-1'den farklı Türkçe karakterler.
const Map<int, int> _cp1254Turkish = <int, int>{
  0xD0: 0x011E, // Ğ
  0xDD: 0x0130, // İ
  0xDE: 0x015E, // Ş
  0xF0: 0x011F, // ğ
  0xFD: 0x0131, // ı
  0xFE: 0x015F, // ş
};

/// Windows-1254 baytlarını metne çevirir.
String decodeWindows1254(Uint8List bytes) {
  final units = Uint16List(bytes.length);
  for (var i = 0; i < bytes.length; i++) {
    final b = bytes[i];
    if (b < 0x80) {
      units[i] = b;
    } else if (b < 0xA0) {
      units[i] = _cp1254High[b - 0x80];
    } else {
      units[i] = _cp1254Turkish[b] ?? b;
    }
  }
  return String.fromCharCodes(units);
}

String _decodeUtf16(Uint8List bytes, int start, {required bool littleEndian}) {
  final count = (bytes.length - start) ~/ 2;
  final units = Uint16List(count);
  for (var i = 0; i < count; i++) {
    final a = bytes[start + i * 2];
    final b = bytes[start + i * 2 + 1];
    units[i] = littleEndian ? (b << 8) | a : (a << 8) | b;
  }
  return String.fromCharCodes(units);
}

/// BOM'suz UTF-16 olasılığı: ilk 4 KB'ta tek (ya da çift) konumlu baytların çoğu sıfır.
bool? _looksLikeUtf16WithoutBom(Uint8List bytes) {
  final n = bytes.length < 4096 ? bytes.length : 4096;
  if (n < 8) return null;
  var evenZero = 0;
  var oddZero = 0;
  for (var i = 0; i < n; i++) {
    if (bytes[i] == 0) {
      if (i.isEven) {
        evenZero++;
      } else {
        oddZero++;
      }
    }
  }
  final half = n / 2;
  if (oddZero > half * 0.4 && evenZero < half * 0.05) return true; // LE: yüksek bayt sıfır
  if (evenZero > half * 0.4 && oddZero < half * 0.05) return false; // BE
  return null;
}

/// [bytes] CSV içeriğini çözer. Metin değilse (ikili dosya) [SpreadsheetException] fırlatır.
DecodedText decodeSpreadsheetText(Uint8List bytes) {
  if (bytes.isEmpty) {
    throw const SpreadsheetException('Dosya boş.', code: 'FILE_EMPTY');
  }
  String text;
  String label;
  var fallback = false;
  if (bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
    try {
      text = utf8.decode(Uint8List.sublistView(bytes, 3));
    } on FormatException {
      throw const SpreadsheetException(
        'Dosya UTF-8 olarak işaretlenmiş ama içeriği bozuk. Excel\'de «CSV UTF-8» olarak yeniden kaydedin.',
      );
    }
    label = 'UTF-8';
  } else if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    text = _decodeUtf16(bytes, 2, littleEndian: true);
    label = 'UTF-16';
  } else if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
    text = _decodeUtf16(bytes, 2, littleEndian: false);
    label = 'UTF-16';
  } else {
    final utf16 = _looksLikeUtf16WithoutBom(bytes);
    if (utf16 != null) {
      text = _decodeUtf16(bytes, 0, littleEndian: utf16);
      label = 'UTF-16';
    } else {
      try {
        text = utf8.decode(bytes);
        label = 'UTF-8';
      } on FormatException {
        text = decodeWindows1254(bytes);
        label = 'Windows-1254';
        fallback = true;
      }
    }
  }
  // Dosyanın başındaki kalıntı BOM (çift BOM) atılır.
  if (text.isNotEmpty && text.codeUnitAt(0) == 0xFEFF) text = text.substring(1);
  // NUL baytı: metin dosyası değildir (ikili dosya .csv adıyla seçilmiş).
  if (text.contains('\u0000')) {
    throw const SpreadsheetException(
      'Dosya metin (CSV) biçiminde değil. Excel dosyası için .xlsx, tablo için CSV kullanın.',
      code: 'FILE_TYPE',
    );
  }
  return DecodedText(text, label, fallback: fallback);
}
