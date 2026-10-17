// Telefon bildirimi (Firebase FCM, Platform Faz 3b-B) istemci akışı — sözleşme: docs/PLATFORM_BELGELER.md B3,
// B7, B8, B10.
//
// [PushService] mesajlaşma katmanı ([PushMessagingGateway]) ile sunucu uçlarını ([PushApi]) birleştirir:
// - AÇIK RIZA: cihaz kaydı YALNIZ (a) sunucu `push_available == true` ve (b) kullanıcı bu cihazda telefon
//   bildirimini AÇIKÇA açmışsa (Bildirim Tercihleri'nde "Bu cihazda aç" / "Telefon bildirimi" anahtarı ya da
//   Duyurular'daki "Aç") yapılır. Varsayılan kapalı: jeton üretilmez, sunucuya gidilmez, FCM otomatik başlatma
//   kapalı kalır. Android 12 ve öncesinde izin varsayılan olarak açık olsa da kendiliğinden kayıt YOKTUR.
// - İzin BAĞLAM İÇİNDE, açma işleminde istenir; açılışta SORULMAZ.
// - Kayıt tazeleme (rıza varsa): giriş sonrası, jeton yenilenince ve açılışta / ön plana dönüşte; izin durumu ya
//   da jeton değişmedikçe günde en çok bir kez. `notifications_enabled` işletim sistemi izninin GÜNCEL hâlidir.
//   Duyuru alamayan roller (süper kullanıcı, bireysel kullanıcı) için kayıt tutulmaz.
// - Çıkış ([AuthService.logout]): oturum belirteci yerelde silinmeden ÖNCE `DELETE /app/push/devices/{id}` aynı
//   belirteçle yola çıkar ve FCM jetonunun silinmesi ONA BAĞLI OLMADAN paralel başlar. Jeton silinemezse (ör.
//   çevrimdışı) "bekleyen temizlik" işareti kalır; açılışta, ön plana dönüşte, kayıttan önce ve kısa aralıklarla
//   yeniden denenir (eski hesabın bildirimleri bu cihaza gelmeye devam etmesin). Firebase henüz hazır değilken
//   çıkışta da sunucu silmesi yapılır ve işaret yazılır; gateway hazır olunca jeton silinir. Kayıt damgası yalnız
//   jeton gerçekten silinince silinir. Silme [cleanupBlockLimit] denemede de başarısızsa (ağ dışı kalıcı hata) yeni
//   kayıt artık engellenmez: sunucu aynı jetonu devralırken eski hesabın satırını siler (B3). Hesap değişimi aynı
//   akıştır. Çıkış arayüzü bunları BEKLEMEZ.
// - Tıklayınca yönlendirme: arka plandan (`onMessageOpenedApp`) ve kapalıyken (`getInitialMessage`, bir kez)
//   gelen dokunuş, yük beyaz listeden geçerse ([pushAnnouncementIdOf]) bekletilir; oturum + ana sayfa hazır ve
//   bakım / zorunlu güncelleme / "Güncellenen koşullar" kapıları kapalı olunca ([bindAnnouncementOpener]) teslim
//   edilir. Ön planda gelen bildirim sistemde gösterilmez; [foregroundAnnouncements] (özet hemen tazelenir, B10)
//   ya da test bildiriminde [foregroundTests] olayı üretilir.
//
// Tüm cihaz kaydı işlemleri TEK SIRADA çalışır (yarış yok). Gateway yokken (web / masaüstü / Firebase
// başlatılamadı / testler) her şey sessizce devre dışıdır. Günlüğe jeton, belirteç, kişisel veri yazılmaz.
import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:site_kapi_kontrol/models/push_models.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/app_gate_state.dart';
import 'package:site_kapi_kontrol/services/app_version.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/push_api.dart';
import 'package:site_kapi_kontrol/services/push_gateway.dart';
import 'package:site_kapi_kontrol/services/push_store.dart';
import 'package:site_kapi_kontrol/ui/views/legal_consent_gate.dart' show LegalConsentBlock;

/// Bu cihazda push altyapısının durumu.
enum PushSupport {
  /// Firebase başlatıldı; bu cihaz bildirim alabilir.
  ready,

  /// Başlatma sürüyor (açılışın ilk anları).
  preparing,

  /// Android/iOS ama Firebase başlatılamadı (bu derlemede yapılandırma yok).
  notConfigured,

  /// Web / masaüstü: telefon bildirimi yok.
  unsupportedPlatform,
}

/// [PushService.start] süreci.
enum PushStartState { idle, starting, ready, failed }

/// Bu cihazın telefon bildirimi durumu (Bildirim Tercihleri ekranı).
@immutable
class PushDeviceState {
  const PushDeviceState({
    required this.support,
    this.permission,
    this.enabledHere = false,
    this.installId,
  });

  final PushSupport support;

  /// Bu cihaz push alabilir mi (Android/iOS ve Firebase başlatıldı)?
  bool get supported => support == PushSupport.ready;

