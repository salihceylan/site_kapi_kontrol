import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/device_record.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/models/site_record.dart';
import 'package:site_kapi_kontrol/models/site_structure_record.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/styles/app_colors.dart';
import 'package:site_kapi_kontrol/ui/helpers/ui_helpers.dart';

class DoorDeviceAssignResult {
  const DoorDeviceAssignResult({required this.deviceUid});

  final String deviceUid;
}

class DoorDeviceDialog extends StatefulWidget {
  const DoorDeviceDialog({
    super.key,
    required this.door,
    required this.initialDeviceUid,
  });

  final DoorRecord door;
  final String initialDeviceUid;

  static Future<DoorDeviceAssignResult?> show(
    BuildContext context, {
    required DoorRecord door,
    required String initialDeviceUid,
  }) {
    return showDialog<DoorDeviceAssignResult>(
      context: context,
      builder: (_) => DoorDeviceDialog(
        door: door,
        initialDeviceUid: initialDeviceUid,
      ),
    );
  }

  @override
  State<DoorDeviceDialog> createState() => _DoorDeviceDialogState();
}

class _DoorDeviceDialogState extends State<DoorDeviceDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _deviceUidController;

  @override
  void initState() {
    super.initState();
    _deviceUidController = TextEditingController(text: widget.initialDeviceUid);
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
    Navigator.of(context).pop(
      DoorDeviceAssignResult(
        deviceUid: _deviceUidController.text.trim().toUpperCase(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: Text('${widget.door.doorName} - Cihaz Ata'),
      content: SizedBox(
        width: dialogWidthForScreen(context),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _deviceUidController,
                  decoration: const InputDecoration(labelText: 'Cihaz Unique ID'),
                  validator: (value) => (value ?? '').trim().length < 6
                      ? 'Cihaz unique id en az 6 karakter olmalı.'
                      : null,
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Mevcut cihaz: ${widget.door.assignedDeviceUid ?? 'Atanmadı'}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('İptal'),
        ),
        ElevatedButton(onPressed: _submit, child: const Text('Ata')),
      ],
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
    Navigator.of(context).pop(door);
  }

  @override
  Widget build(BuildContext context) {
    final doors = _structure?.doors ?? const <DoorRecord>[];
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: Text('${widget.device.deviceUid} - Kapıya Ata'),
      content: SizedBox(
        width: dialogWidthForScreen(context),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                initialValue: _selectedSite?.id,
                decoration: const InputDecoration(labelText: 'Site'),
                items: [
                  for (final site in widget.sites)
                    DropdownMenuItem<int>(
                      value: site.id,
                      child: Text('${site.name} (${site.id})'),
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
              const SizedBox(height: 12),
              if (_loadingDoors)
                const LinearProgressIndicator()
              else if (_error != null)
                Text(_error!, style: const TextStyle(color: Colors.red))
              else
                DropdownButtonFormField<int>(
                  initialValue: _selectedDoor?.id,
                  decoration: const InputDecoration(labelText: 'Kapı'),
                  items: [
                    for (final door in doors)
                      DropdownMenuItem<int>(
                        value: door.id,
                        child: Text(
                          '${door.doorName} - ${door.assignedDeviceUid ?? 'Boş'}',
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
        ),
      ),
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
    );
  }
}

