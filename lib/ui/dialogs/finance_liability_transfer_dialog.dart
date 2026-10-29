import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/finance_liability.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/finance_reason_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/large_dialog_parts.dart';
import 'package:site_kapi_kontrol/ui/helpers/date_input.dart';
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_4b_access.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_errors.dart';
import 'package:site_kapi_kontrol/ui/helpers/money.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart' show ListSkeleton, listCardPadding;

/// Kiracı borcunu ev sahibine devretme penceresi (karar K1; gecikmede öneri K17). Bir dairenin DEVİR ÖNİZLEMESİNİ (kalemler, toplam,
/// gecikme tazminatı istisnası) ve devir GEÇMİŞİNİ gösterir; yönetici devri nedenle onaylar ya da geri alır.
///
/// Devir yazılımın kendiliğinden verdiği bir karar DEĞİLDİR (K1 deseni):
/// - ÖNİZLEME hiçbir şey yazmaz; onay, önizlemedeki toplamı ve özeti (`preview_hash`) sunucuya geri bildirir. Arada ödeme / ters kayıt
///   olduysa sunucu 409 `LIABILITY_TRANSFER_CHANGED` döner, HİÇBİR ŞEY yazılmaz; önizleme otomatik yenilenir ve yeniden onay istenir.
/// - ONAY nedenli ve ayrı bir penceredir ([FinanceReasonDialog]: neden zorunlu, çift gönderim korumalı, sonuç belirsizse aynı veri = aynı
///   `idempotency_key`). Malike uygulama içi bildirim gider.
/// - İZLİ: kayıt ve ters kayıtlar defterde KALIR (silinmez); geçmiş listesi kim / ne zaman / ne kadar / neden bilgisini gösterir.
/// - GERİ ALINABİLİR: devirden sonra ev sahibi hesabına ödeme girilmediği ve devrin kalemleri sonradan başka devirle taşınmadığı sürece
///   (sunucu `reversible` der; aksi halde "Geri Al" çıkmaz, nedeni yazılır).
/// - Gecikme tazminatı kalemleri devredilmez (kiracıda kalır); malik kaydı yoksa devir kapalıdır ve nedeni yazılır.
///
/// Yazma düğmeleri yalnız [PeopleScope.canWrite] iken vardır. Yazma sonrası [onChanged] çağrılır (üst liste / bakiye tazelenir).
class FinanceLiabilityTransferDialog extends StatefulWidget {
  const FinanceLiabilityTransferDialog({
    super.key,
    required this.scope,
    required this.apartmentId,
    required this.apartmentLabel,
    this.onChanged,
  });

  final PeopleScope scope;
  final int apartmentId;
  final String apartmentLabel;
  final VoidCallback? onChanged;

  /// Önizlemede en çok bu kadar kalem satırı çizilir (devir kalem sayısı sınırı 500; fazlası "ve N kalem daha" yazılır).
  static const int maxShownItems = 30;

  static Future<void> show(
    BuildContext context, {
    required PeopleScope scope,
    required int apartmentId,
    required String apartmentLabel,
    VoidCallback? onChanged,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => FinanceLiabilityTransferDialog(
        scope: scope,
        apartmentId: apartmentId,
        apartmentLabel: apartmentLabel,
        onChanged: onChanged,
      ),
    );
  }

  @override
  State<FinanceLiabilityTransferDialog> createState() => _FinanceLiabilityTransferDialogState();
}

class _FinanceLiabilityTransferDialogState extends State<FinanceLiabilityTransferDialog> {
  LiabilityPreview? _preview;
  List<LiabilityTransfer> _history = const <LiabilityTransfer>[];
  bool _loading = true;
  bool _asking = false;
  String? _loadError;
  String? _notice;
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