  /// İşletim sistemi izni; okunamadıysa ya da desteklenmiyorsa null.
  final PushPermission? permission;

  /// Kullanıcı bu cihazda telefon bildirimini açıkça açtı mı (açık rıza)?
  final bool enabledHere;

  /// Bu kurulumun kimliği ("Bu cihaz" eşlemesi); hiç kayıt olunmadıysa null.
  final String? installId;
}

/// [PushService.enableOnThisDevice] sonucu.
enum PushEnableOutcome {
  /// İzin var, cihaz sunucuya kaydedildi.
  registered,

  /// İzin reddedildi (yeniden sorulabilir). Rıza kaydedildi: izin verilince kayıt kendiliğinden yapılır.
  permissionDenied,

  /// İzin kalıcı reddedildi: telefon ayarlarından açılmalı (rıza kaydedildi).
  permissionPermanentlyDenied,

  /// Sunucuda telefon bildirimi şu an kapalı (`push_available: false`).
  pushUnavailable,

  /// Bu cihazda push yok (web / masaüstü / Firebase başlatılamadı / rol alıcı değil).
  unsupported,

  /// Jeton alınamadı (iOS'ta APNs hazır değil, ağ yok): sonra yeniden denenir.
  tokenUnavailable,

  /// Bu cihazdaki önceki oturumun jetonu henüz silinemedi; silinince (ya da birkaç denemeden sonra) kayıt yapılır.
  cleanupPending,
}

enum _SyncResult {
  registered,
  upToDate,
  skipped,
  cleanupPending,
  notConsented,
  notEligible,
  noPermission,
  notAvailable,
  tokenUnavailable,
  unsupported,
}

typedef _PendingRoute = ({int id, DateTime at});
typedef _Availability = ({int userId, bool value, DateTime at});

class PushService {
  PushService({
    PushLocalStore? store,
    PushApi Function(String baseUrl)? apiFactory,
    Future<String?> Function()? appVersion,
    DateTime Function()? now,
    List<ValueListenable<bool>>? routeBlockers,
    this.refreshInterval = const Duration(hours: 24),
    this.pendingRouteTtl = const Duration(minutes: 30),
    this.teardownTimeout = const Duration(seconds: 8),
    this.tokenTimeout = const Duration(seconds: 20),
    this.availabilityTtl = const Duration(minutes: 10),
    this.cleanupRetryDelays = const <Duration>[
      Duration(seconds: 30),
      Duration(minutes: 2),
      Duration(minutes: 10),
    ],
    this.observeLifecycle = true,
    this.cleanupBlockLimit = 5,
  }) : _store = store ?? PushLocalStore(),
       _apiFactory = apiFactory ?? ((baseUrl) => PushApi(baseUrl: baseUrl)),
       _appVersion = appVersion ?? _installedVersion,
       _now = now ?? DateTime.now,
       _routeBlockers =
           routeBlockers ??
           <ValueListenable<bool>>[
             AppGateBlock.active,
             AppGateBlock.pendingFirstCheck,
             LegalConsentBlock.active,
           ];

  /// Uygulama genelindeki örnek (lib/main.dart başlatır; ana sayfa, Duyurular ve Bildirim Tercihleri kullanır).
  /// Gateway verilmedikçe devre dışıdır.
  static PushService get instance => _instance ??= PushService();
  static PushService? _instance;

  /// Testler: genel örneği değiştirir (null: varsayılana döner).
  @visibleForTesting
  static set debugInstance(PushService? service) => _instance = service;

  /// Kayıt tazeleme aralığı (izin/jeton değişmedikçe sunucuya en çok bu sıklıkta gidilir).
  final Duration refreshInterval;

  /// Oturum / ana sayfa / kapılar beklenirken bekletilen yönlendirmenin ömrü (sonra yok sayılır).
  final Duration pendingRouteTtl;

  /// Çıkıştaki silme ve `deleteToken` için üst süre (en iyi çaba).
  final Duration teardownTimeout;

  /// Jeton alma üst süresi (iOS'ta APNs beklenir).
  final Duration tokenTimeout;

  /// `push_available` bilgisinin önbellek ömrü.
  final Duration availabilityTtl;

  /// Bekleyen FCM temizliğinin uygulama açıkken yeniden deneme aralıkları (sonra ön plana dönüşte).
  final List<Duration> cleanupRetryDelays;

  /// Önceki hesabın jetonu bu kadar denemede de silinemezse (ör. ağ dışı kalıcı FCM hatası) yeni kayıt artık
  /// ENGELLENMEZ: sunucu aynı jetonu devralırken eski hesabın satırını siler (B3), eski hesabın bildirimleri bu
  /// cihaza gitmez. Temizlik arka planda denenmeye devam eder.
  final int cleanupBlockLimit;

  /// Ön plana dönüşte izin değişikliği denetimi (testlerde kapatılabilir).
  final bool observeLifecycle;

  final PushLocalStore _store;
  final PushApi Function(String baseUrl) _apiFactory;
  final Future<String?> Function() _appVersion;
  final DateTime Function() _now;
  final List<ValueListenable<bool>> _routeBlockers;

