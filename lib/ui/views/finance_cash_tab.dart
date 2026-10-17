import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/cash_models.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/finance_adjust_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/finance_assign_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/finance_cash_account_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/finance_movements_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/finance_reconcile_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/finance_transfer_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/large_dialog_parts.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_4b_access.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_errors.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_write_mixin.dart';
import 'package:site_kapi_kontrol/ui/helpers/money.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_4b_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

/// "Kasa" sekmesi (Platform Faz 4b, Ö4): kasa / banka hesapları, toplam bakiye, hesaba eşlenmemiş tahsilat uyarısı ve
/// hesap işlemleri (hareketler, düzeltme, mutabakat, aktarım, toplu eşleme).
///
/// - Hesap bakiyesi YALNIZ sunucunun hareket toplamıdır; istemci bakiye hesaplamaz.
/// - Hata / yükleme durumunda eski tutarlar gösterilmez ve ASLA "hesap yok / bakiye 0" yazılmaz ("Tekrar Dene").
/// - Kurul salt okur: hareketleri ve aktarım geçmişini görür, hiçbir yazma düğmesi çizilmez.
/// - Bakiyesi eksiye düşen hesap UYARI taşır (engellenmez); eşlenmemiş tahsilat varsa kasa rakamlarının eksik olabileceği
///   söylenir.
class FinanceCashTab extends StatefulWidget {
  const FinanceCashTab({super.key, required this.scope, required this.onDataChanged, this.now});

  final PeopleScope scope;

  /// Bir yazma yapılınca çağrılır (üst ekran öteki sekmeleri bayatlatır, özeti tazeler).
  final VoidCallback onDataChanged;
  final DateTime Function()? now;

  @override
  State<FinanceCashTab> createState() => FinanceCashTabState();
}

class FinanceCashTabState extends State<FinanceCashTab> {
  CashOverview? _data;
  bool _loading = false;
  String? _error;
  int _token = 0;
  bool _opening = false;

  bool get _canWrite => widget.scope.canWrite;

  @override
  void initState() {
    super.initState();
    unawaited(reload());
  }

  @override
  void dispose() {
    ++_token;
    super.dispose();
  }

