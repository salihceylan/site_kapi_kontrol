// Site yöneticisinin "İşlem Kayıtları" ekranı (SiteAuditLogView; P2-19).
//
// AGENTS.md kural 6: 320x640 x2,0 ve 360x640 x1,5, açık + koyu tema; yükleniyor / boş / hata / dolu / özel aralık / site yok
// durumları taşmaz. Kural 7: yenile düğmesi ve `reload()` (aşağı çekip yenileme) çalışır; "Daha fazla yükle" sonraki sayfayı
// `before_id` ile ekler (aynı kayıt iki kez gösterilmez) ve İLK sayfanın süzgeciyle ister. Gerçek `SiteAuditLogService` +
// `SiteAuditLogApi` sahte HTTP istemcisiyle çalışır: istek yolu ve sorgu dizesi de sınanır.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/site_audit_log_api.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/views/site_audit_log_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/site_audit_log_card.dart';

import 'dialog_layout_harness.dart' show settleFor;
import 'list_fixtures.dart';

http.Response _json(int status, Object body) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: <String, String>{'content-type': 'application/json; charset=utf-8'},
);

class _Auth extends AuthService {
  _Auth() : super(api: AuthApi(baseUrl: 'http://localhost'));

  @override
  UserSession? get session =>
      const UserSession(id: 5, fullName: 'Ayşe', email: 'a@example.com', loginName: null, role: UserRole.siteManager, isActive: true, token: 'tok');

  @override
  Future<void> refreshSession({bool force = false}) async {}
}

Map<String, dynamic> _entry(
  int id, {
  String action = 'finance.run.posted',
  String label = 'Aidat borçlandırıldı',
  String category = 'finance',
  String categoryLabel = 'Aidat ve finans',
  String actor = 'Ayşe Yönetici',
  String? roleLabel = 'Site yöneticisi',
  String? role = 'site_manager',
  String? targetType = 'finance',
  String? targetId = '2026-10',
  Map<String, dynamic> details = const <String, dynamic>{},
}) => <String, dynamic>{
  'id': id,
  'created_at': '2026-10-27T11:20:00.000Z',
  'actor_name': actor,
  'actor_role': role,
  'actor_role_label': roleLabel,
  'action': action,
  'action_label': label,
  'category': category,
  'category_label': categoryLabel,
  'target_type': targetType,
  'target_id': targetId,
  'details': details,
};

/// Sahte sunucu: kayıtlı istekleri tutar; `all` (id DESC) üzerinde `before_id` / `limit` / `category` uygular. Belirli isteği
/// kapıyla bekletmek için [gates] (sırayla tüketilir).
class _Server {
  _Server({List<Map<String, dynamic>>? all}) : all = all ?? <Map<String, dynamic>>[];

  List<Map<String, dynamic>> all;
  final List<Uri> requests = <Uri>[];
  final List<Completer<void>> gates = <Completer<void>>[];
  http.Response Function(Uri uri)? override;

  /// 1..[count] numaralı kayıtlar (en yeni = [count]).
  static List<Map<String, dynamic>> many(int count) => <Map<String, dynamic>>[
    for (var id = count; id >= 1; id--) _entry(id, details: <String, dynamic>{'count': id}),
  ];

  Future<http.Response> handle(http.Request request) async {
    requests.add(request.url);
    if (gates.isNotEmpty) await gates.removeAt(0).future;
    final custom = override;
    if (custom != null) return custom(request.url);
    final query = request.url.queryParameters;
    final before = int.tryParse(query['before_id'] ?? '');
    final limit = int.tryParse(query['limit'] ?? '') ?? 50;
    final category = query['category'];
    final rows = all
        .where((e) => (before == null || (e['id'] as int) < before) && (category == null || e['category'] == category))
        .toList();
    final page = rows.take(limit).toList();
    return _json(200, <String, dynamic>{
      'items': page,
      'next_before_id': rows.length > limit ? page.last['id'] : null,
    });
  }
}

const List<PeopleSite> _oneSite = <PeopleSite>[PeopleSite(code: 11, name: 'Gül Sitesi', canWrite: true)];
const List<PeopleSite> _twoSites = <PeopleSite>[
  PeopleSite(code: 11, name: 'Gül Sitesi', canWrite: true),
  PeopleSite(code: 12, name: 'Mavi Park', canWrite: true),
];

