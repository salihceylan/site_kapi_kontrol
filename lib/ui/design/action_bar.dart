import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

/// [AppActionBar] içindeki tek eylem. [primary] true ise dolu (tonun `a` rengi + beyaz metin), değilse tonal
/// (tonun soluk zemini [AppTone.tint] + `ink` metin). Renkler [AppTone] belirteçlerindendir; kontrast sözleşmesi
/// (>= 4,5:1) açık ve koyu temada tokens testiyle doğrulanır.
class AppBarAction {
  const AppBarAction({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.tone = AppTone.info,
    this.primary = false,
    this.actionKey,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final AppTone tone;
  final bool primary;
  final Key? actionKey;
}

/// Ekran düzeyi eylemler için tek tip çubuk: aynı yükseklik (44), yarıçap ve simge boyutu; telefonda iki sütun (eşit
/// genişlik, eşit aralık), geniş ekranda içerik genişliğinde tek hizalı satır (sığmazsa düzgünce sarar).
class AppActionBar extends StatelessWidget {
  const AppActionBar({super.key, required this.actions});

  final List<AppBarAction> actions;

  static const double height = 44;
  static const double _wideBreakpoint = 560;

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, c) {
        final narrow = c.maxWidth < _wideBreakpoint;
        const gap = AppSpace.sm;
        final cols = narrow ? (actions.length == 1 ? 1 : 2) : actions.length;
        final itemW = narrow ? (c.maxWidth - gap * (cols - 1)) / cols : null;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final a in actions)
              SizedBox(
                width: itemW,
                child: _ActionButton(action: a),
              ),
          ],
        );
      },
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.action});

  final AppBarAction action;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = action.tone;
    final enabled = action.onPressed != null;
    final Color bg;
    final Color fg;
    final Color border;
    if (!enabled) {
      bg = p.surfaceMuted;
      fg = p.textSecondary;
      border = p.border;
    } else if (action.primary) {
      bg = t.a;
      fg = Colors.white;
      border = t.a;
    } else {
      bg = Color.alphaBlend(t.tint(p), p.surface);
      fg = t.ink(p);
      border = t.hue.withValues(alpha: p.isDark ? 0.45 : 0.40);
    }
    final radius = BorderRadius.circular(AppRadius.md);
    return Semantics(
      button: true,
      enabled: enabled,
      child: DecoratedBox(
        decoration: BoxDecoration(color: bg, borderRadius: radius, border: Border.all(color: border)),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            key: action.actionKey,
            borderRadius: radius,
            splashColor: fg.withValues(alpha: 0.16),
            highlightColor: fg.withValues(alpha: 0.08),
            onTap: action.onPressed,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppActionBar.height, minWidth: 96),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(action.icon, size: 20, color: fg),
                    const SizedBox(width: AppSpace.sm),
                    Flexible(
                      child: Text(
                        action.label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(color: fg, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Sekme seçici öğesi ([AppChipTabs]).
class AppTabItem {
  const AppTabItem({required this.key, required this.label, required this.icon});

  final Key key;
  final String label;
  final IconData icon;
}

/// Tek tip sekme şeridi: aynı biçimde `ChoiceChip`ler (seçili olan tonun soluk zemini + `ink` metin, öteki yüzey +
/// çerçeve); eşit aralıkla sarar.
class AppChipTabs extends StatelessWidget {
  const AppChipTabs({
    super.key,
    required this.items,
    required this.selected,
    required this.onSelected,
    this.tone = AppTone.primary,
  });

  final List<AppTabItem> items;
  final int selected;
  final ValueChanged<int> onSelected;
  final AppTone tone;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final ink = tone.ink(p);
    return Wrap(
      spacing: AppSpace.sm,
      runSpacing: AppSpace.sm,
      children: [
        for (var i = 0; i < items.length; i++)
          ChoiceChip(
            key: items[i].key,
            avatar: Icon(items[i].icon, size: 18, color: selected == i ? ink : p.textSecondary),
            label: Text(items[i].label),
            labelStyle: TextStyle(color: selected == i ? ink : p.text, fontWeight: FontWeight.w600),
            selected: selected == i,
            showCheckmark: false,
            materialTapTargetSize: MaterialTapTargetSize.padded,
            backgroundColor: p.surface,
            selectedColor: Color.alphaBlend(tone.tint(p), p.surface),
            side: BorderSide(color: selected == i ? tone.hue.withValues(alpha: 0.55) : p.border),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
            onSelected: (_) => onSelected(i),
          ),
      ],
    );
  }
}
