import 'dart:async';

import 'package:site_kapi_kontrol/models/platform_module.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';

/// Kapı kısayolu / derin bağlantı / sesli komut akışlarında Geçiş Kontrol modülünün KAPALI olması
/// durumunu kullanıcıya doğru söylemek için küçük yardımcı (Platform modül sistemi Faz 1).
///
/// Kapalı modülde kullanıcının kapı listesi sunucuda boşaltılır; bu durumda "Kapı bulunamadı."
/// demek yanıltıcıdır. Kararı [MyModulesResult.isDisabledEverywhere] verir: kullanıcının gerçek kapı
/// erişimi olan TÜM sitelerinde Geçiş Kontrol kapalıysa kapalı sayılır; veri yoksa / hata varsa
/// kapalı SAYILMAZ (fail-open).

/// Kapalı modül mesajı (`MODULE_DISABLED` hata kodunun Türkçe karşılığı).
String get moduleDisabledMessage =>
    AuthApi.messageForErrorCode('MODULE_DISABLED') ??
    'Bu özellik şu an kapalı. Site yöneticisi Modüller ekranından açabilir.';

/// Geçiş Kontrol kapalıysa [moduleDisabledMessage], değilse (açık ya da öğrenilemedi) null.
///
/// Önce `AuthService.cachedMyModules` (HomePage'in yoklamasıyla taze tutulur) okunur: ağ isteği
/// yapılmaz. Önbellek yoksa ve [fetch] true ise `getMyModules` kısa zaman aşımıyla denenir.
Future<String?> doorControlClosedMessage(
  AuthService auth, {
  bool fetch = false,
  Duration timeout = const Duration(seconds: 3),
}) async {
  var modules = auth.cachedMyModules;
  if (modules == null && fetch) {
    try {
      modules = await auth.getMyModules().timeout(timeout);
    } catch (_) {
      return null;
    }
  }
  if (modules == null) return null;
  return modules.isDisabledEverywhere(PlatformModuleCodes.doorControl)
      ? moduleDisabledMessage
      : null;
}