  static Future<String?> _installedVersion() async => (await loadInstalledAppInfo()).version;

  PushMessagingGateway? _gateway;
  final List<StreamSubscription<Object?>> _subscriptions = <StreamSubscription<Object?>>[];
  AppLifecycleListener? _lifecycle;
  bool _disposed = false;

  AuthService? _auth;
  int _attachments = 0;
  UserSession? _session;

  final Map<String, PushApi> _apis = <String, PushApi>{};
  _Availability? _availability;

  _PendingRoute? _pendingRoute;
  void Function(int announcementId)? _opener;

  final StreamController<int> _foreground = StreamController<int>.broadcast();
  final StreamController<void> _foregroundTests = StreamController<void>.broadcast();
  final ValueNotifier<PushStartState> _startState = ValueNotifier<PushStartState>(PushStartState.idle);
  final ValueNotifier<bool> _active = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _busy = ValueNotifier<bool>(false);
  final ValueNotifier<int> _changes = ValueNotifier<int>(0);

  Future<void>? _queue;
  int _queued = 0;
  bool _syncQueued = false;
  Timer? _cleanupTimer;
  int _cleanupAttempt = 0;

  /// Bu cihaz telefon bildirimi alabilir mi (gateway başlatıldı)?
  bool get isSupported => _gateway != null && !_disposed;

  /// Başlatma durumu (Bildirim Tercihleri "hazırlanıyor" / "bu sürümde yok" ayrımı).
  ValueListenable<PushStartState> get startState => _startState;

  /// Bu cihaz şu an telefon bildirimi alıyor mu (rıza + izin + sunucuda kayıtlı)? Duyurular açıklaması bununla
  /// doğru cümleyi seçer.
  ValueListenable<bool> get activeHere => _active;

  /// Sırada / sürmekte olan cihaz kaydı işlemi var mı ("kaydediliyor" göstergesi).
  ValueListenable<bool> get busy => _busy;

  /// Cihaz durumu değişti (kayıt, silme, rıza, başlatma): ekranlar yeniden okur.
  ValueListenable<int> get changes => _changes;

  /// Uygulama ön plandayken gelen DUYURU bildirimlerinin numaraları (sistem bildirimi gösterilmez). Ana sayfa
  /// bununla duyuru özetini yoklama aralığını beklemeden tazeler; "yeni duyuru" uyarısı yine özetten çıkar.
  Stream<int> get foregroundAnnouncements => _foreground.stream;

  /// Uygulama ön plandayken gelen TEST bildirimi (ana sayfa "Test bildirimi bu cihaza ulaştı." der).
  Stream<void> get foregroundTests => _foregroundTests.stream;

  void _bump() {
    if (!_disposed) _changes.value++;
  }

  void _setActive(bool value) {
    if (!_disposed) _active.value = value;
  }

  // --- Başlatma --------------------------------------------------------------------------------

  /// Firebase başlatılmaya başlandı (lib/main.dart, yalnız Android/iOS).
  void markStarting() {
    if (_disposed || _startState.value != PushStartState.idle) return;
    _startState.value = PushStartState.starting;
    _bump();
  }

  /// Firebase başlatılamadı: bu derlemede telefon bildirimi yok.
  void markStartFailed() {
    if (_disposed || _gateway != null) return;
    _startState.value = PushStartState.failed;
    _bump();
  }

  /// Firebase başlatıldıktan sonra BİR kez. Akışlara abone olur, kapalıyken dokunulan bildirimi alır, bekleyen FCM
  /// temizliğini dener, oturum zaten açıksa (ve rıza varsa) kaydı tazeler.
  Future<void> start(PushMessagingGateway gateway) async {
    if (_gateway != null || _disposed) return;
    _gateway = gateway;
    try {
      await gateway.init();
    } catch (_) {
      // iOS ön plan sunum ayarı yapılamadı: push yine çalışır.
    }
    if (_disposed) return;
    _subscriptions
      ..add(gateway.onMessage.listen(_onForegroundMessage, onError: (Object _) {}))
      ..add(gateway.onMessageOpenedApp.listen(_onOpenedMessage, onError: (Object _) {}))
      // Yenilenen jeton damgadaki özetle karşılaştırılır; değiştiyse kayıt hemen, değilse "günde bir" kuralı.
      ..add(gateway.onTokenRefresh.listen((_) => _requestSync(), onError: (Object _) {}));
    for (final blocker in _routeBlockers) {
      blocker.addListener(_deliverPendingRoute);
    }
    if (observeLifecycle) {
      _lifecycle = AppLifecycleListener(onResume: onAppResumed);
    }
    // Kurulum kimliği belleğe alınır: çıkıştaki silme isteği eşzamanlı yola çıkabilsin.
    unawaited(_store.readInstallId());
    _startState.value = PushStartState.ready;
    _bump();
    // Önceki çıkışta silinemeyen jeton (oturum olsun olmasın) şimdi silinir.
    unawaited(_serial(_retryPendingCleanup));
    try {
      final initial = await gateway.getInitialMessage();
      if (initial != null) _onOpenedMessage(initial);
    } catch (_) {}
    if (_session != null) _requestSync();
  }

