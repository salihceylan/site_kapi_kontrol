// Platform Faz 2a (Kişi ve Daire Kayıtları): ekran / pencere testlerinin ortak örnek verisi ve sahte
// servisi. `_test.dart` ile bitmediği için kendi başına test olarak çalışmaz.
//
// Sahte servis sunucuyu taklit eder: kayıtlar JSON olarak tutulur, listeler arama / süzgeç / sayfalama
// uygular, yazmalar kaydı değiştirir ve sunucu kurallarını (hesaplı kişi, tek malik / kiracı, yinelenen
// plaka) aynı Türkçe mesajlarla reddeder. Yarış testleri için her liste çağrısı kuyruktaki bir kapıyı
// bekleyebilir (yanıt çağrı ANINDA hesaplanır, kapı açılınca teslim edilir).
import 'dart:async';

import 'package:site_kapi_kontrol/models/apartment_crm.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/models/history_item.dart';
import 'package:site_kapi_kontrol/models/person_record.dart';
import 'package:site_kapi_kontrol/models/residency_relation.dart';
import 'package:site_kapi_kontrol/models/site_page.dart';
import 'package:site_kapi_kontrol/models/site_manager_record.dart';
import 'package:site_kapi_kontrol/models/site_record.dart';
import 'package:site_kapi_kontrol/models/staff_role_record.dart';
import 'package:site_kapi_kontrol/models/team.dart';
import 'package:site_kapi_kontrol/models/site_structure_record.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/models/vehicle_record.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';

import 'modules_fixtures.dart' show ModuleRequestFixtures;

SiteRecord pplSite(int id, String name, {String approval = 'approved'}) =>
    SiteRecord.fromJson(<String, dynamic>{
      'id': id,
      'name': name,
      'approval_status': approval,
      'created_at': '2026-10-01T12:30:00Z',
    });

/// Bir daire ilişkisi: (daire no, etiket, ilişki).
typedef PplApt = (int, String, ResidencyRelation);

Map<String, dynamic> pplPersonJson(
  int id,
  String name, {
  String? phone,
  String? email,
  bool account = false,
  bool active = true,
  List<PplApt> apts = const <PplApt>[],
  List<PplApt> pastApts = const <PplApt>[],
  List<Map<String, dynamic>> vehicles = const <Map<String, dynamic>>[],
  String? note,
  String moveIn = '2024-03-05',

  /// `internal` (dahili @ahbu.local hesabı), `registered`, `none`; varsayılan hesaba göre.
  String? accountKind,
}) {
  var residencyId = id * 100;
  Map<String, dynamic> residency(PplApt a, {required bool current}) {
    residencyId++;
    return <String, dynamic>{
      'id': residencyId,
      'apartment_id': a.$1,
      'label': a.$2,
      'block_name': a.$2.split(' - ').first,
      'relation': a.$3.apiValue,
      'is_current': current,
      'move_in_date': moveIn,
      'move_out_date': current ? null : '2025-01-31',
    };
  }

  return <String, dynamic>{
    'id': id,
    'full_name': name,
    'phone': phone,
    'email': email,
    'has_account': account,
    'account_kind': accountKind ?? (account ? 'registered' : 'none'),
    'is_active': active,
    'relations': <String>[for (final a in apts) a.$3.apiValue],
    'apartments': <Map<String, dynamic>>[
      for (final a in apts)
        <String, dynamic>{
          'apartment_id': a.$1,
          'label': a.$2,
          'block_name': a.$2.split(' - ').first,
          'relation': a.$3.apiValue,
        },
    ],
    'vehicle_count': vehicles.length,
    'note': note,
    'created_at': '2026-09-01T10:00:00Z',
    'residencies': <Map<String, dynamic>>[
      for (final a in apts) residency(a, current: true),
      for (final a in pastApts) residency(a, current: false),
    ],
    // Değiştirilebilir liste: sahte servis araç ekler / kaldırır.
    'vehicles': List<Map<String, dynamic>>.of(vehicles),
    'user_code': account ? 700 + id : null,
  };
}

Map<String, dynamic> pplVehicleJson(
  int id,
  String plate, {
  String? display,
  String? person,
  int? personId,
  String? apartment,
  String? note,
}) => <String, dynamic>{
  'id': id,
  'plate': plate.replaceAll(' ', '').toUpperCase(),
  'plate_display': display ?? plate,
  'note': note,
  'person_id': personId,
  'person_name': person,
  'apartment_label': apartment,
  'is_active': true,
};

