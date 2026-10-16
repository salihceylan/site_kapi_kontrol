// Platform: site başvurusu (site yöneticisi olma) ekran / pencere testlerinin ortak örnek verisi ve sahte
// servisi. `_test.dart` ile bitmediği için kendi başına test olarak çalışmaz.
//
// Sahte servis SUNUCUYU taklit eder (docs/PLATFORM_SITE_BASVURUSU.md): başvurular bellekte tutulur,
// yanıtlar sunucunun gerçek JSON biçiminde üretilip modellerle ayrıştırılır; liste süzgeç / arama /
// sayfalama (limit-offset) uygular; yazmalar kaydı değiştirir ve sunucu kurallarını (yalnız bireysel /
// daire kullanıcısı başvurur, kişi başına tek bekleyen, yalnız bekleyen onaylanır / reddedilir / iptal
// edilir, IDOR 404) aynı Türkçe mesajlarla uygular. Yarış testleri için çağrılar kapılarla bekletilebilir.
// Rol, sunucudaki rolden ayrıdır: yerel rol yalnız [refreshSession] ile eşitlenir (gerçek davranış).
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/site_application.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';

/// Sunucudaki bir başvuru satırı (süper kullanıcı alanlarıyla; başvurana verilirken ayıklanır).
Map<String, dynamic> saRow(
  int id, {
  String status = 'pending',
  String siteName = 'Gül Sitesi',
  String? city = 'İstanbul',
  String? district = 'Kadıköy',
  String? address,
  List<Map<String, dynamic>>? blocks,
  List<String>? doors,
  String? deviceUid,

  /// null: sunucu gibi -> yalnız BEKLEYEN başvuruda `true` (karar sonrası cihaz tüketilmiş / bağlanmış olabilir).
  bool? deviceAvailable,
  String? note,
  int applicantCode = 5,
  String applicantName = 'Ayşe Yılmaz',
  String applicantEmail = 'ayse@example.com',
  String? applicantPhone = '+905551112233',
  String applicantRole = 'individual',
  bool deletedApplicant = false,
  DateTime? createdAt,
  DateTime? decidedAt,
  String? decisionNote,
  String? decidedByName,
  int? siteCode,
}) {
  final blockList = blocks ??
      <Map<String, dynamic>>[
        <String, dynamic>{'name': 'A Blok', 'apartment_count': 10},
        <String, dynamic>{'name': 'B Blok', 'apartment_count': 20},
      ];
  final doorList = doors ?? <String>['Ana Giriş'];
  return <String, dynamic>{
    'id': id,
    'status': status,
    'site_name': siteName,
    'city': city,
    'district': district,
    'address': address,
    'management_type': 'apartment_site',
    'management_type_label': 'Apartman ve Site',
    'block_count': blockList.length,
    'apartment_count': blockList.fold<int>(0, (s, b) => s + (b['apartment_count'] as int)),
    'door_count': doorList.length,
    'blocks': blockList,
    'doors': <Map<String, dynamic>>[
      for (final d in doorList) <String, dynamic>{'name': d},
    ],
    'device_uid': deviceUid,
    'note': note,
    // Sunucu `plan_code`u başvuruda boş (null) bırakır; `payment_reference` hiçbir yanıtta yoktur.
    'plan_code': null,
    'payment_status': 'not_required',
    'decision_note': decisionNote,
    'decided_at': decidedAt?.toUtc().toIso8601String(),
    'site_code': siteCode,
    'created_at': (createdAt ?? DateTime.utc(2026, 10, 16, 11, 30)).toUtc().toIso8601String(),
    // Yalnız süper kullanıcı yanıtında:
    // Başvuran hesabı silinmişse sunucu `applicant: null` verir (başvuran_user_code ON DELETE SET NULL).
    'applicant': deletedApplicant
        ? null
        : <String, dynamic>{
            'user_code': applicantCode,
            'full_name': applicantName,
            'email': applicantEmail,
            'phone': applicantPhone,
            'role': applicantRole,
          },
    'decision_source': status == 'pending' || status == 'cancelled' ? null : 'super_user',
    'decided_by_name': decidedByName,
    'device_available': deviceAvailable ?? status == 'pending',
  };
}

/// Kendi oturumunun kullanıcısı için sahte oturum (süper kullanıcıda 1, diğerlerinde 5).
UserSession saSession(UserRole role) => UserSession(
  id: role == UserRole.superUser ? 1 : 5,
  fullName: role == UserRole.superUser ? 'Süper Yönetici' : 'Ayşe Yılmaz',
  email: 'kullanici@example.com',
  loginName: null,
  role: role,
  isActive: true,
  token: 'tok',
);

