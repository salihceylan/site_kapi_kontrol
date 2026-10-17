import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

/// Kişiler ekranındaki «Toplu Yükle» ve «Dışa Aktar» giriş düğmeleri (yalnız site yöneticisi / süper kullanıcı;
/// kurul ve görevli bu düğmeleri GÖRMEZ). Dar ekranda alt alta sarar (`Wrap`).
class BulkEntryActions extends StatelessWidget {
  const BulkEntryActions({super.key, required this.onImport, required this.onExport});

  final VoidCallback onImport;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpace.sm,
      runSpacing: AppSpace.sm,
      children: [
        PrimaryActionButton(
          key: const ValueKey<String>('people_bulk_import'),
          label: 'Toplu Yükle',
          icon: Icons.upload_file_rounded,
          variant: AppButtonVariant.tonal,
          expand: false,
          onPressed: onImport,
        ),
        PrimaryActionButton(
          key: const ValueKey<String>('people_bulk_export'),
          label: 'Dışa Aktar',
          icon: Icons.download_rounded,
          variant: AppButtonVariant.tonal,
          expand: false,
          onPressed: onExport,
        ),
      ],
    );
  }
}

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