Map<String, dynamic> pplApartmentJson(
  int id,
  String label, {
  int blockId = 1,
  int? floor,
  String? category,
  double? gross,
  double? net,
  int? shareN,
  int? shareD,
  String party = 'both',
  Map<String, dynamic>? owner,
  Map<String, dynamic>? tenant,
  List<Map<String, dynamic>> current = const <Map<String, dynamic>>[],
  List<Map<String, dynamic>> past = const <Map<String, dynamic>>[],
}) => <String, dynamic>{
  'id': id,
  'label': label,
  'block_id': blockId,
  'block_name': label.split(' - ').first,
  'floor': floor,
  'category': category,
  'gross_area_m2': gross,
  'net_area_m2': net,
  'land_share': shareN == null ? null : <String, dynamic>{'numerator': shareN, 'denominator': shareD},
  'responsible_party': party,
  'owner': owner,
  'tenant': tenant,
  'resident_count': current.length,
  'current_residents': current,
  'past_residents': past,
};

Map<String, dynamic> pplResidentJson(
  int residencyId,
  int personId,
  String name,
  ResidencyRelation relation, {
  bool account = false,
  String? moveOut,
}) => <String, dynamic>{
  'residency_id': residencyId,
  'person_id': personId,
  'full_name': name,
  'relation': relation.apiValue,
  'move_in_date': '2024-03-05',
  'move_out_date': moveOut,
  'has_account': account,
};

HistoryItem pplHistory(
  int id, {
  String action = 'person.updated',
  String actor = 'Site Yöneticisi',
  // Sunucu telefon / e-posta / not değişikliğinde eski-yeni değer GÖNDERMEZ (`changed: true`).
  List<Map<String, dynamic>> changes = const <Map<String, dynamic>>[
    <String, dynamic>{'field': 'phone', 'changed': true},
  ],
  Map<String, dynamic> extra = const <String, dynamic>{},
  String role = 'site_manager',
}) => HistoryItem.fromJson(<String, dynamic>{
  'id': id,
  'created_at': '2026-10-15T09:30:00Z',
  'actor_name': actor,
  'actor_role': role,
  'action': action,
  'site_code': 11,
  'target_type': 'person',
  'target_id': '1',
  'details': <String, dynamic>{...extra, if (changes.isNotEmpty) 'changes': changes},
});

MyRecord pplMyRecord({
  int apartmentId = 301,
  String site = 'Gül Sitesi',
  String label = 'A Blok - 5',
  ResidencyRelation relation = ResidencyRelation.tenant,
  List<Map<String, dynamic>> vehicles = const <Map<String, dynamic>>[],
}) => MyRecord.fromJson(<String, dynamic>{
  'site_code': 11,
  'site_name': site,
  'apartment_id': apartmentId,
  'label': label,
  'block_name': label.split(' - ').first,
  'relation': relation.apiValue,
  'move_in_date': '2024-03-05',
  'vehicles': vehicles,
});

/// Yönetici oturumu (varsayılan site yöneticisi).
UserSession pplSession(UserRole role) => UserSession(
  id: role == UserRole.superUser ? 1 : 5,
  fullName: role == UserRole.superUser ? 'Süper Yönetici' : 'Site Yöneticisi',
  email: 'kullanici@e2e.local',
  loginName: null,
  role: role,
  isActive: true,
  token: 'tok',
);

/// Kişi ve Daire Kayıtları uçları için sahte servis. Çağrılar kaydedilir; yanıtlar testten sürülür.
class PeopleFakeAuth extends AuthService with ModuleRequestFixtures {
  PeopleFakeAuth({
    List<SiteRecord>? sites,
    Map<int, Map<String, dynamic>>? people,
    Map<int, Map<String, dynamic>>? apartments,
    List<Map<String, dynamic>>? vehicles,
    this.role = UserRole.siteManager,
    this.blocks = const <({int id, String name})>[(id: 1, name: 'A Blok'), (id: 2, name: 'B Blok')],
  }) : sites = sites ?? <SiteRecord>[pplSite(11, 'Gül Sitesi')],
       peopleJson = people ?? <int, Map<String, dynamic>>{},
       apartmentsJson = apartments ?? <int, Map<String, dynamic>>{},
       vehiclesJson = vehicles ?? <Map<String, dynamic>>[],
       super(api: AuthApi(baseUrl: 'http://localhost'));

