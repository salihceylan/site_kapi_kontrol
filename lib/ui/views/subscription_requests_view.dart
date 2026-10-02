import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/subscription_request.dart';
import 'package:site_kapi_kontrol/models/subscription_request_page.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/motion_widgets.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/ui_helpers.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/subscription_request_card.dart';

class SubscriptionRequestsView extends StatelessWidget {
  const SubscriptionRequestsView({
    super.key,
    required this.pageData,
    required this.requests,
    required this.busyRequests,
    required this.isLoading,
    required this.onRefresh,
    required this.onLoadPage,
    required this.onApprove,
    required this.onReject,
  });

  final SubscriptionRequestPage? pageData;
  final List<SubscriptionRequest> requests;
  final Set<int> busyRequests;
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
        const PageHeaderCard(title: 'Yeni Abonelik Talepleri'),
        const SizedBox(height: AppSpace.lg),
        // Liste bölümü: başlık sayfa zemininde, her talep kendi AppCard'ı (kart-içinde-kart yok).
        SectionHeader(
          title: page == null
              ? 'Bekleyen Talepler'
              : 'Bekleyen Talepler (${page.total})',
          trailing: IconButton(
            onPressed: isLoading ? null : onRefresh,
            icon: const Icon(Icons.refresh),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        if (isLoading && page == null)
          const ListSkeleton()
        else if (requests.isEmpty)
          const EmptyCard(
            icon: Icons.mark_email_read_outlined,
            title: 'Doğrulanmış yeni abonelik talebi yok.',
          )
        else ...[
          for (var i = 0; i < requests.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.md),
              child: StaggeredEntry(
                index: i,
                child: SubscriptionRequestCard(
                  request: requests[i],
                  busy: busyRequests.contains(requests[i].id),
                  formattedCreatedAt: formatDateTime(requests[i].createdAt),
                  onApprove: () => onApprove(requests[i].id),
                  onReject: () => onReject(requests[i].id),
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
