import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/styles/app_colors.dart';

enum SirketMenuItem {
  dashboard,
  profilim,
  superUserYonetimi,
  siteYoneticileriYonetimi,
  daireKullanicilariYonetimi,
}

class YanMenu extends StatelessWidget {
  const YanMenu({
    super.key,
    required this.fullName,
    required this.userEmail,
    required this.selectedItem,
    required this.onSelect,
    required this.onLogout,
  });

  final String fullName;
  final String userEmail;
  final SirketMenuItem selectedItem;
  final ValueChanged<SirketMenuItem> onSelect;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 56, 16, 20),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.primary, AppColors.primaryLight],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.only(topRight: Radius.circular(24)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.25),
                    shape: BoxShape.circle,
                  ),
                  child: const CircleAvatar(
                    radius: 26,
                    backgroundColor: Colors.white,
                    backgroundImage: AssetImage('assets/images/app_logo.png'),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  fullName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  userEmail,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
              children: [
                _MenuTile(
                  icon: Icons.home_outlined,
                  title: 'Panel',
                  selected: selectedItem == SirketMenuItem.dashboard,
                  onTap: () => onSelect(SirketMenuItem.dashboard),
                ),
                const SizedBox(height: 4),
                _MenuTile(
                  icon: Icons.person_outline,
                  title: 'Profilim',
                  selected: selectedItem == SirketMenuItem.profilim,
                  onTap: () => onSelect(SirketMenuItem.profilim),
                ),
                const SizedBox(height: 4),
                _MenuTile(
                  icon: Icons.manage_accounts_outlined,
                  title: 'Super User Yonetimi',
                  selected: selectedItem == SirketMenuItem.superUserYonetimi,
                  onTap: () => onSelect(SirketMenuItem.superUserYonetimi),
                ),
                const SizedBox(height: 4),
                _MenuTile(
                  icon: Icons.apartment_outlined,
                  title: 'Site Yoneticileri Yonetimi',
                  selected: selectedItem == SirketMenuItem.siteYoneticileriYonetimi,
                  onTap: () => onSelect(SirketMenuItem.siteYoneticileriYonetimi),
                ),
                const SizedBox(height: 4),
                _MenuTile(
                  icon: Icons.groups_2_outlined,
                  title: 'Daire Kullanicilari Yonetimi',
                  selected: selectedItem == SirketMenuItem.daireKullanicilariYonetimi,
                  onTap: () => onSelect(SirketMenuItem.daireKullanicilariYonetimi),
                ),
                const SizedBox(height: 4),
                _MenuTile(
                  icon: Icons.logout,
                  title: 'Cikis Yap',
                  selected: false,
                  onTap: onLogout,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.title,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      tileColor: selected ? AppColors.primary.withValues(alpha: 0.1) : null,
      leading: Icon(icon, color: AppColors.primary),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      onTap: onTap,
    );
  }
}
