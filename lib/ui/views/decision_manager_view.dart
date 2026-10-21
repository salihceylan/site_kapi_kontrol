import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/ui/helpers/list_export.dart';
import 'package:site_kapi_kontrol/models/decision_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/decision_book_api.dart';
import 'package:site_kapi_kontrol/services/pdf_decision_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/decision_detail_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/decision_form_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/decision_loader.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart' show crmMessageOf;
import 'package:site_kapi_kontrol/ui/widgets/decision_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

/// Yönetim "Karar Defteri" ekranı (`decision_book` modülü): yönetici / süper kullanıcı (taslak yazar, düzenler,
/// siler, kesinleştirir, düzeltme kararı yazar) ve yönetim kurulu (taslaklar dahil SALT OKUR).
///
/// - [manageAllSites] true (süper kullanıcı): tüm onaylı siteler listelenir ve yazma yetkisi vardır.
/// - [sites]: `GET /app/my-modules` ile `decision_book` modülü AÇIK siteler (erişim türüyle).
/// - Liste yıl başlıklarıyla gruplanır; yıl seçici sunucunun `years` alanından; durum / toplantı türü / arama süzgeci.
/// - "PDF olarak indir": seçilen yılın KESİN kararları ([DecisionPdfActions]).
/// - HATA ASLA "karar yok" demez; modül kapalıysa (403 `MODULE_DISABLED`) açıklayıcı kart çıkar.
/// - [DecisionManagerViewState.reload] sayfa kabuğunun aşağı çekip yenilemesinden çağrılır.
class DecisionManagerView extends StatefulWidget {
  const DecisionManagerView({
    super.key,
    required this.authService,
    this.service,
    this.manageAllSites = false,
    this.sites = const <DecisionSite>[],
    this.onOpenModules,
    this.clock,
  });

  final AuthService authService;
  final DecisionBookService? service;
  final bool manageAllSites;
  final List<DecisionSite> sites;
  final VoidCallback? onOpenModules;

  /// Test düzeneği (form için şimdiki an).
  final DateTime Function()? clock;

  @override
  State<DecisionManagerView> createState() => DecisionManagerViewState();
}

class DecisionManagerViewState extends State<DecisionManagerView> {
  static const List<(String, String)> _statusChips = <(String, String)>[
    ('all', 'Tümü'),
    ('taslak', 'Taslak'),
    ('kesin', 'Kesin'),
  ];

  List<DecisionSite> _sites = const <DecisionSite>[];
  int? _siteCode;
  bool _loadingSites = false;
  bool _sitesLoadedOnce = false;
  String? _sitesError;
  int _sitesToken = 0;

  final TextEditingController _search = TextEditingController();
  Timer? _timer;
  String _query = '';
  int? _year;
  String _status = 'all';
  String _meetingType = '';
  bool _moduleOff = false;
  String _lastSignature = '';

  bool _pdfBusy = false;
  String? _pdfNotice;
  AppTone _pdfNoticeTone = AppTone.danger;

  late DecisionBookService _service = widget.service ?? DecisionBookService(authService: widget.authService);

  late final DecisionListLoader _loader = DecisionListLoader(
    fetch: (cursor) async {
      final site = _siteCode;
      if (site == null) return const DecisionPage();
      final page = await _service.listManaged(
        site,
        year: _year,
        status: _status,
        meetingType: _meetingType.isEmpty ? null : _meetingType,
        query: _query,
        cursor: cursor,
      );
      if (cursor == null) _moduleOff = false;
      return page;
    },
    notify: () {
      if (mounted) setState(() {});
    },
    isAlive: () => mounted,
    messageOf: (error, fallback) {
      if (error is ApiException && error.code == 'MODULE_DISABLED') _moduleOff = true;
      return crmMessageOf(error, fallback);
    },
  );

  @override
  void initState() {
    super.initState();
    unawaited(reload());
  }

