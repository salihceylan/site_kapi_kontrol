import 'package:site_kapi_kontrol/models/subscription_request.dart';

class SubscriptionRequestPage {
  const SubscriptionRequestPage({
    required this.requests,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  final List<SubscriptionRequest> requests;
  final int total;
  final int page;
  final int pageSize;

  int get totalPages {
    if (total <= 0) {
      return 1;
    }
    return ((total - 1) ~/ pageSize) + 1;
  }
}
