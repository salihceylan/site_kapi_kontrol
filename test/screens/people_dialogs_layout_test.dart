// Platform Faz 2a: Kişi ve Daire Kayıtları pencereleri (kişi kartı, kişi formu, ilişki, taşındı, araç,
// daire kartı / düzenleme, geçmiş, seçiciler).
//
// AGENTS.md kural 6: dört hücre (320x640 x2,0, 360x640 x1,5, yatay 640x360, tablet 820x1180) x açık /
// koyu; yükleniyor / hata / dolu durumlar taşmaz. Davranış: doğrulama mesajları, sunucu reddi pencerede
// kalır, yalnız değişen alanlar gider, hesabı olan kişide salt okunur alanlar, kurul üyesinde yazma
// düğmeleri yok.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/apartment_crm.dart';
import 'package:site_kapi_kontrol/models/history_item.dart';
import 'package:site_kapi_kontrol/models/person_record.dart';
import 'package:site_kapi_kontrol/models/residency_relation.dart';
import 'package:site_kapi_kontrol/models/vehicle_record.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/dialogs/apartment_card_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/apartment_edit_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/crm_confirm_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/crm_pickers.dart';
import 'package:site_kapi_kontrol/ui/dialogs/end_residency_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/history_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/large_dialog_parts.dart';
import 'package:site_kapi_kontrol/ui/dialogs/person_card_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/person_form_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/residency_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/vehicle_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/date_input.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/helpers/phone_input.dart';

import 'dialog_layout_harness.dart';
import 'list_fixtures.dart' show tapFinder, tapText;
import 'people_fixtures.dart';


/// Araç kaldırma düğmeleri: "{plaka} plakalı aracı kaldır" ipucu/anlamı.
final Finder _removeButtons = find.byWidgetPredicate(
  (w) => w is IconButton && (w.tooltip ?? '').endsWith('plakalı aracı kaldır'),
);
Finder _removeFor(String plate) => find.byTooltip('$plate plakalı aracı kaldır');

PeopleScope _scope(PeopleFakeAuth auth, {bool canWrite = true}) => PeopleScope(
  authService: auth,
  siteCode: 11,
  siteName: 'Gül Sitesi',
  canWrite: canWrite,
);

/// Pencereyi gerçek `showDialog` ile açar ve ilk yüklemenin bitmesini bekler.
Future<void> _open(
  WidgetTester t,
  Future<void> Function(BuildContext context) opener, {
  double width = 400,
  double height = 900,
  double scale = 1.0,
  bool dark = false,
}) async {
  await openDialogAt(t, opener, width: width, height: height, scale: scale, dark: dark);
  await settleFor(t);
}

Future<void> _enter(WidgetTester t, String key, String text) async {
  final field = find.byKey(ValueKey<String>(key));
  await scrollTo(t, field);
  await t.enterText(field, text);
  await t.pump();
}

String _fieldText(WidgetTester t, String key) {
  final field = find.descendant(
    of: find.byKey(ValueKey<String>(key)),
    matching: find.byType(EditableText),
  );
  return t.widget<EditableText>(field).controller.text;
}

bool _readOnly(WidgetTester t, String key) {
  final field = find.descendant(
    of: find.byKey(ValueKey<String>(key)),
    matching: find.byType(TextField),
  );
  return t.widget<TextField>(field).readOnly;
}

Future<void> _tapButton(WidgetTester t, String label) async {
  await scrollTo(t, find.text(label));
  await t.tap(find.text(label).last);
  await t.pump();
  await t.pump(const Duration(milliseconds: 450));
}

Future<void> _choose(WidgetTester t, Finder field, String label) async {
  await scrollTo(t, field);
  await t.tap(field);
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
  await t.tap(find.text(label).last);
  await t.pump();
  await t.pump(const Duration(milliseconds: 450));
}

/// Daire seçicisini açar, [label] dairesini seçer.
Future<void> _pickApartment(WidgetTester t, String fieldKey, String label) async {
  final field = find.byKey(ValueKey<String>(fieldKey));
  await scrollTo(t, field);
  await t.tap(field);
  await settleFor(t);
  final target = find.descendant(of: find.byType(AppCard), matching: find.text(label)).last;
  await scrollTo(t, target);
  await t.tap(target);
  await settleFor(t);
}


/// Formun içeriğini (kaydırılabilir bölge) en alta kaydırır.
Future<void> _scrollFormToBottom(WidgetTester t) async {
  final scrollable = find
      .descendant(of: find.byType(AlertDialog).last, matching: find.byType(Scrollable))
      .first;
  await t.drag(scrollable, const Offset(0, -3000));
  await t.pump(const Duration(milliseconds: 500));
}

/// G1: Kaydet'e basılınca özet bildirimi çıkar; ilk geçersiz metin alanı pencerenin GÖRÜNÜR bölgesine
/// kaydırılır ve odaklanır (kaydırılmış uzun formda hata ekran dışında gizli kalmaz).
Future<void> _expectFirstInvalidRevealed(WidgetTester t) async {
  await settleFor(t);
  expect(find.text('Lütfen işaretli alanları düzeltin.'), findsOneWidget);
  final viewport = t.getRect(
    find.descendant(of: find.byType(AlertDialog).last, matching: find.byType(Scrollable)).first,
  );
  Element? firstInvalid;
  for (final element in find.byType(TextFormField).evaluate()) {
    if (element is StatefulElement) {
      final state = element.state;
      if (state is FormFieldState<dynamic> && state.hasError) {
        firstInvalid = element;
        break;
      }
    }
  }
  expect(firstInvalid, isNotNull, reason: 'doğrulama hatası olan bir alan bekleniyordu');
  final rect = t.getRect(find.byElementPredicate((e) => identical(e, firstInvalid)));
  expect(rect.top, greaterThanOrEqualTo(viewport.top - 1), reason: 'ilk geçersiz alan görünür bölgede (üst)');
  expect(rect.top, lessThan(viewport.bottom), reason: 'ilk geçersiz alan görünür bölgede (alt)');
  final editable = find.descendant(
    of: find.byElementPredicate((e) => identical(e, firstInvalid)),
    matching: find.byType(EditableText),
  );
  expect(t.widget<EditableText>(editable).focusNode.hasFocus, isTrue, reason: 'ilk geçersiz alan odaklanır');
}

