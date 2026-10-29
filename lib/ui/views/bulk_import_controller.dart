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
import 'package:site_kapi_kontrol/services/bulk_login_name.dart';
import 'package:site_kapi_kontrol/services/bulk_sheet_types.dart';
import 'package:site_kapi_kontrol/services/bulk_template.dart';
import 'package:site_kapi_kontrol/services/local_cache_purge.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_errors.dart' show financeOutcomeUncertain;
import 'package:site_kapi_kontrol/ui/helpers/idempotency.dart';
import 'package:site_kapi_kontrol/ui/helpers/retry_lock.dart';

// Kişi hesabı penceresi (tek kişi için ad önerisi) bu yardımcıyı denetleyici üzerinden içe aktarıyordu: yer değişti, içe aktarma yolu korunur.
export 'package:site_kapi_kontrol/services/bulk_login_name.dart' show generateUsernameFromFullName, kLoginNameBaseMax;

enum BulkStep { kind, file, mapping, preview, result }

/// Satırdaki yöneticinin seçtiği kullanıcı adı hücresi (şablon sütunu DEĞİL; yalnız önizleme tablosundan gelir). Sunucudaki `LOGIN_NAME_OVERRIDE_KEY`.
const String kLoginNameKey = 'giris_adi';

/// Kişiler girişindeki türler: «Hepsi bir arada» ve «Araçlar».
const List<ImportKind> kClassicImportKinds = <ImportKind>[
  ImportKind.allInOne,
  ImportKind.vehicles,
];

/// Finans girişindeki türler.
const List<ImportKind> kOpeningImportKinds = <ImportKind>[ImportKind.openingBalances];

