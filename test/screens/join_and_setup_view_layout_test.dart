// FAZ 5 / A2-G4: JoinAndSetupView ("Daireye Katıl & Cihaz Ekle") taşma ve davranış testleri.
//
// AGENTS.md kural 6: 320x640 x2,0 ve 360x640 x1,5, açık + koyu tema (pumpAt). Çözülen bulgu: başlık
// ("Sit…", "Yön…") ve düğme etiketi ("QR / Kod ile Daireye…") kırpılıyordu; başlık+rozet aynı satırdaydı.
// Kural 7: RefreshIndicator korunur; düğmelerden dönünce başvurular yeniden yüklenir.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/views/join_and_setup_view.dart';

import '../design/harness.dart';
import 'g4_test_support.dart';

const UserSession _session = UserSession(
  token: 'test_token',
  id: 1,
  fullName: 'Ahmet Ceylan',
  email: 'ahmet@example.com',
  loginName: 'ahmet',
  role: UserRole.individual,
  isActive: true,
);

class _Taps {
  int claim = 0;
  int join = 0;
  int refreshAll = 0;
}

Widget _view(G4Auth auth, _Taps taps) {
  return JoinAndSetupView(
    authService: auth,
    session: _session,
    onOpenClaimDevice: () => taps.claim++,
    onOpenJoinSite: () => taps.join++,
    onRefreshAll: () => taps.refreshAll++,
  );
}

Future<void> _tapVisible(WidgetTester t, Finder finder) async {
  await t.ensureVisible(finder);
  await t.pump();
  await t.tap(finder);
}

