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
  String? leftoverEmail,
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
  residentEmail: resident ? email : leftoverEmail,
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
  bool isSuperUser = false,
}) async {
  await pumpList(
    t,
    ApartmentCard(
      apartment: apartment,
      onEdit: () {},
      onResetPin: onResetPin,
      resettingPin: resetting,
      isSuperUser: isSuperUser,
      onDelete: () {},
    ),
    width: width,
    height: height,
    scale: scale,
    dark: dark,
  );
  await tapText(t, apartment.label);
}

const String _mail = 'sakin.cok.uzun.eposta.adresi@ornek-alan-adi.com';

ApartmentPinIssue _issue({bool? sent = true, String? email = _mail}) => ApartmentPinIssue(
  apartment: _apartment(),
  pinCode: '4821',
  credentialsSent: sent,
  credentialsEmail: email,
);

OutlinedButton _resetButton(WidgetTester t) => t.widget<OutlinedButton>(
  find.ancestor(of: find.text("PIN'i Sıfırla"), matching: find.byType(OutlinedButton)),
);

void main() {
  group('ApartmentCard: PIN yalnız durum olarak; değer hiç yazılmaz', () {
    _matrix('daire hesabı (PIN verildi, sıfırlanabilir)', (t, w, h, s, dark) async {
      await _pumpCard(t, _apartment(pinCode: '9876'), width: w, height: h, scale: s, dark: dark, onResetPin: () {});
      expect(find.text('Şifre (PIN): yönetim verdi'), findsOneWidget);
      expect(find.text(kApartmentPinOnceNotice), findsOneWidget);
      expect(find.text("PIN'i Sıfırla"), findsOneWidget);
      expect(_resetButton(t).onPressed, isNotNull);
      // Model yanlışlıkla PIN taşısa bile satır PIN'i YAZMAZ; eski "Bilgileri Gönder" yok.
      expect(find.textContaining('9876'), findsNothing);
      expect(find.text('Bilgileri Gönder'), findsNothing);
    });

    _matrix('sakin kendi şifresini belirlemiş, YÖNETİCİ görünümü: düğme devre dışı + yalnız süper açıklaması', (t, w, h, s, dark) async {
      await _pumpCard(t, _apartment(issued: false), width: w, height: h, scale: s, dark: dark, onResetPin: () {});
      expect(find.text('Şifre (PIN): sakin kendisi belirledi'), findsOneWidget);
      expect(find.text(kApartmentPinNeedsSuper), findsOneWidget);
      expect(find.text(kApartmentPinOnceNotice), findsNothing);
      expect(_resetButton(t).onPressed, isNull, reason: 'yönetici sıfırlayamaz (sunucu 409 NEEDS_SUPER)');
    });

    testWidgets('sakin kendi şifresini belirlemiş, SÜPER kullanıcı: düğme etkin, "bir kez gösterilir" notu', (t) async {
      var calls = 0;
      await _pumpCard(t, _apartment(issued: false), onResetPin: () => calls += 1, isSuperUser: true);
      expect(find.text(kApartmentPinNeedsSuper), findsNothing);
      expect(find.text(kApartmentPinOnceNotice), findsOneWidget);
      await tapText(t, "PIN'i Sıfırla");
      expect(calls, 1);
    });

    testWidgets('kayıtlı (kendi hesabıyla giren) sakin: PIN satırı, not ve sıfırlama düğmesi YOK', (t) async {
      await _pumpCard(t, _apartment(issued: false, resettable: false), onResetPin: () {});
      expect(find.textContaining('Şifre (PIN)'), findsNothing);
      expect(find.text(kApartmentPinOnceNotice), findsNothing);
      expect(find.text(kApartmentPinNeedsSuper), findsNothing);
      expect(find.text("PIN'i Sıfırla"), findsNothing);
      expect(t.takeException(), isNull);
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
      expect(_resetButton(t).onPressed, isNull);
      expect(t.takeException(), isNull);
    });

    testWidgets('sakinsiz daire: PIN ile ilgili hiçbir şey yok', (t) async {
      await _pumpCard(t, _apartment(resident: false), onResetPin: () {});
      expect(find.textContaining('PIN'), findsNothing);
    });
  });

  group('ApartmentPinIssuedDialog: yeni PIN bir kez', () {
    // (ad, kayıt, beklenen gönderim iletisi)
    final scenarios = <(String, ApartmentPinIssue, String)>[
      ('gönderildi + hedef adres', _issue(), 'PIN $_mail adresine bir kez gönderildi.'),
      ('gönderim sürüyor (yanıt beklemedi)', _issue(sent: null), 'PIN $_mail adresine gönderiliyor. $kApartmentPinMailPending'),
      ('gönderilemedi', _issue(sent: false), "E-posta ($_mail) gönderilemedi. PIN'i sakine kendiniz iletin."),
    ];
    for (final (name, issue, mail) in scenarios) {
      _matrix(name, (t, w, h, s, dark) async {
        await openDialogAt(
          t,
          (context) => ApartmentPinIssuedDialog.show(context, issue),
          width: w,
          height: h,
          scale: s,
          dark: dark,
        );
        expect(find.text("Daire PIN'i"), findsOneWidget);
        expect(find.text('4821'), findsOneWidget);
        expect(find.text('Kopyala'), findsOneWidget);
        expect(find.text('5899864115_a_blok_daire12'), findsOneWidget);
        expect(find.textContaining('yalnız şimdi gösterilir'), findsOneWidget);
        expect(find.text(mail), findsOneWidget);
        await scrollTo(t, find.text('Tamam'));
        expect(t.takeException(), isNull);
      });
    }

    test('gönderim iletileri: adres yoksa elden iletme; "yeniden sıfırlayın" yalnız gönderim sürerken (PIN ekranda)', () {
      expect(
        ApartmentPinIssuedDialog.mailStatus(_issue(sent: null, email: null)).$2,
        "Sakinin e-posta adresi yok. PIN'i sakine kendiniz iletin.",
      );
      expect(ApartmentPinIssuedDialog.mailStatus(_issue(sent: false)).$2, isNot(contains('yeniden sıfırlayın')));
      expect(ApartmentPinIssuedDialog.mailStatus(_issue(sent: true)).$2, isNot(contains('gösterilmez')));
    });

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

  group('confirmApartmentPinReset (role göre metin)', () {
    _matrix('yönetici, yönetimin verdiği PIN: "Yeni PIN size bir kez gösterilir" + e-posta', (t, w, h, s, dark) async {
      await openDialogAt(
        t,
        (context) => confirmApartmentPinReset(context, apartment: _apartment(), isSuper: false),
        width: w,
        height: h,
        scale: s,
        dark: dark,
      );
      expect(find.text('PIN sıfırlansın mı?'), findsOneWidget);
      expect(find.textContaining('Eski şifre artık çalışmaz'), findsOneWidget);
      expect(find.textContaining('Yeni PIN size bir kez gösterilir ve sakinin e-posta adresine ($_mail) de gönderilir.'), findsOneWidget);
      expect(find.textContaining('misafir geçişleri ve karekodlar kapanır'), findsOneWidget);
      await scrollTo(t, find.text('Sıfırla'));
      expect(find.text('Vazgeç'), findsOneWidget);
    });

    _matrix('süper kullanıcı, sakinin kendi şifresi: uyarı + "Yeni PIN size bir kez gösterilir"', (t, w, h, s, dark) async {
      await openDialogAt(
        t,
        (context) => confirmApartmentPinReset(context, apartment: _apartment(issued: false, email: null), isSuper: true),
        width: w,
        height: h,
        scale: s,
        dark: dark,
      );
      expect(find.textContaining('süper kullanıcı olarak onun şifresinin yerine yeni PIN veriyorsunuz'), findsOneWidget);
      expect(find.textContaining('Yeni PIN size bir kez gösterilir.'), findsOneWidget);
      await scrollTo(t, find.text('Sıfırla'));
    });

    testWidgets('onay true, vazgeç false; yönetici + sakinin kendi şifresi: pencere AÇILMAZ (false)', (t) async {
      bool? result;
      await openDialogAt(
        t,
        (context) async => result = await confirmApartmentPinReset(context, apartment: _apartment(email: null), isSuper: false),
        width: 360,
        height: 900,
        scale: 1.0,
        dark: false,
      );
      expect(find.textContaining('Yeni PIN size bir kez gösterilir.'), findsOneWidget);
      await tapText(t, 'Sıfırla');
      await settleFor(t);
      expect(result, isTrue);

      await openDialogAt(
        t,
        (context) async => result = await confirmApartmentPinReset(context, apartment: _apartment(), isSuper: false),
        width: 360,
        height: 900,
        scale: 1.0,
        dark: false,
      );
      await tapFinder(t, find.text('Vazgeç'));
      await settleFor(t);
      expect(result, isFalse);

      result = null;
      await openDialogAt(
        t,
        (context) async => result = await confirmApartmentPinReset(context, apartment: _apartment(issued: false), isSuper: false),
        width: 360,
        height: 900,
        scale: 1.0,
        dark: false,
      );
      expect(find.text('PIN sıfırlansın mı?'), findsNothing);
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

    testWidgets('yeni sakin: dairede kalmış ESKİ e-posta ön doldurulmaz (PIN eski sakine gitmesin)', (t) async {
      await openDialogAt(
        t,
        (context) => ApartmentResidentDialog.show(
          context,
          apartment: _apartment(resident: false, leftoverEmail: 'eski.sakin@example.com'),
        ),
        width: 360,
        height: 1000,
        scale: 1.0,
        dark: false,
      );
      final emailField = t.widget<TextFormField>(find.widgetWithText(TextFormField, 'Daire Sakini E-postası'));
      expect(emailField.controller!.text, isEmpty);
      expect(find.text('eski.sakin@example.com'), findsNothing);
    });

    testWidgets('mevcut sakin düzenlemesi: kayıtlı e-posta dolu gelir', (t) async {
      await openDialogAt(
        t,
        (context) => ApartmentResidentDialog.show(context, apartment: _apartment()),
        width: 360,
        height: 1000,
        scale: 1.0,
        dark: false,
      );
      final emailField = t.widget<TextFormField>(find.widgetWithText(TextFormField, 'Daire Sakini E-postası'));
      expect(emailField.controller!.text, _mail);
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

    test('ApartmentPinIssue.fromResponse: hedef adres; gönderim sürüyor (null + adres); PIN yoksa null (yalnız-e-posta modu YOK)', () {
      final apt = ApartmentRecord.fromJson({'id': 1, 'site_code': 2, 'block_id': 3});
      final pending = ApartmentPinIssue.fromResponse(apt, {'pin_code': '1357', 'credentials_sent': null, 'credentials_email': ' a@b.co '});
      expect(pending!.pinCode, '1357');
      expect(pending.credentialsSent, isNull);
      expect(pending.credentialsEmail, 'a@b.co');
      expect(ApartmentPinIssue.fromResponse(apt, {'pin_code': null, 'pin_delivery': 'email_only', 'credentials_sent': true}), isNull);
      expect(ApartmentPinIssue.fromResponse(apt, {'credentials_email': ''}), isNull);
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
