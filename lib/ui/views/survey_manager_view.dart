import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/ui/helpers/list_export.dart';
import 'package:site_kapi_kontrol/models/survey_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/survey_api.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/crm_confirm_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/survey_form_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/istanbul_time.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart' show crmMessageOf;
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/survey_parts.dart';

/// Yönetim "Anket ve Oylama" ekranı (`survey` modülü): yönetici / süper kullanıcı (anket açar, yayınlar, kapatır,
/// taslağı siler, anonim olmayan ankette oy verenleri görür) ve yönetim kurulu (SALT OKUR; oy verenleri göremez).
///
/// - [manageAllSites] true (süper kullanıcı): tüm onaylı siteler listelenir ve yönetici yetkisi vardır.
/// - [sites]: `GET /app/my-modules` ile `survey` modülü AÇIK siteler (erişim türüyle).
/// - HATA ASLA "anket yok" demez; modül kapalıysa (403 `MODULE_DISABLED`) açıklayıcı kart çıkar.
/// - [SurveyManagerViewState.reload] sayfa kabuğunun aşağı çekip yenilemesinden çağrılır.
class SurveyManagerView extends StatefulWidget {
  const SurveyManagerView({
    super.key,
    required this.authService,
    this.service,
    this.manageAllSites = false,
    this.sites = const <SurveySite>[],
    this.onOpenModules,
  });

  final AuthService authService;
  final SurveyService? service;
  final bool manageAllSites;
  final List<SurveySite> sites;
  final VoidCallback? onOpenModules;

  @override
  State<SurveyManagerView> createState() => SurveyManagerViewState();
}

class SurveyManagerViewState extends State<SurveyManagerView> {
  static const List<(String, String)> _statusChips = <(String, String)>[
    ('all', 'Tümü'),
    ('draft', 'Taslak'),
    ('open', 'Açık'),
    ('closed', 'Kapalı'),
  ];
  static const int _pageSize = 30;

  List<SurveySite> _sites = const <SurveySite>[];
  int? _siteCode;
  bool _loadingSites = false;
  bool _sitesLoadedOnce = false;
  String? _sitesError;
  int _sitesToken = 0;

  String _status = 'all';
  List<SurveySummary> _items = const <SurveySummary>[];
  int _total = 0;
  bool _loading = false;
  bool _loadedOnce = false;
  bool _loadingMore = false;
  String? _error;
  bool _moduleOff = false;
  int _listToken = 0;

  late SurveyService _service = widget.service ?? SurveyService(authService: widget.authService);

  @override
  void initState() {
    super.initState();
    unawaited(_loadSites());
  }

