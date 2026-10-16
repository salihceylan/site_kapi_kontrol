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

/// Doğrulama: boş serbest (çağıran gerekliliğe karar verir); doluysa geçerli saat olmalı.
String? validateTimeField(String? text) {
  final value = (text ?? '').trim();
  if (value.isEmpty) return null;
  return parseTimeField(value) == null
      ? 'Saati SS:DD biçiminde girin (örn. 14:30).'
      : null;
}

/// Yazarken iki noktayı kendisi koyar: "1430" -> "14:30".
///
/// - Yapıştırma: ayırıcılı saat ("9:30", "09.30", "9-30") `SS:DD`'ye normalize edilir.
/// - Yazarken ayırıcı: "9:" -> "09:".
/// - 4 rakamdan FAZLASI sessizce kırpılmaz: giriş REDDEDİLİR, eski değer kalır.
/// - İmleç: kendisinden SONRAKİ rakam sayısı korunur.
class TimeInputFormatter extends TextInputFormatter {
  const TimeInputFormatter();

  static String _mask(String digits) =>
      digits.length <= 2 ? digits : '${digits.substring(0, 2)}:${digits.substring(2)}';

  static TextEditingValue _atEnd(String text) =>
      TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final text = newValue.text;
    if (text == oldValue.text) return newValue;

    // Yapıştırılan ayırıcılı tam saat: yalnız en az 3 karakter EKLENDİYSE (tek tek yazmak bu dala girmez).
    if (text.length - oldValue.text.length >= 3) {
      final full = RegExp(r'^\s*(\d{1,2})[:.\-](\d{1,2})\s*$').firstMatch(text);
      if (full != null) {
        return _atEnd('${full.group(1)!.padLeft(2, '0')}:${full.group(2)!.padLeft(2, '0')}');
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
