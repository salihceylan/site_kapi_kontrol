import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/bulk_import.dart';
import 'package:site_kapi_kontrol/models/residency_relation.dart';
import 'package:site_kapi_kontrol/services/bulk_api.dart';
import 'package:site_kapi_kontrol/ui/widgets/bulk_export_sheet.dart';

/// Kişiler ekranının üç dışa aktarma kaynağı (Kişiler | Daireler | Araçlar — sekme sırasıyla). Süzgeçler açık
/// sekmenin güncel arama / süzgecidir ve sayfa açılırken bir kez okunur ([ExportSheet] TÜM sayfaları indirir).
List<ExportSource> buildCrmExportSources({
  required BulkService service,
  required int siteCode,
  BulkExportFilters Function()? persons,
  BulkExportFilters Function()? apartments,
  BulkExportFilters Function()? vehicles,
}) {
  final personFilters = persons?.call() ?? const BulkExportFilters();
  final apartmentFilters = apartments?.call() ?? const BulkExportFilters();
  final vehicleFilters = vehicles?.call() ?? const BulkExportFilters();
  return <ExportSource>[
    ExportSource(
      label: 'Kişiler',
      icon: Icons.groups_2_rounded,
      sheetName: 'Kişiler',
      filterSummary: personFilters.summary(
        kind: ImportKind.people,
        relationLabel: ResidencyRelation.tryParse(personFilters.relation)?.label,
      ),
      notesLabel: 'Yönetici notlarını da ekle',
      fetch: (format) => service.exportData(siteCode, kind: 'people', filters: personFilters, format: format),
      fetchWithNotes: (format, notes) =>
          service.exportData(siteCode, kind: 'people', filters: personFilters, format: format, includeNotes: notes),
    ),
    ExportSource(
      label: 'Daireler',
      icon: Icons.apartment_rounded,
      sheetName: 'Daireler',
      filterSummary: apartmentFilters.summary(kind: ImportKind.apartments),
      fetch: (format) => service.exportData(siteCode, kind: 'apartments', filters: apartmentFilters, format: format),
    ),
    ExportSource(
      label: 'Araçlar',
      icon: Icons.directions_car_rounded,
      sheetName: 'Araçlar',
      filterSummary: vehicleFilters.summary(kind: ImportKind.vehicles),
      notesLabel: 'Araç notlarını da ekle',
      fetch: (format) => service.exportData(siteCode, kind: 'vehicles', filters: vehicleFilters, format: format),
      fetchWithNotes: (format, notes) => service.exportData(
        siteCode,
        kind: 'vehicles',
        filters: vehicleFilters,
        format: format,
        includeNotes: notes,
      ),
    ),
  ];
}
