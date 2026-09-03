import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/managed_user_account.dart';
import 'package:site_kapi_kontrol/models/managed_user_page.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/styles/app_colors.dart';
import 'package:site_kapi_kontrol/styles/app_decorations.dart';
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
    }
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 680;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: AppDecorations.glassCard,
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _rolePlural(role),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: onOpenAddDialog,
                        icon: const Icon(Icons.person_add_alt_1),
                        label: Text('Yeni ${_roleTitle(role)}'),
                      ),
                    ),
                  ],
                )
              : Row(
                  children: [
                    Expanded(
                      child: Text(
                        _rolePlural(role),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.textDark,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: onOpenAddDialog,
                      icon: const Icon(Icons.person_add_alt_1),
                      label: Text('Yeni ${_roleTitle(role)}'),
                    ),
                  ],
                ),
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: AppDecorations.glassCard,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      pageData == null
                          ? _rolePlural(role)
                          : '${_rolePlural(role)} (${pageData!.total})',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: loading ? null : onRefresh,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (loading && pageData == null)
                const Center(child: CircularProgressIndicator())
              else if (users.isEmpty)
                Text('Kayıtlı ${_rolePlural(role).toLowerCase()} bulunamadı.')
              else ...[
                for (final user in users)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: ManagedUserCard(
                      user: user,
                      isSelf: user.id == session.id,
                      activationBusy: busyActivationUsers.contains(user.id),
                      onActivationChanged: (value) =>
                          onToggleActivation(user, value),
                      onTap: () => onShowUserDetails(user),
                      onDelete: onDeleteUser != null
                          ? () => onDeleteUser!(user)
                          : null,
                    ),
                  ),
                if (pageData != null)
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'Sayfa ${pageData!.page} / ${pageData!.totalPages} | Toplam ${pageData!.total}',
                      ),
                      OutlinedButton(
                        onPressed: pageData!.page > 1
                            ? () => onLoadPage(pageData!.page - 1)
                            : null,
                        child: const Icon(Icons.chevron_left),
                      ),
                      OutlinedButton(
                        onPressed: pageData!.page < pageData!.totalPages
                            ? () => onLoadPage(pageData!.page + 1)
                            : null,
                        child: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

