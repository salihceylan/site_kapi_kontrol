// Toplu yükleme sihirbazının durum makinesi (Platform Faz 2b). Arayüzden bağımsızdır, birim testlenir.
//
// Adımlar: tür -> dosya -> sütunlar -> önizleme -> (onay penceresi) -> sonuç.
//
// Para/veri bütünlüğü kuralları (önceki incelemelerden):
// - İstek uçuştayken ikinci istek BAŞLAMAZ (çift dokunma kilidi); eski/yavaş yanıt yenisini ezmez (jeton).
// - `idempotency_key` imzaya bağlıdır (tür + satır özeti + bayraklar) ve oturum boyunca saklanır: yanıtı kaybolan
//   onay, aynı anahtarla yeniden denenince çift kayıt YARATMAZ. Yalnız başarıda ya da sunucu anahtarı
//   reddedince atılır.
// - Sunucu `PREVIEW_STALE` derse önizleme OTOMATİK yenilenir; yenileme sürerken ya da başarısız olursa eski
//   önizlemeyle onay KAPALIDIR.
// - Hata / yükleme durumunda "boş" sonuç gösterilmez.
import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Rect;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:site_kapi_kontrol/models/bulk_import.dart';
import 'package:site_kapi_kontrol/services/account_export_share.dart' show ExportShareOutcome;
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/bulk_api.dart';
import 'package:site_kapi_kontrol/services/bulk_export_renderer.dart';
import 'package:site_kapi_kontrol/services/bulk_file_delivery.dart';
import 'package:site_kapi_kontrol/services/bulk_file_parser.dart';
import 'package:site_kapi_kontrol/services/bulk_file_picker.dart';
import 'package:site_kapi_kontrol/services/bulk_header_mapper.dart';
import 'package:site_kapi_kontrol/services/bulk_sheet_types.dart';
import 'package:site_kapi_kontrol/services/bulk_template.dart';
import 'package:site_kapi_kontrol/services/local_cache_purge.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_errors.dart' show financeOutcomeUncertain;
import 'package:site_kapi_kontrol/ui/helpers/idempotency.dart';
import 'package:site_kapi_kontrol/ui/helpers/retry_lock.dart';

enum BulkStep { kind, file, mapping, preview, result }

class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

/// Sihirbaz kapanırken çağırana dönen sonuç.
class BulkImportOutcome {
  const BulkImportOutcome({this.changed = false, this.goToTab});

  /// Kayıtlar değişmiş (ya da değişmiş olabilir): çağıran listeleri tazeler.
  final bool changed;

  /// "Kişilere git": sekme dizini (0 Kişiler, 1 Daireler, 2 Araçlar).
  final int? goToTab;
}

class BulkImportController extends ChangeNotifier {
  BulkImportController({
    required this.service,
    required this.siteCode,
    this.siteName = '',
    BulkFileDelivery? delivery,
    BulkParseRunner? parseRunner,
    BulkFilePicker? picker,
    Future<String?> Function()? siteSummaryLoader,
    Future<void> Function()? purgePickerCache,
    this.previewPageSize = 20,
  }) : delivery = delivery ?? BulkFileSharer(),
       _purgePickerCache = purgePickerCache ?? (() => purgeLocalSharedCaches(shareCache: false)),
       _parseRunner = parseRunner ?? parseInBackground,
       _picker = picker ?? pickBulkFile,
       _siteSummaryLoader = siteSummaryLoader,
       _keys = sessionIdempotencyKeys(service.authService, 'imp');

  final BulkService service;
  final int siteCode;
  final String siteName;
  final BulkFileDelivery delivery;
  final int previewPageSize;

  final BulkParseRunner _parseRunner;
  final BulkFilePicker _picker;

  /// Seçilen dosyanın eklenti önbelleğindeki kopyasını siler (okuma bitince; kişisel veri).
  final Future<void> Function() _purgePickerCache;
  final Future<String?> Function()? _siteSummaryLoader;
  final IdempotencyKeys _keys;
  final RetryLock _retry = RetryLock();

  bool _disposed = false;

  // --- Durum -----------------------------------------------------------------------------------

  BulkStep step = BulkStep.kind;

