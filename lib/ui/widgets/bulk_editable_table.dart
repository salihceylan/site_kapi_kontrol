import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/bulk_import.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/views/bulk_import_controller.dart';
import 'package:site_kapi_kontrol/services/bulk_template.dart';

/// Toplu yükleme sırasında yöneticinin verileri Excel görünümünde doğrudan inceleyebileceği,
/// hücre hücre düzenleyebileceği, satır ekleyip silebileceği etkileşimli elektronik tablo bileşeni.
class BulkEditableTable extends StatefulWidget {
  const BulkEditableTable({
    super.key,
    required this.controller,
  });

  final BulkImportController controller;

  @override
  State<BulkEditableTable> createState() => _BulkEditableTableState();
}

class _BulkEditableTableState extends State<BulkEditableTable> {
  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _horizontalScrollController = ScrollController();
  String _searchQuery = '';
  int _page = 0;
  static const int _pageSize = 25;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      final q = _searchCtrl.text.trim().toLowerCase();
      if (q != _searchQuery) {
        setState(() {
          _searchQuery = q;
          _page = 0;
        });
      }
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _horizontalScrollController.dispose();
    super.dispose();
  }

  List<ImportColumn> _visibleColumns() {
    final spec = widget.controller.kindSpec;
    if (spec == null) return const <ImportColumn>[];
    final rows = widget.controller.rows;
    return spec.columns.where((col) {
      if (!kExcludedTemplateKeys.contains(col.key)) return true;
      // Eğer kaldırılan alanlardan biri satırlardan birinde doluysa göster (geriye dönük uyumluluk)
      return rows.any((r) {
        final val = r.cells[col.key];
        return val != null && val.toString().trim().isNotEmpty;
      });
    }).toList();
  }

  List<int> _filteredRowIndices() {
    final rows = widget.controller.rows;
    if (_searchQuery.isEmpty) {
      return List<int>.generate(rows.length, (i) => i);
    }
    final out = <int>[];
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final matchesN = row.n.toString().contains(_searchQuery);
      if (matchesN) {
        out.add(i);
        continue;
      }
      var matchesCell = false;
      for (final val in row.cells.values) {
        if (val != null && val.toString().toLowerCase().contains(_searchQuery)) {
          matchesCell = true;
          break;
        }
      }
      if (matchesCell) {
        out.add(i);
      }
    }
    return out;
  }

  Future<void> _editCell({
    required int realIndex,
    required ImportRow row,
    required ImportColumn col,
  }) async {
    final updated = await showDialog<String?>(
      context: context,
      builder: (_) => _CellEditDialog(
        col: col,
        initialValue: row.cells[col.key]?.toString() ?? '',
        isDuplicateUsername: (lower) => widget.controller.rows.asMap().entries.any(
              (entry) =>
                  entry.key != realIndex &&
                  entry.value.cells['kullanici_adi']?.toString().trim().toLowerCase() == lower,
            ),
      ),
    );
    if (updated != null && mounted) {
      widget.controller.updateCell(realIndex, col.key, updated);
    }
  }

  Future<void> _addNewRow() async {
    final values = await showDialog<Map<String, String>?>(
      context: context,
      builder: (_) => _AddRowDialog(cols: _visibleColumns()),
    );
    if (values != null && mounted) {
      widget.controller.addRow(initialCells: values);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final allRows = widget.controller.rows;
    final cols = _visibleColumns();

    if (allRows.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(AppSpace.lg),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: p.border),
        ),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.table_rows_rounded, size: 40, color: p.textMuted),
              const SizedBox(height: AppSpace.sm),
              Text(
                'Henüz okunmuş veri satırı bulunmuyor.',
                style: th.bodyMedium?.copyWith(color: p.textSecondary),
              ),
            ],
          ),
        ),
      );
    }

    final filteredIndices = _filteredRowIndices();
    final totalCount = filteredIndices.length;
    final totalPages = (totalCount / _pageSize).ceil();
    final effectivePage = _page >= totalPages && totalPages > 0 ? totalPages - 1 : _page;
    final startIdx = effectivePage * _pageSize;
    final endIdx = (startIdx + _pageSize) > totalCount ? totalCount : (startIdx + _pageSize);
    final pageIndices = totalCount == 0 ? const <int>[] : filteredIndices.sublist(startIdx, endIdx);

    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Üst Araç Çubuğu
          Padding(
            padding: const EdgeInsets.all(AppSpace.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.table_chart_rounded, size: 18, color: p.action),
                    const SizedBox(width: AppSpace.xs),
                    Expanded(
                      child: Text(
                        'Excel Tablosu',
                        style: th.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: p.border,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${allRows.length} satır',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: p.textSecondary),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpace.xs),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 32,
                        child: TextField(
                          controller: _searchCtrl,
                          style: const TextStyle(fontSize: 12),
                          decoration: InputDecoration(
                            hintText: 'Tabloda ara...',
                            hintStyle: TextStyle(fontSize: 12, color: p.textMuted),
                            prefixIcon: const Icon(Icons.search_rounded, size: 16),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    padding: EdgeInsets.zero,
                                    icon: const Icon(Icons.clear, size: 14),
                                    onPressed: () => _searchCtrl.clear(),
                                )
                                : null,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpace.xs),
                    OutlinedButton.icon(
                      onPressed: _addNewRow,
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      ),
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Satır Ekle', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Yardım Bilgilendirme Notu
          Container(
            color: AppTone.primary.a.withValues(alpha: 0.05),
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.touch_app_outlined, size: 16, color: AppTone.primary.a),
                const SizedBox(width: AppSpace.xs),
                Expanded(
                  child: Text(
                    'İstediğiniz hücreye dokunarak içeriği doğrudan değiştirebilirsiniz.',
                    style: TextStyle(fontSize: 12, color: p.textSecondary, fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Yatay Kaydırılabilir Excel Görünümlü Tablo (Altta görünür ve sürüklenebilir kaydırma çubuğu)
          Scrollbar(
            controller: _horizontalScrollController,
            thumbVisibility: true,
            trackVisibility: true,
            interactive: true,
            thickness: 8.0,
            radius: const Radius.circular(4),
            child: SingleChildScrollView(
              controller: _horizontalScrollController,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(bottom: 8),
              child: DataTable(
              headingRowColor: WidgetStateProperty.all(p.surface),
              dataRowMinHeight: 40,
              dataRowMaxHeight: 46,
              columnSpacing: 16,
              horizontalMargin: 12,
              headingRowHeight: 42,
              columns: [
                const DataColumn(
                  label: Text('#', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  numeric: true,
                ),
                for (final col in cols)
                  DataColumn(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          col.label,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                        ),
                        if (col.required)
                          const Text('*', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                const DataColumn(
                  label: Text('Sil', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                ),
              ],
              rows: [
                for (final realIdx in pageIndices)
                  _buildDataRow(
                    context: context,
                    realIdx: realIdx,
                    row: allRows[realIdx],
                    cols: cols,
                  ),
              ],
            ),
          ),
          ),
          const Divider(height: 1),

          // Sayfalama Çubuğu
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    totalCount == 0
                        ? 'Kayıt bulunamadı'
                        : '$totalCount satırdan ${startIdx + 1}-$endIdx',
                    style: TextStyle(fontSize: 12, color: p.textSecondary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (totalPages > 1)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.chevron_left_rounded, size: 20),
                        tooltip: 'Önceki Sayfa',
                        onPressed: effectivePage > 0
                            ? () => setState(() => _page = effectivePage - 1)
                            : null,
                      ),
                      Text(
                        '${effectivePage + 1} / $totalPages',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.chevron_right_rounded, size: 20),
                        tooltip: 'Sonraki Sayfa',
                        onPressed: effectivePage < totalPages - 1
                            ? () => setState(() => _page = effectivePage + 1)
                            : null,
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  DataRow _buildDataRow({
    required BuildContext context,
    required int realIdx,
    required ImportRow row,
    required List<ImportColumn> cols,
  }) {
    final p = context.palette;
    final isEven = realIdx % 2 == 0;
    return DataRow(
      color: WidgetStateProperty.resolveWith<Color?>((states) {
        if (states.contains(WidgetState.hovered)) {
          return AppTone.primary.a.withValues(alpha: 0.08);
        }
        return isEven ? null : p.surface.withValues(alpha: 0.5);
      }),
      cells: [
        // Satır No
        DataCell(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: p.border.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${row.n}',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: p.textSecondary),
            ),
          ),
        ),
        // Hücreler
        for (final col in cols)
          DataCell(
            _buildCellContent(row: row, col: col, p: p),
            onTap: () => _editCell(realIndex: realIdx, row: row, col: col),
          ),
        // Satır Silme
        DataCell(
          IconButton(
            icon: Icon(Icons.delete_outline_rounded, size: 18, color: AppTone.danger.a),
            tooltip: 'Satırı Sil',
            onPressed: () => widget.controller.deleteRow(realIdx),
          ),
        ),
      ],
    );
  }

  Widget _buildCellContent({
    required ImportRow row,
    required ImportColumn col,
    required dynamic p,
  }) {
    final val = row.cells[col.key]?.toString();
    final isEmpty = val == null || val.trim().isEmpty;

    if (isEmpty) {
      if (col.required) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.amber.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.amber.shade700, width: 0.8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.warning_amber_rounded, size: 13, color: Colors.amber.shade800),
              const SizedBox(width: 3),
              Text(
                'Boş',
                style: TextStyle(fontSize: 11, color: Colors.amber.shade900, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        );
      }
      return Text(
        '-',
        style: TextStyle(fontSize: 13, color: p.textMuted),
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 220),
      child: Text(
        val,
        style: TextStyle(fontSize: 13, color: p.text),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// Hücre düzenleme penceresi. Metin denetleyicisi pencerenin kendi durumundadır ve pencere ağaçtan çıkınca
/// (kapanış animasyonu bittikten sonra) silinir: çağıran tarafta `showDialog` döner dönmez silmek, kapanış
/// animasyonu sürerken "TextEditingController was used after being disposed" hatası veriyordu.
class _CellEditDialog extends StatefulWidget {
  const _CellEditDialog({required this.col, required this.initialValue, required this.isDuplicateUsername});

  final ImportColumn col;
  final String initialValue;
  final bool Function(String lowerUsername) isDuplicateUsername;

  @override
  State<_CellEditDialog> createState() => _CellEditDialogState();
}

class _CellEditDialogState extends State<_CellEditDialog> {
  late final TextEditingController _ctrl = TextEditingController(text: widget.initialValue);
  String? _fieldError;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _apply() {
    final col = widget.col;
    final text = _ctrl.text.trim();
    if (col.key == 'kullanici_adi' && text.isNotEmpty) {
      // Sunucunun kullanacağı biçimle karşılaştır (tabloda görünen ad = yazılanın sadeleşmiş hali)
      if (widget.isDuplicateUsername(generateUsernameFromFullName(text))) {
        setState(() => _fieldError = 'Bu kullanıcı adı başka bir satırda zaten var!');
        return;
      }
    }
    Navigator.of(context).pop(_ctrl.text);
  }

  @override
  Widget build(BuildContext context) {
    final col = widget.col;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(Icons.edit_note_rounded, color: AppTone.primary.a, size: 24),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Text('Hücreyi Düzenle: ${col.label}', style: const TextStyle(fontSize: 16)),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (col.hint != null && col.hint!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.sm),
              child: Text(
                col.hint!,
                style: TextStyle(fontSize: 12, color: context.palette.textSecondary),
              ),
            ),
          TextField(
            controller: _ctrl,
            autofocus: true,
            decoration: InputDecoration(
              labelText: col.label,
              helperText: col.key == 'kullanici_adi'
                  ? 'Benzersiz kullanıcı adı (örn. ad.soyad)'
                  : (col.required ? 'Bu alan zorunludur' : 'İsteğe bağlı'),
              errorText: _fieldError,
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) {
              if (_fieldError != null) setState(() => _fieldError = null);
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('İptal'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTone.primary.a,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: _apply,
          child: const Text('Uygula'),
        ),
      ],
    );
  }
}

/// Yeni satır penceresi; sütun başına metin denetleyicileri pencereyle birlikte yaşar ve silinir
/// (bkz. [_CellEditDialog]). "Ekle" girilen değerleri döndürür, "İptal" null.
class _AddRowDialog extends StatefulWidget {
  const _AddRowDialog({required this.cols});

  final List<ImportColumn> cols;

  @override
  State<_AddRowDialog> createState() => _AddRowDialogState();
}

class _AddRowDialogState extends State<_AddRowDialog> {
  late final Map<String, TextEditingController> _ctrls = {
    for (final col in widget.cols) col.key: TextEditingController(),
  };

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(Icons.add_circle_outline_rounded, color: AppTone.primary.a),
          const SizedBox(width: AppSpace.sm),
          const Expanded(
            child: Text('Yeni Satır Ekle'),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final col in widget.cols)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: TextField(
                    controller: _ctrls[col.key],
                    decoration: InputDecoration(
                      labelText: '${col.label}${col.required ? ' *' : ''}',
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('İptal'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTone.primary.a,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: () => Navigator.of(context).pop(<String, String>{
            for (final entry in _ctrls.entries)
              if (entry.value.text.isNotEmpty) entry.key: entry.value.text,
          }),
          child: const Text('Ekle'),
        ),
      ],
    );
  }
}
