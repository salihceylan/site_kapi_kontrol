import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:site_kapi_kontrol/models/device_record.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/models/site_record.dart';
import 'package:site_kapi_kontrol/models/site_structure_record.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/icon_orb.dart';
import 'package:site_kapi_kontrol/ui/design/motion_widgets.dart';
import 'package:site_kapi_kontrol/ui/design/skeleton.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/large_dialog_parts.dart';
import 'package:site_kapi_kontrol/ui/dialogs/replace_device_dialog.dart';

class DoorDeviceAssignResult {
  const DoorDeviceAssignResult({
    this.deviceUid,
    this.unassign = false,
  });

  final String? deviceUid;
  final bool unassign;
}

class DoorDeviceDialog extends StatefulWidget {
  const DoorDeviceDialog({
    super.key,
    required this.door,
    required this.initialDeviceUid,
    this.authService,
  });

  final DoorRecord door;
  final String initialDeviceUid;
  final AuthService? authService;

  static Future<DoorDeviceAssignResult?> show(
    BuildContext context, {
    required DoorRecord door,
    required String initialDeviceUid,
    AuthService? authService,
  }) {
    return showDialog<DoorDeviceAssignResult>(
      context: context,
      builder: (_) => DoorDeviceDialog(
        door: door,
        initialDeviceUid: initialDeviceUid,
        authService: authService,
      ),
    );
  }

  @override
  State<DoorDeviceDialog> createState() => _DoorDeviceDialogState();
}