  /// Standart veri: 3 kişi (malik, hesaplı kiracı, eski sakin), 2 daire, 2 araç.
  factory PeopleFakeAuth.seeded({UserRole role = UserRole.siteManager}) {
    final auth = PeopleFakeAuth(role: role);
    auth.peopleJson[1] = pplPersonJson(
      1,
      'Ayşe Yılmaz',
      phone: '+905551112233',
      email: 'ayse@example.com',
      apts: const <PplApt>[(301, 'A Blok - 5', ResidencyRelation.owner)],
      vehicles: <Map<String, dynamic>>[
        pplVehicleJson(1, '34 ABC 123', person: 'Ayşe Yılmaz', personId: 1, apartment: 'A Blok - 5'),
      ],
      note: 'Kapıcıya haber verildi.',
    );
    auth.peopleJson[2] = pplPersonJson(
      2,
      'Mehmet Demir',
      phone: '+905322223344',
      email: 'mehmet@example.com',
      account: true,
      apts: const <PplApt>[(302, 'A Blok - 6', ResidencyRelation.tenant)],
      pastApts: const <PplApt>[(303, 'B Blok - 2', ResidencyRelation.tenant)],
    );
    auth.peopleJson[3] = pplPersonJson(
      3,
      'Zeynep Kaya',
      active: false,
      pastApts: const <PplApt>[(301, 'A Blok - 5', ResidencyRelation.familyMember)],
    );
    auth.apartmentsJson[301] = pplApartmentJson(
      301,
      'A Blok - 5',
      floor: 2,
      category: '3+1',
      gross: 120.5,
      net: 100,
      shareN: 35,
      shareD: 1000,
      owner: <String, dynamic>{'person_id': 1, 'full_name': 'Ayşe Yılmaz'},
      current: <Map<String, dynamic>>[
        pplResidentJson(101, 1, 'Ayşe Yılmaz', ResidencyRelation.owner),
      ],
      past: <Map<String, dynamic>>[
        pplResidentJson(301, 3, 'Zeynep Kaya', ResidencyRelation.familyMember, moveOut: '2025-01-31'),
      ],
    );
    auth.apartmentsJson[302] = pplApartmentJson(
      302,
      'A Blok - 6',
      tenant: <String, dynamic>{'person_id': 2, 'full_name': 'Mehmet Demir'},
      current: <Map<String, dynamic>>[
        pplResidentJson(201, 2, 'Mehmet Demir', ResidencyRelation.tenant, account: true),
      ],
    );
    auth.apartmentsJson[303] = pplApartmentJson(303, 'B Blok - 2', blockId: 2);
    auth.vehiclesJson.add(
      pplVehicleJson(1, '34 ABC 123', person: 'Ayşe Yılmaz', personId: 1, apartment: 'A Blok - 5'),
    );
    auth.vehiclesJson.add(
      pplVehicleJson(2, '06 XYZ 789', person: 'Mehmet Demir', personId: 2, apartment: 'A Blok - 6'),
    );
    return auth;
  }

  List<SiteRecord> sites;
  final Map<int, Map<String, dynamic>> peopleJson;
  final Map<int, Map<String, dynamic>> apartmentsJson;
  final List<Map<String, dynamic>> vehiclesJson;
  UserRole role;
  final List<({int id, String name})> blocks;

  /// Sayfa boyutu üst sınırı: sunucu `limit`'i bununla keser (sayfalama testleri için küçük verilir).
  int? maxPage;

  /// Doluysa liste yanıtlarında `total` yerine bu değer döner (tutarsız sunucu simülasyonu).
  int? totalOverride;

  /// Kişi eklenince yanıttaki `credentials_sent` (null: alan yok).
  bool? nextCredentialsSent;

  /// Kişi eklenince yanıttaki `credentials_email` (null: alan yok). null + adres = gönderim sürüyor.
  String? nextCredentialsEmail;

  /// PERSON_EXISTS yanıtında `person_id` bulunsun mu? (false: alan yok.)
  bool personExistsHasId = true;

  // --- Çağrı kayıtları -------------------------------------------------------------------------
  final List<({int site, String? query, ResidencyRelation? relation, String? status, int limit, int offset})>
  peopleCalls =
      <({int site, String? query, ResidencyRelation? relation, String? status, int limit, int offset})>[];
  final List<({int site, String? query, int? block, int limit, int offset})> apartmentCalls =
      <({int site, String? query, int? block, int limit, int offset})>[];
  final List<({int site, String? query, int limit, int offset})> vehicleCalls =
      <({int site, String? query, int limit, int offset})>[];
  final List<int> getPersonCalls = <int>[];
  final List<int> getApartmentCalls = <int>[];
  final List<Map<String, Object?>> createPersonCalls = <Map<String, Object?>>[];
  final List<({int id, Map<String, Object?> fields})> updatePersonCalls =
      <({int id, Map<String, Object?> fields})>[];
  final List<({int person, int apartment, ResidencyRelation relation, DateTime? date})> addResidencyCalls =
      <({int person, int apartment, ResidencyRelation relation, DateTime? date})>[];
  final List<({int residency, ResidencyRelation? relation, DateTime? date, bool clear})>
  updateResidencyCalls =
      <({int residency, ResidencyRelation? relation, DateTime? date, bool clear})>[];
  final List<({int residency, DateTime? date})> endResidencyCalls =
      <({int residency, DateTime? date})>[];
  final List<({int id, Map<String, Object?> fields})> updateApartmentCalls =
      <({int id, Map<String, Object?> fields})>[];
  final List<({int person, String plate, String? note})> createVehicleCalls =
      <({int person, String plate, String? note})>[];
  final List<int> removeVehicleCalls = <int>[];
  final List<({int site, String? type, int? id, int? before})> historyCalls =
      <({int site, String? type, int? id, int? before})>[];
  int listSitesCalls = 0;
  final List<({int page, int pageSize, String? approval})> listSitesArgs =
      <({int page, int pageSize, String? approval})>[];
  int myRecordsCalls = 0;
  int structureCalls = 0;

