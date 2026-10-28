// Site yöneticisinin "İşlem kayıtları" (P2-19): model, sunucu sözleşmesi ve HTTP katmanı.
//
// `test/fixtures/site_audit/server_page.json` GERÇEK sunucu servisinin (`mapSiteAuditRow`, DB'siz) ürettiği sayfadır; böylece
// sözleşme okuması ile gerçek yanıt arasındaki sapma burada yakalanır. Kategori anahtarları sunucu kataloğuyla karşılaştırılır.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:site_kapi_kontrol/models/site_audit_log.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/site_audit_log_api.dart';

Map<String, dynamic> _fixture() =>
    jsonDecode(File('test/fixtures/site_audit/server_page.json').readAsStringSync()) as Map<String, dynamic>;

http.Response _json(int status, Object body) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: <String, String>{'content-type': 'application/json; charset=utf-8'},
);

class _Auth extends AuthService {
  _Auth({this.token = 'tok'}) : super(api: AuthApi(baseUrl: 'http://localhost'));

  String? token;
  int refreshes = 0;

  @override
  UserSession? get session => token == null
      ? null
      : UserSession(id: 5, fullName: 'Ayşe', email: 'a@example.com', loginName: null, role: UserRole.siteManager, isActive: true, token: token!);

  @override
  Future<void> refreshSession({bool force = false}) async {
    refreshes++;
  }
}

