import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/contract_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/contract_api.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/contract_detail_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/contract_form_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/cursor_loader.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart'
    show crmMessageOf;
import 'package:site_kapi_kontrol/ui/views/contract_vendors_tab.dart';
import 'package:site_kapi_kontrol/ui/widgets/contract_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/cursor_list_body.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

/// Yönetim "Sözleşmeler" ekranı (`contracts` modülü: Firma ve Sözleşme Takibi). Yönetici / süper kullanıcı firma ve
/// sözleşme ekler, düzenler, fesheder; yönetim kurulu ve görevli SALT OKUR (hiçbir yazma düğmesi çizilmez).
///
/// - [manageAllSites] true (süper kullanıcı): tüm onaylı siteler listelenir ve yazma yetkisi vardır.
/// - [sites]: `GET /app/my-modules` ile `contracts` modülü AÇIK siteler (erişim türüyle). Menü kapısı ve site listesi
///   HomePage'dedir; sunucu yine de her çağrıda yetkiyi ve modül durumunu doğrular.
///
/// Sekmeler: Sözleşmeler (özet kutuları + süzgeçler + imleçli liste) ve Firmalar. Site değişince sekmeler yeni siteyle
/// baştan yüklenir. HATA ASLA "kayıt yok" demez; modül kapalıysa (403 `MODULE_DISABLED`) açıklayıcı kart çıkar.
/// [ContractsViewState.reload] sayfa kabuğunun aşağı çekip yenilemesinden çağrılır.
class ContractsView extends StatefulWidget {
  const ContractsView({
    super.key,
    required this.authService,
    this.service,
    this.manageAllSites = false,
    this.sites = const <ContractSite>[],
    this.onOpenModules,
    this.launcher,
  });

  final AuthService authService;
  final ContractService? service;
  final bool manageAllSites;
  final List<ContractSite> sites;
  final VoidCallback? onOpenModules;

  /// Telefon / e-posta bağlantısı açıcı (testlerde sahte; varsayılan `url_launcher`).
  final ContractLauncher? launcher;

  @override
  State<ContractsView> createState() => ContractsViewState();
}

class ContractsViewState extends State<ContractsView> {
  List<ContractSite> _sites = const <ContractSite>[];
  int? _siteCode;
  bool _loadingSites = false;
  bool _sitesLoadedOnce = false;
  String? _sitesError;
  int _sitesToken = 0;
  int _tab = 0;

  final GlobalKey<ContractListTabState> _listKey = GlobalKey<ContractListTabState>();
  final GlobalKey<ContractVendorsTabState> _vendorsKey =
      GlobalKey<ContractVendorsTabState>();

  late ContractService _service =
      widget.service ?? ContractService(authService: widget.authService);

  @override
  void initState() {
    super.initState();
    unawaited(_loadSites());
  }

