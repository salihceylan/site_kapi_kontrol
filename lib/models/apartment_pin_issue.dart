import 'package:site_kapi_kontrol/models/apartment_record.dart';

/// Daire hesabına az önce verilen PIN (oluşturma ya da sıfırlama yanıtı).
///
/// Sunucu PIN'i SAKLAMAZ (KVKK m.12): PIN yalnız bu yanıtta BİR KEZ gelir, ekranda bir kez gösterilir
/// ve hiçbir yerde (yerel depo, günlük, durum) tutulmaz. Unutulursa yönetici PIN'i sıfırlar.
///
/// Sakin parolasını KENDİSİ belirlemişse yöneticinin sıfırlaması PIN'i ekrana getirmez
/// ([emailOnly]: yeni PIN yalnız sakinin e-posta adresine gider; [pinCode] null).
class ApartmentPinIssue {
  const ApartmentPinIssue({
    required this.apartment,
    required this.pinCode,
    required this.credentialsSent,
    this.credentialsEmail,
    this.emailOnly = false,
  });

  final ApartmentRecord apartment;

  /// Bir kez gösterilecek PIN; [emailOnly] ise null.
  final String? pinCode;

  /// true: PIN e-postayla gönderildi; false: gönderilemedi; null: [credentialsEmail] doluysa gönderim
  /// sürüyor (sunucu beklemeden yanıtladı), boşsa e-posta adresi yok.
  final bool? credentialsSent;

  /// PIN'in gönderildiği / gönderilmekte olduğu adres (yoksa null).
  final String? credentialsEmail;

  /// Sakinin kendi parolası sıfırlandı: PIN yalnız sakinin e-postasına gitti, ekranda gösterilmez.
  final bool emailOnly;

  /// `{apartment, pin_code?, pin_delivery?, credentials_sent?, credentials_email?}` yanıtından; yanıtta PIN
  /// yoksa ve teslim yalnız e-posta değilse (mevcut sakin düzenlemesi) null.
  static ApartmentPinIssue? fromResponse(
    ApartmentRecord apartment,
    Map<String, dynamic> payload,
  ) {
    final raw = payload['pin_code'] ?? apartment.residentPinCode;
    final pin = raw is String ? raw.trim() : '';
    final emailOnly = payload['pin_delivery'] == 'email_only';
    if (pin.isEmpty && !emailOnly) return null;
    final sent = payload['credentials_sent'];
    final email = payload['credentials_email'];
    return ApartmentPinIssue(
      apartment: apartment,
      pinCode: emailOnly || pin.isEmpty ? null : pin,
      credentialsSent: sent is bool ? sent : null,
      credentialsEmail: email is String && email.trim().isNotEmpty
          ? email.trim()
          : null,
      emailOnly: emailOnly,
    );
  }
}
