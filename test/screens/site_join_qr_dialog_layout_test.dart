// FAZ 5 / A2-G5: SiteJoinQrDialog taşma testi (AGENTS.md kural 6).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:site_kapi_kontrol/models/site_join_token_record.dart';
import 'package:site_kapi_kontrol/models/site_record.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/icon_orb.dart';
import 'package:site_kapi_kontrol/ui/design/skeleton.dart';
import 'package:site_kapi_kontrol/ui/dialogs/site_join_qr_dialog.dart';

import '../design/harness.dart' show recordHaptics;
import 'dialog_layout_harness.dart';

class _FakeAuth extends AuthService {
  _FakeAuth({this.failWith, this.gate})
    : super(api: AuthApi(baseUrl: 'http://localhost'));

  final String? failWith;

  /// Verilirse belirteç bu tamamlanana dek "yükleniyor" kalır.
  final Completer<void>? gate;
  int rotated = 0;

  SiteJoinTokenRecord _record(String token) => SiteJoinTokenRecord(
    id: 1,
    siteCode: 1,
    siteName: 'Güneş Sitesi',
    token: token,
    qrPayload: 'SITE_JOIN:$token',
    isActive: true,
  );

  @override
  Future<SiteJoinTokenRecord> getSiteJoinToken({required int siteCode}) async {
    await gate?.future;
    if (failWith != null) throw ApiException(failWith!);
    return _record('GUNES-ABC123XYZ-UZUN-KATILIM-KODU-0001');
  }

  @override
  Future<SiteJoinTokenRecord> rotateSiteJoinToken({
    required int siteCode,
  }) async {
    rotated++;
    return _record('GUNES-YENI456XYZ-UZUN-KATILIM-KODU-0002');
  }
}

SiteRecord _site() => SiteRecord(
  id: 1,
  name: 'Güneş Sitesi Uzun İsimli Konutları Yönetimi',
  address: 'Atatürk Mah. No:1',
  city: 'Ankara',
  district: 'Çankaya',
  blockCount: 2,
  apartmentCount: 20,
  doorCount: 2,
  approvalStatus: 'approved',
  approvedAt: DateTime(2026, 1, 1),
  mqttSiteId: 101,
  managerUserCode: 1,
  managerName: 'Ali Yönetici',
  createdAt: DateTime(2026, 1, 1),
);

Future<void> _open(
  WidgetTester t,
  _FakeAuth auth, {
  required double width,
  required double height,
  required double scale,
  required bool dark,
}) async {
  await openDialogAt(
    t,
    (context) =>
        SiteJoinQrDialog.show(context, site: _site(), authService: auth),
    width: width,
    height: height,
    scale: scale,
    dark: dark,
  );
  await settleFor(t);
}

void main() {
  layoutMatrix('SiteJoinQrDialog (QR + eylemler)', (
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

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byType(AppDialogHeader), findsOneWidget);
    expect(find.text('Site Katılım QR Kodu'), findsOneWidget);
    expect(find.byTooltip('Kapat'), findsOneWidget);
    expect(find.byType(InlineNotice), findsOneWidget); // "kapıyı açmaz" bilgisi
    await scrollTo(t, find.text('Karekodu Paylaş'));
    await scrollTo(t, find.text('QR Yenile'));
    expect(find.text('Kodu Kopyala'), findsOneWidget);
  });

  layoutMatrix('SiteJoinQrDialog (token alınamadı: InlineNotice + Tekrar Dene)', (
    t,
    width,
    height,
    scale,
    dark,
  ) async {
    await _open(
      t,
      _FakeAuth(
        failWith:
            'Katılım kodu şu an alınamıyor; lütfen biraz sonra tekrar deneyin.',
      ),
      width: width,
      height: height,
      scale: scale,
      dark: dark,
    );

    expect(find.byType(InlineNotice), findsNWidgets(2));
    expect(
      find.textContaining('Katılım kodu şu an alınamıyor'),
      findsOneWidget,
    );
    await scrollTo(t, find.text('Tekrar Dene'));
    expect(find.text('Karekodu Paylaş'), findsNothing);
  });

  layoutMatrix('SiteJoinQrDialog (QR yenileme onay penceresi)', (
    t,
    width,
    height,
    scale,
    dark,
  ) async {
    final auth = _FakeAuth();
    await _open(
      t,
      auth,
      width: width,
      height: height,
      scale: scale,
      dark: dark,
    );

    await scrollTo(t, find.text('QR Yenile'));
    await t.tap(find.text('QR Yenile'));
    await settleFor(t);

    expect(find.text('QR Kodunu Yenile?'), findsOneWidget);
    expect(find.text('Vazgeç'), findsOneWidget);
    expect(find.text('Evet, Yenile'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNWidgets(2));
  });

  testWidgets(
    'SiteJoinQrDialog: onaylanınca QR yenilenir ve başarı bildirimi gösterilir',
    (t) async {
      final auth = _FakeAuth();
      await _open(t, auth, width: 360, height: 900, scale: 1.0, dark: false);

      await scrollTo(t, find.text('QR Yenile'));
      await t.tap(find.text('QR Yenile'));
      await settleFor(t);
      await t.tap(find.text('Evet, Yenile'));
      await settleFor(t, 700);

      expect(auth.rotated, 1);
      expect(
        find.text('Site katılım QR kodu başarıyla yenilendi.'),
        findsOneWidget,
      );
      expect(
        find.text('GUNES-YENI456XYZ-UZUN-KATILIM-KODU-0002'),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
    },
  );
  // --- Görsel sözleşme (cilalı safir): iskelet, çerçeveli karekod, ikon rozeti, haptik ---

  testWidgets(
    'SiteJoinQrDialog: token yüklenirken karekod boyutunda iskelet (spinner yok); yüklenince çerçeveli karekod',
    (t) async {
      final gate = Completer<void>();
      await openDialogAt(
        t,
        (context) => SiteJoinQrDialog.show(
          context,
          site: _site(),
          authService: _FakeAuth(gate: gate),
        ),
        width: 400,
        height: 1000,
        scale: 1.0,
        dark: false,
      );
      expect(find.byType(SkeletonBox), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byKey(const ValueKey<String>('site_join_qr_frame')), findsNothing);

      gate.complete();
      await settleFor(t);
      expect(find.byType(SkeletonBox), findsNothing);
      final frame = find.byKey(const ValueKey<String>('site_join_qr_frame'));
      expect(frame, findsOneWidget);
      // Karekod her temada beyaz zemin üstünde (okunabilirlik) ve çerçevenin İÇİNDEDİR.
      final qr = find.descendant(of: frame, matching: find.byType(QrImageView));
      expect(qr, findsOneWidget);
      expect(t.widget<QrImageView>(qr).backgroundColor, Colors.white);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'SiteJoinQrDialog: site kartı ikon rozetli; kodu kopyalamak hafif haptik verir ve bildirir',
    (t) async {
      final haptics = recordHaptics(t);
      await _open(
        t,
        _FakeAuth(),
        width: 400,
        height: 1000,
        scale: 1.0,
        dark: false,
      );

      // Diyalog başlığı + site kartı rozetleri.
      expect(find.byType(IconOrb), findsAtLeastNWidgets(2));
      await scrollTo(t, find.text('Kodu Kopyala'));
      await t.tap(find.text('Kodu Kopyala'));
      await settleFor(t);

      expect(haptics, contains('HapticFeedbackType.lightImpact'));
      expect(find.text('Katılım bilgisi panoya kopyalandı.'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
}
