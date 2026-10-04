import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/services/voice_door_service.dart';
import 'package:site_kapi_kontrol/ui/design/icon_orb.dart';
import 'package:site_kapi_kontrol/ui/design/motion_widgets.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

/// Sesli kapı kontrolü alt sayfası.
///
/// Görünüm: dinleme göstergesi cilalı bir küre ([IconOrb], 92 dp, durumun tonu) ve çevresinde
/// düzene girmeyen statik bir aura (radyal ton halesi). Durum değişince durum metni bir kez belirir
/// ([Pop], 200 ms). TEK sürekli animasyon, dinlerken dönen işlevsel mikrofon nabzıdır
/// (`repeat(reverse: true)`): dinleme bitince (durma, işlem, başarı, hata) durur; hareket azaltmada hiç
/// çalışmaz. Metinler ve davranış değişmedi.
class VoiceControlModal extends StatefulWidget {
  const VoiceControlModal({
    super.key,
    required this.voiceService,
    this.candidateDoors,
  });

  final VoiceDoorService voiceService;
  final List<DoorRecord>? candidateDoors;

  static Future<void> show(
    BuildContext context, {
    required VoiceDoorService voiceService,
    List<DoorRecord>? candidateDoors,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => VoiceControlModal(
        voiceService: voiceService,
        candidateDoors: candidateDoors,
      ),
    );
  }

  @override
  State<VoiceControlModal> createState() => _VoiceControlModalState();
}

