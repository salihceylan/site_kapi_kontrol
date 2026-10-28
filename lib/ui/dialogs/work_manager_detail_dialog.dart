// Yönetim talep ayrıntısı (yönetici / görevli / kurul; docs/PLATFORM_IS_TAKIBI.md): talep bilgisi, fotoğraf ekleri
// (yükleyen adıyla; ekle / sil), tüm olaylar (iç notlar dahil; kurulda yalnız herkese açık), durum / öncelik /
// atama / hedef tarih güncellemesi ve iç ya da herkese açık yorum.
//
// Yetki kararını SUNUCU verir; istemci yalnız gizler / gösterir:
// - Kurul ([canWrite] false): düğme YOK (fotoğraf ekle / sil dahil), "yalnızca görüntüleyebilirsiniz" notu;
//   telefon ve iç not sunucudan gelmez.
// - Durum seçenekleri yalnız sunucunun bildirdiği `next_statuses`tir; kapandı / iptal talep değiştirilemez.
// - Görevli kendine al / bırak dışında atama yapamaz: atanabilir liste sunucudan geldiği gibidir; fotoğrafta
//   yalnız kendi yüklediğini ve yalnız açık talepte siler; yönetici her fotoğrafı, kapanmış talepte de siler.
// Yalnız DEĞİŞEN alanlar gönderilir; hata pencerenin içinde kalır, seçimler korunur; 409'da durum sunucuyla eşitlenir.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/vehicle_record.dart' show crmDateParam;
import 'package:site_kapi_kontrol/models/work_tracking_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/work_attachment_picker.dart';
import 'package:site_kapi_kontrol/services/work_attachment_upload.dart';
import 'package:site_kapi_kontrol/services/work_tracking_api.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/a11y_announce.dart';
import 'package:site_kapi_kontrol/ui/helpers/date_input.dart';
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/helpers/form_validation.dart';
import 'package:site_kapi_kontrol/ui/helpers/istanbul_time.dart';
import 'package:site_kapi_kontrol/ui/helpers/retry_lock.dart';
import 'package:site_kapi_kontrol/ui/views/work_detail_controllers.dart';
import 'package:site_kapi_kontrol/ui/widgets/crm_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/work_attachment_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/work_tracking_parts.dart';

class WorkManagerDetailDialog extends StatefulWidget {
  const WorkManagerDetailDialog({
    super.key,
    required this.service,
    required this.site,
    required this.item,
    this.picker = const FilePickerWorkPhotoPicker(),
  });

  final WorkTrackingService service;
  final WorkTrackingSite site;
  final WorkManagedItem item;

  /// Fotoğraf seçici (testlerde sahte).
  final WorkPhotoPicker picker;

  /// Pencere kapanınca listenin yenilenmesi gerekiyorsa true döner.
  static Future<bool> show(
    BuildContext context, {
    required WorkTrackingService service,
    required WorkTrackingSite site,
    required WorkManagedItem item,
    WorkPhotoPicker picker = const FilePickerWorkPhotoPicker(),
  }) async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => WorkManagerDetailDialog(
        service: service,
        site: site,
        item: item,
        picker: picker,
      ),
    );
    return changed ?? false;
  }

  @override
  State<WorkManagerDetailDialog> createState() =>
      _WorkManagerDetailDialogState();
}

class _WorkManagerDetailDialogState extends State<WorkManagerDetailDialog> {
  late final WorkManagerDetailController _c = WorkManagerDetailController(
    service: widget.service,
    siteCode: widget.site.code,
    canWrite: widget.site.canWrite,
    access: widget.site.access,
    initial: widget.item,
  );
  late final WorkAttachmentImageCache _cache = WorkAttachmentImageCache(
    (attachment) => widget.service.downloadAttachment(
      siteCode: widget.site.code,
      id: widget.item.id,
      attachmentId: attachment.id,
    ),
  );
  late final WorkAttachmentUploadController _upload =
      WorkAttachmentUploadController(
        service: widget.service,
        workItemId: widget.item.id,
        siteCode: widget.site.code,
      );
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final RetryLock _retry = RetryLock();
  final TextEditingController _due = TextEditingController();