  @override
  void didUpdateWidget(ContractsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.service, widget.service) ||
        !identical(oldWidget.authService, widget.authService)) {
      _service = widget.service ?? ContractService(authService: widget.authService);
    }
    if (oldWidget.manageAllSites != widget.manageAllSites ||
        !listEquals(oldWidget.sites, widget.sites)) {
      unawaited(_loadSites());
    }
  }

  @override
  void dispose() {
    ++_sitesToken;
    super.dispose();
  }

  ContractSite? get _site {
    final code = _siteCode;
    if (code == null) return null;
    for (final site in _sites) {
      if (site.code == code) return site;
    }
    return null;
  }

  /// Siteleri yeniden çeker (süper kullanıcıda onaylı tüm siteler sayfa sayfa toplanır).
  Future<void> _loadSites() async {
    if (!mounted) return;
    final token = ++_sitesToken;
    setState(() {
      _loadingSites = true;
      _sitesError = null;
    });
    try {
      final merged = <ContractSite>[];
      if (widget.manageAllSites) {
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
              merged.add(ContractSite(code: site.id, name: site.name));
            }
          }
          fetched += page.sites.length;
          if (page.sites.isEmpty || fetched >= page.total || pageNo >= 50) {
            break;
          }
          if (!mounted || token != _sitesToken) return;
          pageNo++;
        }
      }
      for (final site in widget.sites) {
        if (!merged.any((m) => m.code == site.code)) merged.add(site);
      }
      if (!mounted || token != _sitesToken) return;
      final keep = _siteCode != null && merged.any((s) => s.code == _siteCode);
      final next = keep ? _siteCode : (merged.isEmpty ? null : merged.first.code);
      setState(() {
        _sites = merged;
        _loadingSites = false;
        _sitesLoadedOnce = true;
        _siteCode = next;
      });
    } catch (e) {
      if (!mounted || token != _sitesToken) return;
      setState(() {
        _loadingSites = false;
        _sitesError = crmMessageOf(
          e,
          'Siteler yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
        );
      });
    }
  }

  /// Siteleri ve etkin sekmeyi yeniden çeker.
  Future<void> reload() async {
    await _loadSites();
    final ContractReloadable? state = _tab == 0
        ? _listKey.currentState
        : _vendorsKey.currentState;
    await state?.reload();
  }

  String _siteLabel(ContractSite site) {
    final same = _sites.where((s) => s.label == site.label).toList();
    if (same.length < 2) return site.label;
    return '${site.label} (${same.indexOf(site) + 1})';
  }

  void _selectSite(int code) {
    if (code == _siteCode) return;
    setState(() => _siteCode = code);
  }

  void _selectTab(int tab) {
    if (tab == _tab) return;
    setState(() => _tab = tab);
  }

  @override
  Widget build(BuildContext context) {
    final site = _site;
    if (site == null) {
      if (_loadingSites || (!_sitesLoadedOnce && _sitesError == null)) {
        return const ListSkeleton(rows: 2);
      }
      if (_sitesError != null) {
        return InlineNotice(message: _sitesError!, onRetry: _loadSites);
      }
      return const EmptyCard(
        icon: Icons.apartment_rounded,
        title: 'Kayıtlı site bulunamadı.',
        message:
            'Sözleşmeler, Firma ve Sözleşme Takibi modülü açık bir siteye bağlı olduğunuzda burada görünür.',
      );
    }
    return _buildSite(context, site);
  }

  Widget _buildSite(BuildContext context, ContractSite site) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final canWrite = widget.manageAllSites || site.canWrite;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageHeaderCard(title: 'Sözleşmeler', icon: Icons.handshake_rounded),
        const SizedBox(height: AppSpace.sm),
        Text(
          canWrite
              ? 'Hizmet aldığınız firmaları ve sözleşmeleri kaydedin; bitişi yaklaşan sözleşmeleri zamanında görün.'
              : 'Sitenin hizmet aldığı firmaları ve sözleşmelerin bitiş tarihlerini izleyin.',
          style: th.bodyMedium,
        ),
        const SizedBox(height: AppSpace.lg),
        if (_sitesError != null) ...[
          InlineNotice(message: _sitesError!, onRetry: _loadSites),
          const SizedBox(height: AppSpace.md),
        ],
        if (_sites.length > 1)
          AppCard(
            child: DropdownButtonFormField<int>(
              key: ValueKey<String>('contract_site_${site.code}_${_sites.length}'),
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
                    child: Tooltip(
                      message: _siteLabel(s),
                      child: Text(
                        _siteLabel(s),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
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
        if (!canWrite) ...[
          ContractReadOnlyNote(access: site.access),
          const SizedBox(height: AppSpace.md),
        ],
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          children: [
            for (final entry in const <(int, String, String, IconData)>[
              (0, 'contracts_tab_list', 'Sözleşmeler', Icons.description_rounded),
              (1, 'contracts_tab_vendors', 'Firmalar', Icons.business_rounded),
            ])
              ChoiceChip(
                key: ValueKey<String>(entry.$2),
                avatar: Icon(entry.$4, size: 18),
                label: Text(entry.$3),
                selected: _tab == entry.$1,
                onSelected: (_) => _selectTab(entry.$1),
              ),
          ],
        ),
        const SizedBox(height: AppSpace.lg),
        if (_tab == 0)
          ContractListTab(
            key: _listKey,
            service: _service,
            site: site,
            canWrite: canWrite,
            onOpenModules: widget.onOpenModules,
          )
        else
          ContractVendorsTab(
            key: _vendorsKey,
            service: _service,
            site: site,
            canWrite: canWrite,
            onOpenModules: widget.onOpenModules,
            launcher: widget.launcher,
          ),
      ],
    );
  }
}

