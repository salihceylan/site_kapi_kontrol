import 'package:flutter/foundation.dart';
import 'package:site_kapi_kontrol/models/plate_gates.dart';
import 'package:site_kapi_kontrol/services/plate_cameras_api.dart';
import 'package:site_kapi_kontrol/services/plate_recognition_api.dart';
import 'package:site_kapi_kontrol/services/plate_recognition_engine.dart';

/// Tam ekran Canlı Akış komuta merkezinde Giriş Olayları ve Çıkış Olayları
/// panellerinde akan birleştirilmiş (yerel motor + bulut sunucu) geçiş olayı.
@immutable
class PlateLiveStreamEvent {
  const PlateLiveStreamEvent({
    required this.key,
    required this.plate,
    required this.decision,
    required this.reason,
    required this.direction,
    required this.gateName,
    required this.timestamp,
    this.serverId,
    this.cameraId,
    this.cameraName,
    this.apartmentLabel,
    this.personLabel,
    this.isGuest = false,
    this.confidence,
    this.isGateTriggered = false,
    this.gateState,
    this.snapshotBytes,
  });

  factory PlateLiveStreamEvent.fromEngine(PlateEngineDecision d) {
    final norm = canonicalTrPlate(d.plate);
    final dir = d.direction == 'cikis' ? 'cikis' : 'giris';
    final person = d.personLabel?.trim();
    final isGuest = (person ?? '').toLowerCase().contains('misafir');
    return PlateLiveStreamEvent(
      key: 'eng_${d.timestamp.microsecondsSinceEpoch}_$norm',
      plate: norm.isNotEmpty ? norm : d.plate,
      decision: d.decision,
      reason: d.reason,
      direction: dir,
      gateName: d.gateName,
      timestamp: d.timestamp,
      cameraId: d.cameraId,
      cameraName: d.cameraName,
      apartmentLabel: d.apartmentLabel,
      personLabel: person,
      isGuest: isGuest,
      confidence: d.confidence,
      isGateTriggered: d.isGateTriggered,
      gateState: d.isGateTriggered ? 'triggered' : null,
      snapshotBytes: d.snapshotBytes,
    );
  }

  factory PlateLiveStreamEvent.fromServerRow(PlateDecisionRow row) {
    final norm = canonicalTrPlate(row.plate);
    final decision = switch (row.decisionKind) {
      'acildi' => PlateDecisionType.acildi,
      'kara_liste' => PlateDecisionType.karaListe,
      'red' => PlateDecisionType.red,
      'tanimsiz' => PlateDecisionType.tanimsiz,
      _ => switch (row.decision) {
          'ALLOWED' => PlateDecisionType.acildi,
          'DENIED' => PlateDecisionType.red,
          _ => PlateDecisionType.tanimsiz,
        },
    };
    final dir = row.direction == 'cikis' ? 'cikis' : 'giris';
    final gate = (row.doorName ?? '').trim().isNotEmpty
        ? row.doorName!.trim()
        : ((row.deviceName ?? '').trim().isNotEmpty ? row.deviceName!.trim() : 'Geçiş Kapısı');
    return PlateLiveStreamEvent(
      key: 'srv_${row.id}_$norm',
      serverId: row.id,
      plate: norm.isNotEmpty ? norm : row.plate,
      decision: decision,
      reason: row.reasonLabel.trim().isNotEmpty ? row.reasonLabel.trim() : 'Kayıt alındı',
      direction: dir,
      gateName: gate,
      cameraName: row.deviceName,
      apartmentLabel: row.identity?.apartmentLabel,
      personLabel: row.identity?.personLabel,
      isGuest: row.identity?.isGuest ?? false,
      confidence: row.confidence,
      isGateTriggered: row.gateState == 'triggered' || decision == PlateDecisionType.acildi,
      gateState: row.gateState,
      timestamp: row.seenAt ?? DateTime.now(),
    );
  }

  final String key;
  final int? serverId;
  final String plate;
  final PlateDecisionType decision;
  final String reason;

  /// `'giris'` | `'cikis'`
  final String direction;
  final String gateName;
  final int? cameraId;
  final String? cameraName;
  final String? apartmentLabel;
  final String? personLabel;
  final bool isGuest;
  final double? confidence;
  final bool isGateTriggered;
  final String? gateState;
  final DateTime timestamp;
  final Uint8List? snapshotBytes;

  String get formattedPlate => formatTrPlate(plate);

  String get decisionLabel => switch (decision) {
    PlateDecisionType.acildi => 'İZİN VERİLDİ',
    PlateDecisionType.karaListe => 'KARA LİSTE',
    PlateDecisionType.red => 'REDDEDİLDİ',
    PlateDecisionType.tanimsiz => 'TANIMSIZ',
  };

  String? get identitySummary {
    final apt = (apartmentLabel ?? '').trim();
    final person = (personLabel ?? '').trim();
    if (isGuest) {
      if (apt.isNotEmpty && person.isNotEmpty && !person.toLowerCase().startsWith('misafir')) {
        return 'Misafir • $apt ($person)';
      }
      if (apt.isNotEmpty) return 'Misafir • $apt';
      if (person.isNotEmpty) return person;
      return 'Misafir Aracı';
    }
    if (apt.isNotEmpty && person.isNotEmpty) return '$apt • $person';
    if (apt.isNotEmpty) return 'Daire $apt';
    if (person.isNotEmpty) return person;
    return null;
  }

