// XLSX okuyucu (Platform Faz 2b). Kendi uygulamamız: `excel` paketi bilinçli olarak EKLENMEDİ (eski, `archive` /
// `xml` sürümlerini geriletiyor, zip koruması yok; docs/PLATFORM_TOPLU_ISLEMLER.md Karar 2).
//
// Güvenlik (kullanıcının kendi dosyası olsa da kötü niyetli/bozuk dosya cihazı kilitlememeli):
// - Sihirli bayt önce: `PK\x03\x04` zip; `D0CF11E0` eski .xls / parolalı paket -> açık ileti.
// - Zip: girdi sayısı ≤ 300 (dizin sayılmadan ÖNCE, merkezi dizin kaydından); yalnız gereken girdiler okunur
//   (workbook, rels, sharedStrings, styles, seçilen sayfa); HİÇBİR şey diske çıkarılmaz (zip-slip yok); başlıkta
//   bildirilen ve gerçek açılmış boyut toplam ≤ 50 MB / girdi başına ≤ 25 MB; sıkıştırma oranı > 100:1 reddedilir;
//   sharedStrings ≤ 200.000 öğe.
// - XML: olay akışı (tüm ağaç belleğe alınmaz); DOCTYPE reddedilir (varlık genişletme saldırısı yok); sayfa 5011
//   dolu satırdan sonra OKUNMAZ.
// - Formül HİÇ hesaplanmaz: önbellekli sonuç okunur.
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:site_kapi_kontrol/services/bulk_header_mapper.dart' show foldHeader;
import 'package:site_kapi_kontrol/services/bulk_sheet_types.dart';
import 'package:xml/xml_events.dart';

const String _msgBroken =
    'Excel dosyası okunamadı: dosya bozuk ya da desteklenmeyen bir yapıda. Excel\'de «Farklı Kaydet» ile '
    '.xlsx olarak yeniden kaydedin veya CSV kullanın.';

/// Dosyanın türünü ilk baytlarından ayırır.
enum SpreadsheetFileKind { zip, oleCompound, text }

SpreadsheetFileKind sniffFileKind(Uint8List bytes) {
  if (bytes.length >= 4 &&
      bytes[0] == 0x50 &&
      bytes[1] == 0x4B &&
      (bytes[2] == 0x03 || bytes[2] == 0x05) &&
      (bytes[3] == 0x04 || bytes[3] == 0x06)) {
    return SpreadsheetFileKind.zip;
  }
  if (bytes.length >= 4 && bytes[0] == 0xD0 && bytes[1] == 0xCF && bytes[2] == 0x11 && bytes[3] == 0xE0) {
    return SpreadsheetFileKind.oleCompound;
  }
  return SpreadsheetFileKind.text;
}

const String xlsMessage =
    'Eski .xls biçimi (ya da parola korumalı Excel dosyası) desteklenmez. Dosyayı Excel\'de parolasız olarak '
    '.xlsx veya CSV biçiminde kaydedip yükleyin.';

/// Merkezi dizin sonu kaydından girdi sayısını okur (ZipDecoder çalışmadan ÖNCE). Zip64 / bozuk kayıt: null.
int? zipEntryCount(Uint8List bytes) {
  final min = bytes.length - 22;
  if (min < 0) return null;
  final stop = bytes.length - 22 - 65535 < 0 ? 0 : bytes.length - 22 - 65535;
  for (var i = min; i >= stop; i--) {
    if (bytes[i] == 0x50 && bytes[i + 1] == 0x4B && bytes[i + 2] == 0x05 && bytes[i + 3] == 0x06) {
      final total = bytes[i + 10] | (bytes[i + 11] << 8);
      return total;
    }
  }
  return null;
}

const String _msgTooLarge =
    'Excel dosyasının açılmış boyutu çok büyük (en çok 50 MB). Gereksiz görsel ve sayfaları silip yeniden '
    'deneyin.';
const String _msgSuspicious =
    'Excel dosyası olağandışı biçimde sıkıştırılmış ve güvenli görünmüyor. Verileri yeni bir Excel dosyasına '
    'kopyalayıp yeniden deneyin.';
