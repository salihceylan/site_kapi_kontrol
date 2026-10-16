// Platform Faz 4a (Aidat ve Finans): para yardımcısı (lib/ui/helpers/money.dart).
//
// Sözleşme (docs/PLATFORM_FINANS.md, İlkeler 1): para tamsayı kuruştur; uygulamada HİÇBİR yerde kayan nokta
// ile para hesabı yapılmaz; "1.234,56" girişi kuruşa KESİN çevrilir (yuvarlama yok, >= 3 ondalık reddedilir).
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/ui/helpers/money.dart';

int? _ok(String input, {bool allowZero = false}) =>
    parseMoney(input, allowZero: allowZero).minor;

MoneyProblem? _problem(String input, {bool allowZero = false}) =>
    parseMoney(input, allowZero: allowZero).problem;

/// [0, max) aralığında rastgele tamsayı (`Random.nextInt` 2^32 ile sınırlıdır; en büyük tutar ~2^37).
int _randomBelow(Random random, int max) =>
    (random.nextInt(1 << 20) * (1 << 20) + random.nextInt(1 << 20)) % max;

void main() {
  group('formatMinor: kuruş -> "1.234,56 ₺"', () {
    test('örnekler', () {
      expect(formatMinor(0), '0,00 ₺');
      expect(formatMinor(1), '0,01 ₺');
      expect(formatMinor(9), '0,09 ₺');
      expect(formatMinor(10), '0,10 ₺');
      expect(formatMinor(99), '0,99 ₺');
      expect(formatMinor(100), '1,00 ₺');
      expect(formatMinor(123456), '1.234,56 ₺');
      expect(formatMinor(100000), '1.000,00 ₺');
      expect(formatMinor(99999), '999,99 ₺');
      expect(formatMinor(123456789), '1.234.567,89 ₺');
      expect(formatMinor(kMaxMoneyMinor), '999.999.999,99 ₺');
    });

    test('negatif tutar eksi işaretiyle, sembolsüz biçim yalnız sayıdır', () {
      expect(formatMinor(-123456), '-1.234,56 ₺');
      expect(formatMinor(-5), '-0,05 ₺');
      expect(formatMinor(123456, symbol: false), '1.234,56');
      expect(formatMinor(-123456, symbol: false), '-1.234,56');
    });

    test('formatSignedMinor: pozitife artı eklenir', () {
      expect(formatSignedMinor(150000), '+1.500,00 ₺');
      expect(formatSignedMinor(-150000), '-1.500,00 ₺');
      expect(formatSignedMinor(0), '0,00 ₺');
    });

    test('görünmez / yön karakteri yoktur (düz boşluk)', () {
      final text = formatMinor(123456);
      expect(text.runes.every((r) => r < 0x2000 || r == 0x20BA), isTrue, reason: text);
      expect(text.contains(String.fromCharCode(0x00A0)), isFalse);
      expect(text.contains(String.fromCharCode(0x200E)), isFalse);
    });
  });

  group('parseMoney: kabul edilen girişler', () {
    test('tamsayı lira', () {
      expect(_ok('0'), isNull, reason: 'sıfır reddedilir');
      expect(_ok('1'), 100);
      expect(_ok('12'), 1200);
      expect(_ok('1250'), 125000);
      expect(_ok('007'), 700);
    });

    test('virgül ondalıktır: 1 ya da 2 basamak', () {
      expect(_ok('1250,5'), 125050);
      expect(_ok('1250,50'), 125050);
      expect(_ok('1250,05'), 125005);
      expect(_ok('0,5'), 50);
      expect(_ok('0,05'), 5);
      expect(_ok(',5'), 50);
      expect(_ok('12,'), 1200);
    });

    test('nokta: tek nokta + tam 3 rakam = binlik; aksi halde ondalık', () {
      expect(_ok('1.250'), 125000, reason: 'binlik');
      expect(_ok('12.500'), 1250000, reason: 'binlik');
      expect(_ok('999.999'), 99999900);
      expect(_ok('1250.50'), 125050, reason: 'ondalık');
      expect(_ok('1250.5'), 125050, reason: 'ondalık');
      expect(_ok('12.5'), 1250);
      expect(_ok('.5'), 50);
      expect(_ok('0.50'), 50);
    });

    test('hem nokta hem virgül: son ayırıcı ondalıktır', () {
      expect(_ok('1.250,5'), 125050);
      expect(_ok('1.234,56'), 123456);
      expect(_ok('1.234.567,89'), 123456789);
      expect(_ok('1,234.56'), 123456);
      expect(_ok('1,234,567.89'), 123456789);
    });

    test('çok nokta = doğru gruplanmış binlik', () {
      expect(_ok('1.250.000'), 125000000);
      expect(_ok('12.345.678'), 1234567800);
    });

    test('para birimi işareti ve kenar boşlukları yok sayılır', () {
      expect(_ok('  1.234,56 ₺ '), 123456);
      expect(_ok('₺1.234,56'), 123456);
      expect(_ok('1.234,56 TL'), 123456);
      expect(_ok('1234,56tl'), 123456);
      expect(_ok('+50'), 5000);
    });

    test('en büyük kabul edilen tutar', () {
      expect(_ok('999.999.999,99'), kMaxMoneyMinor);
    });

    test('sıfır yalnız allowZero ile kabul edilir', () {
      expect(_ok('0', allowZero: true), 0);
      expect(_ok('0,00', allowZero: true), 0);
      expect(_problem('0,00'), MoneyProblem.zero);
    });
  });

  group('parseMoney: reddedilen girişler', () {
    // W5 (inceleme düzeltmesi): "₺" işareti eskiden sayının ORTASINDAN da sessizce siliniyordu ("12₺50" ->
    // 1.250,00 ₺). Artık yalnız baş / son kenarda kabul edilir; ortadaki işaret girişi geçersiz kılar.
    test('"₺" sayının ortasında REDDEDİLİR (sessizce silinmez)', () {
      for (final input in const <String>['12₺50', '1₺250', '1.2₺50', '₺12₺50', '12₺50₺', '1 ₺ 250', '₺₺5']) {
        expect(_problem(input), MoneyProblem.invalid, reason: '"$input" geçersiz olmalı');
      }
      // Kenardaki tek işaret hâlâ kabul edilir; boşluklu da.
      expect(_ok('₺ 1.250,50'), 125050);
      expect(_ok('1.250,50 ₺'), 125050);
      expect(_ok('₺1250'), 125000);
    });

    test('harf / E gösterimi / karışık metin: sessiz süzme yok, geçersiz', () {
      for (final input in const <String>['1,5E3', '12a5', 'abc12,5x', '1e3', '12 5', '1.2.3,4,5', '٣٤']) {
        expect(parseMoney(input).isOk, isFalse, reason: input);
      }
      expect(_problem('1,5E3'), MoneyProblem.invalid);
      expect(_problem('12a5'), MoneyProblem.invalid);
    });

    test('boş', () {
      expect(_problem(''), MoneyProblem.empty);
      expect(_problem('   '), MoneyProblem.empty);
      expect(parseMoney(null).problem, MoneyProblem.empty);
      expect(_problem('₺'), MoneyProblem.empty);
    });

    test('negatif', () {
      expect(_problem('-5'), MoneyProblem.negative);
      expect(_problem('-1.250,50'), MoneyProblem.negative);
      expect(_problem('\u22125'), MoneyProblem.negative, reason: 'Unicode eksi');
      expect(_problem('(5)'), MoneyProblem.negative);
    });

    test('3 ve üstü ondalık basamak', () {
      expect(_problem('1,250'), MoneyProblem.tooManyDecimals);
      expect(_problem('1250,505'), MoneyProblem.tooManyDecimals);
      expect(_problem('1.250,000'), MoneyProblem.tooManyDecimals);
      expect(_problem('1250.500'), MoneyProblem.tooManyDecimals);
      expect(_problem('0.250'), MoneyProblem.tooManyDecimals, reason: 'baştaki sıfır binlik olmaz');
      expect(_problem('1.2345'), MoneyProblem.tooManyDecimals);
    });

    test('aşırı büyük', () {
      expect(_problem('1.000.000.000'), MoneyProblem.tooLarge);
      expect(_problem('999.999.999,995'), MoneyProblem.tooManyDecimals);
      expect(_problem('1000000000'), MoneyProblem.tooLarge);
      expect(_problem('99999999999999999999'), MoneyProblem.tooLarge);
      expect(_problem('9' * 40), MoneyProblem.tooLarge);
    });

    test('bozuk gruplama / karakter', () {
      expect(_problem('1.25.000'), MoneyProblem.invalid);
      expect(_problem('1.2.3'), MoneyProblem.invalid);
      expect(_problem('1,2,3'), MoneyProblem.invalid);
      expect(_problem('1,250,000'), MoneyProblem.invalid, reason: 'virgül yalnız ondalıktır');
      expect(_problem('1.23,4.5'), MoneyProblem.invalid);
      expect(_problem('1,23.456,7'), MoneyProblem.invalid);
      expect(_problem('12 50'), MoneyProblem.invalid, reason: 'sayı içinde boşluk');
      expect(_problem('abc'), MoneyProblem.invalid);
      expect(_problem('12a'), MoneyProblem.invalid);
      expect(_problem('1e5'), MoneyProblem.invalid);
      expect(_problem('5-'), MoneyProblem.invalid);
      expect(_problem('.'), MoneyProblem.invalid);
      expect(_problem(','), MoneyProblem.invalid);
      expect(_problem('..'), MoneyProblem.invalid);
      expect(_problem('٥٠'), MoneyProblem.invalid, reason: 'Arapça rakam');
    });

    test('hata metinleri Türkçe ve teknik ifade içermez', () {
      for (final problem in MoneyProblem.values) {
        final message = moneyProblemMessage(problem);
        expect(message, isNotEmpty);
        expect(message.contains('_'), isFalse, reason: message);
        expect(message.contains('minor'), isFalse, reason: message);
      }
      expect(parseMoney('abc').message, 'Tutarı rakamlarla girin (örn. 1.250,50).');
      expect(parseMoney('12,345').message, 'Kuruş en çok 2 basamak olabilir (örn. 1.250,50).');
      expect(parseMoney('-1').message, 'Tutar negatif olamaz.');
      expect(parseMoney('').message, 'Tutarı girin.');
      expect(parseMoney('0').message, 'Tutar sıfırdan büyük olmalı.');
      expect(
        parseMoney('1.000.000.000').message,
        'Tutar en çok 999.999.999,99 ₺ olabilir.',
      );
      expect(parseMoney('1,5').message, isNull);
    });

    test('validateMoneyInput: zorunlu / isteğe bağlı', () {
      expect(validateMoneyInput(''), 'Tutarı girin.');
      expect(validateMoneyInput('', required: false), isNull);
      expect(validateMoneyInput('  ', required: false), isNull);
      expect(validateMoneyInput('abc', required: false), isNotNull);
      expect(validateMoneyInput('1.250,50'), isNull);
    });
  });

  group('özellik testleri: tam kuruş, kayan nokta yok', () {
    test('format -> parse her tutarda AYNI kuruşu verir (rastgele 20000 değer)', () {
      final random = Random(20261016);
      for (var i = 0; i < 20000; i++) {
        // Küçük, orta ve büyük ölçekleri dengeli dene.
        final scale = <int>[10, 1000, 100000, 10000000, kMaxMoneyMinor][random.nextInt(5)];
        final minor = 1 + _randomBelow(random, scale);
        final capped = minor > kMaxMoneyMinor ? kMaxMoneyMinor : minor;
        final text = formatMinor(capped, symbol: false);
        expect(_ok(text), capped, reason: '$capped -> "$text"');
        expect(_ok(formatMinor(capped)), capped, reason: 'sembollü: $capped');
      }
    });

    test('ondalık nokta ve virgül biçimleri aynı kuruşu verir', () {
      final random = Random(7);
      for (var i = 0; i < 5000; i++) {
        final lira = random.nextInt(100000); // binlik belirsizliği olmasın: 0-99999
        final kurus = random.nextInt(100);
        final expected = lira * 100 + kurus;
        if (expected == 0) continue;
        final k2 = kurus.toString().padLeft(2, '0');
        // Noktalı ondalık yalnız tek nokta + tam 2 basamak olduğunda belirsizlik yoktur.
        expect(_ok('$lira,$k2'), expected, reason: '$lira,$k2');
        expect(_ok('$lira.$k2'), expected, reason: '$lira.$k2');
        if (kurus % 10 == 0) {
          expect(_ok('$lira,${kurus ~/ 10}'), expected, reason: 'tek basamak');
        }
      }
    });

    test('3 ondalık basamaklı her giriş reddedilir (rastgele)', () {
      final random = Random(11);
      for (var i = 0; i < 2000; i++) {
        final lira = 1 + random.nextInt(100000);
        final tail = random.nextInt(1000).toString().padLeft(3, '0');
        // Virgülle: kesin ondalık. Noktayla "1.250" biçimi binliktir; 4+ haneli tamsayıda ondalıktır.
        expect(_problem('$lira,$tail'), MoneyProblem.tooManyDecimals, reason: '$lira,$tail');
        if (lira >= 1000) {
          expect(_problem('$lira.$tail'), MoneyProblem.tooManyDecimals, reason: '$lira.$tail');
        }
      }
    });

    test('biçimlenen metin her zaman geçerli bir tutardır ve 2 ondalık taşır', () {
      final random = Random(3);
      for (var i = 0; i < 2000; i++) {
        final minor = _randomBelow(random, kMaxMoneyMinor);
        final text = formatMinor(minor, symbol: false);
        expect(RegExp(r'^[0-9]{1,3}(\.[0-9]{3})*,[0-9]{2}$').hasMatch(text), isTrue, reason: text);
      }
    });

    test('money.dart kaynağında kayan nokta işlemi yok', () {
      final source = File('lib/ui/helpers/money.dart').readAsStringSync();
      // Yorumlar ve dize değişmezleri çıkarılır; kalan koddan kayan nokta ipuçları aranır.
      final code = source
          .split('\n')
          .map((line) {
            final at = line.indexOf('//');
            return at < 0 ? line : line.substring(0, at);
          })
          .join('\n')
          .replaceAll(RegExp(r"'(?:[^'\\]|\\.)*'"), "''")
          .replaceAll(RegExp(r'"(?:[^"\\]|\\.)*"'), '""');
      for (final banned in const <String>[
        'double',
        'toDouble',
        'toStringAsFixed',
        'toStringAsPrecision',
        'num.parse',
        'num.tryParse',
        '.round()',
        '.floor()',
        '.ceil()',
        '.truncate()',
        'pow(',
      ]) {
        expect(code.contains(banned), isFalse, reason: '"$banned" kullanılmamalı');
      }
      // `/` bölme işleci (double üretir) yok; tamsayı bölmesi `~/` kullanılır.
      expect(RegExp(r'(?<![~/])/(?![/*=])').hasMatch(code), isFalse, reason: 'bölme işleci "/" yok');
    });
  });

  group('moneySemanticLabel / turkishNumberWords', () {
    test('sözleşmedeki örnek', () {
      expect(moneySemanticLabel(123456), 'bin iki yüz otuz dört lira elli altı kuruş');
    });

    test('lira / kuruş kombinasyonları', () {
      expect(moneySemanticLabel(0), 'sıfır lira');
      expect(moneySemanticLabel(100), 'bir lira');
      expect(moneySemanticLabel(1), 'bir kuruş');
      expect(moneySemanticLabel(50), 'elli kuruş');
      expect(moneySemanticLabel(125000), 'bin iki yüz elli lira');
      expect(moneySemanticLabel(100000), 'bin lira');
      expect(moneySemanticLabel(10000000), 'yüz bin lira');
      expect(moneySemanticLabel(200000), 'iki bin lira');
      expect(moneySemanticLabel(100000000), 'bir milyon lira');
      expect(moneySemanticLabel(123456789), 'bir milyon iki yüz otuz dört bin beş yüz altmış yedi lira seksen dokuz kuruş');
      expect(moneySemanticLabel(kMaxMoneyMinor),
          'dokuz yüz doksan dokuz milyon dokuz yüz doksan dokuz bin dokuz yüz doksan dokuz lira doksan dokuz kuruş');
    });

    test('negatif tutar eksi ile başlar', () {
      expect(moneySemanticLabel(-125000), 'eksi bin iki yüz elli lira');
      expect(moneySemanticLabel(-50), 'eksi elli kuruş');
    });

    test('turkishNumberWords', () {
      expect(turkishNumberWords(0), 'sıfır');
      expect(turkishNumberWords(1), 'bir');
      expect(turkishNumberWords(10), 'on');
      expect(turkishNumberWords(11), 'on bir');
      expect(turkishNumberWords(100), 'yüz');
      expect(turkishNumberWords(101), 'yüz bir');
      expect(turkishNumberWords(110), 'yüz on');
      expect(turkishNumberWords(1000), 'bin');
      expect(turkishNumberWords(1001), 'bin bir');
      expect(turkishNumberWords(2000000), 'iki milyon');
      expect(turkishNumberWords(1000000000), 'bir milyar');
      expect(turkishNumberWords(1000000000000), 'bir trilyon');
      expect(() => turkishNumberWords(-1), throwsArgumentError);
    });

    test('spokenMoneyText: metindeki tutarlar okunuşa çevrilir, geri kalan metin aynen kalır', () {
      expect(spokenMoneyText('Tahsilat kaydedildi: 1.250,00 ₺.'), 'Tahsilat kaydedildi: bin iki yüz elli lira.');
      expect(
        spokenMoneyText('Ek borç yazıldı: 3 daire, toplam 100.000,00 ₺. Güncel bakiye: Borç 500,50 ₺.'),
        'Ek borç yazıldı: 3 daire, toplam yüz bin lira. Güncel bakiye: Borç beş yüz lira elli kuruş.',
      );
      expect(spokenMoneyText('-50,00 ₺ alacak'), 'eksi elli lira alacak');
      expect(spokenMoneyText('0,05 ₺'), 'beş kuruş');
      expect(spokenMoneyText('Tutar yok, 3 daire.'), 'Tutar yok, 3 daire.');
      // Binlik ayırıcısız ya da kuruşsuz yazımlar dokunulmaz (formatMinor üretmez).
      expect(spokenMoneyText('1250 ₺'), '1250 ₺');
      // formatMinor çıktısıyla bire bir tutarlı.
      for (final minor in const <int>[1, 99, 100, 123456, 99999999999]) {
        expect(spokenMoneyText(formatMinor(minor)), moneySemanticLabel(minor), reason: '$minor');
      }
    });

    test('her kuruş değeri için etiket boş değildir ve rakam içermez', () {
      final random = Random(5);
      for (var i = 0; i < 3000; i++) {
        final minor = _randomBelow(random, kMaxMoneyMinor);
        final label = moneySemanticLabel(minor);
        expect(label, isNotEmpty);
        expect(RegExp(r'[0-9]').hasMatch(label), isFalse, reason: label);
        expect(label, anyOf(contains('lira'), contains('kuruş')));
      }
    });
  });
}
