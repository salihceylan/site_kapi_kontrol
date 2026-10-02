import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
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
    final oldUid = widget.door.assignedDeviceUid ?? 'Tanımsız';

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
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: p.surfaceMuted,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: p.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.meeting_room_outlined, size: 16, color: p.textSecondary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Kapı: ${widget.door.doorName}',
                          style: th.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: p.text,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.phonelink_erase_rounded, size: 16, color: AppTone.danger.ink(p)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Eski (Arızalı) Cihaz: $oldUid',
                          style: th.bodyMedium?.copyWith(
                            color: AppTone.danger.ink(p),
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Güvence / Bilgilendirme Rozeti
            const InlineNotice(
              tone: AppTone.success,
              icon: Icons.verified_user_rounded,
              message:
                  'Kapı numarası, daire izinleri ve sakinlerin tüm yetkileri aynen korunur. Sadece fiziksel donanım yenilenir.',
            ),
            const SizedBox(height: 16),

            // Kamera ile QR Tara Butonu
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _scanNewDeviceQr,
              icon: const Icon(Icons.qr_code_scanner_rounded),
              label: const Text('Yeni Cihazın Kutu QR Kodunu Tara'),
            ),
            const SizedBox(height: 14),

            // Varsa Boştaki Cihazlardan Seç
            if (_loadingDevices)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: LinearProgressIndicator(),
              )
            else if (_assignableDevices.isNotEmpty) ...[
              Text(
                'Veya Hesabınızdaki Boş Cihazlardan Seçin:',
                style: th.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: p.textSecondary,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _assignableDevices.take(6).map((dev) {
                  final uid = (dev['device_uid'] ?? '').toString();
                  final isSelected = _inputController.text.trim().toUpperCase() == uid.toUpperCase();
                  final accent = AppTone.primary.ink(p);
                  return ChoiceChip(
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
              const SizedBox(height: 14),
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
              const SizedBox(height: 12),
              InlineNotice(message: _errorMessage!),
            ],
          ],
        ),
      ),
    );
  }
}
