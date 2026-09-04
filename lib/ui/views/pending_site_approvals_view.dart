import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/site_page.dart';
import 'package:site_kapi_kontrol/models/site_record.dart';
import 'package:site_kapi_kontrol/styles/app_colors.dart';
import 'package:site_kapi_kontrol/styles/app_decorations.dart';
import 'package:site_kapi_kontrol/ui/helpers/ui_helpers.dart';
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: AppDecorations.glassCard(context),
          child: const Text(
            'Site Onay Talepleri',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
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
                          ? 'Bekleyen Siteler'
                          : 'Bekleyen Siteler (${pageData!.total})',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: isLoading ? null : onRefresh,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (isLoading && pageData == null)
                const Center(child: CircularProgressIndicator())
              else if (sites.isEmpty)
                const Text('Bekleyen site onay talebi yok.')
              else ...[
                for (final site in sites)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: SiteApprovalRequestCard(
                      site: site,
                      busy: busySiteApprovals.contains(site.id),
                      formattedCreatedAt: formatDateTime(site.createdAt),
                      onApprove: () => onApprove(site.id),
                      onReject: () => onReject(site.id),
                    ),
                  ),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Sayfa ${pageData?.page ?? 1} / ${pageData?.totalPages ?? 1} | Toplam ${pageData?.total ?? 0}',
                    ),
                    OutlinedButton(
                      onPressed: (pageData?.page ?? 1) > 1
                          ? () => onLoadPage((pageData?.page ?? 1) - 1)
                          : null,
                      child: const Icon(Icons.chevron_left),
                    ),
                    OutlinedButton(
                      onPressed: (pageData?.page ?? 1) <
                              (pageData?.totalPages ?? 1)
                          ? () => onLoadPage((pageData?.page ?? 1) + 1)
                          : null,
                      child: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

