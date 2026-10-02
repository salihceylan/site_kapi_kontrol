// FAZ 5 / A2-G4: IndividualDoorCardModel (bireysel kapı kartı eylem/durum TÜRETİMİ) birim testi.
//
// "Yüksek yeniden kurma riski: önce türetim + test". Eski `_buildDoorCard` koşulları bu dosyada
// BİREBİR yeniden yazılır (legacy*) ve türetim 4 bin+ kapı kombinasyonunda onlarla karşılaştırılır:
// hiçbir düğme koşulu, hiçbir durum eşlemesi değişmemiş olmalıdır.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/ui/design/door_open_button.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/widgets/individual_door_card.dart';

import 'g4_test_support.dart';

// ---- Eski kart koşulları (individual_home_view.dart, yeniden yapılandırmadan ÖNCE) ----
bool legacyScanScreenQr(DoorRecord d) => d.hasDisplay;
bool legacyShowQr(DoorRecord d) => d.canShowQrCode;
bool legacyMainOpen(DoorRecord d) =>
    !d.hasDisplay && !d.canShowQrCode && d.canOpenRemote && !d.isQrOnly;
bool legacyGuest(DoorRecord d) => d.canCreateGuestPass;
bool legacyRemoteOpen(DoorRecord d) =>
    d.canOpenRemote && !d.isQrOnly && (d.hasDisplay || d.canShowQrCode);

