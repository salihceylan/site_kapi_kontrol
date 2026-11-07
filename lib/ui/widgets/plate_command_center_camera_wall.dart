import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/plate_command_center_item.dart';
import 'package:site_kapi_kontrol/services/plate_cameras_api.dart';
import 'package:site_kapi_kontrol/ui/widgets/plate_camera_live_view.dart';

/// Tam ekran Canlı Akış penceresinin merkezindeki devasa 4 kameralı duvar:
/// - Üst yarı: **Giriş Kameraları** (Giriş 1 & Giriş 2)
/// - Alt yarı: **Çıkış Kameraları** (Çıkış 1 & Çıkış 2)
/// Kamera tanımlı değilse aynı boyutta yuvarlatılmış yer tutucu çerçeve ve ekleme düğmeleri gösterilir.
class CommandCenterCameraWall extends StatelessWidget {
  const CommandCenterCameraWall({
    super.key,
    required this.siteCode,
    required this.canWrite,
    required this.slots,
    required this.camerasService,
    required this.onAddCamera,
    required this.onDiscoverCamera,
    required this.onAttachExistingCamera,
    required this.onEditCamera,
    this.expandedHeight = true,
  });

  final int siteCode;
  final bool canWrite;
  final GateCameraWallSlots slots;
  final PlateCamerasService camerasService;
  final void Function(String direction, int slotNumber, String suggestedName) onAddCamera;
  final void Function(String direction, int slotNumber, String suggestedName) onDiscoverCamera;
  final void Function(PlateCameraRow camera, String direction) onAttachExistingCamera;
  final void Function(PlateCameraRow camera) onEditCamera;

  /// Masaüstü tam ekranda `true` (tüm yüksekliği iki eşit yarıya böler); dar ekranda `false` (16:9).
  final bool expandedHeight;

  @override
  Widget build(BuildContext context) {
    final gateTitle = slots.gate?.name ?? 'Ana Kapı';

    Widget buildSection({
      required String sectionKey,
      required String title,
      required String direction,
      required Color accentColor,
      required PlateCameraRow? cam1,
      required PlateCameraRow? cam2,
    }) {
      final activeInSection = (cam1 != null && cam1.isActive ? 1 : 0) + (cam2 != null && cam2.isActive ? 1 : 0);
      final slot1Name = '$gateTitle - ${direction == 'giris' ? 'Giriş' : 'Çıkış'} 1';
      final slot2Name = '$gateTitle - ${direction == 'giris' ? 'Giriş' : 'Çıkış'} 2';
      final slot1Title = '${direction == 'giris' ? 'Giriş' : 'Çıkış'} Kamerası 1';
      final slot2Title = '${direction == 'giris' ? 'Giriş' : 'Çıkış'} Kamerası 2';

      Widget buildPairRow(bool stackVertically) {
        final firstSlot = cam1 != null
            ? _ActiveCameraSlot(
                key: ValueKey<String>('cc_active_${direction}_1_${cam1.id}'),
                slotBadge: slot1Title,
                camera: cam1,
                siteCode: siteCode,
                canWrite: canWrite,
                accentColor: accentColor,
                camerasService: camerasService,
                onEdit: () => onEditCamera(cam1),
              )
            : _PlaceholderCameraSlot(
                key: ValueKey<String>('cc_placeholder_${direction}_1'),
                slotTitle: slot1Title,
                gateName: gateTitle,
                canWrite: canWrite,
                accentColor: accentColor,
                unassignedCameras: slots.unassignedCameras,
                onAdd: () => onAddCamera(direction, 1, slot1Name),
                onDiscover: () => onDiscoverCamera(direction, 1, slot1Name),
                onAttachExisting: (c) => onAttachExistingCamera(c, direction),
              );

        final secondSlot = cam2 != null
            ? _ActiveCameraSlot(
                key: ValueKey<String>('cc_active_${direction}_2_${cam2.id}'),
                slotBadge: slot2Title,
                camera: cam2,
                siteCode: siteCode,
                canWrite: canWrite,
                accentColor: accentColor,
                camerasService: camerasService,
                onEdit: () => onEditCamera(cam2),
              )
            : _PlaceholderCameraSlot(
                key: ValueKey<String>('cc_placeholder_${direction}_2'),
                slotTitle: slot2Title,
                gateName: gateTitle,
                canWrite: canWrite,
                accentColor: accentColor,
                unassignedCameras: slots.unassignedCameras,
                onAdd: () => onAddCamera(direction, 2, slot2Name),
                onDiscover: () => onDiscoverCamera(direction, 2, slot2Name),
                onAttachExisting: (c) => onAttachExistingCamera(c, direction),
              );

        if (expandedHeight) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(child: firstSlot),
              const SizedBox(width: 8),
              Expanded(child: secondSlot),
            ],
          );
        }

