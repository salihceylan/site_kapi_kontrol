// Yardım içeriği (lib/ui/views/help_content.dart) ve ilk kullanım turu metinleri: UYDURMA YOK.
//
// Metinlerde “çift tırnak” içinde geçen her arayüz adı (menü başlığı, düğme, bölüm, sekme) uygulama
// kaynağında gerçekten bulunmalıdır; her rolün konu listesi ve tur içeriği eksiksizdir.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/ui/views/help_content.dart';
import 'package:site_kapi_kontrol/ui/views/onboarding_tour.dart';
import 'package:site_kapi_kontrol/ui/widgets/yan_menu.dart';

String _libSource() {
  final buffer = StringBuffer();
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is File && entity.path.endsWith('.dart')) {
      buffer.writeln(entity.readAsStringSync());
    }
  }
  return buffer.toString();
}

Iterable<String> _quoted(String text) => RegExp('“([^”]+)”').allMatches(text).map((m) => m.group(1)!);

List<String> _allHelpTexts() {
  final texts = <String>[];
  for (final audience in HelpAudience.values) {
    for (final topic in HelpContent.howToFor(audience)) {
      texts
        ..add(topic.title)
        ..addAll(topic.steps);
      if (topic.note != null) texts.add(topic.note!);
    }
  }
  for (final faq in HelpContent.faqs) {
    texts
      ..add(faq.question)
      ..add(faq.answer);
  }
  texts.add(HelpContent.accountAndDataText);
  return texts;
}

List<String> _allTourTexts() {
  final texts = <String>[];
  for (final audience in HelpAudience.values) {
    for (final step in OnboardingSteps.forAudience(audience)) {
      texts
        ..add(step.title)
        ..add(step.body);
    }
  }
  return texts;
}

