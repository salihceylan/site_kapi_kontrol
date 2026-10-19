// Sözleşme ayrıntısı (Firma ve Sözleşme Takibi): tüm alanlar (tutar Türkçe para biçiminde, ödeme dönemi etiketiyle);
// yazma yetkisi olana "Düzenle" ve onaylı "Feshet" / "Yeniden etkinleştir".
//
// Pencere değişen sözleşmeyle kapanır (çağıran listeyi ve özeti tazeler); değişiklik yoksa null. Hata pencerenin
// içinde gösterilir; 404 / 409'da kullanıcıya listeyi yenilemesi söylenir.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/contract_models.dart';
import 'package:site_kapi_kontrol/services/contract_api.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/contract_form_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/large_dialog_parts.dart';
import 'package:site_kapi_kontrol/ui/helpers/date_input.dart' show formatDateField;
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/helpers/istanbul_time.dart';
import 'package:site_kapi_kontrol/ui/helpers/money.dart' show spokenMoneyText;
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart'
    show crmMessageOf;
import 'package:site_kapi_kontrol/ui/widgets/contract_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/crm_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

class ContractDetailDialog extends StatefulWidget {
  const ContractDetailDialog({
    super.key,
    required this.service,
    required this.siteCode,
    required this.contract,
    this.canWrite = false,
  });

  final ContractService service;
  final int siteCode;
  final Contract contract;
  final bool canWrite;

  /// Sözleşme değiştiyse (düzenleme / fesih / yeniden etkinleştirme) son haliyle, değişmediyse null döner.
  static Future<Contract?> show(
    BuildContext context, {
    required ContractService service,
    required int siteCode,
    required Contract contract,
    bool canWrite = false,
  }) {
    return showDialog<Contract>(
      context: context,
      builder: (_) => ContractDetailDialog(
        service: service,
        siteCode: siteCode,
        contract: contract,
        canWrite: canWrite,
      ),
    );
  }

  @override
  State<ContractDetailDialog> createState() => _ContractDetailDialogState();
}

class _ContractDetailDialogState extends State<ContractDetailDialog> {
  late Contract _contract = widget.contract;
  bool _changed = false;
  bool _busy = false;
  String? _error;

  void _close() => popIfCurrent<Contract>(context, _changed ? _contract : null);

  Future<void> _edit() async {
    if (_busy) return;
    final saved = await ContractFormDialog.show(
      context,
      service: widget.service,
      siteCode: widget.siteCode,
      contract: _contract,
    );
    if (saved == null || !mounted) return;
    setState(() {
      _contract = saved;
      _changed = true;
      _error = null;
    });
    AppSnack.show(context, 'Sözleşme güncellendi.', kind: AppSnackKind.success);
  }

  Future<void> _setStatus(ContractStatus next) async {
    if (_busy) return;
    final terminate = next == ContractStatus.feshedildi;
    final c = _contract;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AppDialog(
        title: terminate ? 'Sözleşme feshedilsin mi?' : 'Sözleşme yeniden etkinleştirilsin mi?',
        icon: terminate ? Icons.cancel_outlined : Icons.restart_alt_rounded,
        tone: terminate ? AppTone.danger : AppTone.primary,
        actions: [
          TextButton(
            key: const ValueKey<String>('contract_status_keep'),
            onPressed: () => popIfCurrent(dialogContext, false),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            key: const ValueKey<String>('contract_status_ok'),
            onPressed: () => popIfCurrent(dialogContext, true),
            child: Text(terminate ? 'Feshet' : 'Yeniden etkinleştir'),
          ),
        ],
        child: Text(
          terminate
              ? '"${c.displayTitle}" (${c.displayVendor}) feshedilmiş olarak işaretlenecek ve hatırlatmaları durur. '
                    'Gerekirse daha sonra yeniden etkinleştirebilirsiniz.'
              : '"${c.displayTitle}" (${c.displayVendor}) yeniden yürürlüğe alınacak; bitiş tarihine göre hatırlatmalar sürer.',
          style: Theme.of(dialogContext).textTheme.bodyMedium,
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final updated = await widget.service.setContractStatus(widget.siteCode, c.id, next);
      if (!mounted) return;
      setState(() {
        _contract = updated;
        _changed = true;
        _busy = false;
      });
      AppSnack.show(
        context,
        terminate ? 'Sözleşme feshedildi.' : 'Sözleşme yeniden etkinleştirildi.',
        kind: AppSnackKind.success,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = crmMessageOf(
          e,
          'Sözleşme güncellenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
        );
      });
    }
  }