  PlateLiveStreamEvent mergeSnapshotFrom(PlateLiveStreamEvent local) {
    return PlateLiveStreamEvent(
      key: key,
      serverId: serverId ?? local.serverId,
      plate: plate,
      decision: decision,
      reason: reason.isNotEmpty ? reason : local.reason,
      direction: direction,
      gateName: gateName,
      timestamp: timestamp,
      cameraId: cameraId ?? local.cameraId,
      cameraName: (cameraName ?? '').isNotEmpty ? cameraName : local.cameraName,
      apartmentLabel: (apartmentLabel ?? '').isNotEmpty ? apartmentLabel : local.apartmentLabel,
      personLabel: (personLabel ?? '').isNotEmpty ? personLabel : local.personLabel,
      isGuest: isGuest || local.isGuest,
      confidence: confidence ?? local.confidence,
      isGateTriggered: isGateTriggered || local.isGateTriggered,
      gateState: gateState ?? local.gateState,
      snapshotBytes: snapshotBytes ?? local.snapshotBytes,
    );
  }
}

/// Yerel motor kararları ile sunucu `liveFeed` kayıtlarını mükerrerlik üretmeden birleştirir.
List<PlateLiveStreamEvent> mergeLiveStreamEvents({
  required List<PlateEngineDecision> localDecisions,
  required List<PlateDecisionRow> serverRows,
  int maxItems = 80,
}) {
  final serverEvents = <PlateLiveStreamEvent>[
    for (final r in serverRows) PlateLiveStreamEvent.fromServerRow(r),
  ];
  final localEvents = <PlateLiveStreamEvent>[
    for (final d in localDecisions)
      if (!d.fromServer) PlateLiveStreamEvent.fromEngine(d),
  ];

  final merged = <PlateLiveStreamEvent>[];
  final matchedLocalIndices = <int>{};

  for (final srv in serverEvents) {
    var enriched = srv;
    for (var i = 0; i < localEvents.length; i++) {
      if (matchedLocalIndices.contains(i)) continue;
      final loc = localEvents[i];
      if (loc.plate == srv.plate &&
          loc.direction == srv.direction &&
          loc.timestamp.difference(srv.timestamp).inSeconds.abs() <= 14) {
        enriched = srv.mergeSnapshotFrom(loc);
        matchedLocalIndices.add(i);
        break;
      }
    }
    merged.add(enriched);
  }

  for (var i = 0; i < localEvents.length; i++) {
    if (!matchedLocalIndices.contains(i)) {
      merged.add(localEvents[i]);
    }
  }

  merged.sort((a, b) => b.timestamp.compareTo(a.timestamp));
  if (merged.length > maxItems) {
    return merged.sublist(0, maxItems);
  }
  return merged;
}

/// Seçili kapının 4 kamera yuvası (2 Giriş + 2 Çıkış) ve atanmamış kameralar.
@immutable
class GateCameraWallSlots {
  const GateCameraWallSlots({
    required this.gate,
    required this.entry1,
    required this.entry2,
    required this.exit1,
    required this.exit2,
    required this.unassignedCameras,
  });

  factory GateCameraWallSlots.resolve({
    required PlateGate? gate,
    required List<PlateCameraRow> cameras,
  }) {
    final sorted = List<PlateCameraRow>.from(cameras)..sort((a, b) => a.id.compareTo(b.id));
    final unassigned = sorted.where((c) => c.gate == null).toList();

    final List<PlateCameraRow> pool;
    if (gate != null) {
      pool = sorted.where((c) => c.gate?.id == gate.id).toList();
    } else {
      // Sitede henüz kapı açılmamışsa mevcut kameraları yine de yuvalarda göster
      pool = unassigned;
    }

    final entries = <PlateCameraRow>[];
    final exits = <PlateCameraRow>[];
    final autos = <PlateCameraRow>[];

    for (final cam in pool) {
      if (cam.direction == 'cikis') {
        exits.add(cam);
      } else if (cam.direction == 'giris') {
        entries.add(cam);
      } else {
        autos.add(cam);
      }
    }

    // 'auto' yönlü kameraları önce boş giriş yuvalarına, sonra boş çıkış yuvalarına yerleştir
    for (final autoCam in autos) {
      if (entries.length < 2) {
        entries.add(autoCam);
      } else {
        exits.add(autoCam);
      }
    }

    return GateCameraWallSlots(
      gate: gate,
      entry1: entries.isNotEmpty ? entries[0] : null,
      entry2: entries.length > 1 ? entries[1] : null,
      exit1: exits.isNotEmpty ? exits[0] : null,
      exit2: exits.length > 1 ? exits[1] : null,
      unassignedCameras: gate != null ? unassigned : const <PlateCameraRow>[],
    );
  }

  final PlateGate? gate;
  final PlateCameraRow? entry1;
  final PlateCameraRow? entry2;
  final PlateCameraRow? exit1;
  final PlateCameraRow? exit2;
  final List<PlateCameraRow> unassignedCameras;

  int get activeCount => <PlateCameraRow?>[entry1, entry2, exit1, exit2]
      .where((c) => c != null && c.isActive)
      .length;

  int get configuredCount => <PlateCameraRow?>[entry1, entry2, exit1, exit2]
      .where((c) => c != null)
      .length;

  int get entryCount => (entry1 != null ? 1 : 0) + (entry2 != null ? 1 : 0);
  int get exitCount => (exit1 != null ? 1 : 0) + (exit2 != null ? 1 : 0);
}
