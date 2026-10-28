// "Gelen Geri Bildirimler" (docs/PLATFORM_GERI_BILDIRIM.md): yönetici KENDİ sitesinin, platform sahibi tüm kayıtları okur. Her kayıt gönderen adı + rolü,
// zaman, gönderildiği EKRAN (ad + rota), metin ve ek dosyaları gösterir; imleçli sayfalama; hata durumunda "kayıt yok" yerine hata + "Tekrar Dene";
// yetkisiz çağrı (403) sunucu iletisiyle görünür; ek dosyası dokununca açılır; taşma yok.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/feedback_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/feedback_api.dart';
import 'package:site_kapi_kontrol/styles/app_theme.dart';
import 'package:site_kapi_kontrol/ui/views/feedback_inbox_view.dart';

import 'dialog_layout_harness.dart' show settleFor;
import 'work_fixtures.dart';

FeedbackRecord _record(
  int id, {
  String user = 'Ayşe Yılmaz',
  String role = 'resident',
  String screen = 'Talepler',
  String route = 'menu/talepler',
  String message = 'Menü karışık görünüyor.',
  int? site = 11,
  String? siteName = 'Gül Sitesi',
  List<FeedbackAttachment> attachments = const <FeedbackAttachment>[],
}) => FeedbackRecord(
  id: id,
  siteCode: site,
  siteName: siteName,
  userName: user,
  role: role,
  screenName: screen,
  screenRoute: route,
  message: message,
  appVersion: '1.0.0+1',
  platform: 'android',
  createdAt: DateTime(2026, 10, 28, 12, 30),
  attachments: attachments,
);

class _FakeApi extends FeedbackApi {
  _FakeApi() : super(baseUrl: 'http://localhost');

  final List<String> calls = <String>[];
  List<FeedbackPage> pages = <FeedbackPage>[];
  Object? error;
  int downloads = 0;

  FeedbackPage _next(String label, int? cursor) {
    calls.add('$label cursor=${cursor ?? '-'}');
    final failure = error;
    if (failure != null) throw failure;
    return pages.isEmpty ? const FeedbackPage(items: <FeedbackRecord>[], nextCursor: null) : pages.removeAt(0);
  }

  @override
  Future<FeedbackPage> listForSite({required String token, required int siteCode, int? cursor, int limit = 30}) async =>
      _next('site=$siteCode', cursor);

  @override
  Future<FeedbackPage> listAll({required String token, int? siteCode, int? cursor, int limit = 30}) async => _next('all', cursor);

  @override
  Future<Uint8List> downloadAttachment({required String token, int? siteCode, required int feedbackId, required int attachmentId}) async {
    downloads++;
    return kWkPng;
  }
}

FeedbackService _service(_FakeApi api) => FeedbackService(authService: WorkFakeAuth(), api: api);

Finder _k(String key) => find.byKey(ValueKey<String>(key));

Future<void> _pump(
  WidgetTester t,
  FeedbackService service, {
  int? siteCode,
  double width = 400,
  double height = 1200,
  double scale = 1.0,
  bool dark = false,
}) async {
  // Sayfa kendi Scaffold'unu taşır: `pumpAt`in kaydırma sarmalı yerine doğrudan MaterialApp.home.
  t.view.physicalSize = Size(width, height);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(const SizedBox.shrink());
  await t.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      builder: (c, child) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: FeedbackInboxPage(service: service, siteCode: siteCode),
    ),
  );
  await settleFor(t, 100);
  await settleFor(t, 100);
}

