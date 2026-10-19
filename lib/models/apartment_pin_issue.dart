import 'package:site_kapi_kontrol/models/apartment_record.dart';

/// Daire hesabına az önce verilen PIN (oluşturma ya da sıfırlama yanıtı).
///
/// Sunucu PIN'i SAKLAMAZ (KVKK m.12): PIN yalnız bu yanıtta BİR KEZ gelir, ekranda bir kez gösterilir
/// ve hiçbir yerde (yerel depo, günlük, durum) tutulmaz. Unutulursa PIN sıfırlanır (sakin şifresini
/// kendisi belirlemişse yalnız süper kullanıcı).
class ApartmentPinIssue {
  const ApartmentPinIssue({
    required this.apartment,
    required this.pinCode,
    required this.credentialsSent,
    this.credentialsEmail,
  });

  final ApartmentRecord apartment;

  /// Bir kez gösterilecek PIN.
  final String pinCode;

  /// true: PIN e-postayla gönderildi; false: gönderilemedi; null: [credentialsEmail] doluysa gönderim
  /// sürüyor (sunucu beklemeden yanıtladı), boşsa e-posta adresi yok.
  final bool? credentialsSent;

  /// PIN'in gönderildiği / gönderilmekte olduğu adres (yoksa null).
  final String? credentialsEmail;

  /// `{apartment, pin_code?, credentials_sent?, credentials_email?}` yanıtından; yanıtta PIN yoksa
  /// (mevcut sakin düzenlemesi) null.
  static ApartmentPinIssue? fromResponse(
    ApartmentRecord apartment,
    Map<String, dynamic> payload,
  ) {
    final raw = payload['pin_code'] ?? apartment.residentPinCode;
    final pin = raw is String ? raw.trim() : '';
    if (pin.isEmpty) return null;
    final sent = payload['credentials_sent'];
    final email = payload['credentials_email'];
    return ApartmentPinIssue(
      apartment: apartment,
      pinCode: pin,
      credentialsSent: sent is bool ? sent : null,
      credentialsEmail: email is String && email.trim().isNotEmpty
          ? email.trim()
          : null,
    );
  }
}
