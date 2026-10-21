// Platform Faz 3a: sakin "Duyurular" gelen kutusu (AnnouncementsInboxView) ve okuma penceresi.
//
// AGENTS.md kural 6: 320x640 x2,0 ve 360x640 x1,5, açık + koyu tema; yükleniyor / boş / hata / dolu durumlar
// ve çok uzun Türkçe başlık / metin taşmaz. Davranış: okunmamış nokta + kalın başlık + etiket, acil rozeti,
// duyuruyu açınca tam metin + okundu yazımı (başarısızsa görünür kalır), "Tümünü okundu yap", imleçli
// sayfalama, site süzgeci, yenileme yarışları, İstanbul saati.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsAction;
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/services/announcement_notifier.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart' show InlineNotice;
import 'package:site_kapi_kontrol/ui/dialogs/announcement_read_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/views/announcements_inbox_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/announcement_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

import 'announcement_fixtures.dart';
import 'dialog_layout_harness.dart' show settleFor;
import 'list_fixtures.dart';

AnnouncementFakeAuth _auth({List<Map<String, dynamic>>? rows}) {
  final auth = AnnouncementFakeAuth(role: UserRole.apartmentOwner);
  auth.inboxRows.addAll(
    rows ??
        <Map<String, dynamic>>[
          inboxRow(12, title: 'Su kesintisi', importance: 'urgent'),
          inboxRow(11, title: 'Asansör bakımı', editedAt: DateTime.utc(2026, 10, 16, 9)),
          inboxRow(10, title: 'Aidat hatırlatması', read: true),
        ],
  );
  return auth;
}

AnnouncementNotifier _notifier(AnnouncementFakeAuth auth) => AnnouncementNotifier(
  fetchSummary: auth.getNotificationSummary,
  fetchInbox: () => auth.listMyAnnouncements(limit: 30),
  fetchAnnouncement: auth.getMyAnnouncement,
);

Future<GlobalKey<AnnouncementsInboxViewState>> _pump(
  WidgetTester t,
  AnnouncementFakeAuth auth, {
  AnnouncementNotifier? notifier,
  List<PeopleSite> sites = const <PeopleSite>[],
  double width = 400,
  double height = 1600,
  double scale = 1.0,
  bool dark = false,
}) async {
  final key = GlobalKey<AnnouncementsInboxViewState>();
  await pumpList(
    t,
    AnnouncementsInboxView(
      key: key,
      authService: auth,
      notifier: notifier,
      sites: sites,
    ),
    width: width,
    height: height,
    scale: scale,
    dark: dark,
  );
  await settleFor(t, 100);
  await settleFor(t, 100);
  return key;
}

Finder _card(String title) => find.widgetWithText(AnnouncementInboxCard, title);

Future<void> _open(WidgetTester t, String title) async {
  await tapFinder(t, _card(title));
  await settleFor(t);
}

bool _isRead(WidgetTester t, String title) =>
    t.widget<AnnouncementInboxCard>(_card(title)).announcement.isRead;

Finder _unreadDot() => find.byKey(const ValueKey<String>('announcement_unread_dot'));

