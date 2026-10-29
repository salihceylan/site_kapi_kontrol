import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/device_integrations_api.dart' show cameraBrandLabels;
import 'package:site_kapi_kontrol/services/plate_cameras_api.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/plate_discovery_dialog.dart' show InlineNoticeText;

const Map<String, String> _directionLabels = <String, String>{'giris': 'Giriş', 'cikis': 'Çıkış', 'auto': 'Otomatik'};

/// Kapı moduna uyan kamera yönleri: giriş kapısı Giriş / Otomatik, çıkış kapısı Çıkış / Otomatik, çift yönde hepsi (sunucu aynı kuralı doğrular).
List<String> cameraDirectionsFor(String? gateMode) => switch (gateMode) {
  'giris' => const <String>['giris', 'auto'],
  'cikis' => const <String>['cikis', 'auto'],
  _ => const <String>['giris', 'cikis', 'auto'],
};

/// Kamera ekle / düzenle (yeni akış). Kenar PC kameranın RTSP'sini yönetir: kaydedince sunucu kenara "sına" komutu verir; parola sunucuda şifreli
/// saklanır ve yanıtlarda dönmez. [onSave] başarılıysa diyalog `true` ile kapanır; sunucu hatası (örn. kapı moduyla uyumsuz yön) diyalogda gösterilir.
Future<bool?> showPlateCameraForm(
  BuildContext context, {
  required PlateCamerasOverview overview,
  required Future<void> Function(PlateCameraDraft draft) onSave,
  PlateCameraRow? editing,
  DiscoveredDevice? prefill,
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) => PlateCameraFormDialog(overview: overview, onSave: onSave, editing: editing, prefill: prefill),
  );
}

class PlateCameraFormDialog extends StatefulWidget {
  const PlateCameraFormDialog({super.key, required this.overview, required this.onSave, this.editing, this.prefill});

  final PlateCamerasOverview overview;
  final Future<void> Function(PlateCameraDraft draft) onSave;
  final PlateCameraRow? editing;
  final DiscoveredDevice? prefill;

  @override
  State<PlateCameraFormDialog> createState() => _PlateCameraFormDialogState();
}

class _PlateCameraFormDialogState extends State<PlateCameraFormDialog> {
  late final TextEditingController _name;
  late final TextEditingController _host;
  late final TextEditingController _port;
  late final TextEditingController _rtsp;
  late final TextEditingController _user;
  final TextEditingController _pass = TextEditingController();
  late String _brand;
  int? _gateId;
  String _direction = 'auto';
  bool _clearPassword = false;
  bool _busy = false;
  String? _error;

  List<BrandTemplate> get _brands => widget.overview.brands.isNotEmpty
      ? widget.overview.brands
      : <BrandTemplate>[for (final e in cameraBrandLabels.entries) BrandTemplate(code: e.key, label: e.value)];

  @override
  void initState() {
    super.initState();
    final c = widget.editing;
    final d = widget.prefill;
    _brand = c?.brand ?? (_brands.any((b) => b.code == 'hikvision') ? 'hikvision' : _brands.first.code);
    if (!_brands.any((b) => b.code == _brand)) _brand = _brands.first.code;
    _name = TextEditingController(text: c?.name ?? d?.name ?? '');
    _host = TextEditingController(text: c?.host ?? d?.ip ?? '');
    final port = c?.port ?? d?.rtspPort;
    _port = TextEditingController(text: port?.toString() ?? '');
    _rtsp = TextEditingController(text: c?.rtspUrl ?? '');
    _user = TextEditingController(text: c?.username ?? '');
    final gate = c?.gate;
    if (gate != null && widget.overview.gates.any((g) => g.id == gate.id)) {
      _gateId = gate.id;
      _direction = c?.direction ?? 'auto';
    }
  }

  @override
  void dispose() {
    for (final controller in <TextEditingController>[_name, _host, _port, _rtsp, _user, _pass]) {
      controller.dispose();
    }
    super.dispose();
  }

  PlateCameraGate? get _gate => _gateId == null ? null : widget.overview.gates.cast<PlateCameraGate?>().firstWhere((g) => g!.id == _gateId, orElse: () => null);

  BrandTemplate? get _brandTemplate => _brands.cast<BrandTemplate?>().firstWhere((b) => b!.code == _brand, orElse: () => null);

  String get _rtspHint {
    final path = _brandTemplate?.defaultRtspPath;
    return path == null ? 'Boş bırakılırsa kenar PC ONVIF ile kamerayı kendisi bulur' : 'Boş bırakılırsa markaya göre: $path';
  }

