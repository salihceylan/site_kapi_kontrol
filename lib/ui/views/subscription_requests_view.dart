import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/subscription_request.dart';
import 'package:site_kapi_kontrol/models/subscription_request_page.dart';
import 'package:site_kapi_kontrol/styles/app_colors.dart';
import 'package:site_kapi_kontrol/styles/app_decorations.dart';
import 'package:site_kapi_kontrol/ui/helpers/ui_helpers.dart';
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: AppDecorations.glassCard,
          child: const Text(
            'Yeni Abonelik Talepleri',
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
          decoration: AppDecorations.glassCard,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      pageData == null
                          ? 'Bekleyen Talepler'
                          : 'Bekleyen Talepler (${pageData!.total})',
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
              else if (requests.isEmpty)
                const Text('Doğrulanmış yeni abonelik talebi yok.')
              else ...[
                for (final request in requests)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: SubscriptionRequestCard(
                      request: request,
                      busy: busyRequests.contains(request.id),
                      formattedCreatedAt: formatDateTime(request.createdAt),
                      onApprove: () => onApprove(request.id),
                      onReject: () => onReject(request.id),
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

