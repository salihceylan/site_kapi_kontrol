import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';
import 'package:url_launcher/url_launcher.dart';

/// Sitenin Google Drive durumu (`GET /manager/sites/:siteCode/drive`).
class DriveStorageStatus {
  const DriveStorageStatus({
    required this.configured,
    required this.connected,
    required this.status,
    this.accountEmail,
    this.lastError,
    this.pendingCount = 0,
    this.storedCount = 0,
  });

  factory DriveStorageStatus.fromJson(Map<String, dynamic> json) => DriveStorageStatus(
    configured: json['configured'] == true,
    connected: json['connected'] == true,
    status: (json['status'] ?? 'disconnected').toString(),
    accountEmail: json['account_email']?.toString(),
    lastError: json['last_error']?.toString(),
    pendingCount: (json['pending_count'] as num?)?.toInt() ?? 0,
    storedCount: (json['stored_count'] as num?)?.toInt() ?? 0,
  );

  final bool configured;
  final bool connected;
  final String status;
  final String? accountEmail;
  final String? lastError;
  final int pendingCount;
  final int storedCount;
}

/// Drive uçları için ince HTTP katmanı (belirteç günlüğe yazılmaz; yazma ASLA otomatik yeniden denenmez).
class DriveStorageApi {
  DriveStorageApi({required String baseUrl, http.Client? client})
    : _baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), ''),
      _client = client ?? http.Client();

  final String _baseUrl;
  final http.Client _client;

  Future<Map<String, dynamic>> _call(String method, int siteCode, String tail, String token) async {
    final request = http.Request(method, Uri.parse('$_baseUrl/manager/sites/$siteCode/drive$tail'))
      ..headers.addAll(<String, String>{'Authorization': 'Bearer $token', 'Accept': 'application/json'});
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

  Future<DriveStorageStatus> status(int siteCode, String token) async =>
      DriveStorageStatus.fromJson(await _call('GET', siteCode, '', token));

  Future<String> connectUrl(int siteCode, String token) async =>
      (await _call('POST', siteCode, '/connect', token))['url'].toString();

  Future<void> disconnect(int siteCode, String token) async {
    await _call('DELETE', siteCode, '', token);
  }
}

/// "Dosya Deposu (Google Drive)" kartı (Modüller ekranı, seçili site): bağlı hesap, bekleyen dosya sayısı, bağla / kes.
/// Modül kapalıysa açıklama gösterir; sunucuda Google bilgileri tanımlı değilse bağlama "Yakında…" der. Mevcut belge yüklemeleri bu aşamada değişmez.
class DriveStorageCard extends StatefulWidget {
  const DriveStorageCard({super.key, required this.authService, required this.siteCode, this.api, this.launcher});

  final AuthService authService;
  final int siteCode;
  final DriveStorageApi? api;
  final Future<bool> Function(Uri uri)? launcher;

  /// Yalnız testler: Modüller ekranı gibi kartı içeren ekranların testlerinde gerçek ağ çağrısı yapılmasın diye varsayılan API.
  @visibleForTesting
  static DriveStorageApi? debugApi;

  @override
  State<DriveStorageCard> createState() => _DriveStorageCardState();
}

