import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/meter_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/bulk_file_picker.dart';
import 'package:site_kapi_kontrol/services/meter_api.dart';
import 'package:site_kapi_kontrol/services/meter_file_reader.dart';
import 'package:site_kapi_kontrol/ui/views/meter_field_view.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

String _iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _errorText(Object error, String fallback) =>
    error is ApiException && error.message.trim().isNotEmpty ? error.message : fallback;

String _newKey() {
  final rnd = Random.secure();
  final tail = List<int>.generate(8, (_) => rnd.nextInt(256)).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return 'mtr-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}-$tail';
}

/// Yönetim "Sayaçlar" ekranı (`metering` modülü): Sayaçlar | Okuma aktar | Faturalandır. Yönetici yazar, kurul üyesi salt okur
/// (yazma düğmeleri çizilmez). Fotoğrafla okuma bu sürümde yok ("Yakında…").
/// [MetersViewState.reload] sayfa kabuğunun aşağı çekip yenilemesinden çağrılır.
class MetersView extends StatefulWidget {
  const MetersView({
    super.key,
    required this.authService,
    this.service,
    this.sites = const <MeterSite>[],
    this.onOpenModules,
    this.pickFile,
  });

  final AuthService authService;
  final MeterService? service;
  final List<MeterSite> sites;
  final VoidCallback? onOpenModules;

  /// Dosya seçici (testlerde sahte).
  final BulkFilePicker? pickFile;

  @override
  State<MetersView> createState() => MetersViewState();
}

class MetersViewState extends State<MetersView> with SingleTickerProviderStateMixin {
  late final MeterService _service = widget.service ?? MeterService(authService: widget.authService);
  late final TabController _tabs = TabController(length: 3, vsync: this);
  int? _siteCode;
  int _reloadTick = 0;

  MeterSite? get _site {
    for (final s in widget.sites) {
      if (s.code == _siteCode) return s;
    }
    return widget.sites.isEmpty ? null : widget.sites.first;
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> reload() async {
    if (mounted) setState(() => _reloadTick++);
  }

  /// Ana sayfa gövdesi kaydırılan bir kap: sekme görünümüne sınırlı yükseklik verilir (yoksa boş ekran).
  double _bodyHeight(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height * 0.78;
    return h < 480 ? 480 : h;
  }

  @override
  Widget build(BuildContext context) {
    final site = _site;
    if (site == null) {
      return const Center(child: Padding(padding: EdgeInsets.all(AppSpace.xl), child: Text('Sayaç modülü açık bir site bulunamadı. Modüller ekranından açılmasını isteyin.')));
    }
    if (site.fieldOnly) {
      return SizedBox(height: _bodyHeight(context), child: MeterFieldView(key: ValueKey<int>(site.code), authService: widget.authService, siteCode: site.code, siteName: site.label, service: _service));
    }
    return Column(
      children: <Widget>[
        if (widget.sites.length > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.md, AppSpace.lg, 0),
            child: DropdownButtonFormField<int>(
              initialValue: site.code,
              decoration: const InputDecoration(labelText: 'Site'),
              items: <DropdownMenuItem<int>>[for (final s in widget.sites) DropdownMenuItem<int>(value: s.code, child: Text(s.label))],
              onChanged: (v) => setState(() => _siteCode = v),
            ),
          ),
        TabBar(controller: _tabs, tabs: const <Tab>[Tab(text: 'Sayaçlar'), Tab(text: 'Okuma aktar'), Tab(text: 'Faturalandır')]),
        SizedBox(
          height: _bodyHeight(context),
          child: TabBarView(
            controller: _tabs,
            children: <Widget>[
              _MetersTab(key: ValueKey<String>('m${site.code}-$_reloadTick'), service: _service, site: site),
              _ImportTab(key: ValueKey<String>('i${site.code}-$_reloadTick'), service: _service, site: site, pickFile: widget.pickFile ?? pickBulkFile),
              _BillingTab(key: ValueKey<String>('b${site.code}-$_reloadTick'), service: _service, site: site),
            ],
          ),
        ),
      ],
    );
  }
}

