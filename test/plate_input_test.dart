// Plaka girdisi (lib/ui/helpers/plate_input.dart): sunucudaki Türk plakası kuralı (server/src/modules/plate_format.js) ile aynı
// kural, yazarken gruplayan giriş süzgeçleri, çok plakalı alan ve doğrulayıcılar.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/ui/helpers/plate_input.dart';

const String _invalid = 'Plaka biçimi geçersiz. Örnek: 34 ABC 123 (il kodu 01-81).';

TextEditingValue _v(String text, [int? caret]) =>
    TextEditingValue(text: text, selection: TextSelection.collapsed(offset: caret ?? text.length));

/// [chars]'i tek tek yazar (her tuş sonu imleçte); her adımdan sonraki metinleri döndürür.
List<String> _type(TextInputFormatter f, String chars, {TextEditingValue? from}) {
  var value = from ?? TextEditingValue.empty;
  final out = <String>[];
  for (final rune in chars.runes) {
    final ch = String.fromCharCode(rune);
    final caret = value.selection.baseOffset < 0 ? value.text.length : value.selection.baseOffset;
    final next = TextEditingValue(
      text: value.text.replaceRange(caret, value.selection.extentOffset < 0 ? caret : value.selection.extentOffset, ch),
      selection: TextSelection.collapsed(offset: caret + ch.length),
    );
    value = f.formatEditUpdate(value, next);
    out.add(value.text);
  }
  return out;
}

String _typed(TextInputFormatter f, String chars) => _type(f, chars).last;

