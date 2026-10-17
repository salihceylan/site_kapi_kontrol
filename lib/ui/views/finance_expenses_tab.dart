import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/cash_models.dart';
import 'package:site_kapi_kontrol/models/expense_models.dart';
import 'package:site_kapi_kontrol/models/vehicle_record.dart' show crmDateParam;
import 'package:site_kapi_kontrol/services/expense_attachments.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/finance_catalog_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/finance_expense_detail_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/finance_expense_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/cursor_loader.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_4b_access.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_errors.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_export_sources.dart';
import 'package:site_kapi_kontrol/ui/helpers/istanbul_time.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/widgets/bulk_export_sheet.dart' show ExportSource;
import 'package:site_kapi_kontrol/ui/widgets/cursor_list_body.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_4b_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_parts.dart';

/// "Giderler" sekmesi (Platform Faz 4b, Ö3): gider listesi (dönem / durum / kategori / hesap süzgeci + arama),
/// süzgece uyan TOPLAMLAR, **Gider Ekle** ve **Kategori ve Tedarikçiler**; satıra dokununca ayrıntı (düzelt / iptal).
///
/// - Hata / yükleme durumunda "gider yok" ya da sıfır toplam YAZILMAZ; süzgeç ya da arama değişince eski yanıt yenisini
///   ezmez (jeton). Toplamlar yalnız sunucu `totals` alanından gelir (istemci toplamaz).
/// - Kurul salt okur (yazma düğmesi yok).
/// - [attachmentSource] verilmedikçe belge eki alanı gizlidir ("belge modülü / seçici yoksa gizli").
class FinanceExpensesTab extends StatefulWidget {
  const FinanceExpensesTab({
    super.key,
    required this.scope,
    required this.onDataChanged,
    this.attachmentSource,
    this.now,
    this.exportLauncher = defaultFinanceExportLauncher,
  });

  final PeopleScope scope;
  final VoidCallback onDataChanged;
  final ExpenseAttachmentSource? attachmentSource;
  final DateTime Function()? now;

  /// "Dışa Aktar" alt sayfasını açan işlev (yalnız yönetici; testler yakalamak için değiştirir).
  final FinanceExportLauncher exportLauncher;

  @override
  State<FinanceExpensesTab> createState() => FinanceExpensesTabState();
}

enum _Period { thisMonth, lastMonth, thisYear, all }

class FinanceExpensesTabState extends State<FinanceExpensesTab> {
  static const List<(String, String)> _statuses = <(String, String)>[
    ('active', 'Geçerli'),
    ('voided', 'İptal edilen'),
    ('all', 'Hepsi'),
  ];

  final TextEditingController _search = TextEditingController();
  Timer? _timer;
  _Period _period = _Period.thisMonth;
  String _status = 'active';
  String _query = '';
  int? _categoryId;
  int? _accountId;
  String _lastSignature = '';
  bool _opening = false;

  ExpenseTotals? _totals;
  List<ExpenseCategory>? _categories;
  List<CashAccount>? _accounts;
  String? _filterError;
  int _filterToken = 0;

  late final CursorLoader<Expense> _loader = CursorLoader<Expense>(
    fetch: (before) async {
      final range = _range();
      final page = await widget.scope.f4Call(
        (api, t, s) => api.listExpenses(
          token: t,
          siteCode: s,
          from: range.$1,
          to: range.$2,
          categoryId: _categoryId,
          accountId: _accountId,
          status: _status,
          query: _query,
          beforeId: before,
        ),
      );
      if (before == null && mounted) _totals = page.totals;
      return (items: page.items, next: page.nextBeforeId);
    },
    keyOf: (e) => e.id,
    notify: () {
      if (mounted) setState(() {});
    },
    isAlive: () => mounted,
    errorFallback: 'Giderler yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
    moreErrorFallback: 'Daha fazla gider yüklenemedi. Tekrar deneyin.',
    messageOf: financeMessageOf,
  );

  bool get _canWrite => widget.scope.canWrite;

