import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:site_kapi_kontrol/models/plate_command_center_item.dart';
import 'package:site_kapi_kontrol/models/plate_gates.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/desktop_fullscreen_helper.dart';
import 'package:site_kapi_kontrol/services/plate_cameras_api.dart';
import 'package:site_kapi_kontrol/services/plate_recognition_api.dart';
import 'package:site_kapi_kontrol/services/plate_recognition_engine.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/plate_camera_form_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/plate_command_center_detail_dialogs.dart';
import 'package:site_kapi_kontrol/ui/dialogs/plate_discovery_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/plate_input.dart';
import 'package:site_kapi_kontrol/ui/widgets/plate_command_center_camera_wall.dart';
import 'package:site_kapi_kontrol/ui/widgets/plate_command_center_panels.dart';
import 'package:site_kapi_kontrol/ui/widgets/plate_gates_panel.dart'
    show GateEditDialog, GateTimingsDialog, GateTimingsDraft;

/// "Canlı Akış" düğmesine basıldığında tam ekran pencere olarak açılan
/// 4 Kameralı (2 Giriş + 2 Çıkış) Canlı İzleme ve Plaka Tanıma Komuta Merkezi.
Future<void> showPlateLiveCommandCenter(
  BuildContext context, {
  required AuthService authService,
  required PlateSite initialSite,
  required List<PlateSite> sites,
  PlateRecognitionService? service,
  PlateCamerasService? camerasService,
  int? initialGateId,
}) {
  return Navigator.of(context, rootNavigator: true).push<void>(
    PageRouteBuilder<void>(
      fullscreenDialog: true,
      opaque: true,
      transitionDuration: const Duration(milliseconds: 180),
      reverseTransitionDuration: const Duration(milliseconds: 140),
      pageBuilder: (ctx, animation, secondaryAnimation) => FadeTransition(
        opacity: animation,
        child: PlateLiveCommandCenterPage(
          authService: authService,
          initialSite: initialSite,
          sites: sites,
          service: service,
          camerasService: camerasService,
          initialGateId: initialGateId,
        ),
      ),
    ),
  );
}

class PlateLiveCommandCenterPage extends StatefulWidget {
  const PlateLiveCommandCenterPage({
    super.key,
    required this.authService,
    required this.initialSite,
    required this.sites,
    this.service,
    this.camerasService,
    this.initialGateId,
  });

  final AuthService authService;
  final PlateSite initialSite;
  final List<PlateSite> sites;
  final PlateRecognitionService? service;
  final PlateCamerasService? camerasService;
  final int? initialGateId;

  @override
  State<PlateLiveCommandCenterPage> createState() => _PlateLiveCommandCenterPageState();
}

class _PlateLiveCommandCenterPageState extends State<PlateLiveCommandCenterPage> {
  late final PlateRecognitionService _service =
      widget.service ?? PlateRecognitionService(authService: widget.authService);
  late final PlateCamerasService _cameras =
      widget.camerasService ?? PlateCamerasService(authService: widget.authService);

  late PlateSite _site = widget.initialSite;
  int? _selectedGateId;
  bool _loading = true;
  bool _windowFullscreen = false;

  PlateGatesOverview? _gatesOverview;
  PlateCamerasOverview? _camerasOverview;
  PlateInside? _inside;
  List<PlateDecisionRow> _serverEvents = const <PlateDecisionRow>[];
  List<PlateEngineDecision> _localDecisions = const <PlateEngineDecision>[];

  Timer? _pollTimer;
  int _refreshSeconds = 4;
  bool _pollBusy = false;
  StreamSubscription<PlateEngineDecision>? _engineSub;

  @override
  void initState() {
    super.initState();
    _selectedGateId = widget.initialGateId;
    _localDecisions = List<PlateEngineDecision>.from(PlateRecognitionEngine.instance.recentDecisions);
    unawaited(_enterNativeFullscreen());
    _engineSub = PlateRecognitionEngine.instance.decisionsStream.listen(_onEngineDecision);
    unawaited(_loadAll());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _engineSub?.cancel();
    unawaited(DesktopFullscreenHelper.exitFullscreen());
    super.dispose();
  }

  Future<void> _enterNativeFullscreen() async {
    final fs = await DesktopFullscreenHelper.enterFullscreen();
    if (mounted) {
      setState(() => _windowFullscreen = fs);
    }
  }