  // --- Oturum ----------------------------------------------------------------------------------

  /// Ana sayfa açılınca (oturum varken) bağlanır; aynı servise birden çok bağlanma sayılır. Çıkış kancası
  /// ([AuthService.onSessionEnding]) ve oturum dinleyicisi kurulur; oturum ilk kez görülünce kayıt tazelenir.
  void attach(AuthService auth) {
    if (_disposed) return;
    if (!identical(_auth, auth)) {
      _release();
      _auth = auth;
      auth.onSessionEnding = _onSessionEnding;
      auth.addListener(_onAuthChanged);
    }
    _attachments++;
    _onAuthChanged();
  }

  /// [attach]'in karşılığı (ana sayfa kapanınca). Son bağlantı kalkınca kanca ve dinleyici sökülür.
  void detach(AuthService auth) {
    if (!identical(_auth, auth)) return;
    _attachments--;
    if (_attachments > 0) return;
    _release();
  }

  void _release() {
    final auth = _auth;
    if (auth == null) return;
    _auth = null;
    _attachments = 0;
    _session = null;
    try {
      auth.removeListener(_onAuthChanged);
    } catch (_) {
      // Servis zaten kapatılmış (testler).
    }
    if (auth.onSessionEnding == _onSessionEnding) auth.onSessionEnding = null;
  }

  void _onAuthChanged() {
    final auth = _auth;
    if (auth == null || _disposed) return;
    final current = auth.session;
    final previous = _session;
    if (current == null) {
      if (previous != null) {
        // Çıkış kancası çalışmadan kapandı: son görülen belirteçle aynı akış.
        _session = null;
        _endSession(auth, previous);
      }
      return;
    }
    // Aynı hesapta belirteç değişmiş olabilir (parola değişimi): son belirteç tutulur.
    _session = current;
    if (previous == null) {
      _requestSync();
      _deliverPendingRoute();
    } else if (previous.id != current.id) {
      // Hesap değişimi: önceki hesabın çıkış akışı (kendi belirteciyle), ardından yeni hesabın kaydı.
      _endSession(auth, previous);
      _requestSync();
    } else if (previous.role != current.role) {
      // Rol değişti (örn. site başvurusu onaylandı): duyuru alabilir hâle gelmiş olabilir.
      _requestSync();
    }
  }

  /// Duyuru alabilecek roller (sakin ve site yöneticisi). Süper kullanıcı ve bireysel kullanıcı alıcı olamaz:
  /// onlar için cihaz kaydı tutulmaz (kişisel veri en aza).
  static bool _mayReceive(UserRole role) =>
      role == UserRole.apartmentOwner || role == UserRole.siteManager;

  /// [AuthService.logout] oturumu silmeden HEMEN önce çağırır (belirteç hâlâ elde).
  void _onSessionEnding(UserSession ending) {
    final auth = _auth;
    if (_disposed || auth == null) return;
    _session = null;
    _endSession(auth, ending);
  }

  void _endSession(AuthService auth, UserSession ending) {
    // Önceki oturumda bekleyen yönlendirme başka hesaba taşınmaz.
    _pendingRoute = null;
    _availability = null;
    _setActive(false);
    // Yeni çıkış: temizlik yeniden deneme takvimi baştan başlar.
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
    _cleanupAttempt = 0;
    if (_gateway == null) {
      // Firebase henüz hazır değil (başlatma sürüyor / başarısız): sunucu kaydı yine silinir ve yerel jeton için
      // "bekleyen temizlik" yazılır; gateway hazır olunca start() jetonu siler (eski hesabın bildirimleri gelmesin).
      if (!_disposed && pushPlatformSupported()) {
        final api = _apiFor(auth.api.baseUrl);
        unawaited(_serial(() => _teardownWithoutGateway(api, ending)));
      }
      return;
    }
    final api = _apiFor(auth.api.baseUrl);
    unawaited(_serial(() => _teardown(api, ending)));
  }

  Future<void> _teardownWithoutGateway(PushApi api, UserSession ending) async {
    final installId = _store.cachedInstallId ?? await _store.readInstallId();
    if (installId == null) return; // Bu cihazda hiç kayıt / jeton olmadı.
    final server = api
        .deleteDevice(token: ending.token, installId: installId, timeout: teardownTimeout)
        .then<bool>((_) => true, onError: (Object _) => false);
    await _store.setPendingCleanup(true);
    await server;
    _bump();
  }

