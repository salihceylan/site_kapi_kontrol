import 'dart:async';

import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:site_kapi_kontrol/models/bulk_import.dart';
import 'package:site_kapi_kontrol/services/bulk_choices.dart';
import 'package:site_kapi_kontrol/services/bulk_login_name.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/plate_input.dart';
import 'package:site_kapi_kontrol/ui/views/bulk_import_controller.dart';
import 'package:site_kapi_kontrol/services/bulk_template.dart';

/// Tablo sütunu: şablon sütunu ya da sanal «Kullanıcı Adı» sütunu.
class _TableColumn {
  const _TableColumn.spec(ImportColumn this.column) : isLogin = false;
  const _TableColumn.login() : column = null, isLogin = true;

  final ImportColumn? column;
  final bool isLogin;

  String get label => isLogin ? 'Kullanıcı Adı' : column!.label;
  bool get required => !isLogin && column!.required;
}

/// Toplu yükleme sırasında yöneticinin verileri Excel görünümünde doğrudan inceleyebileceği,
/// hücre hücre düzenleyebileceği, satır ekleyip silebileceği etkileşimli elektronik tablo bileşeni.
///
/// - Seçim listesi sütunları (İlişki, Borç Sorumlusu ...) serbest metinle DEĞİL açılır listeyle düzenlenir.
/// - Kişi türlerinde «Kullanıcı Adı» sütunu sistemin seçtiği adı gösterir; yönetici değiştirebilir, ancak yeni ad sunucudaki denetimi (biçim + bu
///   sitedeki kullanılabilirlik) geçmeden kabul edilmez. Mevcut hesaba bağlanan satırlarda ad salt okunurdur.
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

  BulkImportController get _c => widget.controller;

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

  List<_TableColumn> _visibleColumns() {
    final spec = _c.kindSpec;
    if (spec == null) return const <_TableColumn>[];
    final rows = _c.rows;
    final out = <_TableColumn>[];
    for (final col in spec.columns) {
      if (kExcludedTemplateKeys.contains(col.key)) {
        // Eğer kaldırılan alanlardan biri satırlardan birinde doluysa göster (geriye dönük uyumluluk)
        final used = rows.any((r) {
          final val = r.cells[col.key];
          return val != null && val.toString().trim().isNotEmpty;
        });
        if (!used) continue;
      }
      out.add(_TableColumn.spec(col));
      // Kullanıcı adı, Ad Soyad'ın hemen yanında: sistem verir, yönetici değiştirebilir.
      if (col.key == 'ad_soyad' && _c.hasLoginColumn) out.add(const _TableColumn.login());
    }
    return out;
  }

  List<int> _filteredRowIndices() {
    final rows = _c.rows;
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
      if (!matchesCell && (_c.loginNameOf(row)?.toLowerCase().contains(_searchQuery) ?? false)) matchesCell = true;
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
    final choices = choicesFor(col);
    if (choices.isNotEmpty) {
      // Seçim listesi sütunu: serbest metin DEĞİL, açılır liste.
      final current = row.cells[col.key]?.toString() ?? '';
      final selected = await showDialog<String?>(
        context: context,
        builder: (_) => _EnumEditDialog(
          column: col,
          choices: choices,
          currentText: current,
          matched: current.trim().isEmpty ? null : matchChoice(_c.kindSpec, col, current),
        ),
      );
      if (selected != null && mounted) {
        _c.updateCell(realIndex, col.key, selected);
      }
      return;
    }
    final updated = await showDialog<String?>(
      context: context,
      builder: (_) => _CellEditDialog(col: col, initialValue: row.cells[col.key]?.toString() ?? ''),
    );
    if (updated != null && mounted) {
      _c.updateCell(realIndex, col.key, updated);
    }
  }

  Future<void> _editLoginName({required int realIndex, required ImportRow row}) async {
    final result = await showDialog<_LoginNameResult?>(
      context: context,
      builder: (_) => _LoginNameDialog(controller: _c, row: row),
    );
    if (result == null || !mounted) return;
    _c.updateCell(realIndex, kLoginNameKey, result.reset ? null : result.value);
  }

  Future<void> _addNewRow() async {
    final cols = <ImportColumn>[
      for (final col in _visibleColumns())
        if (!col.isLogin) col.column!,
    ];
    final values = await showDialog<Map<String, String>?>(
      context: context,
      builder: (_) => _AddRowDialog(cols: cols),
    );
    if (values != null && mounted) {
      _c.addRow(initialCells: values);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final allRows = _c.rows;
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
    final problems = _c.loginProblems;

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
                    _c.hasLoginColumn
                        ? 'Hücreye dokunarak değiştirebilirsiniz. İlişki gibi alanlar listeden seçilir; kullanıcı adlarını sistem verir, '
                              'değiştirirseniz sistemde kullanılmayan bir ad olmalıdır.'
                        : 'İstediğiniz hücreye dokunarak içeriği doğrudan değiştirebilirsiniz. İlişki gibi alanlar listeden seçilir.',
                    key: const ValueKey<String>('bulk_table_help'),
                    style: TextStyle(fontSize: 12, color: p.textSecondary, fontWeight: FontWeight.w500),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          if (_c.hasLoginColumn) _LoginStatusBar(controller: _c),
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
                    problem: problems[allRows[realIdx].n],
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
    required List<_TableColumn> cols,
    String? problem,
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
          if (col.isLogin)
            DataCell(
              _buildLoginCell(row: row, problem: problem, p: p),
              onTap: _c.isLoginEditable(row) ? () => _editLoginName(realIndex: realIdx, row: row) : null,
            )
          else
            DataCell(
              _buildCellContent(row: row, col: col.column!, p: p),
              showEditIcon: choicesFor(col.column!).isNotEmpty,
              onTap: () => _editCell(realIndex: realIdx, row: row, col: col.column!),
            ),
        // Satır Silme
        DataCell(
          IconButton(
            icon: Icon(Icons.delete_outline_rounded, size: 18, color: AppTone.danger.a),
            tooltip: 'Satırı Sil',
            onPressed: () => _c.deleteRow(realIdx),
          ),
        ),
      ],
    );
  }

  /// «Kullanıcı Adı» hücresi: sistemin seçtiği ad (dokununca değiştirilir), mevcut hesabın adı (salt okunur) ya da hesap açılmama nedeni.
  Widget _buildLoginCell({required ImportRow row, required String? problem, required dynamic p}) {
    final proposal = _c.proposalOf(row);
    final name = _c.loginNameOf(row);
    TextStyle style([Color? color, FontWeight? weight]) => TextStyle(fontSize: 13, color: color ?? p.text, fontWeight: weight);

    if (proposal == null) {
      if (_c.proposalsLoading) {
        return Row(
          key: ValueKey<String>('bulk_login_loading_${row.n}'),
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 6),
            Text('Hazırlanıyor…', style: style(p.textMuted)),
          ],
        );
      }
      return Text('-', style: style(p.textMuted));
    }

    switch (proposal.status) {
      case AccountProposalStatus.rejected:
        return Tooltip(
          message: problem ?? proposal.message ?? 'Kullanıcı adı kabul edilmedi.',
          child: Row(
            key: ValueKey<String>('bulk_login_problem_${row.n}'),
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, size: 15, color: AppTone.danger.a),
              const SizedBox(width: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 240),
                child: Text(
                  problem ?? proposal.message ?? 'Kullanıcı adı kabul edilmedi.',
                  style: style(AppTone.danger.a, FontWeight.w600),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      case AccountProposalStatus.existing:
        return Tooltip(
          message: 'Bu kişi mevcut bir hesaba bağlanır; kullanıcı adı değiştirilemez.',
          child: Row(
            key: ValueKey<String>('bulk_login_existing_${row.n}'),
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline_rounded, size: 14, color: p.textMuted),
              const SizedBox(width: 4),
              Text(name ?? 'Mevcut hesap', style: style(p.textSecondary)),
            ],
          ),
        );
      case AccountProposalStatus.emailInUse:
        return Tooltip(
          message: 'Bu e-posta başka bir hesaba ait; kişi kaydedilir ama hesap açılmaz.',
          child: Text('Hesap açılmaz', key: ValueKey<String>('bulk_login_none_${row.n}'), style: style(p.textMuted)),
        );
      case AccountProposalStatus.shared:
        return Tooltip(
          message: 'Aynı kişi dosyada başka satırda da var; tek hesap açılır.',
          child: Text(
            proposal.line == null ? 'Aynı hesap' : 'Satır ${proposal.line} ile aynı hesap',
            key: ValueKey<String>('bulk_login_shared_${row.n}'),
            style: style(p.textMuted),
          ),
        );
      case AccountProposalStatus.unavailable:
        return Text('-', style: style(p.textMuted));
      case AccountProposalStatus.create:
        final custom = _c.overrideOf(row) != null;
        final shown = problem != null;
        return Tooltip(
          message: shown ? problem : (custom ? 'Sizin seçtiğiniz kullanıcı adı. Değiştirmek için dokunun.' : 'Sistemin seçtiği kullanıcı adı. Değiştirmek için dokunun.'),
          child: Row(
            key: ValueKey<String>('bulk_login_name_${row.n}'),
            mainAxisSize: MainAxisSize.min,
            children: [
              if (shown) ...[
                Icon(Icons.error_outline_rounded, size: 15, color: AppTone.danger.a),
                const SizedBox(width: 4),
              ],
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 240),
                child: Text(
                  shown ? problem : (name ?? '-'),
                  style: style(shown ? AppTone.danger.a : null, custom ? FontWeight.w700 : null),
                  maxLines: shown ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (custom && !shown) ...[
                const SizedBox(width: 4),
                Icon(Icons.edit_rounded, size: 12, color: p.textMuted),
              ],
            ],
          ),
        );
    }
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

