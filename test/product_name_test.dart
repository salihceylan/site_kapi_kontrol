// Platform Faz 1.1: ürün adı. Platformun görünen adı "Site ve Toplu Yaşam Yönetim Sistemi"dir; AHBU
// yalnız Geçiş Kontrol (kapı açma) modülünün adıdır.
//
// DEĞİŞENLER (platform düzeyi): uygulama başlığı, giriş ekranı başlığı/alt başlığı, Panel başlığı, katılım
// kodu metinleri. KALANLAR (kapı modülü): kapı kartı etiketleri, "Geçiş Kontrol (AHBU)", BLE ad öneki.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:site_kapi_kontrol/config/app_config.dart';
import 'package:site_kapi_kontrol/main.dart';
import 'package:site_kapi_kontrol/models/site_join_token_record.dart';
import 'package:site_kapi_kontrol/models/site_record.dart';
import 'package:site_kapi_kontrol/models/audit_log.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/dialogs/site_join_qr_dialog.dart';

import 'screens/dialog_layout_harness.dart';

const String _productName = 'Site ve Toplu Yaşam Yönetim Sistemi';

class _QrAuth extends AuthService {
  _QrAuth() : super(api: AuthApi(baseUrl: 'http://localhost'));

  @override
  Future<SiteJoinTokenRecord> getSiteJoinToken({required int siteCode}) async =>
      SiteJoinTokenRecord(
        id: 1,
        siteCode: 1,
        siteName: 'Güneş Sitesi',
        token: 'GUNES-ABC123',
        qrPayload: 'SITE_JOIN:GUNES-ABC123',
        isActive: true,
      );
}

SiteRecord _site() => SiteRecord(
  id: 1,
  name: 'Güneş Sitesi',
  address: null,
  city: null,
  district: null,
  blockCount: 1,
  apartmentCount: 4,
  doorCount: 1,
  approvalStatus: 'approved',
  approvedAt: DateTime(2026, 1, 1),
  mqttSiteId: 1,
  managerUserCode: 1,
  managerName: 'Ali',
  createdAt: DateTime(2026, 1, 1),
);

String _read(String path) => File(path).readAsStringSync();

void main() {
  test('AppConfig.appName platform adıdır', () {
    expect(AppConfig.appName, _productName);
  });

  group('giriş ekranı ve uygulama başlığı', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      FlutterSecureStorage.setMockInitialValues(<String, String>{});
    });

    testWidgets('MaterialApp başlığı platform adıdır; giriş ekranı yeni başlık + alt başlık; eski ad yok', (t) async {
      await t.pumpWidget(const MyApp(networkCheckEnabled: false));
      await t.pumpAndSettle();

      expect(t.widget<MaterialApp>(find.byType(MaterialApp)).title, _productName);
      expect(find.text(_productName), findsOneWidget);
      expect(find.text('Yönetici ve sakin girişi'), findsOneWidget);
      expect(find.text('AHBU Giriş'), findsNothing);
      expect(find.text('Akıllı Kapı & Site Otomasyon Paneli'), findsNothing);
    });

  });

  group('Katılım kodu metinleri (SiteJoinQrDialog)', () {
    testWidgets('kopyalanan metin AHBU değil platform adını söyler', (t) async {
      String? copied;
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      });
      addTearDown(
        () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );

      await openDialogAt(
        t,
        (context) => SiteJoinQrDialog.show(context, site: _site(), authService: _QrAuth()),
        width: 400,
        height: 1000,
        scale: 1.0,
        dark: false,
      );
      await settleFor(t);
      await scrollTo(t, find.text('Kodu Kopyala'));
      await t.tap(find.text('Kodu Kopyala'));
      await settleFor(t);

      expect(copied, isNotNull);
      expect(copied, contains('$_productName uygulamasından'));
      expect(copied, contains('SITE_JOIN:GUNES-ABC123'));
      expect(copied, isNot(contains('AHBU')));
    });

    test('paylaşım metni (kaynak) platform adını kullanır; AHBU geçmez', () {
      final source = _read('lib/ui/dialogs/site_join_qr_dialog.dart');
      expect(source, contains('$_productName uygulamasından okutabilirsiniz'));
      expect(source, contains('1. $_productName uygulamasını açın.'));
      expect(source.contains('AHBU'), isFalse);
    });
  });

  group('kapı modülünde AHBU adı KALIR', () {
    test('Geçiş Kontrol (AHBU) modül adı ve denetim kaydı etiketi', () {
      final entry = AuditLogEntry.fromJson(<String, dynamic>{
        'id': 1,
        'action': 'module.disabled',
        'target_type': 'module',
        'target_id': 'door_control',
      });
      expect(entry.targetLabel, 'Geçiş Kontrol (AHBU)');
    });

    test('kapı kartı etiketleri, BLE ad öneki ve kapı/cihaz PDF raporları AHBU adını korur', () {
      expect(_read('lib/ui/widgets/resident_door_remote_card.dart'), contains("'AHBU AKILLI GEÇİŞ'"));
      expect(_read('lib/ui/widgets/resident_door_remote_card.dart'), contains("'AHBU YEREL AĞ GEÇİŞ'"));
      expect(_read('lib/services/ble_wifi_provision_service.dart'), contains("startsWith('AHBU')"));
      expect(_read('lib/services/pdf_logs_service.dart'), contains('AHBU AKILLI KAPI & GEÇİŞ SİSTEMİ'));
      expect(_read('lib/services/pdf_device_firmware_service.dart'), contains('AHBU AKILLI KAPI KONTROL SİSTEMİ'));
    });

    test('daire giriş bilgileri PDF\'i (platform düzeyi belge) platform adını kullanır', () {
      final source = _read('lib/services/pdf_credentials_service.dart');
      expect(source.contains('AHBU'), isFalse);
      expect(source, contains("'$_productName'"));
    });
  });

  test('Panel başlığı (home_page) "Panel"dir; AHBU Panel kalmadı', () {
    final source = _read('lib/ui/pages/home_page.dart');
    expect(source, contains("return 'Panel';"));
    expect(source.contains('AHBU Panel'), isFalse);
  });
}
