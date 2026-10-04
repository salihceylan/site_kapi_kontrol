import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/icon_orb.dart';
import 'package:site_kapi_kontrol/ui/design/theme_toggle_button.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

class VerifyEmailCodePage extends StatefulWidget {
  const VerifyEmailCodePage({
    super.key,
    required this.authService,
    required this.email,
    this.fullName,
  });

  /// Sunucu doğrulama kodunu 6 haneli üretir.
  static const int codeLength = 6;

  /// Sunucu aynı e-posta için kodu en fazla 30 sn'de bir yeniden üretir; bu süre içindeki
  /// "tekrar gönder" isteği sessizce yok sayılır (yanıt yine de 200 döner). Düğme bu sürede
  /// pasif tutulur ve geri sayım gösterilir.
  static const int resendCooldownSeconds = 30;

  /// Sunucu kodu bu süre (dakika) boyunca geçerli sayar (membership_rules.js VERIFICATION_CODE_TTL_MINUTES).
  /// E-posta teslimi gecikebildiği için kullanıcıya açıkça söylenir.
  static const int codeValidityMinutes = 30;

  final AuthService authService;
  final String email;
  final String? fullName;

  @override
  State<VerifyEmailCodePage> createState() => _VerifyEmailCodePageState();
}

class _VerifyEmailCodePageState extends State<VerifyEmailCodePage> {
  final _codeController = TextEditingController();
  bool _isLoading = false;
  bool _isResending = false;
  String? _errorMessage;
  String? _successMessage;
  Timer? _cooldownTimer;
  int _cooldownLeft = 0;

  @override
  void initState() {
    super.initState();
    // Kod kayıt sırasında az önce gönderildi: ilk açılışta da bekleme süresi işler.
    _beginCooldown();
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _codeController.dispose();
    super.dispose();
  }

