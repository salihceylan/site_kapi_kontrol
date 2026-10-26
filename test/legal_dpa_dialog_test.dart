// Site başvurusu formunda Veri İşleme Sözleşmesi (dpa) onayı (SetupSiteDialog, başvuru kipi).
//
// Belgeler yüklenmeden / kutu işaretlenmeden "Başvuruyu Gönder" kapalıdır ve nedeni yazılıdır; gönderimde
// accepted_documents:[{id:dpa,version}] yollanır; anlık kurulumda (yalnız süper kullanıcı) kutu ve ağ
// çağrısı yoktur. Site yöneticisi de BAŞVURU yapar (süper kullanıcı onayı), dolayısıyla kutuyu görür.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/dialogs/setup_site_dialog.dart';

import 'legal_fixtures.dart';
import 'screens/dialog_layout_harness.dart';
import 'screens/site_application_fixtures.dart';

Future<void> _open(
  WidgetTester t,
  SiteApplicationFakeAuth auth,
  FakeLegalServer server, {
  double width = 400,
  double height = 900,
  double scale = 1.0,
  bool dark = false,
}) async {
  await openDialogAt(
    t,
    (context) async {
      await SetupSiteDialog.show(context, authService: auth, legalApi: server.api);
    },
    width: width,
    height: height,
    scale: scale,
    dark: dark,
  );
  await t.pump();
  await t.pump(const Duration(milliseconds: 100));
}

Finder get _submit => find.byKey(const ValueKey<String>('setup_site_submit'));
PrimaryActionButton _button(WidgetTester t) => t.widget<PrimaryActionButton>(_submit);

Future<void> _fillName(WidgetTester t) async {
  await t.enterText(find.widgetWithText(TextFormField, 'Site Adı *'), 'Gül Sitesi');
  await t.pump();
}

Future<void> _tapDpaBox(WidgetTester t) async {
  final box = find.byType(Checkbox);
  await scrollTo(t, box);
  await t.tap(box);
  await t.pump();
}

