import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MaxLengthEnforcement;
import 'package:site_kapi_kontrol/models/cash_models.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/finance_reason_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/large_dialog_parts.dart';
import 'package:site_kapi_kontrol/ui/helpers/cursor_loader.dart';
import 'package:site_kapi_kontrol/ui/helpers/date_input.dart';
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_4b_access.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_errors.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_write_mixin.dart';
import 'package:site_kapi_kontrol/ui/helpers/form_validation.dart';
import 'package:site_kapi_kontrol/ui/helpers/istanbul_time.dart';
import 'package:site_kapi_kontrol/ui/helpers/money.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/helpers/text_length.dart';
import 'package:site_kapi_kontrol/ui/widgets/cursor_list_body.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_4b_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/money_field.dart';

/// Hesaplar arası aktarım penceresi (Platform Faz 4b, Ö4): tek işlemde iki hareket (çıkış + giriş). Aynı hesap
/// seçilemez; tarih bugünden ileri olamaz ve AÇIK ayda olmalıdır (sunucu doğrular). Aktarım tutarı kaynak hesabın
/// bakiyesini aşıyorsa uyarılır (engellenmez; sunucu hesabı eksiye düşürebilir ve bunu bildirir).
class FinanceTransferDialog extends StatefulWidget {
  const FinanceTransferDialog({super.key, required this.scope, required this.accounts, this.now, this.onRefreshNeeded});

  final PeopleScope scope;

  /// Aktif hesaplar (en az ikisi).
  final List<CashAccount> accounts;
  final DateTime Function()? now;
  final VoidCallback? onRefreshNeeded;

  static const int maxDescriptionLength = 200;

  static Future<FinanceWriteOutcome?> show(
    BuildContext context, {
    required PeopleScope scope,
    required List<CashAccount> accounts,
    DateTime Function()? now,
    VoidCallback? onRefreshNeeded,
  }) {
    return showDialog<FinanceWriteOutcome>(
      context: context,
      barrierDismissible: false,
      builder: (_) => FinanceTransferDialog(scope: scope, accounts: accounts, now: now, onRefreshNeeded: onRefreshNeeded),
    );
  }

  @override
  State<FinanceTransferDialog> createState() => _FinanceTransferDialogState();
}

class _FinanceTransferDialogState extends State<FinanceTransferDialog> with FinanceWriteMixin, FinanceDiscardGuard {
  @override
  String get keyPrefix => 'xfer';

  @override
  Object? get keyOwner => widget.scope.authService;

  @override
  bool get closeLocked => submitting;

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _description = TextEditingController();
  late final TextEditingController _date = TextEditingController(text: formatDateField(_today()));
  int? _from;
  int? _to;

  DateTime _today() {
    final wall = istanbulNow(widget.now?.call());
    return DateTime(wall.year, wall.month, wall.day);
  }

  CashAccount? _accountOf(int? id) {
    for (final a in widget.accounts) {
      if (a.id == id) return a;
    }
    return null;
  }

  @override
  void dispose() {
    disposeWrite();
    _amount.dispose();
    _description.dispose();
    _date.dispose();
    super.dispose();
  }

  bool get _sameAccount => _from != null && _from == _to;

  Future<void> _submit() async {
    if (writeBlocked) return;
    final ok = validateForm(_formKey, validateExtra: () => _from != null && _to != null && !_sameAccount);
    if (!ok) {
      setState(() => submitError = kFixFieldsMessage);
      return;
    }
    final minor = parseMoney(_amount.text).minor!;
    final date = parseDateField(_date.text)!;
    final description = _description.text.trim();
    final from = _accountOf(_from)!;
    final to = _accountOf(_to)!;
    await runWrite<TransferWriteResult>(
      signature: 'xfer|$_from|$_to|$minor|${formatDateField(date)}|$description',
      action: (key) => widget.scope.f4Call(
        (api, t, s) => api.createTransfer(
          token: t,
          siteCode: s,
          fromAccountId: from.id,
          toAccountId: to.id,
          amountMinor: minor,
          transferDate: date,
          description: description,
          idempotencyKey: key,
        ),
      ),
      onSuccess: (_) => popIfCurrent(
        context,
        FinanceWriteOutcome('Aktarım yapıldı: ${formatMinor(minor)} (${from.name} → ${to.name}).'),
      ),
      failure: 'Aktarım yapılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.',
    );
  }

