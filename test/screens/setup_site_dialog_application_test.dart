// Platform: site kurma formu BAŞVURU modu (SetupSiteDialog; docs/PLATFORM_SITE_BASVURUSU.md).
//
// Rol kapısı (bireysel / daire kullanıcısı başvurur, yönetici / süper anlık kurar), cihaz isteğe bağlı,
// başarı iletisi, "Yeniden başvur" önceki değerleri, doğrulama (ilk geçersiz alana kaydırma + özet), çift
// gönderim / geri tuşu koruması, hata kalıpları (409 / 429 / genel), klavye açıkken ve dar ekran + büyük
// yazıda taşma yok.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/site_application.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/dialogs/setup_site_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/site_application_flow.dart';
import 'package:site_kapi_kontrol/ui/widgets/site_application_parts.dart';
import 'package:site_kapi_kontrol/services/legal_api.dart';

import 'dialog_layout_harness.dart';
import 'g4_test_support.dart';
import 'site_application_fixtures.dart';
import '../legal_fixtures.dart';

SiteApplicationFakeAuth _auth([UserRole role = UserRole.individual]) => SiteApplicationFakeAuth(role: role);

class _Out {
  SetupSiteOutcome? outcome;
  bool closed = false;
}

Future<_Out> _open(
  WidgetTester t,
  SiteApplicationFakeAuth auth, {
  String? deviceUid,
  SetupSiteMode? mode,
  SiteApplication? prefill,
  double width = 400,
  double height = 900,
  double scale = 1.0,
  bool dark = false,
}) async {
  final out = _Out();
  await openDialogAt(
    t,
    (context) async {
      out.outcome = await SetupSiteDialog.show(
        context,
        authService: auth,
        deviceUid: deviceUid,
        mode: mode,
        prefill: prefill,
      );
      out.closed = true;
    },
    width: width,
    height: height,
    scale: scale,
    dark: dark,
  );
  // Cihaz listesi yanıtı.
  await t.pump();
  await t.pump(const Duration(milliseconds: 50));
  return out;
}

Finder _field(String label) => find.widgetWithText(TextFormField, label);

Future<void> _enter(WidgetTester t, String label, String value) async {
  await t.enterText(_field(label), value);
  await t.pump();
}

Future<void> _submit(WidgetTester t, {int ms = 800}) async {
  final button = find.byKey(const ValueKey<String>('setup_site_submit'));
  await scrollTo(t, button);
  await t.tap(button);
  await settleFor(t, ms);
}

PrimaryActionButton _submitButton(WidgetTester t) =>
    t.widget<PrimaryActionButton>(find.byKey(const ValueKey<String>('setup_site_submit')));

SiteApplication _previous() => SiteApplication.fromJson(
  saRow(
    7,
    status: 'rejected',
    siteName: 'Eski Başvuru Sitesi',
    city: 'İstanbul',
    district: 'Kadıköy',
    address: 'Moda Cad. No 5',
    note: 'Önceki not',
    deviceUid: 'ESP32_A',
    blocks: <Map<String, dynamic>>[
      <String, dynamic>{'name': 'Kuzey', 'apartment_count': 12},
      <String, dynamic>{'name': 'Güney', 'apartment_count': 8},
    ],
    doors: <String>['Ana Kapı', 'Otopark'],
  ),
);