class _VoiceControlModalState extends State<VoiceControlModal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  /// Hareket azaltma açıkken nabız atılmaz (didChangeDependencies'te güncellenir).
  bool _reduceMotion = false;

  /// Son görülen durum: başarıya GEÇİŞ anında bir kez hafif haptik vermek için.
  VoiceStatus? _lastStatus;

  /// Küre kutusu (düzendeki yer) ve aurasının kutunun dışına taşan payı (dp).
  static const double _orbSize = 92;
  static const double _orbBox = 100;
  static const double _auraBleed = 36;

  @override
  void initState() {
    super.initState();
    // Nabız yalnız dinlerken döner (durağan durumda ticker yok).
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.25).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Auto-start listening on modal open
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.voiceService.startListening(candidateDoors: widget.candidateDoors);
    });
    widget.voiceService.addListener(_onVoiceStatusChange);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = AppMotion.reduced(context);
    _syncPulse();
  }

  /// Dinliyorsa (ve hareket azaltma kapalıysa) mikrofon nabzını çevirir; değilse durdurur.
  void _syncPulse() {
    final shouldPulse = widget.voiceService.isListening && !_reduceMotion;
    if (shouldPulse && !_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    } else if (!shouldPulse && _pulseController.isAnimating) {
      _pulseController.stop();
      _pulseController.value = 0;
    }
  }

  void _onVoiceStatusChange() {
    if (mounted) _syncPulse();
    final status = widget.voiceService.status;
    // Onay anı: kapı açılıyor (yalnız durum başarıya GEÇERKEN; aynı durumda tekrar bildirimde değil).
    if (status == VoiceStatus.success &&
        _lastStatus != VoiceStatus.success &&
        mounted) {
      HapticFeedback.lightImpact();
    }
    _lastStatus = status;
    if (widget.voiceService.status == VoiceStatus.success && mounted) {
      Future.delayed(const Duration(milliseconds: 1400), () {
        if (mounted) {
          Navigator.of(context).maybePop();
        }
      });
    } else if (widget.voiceService.status == VoiceStatus.error && mounted) {
      Future.delayed(const Duration(milliseconds: 2500), () {
        if (mounted) {
          Navigator.of(context).maybePop();
        }
      });
    }
  }

  @override
  void dispose() {
    widget.voiceService.removeListener(_onVoiceStatusChange);
    _pulseController.dispose();
    widget.voiceService.stopListening();
    super.dispose();
  }

  AppTone _statusTone(VoiceStatus status) {
    switch (status) {
      case VoiceStatus.listening:
        return AppTone.success;
      case VoiceStatus.processing:
        return AppTone.primary;
      case VoiceStatus.success:
        return AppTone.success;
      case VoiceStatus.error:
        return AppTone.danger;
      case VoiceStatus.initializing:
      case VoiceStatus.idle:
        return AppTone.info;
    }
  }

  String _statusTitle(VoiceStatus status) {
    switch (status) {
      case VoiceStatus.listening:
        return 'Dinleniyor...';
      case VoiceStatus.processing:
        return 'Komut İşleniyor...';
      case VoiceStatus.success:
        return 'Kapı Açıldı!';
      case VoiceStatus.error:
        return 'İşlem Başarısız';
      case VoiceStatus.initializing:
        return 'Ses Motoru Başlatılıyor...';
      case VoiceStatus.idle:
        return 'Hazır';
    }
  }

  /// Dinleme küresi: cilalı [IconOrb] (durumun tonu, glow) ve çevresinde düzene GİRMEYEN statik aura
  /// (radyal ton halesi; yalnız boyama, ticker yok). Küre durum değişince kaybolup yeniden belirmez
  /// (açılışta hazır -> başlatılıyor -> dinliyor art arda değişir): ton anında değişir.
  Widget _buildOrb(AppTone tone, bool isListening) {
    return SizedBox(
      width: _orbBox,
      height: _orbBox,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: -_auraBleed,
            top: -_auraBleed,
            right: -_auraBleed,
            bottom: -_auraBleed,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: <Color>[
                    tone.hue.withValues(alpha: isListening ? 0.30 : 0.20),
                    tone.hue.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          IconOrb(
            icon: isListening ? Icons.mic : Icons.mic_none,
            tone: tone,
            size: _orbSize,
            glow: true,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = context.palette;

    return AnimatedBuilder(
      animation: widget.voiceService,
      builder: (context, _) {
        final status = widget.voiceService.status;
        final tone = _statusTone(status);
        final isListening = widget.voiceService.isListening;
        final maxHeight = MediaQuery.sizeOf(context).height * 0.92;

        void toggleListening() {
          if (isListening) {
            widget.voiceService.stopListening();
          } else {
            widget.voiceService.startListening(
              candidateDoors: widget.candidateDoors,
            );
          }
        }

        final closeButton = OutlinedButton.icon(
          icon: const Icon(Icons.close_rounded, size: 18),
          label: const Text('Kapat'),
          onPressed: () => Navigator.of(context).pop(),
        );
        final listenButton = ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: tone.a,
            foregroundColor: Colors.white,
          ),
          icon: Icon(
            isListening ? Icons.stop_rounded : Icons.mic_rounded,
            size: 18,
          ),
          label: Text(
            isListening ? 'Durdur' : 'Tekrar Dinle',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          onPressed: toggleListening,
        );

        return Container(
          constraints: BoxConstraints(maxHeight: maxHeight),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppRadius.xl),
            ),
          ),
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              left: 24,
              right: 24,
              top: 20,
              bottom: MediaQuery.paddingOf(context).bottom + 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag handle
                Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: p.textMuted.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                const SizedBox(height: 20),

                // Title and TTS toggle
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Icon(Icons.mic, color: tone.ink(p), size: 22),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Sesli Kapı Kontrolü',
                              style: theme.textTheme.titleMedium,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: widget.voiceService.ttsEnabled
                          ? 'Sesli Yanıtı Kapat'
                          : 'Sesli Yanıtı Aç',
                      icon: Icon(
                        widget.voiceService.ttsEnabled
                            ? Icons.volume_up_rounded
                            : Icons.volume_off_rounded,
                        color: widget.voiceService.ttsEnabled
                            ? AppTone.info.ink(p)
                            : p.textMuted,
                      ),
                      onPressed: () {
                        widget.voiceService.ttsEnabled =
                            !widget.voiceService.ttsEnabled;
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Dinleme küresi: cilalı küre + statik aura; nabız yalnız dinlerken ölçekler.
                Semantics(
                  button: true,
                  label: isListening ? 'Durdur' : 'Tekrar Dinle',
                  child: GestureDetector(
                    onTap: toggleListening,
                    child: AnimatedBuilder(
                      animation: _pulseAnimation,
                      // Küre bir kez kurulur; nabız karelerinde yalnız ölçek dönüşümü yenilenir.
                      child: _buildOrb(tone, isListening),
                      builder: (context, orb) => Transform.scale(
                        scale: isListening ? _pulseAnimation.value : 1.0,
                        child: orb,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),

                // Durum başlığı + geri bildirim: durum değişince bir kez belirir (Pop).
                Pop(
                  key: ValueKey<VoiceStatus>(status),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _statusTitle(status),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: tone.ink(p),
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (widget.voiceService.feedbackText.isNotEmpty)
                        Text(
                          widget.voiceService.feedbackText,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: status == VoiceStatus.error
                                ? AppTone.danger.ink(p)
                                : p.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Action Buttons: sığmazsa alt alta dizilir
                LayoutBuilder(
                  builder: (context, constraints) {
                    final stacked =
                        MediaQuery.textScalerOf(context).scale(1) > 1.3 ||
                        constraints.maxWidth < 300;
                    if (stacked) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          closeButton,
                          const SizedBox(height: 8),
                          listenButton,
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: closeButton),
                        const SizedBox(width: 12),
                        Expanded(child: listenButton),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

