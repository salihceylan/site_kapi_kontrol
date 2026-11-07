import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/plate_command_center_item.dart';
import 'package:site_kapi_kontrol/models/plate_gates.dart';
import 'package:site_kapi_kontrol/services/plate_cameras_api.dart';
import 'package:site_kapi_kontrol/services/plate_recognition_api.dart';
import 'package:site_kapi_kontrol/services/plate_recognition_engine.dart';
import 'package:site_kapi_kontrol/ui/design/license_plate.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

String _fmtDateTime(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year} '
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}:${d.second.toString().padLeft(2, '0')}';

Color decisionAccentColor(PlateDecisionType decision) => switch (decision) {
  PlateDecisionType.acildi => const Color(0xFF10B981),
  PlateDecisionType.karaListe => const Color(0xFFEF4444),
  PlateDecisionType.red => const Color(0xFFF97316),
  PlateDecisionType.tanimsiz => const Color(0xFFF59E0B),
};

IconData decisionIconOf(PlateDecisionType decision) => switch (decision) {
  PlateDecisionType.acildi => Icons.check_circle_rounded,
  PlateDecisionType.karaListe => Icons.block_rounded,
  PlateDecisionType.red => Icons.do_not_disturb_on_rounded,
  PlateDecisionType.tanimsiz => Icons.help_outline_rounded,
};

