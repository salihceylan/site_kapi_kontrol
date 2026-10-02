// FAZ 5 / A1a: basma ölçeği ve birincil eylem düğmesi.
//
// `ElevatedButton/OutlinedButton/FilledButton` kullanan yerlerde [PrimaryActionButton] EKLENMEZ
// (onların görünümünü tema yönetir; test bulucuları o tiplere bağlıdır). Bu düğme yalnız özel
// `Container + InkWell + gradyan` kopyalarının ve yükleniyor/başarılı geçişi gereken yerlerin
// yerine geçer.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:site_kapi_kontrol/ui/design/motion_widgets.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

/// Basılı tutarken çocuğu hafifçe küçültür ([scale], varsayılan 0,97, 120 ms).
///
/// Dokunma hedefini ve düzeni DEĞİŞTİRMEZ (yalnız boyama dönüşümü). İçteki `InkWell`in `onTap`ını
/// ENGELLEMEZ: aynı hareket arenasında iç tanıyıcı kazanır, dış tanıyıcı `onTapCancel` ile
/// ölçeği geri alır; kaydırma (sürükleme) başlarsa da iptal olur, takılı kalmaz. Haptik YOKTUR:
/// geri bildirim eylem anında verilir (bkz. [PrimaryActionButton]). Anlamsal (Semantics) düğüm
/// eklemez: erişilebilirliği içteki widget sağlar.
class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.child,
    this.scale = 0.97,
    this.enabled = true,
  });

  final Widget child;

  /// Basılıyken ölçek.
  final double scale;

  /// false iken ölçek hiç değişmez.
  final bool enabled;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _down = false;

  void _set(bool down) {
    if (widget.enabled && _down != down && mounted) {
      setState(() => _down = down);
    }
  }

  @override
  void didUpdateWidget(PressableScale oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && _down) _down = false;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      // Anlamsal tap eylemi eklemesin: içteki InkWell zaten sağlar (çift düğüm olmasın).
      excludeFromSemantics: true,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        curve: AppMotion.enter,
        duration: AppMotion.of(context, AppMotion.fast),
        child: widget.child,
      ),
    );
  }
}

/// [PrimaryActionButton] görünümü.
enum AppButtonVariant {
  /// Gradyan dolgu + beyaz metin + tek glow gölge (sayfada/kartta en fazla bir tane).
  filled,

  /// Tonun soluk (tint) zemini + `ink` metin: ikincil eylem.
  tonal,

  /// Yalnız ton kenarlı + `ink` metin.
  outline,
}

/// Özel gradyan düğmelerin yerine geçen birincil/ikincil eylem düğmesi.
///
/// Durumlar: normal | basılı (ölçek 0,97) | devre dışı ([onPressed] null) | [loading] (etiket
/// yerine spinner, tıklama kapalı; etiket ağaçta YOKTUR) | [success] (gradyan success tonuna 200 ms
/// morph + onay işareti; tıklama kapalı; ebeveyn ~1,2 sn sonra false yapar).
///
/// Haptik (`selectionClick`) yalnız dokunma ONAYLANDIĞINDA (parmak kalkınca) verilir; basış
/// anında değil (kaydırma titretmesin). Dokunma hedefi en az 48 dp yüksekliktedir.
///
/// Taşma: etiket kırpılmadan en çok 2 satıra sarar; 2 satırı aşan çok uzun etiket (örn. 320 dp x 2,0
/// yazıda ~28 karakter üstü) elips ile kısalır (erişilebilirlik etiketi her zaman tam metindir).
/// [expand] false ise düğme içeriği kadar (en az 120 dp) geniştir ve yalnız sınırlı genişlikli üst
/// öğede (Wrap/Align/Row'da Flexible) kullanılmalıdır; true iken sınırsız genişlikli üst öğede
/// (Row çocuğu) KULLANMAYIN.
///
/// Erişilebilirlik: yüklenirken etiket ağaçtan kalkar ama ekran okuyucu "etiket, Yükleniyor"
/// (canlı bölge) okur; başarılı/yüklenir iken düğme etkin değildir.
class PrimaryActionButton extends StatelessWidget {
  const PrimaryActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.tone = AppTone.primary,
    this.variant = AppButtonVariant.filled,
    this.loading = false,
    this.success = false,
    this.expand = true,
  });

  final String label;

  /// null ise düğme devre dışıdır.
  final VoidCallback? onPressed;

  final IconData? icon;

  /// Renk tonu ([success] iken success tonuna döner).
  final AppTone tone;

  final AppButtonVariant variant;

  /// true: etiket yerine spinner, tıklama kapalı (erişilebilirlik etiketi "etiket, Yükleniyor").
  final bool loading;

  /// true: success tonuna morph + onay işareti, tıklama kapalı.
  final bool success;

  /// true: kullanılabilir tüm genişlik; false: içerik genişliği (en az 120 dp).
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = success ? AppTone.success : tone;
    final radius = BorderRadius.circular(AppRadius.md);
    final canTap = onPressed != null && !loading && !success;
    final live = canTap || loading || success;
    final filled = variant == AppButtonVariant.filled;
    final fg = !live ? p.textSecondary : (filled ? Colors.white : t.ink(p));

    final Widget content;
    if (loading) {
      content = SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2.5, color: fg),
      );
    } else {
      final lead = success
          ? Pop(child: Icon(Icons.check_rounded, size: 20, color: fg))
          : (icon != null ? Icon(icon, size: 20, color: fg) : null);
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (lead != null) ...[lead, const SizedBox(width: AppSpace.sm)],
          Flexible(
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
                color: fg,
              ),
            ),
          ),
        ],
      );
    }

    return PressableScale(
      enabled: canTap,
      child: Semantics(
        button: true,
        enabled: canTap,
        label: loading ? '$label, Yükleniyor' : null,
        liveRegion: loading ? true : null,
        child: AnimatedContainer(
          duration: AppMotion.of(context, AppMotion.base),
          curve: AppMotion.standard,
          width: expand ? double.infinity : null,
          constraints: BoxConstraints(
            minHeight: 48,
            minWidth: expand ? 0 : 120,
          ),
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: filled && live ? t.gradient : null,
            color: !live
                ? p.border
                : (variant == AppButtonVariant.tonal ? t.tint(p) : null),
            border: variant == AppButtonVariant.outline
                ? Border.all(
                    color: live ? t.hue.withValues(alpha: 0.6) : p.border,
                    width: 1.2,
                  )
                : null,
            boxShadow: filled && live
                ? [
                    BoxShadow(
                      color: t.a.withValues(alpha: 0.30),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: radius,
              // Gradyan üstünde varsayılan gri dalga neredeyse görünmez: dolguda beyaz, diğerlerinde ton.
              splashColor: (filled ? Colors.white : t.hue).withValues(
                alpha: filled ? 0.24 : 0.18,
              ),
              highlightColor: (filled ? Colors.white : t.hue).withValues(
                alpha: filled ? 0.10 : 0.08,
              ),
              onTap: canTap
                  ? () {
                      HapticFeedback.selectionClick();
                      onPressed!();
                    }
                  : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpace.lg,
                  vertical: AppSpace.md,
                ),
                child: Center(widthFactor: 1, child: content),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
