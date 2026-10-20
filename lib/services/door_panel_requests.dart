import 'package:flutter/foundation.dart';

/// Uygulama dışından gelen "Kapılar sayfasını aç" isteği: Android kapı widget'ının gövdesi (`sitekapi://door_control`),
/// uygulama kısayolları (sesli kapı açma, kapı kısayolu) ve kapıyla ilgili derin bağlantılar (`sitekapi://open`, `qr`,
/// `voice`). "Panel" artık modül vitrini olduğundan bu girişler kullanıcıyı eskisi gibi kapı paneline ("Kapılar")
/// götürür. İstek kapı AÇMAZ: yalnız hangi sayfanın gösterileceğini söyler (kapı açan bağlantıların onay penceresi ve
/// kapı açma yolu değişmez).
///
/// `app.dart` [request] ile yazar, HomePage [take] ile tüketir. HomePage henüz kurulmamışsa (soğuk açılış) istek bekler
/// ve HomePage ilk kurulduğunda BİR kez uygulanır; oturum kapanınca [clear] ile atılır. Geçiş Kontrol kapalıysa ya da
/// kullanıcının kapı erişimi yoksa HomePage vitrinde kalır.
class DoorPanelRequests extends ChangeNotifier {
  bool _pending = false;

  /// Uygulanmayı bekleyen istek var mı?
  bool get isPending => _pending;

  /// Kapılar sayfasını iste (dinleyiciler uyarılır).
  void request() {
    _pending = true;
    notifyListeners();
  }

  /// Bekleyen istek varsa siler ve true döner (bir istek bir kez uygulanır).
  bool take() {
    if (!_pending) return false;
    _pending = false;
    return true;
  }

  /// Bekleyen isteği atar (oturum kapandı / kullanıcı değişti).
  void clear() => _pending = false;
}
