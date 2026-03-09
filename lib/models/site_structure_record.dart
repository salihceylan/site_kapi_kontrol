import 'package:site_kapi_kontrol/models/apartment_record.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/models/site_block_record.dart';
import 'package:site_kapi_kontrol/models/site_record.dart';

class SiteStructureRecord {
  const SiteStructureRecord({
    required this.site,
    required this.blocks,
    required this.apartments,
    required this.doors,
  });

  final SiteRecord site;
  final List<SiteBlockRecord> blocks;
  final List<ApartmentRecord> apartments;
  final List<DoorRecord> doors;

  factory SiteStructureRecord.fromJson(Map<String, dynamic> json) {
    return SiteStructureRecord(
      site: SiteRecord.fromJson(json['site'] as Map<String, dynamic>),
      blocks: (json['blocks'] as List<dynamic>? ?? const <dynamic>[])
          .map((item) => SiteBlockRecord.fromJson(item as Map<String, dynamic>))
          .toList(),
      apartments: (json['apartments'] as List<dynamic>? ?? const <dynamic>[])
          .map((item) => ApartmentRecord.fromJson(item as Map<String, dynamic>))
          .toList(),
      doors: (json['doors'] as List<dynamic>? ?? const <dynamic>[])
          .map((item) => DoorRecord.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}
