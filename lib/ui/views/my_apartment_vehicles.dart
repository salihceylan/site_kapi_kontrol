// "Dairem > Araçlarım" bölümü: dairenin araçları. Daire yöneticisi (ve site yöneticisi) araç ekler, notu düzenler, çıkarır;
// aile üyeleri ve admin olmayan malik / kiracı yalnız görür. Sözleşme: docs/PLATFORM_DAIRE_YONETIMI.md ("Araçlar").
// Etki: kayıtlı araç, sitede plaka tanıma açıksa yetkili araç sayılır (ekranda uyarı olarak yazar).
// Ana sayfa gövdesinde sınırsız yükseklik hatası vermesin diye liste widget'ı yok: Column + kartlar (kaydırmayı üst sayfa yapar).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/apartment_vehicles.dart';
import 'package:site_kapi_kontrol/models/vehicle_record.dart';
import 'package:site_kapi_kontrol/services/apartment_management_api.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/apartment_vehicle_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/crm_confirm_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart' show crmMessageOf;

class ApartmentVehiclesSection extends StatefulWidget {
  const ApartmentVehiclesSection({super.key, required this.service, required this.apartmentId});

  final ApartmentManagementService service;
  final int apartmentId;

  @override
  State<ApartmentVehiclesSection> createState() => ApartmentVehiclesSectionState();
}

class ApartmentVehiclesSectionState extends State<ApartmentVehiclesSection> {
  ApartmentVehicles? _data;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  int _token = 0;

  @override
  void initState() {
    super.initState();
    unawaited(reload());
  }

  @override
  void dispose() {
    ++_token;
    super.dispose();
  }

  Future<void> reload() async {
    final token = ++_token;
    setState(() {
      _loading = _data == null;
      _error = null;
    });
    try {
      final data = await widget.service.vehicles(widget.apartmentId);
      if (!mounted || token != _token) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || token != _token) return;
      setState(() {
        _loading = false;
        _error = crmMessageOf(e, 'Araçlar yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.');
      });
    }
  }

  Future<void> _add(ApartmentVehicles data) async {
    final done = await ApartmentVehicleDialog.show(
      context,
      service: widget.service,
      apartmentId: widget.apartmentId,
      owners: data.owners,
      notice: data.notice,
    );
    if (done != true || !mounted) return;
    AppSnack.show(context, 'Araç eklendi.', kind: AppSnackKind.success);
    await reload();
  }

  Future<void> _editNote(ApartmentVehicles data, VehicleRecord v) async {
    final done = await ApartmentVehicleDialog.show(
      context,
      service: widget.service,
      apartmentId: widget.apartmentId,
      owners: data.owners,
      notice: data.notice,
      vehicle: v,
    );
    if (done != true || !mounted) return;
    AppSnack.show(context, 'Araç güncellendi.', kind: AppSnackKind.success);
    await reload();
  }

  Future<void> _remove(VehicleRecord v) async {
    final ok = await confirmCrmAction(
      context,
      title: 'Aracı çıkar',
      message: '${v.displayPlate} plakalı araç çıkarılacak. Sitede plaka tanıma açıksa artık yetkili araç sayılmaz. Kayıt silinmez, pasifleşir.',
      confirmLabel: 'Çıkar',
      icon: Icons.delete_outline_rounded,
      tone: AppTone.danger,
    );
    if (!ok || !mounted || _busy) return;
    setState(() => _busy = true);
    try {
      await widget.service.removeVehicle(widget.apartmentId, v.id);
      if (!mounted) return;
      AppSnack.show(context, 'Araç çıkarıldı.', kind: AppSnackKind.success);
      await reload();
    } catch (e) {
      if (mounted) AppSnack.show(context, crmMessageOf(e, 'Araç çıkarılamadı. Tekrar deneyin.'), kind: AppSnackKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final secondary = th.bodyMedium?.copyWith(color: context.palette.textSecondary);
    final data = _data;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.lg),
      child: Column(
        key: ValueKey<String>('apt_vehicles_${widget.apartmentId}'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Araçlarım', style: th.titleMedium),
          const SizedBox(height: AppSpace.sm),
          if (_loading) Text('Araçlar yükleniyor...', style: secondary),
          if (!_loading && data == null && _error != null) InlineNotice(message: _error!, onRetry: reload),
          if (data != null) ..._content(data, th, secondary),
        ],
      ),
    );
  }

  List<Widget> _content(ApartmentVehicles data, TextTheme th, TextStyle? secondary) {
    return [
      if (_error != null) ...[InlineNotice(message: _error!, onRetry: reload), const SizedBox(height: AppSpace.sm)],
      if (data.items.isEmpty) Text('Kayıtlı araç yok.', style: secondary),
      for (final v in data.items) _vehicleTile(data, v, th, secondary),
      if (data.canManage) ...[
        const SizedBox(height: AppSpace.sm),
        Text('${data.items.length} / ${data.limit} araç', style: secondary),
        const SizedBox(height: AppSpace.sm),
        InlineNotice(message: data.notice, tone: AppTone.warning),
        const SizedBox(height: AppSpace.sm),
        PrimaryActionButton(
          label: 'Araç ekle',
          icon: Icons.add_rounded,
          variant: AppButtonVariant.outline,
          onPressed: _busy || data.isFull ? null : () => unawaited(_add(data)),
        ),
        if (data.isFull) Text('Araç sınırına ulaştınız. Daha fazlası için site yönetimine başvurun.', style: secondary),
      ] else
        Padding(
          padding: const EdgeInsets.only(top: AppSpace.sm),
          child: Text('Araçları yalnızca daire yöneticisi ekleyip değiştirebilir.', style: secondary),
        ),
    ];
  }

  Widget _vehicleTile(ApartmentVehicles data, VehicleRecord v, TextTheme th, TextStyle? secondary) {
    final owner = v.personName ?? '';
    final note = v.note ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: DecoratedBox(
        key: ValueKey<String>('apt_vehicle_${v.id}'),
        decoration: BoxDecoration(
          border: Border.all(color: context.palette.border),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Icon(Icons.directions_car_rounded, size: 20),
                  Text(v.displayPlate, style: th.titleSmall),
                  if (v.source == kVehicleSourceApartmentAdmin) const StatusChip(label: 'Daire yöneticisi ekledi', tone: AppTone.info),
                ],
              ),
              if (owner.isNotEmpty) Text('Sahibi: $owner', style: secondary),
              if (note.isNotEmpty) Text(note, style: th.bodyMedium),
              if (v.source != kVehicleSourceApartmentAdmin) Text('Ekleyen: ${v.sourceLabel}', style: th.bodySmall?.copyWith(color: context.palette.textSecondary)),
              if (data.canManage)
                Align(
                  alignment: Alignment.centerRight,
                  child: Wrap(
                    spacing: AppSpace.xs,
                    children: [
                      TextButton(onPressed: _busy ? null : () => unawaited(_editNote(data, v)), child: const Text('Notu düzenle')),
                      TextButton(onPressed: _busy ? null : () => unawaited(_remove(v)), child: const Text('Aracı çıkar')),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
