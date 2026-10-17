// Belge ayrıntı penceresi (yönetici ve kurul): bilgiler, sürümler ve eylemler (docs/PLATFORM_BELGELER.md A7, A13).
//
// - Yazma yetkisi olana: Aç / Kaydet, Yeni Sürüm Yükle, Düzenle, Sil (onaylı; yayındaki duyuruya ekliyse ikinci
//   onay), silinmişte Geri Yükle ve Kalıcı Sil (onaylı, kalan gün). Sürümler: indir, sil (en az bir sürüm kalır).
// - Kurul (salt okur): yalnız Aç / Kaydet; yükleyen adı ve yazma düğmeleri yoktur.
// - Aç / Kaydet: belge geçici dosyaya AKIŞLA indirilir ve işletim sistemi paylaşım menüsüne verilir; geçici kopya
//   sonra silinir ([downloadAndShareDocument]).
// - Hata ASLA "belge yok" demez: yükleme hatası pencerede "Tekrar Dene" ile kalır; eylem hatası üstte görünür.
// - Eylemler çift dokunuşa karşı korunur (`_busy`); yazma sonrası liste otomatik tazelenir ([onChanged]).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/document_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/document_api.dart';
import 'package:site_kapi_kontrol/services/document_file_share.dart';
import 'package:site_kapi_kontrol/services/document_picker.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/document_download_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/document_edit_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/document_upload_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/large_dialog_parts.dart';
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/helpers/istanbul_time.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart'
    show crmMessageOf;
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/helpers/retry_lock.dart';
import 'package:site_kapi_kontrol/ui/widgets/announcement_parts.dart'
    show isLongTitle;
import 'package:site_kapi_kontrol/ui/widgets/crm_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/document_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

class DocumentDetailDialog extends StatefulWidget {
  const DocumentDetailDialog({
    super.key,
    required this.scope,
    required this.service,
    required this.documentId,
    this.initialTitle = '',
    this.usage,
    this.onChanged,
    this.picker = const FilePickerDocumentPicker(),
    this.sharer,
  });

  final PeopleScope scope;
  final DocumentService service;
  final int documentId;

  /// Liste satırındaki başlık (yükleme sürerken pencere başlığı boş kalmasın).
  final String initialTitle;
  final DocumentUsage? usage;

  /// Yazma ya da bayat durum (404) sonrası çağrılır: liste yenilensin.
  final VoidCallback? onChanged;
  final DocumentPicker picker;
  final DocumentFileSharer? sharer;

  /// Kapanışta, listede gösterilecek kısa mesajla (silme / geri yükleme / kalıcı silme) döner; yoksa null.
  static Future<String?> show(
    BuildContext context, {
    required PeopleScope scope,
    required DocumentService service,
    required int documentId,
    String initialTitle = '',
    DocumentUsage? usage,
    VoidCallback? onChanged,
    DocumentPicker picker = const FilePickerDocumentPicker(),
    DocumentFileSharer? sharer,
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) => DocumentDetailDialog(
        scope: scope,
        service: service,
        documentId: documentId,
        initialTitle: initialTitle,
        usage: usage,
        onChanged: onChanged,
        picker: picker,
        sharer: sharer,
      ),
    );
  }

  @override
  State<DocumentDetailDialog> createState() => _DocumentDetailDialogState();
}

class _DocumentDetailDialogState extends State<DocumentDetailDialog> {
  DocumentDetail? _detail;
  bool _loading = false;
  String? _loadError;
  int _token = 0;

  bool _busy = false;
  String? _actionError;
  String? _notice;
  final RetryLock _retry = RetryLock();

  bool get _canWrite => widget.scope.canWrite;

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

