import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/announcement.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/document_api.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/large_dialog_parts.dart';
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/helpers/istanbul_time.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart';
import 'package:site_kapi_kontrol/ui/helpers/retry_lock.dart';
import 'package:site_kapi_kontrol/ui/widgets/announcement_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/document_attachments_list.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

/// Sakinin duyuru okuma penceresi (Platform Faz 3a): tam metin, yayın zamanı ve "düzenlendi" notu.
///
/// Akış: pencere açılınca tam kayıt çekilir (`GET /app/announcements/:id`, OKUNDU YAZMAZ); yüklenince
/// ve okunmamışsa `POST .../read` çağrılır. Okundu yazımı BAŞARISIZ olursa sessiz yutulmaz: pencerede
/// "Tekrar Dene" ile görünür kalır ve duyuru listede okunmamış durur. Başarıda [onRead] çağrılır
/// (liste ve rozet güncellenir). Duyuru bu arada geri çekildiyse (404) hata gösterilir ve [onGone]
/// çağrılır (liste yenilensin).
///
/// [announcement] liste satırıdır (başlık ve işaretler hemen görünür); yalnız numarayla açılıyorsa
/// (şerit / bildirimden) boş başlıklı bir kayıt verilir.
class AnnouncementReadDialog extends StatefulWidget {
  const AnnouncementReadDialog({
    super.key,
    required this.authService,
    required this.announcement,
    this.onRead,
    this.onGone,
    this.documentService,
  });

  final AuthService authService;
  final ResidentAnnouncement announcement;

  /// Ek indirme servisi (Faz 3b-A); verilmezse oturumdan kurulur (testlerde sahte verilir).
  final DocumentService? documentService;

  /// Sunucu okundu yazımını onayladıktan sonra çağrılır.
  final ValueChanged<ResidentAnnouncement>? onRead;

  /// Duyuru artık yok / yayında değil (404).
  final VoidCallback? onGone;

  static Future<void> show(
    BuildContext context, {
    required AuthService authService,
    required ResidentAnnouncement announcement,
    ValueChanged<ResidentAnnouncement>? onRead,
    VoidCallback? onGone,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => AnnouncementReadDialog(
        authService: authService,
        announcement: announcement,
        onRead: onRead,
        onGone: onGone,
      ),
    );
  }

  @override
  State<AnnouncementReadDialog> createState() => _AnnouncementReadDialogState();
}

class _AnnouncementReadDialogState extends State<AnnouncementReadDialog> {
  late final DocumentService _documents =
      widget.documentService ?? DocumentService(authService: widget.authService);
  late ResidentAnnouncement _announcement = widget.announcement;
  bool _loaded = false;
  bool _loading = false;
  String? _error;
  bool _marking = false;
  String? _markError;
  final RetryLock _retry = RetryLock();
  int _token = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    ++_token;
    _retry.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    final token = ++_token;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await widget.authService.getMyAnnouncement(widget.announcement.id);
      if (!mounted || token != _token) return;
      setState(() {
        _announcement = detail;
        _loaded = true;
        _loading = false;
      });
      if (!detail.isRead) await _markRead();
    } catch (e) {
      if (!mounted || token != _token) return;
      setState(() {
        _loading = false;
        _error = crmMessageOf(
          e,
          'Duyuru yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
        );
      });
      if (e is ApiException && e.code == 'ANNOUNCEMENT_NOT_FOUND') widget.onGone?.call();
    }
  }

  /// Okundu yazar; hata görünür kalır ("Tekrar Dene").
  Future<void> _markRead() async {
    if (_marking || _retry.locked || !mounted) return;
    setState(() {
      _marking = true;
      _markError = null;
    });
    try {
      await widget.authService.markAnnouncementRead(_announcement.id);
      final updated = _announcement.copyWith(isRead: true);
      // Pencere bu arada kapanmış olsa bile okundu sunucuya yazıldı: liste ve rozet güncellenmeli.
      widget.onRead?.call(updated);
      if (!mounted) return;
      setState(() {
        _announcement = updated;
        _marking = false;
      });
    } catch (e) {
      if (!mounted) return;
      final limited = _retry.lockIfRateLimited(e, () {
        if (mounted) setState(() {});
      });
      setState(() {
        _marking = false;
        _markError = limited
            ? RetryLock.messageFor(e)
            : crmMessageOf(
                e,
                'Duyuru okundu olarak işaretlenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
              );
      });
      if (e is ApiException && e.code == 'ANNOUNCEMENT_NOT_FOUND') widget.onGone?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = _announcement;
    final title = a.title.trim();
    final Widget body;
    if (!_loaded) {
      body = _loading || _error == null
          ? const DialogRowsSkeleton(rows: 2, caption: 'Duyuru yükleniyor...')
          : InlineNotice(message: _error!, onRetry: _load);
    } else {
      body = _buildBody(context, a);
    }
    return AppDialog(
      title: title.isEmpty ? 'Duyuru' : title,
      subtitle: a.siteName.trim().isEmpty ? null : a.siteName.trim(),
      icon: a.isUrgent ? Icons.priority_high_rounded : Icons.campaign_rounded,
      tone: a.isUrgent ? AppTone.danger : AppTone.primary,
      actions: [
        TextButton(onPressed: () => popIfCurrent(context), child: const Text('Kapat')),
      ],
      child: body,
    );
  }

  Widget _buildBody(BuildContext context, ResidentAnnouncement a) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_markError != null) ...[
          InlineNotice(
            tone: AppTone.warning,
            message: _markError!,
            onRetry: (_marking || _retry.locked) ? null : _markRead,
          ),
          const SizedBox(height: AppSpace.md),
        ],
        // Pencere başlığı en çok 3 satırdır; uzun başlık 2,0 yazıda kesilebilir: tam başlık gövdede de bulunur.
        if (isLongTitle(a.title)) ...[
          SelectableText(
            a.title.trim(),
            key: const ValueKey<String>('announcement_full_title'),
            style: th.titleMedium,
          ),
          const SizedBox(height: AppSpace.sm),
        ],
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.xs,
          children: [
            if (a.isUrgent) const UrgentChip(),
            if (a.publishedAt != null) InfoChip(formatIstanbulDateTime(a.publishedAt)),
          ],
        ),
        const SizedBox(height: AppSpace.md),
        DialogPanel(
          child: Text(
            a.body.trim().isEmpty ? 'Duyuru metni yok.' : a.body,
            key: const ValueKey<String>('announcement_read_body'),
            style: th.bodyMedium,
          ),
        ),
        if (a.isEdited) ...[
          const SizedBox(height: AppSpace.sm),
          Text(
            'Düzenlendi: ${formatIstanbulDateTime(a.editedAt)}',
            key: const ValueKey<String>('announcement_edited_note'),
            style: th.bodySmall?.copyWith(color: p.textSecondary),
          ),
        ],
        if (a.attachments.isNotEmpty) ...[
          const SizedBox(height: AppSpace.md),
          DocumentAttachmentsList(
            attachments: a.attachments,
            download: (attachment) => (onProgress, cancel) => _documents.downloadAnnouncementAttachment(
              a.id,
              attachment.documentId,
              fallbackName: attachment.fileName.isEmpty ? 'belge' : attachment.fileName,
              onProgress: onProgress,
              cancel: cancel,
            ),
          ),
        ],
        if (_marking) ...[
          const SizedBox(height: AppSpace.sm),
          Text(
            'Okundu olarak işaretleniyor...',
            style: th.bodySmall?.copyWith(color: p.textSecondary),
          ),
        ],
      ],
    );
  }
}