/// Site başvurusu uçları için sahte servis (başvuran + süper kullanıcı tarafı).
class SiteApplicationFakeAuth extends AuthService {
  SiteApplicationFakeAuth({UserRole role = UserRole.individual, this.myUserCode = 5})
    : role = role,
      serverRole = role,
      super(api: AuthApi(baseUrl: 'http://localhost'));

  /// Yerel oturumun rolü ([refreshSession] ile sunucudakine eşitlenir).
  UserRole role;

  /// Sunucudaki gerçek rol (onaylanınca değişir).
  UserRole serverRole;
  final int myUserCode;
  bool loggedIn = true;

  /// Sunucudaki başvurular (kimlik -> satır).
  final Map<int, Map<String, dynamic>> rows = <int, Map<String, dynamic>>{};
  int _nextId = 100;

  /// Hesaba bağlı cihazlar (`GET /membership/my-devices`).
  List<Map<String, dynamic>> devices = <Map<String, dynamic>>[];

  /// Sunucunun `requires_application` bildirimi (yalnız site yöneticisi için anlamlı): true = sahip bağı
  /// olmayan yönetici başvurur, false = anlık "Site Ekle" açık, null = alan HİÇ gönderilmez (eski sunucu).
  bool? serverRequiresApplication;

  /// Sayfa boyutu üst sınırı (sayfalama testleri için küçük verilir).
  int? maxPage;

  /// Doluysa liste yanıtlarında `total` yerine bu değer döner (tutarsız sunucu simülasyonu).
  int? totalOverride;

  /// Bugün yapılan başvuru sayısı için sunucu sınırı (günde 5).
  int dailyLimit = 5;

  // --- Davranış kancaları ----------------------------------------------------------------------
  Object? createError;
  Object? mineError;
  Object? cancelError;
  Object? adminListError;
  Object? summaryError;
  Object? detailError;
  Object? decideError;
  Object? devicesError;
  Object? refreshSessionError;
  Completer<void>? createGate;
  Completer<void>? cancelGate;
  Completer<void>? decideGate;
  final List<Completer<void>> mineGates = <Completer<void>>[];
  final List<Completer<void>> adminListGates = <Completer<void>>[];
  final List<Completer<void>> detailGates = <Completer<void>>[];

  /// true: onayda başvuran silinmiş / pasif (409 APPLICANT_UNAVAILABLE).
  bool applicantUnavailable = false;

  /// Onayda cihaz bağlandı mı (`device_attached`)? null: alan yok.
  bool? deviceAttached = true;

  // --- Çağrı kayıtları -------------------------------------------------------------------------
  final List<Map<String, Object?>> createCalls = <Map<String, Object?>>[];
  int mineCalls = 0;
  final List<int> cancelCalls = <int>[];
  final List<({String? status, String? query, int limit, int offset})> adminListCalls =
      <({String? status, String? query, int limit, int offset})>[];
  int summaryCalls = 0;
  final List<int> detailCalls = <int>[];
  final List<int> approveCalls = <int>[];
  final List<({int id, String? reason})> rejectCalls = <({int id, String? reason})>[];
  int deviceCalls = 0;
  int refreshSessionCalls = 0;
  int refreshSessionForcedCalls = 0;

  @override
  UserSession? get session => loggedIn ? saSession(role) : null;

  @override
  bool get isLoggedIn => loggedIn;

  /// Oturum değişimi (çıkış / yeni giriş / rol değişimi) ve dinleyicilere bildirim.
  void changeSession({UserRole? role, bool? loggedIn}) {
    if (role != null) {
      this.role = role;
      serverRole = role;
    }
    if (loggedIn != null) this.loggedIn = loggedIn;
    notifyListeners();
  }

  DateTime? _verifiedAt;

  /// Oturumun SON BAŞARILI doğrulanma anı (gerçek [AuthService] gibi: hata yutulur, değer ilerlemez).
  @override
  DateTime? get sessionVerifiedAt => _verifiedAt;

  @override
  Future<void> refreshSession({bool force = false}) async {
    refreshSessionCalls++;
    if (force) refreshSessionForcedCalls++;
    final error = refreshSessionError;
    if (error != null) return;
    _verifiedAt = DateTime.now();
    if (role != serverRole) {
      role = serverRole;
      notifyListeners();
    }
  }

