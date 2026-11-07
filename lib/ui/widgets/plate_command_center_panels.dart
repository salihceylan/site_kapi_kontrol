import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/plate_command_center_item.dart';
import 'package:site_kapi_kontrol/models/plate_gates.dart';
import 'package:site_kapi_kontrol/services/plate_recognition_api.dart';
import 'package:site_kapi_kontrol/ui/dialogs/plate_command_center_detail_dialogs.dart';

String _fmtTime(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}:${d.second.toString().padLeft(2, '0')}';

/// Sol üst kart: **Menüler & Diğer Bilgiler**
class CommandCenterMenuCard extends StatelessWidget {
  const CommandCenterMenuCard({
    super.key,
    required this.site,
    required this.sites,
    required this.gates,
    required this.selectedGate,
    required this.slots,
    required this.engineRunning,
    required this.isWindowFullscreen,
    required this.onSelectSite,
    required this.onSelectGate,
    required this.onClose,
    required this.onToggleFullscreen,
    required this.onRefresh,
    required this.onOpenSystemDetail,
    required this.onSimulateOrManualOpen,
    required this.onAddCamera,
    required this.onDiscoverCameras,
    required this.onGrantGuestPermit,
    required this.onAddBlacklist,
    required this.onEditGateTimings,
    required this.onCreateGate,
    this.expandedHeight = true,
  });

  final PlateSite site;
  final List<PlateSite> sites;
  final List<PlateGate> gates;
  final PlateGate? selectedGate;
  final GateCameraWallSlots slots;
  final bool engineRunning;
  final bool isWindowFullscreen;
  final void Function(PlateSite site) onSelectSite;
  final void Function(PlateGate gate) onSelectGate;
  final VoidCallback onClose;
  final VoidCallback onToggleFullscreen;
  final VoidCallback onRefresh;
  final VoidCallback onOpenSystemDetail;
  final VoidCallback onSimulateOrManualOpen;
  final VoidCallback onAddCamera;
  final VoidCallback onDiscoverCameras;
  final VoidCallback onGrantGuestPermit;
  final VoidCallback onAddBlacklist;
  final VoidCallback onEditGateTimings;
  final VoidCallback onCreateGate;
  final bool expandedHeight;

