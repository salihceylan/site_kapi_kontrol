// Yardım içeriği (lib/ui/views/help_content.dart) ve ilk kullanım turu metinleri: UYDURMA YOK.
//
// Metinlerde “çift tırnak” içinde geçen her arayüz adı (menü başlığı, düğme, bölüm, sekme) uygulama
// kaynağında gerçekten bulunmalıdır; her rolün konu listesi ve tur içeriği eksiksizdir.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/ui/views/help_content.dart';
import 'package:site_kapi_kontrol/ui/views/onboarding_tour.dart';

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
