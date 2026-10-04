// FAZ 5 / A2-G5: SiteSecurityPolicyDialog taşma testi (AGENTS.md kural 6).
//
// `Dialog`: başlık şeridi + düğme satırı sabit, politika alanları tek kaydırma alanında; büyük yazıda
// enlem/boylam alt alta dizilir.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/site_record.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/icon_orb.dart';
import 'package:site_kapi_kontrol/ui/design/motion_widgets.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/widgets/site_security_policy_dialog.dart';

import '../design/harness.dart' show recordHaptics;
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
    'SiteSecurityPolicyDialog: bölüm başlıkları cilalı küre (ton anlam taşır), anahtar satırları >= 56 dp',
    (t) async {
      await _open(
        t,
        _site(lat: 41.0082, lng: 28.9784),
        width: 400,
        height: 1100,
        scale: 1.0,
        dark: false,
      );
      await scrollTo(t, find.text('Kapı / Site GPS Koordinatları'));
      // Başlık şeridi (44, glow) + üç bölüm başlığı (32, squircle): giriş yöntemi primary, QR süresi
      // success, GPS koordinatları info.
      final orbs = t.widgetList<IconOrb>(find.byType(IconOrb)).toList();
      expect(orbs, hasLength(4));
      expect(orbs.where((o) => o.size == 32).map((o) => o.tone).toSet(), {
        AppTone.primary,
        AppTone.success,
        AppTone.info,
      });
      for (final o in orbs.where((o) => o.size == 32)) {
        expect(o.shape, IconOrbShape.squircle);
      }
      // Erişim yöntemi kartları kademeli girer (R2; Column içinde, tembel liste değil).
      expect(find.byType(StaggeredEntry), findsNWidgets(3));
      for (final tile in t.widgetList<SwitchListTile>(
        find.byType(SwitchListTile),
      )) {
        expect(tile.contentPadding, EdgeInsets.zero);
      }
      for (final e in find.byType(SwitchListTile).evaluate()) {
        expect(
          t.getSize(find.byWidget(e.widget)).height,
          greaterThanOrEqualTo(56),
        );
      }
      // Kararlı durumda hiçbir animasyon kalmaz (giriş ve açılış animasyonları sonlu).
      await t.pumpAndSettle();
      expect(t.binding.transientCallbackCount, 0);
    },
  );

  testWidgets(
    'SiteSecurityPolicyDialog: QR süresi açılır listesi R8 (yuvarlak köşe, yüzey rengi, 320 dp menü, aşağı ok, >= 48 dp)',
    (t) async {
      for (final dark in const <bool>[false, true]) {
        await _open(
          t,
          _site(requireGeofence: false),
          width: 400,
          height: 900,
          scale: 1.0,
          dark: dark,
        );
        final p = dark ? AppPalette.dark : AppPalette.light;
        await scrollTo(t, find.byType(DropdownButton<int>));
        final dropdown = t.widget<DropdownButton<int>>(
          find.byType(DropdownButton<int>),
        );
        expect(dropdown.borderRadius, BorderRadius.circular(AppRadius.md));
        expect(dropdown.dropdownColor, p.surface);
        expect(dropdown.menuMaxHeight, 320);
        expect((dropdown.icon! as Icon).icon, Icons.keyboard_arrow_down_rounded);
        expect(dropdown.isExpanded, isTrue);
        expect(
          t.getSize(find.byType(DropdownButton<int>)).height,
          greaterThanOrEqualTo(48),
        );
      }
    },
  );

  testWidgets(
    'SiteSecurityPolicyDialog: süper kullanıcı değilse "Sadece Süper User" StatusChip(neutral); devre dışı kartlarda Opacity yok',
    (t) async {
      await _open(
        t,
        _site(requireGeofence: false),
        isSuperUser: false,
        width: 400,
        height: 900,
        scale: 1.0,
        dark: false,
      );
      final chip = t.widget<StatusChip>(
        find.widgetWithText(StatusChip, 'Sadece Süper User'),
      );
      expect(chip.tone, AppTone.neutral);
      expect(
        find.descendant(
          of: find.byType(AppCard),
          matching: find.byType(Opacity),
        ),
        findsNothing,
        reason: 'devre dışı kart Opacity (saveLayer) yerine palet renkleriyle soluk',
      );
      // Kartlar dokunulamaz (onTap null).
      for (final card in t.widgetList<AppCard>(find.byType(AppCard))) {
        expect(card.onTap, isNull);
      }
    },
  );

  testWidgets(
    'SiteSecurityPolicyDialog: mesafe hatası InlineNotice (mevcut cümle); geçerli kayıtta tek hafif haptik',
    (t) async {
      final haptics = recordHaptics(t);
      final saved = await _open(
        t,
        _site(lat: 41.0, lng: 29.0, radius: 5000),
        width: 400,
        height: 1100,
        scale: 1.0,
        dark: false,
      );
      await scrollTo(t, find.text('Değişiklikleri Kaydet'));
      await t.tap(find.text('Değişiklikleri Kaydet'));
      await settleFor(t, 700);
      expect(saved.called, isFalse);
      final notice = t.widget<InlineNotice>(find.byType(InlineNotice));
      expect(notice.message, 'Mesafe 10 ile 2000 metre arasında olmalı.');
      expect(notice.tone, AppTone.danger);
      expect(
        haptics.where((h) => h.contains('lightImpact')),
        isEmpty,
        reason: 'hatalı kayıtta onay haptiği yok',
      );

      // Kaydırıcıyı oynatmak hatayı temizler; geçerli kayıt hafif haptik verir ve kapanır.
      await scrollTo(t, find.byType(Slider));
      await t.drag(find.byType(Slider), const Offset(-200, 0));
      await settleFor(t);
      expect(find.byType(InlineNotice), findsNothing);
      await scrollTo(t, find.text('Değişiklikleri Kaydet'));
      await t.tap(find.text('Değişiklikleri Kaydet'));
      await settleFor(t, 700);
      expect(saved.called, isTrue);
      expect(
        haptics.where((h) => h.contains('lightImpact')),
        hasLength(1),
        reason: 'kayıt başarısında hafif haptik',
      );
      expect(find.byType(Dialog), findsNothing);
      expect(t.takeException(), isNull);
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
