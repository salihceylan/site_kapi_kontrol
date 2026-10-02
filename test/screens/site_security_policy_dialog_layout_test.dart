// FAZ 5 / A2-G5: SiteSecurityPolicyDialog taşma testi (AGENTS.md kural 6).
//
// `Dialog`: başlık şeridi + düğme satırı sabit, politika alanları tek kaydırma alanında; büyük yazıda
// enlem/boylam alt alta dizilir.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/site_record.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/widgets/site_security_policy_dialog.dart';

import 'dialog_layout_harness.dart';

SiteRecord _site({
  bool requireGeofence = true,
  double? lat,
  double? lng,
  int radius = 100,
  int qrRotation = 30,
}) => SiteRecord(
  id: 1,
  name: 'Çok uzun isimli bir site adı: Güneş Mahallesi Konutları 2. Etap',
  address: null,
  city: null,
  district: null,
  blockCount: 1,
  apartmentCount: 10,
  doorCount: 1,
  approvalStatus: 'approved',
  approvedAt: null,
  mqttSiteId: 1,
  managerUserCode: null,
  managerName: null,
  requireGeofence: requireGeofence,
  geofenceLatitude: lat,
  geofenceLongitude: lng,
  geofenceRadiusMeters: radius,
  qrRotationSeconds: qrRotation,
  createdAt: DateTime(2026, 1, 1),
);

class _Saved {
  bool called = false;
  bool? requireGeofence;
  int? radius;
}

Future<_Saved> _open(
  WidgetTester t,
  SiteRecord site, {
  bool isSuperUser = true,
  required double width,
  required double height,
  required double scale,
  required bool dark,
}) async {
  final saved = _Saved();
  await openDialogAt(
    t,
    (context) => showDialog<bool>(
      context: context,
      builder: (_) => SiteSecurityPolicyDialog(
        site: site,
        isSuperUser: isSuperUser,
        onSave:
            ({
              required bool featureRemoteOpenEnabled,
              required bool featureQrEnabled,
              required bool featureGuestPassEnabled,
              required bool qrEntryActive,
              required bool requireGeofence,
              required double? geofenceLatitude,
              required double? geofenceLongitude,
              required int geofenceRadiusMeters,
              required int qrRotationSeconds,
            }) async {
              saved.called = true;
              saved.requireGeofence = requireGeofence;
              saved.radius = geofenceRadiusMeters;
            },
      ),
    ),
    width: width,
    height: height,
    scale: scale,
    dark: dark,
  );
  return saved;
}

void main() {
  layoutMatrix(
    'SiteSecurityPolicyDialog (süper kullanıcı, konum doğrulaması açık)',
    (t, width, height, scale, dark) async {
      await _open(
        t,
        _site(lat: 41.0082, lng: 28.9784),
        width: width,
        height: height,
        scale: scale,
        dark: dark,
      );

      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(AppDialogHeader), findsOneWidget);
      expect(find.text('Giriş & Güvenlik Politikaları'), findsOneWidget);
      expect(find.byType(AppCard), findsNWidgets(3)); // üç giriş yöntemi kartı

      await scrollTo(t, find.text('Mevcut Konumu Al'));
      await scrollTo(t, find.text('İzin Verilen Azami Mesafe:'));
      await scrollTo(t, find.byType(Slider));
      // Düğme satırı sabittir ve her zaman erişilebilir.
      expect(find.text('Değişiklikleri Kaydet'), findsOneWidget);
      expect(find.text('İptal'), findsOneWidget);
    },
  );

  layoutMatrix(
    'SiteSecurityPolicyDialog (boş koordinatla kaydet: hata iletileri)',
    (t, width, height, scale, dark) async {
      final saved = await _open(
        t,
        _site(),
        width: width,
        height: height,
        scale: scale,
        dark: dark,
      );

      await scrollTo(t, find.text('Değişiklikleri Kaydet'));
      await t.tap(find.text('Değişiklikleri Kaydet'));
      await settleFor(t, 700);

      expect(saved.called, isFalse);
      expect(find.text('Geçerli bir enlem girin.'), findsOneWidget);
      expect(find.text('Geçerli bir boylam girin.'), findsOneWidget);
      // Hata bildirimi (SnackBar) da gösterilir.
      expect(
        find.text(
          'Konum doğrulaması açıkken geçerli enlem, boylam ve mesafe girilmelidir.',
        ),
        findsOneWidget,
      );
      await scrollTo(t, find.text('Geçerli bir boylam girin.'));
    },
  );

  layoutMatrix(
    'SiteSecurityPolicyDialog (yönetici: devre dışı kartlar + standart dışı QR süresi)',
    (t, width, height, scale, dark) async {
      await _open(
        t,
        _site(requireGeofence: false, qrRotation: 45),
        isSuperUser: false,
        width: width,
        height: height,
        scale: scale,
        dark: dark,
      );

      expect(find.text('Sadece Süper User'), findsOneWidget);
      expect(find.text('45 saniye'), findsOneWidget);
      await scrollTo(t, find.text('45 saniye'));
      await scrollTo(t, find.text('📍 Konum Doğrulama (GPS Geofence)'));
    },
  );

  testWidgets(
    'SiteSecurityPolicyDialog: erişim yöntemi kartı seçilebilir (süper kullanıcı)',
    (t) async {
      final saved = await _open(
        t,
        _site(requireGeofence: false),
        width: 400,
        height: 900,
        scale: 1.0,
        dark: false,
      );
      await scrollTo(t, find.text('📷 Sadece QR Kod ile Giriş'));
      await t.tap(find.text('📷 Sadece QR Kod ile Giriş'));
      await settleFor(t);
      // QR yöntemi seçilince dinamik QR süresi bölümü hâlâ görünür; uygulama-only'de gizlenirdi.
      expect(find.text('Dinamik QR Yenilenme Süresi'), findsOneWidget);
      await scrollTo(t, find.text('📱 Sadece Mobil Uygulama Butonu'));
      await t.tap(find.text('📱 Sadece Mobil Uygulama Butonu'));
      await settleFor(t);
      expect(find.text('Dinamik QR Yenilenme Süresi'), findsNothing);

      await t.tap(find.text('Değişiklikleri Kaydet'));
      await settleFor(t, 700);
      expect(saved.called, isTrue);
      expect(t.takeException(), isNull);
    },
  );
}
