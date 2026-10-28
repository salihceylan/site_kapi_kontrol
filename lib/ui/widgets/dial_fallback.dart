import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/a11y_announce.dart';
import 'package:site_kapi_kontrol/ui/helpers/dial_call.dart';

/// Kuru mod kartı ("dokun-ara", K13): cihaz aramayı açamadığında (tablet, emülatör, masaüstü, web ya da arama uygulaması
/// olmayan cihaz) numarayı büyük gösterir ve tek dokunuşla kopyalatır. Hata gibi değil, çözümle birlikte anlatılır:
/// "Bu cihazdan arama başlatılamadı. Numarayı telefonunuzdan arayabilirsiniz."
///
/// - [dialable] [dialableNumber] çıktısıdır; kopyalanan değer odur, ekranda [formatPhoneForDisplay] biçimi görünür.
/// - Renk tek başına anlam taşımaz (simge + metin); zemin boyanmaz (opak yüzey, bilgi/uyarı gibi `InlineNotice` dili).
/// - Erişilebilirlik: kart canlı bölgedir (belirince ekran okuyucu "arama başlatılamadı" der); numara görünen metindir;
///   "Numarayı kopyala" tek düğümdür, dokunma hedefi >= 48 dp.
/// - Taşma: başlık ve açıklama sınırsız satıra sarar; numara ile düğme `Wrap`tedir (dar ekranda / büyük yazıda alt alta).
class DialFallbackCard extends StatelessWidget {
  const DialFallbackCard({
    super.key,
    required this.dialable,
    this.title = 'Bu cihazdan arama başlatılamadı',
    this.message = 'Numarayı telefonunuzun arama ekranına yazarak arayabilirsiniz.',
    this.onCopied,
  });

  /// Aranabilir numara ("112", "05321234567", "+905321234567").
  final String dialable;
  final String title;
  final String message;

  /// Numara panoya kopyalanınca (testler / çağıran için).
  final VoidCallback? onCopied;

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: dialable));
    if (!context.mounted) return;
    AppSnack.show(context, 'Numara kopyalandı.', kind: AppSnackKind.success);
    announcePolite(context, 'Numara kopyalandı.');
    onCopied?.call();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final ink = AppTone.warning.sign(p);
    final shown = formatPhoneForDisplay(dialable);
    return Semantics(
      container: true,
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: AppTone.warning.hue.withValues(alpha: 0.4)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.phone_disabled_rounded, size: 20, color: ink),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: Text(title, style: th.bodyMedium?.copyWith(color: ink, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.xs),
              Text(message, style: th.bodyMedium),
              const SizedBox(height: AppSpace.md),
              Wrap(
                spacing: AppSpace.md,
                runSpacing: AppSpace.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    shown,
                    key: const ValueKey<String>('arama_kuru_mod_numara'),
                    style: th.headlineMedium,
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey<String>('arama_kuru_mod_kopyala'),
                    onPressed: () => _copy(context),
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: const Text('Numarayı kopyala'),
                    style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Kuru mod kartını alt sayfada açar (Panel kutusu gibi satır içi yer olmayan yerlerde). [heading] sayfa başlığıdır
/// (örn. "Yöneticiyi ara"), [subtitle] kişiyi / siteyi söyler.
Future<void> showDialFallbackSheet(
  BuildContext context, {
  required String heading,
  required String dialable,
  String? subtitle,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (sheetContext) {
      final th = Theme.of(sheetContext).textTheme;
      return SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(AppSpace.lg, 0, AppSpace.lg, AppSpace.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(header: true, child: Text(heading, style: th.titleLarge)),
              if (subtitle != null) ...[
                const SizedBox(height: AppSpace.xs),
                Text(subtitle, style: th.bodyMedium),
              ],
              const SizedBox(height: AppSpace.md),
              DialFallbackCard(dialable: dialable),
              const SizedBox(height: AppSpace.sm),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  child: const Text('Kapat'),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
