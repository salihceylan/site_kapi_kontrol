import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/finance_refund.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/finance_reason_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/finance_refund_approve_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/finance_refund_receipt_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/large_dialog_parts.dart';
import 'package:site_kapi_kontrol/ui/helpers/date_input.dart';
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_4b_access.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_errors.dart';
import 'package:site_kapi_kontrol/ui/helpers/money.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart' show ListSkeleton, listCardPadding;

/// Alacak iadesi talepleri (karar K4): sakinlerin "Fazla ödememi iade et" talepleri ve yöneticinin açtıkları. Fazla ödeme varsayılan olarak ALACAK kalır ve sonraki borçtan düşer;
/// iade yalnız istenirse ve YÖNETİCİ ONAYIYLA yapılır. Yönetici talebi onaylar (ödeme Hesabını SEÇER; Hesaptan çıkış kaydı + iade makbuzu yazılır) ya da nedenle reddeder;
/// onaylı iade, yanlışsa nedenle geri alınır. Kurul üyesi (salt okunur) listeyi görür, eylem düğmesi çizilmez.
///
/// - Hata asla "talep yok" demez: okunamazsa neden yazılır ve "Tekrar Dene" çıkar.
/// - Bir karar yazılınca liste yeniden okunur ve [onChanged] çağrılır (dikkat barı / şerit tazelenir).
class FinanceRefundsDialog extends StatefulWidget {
  const FinanceRefundsDialog({super.key, required this.scope, this.onChanged});

  final PeopleScope scope;
  final VoidCallback? onChanged;

  static Future<void> show(BuildContext context, {required PeopleScope scope, VoidCallback? onChanged}) {
    return showDialog<void>(
      context: context,
      builder: (_) => FinanceRefundsDialog(scope: scope, onChanged: onChanged),
    );
  }

  @override
  State<FinanceRefundsDialog> createState() => _FinanceRefundsDialogState();
}

class _FinanceRefundsDialogState extends State<FinanceRefundsDialog> {
  static const List<(String, String)> _filters = <(String, String)>[
    ('requested', 'Bekleyen'),
    ('approved', 'İade edilen'),
    ('all', 'Tümü'),
  ];

  String _status = 'requested';
  RefundPage? _page;
  List<RefundRequest> _items = const <RefundRequest>[];
  bool _loading = true;
  bool _loadingMore = false;
  bool _busy = false;
  String? _error;
  int _token = 0;

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
    final token = ++_token;
    setState(() {
      _loading = true;
      _error = null;
      _items = const <RefundRequest>[]; // yenilenirken eski satırlar gösterilmez
    });
    try {
      final page = await widget.scope.f4Call((api, t, s) => api.listRefunds(token: t, siteCode: s, status: _status));
      if (!mounted || token != _token) return;
      setState(() {
        _page = page;
        _items = page.items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || token != _token) return;
      setState(() {
        _loading = false;
        _error = financeMessageOf(e, 'İade talepleri yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.');
      });
    }
  }

