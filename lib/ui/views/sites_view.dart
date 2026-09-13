import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/apartment_record.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/models/site_page.dart';
import 'package:site_kapi_kontrol/models/site_record.dart';
import 'package:site_kapi_kontrol/models/site_structure_record.dart';
import 'package:site_kapi_kontrol/models/site_manager_record.dart';
import 'package:site_kapi_kontrol/styles/app_colors.dart';
import 'package:site_kapi_kontrol/styles/app_decorations.dart';
import 'package:site_kapi_kontrol/ui/helpers/ui_helpers.dart';
import 'package:site_kapi_kontrol/ui/widgets/apartment_card.dart';
import 'package:site_kapi_kontrol/ui/widgets/door_card.dart';
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
    final compact = MediaQuery.sizeOf(context).width < 680;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardTitleColor = isDark ? const Color(0xFFF8FAFC) : AppColors.textDark;
    final structure = selectedStructure;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: AppDecorations.glassCard(context),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      apartmentMode ? 'Site Daireleri' : 'Siteler',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: cardTitleColor,
                      ),
                    ),
                    if (canManageSites) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: onOpenAddSite,
                          icon: const Icon(Icons.add_business_outlined),
                          label: const Text('Yeni Site'),
                        ),
                      ),
                    ],
                  ],
                )
              : Row(
                  children: [
                    Expanded(
                      child: Text(
                        apartmentMode ? 'Site Daireleri' : 'Siteler',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: cardTitleColor,
                        ),
                      ),
                    ),
                    if (canManageSites) ...[
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: onOpenAddSite,
                        icon: const Icon(Icons.add_business_outlined),
                        label: const Text('Yeni Site'),
                      ),
                    ],
                  ],
                ),
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: AppDecorations.glassCard(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      pageData == null
                          ? 'Site Listesi'
                          : 'Site Listesi (${pageData!.total})',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: cardTitleColor,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: isLoadingSites ? null : onRefreshSites,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (isLoadingSites && pageData == null)
                const Center(child: CircularProgressIndicator())
              else if (sites.isEmpty)
                const Text('Kayıtlı site bulunamadı.')
              else ...[
                for (final site in sites)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: SiteCard(
                      site: site,
                      selected: selectedSite?.id == site.id,
                      formattedCreatedAt: formatDateTime(site.createdAt),
                      deleteBusy: busyDeleteSites.contains(site.id),
                      approvalBusy: busySiteApprovals.contains(site.id),
                      onTap: () => onSelectSite(site),
                      onEdit: canManageSites ? () => onEditSite(site) : null,
                      onDelete:
                          canManageSites ? () => onDeleteSite(site) : null,
                      onApprove:
                          canManageSites && site.approvalStatus == 'pending'
                              ? () => onApproveSite(site)
                              : null,
                      onReject:
                          canManageSites && site.approvalStatus == 'pending'
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
                    ),
                  ),
                if (pageData != null)
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'Sayfa ${pageData!.page} / ${pageData!.totalPages} | Toplam ${pageData!.total}',
                      ),
                      OutlinedButton(
                        onPressed: pageData!.page > 1
                            ? () => onLoadPage(pageData!.page - 1)
                            : null,
                        child: const Icon(Icons.chevron_left),
                      ),
                      OutlinedButton(
                        onPressed: pageData!.page < pageData!.totalPages
                            ? () => onLoadPage(pageData!.page + 1)
                            : null,
                        child: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (isLoadingStructure && structure == null)
          const Center(child: CircularProgressIndicator())
        else if (structure != null) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: AppDecorations.glassCard(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  structure.site.name,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: cardTitleColor,
                    fontSize: 20,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    Text('Site Kodu: ${structure.site.id}'),
                    Text('MQTT Site ID: ${structure.site.mqttSiteId}'),
                    Text('Blok: ${structure.site.blockCount}'),
                    Text('Daire: ${structure.site.apartmentCount}'),
                    Text('Kapı: ${structure.site.doorCount}'),
                  ],
                ),
                if ((structure.site.managerName ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Yönetici: ${structure.site.managerName} (${structure.site.managerUserCode ?? '-'})',
                    ),
                  ),
                if ((structure.site.address ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('Adres: ${structure.site.address}'),
                  ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (canManageSites)
                      OutlinedButton.icon(
                        onPressed: () => onEditSite(structure.site),
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Siteyi Düzenle'),
                      ),
                    if (onDownloadCredentialsPdf != null)
                      OutlinedButton.icon(
                        onPressed: () =>
                            onDownloadCredentialsPdf!(structure.site),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: isDark ? const Color(0xFF93C5FD) : const Color(0xFF1E3A8A),
                          side: BorderSide(color: isDark ? const Color(0xFF3B82F6) : const Color(0xFF93C5FD)),
                        ),
                        icon: const Icon(Icons.picture_as_pdf_outlined),
                        label: const Text('Şifreleri İndir (PDF)'),
                      ),
                    if (onShowSiteJoinQr != null)
                      OutlinedButton.icon(
                        onPressed: () => onShowSiteJoinQr!(structure.site),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7),
                          side: BorderSide(color: isDark ? const Color(0xFF0284C7) : const Color(0xFF7DD3FC)),
                        ),
                        icon: const Icon(Icons.qr_code_2_rounded),
                        label: const Text('Site Katılım QR'),
                      ),
                    if (onManageJoinRequests != null)
                      OutlinedButton.icon(
                        onPressed: () => onManageJoinRequests!(structure.site),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706),
                          side: BorderSide(color: isDark ? const Color(0xFFD97706) : const Color(0xFFFDE68A)),
                        ),
                        icon: const Icon(Icons.how_to_reg_outlined),
                        label: const Text('Katılım Talepleri'),
                      ),
                    if (onShowResidentsAccordion != null)
                      OutlinedButton.icon(
                        onPressed: () => onShowResidentsAccordion!(structure.site),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: isDark ? const Color(0xFF34D399) : const Color(0xFF059669),
                          side: BorderSide(color: isDark ? const Color(0xFF059669) : const Color(0xFFA7F3D0)),
                        ),
                        icon: const Icon(Icons.account_tree_rounded),
                        label: const Text('Sakin Listesi (Akordiyon)'),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: AppDecorations.glassCard(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.admin_panel_settings_rounded,
                      color: AppColors.primary,
                      size: 22,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        siteManagersData == null
                            ? 'Site Yöneticileri'
                            : 'Site Yöneticileri (${siteManagersData!.managers.length})',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: cardTitleColor,
                        ),
                      ),
                    ),
                    if (onInviteSiteManager != null)
                      ElevatedButton.icon(
                        onPressed: onInviteSiteManager,
                        icon: const Icon(Icons.person_add_alt_1_rounded, size: 16),
                        label: const Text('Yönetici Davet Et'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 0,
                          ),
                          minimumSize: const Size(0, 32),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (isLoadingManagers && siteManagersData == null)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else if (siteManagersData == null ||
                    siteManagersData!.managers.isEmpty)
                  const Text('Yönetici kaydı bulunamadı.')
                else ...[
                  for (final mgr in siteManagersData!.managers)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.04)
                            : Colors.black.withValues(alpha: 0.02),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.08)
                              : Colors.black.withValues(alpha: 0.06),
                        ),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: mgr.isOwner
                                ? Colors.amber.withValues(alpha: 0.2)
                                : AppColors.primary.withValues(alpha: 0.15),
                            child: Icon(
                              mgr.isOwner
                                  ? Icons.star_rounded
                                  : Icons.person_outline_rounded,
                              color: mgr.isOwner
                                  ? Colors.amber.shade800
                                  : AppColors.primary,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        mgr.fullName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: mgr.isOwner
                                            ? Colors.amber.withValues(alpha: 0.15)
                                            : Colors.blue.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        mgr.roleLabel,
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: mgr.isOwner
                                              ? (isDark
                                                  ? Colors.amber.shade300
                                                  : Colors.amber.shade900)
                                              : (isDark
                                                  ? Colors.blue.shade300
                                                  : Colors.blue.shade800),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  mgr.email,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark
                                        ? Colors.white70
                                        : AppColors.textSecondary(context),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (mgr.phoneNumber != null &&
                                    mgr.phoneNumber!.isNotEmpty)
                                  Text(
                                    mgr.phoneNumber!,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isDark
                                          ? Colors.white60
                                          : AppColors.textSecondary(context),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                          ),
                          if (onRemoveSiteManager != null && !mgr.isOwner)
                            IconButton(
                              icon: const Icon(
                                Icons.person_remove_outlined,
                                color: AppColors.error,
                                size: 20,
                              ),
                              tooltip: 'Yöneticiliği Kaldır',
                              onPressed: () => onRemoveSiteManager!(mgr),
                            ),
                        ],
                      ),
                    ),
                  if (siteManagersData!.invitations.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(
                          Icons.mark_email_unread_outlined,
                          size: 16,
                          color: isDark ? Colors.amber.shade300 : Colors.amber.shade800,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Bekleyen Davetler (${siteManagersData!.invitations.length})',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.amber.shade300 : Colors.amber.shade800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    for (final inv in siteManagersData!.invitations)
                      Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.amber.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.outgoing_mail,
                              color: Colors.amber,
                              size: 18,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    inv.email,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (inv.fullName != null &&
                                      inv.fullName!.isNotEmpty)
                                    Text(
                                      inv.fullName!,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: isDark
                                            ? Colors.white70
                                            : AppColors.textSecondary(context),
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                ],
                              ),
                            ),
                            if (onRevokeSiteManagerInvitation != null)
                              TextButton.icon(
                                onPressed: () =>
                                    onRevokeSiteManagerInvitation!(inv),
                                icon: const Icon(
                                  Icons.close_rounded,
                                  size: 14,
                                  color: AppColors.error,
                                ),
                                label: const Text(
                                  'İptal Et',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.error,
                                  ),
                                ),
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  minimumSize: const Size(0, 28),
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: AppDecorations.glassCard(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Daireler',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: cardTitleColor,
                        ),
                      ),
                    ),
                    if (onShowResidentsAccordion != null)
                      ElevatedButton.icon(
                        onPressed: () => onShowResidentsAccordion!(structure.site),
                        icon: const Icon(Icons.account_tree_rounded, size: 16),
                        label: const Text('Akordiyon Sakin Listesi'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                          minimumSize: const Size(0, 32),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                if (structure.apartments.isEmpty)
                  const Text('Bu site için daire kaydı bulunamadı.')
                else
                  for (final apartment in structure.apartments)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: ApartmentCard(
                        apartment: apartment,
                        onEdit: () => onEditApartmentResident(apartment),
                        onSendMail: () => onSendApartmentMail(apartment),
                        sendingMail: busyApartmentMails.contains(apartment.id),
                        onDelete: onDeleteApartmentResident != null
                            ? () => onDeleteApartmentResident!(apartment)
                            : null,
                      ),
                    ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: AppDecorations.glassCard(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Kapılar',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: cardTitleColor,
                        ),
                      ),
                    ),
                    if (onOpenAddDoor != null)
                      ElevatedButton.icon(
                        onPressed: onOpenAddDoor,
                        icon: const Icon(Icons.add_circle_outline_rounded, size: 16),
                        label: const Text('Yeni Kapı'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                          minimumSize: const Size(0, 32),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                if (structure.doors.isEmpty)
                  const Text('Bu site için kapı kaydı bulunamadı.')
                else
                  for (final door in structure.doors)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: DoorCard(
                        door: door,
                        onAssignDevice: () => onAssignDoorDevice(door),
                        onReplaceDevice: onReplaceDevice != null ? () => onReplaceDevice!(door) : null,
                        onEditDoor: onEditDoor != null ? () => onEditDoor!(door) : null,
                        onDeleteDoor: onDeleteDoor != null ? () => onDeleteDoor!(door) : null,
                        onManagePermissions: onManageDoorPermissions != null ? () => onManageDoorPermissions!(door) : null,
                      ),
                    ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

