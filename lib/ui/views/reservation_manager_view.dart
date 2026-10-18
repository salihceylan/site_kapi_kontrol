import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/reservation_models.dart';
import 'package:site_kapi_kontrol/models/vehicle_record.dart' show crmDateParam;
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/reservation_api.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/reservation_decision_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/cursor_loader.dart';
import 'package:site_kapi_kontrol/ui/helpers/date_input.dart' show formatDateField;
import 'package:site_kapi_kontrol/ui/helpers/istanbul_time.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart'
    show crmMessageOf;
import 'package:site_kapi_kontrol/ui/views/concierge_manager_tab.dart';
import 'package:site_kapi_kontrol/ui/views/reservation_areas_tab.dart';
import 'package:site_kapi_kontrol/ui/widgets/cursor_list_body.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/reservation_parts.dart';

/// Yönetim "Rezervasyonlar" ekranı (`reservation` modülü): yönetici / süper kullanıcı (alan tanımlar, karar verir),
/// görevli (karar verir, konsiyerj ilerletir; alan tanımlayamaz) ve yönetim kurulu (SALT OKUR).
///
/// - [manageAllSites] true (süper kullanıcı): tüm onaylı siteler listelenir ve yönetici yetkisi vardır.
/// - [sites]: `GET /app/my-modules` ile `reservation` modülü AÇIK siteler (erişim türüyle). Menü kapısı ve site
///   listesi HomePage'dedir; sunucu yine de her çağrıda yetkiyi ve modül durumunu doğrular.
/// - Kurul ([ReservationSiteAccess.board]): hiçbir yazma düğmesi çizilmez, "yalnızca görüntüleyebilirsiniz" notu gösterilir;
///   sakin telefonu / kullanıcı kodu sunucudan zaten gelmez.
///
/// Sekmeler: Rezervasyonlar (takvim listesi + onay / ret / iptal), Konsiyerj, Alanlar. Site değişince sekmeler yeni
/// siteyle baştan yüklenir (eski sitenin yanıtı yeni sitenin ekranına yazılamaz). HATA ASLA "kayıt yok" demez; modül
/// kapalıysa (403 `MODULE_DISABLED`) açıklayıcı kart çıkar. [ReservationManagerViewState.reload] sayfa kabuğunun aşağı
/// çekip yenilemesinden çağrılır.
class ReservationManagerView extends StatefulWidget {
  const ReservationManagerView({
    super.key,
    required this.authService,
    this.service,
    this.manageAllSites = false,
    this.sites = const <ReservationSite>[],
    this.onOpenModules,
  });

  final AuthService authService;
  final ReservationService? service;
  final bool manageAllSites;
  final List<ReservationSite> sites;
  final VoidCallback? onOpenModules;

  @override
  State<ReservationManagerView> createState() => ReservationManagerViewState();
}

class ReservationManagerViewState extends State<ReservationManagerView> {
  List<ReservationSite> _sites = const <ReservationSite>[];
  int? _siteCode;
  bool _loadingSites = false;
  bool _sitesLoadedOnce = false;
  String? _sitesError;
  int _sitesToken = 0;
  int _tab = 0;

  final GlobalKey _calendarKey = GlobalKey();
  final GlobalKey _conciergeKey = GlobalKey();
  final GlobalKey _areasKey = GlobalKey();

  late ReservationService _service =
      widget.service ?? ReservationService(authService: widget.authService);

  @override
  void initState() {
    super.initState();
    unawaited(_loadSites());
  }

