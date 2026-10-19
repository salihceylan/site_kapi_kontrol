import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/visitor_log_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/visitor_log_api.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/visitor_entry_form_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/widgets/crm_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/visitor_log_parts.dart';

/// Yönetim / görevli "Ziyaretçi ve Kargo" ekranı (`visitor_log` modülü): yönetici / süper kullanıcı ve görevli
/// (kapıcı / güvenlik) kayıt girer ve kapatır; yönetim kurulu SALT OKUR.
///
/// - [manageAllSites] true (süper kullanıcı): tüm onaylı siteler listelenir ve yazma yetkisi vardır.
/// - [sites]: `GET /app/my-modules` ile `visitor_log` modülü AÇIK siteler (erişim türüyle). Menü kapısı ve site
///   listesi HomePage'dedir; sunucu yine de her çağrıda yetkiyi ve modül durumunu doğrular.
/// - Sekmeler: Bekleyen (kargo) / İçeride (ziyaretçi) / Tümü; tür süzgeci; arama. Kart eylemleri ("Teslim edildi" /
///   "Ayrıldı" / "İptal") ONAYLIDIR ve sunucunun verdiği `next_statuses` ile sınırlıdır.
///
/// Site değişince liste durumu atılır. HATA ASLA "kayıt yok" demez; modül kapalıysa (403 `MODULE_DISABLED`)
/// açıklayıcı kart çıkar. [VisitorManagerViewState.reload] sayfa kabuğunun aşağı çekip yenilemesinden çağrılır.
class VisitorManagerView extends StatefulWidget {
  const VisitorManagerView({
    super.key,
    required this.authService,
    this.service,
    this.manageAllSites = false,
    this.sites = const <VisitorSite>[],
    this.onOpenModules,
  });

  final AuthService authService;
  final VisitorLogService? service;
  final bool manageAllSites;
  final List<VisitorSite> sites;
  final VoidCallback? onOpenModules;

  @override
  State<VisitorManagerView> createState() => VisitorManagerViewState();
}

class VisitorManagerViewState extends State<VisitorManagerView> {
  List<VisitorSite> _sites = const <VisitorSite>[];
  int? _siteCode;
  bool _loadingSites = false;
  bool _sitesLoadedOnce = false;
  String? _sitesError;
  int _sitesToken = 0;

  final TextEditingController _search = TextEditingController();
  Timer? _timer;
  String _query = '';

  /// Sekme: `bekliyor` | `iceride` | '' (Tümü).
  String _status = VisitorStatus.bekliyor.apiValue;

  /// Tür süzgeci: '' (hepsi) | `cargo` | `visitor`.
  String _kind = '';
  bool _moduleOff = false;
  String _lastSignature = '';
  final Set<int> _busy = <int>{};

  late VisitorLogService _service =
      widget.service ?? VisitorLogService(authService: widget.authService);

