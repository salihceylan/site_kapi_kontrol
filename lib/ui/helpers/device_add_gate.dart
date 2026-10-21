import 'package:site_kapi_kontrol/models/platform_module.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/services/module_access.dart';

/// Kullanıcı sisteme CİHAZ EKLEYEBİLİR mi? (kutu QR / seri no ile cihaz sahiplenme girişlerinin tek kuralı)
///
/// - Süper kullanıcı: mevcut davranışı korur (her zaman evet).
/// - Site yöneticisi: yalnız Geçiş Kontrol ([PlatformModuleCodes.doorControl]) modülü AÇIK bir sitenin yöneticisiyse. Site seçici
///   bir site seçiliyse ([ModuleAccess.scopeSiteCode]) yalnız o site değerlendirilir.
/// - Sakin, bireysel kullanıcı, kurul ve görevli: hayır.
///
/// Modül verisi henüz yokken (ilk yükleme başarısız; fail-open) yalnız site yöneticisi rolü yeter: sunucu kuralı zaten zorlar
/// (`POST /membership/claim-device` 403). Mevcut kayıtlı cihazlar ve kapı açma bu kuraldan etkilenmez.
bool canAddDevice({required UserRole role, required ModuleAccess access}) {
  if (role == UserRole.superUser || access.isSuper) return true;
  if (!access.isFiltering) return role == UserRole.siteManager;
  final result = access.result;
  if (result == null) return role == UserRole.siteManager;
  return result.sites.any(
    (site) => site.role == 'manager' && site.isEnabled(PlatformModuleCodes.doorControl),
  );
}