  // --- Davranış kancaları ----------------------------------------------------------------------
  Object? peopleError;
  Object? apartmentsError;
  Object? vehiclesError;
  Object? personError;
  Object? apartmentError;
  Object? writeError;

  /// null değilse her yazma çağrısı (kaydı yaptıktan sonra) bu kapıyı bekler: gönderim sürerken davranış.
  Completer<void>? writeGate;
  Object? historyError;
  Object? myRecordsError;
  Object? listSitesError;
  bool structureFails = false;

  /// Her liste çağrısı kuyruktaki ilk kapıyı bekler (yanıt çağrı anında hesaplanır).
  final List<Completer<void>> peopleGates = <Completer<void>>[];
  final List<Completer<void>> apartmentGates = <Completer<void>>[];
  final List<Completer<void>> vehicleGates = <Completer<void>>[];
  final List<Completer<void>> historyGates = <Completer<void>>[];
  Completer<void>? personGate;
  Completer<void>? apartmentGate;
  Completer<void>? sitesGate;
  Completer<void>? myRecordsGate;

  /// Sıradaki geçmiş sayfaları (boşsa tek boş sayfa).
  List<HistoryPage> historyPages = <HistoryPage>[];
  List<MyRecord> myRecords = <MyRecord>[];

  @override
  UserSession? get session => pplSession(role);

  @override
  bool get isLoggedIn => true;

  Future<void> _writeWait() async {
    final gate = writeGate;
    if (gate != null) await gate.future;
  }

  Future<void> _gate(List<Completer<void>> queue) async {
    if (queue.isEmpty) return;
    await queue.removeAt(0).future;
  }

  int _limit(int limit) => maxPage == null ? limit : (limit < maxPage! ? limit : maxPage!);

  static bool _has(Object? value, String q) => (value?.toString() ?? '').toLowerCase().contains(q);

  @override
  Future<SitePage> listSites({
    required int page,
    int pageSize = 10,
    String? approvalStatus,
  }) async {
    listSitesCalls++;
    listSitesArgs.add((page: page, pageSize: pageSize, approval: approvalStatus));
    final gate = sitesGate;
    if (gate != null) await gate.future;
    final error = listSitesError;
    if (error != null) throw error;
    final filtered = approvalStatus == 'approved'
        ? sites.where((s) => s.isApproved).toList()
        : sites;
    final start = (page - 1) * pageSize;
    final items = filtered.skip(start).take(pageSize).toList();
    return SitePage(sites: items, total: filtered.length, page: page, pageSize: pageSize);
  }

  @override
  Future<(SiteStructureRecord?, String?)> getSiteStructure({required int siteCode}) async {
    structureCalls++;
    if (structureFails) return (null, 'Bu islem icin site yonetim yetkisi gerekir.');
    return (
      SiteStructureRecord.fromJson(<String, dynamic>{
        'site': <String, dynamic>{
          'id': siteCode,
          'name': 'Gül Sitesi',
          'approval_status': 'approved',
          'created_at': '2026-10-01T12:30:00Z',
        },
        'blocks': <Map<String, dynamic>>[
          for (final b in blocks)
            <String, dynamic>{
              'id': b.id,
              'site_code': siteCode,
              'block_name': b.name,
              'sort_order': b.id,
            },
        ],
        'apartments': <dynamic>[],
        'doors': <dynamic>[],
      }),
      null,
    );
  }

  // --- Kişiler ---------------------------------------------------------------------------------

  @override
  Future<PersonPage> listPeople(
    int siteCode, {
    String? query,
    ResidencyRelation? relation,
    String? status,
    int? apartmentId,
    int limit = 50,
    int offset = 0,
  }) async {
    peopleCalls.add((
      site: siteCode,
      query: query,
      relation: relation,
      status: status,
      limit: limit,
      offset: offset,
    ));
    final q = (query ?? '').trim().toLowerCase();
    final rows = peopleJson.values.where((json) {
      final active = json['is_active'] == true;
      final wanted = status ?? 'active';
      if (wanted == 'active' && !active) return false;
      if (wanted == 'inactive' && active) return false;
      if (relation != null && !(json['relations'] as List).contains(relation.apiValue)) {
        return false;
      }
      if (q.isEmpty) return true;
      return _has(json['full_name'], q) ||
          _has(json['phone'], q) ||
          _has(json['email'], q) ||
          (json['apartments'] as List).any((a) => _has((a as Map)['label'], q));
    }).toList();
    final page = rows.skip(offset).take(_limit(limit)).toList();
    final result = PersonPage(
      items: [for (final json in page) PersonSummary.fromJson(json)],
      total: totalOverride ?? rows.length,
    );
    await _gate(peopleGates);
    final error = peopleError;
    if (error != null) throw error;
    return result;
  }