  late final PagedLoader<VisitorEntry> _loader = PagedLoader<VisitorEntry>(
    fetch: (offset, limit) async {
      final site = _siteCode;
      if (site == null) return (items: const <VisitorEntry>[], total: 0);
      final page = await _service.listManaged(
        site,
        kind: _kind.isEmpty ? null : _kind,
        status: _status.isEmpty ? null : _status,
        query: _query,
        limit: limit,
        offset: offset,
      );
      if (offset == 0) _moduleOff = false;
      return (items: page.items, total: page.total);
    },
    keyOf: (item) => item.id,
    notify: () {
      if (mounted) setState(() {});
    },
    isAlive: () => mounted,
    pageSize: 50,
    errorFallback:
        'Kayıtlar yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
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
  void didUpdateWidget(VisitorManagerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.service, widget.service) ||
        !identical(oldWidget.authService, widget.authService)) {
      _service =
          widget.service ?? VisitorLogService(authService: widget.authService);
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

  VisitorSite? get _site {
    final code = _siteCode;
    if (code == null) return null;
    for (final site in _sites) {
      if (site.code == code) return site;
    }
    return null;
  }

  String get _signature => '${_siteCode ?? ''}|$_query|$_status|$_kind';

  /// Siteleri ve görünen listeyi yeniden çeker (mevcut liste yenileme sürerken ekranda kalır).
  Future<void> reload() async {
    if (!mounted) return;
    final token = ++_sitesToken;
    setState(() {
      _loadingSites = true;
      _sitesError = null;
    });
    try {
      final merged = <VisitorSite>[];
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
              merged.add(VisitorSite(code: site.id, name: site.name));
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
      });
      final current = _site;
      if (siteChanged ||
          (previous != null &&
              current != null &&
              previous.access != current.access)) {
        _resetList();
      } else if (current != null) {
        unawaited(_loader.reload());
      }
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

  String _siteLabel(VisitorSite site) {
    final same = _sites.where((s) => s.label == site.label).toList();
    if (same.length < 2) return site.label;
    return '${site.label} (${same.indexOf(site) + 1})';
  }

  void _selectSite(int code) {
    if (code == _siteCode) return;
    setState(() {
      _siteCode = code;
      _moduleOff = false;
    });
    _resetList();
  }

  Future<void> _create(VisitorSite site) async {
    final entry = await VisitorEntryFormDialog.show(
      context,
      service: _service,
      scope: PeopleScope(
        authService: widget.authService,
        siteCode: site.code,
        siteName: site.name,
        canWrite: true,
      ),
    );
    if (entry == null || !mounted) return;
    AppSnack.show(
      context,
      entry.kind == VisitorKind.cargo
          ? 'Kargo kaydı açıldı (Bekliyor).'
          : 'Ziyaretçi kaydı açıldı (İçeride).',
      kind: AppSnackKind.success,
    );
    // Yeni kayıt kendi durum sekmesinde görünür: sekme ona geçer (zaten oradaysa yalnız yenilenir).
    final target = entry.status.isOpen ? entry.status.apiValue : '';
    if (_status != target && _status.isNotEmpty) {
      _setFilter(() => _status = target);
    } else {
      unawaited(_loader.reload());
    }
  }

  Future<void> _action(VisitorEntry entry, VisitorStatus next) async {
    if (_busy.contains(entry.id)) return;
    final site = _siteCode;
    if (site == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AppDialog(
        title: switch (next) {
          VisitorStatus.teslimEdildi => 'Teslim edildi olarak işaretle',
          VisitorStatus.ayrildi => 'Ayrıldı olarak işaretle',
          VisitorStatus.iptal => 'Kayıt iptal edilsin mi?',
          _ => 'Durumu değiştir',
        },
        icon: visitorStatusIcon(next),
        tone: next == VisitorStatus.iptal ? AppTone.danger : AppTone.primary,
        actions: [
          TextButton(
            key: const ValueKey<String>('visitor_confirm_keep'),
            onPressed: () => popIfCurrent(dialogContext, false),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            key: const ValueKey<String>('visitor_confirm_ok'),
            onPressed: () => popIfCurrent(dialogContext, true),
            child: Text(next.actionLabel),
          ),
        ],
        child: Text(
          '${entry.kind.label}: ${entry.displayName} (${entry.placeText}). '
          'Kayıt "${next.label}" olarak kapanacak; bu işlem geri alınamaz.',
          style: Theme.of(dialogContext).textTheme.bodyMedium,
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy.add(entry.id));
    try {
      final updated = await _service.update(site, entry.id, status: next);
      if (!mounted) return;
      _replace(updated);
      AppSnack.show(
        context,
        'Kayıt "${updated.status.label}" olarak güncellendi.',
        kind: AppSnackKind.success,
      );
    } catch (e) {
      if (!mounted) return;
      AppSnack.show(
        context,
        crmMessageOf(e, 'Kayıt güncellenemedi. Lütfen tekrar deneyin.'),
        kind: AppSnackKind.error,
      );
      if (e is ApiException && (e.statusCode == 409 || e.statusCode == 404)) {
        // Başkası kapatmış olabilir: liste sunucudan tazelenir.
        unawaited(_loader.reload());
      }
    } finally {
      if (mounted) setState(() => _busy.remove(entry.id));
    }
  }

  /// Güncellenen kayıt listede yerine konur; sekmeye artık uymuyorsa (kapandı) listeden düşer.
  void _replace(VisitorEntry updated) {
    final fits = _status.isEmpty || updated.status.apiValue == _status;
    setState(() {
      _loader.items = <VisitorEntry>[
        for (final item in _loader.items)
          if (item.id != updated.id)
            item
          else if (fits)
            updated,
      ];
      if (!fits && _loader.total > 0) _loader.total -= 1;
    });
  }

  bool get _filtered => _query.isNotEmpty || _kind.isNotEmpty;

  String get _emptyTitle => switch (_status) {
    'bekliyor' => 'Bekleyen kargo yok.',
    'iceride' => 'İçeride ziyaretçi yok.',
    _ => 'Henüz kayıt yok.',
  };

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
            'Ziyaretçi ve kargo kayıtları, modülü açık bir siteye bağlı olduğunuzda burada görünür.',
      );
    }
    return _buildSite(context, site);
  }

