import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/bulk_import.dart';
import 'package:site_kapi_kontrol/ui/helpers/list_export.dart';

void main() {
  test('yerel kaynak başlık ve satırlarla zarf üretir; tarih gg.aa.yyyy', () async {
    final source = localExportSource(
      label: 'Duyurular',
      filenameBase: 'duyurular',
      headers: <String>['Başlık', 'Tarih'],
      rows: () => <List<Object?>>[
        <Object?>['Su kesintisi', exportDate(DateTime(2026, 10, 5))],
      ],
    );
    final env = await source.fetch(ExportFormat.xlsx);
    expect(env.columns.map((c) => c.label), <String>['Başlık', 'Tarih']);
    expect(env.rows.single, <Object?>['Su kesintisi', '05.10.2026']);
    expect(exportDate(null), '');
  });
}
