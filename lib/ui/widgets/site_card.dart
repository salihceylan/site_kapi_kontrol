import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/site_record.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

class SiteCard extends StatefulWidget {
  const SiteCard({
    super.key,
    required this.site,
    required this.selected,
    required this.formattedCreatedAt,
    required this.deleteBusy,
    required this.approvalBusy,
    required this.onTap,
    this.onEdit,
    this.onDelete,
    this.onApprove,
    this.onReject,
    this.onConfigurePolicy,
    this.onDownloadPdf,
    this.onDownloadLogsPdf,
    this.onShowJoinQr,
    this.onManageJoinRequests,
    this.onApproveDeletion,
    this.onRejectDeletion,
    this.onDeleteWithEmail,
    this.isSuperUser = false,
  });

  final SiteRecord site;
  final bool selected;
  final String formattedCreatedAt;
  final bool deleteBusy;
  final bool approvalBusy;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;
  final VoidCallback? onConfigurePolicy;
  final VoidCallback? onDownloadPdf;
  final VoidCallback? onDownloadLogsPdf;
  final VoidCallback? onShowJoinQr;
  final VoidCallback? onManageJoinRequests;
  final VoidCallback? onApproveDeletion;
  final VoidCallback? onRejectDeletion;
  final VoidCallback? onDeleteWithEmail;
  final bool isSuperUser;

  @override
  State<SiteCard> createState() => _SiteCardState();
}

