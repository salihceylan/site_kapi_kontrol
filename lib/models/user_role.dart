enum UserRole {
  superUser(apiValue: 'super_user', label: 'Super User'),
  siteManager(apiValue: 'site_manager', label: 'Apartman Site Yoneticisi'),
  apartmentOwner(apiValue: 'apartment_owner', label: 'Daire Sahibi');

  const UserRole({required this.apiValue, required this.label});

  final String apiValue;
  final String label;

  static UserRole fromApi(String value) {
    return UserRole.values.firstWhere(
      (role) => role.apiValue == value,
      orElse: () => UserRole.apartmentOwner,
    );
  }
}