class _DriveStorageCardState extends State<DriveStorageCard> {
  late final DriveStorageApi _api =
      widget.api ?? DriveStorageCard.debugApi ?? DriveStorageApi(baseUrl: widget.authService.api.baseUrl);
  DriveStorageStatus? _status;
  String? _error;
  bool _moduleOff = false;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(DriveStorageCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.siteCode != widget.siteCode) unawaited(_load());
  }

  String? get _token => widget.authService.session?.token;

  Future<void> _load() async {
    final token = _token;
    final site = widget.siteCode;
    if (token == null) return;
    setState(() {
      _loading = true;
      _error = null;
      _moduleOff = false;
    });
    try {
      final next = await _api.status(site, token);
      if (!mounted || site != widget.siteCode) return;
      setState(() {
        _status = next;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted || site != widget.siteCode) return;
      setState(() {
        _status = null;
        _loading = false;
        _moduleOff = e.code == 'MODULE_DISABLED';
        _error = _moduleOff ? null : e.message;
      });
    }
  }

  Future<void> _connect() async {
    final token = _token;
    if (token == null || _busy) return;
    setState(() => _busy = true);
    try {
      final url = await _api.connectUrl(widget.siteCode, token);
      final open = widget.launcher ?? (Uri uri) => launchUrl(uri, mode: LaunchMode.externalApplication);
      final opened = await open(Uri.parse(url));
      if (mounted && !opened) {
        AppSnack.show(context, 'Tarayıcı açılamadı. Tekrar deneyin.', kind: AppSnackKind.error);
      } else if (mounted) {
        AppSnack.show(context, 'Google onayından sonra uygulamaya dönüp yenileyin.');
      }
    } on ApiException catch (e) {
      if (mounted) {
        AppSnack.show(context, e.code == 'DRIVE_NOT_CONFIGURED' ? 'Google Drive bağlantısı Yakında…' : e.message, kind: AppSnackKind.warning);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    final token = _token;
    if (token == null || _busy) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Drive bağlantısı kesilsin mi?'),
        content: const Text('Yeni dosyalar Drive\'a gönderilemez. Drive\'daki dosyalarınız silinmez.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Bağlantıyı kes')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await _api.disconnect(widget.siteCode, token);
      await _load();
    } on ApiException catch (e) {
      if (mounted) AppSnack.show(context, e.message, kind: AppSnackKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final muted = th.bodyMedium?.copyWith(color: context.palette.textSecondary);
    final status = _status;
    final List<Widget> body;
    if (_loading) {
      body = [Text('Yükleniyor…', style: muted)];
    } else if (_moduleOff) {
      body = [Text('Bu modül sitenizde kapalı. Yukarıdaki listeden "Dosya Deposu (Google Drive)" modülünü açtığınızda Drive\'ı bağlayabilirsiniz.', style: muted)];
    } else if (_error != null) {
      body = [
        InlineNotice(message: _error!, onRetry: _load),
      ];
    } else if (status == null) {
      body = const [];
    } else if (!status.configured) {
      body = [Text('Google Drive bağlantısı Yakında…', style: muted)];
    } else if (status.connected) {
      body = [
        Text('Bağlı hesap: ${status.accountEmail ?? '-'}', style: th.bodyMedium),
        Text('Drive\'a kaydedilen: ${status.storedCount} dosya · Bekleyen: ${status.pendingCount}', style: muted),
        const SizedBox(height: AppSpace.md),
        Align(
          alignment: Alignment.centerLeft,
          child: PrimaryActionButton(label: 'Bağlantıyı kes', variant: AppButtonVariant.outline, expand: false, loading: _busy, onPressed: _busy ? null : _disconnect),
        ),
      ];
    } else {
      body = [
        Text(
          status.status == 'error'
              ? 'Drive bağlantısı koptu${status.lastError == null ? '' : ': ${status.lastError}'}. Yeniden bağlayın; bekleyen dosyalar sonra gönderilir.'
              : 'Sitenin dosyaları sitenin kendi Google Drive hesabında saklanır. Bağlamak için site adına açılmış bir Google hesabı kullanın.',
          style: muted,
        ),
        const SizedBox(height: AppSpace.md),
        Align(
          alignment: Alignment.centerLeft,
          child: PrimaryActionButton(label: 'Google Drive bağla', icon: Icons.add_to_drive_rounded, expand: false, loading: _busy, onPressed: _busy ? null : _connect),
        ),
      ];
    }
    return AppCard(
      key: const ValueKey<String>('drive_storage_card'),
      padding: listCardPadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'Dosya Deposu (Google Drive)', icon: Icons.cloud_rounded),
          const SizedBox(height: AppSpace.sm),
          ...body,
        ],
      ),
    );
  }
}
