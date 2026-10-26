import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/finance_funds.dart';
import 'package:site_kapi_kontrol/models/fund_models.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/finance_fund_transfer_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/large_dialog_parts.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_4b_access.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_errors.dart';
import 'package:site_kapi_kontrol/ui/helpers/fund_text.dart';
import 'package:site_kapi_kontrol/ui/helpers/istanbul_time.dart';
import 'package:site_kapi_kontrol/ui/helpers/money.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/widgets/crm_parts.dart' show CrmListBody;
import 'package:site_kapi_kontrol/ui/widgets/finance_4b_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_fund_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

/// Görüntülenen dönem (kasa özeti ve dökümü aynı aralıkla okunur).
enum FundPeriodChoice {
  thisMonth('Bu ay'),
  lastMonth('Geçen ay'),
  all('Tüm zamanlar');

  const FundPeriodChoice(this.label);

  final String label;

  /// `(from, to)`; [all] için ikisi de null (sunucu `to`yu bugün sayar ve `from` uygulamaz).
  (DateTime?, DateTime?) range(DateTime today) => switch (this) {
    FundPeriodChoice.thisMonth => (DateTime(today.year, today.month, 1), today),
    FundPeriodChoice.lastMonth => (DateTime(today.year, today.month - 1, 1), DateTime(today.year, today.month, 0)),
    FundPeriodChoice.all => (null, null),
  };
}

/// Finans > Kasa sekmesinin üst bölümü: İşletme Projesi (Aidat) Hesabı ve Yatırım ve Demirbaş (Fon) Hesabı kartları, avans
/// satırı ve "Kasalar arası aktarım" (docs/PLATFORM_FINANS_KASALAR.md §6).
///
/// - Rakamlar YALNIZ sunucunun kasa özetidir; istemci bakiye hesaplamaz. Hata / yükleme durumunda eski tutar gösterilmez
///   ve ASLA "0" yazılmaz ("Tekrar Dene"; 503 `REPORT_BUSY` ise kullanıcı beklemeye yönlendirilir).
/// - Dönem seçimi (Bu ay / Geçen ay / Tüm zamanlar) özeti ve kart içindeki dökümü aynı aralıkla okur.
/// - Kartın "Hareketler" düğmesi o kasanın sayfalı dökümünü açar (yeni -> eski, "Daha fazla yükle").
/// - `negative_balance` uyarı taşır (engellenmez); `unassigned_payments` > 0 ise bilgi notu, `balanced == false` ise fark
///   notu gösterilir. Kurul salt okur: aktarım düğmesi çizilmez, aktarım listesini görür.
/// - Yazma sonrası özet ve döküm kendiliğinden yenilenir; üst ekrana [onDataChanged] ile haber verilir.
class FinanceFundsSection extends StatefulWidget {
  const FinanceFundsSection({super.key, required this.scope, required this.onDataChanged, this.now});

  final PeopleScope scope;

  /// Bir yazma yapılınca çağrılır (üst ekran öteki sekmeleri bayatlatır, özeti tazeler).
  final VoidCallback onDataChanged;
  final DateTime Function()? now;

  @override
  State<FinanceFundsSection> createState() => FinanceFundsSectionState();
}

class FinanceFundsSectionState extends State<FinanceFundsSection> {
  FundSummary? _data;
  bool _loading = false;
  String? _error;
  int _token = 0;

  // Döküm panelleri her başarılı özet yüklemesinde yeniden kurulur (anahtar nesli): yazma sonrası döküm de tazelenir.
  int _generation = 0;
  bool _opening = false;
  FundPeriodChoice _period = FundPeriodChoice.thisMonth;
  final Set<FinanceFund> _expanded = <FinanceFund>{};

  bool get _canWrite => widget.scope.canWrite;

  DateTime get _today {
    final wall = istanbulNow(widget.now?.call());
    return DateTime(wall.year, wall.month, wall.day);
  }

  (DateTime?, DateTime?) get _range => _period.range(_today);

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

