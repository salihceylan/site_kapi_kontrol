// Platform Faz 3a: duyuru formu (AnnouncementFormDialog) ve yayın onayı.
//
// AGENTS.md kural 6: dört hücre (320x640 x2,0, 360x640 x1,5, yatay 640x360, tablet 820x1180) x açık / koyu;
// klavye açıkken de taşma yok. Davranış: doğrulama, hedef seçiciler, yayından önce kitle önizlemesi + onay,
// zamanlama (İstanbul saati -> UTC), SMS / WhatsApp "Yakında…" pasif, yalnız değişen alanlar gider,
// yayınlanmış duyuruda kilitli alanlar, çift gönderim koruması, geri tuşu, sunucu reddi pencerede kalır.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/announcement.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/dialogs/announcement_form_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';

import 'announcement_fixtures.dart';
import 'dialog_layout_harness.dart';
import 'list_fixtures.dart' show tapFinder, tapText;
import 'people_fixtures.dart';

/// Formun şimdiki zamanı (zamanlama kuralı): 16.10.2026 12:00 İstanbul = 09:00 UTC.
final DateTime _now = DateTime.utc(2026, 10, 16, 9);

class _Out {
  AnnouncementFormResult? result;
  bool closed = false;
}

PeopleScope _scope(AnnouncementFakeAuth auth) =>
    PeopleScope(authService: auth, siteCode: 11, siteName: 'Gül Sitesi', canWrite: true);

AnnouncementFakeAuth _auth() {
  final auth = AnnouncementFakeAuth.seeded();
  auth.clock = () => _now;
  final seed = PeopleFakeAuth.seeded();
  auth.apartmentsJson.addAll(seed.apartmentsJson);
  return auth;
}

Future<_Out> _openForm(
  WidgetTester t,
  AnnouncementFakeAuth auth, {
  AnnouncementDetail? announcement,
  VoidCallback? onRefreshNeeded,
  double width = 400,
  double height = 1000,
  double scale = 1.0,
  bool dark = false,
}) async {
  final out = _Out();
  await openDialogAt(
    t,
    (context) async {
      out.result = await AnnouncementFormDialog.show(
        context,
        scope: _scope(auth),
        announcement: announcement,
        now: () => _now,
        onRefreshNeeded: onRefreshNeeded,
      );
      out.closed = true;
    },
    width: width,
    height: height,
    scale: scale,
    dark: dark,
  );
  await settleFor(t);
  return out;
}

Future<AnnouncementDetail> _detailOf(AnnouncementFakeAuth auth, int id) => auth.getAnnouncement(11, id);

Future<void> _enter(WidgetTester t, String key, String text) async {
  final field = find.byKey(ValueKey<String>(key));
  await scrollTo(t, field);
  await t.enterText(field, text);
  await t.pump();
}

Future<void> _tapKey(WidgetTester t, String key) async {
  final finder = find.byKey(ValueKey<String>(key));
  await scrollTo(t, finder);
  await t.tap(finder);
  await t.pump();
  await t.pump(const Duration(milliseconds: 450));
}

Future<void> _submit(WidgetTester t, String label) async {
  await t.tap(find.text(label).last);
  await t.pump();
  await t.pump(const Duration(milliseconds: 450));
}

/// Başlık + metin doldurur.
Future<void> _fill(WidgetTester t, {String title = 'Su kesintisi', String body = 'Yarın su yok.'}) async {
  await _enter(t, 'announcement_title', title);
  await _enter(t, 'announcement_body', body);
}

Finder _dialogText(String text) => find.descendant(of: find.byType(AlertDialog).last, matching: find.text(text));

Future<void> _confirm(WidgetTester t, String label) async {
  final button = find.descendant(of: find.byType(AlertDialog).last, matching: find.text(label));
  await tapFinder(t, button);
  await settleFor(t);
}

Switch _emailSwitch(WidgetTester t) => t.widget<Switch>(
  find.descendant(
    of: find.byKey(const ValueKey<String>('announcement_send_email')),
    matching: find.byType(Switch),
  ),
);

String _fieldText(WidgetTester t, String key) {
  final field = find.descendant(of: find.byKey(ValueKey<String>(key)), matching: find.byType(EditableText));
  return t.widget<EditableText>(field).controller.text;
}

