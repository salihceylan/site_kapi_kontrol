// FAZ 5 / A1b-(iii): iskelet (yükleniyor) yer tutucuları: ShimmerScope + SkeletonBox.
//
// Yalnız İLK yükleme sırasında çıplak `CircularProgressIndicator/LinearProgressIndicator` yerine
// kullanılır (yenilemede mevcut liste kalır). Tek `AnimationController` kapsamdaki tüm kutular
// tarafından paylaşılır: kutu sayısı kaç olursa olsun ekranda TEK ticker çalışır ve kutular yeniden
// KURULMAZ, yalnız yeniden BOYANIR (`CustomPainter(repaint:)`). Kararlı durumda ticker yoktur:
// kapsam yalnız yükleme sürerken ağaçta durur (ya da `active: false` yapılır); hareket azaltma açıkken
// kutular durağan çizilir. Böylece `pumpAndSettle` ve e2e yürüyüşleri bitebilir.
import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

/// Altındaki tüm [SkeletonBox]'lar için TEK paylaşılan shimmer denetleyicisi.
///
/// Kullanım: liste/ekran/kart kökünde TEK `ShimmerScope`, yalnız yükleme sürerken:
/// `if (loading) ShimmerScope(child: ...iskelet...) else ...içerik...`. Yükleme bitince kapsam
/// ağaçtan çıkarılmalı (ya da [active] false yapılmalı); aksi hâlde sonsuz animasyon kalır.
///
/// - Hareket azaltma (`MediaQuery.disableAnimations`) açıkken ya da [active] false iken denetleyici
///   durur ve kutular durağan gri çizilir.
/// - `TickerMode` kapalıyken (örn. üstü başka bir sayfayla kapalı rota) ticker sessizdir: kare
///   istenmez.
/// - Yeniden boyama kapsamın kendi katmanıyla sınırlıdır (`RepaintBoundary`): kapsam dışındaki
///   kardeşler her karede yeniden çizilmez. Bu yüzden kapsamı yalnız iskelet bölgesine koyun.
/// - Erişilebilirlik: kapsayıcı `Semantics(label: 'Yükleniyor', liveRegion: true)` verir; kutular
///   anlamsal ağaçta YOKTUR ([SkeletonBox] `ExcludeSemantics`). Kapsamın içindeki gerçek (iskelet
///   olmayan) widget'ların anlamı korunur.
class ShimmerScope extends StatefulWidget {
  const ShimmerScope({super.key, required this.child, this.active = true});

  final Widget child;

  /// false iken denetleyici durur ve kutular durağan çizilir (yükleme bitince ağaçta kalan kapsam
  /// sonsuz animasyon bırakmasın diye emniyet). Anlamsal "Yükleniyor" etiketi de kalkar.
  final bool active;

  /// Bir shimmer döngüsünün süresi.
  static const Duration period = Duration(milliseconds: 1400);

  @override
  State<ShimmerScope> createState() => _ShimmerScopeState();
}

class _ShimmerScopeState extends State<ShimmerScope>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: ShimmerScope.period,
  );

  bool get _animate => widget.active && !AppMotion.reduced(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(ShimmerScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) _sync();
  }

  /// Denetleyiciyi yalnız gerektiğinde döndürür; durdurulunca kutulara `null` verilir (durağan çizim).
  void _sync() {
    if (_animate) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.active;
    // explicitChildNodes: kapsamdaki gerçek metinler "Yükleniyor" etiketine KATILMAZ (ayrı düğüm
    // kalır); yalnız bu kapsayıcı canlı bölge olarak "Yükleniyor"u söyler.
    // RepaintBoundary: shimmer her karede yeniden boyanır; sınır olmazsa AYNI katmandaki tüm kardeşler
    // (sayfanın geri kalanı) her karede yeniden kaydedilirdi (ölçüm: 10 karede kardeş boyama 2 -> 12).
    return Semantics(
      container: active,
      explicitChildNodes: active,
      liveRegion: active ? true : null,
      label: active ? 'Yükleniyor' : null,
      child: RepaintBoundary(
        child: _Shimmer(_animate ? _controller : null, child: widget.child),
      ),
    );
  }
}

