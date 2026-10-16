// Para yardımcıları (Platform Faz 4a, Aidat ve Finans; sözleşme: docs/PLATFORM_FINANS.md, "İlkeler").
//
// Para = TAMSAYI KURUŞ. Bu dosyada HİÇBİR yerde kayan nokta (double) ile para hesabı yapılmaz: biçimleme
// ve ayrıştırma yalnız tamsayı / BigInt ve metin işlemleriyle yapılır (`~/` ve `%`), yuvarlama YOKTUR.
//
// - [formatMinor]: kuruş -> "1.234,56 ₺" (binlik nokta, ondalık virgül).
// - [parseMoney]: kullanıcı girişi -> kuruş. Virgül ya da nokta ondalık ayırıcı olabilir; 3 ve üstü
//   ondalık, negatif, boş, sıfır ve aşırı büyük tutar REDDEDİLİR. Binlik ayırıcı kuralları aşağıda.
// - [moneySemanticLabel]: ekran okuyucu etiketi ("bin iki yüz otuz dört lira elli altı kuruş").

/// Kabul edilen en büyük tutar (kuruş): 999.999.999,99 ₺. Sunucu BIGINT tutar; uygulama tarafında makul bir
/// üst sınır, yanlışlıkla fazladan sıfır girilmesini ve JavaScript güvenli tamsayı sınırını (2^53) aşmayı önler.
const int kMaxMoneyMinor = 99999999999;

/// Para birimi simgesi (sözleşme: para birimi bugün hep TRY).
const String kMoneySymbol = '₺';

/// Giriş doğrulama sonucunun nedeni.
enum MoneyProblem {
  empty,
  negative,
  invalid,
  tooManyDecimals,
  tooLarge,
  zero,
}

/// [parseMoney] sonucu: ya [minor] (kuruş) ya da [problem].
class MoneyParse {
  const MoneyParse.ok(int this.minor) : problem = null;
  const MoneyParse.fail(MoneyProblem this.problem) : minor = null;

  final int? minor;
  final MoneyProblem? problem;

  bool get isOk => minor != null;

  /// Kullanıcıya gösterilecek Türkçe hata metni; başarıda null.
  String? get message {
    final p = problem;
    return p == null ? null : moneyProblemMessage(p);
  }
}

/// Hata nedeninin Türkçe metni (teknik ifade içermez).
String moneyProblemMessage(MoneyProblem problem) {
  switch (problem) {
    case MoneyProblem.empty:
      return 'Tutarı girin.';
    case MoneyProblem.negative:
      return 'Tutar negatif olamaz.';
    case MoneyProblem.invalid:
      return 'Tutarı rakamlarla girin (örn. 1.250,50).';
    case MoneyProblem.tooManyDecimals:
      return 'Kuruş en çok 2 basamak olabilir (örn. 1.250,50).';
    case MoneyProblem.tooLarge:
      return 'Tutar en çok ${formatMinor(kMaxMoneyMinor)} olabilir.';
    case MoneyProblem.zero:
      return 'Tutar sıfırdan büyük olmalı.';
  }
}

/// Kuruş -> "1.234,56 ₺". Negatif tutar "-1.234,56 ₺". [symbol] false ise yalnız sayı ("1.234,56").
///
/// Tamsayı aritmetiği (BigInt): kayan nokta ve yuvarlama yoktur.
String formatMinor(int minor, {bool symbol = true}) {
  final negative = minor < 0;
  final magnitude = BigInt.from(minor).abs();
  final hundred = BigInt.from(100);
  final whole = (magnitude ~/ hundred).toString();
  final fraction = (magnitude % hundred).toString().padLeft(2, '0');
  final grouped = _groupThousands(whole);
  final sign = negative ? '-' : '';
  return symbol
      ? '$sign$grouped,$fraction $kMoneySymbol'
      : '$sign$grouped,$fraction';
}

/// İşaretli gösterim: pozitif "+1.234,56 ₺", negatif "-1.234,56 ₺", sıfır "0,00 ₺".
String formatSignedMinor(int minor, {bool symbol = true}) {
  final text = formatMinor(minor, symbol: symbol);
  return minor > 0 ? '+$text' : text;
}

String _groupThousands(String digits) {
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    final fromEnd = digits.length - i;
    buffer.write(digits[i]);
    if (fromEnd > 1 && fromEnd % 3 == 1) buffer.write('.');
  }
  return buffer.toString();
}