  Future<void> _load({bool keepNotice = false}) async {
    if (!mounted) return;
    final token = ++_token;
    setState(() {
      _loading = true;
      _loadError = null;
      if (!keepNotice) _notice = null;
    });
    try {
      final detail = await widget.service.getManaged(
        widget.scope.siteCode,
        widget.documentId,
      );
      if (!mounted || token != _token) return;
      setState(() {
        _detail = detail;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || token != _token) return;
      setState(() {
        _loading = false;
        _loadError = crmMessageOf(
          e,
          'Belge yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
        );
      });
      if (e is ApiException && e.code == 'DOCUMENT_NOT_FOUND') {
        widget.onChanged?.call();
      }
    }
  }

  // --- Eylem altyapısı -------------------------------------------------------------------------

  /// Bir yazma eylemini çalıştırır: çift dokunuş korumalı, hata üstte görünür.
  Future<bool> _guarded(Future<void> Function() action, String failure) async {
    if (_busy || _retry.locked) return false;
    setState(() {
      _busy = true;
      _actionError = null;
      _notice = null;
    });
    try {
      await action();
      if (!mounted) return true;
      setState(() => _busy = false);
      return true;
    } catch (e) {
      if (!mounted) return false;
      final limited = _retry.lockIfRateLimited(e, () {
        if (mounted) setState(() {});
      });
      if (e is ApiException &&
          (e.statusCode == 404 || e.code == 'INVALID_STATE')) {
        // Belge başka yerden değişmiş / silinmiş: liste ve ayrıntı tazelenir.
        widget.onChanged?.call();
        unawaited(_load(keepNotice: true));
      }
      setState(() {
        _busy = false;
        _actionError = limited
            ? RetryLock.messageFor(e)
            : crmMessageOf(e, failure);
      });
      return false;
    }
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
    bool danger = true,
    IconData icon = Icons.help_outline_rounded,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AppDialog(
        title: title,
        icon: icon,
        tone: danger ? AppTone.danger : AppTone.warning,
        actions: [
          TextButton(
            key: const ValueKey<String>('document_confirm_cancel'),
            onPressed: () => popIfCurrent(dialogContext, false),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            key: const ValueKey<String>('document_confirm_ok'),
            style: danger
                ? ElevatedButton.styleFrom(
                    backgroundColor: AppTone.danger.b,
                    foregroundColor: Colors.white,
                  )
                : null,
            onPressed: () => popIfCurrent(dialogContext, true),
            child: Text(confirmLabel),
          ),
        ],
        child: Text(
          message,
          style: Theme.of(dialogContext).textTheme.bodyMedium,
        ),
      ),
    );
    return result ?? false;
  }

  // --- Eylemler --------------------------------------------------------------------------------

