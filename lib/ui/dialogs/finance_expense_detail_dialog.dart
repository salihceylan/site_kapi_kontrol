import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/expense_models.dart';
import 'package:site_kapi_kontrol/services/expense_attachments.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/finance_expense_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/finance_reason_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/large_dialog_parts.dart';
import 'package:site_kapi_kontrol/ui/helpers/date_input.dart';
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_4b_access.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_errors.dart';
import 'package:site_kapi_kontrol/ui/helpers/idempotency.dart';
import 'package:site_kapi_kontrol/ui/helpers/istanbul_time.dart';
import 'package:site_kapi_kontrol/ui/helpers/money.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_4b_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

/// Gider ayrıntısı (Platform Faz 4b, Ö3): alanlar, iptal bilgisi, ekler. Yazma yetkisi olan, iptal EDİLMEMİŞ gideri
/// **Düzeltebilir** (iptal + yeni gider) ya da nedenli **İptal Edebilir** (ayna hareket yazılır; gider silinmez).
/// Kurul salt okur (tedarikçi vergi no / telefon sunucuda gizli). Hata asla boş ekran bırakmaz.
class FinanceExpenseDetailDialog extends StatefulWidget {
  const FinanceExpenseDetailDialog({
    super.key,
    required this.scope,
    required this.expenseId,
    this.initialDescription,
    this.attachmentSource,
    this.now,
    this.onChanged,
  });

  final PeopleScope scope;
  final int expenseId;
  final String? initialDescription;
  final ExpenseAttachmentSource? attachmentSource;
  final DateTime Function()? now;

  /// Gider iptal / düzeltme / ek değişince çağrılır (liste tazelenir).
  final VoidCallback? onChanged;

  static Future<void> show(
    BuildContext context, {
    required PeopleScope scope,
    required int expenseId,
    String? initialDescription,
    ExpenseAttachmentSource? attachmentSource,
    DateTime Function()? now,
    VoidCallback? onChanged,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => FinanceExpenseDetailDialog(
        scope: scope,
        expenseId: expenseId,
        initialDescription: initialDescription,
        attachmentSource: attachmentSource,
        now: now,
        onChanged: onChanged,
      ),
    );
  }

  @override
  State<FinanceExpenseDetailDialog> createState() => _FinanceExpenseDetailDialogState();
}

class _FinanceExpenseDetailDialogState extends State<FinanceExpenseDetailDialog> {
  Expense? _expense;
  bool _loading = true;
  String? _error;
  int _token = 0;
  bool _opening = false;
  bool _uploading = false;
  String? _actionError;
  final IdempotencyKeys _keys = IdempotencyKeys('expd');