  @override
  Widget build(BuildContext context) {
    final bodyContent = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // Site seçici (birden çok site varsa)
        if (sites.length > 1) ...<Widget>[
          _CompactDropdownContainer(
            label: 'Site',
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: site.code,
                isExpanded: true,
                isDense: true,
                dropdownColor: const Color(0xFF1E293B),
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                items: <DropdownMenuItem<int>>[
                  for (final s in sites)
                    DropdownMenuItem<int>(
                      value: s.code,
                      child: Text(s.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (code) {
                  if (code == null) return;
                  final found = sites.where((s) => s.code == code).firstOrNull;
                  if (found != null) onSelectSite(found);
                },
              ),
            ),
          ),
          const SizedBox(height: 6),
        ],

        // Kapı seçici (her kapının 2 giriş + 2 çıkış = 4 kamerası arasında anında geçiş)
        if (gates.isNotEmpty) ...<Widget>[
          _CompactDropdownContainer(
            label: 'Geçiş Kapısı (${gates.length})',
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: selectedGate?.id ?? gates.first.id,
                isExpanded: true,
                isDense: true,
                dropdownColor: const Color(0xFF1E293B),
                style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700),
                items: <DropdownMenuItem<int>>[
                  for (final g in gates)
                    DropdownMenuItem<int>(
                      value: g.id,
                      child: Text(
                        '${g.name} (${g.cameras.length}/4)',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (id) {
                  if (id == null) return;
                  final found = gates.where((g) => g.id == id).firstOrNull;
                  if (found != null) onSelectGate(found);
                },
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],

        // Tıklanabilir canlı sistem & AI motor durum kutusu
        Material(
          color: const Color(0xFF162238),
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            key: const ValueKey<String>('cc_system_detail_trigger'),
            borderRadius: BorderRadius.circular(10),
            onTap: onOpenSystemDetail,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: engineRunning
                      ? const Color(0xFF10B981).withValues(alpha: 0.45)
                      : Colors.white12,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: engineRunning ? const Color(0xFF10B981) : const Color(0xFF38BDF8),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          engineRunning ? '4 Kanal Paralel AI Aktif' : 'Canlı İzleme Aktif',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 11.5,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Icon(Icons.open_in_new_rounded, size: 13, color: Colors.white54),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Kamera: ${slots.activeCount}/4 Canlı • 30-60 FPS GPU',
                    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),

        // Hızlı Operatör Menü Butonları
        _MenuActionTile(
          icon: Icons.lock_open_rounded,
          color: const Color(0xFF10B981),
          label: 'Kapı Tetikle / Plaka Test',
          onTap: onSimulateOrManualOpen,
        ),
        if (site.canWrite) ...<Widget>[
          _MenuActionTile(
            icon: Icons.add_a_photo_outlined,
            color: const Color(0xFF38BDF8),
            label: 'Kamera Ekle',
            onTap: onAddCamera,
          ),
          _MenuActionTile(
            icon: Icons.wifi_find_rounded,
            color: const Color(0xFF60A5FA),
            label: 'Ağda Kamera Ara',
            onTap: onDiscoverCameras,
          ),
          _MenuActionTile(
            icon: Icons.badge_outlined,
            color: const Color(0xFFF59E0B),
            label: 'Misafir Plaka İzni Ver',
            onTap: onGrantGuestPermit,
          ),
          _MenuActionTile(
            icon: Icons.block_rounded,
            color: const Color(0xFFEF4444),
            label: 'Kara Listeye Plaka Ekle',
            onTap: onAddBlacklist,
          ),
          if (selectedGate != null)
            _MenuActionTile(
              icon: Icons.timer_outlined,
              color: const Color(0xFFA78BFA),
              label: 'Kapı Geçiş Süre Ayarları',
              onTap: onEditGateTimings,
            ),
          _MenuActionTile(
            icon: Icons.door_sliding_outlined,
            color: const Color(0xFF34D399),
            label: 'Yeni Geçiş Kapısı Ekle',
            onTap: onCreateGate,
          ),
        ],
      ],
    );

    return Container(
      key: const ValueKey<String>('cc_menu_card'),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1E293B), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: expandedHeight ? MainAxisSize.max : MainAxisSize.min,
        children: <Widget>[
          // Üst başlık çubuğu
          Row(
            children: <Widget>[
              const Icon(Icons.dashboard_customize_rounded, size: 16, color: Color(0xFF38BDF8)),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'Menüler & Diğer Bilgiler',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _MiniIconBtn(
                tooltip: 'Yenile',
                icon: Icons.refresh_rounded,
                onTap: onRefresh,
              ),
              const SizedBox(width: 4),
              _MiniIconBtn(
                tooltip: isWindowFullscreen ? 'Pencere Modu (F11)' : 'Tam Ekran (F11)',
                icon: isWindowFullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                onTap: onToggleFullscreen,
              ),
              const SizedBox(width: 4),
              _MiniIconBtn(
                key: const ValueKey<String>('cc_close_btn'),
                tooltip: 'Tam Ekrandan Çık (ESC)',
                icon: Icons.close_rounded,
                danger: true,
                onTap: onClose,
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Divider(height: 1, color: Colors.white12),
          const SizedBox(height: 8),
          if (expandedHeight)
            Expanded(
              child: SingleChildScrollView(child: bodyContent),
            )
          else
            bodyContent,
        ],
      ),
    );
  }
}

/// Sol alt kart: **Canlı Otopark Durum Bilgisi**
/// Karta veya listedeki bir araca tıklandığında tam otopark detay penceresi açılır.
class CommandCenterParkingCard extends StatelessWidget {
  const CommandCenterParkingCard({
    super.key,
    required this.inside,
    required this.onOpenDetail,
    this.expandedHeight = true,
  });

  final PlateInside? inside;
  final VoidCallback onOpenDetail;
  final bool expandedHeight;

  @override
  Widget build(BuildContext context) {
    final data = inside;
    final totalInside = data?.total ?? 0;
    final items = data?.items ?? const <InsideItem>[];
    final guestCount = items.where((i) => i.kind == 'guest').length;
    final residentCount = items.where((i) => i.kind == 'resident').length;
    final totalSlots = data == null
        ? 0
        : data.apartments.fold<int>(0, (sum, a) => sum + a.parkingSlots);
    final occupancyRatio = totalSlots > 0 ? (totalInside / totalSlots).clamp(0.0, 1.0) : 0.0;
    final overdueCount = data?.overdue.length ?? 0;

    Widget vehicleRow(InsideItem item) {
      final isGuest = item.kind == 'guest';
      final tagColor = isGuest ? const Color(0xFFF59E0B) : const Color(0xFF10B981);
      return Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Material(
          color: const Color(0xFF162238),
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onOpenDetail,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0B1120),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: tagColor.withValues(alpha: 0.65)),
                    ),
                    child: Text(
                      formatTrPlate(item.plate),
                      style: const TextStyle(
                        color: Colors.white,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      (item.apartmentLabel ?? '').isNotEmpty
                          ? item.apartmentLabel!
                          : item.kindLabel,
                      style: const TextStyle(color: Colors.white70, fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    item.kindLabel,
                    style: TextStyle(
                      color: tagColor,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      key: const ValueKey<String>('cc_parking_card'),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1E293B), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: expandedHeight ? MainAxisSize.max : MainAxisSize.min,
        children: <Widget>[
          // Tıklanabilir başlık + özet
          InkWell(
            key: const ValueKey<String>('cc_parking_detail_trigger'),
            borderRadius: BorderRadius.circular(8),
            onTap: onOpenDetail,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Icon(Icons.local_parking_rounded, size: 17, color: Color(0xFF10B981)),
                    const SizedBox(width: 6),
                    const Expanded(
                      child: Text(
                        'Canlı Otopark Durum Bilgisi',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 12.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(Icons.open_in_new_rounded, size: 14, color: Colors.white54),
                  ],
                ),
                const SizedBox(height: 6),
                const Divider(height: 1, color: Colors.white12),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF162238),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.35)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              'İçeride: $totalInside Araç',
                              style: const TextStyle(
                                color: Color(0xFF34D399),
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (totalSlots > 0)
                            Text(
                              '$totalInside/$totalSlots',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                        ],
                      ),
                      if (totalSlots > 0) ...<Widget>[
                        const SizedBox(height: 5),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: occupancyRatio,
                            minHeight: 5,
                            backgroundColor: Colors.white12,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              occupancyRatio >= 0.9
                                  ? const Color(0xFFEF4444)
                                  : const Color(0xFF10B981),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: <Widget>[
                          Text(
                            'Sakin: $residentCount',
                            style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.w700),
                          ),
                          Text(
                            'Misafir: $guestCount',
                            style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 11, fontWeight: FontWeight.w700),
                          ),
                          if (overdueCount > 0)
                            Text(
                              'Uzun Süreli: $overdueCount',
                              style: const TextStyle(color: Color(0xFFF87171), fontSize: 11, fontWeight: FontWeight.w700),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (expandedHeight)
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: InkWell(
                        onTap: onOpenDetail,
                        child: const Text(
                          'Şu anda içeride araç yok.\nAyrıntılar için tıklayın.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white54, fontSize: 11.5),
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (_, idx) => vehicleRow(items[idx]),
                    ),
            )
          else if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Şu anda içeride araç yok.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, fontSize: 11.5),
              ),
            )
          else
            Column(
              children: <Widget>[
                for (final item in items.take(5)) vehicleRow(item),
              ],
            ),
        ],
      ),
    );
  }
}