class _DoorDeviceDialogState extends State<DoorDeviceDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _deviceUidController;

  List<Map<String, dynamic>> _assignableDevices = [];
  bool _loadingDevices = false;

  @override
  void initState() {
    super.initState();
    _deviceUidController = TextEditingController(text: widget.initialDeviceUid);
    _loadAssignableDevices();
  }

  Future<void> _loadAssignableDevices() async {
    if (widget.authService == null) return;
    setState(() => _loadingDevices = true);
    final list = await widget.authService!.getAssignableDevices(siteCode: widget.door.siteCode);
    if (!mounted) return;
    setState(() {
      _assignableDevices = list;
      _loadingDevices = false;
    });
  }

  @override
  void dispose() {
    _deviceUidController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    HapticFeedback.lightImpact();
    Navigator.of(context).pop(
      DoorDeviceAssignResult(
        deviceUid: _deviceUidController.text.trim().toUpperCase(),
        unassign: false,
      ),
    );
  }

  void _unassign() {
    HapticFeedback.lightImpact();
    Navigator.of(context).pop(
      const DoorDeviceAssignResult(
        deviceUid: null,
        unassign: true,
      ),
    );
  }

  /// Mevcut cihaz durumu: cihaz varsa birincil, yoksa uyarı tonlu panel + cilalı çip rozeti.
  /// Büyük yazıda (>= 1,75x) rozet gizlenir.
  Widget _buildStatusPanel(BuildContext context, AppTone statusTone) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    return DialogPanel(
      tone: statusTone,
      child: Row(
        children: [
          if (!hideRowOrbs(context)) ...[
            IconOrb(
              icon: Icons.memory_rounded,
              tone: statusTone,
              size: 40,
              shape: IconOrbShape.squircle,
            ),
            const SizedBox(width: AppSpace.md),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Mevcut Cihaz: ${widget.door.assignedDeviceUid ?? "Atanmadı"}',
                  style: th.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: statusTone.ink(p),
                  ),
                ),
                if (widget.door.hasDevice) ...[
                  const SizedBox(height: AppSpace.xs),
                  Text(
                    'Model: ${widget.door.hardwareModelTitle} (${widget.door.hardwareBadgeText})',
                    style: th.bodySmall?.copyWith(color: p.textSecondary),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Seçilebilir cihaz satırı: [donanım ikon rozeti] [UID + donanım] [seçim işareti]. Satırın
  /// tamamı dokunma hedefidir (`AppCard`, >= 48 dp); seçili satır birincil kenarlıdır.
  Widget _buildDeviceTile(BuildContext context, Map<String, dynamic> dev) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final uid = dev['device_uid']?.toString() ?? '';
    final hw = dev['hardware_type']?.toString() ?? '';
    final isWroom = hw.toLowerCase().contains('wroom');
    final isSelected = _deviceUidController.text.trim().toUpperCase() == uid.toUpperCase();
    final accent = AppTone.primary.ink(p);

    return AppCard(
      selected: isSelected,
      padding: const EdgeInsets.all(AppSpace.md),
      onTap: () {
        setState(() {
          _deviceUidController.text = uid;
        });
      },
      child: Row(
        children: [
          if (!hideRowOrbs(context)) ...[
            IconOrb(
              icon: isWroom ? Icons.memory_rounded : Icons.developer_board_rounded,
              tone: isSelected ? AppTone.primary : AppTone.neutral,
              size: 40,
              shape: IconOrbShape.squircle,
            ),
            const SizedBox(width: AppSpace.md),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  uid,
                  style: th.bodyMedium?.copyWith(
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w700,
                    color: isSelected ? accent : p.text,
                  ),
                ),
                Text(
                  isWroom ? 'WROOM' : 'C3',
                  style: th.bodySmall?.copyWith(color: p.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          Icon(
            isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
            size: 22,
            color: isSelected ? accent : p.textMuted,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final statusTone = widget.door.hasDevice ? AppTone.primary : AppTone.warning;

    return AppDialog(
      title: '${widget.door.doorName} - Cihaz Yönetimi',
      icon: Icons.memory_rounded,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('İptal'),
        ),
        ElevatedButton(onPressed: _submit, child: const Text('Cihazı Ata')),
      ],
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Mevcut Cihaz Durumu
            _buildStatusPanel(context, statusTone),
            const SizedBox(height: AppSpace.lg),

            // Atanabilir Cihazlar Listesi (ilk 8 satır girişte kademeli belirir)
            if (_loadingDevices)
              const DialogRowsSkeleton(rows: 2)
            else if (_assignableDevices.isNotEmpty) ...[
              Text(
                'Kullanılabilir Cihazlarınız:',
                style: th.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: p.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpace.sm),
              for (var i = 0; i < _assignableDevices.length; i++) ...[
                if (i > 0) const SizedBox(height: AppSpace.sm),
                StaggeredEntry(
                  index: i,
                  child: _buildDeviceTile(context, _assignableDevices[i]),
                ),
              ],
              const SizedBox(height: AppSpace.lg),
            ],

            // UID Girişi
            TextFormField(
              controller: _deviceUidController,
              decoration: const InputDecoration(
                labelText: 'Cihaz Unique ID (UID)',
                hintText: 'Örn: 00861A0D5020',
                prefixIcon: Icon(Icons.qr_code_rounded),
              ),
              validator: (value) => (value ?? '').trim().length < 6
                  ? 'Cihaz unique id en az 6 karakter olmalı.'
                  : null,
            ),

            // Cihaz Değiştir & Çıkar Butonları
            if (widget.door.hasDevice) ...[
              if (widget.authService != null) ...[
                const SizedBox(height: AppSpace.lg),
                ElevatedButton.icon(
                  onPressed: () async {
                    final nav = Navigator.of(context);
                    final success = await ReplaceDeviceDialog.show(
                      context,
                      door: widget.door,
                      authService: widget.authService!,
                    );
                    if (success == true && mounted) {
                      nav.pop();
                    }
                  },
                  icon: const Icon(Icons.published_with_changes_rounded, size: 18),
                  label: const Text('Arızalı Cihazı Değiştir (QR / Seri No)'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTone.warning.a,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
              const SizedBox(height: AppSpace.md),
              OutlinedButton.icon(
                onPressed: _unassign,
                icon: const Icon(Icons.link_off_rounded, size: 18),
                label: const Text(
                  'Cihazı Kapıdan Çıkar (Serbest Bırak)',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTone.danger.ink(p),
                  side: BorderSide(color: AppTone.danger.hue.withValues(alpha: 0.5)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class DeviceDoorAssignDialog extends StatefulWidget {
  const DeviceDoorAssignDialog({
    super.key,
    required this.authService,
    required this.sites,
    required this.device,
  });

  final AuthService authService;
  final List<SiteRecord> sites;
  final DeviceRecord device;

  static Future<DoorRecord?> show(
    BuildContext context, {
    required AuthService authService,
    required List<SiteRecord> sites,
    required DeviceRecord device,
  }) {
    return showDialog<DoorRecord>(
      context: context,
      builder: (_) => DeviceDoorAssignDialog(
        authService: authService,
        sites: sites,
        device: device,
      ),
    );
  }

  @override
  State<DeviceDoorAssignDialog> createState() =>
      _DeviceDoorAssignDialogState();
}

class _DeviceDoorAssignDialogState extends State<DeviceDoorAssignDialog> {
  SiteRecord? _selectedSite;
  SiteStructureRecord? _structure;
  DoorRecord? _selectedDoor;
  bool _loadingDoors = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selectedSite = widget.sites.isEmpty ? null : widget.sites.first;
    if (_selectedSite != null) {
      _loadDoors(_selectedSite!.id);
    }
  }

  Future<void> _loadDoors(int siteCode) async {
    setState(() {
      _loadingDoors = true;
      _structure = null;
      _selectedDoor = null;
      _error = null;
    });
    final (structure, error) = await widget.authService.getSiteStructure(
      siteCode: siteCode,
    );
    if (!mounted) return;
    setState(() {
      _loadingDoors = false;
      _structure = structure;
      _selectedDoor = structure?.doors.isEmpty ?? true
          ? null
          : structure!.doors.first;
      _error = error;
    });
  }

  void _submit() {
    final door = _selectedDoor;
    if (door == null) return;
    HapticFeedback.lightImpact();
    Navigator.of(context).pop(door);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final doors = _structure?.doors ?? const <DoorRecord>[];
    return AppDialog(
      title: '${widget.device.deviceUid} - Kapıya Ata',
      icon: Icons.door_front_door_rounded,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('İptal'),
        ),
        ElevatedButton(
          onPressed: _selectedDoor == null || _loadingDoors ? null : _submit,
          child: const Text('Ata'),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<int>(
            isExpanded: true,
            borderRadius: BorderRadius.circular(AppRadius.md),
            dropdownColor: p.surface,
            menuMaxHeight: 320,
            icon: const Icon(Icons.keyboard_arrow_down_rounded),
            initialValue: _selectedSite?.id,
            decoration: const InputDecoration(labelText: 'Site'),
            items: [
              for (final site in widget.sites)
                DropdownMenuItem<int>(
                  value: site.id,
                  child: Text(
                    '${site.name} (${site.id})',
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
            ],
            onChanged: (value) {
              if (value == null) return;
              final site =
                  widget.sites.firstWhere((item) => item.id == value);
              setState(() => _selectedSite = site);
              _loadDoors(site.id);
            },
          ),
          const SizedBox(height: AppSpace.md),
          if (_loadingDoors)
            // Kapı seçicinin boyutunda iskelet (paylaşılan tek shimmer; yükleme bitince kalkar).
            const ShimmerScope(
              child: SkeletonBox(height: 56, radius: AppRadius.md),
            )
          else if (_error != null)
            InlineNotice(message: _error!)
          else
            DropdownButtonFormField<int>(
              isExpanded: true,
              borderRadius: BorderRadius.circular(AppRadius.md),
              dropdownColor: p.surface,
              menuMaxHeight: 320,
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
              initialValue: _selectedDoor?.id,
              decoration: const InputDecoration(labelText: 'Kapı'),
              items: [
                for (final door in doors)
                  DropdownMenuItem<int>(
                    value: door.id,
                    child: Text(
                      door.assignedDeviceUid == null
                          ? '${door.doorName} - Boş'
                          : '${door.doorName} • ${door.hardwareBadgeText} (${door.assignedDeviceUid})',
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
              ],
              onChanged: (value) {
                if (value == null) return;
                final door = doors.firstWhere((item) => item.id == value);
                setState(() => _selectedDoor = door);
              },
            ),
        ],
      ),
    );
  }
}
