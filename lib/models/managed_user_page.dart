import 'package:site_kapi_kontrol/models/managed_user_account.dart';

class ManagedUserPage {
  const ManagedUserPage({
    required this.users,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  final List<ManagedUserAccount> users;
  final int total;
  final int page;
  final int pageSize;

  ManagedUserPage copyWith({
    List<ManagedUserAccount>? users,
    int? total,
    int? page,
    int? pageSize,
  }) {
    return ManagedUserPage(
      users: users ?? this.users,
      total: total ?? this.total,
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
    );
  }

  int get totalPages {
    if (total <= 0) {
      return 1;
    }
    return ((total - 1) ~/ pageSize) + 1;
  }
}
