// Hesap silme önizlemesi (docs/PLATFORM_SATISA_HAZIRLIK.md §1.6).
//
// `POST /me/account-deletion/preview` yanıtı:
//   {"can_delete":bool,"blockers":[{"code","message","site_id"?}],"will_remove":["…"],"will_keep":["…"]}
// `POST /me/account-deletion` engel varsa `409 {"code":"ACCOUNT_DELETE_BLOCKED","blockers":[…]}` döner.
//
// Güvenli taraf: yanıt eksik/bozuksa silme AÇILMAZ. `can_delete` yalnız açıkça `true` ve engel listesi
// boşsa true olur (sunucu tutarsız bir yanıt gönderirse kullanıcı yanlışlıkla ilerlemez).

/// Hesap silmeyi engelleyen bir neden (örn. `SUPER_USER`, `LAST_SITE_MANAGER`).
class AccountDeletionBlocker {
  const AccountDeletionBlocker({
    required this.code,
    required this.message,
    this.siteId,
    this.amountMinor,
  });

  /// Makine kodu (`SUPER_USER`, `LAST_SITE_MANAGER`, …); sunucu yeni kod eklerse olduğu gibi gelir.
  final String code;

  /// Kullanıcıya gösterilen metin: sunucu metni; yoksa bilinen kod için Türkçe yedek metin.
  final String message;

  /// Engelin ait olduğu site (varsa).
  final int? siteId;

  /// `OPEN_DEBT` için ödenmemiş borç (kuruş); yoksa null.
  final int? amountMinor;

  /// Bilinen koda göre "ne yapabilirsiniz" yönergesi; bilinmeyen kodda null.
  String? get hint => blockerHint(code);

  factory AccountDeletionBlocker.fromJson(Map<String, dynamic> json) {
    final code = _string(json['code']) ?? 'UNKNOWN';
    final serverMessage = _string(json['message']);
    final rawSite = json['site_id'];
    final siteId = rawSite is num && rawSite.isFinite
        ? rawSite.toInt()
        : (rawSite is String ? int.tryParse(rawSite.trim()) : null);
    final rawAmount = json['amount_minor'];
    final amountMinor = rawAmount is num && rawAmount.isFinite
        ? rawAmount.toInt()
        : (rawAmount is String ? int.tryParse(rawAmount.trim()) : null);
    return AccountDeletionBlocker(
      code: code,
      message: serverMessage ?? blockerFallbackMessage(code),
      siteId: siteId,
      amountMinor: amountMinor,
    );
  }

  /// Sunucu metin göndermediğinde gösterilen yedek metin.
  static String blockerFallbackMessage(String code) {
    switch (code) {
      case 'SUPER_USER':
        return 'Süper kullanıcı hesapları buradan silinemez.';
      case 'LAST_SITE_MANAGER':
        return 'Bir sitenin tek yöneticisisiniz.';
      case 'OPEN_DEBT':
        return 'Ödenmemiş borcunuz var.';
      default:
        return 'Hesabınız şu anda silinemez.';
    }
  }

  /// Bilinen engel kodları için çözüm yönergesi.
  static String? blockerHint(String code) {
    switch (code) {
      case 'SUPER_USER':
        return 'Süper kullanıcı hesabının kaldırılması için başka bir süper kullanıcıyla iletişime geçin.';
      case 'LAST_SITE_MANAGER':
        return 'Devretmek için: Siteler, site, Yöneticiler, Yönetici davet et; davet kabul edilince silebilirsiniz. '
            'Kapatmak için: site kartında Sil; talep süper kullanıcı onayına gider, talep gönderilince hesabınızı silebilirsiniz.';
      case 'OPEN_DEBT':
        return 'Borcunuz kapanınca hesabınızı silebilirsiniz. Ödeme bilgisi Borcum sayfasındadır; '
            'gönderdiğiniz dekont onaylanınca borç kapanır. Kişisel verilerinizle ilgili başvurunuzu site yönetimine yapabilirsiniz.';
      default:
        return null;
    }
  }
}

/// Hesap silme önizlemesi: ne silinecek, ne kalacak ve silmeyi engelleyen nedenler.
class AccountDeletionPreview {
  const AccountDeletionPreview({
    required this.canDelete,
    this.blockers = const <AccountDeletionBlocker>[],
    this.willRemove = const <String>[],
    this.willKeep = const <String>[],
  });

  /// Silmeye ilerlenebilir mi. Engel varsa daima false.
  final bool canDelete;
  final List<AccountDeletionBlocker> blockers;
  final List<String> willRemove;
  final List<String> willKeep;

  factory AccountDeletionPreview.fromJson(Map<String, dynamic> json) {
    final blockers = parseBlockers(json['blockers']);
    return AccountDeletionPreview(
      canDelete: json['can_delete'] == true && blockers.isEmpty,
      blockers: blockers,
      willRemove: _strings(json['will_remove']),
      willKeep: _strings(json['will_keep']),
    );
  }

  /// `409 ACCOUNT_DELETE_BLOCKED` gövdesindeki (ya da önizlemedeki) engel listesi; bozuk öğeler atlanır.
  static List<AccountDeletionBlocker> parseBlockers(Object? raw) {
    if (raw is! List) return const <AccountDeletionBlocker>[];
    return <AccountDeletionBlocker>[
      for (final item in raw)
        if (item is Map) AccountDeletionBlocker.fromJson(Map<String, dynamic>.from(item)),
    ];
  }
}

String? _string(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

List<String> _strings(Object? raw) {
  if (raw is! List) return const <String>[];
  return <String>[
    for (final item in raw)
      if (item is String && item.trim().isNotEmpty) item.trim(),
  ];
}
