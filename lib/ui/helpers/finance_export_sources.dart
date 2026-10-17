import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_4b_access.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/widgets/bulk_export_sheet.dart';

/// Finans dışa aktarma kaynağı (Platform Faz 4b, "Dış bağımlılık arayüzleri"): `GET finance/exports/:kind` zarfını
/// Faz 2b'nin ortak [ExportSource] / [ExportSheet] altyapısıyla DEĞİŞMEDEN kullanır. Dosyayı İSTEMCİ üretir (CSV
/// formül kaçışı tek yerde); sunucu yalnız ham zarfı verir. Yalnız yönetici / süper kullanıcı: kurul 403 alır (bu yüzden
/// kurul ekranlarında "Dışa Aktar" düğmesi çizilmez). `format` yalnız denetim kaydı içindir.
///
/// [kind]: `finance_aging`, `finance_income_expense`, `finance_cash_position`, `finance_statement`, `finance_expenses`,
/// `finance_receipts`. [query]: ekrandaki UYGULANMIŞ süzgeçler (ekranla dosya arasında sapma olmasın).
ExportSource financeExportSource({
  required PeopleScope scope,
  required String label,
  required String kind,
  Map<String, String> query = const <String, String>{},
  String? filterSummary,
  IconData icon = Icons.table_chart_rounded,
  String? sheetName,
}) {
  return ExportSource(
    label: label,
    icon: icon,
    sheetName: sheetName ?? label,
    filterSummary: filterSummary,
    fetch: (format) => scope.f4Call(
      (api, token, site) => api.getExport(
        token: token,
        siteCode: site,
        kind: kind,
        query: <String, String>{...query, 'format': format.apiValue},
      ),
    ),
  );
}

/// Dışa aktarma alt sayfasını açan işlev. Varsayılan [ExportSheet.show]; testler yakalamak için değiştirir.
typedef FinanceExportLauncher = Future<void> Function(BuildContext context, List<ExportSource> sources);

Future<void> defaultFinanceExportLauncher(BuildContext context, List<ExportSource> sources) =>
    ExportSheet.show(context, sources: sources, title: 'Dışa Aktar');