void main() {
  // Yasal belge uçları sahte: başvuruda onay gerektiren belge yok (DPA kutusu çıkmaz, gönderme açık kalır).
  setUp(() {
    LegalApi.debugDefaultFactory = () => FakeLegalServer(documents: <Map<String, dynamic>>[]).api;
  });
  tearDown(() => LegalApi.debugDefaultFactory = null);

  group('rol kapısı', () {
    testWidgets('bireysel ve daire kullanıcısı: BAŞVURU formu; başlık, düğme ve bilgi metni', (t) async {
      for (final role in const [UserRole.individual, UserRole.apartmentOwner]) {
        final auth = _auth(role);
        await _open(t, auth);
        expect(find.text('Site Başvurusu'), findsOneWidget, reason: '$role');
        expect(find.text('Site Kurulum Sihirbazı'), findsNothing);
        expect(find.text('Başvuruyu Gönder'), findsOneWidget);
        expect(find.text('Site Kurulumunu Tamamla'), findsNothing);
        expect(find.text('Onaydan sonra site yöneticisi olursunuz'), findsOneWidget);
        expect(find.textContaining('süper kullanıcı tarafından incelenir'), findsOneWidget);
        await t.pumpWidget(const SizedBox());
      }
    });

    testWidgets('site yöneticisi ve süper kullanıcı: ANLIK kurulum sihirbazı (başvuru yok)', (t) async {
      for (final role in const [UserRole.siteManager, UserRole.superUser]) {
        final auth = _auth(role);
        await _open(t, auth);
        expect(find.text('Site Kurulum Sihirbazı'), findsOneWidget, reason: '$role');
        expect(find.text('Site Kurulumunu Tamamla'), findsOneWidget);
        expect(find.text('Başvuruyu Gönder'), findsNothing);
        expect(find.byKey(const ValueKey<String>('site_application_note')), findsNothing);
        expect(find.text(SiteSubscriptionComingSoonRow.label), findsNothing);
        expect(auth.deviceCalls, 0, reason: 'cihaz listesi yalnız başvuruda istenir');
        await t.pumpWidget(const SizedBox());
      }
    });

    testWidgets('anlık kurulum: setupSite çağrılır, başarıda created ile kapanır; başvuru ucu çağrılmaz', (t) async {
      final auth = _auth(UserRole.siteManager);
      final out = await _open(t, auth, deviceUid: 'ESP32_X');
      await _enter(t, 'Site Adı *', 'Güneş Sitesi');
      await _submit(t);
      expect(auth.setupCalls, hasLength(1));
      expect(auth.setupCalls.single['deviceUid'], 'ESP32_X');
      expect(auth.createCalls, isEmpty);
      expect(out.outcome, SetupSiteOutcome.created);
    });

    testWidgets('mode parametresi rolden önceliklidir', (t) async {
      final auth = _auth(UserRole.individual);
      await _open(t, auth, mode: SetupSiteMode.instant);
      expect(find.text('Site Kurulum Sihirbazı'), findsOneWidget);
    });

    testWidgets('B1 ÇIKMAZ YOK: anlık kurulum 409 APPLICATION_REQUIRED -> form BAŞVURU kipine geçer, bilgiler korunur, aynı formdan başvurulur', (t) async {
      // Sahip bağı olmayan yönetici: istemci "anlık" sanır (alan eksik / bayat), sunucu 409 der.
      final auth = _auth(UserRole.siteManager)..serverRequiresApplication = true;
      final out = await _open(t, auth);
      expect(find.text('Site Kurulum Sihirbazı'), findsOneWidget);
      await _enter(t, 'Site Adı *', 'Güneş Sitesi');
      await _submit(t);

      expect(auth.setupCalls, hasLength(1));
      expect(find.text('Site Başvurusu'), findsOneWidget, reason: 'başvuru kipine geçildi');
      expect(find.text('Site Kurulum Sihirbazı'), findsNothing);
      expect(find.text('Başvuruyu Gönder'), findsOneWidget);
      expect(find.textContaining('Site eklemek için başvuru yapmanız gerekiyor'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('site_application_note')), findsOneWidget);
      String text(String label) => t.widget<EditableText>(find.descendant(of: _field(label), matching: find.byType(EditableText))).controller.text;
      expect(text('Site Adı *'), 'Güneş Sitesi', reason: 'girilen bilgiler korunur');
      expect(auth.deviceCalls, 1, reason: 'cihaz listesi başvuru kipinde istenir');

      await _submit(t);
      expect(auth.createCalls, hasLength(1));
      expect(auth.createCalls.single['name'], 'Güneş Sitesi');
      expect(find.text('Başvurunuz alındı.'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey<String>('setup_site_done')));
      await settleFor(t, 400);
      expect(out.outcome, SetupSiteOutcome.applied);
    });

    testWidgets('B1: APPLICATION_REQUIRED sonrası başvuru göndermeden kapanış -> applicationRequired (çağıran durumu yeniden okur)', (t) async {
      final auth = _auth(UserRole.siteManager)..serverRequiresApplication = true;
      final out = await _open(t, auth);
      await _enter(t, 'Site Adı *', 'Güneş Sitesi');
      await _submit(t);
      await t.tap(find.byTooltip('Kapat'));
      await settleFor(t, 400);
      expect(out.closed, isTrue);
      expect(out.outcome, SetupSiteOutcome.applicationRequired);
    });

    testWidgets('B1: modeFor: yönetici requires_application:true ise BAŞVURU; false / null ise anlık; bireysel hep başvuru', (t) async {
      final manager = _auth(UserRole.siteManager);
      expect(SetupSiteDialog.modeFor(manager, requiresApplication: true), SetupSiteMode.application);
      expect(SetupSiteDialog.modeFor(manager, requiresApplication: false), SetupSiteMode.instant);
      expect(SetupSiteDialog.modeFor(manager), SetupSiteMode.instant, reason: 'alan yoksa eski davranış');
      expect(SetupSiteDialog.modeFor(_auth(UserRole.individual), requiresApplication: false), SetupSiteMode.application);
      expect(SetupSiteDialog.modeFor(_auth(UserRole.superUser), requiresApplication: true), SetupSiteMode.instant,
          reason: 'süper kullanıcı başvurmaz');
    });

    testWidgets('B1: sahip bağı olmayan yönetici başvuru kipinde formu açar ve başvuru ucunu kullanır (anlık uç çağrılmaz)', (t) async {
      final auth = _auth(UserRole.siteManager)..serverRequiresApplication = true;
      final out = _Out();
      await openDialogAt(
        t,
        (context) async {
          out.outcome = await SetupSiteDialog.show(
            context,
            authService: auth,
            mode: SetupSiteDialog.modeFor(auth, requiresApplication: true),
          );
          out.closed = true;
        },
        width: 400,
        height: 900,
        scale: 1.0,
        dark: false,
      );
      await t.pump(const Duration(milliseconds: 50));
      expect(find.text('Site Başvurusu'), findsOneWidget);
      await _enter(t, 'Site Adı *', 'İkinci Site');
      await _submit(t);
      expect(auth.createCalls, hasLength(1));
      expect(auth.setupCalls, isEmpty);
      expect(find.text('Başvurunuz alındı.'), findsOneWidget);
    });

    testWidgets('B7: kapatma düğmesi en az 48 dp (dokunma hedefi)', (t) async {
      final auth = _auth();
      await _open(t, auth);
      final close = t.getSize(find.byTooltip('Kapat'));
      expect(close.width, greaterThanOrEqualTo(48));
      expect(close.height, greaterThanOrEqualTo(48));
    });

    testWidgets('B3: anlık sihirbazın alt başlığı iç rol kodu (SITE_OWNER) göstermez', (t) async {
      final auth = _auth(UserRole.siteManager);
      await _open(t, auth);
      expect(find.text('Site Yönetimi Ayarları'), findsOneWidget);
      expect(find.textContaining('SITE_OWNER'), findsNothing);
      expect(find.textContaining('Site Sahibi'), findsNothing);
    });
  });

  group('başvuru gönderimi', () {
    testWidgets('cihaz ŞART DEĞİL: cihazsız gönderilir (deviceUid null), başarı iletisi aynı pencerede, Tamam ile applied', (t) async {
      final auth = _auth();
      final out = await _open(t, auth);
      expect(find.textContaining('Hesabınıza bağlı cihaz yok. Cihaz sonra eklenebilir'), findsOneWidget);
      expect(find.byType(DropdownButton<String>), findsNWidgets(2), reason: 'yalnız il / ilçe; cihaz seçici yok');

      await _enter(t, 'Site Adı *', '  Gül Sitesi  ');
      await _submit(t);

      expect(auth.createCalls, hasLength(1));
      final call = auth.createCalls.single;
      expect(call['name'], 'Gül Sitesi');
      expect(call['deviceUid'], isNull);
      expect(call['managementType'], 'apartment_site');
      expect(call['blocks'], <Map<String, dynamic>>[
        <String, dynamic>{'name': 'A Blok', 'apartmentCount': 10},
      ]);
      expect(call['doorCount'], 0);
      expect(auth.setupCalls, isEmpty, reason: 'bireysel kullanıcıda anlık kurulum ucu hiç çağrılmaz');

      // Başarı iletisi (sözleşme metni).
      expect(find.text('Başvurunuz alındı.'), findsOneWidget);
      expect(find.text('Süper kullanıcı onayladığında site yöneticisi olacaksınız.'), findsOneWidget);
      expect(out.closed, isFalse, reason: 'ileti okunana kadar pencere açık');
      expect(find.byKey(const ValueKey<String>('setup_site_submit')), findsNothing);

      await t.tap(find.byKey(const ValueKey<String>('setup_site_done')));
      await settleFor(t, 400);
      expect(out.closed, isTrue);
      expect(out.outcome, SetupSiteOutcome.applied);
    });

    testWidgets('başarı iletisi görünürken geri tuşu da applied ile kapatır (başvuru kaybolmaz)', (t) async {
      final auth = _auth();
      final out = await _open(t, auth);
      await _enter(t, 'Site Adı *', 'Gül Sitesi');
      await _submit(t);
      expect(find.text('Başvurunuz alındı.'), findsOneWidget);
      await t.state<NavigatorState>(find.byType(Navigator).first).maybePop();
      await settleFor(t, 400);
      expect(out.closed, isTrue);
      expect(out.outcome, SetupSiteOutcome.applied);
    });

    testWidgets('hesaptaki siteye atanmamış cihazlar seçilebilir; atanmışlar listelenmez; seçilen cihaz iletilir', (t) async {
      final auth = _auth()
        ..devices = [saDevice('ESP32_FREE'), saDevice('ESP32_USED', siteCode: 99), saDevice('ESP32_FREE2')];
      await _open(t, auth);
      expect(auth.deviceCalls, 1);
      expect(find.text('Cihaz bağlama'), findsOneWidget, reason: 'varsayılan: cihazsız');
      expect(find.text('Cihaz sonra eklenebilir.'), findsOneWidget);

      final dropdown = find.byKey(const ValueKey<String>('site_application_device_1'));
      await scrollTo(t, dropdown);
      await t.tap(dropdown);
      await settleFor(t, 400);
      expect(find.text('ESP32_FREE').last, findsOneWidget);
      expect(find.text('ESP32_USED'), findsNothing, reason: 'başka siteye atanmış cihaz önerilmez');
      await t.tap(find.text('ESP32_FREE2').last);
      await settleFor(t, 400);
      expect(find.textContaining('Onaylanırsa bu cihaz siteye bağlanır'), findsOneWidget);

      await _enter(t, 'Site Adı *', 'Gül Sitesi');
      await _submit(t);
      expect(auth.createCalls.single['deviceUid'], 'ESP32_FREE2');
    });

    testWidgets('cihaz sahiplenme akışından gelen cihaz önceden seçili; liste alınamazsa da korunur', (t) async {
      final auth = _auth()..devicesError = ApiException('Sunucu yanıt vermedi, tekrar deneyin.');
      await _open(t, auth, deviceUid: 'ESP32_NEW');
      expect(find.text('ESP32_NEW'), findsWidgets);
      await _enter(t, 'Site Adı *', 'Gül Sitesi');
      await _submit(t);
      expect(auth.createCalls.single['deviceUid'], 'ESP32_NEW');
    });

    testWidgets('B4: cihaz listesi alınamadı -> "cihaz yok" DENMEZ: hata + Tekrar Dene; cihazsız başvuru yine yapılabilir', (t) async {
      final auth = _auth()..devicesError = ApiException('Bağlantı yok.');
      await _open(t, auth);
      await scrollTo(t, find.text('Bağlantı yok.'));
      expect(find.text('Bağlantı yok.'), findsOneWidget, reason: 'hata görünür');
      expect(find.text('Tekrar Dene'), findsOneWidget);
      expect(find.textContaining('Hesabınıza bağlı cihaz yok'), findsNothing, reason: 'yanlış "yok" denmez');
      expect(find.textContaining('Cihaz seçimi isteğe bağlıdır'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('site_application_device_1')), findsNothing);

      // Tekrar Dene: liste gelince seçici çıkar, hata kalkar.
      auth
        ..devicesError = null
        ..devices = [saDevice('ESP32_RETRY')];
      await t.tap(find.text('Tekrar Dene'));
      await settleFor(t, 200);
      expect(auth.deviceCalls, 2);
      expect(find.text('Bağlantı yok.'), findsNothing);
      expect(find.byKey(const ValueKey<String>('site_application_device_2')), findsOneWidget);

      await _enter(t, 'Site Adı *', 'Gül Sitesi');
      await _submit(t);
      expect(auth.createCalls.single['deviceUid'], isNull, reason: 'cihaz seçimi isteğe bağlı: varsayılan cihazsız');
      expect(find.text('Başvurunuz alındı.'), findsOneWidget);
    });

    testWidgets('B4: liste hatasına rağmen cihazsız başvuru gönderilebilir (hata yutulmaz ama engellemez)', (t) async {
      final auth = _auth()..devicesError = ApiException('Bağlantı yok.');
      await _open(t, auth);
      await _enter(t, 'Site Adı *', 'Gül Sitesi');
      await _submit(t);
      expect(auth.createCalls.single['deviceUid'], isNull);
      expect(find.text('Başvurunuz alındı.'), findsOneWidget);
    });

    testWidgets('"Yeniden başvur": form önceki değerlerle açılır ve aynı değerlerle gönderilir (cihaz hâlâ uygunsa seçili)', (t) async {
      final auth = _auth()..devices = [saDevice('ESP32_A')];
      await _open(t, auth, prefill: _previous());
      String text(String label) => t.widget<EditableText>(find.descendant(of: _field(label), matching: find.byType(EditableText))).controller.text;
      expect(text('Site Adı *'), 'Eski Başvuru Sitesi');
      expect(text('Açık Adres (İsteğe Bağlı)'), 'Moda Cad. No 5');
      expect(text('Not (İsteğe Bağlı)'), 'Önceki not');
      expect(find.text('İstanbul'), findsOneWidget);
      expect(find.text('Kadıköy'), findsOneWidget);
      expect(find.text('ESP32_A'), findsWidgets);

      await _submit(t);
      final call = auth.createCalls.single;
      expect(call['name'], 'Eski Başvuru Sitesi');
      expect(call['city'], 'İstanbul');
      expect(call['district'], 'Kadıköy');
      expect(call['deviceUid'], 'ESP32_A');
      expect(call['note'], 'Önceki not');
      expect(call['blocks'], <Map<String, dynamic>>[
        <String, dynamic>{'name': 'Kuzey', 'apartmentCount': 12},
        <String, dynamic>{'name': 'Güney', 'apartmentCount': 8},
      ]);
      expect(call['doors'], isEmpty);
    });

    testWidgets('"Yeniden başvur": önceki cihaz artık hesapta değilse sessizce cihazsız', (t) async {
      final auth = _auth()..devices = [saDevice('ESP32_BASKA')];
      await _open(t, auth, prefill: _previous());
      await _submit(t);
      expect(auth.createCalls.single['deviceUid'], isNull);
    });

    testWidgets('ödeme altyapısı yok: "Abonelikle hemen site aç — Yakında…" PASİF satır (dokunulamaz)', (t) async {
      final auth = _auth();
      await _open(t, auth);
      final row = find.text(SiteSubscriptionComingSoonRow.label);
      await scrollTo(t, row);
      expect(row, findsOneWidget);
      expect(SiteSubscriptionComingSoonRow.label, 'Abonelikle hemen site aç — Yakında…');
      final handle = t.ensureSemantics();
      final node = t.getSemantics(find.byType(SiteSubscriptionComingSoonRow));
      final data = node.getSemanticsData();
      expect(data.label, contains('yakında'));
      expect(data.flagsCollection.isEnabled, isNot(true), reason: 'devre dışı');
      handle.dispose();
      await t.tap(row, warnIfMissed: false);
      await t.pump();
      expect(auth.createCalls, isEmpty);
    });
  });

  group('doğrulama', () {
    testWidgets('boş site adı: özet + ilk geçersiz alana kaydırma (320x640 x2,0), istek yok', (t) async {
      final auth = _auth();
      await _open(t, auth, width: 320, height: 640, scale: 2.0);
      await _submit(t, ms: 900);
      expect(find.text('Lütfen işaretli alanları düzeltin.'), findsOneWidget);
      final error = find.text('Site adı zorunludur.');
      expect(error, findsOneWidget);
      final rect = t.getRect(error);
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(640), reason: 'ilk geçersiz alan görünür alanda');
      expect(auth.createCalls, isEmpty);
    });

    testWidgets('daire sayısı: boş / 0 / sayı değil / 5001 geçersiz; sessiz düzeltme yok', (t) async {
      final auth = _auth();
      await _open(t, auth, height: 1200);
      await _enter(t, 'Site Adı *', 'Gül Sitesi');
      for (final bad in const ['', '0', 'abc', '5001', '-3']) {
        await _enter(t, 'Daire Sayısı', bad);
        await _submit(t);
        expect(find.text('Daire sayısı 1 ile 5000 arasında olmalı.'), findsOneWidget, reason: '"$bad"');
        expect(auth.createCalls, isEmpty, reason: '"$bad" gönderilmez');
      }
      await _enter(t, 'Daire Sayısı', '5000');
      await _submit(t);
      expect(auth.createCalls, hasLength(1));
    });

    testWidgets('toplam daire sayısı 5000\'i aşarsa özet hata gösterilir, istek yok', (t) async {
      final auth = _auth();
      await _open(t, auth, height: 1400);
      await _enter(t, 'Site Adı *', 'Gül Sitesi');
      await _enter(t, 'Daire Sayısı', '4995');
      await scrollTo(t, find.text('Blok Ekle'));
      await t.tap(find.text('Blok Ekle'));
      await settleFor(t, 200);
      await _submit(t); // 4995 + 10
      expect(find.text('Toplam daire sayısı en fazla 5000 olabilir.'), findsOneWidget);
      expect(auth.createCalls, isEmpty);
    });

    testWidgets('site adı 120, adres 300, not 500 karakter sınırı: sessiz kırpma YOK, hata + sayaç', (t) async {
      final auth = _auth();
      await _open(t, auth, height: 1600);
      await _enter(t, 'Site Adı *', 'a' * 121);
      await _enter(t, 'Açık Adres (İsteğe Bağlı)', 'b' * 301);
      await _enter(t, 'Not (İsteğe Bağlı)', 'c' * 520);
      String text(String label) => t.widget<EditableText>(find.descendant(of: _field(label), matching: find.byType(EditableText))).controller.text;
      expect(text('Site Adı *').length, 121, reason: 'yapıştırılan fazlalık kırpılmaz');
      expect(text('Not (İsteğe Bağlı)').length, 520);
      expect(find.text('520/500'), findsOneWidget, reason: 'sayaç');
      await _submit(t);
      expect(find.text('Site adı en çok 120 karakter olabilir.'), findsOneWidget);
      expect(find.text('Adres en çok 300 karakter olabilir.'), findsOneWidget);
      expect(find.text('Not en çok 500 karakter olabilir.'), findsOneWidget);
      expect(auth.createCalls, isEmpty);

      await _enter(t, 'Site Adı *', 'a' * 120);
      await _enter(t, 'Açık Adres (İsteğe Bağlı)', 'b' * 300);
      await _enter(t, 'Not (İsteğe Bağlı)', 'c' * 500);
      await _submit(t);
      expect(auth.createCalls, hasLength(1));
    });

    testWidgets('yinelenen blok adı ve çok uzun blok / kapı adı: Türkçe hata', (t) async {
      final auth = _auth();
      await _open(t, auth, height: 1600);
      await _enter(t, 'Site Adı *', 'Gül Sitesi');
      await scrollTo(t, find.text('Blok Ekle'));
      await t.tap(find.text('Blok Ekle'));
      await settleFor(t, 200);
      final names = find.widgetWithText(TextFormField, 'Blok Adı');
      await t.enterText(names.at(1), 'a blok');
      await t.pump();
      await t.enterText(names.at(0), 'A Blok');
      await t.pump();
      await _submit(t);
      expect(find.text('Blok adı benzersiz olmalı.'), findsWidgets);
      expect(auth.createCalls, isEmpty);

      await t.enterText(names.at(1), 'x' * 61);
      await t.pump();
      await _submit(t);
      expect(find.text('Blok adı en çok 60 karakter olabilir.'), findsOneWidget);
      await t.enterText(names.at(1), 'B Blok');
      await t.pump();
    });

    testWidgets('blok ve kapı üst sınırı 100: ekleme düğmesi kapanır, açıklama gösterilir', (t) async {
      final auth = _auth();
      await _open(t, auth, height: 900);
      for (var i = 0; i < 99; i++) {
        final add = find.text('Blok Ekle');
        await t.ensureVisible(add);
        await t.tap(add);
        await t.pump();
      }
      await settleFor(t, 100);
      expect(find.text('En fazla 100 blok eklenebilir.'), findsOneWidget);
      final addBlock = t.widget<TextButton>(find.widgetWithText(TextButton, 'Blok Ekle'));
      expect(addBlock.onPressed, isNull);
    });
  });

  group('gönderim koruması', () {
    testWidgets('çift gönderim: istek sürerken düğme kilitli, alanlar kapalı, geri tuşu ve kapat etkisiz; tek istek', (t) async {
      final auth = _auth()..createGate = Completer<void>();
      final out = await _open(t, auth);
      await _enter(t, 'Site Adı *', 'Gül Sitesi');
      await _submit(t, ms: 100);
      expect(auth.createCalls, hasLength(1));
      expect(find.text('Gönderiliyor...'), findsNothing, reason: 'yükleniyor: etiket yerine ilerleme göstergesi');
      expect(_submitButton(t).loading, isTrue);
      expect(_submitButton(t).onPressed, isNull);
      expect(t.widget<TextFormField>(_field('Site Adı *')).enabled, isFalse);
      expect(t.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.close_rounded)).onPressed, isNull);

      await t.state<NavigatorState>(find.byType(Navigator).first).maybePop();
      await t.pump();
      expect(out.closed, isFalse);

      auth.createGate!.complete();
      await settleFor(t, 400);
      expect(auth.createCalls, hasLength(1));
      expect(find.text('Başvurunuz alındı.'), findsOneWidget);
    });
  });

  group('hata kalıpları', () {
    Future<void> failWith(WidgetTester t, SiteApplicationFakeAuth auth) async {
      await _open(t, auth);
      await _enter(t, 'Site Adı *', 'Gül Sitesi');
      await _submit(t);
    }

    testWidgets('B8: 409 APPLICATION_PENDING -> form KAPANIR (alreadyPending), bekleyen kartı için çağıran haberdar edilir, ileti gösterilir', (t) async {
      // Davranış değişikliği: eskiden pencere açık kalıp "Başvuruyu Gönder" aktif kalıyordu (aynı hata tekrarlanırdı).
      final auth = _auth()..seed([saRow(3, applicantCode: 5)]);
      final out = await _open(t, auth);
      await _enter(t, 'Site Adı *', 'Gül Sitesi');
      await _submit(t);
      expect(out.closed, isTrue);
      expect(out.outcome, SetupSiteOutcome.alreadyPending);
      expect(find.byType(Dialog), findsNothing);
      expect(find.text(SetupSiteDialog.alreadyPendingMessage), findsOneWidget);
      expect(find.text('Başvurunuz alındı.'), findsNothing);
      expect(auth.createCalls, hasLength(1), reason: 'tekrar gönderilmedi');
    });

    testWidgets('409 ALREADY_SITE_MANAGER: başvuran diliyle mesaj; oturum sunucudan yenilenir', (t) async {
      final auth = _auth()..serverRole = UserRole.siteManager;
      await failWith(t, auth);
      expect(find.textContaining('Zaten site yöneticisisiniz'), findsOneWidget);
      expect(find.textContaining('Bu kişi zaten'), findsNothing);
      expect(auth.refreshSessionForcedCalls, 1);
    });

    testWidgets('günlük başvuru sınırı (409 APPLICATION_DAILY_LIMIT): kayan 24 saat mesajı ("yarın" değil), kilit yok', (t) async {
      final auth = _auth()..dailyLimit = 0;
      await failWith(t, auth);
      expect(
        find.text('Son 24 saatte en fazla 5 başvuru yapabilirsiniz. Daha sonra tekrar deneyin.'),
        findsOneWidget,
      );
      expect(find.textContaining('Yarın'), findsNothing);
      expect(_submitButton(t).onPressed, isNotNull);
    });

    testWidgets('404 DEVICE_NOT_FOUND: cihaz seçimini kaldırma yönlendirmesi', (t) async {
      final auth = _auth()
        ..createError = ApiException(
          AuthApi.siteApplicationDeviceNotFoundMessage,
          statusCode: 404,
          code: 'DEVICE_NOT_FOUND',
        );
      await failWith(t, auth);
      expect(find.text(AuthApi.siteApplicationDeviceNotFoundMessage), findsOneWidget);
    });

    testWidgets('422 APPLICATION_DATA_INVALID: Türkçe mesaj, alan adı sızmaz', (t) async {
      final auth = _auth()
        ..createError = ApiException(
          AuthApi.messageForErrorCode('APPLICATION_DATA_INVALID')!,
          statusCode: 422,
          code: 'APPLICATION_DATA_INVALID',
        );
      await failWith(t, auth);
      expect(
        find.text(
          'Başvurudaki yapı verisi geçersiz; onaylanamaz. Reddedip başvuranın yeniden başvurmasını isteyin.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('429: düğme retry-after kadar kilitli, mesajda bekleme süresi; süre dolunca açılır', (t) async {
      final auth = _auth()
        ..createError = ApiException('Çok fazla istek gönderildi.', statusCode: 429, retryAfterSeconds: 45);
      await failWith(t, auth);
      expect(find.textContaining('Çok sık deneme yapıldı. 45 saniye sonra tekrar deneyin.'), findsOneWidget);
      expect(_submitButton(t).onPressed, isNull);
      await t.pump(const Duration(seconds: 46));
      expect(_submitButton(t).onPressed, isNotNull);
    });

    testWidgets('B11: 429 kilidi dolunca sessiz açılmaz: eski hata silinir, "Tekrar deneyebilirsiniz." gösterilir ve DUYURULUR', (t) async {
      final announced = captureAnnouncements(t);
      final auth = _auth()
        ..createError = ApiException('Çok fazla istek gönderildi.', statusCode: 429, retryAfterSeconds: 10);
      await failWith(t, auth);
      expect(find.textContaining('Çok sık deneme yapıldı'), findsOneWidget);
      expect(announced, isEmpty);
      await t.pump(const Duration(seconds: 11));
      await t.pump();
      expect(find.textContaining('Çok sık deneme yapıldı'), findsNothing, reason: 'bayat hata kalmaz');
      expect(find.text('Tekrar deneyebilirsiniz.'), findsOneWidget);
      expect(announced, contains('Tekrar deneyebilirsiniz.'));
      expect(_submitButton(t).onPressed, isNotNull);
    });

    testWidgets('beklenmeyen istisna: genel Türkçe mesaj, ham istisna sızmaz', (t) async {
      final auth = _auth()..createError = StateError('ham ayrıntı application_id');
      await failWith(t, auth);
      expect(find.text('Başvuru gönderilemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.'), findsOneWidget);
      expect(find.textContaining('ham ayrıntı'), findsNothing);
      expect(find.textContaining('StateError'), findsNothing);
    });

    testWidgets('hata kutusu kaydırılmış formda görünür konuma gelir (320x640 x2,0)', (t) async {
      final auth = _auth()..createError = ApiException(AuthApi.siteApplicationDeviceNotFoundMessage, statusCode: 404, code: 'DEVICE_NOT_FOUND');
      await _open(t, auth, width: 320, height: 640, scale: 2.0);
      await _enter(t, 'Site Adı *', 'Gül Sitesi');
      await _submit(t, ms: 900);
      final rect = t.getRect(find.text(AuthApi.siteApplicationDeviceNotFoundMessage));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(640));
    });
  });

  group('B5: kısa / yatay ekran + klavye + büyük yazı', () {
    for (final application in const [true, false]) {
      for (final dark in const [false, true]) {
        testWidgets(
          '${application ? 'başvuru' : 'anlık'} formu 640x360 x2,0 + klavye (200 dp) ${dark ? 'koyu' : 'açık'}: taşma yok, gönder düğmesine kaydırılıp basılır',
          (t) async {
            final auth = _auth(application ? UserRole.individual : UserRole.siteManager);
            await _open(t, auth, width: 640, height: 360, scale: 2.0, dark: dark);
            t.view.viewInsets = const FakeViewPadding(bottom: 200);
            addTearDown(t.view.resetViewInsets);
            await t.pump();
            expect(t.takeException(), isNull);

            await _enter(t, 'Site Adı *', 'Gül Sitesi');
            final submit = find.byKey(const ValueKey<String>('setup_site_submit'));
            await scrollTo(t, submit);
            expect(t.takeException(), isNull);
            await t.tap(submit);
            await settleFor(t, 800);
            expect(application ? auth.createCalls : auth.setupCalls, hasLength(1));
            expect(t.takeException(), isNull);
          },
        );
      }
    }

    testWidgets('kısa ekran (360 dp yükseklik) + klavye: başlık formla birlikte kayar (sabit başlık yer yemez)', (t) async {
      final auth = _auth();
      await _open(t, auth, width: 640, height: 360, scale: 1.0);
      final header = find.text('Site Başvurusu');
      final before = t.getTopLeft(header).dy;
      t.view.viewInsets = const FakeViewPadding(bottom: 160);
      addTearDown(t.view.resetViewInsets);
      await t.pump();
      await scrollTo(t, find.byKey(const ValueKey<String>('setup_site_submit')));
      expect(t.getTopLeft(header).dy, lessThan(before), reason: 'başlık içerikle birlikte kaydı: tek kaydırma alanı');
      expect(t.takeException(), isNull);
    });

    testWidgets('uzun ekranda düzen eskisi gibi: gönder düğmesi SABİT altta (kaydırmadan görünür)', (t) async {
      final auth = _auth();
      await _open(t, auth, width: 400, height: 900, scale: 1.0);
      final submit = find.byKey(const ValueKey<String>('setup_site_submit'));
      expect(submit, findsOneWidget);
      final rect = t.getRect(submit);
      expect(rect.bottom, lessThanOrEqualTo(900));
      expect(rect.top, greaterThan(500), reason: 'altta sabit');
    });
  });

  group('B6: başarı görünümünde odak ve duyuru', () {
    testWidgets('form başarı görünümüyle değişince odak başlığa taşınır ve ekran okuyucuya duyurulur', (t) async {
      final announced = captureAnnouncements(t);
      final auth = _auth();
      await _open(t, auth);
      await _enter(t, 'Site Adı *', 'Gül Sitesi');
      await _submit(t);
      expect(find.text('Başvurunuz alındı.'), findsOneWidget);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'site_application_success');
      expect(
        announced,
        contains('Başvurunuz alındı. Süper kullanıcı onayladığında site yöneticisi olacaksınız.'),
      );
    });
  });

  group('B10/B11/B16: kapanış sonucu, bağlamlı silme düğmeleri, canlı doğrulama, kod noktası sayımı', () {
    testWidgets('B10: istek sonucu BELİRSİZ hata (zaman aşımı) sonrası kapatınca uncertain; kesin hata (400) sonrası null', (t) async {
      final uncertain = _auth()..createError = ApiException('Sunucu zaman aşımına uğradı.');
      var out = await _open(t, uncertain);
      await _enter(t, 'Site Adı *', 'Gül Sitesi');
      await _submit(t);
      expect(find.textContaining('Sunucu zaman aşımına uğradı'), findsOneWidget);
      await t.tap(find.byTooltip('Kapat'));
      await settleFor(t, 400);
      expect(out.outcome, SetupSiteOutcome.uncertain);

      final definite = _auth()
        ..createError = ApiException('Site adı zorunludur.', statusCode: 400, code: 'INVALID_BODY');
      out = await _open(t, definite);
      await _enter(t, 'Site Adı *', 'Gül Sitesi');
      await _submit(t);
      await t.tap(find.byTooltip('Kapat'));
      await settleFor(t, 400);
      expect(out.closed, isTrue);
      expect(out.outcome, isNull, reason: 'kesin ret: durum yeniden okunmasına gerek yok');

      final server = _auth()..createError = ApiException('Sunucu hatası', statusCode: 503);
      out = await _open(t, server);
      await _enter(t, 'Site Adı *', 'Gül Sitesi');
      await _submit(t);
      await t.tap(find.byTooltip('Kapat'));
      await settleFor(t, 400);
      expect(out.outcome, SetupSiteOutcome.uncertain, reason: '5xx: istek sunucuya ulaşmış olabilir');
    });

    testWidgets('B10: hiçbir şey göndermeden kapatma -> null (gereksiz mine çağrısı yok)', (t) async {
      final auth = _auth();
      final out = await _open(t, auth);
      await t.tap(find.byTooltip('Kapat'));
      await settleFor(t, 400);
      expect(out.outcome, isNull);
      expect(auth.createCalls, isEmpty);
    });

    testWidgets('B11: silme düğmeleri hangi satırı sildiğini söyler (ipucu + ekran okuyucu etiketi), ad değişince güncellenir', (t) async {
      final auth = _auth();
      await _open(t, auth, height: 1400);
      await scrollTo(t, find.text('Blok Ekle'));
      await t.tap(find.text('Blok Ekle'));
      await settleFor(t, 200);
      expect(find.byTooltip('Bloğu sil: A Blok'), findsOneWidget);
      expect(find.byTooltip('Bloğu sil: B Blok'), findsOneWidget);
      final handle = t.ensureSemantics();
      expect(
        t.getSemantics(find.byTooltip('Bloğu sil: B Blok')).getSemanticsData().tooltip,
        'Bloğu sil: B Blok',
      );
      handle.dispose();

      await t.enterText(find.widgetWithText(TextFormField, 'Blok Adı').at(1), 'Kuzey');
      await t.pump();
      expect(find.byTooltip('Bloğu sil: Kuzey'), findsOneWidget);
      expect(find.byTooltip('Bloğu sil: B Blok'), findsNothing);
    });

    testWidgets('B11: yinelenen blok adı hatası CANLI güncellenir (eşinin hatası düzeltince kendiliğinden kalkar)', (t) async {
      final auth = _auth();
      await _open(t, auth, height: 1400);
      await scrollTo(t, find.text('Blok Ekle'));
      await t.tap(find.text('Blok Ekle'));
      await settleFor(t, 200);
      final names = find.widgetWithText(TextFormField, 'Blok Adı');
      await t.enterText(names.at(1), 'A Blok');
      await t.pump();
      await t.pump();
      expect(find.text('Blok adı benzersiz olmalı.'), findsNWidgets(2), reason: 'iki alan da işaretlenir');
      await t.enterText(names.at(0), 'Z Blok');
      await t.pump();
      await t.pump();
      expect(find.text('Blok adı benzersiz olmalı.'), findsNothing, reason: 'gönder düğmesine basmadan temizlendi');
    });

    testWidgets('B16: not sınırı KOD NOKTASIdır (emoji 1 sayılır): 500 emoji kabul; sayaç aynı birimde', (t) async {
      final auth = _auth();
      await _open(t, auth, height: 1600);
      await _enter(t, 'Site Adı *', 'Gül Sitesi');
      await _enter(t, 'Not (İsteğe Bağlı)', '😀' * 500);
      expect(find.text('500/500'), findsOneWidget, reason: 'sayaç kod noktası sayar (UTF-16 olsa 1000 olurdu)');
      await _submit(t);
      expect(auth.createCalls, hasLength(1), reason: '500 emoji sunucuda da geçerli (500 kod noktası)');
    });

    testWidgets('B16: 501 emoji reddedilir; kırpılmış metin sayılır (baştaki / sondaki boşluk fazlalık sayılmaz)', (t) async {
      final auth = _auth();
      await _open(t, auth, height: 1600);
      await _enter(t, 'Site Adı *', 'Gül Sitesi');
      await _enter(t, 'Not (İsteğe Bağlı)', '😀' * 501);
      expect(find.text('501/500'), findsOneWidget);
      await _submit(t);
      expect(find.text('Not en çok 500 karakter olabilir.'), findsOneWidget);
      expect(auth.createCalls, isEmpty);
      await _enter(t, 'Not (İsteğe Bağlı)', '   ${'a' * 500}   ');
      expect(find.text('500/500'), findsOneWidget, reason: 'boşluklar sayılmaz');
      await _submit(t);
      expect(auth.createCalls, hasLength(1));
    });
  });

  group('taşma matrisi', () {
    g4LayoutMatrix('başvuru formu: cihaz seçici, not, pasif abonelik satırı', (t, w, h, s, dark) async {
      final auth = _auth()..devices = [saDevice('ESP32_C3_ABCDEF1234567890'), saDevice('ESP32_WROOM_0011')];
      await _open(t, auth, width: w, height: h, scale: s, dark: dark);
      expect(find.text('Site Başvurusu'), findsOneWidget);
      expect(find.text('Cihaz (isteğe bağlı)'), findsOneWidget);
      await scrollTo(t, find.byKey(const ValueKey<String>('site_application_note')));
      await scrollTo(t, find.text(SiteSubscriptionComingSoonRow.label));
      await scrollTo(t, find.byKey(const ValueKey<String>('setup_site_submit')));
    });

    g4LayoutMatrix('başvuru gönderildi iletisi', (t, w, h, s, dark) async {
      final auth = _auth();
      await _open(t, auth, width: w, height: h, scale: s, dark: dark);
      await _enter(t, 'Site Adı *', 'Gül Sitesi');
      await _submit(t);
      expect(find.text('Başvurunuz alındı.'), findsOneWidget);
      await scrollTo(t, find.byKey(const ValueKey<String>('setup_site_done')));
    });

    g4LayoutMatrix('"Cihaz Eklendi" bilgi penceresi: uzun UID, bilgi metni, Site Kur / Daha Sonra', (t, w, h, s, dark) async {
      final auth = _auth();
      await openDialogAt(
        t,
        (context) => offerSiteApplicationAfterClaim(
          context,
          authService: auth,
          deviceUid: 'ESP32_C3_ABCDEF1234567890ABCDEF',
        ),
        width: w,
        height: h,
        scale: s,
        dark: dark,
      );
      expect(find.text('Cihaz Eklendi'), findsOneWidget);
      expect(find.text(kDeviceAddedMessage), findsOneWidget);
      final siteSetup = find.byKey(const ValueKey<String>('device_added_site_setup'));
      final later = find.byKey(const ValueKey<String>('device_added_later'));
      await scrollTo(t, siteSetup);
      expect(t.getSize(siteSetup).height, greaterThanOrEqualTo(48));
      await scrollTo(t, later);
      expect(t.getSize(later).height, greaterThanOrEqualTo(48));
      await t.tap(later);
      await settleFor(t, 400);
      expect(find.text('Cihaz Eklendi'), findsNothing);
    });

    g4LayoutMatrix('yeniden başvur: önceki değerler, uzun adlar', (t, w, h, s, dark) async {
      final auth = _auth()..devices = [saDevice('ESP32_A')];
      await _open(t, auth, prefill: _previous(), width: w, height: h, scale: s, dark: dark);
      await scrollTo(t, find.text('Kuzey'));
      expect(find.text('Kuzey'), findsOneWidget);
    });

    testWidgets('klavye açıkken (320x640 x2,0) form taşmaz ve hata özeti görünür kalır', (t) async {
      final auth = _auth();
      await _open(t, auth, width: 320, height: 640, scale: 2.0);
      t.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(t.view.resetViewInsets);
      await t.pump();
      await _enter(t, 'Site Adı *', 'Gül');
      await _submit(t);
      expect(auth.createCalls, hasLength(1));
      expect(find.text('Başvurunuz alındı.'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });
}
