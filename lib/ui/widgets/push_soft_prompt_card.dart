import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/push_api.dart';
import 'package:site_kapi_kontrol/services/push_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/push_prefs_panel.dart' show PushPrefsPanelState;

/// Duyurular (gelen kutusu) ekranındaki "telefon bildirimini aç" yumuşak istem kartı (Platform Faz 3b-B, B8).
///
/// Yalnız şu koşulların HEPSİ sağlanınca görünür ([PushService.shouldShowSoftPrompt]): sunucu `push_available`,
/// bu cihaz push alabilir, kullanıcı bu cihazda henüz açmamış, işletim sistemi izni kalıcı reddedilmemiş ve kart
/// kapatılmamış. Aksi hâlde hiç yer kaplamaz.
/// - "Aç" AÇIK RIZADIR: izin bu anda, bağlam içinde istenir ve cihaz kaydedilir; sonuç kartta dürüstçe yazılır.
/// - "Şimdi değil" kartı bu kullanıcı için kalıcı olarak kapatır (Profil > Bildirim Tercihleri'nden açılabilir).
class PushSoftPromptCard extends StatefulWidget {
  const PushSoftPromptCard({super.key, required this.authService, required this.pushService});

  final AuthService authService;
  final PushService pushService;

  @override
  State<PushSoftPromptCard> createState() => PushSoftPromptCardState();
}

class PushSoftPromptCardState extends State<PushSoftPromptCard> {
  bool _visible = false;
  bool _busy = false;
  String? _message;
  AppTone _tone = AppTone.info;
  bool _offerSettings = false;
  int _token = 0;

  static const String title = 'Yeni duyuruları telefonunuzdan öğrenin';
  static const String body =
      'Uygulama kapalıyken yeni duyuru gelince bu telefona bildirim gönderilsin mi? Bildirimde varsayılan olarak '
      'duyurunun ayrıntısı yer almaz; dilediğiniz zaman Profil > Bildirim Tercihleri\'nden kapatabilirsiniz.';

  @override
  void initState() {
    super.initState();
    _listen(widget.pushService);
    unawaited(_check());
  }

  @override
  void didUpdateWidget(PushSoftPromptCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.pushService, widget.pushService)) {
      _unlisten(oldWidget.pushService);
      _listen(widget.pushService);
    }
    if (!identical(oldWidget.authService, widget.authService) ||
        !identical(oldWidget.pushService, widget.pushService)) {
      _visible = false;
      _message = null;
      _busy = false;
      unawaited(_check());
    }
  }

  @override
  void dispose() {
    ++_token;
    _unlisten(widget.pushService);
    super.dispose();
  }

  void _listen(PushService service) {
    service.changes.addListener(_onChanged);
    service.startState.addListener(_onChanged);
  }

  void _unlisten(PushService service) {
    service.changes.removeListener(_onChanged);
    service.startState.removeListener(_onChanged);
  }

  void _onChanged() => unawaited(_check());

  Future<void> _check() async {
    // İşlem sürerken / sonucu gösterilirken kart kendiliğinden kaybolmaz.
    if (!mounted || _busy || _message != null) return;
    final token = ++_token;
    bool show;
    try {
      show = await widget.pushService.shouldShowSoftPrompt(widget.authService);
    } catch (_) {
      show = false;
    }
    if (!mounted || token != _token || _busy || _message != null) return;
    if (show != _visible) setState(() => _visible = show);
  }

  Future<void> _enable() async {
    if (_busy) return;
    final token = ++_token;
    setState(() => _busy = true);
    try {
      final outcome = await widget.pushService.enableOnThisDevice(widget.authService);
      if (!mounted || token != _token) return;
      setState(() {
        _busy = false;
        _offerSettings = false;
        switch (outcome) {
          case PushEnableOutcome.registered:
            _message = 'Telefon bildirimleri bu cihazda açıldı.';
            _tone = AppTone.success;
          case PushEnableOutcome.permissionDenied:
            _message =
                'Bildirim izni verilmedi. İzin verdiğinizde bildirimler bu cihaza gelmeye başlar; Profil > '
                'Bildirim Tercihleri\'nden yeniden deneyebilirsiniz.';
            _tone = AppTone.warning;
          case PushEnableOutcome.permissionPermanentlyDenied:
            _message = PushPrefsPanelState.settingsNote;
            _tone = AppTone.warning;
            _offerSettings = true;
          case PushEnableOutcome.pushUnavailable:
            _message = PushApi.pushUnavailableMessage;
            _tone = AppTone.warning;
          case PushEnableOutcome.tokenUnavailable:
            _message = PushPrefsPanelState.tokenUnavailableNote;
            _tone = AppTone.warning;
          case PushEnableOutcome.cleanupPending:
            _message = PushPrefsPanelState.cleanupPendingNote;
            _tone = AppTone.warning;
          case PushEnableOutcome.unsupported:
            _visible = false;
        }
      });
    } catch (e) {
      if (!mounted || token != _token) return;
      setState(() {
        _busy = false;
        _message = crmMessageOf(
          e,
          'Telefon bildirimi açılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.',
        );
        _tone = AppTone.danger;
      });
    }
  }

  Future<void> _dismiss() async {
    ++_token;
    setState(() => _visible = false);
    await widget.pushService.dismissSoftPrompt(widget.authService);
  }

  void _close() {
    ++_token;
    setState(() {
      _visible = false;
      _message = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final message = _message;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.lg),
      child: AppCard(
        key: const ValueKey<String>('push_soft_prompt'),
        padding: listCardPadding(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.notifications_active_rounded, size: 22, color: p.textSecondary),
                const SizedBox(width: AppSpace.md),
                Expanded(child: Text(title, style: th.titleSmall)),
              ],
            ),
            const SizedBox(height: AppSpace.sm),
            Text(body, style: th.bodySmall),
            const SizedBox(height: AppSpace.md),
            if (message != null) ...[
              InlineNotice(message: message, tone: _tone),
              const SizedBox(height: AppSpace.sm),
              Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.sm,
                children: [
                  if (_offerSettings)
                    OutlinedButton.icon(
                      key: const ValueKey<String>('push_prompt_settings'),
                      onPressed: () =>
                          unawaited(widget.pushService.openSettingsToEnable(widget.authService)),
                      icon: const Icon(Icons.settings_outlined, size: 18),
                      label: const Text('Telefon ayarlarını aç'),
                    ),
                  TextButton(
                    key: const ValueKey<String>('push_prompt_close'),
                    onPressed: _close,
                    child: const Text('Kapat'),
                  ),
                ],
              ),
            ] else
              Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.sm,
                children: [
                  FilledButton.icon(
                    key: const ValueKey<String>('push_prompt_enable'),
                    onPressed: _busy ? null : _enable,
                    icon: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.notifications_rounded, size: 18),
                    label: const Text('Aç'),
                  ),
                  TextButton(
                    key: const ValueKey<String>('push_prompt_dismiss'),
                    onPressed: _busy ? null : _dismiss,
                    child: const Text('Şimdi değil'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