  DateTime _today() {
    final wall = istanbulNow(widget.now?.call());
    return DateTime(wall.year, wall.month, wall.day);
  }

  /// Seçili dönemin (başlangıç, bitiş) takvim günleri; tüm zamanlar için (null, null).
  (DateTime?, DateTime?) _range() {
    final today = _today();
    switch (_period) {
      case _Period.thisMonth:
        return (DateTime(today.year, today.month, 1), DateTime(today.year, today.month + 1, 0));
      case _Period.lastMonth:
        return (DateTime(today.year, today.month - 1, 1), DateTime(today.year, today.month, 0));
      case _Period.thisYear:
        return (DateTime(today.year, 1, 1), DateTime(today.year, 12, 31));
      case _Period.all:
        return (null, null);
    }
  }

  static String _periodLabel(_Period p) => switch (p) {
    _Period.thisMonth => 'Bu ay',
    _Period.lastMonth => 'Geçen ay',
    _Period.thisYear => 'Bu yıl',
    _Period.all => 'Tümü',
  };

  @override
  void initState() {
    super.initState();
    _lastSignature = _signature();
    unawaited(_loader.reload());
    unawaited(_loadFilters());
  }

  @override
  void dispose() {
    ++_filterToken;
    _timer?.cancel();
    _loader.dispose();
    _search.dispose();
    super.dispose();
  }

  String _signature() => '${_search.text.trim()}|$_period|$_status|$_categoryId|$_accountId';

  Future<void> reload() async {
    unawaited(_loadFilters());
    await _loader.reload();
  }

  Future<void> _loadFilters() async {
    final token = ++_filterToken;
    try {
      final categories = await widget.scope.f4Call((api, t, s) => api.listExpenseCategories(token: t, siteCode: s));
      final overview = await widget.scope.f4Call((api, t, s) => api.listAccounts(token: t, siteCode: s));
      if (!mounted || token != _filterToken) return;
      setState(() {
        _categories = categories;
        _accounts = overview.items;
        _filterError = null;
      });
    } catch (e) {
      if (!mounted || token != _filterToken) return;
      setState(() {
        _filterError = financeMessageOf(e, 'Süzgeç listeleri yüklenemedi. Kategori ve hesap süzgeçleri kullanılamıyor.');
      });
    }
  }

  void _apply() {
    _timer?.cancel();
    final signature = _signature();
    if (signature == _lastSignature && (_loader.loading || (_loader.loadedOnce && _loader.error == null))) return;
    _lastSignature = signature;
    _query = _search.text.trim();
    _totals = null;
    _loader.reset();
    unawaited(_loader.reload());
  }

  void _afterChange() {
    widget.onDataChanged();
    if (mounted) unawaited(_loader.reload());
  }

  Future<void> _add() async {
    if (_opening) return;
    _opening = true;
    try {
      final outcome = await FinanceExpenseDialog.show(
        context,
        scope: widget.scope,
        attachmentSource: widget.attachmentSource,
        now: widget.now,
        onRefreshNeeded: _afterChange,
      );
      if (outcome == null || !mounted) return;
      showFinanceSnack(context, outcome.message);
      _afterChange();
    } finally {
      _opening = false;
    }
  }

  Future<void> _open(Expense expense) async {
    if (_opening) return;
    _opening = true;
    try {
      await FinanceExpenseDetailDialog.show(
        context,
        scope: widget.scope,
        expenseId: expense.id,
        initialDescription: expense.description,
        attachmentSource: widget.attachmentSource,
        now: widget.now,
        onChanged: _afterChange,
      );
    } finally {
      _opening = false;
    }
  }

  Future<void> _catalog() async {
    if (_opening) return;
    _opening = true;
    try {
      await FinanceCatalogDialog.show(context, scope: widget.scope, onChanged: () => unawaited(_loadFilters()));
    } finally {
      _opening = false;
    }
  }

