import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/config/app_config.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/ui/design/motion_widgets.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

enum SirketMenuItem {
  dashboard,
  profilim,
  ellerSerbest,
  abonelikTalepleri,
  siteOnayTalepleri,
  kullaniciYonetimi,
  superUserYonetimi,
  siteYoneticileriYonetimi,
  daireKullanicilariYonetimi,
  siteler,
  katilimVeKurulum,
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
    this.isResidentMode = false,
    this.onToggleMode,
    this.canToggleMode = false,
  });

  final String fullName;
  final String userEmail;
  final UserRole role;
  final SirketMenuItem selectedItem;
  final ValueChanged<SirketMenuItem> onSelect;
  final VoidCallback onLogout;
  final bool isResidentMode;
  final VoidCallback? onToggleMode;
  final bool canToggleMode;

  /// Bu yüksekliğin altında (yatay telefon, küçük pencere) başlık, liste ve sürüm satırı TEK
  /// kaydırma alanında akar: sabit başlık + sürüm satırı kısa ekranda listeye yer bırakmaz
  /// (en büyük yazıda 56 dp'ye düşerdi) ve Column ekran yüksekliğini aşıp taşabilirdi.
  static const double _compactHeight = 480;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final tone = role.tone;
    final compact = MediaQuery.sizeOf(context).height < _compactHeight;
    final items = _itemsForRole(
      role,
      isResidentMode: isResidentMode,
      canToggleMode: canToggleMode,
    );
    final showToggle = canToggleMode && onToggleMode != null;
    // Çekmece açılışında ilk 8 öğe sırayla belirir (StaggeredEntry): sıra ekrandaki sıradır.
    final firstItemIndex = showToggle ? 1 : 0;

    // Header Alanı (Rol Temalı Gradient)
    final header = _DrawerHeader(
      fullName: fullName,
      userEmail: userEmail,
      role: role,
      compact: compact,
    );

    // Menü Öğeleri Listesi
    final menuList = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showToggle) ...[
          StaggeredEntry(
            key: const ValueKey<String>('yan_menu_gecis'),
            index: 0,
            child: _MenuTile(
              icon: isResidentMode
                  ? Icons.admin_panel_settings_rounded
                  : Icons.home_rounded,
              title: isResidentMode ? 'Yönetici Paneline Geç' : 'Sakin Moduna Geç',
              selected: false,
              tone: isResidentMode ? AppTone.primary : AppTone.success,
              onTap: onToggleMode!,
            ),
          ),
          const _MenuDivider(),
        ],
        for (var i = 0; i < items.length; i++)
          StaggeredEntry(
            key: ValueKey<SirketMenuItem>(items[i]),
            index: firstItemIndex + i,
            child: _MenuTile(
              icon: _iconForItem(items[i]),
              title: _titleForItem(items[i], role),
              selected: selectedItem == items[i],
              tone: tone,
              onTap: () => onSelect(items[i]),
            ),
          ),
        const _MenuDivider(),
        StaggeredEntry(
          key: const ValueKey<String>('yan_menu_cikis'),
          index: firstItemIndex + items.length,
          child: _MenuTile(
            icon: Icons.logout_rounded,
            title: 'Çıkış Yap',
            selected: false,
            tone: AppTone.danger,
            onTap: onLogout,
          ),
        ),
      ],
    );

    // Alt Sürüm Bilgisi
    final version = Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 16),
      child: Center(
        child: Text(
          AppConfig.versionDisplay,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: p.textMuted,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );

    const listPadding = EdgeInsets.symmetric(vertical: 12, horizontal: 10);

    // Yüzey rengi AppTheme.drawerTheme'den gelir (açık beyaz, koyu #0F172A: eski değerlerle aynı).
    return Drawer(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(AppRadius.xl),
          bottomRight: Radius.circular(AppRadius.xl),
        ),
      ),
      child: compact
          ? SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  header,
                  Padding(padding: listPadding, child: menuList),
                  version,
                ],
              ),
            )
          : Column(
              children: [
                header,
                // Liste kısa (en çok 15 satır) ve öğeler State taşır (giriş animasyonu): tembel
                // ListView yerine SingleChildScrollView; kaydırılıp dönülünce animasyon yinelenmez.
                Expanded(
                  child: SingleChildScrollView(
                    padding: listPadding,
                    child: menuList,
                  ),
                ),
                version,
              ],
            ),
    );
  }
}

/// Çekmece başlığı: rol gradyanı (beyaz metin >= 4,5:1), düz beyaz logo halkası, rol rozeti,
/// ad (en çok 2 satır) ve e-posta. Kısa ekranda ([compact]) üst boşluk azalır.
class _DrawerHeader extends StatelessWidget {
  const _DrawerHeader({
    required this.fullName,
    required this.userEmail,
    required this.role,
    required this.compact,
  });

