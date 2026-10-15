// Platform modül sistemi Faz 1: Modüller / Denetim Kaydı / Ek roller ekranlarının ortak örnek verisi
// ve sahte servisi. `_test.dart` ile bitmediği için kendi başına test olarak çalışmaz.
import 'dart:async';

import 'package:site_kapi_kontrol/models/audit_log.dart';
import 'package:site_kapi_kontrol/models/platform_module.dart';
import 'package:site_kapi_kontrol/models/site_page.dart';
import 'package:site_kapi_kontrol/models/site_record.dart';
import 'package:site_kapi_kontrol/models/staff_role_record.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';

SiteRecord mdSite(int id, String name, {String approval = 'approved'}) =>
    SiteRecord.fromJson(<String, dynamic>{
      'id': id,
      'name': name,
      'approval_status': approval,
      'created_at': '2026-10-01T12:30:00Z',
    });

/// Sunucu kataloğundaki 8 modül (açıklamalar katalogdakiyle aynı).
SiteModulesState mdState(
  int siteCode,
  String siteName, {
  bool door = true,
  String typeLabel = 'Apartman ve Site',
}) {
  Map<String, dynamic> m(
    String code,
    String name,
    String description, {
    bool core = false,
    String status = 'coming_soon',
    bool enabled = false,
    bool toggleable = false,
  }) => <String, dynamic>{
    'code': code,
    'name': name,
    'description': description,
    'core': core,
    'status': status,
    'enabled': enabled,
    'toggleable': toggleable,
    'updated_at': null,
    'updated_by': null,
  };
  return SiteModulesState.fromJson(<String, dynamic>{
    'site_code': siteCode,
    'site_name': siteName,
    'management_type': 'apartment_site',
    'management_type_label': typeLabel,
    'modules': <Map<String, dynamic>>[
      m(
        'door_control',
        'Geçiş Kontrol (AHBU)',
        'Telefondan kapı açma, karekod ve misafir geçişi; kapı ve cihaz yönetimi.',
        status: 'available',
        enabled: door,
        toggleable: true,
      ),
      m(
        'people',
        'Kişi ve Daire Kayıtları',
        'Blok, daire, sakin ve görevli kayıtlarının tutulması.',
        core: true,
      ),
      m(
        'announcements',
        'Duyuru ve Bildirim',
        'Sakinlere duyuru ve bildirim gönderme.',
        core: true,
      ),
      m(
        'finance',
        'Aidat ve Finans',
        'Aidat, borç ve alacak takibi; gelir ve gider kayıtları.',
      ),
      m(
        'reservation',
        'Rezervasyon ve Konsiyerj',
        'Ortak alan rezervasyonu ve konsiyerj talepleri.',
      ),
      m(
        'work_tracking',
        'İş Takibi',
        'Arıza, bakım ve görev kayıtlarının takibi.',
      ),
      m(
        'metering',
        'Sayaç Okuma ve Faturalandırma',
        'Su, elektrik ve doğalgaz sayaç okuma ile faturalandırma.',
      ),
      m(
        'online_payment',
        'Online Tahsilat ve Banka Bağlantısı',
        'Sakinlerden online tahsilat ve banka hesabı bağlantısı.',
      ),
    ],
  });
}

StaffRoleRecord mdRole(
  int userCode,
  String name,
  String email, {
  String role = 'BOARD_MEMBER',
}) => StaffRoleRecord(
  userCode: userCode,
  fullName: name,
  email: email,
  role: role,
  createdAt: DateTime(2026, 10, 1),
);

AuditLogEntry mdAudit(
  int id, {
  String action = 'module.disabled',
  String actor = 'Süper Yönetici',
  String site = 'Gül Sitesi',
  int siteCode = 11,
  String targetType = 'module',
  String targetId = 'door_control',
  Map<String, dynamic> details = const <String, dynamic>{'enabled': false},
}) => AuditLogEntry(
  id: id,
  createdAt: DateTime(2026, 10, 15, 9, 30),
  actorUserCode: 1,
  actorName: actor,
  actorRole: 'super_user',
  action: action,
  siteCode: siteCode,
  siteName: site,
  targetType: targetType,
  targetId: targetId,
  details: details,
);

const UserSession mdSuperSession = UserSession(
  id: 1,
  fullName: 'Süper Yönetici',
  email: 'super@e2e.local',
  loginName: null,
  role: UserRole.superUser,
  isActive: true,
  token: 'tok',
);

/// Modül sistemi uçları için sahte servis: her çağrı kaydedilir; yanıtlar testten sürülür.
class ModulesFakeAuth extends AuthService {
  ModulesFakeAuth({
    List<SiteRecord>? sites,
    Map<int, SiteModulesState>? states,
    Map<int, List<StaffRoleRecord>>? roles,
  }) : sites = sites ?? <SiteRecord>[mdSite(11, 'Gül Sitesi'), mdSite(12, 'Mavi Park')],
       states = states ??
           <int, SiteModulesState>{
             11: mdState(11, 'Gül Sitesi'),
             12: mdState(12, 'Mavi Park'),
           },
       roles = roles ?? <int, List<StaffRoleRecord>>{},
       super(api: AuthApi(baseUrl: 'http://localhost'));

  List<SiteRecord> sites;
  final Map<int, SiteModulesState> states;
  final Map<int, List<StaffRoleRecord>> roles;

