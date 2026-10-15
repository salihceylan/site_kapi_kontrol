// Platform modül sistemi Faz 1: Geçiş Kontrol kapalıyken kapı akışlarının kullanıcıya doğru söylemesi.
//
// - door_module_gate: "Kapı bulunamadı." yerine MODULE_DISABLED mesajı (kısayol / derin bağlantı /
//   sesli tetikleyici) ve fail-open.
// - Masaüstü widget'ı: 403 MODULE_DISABLED -> "Geçiş kapalı".
// - QR modalı: okuyucu red nedeni `module_disabled` / API kodu MODULE_DISABLED.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/models/platform_module.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/door_module_gate.dart';
import 'package:site_kapi_kontrol/services/door_widget_service.dart';
import 'package:site_kapi_kontrol/services/voice_door_service.dart';
import 'package:site_kapi_kontrol/ui/widgets/dynamic_qr_pass_modal.dart';

MySiteModules _site(int code, {required bool door, bool access = true}) => MySiteModules(
  siteCode: code,
  siteName: 'Site $code',
  doorAccess: access,
  modules: <String, bool>{'door_control': door},
);

class _GateAuth extends AuthService {
  _GateAuth() : super(api: AuthApi(baseUrl: 'http://localhost'));

  MyModulesResult? cached;
  MyModulesResult? fetched;
  Object? fetchError;
  Completer<void>? fetchGate;
  int fetchCalls = 0;

  @override
  MyModulesResult? get cachedMyModules => cached;

  @override
  Future<MyModulesResult> getMyModules() async {
    fetchCalls++;
    await fetchGate?.future;
    final error = fetchError;
    if (error != null) throw error;
    return fetched ?? const MyModulesResult();
  }
}

void main() {
  const message =
      'Bu özellik şu an kapalı. Site yöneticisi Modüller ekranından açabilir.';

  group('doorControlClosedMessage', () {
    test('önbellek: tüm kapı erişimli sitelerde kapalıysa MODULE_DISABLED metni, ağ isteği yok', () async {
      final auth = _GateAuth()
        ..cached = MyModulesResult(sites: <MySiteModules>[_site(1, door: false)]);
      expect(await doorControlClosedMessage(auth, fetch: true), message);
      expect(moduleDisabledMessage, message);
      expect(auth.fetchCalls, 0);
    });

    test('bir site açıksa, süper kullanıcıysa ya da yalnız kurul bağı varsa null', () async {
      final open = _GateAuth()
        ..cached = MyModulesResult(
          sites: <MySiteModules>[_site(1, door: false), _site(2, door: true)],
        );
      expect(await doorControlClosedMessage(open), isNull);

      final superUser = _GateAuth()..cached = const MyModulesResult(scope: 'all');
      expect(await doorControlClosedMessage(superUser), isNull);

      final boardOnly = _GateAuth()
        ..cached = MyModulesResult(
          sites: <MySiteModules>[_site(1, door: false, access: false)],
        );
      expect(await doorControlClosedMessage(boardOnly), isNull);
    });

    test('önbellek yok: fetch=false ağ isteği yapmaz (null); fetch=true getMyModules dener', () async {
      final auth = _GateAuth()
        ..fetched = MyModulesResult(sites: <MySiteModules>[_site(1, door: false)]);
      expect(await doorControlClosedMessage(auth), isNull);
      expect(auth.fetchCalls, 0);
      expect(await doorControlClosedMessage(auth, fetch: true), message);
      expect(auth.fetchCalls, 1);
    });

    test('hata ve zaman aşımı fail-open: null', () async {
      final failing = _GateAuth()..fetchError = ApiException('ağ yok');
      expect(await doorControlClosedMessage(failing, fetch: true), isNull);

      final slow = _GateAuth()..fetchGate = Completer<void>();
      expect(
        await doorControlClosedMessage(
          slow,
          fetch: true,
          timeout: const Duration(milliseconds: 20),
        ),
        isNull,
      );
    });
  });

  group('VoiceDoorService.updateCandidateDoors', () {
    setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

    test('boş liste eski aday kapıları temizler (dinlemeyi başlatmaz); null da temizler', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final service = VoiceDoorService(
        authService: AuthService(api: AuthApi(baseUrl: 'http://localhost')),
      );
      const door = DoorRecord(
        id: 1,
        siteCode: 1,
        siteName: 'Gude Sitesi',
        doorIndex: 1,
        doorName: 'Ana Kapı',
        isActive: true,
        assignedDeviceId: 1,
        assignedDeviceUid: 'ESP_1',
        mqttSiteId: 1,
        createdAt: null,
      );

      service.updateCandidateDoors(<DoorRecord>[door]);
      expect(service.debugLastCandidateDoors, hasLength(1));
      expect(service.isListening, isFalse, reason: 'aday güncellemek dinlemeyi başlatmaz');

      // startListening boş aday listesini YOK SAYAR; bu yüzden ayrı yol gerekir.
      service.updateCandidateDoors(const <DoorRecord>[]);
      expect(service.debugLastCandidateDoors, isEmpty);

      service.updateCandidateDoors(<DoorRecord>[door]);
      service.updateCandidateDoors(null);
      expect(service.debugLastCandidateDoors, isNull);
    });
  });

  group('masaüstü widget: mapDoorOpenResponse', () {
    test('403 MODULE_DISABLED -> "Geçiş kapalı"; diğer 403 kodları değişmedi', () {
      expect(
        mapDoorOpenResponse(403, '{"code":"MODULE_DISABLED","module":"door_control"}').status,
        'Geçiş kapalı ❌',
      );
      expect(
        mapDoorOpenResponse(403, '{"code":"REMOTE_OPEN_DISABLED"}').status,
        'Uzaktan açma kapalı ❌',
      );
      expect(mapDoorOpenResponse(403, '{"code":"DOOR_ACCESS_DENIED"}').status, 'Yetkiniz yok ❌');
    });
  });

  group('QR modalı: qrDenialInfoFor', () {
    test('module_disabled (okuyucu) ve MODULE_DISABLED (API) anlaşılır ve kalıcı ret', () {
      for (final reason in <String>['module_disabled', 'MODULE_DISABLED']) {
        final info = qrDenialInfoFor(reason);
        expect(info, isNotNull, reason: reason);
        expect(info!.title, 'Geçiş Kontrol Kapalı');
        expect(info.message, contains('Geçiş Kontrol modülü kapalı'));
        expect(info.message.contains('_'), isFalse);
        expect(info.permanent, isTrue, reason: 'kod bu kapıda artık çalışmaz: yoklama durur');
        expect(info.expired, isFalse);
        expect(info.speech, 'Geçiş Kontrol modülü kapalı.');
      }
    });
  });
}
