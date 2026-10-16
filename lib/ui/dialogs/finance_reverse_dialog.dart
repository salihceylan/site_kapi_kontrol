import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MaxLengthEnforcement;
import 'package:site_kapi_kontrol/models/finance.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/large_dialog_parts.dart';
import 'package:site_kapi_kontrol/ui/helpers/date_input.dart';
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_errors.dart';
import 'package:site_kapi_kontrol/ui/helpers/form_validation.dart';
import 'package:site_kapi_kontrol/ui/helpers/idempotency.dart';
import 'package:site_kapi_kontrol/ui/helpers/money.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/helpers/retry_lock.dart';
import 'package:site_kapi_kontrol/ui/helpers/text_length.dart';
import 'package:site_kapi_kontrol/ui/widgets/crm_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart' show filledToneStyle;

/// "İptal Et" penceresi kapanırken döner.
class FinanceReverseOutcome {
  const FinanceReverseOutcome({required this.result, required this.message});

  final LedgerWriteResult result;
  final String message;
}

/// Bir mali kaydı iptal eden pencere (Platform Faz 4a): kayıt SİLİNMEZ; karşı işaretli bir ters kayıt eklenir
/// (defter yalnız eklenir). Neden zorunludur (en çok 200 karakter, kod noktası sayımı) ve denetim için
/// saklanır. Ters kayıt bugünün AÇIK ayına yazılır; kapalı dönem hatası Türkçe gösterilir.
///
/// Çift gönderim koruması ve `idempotency_key`: [FinancePaymentDialog] ile aynı kural (aynı neden = aynı
/// anahtar). Gönderim sürerken geri tuşu kapatmaz; hata pencerede görünür ve pencere AÇIK kalır.
class FinanceReverseDialog extends StatefulWidget {
  const FinanceReverseDialog({
    super.key,
    required this.scope,
    required this.entry,
    this.onRefreshNeeded,
  });

  final PeopleScope scope;
  final LedgerEntry entry;

  /// Sonuç BELİRSİZ kaldığında (ağ / 5xx) ya da kayıt zaten iptal edilmişse (409) kapanırken çağrılır.
  final VoidCallback? onRefreshNeeded;

  static const int maxReasonLength = 200;

  static Future<FinanceReverseOutcome?> show(
    BuildContext context, {
    required PeopleScope scope,
    required LedgerEntry entry,
    VoidCallback? onRefreshNeeded,
  }) {
    return showDialog<FinanceReverseOutcome>(
      context: context,
      barrierDismissible: false,
      builder: (_) => FinanceReverseDialog(
        scope: scope,
        entry: entry,
        onRefreshNeeded: onRefreshNeeded,
      ),
    );
  }

  @override
  State<FinanceReverseDialog> createState() => _FinanceReverseDialogState();
}

