import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/join_request_record.dart';
import 'package:site_kapi_kontrol/models/site_record.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/empty_state.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
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
            const SizedBox(height: 12),
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
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
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
                  ? const Center(child: CircularProgressIndicator())
                  : _errorMessage != null
                      ? SingleChildScrollView(
                          padding: const EdgeInsets.all(20),
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
                              child: ListView.separated(
                                padding: const EdgeInsets.all(16),
                                itemCount: _requests.length,
                                separatorBuilder: (_, _) => const SizedBox(height: 12),
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

    final statusText = req.isApproved
        ? 'Onaylandı'
        : (req.isRejected ? 'Reddedildi' : 'Onay Bekliyor');

    return AppCard(
      tone: req.isPending ? AppTone.warning : null,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Üst Satır: Kullanıcı Adı ve Durum Rozeti
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                req.fullName ?? 'İsimsiz Kullanıcı',
                style: th.titleMedium,
              ),
              StatusChip(label: statusText, tone: statusTone),
            ],
          ),
          const SizedBox(height: 4),

          // İletişim Bilgileri
          Wrap(
            spacing: 12,
            runSpacing: 4,
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
          const SizedBox(height: 8),

          // Blok ve Daire Rozetleri
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if ((req.blockName ?? '').isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTone.primary.tint(p),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    req.blockName!,
                    style: th.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppTone.primary.ink(p),
                    ),
                  ),
                ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: p.surfaceMuted,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  req.unitLabel ?? 'Daire ?',
                  style: th.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: p.text,
                  ),
                ),
              ),
              Text(
                formatDateTimeOrUnknown(req.createdAt),
                style: th.bodySmall?.copyWith(color: p.textSecondary),
              ),
            ],
          ),

          // Kullanıcı Notu
          if ((req.notes ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: p.surfaceMuted,
                borderRadius: BorderRadius.circular(8),
              ),
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
            const SizedBox(height: 6),
            Text(
              'Ret Sebebi: ${req.rejectionReason!}',
              style: th.bodySmall?.copyWith(
                color: AppTone.danger.ink(p),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],

          // Aksiyon Butonları (Yalnızca PENDING ise): sığmazsa alt alta dizilir.
          if (req.isPending) ...[
            const SizedBox(height: 12),
            OverflowBar(
              alignment: MainAxisAlignment.end,
              spacing: 10,
              overflowSpacing: 8,
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
