import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:site_kapi_kontrol/models/super_user_account.dart';
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

  Future<void> createSuperUser({
    required String token,
    required String fullName,
    required String email,
    required String password,
    String? phoneNumber,
  }) async {
    final response = await _authorizedRequest(
      method: 'POST',
      path: '/admin/super-users',
      token: token,
      body: {
        'full_name': fullName,
        'email': email,
        'password': password,
        'phone_number': phoneNumber,
      },
    );
    _ensureStatus(response, 201);
  }

  Future<List<SuperUserAccount>> listSuperUsers({
    required String token,
  }) async {
    final response = await _authorizedRequest(
      method: 'GET',
      path: '/admin/super-users',
      token: token,
    );
    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    final users = (payload['users'] as List<dynamic>? ?? <dynamic>[])
        .cast<Map<String, dynamic>>();
    return users.map(SuperUserAccount.fromJson).toList();
  }

  Future<void> updateSuperUser({
    required String token,
    required int userCode,
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
      path: '/admin/super-users/$userCode',
      token: token,
      body: body,
    );
    _ensureStatus(response, 200);
  }

  Future<void> deleteSuperUser({
    required String token,
    required int userCode,
  }) async {
    final response = await _authorizedRequest(
      method: 'DELETE',
      path: '/admin/super-users/$userCode',
      token: token,
    );
    _ensureStatus(response, 204, allowEmptyBody: true);
  }

  Future<UserSession> updateMyProfile({
    required String token,
    required int id,
    required UserRole role,
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
  }) {
    return UserSession(
      id: user['id'] as int? ?? fallbackId,
      fullName: user['full_name'] as String,
      email: user['email'] as String,
      role: user['role'] == null
          ? fallbackRole
          : UserRole.fromApi(user['role'] as String),
      token: token,
      phoneNumber: user['phone_number'] as String?,
      createdAt: user['created_at'] == null
          ? null
          : DateTime.tryParse(user['created_at'] as String),
    );
  }
}
