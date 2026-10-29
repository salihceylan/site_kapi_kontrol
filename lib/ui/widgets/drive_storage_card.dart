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
import 'package:site_kapi_kontrol/ui/helpers/ui_helpers.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';
import 'package:url_launcher/url_launcher.dart';

/// Sunucunun yönetici uyarısı (`warnings[]`): Drive'a gitmeyi bekleyen / uzun süredir bekleyen dosya, bekleme alanı dolmak üzere / doldu.
/// Hiçbiri dosya silmez ("silmeyi biz yapmayız", karar K6); metin sunucudan Türkçe gelir.
class DriveStorageWarning {
  const DriveStorageWarning({required this.code, required this.message});

  final String code;
  final String message;

  static DriveStorageWarning? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final message = raw['message']?.toString().trim() ?? '';
    if (message.isEmpty) return null;
    return DriveStorageWarning(code: raw['code']?.toString() ?? '', message: message);
  }
}

/// Google hesap kotası özeti (`health.quota`): `state` unknown | ok | near_full (%90+) | full; metin sunucudan Türkçe gelir.
class DriveQuotaInfo {
  const DriveQuotaInfo({required this.state, this.percent, this.label = '', this.unlimited = false});

  static DriveQuotaInfo? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    return DriveQuotaInfo(
      state: raw['state']?.toString() ?? 'unknown',
      percent: (raw['percent'] as num?)?.toInt(),
      label: raw['label']?.toString() ?? '',
      unlimited: raw['unlimited'] == true,
    );
  }

  final String state;
  final int? percent;
  final String label;
  final bool unlimited;
}

/// Drive sağlık özeti (`health`, P2-17): bağlantı durumu (ok | warning | error | disconnected | not_configured), erişim belirteci,
/// son başarılı aktarım, bekleyen kuyruk ve Google kotası. Eski sunucu bu alanı göndermez: `DriveStorageStatus.health` null kalır.
class DriveHealth {
  const DriveHealth({
    required this.state,
    required this.message,
    this.tokenLabel = '',
    this.lastTransferAt,
    this.checkedAt,
    this.pendingCount = 0,
    this.queueLastError,
    this.quota,
  });

  static DriveHealth? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final message = raw['message']?.toString().trim() ?? '';
    if (message.isEmpty) return null;
    final token = raw['token'] is Map ? raw['token'] as Map : const <Object?, Object?>{};
    final queue = raw['queue'] is Map ? raw['queue'] as Map : const <Object?, Object?>{};
    return DriveHealth(
      state: raw['state']?.toString() ?? 'ok',
      message: message,
      tokenLabel: token['label']?.toString() ?? '',
      lastTransferAt: DateTime.tryParse(raw['last_transfer_at']?.toString() ?? ''),
      checkedAt: DateTime.tryParse(token['checked_at']?.toString() ?? ''),
      pendingCount: (queue['pending_count'] as num?)?.toInt() ?? 0,
      queueLastError: queue['last_error']?.toString(),
      quota: DriveQuotaInfo.tryFromJson(raw['quota']),
    );
  }

  final String state;
  final String message;
  final String tokenLabel;
  final DateTime? lastTransferAt;
  final DateTime? checkedAt;
  final int pendingCount;
  final String? queueLastError;
  final DriveQuotaInfo? quota;
}

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
    this.pendingOverdueCount = 0,
    this.warnings = const <DriveStorageWarning>[],
    this.health,
  });

  factory DriveStorageStatus.fromJson(Map<String, dynamic> json) => DriveStorageStatus(
    configured: json['configured'] == true,
    connected: json['connected'] == true,
    status: (json['status'] ?? 'disconnected').toString(),
    accountEmail: json['account_email']?.toString(),
    lastError: json['last_error']?.toString(),
    pendingCount: (json['pending_count'] as num?)?.toInt() ?? 0,
    storedCount: (json['stored_count'] as num?)?.toInt() ?? 0,
    pendingOverdueCount: (json['pending_overdue_count'] as num?)?.toInt() ?? 0,
    // Eski sunucu `warnings` göndermez: liste boş kalır (yeni alanlar isteğe bağlı).
    warnings: <DriveStorageWarning>[
      for (final raw in (json['warnings'] as List? ?? const <Object?>[])) ?DriveStorageWarning.tryFromJson(raw),
    ],
    health: DriveHealth.tryFromJson(json['health']),
  );

  final bool configured;
  final bool connected;
  final String status;
  final String? accountEmail;
  final String? lastError;
  final int pendingCount;
  final int storedCount;

  /// "Uzun süredir bekliyor" uyarısındaki dosya sayısı (silinmez).
  final int pendingOverdueCount;
  final List<DriveStorageWarning> warnings;

  /// Sağlık özeti (bağlantı / belirteç / son aktarım / kuyruk / kota); eski sunucuda null.
  final DriveHealth? health;
}

