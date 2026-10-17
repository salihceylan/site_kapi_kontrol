// Toplu yükleme: kodlama çözücü ve CSV okuyucu / yazıcı (Platform Faz 2b).
//
// Altın dosyalar: UTF-8 (BOM'lu / BOM'suz), UTF-16LE sekmeli ("Unicode Metin"), Windows-1254. Kötü niyetli / bozuk
// girdiler (kapanmamış tırnak, 200.000 satır, 40+ sütun) 2 sn altında ve DÜRÜST hata ile sonuçlanır.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/services/bulk_csv_codec.dart';
import 'package:site_kapi_kontrol/services/bulk_sheet_types.dart';
import 'package:site_kapi_kontrol/services/bulk_text_decoder.dart';

import 'bulk_test_support.dart';

Uint8List _utf8(String s, {bool bom = false}) =>
    Uint8List.fromList(<int>[if (bom) ...<int>[0xEF, 0xBB, 0xBF], ...utf8.encode(s)]);

Uint8List _utf16le(String s, {bool bom = true}) {
  final units = s.codeUnits;
  final out = Uint8List((units.length + (bom ? 1 : 0)) * 2);
  var i = 0;
  if (bom) {
    out[i++] = 0xFF;
    out[i++] = 0xFE;
  }
  for (final u in units) {
    out[i++] = u & 0xFF;
    out[i++] = u >> 8;
  }
  return out;
}

/// Windows-1254 kodlayıcı (yalnız test için: Türkçe harfler + ASCII).
Uint8List _cp1254(String s) {
  const map = <String, int>{
    'Ğ': 0xD0, 'İ': 0xDD, 'Ş': 0xDE, 'ğ': 0xF0, 'ı': 0xFD, 'ş': 0xFE,
    'Ç': 0xC7, 'Ö': 0xD6, 'Ü': 0xDC, 'ç': 0xE7, 'ö': 0xF6, 'ü': 0xFC,
    '€': 0x80, '’': 0x92,
  };
  return Uint8List.fromList(<int>[
    for (final rune in s.runes) map[String.fromCharCode(rune)] ?? rune,
  ]);
}

List<List<Object?>> _grid(SheetTable t) => <List<Object?>>[for (final r in t.rows) r.cells];