  /// Kasa özetini yeniden çeker (sekme yenileme / yazma sonrası).
  Future<void> reload() async {
    if (!mounted) return;
    final token = ++_token;
    final (from, to) = _range;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.scope.f4Call(
        (api, t, s) => api.getFundSummary(token: t, siteCode: s, from: from, to: to),
      );
      if (!mounted || token != _token) return;
      setState(() {
        _data = data;
        _loading = false;
        _generation++;
      });
    } catch (e) {
      if (!mounted || token != _token) return;
      setState(() {
        _loading = false;
        // Eski tutarlar hata uyarısının altında güncelmiş gibi durmasın.
        _data = null;
        _error = financeMessageOf(
          e,
          'Aidat Hesabı ve Fon Hesabı yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
        );
      });
    }
  }

  void _selectPeriod(FundPeriodChoice period) {
    if (period == _period) return;
    setState(() => _period = period);
    unawaited(reload());
  }

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

  Future<void> _transfer() async {
    if (_opening) return;
    final outcome = await _guarded(
      () => FinanceFundTransferDialog.show(
        context,
        scope: widget.scope,
        summary: _data,
        now: widget.now,
        onRefreshNeeded: _refreshOnly,
      ),
    );
    if (outcome == null || !mounted) return;
    showFinanceSnack(context, outcome.message);
    _refreshOnly();
  }

  Future<void> _transfers() async {
    if (_opening) return;
    await _guarded(() => FinanceFundTransfersDialog.show(context, scope: widget.scope, onChanged: _refreshOnly));
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final data = _data;
    final Widget body;
    if (data == null) {
      body = _loading || _error == null
          ? const ListSkeleton(rows: 2)
          : InlineNotice(key: const ValueKey<String>('finance_funds_error'), message: _error!, onRetry: reload);
    } else {
      body = _buildLoaded(context, data);
    }
    return Column(
      key: const ValueKey<String>('finance_funds_section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(header: true, container: true, child: Text('Aidat Hesabı ve Fon Hesabı', style: th.titleMedium)),
        const SizedBox(height: AppSpace.xs),
        Text(
          'Site bakiyesi iki hesapta izlenir. Nakit ve banka hesapları iki hesapta ortaktır ve aşağıda listelenir.',
          style: th.bodySmall?.copyWith(color: p.textSecondary),
        ),
        const SizedBox(height: AppSpace.sm),
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          children: [
            for (final choice in FundPeriodChoice.values)
              ChoiceChip(
                key: ValueKey<String>('finance_funds_period_${choice.name}'),
                label: Text(choice.label),
                selected: _period == choice,
                onSelected: _loading ? null : (_) => _selectPeriod(choice),
              ),
          ],
        ),
        const SizedBox(height: AppSpace.md),
        body,
      ],
    );
  }

  Widget _buildLoaded(BuildContext context, FundSummary data) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final (from, to) = _range;
    final differenceMessage =
        'Aidat Hesabı, Fon Hesabı ve avans toplamı, kasa ve banka hesaplarının toplamından ${formatMinor(data.differenceMinor.abs())} '
        '${data.differenceMinor > 0 ? 'eksik' : 'fazla'}. Kayıtları kontrol edin; geçmiş bir dönem seçtiyseniz sonradan iptal '
        'edilen kayıtlar farka yol açabilir.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final fund in FinanceFund.values) ...[
          _FundCard(
            key: ValueKey<String>('finance_fund_card_${fund.apiValue}'),
            scope: widget.scope,
            balance: data.of(fund),
            allTime: _period == FundPeriodChoice.all,
            from: from,
            to: to,
            generation: _generation,
            expanded: _expanded.contains(fund),
            onToggle: () => setState(() {
              if (!_expanded.add(fund)) _expanded.remove(fund);
            }),
          ),
          const SizedBox(height: AppSpace.md),
        ],
        AppCard(
          key: const ValueKey<String>('finance_funds_advance'),
          padding: listCardPadding(context),
          child: Semantics(
            container: true,
            label:
                'Avans: ${moneySemanticLabel(data.advanceMinor)}. Henüz hiçbir borca dağıtılmamış ödemeler; '
                '${FinanceFund.operating.label} ve ${FinanceFund.capital.label} bakiyesine yazılmaz.',
            child: ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Avans', style: th.titleMedium),
                  Text(
                    formatMinor(data.advanceMinor),
                    key: const ValueKey<String>('finance_funds_advance_amount'),
                    style: th.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  Text(
                    'Henüz hiçbir borca dağıtılmamış ödemeler. İki hesabın bakiyesine yazılmaz; yeni borç çıkınca o borca uygulanır.',
                    style: th.bodySmall?.copyWith(color: p.textSecondary),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (data.unassigned.any) ...[
          const SizedBox(height: AppSpace.md),
          InlineNotice(
            key: const ValueKey<String>('finance_funds_unassigned'),
            tone: AppTone.info,
            message:
                'Bir kasa ya da banka hesabına eşlenmemiş ${data.unassigned.count} tahsilat var '
                '(${formatMinor(data.unassigned.totalMinor)}). Bu tahsilatlar Aidat Hesabı ve Fon Hesabı bakiyelerine dahil değildir; '
                'hesaba eşlenince görünür.',
            semanticsLabel: spokenMoneyText(
              'Bir kasa ya da banka hesabına eşlenmemiş ${data.unassigned.count} tahsilat var '
              '(${formatMinor(data.unassigned.totalMinor)}). Bu tahsilatlar Aidat Hesabı ve Fon Hesabı bakiyelerine dahil değildir; '
              'hesaba eşlenince görünür.',
            ),
          ),
        ],
        if (!data.balanced) ...[
          const SizedBox(height: AppSpace.md),
          InlineNotice(
            key: const ValueKey<String>('finance_funds_unbalanced'),
            tone: AppTone.warning,
            message: differenceMessage,
            semanticsLabel: spokenMoneyText(differenceMessage),
          ),
        ],
        if (!data.hasAccounts) ...[
          const SizedBox(height: AppSpace.md),
          const InlineNotice(
            key: ValueKey<String>('finance_funds_no_accounts'),
            tone: AppTone.info,
            message: 'Henüz kasa ya da banka hesabı yok. Tahsilat ve giderler bir hesaba işlenince iki hesabın bakiyesi oluşur.',
          ),
        ],
        const SizedBox(height: AppSpace.md),
        if (_canWrite) ...[
          PrimaryActionButton(
            key: const ValueKey<String>('finance_funds_transfer'),
            label: 'Kasalar Arası Aktarım',
            icon: Icons.swap_vert_rounded,
            onPressed: _opening ? null : _transfer,
          ),
          const SizedBox(height: AppSpace.sm),
        ],
        PrimaryActionButton(
          key: const ValueKey<String>('finance_funds_transfers'),
          label: 'Kasalar Arası Aktarım Listesi',
          icon: Icons.history_rounded,
          variant: AppButtonVariant.tonal,
          onPressed: _opening ? null : _transfers,
        ),
      ],
    );
  }
}

