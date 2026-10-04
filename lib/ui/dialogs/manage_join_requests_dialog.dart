import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:site_kapi_kontrol/models/join_request_record.dart';
import 'package:site_kapi_kontrol/models/site_record.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/empty_state.dart';
import 'package:site_kapi_kontrol/ui/design/icon_orb.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/large_dialog_parts.dart';
import 'package:site_kapi_kontrol/ui/helpers/ui_helpers.dart';

class ManageJoinRequestsDialog extends StatefulWidget {
  const ManageJoinRequestsDialog({
    super.key,
    required this.site,
    required this.authService,
  });

  final SiteRecord site;
  final AuthService authService;

  static Future<bool?> show(
    BuildContext context, {
    required SiteRecord site,
    required AuthService authService,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => ManageJoinRequestsDialog(
        site: site,
        authService: authService,
      ),
    );
  }

  @override
  State<ManageJoinRequestsDialog> createState() => _ManageJoinRequestsDialogState();
}

class _ManageJoinRequestsDialogState extends State<ManageJoinRequestsDialog> {
  bool _isLoading = true;
  String? _errorMessage;
  List<JoinRequestRecord> _requests = [];
  final Set<int> _busyRequestIds = {};

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final (list, error) = await widget.authService.getSiteJoinRequests(
      siteCode: widget.site.id,
    );

    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (error != null) {
        _errorMessage = error;
      } else {
        _requests = list ?? [];
      }
    });
  }

  Future<void> _approve(JoinRequestRecord request) async {
    HapticFeedback.lightImpact();
    setState(() => _busyRequestIds.add(request.id));

    final (success, message) = await widget.authService.approveJoinRequest(request.id);
    if (!mounted) return;
    setState(() => _busyRequestIds.remove(request.id));

    if (success) {
      AppSnack.show(
        context,
        message ?? 'Başvuru başarıyla onaylandı.',
        kind: AppSnackKind.success,
      );
      _loadRequests();
    } else {
      AppSnack.show(
        context,
        message ?? 'Başvuru onaylanamadı.',
        kind: AppSnackKind.error,
      );
    }
  }

  Future<void> _reject(JoinRequestRecord request) async {
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppDialog(
        title: 'Katılım Başvurusunu Reddet',
        icon: Icons.person_off_rounded,
        tone: AppTone.danger,
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTone.danger.a,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reddet'),
          ),
        ],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${request.fullName ?? 'Kullanıcı'} (${request.blockName ?? ''} ${request.unitLabel ?? ''}) başvurusunu reddetmek istediğinize emin misiniz?',
            ),
            const SizedBox(height: AppSpace.md),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'Ret Gerekçesi (İsteğe bağlı)',
                hintText: 'Örn: Daire sahibi teyit etmedi...',
                isDense: true,
              ),
              maxLines: 2,
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;
    HapticFeedback.lightImpact();

    setState(() => _busyRequestIds.add(request.id));
    final (success, message) = await widget.authService.rejectJoinRequest(
      request.id,
      reason: reasonController.text.trim(),
    );
    if (!mounted) return;
    setState(() => _busyRequestIds.remove(request.id));

    if (success) {
      AppSnack.show(
        context,
        message ?? 'Başvuru reddedildi.',
        kind: AppSnackKind.warning,
      );
      _loadRequests();
    } else {
      AppSnack.show(
        context,
        message ?? 'Başvuru reddedilemedi.',
        kind: AppSnackKind.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final pendingCount = _requests.where((r) => r.isPending).length;
    // Büyük yazıda sabit başlık küçülür: alt başlık (site adı) bekleyen satırına taşınır.
    final compactHeader = MediaQuery.textScalerOf(context).scale(1) > 1.3;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.xl),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 680),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Üst Başlık Barı (+ sağ üstte kapatma; başlık düğmenin altına girmesin diye sağdan pay)
            Stack(
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 32),
                  child: AppDialogHeader(
                    title: 'Katılım Talepleri',
                    subtitle: compactHeader ? null : widget.site.name,
                    icon: Icons.how_to_reg_rounded,
                  ),
                ),
                PositionedDirectional(
                  top: AppSpace.sm,
                  end: AppSpace.sm,
                  child: IconButton(
                    onPressed: () => Navigator.pop(context, false),
                    icon: const Icon(Icons.close_rounded),
                    constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                  ),
                ),
              ],
            ),
            // Bekleyen sayısı + yenile
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.xl, 0, AppSpace.sm, AppSpace.sm),
              child: Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (compactHeader)
                            Padding(
                              padding: const EdgeInsets.only(bottom: AppSpace.xs),
                              child: Text(
                                widget.site.name,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          if (pendingCount > 0)
                            StatusChip(label: '$pendingCount Bekleyen', tone: AppTone.warning),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Yenile',
                    onPressed: _isLoading ? null : _loadRequests,
                    constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // İçerik
            Expanded(
              child: _isLoading
                  // İlk yükleme: kart satırı iskeleti (paylaşılan tek shimmer; yükleme bitince kalkar).
                  ? const SingleChildScrollView(
                      padding: EdgeInsets.all(AppSpace.lg),
                      child: DialogRowsSkeleton(),
                    )
                  : _errorMessage != null
                      ? SingleChildScrollView(
                          padding: const EdgeInsets.all(AppSpace.lg + AppSpace.xs),
                          child: InlineNotice(
                            message: _errorMessage!,
                            onRetry: _loadRequests,
                          ),
                        )
                      : _requests.isEmpty
                          ? const EmptyState(
                              icon: Icons.inbox_outlined,
                              title: 'Henüz katılım talebi bulunmuyor.',
                              message:
                                  'Site Katılım QR kodu okutan sakinlerin başvuruları burada listelenecektir.',
                            )
                          : RefreshIndicator(
                              onRefresh: _loadRequests,
                              // Tembel liste (geçmiş talepler uzun olabilir): kademeli giriş yok.
                              child: ListView.separated(
                                padding: const EdgeInsets.all(AppSpace.lg),
                                itemCount: _requests.length,
                                separatorBuilder: (_, _) => const SizedBox(height: AppSpace.md),
                                itemBuilder: (context, index) {
                                  final req = _requests[index];
                                  final isBusy = _busyRequestIds.contains(req.id);
                                  return _buildRequestCard(context, req, isBusy);
                                },
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
  }

  /// Talep kartı: [durum ikon rozeti] [ad + durum / iletişim / blok-daire / not / ret sebebi] ve
  /// (yalnız bekleyen talepte) altta tam genişlikte Reddet / Onayla eylemleri. Rozet tonu durumdur
  /// (bekliyor: uyarı, onaylı: başarı, reddedildi: hata); büyük yazıda (>= 1,75x) rozet gizlenir.
  Widget _buildRequestCard(
    BuildContext context,
    JoinRequestRecord req,
    bool isBusy,
  ) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final statusTone = req.isApproved
        ? AppTone.success
        : (req.isRejected ? AppTone.danger : AppTone.warning);
    final statusIcon = req.isApproved
        ? Icons.how_to_reg_rounded
        : (req.isRejected ? Icons.person_off_rounded : Icons.person_add_alt_1_rounded);

    final statusText = req.isApproved
        ? 'Onaylandı'
        : (req.isRejected ? 'Reddedildi' : 'Onay Bekliyor');
    final large = hideRowOrbs(context);

    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Üst Satır: Kullanıcı Adı ve Durum Rozeti
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              req.fullName ?? 'İsimsiz Kullanıcı',
              style: th.titleMedium,
            ),
            StatusChip(label: statusText, tone: statusTone),
          ],
        ),
        const SizedBox(height: AppSpace.xs),

        // İletişim Bilgileri
        Wrap(
          spacing: AppSpace.md,
          runSpacing: AppSpace.xs,
          children: [
            if ((req.email ?? '').isNotEmpty)
              Text(
                req.email!,
                style: th.bodySmall?.copyWith(color: p.textSecondary),
              ),
            if ((req.phoneNumber ?? '').isNotEmpty)
              Text(
                req.phoneNumber!,
                style: th.bodySmall?.copyWith(color: p.textSecondary),
              ),
          ],
        ),
        const SizedBox(height: AppSpace.sm),

        // Blok ve Daire Rozetleri
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if ((req.blockName ?? '').isNotEmpty)
              DialogMetaPill(req.blockName!, tone: AppTone.primary),
            DialogMetaPill(req.unitLabel ?? 'Daire ?'),
            Text(
              formatDateTimeOrUnknown(req.createdAt),
              style: th.bodySmall?.copyWith(color: p.textSecondary),
            ),
          ],
        ),

        // Kullanıcı Notu
        if ((req.notes ?? '').isNotEmpty) ...[
          const SizedBox(height: AppSpace.sm),
          DialogPanel(
            padding: const EdgeInsets.all(AppSpace.sm),
            child: Text(
              'Not: ${req.notes!}',
              style: th.bodySmall?.copyWith(
                fontStyle: FontStyle.italic,
                color: p.textSecondary,
              ),
            ),
          ),
        ],

        // Ret Sebebi (varsa)
        if ((req.rejectionReason ?? '').isNotEmpty) ...[
          const SizedBox(height: AppSpace.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.info_outline_rounded,
                  size: 14,
                  color: AppTone.danger.ink(p),
                ),
              ),
              const SizedBox(width: AppSpace.xs),
              Expanded(
                child: Text(
                  'Ret Sebebi: ${req.rejectionReason!}',
                  style: th.bodySmall?.copyWith(
                    color: AppTone.danger.ink(p),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );

    return AppCard(
      tone: req.isPending ? AppTone.warning : null,
      padding: EdgeInsets.all(
        MediaQuery.sizeOf(context).width < 360 ? AppSpace.md : AppSpace.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!large) ...[
                IconOrb(
                  icon: statusIcon,
                  tone: statusTone,
                  size: 40,
                  shape: IconOrbShape.squircle,
                ),
                const SizedBox(width: AppSpace.md),
              ],
              Expanded(child: details),
            ],
          ),

          // Aksiyon Butonları (Yalnızca PENDING ise): sığmazsa alt alta dizilir.
          if (req.isPending) ...[
            const SizedBox(height: AppSpace.md),
            OverflowBar(
              alignment: MainAxisAlignment.end,
              spacing: AppSpace.md,
              overflowSpacing: AppSpace.sm,
              overflowAlignment: OverflowBarAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: isBusy ? null : () => _reject(req),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTone.danger.ink(p),
                    side: BorderSide(color: AppTone.danger.hue.withValues(alpha: 0.6)),
                  ),
                  icon: const Icon(Icons.close_rounded, size: 16),
                  label: const Text('Reddet'),
                ),
                ElevatedButton.icon(
                  onPressed: isBusy ? null : () => _approve(req),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTone.success.a,
                    foregroundColor: Colors.white,
                  ),
                  icon: isBusy
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.check_rounded, size: 16),
                  label: const Text('Onayla'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