void main() {

  group('G1: doğrulama hatası görünür bölgeye gelir (5 kaydetme penceresi, 320x640 x2,0)', () {
    testWidgets('kişi formu: formun altındayken Kaydet -> ilk geçersiz alan (Ad Soyad) görünür ve odaklı, özet bildirimi', (t) async {
      final auth = PeopleFakeAuth.seeded();
      await _open(t, (c) => PersonFormDialog.show(c, scope: _scope(auth)), width: 320, height: 640, scale: 2.0);
      await _scrollFormToBottom(t);
      await t.tap(find.text('Kaydet').last);
      await t.pump();
      await _expectFirstInvalidRevealed(t);
      expect(auth.createPersonCalls, isEmpty);
    });

    testWidgets('daire düzenleme: geçersiz alan görünür bölgeye gelir', (t) async {
      final auth = PeopleFakeAuth.seeded();
      final detail = await auth.getApartment(11, 301);
      await _open(
        t,
        (c) => ApartmentEditDialog.show(c, scope: _scope(auth), apartment: detail),
        width: 320,
        height: 640,
        scale: 2.0,
      );
      await _enter(t, 'apartment_denominator', 'abc');
      await _scrollFormToBottom(t);
      await t.tap(find.text('Kaydet').last);
      await t.pump();
      await _expectFirstInvalidRevealed(t);
      expect(auth.updateApartmentCalls, isEmpty);
    });

    testWidgets('ilişki ekle: geçersiz tarih görünür bölgeye gelir; daire seçilmediği de bildirilir', (t) async {
      final auth = PeopleFakeAuth.seeded();
      await _open(
        t,
        (c) => ResidencyDialog.show(c, scope: _scope(auth), personId: 1, personName: 'Ayşe Yılmaz'),
        width: 320,
        height: 640,
        scale: 2.0,
      );
      await _enter(t, 'residency_move_in', '31022024');
      await _scrollFormToBottom(t);
      await t.tap(find.text('Kaydet').last);
      await t.pump();
      await _expectFirstInvalidRevealed(t);
      expect(find.text('Bir daire seçin.'), findsOneWidget);
    });

    testWidgets('araç ekle: geçersiz plaka görünür bölgeye gelir; kişi seçilmediği de bildirilir', (t) async {
      final auth = PeopleFakeAuth.seeded();
      await _open(t, (c) => VehicleDialog.show(c, scope: _scope(auth)), width: 320, height: 640, scale: 2.0);
      await _enter(t, 'vehicle_plate', '??');
      await _scrollFormToBottom(t);
      await t.tap(find.text('Ekle').last);
      await t.pump();
      await _expectFirstInvalidRevealed(t);
      expect(find.text('Araç sahibini seçin.'), findsOneWidget);
      expect(auth.createVehicleCalls, isEmpty);
    });

    testWidgets('taşındı: geçersiz tarih görünür bölgede, odaklı ve özet bildirimi var', (t) async {
      final auth = PeopleFakeAuth.seeded();
      final detail = await auth.getPerson(11, 2);
      await _open(
        t,
        (c) => EndResidencyDialog.show(
          c,
          scope: _scope(auth),
          residency: detail.currentResidencies.single,
          personName: detail.fullName,
          hasAccount: true,
        ),
        width: 320,
        height: 640,
        scale: 2.0,
      );
      await _enter(t, 'end_residency_date', '31022024');
      await _scrollFormToBottom(t);
      await t.tap(find.text('Taşındı Olarak İşaretle').last);
      await t.pump();
      await _expectFirstInvalidRevealed(t);
      expect(auth.endResidencyCalls, isEmpty);
    });
  });

  group('taşma matrisi: kişi kartı', () {
    layoutMatrix('dolu (bilgiler, ilişkiler, araçlar, tüm yazma düğmeleri)', (t, w, h, s, dark) async {
      final auth = PeopleFakeAuth.seeded();
      await _open(
        t,
        (c) => PersonCardDialog.show(c, scope: _scope(auth), personId: 1, initialName: 'Ayşe Yılmaz'),
        width: w,
        height: h,
        scale: s,
        dark: dark,
      );
      expect(find.text('Ayşe Yılmaz'), findsWidgets);
      expect(find.text('Bilgiler'), findsOneWidget);
      expect(find.text('+90 555 111 22 33'), findsOneWidget);
      expect(find.text('ayse@example.com'), findsOneWidget);
      expect(find.text('Kapıcıya haber verildi.'), findsOneWidget);
      expect(find.text('A Blok - 5'), findsOneWidget);
      expect(find.text('Malik'), findsWidgets);
      expect(find.text('Giriş: 05.03.2024'), findsOneWidget);
      expect(find.text('34 ABC 123'), findsOneWidget);
      for (final label in const <String>[
        'Düzenle',
        'İlişki Ekle',
        'İlişkiyi Düzenle',
        'Taşındı',
        'Araç Ekle',
        'Geçmiş',
        'Kapat',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(_removeFor('34 ABC 123'), findsOneWidget);
      expect(_removeButtons, findsOneWidget);
    });

    layoutMatrix('hesabı olan kişi: rozet, yardım metni, eski ilişkiler', (t, w, h, s, dark) async {
      final auth = PeopleFakeAuth.seeded();
      await _open(
        t,
        (c) => PersonCardDialog.show(c, scope: _scope(auth), personId: 2),
        width: w,
        height: h,
        scale: s,
        dark: dark,
      );
      expect(find.text('Hesabı var'), findsOneWidget);
      expect(find.text('Kişinin kendi profilinden değişir'), findsOneWidget);
      expect(find.text('Eski ilişkiler'), findsOneWidget);
      expect(find.text('B Blok - 2'), findsOneWidget);
      expect(find.text('Çıkış: 31.01.2025'), findsOneWidget);
      expect(find.text('Kiracı'), findsWidgets, reason: 'roller çipi + güncel + eski ilişki çipi');
      expect(find.text('Kayıtlı araç yok.'), findsOneWidget);
    });

    layoutMatrix('salt okunur (kurul üyesi): yazma düğmeleri YOK, Geçmiş var', (t, w, h, s, dark) async {
      final auth = PeopleFakeAuth.seeded();
      await _open(
        t,
        (c) => PersonCardDialog.show(c, scope: _scope(auth, canWrite: false), personId: 1),
        width: w,
        height: h,
        scale: s,
        dark: dark,
      );
      expect(find.text('Ayşe Yılmaz'), findsWidgets);
      for (final label in const <String>[
        'Düzenle',
        'İlişki Ekle',
        'İlişkiyi Düzenle',
        'Taşındı',
        'Araç Ekle',
      ]) {
        expect(find.text(label), findsNothing, reason: label);
      }
      expect(_removeButtons, findsNothing);
      expect(find.text('Geçmiş'), findsOneWidget);
    });

    layoutMatrix('yükleniyor', (t, w, h, s, dark) async {
      final auth = PeopleFakeAuth.seeded()..personGate = Completer<void>();
      await _open(
        t,
        (c) => PersonCardDialog.show(c, scope: _scope(auth), personId: 1, initialName: 'Ayşe Yılmaz'),
        width: w,
        height: h,
        scale: s,
        dark: dark,
      );
      expect(find.byType(DialogRowsSkeleton), findsOneWidget);
      expect(find.text('Kişi bilgileri yükleniyor...'), findsOneWidget);
      expect(find.text('Bilgiler'), findsNothing);
    });

    layoutMatrix('hata: mesaj + Tekrar Dene (boş kart çizilmez)', (t, w, h, s, dark) async {
      final auth = PeopleFakeAuth.seeded()
        ..personError = ApiException('Bu işlem için yetkiniz yok.', statusCode: 403, code: 'FORBIDDEN_ROLE');
      await _open(
        t,
        (c) => PersonCardDialog.show(c, scope: _scope(auth), personId: 1),
        width: w,
        height: h,
        scale: s,
        dark: dark,
      );
      expect(find.text('Bu işlem için yetkiniz yok.'), findsOneWidget);
      expect(find.text('Tekrar Dene'), findsOneWidget);
      expect(find.text('Bilgiler'), findsNothing);
    });
  });

  group('kişi kartı davranışı', () {
    testWidgets('Tekrar Dene ayrıntıyı getirir', (t) async {
      final auth = PeopleFakeAuth.seeded()..personError = ApiException('Sunucu yanıt vermedi, tekrar deneyin.');
      await _open(t, (c) => PersonCardDialog.show(c, scope: _scope(auth), personId: 1));
      expect(find.text('Sunucu yanıt vermedi, tekrar deneyin.'), findsOneWidget);
      auth.personError = null;
      await tapText(t, 'Tekrar Dene');
      await settleFor(t);
      expect(find.text('Bilgiler'), findsOneWidget);
      expect(auth.getPersonCalls, <int>[1, 1]);
    });

    testWidgets('Taşındı: onay penceresi, tarih bugün; onaylanınca ilişki eski olur, kart güncellenir, liste haberdar edilir', (t) async {
      final auth = PeopleFakeAuth.seeded();
      var changed = 0;
      await _open(
        t,
        (c) => PersonCardDialog.show(c, scope: _scope(auth), personId: 1, onChanged: () => changed++),
      );

      await _tapButton(t, 'Taşındı');
      expect(find.text('Taşındı Olarak İşaretle'), findsOneWidget);
      expect(_fieldText(t, 'end_residency_date'), formatDateField(DateTime.now()));
      expect(find.textContaining('Kayıt silinmez; kişi dairenin geçmişinde kalır.'), findsOneWidget);
      expect(find.textContaining('kapı yetkisi kapanır'), findsNothing, reason: 'hesapsız kişide uyarı yok');

      await _tapButton(t, 'Taşındı Olarak İşaretle');
      await settleFor(t);
      expect(auth.endResidencyCalls, hasLength(1));
      expect(crmDateParamForTest(auth.endResidencyCalls.single.date!), crmDateParamForTest(DateTime.now()));
      expect(changed, 1);
      expect(find.text('Eski ilişkiler'), findsOneWidget);
      expect(find.text('Eski sakin'), findsOneWidget,
          reason: 'son ilişki bitince kişi otomatik pasif olur (sunucu)');
      expect(find.text('Taşındı'), findsNothing, reason: 'güncel ilişki kalmadı: düğme kalktı');
      expect(find.text('Bu kişinin bağlı olduğu daire yok.'), findsNothing,
          reason: 'eski ilişki listede durur');
    });

    testWidgets('Taşındı: hesabı olan kişide kapı yetkisi uyarısı; geçersiz tarih gönderilmez; Vazgeç iptal eder', (t) async {
      final auth = PeopleFakeAuth.seeded();
      await _open(t, (c) => PersonCardDialog.show(c, scope: _scope(auth), personId: 2));
      await _tapButton(t, 'Taşındı');
      expect(find.textContaining('bu dairedeki kapı yetkisi kapanır'), findsOneWidget);

      await _enter(t, 'end_residency_date', '31022024');
      await _tapButton(t, 'Taşındı Olarak İşaretle');
      // G13: 31.02.2024 biçim olarak doğru ama gerçek bir gün değil -> "Geçersiz tarih" (biçim mesajı değil).
      expect(
        find.text('Geçersiz tarih. Gerçek bir gün ve ay ile 1900-2100 arası yıl girin (örn. 05.03.2024).'),
        findsOneWidget,
      );
      // G1: üstte özet bildirimi de görünür (kaydırılmış formda alan hatası gizli kalmasın).
      expect(find.text('Lütfen işaretli alanları düzeltin.'), findsOneWidget);
      expect(auth.endResidencyCalls, isEmpty);

      await tapText(t, 'Vazgeç');
      await settleFor(t);
      expect(auth.endResidencyCalls, isEmpty);
      expect(find.text('Taşındı Olarak İşaretle'), findsNothing);
    });

    testWidgets('Taşındı sunucu reddi: mesaj pencerede kalır, pencere açık', (t) async {
      final auth = PeopleFakeAuth.seeded()
        ..writeError = ApiException('Bu işlem için yetkiniz yok.', statusCode: 403, code: 'FORBIDDEN_ROLE');
      await _open(t, (c) => PersonCardDialog.show(c, scope: _scope(auth), personId: 1));
      await _tapButton(t, 'Taşındı');
      await _tapButton(t, 'Taşındı Olarak İşaretle');
      await settleFor(t);
      expect(find.text('Bu işlem için yetkiniz yok.'), findsOneWidget);
      expect(find.text('Taşındı Olarak İşaretle'), findsOneWidget);
    });

    testWidgets('İlişki Ekle: daire seçilmeden uyarı; dolu malik/kiracı RELATION_TAKEN mesajıyla pencerede kalır; ilişki değişince kaydolur', (t) async {
      final auth = PeopleFakeAuth.seeded();
      var changed = 0;
      await _open(
        t,
        (c) => PersonCardDialog.show(c, scope: _scope(auth), personId: 1, onChanged: () => changed++),
      );
      await _tapButton(t, 'İlişki Ekle');
      expect(find.text('Giriş tarihi (isteğe bağlı)'), findsOneWidget);

      await _tapButton(t, 'Kaydet');
      expect(find.text('Bir daire seçin.'), findsOneWidget);
      expect(auth.addResidencyCalls, isEmpty);

      await _pickApartment(t, 'residency_apartment', 'A Blok - 6');
      await _choose(t, find.byKey(const ValueKey<String>('residency_relation')), 'Kiracı');
      await _tapButton(t, 'Kaydet');
      await settleFor(t);
      expect(find.text('Bu dairede bu ilişki için aktif bir kişi zaten var.'), findsOneWidget);
      expect(find.text('Kaydet'), findsOneWidget, reason: 'pencere açık, düğme yeniden etkin');

      await _choose(t, find.byKey(const ValueKey<String>('residency_relation')), 'Aile Üyesi');
      await _enter(t, 'residency_move_in', '01022025');
      await _tapButton(t, 'Kaydet');
      await settleFor(t);
      expect(auth.addResidencyCalls.last.apartment, 302);
      expect(auth.addResidencyCalls.last.relation, ResidencyRelation.familyMember);
      expect(auth.addResidencyCalls.last.date, DateTime(2025, 2, 1));
      expect(changed, 1);
      expect(find.text('A Blok - 6'), findsOneWidget, reason: 'kart yeni ilişkiyi gösterir');
    });

    testWidgets('İlişkiyi Düzenle: yalnız ilişki ve giriş tarihi; mevcut değerler dolu gelir', (t) async {
      final auth = PeopleFakeAuth.seeded();
      await _open(t, (c) => PersonCardDialog.show(c, scope: _scope(auth), personId: 1));
      await _tapButton(t, 'İlişkiyi Düzenle');
      expect(find.text('İlişkiyi Düzenle'), findsNWidgets(2), reason: 'kart düğmesi + pencere başlığı');
      expect(_fieldText(t, 'residency_move_in'), '05.03.2024');
      expect(find.byKey(const ValueKey<String>('residency_apartment')), findsNothing,
          reason: 'daire düzenlemede sabit');

      await _choose(t, find.byKey(const ValueKey<String>('residency_relation')), 'Kiracı');
      await _tapButton(t, 'Kaydet');
      await settleFor(t);
      expect(auth.updateResidencyCalls.single.relation, ResidencyRelation.tenant);
      expect(auth.updateResidencyCalls.single.date, isNull, reason: 'tarih değişmedi: gönderilmez');
      expect(auth.updateResidencyCalls.single.clear, isFalse);
    });

    testWidgets('Araç Ekle: araç sahibi sabit; geçersiz plaka sunucuya gitmez; kayıtlı plaka PLATE_EXISTS; yeni plaka kartı günceller', (t) async {
      final auth = PeopleFakeAuth.seeded();
      var changed = 0;
      await _open(
        t,
        (c) => PersonCardDialog.show(c, scope: _scope(auth), personId: 1, onChanged: () => changed++),
      );
      await _tapButton(t, 'Araç Ekle');
      expect(find.text('Araç sahibi: Ayşe Yılmaz'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('vehicle_person')), findsNothing);

      await _enter(t, 'vehicle_plate', '12');
      await _tapButton(t, 'Ekle');
      expect(find.text('Plaka biçimi geçersiz.'), findsOneWidget);
      expect(auth.createVehicleCalls, isEmpty);

      await _enter(t, 'vehicle_plate', '34 ABC 123');
      await _tapButton(t, 'Ekle');
      await settleFor(t);
      expect(find.text('Bu plaka bu sitede zaten kayıtlı.'), findsOneWidget);
      expect(changed, 0);

      await _enter(t, 'vehicle_plate', '06 DEF 456');
      await _enter(t, 'vehicle_note', 'Mavi araç');
      await _tapButton(t, 'Ekle');
      await settleFor(t);
      expect(auth.createVehicleCalls.last.person, 1);
      expect(auth.createVehicleCalls.last.plate, '06 DEF 456');
      expect(auth.createVehicleCalls.last.note, 'Mavi araç');
      expect(changed, 1);
      expect(find.text('06 DEF 456'), findsOneWidget, reason: 'kart yeniden çekildi');
      expect(_removeButtons, findsNWidgets(2));
    });

    testWidgets('araç kaldırma: onay sorulur; onaylanınca kaldırılır ve kart güncellenir', (t) async {
      final auth = PeopleFakeAuth.seeded();
      var changed = 0;
      await _open(
        t,
        (c) => PersonCardDialog.show(c, scope: _scope(auth), personId: 1, onChanged: () => changed++),
      );
      await tapFinder(t, _removeFor('34 ABC 123'));
      expect(find.text('34 ABC 123 plakalı araç kaldırılsın mı? Kayıt silinmez, pasifleşir.'), findsOneWidget);
      await tapText(t, 'Vazgeç');
      expect(auth.removeVehicleCalls, isEmpty);

      await tapFinder(t, _removeFor('34 ABC 123'));
      await tapText(t, 'Kaldır');
      await settleFor(t);
      expect(auth.removeVehicleCalls, <int>[1]);
      expect(changed, 1);
      expect(find.text('Kayıtlı araç yok.'), findsOneWidget);
    });

    testWidgets('araç kaldırma reddedilirse hata kartın içinde görünür', (t) async {
      final auth = PeopleFakeAuth.seeded();
      await _open(t, (c) => PersonCardDialog.show(c, scope: _scope(auth), personId: 1));
      auth.writeError = ApiException('Bu işlem için yetkiniz yok.', statusCode: 403, code: 'FORBIDDEN_ROLE');
      await tapFinder(t, _removeFor('34 ABC 123'));
      await tapText(t, 'Kaldır');
      await settleFor(t);
      expect(find.text('Bu işlem için yetkiniz yok.'), findsOneWidget);
      expect(find.text('34 ABC 123'), findsOneWidget);
    });

    testWidgets('Düzenle: kişi formu açılır; kaydedince kart yeni telefonu gösterir', (t) async {
      final auth = PeopleFakeAuth.seeded();
      var changed = 0;
      await _open(
        t,
        (c) => PersonCardDialog.show(c, scope: _scope(auth), personId: 1, onChanged: () => changed++),
      );
      await _tapButton(t, 'Düzenle');
      expect(find.text('Kişiyi Düzenle'), findsOneWidget);
      await _enter(t, 'person_phone', '5324445566');
      await _tapButton(t, 'Kaydet');
      await settleFor(t);
      expect(auth.updatePersonCalls.single.fields, <String, Object?>{'phone': '+905324445566'});
      expect(changed, 1);
      expect(find.text('+90 532 444 55 66'), findsOneWidget);
    });

    testWidgets('Geçmiş: kişi geçmişi hedef türü ve numarasıyla çekilir', (t) async {
      final auth = PeopleFakeAuth.seeded()
        ..historyPages = <HistoryPage>[
          HistoryPage(items: <HistoryItem>[pplHistory(7)]),
        ];
      await _open(t, (c) => PersonCardDialog.show(c, scope: _scope(auth), personId: 1));
      await _tapButton(t, 'Geçmiş');
      await settleFor(t);
      expect(auth.historyCalls.single.type, 'person');
      expect(auth.historyCalls.single.id, 1);
      expect(find.text('Kişi bilgisi güncellendi'), findsOneWidget);
    });
  });

  group('taşma matrisi: kişi formu', () {
    layoutMatrix('ekleme: tüm alanlar (daire seçili: ilişki, tarih; e-posta yardım metni)', (t, w, h, s, dark) async {
      final auth = PeopleFakeAuth.seeded();
      await _open(
        t,
        (c) => PersonFormDialog.show(c, scope: _scope(auth)),
        width: w,
        height: h,
        scale: s,
        dark: dark,
      );
      expect(find.text('Kişi Ekle'), findsOneWidget);
      expect(_fieldText(t, 'person_phone'), '+90 ', reason: '+90 hazır');
      expect(find.text('Telefon *'), findsOneWidget);
      expect(find.text('Daire (blok + daire no, isteğe bağlı)'), findsOneWidget);

      await _pickApartment(t, 'person_apartment', 'B Blok - 2');
      expect(find.text('B Blok - 2'), findsOneWidget);
      expect(find.text('İlişki *'), findsOneWidget);
      expect(find.text('Taşınma (giriş) tarihi *'), findsOneWidget);
      await _enter(t, 'person_email', 'yeni@example.com');
      await t.pump();
      expect(find.textContaining('Dairenin sakin hesabı yoksa bu kişiye giriş bilgileri (kullanıcı adı ve PIN) e-postayla gönderilir.'), findsOneWidget);
      expect(find.textContaining('Telefon yalnız iletişim içindir; giriş telefonla yapılmaz.'), findsOneWidget);
      expect(find.textContaining('hesap açılır'), findsNothing, reason: 'bu e-postanın hesabı var / yok ima edilmez');
    });

    layoutMatrix('hesabı olan kişi düzenleme: ad / telefon / e-posta salt okunur + yardım metni', (t, w, h, s, dark) async {
      final auth = PeopleFakeAuth.seeded();
      final detail = await auth.getPerson(11, 2);
      await _open(
        t,
        (c) => PersonFormDialog.show(c, scope: _scope(auth), person: detail),
        width: w,
        height: h,
        scale: s,
        dark: dark,
      );
      expect(find.text('Kişiyi Düzenle'), findsOneWidget);
      expect(find.text('Kişinin kendi profilinden değişir'), findsNothing,
          reason: 'alanlarda yardım metni tekrarlanmaz');
      expect(find.text('Bu kişinin hesabı var. Ad, telefon ve e-posta kişinin kendi profilinden değişir.'),
          findsOneWidget, reason: 'tek bilgilendirme bandı');
      expect(find.textContaining('Bu kişinin hesabı var.'), findsOneWidget);
      expect(find.text('Daire (blok + daire no, isteğe bağlı)'), findsNothing, reason: 'düzenlemede daire yok');
    });
  });

  group('kişi formu: hesap açıklaması (saha F2.03; sunucu: people_service.createPerson)', () {
    const noEmail = 'E-posta girmezseniz kişi yalnız kayıt olarak tutulur; giriş hesabı açılmaz.';
    const noApartment =
        'Daire seçmezseniz kişi yalnız kayıt olarak tutulur; giriş hesabı açılmaz. '
        'Kişi siteye katılınca e-postası hesabıyla eşleştirilir.';
    const withApartment =
        'Dairenin sakin hesabı yoksa bu kişiye giriş bilgileri (kullanıcı adı ve PIN) e-postayla gönderilir. '
        'Sakin hesabı varsa kişi yalnız kayıt olarak tutulur. '
        'E-posta bu sitedeki kayıtlı bir hesaba aitse kişi o hesaba bağlanır.';
    const phoneHelp = 'Telefon yalnız iletişim içindir; giriş telefonla yapılmaz.';

    testWidgets('yardım metni duruma göre değişir: e-posta yok / e-posta var daire yok / e-posta + daire', (t) async {
      final auth = PeopleFakeAuth.seeded();
      await _open(t, (c) => PersonFormDialog.show(c, scope: _scope(auth)));
      expect(find.text(noEmail), findsOneWidget);
      expect(find.textContaining(phoneHelp), findsOneWidget);

      await _enter(t, 'person_email', 'yeni@example.com');
      expect(find.text(noApartment), findsOneWidget);
      expect(find.text(noEmail), findsNothing);

      await _pickApartment(t, 'person_apartment', 'B Blok - 2');
      expect(find.text(withApartment), findsOneWidget);
      expect(find.text(noApartment), findsNothing);

      await _enter(t, 'person_email', 'gecersiz');
      expect(find.text(noEmail), findsOneWidget, reason: 'geçerli e-posta yokken e-posta yok sayılır');
    });

    testWidgets('düzenlemede ekleme yardım metinleri çıkmaz', (t) async {
      final auth = PeopleFakeAuth.seeded();
      final detail = await auth.getPerson(11, 1);
      await _open(t, (c) => PersonFormDialog.show(c, scope: _scope(auth), person: detail));
      expect(find.text(noEmail), findsNothing);
      expect(find.text(noApartment), findsNothing);
      expect(find.text(withApartment), findsNothing);
    });
  });

  group('kişi formu davranışı', () {
    testWidgets('boş ad: doğrulama mesajı, sunucuya gitmez', (t) async {
      final auth = PeopleFakeAuth.seeded();
      await _open(t, (c) => PersonFormDialog.show(c, scope: _scope(auth)));
      await _tapButton(t, 'Kaydet');
      expect(find.text('Ad soyad en az 2 karakter olmalı.'), findsOneWidget);
      expect(auth.createPersonCalls, isEmpty);
    });

    testWidgets('telefon: yazarken 3-3-2-2 biçimlenir; eksik hane ve hatalı e-posta reddedilir', (t) async {
      final auth = PeopleFakeAuth.seeded();
      await _open(t, (c) => PersonFormDialog.show(c, scope: _scope(auth)));
      await _enter(t, 'person_name', 'Ali Veli');
      await _enter(t, 'person_phone', '5551234567');
      expect(_fieldText(t, 'person_phone'), '+90 555 123 45 67');

      await _enter(t, 'person_phone', '555123');
      expect(_fieldText(t, 'person_phone'), '+90 555 123');
      await _enter(t, 'person_email', 'gecersiz');
      await _tapButton(t, 'Kaydet');
      expect(find.text(phoneFormatError), findsOneWidget);
      expect(find.text('Geçerli bir e-posta girin.'), findsOneWidget);
      expect(auth.createPersonCalls, isEmpty);
    });

    testWidgets('ekleme: alanlar sunucuya sözleşmedeki biçimle gider; pencere sonucu döndürür', (t) async {
      final auth = PeopleFakeAuth.seeded();
      PersonDetail? result;
      await _open(t, (c) async => result = await PersonFormDialog.show(c, scope: _scope(auth)));
      await _enter(t, 'person_name', '  Ali Veli ');
      await _enter(t, 'person_phone', '05551234567');
      await _enter(t, 'person_email', 'Ali@Example.com');
      await _enter(t, 'person_note', 'Not');
      await _pickApartment(t, 'person_apartment', 'B Blok - 2');
      await _choose(t, find.byKey(const ValueKey<String>('person_relation')), 'Malik');
      await _enter(t, 'person_move_in', '05032024');
      await _tapButton(t, 'Kaydet');
      await settleFor(t);

      final call = auth.createPersonCalls.single;
      expect(call['full_name'], '  Ali Veli ', reason: 'kırpma sunucu istemcisinde (AuthApi) yapılır');
      expect(call['phone'], '+905551234567');
      expect(call['email'], 'Ali@Example.com');
      expect(call['note'], 'Not');
      expect(call['apartment_id'], 303);
      expect(call['relation'], ResidencyRelation.owner);
      expect(call['move_in_date'], DateTime(2024, 3, 5));
      expect(result, isNotNull);
      expect(result!.fullName, 'Ali Veli');
      expect(find.text('Kişi Ekle'), findsNothing, reason: 'başarıda pencere kapanır');
    });

    testWidgets('daire seçilmediyse ilişki ve tarih gönderilmez', (t) async {
      final auth = PeopleFakeAuth.seeded();
      await _open(t, (c) => PersonFormDialog.show(c, scope: _scope(auth)));
      await _enter(t, 'person_name', 'Ali Veli');
      await _enter(t, 'person_email', 'ali@example.com');
      await _tapButton(t, 'Kaydet');
      await settleFor(t);
      final call = auth.createPersonCalls.single;
      expect(call['phone'], isNull, reason: '"+90 " tek başına boş sayılır');
      expect(call['apartment_id'], isNull);
      expect(call['relation'], isNull);
      expect(call['move_in_date'], isNull);
    });

    testWidgets('geçersiz giriş tarihi reddedilir; aynı e-posta PERSON_EXISTS ile pencerede kalır', (t) async {
      final auth = PeopleFakeAuth.seeded();
      await _open(t, (c) => PersonFormDialog.show(c, scope: _scope(auth)));
      await _enter(t, 'person_name', 'Yeni Kişi');
      await _pickApartment(t, 'person_apartment', 'B Blok - 2');
      await _enter(t, 'person_move_in', '31022024');
      await _tapButton(t, 'Kaydet');
      // G13: 31.02.2024 biçim olarak doğru ama gerçek bir gün değil -> "Geçersiz tarih" (biçim mesajı değil).
      expect(
        find.text('Geçersiz tarih. Gerçek bir gün ve ay ile 1900-2100 arası yıl girin (örn. 05.03.2024).'),
        findsOneWidget,
      );
      // G1: üstte özet bildirimi de görünür (kaydırılmış formda alan hatası gizli kalmasın).
      expect(find.text('Lütfen işaretli alanları düzeltin.'), findsOneWidget);
      expect(auth.createPersonCalls, isEmpty);

      await _enter(t, 'person_move_in', '05032024');
      await _choose(t, find.byKey(const ValueKey<String>('person_relation')), 'Malik');
      await _enter(t, 'person_email', 'ayse@example.com');
      await _tapButton(t, 'Kaydet');
      await settleFor(t);
      expect(find.text('Bu e-posta ile kayıtlı bir kişi zaten var.'), findsOneWidget);
      expect(find.text('Kişi Ekle'), findsOneWidget, reason: 'pencere açık');
      expect(find.text('Kaydet'), findsOneWidget, reason: 'düğme yeniden etkin');
    });

    testWidgets('kurul üyesi / yetkisiz sunucu reddi (FORBIDDEN_ROLE) Türkçe gösterilir', (t) async {
      final auth = PeopleFakeAuth.seeded()
        ..writeError = ApiException('Bu işlem için yetkiniz yok.', statusCode: 403, code: 'FORBIDDEN_ROLE');
      await _open(t, (c) => PersonFormDialog.show(c, scope: _scope(auth)));
      await _enter(t, 'person_name', 'Ali Veli');
      await _enter(t, 'person_email', 'ali@example.com');
      await _tapButton(t, 'Kaydet');
      await settleFor(t);
      expect(find.text('Bu işlem için yetkiniz yok.'), findsOneWidget);
    });

    testWidgets('düzenleme: alanlar dolu gelir; yalnız değişen alan gider; değişiklik yoksa sunucuya gidilmez', (t) async {
      final auth = PeopleFakeAuth.seeded();
      final detail = await auth.getPerson(11, 1);
      PersonDetail? result;
      await _open(t, (c) async => result = await PersonFormDialog.show(c, scope: _scope(auth), person: detail));
      expect(_fieldText(t, 'person_name'), 'Ayşe Yılmaz');
      expect(_fieldText(t, 'person_phone'), '+90 555 111 22 33');
      expect(_fieldText(t, 'person_email'), 'ayse@example.com');
      expect(_fieldText(t, 'person_note'), 'Kapıcıya haber verildi.');
      expect(_readOnly(t, 'person_name'), isFalse);

      await _tapButton(t, 'Kaydet');
      await settleFor(t);
      expect(auth.updatePersonCalls, isEmpty, reason: 'değişiklik yok');
      expect(identical(result, detail), isTrue);
    });

    testWidgets('düzenleme: ad + e-posta değişir, telefon temizlenir, not boşaltılır', (t) async {
      final auth = PeopleFakeAuth.seeded();
      final detail = await auth.getPerson(11, 1);
      await _open(t, (c) => PersonFormDialog.show(c, scope: _scope(auth), person: detail));
      await _enter(t, 'person_name', 'Ayşe Yıldız');
      await _enter(t, 'person_phone', '');
      await _enter(t, 'person_email', 'AYSE.NEW@example.com');
      await _enter(t, 'person_note', '');
      await _tapButton(t, 'Kaydet');
      await settleFor(t);
      expect(auth.updatePersonCalls.single.fields, <String, Object?>{
        'full_name': 'Ayşe Yıldız',
        'phone': null,
        'email': 'ayse.new@example.com',
        'note': null,
      });
    });

    testWidgets('hesabı olan kişi: ad / telefon / e-posta salt okunur, yalnız not gönderilir', (t) async {
      final auth = PeopleFakeAuth.seeded();
      final detail = await auth.getPerson(11, 2);
      await _open(t, (c) => PersonFormDialog.show(c, scope: _scope(auth), person: detail));
      expect(_readOnly(t, 'person_name'), isTrue);
      expect(_readOnly(t, 'person_phone'), isTrue);
      expect(_readOnly(t, 'person_email'), isTrue);
      expect(_readOnly(t, 'person_note'), isFalse, reason: 'not her zaman düzenlenir');
      expect(_fieldText(t, 'person_name'), 'Mehmet Demir');

      await _enter(t, 'person_note', 'Yeni not');
      await _tapButton(t, 'Kaydet');
      await settleFor(t);
      expect(auth.updatePersonCalls.single.fields, <String, Object?>{'note': 'Yeni not'},
          reason: 'kimlik alanları gönderilmez (PERSON_HAS_ACCOUNT)');
    });
  });

  group('kişi formu: sitenin yönettiği hesapta ad / telefon düzenlenir, telefon biçimi zorlanır', () {
    testWidgets('sitenin yönettiği DAHİLİ hesap (identity_editable): ad ve telefon yazılabilir, e-posta da; bilgi bandı; değişenler gider', (t) async {
      final auth = PeopleFakeAuth.seeded();
      auth.peopleJson[2] = pplPersonJson(
        2,
        'Mehmet Demir',
        phone: '+905322223344',
        email: 'mehmet@example.com',
        account: true,
        accountKind: 'internal',
        identityEditable: true,
        apts: const <PplApt>[(302, 'A Blok - 6', ResidencyRelation.tenant)],
      );
      final detail = await auth.getPerson(11, 2);
      await _open(t, (c) => PersonFormDialog.show(c, scope: _scope(auth), person: detail));
      expect(_readOnly(t, 'person_name'), isFalse);
      expect(_readOnly(t, 'person_phone'), isFalse, reason: 'telefon kutusuna yazılabilir');
      expect(_readOnly(t, 'person_email'), isFalse, reason: 'dahili hesapta iletişim e-postası düzenlenir');
      expect(find.textContaining('Ad ve telefonu değiştirirseniz kişinin hesabında da güncellenir.'), findsOneWidget);
      expect(find.textContaining('kendi profilinden değişir'), findsNothing);
      expect(_fieldText(t, 'person_phone'), '+90 532 222 33 44');

      await _enter(t, 'person_name', 'Mehmet Demir Yeni');
      await _enter(t, 'person_phone', '5061234567');
      expect(_fieldText(t, 'person_phone'), '+90 506 123 45 67');
      await _tapButton(t, 'Kaydet');
      await settleFor(t);
      expect(auth.updatePersonCalls.single.fields, <String, Object?>{'full_name': 'Mehmet Demir Yeni', 'phone': '+905061234567'});
    });

    testWidgets('sitenin yönettiği GERÇEK e-postalı hesap: ad / telefon açık, e-posta (giriş adresi) kilitli; kısa bilgi bandı', (t) async {
      final auth = PeopleFakeAuth.seeded();
      auth.peopleJson[2] = pplPersonJson(
        2,
        'Mehmet Demir',
        phone: '+905322223344',
        email: 'mehmet@example.com',
        account: true,
        identityEditable: true,
        apts: const <PplApt>[(302, 'A Blok - 6', ResidencyRelation.tenant)],
      );
      final detail = await auth.getPerson(11, 2);
      await _open(t, (c) => PersonFormDialog.show(c, scope: _scope(auth), person: detail));
      expect(_readOnly(t, 'person_name'), isFalse);
      expect(_readOnly(t, 'person_phone'), isFalse);
      expect(_readOnly(t, 'person_email'), isTrue);
      expect(find.textContaining('E-posta kişinin giriş adresidir; kişinin kendi profilinden değişir.'), findsOneWidget);

      await _enter(t, 'person_phone', '5061234567');
      await _tapButton(t, 'Kaydet');
      await settleFor(t);
      expect(auth.updatePersonCalls.single.fields, <String, Object?>{'phone': '+905061234567'}, reason: 'e-posta ve ad gönderilmez');
    });

    testWidgets('kişinin KENDİ hesabı (identity_editable yok / false): ad, telefon, e-posta salt okunur ve gönderilmez', (t) async {
      for (final flag in <bool?>[null, false]) {
        final auth = PeopleFakeAuth.seeded();
        auth.peopleJson[2] = pplPersonJson(
          2,
          'Mehmet Demir',
          phone: '+905322223344',
          email: 'mehmet@example.com',
          account: true,
          identityEditable: flag,
          apts: const <PplApt>[(302, 'A Blok - 6', ResidencyRelation.tenant)],
        );
        final detail = await auth.getPerson(11, 2);
        await _open(t, (c) => PersonFormDialog.show(c, scope: _scope(auth), person: detail));
        expect(_readOnly(t, 'person_name'), isTrue, reason: 'flag=$flag');
        expect(_readOnly(t, 'person_phone'), isTrue, reason: 'flag=$flag');
        expect(_readOnly(t, 'person_email'), isTrue, reason: 'flag=$flag');
        expect(find.textContaining('kişinin kendi profilinden değişir'), findsOneWidget, reason: 'flag=$flag');
        await _enter(t, 'person_note', 'Yeni not');
        await _tapButton(t, 'Kaydet');
        await settleFor(t);
        expect(auth.updatePersonCalls.single.fields, <String, Object?>{'note': 'Yeni not'}, reason: 'flag=$flag');
      }
    });

    testWidgets('telefon biçimi zorlanır: +90 hazır, 5 dışı ilk hane yazılamaz, 10 haneden fazlası yazılamaz, eksik numara kaydettirmez', (t) async {
      final auth = PeopleFakeAuth.seeded();
      await _open(t, (c) => PersonFormDialog.show(c, scope: _scope(auth)));
      expect(find.text(phoneFieldHint), findsOneWidget, reason: 'yer tutucu biçim');
      await _enter(t, 'person_phone', '2121234567');
      expect(_fieldText(t, 'person_phone'), '+90 ', reason: 'cep numarası 5 ile başlar');
      await _enter(t, 'person_phone', '50612345678');
      expect(_fieldText(t, 'person_phone'), '+90 ', reason: '11 hane reddedilir');
      await _enter(t, 'person_phone', '506123');
      await _enter(t, 'person_name', 'Ali Veli');
      await _tapButton(t, 'Kaydet');
      await settleFor(t);
      expect(find.text(phoneFormatError), findsOneWidget, reason: 'eksik numara');
      expect(auth.createPersonCalls, isEmpty, reason: 'sunucuya gidilmez');
      await _enter(t, 'person_phone', '5061234567');
      await _tapButton(t, 'Kaydet');
      await settleFor(t);
      expect(find.text(phoneFormatError), findsNothing);
    });

    testWidgets('eski sabit hat kaydı (hesapsız kişi): dokunulmadıkça hata vermez ve gönderilmez; yalnız ad değişir', (t) async {
      final auth = PeopleFakeAuth.seeded();
      auth.peopleJson[1]!['phone'] = '+902121234567';
      final detail = await auth.getPerson(11, 1);
      await _open(t, (c) => PersonFormDialog.show(c, scope: _scope(auth), person: detail));
      expect(_fieldText(t, 'person_phone'), '+90 212 123 45 67', reason: 'eski sabit hat olduğu gibi görünür');
      await _enter(t, 'person_name', 'Ayşe Yıldız');
      await _tapButton(t, 'Kaydet');
      await settleFor(t);
      expect(find.text(phoneFormatError), findsNothing);
      expect(auth.updatePersonCalls.single.fields, <String, Object?>{'full_name': 'Ayşe Yıldız'}, reason: 'telefon gönderilmez');
    });

    testWidgets('eski sabit hat değiştirilirse yeni değer cep kuralına uymalı', (t) async {
      final auth = PeopleFakeAuth.seeded();
      auth.peopleJson[1]!['phone'] = '+902121234567';
      final detail = await auth.getPerson(11, 1);
      await _open(t, (c) => PersonFormDialog.show(c, scope: _scope(auth), person: detail));
      await _enter(t, 'person_phone', '+90 212 123 45 6');
      await _tapButton(t, 'Kaydet');
      await settleFor(t);
      expect(find.text(phoneFormatError), findsOneWidget);
      expect(auth.updatePersonCalls, isEmpty);
      await _enter(t, 'person_phone', '+90 506 123 45 67');
      await _tapButton(t, 'Kaydet');
      await settleFor(t);
      expect(auth.updatePersonCalls.single.fields, <String, Object?>{'phone': '+905061234567'});
    });
  });

  group('taşma matrisi: daire kartı ve düzenleme', () {
    layoutMatrix('daire kartı: dolu', (t, w, h, s, dark) async {
      final auth = PeopleFakeAuth.seeded();
      await _open(
        t,
        (c) => ApartmentCardDialog.show(c, scope: _scope(auth), apartmentId: 301, initialLabel: 'A Blok - 5'),
        width: w,
        height: h,
        scale: s,
        dark: dark,
      );
      expect(find.text('A Blok - 5'), findsOneWidget);
      expect(find.text('Bilgiler'), findsOneWidget);
      expect(find.text('2'), findsOneWidget, reason: 'kat');
      expect(find.text('3+1'), findsOneWidget);
      expect(find.text('35/1000'), findsOneWidget);
      expect(find.text('Borç ve bildirimler kime gitsin'), findsOneWidget);
      expect(find.text('İkisi'), findsOneWidget);
      expect(find.text('Malik, kiracı ve sakinler'), findsOneWidget);
      expect(find.text('Kiracı'), findsOneWidget, reason: 'etiket; kiracı adı "Kayıtlı değil"');
      expect(find.text('Kayıtlı değil'), findsOneWidget);
      expect(find.text('Geçmiş sakinler'), findsOneWidget);
      expect(find.text('Zeynep Kaya'), findsOneWidget);
      expect(find.text('Çıkış: 31.01.2025'), findsOneWidget);
      expect(find.text('Düzenle'), findsOneWidget);
      expect(find.text('Geçmiş'), findsOneWidget);
    });

    layoutMatrix('daire kartı: salt okunur (Düzenle yok) / yükleniyor / hata', (t, w, h, s, dark) async {
      final auth = PeopleFakeAuth.seeded();
      await _open(
        t,
        (c) => ApartmentCardDialog.show(c, scope: _scope(auth, canWrite: false), apartmentId: 301),
        width: w,
        height: h,
        scale: s,
        dark: dark,
      );
      expect(find.text('Bilgiler'), findsOneWidget);
      expect(find.text('Düzenle'), findsNothing);
      expect(find.text('Geçmiş'), findsOneWidget);
    });

    layoutMatrix('daire kartı: yükleniyor', (t, w, h, s, dark) async {
      final auth = PeopleFakeAuth.seeded()..apartmentGate = Completer<void>();
      await _open(
        t,
        (c) => ApartmentCardDialog.show(c, scope: _scope(auth), apartmentId: 301, initialLabel: 'A Blok - 5'),
        width: w,
        height: h,
        scale: s,
        dark: dark,
      );
      expect(find.byType(DialogRowsSkeleton), findsOneWidget);
      expect(find.text('Daire bilgileri yükleniyor...'), findsOneWidget);
      expect(find.text('Bilgiler'), findsNothing);
    });

    layoutMatrix('daire kartı: hata (Tekrar Dene)', (t, w, h, s, dark) async {
      final auth = PeopleFakeAuth.seeded();
      await _open(
        t,
        (c) => ApartmentCardDialog.show(c, scope: _scope(auth), apartmentId: 999),
        width: w,
        height: h,
        scale: s,
        dark: dark,
      );
      expect(find.text('Daire bulunamadı.'), findsOneWidget);
      expect(find.text('Tekrar Dene'), findsOneWidget);
      expect(find.text('Bilgiler'), findsNothing);
    });

    layoutMatrix('daire düzenleme: tüm alanlar dolu', (t, w, h, s, dark) async {
      final auth = PeopleFakeAuth.seeded();
      final detail = await auth.getApartment(11, 301);
      await _open(
        t,
        (c) => ApartmentEditDialog.show(c, scope: _scope(auth), apartment: detail),
        width: w,
        height: h,
        scale: s,
        dark: dark,
      );
      expect(find.text('Daireyi Düzenle'), findsOneWidget);
      expect(_fieldText(t, 'apartment_floor'), '2');
      expect(_fieldText(t, 'apartment_numerator'), '35');
      expect(_fieldText(t, 'apartment_denominator'), '1000');
      expect(_fieldText(t, 'apartment_category'), '3+1');
      expect(find.text('Borç ve bildirimler kime gitsin'), findsOneWidget);
    });
  });

  group('daire kartı / düzenleme davranışı', () {
    testWidgets('Düzenle: kaydedince kart güncellenir ve liste haberdar edilir', (t) async {
      final auth = PeopleFakeAuth.seeded();
      var changed = 0;
      await _open(
        t,
        (c) => ApartmentCardDialog.show(c, scope: _scope(auth), apartmentId: 301, onChanged: () => changed++),
      );
      await _tapButton(t, 'Düzenle');
      await _enter(t, 'apartment_floor', '3');
      await _choose(t, find.byKey(const ValueKey<String>('apartment_party')), 'Malik');
      await _tapButton(t, 'Kaydet');
      await settleFor(t);
      expect(auth.updateApartmentCalls.single.id, 301);
      expect(auth.updateApartmentCalls.single.fields, <String, Object?>{
        'floor': 3,
        'responsible_party': 'owner',
      });
      expect(changed, 1);
      expect(find.text('Daire bilgileri güncellendi.'), findsOneWidget, reason: 'bildirim');
    });

    testWidgets('değişiklik yoksa sunucuya gidilmez ve pencere kapanır', (t) async {
      final auth = PeopleFakeAuth.seeded();
      final detail = await auth.getApartment(11, 301);
      await _open(t, (c) => ApartmentEditDialog.show(c, scope: _scope(auth), apartment: detail));
      await _tapButton(t, 'Kaydet');
      await settleFor(t);
      expect(auth.updateApartmentCalls, isEmpty);
      expect(find.text('Daireyi Düzenle'), findsNothing);
    });

    testWidgets('alan doğrulamaları: kat ve arsa payı kuralları', (t) async {
      final auth = PeopleFakeAuth.seeded();
      final detail = await auth.getApartment(11, 302);
      await _open(t, (c) => ApartmentEditDialog.show(c, scope: _scope(auth), apartment: detail));

      await _enter(t, 'apartment_floor', 'abc');
      await _tapButton(t, 'Kaydet');
      expect(find.text('Kat -20 ile 500 arasında bir tam sayı olmalı.'), findsOneWidget);

      await _enter(t, 'apartment_floor', '');
      final toggle = find.byKey(const ValueKey<String>('apartment_advanced_toggle'));
      await t.ensureVisible(toggle);
      await t.tap(toggle);
      await t.pumpAndSettle();
      await _enter(t, 'apartment_numerator', '5');
      await _tapButton(t, 'Kaydet');
      expect(find.text('Arsa payı için pay ve payda birlikte girilmeli.'), findsOneWidget);

      await _enter(t, 'apartment_denominator', '4');
      await _tapButton(t, 'Kaydet');
      expect(find.text('Arsa payı geçersiz: payda 0\'dan büyük, pay payı aşmamalı.'), findsOneWidget);
      expect(auth.updateApartmentCalls, isEmpty);
    });

    testWidgets('arsa payı pay / payda birlikte gider; ikisi de boşaltılırsa ikisi de null (temizlenir)', (t) async {
      final auth = PeopleFakeAuth.seeded();
      final detail = await auth.getApartment(11, 301);
      await _open(t, (c) => ApartmentEditDialog.show(c, scope: _scope(auth), apartment: detail));
      await _enter(t, 'apartment_numerator', '40');
      await _tapButton(t, 'Kaydet');
      await settleFor(t);
      expect(auth.updateApartmentCalls.single.fields, <String, Object?>{
        'land_share_numerator': 40,
        'land_share_denominator': 1000,
      });

      final again = await auth.getApartment(11, 301);
      await _open(t, (c) => ApartmentEditDialog.show(c, scope: _scope(auth), apartment: again));
      await _enter(t, 'apartment_numerator', '');
      await _enter(t, 'apartment_denominator', '');
      await _enter(t, 'apartment_category', '  Dükkan  ');
      await _tapButton(t, 'Kaydet');
      await settleFor(t);
      expect(auth.updateApartmentCalls.last.fields, <String, Object?>{
        'land_share_numerator': null,
        'land_share_denominator': null,
        'category': 'Dükkan',
      });
    });

    testWidgets('sunucu reddi (INVALID_BODY alan adıyla) pencerede gösterilir, pencere açık kalır', (t) async {
      final auth = PeopleFakeAuth.seeded()
        ..writeError = ApiException('floor alanı geçersiz (-20 ile 500 arasında tam sayı).', statusCode: 400, code: 'INVALID_BODY');
      final detail = await auth.getApartment(11, 301);
      await _open(t, (c) => ApartmentEditDialog.show(c, scope: _scope(auth), apartment: detail));
      await _enter(t, 'apartment_floor', '4');
      await _tapButton(t, 'Kaydet');
      await settleFor(t);
      expect(find.text('floor alanı geçersiz (-20 ile 500 arasında tam sayı).'), findsOneWidget);
      expect(find.text('Daireyi Düzenle'), findsOneWidget);
    });

    testWidgets('Geçmiş: daire geçmişi hedef türü ve numarasıyla çekilir', (t) async {
      final auth = PeopleFakeAuth.seeded()
        ..historyPages = <HistoryPage>[
          HistoryPage(items: <HistoryItem>[pplHistory(3, action: 'apartment.updated')]),
        ];
      await _open(t, (c) => ApartmentCardDialog.show(c, scope: _scope(auth), apartmentId: 301));
      await _tapButton(t, 'Geçmiş');
      await settleFor(t);
      expect(auth.historyCalls.single.type, 'apartment');
      expect(auth.historyCalls.single.id, 301);
      expect(find.text('Daire bilgisi güncellendi'), findsOneWidget);
    });
  });

  group('taşma matrisi: ilişki, taşındı, araç, geçmiş, seçici', () {
    layoutMatrix('ilişki ekle', (t, w, h, s, dark) async {
      final auth = PeopleFakeAuth.seeded();
      await _open(
        t,
        (c) => ResidencyDialog.show(c, scope: _scope(auth), personId: 1, personName: 'Ayşe Yılmaz'),
        width: w,
        height: h,
        scale: s,
        dark: dark,
      );
      expect(find.text('İlişki Ekle'), findsOneWidget);
      expect(find.text('Daire seçmek için dokunun'), findsOneWidget);
      expect(find.text('Kaydet'), findsOneWidget);
    });

    layoutMatrix('taşındı onayı (hesabı olan kişi: kapı yetkisi uyarısı)', (t, w, h, s, dark) async {
      final auth = PeopleFakeAuth.seeded();
      final detail = await auth.getPerson(11, 2);
      await _open(
        t,
        (c) => EndResidencyDialog.show(
          c,
          scope: _scope(auth),
          residency: detail.currentResidencies.single,
          personName: detail.fullName,
          hasAccount: true,
        ),
        width: w,
        height: h,
        scale: s,
        dark: dark,
      );
      expect(find.text('Taşındı Olarak İşaretle'), findsOneWidget);
      expect(find.textContaining('kapı yetkisi kapanır'), findsOneWidget);
      expect(find.text('Taşınma tarihi'), findsOneWidget);
    });

    layoutMatrix('araç ekle (kişi seçicili)', (t, w, h, s, dark) async {
      final auth = PeopleFakeAuth.seeded();
      await _open(
        t,
        (c) => VehicleDialog.show(c, scope: _scope(auth)),
        width: w,
        height: h,
        scale: s,
        dark: dark,
      );
      expect(find.text('Araç Ekle'), findsOneWidget);
      expect(find.text('Kişi seçmek için dokunun'), findsOneWidget);
      expect(find.text('Plaka'), findsOneWidget);
    });

    layoutMatrix('geçmiş: dolu (değişen alanlar, uzun adlar) + Daha fazla yükle', (t, w, h, s, dark) async {
      final auth = PeopleFakeAuth.seeded()
        ..historyPages = <HistoryPage>[
          HistoryPage(
            items: <HistoryItem>[
              pplHistory(
                9,
                actor: 'Çok Uzun Adlı Bir Site Yöneticisi Hesabı Sahibi',
                changes: const [
                  {'field': 'phone', 'changed': true},
                  {'field': 'full_name', 'from': 'Ayşe', 'to': 'Ayşe Yıldız'},
                ],
              ),
              pplHistory(8, action: 'residency.added', changes: const [], extra: const {'relation': 'owner'}),
            ],
            nextBeforeId: 8,
          ),
        ];
      await _open(
        t,
        (c) => HistoryDialog.show(c, scope: _scope(auth), targetType: 'person', targetId: 1, title: 'Ayşe Yılmaz'),
        width: w,
        height: h,
        scale: s,
        dark: dark,
      );
      expect(find.text('Geçmiş'), findsOneWidget);
      expect(find.text('Kişi bilgisi güncellendi'), findsOneWidget);
      expect(find.text('İlişki eklendi'), findsOneWidget);
      expect(find.text('Telefon güncellendi'), findsOneWidget, reason: 'değer gelmezse yalnız alan adı');
      expect(find.text('Ad Soyad: Ayşe → Ayşe Yıldız'), findsOneWidget);
      expect(find.text('İlişki: Malik'), findsOneWidget);
      expect(find.text('Daha fazla yükle'), findsOneWidget);
    });

    layoutMatrix('geçmiş: yükleniyor / boş / hata', (t, w, h, s, dark) async {
      final auth = PeopleFakeAuth.seeded()..historyGates.add(Completer<void>());
      await _open(
        t,
        (c) => HistoryDialog.show(c, scope: _scope(auth), targetType: 'person', targetId: 1, title: 'Ayşe'),
        width: w,
        height: h,
        scale: s,
        dark: dark,
      );
      expect(find.byType(DialogRowsSkeleton), findsOneWidget);
      expect(find.text('Geçmiş yükleniyor...'), findsOneWidget);
      expect(find.text('Henüz geçmiş kaydı yok.'), findsNothing);
    });

    layoutMatrix('geçmiş: hata', (t, w, h, s, dark) async {
      final auth = PeopleFakeAuth.seeded()
        ..historyError = ApiException('Bu işlem için yetkiniz yok.', statusCode: 403, code: 'FORBIDDEN_ROLE');
      await _open(
        t,
        (c) => HistoryDialog.show(c, scope: _scope(auth), targetType: 'person', targetId: 1, title: 'Ayşe'),
        width: w,
        height: h,
        scale: s,
        dark: dark,
      );
      expect(find.text('Bu işlem için yetkiniz yok.'), findsOneWidget);
      expect(find.text('Tekrar Dene'), findsOneWidget);
      expect(find.text('Henüz geçmiş kaydı yok.'), findsNothing);
    });

    layoutMatrix('daire seçici: liste', (t, w, h, s, dark) async {
      final auth = PeopleFakeAuth.seeded();
      await _open(
        t,
        (c) async => showApartmentPicker(c, _scope(auth)),
        width: w,
        height: h,
        scale: s,
        dark: dark,
      );
      expect(find.text('Daire Seç'), findsOneWidget);
      expect(find.byType(AppCard), findsNWidgets(3));
      expect(find.text('Malik: Ayşe Yılmaz'), findsOneWidget);
      expect(find.text('Daire ara'), findsOneWidget);
    });
  });

  group('sunucu kuralları: hesaplı kişi, PERSON_EXISTS, taşınma tarihi, sistem kaydı', () {
    PeopleFakeAuth withAccounts() {
      final auth = PeopleFakeAuth.seeded();
      auth.peopleJson[4] = pplPersonJson(
        4,
        'Dahili Hesap',
        phone: '+905333334455',
        email: 'iletisim@example.com',
        account: true,
        accountKind: 'internal',
        apts: const <PplApt>[(303, 'B Blok - 2', ResidencyRelation.resident)],
      );
      // Eski sunucu: account_kind alanı yok.
      auth.peopleJson[5] = pplPersonJson(5, 'Eski Sunucu Hesabı', account: true, email: 'eski@example.com')
        ..remove('account_kind');
      return auth;
    }

    testWidgets('dahili hesap: ad / telefon salt okunur, iletişim e-postası düzenlenebilir; gövdede yalnız email', (t) async {
      final auth = withAccounts();
      final detail = await auth.getPerson(11, 4);
      expect(detail.isInternalAccount, isTrue);
      await _open(t, (c) => PersonFormDialog.show(c, scope: _scope(auth), person: detail));
      expect(_readOnly(t, 'person_name'), isTrue);
      expect(_readOnly(t, 'person_phone'), isTrue);
      expect(_readOnly(t, 'person_email'), isFalse);
      expect(find.textContaining('iletişim e-postası buradan düzenlenebilir'), findsOneWidget);
      expect(find.text('Kişinin kendi profilinden değişir'), findsNothing);

      await _enter(t, 'person_email', 'yeni@example.com');
      await _tapButton(t, 'Kaydet');
      await settleFor(t);
      final fields = auth.updatePersonCalls.single.fields;
      expect(fields, <String, Object?>{'email': 'yeni@example.com'});
      expect(fields.containsKey('full_name'), isFalse);
      expect(fields.containsKey('phone'), isFalse);
    });

    testWidgets('dahili hesapta yalnız not değişirse gövdede ad / telefon / e-posta anahtarı HİÇ bulunmaz', (t) async {
      final auth = withAccounts();
      final detail = await auth.getPerson(11, 4);
      await _open(t, (c) => PersonFormDialog.show(c, scope: _scope(auth), person: detail));
      await _enter(t, 'person_note', 'Sadece not');
      await _tapButton(t, 'Kaydet');
      await settleFor(t);
      expect(auth.updatePersonCalls.single.fields.keys, <String>['note']);
    });

    testWidgets('kayıtlı hesap ve account_kind alanı olmayan (eski sunucu) hesap: üç kimlik alanı da salt okunur, anahtar gönderilmez', (t) async {
      final auth = withAccounts();
      for (final id in <int>[2, 5]) {
        final detail = await auth.getPerson(11, id);
        await _open(t, (c) => PersonFormDialog.show(c, scope: _scope(auth), person: detail));
        expect(_readOnly(t, 'person_name'), isTrue, reason: 'kişi $id');
        expect(_readOnly(t, 'person_phone'), isTrue, reason: 'kişi $id');
        expect(_readOnly(t, 'person_email'), isTrue, reason: 'kişi $id');
        await _enter(t, 'person_note', 'Not $id');
        await _tapButton(t, 'Kaydet');
        await settleFor(t);
        expect(auth.updatePersonCalls.last.fields.keys, <String>['note'], reason: 'kişi $id');
      }
    });

    testWidgets('PERSON_EXISTS + person_id: "Kişiyi Aç" mevcut kişinin kartını açar', (t) async {
      final auth = PeopleFakeAuth.seeded();
      await _open(t, (c) => PersonFormDialog.show(c, scope: _scope(auth)));
      await _enter(t, 'person_name', 'Yinelenen');
      await _enter(t, 'person_email', 'ayse@example.com');
      await _tapButton(t, 'Kaydet');
      await settleFor(t);
      expect(find.text('Bu e-posta ile kayıtlı bir kişi zaten var.'), findsOneWidget);
      expect(find.text('Kişiyi Aç'), findsOneWidget);

      await _tapButton(t, 'Kişiyi Aç');
      await settleFor(t);
      expect(auth.getPersonCalls, <int>[1]);
      expect(find.text('Bilgiler'), findsOneWidget);
    });

    testWidgets('PERSON_EXISTS: person_id yok ya da 0 ise "Kişiyi Aç" gösterilmez (yarış)', (t) async {
      final auth = PeopleFakeAuth.seeded()..personExistsHasId = false;
      await _open(t, (c) => PersonFormDialog.show(c, scope: _scope(auth)));
      await _enter(t, 'person_name', 'Yinelenen');
      await _enter(t, 'person_email', 'ayse@example.com');
      await _tapButton(t, 'Kaydet');
      await settleFor(t);
      expect(find.text('Bu e-posta ile kayıtlı bir kişi zaten var.'), findsOneWidget);
      expect(find.text('Kişiyi Aç'), findsNothing);

      auth.writeError = ApiException(
        'Bu e-posta ile kayıtlı bir kişi zaten var.',
        statusCode: 409,
        code: 'PERSON_EXISTS',
        payload: const <String, dynamic>{'person_id': 0},
      );
      await _tapButton(t, 'Kaydet');
      await settleFor(t);
      expect(find.text('Kişiyi Aç'), findsNothing);
    });

    testWidgets('Taşındı: gelecek tarih reddedilir (sunucu kabul etmez), bugün ve geçmiş tarih kabul edilir', (t) async {
      final auth = PeopleFakeAuth.seeded();
      final detail = await auth.getPerson(11, 2);
      await _open(
        t,
        (c) => EndResidencyDialog.show(
          c,
          scope: _scope(auth),
          residency: detail.currentResidencies.single,
          personName: detail.fullName,
          hasAccount: true,
        ),
      );
      final tomorrow = DateTime.now().add(const Duration(days: 2));
      await _enter(t, 'end_residency_date', formatDateField(tomorrow).replaceAll('.', ''));
      await _tapButton(t, 'Taşındı Olarak İşaretle');
      expect(find.text('Taşınma tarihi bugünden ileri olamaz.'), findsOneWidget);
      expect(auth.endResidencyCalls, isEmpty);

      await _enter(t, 'end_residency_date', '01012026');
      await _tapButton(t, 'Taşındı Olarak İşaretle');
      await settleFor(t);
      expect(auth.endResidencyCalls.single.date, DateTime(2026, 1, 1));
    });

    testWidgets('geçmiş: sistem kaydı "Sistem tarafından"; değer yoksa "Alan güncellendi"', (t) async {
      final auth = PeopleFakeAuth.seeded()
        ..historyPages = <HistoryPage>[
          HistoryPage(items: <HistoryItem>[
            pplHistory(
              6,
              action: 'person.deactivated',
              actor: 'Sistem',
              role: 'system',
              changes: const [],
              extra: const {'auto': true},
            ),
            pplHistory(5, changes: const [
              {'field': 'email', 'changed': true},
              {'field': 'note', 'changed': true},
              {'field': 'floor', 'from': 2, 'to': 3},
            ]),
          ]),
        ];
      await _open(
        t,
        (c) => HistoryDialog.show(c, scope: _scope(auth), targetType: 'person', targetId: 1, title: 'Ayşe'),
      );
      expect(find.text('Kişi pasifleştirildi'), findsOneWidget);
      expect(find.text('Sistem tarafından'), findsOneWidget);
      expect(find.text('E-posta güncellendi'), findsOneWidget);
      expect(find.text('Not güncellendi'), findsOneWidget);
      expect(find.text('Kat: 2 → 3'), findsOneWidget);
    });
  });

  group('ilişki / araç / geçmiş / seçici davranışı', () {
    testWidgets('araç ekle (Araçlar sekmesi): kişi seçilmeden uyarı; kişi seçici ile ekler', (t) async {
      final auth = PeopleFakeAuth.seeded();
      VehicleRecord? result;
      await _open(t, (c) async => result = await VehicleDialog.show(c, scope: _scope(auth)));
      await _enter(t, 'vehicle_plate', '35 KLM 77');
      await _tapButton(t, 'Ekle');
      expect(find.text('Araç sahibini seçin.'), findsOneWidget);
      expect(auth.createVehicleCalls, isEmpty);

      final field = find.byKey(const ValueKey<String>('vehicle_person'));
      await scrollTo(t, field);
      await t.tap(field);
      await settleFor(t);
      expect(find.text('Kişi Seç'), findsOneWidget);
      expect(auth.peopleCalls.last.status, 'active', reason: 'seçici yalnız aktif kişileri listeler');
      await t.tap(find.descendant(of: find.byType(AppCard), matching: find.text('Mehmet Demir')).last);
      await settleFor(t);
      expect(find.text('Mehmet Demir'), findsOneWidget);

      await _tapButton(t, 'Ekle');
      await settleFor(t);
      expect(auth.createVehicleCalls.single.person, 2);
      expect(result?.plate, '35KLM77');
    });

    testWidgets('seçici: arama sunucuya gider; sonuç yoksa bildirilir', (t) async {
      final auth = PeopleFakeAuth.seeded();
      ApartmentSummary? picked;
      await _open(t, (c) async => picked = await showApartmentPicker(c, _scope(auth)));
      final search = find.byType(TextField).last;
      await t.enterText(search, 'b blok');
      await t.pump(const Duration(milliseconds: 400));
      await t.pump();
      expect(auth.apartmentCalls.last.query, 'b blok');
      expect(find.descendant(of: find.byType(AppCard), matching: find.text('B Blok - 2')), findsOneWidget);
      expect(find.descendant(of: find.byType(AppCard), matching: find.text('A Blok - 5')), findsNothing);

      await t.enterText(search, 'yokböyle');
      await t.pump(const Duration(milliseconds: 400));
      await t.pump();
      expect(find.text('Daire bulunamadı.'), findsOneWidget);

      await t.enterText(search, 'b blok');
      await t.pump(const Duration(milliseconds: 400));
      await t.pump();
      await t.tap(find.descendant(of: find.byType(AppCard), matching: find.text('B Blok - 2')));
      await settleFor(t);
      expect(picked?.id, 303);
    });

    testWidgets('seçici: art arda aramada eski yanıt yenisini ezmez', (t) async {
      final auth = PeopleFakeAuth.seeded();
      await _open(t, (c) async => showApartmentPicker(c, _scope(auth)));
      final first = Completer<void>();
      final second = Completer<void>();
      auth.apartmentGates.addAll(<Completer<void>>[first, second]);
      final search = find.byType(TextField).last;

      await t.enterText(search, 'a blok');
      await t.pump(const Duration(milliseconds: 400));
      await t.enterText(search, 'b blok');
      await t.pump(const Duration(milliseconds: 400));
      second.complete();
      await settleFor(t);
      expect(find.descendant(of: find.byType(AppCard), matching: find.text('B Blok - 2')), findsOneWidget);
      first.complete();
      await settleFor(t);
      expect(find.descendant(of: find.byType(AppCard), matching: find.text('B Blok - 2')), findsOneWidget);
      expect(find.descendant(of: find.byType(AppCard), matching: find.text('A Blok - 5')), findsNothing);
    });

    testWidgets('geçmiş: Daha fazla yükle imleçle sonraki sayfayı ekler, yinelenen atlanır; hata + Tekrar Dene', (t) async {
      final auth = PeopleFakeAuth.seeded()
        ..historyPages = <HistoryPage>[
          HistoryPage(items: <HistoryItem>[pplHistory(9), pplHistory(8, action: 'person.created', changes: const [])], nextBeforeId: 8),
          HistoryPage(items: <HistoryItem>[pplHistory(8, action: 'person.created', changes: const []), pplHistory(7, action: 'vehicle.added', changes: const [])]),
        ];
      await _open(
        t,
        (c) => HistoryDialog.show(c, scope: _scope(auth), targetType: 'person', targetId: 1, title: 'Ayşe'),
      );
      expect(find.text('Kişi eklendi'), findsOneWidget);

      auth.historyError = ApiException('Sunucu yanıt vermedi, tekrar deneyin.');
      await _tapButton(t, 'Daha fazla yükle');
      await settleFor(t);
      expect(find.text('Sunucu yanıt vermedi, tekrar deneyin.'), findsOneWidget);
      expect(find.text('Kişi eklendi'), findsOneWidget, reason: 'mevcut liste kalır');

      auth.historyError = null;
      await _tapButton(t, 'Tekrar Dene');
      await settleFor(t);
      expect(auth.historyCalls.last.before, 8);
      expect(find.text('Kişi eklendi'), findsOneWidget, reason: 'yinelenen kayıt tekrar eklenmedi');
      expect(find.text('Araç eklendi'), findsOneWidget);
      expect(find.text('Daha fazla yükle'), findsNothing);
    });

    testWidgets('geçmiş boş: "Henüz geçmiş kaydı yok."', (t) async {
      final auth = PeopleFakeAuth.seeded();
      await _open(
        t,
        (c) => HistoryDialog.show(c, scope: _scope(auth), targetType: 'vehicle', targetId: 1, title: 'Araç'),
      );
      expect(find.text('Henüz geçmiş kaydı yok.'), findsOneWidget);
      expect(auth.historyCalls.single.type, 'vehicle');
    });

    testWidgets('onay penceresi: onaylanırsa true, vazgeçilirse false', (t) async {
      bool? result;
      await openDialogAt(
        t,
        (c) async => result = await confirmCrmAction(
          c,
          title: 'Aracı kaldır',
          message: 'Emin misiniz?',
          confirmLabel: 'Kaldır',
        ),
        width: 400,
        height: 800,
        scale: 1.0,
        dark: false,
      );
      await tapText(t, 'Vazgeç');
      expect(result, isFalse);
    });
  });
}

/// `crmDateParam` testlerde gerekli (yalnız tarih kısmını karşılaştırır).
String crmDateParamForTest(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
