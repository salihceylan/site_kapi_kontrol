import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/decision_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/decision_book_api.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/decision_detail_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/decision_loader.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart' show crmMessageOf;
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/widgets/decision_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

/// Sakin "Kararlar" ekranı (`decision_book` modülü): yönetimin sakinlerle paylaştığı KESİN kararlar, yıl başlıklarıyla;
/// ayrıntı salt okunur.
///
/// - Birden çok sitede ([sites] >= 2) site süzgeci çıkar ve kartlarda site adı görünür.
/// - HATA ASLA "karar yok" demez; modül kapalıysa (403 `MODULE_DISABLED`) açıklayıcı kart çıkar.
/// - [DecisionResidentViewState.reload] sayfa kabuğunun aşağı çekip yenilemesinden çağrılır.
class DecisionResidentView extends StatefulWidget {
  const DecisionResidentView({
    super.key,
    required this.authService,
    this.service,
    this.sites = const <PeopleSite>[],
  });

  final AuthService authService;
  final DecisionBookService? service;
  final List<PeopleSite> sites;

  @override
  State<DecisionResidentView> createState() => DecisionResidentViewState();
}

class DecisionResidentViewState extends State<DecisionResidentView> {
  static const int _allSites = 0;

  int? _siteFilter;
  int? _year;
  bool _moduleOff = false;

  late DecisionBookService _service = widget.service ?? DecisionBookService(authService: widget.authService);

  late final DecisionListLoader _loader = DecisionListLoader(
    fetch: (cursor) async {
      // Tek site varken o site açıkça istenir (menüdeki site kümesiyle aynı sonuç); çok sitede "Tüm siteler" süzgeçsizdir.
      final site = _siteFilter ?? (widget.sites.length == 1 ? widget.sites.single.code : null);
      final page = await _service.listMine(siteCode: site, year: _year, cursor: cursor);
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
    if (widget.sites.isNotEmpty) unawaited(_loader.reload());
  }

  @override
  void didUpdateWidget(DecisionResidentView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.service, widget.service) || !identical(oldWidget.authService, widget.authService)) {
      _service = widget.service ?? DecisionBookService(authService: widget.authService);
    }
    final filter = _siteFilter;
    if (filter != null && !widget.sites.any((s) => s.code == filter)) {
      _siteFilter = null;
      _year = null;
      _loader.reset();
      unawaited(_loader.reload());
    } else if (oldWidget.sites.isEmpty && widget.sites.isNotEmpty) {
      unawaited(_loader.reload());
    }
  }

  @override
  void dispose() {
    _loader.dispose();
    super.dispose();
  }

  /// Listeyi yeniden çeker (sayfa kabuğunun çekip yenilemesi ve yenile düğmesi).
  Future<void> reload() async {
    if (widget.sites.isEmpty) return;
    await _loader.reload();
  }

  void _setFilter(VoidCallback change) {
    setState(change);
    _loader.reset();
    unawaited(_loader.reload());
  }

  List<int> get _years {
    final set = <int>{..._loader.years, for (final d in _loader.items) if (d.effectiveYear > 0) d.effectiveYear};
    return set.toList()..sort((a, b) => b.compareTo(a));
  }

  String? _siteLabelOf(Decision d) {
    if (widget.sites.length < 2) return null;
    if (d.siteName.isNotEmpty) return d.siteName;
    for (final s in widget.sites) {
      if (s.code == d.siteCode) return s.label;
    }
    return null;
  }

  Future<void> _openDetail(Decision item) async {
    await DecisionDetailDialog.show(context, service: _service, id: item.id, initial: item);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final multiSite = widget.sites.length > 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageHeaderCard(title: 'Kararlar', icon: Icons.library_books_rounded),
        const SizedBox(height: AppSpace.sm),
        Text('Yönetimin sakinlerle paylaştığı kesinleşmiş kararlar.', style: th.bodyMedium),
        const SizedBox(height: AppSpace.md),
        const DecisionLegalNote(),
        const SizedBox(height: AppSpace.md),
        if (widget.sites.isNotEmpty && !_moduleOff) ...[
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (multiSite) ...[
                  DropdownButtonFormField<int>(
                    key: ValueKey<String>('decision_resident_site_${_siteFilter ?? 0}'),
                    isExpanded: true,
                    initialValue: _siteFilter ?? _allSites,
                    dropdownColor: p.surface,
                    style: th.bodyMedium?.copyWith(color: p.text),
                    decoration: const InputDecoration(labelText: 'Site', prefixIcon: Icon(Icons.apartment_rounded)),
                    items: [
                      const DropdownMenuItem<int>(
                        value: _allSites,
                        child: Text('Tüm siteler', maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      for (final s in widget.sites)
                        DropdownMenuItem<int>(
                          value: s.code,
                          child: Text(s.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      final next = value == _allSites ? null : value;
                      if (next == _siteFilter) return;
                      _setFilter(() {
                        _siteFilter = next;
                        _year = null;
                        _loader.years = <int>[];
                      });
                    },
                  ),
                  const SizedBox(height: AppSpace.md),
                ],
                DecisionYearDropdown(
                  fieldKey: 'decision_resident_year',
                  years: _years,
                  selected: _year,
                  onChanged: (year) => _setFilter(() => _year = year),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.md),
        ],
        SectionHeader(
          title: 'Kararlar',
          trailing: IconButton(
            onPressed: _loader.loading || widget.sites.isEmpty ? null : reload,
            tooltip: 'Yenile',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        if (_moduleOff)
          const DecisionModuleOffCard()
        else if (widget.sites.isEmpty)
          const EmptyCard(
            icon: Icons.gavel_outlined,
            title: 'Karar görebileceğiniz site yok.',
            message: 'Kararlar, bir siteye daire sakini olarak bağlandığınızda ve yönetim özelliği açtığında burada görünür.',
          )
        else
          DecisionListBody(
            loader: _loader,
            emptyTitle: _year == null ? 'Paylaşılmış karar yok.' : '$_year yılında paylaşılmış karar yok.',
            emptyMessage: 'Yönetim bir kararı kesinleştirip sakinlerle paylaştığında burada görünür.',
            cardBuilder: (d) => DecisionCard(
              key: ValueKey<String>('decision_card_${d.id}'),
              decision: d,
              showManagerMarkers: false,
              siteLabel: _siteLabelOf(d),
              onTap: () => unawaited(_openDetail(d)),
            ),
          ),
      ],
    );
  }
}
