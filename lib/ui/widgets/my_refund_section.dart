import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/finance.dart';
import 'package:site_kapi_kontrol/models/finance_refund.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/finance_refund_receipt_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/large_dialog_parts.dart';
import 'package:site_kapi_kontrol/ui/dialogs/my_refund_request_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/date_input.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_4b_access.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_errors.dart';
import 'package:site_kapi_kontrol/ui/helpers/money.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_parts.dart' show showFinanceSnack;
import 'package:site_kapi_kontrol/ui/widgets/my_finance_4b_parts.dart';

/// "Borcum" kartındaki fazla ödeme iadesi bölümü (karar K4, sakin): hesapta ALACAK (fazla ödeme) varsa "Fazla ödememi iade et" ile talep açılır; talepler ve durumları
/// (onay bekliyor / iade edildi + makbuz / reddedildi + nedeni / geri çekildi / geri alındı) listelenir. Fazla ödeme varsayılan olarak alacak kalır ve sonraki borçtan düşer;
/// iade YALNIZ site yönetiminin onayıyla yapılır, talep bir karar değildir. Bekleyen talebi onaydan önce geri çekilebilir.
///
/// - Alacak yoksa ve hiç talep yoksa HİÇBİR ŞEY çizilmez. Talepler okunamazsa "talep yok" denmez: neden yazılır ve "Tekrar Dene" çıkar.
/// - İstenebilecek tutar = alacak - bekleyen talepler; sıfırsa düğme pasif ve neden yazılır. Sunucu aynı sınırı yeniden sınar.
class MyRefundSection extends StatefulWidget {
  const MyRefundSection({super.key, required this.authService, required this.item});

  final AuthService authService;
  final MyFinanceApartment item;

  static const int collapsedCount = 3;

  @override
  State<MyRefundSection> createState() => _MyRefundSectionState();
}

class _MyRefundSectionState extends State<MyRefundSection> {
  List<RefundRequest>? _requests;
  String? _loadError;
  String? _actionError;
  bool _busy = false;
  bool _expanded = false;
  int _token = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(MyRefundSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Borcum tazelendi ve alacak değiştiyse (iade onaylandı / geri alındı) talepler de yeniden okunur.
    if (oldWidget.item.balanceMinor != widget.item.balanceMinor) unawaited(_load());
  }

  @override
  void dispose() {
    ++_token;
    super.dispose();
  }

  Future<void> _load() async {
    final token = ++_token;
    try {
      final items = await residentScopeOf(widget.authService, widget.item).f4Call(
        (api, t, _) => api.listMyRefundRequests(token: t, apartmentId: widget.item.apartmentId),
      );
      if (!mounted || token != _token) return;
      setState(() {
        _requests = items;
        _loadError = null;
      });
    } catch (e) {
      if (!mounted || token != _token) return;
      setState(() => _loadError = financeMessageOf(e, 'İade talepleriniz yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.'));
    }
  }

  int get _creditMinor => widget.item.balanceMinor < 0 ? -widget.item.balanceMinor : 0;

  int get _pendingMinor => (_requests ?? const <RefundRequest>[]).where((r) => r.isPending).fold<int>(0, (sum, r) => sum + r.amountMinor);

  int get _availableMinor {
    final left = _creditMinor - _pendingMinor;
    return left > 0 ? left : 0;
  }