String _isoToday() {
  final now = DateTime.now();
  return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
}

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
    this.allowedKinds = kClassicImportKinds,
    this.proposalDelay = const Duration(milliseconds: 700),
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

  /// Tablodaki bir hücre değişince kullanıcı adı önerilerinin sunucudan yenilenmesi için bekleme (art arda düzenlemeler tek istek olur).
  final Duration proposalDelay;

  /// Bu giriş noktasında seçilebilen türler (Kişiler: hepsi bir arada + klasik üçlü; Finans: yalnız devir bakiyesi).
  final List<ImportKind> allowedKinds;

  final BulkParseRunner _parseRunner;
  final BulkFilePicker _picker;

  /// Seçilen dosyanın eklenti önbelleğindeki kopyasını siler (okuma bitince; kişisel veri).
  final Future<void> Function() _purgePickerCache;
  final Future<String?> Function()? _siteSummaryLoader;
  final IdempotencyKeys _keys;
  final RetryLock _retry = RetryLock();

  bool _disposed = false;
  Timer? _proposalTimer;

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

  // Kullanıcı adları (kişi türleri): sistemin seçtiği adlar satır numarasına göre; yönetici seçimi satırın `giris_adi` hücresindedir.
  Map<int, AccountProposal> accountProposals = const <int, AccountProposal>{};
  bool proposalsLoading = false;
  String? proposalsError;

  /// Satırlar öneriler alındıktan sonra değişti (yeni istek bekleniyor / sürüyor).
  bool proposalsStale = false;
  int _proposalToken = 0;
  int _rowsVersion = 0;
  List<ImportRow>? _previewRows;

  // Önizleme.
  ImportPreview? preview;
  bool previewing = false;
  String? previewError;
  bool previewStale = false;
  String? staleNotice;
  ImportPreview? _staleFrom;
  bool allowOverwrite = false;
  bool strict = false;

  /// Devir bakiyesi: devir tarihi (YYYY-MM-DD; bugün ya da önce, en çok 5 yıl geri).
  String cutoverDate = _isoToday();
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

  /// Seçili türün şemadaki sütun anahtarları. `sifre` yalnız bunu tanımlayan türlerde (kişiler, hepsi bir arada) eklenir;
  /// sunucu tanımsız anahtarı olan satırı 400 INVALID_BODY ile reddeder (araçlar, devir bakiyesi).
  Set<String> get _kindColumnKeys => <String>{for (final column in kindSpec?.columns ?? const <ImportColumn>[]) column.key};

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
    if (hasLoginProblems) {
      return 'Kullanıcı adı sorunu olan satırlar var. Geri dönüp tablodan düzeltin.';
    }
    if (p.issues.any((issue) => issue.isError && issue.code.startsWith('LOGIN_NAME_'))) {
      return 'Kullanıcı adı kabul edilmeyen satırlar var. Geri dönüp tablodan düzeltin.';
    }
    if (p.totals.ok <= 0) return 'Aktarılacak geçerli satır yok.';
    if (strict && p.totals.error > 0) {
      return 'Hatalı satırlar var ve «hiçbirini aktarma» seçili. Seçeneği kapatın ya da dosyayı düzeltin.';
    }
    return null;
  }

  bool get canCommit => commitBlockedReason == null && !committing;

  // --- Kullanıcı adları -------------------------------------------------------------------------

  /// Önizleme tablosunda «Kullanıcı Adı» sütunu var mı (kişi türleri).
  bool get hasLoginColumn => kind?.createsAccounts == true;

  /// Satır için sunucunun önerisi / durumu (henüz alınmadıysa null).
  AccountProposal? proposalOf(ImportRow row) => accountProposals[row.n];

  /// Yöneticinin bu satıra yazdığı ad (yoksa null).
  String? overrideOf(ImportRow row) {
    final raw = row.cells[kLoginNameKey]?.toString().trim() ?? '';
    return raw.isEmpty ? null : raw;
  }

  /// Satırın tabloda gösterilen kullanıcı adı: yönetici seçimi, yoksa sunucu önerisi / mevcut hesabın adı.
  String? loginNameOf(ImportRow row) {
    final proposal = proposalOf(row);
    if (proposal != null && proposal.status != AccountProposalStatus.create) return proposal.loginName;
    final override = overrideOf(row);
    // yönetici seçimi sunucunun yapacağı biçimle (küçük harf, Türkçe harfler sadeleşmiş) hemen gösterilir; öneri yenilenince kesinleşir
    if (override != null) return normalizeTypedLoginName(override).value ?? override;
    return proposal?.loginName;
  }

  /// Yönetici bu satırın adını değiştirebilir mi (yeni hesap açılan ve önerisi alınmış satır).
  bool isLoginEditable(ImportRow row) {
    final proposal = proposalOf(row);
    return proposal != null && proposal.status == AccountProposalStatus.create;
  }

  /// Gönderimi engelleyen kullanıcı adı sorunları: satır numarası -> neden (yönetici seçimi reddedilmiş ya da başka satırla aynı).
  Map<int, String> get loginProblems {
    if (!hasLoginColumn) return const <int, String>{};
    final problems = <int, String>{};
    final seen = <String, int>{};
    for (final row in rows) {
      final proposal = proposalOf(row);
      if (proposal?.status == AccountProposalStatus.rejected) {
        problems[row.n] = proposal!.message ?? 'Kullanıcı adı kabul edilmedi.';
        continue;
      }
      final name = loginNameOf(row);
      if (name == null || proposal == null || proposal.status == AccountProposalStatus.existing) continue;
      final key = name.toLowerCase();
      final first = seen[key];
      if (first != null && overrideOf(row) != null) {
        problems[row.n] = 'Bu kullanıcı adı dosyada satır $first ile aynı.';
      } else {
        seen.putIfAbsent(key, () => row.n);
      }
    }
    return problems;
  }

  bool get hasLoginProblems => loginProblems.isNotEmpty;

  /// Yazılan adın tarayıcıda hemen verilebilen denetimi: biçim ve (satır [rowN] hariç) dosyadaki diğer adlarla çakışma. Sorun yoksa null.
  /// Sistemdeki kullanılabilirliği yalnız sunucu bilir: bkz. [checkLoginName].
  String? localLoginNameProblem(String raw, {required int rowN}) {
    final typed = normalizeTypedLoginName(raw);
    if (typed.error != null) return loginNameFormatMessage(typed.error!);
    final wanted = typed.value!;
    for (final row in rows) {
      if (row.n == rowN) continue;
      final proposal = proposalOf(row);
      if (proposal == null || proposal.status == AccountProposalStatus.rejected) continue;
      final other = loginNameOf(row);
      if (other != null && other.toLowerCase() == wanted) return 'Bu kullanıcı adı dosyada satır ${row.n} ile aynı.';
    }
    return null;
  }

  /// Yazılan adı sunucuda denetler (biçim + her site / şehirdeki kullanılabilirlik).
  Future<LoginNameCheck> checkLoginName(String raw) => service.checkLoginName(siteCode, raw);

  // --- Yaşam döngüsü ----------------------------------------------------------------------------

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _proposalTimer?.cancel();
    ++_proposalToken;
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
    _resetProposals();
    kind = value;
    // Devirde «hatalı satır varsa aktarma» varsayılan AÇIK (para yazılır).
    if (value.isOpening) strict = true;
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
      if (format == ExportFormat.xlsx || k == ImportKind.apartments || k == ImportKind.allInOne || k == ImportKind.openingBalances) {
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
    if (rows.isEmpty) {
      _extractRowsIfReady();
    }
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
        _resetProposals();
        _extractRowsIfReady();
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
    rows = const <ImportRow>[];
    _resetProposals();
    _extractRowsIfReady();
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
    if (hasLoginProblems) {
      mappingError = 'Kullanıcı adı sorunu olan satırlar var. Tabloda kırmızı işaretli adları düzeltin.';
      notifyListeners();
      return;
    }
    if (rows.isEmpty) {
      try {
        final extracted = extractImportRows(p.table, m, ks, maxRows: s.maxRows);
        rows = enrichImportRowsWithDefaults(extracted.rows, columnKeys: _kindColumnKeys);
        blankRows = extracted.blankRows;
      } on SpreadsheetException catch (e) {
        mappingError = e.message;
        notifyListeners();
        return;
      }
    }
    if (rows.isEmpty) {
      mappingError = 'Dosyada yüklenecek dolu satır yok. Başlık satırının altındaki hücreler boş görünüyor.';
      notifyListeners();
      return;
    }
    // Kullanıcı adı önerisi isteği beklemede ya da sürüyorsa önizleme onun yerine geçer (önizleme yanıtı da hesapları taşır).
    _proposalTimer?.cancel();
    final (digest, bodyBytes) = _digestOf(_requestRows());
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

  void _extractRowsIfReady() {
    final m = mapping;
    final p = parsed;
    final ks = kindSpec;
    final s = spec;
    if (m == null || p == null || ks == null || s == null) return;
    if (!m.canProceed(ks)) return;
    try {
      final extracted = extractImportRows(p.table, m, ks, maxRows: s.maxRows);
      rows = enrichImportRowsWithDefaults(extracted.rows, columnKeys: _kindColumnKeys);
      blankRows = extracted.blankRows;
      mappingError = null;
      _scheduleProposals(immediate: true);
    } catch (_) {
      // Başlık eşlemesi henüz tamamlanmamış veya eksik olabilir.
    }
  }

  /// Eski şablondan kalan «Kullanıcı Adı» sütunu bu dosyada var mı (artık kullanılmıyor; sistem adı kendisi verir).
  bool get fileHasLegacyLoginColumn {
    final m = mapping;
    if (!hasLoginColumn || m == null) return false;
    for (final i in m.ignoredColumns()) {
      if (kLegacyLoginNameHeaders.contains(foldHeader(m.headers[i]))) return true;
    }
    return false;
  }

  /// Belirli bir satırdaki hücre değerini günceller.
  void updateCell(int rowIndex, String columnKey, Object? newValue) {
    if (rowIndex < 0 || rowIndex >= rows.length) return;
    final currentRow = rows[rowIndex];
    final updatedCells = Map<String, Object?>.from(currentRow.cells);
    if (newValue == null || (newValue is String && newValue.trim().isEmpty)) {
      updatedCells.remove(columnKey);
    } else {
      updatedCells[columnKey] = newValue;
    }

    final updatedRow = ImportRow(
      n: currentRow.n,
      cells: updatedCells,
    );
    final newRows = List<ImportRow>.from(rows);
    newRows[rowIndex] = updatedRow;
    rows = List<ImportRow>.unmodifiable(newRows);
    _onRowsChanged();
  }

  /// Satırı tablodan siler.
  void deleteRow(int rowIndex) {
    if (rowIndex < 0 || rowIndex >= rows.length) return;
    _forgetProposal(rows[rowIndex].n);
    final newRows = List<ImportRow>.from(rows)..removeAt(rowIndex);
    rows = List<ImportRow>.unmodifiable(newRows);
    _onRowsChanged();
  }

  /// Yeni satır ekler.
  void addRow({Map<String, Object?>? initialCells}) {
    final nextN = rows.isEmpty ? 1 : (rows.map((r) => r.n).reduce((a, b) => a > b ? a : b) + 1);
    _forgetProposal(nextN);
    final cells = Map<String, Object?>.from(initialCells ?? const <String, Object?>{});
    final keys = _kindColumnKeys;
    final hasName = (cells['ad_soyad']?.toString().trim() ?? '').isNotEmpty;
    if (hasName && keys.contains('sifre') && (cells['sifre'] == null || cells['sifre'].toString().trim().isEmpty)) {
      cells['sifre'] = '1234';
    }
    final newRow = ImportRow(
      n: nextN,
      cells: cells,
    );
    final newRows = List<ImportRow>.from(rows)..add(newRow);
    rows = List<ImportRow>.unmodifiable(newRows);
    _onRowsChanged();
  }

  void _onRowsChanged() {
    mappingError = null;
    previewStale = true;
    _scheduleProposals();
    notifyListeners();
  }

  // --- Kullanıcı adı önerileri -------------------------------------------------------------------

  /// Silinen / yeniden kullanılan satır numarasının eski önerisi tabloda kalmasın.
  void _forgetProposal(int n) {
    if (accountProposals.containsKey(n)) {
      accountProposals = Map<int, AccountProposal>.of(accountProposals)..remove(n);
    }
  }

  void _resetProposals() {
    _proposalTimer?.cancel();
    ++_proposalToken;
    ++_rowsVersion;
    accountProposals = const <int, AccountProposal>{};
    proposalsLoading = false;
    proposalsError = null;
    proposalsStale = false;
  }

  /// Sunucuya gidecek satırlar: yeni hesap açılmayacak satırdaki (mevcut hesaba bağlanan, e-postası kullanılamayan ...) eski kullanıcı adı seçimi atılır.
  List<ImportRow> _requestRows() {
    if (!hasLoginColumn) return rows;
    var changed = false;
    final out = <ImportRow>[];
    for (final row in rows) {
      final proposal = accountProposals[row.n];
      if (row.cells.containsKey(kLoginNameKey) && proposal != null && proposal.status != AccountProposalStatus.create && proposal.status != AccountProposalStatus.rejected) {
        out.add(ImportRow(n: row.n, cells: Map<String, Object?>.from(row.cells)..remove(kLoginNameKey)));
        changed = true;
      } else {
        out.add(row);
      }
    }
    return changed ? out : rows;
  }

  /// Satırlar değişti: kullanıcı adı önerileri [proposalDelay] sonra (art arda düzenlemeler tek istek) ya da [immediate] hemen yenilenir.
  void _scheduleProposals({bool immediate = false}) {
    if (!hasLoginColumn || _disposed) return;
    ++_rowsVersion;
    proposalsStale = true;
    _proposalTimer?.cancel();
    if (rows.isEmpty) {
      proposalsStale = false;
      return;
    }
    if (immediate || proposalDelay == Duration.zero) {
      unawaited(flushProposals());
    } else {
      _proposalTimer = Timer(proposalDelay, () => unawaited(flushProposals()));
    }
  }

  Future<void>? _proposalFuture;

  /// Sürmekte olan kullanıcı adı önerisi isteği bitince tamamlanır (yoksa hemen). Testler ve «bekle» davranışları içindir.
  Future<void> get proposalsSettled => _proposalFuture ?? Future<void>.value();

  /// Kullanıcı adı önerilerini şimdi sunucudan alır (beklemedeki zamanlayıcıyı iptal eder). Hata engellemez: öneriler önizleme adımında yine gelir.
  Future<void> flushProposals() => _proposalFuture = _flushProposals();

  Future<void> _flushProposals() async {
    _proposalTimer?.cancel();
    final k = kind;
    final s = spec;
    if (_disposed || k == null || s == null || !k.createsAccounts || rows.isEmpty) return;
    final version = _rowsVersion;
    final token = ++_proposalToken;
    final sendRows = _requestRows();
    proposalsLoading = true;
    proposalsError = null;
    notifyListeners();
    try {
      final loaded = await service.previewAccounts(siteCode, kind: k, specVersion: s.specVersion, rows: sendRows);
      if (token != _proposalToken || _disposed) return;
      if (version == _rowsVersion) {
        accountProposals = <int, AccountProposal>{for (final proposal in loaded) proposal.n: proposal};
        proposalsStale = false;
      }
    } catch (e) {
      if (token != _proposalToken || _disposed) return;
      proposalsError = _messageOf(e, 'Kullanıcı adları hazırlanamadı. Önizleme adımında yeniden denenir.');
    } finally {
      if (token == _proposalToken && !_disposed) {
        proposalsLoading = false;
        notifyListeners();
      }
    }
  }

  // --- 4. Önizleme -----------------------------------------------------------------------------

  /// Önizlemeyi (yeniden) alır. Yenileme sürerken ya da başarısız olursa eski önizlemeyle onay kapalıdır.
  Future<void> requestPreview() async {
    final k = kind;
    final s = spec;
    if (k == null || s == null || previewing || committing || rows.isEmpty) return;
    final token = ++_previewToken;
    // Önizlemede gönderilen satırlar onayda AYNEN gider (kullanıcı adı seçimleri dahil): onay öncesi öneri yenilemeleri gönderimi değiştirmez.
    final sendRows = _requestRows();
    _previewRows = sendRows;
    _proposalTimer?.cancel();
    previewing = true;
    previewError = null;
    notifyListeners();
    try {
      final loaded = await service.previewImport(
        siteCode,
        kind: k,
        specVersion: s.specVersion,
        rows: sendRows,
        allowOverwrite: k.supportsOverwrite && allowOverwrite,
        options: _options(k),
      );
      if (token != _previewToken || _disposed) return;
      final before = _staleFrom;
      if (k.createsAccounts && loaded.accountsProvided) {
        // önizleme (CRM eşitlemeli, kesin sonuç) tablodaki önerilerin yerini alır
        ++_proposalToken;
        accountProposals = <int, AccountProposal>{for (final proposal in loaded.accounts) proposal.n: proposal};
        proposalsStale = false;
        proposalsLoading = false;
      }
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

  /// Devir tarihini değiştirir; önizleme eskir ve yenilenir.
  void setCutoverDate(String value) {
    if (value == cutoverDate || committing || previewing || kind?.isOpening != true) return;
    cutoverDate = value;
    previewStale = true;
    notifyListeners();
    unawaited(requestPreview());
  }

  /// Sunucuya giden `options` (yalnız devir bakiyesi). [withTotal]: onayda toplam tutar (kuruş) da gider.
  Map<String, Object?>? _options(ImportKind k, {bool withTotal = false}) {
    if (!k.isOpening) return null;
    return <String, Object?>{
      'cutover_date': cutoverDate,
      if (withTotal) 'expected_total_minor': openingTotalMinor,
      // Alacaklı devir (K16): alacak toplamı borç toplamından AYRI onaylanır (yalnız alacaklı satır varsa gönderilir).
      if (withTotal && openingCreditTotalMinor > 0) 'expected_credit_total_minor': openingCreditTotalMinor,
    };
  }

  /// Önizlemedeki devir BORÇ toplamı (kuruş).
  int get openingTotalMinor => preview?.plan['total_minor'] ?? 0;

  /// Önizlemedeki devir ALACAK toplamı (büyüklük, kuruş); alacaklı satır yoksa 0.
  int get openingCreditTotalMinor => preview?.plan['credit_total_minor'] ?? 0;

  void setStrict(bool value) {
    if (value == strict || committing) return;
    strict = value;
    notifyListeners();
  }

  // --- 5. Onay ---------------------------------------------------------------------------------

  String _signature() =>
      '${kind!.apiValue}|$siteCode|$_rowsDigest|strict=$strict|ow=${kind!.supportsOverwrite && allowOverwrite}|sv=${spec!.specVersion}|cut=${kind!.isOpening ? cutoverDate : ''}|tot=${kind!.isOpening ? openingTotalMinor : 0}';

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
        rows: _previewRows ?? _requestRows(),
        expectedHash: p.previewHash,
        idempotencyKey: key,
        allowOverwrite: k.supportsOverwrite && allowOverwrite,
        strict: strict,
        acknowledged: acknowledged,
        options: _options(k, withTotal: true),
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
      _previewRows = null;
      _resetProposals();
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

    if ((code == 'PREVIEW_STALE' || code == 'TOTAL_MISMATCH') && !limited) {
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
    kLoginNameKey: 'Kullanıcı Adı',
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
    _previewRows = null;
    _resetProposals();
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
    for (final k in allowedKinds) {
      if (k != ImportKind.allInOne && !completedKinds.contains(k) && k != kind) return k;
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
    _previewRows = null;
    _resetProposals();
  }

  // --- Yardımcılar -----------------------------------------------------------------------------

  String _messageOf(Object error, String fallback) {
    if (error is ApiException && !error.genericFallback && error.message.trim().isNotEmpty) {
      return error.message;
    }
    return fallback;
  }
}

/// Kişi satırlarına başlangıç şifresi (`1234`) ekler. YALNIZ türün tanımladığı sütunlar için ([columnKeys]): sunucu tanımsız anahtarı olan satırı 400
/// INVALID_BODY ile reddeder, bu yüzden araç ve devir bakiyesi satırlarına `sifre` EKLENMEZ. Ad soyadı olmayan satır (yalnız daire bilgisi ya da hatalı satır)
/// değişmez. Kullanıcı adlarını artık SİSTEM verir (sunucu önerir, tabloda `giris_adi` ile değiştirilir); istemci ad üretmez.
List<ImportRow> enrichImportRowsWithDefaults(List<ImportRow> rawRows, {required Set<String> columnKeys}) {
  if (!columnKeys.contains('sifre')) return rawRows;

  String textOf(Object? value) => value?.toString().trim() ?? '';

  final enriched = <ImportRow>[];
  for (final row in rawRows) {
    if (textOf(row.cells['ad_soyad']).isEmpty || textOf(row.cells['sifre']).isNotEmpty) {
      enriched.add(row);
      continue;
    }
    enriched.add(ImportRow(n: row.n, cells: Map<String, Object?>.from(row.cells)..['sifre'] = '1234'));
  }
  return enriched;
}
