import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/person_record.dart';
import 'package:site_kapi_kontrol/models/vehicle_record.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/crm_pickers.dart';
import 'package:site_kapi_kontrol/ui/dialogs/large_dialog_parts.dart';
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/helpers/form_validation.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/helpers/plate_input.dart';
import 'package:site_kapi_kontrol/ui/widgets/crm_parts.dart';

// Plaka kuralı ve giriş süzgeçleri artık ui/helpers/plate_input.dart'ta; eski içe aktarmalar bozulmasın diye buradan da dışa verilir.
export 'package:site_kapi_kontrol/ui/helpers/plate_input.dart';

/// "Araç Ekle" penceresi (Platform Faz 2a): plaka ve isteğe bağlı not. [person] verilirse araç o kişiye
/// eklenir (kişi kartından); verilmezse kişi seçici gösterilir (Araçlar sekmesinden).
///
/// Plaka Türk plakası olmalıdır (il kodu 01-81 + 1-3 harf + 2-4 rakam) ve yazarken "34 ABC 123" biçimine girilir
/// ([PlateInputFormatter]); sunucu aynı kuralı uygular (`34 ABC 123` -> `34ABC123`). Aynı sitede aktif aynı plaka 409
/// `PLATE_EXISTS`, geçersiz biçim 400 `PLATE_INVALID` döner ve mesaj pencerede gösterilir. Başarıda
/// eklenen [VehicleRecord] ile kapanır.
class VehicleDialog extends StatefulWidget {
  const VehicleDialog({super.key, required this.scope, this.person});

  final PeopleScope scope;

  /// Sabit araç sahibi; null ise kişi seçilir.
  final PersonSummary? person;

  static const int maxNoteLength = 200;

  static Future<VehicleRecord?> show(
    BuildContext context, {
    required PeopleScope scope,
    PersonSummary? person,
  }) {
    return showDialog<VehicleRecord>(
      context: context,
      barrierDismissible: false,
      builder: (_) => VehicleDialog(scope: scope, person: person),
    );
  }

  @override
  State<VehicleDialog> createState() => _VehicleDialogState();
}

class _VehicleDialogState extends State<VehicleDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _plate = TextEditingController();
  final TextEditingController _note = TextEditingController();
  late PersonSummary? _person = widget.person;
  String? _personError;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _plate.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickPerson() async {
    final picked = await showPersonPicker(context, widget.scope);
    if (picked == null || !mounted) return;
    setState(() {
      _person = picked;
      _personError = null;
    });
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final valid = validateForm(_formKey);
    final person = _person;
    if (person == null) {
      setState(() {
        _personError = 'Araç sahibini seçin.';
        _error = kFixFieldsMessage;
      });
      return;
    }
    if (!valid) {
      setState(() => _error = kFixFieldsMessage);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final vehicle = await widget.scope.authService.createVehicle(
        widget.scope.siteCode,
        person.id,
        _plate.text,
        note: _note.text,
      );
      if (!mounted) return;
      popIfCurrent(context, vehicle);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = crmMessageOf(
          e,
          'Araç eklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
        );
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final fixed = widget.person;
    return PopScope(
      canPop: !_submitting,
      child: AppDialog(
        title: 'Araç Ekle',
        subtitle: widget.scope.siteName.isEmpty ? null : widget.scope.siteName,
        icon: Icons.directions_car_rounded,
        actions: [
          TextButton(
            onPressed: _submitting ? null : () => popIfCurrent(context),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            onPressed: _submitting ? null : _submit,
            child: Text(_submitting ? 'Ekleniyor...' : 'Ekle'),
          ),
        ],
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) CrmFormError(message: _error!),
              if (fixed != null)
                DialogPanel(
                  child: Text(
                    'Araç sahibi: ${fixed.fullName}',
                    style: th.titleSmall,
                  ),
                )
              else
                CrmPickerField(
                  key: const ValueKey<String>('vehicle_person'),
                  label: 'Araç sahibi',
                  icon: Icons.person_rounded,
                  value: _person?.fullName,
                  placeholder: 'Kişi seçmek için dokunun',
                  errorText: _personError,
                  enabled: !_submitting,
                  onTap: _pickPerson,
                ),
              const SizedBox(height: AppSpace.md),
              TextFormField(
                key: const ValueKey<String>('vehicle_plate'),
                controller: _plate,
                enabled: !_submitting,
                inputFormatters: const [PlateInputFormatter()],
                textCapitalization: TextCapitalization.characters,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: 'Plaka',
                  hintText: '34 ABC 123',
                  prefixIcon: Icon(Icons.pin_rounded),
                ),
                validator: validatePlate,
              ),
              const SizedBox(height: AppSpace.md),
              TextFormField(
                key: const ValueKey<String>('vehicle_note'),
                controller: _note,
                enabled: !_submitting,
                maxLength: VehicleDialog.maxNoteLength,
                decoration: const InputDecoration(
                  labelText: 'Not (isteğe bağlı)',
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
