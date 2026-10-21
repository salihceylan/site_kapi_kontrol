import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsRole;
import 'package:site_kapi_kontrol/models/finance.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/expense_attachments.dart';
import 'package:site_kapi_kontrol/services/payment_notice_api.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/finance_payment_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/finance_receipt_flow.dart';
import 'package:site_kapi_kontrol/ui/dialogs/finance_run_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/finance_settings_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_errors.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/views/finance_balances_tab.dart';
import 'package:site_kapi_kontrol/ui/views/finance_cash_tab.dart';
import 'package:site_kapi_kontrol/ui/views/finance_charts_tab.dart';
import 'package:site_kapi_kontrol/ui/views/finance_definitions_tab.dart';
import 'package:site_kapi_kontrol/ui/views/finance_expenses_tab.dart';
import 'package:site_kapi_kontrol/ui/views/finance_late_fee_section.dart';
import 'package:site_kapi_kontrol/ui/views/finance_periods_tab.dart';
import 'package:site_kapi_kontrol/ui/views/finance_reminder_card.dart';
import 'package:site_kapi_kontrol/ui/views/finance_reports_tab.dart';
import 'package:site_kapi_kontrol/ui/views/payment_notices_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_settings_controller.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

/// Yönetici "Finans" ekranı (Platform Faz 4a, `finance` modülü): site seçici, mali özet kartı, eylemler
/// (Tahsilat Ekle, Ek Borç Ekle, Finans Ayarları) ve sekmeler (Daireler | Tanımlar | Dönemler | Kasa | Giderler |
/// Raporlar | Grafikler | Dekontlar). Faz 4b: Daireler sekmesinin üstünde borç hatırlatma kartı, Dönemler sekmesinde gecikme tazminatı bölümü;
/// tazminat ve hatırlatma yalnız sistem bayrağı (`legal_ok`) VE site ayarı açıkken kullanılır, aksi halde nedenini
/// açıklayan pasif kart gösterilir.
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
    this.expenseAttachmentSource,
    this.now,
    this.initialSiteCode,
    this.initialTab,
  });

  /// Yönetici ana sayfasından gelinen site ve sekme (0 Daireler ... 5 Raporlar); yoksa ilk site ve ilk sekme.
  final int? initialSiteCode;
  final int? initialTab;

  final AuthService authService;
  final bool manageAllSites;
  final List<PeopleSite> sites;

  /// Yalnız süper kullanıcı kapalı ayı yeniden açabilir.
  final bool canReopen;

  /// Modül kapalı bilgisinde "Modüller" düğmesi (yalnız modülü açabilen / talep edebilen kullanıcıya verilir).
  final VoidCallback? onOpenModules;

  /// Gider belgesi (fatura / fiş) eki: Belgeler modülü açıkken sağlanır; null ise gider formunda ek alanı GİZLİDİR.
  final ExpenseAttachmentSource? expenseAttachmentSource;

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
    ('Kasa', Icons.account_balance_rounded),
    ('Giderler', Icons.shopping_cart_checkout_rounded),
    ('Raporlar', Icons.insights_rounded),
    ('Dekontlar', Icons.receipt_long_rounded),
    ('Grafikler', Icons.show_chart_rounded),
  ];

  /// Sekme kimlikleri (anahtar `finance_tab_<kimlik>`, `initialTab`, bayatlama) sabit kalır; "Grafikler" (7) çubukta
  /// "Raporlar"ın hemen yanında görünür.
  static const List<int> _tabOrder = <int>[0, 1, 2, 3, 4, 5, 7, 6];

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
  GlobalKey<FinanceLateFeeSectionState> _lateFeeKey = GlobalKey<FinanceLateFeeSectionState>();
  GlobalKey<FinanceCashTabState> _cashKey = GlobalKey<FinanceCashTabState>();
  GlobalKey<FinanceExpensesTabState> _expensesKey = GlobalKey<FinanceExpensesTabState>();
  GlobalKey<FinanceReportsTabState> _reportsKey = GlobalKey<FinanceReportsTabState>();
  GlobalKey<FinanceChartsTabState> _chartsKey = GlobalKey<FinanceChartsTabState>();
  GlobalKey<PaymentNoticesViewState> _noticesKey = GlobalKey<PaymentNoticesViewState>();

  // Dekont bildirimi (2B): bekleyen dekont sayısı ("Dekontlar" sekmesi rozeti).
  int _noticeCount = 0;

  // Faz 4b ayarları (makbuz / tazminat / hatırlatma): site başına tek yükleyici; site değişince atılır.
  FinanceSettingsController? _settings;

  FinanceSummary? _summary;
  String? _summaryError;
  bool _moduleOff = false;
  int _summaryToken = 0;

  // Tahsilat / ek borç pencereleri çift dokunuşta iki kez açılmasın.
  bool _opening = false;

  int? _pendingTab;
  int? _wantedSite;

  @override
  void initState() {
    super.initState();
    _wantedSite = widget.initialSiteCode;
    final tab = widget.initialTab;
    _pendingTab = tab != null && tab >= 0 && tab < _tabs.length ? tab : null;
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
    _settings?.dispose();
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
    unawaited(_settings?.load() ?? Future<void>.value());
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
    final wanted = _wantedSite;
    final preferred = !keep && wanted != null && merged.any((s) => s.code == wanted);
    final next = keep ? _siteCode : (preferred ? wanted : (merged.isEmpty ? null : merged.first.code));
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
    _tab = _pendingTab ?? 0;
    _pendingTab = null;
    _visited
      ..clear()
      ..add(_tab);
    _dirty.clear();
    _balancesKey = GlobalKey<FinanceBalancesTabState>();
    _definitionsKey = GlobalKey<FinanceDefinitionsTabState>();
    _periodsKey = GlobalKey<FinancePeriodsTabState>();
    _lateFeeKey = GlobalKey<FinanceLateFeeSectionState>();
    _cashKey = GlobalKey<FinanceCashTabState>();
    _expensesKey = GlobalKey<FinanceExpensesTabState>();
    _reportsKey = GlobalKey<FinanceReportsTabState>();
    _chartsKey = GlobalKey<FinanceChartsTabState>();
    _noticesKey = GlobalKey<PaymentNoticesViewState>();
    _noticeCount = 0;
    ++_summaryToken;
    _summary = null;
    _summaryError = null;
    _moduleOff = false;
    // Eski sitenin ayarı yeni sitenin ekranında görünmesin: denetleyici atılır, yenisi kurulur.
    _settings?.dispose();
    _settings = null;
    final next = _site;
    if (siteCode != null && next != null) _settings = FinanceSettingsController(_scopeOf(next));
    if (siteCode != null) {
      // Özet bu çerçeveden sonra çekilir (setState içinde başka setState çağırılmaz).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _siteCode != siteCode) return;
        unawaited(_loadSummary());
        unawaited(_settings?.load() ?? Future<void>.value());
      });
    }
  }

  Future<void> _loadSummary() async {
    final code = _siteCode;
    if (code == null || !mounted) return;
    final token = ++_summaryToken;
    unawaited(_loadNoticeCount(code));
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

  /// Bekleyen dekont sayısı (rozet). Yalnız yazma yetkisi olan yönetici sorar; hata sessizdir (rozet görünmez).
  Future<void> _loadNoticeCount(int code) async {
    if (_site?.canWrite != true) return;
    try {
      final attention = await PaymentNoticeService.of(widget.authService).run((api, token) => api.summary(token: token, siteCode: code));
      if (mounted && code == _siteCode && attention.count != _noticeCount) setState(() => _noticeCount = attention.count);
    } catch (_) {
      // rozet isteğe bağlıdır
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
        unawaited(_lateFeeKey.currentState?.reload() ?? Future<void>.value());
      case 3:
        unawaited(_cashKey.currentState?.reload() ?? Future<void>.value());
      case 4:
        unawaited(_expensesKey.currentState?.reload() ?? Future<void>.value());
      case 5:
        unawaited(_reportsKey.currentState?.reload() ?? Future<void>.value());
      case 6:
        unawaited(_noticesKey.currentState?.reload() ?? Future<void>.value());
      case 7:
        unawaited(_chartsKey.currentState?.reload() ?? Future<void>.value());
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
    // Her tahsilatta makbuz otomatik düzenlenir (Q1): makbuz penceresi açılır.
    _opening = true;
    try {
      await openReceiptAfterPayment(context, scope: _scopeOf(site), outcome: outcome, onChanged: _refreshAll);
    } finally {
      _opening = false;
    }
  }

  /// "Finans Ayarları": ayarlar okunamadıysa pencere AÇILMAZ (varsayılan değerle üstüne yazılmasın); önce yeniden okunur.
  Future<void> _openSettings(PeopleSite site) async {
    if (_opening) return;
    final controller = _settings;
    if (controller == null) return;
    _opening = true;
    try {
      if (controller.settings == null) {
        await controller.load();
        if (!mounted) return;
      }
      if (controller.settings == null) {
        showFinanceSnack(context, controller.error ?? 'Ayarlar yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.');
        return;
      }
      final saved = await FinanceSettingsDialog.show(
        context,
        scope: _scopeOf(site),
        controller: controller,
        now: widget.now,
      );
      if (!saved || !mounted) return;
      showFinanceSnack(context, 'Finans ayarları kaydedildi.');
    } finally {
      _opening = false;
    }
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
            const SizedBox(height: AppSpace.sm),
            PrimaryActionButton(
              key: const ValueKey<String>('finance_open_settings'),
              label: 'Finans Ayarları',
              icon: Icons.tune_rounded,
              variant: AppButtonVariant.tonal,
              onPressed: () => _openSettings(site),
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
                for (final i in _tabOrder)
                  MergeSemantics(
                    child: Semantics(
                      role: SemanticsRole.tab,
                      child: ChoiceChip(
                        key: ValueKey<String>('finance_tab_$i'),
                        avatar: Icon(_tabs[i].$2, size: 18),
                        label: Text(i == 6 && _noticeCount > 0 ? '${_tabs[i].$1} ($_noticeCount)' : _tabs[i].$1),
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
        final remindSettings = _settings;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (remindSettings != null) ...[
              FinanceReminderCard(
                scope: scope,
                settings: remindSettings,
                onOpenSettings: () => _openSettings(_siteOf(scope)),
                onDataChanged: () => _afterWrite(0),
              ),
              const SizedBox(height: AppSpace.md),
            ],
            FinanceBalancesTab(
              key: _balancesKey,
              scope: scope,
              now: widget.now,
              onDataChanged: () => _afterWrite(0),
            ),
          ],
        );
      case 1:
        return FinanceDefinitionsTab(
          key: _definitionsKey,
          scope: scope,
          now: widget.now,
          onDataChanged: () => _afterWrite(1),
        );
      case 2:
        final lateSettings = _settings;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FinancePeriodsTab(
              key: _periodsKey,
              scope: scope,
              canReopen: widget.canReopen,
              now: widget.now,
              onDataChanged: () => _afterWrite(2),
            ),
            if (lateSettings != null) ...[
              const SizedBox(height: AppSpace.lg),
              FinanceLateFeeSection(
                key: _lateFeeKey,
                scope: scope,
                settings: lateSettings,
                now: widget.now,
                onOpenSettings: () => _openSettings(_siteOf(scope)),
                onDataChanged: () => _afterWrite(2),
              ),
            ],
          ],
        );
      case 3:
        return FinanceCashTab(
          key: _cashKey,
          scope: scope,
          now: widget.now,
          onDataChanged: () => _afterWrite(3),
        );
      case 4:
        return FinanceExpensesTab(
          key: _expensesKey,
          scope: scope,
          now: widget.now,
          attachmentSource: widget.expenseAttachmentSource,
          onDataChanged: () => _afterWrite(4),
        );
      default:
        if (index == 6) {
          return PaymentNoticesView(
            key: _noticesKey,
            scope: scope,
            onDataChanged: () => _afterWrite(6),
            onAttention: (count) {
              if (mounted && count != _noticeCount) setState(() => _noticeCount = count);
            },
          );
        }
        if (index == 7) {
          return FinanceChartsTab(key: _chartsKey, scope: scope);
        }
        return FinanceReportsTab(key: _reportsKey, scope: scope, now: widget.now);
    }
  }

  PeopleSite _siteOf(PeopleScope scope) =>
      _sites.firstWhere((s) => s.code == scope.siteCode, orElse: () => PeopleSite(code: scope.siteCode, name: scope.siteName, canWrite: scope.canWrite));
}
