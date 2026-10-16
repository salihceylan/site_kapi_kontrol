import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsRole;
import 'package:site_kapi_kontrol/models/finance.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/finance_payment_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/finance_run_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_errors.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/views/finance_balances_tab.dart';
import 'package:site_kapi_kontrol/ui/views/finance_definitions_tab.dart';
import 'package:site_kapi_kontrol/ui/views/finance_periods_tab.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

/// Yönetici "Finans" ekranı (Platform Faz 4a, `finance` modülü): site seçici, mali özet kartı, eylemler
/// (Tahsilat Ekle, Ek Borç Ekle) ve üç sekme (Daireler | Tanımlar | Dönemler).
///
/// - [manageAllSites] true (süper kullanıcı): tüm onaylı siteler listelenir, yazma yetkisi vardır. [sites]:
///   açıkça verilen siteler (`GET /app/my-modules`: `finance` modülü AÇIK olan yönetilen siteler yazma, kurul
///   üyesi olunan siteler salt okunur). Menü kapısı ve site listesi HomePage'dedir; sunucu yine de her
///   çağrıda yetkiyi ve modül durumunu doğrular (403 `FORBIDDEN_ROLE` / `MODULE_DISABLED`).
/// - Kurul üyesi (canWrite false) SALT OKUR: hiçbir yazma düğmesi çizilmez, "yalnızca görüntüleyebilirsiniz" notu
///   gösterilir.
/// - Modül kapalıysa (özet 403 `MODULE_DISABLED`) sekmeler yerine açıklayıcı bilgi gösterilir; hata asla
///   "borç yok" demez.
/// - Sekmeler tembel kurulur ve durumlarını korur; bir sekmedeki yazma diğerlerini "bayat" işaretler.
///   Site değişince tüm durum atılır (eski sitenin yanıtı yeni sitenin ekranına yazılamaz).
class FinanceView extends StatefulWidget {
  const FinanceView({
    super.key,
    required this.authService,
    this.manageAllSites = false,
    this.sites = const <PeopleSite>[],
    this.canReopen = false,
    this.onOpenModules,
    this.now,
  });

  final AuthService authService;
  final bool manageAllSites;
  final List<PeopleSite> sites;

  /// Yalnız süper kullanıcı kapalı ayı yeniden açabilir.
  final bool canReopen;

  /// Modül kapalı bilgisinde "Modüller" düğmesi (yalnız modülü açabilen / talep edebilen kullanıcıya verilir).
  final VoidCallback? onOpenModules;

  /// Şimdiki zaman (testler içindir).
  final DateTime Function()? now;

  @override
  State<FinanceView> createState() => FinanceViewState();
}

class FinanceViewState extends State<FinanceView> {
  static const List<(String, IconData)> _tabs = <(String, IconData)>[
    ('Daireler', Icons.apartment_rounded),
    ('Tanımlar', Icons.request_quote_rounded),
    ('Dönemler', Icons.calendar_month_rounded),
  ];

  List<PeopleSite> _sites = const <PeopleSite>[];
  int? _siteCode;
  bool _loadingSites = false;
  bool _sitesLoadedOnce = false;
  String? _sitesError;
  int _sitesToken = 0;

  int _tab = 0;
  final Set<int> _visited = <int>{0};
  final Set<int> _dirty = <int>{};

  GlobalKey<FinanceBalancesTabState> _balancesKey = GlobalKey<FinanceBalancesTabState>();
  GlobalKey<FinanceDefinitionsTabState> _definitionsKey = GlobalKey<FinanceDefinitionsTabState>();
  GlobalKey<FinancePeriodsTabState> _periodsKey = GlobalKey<FinancePeriodsTabState>();

  FinanceSummary? _summary;
  String? _summaryError;
  bool _moduleOff = false;
  int _summaryToken = 0;

