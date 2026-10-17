// Dışa aktarılan hücrelerin güvenliği (Platform Faz 2b; sözleşme "Formül enjeksiyonu").
//
// Kaçış TEK yerde yapılır: bu dosya. Sunucu ham değer verir; CSV üreticisi her metin hücresini
// [escapeCsvFormula] ile geçirir. XLSX'te kaçış GEREKMEZ (metin hücresi `inlineStr`, formül olamaz) ve eklenmez.

final RegExp _pureNumber = RegExp(r'^[+-]?\d+([.,]\d+)?$');

/// Metin hücrenin ilk karakteri (baştaki boşluklar atlanarak) `=`, `+`, `-`, `@`, TAB ya da CR ise önüne `'`
/// eklenir (OWASP CSV injection önlemi); İSTİSNA yalnız saf sayı kalıbıdır (`^[+-]?\d+([.,]\d+)?$`, ör. kat «-1»).
String escapeCsvFormula(String value) {
  var i = 0;
  while (i < value.length && (value.codeUnitAt(i) == 0x20 || value.codeUnitAt(i) == 0xA0)) {
    i++;
  }
  if (i >= value.length) return value;
  final c = value.codeUnitAt(i);
  final dangerous = c == 0x3D /* = */ ||
      c == 0x2B /* + */ ||
      c == 0x2D /* - */ ||
      c == 0x40 /* @ */ ||
      c == 0x09 /* TAB */ ||
      c == 0x0D /* CR */;
  if (!dangerous) return value;
  if (_pureNumber.hasMatch(value.trim())) return value;
  return "'$value";
}

/// XML 1.0'da geçersiz karakterleri (U+0000–0008, 000B, 000C, 000E–001F, FFFE, FFFF ve eşleşmemiş vekil
/// çiftler) atar.
String stripInvalidXmlChars(String value) {
  var clean = true;
  for (var i = 0; i < value.length; i++) {
    if (!_isValidXmlUnit(value, i)) {
      clean = false;
      break;
    }
  }
  if (clean) return value;
  final out = StringBuffer();
  for (var i = 0; i < value.length; i++) {
    final c = value.codeUnitAt(i);
    if (c >= 0xD800 && c <= 0xDBFF && i + 1 < value.length) {
      final d = value.codeUnitAt(i + 1);
      if (d >= 0xDC00 && d <= 0xDFFF) {
        out
          ..writeCharCode(c)
          ..writeCharCode(d);
        i++;
        continue;
      }
    }
    if (_isValidScalarUnit(c)) out.writeCharCode(c);
  }
  return out.toString();
}

bool _isValidScalarUnit(int c) {
  if (c < 0x20) return c == 0x09 || c == 0x0A || c == 0x0D;
  if (c >= 0xD800 && c <= 0xDFFF) return false; // tek başına vekil
  return c != 0xFFFE && c != 0xFFFF;
}

bool _isValidXmlUnit(String value, int i) {
  final c = value.codeUnitAt(i);
  if (c >= 0xD800 && c <= 0xDBFF) {
    if (i + 1 < value.length) {
      final d = value.codeUnitAt(i + 1);
      return d >= 0xDC00 && d <= 0xDFFF;
    }
    return false;
  }
  if (c >= 0xDC00 && c <= 0xDFFF) {
    if (i == 0) return false;
    final p = value.codeUnitAt(i - 1);
    return p >= 0xD800 && p <= 0xDBFF;
  }
  return _isValidScalarUnit(c);
}

/// XML metin / öznitelik kaçışı.
String escapeXml(String value) {
  final clean = stripInvalidXmlChars(value);
  if (!clean.contains(RegExp(r'[&<>"\r\n\t]'))) return clean;
  final out = StringBuffer();
  for (var i = 0; i < clean.length; i++) {
    final c = clean[i];
    switch (c) {
      case '&':
        out.write('&amp;');
      case '<':
        out.write('&lt;');
      case '>':
        out.write('&gt;');
      case '"':
        out.write('&quot;');
      case '\r':
        out.write('&#13;');
      case '\n':
        out.write('&#10;');
      case '\t':
        out.write('&#9;');
      default:
        out.write(c);
    }
  }
  return out.toString();
}

/// Excel sayfa adı: ≤ 31 karakter, `[]:*?/\` yok, baş/son `'` yok, boş olamaz.
String sanitizeSheetName(String name, {String fallback = 'Sayfa1'}) {
  var cleaned = stripInvalidXmlChars(name).replaceAll(RegExp(r'[\[\]:*?/\\]'), ' ');
  cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
  while (cleaned.startsWith("'")) {
    cleaned = cleaned.substring(1);
  }
  while (cleaned.endsWith("'")) {
    cleaned = cleaned.substring(0, cleaned.length - 1);
  }
  cleaned = cleaned.trim();
  if (cleaned.isEmpty) return fallback;
  // 31 UTF-16 birimi; vekil çiftin ortasından kesme.
  if (cleaned.length > 31) {
    var cut = 31;
    final c = cleaned.codeUnitAt(cut - 1);
    if (c >= 0xD800 && c <= 0xDBFF) cut--;
    cleaned = cleaned.substring(0, cut).trim();
  }
  return cleaned.isEmpty ? fallback : cleaned;
}