void main() {
  group('taşma matrisi', () {
    layoutMatrix('yeni duyuru: varsayılan görünüm (taslak)', (t, w, h, s, dark) async {
      final auth = _auth();
      await _openForm(t, auth, width: w, height: h, scale: s, dark: dark);
      expect(find.text('Yeni Duyuru'), findsWidgets);
      for (final label in const ['Başlık', 'Metin', 'Önem', 'Hedef', 'Gönderim', 'Yayın']) {
        await scrollTo(t, find.text(label).first);
        expect(find.text(label), findsWidgets, reason: label);
      }
      expect(find.text('Taslağı Kaydet'), findsOneWidget);
    });

    layoutMatrix('zamanla + bloklar + acil: tüm alanlar açık, uzun açıklamalar', (t, w, h, s, dark) async {
      final auth = _auth();
      await _openForm(t, auth, width: w, height: h, scale: s, dark: dark);
      await _tapKey(t, 'announcement_importance_urgent');
      await _tapKey(t, 'announcement_target_blocks');
      await _tapKey(t, 'announcement_mode_schedule');
      await scrollTo(t, find.byKey(const ValueKey<String>('announcement_publish_time')));
      expect(find.text('Zamanla'), findsWidgets);
      expect(find.byKey(const ValueKey<String>('announcement_publish_date')), findsOneWidget);
    });

    layoutMatrix('yayınlanmış duyuru: kilitli alanlar paneli', (t, w, h, s, dark) async {
      final auth = _auth();
      final detail = await _detailOf(auth, 41);
      await _openForm(t, auth, announcement: detail, width: w, height: h, scale: s, dark: dark);
      await scrollTo(t, find.byKey(const ValueKey<String>('announcement_locked_panel')));
      expect(find.text('Kilitli alanlar'), findsOneWidget);
    });

    testWidgets('klavye açıkken (320x640 x2,0) alanlar taşmaz ve hata kutusu görünür kalır', (t) async {
      final auth = _auth();
      await _openForm(t, auth, width: 320, height: 640, scale: 2.0);
      t.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(t.view.resetViewInsets);
      await t.pump();
      await _enter(t, 'announcement_title', 'Başlık');
      await _submit(t, 'Taslağı Kaydet');
      expect(find.text('Metin boş olamaz.'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });

  group('doğrulama ve pasif seçenekler', () {
    testWidgets('boş başlık / metin: Türkçe hata, sunucuya gidilmez, pencere açık kalır', (t) async {
      final auth = _auth();
      final out = await _openForm(t, auth);
      await _submit(t, 'Taslağı Kaydet');
      expect(find.text('Başlık boş olamaz.'), findsOneWidget);
      expect(find.text('Metin boş olamaz.'), findsOneWidget);
      expect(auth.announcementCreateCalls, isEmpty);
      expect(out.closed, isFalse);

      await _enter(t, 'announcement_title', '   ');
      await _submit(t, 'Taslağı Kaydet');
      expect(find.text('Başlık boş olamaz.'), findsOneWidget, reason: 'yalnız boşluk geçersiz');
    });

    testWidgets('karakter sayaçları (başlık 120, metin 5000) ve sınır aşılamaz', (t) async {
      final auth = _auth();
      await _openForm(t, auth);
      await _enter(t, 'announcement_title', 'Merhaba');
      await _enter(t, 'announcement_body', 'Metin içeriği');
      expect(find.text('7/120'), findsOneWidget);
      expect(find.text('13/5000'), findsOneWidget);

      await _enter(t, 'announcement_title', 'a' * 150);
      expect(_fieldText(t, 'announcement_title').length, 120, reason: 'sınırı aşan giriş sessizce değil, sayaçla kısıtlanır');
      expect(find.text('120/120'), findsOneWidget);
    });

    testWidgets('SMS ve WhatsApp "Yakında…" etiketli PASİF: anahtar yok, e-posta anahtarı tek', (t) async {
      final semantics = t.ensureSemantics();
      final auth = _auth();
      await _openForm(t, auth);
      await scrollTo(t, find.text('SMS ile gönder'));
      expect(find.text('SMS ile gönder'), findsOneWidget);
      expect(find.text('WhatsApp ile gönder'), findsOneWidget);
      expect(find.widgetWithText(StatusChip, 'Yakında…'), findsNWidgets(2));
      expect(find.byType(Switch), findsOneWidget, reason: 'yalnız "E-posta da gönder" anahtarı etkin');
      expect(find.byType(SwitchListTile), findsOneWidget);
      // Ekran okuyucu: birleşik tek ifade ("SMS ile gönder ... Yakında…").
      for (final name in const ['SMS ile gönder', 'WhatsApp ile gönder']) {
        final merged = find
            .ancestor(of: find.text(name), matching: find.byType(MergeSemantics))
            .first;
        final label = t.getSemantics(merged).getSemanticsData().label;
        expect(label, contains(name));
        expect(label, contains('Yakında…'), reason: '$name: durum yalnız renkle değil metinle de okunur');
      }
      semantics.dispose();
    });

    testWidgets('Acil seçilince "E-posta da gönder" varsayılan açılır', (t) async {
      final auth = _auth();
      await _openForm(t, auth);
      await scrollTo(t, find.byKey(const ValueKey<String>('announcement_send_email')));
      expect(_emailSwitch(t).value, isFalse);
      await _tapKey(t, 'announcement_importance_urgent');
      expect(_emailSwitch(t).value, isTrue);
      await _tapKey(t, 'announcement_importance_normal');
      expect(_emailSwitch(t).value, isTrue, reason: 'Normal\'e dönünce kullanıcının seçimi sessizce değişmez');
    });
  });

  group('oluşturma', () {
    testWidgets('taslak: kitle önizlemesi YOK; metinler kırpılarak gider; sonuç mesajı', (t) async {
      final auth = _auth();
      final out = await _openForm(t, auth);
      await _fill(t, title: '  Su kesintisi ', body: ' Yarın su yok. ');
      await _submit(t, 'Taslağı Kaydet');

      expect(auth.previewCalls, isEmpty);
      final call = auth.announcementCreateCalls.single;
      expect(call['publish'], 'draft');
      expect(call['target'], <String, dynamic>{'type': 'site'});
      expect(call['importance'], 'normal');
      expect(call['send_email'], false);
      expect(out.closed, isTrue);
      expect(out.result!.message, 'Taslak kaydedildi.');
      expect(out.result!.detail.status, AnnouncementStatus.draft);
      expect(out.result!.detail.title, 'Su kesintisi');
    });

    testWidgets('şimdi yayınla: önizleme + onay; Vazgeç yayınlamaz ve formu açık bırakır; onay yayınlar', (t) async {
      final auth = _auth();
      final out = await _openForm(t, auth);
      await _fill(t);
      await _tapKey(t, 'announcement_mode_now');
      expect(find.text('Yayınla'), findsOneWidget);
      await _submit(t, 'Yayınla');

      expect(auth.previewCalls.single.target, <String, dynamic>{'type': 'site'});
      expect(_dialogText('48 kişiye ulaşır'), findsOneWidget);
      expect(_dialogText('Yayını onayla'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('audience_email')), findsNothing, reason: 'e-posta istenmedi');

      await _confirm(t, 'Vazgeç');
      expect(auth.announcementCreateCalls, isEmpty);
      expect(out.closed, isFalse);
      expect(find.text('Kaydediliyor...'), findsNothing, reason: 'form yeniden kullanılabilir');

      await _submit(t, 'Yayınla');
      await _confirm(t, 'Yayınla');
      expect(auth.announcementCreateCalls.single['publish'], 'now');
      expect(out.closed, isTrue);
      expect(out.result!.message, 'Duyuru yayınlandı. 3 kişiye ulaştı.');
      expect(out.result!.detail.status, AnnouncementStatus.published);
    });

    testWidgets('e-posta isteniyorsa onayda "M kişinin e-postası var" görünür ve önizlemeye bayrak gider', (t) async {
      final auth = _auth();
      await _openForm(t, auth);
      await _fill(t);
      await _tapKey(t, 'announcement_importance_urgent');
      await _tapKey(t, 'announcement_mode_now');
      await _submit(t, 'Yayınla');
      expect(auth.previewCalls.single.sendEmail, isTrue);
      expect(
        find.text('44 kişinin e-postası var, 4 kişinin e-postası yok. Gönderilen e-postalar geri alınamaz.'),
        findsOneWidget,
      );
      await _confirm(t, 'Vazgeç');
    });

    testWidgets('kitle yoksa "Şimdi yayınla" onaya bile gitmez: açıklayıcı hata, kayıt oluşmaz', (t) async {
      final auth = _auth()
        ..audience = <String, dynamic>{
          'people': 0,
          'apartments': 0,
          'with_account': 0,
          'with_email': 0,
          'without_email': 0,
        };
      final out = await _openForm(t, auth);
      await _fill(t);
      await _tapKey(t, 'announcement_mode_now');
      await _submit(t, 'Yayınla');
      expect(find.text('Seçilen hedefte duyuruyu alacak kimse yok. Hedefi değiştirin.'), findsOneWidget);
      expect(find.text('Yayını onayla'), findsNothing);
      expect(auth.announcementCreateCalls, isEmpty);
      expect(out.closed, isFalse);
    });

    testWidgets('önizleme alınamazsa (ağ hatası) yayınlanmaz, hata görünür', (t) async {
      final auth = _auth()..previewError = ApiException('Kitle önizlemesi şu an alınamadı.');
      await _openForm(t, auth);
      await _fill(t);
      await _tapKey(t, 'announcement_mode_now');
      await _submit(t, 'Yayınla');
      expect(find.text('Kitle önizlemesi şu an alınamadı.'), findsOneWidget);
      expect(auth.announcementCreateCalls, isEmpty);
    });
  });

  group('zamanlama (İstanbul saati)', () {
    Future<void> schedule(WidgetTester t, String date, String time) async {
      await _fill(t);
      await _tapKey(t, 'announcement_mode_schedule');
      await _enter(t, 'announcement_publish_date', date);
      await _enter(t, 'announcement_publish_time', time);
    }

    testWidgets('geçerli zaman: onayda İstanbul saati yazılır; sunucuya UTC an gider (14:30 İstanbul = 11:30 UTC)', (t) async {
      final auth = _auth();
      final out = await _openForm(t, auth);
      await schedule(t, '20102026', '1430');
      expect(_fieldText(t, 'announcement_publish_date'), '20.10.2026', reason: 'noktalar kendiliğinden');
      expect(_fieldText(t, 'announcement_publish_time'), '14:30');
      await _submit(t, 'Zamanla');
      expect(find.textContaining('Yayın zamanı: 20.10.2026 14:30 (İstanbul saati)'), findsOneWidget);
      await _confirm(t, 'Zamanla');

      final call = auth.announcementCreateCalls.single;
      expect(call['publish'], 'schedule');
      expect(call['publish_at'], DateTime.utc(2026, 10, 20, 11, 30));
      expect(out.result!.detail.status, AnnouncementStatus.scheduled);
      expect(out.result!.message, 'Duyuru 20.10.2026 14:30 için zamanlandı.');
    });

    testWidgets('gece yarısı sınırı: 00:15 İstanbul bir önceki günün 21:15 UTC anıdır', (t) async {
      final auth = _auth();
      await _openForm(t, auth);
      await schedule(t, '21.10.2026', '00:15');
      await _submit(t, 'Zamanla');
      await _confirm(t, 'Zamanla');
      expect(auth.announcementCreateCalls.single['publish_at'], DateTime.utc(2026, 10, 20, 21, 15));
    });

    testWidgets('geçmiş / çok yakın zaman: en az 1 dakika kuralı (sınır dahil); sunucuya gidilmez', (t) async {
      final auth = _auth();
      await _openForm(t, auth);
      await schedule(t, '16.10.2026', '11:00');
      await _submit(t, 'Zamanla');
      expect(find.text('Yayın zamanı şu andan en az 1 dakika sonra olmalı (İstanbul saati).'), findsOneWidget);

      // Tam 1 dakika sonrası (12:01 İstanbul) hâlâ geçersiz; 12:02 geçerli.
      await _enter(t, 'announcement_publish_date', '16102026');
      await _enter(t, 'announcement_publish_time', '1201');
      await _submit(t, 'Zamanla');
      expect(find.text('Yayın zamanı şu andan en az 1 dakika sonra olmalı (İstanbul saati).'), findsOneWidget);
      expect(auth.previewCalls, isEmpty);
      expect(auth.announcementCreateCalls, isEmpty);

      await _enter(t, 'announcement_publish_time', '1202');
      await _submit(t, 'Zamanla');
      expect(find.text('Yayını onayla'), findsNothing);
      expect(find.text('Zamanlamayı onayla'), findsOneWidget);
      await _confirm(t, 'Vazgeç');
    });

    testWidgets('1 yıldan uzak zaman reddedilir', (t) async {
      final auth = _auth();
      await _openForm(t, auth);
      await schedule(t, '17.10.2027', '12:30');
      await _submit(t, 'Zamanla');
      expect(find.text('Yayın zamanı en çok 1 yıl sonrası olabilir.'), findsOneWidget);
      expect(auth.announcementCreateCalls, isEmpty);
    });

    testWidgets('tarih / saat eksik ya da biçimsiz: alan hataları', (t) async {
      final auth = _auth();
      await _openForm(t, auth);
      await _fill(t);
      await _tapKey(t, 'announcement_mode_schedule');
      await _submit(t, 'Zamanla');
      expect(find.text('Yayın tarihini girin.'), findsOneWidget);
      expect(find.text('Yayın saatini girin.'), findsOneWidget);

      await _enter(t, 'announcement_publish_date', '31022026');
      await _enter(t, 'announcement_publish_time', '2560');
      await _submit(t, 'Zamanla');
      expect(find.text('Tarihi GG.AA.YYYY biçiminde girin (örn. 05.03.2024).'), findsOneWidget);
      expect(find.text('Saati SS:DD biçiminde girin (örn. 14:30).'), findsOneWidget);
      expect(auth.previewCalls, isEmpty);
    });

    testWidgets('sunucu zamanlamayı reddederse (INVALID_SCHEDULE) Türkçe mesaj pencerede kalır', (t) async {
      final auth = _auth();
      // Sunucu saati istemciden ileride: istemci kabul eder, sunucu reddeder.
      auth.clock = () => _now.add(const Duration(days: 5));
      final out = await _openForm(t, auth);
      await schedule(t, '20.10.2026', '14:30');
      await _submit(t, 'Zamanla');
      await _confirm(t, 'Zamanla');
      expect(find.text('Yayın zamanı geçersiz. En az 1 dakika, en çok 1 yıl sonrası seçin.'), findsOneWidget);
      expect(out.closed, isFalse);
      expect(find.text('Zamanla'), findsWidgets);
    });
  });

  group('hedef seçiciler', () {
    testWidgets('bloklar: seçim zorunlu; seçici engel olmadan çalışır; chip ile çıkarılır; kimlikler gider', (t) async {
      final auth = _auth();
      final out = await _openForm(t, auth);
      await _fill(t);
      await _tapKey(t, 'announcement_target_blocks');
      await _submit(t, 'Taslağı Kaydet');
      expect(find.text('En az bir blok seçin.'), findsOneWidget);
      expect(auth.announcementCreateCalls, isEmpty);

      await _tapKey(t, 'announcement_add_block');
      expect(find.text('A Blok'), findsWidgets);
      expect(find.text('B Blok'), findsOneWidget);
      await tapFinder(t, find.descendant(of: find.byType(AlertDialog).last, matching: find.text('B Blok')));
      await settleFor(t);
      await _tapKey(t, 'announcement_add_block');
      await tapFinder(t, find.descendant(of: find.byType(AlertDialog).last, matching: find.text('A Blok')));
      await settleFor(t);
      expect(find.byKey(const ValueKey<String>('announcement_pick_1')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('announcement_pick_2')), findsOneWidget);

      // Bir chip çıkarılır: silme düğmesinin ipucu etiketi vardır.
      await scrollTo(t, find.byTooltip('B Blok hedeften çıkar'));
      await t.tap(find.byTooltip('B Blok hedeften çıkar'));
      await t.pump();
      expect(find.byKey(const ValueKey<String>('announcement_pick_2')), findsNothing);

      await _submit(t, 'Taslağı Kaydet');
      final target = auth.announcementCreateCalls.single['target']! as Map<String, dynamic>;
      expect(target, <String, dynamic>{'type': 'blocks', 'block_ids': <int>[1]});
      expect(out.closed, isTrue);
    });

    testWidgets('seçili blok seçicide tekrar listelenmez; bloklar alınamazsa seçici hata + Tekrar Dene gösterir', (t) async {
      final auth = _auth()..structureFails = true;
      await _openForm(t, auth);
      await _tapKey(t, 'announcement_target_blocks');
      await _tapKey(t, 'announcement_add_block');
      expect(find.text('Bu islem icin site yonetim yetkisi gerekir.'), findsOneWidget);
      expect(find.text('Tekrar Dene'), findsOneWidget);
      expect(find.text('Eklenecek blok bulunamadı.'), findsNothing);
    });

    testWidgets('daireler: seçici (Faz 2) ile eklenir; aynı daire iki kez eklenmez; kimlikler gider', (t) async {
      final auth = _auth();
      await _openForm(t, auth);
      await _fill(t);
      await _tapKey(t, 'announcement_target_apartments');
      await _tapKey(t, 'announcement_add_apartment');
      await tapFinder(t, find.descendant(of: find.byType(AlertDialog).last, matching: find.text('A Blok - 5')));
      await settleFor(t);
      expect(find.byKey(const ValueKey<String>('announcement_pick_301')), findsOneWidget);

      await _tapKey(t, 'announcement_add_apartment');
      await tapFinder(t, find.descendant(of: find.byType(AlertDialog).last, matching: find.text('A Blok - 5')));
      await settleFor(t);
      expect(find.byKey(const ValueKey<String>('announcement_pick_301')), findsOneWidget, reason: 'tekrar eklenmez');

      await _submit(t, 'Taslağı Kaydet');
      final target = auth.announcementCreateCalls.single['target']! as Map<String, dynamic>;
      expect(target, <String, dynamic>{
        'type': 'apartments',
        'apartment_ids': <int>[301],
      });
    });

    testWidgets('hedef türü değişince önceki türün kimlikleri gönderilmez', (t) async {
      final auth = _auth();
      await _openForm(t, auth);
      await _fill(t);
      await _tapKey(t, 'announcement_target_blocks');
      await _tapKey(t, 'announcement_add_block');
      await tapFinder(t, find.descendant(of: find.byType(AlertDialog).last, matching: find.text('A Blok')));
      await settleFor(t);
      await _tapKey(t, 'announcement_target_site');
      await _submit(t, 'Taslağı Kaydet');
      expect(auth.announcementCreateCalls.single['target'], <String, dynamic>{'type': 'site'});
    });

    testWidgets('sunucu hedefi reddederse (INVALID_TARGET) mesaj görünür ve form açık kalır', (t) async {
      final auth = _auth()
        ..announcementWriteError = ApiException(
          'Seçilen blok veya daireler bu siteye ait değil. Hedefi yeniden seçin.',
          statusCode: 400,
          code: 'INVALID_TARGET',
        );
      final out = await _openForm(t, auth);
      await _fill(t);
      await _submit(t, 'Taslağı Kaydet');
      expect(find.text('Seçilen blok veya daireler bu siteye ait değil. Hedefi yeniden seçin.'), findsOneWidget);
      expect(out.closed, isFalse);
      expect(_fieldText(t, 'announcement_title'), 'Su kesintisi', reason: 'girilen alanlar korunur');
      auth.announcementWriteError = null;
      await _submit(t, 'Taslağı Kaydet');
      expect(out.closed, isTrue);
    });
  });

  group('düzenleme', () {
    testWidgets('taslak: mevcut değerler dolu; yalnız DEĞİŞEN alan gider; değişiklik yoksa sunucuya gidilmez', (t) async {
      final auth = _auth();
      final detail = await _detailOf(auth, 40);
      final out = await _openForm(t, auth, announcement: detail);
      expect(find.text('Duyuruyu Düzenle'), findsOneWidget);
      expect(_fieldText(t, 'announcement_title'), 'Aidat hatırlatması');
      // Kayıtlı blok seçimi, site yapısından adlarıyla çözülür (tek tek çıkarılabilir).
      expect(find.byKey(const ValueKey<String>('announcement_pick_1')), findsOneWidget);

      await _submit(t, 'Taslağı Kaydet');
      expect(auth.announcementUpdateCalls, isEmpty);
      expect(out.closed, isTrue);
      expect(out.result, isNull, reason: 'değişiklik yok: null döner');
    });

    testWidgets('taslak: yalnız başlık değişti -> {title}; sonuç mesajı ve güncel ayrıntı', (t) async {
      final auth = _auth();
      final detail = await _detailOf(auth, 40);
      final out = await _openForm(t, auth, announcement: detail);
      await _enter(t, 'announcement_title', 'Aidat son gün');
      await _submit(t, 'Taslağı Kaydet');
      expect(auth.announcementUpdateCalls.single.fields, <String, Object?>{'title': 'Aidat son gün'});
      expect(out.result!.detail.title, 'Aidat son gün');
      expect(out.result!.message, 'Taslak kaydedildi.');
    });

    testWidgets('taslak -> zamanla: publish_at (UTC) gönderilir ve duruma "zamanlanmış" olur', (t) async {
      final auth = _auth();
      final detail = await _detailOf(auth, 40);
      final out = await _openForm(t, auth, announcement: detail);
      await _tapKey(t, 'announcement_mode_schedule');
      await _enter(t, 'announcement_publish_date', '25.10.2026');
      await _enter(t, 'announcement_publish_time', '09:00');
      await _submit(t, 'Zamanla');
      await _confirm(t, 'Zamanla');
      expect(auth.announcementUpdateCalls.single.fields, <String, Object?>{
        'publish_at': '2026-10-25T06:00:00.000Z',
      });
      expect(out.result!.detail.status, AnnouncementStatus.scheduled);
    });

    testWidgets('zamanlanmış: mevcut zaman İstanbul saatiyle dolu gelir; Taslak seçilince publish_at:null gider', (t) async {
      final auth = _auth();
      final detail = await _detailOf(auth, 39);
      final out = await _openForm(t, auth, announcement: detail);
      expect(_fieldText(t, 'announcement_publish_date'), '20.11.2026');
      expect(_fieldText(t, 'announcement_publish_time'), '14:30');

      // Hiçbir şey değişmeden kaydetmek zamanlamayı yeniden onaylatmaz ve istek yapmaz.
      await _submit(t, 'Zamanla');
      expect(find.text('Zamanlamayı onayla'), findsNothing);
      expect(auth.announcementUpdateCalls, isEmpty);
      expect(out.closed, isTrue);
    });

    testWidgets('zamanlanmış -> taslak: zamanlama kaldırılır (publish_at: null)', (t) async {
      final auth = _auth();
      final detail = await _detailOf(auth, 39);
      final out = await _openForm(t, auth, announcement: detail);
      await _tapKey(t, 'announcement_mode_draft');
      await _submit(t, 'Taslağı Kaydet');
      expect(auth.announcementUpdateCalls.single.fields, <String, Object?>{'publish_at': null});
      expect(out.result!.detail.status, AnnouncementStatus.draft);
    });

    testWidgets('taslak -> şimdi yayınla: kayıt + yayın TEK istekte; yayın başarısızsa hiçbir şey kaydedilmez, aynı değerlerle yeniden denenir', (t) async {
      final auth = _auth();
      final detail = await _detailOf(auth, 40);
      final out = await _openForm(t, auth, announcement: detail);
      await _enter(t, 'announcement_title', 'Aidat son gün');
      await _tapKey(t, 'announcement_mode_now');
      auth.audienceRecipients = <Map<String, dynamic>>[]; // yayın anında kitle boş: NO_RECIPIENTS
      await _submit(t, 'Yayınla');
      await _confirm(t, 'Yayınla');
      expect(auth.announcementUpdateCalls.single.fields, <String, Object?>{
        'title': 'Aidat son gün',
        'publish': 'now',
      });
      expect(auth.announcementPublishCalls, isEmpty, reason: 'ayrı yayın isteği yok');
      expect(find.text('Seçilen hedefte duyuruyu alacak kimse yok. Hedefi değiştirin.'), findsOneWidget);
      expect(out.closed, isFalse);
      expect(auth.rows[40]!['title'], 'Aidat hatırlatması', reason: 'yayın başarısız: düzenleme de geri alındı');
      expect(auth.rows[40]!['status'], 'draft');

      // Form değerleri korunur: yeniden denenince aynı istek gider ve bu kez yayınlanır.
      auth.audienceRecipients = <Map<String, dynamic>>[annRecipient(1, 'Ayşe Yılmaz')];
      await _submit(t, 'Yayınla');
      await _confirm(t, 'Yayınla');
      expect(auth.announcementUpdateCalls.length, 2);
      expect(auth.announcementUpdateCalls.last.fields['publish'], 'now');
      expect(out.closed, isTrue);
      expect(out.result!.detail.status, AnnouncementStatus.published);
      expect(out.result!.detail.title, 'Aidat son gün');
    });

    testWidgets('taslak, değişiklik yok, şimdi yayınla: yalnız yayın isteği (PATCH yok)', (t) async {
      final auth = _auth();
      final detail = await _detailOf(auth, 40);
      final out = await _openForm(t, auth, announcement: detail);
      await _tapKey(t, 'announcement_mode_now');
      await _submit(t, 'Yayınla');
      await _confirm(t, 'Yayınla');
      expect(auth.announcementUpdateCalls, isEmpty);
      expect(auth.announcementPublishCalls, <int>[40]);
      expect(out.result!.detail.status, AnnouncementStatus.published);
    });

    testWidgets('YAYINLANMIŞ: yalnız başlık / metin; diğer alanlar kilitli ve açıklamalı', (t) async {
      final auth = _auth();
      final detail = await _detailOf(auth, 41);
      final out = await _openForm(t, auth, announcement: detail);
      // Kilitli alanlar paneli: değerler ve neden.
      await scrollTo(t, find.byKey(const ValueKey<String>('announcement_locked_panel')));
      expect(find.text('Kilitli alanlar'), findsOneWidget);
      expect(find.textContaining('Yayınlanmış duyuruda yalnızca başlık ve metin değiştirilebilir'), findsOneWidget);
      expect(find.textContaining('"düzenlendi" notuyla görünür'), findsOneWidget);
      expect(find.text('Acil'), findsOneWidget);
      // Düzenlenebilir olmayan bölümler hiç çizilmez.
      expect(find.byKey(const ValueKey<String>('announcement_importance_urgent')), findsNothing);
      expect(find.byKey(const ValueKey<String>('announcement_target_blocks')), findsNothing);
      expect(find.byKey(const ValueKey<String>('announcement_mode_now')), findsNothing);
      expect(find.byKey(const ValueKey<String>('announcement_send_email')), findsNothing);
      expect(find.text('SMS ile gönder'), findsNothing);
      expect(find.text('Kaydet'), findsOneWidget);

      await _enter(t, 'announcement_body', 'Düzeltilmiş metin.');
      await _submit(t, 'Kaydet');
      expect(auth.announcementUpdateCalls.single.fields, <String, Object?>{'body': 'Düzeltilmiş metin.'});
      expect(auth.previewCalls, isEmpty, reason: 'yayınlanmış düzenlemede kitle onayı yok (yeniden bildirim yok)');
      expect(auth.announcementPublishCalls, isEmpty);
      expect(out.result!.message, 'Duyuru güncellendi.');
      expect(out.result!.detail.editedAt, isNotNull);
    });

    testWidgets('yayınlanmış, değişiklik yok: sunucuya gitmeden kapanır', (t) async {
      final auth = _auth();
      final detail = await _detailOf(auth, 41);
      final out = await _openForm(t, auth, announcement: detail);
      await _submit(t, 'Kaydet');
      expect(auth.announcementUpdateCalls, isEmpty);
      expect(out.closed, isTrue);
      expect(out.result, isNull);
    });

    testWidgets('yayınlanmış duyuru bu arada geri çekilmiş: INVALID_STATE Türkçe mesajla gösterilir', (t) async {
      final auth = _auth();
      final detail = await _detailOf(auth, 41);
      var refresh = 0;
      final out = await _openForm(t, auth, announcement: detail, onRefreshNeeded: () => refresh++);
      auth.rows[41]!['status'] = 'withdrawn';
      await _enter(t, 'announcement_title', 'Yeni başlık');
      await _submit(t, 'Kaydet');
      expect(find.text('Duyurunun durumu değişmiş. Listeyi yenileyip tekrar deneyin.'), findsOneWidget);
      expect(out.closed, isFalse);
      expect(refresh, 1, reason: 'çağıran ayrıntı ve listeyi tazelesin');
    });

    testWidgets('duyuru bu arada silinmiş (404): Türkçe mesaj + çağıran tazelenir', (t) async {
      final auth = _auth();
      final detail = await _detailOf(auth, 40);
      var refresh = 0;
      await _openForm(t, auth, announcement: detail, onRefreshNeeded: () => refresh++);
      auth.rows.remove(40);
      await _enter(t, 'announcement_title', 'Yeni başlık');
      await _submit(t, 'Taslağı Kaydet');
      expect(find.text('Duyuru bulunamadı ya da artık yayında değil.'), findsOneWidget);
      expect(refresh, 1);
    });

    testWidgets('kayıtlı daire seçimi toplu temizlenir; temizlenince yeniden seçim zorunlu', (t) async {
      final auth = _auth();
      auth.rows[45] = annRow(
        45,
        title: 'Daire duyurusu',
        status: 'draft',
        targetType: 'apartments',
        apartmentIds: const <int>[301, 302],
        labels: const <String>['A Blok - 5', 'A Blok - 6'],
      );
      final detail = await _detailOf(auth, 45);
      final out = await _openForm(t, auth, announcement: detail);
      await scrollTo(t, find.text('A Blok - 5'));
      expect(find.text('A Blok - 5'), findsOneWidget);
      expect(find.text('A Blok - 6'), findsOneWidget);
      expect(find.textContaining('Kayıtlı seçim tek tek çıkarılamaz'), findsOneWidget);

      await _tapKey(t, 'announcement_add_apartment_clear');
      expect(find.text('A Blok - 5'), findsNothing);
      await _submit(t, 'Taslağı Kaydet');
      expect(find.text('En az bir daire seçin.'), findsOneWidget);
      expect(auth.announcementUpdateCalls, isEmpty);
      expect(out.closed, isFalse);
    });
  });

  group('hız sınırı (429)', () {
    testWidgets('Çok sık deneme mesajı gösterilir ve gönder düğmesi retry_after süresince kilitlenir', (t) async {
      final auth = _auth()
        ..announcementWriteError = ApiException(
          'Çok fazla duyuru işlemi. Biraz sonra tekrar deneyin.',
          statusCode: 429,
          retryAfterSeconds: 45,
        );
      final out = await _openForm(t, auth);
      await _fill(t);
      await _submit(t, 'Taslağı Kaydet');
      expect(find.text('Çok sık deneme yapıldı. 45 saniye sonra tekrar deneyin.'), findsOneWidget);
      final submit = find.widgetWithText(ElevatedButton, 'Taslağı Kaydet');
      expect(t.widget<ElevatedButton>(submit).onPressed, isNull);
      // Kilitliyken dokunuş istek açmaz.
      await t.tap(submit, warnIfMissed: false);
      await t.pump();
      expect(auth.announcementCreateCalls.length, 1);

      await t.pump(const Duration(seconds: 44));
      expect(t.widget<ElevatedButton>(submit).onPressed, isNull);
      await t.pump(const Duration(seconds: 2));
      expect(t.widget<ElevatedButton>(submit).onPressed, isNotNull);

      auth.announcementWriteError = null;
      await _submit(t, 'Taslağı Kaydet');
      expect(out.closed, isTrue);
      expect(auth.announcementCreateCalls.length, 2);
    });

    testWidgets('çok uzun bekleme (1 saat) kilidi en çok 2 dakikayla sınırlanır', (t) async {
      final auth = _auth()
        ..announcementWriteError = ApiException('Çok fazla.', statusCode: 429, retryAfterSeconds: 3600);
      await _openForm(t, auth);
      await _fill(t);
      await _submit(t, 'Taslağı Kaydet');
      expect(find.text('Çok sık deneme yapıldı. 1 saat sonra tekrar deneyin.'), findsOneWidget);
      final submit = find.widgetWithText(ElevatedButton, 'Taslağı Kaydet');
      await t.pump(const Duration(seconds: 119));
      expect(t.widget<ElevatedButton>(submit).onPressed, isNull);
      await t.pump(const Duration(seconds: 2));
      expect(t.widget<ElevatedButton>(submit).onPressed, isNotNull, reason: 'kilit en çok 2 dakika sürer');
    });
  });

  group('çift gönderim, geri tuşu, hata görünürlüğü', () {
    testWidgets('gönderim sürerken: düğmeler kilitli, "Kaydediliyor...", tek istek; geri tuşu kapatmaz', (t) async {
      final auth = _auth()..announcementWriteGate = Completer<void>();
      final out = await _openForm(t, auth);
      await _fill(t);
      await _submit(t, 'Taslağı Kaydet');
      expect(find.text('Kaydediliyor...'), findsOneWidget);
      expect(auth.announcementCreateCalls.length, 1);

      // İkinci dokunuş: düğme devre dışı.
      await t.tap(find.text('Kaydediliyor...'), warnIfMissed: false);
      await t.pump();
      expect(auth.announcementCreateCalls.length, 1);
      // Vazgeç de kilitli; geri tuşu pencereyi kapatmaz.
      final cancel = t.widget<TextButton>(find.widgetWithText(TextButton, 'Vazgeç'));
      expect(cancel.onPressed, isNull);
      await t.binding.handlePopRoute();
      await t.pump();
      expect(find.byType(AnnouncementFormDialog), findsOneWidget);
      // Alanlar da kilitli.
      expect(t.widget<TextField>(find.descendant(
        of: find.byKey(const ValueKey<String>('announcement_title')),
        matching: find.byType(TextField),
      )).enabled, isFalse);

      auth.announcementWriteGate!.complete();
      await settleFor(t);
      expect(out.closed, isTrue);
      expect(auth.announcementCreateCalls.length, 1);
    });

    testWidgets('sunucu hatası: görünür konuma kaydırılır (320x640 x2,0 uzun formun altında kaydedilince bile)', (t) async {
      final auth = _auth()
        ..announcementWriteError = ApiException('Bu işlem için yetkiniz yok.', statusCode: 403, code: 'FORBIDDEN_ROLE');
      await _openForm(t, auth, width: 320, height: 640, scale: 2.0);
      await _fill(t);
      await scrollTo(t, find.text('Yayın').first);
      await _submit(t, 'Taslağı Kaydet');
      final notice = find.text('Bu işlem için yetkiniz yok.');
      expect(notice, findsOneWidget);
      // Hata kutusu pencerenin görünür alanında (ekran yüksekliği içinde).
      final top = t.getTopLeft(notice).dy;
      expect(top, greaterThanOrEqualTo(0));
      expect(top, lessThan(640));
    });

    testWidgets('boşta Vazgeç pencereyi kapatır ve sonuç null', (t) async {
      final auth = _auth();
      final out = await _openForm(t, auth);
      await tapText(t, 'Vazgeç');
      await settleFor(t);
      expect(out.closed, isTrue);
      expect(out.result, isNull);
      expect(auth.announcementCreateCalls, isEmpty);
    });
  });
}