class _SiteCardState extends State<SiteCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final site = widget.site;
    final hasManager =
        site.managerName != null && site.managerName!.trim().isNotEmpty;

    // Tek yüzey: kart kendi başına bir AppCard'dır (seçili = 1,5 px kenar + seviye 2); dış "cam" kart
    // yoktur (kart-içinde-kart kalktı). Durum rozetleri başlıkla aynı akışta: sığmazsa alta iner.
    return AppCard(
      selected: widget.selected,
      padding: listCardPadding(context),
      onTap: () {
        widget.onTap();
        setState(() => _expanded = !_expanded);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(expanded: _expanded), // Açık/kapalı durumu ekran okuyucuya bildirir (karta birleşir).
          Row(
            children: [
              const IconTile(icon: Icons.apartment_rounded, gap: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: AppSpace.sm,
                      runSpacing: AppSpace.xs,
                      children: [
                        Text(site.name, style: th.titleMedium),
                        if (site.isDeletionPending)
                          const StatusChip(
                            label: 'Silme Onayı',
                            tone: AppTone.danger,
                          )
                        else if (site.approvalStatus == 'pending')
                          const StatusChip(
                            label: 'Onay Bekliyor',
                            tone: AppTone.warning,
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpace.xs),
                    Text(
                      hasManager
                          ? 'Yönetici: ${site.managerName}'
                          : 'Yönetici atanmamış',
                      style: hasManager
                          ? th.bodyMedium
                          : th.bodyMedium?.copyWith(
                              color: AppTone.warning.ink(p),
                              fontWeight: FontWeight.w600,
                            ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              ExpandChevron(expanded: _expanded),
            ],
          ),
          if (site.isDeletionPending) ...[
            const SizedBox(height: AppSpace.md),
            _buildDeletionApprovalBanner(context),
          ],
          ExpandableSection(
            expanded: _expanded,
            child: _buildDetails(context),
          ),
        ],
      ),
    );
  }

  /// Açık kartın gövdesi: bilgi çipleri + gruplanmış eylemler. Eylem düğmeleri GÖRÜNÜR kalır
  /// (menüye taşınmadı): onay kararları, yönetim eylemleri (ton zeminli), yıkıcı eylemler (danger
  /// kenarlı) ayrı satırlarda.
  Widget _buildDetails(BuildContext context) {
    final site = widget.site;

    final decisions = <Widget>[
      if (widget.onApprove != null)
        ElevatedButton.icon(
          onPressed: widget.approvalBusy ? null : widget.onApprove,
          style: filledToneStyle(context, tone: AppTone.success),
          icon: const Icon(Icons.check_circle_outline, size: 16),
          label: const Text('Onayla'),
        ),
      if (widget.onReject != null)
        OutlinedButton.icon(
          onPressed: widget.approvalBusy ? null : widget.onReject,
          style: dangerOutlineStyle(context),
          icon: const Icon(Icons.cancel_outlined, size: 16),
          label: const Text('Reddet'),
        ),
    ];
    final manage = <Widget>[
      if (widget.onConfigurePolicy != null)
        OutlinedButton.icon(
          onPressed: widget.onConfigurePolicy,
          style: tonalActionStyle(context),
          icon: const Icon(Icons.security_outlined, size: 16),
          label: const Text('Giriş & Güvenlik Politikaları'),
        ),
      if (widget.onEdit != null)
        OutlinedButton.icon(
          onPressed: widget.onEdit,
          style: tonalActionStyle(context),
          icon: const Icon(Icons.edit_outlined, size: 16),
          label: const Text('Düzenle'),
        ),
      if (widget.onDownloadLogsPdf != null)
        OutlinedButton.icon(
          onPressed: widget.onDownloadLogsPdf,
          style: tonalActionStyle(context),
          icon: const Icon(Icons.assignment_outlined, size: 16),
          label: const Text('Geçiş Raporu (PDF)'),
        ),
      if (widget.onShowJoinQr != null)
        OutlinedButton.icon(
          onPressed: widget.onShowJoinQr,
          style: tonalActionStyle(context),
          icon: const Icon(Icons.qr_code_2_rounded, size: 16),
          label: const Text('Site Katılım QR'),
        ),
      if (widget.onManageJoinRequests != null)
        OutlinedButton.icon(
          onPressed: widget.onManageJoinRequests,
          style: tonalActionStyle(context, tone: AppTone.warning),
          icon: const Icon(Icons.how_to_reg_outlined, size: 16),
          label: const Text('Katılım Talepleri'),
        ),
    ];
    final destructive = <Widget>[
      if (widget.onDelete != null && !site.isDeletionPending)
        OutlinedButton.icon(
          onPressed: widget.deleteBusy ? null : widget.onDelete,
          style: dangerOutlineStyle(context),
          icon: const Icon(Icons.delete_outline_rounded, size: 16),
          label: const Text('Sil'),
        ),
      if (widget.isSuperUser &&
          widget.onDeleteWithEmail != null &&
          !site.isDeletionPending)
        OutlinedButton.icon(
          onPressed: widget.deleteBusy ? null : widget.onDeleteWithEmail,
          style: dangerOutlineStyle(context),
          icon: const Icon(Icons.mark_email_read_outlined, size: 16),
          label: const Text('E-Posta Koduyla Sil'),
        ),
    ];
    final groups = <List<Widget>>[
      decisions,
      manage,
      destructive,
    ].where((group) => group.isNotEmpty).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpace.md),
        const Divider(),
        const SizedBox(height: AppSpace.md),
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          children: [
            InfoChip('ID: ${site.id}'),
            InfoChip('Oluşturulma: ${widget.formattedCreatedAt}'),
            if (site.address != null && site.address!.isNotEmpty)
              InfoChip('Adres: ${site.address}'),
            if (site.city != null && site.city!.isNotEmpty)
              InfoChip('Şehir: ${site.city}'),
          ],
        ),
        if (groups.isNotEmpty) const SizedBox(height: AppSpace.md),
        for (var i = 0; i < groups.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpace.sm),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: groups[i],
          ),
        ],
      ],
    );
  }

  Widget _buildDeletionApprovalBanner(BuildContext context) {
    final site = widget.site;
    final isSuperUser = widget.isSuperUser;

    // Beklenen onay makami kullanici mi yoksa karsi taraf mi?
    final isUserApprovalRequired =
        (isSuperUser && site.isPendingSuperUserApproval) ||
        (!isSuperUser && site.isPendingSiteManagerApproval);

    final requesterName =
        site.deletionRequestedByName ??
        (site.deletionRequestedByRole == 'super_user'
            ? 'Süper Kullanıcı'
            : 'Site Yöneticisi');

    final String message;
    if (isUserApprovalRequired) {
      message =
          '$requesterName bu sitenin ve bağlı tüm birimlerinin kalıcı olarak silinmesini talep etti. Sitenin silinmesi için ONAYINIZ bekleniyor.';
    } else {
      message =
          'Bu site için kalıcı silme talebinde bulundunuz. ${isSuperUser ? "Site Yöneticisinin" : "Süper Kullanıcının"} onayı bekleniyor.';
    }

    final tone = isUserApprovalRequired ? AppTone.danger : AppTone.warning;
    final actions = <Widget>[
      if (isUserApprovalRequired && widget.onApproveDeletion != null)
        ElevatedButton.icon(
          onPressed: widget.deleteBusy ? null : widget.onApproveDeletion,
          style: filledToneStyle(context, tone: AppTone.danger),
          icon: widget.deleteBusy
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.delete_forever_rounded, size: 16),
          label: const Text('Silmeyi Onayla'),
        ),
      if (widget.onRejectDeletion != null)
        OutlinedButton.icon(
          onPressed: widget.deleteBusy ? null : widget.onRejectDeletion,
          style: tonalActionStyle(context, tone: tone),
          icon: Icon(
            isUserApprovalRequired
                ? Icons.cancel_outlined
                : Icons.undo_rounded,
            size: 16,
          ),
          label: Text(
            isUserApprovalRequired ? 'Talebi Reddet' : 'Talebi İptal Et',
          ),
        ),
      if (isSuperUser && widget.onDeleteWithEmail != null)
        OutlinedButton.icon(
          onPressed: widget.deleteBusy ? null : widget.onDeleteWithEmail,
          style: dangerOutlineStyle(context),
          icon: const Icon(Icons.mark_email_read_outlined, size: 16),
          label: const Text('E-Posta Kodu İle Hemen Sil'),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InlineNotice(
          message: message,
          tone: tone,
          icon: isUserApprovalRequired
              ? Icons.warning_amber_rounded
              : Icons.hourglass_top_rounded,
        ),
        if (actions.isNotEmpty) ...[
          const SizedBox(height: AppSpace.sm),
          Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.sm, children: actions),
        ],
      ],
    );
  }
}
