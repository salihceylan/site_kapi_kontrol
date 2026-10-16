// Yasal onay kutusu: denetleyici (LegalConsentController), alan (LegalConsentField) ve kayıt ekranındaki
// davranış (RegisterIndividualPage). Sahte sunucu: test/legal_fixtures.dart.
//
// Önceki incelemelerin sınıfları: hata/yükleme durumunda yanlış "boş" iletisi, çift dokunma, ekran okuyucu
// etiketleri, küçük ekran taşması.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/legal_document.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/pages/register_individual_page.dart';
import 'package:site_kapi_kontrol/ui/views/legal_consent_controller.dart';
import 'package:site_kapi_kontrol/ui/views/legal_consent_field.dart';

import 'design/harness.dart';
import 'legal_fixtures.dart';

class _FakeAuth extends AuthService {
  _FakeAuth({this.error}) : super(api: AuthApi(baseUrl: 'http://localhost'));

  String? error;
  final List<List<String>> accepted = <List<String>>[];

  @override
  Future<String?> registerIndividual({
    required String firstName,
    required String lastName,
    required String email,
    required String password,
    List<AcceptedDocument>? acceptedDocuments,
  }) async {
    accepted.add(<String>[for (final d in acceptedDocuments ?? const <AcceptedDocument>[]) '${d.id}@${d.version}']);
    return error;
  }
}

const String _good = 'Mavi-Kedi-2026';

Finder get _fields => find.byType(TextFormField);
Finder get _registerButton => find.byType(PrimaryActionButton);

PrimaryActionButton _button(WidgetTester t) => t.widget<PrimaryActionButton>(_registerButton);

Future<void> _pumpPage(
  WidgetTester t,
  FakeLegalServer server, {
  _FakeAuth? auth,
  double width = 360,
  double height = 900,
  double scale = 1.0,
  bool dark = false,
  bool settle = true,
}) async {
  await pumpAt(
    t,
    SizedBox(
      width: width,
      height: height,
      child: RegisterIndividualPage(authService: auth ?? _FakeAuth(), legalApi: server.api),
    ),
    width: width,
    height: height,
    scale: scale,
    dark: dark,
  );
  if (settle) await t.pump(const Duration(milliseconds: 100));
}

Future<void> _fill(WidgetTester t) async {
  await t.enterText(_fields.at(0), 'Ali');
  await t.enterText(_fields.at(1), 'Veli');
  await t.enterText(_fields.at(2), 'ali@example.com');
  await t.enterText(_fields.at(3), _good);
  await t.enterText(_fields.at(4), _good);
}

Future<void> _tapVisible(WidgetTester t, Finder finder) async {
  await t.pump(const Duration(milliseconds: 300));
  await t.ensureVisible(finder);
  await t.pump();
  await t.pump(const Duration(milliseconds: 300));
  await t.tap(finder);
  await t.pump();
}

