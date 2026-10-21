// Beyaz etiket tema (G9; docs/PLATFORM_BEYAZ_ETIKET.md) uçları. Yalnız HTTP katmanı: belirteç oturumdan alınır, hata gövdesi Türkçe
// [ApiException]'a çevrilir. Yazma ASLA otomatik yeniden denenmez; belirteç ve logo günlüğe yazılmaz.
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:site_kapi_kontrol/brand/brand_theme.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';

class BrandThemeService {
  BrandThemeService({required this.authService, http.Client? client}) : _client = client ?? http.Client();

  final AuthService authService;
  final http.Client _client;

  String get _base => authService.api.baseUrl.replaceAll(RegExp(r'/+$'), '');

  Future<Map<String, dynamic>> _call(String method, String path, {Map<String, dynamic>? body}) async {
    final token = authService.session?.token;
    if (token == null) throw ApiException('Oturum açmanız gerekmektedir.');
    final request = http.Request(method, Uri.parse('$_base$path'))
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

  /// Oturumdaki kullanıcının etkin teması; yok ya da okunaksızsa null (varsayılan Gude).
  Future<BrandTheme?> mine() async => BrandTheme.tryParse((await _call('GET', '/brand-theme/mine'))['theme']);

  /// Kapsamın ([scopeType]: 'company' | 'site') kendi kaydı; yoksa null.
  Future<BrandTheme?> forScope(String scopeType, int scopeId) async =>
      BrandTheme.tryParse((await _call('GET', '/brand-themes/$scopeType/$scopeId'))['theme']);

  /// Kaydeder. [logoData] verilmezse sunucudaki logo korunur ([removeLogo] true ise silinir).
  Future<BrandTheme?> save(String scopeType, int scopeId, BrandTheme theme, {String? logoData, bool removeLogo = false}) async {
    final body = theme.toJson();
    if (removeLogo) {
      body['logo_data'] = null;
    } else if (logoData != null) {
      body['logo_data'] = logoData;
    }
    return BrandTheme.tryParse((await _call('PUT', '/brand-themes/$scopeType/$scopeId', body: body))['theme']);
  }

  Future<void> reset(String scopeType, int scopeId) => _call('DELETE', '/brand-themes/$scopeType/$scopeId');
}
