import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:site_kapi_kontrol/models/announcement.dart';
import 'package:site_kapi_kontrol/models/apartment_crm.dart';
import 'package:site_kapi_kontrol/models/apartment_pin_issue.dart';
import 'package:site_kapi_kontrol/models/apartment_record.dart';
import 'package:site_kapi_kontrol/models/audit_log.dart';
import 'package:site_kapi_kontrol/models/device_connectivity_log.dart';
import 'package:site_kapi_kontrol/models/device_page.dart';
import 'package:site_kapi_kontrol/models/device_record.dart';
import 'package:site_kapi_kontrol/models/door_access_log_record.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/models/door_runtime_status.dart';
import 'package:site_kapi_kontrol/models/finance.dart';
import 'package:site_kapi_kontrol/models/finance_funds.dart';
import 'package:site_kapi_kontrol/models/finance_home.dart';
import 'package:site_kapi_kontrol/models/guest_pass.dart';
import 'package:site_kapi_kontrol/models/history_item.dart';
import 'package:site_kapi_kontrol/models/legal_document.dart';
import 'package:site_kapi_kontrol/models/local_door_access.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:site_kapi_kontrol/models/managed_user_page.dart';
import 'package:site_kapi_kontrol/models/manager_contact.dart';
import 'package:site_kapi_kontrol/models/management_terms.dart';
import 'package:site_kapi_kontrol/models/module_request.dart';
import 'package:site_kapi_kontrol/models/person_record.dart';
import 'package:site_kapi_kontrol/models/platform_module.dart';
import 'package:site_kapi_kontrol/models/residency_relation.dart';
import 'package:site_kapi_kontrol/models/vehicle_record.dart';
import 'package:site_kapi_kontrol/models/staff_role_record.dart';
import 'package:site_kapi_kontrol/models/site_page.dart';
import 'package:site_kapi_kontrol/models/site_record.dart';
import 'package:site_kapi_kontrol/models/site_application.dart';
import 'package:site_kapi_kontrol/models/site_join_token_record.dart';
import 'package:site_kapi_kontrol/models/join_request_record.dart';
import 'package:site_kapi_kontrol/models/site_join_info.dart';
import 'package:site_kapi_kontrol/models/apartment_member_record.dart';
import 'package:site_kapi_kontrol/models/door_permission_record.dart';
import 'package:site_kapi_kontrol/models/site_residents_tree_record.dart';
import 'package:site_kapi_kontrol/models/site_structure_record.dart';
import 'package:site_kapi_kontrol/models/site_manager_record.dart';
import 'package:site_kapi_kontrol/models/subscription_request_page.dart';
import 'package:site_kapi_kontrol/models/team.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/services/account_local_wipe.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/door_widget_service.dart';
import 'package:site_kapi_kontrol/services/geofence_service.dart';
import 'package:site_kapi_kontrol/services/local_door_service.dart';
import 'package:site_kapi_kontrol/services/login_device_token_store.dart';

class AuthService extends ChangeNotifier {
  AuthService({
    required this.api,
    Future<LocationFixResult> Function()? locationProvider,
    LoginDeviceTokenStore? deviceTokenStore,
  }) : _locationProvider =
            locationProvider ?? GeofenceService.instance.acquireVerifiedPosition,
       _deviceTokenStore = deviceTokenStore ?? LoginDeviceTokenStore();

  static const String _storageKey = 'auth_session';
  static const String _localDoorCacheKey = 'local_door_cache';
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  /// /me doğrulamasının (C11) art arda çağrılması arasındaki asgari süre.
  static const Duration _sessionCheckMinInterval = Duration(seconds: 20);

  /// Yerel erişim önbelleği değişmediyse en fazla bu sıklıkta yeniden yazılır.
  static const Duration _localCacheRewriteInterval = Duration(hours: 1);

  final AuthApi api;
  final Future<LocationFixResult> Function() _locationProvider;

  /// Güvenilir cihaz belirteci deposu (giriş kilidi koruması; bkz. [LoginDeviceTokenStore]).
  final LoginDeviceTokenStore _deviceTokenStore;
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
  DateTime? _sessionVerifiedAt;

  /// Süren parola değişimi sayısı (updateMyProfile / changeApartmentMemberPassword). Sunucu
  /// parolayı yazar yazmaz eski token'ı iptal eder, yeni token ise ancak yanıtla gelir; bu aralıkta
  /// eşzamanlı bir isteğin TOKEN_REVOKED 401'i oturumu yanlışlıkla kapatmasın diye sayılır.
  int _credentialSwapDepth = 0;

  /// Telefon bildirimi (Faz 3b-B): [logout] oturumu silmeden HEMEN ÖNCE, belirteç hâlâ elde iken çağrılır.
  /// `PushService` cihaz kaydını bu belirteçle sunucudan siler ve FCM jetonunu geçersiz kılar. Beklenmez
  /// (arayüz giriş ekranına hemen döner); hatası çıkışı bozmaz.
  void Function(UserSession ending)? onSessionEnding;

  UserSession? get session => _session;

  /// Oturum bilgisinin (rol dahil) sunucudaki `/me` ile SON BAŞARILI doğrulandığı an; hiç doğrulanmadıysa
  /// null. [refreshSession] hata durumunu yutar; çağıran yenilemenin gerçekten başarılı olup olmadığını
  /// bu değerin ilerlemesinden anlar (örn. onaylanmış başvuruda rol hâlâ bireyselse "yenilendi ama rol
  /// değişmedi" ile "yenilenemedi"yi ayırmak için).
  DateTime? get sessionVerifiedAt => _sessionVerifiedAt;
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
      _sessionVerifiedAt = DateTime.now();
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
      if (e.code == _passwordChangeRequiredCode) {
        // Sunucu zorunlu şifre belirlemeyi istiyor (hesap geçerli): oturum düşürülmez, "şifre belirleme gerekli" durumuna geçilir.
        _markPasswordChangeRequired();
        return;
      }
      if (e.isUnauthorized || e.isForbidden) {
        if (_credentialSwapDepth > 0 && e.code == 'TOKEN_REVOKED') {
          return; // Parola değişimi sürüyor: yeni token değişim yanıtıyla gelecek.
        }
        final deleted = e.code == _accountDeletedCode;
        _sessionNotice = deleted ? _accountDeletedNotice : e.message;
        if (deleted) await LocalDataWiper().clearSavedLoginIdentifier();
        await logout();
        if (deleted) await _wipeAfterRemoteDeletion();
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
        a.phoneNumber != b.phoneNumber ||
        a.trialExpiresAt != b.trialExpiresAt;
  }