void main() {
  final source = _libSource();

  group('Yardım içeriği', () {
    test('rol -> yardım grubu eşlemesi (sakin modundaki yönetici sakin yardımı alır)', () {
      expect(HelpContent.audienceFor(UserRole.superUser), HelpAudience.superUser);
      expect(HelpContent.audienceFor(UserRole.siteManager), HelpAudience.siteManager);
      expect(HelpContent.audienceFor(UserRole.siteManager, residentMode: true), HelpAudience.resident);
      expect(HelpContent.audienceFor(UserRole.apartmentOwner), HelpAudience.resident);
      expect(HelpContent.audienceFor(UserRole.individual), HelpAudience.individual);
      expect(HelpContent.audienceFor(UserRole.superUser, residentMode: true), HelpAudience.superUser);
    });

    test('her grubun konuları dolu; kimlikler grup içinde tekil; adım ve başlık boş değil', () {
      for (final audience in HelpAudience.values) {
        final topics = HelpContent.howToFor(audience);
        expect(topics.length, greaterThanOrEqualTo(3), reason: '$audience');
        expect(topics.map((t) => t.id).toSet().length, topics.length, reason: '$audience: yinelenen kimlik');
        for (final topic in topics) {
          expect(topic.title.trim(), isNotEmpty);
          expect(topic.steps, isNotEmpty, reason: topic.id);
          expect(topic.steps.every((s) => s.trim().isNotEmpty), isTrue, reason: topic.id);
        }
      }
    });

    test('role özgü konular doğru gruplarda', () {
      List<String> ids(HelpAudience a) => HelpContent.howToFor(a).map((t) => t.id).toList();
      expect(ids(HelpAudience.resident), containsAll(<String>['open_door', 'join_apartment', 'announcements']));
      expect(ids(HelpAudience.resident), isNot(contains('profile')), reason: 'sakin profili salt okunur');
      expect(ids(HelpAudience.resident), contains('profile_resident'));
      expect(ids(HelpAudience.individual), containsAll(<String>['add_device', 'site_application', 'join_apartment']));
      expect(ids(HelpAudience.individual), isNot(contains('open_door')));
      expect(ids(HelpAudience.siteManager), containsAll(<String>['manage_site', 'people', 'announce', 'modules']));
      expect(ids(HelpAudience.superUser), containsAll(<String>['users', 'applications', 'device_inventory']));
      for (final audience in HelpAudience.values) {
        expect(ids(audience), contains('panel'), reason: '$audience: Panel (modül vitrini) anlatılmalı');
      }
    });

    group('Panel = modül vitrini; kapı "Kapılar" ekranında', () {
      HelpTopic topic(HelpAudience a, String id) => HelpContent.howToFor(a).firstWhere((t) => t.id == id);
      String joined(HelpTopic t) => <String>[t.title, ...t.steps, if (t.note != null) t.note!].join('\n');

      test('"Kapılar" gerçek menü başlığıdır ve bilinen adlardadır', () {
        expect(YanMenu.titleFor(SirketMenuItem.kapilar), 'Kapılar');
        expect(HelpContent.knownMenuTitles, contains(YanMenu.titleFor(SirketMenuItem.kapilar)));
        expect(HelpContent.knownMenuTitles, contains(YanMenu.titleFor(SirketMenuItem.dashboard)));
      });

      test('"Kapıyı nasıl açarım?": ilk adım Panel\'deki "Kapılar" kartına götürür; not "Kapılar" yokluğunu anlatır', () {
        final door = topic(HelpAudience.resident, 'open_door');
        expect(door.steps.first, contains('“Kapılar”'));
        expect(door.steps.first, contains('“Panel”'));
        expect(door.steps.any((s) => s.contains('“KAPIYI AÇ”')), isTrue);
        expect(door.note, contains('“Kapılar”'));
        expect(door.note, isNot(contains('Panelde kapı kartı')));
      });

      test('her grubun "panel" konusu vitrini anlatır ve kapıyı "Kapılar"a bağlar', () {
        for (final audience in HelpAudience.values) {
          final panel = topic(audience, 'panel');
          expect(panel.steps.first, contains('“Panel”'), reason: '$audience');
          expect(panel.steps.first, contains('vitrin'), reason: '$audience');
          expect(joined(panel), contains('“Kapılar”'), reason: '$audience');
        }
      });

      test('daireye katılma: onaydan sonra kapılar "Kapılar" ekranında görünür', () {
        for (final audience in <HelpAudience>[HelpAudience.resident, HelpAudience.individual]) {
          final join = topic(audience, 'join_apartment');
          expect(join.steps.any((s) => s.contains('kapılarınız “Kapılar” ekranında görünür')), isTrue, reason: '$audience');
        }
      });

      test('sakin turu: ilk adım vitrini ve "Kapılar" kartındaki "KAPIYI AÇ" düğmesini anlatır', () {
        final first = OnboardingSteps.forAudience(HelpAudience.resident).first;
        expect(first.title, 'Kapınız cebinizde');
        expect(first.body, contains('“Panel”'));
        expect(first.body, contains('vitrin'));
        expect(first.body, contains('“Kapılar”'));
        expect(first.body, contains('“KAPIYI AÇ”'));
      });

      test('her rolün turu "Panel" ekranını anlatır', () {
        for (final audience in HelpAudience.values) {
          final tour = OnboardingSteps.forAudience(audience).map((s) => s.body).join('\n');
          expect(tour, contains('“Panel”'), reason: '$audience');
        }
      });

      test('kapı düğmesini anlatan her konu / tur adımı "Kapılar"ı da anar; eski "Panel = kapı" cümleleri yok', () {
        final groups = <String, String>{
          for (final audience in HelpAudience.values)
            for (final t in HelpContent.howToFor(audience)) '$audience/${t.id}': joined(t),
          for (final audience in HelpAudience.values)
            for (final (i, s) in OnboardingSteps.forAudience(audience).indexed) '$audience/tur$i': '${s.title}\n${s.body}',
          for (final (i, faq) in HelpContent.faqs.indexed) 'sss$i': '${faq.question}\n${faq.answer}',
        };
        groups.forEach((where, text) {
          if (text.contains('KAPIYI AÇ')) {
            expect(text, contains('“Kapılar”'), reason: '$where: kapı düğmesi "Kapılar" ekranında anlatılmalı');
          }
          for (final stale in const <String>[
            'Panelde kapı',
            'Panel ekranında kapı',
            '“Panel” ekranında kapı',
            'kapılarınız “Panel”',
            'Menüden “Panel” ekranını açın',
            'Menüdeki “Panel” ekranında',
          ]) {
            expect(text, isNot(contains(stale)), reason: '$where: "$stale" (Panel artık modül vitrinidir)');
          }
        });
      });
    });

    // İP-1D (G2 + G3): yardım ve tur yeni gezinmeyi anlatır; ayar ekranları "Menüden" değil, "Ayarlar" düğmesinden açılır.
    group('yeni gezinme: başlıklı menü, "Ayarlar" (dişli), sakin alt çubuğu, site seçici', () {
      HelpTopic topic(HelpAudience a, String id) => HelpContent.howToFor(a).firstWhere((t) => t.id == id);
      String joined(HelpTopic t) => <String>[t.title, ...t.steps, if (t.note != null) t.note!].join('\n');

      test('her grubun "navigation" konusu menü başlıklarını ve "Ayarlar" düğmesini anlatır', () {
        for (final audience in HelpAudience.values) {
          final text = joined(topic(audience, 'navigation'));
          expect(text, contains('“Ana sayfa”'), reason: '$audience');
          expect(text, contains('“Ayarlar”'), reason: '$audience');
          expect(text, contains('dişli'), reason: '$audience');
        }
      });

      test('sakin: alt çubuğun beş sekmesi, Kapı koşulu ve geri tuşu anlatılır; tur da alt çubuğu anar', () {
        final text = joined(topic(HelpAudience.resident, 'navigation'));
        for (final tab in const <String>['“Özet”', '“Duyuru”', '“Arıza”', '“Kapı”', '“Dosyalar”']) {
          expect(text, contains(tab));
        }
        expect(text, contains('kapı yetkiniz yoksa'));
        // Çubuğun HİÇ görünmediği iki durum (residentTabsFor < 2 sekme, HomePage.residentBarMinHeight) de anlatılır:
        // yalnız görevli bağı olan hesap ve yatay telefon "çubuk nerede?" diye aramasın.
        expect(text, contains('İkiden az sekme'));
        expect(text, contains('yatay'));
        expect(text, contains('Geri tuşu'));
        final tour = OnboardingSteps.forAudience(HelpAudience.resident).map((s) => s.body).join('\n');
        expect(tour, contains('“Özet”'));
        expect(tour, contains('“Kapı”'));
      });

      test('yönetici: site seçici anlatılır; ayar ekranları "Ayarlar" düğmesinden', () {
        final text = joined(topic(HelpAudience.siteManager, 'navigation'));
        expect(text, contains('site satırına'));
        expect(text, contains('“Tüm siteler”'));
        expect(joined(topic(HelpAudience.siteManager, 'modules')), contains('“Ayarlar” düğmesinden “Modüller”'));
      });

      test('bugün öğesi olmayan başlıklar ("Tahsilat", "Giderler", "Raporlar") ekranları varmış gibi anlatılmaz', () {
        // Hiçbir menü öğesinin eşlenmediği çekmece başlığı bugün hiç çizilmez: yardım onu "ekranların toplandığı başlık"
        // diye sayarsa yönetici menüde arar, bulamaz. Anılıyorsa boş olduğu da yazmalıdır.
        final empty = <SirketMenuGroup>[
          for (final group in SirketMenuGroup.drawerGroups)
            if (!SirketMenuItem.values.any((item) => menuGroupOf(item) == group)) group,
        ];
        for (final audience in HelpAudience.values) {
          final text = joined(topic(audience, 'navigation'));
          for (final group in empty) {
            if (!text.contains('“${group.title}”')) continue;
            expect(text, contains('henüz ekran yok'), reason: '$audience: “${group.title}” başlığı bugün görünmez');
          }
        }
      });

      test('ayar ekranları (Profilim, Modüller) için eski "Menüden ... açın" adımı kalmadı', () {
        for (final audience in HelpAudience.values) {
          for (final t in HelpContent.howToFor(audience)) {
            for (final stale in const <String>['Menüden “Profilim”', 'Menüden “Modüller”']) {
              expect(joined(t), isNot(contains(stale)), reason: '$audience/${t.id}');
            }
          }
        }
      });
    });

    test('metinlerdeki “tırnaklı” arayüz adlarının hepsi bilinen menü / etiket listesinde', () {
      final known = <String>{...HelpContent.knownMenuTitles, ...HelpContent.knownScreenLabels};
      final unknown = <String>{
        for (final text in <String>[..._allHelpTexts(), ..._allTourTexts()])
          for (final name in _quoted(text))
            if (!known.contains(name)) name,
      };
      expect(unknown, isEmpty, reason: 'uydurma olabilecek adlar: $unknown');
    });

    test('bilinen her menü adı / etiket uygulama kaynağında gerçekten geçer', () {
      final missing = <String>[
        for (final name in <String>{...HelpContent.knownMenuTitles, ...HelpContent.knownScreenLabels})
          if (!source.contains(name)) name,
      ];
      expect(missing, isEmpty, reason: 'kaynakta bulunamayan adlar: $missing');
    });

    test('adımlar uydurma özellik içermez: yasaklı sözcükler', () {
      final text = _allHelpTexts().join('\n').toLowerCase();
      for (final fantasy in const <String>['whatsapp', 'telegram', 'canlı destek', 'sohbet', 'yapay zeka', 'push']) {
        expect(text.contains(fantasy), isFalse, reason: fantasy);
      }
    });

    test('SSS ve hesap metni dolu', () {
      expect(HelpContent.faqs.length, greaterThanOrEqualTo(4));
      for (final faq in HelpContent.faqs) {
        expect(faq.question.trim().endsWith('?') || faq.question.trim().endsWith('.'), isTrue);
        expect(faq.answer.trim(), isNotEmpty);
      }
      expect(HelpContent.accountAndDataText, contains('Profilim'));
    });
  });

  group('Tanıtım turu içeriği', () {
    test('her rolde 3-4 adım; son adım Yardım; başlık ve gövde dolu', () {
      for (final audience in HelpAudience.values) {
        final steps = OnboardingSteps.forAudience(audience);
        expect(steps.length, inInclusiveRange(3, 4), reason: '$audience');
        expect(steps.last.title, 'Yardım her zaman yanınızda');
        for (final step in steps) {
          expect(step.title.trim(), isNotEmpty);
          expect(step.body.trim().length, greaterThan(20));
        }
      }
    });

    test('adımlar kimlikleri farklı roller için farklı içerik verir', () {
      final bodies = <HelpAudience, String>{
        for (final a in HelpAudience.values) a: OnboardingSteps.forAudience(a).map((s) => s.body).join('|'),
      };
      expect(bodies.values.toSet().length, HelpAudience.values.length);
    });
  });
}
