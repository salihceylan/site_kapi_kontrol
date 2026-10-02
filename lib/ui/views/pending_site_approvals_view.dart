import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/site_page.dart';
import 'package:site_kapi_kontrol/models/site_record.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/motion_widgets.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/ui_helpers.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/site_approval_request_card.dart';

class PendingSiteApprovalsView extends StatelessWidget {
  const PendingSiteApprovalsView({
    super.key,
    required this.pageData,
    required this.sites,
    required this.busySiteApprovals,
    required this.isLoading,
    required this.onRefresh,
    required this.onLoadPage,
    required this.onApprove,
    required this.onReject,
  });

  final SitePage? pageData;
  final List<SiteRecord> sites;
  final Set<int> busySiteApprovals;
  final bool isLoading;
  final VoidCallback onRefresh;
  final ValueChanged<int> onLoadPage;
  final ValueChanged<int> onApprove;
  final ValueChanged<int> onReject;

  @override
  Widget build(BuildContext context) {
    final page = pageData;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageHeaderCard(title: 'Site Onay Talepleri'),
        const SizedBox(height: AppSpace.lg),
        // Liste bölümü: başlık sayfa zemininde, her talep kendi AppCard'ı (kart-içinde-kart yok).
        SectionHeader(
          title: page == null
              ? 'Bekleyen Siteler'
              : 'Bekleyen Siteler (${page.total})',
          trailing: IconButton(
            onPressed: isLoading ? null : onRefresh,
            icon: const Icon(Icons.refresh),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        if (isLoading && page == null)
          const ListSkeleton()
        else if (sites.isEmpty)
          const EmptyCard(
            icon: Icons.fact_check_outlined,
            title: 'Bekleyen site onay talebi yok.',
          )
        else ...[
          for (var i = 0; i < sites.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.md),
              child: StaggeredEntry(
                index: i,
                child: SiteApprovalRequestCard(
                  site: sites[i],
                  busy: busySiteApprovals.contains(sites[i].id),
                  formattedCreatedAt: formatDateTime(sites[i].createdAt),
                  onApprove: () => onApprove(sites[i].id),
                  onReject: () => onReject(sites[i].id),
                ),
              ),
            ),
          PaginationBar(
            label:
                'Sayfa ${page?.page ?? 1} / ${page?.totalPages ?? 1} | Toplam ${page?.total ?? 0}',
            onPrevious: (page?.page ?? 1) > 1
                ? () => onLoadPage((page?.page ?? 1) - 1)
                : null,
            onNext: (page?.page ?? 1) < (page?.totalPages ?? 1)
                ? () => onLoadPage((page?.page ?? 1) + 1)
                : null,
          ),
        ],
      ],
    );
  }
}
