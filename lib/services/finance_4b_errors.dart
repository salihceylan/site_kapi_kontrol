import 'package:site_kapi_kontrol/services/auth_api.dart';

/// Platform Faz 4b (Finans devamı) sunucu hata kodları -> Türkçe metin (sözleşme: docs/PLATFORM_FINANS_4B.md
/// "Hata kodları"). Bilinmeyen kodda null döner (çağıran sunucunun Türkçe metnine ya da 4a eşlemesine düşer);
/// teknik ifade ve ham kod kullanıcıya gösterilmez.
String? finance4bErrorMessage(
  String? code, {
  int? retryAfterSeconds,
  Map<String, dynamic>? payload,
}) {
  if (code == null) return null;
  final wait = retryAfterSeconds != null
      ? ' ${AuthApi.formatWait(retryAfterSeconds)} sonra tekrar deneyin.'
      : ' Biraz sonra tekrar deneyin.';
  switch (code) {
    // --- Makbuz -----------------------------------------------------------------------------
    case 'RECEIPT_NOT_FOUND':
      return 'Makbuz bulunamadı.';
    case 'PAYMENT_REVERSED':
      return 'Bu ödeme iptal edilmiş; iptal edilmiş ödeme için makbuz düzenlenemez.';
    case 'RECEIPT_ALREADY_CANCELLED':
      return 'Bu makbuz zaten iptal edilmiş. Listeyi yenileyip kontrol edin.';
    case 'RECEIPT_NOT_CANCELLABLE':
      return 'Bu makbuz iptal edilemez. İptal makbuzları iptal edilemez.';
    // --- Gecikme tazminatı ------------------------------------------------------------------
    case 'LATE_FEE_DISABLED':
      return 'Gecikme tazminatı bu site için kapalı. Ayarlar bölümünden açın.';
    case 'LATE_FEE_NOT_CONFIGURED':
      return 'Gecikme tazminatı için ilk hesaplanacak ay (başlangıç ayı) belirlenmemiş. Ayarlar bölümünden seçin.';
    case 'LATE_FEE_PERIOD_NOT_CLOSED':
      return 'Önce ilgili dönemi kapatın. Tazminat yalnızca kapatılmış ay için hesaplanır.';
    case 'LATE_FEE_PERIOD_NOT_ENDED':
      return 'Bu ay henüz bitmedi. Tazminat yalnızca bitmiş ay için hesaplanır.';
    case 'LATE_FEE_PERIOD_NOT_NEXT':
      return 'Tazminat aylar sırayla hesaplanır. Sıradaki ayı seçin.';
    case 'LATE_FEE_ALREADY_POSTED':
      return 'Bu ay için tazminat zaten yazılmış. Değiştirmek için önce son çalıştırmayı iptal edin.';
    case 'LATE_FEE_RUN_NOT_FOUND':
      return 'Tazminat çalıştırması bulunamadı.';
    case 'LATE_FEE_RUN_NOT_VOIDABLE':
      return 'Bu çalıştırma iptal edilemiyor: yalnızca son (aktif) tazminat çalıştırması iptal edilir; başka bir yönetici zaten iptal etmiş olabilir. Listeyi yenileyip kontrol edin.';
    case 'PERIOD_HAS_LATE_FEE_RUN':
      return 'Bu ay yeniden açılamaz: sonraki aylar için tazminat çalıştırması var. Önce çalıştırmayı iptal edin.';
    // --- Kasa / banka -----------------------------------------------------------------------
    case 'NO_ACCOUNT':
      return 'Gider kaydı için bir kasa ya da banka hesabı gerekir. Önce Kasa bölümünden hesap ekleyin.';
    case 'ACCOUNT_NOT_FOUND':
      return 'Hesap bulunamadı.';
    case 'ACCOUNT_INACTIVE':
      return 'Bu hesap pasif; pasif hesaba yeni hareket yazılamaz.';
    case 'ACCOUNT_REQUIRED':
      return 'Bu sitede kasa ya da banka hesabı tanımlı; tahsilat için bir hesap seçin.';
    case 'ACCOUNT_LIMIT':
      return 'En çok 20 hesap tanımlanabilir.';
    case 'ACCOUNT_NAME_TAKEN':
      return 'Bu adla başka bir hesap var. Farklı bir ad seçin.';
    case 'BEFORE_OPENING_DATE':
      return 'Tarih, hesabın açılış tarihinden önce olamaz.';
    case 'TRANSFER_NOT_FOUND':
      return 'Aktarım bulunamadı.';
    case 'TRANSFER_ALREADY_VOIDED':
      return 'Bu aktarım zaten iptal edilmiş. Listeyi yenileyip kontrol edin.';
    case 'RECONCILIATION_STALE':
      return 'Hesap bakiyesi siz bakarken değişti. Güncel bakiyeyi kontrol edip yeniden onaylayın.';
    case 'RECONCILIATION_ORDER':
      return 'Daha yeni tarihli bir mutabakatın düzeltmesi var; bu eski tarih için ayrıca düzeltme yazılamaz. '
          'Önce yeni tarihli mutabakatın düzeltmesini gözden geçirin ya da bu mutabakatı yalnızca kayıt olarak (düzeltmesiz) girin.';
    case 'PERIOD_HAS_UNASSIGNED_PAYMENTS':
      return 'Bu ay kapatılamaz: hesaba eşlenmemiş tahsilatlar var. Kasa bölümündeki "Toplu Eşle" ile eşleyin.';
    // --- Gider ------------------------------------------------------------------------------
    case 'EXPENSE_NOT_FOUND':
      return 'Gider bulunamadı.';
    case 'EXPENSE_ALREADY_VOIDED':
      return 'Bu gider zaten iptal edilmiş. Listeyi yenileyip kontrol edin.';
    case 'DUPLICATE_EXPENSE':
      return 'Aynı gider kısa süre önce kaydedilmiş görünüyor. Önce gider listesini kontrol edin.';
    case 'DUPLICATE_DOCUMENT_NO':
      return 'Bu tedarikçiden aynı belge numarasıyla iptal edilmemiş bir gider zaten var.';
    case 'CATEGORY_NOT_FOUND':
      return 'Gider kategorisi bulunamadı.';
    case 'CATEGORY_INACTIVE':
      return 'Bu gider kategorisi pasif. Başka bir kategori seçin.';
    case 'SUPPLIER_NOT_FOUND':
      return 'Tedarikçi bulunamadı.';
    case 'DOCUMENTS_NOT_AVAILABLE':
      return 'Belge ekleme şu an kullanılamıyor. Gider ek belgesiz kaydedilebilir.';
    case 'EXPENSE_DOCUMENT_LIMIT':
      return 'Bir gidere en çok 5 belge eklenebilir.';
    case 'DOCUMENT_NOT_FOUND':
      return 'Belge bulunamadı.';
    case 'DOCUMENT_TOO_LARGE':
      return 'Dosya çok büyük. Daha küçük bir dosya seçin.';
    case 'DOCUMENT_TYPE_NOT_ALLOWED':
    case 'DOCUMENT_CONTENT_MISMATCH':
      return 'Bu dosya türü kabul edilmiyor. Yalnızca PDF, JPG ve PNG eklenebilir.';
    case 'DOCUMENT_ACTIVE_CONTENT':
      return 'Dosyada çalıştırılabilir içerik bulundu; güvenlik nedeniyle kabul edilmedi.';
    case 'DOCUMENT_QUOTA_EXCEEDED':
      return 'Site belge kotası dolu. Yeni belge eklenemez.';
    case 'UPLOAD_BUSY':
      return 'Yükleme sunucusu şu an meşgul.$wait';
    case 'DOCUMENT_STORAGE_FULL':
    case 'DOCUMENT_STORAGE_NOT_CONFIGURED':
      return 'Belge depolama şu an kullanılamıyor. Gider ek belgesiz kaydedilebilir.';
    // --- Rapor / dışa aktarma ---------------------------------------------------------------
    case 'STATEMENT_TOO_LARGE':
      return 'Ekstre çok uzun (5.000 satırdan fazla). Tarih aralığını daraltın.';
    case 'REPORT_BUSY':
      // Önizleme / rapor yuvası dolu (sunucu 503): kullanıcı beklesin; istemci otomatik kısa yeniden deneme YAPMAZ.
      return retryAfterSeconds != null
          ? 'Yoğunluk var, ${AuthApi.formatWait(retryAfterSeconds)} sonra tekrar deneyin.'
          : 'Yoğunluk var, biraz sonra tekrar deneyin.';
    case 'EXPORT_TOO_LARGE':
      return 'Dışa aktarılacak veri çok büyük (en çok 20.000 satır). Süzgeçlerle daraltın.';
    // --- Hatırlatma -------------------------------------------------------------------------
    case 'REMINDERS_DISABLED':
      return 'Borç hatırlatma bu site için kapalı. Ayarlar bölümünden açın.';
    case 'REMINDER_DAILY_LIMIT':
      return 'Bugün zaten bir hatırlatma gönderildi. Günde en çok bir çalıştırma yapılabilir.';
    case 'NO_REMINDER_RECIPIENTS':
      return 'Hatırlatma gönderilecek kimse bulunamadı.';
    case 'EMAIL_NOT_CONFIGURED':
      return 'E-posta gönderimi yapılandırılmamış; hatırlatma gönderilemez.';
    case 'REMINDER_RUN_NOT_FOUND':
      return 'Hatırlatma çalıştırması bulunamadı.';
    case 'REMINDER_RUN_NOT_CANCELLABLE':
      return 'Bu hatırlatma çalıştırması iptal edilemez (zaten iptal edilmiş).';
    // --- Ayarlar ----------------------------------------------------------------------------
    case 'SETTINGS_STALE':
      return 'Ayarlar başka biri tarafından değiştirilmiş. Güncel ayarlar yüklendi; kontrol edip yeniden kaydedin.';
    case 'LEGAL_APPROVAL_REQUIRED':
      return 'Bu özellik hukuki onay bekliyor; onaylanınca kullanılabilir.';
    default:
      return AuthApi.messageForErrorCode(code, retryAfterSeconds: retryAfterSeconds, payload: payload);
  }
}