/// Kullanıcı adı önerilerinin durumu: hazırlanıyor / yenileniyor / hata (yeniden dene) / sorun varsa uyarı. Yüklemeyi yalnız gerçek sorunlar engeller.
class _LoginStatusBar extends StatelessWidget {
  const _LoginStatusBar({required this.controller});

  final BulkImportController controller;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final c = controller;
    final problems = c.loginProblems;
    final Widget? body;
    if (problems.isNotEmpty) {
      final first = problems.entries.first;
      body = Row(
        key: const ValueKey<String>('bulk_login_problems'),
        children: [
          Icon(Icons.error_outline_rounded, size: 16, color: AppTone.danger.a),
          const SizedBox(width: AppSpace.xs),
          Expanded(
            child: Text(
              problems.length == 1
                  ? 'Satır ${first.key}: ${first.value}'
                  : '${problems.length} satırda kullanıcı adı sorunu var (ilki satır ${first.key}: ${first.value}). Düzeltmeden devam edilemez.',
              style: TextStyle(fontSize: 12, color: AppTone.danger.a, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      );
    } else if (c.proposalsError != null && !c.proposalsLoading) {
      body = Column(
        key: const ValueKey<String>('bulk_login_error'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_amber_rounded, size: 16, color: Colors.amber.shade800),
              const SizedBox(width: AppSpace.xs),
              Expanded(child: Text(c.proposalsError!, style: TextStyle(fontSize: 12, color: p.textSecondary))),
            ],
          ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              key: const ValueKey<String>('bulk_login_retry'),
              onPressed: c.flushProposals,
              child: const Text('Yeniden dene'),
            ),
          ),
        ],
      );
    } else if (c.proposalsLoading || c.proposalsStale) {
      body = Row(
        key: const ValueKey<String>('bulk_login_loading'),
        children: [
          const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: AppSpace.xs),
          Expanded(
            child: Text(
              'Kullanıcı adları hazırlanıyor… Sistem, başka sitelerde ve dosyada alınmış adları atlar.',
              style: TextStyle(fontSize: 12, color: p.textSecondary),
            ),
          ),
        ],
      );
    } else {
      body = null;
    }
    if (body == null) return const SizedBox.shrink();
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: 6),
        color: p.surface,
        child: body,
      ),
    );
  }
}