  Future<void> _teardown(PushApi api, UserSession ending) async {
    final gateway = _gateway;
    if (gateway == null) return;
    // Bellekteki kimlik varsa sunucu silmesi BU çağrıda, eşzamanlı olarak (oturum belirteci yerindeyken) yola çıkar.
    final installId = _store.cachedInstallId ?? await _store.readInstallId();
    if (installId == null) return; // Bu cihazda hiç kayıt / jeton olmadı.
    final server = api
        .deleteDevice(token: ending.token, installId: installId, timeout: teardownTimeout)
        .then<bool>((_) => true, onError: (Object _) => false);
    // FCM jetonu sunucu yanıtını BEKLEMEDEN silinir (sunucuya ulaşılamasa da eski jeton geçersiz olur ve sonraki
    // gönderimde UNREGISTERED ile temizlenir).
    final fcm = _deleteFcmToken(gateway);
    await Future.wait<bool>(<Future<bool>>[server, fcm]);
    _bump();
  }

  /// FCM jetonunu siler. Başarısızsa "bekleyen temizlik" kalır ve yeniden denenir; damga YALNIZ başarıda silinir.
  Future<bool> _deleteFcmToken(PushMessagingGateway gateway) async {
    // Silme isteği BU çağrıda yola çıkar; "bekleyen temizlik" işareti yanıt beklenirken yazılır (uygulama bu arada
    // kapanırsa sonraki açılışta yeniden denenir).
    final deletion = Future<void>.sync(gateway.deleteToken)
        .timeout(teardownTimeout)
        .then<bool>((_) => true, onError: (Object _) => false);
    await _store.setPendingCleanup(true);
    if (!await deletion) {
      await _store.recordCleanupFailure();
      _scheduleCleanupRetry();
      return false;
    }
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
    _cleanupAttempt = 0;
    await _store.setPendingCleanup(false);
    await _store.clearStamp();
    return true;
  }

  Future<void> _retryPendingCleanup() async {
    final gateway = _gateway;
    if (gateway == null || _disposed) return;
    if (!await _store.hasPendingCleanup()) return;
    // Temizlik başarılıysa ve oturum açıksa, onun yüzünden bekleyen kayıt şimdi yapılır (zamanlayıcı yolu dahil).
    if (await _deleteFcmToken(gateway) && _session != null) _requestSync();
  }

  void _scheduleCleanupRetry() {
    if (_disposed || cleanupRetryDelays.isEmpty || (_cleanupTimer?.isActive ?? false)) return;
    if (_cleanupAttempt >= cleanupRetryDelays.length) return; // Sonrası: açılışta / ön plana dönüşte.
    final delay = cleanupRetryDelays[_cleanupAttempt++];
    _cleanupTimer = Timer(delay, () {
      _cleanupTimer = null;
      if (!_disposed) unawaited(_serial(_retryPendingCleanup));
    });
  }

  // --- Kayıt tazeleme --------------------------------------------------------------------------

  /// Uygulama ön plana döndü: bekleyen FCM temizliği denenir; rıza varsa ve izin durumu / jeton değiştiyse ya da
  /// son kayıt [refreshInterval]'dan eskiyse cihaz kaydı tazelenir; değilse sunucuya gidilmez.
  void onAppResumed() {
    if (_gateway == null || _disposed) return;
    unawaited(_serial(_retryPendingCleanup));
    _requestSync();
  }

  void _requestSync() {
    if (_gateway == null || _disposed) return;
    if (_syncQueued) return;
    _syncQueued = true;
    unawaited(
      _serial(() async {
        _syncQueued = false;
        final auth = _auth;
        final session = _session;
        if (auth == null || session == null) return;
        try {
          await _sync(auth, session);
        } catch (_) {
          // Arka plan tazelemesi: hata sessizdir, sonraki açılışta yeniden denenir.
        }
      }),
    );
  }

  /// Bildirim Tercihleri: ayarlardan dönüşte kaydın bitmesini bekleyip durumu öyle göstermek için.
  Future<void> syncNow(AuthService auth) {
    final session = auth.session;
    if (_gateway == null || _disposed || session == null) return Future<void>.value();
    return _serial(() async {
      try {
        await _sync(auth, session);
      } catch (_) {}
    });
  }

  Future<_SyncResult> _sync(
    AuthService auth,
    UserSession session, {
    bool force = false,
    bool? knownAvailable,
  }) async {
    final result = await _syncInner(auth, session, force: force, knownAvailable: knownAvailable);
    switch (result) {
      case _SyncResult.registered:
      case _SyncResult.upToDate:
      case _SyncResult.skipped:
      case _SyncResult.cleanupPending:
      case _SyncResult.tokenUnavailable:
        break;
      case _SyncResult.notConsented:
      case _SyncResult.notEligible:
      case _SyncResult.noPermission:
      case _SyncResult.notAvailable:
      case _SyncResult.unsupported:
        _setActive(false);
    }
    _bump();
    return result;
  }

