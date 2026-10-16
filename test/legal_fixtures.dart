// Yasal belge / onay uçları için sahte sunucu (fixture). `_test.dart` ile bitmediği için kendi başına
// test olarak çalışmaz. Gerçek ağ kullanılmaz: [LegalApi] bir `MockClient` ile kurulur.
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:site_kapi_kontrol/services/legal_api.dart';

http.Response jsonResponse(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: <String, String>{'content-type': 'application/json; charset=utf-8'},
);

/// Sözleşmedeki (§1.4) biçimde belge özeti.
Map<String, dynamic> legalDoc(
  String id, {
  String? title,
  String version = '2026-10-16',
  List<String> requiredFor = const <String>[],
  bool complete = true,
}) => <String, dynamic>{
  'id': id,
  'title': title ?? id,
  'version': version,
  'effective_date': '2026-10-16',
  'required_for': requiredFor,
  'complete': complete,
};

/// Üç kayıt belgesi + DPA + silme bilgi sayfası.
List<Map<String, dynamic>> standardLegalDocs({String version = '2026-10-16'}) => <Map<String, dynamic>>[
  legalDoc('terms', title: 'Kullanım Koşulları', version: version, requiredFor: const <String>['register']),
  legalDoc('privacy', title: 'Gizlilik Politikası', version: version, requiredFor: const <String>['register']),
  legalDoc('kvkk_notice', title: 'KVKK Aydınlatma Metni', version: version, requiredFor: const <String>['register']),
  legalDoc('dpa', title: 'Veri İşleme Sözleşmesi', version: version, requiredFor: const <String>['site_application']),
  legalDoc('account_deletion', title: 'Hesap Silme', version: version),
];

/// Sahte sunucu: istekleri kaydeder, yanıtları alanlardan üretir.
class FakeLegalServer {
  FakeLegalServer({List<Map<String, dynamic>>? documents}) : documents = documents ?? standardLegalDocs();

  List<Map<String, dynamic>> documents;

  /// id -> Markdown metni (yoksa kısa bir varsayılan metin).
  final Map<String, String> contents = <String, String>{};

  /// `GET /public/legal-documents` durumu ve (varsa) bekletme kapısı.
  int listStatus = 200;
  Completer<void>? listGate;
  Object? listBodyOverride;

  /// `GET /public/legal-documents/:id` durumu ve bekletme kapısı.
  int docStatus = 200;
  Completer<void>? docGate;

  /// `GET /me/consents`.
  int consentsStatus = 200;
  List<Map<String, dynamic>> pending = <Map<String, dynamic>>[];
  Completer<void>? consentsGate;
  bool consentsThrows = false;

  /// `POST /me/consents`.
  int acceptStatus = 200;
  Map<String, dynamic>? acceptErrorBody;
  Completer<void>? acceptGate;

  /// Sunucu yanıtına `pending` alanı eklesin mi (S-B gerçek davranışı: evet).
  bool acceptIncludesPending = true;

  /// Verilirse onaydan sonra yanıttaki `pending` bu liste olur (hâlâ bekleyen belge senaryosu).
  List<Map<String, dynamic>>? acceptRemainingPending;

  final List<http.Request> requests = <http.Request>[];

  int count(String method, String path) =>
      requests.where((r) => r.method == method && r.url.path == path).length;

  List<http.Request> where(String method, String path) =>
      requests.where((r) => r.method == method && r.url.path == path).toList();

  Map<String, dynamic>? lastJsonBody(String method, String path) {
    final list = where(method, path);
    if (list.isEmpty) return null;
    return jsonDecode(list.last.body) as Map<String, dynamic>;
  }

  late final http.Client client = MockClient(_handle);

  LegalApi get api => LegalApi(baseUrl: 'https://api.example.test', client: client);

  Future<http.Response> _handle(http.Request request) async {
    requests.add(request);
    final path = request.url.path;
    if (request.method == 'GET' && path == '/public/legal-documents') {
      await listGate?.future;
      if (listStatus != 200) return jsonResponse(<String, dynamic>{'error': 'Sunucu hatası'}, listStatus);
      return jsonResponse(listBodyOverride ?? <String, dynamic>{'documents': documents});
    }
    if (request.method == 'GET' && path.startsWith('/public/legal-documents/')) {
      await docGate?.future;
      final id = path.substring('/public/legal-documents/'.length);
      if (docStatus != 200) {
        return jsonResponse(<String, dynamic>{'error': 'Belge bulunamadı', 'code': 'NOT_FOUND'}, docStatus);
      }
      final summary = documents.where((d) => d['id'] == id).firstOrNull;
      if (summary == null) {
        return jsonResponse(<String, dynamic>{'error': 'Belge bulunamadı', 'code': 'NOT_FOUND'}, 404);
      }
      return jsonResponse(<String, dynamic>{
        ...summary,
        'content_md': contents[id] ?? '# ${summary['title']}\n\nKısa **örnek** metin.',
      });
    }
    if (request.method == 'GET' && path == '/me/consents') {
      // Yanıt, kapı açılmadan ÖNCEKİ durumun anlık görüntüsüdür (istek sürerken sunucu durumu değişirse yanıt
      // bayat kalır: gerçek ağdaki yarış durumu).
      final snapshot = List<Map<String, dynamic>>.of(pending);
      await consentsGate?.future;
      if (consentsThrows) throw http.ClientException('network down');
      if (consentsStatus != 200) {
        return jsonResponse(<String, dynamic>{'error': 'Hata', 'code': 'X'}, consentsStatus);
      }
      return jsonResponse(<String, dynamic>{'consents': <Object>[], 'pending': snapshot});
    }
    if (request.method == 'POST' && path == '/me/consents') {
      await acceptGate?.future;
      if (acceptStatus != 200) {
        return jsonResponse(
          acceptErrorBody ?? <String, dynamic>{'error': 'Hata', 'code': 'X'},
          acceptStatus,
        );
      }
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final docs = (body['documents'] as List).cast<Map<String, dynamic>>();
      pending = <Map<String, dynamic>>[];
      return jsonResponse(<String, dynamic>{
        'consents': <Map<String, dynamic>>[
          for (final d in docs)
            <String, dynamic>{
              'document_id': d['id'],
              'version': d['version'],
              'accepted_at': '2026-10-16T10:00:00.000Z',
            },
        ],
        if (acceptIncludesPending) 'pending': acceptRemainingPending ?? pending,
      });
    }
    return jsonResponse(<String, dynamic>{'error': 'yok'}, 404);
  }
}