  Future<void> _gate(List<Completer<void>> queue) async {
    if (queue.isEmpty) return;
    await queue.removeAt(0).future;
  }

  ApiException _coded(String code, int status, [String? serverText]) => ApiException(
    AuthApi.messageForErrorCode(code) ?? serverText ?? code,
    statusCode: status,
    code: code,
  );

  // --- Sunucu biçimli JSON ---------------------------------------------------------------------

  /// Başvurana verilen biçim: süper kullanıcı alanları (`applicant`, `decision_source`, `decided_by_name`,
  /// `device_available`) YOKTUR.
  Map<String, dynamic> userJson(Map<String, dynamic> row) {
    final copy = Map<String, dynamic>.of(row)
      ..remove('applicant')
      ..remove('decision_source')
      ..remove('decided_by_name')
      ..remove('device_available');
    return copy;
  }

  bool _mine(Map<String, dynamic> row) =>
      (row['applicant'] as Map<String, dynamic>?)?['user_code'] == myUserCode;

  // --- Başvuran uçları -------------------------------------------------------------------------

  @override
  Future<SiteApplication> createSiteApplication({
    required String name,
    String? city,
    String? district,
    String? address,
    required List<Map<String, dynamic>> blocks,
    List<Map<String, dynamic>>? doors,
    int doorCount = 1,
    String? deviceUid,
    String? managementType,
    String? note,
  }) async {
    createCalls.add(<String, Object?>{
      'name': name,
      'city': city,
      'district': district,
      'address': address,
      'blocks': blocks,
      'doors': doors,
      'doorCount': doorCount,
      'deviceUid': deviceUid,
      'managementType': managementType,
      'note': note,
    });
    await createGate?.future;
    final error = createError;
    if (error != null) throw error;
    // Sahip bağı olan site yöneticisi başvuramaz (anlık "Site Ekle"yi kullanır); sahip bağı olmayan yönetici
    // (`requires_application: true`) başvurur.
    if (serverRole == UserRole.siteManager && serverRequiresApplication != true) {
      throw ApiException(
        AuthApi.siteApplicationAlreadyManagerMessage,
        statusCode: 409,
        code: 'ALREADY_SITE_MANAGER',
      );
    }
    if (serverRole != UserRole.individual &&
        serverRole != UserRole.apartmentOwner &&
        serverRole != UserRole.siteManager) {
      throw _coded('FORBIDDEN_ROLE', 403);
    }
    if (rows.values.any((r) => _mine(r) && r['status'] == 'pending')) {
      throw _coded('APPLICATION_PENDING', 409);
    }
    final today = rows.values.where((r) => _mine(r)).length;
    if (today >= dailyLimit) throw _coded('APPLICATION_DAILY_LIMIT', 409);
    final id = _nextId++;
    final row = saRow(
      id,
      siteName: name.trim(),
      city: city,
      district: district,
      address: (address ?? '').isEmpty ? null : address,
      blocks: <Map<String, dynamic>>[
        for (final b in blocks)
          <String, dynamic>{'name': b['name'], 'apartment_count': b['apartmentCount']},
      ],
      doors: <String>[for (final d in doors ?? <Map<String, dynamic>>[]) d['name'] as String],
      deviceUid: deviceUid,
      note: (note ?? '').trim().isEmpty ? null : note!.trim(),
      applicantCode: myUserCode,
      createdAt: DateTime.utc(2026, 10, 16, 12),
    );
    rows[id] = row;
    return SiteApplication.fromJson(userJson(row));
  }

  @override
  Future<MySiteApplications> getMySiteApplications() async {
    mineCalls++;
    await _gate(mineGates);
    final error = mineError;
    if (error != null) throw error;
    final mine = rows.values.where(_mine).toList()
      ..sort((a, b) => (b['id'] as int).compareTo(a['id'] as int));
    final pending = mine.where((r) => r['status'] == 'pending').firstOrNull;
    return MySiteApplications.fromJson(<String, dynamic>{
      'pending': pending == null ? null : userJson(pending),
      'items': <Map<String, dynamic>>[for (final r in mine.take(10)) userJson(r)],
      if (serverRequiresApplication != null) 'requires_application': serverRequiresApplication,
    });
  }