  /// Ekrandaki UYGULANMIŞ süzgeçlerle gider listesini dosyaya aktarır (yalnız yönetici; ekranla dosya arasında sapma olmasın).
  void _export() {
    if (_opening) return;
    final range = _range();
    final categoryName = _categoryId == null
        ? null
        : (_categories ?? const <ExpenseCategory>[]).where((c) => c.id == _categoryId).map((c) => c.name).firstOrNull;
    final accountName = _accountId == null
        ? null
        : (_accounts ?? const <CashAccount>[]).where((a) => a.id == _accountId).map((a) => a.name).firstOrNull;
    final statusLabel = _statuses.firstWhere((s) => s.$1 == _status, orElse: () => (_status, _status)).$2;
    final summary = <String>[
      _periodLabel(_period),
      statusLabel,
      ?categoryName,
      ?accountName,
      if (_query.isNotEmpty) 'Arama: $_query',
    ].join(' • ');
    final source = financeExportSource(
      scope: widget.scope,
      label: 'Giderler',
      kind: 'finance_expenses',
      icon: Icons.shopping_cart_checkout_rounded,
      filterSummary: summary,
      query: <String, String>{
        if (range.$1 != null) 'from': crmDateParam(range.$1!),
        if (range.$2 != null) 'to': crmDateParam(range.$2!),
        if (_categoryId != null) 'category_id': '$_categoryId',
        if (_accountId != null) 'account_id': '$_accountId',
        'status': _status,
        if (_query.isNotEmpty) 'q': _query,
      },
    );
    unawaited(widget.exportLauncher(context, <ExportSource>[source]));
  }

