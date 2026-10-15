import 'package:site_kapi_kontrol/models/platform_module.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/services/module_access.dart';
import 'package:site_kapi_kontrol/ui/widgets/yan_menu.dart';

/// Geçiş Kontrol (`door_control`) modülüne bağlı menü öğeleri: modül kapalıyken gizlenir.
/// "Panel" (dashboard) kalır; kapı kartları yerine "Geçiş Kontrol modülü kapalı" bilgi kartı gösterilir.
const Set<SirketMenuItem> doorControlMenuItems = <SirketMenuItem>{
  SirketMenuItem.kayitliCihazlar,
  SirketMenuItem.bluetoothWifiKur,
  SirketMenuItem.ellerSerbest,
};

/// [role] kullanıcısı için modül durumuna göre menüden gizlenecek öğeler.
///
/// Süper kullanıcıda hiçbir şey gizlenmez. Diğerlerinde kullanıcı en az bir siteye bağlı VE bağlı
/// olduğu TÜM sitelerde `door_control` kapalıysa [doorControlMenuItems] gizlenir. Veri yoksa
/// (fail-open) ya da kullanıcının hiç sitesi yoksa küme boştur: menü eskisi gibidir.
Set<SirketMenuItem> hiddenMenuItemsFor(UserRole role, ModuleAccess access) {
  if (role == UserRole.superUser || access.isSuper) {
    return const <SirketMenuItem>{};
  }
  if (access.isDisabledEverywhere(PlatformModuleCodes.doorControl)) {
    return doorControlMenuItems;
  }
  return const <SirketMenuItem>{};
}