  @override
  void didUpdateWidget(ReservationManagerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.service, widget.service) ||
        !identical(oldWidget.authService, widget.authService)) {
      _service =
          widget.service ?? ReservationService(authService: widget.authService);
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

  ReservationSite? get _site {
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
      final merged = <ReservationSite>[];
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
              merged.add(ReservationSite(code: site.id, name: site.name));
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

  /// Siteleri ve etkin sekmenin listesini yeniden çeker.
  Future<void> reload() async {
    await _loadSites();
    final key = switch (_tab) {
      0 => _calendarKey,
      1 => _conciergeKey,
      _ => _areasKey,
    };
    final state = key.currentState;
    if (state is ReservationReloadable) {
      await (state as ReservationReloadable).reload();
    }
  }

  String _siteLabel(ReservationSite site) {
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
            'Rezervasyonlar, Rezervasyon ve Konsiyerj modülü açık bir siteye bağlı olduğunuzda burada görünür.',
      );
    }
    return _buildSite(context, site);
  }

  Widget _buildSite(BuildContext context, ReservationSite site) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageHeaderCard(title: 'Rezervasyonlar', icon: Icons.event_note_rounded),
        const SizedBox(height: AppSpace.sm),
        Text(
          switch (site.access) {
            ReservationSiteAccess.staff =>
              'Sakinlerin rezervasyonlarını onaylar, reddeder ya da iptal eder; konsiyerj taleplerini ilerletirsiniz.',
            ReservationSiteAccess.board =>
              'Sitedeki ortak alan rezervasyonlarını ve konsiyerj taleplerini izleyin.',
            ReservationSiteAccess.manager =>
              'Ortak alanları tanımlayın, rezervasyonları onaylayın ve konsiyerj taleplerini yönetin.',
          },
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
              key: ValueKey<String>('rezm_site_${site.code}_${_sites.length}'),
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
        if (site.access == ReservationSiteAccess.board) ...[
          const ReservationReadOnlyNote(),
          const SizedBox(height: AppSpace.md),
        ],
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          children: [
            for (final entry in const <(int, String, String)>[
              (0, 'rezm_tab_calendar', 'Rezervasyonlar'),
              (1, 'rezm_tab_concierge', 'Konsiyerj'),
              (2, 'rezm_tab_areas', 'Alanlar'),
            ])
              ChoiceChip(
                key: ValueKey<String>(entry.$2),
                label: Text(entry.$3),
                selected: _tab == entry.$1,
                onSelected: (_) => _selectTab(entry.$1),
              ),
          ],
        ),
        const SizedBox(height: AppSpace.lg),
        switch (_tab) {
          0 => ReservationCalendarTab(
            key: _calendarKey,
            service: _service,
            site: site,
            onOpenModules: widget.onOpenModules,
          ),
          1 => ConciergeManagerTab(
            key: _conciergeKey,
            service: _service,
            site: site,
            onOpenModules: widget.onOpenModules,
          ),
          _ => ReservationAreasTab(
            key: _areasKey,
            service: _service,
            site: site,
            onOpenModules: widget.onOpenModules,
          ),
        },
      ],
    );
  }
}

/// "Rezervasyonlar" sekmesi: sitenin rezervasyon takvimi (başlangıç artan), alan / durum / tarih süzgeci ve onay,
/// ret, iptal. Kurul ([ReservationSite.canWrite] false) hiçbir düğme görmez.
class ReservationCalendarTab extends StatefulWidget {
  const ReservationCalendarTab({
    super.key,
    required this.service,
    required this.site,
    this.onOpenModules,
  });

  final ReservationService service;
  final ReservationSite site;
  final VoidCallback? onOpenModules;

  @override
  State<ReservationCalendarTab> createState() => ReservationCalendarTabState();
}

