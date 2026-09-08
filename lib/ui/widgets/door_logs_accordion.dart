import 'package:flutter/material.dart';
import '../../models/door_access_log_record.dart';
import '../../models/door_record.dart';
import '../../models/site_record.dart';
import '../../services/auth_service.dart';
import '../../styles/app_colors.dart';
import '../helpers/ui_helpers.dart';

class DoorLogsAccordion extends StatefulWidget {
  const DoorLogsAccordion({
    super.key,
    required this.selectedSite,
    required this.selectedDoor,
    required this.authService,
    this.onDownloadPdf,
  });

  final SiteRecord? selectedSite;
  final DoorRecord? selectedDoor;
  final AuthService? authService;
  final VoidCallback? onDownloadPdf;

  @override
  State<DoorLogsAccordion> createState() => _DoorLogsAccordionState();
}

class _DoorLogsAccordionState extends State<DoorLogsAccordion> {
  bool _isExpanded = false;
  bool _isLoading = false;
  String? _errorMessage;
  DoorAccessLogPage? _logPage;
  int _currentPage = 1;
  int _requestToken = 0;
  static const int _pageSize = 10;

  @override
  void didUpdateWidget(covariant DoorLogsAccordion oldWidget) {
    super.didUpdateWidget(oldWidget);
    final doorChanged = oldWidget.selectedDoor?.id != widget.selectedDoor?.id;
    final siteChanged = oldWidget.selectedSite?.id != widget.selectedSite?.id;

    if (doorChanged || siteChanged) {
      setState(() {
        _logPage = null;
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
    final service = widget.authService;
    if (service == null) {
      setState(() {
        _errorMessage = 'Giriş oturumu bulunamadı.';
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final now = DateTime.now();
      final sevenDaysAgo = now.subtract(const Duration(days: 7));

      final (result, error) = await service.listDoorAccessLogs(
        siteCode: widget.selectedSite?.id,
        doorId: widget.selectedDoor?.id,
        startDate: sevenDaysAgo,
        endDate: now,
        page: targetPage,
        pageSize: _pageSize,
      );

      if (!mounted || currentToken != _requestToken) return;

      if (result != null) {
        setState(() {
          _logPage = result;
          _currentPage = targetPage;
          _isLoading = false;
          _errorMessage = null;
        });
      } else {
        setState(() {
          _errorMessage = error ?? 'Loglar yüklenirken bir hata oluştu.';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted || currentToken != _requestToken) return;
      setState(() {
        _errorMessage = 'Bağlantı hatası: $e';
        _isLoading = false;
      });
    }
  }

  void _toggleExpand() {
    setState(() {
      _isExpanded = !_isExpanded;
    });
    if (_isExpanded && _logPage == null && !_isLoading) {
      _loadLogs(page: 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final doorName = widget.selectedDoor?.doorName ?? widget.selectedSite?.name ?? 'Kapı';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Açılır / Kapanır Başlık Butonu
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: _toggleExpand,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              foregroundColor: isDark ? const Color(0xFF60A5FA) : const Color(0xFF0284C7),
              side: BorderSide(
                color: isDark
                    ? (_isExpanded ? const Color(0xFF3B82F6) : const Color(0x4060A5FA))
                    : (_isExpanded ? const Color(0xFF0284C7) : const Color(0xFFBAE6FD)),
                width: _isExpanded ? 1.5 : 1.0,
              ),
              backgroundColor: _isExpanded
                  ? (isDark ? const Color(0x1A3B82F6) : const Color(0x140284C7))
                  : Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _isExpanded ? Icons.folder_open_rounded : Icons.history_rounded,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '📊 $doorName Geçiş Logları',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_logPage != null && !_isLoading) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0x333B82F6) : const Color(0x220284C7),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${_logPage!.total}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isDark ? const Color(0xFF93C5FD) : const Color(0xFF0369A1),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Icon(
                  _isExpanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 22,
                ),
              ],
            ),
          ),
        ),

        // Aşağıya Doğru Açılan Panel (AnimatedCrossFade)
        AnimatedCrossFade(
          firstChild: const SizedBox(width: double.infinity, height: 0),
          secondChild: Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF0F172A).withValues(alpha: 0.8)
                  : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDark ? const Color(0x2EFFFFFF) : const Color(0xFFE2E8F0),
                width: 1.0,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeaderBar(context, isDark),
                const SizedBox(height: 8),
                _buildContent(context, isDark),
                if (_logPage != null && _logPage!.logs.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _buildPaginationBar(context, isDark),
                ],
              ],
            ),
          ),
          crossFadeState: _isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 260),
        ),
      ],
    );
  }

  Widget _buildHeaderBar(BuildContext context, bool isDark) {
    final total = _logPage?.total ?? 0;

    return Row(
      children: [
        Icon(
          Icons.access_time_rounded,
          size: 15,
          color: isDark ? AppColors.textMutedLight : AppColors.textMuted,
        ),
        const SizedBox(width: 6),
        Text(
          _logPage != null
              ? 'Toplam $total geçiş (Son 7 Gün)'
              : 'Haftalık Geçiş Geçmişi',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isDark ? AppColors.textMutedLight : AppColors.textMuted,
          ),
        ),
        const Spacer(),
        if (widget.onDownloadPdf != null)
          Tooltip(
            message: 'PDF Raporu İndir',
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: widget.onDownloadPdf,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(
                  Icons.picture_as_pdf_outlined,
                  size: 18,
                  color: isDark ? const Color(0xFF93C5FD) : AppColors.primary,
                ),
              ),
            ),
          ),
        Tooltip(
          message: 'Yenile',
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: _isLoading ? null : () => _loadLogs(page: _currentPage),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: _isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      Icons.refresh_rounded,
                      size: 18,
                      color: isDark ? const Color(0xFFCBD5E1) : AppColors.textDarkSecondary,
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContent(BuildContext context, bool isDark) {
    if (_isLoading && _logPage == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Column(
            children: [
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(height: 10),
              Text(
                'Geçiş logları getiriliyor...',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? AppColors.textMutedLight : AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_errorMessage != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        child: Column(
          children: [
            Icon(Icons.error_outline_rounded, color: AppColors.roseLight, size: 28),
            const SizedBox(height: 6),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: AppColors.roseLight),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _loadLogs(page: _currentPage),
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Tekrar Dene', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      );
    }

    final logs = _logPage?.logs ?? [];
    if (logs.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: Column(
            children: [
              Icon(
                Icons.history_toggle_off_rounded,
                size: 32,
                color: isDark ? const Color(0xFF475569) : const Color(0xFF94A3B8),
              ),
              const SizedBox(height: 6),
              Text(
                'Son 7 güne ait kapı geçiş kaydı bulunamadı.',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? AppColors.textMutedLight : AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        for (final log in logs) _buildLogRow(context, log, isDark),
      ],
    );
  }

  Widget _buildLogRow(BuildContext context, DoorAccessLogRecord log, bool isDark) {
    final (triggerIcon, triggerColor) = _getTriggerInfo(log.triggerType);

    final roleLabel = log.userRoleDisplay;
    final aptText = log.apartmentLabel?.trim();
    final String aptLabel;
    if (aptText == null || aptText.isEmpty) {
      aptLabel = '';
    } else if (aptText.toLowerCase().startsWith('d:') ||
        aptText.toLowerCase().startsWith('daire') ||
        aptText.toLowerCase().contains('blok')) {
      aptLabel = ' • $aptText';
    } else {
      aptLabel = ' • D:$aptText';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? const Color(0x1FFFFFFF) : const Color(0xFFE2E8F0),
          width: 0.8,
        ),
      ),
      child: Row(
        children: [
          // Yöntem İkon Rozeti
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: triggerColor.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(triggerIcon, size: 16, color: triggerColor),
          ),
          const SizedBox(width: 10),

          // Kullanıcı Adı ve Daire/Rol Bilgisi
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        log.userName,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : AppColors.textDark,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: triggerColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        log.triggerTypeDisplay,
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                          color: triggerColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '$roleLabel$aptLabel',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? AppColors.textMutedLight : AppColors.textMuted,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Tarih & Saat
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formatDateTime(log.openedAt),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isDark ? const Color(0xFFCBD5E1) : AppColors.textDarkSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPaginationBar(BuildContext context, bool isDark) {
    final page = _currentPage;
    final totalPages = _logPage?.totalPages ?? 1;
    final hasPrev = page > 1 && !_isLoading;
    final hasNext = page < totalPages && !_isLoading;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: isDark ? const Color(0x1FFFFFFF) : const Color(0x0A000000),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Önceki Sayfa
          TextButton.icon(
            onPressed: hasPrev ? () => _loadLogs(page: page - 1) : null,
            icon: const Icon(Icons.chevron_left_rounded, size: 18),
            label: const Text('Önceki', style: TextStyle(fontSize: 11.5)),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: const Size(60, 32),
              foregroundColor: isDark ? const Color(0xFF93C5FD) : AppColors.primary,
              disabledForegroundColor: isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1),
            ),
          ),

          // Sayfa Numarası
          Text(
            'Sayfa $page / $totalPages',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : AppColors.textDark,
            ),
          ),

          // Sonraki Sayfa
          TextButton.icon(
            onPressed: hasNext ? () => _loadLogs(page: page + 1) : null,
            iconAlignment: IconAlignment.end,
            icon: const Icon(Icons.chevron_right_rounded, size: 18),
            label: const Text('Sonraki', style: TextStyle(fontSize: 11.5)),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: const Size(60, 32),
              foregroundColor: isDark ? const Color(0xFF93C5FD) : AppColors.primary,
              disabledForegroundColor: isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1),
            ),
          ),
        ],
      ),
    );
  }

  (IconData, Color) _getTriggerInfo(String triggerType) {
    switch (triggerType) {
      case 'voice':
        return (Icons.mic_rounded, const Color(0xFFA855F7));
      case 'local_wifi':
        return (Icons.wifi_rounded, const Color(0xFFF59E0B));
      case 'guest_pass':
        return (Icons.qr_code_2_rounded, const Color(0xFF10B981));
      case 'offline_sync':
        return (Icons.sync_rounded, const Color(0xFF64748B));
      case 'cloud_app':
      default:
        return (Icons.cloud_done_rounded, const Color(0xFF3B82F6));
    }
  }
}