  void _notify() {
    if (!needsRefreshOnClose) return;
    needsRefreshOnClose = false;
    widget.onRefreshNeeded?.call();
  }

  Widget _picker({
    required String keyName,
    required String label,
    required int? value,
    required ValueChanged<int?> onChanged,
    required String? errorText,
  }) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final account = _accountOf(value);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<int>(
          key: ValueKey<String>(keyName),
          isExpanded: true,
          initialValue: value,
          dropdownColor: p.surface,
          style: th.bodyMedium?.copyWith(color: p.text),
          decoration: InputDecoration(labelText: label, prefixIcon: const Icon(Icons.account_balance_rounded)),
          items: [
            for (final a in widget.accounts)
              DropdownMenuItem<int>(
                value: a.id,
                child: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: submitting ? null : onChanged,
          validator: (v) => v == null ? '$label seçin.' : null,
          autovalidateMode: AutovalidateMode.onUserInteraction,
        ),
        if (account != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.xs, left: AppSpace.md),
            child: Semantics(
              label: 'Bakiye: ${moneySemanticLabel(account.balanceMinor)}',
              child: ExcludeSemantics(
                child: Text(
                  'Bakiye: ${formatMinor(account.balanceMinor)}',
                  style: th.bodySmall?.copyWith(color: p.textSecondary, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.xs, left: AppSpace.md),
            child: Text(errorText, style: th.bodySmall?.copyWith(color: AppTone.danger.ink(p))),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final from = _accountOf(_from);
    final minor = parseMoney(_amount.text).minor;
    final exceeds = from != null && minor != null && minor > from.balanceMinor;
    return PopScope(
      canPop: canPopNow,
      onPopInvokedWithResult: (didPop, _) {
        handleBlockedPop(didPop);
        if (didPop) _notify();
      },
      child: AppDialog(
        title: 'Hesaplar Arası Aktarım',
        subtitle: widget.scope.siteName.isEmpty ? null : widget.scope.siteName,
        icon: Icons.swap_horiz_rounded,
        actions: [
          TextButton(
            onPressed: submitting ? null : requestClose,
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            key: const ValueKey<String>('finance_transfer_submit'),
            onPressed: (writeBlocked || widget.accounts.length < 2) ? null : _submit,
            child: Text(submitting ? 'Aktarılıyor...' : 'Aktar'),
          ),
        ],
        child: widget.accounts.length < 2
            ? const InlineNotice(
                key: ValueKey<String>('finance_transfer_need_two'),
                tone: AppTone.info,
                message: 'Aktarım için en az iki aktif hesap gerekir. Önce ikinci bir hesap ekleyin.',
              )
            : Form(
                key: _formKey,
                onChanged: markDirty,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (submitError != null) FinanceSubmitError(message: submitError!),
                    _picker(
                      keyName: 'finance_transfer_from',
                      label: 'Çıkış hesabı',
                      value: _from,
                      onChanged: (v) => setState(() {
                        markDirty();
                        _from = v;
                      }),
                      errorText: null,
                    ),
                    const SizedBox(height: AppSpace.md),
                    _picker(
                      keyName: 'finance_transfer_to',
                      label: 'Giriş hesabı',
                      value: _to,
                      onChanged: (v) => setState(() {
                        markDirty();
                        _to = v;
                      }),
                      errorText: _sameAccount ? 'Çıkış ve giriş hesabı aynı olamaz.' : null,
                    ),
                    const SizedBox(height: AppSpace.md),
                    MoneyFormField(
                      key: const ValueKey<String>('finance_transfer_amount_group'),
                      fieldKey: const ValueKey<String>('finance_transfer_amount'),
                      controller: _amount,
                      enabled: !submitting,
                      label: 'Aktarım tutarı',
                      textInputAction: TextInputAction.next,
                      onChanged: (_) => setState(() {}),
                    ),
                    if (exceeds) ...[
                      const SizedBox(height: AppSpace.sm),
                      InlineNotice(
                        key: const ValueKey<String>('finance_transfer_exceeds'),
                        tone: AppTone.warning,
                        message:
                            'Bu tutar çıkış hesabının bakiyesini (${formatMinor(from.balanceMinor)}) aşıyor; hesap '
                            'eksiye düşer. Kayıtları kontrol edin.',
                        semanticsLabel: spokenMoneyText(
                          'Bu tutar çıkış hesabının bakiyesini (${formatMinor(from.balanceMinor)}) aşıyor; hesap eksiye düşer. Kayıtları kontrol edin.',
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpace.md),
                    FinanceDateField(
                      key: const ValueKey<String>('finance_transfer_date_group'),
                      controller: _date,
                      label: 'Aktarım tarihi',
                      enabled: !submitting,
                      maxDate: _today(),
                    ),
                    const SizedBox(height: AppSpace.md),
                    TextFormField(
                      key: const ValueKey<String>('finance_transfer_description'),
                      controller: _description,
                      enabled: !submitting,
                      minLines: 1,
                      maxLines: 3,
                      maxLength: FinanceTransferDialog.maxDescriptionLength,
                      maxLengthEnforcement: MaxLengthEnforcement.none,
                      buildCounter: (context, {required currentLength, required isFocused, maxLength}) =>
                          characterCounter(context, trimmedCodePoints(_description.text), FinanceTransferDialog.maxDescriptionLength),
                      textCapitalization: TextCapitalization.sentences,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Açıklama (isteğe bağlı)',
                        alignLabelWithHint: true,
                        prefixIcon: Icon(Icons.notes_rounded),
                      ),
                      validator: (value) => trimmedCodePoints(value ?? '') > FinanceTransferDialog.maxDescriptionLength
                          ? 'Açıklama en çok ${FinanceTransferDialog.maxDescriptionLength} karakter olabilir.'
                          : null,
                    ),
                    const SizedBox(height: AppSpace.sm),
                    Text(
                      'Aktarım iki hareket yazar (çıkış ve giriş). Yanlışsa silinmez; Aktarım Geçmişi\'nden iptal edilir.',
                      style: th.bodySmall?.copyWith(color: p.textSecondary),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

/// Aktarım geçmişi: son aktarımlar (yeniden eskiye); yazma yetkisi olan, iptal edilmemiş aktarımı nedenli onayla
/// iptal edebilir (iki ayna hareket yazılır). Hata asla "aktarım yok" demez.
class FinanceTransfersDialog extends StatefulWidget {
  const FinanceTransfersDialog({super.key, required this.scope, this.onChanged});

  final PeopleScope scope;
  final VoidCallback? onChanged;

  static Future<void> show(BuildContext context, {required PeopleScope scope, VoidCallback? onChanged}) {
    return showDialog<void>(
      context: context,
      builder: (_) => FinanceTransfersDialog(scope: scope, onChanged: onChanged),
    );
  }

  @override
  State<FinanceTransfersDialog> createState() => _FinanceTransfersDialogState();
}

class _FinanceTransfersDialogState extends State<FinanceTransfersDialog> {
  bool _opening = false;

  late final CursorLoader<AccountTransfer> _loader = CursorLoader<AccountTransfer>(
    fetch: (before) async {
      final page = await widget.scope.f4Call((api, t, s) => api.listTransfers(token: t, siteCode: s, beforeId: before));
      return (items: page.items, next: page.nextBeforeId);
    },
    keyOf: (t) => t.id,
    notify: () {
      if (mounted) setState(() {});
    },
    isAlive: () => mounted,
    errorFallback: 'Aktarımlar yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
    moreErrorFallback: 'Daha fazla aktarım yüklenemedi. Tekrar deneyin.',
    messageOf: financeMessageOf,
  );

  @override
  void initState() {
    super.initState();
    unawaited(_loader.reload());
  }

  @override
  void dispose() {
    _loader.dispose();
    super.dispose();
  }

  Future<void> _void(AccountTransfer transfer) async {
    if (_opening) return;
    _opening = true;
    try {
      final done = await FinanceReasonDialog.show(
        context,
        title: 'Aktarımı İptal Et',
        subtitle: '${transfer.fromName ?? 'Hesap'} → ${transfer.toName ?? 'Hesap'}',
        message:
            '${formatMinor(transfer.amountMinor)} tutarındaki aktarım iptal edilir: iki hesapta da ters hareket yazılır. '
            'Aktarım kaydı silinmez.',
        semanticMessage:
            spokenMoneyText('${formatMinor(transfer.amountMinor)} tutarındaki aktarım iptal edilir: iki hesapta da ters hareket yazılır. Aktarım kaydı silinmez.'),
        confirmLabel: 'Aktarımı İptal Et',
        signatureBase: 'xfer-void|${transfer.id}',
        keyPrefix: 'xfer-v',
        keyOwner: widget.scope.authService,
        onUncertain: () {
          widget.onChanged?.call();
          if (mounted) unawaited(_loader.reload());
        },
        failure: 'Aktarım iptal edilemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
        action: (reason, key) => widget.scope.f4Call(
          (api, t, s) => api.voidTransfer(token: t, siteCode: s, transferId: transfer.id, reason: reason, idempotencyKey: key),
        ),
      );
      if (!mounted) return;
      if (done) {
        widget.onChanged?.call();
        showFinanceSnack(context, 'Aktarım iptal edildi.');
        unawaited(_loader.reload());
      }
    } finally {
      _opening = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    return AppDialog(
      title: 'Aktarım Geçmişi',
      icon: Icons.swap_horiz_rounded,
      actions: [
        TextButton(
          key: const ValueKey<String>('finance_transfers_close'),
          onPressed: () => popIfCurrent(context),
          child: const Text('Kapat'),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(header: true, container: true, child: Text('Aktarımlar', style: th.titleMedium)),
              ),
              IconButton(
                tooltip: 'Yenile',
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                onPressed: _loader.loading ? null : () => unawaited(_loader.reload()),
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          CursorListBody<AccountTransfer>(
            loader: _loader,
            emptyIcon: Icons.swap_horiz_rounded,
            emptyTitle: 'Henüz hesaplar arası aktarım yapılmamış.',
            skeletonRows: 2,
            itemBuilder: (context, transfer) => _TransferTile(
              transfer: transfer,
              onVoid: widget.scope.canWrite && !transfer.voided ? () => _void(transfer) : null,
              busy: _opening,
            ),
          ),
        ],
      ),
    );
  }
}

class _TransferTile extends StatelessWidget {
  const _TransferTile({required this.transfer, this.onVoid, this.busy = false});

  final AccountTransfer transfer;
  final VoidCallback? onVoid;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final t = transfer;
    final route = '${t.fromName ?? 'Hesap'} → ${t.toName ?? 'Hesap'}';
    final semantic = StringBuffer('Aktarım: $route. ${moneySemanticLabel(t.amountMinor)}. ${formatCrmDate(t.transferDate)}.');
    if (t.description != null) semantic.write(' ${t.description}.');
    if (t.voided) semantic.write(' İptal edildi.');
    return DialogPanel(
      key: ValueKey<String>('transfer_${t.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            container: true,
            label: semantic.toString(),
            child: ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (t.voided)
                    const Padding(
                      padding: EdgeInsets.only(bottom: AppSpace.xs),
                      child: DialogMetaPill('İptal edildi', tone: AppTone.neutral, icon: Icons.block_rounded),
                    ),
                  Text(route, style: th.titleSmall),
                  Text(
                    formatMinor(t.amountMinor),
                    style: th.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      decoration: t.voided ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  Text(formatCrmDate(t.transferDate), style: th.bodySmall?.copyWith(color: p.textSecondary)),
                  if (t.description != null) Text(t.description!, style: th.bodyMedium),
                ],
              ),
            ),
          ),
          if (onVoid != null) ...[
            const SizedBox(height: AppSpace.sm),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                key: ValueKey<String>('transfer_void_${t.id}'),
                onPressed: busy ? null : onVoid,
                icon: const Icon(Icons.undo_rounded, size: 18),
                label: const Text('İptal Et'),
                style: TextButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  foregroundColor: AppTone.danger.ink(p),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
