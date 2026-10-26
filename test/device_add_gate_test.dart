// Cihaz ekleme kuralı (istemci): süper kullanıcı ve site yöneticisi; sakin, bireysel, kurul ve görevli ekleyemez.
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/platform_module.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/services/module_access.dart';
import 'package:site_kapi_kontrol/ui/helpers/device_add_gate.dart';

MySiteModules _site(int code, String role, {required bool doorControl}) => MySiteModules(
      siteCode: code,
      siteName: 'Site $code',
      role: role,
      modules: <String, bool>{PlatformModuleCodes.doorControl: doorControl},
    );

Future<ModuleAccess> _access(List<MySiteModules> sites, {String scope = 'sites'}) async {
  final access = ModuleAccess(fetch: () async => MyModulesResult(scope: scope, sites: sites));
  await access.refresh();
  return access;
}

void main() {
  test('süper kullanıcı mevcut davranışı korur (modül verisinden bağımsız)', () async {
    final access = await _access(const <MySiteModules>[], scope: 'all');
    expect(canAddDevice(role: UserRole.superUser, access: access), isTrue);
  });

  // 2bf1bd4: Geçiş Kontrol yeni sitede varsayılan KAPALI; cihaz kapıya bağlanınca açılır. Bu yüzden istemci modül durumuna
  // bakmaz. Süper kullanıcının modülü AÇIKÇA kapattığı sitede sunucu 403 DEVICE_ADD_FORBIDDEN ile son kapıdır.
  test('site yöneticisi: Geçiş Kontrol kapalı (yeni site varsayılanı) olsa da ekler', () async {
    final open = await _access([_site(1, 'manager', doorControl: false), _site(2, 'manager', doorControl: true)]);
    expect(canAddDevice(role: UserRole.siteManager, access: open), isTrue);
    final closed = await _access([_site(1, 'manager', doorControl: false)]);
    expect(canAddDevice(role: UserRole.siteManager, access: closed), isTrue);
  });

  test('site seçici kapsamı: seçili sitenin modül durumu yöneticinin ekleme hakkını değiştirmez', () async {
    final access = await _access([_site(1, 'manager', doorControl: false), _site(2, 'manager', doorControl: true)]);
    access.setScopeSiteCode(1);
    expect(canAddDevice(role: UserRole.siteManager, access: access), isTrue);
    access.setScopeSiteCode(2);
    expect(canAddDevice(role: UserRole.siteManager, access: access), isTrue);
  });

  test('sakin, bireysel, kurul ve görevli ekleyemez (modül açık olsa bile)', () async {
    for (final role in <String>['resident', 'board_member', 'staff']) {
      final access = await _access([_site(1, role, doorControl: true)]);
      expect(canAddDevice(role: UserRole.apartmentOwner, access: access), isFalse, reason: role);
      expect(canAddDevice(role: UserRole.individual, access: access), isFalse, reason: role);
    }
  });

  test('modül verisi yokken (fail-open) yalnız site yöneticisi rolü yeter; sunucu zaten zorlar', () async {
    final access = ModuleAccess(fetch: () async => throw Exception('ağ yok'));
    await access.refresh();
    expect(access.isLoaded, isFalse);
    expect(canAddDevice(role: UserRole.siteManager, access: access), isTrue);
    expect(canAddDevice(role: UserRole.individual, access: access), isFalse);
    expect(canAddDevice(role: UserRole.apartmentOwner, access: access), isFalse);
  });
}