/// Giriş Olayları veya Çıkış Olayları listesinden bir olaya tıklandığında açılan ayrıntı penceresi.
Future<void> showPlateEventDetailDialog(
  BuildContext context, {
  required PlateLiveStreamEvent event,
  required bool canWrite,
  void Function(String plate)? onGrantGuestPermit,
  void Function(String plate)? onAddToBlacklist,
  void Function(String plate, String direction)? onManualTrigger,
}) {
  final Uint8List? frameBytes = event.snapshotBytes ??
      (event.cameraId != null ? PlateRecognitionEngine.instance.lastFrames[event.cameraId!] : null);
  final accent = decisionAccentColor(event.decision);
  final isEntry = event.direction != 'cikis';

  return showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: const Color(0xFF0F172A),
      insetPadding: const EdgeInsets.all(AppSpace.md),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: accent.withValues(alpha: 0.55), width: 1.4),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // Başlık
            Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: 12),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.14),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
                border: Border(bottom: BorderSide(color: accent.withValues(alpha: 0.35))),
              ),
              child: Row(
                children: <Widget>[
                  Icon(decisionIconOf(event.decision), color: accent, size: 22),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: Text(
                      '${isEntry ? 'Giriş' : 'Çıkış'} Olayı Ayrıntısı • ${event.decisionLabel}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                    tooltip: 'Kapat',
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
            ),

            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpace.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    // Plaka + Yön Rozeti
                    Wrap(
                      spacing: AppSpace.sm,
                      runSpacing: AppSpace.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: <Widget>[
                        LicensePlateBadge(plate: event.plate, width: 168),
                        _PillBadge(
                          icon: isEntry ? Icons.login_rounded : Icons.logout_rounded,
                          label: isEntry ? 'Giriş Kamerası' : 'Çıkış Kamerası',
                          color: isEntry ? const Color(0xFF38BDF8) : const Color(0xFFA78BFA),
                        ),
                        _PillBadge(
                          icon: decisionIconOf(event.decision),
                          label: event.decisionLabel,
                          color: accent,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpace.md),

                    // Varsa olay anı karesi
                    if (frameBytes != null && frameBytes.isNotEmpty) ...<Widget>[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        child: AspectRatio(
                          aspectRatio: 16 / 9,
                          child: Image.memory(
                            frameBytes,
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpace.md),
                    ],

                    // Bilgi satırları
                    Container(
                      padding: const EdgeInsets.all(AppSpace.md),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Column(
                        children: <Widget>[
                          _DetailRow(label: 'Geçiş Zamanı', value: _fmtDateTime(event.timestamp)),
                          _DetailRow(label: 'Kapı / Geçiş Noktası', value: event.gateName),
                          if ((event.cameraName ?? '').trim().isNotEmpty)
                            _DetailRow(label: 'Kamera', value: event.cameraName!),
                          if (event.identitySummary != null)
                            _DetailRow(label: 'Aidiyet / Daire', value: event.identitySummary!, highlight: true),
                          _DetailRow(label: 'Karar Nedeni', value: event.reason),
                          if (event.confidence != null)
                            _DetailRow(
                              label: 'Yapay Zeka Okuma Güveni',
                              value: '%${(event.confidence! * 100).clamp(1, 100).round()}',
                            ),
                          _DetailRow(
                            label: 'Kapı Tetik Durumu',
                            value: event.isGateTriggered
                                ? 'Kapı açma komutu iletildi ✓'
                                : 'Kapı açılmadı (Geçiş engellendi)',
                          ),
                        ],
                      ),
                    ),

                    if (canWrite) ...<Widget>[
                      const SizedBox(height: AppSpace.md),
                      Wrap(
                        spacing: AppSpace.xs,
                        runSpacing: AppSpace.xs,
                        children: <Widget>[
                          if (onManualTrigger != null)
                            FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF10B981),
                                visualDensity: VisualDensity.compact,
                              ),
                              onPressed: () {
                                Navigator.of(ctx).pop();
                                onManualTrigger(event.plate, event.direction);
                              },
                              icon: const Icon(Icons.lock_open_rounded, size: 16),
                              label: const Text('Kapıyı Şimdi Tetikle'),
                            ),
                          if (onGrantGuestPermit != null)
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: const BorderSide(color: Colors.white24),
                                visualDensity: VisualDensity.compact,
                              ),
                              onPressed: () {
                                Navigator.of(ctx).pop();
                                onGrantGuestPermit(event.plate);
                              },
                              icon: const Icon(Icons.badge_outlined, size: 16),
                              label: const Text('Misafir İzni Tanımla'),
                            ),
                          if (onAddToBlacklist != null && event.decision != PlateDecisionType.karaListe)
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFFFCA5A5),
                                side: const BorderSide(color: Color(0xFFEF4444)),
                                visualDensity: VisualDensity.compact,
                              ),
                              onPressed: () {
                                Navigator.of(ctx).pop();
                                onAddToBlacklist(event.plate);
                              },
                              icon: const Icon(Icons.block_rounded, size: 16),
                              label: const Text('Kara Listeye Ekle'),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Giriş Olayları veya Çıkış Olayları kart başlığına tıklandığında tam listeyi ve filtreyi açar.
Future<void> showPlateEventsListDetailDialog(
  BuildContext context, {
  required String title,
  required List<PlateLiveStreamEvent> events,
  required bool canWrite,
  void Function(String plate)? onGrantGuestPermit,
  void Function(String plate)? onAddToBlacklist,
  void Function(String plate, String direction)? onManualTrigger,
}) {
  String query = '';
  return showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        final q = query.trim().toUpperCase();
        final filtered = q.isEmpty
            ? events
            : events.where((e) {
                return e.formattedPlate.toUpperCase().contains(q) ||
                    e.plate.toUpperCase().contains(q) ||
                    (e.identitySummary ?? '').toUpperCase().contains(q) ||
                    e.gateName.toUpperCase().contains(q);
              }).toList();

        return Dialog(
          backgroundColor: const Color(0xFF0F172A),
          insetPadding: const EdgeInsets.all(AppSpace.md),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            side: const BorderSide(color: Colors.white12),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720, maxHeight: 680),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: 12),
                  child: Row(
                    children: <Widget>[
                      const Icon(Icons.receipt_long_rounded, color: Color(0xFF38BDF8), size: 22),
                      const SizedBox(width: AppSpace.sm),
                      Expanded(
                        child: Text(
                          '$title (${events.length})',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.white70),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
                  child: TextField(
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Plaka, daire veya kapı ara...',
                      hintStyle: const TextStyle(color: Colors.white54),
                      prefixIcon: const Icon(Icons.search_rounded, color: Colors.white54),
                      filled: true,
                      fillColor: const Color(0xFF1E293B),
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        borderSide: const BorderSide(color: Colors.white12),
                      ),
                    ),
                    onChanged: (v) => setLocal(() => query = v),
                  ),
                ),
                const SizedBox(height: AppSpace.sm),
                Expanded(
                  child: filtered.isEmpty
                      ? const Center(
                          child: Text(
                            'Kayıt bulunamadı.',
                            style: TextStyle(color: Colors.white60),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(AppSpace.md),
                          itemCount: filtered.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (_, idx) {
                            final ev = filtered[idx];
                            final accent = decisionAccentColor(ev.decision);
                            return Material(
                              color: const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(AppRadius.md),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(AppRadius.md),
                                onTap: () => showPlateEventDetailDialog(
                                  ctx,
                                  event: ev,
                                  canWrite: canWrite,
                                  onGrantGuestPermit: onGrantGuestPermit,
                                  onAddToBlacklist: onAddToBlacklist,
                                  onManualTrigger: onManualTrigger,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(10),
                                  child: Row(
                                    children: <Widget>[
                                      LicensePlateBadge(plate: ev.plate),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: <Widget>[
                                            Text(
                                              ev.identitySummary ?? ev.reason,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w600,
                                                fontSize: 13,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            Text(
                                              '${ev.gateName} • ${_fmtDateTime(ev.timestamp)}',
                                              style: const TextStyle(
                                                color: Colors.white60,
                                                fontSize: 11.5,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      _PillBadge(
                                        icon: decisionIconOf(ev.decision),
                                        label: ev.decisionLabel,
                                        color: accent,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

/// Sol alttaki "Canlı Otopark Durum Bilgisi" kartına tıklandığında açılan ayrıntılı otopark penceresi.
Future<void> showLiveParkingDetailDialog(
  BuildContext context, {
  required PlateInside inside,
  required bool canWrite,
  required Future<void> Function(int insideId) onClearInsideItem,
}) {
  int subTab = 0;
  String searchQuery = '';

  return showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        final q = searchQuery.trim().toUpperCase();
        final guestCount = inside.items.where((i) => i.kind == 'guest').length;
        final residentCount = inside.items.where((i) => i.kind == 'resident').length;
        final totalSlots = inside.apartments.fold<int>(0, (s, a) => s + a.parkingSlots);

        final vehicles = q.isEmpty
            ? inside.items
            : inside.items.where((i) {
                return formatTrPlate(i.plate).toUpperCase().contains(q) ||
                    i.plate.toUpperCase().contains(q) ||
                    (i.apartmentLabel ?? '').toUpperCase().contains(q) ||
                    (i.gateName ?? '').toUpperCase().contains(q);
              }).toList();

        final apartments = q.isEmpty
            ? inside.apartments
            : inside.apartments.where((a) => a.label.toUpperCase().contains(q)).toList();

        return Dialog(
          backgroundColor: const Color(0xFF0F172A),
          insetPadding: const EdgeInsets.all(AppSpace.md),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            side: const BorderSide(color: Color(0xFF10B981), width: 1.2),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760, maxHeight: 700),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.14),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
                  ),
                  child: Row(
                    children: <Widget>[
                      const Icon(Icons.local_parking_rounded, color: Color(0xFF10B981), size: 24),
                      const SizedBox(width: AppSpace.sm),
                      const Expanded(
                        child: Text(
                          'Canlı Otopark Durum Bilgisi • Ayrıntılar',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.white70),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.all(AppSpace.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Wrap(
                        spacing: AppSpace.sm,
                        runSpacing: AppSpace.xs,
                        children: <Widget>[
                          _MetricChip(label: 'İçerideki Toplam', value: '${inside.total} Araç', color: const Color(0xFF10B981)),
                          _MetricChip(label: 'Sakin Aracı', value: '$residentCount', color: const Color(0xFF38BDF8)),
                          _MetricChip(label: 'Misafir Aracı', value: '$guestCount', color: const Color(0xFFF59E0B)),
                          if (totalSlots > 0)
                            _MetricChip(label: 'Tanımlı Kontenjan', value: '${inside.total} / $totalSlots', color: const Color(0xFFA78BFA)),
                          if (inside.overdue.isNotEmpty)
                            _MetricChip(
                              label: '${inside.overdueAfterHours}+ Saat İçeride',
                              value: '${inside.overdue.length}',
                              color: const Color(0xFFEF4444),
                            ),
                        ],
                      ),
                      const SizedBox(height: AppSpace.sm),
                      Wrap(
                        spacing: AppSpace.xs,
                        runSpacing: AppSpace.xs,
                        children: <Widget>[
                          ChoiceChip(
                            label: Text('İçerideki Araçlar (${inside.items.length})'),
                            selected: subTab == 0,
                            onSelected: (_) => setLocal(() => subTab = 0),
                          ),
                          ChoiceChip(
                            label: Text('Daire Otopark Kontenjanları (${inside.apartments.length})'),
                            selected: subTab == 1,
                            onSelected: (_) => setLocal(() => subTab = 1),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpace.sm),
                      TextField(
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: subTab == 0 ? 'Plaka veya daire ara...' : 'Daire ara...',
                          hintStyle: const TextStyle(color: Colors.white54),
                          prefixIcon: const Icon(Icons.search_rounded, color: Colors.white54),
                          filled: true,
                          fillColor: const Color(0xFF1E293B),
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            borderSide: const BorderSide(color: Colors.white12),
                          ),
                        ),
                        onChanged: (v) => setLocal(() => searchQuery = v),
                      ),
                    ],
                  ),
                ),

                Expanded(
                  child: subTab == 0
                      ? (vehicles.isEmpty
                          ? const Center(
                              child: Text(
                                'Şu anda otoparkta kayıtlı araç görünmüyor.',
                                style: TextStyle(color: Colors.white60),
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.md),
                              itemCount: vehicles.length,
                              separatorBuilder: (_, _) => const SizedBox(height: 8),
                              itemBuilder: (_, idx) {
                                final item = vehicles[idx];
                                return Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1E293B),
                                    borderRadius: BorderRadius.circular(AppRadius.md),
                                    border: Border.all(color: Colors.white12),
                                  ),
                                  child: Row(
                                    children: <Widget>[
                                      LicensePlateBadge(plate: item.plate),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: <Widget>[
                                            Text(
                                              '${item.kindLabel}${(item.apartmentLabel ?? '').isNotEmpty ? ' • ${item.apartmentLabel}' : ''}',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w700,
                                                fontSize: 13,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            Text(
                                              <String>[
                                                if ((item.gateName ?? '').isNotEmpty) item.gateName!,
                                                if (item.sinceAt != null) 'Giriş: ${_fmtDateTime(item.sinceAt!)}',
                                                if (item.insideHours != null && item.insideHours! > 0) '${item.insideHours} saattir içeride',
                                              ].join(' • '),
                                              style: const TextStyle(color: Colors.white60, fontSize: 11.5),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (canWrite && item.id > 0)
                                        TextButton.icon(
                                          onPressed: () async {
                                            await onClearInsideItem(item.id);
                                            if (ctx.mounted) Navigator.of(ctx).pop();
                                          },
                                          icon: const Icon(Icons.logout_rounded, size: 16, color: Color(0xFFFCA5A5)),
                                          label: const Text(
                                            'Çıkış Düş',
                                            style: TextStyle(color: Color(0xFFFCA5A5), fontSize: 12),
                                          ),
                                        ),
                                    ],
                                  ),
                                );
                              },
                            ))
                      : (apartments.isEmpty
                          ? const Center(
                              child: Text(
                                'Daire otopark kaydı bulunamadı.',
                                style: TextStyle(color: Colors.white60),
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.md),
                              itemCount: apartments.length,
                              separatorBuilder: (_, _) => const SizedBox(height: 8),
                              itemBuilder: (_, idx) {
                                final apt = apartments[idx];
                                final okColor = apt.guestAllowed ? const Color(0xFF10B981) : const Color(0xFFF97316);
                                return Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1E293B),
                                    borderRadius: BorderRadius.circular(AppRadius.md),
                                    border: Border.all(color: Colors.white12),
                                  ),
                                  child: Row(
                                    children: <Widget>[
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: <Widget>[
                                            Text(
                                              apt.label,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13.5,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            Text(
                                              'İçeride: ${apt.insideCount} / Park Hakkı: ${apt.parkingSlots}',
                                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                      ),
                                      _PillBadge(
                                        icon: apt.guestAllowed ? Icons.check_circle_outline_rounded : Icons.info_outline_rounded,
                                        label: apt.guestLabel,
                                        color: okColor,
                                      ),
                                    ],
                                  ),
                                );
                              },
                            )),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

/// Sol üstteki "Menüler & Diğer Bilgiler" kartında sistem / kapı durumuna tıklandığında açılan detay penceresi.
Future<void> showSystemAndGateDetailDialog(
  BuildContext context, {
  required PlateSite site,
  required PlateGate? selectedGate,
  required GateCameraWallSlots slots,
  required bool engineRunning,
  VoidCallback? onEditGateTimings,
  VoidCallback? onCreateGate,
  void Function(PlateCameraRow camera)? onEditCamera,
}) {
  final allSlotCams = <(String label, PlateCameraRow? cam)>[
    ('Giriş Kamerası 1', slots.entry1),
    ('Giriş Kamerası 2', slots.entry2),
    ('Çıkış Kamerası 1', slots.exit1),
    ('Çıkış Kamerası 2', slots.exit2),
  ];

  return showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: const Color(0xFF0F172A),
      insetPadding: const EdgeInsets.all(AppSpace.md),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: const BorderSide(color: Color(0xFF38BDF8), width: 1.2),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 680),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF38BDF8).withValues(alpha: 0.14),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
              ),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.memory_rounded, color: Color(0xFF38BDF8), size: 22),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: Text(
                      'Sistem & Kapı Durum Ayrıntıları • ${site.label}',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpace.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Container(
                      padding: const EdgeInsets.all(AppSpace.md),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Column(
                        children: <Widget>[
                          _DetailRow(
                            label: 'Yapay Zeka & Video Motoru',
                            value: engineRunning
                                ? 'Aktif • 4 Kanal Paralel ONNX + Direct3D11 GPU (30-60 FPS)'
                                : 'Hazır / İzleme Modu',
                            highlight: true,
                          ),
                          _DetailRow(
                            label: 'Seçili Kapı',
                            value: selectedGate != null
                                ? '${selectedGate.name} (${selectedGate.directionLabel})'
                                : 'Henüz kapı tanımlanmadı',
                          ),
                          if (selectedGate != null) ...<Widget>[
                            _DetailRow(
                              label: 'Ardışık Araç Bekleme Süresi',
                              value: '${selectedGate.consecutiveVehicleDelaySeconds} saniye',
                            ),
                            _DetailRow(
                              label: 'Arka Plaka Engelleme (Giriş / Çıkış)',
                              value: '${selectedGate.entryRearSuppressSeconds} sn / ${selectedGate.exitRearSuppressSeconds} sn',
                            ),
                          ],
                          _DetailRow(
                            label: 'Aktif Kamera Yuvaları',
                            value: '${slots.activeCount} / 4 Kamera Canlı (${slots.entryCount} Giriş, ${slots.exitCount} Çıkış)',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpace.md),
                    const Text(
                      '4 Kamera Yuvası Durumu',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: AppSpace.xs),
                    for (final (slotLabel, cam) in allSlotCams)
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Row(
                          children: <Widget>[
                            Icon(
                              cam != null ? Icons.videocam_rounded : Icons.videocam_off_outlined,
                              color: cam != null ? const Color(0xFF10B981) : Colors.white38,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    '$slotLabel: ${cam != null ? cam.name : 'Boş Yuva (Yer Tutucu)'}',
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    cam != null
                                        ? 'IP: ${cam.host.isNotEmpty ? cam.host : (cam.rtspUrl ?? '-')}'
                                        : 'Canlı ekrandan "+ Kamera Ekle" ile bağlanabilir',
                                    style: const TextStyle(color: Colors.white60, fontSize: 11.5),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            if (cam != null && site.canWrite && onEditCamera != null)
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                tooltip: 'Kamerayı Düzenle',
                                icon: const Icon(Icons.edit_outlined, color: Colors.white70, size: 18),
                                onPressed: () {
                                  Navigator.of(ctx).pop();
                                  onEditCamera(cam);
                                },
                              ),
                          ],
                        ),
                      ),
                    if (site.canWrite) ...<Widget>[
                      const SizedBox(height: AppSpace.sm),
                      Wrap(
                        spacing: AppSpace.xs,
                        runSpacing: AppSpace.xs,
                        children: <Widget>[
                          if (selectedGate != null && onEditGateTimings != null)
                            FilledButton.icon(
                              onPressed: () {
                                Navigator.of(ctx).pop();
                                onEditGateTimings();
                              },
                              icon: const Icon(Icons.timer_outlined, size: 16),
                              label: const Text('Kapı Geçiş Sürelerini Düzenle'),
                            ),
                          if (onCreateGate != null)
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: const BorderSide(color: Colors.white24),
                              ),
                              onPressed: () {
                                Navigator.of(ctx).pop();
                                onCreateGate();
                              },
                              icon: const Icon(Icons.add_rounded, size: 16),
                              label: const Text('Yeni Kapı Ekle'),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 165,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white60, fontSize: 12.5),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: highlight ? const Color(0xFF34D399) : Colors.white,
                fontWeight: highlight ? FontWeight.bold : FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PillBadge extends StatelessWidget {
  const _PillBadge({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.65)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(label, style: const TextStyle(color: Colors.white60, fontSize: 11)),
          Text(
            value,
            style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