void main() {
  group('model (gerçek sunucu çıktısı)', () {
    test('sayfa çözülür: sıra, imleç, alanlar', () {
      final page = SiteAuditPage.fromJson(_fixture());
      expect(page.items.map((e) => e.id), <int>[412, 411, 409, 405, 401, 399, 397, 390]);
      expect(page.nextBeforeId, 390);
      expect(page.hasMore, isTrue);
      final first = page.items.first;
      expect(first.action, 'board_decision.finalized');
      expect(first.title, 'Karar kesinleştirildi');
      expect(first.targetLabel, 'Karar 2026/5');
      expect(first.categoryLabel, 'Site hizmetleri');
      expect(first.actorLine, 'Ayşe Yönetici • Site yöneticisi');
      expect(first.createdAt!.toUtc(), DateTime.utc(2026, 10, 27, 11, 20));
    });

    test('kişisel veri asgari: süper kullanıcı adı yok, silinmiş hesap adı yok, sistem satırı', () {
      final byId = {for (final e in SiteAuditPage.fromJson(_fixture()).items) e.id: e};
      expect(byId[409]!.actorLine, 'Sistem yöneticisi');
      expect(byId[409]!.actorRole, 'super_user');
      expect(byId[405]!.actorLine, 'Sistem');
      expect(byId[401]!.actorLine, 'Silinmiş Kullanıcı • Site yöneticisi');
      final text = jsonEncode(_fixture());
      for (final forbidden in <String>[
        'actor_user_code', 'site_code', 'Gerçek Süper Ad', 'Eski Kişi Adı', 'Parola123', 'ali@example.com', 'gizli not', 'user_codes', 'request_id',
      ]) {
        expect(text.contains(forbidden), isFalse, reason: forbidden);
      }
    });

    test('hedef etiketi mevcut etiket mantığından: modül talebi, kapı izni, rol, sözleşme durumu', () {
      final byId = {for (final e in SiteAuditPage.fromJson(_fixture()).items) e.id: e};
      expect(byId[409]!.targetLabel, 'Anket ve Oylama • Talep #9');
      expect(byId[397]!.targetLabel, 'Kullanıcı 30004 • Kapı #4');
      expect(byId[390]!.targetLabel, 'Kullanıcı 20003 • Yönetim Kurulu / Denetçi');
      expect(byId[411]!.targetLabel, 'Dönem: Ekim 2026');
      expect(byId[405]!.targetLabel, 'Duyuru #5');
    });

    test('sunucu başlığı yoksa (eski sunucu) istemci tablosu; bilinmeyen eylem ham kodla değil "Diğer işlem" olarak görünür', () {
      final legacy = SiteAuditEntry.fromJson(<String, dynamic>{'id': 1, 'action': 'module.disabled', 'created_at': '2026-10-01T09:00:00Z'});
      expect(legacy.serverActionLabel, isNull);
      expect(legacy.title, 'Modül kapatıldı');
      final unknown = SiteAuditEntry.fromJson(<String, dynamic>{'id': 2, 'action': 'zzz.yeni_eylem', 'action_label': ' '});
      expect(unknown.title, 'Diğer işlem');
      expect(unknown.title.contains('zzz'), isFalse);
      expect(unknown.actorLine, 'Sistem', reason: 'ad ve rol yoksa');
    });

    test('bozuk / eksik alanlar çökmez', () {
      final entry = SiteAuditEntry.fromJson(<String, dynamic>{
        'id': '7',
        'action': 5,
        'created_at': 'bozuk',
        'details': 'metin',
        'target_id': 12,
      });
      expect(entry.id, 7);
      expect(entry.action, '5');
      expect(entry.createdAt, isNull);
      expect(entry.details, isEmpty);
      expect(entry.targetId, '12');
      final page = SiteAuditPage.fromJson(<String, dynamic>{'items': 'x', 'next_before_id': 'abc'});
      expect(page.items, isEmpty);
      expect(page.nextBeforeId, isNull);
      expect(SiteAuditPage.fromJson(<String, dynamic>{'items': <Object>[], 'next_before_id': 12}).nextBeforeId, 12);
    });
  });

  group('kategori sözleşmesi', () {
    test('istemci anahtarları sunucu kataloğuyla birebir aynı (anahtar, ad ve sıra)', () {
      final source = File('server/src/modules/site_audit_log_catalog.js').readAsStringSync();
      final block = source.substring(source.indexOf('SITE_AUDIT_CATEGORIES = Object.freeze(['), source.indexOf('SITE_AUDIT_CATEGORY_KEYS'));
      final server = <String>[
        for (final m in RegExp(r"key: '([a-z_]+)',\s*label: '([^']+)'").allMatches(block)) '${m.group(1)}|${m.group(2)}',
      ];
      expect(server, hasLength(9));
      expect(siteAuditCategories.map((c) => '${c.key}|${c.label}').toList(), server);
    });

    test('kategori adı anahtardan bulunur; bilinmeyen null', () {
      expect(siteAuditCategoryLabel('finance'), 'Aidat ve finans');
      expect(siteAuditCategoryLabel('yok'), isNull);
      expect(siteAuditCategoryLabel(null), isNull);
    });
  });

  group('HTTP katmanı', () {
    test('sorgu: from / to / category / limit / before_id; yetki başlığı; yol site kodunu taşır', () async {
      late http.Request seen;
      final api = SiteAuditLogApi(
        baseUrl: 'https://api.example.com/',
        client: MockClient((request) async {
          seen = request;
          return _json(200, _fixture());
        }),
      );
      final page = await api.list('tok', 11, from: DateTime(2026, 10, 1), to: DateTime(2026, 10, 31), category: 'finance', limit: 25, beforeId: 900);
      expect(seen.method, 'GET');
      expect(seen.url.path, '/manager/sites/11/audit-log');
      expect(seen.url.queryParameters, <String, String>{'from': '2026-10-01', 'to': '2026-10-31', 'category': 'finance', 'limit': '25', 'before_id': '900'});
      expect(seen.headers['Authorization'], 'Bearer tok');
      expect(seen.headers['Accept'], 'application/json');
      expect(page.items, hasLength(8));
    });

    test('süzgeçsiz sorgu yalnız limit taşır; tek haneli gün/ay sıfırla doldurulur; boş kategori gönderilmez', () async {
      late Uri seen;
      final api = SiteAuditLogApi(
        baseUrl: 'https://api.example.com',
        client: MockClient((request) async {
          seen = request.url;
          return _json(200, <String, dynamic>{'items': <Object>[], 'next_before_id': null});
        }),
      );
      await api.list('tok', 11, category: '');
      expect(seen.queryParameters, <String, String>{'limit': '50'});
      await api.list('tok', 11, from: DateTime(2026, 3, 5));
      expect(seen.queryParameters['from'], '2026-03-05');
      expect(siteAuditDayParam(DateTime(2026, 1, 9)), '2026-01-09');
      expect(siteAuditDayParam(DateTime(987, 12, 31)), '0987-12-31');
    });

    test('hata eşlemesi: yetki, site, tarih, sorgu, hız sınırı; oturum bitişi', () async {
      Future<ApiException> errorOf(int status, Map<String, dynamic> body) async {
        final api = SiteAuditLogApi(baseUrl: 'https://api.example.com', client: MockClient((_) async => _json(status, body)));
        try {
          await api.list('tok', 11);
        } on ApiException catch (e) {
          return e;
        }
        fail('hata bekleniyordu');
        throw StateError('ulaşılmaz');
      }

      var e = await errorOf(403, <String, dynamic>{'error': 'x', 'code': 'FORBIDDEN_ROLE'});
      expect(e.message, 'İşlem kayıtlarını yalnızca site yöneticisi görebilir.');
      expect(e.statusCode, 403);
      e = await errorOf(403, <String, dynamic>{'error': 'x', 'code': 'FORBIDDEN_SITE'});
      expect(e.message, 'Bu siteye erişim yetkiniz yok.');
      e = await errorOf(404, <String, dynamic>{'error': 'Site bulunamadı.', 'code': 'SITE_NOT_FOUND'});
      expect(e.message, 'Site bulunamadı.');
      e = await errorOf(400, <String, dynamic>{'error': 'x', 'code': 'INVALID_DATE_RANGE'});
      expect(e.message, 'Başlangıç tarihi bitiş tarihinden sonra olamaz.');
      e = await errorOf(400, <String, dynamic>{'error': 'x', 'code': 'INVALID_QUERY'});
      expect(e.message, contains('Filtre geçersiz'));
      e = await errorOf(429, <String, dynamic>{'error': 'Çok fazla istek.', 'retry_after_seconds': 42});
      expect(e.message, 'Çok fazla istek. Biraz sonra tekrar deneyin.');
      expect(e.retryAfterSeconds, 42);
      e = await errorOf(500, <String, dynamic>{'error': 'İşlem kayıtları yüklenemedi.', 'errorId': 'abc'});
      expect(e.message, 'İşlem kayıtları yüklenemedi.');
      e = await errorOf(401, <String, dynamic>{'error': 'Geçersiz token.'});
      expect(e, isA<SessionExpiredException>());
      expect(e.invalidatesSession, isTrue);
    });

    test('ağ hatası ve JSON olmayan gövde anlaşılır Türkçe mesaj verir', () async {
      final offline = SiteAuditLogApi(baseUrl: 'https://api.example.com', client: MockClient((_) async => throw http.ClientException('yok')));
      await expectLater(
        offline.list('tok', 11),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('Sunucuya bağlanılamadı'))),
      );
      final html = SiteAuditLogApi(baseUrl: 'https://api.example.com', client: MockClient((_) async => http.Response('<html>502</html>', 502)));
      await expectLater(html.list('tok', 11), throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 502)));
      final blank = SiteAuditLogApi(baseUrl: 'https://api.example.com', client: MockClient((_) async => http.Response('', 200)));
      expect((await blank.list('tok', 11)).items, isEmpty);
    });
  });

  group('servis katmanı', () {
    test('oturum belirteci kullanılır; oturum yoksa istek atılmaz', () async {
      var calls = 0;
      String? auth;
      final api = SiteAuditLogApi(
        baseUrl: 'https://api.example.com',
        client: MockClient((request) async {
          calls++;
          auth = request.headers['Authorization'];
          return _json(200, <String, dynamic>{'items': <Object>[]});
        }),
      );
      final service = SiteAuditLogService(authService: _Auth(), api: api);
      await service.list(11);
      expect(auth, 'Bearer tok');
      final anonymous = SiteAuditLogService(authService: _Auth(token: null), api: api);
      await expectLater(anonymous.list(11), throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Oturum açmanız gerekmektedir.')));
      expect(calls, 1, reason: 'oturumsuz istek ağa çıkmaz');
    });

    test('401 oturumu yeniler ve hatayı iletir', () async {
      final auth = _Auth();
      final api = SiteAuditLogApi(baseUrl: 'https://api.example.com', client: MockClient((_) async => _json(401, <String, dynamic>{'error': 'Geçersiz token.'})));
      final service = SiteAuditLogService(authService: auth, api: api);
      await expectLater(service.list(11), throwsA(isA<SessionExpiredException>()));
      await Future<void>.delayed(Duration.zero);
      expect(auth.refreshes, 1);
    });
  });
}