  // Çağrı kayıtları.
  int listSitesCalls = 0;
  final List<int> getModulesCalls = <int>[];
  final List<int> listRolesCalls = <int>[];
  final List<({int site, String code, bool enabled, bool confirm})> setCalls =
      <({int site, String code, bool enabled, bool confirm})>[];
  final List<({int site, String email, String role})> assignCalls =
      <({int site, String email, String role})>[];
  final List<({int site, int user})> removeCalls = <({int site, int user})>[];

  // Davranış kancaları.
  Object? listSitesError;
  Object? modulesError;
  Object? rolesError;
  Object? setError;
  Object? assignError;
  Object? removeError;

  /// null değilse listSites bu kapıyı bekler (yükleniyor durumu).
  Completer<void>? sitesGate;
  Completer<void>? modulesGate;
  Completer<void>? rolesGate;

  /// null değilse setSiteModule bu kapıyı bekler (işlem sürerken başka eylemler için).
  Completer<void>? setGate;

  /// true ise `confirm: false` ile gelen her setSiteModule çağrısı MODULE_CONFIRM_REQUIRED fırlatır.
  bool demandConfirm = false;

  @override
  UserSession? get session => mdSuperSession;

  @override
  bool get isLoggedIn => true;

  @override
  Future<SitePage> listSites({
    required int page,
    int pageSize = 10,
    String? approvalStatus,
  }) async {
    listSitesCalls++;
    final gate = sitesGate;
    if (gate != null) await gate.future;
    final error = listSitesError;
    if (error != null) throw error;
    return SitePage(sites: sites, total: sites.length, page: 1, pageSize: pageSize);
  }

  @override
  Future<SiteModulesState> getSiteModules(int siteCode) async {
    getModulesCalls.add(siteCode);
    final gate = modulesGate;
    if (gate != null) await gate.future;
    final error = modulesError;
    if (error != null) throw error;
    return states[siteCode] ?? mdState(siteCode, 'Site $siteCode');
  }

  @override
  Future<SiteModulesState> setSiteModule(
    int siteCode,
    String moduleCode,
    bool enabled, {
    bool confirm = false,
  }) async {
    setCalls.add((site: siteCode, code: moduleCode, enabled: enabled, confirm: confirm));
    final setWait = setGate;
    if (setWait != null) await setWait.future;
    final error = setError;
    if (error != null) throw error;
    if (demandConfirm && !confirm) {
      throw ApiException(
        'Geçiş Kontrol kapatılırsa telefondan kapı açma, QR ve misafir geçişi durur. Onaylıyor musunuz?',
        statusCode: 409,
        code: 'MODULE_CONFIRM_REQUIRED',
      );
    }
    final current = states[siteCode] ?? mdState(siteCode, 'Site $siteCode');
    final next = SiteModulesState(
      siteCode: current.siteCode,
      siteName: current.siteName,
      managementType: current.managementType,
      managementTypeLabel: current.managementTypeLabel,
      modules: <PlatformModule>[
        for (final m in current.modules)
          m.code == moduleCode ? m.copyWith(enabled: enabled) : m,
      ],
    );
    states[siteCode] = next;
    return next;
  }

  @override
  Future<List<StaffRoleRecord>> listStaffRoles(int siteCode) async {
    listRolesCalls.add(siteCode);
    final gate = rolesGate;
    if (gate != null) await gate.future;
    final error = rolesError;
    if (error != null) throw error;
    return List<StaffRoleRecord>.of(roles[siteCode] ?? const <StaffRoleRecord>[]);
  }

  @override
  Future<StaffRoleRecord> assignStaffRole(
    int siteCode,
    String email,
    String role,
  ) async {
    assignCalls.add((site: siteCode, email: email, role: role));
    final error = assignError;
    if (error != null) throw error;
    final record = mdRole(900 + assignCalls.length, 'Yeni Kişi', email, role: role);
    roles.putIfAbsent(siteCode, () => <StaffRoleRecord>[]).add(record);
    return record;
  }

  @override
  Future<void> removeStaffRole(int siteCode, int userCode) async {
    removeCalls.add((site: siteCode, user: userCode));
    final error = removeError;
    if (error != null) throw error;
    roles[siteCode]?.removeWhere((r) => r.userCode == userCode);
  }

  // Denetim kaydı.
  final List<({int? site, int limit, int? before, String? action})> auditCalls =
      <({int? site, int limit, int? before, String? action})>[];
  List<AuditLogPage> auditPages = <AuditLogPage>[const AuditLogPage()];
  Object? auditError;
  Completer<void>? auditGate;

  /// Her `listAuditLog` çağrısı sırayla bir kapı tüketir (varsa): eşzamanlı çağrıların tamamlanma
  /// sırası testten sürülür (eski imleç / bayat yanıt senaryoları).
  final List<Completer<void>> auditGateQueue = <Completer<void>>[];

  @override
  Future<AuditLogPage> listAuditLog({
    int? siteCode,
    int limit = 50,
    int? beforeId,
    String? action,
  }) async {
    auditCalls.add((site: siteCode, limit: limit, before: beforeId, action: action));
    // before_id verilmişse bir sonraki hazır sayfa, verilmemişse ilk sayfa (çağrı anında belirlenir).
    final index = beforeId == null ? 0 : auditCalls.where((c) => c.before != null).length;
    final queued = auditGateQueue.isEmpty ? null : auditGateQueue.removeAt(0);
    if (queued != null) await queued.future;
    final gate = auditGate;
    if (gate != null) await gate.future;
    final error = auditError;
    if (error != null) throw error;
    return auditPages[index.clamp(0, auditPages.length - 1)];
  }
}
