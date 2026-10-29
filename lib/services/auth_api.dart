import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:site_kapi_kontrol/models/announcement.dart';
import 'package:site_kapi_kontrol/models/apartment_pin_issue.dart';
import 'package:site_kapi_kontrol/models/apartment_record.dart';
import 'package:site_kapi_kontrol/models/audit_log.dart';
import 'package:site_kapi_kontrol/models/device_connectivity_log.dart';
import 'package:site_kapi_kontrol/models/device_page.dart';
import 'package:site_kapi_kontrol/models/device_record.dart';
import 'package:site_kapi_kontrol/models/door_access_log_record.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/models/door_runtime_status.dart';
import 'package:site_kapi_kontrol/models/finance.dart';
import 'package:site_kapi_kontrol/models/finance_funds.dart';
import 'package:site_kapi_kontrol/models/finance_home.dart';
import 'package:site_kapi_kontrol/models/guest_pass.dart';
import 'package:site_kapi_kontrol/models/managed_user_account.dart';
import 'package:site_kapi_kontrol/models/managed_user_page.dart';
import 'package:site_kapi_kontrol/models/manager_contact.dart';
import 'package:site_kapi_kontrol/models/management_terms.dart';
import 'package:site_kapi_kontrol/models/management_type.dart';
import 'package:site_kapi_kontrol/models/apartment_crm.dart';
import 'package:site_kapi_kontrol/models/history_item.dart';
import 'package:site_kapi_kontrol/models/legal_document.dart';
import 'package:site_kapi_kontrol/models/module_request.dart';
import 'package:site_kapi_kontrol/models/person_record.dart';
import 'package:site_kapi_kontrol/models/residency_relation.dart';
import 'package:site_kapi_kontrol/models/vehicle_record.dart';
import 'package:site_kapi_kontrol/models/platform_module.dart';
import 'package:site_kapi_kontrol/models/staff_role_record.dart';
import 'package:site_kapi_kontrol/models/team.dart';
import 'package:site_kapi_kontrol/models/site_page.dart';
import 'package:site_kapi_kontrol/models/site_record.dart';
import 'package:site_kapi_kontrol/models/site_join_token_record.dart';
import 'package:site_kapi_kontrol/models/join_request_record.dart';
import 'package:site_kapi_kontrol/models/site_application.dart';
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
import 'package:site_kapi_kontrol/services/login_device_token_store.dart';

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

  /// Giriş. [deviceToken]: önceki başarılı girişte sunucunun verdiği güvenilir cihaz belirteci; varsa gövdede
  /// `device_token` olarak gönderilir (dağıtık parola püskürtmesinde hesap sahibinin kilitlenmesini önler).
  /// [onDeviceToken]: yanıtta (yeni) bir `device_token` gelirse çağrılır; eksik / boş / metin olmayan değerde
  /// ÇAĞRILMAZ (eski sunucu uyumu).
  Future<UserSession> login({
    required String email,
    required String password,
    UserRole? role,
    String? deviceToken,
    void Function(String deviceToken)? onDeviceToken,
  }) async {
    return _authRequest(
      path: '/auth/login',
      body: {
        'email': email,
        'password': password,
        if (role != null) 'role': role.apiValue,
        if (deviceToken != null && deviceToken.isNotEmpty) 'device_token': deviceToken,
      },
      expectedCode: 200,
      onDeviceToken: onDeviceToken,
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
    List<AcceptedDocument>? acceptedDocuments,
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
        ..._acceptedDocumentsBody(acceptedDocuments),
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

  /// SMS ile giriş (063): `GET /auth/sms/status` -> sağlayıcı yapılandırıldı mı. Hata olursa kapalı sayılır.
  Future<bool> smsLoginEnabled() async {
    try {
      final response = await _sendRequest(
        method: 'GET',
        uri: Uri.parse('$baseUrl/auth/sms/status'),
        headers: const {'Content-Type': 'application/json'},
      );
      _ensureStatus(response, 200, unauthorizedIsSession: false);
      return _decodePayload(response)['enabled'] == true;
    } catch (_) {
      return false;
    }
  }

  /// `POST /auth/sms/request`: telefona 6 haneli kod gönderir (kayıtlı olsun olmasın aynı yanıt).
  Future<void> requestSmsCode({required String phone}) async {
    final response = await _sendRequest(
      method: 'POST',
      uri: Uri.parse('$baseUrl/auth/sms/request'),
      headers: const {'Content-Type': 'application/json'},
      body: {'phone': phone},
      retryOnTransportError: false,
    );
    _ensureStatus(response, 200, unauthorizedIsSession: false);
  }

  /// Sosyal giriş (076): `GET /auth/oauth/status` -> Google ve iCloud (Apple) yapılandırma durumu.
  Future<Map<String, dynamic>> oauthStatus() async {
    try {
      final response = await _sendRequest(
        method: 'GET',
        uri: Uri.parse('$baseUrl/auth/oauth/status'),
        headers: const {'Content-Type': 'application/json'},
      );
      _ensureStatus(response, 200, unauthorizedIsSession: false);
      return _decodePayload(response);
    } catch (_) {
      return const <String, dynamic>{
        'google': <String, dynamic>{'enabled': false, 'client_id': null},
        'apple': <String, dynamic>{'enabled': false, 'client_id': null},
      };
    }
  }

  /// `POST /auth/oauth/$provider` (`google` veya `apple`): sosyal sağlayıcı id_token ile kayıt veya giriş yapar.
  Future<UserSession> loginWithOAuth({
    required String provider,
    required String idToken,
    String? fullName,
    String? firstName,
    String? lastName,
    List<AcceptedDocument>? acceptedDocuments,
    String? deviceToken,
    void Function(String deviceToken)? onDeviceToken,
    // Yerel giriş nonce'u (HAM değer): sağlayıcıya bunun SHA-256 özeti verilmiştir; sunucu belirteçteki nonce talebini özetle karşılaştırır.
    String? nonce,
  }) {
    final cleanProvider = provider.trim().toLowerCase();
    return _authRequest(
      path: '/auth/oauth/$cleanProvider',
      body: {
        'id_token': idToken,
        if (nonce != null && nonce.isNotEmpty) 'nonce': nonce,
        if (fullName != null && fullName.trim().isNotEmpty) 'full_name': fullName.trim(),
        if (firstName != null && firstName.trim().isNotEmpty) 'first_name': firstName.trim(),
        if (lastName != null && lastName.trim().isNotEmpty) 'last_name': lastName.trim(),
        if (deviceToken != null && deviceToken.isNotEmpty) 'device_token': deviceToken,
        ..._acceptedDocumentsBody(acceptedDocuments),
      },
      expectedCode: 200,
      onDeviceToken: onDeviceToken,
    );
  }

  /// `POST /auth/oauth/$provider/request-code`: Google veya iCloud e-postasına 6 haneli doğrulama kodu gönderir.
  Future<Map<String, dynamic>> requestOAuthEmailCode({
    required String provider,
    required String email,
    String? fullName,
    String? firstName,
    String? lastName,
  }) async {
    final cleanProvider = provider.trim().toLowerCase();
    final response = await _sendRequest(
      method: 'POST',
      uri: Uri.parse('$baseUrl/auth/oauth/$cleanProvider/request-code'),
      headers: const {'Content-Type': 'application/json'},
      body: {
        'email': email.trim(),
        if (fullName != null && fullName.trim().isNotEmpty) 'full_name': fullName.trim(),
        if (firstName != null && firstName.trim().isNotEmpty) 'first_name': firstName.trim(),
        if (lastName != null && lastName.trim().isNotEmpty) 'last_name': lastName.trim(),
      },
      retryOnTransportError: false,
    );
    _ensureStatus(response, 200, unauthorizedIsSession: false);
    return _decodePayload(response);
  }

  /// `POST /auth/oauth/$provider/verify-code`: Google veya iCloud e-postasına gelen 6 haneli kodu onaylar.
  Future<UserSession> verifyOAuthEmailCode({
    required String provider,
    required String email,
    required String code,
    String? fullName,
    String? firstName,
    String? lastName,
    List<AcceptedDocument>? acceptedDocuments,
    String? deviceToken,
    void Function(String deviceToken)? onDeviceToken,
  }) {
    final cleanProvider = provider.trim().toLowerCase();
    return _authRequest(
      path: '/auth/oauth/$cleanProvider/verify-code',
      body: {
        'email': email.trim(),
        'code': code.trim(),
        if (fullName != null && fullName.trim().isNotEmpty) 'full_name': fullName.trim(),
        if (firstName != null && firstName.trim().isNotEmpty) 'first_name': firstName.trim(),
        if (lastName != null && lastName.trim().isNotEmpty) 'last_name': lastName.trim(),
        if (deviceToken != null && deviceToken.isNotEmpty) 'device_token': deviceToken,
        ..._acceptedDocumentsBody(acceptedDocuments),
      },
      expectedCode: 200,
      onDeviceToken: onDeviceToken,
    );
  }

  /// `POST /auth/oauth/$provider/start`: Tarayıcı yönlendirme oturumu başlatır veya e-posta kod modunu bildirir.
  Future<Map<String, dynamic>> startOAuthWebSession({
    required String provider,
    List<AcceptedDocument>? acceptedDocuments,
  }) async {
    final cleanProvider = provider.trim().toLowerCase();
    try {
      final response = await _sendRequest(
        method: 'POST',
        uri: Uri.parse('$baseUrl/auth/oauth/$cleanProvider/start'),
        headers: const {'Content-Type': 'application/json'},
        body: {
          ..._acceptedDocumentsBody(acceptedDocuments),
        },
        retryOnTransportError: false,
      );
      _ensureStatus(response, 200, unauthorizedIsSession: false);
      return _decodePayload(response);
    } catch (_) {
      return <String, dynamic>{
        'mode': 'email_code',
        'provider': cleanProvider,
        'redirect_enabled': false,
      };
    }
  }

  /// `GET /auth/oauth/session/$sessionId`: Tarayıcı yönlendirmesiyle başlatılan oturumun durumunu sorgular.
  Future<Map<String, dynamic>> pollOAuthWebSession({
    required String sessionId,
  }) async {
    final response = await _sendRequest(
      method: 'GET',
      uri: Uri.parse('$baseUrl/auth/oauth/session/${Uri.encodeComponent(sessionId)}'),
      headers: const {'Content-Type': 'application/json'},
    );
    _ensureStatus(response, 200, unauthorizedIsSession: false);
    return _decodePayload(response);
  }

  /// `POST /auth/trial-access`: deneme erişim kodu (tek kullanımlık, 72 saat, demo siteye kilitli) ile oturum açar.
  /// Yanıt giriş yanıtıyla aynı biçimdedir (`token`, `user` + `user.trial_expires_at`). Hatalar: 401 `TRIAL_CODE_INVALID` /
  /// `TRIAL_CODE_USED` / `TRIAL_CODE_EXPIRED` / `TRIAL_CODE_REVOKED`, 429 hız sınırı, 503 `TRIAL_UNAVAILABLE`.
  Future<UserSession> redeemTrialCode({required String code}) {
    return _authRequest(
      path: '/auth/trial-access',
      body: {'code': code},
      expectedCode: 200,
    );
  }

  /// `POST /auth/sms/verify`: kod doğruysa oturum açar.
  Future<UserSession> verifySmsCode({required String phone, required String code}) {
    return _authRequest(
      path: '/auth/sms/verify',
      body: {'phone': phone, 'code': code},
      expectedCode: 200,
    );
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

  /// Bireysel kayıt (`/auth/register-individual`) ve site başvurusu (`/membership/site-applications`) gövdesine
  /// eklenen isteğe bağlı `accepted_documents:[{id,version}]` (docs/PLATFORM_SATISA_HAZIRLIK.md §1.4). Onay yoksa
  /// alan hiç gönderilmez (eski sunucu/istemci uyumu). `/auth/register` ve `/auth/site-manager/register` sunucuda
  /// kalıcı 410 (kapalı): oralara gönderilmez.
  static Map<String, dynamic> _acceptedDocumentsBody(List<AcceptedDocument>? documents) {
    if (documents == null || documents.isEmpty) return const <String, dynamic>{};
    return <String, dynamic>{
      'accepted_documents': <Map<String, dynamic>>[for (final d in documents) d.toJson()],
    };
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

  /// Yönetim türleri: terimler, önerilen modüller ve tek cümlelik açıklama (`GET /app/management-types`,
  /// F9). Eski sunucuda uç yoktur (404 -> ApiException): çağıran yerleşik tanımlara düşer
  /// ([ManagementTypeInfo.builtInAll]); bilinmeyen tür kodu `apartment_site` sayılmaz, atlanır.
  Future<List<ManagementTypeInfo>> getManagementTypes({required String token}) async {
    final response = await _authorizedRequest(
      method: 'GET',
      path: '/app/management-types',
      token: token,
    );
    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return _parsePayload(
      'Yönetim türleri',
      () => (payload['items'] as List<dynamic>? ?? <dynamic>[])
          .whereType<Map>()
          .where((item) => ManagementType.values.any((t) => t.apiValue == item['code']))
          .map((item) => ManagementTypeInfo.fromJson(Map<String, dynamic>.from(item)))
          .toList(growable: false),
    );
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

  // --- Yönetim kadrosu, davet, rehber (058) ------------------------------------------------

  Future<Map<String, dynamic>> _teamJson(
    String method,
    String path,
    String token,
    int expected, {
    Map<String, dynamic>? body,
  }) async {
    final response = await _authorizedRequest(
      method: method,
      path: path,
      token: token,
      body: body,
    );
    _ensureStatus(response, expected);
    return _decodePayload(response);
  }

  Future<TeamData> getTeam({required String token, required int siteCode}) async {
    final payload = await _teamJson('GET', '/manager/sites/$siteCode/team', token, 200);
    return _parsePayload('Yönetim kadrosu', () => TeamData.fromJson(payload));
  }

  /// Görev verir/günceller. Dönüş: sunucunun hesapladığı yetki durumu (`access`).
  Future<String?> setTeamDuty({
    required String token,
    required int siteCode,
    required int personId,
    required String duty,
    String? title,
    String? publicPhone,
    bool showInDirectory = true,
  }) async {
    final payload = await _teamJson(
      'PUT',
      '/manager/sites/$siteCode/people/$personId/duty',
      token,
      200,
      body: <String, dynamic>{
        'duty': duty,
        'title': ?title,
        'public_phone': ?publicPhone,
        'show_in_directory': showInDirectory,
      },
    );
    return payload['access'] as String?;
  }

  Future<void> endTeamDuty({
    required String token,
    required int siteCode,
    required int personId,
  }) async {
    await _teamJson('DELETE', '/manager/sites/$siteCode/people/$personId/duty', token, 200);
  }

  Future<PersonInvitationState> getPersonInvitation({
    required String token,
    required int siteCode,
    required int personId,
  }) async {
    final payload = await _teamJson(
      'GET',
      '/manager/sites/$siteCode/people/$personId/invitation',
      token,
      200,
    );
    return _parsePayload('Davet durumu', () => PersonInvitationState.fromJson(payload));
  }

  Future<PersonInvitationState> sendPersonInvitation({
    required String token,
    required int siteCode,
    required int personId,
  }) async {
    final payload = await _teamJson(
      'POST',
      '/manager/sites/$siteCode/people/$personId/invitation',
      token,
      201,
    );
    return _parsePayload('Davet', () => PersonInvitationState.fromJson(payload));
  }

  Future<void> revokePersonInvitation({
    required String token,
    required int siteCode,
    required int personId,
  }) async {
    await _teamJson('DELETE', '/manager/sites/$siteCode/people/$personId/invitation', token, 200);
  }

  Future<Map<String, dynamic>> provisionPersonAccount({
    required String token,
    required int siteCode,
    required int personId,
    String? loginName,
    String? password,
    String? email,
  }) async {
    return _teamJson(
      'POST',
      '/manager/sites/$siteCode/people/$personId/account',
      token,
      200,
      body: {
        if (loginName != null && loginName.isNotEmpty) 'login_name': loginName,
        if (password != null && password.isNotEmpty) 'password': password,
        if (email != null && email.isNotEmpty) 'email': email,
      },
    );
  }

  Future<Map<String, dynamic>> resetPersonPinDirect({
    required String token,
    required int siteCode,
    required int personId,
  }) async {
    return _teamJson(
      'POST',
      '/manager/sites/$siteCode/people/$personId/reset-pin',
      token,
      200,
    );
  }

  Future<Map<String, dynamic>> sendPersonPasswordReset({
    required String token,
    required int siteCode,
    required int personId,
  }) async {
    return _teamJson(
      'POST',
      '/manager/sites/$siteCode/people/$personId/password-reset',
      token,
      200,
    );
  }

  Future<Map<String, dynamic>> executePeopleBulkAction({
    required String token,
    required int siteCode,
    required String action,
    required List<int> personIds,
  }) async {
    return _teamJson(
      'POST',
      '/manager/sites/$siteCode/people/bulk-actions',
      token,
      200,
      body: <String, dynamic>{
        'action': action,
        'person_ids': personIds,
      },
    );
  }

  Future<void> saveDirectoryContact({
    required String token,
    required int siteCode,
    int? contactId,
    required String label,
    required String phone,
    String? note,
    required String category,
  }) async {
    final body = <String, dynamic>{
      'label': label,
      'phone': phone,
      'note': note,
      'category': category,
    };
    if (contactId == null) {
      await _teamJson('POST', '/manager/sites/$siteCode/directory/contacts', token, 201, body: body);
    } else {
      await _teamJson(
        'PATCH',
        '/manager/sites/$siteCode/directory/contacts/$contactId',
        token,
        200,
        body: body,
      );
    }
  }

  Future<void> deleteDirectoryContact({
    required String token,
    required int siteCode,
    required int contactId,
  }) async {
    await _teamJson(
      'DELETE',
      '/manager/sites/$siteCode/directory/contacts/$contactId',
      token,
      200,
    );
  }

  Future<List<DirectorySite>> getDirectory({required String token}) async {
    final payload = await _teamJson('GET', '/app/directory', token, 200);
    return _parsePayload(
      'Rehber',
      () => (payload['sites'] as List<dynamic>? ?? <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(DirectorySite.fromJson)
          .toList(),
    );
  }

  /// Sakin "Yöneticiyi ara": bağı olunan her sitenin yönetici adı ve profil telefonu (`GET /app/manager-contact`). Eski
  /// sunucuda uç yoktur (404): çağıran bunu "özellik yok" sayar.
  Future<List<ManagerContact>> getManagerContacts({required String token}) async {
    final payload = await _teamJson('GET', '/app/manager-contact', token, 200);
    return _parsePayload('Yönetici bilgisi', () => ManagerContact.listFromJson(payload));
  }

  Future<List<PendingInvitation>> listMyInvitations({required String token}) async {
    final payload = await _teamJson('GET', '/app/invitations', token, 200);
    return _parsePayload(
      'Davetler',
      () => (payload['invitations'] as List<dynamic>? ?? <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(PendingInvitation.fromJson)
          .toList(),
    );
  }

  Future<void> answerInvitation({
    required String token,
    required int invitationId,
    required bool accept,
  }) async {
    await _teamJson(
      'POST',
      '/app/invitations/$invitationId/${accept ? 'accept' : 'decline'}',
      token,
      200,
    );
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

  // --- Site başvurusu (site yöneticisi olma) -----------------------------------------------
  // Sözleşme: docs/PLATFORM_SITE_BASVURUSU.md. Başvuran uçları `/membership/site-applications...`,
  // süper kullanıcı uçları `/admin/site-applications...` altındadır. Başarı durum kodu (200/201)
  // savunmacı okunur: ikisi de kabul edilir.

  /// 200 ya da 201 kabul edilir; başka durum [ApiException] fırlatır. (Aidat ve Finans'ta da kullanılır:
  /// idempotent yazmalar ilk seferde 201, aynı anahtarla tekrarında 200 döner; ikisi de başarıdır.)
  void _ensureCreatedOrOk(http.Response response) {
    final status = response.statusCode;
    _ensureStatus(response, status == 201 ? 201 : 200);
  }

  /// Site başvurusu çağrılarının ortak hata yeniden yazımı. Genel kod -> metin eşlemesi bağlamsızdır;
  /// burada çağıranın bakış açısına göre düzeltilir:
  /// - `USER_NOT_FOUND` ("Bu e-posta ile kayıtlı hesap yok." ek rol atamasının metnidir) başvuruda yanıltır.
  /// - [applicantCreate]: başvuru oluşturma; `ALREADY_SITE_MANAGER` ("Bu kişi zaten site yöneticisi") ve
  ///   `DEVICE_NOT_FOUND` başvuranın dilinde söylenir.
  Future<T> _siteApplicationCall<T>(
    Future<T> Function() body, {
    bool admin = false,
    bool applicantCreate = false,
  }) async {
    try {
      return await body();
    } on ApiException catch (e) {
      String? rewritten;
      if (e.code == 'USER_NOT_FOUND') {
        rewritten = admin ? siteApplicationApplicantNotFoundMessage : siteApplicationAccountNotFoundMessage;
      } else if (applicantCreate && e.code == 'ALREADY_SITE_MANAGER') {
        rewritten = siteApplicationAlreadyManagerMessage;
      } else if (applicantCreate && e.code == 'DEVICE_NOT_FOUND') {
        rewritten = siteApplicationDeviceNotFoundMessage;
      }
      if (rewritten == null) rethrow;
      throw ApiException(
        rewritten,
        statusCode: e.statusCode,
        code: e.code,
        retryAfterSeconds: e.retryAfterSeconds,
        payload: e.payload,
      );
    }
  }

  /// "Zaten site yöneticisisiniz" (başvuran bakış açısı; genel `ALREADY_SITE_MANAGER` metni başkasını anlatır).
  static const String siteApplicationAlreadyManagerMessage =
      'Zaten site yöneticisisiniz. Yeni site için Site Yönetimi bölümündeki "Site Ekle"yi kullanın.';

  static const String siteApplicationDeviceNotFoundMessage =
      'Seçtiğiniz cihaz hesabınızda bulunamadı. Cihaz seçimini kaldırıp tekrar deneyin.';

  static const String siteApplicationAccountNotFoundMessage =
      'Hesap bilgileriniz bulunamadı. Çıkış yapıp yeniden giriş yapın.';

  static const String siteApplicationApplicantNotFoundMessage = 'Başvuran hesap bulunamadı.';

  /// Site başvurusu gönderir (201). Gövde `setup-site` ile aynıdır; [deviceUid] ve [note] isteğe bağlıdır.
  Future<SiteApplication> createSiteApplication({
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
    String? note,
    List<AcceptedDocument>? acceptedDocuments,
  }) {
    final trimmedNote = note?.trim();
    return _siteApplicationCall(applicantCreate: true, () async {
      final response = await _authorizedRequest(
        method: 'POST',
        path: '/membership/site-applications',
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
          if (managementType != null && managementType.isNotEmpty)
            'management_type': managementType,
          if (trimmedNote != null && trimmedNote.isNotEmpty) 'note': trimmedNote,
          ..._acceptedDocumentsBody(acceptedDocuments),
        },
      );
      _ensureCreatedOrOk(response);
      final payload = _decodePayload(response);
      final application = _parsePayload(
        'Site başvurusu',
        () => SiteApplication.fromJson(payload['application'] as Map<String, dynamic>),
      );
      return application;
    });
  }

  /// Kendi başvurularım: bekleyen (yoksa null), son 10 başvuru (yeniden eskiye) ve `requires_application`.
  /// `pending` ve `items` alanlarının ikisi de yoksa yanıt anlaşılamamıştır (hata; "başvuru yok" DEĞİL).
  Future<MySiteApplications> getMySiteApplications({required String token}) {
    return _siteApplicationCall(() async {
      final response = await _authorizedRequest(
        method: 'GET',
        path: '/membership/site-applications/mine',
        token: token,
      );
      _ensureStatus(response, 200);
      final payload = _decodePayload(response);
      final mine = _parsePayload('Site başvurularım', () {
        try {
          return MySiteApplications.fromJson(payload);
        } on FormatException {
          throw ApiException('Başvuru durumu yanıtı anlaşılamadı. Tekrar deneyin.');
        }
      });
      return mine;
    });
  }

  /// Kendi BEKLEYEN başvurusunu iptal eder.
  Future<SiteApplication> cancelSiteApplication({
    required String token,
    required int applicationId,
  }) {
    return _siteApplicationCall(() async {
      final response = await _authorizedRequest(
        method: 'POST',
        path: '/membership/site-applications/$applicationId/cancel',
        token: token,
      );
      _ensureCreatedOrOk(response);
      final payload = _decodePayload(response);
      final application = _parsePayload(
        'Site başvurusu',
        () => SiteApplication.fromJson(payload['application'] as Map<String, dynamic>),
      );
      return application;
    });
  }

  /// Süper kullanıcı: başvurular. [status] `pending|approved|rejected|cancelled|all` (sunucu varsayılanı
  /// `pending`); [query] site adı, şehir, başvuran adı / e-postası.
  Future<SiteApplicationPage> listAdminSiteApplications({
    required String token,
    String? status,
    String? query,
    int limit = 30,
    int offset = 0,
  }) {
    final params = <String, String>{
      if (status != null && status.isNotEmpty) 'status': status,
      if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
      'limit': '$limit',
      'offset': '$offset',
    };
    final path = Uri(path: '/admin/site-applications', queryParameters: params).toString();
    return _siteApplicationCall(admin: true, () async {
      final response = await _authorizedRequest(method: 'GET', path: path, token: token);
      _ensureStatus(response, 200);
      final payload = _decodePayload(response);
      final page = _parsePayload('Site başvuruları', () => SiteApplicationPage.fromJson(payload));
      return page;
    });
  }

  /// Süper kullanıcı: bekleyen başvuru sayısı (çekmece rozeti; hafif uç).
  Future<int> getAdminSiteApplicationsPendingCount({required String token}) {
    return _siteApplicationCall(admin: true, () async {
      final response = await _authorizedRequest(
        method: 'GET',
        path: '/admin/site-applications/summary',
        token: token,
      );
      _ensureStatus(response, 200);
      final payload = _decodePayload(response);
      final count = _parsePayload('Site başvuru özeti', () {
        final raw = payload['pending'];
        final value = raw is num ? raw.toInt() : int.tryParse(raw?.toString() ?? '');
        if (value == null) throw const FormatException('pending yok');
        return value < 0 ? 0 : value;
      });
      return count;
    });
  }

  /// Süper kullanıcı: tek başvuru (başvuran iletişimi, cihaz durumu dahil).
  Future<SiteApplication> getAdminSiteApplication({
    required String token,
    required int applicationId,
  }) {
    return _siteApplicationCall(admin: true, () async {
      final response = await _authorizedRequest(
        method: 'GET',
        path: '/admin/site-applications/$applicationId',
        token: token,
      );
      _ensureStatus(response, 200);
      final payload = _decodePayload(response);
      final application = _parsePayload('Site başvurusu', () {
        // Sözleşme: gövde doğrudan `Application`; bazı sürümler `{ application }` sarar — ikisi de okunur.
        final wrapped = payload['application'];
        return SiteApplication.fromJson(wrapped is Map<String, dynamic> ? wrapped : payload);
      });
      return application;
    });
  }

  /// Süper kullanıcı: başvuruyu onaylar (tek işlemde site kurulur, başvuran site yöneticisi olur).
  /// Onay [note]'u (≤300) BAŞVURANA GÖRÜNÜR (sunucu `decision_note`).
  Future<SiteApplicationDecision> approveSiteApplication({
    required String token,
    required int applicationId,
    String? note,
  }) {
    final trimmed = note?.trim();
    return _siteApplicationCall(admin: true, () async {
      final response = await _authorizedRequest(
        method: 'POST',
        path: '/admin/site-applications/$applicationId/approve',
        token: token,
        body: {if (trimmed != null && trimmed.isNotEmpty) 'note': trimmed},
      );
      _ensureCreatedOrOk(response);
      final payload = _decodePayload(response);
      final decision = _parsePayload('Site başvurusu', () => SiteApplicationDecision.fromJson(payload));
      return decision;
    });
  }

  /// Süper kullanıcı: başvuruyu reddeder; [reason] isteğe bağlı gerekçe (en çok 300 karakter; BAŞVURANA GÖRÜNÜR).
  Future<SiteApplication> rejectSiteApplication({
    required String token,
    required int applicationId,
    String? reason,
  }) {
    final trimmed = reason?.trim();
    return _siteApplicationCall(admin: true, () async {
      final response = await _authorizedRequest(
        method: 'POST',
        path: '/admin/site-applications/$applicationId/reject',
        token: token,
        body: {if (trimmed != null && trimmed.isNotEmpty) 'reason': trimmed},
      );
      _ensureCreatedOrOk(response);
      final payload = _decodePayload(response);
      final application = _parsePayload(
        'Site başvurusu',
        () => SiteApplication.fromJson(payload['application'] as Map<String, dynamic>),
      );
      return application;
    });
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
    List<int>? documentIds,
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
        // Belge ekleri (Faz 3b-A; en çok 5, yalnız sakinlere açık belgeler).
        if (documentIds != null && documentIds.isNotEmpty) 'document_ids': documentIds,
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

  /// Duyuruyu KENDİ listemden kaldırır (DELETE /app/announcements/:id; idempotent, okundu bilgisine dokunmaz).
  Future<void> hideAnnouncement({required String token, required int announcementId}) async {
    final response = await _authorizedRequest(
      method: 'DELETE',
      path: '/app/announcements/$announcementId',
      token: token,
    );
    _ensureStatus(response, 200);
  }

  /// "Geri al": [hideAnnouncement] ile kaldırılan duyuruyu listeye döndürür.
  Future<void> restoreAnnouncement({required String token, required int announcementId}) async {
    final response = await _authorizedRequest(
      method: 'POST',
      path: '/app/announcements/$announcementId/restore',
      token: token,
      body: const <String, dynamic>{},
    );
    _ensureStatus(response, 200);
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

  /// E-posta tercihlerini yazar: yalnız VERİLEN anahtar(lar) gövdeye girer (`email_announcements` ve/veya
  /// `email_finance_reminders`; verilmeyen sunucuda değişmez). İkisi de null ise [ArgumentError]. `push_*`
  /// anahtarları GÖNDERİLMEZ (şimdilik değişmez). Yanıtta tercih alanı yoksa istenen değer geçerli sayılır.
  Future<NotificationPrefs> setNotificationPreferences({
    required String token,
    bool? emailAnnouncements,
    bool? emailFinanceReminders,
  }) async {
    if (emailAnnouncements == null && emailFinanceReminders == null) {
      throw ArgumentError('En az bir e-posta tercihi verilmelidir.');
    }
    final response = await _authorizedRequest(
      method: 'PUT',
      path: '/app/notification-preferences',
      token: token,
      body: {
        'email_announcements': ?emailAnnouncements,
        'email_finance_reminders': ?emailFinanceReminders,
      },
    );
    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return _parsePayload(
      'Bildirim tercihleri',
      () => NotificationPrefs.fromJson(
        payload,
        fallbackEmail: emailAnnouncements,
        fallbackFinance: emailFinanceReminders,
      ),
    );
  }

  // --- Aidat ve Finans (Faz 4a) -------------------------------------------------------------
  // Yönetici uçları `/manager/sites/:siteCode/finance/...`, sakin ucu `/app/my-finance` (sözleşme:
  // docs/PLATFORM_FINANS.md). Tutarlar KURUŞ tamsayıdır. Okuma yönetici / süper kullanıcı / kurul
  // üyesine, yazma yalnız yönetici / süper kullanıcıya açıktır; yetki ve modül durumu sunucuda doğrulanır
  // (403 FORBIDDEN_ROLE / MODULE_DISABLED). Yazma istekleri ASLA otomatik yeniden denenmez; çift kayıt
  // `idempotency_key` ile önlenir (aynı anahtar = aynı kayıt, 200).

  String _financePath(int siteCode, String tail, [Map<String, String>? query]) {
    final path = '/manager/sites/$siteCode/finance/$tail';
    if (query == null || query.isEmpty) return path;
    return Uri(path: path, queryParameters: query).toString();
  }

  /// Tanım listesi. [kind] ve [active] verilmezse süzgeç yok.
  ///
  /// Sunucu listeyi sayfalar (`limit/offset` + `total`): bütün sayfalar sırayla okunur ve birleştirilir, böylece
  /// ekran sessizce ilk sayfada kalmaz. `total` yoksa (eski sunucu) tek yanıt tüm listedir. Sayfa sayısı
  /// sınırlıdır; aynı kimlik iki kez eklenmez. İlk istekte `limit/offset` gönderilmez.
  Future<List<FeeDefinition>> listFeeDefinitions({
    required String token,
    required int siteCode,
    FeeKind? kind,
    bool? active,
  }) async {
    final byId = <int, FeeDefinition>{};
    var offset = 0;
    for (var page = 0; page < _maxDefinitionPages; page++) {
      final response = await _authorizedRequest(
        method: 'GET',
        path: _financePath(siteCode, 'definitions', {
          if (kind != null && kind != FeeKind.unknown) 'kind': kind.apiValue,
          'active': ?active?.toString(),
          // İlk istek sunucunun varsayılan sayfasını ister (eski sunucuyla uyumlu); `total` daha fazlasını
          // bildirirse sonraki sayfalar `offset` ile istenir.
          if (offset > 0) ...{'limit': '$_definitionPageSize', 'offset': '$offset'},
        }),
        token: token,
      );
      _ensureStatus(response, 200);
      final payload = _decodePayload(response);
      final pageItems = _parsePayload('Tanımlar', () {
        final raw = payload['items'];
        if (raw is! List) return const <FeeDefinition>[];
        return raw
            .whereType<Map>()
            .map((e) => FeeDefinition.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      });
      for (final item in pageItems) {
        byId.putIfAbsent(item.id, () => item);
      }
      final total = payload['total'] is num ? (payload['total'] as num).toInt() : null;
      if (total == null || pageItems.isEmpty || offset + pageItems.length >= total) break;
      offset += pageItems.length;
    }
    return List<FeeDefinition>.unmodifiable(byId.values);
  }

  static const int _definitionPageSize = 100;
  static const int _maxDefinitionPages = 20;

  Future<FeeDefinition> createFeeDefinition({
    required String token,
    required int siteCode,
    required FeeDefinitionInput input,
  }) async {
    final response = await _authorizedRequest(
      method: 'POST',
      path: _financePath(siteCode, 'definitions'),
      token: token,
      body: input.toJson(),
    );
    _ensureCreatedOrOk(response);
    final payload = _decodePayload(response);
    return _parsePayload('Tanım', () => FeeDefinition.fromJson(_unwrapKey(payload, 'definition')));
  }

  /// Tanımı günceller: yalnız [fields] içindekiler gönderilir. Borçlandırılmış tanımda yalnız `name`,
  /// `end_period`, `is_active`, `due_day` kabul edilir (sunucu zorlar).
  Future<FeeDefinition> updateFeeDefinition({
    required String token,
    required int siteCode,
    required int definitionId,
    required Map<String, Object?> fields,
  }) async {
    final response = await _authorizedRequest(
      method: 'PATCH',
      path: _financePath(siteCode, 'definitions/$definitionId'),
      token: token,
      body: Map<String, dynamic>.of(fields),
    );
    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return _parsePayload('Tanım', () => FeeDefinition.fromJson(_unwrapKey(payload, 'definition')));
  }

  /// Borçlandırma önizlemesi (YAZMAZ). Aylık tanımda [period], tek seferlikte isteğe bağlı [dueDate].
  Future<FeePreview> previewFeeRun({
    required String token,
    required int siteCode,
    required int definitionId,
    FinancePeriod? period,
    DateTime? dueDate,
  }) async {
    final response = await _authorizedRequest(
      method: 'POST',
      path: _financePath(siteCode, 'definitions/$definitionId/preview'),
      token: token,
      body: {
        if (period != null) 'period': period.toApi(),
        if (dueDate != null) 'due_date': crmDateParam(dueDate),
      },
    );
    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return _parsePayload('Önizleme', () => FeePreview.fromJson(payload));
  }

  /// Borçlandırır: sunucu önizlemeyle aynı hesabı yeniden yapar; toplam / daire sayısı / içerik özeti
  /// ([expectedHash] = önizlemenin `preview_hash`i) uyuşmazsa 409 `PREVIEW_STALE` (hiçbir şey yazılmaz).
  /// [idempotencyKey] yeniden denemede AYNI verilir. [expectedHash] önizleme yanıtında yoksa (eski sunucu) null.
  ///
  /// Tahakkuk dayanağı (K2): Fon (demirbaş) hesabı borcunda Karar Defteri açık sitede [decisionId] (kesinleşmiş karar), kapalı sitede
  /// [decisionReason] (serbest metin gerekçe) ZORUNLUDUR; aksi 400 `DECISION_REQUIRED` / `DECISION_REASON_REQUIRED`.
  Future<FeePostResult> postFeeRun({
    required String token,
    required int siteCode,
    required int definitionId,
    FinancePeriod? period,
    DateTime? dueDate,
    required int expectedTotalMinor,
    required int expectedApartmentCount,
    String? expectedHash,
    bool skipMissing = false,
    String? idempotencyKey,
    int? decisionId,
    String? decisionReason,
  }) async {
    final response = await _authorizedRequest(
      method: 'POST',
      path: _financePath(siteCode, 'definitions/$definitionId/post'),
      token: token,
      body: {
        if (period != null) 'period': period.toApi(),
        if (dueDate != null) 'due_date': crmDateParam(dueDate),
        'expected_total_minor': expectedTotalMinor,
        'expected_apartment_count': expectedApartmentCount,
        'expected_hash': ?expectedHash,
        if (skipMissing) 'skip_missing': true,
        'idempotency_key': ?idempotencyKey,
        'decision_id': ?decisionId,
        if (decisionReason != null && decisionReason.trim().isNotEmpty) 'decision_reason': decisionReason.trim(),
      },
    );
    _ensureCreatedOrOk(response);
    final payload = _decodePayload(response);
    return _parsePayload('Borçlandırma', () => FeePostResult.fromJson(payload));
  }

  /// Ek borç önizlemesi (YAZMAZ).
  Future<FeePreview> previewExtraCharge({
    required String token,
    required int siteCode,
    required ExtraChargeInput input,
  }) async {
    final response = await _authorizedRequest(
      method: 'POST',
      path: _financePath(siteCode, 'charges/preview'),
      token: token,
      body: input.toJson(),
    );
    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return _parsePayload('Önizleme', () => FeePreview.fromJson(payload));
  }

  /// Ek borcu yazar (tek işlemde tek seferlik tanım + önizleme doğrulaması + borçlandırma).
  ///
  /// [idempotencyKey] ZORUNLUDUR (aynı anahtar + farklı gövde = 409 `IDEMPOTENCY_CONFLICT`). Aynı ek borç
  /// son 24 saatte yazıldıysa 409 `DUPLICATE_CHARGE`; kullanıcı bilerek tekrar ekleyecekse [allowDuplicate]
  /// true gönderilir.
  Future<FeePostResult> postExtraCharge({
    required String token,
    required int siteCode,
    required ExtraChargeInput input,
    required int expectedTotalMinor,
    required int expectedApartmentCount,
    String? expectedHash,
    bool skipMissing = false,
    bool allowDuplicate = false,
    required String idempotencyKey,
  }) async {
    final response = await _authorizedRequest(
      method: 'POST',
      path: _financePath(siteCode, 'charges'),
      token: token,
      body: {
        ...input.toJson(),
        'expected_total_minor': expectedTotalMinor,
        'expected_apartment_count': expectedApartmentCount,
        'expected_hash': ?expectedHash,
        if (skipMissing) 'skip_missing': true,
        if (allowDuplicate) 'allow_duplicate': true,
        'idempotency_key': idempotencyKey,
      },
    );
    _ensureCreatedOrOk(response);
    final payload = _decodePayload(response);
    return _parsePayload('Ek borç', () => FeePostResult.fromJson(payload));
  }

  /// Daire bakiyeleri. [status]: `debtor|credit|all`.
  Future<BalancePage> listFinanceBalances({
    required String token,
    required int siteCode,
    String status = 'all',
    String? query,
    int limit = 50,
    int offset = 0,
  }) async {
    final trimmed = query?.trim();
    final response = await _authorizedRequest(
      method: 'GET',
      path: _financePath(siteCode, 'balances', {
        'status': status,
        if (trimmed != null && trimmed.isNotEmpty) 'q': trimmed,
        'limit': '$limit',
        'offset': '$offset',
      }),
      token: token,
    );
    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return _parsePayload('Bakiyeler', () => BalancePage.fromJson(payload));
  }

  /// Daire ekstresi; sonraki sayfa için önceki yanıttaki `next_before_id` [beforeId] olarak verilir. [accountParty] (İP-1A)
  /// verilirse satırlar ve bakiye yalnız o hesabındır (`?account_party=`); verilmezse eski davranış (iki hesap birlikte).
  Future<AccountView> getFinanceAccount({
    required String token,
    required int siteCode,
    required int apartmentId,
    int limit = 50,
    int? beforeId,
    AccountParty? accountParty,
  }) async {
    final response = await _authorizedRequest(
      method: 'GET',
      path: _financePath(siteCode, 'apartments/$apartmentId/account', {
        'limit': '$limit',
        if (beforeId != null) 'before_id': '$beforeId',
        'account_party': ?accountParty?.apiValue,
      }),
      token: token,
    );
    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return _parsePayload('Ekstre', () => AccountView.fromJson(payload));
  }

  /// Tahsilat kaydı. [amountMinor] POZİTİF kuruş (defter −); [entryDate] takvim günü (gelecek olamaz). [accountParty] (İP-1A):
  /// tahsilatın yazılacağı daire hesabı; verilmezse sunucu vadesi en eski açık borcu olan hesabı seçer. [fund]: tahsilat YALNIZ
  /// o kasanın borçlarına uygulanır; verilmezse otomatik (en eski vade önce).
  Future<LedgerWriteResult> recordFeePayment({
    required String token,
    required int siteCode,
    required int apartmentId,
    required int amountMinor,
    required DateTime entryDate,
    required PaymentMethod method,
    String? description,
    required String idempotencyKey,
    AccountParty? accountParty,
    FinanceFund? fund,
  }) async {
    final note = description?.trim();
    final response = await _authorizedRequest(
      method: 'POST',
      path: _financePath(siteCode, 'payments'),
      token: token,
      body: {
        'apartment_id': apartmentId,
        'amount_minor': amountMinor,
        'entry_date': crmDateParam(entryDate),
        'method': method.apiValue,
        if (note != null && note.isNotEmpty) 'description': note,
        'idempotency_key': idempotencyKey,
        'account_party': ?accountParty?.apiValue,
        'fund': ?fund?.apiValue,
      },
    );
    _ensureCreatedOrOk(response);
    final payload = _decodePayload(response);
    return _parsePayload('Tahsilat', () => LedgerWriteResult.fromJson(payload));
  }

  /// Kaydı iptal eder (karşı işaretli ters kayıt; silme YOK).
  Future<LedgerWriteResult> reverseFinanceEntry({
    required String token,
    required int siteCode,
    required int entryId,
    String? reason,
    String? idempotencyKey,
  }) async {
    final text = reason?.trim();
    final response = await _authorizedRequest(
      method: 'POST',
      path: _financePath(siteCode, 'entries/$entryId/reverse'),
      token: token,
      body: {
        if (text != null && text.isNotEmpty) 'reason': text,
        'idempotency_key': ?idempotencyKey,
      },
    );
    _ensureCreatedOrOk(response);
    final payload = _decodePayload(response);
    return _parsePayload('İptal', () => LedgerWriteResult.fromJson(payload));
  }

  /// Tahsilatı düzeltir: TEK işlemde ters kayıt + yeni tahsilat. [accountParty] (İP-1A) verilirse yeni tahsilat o hesaba yazılır
  /// (yanlış hesaba girilen tahsilatın düzeltilmesi); verilmezse eski tahsilatın hesabı korunur. Ters kayıt hep eski hesaptadır.
  /// [fund] verilirse yeni tahsilat yalnız o kasaya uygulanır; verilmezse ASIL tahsilatın kısıtı korunur.
  Future<LedgerWriteResult> correctFinancePayment({
    required String token,
    required int siteCode,
    required int entryId,
    required int amountMinor,
    required DateTime entryDate,
    required PaymentMethod method,
    String? description,
    required String idempotencyKey,
    AccountParty? accountParty,
    FinanceFund? fund,
  }) async {
    final note = description?.trim();
    final response = await _authorizedRequest(
      method: 'POST',
      path: _financePath(siteCode, 'entries/$entryId/correct'),
      token: token,
      body: {
        'amount_minor': amountMinor,
        'entry_date': crmDateParam(entryDate),
        'method': method.apiValue,
        if (note != null && note.isNotEmpty) 'description': note,
        'idempotency_key': idempotencyKey,
        'account_party': ?accountParty?.apiValue,
        'fund': ?fund?.apiValue,
      },
    );
    _ensureCreatedOrOk(response);
    final payload = _decodePayload(response);
    return _parsePayload('Düzeltme', () => LedgerWriteResult.fromJson(payload));
  }

  Future<FinancePeriods> getFinancePeriods({
    required String token,
    required int siteCode,
  }) async {
    final response = await _authorizedRequest(
      method: 'GET',
      path: _financePath(siteCode, 'periods'),
      token: token,
    );
    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return _parsePayload('Dönemler', () => FinancePeriods.fromJson(payload));
  }

  /// Ayı kapatır (sıralı; gelecek ay kapatılamaz). Yanıt gövdesi kullanılmaz: dönem listesi yeniden okunur.
  Future<void> closeFinancePeriod({
    required String token,
    required int siteCode,
    required FinancePeriod period,
  }) async {
    final response = await _authorizedRequest(
      method: 'POST',
      path: _financePath(siteCode, 'periods/${period.toApi()}/close'),
      token: token,
      body: const <String, dynamic>{},
    );
    _ensureCreatedOrOk(response);
  }

  /// Kapalı ayı yeniden açar (yalnız süper kullanıcı, yalnız en son kapalı ay).
  Future<void> reopenFinancePeriod({
    required String token,
    required int siteCode,
    required FinancePeriod period,
  }) async {
    final response = await _authorizedRequest(
      method: 'POST',
      path: _financePath(siteCode, 'periods/${period.toApi()}/reopen'),
      token: token,
      body: const <String, dynamic>{},
    );
    _ensureCreatedOrOk(response);
  }

  Future<FinanceSummary> getFinanceSummary({
    required String token,
    required int siteCode,
  }) async {
    final response = await _authorizedRequest(
      method: 'GET',
      path: _financePath(siteCode, 'summary'),
      token: token,
    );
    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return _parsePayload('Finans özeti', () => FinanceSummary.fromJson(payload));
  }

  /// Yönetici ana sayfası "Bu ay" özeti (`GET .../finance/home`).
  Future<FinanceHome> getFinanceHome({required String token, required int siteCode}) async {
    final response = await _authorizedRequest(
      method: 'GET',
      path: _financePath(siteCode, 'home'),
      token: token,
    );
    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return _parsePayload('Bu ayın özeti', () => FinanceHome.fromJson(payload));
  }

  /// Sakinin kendi dairelerinin borç durumu (`GET /app/my-finance`).
  Future<MyFinance> getMyFinance({required String token}) async {
    final response = await _authorizedRequest(
      method: 'GET',
      path: '/app/my-finance',
      token: token,
    );
    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return _parsePayload('Borcum', () => MyFinance.fromJson(payload));
  }

  /// `{ "definition": {...} }` gibi sarmalı açar; yoksa gövdenin kendisi.
  Map<String, dynamic> _unwrapKey(Map<String, dynamic> payload, String key) {
    final inner = payload[key];
    return inner is Map ? Map<String, dynamic>.from(inner) : payload;
  }

  /// Daire sakinini oluşturur / düzenler. Yeni daire hesabı açıldıysa PIN yanıtta BİR KEZ gelir
  /// (`pinIssue`; e-posta varsa sunucu PIN'i bir kez gönderir); mevcut sakin düzenlemesinde null.
  Future<({ApartmentRecord apartment, ApartmentPinIssue? pinIssue})>
  upsertApartmentResident({
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
    return _parsePayload('Daire kullanicisi', () {
      final apartment = ApartmentRecord.fromJson(
        payload['apartment'] as Map<String, dynamic>,
      );
      return (
        apartment: apartment,
        pinIssue: ApartmentPinIssue.fromResponse(apartment, payload),
      );
    });
  }

  /// Daire hesabının PIN'ini sıfırlar: yeni PIN yanıtta BİR KEZ gelir (sunucu saklamaz); [sendEmail]
  /// ise sakinin e-posta adresine de bir kez gönderilir.
  Future<ApartmentPinIssue> resetApartmentPin({
    required String token,
    required UserRole role,
    required int apartmentId,
    bool sendEmail = true,
  }) async {
    final response = await _authorizedRequest(
      method: 'POST',
      path: '${_managementPrefix(role)}/apartments/$apartmentId/reset-pin',
      token: token,
      body: {'send_email': sendEmail},
    );

    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return _parsePayload('Daire PIN', () {
      final apartment = ApartmentRecord.fromJson(
        payload['apartment'] as Map<String, dynamic>,
      );
      final issue = ApartmentPinIssue.fromResponse(apartment, payload);
      if (issue == null) {
        throw const FormatException('pin_code yok');
      }
      return issue;
    });
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
    String? deviceToken,
    void Function(String deviceToken)? onDeviceToken,
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
      // Parola değişince cihaz belirteci parola sürümüne bağlı olduğundan eskisi düşer: sunucu cihaz kimliğini
      // korumak için kayıtlı belirteci okur ve yenisini döndürür. Yalnız parola değişirken gönderilir.
      extraHeaders: password != null ? _deviceTokenHeader(deviceToken) : null,
    );

    // Yanlış mevcut şifre sunucuda 400 CURRENT_PASSWORD_INVALID döner (oturumu kapatmaz). Bu uçta
    // 401 yalnızca gerçek oturum sorunudur (token iptal/süre dolumu/silinmiş kullanıcı) ve
    // SessionExpiredException olarak oturumu sonlandırır.
    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    // Yeni cihaz belirteci (yalnız parola değişiminde) isteğe bağlıdır; yok / bozuksa sessizce yok sayılır ve
    // parola değişiminin başarısını etkilemez.
    _emitDeviceToken(payload, onDeviceToken);
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
    void Function(String deviceToken)? onDeviceToken,
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
    final session = _parsePayload('Oturum bilgisi', () {
      final user = payload['user'] as Map<String, dynamic>;
      return _toUserSession(
        user: user,
        token: payload['token'] as String,
        fallbackId: user['id'] as int,
        fallbackRole: UserRole.fromApi(user['role'] as String),
        fallbackIsActive: user['is_active'] as bool? ?? true,
      );
    });
    // Güvenilir cihaz belirteci isteğe bağlıdır: yoksa / bozuksa sessizce yok sayılır (giriş etkilenmez).
    _emitDeviceToken(payload, onDeviceToken);
    return session;
  }

  /// Yanıttaki `device_token` boş olmayan bir metinse (kırpılmış, <= 512) [onDeviceToken]'a verir; yok / null /
  /// metin değil / boş / çok uzun ise HİÇBİR ŞEY yapmaz. Geri çağrının hatası çağıranı etkilemez.
  static void _emitDeviceToken(Map<String, dynamic> payload, void Function(String deviceToken)? onDeviceToken) {
    if (onDeviceToken == null) return;
    final raw = payload['device_token'];
    if (raw is! String) return;
    final trimmed = raw.trim();
    if (trimmed.isEmpty || trimmed.length > LoginDeviceTokenStore.maxTokenLength) return;
    try {
      onDeviceToken(trimmed);
    } catch (_) {
      // Saklama hatası parola değişiminin / girişin başarısını bozmaz.
    }
  }

  /// `X-Device-Token` başlığı: belirteç yoksa ya da başlığa yazılamayacak biçimdeyse (boşluk, ASCII dışı, çok
  /// uzun) başlık HİÇ gönderilmez.
  static Map<String, String>? _deviceTokenHeader(String? deviceToken) {
    if (!LoginDeviceTokenStore.isPlausibleToken(deviceToken)) return null;
    return <String, String>{'X-Device-Token': deviceToken!};
  }

  Future<http.Response> _authorizedRequest({
    required String method,
    required String path,
    required String token,
    Map<String, dynamic>? body,
    Duration? timeout,
    String? timeoutMessage,
    Map<String, String>? extraHeaders,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
      ...?extraHeaders,
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
      // Deneme erişim kodu oturumu (P2-27): 72 saat doldu ya da kod iptal edildi; giriş ekranı nedenini gösterir.
      if (code == 'TRIAL_EXPIRED') {
        throw SessionExpiredException(
          'Deneme süreniz doldu. Devam etmek için bizimle iletişime geçin.',
          code,
        );
      }
      if (code == 'TRIAL_REVOKED') {
        throw SessionExpiredException('Deneme erişiminiz sonlandırıldı.', code);
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
    final statusMessage = genericMessageForStatus(status, code: code);
    // Sunucu hiçbir kullanılabilir metin vermediyse mesaj yalnız teknik yedektir ("İşlem başarısız (502)").
    final genericFallback = mappedMessage == null && errorMsg == null && statusMessage == null;
    var message = mappedMessage ?? errorMsg ?? statusMessage ?? 'İşlem başarısız ($status)';

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
      genericFallback: genericFallback,
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
      // Duyuru yayın sınırları (Faz 3a): sunucu metni gelirse o kullanılır; gelmezse bu yedek metinler.
      case 'DUPLICATE_ANNOUNCEMENT':
        return 'Aynı duyuru az önce yayınlandı. Çift gönderimi önlemek için bir dakika bekleyin.';
      case 'ANNOUNCEMENT_DAILY_LIMIT':
        return 'Bu site için günlük duyuru sınırına ulaşıldı. Yarın tekrar deneyin.';
      case 'ANNOUNCEMENT_HOURLY_LIMIT':
        return 'Son bir saatte çok sayıda e-postalı duyuru yayınladınız. Biraz sonra tekrar deneyin.';
    }
    return null;
  }

  /// `400 WEAK_PASSWORD` için Türkçe iletiler (parola ilkesi: docs/PLATFORM_SATISA_HAZIRLIK.md §1.7).
  /// Sunucu yanıtındaki `reason` (required | too_short | too_long | same_as_email | same_as_name | common)
  /// özel iletiye eşlenir; bilinmeyen / eksik `reason` genel iletiye düşer. İstemci doğrulayıcı
  /// (lib/ui/helpers/password_policy.dart) AYNI metinleri kullanır.
  static const String weakPasswordMessage =
      'Bu şifre güvenlik ilkesine uymuyor. En az 8 karakterli, yaygın olmayan ve adınızdan ya da '
      'e-postanızdan farklı bir şifre seçin.';
  static const String passwordRequiredMessage = 'Şifre zorunludur';
  static const String passwordTooShortMessage =
      'Şifre çok kısa: en az 8 karakter olmalı. Birkaç sözcüğü art arda yazabilirsiniz.';
  static const String passwordTooLongMessage =
      'Şifre çok uzun: en fazla 128 karakter ve 72 bayt olabilir (Türkçe harfler 2 bayt sayılır; yaklaşık 36 '
      'Türkçe harf ya da 72 İngilizce harf). Daha kısa bir şifre seçin.';
  static const String passwordSameAsEmailMessage =
      'Şifre e-posta adresinizle aynı olamaz. Farklı bir şifre seçin.';
  static const String passwordSameAsNameMessage =
      'Şifre adınızla ya da kullanıcı adınızla aynı olamaz. Farklı bir şifre seçin.';
  static const String passwordCommonMessage =
      'Bu şifre çok yaygın ve kolay tahmin edilir. Daha özgün bir şifre seçin.';

  /// `WEAK_PASSWORD` yanıtının `reason` alanına karşılık gelen ileti (bilinmiyorsa genel ileti).
  static String weakPasswordMessageFor(Object? reason) {
    switch (reason) {
      case 'required':
        return passwordRequiredMessage;
      case 'too_short':
        return passwordTooShortMessage;
      case 'too_long':
        return passwordTooLongMessage;
      case 'same_as_email':
        return passwordSameAsEmailMessage;
      case 'same_as_name':
        return passwordSameAsNameMessage;
      case 'common':
        return passwordCommonMessage;
    }
    return weakPasswordMessage;
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
      case 'WEAK_PASSWORD':
        // Sunucu parola ilkesi (en az 8, yaygın olmayan, ad/e-postadan farklı). İstemci doğrulayıcı
        // (lib/ui/helpers/password_policy.dart) genellikle bunu önceden yakalar; `reason` varsa özel ileti.
        return weakPasswordMessageFor(payload?['reason']);
      case 'CONSENT_REQUIRED':
        return LegalMessages.consentRequired;
      case 'CONSENT_VERSION_STALE':
        return LegalMessages.consentVersionStale;
      case 'DOCUMENT_NOT_ACCEPTABLE':
        return LegalMessages.documentNotAcceptable;
      case 'DOCUMENT_INCOMPLETE':
        return LegalMessages.documentIncomplete;
      case 'INVALID_ACCEPTED_DOCUMENTS':
        return LegalMessages.invalidAcceptedDocuments;
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
        return 'Plaka biçimi geçersiz. Örnek: 34 ABC 123 (il kodu 01-81).';
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
      // Site başvurusu (site yöneticisi olma). ALREADY_SITE_MANAGER ve DEVICE_NOT_FOUND yukarıda eşlidir;
      // başvuran bakış açısı için [createSiteApplication] bunları bağlama göre yeniden yazar.
      case 'APPLICATION_REQUIRED':
        return 'Site kurmak için başvuru yapmalısınız.';
      case 'APPLICATION_PENDING':
        return 'Zaten bekleyen bir site başvurunuz var.';
      case 'APPLICATION_NOT_FOUND':
        return 'Başvuru bulunamadı.';
      case 'APPLICATION_NOT_PENDING':
        return 'Bu başvuru artık bekleyen durumda değil.';
      case 'APPLICATION_DATA_INVALID':
        // Yalnız süper kullanıcı onayında (422): kayıtlı yapı verisi geçersizdir.
        return 'Başvurudaki yapı verisi geçersiz; onaylanamaz. Reddedip başvuranın yeniden başvurmasını isteyin.';
      case 'APPLICANT_UNAVAILABLE':
        return 'Başvuran hesap silinmiş, pasif, e-postası doğrulanmamış ya da onaysız olabilir; başvuru onaylanamaz.';
      case 'APPLICATION_DAILY_LIMIT':
        // Sunucu sınırı kayan 24 saattir ("yarın" değil).
        return 'Son 24 saatte en fazla 5 başvuru yapabilirsiniz. Daha sonra tekrar deneyin.';
      case 'PAYMENT_NOT_AVAILABLE':
        return 'Ödeme ile site açma yakında.';
      // Aidat ve Finans (Faz 4a). MODULE_DISABLED ve FORBIDDEN_ROLE yukarıda eşlidir; INVALID_BODY için
      // sunucunun Türkçe metni (alan adı jargonu temizlenmiş) ya da genel yedek metin kullanılır.
      case 'PREVIEW_STALE':
        return 'Veriler önizlemeden sonra değişti. Önizlemeyi yenileyip toplamı kontrol edin.';
      case 'PREVIEW_INCOMPLETE':
        return 'Bazı dairelerin bilgisi eksik. Eksikleri tamamlayın ya da bu daireleri atlayarak devam edin.';
      case 'PERIOD_ALREADY_POSTED':
        return 'Bu tanım bu dönem için zaten borçlandırılmış. Aynı ay ikinci kez borçlandırılamaz.';
      case 'PERIOD_CLOSED':
        return 'Bu dönem kapatılmış; kapalı döneme kayıt eklenemez. Kapalı ayı yalnızca süper kullanıcı yeniden açabilir.';
      case 'PERIOD_NOT_CLOSABLE':
        return 'Bu ay kapatılamaz: zaten kapalı, gelecekte ya da 5 yıldan eski. Listeden bir ay seçin.';
      case 'PERIOD_NOT_REOPENABLE':
        return 'Bu ay yeniden açılamaz. Yalnızca en son kapatılan ay açılabilir.';
      case 'DEFINITION_LOCKED':
        return 'Borçlandırılmış tanımın tutarı ve dağıtımı değiştirilemez. Yeni bir tanım ekleyin.';
      case 'ENTRY_NOT_CORRECTABLE':
        return 'Yalnızca tahsilat düzeltilebilir. Borç için kaydı iptal edin.';
      case 'NOTHING_TO_POST':
        return 'Borçlandırılacak daire bulunamadı. Hedefi ve daire bilgilerini kontrol edin.';
      case 'IDEMPOTENCY_CONFLICT':
        return 'Bu işlem daha önce farklı bilgilerle gönderilmiş görünüyor. Önce daire hesaplarını kontrol edin.';
      case 'DUPLICATE_CHARGE':
        return 'Aynı ek borç kısa süre önce kaydedilmiş görünüyor. Önce daire hesaplarını kontrol edin.';
      case 'DEFINITION_INACTIVE':
        return 'Bu tanım pasif ya da bu dönemde geçerli değil. Tanımı etkinleştirin veya dönemi kontrol edin.';
      case 'ENTRY_ALREADY_REVERSED':
        return 'Bu kayıt zaten iptal edilmiş. Listeyi yenileyip kontrol edin.';
      case 'ENTRY_NOT_REVERSIBLE':
        return 'Bu kayıt iptal ya da düzeltme için uygun değil. Ters kayıtlar iptal edilemez.';
      case 'APARTMENT_HAS_FINANCE':
        return 'Mali kaydı olan daire silinemez.';
      case 'DEFINITION_NOT_FOUND':
        return 'Aidat tanımı bulunamadı.';
      case 'ENTRY_NOT_FOUND':
        return 'Mali kayıt bulunamadı.';
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
    String? deviceToken,
    void Function(String deviceToken)? onDeviceToken,
  }) async {
    final response = await _authorizedRequest(
      method: 'POST',
      path: '/membership/apartments/$apartmentId/members/$targetUserCode/change-password',
      token: token,
      body: {
        'new_password': newPassword,
        'current_password': currentPassword,
      },
      extraHeaders: _deviceTokenHeader(deviceToken),
    );
    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    _emitDeviceToken(payload, onDeviceToken);
    return payload;
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
      mustChangePassword: user['must_change_password'] == true,
      // Deneme erişim kodu oturumu (P2-27): yalnız deneme hesabında dolu; eski sunucuda alan yoktur (null).
      trialExpiresAt: user['trial_expires_at'] is String
          ? DateTime.tryParse(user['trial_expires_at'] as String)?.toLocal()
          : null,
      phoneNumber: user['phone_number'] as String?,
      createdAt: user['created_at'] == null
          ? null
          : DateTime.tryParse(user['created_at'] as String),
    );
  }
}