  bool get _canWrite => widget.scope.canWrite;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    ++_token;
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
      final expense = await widget.scope.f4Call(
        (api, t, s) => api.getExpense(token: t, siteCode: s, expenseId: widget.expenseId),
      );
      if (!mounted || token != _token) return;
      setState(() {
        _expense = expense;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || token != _token) return;
      setState(() {
        _loading = false;
        _expense = null;
        _error = financeMessageOf(e, 'Gider yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.');
      });
    }
  }

  Future<void> _correct(Expense expense) async {
    if (_opening) return;
    _opening = true;
    try {
      final outcome = await FinanceExpenseDialog.show(
        context,
        scope: widget.scope,
        correcting: expense,
        attachmentSource: widget.attachmentSource,
        now: widget.now,
        onRefreshNeeded: widget.onChanged,
      );
      if (outcome == null || !mounted) return;
      widget.onChanged?.call();
      showFinanceSnack(context, outcome.message);
      unawaited(_load());
    } finally {
      _opening = false;
    }
  }

  Future<void> _void(Expense expense) async {
    if (_opening) return;
    _opening = true;
    try {
      final done = await FinanceReasonDialog.show(
        context,
        title: 'Gideri İptal Et',
        subtitle: expense.description,
        message:
            '${formatMinor(expense.amountMinor)} tutarındaki gider iptal edilir: hesapta ters hareket yazılır, gider '
            'silinmez ve "İptal edildi" olarak kalır.',
        semanticMessage: spokenMoneyText(
          '${formatMinor(expense.amountMinor)} tutarındaki gider iptal edilir: hesapta ters hareket yazılır, gider silinmez ve "İptal edildi" olarak kalır.',
        ),
        confirmLabel: 'Gideri İptal Et',
        signatureBase: 'exp-void|${expense.id}',
        keyPrefix: 'exp-v',
        keyOwner: widget.scope.authService,
        onUncertain: () {
          widget.onChanged?.call();
          if (mounted) unawaited(_load());
        },
        failure: 'Gider iptal edilemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
        action: (reason, key) => widget.scope.f4Call(
          (api, t, s) => api.voidExpense(token: t, siteCode: s, expenseId: expense.id, reason: reason, idempotencyKey: key),
        ),
      );
      if (!done || !mounted) return;
      widget.onChanged?.call();
      showFinanceSnack(context, 'Gider iptal edildi.');
      unawaited(_load());
    } finally {
      _opening = false;
    }
  }

  Future<void> _addFiles(Expense expense) async {
    final source = widget.attachmentSource;
    if (source == null || _uploading) return;
    final room = FinanceExpenseDialog.maxAttachments - expense.attachments.where((a) => a.isReady).length;
    if (room <= 0) {
      setState(() => _actionError = 'Bir gidere en çok ${FinanceExpenseDialog.maxAttachments} belge eklenebilir.');
      return;
    }
    final picked = await source.pick(context, maxCount: room);
    if (!mounted || picked.isEmpty) return;
    final allowed = picked.where((f) => f.isAllowedType).take(room).toList();
    if (allowed.isEmpty) {
      setState(() => _actionError = 'Yalnızca PDF, JPG ve PNG eklenebilir.');
      return;
    }
    setState(() {
      _uploading = true;
      _actionError = null;
    });
    try {
      final signatures = expenseUploadSignatures(expense.id, allowed);
      final results = await uploadExpenseFiles(
        service: widget.scope.f4,
        siteCode: widget.scope.siteCode,
        expenseId: expense.id,
        files: allowed,
        keyFor: (file) => _keys.keyFor(signatures[file]!),
        isCancelled: () => !mounted,
      );
      for (final r in results.where((r) => r.ok)) {
        _keys.clear(signatures[r.file]!);
      }
      if (!mounted) return;
      final failed = results.where((r) => !r.ok).toList();
      setState(() {
        _uploading = false;
        _actionError = failed.isEmpty ? null : failed.map((r) => '${r.file.name}: ${r.error}').join(' ');
      });
      if (results.any((r) => r.ok)) {
        widget.onChanged?.call();
        unawaited(_load());
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _actionError = 'Belgeler yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final expense = _expense;
    final Widget body;
    if (expense == null) {
      body = _loading || _error == null
          ? const DialogRowsSkeleton(rows: 3, caption: 'Gider yükleniyor...')
          : InlineNotice(message: _error!, onRetry: _load);
    } else {
      body = _buildLoaded(context, expense);
    }
    return AppDialog(
      title: 'Gider',
      subtitle: expense?.description.isNotEmpty == true ? expense!.description : widget.initialDescription,
      icon: Icons.shopping_bag_rounded,
      actions: [
        TextButton(
          key: const ValueKey<String>('finance_expense_detail_close'),
          onPressed: () => popIfCurrent(context),
          child: const Text('Kapat'),
        ),
      ],
      child: body,
    );
  }

  Widget _buildLoaded(BuildContext context, Expense e) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final voided = e.voided;
    final semantic = StringBuffer('Gider: ${e.description}. ${moneySemanticLabel(e.amountMinor)}. ${e.categoryName}.');
    if (e.isVoided) semantic.write(' İptal edildi.');
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_actionError != null) FinanceSubmitError(key: const ValueKey<String>('finance_expense_detail_error'), message: _actionError!),
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.xs,
          children: [
            DialogMetaPill(e.categoryName.isEmpty ? 'Kategorisiz' : e.categoryName, tone: AppTone.info, icon: Icons.sell_rounded),
            if (e.isVoided)
              const DialogMetaPill('İptal edildi', tone: AppTone.neutral, icon: Icons.block_rounded)
            else
              const DialogMetaPill('Geçerli', tone: AppTone.success, icon: Icons.check_circle_rounded),
          ],
        ),
        const SizedBox(height: AppSpace.md),
        DialogPanel(
          key: const ValueKey<String>('finance_expense_detail_summary'),
          child: Semantics(
            container: true,
            label: semantic.toString(),
            child: ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.description.isEmpty ? 'Açıklamasız gider' : e.description, style: th.titleMedium),
                  Text(
                    formatMinor(e.amountMinor),
                    key: const ValueKey<String>('finance_expense_detail_amount'),
                    style: th.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      decoration: e.isVoided ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  if (e.vatMinor != null)
                    Text('Tutara dahil KDV: ${formatMinor(e.vatMinor!)}', style: th.bodySmall?.copyWith(color: p.textSecondary)),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        if (voided != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.md),
            child: InlineNotice(
              key: const ValueKey<String>('finance_expense_detail_voided'),
              tone: AppTone.warning,
              message:
                  'Bu gider iptal edilmiştir${voided.at == null ? '' : ' (${formatIstanbulDateTime(voided.at)})'}.'
                  '${voided.reason == null ? '' : ' Neden: ${voided.reason}'}',
            ),
          ),
        if (e.correctsExpenseId != null)
          const Padding(
            padding: EdgeInsets.only(bottom: AppSpace.md),
            child: InlineNotice(
              tone: AppTone.info,
              message: 'Bu gider, daha önce iptal edilen bir giderin düzeltmesidir.',
            ),
          ),
        FinanceInfoRow(label: 'Gider tarihi', value: formatCrmDate(e.expenseDate)),
        if (e.supplierName != null) FinanceInfoRow(label: 'Tedarikçi', value: e.supplierName),
        FinanceInfoRow(label: 'Hesap', value: e.accountName ?? '-'),
        if (e.fund != null) FinanceInfoRow(label: 'Kasa', value: e.fund!.label),
        FinanceInfoRow(
          label: 'Belge',
          value: e.documentKind == ExpenseDocumentKind.none
              ? 'Belgesiz'
              : '${e.documentKind.label}${e.documentNo == null ? '' : ' • ${e.documentNo}'}',
        ),
        if (e.createdByName != null) FinanceInfoRow(label: 'Kaydeden', value: e.createdByName),
        if (e.createdAt != null) FinanceInfoRow(label: 'Kayıt zamanı', value: formatIstanbulDateTime(e.createdAt)),
        const SizedBox(height: AppSpace.md),
        Semantics(header: true, container: true, child: Text('Belgeler', style: th.titleSmall)),
        const SizedBox(height: AppSpace.xs),
        if (e.attachments.isEmpty)
          Text(
            e.documentsCount > 0 ? '${e.documentsCount} belge bağlı.' : 'Bu gidere bağlı belge yok.',
            key: const ValueKey<String>('finance_expense_detail_no_documents'),
            style: th.bodyMedium?.copyWith(color: p.textSecondary),
          )
        else
          for (final a in e.attachments)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.xs),
              child: Semantics(
                container: true,
                label: 'Belge: ${a.displayName}. ${a.kind.label}.',
                child: ExcludeSemantics(
                  child: Row(
                    children: [
                      const Icon(Icons.attach_file_rounded, size: 18),
                      const SizedBox(width: AppSpace.sm),
                      Expanded(child: Text('${a.displayName} • ${a.kind.label}', style: th.bodyMedium)),
                    ],
                  ),
                ),
              ),
            ),
        if (_canWrite && widget.attachmentSource != null && !e.isVoided) ...[
          const SizedBox(height: AppSpace.sm),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: PrimaryActionButton(
              key: const ValueKey<String>('finance_expense_detail_add_file'),
              label: 'Belge Ekle',
              icon: Icons.upload_file_rounded,
              variant: AppButtonVariant.tonal,
              expand: false,
              loading: _uploading,
              onPressed: _uploading ? null : () => _addFiles(e),
            ),
          ),
        ],
        if (_canWrite && !e.isVoided) ...[
          const SizedBox(height: AppSpace.lg),
          PrimaryActionButton(
            key: const ValueKey<String>('finance_expense_correct'),
            label: 'Gideri Düzelt',
            icon: Icons.edit_rounded,
            variant: AppButtonVariant.tonal,
            onPressed: _opening ? null : () => _correct(e),
          ),
          const SizedBox(height: AppSpace.sm),
          OutlinedButton.icon(
            key: const ValueKey<String>('finance_expense_void'),
            style: dangerOutlineStyle(context),
            onPressed: _opening ? null : () => _void(e),
            icon: const Icon(Icons.block_rounded, size: 18),
            label: const Text('Gideri İptal Et'),
          ),
        ],
      ],
    );
  }
}
