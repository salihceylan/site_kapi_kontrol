import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/apartment_record.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/models/site_page.dart';
import 'package:site_kapi_kontrol/models/site_record.dart';
import 'package:site_kapi_kontrol/models/site_structure_record.dart';
import 'package:site_kapi_kontrol/models/site_manager_record.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/motion_widgets.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/ui_helpers.dart';
import 'package:site_kapi_kontrol/ui/widgets/apartment_card.dart';
import 'package:site_kapi_kontrol/ui/widgets/door_card.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/site_card.dart';

class SitesView extends StatelessWidget {
  const SitesView({
    super.key,
    required this.canManageSites,
    required this.canManageApartmentUsers,
    required this.canAssignDoorDevices,
    required this.apartmentMode,
    required this.pageData,
    required this.sites,
    required this.selectedSite,
    required this.selectedStructure,
    required this.isLoadingSites,
    required this.isLoadingStructure,
    required this.busyDeleteSites,
    required this.busySiteApprovals,
    required this.busyApartmentMails,
    required this.onRefreshSites,
    required this.onLoadPage,
    required this.onOpenAddSite,
    required this.onSelectSite,
    required this.onEditSite,
    required this.onDeleteSite,
    required this.onApproveSite,
    required this.onRejectSite,
    required this.onEditApartmentResident,
    required this.onSendApartmentMail,
    required this.onAssignDoorDevice,
    this.siteManagersData,
    this.isLoadingManagers = false,
    this.onInviteSiteManager,
    this.onRemoveSiteManager,
    this.onRevokeSiteManagerInvitation,
    this.onOpenAddDoor,
    this.onEditDoor,
    this.onDeleteDoor,
    this.onReplaceDevice,
    this.onManageDoorPermissions,
    this.onDeleteApartmentResident,
    this.onConfigurePolicy,
    this.onDownloadCredentialsPdf,
    this.onDownloadLogsPdf,
    this.onShowSiteJoinQr,
    this.onManageJoinRequests,
    this.onShowResidentsAccordion,
    this.isSuperUser = false,
    this.onApproveDeleteSite,
    this.onRejectDeleteSite,
    this.onDeleteSiteWithEmail,
  });

  final bool canManageSites;
  final bool canManageApartmentUsers;
  final bool canAssignDoorDevices;
  final bool apartmentMode;
  final SitePage? pageData;
  final List<SiteRecord> sites;
  final SiteRecord? selectedSite;
  final SiteStructureRecord? selectedStructure;
  final bool isLoadingSites;
  final bool isLoadingStructure;
  final Set<int> busyDeleteSites;
  final Set<int> busySiteApprovals;
  final Set<int> busyApartmentMails;
  final VoidCallback onRefreshSites;
  final ValueChanged<int> onLoadPage;
  final VoidCallback onOpenAddSite;
  final ValueChanged<SiteRecord> onSelectSite;
  final ValueChanged<SiteRecord> onEditSite;
  final ValueChanged<SiteRecord> onDeleteSite;
  final ValueChanged<SiteRecord> onApproveSite;
  final ValueChanged<SiteRecord> onRejectSite;
  final bool isSuperUser;
  final ValueChanged<SiteRecord>? onApproveDeleteSite;
  final ValueChanged<SiteRecord>? onRejectDeleteSite;
  final ValueChanged<SiteRecord>? onDeleteSiteWithEmail;
  final ValueChanged<ApartmentRecord> onEditApartmentResident;
  final ValueChanged<ApartmentRecord> onSendApartmentMail;
  final ValueChanged<DoorRecord> onAssignDoorDevice;
  final SiteManagersData? siteManagersData;
  final bool isLoadingManagers;
  final VoidCallback? onInviteSiteManager;
  final ValueChanged<SiteManagerRecord>? onRemoveSiteManager;
  final ValueChanged<SiteManagerInvitationRecord>? onRevokeSiteManagerInvitation;
  final VoidCallback? onOpenAddDoor;
  final ValueChanged<DoorRecord>? onEditDoor;
  final ValueChanged<DoorRecord>? onDeleteDoor;
  final ValueChanged<DoorRecord>? onReplaceDevice;
  final ValueChanged<DoorRecord>? onManageDoorPermissions;
  final ValueChanged<ApartmentRecord>? onDeleteApartmentResident;
  final ValueChanged<SiteRecord>? onConfigurePolicy;
  final ValueChanged<SiteRecord>? onDownloadCredentialsPdf;
  final ValueChanged<SiteRecord>? onDownloadLogsPdf;
  final ValueChanged<SiteRecord>? onShowSiteJoinQr;
  final ValueChanged<SiteRecord>? onManageJoinRequests;
  final ValueChanged<SiteRecord>? onShowResidentsAccordion;