const String _msgTooManyEntries =
    'Excel dosyası beklenenden çok parça içeriyor ve güvenli olmayabilir. Verileri yeni bir Excel dosyasına '
    'kopyalayıp yeniden deneyin.';

/// Merkezi dizini ZipDecoder'dan ÖNCE kendimiz tarar ve tehlikeli dosyayı HİÇBİR ŞEY AÇILMADAN reddeder.
///
/// Neden: archive 4.5.2 `ZipDecoder.decodeBytes`, Unix sembolik bağ bayraklı girdiyi decode sırasında hemen açar
/// (`readBytes`); boyut / oran denetimlerimiz (`decodeBytes` SONRASI) bu yolda geçersiz kalırdı (300 KB'lık dosya
/// 300 MB bellek, 1 MB'lık dosya 2 GB). Tarama archive'ın dizin okumasıyla AYNI kuralı kullanır: sondan ilk
/// EOCD imzası, dizin `[offset, offset+size)` aralığında imza uyuşmayana dek başlıklar (EOCD'deki sayıya güvenilmez).
///
/// Reddedilenler: zip64 işaretleri (0xFFFFFFFF / 0xFFFF / zip64 konumlayıcı); 300'den çok girdi; sembolik bağ; store ve
/// deflate dışı sıkıştırma (bzip2 / zstd / AES); girdi başına bildirilen açılmış boyut > 25 MB; toplam > 50 MB; oran > 100:1.
void inspectZipDirectory(Uint8List bytes) {
  const broken = SpreadsheetException(_msgBroken);
  final length = bytes.length;
  if (length < 22) throw broken;
  final data = ByteData.sublistView(bytes);
  var eocd = -1;
  final stop = length - 22 - 65535 < 0 ? 0 : length - 22 - 65535;
  for (var i = length - 22; i >= stop; i--) {
    if (data.getUint32(i, Endian.little) == 0x06054b50) {
      eocd = i;
      break;
    }
  }
  if (eocd < 0) throw broken;
  if (eocd >= 20 && data.getUint32(eocd - 20, Endian.little) == 0x07064b50) throw broken; // zip64 konumlayıcı
  final declaredCount = data.getUint16(eocd + 10, Endian.little);
  final cdSize = data.getUint32(eocd + 12, Endian.little);
  final cdOffset = data.getUint32(eocd + 16, Endian.little);
  if (declaredCount == 0xFFFF || cdSize == 0xFFFFFFFF || cdOffset == 0xFFFFFFFF) throw broken;
  if (cdOffset + cdSize > length) throw broken;

  var pos = cdOffset;
  final end = cdOffset + cdSize;
  var entries = 0;
  var total = 0;
  while (pos + 46 <= end && data.getUint32(pos, Endian.little) == 0x02014b50) {
    entries++;
    if (entries > SheetLimits.maxZipEntries) {
      throw const SpreadsheetException(_msgTooManyEntries, code: 'FILE_LIMIT');
    }
    final madeBy = data.getUint16(pos + 4, Endian.little);
    final flags = data.getUint16(pos + 8, Endian.little);
    final method = data.getUint16(pos + 10, Endian.little);
    final compressed = data.getUint32(pos + 20, Endian.little);
    final uncompressed = data.getUint32(pos + 24, Endian.little);
    final nameLength = data.getUint16(pos + 28, Endian.little);
    final extraLength = data.getUint16(pos + 30, Endian.little);
    final commentLength = data.getUint16(pos + 32, Endian.little);
    final externalAttributes = data.getUint32(pos + 38, Endian.little);
    final localOffset = data.getUint32(pos + 42, Endian.little);
    if (compressed == 0xFFFFFFFF || uncompressed == 0xFFFFFFFF || localOffset == 0xFFFFFFFF) throw broken;
    // Unix sembolik bağ (st_mode 0xA000): archive bunu decode sırasında HEMEN açar. xlsx'te bağ olmaz.
    if (((externalAttributes >> 16) & 0xF000) == 0xA000 && (madeBy >> 8) == 3) {
      throw const SpreadsheetException(_msgSuspicious, code: 'FILE_LIMIT');
    }
    if ((flags & 0x1) != 0 || (method != 0 && method != 8)) {
      throw const SpreadsheetException(
        'Excel dosyası parola korumalı ya da desteklenmeyen biçimde sıkıştırılmış. Parolasız .xlsx olarak '
        'kaydedip yeniden deneyin.',
        code: 'FILE_TYPE',
      );
    }
    total += uncompressed;
    if (uncompressed > SheetLimits.maxUncompressedEntry || total > SheetLimits.maxUncompressedTotal) {
      throw const SpreadsheetException(_msgTooLarge, code: 'FILE_TOO_LARGE');
    }
    if (uncompressed > 64 * 1024 && (compressed == 0 || uncompressed / compressed > SheetLimits.maxCompressionRatio)) {
      throw const SpreadsheetException(_msgSuspicious, code: 'FILE_LIMIT');
    }
    pos += 46 + nameLength + extraLength + commentLength;
  }
  if (pos > end) throw broken;
}

