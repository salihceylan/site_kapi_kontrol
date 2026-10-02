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
import 'package:site_kapi_kontrol/services/geofence_service.dart';
import 'package:site_kapi_kontrol/services/local_door_service.dart';

class AuthService extends ChangeNotifier {
  AuthService({
    required this.api,
    Future<LocationFixResult> Function()? locationProvider,
  }) : _locationProvider =
            locationProvider ?? GeofenceService.instance.acquireVerifiedPosition;

  static const String _storageKey = 'auth_session';
  static const String _localDoorCacheKey = 'local_door_cache';
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  /// /me doğrulamasının (C11) art arda çağrılması arasındaki asgari süre.
  static const Duration _sessionCheckMinInterval = Duration(seconds: 20);

  /// Yerel erişim önbelleği değişmediyse en fazla bu sıklıkta yeniden yazılır.
  static const Duration _localCacheRewriteInterval = Duration(hours: 1);

  final AuthApi api;
  final Future<LocationFixResult> Function() _locationProvider;
  final LocalDoorService _localDoorService = LocalDoorService();
  UserSession? _session;
  final Map<String, LocalDoorAccess> _localDoorCache =
      <String, LocalDoorAccess>{};
  List<DoorRecord>? _lastMyDoors;
  bool _isReady = false;
  bool _isDisposed = false;
  Future<void>? _refreshInFlight;
  DateTime? _lastSessionCheckAt;
  String? _sessionNotice;

  /// Süren parola değişimi sayısı (updateMyProfile / changeApartmentMemberPassword). Sunucu
  /// parolayı yazar yazmaz eski token'ı iptal eder, yeni token ise ancak yanıtla gelir; bu aralıkta
  /// eşzamanlı bir isteğin TOKEN_REVOKED 401'i oturumu yanlışlıkla kapatmasın diye sayılır.
  int _credentialSwapDepth = 0;

  UserSession? get session => _session;
  bool get isLoggedIn => _session != null;
  bool get isReady => _isReady;

  /// Oturum sunucu tarafında sonlandırıldıysa (süre dolumu, parola değişimi, hesap pasif)
  /// giriş ekranında BİR KEZ gösterilecek açıklama. Okununca temizlenir.
  String? takeSessionNotice() {
    final notice = _sessionNotice;
    _sessionNotice = null;
    return notice;
  }

  /// Güvenli depodaki oturum metni; okunamazsa null (hata açılışı engellemez).
  Future<String?> _readStoredSessionRaw() async {
    try {
      return await _secureStorage.read(key: _storageKey);
    } catch (_) {
      return null;
    }
  }

  Future<void> initialize() async {
    try {
      // Soğuk açılış: birbirinden bağımsız üç okuma (güvenli depodaki oturum, eski SharedPreferences
      // kopyası, yerel erişim önbelleği) EŞZAMANLI başlar; ekran seçimi bunların toplamını değil en
      // yavaşını bekler. Sonuçlar aşağıda eskisiyle aynı sırayla işlenir (oturum yüklendi -> hazır).
      final rawFuture = _readStoredSessionRaw();
      final legacyFuture = _takeLegacySession();
      final Future<void> cacheFuture =
          kIsWeb ? Future<void>.value() : _loadLocalDoorCache().catchError((_) {});

      String? raw = await rawFuture;

      // Oturum yalnızca flutter_secure_storage'da tutulur. Eski sürümlerin bıraktığı
      // SharedPreferences kopyası (düz metin token) bir kerelik taşınır ve SİLİNİR.
      final legacyRaw = await legacyFuture;
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
        }
      }

