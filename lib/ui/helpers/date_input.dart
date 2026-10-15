import 'package:flutter/services.dart';

/// Tarih girişi (Platform Faz 2a): "GG.AA.YYYY" metni. Uygulamada Türkçe yerelleştirme paketi yoktur
/// (Material tarih seçici İngilizce açılırdı), bu yüzden tarih noktalı metin olarak yazılır ve burada
/// doğrulanır. Sunucu da `GG.AA.YYYY` ve `YYYY-AA-GG` biçimlerini kabul eder; uygulama `YYYY-AA-GG`
/// gönderir (bkz. `crmDateParam`).

/// Alana yazılan geçerli en küçük / en büyük yıl (sunucu ile aynı sınır).
const int dateInputMinYear = 1900;
const int dateInputMaxYear = 2100;

/// Listelerde gösterilen tarih: "05.03.2024"; yoksa "-".
String formatCrmDate(DateTime? date) {
  if (date == null) return '-';
  return formatDateField(date);
}

/// Alanın metni: "05.03.2024"; tarih yoksa boş.
String formatDateField(DateTime? date) {
  if (date == null) return '';
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  final year = date.year.toString().padLeft(4, '0');
  return '$day.$month.$year';
}

/// "GG.AA.YYYY" -> tarih. Boş, eksik ya da gerçek olmayan tarihte (31.02.2024 gibi) null.
DateTime? parseDateField(String? text) {
  final match = RegExp(r'^(\d{2})\.(\d{2})\.(\d{4})$').firstMatch((text ?? '').trim());
  if (match == null) return null;
  final day = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final year = int.parse(match.group(3)!);
  if (year < dateInputMinYear || year > dateInputMaxYear) return null;
  if (month < 1 || month > 12 || day < 1) return null;
  final date = DateTime(year, month, day);
  // DateTime taşan günü sonraki aya kaydırır (31.02 -> 03.03): gerçek tarih mi?
  if (date.year != year || date.month != month || date.day != day) return null;
  return date;
}

/// Doğrulama: boş serbest (isteğe bağlı tarih); doluysa geçerli tarih olmalı. Hata yoksa null.
String? validateDateField(String? text) {
  final value = (text ?? '').trim();
  if (value.isEmpty) return null;
  return parseDateField(value) == null
      ? 'Tarihi GG.AA.YYYY biçiminde girin (örn. 05.03.2024).'
      : null;
}

/// Yazarken yalnız rakamları alır ve noktaları kendisi koyar: "05032024" -> "05.03.2024".
class DateInputFormatter extends TextInputFormatter {
  const DateInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length > 8) digits = digits.substring(0, 8);
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i == 2 || i == 4) buffer.write('.');
      buffer.write(digits[i]);
    }
    final text = buffer.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