class XlsxReader {
  XlsxReader._(this._archive, this._sheetPaths, this.sheets, this.date1904);

  final Archive _archive;
  final Map<int, String> _sheetPaths;

  /// Görünür çalışma sayfaları (çalışma kitabı sırasıyla).
  final List<SheetRef> sheets;
  final bool date1904;

  int _totalRead = 0;
  /// Kırpılmış (≤ 601 karakter) paylaşılan dizeler; boş dize null. Aynı dizeye başvuran binlerce hücre AYNI
  /// `String` nesnesini paylaşır (her başvuruda yeni kopya üretilseydi 1 MB'lık dosya yüzlerce MB bellek tutardı).
  List<String?>? _sharedStrings;
  List<bool>? _dateStyles;

  /// [bytes] XLSX'ini açar ve sayfa listesini çıkarır; veri hücrelerini OKUMAZ.
  static XlsxReader open(Uint8List bytes) {
    if (bytes.isEmpty) throw const SpreadsheetException('Dosya boş.', code: 'FILE_EMPTY');
    if (bytes.length > SheetLimits.maxXlsxBytes) {
      throw const SpreadsheetException(
        'Dosya çok büyük (en çok 10 MB). Satırları parçalara bölüp ayrı ayrı yükleyin.',
        code: 'FILE_TOO_LARGE',
      );
    }
    switch (sniffFileKind(bytes)) {
      case SpreadsheetFileKind.oleCompound:
        throw const SpreadsheetException(xlsMessage, code: 'FILE_TYPE');
      case SpreadsheetFileKind.text:
        throw const SpreadsheetException(
          'Bu dosya bir Excel (.xlsx) dosyası değil ya da bozuk. Excel\'den «Farklı Kaydet» ile .xlsx seçin '
          'veya CSV kullanın.',
          code: 'FILE_TYPE',
        );
      case SpreadsheetFileKind.zip:
        break;
    }
    inspectZipDirectory(bytes);
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      return _build(archive);
    } on SpreadsheetException {
      rethrow;
    } on ArchiveException {
      throw const SpreadsheetException(_msgBroken);
    } on Exception {
      throw const SpreadsheetException(_msgBroken);
    } on RangeError {
      throw const SpreadsheetException(_msgBroken);
    } on StateError {
      throw const SpreadsheetException(_msgBroken);
    }
  }

  static XlsxReader _build(Archive archive) {
    if (archive.length > SheetLimits.maxZipEntries) {
      throw const SpreadsheetException(_msgBroken, code: 'FILE_LIMIT');
    }
    var declaredTotal = 0;
    for (final file in archive.files) {
      declaredTotal += file.size;
      if (file.size > SheetLimits.maxUncompressedEntry || declaredTotal > SheetLimits.maxUncompressedTotal) {
        throw const SpreadsheetException(_msgTooLarge, code: 'FILE_TOO_LARGE');
      }
      _checkRatio(file);
    }
    final names = <String>{for (final f in archive.files) f.name};
    if (names.contains('xl/vbaProject.bin')) {
      throw const SpreadsheetException(
        'Makro içeren Excel dosyaları (.xlsm) desteklenmez. Dosyayı makrosuz .xlsx olarak kaydedin.',
        code: 'FILE_TYPE',
      );
    }
    if (names.contains('xl/workbook.bin')) {
      throw const SpreadsheetException(
        'İkili Excel biçimi (.xlsb) desteklenmez. Dosyayı .xlsx ya da CSV olarak kaydedin.',
        code: 'FILE_TYPE',
      );
    }
    if (names.contains('mimetype') || names.contains('content.xml')) {
      throw const SpreadsheetException(
        'OpenDocument (.ods) dosyaları desteklenmez. Dosyayı .xlsx ya da CSV olarak kaydedin.',
        code: 'FILE_TYPE',
      );
    }
    if (!names.contains('xl/workbook.xml')) {
      throw const SpreadsheetException(
        'Bu dosya bir Excel çalışma kitabı gibi görünmüyor. Excel\'den .xlsx olarak kaydedip yeniden deneyin.',
        code: 'FILE_TYPE',
      );
    }
    final probe = XlsxReader._(archive, <int, String>{}, <SheetRef>[], false);
    return probe._readWorkbook();
  }

  static void _checkRatio(ArchiveFile file) {
    if (file.size <= 0) return;
    final compressed = file.rawContent?.length ?? 0;
    if (compressed <= 0) {
      if (file.size > 1024) throw const SpreadsheetException(_msgBroken, code: 'FILE_LIMIT');
      return;
    }
    if (file.size / compressed > SheetLimits.maxCompressionRatio && file.size > 64 * 1024) {
      throw const SpreadsheetException(
        'Excel dosyası olağandışı biçimde sıkıştırılmış ve güvenli görünmüyor. Verileri yeni bir Excel dosyasına '
        'kopyalayıp yeniden deneyin.',
        code: 'FILE_LIMIT',
      );
    }
  }

  ArchiveFile? _find(String name) {
    final exact = _archive.find(name);
    if (exact != null) return exact;
    final lower = name.toLowerCase();
    for (final file in _archive.files) {
      if (file.name.toLowerCase() == lower) return file;
    }
    return null;
  }

  /// Girdiyi açar (boyut sınırlı) ve UTF-8 metin olarak döner; yoksa null.
  String? _readText(String name) {
    final file = _find(name);
    if (file == null || !file.isFile) return null;
    if (file.size > SheetLimits.maxUncompressedEntry) {
      throw const SpreadsheetException(_msgBroken, code: 'FILE_LIMIT');
    }
    _totalRead += file.size;
    if (_totalRead > SheetLimits.maxUncompressedTotal) {
      throw const SpreadsheetException(_msgBroken, code: 'FILE_LIMIT');
    }
    final data = file.readBytes();
    if (data == null) return '';
    if (data.length > SheetLimits.maxUncompressedEntry) {
      throw const SpreadsheetException(_msgBroken, code: 'FILE_LIMIT');
    }
    var start = 0;
    if (data.length >= 3 && data[0] == 0xEF && data[1] == 0xBB && data[2] == 0xBF) start = 3;
    return utf8.decode(Uint8List.sublistView(data, start), allowMalformed: true);
  }

  // --- Çalışma kitabı ---------------------------------------------------------------------------

  XlsxReader _readWorkbook() {
    final workbookXml = _readText('xl/workbook.xml');
    if (workbookXml == null) throw const SpreadsheetException(_msgBroken);
    final relsXml = _readText('xl/_rels/workbook.xml.rels');
    final targets = <String, String>{};
    if (relsXml != null) {
      for (final event in _events(relsXml)) {
        if (event is XmlStartElementEvent && _local(event.name) == 'Relationship') {
          final id = _attr(event, 'Id');
          final type = _attr(event, 'Type') ?? '';
          final target = _attr(event, 'Target');
          final mode = _attr(event, 'TargetMode');
          if (id != null && target != null && mode != 'External' && type.endsWith('/worksheet')) {
            targets[id] = _resolvePath(target);
          }
        }
      }
    }
    var date1904 = false;
    final visible = <SheetRef>[];
    final paths = <int, String>{};
    var position = 0;
    for (final event in _events(workbookXml)) {
      if (event is! XmlStartElementEvent) continue;
      final name = _local(event.name);
      if (name == 'workbookPr') {
        final v = _attr(event, 'date1904');
        date1904 = v == '1' || v == 'true';
      } else if (name == 'sheet') {
        final sheetName = _attr(event, 'name');
        final state = _attr(event, 'state');
        String? rid;
        for (final a in event.attributes) {
          if (_local(a.name) == 'id' && a.name.contains(':')) rid = a.value;
        }
        final path = rid == null ? null : targets[rid];
        position++;
        if (sheetName == null || path == null) continue;
        if (state == 'hidden' || state == 'veryHidden') continue;
        final index = position - 1;
        visible.add(SheetRef(name: sheetName, index: index));
        paths[index] = path;
      }
    }
    if (visible.isEmpty) {
      throw const SpreadsheetException(
        'Excel dosyasında görünür bir çalışma sayfası bulunamadı.',
        code: 'FILE_EMPTY',
      );
    }
    final reader = XlsxReader._(_archive, paths, List<SheetRef>.unmodifiable(visible), date1904);
    reader._totalRead = _totalRead;
    return reader;
  }

  static String _resolvePath(String target) {
    var path = target.startsWith('/') ? target.substring(1) : 'xl/$target';
    final parts = <String>[];
    for (final part in path.split('/')) {
      if (part.isEmpty || part == '.') continue;
      if (part == '..') {
        if (parts.isNotEmpty) parts.removeLast();
        continue;
      }
      parts.add(part);
    }
    path = parts.join('/');
    return path;
  }

  /// Kullanıcıya sorulmadan seçilebilecek sayfa: [preferred] adlarından (katlamalı) biri, yoksa tek sayfa.
  /// Karar verilemezse null (çağıran listeyi gösterir).
  SheetRef? pickSheet(Iterable<String> preferred) {
    final want = <String>{for (final p in preferred) foldHeader(p)};
    for (final sheet in sheets) {
      if (want.contains(foldHeader(sheet.name))) return sheet;
    }
    if (sheets.length == 1) return sheets.first;
    return null;
  }

  // --- Sayfa ------------------------------------------------------------------------------------

  /// [sheet] sayfasını okur. En çok [maxRecords] dolu satır alınır; fazlası varsa [SheetTable.truncated].
  SheetTable readSheet(SheetRef sheet, {int maxRecords = SheetLimits.maxRecords}) {
    final path = _sheetPaths[sheet.index];
    if (path == null) throw const SpreadsheetException(_msgBroken);
    try {
      final shared = _loadSharedStrings();
      final dateStyles = _loadDateStyles();
      final xml = _readText(path);
      if (xml == null) throw const SpreadsheetException(_msgBroken);
      return _parseSheet(xml, sheet.name, shared, dateStyles, maxRecords);
    } on SpreadsheetException {
      rethrow;
    } on Exception {
      throw const SpreadsheetException(_msgBroken);
    } on RangeError {
      throw const SpreadsheetException(_msgBroken);
    } on StateError {
      throw const SpreadsheetException(_msgBroken);
    }
  }

  List<String?> _loadSharedStrings() {
    final cached = _sharedStrings;
    if (cached != null) return cached;
    final xml = _readText('xl/sharedStrings.xml');
    final out = <String?>[];
    if (xml != null && xml.isNotEmpty) {
      var inSi = false;
      var phonetic = 0;
      var inT = false;
      final buffer = StringBuffer();
      for (final event in _events(xml)) {
        if (event is XmlStartElementEvent) {
          final name = _local(event.name);
          if (name == 'si') {
            inSi = true;
            phonetic = 0;
            buffer.clear();
            if (event.isSelfClosing) {
              inSi = false;
              out.add(null);
            }
          } else if (inSi && name == 'rPh') {
            if (!event.isSelfClosing) phonetic++;
          } else if (inSi && name == 't' && phonetic == 0) {
            inT = !event.isSelfClosing;
          }
        } else if (event is XmlEndElementEvent) {
          final name = _local(event.name);
          if (name == 'si' && inSi) {
            inSi = false;
            out.add(_text(buffer.toString()));
            if (out.length > SheetLimits.maxSharedStrings) {
              throw const SpreadsheetException(
                'Excel dosyasındaki metin sayısı çok fazla. Gereksiz verileri silip yeniden deneyin.',
                code: 'FILE_LIMIT',
              );
            }
          } else if (name == 'rPh' && phonetic > 0) {
            phonetic--;
          } else if (name == 't') {
            inT = false;
          }
        } else if (event is XmlTextEvent && inSi && inT && phonetic == 0) {
          buffer.write(event.value);
        } else if (event is XmlCDATAEvent && inSi && inT && phonetic == 0) {
          buffer.write(event.value);
        }
      }
    }
    return _sharedStrings = out;
  }

  List<bool> _loadDateStyles() {
    final cached = _dateStyles;
    if (cached != null) return cached;
    final xml = _readText('xl/styles.xml');
    final styles = <bool>[];
    if (xml != null && xml.isNotEmpty) {
      final customFormats = <int, String>{};
      var inCellXfs = false;
      for (final event in _events(xml)) {
        if (event is XmlStartElementEvent) {
          final name = _local(event.name);
          if (name == 'numFmt') {
            final id = int.tryParse(_attr(event, 'numFmtId') ?? '');
            final code = _attr(event, 'formatCode');
            if (id != null && code != null) customFormats[id] = code;
          } else if (name == 'cellXfs') {
            inCellXfs = !event.isSelfClosing;
          } else if (inCellXfs && name == 'xf') {
            final id = int.tryParse(_attr(event, 'numFmtId') ?? '0') ?? 0;
            styles.add(isDateNumberFormat(id, customFormats[id]));
            if (styles.length > 64000) break;
          }
        } else if (event is XmlEndElementEvent && _local(event.name) == 'cellXfs') {
          inCellXfs = false;
        }
      }
    }
    return _dateStyles = styles;
  }

  SheetTable _parseSheet(
    String xml,
    String sheetName,
    List<String?> shared,
    List<bool> dateStyles,
    int maxRecords,
  ) {
    final rows = <SheetRow>[];
    var truncated = false;

    var inSheetData = false;
    var rowN = 0;
    var autoRow = 0;
    List<Object?>? cells;

    var colIndex = -1;
    String? cellType;
    int style = 0;
    var inV = false;
    var inF = false;
    var inInline = false;
    var inT = false;
    var phonetic = 0;
    var hasFormula = false;
    var sawV = false;
    var lastEmittedRow = 0;
    final uncachedFormulas = <int, int>{};
    final vBuffer = StringBuffer();
    final tBuffer = StringBuffer();

    void finishCell() {
      final value = _cellValue(cellType, vBuffer.toString(), tBuffer.toString(), style, shared, dateStyles);
      vBuffer.clear();
      tBuffer.clear();
      if (value == null) {
        // Formül var ama sonucu kayıtlı değil (hiç `<v>` yok; hata sonucu `t="e"` ve boş dize sonucu `<v/>` sayılmaz).
        if (hasFormula && !sawV && cellType != 'e' && colIndex >= 0 && colIndex < SheetLimits.maxColumns) {
          uncachedFormulas[colIndex] = (uncachedFormulas[colIndex] ?? 0) + 1;
        }
        return;
      }
      if (colIndex >= SheetLimits.maxColumns) {
        throw const SpreadsheetException(
          'Tabloda 40\'tan fazla sütun var. Gereksiz sütunları silip yeniden yükleyin.',
          code: 'FILE_LIMIT',
        );
      }
      final list = cells;
      if (list == null || colIndex < 0) return; // satır dışı / konumsuz hücre
      while (list.length <= colIndex) {
        list.add(null);
      }
      list[colIndex] = value;
    }

    // Satır bittiğinde: dolu ise ekler; sınır aşıldıysa true döner.
    bool finishRow() {
      final list = cells;
      cells = null;
      if (list == null) return false;
      var last = list.length;
      while (last > 0 && list[last - 1] == null) {
        last--;
      }
      if (last == 0) return false;
      // Sunucu `n` değerlerinin artan ve tekil olmasını şart koşar (aksi halde TÜM istek 400); bozuk dosyayı burada
      // açık bir Türkçe iletiyle reddet.
      if (rowN <= lastEmittedRow) {
        throw const SpreadsheetException(
          'Excel dosyasındaki satır numaraları bozuk (sıralı değil ya da yinelenen satırlar var). Dosyayı '
          'Excel içinde açıp «Farklı Kaydet» ile .xlsx olarak yeniden kaydedin.',
        );
      }
      lastEmittedRow = rowN;
      rows.add(SheetRow(rowN, List<Object?>.unmodifiable(list.sublist(0, last))));
      if (rows.length > maxRecords) {
        truncated = true;
        rows.removeLast();
        return true;
      }
      return false;
    }

    outer:
    for (final event in _events(xml)) {
      if (event is XmlStartElementEvent) {
        final name = _local(event.name);
        if (!inSheetData) {
          if (name == 'sheetData') inSheetData = !event.isSelfClosing;
          continue;
        }
        switch (name) {
          case 'row':
            autoRow++;
            final r = int.tryParse(_attr(event, 'r') ?? '');
            rowN = r != null && r > 0 ? r : autoRow;
            autoRow = rowN;
            cells = <Object?>[];
            colIndex = -1;
            if (event.isSelfClosing && finishRow()) break outer;
          case 'c':
            final ref = _attr(event, 'r');
            final parsed = ref == null ? null : _columnIndex(ref);
            colIndex = parsed ?? colIndex + 1;
            cellType = _attr(event, 't');
            style = int.tryParse(_attr(event, 's') ?? '0') ?? 0;
            vBuffer.clear();
            tBuffer.clear();
            inV = false;
            inF = false;
            inInline = false;
            inT = false;
            phonetic = 0;
            hasFormula = false;
            sawV = false;
            if (event.isSelfClosing) finishCell();
          case 'v':
            sawV = true;
            inV = !event.isSelfClosing;
          case 'f':
            hasFormula = true;
            inF = !event.isSelfClosing;
          case 'is':
            inInline = !event.isSelfClosing;
          case 'rPh':
            if (inInline && !event.isSelfClosing) phonetic++;
          case 't':
            if (inInline && phonetic == 0) inT = !event.isSelfClosing;
        }
      } else if (event is XmlEndElementEvent) {
        if (!inSheetData) continue;
        final name = _local(event.name);
        switch (name) {
          case 'sheetData':
            inSheetData = false;
          case 'row':
            if (finishRow()) break outer;
          case 'c':
            finishCell();
            inV = false;
            inF = false;
            inInline = false;
            inT = false;
          case 'v':
            inV = false;
          case 'f':
            inF = false;
          case 'is':
            inInline = false;
            inT = false;
          case 'rPh':
            if (phonetic > 0) phonetic--;
          case 't':
            inT = false;
        }
      } else if (event is XmlTextEvent) {
        if (inV && !inF) {
          vBuffer.write(event.value);
        } else if (inT) {
          tBuffer.write(event.value);
        }
      } else if (event is XmlCDATAEvent) {
        if (inV && !inF) {
          vBuffer.write(event.value);
        } else if (inT) {
          tBuffer.write(event.value);
        }
      }
    }
    return SheetTable(
      rows: List<SheetRow>.unmodifiable(rows),
      truncated: truncated,
      sheetName: sheetName,
      uncachedFormulaColumns: Map<int, int>.unmodifiable(uncachedFormulas),
    );
  }

  Object? _cellValue(
    String? type,
    String v,
    String inline,
    int style,
    List<String?> shared,
    List<bool> dateStyles,
  ) {
    switch (type) {
      case 's':
        final index = int.tryParse(v.trim());
        if (index == null || index < 0 || index >= shared.length) return null;
        return shared[index];
      case 'inlineStr':
        return _text(inline.isNotEmpty ? inline : v);
      case 'str':
        return _text(v);
      case 'b':
        final t = v.trim();
        if (t.isEmpty) return null;
        return t == '1' || t.toLowerCase() == 'true' ? 'DOĞRU' : 'YANLIŞ';
      case 'e':
        return null;
      case 'd':
        final t = v.trim();
        if (t.length >= 10 && RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(t)) return t.substring(0, 10);
        return _text(t);
      default:
        // 'n' ya da tür yok: sayı. Beklenmedik metin (bazı yazıcılar t'siz metin yazar) metin olarak alınır.
        final t = v.trim();
        if (t.isEmpty) return null;
        final number = double.tryParse(t);
        if (number == null || !number.isFinite) return _text(t);
        if (style >= 0 && style < dateStyles.length && dateStyles[style]) {
          return SheetDateCell(number, date1904: date1904);
        }
        return number == number.roundToDouble() && number.abs() < 9007199254740992 ? number.toInt() : number;
    }
  }

  static String? _text(String value) {
    final t = value.trim();
    if (t.isEmpty) return null;
    return t.length > SheetLimits.cellTextCap ? t.substring(0, SheetLimits.cellTextCap) : t;
  }

  // --- Yardımcılar ------------------------------------------------------------------------------

  static Iterable<XmlEvent> _events(String xml) sync* {
    for (final event in parseEvents(xml)) {
      if (event is XmlDoctypeEvent) {
        throw const SpreadsheetException(
          'Excel dosyası güvenli görünmüyor (beklenmeyen tanım). Verileri yeni bir Excel dosyasına kopyalayıp '
          'yeniden deneyin.',
          code: 'FILE_LIMIT',
        );
      }
      yield event;
    }
  }

  static String _local(String name) {
    final i = name.indexOf(':');
    return i < 0 ? name : name.substring(i + 1);
  }

  static String? _attr(XmlStartElementEvent event, String local) {
    for (final a in event.attributes) {
      if (a.name == local) return a.value;
    }
    for (final a in event.attributes) {
      if (_local(a.name) == local) return a.value;
    }
    return null;
  }

  /// "AB12" -> 27 (0 tabanlı sütun); geçersizse null.
  static int? _columnIndex(String ref) {
    var value = 0;
    var letters = 0;
    for (var i = 0; i < ref.length; i++) {
      final c = ref.codeUnitAt(i);
      if (c >= 0x41 && c <= 0x5A) {
        value = value * 26 + (c - 0x40);
      } else if (c >= 0x61 && c <= 0x7A) {
        value = value * 26 + (c - 0x60);
      } else {
        break;
      }
      letters++;
      if (letters > 3) return null;
    }
    if (letters == 0 || value > 16384) return null;
    return value - 1;
  }
}

/// Excel sayı biçimi tarih mi? Yerleşik kimlikler + özel biçim kodu sezgisi.
bool isDateNumberFormat(int id, String? code) {
  if (code == null) {
    return (id >= 14 && id <= 17) || id == 22 || (id >= 27 && id <= 36) || (id >= 50 && id <= 58);
  }
  var c = code;
  // Tırnaklı metin, kaçışlı karakter ve köşeli parantezli bölümler ([Red], [$-409]) çıkarılır.
  c = c.replaceAll(RegExp(r'"[^"]*"'), '');
  c = c.replaceAll(RegExp(r'\\.'), '');
  c = c.replaceAll(RegExp(r'\[[^\]]*\]'), '');
  c = c.replaceAll(RegExp('general', caseSensitive: false), '');
  c = c.replaceAll(RegExp(r'_.'), '');
  c = c.replaceAll(RegExp(r'\*.'), '');
  final lower = c.toLowerCase();
  // Tarih öğesi: gün, ay ya da yıl (saat / dakika / saniye tek başına zaman biçimidir).
  return RegExp(r'[dy]').hasMatch(lower) || (RegExp('m').hasMatch(lower) && !RegExp(r'[hs]').hasMatch(lower));
}
