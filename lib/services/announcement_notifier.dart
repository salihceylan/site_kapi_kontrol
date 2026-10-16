import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:site_kapi_kontrol/models/announcement.dart';
import 'package:site_kapi_kontrol/services/adaptive_poller.dart';

/// Uygulama içi "yeni duyuru" olayı ([AnnouncementNotifier.alerts]). [title] ayrıntı alınamadıysa null
/// (genel metin gösterilir); [announcementId] belirsizse null (yalnız Duyurular ekranı açılır).
@immutable
class AnnouncementAlert {
  const AnnouncementAlert({this.announcementId, this.title, this.urgent = false});

  final int? announcementId;
  final String? title;
  final bool urgent;
}

/// Sakin için duyuru bildirim durumu (Platform Faz 3a, 4. madde): okunmamış sayısı (çekmece rozeti),
/// okunmamış ACİL duyuru (Panel'in üstündeki kalıcı kırmızı şerit) ve "yeni duyuru" olayları.
///
/// Bu bir "anlık itme" DEĞİLDİR: `GET /app/notifications/summary` [AdaptivePoller] ile yoklanır (ön planda
/// ~20 sn; uygulama arka plandayken / sayfa görünür değilken ağ isteği yapılmaz; ardışık hatada üstel
/// geri çekilme). [dispose]/[stop] zamanlayıcıyı iptal eder.
///
/// - İlk başarılı yanıt YENİ DUYURU sayılmaz (taban çizgisi): uygulama açılınca eski duyuru için şerit
///   çıkmaz. Sonraki yanıtta en son yayınlanan duyurunun YAYIN ZAMANI ilerlemişse (`latest_published_at`;
///   alan yoksa `latest_announcement_id` büyümüşse) ya da okunmamış sayısı SUNUCUNUN önceki değerinden
///   fazlaysa [alerts] olayı yayınlanır (yeni duyuruda başlık ayrıca alınır). Numara tek başına ölçüt
///   DEĞİLDİR: zamanlanmış bir duyuru küçük numarayla sonradan yayınlanabilir; en son duyuru geri çekilince
///   "en son" geriye gidebilir ve bu yeni duyuru sayılmaz.
/// - Okunmamış ACİL sayısı > 0 iken en yeni okunmamış acil duyuru gelen kutusundan bulunur ([urgent]).
///   Bulunamazsa şerit yine görünür (genel metin).
/// - Yerel iyimser güncellemeler ([noteRead], [noteAllRead]) görüntülenen sayıyı hemen düşürür; sunucu
///   değeri yeniden okununca ([refresh]) eşitlenir. Alert karşılaştırması yalnız SUNUCU değerleriyle
///   yapılır (yerel düşüş yüzünden sahte "yeni duyuru" çıkmaz).
/// - [clear] (çıkış / kullanıcı değişimi) durumu sıfırlar; uçuştaki eski yanıt yok sayılır.
class AnnouncementNotifier extends ChangeNotifier {
  AnnouncementNotifier({
    required Future<NotificationSummary> Function() fetchSummary,
    required Future<ResidentAnnouncementPage> Function() fetchInbox,
    required Future<ResidentAnnouncement> Function(int id) fetchAnnouncement,
    bool Function()? isActive,
    bool Function()? isEligible,
    Duration interval = const Duration(seconds: 20),
    Duration maxDelay = const Duration(minutes: 2),
  }) : _fetchSummary = fetchSummary,
       _fetchInbox = fetchInbox,
       _fetchAnnouncement = fetchAnnouncement,
       _isEligible = isEligible {
    _poller = AdaptivePoller(
      interval: interval,
      maxDelay: maxDelay,
      isActive: isActive,
      poll: refresh,
    );
  }

  final Future<NotificationSummary> Function() _fetchSummary;
  final Future<ResidentAnnouncementPage> Function() _fetchInbox;
  final Future<ResidentAnnouncement> Function(int id) _fetchAnnouncement;
  final bool Function()? _isEligible;
  late final AdaptivePoller _poller;
  final StreamController<AnnouncementAlert> _alerts =
      StreamController<AnnouncementAlert>.broadcast();

