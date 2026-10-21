import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/announcement.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/document_api.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/announcement_form_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/crm_confirm_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/large_dialog_parts.dart';
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/helpers/istanbul_time.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/helpers/retry_lock.dart';
import 'package:site_kapi_kontrol/ui/widgets/announcement_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/announcement_recipients_panel.dart';
import 'package:site_kapi_kontrol/ui/widgets/crm_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/document_attachments_list.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

/// Yönetici duyuru ayrıntı penceresi (Platform Faz 3a): tam metin, hedef, yayın zamanı, okundu
/// istatistiği, e-posta özeti ve (yazma yetkisi + yayınlanmış duyuruda) "Alıcılar" sekmesi.
///
/// Eylemler YALNIZ [PeopleScope.canWrite] iken vardır: Düzenle, Şimdi Yayınla (kitle önizlemesi + onay),
/// Geri Çek (onaylı), Sil (taslak / zamanlanmış kalıcı; yayınlanmış ve geri çekilmiş yumuşak silinir, onaylı). Kurul üyesi salt okur: ne yazma düğmesi
/// ne alıcı adları ne de oluşturan kişi görünür (sunucu verse bile).
///
/// Ayrıntı açılışta çekilir: yüklenirken iskelet, hata olursa "Tekrar Dene" (boş pencere ASLA çizilmez).
/// Her başarılı işlemden sonra pencere güncel veriyle yenilenir ve [onChanged] çağrılır (liste tazelenir).
/// Eylemler sürerken düğmeler kilitlidir (çift dokunuş koruması). Duruma uymayan işlemde (409
/// `INVALID_STATE`) mesaj gösterilir ve ayrıntı sunucudan yeniden okunur.
class AnnouncementManageDialog extends StatefulWidget {
  const AnnouncementManageDialog({
    super.key,
    required this.scope,
    required this.announcementId,
    this.initialTitle = '',
    this.onChanged,
    this.documentService,
  });

  final PeopleScope scope;
  final int announcementId;

  /// Ek indirme servisi (Faz 3b-A); verilmezse oturumdan kurulur (testlerde sahte verilir).
  final DocumentService? documentService;

  /// Ayrıntı gelene kadar başlıkta görünen ad (liste satırından).
  final String initialTitle;

  /// Başarılı her yazmadan sonra (ve silince) çağrılır.
  final VoidCallback? onChanged;

  static Future<void> show(
    BuildContext context, {
    required PeopleScope scope,
    required int announcementId,
    String initialTitle = '',
    VoidCallback? onChanged,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => AnnouncementManageDialog(
        scope: scope,
        announcementId: announcementId,
        initialTitle: initialTitle,
        onChanged: onChanged,
      ),
    );
  }

  @override
  State<AnnouncementManageDialog> createState() => _AnnouncementManageDialogState();
}

class _AnnouncementManageDialogState extends State<AnnouncementManageDialog> {
  late final DocumentService _documents =
      widget.documentService ?? DocumentService(authService: widget.scope.authService);
  AnnouncementDetail? _detail;
  bool _loading = false;
  String? _error;
  String? _actionError;
  String? _busyAction;
  bool _gone = false;

  // Düzenleme formu çift dokunuşta iki kez açılmasın.
  bool _opening = false;
  final RetryLock _retry = RetryLock();
  int _token = 0;
  int _tab = 0;
  bool _recipientsVisited = false;

  bool get _canWrite => widget.scope.canWrite;

  /// Sürmekte olan eylem (`publish`, `withdraw`, `delete`); null = boşta.
  bool get _busy => _busyAction != null;

