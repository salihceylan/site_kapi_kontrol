import 'package:flutter/widgets.dart';
import 'package:site_kapi_kontrol/services/locale_service.dart';

enum UserRole {
  superUser(apiValue: 'super_user', label: 'Super User'),
  siteManager(apiValue: 'site_manager', label: 'Site Yoneticisi'),
  apartmentOwner(apiValue: 'apartment_owner', label: 'Daire Kullanicisi'),
  individual(apiValue: 'individual', label: 'Bireysel Kullanici');

  const UserRole({required this.apiValue, required this.label});

  final String apiValue;
  final String label;

  String localizedLabel(BuildContext context) {
    final l = context.l10n;
    switch (this) {
      case UserRole.superUser:
        return l.roleSuperUser;
      case UserRole.siteManager:
        return l.roleSiteManager;
      case UserRole.apartmentOwner:
        return l.roleApartmentOwner;
      case UserRole.individual:
        return l.roleIndividual;
    }
  }

  static UserRole fromApi(String value) {
    return UserRole.values.firstWhere(
      (role) => role.apiValue == value,
      orElse: () => UserRole.apartmentOwner,
    );
  }
}
