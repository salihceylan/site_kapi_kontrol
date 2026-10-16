import 'package:site_kapi_kontrol/models/finance.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';

/// Mali yazma hatalarının ortak yardımcıları (Platform Faz 4a).

/// Mali akışlarda kullanıcıya gösterilecek hata metni: sunucu Türkçe bir metin verdiyse o; sunucu metin
/// vermediyse (mesaj yalnız "İşlem başarısız (502)" gibi teknik yedekse), ağ / ayrıştırma hatasıysa ya da mesaj
/// boşsa bağlama uygun Türkçe [fallback]. Durum kodu ve hata numarası kullanıcıya gösterilmez.
String financeMessageOf(Object error, String fallback) {
  if (error is ApiException && !error.genericFallback && error.message.trim().isNotEmpty) {
    return error.message;
  }
  return fallback;
}

/// İstek sunucuya ulaşmış olabilir mi (sonuç BELİRSİZ)? Ağ / zaman aşımı (durum kodu yok), 5xx ya da araya
/// giren katman. 4xx hatalar kesin reddir: kayıt oluşmamıştır.
bool financeOutcomeUncertain(Object error) {
  if (error is! ApiException) return true;
  if (error.fromIntermediary) return true;
  return error.statusCode == null || error.isServerError;
}

/// Sonucu belirsiz İDEMPOTENT yazma (tahsilat, iptal, düzeltme, borçlandırma) için eklenen açıklama: aynı
/// `idempotency_key` ile yeniden deneme çift kayıt yaratmaz.
const String kFinanceUncertainHint =
    'Kayıt oluşmuş olabilir. Aynı bilgilerle tekrar denerseniz çift kayıt oluşmaz.';

/// Sonucu belirsiz TANIM EKLEME için: sözleşmede tanım oluşturmada işlem anahtarı YOKTUR, yeniden deneme
/// çift tanım yaratabilir; bu yüzden önce liste kontrol ettirilir.
const String kFinanceUncertainDefinitionHint =
    'Tanım oluşmuş olabilir. Tekrar denemeden önce Tanımlar listesini yenileyip kontrol edin.';

/// Sonucu belirsiz DURUM değişikliği (ay kapatma / açma, tanımı pasifleştirme) için: durum yeniden okunur.
const String kFinanceUncertainStateHint = 'İşlem tamamlanmış olabilir; güncel durum yeniden okunuyor.';

/// Yazma hatasının kullanıcı metni: sunucu metni (Türkçe eşlenmiş) ya da [fallback]; sonuç belirsizse
/// [hint] eklenir (varsayılan: idempotent yazma ipucu).
String financeWriteMessage(Object error, String fallback, {String hint = kFinanceUncertainHint}) {
  final base = financeMessageOf(error, fallback);
  if (!financeOutcomeUncertain(error)) return base;
  final trimmed = base.endsWith('.') ? base : '$base.';
  return '$trimmed $hint';
}

/// Modül kapalı mı (403 `MODULE_DISABLED`)?
bool isFinanceModuleDisabled(Object error) =>
    error is ApiException && error.code == 'MODULE_DISABLED';

/// Hata kodu [code] mu?
bool hasErrorCode(Object error, String code) => error is ApiException && error.code == code;

/// 409 `PREVIEW_STALE` yanıtındaki güncel toplam / sayı / içerik özeti; hata başka bir hataysa null.
PreviewStaleInfo? previewStaleInfoOf(Object error) {
  if (!hasErrorCode(error, 'PREVIEW_STALE')) return null;
  return PreviewStaleInfo.fromPayload((error as ApiException).payload);
}

/// 409 `DUPLICATE_CHARGE` yanıtındaki önceki kayıt bilgisi; hata başka bir hataysa null.
DuplicateChargeInfo? duplicateChargeInfoOf(Object error) {
  if (!hasErrorCode(error, 'DUPLICATE_CHARGE')) return null;
  return DuplicateChargeInfo.fromPayload((error as ApiException).payload);
}