  @override
  Future<SiteApplication> cancelSiteApplication(int applicationId) async {
    cancelCalls.add(applicationId);
    await cancelGate?.future;
    final error = cancelError;
    if (error != null) throw error;
    final row = rows[applicationId];
    if (row == null || !_mine(row)) throw _coded('APPLICATION_NOT_FOUND', 404);
    if (row['status'] != 'pending') throw _coded('APPLICATION_NOT_PENDING', 409);
    row
      ..['status'] = 'cancelled'
      ..['decided_at'] = DateTime.now().toUtc().toIso8601String()
      ..['device_available'] = false;
    return SiteApplication.fromJson(userJson(row));
  }

  /// Anlık kurulum (site yöneticisi / süper kullanıcı): çağrılar kaydedilir.
  final List<Map<String, Object?>> setupCalls = <Map<String, Object?>>[];
  Object? setupError;

  @override
  Future<Map<String, dynamic>> setupSite({
    required String name,
    String? city,
    String? district,
    String? address,
    required List<Map<String, dynamic>> blocks,
    List<Map<String, dynamic>>? doors,
    int doorCount = 1,
    String? deviceUid,
    String? managementType,
  }) async {
    setupCalls.add(<String, Object?>{
      'name': name,
      'blocks': blocks,
      'doors': doors,
      'deviceUid': deviceUid,
      'managementType': managementType,
    });
    final error = setupError;
    if (error != null) throw error;
    // Bireysel / daire kullanıcısı ve sahip bağı olmayan yönetici için anlık kurulum kapalıdır (sunucu kuralı).
    if (serverRole == UserRole.individual ||
        serverRole == UserRole.apartmentOwner ||
        (serverRole == UserRole.siteManager && serverRequiresApplication == true)) {
      throw _coded('APPLICATION_REQUIRED', 409);
    }
    return <String, dynamic>{'ok': true};
  }

  /// Cihaz sahiplenme: cihaz hesaba eklenir; rol DEĞİŞMEZ (ürün kararı: yönetici olmak için başvuru gerekir).
  final List<String> claimCalls = <String>[];
  Object? claimError;

  @override
  Future<Map<String, dynamic>> claimDevice({required String deviceInput}) async {
    claimCalls.add(deviceInput);
    final error = claimError;
    if (error != null) throw error;
    devices = <Map<String, dynamic>>[...devices, saDevice(deviceInput)];
    return <String, dynamic>{
      'ok': true,
      'role': serverRole.apiValue,
      'message': 'Cihaz ($deviceInput) başarıyla hesabınıza bağlandı!',
      'device': <String, dynamic>{'device_uid': deviceInput},
    };
  }

  @override
  Future<List<Map<String, dynamic>>> getMyClaimedDevices() async {
    deviceCalls++;
    final error = devicesError;
    if (error != null) throw error;
    return List<Map<String, dynamic>>.of(devices);
  }

  // --- Süper kullanıcı uçları ------------------------------------------------------------------

  @override
  Future<SiteApplicationPage> listAdminSiteApplications({
    String? status,
    String? query,
    int limit = 30,
    int offset = 0,
  }) async {
    adminListCalls.add((status: status, query: query, limit: limit, offset: offset));
    await _gate(adminListGates);
    final error = adminListError;
    if (error != null) throw error;
    final q = (query ?? '').trim().toLowerCase();
    final effective = status ?? 'pending';
    final filtered = rows.values.where((row) {
      if (effective != 'all' && row['status'] != effective) return false;
      if (q.isEmpty) return true;
      final applicant = row['applicant'] as Map<String, dynamic>?;
      return (row['site_name'] as String).toLowerCase().contains(q) ||
          ((row['city'] as String?) ?? '').toLowerCase().contains(q) ||
          ((applicant?['full_name'] as String?) ?? '').toLowerCase().contains(q) ||
          ((applicant?['email'] as String?) ?? '').toLowerCase().contains(q);
    }).toList()
      ..sort((a, b) => (b['id'] as int).compareTo(a['id'] as int));
    final size = maxPage == null ? limit : (limit < maxPage! ? limit : maxPage!);
    final page = filtered.skip(offset).take(size);
    return SiteApplicationPage.fromJson(<String, dynamic>{
      'items': page.toList(),
      'total': totalOverride ?? filtered.length,
    });
  }

  @override
  Future<int> getAdminSiteApplicationsPendingCount() async {
    summaryCalls++;
    final error = summaryError;
    if (error != null) throw error;
    return rows.values.where((r) => r['status'] == 'pending').length;
  }

  @override
  Future<SiteApplication> getAdminSiteApplication(int applicationId) async {
    detailCalls.add(applicationId);
    await _gate(detailGates);
    final error = detailError;
    if (error != null) throw error;
    final row = rows[applicationId];
    if (row == null) throw _coded('APPLICATION_NOT_FOUND', 404);
    return SiteApplication.fromJson(row);
  }