/// Hücre düzenleme penceresi. Metin denetleyicisi pencerenin kendi durumundadır ve pencere ağaçtan çıkınca
/// (kapanış animasyonu bittikten sonra) silinir: çağıran tarafta `showDialog` döner dönmez silmek, kapanış
/// animasyonu sürerken "TextEditingController was used after being disposed" hatası veriyordu.
class _CellEditDialog extends StatefulWidget {
  const _CellEditDialog({required this.col, required this.initialValue});

  final ImportColumn col;
  final String initialValue;

  @override
  State<_CellEditDialog> createState() => _CellEditDialogState();
}

class _CellEditDialogState extends State<_CellEditDialog> {
  late final TextEditingController _ctrl = TextEditingController(text: widget.initialValue);

  /// Plaka sütunu: Türk plakası biçimi yazarken zorlanır, geçersiz plaka satır içinde gösterilir (sunucu yüklemede yine doğrular).
  bool get _isPlate => widget.col.key == 'plaka';

  String? get _plateError => _isPlate ? validatePlateList(_ctrl.text) : null;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
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
            key: const ValueKey<String>('bulk_cell_field'),
            controller: _ctrl,
            autofocus: true,
            inputFormatters: _isPlate ? const <TextInputFormatter>[PlateListInputFormatter()] : null,
            onChanged: _isPlate ? (_) => setState(() {}) : null,
            decoration: InputDecoration(
              labelText: col.label,
              errorText: _plateError,
              helperText: _isPlate ? 'Örnek: 34 ABC 123. Birden çok plaka virgülle, en çok $maxPlatesPerField.' : (col.required ? 'Bu alan zorunludur' : 'İsteğe bağlı'),
              border: const OutlineInputBorder(),
            ),
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
          onPressed: _plateError != null ? null : () => Navigator.of(context).pop(_isPlate ? formatPlateList(_ctrl.text) : _ctrl.text),
          child: const Text('Uygula'),
        ),
      ],
    );
  }
}