/// Paylaşılan animasyonu alt ağaca taşır. Bağımlılık bir notifier DEĞİL: animasyon değeri
/// değişince kutular yeniden kurulmaz, yalnız boyanır. Yalnız animasyonun kendisi (varlığı)
/// değişirse (durdurma/başlatma) bağımlılar yeniden kurulur.
class _Shimmer extends InheritedWidget {
  const _Shimmer(this.anim, {required super.child});

  final Animation<double>? anim;

  @override
  bool updateShouldNotify(_Shimmer oldWidget) => oldWidget.anim != anim;
}

/// Tek bir iskelet yer tutucusu (metin satırı, avatar, düğme, kart...).
///
/// - [width] verilmezse kullanılabilir tüm genişliği kaplar (`double.infinity`): `Column`/`ListView`
///   içinde doğrudan; `Row` içinde ya bir genişlik verin ya da `Expanded`/`Flexible` kullanın
///   (sınırsız genişlikte sonsuz genişlik hatası olur). Metin satırı iskeletleri için yüzde
///   genişlik: `FractionallySizedBox(widthFactor: 0.6, child: SkeletonBox())`.
/// - [radius] yüksekliğin yarısını aşarsa hap/daire olur (avatar: `width == height`, `radius: 999`).
/// - Kapsam ([ShimmerScope]) yoksa ya da durmuşsa durağan çizilir (widget testlerinde güvenli).
/// - Erişilebilirlik: kutu anlamsal ağaçta yoktur; "Yükleniyor"u kapsayıcı söyler.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({super.key, this.width, this.height = 14, this.radius = 8});

  final double? width;
  final double height;
  final double radius;

  // Açık: palet.border -> palet.surfaceMuted. Koyu: yüzeyden bir kademe açık -> slate-700.
  static const Color _baseLight = Color(0xFFE2E8F0);
  static const Color _highlightLight = Color(0xFFF1F5F9);
  static const Color _baseDark = Color(0xFF273449);
  static const Color _highlightDark = Color(0xFF334155);

  @override
  Widget build(BuildContext context) {
    final dark = context.palette.isDark;
    final anim = context.dependOnInheritedWidgetOfExactType<_Shimmer>()?.anim;
    return ExcludeSemantics(
      child: SizedBox(
        width: width ?? double.infinity,
        height: height,
        child: CustomPaint(
          painter: _SkeletonPainter(
            anim,
            dark ? _baseDark : _baseLight,
            dark ? _highlightDark : _highlightLight,
            radius,
          ),
        ),
      ),
    );
  }
}

class _SkeletonPainter extends CustomPainter {
  _SkeletonPainter(this.anim, this.base, this.highlight, this.radius)
    : super(repaint: anim);

  final Animation<double>? anim;
  final Color base;
  final Color highlight;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = base;
    final animation = anim;
    if (animation != null && size.width > 0) {
      // Vurgu bandı kutunun solundan (-0,5 w) sağına (1,5 w) süpürür; uçlarda görünmez.
      final dx = (animation.value * 2 - 0.5) * size.width;
      paint.shader =
          LinearGradient(
            colors: <Color>[base, highlight, base],
            stops: const <double>[0.35, 0.5, 0.65],
          ).createShader(
            Rect.fromLTWH(dx - size.width, 0, size.width * 2, size.height),
          );
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
      paint,
    );
  }

  @override
  bool shouldRepaint(_SkeletonPainter oldDelegate) =>
      oldDelegate.base != base ||
      oldDelegate.highlight != highlight ||
      oldDelegate.radius != radius ||
      oldDelegate.anim != anim;
}