  /// Hesapları yeniden çeker (sekme yenileme / sayfa kabuğu).
  Future<void> reload() async {
    if (!mounted) return;
    final token = ++_token;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.scope.f4Call((api, t, s) => api.listAccounts(token: t, siteCode: s));
      if (!mounted || token != _token) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || token != _token) return;
      setState(() {
        _loading = false;
        // Eski bakiyeler hata uyarısının altında güncelmiş gibi durmasın.
        _data = null;
        _error = financeMessageOf(e, 'Hesaplar yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.');
      });
    }
  }

  Future<void> _afterWrite(FinanceWriteOutcome? outcome) async {
    if (outcome == null || !mounted) return;
    showFinanceSnack(context, outcome.message);
    widget.onDataChanged();
    unawaited(reload());
  }

  /// Çift dokunuşta iki pencere açılmasın.
  Future<T> _guarded<T>(Future<T> Function() open) async {
    if (_opening) return Future<T>.value(null as T);
    _opening = true;
    try {
      return await open();
    } finally {
      _opening = false;
    }
  }

  void _refreshOnly() {
    if (!mounted) return;
    widget.onDataChanged();
    unawaited(reload());
  }

  Future<void> _addAccount() async {
    if (_opening) return;
    final outcome = await _guarded(
      () => FinanceCashAccountDialog.show(context, scope: widget.scope, now: widget.now, onRefreshNeeded: _refreshOnly),
    );
    await _afterWrite(outcome);
  }

  Future<void> _editAccount(CashAccount account) async {
    if (_opening) return;
    final outcome = await _guarded(
      () => FinanceCashAccountDialog.show(
        context,
        scope: widget.scope,
        account: account,
        now: widget.now,
        onRefreshNeeded: _refreshOnly,
      ),
    );
    await _afterWrite(outcome);
  }

  Future<void> _adjust(CashAccount account) async {
    if (_opening) return;
    final outcome = await _guarded(
      () => FinanceAdjustDialog.show(
        context,
        scope: widget.scope,
        account: account,
        now: widget.now,
        onRefreshNeeded: _refreshOnly,
      ),
    );
    await _afterWrite(outcome);
  }

  Future<void> _reconcile(CashAccount account) async {
    if (_opening) return;
    final outcome = await _guarded(
      () => FinanceReconcileDialog.show(
        context,
        scope: widget.scope,
        account: account,
        now: widget.now,
        onRefreshNeeded: _refreshOnly,
      ),
    );
    await _afterWrite(outcome);
  }

  Future<void> _transfer(List<CashAccount> active) async {
    if (_opening) return;
    final outcome = await _guarded(
      () => FinanceTransferDialog.show(
        context,
        scope: widget.scope,
        accounts: active,
        now: widget.now,
        onRefreshNeeded: _refreshOnly,
      ),
    );
    await _afterWrite(outcome);
  }

  Future<void> _assign(List<CashAccount> active) async {
    if (_opening) return;
    final outcome = await _guarded(
      () => FinanceAssignDialog.show(context, scope: widget.scope, accounts: active, onRefreshNeeded: _refreshOnly),
    );
    await _afterWrite(outcome);
  }

  Future<void> _movements(CashAccount account) async {
    if (_opening) return;
    await _guarded(() => FinanceMovementsDialog.show(context, scope: widget.scope, account: account));
  }

  Future<void> _transfers() async {
    if (_opening) return;
    await _guarded(() => FinanceTransfersDialog.show(context, scope: widget.scope, onChanged: _refreshOnly));
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final Widget body;
    if (data == null) {
      body = _loading || _error == null
          ? const ListSkeleton(rows: 2)
          : InlineNotice(message: _error!, onRetry: reload);
    } else {
      body = _buildLoaded(context, data);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: 'Kasa ve Banka',
          trailing: IconButton(
            onPressed: _loading ? null : reload,
            tooltip: 'Yenile',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        body,
      ],
    );
  }

  Widget _buildLoaded(BuildContext context, CashOverview data) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final active = data.activeAccounts;
    final inactive = data.items.where((a) => !a.isActive).toList();
    final negatives = data.items.where((a) => a.isNegative).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          key: const ValueKey<String>('finance_cash_total'),
          padding: listCardPadding(context),
          child: Semantics(
            container: true,
            label: 'Toplam bakiye: ${moneySemanticLabel(data.totalBalanceMinor)}. ${data.items.length} hesap.',
            child: ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Toplam bakiye', style: th.bodySmall?.copyWith(color: p.textSecondary)),
                  Text(
                    formatMinor(data.totalBalanceMinor),
                    key: const ValueKey<String>('finance_cash_total_amount'),
                    style: th.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  Text('${data.items.length} hesap', style: th.bodySmall?.copyWith(color: p.textSecondary)),
                ],
              ),
            ),
          ),
        ),
        if (data.unassigned.any) ...[
          const SizedBox(height: AppSpace.md),
          DialogPanel(
            key: const ValueKey<String>('finance_cash_unassigned'),
            tone: AppTone.warning,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  container: true,
                  label:
                      'Uyarı: hesaba eşlenmemiş ${data.unassigned.count} tahsilat var. Toplam ${moneySemanticLabel(data.unassigned.totalMinor)}.',
                  child: ExcludeSemantics(
                    child: DialogSectionTitle(
                      icon: Icons.warning_amber_rounded,
                      title: 'Hesaba eşlenmemiş ${data.unassigned.count} tahsilat',
                      subtitle:
                          'Toplam ${formatMinor(data.unassigned.totalMinor)}. Kasa rakamları eksik olabilir ve ilgili ay kapatılamaz.',
                      tone: AppTone.warning,
                    ),
                  ),
                ),
                if (_canWrite) ...[
                  const SizedBox(height: AppSpace.sm),
                  PrimaryActionButton(
                    key: const ValueKey<String>('finance_cash_assign'),
                    label: 'Toplu Eşle',
                    icon: Icons.account_tree_rounded,
                    variant: AppButtonVariant.tonal,
                    expand: false,
                    onPressed: active.isEmpty ? null : () => _assign(active),
                  ),
                ],
              ],
            ),
          ),
        ],
        if (negatives.isNotEmpty) ...[
          const SizedBox(height: AppSpace.md),
          InlineNotice(
            key: const ValueKey<String>('finance_cash_negative'),
            tone: AppTone.warning,
            message:
                '${negatives.map((a) => a.name).join(', ')} hesabının bakiyesi eksiye düşmüş. Kayıtlar eksik olabilir; '
                'hareketleri ve açılış bakiyesini kontrol edin.',
          ),
        ],
        const SizedBox(height: AppSpace.md),
        if (_canWrite) ...[
          PrimaryActionButton(
            key: const ValueKey<String>('finance_cash_add'),
            label: 'Hesap Ekle',
            icon: Icons.add_card_rounded,
            onPressed: _addAccount,
          ),
          const SizedBox(height: AppSpace.sm),
          PrimaryActionButton(
            key: const ValueKey<String>('finance_cash_transfer'),
            label: 'Aktarım Yap',
            icon: Icons.swap_horiz_rounded,
            variant: AppButtonVariant.tonal,
            onPressed: active.length < 2 ? null : () => _transfer(active),
          ),
          if (active.length < 2 && data.items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.xs),
              child: Text(
                'Aktarım için en az iki aktif hesap gerekir.',
                key: const ValueKey<String>('finance_cash_transfer_hint'),
                style: th.bodySmall?.copyWith(color: p.textSecondary),
              ),
            ),
          const SizedBox(height: AppSpace.sm),
        ],
        PrimaryActionButton(
          key: const ValueKey<String>('finance_cash_transfers'),
          label: 'Aktarım Geçmişi',
          icon: Icons.history_rounded,
          variant: AppButtonVariant.tonal,
          onPressed: _transfers,
        ),
        const SizedBox(height: AppSpace.lg),
        if (data.items.isEmpty)
          EmptyCard(
            key: const ValueKey<String>('finance_cash_empty'),
            icon: Icons.account_balance_rounded,
            title: 'Henüz kasa ya da banka hesabı yok.',
            message: _canWrite
                ? 'Tahsilat ve giderler bir hesaba işlenir. İlk hesabı "Hesap Ekle" ile oluşturun.'
                : 'Site yönetimi hesap eklediğinde burada görünür.',
          )
        else ...[
          for (final account in active)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.md),
              child: _card(account),
            ),
          if (inactive.isNotEmpty) ...[
            Semantics(header: true, container: true, child: Text('Pasif hesaplar', style: th.titleMedium)),
            const SizedBox(height: AppSpace.sm),
            for (final account in inactive)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.md),
                child: _card(account),
              ),
          ],
        ],
      ],
    );
  }

  Widget _card(CashAccount account) {
    return CashAccountCard(
      account: account,
      busy: _opening,
      onOpen: () => _movements(account),
      onAdjust: _canWrite ? () => _adjust(account) : null,
      onReconcile: _canWrite && account.isActive ? () => _reconcile(account) : null,
      onEdit: _canWrite ? () => _editAccount(account) : null,
    );
  }
}