// 28 Ekim 2026 15:00 (İstanbul).
final DateTime _now = DateTime.utc(2026, 10, 28, 12, 0);

Future<GlobalKey<SiteAuditLogViewState>> _pump(
  WidgetTester t,
  _Server server, {
  List<PeopleSite> sites = _oneSite,
  double width = 400,
  double height = 1600,
  double scale = 1.0,
  bool dark = false,
  DateTime Function()? now,
}) async {
  final key = GlobalKey<SiteAuditLogViewState>();
  final auth = _Auth();
  final service = SiteAuditLogService(
    authService: auth,
    api: SiteAuditLogApi(baseUrl: 'http://localhost', client: MockClient(server.handle)),
  );
  await pumpList(
    t,
    SiteAuditLogView(key: key, authService: auth, sites: sites, service: service, now: now ?? () => _now),
    width: width,
    height: height,
    scale: scale,
    dark: dark,
  );
  return key;
}

Finder _key(String key) => find.byKey(ValueKey<String>(key));

void main() {
  group('taşma matrisi', () {
    listMatrix('dolu görünüm (kayıtlar + Daha fazla yükle)', (t, w, h, s, dark) async {
      final server = _Server(
        all: <Map<String, dynamic>>[
          _entry(9, details: <String, dynamic>{'count': 28}),
          _entry(
            8,
            action: 'staff_role.assigned',
            label: 'Ek rol atandı',
            category: 'roles',
            categoryLabel: 'Yetki ve roller',
            actor: 'Sistem yöneticisi',
            roleLabel: null,
            role: 'super_user',
            targetType: 'user',
            targetId: '42',
            details: <String, dynamic>{'role': 'BOARD_MEMBER'},
          ),
          _entry(
            7,
            action: 'door_permission.bulk_denied',
            label: 'Toplu kapı erişimi engellendi',
            category: 'access',
            categoryLabel: 'Kapı ve geçiş',
            actor: 'Çok Uzun Adlı Bir Site Yöneticisi Hesabı Sahibi',
            targetType: 'door',
            targetId: '12',
            details: <String, dynamic>{'count': 24},
          ),
          ...List<Map<String, dynamic>>.generate(60, (i) => _entry(6 - i)),
        ],
      );
      await _pump(t, server, width: w, height: h, scale: s, dark: dark);

      expect(find.text('İşlem Kayıtları'), findsOneWidget);
      expect(find.byType(SiteAuditLogCard), findsNWidgets(50));
      expect(find.text('Aidat borçlandırıldı'), findsWidgets);
      expect(find.text('Ek rol atandı'), findsOneWidget);
      expect(find.text('Kullanıcı 42 • Yönetim Kurulu / Denetçi'), findsOneWidget);
      expect(find.text('Sistem yöneticisi'), findsOneWidget);
      expect(find.text('Kapı #12 • 24 kişi'), findsOneWidget);
      expect(find.text('27.10.2026 14:20'), findsWidgets);
      expect(find.text('Daha fazla yükle'), findsOneWidget);
      expect(find.byTooltip('Yenile'), findsOneWidget);
      expect(find.text('İşlem türü'), findsOneWidget);
      expect(find.text('Dönem'), findsOneWidget);
      expect(find.text('Site'), findsNothing, reason: 'tek sitede site seçici yok');
    });

    listMatrix('boş durum', (t, w, h, s, dark) async {
      await _pump(t, _Server(), width: w, height: h, scale: s, dark: dark);
      expect(find.byType(EmptyCard), findsOneWidget);
      expect(find.text('Henüz işlem kaydı yok.'), findsOneWidget);
      expect(find.text('Daha fazla yükle'), findsNothing);
    });

    listMatrix('yükleniyor', (t, w, h, s, dark) async {
      final gate = Completer<void>();
      final server = _Server(all: _Server.many(3))..gates.add(gate);
      await _pump(t, server, width: w, height: h, scale: s, dark: dark);
      expect(find.byType(ListSkeleton), findsOneWidget);
      expect(find.byType(SiteAuditLogCard), findsNothing);
      // Bekleyen istek bitirilir (HTTP zaman aşımı sayacı test sonunda askıda kalmasın).
      gate.complete();
      await settleFor(t);
      expect(find.byType(SiteAuditLogCard), findsNWidgets(3));
    });

    listMatrix('hata (InlineNotice + Tekrar Dene)', (t, w, h, s, dark) async {
      final server = _Server()
        ..override = (_) => _json(403, <String, dynamic>{'error': 'Bu işlem için yetkiniz yok.', 'code': 'FORBIDDEN_ROLE'});
      await _pump(t, server, width: w, height: h, scale: s, dark: dark);
      expect(find.byType(InlineNotice), findsOneWidget);
      expect(find.text('İşlem kayıtlarını yalnızca site yöneticisi görebilir.'), findsOneWidget);
      expect(find.text('Tekrar Dene'), findsOneWidget);
      expect(find.text('Henüz işlem kaydı yok.'), findsNothing, reason: 'hata asla "kayıt yok" demez');
    });

    listMatrix('özel aralık açık + geçersiz tarih hatası', (t, w, h, s, dark) async {
      await _pump(t, _Server(all: _Server.many(2)), sites: _twoSites, width: w, height: h, scale: s, dark: dark);
      await tapText(t, 'Özel aralık');
      expect(_key('site_audit_from'), findsOneWidget);
      expect(_key('site_audit_to'), findsOneWidget);
      await t.enterText(_key('site_audit_from'), '31022026');
      await t.pump();
      expect(find.textContaining('Geçersiz tarih'), findsOneWidget);
      await tapFinder(t, _key('site_audit_apply'));
      expect(find.text('Site'), findsOneWidget, reason: 'iki sitede site seçici var');
    });

    listMatrix('site yok', (t, w, h, s, dark) async {
      await _pump(t, _Server(), sites: const <PeopleSite>[], width: w, height: h, scale: s, dark: dark);
      expect(_key('site_audit_no_site'), findsOneWidget);
      expect(find.text('Yönettiğiniz bir site yok.'), findsOneWidget);
    });
  });

  group('davranış', () {
    testWidgets('ilk istek: ilk sitenin yolu, yalnız limit 50 (süzgeç ve before_id yok); kart içeriği', (t) async {
      final server = _Server(all: <Map<String, dynamic>>[_entry(3, targetType: 'finance', targetId: '2026-10')]);
      await _pump(t, server);
      expect(server.requests, hasLength(1));
      expect(server.requests.single.path, '/manager/sites/11/audit-log');
      expect(server.requests.single.queryParameters, <String, String>{'limit': '50'});
      expect(find.byType(SiteAuditLogCard), findsOneWidget);
      expect(find.text('Aidat borçlandırıldı'), findsOneWidget);
      expect(find.text('Dönem: Ekim 2026'), findsOneWidget);
      expect(find.text('Ayşe Yönetici • Site yöneticisi'), findsOneWidget);
      expect(find.text('Aidat ve finans'), findsWidgets);
      expect(find.text('27.10.2026 14:20'), findsOneWidget, reason: 'İstanbul saati');
      expect(find.text('finance.run.posted'), findsNothing, reason: 'ham eylem kodu gösterilmez');
    });

    testWidgets('işlem türü süzgeci: sunucuya category gider, liste sıfırlanır; "Tümü" süzgeci kaldırır', (t) async {
      final server = _Server(
        all: <Map<String, dynamic>>[
          _entry(3, action: 'module.enabled', label: 'Modül açıldı', category: 'modules', categoryLabel: 'Modüller', targetType: 'module', targetId: 'finance'),
          _entry(2),
          _entry(1),
        ],
      );
      await _pump(t, server);
      expect(find.byType(SiteAuditLogCard), findsNWidgets(3));

      await tapFinder(t, find.byType(DropdownButtonFormField<String>));
      for (final label in <String>['Tümü', 'Modüller', 'Yetki ve roller', 'Kapı ve geçiş', 'Kişi ve daire kayıtları', 'Aidat ve finans']) {
        expect(find.text(label), findsWidgets, reason: label);
      }
      await tapFinder(t, find.text('Aidat ve finans').last);
      await settleFor(t);
      expect(server.requests.last.queryParameters['category'], 'finance');
      expect(server.requests.last.queryParameters.containsKey('before_id'), isFalse);
      expect(find.byType(SiteAuditLogCard), findsNWidgets(2));

      await tapFinder(t, find.byType(DropdownButtonFormField<String>));
      await tapFinder(t, find.text('Modüller').last);
      await settleFor(t);
      expect(server.requests.last.queryParameters['category'], 'modules');
      expect(find.byType(SiteAuditLogCard), findsOneWidget);
      expect(find.text('Modül açıldı'), findsOneWidget);

      await tapFinder(t, find.byType(DropdownButtonFormField<String>));
      await tapFinder(t, find.text('Tümü').last);
      await settleFor(t);
      expect(server.requests.last.queryParameters.containsKey('category'), isFalse);
      expect(find.byType(SiteAuditLogCard), findsNWidgets(3));
    });

    testWidgets('süzgece uyan kayıt yoksa "Bu filtre için işlem kaydı yok."; süzgeçsiz boş durum farklı metin', (t) async {
      final server = _Server(all: <Map<String, dynamic>>[_entry(1)]);
      await _pump(t, server);
      await tapFinder(t, find.byType(DropdownButtonFormField<String>));
      await tapFinder(t, find.text('Duyurular').last);
      await settleFor(t);
      expect(find.byType(SiteAuditLogCard), findsNothing);
      expect(find.text('Bu filtre için işlem kaydı yok.'), findsOneWidget);
      expect(find.text('Henüz işlem kaydı yok.'), findsNothing);
    });

    testWidgets('dönem ön ayarları İstanbul gününe göre from/to üretir; Tümü süzgeci kaldırır', (t) async {
      final server = _Server(all: _Server.many(2));
      await _pump(t, server);

      Map<String, String> last() => server.requests.last.queryParameters;

      await tapFinder(t, _key('site_audit_period_today'));
      await settleFor(t);
      expect(last()['from'], '2026-10-28');
      expect(last()['to'], '2026-10-28');

      await tapFinder(t, _key('site_audit_period_last_7'));
      await settleFor(t);
      expect(last()['from'], '2026-10-22');
      expect(last()['to'], '2026-10-28');

      await tapFinder(t, _key('site_audit_period_last_30'));
      await settleFor(t);
      expect(last()['from'], '2026-09-29');
      expect(last()['to'], '2026-10-28');

      await tapFinder(t, _key('site_audit_period_all'));
      await settleFor(t);
      expect(last().containsKey('from'), isFalse);
      expect(last().containsKey('to'), isFalse);
    });

    testWidgets('gece yarısını geçen İstanbul saati: UTC 27 Ekim 21:30 = İstanbul 28 Ekim 00:30 -> "Bugün" 28 Ekim', (t) async {
      final server = _Server(all: _Server.many(1));
      await _pump(t, server, now: () => DateTime.utc(2026, 10, 27, 21, 30));
      await tapFinder(t, _key('site_audit_period_today'));
      await settleFor(t);
      expect(server.requests.last.queryParameters['from'], '2026-10-28');
      expect(server.requests.last.queryParameters['to'], '2026-10-28');
    });

    testWidgets('özel aralık: seçmek istek atmaz; geçersiz / ters / boş aralık reddedilir; geçerli aralık uygulanır; tek uçlu da olur', (t) async {
      final server = _Server(all: _Server.many(2));
      await _pump(t, server);
      expect(server.requests, hasLength(1));

      await tapText(t, 'Özel aralık');
      expect(server.requests, hasLength(1), reason: 'Uygula’ya kadar yükleme değişmez');

      // Boş: en az bir tarih
      await tapFinder(t, _key('site_audit_apply'));
      expect(find.text('En az bir tarih girin (GG.AA.YYYY).'), findsOneWidget);
      expect(server.requests, hasLength(1));

      // Geçersiz gün (31.02): alan hatası, istek yok
      await t.enterText(_key('site_audit_from'), '31022026');
      await tapFinder(t, _key('site_audit_apply'));
      expect(find.textContaining('Geçersiz tarih'), findsOneWidget);
      expect(server.requests, hasLength(1));

      // Ters aralık
      await t.enterText(_key('site_audit_from'), '10102026');
      await t.enterText(_key('site_audit_to'), '09102026');
      await tapFinder(t, _key('site_audit_apply'));
      expect(find.text('Başlangıç tarihi bitiş tarihinden sonra olamaz.'), findsOneWidget);
      expect(server.requests, hasLength(1));

      // 2000 öncesi (sunucu sınırı)
      await t.enterText(_key('site_audit_from'), '01011999');
      await t.enterText(_key('site_audit_to'), '');
      await tapFinder(t, _key('site_audit_apply'));
      expect(find.text('Tarih 2000 ve sonrası olmalıdır.'), findsOneWidget);
      expect(server.requests, hasLength(1));

      // Geçerli iki uçlu aralık
      await t.enterText(_key('site_audit_from'), '01102026');
      await t.enterText(_key('site_audit_to'), '15102026');
      await tapFinder(t, _key('site_audit_apply'));
      await settleFor(t);
      expect(server.requests, hasLength(2));
      expect(server.requests.last.queryParameters['from'], '2026-10-01');
      expect(server.requests.last.queryParameters['to'], '2026-10-15');
      expect(find.byKey(const ValueKey<String>('site_audit_range_error')), findsNothing);

      // Yalnız bitiş
      await t.enterText(_key('site_audit_from'), '');
      await tapFinder(t, _key('site_audit_apply'));
      await settleFor(t);
      expect(server.requests.last.queryParameters.containsKey('from'), isFalse);
      expect(server.requests.last.queryParameters['to'], '2026-10-15');

      // Başka dönem: özel aralık süzgeci kalkar; tekrar özel seçilince son değerler alanlarda
      await tapFinder(t, _key('site_audit_period_all'));
      await settleFor(t);
      expect(server.requests.last.queryParameters.containsKey('to'), isFalse);
      await tapText(t, 'Özel aralık');
      expect(t.widget<TextFormField>(_key('site_audit_to')).controller!.text, '15.10.2026');
    });

    testWidgets('Daha fazla yükle: before_id ile sonraki sayfa İLK sayfanın süzgeciyle istenir, yinelenen atlanır, son sayfada düğme kalkar', (t) async {
      final server = _Server(all: _Server.many(120));
      await _pump(t, server);
      expect(find.byType(SiteAuditLogCard), findsNWidgets(50));

      await tapText(t, 'Daha fazla yükle');
      await settleFor(t);
      expect(server.requests.last.queryParameters['before_id'], '71');
      expect(find.byType(SiteAuditLogCard), findsNWidgets(100));

      await tapText(t, 'Daha fazla yükle');
      await settleFor(t);
      expect(server.requests.last.queryParameters['before_id'], '21');
      expect(find.byType(SiteAuditLogCard), findsNWidgets(120));
      expect(find.text('Daha fazla yükle'), findsNothing);
    });

    testWidgets('süzgeç + Daha fazla yükle: devam sayfası aynı işlem türü ve dönemle istenir', (t) async {
      final server = _Server(all: _Server.many(120));
      await _pump(t, server);
      await tapFinder(t, find.byType(DropdownButtonFormField<String>));
      await tapFinder(t, find.text('Aidat ve finans').last);
      await settleFor(t);
      await tapFinder(t, _key('site_audit_period_last_7'));
      await settleFor(t);
      await tapText(t, 'Daha fazla yükle');
      await settleFor(t);
      final q = server.requests.last.queryParameters;
      expect(q['category'], 'finance');
      expect(q['from'], '2026-10-22');
      expect(q['to'], '2026-10-28');
      expect(q['before_id'], '71');
    });

    testWidgets('yinelenen kayıt (ardışık sayfalarda aynı id) iki kez gösterilmez', (t) async {
      final server = _Server(all: _Server.many(60));
      await _pump(t, server);
      // İkinci sayfa yanıtı ilk sayfanın son kaydını (11) yeniden içerir.
      server.override = (uri) => _json(200, <String, dynamic>{
        'items': <Map<String, dynamic>>[for (var id = 11; id >= 1; id--) _entry(id)],
        'next_before_id': null,
      });
      await tapText(t, 'Daha fazla yükle');
      await settleFor(t);
      expect(find.byType(SiteAuditLogCard), findsNWidgets(60), reason: '50 + (11 - 1 yinelenen)');
    });

    testWidgets('Daha fazla yükle hatası: mesaj + Tekrar Dene, mevcut liste kalır, tekrar denenince devam eder', (t) async {
      final server = _Server(all: _Server.many(80));
      await _pump(t, server);
      server.override = (_) => _json(500, <String, dynamic>{'error': 'İşlem kayıtları yüklenemedi.', 'errorId': 'x'});
      await tapText(t, 'Daha fazla yükle');
      await settleFor(t);
      expect(_key('site_audit_more_error'), findsOneWidget);
      expect(find.text('İşlem kayıtları yüklenemedi.'), findsOneWidget);
      expect(find.byType(SiteAuditLogCard), findsNWidgets(50));
      expect(find.text('Daha fazla yükle'), findsOneWidget);

      server.override = null;
      await tapText(t, 'Tekrar Dene');
      await settleFor(t);
      expect(find.byType(SiteAuditLogCard), findsNWidgets(80));
      expect(_key('site_audit_more_error'), findsNothing);
    });

    testWidgets('iki sitede site seçici: seçilen sitenin yolu istenir, liste sıfırlanır', (t) async {
      final server = _Server(all: _Server.many(3));
      await _pump(t, server, sites: _twoSites);
      expect(server.requests.single.path, '/manager/sites/11/audit-log');

      await tapFinder(t, find.byType(DropdownButtonFormField<int>));
      await tapFinder(t, find.text('Mavi Park').last);
      await settleFor(t);
      expect(server.requests.last.path, '/manager/sites/12/audit-log');
      expect(server.requests.last.queryParameters.containsKey('before_id'), isFalse);
      expect(find.byType(SiteAuditLogCard), findsNWidgets(3));
    });

    testWidgets('site listesi değişince (seçili site artık yok) ilk siteye geçer ve yeniden yükler', (t) async {
      final server = _Server(all: _Server.many(2));
      final auth = _Auth();
      final service = SiteAuditLogService(
        authService: auth,
        api: SiteAuditLogApi(baseUrl: 'http://localhost', client: MockClient(server.handle)),
      );
      final notifier = ValueNotifier<List<PeopleSite>>(_twoSites);
      addTearDown(notifier.dispose);
      t.view.physicalSize = const Size(400, 1600);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ValueListenableBuilder<List<PeopleSite>>(
                valueListenable: notifier,
                builder: (_, sites, _) => SiteAuditLogView(authService: auth, sites: sites, service: service, now: () => _now),
              ),
            ),
          ),
        ),
      );
      await settleFor(t);
      expect(server.requests.last.path, '/manager/sites/11/audit-log');
      notifier.value = const <PeopleSite>[PeopleSite(code: 12, name: 'Mavi Park', canWrite: true)];
      await settleFor(t);
      expect(server.requests.last.path, '/manager/sites/12/audit-log');
      notifier.value = const <PeopleSite>[];
      await settleFor(t);
      expect(find.text('Yönettiğiniz bir site yok.'), findsOneWidget);
    });

    testWidgets('yenile düğmesi ve reload() ilk sayfayı yeniden çeker; liste ekranda kalır; ön ayarlı dönem bugüne göre yeniden hesaplanır', (t) async {
      final server = _Server(all: _Server.many(3));
      var now = _now;
      final key = await _pump(t, server, now: () => now);
      await tapFinder(t, _key('site_audit_period_today'));
      await settleFor(t);
      expect(server.requests.last.queryParameters['from'], '2026-10-28');

      final refreshGate = Completer<void>();
      server.gates.add(refreshGate);
      await tapFinder(t, find.byTooltip('Yenile'));
      expect(find.byType(SiteAuditLogCard), findsNWidgets(3), reason: 'yenilemede mevcut liste kalır');
      expect(find.byType(ListSkeleton), findsNothing);
      refreshGate.complete();
      await settleFor(t);

      now = DateTime.utc(2026, 10, 29, 12, 0); // ertesi gün
      await key.currentState!.reload();
      await settleFor(t);
      expect(server.requests.last.queryParameters['from'], '2026-10-29', reason: 'gün dönümünde "Bugün" yeni günü gösterir');
      expect(server.requests.last.queryParameters.containsKey('before_id'), isFalse);
    });

    testWidgets('Daha fazla yükle sürerken YENİLE: eski yanıt eklenmez, düğme sıfırlanır ve tıklanabilir', (t) async {
      final server = _Server(all: _Server.many(120));
      await _pump(t, server);
      final moreGate = Completer<void>();
      final reloadGate = Completer<void>();
      server.gates
        ..add(moreGate)
        ..add(reloadGate);

      await tapText(t, 'Daha fazla yükle');
      expect(t.widget<PrimaryActionButton>(find.byType(PrimaryActionButton)).loading, isTrue);

      await tapFinder(t, find.byTooltip('Yenile'));
      var button = t.widget<PrimaryActionButton>(find.byType(PrimaryActionButton));
      expect(button.loading, isFalse);
      expect(button.onPressed, isNull, reason: 'yenileme sürerken eski imleçle yeni sayfa istenmez');

      moreGate.complete(); // ESKİ imleçli yanıt şimdi geliyor
      await settleFor(t);
      expect(find.byType(SiteAuditLogCard), findsNWidgets(50), reason: 'eski sayfa listeye eklenmez');

      reloadGate.complete();
      await settleFor(t);
      button = t.widget<PrimaryActionButton>(find.byType(PrimaryActionButton));
      expect(button.loading, isFalse, reason: 'düğme sonsuza dek dönmez');
      expect(button.onPressed, isNotNull);

      await tapText(t, 'Daha fazla yükle');
      await settleFor(t);
      expect(server.requests.last.queryParameters['before_id'], '71');
      expect(find.byType(SiteAuditLogCard), findsNWidgets(100));
    });

    testWidgets('Daha fazla yükle sürerken SÜZGEÇ değişimi: eski yanıt yok sayılır, düğme sıfırlanır', (t) async {
      final server = _Server(all: _Server.many(120));
      await _pump(t, server);
      final moreGate = Completer<void>();
      server.gates.add(moreGate);
      await tapText(t, 'Daha fazla yükle');

      await tapFinder(t, find.byType(DropdownButtonFormField<String>));
      await tapFinder(t, find.text('Aidat ve finans').last);
      await settleFor(t);
      expect(server.requests.last.queryParameters['category'], 'finance');

      moreGate.complete();
      await settleFor(t);
      expect(find.byType(SiteAuditLogCard), findsNWidgets(50));
      final button = t.widget<PrimaryActionButton>(find.byType(PrimaryActionButton));
      expect(button.loading, isFalse);
      expect(button.onPressed, isNotNull);
    });

    testWidgets('hata sonrası Tekrar Dene sürerken iskelet gösterilir; yanıltıcı boş durum yanıp sönmez', (t) async {
      final server = _Server(all: _Server.many(3))
        ..override = (_) => _json(500, <String, dynamic>{'error': 'İşlem kayıtları yüklenemedi.', 'errorId': 'x'});
      await _pump(t, server);
      expect(find.text('Tekrar Dene'), findsOneWidget);

      server.override = null;
      final retryGate = Completer<void>();
      server.gates.add(retryGate);
      await tapText(t, 'Tekrar Dene');
      expect(find.byType(ListSkeleton), findsOneWidget);
      expect(find.text('Henüz işlem kaydı yok.'), findsNothing);
      expect(find.byType(EmptyCard), findsNothing);

      retryGate.complete();
      await settleFor(t);
      expect(find.byType(SiteAuditLogCard), findsNWidgets(3));
    });

    testWidgets('ağ hatası: anlaşılır Türkçe mesaj; kayıt yok denmez', (t) async {
      final server = _Server()..override = (_) => throw http.ClientException('yok');
      await _pump(t, server);
      expect(find.textContaining('Sunucuya bağlanılamadı'), findsOneWidget);
      expect(find.text('Henüz işlem kaydı yok.'), findsNothing);
    });

    testWidgets('kişisel veri: kartta e-posta, telefon, parola, kullanıcı kodu alanı çizilmez (yalnız gelen güvenli alanlar)', (t) async {
      final server = _Server(
        all: <Map<String, dynamic>>[
          _entry(
            1,
            action: 'work_item.created',
            label: 'Talep açıldı',
            category: 'services',
            categoryLabel: 'Site hizmetleri',
            actor: 'Deniz Sakin',
            roleLabel: 'Daire sakini',
            role: 'apartment_owner',
            targetType: 'work_item',
            targetId: '9',
            details: <String, dynamic>{'status': 'yeni'},
          ),
        ],
      );
      await _pump(t, server);
      // Yalnız KART metinleri (ekranın açıklama metni "Parola ve iletişim bilgileri kayıtta yer almaz" der).
      final shown = <String>[
        for (final text in t.widgetList<Text>(find.descendant(of: find.byType(SiteAuditLogCard), matching: find.byType(Text))))
          if (text.data != null) text.data!,
      ].join(' | ');
      expect(shown, contains('Talep açıldı'));
      expect(shown, isNot(matches(RegExp(r'@|parola|password|token|telefon|\+90|actor_user_code', caseSensitive: false))));
      expect(find.text('Deniz Sakin • Daire sakini'), findsOneWidget);
    });
  });
}
