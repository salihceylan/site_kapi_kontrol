import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/budget_models.dart';
import 'package:site_kapi_kontrol/models/expense_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/budget_api.dart';
import 'package:site_kapi_kontrol/services/pdf_budget_service.dart';
import 'package:site_kapi_kontrol/services/pdf_decision_service.dart' show DecisionPdfOutcome;
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/date_input.dart' show formatDateField;
import 'package:site_kapi_kontrol/ui/helpers/money.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart' show crmMessageOf;
import 'package:site_kapi_kontrol/ui/widgets/home_shortcut_button.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

String _isoDay(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Geçici proje kalan gün metni ("Geçici proje: son 18 gün"); süre dolduysa uyarı.
String budgetRemainingText(int days) => days <= 0 ? 'Geçici proje süresi doldu' : 'Geçici proje: son $days gün';

/// Yönetim "İşletme Projesi" ekranı (`budget` modülü). Yönetici / süper kullanıcı proje oluşturur, kalemleri girer, tebliğ eder,
/// kesinleştirir; kurul üyesi salt okur. Hukuki süreler ve adımlar [AVUKAT DOĞRULASIN] (KMK m.37, 7579 sayılı Kanun ile değişik);
/// ekranda bilgilendirme notu gösterilir. [BudgetViewState.reload] sayfa kabuğunun aşağı çekip yenilemesinden çağrılır.
class BudgetView extends StatefulWidget {
  const BudgetView({super.key, required this.authService, this.service, this.manageAllSites = false, this.sites = const <BudgetSite>[], this.onOpenModules});

  final AuthService authService;
  final BudgetService? service;
  final bool manageAllSites;
  final List<BudgetSite> sites;
  final VoidCallback? onOpenModules;

  @override
  State<BudgetView> createState() => BudgetViewState();
}

class BudgetViewState extends State<BudgetView> {
  List<BudgetSite> _sites = const <BudgetSite>[];
  int? _siteCode;
  BudgetListResult? _result;
  bool _loading = false;
  String? _error;
  bool _moduleDisabled = false;
  int _token = 0;

  late final BudgetService _service = widget.service ?? BudgetService(authService: widget.authService);

  @override
  void initState() {
    super.initState();
    unawaited(_loadSites());
  }

  @override
  void didUpdateWidget(BudgetView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.manageAllSites != widget.manageAllSites || !listEquals(oldWidget.sites, widget.sites)) {
      unawaited(_loadSites());
    }
  }

  @override
  void dispose() {
    ++_token;
    super.dispose();
  }

  BudgetSite? get _site {
    for (final s in _sites) {
      if (s.code == _siteCode) return s;
    }
    return null;
  }

  Future<void> _loadSites() async {
    final merged = <BudgetSite>[];
    try {
      if (widget.manageAllSites) {
        var page = 1;
        var fetched = 0;
        while (true) {
          final res = await widget.authService.listSites(page: page, pageSize: 100, approvalStatus: 'approved');
          for (final s in res.sites) {
            if (s.isApproved && !merged.any((m) => m.code == s.id)) merged.add(BudgetSite(code: s.id, name: s.name));
          }
          fetched += res.sites.length;
          if (res.sites.isEmpty || fetched >= res.total || page >= 50) break;
          page++;
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = crmMessageOf(e, 'Siteler yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.'));
      return;
    }
    for (final s in widget.sites) {
      if (!merged.any((m) => m.code == s.code)) merged.add(s);
    }
    if (!mounted) return;
    final keep = _siteCode != null && merged.any((s) => s.code == _siteCode);
    setState(() {
      _sites = merged;
      _siteCode = keep ? _siteCode : (merged.isEmpty ? null : merged.first.code);
    });
    await _loadProjects();
  }

  Future<void> reload() => _sites.isEmpty ? _loadSites() : _loadProjects();

  Future<void> _loadProjects() async {
    final code = _siteCode;
    if (code == null) return;
    final token = ++_token;
    setState(() {
      _loading = true;
      _error = null;
      _moduleDisabled = false;
    });
    try {
      final result = await _service.list(code);
      if (!mounted || token != _token) return;
      setState(() {
        _result = result;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || token != _token) return;
      setState(() {
        _loading = false;
        _moduleDisabled = e is ApiException && e.code == 'MODULE_DISABLED';
        _error = crmMessageOf(e, 'İşletme projeleri yüklenemedi. Tekrar deneyin.');
      });
    }
  }

  Future<void> _create() async {
    final code = _siteCode;
    if (code == null) return;
    final body = await showDialog<Map<String, dynamic>>(context: context, builder: (_) => const _CreateDialog());
    if (body == null || !mounted) return;
    try {
      final detail = await _service.create(code, body);
      if (!mounted) return;
      await _loadProjects();
      if (mounted) await _open(detail.project.id);
    } catch (e) {
      if (mounted) AppSnack.show(context, crmMessageOf(e, 'Proje kaydedilemedi.'), kind: AppSnackKind.error);
    }
  }

  Future<void> _open(int id) async {
    final site = _site;
    if (site == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => BudgetDetailPage(service: _service, site: site, projectId: id)),
    );
    if (mounted) unawaited(_loadProjects());
  }

  @override
  Widget build(BuildContext context) {
    final site = _site;
    if (site == null) {
      if (_error != null) return _Notice(message: _error!, onRetry: _loadSites);
      return const EmptyCard(icon: Icons.apartment_rounded, title: 'Kayıtlı site bulunamadı.');
    }
    final result = _result;
    return ListView(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), 
      padding: const EdgeInsets.all(AppSpace.lg),
      children: <Widget>[
        if (_sites.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.md),
            child: DropdownButtonFormField<int>(
              initialValue: _siteCode,
              decoration: const InputDecoration(labelText: 'Site'),
              items: <DropdownMenuItem<int>>[for (final s in _sites) DropdownMenuItem<int>(value: s.code, child: Text(s.label))],
              onChanged: (v) {
                if (v == null || v == _siteCode) return;
                setState(() {
                  _siteCode = v;
                  _result = null;
                });
                unawaited(_loadProjects());
              },
            ),
          ),
        Row(
          children: <Widget>[
            const Expanded(child: Text('İşletme Projesi', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700))),
            if (site.canWrite) FilledButton.icon(onPressed: _create, icon: const Icon(Icons.add_rounded), label: const Text('Yeni proje')),
          ],
        ),
        const SizedBox(height: AppSpace.md),
        if (_moduleDisabled)
          EmptyCard(
            icon: Icons.lock_outline_rounded,
            title: 'İşletme Projesi modülü kapalı.',
            message: 'Modüller ekranından açılabilir (yönetici talep eder, süper kullanıcı açar).',
            child: widget.onOpenModules == null ? null : TextButton(onPressed: widget.onOpenModules, child: const Text('Modüllere git')),
          )
        else if (_error != null)
          _Notice(message: _error!, onRetry: _loadProjects)
        else if (_loading && result == null)
          const ListSkeleton(rows: 3)
        else if (result != null) ...<Widget>[
          if (result.provisionalRemainingDays != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.md),
              child: AppCard(
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.timer_outlined),
                    const SizedBox(width: AppSpace.md),
                    Expanded(child: Text('${budgetRemainingText(result.provisionalRemainingDays!)}${(result.provisionalTitle ?? '').isEmpty ? '' : ' (${result.provisionalTitle})'}')),
                  ],
                ),
              ),
            ),
          if (result.projects.isEmpty)
            const EmptyCard(icon: Icons.account_balance_wallet_outlined, title: 'Henüz işletme projesi yok.', message: 'Yeni proje ile yıllık gider bütçesini oluşturun.')
          else
            for (final p in result.projects)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.sm),
                child: AppCard(
                  onTap: () => _open(p.id),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text('${p.year} - ${p.title}', style: const TextStyle(fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            Text(
                              '${p.status.label}${p.isProvisional ? ' (geçici)' : ''}  •  ${p.itemCount} kalem  •  ${formatMinor(p.totalMinor)}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            if (p.remainingDays != null) Text(budgetRemainingText(p.remainingDays!), style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded),
                    ],
                  ),
                ),
              ),
        ],
        const SizedBox(height: AppSpace.lg),
        Text(
          'Bilgi: İşletme projesinin tebliği, itiraz süresi ve kesinleşmesi Kat Mülkiyeti Kanunu\'na tabidir; süreler Kurallar tablosundan gelir. '
          'Yasal adımları kendi karar defterinizle birlikte takip edin. [AVUKAT DOĞRULASIN]',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[Text(message), const SizedBox(height: AppSpace.sm), TextButton(onPressed: onRetry, child: const Text('Tekrar dene'))],
    ),
  );
}

