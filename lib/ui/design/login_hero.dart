// FAZ 5 / A1b-(iii): marka başlığı (giriş sayfası ve açılış/ara ekranları).
//
// Logo + (isteğe bağlı) başlık + alt başlık. Başlık/alt başlık ikisi de null ise yalnız logo çizilir
// (açılış/ara ekranlarda logo + mevcut ilerleme göstergesi). Logo varlığı DEĞİŞMEZ
// (`assets/images/app_logo.png`); 1024x1024 kaynak, gösterim boyutunda (mantıksal px x
// devicePixelRatio) çözülür: tam çözünürlüklü ~4 MB bitmap önbellekte tutulmaz.
import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

/// Gradyan halkalı logo + başlık + alt başlık.
///
/// - Giriş: `LoginHero(title: 'AHBU Giriş', subtitle: 'Akıllı Kapı & Site Otomasyon Paneli')`.
/// - Açılış/ara ekran: `LoginHero()` (yalnız logo).
/// - Taşma: başlık ve alt başlık ortalanır, sabit yükseklik yoktur (büyük yazıda satır sarar).
/// - Erişilebilirlik: başlık `Semantics(header)`; logo dekoratiftir (anlamsal ağaçta yok).
/// - Hareket: 320 ms solma + 12 dp yukarı kayma, yalnız ilk kurulumda. Hareket azaltma açıkken yok.
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

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
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
            child: Container(
              width: ringDiameter,
              height: ringDiameter,
              padding: const EdgeInsets.all(AppSpace.xs),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: AppTone.primary.gradient,
                boxShadow: p.shadow(2),
              ),
              child: DecoratedBox(
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
