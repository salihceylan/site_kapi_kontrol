// FAZ 5 / A0: sayfa geçişi ve sayfa içeriği girişi.
//
// Rota geçişi: yalnız solma + %4 yatay kayma (giriş 240 ms, çıkış 200 ms). Hareket azaltma açıkken
// geçiş görünmez (içerik doğrudan gelir). iOS/macOS'ta Cupertino geri-kaydırma korunur.
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

/// Android/Windows/Linux rota geçişi: fade + %4 yatay kayma.
class AppPageTransitionsBuilder extends PageTransitionsBuilder {
  const AppPageTransitionsBuilder();

  @override
  Duration get transitionDuration => const Duration(milliseconds: 240);

  @override
  Duration get reverseTransitionDuration => AppMotion.base;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (AppMotion.reduced(context)) return child;
    return _AppPageTransition(animation: animation, child: child);
  }
}

/// CurvedAnimation'ın ömrünü yönetir: `buildTransitions` her yeniden kurulumda çağrıldığı için
/// orada CurvedAnimation üretmek parent'a dinleyici sızdırırdı.
class _AppPageTransition extends StatefulWidget {
  const _AppPageTransition({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  State<_AppPageTransition> createState() => _AppPageTransitionState();
}

class _AppPageTransitionState extends State<_AppPageTransition> {
  late CurvedAnimation _curved;
  late Animation<Offset> _offset;

  @override
  void initState() {
    super.initState();
    _bind();
  }

  void _bind() {
    _curved = CurvedAnimation(
      parent: widget.animation,
      curve: AppMotion.enter,
      reverseCurve: AppMotion.exit,
    );
    _offset = _curved.drive(
      Tween<Offset>(begin: const Offset(0.04, 0), end: Offset.zero),
    );
  }

  @override
  void didUpdateWidget(_AppPageTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animation != widget.animation) {
      _curved.dispose();
      _bind();
    }
  }

  @override
  void dispose() {
    _curved.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _curved,
      child: SlideTransition(position: _offset, child: widget.child),
    );
  }
}

/// `ThemeData.pageTransitionsTheme` için: iOS/macOS Cupertino, diğerleri [AppPageTransitionsBuilder].
const PageTransitionsTheme appPageTransitions = PageTransitionsTheme(
  builders: <TargetPlatform, PageTransitionsBuilder>{
    TargetPlatform.android: AppPageTransitionsBuilder(),
    TargetPlatform.windows: AppPageTransitionsBuilder(),
    TargetPlatform.linux: AppPageTransitionsBuilder(),
    TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
  },
);

/// Sayfa içeriği girişi (menü öğesi değişince): YALNIZ yeni içerik 200 ms solma + 8 dp
/// yukarı kayma ile gelir; eski içerik hemen kalkar.
///
/// Çağıran, içerik değişince widget'ın yeniden başlaması için `key` verir
/// (ör. `ValueKey('${_selectedMenu.name}-$_isResidentMode')`). `AnimatedSwitcher` KULLANILMAZ:
/// iki görünüm aynı anda ağaçta kalır (GlobalKey çakışması, testlerde çift sonuç).
/// Hareket azaltma açıkken içerik anında tamdır. Giriş bitince ticker çalışmaz.
class PageEntry extends StatefulWidget {
  const PageEntry({super.key, required this.child});

  final Widget child;

  @override
  State<PageEntry> createState() => _PageEntryState();
}

class _PageEntryState extends State<PageEntry>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.base,
  );
  late final Animation<double> _curved = _controller.drive(
    CurveTween(curve: AppMotion.enter),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.reduced(context)) {
      _controller.value = 1;
    } else if (_controller.status == AnimationStatus.dismissed) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _curved,
      alwaysIncludeSemantics: true,
      child: AnimatedBuilder(
        animation: _curved,
        child: widget.child,
        builder: (context, child) => Transform.translate(
          offset: Offset(0, 8 * (1 - _curved.value)),
          child: child,
        ),
      ),
    );
  }
}