  /// Yeniden gönderme geri sayımını başlatır. Çağıran, gerekiyorsa setState içinde kullanır.
  void _beginCooldown() {
    _cooldownTimer?.cancel();
    _cooldownLeft = VerifyEmailCodePage.resendCooldownSeconds;
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_cooldownLeft > 0) _cooldownLeft--;
        if (_cooldownLeft <= 0) timer.cancel();
      });
    });
  }

  Future<void> _verifyCode() async {
    final code = _codeController.text.trim();
    if (code.length != VerifyEmailCodePage.codeLength) {
      setState(() {
        _errorMessage =
            'Lütfen ${VerifyEmailCodePage.codeLength} haneli doğrulama kodunu eksiksiz giriniz.';
        _successMessage = null;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    final error = await widget.authService.verifyIndividualCode(
      email: widget.email,
      code: code,
    );

    if (!mounted) return;

    if (error != null) {
      setState(() {
        _isLoading = false;
        _errorMessage = error;
      });
    } else {
      // Başarılı doğrulama ve otomatik giriş: AuthService oturumu kurup dinleyicileri bilgilendirdi;
      // oturuma tepki veren kök rota (MaterialApp.home, lib/app.dart) HomePage'e dönüşür.
      // Kök rotayı SİLME (pushAndRemoveUntil ... false çıkış/oturum sonunda giriş ekranına
      // dönüşü öldürür ve ses/kısayol servisleri olmadan ikinci bir HomePage açar); yalnızca
      // Kayıt + Doğrulama sayfalarını kapatıp köke dön.
      HapticFeedback.lightImpact();
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  Future<void> _resendCode() async {
    if (_isResending || _cooldownLeft > 0) return;

    setState(() {
      _isResending = true;
      _errorMessage = null;
      _successMessage = null;
    });

    final error = await widget.authService.resendIndividualCode(
      email: widget.email,
    );

    if (!mounted) return;

    setState(() {
      _isResending = false;
      if (error != null) {
        _errorMessage = error;
      } else {
        // Sunucu kullanıcı varlığını ele vermemek için her durumda aynı yanıtı döner; bu yüzden
        // teslimat kesinmiş gibi yazılmaz. Yeni istek için bekleme süresi yeniden işler.
        _successMessage =
            'Bu e-posta adresi için bekleyen bir doğrulama varsa yeni ${VerifyEmailCodePage.codeLength} haneli kod birkaç dakika içinde e-postanıza ulaşır; önceki kodlar geçersiz olur. Ulaşmazsa spam klasörünü kontrol edin.';
        HapticFeedback.lightImpact();
        _beginCooldown();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final theme = Theme.of(context);
    final th = theme.textTheme;
    const tone = AppTone.primary;
    // Dar ekranda (< 400 dp) yan boşluklar 16 dp: büyük yazıda içeriğe daha çok genişlik kalır.
    final hPad = MediaQuery.sizeOf(context).width < 400 ? AppSpace.lg : AppSpace.xl;
    // 6 haneli kod: sayfa başlığından bir kademe daha iri, kalın, sabit genişlikli rakamlar ve geniş
    // harf aralığı. Boyut tipografi ölçeğinden türetilir (başlık x 1,25); yazı ölçeği 1,4 ile sınırlıdır.
    final headline = th.headlineMedium;
    final codeStyle = headline?.copyWith(
      fontSize: headline.fontSize == null ? null : headline.fontSize! * 1.25,
      letterSpacing: 10,
      color: tone.ink(p),
      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
    );

    // Sayfa zemini kökte (lib/app.dart builder) tek kez boyanır: Scaffold şeffaf kalır.
    return Scaffold(
      appBar: AppBar(
        title: const Text('E-Posta Doğrulama'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: const [ThemeToggleButton(), SizedBox(width: AppSpace.sm)],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: hPad, vertical: AppSpace.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AppCard(
                level: 2,
                padding: EdgeInsets.symmetric(horizontal: hPad, vertical: AppSpace.xxl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Hero rozet: cilalı, ışımalı daire (dekoratif; anlam aşağıdaki başlıkta).
                    const Center(
                      child: IconOrb(
                        icon: Icons.mark_email_read_rounded,
                        tone: tone,
                        size: 64,
                        glow: true,
                      ),
                    ),
                    const SizedBox(height: AppSpace.lg),

                    // Başlık ve Açıklama
                    Semantics(
                      header: true,
                      child: Text(
                        'Doğrulama Kodunu Giriniz',
                        textAlign: TextAlign.center,
                        style: th.headlineMedium,
                      ),
                    ),
                    const SizedBox(height: AppSpace.sm),
                    // Text.rich: sistem yazı ölçeğini izler (RichText varsayılanı izlemez).
                    Text.rich(
                      TextSpan(
                        children: [
                          const TextSpan(text: 'Doğrulama kodu '),
                          TextSpan(
                            text: widget.email,
                            style: TextStyle(fontWeight: FontWeight.w700, color: p.text),
                          ),
                          const TextSpan(text: ' adresinize gönderildi.'),
                        ],
                      ),
                      textAlign: TextAlign.center,
                      style: th.bodyMedium,
                    ),
                    const SizedBox(height: AppSpace.sm),
                    // E-posta birkaç dakika gecikebilir; her yeni istek öncekini geçersiz kılar.
                    Text(
                      'E-posta birkaç dakika gecikebilir. Kod ${VerifyEmailCodePage.codeValidityMinutes} dakika geçerlidir; birden fazla e-posta aldıysanız yalnızca en son istenen e-postadaki kodu giriniz.',
                      textAlign: TextAlign.center,
                      style: th.bodySmall?.copyWith(color: p.textMuted),
                    ),
                    const SizedBox(height: AppSpace.xl),

                    // 6 Haneli Kod Alanı. Yazı ölçeği 1,4 ile sınırlı: 6 hane en dar ekranda
                    // (320 dp) ve en büyük yazıda da tek satırda tam görünür.
                    MediaQuery.withClampedTextScaling(
                      maxScaleFactor: 1.4,
                      child: TextField(
                        controller: _codeController,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        maxLength: VerifyEmailCodePage.codeLength,
                        style: codeStyle,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: InputDecoration(
                          counterText: '',
                          // İç yüzey kuyusu: kart yüzeyinden bir kademe soluk zemin (rakam ve ipucu
                          // renkleri bu zeminde de >= 4,5:1).
                          fillColor: p.surfaceMuted,
                          hintText: '••••••',
                          hintStyle: codeStyle?.copyWith(
                            color: p.textMuted,
                            fontWeight: FontWeight.w400,
                          ),
                          // Hata varken kenar kırmızı (tema hata kenarı); yoksa tema kenarı.
                          enabledBorder:
                              _errorMessage != null ? theme.inputDecorationTheme.errorBorder : null,
                          focusedBorder: _errorMessage != null
                              ? theme.inputDecorationTheme.focusedErrorBorder
                              : null,
                        ),
                        onSubmitted: (_) => _verifyCode(),
                      ),
                    ),
                    const SizedBox(height: AppSpace.lg),

                    // Hata veya Başarı Bildirimi
                    if (_errorMessage != null) ...[
                      InlineNotice(message: _errorMessage!),
                      const SizedBox(height: AppSpace.lg),
                    ],

                    if (_successMessage != null) ...[
                      InlineNotice(message: _successMessage!, tone: AppTone.success),
                      const SizedBox(height: AppSpace.lg),
                    ],

                    // Doğrula Butonu: yüklenirken etiket yerine çark gösterilir (tıklama kapalı).
                    PrimaryActionButton(
                      label: 'Hesabımı Doğrula',
                      onPressed: _isLoading ? null : _verifyCode,
                      loading: _isLoading,
                    ),
                    const SizedBox(height: AppSpace.md),

                    // Tekrar Kod Gönder Butonu (etiket sarar: geri sayım büyük yazıda da görünür)
                    TextButton.icon(
                      onPressed: (_isResending || _cooldownLeft > 0) ? null : _resendCode,
                      icon: _isResending
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh_rounded, size: 18),
                      label: Text(
                        _isResending
                            ? 'Kod Gönderiliyor...'
                            : (_cooldownLeft > 0
                                ? 'Kodu Tekrar Gönder ($_cooldownLeft sn)'
                                : 'Kodu Tekrar Gönder'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    // Bekleme süresi çizgisi: kalan süre azaldıkça tükenir. Yer HER durumda ayrılır
                    // (süre bitince kart yüksekliği değişmez, içerik zıplamaz).
                    _ResendCountdownBar(
                      remaining: _cooldownLeft,
                      total: VerifyEmailCodePage.resendCooldownSeconds,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Kodu tekrar gönder" bekleme süresi için ince, dekoratif ilerleme çizgisi.
///
/// Tam çizgi = tam bekleme süresi; kalan saniye azaldıkça (saniyede bir adım, her adım 1 sn'lik
/// doğrusal geçişle) tükenir. Süre bittiğinde çizgi ağaçtan kalkar ama YERİ korunur. Ekran okuyucuya kapalıdır: süre zaten düğme etiketinde ("... (23 sn)") okunur.
/// Hareket azaltmada geçiş yoktur (çizgi saniyede bir adım atlar).
class _ResendCountdownBar extends StatelessWidget {
  const _ResendCountdownBar({required this.remaining, required this.total});

  final int remaining;
  final int total;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    const tone = AppTone.primary;
    final fraction = total <= 0 ? 0.0 : (remaining / total).clamp(0.0, 1.0);
    const barHeight = 4.0;
    // Süre bitince çizgi ağaçtan kalkar (animasyon/ticker kalmaz) ama YERİ ayrılı kalır.
    if (remaining <= 0) {
      return const SizedBox(height: AppSpace.xs + barHeight);
    }
    return ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.only(top: AppSpace.xs),
        child: FractionallySizedBox(
          widthFactor: 0.5,
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(end: fraction),
            duration: AppMotion.of(context, const Duration(seconds: 1)),
            curve: Curves.linear,
            builder: (context, value, _) => LinearProgressIndicator(
              value: value,
              minHeight: barHeight,
              backgroundColor: tone.hue.withValues(alpha: p.isDark ? 0.28 : 0.20),
              color: tone.hue,
            ),
          ),
        ),
      ),
    );
  }
}
