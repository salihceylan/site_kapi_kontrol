// "İstemci Hataları" ekranı (ClientErrorsView, yalnız süper kullanıcı): GET /admin/client-errors, imleçli sayfalama.
//
// Taşma matrisi (320x640 x2,0, 360x640 x1,5, yatay, tablet; açık + koyu), yükleniyor / boş / hata / dolu durumlar,
// hata durumunda yanlış "kayıt yok" iletisi yok, sayfalama (imleç, yinelenen kayıt, çift dokunuş, eski yanıt
// yarışı), örnek yığın aç/kapa ve panoya kopyalama, İstanbul saati.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/account_client_error.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/views/client_errors_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

import 'account_fixtures.dart';
import 'dialog_layout_harness.dart';
import 'list_fixtures.dart';

List<ClientErrorPage> _twoPages() => <ClientErrorPage>[
  ClientErrorPage(
    items: <ClientErrorItem>[
      acError(3, fatal: true),
      acError(
        2,
        platform: 'ios',
        type: 'PlatformException',
        message:
            'PlatformException(channel-error, Unable to establish connection on channel: '
            '"dev.flutter.pigeon.shared_preferences_foundation.LegacyUserDefaultsApi.getAll", null, null)',
        stack: '#0 ${'VeryLongPackageName.' * 12}method (package:site/very/long/path/file.dart:12:3)\n#1 main',
      ),
    ],
    nextCursor: '1',
  ),
  ClientErrorPage(items: <ClientErrorItem>[acError(2), acError(1, platform: 'web', stack: '')]),
];

class _Ctx {
  _Ctx(this.h, this.key);

  final AccountHarness h;
  final GlobalKey<ClientErrorsViewState> key;

  ClientErrorsViewState get state => key.currentState!;
}

Future<_Ctx> _pump(
  WidgetTester t, {
  AccountHarness? harness,
  List<ClientErrorPage>? pages,
  double width = 400,
  double height = 900,
  double scale = 1.0,
  bool dark = false,
}) async {
  final h = harness ?? AccountHarness(role: UserRole.superUser);
  h.api.pages = pages ?? _twoPages();
  final key = GlobalKey<ClientErrorsViewState>();
  await pumpList(
    t,
    ClientErrorsView(key: key, authService: h.auth, service: h.service),
    width: width,
    height: height,
    scale: scale,
    dark: dark,
  );
  await settleFor(t, 100);
  return _Ctx(h, key);
}

Finder _more() => find.text('Daha fazla yükle');

Future<void> _tapMore(WidgetTester t) async {
  await t.ensureVisible(_more());
  await t.pump();
  await t.tap(_more());
  await t.pump();
  await t.pump(const Duration(milliseconds: 100));
}

Finder _card(String fp) => find.byKey(ValueKey<String>('client_error_$fp'));

