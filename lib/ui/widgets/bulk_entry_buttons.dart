import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

/// Boş Kişiler listesindeki «Excel'den yükle» eylemi (EmptyCard içinde): site kurulduktan hemen sonra daire ve
/// kişi bilgilerini dosyadan yüklemek için kısayol.
class BulkEmptyImportAction extends StatelessWidget {
  const BulkEmptyImportAction({super.key, required this.onImport});

  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Daire ve kişi bilgilerini şimdi toplu yükleyin.',
          textAlign: TextAlign.center,
          style: th.bodyMedium?.copyWith(color: context.palette.textSecondary),
        ),
        const SizedBox(height: AppSpace.sm),
        PrimaryActionButton(
          key: const ValueKey<String>('people_empty_bulk_import'),
          label: "Excel'den yükle",
          icon: Icons.upload_file_rounded,
          variant: AppButtonVariant.tonal,
          onPressed: onImport,
        ),
      ],
    );
  }
}