/// `POST .../drive/flush` sonucu: bu turda gönderilen, hâlâ bekleyen ve uzun süredir bekleyen dosya sayısı.
class DriveFlushResult {
  const DriveFlushResult({this.sent = 0, this.waiting = 0, this.overdue = 0});

  factory DriveFlushResult.fromJson(Map<String, dynamic> json) => DriveFlushResult(
    sent: (json['sent'] as num?)?.toInt() ?? 0,
    waiting: (json['waiting'] as num?)?.toInt() ?? 0,
    overdue: (json['overdue'] as num?)?.toInt() ?? 0,
  );

  final int sent;
  final int waiting;
  final int overdue;
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

  /// Bekleyen dosyaları şimdi göndermeyi dener (artan bekleme süreleri yok sayılır). Dosyalar bu işlemle SİLİNMEZ.
  Future<DriveFlushResult> flush(int siteCode, String token) async =>
      DriveFlushResult.fromJson(await _call('POST', siteCode, '/flush', token));

  /// Sağlık denetimini şimdi çalıştırır (belirteç yenileme + kota okuma) ve güncel durumu döner. Hiçbir dosyaya dokunmaz.
  Future<DriveStorageStatus> healthCheck(int siteCode, String token) async =>
      DriveStorageStatus.fromJson(await _call('POST', siteCode, '/health-check', token));
}

/// Dosya Deposu ekranının "Google Drive" bölümü (seçili site; Belgeler listesiyle AYNI modül, `drive_storage`): bağlı hesap,
/// bekleyen dosya sayısı, bağla / kes. Modül kapalıysa açıklama gösterir; sunucuda Google bilgileri tanımlı değilse bağlama "Yakında…" der. Mevcut belge yüklemeleri bu aşamada değişmez.
class DriveStorageCard extends StatefulWidget {
  const DriveStorageCard({super.key, required this.authService, required this.siteCode, this.api, this.launcher, this.onConnectedChanged});