  Future<String?> login({
    required String email,
    required String password,
    UserRole? role,
  }) async {
    try {
      // Önceki girişte sunucunun verdiği güvenilir cihaz belirteci (varsa) gönderilir; yeni belirteç gelirse
      // saklanır. Depolama hataları girişi etkilemez. ÇIKIŞTA silinmez (bkz. [LoginDeviceTokenStore]).
      final deviceToken = await _deviceTokenStore.read(email);
      String? issuedDeviceToken;
      _session = await api.login(
        email: email,
        password: password,
        role: role,
        deviceToken: deviceToken,
        onDeviceToken: (token) => issuedDeviceToken = token,
      );
      final issued = issuedDeviceToken;
      if (issued != null) {
        final active = _session;
        await _deviceTokenStore.save(<String?>[email, active?.email, active?.loginName], issued);
      }
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

  /// SMS ile giriş açık mı (sunucuda sağlayıcı anahtarı var mı).
  Future<bool> smsLoginEnabled() => api.smsLoginEnabled();

  /// Telefona giriş kodu ister; hata mesajı ya da null.
  Future<String?> requestSmsCode({required String phone}) async {
    try {
      await api.requestSmsCode(phone: phone);
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Sunucuya baglanilamadi.';
    }
  }

  /// Telefon + SMS koduyla giriş; hata mesajı ya da null (başarı).
  /// Sosyal giriş (Google / iCloud Apple) yapılandırma durumu.
  Future<Map<String, dynamic>> oauthStatus() => api.oauthStatus();

  /// Google veya iCloud (Apple) kimlik doğrulama belirteci ile kayıt / giriş yapar; hata mesajı ya da null (başarı).
  /// [nonce]: yerel girişte üretilen HAM nonce (sağlayıcıya SHA-256 özeti verilmiş olmalı; bkz. social_auth_buttons.dart). Sağlayıcı nonce'u
  /// belirtece koyamıyorsa (google_sign_in 6.x) null bırakılır; sunucu OAUTH_REQUIRE_NONCE kapalıyken bunu kabul eder.
  Future<String?> loginWithOAuth({
    required String provider,
    required String idToken,
    String? fullName,
    String? firstName,
    String? lastName,
    List<AcceptedDocument>? acceptedDocuments,
    String? nonce,
  }) async {
    try {
      String? issuedDeviceToken;
      _session = await api.loginWithOAuth(
        provider: provider,
        idToken: idToken,
        nonce: nonce,
        fullName: fullName,
        firstName: firstName,
        lastName: lastName,
        acceptedDocuments: acceptedDocuments,
        onDeviceToken: (token) => issuedDeviceToken = token,
      );
      final issued = issuedDeviceToken;
      if (issued != null) {
        final active = _session;
        await _deviceTokenStore.save(<String?>[active?.email, active?.loginName], issued);
      }
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

  /// Google veya iCloud (Apple) e-posta adresine 6 haneli doğrulama kodu gönderir; hata mesajı ya da null.
  Future<String?> requestOAuthEmailCode({
    required String provider,
    required String email,
    String? fullName,
    String? firstName,
    String? lastName,
  }) async {
    try {
      await api.requestOAuthEmailCode(
        provider: provider,
        email: email,
        fullName: fullName,
        firstName: firstName,
        lastName: lastName,
      );
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Sunucuya bağlanılamadı. Lütfen internet bağlantınızı kontrol ediniz.';
    }
  }

  /// Google veya iCloud (Apple) e-posta adresine gönderilen 6 haneli doğrulama kodunu onaylar.
  Future<String?> verifyOAuthEmailCode({
    required String provider,
    required String email,
    required String code,
    String? fullName,
    String? firstName,
    String? lastName,
    List<AcceptedDocument>? acceptedDocuments,
  }) async {
    try {
      final deviceToken = await _deviceTokenStore.read(email);
      String? issuedDeviceToken;
      _session = await api.verifyOAuthEmailCode(
        provider: provider,
        email: email,
        code: code,
        fullName: fullName,
        firstName: firstName,
        lastName: lastName,
        acceptedDocuments: acceptedDocuments,
        deviceToken: deviceToken,
        onDeviceToken: (token) => issuedDeviceToken = token,
      );
      final issued = issuedDeviceToken;
      if (issued != null) {
        final active = _session;
        await _deviceTokenStore.save(<String?>[email, active?.email, active?.loginName], issued);
      }
      _lastSessionCheckAt = DateTime.now();
      await _persist();
      _notifySafely();
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Sunucuya bağlanılamadı. Lütfen internet bağlantınızı kontrol ediniz.';
    }
  }

  /// Tarayıcı yönlendirme oturumunu başlatır (`redirect` veya `email_code` döner).
  Future<Map<String, dynamic>> startOAuthWebSession({
    required String provider,
    List<AcceptedDocument>? acceptedDocuments,
  }) => api.startOAuthWebSession(
        provider: provider,
        acceptedDocuments: acceptedDocuments,
      );

  /// Tarayıcı yönlendirmesi tamamlandıysa oturumu kaydedip `completed` döndürür.
  Future<({String status, String? error})> pollOAuthWebSession({
    required String sessionId,
  }) async {
    try {
      final payload = await api.pollOAuthWebSession(sessionId: sessionId);
      final status = payload['status'] as String? ?? 'pending';
      if (status == 'completed') {
        final userMap = payload['user'] as Map<String, dynamic>?;
        final token = payload['token'] as String?;
        if (userMap != null && token != null && token.isNotEmpty) {
          _session = UserSession.fromJson(<String, dynamic>{
            ...userMap,
            'token': token,
          });
          final deviceToken = payload['device_token'] as String?;
          if (deviceToken != null && deviceToken.isNotEmpty) {
            await _deviceTokenStore.save(
              <String?>[_session?.email, _session?.loginName],
              deviceToken,
            );
          }
          _lastSessionCheckAt = DateTime.now();
          await _persist();
          _notifySafely();
          return (status: 'completed', error: null);
        }
      }
      if (status == 'error') {
        return (
          status: 'error',
          error: payload['error'] as String? ?? 'Giriş tamamlanamadı.',
        );
      }
      return (status: 'pending', error: null);
    } on ApiException catch (e) {
      return (status: 'error', error: e.message);
    } catch (_) {
      return (status: 'pending', error: null);
    }
  }

  /// Deneme erişim kodu (P2-27, karar K10) ile giriş: tek kullanımlık kod, 72 saatlik, YALNIZ demo siteye kilitli oturum.
  /// Oturum `trialExpiresAt` taşır (üstte "Deneme - X saat kaldı" şeridi). Hata mesajı ya da null (başarı).
  Future<String?> loginWithTrialCode({required String code}) async {
    try {
      _session = await api.redeemTrialCode(code: code);
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

  Future<String?> loginWithSms({required String phone, required String code}) async {
    try {
      _session = await api.verifySmsCode(phone: phone, code: code);
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
    List<AcceptedDocument>? acceptedDocuments,
  }) async {
    try {
      await api.registerIndividual(
        firstName: firstName,
        lastName: lastName,
        email: email,
        password: password,
        acceptedDocuments: acceptedDocuments,
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
        // Aktif kod yok: kod 30 dakika geçerlidir; kullanıcıyı yeni kod istemeye yönlendir.
        return '${e.message} Kod 30 dakika geçerlidir; yeni kod için "Kodu Tekrar Gönder"e dokunun.';
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
    // Cihaz sahiplenmek kullanıcıyı site yöneticisi YAPMAZ (site yöneticisi olmak için site başvurusu
    // gerekir; rol değişmez). Rol yine de yerelde tahmin edilmez: /me ile eşitle (C11).
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
    String? managementType,
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
        managementType: managementType,
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
    // Telefon bildirimi: cihaz kaydının silinmesi oturum belirteci silinmeden ÖNCE yola çıkar (en iyi çaba).
    final ending = _session;
    if (ending != null) {
      try {
        onSessionEnding?.call(ending);
      } catch (_) {}
    }
    _session = null;
    _lastSessionCheckAt = null;
    _lastMyDoors = null;
    _lastMyModules = null;
    _doorControlClosedSites.clear();
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

    // Kişisel veri içeren yerel geçici dosyalar (dışa aktarma, toplu yükleme, belge kopyaları ve eklenti
    // önbellekleri) çıkışta da silinir; yalnız hesap silmede değil. En iyi çaba, hata fırlatmaz.
    unawaited(LocalDataWiper.sweepSharedFiles());
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
    String? managementType,
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
        managementType: managementType,
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

  // --- Platform modül sistemi (Faz 1) -------------------------------------------------------
  // Okuma ve yazma çağrıları hata durumunda ApiException FIRLATIR (listSites gibi); oturum hatası
  // merkezi olarak [_runAuthorized] içinde işlenir. Hata kodları AuthApi.messageForErrorCode ile
  // Türkçeye çevrilmiş olarak `ApiException.message` içinde gelir.

  /// Modül kataloğu (`GET /app/modules/catalog`).
  Future<List<PlatformModule>> getModuleCatalog() {
    return _runAuthorized((token) => api.getModuleCatalog(token: token));
  }

  /// Yönetim türleri: terimler, önerilen modüller ve açıklama (`GET /app/management-types`, F9). Eski
  /// sunucuda uç yoktur: çağıran ApiException alınca [ManagementTypeInfo.builtInAll] ile devam eder
  /// (seçici de `types` verilmezse aynı yerleşik tanımları gösterir).
  Future<List<ManagementTypeInfo>> getManagementTypes() {
    return _runAuthorized((token) => api.getManagementTypes(token: token));
  }

  /// Kullanıcının bağlı olduğu sitelerde modül durumları (`GET /app/my-modules`).
  Future<MyModulesResult> getMyModules() {
    return _runAuthorized((token) async {
      final result = await api.getMyModules(token: token);
      // Son başarılı yanıt önbelleğe alınır (kısayol / derin bağlantı mesajları ağ isteği yapmadan
      // modül durumunu okuyabilsin); oturum bu arada değiştiyse eski kullanıcının verisi saklanmaz.
      if (_session?.token == token) {
        _lastMyModules = result;
        // Kapı erişimi olan siteler için Geçiş Kontrol durumu; süper kullanıcı (`scope: all`) yanıtında
        // site yoktur, bilinen siteler (getSiteModules ile) korunur.
        if (!result.isAll) {
          _doorControlClosedSites
            ..clear()
            ..addAll(
              result.doorAccessSites
                  .where((s) => !s.isEnabled(PlatformModuleCodes.doorControl))
                  .map((s) => s.siteCode),
            );
        }
      }
      return result;
    });
  }

  /// Geçiş Kontrol modülünün KAPALI olduğu bilinen sitelerin kodları. [openDoor] bu sitelerde yerel
  /// ağ (LAN) kısayolunu denemez: yerel açma cihaz üzerinde yapıldığından sunucunun modül koruması
  /// devreye girmez; uzak yol sunucuya gider ve karar (MODULE_DISABLED) orada verilir.
  final Set<int> _doorControlClosedSites = <int>{};

  void _noteSiteModules(SiteModulesState state) {
    final door = state.module(PlatformModuleCodes.doorControl);
    if (door == null) return;
    if (door.enabled) {
      _doorControlClosedSites.remove(state.siteCode);
    } else {
      _doorControlClosedSites.add(state.siteCode);
    }
  }

  MyModulesResult? _lastMyModules;

  /// Son başarılı `getMyModules` yanıtı; hiç alınmadıysa ya da çıkıştan sonra null.
  MyModulesResult? get cachedMyModules => _lastMyModules;

  /// Bir sitenin modül durumu (site yöneticisi / süper kullanıcı).
  Future<SiteModulesState> getSiteModules(int siteCode) {
    return _runAuthorized((token) async {
      final state = await api.getSiteModules(token: token, siteCode: siteCode);
      if (_session?.token == token) _noteSiteModules(state);
      return state;
    });
  }

  /// Modülü açar/kapatır; Geçiş Kontrol KAPATILIRKEN [confirm] true verilmelidir.
  Future<SiteModulesState> setSiteModule(
    int siteCode,
    String moduleCode,
    bool enabled, {
    bool confirm = false,
  }) async {
    return _runAuthorized((token) async {
      final state = await api.setSiteModule(
        token: token,
        siteCode: siteCode,
        moduleCode: moduleCode,
        enabled: enabled,
        confirm: confirm,
      );
      if (_session?.token == token) _noteSiteModules(state);
      return state;
    });
  }

  /// Denetim kaydı sayfası (yalnız süper kullanıcı; sunucu doğrular).
  Future<AuditLogPage> listAuditLog({
    int? siteCode,
    int limit = 50,
    int? beforeId,
    String? action,
  }) {
    return _runAuthorized(
      (token) => api.listAuditLog(
        token: token,
        siteCode: siteCode,
        limit: limit,
        beforeId: beforeId,
        action: action,
      ),
    );
  }

  Future<List<StaffRoleRecord>> listStaffRoles(int siteCode) {
    return _runAuthorized(
      (token) => api.listStaffRoles(token: token, siteCode: siteCode),
    );
  }

  /// [role]: `BOARD_MEMBER` ya da `STAFF`.
  Future<StaffRoleRecord> assignStaffRole(
    int siteCode,
    String email,
    String role,
  ) async {
    final res = await _runAuthorized(
      (token) => api.assignStaffRole(
        token: token,
        siteCode: siteCode,
        email: email,
        role: role,
      ),
    );
    return res;
  }

  Future<void> removeStaffRole(int siteCode, int userCode) async {
    await _runAuthorized(
      (token) => api.removeStaffRole(
        token: token,
        siteCode: siteCode,
        userCode: userCode,
      ),
    );
  }

  // --- Yönetim kadrosu, davet, rehber (058) ------------------------------------------------

  Future<TeamData> getTeam(int siteCode) =>
      _runAuthorized((token) => api.getTeam(token: token, siteCode: siteCode));

  Future<String?> setTeamDuty(
    int siteCode,
    int personId, {
    required String duty,
    String? title,
    String? publicPhone,
    bool showInDirectory = true,
  }) => _runAuthorized(
    (token) => api.setTeamDuty(
      token: token,
      siteCode: siteCode,
      personId: personId,
      duty: duty,
      title: title,
      publicPhone: publicPhone,
      showInDirectory: showInDirectory,
    ),
  );

  Future<void> endTeamDuty(int siteCode, int personId) => _runAuthorized(
    (token) => api.endTeamDuty(token: token, siteCode: siteCode, personId: personId),
  );

  Future<PersonInvitationState> getPersonInvitation(int siteCode, int personId) =>
      _runAuthorized(
        (token) => api.getPersonInvitation(token: token, siteCode: siteCode, personId: personId),
      );

  Future<PersonInvitationState> sendPersonInvitation(int siteCode, int personId) =>
      _runAuthorized(
        (token) => api.sendPersonInvitation(token: token, siteCode: siteCode, personId: personId),
      );

  Future<void> revokePersonInvitation(int siteCode, int personId) => _runAuthorized(
    (token) => api.revokePersonInvitation(token: token, siteCode: siteCode, personId: personId),
  );

  Future<Map<String, dynamic>> provisionPersonAccount(
    int siteCode,
    int personId, {
    String? loginName,
    String? password,
    String? email,
  }) =>
      _runAuthorized(
        (token) => api.provisionPersonAccount(
          token: token,
          siteCode: siteCode,
          personId: personId,
          loginName: loginName,
          password: password,
          email: email,
        ),
      );

  Future<Map<String, dynamic>> resetPersonPinDirect(int siteCode, int personId) =>
      _runAuthorized(
        (token) => api.resetPersonPinDirect(
          token: token,
          siteCode: siteCode,
          personId: personId,
        ),
      );

  Future<Map<String, dynamic>> sendPersonPasswordReset(int siteCode, int personId) =>
      _runAuthorized(
        (token) => api.sendPersonPasswordReset(token: token, siteCode: siteCode, personId: personId),
      );

  Future<Map<String, dynamic>> executePeopleBulkAction(
    int siteCode, {
    required String action,
    required List<int> personIds,
  }) =>
      _runAuthorized(
        (token) => api.executePeopleBulkAction(
          token: token,
          siteCode: siteCode,
          action: action,
          personIds: personIds,
        ),
      );

  Future<void> saveDirectoryContact(
    int siteCode, {
    int? contactId,
    required String label,
    required String phone,
    String? note,
    required String category,
  }) => _runAuthorized(
    (token) => api.saveDirectoryContact(
      token: token,
      siteCode: siteCode,
      contactId: contactId,
      label: label,
      phone: phone,
      note: note,
      category: category,
    ),
  );

  Future<void> deleteDirectoryContact(int siteCode, int contactId) => _runAuthorized(
    (token) => api.deleteDirectoryContact(token: token, siteCode: siteCode, contactId: contactId),
  );

  Future<List<DirectorySite>> getDirectory() =>
      _runAuthorized((token) => api.getDirectory(token: token));

  /// Sakin "Yöneticiyi ara": bağı olunan her sitenin yönetici adı ve telefonu (telefon yoksa null).
  Future<List<ManagerContact>> getManagerContacts() =>
      _runAuthorized((token) => api.getManagerContacts(token: token));

  Future<List<PendingInvitation>> listMyInvitations() =>
      _runAuthorized((token) => api.listMyInvitations(token: token));

  Future<void> answerInvitation(int invitationId, {required bool accept}) => _runAuthorized(
    (token) => api.answerInvitation(token: token, invitationId: invitationId, accept: accept),
  );

  // --- Modül talebi (Faz 1.1) ---------------------------------------------------------------

  /// Site yöneticisi: [moduleCode] modülü için süper kullanıcıya talep gönderir.
  Future<ModuleRequest> createModuleRequest(
    int siteCode,
    String moduleCode, {
    String? note,
  }) {
    return _runAuthorized(
      (token) => api.createModuleRequest(
        token: token,
        siteCode: siteCode,
        moduleCode: moduleCode,
        note: note,
      ),
    );
  }

  Future<List<ModuleRequest>> listModuleRequests(int siteCode) {
    return _runAuthorized(
      (token) => api.listModuleRequests(token: token, siteCode: siteCode),
    );
  }

  /// Bekleyen talebi geri çeker.
  Future<ModuleRequest> cancelModuleRequest(int siteCode, int requestId) {
    return _runAuthorized(
      (token) => api.cancelModuleRequest(
        token: token,
        siteCode: siteCode,
        requestId: requestId,
      ),
    );
  }

  /// Süper kullanıcı: talepler ([status]: `pending|approved|rejected|cancelled|all`) ve bekleyen sayısı.
  Future<ModuleRequestPage> listAdminModuleRequests({
    String? status,
    int limit = 50,
    int? beforeId,
  }) {
    return _runAuthorized(
      (token) => api.listAdminModuleRequests(
        token: token,
        status: status,
        limit: limit,
        beforeId: beforeId,
      ),
    );
  }

  /// Süper kullanıcı: talebi onaylar ([approve] true) ya da reddeder; [note] isteğe bağlı gerekçe.
  Future<ModuleRequest> decideModuleRequest(
    int requestId,
    bool approve, {
    String? note,
  }) {
    return _runAuthorized(
      (token) => api.decideModuleRequest(
        token: token,
        requestId: requestId,
        approve: approve,
        note: note,
      ),
    );
  }

  // --- Site başvurusu (site yöneticisi olma) -----------------------------------------------
  // Hata durumunda ApiException FIRLATIR (Türkçe mesajlı); oturum hatası [_runAuthorized] içinde işlenir.
  // Başvuru yalnız bireysel / daire kullanıcısı rolünde yapılır; rol onayla sunucuda değişir ve yerelde
  // TAHMİN EDİLMEZ: onaydan sonra [refreshSession] (`force: true`) çağrılır.

  /// Başvuran: site başvurusu gönderir (`POST /membership/site-applications`). Cihaz isteğe bağlıdır.
  Future<SiteApplication> createSiteApplication({
    required String name,
    String? city,
    String? district,
    String? address,
    required List<Map<String, dynamic>> blocks,
    List<Map<String, dynamic>>? doors,
    int doorCount = 1,
    String? deviceUid,
    String? managementType,
    String? note,
    List<AcceptedDocument>? acceptedDocuments,
  }) {
    return _runAuthorized(
      (token) => api.createSiteApplication(
        token: token,
        name: name,
        city: city,
        district: district,
        address: address,
        blocks: blocks,
        doors: doors,
        doorCount: doorCount,
        deviceUid: deviceUid,
        managementType: managementType,
        note: note,
        acceptedDocuments: acceptedDocuments,
      ),
    );
  }

  /// Başvuran: bekleyen başvuru ve son başvurular.
  Future<MySiteApplications> getMySiteApplications() {
    return _runAuthorized((token) => api.getMySiteApplications(token: token));
  }

  /// Başvuran: kendi bekleyen başvurusunu iptal eder.
  Future<SiteApplication> cancelSiteApplication(int applicationId) {
    return _runAuthorized(
      (token) => api.cancelSiteApplication(token: token, applicationId: applicationId),
    );
  }

  /// Süper kullanıcı: başvurular (`status`: `pending|approved|rejected|cancelled|all`).
  Future<SiteApplicationPage> listAdminSiteApplications({
    String? status,
    String? query,
    int limit = 30,
    int offset = 0,
  }) {
    return _runAuthorized(
      (token) => api.listAdminSiteApplications(
        token: token,
        status: status,
        query: query,
        limit: limit,
        offset: offset,
      ),
    );
  }

  /// Süper kullanıcı: bekleyen başvuru sayısı (çekmece rozeti).
  Future<int> getAdminSiteApplicationsPendingCount() {
    return _runAuthorized((token) => api.getAdminSiteApplicationsPendingCount(token: token));
  }

  /// Süper kullanıcı: tek başvuru (başvuran iletişimi ve cihaz durumuyla).
  Future<SiteApplication> getAdminSiteApplication(int applicationId) {
    return _runAuthorized(
      (token) => api.getAdminSiteApplication(token: token, applicationId: applicationId),
    );
  }

  /// Süper kullanıcı: başvuruyu onaylar; sunucu tek işlemde siteyi kurar ve başvuranı site yöneticisi yapar.
  Future<SiteApplicationDecision> approveSiteApplication(int applicationId, {String? note}) {
    return _runAuthorized(
      (token) => api.approveSiteApplication(
        token: token,
        applicationId: applicationId,
        note: note,
      ),
    );
  }

  /// Süper kullanıcı: başvuruyu reddeder; [reason] isteğe bağlı gerekçe.
  Future<SiteApplication> rejectSiteApplication(int applicationId, {String? reason}) {
    return _runAuthorized(
      (token) => api.rejectSiteApplication(
        token: token,
        applicationId: applicationId,
        reason: reason,
      ),
    );
  }

  // --- Kişi ve Daire Kayıtları (Faz 2a) -----------------------------------------------------
  // Hata durumunda ApiException FIRLATIR (Türkçe mesajlı); oturum hatası [_runAuthorized] içinde işlenir.

  /// Kişi listesi (`GET /manager/sites/:siteCode/people`). [status]: `active|inactive|all`.
  Future<PersonPage> listPeople(
    int siteCode, {
    String? query,
    ResidencyRelation? relation,
    String? status,
    int? apartmentId,
    int limit = 50,
    int offset = 0,
  }) {
    return _runAuthorized(
      (token) => api.listPeople(
        token: token,
        siteCode: siteCode,
        query: query,
        relation: relation,
        status: status,
        apartmentId: apartmentId,
        limit: limit,
        offset: offset,
      ),
    );
  }

  Future<PersonDetail> getPerson(int siteCode, int personId) {
    return _runAuthorized(
      (token) => api.getPerson(token: token, siteCode: siteCode, personId: personId),
    );
  }

  /// Kişi ekler; [apartmentId] verilirse [relation] ile o daireye bağlanır.
  Future<PersonDetail> createPerson(
    int siteCode, {
    required String fullName,
    String? phone,
    String? email,
    String? note,
    int? apartmentId,
    ResidencyRelation? relation,
    DateTime? moveInDate,
  }) {
    return _runAuthorized(
      (token) => api.createPerson(
        token: token,
        siteCode: siteCode,
        fullName: fullName,
        phone: phone,
        email: email,
        note: note,
        apartmentId: apartmentId,
        relation: relation,
        moveInDate: moveInDate,
      ),
    );
  }

  /// Kişiyi günceller; yalnız [fields] içindeki alanlar gönderilir.
  Future<PersonDetail> updatePerson(
    int siteCode,
    int personId,
    Map<String, Object?> fields,
  ) {
    return _runAuthorized(
      (token) => api.updatePerson(
        token: token,
        siteCode: siteCode,
        personId: personId,
        fields: fields,
      ),
    );
  }

  Future<PersonDetail> addResidency(
    int siteCode,
    int personId, {
    required int apartmentId,
    required ResidencyRelation relation,
    DateTime? moveInDate,
  }) {
    return _runAuthorized(
      (token) => api.addResidency(
        token: token,
        siteCode: siteCode,
        personId: personId,
        apartmentId: apartmentId,
        relation: relation,
        moveInDate: moveInDate,
      ),
    );
  }

  Future<PersonDetail> updateResidency(
    int siteCode,
    int residencyId, {
    ResidencyRelation? relation,
    DateTime? moveInDate,
    bool clearMoveInDate = false,
  }) {
    return _runAuthorized(
      (token) => api.updateResidency(
        token: token,
        siteCode: siteCode,
        residencyId: residencyId,
        relation: relation,
        moveInDate: moveInDate,
        clearMoveInDate: clearMoveInDate,
      ),
    );
  }

  /// "Taşındı": ilişkiyi bitirir (kayıt silinmez); hesabı olan kişinin o dairedeki kapı yetkisi kapanır.
  Future<PersonDetail> endResidency(
    int siteCode,
    int residencyId, {
    DateTime? moveOutDate,
  }) {
    return _runAuthorized(
      (token) => api.endResidency(
        token: token,
        siteCode: siteCode,
        residencyId: residencyId,
        moveOutDate: moveOutDate,
      ),
    );
  }

  Future<ApartmentPage> listApartments(
    int siteCode, {
    int? blockId,
    String? query,
    int limit = 50,
    int offset = 0,
  }) {
    return _runAuthorized(
      (token) => api.listApartments(
        token: token,
        siteCode: siteCode,
        blockId: blockId,
        query: query,
        limit: limit,
        offset: offset,
      ),
    );
  }

  Future<ApartmentDetail> getApartment(int siteCode, int apartmentId) {
    return _runAuthorized(
      (token) => api.getApartment(
        token: token,
        siteCode: siteCode,
        apartmentId: apartmentId,
      ),
    );
  }

  /// Daire alanlarını günceller; yalnız [fields] içindeki alanlar gönderilir.
  Future<ApartmentDetail> updateApartment(
    int siteCode,
    int apartmentId,
    Map<String, Object?> fields,
  ) {
    return _runAuthorized(
      (token) => api.updateApartment(
        token: token,
        siteCode: siteCode,
        apartmentId: apartmentId,
        fields: fields,
      ),
    );
  }

  Future<VehiclePage> listVehicles(
    int siteCode, {
    String? query,
    int? personId,
    int limit = 50,
    int offset = 0,
  }) {
    return _runAuthorized(
      (token) => api.listVehicles(
        token: token,
        siteCode: siteCode,
        query: query,
        personId: personId,
        limit: limit,
        offset: offset,
      ),
    );
  }

  Future<VehicleRecord> createVehicle(
    int siteCode,
    int personId,
    String plate, {
    String? note,
  }) {
    return _runAuthorized(
      (token) => api.createVehicle(
        token: token,
        siteCode: siteCode,
        personId: personId,
        plate: plate,
        note: note,
      ),
    );
  }

  Future<void> removeVehicle(int siteCode, int vehicleId) async {
    await _runAuthorized(
      (token) => api.removeVehicle(
        token: token,
        siteCode: siteCode,
        vehicleId: vehicleId,
      ),
    );
  }

  /// Değişiklik geçmişi. [targetType]: `person|apartment|vehicle`; sonraki sayfa için
  /// `HistoryPage.nextBeforeId` [beforeId] olarak verilir.
  Future<HistoryPage> listHistory(
    int siteCode, {
    String? targetType,
    int? targetId,
    int limit = 50,
    int? beforeId,
  }) {
    return _runAuthorized(
      (token) => api.listHistory(
        token: token,
        siteCode: siteCode,
        targetType: targetType,
        targetId: targetId,
        limit: limit,
        beforeId: beforeId,
      ),
    );
  }

  /// Sakinin kendi güncel kayıtları (`GET /app/my-records`).
  Future<List<MyRecord>> getMyRecords() {
    return _runAuthorized((token) => api.getMyRecords(token: token));
  }

  // --- Duyuru ve Bildirim (Faz 3a) ----------------------------------------------------------
  // Hata durumunda ApiException FIRLATIR (Türkçe mesajlı); oturum hatası [_runAuthorized] içinde işlenir.

  /// Yönetici duyuru listesi. [status]: `draft|scheduled|published|withdrawn|all`.
  Future<AnnouncementPage> listAnnouncements(
    int siteCode, {
    String? status,
    String? query,
    int limit = 30,
    int offset = 0,
  }) {
    return _runAuthorized(
      (token) => api.listAnnouncements(
        token: token,
        siteCode: siteCode,
        status: status,
        query: query,
        limit: limit,
        offset: offset,
      ),
    );
  }

  Future<AnnouncementDetail> getAnnouncement(int siteCode, int announcementId) {
    return _runAuthorized(
      (token) => api.getAnnouncement(
        token: token,
        siteCode: siteCode,
        announcementId: announcementId,
      ),
    );
  }

  /// Alıcılar (kurul üyesine 403). [read]: `all|true|false`.
  Future<AnnouncementRecipientPage> listAnnouncementRecipients(
    int siteCode,
    int announcementId, {
    String? read,
    String? query,
    int limit = 50,
    int offset = 0,
  }) {
    return _runAuthorized(
      (token) => api.listAnnouncementRecipients(
        token: token,
        siteCode: siteCode,
        announcementId: announcementId,
        read: read,
        query: query,
        limit: limit,
        offset: offset,
      ),
    );
  }

  Future<AudiencePreview> previewAnnouncementAudience(
    int siteCode,
    AnnouncementTargetInput target, {
    bool sendEmail = false,
  }) {
    return _runAuthorized(
      (token) => api.previewAnnouncementAudience(
        token: token,
        siteCode: siteCode,
        target: target,
        sendEmail: sendEmail,
      ),
    );
  }

  /// [publish]: `draft|now|schedule`; `schedule` iken [publishAt] (en az 1 dakika, en çok 1 yıl sonra).
  Future<AnnouncementDetail> createAnnouncement(
    int siteCode, {
    required String title,
    required String body,
    required AnnouncementTargetInput target,
    AnnouncementImportance importance = AnnouncementImportance.normal,
    bool sendEmail = false,
    String publish = 'draft',
    DateTime? publishAt,
    List<int>? documentIds,
  }) {
    return _runAuthorized(
      (token) => api.createAnnouncement(
        token: token,
        siteCode: siteCode,
        title: title,
        body: body,
        target: target,
        importance: importance,
        sendEmail: sendEmail,
        publish: publish,
        publishAt: publishAt,
        documentIds: documentIds,
      ),
    );
  }

  /// Yalnız [fields] içindeki alanlar gönderilir; yayınlanmış duyuruda yalnız `title` / `body`.
  Future<AnnouncementDetail> updateAnnouncement(
    int siteCode,
    int announcementId,
    Map<String, Object?> fields,
  ) {
    return _runAuthorized(
      (token) => api.updateAnnouncement(
        token: token,
        siteCode: siteCode,
        announcementId: announcementId,
        fields: fields,
      ),
    );
  }

  Future<AnnouncementDetail> publishAnnouncement(int siteCode, int announcementId) {
    return _runAuthorized(
      (token) => api.publishAnnouncement(
        token: token,
        siteCode: siteCode,
        announcementId: announcementId,
      ),
    );
  }

  Future<AnnouncementDetail> withdrawAnnouncement(int siteCode, int announcementId) {
    return _runAuthorized(
      (token) => api.withdrawAnnouncement(
        token: token,
        siteCode: siteCode,
        announcementId: announcementId,
      ),
    );
  }

  Future<void> deleteAnnouncement(int siteCode, int announcementId) async {
    await _runAuthorized(
      (token) => api.deleteAnnouncement(
        token: token,
        siteCode: siteCode,
        announcementId: announcementId,
      ),
    );
  }

  /// Sakin gelen kutusu; sonraki sayfa için `nextBeforeId` [beforeId] olarak verilir.
  Future<ResidentAnnouncementPage> listMyAnnouncements({
    int limit = 30,
    int? beforeId,
    int? siteCode,
  }) {
    return _runAuthorized(
      (token) => api.listMyAnnouncements(
        token: token,
        limit: limit,
        beforeId: beforeId,
        siteCode: siteCode,
      ),
    );
  }

  /// Sakin için tam kayıt (OKUNDU YAZMAZ).
  Future<ResidentAnnouncement> getMyAnnouncement(int announcementId) {
    return _runAuthorized(
      (token) => api.getMyAnnouncement(token: token, announcementId: announcementId),
    );
  }

  /// Duyuruyu okundu işaretler (idempotent); ilk okuma zamanını döndürür.
  Future<DateTime?> markAnnouncementRead(int announcementId) {
    return _runAuthorized(
      (token) => api.markAnnouncementRead(token: token, announcementId: announcementId),
    );
  }

  /// Duyuruyu kendi listemden kaldırır (Geri al için [restoreAnnouncement]).
  Future<void> hideAnnouncement(int announcementId) {
    return _runAuthorized(
      (token) => api.hideAnnouncement(token: token, announcementId: announcementId),
    );
  }

  /// Kaldırılan duyuruyu listeye geri getirir.
  Future<void> restoreAnnouncement(int announcementId) {
    return _runAuthorized(
      (token) => api.restoreAnnouncement(token: token, announcementId: announcementId),
    );
  }

  /// Tümünü okundu yapar; işaretlenen adedi döndürür.
  Future<int> markAllAnnouncementsRead({int? siteCode}) {
    return _runAuthorized(
      (token) => api.markAllAnnouncementsRead(token: token, siteCode: siteCode),
    );
  }

  /// Bildirim özeti (yoklanır).
  Future<NotificationSummary> getNotificationSummary() {
    return _runAuthorized((token) => api.getNotificationSummary(token: token));
  }

  Future<NotificationPrefs> getNotificationPreferences() {
    return _runAuthorized((token) => api.getNotificationPreferences(token: token));
  }

  /// Yalnız verilen e-posta tercihi(leri) yazılır; ikisi de null ise [ArgumentError] (istek gitmez).
  Future<NotificationPrefs> setNotificationPreferences({
    bool? emailAnnouncements,
    bool? emailFinanceReminders,
  }) {
    if (emailAnnouncements == null && emailFinanceReminders == null) {
      throw ArgumentError('En az bir e-posta tercihi verilmelidir.');
    }
    return _runAuthorized(
      (token) => api.setNotificationPreferences(
        token: token,
        emailAnnouncements: emailAnnouncements,
        emailFinanceReminders: emailFinanceReminders,
      ),
    );
  }

  // --- Aidat ve Finans (Faz 4a) -------------------------------------------------------------
  // Hata durumunda ApiException FIRLATIR (Türkçe mesajlı); oturum hatası [_runAuthorized] içinde işlenir.
  // Tutarlar KURUŞ tamsayıdır. Yazma çağrıları otomatik yeniden denenmez; çift kayıt `idempotencyKey` ile
  // önlenir (aynı anahtar = aynı kayıt).

  Future<List<FeeDefinition>> listFeeDefinitions(int siteCode, {FeeKind? kind, bool? active}) {
    return _runAuthorized(
      (token) => api.listFeeDefinitions(
        token: token,
        siteCode: siteCode,
        kind: kind,
        active: active,
      ),
    );
  }

  Future<FeeDefinition> createFeeDefinition(int siteCode, FeeDefinitionInput input) {
    return _runAuthorized(
      (token) => api.createFeeDefinition(token: token, siteCode: siteCode, input: input),
    );
  }

  /// Yalnız [fields] içindekiler gönderilir; borçlandırılmış tanımda yalnız `name`, `end_period`,
  /// `is_active`, `due_day`.
  Future<FeeDefinition> updateFeeDefinition(
    int siteCode,
    int definitionId,
    Map<String, Object?> fields,
  ) {
    return _runAuthorized(
      (token) => api.updateFeeDefinition(
        token: token,
        siteCode: siteCode,
        definitionId: definitionId,
        fields: fields,
      ),
    );
  }

  Future<FeePreview> previewFeeRun(
    int siteCode,
    int definitionId, {
    FinancePeriod? period,
    DateTime? dueDate,
  }) {
    return _runAuthorized(
      (token) => api.previewFeeRun(
        token: token,
        siteCode: siteCode,
        definitionId: definitionId,
        period: period,
        dueDate: dueDate,
      ),
    );
  }

  Future<FeePostResult> postFeeRun(
    int siteCode,
    int definitionId, {
    FinancePeriod? period,
    DateTime? dueDate,
    required int expectedTotalMinor,
    required int expectedApartmentCount,
    String? expectedHash,
    bool skipMissing = false,
    String? idempotencyKey,
  }) {
    return _runAuthorized(
      (token) => api.postFeeRun(
        token: token,
        siteCode: siteCode,
        definitionId: definitionId,
        period: period,
        dueDate: dueDate,
        expectedTotalMinor: expectedTotalMinor,
        expectedApartmentCount: expectedApartmentCount,
        expectedHash: expectedHash,
        skipMissing: skipMissing,
        idempotencyKey: idempotencyKey,
      ),
    );
  }

  Future<FeePreview> previewExtraCharge(int siteCode, ExtraChargeInput input) {
    return _runAuthorized(
      (token) => api.previewExtraCharge(token: token, siteCode: siteCode, input: input),
    );
  }

  /// Ek borç: [idempotencyKey] ZORUNLU; aynı ek borç son 24 saatte yazıldıysa 409 `DUPLICATE_CHARGE`
  /// ([allowDuplicate] bilinçli tekrar için).
  Future<FeePostResult> postExtraCharge(
    int siteCode,
    ExtraChargeInput input, {
    required int expectedTotalMinor,
    required int expectedApartmentCount,
    String? expectedHash,
    bool skipMissing = false,
    bool allowDuplicate = false,
    required String idempotencyKey,
  }) {
    return _runAuthorized(
      (token) => api.postExtraCharge(
        token: token,
        siteCode: siteCode,
        input: input,
        expectedTotalMinor: expectedTotalMinor,
        expectedApartmentCount: expectedApartmentCount,
        expectedHash: expectedHash,
        skipMissing: skipMissing,
        allowDuplicate: allowDuplicate,
        idempotencyKey: idempotencyKey,
      ),
    );
  }

  /// Daire bakiyeleri. [status]: `debtor|credit|all`.
  Future<BalancePage> listFinanceBalances(
    int siteCode, {
    String status = 'all',
    String? query,
    int limit = 50,
    int offset = 0,
  }) {
    return _runAuthorized(
      (token) => api.listFinanceBalances(
        token: token,
        siteCode: siteCode,
        status: status,
        query: query,
        limit: limit,
        offset: offset,
      ),
    );
  }

  /// Daire ekstresi; sonraki sayfa için `nextBeforeId` [beforeId] olarak verilir. [accountParty] (İP-1A) yalnız o hesabı ister.
  Future<AccountView> getFinanceAccount(
    int siteCode,
    int apartmentId, {
    int limit = 50,
    int? beforeId,
    AccountParty? accountParty,
  }) {
    return _runAuthorized(
      (token) => api.getFinanceAccount(
        token: token,
        siteCode: siteCode,
        apartmentId: apartmentId,
        limit: limit,
        beforeId: beforeId,
        accountParty: accountParty,
      ),
    );
  }

  /// Tahsilat kaydı: [amountMinor] POZİTİF kuruş; aynı [idempotencyKey] = aynı kayıt. [accountParty] (İP-1A): daire hesabı;
  /// null ise sunucu seçer (vadesi en eski açık borcu olan hesap). [fund]: tahsilat yalnız o kasanın borçlarına uygulanır;
  /// null ise otomatik (en eski vade önce).
  Future<LedgerWriteResult> recordFeePayment(
    int siteCode, {
    required int apartmentId,
    required int amountMinor,
    required DateTime entryDate,
    required PaymentMethod method,
    String? description,
    required String idempotencyKey,
    AccountParty? accountParty,
    FinanceFund? fund,
  }) {
    return _runAuthorized(
      (token) => api.recordFeePayment(
        token: token,
        siteCode: siteCode,
        apartmentId: apartmentId,
        amountMinor: amountMinor,
        entryDate: entryDate,
        method: method,
        description: description,
        idempotencyKey: idempotencyKey,
        accountParty: accountParty,
        fund: fund,
      ),
    );
  }

  Future<LedgerWriteResult> reverseFinanceEntry(
    int siteCode,
    int entryId, {
    String? reason,
    String? idempotencyKey,
  }) {
    return _runAuthorized(
      (token) => api.reverseFinanceEntry(
        token: token,
        siteCode: siteCode,
        entryId: entryId,
        reason: reason,
        idempotencyKey: idempotencyKey,
      ),
    );
  }

  Future<LedgerWriteResult> correctFinancePayment(
    int siteCode,
    int entryId, {
    required int amountMinor,
    required DateTime entryDate,
    required PaymentMethod method,
    String? description,
    required String idempotencyKey,
    AccountParty? accountParty,
    FinanceFund? fund,
  }) {
    return _runAuthorized(
      (token) => api.correctFinancePayment(
        token: token,
        siteCode: siteCode,
        entryId: entryId,
        amountMinor: amountMinor,
        entryDate: entryDate,
        method: method,
        description: description,
        idempotencyKey: idempotencyKey,
        accountParty: accountParty,
        fund: fund,
      ),
    );
  }

  Future<FinancePeriods> getFinancePeriods(int siteCode) {
    return _runAuthorized((token) => api.getFinancePeriods(token: token, siteCode: siteCode));
  }

  Future<void> closeFinancePeriod(int siteCode, FinancePeriod period) async {
    await _runAuthorized(
      (token) => api.closeFinancePeriod(token: token, siteCode: siteCode, period: period),
    );
  }

  Future<void> reopenFinancePeriod(int siteCode, FinancePeriod period) async {
    await _runAuthorized(
      (token) => api.reopenFinancePeriod(token: token, siteCode: siteCode, period: period),
    );
  }

  Future<FinanceSummary> getFinanceSummary(int siteCode) {
    return _runAuthorized((token) => api.getFinanceSummary(token: token, siteCode: siteCode));
  }

  /// Yönetici ana sayfası "Bu ay" özeti.
  Future<FinanceHome> getFinanceHome(int siteCode) {
    return _runAuthorized((token) => api.getFinanceHome(token: token, siteCode: siteCode));
  }

  /// Sakinin kendi dairelerinin borç durumu (`GET /app/my-finance`).
  Future<MyFinance> getMyFinance() {
    return _runAuthorized((token) => api.getMyFinance(token: token));
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

  /// (kayıt, bir kez verilen PIN [yeni daire hesabı açıldıysa], hata). PIN saklanmaz; çağıran yalnız
  /// gösterir.
  Future<(ApartmentRecord?, ApartmentPinIssue?, String?)>
  upsertApartmentResident({
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
      return (null, null, 'Bu islem icin site yonetim yetkisi gerekir.');
    }

    try {
      final saved = await api.upsertApartmentResident(
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
      return (saved.apartment, saved.pinIssue, null);
    } on ApiException catch (e) {
      _handleSessionError(e, usedToken: active.token);
      return (null, null, e.message);
    } catch (_) {
      return (null, null, 'Sunucuya baglanilamadi.');
    }
  }

  /// Daire hesabının PIN'ini sıfırlar: (bir kez verilen yeni PIN, hata).
  Future<(ApartmentPinIssue?, String?)> resetApartmentPin({
    required int apartmentId,
    bool sendEmail = true,
  }) async {
    final active = _safeRequireManagementSession();
    if (active == null) {
      return (null, 'Bu islem icin site yonetim yetkisi gerekir.');
    }

    try {
      final issue = await api.resetApartmentPin(
        token: active.token,
        role: active.role,
        apartmentId: apartmentId,
        sendEmail: sendEmail,
      );
      return (issue, null);
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
    // Geçiş Kontrol modülü o sitede kapalıysa yerel (LAN) kısayol denenmez (bkz. alan açıklaması).
    final moduleClosed = door != null && _doorControlClosedSites.contains(door.siteCode);
    final allowLocal = door != null && (door.canOpenLocalUdp || isSuper) && !moduleClosed;
    if (!allowRemote && !allowLocal) {
      return (
        null,
        moduleClosed
            ? AuthApi.messageForErrorCode('MODULE_DISABLED')
            : 'Bu kapı için uygulamadan açma kapalı.',
      );
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
        moduleClosed
            ? AuthApi.messageForErrorCode('MODULE_DISABLED')
            : 'Bu kapıda uzaktan açma kapalı. Cihaza yerel ağdan ulaşılamadı; telefonu cihazla aynı Wi-Fi ağına bağlayıp tekrar deneyin.',
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

  /// Bu hesap için saklı cihaz belirteci (önce e-posta, sonra kullanıcı adı); yoksa null. Depo hatası yutulur.
  Future<String?> _readDeviceTokenFor(UserSession account) async {
    return await _deviceTokenStore.read(account.email) ?? await _deviceTokenStore.read(account.loginName);
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
      // Parola değişirken kayıtlı cihaz belirteci (varsa) gönderilir; sunucu yenisini döndürürse saklanır.
      final deviceToken = isPasswordChange ? await _readDeviceTokenFor(active) : null;
      String? issuedDeviceToken;
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
        deviceToken: deviceToken,
        onDeviceToken: (token) => issuedDeviceToken = token,
      );
      final issued = issuedDeviceToken;
      if (issued != null) {
        // Belirteç HESABA bağlıdır: oturum bu arada değişse de bu hesabın tanımlayıcıları için yazılır.
        await _deviceTokenStore.save(
          <String?>[active.email, active.loginName, updated.email, updated.loginName],
          issued,
        );
      }
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
    // Sunucu (auth_middleware) yönetimin verdiği geçici şifre değişene kadar GET/PATCH /me dışındaki her isteğe 403 PASSWORD_CHANGE_REQUIRED
    // döner. Bu bir oturum sonu DEĞİLDİR: oturum korunur, ana sayfadaki zorunlu şifre diyaloğu açılır.
    if (error is ApiException && error.code == _passwordChangeRequiredCode) {
      _markPasswordChangeRequired();
      return;
    }
    if (error is SessionExpiredException ||
        (error is ApiException && error.invalidatesSession)) {
      final deleted = (error as ApiException).code == _accountDeletedCode;
      _sessionNotice = deleted ? _accountDeletedNotice : error.message;
      if (deleted) {
        unawaited(() async {
          await LocalDataWiper().clearSavedLoginIdentifier();
          await logout();
          await _wipeAfterRemoteDeletion();
        }());
      } else {
        unawaited(logout());
      }
    } else if (error is ApiException && error.isForbidden) {
      // 403 hesap pasifleştirme/onay bekleme olabilir: /me ile doğrula (kısıtlı sıklıkta).
      unawaited(refreshSession());
    }
  }

  /// Sunucu zorunlu şifre belirlemeyi istiyor (`403 PASSWORD_CHANGE_REQUIRED`): yönetimin verdiği geçici şifre / PIN değişene kadar
  /// yalnız `GET /me` ve `PATCH /me` (+ yasal onay) çalışır. Oturum DÜŞMEZ; yerel oturum `mustChangePassword` olarak işaretlenir ve dinleyiciler
  /// (ana sayfa) zorunlu şifre diyaloğunu açar. Şifre `PATCH /me` ile değişince sunucu yanıtı bayrağı kapatır.
  static const String _passwordChangeRequiredCode = 'PASSWORD_CHANGE_REQUIRED';

  void _markPasswordChangeRequired() {
    final current = _session;
    if (current == null || current.mustChangePassword) {
      return;
    }
    _session = current.copyWith(mustChangePassword: true);
    unawaited(_persist());
    _notifySafely();
  }

  /// Sunucu hesabın silindiğini bildirir (`401 ACCOUNT_DELETED`): başka cihazda ya da yanıtı kaybolan bir silme
  /// sonucu. Oturum kapanınca uygulama içi silmedekiyle AYNI yerel temizlik yapılır (kayıtlı e-posta, güvenilir
  /// cihaz belirteci, tercihler, kuyruklar); temizlik hataları çıkışı bozmaz.
  static const String _accountDeletedCode = 'ACCOUNT_DELETED';
  static const String _accountDeletedNotice =
      'Bu hesap silinmiş. İsterseniz aynı e-posta adresiyle yeniden kayıt olabilirsiniz.';

  Future<void> _wipeAfterRemoteDeletion() async {
    try {
      await LocalDataWiper().wipe();
    } catch (_) {
      // Temizlik en iyi çabadır.
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
      // Sunucu yalnız kullanıcının KENDİ parolasına izin verir: kayıtlı cihaz belirteci gönderilir, yenisi saklanır.
      final deviceToken = await _readDeviceTokenFor(active);
      String? issuedDeviceToken;
      final res = await api.changeApartmentMemberPassword(
        token: active.token,
        apartmentId: apartmentId,
        targetUserCode: targetUserCode,
        newPassword: newPassword,
        currentPassword: currentPassword,
        deviceToken: deviceToken,
        onDeviceToken: (token) => issuedDeviceToken = token,
      );
      final issued = issuedDeviceToken;
      if (issued != null) {
        await _deviceTokenStore.save(<String?>[active.email, active.loginName], issued);
      }
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
