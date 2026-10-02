// FAZ 5 / A2-G2: ResidentDoorUiState (sakin kartı durum türetimi).
//
// Kart yeniden tasarlanırken iç içe üçlü ifadeler (etiket, ikon, dokunma, durum cümlesi) tek saf
// sınıfa taşındı. Bu test, ESKİ `build` ifadelerinin birebir kopyasını (referans/oracle) tüm
// girdi birleşimlerinde (2^8 = 256) yeni sınıfla karşılaştırır: davranış değişmedi.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/models/door_runtime_status.dart';
import 'package:site_kapi_kontrol/ui/design/door_open_button.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/widgets/resident_door_remote_card.dart';

/// Eski `ResidentDoorRemoteCard.build` ifadelerinin birebir kopyası (yalnız değişken adları girdi).
class _Old {
  _Old({
    required this.hasDoor,
    required this.isDeviceAssigned,
    required this.canRemote,
    required this.canQr,
    required this.isCloudOnline,
    required this.canTryLocalDoorOpen,
    required this.isOpeningDoor,
    required this.isLoadingStatus,
  });

  final bool hasDoor;
  final bool isDeviceAssigned;
  final bool canRemote;
  final bool canQr;
  final bool isCloudOnline;
  final bool canTryLocalDoorOpen;
  final bool isOpeningDoor;
  final bool isLoadingStatus;

  bool get isLocalOnline => !isCloudOnline && canTryLocalDoorOpen;
  bool get isOnline => isCloudOnline || isLocalOnline;
  bool get isQrOnly => hasDoor && !canRemote && canQr;
  bool get commandEnabled =>
      isDeviceAssigned &&
      canRemote &&
      isOnline &&
      !isOpeningDoor &&
      !isLoadingStatus;

  /// İç `InkWell.onTap` (null = dokunma işleyicisi yok).
  String? get innerTap => isOpeningDoor
      ? null
      : (isQrOnly
            ? (isOnline ? 'qr' : 'warn')
            : (commandEnabled ? 'open' : (!isOnline ? 'warn' : null)));

  /// Dış `GestureDetector.onTap`: iç işleyici yoksa devreye giren.
  String? get outerTap => isQrOnly ? 'qr' : (commandEnabled ? 'open' : null);

  /// Kullanıcının dokunuşunun fiilen yol açtığı sonuç.
  String get effectiveTap => innerTap ?? outerTap ?? 'none';

  IconData get icon => isQrOnly
      ? Icons.qr_code_2_rounded
      : (commandEnabled
            ? (isLocalOnline ? Icons.wifi_rounded : Icons.lock_open_rounded)
            : (!canRemote ? Icons.block_rounded : Icons.lock_outline_rounded));

  String get label => isQrOnly
      ? (isOnline ? 'QR KOD İLE AÇ' : 'ÇEVRİMDİŞI')
      : (commandEnabled
            ? (isLocalOnline ? 'YEREL AĞDAN AÇ' : 'KAPIYI AÇ')
            : (!canRemote
                  ? 'UZAKTAN KAPALI'
                  : (isDeviceAssigned ? 'ÇEVRİMDİŞI' : 'KAPALI')));

  String get statusText {
    if (!isDeviceAssigned) {
      return 'Bu kapıya henüz cihaz atanmamış.';
    } else if (isOpeningDoor) {
      return 'Kapı tetikleniyor, lütfen bekleyin...';
    } else if (isLoadingStatus) {
      return 'Cihaz durumu kontrol ediliyor...';
    } else if (isQrOnly) {
      return '📷 Bu sitede yalnızca QR Kod ile giriş aktiftir.';
    } else if (!canRemote) {
      return '🚫 Bu kapıda uzaktan açma yetkisi kapalıdır.';
    } else if (isCloudOnline) {
      return '🟢 Çevrimiçi - Kapıyı açmak için dokunun';
    } else if (isLocalOnline) {
      return '🟡 Yerel Ağda Aktif - Kapıyı açmak için dokunun';
    } else {
      return '🔴 Cihaz Çevrimdışı';
    }
  }
}

