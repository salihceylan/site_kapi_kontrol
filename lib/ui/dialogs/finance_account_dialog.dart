import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/finance.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/finance_payment_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/finance_reverse_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/large_dialog_parts.dart';
import 'package:site_kapi_kontrol/ui/helpers/cursor_loader.dart';
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/helpers/money.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/widgets/cursor_list_body.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_parts.dart';

/// Daire hesap ekstresi penceresi (Platform Faz 4a): güncel bakiye (borç / alacak simge + metinle), vadesi
/// geçen tutar, kim öder ve hareketler (en yeni üstte; "Daha fazla yükle" `before_id` imleciyle).
///
/// - Ters kayıtlar işaretlidir: iptal edilen kayıt "İptal edildi" rozeti ve üstü çizili tutarla, ters kayıt
///   "Ters kayıt" rozeti ve nedeniyle gösterilir. Silme YOKTUR.
/// - Yazma eylemleri (Tahsilat Ekle, Düzelt, İptal Et) YALNIZ [PeopleScope.canWrite] iken vardır; kurul üyesi
///   salt okur. Her yazmadan sonra ekstre yeniden okunur ve [onChanged] çağrılır (liste / özet tazelenir).
/// - Hata asla "borç yok / hareket yok" demez: bakiye okunamadıysa hata + "Tekrar Dene" gösterilir; eski /
///   yavaş yanıt yenisini ezmez ([CursorLoader] jetonu ve başlık sırası).
class FinanceAccountDialog extends StatefulWidget {
  const FinanceAccountDialog({
    super.key,
    required this.scope,
    required this.apartmentId,
    this.initialLabel = '',
    this.onChanged,
    this.now,
  });

  final PeopleScope scope;
  final int apartmentId;

  /// Ekstre gelene kadar başlıkta görünen daire adı (listeden).
  final String initialLabel;
  final VoidCallback? onChanged;
  final DateTime Function()? now;

  static Future<void> show(
    BuildContext context, {
    required PeopleScope scope,
    required int apartmentId,
    String initialLabel = '',
    VoidCallback? onChanged,
    DateTime Function()? now,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => FinanceAccountDialog(
        scope: scope,
        apartmentId: apartmentId,
        initialLabel: initialLabel,
        onChanged: onChanged,
        now: now,
      ),
    );
  }

  @override
  State<FinanceAccountDialog> createState() => _FinanceAccountDialogState();
}

class _FinanceAccountDialogState extends State<FinanceAccountDialog> {
  AccountView? _header;
  int _headerSeq = 0;
  bool _opening = false;

  late final CursorLoader<LedgerEntry> _loader = CursorLoader<LedgerEntry>(
    fetch: (before) async {
      // Başlık yalnız İLK sayfadan ve yalnız EN SON isteğin yanıtından alınır (eski yanıt yenisini ezmez).
      final seq = before == null ? ++_headerSeq : _headerSeq;
      try {
        final view = await widget.scope.authService.getFinanceAccount(
          widget.scope.siteCode,
          widget.apartmentId,
          beforeId: before,
        );
        if (before == null && seq == _headerSeq && mounted) _header = view;
        return (items: view.items, next: view.nextBeforeId);
      } catch (_) {
        // İlk sayfa okunamadı: eski bakiye gösterilmez (yazmadan önceki tutar yanıltmasın).
        if (before == null && seq == _headerSeq && mounted) _header = null;
        rethrow;
      }
    },
    keyOf: (e) => e.id,
    notify: () {
      if (mounted) setState(() {});
    },
    isAlive: () => mounted,
    errorFallback: 'Ekstre yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
    moreErrorFallback: 'Daha fazla hareket yüklenemedi. Tekrar deneyin.',
  );

  bool get _canWrite => widget.scope.canWrite;

  @override
  void initState() {
    super.initState();
    unawaited(_loader.reload());
  }

  @override
  void dispose() {
    ++_headerSeq;
    _loader.dispose();
    super.dispose();
  }

  void _afterChange(String? message) {
    widget.onChanged?.call();
    if (!mounted) return;
    if (message != null) AppSnack.show(context, message, kind: AppSnackKind.success);
    unawaited(_loader.reload());
  }

  /// Belirsiz sonuç / eskimiş kayıt: ekstre ve üst liste tazelenir (mesaj yok).
  void _refreshOnly() {
    widget.onChanged?.call();
    if (mounted) unawaited(_loader.reload());
  }

