import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/services/easy_view_service.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

/// [EasyViewService]'i ağaçtaki her ekrana taşır. `MaterialApp`'ın ÜSTÜNDE durur (lib/app.dart); kapsam yoksa kolay görünüm
/// kapalı sayılır ve [EasyViewSwitchTile] hiçbir şey çizmez ([ThemeScope] ile aynı desen): kapsamsız kurulan ekranlar değişmez.
class EasyViewScope extends InheritedNotifier<EasyViewService> {
  const EasyViewScope({
    super.key,
    required EasyViewService service,
    required super.child,
  }) : super(notifier: service);

  /// Kapsam yoksa null. Servis değişince bağımlı widget'lar yeniden kurulur.
  static EasyViewService? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<EasyViewScope>()?.notifier;
  }

  /// Kolay görünüm açık mı? Kapsam yoksa false. Çağıran kapsama bağımlı olur (açılıp kapanınca yeniden kurulur).
  static bool isEnabled(BuildContext context) => maybeOf(context)?.enabled ?? false;
}

/// Ayarlar panelindeki "Kolay görünüm" anahtarı: büyük yazı + yüksek karşıtlık + büyük düğmeli sade ana ekran.
///
/// - Tek anlamsal düğüm: etiket "Kolay görünüm", durum anahtarın açık/kapalı bilgisi (ekran okuyucu "açık/kapalı" der);
///   açıklama metni ipucu olarak okunur.
/// - Tüm satır dokunma hedefidir (en az 56 dp); anahtar panelin kapanmasına yol açmaz (kullanıcı etkiyi hemen görür).
/// - Kapsam yoksa hiçbir şey çizmez.
class EasyViewSwitchTile extends StatelessWidget {
  const EasyViewSwitchTile({super.key});

  static const String title = 'Kolay görünüm';
  static const String subtitle = 'Büyük yazı, yüksek karşıtlık ve büyük düğmeli sade ana ekran';

  @override
  Widget build(BuildContext context) {
    final service = EasyViewScope.maybeOf(context);
    if (service == null) {
      return const SizedBox.shrink();
    }
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        type: MaterialType.transparency,
        child: SwitchListTile(
          key: const ValueKey<String>('kolay_gorunum_anahtari'),
          value: service.enabled,
          onChanged: (value) => service.setEnabled(value),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
          contentPadding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
          secondary: Icon(Icons.accessibility_new_rounded, size: 24, color: p.textSecondary),
          title: Text(title, style: th.titleMedium),
          subtitle: Text(subtitle, style: th.bodyMedium),
        ),
      ),
    );
  }
}
