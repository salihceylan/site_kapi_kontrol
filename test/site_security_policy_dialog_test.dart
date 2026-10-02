import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/site_record.dart';
import 'package:site_kapi_kontrol/ui/widgets/site_security_policy_dialog.dart';

SiteRecord _site({
  bool requireGeofence = true,
  double? lat,
  double? lng,
  int radius = 100,
}) {
  return SiteRecord(
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
    createdAt: DateTime(2026, 1, 1),
  );
}

class _Saved {
  bool called = false;
  bool? requireGeofence;
  double? latitude;
  double? longitude;
  int? radius;
  int? qrRotationSeconds;
}

Future<_Saved> _openDialog(
  WidgetTester tester,
  SiteRecord site, {
  bool isSuperUser = true,
}) async {
  tester.view.physicalSize = const Size(320, 640);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);

  final saved = _Saved();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showDialog<bool>(
              context: context,
              builder: (_) => SiteSecurityPolicyDialog(
                site: site,
                isSuperUser: isSuperUser,
                onSave: ({
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
                  saved.latitude = geofenceLatitude;
                  saved.longitude = geofenceLongitude;
                  saved.radius = geofenceRadiusMeters;
                  saved.qrRotationSeconds = qrRotationSeconds;
                },
              ),
            ),
            child: const Text('Aç'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Aç'));
  await tester.pumpAndSettle();
  return saved;
}

void main() {
  testWidgets('konum doğrulaması açıkken boş koordinatla kaydedilemez (320 px taşmasız)', (tester) async {
    final saved = await _openDialog(tester, _site());
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Değişiklikleri Kaydet'));
    await tester.pumpAndSettle();

    expect(saved.called, isFalse);
    expect(find.text('Geçerli bir enlem girin.'), findsOneWidget);
    expect(find.text('Geçerli bir boylam girin.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hatalı / aralık dışı koordinat kaydı engeller', (tester) async {
    final saved = await _openDialog(tester, _site());

    await tester.enterText(find.widgetWithText(TextField, 'Enlem (Latitude)'), '95');
    await tester.enterText(find.widgetWithText(TextField, 'Boylam (Longitude)'), 'abc');
    await tester.tap(find.text('Değişiklikleri Kaydet'));
    await tester.pumpAndSettle();

    expect(saved.called, isFalse);
    expect(find.text('Enlem -90 ile 90 arasında olmalı.'), findsOneWidget);
    expect(find.text('Geçerli bir boylam girin.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('geçerli koordinat (virgüllü ondalık dahil) kaydedilir', (tester) async {
    final saved = await _openDialog(tester, _site());

    await tester.enterText(find.widgetWithText(TextField, 'Enlem (Latitude)'), '41,0082');
    await tester.enterText(find.widgetWithText(TextField, 'Boylam (Longitude)'), '28.9784');
    await tester.tap(find.text('Değişiklikleri Kaydet'));
    await tester.pumpAndSettle();

    expect(saved.called, isTrue);
    expect(saved.requireGeofence, isTrue);
    expect(saved.latitude, closeTo(41.0082, 1e-9));
    expect(saved.longitude, closeTo(28.9784, 1e-9));
    expect(saved.radius, 100);
    expect(tester.takeException(), isNull);
  });

  testWidgets('konum doğrulaması kapalıyken koordinat zorunlu değildir', (tester) async {
    final saved = await _openDialog(tester, _site(requireGeofence: false));

    await tester.tap(find.text('Değişiklikleri Kaydet'));
    await tester.pumpAndSettle();

    expect(saved.called, isTrue);
    expect(saved.requireGeofence, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('kaydırıcı aralığı dışındaki yarıçap (örn. 500 m) çökmez ve sessizce değişmez', (tester) async {
    final saved = await _openDialog(tester, _site(lat: 41.0, lng: 29.0, radius: 500));
    expect(tester.takeException(), isNull);
    // Kayıtlı değer gerçek haliyle gösterilir (sunucu 10-2000 m kabul eder).
    expect(find.text('500 metre'), findsOneWidget);

    await tester.tap(find.text('Değişiklikleri Kaydet'));
    await tester.pumpAndSettle();

    expect(saved.called, isTrue);
    expect(saved.radius, 500, reason: 'kaydırıcı oynatılmadıkça kayıtlı yarıçap korunur');
  });

  testWidgets('aralık altındaki yarıçap (örn. 10 m) da kaydırıcı oynatılmadıkça korunur', (tester) async {
    final saved = await _openDialog(tester, _site(lat: 41.0, lng: 29.0, radius: 10));
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Değişiklikleri Kaydet'));
    await tester.pumpAndSettle();

    expect(saved.called, isTrue);
    expect(saved.radius, 10);
  });

  testWidgets('standart dışı QR yenilenme süresi (örn. 45 sn) seçiciyi çökertmez ve korunur', (tester) async {
    final site = _site(requireGeofence: false).copyWith(qrRotationSeconds: 45);
    final saved = await _openDialog(tester, site);
    expect(tester.takeException(), isNull);
    expect(find.text('45 saniye'), findsOneWidget);

    await tester.tap(find.text('Değişiklikleri Kaydet'));
    await tester.pumpAndSettle();

    expect(saved.called, isTrue);
    expect(saved.qrRotationSeconds, 45, reason: 'kayıtlı süre sessizce 30 saniyeye ezilmez');
  });

  testWidgets('süper kullanıcı olmayan yönetici için dar ekranda taşma olmaz', (tester) async {
    await _openDialog(tester, _site(lat: 41.0, lng: 29.0), isSuperUser: false);
    expect(find.text('Sadece Süper User'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