/// Bir kasanın kartı: tam ad, bakiye, dönem rakamları ve (açılınca) sayfalı döküm.
class _FundCard extends StatelessWidget {
  const _FundCard({
    super.key,
    required this.scope,
    required this.balance,
    required this.allTime,
    required this.from,
    required this.to,
    required this.generation,
    required this.expanded,
    required this.onToggle,
  });

  final PeopleScope scope;
  final FundBalance balance;
  final bool allTime;
  final DateTime? from;
  final DateTime? to;
  final int generation;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final fund = balance.fund;
    final negative = balance.isNegative;
    final semantic = StringBuffer('${fund.label}. Bakiye: ${moneySemanticLabel(balance.balanceMinor)}.');
    if (negative) semantic.write(' Uyarı: bakiye eksiye düşmüş.');
    return AppCard(
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
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Icon(fundIcon(fund), size: 22, color: p.textSecondary),
                      ),
                      const SizedBox(width: AppSpace.sm),
                      Expanded(child: Text(fund.label, key: ValueKey<String>('fund_title_${fund.apiValue}'), style: th.titleMedium)),
                    ],
                  ),
                  Text('Borcu ${fund.payerNote}', style: th.bodySmall?.copyWith(color: p.textSecondary)),
                  const SizedBox(height: AppSpace.sm),
                  if (negative)
                    const Padding(
                      padding: EdgeInsets.only(bottom: AppSpace.xs),
                      child: DialogMetaPill('Bakiye eksi', tone: AppTone.danger, icon: Icons.warning_amber_rounded),
                    ),
                  Text(
                    formatMinor(balance.balanceMinor),
                    key: ValueKey<String>('fund_balance_${fund.apiValue}'),
                    style: th.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: negative ? AppTone.danger.ink(p) : null,
                    ),
                  ),
                  if (negative)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpace.xs),
                      child: Text(
                        'Bakiye eksiye düşmüş. Kayıtlar eksik olabilir; hareketleri ve açılış bakiyesini kontrol edin.',
                        key: ValueKey<String>('fund_negative_${fund.apiValue}'),
                        style: th.bodySmall?.copyWith(color: AppTone.danger.ink(p), fontWeight: FontWeight.w700),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpace.sm),
          FinanceInfoRow(label: allTime ? 'Açılış' : 'Dönem başı', money: balance.openingMinor),
          FinanceInfoRow(label: 'Tahsilat', money: balance.collectionsMinor),
          FinanceInfoRow(label: 'Gider', money: balance.expensesMinor),
          FinanceInfoRow(label: 'Aktarım (giren)', money: balance.transfersInMinor),
          FinanceInfoRow(label: 'Aktarım (çıkan)', money: balance.transfersOutMinor),
          FinanceInfoRow(label: 'Düzeltme', money: balance.adjustmentsMinor),
          const SizedBox(height: AppSpace.sm),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              key: ValueKey<String>('fund_movements_toggle_${fund.apiValue}'),
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: onToggle,
              icon: Icon(expanded ? Icons.expand_less_rounded : Icons.list_alt_rounded, size: 18),
              label: Text(expanded ? 'Hareketleri gizle' : 'Hareketler'),
            ),
          ),
          if (expanded)
            _FundMovementsPanel(
              key: ValueKey<String>('fund_movements_${fund.apiValue}_$generation'),
              scope: scope,
              fund: fund,
              from: from,
              to: to,
            ),
        ],
      ),
    );
  }
}