  // Kişi kartı "Roller" bölümü (ek roller, yöneticiler / davetler, kapılar).
  final List<StaffRoleRecord> staffRoles = <StaffRoleRecord>[];
  final List<SiteManagerRecord> siteManagers = <SiteManagerRecord>[];
  final List<SiteManagerInvitationRecord> managerInvitations = <SiteManagerInvitationRecord>[];
  final List<DoorRecord> myDoors = <DoorRecord>[];
  final List<({String email, String role})> staffAssignCalls = <({String email, String role})>[];
  final List<int> staffRemoveCalls = <int>[];
  final List<String> managerInviteCalls = <String>[];
  Object? staffAssignError;

  @override
  Future<List<StaffRoleRecord>> listStaffRoles(int siteCode) async => List<StaffRoleRecord>.of(staffRoles);

  // Yönetim kadrosu ve davet (058): kişi kimliğine göre görev, davet durumu ve çağrı kayıtları.
  final Map<int, TeamDuty> teamDuties = <int, TeamDuty>{};
  final Map<int, PersonInvitationState> invitations = <int, PersonInvitationState>{};
  final List<({int personId, String duty, String? title, String? phone, bool show})> dutyCalls =
      <({int personId, String duty, String? title, String? phone, bool show})>[];
  final List<int> dutyEndCalls = <int>[];
  final List<int> inviteSendCalls = <int>[];
  final List<int> inviteRevokeCalls = <int>[];
  final List<DirectoryContact> teamContacts = <DirectoryContact>[];
  bool teamDirectoryEnabled = false;

  @override
  Future<TeamData> getTeam(int siteCode) async => TeamData(
    managers: const <String>['Yönetici Kişi'],
    duties: teamDuties.values.toList(),
    legacyRoles: <LegacyStaffRole>[
      for (final r in staffRoles) LegacyStaffRole(userCode: r.userCode, fullName: r.fullName, role: r.role),
    ],
    contacts: List<DirectoryContact>.of(teamContacts),
    directoryEnabled: teamDirectoryEnabled,
  );

  @override
  Future<String?> setTeamDuty(
    int siteCode,
    int personId, {
    required String duty,
    String? title,
    String? publicPhone,
    bool showInDirectory = true,
  }) async {
    dutyCalls.add((personId: personId, duty: duty, title: title, phone: publicPhone, show: showInDirectory));
    final person = peopleJson[personId];
    teamDuties[personId] = TeamDuty(
      personId: personId,
      fullName: person?['full_name'] as String? ?? 'Kişi',
      duty: duty,
      title: title,
      publicPhone: publicPhone,
      showInDirectory: showInDirectory,
      access: person?['has_account'] == true ? 'granted' : 'no_account',
    );
    return teamDuties[personId]!.access;
  }

  @override
  Future<void> endTeamDuty(int siteCode, int personId) async {
    dutyEndCalls.add(personId);
    teamDuties.remove(personId);
  }

  @override
  Future<PersonInvitationState> getPersonInvitation(int siteCode, int personId) async =>
      invitations[personId] ?? const PersonInvitationState();

  @override
  Future<PersonInvitationState> sendPersonInvitation(int siteCode, int personId) async {
    inviteSendCalls.add(personId);
    final state = PersonInvitationState(status: 'pending', sendCount: (invitations[personId]?.sendCount ?? 0) + 1, sent: true);
    invitations[personId] = state;
    return state;
  }

  @override
  Future<void> revokePersonInvitation(int siteCode, int personId) async {
    inviteRevokeCalls.add(personId);
    invitations.remove(personId);
  }

  @override
  Future<SiteManagersData?> getSiteManagers(int siteCode) async =>
      SiteManagersData(managers: List.of(siteManagers), invitations: List.of(managerInvitations));

  @override
  Future<StaffRoleRecord> assignStaffRole(int siteCode, String email, String role) async {
    staffAssignCalls.add((email: email, role: role));
    final error = staffAssignError;
    if (error != null) throw error;
    final person = peopleJson.values.firstWhere((p) => p['email'] == email);
    final record = StaffRoleRecord(
      userCode: person['user_code'] as int,
      fullName: person['full_name'] as String? ?? '',
      email: email,
      role: role,
    );
    staffRoles.add(record);
    return record;
  }

  @override
  Future<void> removeStaffRole(int siteCode, int userCode) async {
    staffRemoveCalls.add(userCode);
    staffRoles.removeWhere((r) => r.userCode == userCode);
  }

  @override
  Future<(bool, String?)> inviteSiteManager(int siteCode, {required String email, String? fullName}) async {
    managerInviteCalls.add(email);
    return (true, null);
  }