/// "Sözleşmeler" sekmesi: özet kutuları (süzgeç olarak da çalışır), arama + kategori + firma süzgeci ve imleçli
/// liste. Karta dokunmak ayrıntı penceresini açar; yazma yetkisi olana "Yeni Sözleşme".
class ContractListTab extends StatefulWidget {
  const ContractListTab({
    super.key,
    required this.service,
    required this.site,
    required this.canWrite,
    this.onOpenModules,
  });

  final ContractService service;
  final ContractSite site;
  final bool canWrite;
  final VoidCallback? onOpenModules;

  @override
  State<ContractListTab> createState() => ContractListTabState();
}

class ContractListTabState extends State<ContractListTab> implements ContractReloadable {
  /// Sayfa boyutu (sunucu `limit`).
  static const int pageSize = 30;

  ContractState? _state;
  ContractCategory? _category;
  int? _vendorId;
  String _query = '';
  final TextEditingController _search = TextEditingController();
  Timer? _timer;

  ContractSummary? _summary;
  int _summaryToken = 0;
  List<ContractVendor> _vendors = const <ContractVendor>[];
  int _vendorsToken = 0;
  bool _moduleOff = false;

  // Sunucu imleci opaktır (`next_cursor` metni); [CursorLoader] sayısal imleç taşıdığı için sıra numarası -> imleç
  // tablosu tutulur. Yarış koruması (hızlı süzgeç / arama değişimi): her ilk sayfa isteği yeni bir KUŞAK açar ve
  // tabloyu İSTEKTEN ÖNCE boşaltır; tablo yalnız yanıtı hâlâ güncel kuşağa ait olan istek tarafından yazılır (eski
  // yanıtı [CursorLoader] zaten yok sayar, tabloyu da bozamaz). Sıra numaraları hiç sıfırlanmaz: eski kuşağın numarası
  // yeni kuşağın imlecine denk gelemez.
  final Map<int, String> _cursors = <int, String>{};
  int _cursorSeq = 0;
  int _pageGeneration = 0;

  late final CursorLoader<Contract> _loader = CursorLoader<Contract>(
    fetch: (before) async {
      final String? after;
      final int generation;
      if (before == null) {
        generation = ++_pageGeneration;
        _cursors.clear();
        after = null;
      } else {
        generation = _pageGeneration;
        after = _cursors[before];
        // Numara bu kuşağın tablosunda yok (ör. süzgeç değişip yeni ilk sayfa alınamadı): eski süzgecin imleci yeni
        // süzgeçle gönderilmez; liste burada biter.
        if (after == null) return (items: const <Contract>[], next: null);
      }
      final page = await widget.service.listContracts(
        widget.site.code,
        state: _state?.apiValue ?? 'all',
        vendorId: _vendorId,
        category: _category?.apiValue,
        query: _query,
        cursor: after,
        limit: pageSize,
      );
      // Bu arada daha yeni bir ilk sayfa istendi: yanıt eskidir, tabloya dokunulmaz (yükleyici de yok sayar).
      if (generation != _pageGeneration) return (items: page.items, next: null);
      if (before == null) _moduleOff = false;
      int? next;
      final nextCursor = page.nextCursor;
      // Aynı imleç tekrar gelirse (sunucu tutarsızlığı) durulur: sonsuz döngü olmaz.
      if (nextCursor != null && nextCursor != after) {
        next = ++_cursorSeq;
        _cursors[next] = nextCursor;
      }
      return (items: page.items, next: next);
    },
    keyOf: (item) => item.id,
    notify: () {
      if (mounted) setState(() {});
    },
    isAlive: () => mounted,
    errorFallback:
        'Sözleşmeler yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
    messageOf: (error, fallback) {
      if (error is ApiException && error.code == 'MODULE_DISABLED') {
        _moduleOff = true;
      }
      return crmMessageOf(error, fallback);
    },
  );

  @override
  void initState() {
    super.initState();
    unawaited(_loader.reload());
    unawaited(_loadSummary());
    unawaited(_loadVendors());
  }