Widget _errorCard(String message, VoidCallback retry) => Padding(
  padding: const EdgeInsets.all(AppSpace.lg),
  child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[Text(message, textAlign: TextAlign.center), const SizedBox(height: AppSpace.md), OutlinedButton(onPressed: retry, child: const Text('Tekrar dene'))]),
);

// --- Sayaçlar ---------------------------------------------------------------------------------------------------

class _MetersTab extends StatefulWidget {
  const _MetersTab({super.key, required this.service, required this.site});

  final MeterService service;
  final MeterSite site;

  @override
  State<_MetersTab> createState() => _MetersTabState();
}

class _MetersTabState extends State<_MetersTab> {
  List<Meter>? _meters;
  String? _error;
  MeterKind? _kind;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final list = await widget.service.listMeters(widget.site.code);
      if (mounted) setState(() => _meters = list);
    } catch (e) {
      if (mounted) setState(() => _error = _errorText(e, 'Sayaçlar yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.'));
    }
  }

  Future<void> _add() async {
    final apartments = await _loadApartments();
    if (apartments == null || !mounted) return;
    final created = await showDialog<bool>(context: context, builder: (_) => _MeterFormDialog(service: widget.service, siteCode: widget.site.code, apartments: apartments, initialKind: _kind));
    if (created == true) await _load();
  }

  Future<void> _openField() async {
    await Navigator.of(context).push<void>(MaterialPageRoute<void>(
      builder: (_) => MeterFieldView(authService: widget.service.authService, siteCode: widget.site.code, siteName: widget.site.label, service: widget.service),
    ));
    if (mounted) await _load();
  }

  Future<List<MeterApartment>?> _loadApartments() async {
    try {
      return await widget.service.listApartments(widget.site.code);
    } catch (e) {
      if (mounted) AppSnack.show(context, _errorText(e, 'Daireler yüklenemedi.'), kind: AppSnackKind.error);
      return null;
    }
  }

  Future<void> _toggle(Meter meter) async {
    try {
      await widget.service.updateMeter(widget.site.code, meter.id, isActive: !meter.isActive);
      await _load();
    } catch (e) {
      if (mounted) AppSnack.show(context, _errorText(e, 'Sayaç güncellenemedi.'), kind: AppSnackKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return Center(child: _errorCard(_error!, _load));
    final meters = _meters;
    if (meters == null) return const Center(child: CircularProgressIndicator());
    final shown = <Meter>[for (final m in meters) if (_kind == null || m.kind == _kind) m];
    return ListView(
      padding: const EdgeInsets.all(AppSpace.lg),
      children: <Widget>[
        Wrap(spacing: AppSpace.sm, children: <Widget>[
          ChoiceChip(label: const Text('Tümü'), selected: _kind == null, onSelected: (_) => setState(() => _kind = null)),
          for (final k in MeterKind.values) ChoiceChip(label: Text(k.label), selected: _kind == k, onSelected: (_) => setState(() => _kind = k)),
        ]),
        const SizedBox(height: AppSpace.md),
        if (widget.site.canWrite)
          Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.sm, children: <Widget>[
            FilledButton.icon(onPressed: _add, icon: const Icon(Icons.add_rounded), label: const Text('Sayaç ekle')),
            OutlinedButton.icon(onPressed: _openField, icon: const Icon(Icons.photo_camera_rounded), label: const Text('Fotoğrafla oku')),
          ]),
        const SizedBox(height: AppSpace.md),
        if (shown.isEmpty) const Text('Henüz sayaç kaydı yok.'),
        for (final m in shown)
          Card(
            child: ListTile(
              title: Text('${m.apartmentLabel} · ${m.kind.label}'),
              subtitle: Text('Seri no: ${m.serialNo}\n${m.lastValue == null ? 'Okuma yok' : 'Son okuma: ${m.lastValue} (${m.lastDate})'}${m.isActive ? '' : '\nPasif'}'),
              isThreeLine: true,
              onTap: () => showDialog<void>(context: context, builder: (_) => _ReadingsDialog(service: widget.service, site: widget.site, meter: m)).then((_) => _load()),
              trailing: widget.site.canWrite ? Switch(value: m.isActive, onChanged: (_) => _toggle(m)) : null,
            ),
          ),
      ],
    );
  }
}

