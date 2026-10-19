import 'package:site_kapi_kontrol/models/decision_models.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart' show crmMessageOf;

/// Karar listesi yükleyicisi: [DecisionCursor] imleçli sayfalar (`before_id` ya da opak `cursor`) + kayıtlı yıllar
/// (`years`). [CursorLoader] ile AYNI yarış korumalarını taşır:
/// - [reload] `_token`'ı ve `_moreToken`'ı, [loadMore] yalnız `_moreToken`'ı artırır; eski yanıt yenisini EZMEZ.
/// - [dispose] sonrası gelen yanıt yok sayılır.
/// - Hata durumunda `items` korunur ama "kayıt yok" ASLA gösterilmez (çağıran hata + "Tekrar Dene" çizer).
/// - Sunucu aynı imleci tekrarlar ya da yalnız bilinen kayıtları döndürürse sonsuz döngüye girilmez.
class DecisionListLoader {
  DecisionListLoader({
    required this.fetch,
    required this.notify,
    required this.isAlive,
    this.errorFallback = 'Kararlar yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
    this.moreErrorFallback = 'Daha fazla karar yüklenemedi. Tekrar deneyin.',
    this.messageOf = crmMessageOf,
  });

  /// [cursor] imlecinden (null: ilk sayfa) sayfa getirir; süzgeç değerlerini ÇAĞRI ANINDA okur.
  final Future<DecisionPage> Function(DecisionCursor? cursor) fetch;
  final void Function() notify;
  final bool Function() isAlive;
  final String errorFallback;
  final String moreErrorFallback;
  final String Function(Object error, String fallback) messageOf;

  List<Decision> items = <Decision>[];

  /// Kaydı olan yıllar (son başarılı ilk sayfadan; yeniden eskiye).
  List<int> years = <int>[];
  bool loading = false;
  bool loadingMore = false;
  String? error;
  String? moreError;
  bool loadedOnce = false;

  int _token = 0;
  int _moreToken = 0;
  bool _disposed = false;
  DecisionCursor? _next;

  bool get hasMore => _next != null;

  /// Süzgeç / site değişince eski kayıtları siler (iskelet görünür). Ardından [reload] çağırın. Yıllar korunur.
  void reset() {
    items = <Decision>[];
    _next = null;
    loadedOnce = false;
    error = null;
    moreError = null;
  }

  Future<void> reload() async {
    if (_disposed || !isAlive()) return;
    final token = ++_token;
    ++_moreToken;
    loading = true;
    loadingMore = false;
    error = null;
    moreError = null;
    notify();
    try {
      final page = await fetch(null);
      if (_disposed || !isAlive() || token != _token) return;
      items = List<Decision>.of(page.items);
      if (page.years.isNotEmpty || items.isEmpty) years = page.years;
      _next = page.items.isEmpty ? null : page.next;
      loading = false;
      loadedOnce = true;
      notify();
    } catch (e) {
      if (_disposed || !isAlive() || token != _token) return;
      loading = false;
      error = messageOf(e, errorFallback);
      notify();
    }
  }

  Future<void> loadMore() async {
    final cursor = _next;
    if (cursor == null || _disposed || !isAlive() || loading || loadingMore) return;
    final more = ++_moreToken;
    loadingMore = true;
    moreError = null;
    notify();
    try {
      final page = await fetch(cursor);
      if (_disposed || !isAlive() || more != _moreToken) return;
      final known = <int>{for (final d in items) d.id};
      final fresh = page.items.where((d) => !known.contains(d.id)).toList();
      items = <Decision>[...items, ...fresh];
      _next = (fresh.isEmpty || page.next == cursor) ? null : page.next;
      loadingMore = false;
      notify();
    } catch (e) {
      if (_disposed || !isAlive() || more != _moreToken) return;
      loadingMore = false;
      moreError = messageOf(e, moreErrorFallback);
      notify();
    }
  }

  /// Güncellenen kaydı yerine koyar (yoksa bir şey yapmaz).
  void replace(Decision updated) {
    if (_disposed || !isAlive()) return;
    final index = items.indexWhere((d) => d.id == updated.id);
    if (index < 0) return;
    items = List<Decision>.of(items)..[index] = updated;
    notify();
  }

  void dispose() {
    _disposed = true;
    ++_token;
    ++_moreToken;
  }
}