  Future<_SyncResult> _syncInner(
    AuthService auth,
    UserSession session, {
    required bool force,
    bool? knownAvailable,
  }) async {
    final gateway = _gateway;
    if (gateway == null) return _SyncResult.unsupported;
    if (!_mayReceive(session.role)) return _SyncResult.notEligible;
    // AÇIK RIZA: kullanıcı bu cihazda açmadıysa jeton bile istenmez.
    if (!await _store.isEnabledHere(session.id)) return _SyncResult.notConsented;
    // Önceki hesabın silinemeyen jetonu önce silinir; silinemezse yeni kayıt yapılmaz (aynı jeton taşınmasın). Ancak
    // [cleanupBlockLimit] denemeden sonra engel kalkar: sunucu aynı jetonu devralırken eski hesabın satırını siler.
    if (await _store.hasPendingCleanup() &&
        !await _deleteFcmToken(gateway) &&
        await _store.pendingCleanupFailures() < cleanupBlockLimit) {
      return _SyncResult.cleanupPending;
    }
    final PushPermission permission;
    try {
      permission = await gateway.permissionStatus();
    } catch (_) {
      return _SyncResult.skipped;
    }
    final stamp = await _store.readStamp();
    final registeredHere = stamp != null && stamp.userId == session.id;
    // İzin yok ve bu hesap bu cihazda kayıtlı değil: sunucuya gidilmez.
    if (!permission.isGranted && !registeredHere) return _SyncResult.noPermission;
    // İlk kayıttan önce sunucu push'unun açık olduğu doğrulanır (kapalıyken jeton üretilmez).
    if (!registeredHere) {
      final available = knownAvailable ?? await _pushAvailable(auth, session);
      if (available == null) return _SyncResult.skipped;
      if (!available) return _SyncResult.notAvailable;
    }
    final installId = await _store.installId();
    String? fcmToken;
    try {
      fcmToken = await gateway.getToken().timeout(tokenTimeout);
    } catch (_) {
      fcmToken = null;
    }
    if (fcmToken == null || fcmToken.isEmpty) return _SyncResult.tokenUnavailable;
    final enabled = permission.isGranted;
    final tokenHash = sha256.convert(utf8.encode(fcmToken)).toString();
    final now = _now();
    if (!force &&
        registeredHere &&
        stamp.tokenHash == tokenHash &&
        stamp.notificationsEnabled == enabled) {
      final age = now.difference(stamp.at);
      if (!age.isNegative && age < refreshInterval) {
        // "Bu cihaza bildirim gelir" iddiası için sunucu push'unun açık olduğu (soğuk açılışta tembel, önbellekli)
        // doğrulanır; okunamazsa önceki durum korunur.
        final available = knownAvailable ?? await _pushAvailable(auth, session);
        if (available != null) _setActive(enabled && available);
        return _SyncResult.upToDate;
      }
    }
    if (registeredHere) {
      final available = knownAvailable ?? await _pushAvailable(auth, session);
      if (available == null) return _SyncResult.skipped;
      if (!available) return _SyncResult.notAvailable;
    }
    String? version;
    try {
      version = await _appVersion();
    } catch (_) {}
    // Belirteç bu hesabın GÜNCEL oturumundan, çağrıdan hemen önce alınır (arada bekleme yok): oturum kapandıysa
    // ya da başka hesaba geçildiyse kayıt yapılmaz, başka hesabın belirteci asla gitmez.
    final current = auth.session;
    if (current == null || current.id != session.id) return _SyncResult.skipped;
    await _guardToken(
      auth,
      current.token,
      (token) => _apiFor(auth.api.baseUrl).registerDevice(
        token: token,
        installId: installId,
        platform: gateway.platform,
        fcmToken: fcmToken!,
        appVersion: version,
        notificationsEnabled: enabled,
      ),
    );
    if (auth.session?.id != session.id) return _SyncResult.skipped;
    await _store.writeStamp(
      PushRegistrationStamp(
        userId: session.id,
        tokenHash: tokenHash,
        notificationsEnabled: enabled,
        at: now,
      ),
    );
    _setActive(enabled);
    return _SyncResult.registered;
  }

  /// Sunucu push'u açık mı? (önbellekli; okunamazsa null).
  Future<bool?> _pushAvailable(AuthService auth, UserSession session) async {
    final cached = _availability;
    if (cached != null && cached.userId == session.id) {
      final age = _now().difference(cached.at);
      if (!age.isNegative && age < availabilityTtl) return cached.value;
    }
    try {
      final prefs = await _guardToken(
        auth,
        session.token,
        (token) => _apiFor(auth.api.baseUrl).getPreferences(token: token),
      );
      _noteAvailability(session.id, prefs.available);
      return prefs.available;
    } catch (_) {
      return null;
    }
  }

  void _noteAvailability(int userId, bool value) {
    _availability = (userId: userId, value: value, at: _now());
    if (!value) _setActive(false);
  }

  /// Görevleri sırayla çalıştırır. Sıra boşsa görev BU çağrıda eşzamanlı başlar (çıkıştaki silme isteği oturum
  /// belirteci silinmeden yola çıksın diye).
  Future<T> _serial<T>(Future<T> Function() task) {
    final previous = _queue;
    _queued++;
    if (!_disposed && !_busy.value) _busy.value = true;
    final Future<T> run = previous == null ? Future<T>.sync(task) : previous.then((_) => task());
    final Future<void> tail = run.then<void>((_) {}, onError: (Object _) {});
    _queue = tail;
    unawaited(
      tail.whenComplete(() {
        _queued--;
        if (identical(_queue, tail)) _queue = null;
        if (_queued == 0 && !_disposed) _busy.value = false;
      }),
    );
    return run;
  }

