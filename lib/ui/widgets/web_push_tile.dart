import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/web_push_client.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

/// Tarayıcı bildirimi (Firebase'siz VAPID web push, 063). Yalnız web'de ve tarayıcı destekliyorsa görünür.
/// Sunucuda VAPID anahtarı yoksa "Yakında…" gösterir.
class WebPushTile extends StatefulWidget {
  const WebPushTile({super.key, required this.authService});

  final AuthService authService;

  @override
  State<WebPushTile> createState() => _WebPushTileState();
}

class _WebPushTileState extends State<WebPushTile> {
  bool _loading = true;
  bool _serverEnabled = false;
  String? _publicKey;
  bool _on = false;
  bool _busy = false;
  String? _error;

  String get _base => widget.authService.api.baseUrl.replaceAll(RegExp(r'/+$'), '');

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer ${widget.authService.session?.token ?? ''}',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final response = await http.get(Uri.parse('$_base/app/web-push/config'), headers: _headers);
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final endpoint = await webPushCurrentEndpoint();
      if (!mounted) return;
      setState(() {
        _serverEnabled = response.statusCode == 200 && body['enabled'] == true;
        _publicKey = body['public_key'] as String?;
        _on = endpoint != null;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggle(bool value) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (value) {
        final json = await webPushSubscribe(_publicKey ?? '');
        if (json == null) {
          _error = 'Tarayıcı bildirimi için izin verilmedi.';
        } else {
          final response = await http.put(Uri.parse('$_base/app/web-push/subscriptions'), headers: _headers, body: json);
          if (response.statusCode == 200) {
            _on = true;
          } else {
            await webPushUnsubscribe();
            _error = 'Bildirim kaydedilemedi, tekrar deneyin.';
          }
        }
      } else {
        final endpoint = await webPushUnsubscribe();
        if (endpoint != null) {
          await http.delete(
            Uri.parse('$_base/app/web-push/subscriptions'),
            headers: _headers,
            body: jsonEncode({'endpoint': endpoint}),
          );
        }
        _on = false;
      }
    } catch (_) {
      _error = 'Tarayıcı bildirimi açılamadı.';
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!webPushSupported()) return const SizedBox.shrink();
    final th = Theme.of(context).textTheme;
    if (_loading) return const SizedBox.shrink();
    if (!_serverEnabled) {
      return Row(
        children: [
          const Icon(Icons.web_rounded, size: 20),
          const SizedBox(width: AppSpace.md),
          Expanded(child: Text('Tarayıcı bildirimi', style: th.bodyLarge)),
          const StatusChip(label: 'Yakında…', tone: AppTone.neutral, icon: Icons.schedule_rounded),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.web_rounded),
          title: const Text('Tarayıcı bildirimi'),
          subtitle: const Text('Kargo geldi gibi bildirimler bu tarayıcıya da gelir.'),
          value: _on,
          onChanged: _busy ? null : _toggle,
        ),
        if (_error != null) Text(_error!, style: th.bodySmall),
      ],
    );
  }
}
