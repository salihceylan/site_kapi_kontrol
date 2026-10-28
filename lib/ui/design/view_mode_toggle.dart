import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/services/view_mode_service.dart';
import 'package:site_kapi_kontrol/ui/helpers/a11y_announce.dart';

/// [ViewModeService]'i ağaçtaki her ekrana taşır. `MaterialApp`'ın ÜSTÜNDE durur (lib/app.dart); kapsam yoksa
/// [ViewModeToggle] hiçbir şey çizmez ve ekranlar kendi varsayılan görünümünde kalır, böylece kapsamsız kurulan ekranlar
/// (testler, tek başına sayfalar) değişmez ([ThemeScope] ile aynı desen).
class ViewModeScope extends InheritedNotifier<ViewModeService> {
  const ViewModeScope({
    super.key,
    required ViewModeService service,
    required super.child,
  }) : super(notifier: service);

  /// Kapsam yoksa null. Servis değişince bağımlı widget'lar yeniden kurulur.
  static ViewModeService? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<ViewModeScope>()?.notifier;
  }

  /// [screen] için geçerli kip; kapsam yoksa ekranın varsayılan (eski) görünümü. Çağıran kapsama bağımlı olur.
  static ListViewMode modeOf(BuildContext context, ViewScreen screen) {
    return maybeOf(context)?.modeOf(screen) ?? screen.defaultMode;
  }
}

/// Liste ↔ kutucuk geçiş düğmesi.
///
/// - İkon GÖRÜNEN kipi değil, dokununca geçilecek kipi anlatır (tema düğmesiyle aynı desen): listedeyken ızgara, kutucuktayken
///   liste simgesi.
/// - Tooltip aynı zamanda anlamsal etiketidir (ekran okuyucu): "Kutucuk görünümüne geç" / "Liste görünümüne geç". Geçişten
///   sonra yeni kip ekran okuyucuya duyurulur.
/// - Dokunma hedefi en az 44 dp (başlık satırındaki öteki simge düğmeleriyle aynı).
/// - Kapsam yoksa hiçbir şey çizmez; [maybe] bunu çağıranın yerleşimini değiştirmeden sormasını sağlar.
class ViewModeToggle extends StatelessWidget {
  const ViewModeToggle({super.key, required this.screen, this.iconSize = 22});

  final ViewScreen screen;
  final double iconSize;

  /// Kapsam varsa düğme, yoksa null: çağıran düğme yokken başlık satırını eskisi gibi bırakabilir.
  static Widget? maybe(BuildContext context, ViewScreen screen) {
    if (ViewModeScope.maybeOf(context) == null) return null;
    return ViewModeToggle(key: ValueKey<String>('gorunum_anahtari_${screen.name}'), screen: screen);
  }

  /// Dokununca geçilecek kipin adı (düğme etiketi ve duyuru).
  static String targetLabel(ListViewMode current) =>
      current == ListViewMode.list ? 'Kutucuk görünümüne geç' : 'Liste görünümüne geç';

  @override
  Widget build(BuildContext context) {
    final service = ViewModeScope.maybeOf(context);
    if (service == null) {
      return const SizedBox.shrink();
    }
    final current = service.modeOf(screen);
    final toTiles = current == ListViewMode.list;
    final label = targetLabel(current);
    return IconButton(
      visualDensity: VisualDensity.standard,
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      padding: EdgeInsets.zero,
      tooltip: label,
      icon: Icon(
        toTiles ? Icons.grid_view_rounded : Icons.view_list_rounded,
        size: iconSize,
        // Ekran okuyucu adı: tooltip tek başına anlamsal `label` üretmez; ikonun etiketi düğme düğümüne birleşir.
        semanticLabel: label,
      ),
      onPressed: () {
        service.toggle(screen);
        announcePolite(context, toTiles ? 'Kutucuk görünümü' : 'Liste görünümü');
      },
    );
  }
}
