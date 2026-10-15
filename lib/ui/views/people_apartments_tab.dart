import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/apartment_crm.dart';
import 'package:site_kapi_kontrol/models/site_block_record.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/apartment_card_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/widgets/apartment_crm_card.dart';
import 'package:site_kapi_kontrol/ui/widgets/crm_parts.dart';

/// "Daireler" sekmesi (Platform Faz 2a): arama + blok süzgeci, sayfalı daire listesi ve daire kartı.
///
/// Blok süzgeci sitenin blok listesinden gelir (`getSiteStructure`); liste alınamazsa (ör. salt okunur
/// kurul üyesi) süzgeç GİZLİ kalır, arama ve liste çalışır. Her başarılı düzenlemeden sonra liste
/// otomatik yenilenir ve [onDataChanged] çağrılır.
class PeopleApartmentsTab extends StatefulWidget {
  const PeopleApartmentsTab({
    super.key,
    required this.scope,
    required this.onDataChanged,
  });

  final PeopleScope scope;
  final VoidCallback onDataChanged;

  @override
  State<PeopleApartmentsTab> createState() => PeopleApartmentsTabState();
}

class PeopleApartmentsTabState extends State<PeopleApartmentsTab> {
  static const int _allBlocks = 0;

  final TextEditingController _search = TextEditingController();
  Timer? _timer;
  String _query = '';
  int? _blockId;
  List<SiteBlockRecord> _blocks = const <SiteBlockRecord>[];

  late final PagedLoader<ApartmentSummary> _loader = PagedLoader<ApartmentSummary>(
    fetch: (offset, limit) async {
      final page = await widget.scope.authService.listApartments(
        widget.scope.siteCode,
        blockId: _blockId,
        query: _query,
        limit: limit,
        offset: offset,
      );
      return (items: page.items, total: page.total);
    },
    keyOf: (a) => a.id,
    notify: () {
      if (mounted) setState(() {});
    },
    isAlive: () => mounted,
    errorFallback: 'Daireler yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
  );

  @override
  void initState() {
    super.initState();
    unawaited(_loader.reload());
    unawaited(_loadBlocks());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _loader.dispose();
    _search.dispose();
    super.dispose();
  }

  /// Blok süzgeci listesi: alınamazsa süzgeç gizli kalır (daireler yine listelenir).
  Future<void> _loadBlocks() async {
    final siteCode = widget.scope.siteCode;
    try {
      final (structure, _) = await widget.scope.authService.getSiteStructure(
        siteCode: siteCode,
      );
      if (!mounted || structure == null) return;
      setState(() => _blocks = structure.blocks);
    } catch (_) {
      // Süzgeç olmadan devam.
    }
  }

  /// Listeyi yeniden çeker (sayfa kabuğunun çekip yenilemesi ve yenile düğmesi).
  Future<void> reload() => _loader.reload();

  // Son çalıştırılan sorgunun imzası: aynı sorgu tekrar çağrılmaz (okuma hız sınırı düşüktür).
  String _lastSignature = '|null';

  void _applyFilters() {
    _timer?.cancel();
    final next = _search.text.trim();
    final signature = '$next|$_blockId';
    if (signature == _lastSignature &&
        (_loader.loading || (_loader.loadedOnce && _loader.error == null))) {
      return;
    }
    _lastSignature = signature;
    _query = next;
    _loader.reset();
    unawaited(_loader.reload());
  }

  void _onSearchChanged(String _) {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 350), _applyFilters);
    setState(() {});
  }

  void _afterChange() {
    widget.onDataChanged();
    unawaited(_loader.reload());
  }

  Future<void> _open(ApartmentSummary apartment) {
    return ApartmentCardDialog.show(
      context,
      scope: widget.scope,
      apartmentId: apartment.id,
      initialLabel: apartment.fullLabel,
      onChanged: _afterChange,
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const ValueKey<String>('apartments_search'),
                controller: _search,
                textInputAction: TextInputAction.search,
                onChanged: _onSearchChanged,
                onSubmitted: (_) => _applyFilters(),
                decoration: InputDecoration(
                  labelText: 'Daire ara',
                  hintText: 'Daire no, blok veya kişi adı',
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
              if (_blocks.length > 1) ...[
                const SizedBox(height: AppSpace.md),
                DropdownButtonFormField<int>(
                  key: ValueKey<String>('apartments_block_${_blockId ?? 0}_${_blocks.length}'),
                  isExpanded: true,
                  initialValue: _blockId ?? _allBlocks,
                  dropdownColor: p.surface,
                  style: th.bodyMedium?.copyWith(color: p.text),
                  decoration: const InputDecoration(
                    labelText: 'Blok',
                    prefixIcon: Icon(Icons.filter_list_rounded),
                  ),
                  items: [
                    const DropdownMenuItem<int>(
                      value: _allBlocks,
                      child: Text('Tüm bloklar', maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    for (final block in _blocks)
                      DropdownMenuItem<int>(
                        value: block.id,
                        child: Text(
                          block.blockName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    final next = value == _allBlocks ? null : value;
                    if (next == _blockId) return;
                    _blockId = next;
                    _applyFilters();
                    setState(() {});
                  },
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpace.md),
        SectionHeader(
          title: 'Daireler',
          count: _loader.loadedOnce ? _loader.total : null,
          trailing: IconButton(
            onPressed: _loader.loading ? null : reload,
            tooltip: 'Yenile',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        CrmListBody<ApartmentSummary>(
          loader: _loader,
          emptyIcon: Icons.apartment_rounded,
          emptyTitle: 'Bu sitede daire bulunamadı.',
          filteredTitle: 'Bu arama ve süzgeç için daire bulunamadı.',
          filtered: _query.isNotEmpty || _blockId != null,
          itemBuilder: (context, apartment) =>
              ApartmentCrmCard(apartment: apartment, onTap: () => _open(apartment)),
        ),
      ],
    );
  }
}
