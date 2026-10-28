// Sakin "Yöneticiyi ara" modeli (sunucu: `GET /app/manager-contact`, server/src/modules/team_service.js).
//
// Telefon yöneticinin PROFİLİNDEKİ numaradır; sunucu yalnız site bağı olan oturuma verir. Yanıt savunmacı okunur: eksik / bozuk
// alan "numara yok" sayılır (asla uydurma numara), nesne olmayan satır atlanır.

String? _text(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// Bir sitenin yönetici iletişimi.
class ManagerContact {
  const ManagerContact({
    required this.siteCode,
    required this.siteName,
    this.managerName,
    this.phone,
    this.isSelf = false,
  });

  factory ManagerContact.fromJson(Map<String, dynamic> json) => ManagerContact(
    siteCode: (json['site_code'] as num?)?.toInt() ?? 0,
    siteName: _text(json['site_name']) ?? 'Site',
    managerName: _text(json['manager_name']),
    phone: _text(json['manager_phone']),
    isSelf: json['is_self'] == true,
  );

  /// `{ sites: [...] }` yanıtından liste; `sites` yoksa ya da liste değilse boş.
  static List<ManagerContact> listFromJson(Object? payload) {
    if (payload is! Map) return const <ManagerContact>[];
    final sites = payload['sites'];
    if (sites is! List) return const <ManagerContact>[];
    return <ManagerContact>[
      for (final item in sites)
        if (item is Map) ManagerContact.fromJson(Map<String, dynamic>.from(item)),
    ];
  }

  final int siteCode;
  final String siteName;

  /// Yöneticinin adı (numarası yoksa da bilinebilir); bilinmiyorsa null.
  final String? managerName;

  /// Ham profil telefonu (yalnız gösterim); aranacak biçim için `dialableNumber` kullanılır. Kayıtlı değilse null.
  final String? phone;

  /// Çağıran bu sitenin yöneticisi (sakin modundaki yönetici): kendini aramaz, kutu çizilmez.
  final bool isSelf;
}
