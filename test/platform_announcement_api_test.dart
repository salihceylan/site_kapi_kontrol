// Platform Faz 3a (Duyuru ve Bildirim): AuthApi / AuthService uçları (docs/PLATFORM_DUYURU.md).
//
// MockClient ile: uç yolları, HTTP yöntemleri, gövdeler, sorgu parametreleri, Bearer başlığı, hata kodu ->
// Türkçe mesaj eşlemeleri. Yanıt gövdeleri sunucunun gerçek biçimindedir. Sunucu gerekmez.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:site_kapi_kontrol/models/announcement.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

class _Recorder {
  final List<http.Request> requests = <http.Request>[];

  http.Request get last => requests.last;

  Map<String, dynamic> get lastBody => jsonDecode(last.body) as Map<String, dynamic>;
}

AuthApi _api(_Recorder rec, FutureOr<http.Response> Function(http.Request request) handler) {
  return AuthApi(
    baseUrl: 'https://api.example.test',
    client: MockClient((request) async {
      rec.requests.add(request);
      return handler(request);
    }),
    retryDelay: Duration.zero,
  );
}

Map<String, dynamic> _detailBody({int id = 41, String status = 'draft'}) => <String, dynamic>{
  'id': id,
  'title': 'Asansör bakımı',
  'body_preview': 'Yarın 10:00-12:00',
  'importance': 'normal',
  'status': status,
  'target_type': 'site',
  'publish_at': null,
  'published_at': null,
  'edited_at': null,
  'send_email': false,
  'recipient_count': 0,
  'read_count': 0,
  'created_at': '2026-10-15T20:00:00.000Z',
  'created_by_name': 'Site Yöneticisi',
  'body': 'Yarın 10:00-12:00 arası asansör yok.',
  'target': <String, dynamic>{
    'type': 'site',
    'block_ids': <int>[],
    'apartment_ids': <int>[],
    'labels': <String>['Tüm site'],
  },
  'stats': <String, dynamic>{
    'recipients': 0,
    'read': 0,
    'unread': 0,
    'email': <String, dynamic>{
      'requested': 0,
      'sent': 0,
      'failed': 0,
      'no_address': 0,
      'skipped_pref': 0,
      'capped': 0,
      'duplicate': 0,
      'pending': 0,
    },
  },
};