  /// Önizleme ve geçmiş birlikte okunur (biri okunamazsa eski bilgi gösterilmez; "Tekrar Dene").
  Future<void> _load({bool keepNotice = false}) async {
    final token = ++_token;
    setState(() {
      _loading = true;
      _loadError = null;
      _preview = null; // yenilenirken eski tutarlar gösterilmez (yanıltmasın)
      _history = const <LiabilityTransfer>[];
      if (!keepNotice) _notice = null;
    });
    try {
      final (preview, history) = await (
        widget.scope.f4Call((api, t, s) => api.previewLiabilityTransfer(token: t, siteCode: s, apartmentId: widget.apartmentId)),
        widget.scope.f4Call((api, t, s) => api.listLiabilityTransfers(token: t, siteCode: s, apartmentId: widget.apartmentId)),
      ).wait;
      if (!mounted || token != _token) return;
      setState(() {
        _preview = preview;
        _history = history;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || token != _token) return;
      setState(() {
        _preview = null;
        _history = const <LiabilityTransfer>[];
        _loading = false;
        _loadError = financeMessageOf(e, 'Devir bilgisi yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.');
      });
    }
  }

  void _afterWrite() {
    widget.onChanged?.call();
  }

  String _balancesText(int? tenant, int? owner) {
    final parts = <String>[
      if (tenant != null) 'Kiracı hesabı: ${describeBalance(tenant).badgeText}',
      if (owner != null) 'Ev sahibi hesabı: ${describeBalance(owner).badgeText}',
    ];
    return parts.join(' • ');
  }

  Future<void> _transfer() async {
    final preview = _preview;
    if (preview == null || !preview.canTransfer || _asking || !widget.scope.canWrite) return;
    setState(() => _asking = true);
    final message =
        '${widget.apartmentLabel}\n'
        '${preview.itemCount} borç kalemi, toplam ${formatMinor(preview.totalMinor)}, kiracı hesabından ev sahibi hesabına devredilecek.\n\n'
        'Kayıt silinmez: her kalem için ters kayıt ve ev sahibi hesabına yeni borç yazılır, ev sahibine bildirim gider. '
        'Gecikme tazminatı devredilmez. Devirden sonra ev sahibi hesabına ödeme girilmediği sürece geri alabilirsiniz.';
    LiabilityTransferResult? result;
    final bool done;
    try {
      done = await FinanceReasonDialog.show(
        context,
        title: 'Borcu Malike Devret',
        subtitle: widget.apartmentLabel,
        message: message,
        semanticMessage: spokenMoneyText(message),
        confirmLabel: 'Malike Devret',
        signatureBase: 'liab|${widget.scope.siteCode}|${widget.apartmentId}|${preview.previewHash}|${preview.totalMinor}',
        reasonLabel: 'Devir nedeni',
        icon: Icons.swap_horiz_rounded,
        tone: AppTone.warning,
        keyPrefix: 'liab',
        keyOwner: widget.scope.authService,
        failure: 'Borç devredilemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
        onUncertain: _afterWrite,
        action: (reason, key) async {
          result = await widget.scope.f4Call(
            (api, t, s) => api.createLiabilityTransfer(
              token: t,
              siteCode: s,
              apartmentId: widget.apartmentId,
              expectedTotalMinor: preview.totalMinor,
              expectedHash: preview.previewHash,
              reason: reason,
              idempotencyKey: key,
            ),
          );
        },
      );
    } finally {
      if (mounted) setState(() => _asking = false);
    }
    if (!mounted) return;
    if (done) {
      _afterWrite();
      final balances = _balancesText(result?.tenantBalanceMinor, result?.ownerBalanceMinor);
      setState(() => _notice = 'Borç malike devredildi: ${formatMinor(preview.totalMinor)}.${balances.isEmpty ? '' : ' $balances.'}');
    }
    // Onay açıkken önizleme eskimiş olabilir (409 LIABILITY_TRANSFER_CHANGED) ya da yazma yapıldı: her durumda yeniden okunur.
    unawaited(_load(keepNotice: done));
  }

  Future<void> _reverse(LiabilityTransfer transfer) async {
    if (_asking || !widget.scope.canWrite) return;
    setState(() => _asking = true);
    final message =
        '${widget.apartmentLabel}\n'
        'Geri alınacak devir: ${formatCrmDate(transfer.createdAt)} • ${formatMinor(transfer.totalMinor)} • ${transfer.itemCount} kalem.\n\n'
        'Kayıt silinmez: ters kayıtlar eklenir ve kiracı ile ev sahibi bakiyeleri devirden önceki değerlere döner. '
        'Devirden sonra ev sahibi hesabına ödeme girildiyse geri alınamaz.';
    LiabilityTransferResult? result;
    final bool done;
    try {
      done = await FinanceReasonDialog.show(
        context,
        title: 'Devri Geri Al',
        subtitle: widget.apartmentLabel,
        message: message,
        semanticMessage: spokenMoneyText(message),
        confirmLabel: 'Devri Geri Al',
        signatureBase: 'liabrev|${widget.scope.siteCode}|${transfer.id}',
        reasonLabel: 'Geri alma nedeni',
        icon: Icons.undo_rounded,
        tone: AppTone.danger,
        keyPrefix: 'liabrev',
        keyOwner: widget.scope.authService,
        failure: 'Devir geri alınamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.',
        onUncertain: _afterWrite,
        action: (reason, key) async {
          result = await widget.scope.f4Call(
            (api, t, s) => api.reverseLiabilityTransfer(token: t, siteCode: s, transferId: transfer.id, reason: reason, idempotencyKey: key),
          );
        },
      );
    } finally {
      if (mounted) setState(() => _asking = false);
    }
    if (!mounted) return;
    if (done) {
      _afterWrite();
      final balances = _balancesText(result?.tenantBalanceMinor, result?.ownerBalanceMinor);
      setState(() => _notice = 'Devir geri alındı.${balances.isEmpty ? '' : ' $balances.'}');
    }
    unawaited(_load(keepNotice: done));
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final preview = _preview;
    final canWrite = widget.scope.canWrite;
    final Widget body;
    if (_loading) {
      body = const ListSkeleton(rows: 2);
    } else if (_loadError != null) {
      body = InlineNotice(
        key: const ValueKey<String>('finance_liability_load_error'),
        message: _loadError!,
        onRetry: _load,
      );
    } else if (preview == null) {
      body = const SizedBox.shrink();
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_notice != null) ...[
            InlineNotice(key: const ValueKey<String>('finance_liability_notice'), tone: AppTone.success, message: _notice!, semanticsLabel: spokenMoneyText(_notice!)),
            const SizedBox(height: AppSpace.md),
          ],
          Text(
            'Kiracı borcunu ödemezse borç mutlaka tahsil edilir: kiracı vermezse ev sahibi öder. Devir kendiliğinden olmaz; kalemleri inceleyip '
            'nedenini yazarak onaylarsınız. İşlem kayıtlıdır ve geri alınabilir.',
            style: th.bodySmall?.copyWith(color: p.textSecondary),
          ),
          const SizedBox(height: AppSpace.md),
          _buildPreview(context, preview, canWrite: canWrite),
          const SizedBox(height: AppSpace.lg),
          _buildHistory(context, canWrite: canWrite),
        ],
      );
    }
    return PopScope(
      canPop: !_asking,
      child: AppDialog(
        title: 'Kiracı Borcunu Malike Devret',
        subtitle: widget.apartmentLabel,
        icon: Icons.swap_horiz_rounded,
        tone: AppTone.warning,
        actions: [
          TextButton(
            key: const ValueKey<String>('finance_liability_close'),
            onPressed: _asking ? null : () => popIfCurrent(context),
            child: const Text('Kapat'),
          ),
        ],
        child: body,
      ),
    );
  }

  Widget _buildPreview(BuildContext context, LiabilityPreview preview, {required bool canWrite}) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final shown = preview.items.take(FinanceLiabilityTransferDialog.maxShownItems).toList(growable: false);
    final hidden = preview.itemCount - shown.length;
    final balances = _balancesText(preview.tenantBalanceMinor, preview.ownerBalanceMinor);
    final excluded = preview.excludedLateFee;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!preview.hasOwner) ...[
          const InlineNotice(
            key: ValueKey<String>('finance_liability_no_owner'),
            tone: AppTone.warning,
            message: 'Bu dairede kayıtlı bir malik yok; borç devredilemez. Önce Kişiler bölümünden malik kaydını ekleyin.',
          ),
          const SizedBox(height: AppSpace.md),
        ],
        if (preview.isEmpty)
          const InlineNotice(
            key: ValueKey<String>('finance_liability_empty'),
            tone: AppTone.info,
            message: 'Devredilecek, vadesi geçmiş ve ödenmemiş kiracı borcu yok.',
          )
        else
          DialogPanel(
            key: const ValueKey<String>('finance_liability_preview'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DialogSectionTitle(
                  icon: Icons.receipt_long_rounded,
                  title: '${preview.itemCount} borç kalemi',
                  subtitle: 'Devredilecek toplam: ${formatMinor(preview.totalMinor)}',
                ),
                const SizedBox(height: AppSpace.sm),
                for (final item in shown) _LiabilityItemRow(item: item),
                if (hidden > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpace.xs),
                    child: Text('… ve $hidden kalem daha', style: th.bodySmall?.copyWith(color: p.textSecondary)),
                  ),
                if (balances.isNotEmpty) ...[
                  const SizedBox(height: AppSpace.sm),
                  Text(balances, semanticsLabel: spokenMoneyText(balances), style: th.bodySmall?.copyWith(color: p.textSecondary)),
                ],
              ],
            ),
          ),
        if (excluded.isNotEmpty) ...[
          const SizedBox(height: AppSpace.sm),
          Text(
            'Gecikme tazminatı devredilmez, kiracıda kalır: ${excluded.length} kalem, ${formatMinor(preview.excludedLateFeeMinor)}.',
            key: const ValueKey<String>('finance_liability_excluded'),
            semanticsLabel: spokenMoneyText('Gecikme tazminatı devredilmez, kiracıda kalır: ${excluded.length} kalem, ${formatMinor(preview.excludedLateFeeMinor)}.'),
            style: th.bodySmall?.copyWith(color: p.textSecondary),
          ),
        ],
        if (canWrite && !preview.isEmpty) ...[
          const SizedBox(height: AppSpace.md),
          PrimaryActionButton(
            key: const ValueKey<String>('finance_liability_transfer_button'),
            label: 'Malike Devret',
            icon: Icons.swap_horiz_rounded,
            tone: AppTone.warning,
            onPressed: preview.canTransfer && !_asking && !_loading ? _transfer : null,
          ),
        ],
      ],
    );
  }

  Widget _buildHistory(BuildContext context, {required bool canWrite}) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    return Column(
      key: const ValueKey<String>('finance_liability_history'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(header: true, container: true, child: Text('Devir geçmişi', style: th.titleMedium)),
        const SizedBox(height: AppSpace.sm),
        if (_history.isEmpty)
          Text('Bu daire için devir kaydı yok.', style: th.bodyMedium?.copyWith(color: p.textSecondary))
        else
          for (final transfer in _history)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.sm),
              child: _LiabilityHistoryTile(
                transfer: transfer,
                canWrite: canWrite,
                busy: _asking || _loading,
                onReverse: () => _reverse(transfer),
              ),
            ),
      ],
    );
  }
}

