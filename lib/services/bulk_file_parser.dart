// Dosya -> tablo -> başlık eşleme hattı (Platform Faz 2b).
//
// [runParse] SAF bir üst düzey işlevdir ve ana iş parçacığını dondurmamak için bir isolate'ta çalıştırılır
// ([parseInBackground] -> `compute`; web'de ana iş parçacığında, `compute` oraya düşer). Hatalar fırlatılmaz,
// [ParseFailed] olarak DÖNER: isolate sınırından geçen özel istisnaların sınıf bilgisi kaybolmasın.
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:site_kapi_kontrol/models/bulk_import.dart';
import 'package:site_kapi_kontrol/services/bulk_csv_codec.dart';
import 'package:site_kapi_kontrol/services/bulk_header_mapper.dart';
import 'package:site_kapi_kontrol/services/bulk_sheet_types.dart';
import 'package:site_kapi_kontrol/services/bulk_text_decoder.dart';
import 'package:site_kapi_kontrol/services/bulk_xlsx_reader.dart';

/// Ayrıştırma isteği (isolate'a gönderilebilir: yalnız düz veri).
class ParseRequest {
  const ParseRequest({
    required this.bytes,
    required this.fileName,
    required this.kind,
    required this.spec,
    this.sheetName,
  });

  final Uint8List bytes;
  final String fileName;
  final ImportKind kind;
  final ImportSpec spec;

  /// Kullanıcının listeden seçtiği sayfa (yoksa otomatik seçilir).
  final String? sheetName;
}

sealed class ParseOutcome {
  const ParseOutcome();
}

/// Dosya okundu ve başlık bulundu.
class ParseDone extends ParseOutcome {
  const ParseDone({
    required this.table,
    required this.header,
    required this.isXlsx,
    this.suggestedKind,
    this.sheetNames = const <String>[],
  });

  final SheetTable table;
  final HeaderSearch header;
  final bool isXlsx;

  /// Başlıklara daha çok uyan başka bir tür (yanlış tür seçimi uyarısı).
  final ImportKind? suggestedKind;

  /// XLSX'teki görünür sayfa adları (sayfa değiştirme için).
  final List<String> sheetNames;
}

/// Birden çok sayfa var ve hangisinin yükleneceği belli değil.
class ParseNeedsSheet extends ParseOutcome {
  const ParseNeedsSheet(this.sheetNames);

  final List<String> sheetNames;
}

class ParseFailed extends ParseOutcome {
  const ParseFailed(this.message, {this.code = 'FILE_INVALID'});

  final String message;
  final String code;
}

/// Uzantıya göre erken ret (içerik ayrıca denetlenir). Kabul: null.
String? rejectedExtensionMessage(String fileName) {
  final dot = fileName.lastIndexOf('.');
  if (dot < 0 || dot == fileName.length - 1) return null;
  final ext = fileName.substring(dot + 1).toLowerCase();
  switch (ext) {
    case 'xlsx':
    case 'csv':
      return null;
    case 'xls':
      return xlsMessage;
    case 'xlsm':
      return 'Makro içeren Excel dosyaları (.xlsm) desteklenmez. Dosyayı makrosuz .xlsx olarak kaydedin.';
    case 'xlsb':
      return 'İkili Excel biçimi (.xlsb) desteklenmez. Dosyayı .xlsx ya da CSV olarak kaydedin.';
    case 'ods':
      return 'OpenDocument (.ods) dosyaları desteklenmez. Dosyayı .xlsx ya da CSV olarak kaydedin.';
  }
  return 'Yalnız .xlsx ve .csv dosyaları yüklenebilir.';
}

const String _noHeaderMessage =
    'Başlık satırı bulunamadı. İlk 10 satırda en az iki sütun başlığı (örneğin «Blok», «Daire No») olmalı. '
    'Şablonu indirip kullanın ya da başlıkları kontrol edin.';