  Future<void> _loadMore() async {
    final before = _page?.nextBeforeId;
    if (before == null || _loadingMore) return;
    final token = _token;
    setState(() => _loadingMore = true);
    try {
      final page = await widget.scope.f4Call((api, t, s) => api.listRefunds(token: t, siteCode: s, status: _status, beforeId: before));
      if (!mounted || token != _token) return;
      setState(() {
        _page = page;
        _items = <RefundRequest>[..._items, ...page.items];
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted || token != _token) return;
      setState(() {
        _loadingMore = false;
        _error = financeMessageOf(e, 'Devamı yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.');
      });
    }
  }

  void _select(String status) {
    if (status == _status || _busy) return;
    setState(() => _status = status);
    unawaited(_load());
  }

  Future<void> _afterDecision(String? message) async {
    if (message != null && mounted) showFinanceSnack(context, message);
    widget.onChanged?.call();
    if (mounted) await _load();
  }

  Future<void> _run(Future<void> Function() work) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await work();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _approve(RefundRequest refund) => _run(() async {
    final approved = await FinanceRefundApproveDialog.show(context, scope: widget.scope, refund: refund);
    if (approved == null) return;
    final number = approved.receipt?.number;
    await _afterDecision(number == null ? 'İade onaylandı.' : 'İade onaylandı. İade makbuzu: $number.');
  });

  Future<void> _reject(RefundRequest refund) => _run(() async {
    final done = await FinanceReasonDialog.show(
      context,
      title: 'İade Talebini Reddet',
      subtitle: refund.apartmentLabel,
      message: '${formatMinor(refund.amountMinor)} tutarındaki iade talebi reddedilir; tutar sakinin alacağı olarak kalır ve sonraki borçtan düşer. '
          'Ret nedeni sakine gösterilir.',
      semanticMessage: spokenMoneyText('${formatMinor(refund.amountMinor)} tutarındaki iade talebi reddedilir; tutar sakinin alacağı olarak kalır ve sonraki borçtan düşer. Ret nedeni sakine gösterilir.'),
      confirmLabel: 'Talebi Reddet',
      signatureBase: 'reject|${refund.id}',
      reasonLabel: 'Ret nedeni',
      icon: Icons.block_rounded,
      keyPrefix: 'rfn-rej',
      keyOwner: widget.scope.authService,
      failure: 'İade talebi reddedilemedi. Bağlantınızı kontrol edip tekrar deneyin.',
      action: (reason, key) => widget.scope.f4Call((api, t, s) => api.rejectRefund(token: t, siteCode: s, refundId: refund.id, reason: reason, idempotencyKey: key)),
      onUncertain: () => unawaited(_afterDecision(null)),
    );
    if (done) await _afterDecision('İade talebi reddedildi.');
  });

  Future<void> _reverse(RefundRequest refund) => _run(() async {
    final text = '${formatMinor(refund.amountMinor)} tutarındaki iade geri alınır: hesaptan çıkış kaydı ters çevrilir, iade makbuzu iptal sayılır ve tutar '
        'sakinin alacağına geri döner. Yalnız yanlış onaylanan iade için kullanın; kayıt silinmez, geri alma ayrıca kaydedilir.';
    final done = await FinanceReasonDialog.show(
      context,
      title: 'İadeyi Geri Al',
      subtitle: refund.apartmentLabel,
      message: text,
      semanticMessage: spokenMoneyText(text),
      confirmLabel: 'İadeyi Geri Al',
      signatureBase: 'reverse|${refund.id}',
      reasonLabel: 'Geri alma nedeni',
      keyPrefix: 'rfn-rev',
      keyOwner: widget.scope.authService,
      failure: 'İade geri alınamadı. Bağlantınızı kontrol edip tekrar deneyin.',
      action: (reason, key) => widget.scope.f4Call((api, t, s) => api.reverseRefund(token: t, siteCode: s, refundId: refund.id, reason: reason, idempotencyKey: key)),
      onUncertain: () => unawaited(_afterDecision(null)),
    );
    if (done) await _afterDecision('İade geri alındı.');
  });

  Future<void> _showReceipt(RefundRequest refund) => _run(() => FinanceRefundReceiptDialog.show(context, refund: refund));

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final page = _page;
    final canWrite = widget.scope.canWrite;
    final Widget body;
    if (_loading) {
      body = const ListSkeleton(rows: 3);
    } else if (_error != null && _items.isEmpty) {
      body = InlineNotice(key: const ValueKey<String>('finance_refunds_error'), message: _error!, onRetry: _load);
    } else {
      final pending = page?.pendingCount ?? 0;
      final total = formatMinor(page?.pendingTotalMinor ?? 0);
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Fazla ödeme varsayılan olarak alacak kalır ve sonraki borçtan düşer. Sakin isterse iade talep eder; iade yalnız sizin onayınızla yapılır. '
            'Onayladığınızda seçtiğiniz hesaptan çıkış yazılır ve sakine iade makbuzu düzenlenir.',
            style: th.bodySmall?.copyWith(color: p.textSecondary),
          ),
          const SizedBox(height: AppSpace.md),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.xs,
            children: [
              for (final (value, label) in _filters)
                ChoiceChip(
                  key: ValueKey<String>('finance_refunds_filter_$value'),
                  label: Text(label),
                  selected: _status == value,
                  onSelected: _busy ? null : (_) => _select(value),
                ),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          Semantics(
            container: true,
            label: pending == 0 ? 'Onay bekleyen iade talebi yok.' : '$pending iade talebi onay bekliyor, toplam ${moneySemanticLabel(page?.pendingTotalMinor ?? 0)}.',
            child: ExcludeSemantics(
              child: Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.xs,
                children: [
                  DialogMetaPill(
                    pending == 0 ? 'Onay bekleyen yok' : '$pending talep onay bekliyor',
                    key: const ValueKey<String>('finance_refunds_pending'),
                    tone: pending == 0 ? null : AppTone.warning,
                    icon: Icons.hourglass_top_rounded,
                  ),
                  if (pending > 0) DialogMetaPill('Toplam $total', icon: Icons.account_balance_wallet_outlined),
                ],
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpace.sm),
            InlineNotice(key: const ValueKey<String>('finance_refunds_more_error'), tone: AppTone.warning, message: _error!),
          ],
          const SizedBox(height: AppSpace.md),
          if (_items.isEmpty)
            InlineNotice(
              key: const ValueKey<String>('finance_refunds_empty'),
              tone: AppTone.success,
              message: _status == 'requested' ? 'Onay bekleyen iade talebi yok.' : 'Bu süzgeçte iade talebi yok.',
            )
          else
            for (final refund in _items)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.sm),
                child: _RefundCard(
                  refund: refund,
                  canWrite: canWrite,
                  busy: _busy,
                  onApprove: () => _approve(refund),
                  onReject: () => _reject(refund),
                  onReverse: () => _reverse(refund),
                  onReceipt: () => _showReceipt(refund),
                ),
              ),
          if (page?.nextBeforeId != null)
            Align(
              alignment: Alignment.center,
              child: PrimaryActionButton(
                key: const ValueKey<String>('finance_refunds_more'),
                label: 'Daha fazla göster',
                icon: Icons.expand_more_rounded,
                variant: AppButtonVariant.tonal,
                expand: false,
                loading: _loadingMore,
                onPressed: _loadingMore || _busy ? null : _loadMore,
              ),
            ),
        ],
      );
    }
    return AppDialog(
      title: 'İade Talepleri',
      subtitle: widget.scope.siteName.isEmpty ? null : widget.scope.siteName,
      icon: Icons.currency_exchange_rounded,
      tone: AppTone.info,
      actions: [
        TextButton(
          key: const ValueKey<String>('finance_refunds_close'),
          onPressed: () => popIfCurrent(context),
          child: const Text('Kapat'),
        ),
      ],
      child: body,
    );
  }
}