class _FinanceReverseDialogState extends State<FinanceReverseDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _reason = TextEditingController();
  final IdempotencyKeys _keys = IdempotencyKeys('rev');
  final RetryLock _retry = RetryLock();
  bool _submitting = false;
  bool _needsRefreshOnClose = false;
  String? _error;

  @override
  void dispose() {
    _retry.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || _retry.locked) return;
    if (!validateForm(_formKey)) {
      setState(() => _error = kFixFieldsMessage);
      return;
    }
    final reason = _reason.text.trim();
    final key = _keys.keyFor('${widget.entry.id}|$reason');
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final result = await widget.scope.authService.reverseFinanceEntry(
        widget.scope.siteCode,
        widget.entry.id,
        reason: reason,
        idempotencyKey: key,
      );
      if (!mounted) return;
      _needsRefreshOnClose = false;
      final balance = result.balanceMinor;
      const head = 'Kayıt iptal edildi (ters kayıt eklendi).';
      popIfCurrent(
        context,
        FinanceReverseOutcome(
          result: result,
          message: balance == null ? head : '$head Güncel bakiye: ${describeBalance(balance).badgeText}.',
        ),
      );
    } catch (e) {
      // Kayıt zaten iptal edilmiş / iptal edilemez: kayıt listesi eskimiştir, kapanırken tazelenir.
      if (financeOutcomeUncertain(e) ||
          hasErrorCode(e, 'ENTRY_ALREADY_REVERSED') ||
          hasErrorCode(e, 'ENTRY_NOT_REVERSIBLE')) {
        _needsRefreshOnClose = true;
      }
      if (!mounted) return;
      final limited = _retry.lockIfRateLimited(e, () {
        if (mounted) setState(() {});
      });
      setState(() {
        _submitting = false;
        _error = limited
            ? RetryLock.messageFor(e)
            : financeWriteMessage(
                e,
                'Kayıt iptal edilemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
              );
      });
    }
  }

  void _notifyRefreshOnClose() {
    if (!_needsRefreshOnClose) return;
    _needsRefreshOnClose = false;
    widget.onRefreshNeeded?.call();
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final entry = widget.entry;
    return PopScope(
      canPop: !_submitting,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _notifyRefreshOnClose();
      },
      child: AppDialog(
        title: 'Kaydı İptal Et',
        subtitle: widget.scope.siteName.isEmpty ? null : widget.scope.siteName,
        icon: Icons.undo_rounded,
        tone: AppTone.danger,
        actions: [
          TextButton(
            onPressed: _submitting ? null : () => popIfCurrent(context),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            key: const ValueKey<String>('finance_reverse_submit'),
            style: filledToneStyle(context, tone: AppTone.danger),
            onPressed: (_submitting || _retry.locked) ? null : _submit,
            child: Text(_submitting ? 'İptal ediliyor...' : 'İptal Et'),
          ),
        ],
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) CrmFormError(message: _error!),
              DialogPanel(
                key: const ValueKey<String>('finance_reverse_entry'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DialogSectionTitle(
                      icon: Icons.receipt_long_rounded,
                      title: entry.kind.label,
                    ),
                    const SizedBox(height: AppSpace.sm),
                    Text(
                      '${formatCrmDate(entry.entryDate)} • ${formatMinor(entry.amountMinor.abs())}'
                      '${entry.definitionName == null ? '' : ' • ${entry.definitionName}'}',
                      style: th.bodyMedium,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpace.md),
              Text(
                'Kayıt silinmez; karşı işaretli bir ters kayıt eklenir ve bakiye düzelir. Ters kayıt '
                'bugünün açık ayına yazılır. Yanlış tutarlı bir tahsilatı düzeltmek için "Düzelt"i kullanın.',
                style: th.bodySmall?.copyWith(color: p.textSecondary),
              ),
              const SizedBox(height: AppSpace.md),
              TextFormField(
                key: const ValueKey<String>('finance_reverse_reason'),
                controller: _reason,
                enabled: !_submitting,
                minLines: 2,
                maxLines: 4,
                maxLength: FinanceReverseDialog.maxReasonLength,
                maxLengthEnforcement: MaxLengthEnforcement.none,
                buildCounter: (context, {required currentLength, required isFocused, maxLength}) =>
                    characterCounter(
                      context,
                      _reason.text.trim().runes.length,
                      FinanceReverseDialog.maxReasonLength,
                    ),
                textCapitalization: TextCapitalization.sentences,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                decoration: const InputDecoration(
                  labelText: 'İptal nedeni',
                  alignLabelWithHint: true,
                  prefixIcon: Icon(Icons.notes_rounded),
                ),
                validator: (value) {
                  final length = trimmedCodePoints(value ?? '');
                  if (length < 1) return 'İptal nedenini yazın.';
                  if (length > FinanceReverseDialog.maxReasonLength) {
                    return 'Neden en çok ${FinanceReverseDialog.maxReasonLength} karakter olabilir.';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
