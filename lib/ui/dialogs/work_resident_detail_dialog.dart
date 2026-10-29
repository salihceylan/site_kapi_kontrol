// Sakin talep ayrıntısı (docs/PLATFORM_IS_TAKIBI.md): durum çizgisi (yalnız herkese açık olaylar), fotoğraf ekleri
// (görüntüle / ekle / KENDİ yüklediğini sil), yorum yazma ve KENDİ `yeni` talebini iptal. Açılışta `seen` çağrılır
// (rozet söner). Öncelik, atanan adı ve iç notlar sakine gösterilmez (sunucu da göndermez).
//
// Çift gönderim: yorum / iptal / fotoğraf işlemi sürerken düğmeler kapalıdır ve geri tuşu pencereyi kapatmaz. Hata
// pencerenin içinde kalır, metin korunur; 429'da düğmeler `Retry-After` süresince kilitlenir. Fotoğraflar talep
// açıkken ve sınırın (4) altındayken eklenir; yüklenemeyen fotoğraf dürüstçe bildirilir. Pencere değişiklik
// olduysa `true` ile kapanır (liste yenilenir).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/work_tracking_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/work_attachment_picker.dart';
import 'package:site_kapi_kontrol/services/work_attachment_upload.dart';
import 'package:site_kapi_kontrol/services/work_tracking_api.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/a11y_announce.dart';
import 'package:site_kapi_kontrol/ui/helpers/date_input.dart'
    show formatCrmDate;
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/helpers/istanbul_time.dart';
import 'package:site_kapi_kontrol/ui/helpers/retry_lock.dart';
import 'package:site_kapi_kontrol/ui/views/work_detail_controllers.dart';
import 'package:site_kapi_kontrol/ui/widgets/crm_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/work_attachment_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/work_tracking_parts.dart';

class WorkResidentDetailDialog extends StatefulWidget {
  const WorkResidentDetailDialog({
    super.key,
    required this.service,
    required this.item,
    this.picker = const FilePickerWorkPhotoPicker(),
  });

  final WorkTrackingService service;
  final WorkResidentItem item;

  /// Fotoğraf seçici (testlerde sahte).
  final WorkPhotoPicker picker;

  /// Pencere kapanınca listenin yenilenmesi gerekiyorsa (durum, yorum, görüldü, iptal, fotoğraf değişti) true döner.
  static Future<bool> show(
    BuildContext context, {
    required WorkTrackingService service,
    required WorkResidentItem item,
    WorkPhotoPicker picker = const FilePickerWorkPhotoPicker(),
  }) async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => WorkResidentDetailDialog(
        service: service,
        item: item,
        picker: picker,
      ),
    );
    return changed ?? false;
  }

  @override
  State<WorkResidentDetailDialog> createState() =>
      _WorkResidentDetailDialogState();
}

class _WorkResidentDetailDialogState extends State<WorkResidentDetailDialog> {
  late final WorkResidentDetailController _c = WorkResidentDetailController(
    service: widget.service,
    initial: widget.item,
  );
  late final WorkAttachmentImageCache _cache = WorkAttachmentImageCache(
    (attachment) => widget.service.downloadAttachment(
      id: widget.item.id,
      attachmentId: attachment.id,
    ),
  );
  late final WorkAttachmentUploadController _upload =
      WorkAttachmentUploadController(
        service: widget.service,
        workItemId: widget.item.id,
      );
  final RetryLock _retry = RetryLock();

  /// Fotoğraf seçim / yükleme hatası (ek bölümünde gösterilir).
  String? _photoError;
  List<String> _pickNotes = const <String>[];
  bool _picking = false;

  /// Seçilen fotoğraflar hazırlanıyor (küçültme / JPEG / EXIF silme): "Fotoğraf hazırlanıyor...".
  bool _preparing = false;
  bool _pickedAny = false;

  /// 409 `LIMIT_REACHED` geldi ama ekranda 4'ten az fotoğraf var (başkası yüklüyor olabilir): "Fotoğraf Ekle" bu
  /// yükleme kuşağı boyunca kapalı; sonraki başarılı ayrıntı yüklemesinde açılır. Pencerede başka yükleme olmasa da
  /// kilit kalıcı olmasın diye [kWorkLimitRecheckDelay] sonra sessizce yeniden yüklenir ([_limitRecheck]).
  int? _limitBlockedAt;
  Timer? _limitRecheck;

  bool get _limitBlocked =>
      _limitBlockedAt != null && _limitBlockedAt == _c.loadGeneration;