/// Dosyayı okur. Saf ve eşzamanlıdır; isolate'ta çalıştırılması çağıranın işidir.
ParseOutcome runParse(ParseRequest request) {
  try {
    return _parse(request);
  } on SpreadsheetException catch (e) {
    return ParseFailed(e.message, code: e.code);
  } on Exception {
    return const ParseFailed(
      'Dosya okunamadı. Dosya bozuk olabilir; yeniden kaydedip tekrar deneyin.',
    );
  } on RangeError {
    return const ParseFailed(
      'Dosya okunamadı. Dosya bozuk olabilir; yeniden kaydedip tekrar deneyin.',
    );
  } on StateError {
    return const ParseFailed(
      'Dosya okunamadı. Dosya bozuk olabilir; yeniden kaydedip tekrar deneyin.',
    );
  }
}

ParseOutcome _parse(ParseRequest request) {
  final byName = rejectedExtensionMessage(request.fileName);
  if (byName != null) return ParseFailed(byName, code: 'FILE_TYPE');
  final bytes = request.bytes;
  if (bytes.isEmpty) return const ParseFailed('Dosya boş.', code: 'FILE_EMPTY');

  final kindSpec = request.spec.of(request.kind);
  if (kindSpec == null) return const ParseFailed('Bu tür için şablon bilgisi alınamadı.');

  final fileKind = sniffFileKind(bytes);
  final SheetTable table;
  final bool isXlsx;
  var sheetNames = const <String>[];
  switch (fileKind) {
    case SpreadsheetFileKind.oleCompound:
      return const ParseFailed(xlsMessage, code: 'FILE_TYPE');
    case SpreadsheetFileKind.zip:
      isXlsx = true;
      final reader = XlsxReader.open(bytes);
      sheetNames = <String>[for (final s in reader.sheets) s.name];
      SheetRef? sheet;
      final wanted = request.sheetName;
      if (wanted != null) {
        for (final s in reader.sheets) {
          if (s.name == wanted) sheet = s;
        }
        if (sheet == null) return const ParseFailed('Seçilen sayfa dosyada bulunamadı.');
      } else {
        sheet = reader.pickSheet(<String>[request.kind.sheetName]);
        if (sheet == null) return ParseNeedsSheet(sheetNames);
      }
      table = reader.readSheet(sheet);
    case SpreadsheetFileKind.text:
      isXlsx = false;
      if (bytes.length > SheetLimits.maxCsvBytes) {
        return const ParseFailed(
          'Dosya çok büyük (en çok 5 MB). Satırları parçalara bölüp ayrı ayrı yükleyin.',
          code: 'FILE_TOO_LARGE',
        );
      }
      final decoded = decodeSpreadsheetText(bytes);
      table = parseCsvText(decoded.text, encodingNote: decoded.note);
  }
  if (table.rows.isEmpty) {
    return const ParseFailed('Dosyada okunacak satır yok.', code: 'FILE_EMPTY');
  }
  final header = detectHeader(table, kindSpec);
  if (header == null) {
    // Başka bir türün başlıkları varsa onu söyle: kullanıcı yanlış tür seçmiş olabilir.
    final other = suggestBetterKind(table, request.spec, request.kind);
    if (other != null) {
      return ParseFailed(
        'Bu dosya «${request.kind.label}» yerine «${other.label}» şablonuna benziyor. Önceki adıma dönüp '
        'doğru türü seçin.',
        code: 'NO_HEADER',
      );
    }
    return const ParseFailed(_noHeaderMessage, code: 'NO_HEADER');
  }
  // Satır sınırı (başlıktan sonraki dolu satırlar): eşleme ekranına varmadan açık ileti.
  final dataRows = table.rows.length - header.mapping.headerRowIndex - 1;
  if (table.truncated || dataRows > request.spec.maxRows) {
    final limit = request.spec.maxRows;
    return ParseFailed(
      'Dosyada $limit satırdan fazla veri var. Bir seferde en çok $limit satır yüklenebilir; dosyayı '
      '$limit satırlık parçalara bölüp sırayla yükleyin (aynı kayıtlar tekrar yüklenirse değişiklik yapılmaz).',
      code: 'FILE_LIMIT',
    );
  }
  return ParseDone(
    table: table,
    header: header,
    isXlsx: isXlsx,
    suggestedKind: suggestBetterKind(table, request.spec, request.kind),
    sheetNames: sheetNames,
  );
}

typedef BulkParseRunner = Future<ParseOutcome> Function(ParseRequest request);

/// Varsayılan çalıştırıcı: ayrı isolate (web'de ana iş parçacığı).
Future<ParseOutcome> parseInBackground(ParseRequest request) => compute(runParse, request);