class _CreateDialog extends StatefulWidget {
  const _CreateDialog();

  @override
  State<_CreateDialog> createState() => _CreateDialogState();
}

class _CreateDialogState extends State<_CreateDialog> {
  final TextEditingController _year = TextEditingController(text: '${DateTime.now().year + 1}');
  final TextEditingController _title = TextEditingController();
  bool _provisional = false;
  String? _error;

  @override
  void dispose() {
    _year.dispose();
    _title.dispose();
    super.dispose();
  }

  void _submit() {
    final year = int.tryParse(_year.text.trim());
    if (year == null || year < 2000 || year > 2100) {
      setState(() => _error = 'Yıl 2000-2100 arasında olmalıdır.');
      return;
    }
    final title = _title.text.trim().isEmpty ? '$year yılı işletme projesi' : _title.text.trim();
    Navigator.of(context).pop(<String, dynamic>{'year': year, 'title': title, 'is_provisional': _provisional});
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Yeni işletme projesi'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(controller: _year, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Yıl')),
          TextField(controller: _title, maxLength: 160, decoration: const InputDecoration(labelText: 'Başlık (isteğe bağlı)')),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Geçici proje'),
            subtitle: const Text('Onaylı proje yokken en çok 90 gün (Kurallar tablosu); kalan gün ana sayfada izlenir.'),
            value: _provisional,
            onChanged: (v) => setState(() => _provisional = v),
          ),
          if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
      ),
    ),
    actions: <Widget>[
      TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Vazgeç')),
      FilledButton(onPressed: _submit, child: const Text('Oluştur')),
    ],
  );
}