  /// Durum her yüklendiğinde bildirilir: true = bağlı, false = bağlı değil, null = bilinmiyor (hata / modül kapalı). Belge yükleme düğmesi buna bağlıdır.
  final ValueChanged<bool?>? onConnectedChanged;

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
      widget.onConnectedChanged?.call(next.connected);
    } on ApiException catch (e) {
      if (!mounted || site != widget.siteCode) return;
      setState(() {
        _status = null;
        _loading = false;
        _moduleOff = e.code == 'MODULE_DISABLED';
        _error = _moduleOff ? null : e.message;
      });
      widget.onConnectedChanged?.call(null);
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

  /// Bekleyen dosyaları şimdi göndermeyi dener. Hiçbir dosya silinmez; gitmeyenler beklemeye devam eder.
  Future<void> _flush() async {
    final token = _token;
    if (token == null || _busy) return;
    setState(() => _busy = true);
    try {
      final result = await _api.flush(widget.siteCode, token);
      if (mounted) {
        AppSnack.show(
          context,
          result.waiting == 0
              ? '${result.sent} dosya Drive\'a gönderildi.'
              : '${result.sent} dosya gönderildi, ${result.waiting} dosya bekliyor. Bekleyen dosyalar silinmez.',
          kind: result.waiting == 0 ? AppSnackKind.success : AppSnackKind.warning,
        );
      }
      await _load();
    } on ApiException catch (e) {
      if (mounted) AppSnack.show(context, e.message, kind: AppSnackKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Sağlık denetimini şimdi çalıştırır (belirteç yenileme + kota okuma); güncel durum kartı yeniler. Hiçbir dosya silinmez.
  Future<void> _healthCheck() async {
    final token = _token;
    if (token == null || _busy) return;
    final site = widget.siteCode;
    setState(() => _busy = true);
    try {
      final next = await _api.healthCheck(site, token);
      if (mounted && site == widget.siteCode) setState(() => _status = next);
    } on ApiException catch (e) {
      if (mounted) AppSnack.show(context, e.message, kind: AppSnackKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Sağlık göstergesi (P2-17): durum rozeti, erişim belirteci, son başarılı aktarım, kuyruk, Google kotası (%90'dan itibaren uyarı sunucudan gelir).
  /// Eski sunucuda `health` yoktur: bölüm hiç görünmez.
  List<Widget> _healthSection(DriveStorageStatus status) {
    final health = status.health;
    if (health == null) return const <Widget>[];
    final th = Theme.of(context).textTheme;
    final muted = th.bodySmall?.copyWith(color: context.palette.textSecondary);
    final tone = switch (health.state) {
      'ok' => AppTone.success,
      'warning' => AppTone.warning,
      'error' => AppTone.danger,
      _ => AppTone.neutral,
    };
    final quota = health.quota;
    final percent = quota?.percent;
    return <Widget>[
      Padding(
        padding: const EdgeInsets.only(top: AppSpace.md),
        child: Wrap(children: [StatusChip(key: const ValueKey<String>('drive_health_state'), label: health.message, tone: tone)]),
      ),
      if (health.tokenLabel.isNotEmpty)
        Padding(padding: const EdgeInsets.only(top: AppSpace.xs), child: Text('Erişim: ${health.tokenLabel}', style: muted)),
      Padding(
        padding: const EdgeInsets.only(top: AppSpace.xs),
        child: Text(
          'Son başarılı aktarım: ${health.lastTransferAt == null ? 'henüz yok' : formatDateTime(health.lastTransferAt)}',
          key: const ValueKey<String>('drive_health_last_transfer'),
          style: muted,
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(top: AppSpace.xs),
        child: Text(
          health.pendingCount == 0
              ? 'Kuyruk: boş'
              : 'Kuyruk: ${health.pendingCount} dosya bekliyor${health.queueLastError == null ? '' : '. Son neden: ${health.queueLastError}'}',
          key: const ValueKey<String>('drive_health_queue'),
          style: muted,
        ),
      ),
      if (quota != null && quota.label.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: AppSpace.xs),
          child: Column(
            key: const ValueKey<String>('drive_health_quota'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(quota.label, style: muted),
              if (percent != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpace.xs),
                  child: LinearProgressIndicator(value: (percent.clamp(0, 100)) / 100, minHeight: 6, semanticsLabel: 'Google Drive kotası'),
                ),
            ],
          ),
        ),
      if (health.checkedAt != null)
        Padding(
          padding: const EdgeInsets.only(top: AppSpace.xs),
          child: Text('Son denetim: ${formatDateTime(health.checkedAt)}', style: muted),
        ),
      Padding(
        padding: const EdgeInsets.only(top: AppSpace.sm),
        child: Align(
          alignment: Alignment.centerLeft,
          child: PrimaryActionButton(
            key: const ValueKey<String>('drive_health_check'),
            label: 'Şimdi denetle',
            icon: Icons.health_and_safety_outlined,
            variant: AppButtonVariant.outline,
            expand: false,
            loading: _busy,
            onPressed: _busy ? null : _healthCheck,
          ),
        ),
      ),
    ];
  }

  /// Sunucunun yönetici uyarıları (bekleyen / uzun süredir bekleyen / bekleme alanı dolu): uyarı tonlu kutular + "Şimdi gönder".
  List<Widget> _pendingNotices(DriveStorageStatus status) => <Widget>[
    for (final warning in status.warnings)
      Padding(
        padding: const EdgeInsets.only(top: AppSpace.sm),
        child: InlineNotice(
          key: ValueKey<String>('drive_warning_${warning.code}'),
          message: warning.message,
          tone: AppTone.warning,
        ),
      ),
    if (status.connected && status.pendingCount > 0)
      Padding(
        padding: const EdgeInsets.only(top: AppSpace.sm),
        child: Align(
          alignment: Alignment.centerLeft,
          child: PrimaryActionButton(
            label: 'Bekleyenleri şimdi gönder',
            icon: Icons.cloud_upload_outlined,
            variant: AppButtonVariant.outline,
            expand: false,
            loading: _busy,
            onPressed: _busy ? null : _flush,
          ),
        ),
      ),
  ];

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final muted = th.bodyMedium?.copyWith(color: context.palette.textSecondary);
    final status = _status;
    final List<Widget> body;
    if (_loading) {
      body = [Text('Yükleniyor…', style: muted)];
    } else if (_moduleOff) {
      body = [Text('Dosya Deposu modülü bu sitede kapalı. Modül açıldığında Google Drive\'ı buradan bağlayabilirsiniz.', style: muted)];
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
        ..._healthSection(status),
        ..._pendingNotices(status),
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
        if (status.status == 'error') ..._healthSection(status),
        ..._pendingNotices(status),
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
          const SectionHeader(title: 'Google Drive', icon: Icons.cloud_rounded),
          const SizedBox(height: AppSpace.sm),
          ...body,
        ],
      ),
    );
  }
}
