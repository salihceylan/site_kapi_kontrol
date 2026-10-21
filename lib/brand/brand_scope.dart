import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/brand/brand_theme.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

/// Etkin marka temasını ağaca açar ([BrandThemeController] değişince bağımlılar yeniden kurulur).
class BrandThemeScope extends InheritedNotifier<BrandThemeController> {
  const BrandThemeScope({super.key, required BrandThemeController controller, required super.child}) : super(notifier: controller);

  static BrandTheme? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BrandThemeScope>()?.notifier?.theme;
}

/// Çekmecenin üstündeki marka satırı: logo ve uygulamada görünen ad. Marka teması yoksa (ya da ad ve logo boşsa) hiçbir şey çizmez.
class BrandBar extends StatelessWidget {
  const BrandBar({super.key});

  @override
  Widget build(BuildContext context) {
    final brand = BrandThemeScope.maybeOf(context);
    final name = brand?.displayName;
    final bytes = brand?.logoBytes;
    if (brand == null || (name == null && bytes == null)) return const SizedBox.shrink();
    final p = context.palette;
    return Padding(
      key: const ValueKey<String>('brand_bar'),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(children: <Widget>[
        if (bytes != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(bytes, width: 36, height: 36, fit: BoxFit.contain, errorBuilder: (_, _, _) => const SizedBox(width: 36, height: 36)),
          ),
        if (bytes != null && name != null) const SizedBox(width: 10),
        if (name != null)
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(color: p.text, fontWeight: FontWeight.w700),
            ),
          ),
      ]),
    );
  }
}
