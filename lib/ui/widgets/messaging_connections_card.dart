import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

/// Site başına SMS + WhatsApp bağlantısı uçları için ince HTTP katmanı (sırlar günlüğe yazılmaz; yazma ASLA otomatik yeniden denenmez).
class MessagingApi {
  MessagingApi({required String baseUrl, http.Client? client})
    : _baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), ''),
      _client = client ?? http.Client();

  final String _baseUrl;
  final http.Client _client;

  Future<Map<String, dynamic>> call(String method, int siteCode, String tail, String token, {Map<String, Object?>? body}) async {
    final request = http.Request(method, Uri.parse('$_baseUrl/manager/sites/$siteCode/messaging$tail'))
      ..headers.addAll(<String, String>{'Authorization': 'Bearer $token', 'Accept': 'application/json'});
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final http.Response response;
    try {
      response = await _client.send(request).then(http.Response.fromStream).timeout(const Duration(seconds: 25));
    } on Exception {
      throw ApiException('Sunucuya bağlanılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.');
    }
    Map<String, dynamic>? payload;
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) payload = decoded;
    } on FormatException {
      payload = null;
    }
    if (response.statusCode >= 200 && response.statusCode < 300 && payload != null) return payload;
    throw ApiException(
      payload?['error']?.toString() ?? 'İşlem tamamlanamadı (${response.statusCode}). Lütfen tekrar deneyin.',
      statusCode: response.statusCode,
      code: payload?['code']?.toString(),
    );
  }
}

class _Field {
  const _Field(this.key, this.label, {this.obscure = false, this.hint});

  final String key;
  final String label;
  final bool obscure;
  final String? hint;
}

/// Ayarlar > bildirim kanalları bölgesinde (Duyurular ekranı) site başına SMS ve WhatsApp bağlantısı. Yönetici yazar; kurul üyesi yalnız görür.
/// SMS: sağlayıcıya (NetGSM) kendi hesabıyla bağlanır; "Bağlantıyı sına" yalnız kimlik/bakiye sorgular, GERÇEK SMS GÖNDERMEZ.
/// WhatsApp: bu sürümde doğrulama modunda (sürücü etkin değil); sahte bağlantı gösterilmez.
class MessagingConnectionsCard extends StatefulWidget {
  const MessagingConnectionsCard({super.key, required this.authService, required this.siteCode, required this.canWrite, this.api});

  final AuthService authService;
  final int siteCode;
  final bool canWrite;
  final MessagingApi? api;

  @override
  State<MessagingConnectionsCard> createState() => _MessagingConnectionsCardState();
}

class _MessagingConnectionsCardState extends State<MessagingConnectionsCard> {
  late final MessagingApi _api = widget.api ?? MessagingApi(baseUrl: widget.authService.api.baseUrl);
  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = true;
  bool _busy = false;

