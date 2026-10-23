import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/services/module_access.dart';

/// Kullanıcı sisteme CİHAZ EKLEYEBİLİR mi? (kutu QR / seri no ile cihaz sahiplenme girişlerinin tek kuralı)
///
/// - Süper kullanıcı ve site yöneticisi: evet (yönetici cihaz satın alıp aktif ettiğinde kapısına bağlayabilir).
/// - Sakin, bireysel kullanıcı, kurul ve görevli: hayır.
bool canAddDevice({required UserRole role, required ModuleAccess access}) {
  if (role == UserRole.superUser || access.isSuper) return true;
  return role == UserRole.siteManager;
}
