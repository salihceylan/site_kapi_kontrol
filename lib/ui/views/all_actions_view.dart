import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/icon_orb.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/menu_layout.dart';
import 'package:site_kapi_kontrol/ui/helpers/module_showcase.dart' show showcaseDescription;
import 'package:site_kapi_kontrol/ui/views/legal_parts.dart' show wrappedTitleStyle, wrappedTitleToolbarHeight;
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart' show EmptyCard;
import 'package:site_kapi_kontrol/ui/widgets/yan_menu.dart';

/// "Tüm işlemler" (K8, P1-16): kullanıcının görebildiği BÜTÜN işlemlerin kategorili, aramalı tam listesi.
///
/// YETENEK ile MENÜ YERLEŞİMİ ayrı katmandır: ana menü (çekmece + Panel vitrini) site yöneticisinin seçtiği kompakt kümeyi gösterir; bu
/// ekran ise kümeden BAĞIMSIZ olarak [items] içindeki her öğeyi listeler. Kompakt menüde olmayan bir işlem kaybolmaz, buradan açılır.
/// Çekmecede her zaman erişilir. [featured] yalnız "Ana menüde" işaretini ve üstteki özet metnini belirler; listeyi KISALTMAZ.
///
/// Öğe seçmek, çekmeceden seçmekle AYNI gezinmedir: ekran kapanır, sonra [onOpen] çağrılır. Dokunma hedefleri >= 48 dp; 320 dp'de ve 2,0x
/// yazı ölçeğinde taşma yoktur (metinler sarar). Arama Türkçe katlama yapar ("anket" = "ANKET", "gorev" = "görev").
class AllActionsView extends StatefulWidget {
  const AllActionsView({
    super.key,
    required this.role,
    required this.items,
    required this.onOpen,
    this.featured,
    this.badgeCounts = const <SirketMenuItem, int>{},
    this.badgeNouns = const <SirketMenuItem, String>{},
    this.onEditMenuLayout,
    this.onRefresh,
  });

  final UserRole role;

  /// Görünür TÜM öğeler (`YanMenu.visibleItems`); Panel listelenmez.
  final List<SirketMenuItem> items;

  /// Kompakt menüde öne çıkan öğeler (null: kompakt menü yok, işaret çıkmaz).
  final Set<SirketMenuItem>? featured;

  final Map<SirketMenuItem, int> badgeCounts;
  final Map<SirketMenuItem, String> badgeNouns;

  /// Öğe seçildi (ekran kapandıktan sonra çağrılır).
  final ValueChanged<SirketMenuItem> onOpen;

  /// Verilirse (site yöneticisi) üstte "Ana menüyü düzenle" düğmesi çıkar.
  final VoidCallback? onEditMenuLayout;

  /// Verilirse aşağı çekip yenileme açılır (modül durumu sunucudan yeniden okunur; liste kendiliğinden güncellenir).
  final Future<void> Function()? onRefresh;

  /// Ekranı yeni sayfa olarak açar. [builder] her yenilemede güncel ekranı kurar (örn. modül durumu değişince liste tazelenir).
  static Future<void> open(BuildContext context, WidgetBuilder builder) =>
      Navigator.of(context).push<void>(MaterialPageRoute<void>(builder: builder));

  @override
  State<AllActionsView> createState() => AllActionsViewState();
}

class AllActionsViewState extends State<AllActionsView> {
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _setQuery(String value) => setState(() => _query = value);

  void _clear() {
    _search.clear();
    setState(() => _query = '');
  }

