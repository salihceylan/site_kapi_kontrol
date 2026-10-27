// "Araç ekle" / "Notu düzenle" penceresi (Dairem > Araçlarım). Plaka Türk plakası olmalıdır (il kodu 01-81); sunucu da aynı kuralı uygular.
// Araç sahibi: dairenin aktif sakinlerinden biri (varsayılan daire yöneticisi). Sözleşme: docs/PLATFORM_DAIRE_YONETIMI.md ("Araçlar").
import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/apartment_vehicles.dart';
import 'package:site_kapi_kontrol/models/vehicle_record.dart';
import 'package:site_kapi_kontrol/services/apartment_management_api.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/large_dialog_parts.dart';
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/helpers/form_validation.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart' show crmMessageOf;
import 'package:site_kapi_kontrol/ui/helpers/plate_input.dart';
import 'package:site_kapi_kontrol/ui/widgets/crm_parts.dart';

class ApartmentVehicleDialog extends StatefulWidget {
  const ApartmentVehicleDialog({
    super.key,
    required this.service,
    required this.apartmentId,
    required this.owners,
    required this.notice,
    this.vehicle,
  });

  final ApartmentManagementService service;
  final int apartmentId;
  final List<AptVehicleOwner> owners;
  final String notice;

  /// Verilirse düzenleme (yalnız not ve sahip; plaka değişmez), verilmezse yeni araç.
  final VehicleRecord? vehicle;

  static const int maxNoteLength = 200;

  /// Başarıda true ile kapanır (çağıran listeyi yeniler).
  static Future<bool?> show(
    BuildContext context, {
    required ApartmentManagementService service,
    required int apartmentId,
    required List<AptVehicleOwner> owners,
    required String notice,
    VehicleRecord? vehicle,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ApartmentVehicleDialog(
        service: service,
        apartmentId: apartmentId,
        owners: owners,
        notice: notice,
        vehicle: vehicle,
      ),
    );
  }

  @override
  State<ApartmentVehicleDialog> createState() => _ApartmentVehicleDialogState();
}

class _ApartmentVehicleDialogState extends State<ApartmentVehicleDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _plate = TextEditingController();
  late final TextEditingController _note = TextEditingController(text: widget.vehicle?.note ?? '');
  late int? _owner = _initialOwner();
  bool _submitting = false;
  String? _error;

  bool get _editing => widget.vehicle != null;

  int? _initialOwner() {
    final current = widget.vehicle?.personId;
    if (current != null && widget.owners.any((o) => o.personId == current)) return current;
    for (final o in widget.owners) {
      if (o.isDefault) return o.personId;
    }
    return widget.owners.isEmpty ? null : widget.owners.first.personId;
  }

  @override
  void dispose() {
    _plate.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!validateForm(_formKey)) {
      setState(() => _error = kFixFieldsMessage);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final vehicle = widget.vehicle;
      if (vehicle == null) {
        await widget.service.addVehicle(
          widget.apartmentId,
          plate: _plate.text.trim(),
          note: _note.text.trim().isEmpty ? null : _note.text.trim(),
          personId: _owner,
        );
      } else {
        await widget.service.updateVehicle(
          widget.apartmentId,
          vehicle.id,
          note: _note.text.trim(),
          personId: _owner != null && _owner != vehicle.personId ? _owner : null,
        );
      }
      if (!mounted) return;
      popIfCurrent(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = crmMessageOf(e, _editing ? 'Araç güncellenemedi. Tekrar deneyin.' : 'Araç eklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.');
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final vehicle = widget.vehicle;
    return PopScope(
      canPop: !_submitting,
      child: AppDialog(
        title: _editing ? 'Notu düzenle' : 'Araç ekle',
        icon: Icons.directions_car_rounded,
        actions: [
          TextButton(onPressed: _submitting ? null : () => popIfCurrent(context), child: const Text('Vazgeç')),
          ElevatedButton(
            onPressed: _submitting ? null : _submit,
            child: Text(_submitting ? 'Kaydediliyor...' : (_editing ? 'Kaydet' : 'Ekle')),
          ),
        ],
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) CrmFormError(message: _error!),
              if (!_editing) ...[
                InlineNotice(message: widget.notice, tone: AppTone.warning),
                const SizedBox(height: AppSpace.md),
              ],
              if (vehicle != null)
                DialogPanel(child: Text('Plaka: ${vehicle.displayPlate}', style: th.titleSmall))
              else
                TextFormField(
                  key: const ValueKey<String>('apt_vehicle_plate'),
                  controller: _plate,
                  enabled: !_submitting,
                  inputFormatters: const [PlateInputFormatter()],
                  textCapitalization: TextCapitalization.characters,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    labelText: 'Plaka',
                    hintText: '34 ABC 123',
                    helperText: 'İl kodu 01-81, 1-3 harf, 2-4 rakam',
                    prefixIcon: Icon(Icons.pin_rounded),
                  ),
                  validator: validatePlate,
                ),
              const SizedBox(height: AppSpace.md),
              if (widget.owners.length > 1) ...[
                DropdownButtonFormField<int>(
                  key: const ValueKey<String>('apt_vehicle_owner'),
                  initialValue: _owner,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Araç sahibi', prefixIcon: Icon(Icons.person_rounded)),
                  items: [for (final o in widget.owners) DropdownMenuItem<int>(value: o.personId, child: Text(o.name, overflow: TextOverflow.ellipsis))],
                  onChanged: _submitting ? null : (v) => setState(() => _owner = v),
                ),
                const SizedBox(height: AppSpace.md),
              ],
              TextFormField(
                key: const ValueKey<String>('apt_vehicle_note'),
                controller: _note,
                enabled: !_submitting,
                maxLength: ApartmentVehicleDialog.maxNoteLength,
                decoration: const InputDecoration(
                  labelText: 'Not (isteğe bağlı)',
                  hintText: 'Marka, model, renk',
                  prefixIcon: Icon(Icons.notes_rounded),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
