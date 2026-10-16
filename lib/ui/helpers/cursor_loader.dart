import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart' show crmMessageOf;

/// Bir imleç sayfası: kayıtlar + sonraki sayfanın `before_id`'si (son sayfada null).
typedef CursorPage<T> = ({List<T> items, int? next});

/// `before_id` imleçli bir liste için yükleme durumu (Platform Faz 3a: sakin gelen kutusu).
/// [PagedLoader]'ın (limit/offset) imleç karşılığıdır ve AYNI yarış korumalarını taşır:
/// - [reload] `_token`'ı ve `_moreToken`'ı, [loadMore] yalnız `_moreToken`'ı artırır. Eski bir isteğin
///   yanıtı (hızlı yenileme, site süzgeci değişimi) yeni sonucu EZMEZ ve "Daha fazla yükle" bayrağını
///   bozmaz.
/// - [dispose] sonrası gelen yanıt yok sayılır.
/// - Hata durumunda `items` korunur ama "kayıt yok" ASLA gösterilmez: çağıran `error` dolu ve liste
///   boşken hata + "Tekrar Dene" çizer.
/// - Sunucu aynı imleci tekrarlar ya da sayfayı boş döndürürse sonsuz döngüye girilmez.
class CursorLoader<T> {
  CursorLoader({
    required this.fetch,
    required this.keyOf,
    required this.notify,
    required this.isAlive,
    this.errorFallback = 'Liste yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
    this.moreErrorFallback = 'Daha fazla kayıt yüklenemedi. Tekrar deneyin.',
    this.messageOf = crmMessageOf,
  });

  /// `beforeId` imlecinden (null: ilk sayfa) sayfa getirir; süzgeç değerlerini ÇAĞRI ANINDA okur.
  final Future<CursorPage<T>> Function(int? beforeId) fetch;

  /// Yinelenen kaydı ayıklamak için kayıt anahtarı.
  final Object Function(T item) keyOf;

  /// Durum değişince çağıran `setState` yapar.
  final void Function() notify;

  /// Sahip hâlâ ekranda mı (`mounted`).
  final bool Function() isAlive;

  final String errorFallback;
  final String moreErrorFallback;

  /// Hatadan kullanıcı metni üretir (varsayılan [crmMessageOf]); mali ekranlar teknik metni göstermez.
  final String Function(Object error, String fallback) messageOf;

  List<T> items = <T>[];
  bool loading = false;
  bool loadingMore = false;
  String? error;
  String? moreError;

  /// En az bir yükleme başarıyla bitti mi? (false iken "kayıt yok" yerine iskelet/hata gösterilir.)
  bool loadedOnce = false;

  int _token = 0;
  int _moreToken = 0;
  bool _disposed = false;
  int? _next;

  /// Sonraki sayfa var mı?
  bool get hasMore => _next != null;

  /// Süzgeç / site değişince eski kayıtları siler (iskelet görünür). Ardından [reload] çağırın.
  void reset() {
    items = <T>[];
    _next = null;
    loadedOnce = false;
    error = null;
    moreError = null;
  }

  /// İlk sayfayı yeniden çeker; mevcut liste yenileme sürerken ekranda kalır. Sürmekte olan "Daha fazla
  /// yükle" iptal edilir.
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
      items = List<T>.of(page.items);
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
      // Bu arada yenileme / süzgeç değişimi oldu: eski sayfa eklenmez.
      if (_disposed || !isAlive() || more != _moreToken) return;
      final known = items.map(keyOf).toSet();
      final fresh = page.items.where((item) => !known.contains(keyOf(item))).toList();
      items = <T>[...items, ...fresh];
      // Boş / yalnız yinelenen sayfa ya da aynı imleç: sunucu tutarsız, dur (sonsuz döngü olmasın).
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

  /// Anahtarı [key] olan kaydı [update] ile değiştirir (örn. "okundu" işareti); yoksa bir şey yapmaz.
  void updateItem(Object key, T Function(T old) update) {
    if (_disposed || !isAlive()) return;
    final index = items.indexWhere((e) => keyOf(e) == key);
    if (index < 0) return;
    items = List<T>.of(items)..[index] = update(items[index]);
    notify();
  }

  /// Tüm kayıtları [update] ile değiştirir (örn. "tümünü okundu yap"); tek bildirim yapılır.
  void updateAll(T Function(T old) update) {
    if (_disposed || !isAlive()) return;
    items = <T>[for (final item in items) update(item)];
    notify();
  }

  /// Sahip kapanırken: uçuştaki yanıtlar yok sayılır.
  void dispose() {
    _disposed = true;
    ++_token;
    ++_moreToken;
  }
}
