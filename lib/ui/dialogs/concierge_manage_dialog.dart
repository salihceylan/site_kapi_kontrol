// Yönetim konsiyerj talebi ayrıntısı (yönetici / görevli / kurul; docs/PLATFORM_REZERVASYON.md): talep bilgisi,
// durum ilerletme ve sakine görünür kısa not.
//
// Yetki kararını SUNUCU verir; istemci yalnız gizler / gösterir:
// - Kurul ([ReservationSite.canWrite] false): düğme YOK, "yalnızca görüntüleyebilirsiniz" notu; telefon sunucudan
//   gelmez.
// - Durum seçenekleri yalnız sunucunun bildirdiği `next_statuses`tir; tamamlanan / iptal edilen talep değiştirilemez.
// Yalnız DEĞİŞEN alanlar gönderilir; hata pencerenin içinde kalır, seçimler korunur; 409'da durum sunucuyla eşitlenir.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MaxLengthEnforcement;
import 'package:site_kapi_kontrol/models/reservation_models.dart';
import 'package:site_kapi_kontrol/services/reservation_api.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/a11y_announce.dart';
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/helpers/form_validation.dart';
import 'package:site_kapi_kontrol/ui/helpers/istanbul_time.dart';
import 'package:site_kapi_kontrol/ui/helpers/retry_lock.dart';
import 'package:site_kapi_kontrol/ui/views/reservation_controllers.dart';
import 'package:site_kapi_kontrol/ui/widgets/crm_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/reservation_parts.dart';

class ConciergeManageDialog extends StatefulWidget {
  const ConciergeManageDialog({
    super.key,
    required this.service,
    required this.site,
    required this.record,
  });

  final ReservationService service;
  final ReservationSite site;
  final ConciergeRecord record;

  /// Pencere kapanınca listenin yenilenmesi gerekiyorsa true döner.
  static Future<bool> show(
    BuildContext context, {
    required ReservationService service,
    required ReservationSite site,
    required ConciergeRecord record,
  }) async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ConciergeManageDialog(service: service, site: site, record: record),
    );
    return changed ?? false;
  }

  @override
  State<ConciergeManageDialog> createState() => _ConciergeManageDialogState();
}

class _ConciergeManageDialogState extends State<ConciergeManageDialog> {
  late final ConciergeManageController _c = ConciergeManageController(
    service: widget.service,
    siteCode: widget.site.code,
    canWrite: widget.site.canWrite,
    initial: widget.record,
  );
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final RetryLock _retry = RetryLock();
  final TextEditingController _note = TextEditingController();

  ConciergeStatus? _status;
  bool _synced = false;
  int _epoch = 0;

  @override
  void initState() {
    super.initState();
    _syncFromRecord();
    _c.addListener(_onController);
    unawaited(_c.load());
  }

  @override
  void dispose() {
    _c.removeListener(_onController);
    _retry.dispose();
    _note.dispose();
    _c.dispose();
    super.dispose();
  }

  /// Ayrıntı ilk kez yüklenince seçimler sunucudaki güncel değerlere eşitlenir (liste özeti eskimiş olabilir).
  void _onController() {
    if (_c.loaded && !_synced) {
      _synced = true;
      _syncFromRecord();
    }
  }

  void _syncFromRecord() {
    _status = null;
    _note.text = _c.request.staffNote ?? '';
    ++_epoch;
  }

  void _close() {
    if (_c.busy) return;
    popIfCurrent<bool>(context, _c.changed);
  }

  List<ConciergeStatus> get _statusOptions {
    final current = _c.request.status;
    return <ConciergeStatus>[
      current,
      for (final next in _c.nextStatuses)
        if (next != current) next,
    ];
  }

  bool get _statusChanged {
    final status = _status;
    return status != null &&
        status != _c.request.status &&
        _statusOptions.contains(status);
  }

  bool get _noteChanged => _note.text.trim() != (_c.request.staffNote ?? '');

