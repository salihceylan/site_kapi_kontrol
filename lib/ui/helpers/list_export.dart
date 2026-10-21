import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/bulk_import.dart';
import 'package:site_kapi_kontrol/ui/widgets/bulk_export_sheet.dart';

// Ekranda yüklü liste için «Excel'e aktar» (G10/R3). Dosyayı istemci üretir (mevcut ExportSheet ve
// biçimleyici; formül kaçışı tek yerde). Yalnız ekranda YÜKLENMİŞ kayıtlar yazılır; süzgeç/arama
// uygulanmış listeyi olduğu gibi verir.

/// `gg.aa.yyyy` (yerel saat); null ise boş.
String exportDate(DateTime? value) {
  if (value == null) return '';
  final d = value.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}.${two(d.month)}.${d.year}';
}

/// `gg.aa.yyyy ss:dd`; null ise boş.
String exportDateTime(DateTime? value) {
  if (value == null) return '';
  final d = value.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${exportDate(d)} ${two(d.hour)}:${two(d.minute)}';
}

/// Metin sütunlarından oluşan yerel kaynak. [rows] her çağrıda okunur (güncel liste).
ExportSource localExportSource({
  required String label,
  required String filenameBase,
  required List<String> headers,
  required List<List<Object?>> Function() rows,
  String? filterSummary,
}) {
  return ExportSource(
    label: label,
    sheetName: label,
    filterSummary: filterSummary,
    fetch: (format) async {
      final data = rows();
      return ExportEnvelope(
        kind: filenameBase,
        filenameBase: filenameBase,
        columns: <ExportColumn>[
          for (var i = 0; i < headers.length; i++) ExportColumn(key: 'c$i', label: headers[i]),
        ],
        rows: data,
        generatedAt: DateTime.now(),
      );
    },
  );
}

/// «Excel'e aktar» düğmesi; liste boşken pasif.
class ListExportButton extends StatelessWidget {
  const ListExportButton({super.key, required this.source, required this.enabled});

  final ExportSource source;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: const ValueKey<String>('list_export_excel'),
      tooltip: enabled ? "Excel'e aktar" : 'Aktarılacak kayıt yok',
      icon: const Icon(Icons.table_chart_rounded),
      onPressed: enabled
          ? () => ExportSheet.show(context, sources: <ExportSource>[source], title: "Excel'e aktar")
          : null,
    );
  }
}