  @override
  void didUpdateWidget(SurveyManagerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.service, widget.service) || !identical(oldWidget.authService, widget.authService)) {
      _service = widget.service ?? SurveyService(authService: widget.authService);
    }
    if (oldWidget.manageAllSites != widget.manageAllSites || !listEquals(oldWidget.sites, widget.sites)) {
      unawaited(_loadSites());
    }
  }

  @override
  void dispose() {
    ++_sitesToken;
    ++_listToken;
    super.dispose();
  }

  String _localQuery = '';

  bool _matchesQuery(SurveySummary i) =>
      _localQuery.isEmpty || i.title.toLowerCase().contains(_localQuery);

  SurveySite? get _site {
    final code = _siteCode;
    if (code == null) return null;
    for (final site in _sites) {
      if (site.code == code) return site;
    }
    return null;
  }

  Future<void> _loadSites() async {
    if (!mounted) return;
    final token = ++_sitesToken;
    setState(() {
      _loadingSites = true;
      _sitesError = null;
    });
    try {
      final merged = <SurveySite>[];
      if (widget.manageAllSites) {
        var pageNo = 1;
        var fetched = 0;
        while (true) {
          final page = await widget.authService.listSites(page: pageNo, pageSize: 100, approvalStatus: 'approved');
          for (final site in page.sites) {
            if (site.isApproved && !merged.any((m) => m.code == site.id)) {
              merged.add(SurveySite(code: site.id, name: site.name));
            }
          }
          fetched += page.sites.length;
          if (page.sites.isEmpty || fetched >= page.total || pageNo >= 50) break;
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
      final changed = next != _siteCode;
      setState(() {
        _sites = merged;
        _loadingSites = false;
        _sitesLoadedOnce = true;
        _siteCode = next;
      });
      if (next != null && (changed || !_loadedOnce)) _resetList();
    } catch (e) {
      if (!mounted || token != _sitesToken) return;
      setState(() {
        _loadingSites = false;
        _sitesError = crmMessageOf(e, 'Siteler yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.');
      });
    }
  }

  /// Siteleri ve listeyi yeniden çeker.
  Future<void> reload() async {
    await _loadSites();
    if (_siteCode != null) await _load();
  }

  void _resetList() {
    _items = const <SurveySummary>[];
    _total = 0;
    _loadedOnce = false;
    _error = null;
    _moduleOff = false;
    unawaited(_load());
  }

  Future<void> _load({bool more = false}) async {
    final code = _siteCode;
    if (code == null || !mounted) return;
    final token = ++_listToken;
    setState(() {
      if (more) {
        _loadingMore = true;
      } else {
        _loading = true;
        _error = null;
      }
    });
    try {
      final page = await _service.listManaged(code, status: _status, limit: _pageSize, offset: more ? _items.length : 0);
      if (!mounted || token != _listToken) return;
      setState(() {
        _moduleOff = false;
        _loadedOnce = true;
        _total = page.total;
        if (more) {
          final known = <int>{for (final i in _items) i.id};
          _items = <SurveySummary>[..._items, for (final i in page.items) if (!known.contains(i.id)) i];
        } else {
          _items = page.items;
        }
        _loading = false;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted || token != _listToken) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        if (e is ApiException && e.code == 'MODULE_DISABLED') _moduleOff = true;
        _error = crmMessageOf(e, 'Anketler yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.');
      });
    }
  }

  void _selectSite(int code) {
    if (code == _siteCode) return;
    setState(() => _siteCode = code);
    _resetList();
  }

  void _selectStatus(String status) {
    if (status == _status) return;
    setState(() => _status = status);
    _resetList();
  }

  String _siteLabel(SurveySite site) {
    final same = _sites.where((s) => s.label == site.label).toList();
    if (same.length < 2) return site.label;
    return '${site.label} (${same.indexOf(site) + 1})';
  }

  Future<void> _create(SurveySite site) async {
    final created = await SurveyFormDialog.show(
      context,
      service: _service,
      scope: PeopleScope(authService: widget.authService, siteCode: site.code, siteName: site.name, canWrite: true),
    );
    if (created == null || !mounted) return;
    AppSnack.show(
      context,
      created.summary.isOpen ? 'Anket yayınlandı.' : 'Anket taslak olarak kaydedildi.',
      kind: AppSnackKind.success,
    );
    _resetList();
  }

  Future<void> _openDetail(SurveySite site, SurveySummary item) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => SurveyDetailDialog(service: _service, site: site, summary: item),
    );
    if (changed == true && mounted) _resetList();
  }

  @override
  Widget build(BuildContext context) {
    final site = _site;
    if (site == null) {
      if (_loadingSites || (!_sitesLoadedOnce && _sitesError == null)) return const ListSkeleton(rows: 2);
      if (_sitesError != null) return InlineNotice(message: _sitesError!, onRetry: _loadSites);
      return const EmptyCard(
        icon: Icons.apartment_rounded,
        title: 'Kayıtlı site bulunamadı.',
        message: 'Anketler, Anket ve Oylama modülü açık bir siteye bağlı olduğunuzda burada görünür.',
      );
    }
    return _buildSite(context, site);
  }

  Widget _buildSite(BuildContext context, SurveySite site) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final error = _error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageHeaderCard(title: 'Anket ve Oylama', icon: Icons.poll_rounded),
        const SizedBox(height: AppSpace.sm),
        Text(
          site.canWrite
              ? 'Sakinlere anket açın, yayınlayın ve sonuçları izleyin.'
              : 'Sitedeki anketleri ve sonuçlarını izleyin.',
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
              key: ValueKey<String>('svm_site_${site.code}_${_sites.length}'),
              isExpanded: true,
              initialValue: site.code,
              dropdownColor: p.surface,
              style: th.bodyMedium?.copyWith(color: p.text),
              decoration: const InputDecoration(labelText: 'Site', prefixIcon: Icon(Icons.apartment_rounded)),
              items: [
                for (final s in _sites)
                  DropdownMenuItem<int>(
                    value: s.code,
                    child: Text(_siteLabel(s), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (value) {
                if (value != null) _selectSite(value);
              },
            ),
          )
        else
          Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.xs, children: [InfoChip(site.label)]),
        const SizedBox(height: AppSpace.md),
        if (!site.canWrite) ...[const SurveyReadOnlyNote(), const SizedBox(height: AppSpace.md)],
        if (_moduleOff)
          SurveyModuleOffCard(
            message: 'Modül açılınca anketler burada görünür.',
            onOpenModules: widget.onOpenModules,
          )
        else ...[
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  key: const ValueKey<String>('svm_search'),
                  onChanged: (v) => setState(() => _localQuery = v.trim().toLowerCase()),
                  decoration: const InputDecoration(labelText: 'Anket ara', prefixIcon: Icon(Icons.search_rounded)),
                ),
                const SizedBox(height: AppSpace.md),
                Text('Durum', style: th.titleSmall),
                const SizedBox(height: AppSpace.sm),
                Wrap(
                  spacing: AppSpace.sm,
                  runSpacing: AppSpace.sm,
                  children: [
                    for (final entry in _statusChips)
                      ChoiceChip(
                        key: ValueKey<String>('svm_status_${entry.$1}'),
                        label: Text(entry.$2),
                        selected: _status == entry.$1,
                        onSelected: (_) => _selectStatus(entry.$1),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.md),
          if (site.canWrite) ...[
            PrimaryActionButton(
              key: const ValueKey<String>('svm_new'),
              label: 'Yeni Anket',
              icon: Icons.add_rounded,
              onPressed: () => unawaited(_create(site)),
            ),
            const SizedBox(height: AppSpace.md),
          ],
          SectionHeader(
            title: _loadedOnce ? 'Anketler ($_total)' : 'Anketler',
            trailing: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[ListExportButton(enabled: _items.isNotEmpty, source: localExportSource(label: 'Anket sonuçları', filenameBase: 'anket_sonuclari', headers: <String>['Anket', 'Durum', 'Verilen oy', 'Oy hakkı olan', 'Açılış', 'Kapanış', 'Oluşturan'], rows: () => <List<Object?>>[for (final s in _items) [s.title, s.effectiveStatus.label, s.totalVotes, s.eligibleCount, exportDate(s.openedAt), exportDate(s.closedAt ?? s.closesAt), s.createdByName]])), IconButton(
              onPressed: _loading ? null : () => unawaited(_load()),
              tooltip: 'Yenile',
              icon: const Icon(Icons.refresh_rounded),
            )]),
          ),
          const SizedBox(height: AppSpace.md),
          if (_loading && !_loadedOnce)
            const ListSkeleton(rows: 2)
          else if (error != null && _items.isEmpty)
            EmptyCard(
              key: const ValueKey<String>('svm_error'),
              icon: Icons.cloud_off_rounded,
              tone: AppTone.danger,
              title: error,
              child: TextButton.icon(
                onPressed: _loading ? null : () => unawaited(_load()),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Tekrar Dene'),
              ),
            )
          else if (_items.isEmpty)
            EmptyCard(
              key: const ValueKey<String>('svm_empty'),
              icon: Icons.poll_outlined,
              title: _status == 'all' ? 'Henüz anket yok.' : 'Bu durumda anket yok.',
              message: site.canWrite && _status == 'all' ? '"Yeni Anket" ile ilk anketinizi açın.' : null,
            )
          else ...[
            if (error != null) ...[InlineNotice(message: error, tone: AppTone.danger), const SizedBox(height: AppSpace.md)],
            for (final item in _items.where(_matchesQuery)) ...[
              SurveyManagedCard(
                key: ValueKey<String>('svm_card_${item.id}'),
                item: item,
                onTap: () => unawaited(_openDetail(site, item)),
              ),
              const SizedBox(height: AppSpace.md),
            ],
            if (_items.length < _total)
              TextButton.icon(
                key: const ValueKey<String>('svm_more'),
                onPressed: _loadingMore ? null : () => unawaited(_load(more: true)),
                icon: const Icon(Icons.expand_more_rounded),
                label: const Text('Daha fazla'),
              ),
          ],
        ],
      ],
    );
  }
}

