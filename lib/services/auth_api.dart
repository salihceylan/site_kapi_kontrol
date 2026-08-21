import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:site_kapi_kontrol/models/apartment_record.dart';
import 'package:site_kapi_kontrol/models/device_page.dart';
import 'package:site_kapi_kontrol/models/device_record.dart';
import 'package:site_kapi_kontrol/models/door_runtime_status.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/models/managed_user_account.dart';
import 'package:site_kapi_kontrol/models/managed_user_page.dart';
import 'package:site_kapi_kontrol/models/site_page.dart';
import 'package:site_kapi_kontrol/models/site_record.dart';
import 'package:site_kapi_kontrol/models/site_structure_record.dart';
import 'package:site_kapi_kontrol/models/subscription_request.dart';
import 'package:site_kapi_kontrol/models/subscription_request_page.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';

class AuthApi {
  AuthApi({required this.baseUrl});

  static const Duration _requestTimeout = Duration(seconds: 15);
  static const Duration _retryDelay = Duration(milliseconds: 350);

  final String baseUrl;

  Future<UserSession> login({
    required String email,
    required String password,
    required UserRole role,
  }) async {
    return _authRequest(
      path: '/auth/login',
      body: {'email': email, 'password': password, 'role': role.apiValue},
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

  Future<ManagedUserPage> listManagedUsers({
    required String token,
    required UserRole role,
    required int page,
    required int pageSize,
  }) async {
    final uri = Uri.parse('$baseUrl/admin/users').replace(
      queryParameters: {
        'role': role.apiValue,
        'page': '$page',
        'page_size': '$pageSize',
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
  }) async {
    final body = <String, dynamic>{
      'full_name': fullName,
      'email': email,
      'password': password,
      'phone_number': phoneNumber,
      'is_active': isActive,
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

  Future<SitePage> listSites({
    required String token,
    required int page,
    required int pageSize,
    String? approvalStatus,
  }) async {
    final uri = Uri.parse('$baseUrl/admin/sites').replace(
      queryParameters: {
        'page': '$page',
        'page_size': '$pageSize',
        // ignore: use_null_aware_elements
        if (approvalStatus != null) 'approval_status': approvalStatus,
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
    required String name,
    String? address,
    String? city,
    String? district,
    required List<int> blockApartmentCounts,
    required int doorCount,
    int? managerUserCode,
  }) async {
    final totalApartments = blockApartmentCounts.fold<int>(
      0,
      (sum, count) => sum + count,
    );
    final response = await _authorizedRequest(
      method: 'POST',
      path: '/admin/sites',
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
      path: '/admin/sites/$siteCode',
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

  Future<SiteStructureRecord> getSiteStructure({
    required String token,
    required int siteCode,
  }) async {
    final response = await _authorizedRequest(
      method: 'GET',
      path: '/admin/sites/$siteCode/structure',
      token: token,
    );

    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return _parsePayload(
      'Site yapisi',
      () => SiteStructureRecord.fromJson(payload),
    );
  }

  Future<ApartmentRecord> upsertApartmentResident({
    required String token,
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
      path: '/admin/apartments/$apartmentId/resident',
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
    required int apartmentId,
  }) async {
    final response = await _authorizedRequest(
      method: 'POST',
      path: '/admin/apartments/$apartmentId/send-credentials',
      token: token,
    );

    _ensureStatus(response, 200);
  }

  Future<DoorRecord> assignDoorDevice({
    required String token,
    required int doorId,
    required String deviceUid,
  }) async {
    final response = await _authorizedRequest(
      method: 'PATCH',
      path: '/admin/doors/$doorId/device',
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

  Future<void> deleteSite({
    required String token,
    required int siteCode,
  }) async {
    final response = await _authorizedRequest(
      method: 'DELETE',
      path: '/admin/sites/$siteCode',
      token: token,
    );

    _ensureStatus(response, 204, allowEmptyBody: true);
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
    required int page,
    required int pageSize,
  }) async {
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
    required int deviceId,
    int? assignedUserCode,
    int? siteCode,
    String? gateName,
  }) async {
    final response = await _authorizedRequest(
      method: 'PATCH',
      path: '/admin/devices/$deviceId',
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
    required int deviceId,
  }) async {
    final response = await _authorizedRequest(
      method: 'DELETE',
      path: '/admin/devices/$deviceId',
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
    required String deviceUid,
  }) async {
    final response = await _authorizedRequest(
      method: 'POST',
      path: '/admin/devices/mqtt-credentials',
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
  }) async {
    final response = await _authorizedRequest(
      method: 'POST',
      path: '/app/doors/$doorId/open',
      token: token,
    );

    _ensureStatus(response, 202);
    final payload = _decodePayload(response);
    return _parsePayload(
      'Kapi komutu',
      () => DoorRuntimeStatus.fromJson(payload),
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
    String? phoneNumber,
  }) async {
    final body = <String, dynamic>{
      'full_name': fullName,
      'email': email,
      'password': password,
      'phone_number': phoneNumber,
    }..removeWhere((_, value) => value == null);

    final response = await _authorizedRequest(
      method: 'PATCH',
      path: '/me',
      token: token,
      body: body,
    );

    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return _parsePayload('Profil bilgisi', () {
      final user = payload['user'] as Map<String, dynamic>;
      return _toUserSession(
        user: user,
        token: token,
        fallbackId: id,
        fallbackRole: role,
        fallbackIsActive: isActive,
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

    _ensureStatus(response, expectedCode);
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
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };

    switch (method) {
      case 'GET':
        return _sendRequest(method: 'GET', uri: uri, headers: headers);
      case 'DELETE':
        return _sendRequest(method: 'DELETE', uri: uri, headers: headers);
      case 'PATCH':
        return _sendRequest(
          method: 'PATCH',
          uri: uri,
          headers: headers,
          body: body,
        );
      case 'POST':
        return _sendRequest(
          method: 'POST',
          uri: uri,
          headers: headers,
          body: body,
        );
      default:
        throw ArgumentError('Desteklenmeyen method: $method');
    }
  }

  Future<http.Response> _sendRequest({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    Map<String, dynamic>? body,
    bool retryOnTransportError = true,
  }) async {
    Future<http.Response> execute() {
      switch (method) {
        case 'GET':
          return http.get(uri, headers: headers);
        case 'DELETE':
          return http.delete(uri, headers: headers);
        case 'PATCH':
          return http.patch(
            uri,
            headers: headers,
            body: jsonEncode(body ?? <String, dynamic>{}),
          );
        case 'POST':
          return http.post(
            uri,
            headers: headers,
            body: jsonEncode(body ?? <String, dynamic>{}),
          );
        default:
          throw ArgumentError('Desteklenmeyen method: $method');
      }
    }

    try {
      return await execute().timeout(_requestTimeout);
    } on TimeoutException {
      if (retryOnTransportError) {
        await Future<void>.delayed(_retryDelay);
        return _sendRequest(
          method: method,
          uri: uri,
          headers: headers,
          body: body,
          retryOnTransportError: false,
        );
      }
      throw ApiException('Sunucu zaman asimina ugradi. Tekrar deneyin.');
    } on http.ClientException catch (error) {
      if (retryOnTransportError) {
        await Future<void>.delayed(_retryDelay);
        return _sendRequest(
          method: method,
          uri: uri,
          headers: headers,
          body: body,
          retryOnTransportError: false,
        );
      }
      throw ApiException(_mapClientError(error));
    }
  }

  void _ensureStatus(
    http.Response response,
    int expectedCode, {
    bool allowEmptyBody = false,
  }) {
    if (response.statusCode == expectedCode) {
      return;
    }

    if (allowEmptyBody && response.body.trim().isEmpty) {
      return;
    }

    final payload = _decodePayload(response);
    throw ApiException(
      (payload['error'] as String?) ??
          'Islem basarisiz (${response.statusCode})',
    );
  }

  Map<String, dynamic> _decodePayload(http.Response response) {
    if (response.body.trim().isEmpty) {
      return <String, dynamic>{};
    }

    try {
      final raw = jsonDecode(response.body);
      return raw is Map<String, dynamic> ? raw : <String, dynamic>{};
    } on FormatException {
      throw ApiException('Sunucudan gecersiz yanit alindi.');
    }
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
