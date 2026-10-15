import 'package:site_kapi_kontrol/services/api_exception.dart';

/// Sunucu hatasının kullanıcıya gösterilecek metni: [ApiException.message] doluysa o, değilse
/// [fallback].
String crmMessageOf(Object error, String fallback) {
  if (error is ApiException && error.message.trim().isNotEmpty) {
    return error.message;
  }
  return fallback;
}

/// Bir sayfa: kayıtlar + süzgece uyan toplam sayı.
typedef PagedResult<T> = ({List<T> items, int total});

/// `limit/offset` sayfalı bir liste için yükleme durumu (Platform Faz 2a: Kişiler / Daireler /
/// Araçlar ve seçici pencereleri).
///
/// Yarış koruması (önceki incelemelerin dersleri):
/// - Her [reload] `_token`'ı ve `_moreToken`'ı artırır; her [loadMore] yalnız `_moreToken`'ı artırır.
///   Eski bir isteğin yanıtı (hızlı art arda arama, süzgeç/site değişimi, yenileme) yeni sonucu EZMEZ ve
///   "Daha fazla yükle" bayrağını bozmaz.
/// - [dispose] sonrası gelen yanıt yok sayılır.
/// - Hata durumunda `items` korunur (yenileme hatası eski listeyi silmez) ama "kayıt yok" ASLA gösterilmez:
///   çağıran `error` dolu ve liste boşken hata + "Tekrar Dene" çizer.
class PagedLoader<T> {
  PagedLoader({
    required this.fetch,
    required this.keyOf,
    required this.notify,
    required this.isAlive,
    this.pageSize = 50,
    this.errorFallback = 'Liste yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
    this.moreErrorFallback = 'Daha fazla kayıt yüklenemedi. Tekrar deneyin.',
  });

  /// `offset`'ten başlayarak en çok `limit` kayıt getirir; süzgeç değerlerini ÇAĞRI ANINDA okur.
  final Future<PagedResult<T>> Function(int offset, int limit) fetch;

  /// Yinelenen kaydı ayıklamak için kayıt anahtarı (offset sayfalamada araya kayıt girerse).
  final Object Function(T item) keyOf;

  /// Durum değişince çağıran `setState` yapar.
  final void Function() notify;

  /// Sahip hâlâ ekranda mı (`mounted`).
  final bool Function() isAlive;

  final int pageSize;
  final String errorFallback;
  final String moreErrorFallback;

  List<T> items = <T>[];
  int total = 0;
  bool loading = false;
  bool loadingMore = false;
  String? error;
  String? moreError;

  /// En az bir yükleme başarıyla bitti mi? (false iken "kayıt yok" yerine iskelet/hata gösterilir.)
  bool loadedOnce = false;

  int _token = 0;
  int _moreToken = 0;
  bool _disposed = false;

  // Sunucudan alınan HAM kayıt sayısı (sonraki sayfanın `offset`'i). Yinelenen kayıt ayıklansa da offset
  // sunucunun saydığı gibi ilerler; sunucu `limit`'i kısaltsa (ör. 200'e) bile karar `total` ve `offset`'e
  // göredir, istenen limit'e bakılmaz.
  int _loaded = 0;
  bool _exhausted = false;

  /// Sonraki sayfa var mı? `offset < total`; son sayfa boş geldiyse (sunucu tutarsızlığı) sonsuz döngüye
  /// girmemek için false.
  bool get hasMore => !_exhausted && _loaded < total;

  /// Süzgeç / arama / site değişince eski kayıtları siler (iskelet görünür). Ardından [reload] çağırın.
  void reset() {
    items = <T>[];
    total = 0;
    _loaded = 0;
    _exhausted = false;
    loadedOnce = false;
    error = null;
    moreError = null;
  }

  /// İlk sayfayı yeniden çeker; mevcut liste yenileme sürerken ekranda kalır. Sürmekte olan "Daha fazla
  /// yükle" iptal edilir (sonucu yok sayılır, bayrağı sıfırlanır).
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
      final page = await fetch(0, pageSize);
      if (_disposed || !isAlive() || token != _token) return;
      items = List<T>.of(page.items);
      total = page.total;
      _loaded = page.items.length;
      _exhausted = page.items.isEmpty;
      loading = false;
      loadedOnce = true;
      notify();
    } catch (e) {
      if (_disposed || !isAlive() || token != _token) return;
      loading = false;
      error = crmMessageOf(e, errorFallback);
      notify();
    }
  }

  Future<void> loadMore() async {
    if (_disposed || !isAlive() || loading || loadingMore || !hasMore) return;
    final more = ++_moreToken;
    loadingMore = true;
    moreError = null;
    notify();
    try {
      final page = await fetch(_loaded, pageSize);
      // Bu arada yenileme / süzgeç değişimi oldu: eski sayfa eklenmez (bayrağı yeni yükleme sıfırladı).
      if (_disposed || !isAlive() || more != _moreToken) return;
      final known = items.map(keyOf).toSet();
      items = <T>[
        ...items,
        ...page.items.where((item) => !known.contains(keyOf(item))),
      ];
      total = page.total;
      _loaded += page.items.length;
      _exhausted = page.items.isEmpty;
      loadingMore = false;
      notify();
    } catch (e) {
      if (_disposed || !isAlive() || more != _moreToken) return;
      loadingMore = false;
      moreError = crmMessageOf(e, moreErrorFallback);
      notify();
    }
  }

  /// Sahip kapanırken: uçuştaki yanıtlar yok sayılır.
  void dispose() {
    _disposed = true;
    ++_token;
    ++_moreToken;
  }
}
