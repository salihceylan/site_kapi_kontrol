// Fotoğrafla sayaç okuma (görevli / yönetici): kamera açık kalır, ekranın üstünde sıradaki daire yazar, değer telefonda metin tanımayla
// okunur, görevli onaylar ya da düzeltir. Okumalar önce cihaz kuyruğuna yazılır; internet yoksa orada bekler, gelince sunucuya
// (Drive bağlıysa Drive'a) gönderilir. Web'de kamera yok: yalnız elle giriş. Sözleşme: docs/PLATFORM_SAYAC.md "Fotoğrafla okuma".
import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/meter_field_models.dart';
import 'package:site_kapi_kontrol/models/meter_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/meter_api.dart';
import 'package:site_kapi_kontrol/services/meter_field_queue.dart';
import 'package:site_kapi_kontrol/services/meter_ocr.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

class MeterFieldView extends StatefulWidget {
  const MeterFieldView({
    super.key,
    required this.authService,
    required this.siteCode,
    required this.siteName,
    this.service,
    this.queue,
    this.ocr,
    this.enableCamera,
    this.clock,
  });

  final AuthService authService;
  final int siteCode;
  final String siteName;
  final MeterService? service;
  final MeterFieldQueue? queue;
  final MeterOcr? ocr;

  /// Kamerayı kullan; varsayılan: yalnız Android/iOS.
  final bool? enableCamera;
  final DateTime Function()? clock;

  @override
  State<MeterFieldView> createState() => _MeterFieldViewState();
}

class _MeterFieldViewState extends State<MeterFieldView> with WidgetsBindingObserver {
  late final MeterService _service = widget.service ?? MeterService(authService: widget.authService);
  late final MeterFieldQueue _queue = widget.queue ?? MeterFieldQueue();
  late final MeterOcr _ocr = widget.ocr ?? MlKitMeterOcr();
  late final bool _useCamera = widget.enableCamera ?? MlKitMeterOcr.supported;
  final TextEditingController _value = TextEditingController();
  CameraController? _camera;
  String? _cameraError;
  Timer? _timer;

  MeterKind _kind = MeterKind.water;
  List<FieldMeter> _meters = const <FieldMeter>[];
  final Set<int> _done = <int>{};
  final Set<int> _skipped = <int>{};
  List<PendingMeterReading> _pending = const <PendingMeterReading>[];
  bool _loading = true;
  String? _loadError;
  bool _busy = false;
  bool _offline = false;
  String? _notice;

  /// Gönderilmiş okumaların telefonda KALAN fotoğraf kopyası sayısı (uygulama silmez; kullanıcı "Kopyaları sil" ile siler).
  int _keptCopies = 0;

  // Çekilen fotoğraf ve tanınan değer (onay bekler).
  Uint8List? _shot;
  String? _recognizedNote;