class ReservationCalendarTabState extends State<ReservationCalendarTab>
    implements ReservationReloadable {
  static const List<(String, String)> _statusChips = <(String, String)>[
    ('all', 'Tümü'),
    ('beklemede', 'Onay bekleyen'),
    ('onaylandi', 'Onaylı'),
    ('reddedildi', 'Reddedilen'),
    ('iptal', 'İptal'),
    ('tamamlandi', 'Tamamlanan'),
  ];

  String _status = 'all';
  int? _areaId;
  DateTime? _from;
  DateTime? _to;
  int _pending = 0;
  bool _moduleOff = false;
  List<ReservationArea> _areas = const <ReservationArea>[];
  int _areasToken = 0;

  // Sunucu imleci opaktır (metin); [CursorLoader] sayısal imleç taşıdığı için sıra numarası -> imleç tablosu tutulur.
  final Map<int, String> _cursors = <int, String>{};
  int _cursorSeq = 0;

  late final CursorLoader<ReservationRecord> _loader = CursorLoader<ReservationRecord>(
    fetch: (before) async {
      final cursor = before == null ? null : _cursors[before];
      final from = _from;
      final to = _to;
      final page = await widget.service.listManaged(
        widget.site.code,
        areaId: _areaId,
        status: _status == 'all' ? null : _status,
        from: from == null ? null : crmDateParam(from),
        to: to == null ? null : crmDateParam(to),
        cursor: cursor,
        limit: 30,
      );
      if (before == null) {
        _pending = page.pendingCount;
        _moduleOff = false;
        _cursors.clear();
        _cursorSeq = 0;
      }
      int? next;
      final nextCursor = page.nextCursor;
      if (nextCursor != null) {
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
        'Rezervasyonlar yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
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
    unawaited(_loadAreas());
  }

  @override
  void didUpdateWidget(ReservationCalendarTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.site != widget.site ||
        !identical(oldWidget.service, widget.service)) {
      _areaId = null;
      _areas = const <ReservationArea>[];
      _pending = 0;
      _moduleOff = false;
      _resetList();
      unawaited(_loadAreas());
    }
  }

  @override
  void dispose() {
    ++_areasToken;
    _loader.dispose();
    super.dispose();
  }

  @override
  Future<void> reload() => _loader.reload();

  /// Alan süzgeci seçenekleri; alınamazsa süzgeç yalnız "Tüm alanlar" kalır (liste yine çalışır).
  Future<void> _loadAreas() async {
    final token = ++_areasToken;
    try {
      final list = await widget.service.listManagedAreas(widget.site.code);
      if (!mounted || token != _areasToken) return;
      setState(() => _areas = list.items);
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

  DateTime _today() {
    final wall = istanbulNow();
    return DateTime(wall.year, wall.month, wall.day);
  }

  Future<void> _pickDate({required bool from}) async {
    final today = _today();
    final picked = await showDatePicker(
      context: context,
      initialDate: (from ? _from : _to) ?? today,
      firstDate: today.subtract(const Duration(days: 365)),
      lastDate: today.add(const Duration(days: 365)),
      helpText: from ? 'Başlangıç günü' : 'Bitiş günü',
    );
    if (picked == null || !mounted) return;
    final day = DateTime(picked.year, picked.month, picked.day);
    if (from) {
      final to = _to;
      if (to != null && day.isAfter(to)) {
        AppSnack.show(context, 'Başlangıç günü bitiş gününden sonra olamaz.', kind: AppSnackKind.warning);
        return;
      }
      _setFilter(() => _from = day);
    } else {
      final start = _from ?? today;
      if (day.isBefore(start)) {
        AppSnack.show(context, 'Bitiş günü başlangıç gününden önce olamaz.', kind: AppSnackKind.warning);
        return;
      }
      _setFilter(() => _to = day);
    }
  }

  Future<void> _decide(ReservationRecord record, String action) async {
    final result = await ReservationDecisionDialog.show(
      context,
      service: widget.service,
      siteCode: widget.site.code,
      reservation: record,
      action: action,
    );
    if (!mounted) return;
    if (result != null) {
      AppSnack.show(
        context,
        !result.changed
            ? 'Bu karar zaten verilmişti.'
            : switch (action) {
                'approve' => 'Rezervasyon onaylandı.',
                'reject' => 'Rezervasyon reddedildi.',
                _ => 'Rezervasyon iptal edildi.',
              },
        kind: result.changed ? AppSnackKind.success : AppSnackKind.info,
      );
    }
    // Karar verilse de verilmese de (başkasınca değişmiş olabilir) liste sunucuyla eşitlenir.
    unawaited(_loader.reload());
  }

  bool get _filtered =>
      _status != 'all' || _areaId != null || _from != null || _to != null;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    if (_moduleOff) {
      return ReservationModuleOffCard(
        message: 'Modül açılınca sakinlerin rezervasyonları burada görünür.',
        onOpenModules: widget.onOpenModules,
      );
    }
    final from = _from;
    final to = _to;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Durum', style: th.titleSmall),
              const SizedBox(height: AppSpace.sm),
              Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.sm,
                children: [
                  for (final entry in _statusChips)
                    ChoiceChip(
                      key: ValueKey<String>('rezm_status_${entry.$1}'),
                      label: Text(
                        entry.$1 == 'beklemede' && _loader.loadedOnce
                            ? '${entry.$2} ($_pending)'
                            : entry.$2,
                      ),
                      selected: _status == entry.$1,
                      onSelected: (_) => _setFilter(() => _status = entry.$1),
                    ),
                ],
              ),
              const SizedBox(height: AppSpace.md),
              DropdownButtonFormField<int>(
                key: ValueKey<String>('rezm_area_filter_${_areaId ?? 0}_${_areas.length}'),
                isExpanded: true,
                initialValue: _areaId ?? 0,
                dropdownColor: p.surface,
                style: th.bodyMedium?.copyWith(color: p.text),
                decoration: const InputDecoration(
                  labelText: 'Alan',
                  prefixIcon: Icon(Icons.meeting_room_rounded),
                ),
                items: [
                  const DropdownMenuItem<int>(
                    value: 0,
                    child: Text('Tüm alanlar', maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  for (final area in _areas)
                    DropdownMenuItem<int>(
                      value: area.id,
                      child: Text(area.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (value) {
                  final next = (value == null || value == 0) ? null : value;
                  if (next == _areaId) return;
                  _setFilter(() => _areaId = next);
                },
              ),
              const SizedBox(height: AppSpace.md),
              Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.sm,
                children: [
                  OutlinedButton.icon(
                    key: const ValueKey<String>('rezm_from'),
                    onPressed: () => unawaited(_pickDate(from: true)),
                    icon: const Icon(Icons.event_rounded, size: 18),
                    label: Text(
                      from == null ? 'Bugünden itibaren' : 'Başlangıç: ${formatDateField(from)}',
                    ),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey<String>('rezm_to'),
                    onPressed: () => unawaited(_pickDate(from: false)),
                    icon: const Icon(Icons.event_available_rounded, size: 18),
                    label: Text(to == null ? 'Bitiş: sınırsız' : 'Bitiş: ${formatDateField(to)}'),
                  ),
                  if (from != null || to != null)
                    TextButton(
                      key: const ValueKey<String>('rezm_dates_reset'),
                      onPressed: () => _setFilter(() {
                        _from = null;
                        _to = null;
                      }),
                      child: const Text('Tarihleri sıfırla'),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.md),
        SectionHeader(
          title: 'Rezervasyonlar',
          trailing: IconButton(
            onPressed: _loader.loading ? null : reload,
            tooltip: 'Yenile',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        CursorListBody<ReservationRecord>(
          loader: _loader,
          emptyIcon: Icons.event_busy_rounded,
          emptyTitle: _filtered
              ? 'Bu süzgeç için rezervasyon bulunamadı.'
              : 'Yaklaşan rezervasyon yok.',
          emptyMessage: _filtered
              ? null
              : 'Sakinler bir ortak alan ayırttığında burada görünür.',
          itemBuilder: (context, record) => ManagedReservationCard(
            record: record,
            onDecide: widget.site.canWrite
                ? (action) => unawaited(_decide(record, action))
                : null,
          ),
        ),
      ],
    );
  }
}