/// Seçim listesi sütunu (İlişki, Borç Sorumlusu, Hesap) düzenleme penceresi: serbest metin YOK, açılır liste. Boş bırakmak isteğe bağlı sütunlarda
/// ayrı bir seçenektir (boş hücre mevcut değeri silmez; sunucu varsayılanı uygular). İptal null, «Uygula» seçilen etiketi (ya da boş metni) döndürür.
class _EnumEditDialog extends StatefulWidget {
  const _EnumEditDialog({required this.column, required this.choices, required this.currentText, required this.matched});

  final ImportColumn column;
  final List<String> choices;

  /// Dosyadaki ham hücre metni (listede olmayan eski sözcük olabilir: «Eş»).
  final String currentText;

  /// [currentText]'in listedeki karşılığı (yoksa null).
  final String? matched;

  @override
  State<_EnumEditDialog> createState() => _EnumEditDialogState();
}

class _EnumEditDialogState extends State<_EnumEditDialog> {
  late String? _selected = widget.matched;

  @override
  Widget build(BuildContext context) {
    final col = widget.column;
    final current = widget.currentText.trim();
    final unknown = current.isNotEmpty && widget.matched == null;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(Icons.arrow_drop_down_circle_outlined, color: AppTone.primary.a, size: 24),
          const SizedBox(width: AppSpace.sm),
          Expanded(child: Text('Listeden seçin: ${col.label}', style: const TextStyle(fontSize: 16))),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (unknown)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.sm),
              child: Text(
                'Dosyadaki değer «$current» listede yok. Listeden bir seçenek seçin ya da «İptal» ile değeri olduğu gibi bırakın.',
                key: const ValueKey<String>('bulk_enum_unknown'),
                style: TextStyle(fontSize: 12, color: AppTone.warning.ink(context.palette)),
              ),
            ),
          DropdownButtonFormField<String?>(
            key: const ValueKey<String>('bulk_enum_dropdown'),
            initialValue: _selected,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: col.label,
              helperText: col.required ? 'Bu alan zorunludur' : 'Boş bırakılabilir',
              border: const OutlineInputBorder(),
            ),
            items: [
              if (!col.required) const DropdownMenuItem<String?>(value: null, child: Text('(Boş bırak)')),
              for (final choice in widget.choices) DropdownMenuItem<String?>(value: choice, child: Text(choice)),
            ],
            onChanged: (value) => setState(() => _selected = value),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('İptal'),
        ),
        ElevatedButton(
          key: const ValueKey<String>('bulk_enum_apply'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTone.primary.a,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          // Zorunlu sütunda seçim şart; isteğe bağlıda boş seçim '' döner (hücre temizlenir).
          onPressed: (col.required && _selected == null) ? null : () => Navigator.of(context).pop(_selected ?? ''),
          child: const Text('Uygula'),
        ),
      ],
    );
  }
}

/// Kullanıcı adı penceresinin sonucu: yeni (normalleşmiş) ad ya da sistem önerisine dönüş.
class _LoginNameResult {
  const _LoginNameResult.value(String this.value) : reset = false;
  const _LoginNameResult.reset() : value = null, reset = true;

  final String? value;
  final bool reset;
}

enum _CheckState { idle, checking, ok, bad, failed }