class _MeterFormDialog extends StatefulWidget {
  const _MeterFormDialog({required this.service, required this.siteCode, required this.apartments, this.initialKind});

  final MeterService service;
  final int siteCode;
  final List<MeterApartment> apartments;
  final MeterKind? initialKind;

  @override
  State<_MeterFormDialog> createState() => _MeterFormDialogState();
}

class _MeterFormDialogState extends State<_MeterFormDialog> {
  int? _apartment;
  late MeterKind _kind = widget.initialKind ?? MeterKind.water;
  final TextEditingController _serial = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _serial.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_apartment == null || _serial.text.trim().isEmpty) {
      setState(() => _error = 'Daire ve seri numarası zorunludur.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.service.createMeter(widget.siteCode, apartmentId: _apartment!, kind: _kind, serialNo: _serial.text.trim());
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _errorText(e, 'Sayaç kaydedilemedi.');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Sayaç ekle'),
    content: SingleChildScrollView(
      child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
        DropdownButtonFormField<int>(
          initialValue: _apartment,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Daire'),
          items: <DropdownMenuItem<int>>[for (final a in widget.apartments) DropdownMenuItem<int>(value: a.id, child: Text(a.label))],
          onChanged: _busy ? null : (v) => setState(() => _apartment = v),
        ),
        DropdownButtonFormField<MeterKind>(
          initialValue: _kind,
          decoration: const InputDecoration(labelText: 'Sayaç türü'),
          items: <DropdownMenuItem<MeterKind>>[for (final k in MeterKind.values) DropdownMenuItem<MeterKind>(value: k, child: Text(k.label))],
          onChanged: _busy ? null : (v) => setState(() => _kind = v ?? _kind),
        ),
        TextField(controller: _serial, maxLength: 40, enabled: !_busy, decoration: const InputDecoration(labelText: 'Seri numarası')),
        if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      ]),
    ),
    actions: <Widget>[
      TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(false), child: const Text('Vazgeç')),
      FilledButton(onPressed: _busy ? null : _save, child: const Text('Kaydet')),
    ],
  );
}

class _ReadingsDialog extends StatefulWidget {
  const _ReadingsDialog({required this.service, required this.site, required this.meter});

  final MeterService service;
  final MeterSite site;
  final Meter meter;

  @override
  State<_ReadingsDialog> createState() => _ReadingsDialogState();
}