  static const List<_Field> _smsFields = <_Field>[
    _Field('usercode', 'Kullanıcı kodu'),
    _Field('password', 'Şifre', obscure: true),
    _Field('header', 'Mesaj başlığı', hint: 'Sağlayıcıda onaylı başlık'),
  ];
  static const List<_Field> _waFields = <_Field>[
    _Field('business_name', 'İşletme adı'),
    _Field('phone_number_id', 'Telefon numarası kimliği (phone_number_id)'),
    _Field('access_token', 'Erişim belirteci', obscure: true),
  ];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(MessagingConnectionsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.siteCode != widget.siteCode) unawaited(_load());
  }

  String? get _token => widget.authService.session?.token;

  Map<String, dynamic> _map(Object? raw) => raw is Map<String, dynamic> ? raw : const <String, dynamic>{};

  Future<void> _load() async {
    final token = _token;
    final site = widget.siteCode;
    if (token == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final next = await _api.call('GET', site, '', token);
      if (!mounted || site != widget.siteCode) return;
      setState(() {
        _data = next;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted || site != widget.siteCode) return;
      setState(() {
        _data = null;
        _loading = false;
        _error = e.message;
      });
    }
  }

  Future<void> _run(Future<void> Function(String token) action) async {
    final token = _token;
    if (token == null || _busy) return;
    setState(() => _busy = true);
    try {
      await action(token);
      await _load();
    } on ApiException catch (e) {
      if (mounted) AppSnack.show(context, e.message, kind: AppSnackKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit(String channel, String title, List<_Field> fields, Map<String, Object?> extra, {required bool exists}) async {
    final values = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => _FieldsDialog(title: title, fields: fields, note: exists ? 'Gizli alanları boş bırakırsanız kayıtlı değer korunur.' : null),
    );
    if (values == null) return;
    await _run((token) async {
      await _api.call('PUT', widget.siteCode, '/$channel', token, body: <String, Object?>{...extra, ...values});
      if (mounted) AppSnack.show(context, 'Bağlantı kaydedildi.', kind: AppSnackKind.success);
    });
  }

  Future<void> _test(String channel) => _run((token) async {
    final result = await _api.call('POST', widget.siteCode, '/$channel/test', token);
    if (!mounted) return;
    final message = result['message']?.toString() ?? 'Sınama tamamlandı.';
    final balance = result['balance'];
    final ok = channel == 'sms' && result['ok'] == true;
    AppSnack.show(
      context,
      balance is num ? '$message Bakiye: $balance' : message,
      kind: ok ? AppSnackKind.success : AppSnackKind.warning,
    );
  });

  Future<void> _remove(String channel, String label) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$label bağlantısı kaldırılsın mı?'),
        content: const Text('Kayıtlı bilgiler silinir. Sağlayıcı hesabınıza dokunulmaz.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Kaldır')),
        ],
      ),
    );
    if (ok != true) return;
    await _run((token) async {
      await _api.call('DELETE', widget.siteCode, '/$channel?confirm=true', token);
    });
  }

  Widget _actions(List<Widget> buttons) => Padding(
    padding: const EdgeInsets.only(top: AppSpace.sm),
    child: Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.xs, children: buttons),
  );

  Widget _button(String key, String label, IconData icon, VoidCallback? onPressed) => PrimaryActionButton(
    key: ValueKey<String>(key),
    label: label,
    icon: icon,
    variant: AppButtonVariant.outline,
    expand: false,
    loading: false,
    onPressed: _busy ? null : onPressed,
  );

  Widget _lastTest(Map<String, dynamic> connection) {
    final last = connection['last_test'];
    if (last is! Map) return const SizedBox.shrink();
    final ok = last['ok'];
    final code = last['code']?.toString() ?? '';
    final (label, tone) = switch (ok) {
      true => ('Son sınama: başarılı', AppTone.success),
      false => ('Son sınama: başarısız ($code)', AppTone.danger),
      _ => ('Son sınama: yalnız alan doğrulaması', AppTone.info),
    };
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.xs),
      child: Wrap(children: [StatusChip(label: label, tone: tone)]),
    );
  }

  Widget _smsSection(Map<String, dynamic> sms, TextStyle? muted) {
    final connection = sms['connection'] is Map<String, dynamic> ? sms['connection'] as Map<String, dynamic> : null;
    final drivers = sms['drivers'] is List ? sms['drivers'] as List : const <Object?>[];
    final provider = drivers.isNotEmpty && drivers.first is Map ? (drivers.first as Map)['id']?.toString() ?? 'netgsm' : 'netgsm';
    final providerLabel = drivers.isNotEmpty && drivers.first is Map ? (drivers.first as Map)['label']?.toString() ?? 'NetGSM' : 'NetGSM';
    final config = _map(connection?['config']);
    final canEdit = widget.canWrite && _data?['key_configured'] != false;
    return Column(
      key: const ValueKey<String>('messaging_sms'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('SMS (kendi sağlayıcınız)', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: AppSpace.xs),
        if (connection == null)
          Text(
            sms['global_fallback'] == true ? 'Şu an platformun ortak SMS hesabı kullanılıyor.' : 'SMS bağlantısı tanımlı değil.',
            key: const ValueKey<String>('messaging_sms_empty'),
            style: muted,
          )
        else ...[
          Text('$providerLabel · başlık: ${config['header'] ?? '-'} · kullanıcı: ${config['secret_hint'] ?? '-'}', style: muted),
          _lastTest(connection),
        ],
        if (canEdit)
          _actions([
            _button('messaging_sms_edit', connection == null ? '$providerLabel hesabına bağlan' : 'Düzenle', Icons.edit_outlined, () {
              unawaited(_edit('sms', 'SMS bağlantısı ($providerLabel)', _smsFields, <String, Object?>{'provider': provider}, exists: connection != null));
            }),
            if (connection != null) ...[
              _button('messaging_sms_test', 'Bağlantıyı sına', Icons.verified_outlined, () => unawaited(_test('sms'))),
              _button('messaging_sms_remove', 'Kaldır', Icons.link_off_rounded, () => unawaited(_remove('sms', 'SMS'))),
            ],
          ]),
      ],
    );
  }

  Widget _whatsappSection(Map<String, dynamic> wa, TextStyle? muted) {
    final connection = wa['connection'] is Map<String, dynamic> ? wa['connection'] as Map<String, dynamic> : null;
    final driver = _map(wa['driver']);
    final config = _map(connection?['config']);
    final canEdit = widget.canWrite && _data?['key_configured'] != false;
    return Column(
      key: const ValueKey<String>('messaging_whatsapp'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('WhatsApp (${driver['label'] ?? 'Meta WhatsApp Cloud API'})', style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: AppSpace.xs),
        if (driver['active'] != true)
          InlineNotice(
            key: const ValueKey<String>('messaging_whatsapp_note'),
            tone: AppTone.info,
            message: driver['note']?.toString() ?? 'WhatsApp sürücüsü bu sürümde doğrulama modunda; Meta hesabı bağlanınca etkinleşir.',
          ),
        const SizedBox(height: AppSpace.xs),
        if (connection == null)
          Text('WhatsApp bilgileri girilmedi.', style: muted)
        else ...[
          Text('${config['business_name'] ?? '-'} · numara kimliği: ${config['phone_number_id'] ?? '-'}', style: muted),
          _lastTest(connection),
        ],
        if (canEdit)
          _actions([
            _button('messaging_wa_edit', connection == null ? 'Bilgileri gir' : 'Düzenle', Icons.edit_outlined, () {
              unawaited(_edit('whatsapp', 'WhatsApp bilgileri', _waFields, const <String, Object?>{}, exists: connection != null));
            }),
            if (connection != null) ...[
              _button('messaging_wa_test', 'Alanları doğrula', Icons.fact_check_outlined, () => unawaited(_test('whatsapp'))),
              _button('messaging_wa_remove', 'Kaldır', Icons.link_off_rounded, () => unawaited(_remove('whatsapp', 'WhatsApp'))),
            ],
          ]),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodySmall;
    final data = _data;
    return AppCard(
      key: const ValueKey<String>('messaging_card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.sms_outlined),
              const SizedBox(width: AppSpace.sm),
              Expanded(child: Text('SMS ve WhatsApp bağlantısı', style: Theme.of(context).textTheme.titleMedium)),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          if (_loading)
            const LinearProgressIndicator(minHeight: 3)
          else if (data == null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_error ?? 'Bağlantılar yüklenemedi.', style: muted),
                TextButton(onPressed: _load, child: const Text('Tekrar dene')),
              ],
            )
          else ...[
            if (!widget.canWrite)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.sm),
                child: Text('Yönetim kurulu üyesi olarak bağlantıları yalnızca görüntüleyebilirsiniz.', style: muted),
              ),
            if (widget.canWrite && data['key_configured'] == false)
              const Padding(
                padding: EdgeInsets.only(bottom: AppSpace.sm),
                child: InlineNotice(
                  key: ValueKey<String>('messaging_no_key'),
                  tone: AppTone.warning,
                  message: 'Sunucuda şifreleme anahtarı tanımlı değil; bağlantı bilgileri şimdilik kaydedilemez.',
                ),
              ),
            _smsSection(_map(data['sms']), muted),
            const Divider(height: AppSpace.xl),
            _whatsappSection(_map(data['whatsapp']), muted),
          ],
        ],
      ),
    );
  }
}

class _FieldsDialog extends StatefulWidget {
  const _FieldsDialog({required this.title, required this.fields, this.note});

  final String title;
  final List<_Field> fields;
  final String? note;

  @override
  State<_FieldsDialog> createState() => _FieldsDialogState();
}

class _FieldsDialogState extends State<_FieldsDialog> {
  late final Map<String, TextEditingController> _controllers = <String, TextEditingController>{
    for (final f in widget.fields) f.key: TextEditingController(),
  };

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.note != null) Padding(padding: const EdgeInsets.only(bottom: AppSpace.sm), child: Text(widget.note!)),
          for (final f in widget.fields)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.sm),
              child: TextField(
                key: ValueKey<String>('messaging_field_${f.key}'),
                controller: _controllers[f.key],
                obscureText: f.obscure,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(labelText: f.label, helperText: f.hint),
              ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
      TextButton(
        key: const ValueKey<String>('messaging_save'),
        onPressed: () => Navigator.pop(context, <String, String>{for (final e in _controllers.entries) e.key: e.value.text.trim()}),
        child: const Text('Kaydet'),
      ),
    ],
  );
}