  final String fullName;
  final String userEmail;
  final UserRole role;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(20, compact ? AppSpace.xl : 56, 20, AppSpace.xl),
      decoration: BoxDecoration(
        gradient: role.tone.gradient,
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(AppRadius.xl),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Logo halkası: düz beyaz, gölge yok.
              Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
                child: CircleAvatar(
                  radius: 26,
                  backgroundColor: Colors.white,
                  // 1024x1024 kaynak 52 dp gösterilir: görüntü boyutuna göre küçük çözülür.
                  backgroundImage: ResizeImage(
                    const AssetImage('assets/images/app_logo.png'),
                    width: (52 * MediaQuery.devicePixelRatioOf(context)).ceil(),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      // Gradyan üstünde beyaz %22 zemin beyaz metni ~3,5:1'e düşürür; koyu perde
                      // rozet metnini >= 4,5:1 tutar.
                      color: Colors.black.withValues(alpha: 0.24),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      role.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.lg),
          Text(
            fullName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: textTheme.titleLarge?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: AppSpace.xs),
          Text(
            userEmail,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodyMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

List<SirketMenuItem> _itemsForRole(
  UserRole role, {
  bool isResidentMode = false,
  bool canToggleMode = false,
}) {
  if (canToggleMode && !isResidentMode && (role == UserRole.individual || role == UserRole.apartmentOwner)) {
    return const [
      SirketMenuItem.dashboard,
      SirketMenuItem.profilim,
      SirketMenuItem.siteler,
      SirketMenuItem.kayitliCihazlar,
      SirketMenuItem.katilimVeKurulum,
      SirketMenuItem.bluetoothWifiKur,
    ];
  }
  switch (role) {
    case UserRole.superUser:
      return const [
        SirketMenuItem.dashboard,
        SirketMenuItem.profilim,
        SirketMenuItem.kullaniciYonetimi,
        SirketMenuItem.superUserYonetimi,
        SirketMenuItem.siteYoneticileriYonetimi,
        SirketMenuItem.daireKullanicilariYonetimi,
        SirketMenuItem.siteler,
        SirketMenuItem.katilimVeKurulum,
        SirketMenuItem.cihazEkle,
        SirketMenuItem.kayitliCihazlar,
        SirketMenuItem.bluetoothWifiKur,
      ];
    case UserRole.siteManager:
      if (isResidentMode) {
        return const [
          SirketMenuItem.dashboard,
          SirketMenuItem.katilimVeKurulum,
          SirketMenuItem.profilim,
          SirketMenuItem.ellerSerbest,
        ];
      }
      return const [
        SirketMenuItem.dashboard,
        SirketMenuItem.profilim,
        SirketMenuItem.siteler,
        SirketMenuItem.kayitliCihazlar,
        SirketMenuItem.katilimVeKurulum,
        SirketMenuItem.bluetoothWifiKur,
      ];
    case UserRole.apartmentOwner:
      return const [
        SirketMenuItem.dashboard,
        SirketMenuItem.katilimVeKurulum,
        SirketMenuItem.ellerSerbest,
        SirketMenuItem.profilim,
      ];
    case UserRole.individual:
      return const [
        SirketMenuItem.dashboard,
        SirketMenuItem.katilimVeKurulum,
        SirketMenuItem.profilim,
      ];
  }
}

String _titleForItem(SirketMenuItem item, [UserRole? role]) {
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
    case SirketMenuItem.kullaniciYonetimi:
      return 'Kullanıcı Yönetimi';
    case SirketMenuItem.superUserYonetimi:
      return 'Süper Kullanıcı Yönetimi';
    case SirketMenuItem.siteYoneticileriYonetimi:
      return 'Site Yöneticileri Yönetimi';
    case SirketMenuItem.daireKullanicilariYonetimi:
      return 'Daire Sakinleri';
    case SirketMenuItem.siteler:
      return 'Site Yönetimi';
    case SirketMenuItem.katilimVeKurulum:
      return 'Daireye Katıl & Cihaz Ekle';
    case SirketMenuItem.cihazEkle:
      if (role == UserRole.superUser) return 'Şirket Cihazı Kaydet';
      if (role == UserRole.individual) return 'Yönetici Olarak Cihaz Ekle';
      return 'Cihaz Kaydet';
    case SirketMenuItem.kayitliCihazlar:
      if (role == UserRole.superUser) return 'Şirket Cihaz Envanteri';
      return 'Kayıtlı Cihazlar';
    case SirketMenuItem.bluetoothWifiKur:
      return 'Bluetooth ile Wi-Fi Kur';
  }
}

IconData _iconForItem(SirketMenuItem item) {
  switch (item) {
    case SirketMenuItem.dashboard:
      return Icons.grid_view_rounded;
    case SirketMenuItem.profilim:
      return Icons.account_circle_outlined;
    case SirketMenuItem.ellerSerbest:
      return Icons.directions_car_filled_rounded;
    case SirketMenuItem.abonelikTalepleri:
      return Icons.mark_email_unread_rounded;
    case SirketMenuItem.siteOnayTalepleri:
      return Icons.verified_user_rounded;
    case SirketMenuItem.kullaniciYonetimi:
      return Icons.manage_accounts_rounded;
    case SirketMenuItem.superUserYonetimi:
      return Icons.admin_panel_settings_rounded;
    case SirketMenuItem.siteYoneticileriYonetimi:
      return Icons.apartment_rounded;
    case SirketMenuItem.daireKullanicilariYonetimi:
      return Icons.groups_2_rounded;
    case SirketMenuItem.siteler:
      return Icons.apartment_rounded;
    case SirketMenuItem.katilimVeKurulum:
      return Icons.add_home_work_rounded;
    case SirketMenuItem.cihazEkle:
      return Icons.add_to_photos_rounded;
    case SirketMenuItem.kayitliCihazlar:
      return Icons.devices_other_rounded;
    case SirketMenuItem.bluetoothWifiKur:
      return Icons.bluetooth_searching_rounded;
  }
}

/// Menü grupları arasındaki ince ayırıcı.
class _MenuDivider extends StatelessWidget {
  const _MenuDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: AppSpace.sm,
        horizontal: AppSpace.md,
      ),
      child: Divider(color: context.palette.border, height: 1),
    );
  }
}

