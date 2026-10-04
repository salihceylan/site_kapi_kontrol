// FAZ 5 / A2-G5: SubmitJoinRequestDialog taşma testi (AGENTS.md kural 6).
//
// `Dialog`: başlık şeridi AppDialogHeader, gövde tek kaydırma alanında; kod alanı ile "Tara" düğmesi
// büyük yazıda alt alta dizilir.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/site_join_info.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/icon_orb.dart';
import 'package:site_kapi_kontrol/ui/design/skeleton.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/submit_join_request_dialog.dart';

import '../design/harness.dart';
import 'dialog_layout_harness.dart';

class _FakeAuth extends AuthService {
  _FakeAuth({this.error}) : super(api: AuthApi(baseUrl: 'http://localhost'));

  final String? error;
  final List<int> submitted = [];

  @override
  Future<(SiteJoinInfo?, String?)> fetchSiteJoinInfo(String joinToken) async {
    if (error != null) return (null, error);
    return (
      const SiteJoinInfo(
        siteCode: 101,
        siteName: 'Güneş Sitesi Uzun İsimli Konutları Yönetimi',
        city: 'İstanbul',
        district: 'Kadıköy',
        token: 'SJT-ABC123',
        blocks: [
          SiteJoinBlockInfo(id: 11, blockName: 'A Blok Uzun Adlı Blok İsmi'),
          SiteJoinBlockInfo(id: 12, blockName: 'B Blok'),
        ],
        apartments: [
          SiteJoinApartmentInfo(
            id: 501,
            blockId: 11,
            unitLabel: 'Daire 12 (Kat 3)',
          ),
          SiteJoinApartmentInfo(
            id: 502,
            blockId: 11,
            unitLabel: 'Daire 13 (Kat 3)',
          ),
          SiteJoinApartmentInfo(id: 601, blockId: 12, unitLabel: 'Daire 1'),
        ],
      ),
      null,
    );
  }

  @override
  Future<(Map<String, dynamic>?, String?)> submitJoinRequest({
    required String joinToken,
    int? blockId,
    required int apartmentId,
    String? notes,
  }) async {
    submitted.add(apartmentId);
    return (<String, dynamic>{'message': 'Başvurunuz iletildi.'}, null);
  }
}

/// Site bilgisi isteği [gate] açılana kadar bekler (yükleniyor durumu sınanır).
class _SlowAuth extends _FakeAuth {
  final Completer<void> gate = Completer<void>();

  @override
  Future<(SiteJoinInfo?, String?)> fetchSiteJoinInfo(String joinToken) async {
    await gate.future;
    return super.fetchSiteJoinInfo(joinToken);
  }
}

Future<void> _open(
  WidgetTester t,
  _FakeAuth auth, {
  String? initialToken,
  required double width,
  required double height,
  required double scale,
  required bool dark,
}) async {
  await openDialogAt(
    t,
    (context) => SubmitJoinRequestDialog.show(
      context,
      authService: auth,
      initialToken: initialToken,
    ),
    width: width,
    height: height,
    scale: scale,
    dark: dark,
  );
  await settleFor(t);
}

