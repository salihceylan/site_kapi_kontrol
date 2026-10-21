// Yönetim firması (Y1/Y2; docs/PLATFORM_YONETIM_FIRMASI.md) uçları. Yalnız HTTP katmanı: belirteç oturumdan alınır, hata gövdesi Türkçe
// [ApiException]'a çevrilir. Yazma ASLA otomatik yeniden denenmez; belirteç ve gövdeler günlüğe yazılmaz.
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';

class ManagementCompanyService {
  ManagementCompanyService({required this.authService, http.Client? client}) : _client = client ?? http.Client();

  final AuthService authService;
  final http.Client _client;

  String get _base => authService.api.baseUrl.replaceAll(RegExp(r'/+$'), '');

  Future<Map<String, dynamic>> _call(String method, String path, {Map<String, dynamic>? body, Map<String, String>? query}) async {
    final token = authService.session?.token;
    if (token == null) throw ApiException('Oturum açmanız gerekmektedir.');
    final request = http.Request(method, Uri.parse('$_base$path').replace(queryParameters: query))
      ..headers.addAll(<String, String>{
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
        if (body != null) 'Content-Type': 'application/json; charset=utf-8',
      });
    if (body != null) request.body = jsonEncode(body);
    final http.Response response;
    try {
      response = await _client.send(request).then(http.Response.fromStream).timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw ApiException('Sunucu yanıt vermedi, tekrar deneyin.');
    } on Exception {
      throw ApiException('Sunucuya bağlanılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.');
    }
    Map<String, dynamic> payload = const <String, dynamic>{};
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) payload = decoded;
    } on FormatException {
      // JSON değil: aşağıda durum koduna göre genel ileti.
    }
    if (response.statusCode >= 200 && response.statusCode < 300) return payload;
    final code = payload['code'] is String ? payload['code'] as String : null;
    final text = payload['error'] is String ? payload['error'] as String : null;
    if (response.statusCode == 401) {
      throw SessionExpiredException('Oturum süreniz doldu. Lütfen tekrar giriş yapın.', code);
    }
    throw ApiException(
      text ?? (response.statusCode >= 500 ? 'Sunucu şu anda yanıt veremiyor. Lütfen biraz sonra tekrar deneyin.' : 'İşlem yapılamadı.'),
      statusCode: response.statusCode,
      code: code,
    );
  }

  List<Map<String, dynamic>> _list(Map<String, dynamic> body, String key) =>
      (body[key] as List<dynamic>? ?? const <dynamic>[]).whereType<Map<String, dynamic>>().toList();

  Future<List<Map<String, dynamic>>> companies() async => _list(await _call('GET', '/companies'), 'companies');

  Future<Map<String, dynamic>> company(int id) => _call('GET', '/companies/$id');

  Future<List<Map<String, dynamic>>> sitesTable(int id) async => _list(await _call('GET', '/companies/$id/sites-table'), 'sites');

  Future<Map<String, dynamic>> shareStatement(int id, String month) =>
      _call('GET', '/companies/$id/share-statement', query: <String, String>{'month': month});

  Future<void> addMember(int id, String email, {String role = 'staff'}) =>
      _call('POST', '/companies/$id/members', body: <String, dynamic>{'email': email, 'role': role});

  Future<void> removeMember(int id, int userCode) => _call('DELETE', '/companies/$id/members/$userCode');

  // --- Süper kullanıcı ---
  Future<void> createCompany({required String name, required String ownerEmail, required int shareBp}) =>
      _call('POST', '/admin/companies', body: <String, dynamic>{'name': name, 'owner_email': ownerEmail, 'partner_share_bp': shareBp});

  Future<void> updateCompany(int id, Map<String, dynamic> fields) => _call('PATCH', '/admin/companies/$id', body: fields);

  Future<void> linkSite(int id, int siteCode, int? feeMinor) =>
      _call('POST', '/admin/companies/$id/sites', body: <String, dynamic>{'site_code': siteCode, 'monthly_fee_minor': feeMinor});

  Future<void> unlinkSite(int id, int siteCode) => _call('DELETE', '/admin/companies/$id/sites/$siteCode');

  Future<int> trialDays() async => ((await _call('GET', '/admin/trial-settings'))['trial_days'] as num?)?.toInt() ?? 60;

  Future<void> setTrialDays(int days) => _call('PUT', '/admin/trial-settings', body: <String, dynamic>{'trial_days': days});

  /// [days] null: siteden denemeyi kaldırır.
  Future<void> setSiteTrial(int siteCode, int? days) =>
      _call('PUT', '/admin/sites/$siteCode/trial', body: days == null ? <String, dynamic>{'trial_ends_at': null} : <String, dynamic>{'days': days});
}
