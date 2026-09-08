import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/device_connectivity_log.dart';
import 'package:site_kapi_kontrol/models/device_record.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/styles/app_colors.dart';
import 'package:site_kapi_kontrol/ui/helpers/ui_helpers.dart';

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isOnline = widget.device.mqttConnected == true;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A).withValues(alpha: 0.7) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0x20FFFFFF) : const Color(0xFFE2E8F0),
          width: 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Başlık Çubuğu / Akordeon Tetikleyici
          InkWell(
            onTap: _toggleExpanded,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    Icons.history_toggle_off_rounded,
                    size: 20,
                    color: isOnline ? AppColors.emeraldLight : AppColors.amberLight,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Bağlantı & Kopma Geçmişi',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : AppColors.textDark,
                          ),
                        ),
                        if (_report?.currentOnlineDurationText != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Aktif Uptime: ${_report!.currentOnlineDurationText}',
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.emeraldLight,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0x15FFFFFF)
                          : const Color(0xFFE2E8F0).withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _isExpanded ? 'Gizle' : 'Logları Gör',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: isDark ? AppColors.textMutedLight : AppColors.textDarkSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  AnimatedRotation(
                    turns: _isExpanded ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 20,
                      color: isDark ? AppColors.textMutedLight : AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Açılır İçerik
          if (_isExpanded) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Divider(
                color: isDark ? const Color(0x1AFFFFFF) : const Color(0x150F172A),
                height: 1,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_isLoading && _report == null) ...[
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: CircularProgressIndicator(),
                      ),
                    ),
                  ] else if (_errorMessage != null && _report == null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.rose.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.rose.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded, color: AppColors.roseLight, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: const TextStyle(color: AppColors.roseLight, fontSize: 12),
                            ),
                          ),
                          TextButton(
                            onPressed: () => _loadLogs(page: 1),
                            child: const Text('Tekrar Dene', style: TextStyle(fontSize: 12)),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    // Canlı Uptime Özeti
                    _buildUptimeBanner(context),
                    const SizedBox(height: 12),

                    // Log Başlığı ve Yenile Butonu
                    Row(
                      children: [
                        Text(
                          'Kopma / Çevrimdışı Logları',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: isDark ? AppColors.textMutedLight : AppColors.textDarkSecondary,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          iconSize: 18,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          tooltip: 'Yenile',
                          onPressed: _isLoading ? null : () => _loadLogs(page: _currentPage),
                          icon: _isLoading
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.refresh_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Log Listesi
                    if (_report == null || _report!.logs.isEmpty) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0x10FFFFFF) : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDark ? const Color(0x15FFFFFF) : const Color(0xFFE2E8F0),
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              Icons.verified_rounded,
                              size: 28,
                              color: isDark ? AppColors.emeraldLight : AppColors.emerald,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Kayıtlı kopma logu bulunmuyor.',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white70 : AppColors.textDark,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Cihaz bağlantısı stabil ve kesintisiz çalışıyor.',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: isDark ? AppColors.textMutedLight : AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      for (final log in _report!.logs) ...[
                        _buildLogItem(context, log),
                        const SizedBox(height: 8),
                      ],
                    ],

                    // Sayfalama Çubuğu
                    if (_report != null && _report!.totalPages > 1) ...[
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Sayfa ${_report!.page} / ${_report!.totalPages} (Toplam ${_report!.total})',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: isDark ? AppColors.textMutedLight : AppColors.textMuted,
                            ),
                          ),
                          Row(
                            children: [
                              IconButton(
                                iconSize: 18,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: (_report!.page > 1 && !_isLoading)
                                    ? () => _loadLogs(page: _report!.page - 1)
                                    : null,
                                icon: const Icon(Icons.chevron_left_rounded),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                iconSize: 18,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: (_report!.page < _report!.totalPages && !_isLoading)
                                    ? () => _loadLogs(page: _report!.page + 1)
                                    : null,
                                icon: const Icon(Icons.chevron_right_rounded),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildUptimeBanner(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isOnline = _report?.isOnline ?? (widget.device.mqttConnected == true);

    if (isOnline) {
      final uptimeText = _report?.currentOnlineDurationText ?? 'Hesaplanıyor...';
      final onlineSinceText = _report?.currentOnlineSince != null
          ? formatDateTime(_report!.currentOnlineSince)
          : 'Bilinmiyor';

      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.emerald.withValues(alpha: isDark ? 0.15 : 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.emerald.withValues(alpha: 0.35),
            width: 1.0,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.emerald.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.wifi_rounded, color: AppColors.emeraldLight, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '🟢 Kesintisiz Çevrimiçi (Uptime): $uptimeText',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12.5,
                      color: isDark ? AppColors.emeraldLight : const Color(0xFF065F46),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Bağlantı başlangıcı: $onlineSinceText',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? const Color(0xFFA7F3D0) : const Color(0xFF047857),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    } else {
      final lastOfflineText = _report?.lastOfflineAt != null
          ? formatDateTime(_report!.lastOfflineAt)
          : (widget.device.lastSeenAt != null ? formatDateTime(widget.device.lastSeenAt) : 'Bilinmiyor');

      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.rose.withValues(alpha: isDark ? 0.15 : 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.rose.withValues(alpha: 0.35),
            width: 1.0,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.rose.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.wifi_off_rounded, color: AppColors.roseLight, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '🔴 Cihaz Şu An Çevrimdışı',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12.5,
                      color: isDark ? AppColors.roseLight : const Color(0xFF991B1B),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Son kopma: $lastOfflineText',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? const Color(0xFFFECDD3) : const Color(0xFFB91C1C),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildLogItem(BuildContext context, DeviceConnectivityLogRecord log) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final offlineTimeText = formatDateTime(log.offlineAt ?? log.createdAt);
    final signalText = log.wifiSignalPercent != null
        ? '%${log.wifiSignalPercent}${log.wifiRssi != null ? " (${log.wifiRssi} dBm)" : ""}'
        : '-';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B).withValues(alpha: 0.7) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0x1FFFFFFF) : const Color(0xFFE2E8F0),
          width: 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.rose.withValues(alpha: isDark ? 0.2 : 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.cloud_off_rounded,
                  size: 16,
                  color: AppColors.roseLight,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Kopma: $offlineTimeText',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : AppColors.textDark,
                      ),
                    ),
                    Text(
                      log.reason,
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? AppColors.textMutedLight : AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: isDark ? 0.2 : 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  log.durationText,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: isDark ? AppColors.accentLight : AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 32),
            child: Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                if (log.onlineAt != null)
                  Text(
                    'Bağlantı: ${formatDateTime(log.onlineAt)}',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? AppColors.textMutedLight : AppColors.textMuted,
                    ),
                  ),
                if (log.wifiSignalPercent != null || log.wifiRssi != null)
                  Text(
                    'Sinyal: $signalText',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? AppColors.textMutedLight : AppColors.textMuted,
                    ),
                  ),
                if (log.localIp != null)
                  Text(
                    'IP: ${log.localIp}',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? AppColors.textMutedLight : AppColors.textMuted,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
