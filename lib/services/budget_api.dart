// İşletme projesi (`budget`) uçları: [BudgetApi] yalnız HTTP katmanı, [BudgetService] oturum belirtecini [AuthService]'ten alır.
// Kurallar (diğer modül uçlarıyla aynı): mutasyonlar ASLA otomatik yeniden denenmez; yalnız sunucunun `error` metni gösterilir;
// belirteç ve yanıt gövdeleri günlüğe yazılmaz. Gider kategorileri için mevcut finans ucu kullanılır (Finance4bApi.listExpenseCategories).
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:site_kapi_kontrol/models/budget_models.dart';
import 'package:site_kapi_kontrol/models/expense_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/finance_4b_api.dart' show Finance4bApi;

class BudgetApi {
  BudgetApi({required String baseUrl, http.Client? client})
    : _baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), ''),
      _client = client ?? http.Client();

  final String _baseUrl;
  final http.Client _client;

  static String _path(int siteCode, [String tail = '']) => '/manager/sites/$siteCode/budget-projects${tail.isEmpty ? '' : '/$tail'}';

  Future<BudgetListResult> list({required String token, required int siteCode}) async =>
      BudgetListResult.fromJson(await _send('GET', _path(siteCode), token: token));

  Future<BudgetDetail> get({required String token, required int siteCode, required int id}) async =>
      BudgetDetail.fromJson(await _send('GET', _path(siteCode, '$id'), token: token));

  Future<BudgetDetail> create({required String token, required int siteCode, required Map<String, dynamic> body}) async =>
      BudgetDetail.fromJson(await _send('POST', _path(siteCode), token: token, body: body, ok: const <int>{200, 201}));

  Future<BudgetDetail> update({required String token, required int siteCode, required int id, required Map<String, dynamic> body}) async =>
      BudgetDetail.fromJson(await _send('PATCH', _path(siteCode, '$id'), token: token, body: body));

  /// `PUT .../items`: kalemleri toptan değiştirir (`[{category_id, annual_minor}]`).
  Future<BudgetDetail> putItems({required String token, required int siteCode, required int id, required List<Map<String, int>> items}) async =>
      BudgetDetail.fromJson(await _send('PUT', _path(siteCode, '$id/items'), token: token, body: <String, dynamic>{'items': items}));

  /// `POST .../:id/{notify|revert|finalize}`.
  Future<BudgetDetail> transition({
    required String token,
    required int siteCode,
    required int id,
    required String action,
    Map<String, dynamic>? body,
  }) async => BudgetDetail.fromJson(await _send('POST', _path(siteCode, '$id/$action'), token: token, body: body ?? const <String, dynamic>{}));

  Future<void> delete({required String token, required int siteCode, required int id}) async {
    await _send('DELETE', _path(siteCode, '$id'), token: token);
  }

  Future<BudgetComparison> comparison({required String token, required int siteCode, required int id}) async =>
      BudgetComparison.fromJson(await _send('GET', _path(siteCode, '$id/comparison'), token: token));

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    required String token,
    Map<String, dynamic>? body,
    Set<int> ok = const <int>{200},
  }) async {
    final request = http.Request(method, Uri.parse('$_baseUrl$path'))
      ..headers.addAll(<String, String>{
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
        if (body != null) 'Content-Type': 'application/json; charset=utf-8',
      });
    if (body != null) request.body = jsonEncode(body);
    final http.Response response;
    try {
      response = await _client.send(request).then(http.Response.fromStream).timeout(Duration(seconds: method == 'GET' ? 20 : 45));
    } on TimeoutException {
      throw ApiException(method == 'GET' ? 'Sunucu yanıt vermedi, tekrar deneyin.' : 'Sunucu yanıt vermedi. İşlem tamamlanmış olabilir; ekranı yenileyip kontrol edin.');
    } on Exception {
      throw ApiException('Sunucuya bağlanılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.');
    }
    Map<String, dynamic>? payload;
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map) payload = Map<String, dynamic>.from(decoded);
    } on FormatException {
      payload = null;
    }
    if (ok.contains(response.statusCode)) return payload ?? const <String, dynamic>{};
    final code = payload?['code'] as String?;
    final message = payload?['error'] as String?;
    if (payload == null && (response.statusCode == 401 || response.statusCode == 403) && response.bodyBytes.isNotEmpty) {
      throw ApiException(
        'Sunucuya ulaşılamadı. Ağ bağlantınızı (güvenlik duvarı/proxy) kontrol edip tekrar deneyin.',
        statusCode: response.statusCode,
        fromIntermediary: true,
      );
    }
    throw ApiException(
      code == 'MODULE_DISABLED'
          ? 'İşletme Projesi modülü bu sitede kapalı.'
          : (message ?? 'İşlem tamamlanamadı (${response.statusCode}). Lütfen tekrar deneyin.'),
      statusCode: response.statusCode,
      code: code,
    );
  }
}

class BudgetService {
  BudgetService({required this.authService, BudgetApi? api}) : api = api ?? debugApiFactory?.call(authService) ?? BudgetApi(baseUrl: authService.api.baseUrl);

  @visibleForTesting
  static BudgetApi Function(AuthService authService)? debugApiFactory;

  final AuthService authService;
  final BudgetApi api;

  Future<T> _guard<T>(Future<T> Function(String token) call) async {
    final token = authService.session?.token;
    if (token == null) throw ApiException('Oturum açmanız gerekmektedir.');
    try {
      return await call(token);
    } on ApiException catch (e) {
      if (e.invalidatesSession && authService.session?.token == token) {
        unawaited(authService.refreshSession(force: true));
      }
      rethrow;
    }
  }

  Future<BudgetListResult> list(int siteCode) => _guard((t) => api.list(token: t, siteCode: siteCode));
  Future<BudgetDetail> get(int siteCode, int id) => _guard((t) => api.get(token: t, siteCode: siteCode, id: id));
  Future<BudgetDetail> create(int siteCode, Map<String, dynamic> body) => _guard((t) => api.create(token: t, siteCode: siteCode, body: body));
  Future<BudgetDetail> update(int siteCode, int id, Map<String, dynamic> body) => _guard((t) => api.update(token: t, siteCode: siteCode, id: id, body: body));
  Future<BudgetDetail> putItems(int siteCode, int id, List<Map<String, int>> items) =>
      _guard((t) => api.putItems(token: t, siteCode: siteCode, id: id, items: items));
  Future<BudgetDetail> transition(int siteCode, int id, String action, {Map<String, dynamic>? body}) =>
      _guard((t) => api.transition(token: t, siteCode: siteCode, id: id, action: action, body: body));
  Future<void> delete(int siteCode, int id) => _guard((t) => api.delete(token: t, siteCode: siteCode, id: id));
  Future<BudgetComparison> comparison(int siteCode, int id) => _guard((t) => api.comparison(token: t, siteCode: siteCode, id: id));

  /// Etkin gider kategorileri (finans modülünün ucu; bütçe kalemleri bu kategorilerle tanımlanır).
  Future<List<ExpenseCategory>> categories(int siteCode) =>
      _guard((t) => Finance4bApi(baseUrl: authService.api.baseUrl).listExpenseCategories(token: t, siteCode: siteCode, active: true));
}
