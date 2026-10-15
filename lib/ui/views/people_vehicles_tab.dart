import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/vehicle_record.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/crm_confirm_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/vehicle_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/widgets/crm_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/vehicle_card.dart';

/// "Araçlar" sekmesi (Platform Faz 2a): plaka / kişi araması, sayfalı araç listesi, "Araç Ekle" ve araç
/// kaldırma (ikisi de yalnız yazma yetkisi olanda). Her başarılı işlemden sonra liste otomatik yenilenir
/// ve [onDataChanged] çağrılır.
class PeopleVehiclesTab extends StatefulWidget {
  const PeopleVehiclesTab({
    super.key,
    required this.scope,
    required this.onDataChanged,
  });

  final PeopleScope scope;
  final VoidCallback onDataChanged;

  @override
  State<PeopleVehiclesTab> createState() => PeopleVehiclesTabState();
}

class PeopleVehiclesTabState extends State<PeopleVehiclesTab> {
  final TextEditingController _search = TextEditingController();
  Timer? _timer;
  String _query = '';
  final Set<int> _busy = <int>{};
  String? _actionError;

  late final PagedLoader<VehicleRecord> _loader = PagedLoader<VehicleRecord>(
    fetch: (offset, limit) async {
      final page = await widget.scope.authService.listVehicles(
        widget.scope.siteCode,
        query: _query,
        limit: limit,
        offset: offset,
      );
      return (items: page.items, total: page.total);
    },
    keyOf: (v) => v.id,
    notify: () {
      if (mounted) setState(() {});
    },
    isAlive: () => mounted,
    errorFallback: 'Araçlar yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
  );

  @override
  void initState() {
    super.initState();
    unawaited(_loader.reload());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _loader.dispose();
    _search.dispose();
    super.dispose();
  }

  /// Listeyi yeniden çeker (sayfa kabuğunun çekip yenilemesi ve yenile düğmesi).
  Future<void> reload() => _loader.reload();

  // Son çalıştırılan sorgunun imzası: aynı sorgu tekrar çağrılmaz (okuma hız sınırı düşüktür).
  String _lastSignature = '';

  void _applyFilters() {
    _timer?.cancel();
    final next = _search.text.trim();
    if (next == _lastSignature &&
        (_loader.loading || (_loader.loadedOnce && _loader.error == null))) {
      return;
    }
    _lastSignature = next;
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

  Future<void> _add() async {
    final vehicle = await VehicleDialog.show(context, scope: widget.scope);
    if (vehicle == null || !mounted) return;
    AppSnack.show(context, 'Araç eklendi.', kind: AppSnackKind.success);
    _afterChange();
  }

  Future<void> _remove(VehicleRecord vehicle) async {
    final confirmed = await confirmCrmAction(
      context,
      title: 'Aracı kaldır',
      message: '${vehicle.displayPlate} plakalı araç kaldırılsın mı? Kayıt silinmez, pasifleşir.',
      confirmLabel: 'Kaldır',
      icon: Icons.delete_outline_rounded,
      tone: AppTone.danger,
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _busy.add(vehicle.id);
      _actionError = null;
    });
    try {
      await widget.scope.authService.removeVehicle(widget.scope.siteCode, vehicle.id);
      if (!mounted) return;
      setState(() => _busy.remove(vehicle.id));
      AppSnack.show(context, 'Araç kaldırıldı.', kind: AppSnackKind.success);
      _afterChange();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy.remove(vehicle.id);
        _actionError = crmMessageOf(
          e,
          'Araç kaldırılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.scope.canWrite) ...[
          PrimaryActionButton(
            label: 'Araç Ekle',
            icon: Icons.add_rounded,
            onPressed: _add,
          ),
          const SizedBox(height: AppSpace.md),
        ],
        AppCard(
          child: TextField(
            key: const ValueKey<String>('vehicles_search'),
            controller: _search,
            textInputAction: TextInputAction.search,
            onChanged: _onSearchChanged,
            onSubmitted: (_) => _applyFilters(),
            decoration: InputDecoration(
              labelText: 'Araç ara',
              hintText: 'Plaka veya kişi adı',
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
        ),
        const SizedBox(height: AppSpace.md),
        SectionHeader(
          title: 'Araçlar',
          count: _loader.loadedOnce ? _loader.total : null,
          trailing: IconButton(
            onPressed: _loader.loading ? null : reload,
            tooltip: 'Yenile',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        if (_actionError != null) ...[
          InlineNotice(message: _actionError!),
          const SizedBox(height: AppSpace.md),
        ],
        CrmListBody<VehicleRecord>(
          loader: _loader,
          emptyIcon: Icons.directions_car_rounded,
          emptyTitle: 'Henüz araç kaydı yok.',
          emptyMessage: widget.scope.canWrite
              ? 'Araç Ekle ile ilk aracı kaydedebilirsiniz.'
              : null,
          filteredTitle: 'Bu arama için araç bulunamadı.',
          filtered: _query.isNotEmpty,
          itemBuilder: (context, vehicle) => VehicleCard(
            vehicle: vehicle,
            busy: _busy.contains(vehicle.id),
            showNote: widget.scope.canWrite,
            onRemove: widget.scope.canWrite ? () => _remove(vehicle) : null,
          ),
        ),
      ],
    );
  }
}
