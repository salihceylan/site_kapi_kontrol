import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/skeleton.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/dialog_parts.dart';
import 'package:site_kapi_kontrol/ui/pages/qr_scan_page.dart';

class ReplaceDeviceDialog extends StatefulWidget {
  const ReplaceDeviceDialog({
    super.key,
    required this.door,
    required this.authService,
  });

  final DoorRecord door;
  final AuthService authService;

  static Future<bool?> show(
    BuildContext context, {
    required DoorRecord door,
    required AuthService authService,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ReplaceDeviceDialog(
        door: door,
        authService: authService,
      ),
    );
  }

  @override
  State<ReplaceDeviceDialog> createState() => _ReplaceDeviceDialogState();
}

class _ReplaceDeviceDialogState extends State<ReplaceDeviceDialog> {
  final _formKey = GlobalKey<FormState>();
  final _inputController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;
  List<Map<String, dynamic>> _assignableDevices = [];
  bool _loadingDevices = false;

  @override
  void initState() {
    super.initState();
    _loadAssignableDevices();
  }

  Future<void> _loadAssignableDevices() async {
    if (!mounted) return;
    setState(() => _loadingDevices = true);
    try {
      final list = await widget.authService.getAssignableDevices(
        siteCode: widget.door.siteCode,
      );
      if (!mounted) return;
      setState(() {
        // Zaten bu kapıya atanmış olanı filtrele
        _assignableDevices = list.where((d) {
          final uid = (d['device_uid'] ?? '').toString().toUpperCase();
          final currentUid = (widget.door.assignedDeviceUid ?? '').toUpperCase();
          return uid != currentUid;
        }).toList();
        _loadingDevices = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingDevices = false);
    }
  }

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  Future<void> _scanNewDeviceQr() async {
    final scanned = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const QrScanPage()),
    );
    // QR sayfası açıkken diyalog kapanmış olabilir.
    if (!mounted) return;
    if (scanned != null && scanned.trim().isNotEmpty) {
      setState(() {
        _inputController.text = scanned.trim();
        _errorMessage = null;
      });
    }
  }

  Future<void> _submit() async {
    final cleanInput = _inputController.text.trim();
    if (cleanInput.isEmpty) {
      setState(() {
        _errorMessage = 'Lütfen yeni cihazın QR kodunu okutun veya seri numarasını girin.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final res = await widget.authService.replaceDoorDevice(
        doorId: widget.door.id,
        deviceInput: cleanInput,
      );

      if (!mounted) return;

      final message = res['message'] as String? ??
          'Cihaz başarıyla değiştirildi. Kapı yetkileri ve ayarları aynen korundu.';

      HapticFeedback.lightImpact();
      AppSnack.show(context, message, kind: AppSnackKind.success);

      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e is ApiException ? e.message : e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final door = widget.door;
    final oldUid = door.assignedDeviceUid ?? 'Tanımsız';
    // Eski cihazın donanım hedefi rozeti (yeni cihaz seçerken uyumluluk ipucu).
    final hardwareTone = door.isHardwareWroom
        ? AppTone.violet
        : (door.isHardwareC3 ? AppTone.primary : AppTone.neutral);

    return AppDialog(
      title: 'Arızalı Cihazı Değiştir',
      icon: Icons.published_with_changes_rounded,
      tone: AppTone.warning,
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(false),
          child: const Text('Vazgeç'),
        ),
        ElevatedButton.icon(
          onPressed: _isLoading ? null : _submit,
          icon: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.check_circle_outline_rounded, size: 18),
          label: Text(_isLoading ? 'Değiştiriliyor...' : 'Cihazı Değiştir'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTone.success.a,
            foregroundColor: Colors.white,
          ),
        ),
      ],
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Kapı & Mevcut Cihaz Bilgi Kartı
            AppCard(
              padding: const EdgeInsets.all(AppSpace.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DialogInfoRow(
                    icon: Icons.meeting_room_rounded,
                    tone: AppTone.neutral,
                    title: 'Kapı: ${door.doorName}',
                    titleStyle: th.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: p.text,
                    ),
                  ),
                  const SizedBox(height: AppSpace.md),
                  DialogInfoRow(
                    icon: Icons.phonelink_erase_rounded,
                    tone: AppTone.danger,
                    title: 'Eski (Arızalı) Cihaz: $oldUid',
                    titleStyle: th.bodyMedium?.copyWith(
                      color: AppTone.danger.ink(p),
                      fontWeight: FontWeight.w600,
                    ),
                    chips: [
                      if (door.hasDevice)
                        StatusChip(
                          label: door.hardwareBadgeText,
                          tone: hardwareTone,
                          icon: Icons.memory_rounded,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.md),

            // Güvence / Bilgilendirme Rozeti
            const InlineNotice(
              tone: AppTone.success,
              icon: Icons.verified_user_rounded,
              message:
                  'Kapı numarası, daire izinleri ve sakinlerin tüm yetkileri aynen korunur. Sadece fiziksel donanım yenilenir.',
            ),
            const SizedBox(height: AppSpace.lg),

            // Kamera ile QR Tara Butonu: ikincil eylem (birincil dolu düğme altta "Cihazı Değiştir").
            OutlinedButton.icon(
              onPressed: _isLoading ? null : _scanNewDeviceQr,
              icon: const Icon(Icons.qr_code_scanner_rounded),
              label: const Text('Yeni Cihazın Kutu QR Kodunu Tara'),
            ),
            const SizedBox(height: AppSpace.lg),

            // Varsa Boştaki Cihazlardan Seç
            if (_loadingDevices) ...[
              const ShimmerScope(
                child: Wrap(
                  spacing: AppSpace.sm,
                  runSpacing: AppSpace.sm,
                  children: [
                    SkeletonBox(width: 120, height: 36, radius: AppRadius.md),
                    SkeletonBox(width: 120, height: 36, radius: AppRadius.md),
                    SkeletonBox(width: 120, height: 36, radius: AppRadius.md),
                  ],
                ),
              ),
              const SizedBox(height: AppSpace.lg),
            ] else if (_assignableDevices.isNotEmpty) ...[
              Text(
                'Veya Hesabınızdaki Boş Cihazlardan Seçin:',
                style: th.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: p.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpace.sm),
              Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.sm,
                children: _assignableDevices.take(6).map((dev) {
                  final uid = (dev['device_uid'] ?? '').toString();
                  final isSelected = _inputController.text.trim().toUpperCase() == uid.toUpperCase();
                  final accent = AppTone.primary.ink(p);
                  return ChoiceChip(
                    // Seçili durum renge ek olarak onay ikonuyla da anlatılır.
                    avatar: Icon(
                      isSelected ? Icons.check_circle_rounded : Icons.memory_rounded,
                      size: 16,
                      color: isSelected ? accent : p.textSecondary,
                    ),
                    labelPadding: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
                    label: Text(uid),
                    selected: isSelected,
                    showCheckmark: false,
                    selectedColor: AppTone.primary.tint(p),
                    side: BorderSide(
                      color: isSelected ? accent : p.border,
                      width: isSelected ? 1.4 : 1,
                    ),
                    labelStyle: th.bodySmall?.copyWith(
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected ? accent : p.text,
                    ),
                    onSelected: _isLoading
                        ? null
                        : (_) {
                            setState(() {
                              _inputController.text = uid;
                              _errorMessage = null;
                            });
                          },
                  );
                }).toList(),
              ),
              const SizedBox(height: AppSpace.lg),
            ],

            // Manuel UID / Seri No Girişi
            TextFormField(
              controller: _inputController,
              enabled: !_isLoading,
              decoration: const InputDecoration(
                labelText: 'Yeni Cihaz UID veya Seri No',
                hintText: 'Örn: 00861A0D5020',
                prefixIcon: Icon(Icons.developer_board_rounded),
              ),
            ),

            // Hata Mesajı
            if (_errorMessage != null) ...[
              const SizedBox(height: AppSpace.md),
              InlineNotice(message: _errorMessage!),
            ],
          ],
        ),
      ),
    );
  }
}
