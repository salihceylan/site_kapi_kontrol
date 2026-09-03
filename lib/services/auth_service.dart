import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:site_kapi_kontrol/models/apartment_record.dart';
import 'package:site_kapi_kontrol/models/device_page.dart';
import 'package:site_kapi_kontrol/models/device_record.dart';
import 'package:site_kapi_kontrol/models/door_access_log_record.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/models/door_runtime_status.dart';
import 'package:site_kapi_kontrol/models/guest_pass.dart';
import 'package:site_kapi_kontrol/models/local_door_access.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:site_kapi_kontrol/models/managed_user_page.dart';
import 'package:site_kapi_kontrol/models/site_page.dart';
import 'package:site_kapi_kontrol/models/site_record.dart';
import 'package:site_kapi_kontrol/models/site_structure_record.dart';
import 'package:site_kapi_kontrol/models/subscription_request_page.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/local_door_service.dart';

class AuthService extends ChangeNotifier {
  AuthService({required this.api});

  static const String _storageKey = 'auth_session';
  static const String _localDoorCacheKey = 'local_door_cache';
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  final AuthApi api;
  final LocalDoorService _localDoorService = LocalDoorService();
  UserSession? _session;
  final Map<String, LocalDoorAccess> _localDoorCache =
      <String, LocalDoorAccess>{};
  bool _isReady = false;
  bool _isDisposed = false;

  UserSession? get session => _session;
  bool get isLoggedIn => _session != null;
  bool get isReady => _isReady;

  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? raw;
      try {
        raw = await _secureStorage.read(key: _storageKey);
      } catch (_) {}

      final legacyRaw = prefs.getString(_storageKey);
      if ((raw == null || raw.isEmpty) && legacyRaw != null && legacyRaw.isNotEmpty) {
        raw = legacyRaw;
        try {
          await _secureStorage.write(key: _storageKey, value: legacyRaw);
        } catch (_) {}
      }

      if (raw != null && raw.isNotEmpty) {
        try {
          final data = jsonDecode(raw) as Map<String, dynamic>;
          _session = UserSession.fromJson(data);
        } catch (_) {
          try {
            await _secureStorage.delete(key: _storageKey);
          } catch (_) {}
          await prefs.remove(_storageKey);
        }
      }

