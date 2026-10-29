import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/cash_models.dart';
import 'package:site_kapi_kontrol/models/finance_refund.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/large_dialog_parts.dart';
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_4b_access.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_errors.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_write_mixin.dart';
import 'package:site_kapi_kontrol/ui/helpers/money.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_4b_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart' show filledToneStyle;

/// Alacak iadesi onayı (karar K4): yönetici iadenin hangi kasa / banka Hesabından ödeneceğini SEÇER (yazılım kendiliğinden seçmez), tutarı görür ve onaylar.
/// Onayda TEK işlemde Hesaptan çıkış kaydı, defter satırı ve iade makbuzu (IA-yıl-sıra) yazılır; tutar DEĞİŞTİRİLEMEZ. Nakit Hesapta bakiye yetmiyorsa sunucu 409 döner ve
/// neden pencerede yazılır (başka Hesap seçilebilir). Başarıda [RefundRequest] (onaylanmış, makbuzlu) ile kapanır.
class FinanceRefundApproveDialog extends StatefulWidget {
  const FinanceRefundApproveDialog({super.key, required this.scope, required this.refund});

  final PeopleScope scope;
  final RefundRequest refund;

  static Future<RefundRequest?> show(BuildContext context, {required PeopleScope scope, required RefundRequest refund}) {
    return showDialog<RefundRequest>(
      context: context,
      barrierDismissible: false,
      builder: (_) => FinanceRefundApproveDialog(scope: scope, refund: refund),
    );
  }

  @override
  State<FinanceRefundApproveDialog> createState() => _FinanceRefundApproveDialogState();
}

class _FinanceRefundApproveDialogState extends State<FinanceRefundApproveDialog> with FinanceWriteMixin {
  @override
  String get keyPrefix => 'rfn-ok';

  @override
  Object? get keyOwner => widget.scope.authService;

  List<CashAccount>? _accounts;
  bool _loading = true;
  String? _loadError;
  int? _accountId;
  int _token = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    ++_token;
    disposeWrite();
    super.dispose();
  }

  Future<void> _load() async {
    final token = ++_token;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final overview = await widget.scope.f4Call((api, t, s) => api.listAccounts(token: t, siteCode: s));
      if (!mounted || token != _token) return;
      final active = overview.activeAccounts;
      setState(() {
        _accounts = active;
        _loading = false;
        if (_accountId == null && active.length == 1) _accountId = active.first.id;
      });
    } catch (e) {
      if (!mounted || token != _token) return;
      setState(() {
        _loading = false;
        _loadError = financeMessageOf(e, 'Hesaplar yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.');
      });
    }
  }

  CashAccount? get _selected {
    for (final account in _accounts ?? const <CashAccount>[]) {
      if (account.id == _accountId) return account;
    }
    return null;
  }

  Future<void> _submit() async {
    final account = _selected;
    if (writeBlocked || account == null) return;
    await runWrite<RefundRequest>(
      signature: '${widget.refund.id}|${account.id}',
      action: (key) => widget.scope.f4Call(
        (api, t, s) => api.approveRefund(token: t, siteCode: s, refundId: widget.refund.id, payAccountId: account.id, idempotencyKey: key),
      ),
      onSuccess: (refund) => popIfCurrent(context, refund),
      failure: 'İade onaylanamadı. Bağlantınızı kontrol edip tekrar deneyin.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final refund = widget.refund;
    final amount = formatMinor(refund.amountMinor);
    final accounts = _accounts;
    final selected = _selected;
    // Nakit Hesapta bakiye yetmiyorsa onaydan ÖNCE uyarılır (sunucu yine de reddeder; engelleyen sunucudur).
    final shortCash = selected != null && selected.kind == CashAccountKind.cash && selected.balanceMinor < refund.amountMinor;
    final Widget accountBody;
    if (_loading) {
      accountBody = const DialogLoadingNote(text: 'Hesaplar yükleniyor...');
    } else if (_loadError != null) {
      accountBody = InlineNotice(key: const ValueKey<String>('finance_refund_accounts_error'), tone: AppTone.warning, message: _loadError!, onRetry: _load);
    } else if (accounts == null || accounts.isEmpty) {
      accountBody = const InlineNotice(
        key: ValueKey<String>('finance_refund_accounts_empty'),
        tone: AppTone.warning,
        message: 'İadenin ödeneceği kasa ya da banka hesabı yok. Önce Kasa bölümünden bir hesap ekleyin.',
      );
    } else {
      accountBody = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: [
              for (final account in accounts)
                ChoiceChip(
                  key: ValueKey<String>('finance_refund_account_${account.id}'),
                  avatar: Icon(cashKindIcon(account.kind), size: 18),
                  label: Text('${account.name} • ${formatMinor(account.balanceMinor)}'),
                  selected: _accountId == account.id,
                  onSelected: submitting ? null : (_) => setState(() => _accountId = account.id),
                ),
            ],
          ),
          if (shortCash) ...[
            const SizedBox(height: AppSpace.sm),
            InlineNotice(
              key: const ValueKey<String>('finance_refund_cash_short'),
              tone: AppTone.warning,
              message: 'Seçilen kasada yeterli nakit görünmüyor (${formatMinor(selected.balanceMinor)}). Başka bir hesap seçin ya da önce kasaya para girişi yapın.',
            ),
          ],
        ],
      );
    }
    return PopScope(
      canPop: !submitting,
      child: AppDialog(
        title: 'İadeyi Onayla',
        subtitle: widget.scope.siteName.isEmpty ? null : widget.scope.siteName,
        icon: Icons.currency_exchange_rounded,
        tone: AppTone.success,
        actions: [
          TextButton(
            key: const ValueKey<String>('finance_refund_approve_cancel'),
            onPressed: submitting ? null : () => popIfCurrent(context),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            key: const ValueKey<String>('finance_refund_approve_confirm'),
            style: filledToneStyle(context, tone: AppTone.success),
            onPressed: writeBlocked || selected == null ? null : _submit,
            child: Text(submitting ? 'İşleniyor...' : 'İadeyi Onayla'),
          ),
        ],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (submitError != null) FinanceSubmitError(key: const ValueKey<String>('finance_refund_approve_error'), message: submitError!),
            Text(
              '${refund.apartmentLabel}${refund.accountParty == null ? '' : ' • ${refund.accountParty!.label}'}',
              style: th.titleMedium,
            ),
            Text(
              amount,
              semanticsLabel: spokenMoneyText(amount),
              key: const ValueKey<String>('finance_refund_approve_amount'),
              style: th.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: AppSpace.sm),
            Text(
              'Onayladığınızda bu tutar seçtiğiniz hesaptan çıkış olarak yazılır, hesabın alacağından düşer ve sakine iade makbuzu düzenlenir. '
              'Tutar değiştirilemez; yanlış onay sonradan geri alınabilir.',
              style: th.bodyMedium,
            ),
            const SizedBox(height: AppSpace.md),
            const FinanceGroupTitle('Ödemenin yapılacağı hesap'),
            const SizedBox(height: AppSpace.sm),
            accountBody,
            if (accounts != null && accounts.length > 1 && selected == null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.sm),
                child: Text('Devam etmek için bir hesap seçin.', style: th.bodySmall?.copyWith(color: p.textSecondary)),
              ),
          ],
        ),
      ),
    );
  }
}