  bool get _filtered => _query.isNotEmpty || _period != _Period.thisMonth || _status != 'active' || _categoryId != null || _accountId != null;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final totals = _totals;
    final loadedOk = _loader.loadedOnce && _loader.error == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_canWrite) ...[
          PrimaryActionButton(
            key: const ValueKey<String>('finance_expense_add'),
            label: 'Gider Ekle',
            icon: Icons.add_shopping_cart_rounded,
            onPressed: _add,
          ),
          const SizedBox(height: AppSpace.sm),
        ],
        PrimaryActionButton(
          key: const ValueKey<String>('finance_expense_catalog'),
          label: 'Kategori ve Tedarikçiler',
          icon: Icons.category_rounded,
          variant: AppButtonVariant.tonal,
          onPressed: _catalog,
        ),
        // Dışa aktarma yalnız yönetici / süper kullanıcı içindir (kurul 403 alır).
        if (_canWrite) ...[
          const SizedBox(height: AppSpace.sm),
          PrimaryActionButton(
            key: const ValueKey<String>('finance_expense_export'),
            label: 'Dışa Aktar',
            icon: Icons.file_download_rounded,
            variant: AppButtonVariant.tonal,
            onPressed: _export,
          ),
        ],
        const SizedBox(height: AppSpace.md),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const ValueKey<String>('finance_expense_search'),
                controller: _search,
                textInputAction: TextInputAction.search,
                onChanged: (_) {
                  _timer?.cancel();
                  _timer = Timer(const Duration(milliseconds: 350), _apply);
                  setState(() {});
                },
                onSubmitted: (_) => _apply(),
                decoration: InputDecoration(
                  labelText: 'Gider ara',
                  hintText: 'Açıklama, tedarikçi ya da belge no',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Aramayı temizle',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            _search.clear();
                            _apply();
                            setState(() {});
                          },
                        ),
                ),
              ),
              const SizedBox(height: AppSpace.md),
              const FinanceGroupTitle('Dönem'),
              const SizedBox(height: AppSpace.sm),
              Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.sm,
                children: [
                  for (final period in _Period.values)
                    ChoiceChip(
                      key: ValueKey<String>('finance_expense_period_${period.name}'),
                      label: Text(_periodLabel(period)),
                      selected: _period == period,
                      onSelected: (_) {
                        if (_period == period) return;
                        setState(() => _period = period);
                        _apply();
                      },
                    ),
                ],
              ),
              const SizedBox(height: AppSpace.md),
              const FinanceGroupTitle('Durum'),
              const SizedBox(height: AppSpace.sm),
              Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.sm,
                children: [
                  for (final (value, label) in _statuses)
                    ChoiceChip(
                      key: ValueKey<String>('finance_expense_status_$value'),
                      label: Text(label),
                      selected: _status == value,
                      onSelected: (_) {
                        if (_status == value) return;
                        setState(() => _status = value);
                        _apply();
                      },
                    ),
                ],
              ),
              if (_categories != null && _accounts != null) ...[
                const SizedBox(height: AppSpace.md),
                DropdownButtonFormField<int?>(
                  key: ValueKey<String>('finance_expense_category_filter_${_categoryId ?? 0}'),
                  isExpanded: true,
                  initialValue: _categoryId,
                  dropdownColor: p.surface,
                  style: th.bodyMedium?.copyWith(color: p.text),
                  decoration: const InputDecoration(labelText: 'Kategori', prefixIcon: Icon(Icons.sell_rounded)),
                  items: [
                    const DropdownMenuItem<int?>(value: null, child: Text('Tüm kategoriler')),
                    for (final c in _categories!)
                      DropdownMenuItem<int?>(
                        value: c.id,
                        child: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) {
                    setState(() => _categoryId = v);
                    _apply();
                  },
                ),
                const SizedBox(height: AppSpace.md),
                DropdownButtonFormField<int?>(
                  key: ValueKey<String>('finance_expense_account_filter_${_accountId ?? 0}'),
                  isExpanded: true,
                  initialValue: _accountId,
                  dropdownColor: p.surface,
                  style: th.bodyMedium?.copyWith(color: p.text),
                  decoration: const InputDecoration(labelText: 'Hesap', prefixIcon: Icon(Icons.account_balance_rounded)),
                  items: [
                    const DropdownMenuItem<int?>(value: null, child: Text('Tüm hesaplar')),
                    for (final a in _accounts!)
                      DropdownMenuItem<int?>(
                        value: a.id,
                        child: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) {
                    setState(() => _accountId = v);
                    _apply();
                  },
                ),
              ],
              if (_filterError != null) ...[
                const SizedBox(height: AppSpace.md),
                InlineNotice(
                  key: const ValueKey<String>('finance_expense_filter_error'),
                  tone: AppTone.warning,
                  message: _filterError!,
                  onRetry: _loadFilters,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpace.md),
        SectionHeader(
          title: 'Giderler',
          trailing: IconButton(
            onPressed: _loader.loading ? null : reload,
            tooltip: 'Yenile',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ),
        // Toplamlar yalnız başarılı ilk sayfa yanıtından (sunucu `totals`); hata / yükleme sırasında gösterilmez.
        if (loadedOk && totals != null) ...[
          const SizedBox(height: AppSpace.sm),
          Wrap(
            key: const ValueKey<String>('finance_expense_totals'),
            spacing: AppSpace.sm,
            runSpacing: AppSpace.xs,
            children: [
              TotalPill(label: 'Geçerli gider', minor: totals.activeMinor, tone: AppTone.danger, icon: Icons.shopping_bag_rounded),
              if (_status != 'active')
                TotalPill(label: 'İptal edilen', minor: totals.voidedMinor, tone: AppTone.neutral, icon: Icons.block_rounded),
            ],
          ),
        ],
        const SizedBox(height: AppSpace.md),
        CursorListBody<Expense>(
          loader: _loader,
          emptyIcon: Icons.shopping_bag_rounded,
          emptyTitle: _filtered ? 'Bu süzgeç için gider bulunamadı.' : 'Bu dönemde gider kaydı yok.',
          emptyMessage: _canWrite && !_filtered ? 'İlk gideri "Gider Ekle" ile kaydedin.' : null,
          itemBuilder: (context, expense) => ExpenseTile(expense: expense, onTap: () => _open(expense)),
        ),
      ],
    );
  }
}
