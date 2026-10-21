import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/enforcement_models.dart';
import 'package:site_kapi_kontrol/models/vehicle_record.dart' show crmDateParam;
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_4b_access.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_errors.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_export_sources.dart';
import 'package:site_kapi_kontrol/ui/helpers/money.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/widgets/bulk_export_sheet.dart' show ExportSource;
import 'package:site_kapi_kontrol/ui/widgets/finance_4b_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

/// "İcra Dökümü" (F8, yalnız yönetici): bugün itibarıyla vadesi geçmiş borçlu hesapları (ev sahibi / kiracı) listeler; seçilen hesaplar için
/// hesap başına PDF (vade sırasıyla ödenmemiş kalemler, gecikme tazminatı, işletme projesi / kurul kararı bilgisi, avukat kontrolü notu) ve
/// avukat için Excel listesi üretilir. Döküm bilgi amaçlıdır; icra takibini BAŞLATMAZ.
class FinanceEnforcementView extends StatefulWidget {
  const FinanceEnforcementView({super.key, required this.scope, this.now, this.exportLauncher = defaultFinanceExportLauncher});

  final PeopleScope scope;
  final DateTime Function()? now;
  final FinanceExportLauncher exportLauncher;

  @override
  State<FinanceEnforcementView> createState() => _FinanceEnforcementViewState();
}

class _FinanceEnforcementViewState extends State<FinanceEnforcementView> {
  final TextEditingController _basis = TextEditingController();
  EnforcementReport? _report;
  DateTime? _loadedFor;
  final Set<String> _selected = <String>{};
  bool _loading = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _basis.dispose();
    super.dispose();
  }

  DateTime _today() => (widget.now ?? DateTime.now)();

  Future<void> _load() async {
    final day = _today();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final report = await widget.scope.f4Call((api, t, s) => api.getEnforcementReport(token: t, siteCode: s, asOf: day));
      if (!mounted) return;
      setState(() {
        _report = report;
        _loadedFor = day;
        _selected.clear();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = financeMessageOf(e, 'İcra dökümü yüklenemedi. Tekrar deneyin.');
      });
    }
  }

  /// PDF: seçilen hesapların kalemleri sunucudan seçimle yeniden okunur (ekran ile dosya aynı anlık görüntüden gelsin).
  Future<void> _pdf(bool share) async {
    if (_selected.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final keys = _selected.toList()..sort();
      final day = _loadedFor ?? _today();
      final report = await widget.scope.f4Call((api, t, s) => api.getEnforcementReport(token: t, siteCode: s, asOf: day, accountKeys: keys));
      await FinancePdfActions.enforcement(report, basisNote: _basis.text, share: share);
      if (mounted) setState(() => _busy = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = financeMessageOf(e, 'PDF hazırlanamadı. Tekrar deneyin.');
      });
    }
  }

  void _excel() {
    final day = _loadedFor ?? _today();
    final keys = _selected.toList()..sort();
    unawaited(
      widget.exportLauncher(context, <ExportSource>[
        financeExportSource(
          scope: widget.scope,
          label: 'İcra listesi',
          kind: 'finance_enforcement',
          icon: Icons.gavel_rounded,
          query: <String, String>{'as_of': crmDateParam(day), 'accounts': keys.join(',')},
          filterSummary: '${_selected.length} hesap seçili',
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final report = _report;
    final canAct = _selected.isNotEmpty && !_busy && !_loading;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Vadesi geçmiş borcu olan hesaplar için icra dökümü. Döküm bilgi amaçlıdır; icra takibini başlatmaz ve avukat kontrolünden geçmelidir.',
          style: th.bodyMedium,
        ),
        const SizedBox(height: AppSpace.md),
        PrimaryActionButton(
          key: const ValueKey<String>('finance_enforcement_load'),
          label: report == null ? 'Borçlu Hesapları Getir' : 'Listeyi Yenile',
          icon: Icons.gavel_rounded,
          variant: AppButtonVariant.tonal,
          expand: false,
          loading: _loading,
          onPressed: _loading ? null : _load,
        ),
        const SizedBox(height: AppSpace.md),
        if (_error != null) ...[
          FinanceSubmitError(key: const ValueKey<String>('finance_enforcement_error'), message: _error!),
          const SizedBox(height: AppSpace.md),
        ],
        if (report != null) ...[
          if (report.accounts.isEmpty)
            const EmptyCard(
              key: ValueKey<String>('finance_enforcement_empty'),
              icon: Icons.check_circle_outline_rounded,
              title: 'Bugün vadesi geçmiş borcu olan hesap yok.',
            )
          else ...[
            Row(
              children: [
                Expanded(child: Text('Borçlu hesaplar (${report.accounts.length})', style: th.titleMedium)),
                TextButton(
                  key: const ValueKey<String>('finance_enforcement_select_all'),
                  onPressed: () => setState(() {
                    if (_selected.length == report.accounts.length) {
                      _selected.clear();
                    } else {
                      _selected
                        ..clear()
                        ..addAll(report.accounts.map((a) => a.key));
                    }
                  }),
                  child: Text(_selected.length == report.accounts.length ? 'Seçimi kaldır' : 'Hepsini seç'),
                ),
              ],
            ),
            for (final a in report.accounts)
              CheckboxListTile(
                key: ValueKey<String>('finance_enforcement_${a.key}'),
                value: _selected.contains(a.key),
                onChanged: (v) => setState(() => v == true ? _selected.add(a.key) : _selected.remove(a.key)),
                controlAffinity: ListTileControlAffinity.leading,
                title: Text('${a.label} • ${a.accountParty.label}'),
                subtitle: Text(
                  '${(a.personName ?? '').isEmpty ? 'Kişi adı yok' : a.personName} • ${a.items.length} kalem'
                  '${a.lateFeeMinor > 0 ? ' • tazminat ${formatMinor(a.lateFeeMinor)}' : ''}',
                ),
                secondary: Text(formatMinor(a.totalMinor), style: th.titleSmall),
              ),
            const SizedBox(height: AppSpace.md),
            TextField(
              key: const ValueKey<String>('finance_enforcement_basis'),
              controller: _basis,
              maxLength: 300,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Kesinleşmiş işletme projesi / kurul kararı bilgisi',
                hintText: 'Örn. 2026 işletme projesi, 12.01.2026 tarihli karar',
                helperText: 'Boş bırakırsanız PDF\'te elle doldurulacak bir alan çıkar.',
                helperMaxLines: 2,
              ),
            ),
            const SizedBox(height: AppSpace.sm),
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.sm,
              children: [
                PrimaryActionButton(
                  key: const ValueKey<String>('finance_enforcement_pdf_print'),
                  label: 'PDF Yazdır',
                  icon: Icons.picture_as_pdf_rounded,
                  variant: AppButtonVariant.tonal,
                  expand: false,
                  loading: _busy,
                  onPressed: canAct ? () => _pdf(false) : null,
                ),
                PrimaryActionButton(
                  key: const ValueKey<String>('finance_enforcement_pdf_share'),
                  label: 'PDF Paylaş',
                  icon: Icons.ios_share_rounded,
                  variant: AppButtonVariant.tonal,
                  expand: false,
                  onPressed: canAct ? () => _pdf(true) : null,
                ),
                PrimaryActionButton(
                  key: const ValueKey<String>('finance_enforcement_excel'),
                  label: 'Avukat Excel Listesi',
                  icon: Icons.table_chart_rounded,
                  variant: AppButtonVariant.tonal,
                  expand: false,
                  onPressed: canAct ? _excel : null,
                ),
              ],
            ),
          ],
        ],
      ],
    );
  }
}