/// Menü öğesi: `ListTile` (dokunma >= 48 dp). Seçili = ton zemini (hap) + ton mürekkebi (ikon/
/// başlık kalın) + sağda 4x22 dp çubuk (200 ms; hareket azaltmada anında).
///
/// Hap zemini `ListTile.selectedTileColor` ile DEĞİL, ListTile'ı saran bir `AnimatedContainer` ile
/// çizilir: `selectedTileColor` `Ink` olarak en yakın Material'in katmanına boyanır; öğe
/// `StaggeredEntry`nin `Opacity`si 0 iken (`paintsChild` false) ve kaydırma alanı ayrı bir katman
/// olduğundan o Material sonradan yeniden boyanmaz: hap hiç görünmezdi. Widget katmanındaki zemin
/// öğeyle birlikte solar/kayar ve her zaman çizilir. ListTile kendi saydam Material'ine sarılır:
/// dalga/hover (Ink) hapın ÜSTÜNE, öğenin kendi alt ağacına (Opacity/kaydırma içinde) çizilir ve
/// Flutter'ın "arka plan ink'i gizliyor" denetimi (araya renkli kutu girmesi) tetiklenmez.
class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.title,
    required this.selected,
    required this.tone,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final bool selected;
  final AppTone tone;
  final VoidCallback onTap;

  /// Seçili çubuğun anahtarı (her öğede bir tane; yalnız seçilide yükseklik 22).
  static const Key selectedBarKey = ValueKey<String>('yan_menu_secili_cubuk');

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final ink = tone.ink(p);
    final tint = tone.tint(p);
    final duration = AppMotion.of(context, AppMotion.base);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: AnimatedContainer(
        duration: duration,
        curve: AppMotion.standard,
        decoration: BoxDecoration(
          // Seçili değilken aynı rengin saydamı: geçişte yalnız alfa değişir (siyaha kaymaz).
          color: selected ? tint : tint.withValues(alpha: 0),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: Stack(
            alignment: AlignmentDirectional.centerEnd,
            children: [
              ListTile(
                dense: true,
                selected: selected,
                onTap: onTap,
                selectedColor: ink,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                leading: Icon(
                  icon,
                  size: 22,
                  color: selected ? ink : p.textSecondary,
                ),
                // Başlık kırpılmaz: en büyük yazıda (x2,0) dar çekmecede en çok 3 satıra iner.
                title: Text(
                  title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                    color: selected ? p.text : p.textSecondary,
                  ),
                ),
              ),
              // Çubuk ListTile.trailing yerine üstte çizilir: trailing en az 32 dp yer ayırır ve
              // başlığın genişliğini her öğede daraltırdı (uzun başlıklar gereksiz sarardı).
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 6),
                child: ExcludeSemantics(
                  child: IgnorePointer(
                    child: AnimatedContainer(
                      key: selectedBarKey,
                      duration: duration,
                      curve: AppMotion.standard,
                      width: 4,
                      height: selected ? 22 : 0,
                      decoration: BoxDecoration(
                        color: ink,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
