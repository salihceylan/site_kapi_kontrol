import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/managed_user_account.dart';
import 'package:site_kapi_kontrol/models/managed_user_page.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/motion_widgets.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/managed_user_card.dart';

class ManagedUsersView extends StatelessWidget {
  const ManagedUsersView({
    super.key,
    required this.role,
    required this.session,
    required this.pageData,
    required this.users,
    required this.loading,
    required this.busyActivationUsers,
    required this.onRefresh,
    required this.onLoadPage,
    required this.onOpenAddDialog,
    required this.onToggleActivation,
    required this.onShowUserDetails,
    this.onDeleteUser,
  });

  final UserRole role;
  final UserSession session;
  final ManagedUserPage? pageData;
  final List<ManagedUserAccount> users;
  final bool loading;
  final Set<int> busyActivationUsers;
  final VoidCallback onRefresh;
  final ValueChanged<int> onLoadPage;
  final VoidCallback onOpenAddDialog;
  final void Function(ManagedUserAccount user, bool value) onToggleActivation;
  final ValueChanged<ManagedUserAccount> onShowUserDetails;
  final ValueChanged<ManagedUserAccount>? onDeleteUser;

  String _roleTitle(UserRole r) {
    switch (r) {
      case UserRole.superUser:
        return 'Süper Kullanıcı';
      case UserRole.siteManager:
        return 'Site Yöneticisi';
      case UserRole.apartmentOwner:
        return 'Daire Sakini';
      case UserRole.individual:
        return 'Bireysel Kullanıcı';
    }
  }

  String _rolePlural(UserRole r) {
    switch (r) {
      case UserRole.superUser:
        return 'Süper Kullanıcılar';
      case UserRole.siteManager:
        return 'Site Yöneticileri';
      case UserRole.apartmentOwner:
        return 'Daire Sakinleri';
      case UserRole.individual:
        return 'Bireysel Kullanıcılar';
    }
  }

  @override
  Widget build(BuildContext context) {
    final page = pageData;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeaderCard(
          title: _rolePlural(role),
          action: ElevatedButton.icon(
            onPressed: onOpenAddDialog,
            icon: const Icon(Icons.person_add_alt_1),
            label: Text('Yeni ${_roleTitle(role)}'),
          ),
        ),
        const SizedBox(height: AppSpace.lg),
        // Liste bölümü: başlık sayfa zemininde, her kullanıcı kendi AppCard'ı (kart-içinde-kart yok).
        SectionHeader(
          title: page == null
              ? _rolePlural(role)
              : '${_rolePlural(role)} (${page.total})',
          trailing: IconButton(
            onPressed: loading ? null : onRefresh,
            icon: const Icon(Icons.refresh),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        if (loading && page == null)
          const ListSkeleton()
        else if (users.isEmpty)
          EmptyCard(
            icon: Icons.group_outlined,
            title: 'Kayıtlı ${_rolePlural(role).toLowerCase()} bulunamadı.',
          )
        else ...[
          for (var i = 0; i < users.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.md),
              child: StaggeredEntry(
                index: i,
                child: ManagedUserCard(
                  user: users[i],
                  isSelf: users[i].id == session.id,
                  activationBusy: busyActivationUsers.contains(users[i].id),
                  onActivationChanged: (value) =>
                      onToggleActivation(users[i], value),
                  onTap: () => onShowUserDetails(users[i]),
                  onDelete: onDeleteUser != null
                      ? () => onDeleteUser!(users[i])
                      : null,
                ),
              ),
            ),
          if (page != null)
            PaginationBar(
              label:
                  'Sayfa ${page.page} / ${page.totalPages} | Toplam ${page.total}',
              onPrevious: page.page > 1 ? () => onLoadPage(page.page - 1) : null,
              onNext: page.page < page.totalPages
                  ? () => onLoadPage(page.page + 1)
                  : null,
            ),
        ],
      ],
    );
  }
}
