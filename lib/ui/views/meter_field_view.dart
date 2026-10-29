// Fotoğrafla sayaç okuma (görevli / yönetici): kamera açık kalır, ekranın üstünde sıradaki daire yazar, değer telefonda metin tanımayla
// okunur, görevli onaylar ya da düzeltir. Okumalar önce cihaz kuyruğuna yazılır; internet yoksa orada bekler, gelince sunucuya
// (Drive bağlıysa Drive'a) gönderilir. Web'de kamera yok: yalnız elle giriş. Sözleşme: docs/PLATFORM_SAYAC.md "Fotoğrafla okuma".
//
// Saha akışı (P1-6): blok seç -> dairelerin çekilen / çekilmeyen listesi -> eksikleri sırayla çek -> yanlış çekileni listeden seçip
// YENİDEN ÇEK. Sıçrama uyarısı (P1-7, karar K12): değer son 3 dönem tüketim medyanının eşik katını aşarsa görevli sıradaki daireye
// geçmeden "emin misiniz?" diye sorulur (engel değil, onaylayıp geçer; onay izi sunucuda tutulur). Sunucunun reddettiği kayıtlar
// (sıra dışı, olağan dışı tüketim onayı…) üst çubukta kırmızı rozetle görünür. Sözleşme: docs/PLATFORM_SAYAC.md "Saha akışı".
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
import 'package:site_kapi_kontrol/ui/design/empty_state.dart';
import 'package:site_kapi_kontrol/ui/design/status_dot.dart';
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

/// Bir dairenin okuma durumu (liste ekranı).
enum _MeterState { waiting, skipped, queued, needsConfirm, rejected, sent }

class _MeterRow {
  const _MeterRow({required this.meter, required this.state, required this.detail, required this.retake});

  final FieldMeter meter;
  final _MeterState state;
  final String detail;

  /// Bugün okunmuş: listeden seçilince YENİDEN ÇEKİM olur (değer, bugünkü okumanın yerine geçer).
  final bool retake;
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

  /// Bu oturumda girilen değerler (liste ekranında göstermek için).
  final Map<int, String> _entered = <int, String>{};

  /// Seçili blok (null: tüm bloklar) ve listeden seçilen daire (null: sıradaki).
  String? _block;
  FieldMeter? _picked;
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

  /// Bugün okunmuş mu: sunucuda bugünkü okuma var ya da bu oturumda okundu / kuyruğa girdi.
  bool _isDone(FieldMeter meter) => meter.lastDate == _today || _done.contains(meter.id);

  /// Seçili bloktaki sayaçlar (blok seçili değilse hepsi).
  List<FieldMeter> get _scoped => _block == null ? _meters : <FieldMeter>[for (final m in _meters) if (m.block == _block) m];

  FieldMeter? get _next => nextFieldMeter(_scoped, today: _today, done: _done, skipped: _skipped);

  /// Şimdi okunacak daire: listeden seçilen, yoksa sıradaki.
  FieldMeter? get _current => _picked ?? _next;