void main() {
  layoutMatrix('SubmitJoinRequestDialog (kod girişi + Tara + Getir)', (
    t,
    width,
    height,
    scale,
    dark,
  ) async {
    await _open(
      t,
      _FakeAuth(),
      width: width,
      height: height,
      scale: scale,
      dark: dark,
    );

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(AppDialogHeader), findsOneWidget);
    expect(find.text('Siteye Katıl'), findsOneWidget);
    expect(find.text('Tara'), findsOneWidget);
    expect(find.text('Site Bilgilerini Getir'), findsNothing);

    await t.enterText(find.byType(TextField).first, 'SJT-ABC123');
    await settleFor(t);
    await scrollTo(t, find.text('Site Bilgilerini Getir'));
    expect(find.text('Site Bilgilerini Getir'), findsOneWidget);
  });

  layoutMatrix(
    'SubmitJoinRequestDialog (site bulundu: blok/daire seçimi + gönder)',
    (t, width, height, scale, dark) async {
      final auth = _FakeAuth();
      await _open(
        t,
        auth,
        initialToken: 'SJT-ABC123',
        width: width,
        height: height,
        scale: scale,
        dark: dark,
      );

      expect(
        find.text('Güneş Sitesi Uzun İsimli Konutları Yönetimi'),
        findsOneWidget,
      );
      expect(find.text('Değiştir'), findsOneWidget);
      await scrollTo(t, find.text('Blok Seçiniz'));
      await scrollTo(t, find.text('Daire Seçiniz'));
      await scrollTo(t, find.text('Katılım Başvurusunu Gönder'));
      await t.tap(find.text('Katılım Başvurusunu Gönder'));
      await settleFor(t, 800);
      expect(auth.submitted, [501]);
    },
  );

  layoutMatrix('SubmitJoinRequestDialog (site bulunamadı: InlineNotice)', (
    t,
    width,
    height,
    scale,
    dark,
  ) async {
    await _open(
      t,
      _FakeAuth(
        error:
            'Bu katılım kodu geçersiz ya da süresi dolmuş; lütfen site yöneticisinden yeni kod isteyin.',
      ),
      initialToken: 'SJT-YANLIS',
      width: width,
      height: height,
      scale: scale,
      dark: dark,
    );

    expect(find.byType(InlineNotice), findsOneWidget);
    await scrollTo(t, find.byType(InlineNotice));
  });

  testWidgets(
    'SubmitJoinRequestDialog: site bulununca site kartı (rozet + konum rozeti) ve ortak dilde açılır listeler',
    (t) async {
      await _open(
        t,
        _FakeAuth(),
        initialToken: 'SJT-ABC123',
        width: 360,
        height: 1000,
        scale: 1.0,
        dark: false,
      );

      // Site kartı: 40 dp squircle rozet + konum rozeti; mevcut metinler aynen.
      final card = find.ancestor(
        of: find.text('Güneş Sitesi Uzun İsimli Konutları Yönetimi'),
        matching: find.byType(AppCard),
      );
      expect(card, findsOneWidget);
      final orb = t.widget<IconOrb>(
        find.descendant(of: card, matching: find.byType(IconOrb)),
      );
      expect(orb.size, 40);
      expect(orb.shape, IconOrbShape.squircle);
      final location = find.widgetWithText(StatusChip, 'İstanbul / Kadıköy');
      expect(location, findsOneWidget);
      expect(t.widget<StatusChip>(location).tone, AppTone.info);
      expect(find.text('Değiştir'), findsOneWidget);

      // Açılır listeler: ortak dil.
      final palette = t.element(find.byType(Dialog)).palette;
      final body = Theme.of(t.element(find.byType(Dialog))).textTheme.bodyLarge;
      void expectSharedStyle(DropdownButton<Object?> dropdown, String which) {
        expect(dropdown.borderRadius, BorderRadius.circular(AppRadius.md), reason: which);
        expect(dropdown.dropdownColor, palette.surface, reason: which);
        expect(dropdown.menuMaxHeight, 320, reason: which);
        expect((dropdown.icon! as Icon).icon, Icons.keyboard_arrow_down_rounded, reason: which);
        expect(dropdown.style, body, reason: which);
      }

      expectSharedStyle(
        t.widget<DropdownButton<SiteJoinBlockInfo>>(find.byType(DropdownButton<SiteJoinBlockInfo>)),
        'blok',
      );
      expectSharedStyle(
        t.widget<DropdownButton<SiteJoinApartmentInfo>>(
          find.byType(DropdownButton<SiteJoinApartmentInfo>),
        ),
        'daire',
      );

      // Blok değişince daire listesi güncellenir (davranış korunur).
      await t.tap(find.byType(DropdownButton<SiteJoinBlockInfo>));
      await settleFor(t);
      await t.tap(find.text('B Blok').last);
      await settleFor(t);
      expect(find.text('Daire 1'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'SubmitJoinRequestDialog: site bilgisi yüklenirken iskelet (dönen gösterge yok), sonra kart; ticker kalmaz',
    (t) async {
      final auth = _SlowAuth();
      await _open(
        t,
        auth,
        initialToken: 'SJT-ABC123',
        width: 360,
        height: 900,
        scale: 1.0,
        dark: false,
      );

      expect(find.byType(SkeletonBox), findsNWidgets(3));
      expect(find.text('Site bilgileri yükleniyor...'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      auth.gate.complete();
      await settleFor(t, 800);
      expect(find.byType(SkeletonBox), findsNothing);
      expect(find.text('Site bilgileri yükleniyor...'), findsNothing);
      expect(
        find.text('Güneş Sitesi Uzun İsimli Konutları Yönetimi'),
        findsOneWidget,
      );
      expect(t.binding.transientCallbackCount, 0, reason: 'iskelet kalkınca shimmer ticker kalmaz');
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'SubmitJoinRequestDialog: başvuru başarısında hafif haptik verir; hatada vermez',
    (t) async {
      final haptics = recordHaptics(t);
      // Hata: site bulunamadı.
      await _open(
        t,
        _FakeAuth(error: 'Kod geçersiz.'),
        initialToken: 'SJT-YANLIS',
        width: 360,
        height: 900,
        scale: 1.0,
        dark: false,
      );
      expect(find.text('Kod geçersiz.'), findsOneWidget);
      expect(haptics, isEmpty);

      // Başarı.
      final auth = _FakeAuth();
      await _open(
        t,
        auth,
        initialToken: 'SJT-ABC123',
        width: 360,
        height: 1000,
        scale: 1.0,
        dark: false,
      );
      await scrollTo(t, find.text('Katılım Başvurusunu Gönder'));
      await t.tap(find.text('Katılım Başvurusunu Gönder'));
      await settleFor(t, 800);
      expect(auth.submitted, [501]);
      expect(haptics, ['HapticFeedbackType.lightImpact']);
      expect(find.byType(Dialog), findsNothing);
    },
  );
}
