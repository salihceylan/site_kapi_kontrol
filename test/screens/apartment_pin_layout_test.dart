// Daire PIN'i (KVKK m.12, migration 051): sunucu PIN'i saklamaz; liste PIN taşımaz. Daire satırı yalnız "PIN verildi" durumunu,
// "PIN yalnız oluşturulurken bir kez gösterilir; unutulduysa yenileyin." notunu ve yetkili role "PIN'i Sıfırla" düğmesini gösterir;
// yeni PIN yalnız oluşturma / sıfırlama anında bir kez (ApartmentPinIssuedDialog) görünür.
//
// AGENTS.md kural 6 taşma matrisi: 320x640 x2,0, 360x640 x1,5, 640x360 x2,0, 768x1024 x1,0; açık + koyu tema.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/apartment_pin_issue.dart';
import 'package:site_kapi_kontrol/models/apartment_record.dart';
import 'package:site_kapi_kontrol/ui/dialogs/apartment_pin_dialogs.dart';
import 'package:site_kapi_kontrol/ui/dialogs/apartment_resident_dialog.dart';
import 'package:site_kapi_kontrol/ui/widgets/apartment_card.dart';

import '../design/harness.dart';
import 'dialog_layout_harness.dart' show openDialogAt, settleFor, scrollTo;
import 'list_fixtures.dart' show pumpList, tapText, tapFinder;

const List<(double, double, double)> _cells = <(double, double, double)>[
  (320, 640, 2.0),
  (360, 640, 1.5),
  (640, 360, 2.0),
  (768, 1024, 1.0),
];

void _matrix(
  String name,
  Future<void> Function(WidgetTester t, double w, double h, double s, bool dark) body,
) {
  for (final (w, h, s) in _cells) {
    for (final dark in const <bool>[false, true]) {
      testWidgets('$name: ${w.toInt()}x${h.toInt()} x$s ${dark ? 'koyu' : 'açık'} tema, taşma yok', (t) async {
        await body(t, w, h, s, dark);
        expect(t.takeException(), isNull);
      });
    }
  }
}

ApartmentRecord _apartment({
  bool resident = true,
  bool issued = true,
  bool resettable = true,
  String? email = 'sakin.cok.uzun.eposta.adresi@ornek-alan-adi.com',
  String? pinCode,
}) => ApartmentRecord(
  id: 7,
  siteCode: 5899864115,
  blockId: 1,
  blockName: 'A Blok',
  unitLabel: 'Daire 12',
  sortOrder: 12,
  isActive: true,
  residentUserCode: resident ? 4012 : null,
  residentFullName: resident ? 'Sakin Adı Soyadı Uzun Bir İsim' : null,
  residentLoginName: resident ? '5899864115_a_blok_daire12' : null,
  residentEmail: resident ? email : null,
  residentPinCode: pinCode,
  residentPhoneNumber: null,
  residentIsActive: resident ? true : null,
  createdAt: DateTime(2026, 1, 1),
  residentPinIssued: issued,
  residentPinResettable: resettable,
);

Future<void> _pumpCard(
  WidgetTester t,
  ApartmentRecord apartment, {
  double width = 360,
  double height = 900,
  double scale = 1.0,
  bool dark = false,
  VoidCallback? onResetPin,
  bool resetting = false,
}) async {
  await pumpList(
    t,
    ApartmentCard(
      apartment: apartment,
      onEdit: () {},
      onResetPin: onResetPin,
      resettingPin: resetting,
      onDelete: () {},
    ),
    width: width,
    height: height,
    scale: scale,
    dark: dark,
  );
  await tapText(t, apartment.label);
}

ApartmentPinIssue _issue({bool? sent = true}) => ApartmentPinIssue(
  apartment: _apartment(),
  pinCode: '4821',
  credentialsSent: sent,
);

