import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/device_record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:site_kapi_kontrol/models/managed_user_page.dart';
import 'package:site_kapi_kontrol/models/site_page.dart';
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
  bool _isDisposed = false;

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
    _notifySafely();
  }

  Future<String?> login({
    required String email,
    required String password,
    required UserRole role,
  }) async {
    try {
      _session = await api.login(email: email, password: password, role: role);
      await _persist();
      _notifySafely();
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
      _notifySafely();
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
    _notifySafely();
  }

  Future<ManagedUserPage> listManagedUsers({
    required UserRole role,
    required int page,
    int pageSize = 10,
  }) async {
    final active = _requireSuperUserSession();
    return api.listManagedUsers(
      token: active.token,
      role: role,
      page: page,
      pageSize: pageSize,
    );
  }

  Future<SitePage> listSites({
    required int page,
    int pageSize = 10,
  }) async {
    final active = _requireSuperUserSession();
    return api.listSites(
      token: active.token,
      page: page,
      pageSize: pageSize,
    );
  }

  Future<String?> createManagedUser({
    required String fullName,
    required String email,
    required String password,
    required UserRole role,
    required bool isActive,
    String? phoneNumber,
  }) async {
    final active = _safeRequireSuperUserSession();
    if (active == null) {
      return 'Bu islem icin super user yetkisi gerekir.';
    }

    try {
      await api.createManagedUser(
        token: active.token,
        fullName: fullName,
        email: email,
        password: password,
        role: role,
        isActive: isActive,
        phoneNumber: phoneNumber,
      );
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Sunucuya baglanilamadi.';
    }
  }

  Future<String?> updateManagedUser({
    required int userCode,
    String? fullName,
    String? email,
    String? password,
    String? phoneNumber,
    bool? isActive,
  }) async {
    final active = _safeRequireSuperUserSession();
    if (active == null) {
      return 'Bu islem icin super user yetkisi gerekir.';
    }

    try {
      await api.updateManagedUser(
        token: active.token,
        userCode: userCode,
        fullName: fullName,
        email: email,
        password: password,
        phoneNumber: phoneNumber,
        isActive: isActive,
      );
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Sunucuya baglanilamadi.';
    }
  }

  Future<String?> setManagedUserActivation({
    required int userCode,
    required bool isActive,
  }) async {
    final active = _safeRequireSuperUserSession();
    if (active == null) {
      return 'Bu islem icin super user yetkisi gerekir.';
    }

    try {
      await api.setManagedUserActivation(
        token: active.token,
        userCode: userCode,
        isActive: isActive,
      );
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Sunucuya baglanilamadi.';
    }
  }

  Future<String?> deleteManagedUser({
    required int userCode,
  }) async {
    final active = _safeRequireSuperUserSession();
    if (active == null) {
      return 'Bu islem icin super user yetkisi gerekir.';
    }

    try {
      await api.deleteManagedUser(token: active.token, userCode: userCode);
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Sunucuya baglanilamadi.';
    }
  }

  Future<String?> createSite({
    required String name,
    String? address,
    String? city,
    String? district,
  }) async {
    final active = _safeRequireSuperUserSession();
    if (active == null) {
      return 'Bu islem icin super user yetkisi gerekir.';
    }

    try {
      await api.createSite(
        token: active.token,
        name: name,
        address: address,
        city: city,
        district: district,
      );
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Sunucuya baglanilamadi.';
    }
  }

  Future<String?> updateSite({
    required int siteCode,
    String? name,
    String? address,
    String? city,
    String? district,
  }) async {
    final active = _safeRequireSuperUserSession();
    if (active == null) {
      return 'Bu islem icin super user yetkisi gerekir.';
    }

    try {
      await api.updateSite(
        token: active.token,
        siteCode: siteCode,
        name: name,
        address: address,
        city: city,
        district: district,
      );
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Sunucuya baglanilamadi.';
    }
  }

  Future<String?> deleteSite({
    required int siteCode,
  }) async {
    final active = _safeRequireSuperUserSession();
    if (active == null) {
      return 'Bu islem icin super user yetkisi gerekir.';
    }

    try {
      await api.deleteSite(token: active.token, siteCode: siteCode);
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Sunucuya baglanilamadi.';
    }
  }

  Future<(DeviceRecord?, String?)> createDevice({
    required String deviceUid,
    int? assignedUserCode,
    int? siteCode,
  }) async {
    final active = _safeRequireSuperUserSession();
    if (active == null) {
      return (null, 'Bu islem icin super user yetkisi gerekir.');
    }

    try {
      final device = await api.createDevice(
        token: active.token,
        deviceUid: deviceUid,
        assignedUserCode: assignedUserCode,
        siteCode: siteCode,
      );
      return (device, null);
    } on ApiException catch (e) {
      return (null, e.message);
    } catch (_) {
      return (null, 'Sunucuya baglanilamadi.');
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
        isActive: active.isActive,
        fullName: fullName,
        email: email,
        phoneNumber: phoneNumber,
        password: password,
      );
      _session = updated;
      await _persist();
      _notifySafely();
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Sunucuya baglanilamadi.';
    }
  }

  UserSession _requireSuperUserSession() {
    final active = _safeRequireSuperUserSession();
    if (active == null) {
      throw ApiException('Bu islem icin super user yetkisi gerekir.');
    }
    return active;
  }

  UserSession? _safeRequireSuperUserSession() {
    final active = _session;
    if (active == null) {
      return null;
    }
    if (active.role != UserRole.superUser) {
      return null;
    }
    return active;
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(_session!.toJson()));
  }

  void _notifySafely() {
    if (_isDisposed) {
      return;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}
