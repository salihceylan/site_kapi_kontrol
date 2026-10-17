import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MaxLengthEnforcement;
import 'package:site_kapi_kontrol/models/cash_models.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/date_input.dart';
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_4b_access.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_write_mixin.dart';
import 'package:site_kapi_kontrol/ui/helpers/form_validation.dart';
import 'package:site_kapi_kontrol/ui/helpers/istanbul_time.dart';
import 'package:site_kapi_kontrol/ui/helpers/money.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/helpers/text_length.dart';
import 'package:site_kapi_kontrol/ui/widgets/crm_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_4b_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/money_field.dart';

/// Hesap düzeltme hareketi (banka masrafı, banka faizi, sayım farkı) penceresi (Platform Faz 4b, Ö4).
///
/// Tutar POZİTİF girilir, YÖN açıkça seçilir (giriş +, çıkış -); böylece işaret hatası olmaz. Hareket AÇIK ayda
/// yazılır ve raporlarda AYRI satır olarak görünür (gizlenmez). Neden zorunlu; "Diğer" nedeninde not zorunlu.
/// Yeni bakiye önizlemesi yalnız bilgidir (tamsayı aritmetiği).
class FinanceAdjustDialog extends StatefulWidget {
  const FinanceAdjustDialog({super.key, required this.scope, required this.account, this.now, this.onRefreshNeeded});

  final PeopleScope scope;
  final CashAccount account;
  final DateTime Function()? now;
  final VoidCallback? onRefreshNeeded;

  static const int maxNoteLength = 200;

  static Future<FinanceWriteOutcome?> show(
    BuildContext context, {
    required PeopleScope scope,
    required CashAccount account,
    DateTime Function()? now,
    VoidCallback? onRefreshNeeded,
  }) {
    return showDialog<FinanceWriteOutcome>(
      context: context,
      barrierDismissible: false,
      builder: (_) => FinanceAdjustDialog(scope: scope, account: account, now: now, onRefreshNeeded: onRefreshNeeded),
    );
  }

  @override
  State<FinanceAdjustDialog> createState() => _FinanceAdjustDialogState();
}

class _FinanceAdjustDialogState extends State<FinanceAdjustDialog> with FinanceWriteMixin, FinanceDiscardGuard {
  @override
  String get keyPrefix => 'adj';

  @override
  Object? get keyOwner => widget.scope.authService;

  @override
  bool get closeLocked => submitting;

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final GlobalKey _directionKey = GlobalKey();
  final GlobalKey _reasonKey = GlobalKey();
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _note = TextEditingController();
  late final TextEditingController _date = TextEditingController(text: formatDateField(_today()));
  bool? _inflow;
  AdjustmentReason? _reason;
  String? _directionError;
  String? _reasonError;

  DateTime _today() {
    final wall = istanbulNow(widget.now?.call());
    return DateTime(wall.year, wall.month, wall.day);
  }

  @override
  void dispose() {
    disposeWrite();
    _amount.dispose();
    _note.dispose();
    _date.dispose();
    super.dispose();
  }

  bool _validateChoices() {
    setState(() {
      _directionError = _inflow == null ? 'Düzeltmenin yönünü seçin (giriş ya da çıkış).' : null;
      _reasonError = _reason == null ? 'Düzeltme nedenini seçin.' : null;
    });
    return _inflow != null && _reason != null;
  }

  void _reveal(BuildContext formContext) {
    if (revealFirstInvalidField(formContext)) return;
    final key = _directionError != null ? _directionKey : (_reasonError != null ? _reasonKey : null);
    final target = key?.currentContext;
    if (target != null) Scrollable.ensureVisible(target, alignment: 0.15, duration: Duration.zero);
  }

  Future<void> _submit() async {
    if (writeBlocked) return;
    final ok = validateForm(_formKey, validateExtra: _validateChoices, reveal: _reveal);
    if (!ok) {
      setState(() => submitError = kFixFieldsMessage);
      return;
    }
    final magnitude = parseMoney(_amount.text).minor!;
    final signed = _inflow! ? magnitude : -magnitude;
    final date = parseDateField(_date.text)!;
    final reason = _reason!;
    final note = _note.text.trim();
    await runWrite<AccountMovement>(
      signature: 'adj|${widget.account.id}|$signed|${formatDateField(date)}|${reason.apiValue}|$note',
      action: (key) => widget.scope.f4Call(
        (api, t, s) => api.adjustAccount(
          token: t,
          siteCode: s,
          accountId: widget.account.id,
          amountMinor: signed,
          movementDate: date,
          reason: reason,
          note: note,
          idempotencyKey: key,
        ),
      ),
      onSuccess: (_) => popIfCurrent(
        context,
        FinanceWriteOutcome(
          'Düzeltme yazıldı: ${formatSignedMinor(signed)} (${reason.label}). ${widget.account.name} bakiyesi güncellendi.',
        ),
      ),
      failure: 'Düzeltme yazılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.',
    );
  }