  /// Eylem düğmeleri kilitli mi: eylem sürüyor ya da hız sınırı (429) sonrası bekleme var.
  bool get _actionsLocked => _busy || _retry.locked;

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
      final detail = await widget.scope.authService.getAnnouncement(
        widget.scope.siteCode,
        widget.announcementId,
      );
      if (!mounted || token != _token) return;
      setState(() {
        _detail = detail;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || token != _token) return;
      // 404: duyuru artık yok (başka bir yönetici silmiş). Eski içerik ve eylemler gösterilmez; liste tazelenir.
      final gone = e is ApiException && e.code == 'ANNOUNCEMENT_NOT_FOUND';
      setState(() {
        _loading = false;
        if (gone) {
          _detail = null;
          _gone = true;
          _actionError = null;
        }
        _error = gone
            ? 'Bu duyuru artık yok. Başka bir yönetici silmiş olabilir; liste yenilendi.'
            : crmMessageOf(
                e,
                'Duyuru yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
              );
      });
      if (gone) widget.onChanged?.call();
    }
  }

  /// Sunucudan dönen güncel duyuruyu uygular ve listeye haber verir.
  void _apply(AnnouncementDetail detail, String message) {
    if (!mounted) return;
    // Uçuştaki eski bir yükleme (yazmadan ÖNCE başlamış) bu yeni sonucu ezemesin.
    ++_token;
    setState(() {
      _detail = detail;
      _loading = false;
      _error = null;
      _actionError = null;
      // Yayın durumu değiştiyse alıcılar sekmesi anlamını yitirebilir.
      if (!(_canWrite && detail.hasAudience)) {
        _tab = 0;
        _recipientsVisited = false;
      }
    });
    widget.onChanged?.call();
    AppSnack.show(context, message, kind: AppSnackKind.success);
  }

  /// Eylem hatası: mesaj gösterilir; durum uyuşmazlığında ayrıntı yeniden okunur.
  void _fail(Object e, String fallback) {
    if (!mounted) return;
    final limited = _retry.lockIfRateLimited(e, () {
      if (mounted) setState(() {});
    });
    setState(() {
      _busyAction = null;
      _actionError = limited ? RetryLock.messageFor(e) : crmMessageOf(e, fallback);
    });
    if (e is ApiException && (e.code == 'INVALID_STATE' || e.code == 'ANNOUNCEMENT_NOT_FOUND')) {
      widget.onChanged?.call();
      unawaited(_load());
    }
  }

  Future<void> _edit() async {
    final detail = _detail;
    if (detail == null || _actionsLocked || _opening) return;
    _opening = true;
    final AnnouncementFormResult? result;
    try {
      result = await _showForm(detail);
    } finally {
      _opening = false;
    }
    if (result == null || !mounted) return;
    _apply(result.detail, result.message);
  }

  Future<AnnouncementFormResult?> _showForm(AnnouncementDetail detail) {
    return AnnouncementFormDialog.show(
      context,
      scope: widget.scope,
      announcement: detail,
      // Duyuru başka yerden değişmiş / silinmişse (409 / 404) form sonuçsuz kapansa da ayrıntı ve liste tazelenir.
      onRefreshNeeded: () {
        widget.onChanged?.call();
        if (mounted) unawaited(_load());
      },
    );
  }

  Future<void> _publishNow() async {
    final detail = _detail;
    if (detail == null || _actionsLocked) return;
    setState(() {
      _busyAction = 'publish';
      _actionError = null;
    });
    final auth = widget.scope.authService;
    final siteCode = widget.scope.siteCode;
    try {
      final preview = await auth.previewAnnouncementAudience(
        siteCode,
        AnnouncementTargetInput(
          type: detail.target.type,
          blockIds: detail.target.blockIds,
          apartmentIds: detail.target.apartmentIds,
        ),
        sendEmail: detail.sendEmail,
      );
      if (!mounted) return;
      if (preview.people == 0) {
        setState(() {
          _busyAction = null;
          _actionError = 'Seçilen hedefte duyuruyu alacak kimse yok. Önce hedefi düzenleyin.';
        });
        return;
      }
      final confirmed = await confirmAnnouncementAudience(
        context,
        preview: preview,
        scheduled: false,
        sendEmail: detail.sendEmail,
      );
      if (!mounted) return;
      if (!confirmed) {
        setState(() => _busyAction = null);
        return;
      }
      final updated = await auth.publishAnnouncement(siteCode, detail.id);
      if (!mounted) return;
      setState(() => _busyAction = null);
      _apply(
        updated,
        updated.recipientCount > 0
            ? 'Duyuru yayınlandı. ${updated.recipientCount} kişiye ulaştı.'
            : 'Duyuru yayınlandı.',
      );
    } catch (e) {
      _fail(e, 'Duyuru yayınlanamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.');
    }
  }

  Future<void> _withdraw() async {
    final detail = _detail;
    if (detail == null || _actionsLocked) return;
    final confirmed = await confirmCrmAction(
      context,
      title: 'Duyuruyu geri çek',
      message:
          'Geri çekilen duyuru sakinlerde kaybolur ve geri alınamaz. Daha önce gönderilen e-postalar geri alınamaz.',
      confirmLabel: 'Geri Çek',
      icon: Icons.undo_rounded,
      tone: AppTone.danger,
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _busyAction = 'withdraw';
      _actionError = null;
    });
    try {
      final updated = await widget.scope.authService.withdrawAnnouncement(
        widget.scope.siteCode,
        detail.id,
      );
      if (!mounted) return;
      setState(() => _busyAction = null);
      _apply(updated, 'Duyuru geri çekildi.');
    } catch (e) {
      _fail(e, 'Duyuru geri çekilemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.');
    }
  }

  Future<void> _delete() async {
    final detail = _detail;
    if (detail == null || _actionsLocked) return;
    final confirmed = await confirmCrmAction(
      context,
      title: 'Duyuruyu sil',
      message: switch (detail.status) {
        AnnouncementStatus.published =>
          'Duyuru sakinlerin listesinden ve bu listeden kaldırılır; henüz gönderilmemiş e-postalar iptal edilir. Kayıt yasal saklama süresince arka planda tutulur. Bu işlem geri alınamaz.',
        AnnouncementStatus.withdrawn =>
          'Geri çekilmiş duyuru bu listeden kaldırılır; kayıt yasal saklama süresince saklanır.',
        _ => 'Bu duyuru kalıcı olarak silinir. Silme geri alınamaz.',
      },
      confirmLabel: 'Sil',
      icon: Icons.delete_outline_rounded,
      tone: AppTone.danger,
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _busyAction = 'delete';
      _actionError = null;
    });
    try {
      await widget.scope.authService.deleteAnnouncement(widget.scope.siteCode, detail.id);
      if (!mounted) return;
      widget.onChanged?.call();
      AppSnack.show(context, 'Duyuru silindi.', kind: AppSnackKind.success);
      popIfCurrent(context);
    } catch (e) {
      _fail(e, 'Duyuru silinemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    final title = (detail?.title ?? widget.initialTitle).trim();
    final Widget body;
    if (detail == null) {
      body = _loading || _error == null
          ? const DialogRowsSkeleton(rows: 3, caption: 'Duyuru yükleniyor...')
          : InlineNotice(message: _error!, onRetry: _gone ? null : _load);
    } else {
      body = _buildDetail(context, detail);
    }
    return PopScope(
      // Eylem (yayınla / geri çek / sil) sürerken pencere kapanmaz: sonuç listeye yansıtılabilsin.
      canPop: !_busy,
      child: AppDialog(
        title: title.isEmpty ? 'Duyuru' : title,
        subtitle: widget.scope.siteName.isEmpty ? null : widget.scope.siteName,
        icon: Icons.campaign_rounded,
        actions: [
          TextButton(
            onPressed: _busy ? null : () => popIfCurrent(context),
            child: const Text('Kapat'),
          ),
        ],
        child: body,
      ),
    );
  }

  Widget _buildDetail(BuildContext context, AnnouncementDetail detail) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final showRecipients = _canWrite && detail.hasAudience;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null) ...[
          InlineNotice(message: _error!, onRetry: _load),
          const SizedBox(height: AppSpace.md),
        ],
        if (_actionError != null) ...[
          CrmFormError(message: _actionError!),
        ],
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.xs,
          children: [
            AnnouncementStatusChip(detail.status),
            if (detail.isUrgent) const UrgentChip(),
            if (detail.sendEmail) const InfoChip('E-posta da gönderilir'),
          ],
        ),
        const SizedBox(height: AppSpace.md),
        if (showRecipients) ...[
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: [
              ChoiceChip(
                key: const ValueKey<String>('announcement_tab_detail'),
                avatar: const Icon(Icons.article_rounded, size: 18),
                label: const Text('Ayrıntılar'),
                selected: _tab == 0,
                onSelected: (_) => setState(() => _tab = 0),
              ),
              ChoiceChip(
                key: const ValueKey<String>('announcement_tab_recipients'),
                avatar: const Icon(Icons.groups_2_rounded, size: 18),
                label: const Text('Alıcılar'),
                selected: _tab == 1,
                onSelected: (_) => setState(() {
                  _tab = 1;
                  _recipientsVisited = true;
                }),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
        ],
        // Alıcılar sekmesi bir kez açılınca durumunu (süzgeç, arama, liste) korur.
        Offstage(
          offstage: _tab != 0,
          child: _buildOverview(context, detail, th, p),
        ),
        if (showRecipients && _recipientsVisited)
          Offstage(
            offstage: _tab != 1,
            child: AnnouncementRecipientsPanel(
              key: ValueKey<String>('announcement_recipients_${detail.id}'),
              scope: widget.scope,
              announcementId: detail.id,
              readCount: detail.stats.read ?? 0,
              unreadCount: detail.stats.unread ?? 0,
              sendEmail: detail.sendEmail,
            ),
          ),
      ],
    );
  }

  Widget _buildOverview(BuildContext context, AnnouncementDetail detail, TextTheme th, AppPalette p) {
    final secondary = th.bodyMedium?.copyWith(color: p.textSecondary);
    final emailSummary = detail.stats.email.summary;
    final createdBy = (detail.createdByName ?? '').trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Pencere başlığı en çok 3 satır gösterir; uzun başlık (120 karaktere kadar) 2,0 yazıda kesilebilir:
        // tam başlık gövdenin başında da bulunur.
        if (isLongTitle(detail.title)) ...[
          DialogPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const DialogSectionTitle(icon: Icons.title_rounded, title: 'Başlık'),
                const SizedBox(height: AppSpace.md),
                SelectableText(
                  detail.title.trim(),
                  key: const ValueKey<String>('announcement_full_title'),
                  style: th.titleSmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.md),
        ],
        DialogPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const DialogSectionTitle(icon: Icons.article_rounded, title: 'Metin'),
              const SizedBox(height: AppSpace.md),
              Text(detail.body.trim().isEmpty ? 'Metin yok.' : detail.body, style: th.bodyMedium),
              if (detail.status == AnnouncementStatus.published && detail.editedAt != null) ...[
                const SizedBox(height: AppSpace.sm),
                Text(
                  detail.editCount > 1
                      ? 'Son düzenleme: ${formatIstanbulDateTime(detail.editedAt)} (${detail.editCount} kez düzenlendi)'
                      : 'Düzenlendi: ${formatIstanbulDateTime(detail.editedAt)}',
                  style: th.bodySmall,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpace.md),
        DialogPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const DialogSectionTitle(
                icon: Icons.flag_rounded,
                title: 'Hedef ve yayın',
                tone: AppTone.info,
              ),
              const SizedBox(height: AppSpace.md),
              CrmInfoLine(label: 'Hedef', value: detail.target.summary()),
              const SizedBox(height: AppSpace.sm),
              CrmInfoLine(label: 'Yayın', value: _publishText(detail)),
              if (_canWrite && createdBy.isNotEmpty) ...[
                const SizedBox(height: AppSpace.sm),
                CrmInfoLine(label: 'Oluşturan', value: createdBy),
              ],
            ],
          ),
        ),
        if (detail.attachments.isNotEmpty) ...[
          const SizedBox(height: AppSpace.md),
          DocumentAttachmentsList(
            attachments: detail.attachments,
            download: (attachment) => (onProgress, cancel) => _documents.downloadManaged(
              widget.scope.siteCode,
              attachment.documentId,
              fallbackName: attachment.fileName.isEmpty ? 'belge' : attachment.fileName,
              onProgress: onProgress,
              cancel: cancel,
            ),
          ),
        ],
        if (detail.hasAudience) ...[
          const SizedBox(height: AppSpace.md),
          _buildReadPanel(context, detail, th, secondary),
        ],
        if (detail.sendEmail && !detail.stats.email.hidden) ...[
          const SizedBox(height: AppSpace.md),
          DialogPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const DialogSectionTitle(
                  icon: Icons.email_rounded,
                  title: 'E-posta',
                  tone: AppTone.info,
                ),
                const SizedBox(height: AppSpace.sm),
                Text(
                  detail.hasAudience
                      ? (emailSummary ?? 'E-posta gönderimi henüz başlamadı.')
                      : 'Yayınlandığında e-postası olan alıcılara da gönderilir.',
                  key: const ValueKey<String>('announcement_email_summary'),
                  style: th.bodyMedium,
                ),
              ],
            ),
          ),
        ],
        if (_canWrite) ...[
          const SizedBox(height: AppSpace.lg),
          ..._buildActions(detail),
        ],
      ],
    );
  }

  Widget _buildReadPanel(
    BuildContext context,
    AnnouncementDetail detail,
    TextTheme th,
    TextStyle? secondary,
  ) {
    final total = detail.stats.recipients > 0 ? detail.stats.recipients : detail.recipientCount;
    final int? read = detail.stats.recipients > 0 ? detail.stats.read : detail.readCount;
    final int? unread = detail.stats.recipients > 0
        ? detail.stats.unread
        : (read == null ? null : (total - read).clamp(0, total).toInt());
    // Kurul + küçük hedef (1-4 alıcı): sunucu sayıları gizler (tek bir daireyi ele vermesin). "0/3" YAZILMAZ.
    if (read == null || unread == null) {
      return DialogPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const DialogSectionTitle(
              icon: Icons.mark_email_read_rounded,
              title: 'Okunma',
              tone: AppTone.success,
            ),
            const SizedBox(height: AppSpace.md),
            Tooltip(
              message: 'Gizli: küçük hedef',
              child: Text(
                'Okunma: —',
                key: const ValueKey<String>('announcement_read_hidden'),
                style: th.titleSmall,
              ),
            ),
            const SizedBox(height: AppSpace.sm),
            Text(
              'Gizli: küçük hedef. Beşten az alıcısı olan duyurularda okunma sayıları yönetim kuruluna gösterilmez.',
              style: secondary,
            ),
            const SizedBox(height: AppSpace.xs),
            Text('Alıcı sayısı: $total', style: secondary),
          ],
        ),
      );
    }
    final ratio = total <= 0 ? 0.0 : (read / total).clamp(0.0, 1.0);
    return DialogPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const DialogSectionTitle(
            icon: Icons.mark_email_read_rounded,
            title: 'Okunma',
            tone: AppTone.success,
          ),
          const SizedBox(height: AppSpace.md),
          Text(
            '$read/$total kişi okudu',
            key: const ValueKey<String>('announcement_read_ratio'),
            style: th.titleSmall,
          ),
          const SizedBox(height: AppSpace.sm),
          // Çubuk dekoratiftir; anlamı yukarıdaki metin ve bu etiket taşır (semanticsValue sayısal olmak
          // zorunda olduğundan LinearProgressIndicator'ın kendi anlamı kullanılmaz).
          Semantics(
            label: 'Okunma oranı: $total alıcıdan $read kişi okudu',
            child: ExcludeSemantics(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                child: LinearProgressIndicator(value: ratio, minHeight: 8),
              ),
            ),
          ),
          const SizedBox(height: AppSpace.sm),
          Text('Okuyan: $read • Okumayan: $unread', style: secondary),
        ],
      ),
    );
  }

  String _publishText(AnnouncementDetail detail) {
    switch (detail.status) {
      case AnnouncementStatus.draft:
        return 'Taslak, henüz yayınlanmadı.';
      case AnnouncementStatus.scheduled:
        return 'Zamanlanmış: ${formatIstanbulDateTime(detail.publishAt)} (İstanbul saati)';
      case AnnouncementStatus.published:
        return 'Yayınlandı: ${formatIstanbulDateTime(detail.publishedAt)}';
      case AnnouncementStatus.withdrawn:
        return 'Geri çekildi (yayın zamanı: ${formatIstanbulDateTime(detail.publishedAt)})';
      case AnnouncementStatus.unknown:
        return 'Durum bilinmiyor.';
    }
  }

  List<Widget> _buildActions(AnnouncementDetail detail) {
    final status = detail.status;
    final canEdit = status.isEditable || status == AnnouncementStatus.published;
    return [
      if (canEdit)
        PrimaryActionButton(
          key: const ValueKey<String>('announcement_action_edit'),
          label: 'Düzenle',
          icon: Icons.edit_rounded,
          variant: AppButtonVariant.tonal,
          onPressed: _actionsLocked ? null : _edit,
        ),
      if (status.isEditable) ...[
        const SizedBox(height: AppSpace.sm),
        PrimaryActionButton(
          key: const ValueKey<String>('announcement_action_publish'),
          label: 'Şimdi Yayınla',
          icon: Icons.campaign_rounded,
          loading: _busyAction == 'publish',
          onPressed: _actionsLocked ? null : _publishNow,
        ),
      ],
      if (status == AnnouncementStatus.published) ...[
        const SizedBox(height: AppSpace.sm),
        PrimaryActionButton(
          key: const ValueKey<String>('announcement_action_withdraw'),
          label: 'Geri Çek',
          icon: Icons.undo_rounded,
          variant: AppButtonVariant.outline,
          tone: AppTone.warning,
          onPressed: _actionsLocked ? null : _withdraw,
        ),
      ],
      if (status.isEditable || status == AnnouncementStatus.published || status == AnnouncementStatus.withdrawn) ...[
        const SizedBox(height: AppSpace.sm),
        PrimaryActionButton(
          key: const ValueKey<String>('announcement_action_delete'),
          label: 'Sil',
          icon: Icons.delete_outline_rounded,
          variant: AppButtonVariant.outline,
          tone: AppTone.danger,
          onPressed: _actionsLocked ? null : _delete,
        ),
      ],
    ];
  }
}
