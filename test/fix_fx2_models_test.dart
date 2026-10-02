import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/apartment_record.dart';
import 'package:site_kapi_kontrol/models/device_record.dart';
import 'package:site_kapi_kontrol/models/door_access_log_record.dart';
import 'package:site_kapi_kontrol/models/door_permission_record.dart';
import 'package:site_kapi_kontrol/models/site_block_record.dart';
import 'package:site_kapi_kontrol/models/site_record.dart';
import 'package:site_kapi_kontrol/models/site_structure_record.dart';
import 'package:site_kapi_kontrol/services/pdf_device_firmware_service.dart';
import 'package:site_kapi_kontrol/ui/dialogs/site_dialog.dart';
import 'package:site_kapi_kontrol/ui/widgets/dynamic_qr_pass_modal.dart';

/// membership_service.getDoorPermissions yanıtının GERÇEK şekli (sunucu anahtarları).
Map<String, dynamic> _serverPermissionsJson() => {
      'ok': true,
      'door': {
        'id': 7,
        'site_code': 101,
        'site_name': 'Güneş Sitesi',
        'door_name': 'A Blok Kapısı',
        'access_scope': 'BLOCK',
        'block_id': 11,
        'block_name': 'A Blok',
      },
      'blocks': [
        {
          'id': 11,
          'block_name': 'A Blok',
          'sort_order': 1,
          'is_door_block': true,
          'total_residents': 3,
          'authorized_count': 2,
          'apartments': [
            {
              'id': 501,
              'unit_label': 'Daire 12',
              'sort_order': 12,
              'resident_count': 2,
              'authorized_count': 2,
              'residents': [
                {
                  'user_code': 1001,
                  'full_name': 'Ayşe Yılmaz',
                  'email': 'ayse@example.com',
                  'role': 'APARTMENT_ADMIN',
                  'has_access': true,
                  'access_source': 'BLOCK_DEFAULT',
                  'override': null,
                },
                {
                  'user_code': 1002,
                  'full_name': 'Ali Yılmaz',
                  'email': 'ali@example.com',
                  'role': 'FAMILY_MEMBER',
                  'has_access': true,
                  'access_source': 'OVERRIDE_ALLOWED',
                  'override': {
                    'id': 9,
                    'is_allowed': true,
                    'notes': 'Misafir kullanım',
                    'updated_at': '2026-05-01T09:30:00.000Z',
                  },
                },
              ],
            },
            {
              'id': 502,
              'unit_label': 'Daire 13',
              'sort_order': 13,
              'resident_count': 1,
              'authorized_count': 0,
              'residents': [
                {
                  'user_code': 1003,
                  'full_name': 'Veli Demir',
                  'email': 'veli@example.com',
                  'role': 'FAMILY_MEMBER',
                  'has_access': false,
                  'access_source': 'OVERRIDE_DENIED',
                  'override': {
                    'id': 10,
                    'is_allowed': false,
                    'notes': null,
                    'updated_at': '2026-05-02T10:00:00.000Z',
                  },
                },
              ],
            },
          ],
        },
      ],
      'total_residents': 3,
      'total_authorized': 2,
    };

SiteRecord _siteFromJson({List<int>? blockCounts, String approval = 'approved'}) {
  return SiteRecord.fromJson({
    'id': 101,
    'name': 'Güneş Sitesi',
    'block_count': 2,
    'apartment_count': 54,
    'door_count': 1,
    'approval_status': approval,
    'block_apartment_counts': ?blockCounts,
  });
}

