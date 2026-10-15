import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

/// Kısa onay penceresi (araç kaldırma gibi geri alınması zahmetli işler). Onaylanırsa true, vazgeçilirse
/// ya da kapatılırsa false döner.
Future<bool> confirmCrmAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  IconData icon = Icons.help_outline_rounded,
  AppTone tone = AppTone.warning,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AppDialog(
      title: title,
      icon: icon,
      tone: tone,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Vazgeç'),
        ),
        ElevatedButton(
          style: filledToneStyle(dialogContext, tone: tone),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(confirmLabel),
        ),
      ],
      child: Text(message, style: Theme.of(dialogContext).textTheme.bodyMedium),
    ),
  );
  return result ?? false;
}
