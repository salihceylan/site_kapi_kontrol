// Banka tutarı: metinden / sayıdan KURUŞA çevirir (double ile para hesabı YOK). Saf Dart.
//
// Kabul edilen biçimler: '1.250,00', '-1.250,00', '1250.00', '1,250.00', '1250', '(1.250,00)', '1.250,00-', '1.250,00 B' (borç = eksi), '1.250,00 A' (alacak = artı),
// '₺', 'TL', 'TRY' soneki. Okunamayan ya da kuruştan ince (üçüncü ondalık sıfır değil) tutar null döner.

/// Metin tutarı kuruşa çevirir; okunamazsa null.
int? parseAmountMinor(String raw) {
  var s = raw.trim().toUpperCase();
  if (s.isEmpty) return null;
  s = s.replaceAll(RegExp(r'(₺|TRY|TL)'), '').trim();
  var negative = false;
  var positiveMark = false;
  if (s.startsWith('(') && s.endsWith(')')) {
    negative = true;
    s = s.substring(1, s.length - 1).trim();
  }
  final indicator = RegExp(r'\s*(BORC|BORÇ|ALACAK|B|A|D|C)$').firstMatch(s);
  if (indicator != null) {
    final mark = indicator.group(1)!;
    if (mark == 'B' || mark == 'BORC' || mark == 'BORÇ' || mark == 'D') {
      negative = true;
    } else {
      positiveMark = true;
    }
    s = s.substring(0, indicator.start).trim();
  }
  if (s.startsWith('-') || s.startsWith('−')) {
    negative = true;
    s = s.substring(1).trim();
  } else if (s.startsWith('+')) {
    s = s.substring(1).trim();
  }
  if (s.endsWith('-')) {
    negative = true;
    s = s.substring(0, s.length - 1).trim();
  }
  if (positiveMark && negative) return null;
  s = s.replaceAll(RegExp(r'\s'), '');
  if (s.isEmpty || !RegExp(r'^[0-9.,]+$').hasMatch(s)) return null;

  String whole;
  String fraction = '';
  final lastDot = s.lastIndexOf('.');
  final lastComma = s.lastIndexOf(',');
  int decimalAt = -1;
  if (lastDot >= 0 && lastComma >= 0) {
    decimalAt = lastDot > lastComma ? lastDot : lastComma;
  } else if (lastComma >= 0) {
    final after = s.length - lastComma - 1;
    final single = s.indexOf(',') == lastComma;
    // '1250,00' / '1250,5' -> ondalık; '1,250' ve '1,250,000' -> binlik (üç haneli son grup)
    decimalAt = single && after != 3 ? lastComma : -1;
  } else if (lastDot >= 0) {
    final after = s.length - lastDot - 1;
    final single = s.indexOf('.') == lastDot;
    // '1250.00' ondalık; '1.250' (TR binlik) ve '1.250.000' binlik
    decimalAt = single && after != 3 ? lastDot : -1;
  }
  if (decimalAt >= 0) {
    whole = s.substring(0, decimalAt).replaceAll(RegExp(r'[.,]'), '');
    fraction = s.substring(decimalAt + 1);
    if (RegExp(r'[.,]').hasMatch(fraction)) return null;
  } else {
    // ondalıksız: ayırıcılar yalnız üçlü binlik grupları olabilir
    if (RegExp(r'[.,]').hasMatch(s) && !RegExp(r'^\d{1,3}([.,]\d{3})+$').hasMatch(s)) return null;
    whole = s.replaceAll(RegExp(r'[.,]'), '');
  }
  if (whole.isEmpty) whole = '0';
  if (fraction.length > 2) {
    if (fraction.substring(2).replaceAll('0', '').isNotEmpty) return null;
    fraction = fraction.substring(0, 2);
  }
  fraction = fraction.padRight(2, '0');
  if (whole.length > 13) return null;
  final minor = int.parse(whole) * 100 + int.parse(fraction);
  return negative ? -minor : minor;
}

/// XLSX sayısal hücresi (double) -> kuruş. Kuruştan ince artık varsa null (sessizce yuvarlanmaz).
int? numToMinor(num value) {
  if (value.isNaN || value.isInfinite) return null;
  final scaled = value * 100;
  final rounded = scaled.round();
  if ((scaled - rounded).abs() > 0.001) return null;
  return rounded;
}
