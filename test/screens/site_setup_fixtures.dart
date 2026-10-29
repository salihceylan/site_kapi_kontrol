// Site kurulum sihirbazı (P2-15) testlerinin ortak sahte servisi. `_test.dart` ile bitmediği için kendi başına test
// olarak çalışmaz.
//
// Finans sahtesinin ([FinanceFakeAuth]) üstüne kurulur: kişi listesi, aidat tanımları, dönemler ve oturum oradan
// gelir. Burada yalnız sihirbazın okuduğu iki uç yapılandırılır: site yapısı (`getSiteStructure`: blok + daire
// sayıları, yönetim türü terimleri) ve site modülleri (`getSiteModules`). Hata kancaları "durum alınamadı" yolunu sınar.
import 'dart:async';

import 'package:site_kapi_kontrol/models/platform_module.dart';
import 'package:site_kapi_kontrol/models/site_structure_record.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';

import 'finance_fixtures.dart';
import 'modules_fixtures.dart' show mdState;

class SetupWizardFakeAuth extends FinanceFakeAuth {
  SetupWizardFakeAuth({
    super.role,
    super.sites,
    this.siteCode = 11,
    this.siteName = 'Gül Sitesi',
    this.blockCount = 2,
    this.apartmentsPerBlock = 3,
    this.managementTerms,
    this.managementType = 'apartment_site',
    this.typeLabel = 'Apartman ve Site',
    this.city = 'İstanbul',
    this.district = 'Kadıköy',
    this.address,
  });

  /// Süper kullanıcı oturumlu sahte servis.
  factory SetupWizardFakeAuth.superUser({int blockCount = 2, int apartmentsPerBlock = 3}) =>
      SetupWizardFakeAuth(role: UserRole.superUser, blockCount: blockCount, apartmentsPerBlock: apartmentsPerBlock);

  final int siteCode;
  String siteName;
  int blockCount;
  int apartmentsPerBlock;
  Map<String, dynamic>? managementTerms;
  String managementType;
  String typeLabel;
  String? city;
  String? district;
  String? address;

  /// Doluysa `getSiteStructure` bu iletiyle hata döner (sunucu yanıtı alınamadı).
  String? structureError;

  /// Doluysa `getSiteModules` bunu fırlatır.
  Object? modulesError;

  /// Site modülleri yanıtı: varsayılan 8 modüllü katalog (yönetici görünümü).
  SiteModulesState? modulesState;

  /// `updateSite` çağrıları (süper kullanıcının site düzenlemesi) ve sonucu (null: başarılı, doluysa hata iletisi).
  final List<Map<String, Object?>> updateSiteCalls = <Map<String, Object?>>[];
  String? updateSiteResult;

  int setupStructureCalls = 0;
  int modulesCalls = 0;

  /// Kişi sayısı sorgusu için gecikme kapısı (yükleme durumunu sınamak için).
  Completer<void>? structureGate;

  List<Map<String, dynamic>> _blocksJson() => <Map<String, dynamic>>[
    for (var i = 0; i < blockCount; i++)
      <String, dynamic>{
        'id': 100 + i,
        'site_code': siteCode,
        'block_name': '${String.fromCharCode(65 + i)} Blok',
        'sort_order': i,
      },
  ];

  List<Map<String, dynamic>> _apartmentsJson() => <Map<String, dynamic>>[
    for (var b = 0; b < blockCount; b++)
      for (var n = 1; n <= apartmentsPerBlock; n++)
        <String, dynamic>{
          'id': 1000 + b * 100 + n,
          'site_code': siteCode,
          'block_id': 100 + b,
          'block_name': '${String.fromCharCode(65 + b)} Blok',
          'unit_label': '$n',
          'sort_order': n,
          'is_active': true,
        },
  ];

  @override
  Future<(SiteStructureRecord?, String?)> getSiteStructure({required int siteCode}) async {
    setupStructureCalls++;
    final gate = structureGate;
    if (gate != null) await gate.future;
    final error = structureError;
    if (error != null) return (null, error);
    return (
      SiteStructureRecord.fromJson(<String, dynamic>{
        'site': <String, dynamic>{
          'id': siteCode,
          'name': siteName,
          'approval_status': 'approved',
          'management_type': managementType,
          'management_type_label': typeLabel,
          'management_terms': ?managementTerms,
          'city': city,
          'district': district,
          'address': address,
          'block_count': blockCount,
          'apartment_count': blockCount * apartmentsPerBlock,
          'created_at': '2026-10-01T12:30:00Z',
        },
        'blocks': _blocksJson(),
        'apartments': _apartmentsJson(),
        'doors': <dynamic>[],
      }),
      null,
    );
  }

  @override
  Future<SiteModulesState> getSiteModules(int siteCode) async {
    modulesCalls++;
    final error = modulesError;
    if (error != null) throw error;
    return modulesState ??
        mdState(siteCode, siteName, financeAvailable: true, superView: role == UserRole.superUser);
  }

  @override
  Future<String?> updateSite({
    required int siteCode,
    String? name,
    String? address,
    String? city,
    String? district,
    List<int>? blockApartmentCounts,
    int? doorCount,
    int? managerUserCode,
  }) async {
    updateSiteCalls.add(<String, Object?>{
      'site': siteCode,
      'name': name,
      'address': address,
      'city': city,
      'district': district,
      'counts': blockApartmentCounts,
      'doors': doorCount,
      'manager': managerUserCode,
    });
    final result = updateSiteResult;
    if (result != null) return result;
    if (name != null) siteName = name;
    if (blockApartmentCounts != null && blockApartmentCounts.isNotEmpty) {
      blockCount = blockApartmentCounts.length;
      apartmentsPerBlock = blockApartmentCounts.first;
    }
    return null;
  }
}
