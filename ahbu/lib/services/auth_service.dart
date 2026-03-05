import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ahbu/models/user_role.dart';
import 'package:ahbu/models/user_session.dart';
import 'package:ahbu/services/api_exception.dart';
import 'package:ahbu/services/auth_api.dart';

class AuthService extends ChangeNotifier {
  AuthService({required this.api});

  static const String _storageKey = 'auth_session';

  final AuthApi api;
  UserSession? _session;
  bool _isReady = false;

  UserSession? get session => _session;
  bool get isLoggedIn => _session != null;
  bool get isReady => _isReady;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);

    if (raw != null && raw.isNotEmpty) {
      try {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        _session = UserSession.fromJson(data);
      } catch (_) {
        await prefs.remove(_storageKey);
      }
    }

    _isReady = true;
    notifyListeners();
  }

  Future<String?> login({
    required String email,
    required String password,
    required UserRole role,
  }) async {
    try {
      _session = await api.login(email: email, password: password, role: role);
      await _persist();
      notifyListeners();
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Sunucuya baglanilamadi.';
    }
  }

  Future<String?> register({
    required String fullName,
    required String email,
    required String password,
    required UserRole role,
    String? phoneNumber,
  }) async {
    try {
      _session = await api.register(
        fullName: fullName,
        email: email,
        password: password,
        role: role,
        phoneNumber: phoneNumber,
      );
      await _persist();
      notifyListeners();
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Sunucuya baglanilamadi.';
    }
  }

  Future<void> logout() async {
    _session = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(_session!.toJson()));
  }
}
