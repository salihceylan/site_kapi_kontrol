import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/equipment_api.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

/// Yönetim "Ekipman ve Bakım" ekranı (`equipment` modülü): Ekipman | Bakım takvimi | Teklifler | Gider kırılımı.
///
/// - Yönetici yazar; kurul üyesi ve görevli salt okur. Bakım kaydı yalnız eklenir.
/// - Hatırlatma bildirimi (telefon / e-posta) ve teklife belge yükleme "Yakında…"; şimdilik yaklaşan bakımlar burada listelenir.
/// - [EquipmentViewState.reload] sayfa kabuğunun aşağı çekip yenilemesinden çağrılır.
class EquipmentView extends StatefulWidget {
  const EquipmentView({super.key, required this.authService, required this.sites, this.service, this.onOpenModules});

  final AuthService authService;
  final List<EquipmentSite> sites;
  final EquipmentService? service;
  final VoidCallback? onOpenModules;

  @override
  State<EquipmentView> createState() => EquipmentViewState();
}

class EquipmentViewState extends State<EquipmentView> {
  late final EquipmentService _service = widget.service ?? EquipmentService(authService: widget.authService);
  EquipmentSite? _site;
  int _tab = 0;
  bool _loading = true;
  String? _error;
  List<EquipmentItem> _items = const <EquipmentItem>[];
  List<MaintenancePlan> _due = const <MaintenancePlan>[];
  List<EquipmentQuote> _quotes = const <EquipmentQuote>[];
  EquipmentBreakdown? _breakdown;

  static const List<String> _tabs = <String>['Ekipman', 'Bakım takvimi', 'Teklifler', 'Gider kırılımı'];

  @override
  void initState() {
    super.initState();
    _site = widget.sites.isEmpty ? null : widget.sites.first;
    reload();
  }

