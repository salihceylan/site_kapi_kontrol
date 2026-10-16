import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:site_kapi_kontrol/models/announcement.dart';
import 'package:site_kapi_kontrol/models/apartment_record.dart';
import 'package:site_kapi_kontrol/models/audit_log.dart';
import 'package:site_kapi_kontrol/models/device_connectivity_log.dart';
import 'package:site_kapi_kontrol/models/device_page.dart';
import 'package:site_kapi_kontrol/models/device_record.dart';
import 'package:site_kapi_kontrol/models/door_access_log_record.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/models/door_runtime_status.dart';
import 'package:site_kapi_kontrol/models/guest_pass.dart';
import 'package:site_kapi_kontrol/models/managed_user_account.dart';
import 'package:site_kapi_kontrol/models/managed_user_page.dart';
import 'package:site_kapi_kontrol/models/apartment_crm.dart';
import 'package:site_kapi_kontrol/models/history_item.dart';
import 'package:site_kapi_kontrol/models/module_request.dart';
import 'package:site_kapi_kontrol/models/person_record.dart';
import 'package:site_kapi_kontrol/models/residency_relation.dart';
import 'package:site_kapi_kontrol/models/vehicle_record.dart';
import 'package:site_kapi_kontrol/models/platform_module.dart';
import 'package:site_kapi_kontrol/models/staff_role_record.dart';
import 'package:site_kapi_kontrol/models/site_page.dart';
import 'package:site_kapi_kontrol/models/site_record.dart';
import 'package:site_kapi_kontrol/models/site_join_token_record.dart';
import 'package:site_kapi_kontrol/models/join_request_record.dart';
import 'package:site_kapi_kontrol/models/site_join_info.dart';
import 'package:site_kapi_kontrol/models/apartment_member_record.dart';
import 'package:site_kapi_kontrol/models/site_structure_record.dart';
import 'package:site_kapi_kontrol/models/site_manager_record.dart';
import 'package:site_kapi_kontrol/models/subscription_request.dart';
import 'package:site_kapi_kontrol/models/subscription_request_page.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/background_work.dart';

class AuthApi {
  AuthApi({
    required this.baseUrl,
    http.Client? client,
    Duration? requestTimeout,
    Duration? readTimeout,
    Duration? doorOpenTimeout,
    Duration? retryDelay,
  })  : _client = client ?? http.Client(),
        _requestTimeout = requestTimeout ?? const Duration(seconds: 45),
        _readTimeout = readTimeout ?? _defaultReadTimeout(requestTimeout),
        _doorOpenTimeout = doorOpenTimeout ?? const Duration(seconds: 10),
        _retryDelay = retryDelay ?? const Duration(milliseconds: 350);

  final String baseUrl;
  final http.Client _client;

  /// Okuma (GET) isteklerinin varsayılan zaman aşımı üst sınırı.
  static const Duration _maxDefaultReadTimeout = Duration(seconds: 20);

  /// Okuma zaman aşımı: açıkça verilmediyse 20 sn; genel [requestTimeout] daha kısaysa o.
  static Duration _defaultReadTimeout(Duration? requestTimeout) {
    if (requestTimeout != null && requestTimeout < _maxDefaultReadTimeout) {
      return requestTimeout;
    }
    return _maxDefaultReadTimeout;
  }

  /// Genel (yazma: POST/PATCH/PUT/DELETE) istek zaman aşımı. Yazmalar tekrar edilmez ve
  /// sunucu tarafında uzun sürebilir (site oluşturma vb.); bu yüzden okumadan uzundur.
  final Duration _requestTimeout;

  /// Okuma (GET) zaman aşımı: kullanıcı beklerken arayüz kilitli hissettirmesin (20 sn).
  final Duration _readTimeout;

  /// Kapı açma komutları (bulut + QR) için kısa zaman aşımı: kullanıcı kapıda bekler.
  final Duration _doorOpenTimeout;

  /// Yalnızca GET isteklerinde yeniden deneme öncesi bekleme.
  final Duration _retryDelay;

  Future<UserSession> login({
    required String email,
    required String password,
    UserRole? role,
  }) async {
    return _authRequest(
      path: '/auth/login',
      body: {
        'email': email,
        'password': password,
        if (role != null) 'role': role.apiValue,
      },
      expectedCode: 200,
    );
  }

  String _managementPrefix(UserRole role) {
    return role == UserRole.superUser ? '/admin' : '/manager';
  }

  Future<Map<String, dynamic>> registerIndividual({
    required String firstName,
    required String lastName,
    required String email,
    required String password,
  }) async {
    final uri = Uri.parse('$baseUrl/auth/register-individual');
    final response = await _sendRequest(
      method: 'POST',
      uri: uri,
      headers: const {'Content-Type': 'application/json'},
      body: {
        'first_name': firstName,
        'last_name': lastName,
        'email': email,
        'password': password,
      },
    );
    _ensureStatus(response, 201, unauthorizedIsSession: false);
    return _decodePayload(response);
  }

  Future<UserSession> verifyIndividualCode({
    required String email,
    required String code,
  }) async {
    return _authRequest(
      path: '/auth/verify-code',
      body: {
        'email': email,
        'code': code,
      },
      expectedCode: 200,
    );
  }

  Future<Map<String, dynamic>> resendIndividualCode({
    required String email,
  }) async {
    final uri = Uri.parse('$baseUrl/auth/resend-code');
    final response = await _sendRequest(
      method: 'POST',
      uri: uri,
      headers: const {'Content-Type': 'application/json'},
      body: {
        'email': email,
      },
    );
    _ensureStatus(response, 200, unauthorizedIsSession: false);
    return _decodePayload(response);
  }

  Future<Map<String, dynamic>> forgotPassword({
    required String email,
  }) async {
    final uri = Uri.parse('$baseUrl/auth/forgot-password');
    final response = await _sendRequest(
      method: 'POST',
      uri: uri,
      headers: const {'Content-Type': 'application/json'},
      body: {
        'email': email,
      },
    );
    _ensureStatus(response, 200, unauthorizedIsSession: false);
    return _decodePayload(response);
  }

  Future<UserSession> register({
    required String fullName,
    required String email,
    required String password,
    required UserRole role,
    String? phoneNumber,
  }) async {
    return _authRequest(
      path: '/auth/register',
      body: {
        'full_name': fullName,
        'email': email,
        'password': password,
        'role': role.apiValue,
        'phone_number': phoneNumber,
      },
      expectedCode: 201,
    );
  }