/// Bir kasanın sayfalı hareket dökümü (yeni -> eski; 25'erli, "Daha fazla yükle"). Hata asla "hareket yok" demez.
class _FundMovementsPanel extends StatefulWidget {
  const _FundMovementsPanel({super.key, required this.scope, required this.fund, this.from, this.to});

  final PeopleScope scope;
  final FinanceFund fund;
  final DateTime? from;
  final DateTime? to;

  @override
  State<_FundMovementsPanel> createState() => _FundMovementsPanelState();
}

class _FundMovementsPanelState extends State<_FundMovementsPanel> {
  late final PagedLoader<FundMovement> _loader = PagedLoader<FundMovement>(
    pageSize: 25,
    fetch: (offset, limit) async {
      final page = await widget.scope.f4Call(
        (api, t, s) => api.listFundMovements(
          token: t,
          siteCode: s,
          fund: widget.fund,
          from: widget.from,
          to: widget.to,
          limit: limit,
          offset: offset,
        ),
      );
      return (items: page.items, total: page.total);
    },
    keyOf: (m) => m.key,
    notify: () {
      if (mounted) setState(() {});
    },
    isAlive: () => mounted,
    errorFallback: 'Hareketler yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
    moreErrorFallback: 'Daha fazla hareket yüklenemedi. Tekrar deneyin.',
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

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CrmListBody<FundMovement>(
          loader: _loader,
          emptyIcon: Icons.list_alt_rounded,
          emptyTitle: 'Bu dönemde ${widget.fund.shortLabel} için hareket yok.',
          skeletonRows: 2,
          hideItemsOnError: true,
          itemBuilder: (context, movement) => FundMovementTile(movement: movement),
        ),
      ],
    );
  }
}
