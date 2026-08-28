import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/styles/role_theme.dart';

enum SirketMenuItem {
  dashboard,
  profilim,
  ellerSerbest,
  abonelikTalepleri,
  siteOnayTalepleri,
  superUserYonetimi,
  siteYoneticileriYonetimi,
  daireKullanicilariYonetimi,
  siteler,
  cihazEkle,
  kayitliCihazlar,
  bluetoothWifiKur,
}

class YanMenu extends StatelessWidget {
  const YanMenu({
    super.key,
    required this.fullName,
    required this.userEmail,
    required this.role,
    required this.selectedItem,
    required this.onSelect,
    required this.onLogout,
  });

  final String fullName;
  final String userEmail;
  final UserRole role;
  final SirketMenuItem selectedItem;
  final ValueChanged<SirketMenuItem> onSelect;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final roleColor = role.accentColor;
    final items = _itemsForRole(role);
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
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [roleColor, role.lightAccentColor],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.only(topRight: Radius.circular(24)),
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
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  userEmail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    role.label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
              children: [
                for (final item in items) ...[
                  _MenuTile(
                    icon: _iconForItem(item),
                    title: _titleForItem(item),
                    selected: selectedItem == item,
                    color: roleColor,
                    onTap: () => onSelect(item),
                  ),
                  const SizedBox(height: 4),
                ],
                _MenuTile(
                  icon: Icons.logout,
                  title: 'Cikis Yap',
                  selected: false,
                  color: roleColor,
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

List<SirketMenuItem> _itemsForRole(UserRole role) {
  switch (role) {
    case UserRole.superUser:
      return const [
        SirketMenuItem.dashboard,
        SirketMenuItem.profilim,
        SirketMenuItem.ellerSerbest,
        SirketMenuItem.superUserYonetimi,
        SirketMenuItem.siteYoneticileriYonetimi,
        SirketMenuItem.daireKullanicilariYonetimi,
        SirketMenuItem.siteler,
        SirketMenuItem.cihazEkle,
        SirketMenuItem.kayitliCihazlar,
        SirketMenuItem.bluetoothWifiKur,
      ];
    case UserRole.siteManager:
      return const [
        SirketMenuItem.dashboard,
        SirketMenuItem.profilim,
        SirketMenuItem.ellerSerbest,
        SirketMenuItem.siteler,
        SirketMenuItem.kayitliCihazlar,
        SirketMenuItem.bluetoothWifiKur,
      ];
    case UserRole.apartmentOwner:
      return const [
        SirketMenuItem.dashboard,
        SirketMenuItem.profilim,
        SirketMenuItem.ellerSerbest,
      ];
  }
}

String _titleForItem(SirketMenuItem item) {
  switch (item) {
    case SirketMenuItem.dashboard:
      return 'Panel';
    case SirketMenuItem.profilim:
      return 'Profilim';
    case SirketMenuItem.ellerSerbest:
      return 'Eller Serbest & Kestirmeler';
    case SirketMenuItem.abonelikTalepleri:
      return 'Yeni Abonelik Talepleri';
    case SirketMenuItem.siteOnayTalepleri:
      return 'Site Onay Talepleri';
    case SirketMenuItem.superUserYonetimi:
      return 'Super User Yonetimi';
    case SirketMenuItem.siteYoneticileriYonetimi:
      return 'Site Yoneticileri Yonetimi';
    case SirketMenuItem.daireKullanicilariYonetimi:
      return 'Daire Kullanicilari Yonetimi';
    case SirketMenuItem.siteler:
      return 'Site Yonetimi';
    case SirketMenuItem.cihazEkle:
      return 'Sirket Veritabanina Cihaz Kaydet';
    case SirketMenuItem.kayitliCihazlar:
      return 'Kayitli Cihazlar';
    case SirketMenuItem.bluetoothWifiKur:
      return 'Bluetooth ile Wi-Fi Kur';
  }
}

IconData _iconForItem(SirketMenuItem item) {
  switch (item) {
    case SirketMenuItem.dashboard:
      return Icons.home_outlined;
    case SirketMenuItem.profilim:
      return Icons.person_outline;
    case SirketMenuItem.ellerSerbest:
      return Icons.directions_car_outlined;
    case SirketMenuItem.abonelikTalepleri:
      return Icons.mark_email_unread_outlined;
    case SirketMenuItem.siteOnayTalepleri:
      return Icons.approval_outlined;
    case SirketMenuItem.superUserYonetimi:
      return Icons.manage_accounts_outlined;
    case SirketMenuItem.siteYoneticileriYonetimi:
      return Icons.apartment_outlined;
    case SirketMenuItem.daireKullanicilariYonetimi:
      return Icons.groups_2_outlined;
    case SirketMenuItem.siteler:
      return Icons.location_city_outlined;
    case SirketMenuItem.cihazEkle:
      return Icons.qr_code_scanner_outlined;
    case SirketMenuItem.kayitliCihazlar:
      return Icons.devices_other_outlined;
    case SirketMenuItem.bluetoothWifiKur:
      return Icons.bluetooth_searching_outlined;
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.title,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      tileColor: selected ? color.withValues(alpha: 0.1) : null,
      leading: Icon(icon, color: color),
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
