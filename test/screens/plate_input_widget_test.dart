// Plaka girişi pencerelerde (ui/helpers/plate_input.dart): Araç Ekle penceresi ve Kişi formunun plaka alanı.
//
// Kapsam: yazarken "34 ABC 123" gruplama, plakaya götürmeyen girişin reddi, eksik plakada sunucu iletisiyle aynı hata, ESKİ kayıtlı
// (Türk plakası kuralına uymayan) plakaların düzenlemede bozulmaması / pasife alınmaması.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/person_record.dart';
import 'package:site_kapi_kontrol/ui/dialogs/person_form_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/vehicle_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';

import 'dialog_layout_harness.dart';
import 'people_fixtures.dart';

PeopleScope _scope(PeopleFakeAuth auth) => PeopleScope(authService: auth, siteCode: 11, siteName: 'Gül Sitesi', canWrite: true);

Future<void> _open(WidgetTester t, Future<void> Function(BuildContext context) opener) async {
  await openDialogAt(t, opener, width: 400, height: 900, scale: 1.0, dark: false);
  await settleFor(t);
}

Finder _field(String key) => find.byKey(ValueKey<String>(key)).last;

String _text(WidgetTester t, String key) => t
    .widget<EditableText>(find.descendant(of: _field(key), matching: find.byType(EditableText)))
    .controller
    .text;

Future<void> _enter(WidgetTester t, String key, String text) async {
  await scrollTo(t, _field(key));
  await t.enterText(_field(key), text);
  await t.pump();
}

Future<void> _tap(WidgetTester t, String label) async {
  await scrollTo(t, find.text(label).last);
  await t.tap(find.text(label).last);
  await t.pump();
  await t.pump(const Duration(milliseconds: 450));
}

/// Kişi 5: Türk plakası olmayan ESKİ kayıtlı plaka (eskiden 5-10 harf / rakam yeterdi) + geçerli bir plaka.
PeopleFakeAuth _withLegacy() {
  final auth = PeopleFakeAuth.seeded();
  final vehicles = <Map<String, dynamic>>[
    pplVehicleJson(7, 'ABC 12345', person: 'Eski Kayıt', personId: 5),
    pplVehicleJson(8, '35 DD 4567', person: 'Eski Kayıt', personId: 5),
  ];
  auth.peopleJson[5] = pplPersonJson(5, 'Eski Kayıt', email: 'eski@example.com', vehicles: vehicles);
  auth.vehiclesJson.addAll(vehicles);
  return auth;
}