ResidentDoorUiState _state({
  bool hasDoor = true,
  bool isDeviceAssigned = true,
  bool canRemote = true,
  bool canQr = false,
  bool isCloudOnline = false,
  bool canTryLocalDoorOpen = false,
  bool isOpeningDoor = false,
  bool isLoadingStatus = false,
}) => ResidentDoorUiState(
  hasDoor: hasDoor,
  isDeviceAssigned: isDeviceAssigned,
  canRemote: canRemote,
  canQr: canQr,
  isCloudOnline: isCloudOnline,
  canTryLocalDoorOpen: canTryLocalDoorOpen,
  isOpeningDoor: isOpeningDoor,
  isLoadingStatus: isLoadingStatus,
);

DoorRecord _door({
  String? uid = 'ESP32_WROOM_T1',
  bool remote = true,
  bool qrEnabled = true,
  bool qrActive = true,
  bool qrReader = false,
  String? target = 'esp32-wroom',
}) => DoorRecord(
  id: 7,
  siteCode: 101,
  siteName: 'Güneş Sitesi',
  doorName: 'Ana Giriş',
  doorIndex: 1,
  isActive: true,
  assignedDeviceId: uid == null ? null : 1,
  assignedDeviceUid: uid,
  assignedDeviceHardwareTarget: target,
  assignedDeviceQrReaderEnabled: qrReader,
  featureRemoteOpenEnabled: remote,
  featureQrEnabled: qrEnabled,
  qrEntryActive: qrActive,
  mqttSiteId: 101,
  createdAt: DateTime(2026, 1, 1),
);

DoorRuntimeStatus _runtime({required bool online}) =>
    DoorRuntimeStatus.fromJson({
      'door': {
        'id': 7,
        'site_code': 101,
        'door_name': 'Ana Giriş',
        'door_index': 1,
      },
      'device_status': {
        'device_uid': 'ESP32_WROOM_T1',
        'mqtt_connected': online,
        'mqtt_bridge_connected': true,
      },
    });