  Future<void> _open(BuildContext buttonContext, {int? version}) async {
    final detail = _detail;
    if (detail == null || _busy) return;
    setState(() => _busy = true);
    try {
      await downloadAndShareDocument(
        context,
        title: detail.title,
        originContext: buttonContext,
        sharer: widget.sharer,
        download: (onProgress, cancel) => widget.service.downloadManaged(
          widget.scope.siteCode,
          detail.id,
          version: version,
          fallbackName: detail.currentVersion?.fileName ?? 'belge',
          onProgress: onProgress,
          cancel: cancel,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _uploadVersion() async {
    final detail = _detail;
    if (detail == null || _busy) return;
    setState(() => _busy = true);
    DocumentSummary? uploaded;
    try {
      uploaded = await DocumentUploadDialog.show(
        context,
        scope: widget.scope,
        service: widget.service,
        picker: widget.picker,
        usage: widget.usage,
        versionOf: detail,
        onRefreshNeeded: () => widget.onChanged?.call(),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (uploaded == null || !mounted) return;
    widget.onChanged?.call();
    setState(
      () => _notice =
          'Yeni sürüm yüklendi. Sakinler artık güncel sürümü indirir.',
    );
    unawaited(_load(keepNotice: true));
  }

  Future<void> _edit() async {
    final detail = _detail;
    if (detail == null || _busy) return;
    setState(() => _busy = true);
    DocumentDetail? updated;
    try {
      updated = await DocumentEditDialog.show(
        context,
        scope: widget.scope,
        service: widget.service,
        document: detail,
        onRefreshNeeded: () {
          widget.onChanged?.call();
          if (mounted) unawaited(_load(keepNotice: true));
        },
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (updated == null || !mounted) return;
    widget.onChanged?.call();
    setState(() => _notice = 'Belge güncellendi.');
    unawaited(_load(keepNotice: true));
  }

  Future<void> _delete() async {
    final detail = _detail;
    if (detail == null || _busy) return;
    final ok = await _confirm(
      title: 'Belge silinsin mi?',
      message:
          'Belge Silinenler listesine taşınır ve sakinlere/kurula gösterilmez. Bir süre saklanır; bu sürede geri '
          'yükleyebilirsiniz, sonra kalıcı olarak silinir.',
      confirmLabel: 'Sil',
      icon: Icons.delete_outline_rounded,
    );
    if (!ok || !mounted) return;
    var forced = false;
    while (true) {
      var inUse = false;
      int? attachments;
      final removed = await _guarded(
        () async {
          try {
            await widget.service.deleteDocument(
              widget.scope.siteCode,
              detail.id,
              confirm: forced,
            );
          } on ApiException catch (e) {
            if (e.code != 'DOCUMENT_IN_USE' || forced) rethrow;
            // Yayındaki duyuruya ekli: ikinci, açık onay istenir.
            inUse = true;
            final count = e.payload?['attachments_count'];
            attachments = count is num ? count.toInt() : null;
          }
        },
        'Belge silinemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
      );
      if (!removed || !mounted) return;
      if (!inUse) break;
      final countText = (attachments ?? 0) > 0
          ? '$attachments yayındaki duyuruya'
          : 'yayındaki bir duyuruya';
      final again = await _confirm(
        title: 'Belge duyurularda kullanılıyor',
        message:
            'Bu belge $countText ekli. Silerseniz duyurularda "kullanılamıyor" görünür ve alıcılar dosyayı '
            'indiremez. Yine de silinsin mi?',
        confirmLabel: 'Yine de Sil',
        icon: Icons.warning_amber_rounded,
      );
      if (!again || !mounted) return;
      forced = true;
    }
    widget.onChanged?.call();
    popIfCurrent<String>(
      context,
      forced
          ? 'Belge silindi. Ekli olduğu duyurularda artık kullanılamıyor.'
          : 'Belge silindi. Silinenler listesinden geri yükleyebilirsiniz.',
    );
  }

  Future<void> _restore() async {
    final detail = _detail;
    if (detail == null || _busy) return;
    final ok = await _guarded(
      () => widget.service.restoreDocument(widget.scope.siteCode, detail.id),
      'Belge geri yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
    );
    if (!ok || !mounted) return;
    widget.onChanged?.call();
    popIfCurrent<String>(context, 'Belge geri yüklendi.');
  }

  Future<void> _purge() async {
    final detail = _detail;
    if (detail == null || _busy) return;
    final ok = await _confirm(
      title: 'Kalıcı olarak silinsin mi?',
      message:
          'Belge ve tüm sürümleri hemen ve kalıcı olarak silinir; geri alınamaz. Duyurulardaki ekleri de kalkar.',
      confirmLabel: 'Kalıcı Sil',
      icon: Icons.delete_forever_rounded,
    );
    if (!ok || !mounted) return;
    final done = await _guarded(
      () => widget.service.purgeDocument(widget.scope.siteCode, detail.id),
      'Belge kalıcı silinemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
    );
    if (!done || !mounted) return;
    widget.onChanged?.call();
    popIfCurrent<String>(context, 'Belge kalıcı olarak silindi.');
  }

  Future<void> _deleteVersion(DocumentVersion version) async {
    final detail = _detail;
    if (detail == null || _busy) return;
    final ok = await _confirm(
      title: 'v${version.versionNo} sürümü silinsin mi?',
      message:
          'Bu sürümün dosyası hemen ve kalıcı olarak silinir; geri alınamaz. '
          '${version.isCurrent ? 'Güncel sürüm silinirse bir önceki sürüm güncel olur.' : ''}',
      confirmLabel: 'Sürümü Sil',
      icon: Icons.delete_outline_rounded,
    );
    if (!ok || !mounted) return;
    final done = await _guarded(
      () => widget.service.deleteVersion(
        widget.scope.siteCode,
        detail.id,
        version.versionNo,
      ),
      'Sürüm silinemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
    );
    if (!done || !mounted) return;
    widget.onChanged?.call();
    setState(() => _notice = 'v${version.versionNo} sürümü silindi.');
    unawaited(_load(keepNotice: true));
  }

  // --- Görünüm ---------------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    final title = (detail?.title ?? widget.initialTitle).trim();
    final Widget body;
    if (detail == null) {
      body = _loading || _loadError == null
          ? const DialogRowsSkeleton(rows: 2, caption: 'Belge yükleniyor...')
          : InlineNotice(message: _loadError!, onRetry: _load);
    } else {
      body = _buildBody(context, detail);
    }
    return PopScope(
      // Eylem sürerken geri tuşu pencereyi kapatmaz (yarım kalmış gibi görünmesin).
      canPop: !_busy,
      child: AppDialog(
        title: title.isEmpty ? 'Belge' : title,
        subtitle: widget.scope.siteName.isEmpty ? null : widget.scope.siteName,
        icon: Icons.description_rounded,
        actions: [
          TextButton(
            key: const ValueKey<String>('document_detail_close'),
            onPressed: _busy ? null : () => popIfCurrent<String>(context),
            child: const Text('Kapat'),
          ),
        ],
        child: body,
      ),
    );
  }

  Widget _buildBody(BuildContext context, DocumentDetail d) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final version = d.currentVersion;
    final deleted = d.isDeleted;
    final canWrite = _canWrite;
    final canOpen = !deleted || canWrite;
    final readyVersions = d.versions;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_actionError != null)
          CrmFormError(message: _actionError!, announce: true),
        if (_notice != null) ...[
          InlineNotice(
            key: const ValueKey<String>('document_detail_notice'),
            tone: AppTone.success,
            message: _notice!,
          ),
          const SizedBox(height: AppSpace.md),
        ],
        if (_loadError != null) ...[
          InlineNotice(message: _loadError!, onRetry: _load),
          const SizedBox(height: AppSpace.md),
        ],
        // Pencere başlığı en çok 3 satırdır; uzun başlık dar ekran + büyük yazıda kesilebilir: tam başlık burada.
        if (isLongTitle(d.title)) ...[
          SelectableText(
            d.title.trim(),
            key: const ValueKey<String>('document_full_title'),
            style: th.titleMedium,
          ),
          const SizedBox(height: AppSpace.sm),
        ],
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.xs,
          children: [
            DocumentCategoryChip(d.category),
            if (deleted) DocumentDeletedChip(daysUntilPurge: d.daysUntilPurge),
            InfoChip('Kitle: ${d.audienceSummary}'),
          ],
        ),
        const SizedBox(height: AppSpace.md),
        if (d.description.trim().isNotEmpty) ...[
          DialogPanel(
            child: Text(
              d.description.trim(),
              key: const ValueKey<String>('document_detail_description'),
              style: th.bodyMedium,
            ),
          ),
          const SizedBox(height: AppSpace.md),
        ],
        if (version != null) ...[
          CrmInfoLine(
            label: 'Dosya',
            value:
                '${version.fileName.isEmpty ? 'Dosya' : version.fileName}\n'
                '${documentFileLabel(version.mimeType, version.sizeBytes, version.fileName)}',
          ),
          const SizedBox(height: AppSpace.sm),
        ],
        CrmInfoLine(
          label: 'Güncelleme',
          value: formatIstanbulDateTime(d.updatedAt ?? d.createdAt),
        ),
        const SizedBox(height: AppSpace.sm),
        CrmInfoLine(label: 'İndirme', value: '${d.downloadCount}'),
        if ((d.uploadedByName ?? '').isNotEmpty) ...[
          const SizedBox(height: AppSpace.sm),
          CrmInfoLine(label: 'Yükleyen', value: d.uploadedByName!),
        ],
        if (canWrite && d.attachedAnnouncements.isNotEmpty) ...[
          const SizedBox(height: AppSpace.sm),
          CrmInfoLine(
            label: 'Duyuru ekleri',
            value: '${d.attachedAnnouncements.length} duyuruya ekli',
          ),
        ],
        const SizedBox(height: AppSpace.lg),
        if (canOpen && version != null)
          Builder(
            builder: (buttonContext) => PrimaryActionButton(
              key: const ValueKey<String>('document_detail_open'),
              label: 'Aç / Kaydet',
              icon: Icons.open_in_new_rounded,
              onPressed: _busy ? null : () => unawaited(_open(buttonContext)),
            ),
          ),
        if (canWrite && !deleted) ...[
          const SizedBox(height: AppSpace.sm),
          PrimaryActionButton(
            key: const ValueKey<String>('document_detail_new_version'),
            label: 'Yeni Sürüm Yükle',
            icon: Icons.upgrade_rounded,
            variant: AppButtonVariant.tonal,
            onPressed: _busy ? null : _uploadVersion,
          ),
          const SizedBox(height: AppSpace.sm),
          PrimaryActionButton(
            key: const ValueKey<String>('document_detail_edit'),
            label: 'Düzenle',
            icon: Icons.edit_rounded,
            variant: AppButtonVariant.outline,
            onPressed: _busy ? null : _edit,
          ),
          const SizedBox(height: AppSpace.sm),
          PrimaryActionButton(
            key: const ValueKey<String>('document_detail_delete'),
            label: 'Sil',
            icon: Icons.delete_outline_rounded,
            tone: AppTone.danger,
            variant: AppButtonVariant.outline,
            onPressed: (_busy || _retry.locked) ? null : _delete,
          ),
        ],
        if (canWrite && deleted) ...[
          const SizedBox(height: AppSpace.sm),
          PrimaryActionButton(
            key: const ValueKey<String>('document_detail_restore'),
            label: 'Geri Yükle',
            icon: Icons.restore_from_trash_rounded,
            variant: AppButtonVariant.tonal,
            onPressed: (_busy || _retry.locked) ? null : _restore,
          ),
          const SizedBox(height: AppSpace.sm),
          PrimaryActionButton(
            key: const ValueKey<String>('document_detail_purge'),
            label: 'Kalıcı Sil',
            icon: Icons.delete_forever_rounded,
            tone: AppTone.danger,
            variant: AppButtonVariant.outline,
            onPressed: (_busy || _retry.locked) ? null : _purge,
          ),
        ],
        if (readyVersions.isNotEmpty) ...[
          const SizedBox(height: AppSpace.xl),
          const DialogSectionTitle(
            icon: Icons.history_rounded,
            title: 'Sürümler',
            tone: AppTone.info,
          ),
          const SizedBox(height: AppSpace.sm),
          for (final v in readyVersions) ...[
            Builder(
              builder: (tileContext) => DocumentVersionTile(
                key: ValueKey<String>('document_version_${v.versionNo}'),
                version: v,
                busy: _busy,
                onDownload: canOpen
                    ? () => unawaited(_open(tileContext, version: v.versionNo))
                    : null,
                onDelete: canWrite && !deleted && readyVersions.length > 1
                    ? () => unawaited(_deleteVersion(v))
                    : null,
              ),
            ),
            const SizedBox(height: AppSpace.sm),
          ],
        ],
        if (!canWrite) ...[
          const SizedBox(height: AppSpace.sm),
          Text(
            'Yönetim kurulu üyesi olarak belgeyi yalnızca görüntüleyebilirsiniz.',
            style: th.bodySmall?.copyWith(color: p.textSecondary),
          ),
        ],
      ],
    );
  }
}
