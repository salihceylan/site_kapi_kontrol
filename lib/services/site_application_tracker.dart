import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:site_kapi_kontrol/models/site_application.dart';
import 'package:site_kapi_kontrol/services/adaptive_poller.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';

/// "Başvur" eyleminin durumu (bireysel ana ekran, cihaz kartı, "Daireye Katıl").
enum SiteApplyAvailability {
  /// Durum biliniyor ve bekleyen başvuru yok: başvurulabilir.
  ready,

  /// Zaten bekleyen bir başvuru var: eylem pasif ("Başvurunuz İnceleniyor").
  pending,

  /// Durum henüz öğrenilmedi / gönderilen başvurunun kaydı doğrulanıyor: eylem pasif ("Durum kontrol ediliyor").
  checking,

  /// Durum ÖĞRENİLEMEDİ (hata): eylem pasif; üstteki kartta "Tekrar Dene" vardır.
  unknown,
}

/// Başvuranın (bireysel / daire kullanıcısı; ayrıca site yöneticisi) KENDİ site başvurusunun durumu
/// (Platform: site başvurusu).
///
/// - Veri `GET /membership/site-applications/mine` ile ([fetch]) çekilir. Ekranlar ilk açılışta
///   [ensureLoaded] çağırır; BEKLEYEN başvuru varken, durum öğrenilemediyse ya da son yükleme hatalıysa
///   [AdaptivePoller] ile ~30 sn'de bir (hatada üstel geri çekilmeyle) yoklanır. Bekleyen yokken ve durum
///   sağlıklıyken zamanlayıcı kurulmaz: ağ isteği yoktur. Uygulama arka plandayken / sayfa görünür değilken
///   ([isActive] false) tur atlanır; [dispose]/[stop] zamanlayıcıyı iptal eder.
/// - HATA DÜRÜSTTÜR: yükleme hatası [error] olarak durur ve ASLA "başvuru yok" anlamına gelmez
///   ([data] null kalır); önceki başarılı veri varken yoklama hatası veriyi silmez ama [error] doludur.
/// - Yarış koruması: her yükleme bir sıra numarası alır; daha yeni bir yükleme ya da yazma (iptal) başladıysa
///   eski/yavaş yanıt yok sayılır ve yeni sonucu ezmez. [dispose]/[clear] sonrası gelen yanıt (yükleme de
///   iptal de) yok sayılır.
/// - [approvals]: başvuru ONAYLANDI olayı (her başvuru için bir kez). Dinleyen oturum/rol bilgisini sunucudan
///   yeniler; rol burada TAHMİN EDİLMEZ. Çok eski (>= [approvalWindow]) onay olay üretmez. Dinleyen yenileme
///   sonrası rol hâlâ değişmediyse [consumeApproval] ile kartı kaldırır.
/// - [requiresApplication]: sunucunun `requires_application` bildirimi (site yöneticisi için anlık "Site Ekle"
///   mi, başvuru mu?); alan yoksa null.
/// - [isEligible] false iken (rol izlenmiyorsa; süper kullanıcı) hiçbir istek yapılmaz.
class SiteApplicationTracker extends ChangeNotifier {
  SiteApplicationTracker({
    required Future<MySiteApplications> Function() fetch,
    required Future<SiteApplication> Function(int id) cancel,
    bool Function()? isActive,
    bool Function()? isEligible,
    DateTime Function()? now,
    Duration interval = const Duration(seconds: 30),
    Duration maxDelay = const Duration(minutes: 2),
  }) : _fetch = fetch,
       _cancel = cancel,
       _isEligible = isEligible,
       _now = now ?? DateTime.now {
    _poller = AdaptivePoller(
      interval: interval,
      maxDelay: maxDelay,
      isActive: isActive,
      poll: refresh,
    );
  }

  /// Onay olayı üretilecek en uzun süre (karar zamanından beri).
  static const Duration approvalWindow = Duration(days: 7);

  final Future<MySiteApplications> Function() _fetch;
  final Future<SiteApplication> Function(int id) _cancel;
  final bool Function()? _isEligible;
  final DateTime Function() _now;
  late final AdaptivePoller _poller;
  final StreamController<SiteApplication> _approvals =
      StreamController<SiteApplication>.broadcast();

  MySiteApplications? _data;
  String? _error;
  bool _loading = false;
  bool _requested = false;
  bool _cancelling = false;
  bool _awaitingConfirmation = false;
  String? _cancelError;
  DateTime? _loadedAt;
  final Set<int> _announced = <int>{};
  final Set<int> _consumed = <int>{};
  int _seq = 0;
  int _epoch = 0;
  bool _disposed = false;

