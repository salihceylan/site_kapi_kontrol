import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/services/voice_door_service.dart';
import 'package:site_kapi_kontrol/styles/app_colors.dart';

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

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.25).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Auto-start listening on modal open
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.voiceService.startListening(candidateDoors: widget.candidateDoors);
    });
    widget.voiceService.addListener(_onVoiceStatusChange);
  }

  void _onVoiceStatusChange() {
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

  Color _statusColor(VoiceStatus status) {
    switch (status) {
      case VoiceStatus.listening:
        return const Color(0xFF00C853);
      case VoiceStatus.processing:
        return const Color(0xFF2979FF);
      case VoiceStatus.success:
        return const Color(0xFF00E676);
      case VoiceStatus.error:
        return const Color(0xFFFF5252);
      case VoiceStatus.initializing:
      case VoiceStatus.idle:
        return AppColors.accent;
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AnimatedBuilder(
      animation: widget.voiceService,
      builder: (context, _) {
        final status = widget.voiceService.status;
        final color = _statusColor(status);
        final isListening = widget.voiceService.isListening;

        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1E1F28),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: [
              BoxShadow(
                color: Colors.black54,
                blurRadius: 20,
                offset: Offset(0, -4),
              ),
            ],
          ),
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
                  color: Colors.white24,
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
                        Icon(Icons.mic, color: color, size: 22),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Sesli Kapı Kontrolü',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
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
                          ? AppColors.accent
                          : Colors.white38,
                    ),
                    onPressed: () {
                      widget.voiceService.ttsEnabled =
                          !widget.voiceService.ttsEnabled;
                    },
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Glowing Microphone animation
              GestureDetector(
                onTap: () {
                  if (isListening) {
                    widget.voiceService.stopListening();
                  } else {
                    widget.voiceService.startListening(
                      candidateDoors: widget.candidateDoors,
                    );
                  }
                },
                child: AnimatedBuilder(
                  animation: _pulseAnimation,
                  builder: (context, child) {
                    final scale = isListening ? _pulseAnimation.value : 1.0;
                    return Transform.scale(
                      scale: scale,
                      child: Container(
                        width: 90,
                        height: 90,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: color.withValues(alpha: 0.18),
                          border: Border.all(color: color, width: 2.5),
                          boxShadow: [
                            if (isListening)
                              BoxShadow(
                                color: color.withValues(alpha: 0.4),
                                blurRadius: 24,
                                spreadRadius: 4,
                              ),
                          ],
                        ),
                        child: Center(
                          child: Icon(
                            isListening ? Icons.mic : Icons.mic_none,
                            color: color,
                            size: 42,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 18),

              // Status Title
              Text(
                _statusTitle(status),
                style: theme.textTheme.titleMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              if (widget.voiceService.feedbackText.isNotEmpty)
                Text(
                  widget.voiceService.feedbackText,
                  style: TextStyle(
                    color: status == VoiceStatus.error
                        ? const Color(0xFFFF8A80)
                        : Colors.white70,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              const SizedBox(height: 20),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: const BorderSide(color: Colors.white24),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: const Icon(Icons.close_rounded, size: 18),
                      label: const Text('Kapat'),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: color,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: Icon(
                        isListening ? Icons.stop_rounded : Icons.mic_rounded,
                        size: 18,
                      ),
                      label: Text(
                        isListening ? 'Durdur' : 'Tekrar Dinle',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      onPressed: () {
                        if (isListening) {
                          widget.voiceService.stopListening();
                        } else {
                          widget.voiceService.startListening(
                            candidateDoors: widget.candidateDoors,
                          );
                        }
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