  Future<void> reload() async {
    final site = _site;
    if (site == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    if (mounted) setState(() => _loading = true);
    try {
      final items = await _service.list(site.code);
      final due = await _service.due(site.code);
      final quotes = await _service.quotes(site.code);
      final breakdown = site.financeOn ? await _service.breakdown(site.code) : null;
      if (!mounted || _site != site) return;
      setState(() {
        _items = items;
        _due = due;
        _quotes = quotes;
        _breakdown = breakdown;
        _error = null;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    }
  }

  Future<void> _run(Future<void> Function() action, String okMessage) async {
    try {
      await action();
      if (!mounted) return;
      AppSnack.show(context, okMessage, kind: AppSnackKind.success);
      await reload();
    } on ApiException catch (e) {
      if (mounted) AppSnack.show(context, e.message, kind: AppSnackKind.error);
    }
  }

  Future<void> _addEquipment() async {
    final site = _site!;
    final v = await askForm(context, 'Ekipman ekle', <FormField2>[
      FormField2.choice('kind', 'Tür', <(String, String)>[for (final k in equipmentKinds) (k.code, k.name), ('diger', 'Diğer')], initial: 'asansor'),
      const FormField2.text('name', 'Ad', required: true, max: 120),
      const FormField2.text('location', 'Konum (örn. A Blok)', max: 120),
      const FormField2.text('serial_no', 'Seri no', max: 60),
      const FormField2.date('installed_on', 'Kurulum tarihi'),
      const FormField2.text('note', 'Not', max: 1000, lines: 2),
    ]);
    if (v == null) return;
    await _run(() => _service.create(site.code, <String, Object?>{for (final e in v.entries) if (e.value.isNotEmpty) e.key: e.value}), 'Ekipman kaydedildi.');
  }

  Future<void> _openDetail(EquipmentItem item) async {
    final site = _site!;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => FractionallySizedBox(heightFactor: 0.92, child: EquipmentDetailSheet(service: _service, site: site, itemId: item.id)),
    );
    if (mounted) await reload();
  }

  Future<void> _addQuote() async {
    final site = _site!;
    final v = await askForm(context, 'Teklif ekle', <FormField2>[
      const FormField2.text('topic', 'Konu (aynı konudaki teklifler karşılaştırılır)', required: true, max: 160),
      const FormField2.text('vendor_name', 'Firma', required: true, max: 120),
      const FormField2.money('amount', 'Tutar (TL)', required: true),
      const FormField2.date('valid_until', 'Geçerlilik tarihi'),
      const FormField2.text('document_note', 'Belge notu (belge yükleme Yakında…)', max: 300),
      FormField2.choice('equipment_id', 'İlgili ekipman', <(String, String)>[('', 'Yok'), for (final i in _items) ('${i.id}', i.name)], initial: ''),
    ]);
    if (v == null) return;
    final kurus = parseKurus(v['amount'] ?? '');
    if (!mounted) return;
    if (kurus == null || kurus <= 0) {
      AppSnack.show(context, 'Tutar geçersiz.', kind: AppSnackKind.error);
      return;
    }
    await _run(
      () => _service.createQuote(site.code, <String, Object?>{
        'topic': v['topic'],
        'vendor_name': v['vendor_name'],
        'amount_kurus': kurus,
        if ((v['valid_until'] ?? '').isNotEmpty) 'valid_until': v['valid_until'],
        if ((v['document_note'] ?? '').isNotEmpty) 'document_note': v['document_note'],
        if ((v['equipment_id'] ?? '').isNotEmpty) 'equipment_id': int.parse(v['equipment_id']!),
      }),
      'Teklif kaydedildi.',
    );
  }

  Future<void> _accept(EquipmentQuote q) async {
    final site = _site!;
    final options = <(String, String)>[if (site.financeOn) ('expense', 'Gider olarak kaydet'), if (site.contractsOn) ('contract', 'Sözleşme olarak kaydet')];
    if (options.isEmpty) {
      AppSnack.show(context, 'Kabul için Finans ya da Sözleşmeler modülü açık olmalı.', kind: AppSnackKind.error);
      widget.onOpenModules?.call();
      return;
    }
    final pick = await askForm(context, 'Teklifi kabul et', <FormField2>[FormField2.choice('as', '${q.vendorName} - ${formatKurus(q.amountKurus)}', options, initial: options.first.$1)]);
    if (pick == null) return;
    Map<String, Object?> body;
    try {
      if (pick['as'] == 'expense') {
        final (cats, accs) = await _service.financeChoices(site.code);
        if (cats.isEmpty || accs.isEmpty) {
          if (mounted) AppSnack.show(context, 'Önce Finans bölümünde en az bir gider kategorisi ve hesap olmalı.', kind: AppSnackKind.error);
          return;
        }
        if (!mounted) return;
        final e = await askForm(context, 'Gider bilgileri', <FormField2>[
          FormField2.choice('category_id', 'Kategori', <(String, String)>[for (final c in cats) ('${c.id}', c.name)], initial: '${cats.first.id}'),
          FormField2.choice('account_id', 'Giderin çıkacağı hesap', <(String, String)>[for (final a in accs) ('${a.id}', a.name)], initial: '${accs.first.id}'),
          const FormField2.date('expense_date', 'Gider tarihi (boşsa bugün)'),
        ]);
        if (e == null) return;
        body = <String, Object?>{
          'as': 'expense',
          'expense': <String, Object?>{
            'category_id': int.parse(e['category_id']!),
            'account_id': int.parse(e['account_id']!),
            if ((e['expense_date'] ?? '').isNotEmpty) 'expense_date': e['expense_date'],
          },
        };
      } else {
        final vendors = await _service.vendors(site.code);
        if (vendors.isEmpty) {
          if (mounted) AppSnack.show(context, 'Önce Sözleşmeler bölümünde firma ekleyin.', kind: AppSnackKind.error);
          return;
        }
        if (!mounted) return;
        final c = await askForm(context, 'Sözleşme bilgileri', <FormField2>[
          FormField2.choice('vendor_id', 'Firma', <(String, String)>[for (final v in vendors) ('${v.id}', v.name)], initial: '${vendors.first.id}'),
          const FormField2.date('start_date', 'Başlangıç tarihi', required: true),
          const FormField2.date('end_date', 'Bitiş tarihi'),
        ]);
        if (c == null) return;
        body = <String, Object?>{
          'as': 'contract',
          'contract': <String, Object?>{
            'vendor_id': int.parse(c['vendor_id']!),
            'start_date': c['start_date'],
            if ((c['end_date'] ?? '').isNotEmpty) 'end_date': c['end_date'],
          },
        };
      }
    } on ApiException catch (e) {
      if (mounted) AppSnack.show(context, e.message, kind: AppSnackKind.error);
      return;
    }
    await _run(() => _service.acceptQuote(site.code, q.id, body), 'Teklif kabul edildi.');
  }

  Future<void> _reject(EquipmentQuote q) async {
    final site = _site!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Teklifi reddet'),
        content: Text('${q.vendorName} teklifi reddedilsin mi?'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Reddet')),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() => _service.rejectQuote(site.code, q.id), 'Teklif reddedildi.');
  }

  Widget _equipmentTab(EquipmentSite site) {
    if (_items.isEmpty) return const AppCard(child: Text('Henüz ekipman yok. Asansör, interkom, kamera gibi ekipmanları ekleyip bakım planı kurabilirsiniz.'));
    return Column(
      children: <Widget>[
        for (final i in _items)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.sm),
            child: AppCard(
              onTap: () => _openDetail(i),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(i.name, style: Theme.of(context).textTheme.titleMedium),
                        Text('${equipmentKindLabel(i.kind)}${i.location == null ? '' : ' - ${i.location}'}${i.isActive ? '' : ' (pasif)'}'),
                        if (i.nextDue != null)
                          Text(
                            '${i.overdue ? 'Bakımı gecikmiş' : 'Sonraki bakım'}: ${trDate(i.nextDue!)}',
                            style: i.overdue ? TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.w600) : null,
                          ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _dueTab() {
    if (_due.isEmpty) {
      return const AppCard(child: Text('Önümüzdeki 60 gün içinde bakımı ya da yasal kontrolü gelen ekipman yok. Hatırlatma bildirimi Yakında…'));
    }
    return Column(
      children: <Widget>[
        const Padding(padding: EdgeInsets.only(bottom: AppSpace.sm), child: Text('Telefon / e-posta ile otomatik hatırlatma Yakında…')),
        for (final p in _due)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.sm),
            child: AppCard(
              child: Row(
                children: <Widget>[
                  Icon(p.state == 'overdue' ? Icons.warning_amber_rounded : Icons.event_rounded, color: p.state == 'overdue' ? Theme.of(context).colorScheme.error : null),
                  const SizedBox(width: AppSpace.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text('${p.equipmentName ?? ''} - ${p.title}', style: Theme.of(context).textTheme.titleSmall),
                        Text(
                          '${trDate(p.nextDue)} (${(p.daysLeft ?? 0) < 0 ? '${-(p.daysLeft ?? 0)} gün gecikti' : '${p.daysLeft} gün kaldı'})${p.legal ? ' - yasal kontrol' : ''}',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _quotesTab(EquipmentSite site) {
    if (_quotes.isEmpty) return const AppCard(child: Text('Henüz teklif yok. Aynı konuda birden çok teklif girerseniz en düşük tutar işaretlenir.'));
    final topics = <String>[];
    for (final q in _quotes) {
      if (!topics.contains(q.topic)) topics.add(q.topic);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (final topic in topics) ...<Widget>[
          Padding(padding: const EdgeInsets.symmetric(vertical: AppSpace.sm), child: Text(topic, style: Theme.of(context).textTheme.titleMedium)),
          for (final q in _quotes.where((x) => x.topic == topic))
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.sm),
              child: AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(child: Text(q.vendorName, style: Theme.of(context).textTheme.titleSmall)),
                        Text(formatKurus(q.amountKurus), style: Theme.of(context).textTheme.titleSmall),
                      ],
                    ),
                    Wrap(
                      spacing: AppSpace.sm,
                      children: <Widget>[
                        if (q.lowest) const Chip(label: Text('En düşük')),
                        Chip(label: Text(_statusLabel(q))),
                        if (q.validUntil != null) Chip(label: Text('Geçerlilik: ${trDate(q.validUntil!)}')),
                      ],
                    ),
                    if (q.documentNote != null) Text('Belge: ${q.documentNote}'),
                    if (site.canWrite && q.status == 'open' && !q.expired)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: <Widget>[
                          TextButton(onPressed: () => _reject(q), child: const Text('Reddet')),
                          FilledButton(onPressed: () => _accept(q), child: const Text('Kabul et')),
                        ],
                      ),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }

  String _statusLabel(EquipmentQuote q) {
    if (q.status == 'accepted') return q.acceptedAs == 'contract' ? 'Kabul: sözleşme' : 'Kabul: gider';
    if (q.status == 'rejected') return 'Reddedildi';
    return q.expired ? 'Süresi doldu' : 'Açık';
  }

  Widget _breakdownTab(EquipmentSite site) {
    final b = _breakdown;
    if (!site.financeOn || b == null) {
      return AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('Ekipman bazlı gider kırılımı için Finans modülü açık olmalı.'),
            if (widget.onOpenModules != null) TextButton(onPressed: widget.onOpenModules, child: const Text('Modüller')),
          ],
        ),
      );
    }
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('${b.from} - ${b.to} dönemi net gider (iptaller düşülmüş)', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppSpace.sm),
          if (b.items.isEmpty) const Text('Ekipmana bağlı gider yok. Ekipman ayrıntısından "Gider bağla" ile giderleri ekipmana bağlayın.'),
          for (final r in b.items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: <Widget>[Expanded(child: Text('${r.name} (${equipmentKindLabel(r.kind)})')), Text(formatKurus(r.expenseMinor))]),
            ),
          const Divider(),
          Row(children: <Widget>[const Expanded(child: Text('Ekipmana bağlı')), Text(formatKurus(b.linkedMinor))]),
          Row(children: <Widget>[const Expanded(child: Text('Bağlanmamış')), Text(formatKurus(b.unlinkedMinor))]),
          Row(children: <Widget>[const Expanded(child: Text('Toplam gider')), Text(formatKurus(b.totalMinor))]),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final site = _site;
    return ListView(
      padding: const EdgeInsets.all(AppSpace.lg),
      children: <Widget>[
        Text('Ekipman ve Bakım', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: AppSpace.md),
        if (widget.sites.length > 1)
          DropdownButtonFormField<EquipmentSite>(
            initialValue: site,
            decoration: const InputDecoration(labelText: 'Site'),
            items: <DropdownMenuItem<EquipmentSite>>[for (final s in widget.sites) DropdownMenuItem<EquipmentSite>(value: s, child: Text(s.label))],
            onChanged: (v) {
              setState(() => _site = v);
              reload();
            },
          ),
        const SizedBox(height: AppSpace.md),
        if (site == null)
          const Text('Bu özellik için açık bir siteniz yok.')
        else ...<Widget>[
          Wrap(
            spacing: AppSpace.sm,
            children: <Widget>[
              for (var i = 0; i < _tabs.length; i++) ChoiceChip(label: Text(_tabs[i]), selected: _tab == i, onSelected: (_) => setState(() => _tab = i)),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          if (site.canWrite && (_tab == 0 || _tab == 2))
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _tab == 0 ? _addEquipment : _addQuote,
                icon: const Icon(Icons.add_rounded),
                label: Text(_tab == 0 ? 'Ekipman ekle' : 'Teklif ekle'),
              ),
            ),
          const SizedBox(height: AppSpace.sm),
          if (_loading)
            const Center(child: Padding(padding: EdgeInsets.all(AppSpace.lg), child: CircularProgressIndicator()))
          else if (_error != null)
            AppCard(child: Text(_error!))
          else if (_tab == 0)
            _equipmentTab(site)
          else if (_tab == 1)
            _dueTab()
          else if (_tab == 2)
            _quotesTab(site)
          else
            _breakdownTab(site),
        ],
      ],
    );
  }
}

/// 2023-05-09 -> 09.05.2023
String trDate(String iso) => iso.length >= 10 ? '${iso.substring(8, 10)}.${iso.substring(5, 7)}.${iso.substring(0, 4)}' : iso;

/// Ekipman ayrıntısı: planlar, bakım kayıtları ve eylemler.
class EquipmentDetailSheet extends StatefulWidget {
  const EquipmentDetailSheet({super.key, required this.service, required this.site, required this.itemId});

  final EquipmentService service;
  final EquipmentSite site;
  final int itemId;

  @override
  State<EquipmentDetailSheet> createState() => _EquipmentDetailSheetState();
}

class _EquipmentDetailSheetState extends State<EquipmentDetailSheet> {
  EquipmentDetail? _detail;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await widget.service.detail(widget.site.code, widget.itemId);
      if (mounted) setState(() => _detail = d);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _act(Future<void> Function() action, String ok) async {
    try {
      await action();
      if (mounted) AppSnack.show(context, ok, kind: AppSnackKind.success);
      await _load();
    } on ApiException catch (e) {
      if (mounted) AppSnack.show(context, e.message, kind: AppSnackKind.error);
    }
  }

  Future<void> _addPlan({EquipmentKind? legalKind}) async {
    final v = await askForm(context, legalKind == null ? 'Bakım planı ekle' : 'Yasal kontrol planı', <FormField2>[
      FormField2.text('title', 'Plan adı', required: true, max: 120, initial: legalKind?.legalTitle ?? ''),
      FormField2.choice('interval_months', 'Sıklık', <(String, String)>[for (final m in maintenanceIntervals) ('$m', intervalLabel(m))], initial: '${legalKind?.legalMonths ?? 12}'),
      FormField2.choice('legal', 'Yasal kontrol mü?', const <(String, String)>[('0', 'Hayır'), ('1', 'Evet')], initial: legalKind == null ? '0' : '1'),
      const FormField2.date('next_due', 'İlk / sonraki bakım tarihi', required: true),
    ]);
    if (v == null) return;
    await _act(
      () => widget.service.addPlan(widget.site.code, widget.itemId, <String, Object?>{
        'title': v['title'],
        'interval_months': int.parse(v['interval_months']!),
        'legal': v['legal'] == '1',
        'next_due': v['next_due'],
      }),
      'Plan eklendi.',
    );
  }

  Future<void> _addLog({MaintenancePlan? plan}) async {
    final v = await askForm(context, plan == null ? 'Bakım kaydı ekle' : 'Bakım yapıldı: ${plan.title}', <FormField2>[
      const FormField2.date('done_on', 'Bakım tarihi', required: true),
      const FormField2.text('vendor_name', 'Yapan firma', max: 120),
      const FormField2.money('cost', 'Maliyet (TL)'),
      const FormField2.text('note', 'Not', max: 1000, lines: 2),
    ]);
    if (v == null) return;
    final cost = (v['cost'] ?? '').isEmpty ? null : parseKurus(v['cost']!);
    if ((v['cost'] ?? '').isNotEmpty && cost == null) {
      if (mounted) AppSnack.show(context, 'Maliyet geçersiz.', kind: AppSnackKind.error);
      return;
    }
    await _act(
      () async {
        final d = await widget.service.addLog(widget.site.code, widget.itemId, <String, Object?>{
          'done_on': v['done_on'],
          if (plan != null) 'plan_id': plan.id,
          if ((v['vendor_name'] ?? '').isNotEmpty) 'vendor_name': v['vendor_name'],
          'cost_kurus': ?cost,
          if ((v['note'] ?? '').isNotEmpty) 'note': v['note'],
        });
        if (mounted) setState(() => _detail = d);
      },
      'Bakım kaydedildi.',
    );
  }

  Future<void> _linkExpense() async {
    final v = await askForm(context, 'Gider bağla', const <FormField2>[FormField2.number('expense_id', 'Gider numarası (Finans > Giderler)', required: true)]);
    if (v == null) return;
    await _act(() async => widget.service.linkExpense(widget.site.code, widget.itemId, int.parse(v['expense_id']!)), 'Gider ekipmana bağlandı.');
  }

  @override
  Widget build(BuildContext context) {
    final d = _detail;
    if (_error != null) return Padding(padding: const EdgeInsets.all(AppSpace.lg), child: Text(_error!));
    if (d == null) return const Center(child: CircularProgressIndicator());
    final item = d.item;
    final kind = equipmentKinds.where((k) => k.code == item.kind).firstOrNull;
    final hasLegal = d.plans.any((p) => p.legal && p.isActive);
    final canWrite = widget.site.canWrite;
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpace.lg, 0, AppSpace.lg, AppSpace.xl),
      children: <Widget>[
        Text(item.name, style: Theme.of(context).textTheme.headlineSmall),
        Text('${equipmentKindLabel(item.kind)}${item.location == null ? '' : ' - ${item.location}'}${item.serialNo == null ? '' : ' - Seri: ${item.serialNo}'}'),
        if (item.note != null) Text(item.note!),
        const SizedBox(height: AppSpace.md),
        if (canWrite)
          Wrap(
            spacing: AppSpace.sm,
            children: <Widget>[
              OutlinedButton(onPressed: _addPlan, child: const Text('Plan ekle')),
              if (kind?.legalMonths != null && !hasLegal) OutlinedButton(onPressed: () => _addPlan(legalKind: kind), child: const Text('Yasal kontrol planı')),
              OutlinedButton(onPressed: _addLog, child: const Text('Bakım kaydı')),
              if (widget.site.financeOn) OutlinedButton(onPressed: _linkExpense, child: const Text('Gider bağla')),
              OutlinedButton(
                onPressed: () => _act(() => widget.service.update(widget.site.code, item.id, <String, Object?>{'is_active': !item.isActive}), item.isActive ? 'Pasife alındı.' : 'Etkinleştirildi.'),
                child: Text(item.isActive ? 'Pasife al' : 'Etkinleştir'),
              ),
            ],
          ),
        const SizedBox(height: AppSpace.md),
        Text('Bakım planları', style: Theme.of(context).textTheme.titleMedium),
        if (d.plans.isEmpty) const Text('Plan yok.'),
        for (final p in d.plans)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${p.title}${p.legal ? ' (yasal)' : ''}${p.isActive ? '' : ' - pasif'}'),
            subtitle: Text('${intervalLabel(p.intervalMonths)} - sonraki: ${trDate(p.nextDue)}${p.lastDone == null ? '' : ' - son: ${trDate(p.lastDone!)}'}'),
            trailing: canWrite && p.isActive ? TextButton(onPressed: () => _addLog(plan: p), child: const Text('Yapıldı')) : null,
          ),
        const SizedBox(height: AppSpace.md),
        Text('Bakım kayıtları', style: Theme.of(context).textTheme.titleMedium),
        if (d.logs.isEmpty) const Text('Kayıt yok.'),
        for (final l in d.logs)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${trDate(l.doneOn)}${l.vendorName == null ? '' : ' - ${l.vendorName}'}'),
            subtitle: Text('${l.costKurus == null ? '' : formatKurus(l.costKurus!)}${l.note == null ? '' : ' ${l.note}'}'.trim()),
          ),
        if (d.expenseIds.isNotEmpty) Padding(padding: const EdgeInsets.only(top: AppSpace.md), child: Text('Bağlı giderler: ${d.expenseIds.map((e) => '#$e').join(', ')}')),
      ],
    );
  }
}

enum FormFieldType { text, number, money, date, choice }

/// [askForm] alan tanımı.
class FormField2 {
  const FormField2.text(this.key, this.label, {this.required = false, this.max = 200, this.lines = 1, this.initial = ''}) : type = FormFieldType.text, options = const <(String, String)>[];
  const FormField2.number(this.key, this.label, {this.required = false}) : type = FormFieldType.number, max = 16, lines = 1, initial = '', options = const <(String, String)>[];
  const FormField2.money(this.key, this.label, {this.required = false}) : type = FormFieldType.money, max = 20, lines = 1, initial = '', options = const <(String, String)>[];
  const FormField2.date(this.key, this.label, {this.required = false}) : type = FormFieldType.date, max = 10, lines = 1, initial = '', options = const <(String, String)>[];
  const FormField2.choice(this.key, this.label, this.options, {this.initial = ''}) : type = FormFieldType.choice, required = false, max = 0, lines = 1;

  final String key;
  final String label;
  final FormFieldType type;
  final bool required;
  final int max;
  final int lines;
  final String initial;
  final List<(String, String)> options;
}

/// Basit form penceresi: alanları sırayla gösterir, zorunlu alanlar doluysa { anahtar: değer } döndürür (vazgeçilirse null).
Future<Map<String, String>?> askForm(BuildContext context, String title, List<FormField2> fields) {
  final values = <String, String>{for (final f in fields) f.key: f.initial};
  final controllers = <String, TextEditingController>{
    for (final f in fields)
      if (f.type != FormFieldType.choice) f.key: TextEditingController(text: f.initial),
  };
  return showDialog<Map<String, String>>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setLocal) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (final f in fields)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpace.sm),
                  child: switch (f.type) {
                    FormFieldType.choice => DropdownButtonFormField<String>(
                      initialValue: f.options.any((o) => o.$1 == values[f.key]) ? values[f.key] : f.options.first.$1,
                      isExpanded: true,
                      decoration: InputDecoration(labelText: f.label),
                      items: <DropdownMenuItem<String>>[for (final o in f.options) DropdownMenuItem<String>(value: o.$1, child: Text(o.$2, overflow: TextOverflow.ellipsis))],
                      onChanged: (v) => values[f.key] = v ?? '',
                    ),
                    FormFieldType.date => TextField(
                      controller: controllers[f.key],
                      readOnly: true,
                      decoration: InputDecoration(labelText: f.label + (f.required ? ' *' : ''), suffixIcon: const Icon(Icons.calendar_today_rounded)),
                      onTap: () async {
                        final now = DateTime.now();
                        final picked = await showDatePicker(context: dialogContext, initialDate: now, firstDate: DateTime(now.year - 30), lastDate: DateTime(now.year + 30));
                        if (picked != null) {
                          controllers[f.key]!.text = '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
                        }
                      },
                    ),
                    _ => TextField(
                      controller: controllers[f.key],
                      maxLength: f.max,
                      maxLines: f.lines,
                      keyboardType: f.type == FormFieldType.number ? TextInputType.number : (f.type == FormFieldType.money ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text),
                      decoration: InputDecoration(labelText: f.label + (f.required ? ' *' : ''), counterText: ''),
                    ),
                  },
                ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Vazgeç')),
          FilledButton(
            onPressed: () {
              final out = <String, String>{};
              for (final f in fields) {
                final v = f.type == FormFieldType.choice ? (values[f.key] ?? '') : controllers[f.key]!.text.trim();
                if (f.required && v.isEmpty) {
                  AppSnack.show(dialogContext, '${f.label} zorunlu.', kind: AppSnackKind.error);
                  return;
                }
                out[f.key] = v;
              }
              Navigator.pop(dialogContext, out);
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    ),
  );
}