void main() {
  testWidgets('yönetici ucu: kendi sitesi istenir; kayıt gönderen, rol, EKRAN (ad + rota), metin ve sürümü gösterir', (t) async {
    final api = _FakeApi()
      ..pages = <FeedbackPage>[
        FeedbackPage(items: <FeedbackRecord>[_record(2, user: 'Mehmet Demir', role: 'board_member', screen: 'Finans', route: 'menu/finans', message: 'Rapor güzel.'), _record(1)], nextCursor: null),
      ];
    await _pump(t, _service(api), siteCode: 11);
    expect(api.calls, <String>['site=11 cursor=-']);
    expect(find.text('Mehmet Demir'), findsOneWidget);
    expect(find.text('Kurul üyesi'), findsOneWidget);
    expect(find.text('Sakin'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('feedback_item_screen_2')), findsOneWidget);
    expect(t.widget<Text>(_k('feedback_item_screen_2')).textSpan!.toPlainText(), 'Ekran: Finans  (menu/finans)');
    expect(t.widget<Text>(_k('feedback_item_screen_1')).textSpan!.toPlainText(), 'Ekran: Talepler  (menu/talepler)');
    expect(find.text('Rapor güzel.'), findsOneWidget);
    expect(find.text('Sürüm 1.0.0+1 · android'), findsNWidgets(2));
    expect(find.textContaining('Site:'), findsNothing, reason: 'yönetici zaten tek siteyi görür');
    expect(find.byKey(const ValueKey<String>('feedback_inbox_more')), findsNothing);
  });

  testWidgets('sahip ucu: tüm kayıtlar; site adı satırı (siteye bağlı olmayan "Siteye bağlı değil")', (t) async {
    final api = _FakeApi()
      ..pages = <FeedbackPage>[
        FeedbackPage(items: <FeedbackRecord>[_record(3, site: null, siteName: null, role: 'super_user', user: 'Süper'), _record(2)], nextCursor: null),
      ];
    await _pump(t, _service(api));
    expect(api.calls, <String>['all cursor=-']);
    expect(find.text('Site: Gül Sitesi'), findsOneWidget);
    expect(find.text('Site: Siteye bağlı değil'), findsOneWidget);
    expect(find.text('Süper kullanıcı'), findsOneWidget);
  });

  testWidgets('boş liste: "Henüz geri bildirim yok."; hata: "kayıt yok" DEĞİL hata + Tekrar Dene, yeniden deneme listeyi getirir', (t) async {
    final api = _FakeApi()..error = ApiException('Bu site üzerinde yönetim yetkiniz bulunmuyor.', statusCode: 403, code: 'FORBIDDEN_SITE');
    await _pump(t, _service(api), siteCode: 11);
    expect(find.text('Bu site üzerinde yönetim yetkiniz bulunmuyor.'), findsOneWidget);
    expect(find.text('Henüz geri bildirim yok.'), findsNothing);
    api
      ..error = null
      ..pages = <FeedbackPage>[FeedbackPage(items: <FeedbackRecord>[_record(1)], nextCursor: null)];
    await t.tap(find.text('Tekrar Dene'));
    await settleFor(t, 100);
    await settleFor(t, 100);
    expect(find.text('Ayşe Yılmaz'), findsOneWidget);

    final empty = _FakeApi();
    await _pump(t, _service(empty), siteCode: 11);
    expect(find.text('Henüz geri bildirim yok.'), findsOneWidget);
  });

  testWidgets('sayfalama: "Daha fazla yükle" sonraki sayfayı imleçle ister ve listenin SONUNA ekler; yinelenen kayıt eklenmez', (t) async {
    final api = _FakeApi()
      ..pages = <FeedbackPage>[
        FeedbackPage(items: <FeedbackRecord>[_record(3, message: 'üçüncü'), _record(2, message: 'ikinci')], nextCursor: 2),
        FeedbackPage(items: <FeedbackRecord>[_record(2, message: 'ikinci'), _record(1, message: 'birinci')], nextCursor: null),
      ];
    await _pump(t, _service(api), siteCode: 11);
    expect(find.byKey(const ValueKey<String>('feedback_inbox_more')), findsOneWidget);
    await t.ensureVisible(_k('feedback_inbox_more'));
    await t.pump();
    await t.tap(_k('feedback_inbox_more'));
    await settleFor(t, 100);
    await settleFor(t, 100);
    expect(api.calls, <String>['site=11 cursor=-', 'site=11 cursor=2']);
    expect(find.text('ikinci'), findsOneWidget, reason: 'yinelenen kayıt bir kez');
    expect(find.text('birinci'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('feedback_inbox_more')), findsNothing);
  });

  testWidgets('ek dosya: düğme boyutla yazılır, dokununca indirilir ve görüntülenir', (t) async {
    final api = _FakeApi()
      ..pages = <FeedbackPage>[
        FeedbackPage(
          items: <FeedbackRecord>[
            _record(
              5,
              attachments: const <FeedbackAttachment>[
                FeedbackAttachment(id: 9, feedbackId: 5, fileName: 'a.jpg', mimeType: 'image/png', sizeBytes: 2048, ready: true),
              ],
            ),
          ],
          nextCursor: null,
        ),
      ];
    await _pump(t, _service(api), siteCode: 11);
    expect(find.text('Dosya 1 (2,0 KB)'), findsOneWidget);
    await t.ensureVisible(_k('feedback_item_5_file_0'));
    await t.pump();
    await t.tap(_k('feedback_item_5_file_0'));
    await settleFor(t, 100);
    await settleFor(t, 300);
    expect(api.downloads, 1);
    expect(find.text('Ek Dosya'), findsOneWidget);
    expect(_k('feedback_image'), findsOneWidget);
    await t.tap(_k('feedback_image_close'));
    await settleFor(t, 100);
    await settleFor(t, 400);
    expect(find.text('Ek Dosya'), findsNothing);
  });

  for (final dark in <bool>[false, true]) {
    testWidgets('taşma yok: 320x640 x2,0 uzun ad / rota / metin / site, iki ek ${dark ? 'koyu' : 'açık'} tema', (t) async {
      final api = _FakeApi()
        ..pages = <FeedbackPage>[
          FeedbackPage(
            items: <FeedbackRecord>[
              _record(
                1,
                user: 'Çok Uzun Adlı Bir Kullanıcı Soyadı Daha Uzun',
                screen: 'Sözleşmeler ve firma takibi (yönetim görünümü)',
                route: 'menu/sozlesmeler:sakin',
                message: 'Uzun bir metin ' * 40,
                siteName: 'Çok Uzun Adlı Bir Sitenin Yönetim Kurulu Sitesi',
                attachments: const <FeedbackAttachment>[
                  FeedbackAttachment(id: 1, feedbackId: 1, fileName: 'a.jpg', mimeType: 'image/jpeg', sizeBytes: 5 * 1024 * 1024, ready: true),
                  FeedbackAttachment(id: 2, feedbackId: 1, fileName: 'b.jpg', mimeType: 'image/jpeg', sizeBytes: 123456, ready: true),
                ],
              ),
            ],
            nextCursor: null,
          ),
        ];
      await _pump(t, _service(api), width: 320, height: 640, scale: 2.0, dark: dark);
      expect(find.byType(FeedbackInboxPage), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }
}
