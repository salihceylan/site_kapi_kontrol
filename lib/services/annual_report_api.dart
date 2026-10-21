// Faaliyet raporu (`annual_report`) uçları. Kurallar diğer modül uçlarıyla aynı: mutasyon yeniden denenmez, 401 oturum bitişidir,
// bölüm metinleri günlüğe YAZILMAZ.
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:site_kapi_kontrol/models/annual_report.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';

class AnnualReportService {
  AnnualReportService({required this.authService, http.Client? client}) : _client = client ?? http.Client();

  final AuthService authService;
  final http.Client _client;

  String get _base => authService.api.baseUrl.replaceAll(RegExp(r'/+$'), '');

  /// Sistem taslağı + saklı düzenlemeler. [growthBp] verilirse gelecek yıl tahmini o oranla hesaplanır.
  Future<AnnualReport> load(int siteCode, int year, {int? growthBp}) async => AnnualReport.fromJson(
    await _send('GET', '/manager/sites/$siteCode/annual-report', query: <String, String>{'year': '$year', if (growthBp != null) 'growth_bp': '$growthBp'}),
  );

  /// Yöneticinin düzenlemelerini saklar (boş metin = düzenleme yok).
  Future<void> save(int siteCode, int year, Map<String, String> edits, int growthBp) async {
    await _send('PUT', '/manager/sites/$siteCode/annual-report/$year', body: <String, dynamic>{'edits': edits, 'growth_bp': growthBp});
  }

  Future<Map<String, dynamic>> _send(String method, String path, {Map<String, dynamic>? body, Map<String, String>? query}) async {
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
      response = await _client.send(request).then(http.Response.fromStream).timeout(const Duration(seconds: 45));
    } on Exception {
      throw ApiException('Sunucuya bağlanılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.');
    }
    Map<String, dynamic> payload = const <String, dynamic>{};
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) payload = decoded;
    } on FormatException {
      // JSON olmayan gövde: aşağıda genel hata.
    }
    if (response.statusCode == 200) return payload;
    final message = payload['error'];
    final error = ApiException(
      message is String && message.trim().isNotEmpty ? message : 'İşlem başarısız (${response.statusCode}).',
      statusCode: response.statusCode,
      code: payload['code'] is String ? payload['code'] as String : null,
      payload: payload.isEmpty ? null : payload,
    );
    if (error.invalidatesSession) unawaited(authService.refreshSession(force: true));
    throw error;
  }
}
