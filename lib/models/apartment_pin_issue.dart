import 'package:site_kapi_kontrol/models/apartment_record.dart';

/// Daire hesabına az önce verilen PIN (oluşturma ya da sıfırlama yanıtı).
///
/// Sunucu PIN'i SAKLAMAZ (KVKK m.12): PIN yalnız bu yanıtta BİR KEZ gelir, ekranda bir kez gösterilir
/// ve hiçbir yerde (yerel depo, günlük, durum) tutulmaz. Unutulursa yönetici PIN'i sıfırlar.
class ApartmentPinIssue {
  const ApartmentPinIssue({
    required this.apartment,
    required this.pinCode,
    required this.credentialsSent,
  });

  final ApartmentRecord apartment;
  final String pinCode;

  /// true: PIN sakinin e-posta adresine gönderildi; false: gönderilemedi; null: e-posta adresi yok
  /// (ya da gönderim istenmedi).
  final bool? credentialsSent;

  /// `{apartment, pin_code?, credentials_sent?}` yanıtından; yanıtta PIN yoksa (mevcut sakin
  /// düzenlemesi) null.
  static ApartmentPinIssue? fromResponse(
    ApartmentRecord apartment,
    Map<String, dynamic> payload,
  ) {
    final raw = payload['pin_code'] ?? apartment.residentPinCode;
    final pin = raw is String ? raw.trim() : '';
    if (pin.isEmpty) return null;
    final sent = payload['credentials_sent'];
    return ApartmentPinIssue(
      apartment: apartment,
      pinCode: pin,
      credentialsSent: sent is bool ? sent : null,
    );
  }
}
