// FAZ 5 / A1b-(iii): marka başlığı (giriş sayfası ve açılış/ara ekranları).
//
// Logo + (isteğe bağlı) başlık + alt başlık. Başlık/alt başlık ikisi de null ise yalnız logo çizilir
// (açılış/ara ekranlarda logo + mevcut ilerleme göstergesi).
//
// Logo: Güde Teknoloji'nin vektör, şeffaf zeminli yatay logosu ([AnimatedGudeLogo]); kart yüzeyinin üstünde
// doğrudan çizilir (çerçeve/daire/plaka yok), renkleri etkin temaya göre koyu/açık palete uyar. Işıklı:
// yaprakların arkasında nefes alan altın parıltı + birkaç saniyede bir logo üstünden geçen yumuşak ışık süpürmesi.
// Eski PNG logo (`assets/images/app_logo.png`) artık kullanılmaz: bitmap çözümü / önbelleği yoktur.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/brand/gude_logo.dart';
import 'package:site_kapi_kontrol/brand/gude_logo_animated.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

/// Işıklı logo + başlık + alt başlık.
///
/// - Giriş: `LoginHero(title: 'Site ve Toplu Yaşam Yönetim Sistemi', subtitle: 'Yönetici ve sakin girişi')`.
///   (Platformun adı budur; SmartKeyPass yalnız kapı modülünün adıdır.)
/// - Açılış/ara ekran: `LoginHero()` (yalnız logo).
/// - Taşma: logo en çok [logoHeight] yüksekliğindedir, kullanılabilir genişliğe sığmıyorsa en/boy oranı korunarak
///   küçülür. Başlık ve alt başlık ortalanır, sabit yükseklik yoktur (uzun başlık ve büyük yazıda satır sarar;
///   kısıtlı genişlikte kelime ortasından da bölünür).
/// - Parıltı logonun kendi alanının İÇİNDE kalır (dışına taşmaz): üst öğenin kırpması onu kesmez, ek boşluk gerekmez.
/// - Erişilebilirlik: başlık `Semantics(header)`; logo dekoratiftir (anlamsal ağaçta yok).
/// - Hareket: 320 ms solma + 12 dp yukarı kayma, yalnız ilk kurulumda; logonun ışık animasyonu sürekli ama kibardır.
///   Hareket azaltma açıkken (ya da testlerde [GudeLogoAnimation.enabledByDefault] kapalıyken) hepsi durağandır.
class LoginHero extends StatelessWidget {
  const LoginHero({super.key, this.title, this.subtitle});

  final String? title;
  final String? subtitle;

  /// Logonun en büyük yüksekliği (dp); genişlik = yükseklik x [GudeLogo.aspect] (~182 dp).
  static const double logoHeight = 120;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final title = this.title;
    final subtitle = this.subtitle;

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: AppMotion.of(context, AppMotion.slow),
      curve: AppMotion.enter,
      builder: (context, t, child) => Opacity(
        opacity: t,
        alwaysIncludeSemantics: true,
        child: Transform.translate(
          offset: Offset(0, 12 * (1 - t)),
          child: child,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ExcludeSemantics(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final maxWidth = constraints.maxWidth;
                final height = maxWidth.isFinite
                    ? math.min(logoHeight, maxWidth / GudeLogo.aspect)
                    : logoHeight;
                return AnimatedGudeLogo(height: height, semanticLabel: null);
              },
            ),
          ),
          if (title != null) ...<Widget>[
            const SizedBox(height: AppSpace.lg),
            Semantics(
              header: true,
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: th.headlineMedium,
              ),
            ),
          ],
          if (subtitle != null) ...<Widget>[
            const SizedBox(height: AppSpace.xs),
            Text(subtitle, textAlign: TextAlign.center, style: th.bodyMedium),
          ],
        ],
      ),
    );
  }
}
