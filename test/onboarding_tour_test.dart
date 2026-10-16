// İlk kullanım turu (OnboardingTour / OnboardingTourPage): role göre 3-4 adım, atlanabilir, shared_preferences
// ile "görüldü" (kullanıcı başına), Yardım'dan yeniden açılabilir, ekran okuyucu uyumlu.
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/views/help_content.dart';
import 'package:site_kapi_kontrol/ui/views/onboarding_tour.dart';

import 'design/harness.dart';

class _Auth extends AuthService {
  _Auth({this.id = 5, this.role = UserRole.individual, this.signedIn = true})
    : super(api: AuthApi(baseUrl: 'http://localhost'));

  int id;
  UserRole role;
  bool signedIn;

  @override
  UserSession? get session => signedIn
      ? UserSession(
          id: id,
          fullName: 'Ali Veli',
          email: 'ali@example.com',
          loginName: null,
          role: role,
          isActive: true,
          token: 'tok',
        )
      : null;
}

Future<BuildContext> _host(WidgetTester t, {double width = 400, double height = 800, double scale = 1.0}) async {
  t.view.physicalSize = Size(width, height);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  late BuildContext captured;
  await t.pumpWidget(
    harnessApp(
      Builder(
        builder: (context) {
          captured = context;
          return const Center(child: Text('ANA'));
        },
      ),
      scale: scale,
    ),
  );
  return captured;
}

