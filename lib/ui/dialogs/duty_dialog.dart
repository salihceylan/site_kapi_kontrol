import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/team.dart';

/// "Görev ver" penceresi sonucu.
class DutyChoice {
  const DutyChoice({
    required this.duty,
    required this.showInDirectory,
    this.title,
    this.publicPhone,
  });

  final String duty;
  final String? title;
  final String? publicPhone;
  final bool showInDirectory;
}

/// Kişiye yönetim kadrosunda görev verir / görevi günceller: tür (kurul üyesi, denetçi, kapıcı, teknik görevli,
/// danışma, diğer), unvan, rehberde göster ve rehberde görünecek telefon. Telefonu sakinlere göstermeden önce
/// kişinin onayı alınmalıdır (yazılı uyarı).
class DutyDialog extends StatefulWidget {
  const DutyDialog({super.key, required this.personName, this.current});

  final String personName;
  final TeamDuty? current;

  static Future<DutyChoice?> show(BuildContext context, {required String personName, TeamDuty? current}) {
    return showDialog<DutyChoice>(
      context: context,
      builder: (_) => DutyDialog(personName: personName, current: current),
    );
  }

  @override
  State<DutyDialog> createState() => _DutyDialogState();
}

class _DutyDialogState extends State<DutyDialog> {
  late String _duty = widget.current?.duty ?? 'doorman';
  late final TextEditingController _title = TextEditingController(text: widget.current?.title ?? '');
  late final TextEditingController _phone = TextEditingController(text: widget.current?.publicPhone ?? '');
  late bool _show = widget.current?.showInDirectory ?? true;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _title.text.trim();
    if (_duty == 'other' && title.isEmpty) {
      setState(() => _error = '"Diğer" görev için unvan yazın (ör. Bahçıvan).');
      return;
    }
    final phone = _phone.text.trim();
    Navigator.of(context).pop(
      DutyChoice(
        duty: _duty,
        title: title.isEmpty ? null : title,
        publicPhone: phone.isEmpty ? null : phone,
        showInDirectory: _show,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    return AlertDialog(
      title: Text('Görev ver: ${widget.personName}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _duty,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Görev'),
              items: [
                for (final duty in kTeamDuties)
                  DropdownMenuItem<String>(value: duty, child: Text(teamDutyLabel(duty))),
              ],
              onChanged: (value) => setState(() {
                _duty = value ?? _duty;
                _error = null;
              }),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _title,
              maxLength: 60,
              decoration: InputDecoration(
                labelText: _duty == 'other' ? 'Unvan (zorunlu)' : 'Unvan (isteğe bağlı)',
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Rehberde göster'),
              subtitle: const Text('Sakinler adını ve görevini Rehber\'de görür.'),
              value: _show,
              onChanged: (value) => setState(() => _show = value),
            ),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Rehberde görünecek telefon (isteğe bağlı)',
                helperText: 'Sakinlere göstermeden önce kişinin onayını alın.',
                helperMaxLines: 2,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: th.bodySmall?.copyWith(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Vazgeç')),
        FilledButton(onPressed: _submit, child: const Text('Kaydet')),
      ],
    );
  }
}
