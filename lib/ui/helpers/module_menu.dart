import 'package:site_kapi_kontrol/models/platform_module.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/services/module_access.dart';
import 'package:site_kapi_kontrol/ui/widgets/yan_menu.dart';

/// Geçiş Kontrol (`door_control`) modülüne bağlı menü öğeleri: modül kapalıyken gizlenir.
/// "Panel" (dashboard, modül vitrini) kalır; "Kapılar" öğesi (ve vitrindeki kapı kartı / hızlı "Kapıyı aç" eylemi)
/// gizlenir. Süper kullanıcının Kapılar ekranında seçili site kapalıysa "Geçiş Kontrol modülü kapalı" bilgi kartı çıkar.
const Set<SirketMenuItem> doorControlMenuItems = <SirketMenuItem>{
  SirketMenuItem.kapilar,
  SirketMenuItem.kayitliCihazlar,
  SirketMenuItem.bluetoothWifiKur,
  SirketMenuItem.ellerSerbest,
};

/// [role] kullanıcısı için modül durumuna göre menüden gizlenecek öğeler.
///
/// Süper kullanıcıda hiçbir şey gizlenmez. Diğerlerinde kullanıcı en az bir siteye bağlı VE bağlı
/// olduğu TÜM sitelerde `door_control` kapalıysa [doorControlMenuItems] gizlenir. Veri yoksa
/// (fail-open) ya da kullanıcının hiç sitesi yoksa küme boştur: menü eskisi gibidir.
///
/// Daire sakini rolünde ([UserRole.apartmentOwner]) modül verisi YÜKLÜYKEN kapı erişimi olan hiç sitesi yoksa (yalnız
/// görevli / kurul üyeliği ya da yalnız site üyeliği bağı: sunucu `door_access=false` der) VE kapı listesi de boşsa
/// ([hasDoors] false) kapı öğeleri yine gizlenir: kapı açamayan kullanıcıya "Kapılar" kartı, hızlı "Kapıyı aç" ve
/// "Eller Serbest" gösterilmez. Bireysel kullanıcı ("Kapılar" onun bireysel ana ekranının tek yoludur), yönetici ve
/// süper kullanıcı bu kuraldan etkilenmez; modül verisi yokken de değişen bir şey yoktur. Kapı öğeleri gizliyken ana
/// sayfa sesli asistanı da susturur (otomatik dinlemeyi kapatacak "Eller Serbest" yokken "kapı bulunamadı" konuşulmaz).
Set<SirketMenuItem> hiddenMenuItemsFor(
  UserRole role,
  ModuleAccess access, {
  bool hasDoors = false,
}) {
  if (role == UserRole.superUser || access.isSuper) {
    return const <SirketMenuItem>{};
  }
  if (access.isDisabledEverywhere(PlatformModuleCodes.doorControl)) {
    return doorControlMenuItems;
  }
  if (role == UserRole.apartmentOwner &&
      !hasDoors &&
      access.isFiltering &&
      access.result!.doorAccessSites.isEmpty) {
    return doorControlMenuItems;
  }
  return const <SirketMenuItem>{};
}