  NotificationSummary? _server;
  int _unread = 0;
  int _unreadUrgent = 0;
  ResidentAnnouncement? _urgent;
  String _urgentSignature = '';
  bool _urgentResolveFailed = false;
  bool _hasBaseline = false;
  int? _baselineId;
  DateTime? _baselineAt;
  Future<bool?>? _inFlight;
  bool _degraded = false;
  bool _rerun = false;
  bool _disposed = false;
  int _generation = 0;

  /// Yeni duyuru olayları (broadcast). Dinleyen yoksa olay kaybolur (ekran zaten rozeti gösterir).
  Stream<AnnouncementAlert> get alerts => _alerts.stream;

  /// Çekmece rozeti için okunmamış duyuru sayısı.
  int get unreadCount => _unread;

  /// Okunmamış acil duyuru sayısı.
  int get unreadUrgent => _unreadUrgent;

  /// Okunmamış acil duyuru var mı? (Panel'deki kırmızı şeridin koşulu.)
  bool get hasUnreadUrgent => _unreadUrgent > 0;

  /// Şeridin açacağı en yeni okunmamış acil duyuru; henüz bulunamadıysa null.
  ResidentAnnouncement? get urgentAnnouncement => _urgent;

  /// Son sunucu özeti; hiç alınmadıysa null.
  NotificationSummary? get summary => _server;

  /// Son yoklama başarısız mı? Hatada yoklama aralığı üstel olarak (en çok 2 dk) uzar: "yaklaşık 20 saniyede
  /// bir" bilgisi o sırada yanlış olur; ekran "Bağlantı sorunu: daha seyrek kontrol ediliyor" yazar.
  bool get isDegraded => _degraded;

  /// Zamanlayıcı kurulu mu.
  bool get isRunning => _poller.isRunning;

