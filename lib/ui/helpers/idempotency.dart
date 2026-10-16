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

/// Verinin imzasına bağlı anahtar tutucu: aynı imza -> aynı anahtar, farklı imza -> yeni anahtar.
class IdempotencyKeys {
  IdempotencyKeys(this.prefix);

  final String prefix;
  String? _signature;
  String? _key;

  /// [signature] önceki girişimle aynıysa önceki anahtarı, değilse yenisini döndürür.
  String keyFor(String signature) {
    if (_key == null || _signature != signature) {
      _signature = signature;
      _key = newIdempotencyKey(prefix);
    }
    return _key!;
  }

  /// Başarılı bir yazmadan sonra (ya da önizleme yenilenince) sıfırlanır.
  void reset() {
    _signature = null;
    _key = null;
  }
}