void main() {
  group('ApartmentCard: PIN yalnız durum olarak; değer hiç yazılmaz', () {
    _matrix('daire hesabı (PIN verildi, sıfırlanabilir)', (t, w, h, s, dark) async {
      await _pumpCard(t, _apartment(pinCode: '9876'), width: w, height: h, scale: s, dark: dark, onResetPin: () {});
      expect(find.text('Şifre (PIN): yönetim verdi'), findsOneWidget);
      expect(find.text(kApartmentPinOnceNotice), findsOneWidget);
      expect(find.text("PIN'i Sıfırla"), findsOneWidget);
      // Model yanlışlıkla PIN taşısa bile satır PIN'i YAZMAZ; eski "Bilgileri Gönder" yok.
      expect(find.textContaining('9876'), findsNothing);
      expect(find.text('Bilgileri Gönder'), findsNothing);
    });

    testWidgets('kayıtlı (kendi hesabıyla giren) sakin: PIN satırı, not ve sıfırlama düğmesi YOK', (t) async {
      await _pumpCard(t, _apartment(issued: false, resettable: false), onResetPin: () {});
      expect(find.textContaining('Şifre (PIN)'), findsNothing);
      expect(find.text(kApartmentPinOnceNotice), findsNothing);
      expect(find.text("PIN'i Sıfırla"), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('daire hesabı ama sakin kendi parolasını belirledi: durum yazılır, sıfırlama yine mümkün', (t) async {
      await _pumpCard(t, _apartment(issued: false), onResetPin: () {});
      expect(find.text('Şifre (PIN): sakin kendisi belirledi'), findsOneWidget);
      expect(find.text("PIN'i Sıfırla"), findsOneWidget);
    });

    testWidgets('yetkisiz görünüm (onResetPin yok): not görünür, düğme yok', (t) async {
      await _pumpCard(t, _apartment());
      expect(find.text(kApartmentPinOnceNotice), findsOneWidget);
      expect(find.text("PIN'i Sıfırla"), findsNothing);
    });

    testWidgets('"PIN\'i Sıfırla" geri çağrıyı çağırır; sıfırlanırken devre dışı', (t) async {
      var calls = 0;
      await _pumpCard(t, _apartment(), onResetPin: () => calls += 1);
      await tapText(t, "PIN'i Sıfırla");
      expect(calls, 1);

      await _pumpCard(t, _apartment(), onResetPin: () => calls += 1, resetting: true);
      final button = t.widget<OutlinedButton>(
        find.ancestor(of: find.text("PIN'i Sıfırla"), matching: find.byType(OutlinedButton)),
      );
      expect(button.onPressed, isNull);
      expect(t.takeException(), isNull);
    });

    testWidgets('sakinsiz daire: PIN ile ilgili hiçbir şey yok', (t) async {
      await _pumpCard(t, _apartment(resident: false), onResetPin: () {});
      expect(find.textContaining('PIN'), findsNothing);
    });
  });

  group('ApartmentPinIssuedDialog: yeni PIN bir kez', () {
    for (final sent in const <bool?>[true, false, null]) {
      _matrix('e-posta durumu $sent', (t, w, h, s, dark) async {
        await openDialogAt(
          t,
          (context) => ApartmentPinIssuedDialog.show(context, _issue(sent: sent)),
          width: w,
          height: h,
          scale: s,
          dark: dark,
        );
        expect(find.text("Daire PIN'i"), findsOneWidget);
        expect(find.text('4821'), findsOneWidget);
        expect(find.text('5899864115_a_blok_daire12'), findsOneWidget);
        expect(find.textContaining('yalnız şimdi gösterilir'), findsOneWidget);
        final mail = switch (sent) {
          true => 'PIN sakinin e-posta adresine bir kez gönderildi.',
          false => "E-posta gönderilemedi. PIN'i sakine kendiniz iletin.",
          null => "Sakinin e-posta adresi yok. PIN'i sakine kendiniz iletin.",
        };
        expect(find.text(mail), findsOneWidget);
        await scrollTo(t, find.text('Tamam'));
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('Kopyala panoya PIN\'i yazar ("Kopyalandı"); dışarı dokunmak kapatmaz; Tamam kapatır', (t) async {
      String? copied;
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      });
      addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await openDialogAt(
        t,
        (context) => ApartmentPinIssuedDialog.show(context, _issue()),
        width: 360,
        height: 900,
        scale: 1.0,
        dark: false,
      );
      await tapText(t, 'Kopyala');
      expect(copied, '4821');
      expect(find.text('Kopyalandı'), findsOneWidget);

      await t.tapAt(const Offset(5, 5));
      await settleFor(t);
      expect(find.text("Daire PIN'i"), findsOneWidget, reason: 'barrierDismissible: false');

      await tapText(t, 'Tamam');
      await settleFor(t);
      expect(find.text("Daire PIN'i"), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('ekran okuyucu PIN\'i hane hane okur', (t) async {
      final handle = t.ensureSemantics();
      await openDialogAt(
        t,
        (context) => ApartmentPinIssuedDialog.show(context, _issue()),
        width: 360,
        height: 900,
        scale: 1.0,
        dark: false,
      );
      expect(find.bySemanticsLabel('PIN 4 8 2 1'), findsOneWidget);
      handle.dispose();
    });
  });

  group('confirmApartmentPinReset', () {
    _matrix('onay penceresi', (t, w, h, s, dark) async {
      await openDialogAt(
        t,
        (context) => confirmApartmentPinReset(context, apartment: _apartment()),
        width: w,
        height: h,
        scale: s,
        dark: dark,
      );
      expect(find.text('PIN sıfırlansın mı?'), findsOneWidget);
      expect(find.textContaining('Eski PIN artık çalışmaz'), findsOneWidget);
      expect(find.textContaining('e-posta adresine de gönderilir'), findsOneWidget);
      await scrollTo(t, find.text('Sıfırla'));
      expect(find.text('Vazgeç'), findsOneWidget);
    });

    testWidgets('onay true, vazgeç false; e-postasız dairede yalnız ekranda bir kez', (t) async {
      bool? result;
      await openDialogAt(
        t,
        (context) async => result = await confirmApartmentPinReset(context, apartment: _apartment(email: null)),
        width: 360,
        height: 900,
        scale: 1.0,
        dark: false,
      );
      expect(find.textContaining('Yeni PIN yalnız ekranda bir kez gösterilir.'), findsOneWidget);
      await tapText(t, 'Sıfırla');
      await settleFor(t);
      expect(result, isTrue);

      await openDialogAt(
        t,
        (context) async => result = await confirmApartmentPinReset(context, apartment: _apartment()),
        width: 360,
        height: 900,
        scale: 1.0,
        dark: false,
      );
      await tapFinder(t, find.text('Vazgeç'));
      await settleFor(t);
      expect(result, isFalse);
    });
  });

  group('ApartmentResidentDialog: PIN alanı hiçbir zaman eski PIN ile dolmaz', () {
    testWidgets('yeni sakin: PIN alanı boş, "saklanmaz" notu ve e-posta notu görünür', (t) async {
      await openDialogAt(
        t,
        (context) => ApartmentResidentDialog.show(context, apartment: _apartment(resident: false, pinCode: '5555')),
        width: 360,
        height: 1000,
        scale: 1.0,
        dark: false,
      );
      final pinField = t.widget<TextFormField>(find.widgetWithText(TextFormField, 'İlk Giriş Şifresi / PIN'));
      expect(pinField.controller!.text, isEmpty);
      expect(find.text('Güvenlik gereği saklanmaz; kayıttan sonra yalnız bir kez gösterilir.'), findsOneWidget);
      expect(find.text('Opsiyonel. Girilirse PIN bu adrese bir kez gönderilir.'), findsOneWidget);
    });

    testWidgets('daire hesabı düzenleme: "PIN\'i Sıfırla" yönlendirmesi', (t) async {
      await openDialogAt(
        t,
        (context) => ApartmentResidentDialog.show(context, apartment: _apartment()),
        width: 360,
        height: 1000,
        scale: 1.0,
        dark: false,
      );
      expect(find.textContaining('"PIN\'i Sıfırla" ile yenilenir'), findsOneWidget);
      expect(find.text('Opsiyonel. PIN sıfırlanınca yeni PIN bu adrese gönderilir.'), findsOneWidget);
    });
  });

  group('modeller', () {
    test('ApartmentRecord: eski sunucu (alan yok) -> işaretler false; yeni alanlar okunur', () {
      final base = <String, dynamic>{'id': 1, 'site_code': 2, 'block_id': 3};
      final old = ApartmentRecord.fromJson({...base, 'resident_pin_code': null});
      expect(old.residentPinIssued, isFalse);
      expect(old.residentPinResettable, isFalse);
      final fresh = ApartmentRecord.fromJson({...base, 'resident_pin_issued': true, 'resident_pin_resettable': true});
      expect(fresh.residentPinIssued, isTrue);
      expect(fresh.residentPinResettable, isTrue);
    });

    test('ApartmentPinIssue.fromResponse: pin_code ya da apartment.resident_pin_code; yoksa null; credentials_sent', () {
      final withPin = ApartmentRecord.fromJson({'id': 1, 'site_code': 2, 'block_id': 3, 'resident_pin_code': '6047'});
      final without = ApartmentRecord.fromJson({'id': 1, 'site_code': 2, 'block_id': 3});
      final created = ApartmentPinIssue.fromResponse(withPin, {'credentials_sent': true});
      expect(created!.pinCode, '6047');
      expect(created.credentialsSent, isTrue);
      final reset = ApartmentPinIssue.fromResponse(without, {'pin_code': ' 1357 ', 'credentials_sent': null});
      expect(reset!.pinCode, '1357');
      expect(reset.credentialsSent, isNull);
      expect(ApartmentPinIssue.fromResponse(without, {'credentials_sent': true}), isNull, reason: 'mevcut sakin düzenlemesi');
      expect(ApartmentPinIssue.fromResponse(without, {'pin_code': '2468', 'credentials_sent': 'evet'})!.credentialsSent, isNull);
    });

    test('kimlik bilgisi PDF\'i PIN sütunu / alanı İÇERMEZ (kaynak koruması)', () {
      final source = File('lib/services/pdf_credentials_service.dart').readAsStringSync();
      expect(source.contains('residentPinCode'), isFalse);
      expect(source.contains("'Şifre / PIN'"), isFalse);
      final tree = File('lib/models/site_residents_tree_record.dart').readAsStringSync();
      expect(tree.contains('resident_pin_code'), isFalse);
    });
  });
}
