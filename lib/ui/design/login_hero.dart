// FAZ 5 / A1b-(iii): marka başlığı (giriş sayfası ve açılış/ara ekranları).
//
// Logo + (isteğe bağlı) başlık + alt başlık. Başlık/alt başlık ikisi de null ise yalnız logo çizilir
// (açılış/ara ekranlarda logo + mevcut ilerleme göstergesi). Logo varlığı DEĞİŞMEZ
// (`assets/images/app_logo.png`); 1024x1024 kaynak, gösterim boyutunda (mantıksal px x
// devicePixelRatio) çözülür: tam çözünürlüklü ~4 MB bitmap önbellekte tutulmaz.
//
// "Cilalı Safir" premium halka: birincil ton gradyanı + [Gloss] cilası (kenar ışığı, hacim) +
// halkanın ARKASINDA yumuşak renkli aura. Hepsi durağandır (ticker yok): aura tek `MaskFilter.blur`
// dairesidir ve kendi `RepaintBoundary`sinde olduğundan yalnız renk/tema değişince yeniden boyanır.
import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/ui/design/gloss.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

/// Gradyan halkalı logo + başlık + alt başlık.
///
/// - Giriş: `LoginHero(title: 'AHBU Giriş', subtitle: 'Akıllı Kapı & Site Otomasyon Paneli')`.
/// - Açılış/ara ekran: `LoginHero()` (yalnız logo).
/// - Taşma: başlık ve alt başlık ortalanır, sabit yükseklik yoktur (büyük yazıda satır sarar).
/// - Erişilebilirlik: başlık `Semantics(header)`; logo ve süsler dekoratiftir (anlamsal ağaçta yok).
/// - Hareket: 320 ms solma + 12 dp yukarı kayma, yalnız ilk kurulumda. Hareket azaltma açıkken yok.
/// - Aura: halkanın [auraReach] dp dışına taşan BOYAMA'dır (düzen boyutu halka kadar kalır); üst
///   öğenin kırpması (örn. `SingleChildScrollView` görünüm alanı) auranın kenarını keser: logoyu
///   yalnız içeriği kadar dar bir kaydırıcıya koyuyorsanız etrafına [auraReach] boşluk verin.
///   Yüksek karşıtlık modunda aura (ve cila) çizilmez.
class LoginHero extends StatelessWidget {
  const LoginHero({super.key, this.title, this.subtitle});

  final String? title;
  final String? subtitle;

  /// Gradyan halkanın çapı (dp).
  static const double ringDiameter = 96;

  /// Logonun görüntülendiği çap (dp): halka - 2 x 4 (gradyan kalınlığı) - 2 x 4 (iç yüzey halkası).
  static const double logoDiameter = 80;

  /// Logo varlığı (değişmez).
  static const String logoAsset = 'assets/images/app_logo.png';

  /// Aura halkanın dışına en çok bu kadar (dp) taşar; düzeni etkilemez.
  static const double auraReach = 24;

  /// Aura bulanıklığı (`MaskFilter.blur` sigma). `BoxShadow.blurRadius` eşdeğeri 2 x sigma <= 16.
  static const double auraSigma = 7;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
    final highContrast = MediaQuery.maybeHighContrastOf(context) ?? false;
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
            child: Stack(
              // Aura halkanın dışına taşar: Stack'in boyutu yalnız halkanın boyutudur.
              clipBehavior: Clip.none,
              children: <Widget>[
                // Aura: ton gradyanının ışıması (statik, tek bulanık daire, kendi katmanında).
                if (!highContrast)
                  Positioned(
                    left: -auraReach,
                    top: -auraReach,
                    right: -auraReach,
                    bottom: -auraReach,
                    child: IgnorePointer(
                      child: RepaintBoundary(
                        child: CustomPaint(
                          painter: LoginHeroAuraPainter(dark: p.isDark),
                        ),
                      ),
                    ),
                  ),
                Container(
                  width: ringDiameter,
                  height: ringDiameter,
                  padding: const EdgeInsets.all(AppSpace.xs),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppTone.primary.gradient,
                  ),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: <Widget>[
                      // Cila: gradyan halkanın üstünde, iç yüzeyin ve logonun ALTINDA (yalnız halka
                      // kuşağında görünür: kenar ışığı + hacim). Halkanın tamamına yayılır.
                      const Positioned(
                        left: -AppSpace.xs,
                        top: -AppSpace.xs,
                        right: -AppSpace.xs,
                        bottom: -AppSpace.xs,
                        child: Gloss(shape: GlossShape.circle, strength: 0.9),
                      ),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: p.surface,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpace.xs),
                          child: ClipOval(
                            child: Image.asset(
                              logoAsset,
                              width: logoDiameter,
                              height: logoDiameter,
                              fit: BoxFit.cover,
                              // Kaynak 1024 px, gösterim 80 dp: görüntü boyutuna göre küçük çözülür.
                              cacheWidth: (logoDiameter * dpr).ceil(),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
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

/// [LoginHero] halkasının arkasındaki yumuşak renkli ışıma (aura). Dekoratiftir, durağandır.
///
/// Tek `MaskFilter.blur` dairesi: çağıran `RepaintBoundary` içinde olduğundan yalnız renk/tema
/// değişince yeniden boyanır. Tuval halkadan [LoginHero.auraReach] dp büyüktür (her yönde); daire
/// halkanın tam ortasındadır (hafifçe aşağı kayık: yere düşen ışık hissi) ve halkanın altından başlar,
/// yani yalnız dış kenarı görünür. Renk/saydamlık kapı düğmesinin aurasıyla aynı kalibrasyondur.
@visibleForTesting
class LoginHeroAuraPainter extends CustomPainter {
  const LoginHeroAuraPainter({required this.dark});

  /// Koyu temada ışıma daha belirgin saydamlıkla çizilir.
  final bool dark;

  /// Aura rengi: birincil ton (`a` ucu).
  static const AppTone tone = AppTone.primary;

  /// Açık / koyu zeminde aura saydamlığı.
  static const double alphaLight = 0.36;
  static const double alphaDark = 0.50;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset(0, LoginHero.ringDiameter * 0.04));
    canvas.drawCircle(
      c,
      LoginHero.ringDiameter * 0.54,
      Paint()
        ..color = tone.a.withValues(alpha: dark ? alphaDark : alphaLight)
        ..maskFilter = const MaskFilter.blur(
          BlurStyle.normal,
          LoginHero.auraSigma,
        ),
    );
  }

  @override
  bool shouldRepaint(LoginHeroAuraPainter old) => old.dark != dark;
}
