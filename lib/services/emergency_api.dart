// Acil durum akışı (sunucu 107) uçları: sitelerin adresi + asansör bakım firması ve yöneticinin firma kaydı. Kurallar diğer modül uçlarıyla
// aynı: mutasyon yeniden denenmez, 401 oturum bitişidir. Telefon numarası günlüğe YAZILMAZ.
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:site_kapi_kontrol/models/emergency_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';

class EmergencyService {
  EmergencyService({required this.authService, http.Client? client}) : _client = client ?? http.Client();

  final AuthService authService;
  final http.Client _client;

  String get _base => authService.api.baseUrl.replaceAll(RegExp(r'/+$'), '');

  /// Çağıranın bağlı olduğu sitelerin acil durum bilgisi (kapsam sunucuda hesaplanır).
  Future<List<EmergencySite>> listSites() async {
    final json = await _send('GET', '/app/emergency');
    final raw = json['sites'];
    if (raw is! List) return const <EmergencySite>[];
    return <EmergencySite>[
      for (final entry in raw)
        if (entry is Map<String, dynamic>) EmergencySite.fromJson(entry),
    ];
  }

  /// Yönetici: asansör bakım firmasını YERİNE yazar. İkisi de boşsa kayıt silinir. Dönüş: sunucunun temizleyip sakladığı değerler.
  Future<({String? name, String? phone})> saveElevatorFirm(int siteCode, {String? name, String? phone}) async {
    final json = await _send(
      'PUT',
      '/manager/sites/$siteCode/emergency',
      body: <String, dynamic>{'elevator_firm_name': name, 'elevator_firm_phone': phone},
    );
    String? text(Object? value) => value is String && value.trim().isNotEmpty ? value.trim() : null;
    return (name: text(json['elevator_firm_name']), phone: text(json['elevator_firm_phone']));
  }

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
      response = await _client.send(request).then(http.Response.fromStream).timeout(const Duration(seconds: 20));
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
