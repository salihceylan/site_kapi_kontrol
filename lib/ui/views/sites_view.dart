import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/apartment_record.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/models/site_page.dart';
import 'package:site_kapi_kontrol/models/site_record.dart';
import 'package:site_kapi_kontrol/models/site_structure_record.dart';
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
    this.onDeleteApartmentResident,
    this.onDownloadCredentialsPdf,
    this.onDownloadLogsPdf,
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
  final ValueChanged<ApartmentRecord> onEditApartmentResident;
  final ValueChanged<ApartmentRecord> onSendApartmentMail;
  final ValueChanged<DoorRecord> onAssignDoorDevice;
  final ValueChanged<ApartmentRecord>? onDeleteApartmentResident;
  final ValueChanged<SiteRecord>? onDownloadCredentialsPdf;
  final ValueChanged<SiteRecord>? onDownloadLogsPdf;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 680;
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
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
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
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.textDark,
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
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
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
                      onDownloadPdf: onDownloadCredentialsPdf != null
                          ? () => onDownloadCredentialsPdf!(site)
                          : null,
                      onDownloadLogsPdf: onDownloadLogsPdf != null
                          ? () => onDownloadLogsPdf!(site)
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
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
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
                          foregroundColor: const Color(0xFF1E3A8A),
                          side: const BorderSide(color: Color(0xFF93C5FD)),
                        ),
                        icon: const Icon(Icons.picture_as_pdf_outlined),
                        label: const Text('Şifreleri İndir (PDF)'),
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
                const Text(
                  'Daireler',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
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
                const Text(
                  'Kapılar',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
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