  @override
  Future<(List<DoorRecord>?, String?)> listMyDoors() async => (List<DoorRecord>.of(myDoors), null);

  @override
  Future<PersonDetail> getPerson(int siteCode, int personId) async {
    getPersonCalls.add(personId);
    // Yanıt çağrı ANINDA hesaplanır (sunucu gibi); kapı açılınca teslim edilir: bayat yanıt testleri.
    final json = peopleJson[personId];
    final snapshot = json == null ? null : PersonDetail.fromJson(json);
    final gate = personGate;
    if (gate != null) await gate.future;
    final error = personError;
    if (error != null) throw error;
    if (snapshot == null) {
      throw ApiException('Kişi bulunamadı.', statusCode: 404, code: 'PERSON_NOT_FOUND');
    }
    return snapshot;
  }

  ApiException _coded(String code, int status, {Map<String, dynamic>? payload}) => ApiException(
    AuthApi.messageForErrorCode(code) ?? code,
    statusCode: status,
    code: code,
    payload: payload,
  );

  @override
  Future<PersonDetail> createPerson(
    int siteCode, {
    required String fullName,
    String? phone,
    String? email,
    String? note,
    int? apartmentId,
    ResidencyRelation? relation,
    DateTime? moveInDate,
  }) async {
    createPersonCalls.add(<String, Object?>{
      'full_name': fullName,
      'phone': phone,
      'email': email,
      'note': note,
      'apartment_id': apartmentId,
      'relation': relation,
      'move_in_date': moveInDate,
    });
    await _writeWait();
    final error = writeError;
    if (error != null) throw error;
    final mail = (email ?? '').trim().toLowerCase();
    for (final p in peopleJson.values) {
      if ((p['email']?.toString() ?? '').toLowerCase() == mail && mail.isNotEmpty && p['is_active'] == true) {
        throw _coded(
          'PERSON_EXISTS',
          409,
          payload: personExistsHasId ? <String, dynamic>{'person_id': p['id']} : null,
        );
      }
    }
    final id = (peopleJson.keys.isEmpty ? 0 : peopleJson.keys.reduce((a, b) => a > b ? a : b)) + 1;
    final apartment = apartmentId == null ? null : apartmentsJson[apartmentId];
    peopleJson[id] = pplPersonJson(
      id,
      fullName.trim(),
      phone: (phone ?? '').isEmpty ? null : phone,
      email: mail.isEmpty ? null : mail,
      note: (note ?? '').trim().isEmpty ? null : note!.trim(),
      apts: apartment == null
          ? const <PplApt>[]
          : <PplApt>[(apartmentId!, apartment['label'] as String, relation ?? ResidencyRelation.resident)],
    );
    final created = Map<String, dynamic>.of(peopleJson[id]!);
    if (nextCredentialsSent != null) created['credentials_sent'] = nextCredentialsSent;
    if (nextCredentialsEmail != null) created['credentials_email'] = nextCredentialsEmail;
    return PersonDetail.fromJson(created);
  }

  @override
  Future<PersonDetail> updatePerson(
    int siteCode,
    int personId,
    Map<String, Object?> fields,
  ) async {
    updatePersonCalls.add((id: personId, fields: Map<String, Object?>.of(fields)));
    await _writeWait();
    final error = writeError;
    if (error != null) throw error;
    final json = peopleJson[personId]!;
    // Sunucu kuralı: HESAPLI kişide ad / telefon anahtarı hiç bulunmamalı (null dahil); e-posta yalnız
    // dahili hesapta serbest.
    final internal = json['account_kind'] == 'internal';
    if (json['has_account'] == true &&
        (fields.containsKey('full_name') ||
            fields.containsKey('phone') ||
            (fields.containsKey('email') && !internal))) {
      throw _coded('PERSON_HAS_ACCOUNT', 409);
    }
    fields.forEach((key, value) => json[key] = value);
    return PersonDetail.fromJson(json);
  }

  Map<String, dynamic>? _currentHolder(int apartmentId, ResidencyRelation relation, {int? except}) {
    for (final json in peopleJson.values) {
      if (json['id'] == except) continue;
      for (final r in json['residencies'] as List) {
        final m = r as Map;
        if (m['apartment_id'] == apartmentId && m['is_current'] == true && m['relation'] == relation.apiValue) {
          return json;
        }
      }
    }
    return null;
  }