  WorkStatus? _status;
  late WorkPriority _priority;
  int _assignee = 0;
  bool _internal = true;
  bool _synced = false;
  int _epoch = 0;

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
    _syncFromItem();
    _c.addListener(_onController);
    _upload.addListener(_onUpload);
    unawaited(_c.load());
    if (widget.site.canWrite && !widget.item.status.isTerminal) {
      unawaited(_c.loadAssignees());
    }
  }

  @override
  void dispose() {
    _limitRecheck?.cancel();
    _c.removeListener(_onController);
    _upload.removeListener(_onUpload);
    // Çözülmüş fotoğraflar ImageCache'te kalmasın.
    _cache.dispose();
    _upload.dispose();
    if (_pickedAny) unawaited(widget.picker.release());
    _retry.dispose();
    _due.dispose();
    _c.dispose();
    super.dispose();
  }

  void _onUpload() {
    if (mounted) setState(() {});
  }

  bool get _busy => _c.busy || _upload.busy || _picking;

  /// Ayrıntı ilk kez yüklenince seçimler sunucudaki güncel değerlere eşitlenir (liste özeti eskimiş olabilir).
  void _onController() {
    if (_c.loaded && !_synced) {
      _synced = true;
      _syncFromItem();
    }
  }

  void _syncFromItem() {
    final item = _c.item;
    _status = null;
    _priority = item.priority;
    _assignee = item.assignedTo?.userCode ?? 0;
    _due.text = formatDateField(item.dueDate);
    ++_epoch;
  }

  void _close() {
    if (_busy) return;
    popIfCurrent<bool>(context, _c.changed);
  }

  List<WorkStatus> get _statusOptions {
    final item = _c.item;
    return <WorkStatus>[
      item.status,
      for (final next in _c.nextStatuses)
        if (next != item.status) next,
    ];
  }

  /// Atama seçenekleri (0 = atanmamış). Mevcut atanan listede yoksa (silinmiş / listeden düşmüş) ayrıca eklenir.
  Map<int, String> get _assigneeOptions {
    final options = <int, String>{0: 'Atanmamış'};
    for (final assignee in _c.assignees) {
      options[assignee.userCode] = assignee.label;
    }
    final current = _c.item.assignedTo;
    if (current != null && !options.containsKey(current.userCode)) {
      options[current.userCode] = current.label;
    }
    return options;
  }

  Map<String, Object?> _changedFields() {
    final item = _c.item;
    final fields = <String, Object?>{};
    final status = _status;
    if (status != null &&
        status != item.status &&
        _statusOptions.contains(status)) {
      fields['status'] = status.apiValue;
    }
    if (_priority != item.priority) fields['priority'] = _priority.apiValue;
    final assignee = _assigneeOptions.containsKey(_assignee) ? _assignee : 0;
    if (assignee != (item.assignedTo?.userCode ?? 0)) {
      fields['assigned_to'] = assignee == 0 ? null : assignee;
    }
    final typed = _due.text.trim();
    final parsed = parseDateField(typed);
    final current = item.dueDate;
    final same = parsed == null
        ? current == null
        : (current != null &&
              current.year == parsed.year &&
              current.month == parsed.month &&
              current.day == parsed.day);
    // Geçersiz (yarım yazılmış) tarih değişiklik sayılmaz; kayıt anında doğrulama hatası gösterilir.
    if (typed.isEmpty || parsed != null) {
      if (!same) fields['due_date'] = parsed == null ? null : crmDateParam(parsed);
    }
    return fields;
  }

  Future<void> _save() async {
    if (_c.busy || _retry.locked) return;
    if (!validateForm(_formKey)) return;
    final fields = _changedFields();
    if (fields.isEmpty) return;
    FocusScope.of(context).unfocus();
    final ok = await _c.save(fields);
    if (!mounted) return;
    if (ok) {
      setState(_syncFromItem);
      announcePolite(context, 'Talep güncellendi.');
    } else {
      _lockIfLimited();
    }
  }

  void _lockIfLimited() {
    final error = _c.lastError;
    if (error == null) return;
    final limited = _retry.lockIfRateLimited(error, () {
      if (mounted) setState(() {});
    });
    if (limited) setState(() {});
  }

  Future<bool> _comment(String text) async {
    final ok = await _c.comment(text, internal: _internal);
    if (!mounted) return ok;
    if (ok) {
      announcePolite(context, _internal ? 'İç not eklendi.' : 'Yorum eklendi.');
    } else {
      _lockIfLimited();
    }
    return ok;
  }

  // --- Fotoğraflar ---

  void _lockIfLimitedBy(Object? error) {
    if (error == null) return;
    final limited = _retry.lockIfRateLimited(error, () {
      if (mounted) setState(() {});
    });
    if (limited && mounted) setState(() {});
  }

  Future<void> _addPhotos() async {
    if (_busy || _retry.locked || !_c.canAddAttachment) return;
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
    _lockIfLimitedBy(_upload.lastException);
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
      // Yönetim görünümü: yükleyenin adı gösterilir.
      showUploader: true,
      inFlightAttachmentId: _upload.inFlightAttachmentId,
      // Yükleme sürerken silme yok (uçuştaki kayıt silinmesin); kurulda canDeleteAttachment zaten false.
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
      _lockIfLimitedBy(_c.lastError);
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
          subtitle: widget.site.label,
          icon: workCategoryIcon(_c.item.category),
          actions: [
            TextButton(
              key: const ValueKey<String>('work_manager_detail_close'),
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
            'Talep bulunamadı ya da erişiminiz yok. Başka biri tarafından size görünmez hâle getirilmiş olabilir; listeyi yenileyin.',
      );
    }
    final i = _c.item;
    final due = i.dueDate == null ? null : formatCrmDate(i.dueDate);
    final phone = i.requester.phone;
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
            WorkPriorityChip(i.priority),
            if (i.residentUrgent) const WorkUrgentChip(label: 'Sakin: acil'),
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
              label: 'Talebi açan',
              value: i.requester.name.isEmpty ? '-' : i.requester.name,
            ),
            if (phone != null) CrmInfoLine(label: 'Telefon', value: phone),
            CrmInfoLine(
              label: 'Açılış',
              value: formatIstanbulDateTime(i.createdAt),
            ),
            CrmInfoLine(
              label: 'Son güncelleme',
              value: formatIstanbulDateTime(i.updatedAt),
            ),
            if (i.assignedTo != null)
              CrmInfoLine(
                label: 'Atanan',
                value: i.assignedTo!.name.isEmpty
                    ? 'İsimsiz kişi'
                    : i.assignedTo!.name,
              ),
            if (due != null) CrmInfoLine(label: 'Hedef tarih', value: due),
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
          error: _photoError ?? _c.attachmentError,
          showUploader: true,
        ),
        // Aynı fotoğraf başka kayıtta da kullanılmışsa uyarı (yalnız uyarı; hiçbir işlemi engellemez).
        WorkPhotoWarningList(warnings: _c.photoWarnings, attachments: _c.attachments),
        if (!widget.site.canWrite) ...[
          const SizedBox(height: AppSpace.md),
          const InlineNotice(
            key: ValueKey<String>('work_read_only_note'),
            tone: AppTone.info,
            icon: Icons.visibility_rounded,
            message:
                'Yönetim kurulu üyesi olarak talepleri yalnızca görüntüleyebilirsiniz. İç notlar ve sakinlerin iletişim bilgileri görünmez.',
          ),
        ],
        const SizedBox(height: AppSpace.lg),
        Semantics(
          header: true,
          child: Text('Geçmiş', style: th.titleSmall),
        ),
        const SizedBox(height: AppSpace.sm),
        if (_c.loading && _c.events.isEmpty)
          const ListSkeleton(rows: 2, inCard: true)
        else
          WorkEventTimeline(events: _c.events),
        if (_c.actionError != null)
          CrmFormError(message: _c.actionError!, announce: true),
        if (widget.site.canWrite && _c.loaded) ...[
          const SizedBox(height: AppSpace.sm),
          _manageSection(context),
          if (!i.status.isTerminal) ...[
            const SizedBox(height: AppSpace.lg),
            _commentSection(context),
          ] else ...[
            const SizedBox(height: AppSpace.md),
            InlineNotice(
              key: const ValueKey<String>('work_manage_closed_note'),
              tone: AppTone.info,
              message: widget.site.access == WorkSiteAccess.manager
                  ? 'Kapanmış ya da iptal edilmiş talep değiştirilemez, yorum ve fotoğraf alamaz; gerekirse '
                        'fotoğraflarını silebilirsiniz.'
                  : 'Kapanmış ya da iptal edilmiş talep değiştirilemez; yorum ve fotoğraf alamaz.',
            ),
          ],
        ],
      ],
    );
  }

  Widget _manageSection(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final i = _c.item;
    if (i.status.isTerminal) return const SizedBox.shrink();
    final statusOptions = _statusOptions;
    final selectedStatus = statusOptions.contains(_status) ? _status! : i.status;
    final assigneeOptions = _assigneeOptions;
    final selectedAssignee = assigneeOptions.containsKey(_assignee)
        ? _assignee
        : 0;
    final changed = _changedFields().isNotEmpty;
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text('Talebi yönet', style: th.titleSmall),
          ),
          const SizedBox(height: AppSpace.md),
          DropdownButtonFormField<WorkStatus>(
            key: ValueKey<String>('work_manage_status_$_epoch'),
            isExpanded: true,
            initialValue: selectedStatus,
            dropdownColor: p.surface,
            style: th.bodyMedium?.copyWith(color: p.text),
            decoration: const InputDecoration(
              labelText: 'Durum',
              prefixIcon: Icon(Icons.swap_horiz_rounded),
            ),
            items: [
              for (final status in statusOptions)
                DropdownMenuItem<WorkStatus>(
                  value: status,
                  child: Text(
                    status == i.status
                        ? '${status.label} (mevcut)'
                        : status.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: _c.busy
                ? null
                : (value) => setState(() => _status = value),
          ),
          const SizedBox(height: AppSpace.lg),
          DropdownButtonFormField<WorkPriority>(
            key: ValueKey<String>('work_manage_priority_$_epoch'),
            isExpanded: true,
            initialValue: _priority,
            dropdownColor: p.surface,
            style: th.bodyMedium?.copyWith(color: p.text),
            decoration: const InputDecoration(
              labelText: 'Öncelik',
              prefixIcon: Icon(Icons.flag_outlined),
            ),
            items: [
              for (final priority in WorkPriority.values)
                DropdownMenuItem<WorkPriority>(
                  value: priority,
                  child: Text(
                    priority.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: _c.busy
                ? null
                : (value) {
                    if (value != null) setState(() => _priority = value);
                  },
          ),
          const SizedBox(height: AppSpace.lg),
          DropdownButtonFormField<int>(
            key: ValueKey<String>(
              'work_manage_assignee_${_epoch}_${assigneeOptions.length}',
            ),
            isExpanded: true,
            initialValue: selectedAssignee,
            dropdownColor: p.surface,
            style: th.bodyMedium?.copyWith(color: p.text),
            decoration: const InputDecoration(
              labelText: 'Atanan kişi',
              prefixIcon: Icon(Icons.person_rounded),
            ),
            items: [
              for (final entry in assigneeOptions.entries)
                DropdownMenuItem<int>(
                  value: entry.key,
                  child: Text(
                    entry.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: _c.busy
                ? null
                : (value) => setState(() => _assignee = value ?? 0),
          ),
          if (_c.assigneesError != null) ...[
            const SizedBox(height: AppSpace.sm),
            InlineNotice(
              key: const ValueKey<String>('work_manage_assignees_error'),
              message: _c.assigneesError!,
              onRetry: _c.loadAssignees,
            ),
          ] else if (!_c.assigneesLoaded) ...[
            const SizedBox(height: AppSpace.xs),
            Text(
              'Atanabilir kişiler yükleniyor...',
              style: th.bodySmall?.copyWith(color: p.textSecondary),
            ),
          ],
          const SizedBox(height: AppSpace.lg),
          TextFormField(
            key: ValueKey<String>('work_manage_due_$_epoch'),
            controller: _due,
            enabled: !_c.busy,
            keyboardType: TextInputType.datetime,
            inputFormatters: const [DateInputFormatter()],
            autovalidateMode: AutovalidateMode.onUserInteraction,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Hedef tarih (isteğe bağlı)',
              hintText: 'GG.AA.YYYY',
              prefixIcon: const Icon(Icons.event_rounded),
              suffixIcon: _due.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Hedef tarihi temizle',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: _c.busy
                          ? null
                          : () => setState(() => _due.clear()),
                    ),
            ),
            validator: validateDateField,
          ),
          const SizedBox(height: AppSpace.lg),
          PrimaryActionButton(
            key: const ValueKey<String>('work_manage_save'),
            label: 'Değişiklikleri Kaydet',
            icon: Icons.save_rounded,
            loading: _c.busy,
            onPressed: (!changed || _c.busy || _retry.locked)
                ? null
                : () => unawaited(_save()),
          ),
        ],
      ),
    );
  }

  Widget _commentSection(BuildContext context) {
    final th = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text('Yorum ekle', style: th.titleSmall),
        ),
        const SizedBox(height: AppSpace.sm),
        WorkCommentBox(
          keyPrefix: 'work_manage_comment',
          label: _internal ? 'İç not' : 'Sakine görünür yorum',
          sendLabel: _internal ? 'İç Not Ekle' : 'Yorumu Gönder',
          busy: _c.busy,
          locked: _retry.locked,
          onSubmit: _comment,
          header: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.sm,
                children: [
                  ChoiceChip(
                    key: const ValueKey<String>('work_manage_comment_internal'),
                    avatar: const Icon(Icons.lock_outline_rounded, size: 18),
                    label: const Text('İç not'),
                    selected: _internal,
                    onSelected: _c.busy
                        ? null
                        : (_) => setState(() => _internal = true),
                  ),
                  ChoiceChip(
                    key: const ValueKey<String>('work_manage_comment_public'),
                    avatar: const Icon(Icons.public_rounded, size: 18),
                    label: const Text('Sakine görünür'),
                    selected: !_internal,
                    onSelected: _c.busy
                        ? null
                        : (_) => setState(() => _internal = false),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.xs),
              Text(
                _internal
                    ? 'İç not yalnız yönetimde görünür; talebi açan sakin göremez.'
                    : 'Bu yorumu talebi açan sakin de görür.',
                key: const ValueKey<String>('work_manage_comment_hint'),
                style: th.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