  Future<void> _addPayment() async {
    if (_opening) return;
    _opening = true;
    final FinancePaymentOutcome? outcome;
    try {
      outcome = await FinancePaymentDialog.show(
        context,
        scope: widget.scope,
        apartmentId: widget.apartmentId,
        apartmentLabel: _title,
        now: widget.now,
        onRefreshNeeded: _refreshOnly,
      );
    } finally {
      _opening = false;
    }
    if (outcome != null) _afterChange(outcome.message);
  }

  Future<void> _correct(LedgerEntry entry) async {
    if (_opening) return;
    _opening = true;
    final FinancePaymentOutcome? outcome;
    try {
      outcome = await FinancePaymentDialog.show(
        context,
        scope: widget.scope,
        apartmentId: widget.apartmentId,
        apartmentLabel: _title,
        correcting: entry,
        now: widget.now,
        onRefreshNeeded: _refreshOnly,
      );
    } finally {
      _opening = false;
    }
    if (outcome != null) _afterChange(outcome.message);
  }

  Future<void> _reverse(LedgerEntry entry) async {
    if (_opening) return;
    _opening = true;
    final FinanceReverseOutcome? outcome;
    try {
      outcome = await FinanceReverseDialog.show(
        context,
        scope: widget.scope,
        entry: entry,
        onRefreshNeeded: _refreshOnly,
      );
    } finally {
      _opening = false;
    }
    if (outcome != null) _afterChange(outcome.message);
  }

  String get _title {
    final header = _header;
    if (header != null) {
      final text = financeApartmentTitle(header.apartment.blockName, header.apartment.label);
      if (text != '-') return text;
    }
    final initial = widget.initialLabel.trim();
    return initial.isEmpty ? 'Daire' : initial;
  }

  @override
  Widget build(BuildContext context) {
    final header = _header;
    return AppDialog(
      title: 'Hesap Ekstresi',
      subtitle: _title,
      icon: Icons.receipt_long_rounded,
      actions: [
        TextButton(
          onPressed: () => popIfCurrent(context),
          child: const Text('Kapat'),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (header != null) _buildHeader(context, header),
          if (header != null && _canWrite) ...[
            const SizedBox(height: AppSpace.md),
            PrimaryActionButton(
              key: const ValueKey<String>('finance_account_add_payment'),
              label: 'Tahsilat Ekle',
              icon: Icons.add_card_rounded,
              onPressed: _addPayment,
            ),
          ],
          const SizedBox(height: AppSpace.md),
          Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text('Hareketler', style: Theme.of(context).textTheme.titleMedium),
                ),
              ),
              IconButton(
                tooltip: 'Yenile',
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                onPressed: _loader.loading ? null : () => unawaited(_loader.reload()),
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          // Bakiye henüz okunamadıysa hata gövdede gösterilir; hareket listesi bakiye olmadan "hareket yok"
          // demez (CursorListBody hata / yükleme durumunu boş durumdan önce çizer).
          CursorListBody<LedgerEntry>(
            loader: _loader,
            emptyIcon: Icons.receipt_long_rounded,
            emptyTitle: 'Bu dairede henüz mali hareket yok.',
            skeletonRows: 2,
            itemBuilder: (context, entry) => Padding(
              padding: EdgeInsets.zero,
              child: LedgerEntryTile(
                entry: entry,
                showActor: _canWrite,
                actionsEnabled: !_opening,
                onCorrect: _canWrite && entry.canCorrect ? () => _correct(entry) : null,
                onReverse: _canWrite && entry.canReverse ? () => _reverse(entry) : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, AccountView header) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final balance = describeBalance(header.balanceMinor);
    final overdue = header.overdueMinor;
    return DialogPanel(
      key: const ValueKey<String>('finance_account_header'),
      tone: balance.direction == BalanceDirection.debt ? AppTone.danger : null,
      child: Semantics(
        container: true,
        label:
            '${balance.semanticLabel}.'
            '${overdue != null && overdue > 0 ? ' Vadesi geçen: ${moneySemanticLabel(overdue)}.' : ''}'
            ' ${payerPartyLabel(header.apartment.responsibleParty)}.',
        child: ExcludeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(balance.icon, color: balance.tone.ink(p)),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(child: Text(balance.title, style: th.titleMedium)),
                ],
              ),
              if (balance.amountText.isNotEmpty)
                Text(
                  balance.amountText,
                  key: const ValueKey<String>('finance_account_balance'),
                  style: th.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
              if (overdue != null && overdue > 0) ...[
                const SizedBox(height: AppSpace.xs),
                Text(
                  'Vadesi geçen: ${formatMinor(overdue)}',
                  style: th.bodyMedium?.copyWith(
                    color: AppTone.warning.ink(p),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              const SizedBox(height: AppSpace.xs),
              Text(
                payerPartyLabel(header.apartment.responsibleParty),
                style: th.bodySmall?.copyWith(color: p.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