  // Şema.
  ImportSpec? spec;
  bool specLoading = false;
  String? specError;
  String? siteSummary;

  // Tür / şablon.
  ImportKind? kind;
  final Set<ImportKind> completedKinds = <ImportKind>{};
  bool templateBusy = false;
  String? templateMessage;
  String? templateError;

  // Dosya.
  String? fileName;
  int? fileSize;
  /// İşletim sistemi dosya seçicisi açık (henüz dosya okunmuyor).
  bool picking = false;
  bool parsing = false;
  String? parseError;
  List<String>? sheetChoices;
  ParseDone? parsed;
  Uint8List? _bytes;
  int _parseToken = 0;

  // Eşleme.
  ColumnMapping? mapping;
  String? mappingError;
  List<ImportRow> rows = const <ImportRow>[];
  int blankRows = 0;
  String _rowsDigest = '';

  // Önizleme.
  ImportPreview? preview;
  bool previewing = false;
  String? previewError;
  bool previewStale = false;
  String? staleNotice;
  ImportPreview? _staleFrom;
  bool allowOverwrite = false;
  bool strict = false;
  int _previewToken = 0;

  // Onay.
  bool committing = false;
  String? commitError;

  /// Hata sonrası "Yeniden dene" gösterilebilir (aynı anahtar güvenle yeniden gönderilir).
  bool commitRetryable = false;
  bool _acknowledged = false;
  bool _refreshAfterCommit = false;
  bool _maybeChanged = false;

  // Sonuç.
  ImportResult? result;

  // --- Türetilmiş ------------------------------------------------------------------------------

  ImportKindSpec? get kindSpec => kind == null ? null : spec?.of(kind!);

  bool get busy => picking || parsing || previewing || committing || templateBusy;

  /// Kayıtlar değişti ya da değişmiş olabilir.
  bool get dataChanged => (result != null && (result!.applied > 0 || result!.replayed)) || _maybeChanged;

  /// Çıkış kaydedilmemiş ilerlemeyi (okunmuş dosya, önizleme, sürmekte olan işlem) kaybettirir mi?
  bool get hasProgress => result == null && (parsed != null || preview != null || parsing || picking || committing);

  bool get retryLocked => _retry.locked;

  /// Gönderilecek satır sayısı (bayrak anlamı: veri satırı).
  int get rowCount => rows.length;

  /// Onay düğmesi pasifse NEDENİ; onaylanabiliyorsa null.
  String? get commitBlockedReason {
    final p = preview;
    if (committing) return null;
    if (previewing) return 'Önizleme yenileniyor.';
    if (p == null) return 'Önizleme henüz hazır değil.';
    if (previewStale) return 'Önizleme eskidi. Önce «Önizlemeyi Yenile» düğmesine basın.';
    if (retryLocked) return 'Çok sık deneme yapıldı; biraz bekleyin.';
    if (p.totals.ok <= 0) return 'Aktarılacak geçerli satır yok.';
    if (strict && p.totals.error > 0) {
      return 'Hatalı satırlar var ve «hiçbirini aktarma» seçili. Seçeneği kapatın ya da dosyayı düzeltin.';
    }
    return null;
  }

  bool get canCommit => commitBlockedReason == null && !committing;