  PushApi _apiFor(String baseUrl) => _apis.putIfAbsent(baseUrl, () => _apiFactory(baseUrl));

  /// Verilen oturum belirteciyle çağırır; 401'de (belirteç hâlâ güncelse) oturum sunucudan doğrulanır.
  Future<T> _guardToken<T>(
    AuthService auth,
    String token,
    Future<T> Function(String token) call,
  ) async {
    try {
      return await call(token);
    } on ApiException catch (e) {
      if (e.invalidatesSession && auth.session?.token == token) {
        unawaited(auth.refreshSession(force: true));
      }
      rethrow;
    }
  }

  Future<T> _guard<T>(AuthService auth, Future<T> Function(String token) call) {
    final token = auth.session?.token;
    if (token == null) {
      return Future<T>.error(ApiException('Oturum açmanız gerekmektedir.'));
    }
    return _guardToken(auth, token, call);
  }

  // --- Bildirim Tercihleri / Duyurular ekranları -----------------------------------------------

  PushSupport _support() {
    if (_gateway != null && !_disposed) return PushSupport.ready;
    if (!pushPlatformSupported()) return PushSupport.unsupportedPlatform;
    return _startState.value == PushStartState.failed ? PushSupport.notConfigured : PushSupport.preparing;
  }

  /// Bu cihazın durumu (destek, izin, rıza, kurulum kimliği).
  Future<PushDeviceState> deviceState(AuthService auth) async {
    final support = _support();
    final gateway = _gateway;
    if (support != PushSupport.ready || gateway == null) return PushDeviceState(support: support);
    PushPermission? permission;
    try {
      permission = await gateway.permissionStatus();
    } catch (_) {}
    final session = auth.session;
    final enabled = session != null && await _store.isEnabledHere(session.id);
    return PushDeviceState(
      support: support,
      permission: permission,
      enabledHere: enabled,
      installId: await _store.readInstallId(),
    );
  }

  /// Telefon bildirimini bu cihazda AÇAR (açık rıza): rıza işaretlenir, gerekirse izin BAĞLAM İÇİNDE istenir,
  /// verilirse cihaz kaydedilir. İzin verilmezse rıza kalır; kullanıcı izni sonra ayarlardan verirse kayıt ön
  /// plana dönüşte kendiliğinden yapılır. Sunucu hatası [ApiException] olarak fırlar.
  Future<PushEnableOutcome> enableOnThisDevice(AuthService auth) {
    return _serial(() async {
      final gateway = _gateway;
      if (gateway == null || _disposed) return PushEnableOutcome.unsupported;
      final session = auth.session;
      if (session == null) throw ApiException('Oturum açmanız gerekmektedir.');
      if (!_mayReceive(session.role)) return PushEnableOutcome.unsupported;
      await _store.setEnabledHere(session.id, true);
      _bump();
      var permission = await gateway.permissionStatus();
      if (!permission.isGranted && permission.canAsk) {
        permission = await gateway.requestPermission();
      }
      if (!permission.isGranted) {
        _setActive(false);
        _bump();
        return permission == PushPermission.permanentlyDenied
            ? PushEnableOutcome.permissionPermanentlyDenied
            : PushEnableOutcome.permissionDenied;
      }
      final result = await _sync(auth, session, force: true);
      return switch (result) {
        _SyncResult.registered || _SyncResult.upToDate => PushEnableOutcome.registered,
        _SyncResult.notAvailable => PushEnableOutcome.pushUnavailable,
        _SyncResult.notEligible || _SyncResult.unsupported => PushEnableOutcome.unsupported,
        _SyncResult.cleanupPending => PushEnableOutcome.cleanupPending,
        _ => PushEnableOutcome.tokenUnavailable,
      };
    });
  }

  /// Kalıcı retten sonra "Telefon ayarlarını aç": kullanıcı bu cihazda bildirim istediğini açıkça gösterdi (rıza);
  /// izin ayarlardan verilince kayıt ön plana dönüşte yapılır.
  Future<bool> openSettingsToEnable(AuthService auth) async {
    final session = auth.session;
    if (session != null && _gateway != null && _mayReceive(session.role)) {
      await _store.setEnabledHere(session.id, true);
      _bump();
    }
    return openSystemSettings();
  }

