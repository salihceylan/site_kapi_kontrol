import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:site_kapi_kontrol/models/apartment_record.dart';
import 'package:site_kapi_kontrol/models/device_connectivity_log.dart';
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
import 'package:site_kapi_kontrol/models/site_join_token_record.dart';
import 'package:site_kapi_kontrol/models/join_request_record.dart';
import 'package:site_kapi_kontrol/models/site_join_info.dart';
import 'package:site_kapi_kontrol/models/apartment_member_record.dart';
import 'package:site_kapi_kontrol/models/door_permission_record.dart';
import 'package:site_kapi_kontrol/models/site_residents_tree_record.dart';
import 'package:site_kapi_kontrol/models/site_structure_record.dart';
import 'package:site_kapi_kontrol/models/site_manager_record.dart';
import 'package:site_kapi_kontrol/models/subscription_request_page.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/door_widget_service.dart';
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

  Future<String?> registerIndividual({
    required String firstName,
    required String lastName,
    required String email,
    required String password,
  }) async {
    try {
      await api.registerIndividual(
        firstName: firstName,
        lastName: lastName,
        email: email,
        password: password,
      );
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Sunucuya bağlanılamadı. Lütfen internet bağlantınızı kontrol ediniz.';
    }
  }

  Future<String?> verifyIndividualCode({
    required String email,
    required String code,
  }) async {
    try {
      _session = await api.verifyIndividualCode(
        email: email,
        code: code,
      );
      await _persist();
      _notifySafely();
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Doğrulama işlemi sırasında hata oluştu.';
    }
  }

  Future<String?> resendIndividualCode({
    required String email,
  }) async {
    try {
      await api.resendIndividualCode(email: email);
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Kod tekrar gönderilemedi.';
    }
  }

  Future<Map<String, dynamic>> claimDevice({
    required String deviceInput,
  }) async {
    final token = _session?.token;
    if (token == null) {
      throw ApiException('Oturum açmanız gerekmektedir.');
    }
    final res = await api.claimDevice(token: token, deviceInput: deviceInput);
    if (_session != null && _session!.role != UserRole.superUser) {
      _session = _session!.copyWith(role: UserRole.siteManager);
      await _persist();
      _notifySafely();
    }
    return res;
  }

  Future<List<Map<String, dynamic>>> getMyClaimedDevices() async {
    final token = _session?.token;
    if (token == null) {
      return [];
    }
    try {
      final devices = await api.getMyClaimedDevices(token: token);
      if (devices.isNotEmpty && _session != null && _session!.role == UserRole.individual) {
        _session = _session!.copyWith(role: UserRole.siteManager);
        await _persist();
        _notifySafely();
      }
      return devices;
    } catch (_) {
      return [];
    }
  }

  Future<Map<String, dynamic>> setupSite({
    required String name,
    String? city,
    String? district,
    String? address,
    required List<Map<String, dynamic>> blocks,
    List<Map<String, dynamic>>? doors,
    int doorCount = 1,
    String? deviceUid,
  }) async {
    final token = _session?.token;
    if (token == null) {
      throw ApiException('Oturum açmanız gerekmektedir.');
    }
    final res = await api.setupSite(
      token: token,
      name: name,
      city: city,
      district: district,
      address: address,
      blocks: blocks,
      doors: doors,
      doorCount: doorCount,
      deviceUid: deviceUid,
    );
    if (_session != null && _session!.role != UserRole.superUser) {
      _session = _session!.copyWith(role: UserRole.siteManager);
      await _persist();
      _notifySafely();
    }
    return res;
  }

  Future<Map<String, dynamic>> createDoor({
    required int siteCode,
    required String doorName,
    String accessScope = 'SITE_COMMON',
    int? blockId,
    String? deviceUid,
  }) async {
    final token = _session?.token;
    if (token == null) throw ApiException('Oturum açmanız gerekmektedir.');
    final res = await api.createDoor(
      token: token,
      siteCode: siteCode,
      doorName: doorName,
      accessScope: accessScope,
      blockId: blockId,
      deviceUid: deviceUid,
    );
    _notifySafely();
    return res;
  }

  Future<Map<String, dynamic>> updateDoor({
    required int doorId,
    String? doorName,
    String? accessScope,
    int? blockId,
    bool? isActive,
  }) async {
    final token = _session?.token;
    if (token == null) throw ApiException('Oturum açmanız gerekmektedir.');
    final res = await api.updateDoor(
      token: token,
      doorId: doorId,
      doorName: doorName,
      accessScope: accessScope,
      blockId: blockId,
      isActive: isActive,
    );
    _notifySafely();
    return res;
  }

  Future<void> deleteDoor({required int doorId}) async {
    final token = _session?.token;
    if (token == null) throw ApiException('Oturum açmanız gerekmektedir.');
    await api.deleteDoor(token: token, doorId: doorId);
    _notifySafely();
  }

  Future<Map<String, dynamic>> unassignDoorDevice({required int doorId}) async {
    final token = _session?.token;
    if (token == null) throw ApiException('Oturum açmanız gerekmektedir.');
    final res = await api.unassignDoorDevice(token: token, doorId: doorId);
    _notifySafely();
    return res;
  }

  Future<Map<String, dynamic>> replaceDoorDevice({
    required int doorId,
    String? deviceInput,
    int? deviceId,
  }) async {
    final token = _session?.token;
    if (token == null) throw ApiException('Oturum açmanız gerekmektedir.');
    final res = await api.replaceDoorDevice(
      token: token,
      doorId: doorId,
      deviceInput: deviceInput,
      deviceId: deviceId,
    );
    _notifySafely();
    return res;
  }

  Future<List<Map<String, dynamic>>> getAssignableDevices({required int siteCode}) async {
    final token = _session?.token;
    if (token == null) return [];
    try {
      return await api.getAssignableDevices(token: token, siteCode: siteCode);
    } catch (_) {
      return [];
    }
  }

  Future<SiteJoinTokenRecord> getSiteJoinToken({required int siteCode}) async {
    final token = _session?.token;
    if (token == null) throw ApiException('Oturum açmanız gerekmektedir.');
    return await api.getSiteJoinToken(token: token, siteCode: siteCode);
  }

  Future<SiteJoinTokenRecord> rotateSiteJoinToken({required int siteCode}) async {
    final token = _session?.token;
    if (token == null) throw ApiException('Oturum açmanız gerekmektedir.');
    final res = await api.rotateSiteJoinToken(token: token, siteCode: siteCode);
    _notifySafely();
    return res;
  }

  Future<Map<String, dynamic>> getSiteJoinInfo({required String joinToken}) async {
    final token = _session?.token;
    if (token == null) throw ApiException('Oturum açmanız gerekmektedir.');
    return await api.getSiteJoinInfo(token: token, joinToken: joinToken);
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
    unawaited(DoorWidgetService.instance.clearDoorData());
    _notifySafely();
  }

  Future<ManagedUserPage> listManagedUsers({
    UserRole? role,
    UserRole? excludeRole,
    required int page,
    int pageSize = 10,
    String? search,
  }) async {
    final active = _requireSuperUserSession();
    try {
      return await api.listManagedUsers(
        token: active.token,
        role: role,
        excludeRole: excludeRole,
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
    UserRole? role,
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
        role: role,
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

  Future<Map<String, dynamic>> getDatabaseHealth() async {
    final active = _requireSuperUserSession();
    try {
      return await api.getDatabaseHealth(token: active.token);
    } catch (e) {
      _handleSessionError(e);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> runDatabaseCleanup() async {
    final active = _requireSuperUserSession();
    try {
      final res = await api.runDatabaseCleanup(token: active.token);
      _notifySafely();
      return res;
    } catch (e) {
      _handleSessionError(e);
      rethrow;
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

  Future<String?> updateSiteFeatures({
    required int siteCode,
    bool? featureQrEnabled,
    bool? featureRemoteOpenEnabled,
    bool? featureLocalUdpEnabled,
    bool? featureGuestPassEnabled,
  }) async {
    final active = _safeRequireSuperUserSession();
    if (active == null) {
      return 'Bu islem icin super user yetkisi gerekir.';
    }

    try {
      await api.updateSiteFeatures(
        token: active.token,
        siteCode: siteCode,
        featureQrEnabled: featureQrEnabled,
        featureRemoteOpenEnabled: featureRemoteOpenEnabled,
        featureLocalUdpEnabled: featureLocalUdpEnabled,
        featureGuestPassEnabled: featureGuestPassEnabled,
      );
      return null;
    } on ApiException catch (e) {
      _handleSessionError(e);
      return e.message;
    } catch (_) {
      return 'Sunucuya baglanilamadi.';
    }
  }

  Future<String?> updateSiteSecurityPolicy({
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
    final active = session;
    if (active == null ||
        (active.role != UserRole.superUser && active.role != UserRole.siteManager)) {
      return 'Bu islem icin yetkiniz bulunmamaktadir.';
    }

    try {
      await api.updateSiteSecurityPolicy(
        token: active.token,
        role: active.role,
        siteCode: siteCode,
        featureRemoteOpenEnabled: featureRemoteOpenEnabled,
        featureQrEnabled: featureQrEnabled,
        featureLocalUdpEnabled: featureLocalUdpEnabled,
        featureGuestPassEnabled: featureGuestPassEnabled,
        qrEntryActive: qrEntryActive,
        requireGeofence: requireGeofence,
        geofenceLatitude: geofenceLatitude,
        geofenceLongitude: geofenceLongitude,
        geofenceRadiusMeters: geofenceRadiusMeters,
        qrRotationSeconds: qrRotationSeconds,
      );
      return null;
    } on ApiException catch (e) {
      _handleSessionError(e);
      return e.message;
    } catch (_) {
      return 'Sunucuya baglanilamadi.';
    }
  }

  Future<({bool deleted, bool pending, String? message, String? error})> deleteSite({
    required int siteCode,
  }) async {
    final active = _safeRequireManagementSession();
    if (active == null) {
      return (
        deleted: false,
        pending: false,
        message: null,
        error: 'Bu islem icin yetkiniz bulunmamaktadir.',
      );
    }

    try {
      final res = await api.deleteSite(
        token: active.token,
        role: active.role,
        siteCode: siteCode,
      );
      final isDeleted = res['deleted'] == true;
      final isPending = res['pending'] == true;
      final msg = res['message'] as String?;
      return (
        deleted: isDeleted,
        pending: isPending,
        message: msg ?? (isDeleted ? 'Site silindi.' : 'Talep iletildi.'),
        error: null,
      );
    } on ApiException catch (e) {
      _handleSessionError(e);
      return (
        deleted: false,
        pending: false,
        message: null,
        error: e.message,
      );
    } catch (_) {
      return (
        deleted: false,
        pending: false,
        message: null,
        error: 'Sunucuya baglanilamadi.',
      );
    }
  }

  Future<({bool success, String? message, String? error})> approveSiteDeletion({
    required int siteCode,
  }) async {
    final active = _safeRequireManagementSession();
    if (active == null) {
      return (
        success: false,
        message: null,
        error: 'Bu islem icin yetkiniz bulunmamaktadir.',
      );
    }

    try {
      final res = await api.approveSiteDeletion(
        token: active.token,
        role: active.role,
        siteCode: siteCode,
      );
      final msg = res['message'] as String?;
      return (
        success: true,
        message: msg ?? 'Site silme talebi onaylandi ve site silindi.',
        error: null,
      );
    } on ApiException catch (e) {
      _handleSessionError(e);
      return (
        success: false,
        message: null,
        error: e.message,
      );
    } catch (_) {
      return (
        success: false,
        message: null,
        error: 'Sunucuya baglanilamadi.',
      );
    }
  }

  Future<({bool success, String? message, String? error})> rejectSiteDeletion({
    required int siteCode,
  }) async {
    final active = _safeRequireManagementSession();
    if (active == null) {
      return (
        success: false,
        message: null,
        error: 'Bu islem icin yetkiniz bulunmamaktadir.',
      );
    }

    try {
      final res = await api.rejectSiteDeletion(
        token: active.token,
        role: active.role,
        siteCode: siteCode,
      );
      final msg = res['message'] as String?;
      return (
        success: true,
        message: msg ?? 'Site silme talebi reddedildi / iptal edildi.',
        error: null,
      );
    } on ApiException catch (e) {
      _handleSessionError(e);
      return (
        success: false,
        message: null,
        error: e.message,
      );
    } catch (_) {
      return (
        success: false,
        message: null,
        error: 'Sunucuya baglanilamadi.',
      );
    }
  }

  Future<({bool success, String? message, String? maskedEmail, String? error})>
      requestSiteDeletionEmailCode({required int siteCode}) async {
    final active = _safeRequireSuperUserSession();
    if (active == null) {
      return (
        success: false,
        message: null,
        maskedEmail: null,
        error: 'Bu islem icin super user yetkisi gerekir.',
      );
    }

    try {
      final res = await api.requestSiteDeletionEmailCode(
        token: active.token,
        siteCode: siteCode,
      );
      return (
        success: true,
        message: res['message'] as String? ??
            'Dogrulama kodu e-posta adresinize gonderildi.',
        maskedEmail: res['maskedEmail'] as String?,
        error: null,
      );
    } on ApiException catch (e) {
      _handleSessionError(e);
      return (
        success: false,
        message: null,
        maskedEmail: null,
        error: e.message,
      );
    } catch (_) {
      return (
        success: false,
        message: null,
        maskedEmail: null,
        error: 'Sunucuya baglanilamadi.',
      );
    }
  }

  Future<({bool success, String? message, String? error})>
      confirmSiteDeletionWithEmailCode({
    required int siteCode,
    required String code,
  }) async {
    final active = _safeRequireSuperUserSession();
    if (active == null) {
      return (
        success: false,
        message: null,
        error: 'Bu islem icin super user yetkisi gerekir.',
      );
    }

    try {
      final res = await api.confirmSiteDeletionWithEmailCode(
        token: active.token,
        siteCode: siteCode,
        code: code,
      );
      return (
        success: true,
        message: res['message'] as String? ?? 'Site basariyla silindi.',
        error: null,
      );
    } on ApiException catch (e) {
      _handleSessionError(e);
      return (
        success: false,
        message: null,
        error: e.message,
      );
    } catch (_) {
      return (
        success: false,
        message: null,
        error: 'Sunucuya baglanilamadi.',
      );
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

  Future<(DeviceConnectivityReport?, String?)> getDeviceConnectivityLogs({
    required String deviceUid,
    int page = 1,
    int pageSize = 10,
  }) async {
    final active = _safeRequireManagementSession();
    if (active == null) {
      return (null, 'Bu islem icin yonetim yetkisi gerekir.');
    }

    try {
      final report = await api.getDeviceConnectivityLogs(
        token: active.token,
        deviceUid: deviceUid,
        page: page,
        pageSize: pageSize,
      );
      return (report, null);
    } on ApiException catch (e) {
      _handleSessionError(e);
      return (null, e.message);
    } catch (_) {
      return (null, 'Baglanti loglari yuklenirken bir hata olustu.');
    }
  }

  Future<(int, String?)> syncDeviceLogs({
    required String deviceUid,
    required List<Map<String, dynamic>> logs,
  }) async {
    try {
      final token = session?.token;
      final count = await api.syncDeviceLogs(
        deviceUid: deviceUid,
        logs: logs,
        token: token,
      );
      return (count, null);
    } on ApiException catch (e) {
      _handleSessionError(e);
      return (0, e.message);
    } catch (_) {
      return (0, 'Log senkronizasyonu icin sunucuya baglanilamadi.');
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

  Future<(Map<String, dynamic>?, String?)> requestDoorQrToken(
    int doorId, {
    Map<String, dynamic>? location,
  }) async {
    final active = session;
    if (active == null) {
      return (null, 'Oturum bulunamadı.');
    }
    try {
      final res = await api.requestDoorQrToken(
        token: active.token,
        doorId: doorId,
        location: location,
      );
      return (res, null);
    } on ApiException catch (e) {
      _handleSessionError(e);
      return (null, e.message);
    } catch (_) {
      return (null, 'Sunucuya bağlanılamadı.');
    }
  }

  Future<(Map<String, dynamic>?, String?)> revokeMyDoorQr(int doorId) async {
    final active = session;
    if (active == null) {
      return (null, 'Oturum bulunamadı.');
    }
    try {
      final res = await api.revokeMyDoorQr(
        token: active.token,
        doorId: doorId,
      );
      return (res, null);
    } on ApiException catch (e) {
      _handleSessionError(e);
      return (null, e.message);
    } catch (_) {
      return (null, 'Sunucuya bağlanılamadı.');
    }
  }

  Future<(Map<String, dynamic>?, String?)> getDoorQrStatus(String qrToken) async {
    final active = session;
    if (active == null) {
      return (null, 'Oturum bulunamadı.');
    }
    try {
      final res = await api.getDoorQrStatus(
        token: active.token,
        qrToken: qrToken,
      );
      return (res, null);
    } on ApiException catch (e) {
      _handleSessionError(e);
      return (null, e.message);
    } catch (_) {
      return (null, 'Sunucuya bağlanılamadı.');
    }
  }


  Future<bool> isPhoneConnectedToLocalWifi() async {
    return await _localDoorService.hasLocalWifiConnection();
  }

  Future<bool> isDeviceReachableOnLocalWifi(String deviceUid) async {
    return await _localDoorService.isDeviceReachableLocally(deviceUid);
  }

  Future<(DoorRuntimeStatus?, String?)> openDoor({
    required int doorId,
    DoorRecord? door,
  }) async {
    final active = session;
    if (active == null) {
      return (null, 'Oturum bulunamadı.');
    }

    final hasWifi = await _localDoorService.hasLocalWifiConnection();
    final uid = door?.assignedDeviceUid?.trim().toUpperCase();
    final hasDeviceUid = uid != null && uid.isNotEmpty;

    // YEREL AĞ YALNIZCA VE YALNIZCA CİHAZ CANLI BEACON GÖNDERİYORSA DENENİR (Sıfır Gecikme):
    final liveBeacon = hasDeviceUid ? _localDoorService.getCachedDevice(uid) : null;
    final isDeviceLocallyAlive = liveBeacon != null && liveBeacon.isFresh;

    if (hasWifi && isDeviceLocallyAlive && door != null) {
      debugPrint('[AuthService] ⚡ Cihaz yerel ağda canlı (${liveBeacon.ip}), hızlı yerel UDP deneniyor...');
      final localResult = await _tryOpenDoorLocally(door);
      if (localResult != null && localResult.$1 != null) {
        debugPrint('[AuthService] ⚡ Yerel ağ üzerinden kapı ANINDA açıldı!');
        return localResult;
      }

      debugPrint('[AuthService] Yerel ağ yanıt vermedi -> Anında buluta devrediliyor...');
    }

    // Bulut üzerinden anında kapı açma (MQTT ~150-250ms)
    try {
      final status = await api.openDoor(token: active.token, doorId: doorId);
      unawaited(_cacheLocalDoorAccess(status));
      return (status, null);
    } on ApiException catch (e) {
      return (null, e.message);
    } catch (_) {
      return (null, 'Kapı açılamadı. Sunucuya bağlanılamadı.');
    }
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
    final liveBeacon = _localDoorService.getCachedDevice(uid);
    final targetIp = liveBeacon?.ip ?? cached?.ip ?? door.assignedDeviceLocalIp?.trim();
    final access = LocalDoorAccess(
      deviceUid: uid,
      token: cached?.token ?? '',
      ip: targetIp,
      port: liveBeacon?.port ?? cached?.port ?? 8765,
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

  Future<(SiteJoinInfo?, String?)> fetchSiteJoinInfo(String joinToken) async {
    final active = session;
    if (active == null) {
      return (null, 'Oturum bulunamadı.');
    }
    try {
      final info = await api.fetchSiteJoinInfo(
        token: active.token,
        joinToken: joinToken,
      );
      return (info, null);
    } on ApiException catch (e) {
      _handleSessionError(e);
      return (null, e.message);
    } catch (_) {
      return (null, 'Site bilgileri alınamadı.');
    }
  }

  Future<(Map<String, dynamic>?, String?)> submitJoinRequest({
    required String joinToken,
    int? blockId,
    required int apartmentId,
    String? notes,
  }) async {
    final active = session;
    if (active == null) {
      return (null, 'Oturum bulunamadı.');
    }
    try {
      final result = await api.submitJoinRequest(
        token: active.token,
        joinToken: joinToken,
        blockId: blockId,
        apartmentId: apartmentId,
        notes: notes,
      );
      return (result, null);
    } on ApiException catch (e) {
      _handleSessionError(e);
      return (null, e.message);
    } catch (_) {
      return (null, 'Katılım başvurusu gönderilemedi.');
    }
  }

  Future<(List<JoinRequestRecord>?, String?)> getMyJoinRequests() async {
    final active = session;
    if (active == null) {
      return (null, 'Oturum bulunamadı.');
    }
    try {
      final list = await api.getMyJoinRequests(token: active.token);
      return (list, null);
    } on ApiException catch (e) {
      _handleSessionError(e);
      return (null, e.message);
    } catch (_) {
      return (null, 'Başvurular listelenemedi.');
    }
  }

  Future<(List<JoinRequestRecord>?, String?)> getSiteJoinRequests({
    required int siteCode,
    String? status,
  }) async {
    final active = session;
    if (active == null) {
      return (null, 'Oturum bulunamadı.');
    }
    try {
      final list = await api.getSiteJoinRequests(
        token: active.token,
        siteCode: siteCode,
        status: status,
      );
      return (list, null);
    } on ApiException catch (e) {
      _handleSessionError(e);
      return (null, e.message);
    } catch (_) {
      return (null, 'Site başvuruları listelenemedi.');
    }
  }

  Future<(bool, String?)> approveJoinRequest(int requestId) async {
    final active = session;
    if (active == null) {
      return (false, 'Oturum bulunamadı.');
    }
    try {
      final res = await api.approveJoinRequest(
        token: active.token,
        requestId: requestId,
      );
      return (true, res['message'] as String? ?? 'Başvuru onaylandı.');
    } on ApiException catch (e) {
      _handleSessionError(e);
      return (false, e.message);
    } catch (_) {
      return (false, 'Başvuru onaylanamadı.');
    }
  }

  Future<(bool, String?)> rejectJoinRequest(int requestId, {String? reason}) async {
    final active = session;
    if (active == null) {
      return (false, 'Oturum bulunamadı.');
    }
    try {
      final res = await api.rejectJoinRequest(
        token: active.token,
        requestId: requestId,
        reason: reason,
      );
      return (true, res['message'] as String? ?? 'Başvuru reddedildi.');
    } on ApiException catch (e) {
      _handleSessionError(e);
      return (false, e.message);
    } catch (_) {
      return (false, 'Başvuru reddedilemedi.');
    }
  }

  Future<(List<MyApartmentRecord>?, String?)> getMyApartments() async {
    final active = session;
    if (active == null) {
      return (null, 'Oturum bulunamadı.');
    }
    try {
      final list = await api.getMyApartments(token: active.token);
      return (list, null);
    } on ApiException catch (e) {
      _handleSessionError(e);
      return (null, e.message);
    } catch (_) {
      return (null, 'Daireler yüklenemedi.');
    }
  }

  Future<(bool, String?)> removeApartmentMember(int apartmentId, int targetUserCode) async {
    final active = session;
    if (active == null) {
      return (false, 'Oturum bulunamadı.');
    }
    try {
      final res = await api.removeApartmentMember(
        token: active.token,
        apartmentId: apartmentId,
        targetUserCode: targetUserCode,
      );
      return (true, res['message'] as String? ?? 'Üye daireden çıkarıldı.');
    } on ApiException catch (e) {
      _handleSessionError(e);
      return (false, e.message);
    } catch (_) {
      return (false, 'İşlem başarısız.');
    }
  }

  Future<(DoorPermissionsData?, String?)> getDoorPermissions(int doorId) async {
    final active = session;
    if (active == null) {
      return (null, 'Oturum bulunamadı.');
    }
    try {
      final json = await api.getDoorPermissions(
        token: active.token,
        doorId: doorId,
      );
      return (DoorPermissionsData.fromJson(json), null);
    } on ApiException catch (e) {
      _handleSessionError(e);
      return (null, e.message);
    } catch (_) {
      return (null, 'Kapı yetkileri alınamadı.');
    }
  }

  Future<(bool, String?)> setDoorAccessOverride({
    required int doorId,
    required int userCode,
    bool? isAllowed,
    String? notes,
  }) async {
    final active = session;
    if (active == null) {
      return (false, 'Oturum bulunamadı.');
    }
    try {
      final res = await api.setDoorAccessOverride(
        token: active.token,
        doorId: doorId,
        userCode: userCode,
        isAllowed: isAllowed,
        notes: notes,
      );
      return (true, res['message'] as String? ?? 'Yetki güncellendi.');
    } on ApiException catch (e) {
      _handleSessionError(e);
      return (false, e.message);
    } catch (_) {
      return (false, 'Yetki güncellenemedi.');
    }
  }

  Future<(bool, String?)> setBulkDoorAccessOverride({
    required int doorId,
    int? blockId,
    int? apartmentId,
    List<int>? userCodes,
    bool? isAllowed,
    String? notes,
  }) async {
    final active = session;
    if (active == null) {
      return (false, 'Oturum bulunamadı.');
    }
    try {
      final res = await api.setBulkDoorAccessOverride(
        token: active.token,
        doorId: doorId,
        blockId: blockId,
        apartmentId: apartmentId,
        userCodes: userCodes,
        isAllowed: isAllowed,
        notes: notes,
      );
      return (true, res['message'] as String? ?? 'Toplu yetkilendirme uygulandı.');
    } on ApiException catch (e) {
      _handleSessionError(e);
      return (false, e.message);
    } catch (_) {
      return (false, 'Toplu işlem başarısız.');
    }
  }

  Future<(SiteResidentsTreeData?, String?)> getSiteResidentsTree(int siteCode) async {
    final active = session;
    if (active == null) {
      return (null, 'Oturum bulunamadı.');
    }
    try {
      final json = await api.getSiteResidentsTree(
        token: active.token,
        siteCode: siteCode,
      );
      return (SiteResidentsTreeData.fromJson(json), null);
    } on ApiException catch (e) {
      _handleSessionError(e);
      return (null, e.message);
    } catch (_) {
      return (null, 'Sakin listesi yüklenemedi.');
    }
  }

  Future<(bool, String?)> toggleApartmentMemberStatus({
    required int apartmentId,
    required int targetUserCode,
    required bool isActive,
  }) async {
    final active = session;
    if (active == null) {
      return (false, 'Oturum bulunamadı.');
    }
    try {
      final res = await api.toggleApartmentMemberStatus(
        token: active.token,
        apartmentId: apartmentId,
        targetUserCode: targetUserCode,
        isActive: isActive,
      );
      return (true, res['message'] as String? ?? 'Sakin durumu güncellendi.');
    } on ApiException catch (e) {
      _handleSessionError(e);
      return (false, e.message);
    } catch (_) {
      return (false, 'Durum güncellenirken bir hata oluştu.');
    }
  }

  Future<(bool, String?)> deleteApartmentMember({
    required int apartmentId,
    required int targetUserCode,
  }) async {
    final active = session;
    if (active == null) {
      return (false, 'Oturum bulunamadı.');
    }
    try {
      final res = await api.deleteApartmentMember(
        token: active.token,
        apartmentId: apartmentId,
        targetUserCode: targetUserCode,
      );
      return (true, res['message'] as String? ?? 'Sakin daireden silindi.');
    } on ApiException catch (e) {
      _handleSessionError(e);
      return (false, e.message);
    } catch (_) {
      return (false, 'Sakin silinirken bir hata oluştu.');
    }
  }

  Future<(bool, String?)> changeApartmentMemberPassword({
    required int apartmentId,
    required int targetUserCode,
    required String newPassword,
  }) async {
    final active = session;
    if (active == null) {
      return (false, 'Oturum bulunamadı.');
    }
    try {
      final res = await api.changeApartmentMemberPassword(
        token: active.token,
        apartmentId: apartmentId,
        targetUserCode: targetUserCode,
        newPassword: newPassword,
      );
      return (true, res['message'] as String? ?? 'Şifre başarıyla güncellendi.');
    } on ApiException catch (e) {
      _handleSessionError(e);
      return (false, e.message);
    } catch (_) {
      return (false, 'Şifre güncellenirken bir hata oluştu.');
    }
  }

  Future<(bool, String?)> setApartmentPrimaryAdmin({
    required int apartmentId,
    required int targetUserCode,
  }) async {
    final active = session;
    if (active == null) {
      return (false, 'Oturum bulunamadı.');
    }
    try {
      final res = await api.setApartmentPrimaryAdmin(
        token: active.token,
        apartmentId: apartmentId,
        targetUserCode: targetUserCode,
      );
      return (true, res['message'] as String? ?? 'Aile reisi başarıyla güncellendi.');
    } on ApiException catch (e) {
      _handleSessionError(e);
      return (false, e.message);
    } catch (_) {
      return (false, 'Aile reisi atanırken bir hata oluştu.');
    }
  }

  Future<SiteManagersData?> getSiteManagers(int siteCode) async {
    final active = session;
    if (active == null) {
      return null;
    }
    try {
      return await api.getSiteManagers(
        token: active.token,
        siteCode: siteCode,
      );
    } on ApiException catch (e) {
      _handleSessionError(e);
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<(bool, String?)> inviteSiteManager(
    int siteCode, {
    required String email,
    String? fullName,
  }) async {
    final active = session;
    if (active == null) {
      return (false, 'Oturum bulunamadı.');
    }
    try {
      final res = await api.inviteSiteManager(
        token: active.token,
        siteCode: siteCode,
        email: email,
        fullName: fullName,
      );
      return (true, res['message'] as String? ?? 'Yönetici daveti başarıyla iletildi.');
    } on ApiException catch (e) {
      _handleSessionError(e);
      return (false, e.message);
    } catch (_) {
      return (false, 'Yönetici davet edilirken bir hata oluştu.');
    }
  }

  Future<(bool, String?)> removeSiteManager(
    int siteCode,
    String userCode,
  ) async {
    final active = session;
    if (active == null) {
      return (false, 'Oturum bulunamadı.');
    }
    try {
      final res = await api.removeSiteManager(
        token: active.token,
        siteCode: siteCode,
        userCode: userCode,
      );
      return (true, res['message'] as String? ?? 'Yönetici yetkisi başarıyla kaldırıldı.');
    } on ApiException catch (e) {
      _handleSessionError(e);
      return (false, e.message);
    } catch (_) {
      return (false, 'Yönetici yetkisi kaldırılırken bir hata oluştu.');
    }
  }

  Future<(bool, String?)> revokeSiteManagerInvitation(
    int siteCode,
    int invitationId,
  ) async {
    final active = session;
    if (active == null) {
      return (false, 'Oturum bulunamadı.');
    }
    try {
      final res = await api.revokeSiteManagerInvitation(
        token: active.token,
        siteCode: siteCode,
        invitationId: invitationId,
      );
      return (true, res['message'] as String? ?? 'Davet başarıyla iptal edildi.');
    } on ApiException catch (e) {
      _handleSessionError(e);
      return (false, e.message);
    } catch (_) {
      return (false, 'Davet iptal edilirken bir hata oluştu.');
    }
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
