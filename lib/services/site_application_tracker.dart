import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:site_kapi_kontrol/models/site_application.dart';
import 'package:site_kapi_kontrol/services/adaptive_poller.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';

/// Başvuranın (bireysel / daire kullanıcısı) KENDİ site başvurusunun durumu (Platform: site başvurusu).
///
/// - Veri `GET /membership/site-applications/mine` ile ([fetch]) çekilir. Ekranlar ilk açılışta
///   [ensureLoaded] çağırır; BEKLEYEN başvuru varken (ya da durum henüz öğrenilemediyse) [AdaptivePoller] ile
///   ~30 sn'de bir yoklanır. Bekleyen yokken zamanlayıcı kurulmaz: ağ isteği yoktur. Uygulama arka plandayken
///   / sayfa görünür değilken ([isActive] false) tur atlanır; [dispose]/[stop] zamanlayıcıyı iptal eder.
/// - HATA DÜRÜSTTÜR: yükleme hatası [error] olarak durur ve ASLA "başvuru yok" anlamına gelmez
///   ([data] null kalır); önceki başarılı veri varken yoklama hatası veriyi silmez (kart kalır, uyarı çıkar).
/// - Yarış koruması: her yükleme bir sıra numarası alır; daha yeni bir yükleme ya da yazma (iptal) başladıysa
///   eski/yavaş yanıt yok sayılır ve yeni sonucu ezmez. [dispose]/[clear] sonrası gelen yanıt yok sayılır.
/// - [approvals]: başvuru ONAYLANDI olayı (her başvuru için bir kez). Dinleyen oturum/rol bilgisini sunucudan
///   yeniler; rol burada TAHMİN EDİLMEZ. Çok eski (>= [approvalWindow]) onay olay üretmez (site sonradan
///   silinmiş bir hesapta sonsuz yenileme döngüsü olmasın).
/// - [isEligible] false iken (rol bireysel / daire kullanıcısı değilse) hiçbir istek yapılmaz.
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
  String? _cancelError;
  DateTime? _loadedAt;
  final Set<int> _announced = <int>{};
  int _seq = 0;
  bool _disposed = false;

  /// Onaylanan başvuru olayları (broadcast).
  Stream<SiteApplication> get approvals => _approvals.stream;

  /// Son BAŞARILI yanıt; hiç alınmadıysa null ("başvuru yok" DEĞİL: bilinmiyor).
  MySiteApplications? get data => _data;

  /// Bekleyen başvuru (yoksa ya da bilinmiyorsa null).
  SiteApplication? get pending => _data?.pending;

  /// Ekranda gösterilecek en güncel başvuru; hiç başvuru yoksa ya da bilinmiyorsa null.
  SiteApplication? get latest => _data?.latest;

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

  /// Yoklama zamanlayıcısı kurulu mu (testler için).
  bool get isPolling => _poller.isRunning;

  bool get _eligible => _isEligible?.call() ?? true;

  /// Yoklama istenir mi: bekleyen başvuru var ya da durum öğrenilemedi (ilk yükleme hatalı).
  bool get _wantsPolling =>
      !_disposed && _requested && _eligible && (pending != null || _data == null);

  /// Bir ekran görünür olurken: hiç yüklenmediyse ya da [staleAfter]'dan eskiyse yükler (aksi hâlde no-op).
  Future<void> ensureLoaded({Duration staleAfter = const Duration(minutes: 1)}) async {
    if (_disposed || !_eligible) return;
    _requested = true;
    final at = _loadedAt;
    final fresh = at != null && _now().difference(at) < staleAfter;
    if (_loading || (_data != null && fresh)) {
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
    _data = next;
    _loadedAt = _now();
    _announceApproval(next.latest);
    _syncPolling();
    notifyListeners();
    return true;
  }

  /// Bekleyen başvuruyu iptal eder. Dönüş: iptal edilen başvuru; hata ya da atlanırsa null ([cancelError]
  /// doludur). Sonuç ne olursa olsun durum sunucudan yeniden okunur (örn. 409 `APPLICATION_NOT_PENDING`).
  Future<SiteApplication?> cancelPending() async {
    final target = pending;
    if (_disposed || _cancelling || target == null) return null;
    _cancelling = true;
    _cancelError = null;
    // Uçuştaki eski bir yükleme (iptalden ÖNCE başlamış) bu yeni sonucu ezemesin.
    ++_seq;
    notifyListeners();
    SiteApplication? updated;
    try {
      final result = await _cancel(target.id);
      updated = result;
      if (_disposed) return null;
      final current = _data;
      _data = MySiteApplications(
        items: <SiteApplication>[
          result,
          ...?current?.items.where((e) => e.id != result.id),
        ],
      );
    } catch (e) {
      if (_disposed) return null;
      _cancelError = _messageOf(e, 'Başvuru iptal edilemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.');
    }
    _cancelling = false;
    _syncPolling();
    notifyListeners();
    // Gerçek durum sunucudan: başarılıysa iptal doğrulanır, 409 ise (başka yerden karar verilmiş) güncel durum görünür.
    unawaited(refresh());
    return updated;
  }

  /// Yeni başvuru gönderildi (ya da 409 `APPLICATION_PENDING` döndü): durumu hemen yeniden okur.
  Future<void> noteChanged() async {
    await refresh();
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

  /// Çıkış / kullanıcı ya da rol değişimi: durumu sıfırlar (eski kullanıcının başvurusu yeni kullanıcıya
  /// sızmaz). Uçuştaki eski yanıt yok sayılır.
  void clear() {
    ++_seq;
    _poller.stop();
    final changed = _data != null || _error != null || _loading || _cancelling || _cancelError != null;
    _data = null;
    _error = null;
    _loading = false;
    _requested = false;
    _cancelling = false;
    _cancelError = null;
    _loadedAt = null;
    _announced.clear();
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
    _poller.dispose();
    unawaited(_approvals.close());
    super.dispose();
  }
}
