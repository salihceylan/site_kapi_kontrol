// Sakin talep ayrıntısı (docs/PLATFORM_IS_TAKIBI.md): durum çizgisi (yalnız herkese açık olaylar), yorum yazma ve
// KENDİ `yeni` talebini iptal. Açılışta `seen` çağrılır (rozet söner). Öncelik, atanan adı ve iç notlar sakine
// gösterilmez (sunucu da göndermez).
//
// Çift gönderim: yorum / iptal sürerken düğmeler kapalıdır ve geri tuşu pencereyi kapatmaz. Hata pencerenin içinde
// kalır, metin korunur; 429'da düğme `Retry-After` süresince kilitlenir. Pencere değişiklik olduysa `true` ile
// kapanır (liste yenilenir).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/work_tracking_models.dart';
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
import 'package:site_kapi_kontrol/ui/widgets/work_tracking_parts.dart';

class WorkResidentDetailDialog extends StatefulWidget {
  const WorkResidentDetailDialog({
    super.key,
    required this.service,
    required this.item,
  });

  final WorkTrackingService service;
  final WorkResidentItem item;

  /// Pencere kapanınca listenin yenilenmesi gerekiyorsa (durum, yorum, görüldü, iptal değişti) true döner.
  static Future<bool> show(
    BuildContext context, {
    required WorkTrackingService service,
    required WorkResidentItem item,
  }) async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => WorkResidentDetailDialog(service: service, item: item),
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
  final RetryLock _retry = RetryLock();

  @override
  void initState() {
    super.initState();
    unawaited(_c.load());
  }

  @override
  void dispose() {
    _retry.dispose();
    _c.dispose();
    super.dispose();
  }

  void _close() {
    if (_c.busy) return;
    popIfCurrent<bool>(context, _c.changed);
  }

  void _afterWrite(bool ok, String success) {
    if (!mounted) return;
    if (ok) {
      announcePolite(context, success);
      return;
    }
    final error = _c.lastError;
    if (error != null) {
      _retry.lockIfRateLimited(error, () {
        if (mounted) setState(() {});
      });
      if (_retry.locked) setState(() {});
    }
  }

  Future<bool> _comment(String text) async {
    final ok = await _c.comment(text);
    _afterWrite(ok, 'Yorumunuz eklendi.');
    return ok;
  }

  Future<void> _cancel() async {
    if (_c.busy || _retry.locked) return;
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
            CrmInfoLine(label: 'Kategori', value: i.category.label),
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
              onPressed: (_c.busy || _retry.locked) ? null : () => unawaited(_cancel()),
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