  @override
  Future<SiteApplicationDecision> approveSiteApplication(int applicationId, {String? note}) async {
    approveCalls.add(applicationId);
    await decideGate?.future;
    final error = decideError;
    if (error != null) throw error;
    final row = rows[applicationId];
    if (row == null) throw _coded('APPLICATION_NOT_FOUND', 404);
    if (row['status'] != 'pending') throw _coded('APPLICATION_NOT_PENDING', 409);
    if (applicantUnavailable) throw _coded('APPLICANT_UNAVAILABLE', 409);
    row
      ..['status'] = 'approved'
      ..['decided_at'] = DateTime.now().toUtc().toIso8601String()
      ..['decided_by_name'] = 'Süper Yönetici'
      ..['decision_source'] = 'super_user'
      ..['device_available'] = false
      ..['site_code'] = 900 + applicantCodeOf(row);
    // Başvuranın sunucudaki rolü site yöneticisi olur (yerel oturum yalnız refreshSession ile eşitlenir) ve
    // artık sahip bağı vardır (`requires_application` düşer).
    if (_mine(row)) {
      serverRole = UserRole.siteManager;
      if (serverRequiresApplication != null) serverRequiresApplication = false;
    }
    return SiteApplicationDecision.fromJson(<String, dynamic>{
      'application': row,
      'site': <String, dynamic>{'site_code': row['site_code'], 'name': row['site_name']},
      'device_attached': ?deviceAttached,
    });
  }

  int applicantCodeOf(Map<String, dynamic> row) =>
      ((row['applicant'] as Map<String, dynamic>?)?['user_code'] as int?) ?? 0;

  @override
  Future<SiteApplication> rejectSiteApplication(int applicationId, {String? reason}) async {
    rejectCalls.add((id: applicationId, reason: reason));
    await decideGate?.future;
    final error = decideError;
    if (error != null) throw error;
    final row = rows[applicationId];
    if (row == null) throw _coded('APPLICATION_NOT_FOUND', 404);
    if (row['status'] != 'pending') throw _coded('APPLICATION_NOT_PENDING', 409);
    row
      ..['status'] = 'rejected'
      ..['decided_at'] = DateTime.now().toUtc().toIso8601String()
      ..['decided_by_name'] = 'Süper Yönetici'
      ..['decision_source'] = 'super_user'
      ..['device_available'] = false
      ..['decision_note'] = (reason ?? '').trim().isEmpty ? null : reason!.trim();
    return SiteApplication.fromJson(row);
  }

  /// Sunucuda başka bir süper kullanıcının verdiği karar (kullanıcı arayüzü bunu henüz bilmez).
  void serverDecide(int id, String status, {String? note}) {
    final row = rows[id]!;
    row
      ..['status'] = status
      ..['decided_at'] = DateTime.now().toUtc().toIso8601String()
      ..['decided_by_name'] = 'Başka Yönetici'
      ..['decision_source'] = 'super_user'
      ..['decision_note'] = note
      ..['device_available'] = false
      ..['site_code'] = status == 'approved' ? 900 + id : null;
    if (status == 'approved' && _mine(row)) {
      serverRole = UserRole.siteManager;
      if (serverRequiresApplication != null) serverRequiresApplication = false;
    }
  }

  @visibleForTesting
  void seed(Iterable<Map<String, dynamic>> list) {
    for (final row in list) {
      rows[row['id'] as int] = row;
    }
  }
}

/// Ekran okuyucu duyurularını (`SemanticsService.sendAnnouncement`) toplar; test bitince işleyiciyi kaldırır.
List<String> captureAnnouncements(WidgetTester t) {
  final announced = <String>[];
  t.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(SystemChannels.accessibility, (
    dynamic message,
  ) async {
    if (message is Map && message['type'] == 'announce') {
      final data = message['data'];
      if (data is Map && data['message'] is String) announced.add(data['message'] as String);
    }
    return null;
  });
  addTearDown(
    () => t.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(
      SystemChannels.accessibility,
      null,
    ),
  );
  return announced;
}

/// Bir cihaz kaydı (`GET /membership/my-devices` öğesi).
Map<String, dynamic> saDevice(String uid, {int? siteCode}) => <String, dynamic>{
  'device_uid': uid,
  'hardware_type': 'esp32_wroom',
  'claimed_at': '2026-10-01T10:00:00Z',
  'site_code': siteCode,
};