void main() {
  group('Araç Ekle penceresi', () {
    testWidgets('yazarken gruplanır; gönderilen plaka "34 ABC 123"', (t) async {
      final auth = PeopleFakeAuth.seeded();
      await _open(t, (c) => VehicleDialog.show(c, scope: _scope(auth), person: PersonSummary.fromJson(const <String, dynamic>{'id': 1, 'full_name': 'Ayşe Yılmaz'})));
      await _enter(t, 'vehicle_plate', '06xy789');
      expect(_text(t, 'vehicle_plate'), '06 XY 789');
      await _tap(t, 'Ekle');
      await settleFor(t);
      expect(auth.createVehicleCalls.single.plate, '06 XY 789');
    });

    testWidgets('plakaya götürmeyen giriş yazılamaz; eksik plaka sunucu iletisiyle reddedilir ve gönderilmez', (t) async {
      final auth = PeopleFakeAuth.seeded();
      await _open(t, (c) => VehicleDialog.show(c, scope: _scope(auth), person: PersonSummary.fromJson(const <String, dynamic>{'id': 1, 'full_name': 'Ayşe Yılmaz'})));
      await _enter(t, 'vehicle_plate', '99 zz 1');
      expect(_text(t, 'vehicle_plate'), '', reason: 'il kodu 99: yazılmaz');
      await _enter(t, 'vehicle_plate', '34 abcd');
      expect(_text(t, 'vehicle_plate'), '', reason: '4. harf: bütün giriş reddedilir, alan önceki değerinde kalır');
      await _enter(t, 'vehicle_plate', '34 a 1');
      expect(_text(t, 'vehicle_plate'), '34 A 1');
      await _tap(t, 'Ekle');
      expect(find.text(kPlateInvalidMessage), findsOneWidget);
      expect(auth.createVehicleCalls, isEmpty);
      final field = t.widget<TextField>(find.descendant(of: _field('vehicle_plate'), matching: find.byType(TextField)));
      expect(field.autocorrect, isFalse);
      expect(field.enableSuggestions, isFalse);
      expect(field.textCapitalization, TextCapitalization.characters);
    });
  });

  group('Kişi formu: plaka alanı', () {
    testWidgets('yeni kişi: virgülle ayrılmış plakalar gruplanır ve her biri biçimli gönderilir', (t) async {
      final auth = PeopleFakeAuth.seeded();
      await _open(t, (c) => PersonFormDialog.show(c, scope: _scope(auth)));
      await _enter(t, 'person_name', 'Yeni Kişi');
      await _enter(t, 'person_email', 'yeni@example.com');
      await _enter(t, 'person_plates', '34abc123;06 xy 789');
      expect(_text(t, 'person_plates'), '34 ABC 123, 06 XY 789');
      await _tap(t, 'Kaydet');
      await settleFor(t);
      expect(auth.createVehicleCalls.map((c) => c.plate), <String>['34 ABC 123', '06 XY 789']);
    });

    testWidgets('eksik plaka: tek ileti geçersiz plakayı adıyla söyler ve hiçbir şey kaydedilmez', (t) async {
      final auth = PeopleFakeAuth.seeded();
      await _open(t, (c) => PersonFormDialog.show(c, scope: _scope(auth)));
      await _enter(t, 'person_name', 'Yeni Kişi');
      await _enter(t, 'person_email', 'yeni@example.com');
      await _enter(t, 'person_plates', '34 ABC 123, 06 x 1');
      await _tap(t, 'Kaydet');
      expect(find.text('Plaka biçimi geçersiz: 06 X 1. Örnek: 34 ABC 123 (il kodu 01-81).'), findsOneWidget);
      expect(auth.createPersonCalls, isEmpty);
      expect(auth.createVehicleCalls, isEmpty);
    });

    testWidgets('eski kayıtlı plaka: alan dolu gelir, değişmeden Kaydet engellenmez ve plaka pasife alınmaz', (t) async {
      final auth = _withLegacy();
      final detail = await auth.getPerson(11, 5);
      await _open(t, (c) => PersonFormDialog.show(c, scope: _scope(auth), person: detail));
      expect(_text(t, 'person_plates'), 'ABC 12345, 35 DD 4567');
      await _tap(t, 'Kaydet');
      await settleFor(t);
      expect(find.textContaining('Plaka biçimi geçersiz'), findsNothing);
      expect(auth.createVehicleCalls, isEmpty);
      expect(auth.removeVehicleCalls, isEmpty, reason: 'eski plaka alandan silinmedikçe pasife alınmaz');
    });

    testWidgets('eski kayıtlı plakanın yanına yeni plaka eklenir; eski plaka korunur; yeni plaka kurala uymalı', (t) async {
      final auth = _withLegacy();
      final detail = await auth.getPerson(11, 5);
      await _open(t, (c) => PersonFormDialog.show(c, scope: _scope(auth), person: detail));
      await _enter(t, 'person_plates', 'ABC 12345, 35 DD 4567, 06 def 456');
      expect(_text(t, 'person_plates'), 'ABC 12345, 35 DD 4567, 06 DEF 456');
      await _tap(t, 'Kaydet');
      await settleFor(t);
      expect(auth.createVehicleCalls.map((c) => c.plate), <String>['06 DEF 456'], reason: 'yalnız yeni plaka sunucuya gider');
      expect(auth.removeVehicleCalls, isEmpty);
    });

    testWidgets('eski kayıtlı plaka alandan silinirse pasife alınır; yenisi eski biçimde yazılamaz', (t) async {
      final auth = _withLegacy();
      final detail = await auth.getPerson(11, 5);
      await _open(t, (c) => PersonFormDialog.show(c, scope: _scope(auth), person: detail));
      // eskisini silip eski biçimde yeni bir değer yazmak: kayıtlı olmayan 5-10 harf / rakam artık yazılamaz
      await _enter(t, 'person_plates', 'ABC 12345, 35 DD 4567, XYZ98765');
      expect(_text(t, 'person_plates'), 'ABC 12345, 35 DD 4567');
      await _enter(t, 'person_plates', '35 DD 4567');
      await _tap(t, 'Kaydet');
      await settleFor(t);
      expect(auth.removeVehicleCalls, <int>[7]);
      expect(auth.createVehicleCalls, isEmpty);
    });

    testWidgets('kayıtta 5 plakadan çok araç varsa değişmemiş alan kaydı engellemez ve hiçbirini pasife almaz', (t) async {
      final auth = PeopleFakeAuth.seeded();
      final vehicles = <Map<String, dynamic>>[
        for (var i = 0; i < 6; i++) pplVehicleJson(20 + i, '${11 * (i + 1)} AAA ${11 * (i + 1)}', person: 'Çok Araçlı', personId: 6),
      ];
      auth.peopleJson[6] = pplPersonJson(6, 'Çok Araçlı', email: 'cok@example.com', vehicles: vehicles);
      auth.vehiclesJson.addAll(vehicles);
      final detail = await auth.getPerson(11, 6);
      await _open(t, (c) => PersonFormDialog.show(c, scope: _scope(auth), person: detail));
      await _tap(t, 'Kaydet');
      await settleFor(t);
      expect(find.textContaining('En çok'), findsNothing);
      expect(auth.removeVehicleCalls, isEmpty, reason: 'ayrıştırılamayan alan boş sayılıp tüm plakalar pasife alınmamalı');
      expect(auth.createVehicleCalls, isEmpty);
    });
  });
}
