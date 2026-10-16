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
///
/// Biçim doğru ama değer gerçek bir tarih değilse (31.02.2024, 15.13.2024, yıl aralık dışı) "Geçersiz
/// tarih" der; biçim bozuksa (eksik hane, harf) biçimi söyler.
String? validateDateField(String? text) {
  final value = (text ?? '').trim();
  if (value.isEmpty) return null;
  if (parseDateField(value) != null) return null;
  if (RegExp(r'^\d{2}\.\d{2}\.\d{4}$').hasMatch(value)) {
    return 'Geçersiz tarih. Gerçek bir gün ve ay ile $dateInputMinYear-$dateInputMaxYear arası yıl girin (örn. 05.03.2024).';
  }
  return 'Tarihi GG.AA.YYYY biçiminde girin (örn. 05.03.2024).';
}

/// Yazarken noktaları kendisi koyar: "05032024" -> "05.03.2024".
///
/// - Yapıştırma: ayırıcılı tam tarih ("5.3.2024", "5/3/2024", "5-3-2024") `GG.AA.YYYY`'ye normalize edilir
///   (tek haneli gün / ay başına 0 eklenir).
/// - Yazarken ayırıcı: "5." -> "05.", "05.3." -> "05.03.".
/// - Diğer girişler rakam dizisi olarak yeniden dizilir. 8 rakamdan FAZLASI sessizce kırpılmaz: giriş
///   (yapıştırma ya da dolu alanın ortasına rakam yazma) REDDEDİLİR, eski değer kalır.
/// - İmleç: kendisinden SONRAKİ rakam sayısı korunur (ortadan düzeltmede imleç sona atlamaz).
class DateInputFormatter extends TextInputFormatter {
  const DateInputFormatter({this.onRejected});

  /// 8 rakamdan fazlası reddedilince çağrılır (sessiz reddetme olmasın: çağıran kısa bir uyarı gösterir). Çağıran
  /// `const` ifadesini kullanıyorsa verilmez.
  final VoidCallback? onRejected;

  static String _mask(String digits) {
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i == 2 || i == 4) buffer.write('.');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  static TextEditingValue _atEnd(String text) =>
      TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    if (text == oldValue.text) return newValue;

    // Yapıştırılan ayırıcılı tam tarih. Yalnız EKLENEN parça (uzun) tam tarihse: ortadan rakam silmek
    // ya da tek tek yazmak bu dala girmez (imleç sona atlamasın, haneler kendi kaymasıyla kalsın).
    final oldText = oldValue.text;
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
    final insertedLength = text.length - prefix - suffix;
    final full = insertedLength >= 6
        ? RegExp(r'^\s*(\d{1,2})[./\-](\d{1,2})[./\-](\d{4})\s*$').firstMatch(text)
        : null;
    if (full != null) {
      return _atEnd('${full.group(1)!.padLeft(2, '0')}.${full.group(2)!.padLeft(2, '0')}.${full.group(3)}');
    }
    // Yazarken ayırıcı: tek haneli gün / ay tamamlanır.
    final day = RegExp(r'^(\d)[./\-]$').firstMatch(text);
    if (day != null) return _atEnd('0${day.group(1)}.');
    final month = RegExp(r'^(\d{2})\.(\d)[./\-]$').firstMatch(text);
    if (month != null) return _atEnd('${month.group(1)}.0${month.group(2)}.');

    final digits = text.replaceAll(RegExp(r'\D'), '');
    if (digits.length > 8) {
      onRejected?.call();
      return oldValue;
    }
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