void main() {
  group('kodlama çözücü', () {
    test('BOM\'suz UTF-8 Türkçe karakterler', () {
      final d = decodeSpreadsheetText(_utf8('Ad Soyad;Şehir\nÇağlar Öztürk;İzmir\n'));
      expect(d.text, contains('Çağlar Öztürk'));
      expect(d.label, 'UTF-8');
      expect(d.fallback, isFalse);
    });

    test('BOM\'lu UTF-8: BOM metne sızmaz', () {
      final d = decodeSpreadsheetText(_utf8('Ad;Soyad\n', bom: true));
      expect(d.text.startsWith('Ad'), isTrue);
      expect(d.text.codeUnitAt(0), isNot(0xFEFF));
    });

    test('UTF-16LE (Excel Unicode Metin, sekmeli)', () {
      final d = decodeSpreadsheetText(_utf16le('Ad Soyad\tŞehir\r\nĞamze Işık\tİstanbul\r\n'));
      expect(d.text, contains('Ğamze Işık'));
      expect(d.label, 'UTF-16');
    });

    test('UTF-16BE BOM\'u', () {
      final le = _utf16le('Aş;Bö', bom: false);
      final be = Uint8List(le.length + 2)
        ..[0] = 0xFE
        ..[1] = 0xFF;
      for (var i = 0; i < le.length; i += 2) {
        be[2 + i] = le[i + 1];
        be[2 + i + 1] = le[i];
      }
      expect(decodeSpreadsheetText(be).text, 'Aş;Bö');
    });

    test('BOM\'suz UTF-16LE sezgisi', () {
      final d = decodeSpreadsheetText(_utf16le('Ad Soyad;Telefon\r\nAli;555\r\n', bom: false));
      expect(d.text, contains('Ad Soyad;Telefon'));
    });

    test('Windows-1254 altın dosya ve açık not', () {
      final d = decodeSpreadsheetText(_cp1254('Ad Soyad;Şehir\nĞamze Işık;İstanbul\nÇiğdem Ünal;Şişli\n'));
      expect(d.fallback, isTrue);
      expect(d.label, 'Windows-1254');
      expect(d.note, 'Windows-1254 olarak okundu');
      expect(d.text, contains('Ğamze Işık;İstanbul'));
      expect(d.text, contains('Çiğdem Ünal;Şişli'));
    });

    test('Windows-1254 0x80-0x9F tablosu: euro ve kıvrık tırnak', () {
      final d = decodeSpreadsheetText(Uint8List.fromList(<int>[0x80, 0x92, 0xFD, 0x20, 0x81]));
      expect(d.text.runes.first, 0x20AC);
      expect(d.text.runes.elementAt(1), 0x2019);
      expect(d.text.runes.elementAt(2), 0x131);
      expect(d.text.runes.last, 0xFFFD);
    });

    test('boş dosya ve ikili (NUL içeren) dosya dürüst hata verir', () {
      expect(() => decodeSpreadsheetText(Uint8List(0)), throwsA(isA<SpreadsheetException>()));
      expect(
        () => decodeSpreadsheetText(Uint8List.fromList(<int>[0x41, 0x00, 0x00, 0x00, 0x42, 0x01, 0x02, 0x03, 0x04])),
        throwsA(isA<SpreadsheetException>()),
      );
    });
  });

  group('CSV okuyucu', () {
    test('Türkçe CSV: ; ayırıcı, ondalık virgül, binlik nokta metin olarak korunur', () {
      final t = parseCsvText('Blok;Daire No;Brüt m²\nA Blok;5;1.250,50\nA Blok;6;125,5\n');
      expect(t.delimiter, ';');
      expect(_grid(t), <List<Object?>>[
        <Object?>['Blok', 'Daire No', 'Brüt m²'],
        <Object?>['A Blok', '5', '1.250,50'],
        <Object?>['A Blok', '6', '125,5'],
      ]);
      expect(t.rows.map((r) => r.n), <int>[1, 2, 3]);
    });

    test('virgül ve TAB ve | ayırıcıları sezilir', () {
      expect(parseCsvText('a,b,c\n1,2,3\n4,5,6\n').delimiter, ',');
      expect(parseCsvText('a\tb\tc\n1\t2\t3\n').delimiter, '\t');
      expect(parseCsvText('a|b|c\n1|2|3\n').delimiter, '|');
    });

    test('; dosyasında ondalık virgül ayırıcıyı yanıltmaz', () {
      final t = parseCsvText('Ad;Alan;Not\nAli;1,5;x\nVeli;2,25;y\nAyşe;3,75;z\n');
      expect(t.delimiter, ';');
      expect(t.rows.length, 4);
      expect(t.rows[1].cells, <Object?>['Ali', '1,5', 'x']);
    });

    test('sep=; ilk satırı ayırıcıyı belirler ve atlanır; numara korunur', () {
      final t = parseCsvText('sep=,\r\nAd,Soyad\r\nAli,Veli\r\n');
      expect(t.delimiter, ',');
      expect(t.rows.first.cells, <Object?>['Ad', 'Soyad']);
      expect(t.rows.first.n, 1, reason: 'sep= satırı Excel\'de görünmez, sayılmaz');
    });

    test('tırnak içinde ayırıcı, satır sonu ve çift tırnak', () {
      final t = parseCsvText('Ad;Not\n"Yılmaz; Ahmet";"satır1\nsatır2 ""alıntı"""\nX;Y\n');
      expect(t.rows[1].cells, <Object?>['Yılmaz; Ahmet', 'satır1\nsatır2 "alıntı"']);
      expect(t.rows[2].cells, <Object?>['X', 'Y']);
      expect(t.rows[2].n, 3, reason: 'çok satırlı hücre tek kayıttır');
    });

    test('CR, LF ve CRLF satır sonları', () {
      for (final eol in <String>['\r\n', '\n', '\r']) {
        final t = parseCsvText('a;b${eol}1;2${eol}3;4$eol');
        expect(t.rows.length, 3, reason: 'eol=${eol.codeUnits}');
        expect(t.rows.last.cells, <Object?>['3', '4']);
      }
    });

    test('boş kayıtlar atlanır ama satır numarası korunur', () {
      final t = parseCsvText('Ad;Soyad\n\n;;\nAli;Veli\n');
      expect(t.rows.length, 2);
      expect(t.rows.last.n, 4);
    });

    test('baş / son boşluk kırpılır, boş hücre null olur', () {
      final t = parseCsvText('a;b;c\n  x  ;;"  y  "\n');
      expect(t.rows[1].cells, <Object?>['x', null, 'y']);
    });

    test('kapanmamış tırnak: kalan satırlar sessizce yutulmaz, dürüst hata', () {
      expect(
        () => parseCsvText('a;b\n1;"2\n3;4\n5;6\n'),
        throwsA(
          isA<SpreadsheetException>().having((e) => e.message, 'ileti', contains('kapanmamış tırnak')),
        ),
      );
    });

    test('hücre içi tek tırnak harfi (5" gibi) bozmaz', () {
      final t = parseCsvText('a;b\n5" pencere;x\n');
      expect(t.rows[1].cells, <Object?>['5" pencere', 'x']);
    });

    test('40\'tan fazla DOLU sütun hata; boş fazlalık sorun değil', () {
      final wide = List<String>.generate(41, (i) => 'c$i').join(';');
      expect(() => parseCsvText('$wide\n'), throwsA(isA<SpreadsheetException>()));
      final padded = '${List<String>.generate(3, (i) => 'c$i').join(';')}${';' * 60}\n';
      expect(parseCsvText(padded).rows.first.cells.length, 3);
    });

    test('formül öneki olan hücre OLDUĞU GİBİ okunur (silinmez, değiştirilmez)', () {
      final t = parseCsvText('Ad;Not\n=1+1;@SUM(A1)\n+90555;-1\n');
      expect(t.rows[1].cells, <Object?>['=1+1', '@SUM(A1)']);
      expect(t.rows[2].cells, <Object?>['+90555', '-1']);
    });

    test('çok uzun hücre 601 karakterde kesilir', () {
      final t = parseCsvText('a;b\n${'x' * 5000};y\n');
      expect((t.rows[1].cells[0] as String).length, SheetLimits.cellTextCap);
    });

    test('200.000 satır: ilk 5011 dolu kayıtta DURUR, 2 sn altında', () {
      final sb = StringBuffer('Ad Soyad;Telefon\n');
      for (var i = 0; i < 200000; i++) {
        sb.write('Kişi $i;555$i\n');
      }
      final text = sb.toString();
      final (ms, t) = bestOfMillis(() => parseCsvText(text));
      expect(t.truncated, isTrue);
      expect(t.rows.length, SheetLimits.maxRecords);
      expect(ms, lessThan(2000), reason: '$ms ms');
    });

    test('milyonlarca boş satır hızlı geçilir', () {
      final text = 'a;b\n${'\n' * 2000000}1;2\n';
      final (ms, t) = bestOfMillis(() => parseCsvText(text));
      expect(t.rows.length, 2);
      expect(t.rows.last.n, 2000002);
      expect(ms, lessThan(2000), reason: '$ms ms');
    });

    test('tek sütunlu dosya (yalnız adlar) bozulmaz', () {
      final t = parseCsvText('Ad Soyad\nAli Veli\nAyşe, Fatma\n');
      expect(t.rows.length, 3);
    });
  });

  group('CSV yazıcı', () {
    test('BOM, ; ayırıcı ve CRLF', () {
      final bytes = csvBytes(<List<String>>[
        <String>['Ad', 'Not'],
        <String>['Ali', 'x'],
      ]);
      expect(bytes.sublist(0, 3), <int>[0xEF, 0xBB, 0xBF]);
      expect(utf8.decode(bytes.sublist(3)), 'Ad;Not\r\nAli;x\r\n');
    });

    test('; " CR LF içeren ve baş/son boşluklu hücre tırnaklanır', () {
      expect(csvEncodeCell('a;b'), '"a;b"');
      expect(csvEncodeCell('say "x"'), '"say ""x"""');
      expect(csvEncodeCell('a\nb'), '"a\nb"');
      expect(csvEncodeCell(' a'), '" a"');
      expect(csvEncodeCell('a '), '"a "');
      expect(csvEncodeCell('düz'), 'düz');
      expect(csvEncodeCell(''), '');
    });

    test('yazıcı çıktısı okuyucudan aynen geri okunur (gidiş-dönüş)', () {
      final rows = <List<String>>[
        <String>['Ad', 'Not', 'Sayı'],
        <String>['Çağlar; Öztürk', 'satır1\nsatır2', '1250,50'],
        <String>['"tırnaklı"', 'x', '3'],
      ];
      final decoded = decodeSpreadsheetText(csvBytes(rows));
      final t = parseCsvText(decoded.text);
      expect(_grid(t), rows);
    });
  });
}