  @override
  Future<PersonDetail> addResidency(
    int siteCode,
    int personId, {
    required int apartmentId,
    required ResidencyRelation relation,
    DateTime? moveInDate,
  }) async {
    addResidencyCalls.add((person: personId, apartment: apartmentId, relation: relation, date: moveInDate));
    await _writeWait();
    final error = writeError;
    if (error != null) throw error;
    if (relation.isExclusive && _currentHolder(apartmentId, relation) != null) {
      throw _coded('RELATION_TAKEN', 409);
    }
    final json = peopleJson[personId]!;
    final label = apartmentsJson[apartmentId]?['label'] as String? ?? 'A Blok - 1';
    final residencies = json['residencies'] as List;
    residencies.add(<String, dynamic>{
      'id': 9000 + residencies.length,
      'apartment_id': apartmentId,
      'label': label,
      'block_name': label.split(' - ').first,
      'relation': relation.apiValue,
      'is_current': true,
      'move_in_date': moveInDate == null ? '2026-10-15' : crmDateParam(moveInDate),
      'move_out_date': null,
    });
    (json['relations'] as List).add(relation.apiValue);
    (json['apartments'] as List).add(<String, dynamic>{
      'apartment_id': apartmentId,
      'label': label,
      'block_name': label.split(' - ').first,
      'relation': relation.apiValue,
    });
    json['is_active'] = true;
    return PersonDetail.fromJson(json);
  }

  Map<String, dynamic>? _residencyOwner(int residencyId) {
    for (final json in peopleJson.values) {
      for (final r in json['residencies'] as List) {
        if ((r as Map)['id'] == residencyId) return json;
      }
    }
    return null;
  }

  @override
  Future<PersonDetail> updateResidency(
    int siteCode,
    int residencyId, {
    ResidencyRelation? relation,
    DateTime? moveInDate,
    bool clearMoveInDate = false,
  }) async {
    updateResidencyCalls.add((
      residency: residencyId,
      relation: relation,
      date: moveInDate,
      clear: clearMoveInDate,
    ));
    await _writeWait();
    final error = writeError;
    if (error != null) throw error;
    final json = _residencyOwner(residencyId)!;
    final row = (json['residencies'] as List).cast<Map>().firstWhere((r) => r['id'] == residencyId);
    if (relation != null) {
      if (relation.isExclusive &&
          _currentHolder(row['apartment_id'] as int, relation, except: json['id'] as int) != null) {
        throw _coded('RELATION_TAKEN', 409);
      }
      row['relation'] = relation.apiValue;
    }
    if (moveInDate != null) {
      row['move_in_date'] = crmDateParam(moveInDate);
    } else if (clearMoveInDate) {
      row['move_in_date'] = null;
    }
    _refreshDerived(json);
    return PersonDetail.fromJson(json);
  }

  @override
  Future<PersonDetail> endResidency(
    int siteCode,
    int residencyId, {
    DateTime? moveOutDate,
  }) async {
    endResidencyCalls.add((residency: residencyId, date: moveOutDate));
    await _writeWait();
    final error = writeError;
    if (error != null) throw error;
    final json = _residencyOwner(residencyId)!;
    final row = (json['residencies'] as List).cast<Map>().firstWhere((r) => r['id'] == residencyId);
    row['is_current'] = false;
    row['move_out_date'] = moveOutDate == null ? '2026-10-15' : crmDateParam(moveOutDate);
    _refreshDerived(json);
    // Son ilişki bitince kişi otomatik pasif olur.
    if ((json['residencies'] as List).cast<Map>().every((r) => r['is_current'] != true)) {
      json['is_active'] = false;
    }
    return PersonDetail.fromJson(json);
  }

  /// `relations` / `apartments` özetlerini güncel ilişkilerden yeniden üretir.
  void _refreshDerived(Map<String, dynamic> json) {
    final current = (json['residencies'] as List).cast<Map>().where((r) => r['is_current'] == true).toList();
    json['relations'] = <String>[for (final r in current) r['relation'] as String];
    json['apartments'] = <Map<String, dynamic>>[
      for (final r in current)
        <String, dynamic>{
          'apartment_id': r['apartment_id'],
          'label': r['label'],
          'block_name': r['block_name'],
          'relation': r['relation'],
        },
    ];
  }

  // --- Daireler --------------------------------------------------------------------------------

  @override
  Future<ApartmentPage> listApartments(
    int siteCode, {
    int? blockId,
    String? query,
    int limit = 50,
    int offset = 0,
  }) async {
    apartmentCalls.add((site: siteCode, query: query, block: blockId, limit: limit, offset: offset));
    final q = (query ?? '').trim().toLowerCase();
    final rows = apartmentsJson.values.where((json) {
      if (blockId != null && json['block_id'] != blockId) return false;
      if (q.isEmpty) return true;
      // Sunucu: q = blok-daire etiketi VE güncel sakin adları.
      return _has(json['label'], q) ||
          (json['current_residents'] as List).any((r) => _has((r as Map)['full_name'], q));
    }).toList();
    final page = rows.skip(offset).take(_limit(limit)).toList();
    final result = ApartmentPage(
      items: [for (final json in page) ApartmentSummary.fromJson(json)],
      total: rows.length,
    );
    await _gate(apartmentGates);
    final error = apartmentsError;
    if (error != null) throw error;
    return result;
  }

