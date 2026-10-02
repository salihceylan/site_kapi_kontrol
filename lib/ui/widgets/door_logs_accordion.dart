import 'package:flutter/material.dart';
import '../../models/door_access_log_record.dart';
import '../../models/door_record.dart';
import '../../models/site_record.dart';
import '../../services/auth_service.dart';
import '../design/app_card.dart';
import '../design/empty_state.dart';
import '../design/motion_widgets.dart';
import '../design/skeleton.dart';
import '../design/tokens.dart';


class DoorLogsAccordion extends StatefulWidget {
  const DoorLogsAccordion({
    super.key,
    required this.selectedSite,
    required this.selectedDoor,
    required this.authService,
    this.onDownloadPdf,
    this.isOpeningDoor = false,
  });

  final SiteRecord? selectedSite;
  final DoorRecord? selectedDoor;
  final AuthService? authService;
  final VoidCallback? onDownloadPdf;
  final bool isOpeningDoor;

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
    final doorOpened = oldWidget.isOpeningDoor && !widget.isOpeningDoor;

    if (doorChanged || siteChanged) {
      setState(() {
        _logPage = null;
        _currentPage = 1;
        _errorMessage = null;
      });
      if (_isExpanded) {
        _loadLogs(page: 1);
      }
    } else if (doorOpened) {
      if (_isExpanded) {
        _loadLogs(page: 1);
      } else {
        _logPage = null;
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
      final (result, error) = await service.listDoorAccessLogs(
        siteCode: widget.selectedSite?.id,
        doorId: widget.selectedDoor?.id,
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
    if (_isExpanded) {
      _loadLogs(page: 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    const tone = AppTone.info;
    final ink = tone.ink(p);
    final doorName = widget.selectedDoor?.doorName ?? widget.selectedSite?.name ?? 'Kapı';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Açılır / Kapanır Başlık Butonu
        OutlinedButton(
          onPressed: _toggleExpand,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.lg,
              vertical: AppSpace.md,
            ),
            foregroundColor: ink,
            side: BorderSide(
              color: tone.hue.withValues(alpha: _isExpanded ? 0.8 : 0.4),
              width: _isExpanded ? 1.5 : 1.0,
            ),
            backgroundColor: _isExpanded ? tone.tint(p) : Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
          ),
          child: Row(
            children: [
              Icon(
                _isExpanded ? Icons.folder_open_rounded : Icons.history_rounded,
                size: 20,
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Text(
                  '📊 $doorName Geçiş Logları',
                  style: th.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: ink,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_logPage != null && !_isLoading) ...[
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: tone.tint(p),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpace.sm,
                      vertical: AppSpace.xs,
                    ),
                    child: AnimatedCount(
                      value: _logPage!.total,
                      style: th.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: ink,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
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

        // Aşağıya Doğru Açılan Panel (AnimatedCrossFade)
        AnimatedCrossFade(
          firstChild: const SizedBox(width: double.infinity, height: 0),
          secondChild: Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: AppSpace.sm),
            padding: const EdgeInsets.all(AppSpace.md),
            decoration: BoxDecoration(
              color: p.surfaceMuted,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: p.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeaderBar(context),
                const SizedBox(height: AppSpace.sm),
                _buildContent(context),
                if (_logPage != null && _logPage!.logs.isNotEmpty) ...[
                  const SizedBox(height: AppSpace.md),
                  _buildPaginationBar(context),
                ],
              ],
            ),
          ),
          crossFadeState: _isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: _foldDuration(context),
          sizeCurve: AppMotion.standard,
        ),
      ],
    );
  }

  /// Akordiyon/detay panelinin katlanma süresi: 200 ms; hareket azaltmada 1 ms. SIFIR süre
  /// KULLANILMAZ: `AnimatedCrossFade` içindeki `AnimatedSize` süre sıfırken kendi `performLayout`'u
  /// içinde yeniden yerleşim ister (Flutter assert'i: "RenderAnimatedSize was mutated in its own
  /// performLayout"); 1 ms görsel olarak anındadır.
  static Duration _foldDuration(BuildContext context) =>
      AppMotion.reduced(context) ? const Duration(milliseconds: 1) : AppMotion.base;

  Widget _buildHeaderBar(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final total = _logPage?.total ?? 0;
    final captionStyle = th.bodySmall?.copyWith(
      fontWeight: FontWeight.w600,
      color: p.textSecondary,
    );

    return Row(
      children: [
        Icon(Icons.access_time_rounded, size: 15, color: p.textSecondary),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: _logPage != null
              ? AnimatedCount(
                  prefix: 'Toplam ',
                  value: total,
                  suffix: ' geçiş kaydı',
                  style: captionStyle,
                )
              : Text(
                  'Geçiş Geçmişi',
                  style: captionStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
        ),

        if (widget.onDownloadPdf != null)
          IconButton(
            tooltip: 'PDF Raporu İndir',
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            onPressed: widget.onDownloadPdf,
            icon: Icon(
              Icons.picture_as_pdf_outlined,
              size: 20,
              color: AppTone.primary.ink(p),
            ),
          ),
        IconButton(
          tooltip: 'Yenile',
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          onPressed: _isLoading ? null : () => _loadLogs(page: _currentPage),
          icon: _isLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(Icons.refresh_rounded, size: 20, color: p.textSecondary),
        ),
      ],
    );
  }

  Widget _buildContent(BuildContext context) {
    final th = Theme.of(context).textTheme;

    // İlk yükleme: 4 satır iskelet (yenilemede mevcut liste kalır).
    if (_isLoading && _logPage == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
        child: Column(
          children: [
            ShimmerScope(
              child: Column(
                children: [for (var i = 0; i < 4; i++) const _LogRowSkeleton()],
              ),
            ),
            const SizedBox(height: AppSpace.sm),
            Text(
              'Geçiş logları getiriliyor...',
              textAlign: TextAlign.center,
              style: th.bodySmall,
            ),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return InlineNotice(
        message: _errorMessage!,
        onRetry: () => _loadLogs(page: _currentPage),
      );
    }

    final logs = _logPage?.logs ?? [];
    if (logs.isEmpty) {
      return const EmptyState.compact(
        icon: Icons.history_toggle_off_rounded,
        title: 'Kayıtlı kapı geçiş kaydı bulunamadı.',
      );
    }

    return Column(
      children: [
        for (var i = 0; i < logs.length; i++)
          StaggeredEntry(index: i, child: _buildLogRow(context, logs[i])),
      ],
    );
  }

  String _formatTimeOnly(DateTime? dt) {
    if (dt == null) return '--:--';
    final local = dt.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _formatDateOnly(DateTime? dt) {
    if (dt == null) return 'Bilinmiyor';
    final local = dt.toLocal();
    final d = local.day.toString().padLeft(2, '0');
    final mo = local.month.toString().padLeft(2, '0');
    final y = local.year;
    return '$d.$mo.$y';
  }

  Widget _buildLogRow(BuildContext context, DoorAccessLogRecord log) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final (triggerIcon, triggerTone) = _getTriggerInfo(log.triggerType);
    final triggerInk = triggerTone.ink(p);

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

    final rawName = log.userName.trim();
    final displayName = rawName.isEmpty
        ? (roleLabel.isNotEmpty ? roleLabel : 'Yetkili Geçiş')
        : rawName;

    final timeText = Text(
      _formatTimeOnly(log.openedAt),
      style: th.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: p.text),
    );
    final dateText = Text(
      _formatDateOnly(log.openedAt),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: th.bodySmall,
    );

    // Ad + yöntem rozeti: sığmazsa rozet alt satıra iner (ad kırpılmaz).
    final nameBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpace.sm,
          runSpacing: AppSpace.xs,
          children: [
            Text(
              displayName,
              style: th.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: p.text,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                color: triggerTone.tint(p),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpace.sm,
                  vertical: AppSpace.xs,
                ),
                child: Text(
                  log.triggerTypeDisplay,
                  style: th.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: triggerInk,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.xs),
        Text(
          '$roleLabel$aptLabel',
          style: th.bodySmall,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpace.sm),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.md,
        vertical: AppSpace.sm,
      ),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: p.border),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Tarih/saat sütunu yan yana sığmıyorsa (dar ekran / büyük yazı) adın altına iner.
          final scale = MediaQuery.textScalerOf(context).scale(12) / 12;
          final stacked = constraints.maxWidth - _rowFixedWidth - 60 * scale < _rowMinNameWidth;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Yöntem İkon Rozeti
              DecoratedBox(
                decoration: BoxDecoration(
                  color: triggerTone.tint(p),
                  shape: BoxShape.circle,
                ),
                child: SizedBox(
                  width: 32,
                  height: 32,
                  child: Icon(triggerIcon, size: 16, color: triggerInk),
                ),
              ),
              const SizedBox(width: AppSpace.md),

              // Kullanıcı Adı ve Daire/Rol Bilgisi (+ dar düzende tarih & saat)
              Expanded(
                child: stacked
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          nameBlock,
                          const SizedBox(height: AppSpace.xs),
                          Wrap(
                            spacing: AppSpace.sm,
                            children: [timeText, dateText],
                          ),
                        ],
                      )
                    : nameBlock,
              ),

              // Tarih & Saat (2 satır, geniş düzende sağda)
              if (!stacked) ...[
                const SizedBox(width: AppSpace.sm),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [timeText, dateText],
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  /// Satırdaki sabit genişlikler: simge 32 + boşluk 12 + sağ sütun boşluğu 8.
  static const double _rowFixedWidth = 32 + AppSpace.md + AppSpace.sm;

  /// Ad sütununa kalması gereken en az genişlik (altında tarih/saat adın altına iner).
  static const double _rowMinNameWidth = 110;

  Widget _buildPaginationBar(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final page = _currentPage;
    final totalPages = _logPage?.totalPages ?? 1;
    final hasPrev = page > 1 && !_isLoading;
    final hasNext = page < totalPages && !_isLoading;
    final buttonStyle = TextButton.styleFrom(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.sm,
        vertical: AppSpace.xs,
      ),
      minimumSize: const Size(64, 44),
      foregroundColor: AppTone.primary.ink(p),
      disabledForegroundColor: p.textMuted.withValues(alpha: 0.6),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: p.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
        // Çok dar ekran/büyük yazıda üç öğe alt satırlara akar (taşmaz).
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            // Önceki Sayfa
            TextButton.icon(
              onPressed: hasPrev ? () => _loadLogs(page: page - 1) : null,
              icon: const Icon(Icons.chevron_left_rounded, size: 18),
              label: Text('Önceki', style: th.bodySmall),
              style: buttonStyle,
            ),

            // Sayfa Numarası
            Text(
              'Sayfa $page / $totalPages',
              style: th.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: p.text,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),

            // Sonraki Sayfa
            TextButton.icon(
              onPressed: hasNext ? () => _loadLogs(page: page + 1) : null,
              iconAlignment: IconAlignment.end,
              icon: const Icon(Icons.chevron_right_rounded, size: 18),
              label: Text('Sonraki', style: th.bodySmall),
              style: buttonStyle,
            ),
          ],
        ),
      ),
    );
  }

  /// Geçiş yöntemi -> (ikon, ton). Renk METİN/ikon olarak `ink` ile (>= 4,5:1), zemin `tint` ile
  /// kullanılır; ham renk yok.
  (IconData, AppTone) _getTriggerInfo(String triggerType) {
    switch (triggerType) {
      case 'voice':
        return (Icons.mic_rounded, AppTone.violet);
      case 'local_wifi':
      case 'local_udp':
      case 'local_http':
        return (Icons.wifi_rounded, AppTone.warning);
      case 'local_ble':
      case 'ble':
        return (Icons.bluetooth_rounded, AppTone.info);
      case 'guest_pass':
        return (Icons.qr_code_2_rounded, AppTone.success);
      case 'screen_qr':
        return (Icons.qr_code_scanner_rounded, AppTone.info);
      case 'qr_scanner':
        return (Icons.camera_alt_rounded, AppTone.success);
      case 'display_btn':
      case 'admin_display_btn':
        return (Icons.touch_app_rounded, AppTone.violet);
      case 'physical_btn':
        return (Icons.radio_button_checked_rounded, AppTone.violet);
      case 'serial_btn':
        return (Icons.usb_rounded, AppTone.neutral);
      case 'offline_sync':
        return (Icons.sync_rounded, AppTone.neutral);
      case 'cloud_app':
      case 'mqtt':
      case 'mqtt_pulse':
      case 'remote':
      default:
        return (Icons.cloud_done_rounded, AppTone.primary);
    }
  }
}

/// Günlük satırı iskeleti (simge + iki satır + saat): ilk yükleme sırasında 4 adet gösterilir.
class _LogRowSkeleton extends StatelessWidget {
  const _LogRowSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(bottom: AppSpace.sm),
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
          SkeletonBox(width: 44, height: 24, radius: AppRadius.sm),
        ],
      ),
    );
  }
}
