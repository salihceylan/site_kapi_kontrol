// FAZ 5 / A1b (i): boş durum (ikon karosu + metin + isteğe bağlı eylem).
import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

/// Boş / sonuç yok durumu: ikon karosu + [title] + [message] + isteğe bağlı eylem düğmesi.
///
/// Aynı bileşen "boş liste", "boş + eylem" ve "filtre sonucu yok" için kullanılır; mevcut cümleler
/// ("Kayıtlı site bulunamadı." vb.) birebir geçer. Eylem düğmesi yalnız [actionLabel] VE [onAction]
/// ikisi de verilince gösterilir.
///
/// Varsayılan (tam sayfa/bölüm): ortalanmış, en çok 360 dp genişlik, 64 dp ikon karosu. Yükseklik
/// sınırlıysa ve içerik (büyük yazıda) sığmıyorsa içerik KAYDIRILIR (taşma yok); sınırsızsa (ListView,
/// SingleChildScrollView) içeriği kadar yer kaplar. [EmptyState.compact]: kart/akordiyon içi satır
/// düzeni (40 dp ikon karosu solda, metin sağda, sola hizalı).
///
/// Giriş: 200 ms solma + 8 dp yukarı kayma (hareket azaltmada anında). Kararlı durumda animasyon yoktur.
/// Erişilebilirlik: başlık + mesaj tek anlamsal düğüm ("başlık. mesaj"); eylem düğmesi dışlanmaz.
/// Üst öğe sınırlı genişlikte olmalıdır.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    this.tone = AppTone.primary,
    this.compact = false,
  });

  /// Kart/akordiyon içi kompakt düzen (satır: ikon karosu + metin).
  const EmptyState.compact({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    this.tone = AppTone.primary,
  }) : compact = true;

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final AppTone tone;

  /// true: kompakt satır düzeni.
  final bool compact;

  /// Giriş animasyonu: 200 ms solma + 8 dp yukarı kayma. `alwaysIncludeSemantics`: ilk karede (opaklık
  /// 0) içerik erişilebilirlik ağacından düşmesin.
  Widget _entrance(BuildContext context, Widget child) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: AppMotion.of(context, AppMotion.base),
      curve: AppMotion.enter,
      builder: (context, t, c) => Opacity(
        opacity: t,
        alwaysIncludeSemantics: true,
        child: Transform.translate(offset: Offset(0, 8 * (1 - t)), child: c),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final message = this.message;
    final label = message == null ? title : '$title. $message';
    final hasAction = onAction != null && actionLabel != null;

    final Widget action = hasAction
        ? PrimaryActionButton(
            label: actionLabel!,
            onPressed: onAction,
            variant: AppButtonVariant.tonal,
            expand: false,
          )
        : const SizedBox.shrink();

    if (compact) {
      return _entrance(
        context,
        Padding(
          padding: const EdgeInsets.all(AppSpace.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                container: true,
                label: label,
                child: ExcludeSemantics(
                  child: Row(
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: tone.tint(p),
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpace.sm),
                          child: Icon(icon, size: 24, color: tone.ink(p)),
                        ),
                      ),
                      const SizedBox(width: AppSpace.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(title, style: th.titleMedium),
                            if (message != null) ...[
                              const SizedBox(height: AppSpace.xs),
                              Text(message, style: th.bodyMedium),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (hasAction) ...[const SizedBox(height: AppSpace.md), action],
            ],
          ),
        ),
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: SingleChildScrollView(
          // Üst öğenin PrimaryScrollController'ını almasın (sayfadaki asıl liste onu kullanır).
          primary: false,
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.xl),
            child: _entrance(
              context,
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Semantics(
                    container: true,
                    label: label,
                    child: ExcludeSemantics(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: tone.tint(p),
                              borderRadius: BorderRadius.circular(AppRadius.lg),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(AppSpace.lg),
                              child: Icon(icon, size: 32, color: tone.ink(p)),
                            ),
                          ),
                          const SizedBox(height: AppSpace.lg),
                          Text(
                            title,
                            textAlign: TextAlign.center,
                            style: th.titleMedium,
                          ),
                          if (message != null) ...[
                            const SizedBox(height: AppSpace.xs),
                            Text(
                              message,
                              textAlign: TextAlign.center,
                              style: th.bodyMedium,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (hasAction) ...[
                    const SizedBox(height: AppSpace.lg),
                    action,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
