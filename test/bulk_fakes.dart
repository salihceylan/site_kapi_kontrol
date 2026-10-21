// Toplu yükleme testlerinin sahte sunucu / dosya katmanı (Platform Faz 2b). `_test.dart` ile bitmediği için kendi
// başına koşmaz.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:site_kapi_kontrol/models/bulk_import.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/services/account_export_share.dart' show ExportShareOutcome;
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/bulk_api.dart';
import 'package:site_kapi_kontrol/services/bulk_export_renderer.dart';
import 'package:site_kapi_kontrol/services/bulk_file_delivery.dart';
import 'package:site_kapi_kontrol/services/bulk_file_parser.dart';
import 'package:site_kapi_kontrol/services/bulk_file_picker.dart';

import 'bulk_test_support.dart';

/// Sahte [AuthService]: yalnız oturum belirteci (ağ yok).
class FakeBulkAuth extends AuthService {
  FakeBulkAuth({this.role = UserRole.siteManager}) : super(api: AuthApi(baseUrl: 'http://localhost'));

  UserRole role;
  int forcedRefreshes = 0;

  @override
  UserSession? get session => UserSession(
    id: 7,
    fullName: 'Ayşe Yılmaz',
    email: 'ayse@example.com',
    loginName: null,
    role: role,
    isActive: true,
    token: 'tok-7',
  );

  @override
  bool get isLoggedIn => true;

  @override
  Future<void> refreshSession({bool force = false}) async {
    if (force) forcedRefreshes++;
  }
}

typedef PreviewCall = ({ImportKind kind, List<ImportRow> rows, bool allowOverwrite, int specVersion});
typedef CommitCall = ({
  ImportKind kind,
  List<ImportRow> rows,
  String expectedHash,
  String key,
  bool allowOverwrite,
  bool strict,
  bool acknowledged,
});
typedef ExportCall = ({String kind, BulkExportFilters filters, bool includeNotes, ExportFormat format});

/// Sahte [BulkApi]: tüm uçlar testten sürülür.
class FakeBulkApi extends BulkApi {
  FakeBulkApi() : super(baseUrl: 'http://localhost');

  // Spec.
  ImportSpec spec = testSpec();
  Object? specError;
  Completer<void>? specGate;
  int specCalls = 0;

  // Önizleme.
  ImportPreview Function(ImportKind kind, List<ImportRow> rows, bool allowOverwrite)? previewBuilder;

  /// Sırayla tüketilen yanıtlar ([ImportPreview] ya da fırlatılacak hata); bitince [previewBuilder] / varsayılan.
  final List<Object> previewScript = <Object>[];
  Object? previewError;
  Completer<void>? previewGate;
  final List<PreviewCall> previewCalls = <PreviewCall>[];

  // Onay.
  final List<Object> commitScript = <Object>[];
  Completer<void>? commitGate;
  final List<CommitCall> commitCalls = <CommitCall>[];

  // Dışa aktarma.
  ExportEnvelope? envelope;
  Object? exportError;
  Completer<void>? exportGate;
  final List<ExportCall> exportCalls = <ExportCall>[];

  @override
  Future<ImportSpec> getImportSpec({required String token, required int siteCode}) async {
    specCalls++;
    await specGate?.future;
    final error = specError;
    if (error != null) throw error;
    return spec;
  }

  /// Son önizleme / onay isteğindeki `options` (devir bakiyesi).
  Map<String, Object?>? lastPreviewOptions;
  Map<String, Object?>? lastCommitOptions;