  @override
  void initState() {
    super.initState();
    _upload.addListener(_onUpload);
    unawaited(_c.load());
  }

  @override
  void dispose() {
    _limitRecheck?.cancel();
    _upload.removeListener(_onUpload);
    _upload.dispose();
    if (_pickedAny) unawaited(widget.picker.release());
    // Çözülmüş fotoğraflar ImageCache'te kalmasın.
    _cache.dispose();
    _retry.dispose();
    _c.dispose();
    super.dispose();
  }

  void _onUpload() {
    if (mounted) setState(() {});
  }

  bool get _busy => _c.busy || _upload.busy || _picking;

  void _close() {
    if (_busy) return;
    popIfCurrent<bool>(context, _c.changed);
  }

  void _lockIfLimited(Object? error) {
    if (error == null) return;
    final limited = _retry.lockIfRateLimited(error, () {
      if (mounted) setState(() {});
    });
    if (limited && mounted) setState(() {});
  }

  void _afterWrite(bool ok, String success) {
    if (!mounted) return;
    if (ok) {
      announcePolite(context, success);
      return;
    }
    _lockIfLimited(_c.lastError);
  }

  Future<bool> _comment(String text) async {
    final ok = await _c.comment(text);
    _afterWrite(ok, 'Yorumunuz eklendi.');
    return ok;
  }