  // Tahsilat / ek borç pencereleri çift dokunuşta iki kez açılmasın.
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSites());
  }

  @override
  void didUpdateWidget(FinanceView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.manageAllSites != widget.manageAllSites ||
        !listEquals(oldWidget.sites, widget.sites)) {
      unawaited(_loadSites());
    }
  }

  @override
  void dispose() {
    ++_sitesToken;
    ++_summaryToken;
    super.dispose();
  }

  PeopleSite? get _site {
    final code = _siteCode;
    if (code == null) return null;
    for (final site in _sites) {
      if (site.code == code) return site;
    }
    return null;
  }

  /// Siteleri, özeti ve görünen sekmeyi yeniden çeker (çekip yenileme / yenile düğmesi).
  Future<void> reload() async {
    await _loadSites();
    if (!mounted) return;
    final site = _site;
    if (site == null) return;
    unawaited(_loadSummary());
    _reloadVisibleTab();
    _markOthersDirty(_tab);
  }

  Future<void> _loadSites() async {
    if (!mounted) return;
    final token = ++_sitesToken;
    final merged = <PeopleSite>[];
    if (widget.manageAllSites) {
      setState(() {
        _loadingSites = true;
        _sitesError = null;
      });
      try {
        // Süper kullanıcıda site sayısı 100'ü aşabilir: onaylı siteler sayfa sayfa toplanır (üst sınır 50 sayfa).
        var pageNo = 1;
        var fetched = 0;
        while (true) {
          final page = await widget.authService.listSites(
            page: pageNo,
            pageSize: 100,
            approvalStatus: 'approved',
          );
          for (final site in page.sites) {
            if (site.isApproved && !merged.any((m) => m.code == site.id)) {
              merged.add(PeopleSite(code: site.id, name: site.name, canWrite: true));
            }
          }
          fetched += page.sites.length;
          if (page.sites.isEmpty || fetched >= page.total || pageNo >= 50) break;
          if (!mounted || token != _sitesToken) return;
          pageNo++;
        }
      } catch (e) {
        if (!mounted || token != _sitesToken) return;
        setState(() {
          _loadingSites = false;
          _sitesError = financeMessageOf(
            e,
            'Siteler yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
          );
        });
        return;
      }
    }
    for (final site in widget.sites) {
      if (!merged.any((m) => m.code == site.code)) merged.add(site);
    }
    if (!mounted || token != _sitesToken) return;
    final keep = _siteCode != null && merged.any((s) => s.code == _siteCode);
    final next = keep ? _siteCode : (merged.isEmpty ? null : merged.first.code);
    final siteChanged = next != _siteCode;
    final previous = _site;
    setState(() {
      _sites = merged;
      _loadingSites = false;
      _sitesLoadedOnce = true;
      if (siteChanged) _resetSite(next);
    });
    // Yetki değiştiyse (ör. kurul üyeliği yönetime döndü) sekme durumu atılır.
    final current = _site;
    if (!siteChanged && current != null && previous != null && previous.canWrite != current.canWrite) {
      setState(() => _resetSite(current.code));
    }
  }

  /// Site değişti: sekme durumu ve özet atılır; uçuştaki eski yanıtlar yok sayılır.
  void _resetSite(int? siteCode) {
    _siteCode = siteCode;
    _tab = 0;
    _visited
      ..clear()
      ..add(0);
    _dirty.clear();
    _balancesKey = GlobalKey<FinanceBalancesTabState>();
    _definitionsKey = GlobalKey<FinanceDefinitionsTabState>();
    _periodsKey = GlobalKey<FinancePeriodsTabState>();
    ++_summaryToken;
    _summary = null;
    _summaryError = null;
    _moduleOff = false;
    if (siteCode != null) {
      // Özet bu çerçeveden sonra çekilir (setState içinde başka setState çağırılmaz).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _siteCode == siteCode) unawaited(_loadSummary());
      });
    }
  }

  Future<void> _loadSummary() async {
    final code = _siteCode;
    if (code == null || !mounted) return;
    final token = ++_summaryToken;
    setState(() => _summaryError = null);
    try {
      final summary = await widget.authService.getFinanceSummary(code);
      if (!mounted || token != _summaryToken || code != _siteCode) return;
      setState(() {
        _summary = summary;
        _moduleOff = false;
      });
    } catch (e) {
      if (!mounted || token != _summaryToken || code != _siteCode) return;
      setState(() {
        // Eski özet gösterilmez: yazmadan önceki tutarlar yanıltmasın.
        _summary = null;
        if (isFinanceModuleDisabled(e)) {
          _moduleOff = true;
        } else {
          _summaryError = financeMessageOf(
            e,
            'Mali özet yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
          );
        }
      });
    }
  }

  void _reloadVisibleTab() {
    switch (_tab) {
      case 0:
        unawaited(_balancesKey.currentState?.reload() ?? Future<void>.value());
      case 1:
        unawaited(_definitionsKey.currentState?.reload() ?? Future<void>.value());
      case 2:
        unawaited(_periodsKey.currentState?.reload() ?? Future<void>.value());
    }
  }

  void _markOthersDirty(int source) {
    for (final index in _visited) {
      if (index != source) _dirty.add(index);
    }
  }

  /// Bir sekmede ya da pencerede yazma yapıldı: özet tazelenir, öteki sekmeler bayatlar.
  void _afterWrite(int sourceTab) {
    _markOthersDirty(sourceTab);
    unawaited(_loadSummary());
  }

  void _selectTab(int index) {
    if (index == _tab) return;
    final stale = _dirty.remove(index);
    setState(() {
      _tab = index;
      _visited.add(index);
    });
    if (stale) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _tab == index) _reloadVisibleTab();
      });
    }
  }

  void _selectSite(int code) {
    if (code == _siteCode) return;
    setState(() => _resetSite(code));
  }

  /// Seçicide yalnız site adı görünür (site kodu teknik bir ifadedir). Aynı ad birden çok sitede varsa
  /// ayırt etmek için sıra numarası eklenir.
  String _siteLabel(PeopleSite site) {
    final same = _sites.where((s) => s.label == site.label).toList();
    if (same.length < 2) return site.label;
    return '${site.label} (${same.indexOf(site) + 1})';
  }

  PeopleScope _scopeOf(PeopleSite site) => PeopleScope(
    authService: widget.authService,
    siteCode: site.code,
    siteName: site.name,
    canWrite: site.canWrite,
  );

  Future<void> _addPayment(PeopleSite site) async {
    if (_opening) return;
    _opening = true;
    final FinancePaymentOutcome? outcome;
    try {
      outcome = await FinancePaymentDialog.show(
        context,
        scope: _scopeOf(site),
        now: widget.now,
        // Sonuç belirsiz kaldıysa liste ve özet tazelenir.
        onRefreshNeeded: () => _refreshAll(),
      );
    } finally {
      _opening = false;
    }
    if (outcome == null || !mounted) return;
    showFinanceSnack(context, outcome.message);
    _refreshAll();
  }

  Future<void> _addCharge(PeopleSite site) async {
    if (_opening) return;
    _opening = true;
    final FinanceRunOutcome? outcome;
    try {
      outcome = await FinanceRunDialog.showCharge(
        context,
        scope: _scopeOf(site),
        now: widget.now,
        onRefreshNeeded: () => _refreshAll(),
      );
    } finally {
      _opening = false;
    }
    if (outcome == null || !mounted) return;
    showFinanceSnack(context, outcome.message);
    _refreshAll();
  }

  /// Her sekme yeniden okunur ve özet tazelenir (yazma sonrası).
  void _refreshAll() {
    if (!mounted) return;
    unawaited(_loadSummary());
    _reloadVisibleTab();
    for (final index in _visited) {
      if (index != _tab) _dirty.add(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final site = _site;
    final Widget content;
    if (site == null) {
      if (_loadingSites || (!_sitesLoadedOnce && _sitesError == null)) {
        content = const ListSkeleton(rows: 2);
      } else if (_sitesError != null) {
        content = InlineNotice(message: _sitesError!, onRetry: reload);
      } else {
        content = const EmptyCard(
          icon: Icons.apartment_rounded,
          title: 'Kayıtlı site bulunamadı.',
          message: 'Aidat ve Finans modülü açık bir siteye bağlı olduğunuzda burada görünür.',
        );
      }
    } else {
      content = _buildSite(context, site);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageHeaderCard(title: 'Finans', icon: Icons.account_balance_wallet_rounded),
        const SizedBox(height: AppSpace.sm),
        Text(
          'Aidat tanımlarını, daire borç ve alacaklarını, tahsilatları ve mali dönemleri buradan yönetin.',
          style: th.bodyMedium,
        ),
        const SizedBox(height: AppSpace.lg),
        content,
      ],
    );
  }

  Widget _buildSite(BuildContext context, PeopleSite site) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final scope = _scopeOf(site);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_sitesError != null) ...[
          InlineNotice(message: _sitesError!, onRetry: reload),
          const SizedBox(height: AppSpace.md),
        ],
        if (_sites.length > 1)
          AppCard(
            child: DropdownButtonFormField<int>(
              key: ValueKey<String>('finance_site_${site.code}_${_sites.length}'),
              isExpanded: true,
              initialValue: site.code,
              dropdownColor: p.surface,
              style: th.bodyMedium?.copyWith(color: p.text),
              decoration: const InputDecoration(
                labelText: 'Site',
                prefixIcon: Icon(Icons.apartment_rounded),
              ),
              items: [
                for (final s in _sites)
                  DropdownMenuItem<int>(
                    value: s.code,
                    // Uzun ad satırda kısalır; tam ad uzun basınca / imleçle üzerine gelince tooltip'te görünür
                    // (ekran okuyucu zaten tam metni okur).
                    child: Tooltip(
                      message: _siteLabel(s),
                      child: Text(_siteLabel(s), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ),
              ],
              onChanged: (value) {
                if (value != null) _selectSite(value);
              },
            ),
          )
        else
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.xs,
            children: [InfoChip(site.label)],
          ),
        const SizedBox(height: AppSpace.md),
        if (!site.canWrite) ...[
          const InlineNotice(
            key: ValueKey<String>('finance_read_only_note'),
            tone: AppTone.info,
            icon: Icons.visibility_rounded,
            message:
                'Yönetim kurulu üyesi olarak mali kayıtları yalnızca görüntüleyebilirsiniz.',
          ),
          const SizedBox(height: AppSpace.md),
        ],
        if (_moduleOff)
          _buildModuleOff(context)
        else ...[
          _buildSummary(context),
          const SizedBox(height: AppSpace.md),
          if (site.canWrite) ...[
            PrimaryActionButton(
              key: const ValueKey<String>('finance_add_payment'),
              label: 'Tahsilat Ekle',
              icon: Icons.add_card_rounded,
              onPressed: () => _addPayment(site),
            ),
            const SizedBox(height: AppSpace.sm),
            PrimaryActionButton(
              key: const ValueKey<String>('finance_add_charge'),
              label: 'Ek Borç Ekle',
              icon: Icons.post_add_rounded,
              variant: AppButtonVariant.tonal,
              onPressed: () => _addCharge(site),
            ),
            const SizedBox(height: AppSpace.md),
          ],
          // Sekme çubuğu: ekran okuyucu "sekme" rolünü ve seçili durumu okur.
          Semantics(
            container: true,
            role: SemanticsRole.tabBar,
            child: Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.sm,
              children: [
                for (var i = 0; i < _tabs.length; i++)
                  MergeSemantics(
                    child: Semantics(
                      role: SemanticsRole.tab,
                      child: ChoiceChip(
                        key: ValueKey<String>('finance_tab_$i'),
                        avatar: Icon(_tabs[i].$2, size: 18),
                        label: Text(_tabs[i].$1),
                        selected: _tab == i,
                        onSelected: (_) => _selectTab(i),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.md),
          // Kurulu sekmeler durumunu korur; görünmeyenin animasyonları (iskelet) durur ve alanları klavye /
          // ekran okuyucu odağına GİRMEZ (Offstage odağı kapatmaz, ExcludeFocus kapatır).
          for (var i = 0; i < _tabs.length; i++)
            if (_visited.contains(i))
              Offstage(
                offstage: _tab != i,
                child: ExcludeFocus(
                  excluding: _tab != i,
                  child: TickerMode(enabled: _tab == i, child: _buildTab(i, scope)),
                ),
              ),
        ],
      ],
    );
  }

  Widget _buildSummary(BuildContext context) {
    final summary = _summary;
    if (summary != null) return FinanceSummaryCard(summary: summary);
    if (_summaryError != null) {
      return InlineNotice(message: _summaryError!, onRetry: _loadSummary);
    }
    return const ListSkeleton(rows: 1);
  }

  Widget _buildModuleOff(BuildContext context) {
    final th = Theme.of(context).textTheme;
    return EmptyCard(
      key: const ValueKey<String>('finance_module_off'),
      icon: Icons.account_balance_wallet_rounded,
      tone: AppTone.warning,
      title: 'Aidat ve Finans bu site için kapalı.',
      message: 'Modül açılınca aidat, borç ve tahsilat işlemleri burada görünür.',
      child: widget.onOpenModules == null
          ? null
          : Column(
              children: [
                Text(
                  'Modüller ekranından açabilir ya da talep edebilirsiniz.',
                  textAlign: TextAlign.center,
                  style: th.bodyMedium,
                ),
                const SizedBox(height: AppSpace.md),
                PrimaryActionButton(
                  key: const ValueKey<String>('finance_open_modules'),
                  label: 'Modüller',
                  icon: Icons.extension_rounded,
                  variant: AppButtonVariant.tonal,
                  expand: false,
                  onPressed: widget.onOpenModules,
                ),
              ],
            ),
    );
  }

  Widget _buildTab(int index, PeopleScope scope) {
    switch (index) {
      case 0:
        return FinanceBalancesTab(
          key: _balancesKey,
          scope: scope,
          now: widget.now,
          onDataChanged: () => _afterWrite(0),
        );
      case 1:
        return FinanceDefinitionsTab(
          key: _definitionsKey,
          scope: scope,
          now: widget.now,
          onDataChanged: () => _afterWrite(1),
        );
      default:
        return FinancePeriodsTab(
          key: _periodsKey,
          scope: scope,
          canReopen: widget.canReopen,
          now: widget.now,
          onDataChanged: () => _afterWrite(2),
        );
    }
  }
}
