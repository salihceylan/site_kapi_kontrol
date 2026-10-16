import 'package:flutter/services.dart';

/// Saat girişi (Platform Faz 3a, duyuru zamanlama): "SS:DD" metni (24 saat). Tarih girişiyle
/// (`date_input.dart`) aynı yaklaşım: Türkçe yerelleştirme paketi olmadığından Material saat seçici
/// İngilizce açılırdı; saat yazılır ve burada doğrulanır. Saat İstanbul saatidir.

/// "SS:DD" -> (saat, dakika). Boş, eksik ya da gerçek olmayan saatte (25:00, 12:60) null.
({int hour, int minute})? parseTimeField(String? text) {
  final match = RegExp(r'^(\d{2}):(\d{2})$').firstMatch((text ?? '').trim());
  if (match == null) return null;
  final hour = int.parse(match.group(1)!);
  final minute = int.parse(match.group(2)!);
  if (hour > 23 || minute > 59) return null;
  return (hour: hour, minute: minute);
}

/// Doğrulama: boş serbest (çağıran gerekliliğe karar verir); doluysa geçerli saat olmalı. Biçim doğru
/// ama değer gerçek değilse (25:61) "Geçersiz saat" der; biçim bozuksa biçimi söyler.
String? validateTimeField(String? text) {
  final value = (text ?? '').trim();
  if (value.isEmpty) return null;
  if (parseTimeField(value) != null) return null;
  if (RegExp(r'^\d{2}:\d{2}$').hasMatch(value)) {
    return 'Geçersiz saat. Saat 00-23, dakika 00-59 olmalı (örn. 14:30).';
  }
  return 'Saati SS:DD biçiminde girin (örn. 14:30).';
}

/// Yazarken iki noktayı kendisi koyar: "1430" -> "14:30".
///
/// - Yapıştırma: EKLENEN parça (önek / sonek farkı) en az 2 karakterse ayırıcılı ("9:30", "09.30", "9-30")
///   ya da 3-4 rakamlı ("930", "0930") saat `SS:DD`'ye normalize edilir. Mevcut metnin üstüne yapıştırma
///   ("12:00" üstüne "9:30") toplam uzunluğa değil eklenen parçaya bakar. Geçersiz yapıştırma (harf vb.)
///   REDDEDİLİR, eski değer kalır.
/// - Yazarken ayırıcı: "9:" -> "09:".
/// - 4 rakamdan FAZLASI sessizce kırpılmaz: giriş REDDEDİLİR, eski değer kalır.
/// - İmleç: kendisinden SONRAKİ rakam sayısı korunur.
class TimeInputFormatter extends TextInputFormatter {
  const TimeInputFormatter();

  static String _mask(String digits) =>
      digits.length <= 2 ? digits : '${digits.substring(0, 2)}:${digits.substring(2)}';

  static TextEditingValue _atEnd(String text) =>
      TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));

  /// [text] içinde, [oldValue]'ya göre EKLENEN parça.
  static String _insertedPart(TextEditingValue oldValue, String text) {
    final oldText = oldValue.text;
    final selection = oldValue.selection;
    if (selection.isValid && !selection.isCollapsed && selection.end <= oldText.length) {
      final before = oldText.substring(0, selection.start);
      final after = oldText.substring(selection.end);
      if (text.length >= before.length + after.length &&
          text.startsWith(before) &&
          text.endsWith(after)) {
        return text.substring(before.length, text.length - after.length);
      }
    }
    var prefix = 0;
    while (prefix < oldText.length &&
        prefix < text.length &&
        oldText.codeUnitAt(prefix) == text.codeUnitAt(prefix)) {
      prefix++;
    }
    var suffix = 0;
    while (suffix < oldText.length - prefix &&
        suffix < text.length - prefix &&
        oldText.codeUnitAt(oldText.length - 1 - suffix) ==
            text.codeUnitAt(text.length - 1 - suffix)) {
      suffix++;
    }
    return text.substring(prefix, text.length - suffix);
  }

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final text = newValue.text;
    if (text == oldValue.text) return newValue;

    // Eklenen parça. Eski değerde seçili aralık varsa (seçip üstüne yapıştırma) o aralığın yerine geçen
    // kısımdır; yoksa ortak önek ve ortak sonek dışında kalan kısımdır.
    final inserted = _insertedPart(oldValue, text);

    // Saat yazımında anlamsız karakter (harf vb.) içeren giriş reddedilir.
    if (inserted.isNotEmpty && RegExp(r'[^0-9:.\-\s]').hasMatch(inserted)) return oldValue;

    if (inserted.length >= 2) {
      final full = RegExp(r'^\s*(\d{1,2})[:.\-](\d{1,2})\s*$').firstMatch(text);
      if (full != null) {
        return _atEnd('${full.group(1)!.padLeft(2, '0')}:${full.group(2)!.padLeft(2, '0')}');
      }
      final compact = RegExp(r'^\s*(\d{3,4})\s*$').firstMatch(text);
      if (compact != null) {
        final d = compact.group(1)!;
        return _atEnd(d.length == 3 ? '0${d[0]}:${d.substring(1)}' : '${d.substring(0, 2)}:${d.substring(2)}');
      }
    }
    final hour = RegExp(r'^(\d)[:.\-]$').firstMatch(text);
    if (hour != null) return _atEnd('0${hour.group(1)}:');

    final digits = text.replaceAll(RegExp(r'\D'), '');
    if (digits.length > 4) return oldValue;
    final masked = _mask(digits);

    final caret = newValue.selection.isValid
        ? newValue.selection.end.clamp(0, text.length)
        : text.length;
    final digitsAfter = RegExp(r'\d').allMatches(text.substring(caret)).length;
    return TextEditingValue(
      text: masked,
      selection: TextSelection.collapsed(offset: _caretFor(masked, digitsAfter)),
    );
  }

  /// [masked] içinde kendisinden sonra [digitsAfter] rakam kalan konum.
  static int _caretFor(String masked, int digitsAfter) {
    var remaining = digitsAfter;
    for (var i = masked.length; i > 0; i--) {
      if (remaining == 0) return i;
      if (RegExp(r'\d').hasMatch(masked[i - 1])) remaining--;
    }
    return 0;
  }
}
