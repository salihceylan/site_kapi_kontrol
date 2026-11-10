import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

/// Tüm projede standart olarak kullanılan menülü kart eylem öğesi.
class CardActionItem {
  const CardActionItem({
    required this.label,
    required this.icon,
    required this.onTap,
    this.key,
    this.isDestructive = false,
    this.tone,
    this.enabled = true,
  });

  final Key? key;
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool isDestructive;
  final AppTone? tone;
  final bool enabled;
}

/// Tüm projede sadelik, anlaşılırlık ve hızlı erişim sağlayan
/// Evrensel Menülü Eylem Kartı (Universal Action Card).
///
/// Hick-Hyman ve Fitts yasaları doğrultusunda:
/// - Kart üzerinde buton kalabalığı yaratmaz; sağdaki üç nokta menüsüyle (`⋮`)
///   tüm eylemleri ergonomik ve güvenli bir menüye toplar.
/// - Minimum 48x48 touch target sağlar.
/// - Yatay ve dikey taşma (overflow) yapmayacak esnek metin mimarisine sahiptir.
class AppActionCard extends StatelessWidget {
  const AppActionCard({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.badges,
    this.actions,
    this.inlineActions,
    this.menuKey,
    this.trailing,
    this.content,
    this.onTap,
    this.tone,
    this.accentBar,
    this.selected = false,
    this.padding = const EdgeInsets.all(AppSpace.md),
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget>? badges;
  final List<CardActionItem>? actions;
  final List<Widget>? inlineActions;
  final Key? menuKey;
  final Widget? trailing;
  final Widget? content;
  final VoidCallback? onTap;
  final AppTone? tone;
  final Color? accentBar;
  final bool selected;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final pal = context.palette;

    Widget? menuWidget;
    if (trailing != null) {
      menuWidget = trailing;
    } else if (actions != null && actions!.isNotEmpty) {
      menuWidget = _buildActionMenu(context, actions!);
    }

    return AppCard(
      padding: padding,
      tone: tone,
      accentBar: accentBar,
      selected: selected,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (leading != null) ...[
                leading!,
                const SizedBox(width: AppSpace.md),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: th.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!.trim(),
                        style: th.bodySmall?.copyWith(
                          color: pal.textSecondary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (badges != null && badges!.isNotEmpty) ...[
                      const SizedBox(height: AppSpace.xs),
                      Wrap(
                        spacing: AppSpace.xs,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: badges!,
                      ),
                    ],
                  ],
                ),
              ),
              if (menuWidget != null) ...[
                const SizedBox(width: AppSpace.xs),
                menuWidget,
              ],
            ],
          ),
          if (content != null) ...[
            const SizedBox(height: AppSpace.sm),
            content!,
          ],
          if (inlineActions != null && inlineActions!.isNotEmpty) ...[
            const SizedBox(height: AppSpace.sm),
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: inlineActions!,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionMenu(BuildContext context, List<CardActionItem> items) {
    final pal = context.palette;

    return Theme(
      data: Theme.of(context).copyWith(
        splashFactory: InkRipple.splashFactory,
      ),
      child: PopupMenuButton<int>(
        key: menuKey,
        icon: Icon(
          Icons.more_vert_rounded,
          color: pal.textSecondary,
          size: 20,
        ),
        tooltip: 'Seçenekler',
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        onSelected: (index) {
          if (index >= 0 && index < items.length) {
            items[index].onTap();
          }
        },
        itemBuilder: (context) {
          final entries = <PopupMenuEntry<int>>[];
          for (var i = 0; i < items.length; i++) {
            final item = items[i];
            Color itemColor;
            if (item.isDestructive) {
              itemColor = Colors.red;
            } else if (item.tone == AppTone.warning) {
              itemColor = Colors.orange;
            } else if (item.tone == AppTone.success) {
              itemColor = Colors.green;
            } else {
              itemColor = pal.text;
            }

            entries.add(
              PopupMenuItem<int>(
                key: item.key,
                value: i,
                enabled: item.enabled,
                height: 40,
                child: Row(
                  children: [
                    Icon(item.icon, size: 18, color: itemColor),
                    const SizedBox(width: AppSpace.sm),
                    Expanded(
                      child: Text(
                        item.label,
                        style: TextStyle(
                          color: itemColor,
                          fontWeight: item.isDestructive ? FontWeight.w600 : FontWeight.normal,
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
          return entries;
        },
      ),
    );
  }
}

/// Kart sol başı için yuvarlak veya kare renkli avatar/ikon rozeti.
class CardAvatarIcon extends StatelessWidget {
  const CardAvatarIcon({
    super.key,
    required this.icon,
    this.tone = AppTone.primary,
    this.size = 40,
    this.iconSize = 20,
  });

  final IconData icon;
  final AppTone tone;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;

    switch (tone) {
      case AppTone.primary:
        bg = Theme.of(context).colorScheme.primary.withValues(alpha: 0.12);
        fg = Theme.of(context).colorScheme.primary;
        break;
      case AppTone.warning:
        bg = Colors.orange.withValues(alpha: 0.12);
        fg = Colors.orange;
        break;
      case AppTone.danger:
        bg = Colors.red.withValues(alpha: 0.12);
        fg = Colors.red;
        break;
      case AppTone.success:
        bg = Colors.green.withValues(alpha: 0.12);
        fg = Colors.green;
        break;
      default:
        bg = Colors.grey.withValues(alpha: 0.12);
        fg = Colors.grey.shade700;
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Center(
        child: Icon(icon, size: iconSize, color: fg),
      ),
    );
  }
}
