// Yasal belge Markdown alt kümesi çözümleyicisi + işleyici widget (lib/ui/views/legal_markdown.dart).
//
// Birim: başlık / paragraf / liste / kalın / bağlantı; güvenlik (javascript:, http:, data:, kullanıcı bilgisi,
// HTML, görsel, bidi karakterleri) ve bozuk girdi. Widget: metin ölçeği 2,0'da taşma yok, bağlantı yalnız
// https açar, anlamsal etiketler.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/ui/views/legal_markdown.dart';

import 'design/harness.dart';

List<MdBlock> _parse(String source) => parseLegalMarkdown(source);

/// Düz metin döküm (biçimsiz): test okunabilirliği için.
String _plain(String source) => legalMarkdownPlainText(_parse(source));

List<MdLink> _links(List<MdBlock> blocks) {
  final out = <MdLink>[];
  void collect(List<MdSpan> spans) => out.addAll(spans.whereType<MdLink>());
  for (final block in blocks) {
    switch (block) {
      case MdHeading(:final spans):
      case MdParagraph(:final spans):
        collect(spans);
      case MdList(:final items):
        for (final item in items) {
          collect(item.spans);
        }
      case MdRule():
      case MdTruncated():
        break;
    }
  }
  return out;
}

void main() {
  group('Bloklar', () {
    test('başlıklar 1-3 düzeyi; 4+ düzey 3\'e iner; boşluksuz # başlık değildir', () {
      final blocks = _parse('# Bir\n\n## İki\n\n### Üç\n\n#### Dört\n\n#etiket');
      expect(blocks[0], isA<MdHeading>().having((h) => h.level, 'level', 1));
      expect(blocks[1], isA<MdHeading>().having((h) => h.level, 'level', 2));
      expect(blocks[2], isA<MdHeading>().having((h) => h.level, 'level', 3));
      expect(blocks[3], isA<MdHeading>().having((h) => h.level, 'level', 3));
      expect(blocks[4], isA<MdParagraph>());
      expect(_plain('#etiket'), '#etiket');
    });

    test('paragraf satırları boşlukla birleşir; boş satır yeni paragraf başlatır', () {
      final blocks = _parse('birinci satır\nikinci satır\n\nüçüncü');
      expect(blocks, hasLength(2));
      expect(_plain('birinci satır\nikinci satır'), 'birinci satır ikinci satır');
    });

    test('madde işaretli ve sıralı listeler; iç içelik derinliği; tembel devam', () {
      final blocks = _parse('- bir\n- iki\n  - iç\n    sürdü\n\n1. a\n2. b');
      final bullets = blocks[0] as MdList;
      expect(bullets.items.map((i) => i.spans.map((s) => s.text).join()).toList(), <String>[
        'bir',
        'iki',
        'iç sürdü',
      ]);
      expect(bullets.items.map((i) => i.depth).toList(), <int>[0, 0, 1]);
      expect(bullets.items.every((i) => i.number == null), isTrue);
      final ordered = blocks[1] as MdList;
      expect(ordered.items.map((i) => i.number).toList(), <int?>[1, 2]);
    });

    test('* ve + de madde işaretidir; kalın işaretçi (**) madde sanılmaz', () {
      expect(_parse('* a\n+ b').single, isA<MdList>());
      expect(_parse('**kalın** başlangıç').single, isA<MdParagraph>());
    });

    test('yatay çizgi', () {
      expect(_parse('a\n\n---\n\nb')[1], isA<MdRule>());
    });

    test('tablo yok: satır düz metin olarak kalır', () {
      final text = _plain('| a | b |\n|---|---|\n| 1 | 2 |');
      expect(text, contains('| a | b |'));
    });

    test('boş / yalnız boşluk girdi boş liste döner', () {
      expect(_parse(''), isEmpty);
      expect(_parse('   \n\n  '), isEmpty);
    });
  });

  group('Satır içi biçim', () {
    test('**kalın** ve __kalın__', () {
      final paragraph = _parse('a **kalın** ve __de kalın__ b').single as MdParagraph;
      expect(paragraph.spans.map((s) => (s.text, s.bold)).toList(), <(String, bool)>[
        ('a ', false),
        ('kalın', true),
        (' ve ', false),
        ('de kalın', true),
        (' b', false),
      ]);
    });

    test('kapanmayan ** ve boş ** düz metin kalır', () {
      expect(_plain('**açık kaldı'), '**açık kaldı');
      expect(_plain('**** boş'), '**** boş');
    });

    test('ters eğik çizgi kaçışı', () {
      expect(_plain(r'\*yıldız\* ve \[köşeli\]'), '*yıldız* ve [köşeli]');
    });
  });

  group('Bağlantı güvenliği', () {
    test('https bağlantı çözülür (başlıklı biçim dahil); metin ve adres ayrıdır', () {
      final links = _links(_parse('bkz. [Gizlilik](https://example.com/gizlilik) ve '
          '[KVKK](https://example.com/kvkk "Başlık").'));
      expect(links.map((l) => l.text).toList(), <String>['Gizlilik', 'KVKK']);
      expect(links[0].uri.toString(), 'https://example.com/gizlilik');
      expect(links[1].uri.host, 'example.com');
    });

    test('https dışındaki ve tehlikeli adresler bağlantı OLMAZ, metin kalır', () {
      const bad = <String>[
        'javascript:alert(1)',
        'JavaScript:alert(1)',
        'http://example.com',
        'data:text/html;base64,PHNjcmlwdD4=',
        'mailto:a@b.com',
        'tel:+905551112233',
        'ftp://example.com/x',
        '//evil.example.com/x',
        '/gizlilik',
        'gizlilik.html',
        'https://user:pass@example.com/',
        'https://exa mple.com/',
        'https:///yol-yok',
        'https://',
        'file:///etc/passwd',
        'vbscript:msgbox(1)',
      ];
      for (final url in bad) {
        final blocks = _parse('[tıkla]($url)');
        expect(_links(blocks), isEmpty, reason: url);
        expect(_plain('[tıkla]($url)'), 'tıkla', reason: url);
      }
    });

    test('görsel sözdizimi bağlantı üretmez (yalnız alt metin)', () {
      final blocks = _parse('![resim](https://example.com/a.png)');
      expect(_links(blocks), isEmpty);
      expect(_plain('![resim](https://example.com/a.png)'), 'resim');
    });

    test('etiket içindeki kalın korunur, iç içe bağlantı yok', () {
      final links = _links(_parse('[**önemli** metin](https://example.com)'));
      expect(links.single.text, 'önemli metin');
      final nested = _links(_parse('[dış [iç](https://a.example)](https://b.example)'));
      expect(nested.length, lessThanOrEqualTo(1));
    });

    test('adres ASCII dışı / kontrol karakteri içerirse bağlantı olmaz', () {
      final nbsp = String.fromCharCode(0xA0);
      expect(_links(_parse('[x](https://example.com/a${nbsp}b)')), isEmpty);
      final cyr = String.fromCharCode(0x0430);
      expect(_links(_parse('[x](https://ex${cyr}mple.com)')), isEmpty);
    });
  });

  group('Bozuk / düşmanca girdi', () {
    test('HTML ve betik düz metin olarak kalır', () {
      const html = '<script>alert(1)</script> <img src=x onerror=alert(1)> <a href="javascript:x">k</a>';
      final blocks = _parse(html);
      expect(_links(blocks), isEmpty);
      expect(_plain(html), contains('<script>alert(1)</script>'));
    });

    test('denetim ve çift yönlü (bidi) karakterler temizlenir', () {
      final rlo = String.fromCharCode(0x202E);
      final lri = String.fromCharCode(0x2066);
      final bom = String.fromCharCode(0xFEFF);
      final nul = String.fromCharCode(0);
      final text = _plain('${bom}a${rlo}b${lri}c${nul}d');
      expect(text, 'abcd');
    });

    test('LRM / RLM / ALM ve sıfır genişlikli karakterler de temizlenir', () {
      const stripped = <int>[
        0x061C, 0x200B, 0x200C, 0x200D, 0x200E, 0x200F, 0x2060, 0x202A, 0x202B, 0x202C,
        0x202D, 0x202E, 0x2066, 0x2067, 0x2068, 0x2069, 0xFEFF, 0x7F, 0x01, 0x0B, 0x0C,
      ];
      final noise = String.fromCharCodes(stripped);
      expect(_plain('Gi${noise}zlilik ${noise}Politikası'), 'Gizlilik Politikası');
      final zwsp = String.fromCharCode(0x200B);
      final lrm = String.fromCharCode(0x200E);
      expect(_plain('# ${zwsp}Başlık'), 'Başlık');
      final link = _links(_parse('[et${lrm}iket](https://example.com)'));
      expect(link.single.text, 'etiket');
      // Türkçe karakterler ve normal boşluk korunur.
      expect(_plain('çğıöşü ÇĞİÖŞÜ'), 'çğıöşü ÇĞİÖŞÜ');
    });

    test('CRLF ve tek CR satır sonları', () {
      expect(_parse('a\r\n\r\nb\rc').length, 2);
    });

    test('kapanmayan köşeli parantez / parantez yığını hızlı ve hatasız', () {
      final watch = Stopwatch()..start();
      final blocks = _parse('[' * 60000);
      expect(blocks, isNotEmpty);
      final blocks2 = _parse('[a](' * 20000);
      expect(blocks2, isNotEmpty);
      final blocks3 = _parse('**' * 30000);
      expect(blocks3, isNotEmpty);
      expect(watch.elapsed, lessThan(const Duration(seconds: 20)));
    });

    test('çok büyük girdi kesilir, çok satırlı belge hata vermez', () {
      final big = List<String>.filled(3000, '- madde **kalın** [b](https://example.com)').join('\n');
      expect(() => _parse(big), returnsNormally);
      // Tek satır üst sınırı: kesilir (içerik sessizce sonsuza uzamaz).
      final oneLine = 'a' * (kLegalMarkdownMaxLength + 5000);
      expect(_plain(oneLine).length, kLegalMarkdownMaxLineLength);
      expect(_parse(oneLine).last, isA<MdTruncated>(), reason: 'kesilen belgede uyarı bloğu var');
      // Toplam kaynak sınırı: çok satırlı belge kaynak sınırında kesilir.
      final manyLines = List<String>.filled(720, 'b' * 999).join('\n\n');
      expect(_plain(manyLines).replaceAll('\n', '').length, lessThanOrEqualTo(kLegalMarkdownMaxLength));
      expect(_parse(manyLines).last, isA<MdTruncated>());
    });

    test('rastgele karışık işaretler asla istisna fırlatmaz', () {
      const pieces = <String>['[', ']', '(', ')', '**', '__', '#', '- ', '1. ', '\\', '!', '\n', ' ', 'a', '|', '"'];
      var seed = 7;
      int next() {
        seed = (seed * 1103515245 + 12345) & 0x7fffffff;
        return seed;
      }

      for (var round = 0; round < 300; round++) {
        final buffer = StringBuffer();
        for (var i = 0; i < 80; i++) {
          buffer.write(pieces[next() % pieces.length]);
        }
        expect(() => _parse(buffer.toString()), returnsNormally, reason: buffer.toString());
      }
    });
  });

  group('Sert satır sonu ve boş satır (R8 B4 / B8)', () {
    test('sondaki iki boşluk SERT satır sonudur: "a  \nb" -> "a\nb"', () {
      final paragraph = _parse('a  \nb').single as MdParagraph;
      expect(paragraph.spans.map((s) => s.text).join(), 'a\nb');
      expect(_plain('ilk  \nikinci  \nüçüncü'), 'ilk\nikinci\nüçüncü');
      expect(_plain('a   \nb'), 'a\nb', reason: 'üç boşluk da sert satır sonu');
    });

    test('sondaki ters eğik çizgi SERT satır sonudur ve işaret metinde kalmaz', () {
      expect(_plain('a\\\nb'), 'a\nb');
    });

    test('tek boşluk ya da hiç boşluk: yumuşak satır sonu (boşluk)', () {
      expect(_plain('a \nb'), 'a b');
      expect(_plain('a\nb'), 'a b');
    });

    test('paragrafın son satırındaki iki boşluk satır sonu üretmez', () {
      expect(_plain('a\nb  '), 'a b');
    });

    test('sert satır sonu başlık / liste devamıyla karışmaz', () {
      final blocks = _parse('# Başlık  \n\n- madde  \n  devam');
      expect(blocks[0], isA<MdHeading>());
      expect((blocks[1] as MdList).items.single.spans.map((s) => s.text).join(), 'madde devam');
    });

    test('yalnız NBSP / ideografik boşluk / dar NBSP içeren satır paragrafı ayırır', () {
      for (final code in const <int>[0x00A0, 0x3000, 0x202F, 0x2003, 0x205F]) {
        final blank = String.fromCharCode(code);
        final blocks = _parse('birinci\n$blank\nikinci');
        expect(blocks, hasLength(2), reason: 'U+${code.toRadixString(16)}');
        expect(_plain('birinci\n $blank \t$blank\nikinci'), 'birinci\nikinci');
      }
      // Madde listesi de boş (Unicode) satırla kapanır.
      final nbsp = String.fromCharCode(0x00A0);
      expect(_parse('- a\n$nbsp\nparagraf').map((b) => b.runtimeType).toList(), <Type>[MdList, MdParagraph]);
    });

    test('U+2028 / U+2029 SİLİNMEZ, boşluğa çevrilir: kelimeler yapışmaz', () {
      final ls = String.fromCharCode(0x2028);
      final ps = String.fromCharCode(0x2029);
      expect(_plain('kelime1${ls}kelime2'), 'kelime1 kelime2');
      expect(_plain('kelime1${ps}kelime2'), 'kelime1 kelime2');
      expect(_plain('# Baş${ls}lık'), 'Baş lık');
      // Bağlantı adresinde boşluk olur: bağlantı sayılmaz.
      expect(_links(_parse('[x](https://example.com/a${ls}b)')), isEmpty);
      // Silinen karakterler yine silinir (yan yana ZWSP kelimeyi bölmez).
      final zwsp = String.fromCharCode(0x200B);
      expect(_plain('kelime1${zwsp}kelime2'), 'kelime1kelime2');
    });
  });

  group('Kesme uyarısı (R8 P3): sınır aşılınca sessiz kesme yok', () {
    List<MdBlock> parseLong(String s) => parseLegalMarkdown(s);

    test('sınır değerleri', () {
      expect(kLegalMarkdownMaxLength, greaterThanOrEqualTo(600000), reason: 'sunucu dosya sınırı 512 KiB');
      expect(kLegalMarkdownMaxLength, greaterThan(512 * 1024));
    });

    test('normal belge ve sınır içi büyük belge: uyarı bloğu YOK', () {
      expect(_parse('# Başlık\n\nmetin').any((b) => b is MdTruncated), isFalse);
      // 512 KiB'lik (sunucu sınırında) belge kesilmez.
      final line = 'Bu bir hukuki metin satırıdır ve noktalama içerir. ' * 4;
      final doc = List<String>.filled(512 * 1024 ~/ (line.length + 2), line).join('\n\n');
      expect(doc.length, lessThanOrEqualTo(512 * 1024));
      expect(parseLong(doc).any((b) => b is MdTruncated), isFalse);
      // Sınırdan sonra yalnız boş satır kalırsa kesme sayılmaz.
      expect(parseLong('metin${'\n' * (kLegalMarkdownMaxLines + 10)}').any((b) => b is MdTruncated), isFalse);
    });

    test('kaynak uzunluğu aşılınca: ilk içerik korunur, son blok uyarı', () {
      final blocks = parseLong('# İlk Başlık\n\n${'x' * (kLegalMarkdownMaxLength + 1)}');
      expect(blocks.first, isA<MdHeading>());
      expect(blocks.last, isA<MdTruncated>());
      expect(blocks.whereType<MdTruncated>(), hasLength(1));
    });

    test('blok sayısı aşılınca', () {
      final doc = List<String>.generate(kLegalMarkdownMaxBlocks + 100, (i) => 'p$i').join('\n\n');
      final blocks = parseLong(doc);
      expect(blocks.last, isA<MdTruncated>());
      expect(blocks.length, kLegalMarkdownMaxBlocks + 1);
    });

    test('satır sayısı aşılınca (kalan satırlarda görünür metin var)', () {
      final blocks = parseLong('${'\n' * (kLegalMarkdownMaxLines + 10)}kalan metin');
      expect(blocks.last, isA<MdTruncated>());
    });

    test('madde sayısı aşılınca', () {
      final doc = List<String>.filled(kLegalMarkdownMaxListItems + 5, '- a').join('\n');
      final blocks = parseLong(doc);
      expect(blocks.last, isA<MdTruncated>());
      expect((blocks.first as MdList).items.length, kLegalMarkdownMaxListItems);
    });

    test('tek satır sınırı aşılınca', () {
      expect(parseLong('x' * (kLegalMarkdownMaxLineLength + 1)).last, isA<MdTruncated>());
      expect(parseLong('x' * kLegalMarkdownMaxLineLength).any((b) => b is MdTruncated), isFalse);
    });

    testWidgets('widget: uyarı + "Web sayfasını aç" (yalnız https adres verilirse); dokununca adres açılır', (t) async {
      final opened = <Uri>[];
      await pumpAt(
        t,
        LegalMarkdown(
          source: 'Kısa metin\n\n${'y' * (kLegalMarkdownMaxLength + 10)}',
          fullTextUri: Uri.parse('https://api.example.test/legal/privacy'),
          onOpenLink: (uri) async {
            opened.add(uri);
            return true;
          },
        ),
        width: 400,
        height: 800,
        scale: 1.0,
      );
      expect(find.text(kLegalMarkdownTruncatedMessage), findsOneWidget);
      expect(find.text('Web sayfasını aç'), findsOneWidget);
      // Uyarı çok uzun paragrafın ALTINDADIR: önce görünür kılınır.
      await t.ensureVisible(find.text('Web sayfasını aç'));
      await t.pump();
      await t.tap(find.text('Web sayfasını aç'));
      await t.pump();
      expect(opened.map((u) => u.toString()), <String>['https://api.example.test/legal/privacy']);
    });

    testWidgets('widget: adres yok ya da http ise düğme yok, uyarı yine var; kesilmeyen belgede uyarı yok', (t) async {
      final longSource = 'z' * (kLegalMarkdownMaxLength + 10);
      for (final uri in <Uri?>[null, Uri.parse('http://insecure.example.test/legal/privacy')]) {
        await pumpAt(t, LegalMarkdown(source: longSource, fullTextUri: uri), width: 400, height: 800, scale: 1.0);
        expect(find.text(kLegalMarkdownTruncatedMessage), findsOneWidget);
        expect(find.text('Web sayfasını aç'), findsNothing);
      }
      await pumpAt(
        t,
        LegalMarkdown(source: '# Normal', fullTextUri: Uri.parse('https://api.example.test/legal/x')),
        width: 400,
        height: 800,
        scale: 1.0,
      );
      expect(find.text(kLegalMarkdownTruncatedMessage), findsNothing);
    });

    testWidgets('uyarı büyük yazıda taşmaz (320 x 2,0 ve yatay 640x360 x2,0)', (t) async {
      final longSource = 'q' * (kLegalMarkdownMaxLength + 10);
      for (final (w, h) in const <(double, double)>[(320, 640), (640, 360)]) {
        await pumpAt(
          t,
          LegalMarkdown(source: longSource, fullTextUri: Uri.parse('https://api.example.test/legal/privacy')),
          width: w,
          height: h,
          scale: 2.0,
        );
        expect(t.takeException(), isNull);
      }
    });
  });

  group('Doğrusal çözümleme: kötü niyetli girdi < 2 sn', () {
    // Eski ikinci dereceden çözümleyici bu girdilerde 4-30 sn sürüyordu; 2 sn sınırı onu hâlâ yakalar,
    // ama yoğun makinede (paralel test/derleme) 200 ms'lik sıkı sınır yalancı kırmızı üretiyordu.
    void expectFast(String name, String source, {int maxMs = 2000}) {
      final watch = Stopwatch()..start();
      final blocks = parseLegalMarkdown(source);
      watch.stop();
      expect(blocks, isNotNull);
      expect(watch.elapsedMilliseconds, lessThan(maxMs), reason: '$name: ${watch.elapsedMilliseconds} ms');
    }

    final spaces = ' ' * 32000;

    test('32.000 boşluklu başlık satırları (başlık / kapanış # / boş başlık)', () {
      expectFast('başlık+boşluk', '# ${spaces}x');
      expectFast('yalnız boşluk', '# $spaces');
      expectFast('kapanış #', '# başlık $spaces${'#' * 5000}');
      expectFast('çok # ', '#${'#' * 30000} x');
      expectFast('girintili', '   ## $spaces yazı ## $spaces');
      expectFast('çok başlık', List<String>.filled(2000, '#  $spaces').join('\n'));
    });

    test('50.000 tembel devam satırı', () {
      expectFast('madde + devam', '- a\n${List<String>.filled(50000, 'devam').join('\n')}');
      expectFast('sıralı + devam', '1. a\n${List<String>.filled(50000, 'devam metni').join('\n')}');
      final blocks = parseLegalMarkdown('- a\n${List<String>.filled(1000, 'devam').join('\n')}');
      // Devam satırı üst sınırı aşılınca içerik KAYBOLMAZ: kalan satırlar yeni paragraf olur.
      expect(legalMarkdownPlainText(blocks).split(' ').where((w) => w.contains('devam')).length, greaterThanOrEqualTo(1));
      expect(legalMarkdownPlainText(blocks).split(RegExp(r'\s+')).where((w) => w == 'devam').length, 1000);
    });

    test('50.000 paragraf satırı, boş satır, madde', () {
      expectFast('paragraf', List<String>.filled(50000, 'metin satırı').join('\n'));
      expectFast('boş satırlar', '\n' * 100000);
      expectFast('maddeler', List<String>.filled(50000, '- madde **kalın**').join('\n'));
      expectFast('sıralı maddeler', List<String>.filled(50000, '1. madde').join('\n'));
      expectFast('girintili yığın', List<String>.generate(20000, (i) => '${' ' * (i % 40)}- m').join('\n'));
    });

    test('yatay çizgi örüntüleri', () {
      expectFast('- - - ...', '- ' * 15000);
      expectFast('tire boşluk tire', '-${' ' * 32000}-');
      expectFast('çok çizgi', List<String>.filled(30000, '---').join('\n'));
      expectFast('çizgi + yabancı karakter', '${'- ' * 15000}x');
    });

    test('satır içi: kapanmayan işaretler ve bağlantı yığınları', () {
      expectFast('[', '[' * 100000);
      expectFast('[a](', '[a](' * 25000);
      expectFast('![', '![' * 50000);
      expectFast('**', '**' * 100000);
      expectFast('__', '__' * 100000);
      expectFast('ters eğik çizgi', r'\' * 100000);
      expectFast('bitişik geçersiz bağlantılar', '[x](javascript:a)' * 15000);
      expectFast('bitişik geçerli bağlantılar', '[x](https://example.com) ' * 8000);
      expectFast('iç içe', '${'[' * 300}x${']' * 300}(https://a.example)');
      expectFast('kalın + bağlantı', '**[a](https://example.com)** ' * 8000);
    });

    test('girintisi çok uzun / yalnız boşluk satırı', () {
      expectFast('32k girinti + metin', '${' ' * 32000}a');
      expectFast('32k boşluk + sekme', '${' ' * 16000}\t${' ' * 16000}a');
      expectFast('32k boşluk + madde işareti', '${' ' * 32000}- a');
      expectFast('32k boşluk + sıra', '${' ' * 32000}1. a');
    });

    test('hızlandırma çıktıyı bozmaz: aynı girdilerde beklenen bloklar', () {
      final blocks = _parse('# Başlık ##\n\n   ### Üç   \n\n- - -\n\n1) bir\n2) iki');
      expect(blocks[0], isA<MdHeading>().having((h) => (h.spans.single as MdText).text, 'text', 'Başlık'));
      expect(blocks[1], isA<MdHeading>().having((h) => h.level, 'level', 3));
      expect(blocks[2], isA<MdRule>());
      expect((blocks[3] as MdList).items.map((i) => i.number).toList(), <int?>[1, 2]);
      // Girinti 4+: başlık değil (düz metin).
      expect(_parse('    # değil').single, isA<MdParagraph>());
      // Başlıkta metin yoksa blok üretilmez.
      expect(_parse('#   '), isEmpty);
    });
  });

  group('Widget', () {
    const doc = '# Başlık\n\nParagraf **kalın** ve [bağlantı](https://example.com/x).\n\n'
        '- madde bir\n- madde iki\n\n1. sıralı\n\n[tehlikeli](javascript:alert(1))';

    testWidgets('metinler görünür; taşma yok (320 x 2,0 açık / koyu)', (t) async {
      for (final dark in const <bool>[false, true]) {
        await pumpAt(
          t,
          const LegalMarkdown(source: doc),
          width: 320,
          height: 640,
          scale: 2.0,
          dark: dark,
        );
        expect(find.textContaining('Başlık', findRichText: true), findsOneWidget);
        expect(find.textContaining('madde bir', findRichText: true), findsOneWidget);
        expect(find.textContaining('sıralı', findRichText: true), findsOneWidget);
        expect(find.textContaining('tehlikeli', findRichText: true), findsOneWidget);
        expect(t.takeException(), isNull);
      }
    });

    testWidgets('bağlantıya dokunmak yalnız https adresi açar; tehlikeli olan açılamaz', (t) async {
      final opened = <Uri>[];
      await pumpAt(
        t,
        LegalMarkdown(
          source: doc,
          onOpenLink: (uri) async {
            opened.add(uri);
            return true;
          },
        ),
        width: 400,
        height: 800,
        scale: 1.0,
      );
      // Bağlantı kapsayan paragrafı bul ve bağlantı aralığına dokun.
      final richFinder = find.byWidgetPredicate(
        (w) => w is RichText && w.text.toPlainText().contains('bağlantı'),
      );
      expect(richFinder, findsOneWidget);
      final rich = t.widget<RichText>(richFinder);
      final plain = rich.text.toPlainText();
      final start = plain.indexOf('bağlantı');
      final renderParagraph = t.renderObject<RenderParagraph>(richFinder);
      final boxes = renderParagraph.getBoxesForSelection(
        TextSelection(baseOffset: start, extentOffset: start + 'bağlantı'.length),
      );
      final origin = renderParagraph.localToGlobal(boxes.first.toRect().center);
      await t.tapAt(origin);
      await t.pump();
      expect(opened.map((u) => u.toString()), <String>['https://example.com/x']);

      // "tehlikeli" metni bağlantı değildir: dokunmak hiçbir şey açmaz.
      final dangerous = find.byWidgetPredicate(
        (w) => w is RichText && w.text.toPlainText().contains('tehlikeli'),
      );
      await t.tap(dangerous, warnIfMissed: false);
      await t.pump();
      expect(opened, hasLength(1));
    });

    testWidgets('açılamayan bağlantıda bilgi çubuğu (ana makine adıyla)', (t) async {
      await pumpAt(
        t,
        LegalMarkdown(source: 'bkz [adres](https://example.com/x)', onOpenLink: (_) async => false),
        width: 400,
        height: 600,
        scale: 1.0,
      );
      final richFinder = find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText().contains('adres'));
      final rp = t.renderObject<RenderParagraph>(richFinder);
      final start = rp.text.toPlainText().indexOf('adres');
      final boxes = rp.getBoxesForSelection(TextSelection(baseOffset: start, extentOffset: start + 5));
      await t.tapAt(rp.localToGlobal(boxes.first.toRect().center));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Bağlantı açılamadı: example.com'), findsOneWidget);
    });

    testWidgets('başlıklar ekran okuyucuda başlık, bağlantılar "bağlantı, ana makine" etiketli', (t) async {
      final semantics = t.ensureSemantics();
      try {
        await pumpAt(t, const LegalMarkdown(source: doc), width: 400, height: 800, scale: 1.0);
        final header = t.getSemantics(find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText() == 'Başlık'));
        expect(header.flagsCollection.isHeader, isTrue);
        final linkNodes = <SemanticsNode>[];
        void walk(SemanticsNode node) {
          if (node.flagsCollection.isLink) linkNodes.add(node);
          node.visitChildren((child) {
            walk(child);
            return true;
          });
        }

        walk(t.binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!);
        expect(linkNodes, hasLength(1), reason: 'yalnız https bağlantısı bağlantı düğümüdür');
        expect(linkNodes.single.label, contains('example.com'));
        expect(linkNodes.single.label, contains('bağlantı'));
      } finally {
        semantics.dispose();
      }
    });

    testWidgets('kaynak değişince yeniden çözülür; atılırken hata yok', (t) async {
      final source = ValueNotifier<String>('# Bir');
      addTearDown(source.dispose);
      await pumpAt(
        t,
        ValueListenableBuilder<String>(
          valueListenable: source,
          builder: (context, value, _) => LegalMarkdown(source: value),
        ),
        width: 400,
        height: 400,
        scale: 1.0,
      );
      expect(find.textContaining('Bir', findRichText: true), findsOneWidget);
      source.value = '# İki\n\n[x](https://example.com)';
      await t.pump();
      expect(find.textContaining('İki', findRichText: true), findsOneWidget);
      expect(find.textContaining('Bir', findRichText: true), findsNothing);
      await t.pumpWidget(const SizedBox.shrink());
      expect(t.takeException(), isNull);
    });
  });
}
