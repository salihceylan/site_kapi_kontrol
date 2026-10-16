// "Güncellenen koşullar" kapısı (LegalConsentGate + LegalConsentPage): giriş sonrası GET /me/consents.
//
// pending boşsa hiçbir şey görünmez; doluysa tam ekran onay; hata / zaman aşımında kullanıcı KİLİTLENMEZ
// (uygulama açılır, sonra yeniden dener); 401'de oturum doğrulanır; onay / ret / çift dokunma / bayat sürüm.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/legal_document.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/legal_api.dart';
import 'package:site_kapi_kontrol/styles/app_theme.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/views/legal_consent_gate.dart';

import 'legal_fixtures.dart';

class _Auth extends AuthService {
  _Auth() : super(api: AuthApi(baseUrl: 'http://localhost'));

  bool signedIn = true;
  int logouts = 0;
  int refreshes = 0;

  @override
  UserSession? get session => signedIn
      ? const UserSession(
          id: 5,
          fullName: 'Ali Veli',
          email: 'ali@example.com',
          loginName: null,
          role: UserRole.individual,
          isActive: true,
          token: 'tok-5',
        )
      : null;

  @override
  bool get isLoggedIn => signedIn;

  @override
  Future<void> refreshSession({bool force = false}) async {
    refreshes++;
  }

  @override
  Future<void> logout() async {
    logouts++;
    signedIn = false;
    notifyListeners();
  }
}

Map<String, dynamic> _pendingDoc(String id, String title, String version) =>
    <String, dynamic>{'id': id, 'title': title, 'version': version};

List<Map<String, dynamic>> _twoPending() => <Map<String, dynamic>>[
  _pendingDoc('terms', 'Kullanım Koşulları', '2026-11-01'),
  _pendingDoc('privacy', 'Gizlilik Politikası', '2026-11-01'),
];

/// POST /me/consents çağrısını verilen hatayla düşüren API (GET'ler sahte sunucudan gelir).
class _ThrowingApi extends LegalApi {
  _ThrowingApi(FakeLegalServer server, this.error)
    : super(baseUrl: 'https://api.example.test', client: server.client);

  final Object error;

  @override
  Future<ConsentAcceptResult> acceptDocuments({
    required String token,
    required List<AcceptedDocument> documents,
  }) async => throw error;
}

int _settled = 0;

Widget _app(
  _Auth auth,
  FakeLegalServer server, {
  LegalApi? api,
  double scale = 1.0,
  bool dark = false,
  bool enabled = true,
  Duration recheckAfter = const Duration(hours: 6),
  Duration resumeRecheckGap = Duration.zero,
  DateTime Function()? clock,
  List<Duration> retryDelays = const <Duration>[Duration(seconds: 5), Duration(seconds: 20)],
}) {
  return MaterialApp(
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    themeMode: dark ? ThemeMode.dark : ThemeMode.light,
    builder: (c, child) => MediaQuery(
      data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: LegalConsentGate(
      authService: auth,
      api: api ?? server.api,
      enabled: enabled,
      recheckAfter: recheckAfter,
      resumeRecheckGap: resumeRecheckGap,
      clock: clock,
      retryDelays: retryDelays,
      onSettled: (_) => _settled++,
      child: Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const <Widget>[Text('ANA SAYFA'), SizedBox(width: 200, child: TextField())],
          ),
        ),
      ),
    ),
  );
}

Future<void> _pump(
  WidgetTester t,
  _Auth auth,
  FakeLegalServer server, {
  LegalApi? api,
  double width = 400,
  double height = 900,
  double scale = 1.0,
  bool dark = false,
  bool enabled = true,
  Duration recheckAfter = const Duration(hours: 6),
  Duration resumeRecheckGap = Duration.zero,
  DateTime Function()? clock,
}) async {
  t.view.physicalSize = Size(width, height);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    _app(
      auth,
      server,
      api: api,
      scale: scale,
      dark: dark,
      enabled: enabled,
      recheckAfter: recheckAfter,
      resumeRecheckGap: resumeRecheckGap,
      clock: clock,
    ),
  );
  await t.pump(); // ilk kare -> post-frame denetimi başlar
  await t.pump(const Duration(milliseconds: 100)); // sahte yanıt
  await t.pump(const Duration(milliseconds: 300)); // geçiş animasyonları
}

