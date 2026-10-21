import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/bulk_import.dart' show ImportKind;
import 'package:site_kapi_kontrol/models/finance_opening.dart';
import 'package:site_kapi_kontrol/services/bulk_api.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_errors.dart';
import 'package:site_kapi_kontrol/ui/helpers/idempotency.dart';
import 'package:site_kapi_kontrol/ui/helpers/money.dart' show formatMinor;
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/views/bulk_import_controller.dart' show kOpeningImportKinds;
import 'package:site_kapi_kontrol/ui/views/bulk_import_view.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart' show InlineNotice;

/// Finans > Daireler > «Devir bakiyesi» (F4): önceki devir yüklemeleri, «Excel'den yükle» ve yükleme bazında
/// «Geri al» (neden zorunlu; ters kayıt yazılır, defter silinmez). Yalnız yazma yetkisi olanlara açılır.
class FinanceOpeningDialog extends StatefulWidget {
  const FinanceOpeningDialog({super.key, required this.scope, required this.onChanged, this.service});

  final PeopleScope scope;
  final VoidCallback onChanged;
  final BulkService? service;

  static Future<void> show(BuildContext context, {required PeopleScope scope, required VoidCallback onChanged}) {
    return showDialog<void>(
      context: context,
      builder: (_) => FinanceOpeningDialog(scope: scope, onChanged: onChanged),
    );
  }

  @override
  State<FinanceOpeningDialog> createState() => _FinanceOpeningDialogState();
}