void main() {
  group('eski davranışla eşdeğerlik (tüm 256 girdi birleşimi)', () {
    test('etiket, ikon, durum cümlesi ve dokunma sonucu eskiyle aynı', () {
      var checked = 0;
      var exceptions = 0;
      for (var bits = 0; bits < 256; bits++) {
        bool b(int i) => (bits >> i) & 1 == 1;
        final old = _Old(
          hasDoor: b(0),
          isDeviceAssigned: b(1),
          canRemote: b(2),
          canQr: b(3),
          isCloudOnline: b(4),
          canTryLocalDoorOpen: b(5),
          isOpeningDoor: b(6),
          isLoadingStatus: b(7),
        );
        final now = _state(
          hasDoor: old.hasDoor,
          isDeviceAssigned: old.isDeviceAssigned,
          canRemote: old.canRemote,
          canQr: old.canQr,
          isCloudOnline: old.isCloudOnline,
          canTryLocalDoorOpen: old.canTryLocalDoorOpen,
          isOpeningDoor: old.isOpeningDoor,
          isLoadingStatus: old.isLoadingStatus,
        );
        final reason = 'bits=${bits.toRadixString(2).padLeft(8, '0')}';

        expect(now.isLocalOnline, old.isLocalOnline, reason: reason);
        expect(now.isOnline, old.isOnline, reason: reason);
        expect(now.isQrOnly, old.isQrOnly, reason: reason);
        expect(now.commandEnabled, old.commandEnabled, reason: reason);
        expect(now.buttonIcon, old.icon, reason: reason);
        expect(now.buttonLabel, old.label, reason: reason);
        expect(now.statusText, old.statusText, reason: reason);

        final expectedTap = switch (now.tap) {
          ResidentDoorTap.openDoor => 'open',
          ResidentDoorTap.showQr => 'qr',
          ResidentDoorTap.offlineWarning => 'warn',
          ResidentDoorTap.none => 'none',
        };
        if (old.isOpeningDoor && old.isQrOnly) {
          // BİLİNÇLİ fark: eski kodda dış GestureDetector, komut sürerken yalnız-karekod kapıda
          // karekod penceresini açıyordu; yeni düğme açılırken dokunmayı kabul etmez.
          expect(old.effectiveTap, 'qr', reason: reason);
          expect(expectedTap, 'none', reason: reason);
          exceptions++;
        } else {
          expect(expectedTap, old.effectiveTap, reason: reason);
        }
        checked++;
      }
      expect(checked, 256);
      // Bilinçli fark yalnız (açılıyor && yalnız-karekod) birleşimlerinde: 2^8 içinde 2^4 = 16 hâl.
      expect(exceptions, 16);
    });

    test(
      'DoorOpenState: açılıyor; dokununca iş yapılıyorsa ready; uyarıysa offline; yoksa disabled',
      () {
        for (var bits = 0; bits < 256; bits++) {
          bool b(int i) => (bits >> i) & 1 == 1;
          final s = _state(
            hasDoor: b(0),
            isDeviceAssigned: b(1),
            canRemote: b(2),
            canQr: b(3),
            isCloudOnline: b(4),
            canTryLocalDoorOpen: b(5),
            isOpeningDoor: b(6),
            isLoadingStatus: b(7),
          );
          final expected = s.isOpeningDoor
              ? DoorOpenState.opening
              : switch (s.tap) {
                  ResidentDoorTap.openDoor ||
                  ResidentDoorTap.showQr => DoorOpenState.ready,
                  ResidentDoorTap.offlineWarning => DoorOpenState.offline,
                  ResidentDoorTap.none => DoorOpenState.disabled,
                };
          expect(s.buttonState, expected, reason: 'bits=$bits');
        }
      },
    );
  });

  group('senaryolar', () {
    test('bulutta çevrimiçi: KAPIYI AÇ (primary, ready, kapı açar)', () {
      final s = _state(isCloudOnline: true);
      expect(s.buttonState, DoorOpenState.ready);
      expect(s.buttonLabel, 'KAPIYI AÇ');
      expect(s.buttonIcon, Icons.lock_open_rounded);
      expect(s.buttonTone, AppTone.primary);
      expect(s.tap, ResidentDoorTap.openDoor);
      expect(s.statusText, '🟢 Çevrimiçi - Kapıyı açmak için dokunun');
      expect(s.statusTone, AppTone.success);
    });

    test('yalnız yerel ağda: YEREL AĞDAN AÇ (warning)', () {
      final s = _state(canTryLocalDoorOpen: true);
      expect(s.isLocalOnline, isTrue);
      expect(s.buttonState, DoorOpenState.ready);
      expect(s.buttonLabel, 'YEREL AĞDAN AÇ');
      expect(s.buttonIcon, Icons.wifi_rounded);
      expect(s.buttonTone, AppTone.warning);
      expect(s.statusTone, AppTone.warning);
    });

    test(
      'bulut varsa yerel ağ bayrağı yok sayılır (turuncu yalnız bulut yokken)',
      () {
        final s = _state(isCloudOnline: true, canTryLocalDoorOpen: true);
        expect(s.isLocalOnline, isFalse);
        expect(s.buttonTone, AppTone.primary);
        expect(s.buttonLabel, 'KAPIYI AÇ');
      },
    );

    test(
      'çevrimdışı: offline durumu, uyarı gösterir (sakin kartındaki mevcut akış)',
      () {
        final s = _state();
        expect(s.buttonState, DoorOpenState.offline);
        expect(s.buttonLabel, 'ÇEVRİMDİŞI');
        expect(s.tap, ResidentDoorTap.offlineWarning);
        expect(s.statusText, '🔴 Cihaz Çevrimdışı');
        expect(s.statusTone, AppTone.danger);
      },
    );

    test('cihaz atanmamış: KAPALI, uyarı gösterir', () {
      final s = _state(isDeviceAssigned: false);
      expect(s.buttonLabel, 'KAPALI');
      expect(s.buttonState, DoorOpenState.offline);
      expect(s.statusText, 'Bu kapıya henüz cihaz atanmamış.');
      expect(s.statusTone, AppTone.danger);
    });

    test(
      'uzaktan açma kapalı + çevrimiçi: UZAKTAN KAPALI, dokunma yok (disabled)',
      () {
        final s = _state(canRemote: false, isCloudOnline: true);
        expect(s.buttonLabel, 'UZAKTAN KAPALI');
        expect(s.buttonIcon, Icons.block_rounded);
        expect(s.buttonState, DoorOpenState.disabled);
        expect(s.tap, ResidentDoorTap.none);
        expect(s.statusText, '🚫 Bu kapıda uzaktan açma yetkisi kapalıdır.');
      },
    );

    test(
      'yalnız karekod + çevrimiçi: QR KOD İLE AÇ (success, ready, karekod gösterir)',
      () {
        final s = _state(canRemote: false, canQr: true, isCloudOnline: true);
        expect(s.isQrOnly, isTrue);
        expect(s.buttonState, DoorOpenState.ready);
        expect(s.buttonLabel, 'QR KOD İLE AÇ');
        expect(s.buttonIcon, Icons.qr_code_2_rounded);
        expect(s.buttonTone, AppTone.success);
        expect(s.tap, ResidentDoorTap.showQr);
        expect(
          s.statusText,
          '📷 Bu sitede yalnızca QR Kod ile giriş aktiftir.',
        );
        expect(s.statusTone, AppTone.success);
      },
    );

    test('yalnız karekod + çevrimdışı: ÇEVRİMDİŞI, uyarı gösterir', () {
      final s = _state(canRemote: false, canQr: true);
      expect(s.buttonState, DoorOpenState.offline);
      expect(s.buttonLabel, 'ÇEVRİMDİŞI');
      expect(s.tap, ResidentDoorTap.offlineWarning);
    });

    test('komut sürerken: opening, dokunma yok, durum cümlesi primary', () {
      final s = _state(isCloudOnline: true, isOpeningDoor: true);
      expect(s.buttonState, DoorOpenState.opening);
      expect(s.tap, ResidentDoorTap.none);
      expect(s.statusText, 'Kapı tetikleniyor, lütfen bekleyin...');
      expect(s.statusTone, AppTone.primary);
    });

    test(
      'durum yüklenirken çevrimiçi kapı geçici olarak dokunulamaz (disabled), cümle neutral',
      () {
        final s = _state(isCloudOnline: true, isLoadingStatus: true);
        expect(s.commandEnabled, isFalse);
        expect(s.buttonState, DoorOpenState.disabled);
        expect(s.statusText, 'Cihaz durumu kontrol ediliyor...');
        expect(s.statusTone, AppTone.neutral);
      },
    );
  });

  group('ResidentDoorUiState.of (kapı kaydı + çalışma durumu)', () {
    test(
      'kapı yok: yetki varsayılanları (uzaktan açık, karekod kapalı), cihaz atanmamış',
      () {
        final s = ResidentDoorUiState.of(
          door: null,
          runtimeStatus: null,
          canTryLocalDoorOpen: false,
          isOpeningDoor: false,
          isLoadingStatus: false,
        );
        expect(s.hasDoor, isFalse);
        expect(s.canRemote, isTrue);
        expect(s.canQr, isFalse);
        expect(s.isDeviceAssigned, isFalse);
        expect(s.isQrOnly, isFalse);
      },
    );

    test('boş/boşluklu cihaz UID atanmamış sayılır', () {
      for (final uid in <String?>[null, '', '   ']) {
        final s = ResidentDoorUiState.of(
          door: _door(uid: uid),
          runtimeStatus: null,
          canTryLocalDoorOpen: false,
          isOpeningDoor: false,
          isLoadingStatus: false,
        );
        expect(s.isDeviceAssigned, isFalse, reason: 'uid=$uid');
      }
    });

    test(
      'bulut çevrimiçiliği çalışma durumundan, kapı yetkileri kayıttan gelir',
      () {
        final s = ResidentDoorUiState.of(
          door: _door(remote: false, qrReader: true),
          runtimeStatus: _runtime(online: true),
          canTryLocalDoorOpen: false,
          isOpeningDoor: false,
          isLoadingStatus: false,
        );
        expect(s.isDeviceAssigned, isTrue);
        expect(s.canRemote, isFalse);
        expect(s.canQr, isTrue, reason: 'WROOM + okuyucu açık + karekod etkin');
        expect(s.isCloudOnline, isTrue);
        expect(s.isQrOnly, isTrue);
        expect(s.buttonLabel, 'QR KOD İLE AÇ');

        final off = ResidentDoorUiState.of(
          door: _door(),
          runtimeStatus: _runtime(online: false),
          canTryLocalDoorOpen: false,
          isOpeningDoor: false,
          isLoadingStatus: false,
        );
        expect(off.isCloudOnline, isFalse);
        expect(off.buttonLabel, 'ÇEVRİMDİŞI');
      },
    );
  });

  test('değer eşitliği: aynı girdiler eşit, farklı girdi farklı', () {
    expect(_state(isCloudOnline: true), _state(isCloudOnline: true));
    expect(
      _state(isCloudOnline: true).hashCode,
      _state(isCloudOnline: true).hashCode,
    );
    expect(_state(isCloudOnline: true), isNot(_state()));
    expect(_state(isOpeningDoor: true), isNot(_state()));
  });
}