  /// Cihazı listeden kaldırır. BU cihazsa rıza işareti silinir ve jeton geçersiz kılınır: kullanıcı yeniden açana
  /// dek kayıt olunmaz (acil duyurular da gelmez).
  Future<void> removeDevice(AuthService auth, String installId) {
    return _serial(() async {
      final session = auth.session;
      if (session == null) throw ApiException('Oturum açmanız gerekmektedir.');
      final mine = _store.cachedInstallId ?? await _store.readInstallId();
      await _guard(
        auth,
        (token) => _apiFor(auth.api.baseUrl).deleteDevice(token: token, installId: installId),
      );
      if (installId != mine) {
        _bump();
        return;
      }
      await _store.setEnabledHere(session.id, false);
      _setActive(false);
      final gateway = _gateway;
      if (gateway != null) await _deleteFcmToken(gateway);
      _bump();
    });
  }

  /// Duyurular ekranındaki "telefon bildirimini aç" kartı gösterilsin mi? Koşulların HEPSİ: push bu cihazda
  /// destekleniyor, rol alıcı, bu cihazda henüz açılmamış, kart kapatılmamış, izin kalıcı reddedilmemiş ve sunucu
  /// `push_available == true` (yerel denetimler önce; ağ en son, önbellekli).
  Future<bool> shouldShowSoftPrompt(AuthService auth) async {
    final gateway = _gateway;
    final session = auth.session;
    if (gateway == null || _disposed || session == null || !_mayReceive(session.role)) return false;
    if (await _store.isEnabledHere(session.id)) return false;
    if (await _store.isPromptDismissed(session.id)) return false;
    try {
      if (await gateway.permissionStatus() == PushPermission.permanentlyDenied) return false;
    } catch (_) {
      return false;
    }
    return await _pushAvailable(auth, session) ?? false;
  }

  /// Kart "Şimdi değil" ile kapatıldı (kullanıcı başına, kalıcı).
  Future<void> dismissSoftPrompt(AuthService auth) async {
    final session = auth.session;
    if (session != null) await _store.setPromptDismissed(session.id);
  }

  Future<PushPreferences> getPreferences(AuthService auth) async {
    final prefs = await _guard(auth, (token) => _apiFor(auth.api.baseUrl).getPreferences(token: token));
    final session = auth.session;
    if (session != null) _noteAvailability(session.id, prefs.available);
    return prefs;
  }

  Future<PushPreferences> updatePreferences(
    AuthService auth,
    PushPreferencesPatch patch,
    PushPreferences current,
  ) => _guard(
    auth,
    (token) => _apiFor(auth.api.baseUrl).updatePreferences(token: token, patch: patch, current: current),
  );

  Future<List<PushDevice>> listDevices(AuthService auth) =>
      _guard(auth, (token) => _apiFor(auth.api.baseUrl).listDevices(token: token));

  Future<PushTestResult> sendTest(AuthService auth) =>
      _guard(auth, (token) => _apiFor(auth.api.baseUrl).sendTest(token: token));

  /// Uygulamanın sistem ayarlarını açar (kalıcı ret sonrası izin).
  Future<bool> openSystemSettings() async {
    final gateway = _gateway;
    if (gateway == null) return false;
    try {
      return await gateway.openSystemSettings();
    } catch (_) {
      return false;
    }
  }

  // --- Gelen bildirimler -----------------------------------------------------------------------

  void _onForegroundMessage(PushMessage message) {
    if (_disposed || _session == null) return;
    if (message.isTest) {
      _foregroundTests.add(null);
      return;
    }
    final id = message.announcementId;
    if (id == null) return;
    _foreground.add(id);
  }

  void _onOpenedMessage(PushMessage message) {
    final id = message.announcementId;
    // Beyaz liste dışı yük (tür / numara geçersiz; test bildirimi dahil) yok sayılır.
    if (id == null || _disposed) return;
    _pendingRoute = (id: id, at: _now());
    _deliverPendingRoute();
  }

  /// Ana sayfa hazır olunca duyuru açıcısını bağlar; bekleyen yönlendirme varsa hemen teslim edilir.
  void bindAnnouncementOpener(void Function(int announcementId) opener) {
    if (_disposed) return;
    _opener = opener;
    _deliverPendingRoute();
  }

  void unbindAnnouncementOpener(void Function(int announcementId) opener) {
    if (_opener == opener) _opener = null;
  }

  void _deliverPendingRoute() {
    final route = _pendingRoute;
    final opener = _opener;
    if (route == null || opener == null || _disposed) return;
    // Oturum yok ya da uygulama bakım / zorunlu güncelleme / "Güncellenen koşullar" kapısının altında: bekletilir.
    if (_auth?.session == null) return;
    for (final blocker in _routeBlockers) {
      if (blocker.value) return;
    }
    _pendingRoute = null;
    final age = _now().difference(route.at);
    if (age.isNegative || age > pendingRouteTtl) return;
    opener(route.id);
  }

  /// Testler: abonelikleri, zamanlayıcıları ve dinleyicileri kapatır.
  @visibleForTesting
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _release();
    _opener = null;
    _pendingRoute = null;
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
    for (final blocker in _routeBlockers) {
      blocker.removeListener(_deliverPendingRoute);
    }
    _lifecycle?.dispose();
    _lifecycle = null;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    await _foreground.close();
    await _foregroundTests.close();
  }
}
