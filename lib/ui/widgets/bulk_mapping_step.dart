import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/bulk_import.dart';
import 'package:site_kapi_kontrol/services/bulk_header_mapper.dart';
import 'package:site_kapi_kontrol/ui/widgets/bulk_error_notice.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/views/bulk_import_controller.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

/// Excel sütun harfi: 0 -> A, 26 -> AA.
String bulkColumnLetters(int index) {
  var n = index + 1;
  final out = <int>[];
  while (n > 0) {
    out.add(0x41 + (n - 1) % 26);
    n = (n - 1) ~/ 26;
  }
  return String.fromCharCodes(out.reversed);
}

/// Adım 3: sütun eşleme. Otomatik eşleşme özeti; zorunlu sütun eksikse / iki sütun aynı alana düşerse devam
/// KAPALI ve nedeni yazılır; her alan için açılır listeyle düzeltilir; tanınmayan sütunlar «yok sayılacak».
class BulkMappingStep extends StatelessWidget {
  const BulkMappingStep({super.key, required this.controller, required this.onBack});

  final BulkImportController controller;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final mapping = c.mapping;
    final kindSpec = c.kindSpec;
    final parsed = c.parsed;
    if (mapping == null || kindSpec == null || parsed == null) {
      return const InlineNotice(message: 'Okunmuş dosya bulunamadı. Geri dönüp dosyayı yeniden seçin.');
    }
    final dataRows = parsed.table.rows.length - mapping.headerRowIndex - 1;
    final blockers = _blockers(mapping, kindSpec);
    final canProceed = blockers.isEmpty && !c.previewing;
    final ignored = mapping.ignoredColumns();

