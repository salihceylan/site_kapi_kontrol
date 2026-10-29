import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/finance.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/finance_account_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/finance_opening_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_errors.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/widgets/crm_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_liability_banner.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_refunds_entry.dart';

/// "Daireler" sekmesi (Platform Faz 4a): arama (daire etiketi, sakin adı) + durum süzgeci (Hepsi / Borçlu /
/// Alacaklı), sayfalı bakiye listesi; daireye dokununca ekstre açılır.
///
/// Yarışlar: art arda arama / süzgeç değişiminde eski yanıt yenisini ezmez ([PagedLoader] jetonu); dispose
/// sonrası yanıt yok sayılır; hata asla "daire yok / borç yok" demez ("Tekrar Dene" gösterilir).
class FinanceBalancesTab extends StatefulWidget {
  const FinanceBalancesTab({
    super.key,
    required this.scope,
    required this.onDataChanged,
    this.now,
  });

  final PeopleScope scope;

  /// Ekstrede bir yazma yapılınca çağrılır (üst ekran özeti ve öteki sekmeleri tazeler).
  final VoidCallback onDataChanged;
  final DateTime Function()? now;

  @override
  State<FinanceBalancesTab> createState() => FinanceBalancesTabState();
}

class FinanceBalancesTabState extends State<FinanceBalancesTab> {
  static const List<(String, String)> _filters = <(String, String)>[
    ('all', 'Hepsi'),
    ('debtor', 'Borçlu'),
    ('credit', 'Alacaklı'),
  ];

  final TextEditingController _search = TextEditingController();
  Timer? _timer;
  String _query = '';
  String _status = 'all';
  String _lastSignature = '|all';
  bool _opening = false;

  /// Devir öneri şeridini ([FinanceLiabilityBanner]) yeniden kurar (liste tazelenince şerit de tazelenir).
  int _liabilityTick = 0;

  late final PagedLoader<BalanceRow> _loader = PagedLoader<BalanceRow>(
    fetch: (offset, limit) async {
      final page = await widget.scope.authService.listFinanceBalances(
        widget.scope.siteCode,
        status: _status,
        query: _query,
        limit: limit,
        offset: offset,
      );
      return (items: page.items, total: page.total);
    },
    keyOf: (r) => r.apartmentId,
    notify: () {
      if (mounted) setState(() {});
    },
    isAlive: () => mounted,
    errorFallback: 'Bakiyeler yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
    messageOf: financeMessageOf,
  );

  @override
  void initState() {
    super.initState();
    unawaited(_loader.reload());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _loader.dispose();
    _search.dispose();
    super.dispose();
  }

  /// Listeyi yeniden çeker (sayfa kabuğunun çekip yenilemesi ve yenile düğmesi); devir öneri şeridi de tazelenir.
  Future<void> reload() {
    if (mounted) setState(() => _liabilityTick++);
    return _loader.reload();
  }

  void _applyFilters() {
    _timer?.cancel();
    final next = _search.text.trim();
    final signature = '$next|$_status';
    if (signature == _lastSignature &&
        (_loader.loading || (_loader.loadedOnce && _loader.error == null))) {
      return;
    }
    _lastSignature = signature;
    _query = next;
    _loader.reset();
    unawaited(_loader.reload());
  }

  void _onSearchChanged(String _) {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 350), _applyFilters);
    setState(() {});
  }

  void _selectStatus(String status) {
    if (status == _status) return;
    _status = status;
    _applyFilters();
    setState(() {});
  }

  void _afterChange() {
    widget.onDataChanged();
    if (mounted) unawaited(reload());
  }

  Future<void> _open(BalanceRow row) async {
    if (_opening) return;
    _opening = true;
    try {
      await FinanceAccountDialog.show(
        context,
        scope: widget.scope,
        apartmentId: row.apartmentId,
        initialLabel: financeApartmentTitle(row.blockName, row.label),
        onChanged: _afterChange,
        now: widget.now,
      );
    } finally {
      _opening = false;
    }
  }

  bool get _filtered => _query.isNotEmpty || _status != 'all';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const ValueKey<String>('finance_balances_search'),
                controller: _search,
                textInputAction: TextInputAction.search,
                onChanged: _onSearchChanged,
                onSubmitted: (_) => _applyFilters(),
                decoration: InputDecoration(
                  labelText: 'Daire ara',
                  hintText: 'Daire no, blok veya kişi adı',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Aramayı temizle',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            _search.clear();
                            _applyFilters();
                            setState(() {});
                          },
                        ),
                ),
              ),
              const SizedBox(height: AppSpace.md),
              const FinanceGroupTitle('Durum'),
              const SizedBox(height: AppSpace.sm),
              Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.sm,
                children: [
                  for (final (value, label) in _filters)
                    ChoiceChip(
                      key: ValueKey<String>('finance_balance_filter_$value'),
                      label: Text(label),
                      selected: _status == value,
                      onSelected: (_) => _selectStatus(value),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.md),
        if (widget.scope.canWrite) FinanceLiabilityBanner(key: ValueKey<int>(_liabilityTick), scope: widget.scope, onChanged: _afterChange),
        // İade talepleri (K4): onay bekleyen varsa kart, her durumda "İade talepleri" düğmesi (kurul da listeyi okur); yanında "Devir bakiyesi" (yalnız yazma yetkisi).
        FinanceRefundsEntry(
          key: ValueKey<String>('finance_refunds_entry_$_liabilityTick'),
          scope: widget.scope,
          onChanged: _afterChange,
          extraAction: widget.scope.canWrite
              ? OutlinedButton.icon(
                  key: const ValueKey<String>('finance_opening_button'),
                  onPressed: () => unawaited(FinanceOpeningDialog.show(context, scope: widget.scope, onChanged: _afterChange)),
                  icon: const Icon(Icons.account_balance_wallet_outlined),
                  label: const Text('Devir bakiyesi'),
                )
              : null,
        ),
        const SizedBox(height: AppSpace.md),
        SectionHeader(
          title: 'Daireler',
          count: _loader.loadedOnce ? _loader.total : null,
          trailing: IconButton(
            onPressed: _loader.loading ? null : reload,
            tooltip: 'Yenile',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        CrmListBody<BalanceRow>(
          loader: _loader,
          emptyIcon: Icons.apartment_rounded,
          emptyTitle: 'Bu sitede daire bulunamadı.',
          filteredTitle: 'Bu arama ve süzgeç için daire bulunamadı.',
          filtered: _filtered,
          // Yenileme başarısızsa eski tutarlar hata kutusunun altında güncelmiş gibi durmasın: gizlenir.
          hideItemsOnError: true,
          itemBuilder: (context, row) => BalanceRowCard(row: row, onTap: () => _open(row)),
        ),
      ],
    );
  }
}