  void _choose(SirketMenuItem item) {
    Navigator.of(context).pop();
    widget.onOpen(item);
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final hPad = MediaQuery.sizeOf(context).width < 400 ? AppSpace.md : AppSpace.lg;
    final all = allActionsSections(widget.items);
    final sections = filterAllActions(
      sections: all,
      query: _query,
      titleOf: (item) => YanMenu.titleFor(item, widget.role),
      descriptionOf: (item) => showcaseDescription(item, widget.role),
    );
    final total = all.fold<int>(0, (sum, section) => sum + section.items.length);
    final beyond = YanMenu.itemsBeyondCompact(widget.items, widget.featured);
    final refresh = widget.onRefresh;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: wrappedTitleToolbarHeight(context),
        titleTextStyle: wrappedTitleStyle(context),
        title: const Text('Tüm işlemler', maxLines: 2, overflow: TextOverflow.ellipsis),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: _maybeRefreshable(
          refresh,
          SingleChildScrollView(
          key: const ValueKey<String>('tum_islemler_kaydirma'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(hPad, AppSpace.sm, hPad, AppSpace.xxl),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  AppCard(
                    level: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            const IconOrb(icon: Icons.checklist_rounded, size: 48),
                            const SizedBox(width: AppSpace.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Semantics(
                                    header: true,
                                    child: Text('Tüm işlemler', style: th.titleLarge),
                                  ),
                                  const SizedBox(height: AppSpace.xs),
                                  Text(
                                    key: const ValueKey<String>('tum_islemler_ozet'),
                                    _summary(total, beyond.length),
                                    style: th.bodyMedium,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (widget.onEditMenuLayout != null) ...<Widget>[
                          const SizedBox(height: AppSpace.md),
                          PrimaryActionButton(
                            key: const ValueKey<String>('tum_islemler_menu_duzenle'),
                            label: 'Ana menüyü düzenle',
                            icon: Icons.tune_rounded,
                            variant: AppButtonVariant.tonal,
                            onPressed: widget.onEditMenuLayout,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpace.lg),
                  TextField(
                    key: const ValueKey<String>('tum_islemler_arama'),
                    controller: _search,
                    textInputAction: TextInputAction.search,
                    onChanged: _setQuery,
                    decoration: InputDecoration(
                      labelText: 'İşlem ara',
                      hintText: 'Örn. aidat, duyuru, arıza',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              key: const ValueKey<String>('tum_islemler_arama_temizle'),
                              tooltip: 'Aramayı temizle',
                              icon: const Icon(Icons.close_rounded),
                              onPressed: _clear,
                            ),
                    ),
                  ),
                  const SizedBox(height: AppSpace.lg),
                  if (sections.isEmpty)
                    const EmptyCard(
                      key: ValueKey<String>('tum_islemler_bos'),
                      icon: Icons.search_off_rounded,
                      title: 'Eşleşen işlem yok',
                      message: 'Başka bir sözcükle aramayı deneyin.',
                    )
                  else
                    for (final section in sections) ...<Widget>[
                      SectionHeader(
                        key: ValueKey<String>('tum_islemler_grup_${section.group.name}'),
                        title: section.group.title,
                        count: section.items.length,
                      ),
                      const SizedBox(height: AppSpace.sm),
                      AppCard(
                        padding: EdgeInsets.zero,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            for (final (index, item) in section.items.indexed) ...<Widget>[
                              if (index > 0) Divider(height: 1, color: context.palette.border),
                              _ActionRow(
                                key: ValueKey<String>('tum_islemler_${item.name}'),
                                title: YanMenu.titleFor(item, widget.role),
                                description: showcaseDescription(item, widget.role),
                                icon: YanMenu.iconFor(item),
                                badge: widget.badgeCounts[item] ?? 0,
                                badgeNoun: widget.badgeNouns[item] ?? 'bekleyen',
                                inMainMenu: widget.featured != null &&
                                    item != SirketMenuItem.dashboard &&
                                    menuGroupOf(item) != SirketMenuGroup.ayarlar &&
                                    widget.featured!.contains(item),
                                onTap: () => _choose(item),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpace.lg),
                    ],
                ],
              ),
            ),
          ),
          ),
        ),
      ),
    );
  }

  /// [refresh] verilmişse aşağı çekip yenileme ekler (AGENTS.md Kural 7); kaydırma alanı her durumda çekilebilir kalır.
  static Widget _maybeRefreshable(Future<void> Function()? refresh, Widget scroll) =>
      refresh == null ? scroll : RefreshIndicator(onRefresh: refresh, child: scroll);

  String _summary(int total, int beyondCount) {
    if (beyondCount > 0) {
      return 'Ana menüde öne çıkmayan $beyondCount işlem dahil, kullanabildiğiniz $total işlemin tamamı burada.';
    }
    return 'Kullanabildiğiniz $total işlemin tamamı burada.';
  }
}

/// Liste satırı: simge + başlık + açıklama (+ "Ana menüde" işareti) + rozet + ok. Tek erişilebilir düğme.
class _ActionRow extends StatelessWidget {
  const _ActionRow({
    super.key,
    required this.title,
    required this.description,
    required this.icon,
    required this.badge,
    required this.badgeNoun,
    required this.inMainMenu,
    required this.onTap,
  });

  final String title;
  final String description;
  final IconData icon;
  final int badge;
  final String badgeNoun;
  final bool inMainMenu;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final label = badge > 0 ? '$title, $badge $badgeNoun' : title;
    return Semantics(
      container: true,
      button: true,
      label: label,
      hint: <String>[
        if (description.isNotEmpty) description,
        if (inMainMenu) 'Ana menüde',
      ].join('. '),
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
            child: Row(
              children: <Widget>[
                IconOrb(icon: icon, size: 40, shape: IconOrbShape.squircle),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(title, maxLines: 3, overflow: TextOverflow.ellipsis, style: th.titleMedium),
                      if (description.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            description,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: th.bodySmall?.copyWith(color: p.textSecondary),
                          ),
                        ),
                      if (inMainMenu)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              ExcludeSemantics(child: Icon(Icons.push_pin_outlined, size: 14, color: p.textMuted)),
                              const SizedBox(width: AppSpace.xs),
                              Flexible(
                                child: Text(
                                  'Ana menüde',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: th.bodySmall?.copyWith(color: p.textMuted),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                if (badge > 0) ...<Widget>[
                  const SizedBox(width: AppSpace.sm),
                  ExcludeSemantics(
                    child: DecoratedBox(
                      key: const ValueKey<String>('tum_islemler_rozet'),
                      decoration: BoxDecoration(color: AppTone.danger.a, borderRadius: BorderRadius.circular(AppRadius.pill)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs / 2),
                        child: Text(
                          badge > 99 ? '99+' : '$badge',
                          maxLines: 1,
                          style: th.bodySmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: AppSpace.xs),
                ExcludeSemantics(child: Icon(Icons.chevron_right_rounded, color: p.textSecondary)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