      if (!kIsWeb) {
        await _loadLocalDoorCache();
      }
    } catch (_) {}

    _isReady = true;
    _notifySafely();
  }

  Future<String?> login({
    required String email,
    required String password,
    UserRole? role,
  }) async {
    try {
      _session = await api.login(email: email, password: password, role: role);
      await _persist();
      _notifySafely();
      return null;
    } on ApiException catch (e) {
      _handleSessionError(e);
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
      _handleSessionError(e);
      return e.message;
    } catch (_) {
      return 'Sunucuya baglanilamadi.';
    }
  }

  Future<void> logout() async {
    _session = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storageKey);
    } catch (_) {}
    try {
      await _secureStorage.delete(key: _storageKey);
      await _secureStorage.delete(key: _localDoorCacheKey);
    } catch (_) {}
    _localDoorCache.clear();
    _notifySafely();
  }

  Future<ManagedUserPage> listManagedUsers({
    required UserRole role,
    required int page,
    int pageSize = 10,
    String? search,
  }) async {
    final active = _requireSuperUserSession();
    try {
      return await api.listManagedUsers(
        token: active.token,
        role: role,
        page: page,
        pageSize: pageSize,
        search: search,
      );
    } catch (e) {
      _handleSessionError(e);
      rethrow;
    }
  }

  Future<SitePage> listSites({
    required int page,
    int pageSize = 10,
    String? approvalStatus,
  }) async {
    final active = _requireManagementSession();
    try {
      return await api.listSites(
        token: active.token,
        role: active.role,
        page: page,
        pageSize: pageSize,
        approvalStatus: approvalStatus,
      );
    } catch (e) {
      _handleSessionError(e);
      rethrow;
    }
  }

  Future<SubscriptionRequestPage> listSubscriptionRequests({
    required int page,
    int pageSize = 10,
  }) async {
    final active = _requireSuperUserSession();
    try {
      return await api.listSubscriptionRequests(
        token: active.token,
        page: page,
        pageSize: pageSize,
      );
    } catch (e) {
      _handleSessionError(e);
      rethrow;
    }
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
      _handleSessionError(e);
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
      _handleSessionError(e);
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
      _handleSessionError(e);
      return e.message;
    } catch (_) {
      return 'Sunucuya baglanilamadi.';
    }
  }

  Future<String?> deleteManagedUser({required int userCode}) async {
    final active = _safeRequireSuperUserSession();
    if (active == null) {
      return 'Bu islem icin super user yetkisi gerekir.';
    }

    try {
      await api.deleteManagedUser(token: active.token, userCode: userCode);
      return null;
    } on ApiException catch (e) {
      _handleSessionError(e);
      return e.message;
    } catch (_) {
      return 'Sunucuya baglanilamadi.';
    }
  }

  Future<(SiteRecord?, String?)> createSite({
    required String name,
    String? address,
    String? city,
    String? district,
    required List<int> blockApartmentCounts,
    required int doorCount,
    int? managerUserCode,
    Map<String, dynamic>? managerUser,
  }) async {
    final active = _safeRequireSuperUserSession();
    if (active == null) {
      return (null, 'Bu islem icin super user yetkisi gerekir.');
    }

    try {
      final site = await api.createSite(
        token: active.token,
        role: active.role,
        name: name,
        address: address,
        city: city,
        district: district,
        blockApartmentCounts: blockApartmentCounts,
        doorCount: doorCount,
        managerUserCode: managerUserCode,
        managerUser: managerUser,
      );
      return (site, null);
    } on ApiException catch (e) {
      _handleSessionError(e);
      return (null, e.message);
    } catch (e) {
      return (null, e.toString());
    }
  }

  Future<String?> updateSite({
    required int siteCode,
    String? name,
    String? address,
    String? city,
    String? district,
    List<int>? blockApartmentCounts,
    int? doorCount,
    int? managerUserCode,
  }) async {
    final active = _safeRequireSuperUserSession();
    if (active == null) {
      return 'Bu islem icin super user yetkisi gerekir.';
    }

    try {
      await api.updateSite(
        token: active.token,
        role: active.role,
        siteCode: siteCode,
        name: name,
        address: address,
        city: city,
        district: district,
        blockApartmentCounts: blockApartmentCounts,
        doorCount: doorCount,
        managerUserCode: managerUserCode,
      );
      return null;
    } on ApiException catch (e) {
      _handleSessionError(e);
      return e.message;
    } catch (_) {
      return 'Sunucuya baglanilamadi.';
    }
  }

  Future<String?> deleteSite({required int siteCode}) async {
    final active = _safeRequireSuperUserSession();
    if (active == null) {
      return 'Bu islem icin super user yetkisi gerekir.';
    }

    try {
      await api.deleteSite(token: active.token, siteCode: siteCode);
      return null;
    } on ApiException catch (e) {
      _handleSessionError(e);
      return e.message;
    } catch (_) {
      return 'Sunucuya baglanilamadi.';
    }
  }

  Future<(SiteStructureRecord?, String?)> getSiteStructure({
    required int siteCode,
  }) async {
    final active = _safeRequireManagementSession();
    if (active == null) {
      return (null, 'Bu islem icin site yonetim yetkisi gerekir.');
    }

    try {
      final structure = await api.getSiteStructure(
        token: active.token,
        role: active.role,
        siteCode: siteCode,
      );
      return (structure, null);
    } on ApiException catch (e) {
      _handleSessionError(e);
      return (null, e.message);
    } catch (_) {
      return (null, 'Sunucuya baglanilamadi.');
    }
  }

  Future<(ApartmentRecord?, String?)> upsertApartmentResident({
    required int apartmentId,
    required String fullName,
    required String loginName,
    required String password,
    String? email,
    String? phoneNumber,
    required bool isActive,
  }) async {
    final active = _safeRequireManagementSession();
    if (active == null) {
      return (null, 'Bu islem icin site yonetim yetkisi gerekir.');
    }

    try {
      final apartment = await api.upsertApartmentResident(
        token: active.token,
        role: active.role,
        apartmentId: apartmentId,
        fullName: fullName,
        loginName: loginName,
        password: password,
        email: email,
        phoneNumber: phoneNumber,
        isActive: isActive,
      );
      return (apartment, null);
    } on ApiException catch (e) {
      _handleSessionError(e);
      return (null, e.message);
    } catch (_) {
      return (null, 'Sunucuya baglanilamadi.');
    }
  }

  Future<String?> deleteApartmentResident({required int apartmentId}) async {
    final active = _safeRequireManagementSession();
    if (active == null) {
      return 'Bu islem icin site yonetim yetkisi gerekir.';
    }

    try {
      await api.deleteApartmentResident(
        token: active.token,
        role: active.role,
        apartmentId: apartmentId,
      );
      return null;
    } on ApiException catch (e) {
      _handleSessionError(e);
      return e.message;
    } catch (_) {
      return 'Sunucuya baglanilamadi.';
    }
  }

  Future<String?> sendApartmentCredentials({required int apartmentId}) async {
    final active = _safeRequireManagementSession();
    if (active == null) {
      return 'Bu islem icin site yonetim yetkisi gerekir.';
    }

    try {
      await api.sendApartmentCredentials(
        token: active.token,
        role: active.role,
        apartmentId: apartmentId,
      );
      return null;
    } on ApiException catch (e) {
      _handleSessionError(e);
      return e.message;
    } catch (_) {
      return 'Sunucuya baglanilamadi.';
    }
  }

  Future<(DoorAccessLogPage?, String?)> listDoorAccessLogs({
    int? siteCode,
    int? doorId,
    String? search,
    DateTime? startDate,
    DateTime? endDate,
    int page = 1,
    int pageSize = 50,
  }) async {
    final active = _safeRequireManagementSession();
    if (active == null) {
      return (null, 'Bu islem icin site yonetim yetkisi gerekir.');
    }

    try {
      final logPage = await api.listDoorAccessLogs(
        token: active.token,
        role: active.role,
        siteCode: siteCode,
        doorId: doorId,
        search: search,
        startDate: startDate,
        endDate: endDate,
        page: page,
        pageSize: pageSize,
      );
      return (logPage, null);
    } on ApiException catch (e) {
      _handleSessionError(e);
      return (null, e.message);
    } catch (_) {
      return (null, 'Sunucuya baglanilamadi.');
    }
  }

  Future<(DoorRecord?, String?)> assignDoorDevice({
    required int doorId,
    required String deviceUid,
  }) async {
    final active = _safeRequireManagementSession();
    if (active == null) {
      return (null, 'Bu islem icin site yonetim yetkisi gerekir.');
    }

    try {
      final door = await api.assignDoorDevice(
        token: active.token,
        role: active.role,
        doorId: doorId,
        deviceUid: deviceUid,
      );
      return (door, null);
    } on ApiException catch (e) {
      _handleSessionError(e);
      return (null, e.message);
    } catch (_) {
      return (null, 'Sunucuya baglanilamadi.');
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
      _handleSessionError(e);
      return (null, e.message);
    } catch (_) {
      return (null, 'Sunucuya baglanilamadi.');
    }
  }

  Future<(DevicePage?, String?)> listCompanyDevices({
    required int page,
    required int pageSize,
  }) async {
    final active = _safeRequireManagementSession();
    if (active == null) {
      return (null, 'Bu islem icin site yonetim yetkisi gerekir.');
    }

    try {
      final devices = await api.listCompanyDevices(
        token: active.token,
        role: active.role,
        page: page,
        pageSize: pageSize,
      );
      return (devices, null);
    } on ApiException catch (e) {
      _handleSessionError(e);
      return (null, e.message);
    } catch (_) {
      return (null, 'Sunucuya baglanilamadi.');
    }
  }

  Future<(DeviceRecord?, String?)> updateDevice({
    required int deviceId,
    int? assignedUserCode,
    int? siteCode,
    String? gateName,
  }) async {
    final active = _safeRequireManagementSession();
    if (active == null) {
      return (null, 'Bu islem icin site yonetim yetkisi gerekir.');
    }

    try {
      final device = await api.updateDevice(
        token: active.token,
        role: active.role,
        deviceId: deviceId,
        assignedUserCode: assignedUserCode,
        siteCode: siteCode,
        gateName: gateName,
      );
      return (device, null);
    } on ApiException catch (e) {
      _handleSessionError(e);
      return (null, e.message);
    } catch (_) {
      return (null, 'Sunucuya baglanilamadi.');
    }
  }

  Future<String?> deleteDevice({required int deviceId}) async {
    final active = _safeRequireSuperUserSession();
    if (active == null) {
      return 'Bu islem icin super user yetkisi gerekir.';
    }

    try {
      await api.deleteDevice(
        token: active.token,
        role: active.role,
        deviceId: deviceId,
      );
      return null;
    } on ApiException catch (e) {
      _handleSessionError(e);
      return e.message;
    } catch (_) {
      return 'Sunucuya baglanilamadi.';
    }
  }

  Future<(Map<String, dynamic>?, String?)> broadcastOtaCheck() async {
    final active = _safeRequireSuperUserSession();
    if (active == null) {
      return (null, 'Bu islem icin super user yetkisi gerekir.');
    }

    try {
      final result = await api.broadcastOtaCheck(token: active.token);
      return (result, null);
    } on ApiException catch (e) {
      _handleSessionError(e);
      return (null, e.message);
    } catch (_) {
      return (null, 'Sunucuya baglanilamadi.');
    }
  }

  Future<(Map<String, dynamic>?, String?)> getDeviceMqttCredentials({
    required String deviceUid,
  }) async {
    final active = _safeRequireManagementSession();
    if (active == null) {
      return (null, 'Bu islem icin site yonetim yetkisi gerekir.');
    }

    try {
      final result = await api.getDeviceMqttCredentials(
        token: active.token,
        role: active.role,
        deviceUid: deviceUid,
      );
      return (result, null);
    } on ApiException catch (e) {
      _handleSessionError(e);
      return (null, e.message);
    } catch (_) {
      return (null, 'Sunucuya baglanilamadi.');
    }
  }

  Future<(DoorRuntimeStatus?, String?)> getDoorRuntimeStatus({
    required int doorId,
  }) async {
    final active = session;
    if (active == null) {
      return (null, 'Oturum bulunamadi.');
    }

    try {
      final status = await api.getDoorRuntimeStatus(
        token: active.token,
        doorId: doorId,
      );
      await _cacheLocalDoorAccess(status);
      return (status, null);
    } on ApiException catch (e) {
      _handleSessionError(e);
      return (null, e.message);
    } catch (_) {
      return (null, 'Sunucuya baglanilamadi.');
    }
  }

  Future<(DoorRuntimeStatus?, String?)> openDoor({
    required int doorId,
    DoorRecord? door,
  }) async {
    final active = session;
    if (active == null) {
      return (null, 'Oturum bulunamadi.');
    }

    Future<(DoorRuntimeStatus?, String?)> cloudFuture() async {
      try {
        final status = await api.openDoor(token: active.token, doorId: doorId);
        unawaited(_cacheLocalDoorAccess(status));
        return (status, null);
      } on ApiException catch (e) {
        return (null, e.message);
      } catch (_) {
        return (null, 'Sunucuya baglanilamadi.');
      }
    }

    final hasLocal = door != null && canTryLocalDoorOpen(door);

    if (hasLocal) {
      final completer = Completer<(DoorRuntimeStatus?, String?)>();
      var cloudFinished = false;
      var localFinished = false;
      (DoorRuntimeStatus?, String?)? cloudResult;
      (DoorRuntimeStatus?, String?)? localResult;

      cloudFuture().then((res) {
        cloudFinished = true;
        cloudResult = res;
        if (res.$1 != null && !completer.isCompleted) {
          completer.complete(res);
        } else if (localFinished && !completer.isCompleted) {
          completer.complete(
            localResult?.$1 != null
                ? localResult
                : (localResult ?? res),
          );
        }
      });

      _tryOpenDoorLocally(door).then((res) {
        localFinished = true;
        localResult = res;
        if (res != null && res.$1 != null && !completer.isCompleted) {
          completer.complete(res);
        } else if (cloudFinished && !completer.isCompleted) {
          completer.complete(
            res?.$1 != null
                ? res
                : (res ?? cloudResult ?? (null, 'Kapı açılamadı.')),
          );
        }
      });

      return await completer.future.timeout(
        const Duration(seconds: 6),
        onTimeout: () =>
            localResult ?? cloudResult ?? (null, 'Kapı açma komutu zaman aşımına uğradı.'),
      );
    }

    return await cloudFuture();
  }

  bool canTryLocalDoorOpen(DoorRecord door) {
    final uid = door.assignedDeviceUid?.trim().toUpperCase();
    if (uid == null || uid.isEmpty) {
      return false;
    }
    return true;
  }

  Future<(List<DoorRecord>?, String?)> listMyDoors() async {
    final active = session;
    if (active == null) {
      return (null, 'Oturum bulunamadi.');
    }

    try {
      final doors = await api.listMyDoors(token: active.token);
      return (doors, null);
    } on ApiException catch (e) {
      _handleSessionError(e);
      return (null, e.message);
    } catch (_) {
      return (null, 'Sunucuya baglanilamadi.');
    }
  }

  Future<String?> resolveSubscriptionRequest({
    required int userCode,
    required String action,
  }) async {
    final active = _safeRequireSuperUserSession();
    if (active == null) {
      return 'Bu islem icin super user yetkisi gerekir.';
    }

    try {
      await api.resolveSubscriptionRequest(
        token: active.token,
        userCode: userCode,
        action: action,
      );
      return null;
    } on ApiException catch (e) {
      _handleSessionError(e);
      return e.message;
    } catch (_) {
      return 'Sunucuya baglanilamadi.';
    }
  }

  Future<String?> resolveSiteApproval({
    required int siteCode,
    required String action,
  }) async {
    final active = _safeRequireSuperUserSession();
    if (active == null) {
      return 'Bu islem icin super user yetkisi gerekir.';
    }

    try {
      await api.resolveSiteApproval(
        token: active.token,
        siteCode: siteCode,
        action: action,
      );
      return null;
    } on ApiException catch (e) {
      _handleSessionError(e);
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
      _handleSessionError(e);
      return e.message;
    } catch (_) {
      return 'Sunucuya baglanilamadi.';
    }
  }

  Future<(GuestPassRecord?, String?)> createGuestPass({
    required int doorId,
    required String title,
    required String passType,
    int? durationMinutes,
    int? maxUses,
  }) async {
    final active = _session;
    if (active == null) {
      return (null, 'Oturum bulunamadi.');
    }

    try {
      final pass = await api.createGuestPass(
        token: active.token,
        doorId: doorId,
        title: title,
        passType: passType,
        durationMinutes: durationMinutes,
        maxUses: maxUses,
      );
      return (pass, null);
    } on ApiException catch (e) {
      _handleSessionError(e);
      return (null, e.message);
    } catch (_) {
      return (null, 'Sunucuya baglanilamadi.');
    }
  }

  Future<(List<GuestPassRecord>?, String?)> listGuestPasses() async {
    final active = _session;
    if (active == null) {
      return (null, 'Oturum bulunamadi.');
    }

    try {
      final passes = await api.listGuestPasses(token: active.token);
      return (passes, null);
    } on ApiException catch (e) {
      _handleSessionError(e);
      return (null, e.message);
    } catch (_) {
      return (null, 'Sunucuya baglanilamadi.');
    }
  }

  Future<String?> revokeGuestPass(int passId) async {
    final active = _session;
    if (active == null) {
      return 'Oturum bulunamadi.';
    }

    try {
      await api.revokeGuestPass(token: active.token, passId: passId);
      return null;
    } on ApiException catch (e) {
      _handleSessionError(e);
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

  UserSession _requireManagementSession() {
    final active = _safeRequireManagementSession();
    if (active == null) {
      throw ApiException('Bu islem icin site yonetim yetkisi gerekir.');
    }
    return active;
  }

  UserSession? _safeRequireManagementSession() {
    final active = _session;
    if (active == null || active.role == UserRole.apartmentOwner) {
      return null;
    }
    return active;
  }

  void _handleSessionError(Object error) {
    if (error is SessionExpiredException ||
        (error is ApiException && error.isUnauthorized)) {
      logout();
    }
  }

  Future<void> _persist() async {
    if (_session == null) {
      return;
    }
    final raw = jsonEncode(_session!.toJson());
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, raw);
    } catch (_) {}
    try {
      await _secureStorage.write(
        key: _storageKey,
        value: raw,
      );
    } catch (_) {}
  }

  Future<void> _loadLocalDoorCache() async {
    if (kIsWeb) {
      return;
    }
    _localDoorCache.clear();
    String? raw;
    try {
      raw = await _secureStorage.read(key: _localDoorCacheKey);
    } catch (_) {}
    if (raw == null || raw.isEmpty) {
      return;
    }
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      for (final entry in decoded.entries) {
        final value = entry.value;
        if (value is! Map<String, dynamic>) {
          continue;
        }
        final access = LocalDoorAccess.fromJson(value);
        if (access.isUsable) {
          _localDoorCache[access.deviceUid.toUpperCase()] = access;
        }
      }
    } catch (_) {
      try {
        await _secureStorage.delete(key: _localDoorCacheKey);
      } catch (_) {}
    }
  }

  Future<void> _persistLocalDoorCache() async {
    if (kIsWeb) {
      return;
    }
    final data = _localDoorCache.map(
      (key, value) => MapEntry(key, value.toJson()),
    );
    try {
      await _secureStorage.write(
        key: _localDoorCacheKey,
        value: jsonEncode(data),
      );
    } catch (_) {}
  }

  Future<void> _cacheLocalDoorAccess(DoorRuntimeStatus status) async {
    final uid = status.deviceUid.trim().toUpperCase();
    final token = status.localControlToken?.trim() ?? '';
    if (uid.isEmpty || token.isEmpty) {
      return;
    }

    _localDoorCache[uid] = LocalDoorAccess(
      deviceUid: uid,
      token: token,
      ip: status.localIp,
      port: status.localControlPort ?? 8765,
      updatedAt: DateTime.now(),
    );
    await _persistLocalDoorCache();
  }

  Future<(DoorRuntimeStatus?, String?)?> _tryOpenDoorLocally(
    DoorRecord door,
  ) async {
    final uid = door.assignedDeviceUid?.trim().toUpperCase();
    if (uid == null || uid.isEmpty) {
      return null;
    }

    final cached = _localDoorCache[uid];
    final access = cached ??
        LocalDoorAccess(
          deviceUid: uid,
          token: '',
          ip: null,
          port: 8765,
          updatedAt: DateTime.now(),
        );

    final result = await _localDoorService.openDoor(access);
    if (!result.ok) {
      return (null, result.message);
    }

    final updatedAccess = LocalDoorAccess(
      deviceUid: access.deviceUid,
      token: access.token,
      ip: result.ip ?? access.ip,
      port: access.port,
      updatedAt: DateTime.now(),
    );
    _localDoorCache[uid] = updatedAccess;
    await _persistLocalDoorCache();

    final active = session;
    if (active != null) {
      unawaited(
        api
            .notifyLocalDoorOpened(
              token: active.token,
              doorId: door.id,
              localIp: result.ip ?? access.ip,
            )
            .catchError((_) {}),
      );
    }

    return (
      DoorRuntimeStatus(
        door: door,
        deviceUid: uid,
        mqttBridgeConnected: false,
        mqttConnected: false,
        doorLocked: false,
        firmwareVersion: null,
        otaStatus: 'yerel komut',
        wifiRssi: null,
        wifiSignalPercent: null,
        localIp: updatedAccess.ip,
        localControlPort: updatedAccess.port,
        localControlToken: updatedAccess.token,
        localControlAvailable: true,
        lastEvent: 'local_pulse_started',
        lastSeenAt: DateTime.now(),
      ),
      null,
    );
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
    _localDoorService.dispose();
    super.dispose();
  }
}
