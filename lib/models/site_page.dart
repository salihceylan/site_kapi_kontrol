import 'package:site_kapi_kontrol/models/site_record.dart';

class SitePage {
  const SitePage({
    required this.sites,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  final List<SiteRecord> sites;
  final int total;
  final int page;
  final int pageSize;

  SitePage copyWith({
    List<SiteRecord>? sites,
    int? total,
    int? page,
    int? pageSize,
  }) {
    return SitePage(
      sites: sites ?? this.sites,
      total: total ?? this.total,
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
    );
  }

  int get totalPages {
    if (total <= 0) {
      return 1;
    }
    return ((total - 1) ~/ pageSize) + 1;
  }
}