  /// Özeti şimdi (uçuşta bir tur varsa ondan SONRA bir kez daha) çeker. Dönüş: true başarılı, false hata
  /// (mevcut değer korunur), null atlandı (uygun değil / sıfırlandı / kapatıldı).
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
    final eligible = _isEligible;
    if (eligible != null && !eligible()) return null;
    final generation = _generation;
    final NotificationSummary next;
    try {
      next = await _fetchSummary();
    } catch (_) {
      if (_disposed || generation != _generation) return null;
      _setDegraded(true);
      return false;
    }
    if (_disposed || generation != _generation) return null;
    _setDegraded(false);
    _apply(next, generation);
    return true;
  }

  void _setDegraded(bool value) {
    if (_degraded == value || _disposed) return;
    _degraded = value;
    notifyListeners();
  }

  void _apply(NotificationSummary next, int generation) {
    final previous = _server;
    final latest = next.latestAnnouncementId;

    // Yeni duyuru tespiti (yalnız sunucu değerleriyle).
    AnnouncementAlert? pendingAlert;
    var fetchTitleOf = 0;
    if (!_hasBaseline) {
      _hasBaseline = true;
    } else {
      final latestAt = next.latestPublishedAt;
      final fresh = latestAt != null
          ? (_baselineAt == null || latestAt.isAfter(_baselineAt!))
          : (latest != null && (_baselineId == null || latest > _baselineId!));
      final countUp =
          previous != null && next.unreadAnnouncements > previous.unreadAnnouncements;
      if (fresh && latest != null) {
        fetchTitleOf = latest;
      } else if (fresh || countUp) {
        pendingAlert = const AnnouncementAlert();
      }
    }
    _baselineId = latest;
    _baselineAt = next.latestPublishedAt;

    final changed =
        _server != next ||
        _unread != next.unreadAnnouncements ||
        _unreadUrgent != next.unreadUrgent;
    _server = next;
    _unread = next.unreadAnnouncements;
    _unreadUrgent = next.unreadUrgent;
    var urgentChanged = false;
    if (_unreadUrgent == 0 && _urgent != null) {
      _urgent = null;
      urgentChanged = true;
    }
    if (changed || urgentChanged) notifyListeners();

    if (pendingAlert != null) _alerts.add(pendingAlert);
    if (fetchTitleOf > 0) unawaited(_announceNew(fetchTitleOf, generation));
    _maybeResolveUrgent(generation);
  }

  /// Yeni duyurunun başlığını alıp olayı yayınlar; alınamazsa başlıksız (genel metinli) olay.
  Future<void> _announceNew(int id, int generation) async {
    AnnouncementAlert alert;
    try {
      final item = await _fetchAnnouncement(id);
      alert = AnnouncementAlert(
        announcementId: id,
        title: item.title.trim().isEmpty ? null : item.title.trim(),
        urgent: item.isUrgent,
      );
    } catch (_) {
      alert = AnnouncementAlert(announcementId: id);
    }
    if (_disposed || generation != _generation) return;
    _alerts.add(alert);
  }

  void _maybeResolveUrgent(int generation) {
    if (_unreadUrgent <= 0) {
      _urgentSignature = '';
      _urgentResolveFailed = false;
      return;
    }
    final signature = '$_unreadUrgent|${_server?.latestAnnouncementId}';
    if (signature == _urgentSignature && !_urgentResolveFailed) return;
    _urgentSignature = signature;
    unawaited(_resolveUrgent(generation));
  }

  Future<void> _resolveUrgent(int generation) async {
    try {
      final page = await _fetchInbox();
      if (_disposed || generation != _generation) return;
      ResidentAnnouncement? found;
      for (final item in page.items) {
        if (item.isUrgent && !item.isRead) {
          found = item;
          break;
        }
      }
      _urgentResolveFailed = false;
      if (_urgent?.id != found?.id) {
        _urgent = found;
        notifyListeners();
      }
    } catch (_) {
      if (_disposed || generation != _generation) return;
      _urgentResolveFailed = true;
    }
  }

  /// Sakin [id] numaralı duyuruyu okudu (sunucuya yazıldı): görüntülenen sayılar hemen düşer. Ardından
  /// sunucu değeriyle eşitlemek için [refresh] çağrılmalıdır.
  void noteRead(int id, {required bool urgent}) {
    if (_disposed) return;
    var changed = false;
    if (_unread > 0) {
      _unread--;
      changed = true;
    }
    if (urgent && _unreadUrgent > 0) {
      _unreadUrgent--;
      changed = true;
    }
    if (_urgent?.id == id) {
      _urgent = null;
      // Başka okunmamış acil duyuru varsa bir sonraki turda yeniden aranır.
      _urgentResolveFailed = _unreadUrgent > 0;
      changed = true;
    }
    if (changed) notifyListeners();
  }

  /// "Tümünü okundu yap" sunucuya yazıldı. Tüm sitelerde ise ([allSites]) sayılar sıfırlanır; tek site
  /// ise yalnız [refresh] gerekir (kalan sayı sunucudan okunur).
  void noteAllRead({required bool allSites}) {
    if (_disposed || !allSites) return;
    if (_unread != 0 || _unreadUrgent != 0 || _urgent != null) {
      _unread = 0;
      _unreadUrgent = 0;
      _urgent = null;
      notifyListeners();
    }
  }

  /// Kısa aralıklı yoklamayı başlatır ([immediately]: ilk tur hemen).
  void start({bool immediately = false}) {
    if (_disposed) return;
    _poller.start(immediately: immediately);
  }

  /// Yoklamayı durdurur (veri korunur).
  void stop() => _poller.stop();

  /// Ön plana dönüşte ya da elle yenilemede geri çekilmeyi sıfırlar.
  void resetBackoff() => _poller.resetBackoff();

  /// Çıkış ya da kullanıcı değişimi: durumu sıfırlar (yeni kullanıcıya eski kullanıcının duyuruları
  /// sızmaz). Uçuştaki eski yanıt yok sayılır; taban çizgisi yeniden kurulur.
  void clear() {
    _generation++;
    final had = _server != null || _unread != 0 || _unreadUrgent != 0 || _urgent != null;
    _server = null;
    _unread = 0;
    _unreadUrgent = 0;
    _urgent = null;
    _urgentSignature = '';
    _urgentResolveFailed = false;
    _hasBaseline = false;
    _degraded = false;
    _baselineId = null;
    _baselineAt = null;
    if (had && !_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _poller.dispose();
    unawaited(_alerts.close());
    super.dispose();
  }
}