/// Proje ayrıntısı: kalemler (taslakta düzenlenir), durum eylemleri, planlanan-gerçekleşen karşılaştırması ve PDF.
class BudgetDetailPage extends StatefulWidget {
  const BudgetDetailPage({super.key, required this.service, required this.site, required this.projectId});

  final BudgetService service;
  final BudgetSite site;
  final int projectId;

  @override
  State<BudgetDetailPage> createState() => _BudgetDetailPageState();
}

class _BudgetDetailPageState extends State<BudgetDetailPage> {
  BudgetDetail? _detail;
  BudgetComparison? _comparison;
  List<ExpenseCategory> _categories = const <ExpenseCategory>[];
  final Map<int, TextEditingController> _amounts = <int, TextEditingController>{};
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    for (final c in _amounts.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final detail = await widget.service.get(widget.site.code, widget.projectId);
      var categories = _categories;
      if (detail.project.status == BudgetStatus.taslak && widget.site.canWrite && categories.isEmpty) {
        categories = await widget.service.categories(widget.site.code);
      }
      BudgetComparison? comparison;
      if (detail.project.status != BudgetStatus.taslak || detail.items.isNotEmpty) {
        comparison = await widget.service.comparison(widget.site.code, widget.projectId);
      }
      if (!mounted) return;
      _applyDetail(detail, categories, comparison);
    } catch (e) {
      if (mounted) setState(() => _error = crmMessageOf(e, 'Proje yüklenemedi. Tekrar deneyin.'));
    }
  }

  void _applyDetail(BudgetDetail detail, List<ExpenseCategory> categories, BudgetComparison? comparison) {
    final byId = <int, int>{for (final i in detail.items) i.categoryId: i.annualMinor};
    for (final c in _amounts.values) {
      c.dispose();
    }
    _amounts.clear();
    for (final c in categories) {
      final minor = byId[c.id];
      _amounts[c.id] = TextEditingController(text: minor == null ? '' : (minor / 100).toStringAsFixed(2).replaceAll('.', ','));
    }
    setState(() {
      _detail = detail;
      _categories = categories;
      _comparison = comparison;
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) AppSnack.show(context, crmMessageOf(e, 'İşlem tamamlanamadı.'), kind: AppSnackKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveItems() => _run(() async {
    final items = <Map<String, int>>[];
    for (final c in _categories) {
      final text = _amounts[c.id]?.text.trim() ?? '';
      if (text.isEmpty) continue;
      final parsed = parseMoney(text, allowZero: true);
      if (!parsed.isOk) {
        AppSnack.show(context, '${c.name}: ${parsed.message}', kind: AppSnackKind.error);
        return;
      }
      items.add(<String, int>{'category_id': c.id, 'annual_minor': parsed.minor!});
    }
    final detail = await widget.service.putItems(widget.site.code, widget.projectId, items);
    final comparison = items.isEmpty ? null : await widget.service.comparison(widget.site.code, widget.projectId);
    if (!mounted) return;
    _applyDetail(detail, _categories, comparison);
    AppSnack.show(context, 'Kalemler kaydedildi.');
  });

  Future<void> _transition(String action, {Map<String, dynamic>? body}) => _run(() async {
    await widget.service.transition(widget.site.code, widget.projectId, action, body: body);
    await _load();
  });

  Future<void> _notify() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(DateTime.now().year - 1),
      lastDate: DateTime.now(),
      helpText: 'Tebliğ tarihi',
    );
    if (picked == null || !mounted) return;
    await _transition('notify', body: <String, dynamic>{'notified_at': _isoDay(picked)});
  }

  Future<void> _confirm(String title, String message, VoidCallback onYes) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Onayla')),
        ],
      ),
    );
    if (ok == true) onYes();
  }

  Future<void> _delete() => _run(() async {
    await widget.service.delete(widget.site.code, widget.projectId);
    if (mounted) Navigator.of(context).pop();
  });

  Future<void> _pdf() => _run(() async {
    final comparison = _comparison ?? await widget.service.comparison(widget.site.code, widget.projectId);
    final outcome = await PdfBudgetService.download(siteName: widget.site.name, comparison: comparison);
    if (mounted && outcome == DecisionPdfOutcome.delivered) AppSnack.show(context, 'PDF hazırlandı.');
  });

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    final project = detail?.project;
    return Scaffold(
      // Proje ayrıntısı (İşletme Projesi > proje): üst çubukta tek dokunuşla ana sayfa (P1-13).
      appBar: AppBar(
        title: Text(project == null ? 'İşletme projesi' : '${project.year} - ${project.title}'),
        actions: const <Widget>[HomeShortcutButton()],
      ),
      body: _error != null
          ? Padding(padding: const EdgeInsets.all(AppSpace.lg), child: _Notice(message: _error!, onRetry: _load))
          : project == null
          ? const Padding(padding: EdgeInsets.all(AppSpace.lg), child: ListSkeleton(rows: 4))
          : ListView(padding: const EdgeInsets.all(AppSpace.lg), children: _body(context, detail!, project)),
    );
  }

  List<Widget> _body(BuildContext context, BudgetDetail detail, BudgetProject p) {
    final canWrite = widget.site.canWrite;
    final draft = p.status == BudgetStatus.taslak;
    final small = Theme.of(context).textTheme.bodySmall;
    String day(DateTime? d) => d == null ? '-' : formatDateField(d);
    final comparison = _comparison;
    return <Widget>[
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Durum: ${p.status.label}', style: const TextStyle(fontWeight: FontWeight.w700)),
            if (p.isProvisional) Text('Geçici proje; bitiş ${day(p.provisionalUntil)}${p.remainingDays == null ? '' : ' - ${budgetRemainingText(p.remainingDays!)}'}'),
            if (p.notifiedAt != null) Text('Tebliğ tarihi: ${day(p.notifiedAt)}'),
            if (p.objectionEnds != null) Text('İtiraz süresi sonu: ${day(p.objectionEnds)} (${p.objectionDays} gün)'),
            Text('Toplam bütçe: ${formatMinor(p.totalMinor)}'),
          ],
        ),
      ),
      const SizedBox(height: AppSpace.md),
      if (canWrite) ...<Widget>[
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          children: <Widget>[
            if (draft) FilledButton(onPressed: _busy ? null : _notify, child: const Text('Tebliğ et')),
            if (p.status == BudgetStatus.teblig) ...<Widget>[
              FilledButton(
                onPressed: _busy ? null : () => _confirm('Kesinleştir', 'Proje kesinleşir ve bir daha değiştirilemez. İtiraz süresi bitmiş olmalıdır.', () => _transition('finalize')),
                child: const Text('Kesinleştir'),
              ),
              OutlinedButton(
                onPressed: _busy ? null : () => _confirm('Taslağa al', 'İtiraz üzerine proje taslağa alınır; tebliğ bilgileri silinir.', () => _transition('revert')),
                child: const Text('İtiraz: taslağa al'),
              ),
            ],
            if (draft) TextButton(onPressed: _busy ? null : () => _confirm('Sil', 'Taslak proje silinsin mi?', _delete), child: const Text('Sil')),
          ],
        ),
        const SizedBox(height: AppSpace.md),
      ],
      const Text('Kalemler (yıllık, ₺)', style: TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: AppSpace.sm),
      if (draft && canWrite) ...<Widget>[
        if (_categories.isEmpty) Text('Gider kategorisi bulunamadı (Aidat ve Finans modülü açık olmalı).', style: small),
        for (final c in _categories)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.sm),
            child: TextField(
              controller: _amounts[c.id],
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: c.name, suffixText: '₺'),
            ),
          ),
        FilledButton(onPressed: _busy ? null : _saveItems, child: const Text('Kalemleri kaydet')),
      ] else if (detail.items.isEmpty)
        Text('Kalem girilmemiş.', style: small)
      else
        for (final i in detail.items) ListTile(dense: true, contentPadding: EdgeInsets.zero, title: Text(i.categoryName), trailing: Text(formatMinor(i.annualMinor))),
      const SizedBox(height: AppSpace.lg),
      Row(
        children: <Widget>[
          const Expanded(child: Text('Planlanan - gerçekleşen', style: TextStyle(fontWeight: FontWeight.w700))),
          OutlinedButton.icon(onPressed: _busy || (comparison == null && detail.items.isEmpty) ? null : _pdf, icon: const Icon(Icons.picture_as_pdf_rounded), label: const Text('PDF')),
        ],
      ),
      const SizedBox(height: AppSpace.sm),
      if (comparison == null)
        Text('Kalem girilince karşılaştırma görünür.', style: small)
      else ...<Widget>[
        for (final r in <BudgetCompareRow>[...comparison.rows, comparison.totals])
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(r.categoryName),
            subtitle: Text('Planlanan ${formatMinor(r.plannedMinor)}  •  Gerçekleşen ${formatMinor(r.actualMinor)}${r.usedPct == null ? '' : '  •  %${r.usedPct!.toStringAsFixed(1).replaceAll('.', ',')}'}'),
            trailing: Text(
              formatSignedMinor(r.varianceMinor),
              style: TextStyle(color: r.varianceMinor > 0 ? Theme.of(context).colorScheme.error : null, fontWeight: FontWeight.w600),
            ),
          ),
        Text('Fark = gerçekleşen - planlanan; artı değer bütçe aşımıdır.', style: small),
      ],
    ];
  }
}