  void _notify() {
    if (!needsRefreshOnClose) return;
    needsRefreshOnClose = false;
    widget.onRefreshNeeded?.call();
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final magnitude = parseMoney(_amount.text).minor;
    final inflow = _inflow;
    final next = magnitude == null || inflow == null
        ? null
        : widget.account.balanceMinor + (inflow ? magnitude : -magnitude);
    final noteRequired = _reason == AdjustmentReason.other;
    return PopScope(
      canPop: canPopNow,
      onPopInvokedWithResult: (didPop, _) {
        handleBlockedPop(didPop);
        if (didPop) _notify();
      },
      child: AppDialog(
        title: 'Düzeltme Hareketi',
        subtitle: widget.account.name,
        icon: Icons.tune_rounded,
        actions: [
          TextButton(
            onPressed: submitting ? null : requestClose,
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            key: const ValueKey<String>('finance_adjust_submit'),
            onPressed: writeBlocked ? null : _submit,
            child: Text(submitting ? 'Kaydediliyor...' : 'Kaydet'),
          ),
        ],
        child: Form(
          key: _formKey,
          onChanged: markDirty,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (submitError != null) FinanceSubmitError(message: submitError!),
              Text(
                'Banka masrafı, banka faizi ya da kasa sayım farkı gibi hesap bakiyesini düzelten bir hareket yazar. '
                'Hareket raporlarda ayrı satır olarak görünür.',
                style: th.bodyMedium,
              ),
              const SizedBox(height: AppSpace.md),
              KeyedSubtree(
                key: _directionKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const FinanceGroupTitle('Yön'),
                    const SizedBox(height: AppSpace.sm),
                    Wrap(
                      spacing: AppSpace.sm,
                      runSpacing: AppSpace.sm,
                      children: [
                        ChoiceChip(
                          key: const ValueKey<String>('finance_adjust_in'),
                          avatar: const Icon(Icons.add_circle_outline_rounded, size: 18),
                          label: const Text('Hesaba giriş (+)'),
                          selected: _inflow == true,
                          onSelected: submitting
                              ? null
                              : (_) => setState(() {
                                  markDirty();
                                  _inflow = true;
                                  _directionError = null;
                                }),
                        ),
                        ChoiceChip(
                          key: const ValueKey<String>('finance_adjust_out'),
                          avatar: const Icon(Icons.remove_circle_outline_rounded, size: 18),
                          label: const Text('Hesaptan çıkış (-)'),
                          selected: _inflow == false,
                          onSelected: submitting
                              ? null
                              : (_) => setState(() {
                                  markDirty();
                                  _inflow = false;
                                  _directionError = null;
                                }),
                        ),
                      ],
                    ),
                    if (_directionError != null) ...[
                      const SizedBox(height: AppSpace.sm),
                      CrmFormError(message: _directionError!, reveal: false),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AppSpace.md),
              MoneyFormField(
                key: const ValueKey<String>('finance_adjust_amount_group'),
                fieldKey: const ValueKey<String>('finance_adjust_amount'),
                controller: _amount,
                enabled: !submitting,
                label: 'Tutar',
                helperText: 'Eksi işareti girmeyin; yön yukarıda seçilir.',
                textInputAction: TextInputAction.next,
                onChanged: (_) => setState(() {}),
              ),
              if (next != null) ...[
                const SizedBox(height: AppSpace.xs),
                Padding(
                  padding: const EdgeInsets.only(left: AppSpace.md),
                  child: Semantics(
                    label:
                        'Yeni hesap bakiyesi: ${moneySemanticLabel(next)}. Şimdiki bakiye: ${moneySemanticLabel(widget.account.balanceMinor)}.',
                    child: ExcludeSemantics(
                      child: Text(
                        'Bakiye: ${formatMinor(widget.account.balanceMinor)} → ${formatMinor(next)}',
                        key: const ValueKey<String>('finance_adjust_preview'),
                        style: th.bodySmall?.copyWith(
                          color: next < 0 ? AppTone.danger.ink(p) : p.textSecondary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: AppSpace.md),
              FinanceDateField(
                key: const ValueKey<String>('finance_adjust_date_group'),
                controller: _date,
                label: 'Hareket tarihi',
                enabled: !submitting,
                maxDate: _today(),
              ),
              const SizedBox(height: AppSpace.lg),
              KeyedSubtree(
                key: _reasonKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const FinanceGroupTitle('Neden'),
                    const SizedBox(height: AppSpace.sm),
                    Wrap(
                      spacing: AppSpace.sm,
                      runSpacing: AppSpace.sm,
                      children: [
                        for (final reason in AdjustmentReason.values)
                          ChoiceChip(
                            key: ValueKey<String>('finance_adjust_reason_${reason.apiValue}'),
                            label: Text(reason.label),
                            selected: _reason == reason,
                            onSelected: submitting
                                ? null
                                : (_) => setState(() {
                                    markDirty();
                                    _reason = reason;
                                    _reasonError = null;
                                  }),
                          ),
                      ],
                    ),
                    if (_reasonError != null) ...[
                      const SizedBox(height: AppSpace.sm),
                      CrmFormError(message: _reasonError!, reveal: false),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AppSpace.md),
              TextFormField(
                key: const ValueKey<String>('finance_adjust_note'),
                controller: _note,
                enabled: !submitting,
                minLines: 2,
                maxLines: 4,
                maxLength: FinanceAdjustDialog.maxNoteLength,
                maxLengthEnforcement: MaxLengthEnforcement.none,
                buildCounter: (context, {required currentLength, required isFocused, maxLength}) =>
                    characterCounter(context, trimmedCodePoints(_note.text), FinanceAdjustDialog.maxNoteLength),
                textCapitalization: TextCapitalization.sentences,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: noteRequired ? 'Not (zorunlu)' : 'Not (isteğe bağlı)',
                  alignLabelWithHint: true,
                  prefixIcon: const Icon(Icons.notes_rounded),
                ),
                validator: (value) {
                  final length = trimmedCodePoints(value ?? '');
                  if (noteRequired && length < 1) return '"Diğer" nedeninde açıklama notu zorunludur.';
                  if (length > FinanceAdjustDialog.maxNoteLength) {
                    return 'Not en çok ${FinanceAdjustDialog.maxNoteLength} karakter olabilir.';
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
