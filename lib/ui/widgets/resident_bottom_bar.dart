import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/resident_tabs.dart';

/// İP-1D / G3: daire sakini alt çubuğu (Material 3 [NavigationBar]): Özet · Duyuru · Arıza · Kapı · Dosyalar.
///
/// - Sekmeler ([tabs]) çağıranın görünür menüsünden türetilir (`residentTabsFor`); burada görünürlük kuralı yoktur.
/// - [selected] listede yoksa ilk sekme (Özet) işaretlidir. Seçili sekmeye dokunmak da [onSelect]'i çağırır (örn. Özet
///   altındaki bir sayfadan Özet'e dönüş).
/// - Etiketler yazı ölçeğiyle büyümez: Material zaten 1,3 ile sınırlar; beş sekme 320 dp'de taşmasın diye 1,0. Anlam
///   simge + ekran okuyucu etiketindedir (her sekme tek düğüm, "Sekme 2 / 5").
/// - Rozet ([badges], örn. okunmamış duyuru) çekmecedeki rozetle aynı belirteçtir ([AppTone.danger] `a`, beyaz sayı);
///   ekran okuyucu sayıyı "3 okunmamış" diye okur ([badgeNouns], verilmezse "bekleyen").
/// - Renkler palet belirteçlerindendir (zemin [AppPalette.surface], üst çizgi [AppPalette.border], seçili gösterge rol
///   tonunun açık zemini); metin palet sözleşmesiyle >= 4,5:1.
class ResidentBottomBar extends StatelessWidget {
  const ResidentBottomBar({
    super.key,
    required this.tabs,
    required this.selected,
    required this.onSelect,
    required this.tone,
    this.badges = const <ResidentTab, int>{},
    this.badgeNouns = const <ResidentTab, String>{ResidentTab.duyuru: 'okunmamış'},
  });

  final List<ResidentTab> tabs;
  final ResidentTab selected;
  final ValueChanged<ResidentTab> onSelect;

  /// Seçili göstergenin ve seçili simgenin tonu (rol tonu).
  final AppTone tone;

  final Map<ResidentTab, int> badges;
  final Map<ResidentTab, String> badgeNouns;

  Widget _icon(BuildContext context, ResidentTab tab, {required bool selected}) {
    final p = context.palette;
    final icon = Icon(
      selected ? tab.selectedIcon : tab.icon,
      color: selected ? tone.ink(p) : p.textSecondary,
    );
    final count = badges[tab] ?? 0;
    if (count <= 0) return icon;
    return Semantics(
      label: '$count ${badgeNouns[tab] ?? 'bekleyen'}',
      child: ExcludeSemantics(
        child: Badge(
          key: ValueKey<String>('sakin_sekme_rozet_${tab.name}'),
          backgroundColor: AppTone.danger.a,
          textColor: Colors.white,
          label: Text(count > 99 ? '99+' : '$count'),
          child: icon,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final index = tabs.indexOf(selected);
    final labelStyle = Theme.of(context).textTheme.labelMedium;
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.0,
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(border: Border(top: BorderSide(color: p.border))),
        child: NavigationBar(
          key: const ValueKey<String>('sakin_alt_cubuk'),
          selectedIndex: index < 0 ? 0 : index,
          onDestinationSelected: (i) => onSelect(tabs[i]),
          backgroundColor: p.surface,
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.transparent,
          elevation: 0,
          indicatorColor: tone.tint(p),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            final on = states.contains(WidgetState.selected);
            return labelStyle?.copyWith(
              color: on ? p.text : p.textSecondary,
              fontWeight: on ? FontWeight.w700 : FontWeight.w500,
            );
          }),
          destinations: <Widget>[
            for (final tab in tabs)
              NavigationDestination(
                key: ValueKey<String>('sakin_sekme_${tab.name}'),
                icon: _icon(context, tab, selected: false),
                selectedIcon: _icon(context, tab, selected: true),
                label: tab.label,
              ),
          ],
        ),
      ),
    );
  }
}
