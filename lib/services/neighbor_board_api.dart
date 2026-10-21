// Komşu Panosu (`neighbor_board`) uçları. Kurallar DecisionBookApi ile aynı: mutasyonlar yeniden denenmez, 401 oturum
// bitişidir, ilan metni günlüğe YAZILMAZ.
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:site_kapi_kontrol/models/neighbor_post.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';

class NeighborBoardService {
  NeighborBoardService({required this.authService, http.Client? client}) : _client = client ?? http.Client();

  final AuthService authService;
  final http.Client _client;

  String get _base => authService.api.baseUrl.replaceAll(RegExp(r'/+$'), '');

  /// Sakin: yayındaki ilanlar + kendi bekleyen / reddedilen ilanları.
  Future<List<NeighborPost>> listResident(int siteCode) async =>
      _items(await _send('GET', '/app/neighbor-board', query: {'site_code': '$siteCode'}));

  /// Yönetim: [status] pending | published | rejected | removed | reported.
  Future<List<NeighborPost>> listManaged(int siteCode, String status) async =>
      _items(await _send('GET', '/manager/sites/$siteCode/neighbor-board', query: {'status': status}));

  Future<void> create(int siteCode, String title, String body) async {
    await _send('POST', '/app/neighbor-board', body: {'site_code': siteCode, 'title': title, 'body': body}, ok: {201});
  }

  Future<void> report(int id, String reason) async {
    await _send('POST', '/app/neighbor-board/$id/report', body: {'reason': reason});
  }

  Future<void> withdraw(int id) async {
    await _send('POST', '/app/neighbor-board/$id/withdraw', body: const <String, dynamic>{});
  }

  /// [action]: approve | reject | remove (reject / remove için [note] zorunlu).
  Future<void> decide(int siteCode, int id, String action, {String? note}) async {
    await _send('POST', '/manager/sites/$siteCode/neighbor-board/$id/$action', body: {'note': ?note});
  }

  List<NeighborPost> _items(Map<String, dynamic> json) {
    final raw = json['items'];
    if (raw is! List) return const <NeighborPost>[];
    return <NeighborPost>[
      for (final e in raw)
        if (e is Map<String, dynamic>) NeighborPost.fromJson(e),
    ];
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    Set<int> ok = const <int>{200},
  }) async {
    final token = authService.session?.token;
    if (token == null) throw ApiException('Oturum açmanız gerekmektedir.');
    final uri = Uri.parse('$_base$path').replace(queryParameters: query);
    final request = http.Request(method, uri)
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
      // JSON olmayan gövde (araya giren katman): aşağıda genel hata.
    }
    if (ok.contains(response.statusCode)) return payload;
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