  String get _today {
    final d = (widget.clock ?? DateTime.now)();
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  FieldMeter? get _current => nextFieldMeter(_meters, today: _today, done: _done, skipped: _skipped);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadMeters());
    unawaited(_refreshPending(flush: true));
    if (_useCamera) unawaited(_startCamera());
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => unawaited(_refreshPending(flush: true)));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _value.dispose();
    unawaited(_camera?.dispose());
    if (widget.ocr == null) unawaited(_ocr.close());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refreshPending(flush: true));
  }

  Future<void> _startCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw CameraException('none', 'Kamera bulunamadı.');
      final back = cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.back, orElse: () => cameras.first);
      final controller = CameraController(back, ResolutionPreset.high, enableAudio: false);
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _camera = controller);
    } on CameraException catch (e) {
      if (mounted) setState(() => _cameraError = e.code == 'CameraAccessDenied' ? 'Kamera izni verilmedi. Değeri elle yazabilirsiniz.' : 'Kamera açılamadı. Değeri elle yazabilirsiniz.');
    } on Object {
      if (mounted) setState(() => _cameraError = 'Kamera açılamadı. Değeri elle yazabilirsiniz.');
    }
  }

  Future<void> _loadMeters() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final all = await _service.listFieldMeters(widget.siteCode, kind: _kind);
      if (mounted) setState(() => _meters = all);
    } on ApiException catch (e) {
      if (mounted) setState(() => _loadError = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refreshPending({bool flush = false}) async {
    MeterFlushReport? report;
    if (flush) {
      try {
        report = await _queue.flush(_service);
      } on Object {
        report = null;
      }
    }
    final items = await _queue.items();
    final kept = await _queue.keptPhotoCount();
    if (!mounted) return;
    setState(() {
      _pending = items;
      _keptCopies = kept;
      if (report != null) _offline = report.offline;
      if (report != null && report.sent > 0) _notice = _sentNotice(report);
    });
  }

  /// Gönderim sonrası bilgi: fotoğrafın telefondaki kopyası SİLİNMEZ; isterse kullanıcı siler. Sunucu fotoğrafı almadıysa bu da söylenir.
  static String _sentNotice(MeterFlushReport report) {
    final text = StringBuffer('${report.sent} okuma gönderildi.');
    if (report.photosMissed > 0) {
      text.write(' ${report.photosMissed} okumanın fotoğrafı sunucuya ulaşmadı; kopyası telefonunuzda duruyor.');
    } else if (report.keptPhotos > 0) {
      text.write(' Fotoğrafların telefonunuzdaki kopyası silinmedi; isterseniz siz silebilirsiniz.');
    }
    return text.toString();
  }

  /// Telefonda duran, gönderilmiş fotoğraf kopyaları: uygulama bunları KENDİLİĞİNDEN silmez; kullanıcı isterse burada siler.
  Future<void> _showKeptCopies() async {
    final delete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Telefondaki fotoğraf kopyaları'),
        content: Text(
          'Gönderilmiş okumaların $_keptCopies fotoğrafı telefonunuzda duruyor. Uygulama bunları kendiliğinden silmez; yer açmak isterseniz siz silebilirsiniz. '
          'Sunucudaki kayıtlar etkilenmez.',
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Kalsın')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Kopyaları sil')),
        ],
      ),
    );
    if (delete != true) return;
    final removed = await _queue.deleteKeptPhotos();
    if (!mounted) return;
    setState(() => _notice = '$removed fotoğraf kopyası telefondan silindi.');
    await _refreshPending();
  }

  Future<void> _capture() async {
    final camera = _camera;
    final meter = _current;
    if (camera == null || meter == null || _busy) return;
    setState(() => _busy = true);
    try {
      final file = await camera.takePicture();
      final raw = await file.readAsBytes();
      final small = await shrinkMeterPhotoAsync(raw);
      final text = await _ocr.recognize(file.path);
      final guess = text == null ? null : pickMeterValue(text, lastValue: meter.lastValue);
      if (!mounted) return;
      setState(() {
        _shot = small;
        _value.text = guess ?? '';
        _recognizedNote = guess == null ? 'Değer okunamadı; sayaçtaki değeri yazın.' : 'Okunan değeri sayaçla karşılaştırın, gerekirse düzeltin.';
      });
    } on Object {
      if (mounted) setState(() => _notice = 'Fotoğraf çekilemedi. Tekrar deneyin ya da değeri elle yazın.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    final meter = _current;
    if (meter == null) return;
    final value = normalizeReadingValue(_value.text);
    if (value == null) {
      setState(() => _notice = 'Değer geçersiz. En çok 3 ondalıklı bir sayı yazın (örn. 1234,5).');
      return;
    }
    setState(() => _busy = true);
    await _queue.enqueue(siteCode: widget.siteCode, meter: meter, date: _today, value: value, photo: _shot);
    _done.add(meter.id);
    _value.clear();
    setState(() {
      _shot = null;
      _recognizedNote = null;
      _notice = 'Kaydedildi (${meter.apartmentLabel}).';
    });
    await _refreshPending(flush: true);
    if (mounted) setState(() => _busy = false);
  }

  void _skip() {
    final meter = _current;
    if (meter == null) return;
    setState(() {
      _skipped.add(meter.id);
      _shot = null;
      _value.clear();
      _recognizedNote = null;
    });
  }

  Future<void> _showPending() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _PendingSheet(queue: _queue, onChanged: () => unawaited(_refreshPending())),
    );
    if (mounted) unawaited(_refreshPending(flush: true));
  }

  @override
  Widget build(BuildContext context) {
    final meter = _current;
    final total = _meters.length;
    final read = _meters.where((m) => m.lastDate == _today || _done.contains(m.id)).length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fotoğrafla sayaç okuma'),
        actions: <Widget>[
          if (_keptCopies > 0)
            IconButton(
              key: const ValueKey<String>('meter_kept_copies'),
              tooltip: 'Telefondaki fotoğraf kopyaları ($_keptCopies)',
              icon: const Icon(Icons.photo_library_outlined),
              onPressed: _showKeptCopies,
            ),
          if (_pending.isNotEmpty)
            TextButton.icon(
              onPressed: _showPending,
              icon: Icon(_offline ? Icons.cloud_off_rounded : Icons.cloud_upload_outlined),
              label: Text('Bekleyen: ${_pending.length}'),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.md, AppSpace.lg, AppSpace.sm),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(widget.siteName, style: Theme.of(context).textTheme.labelLarge, overflow: TextOverflow.ellipsis),
                  ),
                  DropdownButton<MeterKind>(
                    value: _kind,
                    items: <DropdownMenuItem<MeterKind>>[for (final k in MeterKind.values) DropdownMenuItem<MeterKind>(value: k, child: Text(k.label))],
                    onChanged: _busy
                        ? null
                        : (k) {
                            if (k == null) return;
                            setState(() {
                              _kind = k;
                              _skipped.clear();
                              _done.clear();
                            });
                            unawaited(_loadMeters());
                          },
                  ),
                ],
              ),
            ),
            if (_loading) const LinearProgressIndicator(),
            if (_loadError != null) Padding(padding: const EdgeInsets.all(AppSpace.lg), child: Text(_loadError!)),
            if (!_loading && _loadError == null && total == 0)
              const Padding(padding: EdgeInsets.all(AppSpace.lg), child: Text('Bu türde etkin sayaç yok. Yönetici önce sayaçları tanımlamalıdır.')),
            if (total > 0) _nextBanner(context, meter, read, total),
            if (_useCamera) Expanded(child: _cameraArea()) else const Spacer(),
            _confirmPanel(context, meter),
          ],
        ),
      ),
    );
  }

  Widget _nextBanner(BuildContext context, FieldMeter? meter, int read, int total) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.primaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.md),
      child: meter == null
          ? Text('Okunacak daire kalmadı ($read/$total).', style: TextStyle(color: scheme.onPrimaryContainer, fontWeight: FontWeight.w700))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Sıradaki: ${meter.apartmentLabel}', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: scheme.onPrimaryContainer, fontWeight: FontWeight.w800)),
                Text(
                  '${meter.kind.label} sayacı · $read/$total okundu${meter.lastValue == null ? '' : ' · son okuma ${meter.lastValue}'}',
                  style: TextStyle(color: scheme.onPrimaryContainer),
                ),
              ],
            ),
    );
  }

  Widget _cameraArea() {
    final camera = _camera;
    if (_cameraError != null) return Center(child: Padding(padding: const EdgeInsets.all(AppSpace.lg), child: Text(_cameraError!, textAlign: TextAlign.center)));
    if (camera == null || !camera.value.isInitialized) return const Center(child: CircularProgressIndicator());
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        ClipRect(child: FittedBox(fit: BoxFit.cover, child: SizedBox(width: camera.value.previewSize?.height ?? 1, height: camera.value.previewSize?.width ?? 1, child: CameraPreview(camera)))),
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: FloatingActionButton.large(
              heroTag: 'meter_capture',
              tooltip: 'Fotoğraf çek ve oku',
              onPressed: _busy || _current == null || _shot != null ? null : _capture,
              child: _busy ? const CircularProgressIndicator() : const Icon(Icons.photo_camera_rounded),
            ),
          ),
        ),
      ],
    );
  }

  Widget _confirmPanel(BuildContext context, FieldMeter? meter) {
    return Material(
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (_notice != null) Padding(padding: const EdgeInsets.only(bottom: AppSpace.sm), child: Text(_notice!, style: Theme.of(context).textTheme.bodySmall)),
            if (_recognizedNote != null) Padding(padding: const EdgeInsets.only(bottom: AppSpace.sm), child: Text(_recognizedNote!, style: const TextStyle(fontWeight: FontWeight.w600))),
            Row(
              children: <Widget>[
                if (_shot != null) Padding(padding: const EdgeInsets.only(right: AppSpace.md), child: ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(_shot!, width: 64, height: 64, fit: BoxFit.cover))),
                Expanded(
                  child: TextField(
                    controller: _value,
                    enabled: meter != null && !_busy,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Okunan değer', hintText: 'Örn. 1234,5'),
                    onSubmitted: (_) => unawaited(_confirm()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.md),
            Row(
              children: <Widget>[
                Expanded(
                  child: FilledButton.icon(
                    onPressed: meter == null || _busy ? null : _confirm,
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Onayla ve sonraki'),
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
                OutlinedButton(onPressed: meter == null || _busy ? null : _skip, child: const Text('Atla')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PendingSheet extends StatefulWidget {
  const _PendingSheet({required this.queue, required this.onChanged});

  final MeterFieldQueue queue;
  final VoidCallback onChanged;

  @override
  State<_PendingSheet> createState() => _PendingSheetState();
}

class _PendingSheetState extends State<_PendingSheet> {
  List<PendingMeterReading> _items = const <PendingMeterReading>[];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final items = await widget.queue.items();
    if (mounted) setState(() => _items = items);
  }

  Future<void> _fix(PendingMeterReading item) async {
    final controller = TextEditingController(text: item.value);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(item.apartmentLabel),
        content: TextField(controller: controller, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Doğru değer')),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(context, normalizeReadingValue(controller.text)), child: const Text('Düzelt ve gönder')),
        ],
      ),
    );
    controller.dispose();
    if (value == null) return;
    await widget.queue.correct(item.id, value);
    widget.onChanged();
    await _load();
  }

  Future<void> _discard(PendingMeterReading item) async {
    await widget.queue.remove(item.id);
    widget.onChanged();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: _items.isEmpty
          ? const Padding(padding: EdgeInsets.all(AppSpace.xl), child: Text('Bekleyen okuma yok.'))
          : ListView(
              shrinkWrap: true,
              children: <Widget>[
                const Padding(
                  padding: EdgeInsets.all(AppSpace.lg),
                  child: Text('Cihazda bekleyen okumalar internet gelince kendiliğinden gönderilir. Gönderilen okumaların fotoğraf kopyaları telefonunuzdan kendiliğinden silinmez.'),
                ),
                for (final item in _items)
                  ListTile(
                    leading: Icon(item.error == null ? Icons.schedule_rounded : Icons.error_outline_rounded),
                    title: Text('${item.apartmentLabel} · ${item.kindLabel} · ${item.value}'),
                    subtitle: Text(item.error ?? '${item.date} · gönderilmeyi bekliyor${item.photoPath == null ? '' : ' (fotoğraflı)'}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        if (item.error != null) IconButton(tooltip: 'Değeri düzelt', icon: const Icon(Icons.edit_rounded), onPressed: () => _fix(item)),
                        IconButton(tooltip: 'Sil', icon: const Icon(Icons.delete_outline_rounded), onPressed: () => _discard(item)),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}