  Widget _buildSite(BuildContext context, VisitorSite site) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final canWrite = widget.manageAllSites || site.canWrite;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeaderCard(
          title: 'Ziyaretçi ve Kargo',
          icon: Icons.door_front_door_rounded,
          action: canWrite && !_moduleOff
              ? ElevatedButton.icon(
                  key: const ValueKey<String>('visitor_new_entry'),
                  onPressed: () => unawaited(_create(site)),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Yeni Kayıt'),
                )
              : null,
        ),
        const SizedBox(height: AppSpace.sm),
        Text(
          switch (site.access) {
            VisitorSiteAccess.staff =>
              'Gelen kargoyu ve ziyaretçiyi kaydedin; teslim ya da çıkışta kapatın. Sakin uygulama içinde görür.',
            VisitorSiteAccess.board =>
              'Sitedeki ziyaretçi ve kargo kayıtlarını izleyin.',
            VisitorSiteAccess.manager =>
              'Kapıdan giren kargo ve ziyaretçileri kaydedin; sakin uygulama içinde bildirim görür.',
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
              key: ValueKey<String>('visitor_site_${site.code}_${_sites.length}'),
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
          const InlineNotice(
            key: ValueKey<String>('visitor_read_only_note'),
            tone: AppTone.info,
            icon: Icons.visibility_rounded,
            message:
                'Yönetim kurulu üyesi olarak kayıtları yalnızca görüntüleyebilirsiniz.',
          ),
          const SizedBox(height: AppSpace.md),
        ],
        if (_moduleOff)
          _buildModuleOff(context)
        else ...[
          _buildFilters(context),
          const SizedBox(height: AppSpace.md),
          SectionHeader(
            title: 'Kayıtlar',
            trailing: IconButton(
              onPressed: _loader.loading ? null : reload,
              tooltip: 'Yenile',
              icon: const Icon(Icons.refresh_rounded),
            ),
          ),
          const SizedBox(height: AppSpace.md),
          CrmListBody<VisitorEntry>(
            loader: _loader,
            emptyIcon: Icons.door_front_door_outlined,
            emptyTitle: _emptyTitle,
            filtered: _filtered,
            filteredTitle: 'Bu süzgeç için kayıt bulunamadı.',
            emptyMessage: _filtered
                ? null
                : (canWrite
                      ? 'Kapıya kargo ya da ziyaretçi geldiğinde "Yeni Kayıt" ile ekleyin.'
                      : 'Görevli bir kayıt açtığında burada görünür.'),
            itemBuilder: (context, item) => VisitorManagedCard(
              key: ValueKey<String>('visitor_card_${item.id}'),
              entry: item,
              canWrite: canWrite,
              busy: _busy.contains(item.id),
              onAction: (next) => unawaited(_action(item, next)),
            ),
          ),
        ],
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
            key: const ValueKey<String>('visitor_search'),
            controller: _search,
            textInputAction: TextInputAction.search,
            onChanged: _onSearchChanged,
            onSubmitted: (_) => _applyFilters(),
            decoration: InputDecoration(
              labelText: 'Kayıt ara',
              hintText: 'Ad, firma veya daire',
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
              for (final entry in const <(String, String)>[
                ('bekliyor', 'Bekleyen'),
                ('iceride', 'İçeride'),
                ('', 'Tümü'),
              ])
                ChoiceChip(
                  key: ValueKey<String>(
                    'visitor_status_${entry.$1.isEmpty ? 'all' : entry.$1}',
                  ),
                  label: Text(entry.$2),
                  selected: _status == entry.$1,
                  onSelected: (_) => _setFilter(() => _status = entry.$1),
                ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          Text('Tür', style: th.titleSmall),
          const SizedBox(height: AppSpace.sm),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: [
              ChoiceChip(
                key: const ValueKey<String>('visitor_kind_all'),
                label: const Text('Hepsi'),
                selected: _kind.isEmpty,
                onSelected: (_) => _setFilter(() => _kind = ''),
              ),
              for (final kind in VisitorKind.values)
                ChoiceChip(
                  key: ValueKey<String>('visitor_kind_${kind.apiValue}'),
                  avatar: Icon(visitorKindIcon(kind), size: 18),
                  label: Text(kind.label),
                  selected: _kind == kind.apiValue,
                  onSelected: (_) => _setFilter(() => _kind = kind.apiValue),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildModuleOff(BuildContext context) {
    final th = Theme.of(context).textTheme;
    return EmptyCard(
      key: const ValueKey<String>('visitor_module_off'),
      icon: Icons.door_front_door_outlined,
      tone: AppTone.warning,
      title: 'Ziyaretçi ve kargo kaydı bu site için kapalı.',
      message:
          'Modül açılınca kapıdan giren kargo ve ziyaretçiler burada kaydedilir.',
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
                  key: const ValueKey<String>('visitor_open_modules'),
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