class _ReadingsDialogState extends State<_ReadingsDialog> {
  List<MeterReading>? _items;
  String? _error;
  DateTime _date = DateTime.now();
  final TextEditingController _value = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final items = await widget.service.listReadings(widget.site.code, widget.meter.id);
      if (mounted) setState(() => _items = items);
    } catch (e) {
      if (mounted) setState(() => _error = _errorText(e, 'Okumalar yüklenemedi.'));
    }
  }

  Future<void> _add() async {
    if (_value.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.service.addReading(widget.site.code, widget.meter.id, date: _iso(_date), value: _value.text.trim());
      _value.clear();
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = _errorText(e, 'Okuma kaydedilemedi.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(MeterReading r) async {
    try {
      await widget.service.deleteReading(widget.site.code, widget.meter.id, r.id);
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = _errorText(e, 'Okuma silinemedi.'));
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('${widget.meter.apartmentLabel} · ${widget.meter.kind.label}'),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          if (widget.site.canWrite && widget.meter.isActive) ...<Widget>[
            Row(children: <Widget>[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : () async {
                    final picked = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(2000), lastDate: DateTime.now());
                    if (picked != null) setState(() => _date = picked);
                  },
                  icon: const Icon(Icons.event_rounded),
                  label: Text(_iso(_date)),
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(child: TextField(controller: _value, enabled: !_busy, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Okuma değeri'))),
            ]),
            const SizedBox(height: AppSpace.sm),
            FilledButton(onPressed: _busy ? null : _add, child: const Text('Okuma ekle')),
          ],
          if (_error != null) Padding(padding: const EdgeInsets.only(top: AppSpace.sm), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          const SizedBox(height: AppSpace.md),
          if (_items == null && _error == null) const Center(child: CircularProgressIndicator()),
          if (_items != null && _items!.isEmpty) const Text('Henüz okuma yok.'),
          for (final r in _items ?? const <MeterReading>[])
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text('${r.date} · ${r.value}'),
              subtitle: Text(r.source == 'file' ? 'Dosyadan' : 'Elle'),
              trailing: widget.site.canWrite ? IconButton(tooltip: 'Okumayı sil', icon: const Icon(Icons.delete_outline_rounded), onPressed: () => _delete(r)) : null,
            ),
        ]),
      ),
    ),
    actions: <Widget>[TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Kapat'))],
  );
}

// --- Okuma aktar ------------------------------------------------------------------------------------------------

class _ImportTab extends StatefulWidget {
  const _ImportTab({super.key, required this.service, required this.site, required this.pickFile});

  final MeterService service;
  final MeterSite site;
  final BulkFilePicker pickFile;

  @override
  State<_ImportTab> createState() => _ImportTabState();
}

class _ImportTabState extends State<_ImportTab> {
  MeterKind _kind = MeterKind.water;
  DateTime _date = DateTime.now();
  String? _fileName;
  List<MeterFileRow> _rows = const <MeterFileRow>[];
  MeterImportResult? _checked;
  bool _busy = false;
  String? _error;

  void _invalidate() => _checked = null;

