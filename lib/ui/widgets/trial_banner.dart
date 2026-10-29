// Deneme erişim kodu oturumunda ekranın ÜSTÜNDE duran şerit: "Deneme - X saat kaldı" (P2-27, karar K10).
//
// Sade stil (docs/TASARIM_DILI.md): soluk yüzey + ince alt çizgi, durum noktası + metin (zemin boyanmaz), animasyon yok.
// Şerit uygulama kökündedir (MaterialApp.builder): hangi sayfa açık olursa olsun görünür; normal oturumda hiç yer kaplamaz.
// Süre dolunca `onExpired` bir kez çağrılır; kök, sunucuyla oturumu doğrular (401 TRIAL_EXPIRED -> giriş ekranı + açıklama).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/design/status_dot.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

/// Kalan süreyi şerit metnine çevirir. Saat YUKARI yuvarlanır (72 saat verilen oturum "72 saat kaldı" der, "0 saat" asla çıkmaz);
/// bir saatten azı dakika olarak gösterilir.
String trialRemainingLabel(Duration remaining) {
  if (remaining.inSeconds <= 0) {
    return 'Deneme süresi doldu';
  }
  final totalMinutes = (remaining.inSeconds / 60).ceil();
  if (totalMinutes < 60) {
    return 'Deneme - $totalMinutes dakika kaldı';
  }
  final hours = (totalMinutes / 60).ceil();
  return 'Deneme - $hours saat kaldı';
}

/// Şeridin kendisi. [expiresAt] oturumun bitiş anıdır; [now] testte saati verir.
class TrialBanner extends StatefulWidget {
  const TrialBanner({
    super.key,
    required this.expiresAt,
    this.onExpired,
    this.now,
    this.tick = const Duration(seconds: 30),
  });

  final DateTime expiresAt;
  final VoidCallback? onExpired;
  final DateTime Function()? now;

  /// Metnin yenilenme aralığı.
  final Duration tick;

  @override
  State<TrialBanner> createState() => _TrialBannerState();
}

class _TrialBannerState extends State<TrialBanner> {
  Timer? _timer;
  bool _expiredReported = false;

  DateTime _now() => (widget.now ?? DateTime.now)();

  Duration get _remaining => widget.expiresAt.difference(_now());

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(widget.tick, (_) => _onTick());
    _reportIfExpired();
  }

  @override
  void didUpdateWidget(TrialBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.expiresAt != widget.expiresAt) {
      _expiredReported = false;
      _reportIfExpired();
    }
  }

  void _onTick() {
    if (!mounted) return;
    setState(() {});
    _reportIfExpired();
  }

  void _reportIfExpired() {
    if (_expiredReported || _remaining.inSeconds > 0) return;
    _expiredReported = true;
    // Kurulum sırasında setState/oturum değişimi tetiklemeyelim: çerçeve sonrası.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onExpired?.call();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final label = trialRemainingLabel(_remaining);
    final expired = _remaining.inSeconds <= 0;
    return Material(
      color: p.surfaceMuted,
      child: DecoratedBox(
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.border))),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.sm),
            child: Align(
              alignment: Alignment.centerLeft,
              child: StatusDot(
                label: label,
                tone: expired ? AppTone.danger : AppTone.warning,
                maxLines: 2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Uygulama kökünde [child]'ın (Navigator) üstüne şeridi koyar. Deneme oturumu yoksa şerit yer kaplamaz ve [child] aynı
/// konumda kalır (ağaç biçimi değişmez: oturum açılıp kapanırken sayfa yığını yeniden kurulmaz).
class TrialBannerFrame extends StatelessWidget {
  const TrialBannerFrame({super.key, required this.authService, required this.child});

  final AuthService authService;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: authService,
      builder: (context, _) {
        final expiresAt = authService.session?.trialExpiresAt;
        return Column(
          // stretch: Navigator eskisi gibi SIKI genişlik alır (şerit yokken de aynı kısıtlar).
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (expiresAt == null)
              const SizedBox.shrink()
            else
              TrialBanner(
                key: ValueKey<int>(expiresAt.millisecondsSinceEpoch),
                expiresAt: expiresAt,
                // Süre dolunca sunucu 401 TRIAL_EXPIRED döner; oturum kapanır ve giriş ekranı nedenini gösterir.
                onExpired: () => authService.refreshSession(force: true),
              ),
            Expanded(
              child: MediaQuery.removePadding(
                context: context,
                removeTop: expiresAt != null,
                child: child,
              ),
            ),
          ],
        );
      },
    );
  }
}
