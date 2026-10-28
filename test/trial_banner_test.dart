// Deneme erişim kodu oturumunda üstteki şerit (P2-27, karar K10): "Deneme - X saat kaldı".
// Kapsam: metin + zamanla yenilenme, süre dolumunda tek bildirim, kök çerçevesi (şerit yalnız deneme oturumunda; sayfa yığını
// yeniden kurulmaz), taşma matrisi (AGENTS.md kural 6), erişilebilirlik (metin okunur).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/styles/app_theme.dart';
import 'package:site_kapi_kontrol/ui/design/status_dot.dart';
import 'package:site_kapi_kontrol/ui/widgets/trial_banner.dart';

import 'design/harness.dart';

/// Oturumu test belirler; ağa çıkmaz.
class _FakeAuth extends AuthService {
  _FakeAuth() : super(api: AuthApi(baseUrl: 'http://localhost'));

  UserSession? current;
  int refreshes = 0;

  @override
  UserSession? get session => current;

  @override
  Future<void> refreshSession({bool force = false}) async {
    refreshes += 1;
  }

  void setSession(UserSession? value) {
    current = value;
    notifyListeners();
  }
}

UserSession _session({DateTime? trialExpiresAt}) => UserSession(
      id: 20099,
      fullName: 'Deneme Kullanıcısı 7',
      email: 'trial-aa@deneme.invalid',
      loginName: null,
      role: UserRole.siteManager,
      isActive: true,
      token: 'tok',
      trialExpiresAt: trialExpiresAt,
    );

class _Probe extends StatefulWidget {
  const _Probe(this.onInit);
  final VoidCallback onInit;
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    widget.onInit();
  }

  @override
  Widget build(BuildContext context) => const Center(child: Text('ICERIK'));
}

Widget _app(_FakeAuth auth, {VoidCallback? onInit, bool dark = false, double scale = 1.0}) {
  return MaterialApp(
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    themeMode: dark ? ThemeMode.dark : ThemeMode.light,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
      child: TrialBannerFrame(authService: auth, child: child ?? const SizedBox.shrink()),
    ),
    home: Scaffold(body: _Probe(onInit ?? () {})),
  );
}