Map<String, dynamic> _error(String code, String message) => <String, dynamic>{
  'error': message,
  'code': code,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AuthApi: yönetici duyuru uçları', () {
    test('listAnnouncements: GET, durum / arama / sayfa sorguya yazılır, boş arama atlanır', () async {
      final rec = _Recorder();
      final api = _api(rec, (r) => _json(<String, dynamic>{
        'items': <Map<String, dynamic>>[_detailBody()],
        'total': 7,
      }));

      final page = await api.listAnnouncements(
        token: 'tok',
        siteCode: 7,
        status: 'published',
        query: '  asansör ',
        limit: 20,
        offset: 40,
      );
      expect(rec.last.method, 'GET');
      expect(rec.last.url.path, '/manager/sites/7/announcements');
      expect(rec.last.headers['Authorization'], 'Bearer tok');
      expect(rec.last.url.queryParameters, <String, String>{
        'status': 'published',
        'q': 'asansör',
        'limit': '20',
        'offset': '40',
      });
      expect(page.total, 7);
      expect(page.items.single.title, 'Asansör bakımı');

      await api.listAnnouncements(token: 'tok', siteCode: 7, query: '   ');
      expect(rec.last.url.queryParameters, <String, String>{'limit': '30', 'offset': '0'});
      await api.listAnnouncements(token: 'tok', siteCode: 7, status: 'all');
      expect(rec.last.url.queryParameters['status'], 'all');
    });

    test('getAnnouncement: GET /announcements/:id, ayrıntı ayrışır', () async {
      final rec = _Recorder();
      final api = _api(rec, (r) => _json(_detailBody(id: 12)));
      final detail = await api.getAnnouncement(token: 'tok', siteCode: 7, announcementId: 12);
      expect(rec.last.method, 'GET');
      expect(rec.last.url.path, '/manager/sites/7/announcements/12');
      expect(detail.id, 12);
      expect(detail.body, contains('asansör'));
      expect(detail.target.summary(), 'Tüm site');
    });

    test('listAnnouncementRecipients: okundu süzgeci, arama ve sayfa', () async {
      final rec = _Recorder();
      final api = _api(rec, (r) => _json(<String, dynamic>{
        'items': <Map<String, dynamic>>[
          <String, dynamic>{
            'person_id': 5,
            'full_name': 'Ayşe Yılmaz',
            'apartments': <String>['A Blok - 5'],
            'has_account': true,
            'read_at': null,
            'email_status': 'pending',
          },
        ],
        'total': 1,
      }));
      final page = await api.listAnnouncementRecipients(
        token: 'tok',
        siteCode: 7,
        announcementId: 12,
        read: 'false',
        query: ' ayşe ',
        limit: 25,
        offset: 50,
      );
      expect(rec.last.method, 'GET');
      expect(rec.last.url.path, '/manager/sites/7/announcements/12/recipients');
      expect(rec.last.url.queryParameters, <String, String>{
        'read': 'false',
        'q': 'ayşe',
        'limit': '25',
        'offset': '50',
      });
      expect(page.items.single.emailStatus, EmailDelivery.pending);
      await api.listAnnouncementRecipients(token: 'tok', siteCode: 7, announcementId: 12);
      expect(rec.last.url.queryParameters, <String, String>{'limit': '50', 'offset': '0'});
    });

    test('previewAnnouncementAudience: POST preview-audience, hedef + e-posta bayrağı', () async {
      final rec = _Recorder();
      final api = _api(rec, (r) => _json(<String, dynamic>{
        'people': 48,
        'apartments': 30,
        'with_account': 40,
        'with_email': 44,
        'without_email': 4,
      }));
      final preview = await api.previewAnnouncementAudience(
        token: 'tok',
        siteCode: 7,
        target: const AnnouncementTargetInput(
          type: AnnouncementTargetType.blocks,
          blockIds: <int>[3, 4],
        ),
        sendEmail: true,
      );
      expect(rec.last.method, 'POST');
      expect(rec.last.url.path, '/manager/sites/7/announcements/preview-audience');
      expect(rec.lastBody, <String, dynamic>{
        'target': <String, dynamic>{
          'type': 'blocks',
          'block_ids': <int>[3, 4],
        },
        'send_email': true,
      });
      expect(preview.people, 48);
      expect(preview.withoutEmail, 4);
    });

    test('createAnnouncement: POST 201; metinler kırpılır, zamanlama UTC ISO olarak gider', () async {
      final rec = _Recorder();
      final api = _api(rec, (r) => _json(_detailBody(status: 'scheduled'), 201));

      await api.createAnnouncement(
        token: 'tok',
        siteCode: 7,
        title: '  Asansör bakımı ',
        body: ' Yarın asansör yok. ',
        target: const AnnouncementTargetInput(),
        importance: AnnouncementImportance.urgent,
        sendEmail: true,
        publish: 'schedule',
        publishAt: DateTime.utc(2026, 10, 20, 11, 30),
      );
      expect(rec.last.method, 'POST');
      expect(rec.last.url.path, '/manager/sites/7/announcements');
      expect(rec.lastBody, <String, dynamic>{
        'title': 'Asansör bakımı',
        'body': 'Yarın asansör yok.',
        'importance': 'urgent',
        'target': <String, dynamic>{'type': 'site'},
        'send_email': true,
        'publish': 'schedule',
        'publish_at': '2026-10-20T11:30:00.000Z',
      });

      // Taslak / şimdi: publish_at gitmez (zamanlama yalnız "schedule" ile anlamlı).
      await api.createAnnouncement(
        token: 'tok',
        siteCode: 7,
        title: 'T',
        body: 'B',
        target: const AnnouncementTargetInput(),
        publishAt: DateTime.utc(2026, 10, 20),
      );
      expect(rec.lastBody['publish'], 'draft');
      expect(rec.lastBody.containsKey('publish_at'), isFalse);
      expect(rec.lastBody['importance'], 'normal');
      expect(rec.lastBody['send_email'], false);
    });

    test('updateAnnouncement / publish / withdraw / delete: yöntem ve yollar', () async {
      final rec = _Recorder();
      final api = _api(rec, (r) {
        if (r.method == 'DELETE') return _json(<String, dynamic>{'ok': true});
        return _json(_detailBody(id: 12, status: 'published'));
      });

      final updated = await api.updateAnnouncement(
        token: 'tok',
        siteCode: 7,
        announcementId: 12,
        fields: <String, Object?>{'title': 'Yeni', 'publish_at': null},
      );
      expect(rec.last.method, 'PATCH');
      expect(rec.last.url.path, '/manager/sites/7/announcements/12');
      expect(rec.lastBody, <String, dynamic>{'title': 'Yeni', 'publish_at': null});
      expect(updated.status, AnnouncementStatus.published);

      await api.publishAnnouncement(token: 'tok', siteCode: 7, announcementId: 12);
      expect(rec.last.method, 'POST');
      expect(rec.last.url.path, '/manager/sites/7/announcements/12/publish');

      await api.withdrawAnnouncement(token: 'tok', siteCode: 7, announcementId: 12);
      expect(rec.last.method, 'POST');
      expect(rec.last.url.path, '/manager/sites/7/announcements/12/withdraw');

      await api.deleteAnnouncement(token: 'tok', siteCode: 7, announcementId: 12);
      expect(rec.last.method, 'DELETE');
      expect(rec.last.url.path, '/manager/sites/7/announcements/12');
    });

    test('hata kodları Türkçe mesaja çevrilir ve ApiException.code korunur', () async {
      final cases = <(int, String, String, String)>[
        (404, 'ANNOUNCEMENT_NOT_FOUND', 'Duyuru bulunamadı.', 'Duyuru bulunamadı ya da artık yayında değil.'),
        (409, 'INVALID_STATE', 'Duyuru zaten yayınlanmış.', 'Duyurunun durumu değişmiş. Listeyi yenileyip tekrar deneyin.'),
        (409, 'NO_RECIPIENTS', 'Seçilen hedefte duyuruyu alacak kimse bulunamadı.', 'Seçilen hedefte duyuruyu alacak kimse yok. Hedefi değiştirin.'),
        (400, 'INVALID_TARGET', 'Seçilen blok veya daireler bu siteye ait değil.', 'Seçilen blok veya daireler bu siteye ait değil. Hedefi yeniden seçin.'),
        (400, 'INVALID_SCHEDULE', 'Yayın zamanı geçersiz.', 'Yayın zamanı geçersiz. En az 1 dakika, en çok 1 yıl sonrası seçin.'),
        (400, 'ANNOUNCEMENT_EMAIL_LIMIT', 'E-posta gönderilecek kişi sayısı tek yayında 1000 adresi aşıyor.', 'Tek seferde en çok 1000 kişiye e-posta gönderilebilir. Hedefi bölüp ayrı duyurular oluşturun.'),
        (403, 'FORBIDDEN_ROLE', 'Bu işlem için yetkiniz yok.', 'Bu işlem için yetkiniz yok.'),
      ];
      for (final (status, code, serverText, expected) in cases) {
        final rec = _Recorder();
        final api = _api(rec, (r) => _json(_error(code, serverText), status));
        await expectLater(
          api.publishAnnouncement(token: 'tok', siteCode: 7, announcementId: 1),
          throwsA(
            isA<ApiException>()
                .having((e) => e.message, 'message', expected)
                .having((e) => e.code, 'code', code)
                .having((e) => e.statusCode, 'status', status),
          ),
          reason: code,
        );
      }
    });

    test('INVALID_BODY: sunucunun Türkçe etiketli metni gösterilir; alan adı sızarsa genel metne düşer', () async {
      final rec = _Recorder();
      final okApi = _api(rec, (r) => _json(_error('INVALID_BODY', 'Başlık boş olamaz.'), 400));
      await expectLater(
        okApi.createAnnouncement(
          token: 'tok',
          siteCode: 7,
          title: 'x',
          body: 'y',
          target: const AnnouncementTargetInput(),
        ),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Başlık boş olamaz.')),
      );
      final jargonApi = _api(rec, (r) => _json(_error('INVALID_BODY', 'send_email must be boolean'), 400));
      await expectLater(
        jargonApi.createAnnouncement(
          token: 'tok',
          siteCode: 7,
          title: 'x',
          body: 'y',
          target: const AnnouncementTargetInput(),
        ),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', AuthApi.jargonFallbackMessage)),
      );
    });
  });

  group('AuthApi: sakin uçları', () {
    test('listMyAnnouncements: GET /app/announcements, imleç ve site süzgeci', () async {
      final rec = _Recorder();
      final api = _api(rec, (r) => _json(<String, dynamic>{
        'items': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 41,
            'site_code': 11,
            'site_name': 'Gül Sitesi',
            'title': 'Su kesintisi',
            'body_preview': 'Yarın su yok.',
            'importance': 'urgent',
            'published_at': '2026-10-16T08:00:00.000Z',
            'edited_at': null,
            'is_read': false,
          },
        ],
        'next_before_id': 41,
      }));
      final page = await api.listMyAnnouncements(token: 'tok', limit: 20, beforeId: 60, siteCode: 11);
      expect(rec.last.method, 'GET');
      expect(rec.last.url.path, '/app/announcements');
      expect(rec.last.url.queryParameters, <String, String>{
        'limit': '20',
        'before_id': '60',
        'site_code': '11',
      });
      expect(page.nextBeforeId, 41);
      expect(page.items.single.isUrgent, isTrue);

      await api.listMyAnnouncements(token: 'tok');
      expect(rec.last.url.queryParameters, <String, String>{'limit': '30'});
    });

    test('getMyAnnouncement okundu YAZMAZ; markAnnouncementRead POST /read ilk okuma zamanını döndürür', () async {
      final rec = _Recorder();
      final api = _api(rec, (r) {
        if (r.url.path.endsWith('/read')) {
          return _json(<String, dynamic>{'ok': true, 'read_at': '2026-10-16T09:00:00.000Z'});
        }
        return _json(<String, dynamic>{
          'id': 41,
          'site_code': 11,
          'site_name': 'Gül Sitesi',
          'title': 'Su kesintisi',
          'body': 'Tam metin',
          'importance': 'normal',
          'published_at': '2026-10-16T08:00:00.000Z',
          'edited_at': null,
          'is_read': false,
          'read_at': null,
        });
      });
      final detail = await api.getMyAnnouncement(token: 'tok', announcementId: 41);
      expect(rec.requests.length, 1);
      expect(rec.last.method, 'GET');
      expect(rec.last.url.path, '/app/announcements/41');
      expect(detail.body, 'Tam metin');

      final readAt = await api.markAnnouncementRead(token: 'tok', announcementId: 41);
      expect(rec.last.method, 'POST');
      expect(rec.last.url.path, '/app/announcements/41/read');
      expect(readAt, DateTime.utc(2026, 10, 16, 9));
    });

    test('markAllAnnouncementsRead: site_code yalnız verilirse gider; işaretlenen adet döner', () async {
      final rec = _Recorder();
      final api = _api(rec, (r) => _json(<String, dynamic>{'ok': true, 'marked': 3}));
      expect(await api.markAllAnnouncementsRead(token: 'tok'), 3);
      expect(rec.last.method, 'POST');
      expect(rec.last.url.path, '/app/announcements/read-all');
      expect(rec.lastBody, <String, dynamic>{});
      await api.markAllAnnouncementsRead(token: 'tok', siteCode: 11);
      expect(rec.lastBody, <String, dynamic>{'site_code': 11});
    });

    test('getNotificationSummary: GET, eklemeli latest_published_at okunur', () async {
      final rec = _Recorder();
      final api = _api(rec, (r) => _json(<String, dynamic>{
        'unread_announcements': 3,
        'unread_urgent': 1,
        'latest_announcement_id': 41,
        'latest_published_at': '2026-10-16T08:00:00.000Z',
        'server_time': '2026-10-16T08:00:20.000Z',
      }));
      final s = await api.getNotificationSummary(token: 'tok');
      expect(rec.last.method, 'GET');
      expect(rec.last.url.path, '/app/notifications/summary');
      expect(s.unreadAnnouncements, 3);
      expect(s.unreadUrgent, 1);
      expect(s.latestPublishedAt, DateTime.utc(2026, 10, 16, 8));
    });

    test('bildirim tercihleri: GET; PUT yalnız email_announcements gönderir (push_* değişmez)', () async {
      final rec = _Recorder();
      final api = _api(rec, (r) {
        if (r.method == 'PUT') {
          return _json(<String, dynamic>{
            'email_announcements': false,
            'push_announcements': true,
            'push_available': false,
          });
        }
        return _json(<String, dynamic>{
          'email_announcements': true,
          'push_announcements': true,
          'push_available': false,
        });
      });
      final before = await api.getNotificationPreferences(token: 'tok');
      expect(rec.last.url.path, '/app/notification-preferences');
      expect(before.emailAnnouncements, isTrue);
      expect(before.pushAvailable, isFalse);

      final after = await api.setNotificationPreferences(token: 'tok', emailAnnouncements: false);
      expect(rec.last.method, 'PUT');
      expect(rec.lastBody, <String, dynamic>{'email_announcements': false});
      expect(after.emailAnnouncements, isFalse);
    });

    test('sakin uçlarında 404 / 429 Türkçe mesajla ApiException olur', () async {
      final rec = _Recorder();
      final notFound = _api(rec, (r) => _json(_error('ANNOUNCEMENT_NOT_FOUND', 'Duyuru bulunamadı.'), 404));
      await expectLater(
        notFound.getMyAnnouncement(token: 'tok', announcementId: 9),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'ANNOUNCEMENT_NOT_FOUND')),
      );
      final limited = _api(
        rec,
        (r) => http.Response(
          jsonEncode(<String, dynamic>{'error': 'Çok fazla istek. Biraz sonra tekrar deneyin.'}),
          429,
          headers: {'content-type': 'application/json; charset=utf-8', 'retry-after': '90'},
        ),
      );
      await expectLater(
        limited.getNotificationSummary(token: 'tok'),
        throwsA(isA<ApiException>().having((e) => e.isRateLimited, 'rateLimited', isTrue)),
      );
    });
  });

  group('AuthService: duyuru sarmalayıcıları', () {
    UserSession session0({UserRole role = UserRole.apartmentOwner}) => UserSession(
      id: 5,
      fullName: 'Ali Veli',
      email: 'ali@example.com',
      loginName: null,
      role: role,
      isActive: true,
      token: 'tok-A',
    );

    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      FlutterSecureStorage.setMockInitialValues(<String, String>{});
    });

    Future<({AuthService service, _Recorder rec})> makeService(
      FutureOr<http.Response> Function(http.Request request) handler, {
      UserRole role = UserRole.siteManager,
    }) async {
      FlutterSecureStorage.setMockInitialValues(<String, String>{
        'auth_session': jsonEncode(session0(role: role).toJson()),
      });
      final rec = _Recorder();
      final service = AuthService(api: _api(rec, (r) {
        if (r.url.path == '/me') {
          return _json({
            'user': {
              'id': 5,
              'full_name': 'Ali Veli',
              'email': 'ali@example.com',
              'login_name': null,
              'role': role.apiValue,
              'is_active': true,
            },
          });
        }
        return handler(r);
      }));
      await service.initialize();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      rec.requests.clear();
      return (service: service, rec: rec);
    }

    test('tüm sarmalayıcılar oturum belirteciyle sözleşmedeki yollara gider', () async {
      final h = await makeService((r) {
        final path = r.url.path;
        if (path == '/manager/sites/7/announcements' && r.method == 'GET') {
          return _json(<String, dynamic>{'items': <dynamic>[], 'total': 0});
        }
        if (path.endsWith('/preview-audience')) {
          return _json(<String, dynamic>{
            'people': 1,
            'apartments': 1,
            'with_account': 1,
            'with_email': 1,
            'without_email': 0,
          });
        }
        if (path.endsWith('/recipients')) return _json(<String, dynamic>{'items': <dynamic>[], 'total': 0});
        if (r.method == 'DELETE') return _json(<String, dynamic>{'ok': true});
        if (path == '/app/announcements' && r.method == 'GET') {
          return _json(<String, dynamic>{'items': <dynamic>[], 'next_before_id': null});
        }
        if (path == '/app/announcements/read-all') return _json(<String, dynamic>{'ok': true, 'marked': 2});
        if (path.endsWith('/read')) return _json(<String, dynamic>{'ok': true, 'read_at': '2026-10-16T09:00:00Z'});
        if (path.startsWith('/app/announcements/')) {
          return _json(<String, dynamic>{'id': 41, 'title': 'T', 'body': 'B'});
        }
        if (path == '/app/notifications/summary') {
          return _json(<String, dynamic>{'unread_announcements': 0, 'unread_urgent': 0});
        }
        if (path == '/app/notification-preferences') {
          return _json(<String, dynamic>{'email_announcements': false, 'push_announcements': true});
        }
        if (r.method == 'POST' && path == '/manager/sites/7/announcements') {
          return _json(_detailBody(), 201);
        }
        return _json(_detailBody());
      });
      final s = h.service;

      await s.listAnnouncements(7, status: 'draft', query: 'a');
      expect(h.rec.last.headers['Authorization'], 'Bearer tok-A');
      expect(h.rec.last.url.path, '/manager/sites/7/announcements');
      expect(h.rec.last.url.queryParameters['status'], 'draft');

      await s.getAnnouncement(7, 41);
      expect(h.rec.last.url.path, '/manager/sites/7/announcements/41');

      await s.listAnnouncementRecipients(7, 41, read: 'true');
      expect(h.rec.last.url.path, '/manager/sites/7/announcements/41/recipients');
      expect(h.rec.last.url.queryParameters['read'], 'true');

      await s.previewAnnouncementAudience(7, const AnnouncementTargetInput(), sendEmail: true);
      expect(h.rec.last.method, 'POST');
      expect(h.rec.lastBody['send_email'], true);

      await s.createAnnouncement(
        7,
        title: 'T',
        body: 'B',
        target: const AnnouncementTargetInput(),
        publish: 'now',
      );
      expect(h.rec.last.method, 'POST');
      expect(h.rec.lastBody['publish'], 'now');

      await s.updateAnnouncement(7, 41, <String, Object?>{'body': 'Yeni'});
      expect(h.rec.last.method, 'PATCH');
      expect(h.rec.lastBody, <String, dynamic>{'body': 'Yeni'});

      await s.publishAnnouncement(7, 41);
      expect(h.rec.last.url.path, '/manager/sites/7/announcements/41/publish');
      await s.withdrawAnnouncement(7, 41);
      expect(h.rec.last.url.path, '/manager/sites/7/announcements/41/withdraw');
      await s.deleteAnnouncement(7, 41);
      expect(h.rec.last.method, 'DELETE');

      await s.listMyAnnouncements(beforeId: 5, siteCode: 11);
      expect(h.rec.last.url.queryParameters['before_id'], '5');
      await s.getMyAnnouncement(41);
      expect(h.rec.last.url.path, '/app/announcements/41');
      await s.markAnnouncementRead(41);
      expect(h.rec.last.url.path, '/app/announcements/41/read');
      expect(await s.markAllAnnouncementsRead(siteCode: 11), 2);
      expect(h.rec.lastBody, <String, dynamic>{'site_code': 11});
      await s.getNotificationSummary();
      expect(h.rec.last.url.path, '/app/notifications/summary');
      expect((await s.getNotificationPreferences()).emailAnnouncements, isFalse);
      final saved = await s.setNotificationPreferences(emailAnnouncements: true);
      expect(h.rec.last.method, 'PUT');
      expect(saved.emailAnnouncements, isFalse, reason: 'sunucu yanıtı geçerlidir');
    });

    test('oturum yokken Türkçe ApiException ve ağ isteği yapılmaz', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      FlutterSecureStorage.setMockInitialValues(<String, String>{});
      final rec = _Recorder();
      final loggedOut = AuthService(api: _api(rec, (r) => _json(<String, dynamic>{})));
      await expectLater(
        loggedOut.getNotificationSummary(),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Oturum açmanız gerekmektedir.')),
      );
      expect(rec.requests, isEmpty);
    });
  });
}