class _RefundCard extends StatelessWidget {
  const _RefundCard({
    required this.refund,
    required this.canWrite,
    required this.busy,
    required this.onApprove,
    required this.onReject,
    required this.onReverse,
    required this.onReceipt,
  });

  final RefundRequest refund;
  final bool canWrite;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onReverse;
  final VoidCallback onReceipt;

  static AppTone _tone(RefundStatus status) => switch (status) {
    RefundStatus.requested => AppTone.warning,
    RefundStatus.approved => AppTone.success,
    RefundStatus.rejected => AppTone.danger,
    RefundStatus.reversed => AppTone.danger,
    _ => AppTone.info,
  };

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final amount = formatMinor(refund.amountMinor);
    final status = refund.status;
    final semantic = StringBuffer('Daire: ${refund.apartmentLabel}. İade tutarı ${spokenMoneyText(amount)}. ${status.label}.');
    if (refund.accountParty != null) semantic.write(' ${refund.accountParty!.label}.');
    if (refund.requestedByManager) semantic.write(' Yönetim sakin adına açtı.');
    return AppCard(
      key: ValueKey<String>('finance_refund_${refund.id}'),
      padding: listCardPadding(context),
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
                  Text(refund.apartmentLabel, style: th.titleMedium),
                  Text(amount, style: th.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: AppSpace.sm),
                  Wrap(
                    spacing: AppSpace.sm,
                    runSpacing: AppSpace.xs,
                    children: [
                      DialogMetaPill(status.label, key: ValueKey<String>('finance_refund_status_${refund.id}'), tone: _tone(status), icon: Icons.flag_rounded),
                      if (refund.accountParty != null) DialogMetaPill(refund.accountParty!.label, icon: Icons.person_outline_rounded),
                      if (refund.requestedAt != null) DialogMetaPill('Talep ${formatCrmDate(refund.requestedAt)}', icon: Icons.event_rounded),
                      if (refund.requestedByManager) const DialogMetaPill('Yönetim açtı', icon: Icons.admin_panel_settings_outlined),
                    ],
                  ),
                  if (refund.note != null) ...[
                    const SizedBox(height: AppSpace.sm),
                    Text('Sakinin notu: ${refund.note}', style: th.bodySmall?.copyWith(color: p.textSecondary)),
                  ],
                  if (refund.status == RefundStatus.rejected && refund.rejectReason != null) ...[
                    const SizedBox(height: AppSpace.xs),
                    Text('Ret nedeni: ${refund.rejectReason}', style: th.bodySmall?.copyWith(color: p.textSecondary)),
                  ],
                  if (refund.receipt != null) ...[
                    const SizedBox(height: AppSpace.xs),
                    Text(
                      'İade makbuzu ${refund.receipt!.number}${refund.payAccountName == null ? '' : ' • ${refund.payAccountName}'}',
                      style: th.bodySmall?.copyWith(color: p.textSecondary),
                    ),
                  ],
                  if (refund.status == RefundStatus.reversed && refund.reversalReason != null) ...[
                    const SizedBox(height: AppSpace.xs),
                    Text('Geri alma nedeni: ${refund.reversalReason}', style: th.bodySmall?.copyWith(color: p.textSecondary)),
                  ],
                ],
              ),
            ),
          ),
          if ((canWrite && (refund.isPending || refund.isApproved)) || refund.receipt != null) ...[
            const SizedBox(height: AppSpace.md),
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.sm,
              children: [
                if (canWrite && refund.isPending) ...[
                  PrimaryActionButton(
                    key: ValueKey<String>('finance_refund_approve_${refund.id}'),
                    label: 'Onayla',
                    icon: Icons.check_rounded,
                    expand: false,
                    onPressed: busy ? null : onApprove,
                  ),
                  PrimaryActionButton(
                    key: ValueKey<String>('finance_refund_reject_${refund.id}'),
                    label: 'Reddet',
                    icon: Icons.block_rounded,
                    variant: AppButtonVariant.tonal,
                    tone: AppTone.danger,
                    expand: false,
                    onPressed: busy ? null : onReject,
                  ),
                ],
                if (refund.receipt != null)
                  PrimaryActionButton(
                    key: ValueKey<String>('finance_refund_receipt_${refund.id}'),
                    label: 'Makbuzu Gör',
                    icon: Icons.receipt_long_rounded,
                    variant: AppButtonVariant.tonal,
                    expand: false,
                    onPressed: busy ? null : onReceipt,
                  ),
                if (canWrite && refund.isApproved)
                  PrimaryActionButton(
                    key: ValueKey<String>('finance_refund_reverse_${refund.id}'),
                    label: 'Geri Al',
                    icon: Icons.undo_rounded,
                    variant: AppButtonVariant.tonal,
                    tone: AppTone.danger,
                    expand: false,
                    onPressed: busy ? null : onReverse,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
