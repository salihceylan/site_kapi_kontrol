// Hesap silindikten sonra cihazdaki yerel durumu temizler.
//
// Merkezi çıkış ([AuthService.logout]) oturumu, kapı önbelleğini ve ana ekran widget verisini zaten siler;
// bu sınıf geri kalanını siler:
// - güvenli depolama (oturum kopyası, yerel kapı erişim önbelleği, varsa diğer her anahtar),
// - SharedPreferences: "beni hatırla" (kayıtlı giriş adı = e-posta), sesli komut ayarı ve uygulamanın diğer tüm
//   anahtarları. TEMA tercihi korunur: hesaba bağlı olmayan, yalnız cihaz görünümü ayarıdır,
// - ana ekran kısayolları (kapı adı taşır),
// - diskte kalmış kişisel veri dışa aktarma geçici dosyaları,
// - bellekteki görüntü önbelleği.
// YAN ETKİ (kasıtlı, uygulama içi silmeyle de uzaktan silmeyle de AYNI): güvenli depolama komple `deleteAll` edilir,
// yani aynı cihazdaki DİĞER hesapların güvenilir cihaz belirteçleri (`login_device_tokens_v1` haritası) da gider
// (o hesaplar sonraki girişte yalnızca yeniden doğrulama ister); SharedPreferences'ta tema dışındaki her anahtar
// silinir. Hesap bazlı ayıklama yapılmaz: silinen hesabın hangi anahtarlara yazdığını güvenle ayırt etmek,
// ortada kalan kişisel veri riskinden daha kırılgandır.
// AdaptivePoller / bildirim izleyicileri ana sayfaya aittir; oturum kapanınca ana sayfa ağaçtan kalkıp bunları
// kendisi durdurur ve atar.
//
// Her adım bağımsızdır: biri hata verirse diğerleri yine çalışır; hata ayrıntısı DEĞİL yalnız adım adı raporlanır
// (kişisel veri günlüğe yazılmaz).
import 'dart:io' show Directory;

import 'package:flutter/painting.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:site_kapi_kontrol/services/account_export_share.dart';
import 'package:site_kapi_kontrol/services/quick_actions_service.dart';
import 'package:site_kapi_kontrol/services/theme_service.dart';

/// Temizlik sonucu: başarısız adımların adları (boşsa hepsi tamam).
class LocalWipeReport {
  const LocalWipeReport({this.failedSteps = const <String>[]});

  final List<String> failedSteps;

  bool get complete => failedSteps.isEmpty;
}

class LocalDataWiper {
  LocalDataWiper({
    FlutterSecureStorage? secureStorage,
    Future<SharedPreferences> Function()? preferences,
    Future<void> Function()? clearShortcuts,
    Set<String> keepPreferenceKeys = const <String>{ThemeService.storageKey},
    Directory? exportTempRoot,
  }) : _exportTempRoot = exportTempRoot,
       _secureStorage = secureStorage ?? const FlutterSecureStorage(),
       _preferences = preferences ?? SharedPreferences.getInstance,
       _clearShortcuts = clearShortcuts ?? QuickActionsService().clearShortcuts,
       _keepPreferenceKeys = keepPreferenceKeys;

  /// Giriş ekranının "beni hatırla" ile sakladığı kayıtlı giriş adı (e-posta) anahtarı (`LoginPage`).
  static const String savedLoginIdentifierKey = 'saved_login_identifier';

  final FlutterSecureStorage _secureStorage;
  final Future<SharedPreferences> Function() _preferences;
  final Future<void> Function() _clearShortcuts;
  final Set<String> _keepPreferenceKeys;

  /// Dışa aktarma geçici klasörlerinin süpürüleceği kök (null: sistem geçici dizini). Testler içindir.
  final Directory? _exportTempRoot;

  /// Kayıtlı giriş adını (e-posta) siler. Çıkıştan ÖNCE çağrılır: çıkış giriş ekranını hemen kurar ve ekran
  /// açılışta bu değeri okuyup alana yazar; silinmiş hesabın e-postası ekranda görünmesin.
  Future<void> clearSavedLoginIdentifier() async {
    try {
      final prefs = await _preferences();
      await prefs.remove(savedLoginIdentifierKey);
    } catch (_) {
      // Tam temizlik [wipe] içinde yeniden denenir.
    }
  }

  Future<LocalWipeReport> wipe() async {
    final failed = <String>[];

    try {
      final prefs = await _preferences();
      for (final key in prefs.getKeys().toList()) {
        if (_keepPreferenceKeys.contains(key)) continue;
        await prefs.remove(key);
      }
    } catch (_) {
      failed.add('shared_preferences');
    }

    try {
      await _secureStorage.deleteAll();
    } catch (_) {
      failed.add('secure_storage');
    }

    try {
      await _clearShortcuts();
    } catch (_) {
      failed.add('shortcuts');
    }

    // Kişisel veri dışa aktarmasının geçici JSON kopyaları: diskte kalmış olanlar (süreç öldürüldüyse silme
    // zamanlayıcısı hiç çalışmamıştır) VE bu süreçte paylaşımı süren / gecikmeli silinecek olanlar (hesap artık yok:
    // alıcıyı beklemenin anlamı yok, bekleyen zamanlayıcılar iptal edilir). Hata fırlatmaz (en iyi çaba).
    await AccountExportSharer.sweepAll(staleAfter: Duration.zero, root: _exportTempRoot, includeLive: true);

    try {
      final cache = PaintingBinding.instance.imageCache;
      cache.clear();
      cache.clearLiveImages();
    } catch (_) {
      failed.add('image_cache');
    }

    return LocalWipeReport(failedSteps: failed);
  }
}
