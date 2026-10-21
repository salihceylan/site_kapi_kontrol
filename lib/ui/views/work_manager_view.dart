import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/ui/helpers/list_export.dart';
import 'package:site_kapi_kontrol/models/work_tracking_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/work_attachment_picker.dart';
import 'package:site_kapi_kontrol/services/work_tracking_api.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/work_manager_detail_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/cursor_loader.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart'
    show crmMessageOf;
import 'package:site_kapi_kontrol/ui/views/work_report_tab.dart';
import 'package:site_kapi_kontrol/ui/widgets/cursor_list_body.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/work_tracking_parts.dart';

/// Yönetim ekranının sekmeleri: talep listesi ve rapor.
enum WorkManagerTab { list, report }

/// Yönetim "Talepler" ekranı (İş Takibi, `work_tracking` modülü): yönetici / süper kullanıcı (yazar), görevli
/// (kendine atanmış ya da atanmamış talepleri yazar) ve yönetim kurulu (SALT OKUR).
///
/// - [manageAllSites] true (süper kullanıcı): tüm onaylı siteler listelenir ve yazma yetkisi vardır.
/// - [sites]: `GET /app/my-modules` ile `work_tracking` modülü AÇIK siteler (erişim türüyle). Menü kapısı ve site
///   listesi HomePage'dedir; sunucu yine de her çağrıda yetkiyi ve modül durumunu doğrular.
/// - Kurul ([WorkSiteAccess.board]): hiçbir yazma düğmesi çizilmez, "yalnızca görüntüleyebilirsiniz" notu gösterilir;
///   iç not ve sakin iletişim bilgisi sunucudan zaten gelmez.
/// - "Rapor" sekmesi YALNIZ yönetici ve kurul için çizilir ([workReportAllowed]; görevli ve diğer her şey için
///   kapalı — fail-closed); site değişince izin yoksa liste sekmesine dönülür.
///
/// Site değişince liste durumu atılır (eski sitenin yanıtı yeni sitenin ekranına yazılamaz). HATA ASLA "talep yok"
/// demez; modül kapalıysa (403 `MODULE_DISABLED`) açıklayıcı kart çıkar. [WorkManagerViewState.reload] sayfa
/// kabuğunun aşağı çekip yenilemesinden çağrılır (rapor sekmesi açıksa rapor da yenilenir).
class WorkManagerView extends StatefulWidget {
  const WorkManagerView({
    super.key,
    required this.authService,
    this.service,
    this.manageAllSites = false,
    this.sites = const <WorkTrackingSite>[],
    this.onOpenModules,
    this.photoPicker,
  });

  final AuthService authService;
  final WorkTrackingService? service;
  final bool manageAllSites;
  final List<WorkTrackingSite> sites;
  final VoidCallback? onOpenModules;

  /// Fotoğraf seçici (testlerde sahte); null ise gerçek `file_picker`.
  final WorkPhotoPicker? photoPicker;

  @override
  State<WorkManagerView> createState() => WorkManagerViewState();
}

class WorkManagerViewState extends State<WorkManagerView> {
  List<WorkTrackingSite> _sites = const <WorkTrackingSite>[];
  int? _siteCode;
  bool _loadingSites = false;
  bool _sitesLoadedOnce = false;
  String? _sitesError;
  int _sitesToken = 0;
  WorkManagerTab _tab = WorkManagerTab.list;
  final GlobalKey<WorkReportTabState> _reportKey = GlobalKey<WorkReportTabState>();

  final TextEditingController _search = TextEditingController();
  Timer? _timer;
  String _query = '';
  String _status = 'open';
  String? _category;
  String? _priority;
  String? _assigned;
  Map<WorkStatus, int> _counts = const <WorkStatus, int>{};
  bool _moduleOff = false;
  String _lastSignature = '';

  late WorkTrackingService _service =
      widget.service ?? WorkTrackingService(authService: widget.authService);

  late final CursorLoader<WorkManagedItem> _loader =
      CursorLoader<WorkManagedItem>(
        fetch: (before) async {
          final site = _siteCode;
          if (site == null) return (items: const <WorkManagedItem>[], next: null);
          final page = await _service.listManaged(
            site,
            status: _status == 'all' ? null : _status,
            category: _category,
            priority: _priority,
            assigned: _assigned,
            query: _query,
            limit: 30,
            beforeId: before,
          );
          if (before == null) {
            _counts = page.counts;
            _moduleOff = false;
          }
          return (items: page.items, next: page.nextBeforeId);
        },
        keyOf: (item) => item.id,
        notify: () {
          if (mounted) setState(() {});
        },
        isAlive: () => mounted,
        errorFallback:
            'Talepler yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
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
    unawaited(reload());
  }

