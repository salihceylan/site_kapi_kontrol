import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/services/theme_service.dart';

/// [ThemeService]'i ağaçtaki her ekrana (diyaloglar ve itilen sayfalar dahil) taşır. `MaterialApp`'ın ÜSTÜNDE
/// durur (lib/app.dart); kapsam yoksa [ThemeToggleButton] hiçbir şey çizmez, böylece kapsamsız kurulan
/// ekranlar (testler, tek başına sayfalar) değişmez.
class ThemeScope extends InheritedNotifier<ThemeService> {
  const ThemeScope({
    super.key,
    required ThemeService service,
    required super.child,
  }) : super(notifier: service);

  /// Kapsam yoksa null. Servis değişince bağımlı widget'lar yeniden kurulur.
  static ThemeService? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<ThemeScope>()?.notifier;
  }
}

/// Aydınlık ↔ karanlık tema geçiş düğmesi.
///
/// - İkon GÖRÜNEN temayı değil, dokununca geçilecek temayı anlatır: aydınlıkta ay, karanlıkta güneş.
/// - Tooltip aynı zamanda anlamsal etiketidir (ekran okuyucu): "Koyu temaya geç" / "Aydınlık temaya geç".
/// - Dokunma hedefi en az 44 dp (AGENTS.md kural 6 ve ana sayfadaki eylem düğmeleriyle tutarlı).
class ThemeToggleButton extends StatelessWidget {
  const ThemeToggleButton({super.key, this.iconSize = 22});

  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final service = ThemeScope.maybeOf(context);
    if (service == null) {
      return const SizedBox.shrink();
    }
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;
    final label = isDark ? 'Aydınlık temaya geç' : 'Koyu temaya geç';
    return IconButton(
      visualDensity: VisualDensity.standard,
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      padding: EdgeInsets.zero,
      tooltip: label,
      icon: Icon(
        isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
        size: iconSize,
        // Ekran okuyucu adı: tooltip tek başına anlamsal `label` üretmez; ikonun etiketi düğme düğümüne birleşir.
        semanticLabel: label,
      ),
      onPressed: () => service.toggle(brightness),
    );
  }
}