void main() {
  group('saklama süresi satırı (sunucu retention_days)', () {
    testWidgets('alan varsa tek satır bilgi; yoksa hiçbir şey', (t) async {
      final auth = _auth()..retentionDays = 90;
      await _pump(t, auth);
      expect(find.text('Duyurular son 90 gün gösterilir.'), findsOneWidget);

      final without = _auth();
      await _pump(t, without);
      expect(find.textContaining('gün gösterilir'), findsNothing);

      final zero = _auth()..retentionDays = 0;
      await _pump(t, zero);
      expect(find.textContaining('gün gösterilir'), findsNothing, reason: 'geçersiz değer gösterilmez');
    });

    testWidgets('320x640 x2,0 koyu temada taşmaz', (t) async {
      final auth = _auth()..retentionDays = 30;
      await _pump(t, auth, width: 320, height: 640, scale: 2.0, dark: true);
      expect(find.text('Duyurular son 30 gün gösterilir.'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });

  group('taşma matrisi', () {
    listMatrix('dolu görünüm (okunmamış nokta, kalın başlık, acil rozeti, İstanbul saati)', (t, w, h, s, dark) async {
      final auth = _auth();
      await _pump(t, auth, width: w, height: h, scale: s, dark: dark);

      expect(find.byType(AnnouncementInboxCard), findsNWidgets(3));
      // Sıra: yayın zamanına göre yeni -> eski.
      final order = [
        for (final card in t.widgetList<AnnouncementInboxCard>(find.byType(AnnouncementInboxCard)))
          card.announcement.id,
      ];
      expect(order, <int>[12, 11, 10]);
      expect(_unreadDot(), findsNWidgets(2), reason: 'okunmamış iki duyuru');
      expect(find.text('Acil'), findsOneWidget);
      expect(find.text('16.10.2026 11:12'), findsOneWidget, reason: '08:12 UTC = 11:12 İstanbul');
      expect(find.text('Düzenlendi'), findsOneWidget);
      expect(find.text('Tümünü okundu yap'), findsOneWidget);
      expect(find.text('Gelen duyurular'), findsOneWidget);
      // Okunmamış başlık kalın, okunmuş daha hafif (renk tek başına anlam taşımaz: nokta + etiket de var).
      final unread = t.widget<Text>(find.text('Su kesintisi'));
      final read = t.widget<Text>(find.text('Aidat hatırlatması'));
      expect(unread.style!.fontWeight, FontWeight.w800);
      expect(read.style!.fontWeight, FontWeight.w600);
    });

    listMatrix('çok uzun Türkçe başlık ve metin taşmaz (acil + düzenlendi + site)', (t, w, h, s, dark) async {
      final long = 'Çok uzun başlıklı önemli ışık güvenliği duyurusu ' * 3;
      final auth = _auth(
        rows: <Map<String, dynamic>>[
          inboxRow(6, title: 'A' * 220, body: 'B' * 400),
          inboxRow(
            5,
            title: long,
            body: 'Şüphelendiğiniz çöp toplama hizmetinde yaşanan gecikme nedeniyle ' * 12,
            importance: 'urgent',
            siteName: 'Çok Uzun İsimli Güzelyalı Yeşilvadi Konutları Sitesi',
            editedAt: DateTime.utc(2026, 10, 16, 9),
          ),
        ],
      );
      await _pump(
        t,
        auth,
        width: w,
        height: h,
        scale: s,
        dark: dark,
        sites: const <PeopleSite>[
          PeopleSite(code: 11, name: 'Gül Sitesi'),
          PeopleSite(code: 12, name: 'Çok Uzun İsimli Güzelyalı Yeşilvadi Konutları Sitesi'),
        ],
      );
      expect(find.byType(AnnouncementInboxCard), findsNWidgets(2));
    });

    listMatrix('yükleniyor', (t, w, h, s, dark) async {
      final auth = _auth()..inboxGates.add(Completer<void>());
      await _pump(t, auth, width: w, height: h, scale: s, dark: dark);
      expect(find.byType(ListSkeleton), findsOneWidget);
      expect(find.byType(AnnouncementInboxCard), findsNothing);
      expect(find.text('Henüz duyuru yok.'), findsNothing);
    });

    listMatrix('boş', (t, w, h, s, dark) async {
      await _pump(t, _auth(rows: <Map<String, dynamic>>[]), width: w, height: h, scale: s, dark: dark);
      expect(find.byType(EmptyCard), findsOneWidget);
      expect(find.text('Henüz duyuru yok.'), findsOneWidget);
      expect(find.text('Yönetimin size gönderdiği duyurular burada görünür.'), findsOneWidget);
    });

    listMatrix('hata: "duyuru yok" demez, Tekrar Dene ile düzelir', (t, w, h, s, dark) async {
      final auth = _auth()..inboxError = ApiException('Sunucu yanıt vermedi, tekrar deneyin.');
      await _pump(t, auth, width: w, height: h, scale: s, dark: dark);
      expect(find.text('Sunucu yanıt vermedi, tekrar deneyin.'), findsOneWidget);
      expect(find.text('Henüz duyuru yok.'), findsNothing);
      expect(find.byType(AnnouncementInboxCard), findsNothing);
      auth.inboxError = null;
      await tapText(t, 'Tekrar Dene');
      await settleFor(t);
      expect(find.byType(AnnouncementInboxCard), findsNWidgets(3));
    });

    listMatrix('okuma penceresi: acil duyuru, düzenlendi notu, tam metin', (t, w, h, s, dark) async {
      final auth = _auth(
        rows: <Map<String, dynamic>>[
          inboxRow(
            12,
            title: 'Su kesintisi',
            body: 'Yarın 09:00-13:00 arası su kesintisi olacaktır. ' * 10,
            importance: 'urgent',
            editedAt: DateTime.utc(2026, 10, 16, 9),
          ),
        ],
      );
      await _pump(t, auth, width: w, height: h, scale: s, dark: dark);
      await _open(t, 'Su kesintisi');
      expect(find.byType(AnnouncementReadDialog), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('announcement_read_body')), findsOneWidget);
      expect(find.text('Düzenlendi: 16.10.2026 12:00'), findsOneWidget, reason: '09:00 UTC = 12:00 İstanbul');
      expect(find.text('Acil'), findsWidgets);
    });
  });

  group('okuma akışı', () {
    testWidgets('açınca önce tam metin alınır (OKUNDU YAZMAZ), sonra okundu yazılır; liste ve rozet güncellenir', (t) async {
      final auth = _auth();
      final notifier = _notifier(auth);
      await notifier.refresh();
      await _pump(t, auth, notifier: notifier);
      expect(notifier.unreadCount, 2);
      expect(notifier.unreadUrgent, 1);
      expect(_isRead(t, 'Su kesintisi'), isFalse);

      await _open(t, 'Su kesintisi');
      expect(auth.myDetailCalls, <int>[12]);
      expect(auth.readCalls, <int>[12]);
      expect(find.text('Yarın 09:00-13:00 arası su kesintisi olacaktır. Lütfen önlem alın.'), findsWidgets);
      // Liste ve rozet pencere açıkken bile güncel.
      expect(_isRead(t, 'Su kesintisi'), isTrue);
      expect(notifier.unreadCount, 1);
      expect(notifier.unreadUrgent, 0);
      expect(notifier.urgentAnnouncement, isNull);

      await tapText(t, 'Kapat');
      await settleFor(t);
      expect(_unreadDot(), findsOneWidget);
      // Aynı duyuru yeniden açılınca tekrar okundu yazılmaz (zaten okundu).
      await _open(t, 'Su kesintisi');
      expect(auth.readCalls, <int>[12]);
      notifier.dispose();
    });

    testWidgets('okundu yazımı BAŞARISIZ olursa görünür kalır; duyuru listede okunmamış durur; Tekrar Dene yazar', (t) async {
      final auth = _auth()..readError = ApiException('Bağlantı kesildi.');
      final notifier = _notifier(auth);
      await notifier.refresh();
      await _pump(t, auth, notifier: notifier);

      await _open(t, 'Asansör bakımı');
      expect(auth.readCalls, <int>[11]);
      expect(find.text('Bağlantı kesildi.'), findsOneWidget, reason: 'sessiz yutulmaz');
      expect(find.text('Tekrar Dene'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('announcement_read_body')), findsOneWidget, reason: 'metin yine de okunur');
      expect(_isRead(t, 'Asansör bakımı'), isFalse);
      expect(notifier.unreadCount, 2, reason: 'rozet düşmez');

      auth.readError = null;
      await tapText(t, 'Tekrar Dene');
      await settleFor(t);
      expect(auth.readCalls, <int>[11, 11]);
      expect(find.text('Bağlantı kesildi.'), findsNothing);
      expect(_isRead(t, 'Asansör bakımı'), isTrue);
      expect(notifier.unreadCount, 1);
      notifier.dispose();
    });

    testWidgets('okundu yazımı 429 alırsa Tekrar Dene süre dolana dek yok; sonra yazılır', (t) async {
      final auth = _auth()
        ..readError = ApiException('Çok fazla duyuru işlemi.', statusCode: 429, retryAfterSeconds: 10);
      await _pump(t, auth);
      await _open(t, 'Asansör bakımı');
      expect(find.text('Çok sık deneme yapıldı. 10 saniye sonra tekrar deneyin.'), findsOneWidget);
      expect(find.text('Tekrar Dene'), findsNothing);
      expect(_isRead(t, 'Asansör bakımı'), isFalse);

      auth.readError = null;
      await t.pump(const Duration(seconds: 11));
      await t.pump();
      expect(find.text('Tekrar Dene'), findsOneWidget);
      await tapText(t, 'Tekrar Dene');
      await settleFor(t);
      expect(auth.readCalls, <int>[11, 11]);
      expect(_isRead(t, 'Asansör bakımı'), isTrue);
    });

    testWidgets('duyuru bu arada geri çekilmiş (404): Türkçe hata, okundu yazılmaz, liste yenilenir', (t) async {
      final auth = _auth();
      await _pump(t, auth);
      auth.inboxRows.firstWhere((r) => r['id'] == 11)['status'] = 'withdrawn';
      final callsBefore = auth.inboxCalls.length;
      await _open(t, 'Asansör bakımı');
      expect(find.text('Duyuru bulunamadı ya da artık yayında değil.'), findsOneWidget);
      expect(auth.readCalls, isEmpty);
      expect(find.byKey(const ValueKey<String>('announcement_read_body')), findsNothing);
      expect(auth.inboxCalls.length, greaterThan(callsBefore), reason: 'liste yenilendi');
      await tapText(t, 'Kapat');
      await settleFor(t);
      expect(find.text('Asansör bakımı'), findsNothing);
    });

    testWidgets('tam metin alınamazsa hata + Tekrar Dene; okundu yazılmaz', (t) async {
      final auth = _auth()..myDetailError = ApiException('Duyuru şu an açılamadı.');
      await _pump(t, auth);
      await _open(t, 'Su kesintisi');
      expect(find.text('Duyuru şu an açılamadı.'), findsOneWidget);
      expect(auth.readCalls, isEmpty);
      auth.myDetailError = null;
      await tapText(t, 'Tekrar Dene');
      await settleFor(t);
      expect(find.byKey(const ValueKey<String>('announcement_read_body')), findsOneWidget);
      expect(auth.readCalls, <int>[12]);
    });

    testWidgets('okundu yazımı sürerken pencere kapatılsa bile liste ve rozet güncellenir', (t) async {
      final auth = _auth()..readGate = Completer<void>();
      final notifier = _notifier(auth);
      await notifier.refresh();
      await _pump(t, auth, notifier: notifier);
      await tapFinder(t, _card('Asansör bakımı'));
      await settleFor(t);
      expect(auth.readCalls, <int>[11]);
      await tapText(t, 'Kapat');
      await settleFor(t);
      expect(_isRead(t, 'Asansör bakımı'), isFalse, reason: 'sunucu henüz yanıt vermedi');

      auth.readGate!.complete();
      await settleFor(t);
      expect(_isRead(t, 'Asansör bakımı'), isTrue);
      expect(notifier.unreadCount, 1);
      expect(t.takeException(), isNull);
      notifier.dispose();
    });

    testWidgets('pencere kapanırken uçuştaki yanıt çökmez (dispose sonrası setState yok)', (t) async {
      final auth = _auth()..myDetailGate = Completer<void>();
      await _pump(t, auth);
      await tapFinder(t, _card('Su kesintisi'));
      await settleFor(t);
      expect(find.text('Duyuru yükleniyor...'), findsOneWidget);
      await tapText(t, 'Kapat');
      await settleFor(t);
      auth.myDetailGate!.complete();
      await settleFor(t);
      expect(t.takeException(), isNull);
      expect(auth.readCalls, isEmpty, reason: 'kapanan pencere okundu yazmaz');
    });
  });

  group('tümünü okundu yap', () {
    testWidgets('sunucuya yazılır, liste ve rozet güncellenir, düğme kilitlenir', (t) async {
      final auth = _auth();
      final notifier = _notifier(auth);
      await notifier.refresh();
      await _pump(t, auth, notifier: notifier);
      expect(find.text('2 okunmamış'), findsOneWidget);

      await tapText(t, 'Tümünü okundu yap');
      await settleFor(t);
      expect(auth.readAllCalls, <int?>[null]);
      expect(find.text('2 duyuru okundu olarak işaretlendi.'), findsOneWidget);
      expect(_unreadDot(), findsNothing);
      expect(notifier.unreadCount, 0);
      expect(notifier.unreadUrgent, 0);
      expect(find.text('2 okunmamış'), findsNothing, reason: 'sayaç rozeti kalktı');
      notifier.dispose();
    });

    testWidgets('hata: görünür, duyurular okunmamış kalır; okunmamış yoksa düğme devre dışı', (t) async {
      final auth = _auth()..readAllError = ApiException('Toplu işlem başarısız.');
      await _pump(t, auth);
      await tapText(t, 'Tümünü okundu yap');
      await settleFor(t);
      expect(find.text('Toplu işlem başarısız.'), findsOneWidget);
      expect(_unreadDot(), findsNWidgets(2));

      auth.readAllError = null;
      await tapText(t, 'Tümünü okundu yap');
      await settleFor(t);
      expect(find.text('Toplu işlem başarısız.'), findsNothing);
      expect(_unreadDot(), findsNothing);

      // Tüm duyurular okunmuş: düğme tıklanamaz (gereksiz istek yok).
      final calls = auth.readAllCalls.length;
      await t.tap(find.text('Tümünü okundu yap'), warnIfMissed: false);
      await t.pump();
      expect(auth.readAllCalls.length, calls);
    });

    testWidgets('429: "çok sık deneme" mesajı ve düğme retry_after süresince kilitli', (t) async {
      final auth = _auth()
        ..readAllError = ApiException('Çok fazla duyuru işlemi.', statusCode: 429, retryAfterSeconds: 15);
      await _pump(t, auth);
      await tapText(t, 'Tümünü okundu yap');
      await settleFor(t);
      expect(find.text('Çok sık deneme yapıldı. 15 saniye sonra tekrar deneyin.'), findsOneWidget);
      await t.tap(find.text('Tümünü okundu yap'), warnIfMissed: false);
      await t.pump();
      expect(auth.readAllCalls.length, 1, reason: 'kilitliyken yeni istek yok');

      await t.pump(const Duration(seconds: 16));
      auth.readAllError = null;
      await tapText(t, 'Tümünü okundu yap');
      await settleFor(t);
      expect(auth.readAllCalls.length, 2);
      expect(_unreadDot(), findsNothing);
    });

    testWidgets('site süzgeciyle: yalnız o sitenin duyuruları okundu yapılır (site_code gider)', (t) async {
      final auth = _auth(
        rows: <Map<String, dynamic>>[
          inboxRow(21, title: 'Gül duyurusu'),
          inboxRow(22, title: 'Mavi duyurusu', siteCode: 12, siteName: 'Mavi Park'),
        ],
      );
      final notifier = _notifier(auth);
      await notifier.refresh();
      await _pump(
        t,
        auth,
        notifier: notifier,
        sites: const <PeopleSite>[
          PeopleSite(code: 11, name: 'Gül Sitesi'),
          PeopleSite(code: 12, name: 'Mavi Park'),
        ],
      );
      expect(find.text('Gül Sitesi'), findsWidgets, reason: 'birden çok sitede kartta site adı yazılır');

      await t.tap(find.byType(DropdownButtonFormField<int>));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      await t.tap(find.text('Mavi Park').last);
      await t.pump();
      await t.pump(const Duration(milliseconds: 450));
      await settleFor(t);
      expect(auth.inboxCalls.last.site, 12);
      expect(find.byType(AnnouncementInboxCard), findsOneWidget);
      expect(find.text('Mavi duyurusu'), findsOneWidget);

      await tapText(t, 'Tümünü okundu yap');
      await settleFor(t);
      expect(auth.readAllCalls, <int?>[12]);
      expect(auth.inboxRows.firstWhere((r) => r['id'] == 21)['read_at'], isNull, reason: 'diğer site dokunulmadı');
      expect(notifier.unreadCount, 1, reason: 'tek sitede kalan sayı sunucudan okunur');
      notifier.dispose();
    });
  });

  group('sayfalama ve yenileme', () {
    AnnouncementFakeAuth many(int count) => _auth(
      rows: <Map<String, dynamic>>[
        for (var i = 1; i <= count; i++) inboxRow(i, title: 'Duyuru $i', read: true),
      ],
    );

    testWidgets('next_before_id imleci: "Daha fazla yükle" sonraki sayfayı ekler, tekrar eden kayıt eklenmez', (t) async {
      final auth = many(5)..maxPage = 2;
      await _pump(t, auth);
      expect(find.byType(AnnouncementInboxCard), findsNWidgets(2));
      expect(auth.inboxCalls.single.before, isNull);

      await tapText(t, 'Daha fazla yükle');
      await settleFor(t);
      expect(find.byType(AnnouncementInboxCard), findsNWidgets(4));
      expect(auth.inboxCalls.last.before, 4, reason: 'imleç = önceki sayfanın son numarası');
      await tapText(t, 'Daha fazla yükle');
      await settleFor(t);
      expect(find.byType(AnnouncementInboxCard), findsNWidgets(5));
      expect(find.text('Daha fazla yükle'), findsNothing);
      final ids = [
        for (final card in t.widgetList<AnnouncementInboxCard>(find.byType(AnnouncementInboxCard)))
          card.announcement.id,
      ];
      expect(ids, <int>[5, 4, 3, 2, 1]);
    });

    testWidgets('sayfa yüklenirken yenileme olursa eski imleçli sayfa listeye eklenmez', (t) async {
      final auth = many(5)..maxPage = 2;
      final key = await _pump(t, auth);
      final slow = Completer<void>();
      auth.inboxGates.add(slow);
      await tapText(t, 'Daha fazla yükle'); // yavaş sayfa 2
      await t.pump();
      await key.currentState!.reload(); // yenileme (sayfa 1) kapısız tamamlanır
      await settleFor(t);
      expect(find.byType(AnnouncementInboxCard), findsNWidgets(2));
      slow.complete();
      await settleFor(t);
      expect(find.byType(AnnouncementInboxCard), findsNWidgets(2), reason: 'eski imleçle gelen sayfa eklenmedi');
      expect(find.text('Daha fazla yükle'), findsOneWidget, reason: 'bayrak yeni yüklemeye göre');
    });

    testWidgets('sayfa hatası mevcut listeyi silmez, Tekrar Dene ile düzelir', (t) async {
      final auth = many(5)..maxPage = 2;
      await _pump(t, auth);
      auth.inboxError = ApiException('Sunucu yanıt vermedi, tekrar deneyin.');
      await tapText(t, 'Daha fazla yükle');
      await settleFor(t);
      expect(find.text('Sunucu yanıt vermedi, tekrar deneyin.'), findsOneWidget);
      expect(find.byType(AnnouncementInboxCard), findsNWidgets(2));
      auth.inboxError = null;
      await tapText(t, 'Tekrar Dene');
      await settleFor(t);
      expect(find.byType(AnnouncementInboxCard), findsNWidgets(4));
    });

    testWidgets('yenile düğmesi ve reload() (aşağı çekip yenileme) yeni duyuruyu getirir', (t) async {
      final auth = _auth();
      final key = await _pump(t, auth);
      auth.inboxRows.add(inboxRow(30, title: 'Yeni gelen'));
      await tapFinder(t, find.byTooltip('Yenile'));
      await settleFor(t);
      expect(find.text('Yeni gelen'), findsOneWidget);

      auth.inboxRows.add(inboxRow(31, title: 'Çekip yenilenen'));
      await key.currentState!.reload();
      await settleFor(t);
      expect(find.text('Çekip yenilenen'), findsOneWidget);
    });

    testWidgets('yoklama yeni duyuru bildirince liste kendiliğinden yenilenir (sayfa yenilemeden)', (t) async {
      final auth = _auth();
      final notifier = _notifier(auth);
      await notifier.refresh();
      await _pump(t, auth, notifier: notifier);
      expect(find.text('Yeni acil toplantı'), findsNothing);

      auth.inboxRows.add(inboxRow(40, title: 'Yeni acil toplantı', importance: 'urgent'));
      await notifier.refresh();
      await settleFor(t);
      expect(find.text('Yeni acil toplantı'), findsOneWidget);
      expect(find.text('3 okunmamış'), findsOneWidget);
      notifier.dispose();
    });
  });

  group('erişilebilirlik', () {
    testWidgets('kart etiketi okunmamış / acil durumunu metinle söyler', (t) async {
      final semantics = t.ensureSemantics();
      final auth = _auth();
      await _pump(t, auth);
      expect(
        find.bySemanticsLabel(RegExp('Okunmamış duyuru: Acil\\. Su kesintisi')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(RegExp('^Duyuru: Aidat hatırlatması')), findsOneWidget);
      // Dokunma hedefleri >= 48 dp.
      final size = t.getSize(find.byType(AnnouncementInboxCard).first);
      expect(size.height, greaterThanOrEqualTo(48));
      expect(t.getSize(find.byTooltip('Yenile')).shortestSide, greaterThanOrEqualTo(40));
      semantics.dispose();
    });
  });

  group('inceleme düzeltmeleri: bekleyen yenileme, anlam ağacı, çift dokunuş, uzun başlık', () {
    const longTitle =
        'Sitemizin tüm bloklarında yapılacak yıllık periyodik asansör bakım ve kontrol çalışmaları hakkında önemli bilgilendirme';

    testWidgets('G7: liste YÜKLENİRKEN özet imzası değişirse yeniden yükleme ertelenir, yükleme bitince BİR kez yapılır', (t) async {
      final auth = _auth();
      final notifier = _notifier(auth);
      await notifier.refresh();
      final gate = Completer<void>();
      auth.inboxGates.add(gate);
      await _pump(t, auth, notifier: notifier);
      expect(find.byType(AnnouncementInboxCard), findsNothing, reason: 'ilk yükleme sürüyor');

      // Yükleme sürerken yeni duyuru yayınlanır ve yoklama bunu bildirir.
      auth.inboxRows.add(inboxRow(40, title: 'Yeni toplantı'));
      await notifier.refresh();
      await settleFor(t);
      final callsWhileLoading = auth.inboxCalls.length;

      gate.complete();
      await settleFor(t);
      await settleFor(t);
      expect(find.text('Yeni toplantı'), findsOneWidget, reason: 'bekleyen yenileme yükleme bitince çalıştı');
      expect(auth.inboxCalls.length, greaterThan(callsWhileLoading));
      // Bir kez: ek bir yenileme döngüsü yok.
      final settled = auth.inboxCalls.length;
      await settleFor(t);
      await settleFor(t);
      expect(auth.inboxCalls.length, settled);
      notifier.dispose();
    });

    testWidgets('G12: kart ekran okuyucuya TEK kez okunur (etiket + içerik çift okunmaz)', (t) async {
      final semantics = t.ensureSemantics();
      final auth = _auth();
      await _pump(t, auth);
      final labels = semanticLabels(t);
      for (final title in const ['Su kesintisi', 'Asansör bakımı', 'Aidat hatırlatması']) {
        expect(labels.where((l) => l.contains(title)), hasLength(1), reason: title);
      }
      final urgent = labels.singleWhere((l) => l.contains('Su kesintisi'));
      expect(urgent, contains('Okunmamış'));
      expect(urgent, contains('Acil'));
      expect(t.getSemantics(_card('Su kesintisi')).getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      semantics.dispose();
    });

    testWidgets('G15: karta çift dokunuş iki okuma penceresi açmaz; okundu isteği tek gider', (t) async {
      final auth = _auth();
      await _pump(t, auth);
      final onTap = t.widget<AnnouncementInboxCard>(_card('Su kesintisi')).onTap;
      onTap();
      onTap();
      await settleFor(t);
      expect(find.byType(AnnouncementReadDialog), findsOneWidget);
      expect(auth.readCalls, <int>[12]);
      await tapText(t, 'Kapat');
      expect(find.byType(AnnouncementReadDialog), findsNothing);
    });

    testWidgets('G11: uzun başlık okuma penceresinde gövdede SEÇİLEBİLİR tam metin olarak da yer alır (2,0 yazıda taşmaz)', (t) async {
      final auth = _auth(rows: <Map<String, dynamic>>[inboxRow(30, title: longTitle)]);
      await _pump(t, auth, width: 320, height: 640, scale: 2.0);
      await _open(t, longTitle);
      final full = find.byKey(const ValueKey<String>('announcement_full_title'));
      expect(full, findsOneWidget);
      expect(t.widget<SelectableText>(full).data, longTitle);
      expect(t.takeException(), isNull);
    });

    testWidgets('G11: kısa başlıkta tekrar eden başlık bloğu yok; kartta başlık en çok 3 satır, tam metin etiketinde', (t) async {
      final semantics = t.ensureSemantics();
      final auth = _auth(rows: <Map<String, dynamic>>[inboxRow(30, title: longTitle), inboxRow(31, title: 'Kısa başlık')]);
      await _pump(t, auth, width: 320, height: 640, scale: 2.0);
      final text = t.widget<Text>(find.descendant(of: _card(longTitle), matching: find.text(longTitle)));
      expect(text.maxLines, 3);
      expect(text.overflow, TextOverflow.ellipsis);
      expect(semanticLabels(t).where((l) => l.contains(longTitle)), hasLength(1));
      await _open(t, 'Kısa başlık');
      expect(find.byKey(const ValueKey<String>('announcement_full_title')), findsNothing);
      semantics.dispose();
    });
  });

  group('listemden kaldır', () {
    testWidgets('X: öğe kalkar, rozet düşer, Geri al geri getirir', (t) async {
      final auth = _auth();
      final notifier = _notifier(auth);
      await notifier.refresh();
      await _pump(t, auth, notifier: notifier);
      expect(notifier.unreadCount, 2);

      await tapFinder(t, find.byKey(const ValueKey<String>('announcement_remove_11')));
      await settleFor(t);
      expect(auth.hideCalls, <int>[11]);
      expect(find.text('Asansör bakımı'), findsNothing);
      expect(find.text('Duyuru listenizden kaldırıldı.'), findsOneWidget);
      expect(notifier.unreadCount, 1, reason: 'okunmamış duyuru kaldırılınca rozet düşer');

      await tapText(t, 'Geri al');
      await settleFor(t);
      expect(auth.restoreCalls, <int>[11]);
      expect(find.text('Asansör bakımı'), findsOneWidget);
      expect(notifier.unreadCount, 2);
      notifier.dispose();
    });

    testWidgets('hata görünür kalır ve öğe yerinde durur; okuma penceresinden de kaldırılır', (t) async {
      final auth = _auth()..hideError = ApiException('Sunucu hatası', statusCode: 500);
      await _pump(t, auth);
      await tapFinder(t, find.byKey(const ValueKey<String>('announcement_remove_10')));
      await settleFor(t);
      expect(find.text('Aidat hatırlatması'), findsOneWidget);
      expect(find.byType(InlineNotice), findsOneWidget);

      auth.hideError = null;
      await _open(t, 'Aidat hatırlatması');
      await tapFinder(t, find.byKey(const ValueKey<String>('announcement_read_hide')));
      await settleFor(t);
      expect(auth.hideCalls, <int>[10, 10]);
      expect(find.text('Aidat hatırlatması'), findsNothing);
    });
  });
}