  Future<void> _cancel() async {
    if (_busy || _retry.locked) return;
    final go = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AppDialog(
        title: 'Talep iptal edilsin mi?',
        icon: Icons.cancel_outlined,
        tone: AppTone.warning,
        actions: [
          TextButton(
            key: const ValueKey<String>('work_cancel_keep'),
            onPressed: () => popIfCurrent(dialogContext, false),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            key: const ValueKey<String>('work_cancel_confirm'),
            onPressed: () => popIfCurrent(dialogContext, true),
            child: const Text('Talebi İptal Et'),
          ),
        ],
        child: Text(
          'Talebiniz iptal edilir ve yönetim tarafından işleme alınmaz. Bu işlem geri alınamaz.',
          style: Theme.of(dialogContext).textTheme.bodyMedium,
        ),
      ),
    );
    if (go != true || !mounted) return;
    final ok = await _c.cancel();
    _afterWrite(ok, 'Talebiniz iptal edildi.');
  }

  // --- Fotoğraflar ---

  Future<void> _addPhotos() async {
    if (_busy || _retry.locked) return;
    final remaining = kWorkAttachmentMax - _c.attachments.length;
    if (remaining <= 0) return;
    // Seçici kopyaları seçim sürerken pencere kapansa da silinsin: bayrak beklemeden ÖNCE.
    _pickedAny = true;
    final picker = widget.picker;
    setState(() {
      _picking = true;
      _photoError = null;
    });
    WorkPhotoSelection selection;
    try {
      selection = await picker.pick(
        maxCount: remaining,
        onPreparing: () {
          if (mounted) setState(() => _preparing = true);
        },
      );
    } catch (_) {
      if (!mounted) {
        unawaited(picker.release());
        return;
      }
      setState(() {
        _picking = false;
        _preparing = false;
        _photoError = 'Fotoğraf seçilemedi. Tekrar deneyin.';
      });
      return;
    }
    if (!mounted) {
      // Pencere seçim sürerken kapandı: sonradan oluşan kopyalar da silinsin.
      unawaited(picker.release());
      return;
    }
    final split = workSplitSelection(selection, remaining: remaining);
    final notes = split.notes;
    final valid = split.valid;
    setState(() {
      _picking = false;
      _preparing = false;
      _pickNotes = notes;
      _photoError = notes.isEmpty ? null : notes.join('\n');
    });
    if (valid.isEmpty) return;
    _upload.reset();
    await _upload.run(valid, onUploaded: _c.addAttachment);
    if (!mounted) return;
    _afterUpload(notes);
    unawaited(_syncAfterUpload());
  }

  /// Yükleme turundan sonra: içeriği kesin gitmemiş yarım kayıtlar silinir (talep başına 4 sınırını doldurmasın),
  /// ardından ayrıntı sunucuyla sessizce eşitlenir ("Fotoğraf eklendi" olayı, sonucu belirsiz kalan kayıt). Sınır
  /// (409 `LIMIT_REACHED`) geldiği hâlde ekranda 4'ten az fotoğraf varsa başkası yüklüyor olabilir: açıklayıcı ileti ve
  /// "Fotoğraf Ekle" sonraki yüklemeye dek kapalı.
  Future<void> _syncAfterUpload() async {
    final error = _upload.lastException;
    final limitHit = error is ApiException && error.code == 'LIMIT_REACHED';
    await _upload.discardPending();
    if (!mounted) return;
    await _c.load(silent: true);
    if (!mounted || !limitHit) return;
    if (_c.attachments.length < kWorkAttachmentMax) {
      setState(() {
        _limitBlockedAt = _c.loadGeneration;
        _photoError = <String>[
          ..._pickNotes,
          WorkAttachmentRules.limitBusyMessage,
        ].join('\n');
      });
      _armLimitRecheck();
    }
  }

  /// Sınır kilidi için tek seferlik zamanlayıcı: [kWorkLimitRecheckDelay] sonra ayrıntı sessizce yeniden yüklenir
  /// (başarılı yükleme kilidi açar). Yükleme başarısız olursa (ağ yok) kilit sürer ve aynı süreyle yeniden kurulur
  /// (kilit açılana ya da pencere kapanana dek); pencere kapanınca iptal edilir.
  void _armLimitRecheck() {
    _limitRecheck?.cancel();
    _limitRecheck = Timer(kWorkLimitRecheckDelay, () async {
      _limitRecheck = null;
      if (!mounted || !_limitBlocked) return;
      await _c.load(silent: true);
      if (!mounted) return;
      if (_limitBlocked) {
        _armLimitRecheck();
        return;
      }
      // Kilit açıldı: "başka fotoğraf yükleniyor olabilir" iletisi artık geçerli değil.
      if (_photoError?.contains(WorkAttachmentRules.limitBusyMessage) ?? false) {
        setState(() {
          _photoError = _pickNotes.isEmpty ? null : _pickNotes.join('\n');
        });
      }
    });
  }

  void _afterUpload(List<String> notes) {
    final failed = _upload.failedCount;
    final uploaded = _upload.results.where((r) => r.ok).length;
    if (uploaded > 0) {
      announcePolite(
        context,
        uploaded == 1 ? 'Fotoğraf eklendi.' : '$uploaded fotoğraf eklendi.',
      );
    }
    _lockIfLimited(_upload.lastException);
    final first = _upload.error;
    final String? text = failed == 0
        ? null
        : (failed == 1
              ? (first ?? 'Fotoğraf yüklenemedi.')
              : '$failed fotoğraf yüklenemedi. ${first ?? ''}'.trim());
    final lines = <String>[...notes, ?text];
    setState(() => _photoError = lines.isEmpty ? null : lines.join('\n'));
  }

  Future<void> _openPhoto(int index) async {
    final toDelete = await WorkPhotoViewer.show(
      context,
      attachments: _c.attachments,
      cache: _cache,
      initialIndex: index,
      // Sakin görünümü: yükleyen adı yok ("Siz" / "Yönetim").
      showUploader: false,
      inFlightAttachmentId: _upload.inFlightAttachmentId,
      // Yükleme sürerken silme yok (uçuştaki kayıt silinmesin).
      canDelete: (attachment) => !_upload.busy && _c.canDeleteAttachment(attachment),
    );
    if (!mounted) return;
    if (toDelete == null) {
      // Görüntüleyicide yeniden denenen küçük görseller önbellekten tazelensin.
      setState(() {});
      return;
    }
    // Silme onaylandı: önceki fotoğraf iletisi artık geçerli değil.
    setState(() => _photoError = null);
    final ok = await _c.deleteAttachment(toDelete);
    if (!mounted) return;
    if (ok) {
      _cache.evict(toDelete.id);
      announcePolite(context, 'Fotoğraf silindi.');
      // Olay çizgisi ("Fotoğraf kaldırıldı") sunucuyla eşitlenir.
      unawaited(_c.load(silent: true));
    } else {
      _lockIfLimited(_c.lastError);
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: ListenableBuilder(
        listenable: _c,
        builder: (context, _) => AppDialog(
          title: 'Talep Ayrıntısı',
          subtitle: _c.item.siteName.isEmpty ? null : _c.item.siteName,
          icon: workCategoryIcon(_c.item.category),
          actions: [
            TextButton(
              key: const ValueKey<String>('work_resident_detail_close'),
              onPressed: _busy ? null : _close,
              child: const Text('Kapat'),
            ),
          ],
          child: _content(context),
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    final th = Theme.of(context).textTheme;
    if (_c.moduleClosed) {
      return const InlineNotice(
        key: ValueKey<String>('work_detail_module_off'),
        tone: AppTone.warning,
        message: 'İş takibi bu site için kapalı.',
      );
    }
    if (_c.gone) {
      return const InlineNotice(
        key: ValueKey<String>('work_detail_gone'),
        message:
            'Talep bulunamadı ya da erişiminiz yok. Listeyi yenileyip tekrar deneyin.',
      );
    }
    final i = _c.item;
    final due = i.dueDate == null ? null : formatCrmDate(i.dueDate);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_c.loadError != null) ...[
          InlineNotice(message: _c.loadError!, onRetry: _c.load),
          const SizedBox(height: AppSpace.md),
        ],
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.xs,
          children: [
            WorkStatusChip(i.status),
            if (i.urgent) const WorkUrgentChip(),
          ],
        ),
        const SizedBox(height: AppSpace.md),
        Semantics(
          header: true,
          child: Text(
            i.title.isEmpty ? 'Başlıksız talep' : i.title,
            style: th.titleMedium,
          ),
        ),
        if (i.description.isNotEmpty) ...[
          const SizedBox(height: AppSpace.sm),
          Text(i.description, style: th.bodyMedium),
        ],
        const SizedBox(height: AppSpace.md),
        Wrap(
          spacing: AppSpace.xl,
          runSpacing: AppSpace.sm,
          children: [
            CrmInfoLine(label: 'Kategori', value: i.categoryText),
            CrmInfoLine(label: 'Konum', value: i.locationText),
            CrmInfoLine(
              label: 'Açılış',
              value: formatIstanbulDateTime(i.createdAt),
            ),
            CrmInfoLine(
              label: 'Son güncelleme',
              value: formatIstanbulDateTime(i.updatedAt),
            ),
            if (due != null) CrmInfoLine(label: 'Hedef tarih', value: due),
            if (!i.status.isTerminal)
              CrmInfoLine(
                label: 'Görevli',
                value: i.hasAssignee ? 'Atandı' : 'Henüz atanmadı',
              ),
          ],
        ),
        const SizedBox(height: AppSpace.lg),
        WorkAttachmentSection(
          attachments: _c.attachments,
          cache: _cache,
          onOpen: (index) => unawaited(_openPhoto(index)),
          loading: _c.loading && !_c.loaded,
          canAdd: _c.canAddAttachment,
          addLocked: _retry.locked || _picking || _c.busy || _limitBlocked,
          onAdd: () => unawaited(_addPhotos()),
          uploader: _upload,
          onCancelUpload: _upload.cancel,
          preparing: _preparing,
          // Sakin görünümü: yükleyen adı yok ("Siz" / "Yönetim").
          showUploader: false,
          error: _photoError ?? _c.attachmentError,
        ),
        const SizedBox(height: AppSpace.lg),
        Semantics(
          header: true,
          child: Text('Geçmiş', style: th.titleSmall),
        ),
        const SizedBox(height: AppSpace.sm),
        if (_c.loading && _c.events.isEmpty)
          const ListSkeleton(rows: 2, inCard: true)
        else
          WorkEventTimeline(events: _c.events, selfIsResident: true),
        if (_c.actionError != null)
          CrmFormError(message: _c.actionError!, announce: true),
        if (_c.loaded) ...[
          if (i.canComment) ...[
            const SizedBox(height: AppSpace.sm),
            WorkCommentBox(
              keyPrefix: 'work_resident_comment',
              label: 'Yönetime not yazın',
              sendLabel: 'Yorum Gönder',
              busy: _c.busy,
              locked: _retry.locked,
              onSubmit: _comment,
            ),
          ] else ...[
            const SizedBox(height: AppSpace.sm),
            const InlineNotice(
              key: ValueKey<String>('work_resident_no_comment'),
              tone: AppTone.info,
              message:
                  'Bu talep kapandığı ya da iptal edildiği için yeni yorum eklenemez.',
            ),
          ],
          if (i.canCancel) ...[
            const SizedBox(height: AppSpace.md),
            OutlinedButton.icon(
              key: const ValueKey<String>('work_resident_cancel'),
              onPressed: (_busy || _retry.locked) ? null : () => unawaited(_cancel()),
              icon: const Icon(Icons.cancel_outlined, size: 18),
              label: const Text('Talebi İptal Et'),
              style: dangerOutlineStyle(context),
            ),
          ],
        ],
      ],
    );
  }
}