  Future<ManagedUserPage> listManagedUsers({
    required String token,
    UserRole? role,
    UserRole? excludeRole,
    required int page,
    required int pageSize,
    String? search,
  }) async {
    final uri = Uri.parse('$baseUrl/admin/users').replace(
      queryParameters: {
        if (role != null) 'role': role.apiValue,
        if (excludeRole != null) 'exclude_role': excludeRole.apiValue,
        'page': '$page',
        'page_size': '$pageSize',
        if (search != null && search.trim().isNotEmpty)
          'search': search.trim(),
      },
    );

    final response = await _sendRequest(
      method: 'GET',
      uri: uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    _ensureStatus(response, 200);

    final payload = _decodePayload(response);
    final users = _parsePayload(
      'Kullanici listesi',
      () => (payload['users'] as List<dynamic>? ?? <dynamic>[])
          .map(
            (item) => ManagedUserAccount.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
    );

    return ManagedUserPage(
      users: users,
      total: payload['total'] as int? ?? 0,
      page: payload['page'] as int? ?? page,
      pageSize: payload['page_size'] as int? ?? pageSize,
    );
  }

  Future<void> createManagedUser({
    required String token,
    required String fullName,
    required String email,
    required String password,
    required UserRole role,
    required bool isActive,
    String? phoneNumber,
  }) async {
    final response = await _authorizedRequest(
      method: 'POST',
      path: '/admin/users',
      token: token,
      body: {
        'full_name': fullName,
        'email': email,
        'password': password,
        'role': role.apiValue,
        'is_active': isActive,
        'phone_number': phoneNumber,
      },
    );

    _ensureStatus(response, 201);
  }

  Future<void> updateManagedUser({
    required String token,
    required int userCode,
    String? fullName,
    String? email,
    String? password,
    String? phoneNumber,
    bool? isActive,
    UserRole? role,
    bool? emailVerified,
  }) async {
    final body = <String, dynamic>{
      'full_name': fullName,
      'email': email,
      'password': password,
      'phone_number': phoneNumber,
      'is_active': isActive,
      if (role != null) 'role': role.apiValue,
      // Süper kullanıcı e-posta doğrulama durumunu elle değiştirebilir (null = değiştirme).
      'email_verified': emailVerified,
    }..removeWhere((_, value) => value == null);

    final response = await _authorizedRequest(
      method: 'PATCH',
      path: '/admin/users/$userCode',
      token: token,
      body: body,
    );

    _ensureStatus(response, 200);
  }

  Future<void> setManagedUserActivation({
    required String token,
    required int userCode,
    required bool isActive,
  }) async {
    final response = await _authorizedRequest(
      method: 'PATCH',
      path: '/admin/users/$userCode/activation',
      token: token,
      body: {'is_active': isActive},
    );

    _ensureStatus(response, 200);
  }

  Future<void> deleteManagedUser({
    required String token,
    required int userCode,
  }) async {
    final response = await _authorizedRequest(
      method: 'DELETE',
      path: '/admin/users/$userCode',
      token: token,
    );

    _ensureStatus(response, 204, allowEmptyBody: true);
  }

  Future<Map<String, dynamic>> getDatabaseHealth({
    required String token,
  }) async {
    final response = await _authorizedRequest(
      method: 'GET',
      path: '/admin/maintenance/health',
      token: token,
    );

    _ensureStatus(response, 200);
    return _decodePayload(response);
  }

  Future<Map<String, dynamic>> runDatabaseCleanup({
    required String token,
  }) async {
    final response = await _authorizedRequest(
      method: 'POST',
      path: '/admin/maintenance/cleanup',
      token: token,
    );

    _ensureStatus(response, 200);
    return _decodePayload(response);
  }

  Future<SitePage> listSites({
    required String token,
    required UserRole role,
    required int page,
    required int pageSize,
    String? approvalStatus,
  }) async {
    final uri = Uri.parse('$baseUrl${_managementPrefix(role)}/sites').replace(
      queryParameters: {
        'page': '$page',
        'page_size': '$pageSize',
        if (role == UserRole.superUser && approvalStatus != null)
          'approval_status': approvalStatus,
      },
    );

    final response = await _sendRequest(
      method: 'GET',
      uri: uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    final sites = _parsePayload(
      'Site listesi',
      () => (payload['sites'] as List<dynamic>? ?? <dynamic>[])
          .map((item) => SiteRecord.fromJson(item as Map<String, dynamic>))
          .toList(),
    );

    return SitePage(
      sites: sites,
      total: payload['total'] as int? ?? 0,
      page: payload['page'] as int? ?? page,
      pageSize: payload['page_size'] as int? ?? pageSize,
    );
  }

  Future<void> resolveSiteApproval({
    required String token,
    required int siteCode,
    required String action,
  }) async {
    final response = await _authorizedRequest(
      method: 'PATCH',
      path: '/admin/sites/$siteCode/approval',
      token: token,
      body: {'action': action},
    );

    _ensureStatus(response, 200);
  }

  Future<SiteRecord> createSite({
    required String token,
    required UserRole role,
    required String name,
    String? address,
    String? city,
    String? district,
    required List<int> blockApartmentCounts,
    required int doorCount,
    int? managerUserCode,
    Map<String, dynamic>? managerUser,
    String? managementType,
  }) async {
    final totalApartments = blockApartmentCounts.fold<int>(
      0,
      (sum, count) => sum + count,
    );
    final response = await _authorizedRequest(
      method: 'POST',
      path: '${_managementPrefix(role)}/sites',
      token: token,
      body: {
        'name': name,
        'address': address,
        'city': city,
        'district': district,
        'block_count': blockApartmentCounts.length,
        'apartment_count': totalApartments,
        'block_apartment_counts': blockApartmentCounts,
        'door_count': doorCount,
        'manager_user_code': managerUserCode,
        'manager_user': managerUser,
        // Yönetim türü (Faz 1: yalnız apartment_site); verilmezse alan hiç gönderilmez.
        if (managementType != null && managementType.isNotEmpty)
          'management_type': managementType,
      },
    );

    _ensureStatus(response, 201);
    final payload = _decodePayload(response);
    return _parsePayload(
      'Site kaydi',
      () => SiteRecord.fromJson(payload['site'] as Map<String, dynamic>),
    );
  }

  Future<SiteRecord> updateSite({
    required String token,
    required UserRole role,
    required int siteCode,
    String? name,
    String? address,
    String? city,
    String? district,
    List<int>? blockApartmentCounts,
    int? doorCount,
    int? managerUserCode,
  }) async {
    final totalApartments = blockApartmentCounts?.fold<int>(
      0,
      (sum, count) => sum + count,
    );
    final body = <String, dynamic>{
      'name': name,
      'address': address,
      'city': city,
      'district': district,
      'block_count': blockApartmentCounts?.length,
      'apartment_count': totalApartments,
      'block_apartment_counts': blockApartmentCounts,
      'door_count': doorCount,
      'manager_user_code': managerUserCode,
    }..removeWhere((_, value) => value == null);

    final response = await _authorizedRequest(
      method: 'PATCH',
      path: '${_managementPrefix(role)}/sites/$siteCode',
      token: token,
      body: body,
    );

    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return _parsePayload(
      'Site kaydi',
      () => SiteRecord.fromJson(payload['site'] as Map<String, dynamic>),
    );
  }

  Future<SiteRecord> updateSiteFeatures({
    required String token,
    required int siteCode,
    bool? featureQrEnabled,
    bool? featureRemoteOpenEnabled,
    bool? featureLocalUdpEnabled,
    bool? featureGuestPassEnabled,
  }) async {
    final body = <String, dynamic>{
      'feature_qr_enabled': featureQrEnabled,
      'feature_remote_open_enabled': featureRemoteOpenEnabled,
      'feature_local_udp_enabled': featureLocalUdpEnabled,
      'feature_guest_pass_enabled': featureGuestPassEnabled,
    }..removeWhere((_, value) => value == null);

    final response = await _authorizedRequest(
      method: 'PATCH',
      path: '/admin/sites/$siteCode/features',
      token: token,
      body: body,
    );

    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return _parsePayload(
      'Site modulleri',
      () => SiteRecord.fromJson(payload['site'] as Map<String, dynamic>),
    );
  }

  Future<SiteRecord> updateSiteSecurityPolicy({
    required String token,
    required UserRole role,
    required int siteCode,
    bool? featureRemoteOpenEnabled,
    bool? featureQrEnabled,
    bool? featureLocalUdpEnabled,
    bool? featureGuestPassEnabled,
    bool? qrEntryActive,
    bool? requireGeofence,
    double? geofenceLatitude,
    double? geofenceLongitude,
    int? geofenceRadiusMeters,
    int? qrRotationSeconds,
  }) async {
    final body = <String, dynamic>{
      'feature_remote_open_enabled': featureRemoteOpenEnabled,
      'feature_qr_enabled': featureQrEnabled,
      'feature_local_udp_enabled': featureLocalUdpEnabled,
      'feature_guest_pass_enabled': featureGuestPassEnabled,
      'qr_entry_active': qrEntryActive,
      'require_geofence': requireGeofence,
      'geofence_latitude': geofenceLatitude,
      'geofence_longitude': geofenceLongitude,
      'geofence_radius_meters': geofenceRadiusMeters,
      'qr_rotation_seconds': qrRotationSeconds,
    }..removeWhere((_, value) => value == null);

    final response = await _authorizedRequest(
      method: 'PATCH',
      path: '${_managementPrefix(role)}/sites/$siteCode/security-policy',
      token: token,
      body: body,
    );

    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return _parsePayload(
      'Guvenlik politikasi',
      () => SiteRecord.fromJson(payload['site'] as Map<String, dynamic>),
    );
  }

  Future<SiteStructureRecord> getSiteStructure({
    required String token,
    required UserRole role,
    required int siteCode,
  }) async {
    final response = await _authorizedRequest(
      method: 'GET',
      path: '${_managementPrefix(role)}/sites/$siteCode/structure',
      token: token,
    );

    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return _parsePayload(
      'Site yapisi',
      () => SiteStructureRecord.fromJson(payload),
    );
  }

  // --- Platform modül sistemi (Faz 1) -------------------------------------------------------
  // Modül ve ek rol uçları site yönetimi yolundadır (`/manager/...`): süper kullanıcı da aynı
  // uçlarla çalışır (sunucu `hasSiteManagementAccess` ile geçirir); denetim kaydı yalnız süper
  // kullanıcıya açık `/admin/audit-log` ucundadır.

  Future<List<PlatformModule>> getModuleCatalog({required String token}) async {
    final response = await _authorizedRequest(
      method: 'GET',
      path: '/app/modules/catalog',
      token: token,
    );
    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return _parsePayload(
      'Modül kataloğu',
      () => (payload['modules'] as List<dynamic>? ?? <dynamic>[])
          .map((item) => PlatformModule.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }

  Future<MyModulesResult> getMyModules({required String token}) async {
    final response = await _authorizedRequest(
      method: 'GET',
      path: '/app/my-modules',
      token: token,
    );
    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return _parsePayload('Modül durumu', () => MyModulesResult.fromJson(payload));
  }

  Future<SiteModulesState> getSiteModules({
    required String token,
    required int siteCode,
  }) async {
    final response = await _authorizedRequest(
      method: 'GET',
      path: '/manager/sites/$siteCode/modules',
      token: token,
    );
    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return _parsePayload(
      'Site modülleri',
      () => SiteModulesState.fromJson(payload),
    );
  }

  /// Modülü açar/kapatır. Geçiş Kontrol KAPATILIRKEN [confirm] true olmalıdır (aksi halde sunucu
  /// 409 `MODULE_CONFIRM_REQUIRED` döner); uygulama onay penceresini önceden gösterir.
  Future<SiteModulesState> setSiteModule({
    required String token,
    required int siteCode,
    required String moduleCode,
    required bool enabled,
    bool confirm = false,
  }) async {
    final response = await _authorizedRequest(
      method: 'PUT',
      path: '/manager/sites/$siteCode/modules/${Uri.encodeComponent(moduleCode)}',
      token: token,
      body: {'enabled': enabled, 'confirm': confirm},
    );
    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return _parsePayload(
      'Site modülleri',
      () => SiteModulesState.fromJson(payload),
    );
  }

  /// Denetim kaydı (yalnız süper kullanıcı). `id DESC`; sonraki sayfa için önceki yanıttaki
  /// `next_before_id` [beforeId] olarak verilir.
  Future<AuditLogPage> listAuditLog({
    required String token,
    int? siteCode,
    int limit = 50,
    int? beforeId,
    String? action,
  }) async {
    final query = <String, String>{
      if (siteCode != null) 'site_code': '$siteCode',
      if (action != null && action.isNotEmpty) 'action': action,
      'limit': '$limit',
      if (beforeId != null) 'before_id': '$beforeId',
    };
    final path = Uri(path: '/admin/audit-log', queryParameters: query).toString();
    final response = await _authorizedRequest(
      method: 'GET',
      path: path,
      token: token,
    );
    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return _parsePayload('Denetim kaydı', () => AuditLogPage.fromJson(payload));
  }

  Future<List<StaffRoleRecord>> listStaffRoles({
    required String token,
    required int siteCode,
  }) async {
    final response = await _authorizedRequest(
      method: 'GET',
      path: '/manager/sites/$siteCode/staff-roles',
      token: token,
    );
    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return _parsePayload(
      'Ek roller',
      () => (payload['items'] as List<dynamic>? ?? <dynamic>[])
          .map((item) => StaffRoleRecord.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }

  /// E-postası verilen mevcut hesaba ek rol (`BOARD_MEMBER` ya da `STAFF`) atar.
  Future<StaffRoleRecord> assignStaffRole({
    required String token,
    required int siteCode,
    required String email,
    required String role,
  }) async {
    final response = await _authorizedRequest(
      method: 'PUT',
      path: '/manager/sites/$siteCode/staff-roles',
      token: token,
      body: {'email': email, 'role': role},
    );
    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return _parsePayload(
      'Ek rol',
      () => StaffRoleRecord.fromJson(payload['item'] as Map<String, dynamic>),
    );
  }

  Future<void> removeStaffRole({
    required String token,
    required int siteCode,
    required int userCode,
  }) async {
    final response = await _authorizedRequest(
      method: 'DELETE',
      path: '/manager/sites/$siteCode/staff-roles/$userCode',
      token: token,
    );
    _ensureStatus(response, 200);
  }

  // --- Modül talebi (Faz 1.1) ---------------------------------------------------------------
  // Site yöneticisi modülü kendi açmaz, TALEP eder (`/manager/sites/:siteCode/module-requests`);
  // süper kullanıcı talepleri `/admin/module-requests` ucundan listeler ve karara bağlar.

  /// Modül talebi oluşturur (201). [note] en çok 500 karakter, isteğe bağlı.
  Future<ModuleRequest> createModuleRequest({
    required String token,
    required int siteCode,
    required String moduleCode,
    String? note,
  }) async {
    final trimmed = note?.trim();
    final response = await _authorizedRequest(
      method: 'POST',
      path: '/manager/sites/$siteCode/module-requests',
      token: token,
      body: {
        'module_code': moduleCode,
        if (trimmed != null && trimmed.isNotEmpty) 'note': trimmed,
      },
    );
    _ensureStatus(response, 201);
    final payload = _decodePayload(response);
    return _parsePayload(
      'Modül talebi',
      () => ModuleRequest.fromJson(payload['request'] as Map<String, dynamic>),
    );
  }

  /// Sitenin son modül talepleri (en çok 50, `id DESC`).
  Future<List<ModuleRequest>> listModuleRequests({
    required String token,
    required int siteCode,
  }) async {
    final response = await _authorizedRequest(
      method: 'GET',
      path: '/manager/sites/$siteCode/module-requests',
      token: token,
    );
    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return _parsePayload(
      'Modül talepleri',
      () => (payload['items'] as List<dynamic>? ?? <dynamic>[])
          .map((item) => ModuleRequest.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }

  /// Bekleyen talebi geri çeker (`cancelled`).
  Future<ModuleRequest> cancelModuleRequest({
    required String token,
    required int siteCode,
    required int requestId,
  }) async {
    final response = await _authorizedRequest(
      method: 'DELETE',
      path: '/manager/sites/$siteCode/module-requests/$requestId',
      token: token,
    );
    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return _parsePayload(
      'Modül talebi',
      () => ModuleRequest.fromJson(payload['request'] as Map<String, dynamic>),
    );
  }

  /// Süper kullanıcı: talepler. [status] `pending|approved|rejected|cancelled|all` (sunucu varsayılanı
  /// `pending`). Sonraki sayfa için önceki yanıttaki `next_before_id` [beforeId] olarak verilir.
  Future<ModuleRequestPage> listAdminModuleRequests({
    required String token,
    String? status,
    int limit = 50,
    int? beforeId,
  }) async {
    final query = <String, String>{
      if (status != null && status.isNotEmpty) 'status': status,
      'limit': '$limit',
      if (beforeId != null) 'before_id': '$beforeId',
    };
    final path = Uri(path: '/admin/module-requests', queryParameters: query).toString();
    final response = await _authorizedRequest(method: 'GET', path: path, token: token);
    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return _parsePayload('Modül talepleri', () => ModuleRequestPage.fromJson(payload));
  }

  /// Süper kullanıcı: talebi onaylar (`approve`) ya da reddeder (`reject`); [note] isteğe bağlı gerekçe.
  Future<ModuleRequest> decideModuleRequest({
    required String token,
    required int requestId,
    required bool approve,
    String? note,
  }) async {
    final trimmed = note?.trim();
    final response = await _authorizedRequest(
      method: 'PUT',
      path: '/admin/module-requests/$requestId',
      token: token,
      body: {
        'decision': approve ? 'approve' : 'reject',
        if (trimmed != null && trimmed.isNotEmpty) 'note': trimmed,
      },
    );
    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return _parsePayload(
      'Modül talebi',
      () => ModuleRequest.fromJson(payload['request'] as Map<String, dynamic>),
    );
  }

  // --- Kişi ve Daire Kayıtları (Faz 2a) -----------------------------------------------------
  // Hepsi `/manager/sites/:siteCode/...` altındadır (sözleşme: docs/PLATFORM_KISILER.md). Okuma
  // yönetici / süper kullanıcı / kurul üyesine, yazma yalnız yönetici / süper kullanıcıya açıktır;
  // yetki sunucuda doğrulanır (403 FORBIDDEN_ROLE / FORBIDDEN_SITE).

  String _peoplePath(int siteCode, String tail, [Map<String, String>? query]) {
    final path = '/manager/sites/$siteCode/$tail';
    if (query == null || query.isEmpty) return path;
    return Uri(path: path, queryParameters: query).toString();
  }

  /// Kişi listesi. [status]: `active|inactive|all` (sunucu varsayılanı `active`); [relation]: kişinin
  /// GÜNCEL ilişkilerinden biri.
  Future<PersonPage> listPeople({
    required String token,
    required int siteCode,
    String? query,
    ResidencyRelation? relation,
    String? status,
    int? apartmentId,
    int limit = 50,
    int offset = 0,
  }) async {
    final trimmed = query?.trim();
    final response = await _authorizedRequest(
      method: 'GET',
      path: _peoplePath(siteCode, 'people', {
        if (trimmed != null && trimmed.isNotEmpty) 'q': trimmed,
        if (relation != null) 'relation': relation.apiValue,
        if (status != null && status.isNotEmpty) 'status': status,
        if (apartmentId != null) 'apartment_id': '$apartmentId',
        'limit': '$limit',
        'offset': '$offset',
      }),
      token: token,
    );
    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return _parsePayload('Kişiler', () => PersonPage.fromJson(payload));
  }

  Future<PersonDetail> getPerson({
    required String token,
    required int siteCode,
    required int personId,
  }) async {
    final response = await _authorizedRequest(
      method: 'GET',
      path: _peoplePath(siteCode, 'people/$personId'),
      token: token,
    );
    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return _parsePayload('Kişi', () => PersonDetail.fromJson(payload));
  }

  /// Kişi ekler (201). [apartmentId] verilirse [relation] ile o daireye bağlanır; e-posta kayıtlı bir
  /// hesaba aitse kişi o hesaba bağlanır (sunucu kararı).
  Future<PersonDetail> createPerson({
    required String token,
    required int siteCode,
    required String fullName,
    String? phone,
    String? email,
    String? note,
    int? apartmentId,
    ResidencyRelation? relation,
    DateTime? moveInDate,
  }) async {
    final response = await _authorizedRequest(
      method: 'POST',
      path: _peoplePath(siteCode, 'people'),
      token: token,
      body: {
        'full_name': fullName.trim(),
        if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
        if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
        'apartment_id': ?apartmentId,
        if (apartmentId != null && relation != null) 'relation': relation.apiValue,
        if (apartmentId != null && moveInDate != null)
          'move_in_date': crmDateParam(moveInDate),
      },
    );
    _ensureStatus(response, 201);
    final payload = _decodePayload(response);
    return _parsePayload('Kişi', () => PersonDetail.fromJson(payload));
  }

  /// Kişiyi günceller: yalnız [fields] içindeki alanlar gönderilir (`full_name`, `phone`, `email`,
  /// `note`, `is_active`). Hesabı olan kişide ad/telefon/e-posta gönderilirse sunucu 409
  /// `PERSON_HAS_ACCOUNT` döner.
  Future<PersonDetail> updatePerson({
    required String token,
    required int siteCode,
    required int personId,
    required Map<String, Object?> fields,
  }) async {
    final response = await _authorizedRequest(
      method: 'PATCH',
      path: _peoplePath(siteCode, 'people/$personId'),
      token: token,
      body: Map<String, dynamic>.of(fields),
    );
    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return _parsePayload('Kişi', () => PersonDetail.fromJson(payload));
  }

  /// Kişiye bir daire ilişkisi ekler (201).
  Future<PersonDetail> addResidency({
    required String token,
    required int siteCode,
    required int personId,
    required int apartmentId,
    required ResidencyRelation relation,
    DateTime? moveInDate,
  }) async {
    final response = await _authorizedRequest(
      method: 'POST',
      path: _peoplePath(siteCode, 'people/$personId/residencies'),
      token: token,
      body: {
        'apartment_id': apartmentId,
        'relation': relation.apiValue,
        if (moveInDate != null) 'move_in_date': crmDateParam(moveInDate),
      },
    );
    _ensureStatus(response, 201);
    final payload = _decodePayload(response);
    return _parsePayload('Kişi', () => PersonDetail.fromJson(payload));
  }

  Future<PersonDetail> updateResidency({
    required String token,
    required int siteCode,
    required int residencyId,
    ResidencyRelation? relation,
    DateTime? moveInDate,

    /// true ve [moveInDate] null: giriş tarihi AÇIKÇA temizlenir (`move_in_date: null`).
    bool clearMoveInDate = false,
  }) async {
    final response = await _authorizedRequest(
      method: 'PATCH',
      path: _peoplePath(siteCode, 'residencies/$residencyId'),
      token: token,
      body: {
        if (relation != null) 'relation': relation.apiValue,
        if (moveInDate != null)
          'move_in_date': crmDateParam(moveInDate)
        else if (clearMoveInDate)
          'move_in_date': null,
      },
    );
    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return _parsePayload('Kişi', () => PersonDetail.fromJson(payload));
  }

  /// "Taşındı": ilişkiyi bitirir (kayıt silinmez). Kişinin hesabı varsa o dairedeki kapı yetkisi
  /// sunucuda kapanır. [moveOutDate] verilmezse sunucu bugünü yazar.
  Future<PersonDetail> endResidency({
    required String token,
    required int siteCode,
    required int residencyId,
    DateTime? moveOutDate,
  }) async {
    final response = await _authorizedRequest(
      method: 'POST',
      path: _peoplePath(siteCode, 'residencies/$residencyId/end'),
      token: token,
      body: {if (moveOutDate != null) 'move_out_date': crmDateParam(moveOutDate)},
    );
    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return _parsePayload('Kişi', () => PersonDetail.fromJson(payload));
  }

  Future<ApartmentPage> listApartments({
    required String token,
    required int siteCode,
    int? blockId,
    String? query,
    int limit = 50,
    int offset = 0,
  }) async {
    final trimmed = query?.trim();
    final response = await _authorizedRequest(
      method: 'GET',
      path: _peoplePath(siteCode, 'apartments', {
        if (blockId != null) 'block_id': '$blockId',
        if (trimmed != null && trimmed.isNotEmpty) 'q': trimmed,
        'limit': '$limit',
        'offset': '$offset',
      }),
      token: token,
    );
    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return _parsePayload('Daireler', () => ApartmentPage.fromJson(payload));
  }

  Future<ApartmentDetail> getApartment({
    required String token,
    required int siteCode,
    required int apartmentId,
  }) async {
    final response = await _authorizedRequest(
      method: 'GET',
      path: _peoplePath(siteCode, 'apartments/$apartmentId'),
      token: token,
    );
    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return _parsePayload('Daire', () => ApartmentDetail.fromJson(payload));
  }

  /// Daire alanlarını günceller: yalnız [fields] içindekiler gönderilir (`floor`, `gross_area_m2`,
  /// `net_area_m2`, `land_share_numerator`, `land_share_denominator`, `category`,
  /// `responsible_party`). Blok ve daire etiketi bu uçla DEĞİŞMEZ.
  Future<ApartmentDetail> updateApartment({
    required String token,
    required int siteCode,
    required int apartmentId,
    required Map<String, Object?> fields,
  }) async {
    final response = await _authorizedRequest(
      method: 'PATCH',
      path: _peoplePath(siteCode, 'apartments/$apartmentId'),
      token: token,
      body: Map<String, dynamic>.of(fields),
    );
    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return _parsePayload('Daire', () => ApartmentDetail.fromJson(payload));
  }

  Future<VehiclePage> listVehicles({
    required String token,
    required int siteCode,
    String? query,
    int? personId,
    int limit = 50,
    int offset = 0,
  }) async {
    final trimmed = query?.trim();
    final response = await _authorizedRequest(
      method: 'GET',
      path: _peoplePath(siteCode, 'vehicles', {
        if (trimmed != null && trimmed.isNotEmpty) 'q': trimmed,
        if (personId != null) 'person_id': '$personId',
        'limit': '$limit',
        'offset': '$offset',
      }),
      token: token,
    );
    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return _parsePayload('Araçlar', () => VehiclePage.fromJson(payload));
  }

  /// Araç ekler (201). Plakayı sunucu normalize eder (`34 ABC 123` -> `34ABC123`).
  Future<VehicleRecord> createVehicle({
    required String token,
    required int siteCode,
    required int personId,
    required String plate,
    String? note,
  }) async {
    final response = await _authorizedRequest(
      method: 'POST',
      path: _peoplePath(siteCode, 'vehicles'),
      token: token,
      body: {
        'person_id': personId,
        'plate': plate.trim(),
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      },
    );
    _ensureStatus(response, 201);
    final payload = _decodePayload(response);
    return _parsePayload(
      'Araç',
      () => VehicleRecord.fromJson(payload['vehicle'] as Map<String, dynamic>),
    );
  }

  /// Aracı kaldırır (kayıt pasifleşir, silinmez).
  Future<void> removeVehicle({
    required String token,
    required int siteCode,
    required int vehicleId,
  }) async {
    final response = await _authorizedRequest(
      method: 'DELETE',
      path: _peoplePath(siteCode, 'vehicles/$vehicleId'),
      token: token,
    );
    _ensureStatus(response, 200);
  }

  /// Değişiklik geçmişi (F2.11). [targetType]: `person|apartment|vehicle`; `id DESC`, sonraki sayfa
  /// için önceki yanıttaki `next_before_id` [beforeId] olarak verilir.
  Future<HistoryPage> listHistory({
    required String token,
    required int siteCode,
    String? targetType,
    int? targetId,
    int limit = 50,
    int? beforeId,
  }) async {
    final response = await _authorizedRequest(
      method: 'GET',
      path: _peoplePath(siteCode, 'history', {
        if (targetType != null && targetType.isNotEmpty) 'target_type': targetType,
        if (targetId != null) 'target_id': '$targetId',
        'limit': '$limit',
        if (beforeId != null) 'before_id': '$beforeId',
      }),
      token: token,
    );
    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return _parsePayload('Geçmiş', () => HistoryPage.fromJson(payload));
  }

  /// Sakinin KENDİ güncel kayıtları (daireler, ilişki, giriş tarihi, araçlar).
  Future<List<MyRecord>> getMyRecords({required String token}) async {
    final response = await _authorizedRequest(
      method: 'GET',
      path: '/app/my-records',
      token: token,
    );
    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return _parsePayload('Kayıtlarım', () => MyRecord.listFrom(payload['records']));
  }

  // --- Duyuru ve Bildirim (Faz 3a) ----------------------------------------------------------
  // Yönetici uçları `/manager/sites/:siteCode/announcements...`, sakin uçları `/app/...` altındadır
  // (sözleşme: docs/PLATFORM_DUYURU.md). Okuma yönetici / süper kullanıcı / kurul üyesine, yazma yalnız
  // yönetici / süper kullanıcıya açıktır; yetki sunucuda doğrulanır (403 FORBIDDEN_ROLE / FORBIDDEN_SITE).

  String _announcementPath(int siteCode, [String tail = '', Map<String, String>? query]) {
    final path =
        '/manager/sites/$siteCode/announcements${tail.isEmpty ? '' : '/$tail'}';
    if (query == null || query.isEmpty) return path;
    return Uri(path: path, queryParameters: query).toString();
  }

  /// Yönetici duyuru listesi. [status]: `draft|scheduled|published|withdrawn|all` (sunucu varsayılanı
  /// `all`); [query] başlıkta aranır.
  Future<AnnouncementPage> listAnnouncements({
    required String token,
    required int siteCode,
    String? status,
    String? query,
    int limit = 30,
    int offset = 0,
  }) async {
    final trimmed = query?.trim();
    final response = await _authorizedRequest(
      method: 'GET',
      path: _announcementPath(siteCode, '', {
        if (status != null && status.isNotEmpty) 'status': status,
        if (trimmed != null && trimmed.isNotEmpty) 'q': trimmed,
        'limit': '$limit',
        'offset': '$offset',
      }),
      token: token,
    );
    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return _parsePayload('Duyurular', () => AnnouncementPage.fromJson(payload));
  }

  Future<AnnouncementDetail> getAnnouncement({
    required String token,
    required int siteCode,
    required int announcementId,
  }) async {
    final response = await _authorizedRequest(
      method: 'GET',
      path: _announcementPath(siteCode, '$announcementId'),
      token: token,
    );
    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return _parsePayload('Duyuru', () => AnnouncementDetail.fromJson(payload));
  }

  /// Alıcılar (okuyan / okumayan). [read]: `all|true|false`. Kurul üyesine 403 döner.
  Future<AnnouncementRecipientPage> listAnnouncementRecipients({
    required String token,
    required int siteCode,
    required int announcementId,
    String? read,
    String? query,
    int limit = 50,
    int offset = 0,
  }) async {
    final trimmed = query?.trim();
    final response = await _authorizedRequest(
      method: 'GET',
      path: _announcementPath(siteCode, '$announcementId/recipients', {
        if (read != null && read.isNotEmpty) 'read': read,
        if (trimmed != null && trimmed.isNotEmpty) 'q': trimmed,
        'limit': '$limit',
        'offset': '$offset',
      }),
      token: token,
    );
    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return _parsePayload(
      'Alıcılar',
      () => AnnouncementRecipientPage.fromJson(payload),
    );
  }

  /// Yayın öncesi kitle önizlemesi (hiçbir şey yazmaz).
  Future<AudiencePreview> previewAnnouncementAudience({
    required String token,
    required int siteCode,
    required AnnouncementTargetInput target,
    bool sendEmail = false,
  }) async {
    final response = await _authorizedRequest(
      method: 'POST',
      path: _announcementPath(siteCode, 'preview-audience'),
      token: token,
      body: {'target': target.toJson(), 'send_email': sendEmail},
    );
    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return _parsePayload('Kitle önizlemesi', () => AudiencePreview.fromJson(payload));
  }

  /// Duyuru oluşturur (201). [publish]: `draft|now|schedule`; `schedule` iken [publishAt] verilir ve
  /// UTC ISO 8601 olarak gönderilir.
  Future<AnnouncementDetail> createAnnouncement({
    required String token,
    required int siteCode,
    required String title,
    required String body,
    required AnnouncementTargetInput target,
    AnnouncementImportance importance = AnnouncementImportance.normal,
    bool sendEmail = false,
    String publish = 'draft',
    DateTime? publishAt,
  }) async {
    final response = await _authorizedRequest(
      method: 'POST',
      path: _announcementPath(siteCode),
      token: token,
      body: {
        'title': title.trim(),
        'body': body.trim(),
        'importance': importance.apiValue,
        'target': target.toJson(),
        'send_email': sendEmail,
        'publish': publish,
        if (publish == 'schedule' && publishAt != null)
          'publish_at': publishAt.toUtc().toIso8601String(),
      },
    );
    _ensureStatus(response, 201);
    final payload = _decodePayload(response);
    return _parsePayload('Duyuru', () => AnnouncementDetail.fromJson(payload));
  }

  /// Duyuruyu günceller: yalnız [fields] içindekiler gönderilir (`title`, `body`, `importance`, `target`,
  /// `send_email`, `publish_at`). Yayınlanmış duyuruda yalnız `title` / `body` kabul edilir.
  Future<AnnouncementDetail> updateAnnouncement({
    required String token,
    required int siteCode,
    required int announcementId,
    required Map<String, Object?> fields,
  }) async {
    final response = await _authorizedRequest(
      method: 'PATCH',
      path: _announcementPath(siteCode, '$announcementId'),
      token: token,
      body: Map<String, dynamic>.of(fields),
    );
    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return _parsePayload('Duyuru', () => AnnouncementDetail.fromJson(payload));
  }

  /// Taslak / zamanlanmış duyuruyu şimdi yayınlar.
  Future<AnnouncementDetail> publishAnnouncement({
    required String token,
    required int siteCode,
    required int announcementId,
  }) async {
    final response = await _authorizedRequest(
      method: 'POST',
      path: _announcementPath(siteCode, '$announcementId/publish'),
      token: token,
      body: const <String, dynamic>{},
    );
    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return _parsePayload('Duyuru', () => AnnouncementDetail.fromJson(payload));
  }

  /// Yayındaki duyuruyu geri çeker (geri alınamaz).
  Future<AnnouncementDetail> withdrawAnnouncement({
    required String token,
    required int siteCode,
    required int announcementId,
  }) async {
    final response = await _authorizedRequest(
      method: 'POST',
      path: _announcementPath(siteCode, '$announcementId/withdraw'),
      token: token,
      body: const <String, dynamic>{},
    );
    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return _parsePayload('Duyuru', () => AnnouncementDetail.fromJson(payload));
  }

  /// Taslak / zamanlanmış duyuruyu siler.
  Future<void> deleteAnnouncement({
    required String token,
    required int siteCode,
    required int announcementId,
  }) async {
    final response = await _authorizedRequest(
      method: 'DELETE',
      path: _announcementPath(siteCode, '$announcementId'),
      token: token,
    );
    _ensureStatus(response, 200);
  }

  /// Sakin gelen kutusu (`published_at DESC, id DESC`); sonraki sayfa için önceki yanıttaki
  /// `next_before_id` [beforeId] olarak verilir. [siteCode] tek siteyle sınırlar.
  Future<ResidentAnnouncementPage> listMyAnnouncements({
    required String token,
    int limit = 30,
    int? beforeId,
    int? siteCode,
  }) async {
    final query = <String, String>{
      'limit': '$limit',
      if (beforeId != null) 'before_id': '$beforeId',
      if (siteCode != null) 'site_code': '$siteCode',
    };
    final response = await _authorizedRequest(
      method: 'GET',
      path: Uri(path: '/app/announcements', queryParameters: query).toString(),
      token: token,
    );
    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return _parsePayload('Duyurular', () => ResidentAnnouncementPage.fromJson(payload));
  }

  /// Sakin için tam kayıt. OKUNDU YAZMAZ ([markAnnouncementRead] ayrıdır).
  Future<ResidentAnnouncement> getMyAnnouncement({
    required String token,
    required int announcementId,
  }) async {
    final response = await _authorizedRequest(
      method: 'GET',
      path: '/app/announcements/$announcementId',
      token: token,
    );
    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return _parsePayload('Duyuru', () => ResidentAnnouncement.fromJson(payload));
  }

  /// Duyuruyu okundu işaretler (idempotent). Dönüş: ilk okuma zamanı (alan yoksa null).
  Future<DateTime?> markAnnouncementRead({
    required String token,
    required int announcementId,
  }) async {
    final response = await _authorizedRequest(
      method: 'POST',
      path: '/app/announcements/$announcementId/read',
      token: token,
      body: const <String, dynamic>{},
    );
    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return announcementInstant(payload['read_at']);
  }

  /// Tümünü okundu yapar ([siteCode] verilirse yalnız o site). Dönüş: işaretlenen adet.
  Future<int> markAllAnnouncementsRead({required String token, int? siteCode}) async {
    final response = await _authorizedRequest(
      method: 'POST',
      path: '/app/announcements/read-all',
      token: token,
      body: {'site_code': ?siteCode},
    );
    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return crmInt(payload['marked']);
  }

  /// Hafif bildirim özeti (uygulama bunu yoklar).
  Future<NotificationSummary> getNotificationSummary({required String token}) async {
    final response = await _authorizedRequest(
      method: 'GET',
      path: '/app/notifications/summary',
      token: token,
    );
    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return _parsePayload('Bildirim özeti', () => NotificationSummary.fromJson(payload));
  }

  Future<NotificationPrefs> getNotificationPreferences({required String token}) async {
    final response = await _authorizedRequest(
      method: 'GET',
      path: '/app/notification-preferences',
      token: token,
    );
    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return _parsePayload('Bildirim tercihleri', () => NotificationPrefs.fromJson(payload));
  }

  /// E-posta tercihini yazar. `push_*` anahtarları GÖNDERİLMEZ (şimdilik değişmez). Yanıtta tercih alanı
  /// yoksa istenen değer geçerli sayılır.
  Future<NotificationPrefs> setNotificationPreferences({
    required String token,
    required bool emailAnnouncements,
  }) async {
    final response = await _authorizedRequest(
      method: 'PUT',
      path: '/app/notification-preferences',
      token: token,
      body: {'email_announcements': emailAnnouncements},
    );
    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return _parsePayload(
      'Bildirim tercihleri',
      () => NotificationPrefs.fromJson(payload, fallbackEmail: emailAnnouncements),
    );
  }

  Future<ApartmentRecord> upsertApartmentResident({
    required String token,
    required UserRole role,
    required int apartmentId,
    required String fullName,
    required String loginName,
    required String password,
    String? email,
    String? phoneNumber,
    required bool isActive,
  }) async {
    final response = await _authorizedRequest(
      method: 'PATCH',
      path: '${_managementPrefix(role)}/apartments/$apartmentId/resident',
      token: token,
      body: {
        'full_name': fullName,
        'login_name': loginName,
        'password': password,
        'email': email,
        'phone_number': phoneNumber,
        'is_active': isActive,
      },
    );

    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return _parsePayload(
      'Daire kullanicisi',
      () => ApartmentRecord.fromJson(
        payload['apartment'] as Map<String, dynamic>,
      ),
    );
  }

  Future<void> sendApartmentCredentials({
    required String token,
    required UserRole role,
    required int apartmentId,
  }) async {
    final response = await _authorizedRequest(
      method: 'POST',
      path: '${_managementPrefix(role)}/apartments/$apartmentId/send-credentials',
      token: token,
    );

    _ensureStatus(response, 200);
  }

  Future<void> deleteApartmentResident({
    required String token,
    required UserRole role,
    required int apartmentId,
  }) async {
    final response = await _authorizedRequest(
      method: 'DELETE',
      path: '${_managementPrefix(role)}/apartments/$apartmentId/resident',
      token: token,
    );

    _ensureStatus(response, 200);
  }

  Future<DoorAccessLogPage> listDoorAccessLogs({
    required String token,
    required UserRole role,
    int? siteCode,
    int? doorId,
    String? search,
    DateTime? startDate,
    DateTime? endDate,
    int page = 1,
    int pageSize = 50,
  }) async {
    final query = <String, String>{
      'page': page.toString(),
      'page_size': pageSize.toString(),
      if (siteCode != null) 'site_code': siteCode.toString(),
      if (doorId != null) 'door_id': doorId.toString(),
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
      // Saat dilimi belirsizliğini önlemek için tarihler UTC olarak gönderilir.
      if (startDate != null) 'start_date': startDate.toUtc().toIso8601String(),
      if (endDate != null) 'end_date': endDate.toUtc().toIso8601String(),
    };

    final uri = Uri.parse('$baseUrl${_managementPrefix(role)}/door-logs')
        .replace(queryParameters: query);

    final response = await _sendRequest(
      method: 'GET',
      uri: uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return _parsePayload(
      'Kapi gecis loglari',
      () => DoorAccessLogPage.fromJson(payload),
    );
  }

  Future<DeviceConnectivityReport> getDeviceConnectivityLogs({
    required String token,
    required String deviceUid,
    int page = 1,
    int pageSize = 10,
  }) async {
    final query = <String, String>{
      'page': page.toString(),
      'page_size': pageSize.toString(),
    };

    final uri = Uri.parse('$baseUrl/admin/devices/${Uri.encodeComponent(deviceUid)}/connectivity-logs')
        .replace(queryParameters: query);

    final response = await _sendRequest(
      method: 'GET',
      uri: uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return _parsePayload(
      'Cihaz baglanti raporu',
      () => DeviceConnectivityReport.fromJson(payload),
    );
  }

  Future<int> syncDeviceLogs({
    required String deviceUid,
    required List<Map<String, dynamic>> logs,
    String? token,
  }) async {
    final uri = Uri.parse('$baseUrl/device/sync-logs');
    final response = await _sendRequest(
      method: 'POST',
      uri: uri,
      headers: {
        'Content-Type': 'application/json',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
        'X-Ahbu-Device-Uid': deviceUid,
      },
      body: {
        'device_uid': deviceUid,
        'logs': logs,
      },
    );

    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return (payload['synced_count'] as num?)?.toInt() ?? 0;
  }

  Future<DoorRecord> assignDoorDevice({
    required String token,
    required UserRole role,
    required int doorId,
    required String deviceUid,
  }) async {
    final response = await _authorizedRequest(
      method: 'PATCH',
      path: '${_managementPrefix(role)}/doors/$doorId/device',
      token: token,
      body: {'device_uid': deviceUid},
    );

    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return _parsePayload(
      'Kapi kaydi',
      () => DoorRecord.fromJson(payload['door'] as Map<String, dynamic>),
    );
  }

  Future<Map<String, dynamic>> deleteSite({
    required String token,
    required UserRole role,
    required int siteCode,
  }) async {
    final response = await _authorizedRequest(
      method: 'DELETE',
      path: '${_managementPrefix(role)}/sites/$siteCode',
      token: token,
    );

    // Boş gövde yalnızca BAŞARILI (2xx) yanıtta silme sayılır; boş gövdeli 4xx/5xx hata olarak
    // _ensureStatus'a düşer (geri dönüşsüz işlemde yanlış başarı gösterilmez).
    final status = response.statusCode;
    if (status == 204 ||
        (status >= 200 && status < 300 && response.body.trim().isEmpty)) {
      return {'ok': true, 'deleted': true};
    }
    _ensureStatus(response, 200);
    return _decodePayload(response);
  }

  Future<Map<String, dynamic>> approveSiteDeletion({
    required String token,
    required UserRole role,
    required int siteCode,
  }) async {
    final response = await _authorizedRequest(
      method: 'POST',
      path: '${_managementPrefix(role)}/sites/$siteCode/approve-deletion',
      token: token,
    );

    _ensureStatus(response, 200);
    return _decodePayload(response);
  }

  Future<Map<String, dynamic>> rejectSiteDeletion({
    required String token,
    required UserRole role,
    required int siteCode,
  }) async {
    final response = await _authorizedRequest(
      method: 'POST',
      path: '${_managementPrefix(role)}/sites/$siteCode/reject-deletion',
      token: token,
    );

    _ensureStatus(response, 200);
    return _decodePayload(response);
  }

  Future<Map<String, dynamic>> requestSiteDeletionEmailCode({
    required String token,
    required int siteCode,
  }) async {
    final response = await _authorizedRequest(
      method: 'POST',
      path: '/admin/sites/$siteCode/request-email-deletion-code',
      token: token,
    );

    _ensureStatus(response, 200);
    return _decodePayload(response);
  }

  Future<Map<String, dynamic>> confirmSiteDeletionWithEmailCode({
    required String token,
    required int siteCode,
    required String code,
  }) async {
    final response = await _authorizedRequest(
      method: 'POST',
      path: '/admin/sites/$siteCode/confirm-email-deletion',
      token: token,
      body: {'code': code},
    );

    _ensureStatus(response, 200);
    return _decodePayload(response);
  }

  Future<DeviceRecord> createDevice({
    required String token,
    required String deviceUid,
    int? assignedUserCode,
    int? siteCode,
  }) async {
    final response = await _authorizedRequest(
      method: 'POST',
      path: '/admin/devices',
      token: token,
      body: {
        'device_uid': deviceUid,
        'assigned_user_code': assignedUserCode,
        'site_code': siteCode,
      },
    );

    _ensureStatus(response, 201);
    final payload = _decodePayload(response);
    return _parsePayload(
      'Cihaz kaydi',
      () => DeviceRecord.fromJson(payload['device'] as Map<String, dynamic>),
    );
  }

  Future<DevicePage> listCompanyDevices({
    required String token,
    required UserRole role,
    required int page,
    required int pageSize,
  }) async {
    if (role == UserRole.siteManager) {
      final response = await _authorizedRequest(
        method: 'GET',
        path: '/manager/devices',
        token: token,
      );
      _ensureStatus(response, 200);
      final payload = _decodePayload(response);
      final devices = _parsePayload(
        'Cihazlar',
        () => (payload['devices'] as List<dynamic>? ?? <dynamic>[])
            .map((item) => DeviceRecord.fromJson(item as Map<String, dynamic>))
            .toList(),
      );
      return DevicePage(
        devices: devices,
        total: devices.length,
        page: 1,
        pageSize: devices.length,
      );
    }

    final uri = Uri.parse('$baseUrl/admin/devices').replace(
      queryParameters: {'page': '$page', 'page_size': '$pageSize'},
    );

    final response = await _sendRequest(
      method: 'GET',
      uri: uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    final devices = _parsePayload(
      'Cihazlar',
      () => (payload['devices'] as List<dynamic>? ?? <dynamic>[])
          .map((item) => DeviceRecord.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
    return DevicePage(
      devices: devices,
      total: payload['total'] as int? ?? 0,
      page: payload['page'] as int? ?? page,
      pageSize: payload['page_size'] as int? ?? pageSize,
    );
  }

  Future<DeviceRecord> updateDevice({
    required String token,
    required UserRole role,
    required int deviceId,
    int? assignedUserCode,
    int? siteCode,
    String? gateName,
  }) async {
    final response = await _authorizedRequest(
      method: 'PATCH',
      path: role == UserRole.superUser
          ? '/admin/devices/$deviceId'
          : '/manager/devices/$deviceId/assignment',
      token: token,
      body: {
        'assigned_user_code': assignedUserCode,
        'site_code': siteCode,
        'gate_name': gateName,
      },
    );

    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return _parsePayload(
      'Cihaz kaydi',
      () => DeviceRecord.fromJson(payload['device'] as Map<String, dynamic>),
    );
  }

  Future<void> deleteDevice({
    required String token,
    required UserRole role,
    required int deviceId,
  }) async {
    final response = await _authorizedRequest(
      method: 'DELETE',
      path: role == UserRole.superUser
          ? '/admin/devices/$deviceId'
          : '/manager/devices/$deviceId',
      token: token,
    );

    _ensureStatus(response, 204, allowEmptyBody: true);
  }

  Future<Map<String, dynamic>> broadcastOtaCheck({
    required String token,
  }) async {
    final response = await _authorizedRequest(
      method: 'POST',
      path: '/admin/devices/ota-check',
      token: token,
    );

    _ensureStatus(response, 202);
    return _decodePayload(response);
  }

  Future<Map<String, dynamic>> getDeviceMqttCredentials({
    required String token,
    required UserRole role,
    required String deviceUid,
  }) async {
    final response = await _authorizedRequest(
      method: 'POST',
      path: role == UserRole.superUser
          ? '/admin/devices/mqtt-credentials'
          : '/manager/devices/mqtt-credentials',
      token: token,
      body: {'device_uid': deviceUid},
    );

    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return _parsePayload(
      'MQTT cihaz kimligi',
      () => payload['mqtt'] as Map<String, dynamic>,
    );
  }

  Future<DoorRuntimeStatus> getDoorRuntimeStatus({
    required String token,
    required int doorId,
  }) async {
    final response = await _authorizedRequest(
      method: 'GET',
      path: '/app/doors/$doorId/status',
      token: token,
    );

    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return _parsePayload(
      'Kapi durumu',
      () => DoorRuntimeStatus.fromJson(payload),
    );
  }

  Future<DoorRuntimeStatus> openDoor({
    required String token,
    required int doorId,
    Map<String, dynamic>? location,
  }) async {
    // Konum alanları (C3): latitude, longitude, accuracy, timestamp (ISO UTC), is_mocked.
    final response = await _authorizedRequest(
      method: 'POST',
      path: '/app/doors/$doorId/open',
      token: token,
      body: location,
      timeout: _doorOpenTimeout,
      timeoutMessage:
          'Kapı komutuna zamanında yanıt alınamadı. Kapı açılmış olabilir; durumu kontrol edip gerekirse tekrar deneyin.',
    );

    _ensureStatus(response, 202);
    final payload = _decodePayload(response);
    return _parsePayload(
      'Kapi komutu',
      () => DoorRuntimeStatus.fromJson(payload),
    );
  }

  Future<Map<String, dynamic>> openDoorWithScannedQr({
    required String token,
    required String qrPayload,
    Map<String, dynamic>? location,
  }) async {
    final response = await _authorizedRequest(
      method: 'POST',
      path: '/app/doors/scan-qr-open',
      token: token,
      body: {
        'qr_payload': qrPayload.trim(),
        // Konum alanları (C3) gövdede üst düzey gönderilir.
        ...?location,
      },
      timeout: _doorOpenTimeout,
      timeoutMessage:
          'Karekod doğrulamasına zamanında yanıt alınamadı. Kapı açılmış olabilir; durumu kontrol edip gerekirse tekrar deneyin.',
    );

    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return payload;
  }

  Future<void> notifyLocalDoorOpened({
    required String token,
    required int doorId,
    String? localIp,
  }) async {
    final response = await _authorizedRequest(
      method: 'POST',
      path: '/app/doors/$doorId/local-open-notify',
      token: token,
      body: {
        if (localIp != null && localIp.trim().isNotEmpty)
          'local_ip': localIp.trim(),
      },
    );
    _ensureStatus(response, 200);
  }

  Future<Map<String, dynamic>> requestDoorQrToken({
    required String token,
    required int doorId,
    Map<String, dynamic>? location,
  }) async {
    final response = await _authorizedRequest(
      method: 'POST',
      path: '/app/doors/$doorId/qr-token',
      token: token,
      body: location != null ? {'location': location} : null,
    );

    _ensureStatus(response, 200);
    return _decodePayload(response);
  }

  Future<Map<String, dynamic>> revokeMyDoorQr({
    required String token,
    required int doorId,
  }) async {
    final response = await _authorizedRequest(
      method: 'POST',
      path: '/app/doors/$doorId/revoke-my-qr',
      token: token,
    );

    _ensureStatus(response, 200);
    return _decodePayload(response);
  }

  Future<Map<String, dynamic>> getDoorQrStatus({
    required String token,
    required String qrToken,
  }) async {
    final response = await _authorizedRequest(
      method: 'GET',
      path: '/app/doors/qr-status?token=${Uri.encodeComponent(qrToken)}',
      token: token,
    );

    _ensureStatus(response, 200);
    return _decodePayload(response);
  }


  Future<List<DoorRecord>> listMyDoors({required String token}) async {
    final response = await _authorizedRequest(
      method: 'GET',
      path: '/app/my-doors',
      token: token,
    );

    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return _parsePayload(
      'Kapilar',
      () => (payload['doors'] as List<dynamic>? ?? <dynamic>[])
          .map((item) => DoorRecord.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }

  Future<SubscriptionRequestPage> listSubscriptionRequests({
    required String token,
    required int page,
    required int pageSize,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/admin/subscription-requests',
    ).replace(queryParameters: {'page': '$page', 'page_size': '$pageSize'});

    final response = await _sendRequest(
      method: 'GET',
      uri: uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    final requests = _parsePayload(
      'Abonelik talepleri',
      () => (payload['requests'] as List<dynamic>? ?? <dynamic>[])
          .map(
            (item) => SubscriptionRequest.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
    );

    return SubscriptionRequestPage(
      requests: requests,
      total: payload['total'] as int? ?? 0,
      page: payload['page'] as int? ?? page,
      pageSize: payload['page_size'] as int? ?? pageSize,
    );
  }

  Future<void> resolveSubscriptionRequest({
    required String token,
    required int userCode,
    required String action,
  }) async {
    final response = await _authorizedRequest(
      method: 'PATCH',
      path: '/admin/subscription-requests/$userCode',
      token: token,
      body: {'action': action},
    );

    _ensureStatus(response, 200);
  }

  Future<UserSession> updateMyProfile({
    required String token,
    required int id,
    required UserRole role,
    required bool isActive,
    String? fullName,
    String? email,
    String? password,
    String? currentPassword,
    String? phoneNumber,
  }) async {
    final body = <String, dynamic>{
      'full_name': fullName,
      'email': email,
      'password': password,
      // C8: şifre değişiyorsa mevcut şifre sunucuya zorunlu olarak iletilir.
      if (password != null) 'current_password': currentPassword,
      'phone_number': phoneNumber,
    }..removeWhere((_, value) => value == null);

    final response = await _authorizedRequest(
      method: 'PATCH',
      path: '/me',
      token: token,
      body: body,
    );

    // Yanlış mevcut şifre sunucuda 400 CURRENT_PASSWORD_INVALID döner (oturumu kapatmaz). Bu uçta
    // 401 yalnızca gerçek oturum sorunudur (token iptal/süre dolumu/silinmiş kullanıcı) ve
    // SessionExpiredException olarak oturumu sonlandırır.
    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return _parsePayload('Profil bilgisi', () {
      final user = payload['user'] as Map<String, dynamic>;
      // Şifre değişiminde sunucu yeni bir token döndürürse (parola sürümü claim'i) onu kullan.
      final newToken = payload['token'];
      return _toUserSession(
        user: user,
        token: newToken is String && newToken.isNotEmpty ? newToken : token,
        fallbackId: id,
        fallbackRole: role,
        fallbackIsActive: isActive,
      );
    });
  }

  /// GET /me: sunucudaki güncel kullanıcı kaydı (rol/aktiflik için tek doğruluk kaynağı, C11).
  /// 401 -> [SessionExpiredException]; 403 (pasif/onaysız hesap) -> [ApiException] (statusCode 403).
  Future<UserSession> fetchMe({
    required String token,
    required UserSession current,
  }) async {
    final response = await _authorizedRequest(
      method: 'GET',
      path: '/me',
      token: token,
    );
    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return _parsePayload('Profil bilgisi', () {
      final user = payload['user'] as Map<String, dynamic>;
      return _toUserSession(
        user: user,
        token: token,
        fallbackId: current.id,
        fallbackRole: current.role,
        fallbackIsActive: current.isActive,
      );
    });
  }

  Future<UserSession> _authRequest({
    required String path,
    required Map<String, dynamic> body,
    required int expectedCode,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final response = await _sendRequest(
      method: 'POST',
      uri: uri,
      headers: const {'Content-Type': 'application/json'},
      body: body,
    );

    _ensureStatus(response, expectedCode, unauthorizedIsSession: false);
    final payload = _decodePayload(response);
    return _parsePayload('Oturum bilgisi', () {
      final user = payload['user'] as Map<String, dynamic>;
      return _toUserSession(
        user: user,
        token: payload['token'] as String,
        fallbackId: user['id'] as int,
        fallbackRole: UserRole.fromApi(user['role'] as String),
        fallbackIsActive: user['is_active'] as bool? ?? true,
      );
    });
  }

  Future<http.Response> _authorizedRequest({
    required String method,
    required String path,
    required String token,
    Map<String, dynamic>? body,
    Duration? timeout,
    String? timeoutMessage,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };

    switch (method) {
      case 'GET':
      case 'DELETE':
        return _sendRequest(
          method: method,
          uri: uri,
          headers: headers,
          timeout: timeout,
          timeoutMessage: timeoutMessage,
        );
      case 'PATCH':
      case 'PUT':
      case 'POST':
        return _sendRequest(
          method: method,
          uri: uri,
          headers: headers,
          body: body,
          timeout: timeout,
          timeoutMessage: timeoutMessage,
        );
      default:
        throw ArgumentError('Desteklenmeyen method: $method');
    }
  }

  /// Ağ isteği gönderir. Otomatik yeniden deneme YALNIZCA GET isteklerinde yapılır;
  /// mutasyonlar (POST/PATCH/PUT/DELETE) çift işlem riskine karşı asla tekrar edilmez.
  Future<http.Response> _sendRequest({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    Map<String, dynamic>? body,
    Duration? timeout,
    String? timeoutMessage,
    bool retryOnTransportError = true,
  }) async {
    Future<http.Response> execute() {
      switch (method) {
        case 'GET':
          return _client.get(uri, headers: headers);
        case 'DELETE':
          return _client.delete(uri, headers: headers);
        case 'PATCH':
          return _client.patch(
            uri,
            headers: headers,
            body: jsonEncode(body ?? <String, dynamic>{}),
          );
        case 'PUT':
          return _client.put(
            uri,
            headers: headers,
            body: jsonEncode(body ?? <String, dynamic>{}),
          );
        case 'POST':
          return _client.post(
            uri,
            headers: headers,
            body: jsonEncode(body ?? <String, dynamic>{}),
          );
        default:
          throw ArgumentError('Desteklenmeyen method: $method');
      }
    }

    final isIdempotentRead = method == 'GET';
    final canRetry = retryOnTransportError && isIdempotentRead;

    final http.Response response;
    try {
      response = await execute().timeout(
        timeout ?? (isIdempotentRead ? _readTimeout : _requestTimeout),
      );
    } on TimeoutException {
      // Okuma zaman aşımında yeniden DENENMEZ: ikinci bekleme kullanıcının bekleme süresini
      // iki katına çıkarırdı (20 sn -> 40 sn); mesaj zaten elle yeniden denemeyi önerir.
      // Hızlı aktarım hataları (ClientException) için tek yeniden deneme aşağıda korunur.
      throw ApiException(
        timeoutMessage ??
            (isIdempotentRead
                ? 'Sunucu yanıt vermedi, tekrar deneyin.'
                : 'Sunucu zaman aşımına uğradı. İşlem tamamlanmış olabilir; durumu kontrol edip tekrar deneyin.'),
      );
    } on http.ClientException catch (error) {
      if (canRetry) {
        await Future<void>.delayed(_retryDelay);
        return _sendRequest(
          method: method,
          uri: uri,
          headers: headers,
          body: body,
          timeout: timeout,
          timeoutMessage: timeoutMessage,
          retryOnTransportError: false,
        );
      }
      throw ApiException(_mapClientError(error));
    }

    await _decodeLargeBodyInBackground(response);
    return response;
  }

  /// [_decodePayload] için gövdesi büyük (>= [BackgroundWork.jsonIsolateThresholdBytes]) yanıtların
  /// JSON'u arka plan izolesinde çözülür: yüzlerce KB'lık yanıtta (site yapısı, sakin ağacı, günlük
  /// sayfaları) ana izolede `jsonDecode` kare bütçesini aşabilir. Küçük gövdeler ana izolede kalır.
  /// Çözülen harita yanıt nesnesine bağlanır ([_decodePayload] eşzamanlı çağrılarının imzası ve
  /// hata eşlemesi değişmez); çözülemezse bağlanmaz ve eski eşzamanlı yol aynı hatayı üretir.
  final Expando<Map<String, dynamic>> _offloadedPayloads =
      Expando<Map<String, dynamic>>('AuthApi.offloadedPayloads');

  Future<void> _decodeLargeBodyInBackground(http.Response response) async {
    if (response.bodyBytes.length < BackgroundWork.jsonIsolateThresholdBytes) {
      return;
    }
    try {
      // Sunucu UTF-8 JSON döndürür: baytlar doğrudan arka plana gider (bayt -> metin çevrimi de
      // orada yapılır). Başka bir karakter kodlaması bildirilirse http paketinin çözümlemesi
      // (response.body) korunur ve metin gönderilir.
      final Object? raw = _isUtf8Json(response)
          ? await BackgroundWork.run<Uint8List, Object?>(
              decodeJsonUtf8Bytes,
              response.bodyBytes,
              debugLabel: 'authApi.jsonDecode',
            )
          : await BackgroundWork.run<String, Object?>(
              decodeJsonText,
              response.body,
              debugLabel: 'authApi.jsonDecode',
            );
      _offloadedPayloads[response] =
          raw is Map<String, dynamic> ? raw : <String, dynamic>{};
    } catch (_) {
      // Geçersiz JSON / gönderilemeyen hata: _decodePayload eşzamanlı çözümleyip eski hata
      // eşlemesini (ApiException) uygular.
    }
  }

  static final RegExp _charsetPattern = RegExp(r'charset\s*=\s*"?([^";\s]+)');

  /// Yanıt UTF-8 JSON mu? (`charset=utf-8` ya da charset'siz `application/json` — http paketinin
  /// [http.Response.body] için kullandığı kodlama kuralıyla aynı.)
  static bool _isUtf8Json(http.Response response) {
    final type = (response.headers['content-type'] ?? '').toLowerCase();
    final charset = _charsetPattern.firstMatch(type)?.group(1);
    if (charset != null) {
      return charset == 'utf-8' || charset == 'utf8';
    }
    return type.startsWith('application/json');
  }

  /// Beklenen durum kodu dışındaki yanıtları [ApiException]'a çevirir.
  /// 401 tespiti hata metnine değil durum koduna dayanır: [unauthorizedIsSession] true iken
  /// (yetkili istekler) [SessionExpiredException] fırlatılır; giriş/profil gibi kimlik
  /// bilgisi doğrulayan uçlarda false verilir ve sunucu mesajı gösterilir.
  void _ensureStatus(
    http.Response response,
    int expectedCode, {
    bool allowEmptyBody = false,
    bool unauthorizedIsSession = true,
  }) {
    final status = response.statusCode;
    if (status == expectedCode) {
      return;
    }

    // Boş gövde yalnızca başarılı (2xx) yanıtlarda kabul edilir; hata durumları yutulmaz.
    if (allowEmptyBody &&
        status >= 200 &&
        status < 300 &&
        response.body.trim().isEmpty) {
      return;
    }

    // Sunucu 401/403'ü her zaman JSON hata zarfıyla döndürür; JSON olmayan (HTML/düz metin) gövde
    // araya giren bir katmandır (proxy/WAF/captive portal): oturum sonu DEĞİL, geçici ağ hatasıdır.
    final intermediary = _intermediaryAuthError(response);
    if (intermediary != null) {
      throw intermediary;
    }

    if (status == 401 && unauthorizedIsSession) {
      final code = _readErrorCode(response);
      if (code == 'TOKEN_REVOKED') {
        // Parola değişince eski token'lar iptal edilir (pv claim'i).
        throw SessionExpiredException(
          'Şifreniz değiştirildiği için oturumunuz sonlandırıldı. Lütfen yeniden giriş yapın.',
          code,
        );
      }
      throw SessionExpiredException(
        'Oturum süreniz doldu. Lütfen tekrar giriş yapın.',
        code,
      );
    }

    final payload = _decodePayload(response);
    final rawError = payload['error'];
    final errorMsg = rawError is String && rawError.trim().isNotEmpty
        ? sanitizeServerMessage(rawError.trim())
        : null;
    final rawCode = payload['code'];
    final code = rawCode is String && rawCode.trim().isNotEmpty
        ? rawCode.trim()
        : null;
    final retryAfter = _retryAfterSeconds(response, payload);

    if (status == 401) {
      // Buraya yalnızca kimlik bilgisi doğrulayan uçlar düşer (hatalı şifre vb.): oturum bozulmaz.
      throw ApiException(
        messageForErrorCode(code, retryAfterSeconds: retryAfter, payload: payload) ??
            errorMsg ??
            'Yetkisiz erişim (401)',
        statusCode: 401,
        code: code,
        retryAfterSeconds: retryAfter,
        invalidatesSession: false,
      );
    }

    final mappedMessage =
        messageForErrorCode(code, retryAfterSeconds: retryAfter, payload: payload);
    var message = mappedMessage ??
        errorMsg ??
        genericMessageForStatus(status, code: code) ??
        'İşlem başarısız ($status)';

    if (status == 429 && mappedMessage == null) {
      // Genel hız sınırı: bekleme süresini kullanıcıya göster (kapı açma dahil).
      message = _withRetryHint(message, retryAfter);
    }

    if (status >= 500) {
      // Sunucu 5xx yanıtlarında destek için hata kodunu (errorId) göster.
      final errorId = payload['errorId'] ?? payload['error_id'];
      if (errorId is String && errorId.isNotEmpty) {
        message = '$message (Hata kodu: $errorId)';
      }
    }
    throw ApiException(
      message,
      statusCode: status,
      code: code,
      retryAfterSeconds: retryAfter,
      payload: payload,
    );
  }

  /// 401/403 yanıtının gövdesi sunucunun JSON hata zarfı değilse (boş olmayan HTML/düz metin) geçici
  /// ağ/proxy hatası döndürür ([ApiException.fromIntermediary]: oturumu SONLANDIRMAZ ve "hesap pasif"
  /// doğrulamasını tetiklemez). Boş gövde bu sınıfa girmez (mevcut davranış: sunucu yanıtı sayılır).
  ApiException? _intermediaryAuthError(http.Response response) {
    final status = response.statusCode;
    if (status != 401 && status != 403) {
      return null;
    }
    final body = response.body.trim();
    if (body.isEmpty) {
      return null;
    }
    try {
      if (jsonDecode(body) is Map<String, dynamic>) {
        return null;
      }
    } on FormatException {
      // JSON değil: aşağıda ara katman hatası olarak döner.
    }
    return ApiException(
      'Sunucuya ulaşılamadı. Ağ bağlantınızı (güvenlik duvarı/proxy) kontrol edip tekrar deneyin.',
      statusCode: status,
      fromIntermediary: true,
    );
  }

  /// Hata gövdesindeki `code` alanını (varsa) sessizce okur; gövde JSON değilse null.
  String? _readErrorCode(http.Response response) {
    if (response.body.trim().isEmpty) return null;
    try {
      final raw = jsonDecode(response.body);
      if (raw is Map<String, dynamic>) {
        final code = raw['code'];
        if (code is String && code.trim().isNotEmpty) return code.trim();
      }
    } on FormatException {
      // JSON olmayan gövde: kod yok.
    }
    return null;
  }

  /// Bekleme süresi: önce gövdedeki `retry_after_seconds`, yoksa `Retry-After` başlığı (saniye).
  int? _retryAfterSeconds(http.Response response, Map<String, dynamic> payload) {
    final body = payload['retry_after_seconds'] ?? payload['retryAfterSeconds'];
    if (body is num && body.isFinite && body > 0) {
      return body.ceil();
    }
    if (body is String) {
      final parsed = int.tryParse(body.trim());
      if (parsed != null && parsed > 0) return parsed;
    }
    final header = response.headers['retry-after'];
    if (header != null) {
      final parsed = int.tryParse(header.trim());
      if (parsed != null && parsed > 0) return parsed;
    }
    return null;
  }

  /// Saniyeyi "45 saniye" / "5 dakika" / "2 saat" biçiminde yazar (yukarı yuvarlar).
  static String formatWait(int seconds) {
    if (seconds < 60) return '$seconds saniye';
    final minutes = (seconds / 60).ceil();
    if (minutes < 60) return '$minutes dakika';
    final hours = (minutes / 60).ceil();
    return '$hours saat';
  }

  String _withRetryHint(String base, int? retryAfter) {
    if (retryAfter == null) return base;
    if (base.toLowerCase().contains('sonra')) return base;
    final trimmed = base.endsWith('.') ? base : '$base.';
    return '$trimmed Lütfen ${formatWait(retryAfter)} sonra tekrar deneyin.';
  }

  /// Sunucu hata metninde alan adı jargonu (`gross_area_m2`, `YYYY-AA-GG` gibi) varsa kullanıcıya
  /// gösterilmez; yerine [jargonFallbackMessage] gelir. Temiz metin olduğu gibi döner.
  static String? sanitizeServerMessage(String? message) {
    if (message == null) return null;
    final jargon = RegExp(r'[a-z][a-z0-9]*(?:_[a-z0-9]+)+').hasMatch(message) ||
        message.contains('YYYY-AA-GG') ||
        message.contains('YYYY-MM-DD');
    return jargon ? jargonFallbackMessage : message;
  }

  /// Jargonlu sunucu metni yerine gösterilen genel Türkçe mesaj.
  static const String jargonFallbackMessage =
      'Girilen bilgilerde hata var. Alanları kontrol edip tekrar deneyin.';

  /// Sunucu `error` metni göndermediğinde durum koduna / genel koda göre Türkçe yedek mesaj
  /// (429 hız sınırı: gövdede `code` yoktur; 400 `INVALID_BODY` / `INVALID_QUERY`). Metin gelirse
  /// sunucunun kendi mesajı önceliklidir; bilinmiyorsa null.
  static String? genericMessageForStatus(int status, {String? code}) {
    if (status == 429) return 'Çok fazla istek gönderildi.';
    switch (code) {
      case 'INVALID_BODY':
        return 'Gönderilen bilgiler geçersiz. Alanları kontrol edip tekrar deneyin.';
      case 'INVALID_QUERY':
        return 'Geçersiz sorgu. Süzgeçleri kontrol edip tekrar deneyin.';
      // Kişi ve Daire Kayıtları (Faz 2a): sunucu `error` metni göndermezse genel Türkçe yedek mesajlar
      // (metin gelirse sunucunun kendi mesajı önceliklidir).
      case 'PERSON_NOT_FOUND':
        return 'Kişi bulunamadı.';
      case 'VEHICLE_NOT_FOUND':
        return 'Araç bulunamadı.';
      case 'RESIDENCY_NOT_FOUND':
        return 'İlişki kaydı bulunamadı.';
      case 'RESIDENCY_NOT_CURRENT':
        return 'Bu ilişki artık güncel değil.';
      case 'RESIDENCY_EXISTS':
        return 'Kişi bu dairede zaten kayıtlı.';
      case 'SITE_NOT_FOUND':
      case 'INVALID_SITE_CODE':
        return 'Site bulunamadı.';
    }
    return null;
  }

  /// Bilinen sunucu hata kodları için anlaşılır (kısa, taşmayan) Türkçe metin;
  /// bilinmiyorsa null döner ve sunucunun `error` metni kullanılır.
  /// [payload]: GEOFENCE_OUT_OF_RANGE için `distance_meters` / `allowed_radius_meters`.
  static String? messageForErrorCode(
    String? code, {
    int? retryAfterSeconds,
    Map<String, dynamic>? payload,
  }) {
    if (code == null) return null;
    final wait = retryAfterSeconds != null
        ? ' ${formatWait(retryAfterSeconds)} sonra tekrar deneyin.'
        : ' Lütfen daha sonra tekrar deneyin.';

    int? meters(Object? value) {
      if (value is num && value.isFinite && value >= 0) return value.round();
      if (value is String) {
        final parsed = double.tryParse(value.trim());
        if (parsed != null && parsed.isFinite && parsed >= 0) return parsed.round();
      }
      return null;
    }

    switch (code) {
      // --- Hesap / kimlik doğrulama
      case 'CURRENT_PASSWORD_REQUIRED':
        return 'Şifrenizi değiştirmek için mevcut şifrenizi girmelisiniz.';
      case 'CURRENT_PASSWORD_INVALID':
        return 'Mevcut şifreniz hatalı. Lütfen kontrol edip tekrar deneyin.';
      case 'CURRENT_PASSWORD_LOCKED':
        return 'Mevcut şifre için çok fazla hatalı deneme yapıldı.$wait';
      case 'LOGIN_LOCKED':
        return 'Çok fazla hatalı deneme yapıldı.$wait';
      case 'USE_PROFILE_PASSWORD_CHANGE':
        // PATCH /admin/users/:id kendi hesabında parola gelirse 400 döner (mevcut şifre doğrulaması yok).
        return 'Kendi şifrenizi Profilim ekranından değiştirin.';

      // --- Konum doğrulaması (C3)
      case 'GEOFENCE_LOCATION_REQUIRED':
        return 'Bu kapı için konum doğrulaması zorunludur. Konum servisini açıp tekrar deneyin.';
      case 'GEOFENCE_LOCATION_INVALID':
        return 'Konum bilgisi geçersiz. GPS\'i kontrol edip tekrar deneyin.';
      case 'GEOFENCE_MOCK_LOCATION':
        return 'Sahte konum (Mock Location) tespit edildi. Güvenlik nedeniyle işlem yapılamaz.';
      case 'GEOFENCE_LOCATION_STALE':
        return 'Konum bilginiz güncel değil. GPS sinyalinin yenilenmesini bekleyip tekrar deneyin.';
      case 'GEOFENCE_LOCATION_INACCURATE':
        return 'GPS doğruluğu yetersiz. Açık alana çıkıp tekrar deneyin.';
      case 'GEOFENCE_OUT_OF_RANGE':
        final distance = meters(payload?['distance_meters']);
        final allowed = meters(payload?['allowed_radius_meters']);
        if (distance != null && allowed != null) {
          return '$distance m uzaktasınız, izin verilen mesafe $allowed m. Lütfen kapıya yaklaşın.';
        }
        return 'Kapı konumunda değilsiniz. Lütfen kapıya yaklaşın.';
      case 'GEOFENCE_SITE_MISCONFIGURED':
        return 'Bu sitenin konum çemberi hatalı tanımlanmış. Lütfen site yöneticinize başvurun.';

      // --- Kapı açma politikası (C2)
      case 'REMOTE_OPEN_DISABLED':
        return 'Bu sitede uygulamadan uzaktan kapı açma kapalı.';
      case 'QR_DISABLED':
        return 'Bu sitede QR ile giriş kapalı.';
      case 'QR_ENTRY_INACTIVE':
        return 'Bu kapıda QR ile giriş şu an devre dışı.';
      case 'GUEST_DISABLED':
        return 'Bu sitede misafir geçişi kapalı.';
      case 'LOCAL_DISABLED':
        return 'Bu sitede yerel ağdan kapı açma kapalı.';

      // --- Karekod
      case 'DYNAMIC_QR_REQUIRED':
        return 'Bu kapıda dinamik karekod geçerlidir. Lütfen kapı ekranındaki güncel karekodu okutun.';
      case 'SCREEN_QR_ALREADY_USED':
        return 'Bu karekod daha önce kullanıldı. Ekranda yenilenen güncel karekodu okutun.';
      case 'SCREEN_QR_EXPIRED':
        return 'Karekodun süresi doldu. Ekranda yenilenen güncel karekodu okutun.';
      case 'EKRAN_QR_BEKLENIYOR':
        return 'Kapı ekranındaki karekod henüz alınamadı. Birkaç saniye sonra tekrar deneyin.';
      case 'INVALID_QR_PAYLOAD':
        return 'Okutulan karekod geçersiz.';

      // --- Kapı / cihaz
      case 'INVALID_DOOR_ID':
        return 'Geçersiz kapı bilgisi.';
      case 'DOOR_NOT_FOUND':
        return 'Kapı bulunamadı.';
      case 'DOOR_ACCESS_DENIED':
        return 'Bu kapıyı açma yetkiniz yok.';
      case 'MQTT_BRIDGE_NOT_CONNECTED':
        return 'Sunucunun cihaz bağlantısı şu an hazır değil. Lütfen biraz sonra tekrar deneyin.';
      case 'DEVICE_OFFLINE':
        return 'Cihaz şu an çevrimdışı. Cihazın internet bağlantısını kontrol edin.';
      case 'DEVICE_NOT_ASSIGNABLE':
        return 'Bu cihaz bu kapıya atanamaz.';
      case 'DEVICE_OWNED_BY_ANOTHER':
        return 'Bu cihaz başka bir hesaba ait.';
      case 'DEVICE_DEFECTIVE':
        return 'Bu cihaz arızalı olarak işaretlenmiş.';
      case 'DEVICE_NOT_FOUND':
        return 'Cihaz bulunamadı.';

      // --- Platform modül sistemi (Faz 1). MODULE_CONFIRM_REQUIRED bilerek yok: sunucunun kendi
      // metni ("Geçiş Kontrol kapatılırsa ... Onaylıyor musunuz?") kullanılır.
      case 'MODULE_DISABLED':
        return 'Bu özellik şu an kapalı. Site yöneticisi Modüller ekranından açabilir.';
      case 'MODULE_COMING_SOON':
        return 'Bu modül yakında.';
      case 'MODULE_NOT_TOGGLEABLE':
        return 'Bu modül kapatılamaz.';
      case 'MODULE_NOT_FOUND':
        return 'Modül bulunamadı.';
      case 'MANAGEMENT_TYPE_COMING_SOON':
        return 'Bu yönetim türü yakında.';
      case 'MANAGEMENT_TYPE_INVALID':
        return 'Geçersiz yönetim türü.';
      case 'USER_NOT_FOUND':
        return 'Bu e-posta ile kayıtlı hesap yok.';
      case 'USER_NOT_ACTIVE':
        return 'Bu hesap henüz etkin değil.';
      case 'ALREADY_SITE_MANAGER':
        return 'Bu kişi zaten site yöneticisi.';
      case 'ROLE_INVALID':
        return 'Geçersiz rol.';
      case 'ROLE_NOT_FOUND':
        return 'Bu kişide kurul veya görevli rolü yok.';
      // Modül talebi (Faz 1.1).
      case 'MODULE_ADMIN_ONLY':
        return 'Modülleri yalnızca sistem yöneticisi açıp kapatabilir. Modül talebi gönderebilirsiniz.';
      case 'MODULE_ALREADY_ENABLED':
        return 'Bu modül zaten açık.';
      case 'MODULE_REQUEST_PENDING':
        return 'Bu modül için bekleyen bir talebiniz var.';
      case 'REQUEST_NOT_FOUND':
        return 'Talep bulunamadı.';
      case 'REQUEST_NOT_PENDING':
        return 'Bu talep artık bekleyen durumda değil.';
      // Kişi ve Daire Kayıtları (Faz 2a).
      case 'PERSON_EXISTS':
        return 'Bu e-posta ile kayıtlı bir kişi zaten var.';
      case 'PERSON_HAS_ACCOUNT':
        return 'Hesabı olan kişinin bilgileri kişinin kendi profilinden değişir.';
      case 'RELATION_TAKEN':
        return 'Bu dairede bu ilişki için aktif bir kişi zaten var.';
      case 'APARTMENT_NOT_FOUND':
        return 'Daire bulunamadı.';
      case 'PLATE_INVALID':
        return 'Plaka biçimi geçersiz.';
      case 'PLATE_EXISTS':
        return 'Bu plaka bu sitede zaten kayıtlı.';
      case 'FORBIDDEN_ROLE':
        return 'Bu işlem için yetkiniz yok.';
      // Duyuru ve Bildirim (Faz 3a). INVALID_BODY için sunucunun Türkçe etiketli metni kullanılır.
      case 'ANNOUNCEMENT_NOT_FOUND':
        return 'Duyuru bulunamadı ya da artık yayında değil.';
      case 'INVALID_STATE':
        return 'Duyurunun durumu değişmiş. Listeyi yenileyip tekrar deneyin.';
      case 'NO_RECIPIENTS':
        return 'Seçilen hedefte duyuruyu alacak kimse yok. Hedefi değiştirin.';
      case 'INVALID_TARGET':
        return 'Seçilen blok veya daireler bu siteye ait değil. Hedefi yeniden seçin.';
      case 'INVALID_SCHEDULE':
        return 'Yayın zamanı geçersiz. En az 1 dakika, en çok 1 yıl sonrası seçin.';
      case 'ANNOUNCEMENT_EMAIL_LIMIT':
        return 'Tek seferde en çok 1000 kişiye e-posta gönderilebilir. Hedefi bölüp ayrı duyurular oluşturun.';
      default:
        return null;
    }
  }

  Map<String, dynamic> _decodePayload(http.Response response) {
    final offloaded = _offloadedPayloads[response];
    if (offloaded != null) {
      return offloaded;
    }
    if (response.body.trim().isEmpty) {
      return <String, dynamic>{};
    }

    try {
      final raw = jsonDecode(response.body);
      return raw is Map<String, dynamic> ? raw : <String, dynamic>{};
    } on FormatException {
      final status = response.statusCode;
      // 5xx (502/503/504 dahil) "modem" sezgisinden ÖNCE sınıflandırılır: gateway/proxy
      // sayfaları 'gateway' gibi kelimeler içerir ama sorun kullanıcının internetinde değildir.
      if (status >= 500) {
        throw ApiException(_serverUnavailableMessage(status), statusCode: status);
      }
      // Proxy (nginx) tarafından üretilen JSON olmayan 413/429 yanıtları da sınıflandırılır.
      if (status == 413) {
        throw ApiException(
          'Gönderilen veri çok büyük (413). Lütfen daha küçük bir veri ile tekrar deneyin.',
          statusCode: status,
        );
      }
      if (status == 429) {
        final retryAfter = _retryAfterSeconds(response, const <String, dynamic>{});
        throw ApiException(
          _withRetryHint('Çok fazla istek gönderildi.', retryAfter),
          statusCode: status,
          retryAfterSeconds: retryAfter,
        );
      }
      final bodyLower = response.body.toLowerCase();
      if (bodyLower.contains('<html') ||
          bodyLower.contains('<!doctype') ||
          bodyLower.contains('router') ||
          bodyLower.contains('modem') ||
          bodyLower.contains('gateway')) {
        throw ApiException(
          'İnternet bağlantısı yok (Modem internete bağlı değil).',
          statusCode: status,
          fromIntermediary: true,
        );
      }
      throw ApiException(
        'Sunucuya ulaşılamadı. İnternet bağlantınızı kontrol edin.',
        statusCode: status,
        fromIntermediary: true,
      );
    }
  }

  String _serverUnavailableMessage(int status) {
    if (status == 502 || status == 503 || status == 504) {
      return 'Sunucu geçici olarak yanıt vermiyor ($status). Lütfen biraz sonra tekrar deneyin.';
    }
    return 'Sunucuda beklenmeyen bir hata oluştu ($status). Lütfen biraz sonra tekrar deneyin.';
  }

  String _mapClientError(http.ClientException error) {
    final message = error.message.toLowerCase();
    if (message.contains('certificate') ||
        message.contains('handshake') ||
        message.contains('tls')) {
      return 'SSL baglantisi kurulurken hata olustu.';
    }
    if (message.contains('connection closed') ||
        message.contains('connection reset') ||
        message.contains('failed host lookup') ||
        message.contains('socket')) {
      return 'Sunucuya ulasilamadi. Internet veya DNS baglantisini kontrol edin.';
    }
    return 'Sunucu baglantisinda istemci hatasi olustu.';
  }

  T _parsePayload<T>(String label, T Function() parser) {
    try {
      return parser();
    } on FormatException {
      throw ApiException('$label verisi islenemedi.');
    } on TypeError {
      throw ApiException('$label verisi beklenen formatta degil.');
    }
  }

  Future<GuestPassRecord> createGuestPass({
    required String token,
    required int doorId,
    required String title,
    required String passType,
    int? durationMinutes,
    int? maxUses,
  }) async {
    final response = await _authorizedRequest(
      method: 'POST',
      path: '/app/guest-passes',
      token: token,
      body: {
        'door_id': doorId,
        'title': title,
        'pass_type': passType,
        'duration_minutes': durationMinutes,
        'max_uses': maxUses,
      },
    );

    _ensureStatus(response, 201);
    final payload = _decodePayload(response);
    return _parsePayload(
      'Gecis kaydi',
      () => GuestPassRecord.fromJson(
        payload['guest_pass'] as Map<String, dynamic>,
      ),
    );
  }

  Future<List<GuestPassRecord>> listGuestPasses({
    required String token,
  }) async {
    final response = await _authorizedRequest(
      method: 'GET',
      path: '/app/guest-passes',
      token: token,
    );

    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return _parsePayload(
      'Gecisler',
      () => (payload['passes'] as List<dynamic>? ?? <dynamic>[])
          .map(
            (item) => GuestPassRecord.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
    );
  }

  Future<void> revokeGuestPass({
    required String token,
    required int passId,
  }) async {
    final response = await _authorizedRequest(
      method: 'DELETE',
      path: '/app/guest-passes/$passId',
      token: token,
    );

    _ensureStatus(response, 200);
  }

  Future<Map<String, dynamic>> claimDevice({
    required String token,
    required String deviceInput,
  }) async {
    final response = await _authorizedRequest(
      method: 'POST',
      path: '/membership/claim-device',
      token: token,
      body: {
        'deviceInput': deviceInput,
      },
    );

    _ensureStatus(response, 200);
    return _decodePayload(response);
  }

  Future<List<Map<String, dynamic>>> getMyClaimedDevices({
    required String token,
  }) async {
    final response = await _authorizedRequest(
      method: 'GET',
      path: '/membership/my-devices',
      token: token,
    );

    _ensureStatus(response, 200);
    final data = _decodePayload(response);
    final list = data['devices'] as List<dynamic>? ?? [];
    return list.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  Future<Map<String, dynamic>> setupSite({
    required String token,
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
    final response = await _authorizedRequest(
      method: 'POST',
      path: '/membership/setup-site',
      token: token,
      body: {
        'name': name,
        if (city != null && city.isNotEmpty) 'city': city,
        if (district != null && district.isNotEmpty) 'district': district,
        if (address != null && address.isNotEmpty) 'address': address,
        'blocks': blocks,
        if (doors != null && doors.isNotEmpty) 'doors': doors,
        'doorCount': doors != null && doors.isNotEmpty ? doors.length : doorCount,
        if (deviceUid != null && deviceUid.isNotEmpty) 'deviceUid': deviceUid,
        // Yönetim türü (Faz 1: yalnız apartment_site); verilmezse alan hiç gönderilmez.
        if (managementType != null && managementType.isNotEmpty)
          'management_type': managementType,
      },
    );

    _ensureStatus(response, 201);
    return _decodePayload(response);
  }

  Future<Map<String, dynamic>> createDoor({
    required String token,
    required int siteCode,
    required String doorName,
    String accessScope = 'SITE_COMMON',
    int? blockId,
    String? deviceUid,
  }) async {
    final response = await _authorizedRequest(
      method: 'POST',
      path: '/manager/sites/$siteCode/doors',
      token: token,
      body: {
        'door_name': doorName,
        'access_scope': accessScope,
        'block_id': ?blockId,
        if (deviceUid != null && deviceUid.isNotEmpty) 'device_uid': deviceUid,
      },
    );
    _ensureStatus(response, 201);
    return _decodePayload(response);
  }

  Future<Map<String, dynamic>> updateDoor({
    required String token,
    required int doorId,
    String? doorName,
    String? accessScope,
    int? blockId,
    bool? isActive,
  }) async {
    final body = <String, dynamic>{};
    if (doorName != null) body['door_name'] = doorName;
    if (accessScope != null) body['access_scope'] = accessScope;
    if (blockId != null) body['block_id'] = blockId;
    if (isActive != null) body['is_active'] = isActive;

    final response = await _authorizedRequest(
      method: 'PUT',
      path: '/manager/doors/$doorId',
      token: token,
      body: body,
    );
    _ensureStatus(response, 200);
    return _decodePayload(response);
  }

  Future<void> deleteDoor({
    required String token,
    required int doorId,
  }) async {
    final response = await _authorizedRequest(
      method: 'DELETE',
      path: '/manager/doors/$doorId',
      token: token,
    );
    _ensureStatus(response, 200);
  }

  Future<Map<String, dynamic>> unassignDoorDevice({
    required String token,
    required int doorId,
  }) async {
    final response = await _authorizedRequest(
      method: 'POST',
      path: '/manager/doors/$doorId/unassign-device',
      token: token,
    );
    _ensureStatus(response, 200);
    return _decodePayload(response);
  }

  Future<Map<String, dynamic>> replaceDoorDevice({
    required String token,
    required int doorId,
    String? deviceInput,
    int? deviceId,
  }) async {
    final response = await _authorizedRequest(
      method: 'POST',
      path: '/manager/doors/$doorId/replace-device',
      token: token,
      body: {
        if (deviceInput != null && deviceInput.trim().isNotEmpty)
          'device_input': deviceInput.trim(),
        'device_id': ?deviceId,
      },
    );
    _ensureStatus(response, 200);
    return _decodePayload(response);
  }

  Future<List<Map<String, dynamic>>> getAssignableDevices({
    required String token,
    required int siteCode,
  }) async {
    final response = await _authorizedRequest(
      method: 'GET',
      path: '/manager/sites/$siteCode/assignable-devices',
      token: token,
    );
    _ensureStatus(response, 200);
    final data = _decodePayload(response);
    final list = data['devices'] as List<dynamic>? ?? [];
    return list.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  Future<SiteJoinTokenRecord> getSiteJoinToken({
    required String token,
    required int siteCode,
  }) async {
    final response = await _authorizedRequest(
      method: 'GET',
      path: '/manager/sites/$siteCode/join-token',
      token: token,
    );
    _ensureStatus(response, 200);
    final data = _decodePayload(response);
    return SiteJoinTokenRecord.fromJson(data['token'] as Map<String, dynamic>);
  }

  Future<SiteJoinTokenRecord> rotateSiteJoinToken({
    required String token,
    required int siteCode,
  }) async {
    final response = await _authorizedRequest(
      method: 'POST',
      path: '/manager/sites/$siteCode/join-token/rotate',
      token: token,
    );
    _ensureStatus(response, 200);
    final data = _decodePayload(response);
    return SiteJoinTokenRecord.fromJson(data['token'] as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> getSiteJoinInfo({
    required String token,
    required String joinToken,
  }) async {
    final response = await _authorizedRequest(
      method: 'GET',
      path: '/membership/join-info/${Uri.encodeComponent(joinToken)}',
      token: token,
    );
    _ensureStatus(response, 200);
    return _decodePayload(response);
  }

  Future<SiteJoinInfo> fetchSiteJoinInfo({
    required String token,
    required String joinToken,
  }) async {
    final cleanToken = joinToken.replaceFirst('SITE_JOIN:', '').trim();
    final data = await getSiteJoinInfo(token: token, joinToken: cleanToken);
    return SiteJoinInfo.fromJson(data);
  }

  Future<Map<String, dynamic>> submitJoinRequest({
    required String token,
    required String joinToken,
    int? blockId,
    required int apartmentId,
    String? notes,
  }) async {
    final response = await _authorizedRequest(
      method: 'POST',
      path: '/membership/join-request',
      token: token,
      body: {
        'token': joinToken,
        // ignore: use_null_aware_elements
        if (blockId != null) 'blockId': blockId,
        'apartmentId': apartmentId,
        if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      },
    );
    _ensureStatus(response, 201);
    return _decodePayload(response);
  }

  Future<List<JoinRequestRecord>> getMyJoinRequests({
    required String token,
  }) async {
    final response = await _authorizedRequest(
      method: 'GET',
      path: '/membership/my-join-requests',
      token: token,
    );
    _ensureStatus(response, 200);
    final data = _decodePayload(response);
    final list = data['requests'] as List<dynamic>? ?? [];
    return list.map((item) => JoinRequestRecord.fromJson(item as Map<String, dynamic>)).toList();
  }

  Future<List<JoinRequestRecord>> getSiteJoinRequests({
    required String token,
    required int siteCode,
    String? status,
  }) async {
    final query = status != null && status.isNotEmpty
        ? '?status=${Uri.encodeQueryComponent(status)}'
        : '';
    final response = await _authorizedRequest(
      method: 'GET',
      path: '/manager/sites/$siteCode/join-requests$query',
      token: token,
    );
    _ensureStatus(response, 200);
    final data = _decodePayload(response);
    final list = data['requests'] as List<dynamic>? ?? [];
    return list.map((item) => JoinRequestRecord.fromJson(item as Map<String, dynamic>)).toList();
  }

  Future<Map<String, dynamic>> approveJoinRequest({
    required String token,
    required int requestId,
  }) async {
    final response = await _authorizedRequest(
      method: 'POST',
      path: '/manager/join-requests/$requestId/approve',
      token: token,
    );
    _ensureStatus(response, 200);
    return _decodePayload(response);
  }

  Future<Map<String, dynamic>> rejectJoinRequest({
    required String token,
    required int requestId,
    String? reason,
  }) async {
    final response = await _authorizedRequest(
      method: 'POST',
      path: '/manager/join-requests/$requestId/reject',
      token: token,
      body: {
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      },
    );
    _ensureStatus(response, 200);
    return _decodePayload(response);
  }

  Future<List<MyApartmentRecord>> getMyApartments({
    required String token,
  }) async {
    final response = await _authorizedRequest(
      method: 'GET',
      path: '/membership/my-apartments',
      token: token,
    );
    _ensureStatus(response, 200);
    final data = _decodePayload(response);
    final list = data['apartments'] as List<dynamic>? ?? [];
    return list.map((item) => MyApartmentRecord.fromJson(item as Map<String, dynamic>)).toList();
  }

  Future<Map<String, dynamic>> removeApartmentMember({
    required String token,
    required int apartmentId,
    required int targetUserCode,
  }) async {
    final response = await _authorizedRequest(
      method: 'POST',
      path: '/membership/apartments/$apartmentId/members/$targetUserCode/remove',
      token: token,
    );
    _ensureStatus(response, 200);
    return _decodePayload(response);
  }

  Future<Map<String, dynamic>> getDoorPermissions({
    required String token,
    required int doorId,
  }) async {
    final response = await _authorizedRequest(
      method: 'GET',
      path: '/membership/doors/$doorId/permissions',
      token: token,
    );
    _ensureStatus(response, 200);
    return _decodePayload(response);
  }

  Future<Map<String, dynamic>> setDoorAccessOverride({
    required String token,
    required int doorId,
    required int userCode,
    bool? isAllowed,
    String? notes,
  }) async {
    final body = <String, dynamic>{
      'userCode': userCode,
      'isAllowed': isAllowed,
    };
    if (notes != null) {
      body['notes'] = notes;
    }
    final response = await _authorizedRequest(
      method: 'POST',
      path: '/membership/doors/$doorId/permissions',
      token: token,
      body: body,
    );
    _ensureStatus(response, 200);
    return _decodePayload(response);
  }

  Future<Map<String, dynamic>> setBulkDoorAccessOverride({
    required String token,
    required int doorId,
    int? blockId,
    int? apartmentId,
    List<int>? userCodes,
    bool? isAllowed,
    String? notes,
  }) async {
    final body = <String, dynamic>{
      'isAllowed': isAllowed,
    };
    if (blockId != null) body['blockId'] = blockId;
    if (apartmentId != null) body['apartmentId'] = apartmentId;
    if (userCodes != null) body['userCodes'] = userCodes;
    if (notes != null) body['notes'] = notes;

    final response = await _authorizedRequest(
      method: 'POST',
      path: '/membership/doors/$doorId/permissions/bulk',
      token: token,
      body: body,
    );
    _ensureStatus(response, 200);
    return _decodePayload(response);
  }

  Future<Map<String, dynamic>> getSiteResidentsTree({
    required String token,
    required int siteCode,
  }) async {
    final response = await _authorizedRequest(
      method: 'GET',
      path: '/membership/sites/$siteCode/residents-tree',
      token: token,
    );
    _ensureStatus(response, 200);
    return _decodePayload(response);
  }

  Future<Map<String, dynamic>> toggleApartmentMemberStatus({
    required String token,
    required int apartmentId,
    required int targetUserCode,
    required bool isActive,
  }) async {
    final response = await _authorizedRequest(
      method: 'PATCH',
      path: '/membership/apartments/$apartmentId/members/$targetUserCode/status',
      token: token,
      body: {'is_active': isActive},
    );
    _ensureStatus(response, 200);
    return _decodePayload(response);
  }

  Future<Map<String, dynamic>> deleteApartmentMember({
    required String token,
    required int apartmentId,
    required int targetUserCode,
  }) async {
    final response = await _authorizedRequest(
      method: 'DELETE',
      path: '/membership/apartments/$apartmentId/members/$targetUserCode',
      token: token,
    );
    _ensureStatus(response, 200);
    return _decodePayload(response);
  }

  /// Sunucu yalnızca kullanıcının KENDİ parolasına izin verir ve `current_password` ister.
  /// Yanıttaki yeni `token` (parola sürümü claim'i) çağıran tarafından oturuma yazılmalıdır.
  Future<Map<String, dynamic>> changeApartmentMemberPassword({
    required String token,
    required int apartmentId,
    required int targetUserCode,
    required String newPassword,
    required String currentPassword,
  }) async {
    final response = await _authorizedRequest(
      method: 'POST',
      path: '/membership/apartments/$apartmentId/members/$targetUserCode/change-password',
      token: token,
      body: {
        'new_password': newPassword,
        'current_password': currentPassword,
      },
    );
    _ensureStatus(response, 200);
    return _decodePayload(response);
  }

  Future<Map<String, dynamic>> setApartmentPrimaryAdmin({
    required String token,
    required int apartmentId,
    required int targetUserCode,
  }) async {
    final response = await _authorizedRequest(
      method: 'POST',
      path: '/membership/apartments/$apartmentId/members/$targetUserCode/set-primary-admin',
      token: token,
    );
    _ensureStatus(response, 200);
    return _decodePayload(response);
  }

  Future<SiteManagersData> getSiteManagers({
    required String token,
    required int siteCode,
  }) async {
    final response = await _authorizedRequest(
      method: 'GET',
      path: '/manager/sites/$siteCode/managers',
      token: token,
    );
    _ensureStatus(response, 200);
    final data = _decodePayload(response);
    return SiteManagersData.fromJson(data);
  }

  Future<Map<String, dynamic>> inviteSiteManager({
    required String token,
    required int siteCode,
    required String email,
    String? fullName,
  }) async {
    final response = await _authorizedRequest(
      method: 'POST',
      path: '/manager/sites/$siteCode/managers/invite',
      token: token,
      body: {
        'email': email,
        if (fullName != null && fullName.trim().isNotEmpty)
          'full_name': fullName.trim(),
      },
    );
    _ensureStatus(response, 200);
    return _decodePayload(response);
  }

  Future<Map<String, dynamic>> removeSiteManager({
    required String token,
    required int siteCode,
    required String userCode,
  }) async {
    final response = await _authorizedRequest(
      method: 'DELETE',
      path: '/manager/sites/$siteCode/managers/${Uri.encodeComponent(userCode)}',
      token: token,
    );
    _ensureStatus(response, 200);
    return _decodePayload(response);
  }

  Future<Map<String, dynamic>> revokeSiteManagerInvitation({
    required String token,
    required int siteCode,
    required int invitationId,
  }) async {
    final response = await _authorizedRequest(
      method: 'DELETE',
      path: '/manager/sites/$siteCode/invitations/$invitationId',
      token: token,
    );
    _ensureStatus(response, 200);
    return _decodePayload(response);
  }

  Future<Map<String, dynamic>> setDeviceDefectStatus({
    required String token,
    required int deviceId,
    required bool isDefective,
    String? defectiveReason,
  }) async {
    final response = await _authorizedRequest(
      method: 'PATCH',
      path: '/admin/devices/$deviceId/defect',
      token: token,
      body: {
        'is_defective': isDefective,
        if (defectiveReason != null && defectiveReason.trim().isNotEmpty)
          'defective_reason': defectiveReason.trim(),
      },
    );
    _ensureStatus(response, 200);
    return _decodePayload(response);
  }

  Future<Map<String, dynamic>> releaseDeviceOwnership({
    required String token,
    required int deviceId,
    String? reason,
  }) async {
    final response = await _authorizedRequest(
      method: 'POST',
      path: '/admin/devices/$deviceId/release-ownership',
      token: token,
      body: {
        if (reason != null && reason.trim().isNotEmpty)
          'reason': reason.trim(),
      },
    );
    _ensureStatus(response, 200);
    return _decodePayload(response);
  }

  UserSession _toUserSession({
    required Map<String, dynamic> user,
    required String token,
    required int fallbackId,
    required UserRole fallbackRole,
    required bool fallbackIsActive,
  }) {
    return UserSession(
      id: user['id'] as int? ?? fallbackId,
      fullName: user['full_name'] as String,
      email: user['email'] as String,
      loginName: user['login_name'] as String?,
      role: user['role'] == null
          ? fallbackRole
          : UserRole.fromApi(user['role'] as String),
      isActive: user['is_active'] as bool? ?? fallbackIsActive,
      token: token,
      phoneNumber: user['phone_number'] as String?,
      createdAt: user['created_at'] == null
          ? null
          : DateTime.tryParse(user['created_at'] as String),
    );
  }
}