/// Kullanıcı adı düzenleme penceresi: yazılan ad önce tarayıcıda (biçim + dosyadaki diğer adlar), sonra bekletmeli olarak sunucuda (bu sitedeki
/// kullanılabilirlik) denetlenir; «Uygula» yalnız denetim geçtiğinde açılır. Alınmış adda sunucunun önerdiği boş ad tek dokunuşla alınır.
class _LoginNameDialog extends StatefulWidget {
  const _LoginNameDialog({required this.controller, required this.row});

  final BulkImportController controller;
  final ImportRow row;

  @override
  State<_LoginNameDialog> createState() => _LoginNameDialogState();
}

class _LoginNameDialogState extends State<_LoginNameDialog> {
  late final TextEditingController _ctrl;
  late final String _initial;
  Timer? _timer;
  int _token = 0;
  _CheckState _state = _CheckState.idle;
  String? _message;
  String? _suggestion;
  String? _normalized;

  BulkImportController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _initial = _c.loginNameOf(widget.row) ?? '';
    _ctrl = TextEditingController(text: _initial);
  }

  @override
  void dispose() {
    _timer?.cancel();
    ++_token;
    _ctrl.dispose();
    super.dispose();
  }

  bool get _unchanged => _normalizedOf(_ctrl.text) == _normalizedOf(_initial);

  String _normalizedOf(String text) => normalizeTypedLoginName(text).value ?? text.trim().toLowerCase();

  void _onChanged(String text) {
    _timer?.cancel();
    final token = ++_token;
    if (_unchanged) {
      setState(() {
        _state = _CheckState.idle;
        _message = null;
        _suggestion = null;
        _normalized = null;
      });
      return;
    }
    final local = _c.localLoginNameProblem(text, rowN: widget.row.n);
    if (local != null) {
      setState(() {
        _state = _CheckState.bad;
        _message = local;
        _suggestion = null;
        _normalized = null;
      });
      return;
    }
    setState(() {
      _state = _CheckState.checking;
      _message = null;
      _suggestion = null;
      _normalized = normalizeTypedLoginName(text).value;
    });
    _timer = Timer(const Duration(milliseconds: 450), () => _check(text, token));
  }

  Future<void> _check(String text, int token) async {
    try {
      final result = await _c.checkLoginName(text);
      if (!mounted || token != _token) return;
      setState(() {
        _normalized = result.loginName ?? _normalized;
        if (result.ok) {
          // sunucu kabul etse bile dosyadaki başka bir satırla çakışma yerel olarak yeniden denetlenir (arada başka satır değişmiş olabilir)
          final local = _c.localLoginNameProblem(result.loginName ?? text, rowN: widget.row.n);
          _state = local == null ? _CheckState.ok : _CheckState.bad;
          _message = local;
          _suggestion = null;
        } else {
          _state = _CheckState.bad;
          _message = result.message ?? 'Bu kullanıcı adı kullanılamıyor.';
          _suggestion = result.suggestion;
        }
      });
    } catch (e) {
      if (!mounted || token != _token) return;
      setState(() {
        _state = _CheckState.failed;
        _message = 'Kullanıcı adı şu an denetlenemedi. Bağlantıyı kontrol edip tekrar deneyin.';
        _suggestion = null;
      });
    }
  }

  void _useSuggestion() {
    final suggestion = _suggestion;
    if (suggestion == null) return;
    _ctrl.text = suggestion;
    _ctrl.selection = TextSelection.collapsed(offset: suggestion.length);
    _onChanged(suggestion);
  }

  bool get _canApply => _unchanged || _state == _CheckState.ok;

  void _apply() {
    if (!_canApply) return;
    if (_unchanged) {
      Navigator.of(context).pop(null);
      return;
    }
    Navigator.of(context).pop(_LoginNameResult.value(_normalized ?? _ctrl.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final hasOverride = _c.overrideOf(widget.row) != null;
    final Color? stateColor = switch (_state) {
      _CheckState.ok => AppTone.success.a,
      _CheckState.bad || _CheckState.failed => AppTone.danger.a,
      _ => null,
    };
    final String? status = switch (_state) {
      _CheckState.checking => 'Denetleniyor…',
      _CheckState.ok => 'Kullanılabilir.',
      _ => _message,
    };
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(Icons.badge_outlined, color: AppTone.primary.a, size: 24),
          const SizedBox(width: AppSpace.sm),
          const Expanded(child: Text('Kullanıcı Adı', style: TextStyle(fontSize: 16))),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Satır ${widget.row.n}. Kullanıcı adını sistem Ad Soyad\'dan verdi. Değiştirirseniz ad Türkiye genelinde başka hiçbir hesapta ve '
              'dosyada kullanılmıyor olmalıdır (3-40 karakter; harf, rakam, nokta, alt çizgi, tire).',
              style: TextStyle(fontSize: 12, color: p.textSecondary),
            ),
            const SizedBox(height: AppSpace.sm),
            TextField(
              key: const ValueKey<String>('bulk_login_field'),
              controller: _ctrl,
              autofocus: true,
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.done,
              onChanged: _onChanged,
              onSubmitted: (_) => _apply(),
              decoration: InputDecoration(
                labelText: 'Kullanıcı adı',
                border: const OutlineInputBorder(),
                errorText: _state == _CheckState.bad || _state == _CheckState.failed ? _message : null,
                errorMaxLines: 3,
                suffixIcon: _state == _CheckState.checking
                    ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
                    : (_state == _CheckState.ok ? Icon(Icons.check_circle_rounded, color: AppTone.success.a) : null),
              ),
            ),
            if (status != null && (_state == _CheckState.checking || _state == _CheckState.ok))
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    status,
                    key: const ValueKey<String>('bulk_login_status'),
                    style: TextStyle(fontSize: 12, color: stateColor ?? p.textSecondary, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            if (_normalized != null && _normalized != _ctrl.text.trim() && _state != _CheckState.bad)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Kaydedilecek ad: $_normalized', style: TextStyle(fontSize: 12, color: p.textSecondary)),
              ),
            if (_suggestion != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: TextButton.icon(
                  key: const ValueKey<String>('bulk_login_suggestion'),
                  onPressed: _useSuggestion,
                  icon: const Icon(Icons.auto_fix_high_rounded, size: 16),
                  label: Text('Boştaki ad: $_suggestion'),
                ),
              ),
            if (_state == _CheckState.failed)
              TextButton.icon(
                key: const ValueKey<String>('bulk_login_recheck'),
                onPressed: () => _onChanged(_ctrl.text),
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Yeniden denetle'),
              ),
          ],
        ),
      ),
      actions: [
        if (hasOverride)
          TextButton(
            key: const ValueKey<String>('bulk_login_reset'),
            onPressed: () => Navigator.of(context).pop(const _LoginNameResult.reset()),
            child: const Text('Sistem önerisine dön'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('İptal'),
        ),
        ElevatedButton(
          key: const ValueKey<String>('bulk_login_apply'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTone.primary.a,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: _canApply ? _apply : null,
          child: const Text('Uygula'),
        ),
      ],
    );
  }
}

