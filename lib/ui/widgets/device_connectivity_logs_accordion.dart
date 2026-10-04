import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/device_connectivity_log.dart';
import 'package:site_kapi_kontrol/models/device_record.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/empty_state.dart';
import 'package:site_kapi_kontrol/ui/design/icon_orb.dart';
import 'package:site_kapi_kontrol/ui/design/motion_widgets.dart';
import 'package:site_kapi_kontrol/ui/design/skeleton.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/ui_helpers.dart';

/// "Bağlantı & Kopma Geçmişi" akordiyonu (şirket cihaz kartının içinde).
///
/// Görünüm: soluk yüzeyli ([AppPalette.surfaceMuted]) yuvarlak panel (kart içinde kart: ek gölge yok),
/// başlıkta cilalı ton küresi ([IconOrb]: çevrimiçi success, çevrimdışı warning), çevrimiçi/çevrimdışı
/// özeti ton kutusu + küre, kopma günlükleri satır kartı (küre + [StatusChip] süre rozeti); ilk açılışta
/// satırlar kademeli belirir ([StaggeredEntry]), ilk yükleme iskelet ([SkeletonBox]), hata
/// [InlineNotice], boş durum [EmptyState]. Renkler yalnız palet/ton belirteçlerinden gelir; açık ve koyu
/// temada aynı kod çalışır. Sayfalama/yenileme mantığı ve metinler AYNIDIR.
class DeviceConnectivityLogsAccordion extends StatefulWidget {
  const DeviceConnectivityLogsAccordion({
    super.key,
    required this.device,
    required this.authService,
  });

  final DeviceRecord device;
  final AuthService authService;

  @override
  State<DeviceConnectivityLogsAccordion> createState() =>
      _DeviceConnectivityLogsAccordionState();
}