  @override
  Future<ApartmentDetail> getApartment(int siteCode, int apartmentId) async {
    getApartmentCalls.add(apartmentId);
    final gate = apartmentGate;
    if (gate != null) await gate.future;
    final error = apartmentError;
    if (error != null) throw error;
    final json = apartmentsJson[apartmentId];
    if (json == null) throw _coded('APARTMENT_NOT_FOUND', 404);
    return ApartmentDetail.fromJson(json);
  }

  @override
  Future<ApartmentDetail> updateApartment(
    int siteCode,
    int apartmentId,
    Map<String, Object?> fields,
  ) async {
    updateApartmentCalls.add((id: apartmentId, fields: Map<String, Object?>.of(fields)));
    await _writeWait();
    final error = writeError;
    if (error != null) throw error;
    final json = apartmentsJson[apartmentId]!;
    fields.forEach((key, value) {
      if (key == 'land_share_numerator' || key == 'land_share_denominator') return;
      json[key] = value;
    });
    if (fields.containsKey('land_share_numerator')) {
      final n = fields['land_share_numerator'];
      json['land_share'] = n == null
          ? null
          : <String, dynamic>{'numerator': n, 'denominator': fields['land_share_denominator']};
    }
    return ApartmentDetail.fromJson(json);
  }

  // --- Araçlar ---------------------------------------------------------------------------------

  @override
  Future<VehiclePage> listVehicles(
    int siteCode, {
    String? query,
    int? personId,
    int limit = 50,
    int offset = 0,
  }) async {
    vehicleCalls.add((site: siteCode, query: query, limit: limit, offset: offset));
    final q = (query ?? '').trim().toLowerCase().replaceAll(' ', '');
    final rows = vehiclesJson.where((json) {
      if (personId != null && json['person_id'] != personId) return false;
      if (q.isEmpty) return true;
      return _has(json['plate'], q) || _has(json['person_name'], q);
    }).toList();
    final page = rows.skip(offset).take(_limit(limit)).toList();
    final result = VehiclePage(
      items: VehicleRecord.listFrom(page),
      total: rows.length,
    );
    await _gate(vehicleGates);
    final error = vehiclesError;
    if (error != null) throw error;
    return result;
  }

  @override
  Future<VehicleRecord> createVehicle(
    int siteCode,
    int personId,
    String plate, {
    String? note,
  }) async {
    createVehicleCalls.add((person: personId, plate: plate, note: note));
    await _writeWait();
    final error = writeError;
    if (error != null) throw error;
    final normalized = plate.replaceAll(RegExp(r'[\s\-.]'), '').toUpperCase();
    if (!RegExp(r'^[A-Z0-9]{5,10}$').hasMatch(normalized)) throw _coded('PLATE_INVALID', 400);
    if (vehiclesJson.any((v) => v['plate'] == normalized)) throw _coded('PLATE_EXISTS', 409);
    final person = peopleJson[personId]!;
    final id = 100 + vehiclesJson.length;
    final json = pplVehicleJson(
      id,
      plate,
      person: person['full_name'] as String,
      personId: personId,
      note: (note ?? '').trim().isEmpty ? null : note!.trim(),
    );
    vehiclesJson.add(json);
    (person['vehicles'] as List).add(json);
    person['vehicle_count'] = (person['vehicles'] as List).length;
    return VehicleRecord.fromJson(json);
  }

  @override
  Future<void> removeVehicle(int siteCode, int vehicleId) async {
    removeVehicleCalls.add(vehicleId);
    await _writeWait();
    final error = writeError;
    if (error != null) throw error;
    vehiclesJson.removeWhere((v) => v['id'] == vehicleId);
    for (final person in peopleJson.values) {
      (person['vehicles'] as List).removeWhere((v) => (v as Map)['id'] == vehicleId);
      person['vehicle_count'] = (person['vehicles'] as List).length;
    }
  }

  // --- Geçmiş ve sakin kayıtları ---------------------------------------------------------------

  @override
  Future<HistoryPage> listHistory(
    int siteCode, {
    String? targetType,
    int? targetId,
    int limit = 50,
    int? beforeId,
  }) async {
    historyCalls.add((site: siteCode, type: targetType, id: targetId, before: beforeId));
    HistoryPage page = const HistoryPage();
    if (historyPages.isNotEmpty) {
      // N. çağrı N. sayfayı döner (son sayfadan sonrası son sayfayı tekrarlar).
      final index = historyCalls.length - 1;
      page = historyPages[index < historyPages.length ? index : historyPages.length - 1];
    }
    await _gate(historyGates);
    final error = historyError;
    if (error != null) throw error;
    return page;
  }

  @override
  Future<List<MyRecord>> getMyRecords() async {
    myRecordsCalls++;
    final gate = myRecordsGate;
    if (gate != null) await gate.future;
    final error = myRecordsError;
    if (error != null) throw error;
    return myRecords;
  }
}
