import 'package:flutter/widgets.dart';

/// Derin (yeni sayfa olarak açılan) ekranlardan "Ana sayfa": açık ekranların hepsini kapatır ve ana kabuğa (HomePage)
/// Panel'i (ana sayfa) seçtirir. Karşılaştırma raporu P1-13.
///
/// Ana kabuğun üst çubuğundaki "Ana sayfa" düğmesi bu servise ihtiyaç duymaz (kendi menüsünü doğrudan değiştirir). Servis,
/// kabuğun ÜSTÜNE itilmiş ekranlar içindir (Finans > Banka dosyası > Banka satırları gibi iç içe sayfalar): onların kendi
/// üst çubuğu vardır, ana kabuğun düğmesi ve sakin alt çubuğu (Özet sekmesi) altta kalır. Bu ekranlar [returnToPanel]'i
/// çağırır; HomePage [request] ile uyarılır ve çekmeceden "Panel"i seçmekle AYNI korumalı yoldan Panel'e geçer
/// (kaydedilmemiş değişiklik onayı dahil).
///
/// İstek BEKLETİLMEZ: o anda kabuk dinlemiyorsa (örneğin oturum kapanmışsa) hiçbir şey olmaz. Servis hiçbir ekranı
/// kendiliğinden kapatmaz; yalnız [returnToPanel] çağrısı kapatır ve kaydedilmemiş veri taşıyan formlara (sihirbaz,
/// düzenleme) varsayılan düğme konmaz (konursa ekran [returnToPanel]'den ÖNCE kendi onayını verir: İşletme Projesi ayrıntısı).
class PanelReturnRequests extends ChangeNotifier {
  PanelReturnRequests._();

  /// Uygulamanın tek örneği (kabuk dinler, derin ekranlar çağırır; yapıcıya taşıma gerekmez).
  static final PanelReturnRequests instance = PanelReturnRequests._();

  /// [context]'in bulunduğu ekrandan başlayarak ilk sayfaya (ana kabuk) kadar her şeyi kapatır ve Panel'i ister.
  static void returnToPanel(BuildContext context) {
    Navigator.of(context).popUntil((route) => route.isFirst);
    instance.request();
  }

  /// Dinleyen kabuğa "Panel'e dön" der.
  void request() => notifyListeners();
}
