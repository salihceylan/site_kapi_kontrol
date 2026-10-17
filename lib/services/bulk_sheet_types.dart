// Tablo dosyası (CSV / XLSX) okuyucularının ortak tipleri ve sınırları (Platform Faz 2b).
//
// Hepsi saf Dart'tır (Flutter'a bağlı değil): ayrıştırma bir isolate'ta çalışır ve testler Flutter olmadan koşar.

/// Okuma / yazma sınırları (docs/PLATFORM_TOPLU_ISLEMLER.md "Okuyucular").
abstract final class SheetLimits {
  /// CSV dosyası üst sınırı.
  static const int maxCsvBytes = 5 * 1024 * 1024;

  /// XLSX (sıkıştırılmış) dosya üst sınırı. Sözleşme yalnız CSV için 5 MB der; XLSX zaten sıkıştırılmıştır ve
  /// yapıdaki görseller dosyayı büyütebilir, bu yüzden 10 MB'a izin verilir (açılmış boyut ayrıca sınırlıdır).
  static const int maxXlsxBytes = 10 * 1024 * 1024;

  /// Sunucunun kabul ettiği en çok VERİ satırı (başlık hariç).
  static const int maxDataRows = 5000;

  /// Başlık aranan ilk dolu satır sayısı.
  static const int headerSearchRows = 10;

  /// Okuyucunun toplayacağı en çok dolu satır: başlık araması + veri + 1 (aşımı fark etmek için) + birkaç
  /// açıklama satırı payı. Aşıldığında okuma DURUR ve [SheetTable.truncated] true olur.
  static const int maxRecords = headerSearchRows + maxDataRows + 1;

  /// En çok sütun (dolu hücre).
  static const int maxColumns = 40;

  /// XLSX zip girdi sayısı.
  static const int maxZipEntries = 300;

  /// XLSX açılmış toplam / girdi başına boyut ve sıkıştırma oranı.
  static const int maxUncompressedTotal = 50 * 1024 * 1024;
  static const int maxUncompressedEntry = 25 * 1024 * 1024;
  static const int maxCompressionRatio = 100;

  /// sharedStrings öğe sayısı.
  static const int maxSharedStrings = 200000;

  /// Bir hücre metni: sunucu sınırı 600; aşımı sunucuda `TOO_LONG` doğurabilsin diye 601'de kesilir.
  static const int cellTextCap = 601;
}

/// Kullanıcıya olduğu gibi gösterilebilen okuma hatası. Teknik ayrıntı içermez.
class SpreadsheetException implements Exception {
  const SpreadsheetException(this.message, {this.code = 'FILE_INVALID'});

  final String message;

  /// Makine kodu: `FILE_TOO_LARGE`, `FILE_TYPE`, `FILE_INVALID`, `FILE_LIMIT`, `FILE_EMPTY`, `NO_HEADER`...
  final String code;

  @override
  String toString() => message;
}

/// XLSX'te tarih biçimli sayısal hücre. Hangi sütunda tarihe çevrileceğine eşleme karar verir.
class SheetDateCell {
  const SheetDateCell(this.serial, {this.date1904 = false});

  final double serial;
  final bool date1904;

  @override
  bool operator ==(Object other) =>
      other is SheetDateCell && other.serial == serial && other.date1904 == date1904;

  @override
  int get hashCode => Object.hash(serial, date1904);

  @override
  String toString() => 'SheetDateCell($serial${date1904 ? ', 1904' : ''})';
}

/// Dosyadaki bir satır. [n] = Excel'de / dosyada görünen 1 tabanlı satır numarası (boş satırlar da sayılır).
/// [cells] değerleri: `String` (kırpılmış, boş değil) | `num` | [SheetDateCell] | `null` (boş).
class SheetRow {
  const SheetRow(this.n, this.cells);

  final int n;
  final List<Object?> cells;

  bool get isBlank => cells.every((c) => c == null);
}

/// Okunmuş sayfa.
class SheetTable {
  const SheetTable({
    required this.rows,
    this.truncated = false,
    this.sheetName,
    this.encodingNote,
    this.delimiter,
    this.uncachedFormulaColumns = const <int, int>{},
  });

  /// Yalnız DOLU satırlar (boşlar atlanmıştır; [SheetRow.n] korunur).
  final List<SheetRow> rows;

  /// [SheetLimits.maxRecords] aşıldı: okuma durdu, sonraki satırlar okunmadı.
  final bool truncated;

  /// XLSX sayfa adı.
  final String? sheetName;

  /// "UTF-8", "Windows-1254 olarak okundu" gibi kullanıcıya bildirilen not.
  final String? encodingNote;

  /// CSV ayırıcısı.
  final String? delimiter;

  /// XLSX: sonucu dosyada KAYITLI olmayan formül hücreleri (bazı üretici kütüphaneler önbellek yazmaz; formül hiç
  /// hesaplanmaz, hücre boş okunur). Sütun indeksi -> hücre sayısı. Boşsa sorun yok.
  final Map<int, int> uncachedFormulaColumns;
}

/// Çalışma kitabındaki seçilebilir sayfa.
class SheetRef {
  const SheetRef({required this.name, required this.index});

  final String name;
  final int index;
}