/// Önizlemedeki borç kalemi: ad, vade, devredilecek kalan tutar (+ kısmen ödenmişse kiracıda kalan ödenmiş kısım).
class _LiabilityItemRow extends StatelessWidget {
  const _LiabilityItemRow({required this.item});

  final LiabilityItem item;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final due = item.dueDate == null ? '' : ' • Vade ${formatCrmDate(item.dueDate)}';
    final amount = formatMinor(item.remainingMinor);
    // Dar ekranda ve büyük yazıda tutar adın yanına SIĞMAZ (Row taşardı): ad, altında tutar, altında ödenmiş kısım notu (hepsi sarar).
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${item.name ?? 'Borç'}$due', style: th.bodyMedium),
          Text(amount, semanticsLabel: spokenMoneyText(amount), style: th.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
          if (item.paidMinor > 0)
            Text(
              'Ödenen ${formatMinor(item.paidMinor)} kiracıda kalır',
              semanticsLabel: spokenMoneyText('Ödenen ${formatMinor(item.paidMinor)} kiracıda kalır'),
              style: th.bodySmall?.copyWith(color: p.textSecondary),
            ),
        ],
      ),
    );
  }
}

/// Geçmiş satırı: devir ya da geri alma; kim / ne zaman / ne kadar / neden. Etkin ve geri alınabilir devirde "Geri Al".
class _LiabilityHistoryTile extends StatelessWidget {
  const _LiabilityHistoryTile({required this.transfer, required this.canWrite, required this.busy, required this.onReverse});

