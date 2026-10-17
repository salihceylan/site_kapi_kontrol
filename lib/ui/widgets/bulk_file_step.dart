import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/account_data_export.dart' show formatByteSize;
import 'package:site_kapi_kontrol/ui/widgets/bulk_error_notice.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/views/bulk_import_controller.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

/// Adım 2: dosya seçimi. Okuma bir isolate'ta sürer (ilerleme + iptal); hata ve sayfa seçimi bu adımda gösterilir.
class BulkFileStep extends StatelessWidget {
  const BulkFileStep({super.key, required this.controller, required this.onBack, required this.onToMapping});

  final BulkImportController controller;
  final VoidCallback onBack;
  final VoidCallback onToMapping;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final kind = c.kind;
    final hasFile = c.parsed != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${kind?.label ?? 'Tablo'} için bir Excel (.xlsx) ya da CSV dosyası seçin. Bir seferde en çok '
          '5.000 satır yüklenebilir.',
          style: th.bodyMedium?.copyWith(color: p.textSecondary),
        ),
        const SizedBox(height: AppSpace.sm),
        Text(
          'Dosyanın kendisi sunucuya gönderilmez; yalnızca okunan satırlar önizleme ve yükleme için gönderilir.',
          style: th.bodySmall?.copyWith(color: p.textSecondary),
        ),
        const SizedBox(height: AppSpace.lg),
        if (c.parsing) ...[
          _ParsingCard(controller: c),
          const SizedBox(height: AppSpace.lg),
        ],
        if (!c.parsing && c.parseError != null) ...[
          BulkErrorNotice(key: const ValueKey<String>('bulk_parse_error'), message: c.parseError!),
          const SizedBox(height: AppSpace.lg),
        ],
        if (!c.parsing && c.sheetChoices != null) ...[
          _SheetChooser(controller: c),
          const SizedBox(height: AppSpace.lg),
        ],
        if (!c.parsing && hasFile && c.parseError == null) ...[
          _SelectedFile(controller: c, onToMapping: onToMapping),
          const SizedBox(height: AppSpace.lg),
        ],
        PrimaryActionButton(
          key: const ValueKey<String>('bulk_pick_file'),
          label: hasFile || c.fileName != null ? 'Başka Dosya Seç' : 'Dosya Seç',
          icon: Icons.folder_open_rounded,
          variant: hasFile ? AppButtonVariant.tonal : AppButtonVariant.filled,
          loading: c.parsing || c.picking,
          onPressed: c.busy ? null : c.pickAndParse,
        ),
        const SizedBox(height: AppSpace.sm),
        SizedBox(
          width: double.infinity,
          child: TextButton(
            key: const ValueKey<String>('bulk_file_back'),
            onPressed: c.parsing ? null : onBack,
            child: const Text('Geri', textAlign: TextAlign.center),
          ),
        ),
      ],
    );
  }
}

class _ParsingCard extends StatelessWidget {
  const _ParsingCard({required this.controller});

  final BulkImportController controller;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    return AppCard(
      key: const ValueKey<String>('bulk_parsing'),
      padding: listCardPadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            liveRegion: true,
            container: true,
            label: 'Dosya okunuyor',
            child: ExcludeSemantics(
              child: Row(
                children: [
                  const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
                  const SizedBox(width: AppSpace.md),
                  Expanded(child: Text('Dosya okunuyor…', style: th.titleSmall)),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpace.sm),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              key: const ValueKey<String>('bulk_parse_cancel'),
              onPressed: controller.cancelParse,
              child: const Text('İptal'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetChooser extends StatelessWidget {
  const _SheetChooser({required this.controller});

  final BulkImportController controller;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final names = controller.sheetChoices!;
    return AppCard(
      key: const ValueKey<String>('bulk_sheet_chooser'),
      padding: listCardPadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text('Hangi sayfa yüklensin?', style: th.titleMedium),
          ),
          const SizedBox(height: AppSpace.xs),
          Text(
            'Dosyada birden çok sayfa var ve ${controller.kind?.label ?? 'bu tür'} sayfası bulunamadı. Verilerin '
            'olduğu sayfayı seçin.',
            style: th.bodyMedium,
          ),
          const SizedBox(height: AppSpace.md),
          for (final name in names)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.sm),
              child: OutlinedButton(
                key: ValueKey<String>('bulk_sheet_$name'),
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48), alignment: Alignment.centerLeft),
                onPressed: controller.parsing ? null : () => controller.chooseSheet(name),
                child: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
            ),
        ],
      ),
    );
  }
}

class _SelectedFile extends StatelessWidget {
  const _SelectedFile({required this.controller, required this.onToMapping});

  final BulkImportController controller;
  final VoidCallback onToMapping;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final th = Theme.of(context).textTheme;
    final parsed = c.parsed!;
    final size = c.fileSize;
    return AppCard(
      key: const ValueKey<String>('bulk_selected_file'),
      padding: listCardPadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.insert_drive_file_outlined),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Text(
                  '${c.fileName ?? 'Dosya'}${size == null ? '' : ' (${formatByteSize(size)})'}',
                  style: th.titleSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.xs),
          Text(
            '${parsed.table.rows.length - parsed.header.mapping.headerRowIndex - 1} satır okundu. '
            'Sütun eşlemesini gözden geçirebilirsiniz.',
            style: th.bodySmall,
          ),
          const SizedBox(height: AppSpace.md),
          PrimaryActionButton(
            key: const ValueKey<String>('bulk_file_to_mapping'),
            label: 'Sütunları Gözden Geçir',
            icon: Icons.arrow_forward_rounded,
            onPressed: onToMapping,
          ),
        ],
      ),
    );
  }
}