/// Sağ üst (**Giriş Olayları**) ve sağ alt (**Çıkış Olayları**) gerçek zamanlı akış kartları.
class CommandCenterEventsCard extends StatelessWidget {
  const CommandCenterEventsCard({
    super.key,
    required this.cardKey,
    required this.title,
    required this.emptyText,
    required this.accentColor,
    required this.icon,
    required this.events,
    required this.onTapEvent,
    required this.onTapHeader,
    this.expandedHeight = true,
  });

  final String cardKey;
  final String title;
  final String emptyText;
  final Color accentColor;
  final IconData icon;
  final List<PlateLiveStreamEvent> events;
  final void Function(PlateLiveStreamEvent event) onTapEvent;
  final VoidCallback onTapHeader;
  final bool expandedHeight;

  @override
  Widget build(BuildContext context) {
    Widget buildEventItem(PlateLiveStreamEvent ev) {
      final decColor = decisionAccentColor(ev.decision);
      final subtitle = ev.identitySummary ?? ev.reason;
      return Padding(
        key: ValueKey<String>('ev_${ev.key}'),
        padding: const EdgeInsets.only(bottom: 6),
        child: Material(
          color: const Color(0xFF162238),
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => onTapEvent(ev),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: decColor.withValues(alpha: 0.42)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      // Monospace TR plaka etiketi
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0B1120),
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(color: decColor.withValues(alpha: 0.75)),
                        ),
                        child: Text(
                          ev.formattedPlate,
                          style: const TextStyle(
                            color: Colors.white,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w900,
                            fontSize: 11.5,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: decColor.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              ev.decisionLabel,
                              style: TextStyle(
                                color: decColor,
                                fontSize: 9.8,
                                fontWeight: FontWeight.w800,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11.2,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          ev.gateName,
                          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10.5),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _fmtTime(ev.timestamp),
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontFamily: 'monospace',
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      key: ValueKey<String>(cardKey),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1E293B), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: expandedHeight ? MainAxisSize.max : MainAxisSize.min,
        children: <Widget>[
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onTapHeader,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: <Widget>[
                  Icon(icon, size: 16, color: accentColor),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${events.length}',
                      style: TextStyle(
                        color: accentColor,
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.open_in_new_rounded, size: 13, color: Colors.white54),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          const Divider(height: 1, color: Colors.white12),
          const SizedBox(height: 8),
          if (expandedHeight)
            Expanded(
              child: events.isEmpty
                  ? Center(
                      child: Text(
                        emptyText,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white54, fontSize: 11.5),
                      ),
                    )
                  : ListView.builder(
                      itemCount: events.length,
                      itemBuilder: (_, idx) => buildEventItem(events[idx]),
                    ),
            )
          else if (events.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                emptyText,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54, fontSize: 11.5),
              ),
            )
          else
            Column(
              children: <Widget>[
                for (final ev in events.take(6)) buildEventItem(ev),
              ],
            ),
        ],
      ),
    );
  }
}

class _CompactDropdownContainer extends StatelessWidget {
  const _CompactDropdownContainer({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF162238),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10, fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          child,
        ],
      ),
    );
  }
}

class _MenuActionTile extends StatelessWidget {
  const _MenuActionTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Material(
        color: const Color(0xFF162238),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
            child: Row(
              children: <Widget>[
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11.8,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, size: 15, color: Colors.white38),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniIconBtn extends StatelessWidget {
  const _MiniIconBtn({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onTap,
    this.danger = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final bg = danger ? const Color(0xFFEF4444).withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.08);
    final fg = danger ? const Color(0xFFFCA5A5) : Colors.white70;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(7),
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: onTap,
        child: Tooltip(
          message: tooltip,
          child: Padding(
            padding: const EdgeInsets.all(5),
            child: Icon(icon, size: 16, color: fg),
          ),
        ),
      ),
    );
  }
}
