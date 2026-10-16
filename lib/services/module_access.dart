import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:site_kapi_kontrol/models/platform_module.dart';
import 'package:site_kapi_kontrol/services/adaptive_poller.dart';

/// Kullanıcının bağlı olduğu sitelerde hangi modüllerin açık olduğunu tutar (menü ve ekran
/// süzgeçleri bunu okur). Platform modül sistemi Faz 1.
///
/// - SÜPER KULLANICIDA ayrıca bekleyen modül talebi sayısı ([pendingRequestCount]; çekmece rozeti)
///   aynı yoklamayla tazelenir ([fetchPendingCount] verilmişse); modül süzgeci yine yoktur. Aynı yoklama
///   bekleyen SİTE BAŞVURUSU sayısını da ([pendingApplicationCount]; [fetchPendingApplicationCount]
///   verilmişse) tazeler: iki sayı birbirinden bağımsızdır (biri hata verirse öbürünün son değeri ve
///   güncellemesi etkilenmez).
/// - Veri `GET /app/my-modules` ile ([fetch]) çekilir: girişten sonra, her genel yenilemede
///   ([refresh]) ve [AdaptivePoller] ile kısa aralıklı ([start]/[stop]; uygulama arka plandayken ya
///   da sayfa görünür değilken [isActive] false döner ve ağ isteği yapılmaz).
/// - SÜPER KULLANICIDA her şey açık sayılır ([isSuperUser] ya da sunucunun `scope: all` yanıtı);
///   süper kullanıcı için ağ isteği hiç yapılmaz.
/// - FAIL-OPEN: çağrı hatasında mevcut değer korunur; ilk yükleme hiç başarılı olmadıysa TÜM
///   modüller açık sayılır (ağ hatası yüzünden menüler/kapılar kaybolmasın). Sunucu zaten kapalı
///   modülü reddeder; burası yalnız arayüz süzgecidir.
/// - [clear] (çıkış / kullanıcı değişimi) durumu sıfırlar; uçuştaki eski yanıt yok sayılır.
class ModuleAccess extends ChangeNotifier {
  ModuleAccess({
    required Future<MyModulesResult> Function() fetch,
    bool Function()? isSuperUser,
    bool Function()? isActive,
    Future<int> Function()? fetchPendingCount,
    Future<int> Function()? fetchPendingApplicationCount,
    Duration interval = const Duration(seconds: 30),
    Duration maxDelay = const Duration(minutes: 5),
  }) : _fetch = fetch,
       _isSuperUser = isSuperUser,
       _fetchPendingCount = fetchPendingCount,
       _fetchPendingApplicationCount = fetchPendingApplicationCount {
    _poller = AdaptivePoller(
      interval: interval,
      maxDelay: maxDelay,
      isActive: isActive,
      poll: refresh,
    );
  }

  final Future<MyModulesResult> Function() _fetch;
  final bool Function()? _isSuperUser;
  final Future<int> Function()? _fetchPendingCount;
  final Future<int> Function()? _fetchPendingApplicationCount;
  late final AdaptivePoller _poller;

  MyModulesResult? _result;
  int? _pendingRequestCount;
  int? _pendingApplicationCount;
  Future<bool?>? _inFlight;
  bool _rerun = false;
  bool _disposed = false;
  int _generation = 0;

  /// Son başarılı yanıt; hiç alınmadıysa null.
  MyModulesResult? get result => _result;

  /// Süper kullanıcı için bekleyen modül talebi sayısı; henüz alınmadıysa (ya da süper kullanıcı
  /// değilse) null. Çağrı hatasında son değer korunur.
  int? get pendingRequestCount => _pendingRequestCount;

  /// Süper kullanıcı için bekleyen site başvurusu sayısı; henüz alınmadıysa (ya da süper kullanıcı değilse)
  /// null. Çağrı hatasında son değer korunur.
  int? get pendingApplicationCount => _pendingApplicationCount;

