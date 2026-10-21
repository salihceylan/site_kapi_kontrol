// Sayaç okuma dosyası (CSV / XLSX) -> { kod, değer } satırları. Saf Dart (UI'siz): mevcut toplu yükleme okuyucularını kullanır.
//
// Biçim: ilk sütun daire kodu (ör. "A Blok - 5") YA DA sayaç seri numarası, ikinci sütun okuma değeri. İlk satır başlıksa
// ("Daire kodu", "Değer"/"Okuma"/"Endeks" gibi) otomatik atlanır; başlıkta sütun adları varsa sütunlar adlarından bulunur.
import 'dart:typed_data';

import 'package:site_kapi_kontrol/services/bulk_csv_codec.dart';
import 'package:site_kapi_kontrol/services/bulk_sheet_types.dart';
import 'package:site_kapi_kontrol/services/bulk_text_decoder.dart';
import 'package:site_kapi_kontrol/services/bulk_xlsx_reader.dart';

/// Dosyadan okunan tek satır; [n] dosyadaki satır numarası.
class MeterFileRow {
  const MeterFileRow({required this.n, required this.code, required this.value});

  final int n;
  final String code;
  final String value;

  Map<String, dynamic> toJson() => <String, dynamic>{'n': n, 'code': code, 'value': value};
}

/// Okuma sonucu: ya [rows] ya da düz Türkçe [error].
class MeterFileRead {
  const MeterFileRead.rows(this.rows) : error = null;
  const MeterFileRead.failure(this.error) : rows = const <MeterFileRow>[];

  final List<MeterFileRow> rows;
  final String? error;
}

/// Sunucunun bir seferde kabul ettiği en çok satır.
const int meterImportMaxRows = 5000;

String _cellText(Object? cell) {
  if (cell == null) return '';
  if (cell is num) {
    if (cell is int || cell == cell.truncateToDouble()) return cell.truncate().toString();
    return cell.toString();
  }
  if (cell is SheetDateCell) return '';
  return cell.toString().trim();
}

bool _looksNumeric(String text) => RegExp(r'^\d{1,11}([.,]\d{1,3})?$').hasMatch(text.trim());

/// Dosya baytlarını okur. Hata fırlatmaz; [MeterFileRead.failure] döner.
MeterFileRead readMeterFile(Uint8List bytes, String fileName) {
  try {
    final lower = fileName.toLowerCase();
    if (!lower.endsWith('.csv') && !lower.endsWith('.xlsx')) {
      return const MeterFileRead.failure('Yalnız .xlsx ve .csv dosyaları yüklenebilir.');
    }
    if (bytes.isEmpty) return const MeterFileRead.failure('Dosya boş.');
    final SheetTable table;
    switch (sniffFileKind(bytes)) {
      case SpreadsheetFileKind.oleCompound:
        return const MeterFileRead.failure('Eski .xls biçimi desteklenmez. Dosyayı .xlsx ya da CSV olarak kaydedin.');
      case SpreadsheetFileKind.zip:
        final reader = XlsxReader.open(bytes);
        if (reader.sheets.isEmpty) return const MeterFileRead.failure('Dosyada okunacak sayfa yok.');
        table = reader.readSheet(reader.sheets.first);
      case SpreadsheetFileKind.text:
        if (bytes.length > SheetLimits.maxCsvBytes) return const MeterFileRead.failure('Dosya çok büyük (en çok 5 MB).');
        final decoded = decodeSpreadsheetText(bytes);
        table = parseCsvText(decoded.text, encodingNote: decoded.note);
    }
    final rows = table.rows.where((r) => !r.isBlank).toList();
    if (rows.isEmpty) return const MeterFileRead.failure('Dosyada okunacak satır yok.');
    var codeCol = 0;
    var valueCol = 1;
    var start = 0;
    final first = rows.first.cells.map(_cellText).toList();
    final firstValue = first.length > 1 ? first[1] : '';
    if (!_looksNumeric(firstValue)) {
      // Başlık satırı: sütunları adlarından bul (yoksa 0 ve 1).
      for (var i = 0; i < first.length; i++) {
        final name = first[i].toLowerCase();
        if (RegExp(r'kod|daire|seri|sayaç|sayac').hasMatch(name)) {
          codeCol = i;
          break;
        }
      }
      for (var i = 0; i < first.length; i++) {
        final name = first[i].toLowerCase();
        if (i != codeCol && RegExp(r'değer|deger|okuma|endeks|index').hasMatch(name)) {
          valueCol = i;
          break;
        }
      }
      start = 1;
    }
    final result = <MeterFileRow>[];
    for (final row in rows.skip(start)) {
      final cells = row.cells;
      final code = codeCol < cells.length ? _cellText(cells[codeCol]) : '';
      final value = valueCol < cells.length ? _cellText(cells[valueCol]) : '';
      if (code.isEmpty && value.isEmpty) continue;
      result.add(MeterFileRow(n: row.n, code: code, value: value));
    }
    if (result.isEmpty) return const MeterFileRead.failure('Dosyada okuma satırı bulunamadı. İlk sütun daire kodu ya da seri numarası, ikinci sütun okuma değeri olmalıdır.');
    if (table.truncated || result.length > meterImportMaxRows) {
      return const MeterFileRead.failure('Dosyada $meterImportMaxRows satırdan fazla veri var. Dosyayı parçalara bölüp ayrı ayrı yükleyin.');
    }
    return MeterFileRead.rows(result);
  } on SpreadsheetException catch (e) {
    return MeterFileRead.failure(e.message);
  } on Object {
    return const MeterFileRead.failure('Dosya okunamadı. Dosya bozuk olabilir; yeniden kaydedip tekrar deneyin.');
  }
}