  final LiabilityTransfer transfer;
  final bool canWrite;
  final bool busy;
  final VoidCallback onReverse;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final head = '${transfer.isReversal ? 'Geri alma' : 'Devir'} • ${formatCrmDate(transfer.createdAt)} • ${formatMinor(transfer.totalMinor)} • ${transfer.itemCount} kalem';
    final who = transfer.createdByName == null ? '' : ' • ${transfer.createdByName}';
    final canReverse = canWrite && !transfer.isReversal && !transfer.isReversed && transfer.reversible;
    final stuck = !transfer.isReversal && !transfer.isReversed && !transfer.reversible;
    return AppCard(
      key: ValueKey<String>('finance_liability_history_${transfer.id}'),
      padding: listCardPadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(head, semanticsLabel: spokenMoneyText(head), style: th.titleSmall),
          if (transfer.reason.isNotEmpty || who.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.xs),
              child: Text('Neden: ${transfer.reason}$who', style: th.bodySmall?.copyWith(color: p.textSecondary)),
            ),
          if (transfer.isReversed)
            const Padding(
              padding: EdgeInsets.only(top: AppSpace.sm),
              child: Align(alignment: AlignmentDirectional.centerStart, child: DialogMetaPill('Geri alındı', tone: AppTone.info, icon: Icons.undo_rounded)),
            ),
          if (stuck)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.sm),
              child: Text(
                'Bu devir artık geri alınamaz: devirden sonra ev sahibi hesabına ödeme girilmiş ya da kalemleri sonradan başka bir devirle taşınmış olabilir.',
                key: ValueKey<String>('finance_liability_stuck_${transfer.id}'),
                style: th.bodySmall?.copyWith(color: p.textSecondary),
              ),
            ),
          if (canReverse)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.sm),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: OutlinedButton.icon(
                  key: ValueKey<String>('finance_liability_reverse_${transfer.id}'),
                  onPressed: busy ? null : onReverse,
                  icon: const Icon(Icons.undo_rounded),
                  label: const Text('Geri Al'),
                ),
              ),
            ),
        ],
      ),
    );
  }

}