void main() {
  const single = PlateInputFormatter();
  const list = PlateListInputFormatter();

  group('kural: sunucuyla aynı tablo (server/test/plate_format.test.js)', () {
    test('geçerli plakalar normalize edilir', () {
      for (final plate in <String>['01A12', '34ABC123', '06XY789', '81Z1234', '34AB12', '07ABC1234', '10A99', '80ABC12', '81AB123']) {
        expect(normalizePlateInput(plate), plate, reason: plate);
      }
      expect(normalizePlateInput('34 abc 123'), '34ABC123');
      expect(normalizePlateInput('34-ABC-123'), '34ABC123');
      expect(normalizePlateInput(' 06 a 1234 '), '06A1234');
      expect(normalizePlateInput('34.abc.123'), '34ABC123');
      expect(normalizePlateInput('34 şçğ 12'), '34SCG12');
    });

    test('geçersiz plakalar', () {
      for (final bad in <String>[
        '00ABC123', '82ABC123', '99ABC123', '34ABC1', '34ABC12345', '34ABCD123', '34123', '34ABC', 'ABC123', '3ABC123', '34 12 ABC',
        'ABC12345', '12345', '34A', '34ABC12A', '3412ABC', '340ABC12', '34-', '', '   ',
      ]) {
        expect(normalizePlateInput(bad), isNull, reason: bad);
      }
      expect(normalizePlateInput(null), isNull);
      expect(normalizePlateInput('34 ABC 123 ' * 3), isNull, reason: '24 karakterden uzun');
    });

    test('formatPlateInput: geçerliyse "34 ABC 123", değilse büyük harfle yazıldığı gibi', () {
      expect(formatPlateInput('34abc123'), '34 ABC 123');
      expect(formatPlateInput(' 06-xy-12 '), '06 XY 12');
      expect(formatPlateInput('abc  12345'), 'ABC 12345');
      expect(formatPlateInput(null), '');
    });

    test('isPlatePrefix: plakaya götürebilecek başlangıçlar', () {
      for (final ok in <String>['', '0', '3', '8', '34', '81', '01', '34A', '34ABC', '34ABC1', '34ABC123', '34A1234']) {
        expect(isPlatePrefix(ok), isTrue, reason: ok);
      }
      for (final bad in <String>['9', '3A', '00', '82', '85', '90', '341', '34ABCD', '34ABC12345', '34A1B', '34123', 'A']) {
        expect(isPlatePrefix(bad), isFalse, reason: bad);
      }
    });
  });

  group('PlateInputFormatter: yazarken', () {
    test('34ABC123 adım adım gruplanır', () {
      expect(_type(single, '34abc123'), <String>['3', '34', '34 A', '34 AB', '34 ABC', '34 ABC 1', '34 ABC 12', '34 ABC 123']);
    });

    test('1 ve 2 harfli, 2 / 4 rakamlı plakalar', () {
      expect(_typed(single, '06a1234'), '06 A 1234');
      expect(_typed(single, '35dd45'), '35 DD 45');
      expect(_typed(single, '81xy12'), '81 XY 12');
    });

    test('büyük harfe çevirir; Türkçe harf ASCII olur (i, ı, İ -> I)', () {
      expect(_typed(single, '34abc'), '34 ABC');
      expect(_typed(single, '34şğü12'), '34 SGU 12');
      expect(_typed(single, '34çöı12'), '34 COI 12');
      expect(_typed(single, '34İi12'), '34 II 12');
    });

    test('ayırıcılar (boşluk, tire, nokta, alt çizgi) atılır; metin değişmez', () {
      expect(_typed(single, '34 ABC 123'), '34 ABC 123');
      expect(_typed(single, '34-ABC.123_'), '34 ABC 123');
      expect(_type(single, '34 '), <String>['3', '34', '34']);
    });

    test('plakaya götürmeyen tuşlar reddedilir (metin ve imleç eski kalır)', () {
      // il kodunda harf
      expect(_typed(single, 'a'), '');
      expect(_typed(single, '3a'), '3');
      // il kodu 00 ve 81'den büyük
      expect(_typed(single, '9'), '');
      expect(_typed(single, '00'), '0');
      expect(_typed(single, '82'), '8');
      expect(_typed(single, '85'), '8');
      expect(_typed(single, '90'), '0', reason: '9 reddedilir, ardından 0 yeni başlangıçtır');
      // harfsiz rakam
      expect(_typed(single, '341'), '34');
      // 4. harf, 5. rakam, harfin ardından yeniden harf
      expect(_typed(single, '34abcd'), '34 ABC');
      expect(_typed(single, '34abc12345'), '34 ABC 1234');
      expect(_typed(single, '34a1b'), '34 A 1');
      // harf / rakam / ayırıcı dışı
      expect(_typed(single, '34!'), '34');
      expect(_typed(single, '34@'), '34');
      expect(_typed(single, '34,'), '34');
      expect(_typed(single, '34é'), '34');
      expect(_typed(single, '34ß'), '34');
    });

    test('reddedilen tuş imleci olduğu yerde bırakır', () {
      final old = _v('34 ABC', 4);
      final out = single.formatEditUpdate(old, _v('34 ABCD', 7));
      expect(out.text, '34 ABC');
      expect(out.selection, old.selection);
    });

    test('yapıştırma: tam plaka biçimlenir; geçersiz yapıştırma reddedilir', () {
      expect(single.formatEditUpdate(TextEditingValue.empty, _v('34-abc-123')).text, '34 ABC 123');
      expect(single.formatEditUpdate(TextEditingValue.empty, _v('34-abc-123')).selection.baseOffset, 10);
      expect(single.formatEditUpdate(TextEditingValue.empty, _v(' 06 xy 789 ')).text, '06 XY 789');
      expect(single.formatEditUpdate(TextEditingValue.empty, _v('ABC12345')).text, '');
      expect(single.formatEditUpdate(TextEditingValue.empty, _v('34 ABC 123456')).text, '');
      expect(single.formatEditUpdate(_v('34 A'), _v('34 A99 ABC')).text, '34 A');
    });

    test('imleç: ortaya yazma, ayırıcı ekleme ve silme', () {
      // ortaya harf ekleme: biçim aynı kalır, imleç harfin sağında
      final mid = single.formatEditUpdate(_v('34 AC 123', 4), _v('34 ABC 123', 5));
      expect(mid.text, '34 ABC 123');
      expect(mid.selection.baseOffset, 5);
      // ilk harf: otomatik boşluk eklenir, imleç harfin sağında
      final first = single.formatEditUpdate(_v('34', 2), _v('34A', 3));
      expect(first.text, '34 A');
      expect(first.selection.baseOffset, 4);
      // seçili parçayı değiştirme
      final replace = single.formatEditUpdate(
        const TextEditingValue(text: '34 ABC 123', selection: TextSelection(baseOffset: 3, extentOffset: 6)),
        _v('34 X 123', 4),
      );
      expect(replace.text, '34 X 123');
      expect(replace.selection.baseOffset, 4);
      // ortadaki rakam ekleme: plaka bozulacaksa reddedilir ve imleç eski kalır
      final bad = single.formatEditUpdate(_v('34 ABC', 1), _v('354 ABC', 2));
      expect(bad.text, '34 ABC');
      expect(bad.selection.baseOffset, 1);
    });

    test('geri tuşu: otomatik boşluğu aşar, sonra rakamı siler; yeni rakamla düzeltilir', () {
      // "34 A|" -> A silinir -> "34" (sondaki boşluk atılır)
      final a = single.formatEditUpdate(_v('34 A'), _v('34 '));
      expect(a.text, '34');
      expect(a.selection.baseOffset, 2);
      // "34 |A" -> boşluk silinmek istenir: metin aynı kalır, imleç boşluğun soluna geçer
      final space = single.formatEditUpdate(_v('34 A', 3), _v('34A', 2));
      expect(space.text, '34 A');
      expect(space.selection.baseOffset, 2);
      // "34| A" -> 4 silinir: ara hâl ("3 A") serbesttir
      final digit = single.formatEditUpdate(_v('34 A', 2), _v('3 A', 1));
      expect(digit.text, '3 A');
      expect(digit.selection.baseOffset, 1);
      // ... ve "3| A" önüne 5 yazılınca plaka geçerli olur
      final fixed = single.formatEditUpdate(_v('3 A', 1), _v('35 A', 2));
      expect(fixed.text, '35 A');
    });

    test('Delete tuşu: otomatik boşluğu aşar', () {
      // "34| A" imleçte Delete: boşluk silinmek istenir -> metin aynı, imleç boşluğun sağına
      final out = single.formatEditUpdate(_v('34 A', 2), _v('34A', 2));
      expect(out.text, '34 A');
      expect(out.selection.baseOffset, 3);
    });

    test('tümünü silme ve baştan silme serbest', () {
      expect(single.formatEditUpdate(_v('34 ABC 123'), TextEditingValue.empty).text, '');
      final mid = single.formatEditUpdate(_v('34 ABC 123', 6), _v('34 AB 123', 5));
      expect(mid.text, '34 AB 123');
      final head = single.formatEditUpdate(_v('34 ABC 123', 1), _v('4 ABC 123', 0));
      expect(head.text, '4 ABC 123', reason: 'ara hâl (silerken) serbest; doğrulayıcı yakalar');
      expect(validatePlate(head.text), _invalid);
    });

    test('eski (kurala uymayan) değer: silerek temizlenir, üzerine yazılamaz', () {
      const legacy = TextEditingValue(text: 'ABC 12345', selection: TextSelection.collapsed(offset: 9));
      expect(single.formatEditUpdate(legacy, _v('ABC 1234', 8)).text, 'ABC 1234');
      expect(single.formatEditUpdate(legacy, _v('ABC 12345 6', 11)).text, 'ABC 12345', reason: 'ekleme reddedilir');
      expect(single.formatEditUpdate(legacy, TextEditingValue.empty).text, '');
    });

    test('değişmeyen biçimli metin aynen döner (seçim ve birleştirme bölgesi korunur)', () {
      final value = TextEditingValue(
        text: '34 ABC',
        selection: const TextSelection.collapsed(offset: 6),
        composing: const TextRange(start: 3, end: 6),
      );
      expect(identical(single.formatEditUpdate(_v('34 AB'), value), value), isTrue);
    });
  });

  group('validatePlate', () {
    test('geçerli plaka null; boş ya da geçersiz sunucu iletisi', () {
      expect(validatePlate('34 ABC 123'), isNull);
      expect(validatePlate('34abc123'), isNull);
      expect(validatePlate(''), _invalid);
      expect(validatePlate(null), _invalid);
      expect(validatePlate('34 A 1'), _invalid);
      expect(validatePlate('ABC12345'), _invalid);
      expect(kPlateInvalidMessage, _invalid);
    });

    test('alan ilk değeriyle aynıysa (eski kayıt) engellenmez; değişince engellenir', () {
      expect(validatePlate('ABC 12345', initial: 'ABC 12345'), isNull);
      expect(validatePlate(' ABC 12345 ', initial: 'ABC 12345'), isNull);
      expect(validatePlate('ABC 1234', initial: 'ABC 12345'), _invalid);
      expect(validatePlate('', initial: ''), _invalid, reason: 'boş ilk değer korunmaz');
    });
  });

  group('çok plakalı alan', () {
    test('parsePlateList: ayırıcılar, normalize, yinelenen, görünen biçim', () {
      final r = parsePlateList('34 abc 123, 06 XY 789; 34ABC123 / 35-DD-4567');
      expect(r.isValid, isTrue);
      expect(r.plates.map((e) => e.plate), <String>['34ABC123', '06XY789', '35DD4567']);
      expect(r.plates.map((e) => e.display), <String>['34 ABC 123', '06 XY 789', '35 DD 4567']);
    });

    test('en çok 5 plaka; geçersiz parçalar adıyla; formül benzeri başlangıç; boş serbest', () {
      expect(parsePlateList('11AAA11, 22BBB22, 33CCC33, 44DDD44, 55EEE55, 66FFF66').tooMany, isTrue);
      expect(parsePlateList('34 ABC 123, XY').invalid, <String>['XY']);
      expect(parsePlateList('ABC12345, 99 ZZ 1').invalid, <String>['ABC12345', '99 ZZ 1']);
      expect(parsePlateList('=34ABC123').formulaLike, isTrue);
      expect(parsePlateList('  ').plates, isEmpty);
      expect(parsePlateList(null).isValid, isTrue);
    });

    test('kayıtlı eski plaka (preserved) geçerli sayılır ve listede kalır', () {
      final r = parsePlateList('ABC 12345, 34 ABC 123', preserved: const <String>{'ABC12345'});
      expect(r.isValid, isTrue);
      expect(r.plates.map((e) => e.plate), <String>['ABC12345', '34ABC123']);
      // kayıtlı olmayan eski biçim hâlâ geçersiz
      expect(parsePlateList('ABC 12345', preserved: const <String>{'XYZ98765'}).invalid, <String>['ABC 12345']);
    });

    test('validatePlateList: tek ileti, geçersiz plakayı adıyla söyler', () {
      expect(validatePlateList('34 ABC 123, 06 XY 789'), isNull);
      expect(validatePlateList(''), isNull);
      expect(validatePlateList('34 ABC 123, ABC12345'), 'Plaka biçimi geçersiz: ABC12345. Örnek: 34 ABC 123 (il kodu 01-81).');
      expect(
        validatePlateList('ABC12345, 99 ZZ 1'),
        'Plaka biçimi geçersiz: ABC12345, 99 ZZ 1. Örnek: 34 ABC 123 (il kodu 01-81).',
      );
      expect(validatePlateList('=34ABC123'), 'Plaka biçimi geçersiz: =, @, + ya da - ile başlayamaz.');
      expect(validatePlateList('11AAA11, 22BBB22, 33CCC33, 44DDD44, 55EEE55, 66FFF66'), 'En çok 5 plaka girilebilir; virgülle ayırın.');
    });

    test('validatePlateList: kayıtlı eski plaka ve değişmemiş alan engellenmez', () {
      expect(validatePlateList('ABC 12345, 34 ABC 123', preserved: const <String>{'ABC12345'}), isNull);
      expect(validatePlateList('ABC 12345, 34 ABC 123'), isNotNull);
      const six = '11AAA11, 22BBB22, 33CCC33, 44DDD44, 55EEE55, 66FFF66';
      expect(validatePlateList(six, initial: six), isNull, reason: 'eski kayıtta 5\'ten çok plaka: değişmemiş alan geçer');
      expect(validatePlateList('$six, 77GGG77', initial: six), isNotNull);
    });

    test('formatPlateList: her plaka biçimlenir', () {
      expect(formatPlateList('34abc123;06-xy-789 / ABC12345'), '34 ABC 123, 06 XY 789, ABC12345');
      expect(formatPlateList(''), '');
      expect(formatPlateList(null), '');
    });
  });

  group('PlateListInputFormatter', () {
    test('plakalar adım adım ", " ile ayrılıp gruplanır', () {
      expect(
        _type(list, '34abc123,06xy7'),
        <String>[
          '3', '34', '34 A', '34 AB', '34 ABC', '34 ABC 1', '34 ABC 12', '34 ABC 123',
          '34 ABC 123,', '34 ABC 123, 0', '34 ABC 123, 06', '34 ABC 123, 06 X', '34 ABC 123, 06 XY', '34 ABC 123, 06 XY 7',
        ],
      );
    });

    test(';  /  |  ve satır sonu virgüle çevrilir; baştaki ve yinelenen virgül atılır', () {
      expect(_typed(list, '34abc123;'), '34 ABC 123,');
      expect(_typed(list, '34abc123/'), '34 ABC 123,');
      expect(_typed(list, '34abc123|'), '34 ABC 123,');
      expect(_typed(list, '34abc123\n'), '34 ABC 123,');
      expect(_typed(list, ','), '');
      expect(_typed(list, '34abc123,,'), '34 ABC 123,');
    });

    test('her parça plaka kuralına uymalı; geçersiz tuş reddedilir', () {
      expect(_typed(list, '34abc123,a'), '34 ABC 123,');
      expect(_typed(list, '34abc123,99'), '34 ABC 123,', reason: '9 ile başlayan plaka yok');
      expect(_typed(list, '34abc123,06xy78901'), '34 ABC 123, 06 XY 7890');
      expect(_typed(list, '34abc!'), '34 ABC');
    });

    test('en çok 5 plaka: 6. plaka (ve 5. plakadan sonra virgül) yazılamaz', () {
      const five = '11 AAA 11, 22 BBB 22, 33 CCC 33, 44 DDD 44, 55 EEE 55';
      expect(list.formatEditUpdate(_v(five), _v('$five,')).text, five);
      expect(list.formatEditUpdate(_v('11 AAA 11, 22 BBB 22, 33 CCC 33, 44 DDD 44,'), _v('11 AAA 11, 22 BBB 22, 33 CCC 33, 44 DDD 44, 5')).text,
          '11 AAA 11, 22 BBB 22, 33 CCC 33, 44 DDD 44, 5');
    });

    test('yapıştırma: virgüllü liste biçimlenir', () {
      final out = list.formatEditUpdate(TextEditingValue.empty, _v('34abc123 ; 06-xy-789'));
      expect(out.text, '34 ABC 123, 06 XY 789');
      expect(out.selection.baseOffset, 21);
    });

    test('sondaki virgülü silmek: boşluk atılır, imleç sonda; ikinci geri tuşu virgülü siler', () {
      final a = list.formatEditUpdate(_v('34 ABC 123, 0'), _v('34 ABC 123, '));
      expect(a.text, '34 ABC 123,');
      expect(a.selection.baseOffset, 11);
      final b = list.formatEditUpdate(a, _v('34 ABC 123'));
      expect(b.text, '34 ABC 123');
    });

    test('ortadaki ayırıcıyı silmek metni bozmaz, imleç ayırıcıyı aşar', () {
      // "34 ABC 123, |06 XY 789": geri tuşu boşluğu silmek ister
      final out = list.formatEditUpdate(_v('34 ABC 123, 06 XY 789', 12), _v('34 ABC 123,06 XY 789', 11));
      expect(out.text, '34 ABC 123, 06 XY 789');
      expect(out.selection.baseOffset, 11, reason: 'virgülün sağında kalır; sonraki geri tuşu virgülü siler');
    });

    test('kayıtlı eski plaka (preserved) bozulmaz; yanına yenisi eklenebilir; üzerine yazılamaz', () {
      const legacy = PlateListInputFormatter(preserved: <String>{'ABC12345'});
      expect(legacy.formatEditUpdate(_v('ABC 12345'), _v('ABC 12345,')).text, 'ABC 12345,');
      expect(legacy.formatEditUpdate(_v('ABC 12345,'), _v('ABC 12345,3')).text, 'ABC 12345, 3');
      expect(legacy.formatEditUpdate(_v('ABC 12345, 34'), _v('ABC 12345, 34 ABC 123 ')).text, 'ABC 12345, 34 ABC 123');
      expect(legacy.formatEditUpdate(_v('ABC 12345'), _v('ABC 123456')).text, 'ABC 12345', reason: 'yeni karakter reddedilir');
      // aynı eski değer eski plaka listesi olmayan süzgeçte de silinebilir
      expect(list.formatEditUpdate(_v('ABC 12345'), _v('ABC 1234')).text, 'ABC 1234');
    });
  });
}
