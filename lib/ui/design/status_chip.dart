// FAZ 5 / A1b (i): durum rozeti (çevrimiçi/çevrimdışı/uyarı) ve nabız noktası.
import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

/// Salt görüntü durum rozeti: nokta (ya da ikon) + kısa etiket.
///
/// Eşleme: çevrimiçi -> success + [pulse]; yerel ağ -> warning; çevrimdışı -> danger; cihaz yok ->
/// neutral; onay bekliyor -> warning. Etiket çağıranın mevcut metnidir ("Çevrimiçi", "Online"...).
///
/// Durumlar: normal | [pulse] (nokta 3 tur "ping" atar, SONRA DURUR: kararlı durumda ticker yok,
/// `pumpAndSettle` biter) | ton değişimi (200 ms zemin/kenar/metin/nokta renk geçişi). [icon] verilir
/// ve [pulse] kapalıysa nokta yerine ikon gösterilir; nabızda nokta öncelik taşır.
///
/// Taşma: etiket tek satır + elips (`Flexible`), sabit yükseklik/genişlik yoktur; sınırlı genişlikte
/// (`Wrap`, `Row` içinde `Flexible`) kullanın. Erişilebilirlik: tek `Semantics(label)`; nokta ve ikon
/// dışlanır; rozet DOKUNULAMAZ (etkileşimli "mod hapı" gibi rozetler StatusChip değildir). Hareket
/// azaltma: nabız ve renk geçişi kapanır.
class StatusChip extends StatefulWidget {
  const StatusChip({
    super.key,
    required this.label,
    required this.tone,
    this.icon,
    this.pulse = false,
  });

  final String label;

  final AppTone tone;

  /// Nokta yerine gösterilecek ikon ([pulse] kapalıyken).
  final IconData? icon;

  /// true: nokta 3 tur nabız atar ve durur. false->true geçişinde yeniden başlar.
  final bool pulse;

  @override
  State<StatusChip> createState() => _StatusChipState();
}

class _StatusChipState extends State<StatusChip>
    with SingleTickerProviderStateMixin {
  /// Tek nabzın süresi ve nabız sayısı: toplam 2,7 sn, sonra durur.
  static const Duration _period = Duration(milliseconds: 900);
  static const int _pings = 3;

  /// Yalnız nabız gerektiğinde kurulur: nabızsız rozetler (çoğunluk) ticker/controller taşımaz.
  AnimationController? _c;

  /// Son görülen hareket azaltma durumu (tema/ölçek değişince nabzı yeniden başlatmamak için).
  bool? _reduced;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = AppMotion.reduced(context);
    if (_reduced != reduced) {
      _reduced = reduced;
      _sync();
    }
  }

  @override
  void didUpdateWidget(StatusChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pulse != oldWidget.pulse) _sync();
  }

  void _sync() {
    final existing = _c;
    if (widget.pulse && _reduced != true) {
      final controller =
          existing ??
          (_c = AnimationController(vsync: this, duration: _period));
      controller
        ..value = 0
        ..repeat(count: _pings);
    } else if (existing != null &&
        (existing.isAnimating || existing.value != 0)) {
      existing
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  /// Nabız halkası: yalnız animasyon sürerken çizilir (bittiğinde ağaçta iz kalmaz).
  Widget _ring(AnimationController c, Color ink) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: c,
        builder: (context, _) {
          if (!c.isAnimating) return const SizedBox.shrink();
          final t = c.value;
          return Transform.scale(
            scale: 1 + 0.75 * t,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: ink.withValues(alpha: 0.35 * (1 - t)),
              ),
              child: const SizedBox(width: 8, height: 8),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final tone = widget.tone;
    final ink = tone.ink(p);
    final duration = AppMotion.of(context, AppMotion.base);
    final base = Theme.of(context).textTheme.bodySmall ?? const TextStyle();

    final Widget lead;
    if (widget.icon != null && !widget.pulse) {
      lead = TweenAnimationBuilder<Color?>(
        tween: ColorTween(end: ink),
        duration: duration,
        curve: AppMotion.standard,
        builder: (context, color, _) =>
            Icon(widget.icon, size: 14, color: color),
      );
    } else {
      lead = SizedBox(
        width: 14,
        height: 14,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            if (widget.pulse && _c != null) _ring(_c!, ink),
            AnimatedContainer(
              duration: duration,
              curve: AppMotion.standard,
              width: 8,
              height: 8,
              decoration: BoxDecoration(shape: BoxShape.circle, color: ink),
            ),
          ],
        ),
      );
    }

    return Semantics(
      label: widget.label,
      container: true,
      child: ExcludeSemantics(
        child: AnimatedContainer(
          duration: duration,
          curve: AppMotion.standard,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.md,
            vertical: AppSpace.xs,
          ),
          decoration: BoxDecoration(
            color: tone.tint(p),
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: tone.hue.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              lead,
              const SizedBox(width: AppSpace.xs),
              Flexible(
                child: AnimatedDefaultTextStyle(
                  duration: duration,
                  curve: AppMotion.standard,
                  style: base.copyWith(fontWeight: FontWeight.w700, color: ink),
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
