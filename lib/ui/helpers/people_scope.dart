import 'package:flutter/foundation.dart';
import 'package:site_kapi_kontrol/models/management_terms.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';

/// Kişi ve Daire Kayıtları ekranlarının ve pencerelerinin ortak bağlamı (Platform Faz 2a): hangi
/// servis, hangi site ve yazma yetkisi var mı.
///
/// [canWrite] false = kurul üyesi (salt okunur): hiçbir yazma düğmesi çizilmez. Yetkinin tek kaynağı
/// yine sunucudur (yazma 403 `FORBIDDEN_ROLE` döner); bu bayrak yalnız arayüzü sadeleştirir.
@immutable
class PeopleScope {
  const PeopleScope({
    required this.authService,
    required this.siteCode,
    this.siteName = '',
    this.canWrite = false,
    this.terms = ManagementTerms.defaults,
  });

  final AuthService authService;
  final int siteCode;
  final String siteName;
  final bool canWrite;

  /// Yönetim türü terimleri (F9): yalnız başlık / sekme / boş durum metinlerinde kullanılır; iş mantığı ve
  /// API alanları değişmez. Eski sunucuda varsayılan (Daire / Sakin / ...).
  final ManagementTerms terms;
}

/// Site seçicide listelenen site.
@immutable
class PeopleSite {
  const PeopleSite({
    required this.code,
    required this.name,
    this.canWrite = false,
    this.terms = ManagementTerms.defaults,
  });

  final int code;
  final String name;

  /// Yönetici / süper kullanıcı: true; yalnız kurul üyesi olunan sitede false.
  final bool canWrite;

  /// Sitenin yönetim türü terimleri (F9); bilinmiyorsa varsayılan.
  final ManagementTerms terms;

  /// Kullanıcıya görünen site adı. Ad boşsa teknik site KODU gösterilmez ("Site 11" değil).
  String get label => name.trim().isEmpty ? 'İsimsiz site' : name.trim();

  @override
  bool operator ==(Object other) =>
      other is PeopleSite &&
      other.code == code &&
      other.name == name &&
      other.canWrite == canWrite &&
      other.terms == terms;

  @override
  int get hashCode => Object.hash(code, name, canWrite, terms);
}