  /// En az bir yanıt başarıyla alındı mı? (false iken fail-open: her şey açık.)
  bool get isLoaded => _result != null;

  /// Süper kullanıcı (rol ya da sunucunun `scope: all` yanıtı): modül süzgeci uygulanmaz.
  bool get isSuper => (_isSuperUser?.call() ?? false) || (_result?.isAll ?? false);

  /// Süzgeç devrede mi? Süper kullanıcıda ve ilk yükleme başarısızken değildir.
  bool get isFiltering => !isSuper && isLoaded;

  /// [siteCode] sitesinde [code] modülü açık mı?
  ///
  /// Süper kullanıcıda ve veri yokken (fail-open) true. Site listede yoksa (örn. onay bekleyen ya da
  /// yeni kurulmuş site) ya da kod o sitede yoksa katalog varsayılanı geçerlidir
  /// ([PlatformModule.defaultEnabled]: yalnız `door_control` ve çekirdek modüller açık).
  bool isEnabled(int siteCode, String code) {
    if (!isFiltering) return true;
    for (final site in _result!.sites) {
      if (site.siteCode == siteCode) return site.isEnabled(code);
    }
    return PlatformModule.defaultEnabled(code);
  }

  /// Kullanıcının bağlı olduğu sitelerden en az birinde [code] açık mı? Süper kullanıcıda ve veri
  /// yokken true; hiç sitesi olmayan kullanıcıda false (bkz. [isDisabledEverywhere]).
  bool anyEnabled(String code) {
    if (!isFiltering) return true;
    return _result!.sites.any((s) => s.isEnabled(code));
  }

  /// Kullanıcının Yönetim Kurulu / Denetçi üyesi olduğu siteler (`role == board_member`; sunucu rol
  /// önceliği: yönetici > kurul > görevli > sakin). Süper kullanıcıda ve veri yokken boş liste döner.
  /// Kişi ve Daire Kayıtları ekranına salt okunur erişim buradan açılır (Faz 2a).
  List<MySiteModules> get boardMemberSites {
    if (!isFiltering) return const <MySiteModules>[];
    return _result!.sites.where((s) => s.isBoardMember).toList(growable: false);
  }

  /// [code] modülünün açık olduğu siteler (süper kullanıcıda ya da veri yokken boş liste döner:
  /// bu durumda süzgeç yoktur, tüm siteler için [isEnabled] true'dur).
  List<MySiteModules> sitesWith(String code) {
    if (!isFiltering) return const <MySiteModules>[];
    return _result!.sites.where((s) => s.isEnabled(code)).toList(growable: false);
  }

  /// Kullanıcı en az bir siteye bağlı VE bağlı olduğu TÜM sitelerde [code] kapalı mı?
  ///
  /// Kapıyla ilgili menü öğelerinin gizlenmesi ve Panel'deki "Geçiş Kontrol modülü kapalı" kartı bu
  /// duruma bağlıdır. `door_control` için YALNIZ gerçek kapı erişimi olan siteler
  /// ([MySiteModules.doorAccess]) dikkate alınır: yalnız Yönetim Kurulu / Görevli bağı olan site
  /// sayılmaz. Hiç sitesi olmayan ya da kapı erişimi olan hiç sitesi olmayan kullanıcıda (örn. yalnız
  /// kendi cihazını kaydeden bireysel kullanıcı, yalnız kurul üyesi) false'tur: ekranları değişmez.
  bool isDisabledEverywhere(String code) {
    if (!isFiltering) return false;
    return _result!.isDisabledEverywhere(code);
  }

