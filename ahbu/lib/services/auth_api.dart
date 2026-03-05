import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:ahbu/models/user_role.dart';
import 'package:ahbu/models/user_session.dart';
import 'package:ahbu/services/api_exception.dart';

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

    final payload =
        (jsonDecode(response.body) as Map<String, dynamic>?) ??
        <String, dynamic>{};

    if (response.statusCode != expectedCode) {
      throw ApiException(
        (payload['error'] as String?) ??
            'Islem basarisiz (${response.statusCode})',
      );
    }

    final user = payload['user'] as Map<String, dynamic>;
    return UserSession(
      id: user['id'] as int,
      fullName: user['full_name'] as String,
      email: user['email'] as String,
      role: UserRole.fromApi(user['role'] as String),
      token: payload['token'] as String,
      phoneNumber: user['phone_number'] as String?,
      createdAt: user['created_at'] == null
          ? null
          : DateTime.tryParse(user['created_at'] as String),
    );
  }
}