void main() {
  group('Başvuru: Veri İşleme Sözleşmesi onayı', () {
    testWidgets('kutu görünür; işaretsizken gönderme kapalı ve neden yazılı; işaretleyince açılır', (t) async {
      final server = FakeLegalServer();
      final auth = SiteApplicationFakeAuth(role: UserRole.individual);
      await _open(t, auth, server);
      await scrollTo(t, find.byType(Checkbox));
      expect(find.text("Veri İşleme Sözleşmesi'ni okudum ve kabul ediyorum."), findsOneWidget);
      expect(find.text('Veri İşleme Sözleşmesi metnini oku'), findsOneWidget);
      expect(find.text('Kullanım Koşulları metnini oku'), findsNothing, reason: 'kayıt belgeleri başvuruda istenmez');
      expect(_button(t).onPressed, isNull);
      expect(find.byKey(const ValueKey<String>('setup_site_block_reason')), findsOneWidget);
      expect(find.textContaining('onay kutusunu işaretleyin'), findsOneWidget);

      await _tapDpaBox(t);
      expect(_button(t).onPressed, isNotNull);
      expect(find.byKey(const ValueKey<String>('setup_site_block_reason')), findsNothing);
    });

    testWidgets('pasif "Başvuruyu Gönder" düğmesinin NEDENİ düğmeye bağlıdır; işaretleyince kalkar', (t) async {
      final semantics = t.ensureSemantics();
      try {
        final auth = SiteApplicationFakeAuth(role: UserRole.individual);
        await _open(t, auth, FakeLegalServer());
        await scrollTo(t, _submit);
        expect(t.getSemantics(_submit).hint, contains('onay kutusunu işaretleyin'));
        await _tapDpaBox(t);
        await scrollTo(t, _submit);
        expect(t.getSemantics(_submit).hint, isEmpty);
      } finally {
        semantics.dispose();
      }
    });

    testWidgets('gönderimde accepted_documents = dpa@sürüm', (t) async {
      final server = FakeLegalServer();
      final auth = SiteApplicationFakeAuth(role: UserRole.individual);
      await _open(t, auth, server);
      await _fillName(t);
      await _tapDpaBox(t);
      await scrollTo(t, _submit);
      await t.tap(_submit);
      await settleFor(t, 800);
      expect(auth.createCalls, hasLength(1));
      expect(auth.createAccepted.single, <String>['dpa@2026-10-16']);
    });

    testWidgets('kutu işaretlenmeden form doğrulanıp gönderilemez (düğmeye dokunmak istek açmaz)', (t) async {
      final server = FakeLegalServer();
      final auth = SiteApplicationFakeAuth(role: UserRole.individual);
      await _open(t, auth, server);
      await _fillName(t);
      await scrollTo(t, _submit);
      await t.tap(_submit, warnIfMissed: false);
      await settleFor(t, 400);
      expect(auth.createCalls, isEmpty);
    });

    testWidgets('yüklenemezse: neden + "Yeniden dene", kutu yok, gönderme kapalı; düzelince kutu çıkar', (t) async {
      final server = FakeLegalServer()..listStatus = 500;
      final auth = SiteApplicationFakeAuth(role: UserRole.individual);
      await _open(t, auth, server);
      await scrollTo(t, find.text('Yeniden dene'));
      expect(find.byType(Checkbox), findsNothing);
      expect(_button(t).onPressed, isNull);
      expect(find.textContaining('Belgeler yüklenemediği için devam edilemiyor'), findsOneWidget);

      server.listStatus = 200;
      await t.tap(find.text('Yeniden dene'));
      await settleFor(t, 300);
      expect(find.byType(Checkbox), findsOneWidget);
      expect(find.text('Yeniden dene'), findsNothing);
    });

    testWidgets('belge listesi başarıyla boşsa kutu yok, gönderme açık', (t) async {
      final server = FakeLegalServer(documents: <Map<String, dynamic>>[]);
      final auth = SiteApplicationFakeAuth(role: UserRole.individual);
      await _open(t, auth, server);
      expect(find.byType(Checkbox), findsNothing);
      expect(_button(t).onPressed, isNotNull);
      await _fillName(t);
      await scrollTo(t, _submit);
      await t.tap(_submit);
      await settleFor(t, 800);
      expect(auth.createAccepted.single, isEmpty);
    });

    testWidgets('sunucu CONSENT_VERSION_STALE derse işaret kalkar ve belgeler yeniden okunur', (t) async {
      final server = FakeLegalServer();
      final auth = SiteApplicationFakeAuth(role: UserRole.individual)
        ..createError = ApiException(
          'Belgeler güncellendi. Güncel metinleri okuyup onay kutusunu yeniden işaretleyin.',
          statusCode: 409,
          code: 'CONSENT_VERSION_STALE',
        );
      await _open(t, auth, server);
      await _fillName(t);
      await _tapDpaBox(t);
      server.documents = standardLegalDocs(version: '2026-12-01');
      await scrollTo(t, _submit);
      await t.tap(_submit);
      await settleFor(t, 800);
      expect(server.count('GET', '/public/legal-documents'), 2);
      await scrollTo(t, find.byType(Checkbox));
      expect(t.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
      expect(_button(t).onPressed, isNull);
    });

    testWidgets('anlık kurulum (süper kullanıcı): kutu yok, belge uçları çağrılmaz, gönderme açık', (t) async {
      final server = FakeLegalServer();
      final auth = SiteApplicationFakeAuth(role: UserRole.superUser);
      await _open(t, auth, server);
      expect(find.byType(Checkbox), findsNothing);
      expect(server.requests, isEmpty);
      expect(_button(t).onPressed, isNotNull);
    });

    testWidgets('site yöneticisi de başvuru yapar: kutu görünür, işaretsizken gönderme kapalı', (t) async {
      final server = FakeLegalServer();
      final auth = SiteApplicationFakeAuth(role: UserRole.siteManager);
      await _open(t, auth, server);
      await scrollTo(t, find.byType(Checkbox));
      expect(find.byType(Checkbox), findsOneWidget);
      expect(_button(t).onPressed, isNull);
    });

    for (final (w, h, s) in const <(double, double, double)>[
      (320, 640, 2.0),
      (360, 640, 1.5),
      (640, 360, 2.0), // yatay + büyük yazı
    ]) {
      for (final dark in const <bool>[false, true]) {
        testWidgets('taşma yok: yüklü / hata (${w.toInt()}x${h.toInt()} x$s ${dark ? 'koyu' : 'açık'})', (t) async {
          await _open(t, SiteApplicationFakeAuth(role: UserRole.individual), FakeLegalServer(),
              width: w, height: h, scale: s, dark: dark);
          await scrollTo(t, find.byType(Checkbox));
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox());

          await _open(t, SiteApplicationFakeAuth(role: UserRole.individual), FakeLegalServer()..listStatus = 500,
              width: w, height: h, scale: s, dark: dark);
          await scrollTo(t, find.text('Yeniden dene'));
          expect(t.takeException(), isNull);
        });
      }
    }
  });
}