  @override
  void didUpdateWidget(ContractListTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.site != widget.site ||
        !identical(oldWidget.service, widget.service)) {
      _timer?.cancel();
      _search.clear();
      _query = '';
      _state = null;
      _category = null;
      _vendorId = null;
      _summary = null;
      _vendors = const <ContractVendor>[];
      _moduleOff = false;
      _resetList();
      unawaited(_loadSummary());
      unawaited(_loadVendors());
    }
  }

  @override
  void dispose() {
    ++_summaryToken;
    ++_vendorsToken;
    _timer?.cancel();
    _search.dispose();
    _loader.dispose();
    super.dispose();
  }

  @override
  Future<void> reload() async {
    unawaited(_loadSummary());
    unawaited(_loadVendors());
    await _loader.reload();
  }

  /// Özet sayıları; alınamazsa kutular "-" gösterir (liste yine çalışır).
  Future<void> _loadSummary() async {
    final token = ++_summaryToken;
    try {
      final summary = await widget.service.summary(widget.site.code);
      if (!mounted || token != _summaryToken) return;
      setState(() => _summary = summary);
    } catch (_) {
      // Özet yardımcıdır: hata kullanıcıya liste üzerinden gösterilir.
    }
  }

  /// Firma süzgecinin seçenekleri (aktif + pasif); alınamazsa süzgeç yalnız "Tüm firmalar" kalır.
  Future<void> _loadVendors() async {
    final token = ++_vendorsToken;
    try {
      final vendors = await widget.service.listVendors(widget.site.code);
      if (!mounted || token != _vendorsToken) return;
      setState(() => _vendors = vendors);
    } catch (_) {
      // Süzgeç seçenekleri yardımcıdır; hata kullanıcıya gösterilmez.
    }
  }

  void _resetList() {
    _loader.reset();
    unawaited(_loader.reload());
  }

  void _setFilter(VoidCallback change) {
    setState(change);
    _resetList();
  }

  void _toggleState(ContractState state) =>
      _setFilter(() => _state = _state == state ? null : state);

  void _applySearch() {
    _timer?.cancel();
    final next = _search.text.trim();
    if (next == _query && _loader.loadedOnce && _loader.error == null) return;
    _setFilter(() => _query = next);
  }

  void _onSearchChanged(String _) {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 350), _applySearch);
    setState(() {});
  }

  bool get _filtered =>
      _state != null || _category != null || _vendorId != null || _query.isNotEmpty;

  void _clearFilters() {
    _timer?.cancel();
    _search.clear();
    _setFilter(() {
      _state = null;
      _category = null;
      _vendorId = null;
      _query = '';
    });
  }

  Future<void> _create() async {
    final saved = await ContractFormDialog.show(
      context,
      service: widget.service,
      siteCode: widget.site.code,
    );
    if (saved == null || !mounted) return;
    AppSnack.show(context, 'Sözleşme eklendi.', kind: AppSnackKind.success);
    unawaited(reload());
  }

  Future<void> _openDetail(Contract contract) async {
    final changed = await ContractDetailDialog.show(
      context,
      service: widget.service,
      siteCode: widget.site.code,
      contract: contract,
      canWrite: widget.canWrite,
    );
    if (changed == null || !mounted) return;
    _replace(changed);
    unawaited(_loadSummary());
    unawaited(_loadVendors());
  }

  /// Değişen sözleşme listede yerine konur; süzgece artık uymuyorsa listeden düşer.
  void _replace(Contract updated) {
    final fits = (_state == null || updated.state == _state) &&
        (_category == null || updated.category == _category) &&
        (_vendorId == null || updated.vendorId == _vendorId);
    setState(() {
      _loader.items = <Contract>[
        for (final item in _loader.items)
          if (item.id != updated.id)
            item
          else if (fits)
            updated,
      ];
    });
  }

  String get _emptyTitle {
    if (_filtered) return 'Bu süzgeç için sözleşme bulunamadı.';
    return 'Henüz sözleşme yok.';
  }

  String? get _emptyMessage {
    if (_filtered) return 'Süzgeçleri değiştirin ya da temizleyin.';
    return widget.canWrite
        ? 'Asansör, güvenlik, temizlik gibi hizmet sözleşmelerini "Yeni Sözleşme" ile ekleyin; bitişi yaklaşanlar burada öne çıkar.'
        : 'Yönetici bir sözleşme eklediğinde burada görünür.';
  }

  @override
  Widget build(BuildContext context) {
    if (_moduleOff) {
      return ContractModuleOffCard(onOpenModules: widget.onOpenModules);
    }
    final state = _state;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.canWrite) ...[
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: ElevatedButton.icon(
              key: const ValueKey<String>('contract_new'),
              onPressed: () => unawaited(_create()),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Yeni Sözleşme'),
            ),
          ),
          const SizedBox(height: AppSpace.md),
        ],
        ContractSummaryTiles(
          summary: _summary,
          selected: state,
          onSelect: _toggleState,
        ),
        const SizedBox(height: AppSpace.md),
        _buildFilters(context),
        const SizedBox(height: AppSpace.md),
        SectionHeader(
          title: state == null ? 'Tüm sözleşmeler' : contractSummaryLabel(state),
          trailing: IconButton(
            onPressed: _loader.loading ? null : reload,
            tooltip: 'Yenile',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        CursorListBody<Contract>(
          loader: _loader,
          emptyIcon: Icons.handshake_outlined,
          emptyTitle: _emptyTitle,
          emptyMessage: _emptyMessage,
          itemBuilder: (context, contract) => ContractCard(
            key: ValueKey<String>('contract_card_${contract.id}'),
            contract: contract,
            onTap: () => unawaited(_openDetail(contract)),
          ),
        ),
      ],
    );
  }

  Widget _buildFilters(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final vendorId = _vendorId;
    final knownVendor = vendorId == null || _vendors.any((v) => v.id == vendorId);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const ValueKey<String>('contract_search'),
            controller: _search,
            textInputAction: TextInputAction.search,
            onChanged: _onSearchChanged,
            onSubmitted: (_) => _applySearch(),
            decoration: InputDecoration(
              labelText: 'Sözleşme ara',
              hintText: 'Başlık veya firma',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Aramayı temizle',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () {
                        _search.clear();
                        _applySearch();
                      },
                    ),
            ),
          ),
          const SizedBox(height: AppSpace.md),
          DropdownButtonFormField<String>(
            key: ValueKey<String>('contract_category_filter_${_category?.apiValue ?? 'all'}'),
            isExpanded: true,
            initialValue: _category?.apiValue ?? '',
            dropdownColor: p.surface,
            style: th.bodyMedium?.copyWith(color: p.text),
            decoration: const InputDecoration(
              labelText: 'Kategori',
              prefixIcon: Icon(Icons.category_rounded),
            ),
            items: [
              const DropdownMenuItem<String>(
                value: '',
                child: Text('Tüm kategoriler', maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              for (final category in ContractCategory.values)
                DropdownMenuItem<String>(
                  value: category.apiValue,
                  child: Text(category.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (value) {
              final next = ContractCategory.tryParse(value);
              if (next == _category) return;
              _setFilter(() => _category = next);
            },
          ),
          const SizedBox(height: AppSpace.md),
          DropdownButtonFormField<int>(
            key: ValueKey<String>('contract_vendor_filter_${vendorId ?? 0}_${_vendors.length}'),
            isExpanded: true,
            initialValue: vendorId ?? 0,
            dropdownColor: p.surface,
            style: th.bodyMedium?.copyWith(color: p.text),
            decoration: const InputDecoration(
              labelText: 'Firma',
              prefixIcon: Icon(Icons.business_rounded),
            ),
            items: [
              const DropdownMenuItem<int>(
                value: 0,
                child: Text('Tüm firmalar', maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              for (final vendor in _vendors)
                DropdownMenuItem<int>(
                  value: vendor.id,
                  child: Text(
                    vendor.isActive ? vendor.displayName : '${vendor.displayName} (pasif)',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              // Seçili firma listede yoksa (silinmiş / liste alınamadı) seçim korunur.
              if (!knownVendor)
                DropdownMenuItem<int>(
                  value: vendorId,
                  child: const Text('Seçili firma', maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (value) {
              final next = (value == null || value == 0) ? null : value;
              if (next == _vendorId) return;
              _setFilter(() => _vendorId = next);
            },
          ),
          if (_filtered) ...[
            const SizedBox(height: AppSpace.sm),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                key: const ValueKey<String>('contract_filters_reset'),
                onPressed: _clearFilters,
                icon: const Icon(Icons.filter_alt_off_rounded, size: 18),
                label: const Text('Süzgeçleri temizle'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
