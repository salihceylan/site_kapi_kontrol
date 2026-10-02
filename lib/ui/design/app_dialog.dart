// FAZ 5 / A1b (i): ortak diyalog şablonu (başlık şeridi + içerik + eylem satırı).
import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/ui_helpers.dart';

/// Diyalog başlık şeridi: ikon karosu (44 dp, ton zeminli) + başlık + alt başlık.
///
/// [AppDialog] bunu `AlertDialog.title` olarak kullanır; `Dialog` tabanlı özel diyaloglar (cihaz
/// sahiplenme, QR modalı) doğrudan içeriklerinin başına koyar. Kendi kenar boşluğunu taşır
/// (24 / 24 / 24 / 12): çağıran ayrıca dolgu vermez.
///
/// Taşma: başlık ve alt başlık en çok 3 satır (+ elips); ikon karosu sabit 44 dp, başlık kalan genişliği
/// alır. Erişilebilirlik: başlık `Semantics(header)`. Üst öğe sınırlı genişlikte olmalıdır.
class AppDialogHeader extends StatelessWidget {
  const AppDialogHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.tone = AppTone.primary,
  });

  final String title;
  final String? subtitle;

  /// null ise ikon karosu çizilmez.
  final IconData? icon;

  final AppTone tone;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final subtitle = this.subtitle;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.xl,
        AppSpace.xl,
        AppSpace.xl,
        AppSpace.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            DecoratedBox(
              decoration: BoxDecoration(
                color: tone.tint(p),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: SizedBox(
                width: 44,
                height: 44,
                child: Center(child: Icon(icon, color: tone.ink(p), size: 24)),
              ),
            ),
            const SizedBox(width: AppSpace.md),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: th.titleLarge,
                  ),
                ),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpace.xs),
                    child: Text(
                      subtitle,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: th.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Ortak diyalog şablonu. Bir `AlertDialog` DÖNDÜRÜR (`find.byType(AlertDialog)` bulucuları aynı
/// kalır): başlık = [AppDialogHeader], içerik = sabit genişlikli (`dialogWidthForScreen`; AlertDialog
/// `IntrinsicWidth` kullandığı için genişlik SABİT olmalı) [child], eylem satırı =
/// `AlertDialog.actions`.
///
/// Eylem sırası: [İptal/Vazgeç = TextButton] sonra [birincil = FilledButton/ElevatedButton; yıkıcı =
/// danger stilli]. Eylem düğmeleri yerleşik tipte kalır (tema stilini alır). Dar ekranda/büyük yazıda
/// eylemler `OverflowBar` ile alt alta dizilir. [actions] boşsa eylem alanı hiç eklenmez.
///
/// Kaydırma: başlık + içerik BİRLİKTE kaydırılır (`AlertDialog.scrollable`), eylem satırı sabit
/// kalır. Başlığı sabitleyip yalnız içeriği kaydırmak yatayda ve klavye açıkken (özellikle büyük
/// yazıyla) başlık + eylemler için bile yer bırakmadığından taşırdı; bu düzen her boyutta taşmaz ve
/// klavye açıkken alanı forma bırakır. İçeriğe sabit yükseklik/`Expanded` vermeyin (sınırsız
/// yükseklik alır).
///
/// Taşma: başlık/alt başlık en çok 3 satır; yatay kenar boşluğu 16. Ham `Colors.red/grey/green`
/// yerine `InlineNotice`/palet kullanın. Hareket azaltma: yerleşik diyalog geçişi (~150 ms) olduğu
/// gibi kalır.
class AppDialog extends StatelessWidget {
  const AppDialog({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.icon,
    this.tone = AppTone.primary,
    this.actions = const <Widget>[],
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final AppTone tone;

  /// Diyalog içeriği (başlıkla birlikte kaydırılan alana konur; sabit yükseklik vermeyin).
  final Widget child;

  /// Eylem düğmeleri (sıra: iptal, birincil).
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final hasActions = actions.isNotEmpty;
    return AlertDialog(
      scrollable: true,
      titlePadding: EdgeInsets.zero,
      title: AppDialogHeader(
        title: title,
        subtitle: subtitle,
        icon: icon,
        tone: tone,
      ),
      contentPadding: EdgeInsets.fromLTRB(
        AppSpace.xl,
        0,
        AppSpace.xl,
        hasActions ? AppSpace.md : AppSpace.xl,
      ),
      content: SizedBox(width: dialogWidthForScreen(context), child: child),
      actionsPadding: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        0,
        AppSpace.lg,
        AppSpace.lg,
      ),
      actions: hasActions ? actions : null,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AppSpace.lg,
        vertical: AppSpace.xl,
      ),
    );
  }
}