void main() {
  group('taşma matrisi', () {
    accountLayoutMatrix('dolu liste: çökme + hata, uzun ileti, uzun yığın açık', (t, w, h, s, dark) async {
      await _pump(t, width: w, height: h, scale: s, dark: dark);
      expect(find.text('İstemci Hataları'), findsOneWidget);
      expect(find.byType(ClientErrorCard), findsNWidgets(2));
      expect(find.text('Çökme'), findsOneWidget);
      expect(find.text('Hata'), findsOneWidget);
      expect(find.text('Daha fazla yükle'), findsOneWidget);

      final toggle = find.byKey(const ValueKey<String>('client_error_stack_toggle_fp2'));
      await t.ensureVisible(toggle);
      await t.pump();
      await t.tap(toggle);
      await settleFor(t);
      expect(find.byKey(const ValueKey<String>('client_error_stack_fp2')), findsOneWidget);
      expect(find.text('Örnek yığını gizle'), findsOneWidget);
    });

    accountLayoutMatrix('boş durum (başarıyla yüklendi, hiç kayıt yok)', (t, w, h, s, dark) async {
      await _pump(t, pages: const <ClientErrorPage>[ClientErrorPage()], width: w, height: h, scale: s, dark: dark);
      expect(find.byType(EmptyCard), findsOneWidget);
      expect(find.text('Kayıtlı istemci hatası yok.'), findsOneWidget);
      expect(find.byType(ClientErrorCard), findsNothing);
    });

    accountLayoutMatrix('yükleniyor: iskelet; boş durum / kart yok', (t, w, h, s, dark) async {
      final harness = AccountHarness(role: UserRole.superUser)..api.errorsGate = Completer<void>();
      await _pump(t, harness: harness, width: w, height: h, scale: s, dark: dark);
      expect(find.byType(ListSkeleton), findsOneWidget);
      expect(find.byType(EmptyCard), findsNothing);
      expect(find.text('Kayıtlı istemci hatası yok.'), findsNothing);
    });

    accountLayoutMatrix('hata: hata + Tekrar Dene; "kayıt yok" YANLIŞ iletisi çıkmaz', (t, w, h, s, dark) async {
      final harness = AccountHarness(role: UserRole.superUser)
        ..api.errorsError = ApiException('Bu işlem için yetkiniz yok.', statusCode: 403);
      await _pump(t, harness: harness, width: w, height: h, scale: s, dark: dark);
      expect(find.text('Bu işlem için yetkiniz yok.'), findsOneWidget);
      expect(find.text('Tekrar Dene'), findsOneWidget);
      expect(find.byType(EmptyCard), findsNothing);
      expect(find.text('Kayıtlı istemci hatası yok.'), findsNothing);
    });
  });

  group('kart içeriği', () {
    testWidgets('tür, ileti, sayı / platform / sürüm çipleri ve İstanbul saatiyle ilk-son görülme', (t) async {
      await _pump(t);
      expect(find.text('FlutterError'), findsOneWidget);
      expect(find.textContaining('A RenderFlex overflowed by 21 pixels'), findsOneWidget);
      expect(find.text('9 kez'), findsOneWidget);
      expect(find.text('Android'), findsOneWidget);
      expect(find.text('iOS'), findsOneWidget);
      expect(find.text('v1.0.3'), findsOneWidget);
      // 09:05Z ve 07:30Z -> İstanbul (UTC+3).
      expect(find.text('İlk görülme: 01.10.2026 12:05'), findsNWidgets(2));
      expect(find.text('Son görülme: 16.10.2026 10:30'), findsNWidgets(2));
    });

    testWidgets('yığın varsayılan kapalı; aç / kapa; yığını olmayan kayıtta düğme yok', (t) async {
      await _pump(t, pages: <ClientErrorPage>[
        ClientErrorPage(items: <ClientErrorItem>[acError(1, stack: ''), acError(2)]),
      ]);
      expect(find.byKey(const ValueKey<String>('client_error_stack_fp2')), findsNothing, reason: 'kapalıyken ağaçta yok');
      expect(find.byKey(const ValueKey<String>('client_error_stack_toggle_fp1')), findsNothing);

      final toggle = find.byKey(const ValueKey<String>('client_error_stack_toggle_fp2'));
      await t.tap(toggle);
      await settleFor(t);
      expect(find.byKey(const ValueKey<String>('client_error_stack_fp2')), findsOneWidget);
      expect(find.textContaining('RenderFlex.performLayout'), findsOneWidget);
      await t.tap(toggle);
      await settleFor(t);
      expect(find.byKey(const ValueKey<String>('client_error_stack_fp2')), findsNothing);
    });

    testWidgets('"Ayrıntıyı kopyala": pano metni tür, ileti, platform / sürüm / sayı ve yığını içerir', (t) async {
      String? copied;
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map<Object?, Object?>)['text'] as String?;
        }
        return null;
      });
      addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

      await _pump(t, pages: <ClientErrorPage>[
        ClientErrorPage(items: <ClientErrorItem>[acError(3, fatal: true)]),
      ]);
      await t.tap(find.byKey(const ValueKey<String>('client_error_stack_toggle_fp3')));
      await settleFor(t);
      await t.ensureVisible(find.text('Ayrıntıyı kopyala'));
      await t.tap(find.text('Ayrıntıyı kopyala'));
      await settleFor(t);

      expect(copied, contains('FlutterError: A RenderFlex overflowed'));
      expect(copied, contains('Android • v1.0.3 • 9 kez • çökme'));
      expect(copied, contains('#0 RenderFlex.performLayout'));
      expect(find.text('Hata ayrıntısı panoya kopyalandı.'), findsOneWidget);
    });
  });

  group('sayfalama', () {
    testWidgets('ilk istek: limit 50, imleç yok; Daha fazla yükle imleçle sonraki sayfayı ekler, yinelenen atlanır', (t) async {
      final c = await _pump(t);
      expect(c.h.api.errorCalls, <({int limit, String? cursor})>[(limit: 50, cursor: null)]);
      expect(find.byType(ClientErrorCard), findsNWidgets(2));

      await _tapMore(t);
      await settleFor(t);

      expect(c.h.api.errorCalls.last, (limit: 50, cursor: '1'));
      expect(find.byType(ClientErrorCard), findsNWidgets(3), reason: '2 + (2 - 1 yinelenen)');
      expect(_card('fp1'), findsOneWidget);
      expect(find.text('Daha fazla yükle'), findsNothing, reason: 'son sayfa');
    });

    testWidgets('çift dokunuş: tek istek', (t) async {
      final c = await _pump(t);
      c.h.api.errorsGate = Completer<void>();
      await _tapMore(t);
      // Yüklenirken etiket ağaçtan kalkar; ikinci dokunuş düğmenin kendisine yapılır.
      await t.tap(find.byType(PrimaryActionButton), warnIfMissed: false);
      await t.pump();
      expect(c.h.api.errorCalls.where((e) => e.cursor == '1'), hasLength(1));
      expect(t.widget<PrimaryActionButton>(find.byType(PrimaryActionButton)).loading, isTrue);
      c.h.api.errorsGate!.complete();
      await settleFor(t);
    });

    testWidgets('sonraki sayfa hatası: mevcut liste kalır, hata + Tekrar Dene, yeniden deneyince devam eder', (t) async {
      final c = await _pump(t);
      c.h.api.errorsError = ApiException('Sunucu yanıt vermedi, tekrar deneyin.');
      await _tapMore(t);
      await settleFor(t);
      expect(find.text('Sunucu yanıt vermedi, tekrar deneyin.'), findsOneWidget);
      expect(find.byType(ClientErrorCard), findsNWidgets(2));
      expect(_more(), findsOneWidget);

      c.h.api.errorsError = null;
      await t.ensureVisible(find.text('Tekrar Dene'));
      await t.pump();
      await t.tap(find.text('Tekrar Dene'));
      await settleFor(t);
      expect(find.byType(ClientErrorCard), findsNWidgets(3));
      expect(find.text('Sunucu yanıt vermedi, tekrar deneyin.'), findsNothing);
    });

    testWidgets('sunucu aynı imleci tekrarlar / yalnız yinelenen sayfa döner: sonsuz döngü yok', (t) async {
      final c = await _pump(t, pages: <ClientErrorPage>[
        ClientErrorPage(items: <ClientErrorItem>[acError(1)], nextCursor: '1'),
        ClientErrorPage(items: <ClientErrorItem>[acError(1)], nextCursor: '1'),
      ]);
      await _tapMore(t);
      await settleFor(t);
      expect(find.byType(ClientErrorCard), findsOneWidget);
      expect(_more(), findsNothing, reason: 'yeni kayıt gelmedi: sayfalama durur');
      expect(c.h.api.errorCalls, hasLength(2));
    });

    testWidgets('sayfa tamamen YİNELENEN kayıtlardan oluşsa da sunucuda devam varsa sonraki sayfaya geçilir (düğme kaybolmaz)', (t) async {
      final messages = captureAnnouncements(t);
      final c = await _pump(t, pages: <ClientErrorPage>[
        ClientErrorPage(items: <ClientErrorItem>[acError(1), acError(2)], nextCursor: '1'),
        ClientErrorPage(items: <ClientErrorItem>[acError(1), acError(2)], nextCursor: '2'),
        ClientErrorPage(items: <ClientErrorItem>[acError(3)], nextCursor: '3'),
        ClientErrorPage(items: <ClientErrorItem>[acError(4)]),
      ]);
      await _tapMore(t);
      await settleFor(t);

      // Tek dokunuşla: yinelenen sayfa atlandı, 3. sayfadaki yeni kayıt eklendi; sunucuda hâlâ devam var.
      expect(c.h.api.errorCalls.map((e) => e.cursor), <String?>[null, '1', '2']);
      expect(_card('fp3'), findsOneWidget);
      expect(find.byType(ClientErrorCard), findsNWidgets(3));
      expect(_more(), findsOneWidget, reason: 'sonraki sayfa (imleç 3) var: düğme kalır');
      expect(messages, contains('1 yeni hata kaydı yüklendi.'));

      await _tapMore(t);
      await settleFor(t);
      expect(_card('fp4'), findsOneWidget);
      expect(_more(), findsNothing);
    });

    testWidgets('art arda çok sayıda yinelenen sayfa: 5 sayfa sonra durur, imleç ilerlemiş halde düğme KALIR (sonsuz döngü yok)', (t) async {
      final dup = <ClientErrorItem>[acError(1)];
      final c = await _pump(t, pages: <ClientErrorPage>[
        ClientErrorPage(items: dup, nextCursor: '1'),
        for (var i = 1; i <= 8; i++) ClientErrorPage(items: dup, nextCursor: '${i + 1}'),
        ClientErrorPage(items: <ClientErrorItem>[acError(9)]),
      ]);
      await _tapMore(t);
      await settleFor(t);
      expect(c.h.api.errorCalls.length, 1 + 5, reason: 'ilk sayfa + en çok 5 atlama');
      expect(find.byType(ClientErrorCard), findsOneWidget);
      expect(_more(), findsOneWidget, reason: 'kullanıcı devam edebilir');

      await _tapMore(t);
      await settleFor(t);
      expect(c.h.api.errorCalls[6].cursor, '6', reason: 'kaldığı imleçten sürer (ilk 6 çağrı: ilk sayfa + 5 atlama)');
      expect(_card('fp9'), findsOneWidget, reason: 'yinelenenleri atlayıp yeni kayda ulaşır');
    });

    testWidgets('yinelenen sayfa varken hata: ileti + Tekrar Dene, sonra atlayarak yeni kayda ulaşır', (t) async {
      final c = await _pump(t, pages: <ClientErrorPage>[
        ClientErrorPage(items: <ClientErrorItem>[acError(1)], nextCursor: '1'),
        ClientErrorPage(items: <ClientErrorItem>[acError(1)], nextCursor: '2'),
        ClientErrorPage(items: <ClientErrorItem>[acError(5)]),
      ]);
      c.h.api.errorsError = ApiException('Sunucu yanıt vermedi, tekrar deneyin.');
      await _tapMore(t);
      await settleFor(t);
      expect(find.text('Sunucu yanıt vermedi, tekrar deneyin.'), findsOneWidget);

      c.h.api.errorsError = null;
      await t.ensureVisible(find.text('Tekrar Dene'));
      await t.pump();
      await t.tap(find.text('Tekrar Dene'));
      await settleFor(t);
      expect(_card('fp5'), findsOneWidget);
    });

    testWidgets('sonraki sayfa yüklenirken düğme "Yükleniyor" anlamı taşır; yükleme bitince duyuru yapılır', (t) async {
      final handle = t.ensureSemantics();
      final messages = captureAnnouncements(t);
      final c = await _pump(t);
      c.h.api.errorsGate = Completer<void>();
      await _tapMore(t);
      expect(find.bySemanticsLabel(RegExp('Daha fazla yükle.*Yükleniyor')), findsOneWidget);
      c.h.api.errorsGate!.complete();
      await settleFor(t);
      expect(messages, contains('1 yeni hata kaydı yüklendi.'));
      handle.dispose();
    });

    testWidgets('son sayfada yeni kayıt yoksa "Başka hata kaydı yok." duyurulur', (t) async {
      final messages = captureAnnouncements(t);
      await _pump(t, pages: <ClientErrorPage>[
        ClientErrorPage(items: <ClientErrorItem>[acError(1)], nextCursor: '1'),
        ClientErrorPage(items: <ClientErrorItem>[acError(1)]),
      ]);
      await _tapMore(t);
      await settleFor(t);
      expect(messages, contains('Başka hata kaydı yok.'));
      expect(_more(), findsNothing);
    });

    testWidgets('kartlar ve başlık anlamlı: bölüm başlığı "başlık", yenile düğmesi ipuçlu, çipler okunur', (t) async {
      final handle = t.ensureSemantics();
      await _pump(t);
      expect(t.getSemantics(find.text('Hatalar')).flagsCollection.isHeader, isTrue);
      expect(find.byTooltip('Yenile'), findsOneWidget);
      expect(t.getSemantics(find.text('Çökme')).label, contains('Çökme'));
      expect(t.getSemantics(find.text('9 kez')).label, contains('9 kez'));
      handle.dispose();
    });

    testWidgets('yenileme sürerken eski imleçle gelen sayfa yeni listeyi ezmez', (t) async {
      final c = await _pump(t);
      final gate = Completer<void>();
      c.h.api.errorsGate = gate;
      await _tapMore(t); // eski imleç (1) bekliyor

      // Yenileme başlar: yeni liste farklı.
      c.h.api.pages = <ClientErrorPage>[ClientErrorPage(items: <ClientErrorItem>[acError(9)])];
      unawaited(c.state.reload());
      await t.pump();
      gate.complete();
      await settleFor(t);

      expect(_card('fp9'), findsOneWidget);
      expect(_card('fp3'), findsNothing);
      expect(_card('fp1'), findsNothing, reason: 'eski sayfa eklenmedi');
      expect(find.byType(ClientErrorCard), findsOneWidget);
    });
  });

  group('yenileme ve hata kurtarma', () {
    testWidgets('yenile düğmesi ilk sayfayı yeniden çeker; liste yenileme sürerken ekranda kalır', (t) async {
      final c = await _pump(t);
      final gate = Completer<void>();
      c.h.api.errorsGate = gate;
      await t.tap(find.byTooltip('Yenile'));
      await t.pump();
      expect(c.h.api.errorCalls, hasLength(2));
      expect(find.byType(ClientErrorCard), findsNWidgets(2), reason: 'iskelete dönmez');
      expect(find.byType(ListSkeleton), findsNothing);
      gate.complete();
      await settleFor(t);
      expect(find.byType(ClientErrorCard), findsNWidgets(2));
    });

    testWidgets('ilk yükleme hatası -> Tekrar Dene -> liste gelir', (t) async {
      final h = AccountHarness(role: UserRole.superUser)..api.errorsError = ApiException('Sunucuya bağlanılamadı.');
      final c = await _pump(t, harness: h);
      expect(find.text('Sunucuya bağlanılamadı.'), findsOneWidget);
      h.api.errorsError = null;
      await t.tap(find.text('Tekrar Dene'));
      await settleFor(t);
      expect(find.byType(ClientErrorCard), findsNWidgets(2));
      expect(c.h.api.errorCalls, hasLength(2));
    });

    testWidgets('liste doluyken yenileme hatası: eski kayıtlar + hata bildirimi birlikte', (t) async {
      final c = await _pump(t);
      c.h.api.errorsError = ApiException('Sunucuya bağlanılamadı.');
      await c.state.reload();
      await settleFor(t);
      expect(find.text('Sunucuya bağlanılamadı.'), findsOneWidget);
      expect(find.byType(ClientErrorCard), findsNWidgets(2));
    });

    testWidgets('reload() (aşağı çekip yenileme) çalışır', (t) async {
      final c = await _pump(t);
      await c.state.reload();
      await settleFor(t);
      expect(c.h.api.errorCalls, hasLength(2));
    });
  });
}
