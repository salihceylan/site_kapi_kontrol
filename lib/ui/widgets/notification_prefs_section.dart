import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/announcement.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

/// Profilde "Bildirim Tercihleri" bölümü (Platform Faz 3a): "E-posta ile duyuru al" anahtarı ve pasif
/// "Telefon bildirimi — Yakında…" satırı.
///
/// - Tercih sunucudan okunur; yüklenirken iskelet, hata olursa hata + "Tekrar Dene" (varsayılan bir anahtar
///   ASLA çizilmez: yanlış değeri doğruymuş gibi göstermesin).
/// - Anahtar değişince `PUT` gider; sürerken anahtar kilitlidir (çift dokunuş yok). Başarısızsa eski değere
///   DÖNER ve hata görünür kalır. Yanıt eski bir bölümü ezmez (jeton).
/// - Açıklama: kapalıyken normal duyurular e-postayla gelmez; ACİL duyurunun e-postası bu tercihten etkilenmez
///   (uygulamada her zaman görünür).
/// - Hesap değişince (yeni [authService]) yeniden yüklenir.
class NotificationPrefsSection extends StatefulWidget {
  const NotificationPrefsSection({super.key, required this.authService});

  final AuthService authService;

  @override
  State<NotificationPrefsSection> createState() => NotificationPrefsSectionState();
}

class NotificationPrefsSectionState extends State<NotificationPrefsSection> {
  NotificationPrefs? _prefs;
  bool _loading = false;
  bool _saving = false;
  String? _error;
  String? _saveError;
  int _token = 0;

  @override
  void initState() {
    super.initState();
    unawaited(reload());
  }

  @override
  void didUpdateWidget(NotificationPrefsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.authService, widget.authService)) {
      // Hesap değişti: eski hesabın tercihi yeni hesaba sızmasın.
      _prefs = null;
      _saving = false;
      _saveError = null;
      unawaited(reload());
    }
  }

  @override
  void dispose() {
    ++_token;
    super.dispose();
  }

  Future<void> reload() async {
    if (!mounted) return;
    final token = ++_token;
    setState(() {
      _loading = true;
      _error = null;
      // Sürmekte olan bir kayıt yanıtı bu jetonla yok sayılacağından kilit de kalkar.
      _saving = false;
    });
    try {
      final prefs = await widget.authService.getNotificationPreferences();
      if (!mounted || token != _token) return;
      setState(() {
        _prefs = prefs;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || token != _token) return;
      setState(() {
        _loading = false;
        _error = crmMessageOf(
          e,
          'Bildirim tercihleri yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
        );
      });
    }
  }

  Future<void> _setEmail(bool value) async {
    final before = _prefs;
    if (before == null || _saving) return;
    final token = ++_token;
    setState(() {
      _saving = true;
      _saveError = null;
      _prefs = before.copyWith(emailAnnouncements: value);
    });
    try {
      final saved = await widget.authService.setNotificationPreferences(
        emailAnnouncements: value,
      );
      if (!mounted || token != _token) return;
      setState(() {
        _prefs = saved;
        _saving = false;
      });
    } catch (e) {
      if (!mounted || token != _token) return;
      setState(() {
        _prefs = before;
        _saving = false;
        _saveError = crmMessageOf(
          e,
          'Tercih kaydedilemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final prefs = _prefs;
    final Widget body;
    if (prefs == null) {
      body = _loading || _error == null
          ? const ListSkeleton(rows: 1, inCard: true)
          : InlineNotice(message: _error!, onRetry: reload);
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[
            InlineNotice(message: _error!, onRetry: reload),
            const SizedBox(height: AppSpace.md),
          ],
          if (_saveError != null) ...[
            InlineNotice(message: _saveError!),
            const SizedBox(height: AppSpace.md),
          ],
          SwitchListTile(
            key: const ValueKey<String>('notification_email_switch'),
            contentPadding: EdgeInsets.zero,
            title: const Text('E-posta ile duyuru al'),
            subtitle: const Text(
              'Kapalıyken normal duyurular e-postayla gelmez. Acil duyuruların e-postası tercihinizden '
              'etkilenmez; uygulamada her zaman görünürler.',
            ),
            value: prefs.emailAnnouncements,
            onChanged: _saving ? null : _setEmail,
          ),
          const SizedBox(height: AppSpace.sm),
          MergeSemantics(
            child: Row(
              children: [
                Icon(Icons.phone_android_rounded, size: 20, color: p.textSecondary),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: Text(
                    'Telefon bildirimi',
                    style: th.bodyLarge?.copyWith(color: p.textSecondary),
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
                const Flexible(
                  child: StatusChip(
                    label: 'Yakında…',
                    tone: AppTone.neutral,
                    icon: Icons.schedule_rounded,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }
    return AppCard(
      padding: listCardPadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'Bildirim Tercihleri'),
          const SizedBox(height: AppSpace.xs),
          Text(
            'Duyuruları nasıl almak istediğinizi seçin.',
            style: th.bodySmall,
          ),
          const SizedBox(height: AppSpace.md),
          body,
        ],
      ),
    );
  }
}