  Future<void> _save() async {
    if (_c.busy || _retry.locked) return;
    if (!validateForm(_formKey)) return;
    if (!_statusChanged && !_noteChanged) return;
    FocusScope.of(context).unfocus();
    final ok = await _c.save(
      status: _statusChanged ? _status : null,
      noteChanged: _noteChanged,
      note: _note.text,
    );
    if (!mounted) return;
    if (ok) {
      setState(_syncFromRecord);
      announcePolite(context, 'Talep güncellendi.');
      return;
    }
    final error = _c.lastError;
    if (error != null) {
      final limited = _retry.lockIfRateLimited(error, () {
        if (mounted) setState(() {});
      });
      if (limited) setState(() {});
    }
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
          title: 'Konsiyerj Talebi',
          subtitle: widget.site.label,
          icon: conciergeCategoryIcon(_c.request.category),
          actions: [
            TextButton(
              key: const ValueKey<String>('cnc_manage_close'),
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
        key: ValueKey<String>('cnc_manage_module_off'),
        tone: AppTone.warning,
        message: 'Rezervasyon ve Konsiyerj bu site için kapalı.',
      );
    }
    if (_c.gone) {
      return const InlineNotice(
        key: ValueKey<String>('cnc_manage_gone'),
        message:
            'Talep bulunamadı ya da erişiminiz yok. Başka biri tarafından kaldırılmış olabilir; listeyi yenileyin.',
      );
    }
    final r = _c.request;
    final phone = r.requester?.phone;
    final apartment = r.apartment?.label.trim() ?? '';
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
          children: [ConciergeStatusChip(r.status)],
        ),
        const SizedBox(height: AppSpace.md),
        Semantics(header: true, child: Text(r.category.label, style: th.titleMedium)),
        if (r.note != null) ...[
          const SizedBox(height: AppSpace.sm),
          Text(r.note!, style: th.bodyMedium),
        ],
        const SizedBox(height: AppSpace.md),
        Wrap(
          spacing: AppSpace.xl,
          runSpacing: AppSpace.sm,
          children: [
            CrmInfoLine(
              label: 'Talebi açan',
              value: (r.requester?.name.trim().isEmpty ?? true) ? '-' : r.requester!.name,
            ),
            if (phone != null) CrmInfoLine(label: 'Telefon', value: phone),
            if (apartment.isNotEmpty) CrmInfoLine(label: 'Daire', value: apartment),
            if (r.requestedFor != null)
              CrmInfoLine(
                label: 'İstenen zaman',
                value: formatIstanbulDateTime(r.requestedFor),
              ),
            CrmInfoLine(label: 'Talep zamanı', value: formatIstanbulDateTime(r.createdAt)),
            CrmInfoLine(label: 'Son güncelleme', value: formatIstanbulDateTime(r.updatedAt)),
          ],
        ),
        if (!widget.site.canWrite) ...[
          const SizedBox(height: AppSpace.md),
          const ReservationReadOnlyNote(),
          if (r.staffNote != null) ...[
            const SizedBox(height: AppSpace.md),
            CrmInfoLine(label: 'Sakine görünen not', value: r.staffNote!),
          ],
        ],
        if (widget.site.canWrite && _c.loaded) ...[
          const SizedBox(height: AppSpace.lg),
          if (_c.actionError != null)
            CrmFormError(message: _c.actionError!, announce: true),
          if (r.status.isTerminal)
            const InlineNotice(
              key: ValueKey<String>('cnc_manage_closed_note'),
              tone: AppTone.info,
              message: 'Tamamlanmış ya da iptal edilmiş talep değiştirilemez.',
            )
          else
            _manageSection(context),
        ],
      ],
    );
  }

  Widget _manageSection(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final options = _statusOptions;
    final selected = options.contains(_status) ? _status! : _c.request.status;
    final changed = _statusChanged || _noteChanged;
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(header: true, child: Text('Talebi yönet', style: th.titleSmall)),
          const SizedBox(height: AppSpace.md),
          DropdownButtonFormField<ConciergeStatus>(
            key: ValueKey<String>('cnc_manage_status_$_epoch'),
            isExpanded: true,
            initialValue: selected,
            dropdownColor: p.surface,
            style: th.bodyMedium?.copyWith(color: p.text),
            decoration: const InputDecoration(
              labelText: 'Durum',
              prefixIcon: Icon(Icons.swap_horiz_rounded),
            ),
            items: [
              for (final status in options)
                DropdownMenuItem<ConciergeStatus>(
                  value: status,
                  child: Text(
                    status == _c.request.status ? '${status.label} (mevcut)' : status.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: _c.busy ? null : (value) => setState(() => _status = value),
          ),
          const SizedBox(height: AppSpace.lg),
          TextFormField(
            key: ValueKey<String>('cnc_manage_note_$_epoch'),
            controller: _note,
            enabled: !_c.busy,
            minLines: 2,
            maxLines: 4,
            maxLength: kConciergeStaffNoteMax,
            maxLengthEnforcement: MaxLengthEnforcement.none,
            buildCounter:
                (context, {required currentLength, required isFocused, maxLength}) =>
                    reservationCounter(context, _note.text.runes.length, kConciergeStaffNoteMax),
            textCapitalization: TextCapitalization.sentences,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Sakine görünür not',
              helperText: 'Talebi açan sakin bu notu görür. Boş bırakırsanız not silinir.',
              alignLabelWithHint: true,
            ),
            validator: (value) {
              final length = (value ?? '').trim().runes.length;
              return length > kConciergeStaffNoteMax
                  ? 'Not en çok $kConciergeStaffNoteMax karakter olabilir.'
                  : null;
            },
          ),
          const SizedBox(height: AppSpace.lg),
          PrimaryActionButton(
            key: const ValueKey<String>('cnc_manage_save'),
            label: 'Değişiklikleri Kaydet',
            icon: Icons.save_rounded,
            loading: _c.busy,
            onPressed: (!changed || _c.busy || _retry.locked) ? null : () => unawaited(_save()),
          ),
        ],
      ),
    );
  }
}
