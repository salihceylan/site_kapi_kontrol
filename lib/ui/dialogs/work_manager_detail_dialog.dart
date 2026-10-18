// Yönetim talep ayrıntısı (yönetici / görevli / kurul; docs/PLATFORM_IS_TAKIBI.md): talep bilgisi, tüm olaylar
// (iç notlar dahil; kurulda yalnız herkese açık), durum / öncelik / atama / hedef tarih güncellemesi ve iç ya da
// herkese açık yorum.
//
// Yetki kararını SUNUCU verir; istemci yalnız gizler / gösterir:
// - Kurul ([canWrite] false): düğme YOK, "yalnızca görüntüleyebilirsiniz" notu; telefon ve iç not sunucudan gelmez.
// - Durum seçenekleri yalnız sunucunun bildirdiği `next_statuses`tir; kapandı / iptal talep değiştirilemez.
// - Görevli kendine al / bırak dışında atama yapamaz: atanabilir liste sunucudan geldiği gibidir.
// Yalnız DEĞİŞEN alanlar gönderilir; hata pencerenin içinde kalır, seçimler korunur; 409'da durum sunucuyla eşitlenir.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/vehicle_record.dart' show crmDateParam;
import 'package:site_kapi_kontrol/models/work_tracking_models.dart';
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
import 'package:site_kapi_kontrol/ui/widgets/work_tracking_parts.dart';

class WorkManagerDetailDialog extends StatefulWidget {
  const WorkManagerDetailDialog({
    super.key,
    required this.service,
    required this.site,
    required this.item,
  });

  final WorkTrackingService service;
  final WorkTrackingSite site;
  final WorkManagedItem item;

  /// Pencere kapanınca listenin yenilenmesi gerekiyorsa true döner.
  static Future<bool> show(
    BuildContext context, {
    required WorkTrackingService service,
    required WorkTrackingSite site,
    required WorkManagedItem item,
  }) async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          WorkManagerDetailDialog(service: service, site: site, item: item),
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
    initial: widget.item,
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

  @override
  void initState() {
    super.initState();
    _syncFromItem();
    _c.addListener(_onController);
    unawaited(_c.load());
    if (widget.site.canWrite && !widget.item.status.isTerminal) {
      unawaited(_c.loadAssignees());
    }
  }

  @override
  void dispose() {
    _c.removeListener(_onController);
    _retry.dispose();
    _due.dispose();
    _c.dispose();
    super.dispose();
  }

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
    if (_c.busy) return;
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
              onPressed: _c.busy ? null : _close,
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
            CrmInfoLine(label: 'Kategori', value: i.category.label),
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
            const InlineNotice(
              key: ValueKey<String>('work_manage_closed_note'),
              tone: AppTone.info,
              message:
                  'Kapanmış ya da iptal edilmiş talep değiştirilemez ve yorum alamaz.',
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
