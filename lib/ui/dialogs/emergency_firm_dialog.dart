// Acil durum ekranı: yöneticinin asansör bakım firmasını (ad + acil arıza telefonu) eklediği / düzenlediği / kaldırdığı pencere.
import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/emergency_models.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/phone_input.dart';

/// Pencerenin sonucu: [name] ve [phone] ikisi de null ise firma KALDIRILIR. Vazgeçilirse pencere null döner.
typedef EmergencyFirmValues = ({String? name, String? phone});

/// Asansör bakım firması penceresi. Telefon kısa numara ("444 1 234"), sabit hat ya da cep olabilir ([ServicePhoneInputFormatter]).
Future<EmergencyFirmValues?> showEmergencyFirmDialog(BuildContext context, EmergencySite site) {
  return showDialog<EmergencyFirmValues>(
    context: context,
    builder: (context) => _EmergencyFirmDialog(site: site),
  );
}

class _EmergencyFirmDialog extends StatefulWidget {
  const _EmergencyFirmDialog({required this.site});

  final EmergencySite site;

  @override
  State<_EmergencyFirmDialog> createState() => _EmergencyFirmDialogState();
}

class _EmergencyFirmDialogState extends State<_EmergencyFirmDialog> {
  late final TextEditingController _name = TextEditingController(text: widget.site.elevatorFirmName ?? '');
  late final TextEditingController _phone = TextEditingController(text: servicePhoneInitial(widget.site.elevatorFirmPhone));
  String? _phoneError;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    final error = validateServicePhoneInput(_phone.text, stored: widget.site.elevatorFirmPhone);
    if (error != null) {
      setState(() => _phoneError = error);
      return;
    }
    final phone = servicePhoneForSave(_phone.text, stored: widget.site.elevatorFirmPhone);
    if (phone == null) {
      // Telefon yok: ad da yoksa firma kaldırılır, ad varsa telefon istenir (telefonsuz firma acil durumda işe yaramaz).
      if (name.isNotEmpty) {
        setState(() => _phoneError = 'Firma adını yazdıysanız telefonunu da yazın.');
        return;
      }
      Navigator.of(context).pop((name: null, phone: null));
      return;
    }
    Navigator.of(context).pop((name: name.isEmpty ? null : name, phone: phone));
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final hasFirm = widget.site.elevatorFirmPhone != null || widget.site.elevatorFirmName != null;
    return AlertDialog(
      title: const Text('Asansör bakım firması'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Asansör arızasında sakinler bu firmayı tek dokunuşla arar. Telefon, bakım sözleşmesindeki acil arıza hattı olmalıdır.',
              style: th.bodyMedium?.copyWith(color: context.palette.textSecondary),
            ),
            const SizedBox(height: AppSpace.md),
            TextField(
              key: const ValueKey<String>('emergency_firm_name'),
              controller: _name,
              maxLength: 120,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Firma adı (isteğe bağlı)'),
            ),
            TextField(
              key: const ValueKey<String>('emergency_firm_phone'),
              controller: _phone,
              keyboardType: TextInputType.phone,
              inputFormatters: const [ServicePhoneInputFormatter()],
              onChanged: (_) {
                if (_phoneError != null) setState(() => _phoneError = null);
              },
              decoration: InputDecoration(
                labelText: 'Acil arıza telefonu',
                hintText: phoneFieldHintAny,
                helperText: 'Sabit hat ya da cep: +90 XXX XXX XX XX. Kısa numaralar (444 1 234) olduğu gibi yazılır.',
                helperMaxLines: 3,
                errorText: _phoneError,
                errorMaxLines: 3,
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (hasFirm)
          TextButton(
            key: const ValueKey<String>('emergency_firm_remove'),
            onPressed: () => Navigator.of(context).pop((name: null, phone: null)),
            child: const Text('Kaldır'),
          ),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Vazgeç')),
        FilledButton(
          key: const ValueKey<String>('emergency_firm_save'),
          onPressed: _save,
          child: const Text('Kaydet'),
        ),
      ],
    );
  }
}
