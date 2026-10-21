import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/announcement.dart';
import 'package:site_kapi_kontrol/ui/widgets/web_push_tile.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/push_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/push_prefs_panel.dart';

/// Profilde "Bildirim Tercihleri" bölümü (Platform Faz 3a, Faz 4b): "E-posta ile duyuru al" ve "Borç hatırlatma
/// e-postaları" anahtarları ve pasif "Telefon bildirimi — Yakında…" satırı.
///
/// - Tercih sunucudan okunur; yüklenirken iskelet, hata olursa hata + "Tekrar Dene" (varsayılan bir anahtar
///   ASLA çizilmez: yanlış değeri doğruymuş gibi göstermesin).
/// - Anahtar değişince `PUT` gider (yalnız o anahtar; öteki değişmez); sürerken İKİ anahtar da kilitlidir (çift
///   dokunuş yok). Başarısızsa eski değere DÖNER ve hata görünür kalır. Yanıt eski bir bölümü ezmez (jeton).
/// - Açıklama: kapalıyken normal duyurular e-postayla gelmez; ACİL duyurunun e-postası bu tercihten etkilenmez
///   (uygulamada her zaman görünür). Borç hatırlatması kapalıyken yalnız o e-posta gelmez; duyurular ve borç
///   bilgileri uygulamada görünmeye devam eder.
/// - E-posta adresi e-postadaki "abonelikten çık" bağlantısıyla bastırılmışsa (`email_suppressed`; adres düzeyinde,
///   iki tercihi birden durdurur) İKİ anahtar da KAPALI gösterilir ve altında not BİR kez yazar. Kullanıcı
///   anahtarlardan birini AÇARSA bastırma kalkar (yanıt `email_suppressed:false`). Açtıktan sonra yanıt HÂLÂ
///   bastırılmış dönerse (dahili hesabın iletişim adresi) anahtar kapalı kalır ve hata değil BİLGİ olarak
///   "yönetici/destek ile açılabilir" yazılır. Alan yoksa (eski sunucu) eski davranış.
/// - Hesap değişince (yeni [authService]) yeniden yüklenir.
/// - Telefon bildirimi (Faz 3b-B): sunucu `push_available: true` dediğinde pasif "Yakında…" satırının yerine
///   [PushPrefsPanel] gelir (anahtar, başlık önizlemesi, sessiz saatler, cihazlarım, test bildirimi).
class NotificationPrefsSection extends StatefulWidget {
  const NotificationPrefsSection({super.key, required this.authService, this.pushService});

  final AuthService authService;

  /// Verilmezse uygulama genelindeki [PushService.instance] (testler sahtesini verir).
  final PushService? pushService;

  @override
  State<NotificationPrefsSection> createState() => NotificationPrefsSectionState();
}

/// Bölümdeki iki e-posta anahtarı.
enum _EmailPref { announcements, financeReminders }

class NotificationPrefsSectionState extends State<NotificationPrefsSection> {
  NotificationPrefs? _prefs;
  bool _loading = false;
  bool _saving = false;
  String? _error;
  String? _saveError;
  String? _saveInfo;
  int _token = 0;

  static const String suppressedNote = 'E-posta bildirimleri e-postadaki bağlantıyla durduruldu.';
  static const String supportNote =
      'Bu adres için e-posta bildirimleri yönetici/destek ile açılabilir.';

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
      _saveInfo = null;
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

  /// Tek bir e-posta tercihini yazar (duyuru VEYA borç hatırlatma). Yalnız o anahtar sunucuya gider ve yalnız
  /// o anahtar iyimser güncellenir: öteki anahtarın saklanan değeri ezilmez. Kilit, jeton ve geri alma iki
  /// anahtar için ortaktır (aynı anda tek kayıt).
  Future<void> _setPref(_EmailPref which, bool value) async {
    final before = _prefs;
    if (before == null || _saving) return;
    final token = ++_token;
    final announcements = which == _EmailPref.announcements;
    setState(() {
      _saving = true;
      _saveError = null;
      _saveInfo = null;
      // Açarken bastırma kalkacağı varsayılır (yanıt kesinleştirir); kapatırken bastırma durumu değişmez.
      _prefs = before.copyWith(
        emailAnnouncements: announcements ? value : null,
        emailFinanceReminders: announcements ? null : value,
        emailSuppressed: value ? false : null,
      );
    });
    try {
      final saved = await widget.authService.setNotificationPreferences(
        emailAnnouncements: announcements ? value : null,
        emailFinanceReminders: announcements ? null : value,
      );
      if (!mounted || token != _token) return;
      setState(() {
        _prefs = saved;
        _saving = false;
        // Açılmak istendi ama adres hâlâ bastırılmış: anahtar kapalı kalır, bu bir HATA değil bilgidir.
        final effective = announcements ? saved.emailAnnouncements : saved.emailFinanceReminders;
        _saveInfo = value && saved.emailSuppressed && !effective ? supportNote : null;
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
          if (_saveInfo != null) ...[
            InlineNotice(
              key: const ValueKey<String>('notification_support_note'),
              message: _saveInfo!,
              tone: AppTone.info,
            ),
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
            onChanged: _saving ? null : (v) => unawaited(_setPref(_EmailPref.announcements, v)),
          ),
          SwitchListTile(
            key: const ValueKey<String>('notification_finance_reminders_switch'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Borç hatırlatma e-postaları'),
            subtitle: const Text(
              'Aidat borcunuz için site yönetiminin gönderdiği hatırlatma e-postaları. Kapalıyken bu '
              'hatırlatmalar e-postayla gelmez; duyurular ve borç bilgileriniz uygulamada görünmeye devam eder.',
            ),
            value: prefs.emailFinanceReminders,
            onChanged: _saving ? null : (v) => unawaited(_setPref(_EmailPref.financeReminders, v)),
          ),
          // Bastırma adres düzeyindedir (e-postadaki bağlantı iki tercihi birden durdurur): not BİR kez görünür.
          if (prefs.emailSuppressed) ...[
            const SizedBox(height: AppSpace.xs),
            Row(
              key: const ValueKey<String>('notification_suppressed_note'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, size: 18, color: p.textSecondary),
                const SizedBox(width: AppSpace.sm),
                Expanded(child: Text(suppressedNote, style: th.bodySmall)),
              ],
            ),
          ],
          const SizedBox(height: AppSpace.sm),
          if (kIsWeb) ...[
            const Divider(height: AppSpace.lg),
            WebPushTile(authService: widget.authService),
          ],
          if (prefs.pushAvailable) ...[
            const Divider(height: AppSpace.lg),
            PushPrefsPanel(
              authService: widget.authService,
              pushService: widget.pushService ?? PushService.instance,
            ),
          ] else
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
            'Duyuruları ve borç hatırlatmalarını nasıl almak istediğinizi seçin.',
            style: th.bodySmall,
          ),
          const SizedBox(height: AppSpace.md),
          body,
        ],
      ),
    );
  }
}