class _FinanceOpeningDialogState extends State<FinanceOpeningDialog> {
  late final BulkService _service = widget.service ?? BulkService(authService: widget.scope.authService);
  final IdempotencyKeys _keys = IdempotencyKeys('rev');
  final TextEditingController _reason = TextEditingController();
  List<OpeningRun>? _runs;
  String? _error;
  bool _loading = false;
  bool _busy = false;
  OpeningRevertPreview? _revert;
  String? _revertError;
  String? _notice;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final runs = await _service.listOpeningRuns(widget.scope.siteCode);
      if (!mounted) return;
      setState(() => _runs = runs);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = financeMessageOf(e, 'Devir yüklemeleri alınamadı. Tekrar deneyin.'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _upload() async {
    final outcome = await BulkImportView.open(
      context,
      scope: widget.scope,
      initialKind: ImportKind.openingBalances,
      allowedKinds: kOpeningImportKinds,
    );
    if (!mounted) return;
    if (outcome?.changed == true) {
      widget.onChanged();
      await _load();
    }
  }

  Future<void> _startRevert(OpeningRun run) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _revertError = null;
      _notice = null;
    });
    try {
      final detail = await _service.getOpeningRun(widget.scope.siteCode, run.id);
      if (!mounted) return;
      _reason.clear();
      setState(() => _revert = detail);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = financeMessageOf(e, 'Devir ayrıntısı alınamadı. Tekrar deneyin.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmRevert() async {
    final detail = _revert;
    final reason = _reason.text.trim();
    if (detail == null || _busy) return;
    if (reason.isEmpty) {
      setState(() => _revertError = 'Geri alma nedenini yazın.');
      return;
    }
    final signature = 'rev|${detail.run.id}|${detail.entriesToReverse}|${detail.totalMinor}|$reason';
    final key = _keys.keyFor(signature);
    setState(() {
      _busy = true;
      _revertError = null;
    });
    try {
      final count = await _service.revertOpening(
        widget.scope.siteCode,
        detail.run.id,
        reason: reason,
        idempotencyKey: key,
        expectedCount: detail.entriesToReverse,
        expectedTotalMinor: detail.totalMinor,
      );
      _keys.clear(signature);
      widget.onChanged();
      if (!mounted) return;
      setState(() {
        _revert = null;
        _notice = '$count devir kaydı geri alındı.';
      });
      await _load();
    } catch (e) {
      if (!mounted) return;
      final hint = financeOutcomeUncertain(e) ? ' $kFinanceUncertainHint' : '';
      setState(() => _revertError = '${financeMessageOf(e, 'Geri alınamadı. Tekrar deneyin.')}$hint');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String _dateText(String? iso) {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(iso ?? '');
    return m == null ? (iso ?? '-') : '${m[3]}.${m[2]}.${m[1]}';
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final detail = _revert;
    return AppDialog(
      title: 'Devir bakiyesi',
      subtitle: detail == null ? 'Eski yazılımdan devreden borçlar' : 'Yüklemeyi geri al',
      icon: Icons.account_balance_wallet_rounded,
      actions: [
        if (detail != null) ...[
          TextButton(
            key: const ValueKey<String>('opening_revert_cancel'),
            onPressed: _busy ? null : () => setState(() => _revert = null),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            key: const ValueKey<String>('opening_revert_submit'),
            onPressed: _busy || detail.entriesToReverse == 0 ? null : _confirmRevert,
            child: const Text('Geri al'),
          ),
        ] else
          TextButton(
            key: const ValueKey<String>('opening_close'),
            onPressed: () => popIfCurrent(context, null),
            child: const Text('Kapat'),
          ),
      ],
      child: detail != null ? _revertBody(detail, th, p) : _listBody(th, p),
    );
  }

  Widget _revertBody(OpeningRevertPreview detail, TextTheme th, AppPalette p) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${detail.entriesToReverse} kayıt için toplam ${formatMinor(detail.totalMinor)} tutarında ters kayıt '
          'yazılacak. Eski kayıtlar silinmez.',
          key: const ValueKey<String>('opening_revert_summary'),
          style: th.bodyMedium,
        ),
        if (detail.individuallyCancelled > 0)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.xs),
            child: Text(
              '${detail.individuallyCancelled} kayıt daha önce tek tek iptal edilmiş; atlanır.',
              style: th.bodySmall?.copyWith(color: p.textSecondary),
            ),
          ),
        if (detail.apartmentsWithLaterPayments > 0)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.sm),
            child: InlineNotice(
              key: const ValueKey<String>('opening_revert_paid_warning'),
              tone: AppTone.warning,
              message:
                  '${detail.apartmentsWithLaterPayments} dairede devirden sonra tahsilat var; geri almadan sonra bu '
                  'dairelerde alacak oluşabilir.',
            ),
          ),
        if (detail.lateFeeEntriesAfter > 0)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.sm),
            child: InlineNotice(
              tone: AppTone.warning,
              message:
                  '${detail.lateFeeEntriesAfter} gecikme tazminatı kaydı bu dairelere sonradan hesaplanmış; '
                  'geri alma bunları iptal etmez.',
            ),
          ),
        const SizedBox(height: AppSpace.md),
        TextField(
          key: const ValueKey<String>('opening_revert_reason'),
          controller: _reason,
          maxLength: 200,
          enabled: !_busy,
          decoration: const InputDecoration(labelText: 'Geri alma nedeni (zorunlu)'),
        ),
        if (_revertError != null)
          InlineNotice(key: const ValueKey<String>('opening_revert_error'), tone: AppTone.danger, message: _revertError!),
      ],
    );
  }

  Widget _listBody(TextTheme th, AppPalette p) {
    final runs = _runs;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PrimaryActionButton(
          key: const ValueKey<String>('opening_upload'),
          label: "Excel'den yükle",
          icon: Icons.upload_file_rounded,
          variant: AppButtonVariant.tonal,
          onPressed: _busy ? null : _upload,
        ),
        const SizedBox(height: AppSpace.md),
        if (_notice != null)
          InlineNotice(key: const ValueKey<String>('opening_notice'), tone: AppTone.success, message: _notice!),
        if (_error != null)
          InlineNotice(key: const ValueKey<String>('opening_error'), tone: AppTone.danger, message: _error!),
        if (_loading && runs == null)
          const Center(child: Padding(padding: EdgeInsets.all(AppSpace.md), child: CircularProgressIndicator()))
        else if (runs != null && runs.isEmpty && _error == null)
          Text('Henüz devir yüklemesi yok.', style: th.bodyMedium?.copyWith(color: p.textSecondary))
        else if (runs != null)
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final run in runs)
                  ListTile(
                    key: ValueKey<String>('opening_run_${run.id}'),
                    contentPadding: EdgeInsets.zero,
                    title: Text('${formatMinor(run.totalMinor)} · ${run.entryCount} kayıt'),
                    subtitle: Text(
                      'Devir tarihi ${_dateText(run.cutoverDate)}${run.reverted ? ' · Geri alındı' : ''}',
                    ),
                    trailing: run.reverted
                        ? null
                        : TextButton(
                            key: ValueKey<String>('opening_revert_${run.id}'),
                            onPressed: _busy ? null : () => _startRevert(run),
                            child: const Text('Geri al'),
                          ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