        if (stackVertically) {
          return Column(
            children: <Widget>[
              AspectRatio(aspectRatio: 16 / 9, child: firstSlot),
              const SizedBox(height: 8),
              AspectRatio(aspectRatio: 16 / 9, child: secondSlot),
            ],
          );
        }

        return Row(
          children: <Widget>[
            Expanded(child: AspectRatio(aspectRatio: 16 / 9, child: firstSlot)),
            const SizedBox(width: 8),
            Expanded(child: AspectRatio(aspectRatio: 16 / 9, child: secondSlot)),
          ],
        );
      }

      return Column(
        key: ValueKey<String>(sectionKey),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: expandedHeight ? MainAxisSize.max : MainAxisSize.min,
        children: <Widget>[
          // Bölüm başlığı + çizgi (wireframe ile birebir uyumlu)
          Row(
            children: <Widget>[
              Icon(
                direction == 'giris' ? Icons.login_rounded : Icons.logout_rounded,
                size: 16,
                color: accentColor,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                    letterSpacing: 0.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: accentColor.withValues(alpha: 0.5)),
                  ),
                  child: Text(
                    '$gateTitle • $activeInSection/2 Aktif',
                    style: TextStyle(
                      color: accentColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Container(
            height: 2,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: <Color>[
                  accentColor.withValues(alpha: 0.9),
                  Colors.white24,
                  Colors.white10,
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          if (expandedHeight)
            Expanded(child: buildPairRow(false))
          else
            LayoutBuilder(
              builder: (context, c) => buildPairRow(c.maxWidth < 560),
            ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1120),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1E293B), width: 1.2),
      ),
      child: expandedHeight
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(
                  child: buildSection(
                    sectionKey: 'cc_entry_section',
                    title: 'Giriş Kameraları',
                    direction: 'giris',
                    accentColor: const Color(0xFF10B981),
                    cam1: slots.entry1,
                    cam2: slots.entry2,
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: buildSection(
                    sectionKey: 'cc_exit_section',
                    title: 'Çıkış Kameraları',
                    direction: 'cikis',
                    accentColor: const Color(0xFF38BDF8),
                    cam1: slots.exit1,
                    cam2: slots.exit2,
                  ),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                buildSection(
                  sectionKey: 'cc_entry_section',
                  title: 'Giriş Kameraları',
                  direction: 'giris',
                  accentColor: const Color(0xFF10B981),
                  cam1: slots.entry1,
                  cam2: slots.entry2,
                ),
                const SizedBox(height: 12),
                buildSection(
                  sectionKey: 'cc_exit_section',
                  title: 'Çıkış Kameraları',
                  direction: 'cikis',
                  accentColor: const Color(0xFF38BDF8),
                  cam1: slots.exit1,
                  cam2: slots.exit2,
                ),
              ],
            ),
    );
  }
}

class _ActiveCameraSlot extends StatelessWidget {
  const _ActiveCameraSlot({
    super.key,
    required this.slotBadge,
    required this.camera,
    required this.siteCode,
    required this.canWrite,
    required this.accentColor,
    required this.camerasService,
    required this.onEdit,
  });

  final String slotBadge;
  final PlateCameraRow camera;
  final int siteCode;
  final bool canWrite;
  final Color accentColor;
  final PlateCamerasService camerasService;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(20);
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: radius,
        border: Border.all(color: accentColor.withValues(alpha: 0.65), width: 1.6),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18.5),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            PlateCameraLivePreview(
              cameraId: camera.id,
              name: camera.name,
              camera: camera,
              host: camera.host,
              port: camera.port,
              rtspUrl: camera.rtspUrl,
              isActive: camera.isActive,
              siteCode: siteCode,
              camerasService: camerasService,
              showControls: true,
              preferSubStream: true,
              pollInterval: const Duration(milliseconds: 280),
            ),

            // Sol üst bilgi etiketi: CANLI + Yuva + Kamera Adı
            Positioned(
              top: 8,
              left: 8,
              right: canWrite ? 78 : 44,
              child: Align(
                alignment: Alignment.topLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF090D16).withValues(alpha: 0.78),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: accentColor.withValues(alpha: 0.6)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: camera.isActive ? const Color(0xFF10B981) : Colors.grey,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          '$slotBadge • ${camera.name}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Sağ üst düzenleme ikonu (PlateCameraLivePreview büyütme ikonunun hemen solunda)
            if (canWrite)
              Positioned(
                top: 8,
                right: 42,
                child: Material(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: onEdit,
                    child: const Tooltip(
                      message: 'Kamera Ayarlarını Düzenle',
                      child: Padding(
                        padding: EdgeInsets.all(6),
                        child: Icon(Icons.tune_rounded, size: 18, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PlaceholderCameraSlot extends StatelessWidget {
  const _PlaceholderCameraSlot({
    super.key,
    required this.slotTitle,
    required this.gateName,
    required this.canWrite,
    required this.accentColor,
    required this.unassignedCameras,
    required this.onAdd,
    required this.onDiscover,
    required this.onAttachExisting,
  });

  final String slotTitle;
  final String gateName;
  final bool canWrite;
  final Color accentColor;
  final List<PlateCameraRow> unassignedCameras;
  final VoidCallback onAdd;
  final VoidCallback onDiscover;
  final void Function(PlateCameraRow camera) onAttachExisting;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFF0F172A), Color(0xFF131F35)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: accentColor.withValues(alpha: 0.35),
          width: 1.5,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          // Köşe vizör çizgileri ("kamera varmış gibi" monitör hissi)
          const Positioned(top: 12, left: 12, child: _ViewfinderCorner(top: true, left: true)),
          const Positioned(top: 12, right: 12, child: _ViewfinderCorner(top: true, left: false)),
          const Positioned(bottom: 12, left: 12, child: _ViewfinderCorner(top: false, left: true)),
          const Positioned(bottom: 12, right: 12, child: _ViewfinderCorner(top: false, left: false)),

          // Sol üst yuva etiketi
          Positioned(
            top: 10,
            left: 14,
            right: 14,
            child: Align(
              alignment: Alignment.topLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.white12),
                ),
                child: Text(
                  '$gateName • $slotTitle',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),

          // Orta içerik (taşma korumalı esnek yerleşim)
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                      border: Border.all(color: accentColor.withValues(alpha: 0.4)),
                    ),
                    child: Icon(Icons.add_a_photo_outlined, size: 28, color: accentColor),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    slotTitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14.5,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    canWrite
                        ? 'Kamera bağlı değil • Eklediğiniz anda canlı akış ve AI plaka okuma başlar'
                        : 'Bu yuvaya henüz kamera tanımlanmamış',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white60, fontSize: 11.5),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (canWrite) ...<Widget>[
                    const SizedBox(height: 12),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 6,
                      children: <Widget>[
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: accentColor,
                            foregroundColor: const Color(0xFF06131F),
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          onPressed: onAdd,
                          icon: const Icon(Icons.add_rounded, size: 17),
                          label: const Text(
                            'Kamera Ekle',
                            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                          ),
                        ),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: BorderSide(color: accentColor.withValues(alpha: 0.55)),
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          ),
                          onPressed: onDiscover,
                          icon: const Icon(Icons.wifi_find_rounded, size: 16),
                          label: const Text(
                            'Ağda Ara',
                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                          ),
                        ),
                        if (unassignedCameras.isNotEmpty)
                          PopupMenuButton<PlateCameraRow>(
                            tooltip: 'Kayıtlı Atanmamış Kamerayı Bağla',
                            color: const Color(0xFF1E293B),
                            onSelected: onAttachExisting,
                            itemBuilder: (_) => <PopupMenuEntry<PlateCameraRow>>[
                              for (final c in unassignedCameras)
                                PopupMenuItem<PlateCameraRow>(
                                  value: c,
                                  child: Text(
                                    '${c.name} (${c.host.isNotEmpty ? c.host : 'RTSP'})',
                                    style: const TextStyle(color: Colors.white, fontSize: 12.5),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: Colors.white24),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  const Icon(Icons.link_rounded, size: 15, color: Colors.white),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      'Mevcut Kamerayı Ata (${unassignedCameras.length})',
                                      style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
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
    );
  }
}

class _ViewfinderCorner extends StatelessWidget {
  const _ViewfinderCorner({required this.top, required this.left});

  final bool top;
  final bool left;

  @override
  Widget build(BuildContext context) {
    const borderSide = BorderSide(color: Colors.white24, width: 1.8);
    return IgnorePointer(
      child: Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          border: Border(
            top: top ? borderSide : BorderSide.none,
            bottom: !top ? borderSide : BorderSide.none,
            left: left ? borderSide : BorderSide.none,
            right: !left ? borderSide : BorderSide.none,
          ),
        ),
      ),
    );
  }
}
