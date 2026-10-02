import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/adaptive_poller.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/geofence_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/countdown_ring.dart';
import 'package:site_kapi_kontrol/ui/design/skeleton.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

/// Sunucunun karekod durum yoklamasında bildirdiği ret nedeninin kullanıcıya gösterilen karşılığı.
class QrDenialInfo {
  const QrDenialInfo({
    required this.title,
    required this.message,
    required this.speech,
    this.permanent = false,
    this.expired = false,
  });

  final String title;
  final String message;
  final String speech;

  /// Kod bu kapıda artık çalışmaz (yetki/politika/hesap): yoklama durur, yeni kod alınabilir.
  final bool permanent;

  /// Sunucu kodun süresinin dolduğunu bildirdi: "Süresi Doldu" durumuna geçilir.
  final bool expired;
}

/// `last_denial_reason` -> açıklama. ALREADY_USED / SUPERSEDED / DOOR_MISMATCH kendi rozetleriyle
/// gösterilir; kullanıcının kendi iptali (REVOKED / USER_REVOKED) ve bilinmeyen nedenler için null.
@visibleForTesting
QrDenialInfo? qrDenialInfoFor(String? reason) {
  switch (reason) {
    case 'ACCESS_REVOKED':
      return const QrDenialInfo(
        title: 'Kapı Yetkisi Yok',
        message: 'Bu kapı için geçiş yetkiniz kaldırılmış. Site yönetimiyle iletişime geçin.',
        speech: 'Bu kapı için geçiş yetkiniz bulunmuyor.',
        permanent: true,
      );
    case 'QR_DISABLED':
      return QrDenialInfo(
        title: 'Karekod Girişi Kapalı',
        message: AuthApi.messageForErrorCode(reason) ?? 'Bu sitede karekodla giriş kapalı.',
        speech: 'Bu sitede karekodla giriş kapalı.',
        permanent: true,
      );
    case 'QR_ENTRY_INACTIVE':
      return QrDenialInfo(
        title: 'Karekod Girişi Durduruldu',
        message: AuthApi.messageForErrorCode(reason) ?? 'Bu kapıda karekodla giriş şu an devre dışı.',
        speech: 'Bu kapıda karekodla giriş şu an devre dışı.',
        permanent: true,
      );
    case 'TOKEN_OR_USER_INACTIVE':
      return const QrDenialInfo(
        title: 'Karekod Geçersiz',
        message:
            'Hesabınız veya karekodunuz artık geçerli değil. Yeni kod alın; sorun sürerse site yönetimine başvurun.',
        speech: 'Karekodunuz geçerli değil. Lütfen yeni karekod alınız.',
        permanent: true,
      );
    case 'ADMIN_REVOKED':
      return const QrDenialInfo(
        title: 'Karekod İptal Edildi',
        message: 'Karekodunuz yönetici tarafından iptal edildi. Lütfen yeni kod alın.',
        speech: 'Karekodunuz yönetici tarafından iptal edildi.',
        permanent: true,
      );
    case 'PULSE_FAILED':
      return const QrDenialInfo(
        title: 'Kapı Komutu Gönderilemedi',
        message: 'Kapıya komut iletilemedi. Kodunuz hâlâ geçerli; okuyucuya tekrar gösterin.',
        speech: 'Kapı komutu gönderilemedi. Karekodu okuyucuya tekrar gösteriniz.',
      );
    case 'EXPIRED_TOKEN':
      return const QrDenialInfo(
        title: 'Karekodun Süresi Doldu',
        message: 'Lütfen yeni kod alıp okuyucuya tekrar gösterin.',
        speech: 'Karekodun süresi doldu, lütfen kodu yenileyiniz.',
        expired: true,
      );
    default:
      return null;
  }
}

class DynamicQrPassModal extends StatefulWidget {
  const DynamicQrPassModal({
    super.key,
    required this.door,
    this.initialSeconds = 30,
    this.authService,
  });

  final DoorRecord door;
  final int initialSeconds;
  final AuthService? authService;

  @override
  State<DynamicQrPassModal> createState() => _DynamicQrPassModalState();
}