void main() {
  group('LegalConsentController', () {
    test('yükleme -> hazır: yalnız bu bağlamın belgeleri; onay yokken gönderme kapalı ve nedeni yazılı', () async {
      final server = FakeLegalServer();
      final c = LegalConsentController(api: server.api, context: LegalContexts.register);
      expect(c.status, LegalLoadStatus.loading);
      expect(c.blocksSubmit, isTrue);
      expect(c.blockReason, contains('yükleniyor'));
      await c.load();
      expect(c.status, LegalLoadStatus.ready);
      expect(c.documents.map((d) => d.id), <String>['terms', 'privacy', 'kvkk_notice']);
      expect(c.needsConsent, isTrue);
      expect(c.blocksSubmit, isTrue);
      expect(c.blockReason, contains('onay kutusunu işaretleyin'));
      expect(c.acceptedDocuments, isEmpty, reason: 'işaretlenmeden onay gönderilmez');

      c.setAccepted(true);
      expect(c.blocksSubmit, isFalse);
      expect(c.blockReason, isNull);
      expect(c.acceptedDocuments.map((d) => '${d.id}@${d.version}'), <String>[
        'terms@2026-10-16',
        'privacy@2026-10-16',
        'kvkk_notice@2026-10-16',
      ]);
      c.setAccepted(false);
      expect(c.blocksSubmit, isTrue);
      c.dispose();
    });

    test('site başvurusu bağlamı yalnız dpa belgesini getirir', () async {
      final server = FakeLegalServer();
      final c = LegalConsentController(api: server.api, context: LegalContexts.siteApplication);
      await c.load();
      expect(c.documents.map((d) => d.id), <String>['dpa']);
      c.dispose();
    });

    test('hata: kutu işaretlenemez (sahte onay yok), gönderme kapalı; yeniden denenince düzelir', () async {
      final server = FakeLegalServer()..listStatus = 500;
      final c = LegalConsentController(api: server.api, context: LegalContexts.register);
      await c.load();
      expect(c.status, LegalLoadStatus.error);
      expect(c.error, isNotNull);
      expect(c.needsConsent, isFalse);
      c.setAccepted(true);
      expect(c.accepted, isFalse, reason: 'belgeler yüklenmeden işaretlenemez');
      expect(c.blocksSubmit, isTrue);
      expect(c.blockReason, contains('Yeniden dene'));
      expect(c.acceptedDocuments, isEmpty);

      server.listStatus = 200;
      await c.load();
      expect(c.status, LegalLoadStatus.ready);
      expect(c.error, isNull);
      c.dispose();
    });

    test('başarıyla BOŞ liste: kutu yok ve gönderme kapalı DEĞİL', () async {
      final server = FakeLegalServer(documents: <Map<String, dynamic>>[]);
      final c = LegalConsentController(api: server.api, context: LegalContexts.register);
      await c.load();
      expect(c.status, LegalLoadStatus.ready);
      expect(c.needsConsent, isFalse);
      expect(c.blocksSubmit, isFalse);
      expect(c.blockReason, isNull);
      expect(c.acceptedDocuments, isEmpty);
      c.dispose();
    });

    test('complete:false belgeler de gösterilir ve onaya dahil edilir (sunucu sessizce atlar)', () async {
      final server = FakeLegalServer(
        documents: <Map<String, dynamic>>[
          legalDoc('terms', requiredFor: const <String>['register'], complete: false),
          legalDoc('privacy', requiredFor: const <String>['register'], complete: false),
        ],
      );
      final c = LegalConsentController(api: server.api, context: LegalContexts.register);
      await c.load();
      expect(c.needsConsent, isTrue);
      c.setAccepted(true);
      expect(c.acceptedDocuments.map((d) => d.id), <String>['terms', 'privacy']);
      c.dispose();
    });

    test('yeniden yüklemede sürüm değiştiyse işaret kalkar; aynıysa korunur', () async {
      final server = FakeLegalServer();
      final c = LegalConsentController(api: server.api, context: LegalContexts.register);
      await c.load();
      c.setAccepted(true);
      await c.load();
      expect(c.accepted, isTrue, reason: 'aynı sürümler: işaret korunur');

      server.documents = standardLegalDocs(version: '2026-11-01');
      await c.load();
      expect(c.accepted, isFalse, reason: 'yeni sürüm görülmeden onay geçerli sayılmaz');
      expect(c.documents.first.version, '2026-11-01');
      c.dispose();
    });

    test('hazırken sessiz yenileme başarısız olursa eski liste ve işaret korunur', () async {
      final server = FakeLegalServer();
      final c = LegalConsentController(api: server.api, context: LegalContexts.register);
      await c.load();
      c.setAccepted(true);
      server.listStatus = 503;
      await c.load();
      expect(c.status, LegalLoadStatus.ready);
      expect(c.accepted, isTrue);
      c.dispose();
    });

    test('reloadAfterRejection: işareti kaldırır ve hatayı AÇIKÇA gösterir', () async {
      final server = FakeLegalServer();
      final c = LegalConsentController(api: server.api, context: LegalContexts.register);
      await c.load();
      c.setAccepted(true);
      server.listStatus = 500;
      await c.reloadAfterRejection();
      expect(c.accepted, isFalse);
      expect(c.status, LegalLoadStatus.error);
      c.dispose();
    });

    test('eşzamanlı load çağrıları tek istek açar', () async {
      final server = FakeLegalServer()..listGate = Completer<void>();
      final c = LegalConsentController(api: server.api, context: LegalContexts.register);
      final a = c.load();
      final b = c.load();
      final d = c.load();
      server.listGate!.complete();
      await Future.wait<void>(<Future<void>>[a, b, d]);
      expect(server.count('GET', '/public/legal-documents'), 1);
      c.dispose();
    });

    test('dispose sonrası gelen yanıt hata fırlatmaz', () async {
      final server = FakeLegalServer()..listGate = Completer<void>();
      final c = LegalConsentController(api: server.api, context: LegalContexts.register);
      final pending = c.load();
      c.dispose();
      server.listGate!.complete();
      await pending;
    });
  });

  group('LegalConsentField.leadFor', () {
    LegalDocumentSummary doc(String id) => LegalDocumentSummary(id: id, title: id, version: 'v1');

    test('üç kayıt belgesi: sözleşme cümlesi', () {
      expect(
        LegalConsentField.leadFor(<LegalDocumentSummary>[doc('terms'), doc('privacy'), doc('kvkk_notice')]),
        "Kullanım Koşulları, Gizlilik Politikası ve KVKK Aydınlatma Metni'ni okudum.",
      );
    });

    test('alt küme ve sıra: ek (nı/ni) son belgeye göre', () {
      expect(LegalConsentField.leadFor(<LegalDocumentSummary>[doc('kvkk_notice'), doc('terms')]),
          "Kullanım Koşulları ve KVKK Aydınlatma Metni'ni okudum.");
      expect(LegalConsentField.leadFor(<LegalDocumentSummary>[doc('privacy'), doc('terms')]),
          "Kullanım Koşulları ve Gizlilik Politikası'nı okudum.");
      expect(LegalConsentField.leadFor(<LegalDocumentSummary>[doc('terms')]), "Kullanım Koşulları'nı okudum.");
    });

    test('dpa ve bilinmeyen belgeler', () {
      expect(LegalConsentField.leadFor(<LegalDocumentSummary>[doc('dpa')]),
          "Veri İşleme Sözleşmesi'ni okudum ve kabul ediyorum.");
      expect(LegalConsentField.leadFor(<LegalDocumentSummary>[doc('terms'), doc('yeni_belge')]),
          'Aşağıdaki belgeleri okudum ve kabul ediyorum.');
      expect(LegalConsentField.leadFor(const <LegalDocumentSummary>[]), isEmpty);
    });
  });

  group('Kayıt ekranı: yasal onay', () {
    testWidgets('yükleniyor: kutu yok, gönderme kapalı, neden yazılı; yüklenince kutu çıkar', (t) async {
      final server = FakeLegalServer()..listGate = Completer<void>();
      await _pumpPage(t, server);
      expect(find.byType(Checkbox), findsNothing);
      expect(find.text('Belgeler yükleniyor...'), findsOneWidget);
      expect(_button(t).onPressed, isNull);
      expect(find.byKey(const ValueKey<String>('register_block_reason')), findsOneWidget);
      expect(find.textContaining('Belgeler yükleniyor; yüklenince'), findsOneWidget);

      server.listGate!.complete();
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      expect(find.byType(Checkbox), findsOneWidget);
      expect(find.text('Belgeler yükleniyor...'), findsNothing);
    });

    testWidgets('kutu cümlesi ve belge bağlantıları; işaretsizken "Kayıt Ol" kapalı ve neden okunur', (t) async {
      await _pumpPage(t, FakeLegalServer());
      expect(find.text("Kullanım Koşulları, Gizlilik Politikası ve KVKK Aydınlatma Metni'ni okudum."), findsOneWidget);
      expect(find.text('Kullanım Koşulları metnini oku'), findsOneWidget);
      expect(find.text('Gizlilik Politikası metnini oku'), findsOneWidget);
      expect(find.text('KVKK Aydınlatma Metni metnini oku'), findsOneWidget);
      expect(find.text('Veri İşleme Sözleşmesi metnini oku'), findsNothing, reason: 'dpa kayıtta istenmez');
      expect(t.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
      expect(_button(t).onPressed, isNull);
      expect(find.textContaining('Devam etmek için belgeleri okuyup onay kutusunu işaretleyin'), findsOneWidget);
    });

    testWidgets('işaretleyince açılır; kaldırınca yeniden kapanır; satırın tamamı dokunma alanıdır', (t) async {
      await _pumpPage(t, FakeLegalServer());
      await _tapVisible(t, find.text("Kullanım Koşulları, Gizlilik Politikası ve KVKK Aydınlatma Metni'ni okudum."));
      expect(t.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
      expect(_button(t).onPressed, isNotNull);
      expect(find.byKey(const ValueKey<String>('register_block_reason')), findsNothing);

      await _tapVisible(t, find.byType(Checkbox));
      expect(t.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
      expect(_button(t).onPressed, isNull);
    });

    testWidgets('gönderimde accepted_documents (kimlik@sürüm) yollanır; dpa/silme belgesi yollanmaz', (t) async {
      final auth = _FakeAuth();
      await _pumpPage(t, FakeLegalServer(), auth: auth);
      await _fill(t);
      await _tapVisible(t, find.byType(Checkbox));
      await _tapVisible(t, _registerButton);
      await t.pump(const Duration(milliseconds: 400));
      expect(auth.accepted.single, <String>['terms@2026-10-16', 'privacy@2026-10-16', 'kvkk_notice@2026-10-16']);
    });

    testWidgets('complete:false belgeler de gösterilir ve gönderilir (S-B kararı)', (t) async {
      final server = FakeLegalServer(
        documents: <Map<String, dynamic>>[
          for (final id in const <String>['terms', 'privacy', 'kvkk_notice'])
            legalDoc(id, requiredFor: const <String>['register'], complete: false),
        ],
      );
      final auth = _FakeAuth();
      await _pumpPage(t, server, auth: auth);
      expect(find.byType(Checkbox), findsOneWidget);
      await _fill(t);
      await _tapVisible(t, find.byType(Checkbox));
      await _tapVisible(t, _registerButton);
      await t.pump(const Duration(milliseconds: 400));
      expect(auth.accepted.single, hasLength(3));
    });

    testWidgets('liste başarıyla BOŞ dönerse kutu çıkmaz ve kayıt engellenmez', (t) async {
      final auth = _FakeAuth();
      await _pumpPage(t, FakeLegalServer(documents: <Map<String, dynamic>>[]), auth: auth);
      expect(find.byType(Checkbox), findsNothing);
      expect(find.byKey(const ValueKey<String>('register_block_reason')), findsNothing);
      expect(_button(t).onPressed, isNotNull);
      await _fill(t);
      await _tapVisible(t, _registerButton);
      await t.pump(const Duration(milliseconds: 400));
      expect(auth.accepted.single, isEmpty);
    });

    testWidgets('yükleme HATASI: "boş" denmez; neden + "Yeniden dene"; kutu ve gönderme kilitli', (t) async {
      final server = FakeLegalServer()..listStatus = 500;
      await _pumpPage(t, server);
      expect(find.byType(Checkbox), findsNothing);
      expect(find.text('Yeniden dene'), findsOneWidget);
      expect(find.textContaining('Sunucu'), findsWidgets);
      expect(_button(t).onPressed, isNull);
      expect(find.textContaining('Belgeler yüklenemediği için devam edilemiyor'), findsOneWidget);

      server.listStatus = 200;
      await _tapVisible(t, find.text('Yeniden dene'));
      await t.pump(const Duration(milliseconds: 100));
      expect(find.text('Yeniden dene'), findsNothing);
      expect(find.byType(Checkbox), findsOneWidget);
    });

    testWidgets('"Yeniden dene" çift dokunuşta tek istek açar', (t) async {
      final server = FakeLegalServer()..listStatus = 500;
      await _pumpPage(t, server);
      expect(server.count('GET', '/public/legal-documents'), 1);
      server.listStatus = 200;
      server.listGate = Completer<void>();
      final retry = find.text('Yeniden dene');
      await t.ensureVisible(retry);
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(retry);
      await t.pump();
      // İkinci dokunuş: düğme artık yok / pasif; ikinci istek açılmaz.
      await t.tap(find.byType(TextButton).first, warnIfMissed: false);
      await t.pump();
      server.listGate!.complete();
      await t.pump(const Duration(milliseconds: 100));
      expect(server.count('GET', '/public/legal-documents'), 2);
    });

    testWidgets('belge bağlantısı belgeyi açar; geri dönünce işaret ve form korunur', (t) async {
      final server = FakeLegalServer();
      server.contents['terms'] = '# Koşullar\n\n**Madde 1** metni';
      await _pumpPage(t, server, height: 1400);
      await _fill(t);
      await _tapVisible(t, find.byType(Checkbox));

      await _tapVisible(t, find.text('Kullanım Koşulları metnini oku'));
      await t.pump(const Duration(milliseconds: 500));
      expect(find.textContaining('Madde 1', findRichText: true), findsOneWidget);
      expect(server.count('GET', '/public/legal-documents/terms'), 1);

      final navigator = t.state<NavigatorState>(find.byType(Navigator).first);
      navigator.pop();
      await t.pump(const Duration(milliseconds: 500));
      expect(t.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
      expect(t.widget<TextFormField>(_fields.at(0)).controller!.text, 'Ali');
    });

    testWidgets('sunucu "onay gerekli / belgeler güncellendi" derse işaret kalkar ve belgeler yeniden okunur', (t) async {
      final server = FakeLegalServer();
      final auth = _FakeAuth(error: LegalMessages.consentVersionStale);
      await _pumpPage(t, server, auth: auth);
      await _fill(t);
      await _tapVisible(t, find.byType(Checkbox));
      server.documents = standardLegalDocs(version: '2026-12-01');
      await _tapVisible(t, _registerButton);
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text(LegalMessages.consentVersionStale), findsOneWidget);
      expect(server.count('GET', '/public/legal-documents'), 2);
      expect(t.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
      expect(_button(t).onPressed, isNull);
    });

    testWidgets('gönderim sürerken kutu ve bağlantılar pasif; çift dokunma tek kayıt çağrısı', (t) async {
      final gate = Completer<String?>();
      final auth = _GateAuth(gate);
      await _pumpPage(t, FakeLegalServer(), auth: auth);
      await _fill(t);
      await _tapVisible(t, find.byType(Checkbox));
      await _tapVisible(t, _registerButton);
      await t.tap(_registerButton, warnIfMissed: false);
      await t.pump();
      expect(auth.calls, 1);
      expect(t.widget<Checkbox>(find.byType(Checkbox)).onChanged, isNull);
      gate.complete('hata');
      await t.pump(const Duration(milliseconds: 400));
    });

    testWidgets('pasif "Kayıt Ol" düğmesinin NEDENİ düğmeye bağlıdır (ipucu); işaretleyince kalkar', (t) async {
      final semantics = t.ensureSemantics();
      try {
        await _pumpPage(t, FakeLegalServer(), height: 1400);
        expect(t.getSemantics(_registerButton).hint, contains('onay kutusunu işaretleyin'));
        await _tapVisible(t, find.byType(Checkbox));
        expect(t.getSemantics(_registerButton).hint, isEmpty);
      } finally {
        semantics.dispose();
      }
    });

    testWidgets('belgeler yüklenemediyse düğme ipucu "Yeniden dene"yi söyler', (t) async {
      final semantics = t.ensureSemantics();
      try {
        await _pumpPage(t, FakeLegalServer()..listStatus = 500, height: 1400);
        expect(t.getSemantics(_registerButton).hint, contains('Yeniden dene'));
      } finally {
        semantics.dispose();
      }
    });

    testWidgets('ekran okuyucu: kutu + etiket tek öğe, bağlantı düğmeleri ayrı ve adlı', (t) async {
      final semantics = t.ensureSemantics();
      try {
        await _pumpPage(t, FakeLegalServer(), height: 1400);
        final node = t.getSemantics(find.byType(Checkbox));
        expect(node.label, contains("Kullanım Koşulları, Gizlilik Politikası ve KVKK Aydınlatma Metni'ni okudum."));
        for (final label in const <String>[
          'Kullanım Koşulları metnini oku',
          'Gizlilik Politikası metnini oku',
          'KVKK Aydınlatma Metni metnini oku',
        ]) {
          expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
        }
      } finally {
        semantics.dispose();
      }
    });

    for (final (w, h, s) in const <(double, double, double)>[
      (320, 640, 2.0),
      (360, 640, 1.5),
      (640, 360, 2.0), // yatay + büyük yazı
    ]) {
      for (final dark in const <bool>[false, true]) {
        final cell = '${w.toInt()}x${h.toInt()} x$s ${dark ? 'koyu' : 'açık'}';

        testWidgets('taşma yok: yükleniyor / hazır / hata / boş durumları ($cell)', (t) async {
          // Yükleniyor
          final loading = FakeLegalServer()..listGate = Completer<void>();
          await _pumpPage(t, loading, width: w, height: h, scale: s, dark: dark);
          expect(t.takeException(), isNull);
          loading.listGate!.complete();
          await t.pump(const Duration(milliseconds: 100));
          // Hazır
          await _pumpPage(t, FakeLegalServer(), width: w, height: h, scale: s, dark: dark);
          expect(find.byType(Checkbox), findsOneWidget);
          await t.ensureVisible(find.byType(Checkbox));
          await t.pump();
          expect(t.takeException(), isNull);
          // Hata
          await _pumpPage(t, FakeLegalServer()..listStatus = 500, width: w, height: h, scale: s, dark: dark);
          await t.ensureVisible(find.text('Yeniden dene'));
          await t.pump();
          expect(t.takeException(), isNull);
          // Boş
          await _pumpPage(
            t,
            FakeLegalServer(documents: <Map<String, dynamic>>[]),
            width: w,
            height: h,
            scale: s,
            dark: dark,
          );
          expect(t.takeException(), isNull);
        });

        testWidgets('klavye açıkken (yatay + alt boşluk) "Kayıt Ol" ve kutu kaydırarak erişilir ($cell)', (t) async {
          // Yatay + klavye: kısa ve geniş pencere, alt kenarda klavye boşluğu.
          t.view.viewInsets = const FakeViewPadding(bottom: 260);
          addTearDown(t.view.resetViewInsets);
          await _pumpPage(t, FakeLegalServer(), width: 640, height: 360, scale: s, dark: dark);
          await t.ensureVisible(find.byType(Checkbox));
          await t.pump(const Duration(milliseconds: 300));
          await t.ensureVisible(_registerButton);
          await t.pump(const Duration(milliseconds: 300));
          expect(t.takeException(), isNull);
          expect(_registerButton, findsOneWidget);
        });
      }
    }
  });
}

class _GateAuth extends _FakeAuth {
  _GateAuth(this.gate);

  final Completer<String?> gate;
  int calls = 0;

  @override
  Future<String?> registerIndividual({
    required String firstName,
    required String lastName,
    required String email,
    required String password,
    List<AcceptedDocument>? acceptedDocuments,
  }) {
    calls++;
    return gate.future;
  }
}