/// Kullanıcı girişini kuruşa çevirir.
///
/// Kurallar (hiçbirinde yuvarlama yoktur):
/// - Başındaki/sonundaki boşluk, "₺" ve "TL" işareti yok sayılır; sayının İÇİNDE boşluk GEÇERSİZdir.
/// - Eksi işareti ya da parantez -> [MoneyProblem.negative]; boş -> [MoneyProblem.empty]; rakam, nokta ve
///   virgül dışında karakter -> [MoneyProblem.invalid].
/// - Hem nokta hem virgül varsa SON ayırıcı ondalıktır, diğeri binliktir ve doğru gruplanmalıdır
///   ("1.234,56" ve "1,234.56" -> 1234,56; "1.23,4" geçersiz).
/// - Yalnız virgül: TEK virgül ondalık ayırıcıdır ("1250,5" -> 1250,50; "1,250" -> üç ondalık, REDDEDİLİR).
///   Birden çok virgül geçersizdir.
/// - Yalnız nokta, tek nokta: noktadan sonra TAM 3 rakam ve noktadan önce 1-3 rakam (baştaki sıfır yok)
///   varsa nokta BİNLİKtir ("1.250" -> 1250,00); aksi halde ondalıktır ("1250.50", "12.5" -> 12,50;
///   "1250.500" ve "0.250" -> üç ondalık, REDDEDİLİR). Birden çok nokta doğru gruplanmış binliktir
///   ("1.250.000" -> 1250000,00; "1.25.000" geçersiz).
/// - En çok 2 ondalık basamak; sıfır tutar [allowZero] false iken [MoneyProblem.zero]; [maxMinor] üstü
///   [MoneyProblem.tooLarge].
MoneyParse parseMoney(
  String? input, {
  int maxMinor = kMaxMoneyMinor,
  bool allowZero = false,
}) {
  var s = (input ?? '').trim();
  // Para birimi işareti (yapıştırma): "1.250,50 ₺", "₺1.250,50", "1.250,50 TL".
  s = s.replaceAll(kMoneySymbol, '');
  s = s.replaceFirst(RegExp(r'\s*(TL|tl|Tl)\s*$'), '').trim();
  if (s.isEmpty) return const MoneyParse.fail(MoneyProblem.empty);

  // Eksi işareti (ASCII, Unicode eksi, kısa/uzun tire) ya da parantez: negatif.
  if (RegExp('^[-−‒–—(]').hasMatch(s)) {
    return const MoneyParse.fail(MoneyProblem.negative);
  }
  if (s.startsWith('+')) s = s.substring(1);
  if (s.isEmpty || !RegExp(r'^[0-9.,]+$').hasMatch(s)) {
    return const MoneyParse.fail(MoneyProblem.invalid);
  }

  final dots = '.'.allMatches(s).length;
  final commas = ','.allMatches(s).length;
  String integerPart;
  String fractionPart = '';

  if (dots > 0 && commas > 0) {
    final lastDot = s.lastIndexOf('.');
    final lastComma = s.lastIndexOf(',');
    final decimalIsComma = lastComma > lastDot;
    final decimalCount = decimalIsComma ? commas : dots;
    if (decimalCount != 1) return const MoneyParse.fail(MoneyProblem.invalid);
    final at = decimalIsComma ? lastComma : lastDot;
    final left = s.substring(0, at);
    fractionPart = s.substring(at + 1);
    final stripped = _stripThousands(left, decimalIsComma ? '.' : ',');
    if (stripped == null) return const MoneyParse.fail(MoneyProblem.invalid);
    integerPart = stripped;
  } else if (commas > 0) {
    if (commas != 1) return const MoneyParse.fail(MoneyProblem.invalid);
    final at = s.indexOf(',');
    integerPart = s.substring(0, at);
    fractionPart = s.substring(at + 1);
  } else if (dots > 0) {
    if (dots > 1) {
      final stripped = _stripThousands(s, '.');
      if (stripped == null) return const MoneyParse.fail(MoneyProblem.invalid);
      integerPart = stripped;
    } else {
      final at = s.indexOf('.');
      final left = s.substring(0, at);
      final right = s.substring(at + 1);
      if (right.length == 3 && _isFirstGroup(left)) {
        integerPart = left + right;
      } else {
        integerPart = left;
        fractionPart = right;
      }
    }
  } else {
    integerPart = s;
  }

  if (integerPart.isEmpty && fractionPart.isEmpty) {
    return const MoneyParse.fail(MoneyProblem.invalid);
  }
  if (fractionPart.length > 2) {
    return const MoneyParse.fail(MoneyProblem.tooManyDecimals);
  }
  // Çok uzun tamsayı kısmı BigInt'e girmeden büyük sayılır.
  final trimmedInteger = integerPart.replaceFirst(RegExp(r'^0+'), '');
  if (trimmedInteger.length > 13) return const MoneyParse.fail(MoneyProblem.tooLarge);

  final lira = BigInt.parse(trimmedInteger.isEmpty ? '0' : trimmedInteger);
  final kurus = BigInt.parse(fractionPart.padRight(2, '0'));
  final total = lira * BigInt.from(100) + kurus;
  if (total > BigInt.from(maxMinor)) return const MoneyParse.fail(MoneyProblem.tooLarge);
  final minor = total.toInt();
  if (minor == 0 && !allowZero) return const MoneyParse.fail(MoneyProblem.zero);
  return MoneyParse.ok(minor);
}