  Future<void> _toggleNativeFullscreen() async {
    final fs = await DesktopFullscreenHelper.toggleFullscreen();
    if (mounted) {
      setState(() => _windowFullscreen = fs);
    }
  }

  void _onEngineDecision(PlateEngineDecision d) {
    if (!mounted) return;
    setState(() {
      _localDecisions = List<PlateEngineDecision>.from(PlateRecognitionEngine.instance.recentDecisions);
    });
    if (!d.fromServer) {
      Future<void>.delayed(const Duration(milliseconds: 700), () {
        if (mounted) unawaited(_loadAll(silent: true, lightweight: true));
      });
    }
  }

  void _schedulePoll() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(Duration(seconds: _refreshSeconds.clamp(3, 15)), (_) {
      if (mounted) unawaited(_loadAll(silent: true, lightweight: true));
    });
  }

  PlateGate? get _selectedGate {
    final gates = _gatesOverview?.gates ?? const <PlateGate>[];
    if (gates.isEmpty) return null;
    if (_selectedGateId != null) {
      final match = gates.where((g) => g.id == _selectedGateId).firstOrNull;
      if (match != null) return match;
    }
    return gates.first;
  }

  Future<void> _loadAll({bool silent = false, bool lightweight = false}) async {
    if (_pollBusy && lightweight) return;
    _pollBusy = true;
    if (!silent && mounted) {
      setState(() => _loading = true);
    }

    final siteCode = _site.code;
    try {
      if (lightweight && _gatesOverview != null && _camerasOverview != null) {
        PlateLiveFeed? feed;
        PlateInside? inside;
        await Future.wait<void>(<Future<void>>[
          _service.liveFeed(siteCode, limit: 60).then<void>((v) {
            feed = v;
          }).catchError((_) {}),
          _service.inside(siteCode).then<void>((v) {
            inside = v;
          }).catchError((_) {}),
        ]);
        if (!mounted || _site.code != siteCode) return;
        if (feed != null && feed!.events.isNotEmpty) {
          PlateRecognitionEngine.instance.ingestServerDecisionRow(feed!.events.first);
        }
        setState(() {
          if (feed != null) {
            _serverEvents = feed!.events;
            if (feed!.refreshSeconds != _refreshSeconds) {
              _refreshSeconds = feed!.refreshSeconds.clamp(3, 15);
              _schedulePoll();
            }
          }
          if (inside != null) _inside = inside;
          _localDecisions = List<PlateEngineDecision>.from(PlateRecognitionEngine.instance.recentDecisions);
          _loading = false;
        });
        return;
      }

      PlateGatesOverview? gatesOv;
      PlateCamerasOverview? camsOv;
      PlateInside? inside;
      PlateLiveFeed? feed;

      await Future.wait<void>(<Future<void>>[
        _service.gatesOverview(siteCode).then<void>((v) {
          gatesOv = v;
        }).catchError((_) {}),
        _cameras.overview(siteCode).then<void>((v) {
          camsOv = v;
        }).catchError((_) {}),
        _service.inside(siteCode).then<void>((v) {
          inside = v;
        }).catchError((_) {}),
        _service.liveFeed(siteCode, limit: 60).then<void>((v) {
          feed = v;
        }).catchError((_) {}),
      ]);

      if (!mounted || _site.code != siteCode) return;

      final nextGates = gatesOv ?? _gatesOverview;
      if (nextGates != null && nextGates.gates.isNotEmpty) {
        if (_selectedGateId == null || !nextGates.gates.any((g) => g.id == _selectedGateId)) {
          _selectedGateId = nextGates.gates.first.id;
        }
      }

      setState(() {
        if (gatesOv != null) _gatesOverview = gatesOv;
        if (camsOv != null) _camerasOverview = camsOv;
        if (inside != null) _inside = inside;
        if (feed != null) {
          _serverEvents = feed!.events;
          _refreshSeconds = feed!.refreshSeconds.clamp(3, 15);
        }
        _localDecisions = List<PlateEngineDecision>.from(PlateRecognitionEngine.instance.recentDecisions);
        _loading = false;
      });

      _schedulePoll();
      unawaited(_syncEngineForSite(camsOv?.cameras, inside));
    } finally {
      _pollBusy = false;
      if (mounted && _loading && !silent) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _syncEngineForSite(List<PlateCameraRow>? cams, PlateInside? insideData) async {
    if (_site.isResident) return;
    try {
      final cameras = cams ?? _camerasOverview?.cameras ?? PlateRecognitionEngine.instance.activeCameras;
      List<PlateBlacklistItem> blacklist = const <PlateBlacklistItem>[];
      List<PlatePermit> permits = const <PlatePermit>[];
      try {
        blacklist = await _service.blacklist(_site.code);
      } catch (_) {}
      try {
        permits = await _service.permits(_site.code);
      } catch (_) {}

      final parkingSlots = <int, int>{};
      final insideCounts = <int, int>{};
      final slotsByLabel = <String, int>{};
      final insideByLabel = <String, int>{};
      final ins = insideData ?? _inside;
      if (ins != null) {
        for (final apt in ins.apartments) {
          if (apt.id != null) {
            parkingSlots[apt.id!] = apt.parkingSlots;
            insideCounts[apt.id!] = apt.insideCount;
          }
          slotsByLabel[apt.label] = apt.parkingSlots;
          insideByLabel[apt.label] = apt.insideCount;
        }
      }

      final vehiclesMap = <String, Map<String, dynamic>>{};
      try {
        final session = widget.authService.session;
        if (session != null) {
          final page = await widget.authService.api.listVehicles(
            token: session.token,
            siteCode: _site.code,
            limit: 200,
          );
          for (final v in page.items) {
            final norm = canonicalTrPlate(v.plate);
            if (norm.isNotEmpty) {
              vehiclesMap[norm] = <String, dynamic>{
                'plate': norm,
                'person_label': v.personName,
                'apartment_label': v.apartmentLabel,
              };
            }
          }
        }
      } catch (_) {}

      PlateRecognitionEngine.instance.start(
        siteCode: _site.code,
        baseUrl: widget.authService.api.baseUrl,
        token: widget.authService.session?.token,
        cameras: cameras,
        blacklist: blacklist,
        guestPermits: permits,
        vehicles: vehiclesMap,
        parkingSlots: parkingSlots,
        insideCounts: insideCounts,
        parkingSlotsByLabel: slotsByLabel,
        insideCountsByLabel: insideByLabel,
      );
      if (mounted) setState(() {});
    } catch (_) {}
  }

  /// Seçili kapının hedef kamera yönünü (`giris` veya `cikis`) desteklediğinden emin olur;
  /// sitede hiç kapı yoksa otomatik çift yönlü `Ana Giriş Kapısı` açar, kapı tek yönlüyse `cift`e yükseltir.
  Future<int?> _prepareGateForDirection(String targetDirection) async {
    var gate = _selectedGate;
    if (gate == null) {
      final createdOv = await _service.createGatePoint(
        _site.code,
        const GateDraft(name: 'Ana Giriş Kapısı', directionMode: 'cift'),
      );
      _gatesOverview = createdOv;
      gate = createdOv.gates.firstOrNull;
      _selectedGateId = gate?.id;
      return gate?.id;
    }

    if (!gateCameraDirectionFits(gate.directionMode, targetDirection)) {
      final updatedOv = await _service.updateGatePoint(
        _site.code,
        gate.id,
        GateDraft(
          name: gate.name,
          directionMode: 'cift',
          deviceUid: gate.deviceUid,
          consecutiveVehicleDelaySeconds: gate.consecutiveVehicleDelaySeconds,
          entryRearSuppressSeconds: gate.entryRearSuppressSeconds,
          exitRearSuppressSeconds: gate.exitRearSuppressSeconds,
          cameras: <GateCameraDraft>[
            for (final c in gate.cameras) GateCameraDraft(cameraId: c.cameraId, direction: c.direction),
          ],
        ),
      );
      _gatesOverview = updatedOv;
    }
    return gate.id;
  }

  Future<void> _addCameraForSlot({
    String? direction,
    String? suggestedName,
  }) async {
    if (!_site.canWrite) return;
    try {
      final gateId = direction != null
          ? await _prepareGateForDirection(direction)
          : (_selectedGate?.id ?? await _prepareGateForDirection('giris'));
      final overview = await _cameras.overview(_site.code);
      if (!mounted) return;
      int? probeId;
      final saved = await showPlateCameraForm(
        context,
        overview: overview,
        initialGateId: gateId,
        initialDirection: direction,
        initialName: suggestedName,
        onSave: (draft) async {
          final created = await _cameras.createCamera(_site.code, draft);
          probeId = created.probeCommandId;
        },
      );
      if (saved == true && mounted) {
        AppSnack.show(context, plateCameraSavedMessage(probeId, overview), kind: AppSnackKind.success);
        await _loadAll(silent: true);
      }
    } on ApiException catch (e) {
      if (mounted) AppSnack.show(context, e.message, kind: AppSnackKind.error);
    }
  }

  Future<void> _discoverCameraForSlot({
    String? direction,
    String? suggestedName,
  }) async {
    if (!_site.canWrite) return;
    try {
      final gateId = direction != null
          ? await _prepareGateForDirection(direction)
          : (_selectedGate?.id ?? await _prepareGateForDirection('giris'));
      final overview = await _cameras.overview(_site.code);
      if (!mounted) return;
      final choice = await showPlateDiscoveryDialog(
        context,
        service: _cameras,
        siteCode: _site.code,
        edge: overview.edge,
      );
      if (choice != null && mounted) {
        int? probeId;
        final saved = await showPlateCameraForm(
          context,
          overview: overview,
          prefill: choice.device,
          initialGateId: gateId,
          initialDirection: direction,
          initialName: suggestedName,
          onSave: (draft) async {
            final created = await _cameras.createCamera(_site.code, draft);
            probeId = created.probeCommandId;
          },
        );
        if (saved == true && mounted) {
          AppSnack.show(context, plateCameraSavedMessage(probeId, overview), kind: AppSnackKind.success);
          await _loadAll(silent: true);
        }
      }
    } on ApiException catch (e) {
      if (mounted) AppSnack.show(context, e.message, kind: AppSnackKind.error);
    }
  }

  Future<void> _attachExistingCameraToSlot(PlateCameraRow camera, String direction) async {
    if (!_site.canWrite) return;
    try {
      final gateId = await _prepareGateForDirection(direction);
      if (gateId == null) return;
      await _cameras.updateCamera(
        _site.code,
        camera.id,
        PlateCameraDraft(
          name: camera.name,
          brand: camera.brand,
          host: camera.host,
          port: camera.port?.toString(),
          rtspInput: camera.rtspUrl,
          username: camera.username,
          gateId: gateId,
          direction: direction,
        ),
      );
      if (!mounted) return;
      AppSnack.show(
        context,
        '${camera.name} kamerası ${direction == 'cikis' ? 'Çıkış' : 'Giriş'} yuvasına bağlandı.',
        kind: AppSnackKind.success,
      );
      await _loadAll(silent: true);
    } on ApiException catch (e) {
      if (mounted) AppSnack.show(context, e.message, kind: AppSnackKind.error);
    }
  }

  Future<void> _editCamera(PlateCameraRow camRow) async {
    if (!_site.canWrite) return;
    try {
      final overview = await _cameras.overview(_site.code);
      if (!mounted) return;
      final latest = overview.cameras.where((c) => c.id == camRow.id).firstOrNull ?? camRow;
      int? probeId;
      final saved = await showPlateCameraForm(
        context,
        overview: overview,
        editing: latest,
        onSave: (draft) async {
          final res = await _cameras.updateCamera(_site.code, latest.id, draft);
          probeId = res.probeCommandId;
        },
      );
      if (saved == true && mounted) {
        AppSnack.show(context, plateCameraSavedMessage(probeId, overview), kind: AppSnackKind.success);
        await _loadAll(silent: true);
      }
    } on ApiException catch (e) {
      if (mounted) AppSnack.show(context, e.message, kind: AppSnackKind.error);
    }
  }

  Future<void> _createNewGate() async {
    if (!_site.canWrite) return;
    try {
      final ov = _gatesOverview ?? await _service.gatesOverview(_site.code);
      if (!mounted) return;
      final draft = await showDialog<GateDraft>(
        context: context,
        builder: (_) => GateEditDialog(overview: ov),
      );
      if (draft == null || !mounted) return;
      final updated = await _service.createGatePoint(_site.code, draft);
      if (!mounted) return;
      setState(() {
        _gatesOverview = updated;
        if (updated.gates.isNotEmpty) {
          _selectedGateId = updated.gates.last.id;
        }
      });
      AppSnack.show(context, 'Yeni geçiş kapısı oluşturuldu.', kind: AppSnackKind.success);
      await _loadAll(silent: true);
    } on ApiException catch (e) {
      if (mounted) AppSnack.show(context, e.message, kind: AppSnackKind.error);
    }
  }

  Future<void> _editGateTimings() async {
    final gate = _selectedGate;
    if (!_site.canWrite || gate == null) return;
    final result = await showDialog<GateTimingsDraft>(
      context: context,
      builder: (_) => GateTimingsDialog(gate: gate),
    );
    if (result == null || !mounted) return;

    PlateRecognitionEngine.instance.updateGateCooldowns(
      gateId: gate.id,
      consecutiveVehicleDelaySeconds: result.consecutiveVehicleDelaySeconds,
      entryRearSuppressSeconds: result.entryRearSuppressSeconds,
      exitRearSuppressSeconds: result.exitRearSuppressSeconds,
    );

    try {
      final updated = await _service.updateGatePoint(
        _site.code,
        gate.id,
        GateDraft(
          name: gate.name,
          directionMode: gate.directionMode,
          deviceUid: gate.deviceUid,
          consecutiveVehicleDelaySeconds: result.consecutiveVehicleDelaySeconds,
          entryRearSuppressSeconds: result.entryRearSuppressSeconds,
          exitRearSuppressSeconds: result.exitRearSuppressSeconds,
          cameras: <GateCameraDraft>[
            for (final c in gate.cameras) GateCameraDraft(cameraId: c.cameraId, direction: c.direction),
          ],
        ),
      );
      if (!mounted) return;
      setState(() => _gatesOverview = updated);
      AppSnack.show(context, '${gate.name} geçiş süreleri güncellendi.', kind: AppSnackKind.success);
    } on ApiException catch (e) {
      if (mounted) AppSnack.show(context, e.message, kind: AppSnackKind.error);
    }
  }

  Future<void> _grantGuestPermit({String? prefillPlate}) async {
    if (!_site.canWrite) return;
    final plateCtrl = TextEditingController(text: prefillPlate != null ? formatTrPlate(prefillPlate) : '');
    final noteCtrl = TextEditingController();
    PlateApartment? selectedApartment;
    String duration = 'day';
    String? formErr;
    String lastQuery = '';

    final draft = await showDialog<PermitDraft>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Misafir Plaka İzni Ver'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Autocomplete<PlateApartment>(
                    displayStringForOption: (a) => a.label,
                    optionsBuilder: (val) async {
                      lastQuery = val.text;
                      await Future<void>.delayed(const Duration(milliseconds: 260));
                      if (lastQuery != val.text) return const <PlateApartment>[];
                      try {
                        return await _service.searchApartments(_site.code, val.text);
                      } catch (_) {
                        return const <PlateApartment>[];
                      }
                    },
                    onSelected: (a) => setLocal(() => selectedApartment = a),
                    fieldViewBuilder: (context, ctrl, focus, _) => TextField(
                      controller: ctrl,
                      focusNode: focus,
                      onChanged: (_) {
                        if (selectedApartment != null) setLocal(() => selectedApartment = null);
                      },
                      decoration: InputDecoration(
                        labelText: 'Daire (blok veya daire no yazın)',
                        suffixIcon: selectedApartment != null ? const Icon(Icons.check_circle_rounded) : null,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpace.sm),
                  TextField(
                    controller: plateCtrl,
                    inputFormatters: const <TextInputFormatter>[PlateInputFormatter()],
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(labelText: 'Plaka', hintText: '34 ABC 123'),
                  ),
                  const SizedBox(height: AppSpace.sm),
                  Wrap(
                    spacing: 8,
                    children: <Widget>[
                      ChoiceChip(
                        label: const Text('1 Gün'),
                        selected: duration == 'day',
                        onSelected: (_) => setLocal(() => duration = 'day'),
                      ),
                      ChoiceChip(
                        label: const Text('1 Hafta'),
                        selected: duration == 'week',
                        onSelected: (_) => setLocal(() => duration = 'week'),
                      ),
                    ],
                  ),
                  TextField(
                    controller: noteCtrl,
                    maxLength: 100,
                    decoration: const InputDecoration(labelText: 'Not (isteğe bağlı)', counterText: ''),
                  ),
                  if (formErr != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(formErr!, style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
                    ),
                ],
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
            FilledButton(
              onPressed: () {
                final norm = normalizeTrPlate(plateCtrl.text);
                if (norm == null) {
                  setLocal(() => formErr = kPlateInvalidMessage);
                  return;
                }
                if (selectedApartment == null) {
                  setLocal(() => formErr = 'Lütfen daire seçin.');
                  return;
                }
                Navigator.pop(
                  ctx,
                  PermitDraft(
                    apartmentId: selectedApartment!.id,
                    plate: norm,
                    duration: duration,
                    note: noteCtrl.text,
                  ),
                );
              },
              child: const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );
    plateCtrl.dispose();
    noteCtrl.dispose();
    if (draft == null || !mounted) return;

    try {
      await _service.createPermit(_site.code, draft);
      if (!mounted) return;
      AppSnack.show(context, 'Misafir plaka izni kaydedildi.', kind: AppSnackKind.success);
      await _loadAll(silent: true);
    } on ApiException catch (e) {
      if (mounted) AppSnack.show(context, e.message, kind: AppSnackKind.error);
    }
  }

  Future<void> _addToBlacklist({String? prefillPlate}) async {
    if (!_site.canWrite) return;
    final plateCtrl = TextEditingController(text: prefillPlate != null ? formatTrPlate(prefillPlate) : '');
    final reasonCtrl = TextEditingController();
    String? formErr;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Kara Listeye Plaka Ekle'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                TextField(
                  controller: plateCtrl,
                  inputFormatters: const <TextInputFormatter>[PlateInputFormatter()],
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(labelText: 'Plaka', hintText: '34 ABC 123'),
                ),
                TextField(
                  controller: reasonCtrl,
                  maxLength: 200,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Gerekçe (isteğe bağlı)', counterText: ''),
                ),
                if (formErr != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(formErr!, style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
                  ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
            FilledButton(
              onPressed: () {
                if (normalizeTrPlate(plateCtrl.text) == null) {
                  setLocal(() => formErr = kPlateInvalidMessage);
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('Kara Listeye Ekle'),
            ),
          ],
        ),
      ),
    );
    final norm = normalizeTrPlate(plateCtrl.text);
    final reason = reasonCtrl.text;
    plateCtrl.dispose();
    reasonCtrl.dispose();
    if (ok != true || norm == null || !mounted) return;

    try {
      await _service.addBlacklist(_site.code, norm, reason);
      if (!mounted) return;
      AppSnack.show(context, 'Plaka kara listeye eklendi.', kind: AppSnackKind.success);
      await _loadAll(silent: true);
    } on ApiException catch (e) {
      if (mounted) AppSnack.show(context, e.message, kind: AppSnackKind.error);
    }
  }

  Future<void> _showSimulateOrManualTriggerDialog({
    String? initialPlate,
    String initialDirection = 'giris',
  }) async {
    final plateCtrl = TextEditingController(text: initialPlate != null ? formatTrPlate(initialPlate) : '34 ABC 123');
    String direction = initialDirection;
    bool busy = false;
    PlateEngineDecision? lastRes;
    final gate = _selectedGate;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('Kapı Tetikle / Plaka Testi${gate != null ? ' • ${gate.name}' : ''}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Plakayı test ederek otopark kabul kuralını ve SmartKeyPass kapı açma sinyalini anında tetikleyebilirsiniz.',
                  style: TextStyle(fontSize: 12.5),
                ),
                const SizedBox(height: AppSpace.sm),
                TextField(
                  controller: plateCtrl,
                  inputFormatters: const <TextInputFormatter>[PlateInputFormatter()],
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(labelText: 'Plaka', hintText: '34 ABC 123'),
                ),
                const SizedBox(height: AppSpace.sm),
                Wrap(
                  spacing: 8,
                  children: <Widget>[
                    ChoiceChip(
                      label: const Text('Giriş Yönü'),
                      selected: direction == 'giris',
                      onSelected: (_) => setLocal(() => direction = 'giris'),
                    ),
                    ChoiceChip(
                      label: const Text('Çıkış Yönü'),
                      selected: direction == 'cikis',
                      onSelected: (_) => setLocal(() => direction = 'cikis'),
                    ),
                  ],
                ),
                if (lastRes != null) ...<Widget>[
                  const SizedBox(height: AppSpace.md),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: lastRes!.decision == PlateDecisionType.acildi
                          ? const Color(0xFF10B981).withValues(alpha: 0.14)
                          : const Color(0xFFEF4444).withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Text(
                      '${lastRes!.decision == PlateDecisionType.acildi ? 'KAPI TETİKLENDİ ✓' : 'KAPI AÇILMADI ✕'}\n${lastRes!.reason}',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Kapat')),
            FilledButton.icon(
              onPressed: busy
                  ? null
                  : () async {
                      setLocal(() => busy = true);
                      final res = await PlateRecognitionEngine.instance.testProcessPlate(
                        plateCtrl.text,
                        gateId: gate?.doorId ?? gate?.id,
                        gateName: gate?.name,
                        direction: direction,
                      );
                      if (ctx.mounted) {
                        setLocal(() {
                          busy = false;
                          lastRes = res;
                        });
                      }
                    },
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Tetikle & Test Et'),
            ),
          ],
        ),
      ),
    );
    plateCtrl.dispose();
  }

  Future<void> _clearInsideVehicle(int insideId) async {
    try {
      await _service.clearInside(_site.code, insideId);
      if (!mounted) return;
      AppSnack.show(context, 'Araç içeride listesinden düşürüldü.', kind: AppSnackKind.success);
      await _loadAll(silent: true, lightweight: true);
    } on ApiException catch (e) {
      if (mounted) AppSnack.show(context, e.message, kind: AppSnackKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final gates = _gatesOverview?.gates ?? const <PlateGate>[];
    final selectedGate = _selectedGate;
    final cameras = _camerasOverview?.cameras ?? PlateRecognitionEngine.instance.activeCameras;
    final slots = GateCameraWallSlots.resolve(gate: selectedGate, cameras: cameras);

    final allEvents = mergeLiveStreamEvents(
      localDecisions: _localDecisions,
      serverRows: _serverEvents,
    );
    final entryEvents = allEvents.where((e) => e.direction != 'cikis').toList();
    final exitEvents = allEvents.where((e) => e.direction == 'cikis').toList();
    final engineRunning = PlateRecognitionEngine.instance.isRunning;

    void openParkingModal() {
      showLiveParkingDetailDialog(
        context,
        inside: _inside ?? const PlateInside(total: 0, items: <InsideItem>[], apartments: <InsideApartment>[]),
        canWrite: _site.canWrite,
        onClearInsideItem: _clearInsideVehicle,
      );
    }

    void openEventModal(PlateLiveStreamEvent ev) {
      showPlateEventDetailDialog(
        context,
        event: ev,
        canWrite: _site.canWrite,
        onGrantGuestPermit: (p) => unawaited(_grantGuestPermit(prefillPlate: p)),
        onAddToBlacklist: (p) => unawaited(_addToBlacklist(prefillPlate: p)),
        onManualTrigger: (p, dir) => unawaited(
          _showSimulateOrManualTriggerDialog(initialPlate: p, initialDirection: dir),
        ),
      );
    }

    void openSystemModal() {
      showSystemAndGateDetailDialog(
        context,
        site: _site,
        selectedGate: selectedGate,
        slots: slots,
        engineRunning: engineRunning,
        onEditGateTimings: _editGateTimings,
        onCreateGate: _createNewGate,
        onEditCamera: _editCamera,
      );
    }

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).maybePop(),
        const SingleActivator(LogicalKeyboardKey.f11): () => unawaited(_toggleNativeFullscreen()),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: const Color(0xFF050811),
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 980 && constraints.maxHeight >= 540;
                final leftWidth = (constraints.maxWidth * 0.165).clamp(218.0, 265.0);
                final rightWidth = (constraints.maxWidth * 0.175).clamp(230.0, 285.0);

                final menuCard = CommandCenterMenuCard(
                  site: _site,
                  sites: widget.sites,
                  gates: gates,
                  selectedGate: selectedGate,
                  slots: slots,
                  engineRunning: engineRunning,
                  isWindowFullscreen: _windowFullscreen,
                  expandedHeight: isWide,
                  onSelectSite: (nextSite) {
                    setState(() {
                      _site = nextSite;
                      _selectedGateId = null;
                      _gatesOverview = null;
                      _camerasOverview = null;
                    });
                    unawaited(_loadAll());
                  },
                  onSelectGate: (gate) => setState(() => _selectedGateId = gate.id),
                  onClose: () => Navigator.of(context).maybePop(),
                  onToggleFullscreen: () => unawaited(_toggleNativeFullscreen()),
                  onRefresh: () => unawaited(_loadAll()),
                  onOpenSystemDetail: openSystemModal,
                  onSimulateOrManualOpen: () => unawaited(_showSimulateOrManualTriggerDialog()),
                  onAddCamera: () => unawaited(_addCameraForSlot()),
                  onDiscoverCameras: () => unawaited(_discoverCameraForSlot()),
                  onGrantGuestPermit: () => unawaited(_grantGuestPermit()),
                  onAddBlacklist: () => unawaited(_addToBlacklist()),
                  onEditGateTimings: () => unawaited(_editGateTimings()),
                  onCreateGate: () => unawaited(_createNewGate()),
                );

                final parkingCard = CommandCenterParkingCard(
                  inside: _inside,
                  expandedHeight: isWide,
                  onOpenDetail: openParkingModal,
                );

                final cameraWall = CommandCenterCameraWall(
                  siteCode: _site.code,
                  canWrite: _site.canWrite,
                  slots: slots,
                  camerasService: _cameras,
                  expandedHeight: isWide,
                  onAddCamera: (dir, slotNum, suggestedName) => unawaited(
                    _addCameraForSlot(direction: dir, suggestedName: suggestedName),
                  ),
                  onDiscoverCamera: (dir, slotNum, suggestedName) => unawaited(
                    _discoverCameraForSlot(direction: dir, suggestedName: suggestedName),
                  ),
                  onAttachExistingCamera: (cam, dir) => unawaited(
                    _attachExistingCameraToSlot(cam, dir),
                  ),
                  onEditCamera: (cam) => unawaited(_editCamera(cam)),
                );

                final entryEventsCard = CommandCenterEventsCard(
                  cardKey: 'cc_entry_events_card',
                  title: 'Giriş Olayları',
                  emptyText: 'Henüz giriş olayı yok.\nKameralar canlı izleniyor.',
                  accentColor: const Color(0xFF10B981),
                  icon: Icons.login_rounded,
                  events: entryEvents,
                  expandedHeight: isWide,
                  onTapEvent: openEventModal,
                  onTapHeader: () => showPlateEventsListDetailDialog(
                    context,
                    title: 'Giriş Olayları',
                    events: entryEvents,
                    canWrite: _site.canWrite,
                    onGrantGuestPermit: (p) => unawaited(_grantGuestPermit(prefillPlate: p)),
                    onAddToBlacklist: (p) => unawaited(_addToBlacklist(prefillPlate: p)),
                    onManualTrigger: (p, dir) => unawaited(
                      _showSimulateOrManualTriggerDialog(initialPlate: p, initialDirection: dir),
                    ),
                  ),
                );

                final exitEventsCard = CommandCenterEventsCard(
                  cardKey: 'cc_exit_events_card',
                  title: 'Çıkış Olayları',
                  emptyText: 'Henüz çıkış olayı yok.\nKameralar canlı izleniyor.',
                  accentColor: const Color(0xFF38BDF8),
                  icon: Icons.logout_rounded,
                  events: exitEvents,
                  expandedHeight: isWide,
                  onTapEvent: openEventModal,
                  onTapHeader: () => showPlateEventsListDetailDialog(
                    context,
                    title: 'Çıkış Olayları',
                    events: exitEvents,
                    canWrite: _site.canWrite,
                    onGrantGuestPermit: (p) => unawaited(_grantGuestPermit(prefillPlate: p)),
                    onAddToBlacklist: (p) => unawaited(_addToBlacklist(prefillPlate: p)),
                    onManualTrigger: (p, dir) => unawaited(
                      _showSimulateOrManualTriggerDialog(initialPlate: p, initialDirection: dir),
                    ),
                  ),
                );

                if (_loading && _gatesOverview == null && _camerasOverview == null) {
                  return const Center(
                    child: CircularProgressIndicator(color: Color(0xFF10B981)),
                  );
                }

                if (isWide) {
                  // Wireframe 3 sütunlu kenardan kenara tam ekran düzeni
                  return Padding(
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        // SOL SÜTUN: Menüler & Diğer Bilgiler + Canlı Otopark Durum Bilgisi
                        SizedBox(
                          width: leftWidth,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              Expanded(flex: 53, child: menuCard),
                              const SizedBox(height: 8),
                              Expanded(flex: 47, child: parkingCard),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),

                        // ORTA SÜTUN (DEVASA ALAN): Giriş Kameraları (2) + Çıkış Kameraları (2)
                        Expanded(child: cameraWall),
                        const SizedBox(width: 8),

                        // SAĞ SÜTUN: Giriş Olayları + Çıkış Olayları
                        SizedBox(
                          width: rightWidth,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              Expanded(child: entryEventsCard),
                              const SizedBox(height: 8),
                              Expanded(child: exitEventsCard),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }

                // Dar ekran / mobil / tablet taşma-korumalı dikey düzen
                return RefreshIndicator(
                  onRefresh: _loadAll,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        menuCard,
                        const SizedBox(height: 8),
                        cameraWall,
                        const SizedBox(height: 8),
                        parkingCard,
                        const SizedBox(height: 8),
                        entryEventsCard,
                        const SizedBox(height: 8),
                        exitEventsCard,
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
