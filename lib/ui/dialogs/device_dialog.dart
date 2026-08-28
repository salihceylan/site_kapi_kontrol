import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/device_record.dart';
import 'package:site_kapi_kontrol/styles/app_colors.dart';
import 'package:site_kapi_kontrol/ui/helpers/ui_helpers.dart';

class DeviceFormResult {
  const DeviceFormResult({
    required this.deviceUid,
    required this.assignedUserCode,
    required this.siteCode,
  });

  final String deviceUid;
  final int? assignedUserCode;
  final int? siteCode;
}

class DeviceEditResult {
  const DeviceEditResult({
    required this.assignedUserCode,
    required this.siteCode,
    required this.gateName,
  });

  final int? assignedUserCode;
  final int? siteCode;
  final String? gateName;
}

class DeviceDialog extends StatefulWidget {
  const DeviceDialog({
    super.key,
    this.initialDeviceUid,
  });

  final String? initialDeviceUid;

  static Future<DeviceFormResult?> show(
    BuildContext context, {
    String? initialDeviceUid,
  }) {
    return showDialog<DeviceFormResult>(
      context: context,
      builder: (_) => DeviceDialog(initialDeviceUid: initialDeviceUid),
    );
  }

  @override
  State<DeviceDialog> createState() => _DeviceDialogState();
}

class _DeviceDialogState extends State<DeviceDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _deviceUidController;
  late final TextEditingController _assignedUserCodeController;
  late final TextEditingController _siteCodeController;

  @override
  void initState() {
    super.initState();
    _deviceUidController = TextEditingController(
      text: widget.initialDeviceUid ?? '',
    );
    _assignedUserCodeController = TextEditingController();
    _siteCodeController = TextEditingController();
  }

  @override
  void dispose() {
    _deviceUidController.dispose();
    _assignedUserCodeController.dispose();
    _siteCodeController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final assignedUserCodeText = _assignedUserCodeController.text.trim();
    final siteCodeText = _siteCodeController.text.trim();

    Navigator.of(context).pop(
      DeviceFormResult(
        deviceUid: _deviceUidController.text.trim().toUpperCase(),
        assignedUserCode: assignedUserCodeText.isEmpty
            ? null
            : int.parse(assignedUserCodeText),
        siteCode: siteCodeText.isEmpty ? null : int.parse(siteCodeText),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: const Text('Cihaz Kaydet'),
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
                  decoration: const InputDecoration(
                    labelText: 'Cihaz Unique ID (UID)',
                    hintText: 'Örn: 1CDA72A172E0',
                  ),
                  validator: (value) => (value ?? '').trim().length < 6
                      ? 'Cihaz Unique ID en az 6 karakter olmalı.'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _assignedUserCodeController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Kullanıcı ID (opsiyonel)',
                  ),
                  validator: (value) {
                    final text = (value ?? '').trim();
                    if (text.isEmpty) return null;
                    return int.tryParse(text) == null
                        ? 'Kullanıcı ID sayısal olmalı.'
                        : null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _siteCodeController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Site ID (opsiyonel)',
                  ),
                  validator: (value) {
                    final text = (value ?? '').trim();
                    if (text.isEmpty) return null;
                    return int.tryParse(text) == null
                        ? 'Site ID sayısal olmalı.'
                        : null;
                  },
                ),
                const SizedBox(height: 12),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Kullanıcı ID ve Site ID alanlarını boş bırakabilirsiniz.',
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted),
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
        ElevatedButton(onPressed: _submit, child: const Text('Cihazı Kaydet')),
      ],
    );
  }
}

class DeviceEditDialog extends StatefulWidget {
  const DeviceEditDialog({
    super.key,
    required this.device,
    required this.isSuperUser,
  });

  final DeviceRecord device;
  final bool isSuperUser;

  static Future<DeviceEditResult?> show(
    BuildContext context, {
    required DeviceRecord device,
    required bool isSuperUser,
  }) {
    return showDialog<DeviceEditResult>(
      context: context,
      builder: (_) => DeviceEditDialog(
        device: device,
        isSuperUser: isSuperUser,
      ),
    );
  }

  @override
  State<DeviceEditDialog> createState() => _DeviceEditDialogState();
}

class _DeviceEditDialogState extends State<DeviceEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _assignedUserCodeController;
  late final TextEditingController _siteCodeController;
  late final TextEditingController _gateNameController;

  @override
  void initState() {
    super.initState();
    _assignedUserCodeController = TextEditingController(
      text: widget.device.assignedUserCode?.toString() ?? '',
    );
    _siteCodeController = TextEditingController(
      text: widget.device.siteCode?.toString() ?? '',
    );
    _gateNameController = TextEditingController(
      text: widget.device.gateName ?? '',
    );
  }

  @override
  void dispose() {
    _assignedUserCodeController.dispose();
    _siteCodeController.dispose();
    _gateNameController.dispose();
    super.dispose();
  }

  int? _parseOptionalInt(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    return int.tryParse(text);
  }

  String? _validateOptionalInt(String? value, String label) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return null;
    return int.tryParse(text) == null ? '$label sayısal olmalı.' : null;
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    Navigator.of(context).pop(
      DeviceEditResult(
        assignedUserCode: widget.isSuperUser
            ? _parseOptionalInt(_assignedUserCodeController.text)
            : widget.device.assignedUserCode,
        siteCode: _parseOptionalInt(_siteCodeController.text),
        gateName: _gateNameController.text.trim().isEmpty
            ? null
            : _gateNameController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: Text('${widget.device.deviceUid} - Düzenle'),
      content: SizedBox(
        width: dialogWidthForScreen(context),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.isSuperUser) ...[
                  TextFormField(
                    controller: _assignedUserCodeController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Kullanıcı ID (opsiyonel)',
                    ),
                    validator: (value) =>
                        _validateOptionalInt(value, 'Kullanıcı ID'),
                  ),
                  const SizedBox(height: 12),
                ],
                TextFormField(
                  controller: _siteCodeController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Site ID (opsiyonel)',
                  ),
                  validator: (value) => _validateOptionalInt(value, 'Site ID'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _gateNameController,
                  decoration: const InputDecoration(
                    labelText: 'Kapı Etiketi (opsiyonel)',
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
        ElevatedButton(onPressed: _submit, child: const Text('Kaydet')),
      ],
    );
  }
}