/// Baştaki grup: 1-3 rakam, baştaki sıfır yok ("0" tek başına binlik grubunun başı SAYILMAZ).
bool _isFirstGroup(String group) =>
    RegExp(r'^[1-9][0-9]{0,2}$').hasMatch(group);

/// "1.250.000" gibi binlik gruplu metni ayırıcısız rakama çevirir; grup düzeni bozuksa null
/// (ilk grup 1-3 rakam ve baştaki sıfır yok, sonrakiler TAM 3 rakam; en az iki grup).
String? _stripThousands(String raw, String separator) {
  final groups = raw.split(separator);
  if (groups.length < 2) return null;
  if (!_isFirstGroup(groups.first)) return null;
  for (final group in groups.skip(1)) {
    if (!RegExp(r'^[0-9]{3}$').hasMatch(group)) return null;
  }
  return groups.join();
}

/// Form doğrulayıcısı: geçerliyse null, değilse Türkçe hata metni. [required] false iken boş giriş geçerlidir.
String? validateMoneyInput(
  String? text, {
  bool required = true,
  int maxMinor = kMaxMoneyMinor,
  bool allowZero = false,
}) {
  if (!required && (text ?? '').trim().isEmpty) return null;
  return parseMoney(text, maxMinor: maxMinor, allowZero: allowZero).message;
}

// --- Ekran okuyucu etiketi -----------------------------------------------------------------------

const List<String> _ones = <String>[
  '',
  'bir',
  'iki',
  'üç',
  'dört',
  'beş',
  'altı',
  'yedi',
  'sekiz',
  'dokuz',
];

const List<String> _tens = <String>[
  '',
  'on',
  'yirmi',
  'otuz',
  'kırk',
  'elli',
  'altmış',
  'yetmiş',
  'seksen',
  'doksan',
];

String _belowThousand(int n) {
  final hundreds = n ~/ 100;
  final tens = (n % 100) ~/ 10;
  final ones = n % 10;
  return <String>[
    if (hundreds > 0) hundreds == 1 ? 'yüz' : '${_ones[hundreds]} yüz',
    if (tens > 0) _tens[tens],
    if (ones > 0) _ones[ones],
  ].join(' ');
}

/// Sayının Türkçe okunuşu ("1234" -> "bin iki yüz otuz dört"). [n] negatif olamaz.
String turkishNumberWords(int n) {
  if (n < 0) throw ArgumentError.value(n, 'n', 'negatif olamaz');
  if (n == 0) return 'sıfır';
  const scales = <(int, String)>[
    (1000000000000, 'trilyon'),
    (1000000000, 'milyar'),
    (1000000, 'milyon'),
    (1000, 'bin'),
  ];
  var rest = n;
  final parts = <String>[];
  for (final (value, name) in scales) {
    final quotient = rest ~/ value;
    rest %= value;
    if (quotient == 0) continue;
    // Türkçede "bir bin" denmez ("bin"); milyon ve üstünde "bir milyon" denir.
    parts.add(value == 1000 && quotient == 1 ? name : '${_belowThousand(quotient)} $name');
  }
  if (rest > 0) parts.add(_belowThousand(rest));
  return parts.join(' ');
}

/// Ekran okuyucu etiketi: 123456 kuruş -> "bin iki yüz otuz dört lira elli altı kuruş". Negatif tutar
/// "eksi ..." ile başlar. Sıfır liralı tutarda lira söylenmez ("elli kuruş"); tam sıfır "sıfır lira".
String moneySemanticLabel(int minor) {
  final magnitude = minor.abs();
  final lira = magnitude ~/ 100;
  final kurus = magnitude % 100;
  final prefix = minor < 0 ? 'eksi ' : '';
  if (lira == 0 && kurus == 0) return 'sıfır lira';
  if (lira == 0) return '$prefix${turkishNumberWords(kurus)} kuruş';
  if (kurus == 0) return '$prefix${turkishNumberWords(lira)} lira';
  return '$prefix${turkishNumberWords(lira)} lira ${turkishNumberWords(kurus)} kuruş';
}
