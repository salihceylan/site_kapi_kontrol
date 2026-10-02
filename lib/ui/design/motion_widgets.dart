// FAZ 5 / A1a: hareket primitifleri (sayaç, liste girişi, beliriş).
//
// Hepsi `AppMotion.of(context, ...)` üzerinden geçer: `MediaQuery.disableAnimations` açıkken süre
// sıfırdır / hareket yoktur ve tek `pump()` son durumu gösterir. Hiçbirinde sonsuz animasyon yok:
// `pumpAndSettle` biter.
import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

/// Tam sayı değişince eski değerden yenisine 320 ms akan sayaç ("2 Kapı", "(3)", geri sayım).
///
/// İlk karede animasyon yoktur (doğrudan [value] görünür). Rakamlar sabit genişlikli
/// (tabular) olduğundan sayı akarken metin titremez. Tek satır + elips: taşmaz.
class AnimatedCount extends StatelessWidget {
  const AnimatedCount({
    super.key,
    required this.value,
    this.prefix = '',
    this.suffix = '',
    this.style,
  });

  final int value;

  /// Sayının önüne eklenen sabit metin (örn. "(").
  final String prefix;

  /// Sayının arkasına eklenen sabit metin (örn. " Kapı", " sn").
  final String suffix;

  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    // Ekran okuyucu akış sırasındaki ara değerleri değil, hedef değeri okur (anlamsal ağaç her
    // karede değişmez).
    return Semantics(
      label: '$prefix$value$suffix',
      excludeSemantics: true,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(end: value.toDouble()),
        duration: AppMotion.of(context, AppMotion.slow),
        curve: AppMotion.enter,
        builder: (context, current, _) => Text(
          '$prefix${current.round()}$suffix',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: (style ?? const TextStyle()).copyWith(
            fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

/// Liste girişi: yalnız ilk [maxAnimated] öğe, öğe başına [AppMotion.base] (200 ms) + [step]
/// (30 ms) kademe ile (toplam <= 440 ms) 12 dp yukarıdan kayarak ve solarak gelir.
///
/// `index >= 8` ya da hareket azaltma açıkken öğe doğrudan görünür. Ağaç yapısı HER durumda
/// aynıdır (liste başında öğe eklenip silinince bir öğenin sırası 7 <-> 8 geçse bile alt ağacının
/// State'i kaybolmaz). Animasyon yalnız ilk kurulumda bir kez oynar: `Column + for` listelerinde
/// yenilemede yeniden kurulmayan öğeler tekrar hareketlenmez. Tembel (`ListView.builder`)
/// listelerde öğe önbellek dışına çıkıp dönünce State yeniden kurulacağından animasyon tekrar
/// oynar: bu listelerde kullanmayın.
class StaggeredEntry extends StatefulWidget {
  const StaggeredEntry({super.key, required this.index, required this.child});

  /// Listedeki sıra (0'dan).
  final int index;

  final Widget child;

  /// Hareketlenen öğe sayısı sınırı.
  static const int maxAnimated = 8;

  /// Öğeler arası kademe.
  static const Duration step = Duration(milliseconds: 30);

  /// Yukarıdan kayma mesafesi (dp).
  static const double rise = 12;

  @override
  State<StaggeredEntry> createState() => _StaggeredEntryState();
}

class _StaggeredEntryState extends State<StaggeredEntry>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  Animation<double> _progress = kAlwaysCompleteAnimation;
  bool _decided = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_decided) {
      // Hareket azaltma giriş sürerken açılırsa öğe hemen tamamlanır.
      if (AppMotion.reduced(context)) _controller?.value = 1;
      return;
    }
    _decided = true;
    final skip =
        widget.index >= StaggeredEntry.maxAnimated ||
        AppMotion.reduced(context);
    if (skip) return;
    final index = widget.index < 0 ? 0 : widget.index;
    final delay = StaggeredEntry.step * index;
    final total = AppMotion.base + delay;
    final controller = AnimationController(vsync: this, duration: total);
    _controller = controller;
    _progress = controller.drive(
      CurveTween(
        curve: Interval(
          delay.inMilliseconds / total.inMilliseconds,
          1,
          curve: AppMotion.enter,
        ),
      ),
    );
    controller.forward();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _progress,
      child: widget.child,
      builder: (context, child) {
        final t = _progress.value;
        return Opacity(
          opacity: t,
          alwaysIncludeSemantics: true,
          child: Transform.translate(
            offset: Offset(0, StaggeredEntry.rise * (1 - t)),
            child: child,
          ),
        );
      },
    );
  }
}

/// Beliriş: [key] değişince YALNIZ yeni çocuk 0,9 -> 1 ölçek ve solma ile gelir; eski çocuk hemen
/// kalkar (AnimatedSwitcher gibi iki çocuk aynı anda ağaçta KALMAZ: `find.text` çift sonuç vermez).
///
/// Kullanım: `Pop(key: ValueKey(durum), child: Text(durumMetni))`. Durum metni/etiket
/// değişimlerinde ve hata/başarı kutularının girişinde kullanılır.
class Pop extends StatelessWidget {
  const Pop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // İlerleme 0 -> 1 (easeOutBack hafifçe aşar): opaklık ilerlemedir (sınırlı), ölçek 0,9 + 0,1 x ilerleme.
    // Son karede opaklık ve ölçek tam 1,0'dır (kayan nokta artığı yok).
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: AppMotion.of(context, AppMotion.base),
      curve: Curves.easeOutBack,
      builder: (context, progress, child) => Opacity(
        opacity: progress.clamp(0.0, 1.0),
        alwaysIncludeSemantics: true,
        child: Transform.scale(scale: 0.9 + 0.1 * progress, child: child),
      ),
      child: child,
    );
  }
}