void main() {
  group('TrialBanner', () {
    testWidgets('metin kalan süreden üretilir ve zamanla yenilenir', (t) async {
      var now = DateTime(2026, 11, 1, 10);
      final expires = now.add(const Duration(hours: 72));
      await t.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: TrialBanner(expiresAt: expires, now: () => now, tick: const Duration(seconds: 1)),
        ),
      ));
      expect(find.text('Deneme - 72 saat kaldı'), findsOneWidget);
      now = now.add(const Duration(hours: 24, minutes: 30));
      await t.pump(const Duration(seconds: 1));
      expect(find.text('Deneme - 48 saat kaldı'), findsOneWidget);
      now = expires.subtract(const Duration(minutes: 20));
      await t.pump(const Duration(seconds: 1));
      expect(find.text('Deneme - 20 dakika kaldı'), findsOneWidget);
      await t.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('süre dolunca "Deneme süresi doldu" gösterilir ve onExpired TEK kez çağrılır', (t) async {
      var now = DateTime(2026, 11, 1, 10);
      final expires = now.add(const Duration(minutes: 1));
      var expiredCalls = 0;
      await t.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: TrialBanner(
            expiresAt: expires,
            now: () => now,
            tick: const Duration(seconds: 1),
            onExpired: () => expiredCalls += 1,
          ),
        ),
      ));
      expect(expiredCalls, 0);
      now = expires.add(const Duration(seconds: 1));
      await t.pump(const Duration(seconds: 1));
      await t.pump();
      expect(find.text('Deneme süresi doldu'), findsOneWidget);
      expect(expiredCalls, 1);
      await t.pump(const Duration(seconds: 3));
      expect(expiredCalls, 1, reason: 'tekrar bildirilmez');
      await t.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('süresi baştan dolmuş oturum açılışta bir kez bildirir', (t) async {
      var expiredCalls = 0;
      await t.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: TrialBanner(
            expiresAt: DateTime.now().subtract(const Duration(minutes: 5)),
            onExpired: () => expiredCalls += 1,
          ),
        ),
      ));
      await t.pump();
      expect(find.text('Deneme süresi doldu'), findsOneWidget);
      expect(expiredCalls, 1);
      await t.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('durum noktası + metin (sade stil); metin ekran okuyucuya açık', (t) async {
      final handle = t.ensureSemantics();
      await t.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: TrialBanner(expiresAt: DateTime.now().add(const Duration(hours: 5)))),
      ));
      expect(find.byType(StatusDot), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^Deneme - \d+ saat kaldı$')), findsOneWidget);
      handle.dispose();
      await t.pumpWidget(const SizedBox.shrink());
    });

    for (final (width, scale) in const <(double, double)>[(320, 2.0), (360, 1.5), (412, 1.0), (820, 1.0)]) {
      for (final dark in const <bool>[false, true]) {
        testWidgets('taşma yok: ${width.toInt()} dp x$scale ${dark ? 'koyu' : 'açık'}', (t) async {
          await pumpAt(
            t,
            SizedBox(
              width: width,
              child: TrialBanner(expiresAt: DateTime.now().add(const Duration(hours: 71, minutes: 30))),
            ),
            width: width,
            scale: scale,
            dark: dark,
          );
          expect(find.text('Deneme - 72 saat kaldı'), findsOneWidget);
          await t.pumpWidget(const SizedBox.shrink());
        });
      }
    }
  });

  group('TrialBannerFrame', () {
    testWidgets('normal oturumda ve oturumsuzken şerit YOK; içerik tam ekranı kaplar', (t) async {
      final auth = _FakeAuth()..current = _session();
      await t.pumpWidget(_app(auth));
      expect(find.byType(TrialBanner), findsNothing);
      expect(t.getSize(find.text('ICERIK')), isNotNull);
      final fullHeight = t.getSize(find.byType(Scaffold)).height;
      expect(fullHeight, t.view.physicalSize.height / t.view.devicePixelRatio);
      auth.setSession(null);
      await t.pump();
      expect(find.byType(TrialBanner), findsNothing);
    });

    testWidgets('deneme oturumunda içeriğin ÜSTÜNDE şerit görünür; içerik şerit kadar küçülür; çıkışta kalkar', (t) async {
      final auth = _FakeAuth()..current = _session(trialExpiresAt: DateTime.now().add(const Duration(hours: 71, minutes: 10)));
      await t.pumpWidget(_app(auth));
      expect(find.byType(TrialBanner), findsOneWidget);
      expect(find.text('Deneme - 72 saat kaldı'), findsOneWidget);
      final bannerBox = t.getRect(find.byType(TrialBanner));
      final scaffoldBox = t.getRect(find.byType(Scaffold));
      expect(bannerBox.top, 0);
      expect(scaffoldBox.top, bannerBox.bottom, reason: 'içerik şeridin hemen altında başlar');
      expect(bannerBox.width, t.view.physicalSize.width / t.view.devicePixelRatio, reason: 'şerit tam genişlik');
      auth.setSession(null);
      await t.pump();
      expect(find.byType(TrialBanner), findsNothing);
      expect(t.getRect(find.byType(Scaffold)).top, 0);
      await t.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('sayfa yığını yeniden kurulmaz: deneme oturumu açılıp kapanırken içerik aynı State ile kalır', (t) async {
      var inits = 0;
      final auth = _FakeAuth()..current = _session();
      await t.pumpWidget(_app(auth, onInit: () => inits += 1));
      expect(inits, 1);
      auth.setSession(_session(trialExpiresAt: DateTime.now().add(const Duration(hours: 72))));
      await t.pump();
      expect(find.byType(TrialBanner), findsOneWidget);
      auth.setSession(_session());
      await t.pump();
      auth.setSession(_session(trialExpiresAt: DateTime.now().add(const Duration(hours: 10))));
      await t.pump();
      expect(inits, 1, reason: 'Navigator / sayfa yığını şerit nedeniyle yeniden kurulmamalı');
      await t.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('süre dolunca kök oturumu sunucuyla doğrular (refreshSession force)', (t) async {
      final auth = _FakeAuth()..current = _session(trialExpiresAt: DateTime.now().subtract(const Duration(seconds: 2)));
      await t.pumpWidget(_app(auth));
      await t.pump();
      await t.pump();
      expect(auth.refreshes, 1);
      expect(find.text('Deneme süresi doldu'), findsOneWidget);
      await t.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('üst güvenli alan: şerit çentiği kendisi karşılar, içerik üst boşluğu ikinci kez eklemez', (t) async {
      final auth = _FakeAuth()..current = _session(trialExpiresAt: DateTime.now().add(const Duration(hours: 5)));
      t.view.physicalSize = const Size(360, 640);
      t.view.devicePixelRatio = 1.0;
      t.view.padding = const FakeViewPadding(top: 40);
      t.view.viewPadding = const FakeViewPadding(top: 40);
      addTearDown(t.view.reset);
      double? contentTopPadding;
      await t.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        builder: (context, child) => TrialBannerFrame(authService: auth, child: child ?? const SizedBox.shrink()),
        home: Builder(builder: (context) {
          contentTopPadding = MediaQuery.paddingOf(context).top;
          return const Scaffold(body: Center(child: Text('ICERIK')));
        }),
      ));
      expect(contentTopPadding, 0, reason: 'çentik şeritte karşılandı');
      final banner = t.getRect(find.byType(TrialBanner));
      expect(banner.height, greaterThan(40), reason: 'şerit çentik boşluğunu içerir');
      await t.pumpWidget(const SizedBox.shrink());
    });

    for (final (width, scale) in const <(double, double)>[(320, 2.0), (360, 1.5)]) {
      testWidgets('çerçeve taşma yok: ${width.toInt()} dp x$scale', (t) async {
        final auth = _FakeAuth()..current = _session(trialExpiresAt: DateTime.now().add(const Duration(hours: 71)));
        t.view.physicalSize = Size(width, 640);
        t.view.devicePixelRatio = 1.0;
        addTearDown(t.view.reset);
        await t.pumpWidget(_app(auth, scale: scale));
        await t.pump(const Duration(milliseconds: 300));
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox.shrink());
      });
    }
  });
}