Future<void> _tap(WidgetTester t, Finder finder) async {
  await t.pump(const Duration(milliseconds: 300));
  await t.ensureVisible(finder);
  await t.pump();
  await t.pump(const Duration(milliseconds: 300));
  await t.tap(finder);
  await t.pump();
}

Future<void> _disposeTree(WidgetTester t) async {
  await t.pumpWidget(const SizedBox.shrink());
}

Finder get _overlayTitle => find.text('Güncellenen Koşullar');
Finder get _accept => find.widgetWithText(PrimaryActionButton, 'Kabul Et ve Devam Et');

void main() {
  setUp(() => _settled = 0);

  group('Bekleyen yok / etkin değil', () {
    testWidgets('pending boş: hiçbir şey görünmez; tek GET /me/consents (Bearer); onSettled bir kez', (t) async {
      final server = FakeLegalServer();
      await _pump(t, _Auth(), server);
      expect(_overlayTitle, findsNothing);
      expect(find.text('ANA SAYFA'), findsOneWidget);
      expect(server.count('GET', '/me/consents'), 1);
      expect(server.requests.single.headers['Authorization'], 'Bearer tok-5');
      expect(_settled, 1);
      await _disposeTree(t);
    });

    testWidgets('enabled:false: kapı şeffaf, ağ çağrısı ve onSettled yok', (t) async {
      final server = FakeLegalServer()..pending = _twoPending();
      await _pump(t, _Auth(), server, enabled: false);
      expect(_overlayTitle, findsNothing);
      expect(find.text('ANA SAYFA'), findsOneWidget);
      expect(server.requests, isEmpty);
      expect(_settled, 0);
      await _disposeTree(t);
    });
  });

  group('Bekleyen belge var', () {
    testWidgets('tam ekran onay: belgeler, alttaki sayfa odak/ekran okuyucudan dışlanır, onSettled bekler', (t) async {
      final semantics = t.ensureSemantics();
      try {
        final server = FakeLegalServer()..pending = _twoPending();
        await _pump(t, _Auth(), server);
        expect(_overlayTitle, findsOneWidget);
        expect(find.text('Kullanım Koşulları'), findsOneWidget);
        expect(find.text('Gizlilik Politikası'), findsOneWidget);
        expect(find.text('Sürüm: 2026-11-01'), findsNWidgets(2));
        expect(find.text('Kullanım Koşulları metnini oku'), findsOneWidget);
        expect(_settled, 0, reason: 'onay verilene dek ilk kullanım turu başlamaz');

        // Alttaki ana sayfa ağaçta DURUR (durumu korunur) ama dışlanır.
        expect(find.text('ANA SAYFA', skipOffstage: false), findsOneWidget);
        final labels = <String>[];
        void walk(SemanticsNode node) {
          labels.add(node.label);
          node.visitChildren((child) {
            walk(child);
            return true;
          });
        }

        walk(t.binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!);
        expect(labels.any((l) => l.contains('ANA SAYFA')), isFalse, reason: 'alttaki sayfa ekran okuyucudan dışlanır');
        expect(labels.any((l) => l.contains('Güncellenen Koşullar')), isTrue, reason: labels.join(' | '));
        final home = find.text('ANA SAYFA', skipOffstage: false);
        final excludeFocus = find.ancestor(of: home, matching: find.byType(ExcludeFocus));
        expect(t.widgetList<ExcludeFocus>(excludeFocus).any((w) => w.excluding), isTrue);
        final ignore = find.ancestor(of: home, matching: find.byType(IgnorePointer));
        expect(t.widgetList<IgnorePointer>(ignore).any((w) => w.ignoring), isTrue);
        // Başlık anlamsal başlık olarak okunur.
        final headers = <String>[];
        void collect(SemanticsNode node) {
          if (node.flagsCollection.isHeader) headers.add(node.label);
          node.visitChildren((child) {
            collect(child);
            return true;
          });
        }

        collect(t.binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!);
        expect(headers.any((l) => l.contains('Güncellenen Koşullar')), isTrue);
      } finally {
        semantics.dispose();
      }
      await _disposeTree(t);
    });

    testWidgets('onay kutusu işaretlenmeden kapalı ve neden yazılı; işaretleyince POST, kapı kalkar, onSettled', (t) async {
      final server = FakeLegalServer()..pending = _twoPending();
      await _pump(t, _Auth(), server);
      expect(t.widget<PrimaryActionButton>(_accept).onPressed, isNull);
      expect(find.text('Devam etmek için belgeleri okuyup onay kutusunu işaretleyin.'), findsOneWidget);

      await _tap(t, find.byType(Checkbox));
      expect(t.widget<PrimaryActionButton>(_accept).onPressed, isNotNull);
      expect(find.text('Devam etmek için belgeleri okuyup onay kutusunu işaretleyin.'), findsNothing);

      await _tap(t, _accept);
      await t.pump(const Duration(milliseconds: 400));
      expect(server.lastJsonBody('POST', '/me/consents'), <String, dynamic>{
        'documents': <Map<String, dynamic>>[
          <String, dynamic>{'id': 'terms', 'version': '2026-11-01'},
          <String, dynamic>{'id': 'privacy', 'version': '2026-11-01'},
        ],
      });
      expect(server.where('POST', '/me/consents').single.headers['Authorization'], 'Bearer tok-5');
      expect(_overlayTitle, findsNothing);
      expect(_settled, 1);
      await _disposeTree(t);
    });

    testWidgets('çift dokunma tek POST açar; gönderim sürerken düğme yükleniyor', (t) async {
      final server = FakeLegalServer()
        ..pending = _twoPending()
        ..acceptGate = Completer<void>();
      await _pump(t, _Auth(), server);
      await _tap(t, find.byType(Checkbox));
      await _tap(t, _accept);
      await t.tap(find.byType(PrimaryActionButton), warnIfMissed: false);
      await t.pump();
      expect(t.widget<PrimaryActionButton>(find.byType(PrimaryActionButton)).loading, isTrue);
      expect(server.count('POST', '/me/consents'), 1);
      server.acceptGate!.complete();
      await t.pump(const Duration(milliseconds: 400));
      expect(_overlayTitle, findsNothing);
      await _disposeTree(t);
    });

    testWidgets('onaydan sonra sunucu hâlâ bekleyen bildirirse kapı yeni listeyle açık kalır', (t) async {
      final server = FakeLegalServer()
        ..pending = _twoPending()
        ..acceptRemainingPending = <Map<String, dynamic>>[_pendingDoc('dpa', 'Veri İşleme Sözleşmesi', '2026-11-01')];
      await _pump(t, _Auth(), server);
      await _tap(t, find.byType(Checkbox));
      await _tap(t, _accept);
      await t.pump(const Duration(milliseconds: 400));
      expect(_overlayTitle, findsOneWidget);
      expect(find.text('Veri İşleme Sözleşmesi'), findsOneWidget);
      expect(find.text('Gizlilik Politikası'), findsNothing);
      expect(t.widget<Checkbox>(find.byType(Checkbox)).value, isFalse, reason: 'yeni belge için yeniden onay gerekir');
      expect(_settled, 0);
      await _disposeTree(t);
    });

    testWidgets('409 CONSENT_VERSION_STALE: ileti, bekleyen listesi yeniden okunur, işaret kalkar', (t) async {
      final server = FakeLegalServer()
        ..pending = _twoPending()
        ..acceptStatus = 409
        ..acceptErrorBody = <String, dynamic>{
          'error': 'Sürüm eski',
          'code': 'CONSENT_VERSION_STALE',
          'stale': <Object>[
            <String, dynamic>{'id': 'terms', 'current_version': '2026-12-01'},
          ],
        };
      await _pump(t, _Auth(), server);
      await _tap(t, find.byType(Checkbox));
      // Sunucu bu arada yeni sürümü yayımladı.
      server.pending = <Map<String, dynamic>>[
        _pendingDoc('terms', 'Kullanım Koşulları', '2026-12-01'),
        _pendingDoc('privacy', 'Gizlilik Politikası', '2026-11-01'),
      ];
      await _tap(t, _accept);
      await t.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('Belgeler güncellendi'), findsOneWidget);
      expect(server.count('GET', '/me/consents'), 2);
      expect(find.text('Sürüm: 2026-12-01'), findsOneWidget);
      expect(t.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
      expect(t.widget<PrimaryActionButton>(_accept).onPressed, isNull);
      await _disposeTree(t);
    });

    testWidgets('POST ağ hatası: ileti gösterilir, kapı açık kalır, yeniden denenebilir', (t) async {
      final server = FakeLegalServer()
        ..pending = _twoPending()
        ..acceptStatus = 503
        ..acceptErrorBody = <String, dynamic>{'error': 'Geçici hata', 'code': 'X'};
      await _pump(t, _Auth(), server);
      await _tap(t, find.byType(Checkbox));
      await _tap(t, _accept);
      await t.pump(const Duration(milliseconds: 400));
      expect(_overlayTitle, findsOneWidget);
      expect(find.text('Geçici hata'), findsOneWidget);
      expect(t.widget<PrimaryActionButton>(_accept).onPressed, isNotNull);

      server.acceptStatus = 200;
      await _tap(t, _accept);
      await t.pump(const Duration(milliseconds: 400));
      expect(_overlayTitle, findsNothing);
      await _disposeTree(t);
    });

    testWidgets('POST 429: düğme geçici kilitlenir ve süre dolunca açılır', (t) async {
      final server = FakeLegalServer()
        ..pending = _twoPending()
        ..acceptStatus = 429
        ..acceptErrorBody = <String, dynamic>{'error': 'Çok sık', 'code': 'RATE_LIMITED', 'retry_after_seconds': 2};
      await _pump(t, _Auth(), server);
      await _tap(t, find.byType(Checkbox));
      await _tap(t, _accept);
      await t.pump(const Duration(milliseconds: 400));
      expect(t.widget<PrimaryActionButton>(_accept).onPressed, isNull);
      expect(find.textContaining('Çok sık deneme yapıldı'), findsOneWidget);
      await t.pump(const Duration(seconds: 3));
      expect(t.widget<PrimaryActionButton>(_accept).onPressed, isNotNull);
      await _disposeTree(t);
    });

    testWidgets('reddet: onay penceresi; Vazgeç kapıyı korur, "Oturumu Kapat" çıkış yapar', (t) async {
      final auth = _Auth();
      final server = FakeLegalServer()..pending = _twoPending();
      await _pump(t, auth, server);
      await _tap(t, find.text('Kabul etmiyorum, oturumu kapat'));
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('Oturum kapatılsın mı?'), findsOneWidget);

      await t.tap(find.text('Vazgeç'));
      await t.pump(const Duration(milliseconds: 400));
      expect(auth.logouts, 0);
      expect(_overlayTitle, findsOneWidget);

      await _tap(t, find.text('Kabul etmiyorum, oturumu kapat'));
      await t.pump(const Duration(milliseconds: 400));
      await t.tap(find.text('Oturumu Kapat'));
      await t.pump(const Duration(milliseconds: 400));
      expect(auth.logouts, 1);
      await _disposeTree(t);
    });

    testWidgets('belge metni açılır; geri dönünce kapı ve işaret korunur', (t) async {
      final server = FakeLegalServer()..pending = _twoPending();
      server.documents = <Map<String, dynamic>>[
        legalDoc('terms', title: 'Kullanım Koşulları', version: '2026-11-01'),
        legalDoc('privacy', title: 'Gizlilik Politikası', version: '2026-11-01'),
      ];
      server.contents['terms'] = '# Koşullar\n\nMadde **bir**';
      await _pump(t, _Auth(), server);
      await _tap(t, find.byType(Checkbox));
      await _tap(t, find.text('Kullanım Koşulları metnini oku'));
      await t.pump(const Duration(milliseconds: 500));
      expect(find.textContaining('Madde', findRichText: true), findsOneWidget);
      t.state<NavigatorState>(find.byType(Navigator).first).pop();
      await t.pump(const Duration(milliseconds: 500));
      expect(_overlayTitle, findsOneWidget);
      expect(t.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
      await _disposeTree(t);
    });

    for (final (w, h, s) in const <(double, double, double)>[
      (320, 640, 2.0),
      (360, 640, 1.5),
      (640, 360, 2.0), // yatay + büyük yazı
    ]) {
      for (final dark in const <bool>[false, true]) {
        testWidgets('taşma yok: üç belge + hata (${w.toInt()}x${h.toInt()} x$s ${dark ? 'koyu' : 'açık'})', (t) async {
          final server = FakeLegalServer()
            ..pending = <Map<String, dynamic>>[
              ..._twoPending(),
              _pendingDoc('kvkk_notice', 'KVKK Aydınlatma Metni ve Açık Rıza Beyanı (Uzun Ad)', '2026-11-01'),
            ]
            ..acceptStatus = 500
            ..acceptErrorBody = <String, dynamic>{'error': 'Sunucuda beklenmeyen bir hata oluştu', 'code': 'X'};
          await _pump(t, _Auth(), server, width: w, height: h, scale: s, dark: dark);
          expect(t.takeException(), isNull);
          await _tap(t, find.byType(Checkbox));
          await _tap(t, _accept);
          await t.pump(const Duration(milliseconds: 400));
          await t.ensureVisible(find.textContaining('Sunucuda beklenmeyen'));
          await t.pump();
          expect(t.takeException(), isNull);
          await _disposeTree(t);
        });
      }
    }
  });

  group('Hata / zaman aşımı: kullanıcı kilitlenmez', () {
    testWidgets('500: uygulama açılır, kapı yok, onSettled çağrılır; gecikmeden sonra yeniden dener ve bekleyen görünce açar', (
      t,
    ) async {
      final server = FakeLegalServer()..consentsStatus = 500;
      await _pump(t, _Auth(), server);
      expect(_overlayTitle, findsNothing);
      expect(find.text('ANA SAYFA'), findsOneWidget);
      expect(_settled, 1);
      expect(server.count('GET', '/me/consents'), 1);

      // Sunucu düzeldi ve artık bekleyen belge var: ilk gecikme (5 sn) sonunda yeniden denenir.
      server
        ..consentsStatus = 200
        ..pending = _twoPending();
      await t.pump(const Duration(seconds: 6));
      await t.pump(const Duration(milliseconds: 300));
      expect(server.count('GET', '/me/consents'), 2);
      expect(_overlayTitle, findsOneWidget);
      expect(_settled, 1, reason: 'onSettled bir kez');
      await _disposeTree(t);
    });

    testWidgets('ağ kesik: artan aralıklarla yeniden dener (5 sn, sonra 20 sn)', (t) async {
      final server = FakeLegalServer()..consentsThrows = true;
      await _pump(t, _Auth(), server);
      expect(server.count('GET', '/me/consents'), 1);
      await t.pump(const Duration(seconds: 6));
      expect(server.count('GET', '/me/consents'), 2);
      await t.pump(const Duration(seconds: 10));
      expect(server.count('GET', '/me/consents'), 2, reason: 'ikinci aralık 20 sn');
      await t.pump(const Duration(seconds: 11));
      expect(server.count('GET', '/me/consents'), 3);
      await _disposeTree(t);
      // Ağaç atılınca zamanlayıcı kalmaz.
    });

    testWidgets('401: oturum sunucudan doğrulanır, yeniden deneme zamanlayıcısı kurulmaz, kapı açılmaz', (t) async {
      final auth = _Auth();
      final server = FakeLegalServer()..consentsStatus = 401;
      await _pump(t, auth, server);
      expect(auth.refreshes, 1);
      expect(_overlayTitle, findsNothing);
      await t.pump(const Duration(minutes: 1));
      expect(server.count('GET', '/me/consents'), 1);
      await _disposeTree(t);
    });

    testWidgets('uygulama öne gelince önceki hata varsa yeniden denenir; başarılıysa süre dolmadan denenmez', (t) async {
      final server = FakeLegalServer()..consentsThrows = true;
      await _pump(t, _Auth(), server);
      expect(server.count('GET', '/me/consents'), 1);
      server.consentsThrows = false;
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pump(const Duration(milliseconds: 200));
      expect(server.count('GET', '/me/consents'), 2);

      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pump(const Duration(milliseconds: 200));
      expect(server.count('GET', '/me/consents'), 2, reason: 'son denetim başarılı ve yeni');
      await _disposeTree(t);
    });
  });

  group('Bayat liste: sunucu listeyle çelişirse kapı güncel listeyi yeniden okur (R3 B6)', () {
    const refreshCases = <(int, String)>[
      (409, 'CONSENT_VERSION_STALE'),
      (409, 'DOCUMENT_INCOMPLETE'),
      (400, 'DOCUMENT_NOT_ACCEPTABLE'),
      (400, 'INVALID_ACCEPTED_DOCUMENTS'),
    ];

    for (final (status, code) in refreshCases) {
      testWidgets('POST $status $code: ileti, işaret kalkar, bekleyen listesi yeniden okunur ve yeni liste görünür', (
        t,
      ) async {
        final server = FakeLegalServer()
          ..pending = _twoPending()
          ..acceptStatus = status
          ..acceptErrorBody = <String, dynamic>{'error': 'Sunucu iletisi', 'code': code};
        await _pump(t, _Auth(), server);
        await _tap(t, find.byType(Checkbox));
        // Sunucuda liste değişti: terms artık beklemiyor, yalnız privacy kaldı.
        server.pending = <Map<String, dynamic>>[_pendingDoc('privacy', 'Gizlilik Politikası', '2026-12-01')];
        await _tap(t, _accept);
        await t.pump(const Duration(milliseconds: 400));
        expect(server.count('GET', '/me/consents'), 2, reason: code);
        expect(find.text('Kullanım Koşulları'), findsNothing, reason: code);
        expect(find.text('Sürüm: 2026-12-01'), findsOneWidget, reason: code);
        expect(t.widget<Checkbox>(find.byType(Checkbox)).value, isFalse, reason: code);
        expect(t.widget<PrimaryActionButton>(_accept).onPressed, isNull, reason: code);
        await _disposeTree(t);
      });
    }

    testWidgets('yenilenen liste BOŞSA kapı kapanır ve onSettled çağrılır', (t) async {
      final server = FakeLegalServer()
        ..pending = _twoPending()
        ..acceptStatus = 409
        ..acceptErrorBody = <String, dynamic>{'error': 'Belge tamamlanmadı', 'code': 'DOCUMENT_INCOMPLETE'};
      await _pump(t, _Auth(), server);
      await _tap(t, find.byType(Checkbox));
      server.pending = <Map<String, dynamic>>[];
      await _tap(t, _accept);
      await t.pump(const Duration(milliseconds: 400));
      expect(_overlayTitle, findsNothing);
      expect(find.text('ANA SAYFA'), findsOneWidget);
      expect(_settled, 1);
      await _disposeTree(t);
    });

    testWidgets('uygulama öne gelince kapı AÇIKKEN de yeniden denetlenir: liste boşalırsa kapı kapanır', (t) async {
      final server = FakeLegalServer()..pending = _twoPending();
      await _pump(t, _Auth(), server);
      expect(_overlayTitle, findsOneWidget);
      expect(server.count('GET', '/me/consents'), 1);

      // Belge arada tamamlanmamış / başka cihazdan onaylanmış hâle geldi.
      server.pending = <Map<String, dynamic>>[];
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pump(const Duration(milliseconds: 200));
      await t.pump(const Duration(milliseconds: 400));
      expect(server.count('GET', '/me/consents'), 2);
      expect(_overlayTitle, findsNothing);
      expect(_settled, 1);
      await _disposeTree(t);
    });

    testWidgets('öne gelişte liste DEĞİŞMİŞSE yeni liste görünür ve işaret kalkar', (t) async {
      final server = FakeLegalServer()..pending = _twoPending();
      await _pump(t, _Auth(), server);
      await _tap(t, find.byType(Checkbox));
      expect(t.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);

      server.pending = <Map<String, dynamic>>[_pendingDoc('terms', 'Kullanım Koşulları', '2027-01-01')];
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pump(const Duration(milliseconds: 200));
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('Sürüm: 2027-01-01'), findsOneWidget);
      expect(t.widget<Checkbox>(find.byType(Checkbox)).value, isFalse, reason: 'yeni sürümü görmeden onay geçerli sayılmaz');
      await _disposeTree(t);
    });

    testWidgets('öne gelişte denetim başarısızsa kapı AÇIK kalır (kilit açılmaz) ve yeniden denenir', (t) async {
      final server = FakeLegalServer()..pending = _twoPending();
      await _pump(t, _Auth(), server);
      server.consentsThrows = true;
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pump(const Duration(milliseconds: 200));
      expect(_overlayTitle, findsOneWidget, reason: 'bayat ama bilinen liste korunur');
      expect(server.count('GET', '/me/consents'), 2);

      server
        ..consentsThrows = false
        ..pending = <Map<String, dynamic>>[];
      await t.pump(const Duration(seconds: 6)); // ilk yeniden deneme aralığı (5 sn)
      await t.pump(const Duration(milliseconds: 400));
      expect(server.count('GET', '/me/consents'), 3);
      expect(_overlayTitle, findsNothing);
      await _disposeTree(t);
    });
  });

  group('Öne gelişte kısıtlama ve bekleyen denetim (R8)', () {
    testWidgets('kapı açıkken öne gelişler en az 10 sn arayla denetlenir (art arda öne gelişler sunucuyu yormaz)', (
      t,
    ) async {
      var now = DateTime(2026, 10, 16, 12);
      final server = FakeLegalServer()..pending = _twoPending();
      await _pump(t, _Auth(), server, resumeRecheckGap: const Duration(seconds: 10), clock: () => now);
      expect(server.count('GET', '/me/consents'), 1);

      // 3 sn sonra öne gelme: kısıtlı (istek yok).
      now = now.add(const Duration(seconds: 3));
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pump(const Duration(milliseconds: 200));
      expect(server.count('GET', '/me/consents'), 1);

      // 11 sn sonra: denetlenir.
      now = now.add(const Duration(seconds: 8));
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pump(const Duration(milliseconds: 200));
      expect(server.count('GET', '/me/consents'), 2);

      // Hemen yine: kısıtlı.
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pump(const Duration(milliseconds: 200));
      expect(server.count('GET', '/me/consents'), 2);

      // Tam 10 sn dolunca yeniden.
      now = now.add(const Duration(seconds: 10));
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pump(const Duration(milliseconds: 200));
      expect(server.count('GET', '/me/consents'), 3);
      await _disposeTree(t);
    });

    testWidgets('denetim sürerken gelen "bayat liste" isteği bitince BİR KEZ daha çalışır; son durum görünür', (t) async {
      final server = FakeLegalServer()..pending = _twoPending();
      await _pump(t, _Auth(), server);
      expect(server.count('GET', '/me/consents'), 1);

      // 2. denetim (öne gelme) sürüyor: yanıtı sunucunun ESKİ durumunu taşıyacak.
      server.consentsGate = Completer<void>();
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pump(const Duration(milliseconds: 100));
      expect(server.count('GET', '/me/consents'), 2);

      // Bu arada sunucuda liste değişti ve kullanıcının gönderimi bayat sürümle reddedildi (onStale -> meşgul).
      server
        ..pending = <Map<String, dynamic>>[_pendingDoc('terms', 'Kullanım Koşulları', '2027-01-01')]
        ..acceptStatus = 409
        ..acceptErrorBody = <String, dynamic>{'error': 'Sürüm eski', 'code': 'CONSENT_VERSION_STALE'};
      await _tap(t, find.byType(Checkbox));
      await _tap(t, _accept);
      await t.pump(const Duration(milliseconds: 100));
      expect(server.count('GET', '/me/consents'), 2, reason: 'sürerken yeni istek açılmaz (kuyruğa alınır)');

      // Denetim biter: önce eski anlık görüntü gelir, sonra kuyruktaki ikinci denetim güncel listeyi getirir.
      server.consentsGate!.complete();
      await t.pump(const Duration(milliseconds: 100));
      await t.pump(const Duration(milliseconds: 400));
      expect(server.count('GET', '/me/consents'), 3, reason: 'kuyruktaki istek bir kez çalıştı');
      expect(find.text('Sürüm: 2027-01-01'), findsOneWidget);
      expect(find.text('Sürüm: 2026-11-01'), findsNothing, reason: 'bayat liste bir sonraki olayı beklemedi');
      await t.pump(const Duration(seconds: 30));
      expect(server.count('GET', '/me/consents'), 3, reason: 'döngü yok: tek ek çalıştırma');
      await _disposeTree(t);
    });

    testWidgets('denetim sürerken art arda öne gelişler yeni istek açmaz', (t) async {
      final server = FakeLegalServer()..pending = _twoPending();
      await _pump(t, _Auth(), server);
      server.consentsGate = Completer<void>();
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pump(const Duration(milliseconds: 100));
      for (var i = 0; i < 5; i++) {
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      }
      await t.pump(const Duration(milliseconds: 100));
      server.consentsGate!.complete();
      await t.pump(const Duration(milliseconds: 100));
      await t.pump(const Duration(milliseconds: 400));
      expect(server.count('GET', '/me/consents'), 2, reason: 'sürerken gelen öne gelişler yeni istek açmaz');
      await _disposeTree(t);
    });
  });

  group('Gönderim hata iletileri (R4)', () {
    testWidgets('ApiException iletisi boşsa boş hata kutusu ÇIKMAZ: yedek ileti', (t) async {
      final server = FakeLegalServer()..pending = _twoPending();
      await _pump(t, _Auth(), server, api: _ThrowingApi(server, ApiException('   ', statusCode: 500)));
      await _tap(t, find.byType(Checkbox));
      await _tap(t, _accept);
      await t.pump(const Duration(milliseconds: 400));
      expect(find.byType(InlineNotice), findsOneWidget);
      expect(find.text(LegalMessages.consentSubmitFailed), findsOneWidget);
      expect(LegalMessages.consentSubmitFailed, startsWith('Onayınız gönderilemedi'));
      expect(_overlayTitle, findsOneWidget);
      await _disposeTree(t);
    });

    testWidgets('beklenmedik hata (ApiException dışı): "Belgeler yüklenemedi" DEĞİL, gönderim iletisi', (t) async {
      final server = FakeLegalServer()..pending = _twoPending();
      await _pump(t, _Auth(), server, api: _ThrowingApi(server, StateError('beklenmedik')));
      await _tap(t, find.byType(Checkbox));
      await _tap(t, _accept);
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text(LegalMessages.consentSubmitFailed), findsOneWidget);
      expect(find.textContaining('Belgeler yüklenemedi'), findsNothing);
      expect(t.widget<PrimaryActionButton>(_accept).onPressed, isNotNull, reason: 'yeniden denenebilir');
      await _disposeTree(t);
    });

    testWidgets('dolu sunucu iletisi aynen gösterilir', (t) async {
      final server = FakeLegalServer()..pending = _twoPending();
      await _pump(t, _Auth(), server, api: _ThrowingApi(server, ApiException('Sunucu şunu dedi', statusCode: 500)));
      await _tap(t, find.byType(Checkbox));
      await _tap(t, _accept);
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('Sunucu şunu dedi'), findsOneWidget);
      await _disposeTree(t);
    });
  });

  group('Pasif düğmenin nedeni düğmeye bağlı (R4)', () {
    String hintOf(WidgetTester t) => t.getSemantics(find.byType(PrimaryActionButton)).hint;

    testWidgets('onay işaretsizken düğme düğümünde neden ipucu olarak vardır; işaretleyince kalkar', (t) async {
      final semantics = t.ensureSemantics();
      try {
        final server = FakeLegalServer()..pending = _twoPending();
        await _pump(t, _Auth(), server);
        expect(hintOf(t), contains('onay kutusunu işaretleyin'));
        await _tap(t, find.byType(Checkbox));
        expect(hintOf(t), isEmpty);
      } finally {
        semantics.dispose();
      }
      await _disposeTree(t);
    });

    testWidgets('429 kilidinde ipucu hız sınırı iletisidir', (t) async {
      final semantics = t.ensureSemantics();
      try {
        final server = FakeLegalServer()
          ..pending = _twoPending()
          ..acceptStatus = 429
          ..acceptErrorBody = <String, dynamic>{'error': 'Çok sık', 'code': 'RATE_LIMITED', 'retry_after_seconds': 5};
        await _pump(t, _Auth(), server);
        await _tap(t, find.byType(Checkbox));
        await _tap(t, _accept);
        await t.pump(const Duration(milliseconds: 400));
        expect(hintOf(t), contains('Çok sık deneme yapıldı'));
        await t.pump(const Duration(seconds: 6));
        expect(hintOf(t), isEmpty);
      } finally {
        semantics.dispose();
      }
      await _disposeTree(t);
    });
  });
}