  PendingMeterReading? _pendingFor(int meterId) {
    PendingMeterReading? found;
    for (final item in _pending) {
      if (item.meterId == meterId && item.siteCode == widget.siteCode) found = item;
    }
    return found;
  }

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
      final all = await _service.listFieldMeters(widget.siteCode, kind: _kind, date: _today);
      if (mounted) {
        setState(() {
          _meters = all;
          if (_block != null && !fieldBlocks(all).contains(_block)) _block = null;
          _picked = null;
        });
      }
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
      if (report != null) {
        final parts = <String>[
          if (report.sent > 0) _sentNotice(report),
          if (report.jumpPending > 0) '${report.jumpPending} okuma olağan dışı tüketim nedeniyle onayınızı bekliyor; Bekleyen listesinden onaylayın ya da düzeltin.',
          if (report.rejected > report.jumpPending) '${report.rejected - report.jumpPending} okuma sunucuya kabul edilmedi; Bekleyen listesinden düzeltin.',
        ];
        if (parts.isNotEmpty) _notice = parts.join(' ');
      }
    });
  }

  void _selectBlock(String? block) {
    setState(() {
      _block = block;
      _picked = null;
      _shot = null;
      _recognizedNote = null;
      _value.clear();
    });
  }

  /// Listeden seçilen daire: çekilmediyse sıradaki yerine bu okunur, çekildiyse YENİDEN ÇEKİM başlar.
  void _pick(FieldMeter meter) {
    setState(() {
      _picked = meter;
      _shot = null;
      _recognizedNote = null;
      _value.clear();
      _notice = null;
    });
  }

  void _cancelPick() {
    setState(() {
      _picked = null;
      _shot = null;
      _recognizedNote = null;
      _value.clear();
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
      final guess = text == null ? null : pickMeterValue(text, lastValue: meter.baseValueFor(retake: _isDone(meter)));
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

  /// Olağan dışı tüketim: görevli sıradaki daireye geçmeden önce sorulur. true: "doğru, kaydet"; false / kapatma: değeri düzeltecek.
  Future<bool?> _askJump(FieldMeter meter, JumpFinding finding) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        key: const ValueKey<String>('jump_dialog'),
        title: const Text('Olağan dışı tüketim'),
        content: Text(
          '${meter.apartmentLabel}: bu okuma, önceki okumaya göre ${formatMilli(finding.consumption)} tüketim gösteriyor. '
          'Son 3 dönemin ortanca tüketimi ${formatMilli(finding.median)}; uyarı eşiği bunun ${finding.factor} katıdır (${formatMilli(finding.limit)}).\n\n'
          'Sayaçtaki değeri bir kez daha kontrol edin. Doğruysa kaydedin; onayınız kayıt altına alınır.',
        ),
        actions: <Widget>[
          TextButton(key: const ValueKey<String>('jump_fix'), onPressed: () => Navigator.pop(context, false), child: const Text('Değeri düzelt')),
          FilledButton(key: const ValueKey<String>('jump_confirm'), onPressed: () => Navigator.pop(context, true), child: const Text('Doğru, kaydet')),
        ],
      ),
    );
  }

  Future<void> _confirm() async {
    final meter = _current;
    if (meter == null || _busy) return;
    final value = normalizeReadingValue(_value.text);
    if (value == null) {
      setState(() => _notice = 'Değer geçersiz. En çok 3 ondalıklı bir sayı yazın (örn. 1234,5).');
      return;
    }
    final retake = _isDone(meter);
    final below = belowPreviousReading(meter, value, retake: retake);
    if (below != null) {
      setState(() => _notice = 'Değer önceki okumadan (${formatMeterNumber(below)}) küçük olamaz. Sayaçtaki değeri kontrol edin.');
      return;
    }
    var jumpConfirmed = false;
    final finding = checkJump(meter, value);
    if (finding != null) {
      setState(() => _busy = true);
      final accepted = await _askJump(meter, finding);
      if (!mounted) return;
      if (accepted != true) {
        setState(() => _busy = false);
        return;
      }
      jumpConfirmed = true;
    }
    setState(() => _busy = true);
    // Aynı dairenin bugünkü gönderilmemiş / reddedilmiş kaydı varsa yenisi onun yerine geçer (iki kayıt birbirini ezmesin).
    for (final old in await _queue.items()) {
      if (old.siteCode == widget.siteCode && old.meterId == meter.id && old.date == _today) await _queue.remove(old.id);
    }
    await _queue.enqueue(siteCode: widget.siteCode, meter: meter, date: _today, value: value, photo: _shot, replace: retake, jumpConfirmed: jumpConfirmed);
    _done.add(meter.id);
    _skipped.remove(meter.id);
    _entered[meter.id] = value;
    _value.clear();
    if (!mounted) return;
    setState(() {
      _shot = null;
      _recognizedNote = null;
      _picked = null;
      _notice = retake ? 'Yeniden çekim kaydedildi (${meter.apartmentLabel}).' : 'Kaydedildi (${meter.apartmentLabel}).';
    });
    await _refreshPending(flush: true);
    if (mounted) setState(() => _busy = false);
  }

  void _skip() {
    final meter = _current;
    if (meter == null) return;
    setState(() {
      _skipped.add(meter.id);
      _picked = null;
      _shot = null;
      _value.clear();
      _recognizedNote = null;
    });
  }

  Future<void> _showPending() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _PendingSheet(
        queue: _queue,
        onChanged: () => unawaited(_refreshPending()),
        onConfirmed: () => _refreshPending(flush: true),
      ),
    );
    if (mounted) unawaited(_refreshPending(flush: true));
  }

  _MeterRow _rowOf(FieldMeter meter) {
    final queued = _pendingFor(meter.id);
    final shown = _entered[meter.id] ?? (meter.lastDate == _today ? meter.lastValue : null);
    final retake = _isDone(meter);
    _MeterRow row(_MeterState state, String detail) => _MeterRow(meter: meter, state: state, detail: detail, retake: retake);
    if (queued != null) {
      if (queued.needsJumpConfirm) return row(_MeterState.needsConfirm, 'Olağan dışı tüketim: onayınız bekleniyor (${formatMeterNumber(queued.value)})');
      if (queued.error != null) return row(_MeterState.rejected, 'Sunucu kabul etmedi: ${queued.error}');
      return row(_MeterState.queued, 'Gönderilmeyi bekliyor (${formatMeterNumber(queued.value)})');
    }
    if (retake) return row(_MeterState.sent, shown == null ? 'Çekildi' : 'Çekildi (${formatMeterNumber(shown)})');
    if (_skipped.contains(meter.id)) return row(_MeterState.skipped, 'Atlandı');
    final last = meter.lastValue;
    return row(_MeterState.waiting, last == null ? 'Çekilmedi' : 'Çekilmedi · son okuma ${formatMeterNumber(last)}');
  }

  Future<void> _showList() async {
    final rows = <_MeterRow>[for (final m in _scoped) _rowOf(m)];
    final picked = await showModalBottomSheet<FieldMeter>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _MeterListSheet(title: _block ?? 'Tüm bloklar', rows: rows),
    );
    if (picked != null && mounted) _pick(picked);
  }

  @override
  Widget build(BuildContext context) {
    final meter = _current;
    final scoped = _scoped;
    final total = scoped.length;
    final read = scoped.where(_isDone).length;
    final problems = _pending.where((e) => e.error != null).length;
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
              key: const ValueKey<String>('pending_button'),
              onPressed: _showPending,
              icon: Badge(
                key: const ValueKey<String>('pending_badge'),
                isLabelVisible: problems > 0,
                label: Text('$problems'),
                child: Icon(_offline ? Icons.cloud_off_rounded : Icons.cloud_upload_outlined),
              ),
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
                              _entered.clear();
                              _picked = null;
                            });
                            unawaited(_loadMeters());
                          },
                  ),
                ],
              ),
            ),
            if (_loading) const LinearProgressIndicator(),
            if (_loadError != null) Padding(padding: const EdgeInsets.all(AppSpace.lg), child: Text(_loadError!)),
            if (!_loading && _loadError == null && _meters.isEmpty)
              const Padding(padding: EdgeInsets.all(AppSpace.lg), child: Text('Bu türde etkin sayaç yok. Yönetici önce sayaçları tanımlamalıdır.')),
            if (_meters.isNotEmpty) _blockBar(),
            if (_meters.isNotEmpty) _nextBanner(context, meter, read, total),
            Expanded(child: _useCamera ? _cameraArea() : _noCameraNote()),
            _confirmPanel(context, meter),
          ],
        ),
      ),
    );
  }

  /// Blok seçici: birden çok blok varsa "Tümü" + her blok (okunan/toplam).
  Widget _blockBar() {
    final blocks = fieldBlocks(_meters);
    if (blocks.length < 2) return const SizedBox.shrink();
    String count(List<FieldMeter> list) => '${list.where(_isDone).length}/${list.length}';
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.xs),
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: AppSpace.sm),
            child: ChoiceChip(
              key: const ValueKey<String>('block_chip_all'),
              label: Text('Tümü (${count(_meters)})'),
              selected: _block == null,
              onSelected: _busy ? null : (_) => _selectBlock(null),
            ),
          ),
          for (final block in blocks)
            Padding(
              padding: const EdgeInsets.only(right: AppSpace.sm),
              child: ChoiceChip(
                key: ValueKey<String>('block_chip_$block'),
                label: Text('$block (${count(<FieldMeter>[for (final m in _meters) if (m.block == block) m])})'),
                selected: _block == block,
                onSelected: _busy ? null : (_) => _selectBlock(block),
              ),
            ),
        ],
      ),
    );
  }

  Widget _nextBanner(BuildContext context, FieldMeter? meter, int read, int total) {
    final scheme = Theme.of(context).colorScheme;
    final retake = meter != null && _isDone(meter);
    // Yeniden çekim nötr gri (temanın ikincil kabı); renk tohumdan türeyen üçüncül ton değil, sade stilin paletidir.
    final background = retake ? scheme.secondaryContainer : scheme.primaryContainer;
    final foreground = retake ? scheme.onSecondaryContainer : scheme.onPrimaryContainer;
    final skippedHere = _scoped.where((m) => _skipped.contains(m.id) && !_isDone(m)).length;
    final lastValue = meter?.lastValue;
    final String headline;
    final String? subline;
    if (meter == null) {
      headline = 'Okunacak daire kalmadı ($read/$total).';
      subline = skippedHere > 0 ? '$skippedHere daire atlandı.' : null;
    } else if (retake) {
      headline = 'Yeniden çekim: ${meter.apartmentLabel}';
      final shown = _entered[meter.id] ?? lastValue;
      subline = 'Yeni değer, bugünkü okumanın${shown == null ? '' : ' (${formatMeterNumber(shown)})'} yerine geçer.';
    } else {
      headline = 'Sıradaki: ${meter.apartmentLabel}';
      subline = '${meter.kind.label} sayacı · $read/$total okundu${lastValue == null ? '' : ' · son okuma ${formatMeterNumber(lastValue)}'}';
    }
    return Container(
      width: double.infinity,
      color: background,
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.md),
      child: Row(
        children: <Widget>[
          if (retake) Padding(padding: const EdgeInsets.only(right: AppSpace.md), child: Icon(Icons.replay_rounded, color: foreground)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  headline,
                  style: meter == null
                      ? TextStyle(color: foreground, fontWeight: FontWeight.w700)
                      : Theme.of(context).textTheme.titleLarge?.copyWith(color: foreground, fontWeight: FontWeight.w800),
                ),
                if (subline != null) Text(subline, style: TextStyle(color: foreground)),
              ],
            ),
          ),
          if (meter == null && skippedHere > 0)
            TextButton(
              key: const ValueKey<String>('back_to_skipped'),
              style: TextButton.styleFrom(foregroundColor: foreground),
              onPressed: () => setState(() => _skipped.removeWhere((id) => _scoped.any((m) => m.id == id))),
              child: const Text('Atlananlara dön'),
            ),
          TextButton.icon(
            key: const ValueKey<String>('meter_list_open'),
            style: TextButton.styleFrom(foregroundColor: foreground),
            onPressed: _busy ? null : _showList,
            icon: const Icon(Icons.format_list_bulleted_rounded),
            label: Text('Liste ($read/$total)'),
          ),
        ],
      ),
    );
  }

  /// Kamera / metin tanıma desteklenmeyen platform (web, masaüstü): kamera alanı yerine boş kalan yerde nedeni söyler.
  Widget _noCameraNote() {
    return const EmptyState(
      key: ValueKey<String>('meter_no_camera_note'),
      icon: Icons.no_photography_outlined,
      title: 'Bu cihazda fotoğrafla okuma yok; değeri elle yazın.',
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
    final retake = meter != null && _isDone(meter);
    return Material(
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (_notice != null) Padding(padding: const EdgeInsets.only(bottom: AppSpace.sm), child: Text(_notice!, key: const ValueKey<String>('field_notice'), style: Theme.of(context).textTheme.bodySmall)),
            if (_recognizedNote != null) Padding(padding: const EdgeInsets.only(bottom: AppSpace.sm), child: Text(_recognizedNote!, style: const TextStyle(fontWeight: FontWeight.w600))),
            Row(
              children: <Widget>[
                if (_shot != null) Padding(padding: const EdgeInsets.only(right: AppSpace.md), child: ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(_shot!, width: 64, height: 64, fit: BoxFit.cover))),
                Expanded(
                  child: TextField(
                    key: const ValueKey<String>('reading_value'),
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
                    key: const ValueKey<String>('reading_confirm'),
                    onPressed: meter == null || _busy ? null : _confirm,
                    icon: const Icon(Icons.check_rounded),
                    label: Text(retake ? 'Onayla ve değiştir' : 'Onayla ve sonraki'),
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
                if (retake || _picked != null)
                  OutlinedButton(key: const ValueKey<String>('reading_cancel'), onPressed: meter == null || _busy ? null : _cancelPick, child: const Text('Vazgeç'))
                else
                  OutlinedButton(key: const ValueKey<String>('reading_skip'), onPressed: meter == null || _busy ? null : _skip, child: const Text('Atla')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Dairelerin okuma durumu: sorunlu (sunucu kabul etmedi / onay bekliyor), çekilmeyenler, çekilenler. Bir daire seçilince döner
/// (çekilmemişse o okunur, çekilmişse yeniden çekilir).
class _MeterListSheet extends StatelessWidget {
  const _MeterListSheet({required this.title, required this.rows});

  final String title;
  final List<_MeterRow> rows;

  static AppTone _toneOf(_MeterState state) => switch (state) {
    _MeterState.sent => AppTone.success,
    _MeterState.queued || _MeterState.needsConfirm => AppTone.warning,
    _MeterState.rejected => AppTone.danger,
    _MeterState.waiting || _MeterState.skipped => AppTone.neutral,
  };

  List<Widget> _section(BuildContext context, String heading, List<_MeterRow> list) {
    return <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.md, AppSpace.lg, AppSpace.xs),
        child: Text(heading, style: Theme.of(context).textTheme.labelLarge),
      ),
      for (final row in list)
        ListTile(
          key: ValueKey<String>('meter_row_${row.meter.id}'),
          title: Text(row.meter.apartmentLabel),
          subtitle: Padding(padding: const EdgeInsets.only(top: AppSpace.xs), child: StatusDot(label: row.detail, tone: _toneOf(row.state), maxLines: 3)),
          trailing: TextButton(
            key: ValueKey<String>('meter_pick_${row.meter.id}'),
            onPressed: () => Navigator.of(context).pop(row.meter),
            child: Text(row.retake ? 'Yeniden çek' : 'Çek'),
          ),
          onTap: () => Navigator.of(context).pop(row.meter),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final problem = <_MeterRow>[for (final r in rows) if (r.state == _MeterState.rejected || r.state == _MeterState.needsConfirm) r];
    final waiting = <_MeterRow>[for (final r in rows) if (r.state == _MeterState.waiting || r.state == _MeterState.skipped) r];
    final done = <_MeterRow>[for (final r in rows) if (r.state == _MeterState.queued || r.state == _MeterState.sent) r];
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: ListView(
          key: const ValueKey<String>('meter_list'),
          shrinkWrap: true,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.lg, AppSpace.lg, AppSpace.xs),
              child: Text(title, style: Theme.of(context).textTheme.titleMedium),
            ),
            if (rows.isEmpty) const Padding(padding: EdgeInsets.all(AppSpace.lg), child: Text('Bu blokta etkin sayaç yok.')),
            if (problem.isNotEmpty) ..._section(context, 'Sorunlu (${problem.length})', problem),
            if (waiting.isNotEmpty) ..._section(context, 'Çekilmeyenler (${waiting.length})', waiting),
            if (done.isNotEmpty) ..._section(context, 'Çekilenler (${done.length})', done),
          ],
        ),
      ),
    );
  }
}

class _PendingSheet extends StatefulWidget {
  const _PendingSheet({required this.queue, required this.onChanged, required this.onConfirmed});

  final MeterFieldQueue queue;
  final VoidCallback onChanged;

  /// Görevli olağan dışı tüketimi onayladı: ekran hemen göndermeyi dener (liste, tur bitince yenilensin diye beklenir).
  final Future<void> Function() onConfirmed;

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

  /// "Doğru": olağan dışı tüketim uyarısı onaylanır; kayıt `confirm_jump` ile gönderilir ve sunucuda onay izi tutulur.
  Future<void> _confirmJump(PendingMeterReading item) async {
    await widget.queue.confirmJump(item.id);
    await widget.onConfirmed();
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
                    key: ValueKey<String>('pending_${item.id}'),
                    leading: Icon(item.error == null ? Icons.schedule_rounded : Icons.error_outline_rounded),
                    title: Text('${item.apartmentLabel} · ${item.kindLabel} · ${formatMeterNumber(item.value)}'),
                    subtitle: Text(
                      item.needsJumpConfirm
                          ? '${item.error}\nDeğer doğruysa onaylayın; değilse düzeltin.'
                          : item.error ?? '${item.date} · gönderilmeyi bekliyor${item.photoPath == null ? '' : ' (fotoğraflı)'}${item.replace ? ' · yeniden çekim' : ''}',
                    ),
                    isThreeLine: item.needsJumpConfirm,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        if (item.needsJumpConfirm)
                          IconButton(key: ValueKey<String>('pending_confirm_${item.id}'), tooltip: 'Doğru, onayla ve gönder', icon: const Icon(Icons.task_alt_rounded), onPressed: () => _confirmJump(item)),
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