  Widget _row(String label, String value, {String? key, String? spoken}) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpace.sm),
    child: Semantics(
      key: key == null ? null : ValueKey<String>(key),
      label: '$label: ${spoken ?? value}',
      excludeSemantics: true,
      child: CrmInfoLine(label: label, value: value),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final c = _contract;
    final terminated = c.isTerminated;
    final end = c.endDate;
    final start = c.startDate;
    final deadline = c.noticeDeadline;
    final amount = contractAmountText(c);
    final note = c.note?.trim() ?? '';
    final creator = c.createdByName?.trim() ?? '';
    final canWrite = widget.canWrite;
    // Geri tuşu / dış alana dokunma da değişen sözleşmeyle kapatır (çağıran listeyi tazelesin).
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_busy) _close();
      },
      child: AppDialog(
        title: c.displayTitle,
        subtitle: c.displayVendor,
        icon: contractCategoryIcon(c.category),
        tone: contractStateTone(c.state),
        actions: [
          TextButton(
            key: const ValueKey<String>('contract_detail_close'),
            onPressed: _busy ? null : _close,
            child: const Text('Kapat'),
          ),
          if (canWrite)
            OutlinedButton.icon(
              key: const ValueKey<String>('contract_detail_edit'),
              onPressed: _busy ? null : () => unawaited(_edit()),
              icon: const Icon(Icons.edit_rounded, size: 18),
              label: const Text('Düzenle'),
            ),
          if (canWrite && !terminated)
            ElevatedButton.icon(
              key: const ValueKey<String>('contract_detail_terminate'),
              style: filledToneStyle(context, tone: AppTone.danger),
              onPressed: _busy ? null : () => unawaited(_setStatus(ContractStatus.feshedildi)),
              icon: const Icon(Icons.cancel_outlined, size: 18),
              label: const Text('Feshet'),
            ),
          if (canWrite && terminated)
            ElevatedButton.icon(
              key: const ValueKey<String>('contract_detail_reactivate'),
              onPressed: _busy ? null : () => unawaited(_setStatus(ContractStatus.aktif)),
              icon: const Icon(Icons.restart_alt_rounded, size: 18),
              label: const Text('Yeniden etkinleştir'),
            ),
        ],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null) CrmFormError(message: _error!, announce: true),
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.xs,
              children: [
                ContractStateChip(c.state),
                InfoChip(c.category.label),
                if (c.autoRenew) const InfoChip('Otomatik yenilenir', tone: AppTone.info),
              ],
            ),
            const SizedBox(height: AppSpace.md),
            DialogPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _row('Firma', c.displayVendor, key: 'contract_detail_vendor'),
                  _row('Başlangıç', start == null ? '-' : formatDateField(start)),
                  _row(
                    'Bitiş',
                    end == null ? 'Süresiz' : formatDateField(end),
                    key: 'contract_detail_end',
                  ),
                  if (end != null && !terminated)
                    _row('Kalan süre', contractRemainingText(c), key: 'contract_detail_remaining'),
                  _row('Fesih bildirim süresi', '${c.noticeDays} gün'),
                  _row(
                    'Hatırlatma',
                    c.remindBeforeDays == 0
                        ? 'Bitiş günü'
                        : 'Bitişten ${c.remindBeforeDays} gün önce',
                  ),
                  if (c.autoRenew && deadline != null && !terminated)
                    _row(
                      'Fesih bildirimi son günü',
                      formatDateField(deadline),
                      key: 'contract_detail_deadline',
                    ),
                  _row('Otomatik yenileme', c.autoRenew ? 'Evet' : 'Hayır'),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.md),
            DialogPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _row(
                    'Tutar',
                    amount ?? 'Belirtilmedi',
                    key: 'contract_detail_amount',
                    spoken: amount == null ? null : spokenMoneyText(amount),
                  ),
                  _row(
                    'Ödeme dönemi',
                    c.period?.label ?? 'Belirtilmedi',
                    key: 'contract_detail_period',
                  ),
                ],
              ),
            ),
            if (terminated && c.terminatedAt != null) ...[
              const SizedBox(height: AppSpace.md),
              _row('Feshedildiği tarih', formatIstanbulDateTime(c.terminatedAt)),
            ],
            if (note.isNotEmpty) ...[
              const SizedBox(height: AppSpace.md),
              Text('Not', style: th.titleSmall),
              const SizedBox(height: AppSpace.xs),
              Text(note, style: th.bodyMedium),
            ],
            const SizedBox(height: AppSpace.md),
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.xs,
              children: [
                if (creator.isNotEmpty) InfoChip('Kaydeden: $creator'),
                if (c.createdAt != null)
                  InfoChip('Oluşturulma: ${formatIstanbulDateTime(c.createdAt)}'),
                if (c.updatedAt != null)
                  InfoChip('Son güncelleme: ${formatIstanbulDateTime(c.updatedAt)}'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
