// Site menü yerleşimi (K8, P1-16) uçları: site başına "kompakt menü" kümesi. Sözleşme: docs/PLATFORM_MENU_KATMANI.md.
//
// YETENEK (modül açık / kapalı) bu uçlarla DEĞİŞMEZ: yalnız ana menüde (çekmece + Panel vitrini) hangi modüllerin öne çıkacağı saklanır.
// Kurallar diğer modül uçlarıyla aynıdır: mutasyon yeniden denenmez, 401 oturum bitişidir.
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:site_kapi_kontrol/models/menu_layout.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';

class MenuLayoutService {
  MenuLayoutService({required this.authService, http.Client? client}) : _client = client ?? http.Client();

  final AuthService authService;
  final http.Client _client;

  String get _base => authService.api.baseUrl.replaceAll(RegExp(r'/+$'), '');

  String _path(int siteCode) => '/manager/sites/$siteCode/menu-layout';

  /// Sitenin menü düzeni: seçili küme, yönetim türü önerilerinden türetilen varsayılan küme ve modül satırları.
  Future<SiteMenuLayoutState> load(int siteCode) async =>
      SiteMenuLayoutState.fromJson(await _send('GET', _path(siteCode)));

  /// Kompakt menü kümesini kaydeder ([compactModules]: öne çıkacak modül kodları). Sunucu varsayılanla aynı kümeyi "özelleştirme"
  /// saymaz. Modül açık / kapalı durumuna DOKUNMAZ. Güncel durumu döner.
  Future<SiteMenuLayoutState> save(int siteCode, List<String> compactModules) async => SiteMenuLayoutState.fromJson(
        await _send('PUT', _path(siteCode), body: <String, dynamic>{'compact_modules': compactModules}),
      );

  /// Varsayılana (yönetim türü önerilerinden türetilen küme) döner. Güncel durumu döner.
  Future<SiteMenuLayoutState> reset(int siteCode) async =>
      SiteMenuLayoutState.fromJson(await _send('DELETE', _path(siteCode)));

  Future<Map<String, dynamic>> _send(String method, String path, {Map<String, dynamic>? body}) async {
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