  @override
  Widget build(BuildContext context) {
    final structure = selectedStructure;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeaderCard(
          title: apartmentMode ? 'Site Daireleri' : 'Siteler',
          action: canManageSites
              ? ElevatedButton.icon(
                  onPressed: onOpenAddSite,
                  icon: const Icon(Icons.add_business_outlined),
                  label: const Text('Yeni Site'),
                )
              : null,
        ),
        const SizedBox(height: AppSpace.lg),
        ..._buildSiteList(context),
        const SizedBox(height: AppSpace.lg),
        if (isLoadingStructure && structure == null)
          const ListSkeleton(rows: 2)
        else if (structure != null) ...[
          _buildStructureSummary(context, structure),
          const SizedBox(height: AppSpace.lg),
          _buildManagers(context),
          const SizedBox(height: AppSpace.lg),
          _buildApartments(context, structure),
          const SizedBox(height: AppSpace.lg),
          ..._buildDoors(context, structure),
        ],
      ],
    );
  }

  /// "Site Listesi" bölümü: başlık sayfa zemininde, her site kendi AppCard'ı (tek yüzey).
  List<Widget> _buildSiteList(BuildContext context) {
    final page = pageData;
    return [
      SectionHeader(
        title: page == null ? 'Site Listesi' : 'Site Listesi (${page.total})',
        trailing: IconButton(
          onPressed: isLoadingSites ? null : onRefreshSites,
          icon: const Icon(Icons.refresh),
        ),
      ),
      const SizedBox(height: AppSpace.md),
      if (isLoadingSites && page == null)
        const ListSkeleton()
      else if (sites.isEmpty)
        const EmptyCard(
          icon: Icons.apartment_rounded,
          title: 'Kayıtlı site bulunamadı.',
        )
      else ...[
        for (var i = 0; i < sites.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.md),
            child: StaggeredEntry(
              index: i,
              child: _buildSiteCard(sites[i]),
            ),
          ),
        if (page != null)
          PaginationBar(
            label:
                'Sayfa ${page.page} / ${page.totalPages} | Toplam ${page.total}',
            onPrevious: page.page > 1 ? () => onLoadPage(page.page - 1) : null,
            onNext: page.page < page.totalPages
                ? () => onLoadPage(page.page + 1)
                : null,
          ),
      ],
    ];
  }

  Widget _buildSiteCard(SiteRecord site) {
    return SiteCard(
      site: site,
      selected: selectedSite?.id == site.id,
      formattedCreatedAt: formatDateTime(site.createdAt),
      deleteBusy: busyDeleteSites.contains(site.id),
      approvalBusy: busySiteApprovals.contains(site.id),
      onTap: () => onSelectSite(site),
      onEdit: canManageSites ? () => onEditSite(site) : null,
      onDelete: canManageSites ? () => onDeleteSite(site) : null,
      onApprove: canManageSites && site.approvalStatus == 'pending'
          ? () => onApproveSite(site)
          : null,
      onReject: canManageSites && site.approvalStatus == 'pending'
          ? () => onRejectSite(site)
          : null,
      onConfigurePolicy: onConfigurePolicy != null
          ? () => onConfigurePolicy!(site)
          : null,
      onDownloadPdf: onDownloadCredentialsPdf != null
          ? () => onDownloadCredentialsPdf!(site)
          : null,
      onDownloadLogsPdf: onDownloadLogsPdf != null
          ? () => onDownloadLogsPdf!(site)
          : null,
      onShowJoinQr: onShowSiteJoinQr != null
          ? () => onShowSiteJoinQr!(site)
          : null,
      onManageJoinRequests: onManageJoinRequests != null
          ? () => onManageJoinRequests!(site)
          : null,
      isSuperUser: isSuperUser,
      onApproveDeletion: onApproveDeleteSite != null
          ? () => onApproveDeleteSite!(site)
          : null,
      onRejectDeletion: onRejectDeleteSite != null
          ? () => onRejectDeleteSite!(site)
          : null,
      onDeleteWithEmail: onDeleteSiteWithEmail != null
          ? () => onDeleteSiteWithEmail!(site)
          : null,
    );
  }

  /// Seçili sitenin özeti: ad, kimlik çipleri, yönetici/adres ve yönetim eylemleri (ton zeminli).
  Widget _buildStructureSummary(
    BuildContext context,
    SiteStructureRecord structure,
  ) {
    final th = Theme.of(context).textTheme;
    final site = structure.site;
    return AppCard(
      padding: listCardPadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(site.name, style: th.titleLarge),
          const SizedBox(height: AppSpace.sm),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: [
              InfoChip('Site Kodu: ${site.id}'),
              InfoChip('MQTT Site ID: ${site.mqttSiteId}'),
              InfoChip('Blok: ${site.blockCount}'),
              InfoChip('Daire: ${site.apartmentCount}'),
              InfoChip('Kapı: ${site.doorCount}'),
            ],
          ),
          if ((site.managerName ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.sm),
              child: Text(
                'Yönetici: ${site.managerName} (${site.managerUserCode ?? '-'})',
                style: th.bodyMedium,
              ),
            ),
          if ((site.address ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.xs),
              child: Text('Adres: ${site.address}', style: th.bodyMedium),
            ),
          const SizedBox(height: AppSpace.md),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: [
              if (canManageSites)
                OutlinedButton.icon(
                  onPressed: () => onEditSite(site),
                  style: tonalActionStyle(context),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Siteyi Düzenle'),
                ),
              if (onShowSiteJoinQr != null)
                OutlinedButton.icon(
                  onPressed: () => onShowSiteJoinQr!(site),
                  style: tonalActionStyle(context),
                  icon: const Icon(Icons.qr_code_2_rounded),
                  label: const Text('Site Katılım QR'),
                ),
              if (onManageJoinRequests != null)
                OutlinedButton.icon(
                  onPressed: () => onManageJoinRequests!(site),
                  style: tonalActionStyle(context, tone: AppTone.warning),
                  icon: const Icon(Icons.how_to_reg_outlined),
                  label: const Text('Katılım Talepleri'),
                ),
              if (onShowResidentsAccordion != null)
                OutlinedButton.icon(
                  onPressed: () => onShowResidentsAccordion!(site),
                  style: tonalActionStyle(context),
                  icon: const Icon(Icons.account_tree_rounded),
                  label: const Text('Sakin Listesi (Akordiyon)'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// "Site Yöneticileri": tek kart, satırlar `Divider` ile ayrılır (iç içe kutu yok).
  Widget _buildManagers(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final data = siteManagersData;
    final warningInk = AppTone.warning.ink(p);

    return AppCard(
      padding: listCardPadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            icon: Icons.admin_panel_settings_rounded,
            title: data == null
                ? 'Site Yöneticileri'
                : 'Site Yöneticileri (${data.managers.length})',
            trailing: onInviteSiteManager != null
                ? ElevatedButton.icon(
                    onPressed: onInviteSiteManager,
                    icon: const Icon(Icons.person_add_alt_1_rounded, size: 16),
                    label: const Text('Yönetici Davet Et'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpace.md,
                        vertical: AppSpace.sm,
                      ),
                      minimumSize: const Size(0, 44),
                    ),
                  )
                : null,
          ),
          const SizedBox(height: AppSpace.md),
          if (isLoadingManagers && data == null)
            const ListSkeleton(rows: 1, inCard: true)
          else if (data == null || data.managers.isEmpty)
            const Text('Yönetici kaydı bulunamadı.')
          else ...[
            for (var i = 0; i < data.managers.length; i++) ...[
              if (i > 0) const Divider(),
              _buildManagerRow(context, data.managers[i]),
            ],
            if (data.invitations.isNotEmpty) ...[
              const SizedBox(height: AppSpace.md),
              Row(
                children: [
                  Icon(
                    Icons.mark_email_unread_outlined,
                    size: 16,
                    color: warningInk,
                  ),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: Text(
                      'Bekleyen Davetler (${data.invitations.length})',
                      style: th.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: warningInk,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.sm),
              for (var i = 0; i < data.invitations.length; i++) ...[
                if (i > 0) const Divider(),
                _buildInvitationRow(context, data.invitations[i]),
              ],
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildManagerRow(BuildContext context, SiteManagerRecord mgr) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final tone = mgr.isOwner ? AppTone.warning : AppTone.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
      child: Row(
        children: [
          IconTile(
            icon: mgr.isOwner
                ? Icons.star_rounded
                : Icons.person_outline_rounded,
            tone: tone,
            size: 40,
            iconSize: 20,
            gap: AppSpace.md,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: AppSpace.sm,
                  runSpacing: AppSpace.xs,
                  children: [
                    Text(
                      mgr.fullName,
                      style: th.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    StatusChip(label: mgr.roleLabel, tone: tone),
                  ],
                ),
                const SizedBox(height: AppSpace.xs),
                Text(mgr.email, style: th.bodyMedium),
                if (mgr.phoneNumber != null && mgr.phoneNumber!.isNotEmpty)
                  Text(mgr.phoneNumber!, style: th.bodySmall),
              ],
            ),
          ),
          if (onRemoveSiteManager != null && !mgr.isOwner)
            IconButton(
              icon: Icon(
                Icons.person_remove_outlined,
                color: AppTone.danger.ink(p),
                size: 20,
              ),
              tooltip: 'Yöneticiliği Kaldır',
              onPressed: () => onRemoveSiteManager!(mgr),
            ),
        ],
      ),
    );
  }

  Widget _buildInvitationRow(
    BuildContext context,
    SiteManagerInvitationRecord inv,
  ) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.xs),
            child: Icon(
              Icons.outgoing_mail,
              color: AppTone.warning.ink(p),
              size: 18,
            ),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  inv.email,
                  style: th.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: p.text,
                  ),
                ),
                if (inv.fullName != null && inv.fullName!.isNotEmpty)
                  Text(inv.fullName!, style: th.bodySmall),
                if (onRevokeSiteManagerInvitation != null)
                  TextButton.icon(
                    onPressed: () => onRevokeSiteManagerInvitation!(inv),
                    icon: Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: AppTone.danger.ink(p),
                    ),
                    label: Text(
                      'İptal Et',
                      style: TextStyle(color: AppTone.danger.ink(p)),
                    ),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 44),
                      alignment: AlignmentDirectional.centerStart,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// "Daireler" akordiyonu: kart + `ExpansionTile` (e2e akordiyon taraması ve metin bulucuları
  /// korunur); daireler kartın içinde düz satırlar, aralarında `Divider`.
  Widget _buildApartments(
    BuildContext context,
    SiteStructureRecord structure,
  ) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    return AppCard(
      padding: EdgeInsets.zero,
      // Kenarlıksız (shape/collapsedShape): ExpansionTile'ın açıkken çizdiği üst/alt çizgi yok; böylece
      // tema bölücü/splash rengi şeffaflaştırılmaz (başlık ve daire satırları dokunma geri bildirimi verir).
      child: ExpansionTile(
        initiallyExpanded: false,
        shape: const Border(),
        collapsedShape: const Border(),
        iconColor: p.textSecondary,
        collapsedIconColor: p.textSecondary,
        tilePadding: const EdgeInsets.symmetric(
          horizontal: AppSpace.lg,
          vertical: AppSpace.xs,
        ),
        childrenPadding: const EdgeInsets.fromLTRB(
          AppSpace.lg,
          0,
          AppSpace.lg,
          AppSpace.md,
        ),
        leading: DecoratedBox(
          decoration: BoxDecoration(
            color: AppTone.primary.tint(p),
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.sm),
            child: Icon(
              Icons.apartment_rounded,
              color: AppTone.primary.ink(p),
              size: 20,
            ),
          ),
        ),
        title: SectionHeader(
          title: 'Daireler',
          count: structure.apartments.length,
          countSuffix: ' Daire',
        ),
        subtitle: Text(
          structure.apartments.isEmpty
              ? 'Kayıtlı daire bulunmuyor'
              : 'Daireleri listelemek veya gizlemek için dokunun',
          style: th.bodySmall,
        ),
        children: [
          if (structure.apartments.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpace.md),
              child: Text('Bu site için daire kaydı bulunamadı.'),
            )
          else
            for (var i = 0; i < structure.apartments.length; i++) ...[
              if (i > 0) const Divider(),
              ApartmentCard(
                apartment: structure.apartments[i],
                onEdit: () =>
                    onEditApartmentResident(structure.apartments[i]),
                onSendMail: () =>
                    onSendApartmentMail(structure.apartments[i]),
                sendingMail: busyApartmentMails.contains(
                  structure.apartments[i].id,
                ),
                onDelete: onDeleteApartmentResident != null
                    ? () => onDeleteApartmentResident!(structure.apartments[i])
                    : null,
              ),
            ],
        ],
      ),
    );
  }

  /// "Kapılar": başlık sayfa zemininde, her kapı kendi AppCard'ı (cihazsız = uyarı tonlu).
  List<Widget> _buildDoors(BuildContext context, SiteStructureRecord structure) {
    return [
      SectionHeader(
        title: 'Kapılar',
        trailing: onOpenAddDoor != null
            ? ElevatedButton.icon(
                onPressed: onOpenAddDoor,
                icon: const Icon(Icons.add_circle_outline_rounded, size: 16),
                label: const Text('Yeni Kapı'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpace.md,
                    vertical: AppSpace.sm,
                  ),
                  minimumSize: const Size(0, 44),
                ),
              )
            : null,
      ),
      const SizedBox(height: AppSpace.md),
      if (structure.doors.isEmpty)
        const EmptyCard(
          icon: Icons.meeting_room_outlined,
          title: 'Bu site için kapı kaydı bulunamadı.',
        )
      else
        for (final door in structure.doors)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.md),
            child: DoorCard(
              door: door,
              onAssignDevice: () => onAssignDoorDevice(door),
              onReplaceDevice: onReplaceDevice != null
                  ? () => onReplaceDevice!(door)
                  : null,
              onEditDoor: onEditDoor != null ? () => onEditDoor!(door) : null,
              onDeleteDoor: onDeleteDoor != null
                  ? () => onDeleteDoor!(door)
                  : null,
              onManagePermissions: onManageDoorPermissions != null
                  ? () => onManageDoorPermissions!(door)
                  : null,
            ),
          ),
    ];
  }
}