  /// Yanıtı şimdi (uçuşta bir tur varsa ondan SONRA bir kez daha) çeker. Dönüş: true başarılı, false
  /// hata (mevcut değer korunur), null atlandı (süper kullanıcı / sıfırlandı / kapatıldı).
  ///
  /// Bir tur sürerken çağrılırsa yeni tur o bittikten sonra çalışır: yazma işleminden hemen sonra
  /// çağrılan yenileme, işlemden ÖNCE başlamış eski bir yanıta takılıp bayat veri bırakmaz.
  Future<bool?> refresh() {
    if (_disposed) return Future<bool?>.value(null);
    final running = _inFlight;
    if (running != null) {
      _rerun = true;
      return running;
    }
    final run = _run();
    _inFlight = run;
    unawaited(
      run.whenComplete(() {
        if (identical(_inFlight, run)) _inFlight = null;
      }),
    );
    return run;
  }

  Future<bool?> _run() async {
    bool? outcome;
    do {
      _rerun = false;
      outcome = await _fetchOnce();
    } while (_rerun && !_disposed);
    return outcome;
  }

  Future<bool?> _fetchOnce() async {
    if (_isSuperUser?.call() ?? false) {
      // Süper kullanıcıda modül süzgeci yok; yalnız bekleyen talep / başvuru sayıları (rozet) tazelenir.
      final pending = _fetchPendingCount;
      final applications = _fetchPendingApplicationCount;
      if (pending == null && applications == null) return null;
      // İkisi eşzamanlı çekilir; sonuç: en az biri başarılıysa true, hepsi hatalıysa false (geri çekilme),
      // ikisi de atlandıysa null.
      final results = await Future.wait(<Future<bool?>>[
        if (pending != null) _fetchPendingOnce(pending),
        if (applications != null) _fetchPendingApplicationsOnce(applications),
      ]);
      if (results.any((r) => r == true)) return true;
      if (results.any((r) => r == false)) return false;
      return null;
    }
    final generation = _generation;
    try {
      final next = await _fetch();
      if (_disposed || generation != _generation) return null;
      if (_result != next) {
        _result = next;
        notifyListeners();
      }
      return true;
    } catch (_) {
      // Mevcut değer korunur (ya da hiç yoksa fail-open sürer).
      if (_disposed || generation != _generation) return null;
      return false;
    }
  }

  Future<bool?> _fetchPendingOnce(Future<int> Function() fetchPending) async {
    final generation = _generation;
    try {
      final count = await fetchPending();
      if (_disposed || generation != _generation) return null;
      if (_pendingRequestCount != count) {
        _pendingRequestCount = count;
        notifyListeners();
      }
      return true;
    } catch (_) {
      if (_disposed || generation != _generation) return null;
      return false;
    }
  }

  Future<bool?> _fetchPendingApplicationsOnce(Future<int> Function() fetchPending) async {
    final generation = _generation;
    try {
      final count = await fetchPending();
      if (_disposed || generation != _generation) return null;
      if (_pendingApplicationCount != count) {
        _pendingApplicationCount = count;
        notifyListeners();
      }
      return true;
    } catch (_) {
      if (_disposed || generation != _generation) return null;
      return false;
    }
  }

  /// Kısa aralıklı tazelemeyi başlatır (ilk tur [interval] sonra; hemen çekmek için [refresh]).
  void start({bool immediately = false}) {
    if (_disposed) return;
    _poller.start(immediately: immediately);
  }

  /// Tazelemeyi durdurur (uygulama arka plana gidince). Veri korunur.
  void stop() => _poller.stop();

  /// Ön plana dönüşte ya da elle yenilemede geri çekilmeyi sıfırlar.
  void resetBackoff() => _poller.resetBackoff();

  /// Çıkış ya da kullanıcı değişimi: durumu sıfırlar (yeni kullanıcıya eski kullanıcının
  /// modülleri sızmaz). Uçuştaki eski yanıt yok sayılır.
  void clear() {
    _generation++;
    if (_result != null || _pendingRequestCount != null || _pendingApplicationCount != null) {
      _result = null;
      _pendingRequestCount = null;
      _pendingApplicationCount = null;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _poller.dispose();
    super.dispose();
  }
}