void main() {
  group('eski koşullarla BİREBİR eşdeğerlik (tüm kombinasyonlar)', () {
    test('düğme görünürlüğü, kapı açma türü/durumu ve cihaz durumu', () {
      var combos = 0;
      for (final hardware in const <String?>[
        'esp32_wroom',
        'esp32_c3',
        null,
        '',
      ]) {
        for (final uid in const <String?>[null, '', 'ESP32_UID']) {
          for (final qrReader in const <bool>[true, false]) {
            for (final remote in const <bool>[true, false]) {
              for (final guest in const <bool>[true, false]) {
                for (final qrFeature in const <bool>[true, false]) {
                  for (final qrEntry in const <bool>[true, false]) {
                    for (final online in const <bool?>[true, false, null]) {
                      for (final opening in const <bool>[true, false]) {
                        final door = g4Door(
                          hardware: hardware,
                          deviceUid: uid,
                          qrReader: qrReader,
                          remote: remote,
                          guest: guest,
                          qrFeature: qrFeature,
                          qrEntryActive: qrEntry,
                          online: online,
                        );
                        final m = IndividualDoorCardModel.of(
                          door,
                          isOpening: opening,
                        );
                        combos++;
                        final why =
                            'hw=$hardware uid=$uid qr=$qrReader remote=$remote guest=$guest '
                            'qrF=$qrFeature qrE=$qrEntry online=$online opening=$opening';

                        expect(
                          m.showScanScreenQr,
                          legacyScanScreenQr(door),
                          reason: why,
                        );
                        expect(m.showShowQr, legacyShowQr(door), reason: why);
                        expect(m.showGuestPass, legacyGuest(door), reason: why);
                        expect(
                          m.openKind == IndividualDoorOpenKind.main,
                          legacyMainOpen(door),
                          reason: why,
                        );
                        expect(
                          m.openKind == IndividualDoorOpenKind.remote,
                          legacyRemoteOpen(door),
                          reason: why,
                        );
                        // Aynı kapıda ikisi birden asla görünmez (eski koşullar da ayrıktı).
                        expect(
                          legacyMainOpen(door) && legacyRemoteOpen(door),
                          isFalse,
                          reason: why,
                        );
                        expect(
                          m.hasActions,
                          legacyScanScreenQr(door) ||
                              legacyShowQr(door) ||
                              legacyGuest(door) ||
                              legacyMainOpen(door) ||
                              legacyRemoteOpen(door),
                          reason: why,
                        );

                        final assigned = uid != null && uid.isNotEmpty;
                        final isOnline = online == true;
                        expect(m.isOnline, isOnline, reason: why);
                        expect(
                          m.deviceStatus,
                          !assigned
                              ? IndividualDoorDeviceStatus.noDevice
                              : (isOnline
                                    ? IndividualDoorDeviceStatus.online
                                    : IndividualDoorDeviceStatus.offline),
                          reason: why,
                        );
                        // Kapı açma düğmesi durumu: komut sürüyorsa opening; çevrimiçiyse ready;
                        // aksi hâlde offline (dokunuş eski yeniden-kontrol akışını çağırır).
                        expect(
                          m.openState,
                          opening
                              ? DoorOpenState.opening
                              : (isOnline
                                    ? DoorOpenState.ready
                                    : DoorOpenState.offline),
                          reason: why,
                        );
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
      expect(combos, 4 * 3 * 2 * 2 * 2 * 2 * 2 * 3 * 2);
    });
  });

  group('örnek kapılar', () {
    test(
      'WROOM + QR okuyucu (ekranlı): QR eylemleri + misafir + "Uzaktan Aç"',
      () {
        final m = IndividualDoorCardModel.of(g4Door(), isOpening: false);
        expect(m.showScanScreenQr, isTrue);
        expect(m.showShowQr, isTrue);
        expect(m.showGuestPass, isTrue);
        expect(m.openKind, IndividualDoorOpenKind.remote);
        expect(m.openLabel, 'Uzaktan Aç');
        expect(m.openingLabel, 'Açılıyor...');
        expect(m.openState, DoorOpenState.ready);
        expect(m.deviceStatusLabel, 'Çevrimiçi');
        expect(m.deviceStatusTone, AppTone.success);
        expect(m.isOnline, isTrue);
      },
    );

    test('C3 çevrimdışı: yalnız "Kapıyı Aç" + misafir; durum çevrimdışı', () {
      final m = IndividualDoorCardModel.of(
        g4Door(hardware: 'esp32_c3', qrReader: false, online: false),
        isOpening: false,
      );
      expect(m.showScanScreenQr, isFalse);
      expect(m.showShowQr, isFalse);
      expect(m.openKind, IndividualDoorOpenKind.main);
      expect(m.openLabel, 'Kapıyı Aç');
      expect(m.openingLabel, 'Kapı Açılıyor...');
      expect(m.openState, DoorOpenState.offline);
      expect(m.deviceStatusLabel, 'Çevrimdışı');
      expect(m.deviceStatusTone, AppTone.danger);
    });

    test('komut sürerken (isOpening) düğme opening olur', () {
      final m = IndividualDoorCardModel.of(
        g4Door(hardware: 'esp32_c3', qrReader: false),
        isOpening: true,
      );
      expect(m.openState, DoorOpenState.opening);
      expect(m.isOpening, isTrue);
    });

    test(
      'yalnız QR ile açılan kapı (uzaktan açma kapalı): kapı açma düğmesi yok',
      () {
        final m = IndividualDoorCardModel.of(
          g4Door(remote: false),
          isOpening: false,
        );
        expect(m.openKind, IndividualDoorOpenKind.none);
        expect(m.showScanScreenQr, isTrue);
        expect(m.hasActions, isTrue);
      },
    );

    test('hiçbir yetkisi olmayan kapıda eylem alanı yoktur', () {
      final m = IndividualDoorCardModel.of(
        g4Door(
          hardware: 'esp32_c3',
          qrReader: false,
          remote: false,
          guest: false,
        ),
        isOpening: false,
      );
      expect(m.hasActions, isFalse);
      expect(m.openKind, IndividualDoorOpenKind.none);
    });

    test(
      'cihaz atanmamış kapı: "Cihaz Yok" nötr; kapı açma hâlâ denenebilir (eski davranış)',
      () {
        final m = IndividualDoorCardModel.of(
          g4Door(
            deviceUid: null,
            hardware: null,
            qrReader: false,
            online: null,
          ),
          isOpening: false,
        );
        expect(m.deviceStatus, IndividualDoorDeviceStatus.noDevice);
        expect(m.deviceStatusLabel, 'Cihaz Yok');
        expect(m.deviceStatusTone, AppTone.neutral);
        expect(m.openKind, IndividualDoorOpenKind.main);
        expect(m.openState, DoorOpenState.offline);
      },
    );
  });

  group('kapsam rozeti', () {
    test('BLOCK: blok adıyla; adsızsa "Blok Kapısı"; ton birincil', () {
      final named = IndividualDoorCardModel.of(
        g4Door(scope: 'BLOCK', block: 'B Blok'),
        isOpening: false,
      );
      expect(named.scopeLabel, 'B Blok Kapısı');
      expect(named.scopeIcon, Icons.apartment_rounded);
      expect(named.scopeTone, AppTone.primary);

      final unnamed = IndividualDoorCardModel.of(
        g4Door(scope: 'BLOCK', block: ''),
        isOpening: false,
      );
      expect(unnamed.scopeLabel, 'Blok Kapısı');
      final nullBlock = IndividualDoorCardModel.of(
        g4Door(scope: 'BLOCK'),
        isOpening: false,
      );
      expect(nullBlock.scopeLabel, 'Blok Kapısı');
    });

    test('CUSTOM: "Özel İzinli Kapı" (mor)', () {
      final m = IndividualDoorCardModel.of(
        g4Door(scope: 'CUSTOM'),
        isOpening: false,
      );
      expect(m.scopeLabel, 'Özel İzinli Kapı');
      expect(m.scopeIcon, Icons.vpn_key_rounded);
      expect(m.scopeTone, AppTone.violet);
    });

    test('diğer/SITE_COMMON: "Site Ortak Kapısı" (bilgi tonu)', () {
      for (final scope in const <String>['SITE_COMMON', '', 'BILINMEYEN']) {
        final m = IndividualDoorCardModel.of(
          g4Door(scope: scope),
          isOpening: false,
        );
        expect(m.scopeLabel, 'Site Ortak Kapısı', reason: 'scope=$scope');
        expect(m.scopeIcon, Icons.public_rounded);
        expect(m.scopeTone, AppTone.info);
      }
    });
  });
}
