import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:site_kapi_kontrol/models/apartment_record.dart';
import 'package:site_kapi_kontrol/models/device_record.dart';
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

    final response = await http.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    _ensureStatus(response, 200);

    final payload = _decodePayload(response);
    final users = (payload['users'] as List<dynamic>? ?? <dynamic>[])
        .map((item) => ManagedUserAccount.fromJson(item as Map<String, dynamic>))
        .toList();

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
  }) async {
    final uri = Uri.parse('$baseUrl/admin/sites').replace(
      queryParameters: {
        'page': '$page',
        'page_size': '$pageSize',
      },
    );

    final response = await http.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    final sites = (payload['sites'] as List<dynamic>? ?? <dynamic>[])
        .map((item) => SiteRecord.fromJson(item as Map<String, dynamic>))
        .toList();

    return SitePage(
      sites: sites,
      total: payload['total'] as int? ?? 0,
      page: payload['page'] as int? ?? page,
      pageSize: payload['page_size'] as int? ?? pageSize,
    );
  }

  Future<SiteRecord> createSite({
    required String token,
    required String name,
    String? address,
    String? city,
    String? district,
    required int blockCount,
    required int apartmentCount,
    required int doorCount,
    int? managerUserCode,
  }) async {
    final response = await _authorizedRequest(
      method: 'POST',
      path: '/admin/sites',
      token: token,
      body: {
        'name': name,
        'address': address,
        'city': city,
        'district': district,
        'block_count': blockCount,
        'apartment_count': apartmentCount,
        'door_count': doorCount,
        'manager_user_code': managerUserCode,
      },
    );

    _ensureStatus(response, 201);
    final payload = _decodePayload(response);
    return SiteRecord.fromJson(payload['site'] as Map<String, dynamic>);
  }

  Future<SiteRecord> updateSite({
    required String token,
    required int siteCode,
    String? name,
    String? address,
    String? city,
    String? district,
    int? blockCount,
    int? apartmentCount,
    int? doorCount,
    int? managerUserCode,
  }) async {
    final body = <String, dynamic>{
      'name': name,
      'address': address,
      'city': city,
      'district': district,
      'block_count': blockCount,
      'apartment_count': apartmentCount,
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
    return SiteRecord.fromJson(payload['site'] as Map<String, dynamic>);
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
    return SiteStructureRecord.fromJson(payload);
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
    return ApartmentRecord.fromJson(payload['apartment'] as Map<String, dynamic>);
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
      body: {
        'device_uid': deviceUid,
      },
    );

    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return DoorRecord.fromJson(payload['door'] as Map<String, dynamic>);
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
    return DeviceRecord.fromJson(payload['device'] as Map<String, dynamic>);
  }

  Future<SubscriptionRequestPage> listSubscriptionRequests({
    required String token,
    required int page,
    required int pageSize,
  }) async {
    final uri = Uri.parse('$baseUrl/admin/subscription-requests').replace(
      queryParameters: {
        'page': '$page',
        'page_size': '$pageSize',
      },
    );

    final response = await http.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    final requests = (payload['requests'] as List<dynamic>? ?? <dynamic>[])
        .map((item) => SubscriptionRequest.fromJson(item as Map<String, dynamic>))
        .toList();

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
    final user = payload['user'] as Map<String, dynamic>;
    return _toUserSession(
      user: user,
      token: token,
      fallbackId: id,
      fallbackRole: role,
      fallbackIsActive: isActive,
    );
  }

  Future<UserSession> _authRequest({
    required String path,
    required Map<String, dynamic> body,
    required int expectedCode,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );

    _ensureStatus(response, expectedCode);
    final payload = _decodePayload(response);
    final user = payload['user'] as Map<String, dynamic>;
    return _toUserSession(
      user: user,
      token: payload['token'] as String,
      fallbackId: user['id'] as int,
      fallbackRole: UserRole.fromApi(user['role'] as String),
      fallbackIsActive: user['is_active'] as bool? ?? true,
    );
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
        return http.get(uri, headers: headers);
      case 'DELETE':
        return http.delete(uri, headers: headers);
      case 'PATCH':
        return http.patch(uri, headers: headers, body: jsonEncode(body ?? {}));
      case 'POST':
        return http.post(uri, headers: headers, body: jsonEncode(body ?? {}));
      default:
        throw ArgumentError('Desteklenmeyen method: $method');
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

    final raw = jsonDecode(response.body);
    return raw is Map<String, dynamic> ? raw : <String, dynamic>{};
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
