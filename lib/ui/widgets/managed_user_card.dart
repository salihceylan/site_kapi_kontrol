import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/managed_user_account.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/icon_orb.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/ui_helpers.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

/// Rol simgesi: yan menüdeki rol simgeleriyle aynı dil (süper = yetkili yönetici, yönetici = site,
/// sakin = ev, bireysel = kişi).
IconData userRoleIcon(UserRole role) => switch (role) {
  UserRole.superUser => Icons.admin_panel_settings_rounded,
  UserRole.siteManager => Icons.apartment_rounded,
  UserRole.apartmentOwner => Icons.home_rounded,
  UserRole.individual => Icons.person_rounded,
};

/// Rozetlerin ([StatusChip]) düz metne dönmesi gereken durum: dar ekran (< 340 dp) ya da büyük yazı
/// (> 1,3x). [StatusChip] etiketi tek satır + elips olduğundan bu durumlarda uzun rol adı
/// ("Bireysel Kullanici") kırpılırdı.
bool badgesAsText(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(1) > 1.3 ||
    MediaQuery.sizeOf(context).width < 340;

/// Kullanıcı avatarı: rol tonunda cilalı daire rozet ([IconOrb], rol simgesiyle). Ton rolü anlatır
/// (süper = mavi, yönetici = yeşil, sakin/bireysel = mor): her satıra ayrı vurgu değil, anlam taşır.
///
/// Dekoratiftir (anlamsal ağaçta yok: rolü yanındaki rozet söyler). Sabit dp boyutludur; büyük
/// yazıda (>= 1,75x) metne yer kalsın diye [gap] ile birlikte gizlenir (eski baş harf avatarıyla aynı).
class UserRoleOrb extends StatelessWidget {
  const UserRoleOrb({
    super.key,
    required this.role,
    this.size = 40,
    this.glow = false,
    this.gap = 0,
  });

  final UserRole role;

  /// Çap (dp): liste satırı 40, hero 56-72.
  final double size;

  /// true: tonun glow gölgesi (yalnız hero/başlık kullanımında).
  final bool glow;

  /// Rozetin sağındaki boşluk (rozetle birlikte gizlenir).
  final double gap;

  @override
  Widget build(BuildContext context) {
    if (isLargeText(context)) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(right: gap),
      child: IconOrb(
        icon: userRoleIcon(role),
        tone: role.tone,
        size: size,
        glow: glow,
      ),
    );
  }
}

/// Rol / durum rozeti: normalde [StatusChip]; dar ekran ya da büyük yazıda ([badgesAsText]) aynı
/// tonda, sarmalanan düz metin (etiket hiçbir zaman kırpılmaz). Metin her iki durumda da aynıdır.
class UserBadge extends StatelessWidget {
  const UserBadge({super.key, required this.label, required this.tone});

  final String label;
  final AppTone tone;

  @override
  Widget build(BuildContext context) {
    if (!badgesAsText(context)) return StatusChip(label: label, tone: tone);
    return Text(
      label,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        fontWeight: FontWeight.w700,
        color: tone.ink(context.palette),
      ),
    );
  }
}

/// Bir kullanıcının rol ve aktiflik rozetleri (rol tonunda rol, "Aktif" = success, "Pasif" = nötr).
/// Sığmayan rozet alta iner ([Wrap]); üst öğe sınırlı genişlikte olmalıdır.
///
/// [showActive] false ise aktiflik rozeti yalnız hesap PASİFSE gösterilir: etkinleştirme anahtarının
/// zaten yanında durduğu kartta ("Aktif" anahtarla aynı şeyi söyler) başlık sütunu sığsın diye.
class UserBadges extends StatelessWidget {
  const UserBadges({super.key, required this.user, this.showActive = true});

  final ManagedUserAccount user;
  final bool showActive;

  @override
  Widget build(BuildContext context) {
    final active = user.isActive;
    return Wrap(
      spacing: AppSpace.sm,
      runSpacing: AppSpace.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        UserBadge(label: user.role.label, tone: user.role.tone),
        if (showActive || !active)
          UserBadge(
            label: active ? 'Aktif' : 'Pasif',
            tone: active ? AppTone.success : AppTone.neutral,
          ),
      ],
    );
  }
}

class ManagedUserCard extends StatefulWidget {
  const ManagedUserCard({
    super.key,
    required this.user,
    required this.isSelf,
    required this.activationBusy,
    required this.onTap,
    required this.onActivationChanged,
    this.onDelete,
  });

  final ManagedUserAccount user;
  final bool isSelf;
  final bool activationBusy;
  final VoidCallback onTap;
  final ValueChanged<bool> onActivationChanged;
  final VoidCallback? onDelete;

  @override
  State<ManagedUserCard> createState() => _ManagedUserCardState();
}

class _ManagedUserCardState extends State<ManagedUserCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final user = widget.user;

    // Avatar rozeti rol tonu (süper = mavi, yönetici = yeşil, sakin/bireysel = mor); pasif hesap nötr
    // tonlu kart (önceki sürümde pasif = gri kenar). Tek yüzey: kart AppCard'dır.
    return AppCard(
      tone: user.isActive ? null : AppTone.neutral,
      padding: listCardPadding(context),
      onTap: () => setState(() => _expanded = !_expanded),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(expanded: _expanded), // Açık/kapalı durumu ekran okuyucuya bildirir (karta birleşir).
          Row(
            children: [
              UserRoleOrb(role: user.role, gap: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      user.fullName,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: th.titleMedium,
                    ),
                    const SizedBox(height: AppSpace.xs),
                    // Anahtar aktifliği zaten gösterir: "Pasif" rozeti yalnız pasif hesapta.
                    UserBadges(user: user, showActive: false),
                  ],
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              widget.activationBusy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Switch.adaptive(
                      value: user.isActive,
                      activeThumbColor: AppTone.primary.a,
                      onChanged: widget.isSelf
                          ? null
                          : widget.onActivationChanged,
                    ),
              ExpandChevron(expanded: _expanded),
            ],
          ),
          ExpandableSection(
            expanded: _expanded,
            child: _buildDetails(context),
          ),
        ],
      ),
    );
  }

  Widget _buildDetails(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final user = widget.user;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpace.md),
        const Divider(),
        const SizedBox(height: AppSpace.md),
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          children: [
            InfoChip('Kullanıcı ID: ${user.id}'),
            InfoChip('E-posta: ${user.email}'),
            if ((user.phoneNumber ?? '').isNotEmpty)
              InfoChip('Telefon: ${user.phoneNumber}'),
          ],
        ),
        const SizedBox(height: AppSpace.sm),
        // Tonlu (pasif) kartta textMuted soluk zeminde 4,5:1'in altına düşer: ikincil metin kullanılır.
        Text(
          'Kayıt: ${formatDateTime(user.createdAt)}',
          style: th.bodySmall?.copyWith(color: p.textSecondary),
        ),
        const SizedBox(height: AppSpace.md),
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          children: [
            ElevatedButton.icon(
              onPressed: widget.onTap,
              style: tonalActionStyle(context),
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Düzenle'),
            ),
            if (!widget.isSelf && widget.onDelete != null)
              OutlinedButton.icon(
                onPressed: widget.onDelete,
                style: dangerOutlineStyle(context),
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('Sil'),
              ),
          ],
        ),
      ],
    );
  }
}
