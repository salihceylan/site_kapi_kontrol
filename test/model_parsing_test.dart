import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/device_connectivity_log.dart';
import 'package:site_kapi_kontrol/models/door_access_log_record.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/models/join_request_record.dart';
import 'package:site_kapi_kontrol/models/site_record.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/helpers/ui_helpers.dart';
import 'package:site_kapi_kontrol/ui/widgets/door_logs_accordion.dart';

class _LogsAuthService extends AuthService {
  _LogsAuthService(this.page) : super(api: AuthApi(baseUrl: 'http://localhost'));

  final DoorAccessLogPage page;

  @override
  Future<(DoorAccessLogPage?, String?)> listDoorAccessLogs({
    int? siteCode,
    int? doorId,
    String? search,
    DateTime? startDate,
    DateTime? endDate,
    int page = 1,
    int pageSize = 50,
  }) async {
    return (this.page, null);
  }
}

void main() {
  group('Ayrıştırma varsayılanları: uydurma "şimdi" yerine null', () {
    test('DoorAccessLogRecord: opened_at yok/bozuk ise openedAt null', () {
      final missing = DoorAccessLogRecord.fromJson({'id': 1, 'site_code': 2});
      expect(missing.openedAt, isNull);

      final broken = DoorAccessLogRecord.fromJson({'id': 1, 'opened_at': 'not-a-date'});
      expect(broken.openedAt, isNull);

      final wrongType = DoorAccessLogRecord.fromJson({'id': 1, 'opened_at': 12345});
      expect(wrongType.openedAt, isNull);
    });

    test('DoorAccessLogRecord: geçerli opened_at yerel saate çevrilir', () {
      final record = DoorAccessLogRecord.fromJson({
        'id': 1,
        'opened_at': '2026-05-01T09:30:00.000Z',
      });
      expect(record.openedAt, isNotNull);
      expect(record.openedAt!.toUtc(), DateTime.utc(2026, 5, 1, 9, 30));
    });

    test('DeviceConnectivityLogRecord: created_at yok/bozuk ise createdAt null', () {
      expect(DeviceConnectivityLogRecord.fromJson({'id': 1}).createdAt, isNull);
      expect(
        DeviceConnectivityLogRecord.fromJson({'id': 1, 'created_at': 'garbage'}).createdAt,
        isNull,
      );
      expect(
        DeviceConnectivityLogRecord.fromJson({
          'id': 1,
          'created_at': '2026-05-01T09:30:00Z',
        }).createdAt,
        DateTime.utc(2026, 5, 1, 9, 30),
      );
    });

    test('JoinRequestRecord: createdAt yok/bozuksa null ve toJson bozulmaz', () {
      final missing = JoinRequestRecord.fromJson({'id': 3, 'apartmentId': 4});
      expect(missing.createdAt, isNull);
      expect(missing.toJson()['createdAt'], isNull);

      final ok = JoinRequestRecord.fromJson({
        'id': 3,
        'apartmentId': 4,
        'createdAt': '2026-05-01T09:30:00Z',
      });
      expect(ok.createdAt, DateTime.utc(2026, 5, 1, 9, 30));
      expect(ok.toJson()['createdAt'], isNotNull);
    });

    test('formatDateTimeOrUnknown null için açık "Bilinmiyor" yazar', () {
      expect(formatDateTimeOrUnknown(null), 'Bilinmiyor');
      expect(formatDateTimeOrUnknown(DateTime(2026, 5, 1, 9, 5)), '01.05.2026 09:05');
    });
  });

  group('qr_totp_secret istemcide okunmaz', () {
    test('DoorRecord sunucudan gelse bile sırrı modelde tutmaz', () {
      final door = DoorRecord.fromJson({
        'id': 1,
        'site_code': 1,
        'door_name': 'K',
        'qr_totp_secret': 'SUPER-SECRET',
      });
      expect(() => (door as dynamic).qrTotpSecret, throwsNoSuchMethodError);
    });

    test('SiteRecord sunucudan gelse bile sırrı modelde tutmaz', () {
      final site = SiteRecord.fromJson({
        'id': 1,
        'name': 'S',
        'qr_totp_secret': 'SUPER-SECRET',
      });
      expect(() => (site as dynamic).qrTotpSecret, throwsNoSuchMethodError);
    });
  });

  group('UI: bilinmeyen tarih taşmadan gösterilir', () {
    testWidgets('DoorLogsAccordion openedAt null olan kaydı 320 px genişlikte gösterir', (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final auth = _LogsAuthService(
        DoorAccessLogPage.fromJson({
          'logs': [
            {
              'id': 1,
              'site_code': 1,
              'door_name': 'Çok uzun isimli ana giriş kapısı ve otopark bariyeri',
              'user_name': 'Çok uzun isimli bir kullanıcı adı soyadı örneği',
              'trigger_type': 'cloud_app',
              // opened_at yok
            },
          ],
          'total': 1,
          'page': 1,
          'page_size': 10,
          'total_pages': 1,
        }),
      );

      final door = DoorRecord(
        id: 1,
        siteCode: 1,
        siteName: 'Site',
        doorName: 'Ana Kapı',
        doorIndex: 1,
        isActive: true,
        assignedDeviceId: 1,
        assignedDeviceUid: 'DEV',
        mqttSiteId: 1,
        createdAt: DateTime(2026, 1, 1),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DoorLogsAccordion(
                selectedSite: null,
                selectedDoor: door,
                authService: auth,
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('📊 Ana Kapı Geçiş Logları'));
      await tester.pumpAndSettle();

      expect(find.text('Bilinmiyor'), findsOneWidget);
      expect(find.text('--:--'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  test('UserSession sözleşmesi bozulmadı (toJson/fromJson gidiş-dönüş)', () {
    const session = UserSession(
      id: 5,
      fullName: 'Ali',
      email: 'ali@example.com',
      loginName: 'ali',
      role: UserRole.siteManager,
      isActive: true,
      token: 'tok',
    );
    final restored = UserSession.fromJson(session.toJson());
    expect(restored.role, UserRole.siteManager);
    expect(restored.token, 'tok');
  });
}
