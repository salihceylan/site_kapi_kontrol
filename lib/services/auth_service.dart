import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:site_kapi_kontrol/models/super_user_account.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';

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

  Future<String?> createSuperUser({
    required String fullName,
    required String email,
    required String password,
    String? phoneNumber,
  }) async {
    final active = _session;
    if (active == null) {
      return 'Oturum bulunamadi.';
    }
    if (active.role != UserRole.superUser) {
      return 'Bu islem icin super user yetkisi gerekir.';
    }

    try {
      await api.createSuperUser(
        token: active.token,
        fullName: fullName,
        email: email,
        password: password,
        phoneNumber: phoneNumber,
      );
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Sunucuya baglanilamadi.';
    }
  }

  Future<List<SuperUserAccount>> listSuperUsers() async {
    final active = _session;
    if (active == null) {
      throw ApiException('Oturum bulunamadi.');
    }
    if (active.role != UserRole.superUser) {
      throw ApiException('Bu islem icin super user yetkisi gerekir.');
    }

    return api.listSuperUsers(token: active.token);
  }

  Future<String?> updateSuperUser({
    required int userCode,
    String? fullName,
    String? email,
    String? password,
    String? phoneNumber,
  }) async {
    final active = _session;
    if (active == null) {
      return 'Oturum bulunamadi.';
    }
    if (active.role != UserRole.superUser) {
      return 'Bu islem icin super user yetkisi gerekir.';
    }

    try {
      await api.updateSuperUser(
        token: active.token,
        userCode: userCode,
        fullName: fullName,
        email: email,
        password: password,
        phoneNumber: phoneNumber,
      );
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Sunucuya baglanilamadi.';
    }
  }

  Future<String?> deleteSuperUser({
    required int userCode,
  }) async {
    final active = _session;
    if (active == null) {
      return 'Oturum bulunamadi.';
    }
    if (active.role != UserRole.superUser) {
      return 'Bu islem icin super user yetkisi gerekir.';
    }

    try {
      await api.deleteSuperUser(token: active.token, userCode: userCode);
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Sunucuya baglanilamadi.';
    }
  }

  Future<String?> updateMyProfile({
    required String fullName,
    required String email,
    String? phoneNumber,
    String? password,
  }) async {
    final active = _session;
    if (active == null) {
      return 'Oturum bulunamadi.';
    }

    try {
      final updated = await api.updateMyProfile(
        token: active.token,
        id: active.id,
        role: active.role,
        fullName: fullName,
        email: email,
        phoneNumber: phoneNumber,
        password: password,
      );
      _session = updated;
      await _persist();
      notifyListeners();
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Sunucuya baglanilamadi.';
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(_session!.toJson()));
  }
}