void main() {
  group('DoorPermissionsData: sunucunun gerçek anahtarlarını okur (membership#2, models-json#1)', () {
    test('sunucu şekli: has_access/role/override/unit_label/authorized_count/site_code', () {
      final data = DoorPermissionsData.fromJson(_serverPermissionsJson());

      expect(data.door.siteId, 101, reason: 'site_code okunur');
      expect(data.door.blockId, 11);
      expect(data.door.isBlockScope, isTrue);

      final block = data.blocks.single;
      expect(block.allowedResidentsCount, 2, reason: 'authorized_count okunur');
      expect(block.totalResidents, 3);
      expect(block.totalApartments, 2, reason: 'sunucu göndermez: daire listesinden türetilir');

      final apt = block.apartments.first;
      expect(apt.doorNumber, 'Daire 12', reason: 'unit_label okunur');
      expect(apt.label, 'Daire 12', reason: '"Daire Daire 12" olmaz');

      final admin = apt.residents[0];
      expect(admin.canOpen, isTrue, reason: 'has_access okunur');
      expect(admin.memberRole, 'APARTMENT_ADMIN');
      expect(admin.roleLabel, 'Daire Admini');
      expect(admin.isBlockDefault, isTrue);
      expect(admin.overrideAllowed, isNull);

      final member = apt.residents[1];
      expect(member.canOpen, isTrue);
      expect(member.roleLabel, 'Aile Üyesi');
      expect(member.isOverrideAllowed, isTrue);
      expect(member.overrideAllowed, isTrue);
      expect(member.overrideNotes, 'Misafir kullanım');
      expect(member.overrideUpdatedAt, '2026-05-01T09:30:00.000Z');

      final denied = block.apartments[1].residents.single;
      expect(denied.canOpen, isFalse);
      expect(denied.isOverrideDenied, isTrue);
      expect(denied.overrideAllowed, isFalse);
      expect(denied.overrideNotes, isNull);
    });

    test('eski anahtarlar (can_open, member_role, override_*, door_number, allowed_residents_count) çalışır', () {
      final data = DoorPermissionsData.fromJson({
        'door': {'id': 1, 'site_id': 5, 'door_name': 'Ana', 'access_scope': 'SITE_COMMON'},
        'blocks': [
          {
            'id': 2,
            'block_name': 'B Blok',
            'total_apartments': 4,
            'total_residents': 6,
            'allowed_residents_count': 5,
            'apartments': [
              {
                'id': 3,
                'door_number': '5',
                'floor': 2,
                'residents': [
                  {
                    'user_code': 9,
                    'full_name': 'Eski İstemci',
                    'member_role': 'ADMIN',
                    'can_open': true,
                    'access_source': 'OVERRIDE_ALLOWED',
                    'override_allowed': true,
                    'override_notes': 'not',
                    'override_updated_at': '2026-01-01',
                  },
                ],
              },
            ],
          },
        ],
      });

      expect(data.door.siteId, 5);
      final block = data.blocks.single;
      expect(block.totalApartments, 4);
      expect(block.allowedResidentsCount, 5);
      final apt = block.apartments.single;
      expect(apt.doorNumber, '5');
      expect(apt.label, 'Daire 5', reason: 'yalnız sayı gelirse önek eklenir');
      expect(apt.floor, 2);
      final r = apt.residents.single;
      expect(r.canOpen, isTrue);
      expect(r.roleLabel, 'Daire Admini');
      expect(r.overrideAllowed, isTrue);
      expect(r.overrideNotes, 'not');
      expect(r.overrideUpdatedAt, '2026-01-01');
    });

    test('has_access varsa can_open yerine o esas alınır; ikisi de yoksa kapalı', () {
      expect(
        DoorResidentPermission.fromJson({'has_access': false, 'can_open': true}).canOpen,
        isFalse,
      );
      expect(DoorResidentPermission.fromJson({'user_code': 1}).canOpen, isFalse);
    });

    test('blok sayaçları yoksa daire/sakin listelerinden türetilir', () {
      final data = DoorPermissionsData.fromJson({
        'blocks': [
          {
            'id': 1,
            'block_name': 'C Blok',
            'apartments': [
              {
                'id': 1,
                'unit_label': 'Daire 1',
                'residents': [
                  {'user_code': 1, 'full_name': 'A', 'has_access': true},
                  {'user_code': 2, 'full_name': 'B', 'has_access': false},
                ],
              },
            ],
          },
        ],
      });
      final block = data.blocks.single;
      expect(block.totalResidents, 2);
      expect(block.allowedResidentsCount, 1);
      expect(block.totalApartments, 1);
    });
  });

  group('DeviceRecord donanım ve sahiplik alanları (models-json#3/#4, device-ota-logs#4/#5)', () {
    Map<String, dynamic> base(Map<String, dynamic> extra) => {
          'id': 1,
          'device_uid': 'ESP32_TEST',
          ...extra,
        };

    test('hardware_target esas alınır, yoksa hardware_type türetilir', () {
      expect(
        DeviceRecord.fromJson(base({'hardware_target': 'esp32-wroom', 'hardware_type': 'esp32_c3'}))
            .hardwareTarget,
        'esp32-wroom',
      );
      final fromType = DeviceRecord.fromJson(base({'hardware_type': 'esp32_wroom'}));
      expect(fromType.hardwareTarget, 'esp32-wroom');
      expect(fromType.hardwareType, 'esp32_wroom');
      expect(DeviceRecord.fromJson(base({})).hardwareTarget, isNull,
          reason: 'bilgi yoksa uydurulmaz ("ESP32-C3" yazılmaz)');
    });

    test('kayıtlı tür ile cihazın bildirdiği hedef çelişirse uyarı bayrağı', () {
      expect(
        DeviceRecord.fromJson(base({'hardware_target': 'esp32-wroom', 'hardware_type': 'esp32_c3'}))
            .hasHardwareMismatch,
        isTrue,
      );
      expect(
        DeviceRecord.fromJson(base({'hardware_target': 'esp32-c3', 'hardware_type': 'esp32_c3'}))
            .hasHardwareMismatch,
        isFalse,
      );
      expect(DeviceRecord.fromJson(base({'hardware_type': 'esp32_c3'})).hasHardwareMismatch, isFalse);
    });

    test('owner_user_code okunur; yalnız owner_user_id/sahip adı olsa da hasOwner true', () {
      final byCode = DeviceRecord.fromJson(base({'owner_user_code': 4242}));
      expect(byCode.ownerUserCode, 4242);
      expect(byCode.hasOwner, isTrue);

      final byId = DeviceRecord.fromJson(base({'owner_user_id': 17}));
      expect(byId.ownerUserCode, isNull);
      expect(byId.ownerUserId, 17);
      expect(byId.hasOwner, isTrue);

      expect(DeviceRecord.fromJson(base({'owner_full_name': 'Ayşe Y.'})).hasOwner, isTrue);
      expect(DeviceRecord.fromJson(base({'owner_user_id': null})).hasOwner, isFalse);
    });
  });

  group('Cihaz günlüğü tetikleyici etiketleri (door-open#2, models-json#5, device-ota-logs#7)', () {
    DoorAccessLogRecord log(String trigger) =>
        DoorAccessLogRecord.fromJson({'id': 1, 'trigger_type': trigger});

    // door_log_service.ALLOWED_TRIGGER_TYPES ile aynı liste.
    const allowed = <String>[
      'cloud_app',
      'voice',
      'local_wifi',
      'local_udp',
      'local_http',
      'local_ble',
      'ble',
      'guest_pass',
      'offline_sync',
      'qr_scanner',
      'screen_qr',
      'display_btn',
      'admin_display_btn',
      'physical_btn',
      'serial_btn',
      'mqtt',
      'mqtt_pulse',
      'remote',
    ];

    test('yeni cihaz tetikleyicileri "Mobil Bulut" olarak etiketlenmez', () {
      expect(log('local_udp').triggerTypeDisplay, 'Yerel Wi-Fi (UDP)');
      expect(log('local_http').triggerTypeDisplay, 'Yerel Wi-Fi (HTTP)');
      expect(log('local_ble').triggerTypeDisplay, 'Bluetooth');
      expect(log('ble').triggerTypeDisplay, 'Bluetooth');
      expect(log('admin_display_btn').triggerTypeDisplay, 'Ekran Yönetici PIN');
      expect(log('serial_btn').triggerTypeDisplay, 'Seri Port');
      for (final cloud in ['cloud_app', 'mqtt', 'mqtt_pulse', 'remote']) {
        expect(log(cloud).triggerTypeDisplay, 'Mobil Bulut');
      }
    });

    test('bilinmeyen tür uydurulmaz, ham değer gösterilir', () {
      expect(log('yeni_tur').triggerTypeDisplay, 'yeni_tur');
    });

    test('sunucunun izin verdiği her tür bir gruba girer ve gruplar toplamı tutar', () {
      const groups = {'cloud', 'local', 'guest', 'voice', 'offline', 'other'};
      final counts = <String, int>{};
      for (final trigger in allowed) {
        final group = log(trigger).triggerGroup;
        expect(groups, contains(group));
        counts[group] = (counts[group] ?? 0) + 1;
      }
      expect(counts.values.fold<int>(0, (a, b) => a + b), allowed.length);
      expect(log('local_udp').triggerGroup, 'local');
      expect(log('local_http').triggerGroup, 'local');
      expect(log('serial_btn').triggerGroup, 'other');
      expect(log('mqtt').triggerGroup, 'cloud');
    });
  });

  group('SiteDialog gerçek daire sayıları (models-json#0, site-manager-admin#1)', () {
    SiteStructureRecord structure({
      required List<List<int>> apartmentsPerBlock,
      List<int>? storedCounts,
    }) {
      final blocks = <SiteBlockRecord>[];
      final apartments = <ApartmentRecord>[];
      var aptId = 1;
      for (var b = 0; b < apartmentsPerBlock.length; b++) {
        blocks.add(SiteBlockRecord.fromJson({
          'id': 100 + b,
          'site_code': 101,
          'block_name': '${String.fromCharCode(65 + b)} Blok',
          'sort_order': b + 1,
        }));
        for (final _ in apartmentsPerBlock[b]) {
          apartments.add(ApartmentRecord.fromJson({
            'id': aptId++,
            'site_code': 101,
            'block_id': 100 + b,
          }));
        }
      }
      return SiteStructureRecord(
        site: _siteFromJson(blockCounts: storedCounts),
        blocks: blocks,
        apartments: apartments,
        doors: const [],
      );
    }

    test('blok başına mevcut daire adedi sıra numarasına göre türetilir', () {
      final s = structure(
        apartmentsPerBlock: [List.filled(24, 0), List.filled(30, 0)],
      );
      expect(siteBlockApartmentCountsFromStructure(s), [24, 30]);
    });

    test('blok sırası sort_order ile belirlenir (liste sırası değil)', () {
      final s = structure(apartmentsPerBlock: [List.filled(3, 0), List.filled(5, 0)]);
      final reversed = SiteStructureRecord(
        site: s.site,
        blocks: s.blocks.reversed.toList(),
        apartments: s.apartments,
        doors: const [],
      );
      expect(siteBlockApartmentCountsFromStructure(reversed), [3, 5]);
    });

    test('daire listesi boşsa sunucuda saklanan dizi kullanılır; o da yoksa boş döner', () {
      final stored = structure(apartmentsPerBlock: [const [], const []], storedCounts: [12, 8]);
      expect(siteBlockApartmentCountsFromStructure(stored), [12, 8]);
      final none = structure(apartmentsPerBlock: [const [], const []]);
      expect(siteBlockApartmentCountsFromStructure(none), isEmpty);
    });
  });

  group('PDF sürüm raporu hedef sürümü (device-ota-logs#10)', () {
    DeviceRecord dev(String uid, String? target, String? version) => DeviceRecord.fromJson({
          'id': uid.hashCode,
          'device_uid': uid,
          'hardware_target': ?target,
          'firmware_version': ?version,
        });

    test('sürümler sayısal karşılaştırılır (1.10.0 > 1.9.0, v öneki yok sayılır)', () {
      expect(PdfDeviceFirmwareService.compareFirmwareVersions('4.2.0', '4.10.0'), lessThan(0));
      expect(PdfDeviceFirmwareService.compareFirmwareVersions('v5.1.0', '5.1.0'), 0);
      expect(PdfDeviceFirmwareService.compareFirmwareVersions('5.1', '5.1.0'), 0);
      expect(PdfDeviceFirmwareService.compareFirmwareVersions('5.2.0', '5.1.9'), greaterThan(0));
    });

    test('her donanım hedefi için en yüksek bildirilen sürüm bulunur', () {
      final latest = PdfDeviceFirmwareService.latestVersionsByTarget([
        dev('a', 'esp32-c3', '4.1.0'),
        dev('b', 'esp32-c3', '4.2.0'),
        dev('c', 'esp32-wroom', '5.0.0'),
        dev('d', 'esp32-wroom', 'v5.1.0'),
        dev('e', 'esp32-wroom', 'Bilinmiyor'),
        dev('f', 'esp32-c3', null),
      ]);
      expect(latest, {'esp32-c3': '4.2.0', 'esp32-wroom': '5.1.0'});
    });
  });

  group('Karekod modalı ret nedenleri (door-open#8, models-json#9)', () {
    test('kalıcı ret nedenleri anlaşılır Türkçe mesaj üretir ve yoklamayı durdurur', () {
      for (final reason in [
        'ACCESS_REVOKED',
        'QR_DISABLED',
        'QR_ENTRY_INACTIVE',
        'TOKEN_OR_USER_INACTIVE',
        'ADMIN_REVOKED',
      ]) {
        final info = qrDenialInfoFor(reason);
        expect(info, isNotNull, reason: reason);
        expect(info!.permanent, isTrue, reason: reason);
        expect(info.title.trim(), isNotEmpty);
        expect(info.message.trim(), isNotEmpty);
      }
      expect(qrDenialInfoFor('QR_DISABLED')!.message, contains('QR ile giriş kapalı'));
    });

    test('PULSE_FAILED geçici (kod hâlâ geçerli), EXPIRED_TOKEN süre dolumu olarak işlenir', () {
      final pulse = qrDenialInfoFor('PULSE_FAILED')!;
      expect(pulse.permanent, isFalse);
      expect(pulse.expired, isFalse);
      expect(pulse.message, contains('tekrar gösterin'));

      expect(qrDenialInfoFor('EXPIRED_TOKEN')!.expired, isTrue);
    });

    test('kendi rozetleri olan / kullanıcı kaynaklı nedenler ayrıca işlenmez', () {
      for (final reason in ['ALREADY_USED', 'SUPERSEDED', 'DOOR_MISMATCH', 'REVOKED', 'USER_REVOKED', null, 'XYZ']) {
        expect(qrDenialInfoFor(reason), isNull, reason: '$reason');
      }
    });
  });
}