  @override
  Future<ImportPreview> previewImport({
    required String token,
    required int siteCode,
    required ImportKind kind,
    required int specVersion,
    required List<ImportRow> rows,
    bool allowOverwrite = false,
    Map<String, Object?>? options,
  }) async {
    lastPreviewOptions = options;
    previewCalls.add((kind: kind, rows: rows, allowOverwrite: allowOverwrite, specVersion: specVersion));
    await previewGate?.future;
    if (previewScript.isNotEmpty) {
      final next = previewScript.removeAt(0);
      if (next is ImportPreview) return next;
      throw next;
    }
    final error = previewError;
    if (error != null) throw error;
    return previewBuilder?.call(kind, rows, allowOverwrite) ??
        ImportPreview.fromJson(previewJson(kind: kind.apiValue, rows: rows.length));
  }

  @override
  Future<ImportResult> commitImport({
    required String token,
    required int siteCode,
    required ImportKind kind,
    required int specVersion,
    required List<ImportRow> rows,
    required String expectedHash,
    required String idempotencyKey,
    bool allowOverwrite = false,
    bool strict = false,
    bool acknowledged = false,
    Map<String, Object?>? options,
  }) async {
    lastCommitOptions = options;
    commitCalls.add((
      kind: kind,
      rows: rows,
      expectedHash: expectedHash,
      key: idempotencyKey,
      allowOverwrite: allowOverwrite,
      strict: strict,
      acknowledged: acknowledged,
    ));
    await commitGate?.future;
    if (commitScript.isNotEmpty) {
      final next = commitScript.removeAt(0);
      if (next is ImportResult) return next;
      throw next;
    }
    return ImportResult.fromJson(commitJson());
  }

  @override
  Future<ExportEnvelope> exportData({
    required String token,
    required int siteCode,
    required String kind,
    BulkExportFilters filters = const BulkExportFilters(),
    bool includeNotes = false,
    ExportFormat format = ExportFormat.xlsx,
    String pathPrefix = '',
  }) async {
    exportCalls.add((kind: kind, filters: filters, includeNotes: includeNotes, format: format));
    await exportGate?.future;
    final error = exportError;
    if (error != null) throw error;
    return envelope ??
        (kind == 'apartments'
            ? ExportEnvelope.fromJson(apartmentsEnvelopeJson())
            : ExportEnvelope.fromJson(envelopeJson(kind: kind)));
  }
}

/// Sahte dosya teslimi: dosyalar kaydedilir; sonuç / hata / bekleme testten verilir.
class FakeDelivery implements BulkFileDelivery {
  final List<RenderedFile> files = <RenderedFile>[];
  final List<Rect?> origins = <Rect?>[];
  ExportShareOutcome outcome = ExportShareOutcome.shared;
  Object? error;
  Completer<void>? gate;

  @override
  Future<ExportShareOutcome> deliver(RenderedFile file, {Rect? sharePositionOrigin, String subject = 'Dosya'}) async {
    files.add(file);
    origins.add(sharePositionOrigin);
    await gate?.future;
    final thrown = error;
    if (thrown != null) throw thrown;
    return outcome;
  }
}

/// Satır içi çalışan ayrıştırıcı (isolate yok).
Future<ParseOutcome> inlineParse(ParseRequest request) async => runParse(request);

/// Sahte seçici: [name] / [bytes] döner (null: vazgeçti).
BulkFilePicker fakePicker(String? name, Uint8List? bytes, {Object? error, Completer<void>? gate}) => () async {
  await gate?.future;
  if (error != null) throw error;
  if (name == null || bytes == null) return null;
  return PickedBulkFile(name: name, size: bytes.length, readBytes: () async => bytes);
};

Uint8List utf8Bytes(String text) => Uint8List.fromList(utf8.encode(text));

/// Kişiler şablonuna uygun küçük CSV (iki veri satırı).
const String kPeopleCsv =
    'Ad Soyad;Telefon;E-posta;Blok;Daire No;İlişki;Giriş Tarihi;Plaka\r\n'
    'Ahmet Yılmaz;0 (555) 123 45 67;ahmet@x.com;A;3;Malik;15.03.2021;34 ABC 123\r\n'
    'Ayşe Demir;;ayse@x.com;A;3;Kiracı;;\r\n';