    Widget confirm = PrimaryActionButton(
      key: const ValueKey<String>('bulk_mapping_continue'),
      label: 'Önizlemeyi Hazırla',
      icon: Icons.fact_check_rounded,
      loading: c.previewing,
      onPressed: canProceed ? c.confirmMapping : null,
    );
    if (blockers.isNotEmpty) {
      confirm = Semantics(
        container: true,
        excludeSemantics: true,
        button: true,
        enabled: false,
        label: 'Önizlemeyi Hazırla',
        hint: blockers.first,
        child: confirm,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Dosyanızın sütunları aşağıdaki alanlarla eşlendi. Yanlış olanı düzeltin; bir alanı boş bırakabilirsiniz.',
          style: th.bodyMedium?.copyWith(color: p.textSecondary),
        ),
        const SizedBox(height: AppSpace.md),
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.xs,
          children: [
            if (c.fileName != null) InfoChip(c.fileName!),
            if (parsed.table.sheetName != null) InfoChip('Sayfa: ${parsed.table.sheetName}'),
            if (parsed.table.encodingNote != null) InfoChip(parsed.table.encodingNote!),
            InfoChip('Başlık: ${mapping.headerN}. satır'),
            InfoChip('$dataRows satır okundu'),
          ],
        ),
        if (c.parsed!.suggestedKind != null) ...[
          const SizedBox(height: AppSpace.md),
          InlineNotice(
            key: const ValueKey<String>('bulk_suggest_kind'),
            tone: AppTone.warning,
            message:
                'Bu dosyanın başlıkları «${c.parsed!.suggestedKind!.label}» türüne daha çok benziyor. Yanlış türü '
                'seçmiş olabilirsiniz; devam edebilir ya da geri dönüp türü değiştirebilirsiniz.',
          ),
        ],
        if (c.uncachedFormulaCells > 0) ...[
          const SizedBox(height: AppSpace.md),
          InlineNotice(
            key: const ValueKey<String>('bulk_uncached_formulas'),
            tone: AppTone.warning,
            message:
                '${c.uncachedFormulaCells} hücrede formül var ama sonucu dosyada kayıtlı değil; bu hücreler BOŞ '
                'okundu. Dosyayı Excel içinde açıp kaydederek formül sonuçlarını yazdırın ve yeniden yükleyin.',
          ),
        ],
        if (c.mappingError != null) ...[
          const SizedBox(height: AppSpace.md),
          BulkErrorNotice(key: const ValueKey<String>('bulk_mapping_error'), message: c.mappingError!),
        ],
        if (blockers.isNotEmpty) ...[
          const SizedBox(height: AppSpace.md),
          InlineNotice(
            key: const ValueKey<String>('bulk_mapping_blockers'),
            tone: AppTone.warning,
            message: 'Devam etmek için: ${blockers.join(' ')}',
          ),
        ],
        const SizedBox(height: AppSpace.lg),
        for (final column in kindSpec.columns) ...[
          _FieldRow(controller: c, column: column, mapping: mapping),
          const SizedBox(height: AppSpace.md),
        ],
        if (ignored.isNotEmpty) ...[
          InlineNotice(
            key: const ValueKey<String>('bulk_ignored_columns'),
            tone: AppTone.info,
            message:
                'Yok sayılacak sütunlar: ${_ignoredText(mapping, ignored)}. Bu sütunlardaki veriler yüklenmez.',
          ),
          const SizedBox(height: AppSpace.lg),
        ],
        confirm,
        const SizedBox(height: AppSpace.sm),
        SizedBox(
          width: double.infinity,
          child: TextButton(
            key: const ValueKey<String>('bulk_mapping_back'),
            onPressed: c.previewing ? null : onBack,
            child: const Text('Geri', textAlign: TextAlign.center),
          ),
        ),
      ],
    );
  }

  static List<String> _blockers(ColumnMapping mapping, ImportKindSpec spec) {
    final out = <String>[];
    for (final column in mapping.missingRequired(spec)) {
      if (!mapping.conflicts.containsKey(column.key)) {
        out.add('«${column.label}» alanı için bir sütun seçin.');
      }
    }
    for (final key in mapping.conflicts.keys) {
      final label = spec.column(key)?.label ?? key;
      out.add('«$label» alanına birden çok sütun uyuyor, birini seçin.');
    }
    return out;
  }

  static String _ignoredText(ColumnMapping mapping, List<int> ignored) {
    const maxShown = 8;
    final names = <String>[
      for (final i in ignored.take(maxShown)) '«${mapping.headers[i]}»',
    ];
    final rest = ignored.length - maxShown;
    return rest > 0 ? '${names.join(', ')} ve $rest sütun daha' : names.join(', ');
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({required this.controller, required this.column, required this.mapping});

  final BulkImportController controller;
  final ImportColumn column;
  final ColumnMapping mapping;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final current = mapping.assignment[column.key];
    final conflict = mapping.conflicts[column.key];
    final missing = column.required && current == null;
    final tone = conflict != null || missing ? AppTone.warning : null;
    final locked = controller.previewing;
    return AppCard(
      key: ValueKey<String>('bulk_field_${column.key}'),
      tone: tone,
      padding: listCardPadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(column.label, style: th.titleSmall),
              if (column.required) const InfoChip('Zorunlu', tone: AppTone.primary),
            ],
          ),
          if (column.hint != null) ...[
            const SizedBox(height: AppSpace.xs),
            Text(column.hint!, style: th.bodySmall?.copyWith(color: p.textSecondary)),
          ],
          if (conflict != null) ...[
            const SizedBox(height: AppSpace.sm),
            Text(
              'Birden çok sütun bu alana uyuyor (${conflict.map(bulkColumnLetters).join(', ')}). Birini seçin.',
              style: th.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: AppTone.warning.ink(p)),
            ),
          ] else if (missing) ...[
            const SizedBox(height: AppSpace.sm),
            Text(
              'Bu alan zorunlu: dosyada karşılığı bulunamadı. Sütunu seçin.',
              style: th.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: AppTone.warning.ink(p)),
            ),
          ],
          const SizedBox(height: AppSpace.sm),
          DropdownButtonFormField<int?>(
            key: ValueKey<String>('bulk_map_${column.key}_${current ?? 'none'}'),
            isExpanded: true,
            initialValue: current,
            dropdownColor: p.surface,
            style: th.bodyMedium?.copyWith(color: p.text),
            decoration: InputDecoration(
              labelText: '${column.label} için dosyadaki sütun',
              prefixIcon: const Icon(Icons.view_column_rounded),
            ),
            items: [
              const DropdownMenuItem<int?>(
                value: null,
                child: Text('Eşleme yok (boş bırak)', maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              for (var i = 0; i < mapping.headers.length; i++)
                if (mapping.headers[i].isNotEmpty)
                  DropdownMenuItem<int?>(
                    value: i,
                    child: Text(
                      '${bulkColumnLetters(i)} · ${mapping.headers[i]}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
            ],
            onChanged: locked ? null : (value) => controller.assign(column.key, value),
          ),
        ],
      ),
    );
  }
}
