import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/models/guest_pass.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

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
      builder: (ctx) {
        final p = ctx.palette;
        final th = Theme.of(ctx).textTheme;
        return AppDialog(
          title: '🎉 Geçiş Linki Hazır!',
          icon: Icons.link_rounded,
          tone: AppTone.success,
          actions: [
            TextButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: pass.webUrl));
                Navigator.pop(ctx);
                showMessage('Geçiş linki panoya kopyalandı!');
              },
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('Linki Kopyala'),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                final shareText =
                    '${door.doorName} kapı açma bağlantınız: ${pass.webUrl}';
                try {
                  // Sistem paylaşım sayfasını (WhatsApp, SMS ...) açar.
                  await SharePlus.instance.share(
                    ShareParams(
                      text: shareText,
                      subject: '${door.doorName} geçiş linki',
                    ),
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                } catch (_) {
                  // Paylaşım sayfası açılamadıysa mesaj panoya kopyalanır.
                  await Clipboard.setData(ClipboardData(text: shareText));
                  if (ctx.mounted) Navigator.pop(ctx);
                  showMessage(
                    'Geçiş mesajı kopyalandı! WhatsApp veya SMS ile paylaşabilirsiniz.',
                  );
                }
              },
              icon: const Icon(Icons.share, size: 18),
              label: const Text('Paylaş'),
            ),
          ],
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Kurye veya misafiriniz bu linke tıklayarak ${door.doorName} kapısını açabilir.',
                style: th.bodyMedium,
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: p.surfaceMuted,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: p.border),
                ),
                child: SelectableText(
                  pass.webUrl,
                  style: th.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppTone.primary.ink(p),
                  ),
                ),
              ),
            ],
          ),
        );
      },
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
    final th = Theme.of(context).textTheme;

    return AppDialog(
      title: '${widget.door.doorName} - Geçiş Linki',
      icon: Icons.link_rounded,
      tone: AppTone.success,
      actions: [
        TextButton(
          onPressed: _isCreating ? null : () => Navigator.of(context).pop(),
          child: const Text('İptal'),
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
          label: Text(_isCreating ? 'Üretiliyor...' : 'Linki Oluştur'),
        ),
      ],
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Kurye veya misafirlerinizin uygulamayı yüklemesine gerek kalmadan tek tıkla kapıyı açabilmesi için geçici bağlantı üretin.',
              style: th.bodyMedium,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Geçiş Başlığı / Açıklama',
                hintText: 'Örn: Trendyol Kuryesi, Misafir vb.',
              ),
              validator: (value) => (value ?? '').trim().isEmpty
                  ? 'Başlık alanı boş bırakılamaz.'
                  : null,
            ),
            const SizedBox(height: 16),
            Text('Geçiş Süresi ve Türü', style: th.titleMedium),
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
              const SizedBox(height: 12),
              InlineNotice(message: _error!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPresetOption({
    required String key,
    required String title,
    required String subtitle,
  }) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final accent = AppTone.primary.ink(p);
    final selected = _selectedPreset == key;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => setState(() => _selectedPreset = key),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppTone.primary.tint(p) : p.surfaceMuted,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? accent : p.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: selected ? accent : p.textSecondary,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: th.bodyMedium?.copyWith(
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                      color: selected ? accent : p.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: th.bodySmall?.copyWith(color: p.textSecondary),
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

