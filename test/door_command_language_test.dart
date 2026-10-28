// Kapı komutu dili (P1-15): komut kabul edilince kullanıcıya "kapı açıldı" DENMEZ.
//
// Sunucu 202 / 200 yalnız komutun kabul edildiğini söyler; cihaz yanıtı ya da fiziksel açılma kanıtı (sensör) yoktur
// (`openedAt` komut anının damgasıdır). Bu yüzden başarı metni "komut gönderildi"dir. Cihazdan gelen gerçek durum
// (ör. yönetici kartındaki `Kapı Durumu: Açık`) ve olay adları (geçiş kaydı, "Erişim geri açıldı") bu kuralın dışındadır.
//
// Bu dosya kaynağı tarar: ekran/sesli okuma/widget metinlerinden biri yeniden kanıtsız "açıldı" derse test kırılır.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Küçük harf + aksansız katlama (e2e `foldText` ile aynı fikir): "Kapı Açıldı!" -> "kapi acildi!".
String _fold(String s) {
  const from = 'İIıÇçĞğÖöŞşÜü';
  const to = 'iiiccggoossuu';
  final b = StringBuffer();
  for (final r in s.runes) {
    final ch = String.fromCharCode(r);
    final i = from.indexOf(ch);
    b.write(i >= 0 ? to[i] : ch.toLowerCase());
  }
  return b.toString();
}

/// Kapının açıldığını kanıtsız söyleyen ifadeler (katlanmış metinde).
final List<RegExp> _unproven = <RegExp>[
  RegExp(r'kapi(si|yi)?\s+acildi\b'),
  RegExp(r'\bacildi!'),
  RegExp(r'basariyla acildi\b'),
  RegExp(r'gecebilirsiniz'),
  RegExp(r'kapi\s+aciliyor!'),
];

bool _isComment(String line) {
  final t = line.trimLeft();
  return t.startsWith('//') || t.startsWith('*') || t.startsWith('/*');
}

List<File> _dartFiles(String dir) => Directory(dir)
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .where((f) => !f.path.replaceAll(r'\', '/').contains('/l10n/gen/'))
    .toList();

String _read(String path) => File(path).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  group('kapı komutu dili: kanıtsız "açıldı" yok (P1-15)', () {
    test('lib/ içinde kapının açıldığını iddia eden metin kalmadı', () {
      final files = _dartFiles('lib');
      expect(files.length, greaterThan(100), reason: 'tarama boş kalmasın');
      final offenders = <String>[];
      for (final file in files) {
        final path = file.path.replaceAll(r'\', '/');
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (_isComment(lines[i])) continue;
          final folded = _fold(lines[i]);
          if (_unproven.any((re) => re.hasMatch(folded))) {
            offenders.add('$path:${i + 1}: ${lines[i].trim()}');
          }
        }
      }
      expect(
        offenders,
        isEmpty,
        reason: 'Komut kabulü "açma komutu gönderildi" der; "açıldı" yalnız cihaz yanıtı/sensör kanıtıyla yazılır',
      );
    });

    test('kapı komutunu kabul eden her akış "gönderildi" diliyle konuşur', () {
      const expected = <String, String>{
        'lib/ui/widgets/resident_door_actions.dart': 'için açma komutu gönderildi.',
        'lib/ui/views/individual_home_view.dart': 'için açma komutu gönderildi.',
        'lib/ui/pages/home_page.dart': 'Kapı açma komutu gönderildi.',
        'lib/app.dart': 'için açma komutu gönderildi.',
        'lib/services/voice_door_service.dart': 'için açma komutu gönderildi.',
        'lib/ui/widgets/voice_control_modal.dart': 'Komut Gönderildi',
        'lib/ui/widgets/voice_live_banner.dart': 'Komut Gönderildi',
        'lib/ui/widgets/dynamic_qr_pass_modal.dart': 'Geçiş onaylandı, açma komutu gönderildi.',
        'lib/services/door_widget_service.dart': 'Komut gönderildi ✅',
      };
      for (final entry in expected.entries) {
        expect(_read(entry.key), contains(entry.value), reason: '${entry.key}: "${entry.value}" bekleniyor');
      }
    });

    test('yerel ağ yolu: cihazın doğrulanmış yanıtı "yanıt verdi" diye anılır, "açıldı" denmez', () {
      final src = _read('lib/services/local_door_service.dart');
      expect(src, contains('Komut yerel ağdan iletildi, cihaz yanıt verdi.'));
      expect(_fold(src), isNot(contains('aninda acildi')));
    });

    test('katlama yardımcısı beklenen ifadeleri yakalar (testin kendisi sağlam)', () {
      for (final bad in <String>[
        'Kapı Açıldı!',
        '✅ "Ana Kapı" kapısı açıldı!',
        'Açıldı! ✅',
        'Kapı açıldı, geçebilirsiniz.',
        'Ana Kapı başarıyla açıldı.',
        'KAPI AÇILDI',
      ]) {
        expect(_unproven.any((re) => re.hasMatch(_fold(bad))), isTrue, reason: bad);
      }
      for (final ok in <String>[
        'Kapı açma komutu gönderildi.',
        'Ana Kapı için açma komutu gönderildi.',
        'Komut gönderildi ✅',
        'Kapı açılmış olabilir; durumu kontrol edin.',
        'Erişim geri açıldı.',
        'Modül açıldı.',
      ]) {
        expect(_unproven.any((re) => re.hasMatch(_fold(ok))), isFalse, reason: ok);
      }
    });
  });
}