  String? _validate() {
    if (_name.text.trim().isEmpty) return 'Kamera adını yazın.';
    final rtsp = _rtsp.text.trim().toLowerCase();
    final hasUrl = rtsp.startsWith('rtsp://') || rtsp.startsWith('rtsps://');
    if (_host.text.trim().isEmpty && !hasUrl) return 'Kameranın IP adresini ya da tam RTSP adresini yazın.';
    final port = _port.text.trim();
    if (port.isNotEmpty) {
      final n = int.tryParse(port);
      if (n == null || n < 1 || n > 65535) return 'Port 1-65535 arasında olmalı.';
    }
    return null;
  }

  Future<void> _save() async {
    final problem = _validate();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSave(
        PlateCameraDraft(
          name: _name.text,
          brand: _brand,
          host: _host.text,
          port: _port.text,
          rtspInput: _rtsp.text,
          username: _user.text,
          password: _pass.text,
          clearPassword: _clearPassword,
          gateId: _gateId,
          direction: _gateId == null ? null : _direction,
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.editing;
    final directions = cameraDirectionsFor(_gate?.directionMode);
    if (!directions.contains(_direction)) _direction = 'auto';
    return AlertDialog(
      title: Text(editing == null ? 'Kamera ekle' : 'Kamerayı düzenle'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Text('Kamerayı güvenlik kulübesindeki kenar PC bağlanıp sınar; görüntüyü ve plakayı o okur.'),
              const SizedBox(height: AppSpace.sm),
              DropdownButtonFormField<String>(
                key: const ValueKey<String>('cam_brand'),
                initialValue: _brand,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Marka'),
                items: <DropdownMenuItem<String>>[for (final b in _brands) DropdownMenuItem<String>(value: b.code, child: Text(b.label, overflow: TextOverflow.ellipsis))],
                onChanged: _busy ? null : (v) => setState(() => _brand = v ?? _brand),
              ),
              TextField(key: const ValueKey<String>('cam_name'), controller: _name, maxLength: 60, enabled: !_busy, decoration: const InputDecoration(labelText: 'Ad (örn. Giriş kapısı)')),
              TextField(key: const ValueKey<String>('cam_host'), controller: _host, enabled: !_busy, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'IP adresi')),
              TextField(
                key: const ValueKey<String>('cam_port'),
                controller: _port,
                enabled: !_busy,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'RTSP portu (isteğe bağlı)'),
              ),
              TextField(
                key: const ValueKey<String>('cam_rtsp'),
                controller: _rtsp,
                enabled: !_busy,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(labelText: 'RTSP adresi ya da yolu (isteğe bağlı)', helperText: _rtspHint, helperMaxLines: 3),
              ),
              TextField(key: const ValueKey<String>('cam_user'), controller: _user, enabled: !_busy, decoration: const InputDecoration(labelText: 'Kullanıcı adı (isteğe bağlı)')),
              TextField(
                key: const ValueKey<String>('cam_pass'),
                controller: _pass,
                enabled: !_busy && !_clearPassword,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Parola (sunucuda şifreli saklanır)',
                  helperText: editing != null && editing.hasPassword ? 'Boş bırakılırsa mevcut parola korunur.' : null,
                  helperMaxLines: 2,
                ),
              ),
              if (editing != null && editing.hasPassword)
                CheckboxListTile(
                  key: const ValueKey<String>('cam_clear_pass'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _clearPassword,
                  onChanged: _busy ? null : (v) => setState(() => _clearPassword = v ?? false),
                  title: const Text('Kayıtlı parolayı sil'),
                ),
              DropdownButtonFormField<int?>(
                key: const ValueKey<String>('cam_gate'),
                initialValue: _gateId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Kapı'),
                items: <DropdownMenuItem<int?>>[
                  const DropdownMenuItem<int?>(value: null, child: Text('Kapı yok')),
                  for (final g in widget.overview.gates) DropdownMenuItem<int?>(value: g.id, child: Text(g.name, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: _busy ? null : (v) => setState(() => _gateId = v),
              ),
              DropdownButtonFormField<String>(
                key: ValueKey<String>('cam_direction_${_gateId ?? 'none'}'),
                initialValue: _direction,
                isExpanded: true,
                decoration: InputDecoration(labelText: 'Yön', helperText: _gateId == null ? 'Yön, kamera bir kapıya bağlanınca seçilir.' : null, helperMaxLines: 2),
                items: <DropdownMenuItem<String>>[for (final d in directions) DropdownMenuItem<String>(value: d, child: Text(_directionLabels[d] ?? d))],
                onChanged: _busy || _gateId == null ? null : (v) => setState(() => _direction = v ?? _direction),
              ),
              if (_error != null) ...<Widget>[
                const SizedBox(height: AppSpace.sm),
                InlineNoticeText(key: const ValueKey<String>('cam_error'), tone: AppTone.danger, text: _error!),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: const Text('Vazgeç')),
        FilledButton(key: const ValueKey<String>('cam_save'), onPressed: _busy ? null : () => unawaited(_save()), child: Text(_busy ? 'Kaydediliyor…' : 'Kaydet')),
      ],
    );
  }
}