/// Yeni satır penceresi; sütun başına metin denetleyicileri pencereyle birlikte yaşar ve silinir
/// (bkz. [_CellEditDialog]). Seçim listesi sütunları açılır listedir. "Ekle" girilen değerleri döndürür, "İptal" null.
class _AddRowDialog extends StatefulWidget {
  const _AddRowDialog({required this.cols});

  final List<ImportColumn> cols;

  @override
  State<_AddRowDialog> createState() => _AddRowDialogState();
}

class _AddRowDialogState extends State<_AddRowDialog> {
  late final Map<String, TextEditingController> _ctrls = {
    for (final col in widget.cols)
      if (choicesFor(col).isEmpty) col.key: TextEditingController(),
  };
  final Map<String, String> _picked = <String, String>{};

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
                  child: choicesFor(col).isNotEmpty
                      ? DropdownButtonFormField<String?>(
                          key: ValueKey<String>('bulk_add_enum_${col.key}'),
                          initialValue: _picked[col.key],
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: '${col.label}${col.required ? ' *' : ''}',
                            isDense: true,
                            border: const OutlineInputBorder(),
                          ),
                          items: [
                            if (!col.required) const DropdownMenuItem<String?>(value: null, child: Text('(Boş bırak)')),
                            for (final choice in choicesFor(col)) DropdownMenuItem<String?>(value: choice, child: Text(choice)),
                          ],
                          onChanged: (value) => setState(() {
                            if (value == null) {
                              _picked.remove(col.key);
                            } else {
                              _picked[col.key] = value;
                            }
                          }),
                        )
                      : TextField(
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
            ..._picked,
          }),
          child: const Text('Ekle'),
        ),
      ],
    );
  }
}