  Future<void> _pick() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final file = await widget.pickFile();
      if (file == null) return;
      final size = file.size;
      if (size != null && size > 10 * 1024 * 1024) {
        setState(() => _error = 'Dosya çok büyük (en çok 10 MB).');
        return;
      }
      final read = readMeterFile(await file.readBytes(), file.name);
      setState(() {
        _invalidate();
        if (read.error != null) {
          _error = read.error;
          _rows = const <MeterFileRow>[];
          _fileName = null;
        } else {
          _rows = read.rows;
          _fileName = file.name;
        }
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Dosya okunamadı. Yeniden deneyin.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _run({required bool dryRun}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.service.importReadings(
        widget.site.code,
        kind: _kind,
        readingDate: _iso(_date),
        rows: <Map<String, dynamic>>[for (final r in _rows) r.toJson()],
        dryRun: dryRun,
      );
      if (!mounted) return;
      setState(() => _checked = dryRun ? result : null);
      if (!dryRun) {
        setState(() {
          _rows = const <MeterFileRow>[];
          _fileName = null;
        });
        AppSnack.show(context, '${result.okCount} okuma aktarıldı${result.errorCount > 0 ? ', ${result.errorCount} satır atlandı' : ''}.', kind: AppSnackKind.success);
      }
    } catch (e) {
      if (mounted) setState(() => _error = _errorText(e, 'Okumalar aktarılamadı. İnternet bağlantınızı kontrol edin.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final checked = _checked;
    return ListView(
      padding: const EdgeInsets.all(AppSpace.lg),
      children: <Widget>[
        const Text('Uzaktan okuyan sayaçların dosyasını (CSV ya da Excel) yükleyin. İlk sütun daire kodu (ör. "A Blok - 5") ya da sayaç seri numarası, ikinci sütun okuma değeri olmalıdır.'),
        const SizedBox(height: AppSpace.md),
        DropdownButtonFormField<MeterKind>(
          initialValue: _kind,
          decoration: const InputDecoration(labelText: 'Sayaç türü'),
          items: <DropdownMenuItem<MeterKind>>[for (final k in MeterKind.values) DropdownMenuItem<MeterKind>(value: k, child: Text(k.label))],
          onChanged: _busy ? null : (v) => setState(() {
            _kind = v ?? _kind;
            _invalidate();
          }),
        ),
        const SizedBox(height: AppSpace.sm),
        OutlinedButton.icon(
          onPressed: _busy ? null : () async {
            final picked = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(2000), lastDate: DateTime.now());
            if (picked == null) return;
            setState(() {
              _date = picked;
              _invalidate();
            });
          },
          icon: const Icon(Icons.event_rounded),
          label: Text('Okuma tarihi: ${_iso(_date)}'),
        ),
        const SizedBox(height: AppSpace.sm),
        if (widget.site.canWrite) FilledButton.icon(onPressed: _busy ? null : _pick, icon: const Icon(Icons.upload_file_rounded), label: const Text('Dosya seç')),
        if (_fileName != null) Padding(padding: const EdgeInsets.only(top: AppSpace.sm), child: Text('$_fileName · ${_rows.length} satır')),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: AppSpace.sm), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        if (_rows.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpace.md),
          FilledButton.tonal(onPressed: _busy ? null : () => _run(dryRun: true), child: const Text('Kontrol et')),
        ],
        if (checked != null) ...<Widget>[
          const SizedBox(height: AppSpace.md),
          Text('${checked.okCount} satır aktarılacak, ${checked.sameCount} satır zaten kayıtlı, ${checked.errorCount} satırda sorun var.', style: Theme.of(context).textTheme.titleSmall),
          for (final row in checked.rows.where((r) => r.isError).take(50)) ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: const Icon(Icons.error_outline_rounded), title: Text('Satır ${row.n}: ${row.code}'), subtitle: Text(MeterImportRow.reasonText(row.reason))),
          if (checked.okCount > 0) FilledButton(onPressed: _busy ? null : () => _run(dryRun: false), child: Text('${checked.okCount} okumayı aktar')),
        ],
        const SizedBox(height: AppSpace.xl),
        const Text('Fotoğrafla okuma: Yakında…'),
      ],
    );
  }
}

// --- Faturalandır -----------------------------------------------------------------------------------------------

class _BillingTab extends StatefulWidget {
  const _BillingTab({super.key, required this.service, required this.site});

  final MeterService service;
  final MeterSite site;

  @override
  State<_BillingTab> createState() => _BillingTabState();
}