  Future<void> _request() async {
    if (_busy || _availableMinor <= 0) return;
    setState(() {
      _busy = true;
      _actionError = null;
    });
    try {
      final created = await MyRefundRequestDialog.show(context, authService: widget.authService, item: widget.item, availableMinor: _availableMinor);
      if (created != null && mounted) {
        showFinanceSnack(context, 'İade talebiniz gönderildi. Site yönetimi onayladığında size bildirilir.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted) unawaited(_load());
  }

  Future<void> _cancel(RefundRequest request) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _actionError = null;
    });
    try {
      await residentScopeOf(widget.authService, widget.item).f4Call((api, t, _) => api.cancelMyRefundRequest(token: t, refundId: request.id));
      if (!mounted) return;
      showFinanceSnack(context, 'İade talebiniz geri çekildi.');
    } catch (e) {
      if (!mounted) return;
      _actionError = financeWriteMessage(e, 'İade talebi geri çekilemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted) unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final requests = _requests;
    final credit = _creditMinor;
    if (requests == null && _loadError == null) return const SizedBox.shrink(); // yüklenirken bölüm yer tutmaz
    if (_loadError != null && requests == null) {
      // Talepler okunamadı: alacak varsa yine de iade istenebilir; durum satırı yerine hata + "Tekrar Dene".
      if (credit <= 0) return const SizedBox.shrink();
    } else if (credit <= 0 && (requests?.isEmpty ?? true)) {
      return const SizedBox.shrink();
    }
    final available = _availableMinor;
    final shown = _expanded || (requests?.length ?? 0) <= MyRefundSection.collapsedCount ? (requests ?? const <RefundRequest>[]) : requests!.take(MyRefundSection.collapsedCount).toList();
    final hidden = (requests?.length ?? 0) - shown.length;
    final availableText = formatMinor(available);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.md),
      child: DialogPanel(
        key: const ValueKey<String>('my_refund_section'),
        tone: AppTone.info,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(header: true, container: true, child: Text('Fazla ödeme iadesi', style: th.titleSmall)),
            const SizedBox(height: AppSpace.xs),
            if (credit > 0) ...[
              Text(
                'Fazla ödemeniz alacak olarak kalır ve sonraki borçlarınızdan düşer. İsterseniz iadesini talep edebilirsiniz; iade site yönetiminin onayıyla yapılır.',
                style: th.bodySmall?.copyWith(color: p.textSecondary),
              ),
              const SizedBox(height: AppSpace.sm),
              if (available > 0)
                PrimaryActionButton(
                  key: const ValueKey<String>('my_refund_request'),
                  label: 'Fazla ödememi iade et',
                  icon: Icons.currency_exchange_rounded,
                  variant: AppButtonVariant.tonal,
                  expand: false,
                  loading: _busy,
                  onPressed: _busy ? null : _request,
                )
              else
                Text(
                  'Bekleyen iade talepleriniz alacağınızın tamamını kapsıyor.',
                  key: const ValueKey<String>('my_refund_all_pending'),
                  style: th.bodyMedium,
                ),
              if (available > 0 && _pendingMinor > 0) ...[
                const SizedBox(height: AppSpace.xs),
                Text(
                  'Yeni talep için kalan: $availableText',
                  semanticsLabel: spokenMoneyText('Yeni talep için kalan: $availableText'),
                  style: th.bodySmall?.copyWith(color: p.textSecondary),
                ),
              ],
            ],
            if (_actionError != null) ...[
              const SizedBox(height: AppSpace.sm),
              InlineNotice(key: const ValueKey<String>('my_refund_action_error'), tone: AppTone.warning, message: _actionError!),
            ],
            if (_loadError != null) ...[
              const SizedBox(height: AppSpace.sm),
              InlineNotice(key: const ValueKey<String>('my_refund_load_error'), tone: AppTone.warning, message: _loadError!, onRetry: _load),
            ],
            if (shown.isNotEmpty) ...[
              const SizedBox(height: AppSpace.md),
              Semantics(header: true, container: true, child: Text('İade taleplerim', style: th.labelLarge)),
              const SizedBox(height: AppSpace.sm),
              for (final request in shown)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpace.sm),
                  child: _RequestTile(request: request, busy: _busy, onCancel: () => _cancel(request)),
                ),
              if (hidden > 0 || _expanded && (requests?.length ?? 0) > MyRefundSection.collapsedCount)
                Align(
                  alignment: Alignment.center,
                  child: PrimaryActionButton(
                    key: const ValueKey<String>('my_refund_toggle'),
                    label: _expanded ? 'Daha az göster' : 'Tümünü göster ($hidden)',
                    icon: _expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                    variant: AppButtonVariant.tonal,
                    expand: false,
                    onPressed: () => setState(() => _expanded = !_expanded),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RequestTile extends StatelessWidget {
  const _RequestTile({required this.request, required this.busy, required this.onCancel});

  final RefundRequest request;
  final bool busy;
  final VoidCallback onCancel;

  static AppTone _tone(RefundStatus status) => switch (status) {
    RefundStatus.requested => AppTone.warning,
    RefundStatus.approved => AppTone.success,
    RefundStatus.rejected || RefundStatus.reversed => AppTone.danger,
    _ => AppTone.info,
  };

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final amount = formatMinor(request.amountMinor);
    final status = request.status;
    final semantic = StringBuffer('İade talebi, ${spokenMoneyText(amount)}. ${status.label}.');
    if (request.requestedAt != null) semantic.write(' Talep tarihi ${formatCrmDate(request.requestedAt)}.');
    if (request.status == RefundStatus.rejected && request.rejectReason != null) semantic.write(' Ret nedeni: ${request.rejectReason}.');
    return Column(
      key: ValueKey<String>('my_refund_${request.id}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          container: true,
          label: semantic.toString(),
          child: ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(amount, style: th.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: AppSpace.xs),
                Wrap(
                  spacing: AppSpace.sm,
                  runSpacing: AppSpace.xs,
                  children: [
                    DialogMetaPill(status.label, key: ValueKey<String>('my_refund_status_${request.id}'), tone: _tone(status), icon: Icons.flag_rounded),
                    if (request.requestedAt != null) DialogMetaPill(formatCrmDate(request.requestedAt), icon: Icons.event_rounded),
                  ],
                ),
                if (request.status == RefundStatus.rejected && request.rejectReason != null) ...[
                  const SizedBox(height: AppSpace.xs),
                  Text('Ret nedeni: ${request.rejectReason}', style: th.bodySmall?.copyWith(color: p.textSecondary)),
                ],
                if (request.receipt != null) ...[
                  const SizedBox(height: AppSpace.xs),
                  Text('İade makbuzu ${request.receipt!.number}', style: th.bodySmall?.copyWith(color: p.textSecondary)),
                ],
              ],
            ),
          ),
        ),
        if (request.isPending || request.receipt != null) ...[
          const SizedBox(height: AppSpace.sm),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: [
              if (request.isPending)
                PrimaryActionButton(
                  key: ValueKey<String>('my_refund_cancel_${request.id}'),
                  label: 'Talebi Geri Çek',
                  icon: Icons.undo_rounded,
                  variant: AppButtonVariant.tonal,
                  expand: false,
                  onPressed: busy ? null : onCancel,
                ),
              if (request.receipt != null)
                PrimaryActionButton(
                  key: ValueKey<String>('my_refund_receipt_${request.id}'),
                  label: 'Makbuzu Gör',
                  icon: Icons.receipt_long_rounded,
                  variant: AppButtonVariant.tonal,
                  expand: false,
                  onPressed: busy ? null : () => unawaited(FinanceRefundReceiptDialog.show(context, refund: request)),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