      await cacheFuture;
    } catch (_) {}

    _isReady = true;
    _notifySafely();

    // C11: kayıtlı oturum varsa sunucudaki güncel rol/aktiflik bilgisiyle doğrula.
    // Çevrimdışı açılışı engellememek için beklenmez.
    if (_session != null) {
      unawaited(refreshSession(force: true));
    }
  }

  /// Eski (SharedPreferences) oturum kopyasını okuyup siler; yoksa null döner.
  Future<String?> _takeLegacySession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final legacy = prefs.getString(_storageKey);
      if (legacy != null) {
        await prefs.remove(_storageKey);
      }
      return (legacy == null || legacy.isEmpty) ? null : legacy;
    } catch (_) {
      return null;
    }
  }

  /// C11: Sunucudaki GET /me yanıtını kaynak kabul eder. 401 veya 403 (hesap pasif /
  /// onaysız) durumunda oturumu kapatır; ağ/5xx hatalarında mevcut oturum korunur.
  /// Uygulama açılışında ve ön plana dönüşte çağrılır.
  Future<void> refreshSession({bool force = false}) async {
    // Süren bir doğrulama varsa: normal çağrı onu bekleyip biter; zorlamalı çağrı (örn.
    // cihaz sahiplenme sonrası rol eşitleme) bittikten sonra güncel veriyle bir kez daha çalışır.
    final inFlight = _refreshInFlight;
    if (inFlight != null) {
      await inFlight;
      if (!force) {
        return;
      }
    }

    final active = _session;
    if (active == null) {
      return;
    }
    final now = DateTime.now();
    final last = _lastSessionCheckAt;
    if (!force && last != null && now.difference(last) < _sessionCheckMinInterval) {
      return;
    }

    _lastSessionCheckAt = now;
    final run = _runSessionRefresh(active);
    _refreshInFlight = run;
    try {
      await run;
    } finally {
      if (identical(_refreshInFlight, run)) {
        _refreshInFlight = null;
      }
    }
  }

  Future<void> _runSessionRefresh(UserSession active) async {
    try {
      final fresh = await api.fetchMe(token: active.token, current: active);
      if (_session?.token != active.token) {
        return; // Bu arada oturum değişti/kapandı.
      }
      if (!fresh.isActive) {
        _sessionNotice = 'Hesabınız pasif duruma alındı. Lütfen yöneticinizle iletişime geçin.';
        await logout();
        return;
      }
      if (_sessionDiffers(active, fresh)) {
        _session = fresh;
        await _persist();
        _notifySafely();
      }
    } on ApiException catch (e) {
      if (_session?.token != active.token) {
        return;
      }
      if (e.isUnauthorized || e.isForbidden) {
        if (_credentialSwapDepth > 0 && e.code == 'TOKEN_REVOKED') {
          return; // Parola değişimi sürüyor: yeni token değişim yanıtıyla gelecek.
        }
        _sessionNotice = e.message;
        await logout();
      }
      // Diğer hatalar (ağ, 5xx, ara katman 401/403): çevrimdışı oturum korunur.
    } catch (_) {
      // Beklenmeyen/ağ hatası: oturumu bozma.
    }
  }

  bool _sessionDiffers(UserSession a, UserSession b) {
    return a.role != b.role ||
        a.isActive != b.isActive ||
        a.fullName != b.fullName ||
        a.email != b.email ||
        a.loginName != b.loginName ||
        a.phoneNumber != b.phoneNumber;
  }

  Future<String?> login({
    required String email,
    required String password,
    UserRole? role,
  }) async {
    try {
      _session = await api.login(email: email, password: password, role: role);
      _lastSessionCheckAt = DateTime.now();
      await _persist();
      _notifySafely();
      return null;
    } on ApiException catch (e) {
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
      _lastSessionCheckAt = DateTime.now();
      await _persist();
      _notifySafely();
      return null;
    } on ApiException catch (e) {
      if (e.statusCode == 404) {
        // Aktif kod yok: kod 10 dakika geçerlidir; kullanıcıyı yeni kod istemeye yönlendir.
        return '${e.message} Kod 10 dakika geçerlidir; yeni kod için "Kodu Tekrar Gönder"e dokunun.';
      }
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

  /// Tüm yetkili (Bearer) API çağrıları için ortak sarmalayıcı: oturum yoksa hata fırlatır,
  /// 401 gibi oturum hatalarında merkezi çıkışı uygular ve hatayı yeniden fırlatır.
  Future<T> _runAuthorized<T>(
    Future<T> Function(String token) call, {
    String noSessionMessage = 'Oturum açmanız gerekmektedir.',
  }) async {
    final token = _session?.token;
    if (token == null) {
      throw ApiException(noSessionMessage);
    }
    try {
      return await call(token);
    } on ApiException catch (e) {
      _handleSessionError(e, usedToken: token);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> claimDevice({
    required String deviceInput,
  }) async {
    final res = await _runAuthorized(
      (token) => api.claimDevice(token: token, deviceInput: deviceInput),
    );
    // Rol yükseltmesi sunucuda yapılır; yerelde tahmin etmek yerine /me ile eşitle (C11).
    await refreshSession(force: true);
    return res;
  }

  Future<List<Map<String, dynamic>>> getMyClaimedDevices() async {
    final active = _session;
    if (active == null) {
      return [];
    }
    try {
      // Salt-okunur: rol değişimi yerelde yapılmaz, /me ile eşitlenir.
      return await api.getMyClaimedDevices(token: active.token);
    } on ApiException catch (e) {
      _handleSessionError(e, usedToken: active.token);
      rethrow;
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
    final res = await _runAuthorized(
      (token) => api.setupSite(
        token: token,
        name: name,
        city: city,
        district: district,
        address: address,
        blocks: blocks,
        doors: doors,
        doorCount: doorCount,
        deviceUid: deviceUid,
      ),
    );
    // Site kurulumunda sunucu rolü site_manager yapar; /me ile eşitle (C11).
    await refreshSession(force: true);
    return res;
  }

  Future<Map<String, dynamic>> createDoor({
    required int siteCode,
    required String doorName,
    String accessScope = 'SITE_COMMON',
    int? blockId,
    String? deviceUid,
  }) async {
    final res = await _runAuthorized(
      (token) => api.createDoor(
        token: token,
        siteCode: siteCode,
        doorName: doorName,
        accessScope: accessScope,
        blockId: blockId,
        deviceUid: deviceUid,
      ),
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
    final res = await _runAuthorized(
      (token) => api.updateDoor(
        token: token,
        doorId: doorId,
        doorName: doorName,
        accessScope: accessScope,
        blockId: blockId,
        isActive: isActive,
      ),
    );
    _notifySafely();
    return res;
  }

  Future<void> deleteDoor({required int doorId}) async {
    await _runAuthorized(
      (token) => api.deleteDoor(token: token, doorId: doorId),
    );
    _notifySafely();
  }

  Future<Map<String, dynamic>> unassignDoorDevice({required int doorId}) async {
    final res = await _runAuthorized(
      (token) => api.unassignDoorDevice(token: token, doorId: doorId),
    );
    _notifySafely();
    return res;
  }

  Future<Map<String, dynamic>> replaceDoorDevice({
    required int doorId,
    String? deviceInput,
    int? deviceId,
  }) async {
    final res = await _runAuthorized(
      (token) => api.replaceDoorDevice(
        token: token,
        doorId: doorId,
        deviceInput: deviceInput,
        deviceId: deviceId,
      ),
    );
    _notifySafely();
    return res;
  }

  Future<List<Map<String, dynamic>>> getAssignableDevices({required int siteCode}) async {
    final active = _session;
    if (active == null) return [];
    try {
      return await api.getAssignableDevices(token: active.token, siteCode: siteCode);
    } on ApiException catch (e) {
      _handleSessionError(e, usedToken: active.token);
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<SiteJoinTokenRecord> getSiteJoinToken({required int siteCode}) async {
    return _runAuthorized(
      (token) => api.getSiteJoinToken(token: token, siteCode: siteCode),
    );
  }

  Future<SiteJoinTokenRecord> rotateSiteJoinToken({required int siteCode}) async {
    final res = await _runAuthorized(
      (token) => api.rotateSiteJoinToken(token: token, siteCode: siteCode),
    );
    _notifySafely();
    return res;
  }

  Future<Map<String, dynamic>> getSiteJoinInfo({required String joinToken}) async {
    return _runAuthorized(
      (token) => api.getSiteJoinInfo(token: token, joinToken: joinToken),
    );
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
      _lastSessionCheckAt = DateTime.now();
      await _persist();
      _notifySafely();
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Sunucuya baglanilamadi.';
    }
  }

  Future<String?> forgotPassword({required String email}) async {
    try {
      await api.forgotPassword(email: email);
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Sunucuya bağlanılamadı. Lütfen internet bağlantınızı kontrol ediniz.';
    }
  }

  Future<void> logout() async {
    final hadSession = _session != null;
    _session = null;
    _lastSessionCheckAt = null;
    _lastMyDoors = null;
    _localDoorCache.clear();
    _doorStatusCloudDown.clear();
    // Arayüz hemen giriş ekranına dönsün; temizlik arka planda tamamlanır.
    _notifySafely();

    // Eski sürümlerden kalmış olabilecek düz metin kopyayı da sil.
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storageKey);
    } catch (_) {}
    try {
      await _secureStorage.delete(key: _storageKey);
      await _secureStorage.delete(key: _localDoorCacheKey);
    } catch (_) {}

    // Widget'ta kalan kapı listesi ve token silinir (çıkış sonrası widget kapı açamasın).
    if (hadSession) {
      try {
        await DoorWidgetService.instance.clearDoorData();
      } catch (_) {}
    }
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
      _handleSessionError(e, usedToken: active.token);
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
      _handleSessionError(e, usedToken: active.token);
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
      _handleSessionError(e, usedToken: active.token);
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
      _handleSessionError(e, usedToken: active.token);
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
    bool? emailVerified,
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
        emailVerified: emailVerified,
      );
      return null;
    } on ApiException catch (e) {
      _handleSessionError(e, usedToken: active.token);
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
      _handleSessionError(e, usedToken: active.token);
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
      _handleSessionError(e, usedToken: active.token);
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
      _handleSessionError(e, usedToken: active.token);
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
      _handleSessionError(e, usedToken: active.token);
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
      _handleSessionError(e, usedToken: active.token);
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
      _handleSessionError(e, usedToken: active.token);
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
      _handleSessionError(e, usedToken: active.token);
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
      _handleSessionError(e, usedToken: active.token);
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
      _handleSessionError(e, usedToken: active.token);
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
      _handleSessionError(e, usedToken: active.token);
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
      _handleSessionError(e, usedToken: active.token);
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
      _handleSessionError(e, usedToken: active.token);
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
      _handleSessionError(e, usedToken: active.token);
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
      _handleSessionError(e, usedToken: active.token);
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
      _handleSessionError(e, usedToken: active.token);
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
      _handleSessionError(e, usedToken: active.token);
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
      _handleSessionError(e, usedToken: active.token);
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
      _handleSessionError(e, usedToken: active.token);
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
      _handleSessionError(e, usedToken: active.token);
      return (null, e.message);
    } catch (_) {
      return (null, 'Baglanti loglari yuklenirken bir hata olustu.');
    }
  }

  Future<(int, String?)> syncDeviceLogs({
    required String deviceUid,
    required List<Map<String, dynamic>> logs,
  }) async {
    // Sunucu bu uçta JWT zorunlu kılar (S3); oturum yoksa istek boşuna gönderilmez.
    final active = session;
    if (active == null) {
      return (0, 'Oturum bulunamadi.');
    }
    try {
      final count = await api.syncDeviceLogs(
        deviceUid: deviceUid,
        logs: logs,
        token: active.token,
      );
      return (count, null);
    } on ApiException catch (e) {
      _handleSessionError(e, usedToken: active.token);
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
      _handleSessionError(e, usedToken: active.token);
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
      _handleSessionError(e, usedToken: active.token);
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
      _handleSessionError(e, usedToken: active.token);
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
      _handleSessionError(e, usedToken: active.token);
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
      _handleSessionError(e, usedToken: active.token);
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
      _handleSessionError(e, usedToken: active.token);
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
      _handleSessionError(e, usedToken: active.token);
      return (null, e.message);
    } catch (_) {
      return (null, 'Sunucuya baglanilamadi.');
    }
  }

  /// Kapı durum yoklaması hatası "bulut erişilemiyor" türündeyse (ağ yok, zaman aşımı, 5xx,
  /// proxy/HTML yanıtı) true. Karar hata metnine DEĞİL, [ApiException] türüne/durum koduna dayanır;
  /// sunucunun açık iş hataları (403/404 vb.) bulut sorunu sayılmaz. Son yoklama başarılıysa false.
  bool isDoorStatusCloudUnreachable(int doorId) => _doorStatusCloudDown.contains(doorId);

  final Set<int> _doorStatusCloudDown = <int>{};

  static bool _isCloudUnreachableError(ApiException e) =>
      e.statusCode == null || e.isServerError || e.fromIntermediary;

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
      _doorStatusCloudDown.remove(doorId);
      await _cacheLocalDoorAccess(status);
      return (status, null);
    } on ApiException catch (e) {
      if (_isCloudUnreachableError(e)) {
        _doorStatusCloudDown.add(doorId);
      } else {
        _doorStatusCloudDown.remove(doorId);
      }
      _handleSessionError(e, usedToken: active.token);
      return (null, e.message);
    } catch (_) {
      _doorStatusCloudDown.add(doorId);
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
      Map<String, dynamic> res;
      try {
        res = await api.requestDoorQrToken(
          token: active.token,
          doorId: doorId,
          location: location,
        );
      } on ApiException catch (e) {
        // Kapı bayrakları bayat olabilir: sunucu konum istiyorsa (token üretilmeden, yan etkisiz
        // reddedildi) konumu alıp BİR KEZ yeniden dene (open / scan-qr-open ile aynı kalıp).
        if (location == null && e.code == 'GEOFENCE_LOCATION_REQUIRED') {
          final fix = await _locationProvider();
          final position = fix.position;
          if (position == null) {
            return (null, fix.errorMessage ?? e.message);
          }
          res = await api.requestDoorQrToken(
            token: active.token,
            doorId: doorId,
            location: GeofenceService.locationRequestFields(position),
          );
        } else {
          rethrow;
        }
      }
      return (res, null);
    } on ApiException catch (e) {
      _handleSessionError(e, usedToken: active.token);
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
      _handleSessionError(e, usedToken: active.token);
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
      _handleSessionError(e, usedToken: active.token);
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

    // Kapı politikası: bayraklar biliniyorsa istemci de uygular (sunucu yine nihai karar verir).
    // Sunucu süper kullanıcıya remote/local kanallarında istisna tanır (door_access_policy.js);
    // istemci de aynı istisnayı uygular (aksi halde istek hiç gönderilmeden reddedilirdi).
    final isSuper = active.role == UserRole.superUser;
    final allowRemote = door == null || door.canOpenRemote || isSuper;
    final allowLocal = door != null && (door.canOpenLocalUdp || isSuper);
    if (!allowRemote && !allowLocal) {
      return (null, 'Bu kapı için uygulamadan açma kapalı.');
    }

    // YEREL AĞ YALNIZCA cihaz canlı beacon gönderiyorsa, kapı yerel açmaya izin veriyorsa
    // ve sunucudan alınmış yerel erişim token'ı varsa denenir (C4: token yoksa yerel yok).
    if (allowLocal) {
      final localResult = await _tryOpenDoorLocallyIfAlive(door);
      if (localResult != null) {
        return localResult;
      }
    }

    if (!allowRemote) {
      return (
        null,
        'Bu kapıda uzaktan açma kapalı. Cihaza yerel ağdan ulaşılamadı; telefonu cihazla aynı Wi-Fi ağına bağlayıp tekrar deneyin.',
      );
    }

    // C3: Konum zorunlu kapıda konum alınamıyorsa istek HİÇ gönderilmez.
    Map<String, dynamic>? location;
    if (door != null && door.requireGeofence) {
      final fix = await _locationProvider();
      final position = fix.position;
      if (position == null) {
        return (
          null,
          fix.errorMessage ??
              'Bu kapı için konum doğrulaması zorunludur. Lütfen konum servisini ve izinlerini açın.',
        );
      }
      location = GeofenceService.locationRequestFields(position);
    }

    // Bulut üzerinden kapı açma (MQTT ~150-250ms)
    try {
      DoorRuntimeStatus status;
      try {
        status = await api.openDoor(
          token: active.token,
          doorId: doorId,
          location: location,
        );
      } on ApiException catch (e) {
        // Kapı bayrakları bayat olabilir: sunucu konum istiyorsa (hiçbir yan etki olmadan
        // reddedildi) konumu alıp BİR KEZ yeniden dene; konum alınamazsa gönderme.
        if (location == null && e.code == 'GEOFENCE_LOCATION_REQUIRED') {
          final fix = await _locationProvider();
          final position = fix.position;
          if (position == null) {
            return (null, fix.errorMessage ?? e.message);
          }
          status = await api.openDoor(
            token: active.token,
            doorId: doorId,
            location: GeofenceService.locationRequestFields(position),
          );
        } else {
          rethrow;
        }
      }
      unawaited(_cacheLocalDoorAccess(status));
      return (status, null);
    } on ApiException catch (e) {
      _handleSessionError(e, usedToken: active.token);
      return (null, e.message);
    } catch (_) {
      return (null, 'Kapı açılamadı. Sunucuya bağlanılamadı.');
    }
  }

  /// Kapının yerel (UDP/HTTP) kontrol için kullanılabilir olup olmadığı:
  /// kapı politikası izin vermeli ve sunucudan alınmış geçerli bir token önbellekte olmalı.
  bool canTryLocalDoorOpen(DoorRecord door) {
    // Süper kullanıcı için sunucu politika bayrağını yok sayar (token yine sunucudan gelir).
    if (!door.canOpenLocalUdp && _session?.role != UserRole.superUser) {
      return false;
    }
    final uid = door.assignedDeviceUid?.trim().toUpperCase();
    if (uid == null || uid.isEmpty) {
      return false;
    }
    final cached = _localDoorCache[uid];
    return cached != null && cached.isUsable && cached.token.trim().isNotEmpty;
  }

  Future<(Map<String, dynamic>?, String?)> openDoorWithScannedQr({
    required String qrPayload,
    bool requireLocation = false,
  }) async {
    final active = session;
    if (active == null) {
      return (null, 'Oturum bulunamadı.');
    }

    // C3: Konum zorunluysa alınamadığında istek GÖNDERİLMEZ ve anlaşılır hata döner.
    Map<String, dynamic>? location;
    if (requireLocation) {
      final fix = await _locationProvider();
      final position = fix.position;
      if (position == null) {
        return (
          null,
          fix.errorMessage ??
              'Bu kapı için konum doğrulaması zorunludur. Lütfen konum servisini ve izinlerini açın.',
        );
      }
      location = GeofenceService.locationRequestFields(position);
    }

    try {
      Map<String, dynamic> res;
      try {
        res = await api.openDoorWithScannedQr(
          token: active.token,
          qrPayload: qrPayload,
          location: location,
        );
      } on ApiException catch (e) {
        // Okutulan karekod başka bir kapıya/ekransız cihaza aitse ve sunucu konum istiyorsa
        // (karekod henüz tüketilmedi) konumu alıp BİR KEZ yeniden dene.
        if (location == null && e.code == 'GEOFENCE_LOCATION_REQUIRED') {
          final fix = await _locationProvider();
          final position = fix.position;
          if (position == null) {
            return (null, fix.errorMessage ?? e.message);
          }
          res = await api.openDoorWithScannedQr(
            token: active.token,
            qrPayload: qrPayload,
            location: GeofenceService.locationRequestFields(position),
          );
        } else {
          rethrow;
        }
      }
      return (res, null);
    } on ApiException catch (e) {
      _handleSessionError(e, usedToken: active.token);
      return (null, e.message);
    } catch (_) {
      return (null, 'Karekod okutularak kapı açılamadı. Sunucuya bağlanılamadı.');
    }
  }

  Future<(List<DoorRecord>?, String?)> listMyDoors() async {
    final active = session;
    if (active == null) {
      return (null, 'Oturum bulunamadi.');
    }

    try {
      final doors = await api.listMyDoors(token: active.token);
      if (_session?.token == active.token) {
        _syncDoorWidget(active, doors);
      }
      return (doors, null);
    } on ApiException catch (e) {
      _handleSessionError(e, usedToken: active.token);
      return (null, e.message);
    } catch (_) {
      return (null, 'Sunucuya baglanilamadi.');
    }
  }

  /// Masaüstü widget'ının kapı listesi için TEK kaynak: kullanıcının erişebildiği kapılar
  /// (listMyDoors). Liste boşsa widget temizlenir. Süper kullanıcı için widget kullanılmaz.
  void _syncDoorWidget(UserSession active, List<DoorRecord> doors) {
    if (kIsWeb || active.role == UserRole.superUser) {
      return;
    }
    _lastMyDoors = List<DoorRecord>.unmodifiable(doors);
    try {
      unawaited(
        DoorWidgetService.instance
            .syncDoorsList(
              doors: doors,
              token: active.token,
              apiBaseUrl: api.baseUrl,
            )
            .catchError((_) {}),
      );
    } catch (_) {}
  }

  /// Kullanıcı arayüzde bir kapıyı AÇIKÇA seçtiğinde widget'ın aktif kapısını da ona çeker
  /// (`forceSelectDoor: true`). Otomatik senkronlar bunu KULLANMAZ; widget'ta kullanıcının
  /// seçtiği kapı korunur.
  void selectWidgetDoor(DoorRecord door, {bool? isOnline}) {
    final active = _session;
    if (kIsWeb || active == null || active.role == UserRole.superUser) {
      return;
    }
    final doors = _lastMyDoors;
    if (doors == null) {
      // Liste henüz alınmadıysa önce alınır (listMyDoors widget'ı da senkronlar), sonra seçim uygulanır.
      unawaited(listMyDoors().then((_) {
        final loaded = _lastMyDoors;
        if (loaded != null && _session?.token == active.token) {
          _forceWidgetDoor(active, loaded, door, isOnline);
        }
      }));
      return;
    }
    _forceWidgetDoor(active, doors, door, isOnline);
  }

  void _forceWidgetDoor(
    UserSession active,
    List<DoorRecord> doors,
    DoorRecord door,
    bool? isOnline,
  ) {
    if (!doors.any((d) => d.id == door.id)) {
      return;
    }
    try {
      unawaited(
        DoorWidgetService.instance
            .syncDoorsList(
              doors: doors,
              token: active.token,
              apiBaseUrl: api.baseUrl,
              selectedDoor: door,
              isSelectedDoorOnline: isOnline,
              forceSelectDoor: true,
            )
            .catchError((_) {}),
      );
    } catch (_) {}
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
      _handleSessionError(e, usedToken: active.token);
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
      _handleSessionError(e, usedToken: active.token);
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
    String? currentPassword,
  }) async {
    final active = _session;
    if (active == null) {
      return 'Oturum bulunamadi.';
    }

    // C8: şifre değiştirilirken mevcut şifre zorunludur.
    if (password != null && password.isNotEmpty && (currentPassword ?? '').isEmpty) {
      return 'Şifrenizi değiştirmek için mevcut şifrenizi girin.';
    }

    // Parola değişimi sürerken eşzamanlı isteklerin TOKEN_REVOKED 401'i oturumu kapatmasın.
    final isPasswordChange = password != null && password.isNotEmpty;
    if (isPasswordChange) {
      _credentialSwapDepth++;
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
        currentPassword: currentPassword,
      );
      if (_session?.token != active.token) {
        // Yanıt beklenirken oturum kapandı/değişti: eski oturumu yeniden yazma.
        return null;
      }
      final tokenChanged = updated.token != active.token;
      _session = updated;
      await _persist();
      // Parola değişince sunucu yeni token döndürür; masaüstü widget'ı eski (iptal edilmiş)
      // token ile kalmasın.
      final knownDoors = _lastMyDoors;
      if (tokenChanged && knownDoors != null) {
        _syncDoorWidget(updated, knownDoors);
      }
      _notifySafely();
      return null;
    } on ApiException catch (e) {
      // PATCH /me'nin KENDİ 401'i (token iptal/süre dolumu/silinmiş kullanıcı) gerçek oturum sonudur;
      // yanlış mevcut şifre 400 CURRENT_PASSWORD_INVALID döner ve oturumu kapatmaz.
      _handleSessionError(e, usedToken: active.token, ownCredentialSwap: true);
      return e.message;
    } catch (_) {
      return 'Sunucuya baglanilamadi.';
    } finally {
      if (isPasswordChange) {
        _credentialSwapDepth--;
      }
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
      _handleSessionError(e, usedToken: active.token);
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
      _handleSessionError(e, usedToken: active.token);
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
      _handleSessionError(e, usedToken: active.token);
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

  /// [ownCredentialSwap]: hata, parola değişimini yapan isteğin KENDİSİNE aittir (gerçek oturum sonu).
  void _handleSessionError(
    Object error, {
    String? usedToken,
    bool ownCredentialSwap = false,
  }) {
    final current = _session;
    if (current == null) {
      return; // Zaten oturum yok (örn. giriş denemesi hatası).
    }
    // Eski bir token ile başlatılmış gecikmiş isteğin 401'i yeni oturumu kapatmasın.
    if (usedToken != null && current.token != usedToken) {
      return;
    }
    // Parola değişimi sürerken eşzamanlı (örn. 3 sn'lik durum yoklaması) bir isteğin TOKEN_REVOKED
    // 401'i yok sayılır: yeni token yanıtla gelecek; gerçekten iptal edilmişse sonraki istek kapatır.
    if (!ownCredentialSwap &&
        _credentialSwapDepth > 0 &&
        error is ApiException &&
        error.code == 'TOKEN_REVOKED') {
      return;
    }
    if (error is SessionExpiredException ||
        (error is ApiException && error.invalidatesSession)) {
      _sessionNotice = (error as ApiException).message;
      unawaited(logout());
    } else if (error is ApiException && error.isForbidden) {
      // 403 hesap pasifleştirme/onay bekleme olabilir: /me ile doğrula (kısıtlı sıklıkta).
      unawaited(refreshSession());
    }
  }

  /// Oturum yalnızca flutter_secure_storage'da saklanır.
  Future<void> _persist() async {
    if (_session == null) {
      return;
    }
    final raw = jsonEncode(_session!.toJson());
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
    if (uid.isEmpty) {
      return;
    }
    final token = status.localControlToken?.trim() ?? '';
    if (token.isEmpty) {
      // Sunucu bu kullanıcıya token vermiyor (yetki kalktı / token döndürüldü):
      // önbellekteki eski token düşürülür, yerel açma denenmez (C4 fail-closed).
      if (_localDoorCache.remove(uid) != null) {
        await _persistLocalDoorCache();
      }
      return;
    }

    final existing = _localDoorCache[uid];
    final port = status.localControlPort ?? 8765;
    final ip = status.localIp ?? existing?.ip;
    final now = DateTime.now();

    // Durum yoklaması her ~3 sn'de bu metodu çağırır; veri değişmediyse güvenli depoya
    // yeniden yazma (saatte en fazla bir kez tazele).
    if (existing != null &&
        existing.token == token &&
        existing.ip == ip &&
        existing.port == port &&
        now.difference(existing.updatedAt) < _localCacheRewriteInterval) {
      return;
    }

    _localDoorCache[uid] = LocalDoorAccess(
      deviceUid: uid,
      token: token,
      ip: ip,
      port: port,
      updatedAt: now,
    );
    await _persistLocalDoorCache();
  }

  /// Yerel yolu yalnızca cihaz canlı beacon gönderiyorsa, telefon yerel Wi-Fi'deyse ve
  /// geçerli bir token önbellekteyse dener. Başarısızsa null döner (bulutla devam edilir).
  Future<(DoorRuntimeStatus?, String?)?> _tryOpenDoorLocallyIfAlive(
    DoorRecord door,
  ) async {
    final uid = door.assignedDeviceUid?.trim().toUpperCase();
    if (uid == null || uid.isEmpty) {
      return null;
    }
    final cached = _localDoorCache[uid];
    if (cached == null || !cached.isUsable || cached.token.trim().isEmpty) {
      return null;
    }
    if (!await _localDoorService.hasLocalWifiConnection()) {
      return null;
    }
    final liveBeacon = _localDoorService.getCachedDevice(uid);
    if (liveBeacon == null || !liveBeacon.isFresh) {
      return null;
    }

    debugPrint('[AuthService] Cihaz yerel ağda canlı (${liveBeacon.ip}), yerel UDP deneniyor...');
    final localResult = await _tryOpenDoorLocally(door);
    if (localResult != null && localResult.$1 != null) {
      return localResult;
    }
    debugPrint('[AuthService] Yerel ağ yanıt vermedi -> buluta devrediliyor...');
    return null;
  }

  Future<(DoorRuntimeStatus?, String?)?> _tryOpenDoorLocally(
    DoorRecord door,
  ) async {
    final uid = door.assignedDeviceUid?.trim().toUpperCase();
    if (uid == null || uid.isEmpty) {
      return null;
    }

    final cached = _localDoorCache[uid];
    if (cached == null || !cached.isUsable || cached.token.trim().isEmpty) {
      return null;
    }
    final liveBeacon = _localDoorService.getCachedDevice(uid);
    final targetIp = liveBeacon?.ip ?? cached.ip ?? door.assignedDeviceLocalIp?.trim();
    // Önbellekteki token'ın GERÇEK yaşı korunur (updatedAt = sunucudan alındığı an);
    // yerel açma başarısı token'ı "yenilemiş" sayılmaz, geçerlilik süresi uzamaz.
    final access = LocalDoorAccess(
      deviceUid: uid,
      token: cached.token,
      ip: targetIp,
      port: liveBeacon?.port ?? cached.port,
      updatedAt: cached.updatedAt,
    );

    final result = await _localDoorService.openDoor(access);
    if (!result.ok) {
      return (null, result.message);
    }

    // Yalnızca IP güncellenir; token ve yaş bilgisi aynen kalır.
    final updatedAccess = LocalDoorAccess(
      deviceUid: access.deviceUid,
      token: access.token,
      ip: result.ip ?? access.ip,
      port: access.port,
      updatedAt: cached.updatedAt,
    );
    if (updatedAccess.ip != cached.ip) {
      _localDoorCache[uid] = updatedAccess;
      await _persistLocalDoorCache();
    }

    final active = session;
    if (active != null) {
      unawaited(
        api
            .notifyLocalDoorOpened(
              token: active.token,
              doorId: door.id,
              localIp: result.ip ?? access.ip,
            )
            .catchError((Object e) {
          _handleSessionError(e, usedToken: active.token);
        }),
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
      _handleSessionError(e, usedToken: active.token);
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
      _handleSessionError(e, usedToken: active.token);
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
      _handleSessionError(e, usedToken: active.token);
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
      _handleSessionError(e, usedToken: active.token);
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
      _handleSessionError(e, usedToken: active.token);
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
      _handleSessionError(e, usedToken: active.token);
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
      _handleSessionError(e, usedToken: active.token);
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
      _handleSessionError(e, usedToken: active.token);
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
      _handleSessionError(e, usedToken: active.token);
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
      _handleSessionError(e, usedToken: active.token);
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
      _handleSessionError(e, usedToken: active.token);
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
      _handleSessionError(e, usedToken: active.token);
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
      _handleSessionError(e, usedToken: active.token);
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
      _handleSessionError(e, usedToken: active.token);
      return (false, e.message);
    } catch (_) {
      return (false, 'Sakin silinirken bir hata oluştu.');
    }
  }

  Future<(bool, String?)> changeApartmentMemberPassword({
    required int apartmentId,
    required int targetUserCode,
    required String newPassword,
    required String currentPassword,
  }) async {
    final active = session;
    if (active == null) {
      return (false, 'Oturum bulunamadı.');
    }
    if (currentPassword.isEmpty) {
      return (false, 'Şifrenizi değiştirmek için mevcut şifrenizi girin.');
    }
    // Kendi şifresi değişirse sunucu eski token'ı iptal eder: eşzamanlı isteklerin TOKEN_REVOKED'ı
    // oturumu kapatmasın (yeni token bu yanıtla gelir).
    _credentialSwapDepth++;
    try {
      final res = await api.changeApartmentMemberPassword(
        token: active.token,
        apartmentId: apartmentId,
        targetUserCode: targetUserCode,
        newPassword: newPassword,
        currentPassword: currentPassword,
      );
      // Parola değişince eski token'lar iptal olur; sunucunun döndürdüğü yeni token'ı yaz.
      final newToken = res['token'];
      if (newToken is String &&
          newToken.isNotEmpty &&
          newToken != active.token &&
          _session?.token == active.token) {
        final updated = active.copyWith(token: newToken);
        _session = updated;
        await _persist();
        final knownDoors = _lastMyDoors;
        if (knownDoors != null) {
          _syncDoorWidget(updated, knownDoors);
        }
        _notifySafely();
      }
      return (true, res['message'] as String? ?? 'Şifre başarıyla güncellendi.');
    } on ApiException catch (e) {
      _handleSessionError(e, usedToken: active.token, ownCredentialSwap: true);
      return (false, e.message);
    } catch (_) {
      return (false, 'Şifre güncellenirken bir hata oluştu.');
    } finally {
      _credentialSwapDepth--;
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
      _handleSessionError(e, usedToken: active.token);
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
      _handleSessionError(e, usedToken: active.token);
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
      _handleSessionError(e, usedToken: active.token);
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
      _handleSessionError(e, usedToken: active.token);
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
      _handleSessionError(e, usedToken: active.token);
      return (false, e.message);
    } catch (_) {
      return (false, 'Davet iptal edilirken bir hata oluştu.');
    }
  }

  Future<(bool, String?)> setDeviceDefectStatus({
    required int deviceId,
    required bool isDefective,
    String? defectiveReason,
  }) async {
    final active = session;
    if (active == null) {
      return (false, 'Oturum bulunamadı.');
    }
    try {
      final res = await api.setDeviceDefectStatus(
        token: active.token,
        deviceId: deviceId,
        isDefective: isDefective,
        defectiveReason: defectiveReason,
      );
      return (true, res['message'] as String? ?? 'Cihaz arıza durumu güncellendi.');
    } on ApiException catch (e) {
      _handleSessionError(e, usedToken: active.token);
      return (false, e.message);
    } catch (_) {
      return (false, 'Arıza durumu güncellenirken bir hata oluştu.');
    }
  }

  Future<(bool, String?)> releaseDeviceOwnership({
    required int deviceId,
    String? reason,
  }) async {
    final active = session;
    if (active == null) {
      return (false, 'Oturum bulunamadı.');
    }
    try {
      final res = await api.releaseDeviceOwnership(
        token: active.token,
        deviceId: deviceId,
        reason: reason,
      );
      return (true, res['message'] as String? ?? 'Cihaz sahipliği sıfırlandı ve depoya alındı.');
    } on ApiException catch (e) {
      _handleSessionError(e, usedToken: active.token);
      return (false, e.message);
    } catch (_) {
      return (false, 'Cihaz sahipliği sıfırlanırken bir hata oluştu.');
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
