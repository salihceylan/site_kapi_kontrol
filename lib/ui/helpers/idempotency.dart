import 'dart:collection';
import 'dart:math';

/// Mali yazma isteklerinin `idempotency_key` değeri (Platform Faz 4a; sözleşme: çift tıklama / yeniden deneme
/// çift kayıt YARATMAZ). Anahtar 64 karakteri aşmaz ve yalnız küçük harf, rakam ve tire içerir.
///
/// Kullanım kuralı: bir GÖNDERİM girişimi için anahtar bir kez üretilir ve aynı veriyle yeniden denemede AYNI
/// anahtar kullanılır ([IdempotencyKeys.keyFor]); veri değişirse (kullanıcı tutarı düzeltti) yeni anahtar
/// üretilir, böylece eski isteğin sonucu yeni veriyle karışmaz.
String newIdempotencyKey([String prefix = 'app']) {
  final random = Random.secure();
  final buffer = StringBuffer(prefix)..write('-');
  for (var i = 0; i < 24; i++) {
    buffer.write(random.nextInt(16).toRadixString(16));
  }
  final key = buffer.toString();
  return key.length <= 64 ? key : key.substring(0, 64);
}

/// Verinin imzasına bağlı anahtar HARİTASI: aynı imza HER ZAMAN aynı anahtar, farklı imza farklı anahtar.
///
/// Neden harita (tek son imza değil): "A gönder (yanıt kayboldu) -> B'ye geç -> A'ya dön" akışında A'nın
/// anahtarı unutulursa ikinci A yeni anahtar alır ve sunucu ilk A'yı bilmediği için çift kayıt oluşur. Harita
/// her imzanın anahtarını, başarıyla bitene kadar ([clear]) tutar. Bellek sınırlıdır ([capacity]): en az
/// kullanılan imza atılır.
class IdempotencyKeys {
  IdempotencyKeys(this.prefix, {this.capacity = 32});

  final String prefix;
  final int capacity;
  final LinkedHashMap<String, String> _keys = LinkedHashMap<String, String>();

  /// [signature] için anahtar: varsa ESKİSİ, yoksa yenisi (en son kullanılan imza sona alınır).
  String keyFor(String signature) {
    final key = _keys.remove(signature) ?? newIdempotencyKey(prefix);
    _keys[signature] = key;
    while (_keys.length > capacity) {
      _keys.remove(_keys.keys.first);
    }
    return key;
  }

  /// [signature] için kayıtlı anahtar var mı?
  bool has(String signature) => _keys.containsKey(signature);

  /// Başarılı yazmadan sonra ya da sunucu anahtarı reddedince (`IDEMPOTENCY_CONFLICT`): imzanın anahtarı atılır;
  /// aynı imza sonraki gönderimde YENİ anahtar alır.
  void clear(String signature) => _keys.remove(signature);

  /// Hepsini atar (pencere kapanırken).
  void reset() => _keys.clear();
}

final Expando<Map<String, IdempotencyKeys>> _sessionKeys = Expando<Map<String, IdempotencyKeys>>(
  'idempotency',
);

/// [owner] (oturumu temsil eden servis nesnesi) ömrünce yaşayan anahtar haritası: yazma penceresi kapanıp
/// yeniden açılsa bile aynı oturumda aynı imza aynı anahtarı kullanır (yanıtı kaybolan tahsilat, pencereyi
/// kapatıp açınca çift kaydedilmez). Çıkış yapılıp servis atılınca anahtarlar da gider.
IdempotencyKeys sessionIdempotencyKeys(Object owner, String prefix) {
  final stores = _sessionKeys[owner] ??= <String, IdempotencyKeys>{};
  return stores.putIfAbsent(prefix, () => IdempotencyKeys(prefix));
}