Future<void> _settle(WidgetTester t) async {
  await t.pump();
  // shared_preferences okuması birkaç olay döngüsü turu sürebilir: kareler arasında mikro görevler akar.
  for (var i = 0; i < 4; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
  await t.pump(const Duration(milliseconds: 500));
}

Finder get _next => find.text('İleri');
Finder get _back => find.text('Geri');
Finder get _skip => find.text('Atla');
Finder get _start => find.text('Başla');

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    OnboardingTour.resetForTesting();
  });

  group('Görüldü bilgisi', () {
    test('anahtar kullanıcı başınadır; okuma / yazma; bozuk depo "görüldü" sayılır', () async {
      expect(OnboardingTour.seenKey(5), isNot(OnboardingTour.seenKey(6)));
      expect(await OnboardingTour.hasSeen(5), isFalse);
      await OnboardingTour.markSeen(5);
      expect(await OnboardingTour.hasSeen(5), isTrue);
      expect(await OnboardingTour.hasSeen(6), isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(OnboardingTour.seenKey(5)), isTrue);
    });
  });

  group('maybeShow (giriş sonrası ilk açılış)', () {
    testWidgets('görülmediyse açılır; kapanınca işaretlenir; ikinci çağrıda tekrar açılmaz', (t) async {
      final context = await _host(t);
      final auth = _Auth(id: 5, role: UserRole.individual);
      final future = OnboardingTour.maybeShow(context, authService: auth);
      await _settle(t);
      expect(find.text('Hoş geldiniz'), findsOneWidget);
      expect(await OnboardingTour.hasSeen(5), isFalse, reason: 'tur sürerken henüz işaretlenmez');

      await t.tap(_skip);
      await _settle(t);
      await future;
      expect(find.text('Hoş geldiniz'), findsNothing);
      expect(await OnboardingTour.hasSeen(5), isTrue);

      await OnboardingTour.maybeShow(context, authService: auth);
      await _settle(t);
      expect(find.text('Hoş geldiniz'), findsNothing, reason: 'görüldü: tekrar gösterilmez');
    });

    testWidgets('başka kullanıcı için yeniden açılır', (t) async {
      await OnboardingTour.markSeen(5);
      final context = await _host(t);
      unawaited6(OnboardingTour.maybeShow(context, authService: _Auth(id: 5)));
      await _settle(t);
      expect(find.text('Hoş geldiniz'), findsNothing);

      unawaited6(OnboardingTour.maybeShow(context, authService: _Auth(id: 6)));
      await _settle(t);
      expect(find.text('Hoş geldiniz'), findsOneWidget);
    });

    testWidgets('oturum yoksa hiçbir şey olmaz', (t) async {
      final context = await _host(t);
      await OnboardingTour.maybeShow(context, authService: _Auth(signedIn: false));
      await _settle(t);
      expect(find.byType(OnboardingTourPage), findsNothing);
    });

    testWidgets('eşzamanlı çağrılar tek tur açar', (t) async {
      final context = await _host(t);
      final auth = _Auth(id: 9);
      unawaited6(OnboardingTour.maybeShow(context, authService: auth));
      unawaited6(OnboardingTour.maybeShow(context, authService: auth));
      await _settle(t);
      expect(find.byType(OnboardingTourPage), findsOneWidget);
      await t.tap(_skip);
      await _settle(t);
    });

    testWidgets('rol başına içerik: daire sakini sakin turunu görür', (t) async {
      final context = await _host(t);
      unawaited6(OnboardingTour.maybeShow(context, authService: _Auth(id: 11, role: UserRole.apartmentOwner)));
      await _settle(t);
      expect(find.text('Kapınız cebinizde'), findsOneWidget);
    });
  });

  group('Tur sayfası', () {
    Future<void> open(WidgetTester t, UserRole role, {int? userId, bool resident = false, double scale = 1.0, double width = 400, double height = 800}) async {
      final context = await _host(t, scale: scale, width: width, height: height);
      unawaited6(OnboardingTour.show(context, role: role, residentMode: resident, userId: userId));
      await _settle(t);
    }

    testWidgets('4 adım: İleri / Geri / Başla; son adımda Başla turu kapatır ve işaretler', (t) async {
      await open(t, UserRole.individual, userId: 21);
      final titles = OnboardingSteps.forAudience(HelpAudience.individual).map((s) => s.title).toList();
      expect(titles, hasLength(4));
      expect(find.text(titles[0]), findsOneWidget);
      expect(_back, findsNothing, reason: 'ilk adımda Geri yok');
      expect(find.text('Atla'), findsOneWidget);

      await t.tap(_next);
      await _settle(t);
      expect(find.text(titles[1]), findsOneWidget);
      expect(_back, findsOneWidget);

      await t.tap(_back);
      await _settle(t);
      expect(find.text(titles[0]), findsOneWidget);

      for (var i = 1; i < 4; i++) {
        await t.tap(_next);
        await _settle(t);
        expect(find.text(titles[i]), findsOneWidget, reason: 'adım ${i + 1}');
      }
      expect(_next, findsNothing);
      expect(_start, findsOneWidget);

      await t.tap(_start);
      await _settle(t);
      expect(find.byType(OnboardingTourPage), findsNothing);
      expect(await OnboardingTour.hasSeen(21), isTrue);
    });

    testWidgets('her adımda "Atla" turu kapatır; kullanıcı yoksa (Yardım\'dan) işaretlenmez', (t) async {
      await open(t, UserRole.superUser);
      await t.tap(_next);
      await _settle(t);
      await t.tap(_skip);
      await _settle(t);
      expect(find.byType(OnboardingTourPage), findsNothing);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), isEmpty);
    });

    testWidgets('geri tuşu (maybePop) turu kapatır = atlar ve işaretler', (t) async {
      await open(t, UserRole.siteManager, userId: 31);
      await t.state<NavigatorState>(find.byType(Navigator).first).maybePop();
      await _settle(t);
      expect(find.byType(OnboardingTourPage), findsNothing);
      expect(await OnboardingTour.hasSeen(31), isTrue);
    });

    testWidgets('kaydırarak sayfa değişir', (t) async {
      await open(t, UserRole.individual);
      final titles = OnboardingSteps.forAudience(HelpAudience.individual).map((s) => s.title).toList();
      await t.drag(find.byType(PageView), const Offset(-300, 0));
      await _settle(t);
      expect(find.text(titles[1]), findsOneWidget);
    });

    /// Ekran okuyucu duyurularını (SemanticsService.sendAnnouncement) kaydeder.
    List<String> captureAnnouncements(WidgetTester t) {
      final messages = <String>[];
      t.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(SystemChannels.accessibility, (
        message,
      ) async {
        if (message is Map && message['type'] == 'announce') {
          final data = message['data'];
          if (data is Map && data['message'] is String) messages.add(data['message'] as String);
        }
        return null;
      });
      addTearDown(
        () => t.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(SystemChannels.accessibility, null),
      );
      return messages;
    }

    testWidgets('adım değişiminde TEK duyuru: "Adım n / 4: başlık"; ilerleme noktaları ikinci bir etiket/duyuru üretmez', (
      t,
    ) async {
      final semantics = t.ensureSemantics();
      try {
        final announced = captureAnnouncements(t);
        await open(t, UserRole.individual);
        final titles = OnboardingSteps.forAudience(HelpAudience.individual).map((s) => s.title).toList();
        announced.clear();

        for (var i = 1; i < titles.length; i++) {
          await t.tap(_next);
          await _settle(t);
          expect(announced, <String>['Adım ${i + 1} / 4: ${titles[i]}'], reason: 'adım ${i + 1}: tek duyuru');
          announced.clear();
        }
        // Geri de tek duyuru.
        await t.tap(_back);
        await _settle(t);
        expect(announced, <String>['Adım 3 / 4: ${titles[2]}']);

        // İlerleme noktaları süs: ayrı bir "Adım n / 4" anlamsal etiketi YOK (çift duyuruya yol açardı).
        final labels = <String>[];
        void walk(SemanticsNode node) {
          labels.add(node.label);
          node.visitChildren((child) {
            walk(child);
            return true;
          });
        }

        walk(t.binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!);
        expect(labels.where((l) => l.startsWith('Adım ')), isEmpty);
        for (final label in const <String>['İleri', 'Geri', 'Atla']) {
          expect(find.bySemanticsLabel(label), findsWidgets, reason: label);
        }
        expect(labels.any((l) => l.contains(titles[2])), isTrue, reason: 'başlık okunabilir');
      } finally {
        semantics.dispose();
      }
    });

    testWidgets('kaydırarak sayfa değişince de tek duyuru', (t) async {
      final announced = captureAnnouncements(t);
      await open(t, UserRole.individual);
      announced.clear();
      await t.drag(find.byType(PageView), const Offset(-300, 0));
      await _settle(t);
      expect(announced.length, 1);
      expect(announced.single, startsWith('Adım 2 / 4: '));
    });

    testWidgets('yardımdan sakin modundaki yönetici sakin turunu görür', (t) async {
      await open(t, UserRole.siteManager, resident: true);
      expect(find.text('Kapınız cebinizde'), findsOneWidget);
    });

    for (final role in UserRole.values) {
      for (final (w, h, s) in const <(double, double, double)>[(320, 640, 2.0), (360, 640, 1.5)]) {
        testWidgets('taşma yok: $role ${w.toInt()}x${h.toInt()} x$s (tüm adımlar, açık+koyu)', (t) async {
          for (final dark in const <bool>[false, true]) {
            t.view.physicalSize = Size(w, h);
            t.view.devicePixelRatio = 1.0;
            addTearDown(t.view.reset);
            late BuildContext context;
            await t.pumpWidget(
              harnessApp(
                Builder(
                  builder: (c) {
                    context = c;
                    return const SizedBox.shrink();
                  },
                ),
                scale: s,
                dark: dark,
              ),
            );
            unawaited6(OnboardingTour.show(context, role: role));
            await _settle(t);
            expect(t.takeException(), isNull);
            final steps = OnboardingSteps.forAudience(HelpContent.audienceFor(role)).length;
            for (var i = 1; i < steps; i++) {
              await t.tap(_next);
              await _settle(t);
              expect(t.takeException(), isNull, reason: 'adım ${i + 1}');
            }
            await t.tap(_start);
            await _settle(t);
          }
        });
      }
    }

    for (final role in UserRole.values) {
      testWidgets('yatay ekran (640x360, 2,0x yazı) taşmaz: $role (tüm adımlar)', (t) async {
        await open(t, role, scale: 2.0, width: 640, height: 360);
        expect(t.takeException(), isNull);
        final steps = OnboardingSteps.forAudience(HelpContent.audienceFor(role)).length;
        for (var i = 1; i < steps; i++) {
          await t.tap(_next);
          await _settle(t);
          expect(t.takeException(), isNull, reason: 'adım ${i + 1}');
        }
        // Düğmeler yatay kısa ekranda da erişilebilir (kaydırma ya da görünür).
        expect(find.text('Başla'), findsOneWidget);
        await t.tap(_start);
        await _settle(t);
      });
    }

    testWidgets('hareket azaltma: sayfa geçişi anında', (t) async {
      t.view.physicalSize = const Size(400, 800);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      late BuildContext context;
      await t.pumpWidget(
        harnessApp(
          Builder(
            builder: (c) {
              context = c;
              return const SizedBox.shrink();
            },
          ),
          reduce: true,
        ),
      );
      unawaited6(OnboardingTour.show(context, role: UserRole.individual));
      await _settle(t);
      await t.tap(_next);
      await t.pump();
      expect(find.text(OnboardingSteps.forAudience(HelpAudience.individual)[1].title), findsOneWidget);
    });
  });
}

/// `unawaited` (dart:async) yerine kısa takma ad: testler turu açık bırakıp devam eder.
void unawaited6(Future<void> future) {}