void main() {
  group('taşma matrisi', () {
    g4LayoutMatrix('başvurulu görünüm (3 durum)', (
      t,
      width,
      height,
      scale,
      dark,
    ) async {
      final auth = G4Auth(requests: g4Requests());
      await pumpAt(
        t,
        _view(auth, _Taps()),
        width: width,
        height: height,
        scale: scale,
        dark: dark,
      );

      expect(find.text('Daireye Katıl & Cihaz Ekle'), findsOneWidget);
      expect(find.text('Site Sakini Girişi'), findsOneWidget);
      expect(find.text('Daireye Katıl'), findsOneWidget);
      expect(find.text('Yönetici & Cihaz Kurulumu'), findsOneWidget);
      expect(find.text('Yönetici Ol'), findsOneWidget);
      expect(find.text('QR / Kod ile Daireye Katıl'), findsOneWidget);
      expect(find.text('Cihaz Ekleyerek Site Yöneticisi Ol'), findsOneWidget);
      expect(find.text('Katılım Başvurularım'), findsOneWidget);
      expect(find.text('Güneş Sitesi'), findsOneWidget);
      expect(find.text('A Blok • Daire 12'), findsOneWidget);
      expect(find.text('Not: "Daireye taşındım, kiracıyım"'), findsOneWidget);
      expect(
        find.text('Site #103'),
        findsOneWidget,
        reason: 'site adı yoksa kod gösterilir (mevcut davranış)',
      );
      expect(find.text('Daire 5'), findsOneWidget);
      expect(find.text('Daire 8'), findsOneWidget);
      expect(find.text('Onay Bekliyor'), findsOneWidget);
      expect(find.text('Onaylandı'), findsOneWidget);
      expect(find.text('Reddedildi'), findsOneWidget);
    });

    g4LayoutMatrix('başvurusuz görünüm (yalnız iki kurulum kartı)', (
      t,
      width,
      height,
      scale,
      dark,
    ) async {
      await pumpAt(
        t,
        _view(G4Auth(), _Taps()),
        width: width,
        height: height,
        scale: scale,
        dark: dark,
      );

      expect(find.text('Katılım Başvurularım'), findsNothing);
      expect(find.text('Site Sakini Girişi'), findsOneWidget);
      expect(find.text('Yönetici & Cihaz Kurulumu'), findsOneWidget);
    });
  });

  group('başlık + rozet kırpılmaz', () {
    testWidgets(
      'dar ekranda rozet başlığın ALTINA iner; ikisi de tam metindir',
      (t) async {
        await pumpAt(
          t,
          _view(G4Auth(), _Taps()),
          width: 320,
          scale: 2.0,
          height: 2400,
        );

        for (final (title, badge) in const <(String, String)>[
          ('Site Sakini Girişi', 'Daireye Katıl'),
          ('Yönetici & Cihaz Kurulumu', 'Yönetici Ol'),
        ]) {
          final titleBottom = t.getBottomLeft(find.text(title)).dy;
          final badgeTop = t
              .getTopLeft(find.widgetWithText(StatusChip, badge))
              .dy;
          expect(
            badgeTop,
            greaterThanOrEqualTo(titleBottom - 0.5),
            reason: '"$badge" rozeti "$title" başlığının altında',
          );
          expect(
            g4IsEllipsized(t, find.text(title)),
            isFalse,
            reason: 'başlık kırpılmaz',
          );
          expect(
            t.widget<Text>(find.text(title)).overflow,
            isNot(TextOverflow.ellipsis),
          );
        }
      },
    );

    testWidgets(
      'geniş ekranda (820 px, 1,0x) rozet başlıkla aynı satırda durur',
      (t) async {
        await pumpAt(
          t,
          _view(G4Auth(), _Taps()),
          width: 820,
          scale: 1.0,
          height: 1400,
        );

        final titleTop = t.getTopLeft(find.text('Site Sakini Girişi')).dy;
        final titleBottom = t.getBottomLeft(find.text('Site Sakini Girişi')).dy;
        final badgeTop = t
            .getTopLeft(find.widgetWithText(StatusChip, 'Daireye Katıl'))
            .dy;
        expect(
          badgeTop,
          lessThan(titleBottom),
          reason: 'aynı satır: rozetin üstü başlığın altından önce başlar',
        );
        expect(badgeTop, greaterThan(titleTop - 40));
      },
    );

    testWidgets(
      'düğme etiketleri 2 satıra sarar (elips yok) ve ElevatedButton olarak kalır',
      (t) async {
        await pumpAt(
          t,
          _view(G4Auth(), _Taps()),
          width: 320,
          scale: 2.0,
          height: 2400,
        );

        expect(
          find.widgetWithText(ElevatedButton, 'QR / Kod ile Daireye Katıl'),
          findsOneWidget,
        );
        expect(
          find.widgetWithText(
            ElevatedButton,
            'Cihaz Ekleyerek Site Yöneticisi Ol',
          ),
          findsOneWidget,
        );
        for (final label in const <String>[
          'QR / Kod ile Daireye Katıl',
          'Cihaz Ekleyerek Site Yöneticisi Ol',
        ]) {
          expect(
            t.widget<Text>(find.text(label)).overflow,
            isNot(TextOverflow.ellipsis),
            reason: label,
          );
          expect(
            t.widget<Text>(find.text(label)).maxLines,
            isNull,
            reason: 'sınırsız satır: etiket kırpılmaz',
          );
        }
      },
    );
  });

  group('davranış (Kural 7 korunur)', () {
    testWidgets(
      'düğmeler geri çağrıları tetikler ve başvurular yeniden yüklenir',
      (t) async {
        final auth = G4Auth(requests: g4Requests());
        final taps = _Taps();
        await pumpAt(
          t,
          _view(auth, taps),
          width: 360,
          scale: 1.0,
          height: 1400,
        );
        final initialCalls = auth.requestCalls;

        await _tapVisible(t, find.text('QR / Kod ile Daireye Katıl'));
        await t.pump();
        expect(taps.join, 1);
        expect(
          auth.requestCalls,
          initialCalls + 1,
          reason: 'diyalogdan dönünce başvurular otomatik yenilenir',
        );

        await _tapVisible(t, find.text('Cihaz Ekleyerek Site Yöneticisi Ol'));
        await t.pump();
        expect(taps.claim, 1);
        expect(auth.requestCalls, initialCalls + 2);
      },
    );

    testWidgets('başvuru bölümü yenile düğmesi listeyi yeniden çeker', (
      t,
    ) async {
      final auth = G4Auth(requests: g4Requests());
      await pumpAt(
        t,
        _view(auth, _Taps()),
        width: 360,
        scale: 1.0,
        height: 1400,
      );
      final calls = auth.requestCalls;

      await _tapVisible(t, find.byTooltip('Yenile'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      expect(auth.requestCalls, calls + 1);
    });

    testWidgets(
      'RefreshIndicator korunur: yenileme başvuruları yeniden çeker ve üst sayfayı yeniler',
      (t) async {
        final auth = G4Auth(requests: g4Requests());
        final taps = _Taps();
        await pumpAt(t, _view(auth, taps), width: 360, scale: 1.0, height: 900);
        expect(find.byType(RefreshIndicator), findsOneWidget);
        final calls = auth.requestCalls;

        await t
            .widget<RefreshIndicator>(find.byType(RefreshIndicator))
            .onRefresh();
        await t.pump();

        expect(auth.requestCalls, calls + 1);
        expect(taps.refreshAll, 1);
      },
    );

    testWidgets(
      'başvuru durumu tonları: onaylı=başarı, reddedilmiş=hata, bekleyen=uyarı',
      (t) async {
        final auth = G4Auth(requests: g4Requests());
        await pumpAt(
          t,
          _view(auth, _Taps()),
          width: 360,
          scale: 1.0,
          height: 1400,
        );

        AppTone toneOf(String label) =>
            t.widget<StatusChip>(find.widgetWithText(StatusChip, label)).tone;
        expect(toneOf('Onaylandı'), AppTone.success);
        expect(toneOf('Reddedildi'), AppTone.danger);
        expect(toneOf('Onay Bekliyor'), AppTone.warning);
      },
    );

    testWidgets(
      'yenilenirken (yükleme sürerken) bölüm düğmesi devre dışı ve gösterge döner (E2E "meşgul" tespiti korunur)',
      (t) async {
        final auth = G4Auth(requests: g4Requests());
        await pumpAt(
          t,
          _view(auth, _Taps()),
          width: 360,
          scale: 1.0,
          height: 1400,
        );
        expect(find.byType(CircularProgressIndicator), findsNothing);

        // Yeniden yükleme: istek tamamlanana kadar bekletilir.
        auth.gate = Completer<void>();
        await _tapVisible(t, find.byTooltip('Yenile'));
        await t.pump();
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        final button = t.widget<IconButton>(
          find.byWidgetPredicate(
            (w) => w is IconButton && w.tooltip == 'Yenile',
          ),
        );
        expect(button.onPressed, isNull);

        auth.gate!.complete();
        await t.pump();
        await t.pump(const Duration(milliseconds: 100));
        expect(find.byType(CircularProgressIndicator), findsNothing);
      },
    );
  });
}