  /// Onaylanan başvuru olayları (broadcast).
  Stream<SiteApplication> get approvals => _approvals.stream;

  /// Son BAŞARILI yanıt; hiç alınmadıysa null ("başvuru yok" DEĞİL: bilinmiyor).
  MySiteApplications? get data => _data;

  /// Bekleyen başvuru (yoksa ya da bilinmiyorsa null).
  SiteApplication? get pending => _data?.pending;

  /// Ekranda gösterilecek en güncel başvuru; hiç başvuru yoksa ya da bilinmiyorsa null.
  SiteApplication? get latest => _data?.latest;

  /// Sunucunun `requires_application` bildirimi; bilinmiyorsa / alan yoksa null.
  bool? get requiresApplication => _data?.requiresApplication;

  /// En az bir yanıt başarıyla alındı mı?
  bool get hasLoaded => _data != null;

  /// Bir yükleme sürüyor mu?
  bool get loading => _loading;

  /// Son yükleme hatası (Türkçe); son yükleme başarılıysa null.
  String? get error => _error;

  /// İptal isteği sürüyor mu? (Çift dokunuş koruması.)
  bool get cancelling => _cancelling;

  /// Son iptal hatası (Türkçe); yoksa null.
  String? get cancelError => _cancelError;

  /// Başvuru gönderildi ama kaydı henüz sunucudan DOĞRULANAMADI (201 sonrası durum yenilemesi başarısız /
  /// sürüyor). Kullanıcıya "başvurunuz alındı, durum yenilenemedi" denir; yeni başvuru eylemi pasiftir.
  bool get awaitingConfirmation => _awaitingConfirmation;

  /// Yoklama zamanlayıcısı kurulu mu (testler için).
  bool get isPolling => _poller.isRunning;

  /// "Başvur" eyleminin durumu (bkz. [SiteApplyAvailability]).
  SiteApplyAvailability get applyAvailability {
    if (pending != null) return SiteApplyAvailability.pending;
    if (_awaitingConfirmation) {
      return _error != null ? SiteApplyAvailability.unknown : SiteApplyAvailability.checking;
    }
    if (!hasLoaded) {
      return _error != null ? SiteApplyAvailability.unknown : SiteApplyAvailability.checking;
    }
    return SiteApplyAvailability.ready;
  }

  /// [id] numaralı onay kartı kaldırıldı mı? (Yenileme sonrası rol hâlâ değişmediyse kart gösterilmez.)
  bool isApprovalConsumed(int id) => _consumed.contains(id);

  bool get _eligible => _isEligible?.call() ?? true;

  /// Yoklama istenir mi: bekleyen başvuru var, durum öğrenilemedi, son yükleme hatalı ya da gönderilen
  /// başvuru henüz doğrulanmadı.
  bool get _wantsPolling =>
      !_disposed &&
      _requested &&
      _eligible &&
      (pending != null || _data == null || _error != null || _awaitingConfirmation);

  /// Bir ekran görünür olurken: hiç yüklenmediyse ya da [staleAfter]'dan eskiyse yükler (aksi hâlde no-op).
  Future<void> ensureLoaded({Duration staleAfter = const Duration(minutes: 1)}) async {
    if (_disposed || !_eligible) return;
    _requested = true;
    final at = _loadedAt;
    final fresh = at != null && _now().difference(at) < staleAfter;
    if (_loading || (_data != null && fresh && _error == null)) {
      _syncPolling();
      return;
    }
    await refresh();
  }

  /// Durumu şimdi çeker. Dönüş: true başarılı, false hata (veri korunur), null atlandı (uygun değil / daha yeni
  /// bir yükleme ya da yazma başladı / kapatıldı).
  Future<bool?> refresh() async {
    if (_disposed || !_eligible) return null;
    _requested = true;
    final seq = ++_seq;
    if (!_loading) {
      _loading = true;
      notifyListeners();
    }
    final MySiteApplications next;
    try {
      next = await _fetch();
    } catch (e) {
      if (_disposed || seq != _seq) return null;
      _loading = false;
      _error = _messageOf(e, 'Site başvuru durumu alınamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.');
      _syncPolling();
      notifyListeners();
      return false;
    }
    if (_disposed || seq != _seq) return null;
    _loading = false;
    _error = null;
    _awaitingConfirmation = false;
    _data = next;
    _loadedAt = _now();
    _announceApproval(next.latest);
    _syncPolling();
    notifyListeners();
    return true;
  }

