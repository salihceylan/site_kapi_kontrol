// Dışa aktarma değer biçimlendirme yardımcıları (Platform Faz 2b). Saf Dart.
//
// Para (`money`) TAMSAYI KURUŞtur ve yalnız tamsayı / metin aritmetiğiyle yazılır: kayan nokta KULLANILMAZ
// (1 TL = 100 kuruş; 0,1 + 0,2 tuzağı yok).

/// Kuruş tamsayısını "1250,50" / "-0,05" yapar (binlik ayırıcısız). [minor] `int`, `BigInt` ya da yalnız rakamlardan
/// (ve baştaki işaretten) oluşan metin olabilir; başka her şey null döner.
String? formatMoneyMinor(Object? minor, {String separator = ','}) {
  BigInt? value;
  if (minor is int) {
    value = BigInt.from(minor);
  } else if (minor is BigInt) {
    value = minor;
  } else if (minor is String && RegExp(r'^[+-]?\d{1,30}$').hasMatch(minor.trim())) {
    value = BigInt.tryParse(minor.trim());
  } else if (minor is double && minor.isFinite && minor == minor.roundToDouble() && minor.abs() < 9007199254740992) {
    value = BigInt.from(minor.toInt());
  }
  if (value == null) return null;
  final negative = value.isNegative;
  final abs = value.abs();
  final hundred = BigInt.from(100);
  final whole = abs ~/ hundred;
  final cents = (abs % hundred).toInt().toString().padLeft(2, '0');
  return '${negative ? '-' : ''}$whole$separator$cents';
}

/// Sayıyı ondalık [separator] ile yazar, binlik ayırıcı yok. [scale] verilirse tam o kadar ondalık basamak.
String formatPlainNumber(Object? value, {int? scale, String separator = ','}) {
  num? number;
  if (value is num) {
    number = value;
  } else if (value is String) {
    number = num.tryParse(value.trim().replaceAll(',', '.'));
  }
  if (number == null || (number is double && !number.isFinite)) return '';
  String text;
  if (scale != null) {
    text = number.toDouble().toStringAsFixed(scale);
    if (number is int && scale >= 0) {
      text = scale == 0 ? number.toString() : '${number.toString()}.${'0' * scale}';
    }
  } else if (number is int) {
    text = number.toString();
  } else {
    final d = number.toDouble();
    if (d == d.roundToDouble() && d.abs() < 9007199254740992) {
      text = d.toInt().toString();
    } else {
      text = d.toString();
      if (text.contains('e') || text.contains('E')) {
        text = d.toStringAsFixed(8).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
      }
    }
  }
  return separator == '.' ? text : text.replaceAll('.', separator);
}

/// "2021-03-15" (ya da ISO zaman damgasının tarih kısmı) -> (yıl, ay, gün); geçersizse null.
(int, int, int)? parseIsoDate(Object? value) {
  if (value is DateTime) return (value.year, value.month, value.day);
  if (value is! String) return null;
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(value.trim());
  if (m == null) return null;
  final y = int.parse(m.group(1)!);
  final mo = int.parse(m.group(2)!);
  final d = int.parse(m.group(3)!);
  if (mo < 1 || mo > 12 || d < 1 || d > 31) return null;
  final check = DateTime.utc(y, mo, d);
  if (check.month != mo || check.day != d) return null;
  return (y, mo, d);
}

/// ISO tarih -> "15.03.2021"; geçersizse null.
String? formatTurkishDate(Object? value) {
  final parts = parseIsoDate(value);
  if (parts == null) return null;
  final (y, m, d) = parts;
  return '${d.toString().padLeft(2, '0')}.${m.toString().padLeft(2, '0')}.${y.toString().padLeft(4, '0')}';
}

/// ISO tarih -> Excel 1900 sistemi seri numarası; Excel'in 1900-03-01 öncesi hatası nedeniyle yalnız 1900-03-01
/// ve sonrası desteklenir (daha eskisi null).
int? excelSerialOf(Object? value) {
  final parts = parseIsoDate(value);
  if (parts == null) return null;
  final (y, m, d) = parts;
  final date = DateTime.utc(y, m, d);
  if (date.isBefore(DateTime.utc(1900, 3, 1))) return null;
  return date.difference(DateTime.utc(1899, 12, 30)).inDays;
}