class _DynamicQrPassModalState extends State<DynamicQrPassModal>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  String? _qrToken;
  String? _errorMessage;
  bool _isLoading = true;

  final FlutterTts _tts = FlutterTts();

  late AnimationController _countdownController;
  late AnimationController _successAnimController;
  late Animation<double> _scaleAnimation;

  // Durum yoklaması (800 ms): arka plandayken durur, ardışık hatada üstel geri çekilir; her tur
  // öncekinin bitmesini bekler (üst üste binmez). Karekod kalıcı sonuçlandığında (kullanıldı, süresi
  // doldu, kalıcı ret) kaldırılır.
  AdaptivePoller? _statusPoller;
  int _totalSeconds = 30;
  bool _isExpired = false;
  bool _isDoorOpened = false;
  bool _isDoorMismatch = false;
  bool _isAlreadyUsed = false;
  bool _isSuperseded = false;
  bool _isFetchingToken = false;
  String? _deniedDoorName;
  QrDenialInfo? _denial;
  String? _handledDenialKey;


  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initTts();

    _countdownController = AnimationController(
      vsync: this,
      duration: Duration(seconds: widget.initialSeconds),
    );

    _countdownController.addStatusListener((status) {
      if (status == AnimationStatus.dismissed) {
        if (mounted && !_isDoorOpened) {
          setState(() {
            _isExpired = true;
          });
          _stopQrPolling();
          _speak('Karekodun süresi doldu, lütfen kodu yenileyiniz.');
        }
      }
    });

    _successAnimController = AnimationController(
      vsync: this,
      duration: CountdownRing.successTickDuration,
    );

    _scaleAnimation = CurvedAnimation(
      parent: _successAnimController,
      curve: CountdownRing.successTickCurve,
    );

    _fetchQrToken();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tts.stop();
    _stopQrPolling();
    _countdownController.dispose();
    _successAnimController.dispose();
    if (_qrToken != null && !_isDoorOpened) {
      widget.authService?.revokeMyDoorQr(widget.door.id);
    }
    super.dispose();
  }

  Future<void> _initTts() async {
    if (kIsWeb) return;
    try {
      await _tts.setLanguage('tr-TR');
      await _tts.setSpeechRate(0.58);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
    } catch (_) {}
  }

  Future<void> _speak(String text) async {
    if (kIsWeb || text.trim().isEmpty) return;
    try {
      await _tts.stop();
      await _tts.speak(text);
    } catch (_) {}
  }

  void _startCountdown(int totalSeconds) {
    _totalSeconds = totalSeconds > 0 ? totalSeconds : 30;
    _isExpired = false;
    _isDoorMismatch = false;
    _isAlreadyUsed = false;
    _isSuperseded = false;
    _denial = null;
    _handledDenialKey = null;
    _countdownController.stop();
    _countdownController.duration = Duration(seconds: _totalSeconds);
    _countdownController.reverse(from: 1.0);
  }

  /// Yoklama arka planda durur; uygulama ön plana dönünce [didChangeAppLifecycleState] sürdürür.
  void _startStatusPolling(String qrToken) {
    _stopQrPolling();
    final poller = AdaptivePoller(
      interval: const Duration(milliseconds: 800),
      // Karekodun ömrü ~30 sn: daha uzun bir geri çekilme, bağlantı dönünce "kapı açıldı"
      // bilgisini karekod süresinden sonra getirirdi.
      maxDelay: const Duration(seconds: 5),
      isActive: _isAppResumed,
      poll: () => _pollQrStatus(qrToken),
    );
    _statusPoller = poller;
    poller.start();
  }

  void _stopQrPolling() {
    _statusPoller?.dispose();
    _statusPoller = null;
  }

  bool _isAppResumed() {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    return mounted && (lifecycle == null || lifecycle == AppLifecycleState.resumed);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final poller = _statusPoller;
    if (poller == null) return;
    if (state == AppLifecycleState.resumed) {
      // Arka planda okuyucu karekodu işlemiş olabilir: hemen yokla.
      poller.resetBackoff();
      poller.start(immediately: true);
    } else {
      poller.stop();
    }
  }

  /// Yoklama turu: true başarılı, false hata (geri çekilme), null atlandı/yok sayıldı.
  Future<bool?> _pollQrStatus(String qrToken) async {
    if (!mounted || _isDoorOpened || _isExpired) {
      _stopQrPolling();
      return null;
    }

    final auth = widget.authService;
    if (auth == null) return null;

    final (data, error) = await auth.getDoorQrStatus(qrToken);
    if (!mounted) return null;
    // Bu arada yeni bir token alındıysa eski token'ın yanıtı yok sayılır.
    if (_qrToken != qrToken) return null;

    if (data?['used'] == true) {
      _stopQrPolling();
      _countdownController.stop();
      setState(() {
        _isDoorOpened = true;
        _isDoorMismatch = false;
        _isAlreadyUsed = false;
        _isSuperseded = false;
      });
      _successAnimController.forward(from: 0.0);
      _speak('Kapı açıldı, geçebilirsiniz.');

      // 3 saniye sonra otomatik pencereyi kapat
      Future.delayed(const Duration(milliseconds: 3200), () {
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop(true);
        }
      });
      return true;
    }

    final lastDenial = data?['last_denial_reason'] as String?;

    // Aşama 3: Tek Kullanımlık (Zaten Kullanılmış) Kod Uyarısı
    if (lastDenial == 'ALREADY_USED' && !_isAlreadyUsed) {
      setState(() {
        _isAlreadyUsed = true;
        _isDoorMismatch = false;
        _isSuperseded = false;
      });
      _speak('Bu karekod daha önce kullanılmıştır. Lütfen yeni karekod alınız.');

      Future.delayed(const Duration(seconds: 4), () {
        if (mounted && !_isDoorOpened) {
          setState(() {
            _isAlreadyUsed = false;
          });
        }
      });
    }

    // Aşama 4: Yenilenmiş ve Hükümsüz Kılınmış Kod Uyarısı (SUPERSEDED)
    if (lastDenial == 'SUPERSEDED' && !_isSuperseded) {
      setState(() {
        _isSuperseded = true;
        _isAlreadyUsed = false;
        _isDoorMismatch = false;
      });
      _speak('Bu karekod yenilendiği için hükümsüz kılınmıştır. Lütfen güncel karekodu okutunuz.');

      Future.delayed(const Duration(seconds: 4), () {
        if (mounted && !_isDoorOpened) {
          setState(() {
            _isSuperseded = false;
          });
        }
      });
    }

    // Kapı Uyuşmazlığı (Başka Kapının QR Kodunu Okutma) Durumu
    if (lastDenial == 'DOOR_MISMATCH' && !_isDoorMismatch) {
      final deniedDoor = (data?['denied_door_name'] as String?) ?? 'başka bir kapı';
      setState(() {
        _isDoorMismatch = true;
        _isAlreadyUsed = false;
        _isSuperseded = false;
        _deniedDoorName = deniedDoor;
      });
      _speak('Bu karekod bu kapıya ait değil. Lütfen doğru kapının karekodunu gösteriniz.');

      // 4 saniye sonra uyarının kalkıp yeniden denemeye dönmesi
      Future.delayed(const Duration(seconds: 4), () {
        if (mounted && !_isDoorOpened) {
          setState(() {
            _isDoorMismatch = false;
          });
        }
      });
    }

    // Yetki/politika/hesap/pulse ret nedenleri: okuyucu reddetti ama modal geçerliymiş gibi
    // görünmesin. Aynı ret olayı (neden + zaman) bir kez gösterilir.
    final denial = qrDenialInfoFor(lastDenial);
    final denialKey = '$lastDenial|${data?['last_denied_at']}';
    if (denial != null && denialKey != _handledDenialKey) {
      _handledDenialKey = denialKey;
      if (denial.expired) {
        _stopQrPolling();
        _countdownController.stop();
        setState(() {
          _isExpired = true;
        });
      } else if (denial.permanent) {
        _stopQrPolling();
        _countdownController.stop();
        setState(() {
          _denial = denial;
          _isDoorMismatch = false;
          _isAlreadyUsed = false;
          _isSuperseded = false;
        });
      } else {
        setState(() {
          _denial = denial;
        });
        Future.delayed(const Duration(seconds: 5), () {
          if (mounted && !_isDoorOpened && _denial == denial) {
            setState(() {
              _denial = null;
            });
          }
        });
      }
      _speak(denial.speech);
    }
    return error == null;
  }

  Future<void> _fetchQrToken() async {
    if (_isFetchingToken) return;
    _isFetchingToken = true;

    try {
      _stopQrPolling();
      _countdownController.stop();
      setState(() {
        _isLoading = true;
        _errorMessage = null;
        _isExpired = false;
        _isDoorOpened = false;
        _isDoorMismatch = false;
        _isAlreadyUsed = false;
        _isSuperseded = false;
        _denial = null;
        _handledDenialKey = null;
      });

      final auth = widget.authService;
      if (auth == null) {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _errorMessage = 'Yetkilendirme servisi bulunamadı.';
        });
        return;
      }

      Map<String, dynamic>? locationPayload;
      if (widget.door.requireGeofence) {
        final fix = await GeofenceService.instance.acquireVerifiedPosition();
        final pos = fix.position;
        if (pos == null) {
          if (!mounted) return;
          setState(() {
            _isLoading = false;
            _errorMessage = fix.errorMessage ??
                'Bu kapı için konum doğrulaması zorunludur. Lütfen telefonunuzun GPS konum servisini ve uygulama izinlerini açınız.';
          });
          return;
        }
        // Sözleşme C3: latitude, longitude, accuracy, timestamp (ISO UTC), is_mocked.
        locationPayload = GeofenceService.locationRequestFields(pos);
      }

      final (data, error) = await auth.requestDoorQrToken(
        widget.door.id,
        location: locationPayload,
      );
      if (!mounted) return;

      if (error != null) {
        setState(() {
          _isLoading = false;
          _errorMessage = error;
        });
        return;
      }

      final token = data?['token'] as String?;
      final expiresIn = (data?['expires_in_seconds'] as num?)?.toInt() ??
          (data?['validity_seconds'] as num?)?.toInt() ??
          widget.initialSeconds;

      setState(() {
        _isLoading = false;
        _qrToken = token;
      });

      _startCountdown(expiresIn);

      if (token != null) {
        _startStatusPolling(token);
        _speak('Telefonunuzun ekranını kameraya gösteriniz, 10 15 santimetre yaklaştırınız.');
      }
    } finally {
      _isFetchingToken = false;
    }
  }

  /// Üst durum bilgisi: başlık metni + ton. Öncelik sırası eski iç içe üçlü ifadeyle aynıdır
  /// (geçiş başarılı > ret nedeni > kullanılmış > yenilenmiş > kapı uyuşmazlığı > süresi dolmuş > geçerli).
  ({String title, AppTone tone}) _headerState(QrDenialInfo? denial) {
    if (_isDoorOpened) return (title: 'Geçiş Başarılı', tone: AppTone.success);
    if (denial != null) {
      return (title: denial.title, tone: denial.permanent ? AppTone.danger : AppTone.warning);
    }
    if (_isAlreadyUsed) return (title: 'Kullanılmış Karekod', tone: AppTone.warning);
    if (_isSuperseded) return (title: 'Yenilenmiş Karekod', tone: AppTone.warning);
    if (_isDoorMismatch) return (title: 'Kapı Uyuşmazlığı', tone: AppTone.danger);
    if (_isExpired) return (title: 'Süresi Dolmuş QR Kod', tone: AppTone.danger);
    return (title: 'Güvenli Kapı QR Kodu', tone: AppTone.success);
  }

  /// Halka rengi: null = akış (yeşil -> amber -> kırmızı, painter içinde); aksi hâlde sabit durum rengi.
  Color? _ringColor(QrDenialInfo? denial) {
    if (_isDoorOpened) return CountdownRing.successColor;
    if (denial != null) {
      return denial.permanent ? CountdownRing.lowColor : CountdownRing.warnColor;
    }
    if (_isAlreadyUsed || _isSuperseded) return CountdownRing.warnColor;
    if (_isDoorMismatch || _isExpired) return CountdownRing.lowColor;
    return null;
  }

  /// Karekod hiçbir temada değişmez: tarayıcı güvenilirliği için koyu-lacivert üstü beyaz.
  static const Color _qrInk = Color(0xFF0F172A);

  Widget _buildQrCard(BuildContext context, {required bool isQrDead}) {
    final p = context.palette;
    // Süresi dolan/ölü kod: modüller soluklaşır (Opacity/saveLayer yerine renk alfası).
    final ink = isQrDead ? _qrInk.withValues(alpha: 0.12) : _qrInk;
    return SizedBox(
      width: 184,
      height: 184,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: p.border),
          boxShadow: p.shadow(1),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.md),
          child: QrImageView(
            data: _qrToken!,
            version: QrVersions.auto,
            size: 160,
            backgroundColor: Colors.white,
            eyeStyle: QrEyeStyle(eyeShape: QrEyeShape.square, color: ink),
            dataModuleStyle: QrDataModuleStyle(
              dataModuleShape: QrDataModuleShape.square,
              color: ink,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSuccessContent(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final ink = AppTone.success.ink(p);
    return ScaleTransition(
      scale: _scaleAnimation,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: AppTone.success.tint(p),
              shape: BoxShape.circle,
              border: Border.all(
                color: AppTone.success.hue.withValues(alpha: 0.4),
                width: 2,
              ),
            ),
            child: SizedBox(
              width: 88,
              height: 88,
              child: Icon(Icons.check_rounded, color: ink, size: 56),
            ),
          ),
          const SizedBox(height: AppSpace.md),
          Text(
            'Kapı Açıldı!',
            textAlign: TextAlign.center,
            style: th.titleLarge?.copyWith(color: ink),
          ),
          const SizedBox(height: AppSpace.xs),
          Text(
            'Geçiş onaylandı',
            textAlign: TextAlign.center,
            style: th.bodySmall?.copyWith(fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  /// Karekod yüklenirken (ilk yükleme ve yenileme): karekod boyutunda iskelet + mevcut metin.
  Widget _buildLoading(BuildContext context) {
    final th = Theme.of(context).textTheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: _bodyHeight),
      child: ShimmerScope(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SkeletonBox(width: 184, height: 184, radius: AppRadius.lg),
            const SizedBox(height: AppSpace.lg),
            Text(
              'Güvenli token üretiliyor...',
              textAlign: TextAlign.center,
              style: th.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }

  /// Halka + karekod alanının (ve yükleme/hata durumlarının) en düşük yüksekliği.
  static const double _bodyHeight = 270;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final door = widget.door;
    final denial = _denial;
    final isQrDead = _isExpired || (denial?.permanent ?? false);
    final head = _headerState(denial);
    // Geri sayım: karekod var, yükleme/hata yok, geçiş olmadı ve kod henüz ölmedi.
    final isCounting =
        _qrToken != null && !_isLoading && _errorMessage == null && !_isDoorOpened && !isQrDead;
    final siteName = door.siteName;

    final Animation<double> ringProgress = _isDoorOpened
        ? kAlwaysCompleteAnimation
        : (isQrDead ? kAlwaysDismissedAnimation : _countdownController);

    return Dialog(
      backgroundColor: p.surface,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AppSpace.lg,
        vertical: AppSpace.xl,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Başlık şeridi: kapı adı + site adı; kapatma düğmesi sağ üstte (başlık altına girmez)
              Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpace.xl),
                    child: AppDialogHeader(
                      title: door.doorName,
                      subtitle: (siteName != null && siteName.isNotEmpty) ? siteName : null,
                      icon: Icons.qr_code_2_rounded,
                      tone: head.tone,
                    ),
                  ),
                  Positioned(
                    top: AppSpace.xs,
                    right: AppSpace.xs,
                    child: IconButton(
                      tooltip: 'Kapat',
                      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close, size: 20),
                    ),
                  ),
                ],
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.xl,
                  0,
                  AppSpace.xl,
                  AppSpace.xl,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Durum rozeti (geçerli kodda nabız atar, 3 turdan sonra durur) + kalan saniye
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: AppSpace.sm,
                      runSpacing: AppSpace.xs,
                      children: [
                        StatusChip(
                          label: head.title,
                          tone: head.tone,
                          pulse: isCounting && head.tone == AppTone.success,
                        ),
                        if (isCounting)
                          // Saniye metni kendi katmanında: saniyede bir boyanması karekodu etkilemez.
                          RepaintBoundary(
                            child: CountdownSeconds(
                              progress: _countdownController,
                              totalSeconds: _totalSeconds,
                              style: th.bodySmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: p.textSecondary,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (door.requireGeofence) ...[
                      const SizedBox(height: AppSpace.sm),
                      StatusChip(
                        label: 'Konum Korumalı (~${door.geofenceRadiusMeters}m)',
                        tone: AppTone.info,
                        icon: Icons.near_me_rounded,
                      ),
                    ],
                    const SizedBox(height: AppSpace.lg),

                    if (_isLoading)
                      _buildLoading(context)
                    else if (_errorMessage != null)
                      ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: _bodyHeight),
                        child: Center(
                          child: SizedBox(
                            width: double.infinity,
                            child: InlineNotice(
                              message: _errorMessage!,
                              onRetry: _fetchQrToken,
                            ),
                          ),
                        ),
                      )
                    else if (_qrToken != null) ...[
                      // Geri sayım halkası: yalnız halka her karede çizilir; karekod bir kez kurulur.
                      CountdownRing(
                        progress: ringProgress,
                        colorOverride: _ringColor(denial),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            if (_isDoorOpened)
                              _buildSuccessContent(context)
                            else
                              _buildQrCard(context, isQrDead: isQrDead),

                            if (!_isDoorOpened) ...[
                              // Kapı uyuşmazlığı
                              if (_isDoorMismatch)
                                _QrOverlay(
                                  tone: AppTone.danger,
                                  icon: Icons.wrong_location_rounded,
                                  title: 'Kapı Uyuşmazlığı!',
                                  message: 'Bu kod ${_deniedDoorName ?? "başka bir kapı"} kapısına ait değil',
                                ),
                              // Zaten kullanılmış (Aşama 3)
                              if (_isAlreadyUsed)
                                const _QrOverlay(
                                  tone: AppTone.warning,
                                  icon: Icons.history_toggle_off_rounded,
                                  title: 'Bu Karekod Zaten Kullanıldı!',
                                  message: 'Karekodlar tek kullanımlıktır. Lütfen yeni kod alınız.',
                                ),
                              // Yenilenmiş ve hükümsüz kılınmış (Aşama 4)
                              if (_isSuperseded)
                                const _QrOverlay(
                                  tone: AppTone.warning,
                                  icon: Icons.sync_problem_rounded,
                                  title: 'Karekod Hükümsüz Kılındı!',
                                  message:
                                      'Bu kod yenilendiği için geçersizdir. Lütfen ekrandaki yeni kodu gösteriniz.',
                                ),
                              // Yetki/politika/hesap/pulse ret rozeti (ACCESS_REVOKED, QR_DISABLED, ...)
                              if (denial != null)
                                _QrOverlay(
                                  tone: denial.permanent ? AppTone.danger : AppTone.warning,
                                  icon: denial.permanent
                                      ? Icons.block_rounded
                                      : Icons.error_outline_rounded,
                                  title: denial.title,
                                  message: denial.message,
                                  messageMaxLines: 8,
                                ),
                              // Süresi doldu (başka bir durum yoksa)
                              if (_isExpired &&
                                  !_isDoorMismatch &&
                                  !_isAlreadyUsed &&
                                  !_isSuperseded &&
                                  denial == null)
                                const _QrOverlay(
                                  tone: AppTone.danger,
                                  icon: Icons.timer_off_rounded,
                                  title: 'Süresi Doldu',
                                  message: 'Kodu yenileyiniz',
                                ),
                            ],
                          ],
                        ),
                      ),

                      if (!_isDoorOpened) ...[
                        const SizedBox(height: AppSpace.lg),
                        _isExpired
                            ? PrimaryActionButton(
                                label: 'Yeni QR Kod Al',
                                icon: Icons.refresh_rounded,
                                onPressed: _fetchQrToken,
                              )
                            : PrimaryActionButton(
                                label: 'Kodu Yenile',
                                icon: Icons.refresh_rounded,
                                variant: AppButtonVariant.tonal,
                                onPressed: _fetchQrToken,
                              ),
                      ],
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Karekodun üstüne binen durum rozeti (kapı uyuşmazlığı, kullanılmış, hükümsüz, ret nedeni, süresi
/// doldu): ton gradyanı üstü beyaz metin (>= 4,5:1), tek yapı. Halka alanından (270 dp) taşmasın diye
/// büyük yazıda orantılı küçülür (FittedBox); durum canlı bölge olarak duyurulur.
class _QrOverlay extends StatelessWidget {
  const _QrOverlay({
    required this.tone,
    required this.icon,
    required this.title,
    required this.message,
    this.messageMaxLines = 6,
  });

  final AppTone tone;
  final IconData icon;
  final String title;
  final String message;
  final int messageMaxLines;

  /// Rozet genişliği: halka alanı 270 dp - iki yandan 14 dp.
  static const double _width = 242;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Semantics(
        liveRegion: true,
        container: true,
        child: SizedBox(
          width: _width,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: tone.gradient,
              borderRadius: BorderRadius.circular(AppRadius.md),
              boxShadow: p.shadow(2),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpace.lg,
                vertical: AppSpace.md,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: Colors.white, size: 36),
                  const SizedBox(height: AppSpace.xs),
                  Text(
                    title,
                    style: th.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpace.xs),
                  Text(
                    message,
                    style: th.bodySmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: messageMaxLines,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