  // --- Yaşam döngüsü ----------------------------------------------------------------------------

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_parseToken;
    ++_previewToken;
    _bytes = null;
    _retry.dispose();
    super.dispose();
  }

  // --- 1. Şema ve tür --------------------------------------------------------------------------

  /// Şemayı (ve site özetini) yükler. Başarısızsa tür kartları GÖSTERİLMEZ, hata + tekrar dene çıkar.
  Future<void> loadSpec() async {
    if (specLoading) return;
    specLoading = true;
    specError = null;
    notifyListeners();
    try {
      final loaded = await service.getImportSpec(siteCode);
      if (_disposed) return;
      if (loaded.specVersion != ImportSpec.supportedVersion) {
        spec = null;
        specError = 'Uygulamayı güncelleyin.';
      } else {
        spec = loaded;
      }
    } catch (e) {
      if (_disposed) return;
      spec = null;
      specError = _messageOf(e, 'Şablon bilgisi alınamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.');
    } finally {
      if (!_disposed) {
        specLoading = false;
        notifyListeners();
      }
    }
    if (spec != null && siteSummary == null) unawaited(_loadSiteSummary());
  }

  Future<void> _loadSiteSummary() async {
    final loader = _siteSummaryLoader;
    if (loader == null) return;
    try {
      final text = await loader();
      if (_disposed) return;
      siteSummary = text;
      notifyListeners();
    } catch (_) {
      // Özet yardımcı bilgidir; alınamazsa gösterilmez.
    }
  }

  void selectKind(ImportKind value) {
    if (busy || kind == value) return;
    if (kind != null) {
      // Farklı tür: okunmuş dosya ve önizleme bu türe ait değildir, atılır.
      _resetFile(keepName: false);
      preview = null;
      previewError = null;
      previewStale = false;
      staleNotice = null;
      commitError = null;
      commitRetryable = false;
    }
    kind = value;
    templateMessage = null;
    templateError = null;
    notifyListeners();
  }

  /// Şablonu üretip kullanıcıya verir (kaydet / paylaş).
  Future<ExportShareOutcome?> downloadTemplate(ExportFormat format, {Rect? origin}) async {
    final k = kind;
    final s = spec;
    if (templateBusy || k == null || s == null) return null;
    templateBusy = true;
    templateMessage = null;
    templateError = null;
    notifyListeners();
    try {
      ExportEnvelope? apartments;
      String? note;
      // Daireler sayfası sitenin MEVCUT blok / daire numaralarıyla ön doldurulur.
      if (format == ExportFormat.xlsx || k == ImportKind.apartments) {
        try {
          apartments = await service.exportData(siteCode, kind: 'apartments');
        } catch (_) {
          note = 'Mevcut daire numaraları alınamadığı için daire sayfası boş hazırlandı.';
        }
      }
      if (_disposed) return null;
      final file = buildImportTemplate(
        spec: s,
        kind: k,
        format: format,
        apartments: apartments,
        siteName: siteName,
      );
      final outcome = await delivery.deliver(file, sharePositionOrigin: origin, subject: 'Toplu yükleme şablonu');
      if (_disposed) return outcome;
      templateMessage = switch (outcome) {
        ExportShareOutcome.dismissed => 'Şablon kaydedilmedi.',
        _ => 'Şablon hazır: ${file.fileName}${note == null ? '' : '. $note'}',
      };
      return outcome;
    } catch (e) {
      if (!_disposed) {
        templateError = _messageOf(e, 'Şablon hazırlanamadı. Tekrar deneyin.');
      }
      return null;
    } finally {
      if (!_disposed) {
        templateBusy = false;
        notifyListeners();
      }
    }
  }

  /// Dosya adımından, okunmuş dosyanın sütun eşlemesine dön.
  void goToMappingStep() {
    if (parsed == null || mapping == null || busy) return;
    step = BulkStep.mapping;
    notifyListeners();
  }

  void goToFileStep() {
    if (kind == null || spec == null || busy) return;
    step = BulkStep.file;
    notifyListeners();
  }

  // --- 2. Dosya --------------------------------------------------------------------------------

  /// Dosya seçtirir ve okur. Başarıda sütun eşleme adımına geçer.
  Future<void> pickAndParse() async {
    final k = kind;
    final s = spec;
    if (picking || parsing || k == null || s == null) return;
    final token = ++_parseToken;
    parseError = null;
    sheetChoices = null;
    picking = true;
    notifyListeners();
    final PickedBulkFile? picked;
    try {
      picked = await _picker();
    } catch (_) {
      if (token == _parseToken && !_disposed) {
        parseError = 'Dosya seçici açılamadı. Uygulamanın dosya erişim iznini kontrol edip tekrar deneyin.';
        picking = false;
        notifyListeners();
      }
      return;
    }
    if (token != _parseToken || _disposed) return;
    picking = false;
    if (picked == null) {
      notifyListeners(); // vazgeçti
      return;
    }
    parsing = true;
    notifyListeners();
    try {
      final size = picked.size;
      if (size != null && size > SheetLimits.maxXlsxBytes) {
        fileName = picked.name;
        fileSize = size;
        // Önceki dosyanın okunmuş verisi yeni adın altında kalmasın (_runParse hata dalıyla aynı sıfırlama).
        parsed = null;
        mapping = null;
        mappingError = null;
        _bytes = null;
        rows = const <ImportRow>[];
        parseError = 'Dosya çok büyük (en çok 10 MB). Satırları parçalara bölüp ayrı ayrı yükleyin.';
        return;
      }
      final Uint8List bytes;
      try {
        bytes = await picked.readBytes();
      } catch (_) {
        if (token != _parseToken || _disposed) return;
        parseError = 'Dosya okunamadı. Dosyayı başka bir konuma kopyalayıp tekrar deneyin.';
        return;
      }
      if (token != _parseToken || _disposed) return;
      fileName = picked.name;
      fileSize = bytes.length;
      _bytes = bytes;
      await _runParse(token, ParseRequest(bytes: bytes, fileName: picked.name, kind: k, spec: s));
    } finally {
      // Dosya bellekte (ya da okunamadı): eklentinin önbellekteki kopyası artık gerekmez.
      unawaited(_purgePickerQuietly());
      if (token == _parseToken && !_disposed) {
        parsing = false;
        notifyListeners();
      }
    }
  }

  Future<void> _purgePickerQuietly() async {
    try {
      await _purgePickerCache();
    } catch (_) {
      // En iyi çaba.
    }
  }

  /// Çok sayfalı dosyada kullanıcının seçtiği sayfayı okur.
  Future<void> chooseSheet(String name) async {
    final k = kind;
    final s = spec;
    final bytes = _bytes;
    final file = fileName;
    if (parsing || k == null || s == null || bytes == null || file == null) return;
    final token = ++_parseToken;
    parseError = null;
    parsing = true;
    notifyListeners();
    try {
      await _runParse(token, ParseRequest(bytes: bytes, fileName: file, kind: k, spec: s, sheetName: name));
    } finally {
      if (token == _parseToken && !_disposed) {
        parsing = false;
        notifyListeners();
      }
    }
  }

  Future<void> _runParse(int token, ParseRequest request) async {
    ParseOutcome outcome;
    try {
      outcome = await _parseRunner(request);
    } catch (_) {
      outcome = const ParseFailed('Dosya okunamadı. Dosya bozuk olabilir; yeniden kaydedip tekrar deneyin.');
    }
    if (token != _parseToken || _disposed) return; // iptal edildi / eski yanıt
    switch (outcome) {
      case ParseFailed(:final message):
        parseError = message;
        parsed = null;
        mapping = null;
        sheetChoices = null;
      case ParseNeedsSheet(:final sheetNames):
        parsed = null;
        mapping = null;
        sheetChoices = sheetNames;
      case ParseDone():
        parsed = outcome;
        sheetChoices = null;
        mapping = outcome.header.mapping;
        mappingError = null;
        step = BulkStep.mapping;
    }
  }

  /// Okuma sürerken kullanıcı iptal etti: sonuç yok sayılır.
  void cancelParse() {
    if (!parsing && !picking) return;
    ++_parseToken;
    parsing = false;
    picking = false;
    parseError = null;
    notifyListeners();
  }

  // --- 3. Eşleme -------------------------------------------------------------------------------

  void assign(String key, int? column) {
    final m = mapping;
    if (m == null || previewing || committing) return;
    mapping = m.assign(key, column);
    mappingError = null;
    notifyListeners();
  }

  /// Eşlemeyi doğrular, satırları çıkarır ve önizlemeyi başlatır.
  Future<void> confirmMapping() async {
    final m = mapping;
    final p = parsed;
    final ks = kindSpec;
    final s = spec;
    if (m == null || p == null || ks == null || s == null || previewing) return;
    if (!m.canProceed(ks)) return;
    try {
      final extracted = extractImportRows(p.table, m, ks, maxRows: s.maxRows);
      rows = extracted.rows;
      blankRows = extracted.blankRows;
    } on SpreadsheetException catch (e) {
      mappingError = e.message;
      notifyListeners();
      return;
    }
    if (rows.isEmpty) {
      mappingError = 'Dosyada yüklenecek dolu satır yok. Başlık satırının altındaki hücreler boş görünüyor.';
      notifyListeners();
      return;
    }
    final (digest, bodyBytes) = _digestOf(rows);
    // Sunucu gövde sınırı (5 MB): aşan istek önizlemede 413 alırdı; gönderilmeden açık ileti ver.
    if (bodyBytes + _bodyOverheadBytes > s.maxBodyBytes) {
      mappingError =
          'Dosyadaki veriler gönderilemeyecek kadar büyük (${(bodyBytes / (1024 * 1024)).toStringAsFixed(1).replaceAll('.', ',')} MB; '
          'sınır ${(s.maxBodyBytes / (1024 * 1024)).toStringAsFixed(0)} MB). Satırları iki ya da daha fazla parçaya '
          'bölüp sırayla yükleyin; aynı kayıtlar tekrar yüklenirse değişiklik yapılmaz.';
      notifyListeners();
      return;
    }
    mappingError = null;
    _rowsDigest = digest;
    allowOverwrite = false;
    strict = false;
    preview = null;
    previewStale = false;
    staleNotice = null;
    commitError = null;
    commitRetryable = false;
    step = BulkStep.preview;
    notifyListeners();
    await requestPreview();
  }

  /// Gövdenin satır dışı kısmı (spec_version, bayraklar, expected_hash, idempotency_key...) için pay.
  static const int _bodyOverheadBytes = 1024;

  /// (satırların SHA-256'sı, satırların UTF-8 JSON bayt toplamı).
  static (String, int) _digestOf(List<ImportRow> rows) {
    final sink = _DigestSink();
    final input = sha256.startChunkedConversion(sink);
    var bytes = 0;
    for (final row in rows) {
      final encoded = utf8.encode(jsonEncode(row.toJson()));
      bytes += encoded.length + 1; // virgül
      input.add(encoded);
    }
    input.close();
    return (sink.value.toString(), bytes);
  }

  /// Eşlenmiş sütunlarda, sonucu dosyada KAYITLI olmayan formül hücreleri (boş okunmuştur).
  int get uncachedFormulaCells {
    final table = parsed?.table;
    final m = mapping;
    if (table == null || m == null || table.uncachedFormulaColumns.isEmpty) return 0;
    var total = 0;
    for (final column in m.assignment.values.whereType<int>()) {
      total += table.uncachedFormulaColumns[column] ?? 0;
    }
    return total;
  }

  // --- 4. Önizleme -----------------------------------------------------------------------------

  /// Önizlemeyi (yeniden) alır. Yenileme sürerken ya da başarısız olursa eski önizlemeyle onay kapalıdır.
  Future<void> requestPreview() async {
    final k = kind;
    final s = spec;
    if (k == null || s == null || previewing || committing || rows.isEmpty) return;
    final token = ++_previewToken;
    previewing = true;
    previewError = null;
    notifyListeners();
    try {
      final loaded = await service.previewImport(
        siteCode,
        kind: k,
        specVersion: s.specVersion,
        rows: rows,
        allowOverwrite: k.supportsOverwrite && allowOverwrite,
      );
      if (token != _previewToken || _disposed) return;
      final before = _staleFrom;
      preview = loaded;
      previewStale = false;
      staleNotice = before == null ? null : _staleText(before, loaded);
      _staleFrom = null;
    } catch (e) {
      if (token != _previewToken || _disposed) return;
      final limited = _retry.lockIfRateLimited(e, notifyListeners);
      final base = _messageOf(e, '');
      if (limited) {
        previewError = RetryLock.messageFor(e);
      } else if (previewStale) {
        // Yenileme başarısız: «önizleme yenilendi» DENMEZ; eski önizlemeyle onay kapalı kalır.
        previewError = base.isEmpty
            ? 'Önizleme yenilenemedi. İnternet bağlantınızı kontrol edip önizlemeyi yenileyin.'
            : 'Önizleme yenilenemedi. $base';
      } else {
        previewError = base.isEmpty
            ? 'Önizleme alınamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.'
            : base;
      }
    } finally {
      if (token == _previewToken && !_disposed) {
        previewing = false;
        notifyListeners();
      }
    }
  }

  /// Önizlemeyi atar ve bir kez daha alır (hata sonrası "Önizlemeyi Yenile").
  Future<void> refreshPreview() => requestPreview();

  String _staleText(ImportPreview before, ImportPreview now) {
    final a = before.totals;
    final b = now.totals;
    return 'Veriler siz bakarken değişti, özet güncellendi. Geçerli satır ${a.ok} iken ${b.ok}, hatalı satır '
        '${a.error} iken ${b.error} oldu. Kontrol edip yeniden onaylayın.';
  }

  void setAllowOverwrite(bool value) {
    if (value == allowOverwrite || committing || previewing || kind?.supportsOverwrite != true) return;
    allowOverwrite = value;
    // Plan ve özet bu seçeneğe bağlıdır: onay eski önizlemeyle YAPILMAZ.
    previewStale = true;
    notifyListeners();
    unawaited(requestPreview());
  }

  void setStrict(bool value) {
    if (value == strict || committing) return;
    strict = value;
    notifyListeners();
  }

  // --- 5. Onay ---------------------------------------------------------------------------------

  String _signature() =>
      '${kind!.apiValue}|$siteCode|$_rowsDigest|strict=$strict|ow=${kind!.supportsOverwrite && allowOverwrite}|sv=${spec!.specVersion}';

  /// Yüklemeyi onaylar. [acknowledged]: KVKK onayı (people / vehicles için zorunlu).
  Future<void> commit({required bool acknowledged}) async {
    final k = kind;
    final s = spec;
    final p = preview;
    if (committing || previewing || k == null || s == null || p == null) return;
    if (!canCommit) return;
    if (k.needsAcknowledgement && !acknowledged) return;
    _acknowledged = acknowledged;
    final signature = _signature();
    final key = _keys.keyFor(signature);
    committing = true;
    commitError = null;
    commitRetryable = false;
    staleNotice = null;
    notifyListeners();
    try {
      final response = await service.commitImport(
        siteCode,
        kind: k,
        specVersion: s.specVersion,
        rows: rows,
        expectedHash: p.previewHash,
        idempotencyKey: key,
        allowOverwrite: k.supportsOverwrite && allowOverwrite,
        strict: strict,
        acknowledged: acknowledged,
      );
      _keys.clear(signature);
      if (_disposed) return;
      result = response;
      completedKinds.add(k);
      _maybeChanged = true;
      // Yüklenen kişisel veri (dosya baytları, okunan tablo, gönderilen satırlar) bellekten bırakılır.
      _bytes = null;
      parsed = null;
      mapping = null;
      rows = const <ImportRow>[];
      step = BulkStep.result;
    } catch (e) {
      if (_disposed) return;
      _handleCommitError(e, signature);
    } finally {
      if (!_disposed) {
        committing = false;
        notifyListeners();
        if (_refreshAfterCommit) {
          _refreshAfterCommit = false;
          unawaited(requestPreview());
        }
      }
    }
  }

  /// Hata sonrası aynı anahtar ve aynı onayla yeniden dener.
  Future<void> retryCommit() => commit(acknowledged: _acknowledged || kind?.needsAcknowledgement != true);

  void _handleCommitError(Object e, String signature) {
    final limited = _retry.lockIfRateLimited(e, notifyListeners);
    if (financeOutcomeUncertain(e)) _maybeChanged = true;
    final code = e is ApiException ? e.code : null;

    if (code == 'PREVIEW_STALE' && !limited) {
      // Veri önizlemeden sonra değişti: onay kapanır, önizleme yeniden alınır.
      previewStale = true;
      _staleFrom = preview;
      commitError = null;
      _refreshAfterCommit = true;
      return;
    }
    if (code == 'IDEMPOTENCY_CONFLICT') {
      // Sunucu bu anahtarı farklı bilgiyle zaten kullanmış: anahtar atılır, yazma yapılmış olabilir.
      _keys.clear(signature);
      _maybeChanged = true;
    }
    final retryable = limited ||
        code == 'IMPORT_IN_PROGRESS' ||
        code == 'SITE_BUSY' ||
        financeOutcomeUncertain(e);
    commitRetryable = retryable && code != 'IDEMPOTENCY_CONFLICT';
    var message = limited
        ? (RetryLock.messageFor(e) ?? 'Çok sık deneme yapıldı. Biraz sonra tekrar deneyin.')
        : _messageOf(e, 'Yükleme yapılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.');
    if (!limited && financeOutcomeUncertain(e) && !message.contains('çift kayıt')) {
      final trimmed = message.endsWith('.') ? message : '$message.';
      message = '$trimmed Yükleme tamamlanmış olabilir; aynı işlemi tekrar denerseniz çift kayıt oluşmaz.';
    }
    commitError = message;
  }

  // --- Hata raporu -----------------------------------------------------------------------------

  /// Raporlanacak sorunlar (sonuç, yoksa önizleme).
  List<ImportIssue> get reportIssues => result?.issues ?? preview?.issues ?? const <ImportIssue>[];

  Map<String, String> get fieldLabels => <String, String>{
    for (final c in kindSpec?.columns ?? const <ImportColumn>[]) c.key: c.label,
  };

  String? reportMessage;
  String? reportError;
  bool reportBusy = false;

  Future<void> downloadReport({Rect? origin}) async {
    final k = kind;
    if (reportBusy || k == null) return;
    final issues = reportIssues;
    if (issues.isEmpty) return;
    reportBusy = true;
    reportMessage = null;
    reportError = null;
    notifyListeners();
    try {
      final file = renderIssueReport(issues, k, fieldLabels: fieldLabels);
      final outcome = await delivery.deliver(file, sharePositionOrigin: origin, subject: 'Hata raporu');
      if (_disposed) return;
      reportMessage = outcome == ExportShareOutcome.dismissed ? 'Rapor kaydedilmedi.' : 'Rapor hazır: ${file.fileName}';
    } catch (e) {
      if (!_disposed) reportError = _messageOf(e, 'Rapor hazırlanamadı. Tekrar deneyin.');
    } finally {
      if (!_disposed) {
        reportBusy = false;
        notifyListeners();
      }
    }
  }

  // --- Gezinme ---------------------------------------------------------------------------------

  /// Bir adım geri. Çıkış gerekiyorsa false döner (çağıran sayfayı kapatır).
  bool back() {
    if (committing) return true;
    switch (step) {
      case BulkStep.kind:
        return false;
      case BulkStep.file:
        step = BulkStep.kind;
      case BulkStep.mapping:
        // Okunmuş dosya ve eşleme KORUNUR: dosya adımından «sütunlara dön» ya da başka dosya seçilebilir.
        step = BulkStep.file;
      case BulkStep.preview:
        ++_previewToken;
        previewing = false;
        step = BulkStep.mapping;
      case BulkStep.result:
        return false;
    }
    notifyListeners();
    return true;
  }

  /// Sonuç sonrası başka bir tür yüklemek için başa dön.
  void startNext([ImportKind? next]) {
    _resetFile(keepName: false);
    preview = null;
    result = null;
    commitError = null;
    commitRetryable = false;
    previewError = null;
    previewStale = false;
    staleNotice = null;
    rows = const <ImportRow>[];
    mapping = null;
    reportMessage = null;
    reportError = null;
    templateMessage = null;
    templateError = null;
    kind = next;
    step = BulkStep.kind;
    notifyListeners();
  }

  /// Önerilen sıradaki, henüz yüklenmemiş tür.
  ImportKind? get suggestedNextKind {
    for (final k in ImportKind.values) {
      if (!completedKinds.contains(k) && k != kind) return k;
    }
    return null;
  }

  void _resetFile({required bool keepName}) {
    ++_parseToken;
    parsing = false;
    parseError = null;
    sheetChoices = null;
    parsed = null;
    _bytes = null;
    if (!keepName) {
      fileName = null;
      fileSize = null;
    }
    mapping = null;
    mappingError = null;
    rows = const <ImportRow>[];
  }

  // --- Yardımcılar -----------------------------------------------------------------------------

  String _messageOf(Object error, String fallback) {
    if (error is ApiException && !error.genericFallback && error.message.trim().isNotEmpty) {
      return error.message;
    }
    return fallback;
  }
}