  @override
  void didUpdateWidget(WorkManagerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.service, widget.service) ||
        !identical(oldWidget.authService, widget.authService)) {
      _service =
          widget.service ?? WorkTrackingService(authService: widget.authService);
    }
    if (oldWidget.manageAllSites != widget.manageAllSites ||
        !listEquals(oldWidget.sites, widget.sites)) {
      unawaited(reload());
    }
  }

  @override
  void dispose() {
    ++_sitesToken;
    _timer?.cancel();
    _search.dispose();
    _loader.dispose();
    super.dispose();
  }

  WorkTrackingSite? get _site {
    final code = _siteCode;
    if (code == null) return null;
    for (final site in _sites) {
      if (site.code == code) return site;
    }
    return null;
  }

  String get _signature =>
      '${_siteCode ?? ''}|$_query|$_status|${_category ?? ''}|${_priority ?? ''}|${_assigned ?? ''}';

  /// Siteleri ve görünen listeyi yeniden çeker (mevcut liste yenileme sürerken ekranda kalır).
  Future<void> reload() async {
    if (!mounted) return;
    final token = ++_sitesToken;
    setState(() {
      _loadingSites = true;
      _sitesError = null;
    });
    try {
      final merged = <WorkTrackingSite>[];
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
              merged.add(WorkTrackingSite(code: site.id, name: site.name));
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
      final siteChanged = next != _siteCode;
      final previous = _site;
      setState(() {
        _sites = merged;
        _loadingSites = false;
        _sitesLoadedOnce = true;
        _siteCode = next;
        if (siteChanged) _counts = const <WorkStatus, int>{};
      });
      final current = _site;
      if (current != null && !workReportAllowed(current.access) && _tab == WorkManagerTab.report) {
        setState(() => _tab = WorkManagerTab.list);
      }
      if (siteChanged || (previous != null && current != null && previous.access != current.access)) {
        _resetList();
      } else if (current != null) {
        unawaited(_loader.reload());
      }
      if (_tab == WorkManagerTab.report) unawaited(_reportKey.currentState?.reload());
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

  /// Süzgeç / site değişimi: eski kayıtlar atılır ve liste baştan çekilir.
  void _resetList() {
    _lastSignature = _signature;
    _loader.reset();
    if (_siteCode != null) unawaited(_loader.reload());
  }

  void _applyFilters() {
    _timer?.cancel();
    _query = _search.text.trim();
    if (_signature == _lastSignature &&
        (_loader.loading || (_loader.loadedOnce && _loader.error == null))) {
      return;
    }
    _resetList();
  }

  void _onSearchChanged(String _) {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 350), _applyFilters);
    setState(() {});
  }

  void _setFilter(VoidCallback change) {
    setState(change);
    _applyFilters();
  }

  String _siteLabel(WorkTrackingSite site) {
    final same = _sites.where((s) => s.label == site.label).toList();
    if (same.length < 2) return site.label;
    return '${site.label} (${same.indexOf(site) + 1})';
  }

  void _selectSite(int code) {
    if (code == _siteCode) return;
    setState(() {
      _siteCode = code;
      _counts = const <WorkStatus, int>{};
      _moduleOff = false;
      final next = _site;
      if (next != null && !workReportAllowed(next.access)) _tab = WorkManagerTab.list;
    });
    _resetList();
  }

  void _selectTab(WorkManagerTab tab, WorkTrackingSite site) {
    if (tab == _tab) return;
    // Fail-closed: izin yoksa rapor sekmesine geçilmez.
    if (tab == WorkManagerTab.report && !workReportAllowed(site.access)) return;
    setState(() => _tab = tab);
  }

  Future<void> _open(WorkManagedItem item, WorkTrackingSite site) async {
    final changed = await WorkManagerDetailDialog.show(
      context,
      service: _service,
      site: site,
      item: item,
      picker: widget.photoPicker ?? const FilePickerWorkPhotoPicker(),
    );
    if (changed && mounted) unawaited(_loader.reload());
  }

  bool get _filtered =>
      _query.isNotEmpty ||
      _status != 'open' ||
      _category != null ||
      _priority != null ||
      _assigned != null;

  int? _openCount() {
    if (_counts.isEmpty) return null;
    return (_counts[WorkStatus.yeni] ?? 0) +
        (_counts[WorkStatus.islemde] ?? 0) +
        (_counts[WorkStatus.beklemede] ?? 0) +
        (_counts[WorkStatus.cozuldu] ?? 0);
  }

  String _chipLabel(String label, int? count) =>
      count == null ? label : '$label ($count)';

  @override
  Widget build(BuildContext context) {
    final site = _site;
    if (site == null) {
      if (_loadingSites || (!_sitesLoadedOnce && _sitesError == null)) {
        return const ListSkeleton(rows: 2);
      }
      if (_sitesError != null) {
        return InlineNotice(message: _sitesError!, onRetry: reload);
      }
      return const EmptyCard(
        icon: Icons.apartment_rounded,
        title: 'Kayıtlı site bulunamadı.',
        message:
            'Talepler, İş Takibi modülü açık bir siteye bağlı olduğunuzda burada görünür.',
      );
    }
    return _buildSite(context, site);
  }

  Widget _buildSite(BuildContext context, WorkTrackingSite site) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageHeaderCard(title: 'Talepler', icon: Icons.assignment_rounded),
        const SizedBox(height: AppSpace.sm),
        Text(
          switch (site.access) {
            WorkSiteAccess.staff =>
              'Size atanan ve henüz kimseye atanmamış talepleri görür, durumunu güncellersiniz.',
            WorkSiteAccess.board =>
              'Sitedeki arıza, bakım ve talepleri izleyin.',
            WorkSiteAccess.manager =>
              'Sakinlerin açtığı arıza, bakım ve talepleri izleyin; durum, öncelik ve atama yapın.',
          },
          style: th.bodyMedium,
        ),
        const SizedBox(height: AppSpace.lg),
        if (_sitesError != null) ...[
          InlineNotice(message: _sitesError!, onRetry: reload),
          const SizedBox(height: AppSpace.md),
        ],
        if (_sites.length > 1)
          AppCard(
            child: DropdownButtonFormField<int>(
              key: ValueKey<String>('work_site_${site.code}_${_sites.length}'),
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
        if (site.access == WorkSiteAccess.board) ...[
          const InlineNotice(
            key: ValueKey<String>('work_read_only_note'),
            tone: AppTone.info,
            icon: Icons.visibility_rounded,
            message:
                'Yönetim kurulu üyesi olarak talepleri yalnızca görüntüleyebilirsiniz. İç notlar ve sakinlerin iletişim bilgileri görünmez.',
          ),
          const SizedBox(height: AppSpace.md),
        ],
        if (_moduleOff)
          _buildModuleOff(context)
        else ...[
          if (workReportAllowed(site.access)) ...[
            _buildTabs(context, site),
            const SizedBox(height: AppSpace.md),
          ],
          if (_tab == WorkManagerTab.report && workReportAllowed(site.access))
            WorkReportTab(key: _reportKey, service: _service, site: site)
          else ...[
            _buildFilters(context),
            const SizedBox(height: AppSpace.md),
            SectionHeader(
              title: 'Talepler',
              trailing: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[ListExportButton(enabled: _loader.items.isNotEmpty, source: localExportSource(label: 'İş talepleri', filenameBase: 'is_talepleri', headers: <String>['No', 'Başlık', 'Kategori', 'Durum', 'Öncelik', 'Konum', 'Talep eden', 'Atanan', 'Açılış', 'Kapanış'], rows: () => <List<Object?>>[for (final w in _loader.items) [w.id, w.title, w.category.label, w.status.label, w.priority.label, w.apartment?.label ?? w.block?.label, w.requester.name, w.assignedTo?.name, exportDate(w.createdAt), exportDate(w.closedAt)]])), IconButton(
                onPressed: _loader.loading ? null : reload,
                tooltip: 'Yenile',
                icon: const Icon(Icons.refresh_rounded),
              )]),
            ),
            const SizedBox(height: AppSpace.md),
            CursorListBody<WorkManagedItem>(
              loader: _loader,
              emptyIcon: Icons.assignment_turned_in_rounded,
              emptyTitle: _filtered
                  ? 'Bu süzgeç için talep bulunamadı.'
                  : 'Açık talep yok.',
              emptyMessage: _filtered
                  ? null
                  : 'Sakinler bir talep açtığında burada görünür.',
              itemBuilder: (context, item) => WorkManagedCard(
                item: item,
                onTap: () => unawaited(_open(item, site)),
              ),
            ),
          ],
        ],
      ],
    );
  }

  /// "Talepler | Rapor" seçimi (yalnız yönetici ve kurul; görevli bu satırı hiç görmez).
  Widget _buildTabs(BuildContext context, WorkTrackingSite site) {
    return Wrap(
      spacing: AppSpace.sm,
      runSpacing: AppSpace.sm,
      children: [
        ChoiceChip(
          key: const ValueKey<String>('work_tab_list'),
          avatar: const Icon(Icons.list_alt_rounded, size: 18),
          label: const Text('Talepler'),
          selected: _tab == WorkManagerTab.list,
          onSelected: (_) => _selectTab(WorkManagerTab.list, site),
        ),
        ChoiceChip(
          key: const ValueKey<String>('work_tab_report'),
          avatar: const Icon(Icons.insights_rounded, size: 18),
          label: const Text('Rapor'),
          selected: _tab == WorkManagerTab.report,
          onSelected: (_) => _selectTab(WorkManagerTab.report, site),
        ),
      ],
    );
  }

  Widget _buildFilters(BuildContext context) {
    final th = Theme.of(context).textTheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const ValueKey<String>('work_search'),
            controller: _search,
            textInputAction: TextInputAction.search,
            onChanged: _onSearchChanged,
            onSubmitted: (_) => _applyFilters(),
            decoration: InputDecoration(
              labelText: 'Talep ara',
              hintText: 'Başlık veya açıklama',
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
          Text('Durum', style: th.titleSmall),
          const SizedBox(height: AppSpace.sm),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: [
              ChoiceChip(
                key: const ValueKey<String>('work_status_open'),
                label: Text(_chipLabel('Açık', _openCount())),
                selected: _status == 'open',
                onSelected: (_) => _setFilter(() => _status = 'open'),
              ),
              for (final status in WorkStatus.known)
                ChoiceChip(
                  key: ValueKey<String>('work_status_${status.apiValue}'),
                  label: Text(_chipLabel(status.label, _counts[status])),
                  selected: _status == status.apiValue,
                  onSelected: (_) =>
                      _setFilter(() => _status = status.apiValue),
                ),
              ChoiceChip(
                key: const ValueKey<String>('work_status_all'),
                label: const Text('Tümü'),
                selected: _status == 'all',
                onSelected: (_) => _setFilter(() => _status = 'all'),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          _dropdown(
            context,
            fieldKey: 'work_filter_category',
            label: 'Kategori',
            icon: Icons.category_rounded,
            value: _category ?? '',
            options: <(String, String)>[
              ('', 'Tüm kategoriler'),
              for (final c in WorkCategory.values) (c.apiValue, c.label),
            ],
            onChanged: (v) => _setFilter(() => _category = v.isEmpty ? null : v),
          ),
          const SizedBox(height: AppSpace.md),
          _dropdown(
            context,
            fieldKey: 'work_filter_priority',
            label: 'Öncelik',
            icon: Icons.flag_outlined,
            value: _priority ?? '',
            options: <(String, String)>[
              ('', 'Tüm öncelikler'),
              for (final pr in WorkPriority.values) (pr.apiValue, pr.label),
            ],
            onChanged: (v) => _setFilter(() => _priority = v.isEmpty ? null : v),
          ),
          const SizedBox(height: AppSpace.md),
          _dropdown(
            context,
            fieldKey: 'work_filter_assigned',
            label: 'Atanan',
            icon: Icons.person_rounded,
            value: _assigned ?? '',
            options: const <(String, String)>[
              ('', 'Hepsi'),
              ('me', 'Bana atananlar'),
              ('none', 'Atanmamış olanlar'),
            ],
            onChanged: (v) => _setFilter(() => _assigned = v.isEmpty ? null : v),
          ),
        ],
      ),
    );
  }

  Widget _dropdown(
    BuildContext context, {
    required String fieldKey,
    required String label,
    required IconData icon,
    required String value,
    required List<(String, String)> options,
    required ValueChanged<String> onChanged,
  }) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    return DropdownButtonFormField<String>(
      key: ValueKey<String>('${fieldKey}_$value'),
      isExpanded: true,
      initialValue: value,
      dropdownColor: p.surface,
      style: th.bodyMedium?.copyWith(color: p.text),
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
      items: [
        for (final option in options)
          DropdownMenuItem<String>(
            value: option.$1,
            child: Text(
              option.$2,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: (v) {
        if (v != null && v != value) onChanged(v);
      },
    );
  }

  Widget _buildModuleOff(BuildContext context) {
    final th = Theme.of(context).textTheme;
    return EmptyCard(
      key: const ValueKey<String>('work_module_off'),
      icon: Icons.assignment_late_rounded,
      tone: AppTone.warning,
      title: 'İş takibi bu site için kapalı.',
      message:
          'Modül açılınca sakinlerin arıza, bakım ve talepleri burada görünür.',
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
                  key: const ValueKey<String>('work_open_modules'),
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
}