  /// Bekleyen başvuruyu iptal eder. Dönüş: iptal edilen başvuru; hata ya da atlanırsa null ([cancelError]
  /// doludur). Sonuç ne olursa olsun durum sunucudan yeniden okunur (örn. 409 `APPLICATION_NOT_PENDING`).
  /// İptal sürerken [clear]/[dispose] olursa eski sonuç geri yazılmaz.
  Future<SiteApplication?> cancelPending() async {
    final target = pending;
    if (_disposed || _cancelling || target == null) return null;
    _cancelling = true;
    _cancelError = null;
    final epoch = _epoch;
    // Uçuştaki eski bir yükleme (iptalden ÖNCE başlamış) bu yeni sonucu ezemesin.
    ++_seq;
    notifyListeners();
    SiteApplication? updated;
    try {
      final result = await _cancel(target.id);
      if (_disposed || epoch != _epoch) return null;
      updated = result;
      final current = _data;
      _data = MySiteApplications(
        items: <SiteApplication>[
          result,
          ...?current?.items.where((e) => e.id != result.id),
        ],
        requiresApplication: current?.requiresApplication,
      );
    } catch (e) {
      if (_disposed || epoch != _epoch) return null;
      _cancelError = _messageOf(e, 'Başvuru iptal edilemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.');
    }
    _cancelling = false;
    _syncPolling();
    notifyListeners();
    // Gerçek durum sunucudan: başarılıysa iptal doğrulanır, 409 ise (başka yerden karar verilmiş) güncel durum görünür.
    unawaited(refresh());
    return updated;
  }

  /// Başvuru formu durum uyuşmazlığıyla (örn. 409 `APPLICATION_PENDING`) kapandı: durumu sunucudan okur.
  Future<void> noteChanged() async {
    await refresh();
  }

  /// Başvuru GÖNDERİLDİ ya da sonucu BELİRSİZ (zaman aşımı / 5xx): durumu sunucudan okur. Okuma başarısız
  /// olursa [awaitingConfirmation] sürer, "başvurunuz alındı, durum yenilenemedi" bilgisi gösterilir ve
  /// yeniden deneme / yoklama devam eder; yeni başvuru eylemi pasif kalır.
  Future<void> noteSubmitted() async {
    if (_disposed) return;
    _awaitingConfirmation = true;
    _syncPolling();
    notifyListeners();
    await refresh();
  }

  /// Onay kartını kaldırır (yenileme sonrası rol hâlâ değişmediyse); olay tüketilmiş sayılır.
  void consumeApproval(int id) {
    if (_disposed || !_consumed.add(id)) return;
    notifyListeners();
  }

  void _announceApproval(SiteApplication? latest) {
    if (latest == null || !latest.isApproved || _announced.contains(latest.id)) return;
    final decided = latest.decidedAt;
    if (decided != null && _now().difference(decided) >= approvalWindow) return;
    _announced.add(latest.id);
    if (_approvals.hasListener) _approvals.add(latest);
  }

  void _syncPolling() {
    if (_wantsPolling) {
      if (!_poller.isRunning) _poller.start();
    } else if (_poller.isRunning) {
      _poller.stop();
    }
  }

  /// Ön plana dönüşte / elle yenilemede geri çekilmeyi sıfırlar.
  void resetBackoff() => _poller.resetBackoff();

  /// Zamanlayıcıyı durdurur (veri korunur). Bir sonraki [ensureLoaded] / [refresh] yeniden kurar.
  void stop() => _poller.stop();

  /// Çıkış / kullanıcı değişimi / izlenmeyen role geçiş: durumu sıfırlar (eski kullanıcının başvurusu yeni
  /// kullanıcıya sızmaz). Uçuştaki eski yanıt (yükleme ve iptal) yok sayılır.
  void clear() {
    ++_seq;
    ++_epoch;
    _poller.stop();
    final changed =
        _data != null || _error != null || _loading || _cancelling || _cancelError != null || _awaitingConfirmation;
    _data = null;
    _error = null;
    _loading = false;
    _requested = false;
    _cancelling = false;
    _cancelError = null;
    _awaitingConfirmation = false;
    _loadedAt = null;
    _announced.clear();
    _consumed.clear();
    if (changed && !_disposed) notifyListeners();
  }

  static String _messageOf(Object error, String fallback) {
    if (error is ApiException && error.message.trim().isNotEmpty) return error.message;
    return fallback;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    ++_seq;
    ++_epoch;
    _poller.dispose();
    unawaited(_approvals.close());
    super.dispose();
  }
}
