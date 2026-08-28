import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/models/guest_pass.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/styles/app_colors.dart';
import 'package:site_kapi_kontrol/ui/helpers/ui_helpers.dart';

class CreateGuestPassDialog extends StatefulWidget {
  const CreateGuestPassDialog({
    super.key,
    required this.door,
    required this.authService,
  });

  final DoorRecord door;
  final AuthService authService;

  static Future<void> show(
    BuildContext context, {
    required DoorRecord door,
    required AuthService authService,
    required void Function(String message) showMessage,
  }) async {
    final pass = await showDialog<GuestPassRecord>(
      context: context,
      builder: (_) => CreateGuestPassDialog(
        door: door,
        authService: authService,
      ),
    );

    if (!context.mounted || pass == null) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('🎉 Gecis Linki Hazir!'),
        content: SizedBox(
          width: dialogWidthForScreen(context),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Kurye veya misafiriniz bu linke tiklayarak ${door.doorName} kapisini acabilir.',
                  style: const TextStyle(fontSize: 13.5),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: SelectableText(
                    pass.webUrl,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: pass.webUrl));
              Navigator.pop(ctx);
              showMessage('Gecis linki panoya kopyalandi!');
            },
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('Linki Kopyala'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              final shareText =
                  '${door.doorName} kapi acma baglantiniz: ${pass.webUrl}';
              Clipboard.setData(ClipboardData(text: shareText));
              Navigator.pop(ctx);
              showMessage(
                'Gecis mesaji kopyalandi! WhatsApp veya SMS ile paylasabilirsiniz.',
              );
            },
            icon: const Icon(Icons.share, size: 18),
            label: const Text('Paylas'),
          ),
        ],
      ),
    );
  }

  @override
  State<CreateGuestPassDialog> createState() => _CreateGuestPassDialogState();
}

class _CreateGuestPassDialogState extends State<CreateGuestPassDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController(text: 'Kurye / Misafir');
  String _selectedPreset = 'single_30';
  bool _isCreating = false;
  String? _error;

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    setState(() {
      _isCreating = true;
      _error = null;
    });

    final (passType, durationMinutes, maxUses) = switch (_selectedPreset) {
      'single_30' => ('single_use', 30, 1),
      'timed_120' => ('time_limited', 120, 5),
      'timed_720' => ('time_limited', 720, 10),
      _ => ('single_use', 30, 1),
    };

    final (pass, error) = await widget.authService.createGuestPass(
      doorId: widget.door.id,
      title: _titleController.text.trim(),
      passType: passType,
      durationMinutes: durationMinutes,
      maxUses: maxUses,
    );

    if (!mounted) {
      return;
    }

    setState(() => _isCreating = false);

    if (error != null) {
      setState(() => _error = error);
      return;
    }

    Navigator.of(context).pop(pass);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: Text('${widget.door.doorName} - Gecis Linki'),
      content: SizedBox(
        width: dialogWidthForScreen(context),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Kurye veya misafirlerinizin uygulamayi yuklemesine gerek kalmadan tek tikla kapiyi acabilmesi icin gecici baglanti uretin.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: 'Gecis Basligi / Aciklama',
                    hintText: 'Orn: Trendyol Kuryesi, Misafir vb.',
                  ),
                  validator: (value) => (value ?? '').trim().isEmpty
                      ? 'Baslik alani bos birakilamaz.'
                      : null,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Gecis Suresi ve Turu',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 8),
                _buildPresetOption(
                  key: 'single_30',
                  title: 'Tek Kullanımlık (30 Dakika)',
                  subtitle: 'Kurye ve tek seferlik teslimatlar için',
                ),
                const SizedBox(height: 6),
                _buildPresetOption(
                  key: 'timed_120',
                  title: 'Süreli Misafir (2 Saat - 5 Kullanım)',
                  subtitle: 'Misafir ve akrabalar için',
                ),
                const SizedBox(height: 6),
                _buildPresetOption(
                  key: 'timed_720',
                  title: 'Günlük Geçiş (12 Saat - 10 Kullanım)',
                  subtitle: 'Usta, nakliye ve servisler için',
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    style: const TextStyle(color: Colors.red, fontSize: 12.5),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isCreating ? null : () => Navigator.of(context).pop(),
          child: const Text('Iptal'),
        ),
        ElevatedButton.icon(
          onPressed: _isCreating ? null : _submit,
          icon: _isCreating
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.link, size: 18),
          label: Text(_isCreating ? 'Uretiliyor...' : 'Linki Olustur'),
        ),
      ],
    );
  }

  Widget _buildPresetOption({
    required String key,
    required String title,
    required String subtitle,
  }) {
    final selected = _selectedPreset == key;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => setState(() => _selectedPreset = key),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.08)
              : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.primary : Colors.grey.shade300,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: selected ? AppColors.primary : Colors.grey.shade500,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                      fontSize: 13,
                      color: selected ? AppColors.primary : AppColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
