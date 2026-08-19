import 'package:site_kapi_kontrol/models/device_record.dart';

class DevicePage {
  const DevicePage({
    required this.devices,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  final List<DeviceRecord> devices;
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