  @override
  void didUpdateWidget(DecisionManagerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.service, widget.service) || !identical(oldWidget.authService, widget.authService)) {
      _service = widget.service ?? DecisionBookService(authService: widget.authService);
    }
    if (oldWidget.manageAllSites != widget.manageAllSites || !listEquals(oldWidget.sites, widget.sites)) {
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

  DecisionSite? get _site {
    final code = _siteCode;
    if (code == null) return null;
    for (final site in _sites) {
      if (site.code == code) return site;
    }
    return null;
  }

  String get _signature => '${_siteCode ?? ''}|$_query|$_year|$_status|$_meetingType';

  /// Siteleri ve listeyi yeniden çeker (mevcut liste yenileme sürerken ekranda kalır).
  Future<void> reload() async {
    if (!mounted) return;
    final token = ++_sitesToken;
    setState(() {
      _loadingSites = true;
      _sitesError = null;
    });
    try {
      final merged = <DecisionSite>[];
      if (widget.manageAllSites) {
        // Süper kullanıcıda site sayısı 100'ü aşabilir: onaylı siteler sayfa sayfa toplanır (üst sınır 50 sayfa).
        var pageNo = 1;
        var fetched = 0;
        while (true) {
          final page = await widget.authService.listSites(page: pageNo, pageSize: 100, approvalStatus: 'approved');
          for (final site in page.sites) {
            if (site.isApproved && !merged.any((m) => m.code == site.id)) {
              merged.add(DecisionSite(code: site.id, name: site.name));
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
      final siteChanged = next != _siteCode;
      final previous = _site;
      setState(() {
        _sites = merged;
        _loadingSites = false;
        _sitesLoadedOnce = true;
        _siteCode = next;
      });
      final current = _site;
      if (siteChanged || (previous != null && current != null && previous.access != current.access)) {
        _resetList();
      } else if (current != null) {
        await _loader.reload();
      }
    } catch (e) {
      if (!mounted || token != _sitesToken) return;
      setState(() {
        _loadingSites = false;
        _sitesError = crmMessageOf(e, 'Siteler yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.');
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
    if (_signature == _lastSignature && (_loader.loading || (_loader.loadedOnce && _loader.error == null))) return;
    _resetList();
  }

  void _onSearchChanged(String _) {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 350), _applyFilters);
    setState(() {});
  }

  void _setFilter(VoidCallback change) {
    setState(() {
      change();
      _pdfNotice = null;
    });
    _applyFilters();
  }

  void _selectSite(int code) {
    if (code == _siteCode) return;
    setState(() {
      _siteCode = code;
      _moduleOff = false;
      _year = null;
      _pdfNotice = null;
      _loader.years = <int>[];
    });
    _resetList();
  }

  String _siteLabel(DecisionSite site) {
    final same = _sites.where((s) => s.label == site.label).toList();
    if (same.length < 2) return site.label;
    return '${site.label} (${same.indexOf(site) + 1})';
  }

  /// Seçicide gösterilen yıllar: sunucunun `years` alanı + listedeki kayıtların yılları.
  List<int> get _years {
    final set = <int>{..._loader.years, for (final d in _loader.items) if (d.effectiveYear > 0) d.effectiveYear};
    return set.toList()..sort((a, b) => b.compareTo(a));
  }

  Future<void> _create(DecisionSite site, {Decision? supersedes}) async {
    final created = await DecisionFormDialog.show(
      context,
      service: _service,
      site: site,
      supersedes: supersedes,
      clock: widget.clock,
    );
    if (created == null || !mounted) return;
    AppSnack.show(context, 'Karar taslak olarak kaydedildi. Kesinleştirince numara alır.', kind: AppSnackKind.success);
    _resetList();
  }

  Future<void> _openDetail(DecisionSite site, Decision item) async {
    final outcome = await DecisionDetailDialog.show(
      context,
      service: _service,
      id: item.id,
      site: site,
      initial: item,
      clock: widget.clock,
    );
    if (!mounted || outcome == null) return;
    if (outcome.changed) _resetList();
    final correction = outcome.correctionOf;
    if (correction != null && site.canWrite) await _create(site, supersedes: correction);
  }

  Future<int?> _pickYear(List<int> years) => showDialog<int>(
    context: context,
    builder: (dialogContext) => SimpleDialog(
      key: const ValueKey<String>('decision_pdf_year_dialog'),
      title: const Text('Hangi yılın kararları?'),
      children: [
        for (final y in years)
          SimpleDialogOption(
            key: ValueKey<String>('decision_pdf_year_$y'),
            onPressed: () => Navigator.of(dialogContext).pop(y),
            child: Text('$y yılının kesin kararları'),
          ),
      ],
    ),
  );

  Future<void> _downloadPdf(DecisionSite site) async {
    if (_pdfBusy) return;
    var year = _year;
    if (year == null) {
      final years = _years;
      if (years.isEmpty) {
        setState(() {
          _pdfNotice = 'PDF için önce kesinleşmiş bir karar olmalı.';
          _pdfNoticeTone = AppTone.info;
        });
        return;
      }
      year = years.length == 1 ? years.single : await _pickYear(years);
      if (year == null || !mounted) return;
    }
    setState(() {
      _pdfBusy = true;
      _pdfNotice = null;
    });
    try {
      final decisions = await _service.collectFinalForYear(site.code, year);
      if (!mounted) return;
      if (decisions.isEmpty) {
        setState(() {
          _pdfBusy = false;
          _pdfNotice = '$year yılında kesinleşmiş karar yok. Taslaklar PDF\'e girmez.';
          _pdfNoticeTone = AppTone.info;
        });
        return;
      }
      final outcome = await DecisionPdfActions.downloadYear(siteName: site.label, year: year, decisions: decisions);
      if (!mounted) return;
      setState(() => _pdfBusy = false);
      if (outcome == DecisionPdfOutcome.delivered) {
        AppSnack.show(
          context,
          '$year yılının ${decisions.length} kesin kararı PDF olarak hazırlandı.',
          kind: AppSnackKind.success,
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _pdfBusy = false;
        _pdfNotice = crmMessageOf(e, 'PDF hazırlanamadı. Tekrar deneyin.');
        _pdfNoticeTone = AppTone.danger;
      });
    }
  }

  bool get _filtered => _query.isNotEmpty || _year != null || _status != 'all' || _meetingType.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final site = _site;
    if (site == null) {
      if (_loadingSites || (!_sitesLoadedOnce && _sitesError == null)) return const ListSkeleton(rows: 2);
      if (_sitesError != null) return InlineNotice(message: _sitesError!, onRetry: reload);
      return const EmptyCard(
        icon: Icons.apartment_rounded,
        title: 'Kayıtlı site bulunamadı.',
        message: 'Kararlar, Karar Defteri modülü açık bir siteye bağlı olduğunuzda burada görünür.',
      );
    }
    return _buildSite(context, site);
  }

  Widget _buildSite(BuildContext context, DecisionSite site) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final canWrite = site.canWrite;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeaderCard(
          title: 'Karar Defteri',
          icon: Icons.gavel_rounded,
          action: canWrite && !_moduleOff
              ? ElevatedButton.icon(
                  key: const ValueKey<String>('decision_new'),
                  onPressed: () => unawaited(_create(site)),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Yeni Karar'),
                )
              : null,
        ),
        const SizedBox(height: AppSpace.sm),
        Text(
          canWrite
              ? 'Yönetim kurulu, genel kurul ve denetim kurulu kararlarını kaydedin; kesinleşen karar numara alır.'
              : 'Sitedeki kararları ve taslakları izleyin.',
          style: th.bodyMedium,
        ),
        const SizedBox(height: AppSpace.md),
        const DecisionLegalNote(),
        const SizedBox(height: AppSpace.md),
        if (_sitesError != null) ...[
          InlineNotice(message: _sitesError!, onRetry: reload),
          const SizedBox(height: AppSpace.md),
        ],
        if (_sites.length > 1)
          AppCard(
            child: DropdownButtonFormField<int>(
              key: ValueKey<String>('decision_site_${site.code}_${_sites.length}'),
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
        if (!canWrite) ...[const DecisionReadOnlyNote(), const SizedBox(height: AppSpace.md)],
        if (_moduleOff)
          DecisionModuleOffCard(
            message: 'Modül açılınca kararlar burada kaydedilir.',
            onOpenModules: widget.onOpenModules,
          )
        else ...[
          _buildFilters(context),
          const SizedBox(height: AppSpace.md),
          _buildPdf(context, site),
          const SizedBox(height: AppSpace.md),
          SectionHeader(
            title: 'Kararlar',
            trailing: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[ListExportButton(enabled: _loader.items.isNotEmpty, source: localExportSource(label: 'Kararlar', filenameBase: 'kararlar', headers: <String>['Karar no', 'Başlık', 'Toplantı türü', 'Toplantı tarihi', 'Oylama', 'Durum'], rows: () => <List<Object?>>[for (final d in _loader.items) [d.numberLabel ?? d.decisionNo, d.title, d.meetingType.label, exportDate(d.meetingDate), d.voteResult.label, d.status.label]])), IconButton(
              onPressed: _loader.loading ? null : reload,
              tooltip: 'Yenile',
              icon: const Icon(Icons.refresh_rounded),
            )]),
          ),
          const SizedBox(height: AppSpace.md),
          DecisionListBody(
            loader: _loader,
            emptyTitle: _filtered ? 'Bu süzgeç için karar bulunamadı.' : 'Henüz karar yok.',
            emptyMessage: _filtered
                ? null
                : (canWrite ? '"Yeni Karar" ile ilk kararı taslak olarak yazın.' : 'Yönetim bir karar yazdığında burada görünür.'),
            cardBuilder: (d) => DecisionCard(
              key: ValueKey<String>('decision_card_${d.id}'),
              decision: d,
              onTap: () => unawaited(_openDetail(site, d)),
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
            key: const ValueKey<String>('decision_search'),
            controller: _search,
            textInputAction: TextInputAction.search,
            onChanged: _onSearchChanged,
            onSubmitted: (_) => _applyFilters(),
            decoration: InputDecoration(
              labelText: 'Karar ara',
              hintText: 'Başlık, metin ya da numara (2026/3)',
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
          DecisionYearDropdown(
            years: _years,
            selected: _year,
            onChanged: (year) => _setFilter(() => _year = year),
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
                  key: ValueKey<String>('decision_status_${entry.$1}'),
                  label: Text(entry.$2),
                  selected: _status == entry.$1,
                  onSelected: (_) => _setFilter(() => _status = entry.$1),
                ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          Text('Toplantı türü', style: th.titleSmall),
          const SizedBox(height: AppSpace.sm),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: [
              ChoiceChip(
                key: const ValueKey<String>('decision_type_all'),
                label: const Text('Tümü'),
                selected: _meetingType.isEmpty,
                onSelected: (_) => _setFilter(() => _meetingType = ''),
              ),
              for (final t in DecisionMeetingType.values)
                ChoiceChip(
                  key: ValueKey<String>('decision_type_${t.apiValue}'),
                  label: Text(t.label),
                  selected: _meetingType == t.apiValue,
                  onSelected: (_) => _setFilter(() => _meetingType = t.apiValue),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPdf(BuildContext context, DecisionSite site) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final year = _year;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_pdfNotice != null) ...[
          InlineNotice(key: const ValueKey<String>('decision_pdf_notice'), message: _pdfNotice!, tone: _pdfNoticeTone),
          const SizedBox(height: AppSpace.sm),
        ],
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            PrimaryActionButton(
              key: const ValueKey<String>('decision_pdf'),
              label: 'PDF olarak indir',
              icon: Icons.picture_as_pdf_rounded,
              variant: AppButtonVariant.tonal,
              expand: false,
              loading: _pdfBusy,
              onPressed: _pdfBusy ? null : () => unawaited(_downloadPdf(site)),
            ),
            Text(
              year == null ? 'Seçilen yılın kesin kararları.' : '$year yılının kesin kararları.',
              style: th.bodySmall?.copyWith(color: p.textSecondary),
            ),
          ],
        ),
      ],
    );
  }
}