/// Anket ayrıntısı: soru, seçenekler ve sonuç çubukları (tamsayı yüzde), hedef, anonim değilse "Oy verenler",
/// eylemler (Yayınla / Kapat / Sil, onaylı). Değişiklik olduysa `true` ile kapanır.
class SurveyDetailDialog extends StatefulWidget {
  const SurveyDetailDialog({super.key, required this.service, required this.site, required this.summary});

  final SurveyService service;
  final SurveySite site;
  final SurveySummary summary;

  @override
  State<SurveyDetailDialog> createState() => _SurveyDetailDialogState();
}

class _SurveyDetailDialogState extends State<SurveyDetailDialog> {
  SurveyDetail? _detail;
  String? _error;
  bool _loading = true;
  bool _busy = false;
  bool _changed = false;
  List<SurveyVoter>? _voters;
  int _votersTotal = 0;
  bool _votersLoading = false;
  String? _votersError;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await widget.service.getManaged(widget.site.code, widget.summary.id);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = crmMessageOf(e, 'Anket yüklenemedi. Lütfen tekrar deneyin.');
      });
    }
  }

  Future<void> _loadVoters() async {
    setState(() {
      _votersLoading = true;
      _votersError = null;
    });
    try {
      final page = await widget.service.voters(widget.site.code, widget.summary.id, limit: 100);
      if (!mounted) return;
      setState(() {
        _voters = page.items;
        _votersTotal = page.total;
        _votersLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _votersLoading = false;
        _votersError = crmMessageOf(e, 'Oy verenler yüklenemedi. Lütfen tekrar deneyin.');
      });
    }
  }

  Future<void> _act(String action) async {
    final detail = _detail;
    if (detail == null || _busy) return;
    final (title, message, label, icon, tone) = switch (action) {
      'open' => (
        'Anketi yayınla',
        'Anket hedef kitleye açılır ve oy verilebilir. Yayınlanan anketin sorusu ve seçenekleri değiştirilemez.',
        'Yayınla',
        Icons.send_rounded,
        AppTone.primary,
      ),
      'close' => (
        'Anketi kapat',
        'Oylama sona erer; kapanan anket yeniden açılamaz.',
        'Kapat',
        Icons.lock_outline_rounded,
        AppTone.warning,
      ),
      _ => ('Taslağı sil', 'Bu taslak kalıcı olarak silinir.', 'Sil', Icons.delete_outline_rounded, AppTone.danger),
    };
    final ok = await confirmCrmAction(context, title: title, message: message, confirmLabel: label, icon: icon, tone: tone);
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      switch (action) {
        case 'open':
          final updated = await widget.service.open(widget.site.code, detail.id);
          if (!mounted) return;
          setState(() => _detail = updated);
          AppSnack.show(context, 'Anket yayınlandı.', kind: AppSnackKind.success);
        case 'close':
          final updated = await widget.service.close(widget.site.code, detail.id);
          if (!mounted) return;
          setState(() => _detail = updated);
          AppSnack.show(context, 'Anket kapatıldı.', kind: AppSnackKind.success);
        default:
          await widget.service.delete(widget.site.code, detail.id);
          if (!mounted) return;
          AppSnack.show(context, 'Taslak silindi.', kind: AppSnackKind.success);
          Navigator.of(context).pop(true);
          return;
      }
      _changed = true;
    } catch (e) {
      if (!mounted) return;
      AppSnack.show(context, crmMessageOf(e, 'İşlem yapılamadı. Lütfen tekrar deneyin.'), kind: AppSnackKind.error);
      if (e is ApiException && e.code == 'INVALID_STATE') {
        _changed = true;
        unawaited(_load());
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final detail = _detail;
    final summary = detail?.summary ?? widget.summary;
    final canWrite = widget.site.canWrite;
    return PopScope(
      canPop: !_busy,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_busy) Navigator.of(context).pop(_changed);
      },
      child: AlertDialog(
        key: const ValueKey<String>('svm_detail'),
        title: Text(summary.title, maxLines: 3, overflow: TextOverflow.ellipsis),
        scrollable: true,
        content: SizedBox(
          width: 480,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.xs,
                children: [
                  SurveyStatusChip(status: summary.status, expired: summary.isExpired),
                  if (!summary.anonymous)
                    const StatusChip(label: 'Açık oy', tone: AppTone.warning, icon: Icons.badge_outlined),
                  if (summary.oneVotePerApartment)
                    const StatusChip(label: 'Daire başına tek oy', tone: AppTone.info, icon: Icons.home_rounded),
                ],
              ),
              const SizedBox(height: AppSpace.sm),
              Text(surveyClosesText(summary.closesAt), style: th.bodySmall?.copyWith(color: p.textSecondary)),
              if (summary.createdByName != null)
                Text('Açan: ${summary.createdByName}', style: th.bodySmall?.copyWith(color: p.textSecondary)),
              const SizedBox(height: AppSpace.md),
              if (_loading)
                const ListSkeleton(rows: 2)
              else if (_error != null)
                InlineNotice(key: const ValueKey<String>('svm_detail_error'), message: _error!, tone: AppTone.danger, onRetry: _load)
              else if (detail != null) ...[
                Text('Hedef: ${detail.target.summary}', style: th.bodySmall?.copyWith(color: p.textSecondary)),
                const SizedBox(height: AppSpace.md),
                Text(detail.question, style: th.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: AppSpace.md),
                SurveyResultBars(options: detail.options, results: detail.results),
                if (!summary.anonymous && canWrite) ...[
                  const SizedBox(height: AppSpace.lg),
                  Text('Oy verenler', style: th.titleSmall),
                  const SizedBox(height: AppSpace.sm),
                  if (_voters == null && !_votersLoading)
                    TextButton.icon(
                      key: const ValueKey<String>('svm_voters_load'),
                      onPressed: () => unawaited(_loadVoters()),
                      icon: const Icon(Icons.people_alt_outlined),
                      label: const Text('Oy verenleri göster'),
                    )
                  else if (_votersLoading)
                    const ListSkeleton(rows: 1)
                  else if (_votersError != null)
                    InlineNotice(message: _votersError!, tone: AppTone.danger, onRetry: _loadVoters)
                  else if (_voters!.isEmpty)
                    Text('Henüz oy verilmedi.', style: th.bodySmall?.copyWith(color: p.textSecondary))
                  else ...[
                    for (final v in _voters!)
                      Padding(
                        key: ValueKey<String>('svm_voter_${v.userCode ?? 0}_${v.votedAt?.millisecondsSinceEpoch ?? 0}'),
                        padding: const EdgeInsets.only(bottom: AppSpace.xs),
                        child: Text(
                          '${v.displayName}${v.apartmentLabel.isEmpty ? '' : ' (${v.apartmentLabel})'} · '
                          '${v.optionIndex >= 0 && v.optionIndex < detail.options.length ? detail.options[v.optionIndex] : 'Seçenek ${v.optionIndex + 1}'}'
                          '${v.votedAt == null ? '' : ' · ${formatIstanbulDateTime(v.votedAt!)}'}',
                          style: th.bodySmall,
                        ),
                      ),
                    if (_voters!.length < _votersTotal)
                      Text('İlk ${_voters!.length} / $_votersTotal gösteriliyor.', style: th.bodySmall?.copyWith(color: p.textSecondary)),
                  ],
                ],
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            key: const ValueKey<String>('svm_detail_close'),
            onPressed: _busy ? null : () => Navigator.of(context).pop(_changed),
            child: const Text('Kapat'),
          ),
          if (canWrite && detail != null && summary.canDelete)
            TextButton(
              key: const ValueKey<String>('svm_action_delete'),
              onPressed: _busy ? null : () => unawaited(_act('delete')),
              child: const Text('Sil'),
            ),
          if (canWrite && detail != null && summary.canClose)
            FilledButton.tonal(
              key: const ValueKey<String>('svm_action_close'),
              onPressed: _busy ? null : () => unawaited(_act('close')),
              child: const Text('Anketi Kapat'),
            ),
          if (canWrite && detail != null && summary.canPublish)
            FilledButton(
              key: const ValueKey<String>('svm_action_open'),
              onPressed: _busy ? null : () => unawaited(_act('open')),
              child: const Text('Yayınla'),
            ),
        ],
      ),
    );
  }
}