class _DeviceConnectivityLogsAccordionState
    extends State<DeviceConnectivityLogsAccordion> {
  bool _isExpanded = false;
  bool _isLoading = false;
  String? _errorMessage;
  DeviceConnectivityReport? _report;
  int _currentPage = 1;
  int _requestToken = 0;
  static const int _pageSize = 10;

  /// Zaman damgası/sayı metinlerinde sabit genişlikli rakamlar (satırlar arası hizalı).
  static const List<FontFeature> _tabular = <FontFeature>[
    FontFeature.tabularFigures(),
  ];

  @override
  void didUpdateWidget(covariant DeviceConnectivityLogsAccordion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.device.deviceUid != widget.device.deviceUid) {
      setState(() {
        _report = null;
        _currentPage = 1;
        _errorMessage = null;
      });
      if (_isExpanded) {
        _loadLogs(page: 1);
      }
    }
  }

  Future<void> _loadLogs({int? page}) async {
    final currentToken = ++_requestToken;
    final targetPage = page ?? _currentPage;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final (result, error) = await widget.authService.getDeviceConnectivityLogs(
        deviceUid: widget.device.deviceUid,
        page: targetPage,
        pageSize: _pageSize,
      );

      if (!mounted || currentToken != _requestToken) return;

      if (result != null) {
        setState(() {
          _report = result;
          _currentPage = targetPage;
          _isLoading = false;
          _errorMessage = null;
        });
      } else {
        setState(() {
          _errorMessage = error ?? 'Bağlantı logları yüklenirken bir hata oluştu.';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted || currentToken != _requestToken) return;
      setState(() {
        _errorMessage = 'Hata: $e';
        _isLoading = false;
      });
    }
  }

  void _toggleExpanded() {
    setState(() {
      _isExpanded = !_isExpanded;
    });
    if (_isExpanded && _report == null && !_isLoading) {
      _loadLogs(page: 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isOnline = widget.device.mqttConnected == true;
    final radius = BorderRadius.circular(AppRadius.md);
    final uptime = _report?.currentOnlineDurationText;

    // Material: dokunma dalgası (InkWell) yüzey renginin ÜSTÜNDE görünür; yuvarlak köşeye kırpılır.
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: p.surfaceMuted,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: p.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Başlık Çubuğu / Akordeon Tetikleyici
            InkWell(
              onTap: _toggleExpanded,
              child: Padding(
                padding: const EdgeInsets.all(AppSpace.md),
                child: _buildHeaderRow(
                  context,
                  tone: isOnline ? AppTone.success : AppTone.warning,
                  uptime: uptime,
                ),
              ),
            ),

            // Açılır İçerik
            if (_isExpanded) ...[
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: AppSpace.md),
                child: Divider(height: 1),
              ),
              Padding(
                padding: const EdgeInsets.all(AppSpace.md),
                child: _buildBody(context),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// [text]'in [style] ve geçerli yazı ölçeğiyle tek satırdaki genişliği (dp).
  static double _measure(BuildContext context, String text, TextStyle? style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  /// Başlık satırının sabit genişlikleri: küre 36 + boşluk 12 (sol); boşluk 4 + ok 22 (sağ).
  static const double _headerOrb = 36;
  static const double _headerChevron = 22;

  /// Başlık satırı: küre + başlık (+ canlı uptime) + "Gizle / Logları Gör" ipucu hapı + ok.
  ///
  /// Hap başlığın YANINDA durur; başlığa kalan genişlik en uzun sözcüğün (~1,4 katı) altına düşecekse
  /// (büyük yazı / dar ekran) hap başlığın ALTINA, sola hizalı iner: başlık sözcük ortasından bölünmez.
  /// Karar genişlik ve yazı ölçeği değişince yeniden verilir (gerçek ölçümle; tahminle değil).
  Widget _buildHeaderRow(
    BuildContext context, {
    required AppTone tone,
    required String? uptime,
  }) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final pillStyle = th.bodySmall?.copyWith(
      fontWeight: FontWeight.w700,
      color: p.textSecondary,
    );
    final pill = DecoratedBox(
      decoration: BoxDecoration(
        color: p.border,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.sm,
          vertical: AppSpace.xs,
        ),
        child: Text(
          _isExpanded ? 'Gizle' : 'Logları Gör',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: pillStyle,
        ),
      ),
    );
    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Bağlantı & Kopma Geçmişi', style: th.titleMedium),
        if (uptime != null) ...[
          const SizedBox(height: AppSpace.xs / 2),
          Text(
            'Aktif Uptime: $uptime',
            style: th.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: AppTone.success.ink(p),
              fontFeatures: _tabular,
            ),
          ),
        ],
      ],
    );
    final chevron = AnimatedRotation(
      turns: _isExpanded ? 0.5 : 0.0,
      duration: AppMotion.of(context, AppMotion.base),
      curve: AppMotion.standard,
      child: Icon(
        Icons.keyboard_arrow_down_rounded,
        size: _headerChevron,
        color: p.textMuted,
      ),
    );
    final orb = IconOrb(
      icon: Icons.history_toggle_off_rounded,
      tone: tone,
      size: _headerOrb,
      shape: IconOrbShape.squircle,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // Hap genişliği: iki etiketten uzun olanı (durum değişince yerleşim oynamasın) + yatay dolgu.
        final pillWidth =
            math.max(
              _measure(context, 'Gizle', pillStyle),
              _measure(context, 'Logları Gör', pillStyle),
            ) +
            2 * AppSpace.sm;
        final titleRoom =
            constraints.maxWidth -
            _headerOrb -
            AppSpace.md -
            AppSpace.sm -
            pillWidth -
            AppSpace.xs -
            _headerChevron;
        final longestWord = math.max(
          _measure(context, 'Bağlantı', th.titleMedium),
          _measure(context, 'Geçmişi', th.titleMedium),
        );
        final stacked = titleRoom < longestWord * 1.4;
        return Row(
          crossAxisAlignment: stacked
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.center,
          children: [
            orb,
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: stacked
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        titleBlock,
                        const SizedBox(height: AppSpace.sm),
                        pill,
                      ],
                    )
                  : titleBlock,
            ),
            if (!stacked) ...[
              const SizedBox(width: AppSpace.sm),
              // Flexible: büyük yazıda ipucu hapı kalan genişliği aşmaz (üç nokta ile kısalır).
              Flexible(child: pill),
            ],
            const SizedBox(width: AppSpace.xs),
            // Dar düzende ok, küreyle aynı hizada (üstte) durur.
            stacked
                ? Padding(
                    padding: EdgeInsets.only(
                      top: (_headerOrb - _headerChevron) / 2,
                    ),
                    child: chevron,
                  )
                : chevron,
          ],
        );
      },
    );
  }

  Widget _buildBody(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final report = _report;

    // İlk yükleme: iskelet satırlar (yenilemede mevcut liste kalır).
    if (_isLoading && report == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpace.sm),
        child: ShimmerScope(
          child: Column(
            children: [
              _LogSkeletonRow(),
              _LogSkeletonRow(),
              _LogSkeletonRow(),
            ],
          ),
        ),
      );
    }

    if (_errorMessage != null && report == null) {
      return InlineNotice(
        message: _errorMessage!,
        onRetry: () => _loadLogs(page: 1),
      );
    }

    final logs = report?.logs ?? const <DeviceConnectivityLogRecord>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Canlı Uptime Özeti
        _buildUptimeBanner(context),
        const SizedBox(height: AppSpace.md),

        // Log Başlığı ve Yenile Butonu
        Row(
          children: [
            // Expanded: başlık büyük yazıda sarar; yenile düğmesi sağda kalır.
            Expanded(
              child: Text(
                'Kopma / Çevrimdışı Logları',
                style: th.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: p.textSecondary,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Yenile',
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              onPressed: _isLoading ? null : () => _loadLogs(page: _currentPage),
              icon: _isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(Icons.refresh_rounded, size: 20, color: p.textSecondary),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.sm),

        // Log Listesi
        if (logs.isEmpty)
          DecoratedBox(
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: p.border),
            ),
            child: const EmptyState.compact(
              icon: Icons.verified_rounded,
              tone: AppTone.success,
              title: 'Kayıtlı kopma logu bulunmuyor.',
              message: 'Cihaz bağlantısı stabil ve kesintisiz çalışıyor.',
            ),
          )
        else
          for (var i = 0; i < logs.length; i++)
            StaggeredEntry(
              index: i,
              child: Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.sm),
                child: _buildLogItem(context, logs[i]),
              ),
            ),

        // Sayfalama Çubuğu
        if (report != null && report.totalPages > 1) ...[
          const SizedBox(height: AppSpace.xs),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  'Sayfa ${report.page} / ${report.totalPages} (Toplam ${report.total})',
                  style: th.bodySmall?.copyWith(fontFeatures: _tabular),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                    onPressed: (report.page > 1 && !_isLoading)
                        ? () => _loadLogs(page: report.page - 1)
                        : null,
                    icon: const Icon(Icons.chevron_left_rounded, size: 22),
                  ),
                  IconButton(
                    constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                    onPressed: (report.page < report.totalPages && !_isLoading)
                        ? () => _loadLogs(page: report.page + 1)
                        : null,
                    icon: const Icon(Icons.chevron_right_rounded, size: 22),
                  ),
                ],
              ),
            ],
          ),
        ],
      ],
    );
  }

  /// Çevrimiçi/çevrimdışı özet kutusu: ton zemini + ton kenarı + cilalı küre + `ink` metin (>= 4,5:1).
  Widget _buildUptimeBanner(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final isOnline = _report?.isOnline ?? (widget.device.mqttConnected == true);
    final tone = isOnline ? AppTone.success : AppTone.danger;
    final ink = tone.ink(p);

    final String title;
    final String subtitle;
    if (isOnline) {
      final uptimeText = _report?.currentOnlineDurationText ?? 'Hesaplanıyor...';
      final onlineSinceText = _report?.currentOnlineSince != null
          ? formatDateTime(_report!.currentOnlineSince)
          : 'Bilinmiyor';
      title = '🟢 Kesintisiz Çevrimiçi (Uptime): $uptimeText';
      subtitle = 'Bağlantı başlangıcı: $onlineSinceText';
    } else {
      final lastOfflineText = _report?.lastOfflineAt != null
          ? formatDateTime(_report!.lastOfflineAt)
          : (widget.device.lastSeenAt != null
                ? formatDateTime(widget.device.lastSeenAt)
                : 'Bilinmiyor');
      title = '🔴 Cihaz Şu An Çevrimdışı';
      subtitle = 'Son kopma: $lastOfflineText';
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Color.alphaBlend(tone.tint(p), p.surface),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: tone.hue.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.md),
        child: Row(
          // Çok satırlı metinde küre üstte durur (büyük yazıda aşağı kaymaz).
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconOrb(
              icon: isOnline ? Icons.wifi_rounded : Icons.wifi_off_rounded,
              tone: tone,
              size: 36,
              glow: true,
            ),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: th.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: ink,
                    ),
                  ),
                  const SizedBox(height: AppSpace.xs / 2),
                  Text(
                    subtitle,
                    style: th.bodySmall?.copyWith(color: ink, fontFeatures: _tabular),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogItem(BuildContext context, DeviceConnectivityLogRecord log) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final offlineTimeText = formatDateTimeOrUnknown(log.offlineAt ?? log.createdAt);
    final signalText = log.wifiSignalPercent != null
        ? '%${log.wifiSignalPercent}${log.wifiRssi != null ? " (${log.wifiRssi} dBm)" : ""}'
        : '-';
    final detailStyle = th.bodySmall?.copyWith(fontFeatures: _tabular);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: p.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const IconOrb(
                  icon: Icons.cloud_off_rounded,
                  tone: AppTone.danger,
                  size: 32,
                ),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Kopma: $offlineTimeText',
                        style: th.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: p.text,
                          fontFeatures: _tabular,
                        ),
                      ),
                      Text(log.reason, style: th.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.sm),
            Padding(
              // Küre (32) + boşluk: ayrıntılar başlık metniyle aynı hizada başlar.
              padding: const EdgeInsets.only(left: 32 + AppSpace.md),
              child: Wrap(
                spacing: AppSpace.md,
                runSpacing: AppSpace.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  // Kopma süresi: ayrıntı satırının başında rozet (başlık satırını daraltmaz; dar
                  // ekranda/büyük yazıda sarar, rozet kendi etiketini üç nokta ile kısaltabilir).
                  StatusChip(
                    label: log.durationText,
                    tone: AppTone.primary,
                    icon: Icons.timer_outlined,
                  ),
                  if (log.onlineAt != null)
                    Text(
                      'Bağlantı: ${formatDateTime(log.onlineAt)}',
                      style: detailStyle,
                    ),
                  if (log.wifiSignalPercent != null || log.wifiRssi != null)
                    Text('Sinyal: $signalText', style: detailStyle),
                  if (log.localIp != null)
                    Text('IP: ${log.localIp}', style: detailStyle),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Günlük satırı iskeleti (küre + iki satır + süre rozeti): ilk yükleme sırasında 3 adet gösterilir.
class _LogSkeletonRow extends StatelessWidget {
  const _LogSkeletonRow();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(bottom: AppSpace.md),
      child: Row(
        children: [
          SkeletonBox(width: 32, height: 32, radius: AppRadius.pill),
          SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FractionallySizedBox(
                  widthFactor: 0.6,
                  child: SkeletonBox(height: 12),
                ),
                SizedBox(height: AppSpace.xs),
                FractionallySizedBox(
                  widthFactor: 0.4,
                  child: SkeletonBox(height: 10),
                ),
              ],
            ),
          ),
          SizedBox(width: AppSpace.sm),
          SkeletonBox(width: 56, height: 24, radius: AppRadius.pill),
        ],
      ),
    );
  }
}