class _BillingTabState extends State<_BillingTab> {
  MeterKind _kind = MeterKind.water;
  MeterMethod _method = MeterMethod.unitPrice;
  DateTime? _from;
  DateTime? _to;
  final TextEditingController _amount = TextEditingController();
  bool _skipMissing = false;
  BillingPreview? _preview;
  String _key = _newKey();
  Map<String, dynamic>? _previewInput;
  List<MeterBilling>? _history;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_loadHistory());
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    try {
      final list = await widget.service.listBillings(widget.site.code);
      if (mounted) setState(() => _history = list);
    } catch (_) {
      // Geçmiş yardımcıdır; ana akış çalışır.
    }
  }

  void _dirty() {
    _preview = null;
    _previewInput = null;
    _key = _newKey();
  }

  List<MeterMethod> get _methods => <MeterMethod>[MeterMethod.unitPrice, MeterMethod.invoice, if (_kind == MeterKind.heat) MeterMethod.heat];

  Map<String, dynamic>? _input() {
    if (_from == null || _to == null) {
      setState(() => _error = 'Başlangıç ve bitiş tarihlerini seçin.');
      return null;
    }
    final minor = parseTlToMinor(_amount.text);
    if (minor == null) {
      setState(() => _error = _method == MeterMethod.unitPrice ? 'Birim fiyatı TL olarak girin (ör. 45,50).' : 'Tutarı TL olarak girin (ör. 12500,00).');
      return null;
    }
    return <String, dynamic>{
      'kind': _kind.api,
      'method': _method.api,
      'period_from': _iso(_from!),
      'period_to': _iso(_to!),
      if (_method == MeterMethod.unitPrice) 'unit_price_minor': minor else 'total_minor': minor,
      'skip_missing': _skipMissing,
    };
  }

  Future<void> _previewNow() async {
    final input = _input();
    if (input == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final preview = await widget.service.previewBilling(widget.site.code, input);
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _previewInput = input;
      });
    } catch (e) {
      if (mounted) setState(() => _error = _errorText(e, 'Önizleme hesaplanamadı. İnternet bağlantınızı kontrol edin.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _post() async {
    final preview = _preview;
    final input = _previewInput;
    if (preview == null || input == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Borçlandırılsın mı?'),
        content: Text('${preview.apartmentCount} daireye toplam ${formatMinorTl(preview.totalMinor)} borç yazılacak. Borç, dairenin oturanının hesabına işlenir. Hata olursa Finans ekranından kalem kalem ters kayıtla düzeltilir.'),
        actions: <Widget>[TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Vazgeç')), FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Borçlandır'))],
      ),
    );
    if (ok != true) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.service.postBilling(widget.site.code, <String, dynamic>{
        ...input,
        'idempotency_key': _key,
        'expected_total_minor': preview.totalMinor,
        'expected_count': preview.apartmentCount,
        'expected_hash': preview.previewHash,
      });
      if (!mounted) return;
      AppSnack.show(context, 'Borçlandırma yapıldı.', kind: AppSnackKind.success);
      setState(_dirty);
      await _loadHistory();
    } catch (e) {
      if (mounted) setState(() => _error = _errorText(e, 'Borçlandırma yapılamadı. İşlem tamamlanmış olabilir; geçmişi yenileyip kontrol edin.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickDate(bool from) async {
    final picked = await showDatePicker(context: context, initialDate: (from ? _from : _to) ?? DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime.now().add(const Duration(days: 1)));
    if (picked != null) {
      setState(() {
        if (from) {
          _from = picked;
        } else {
          _to = picked;
        }
        _dirty();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    final error = Theme.of(context).colorScheme.error;
    return ListView(
      padding: const EdgeInsets.all(AppSpace.lg),
      children: <Widget>[
        if (!widget.site.canWrite) const Text('Faturalandırmayı yalnızca site yöneticisi yapabilir.'),
        if (widget.site.canWrite) ...<Widget>[
          const Text('İki okuma tarihi arasındaki tüketim hesaplanır. Başlangıç tarihinde (ya da öncesinde) ve bitiş tarihinde (ya da öncesinde) okuma olmalıdır. Borçlandırma için "Aidat ve Finans" modülü de açık olmalıdır.'),
          const SizedBox(height: AppSpace.md),
          DropdownButtonFormField<MeterKind>(
            initialValue: _kind,
            decoration: const InputDecoration(labelText: 'Sayaç türü'),
            items: <DropdownMenuItem<MeterKind>>[for (final k in MeterKind.values) DropdownMenuItem<MeterKind>(value: k, child: Text(k.label))],
            onChanged: _busy ? null : (v) => setState(() {
              _kind = v ?? _kind;
              if (!_methods.contains(_method)) _method = MeterMethod.unitPrice;
              _dirty();
            }),
          ),
          DropdownButtonFormField<MeterMethod>(
            initialValue: _method,
            decoration: const InputDecoration(labelText: 'Dağıtım yöntemi'),
            items: <DropdownMenuItem<MeterMethod>>[for (final m in _methods) DropdownMenuItem<MeterMethod>(value: m, child: Text(m.label))],
            onChanged: _busy ? null : (v) => setState(() {
              _method = v ?? _method;
              _dirty();
            }),
          ),
          const SizedBox(height: AppSpace.sm),
          Row(children: <Widget>[
            Expanded(child: OutlinedButton(onPressed: _busy ? null : () => _pickDate(true), child: Text(_from == null ? 'Başlangıç tarihi' : _iso(_from!)))),
            const SizedBox(width: AppSpace.sm),
            Expanded(child: OutlinedButton(onPressed: _busy ? null : () => _pickDate(false), child: Text(_to == null ? 'Bitiş tarihi' : _iso(_to!)))),
          ]),
          TextField(
            controller: _amount,
            enabled: !_busy,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(_dirty),
            decoration: InputDecoration(labelText: _method == MeterMethod.unitPrice ? 'Birim fiyat (TL / birim)' : _method == MeterMethod.invoice ? 'Fatura tutarı (TL)' : 'Toplam ısınma gideri (TL)'),
          ),
          if (_method == MeterMethod.heat) const Padding(padding: EdgeInsets.only(top: AppSpace.xs), child: Text('Gider; ölçüme göre ve alan payıyla (hepsinde arsa payı tanımlıysa arsa payına, değilse eşit), platform kuralındaki oranla (varsayılan %70 / %30) paylaştırılır.')),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Okuması eksik daireleri atla'), value: _skipMissing, onChanged: _busy ? null : (v) => setState(() {
            _skipMissing = v;
            _dirty();
          })),
          FilledButton(onPressed: _busy ? null : _previewNow, child: const Text('Önizle')),
        ],
        if (_error != null) Padding(padding: const EdgeInsets.only(top: AppSpace.sm), child: Text(_error!, style: TextStyle(color: error))),
        if (preview != null) ...<Widget>[
          const SizedBox(height: AppSpace.md),
          Text('${preview.apartmentCount} daire · toplam ${formatMinorTl(preview.totalMinor)}', style: Theme.of(context).textTheme.titleMedium),
          if (preview.missing.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpace.sm),
            Text('Eksik olan ${preview.missing.length} daire:', style: TextStyle(color: error)),
            for (final m in preview.missing.take(30)) Text('• ${m.label}: ${m.reasonText}'),
          ],
          const SizedBox(height: AppSpace.sm),
          for (final l in preview.lines.take(300)) ListTile(dense: true, contentPadding: EdgeInsets.zero, title: Text(l.label), subtitle: Text('Tüketim: ${l.consumption} · ${l.accountParty == 'tenant' ? 'kiracı hesabı' : 'ev sahibi hesabı'}'), trailing: Text(formatMinorTl(l.amountMinor))),
          if (preview.lines.length > 300) Text('… ve ${preview.lines.length - 300} daire daha'),
          const SizedBox(height: AppSpace.sm),
          if (widget.site.canWrite) FilledButton(onPressed: _busy || !preview.canPost ? null : _post, child: const Text('Borçlandır')),
          if (!preview.canPost && preview.missing.isNotEmpty) const Text('Eksikleri tamamlayın ya da "eksik daireleri atla" seçeneğini işaretleyip yeniden önizleyin.'),
        ],
        const SizedBox(height: AppSpace.xl),
        Text('Geçmiş faturalandırmalar', style: Theme.of(context).textTheme.titleSmall),
        if (_history == null) const Padding(padding: EdgeInsets.all(AppSpace.md), child: Text('Yükleniyor…')),
        if (_history != null && _history!.isEmpty) const Text('Henüz faturalandırma yapılmadı.'),
        for (final b in _history ?? const <MeterBilling>[]) ListTile(dense: true, contentPadding: EdgeInsets.zero, title: Text('${b.kind.label} · ${b.periodFrom} – ${b.periodTo}'), subtitle: Text('${b.apartmentCount} daire'), trailing: Text(formatMinorTl(b.totalMinor))),
      ],
    );
  }
}
