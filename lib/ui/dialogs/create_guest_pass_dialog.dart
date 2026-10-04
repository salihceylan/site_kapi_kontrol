import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/models/guest_pass.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/icon_orb.dart';
import 'package:site_kapi_kontrol/ui/design/motion_widgets.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/dialog_parts.dart';
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
      builder: (ctx) {
        return AppDialog(
          title: '🎉 Geçiş Linki Hazır!',
          icon: Icons.link_rounded,
          tone: AppTone.success,
          actions: [
            TextButton.icon(
              onPressed: () {
                HapticFeedback.lightImpact();
                Clipboard.setData(ClipboardData(text: pass.webUrl));
                Navigator.pop(ctx);
                showMessage('Geçiş linki panoya kopyalandı!');
              },
              icon: const Icon(Icons.copy_rounded, size: 18),
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
              icon: const Icon(Icons.share_rounded, size: 18),
              label: const Text('Paylaş'),
            ),
          ],
          child: _GuestPassResult(pass: pass, doorName: door.doorName),
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

    HapticFeedback.lightImpact();
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
              : const Icon(Icons.link_rounded, size: 18),
          label: Text(_isCreating ? 'Üretiliyor...' : 'Linki Oluştur'),
        ),
      ],
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Kurye veya misafirlerinizin uygulamayı yüklemesine gerek kalmadan tek tıkla kapıyı açabilmesi için geçici bağlantı üretin.',
              style: th.bodyMedium,
            ),
            const SizedBox(height: AppSpace.lg),
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Geçiş Başlığı / Açıklama',
                hintText: 'Örn: Trendyol Kuryesi, Misafir vb.',
                prefixIcon: Icon(Icons.edit_note_rounded),
              ),
              validator: (value) => (value ?? '').trim().isEmpty
                  ? 'Başlık alanı boş bırakılamaz.'
                  : null,
            ),
            const SizedBox(height: AppSpace.lg),
            Text('Geçiş Süresi ve Türü', style: th.titleMedium),
            const SizedBox(height: AppSpace.sm),
            _buildPresetOption(
              index: 0,
              key: 'single_30',
              icon: Icons.local_shipping_rounded,
              title: 'Tek Kullanımlık (30 Dakika)',
              subtitle: 'Kurye ve tek seferlik teslimatlar için',
            ),
            const SizedBox(height: AppSpace.sm),
            _buildPresetOption(
              index: 1,
              key: 'timed_120',
              icon: Icons.group_rounded,
              title: 'Süreli Misafir (2 Saat - 5 Kullanım)',
              subtitle: 'Misafir ve akrabalar için',
            ),
            const SizedBox(height: AppSpace.sm),
            _buildPresetOption(
              index: 2,
              key: 'timed_720',
              icon: Icons.handyman_rounded,
              title: 'Günlük Geçiş (12 Saat - 10 Kullanım)',
              subtitle: 'Usta, nakliye ve servisler için',
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpace.md),
              InlineNotice(message: _error!),
            ],
          ],
        ),
      ),
    );
  }

  /// Süre/tür seçim satırı: seçili satır birincil tonlu rozet + onay işareti + vurgulu kenar,
  /// diğerleri nötr rozet + boş halka. Satır bir [AppCard]'dır (düğme + "seçili" anlamı).
  Widget _buildPresetOption({
    required int index,
    required String key,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final accent = AppTone.primary.ink(p);
    final selected = _selectedPreset == key;
    return StaggeredEntry(
      index: index,
      child: AppCard(
        selected: selected,
        padding: const EdgeInsets.all(AppSpace.md),
        onTap: () => setState(() => _selectedPreset = key),
        child: Row(
          children: [
            if (!dialogLargeText(context)) ...[
              IconOrb(
                icon: icon,
                tone: selected ? AppTone.primary : AppTone.neutral,
                size: 40,
                shape: IconOrbShape.squircle,
              ),
              const SizedBox(width: AppSpace.md),
            ],
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
                  const SizedBox(height: AppSpace.xs),
                  Text(
                    subtitle,
                    style: th.bodySmall?.copyWith(color: p.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpace.sm),
            Icon(
              selected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: selected ? accent : p.textSecondary,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}

/// Oluşturulan geçiş linkinin sonuç kartı: başarı rozeti + açıklama + seçilebilir link + geçerlilik
/// bilgisi. Kartın kendisi `level: 2` + success tonu (hero); yalnız rozet [Pop] ile belirir.
///
/// Link tek bir `SelectableText`'tir (kopyalanabilir, uzun linkte satır kırar). Geçerlilik satırları
/// sunucunun döndürdüğü `expires_at` ve `max_uses` değerlerinden gelir; süresi geçmiş/ayrıştırılamamış
/// bir tarih için "Son geçerlilik" satırı gösterilmez (uydurma zaman yazılmaz).
class _GuestPassResult extends StatelessWidget {
  const _GuestPassResult({required this.pass, required this.doorName});

  final GuestPassRecord pass;
  final String doorName;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final ink = AppTone.success.ink(p);
    final expiry = pass.expiresAt;
    final facts = <(IconData, String)>[
      if (expiry.isAfter(DateTime.now()))
        (Icons.schedule_rounded, 'Son geçerlilik: ${formatDateTime(expiry)}'),
      if (pass.maxUses > 0)
        (Icons.touch_app_rounded, 'Kullanım hakkı: ${pass.maxUses}'),
    ];
    return AppCard(
      level: 2,
      tone: AppTone.success,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(
            child: Pop(
              child: IconOrb(
                icon: Icons.check_rounded,
                tone: AppTone.success,
                size: 56,
                glow: true,
              ),
            ),
          ),
          const SizedBox(height: AppSpace.md),
          Text(
            'Kurye veya misafiriniz bu linke tıklayarak $doorName kapısını açabilir.',
            textAlign: TextAlign.center,
            style: th.bodyMedium,
          ),
          const SizedBox(height: AppSpace.md),
          DecoratedBox(
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: p.border),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpace.xs),
                    child: Icon(
                      Icons.link_rounded,
                      size: 18,
                      color: p.textSecondary,
                    ),
                  ),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
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
            ),
          ),
          for (final (icon, text) in facts)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 18, color: ink),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(child: Text(text, style: th.bodyMedium)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
