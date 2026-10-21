// Platform Faz 3a: AnnouncementNotifier (özet yoklaması, rozet, acil şerit, "yeni duyuru" olayı).
//
// Kurallar (docs/PLATFORM_DUYURU.md, "Anlık bildirim"): `GET /app/notifications/summary` AdaptivePoller ile
// (ön planda ~20 sn; arka planda ya da uygun olmayan rolde ağ isteği yok; hatada geri çekilme) yoklanır;
// ilk yanıt yeni duyuru sayılmaz; yeni duyuru olayı başlıkla yayınlanır; okunmamış ACİL duyuru bulunur;
// yerel okundu düşüşü sahte "yeni duyuru" üretmez; clear / dispose sonrası eski yanıt yok sayılır.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/announcement.dart';
import 'package:site_kapi_kontrol/services/announcement_notifier.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';

NotificationSummary _summary({
  int unread = 0,
  int urgent = 0,
  int? latestId,
  DateTime? latestAt,
}) => NotificationSummary(
  unreadAnnouncements: unread,
  unreadUrgent: urgent,
  latestAnnouncementId: latestId,
  latestPublishedAt: latestAt,
);

ResidentAnnouncement _item(
  int id, {
  String title = 'Duyuru',
  bool urgent = false,
  bool read = false,
}) => ResidentAnnouncement(
  id: id,
  title: title,
  importance: urgent ? AnnouncementImportance.urgent : AnnouncementImportance.normal,
  isRead: read,
);

/// Sunucuyu taklit eder: sıradaki özet, gelen kutusu ve tek tek duyurular testten sürülür.
class _Server {
  NotificationSummary summary = _summary();
  List<ResidentAnnouncement> inbox = <ResidentAnnouncement>[];
  final Map<int, ResidentAnnouncement> byId = <int, ResidentAnnouncement>{};
  Object? summaryError;
  Object? inboxError;
  Object? announcementError;
  int summaryCalls = 0;
  int inboxCalls = 0;
  final List<int> announcementCalls = <int>[];
  final List<Completer<NotificationSummary>> summaryGates = <Completer<NotificationSummary>>[];

  Future<NotificationSummary> fetchSummary() {
    summaryCalls++;
    final error = summaryError;
    if (error != null) return Future<NotificationSummary>.error(error);
    final snapshot = summary;
    if (summaryGates.isNotEmpty) {
      return summaryGates.removeAt(0).future;
    }
    return Future<NotificationSummary>.value(snapshot);
  }

  Future<ResidentAnnouncementPage> fetchInbox() async {
    inboxCalls++;
    final error = inboxError;
    if (error != null) throw error;
    return ResidentAnnouncementPage(items: List<ResidentAnnouncement>.of(inbox));
  }

  Future<ResidentAnnouncement> fetchAnnouncement(int id) async {
    announcementCalls.add(id);
    final error = announcementError;
    if (error != null) throw error;
    return byId[id] ?? _item(id);
  }
}

AnnouncementNotifier _make(
  _Server server, {
  bool Function()? isActive,
  bool Function()? isEligible,
  Duration interval = const Duration(seconds: 20),
}) {
  return AnnouncementNotifier(
    fetchSummary: server.fetchSummary,
    fetchInbox: server.fetchInbox,
    fetchAnnouncement: server.fetchAnnouncement,
    isActive: isActive,
    isEligible: isEligible,
    interval: interval,
  );
}

Future<void> _tick(WidgetTester t, [Duration d = Duration.zero]) async {
  await t.pump(d);
  await t.pump();
  await t.pump();
}

void main() {
  final t0 = DateTime.utc(2026, 10, 16, 8);

  group('özet ve taban çizgisi', () {
    testWidgets('ilk yanıt YENİ DUYURU sayılmaz; rozet ve acil sayısı güncellenir', (t) async {
      final server = _Server()
        ..summary = _summary(unread: 3, urgent: 1, latestId: 41, latestAt: t0)
        ..inbox = <ResidentAnnouncement>[_item(41, title: 'Su kesintisi', urgent: true)];
      final notifier = _make(server);
      final alerts = <AnnouncementAlert>[];
      final sub = notifier.alerts.listen(alerts.add);
      var notified = 0;
      notifier.addListener(() => notified++);

      expect(await notifier.refresh(), isTrue);
      await _tick(t);
      expect(notifier.unreadCount, 3);
      expect(notifier.unreadUrgent, 1);
      expect(notifier.hasUnreadUrgent, isTrue);
      expect(alerts, isEmpty, reason: 'uygulama açılınca eski duyuru için bildirim çıkmaz');
      expect(notified, greaterThan(0));
      expect(notifier.urgentAnnouncement?.id, 41);
      expect(notifier.urgentAnnouncement?.title, 'Su kesintisi');
      expect(server.announcementCalls, isEmpty);
      unawaited(sub.cancel());
      notifier.dispose();
    });

    testWidgets('yayın zamanı ilerleyince başlıklı olay; numara KÜÇÜLSE de (zamanlanmış duyuru) yeni sayılır', (t) async {
      final server = _Server()
        ..summary = _summary(unread: 0, latestId: 50, latestAt: t0)
        ..byId[30] = _item(30, title: 'Zamanlanmış duyuru')
        ..byId[51] = _item(51, title: 'Acil toplantı', urgent: true);
      final notifier = _make(server);
      final alerts = <AnnouncementAlert>[];
      final sub = notifier.alerts.listen(alerts.add);
      await notifier.refresh();
      await _tick(t);

      // Daha küçük numaralı (30), daha sonra yayınlanan duyuru: numara tek başına ölçüt olsaydı kaçardı.
      server.summary = _summary(unread: 1, latestId: 30, latestAt: t0.add(const Duration(minutes: 5)));
      await notifier.refresh();
      await _tick(t);
      expect(alerts.length, 1);
      expect(alerts.single.announcementId, 30);
      expect(alerts.single.title, 'Zamanlanmış duyuru');
      expect(alerts.single.urgent, isFalse);

      server.summary = _summary(unread: 2, urgent: 1, latestId: 51, latestAt: t0.add(const Duration(minutes: 9)));
      await notifier.refresh();
      await _tick(t);
      expect(alerts.length, 2);
      expect(alerts.last.title, 'Acil toplantı');
      expect(alerts.last.urgent, isTrue);
      expect(server.announcementCalls, <int>[30, 51]);

      // Aynı özet tekrar gelirse yeni olay yok.
      await notifier.refresh();
      await _tick(t);
      expect(alerts.length, 2);
      unawaited(sub.cancel());
      notifier.dispose();
    });

    testWidgets('en son duyuru GERİ ÇEKİLİNCE (zaman geriye gider) yeni duyuru sayılmaz', (t) async {
      final server = _Server()..summary = _summary(unread: 2, latestId: 50, latestAt: t0);
      final notifier = _make(server);
      final alerts = <AnnouncementAlert>[];
      final sub = notifier.alerts.listen(alerts.add);
      await notifier.refresh();
      await _tick(t);

      server.summary = _summary(unread: 1, latestId: 49, latestAt: t0.subtract(const Duration(hours: 2)));
      await notifier.refresh();
      await _tick(t);
      expect(alerts, isEmpty);
      expect(notifier.unreadCount, 1);

      // Sonra gerçek yeni duyuru: geri çekilme sonrası taban doğru güncellendiği için yakalanır.
      server.summary = _summary(unread: 2, latestId: 52, latestAt: t0.add(const Duration(hours: 1)));
      await notifier.refresh();
      await _tick(t);
      expect(alerts.length, 1);
      expect(alerts.single.announcementId, 52);
      unawaited(sub.cancel());
      notifier.dispose();
    });

    testWidgets('yayın zamanı alanı yoksa (eski sunucu) numara büyümesi yeni duyurudur', (t) async {
      final server = _Server()..summary = _summary(unread: 0, latestId: 10);
      final notifier = _make(server);
      final alerts = <AnnouncementAlert>[];
      final sub = notifier.alerts.listen(alerts.add);
      await notifier.refresh();
      server.summary = _summary(unread: 1, latestId: 11);
      await notifier.refresh();
      await _tick(t);
      expect(alerts.single.announcementId, 11);
      unawaited(sub.cancel());
      notifier.dispose();
    });

    testWidgets('ilk duyuru hiç yokken gelen ilk duyuru yeni sayılır', (t) async {
      final server = _Server();
      final notifier = _make(server);
      final alerts = <AnnouncementAlert>[];
      final sub = notifier.alerts.listen(alerts.add);
      await notifier.refresh();
      server.summary = _summary(unread: 1, latestId: 1, latestAt: t0);
      await notifier.refresh();
      await _tick(t);
      expect(alerts.length, 1);
      unawaited(sub.cancel());
      notifier.dispose();
    });

    testWidgets('başlık alınamazsa başlıksız olay (genel metin); numara korunur', (t) async {
      final server = _Server()
        ..summary = _summary(latestId: 5, latestAt: t0)
        ..announcementError = ApiException('ağ yok');
      final notifier = _make(server);
      final alerts = <AnnouncementAlert>[];
      final sub = notifier.alerts.listen(alerts.add);
      await notifier.refresh();
      server.summary = _summary(unread: 1, latestId: 6, latestAt: t0.add(const Duration(minutes: 1)));
      await notifier.refresh();
      await _tick(t);
      expect(alerts.single.announcementId, 6);
      expect(alerts.single.title, isNull);
      unawaited(sub.cancel());
      notifier.dispose();
    });

    testWidgets('okunmamış sayısı SUNUCUDA arttıysa ve en son duyuru değişmediyse genel olay', (t) async {
      final server = _Server()..summary = _summary(unread: 1, latestId: 5, latestAt: t0);
      final notifier = _make(server);
      final alerts = <AnnouncementAlert>[];
      final sub = notifier.alerts.listen(alerts.add);
      await notifier.refresh();
      server.summary = _summary(unread: 2, latestId: 5, latestAt: t0);
      await notifier.refresh();
      await _tick(t);
      expect(alerts.length, 1);
      expect(alerts.single.announcementId, isNull);
      unawaited(sub.cancel());
      notifier.dispose();
    });
  });

  group('yerel okundu ve acil şerit', () {
    testWidgets('yerel düşüş sahte "yeni duyuru" üretmez; sunucu eski sayıyı döndürse bile', (t) async {
      final server = _Server()
        ..summary = _summary(unread: 2, urgent: 1, latestId: 5, latestAt: t0)
        ..inbox = <ResidentAnnouncement>[_item(5, title: 'Acil', urgent: true), _item(4)];
      final notifier = _make(server);
      final alerts = <AnnouncementAlert>[];
      final sub = notifier.alerts.listen(alerts.add);
      await notifier.refresh();
      await _tick(t);
      expect(notifier.urgentAnnouncement?.id, 5);

      notifier.noteRead(5, urgent: true);
      expect(notifier.unreadCount, 1);
      expect(notifier.unreadUrgent, 0);
      expect(notifier.urgentAnnouncement, isNull, reason: 'okunan acil duyuru şeritten hemen kalkar');

      // Okuma sunucuya henüz yazılmamış gibi eski özet gelir: sayı geri çıkar ama "yeni duyuru" olayı yok.
      await notifier.refresh();
      await _tick(t);
      expect(notifier.unreadCount, 2);
      expect(alerts, isEmpty);

      server.summary = _summary(unread: 1, urgent: 0, latestId: 5, latestAt: t0);
      await notifier.refresh();
      await _tick(t);
      expect((notifier.unreadCount, notifier.unreadUrgent), (1, 0));
      expect(notifier.urgentAnnouncement, isNull);
      unawaited(sub.cancel());
      notifier.dispose();
    });

    testWidgets('noteHidden: okunmamışsa sayı düşer ve acil şerit kalkar; okunmuşsa sayılar değişmez', (t) async {
      final server = _Server()
        ..summary = _summary(unread: 2, urgent: 1, latestId: 5, latestAt: t0)
        ..inbox = <ResidentAnnouncement>[_item(5, urgent: true), _item(4)];
      final notifier = _make(server);
      await notifier.refresh();
      await _tick(t);
      notifier.noteHidden(9, unread: false, urgent: false);
      expect(notifier.unreadCount, 2);
      notifier.noteHidden(5, unread: true, urgent: true);
      expect((notifier.unreadCount, notifier.unreadUrgent), (1, 0));
      expect(notifier.urgentAnnouncement, isNull);
      notifier.dispose();
    });

    testWidgets('birden çok acil duyuruda biri okununca diğeri bir sonraki turda bulunur', (t) async {
      final server = _Server()
        ..summary = _summary(unread: 2, urgent: 2, latestId: 7, latestAt: t0)
        ..inbox = <ResidentAnnouncement>[
          _item(7, title: 'İkinci acil', urgent: true),
          _item(6, title: 'Birinci acil', urgent: true),
        ];
      final notifier = _make(server);
      await notifier.refresh();
      await _tick(t);
      expect(notifier.urgentAnnouncement?.id, 7);
      expect(notifier.unreadUrgent, 2);

      notifier.noteRead(7, urgent: true);
      expect(notifier.unreadUrgent, 1);
      expect(notifier.urgentAnnouncement, isNull);
      server
        ..summary = _summary(unread: 1, urgent: 1, latestId: 7, latestAt: t0)
        ..inbox = <ResidentAnnouncement>[
          _item(7, title: 'İkinci acil', urgent: true, read: true),
          _item(6, title: 'Birinci acil', urgent: true),
        ];
      await notifier.refresh();
      await _tick(t);
      expect(notifier.urgentAnnouncement?.id, 6);
      expect(notifier.urgentAnnouncement?.title, 'Birinci acil');
      notifier.dispose();
    });

    testWidgets('acil sayısı 0 olunca şerit kalkar; gelen kutusu yalnız değişimde yeniden okunur', (t) async {
      final server = _Server()
        ..summary = _summary(unread: 1, urgent: 1, latestId: 5, latestAt: t0)
        ..inbox = <ResidentAnnouncement>[_item(5, urgent: true)];
      final notifier = _make(server);
      await notifier.refresh();
      await _tick(t);
      await notifier.refresh();
      await _tick(t);
      await notifier.refresh();
      await _tick(t);
      expect(server.inboxCalls, 1, reason: 'imza değişmedi: gelen kutusu tekrar çekilmez');

      server.summary = _summary(unread: 0, urgent: 0, latestId: 5, latestAt: t0);
      await notifier.refresh();
      await _tick(t);
      expect(notifier.hasUnreadUrgent, isFalse);
      expect(notifier.urgentAnnouncement, isNull);
      notifier.dispose();
    });

    testWidgets('gelen kutusu alınamazsa şerit yine görünür (başlıksız) ve sonraki turda yeniden denenir', (t) async {
      final server = _Server()
        ..summary = _summary(unread: 1, urgent: 1, latestId: 5, latestAt: t0)
        ..inboxError = ApiException('ağ yok');
      final notifier = _make(server);
      await notifier.refresh();
      await _tick(t);
      expect(notifier.hasUnreadUrgent, isTrue);
      expect(notifier.urgentAnnouncement, isNull);

      server
        ..inboxError = null
        ..inbox = <ResidentAnnouncement>[_item(5, title: 'Acil', urgent: true)];
      await notifier.refresh();
      await _tick(t);
      expect(notifier.urgentAnnouncement?.title, 'Acil');
      expect(server.inboxCalls, 2);
      notifier.dispose();
    });

    testWidgets('noteAllRead: tüm sitelerde sayılar sıfırlanır; tek sitede yalnız sunucu değeri geçerli', (t) async {
      final server = _Server()
        ..summary = _summary(unread: 4, urgent: 1, latestId: 5, latestAt: t0)
        ..inbox = <ResidentAnnouncement>[_item(5, urgent: true)];
      final notifier = _make(server);
      await notifier.refresh();
      await _tick(t);

      notifier.noteAllRead(allSites: false);
      expect(notifier.unreadCount, 4);
      notifier.noteAllRead(allSites: true);
      expect((notifier.unreadCount, notifier.unreadUrgent), (0, 0));
      expect(notifier.urgentAnnouncement, isNull);
      notifier.dispose();
    });
  });

  group('yoklama: AdaptivePoller', () {
    testWidgets('~20 sn aralıkla yoklar; stop() sonrası ağ isteği yok', (t) async {
      final server = _Server()..summary = _summary(unread: 1, latestId: 1, latestAt: t0);
      final notifier = _make(server)..start(immediately: true);
      await _tick(t);
      expect(server.summaryCalls, 1);
      await _tick(t, const Duration(seconds: 19));
      expect(server.summaryCalls, 1);
      await _tick(t, const Duration(seconds: 1));
      expect(server.summaryCalls, 2);
      await _tick(t, const Duration(seconds: 20));
      expect(server.summaryCalls, 3);

      notifier.stop();
      await _tick(t, const Duration(minutes: 2));
      expect(server.summaryCalls, 3);
      expect(notifier.isRunning, isFalse);
      notifier.dispose();
    });

    testWidgets('arka planda (isActive false) ağ isteği yok; görünür olunca sürer', (t) async {
      var active = false;
      final server = _Server();
      final notifier = _make(server, isActive: () => active)..start(immediately: true);
      await _tick(t, const Duration(seconds: 70));
      expect(server.summaryCalls, 0);
      active = true;
      await _tick(t, const Duration(seconds: 20));
      expect(server.summaryCalls, 1);
      notifier.dispose();
    });

    testWidgets('uygun olmayan rolde (isEligible false) ağ isteği yok ve sonuç "atlandı"', (t) async {
      final server = _Server();
      final notifier = _make(server, isEligible: () => false);
      expect(await notifier.refresh(), isNull);
      expect(server.summaryCalls, 0);
      notifier.dispose();
    });

    testWidgets('hatada üstel geri çekilme: 20, 40, 80 sn; başarıda aralık döner', (t) async {
      final server = _Server()..summaryError = ApiException('sunucu yok');
      final notifier = _make(server)..start(immediately: true);
      await _tick(t);
      expect(server.summaryCalls, 1);
      await _tick(t, const Duration(seconds: 39));
      expect(server.summaryCalls, 1, reason: 'ilk hatadan sonra 40 sn beklenir');
      await _tick(t, const Duration(seconds: 1));
      expect(server.summaryCalls, 2);
      await _tick(t, const Duration(seconds: 79));
      expect(server.summaryCalls, 2, reason: 'ikinci hatadan sonra 80 sn');
      await _tick(t, const Duration(seconds: 1));
      expect(server.summaryCalls, 3);

      server.summaryError = null;
      await _tick(t, const Duration(seconds: 120));
      expect(server.summaryCalls, 4);
      await _tick(t, const Duration(seconds: 20));
      expect(server.summaryCalls, 5, reason: 'başarıdan sonra 20 sn');
      notifier.dispose();
    });

    testWidgets('G19: isDegraded hatada true olur (dinleyiciler uyarılır), başarıda false; clear() sıfırlar', (t) async {
      final server = _Server()..summaryError = ApiException('sunucu yok');
      final notifier = _make(server);
      var notified = 0;
      notifier.addListener(() => notified++);
      expect(notifier.isDegraded, isFalse);

      expect(await notifier.refresh(), isFalse);
      expect(notifier.isDegraded, isTrue, reason: 'hatada aralık uzar: ekran "yaklaşık 20 sn" demez');
      expect(notified, 1);

      // Aynı durumda tekrar hata: gereksiz yeniden çizim yok.
      expect(await notifier.refresh(), isFalse);
      expect(notified, 1);

      server.summaryError = null;
      server.summary = _summary(unread: 1, latestId: 1, latestAt: t0);
      expect(await notifier.refresh(), isTrue);
      expect(notifier.isDegraded, isFalse);

      server.summaryError = ApiException('sunucu yok');
      await notifier.refresh();
      expect(notifier.isDegraded, isTrue);
      notifier.clear();
      expect(notifier.isDegraded, isFalse, reason: 'çıkış yapınca bayrak sıfırlanır');
      notifier.dispose();
    });

    testWidgets('uçuşta tur varken refresh() ikinci istek açmaz, bitince bir tur daha çalıştırır', (t) async {
      final server = _Server();
      final gate = Completer<NotificationSummary>();
      server.summaryGates.add(gate);
      final notifier = _make(server);
      final first = notifier.refresh();
      final second = notifier.refresh();
      expect(server.summaryCalls, 1);
      gate.complete(_summary(unread: 1));
      await first;
      await second;
      await _tick(t);
      expect(server.summaryCalls, 2, reason: 'yazma sonrası çağrılan yenileme bayat yanıta takılmaz');
      notifier.dispose();
    });
  });

  group('clear ve dispose', () {
    testWidgets('clear(): durum sıfırlanır, uçuştaki eski yanıt yok sayılır, taban yeniden kurulur', (t) async {
      final server = _Server();
      final gate = Completer<NotificationSummary>();
      server.summaryGates.add(gate);
      final notifier = _make(server);
      final alerts = <AnnouncementAlert>[];
      final sub = notifier.alerts.listen(alerts.add);
      final pending = notifier.refresh();
      notifier.clear();
      gate.complete(_summary(unread: 9, urgent: 2, latestId: 99, latestAt: t0));
      expect(await pending, isNull);
      await _tick(t);
      expect(notifier.unreadCount, 0, reason: 'çıkış yapan kullanıcının eski yanıtı yeni kullanıcıya sızmaz');
      expect(notifier.summary, isNull);

      // Yeni kullanıcı: ilk yanıt yine taban sayılır (yeni duyuru olayı yok).
      server.summary = _summary(unread: 1, latestId: 3, latestAt: t0);
      await notifier.refresh();
      await _tick(t);
      expect(notifier.unreadCount, 1);
      expect(alerts, isEmpty);
      unawaited(sub.cancel());
      notifier.dispose();
    });

    testWidgets('dispose(): zamanlayıcı kalmaz, uçuştaki yanıt dinleyicileri uyarmaz, olay akışı kapanır', (t) async {
      final server = _Server();
      final gate = Completer<NotificationSummary>();
      server.summaryGates.add(gate);
      final notifier = _make(server)..start(immediately: true);
      await _tick(t);
      var notified = 0;
      notifier.addListener(() => notified++);
      var done = false;
      final sub = notifier.alerts.listen((_) {}, onDone: () => done = true);
      notifier.dispose();
      gate.complete(_summary(unread: 5, latestId: 1, latestAt: t0));
      await _tick(t);
      await _tick(t, const Duration(minutes: 5));
      expect(notified, 0);
      expect(done, isTrue);
      expect(server.summaryCalls, 1);
      unawaited(sub.cancel());
    });
  });

  group('Panel kartı (okunmamış, acil olmayan en yeni duyuru)', () {
    testWidgets('acil olanı atlar; kalan sayı "+N"; imza değişmedikçe gelen kutusu tekrar çekilmez', (t) async {
      final server = _Server()
        ..summary = _summary(unread: 4, urgent: 1, latestId: 9, latestAt: t0)
        ..inbox = <ResidentAnnouncement>[
          _item(9, title: 'Acil su', urgent: true),
          _item(8, title: 'Asansör bakımı'),
          _item(7, title: 'Aidat'),
          _item(6, title: 'Eski', read: true),
          _item(5, title: 'Otopark'),
        ];
      final notifier = _make(server);
      await notifier.refresh();
      await _tick(t);
      expect(notifier.cardAnnouncement?.id, 8, reason: 'acil duyuru şeritte; kart onu tekrarlamaz');
      expect(notifier.urgentAnnouncement?.id, 9);
      expect(notifier.cardMoreCount, 2, reason: '4 okunmamış - 1 acil - kartın kendisi');

      await notifier.refresh();
      await _tick(t);
      await notifier.refresh();
      await _tick(t);
      expect(server.inboxCalls, 1, reason: 'ek yoklama yok: aynı imza');
      notifier.dispose();
    });

    testWidgets('yalnız acil okunmamışsa kart yok; hiç okunmamış yoksa gelen kutusu çekilmez', (t) async {
      final server = _Server()
        ..summary = _summary(unread: 1, urgent: 1, latestId: 9, latestAt: t0)
        ..inbox = <ResidentAnnouncement>[_item(9, urgent: true)];
      final notifier = _make(server);
      await notifier.refresh();
      await _tick(t);
      expect(notifier.cardAnnouncement, isNull);
      expect(notifier.cardMoreCount, 0);

      final empty = _Server()..summary = _summary(latestId: 9, latestAt: t0);
      final quiet = _make(empty);
      await quiet.refresh();
      await _tick(t);
      expect(quiet.cardAnnouncement, isNull);
      expect(empty.inboxCalls, 0);
      notifier.dispose();
      quiet.dispose();
    });

    testWidgets('noteRead kartı hemen kaldırır; okundu sunucuya yansıyınca sıradaki duyuru gelir', (t) async {
      final server = _Server()
        ..summary = _summary(unread: 2, latestId: 8, latestAt: t0)
        ..inbox = <ResidentAnnouncement>[_item(8, title: 'Yeni'), _item(7, title: 'Eski okunmamış')];
      final notifier = _make(server);
      await notifier.refresh();
      await _tick(t);
      expect(notifier.cardAnnouncement?.id, 8);
      expect(notifier.cardMoreCount, 1);

      var notified = 0;
      notifier.addListener(() => notified++);
      notifier.noteRead(8, urgent: false);
      expect(notified, greaterThan(0));
      expect(notifier.cardAnnouncement?.id, 7, reason: 'sıradaki okunmamış');
      expect(notifier.cardMoreCount, 0);

      server
        ..summary = _summary(unread: 1, latestId: 8, latestAt: t0)
        ..inbox = <ResidentAnnouncement>[_item(8, title: 'Yeni', read: true), _item(7, title: 'Eski okunmamış')];
      await notifier.refresh();
      await _tick(t);
      expect(notifier.cardAnnouncement?.id, 7);

      server
        ..summary = _summary(unread: 0, latestId: 8, latestAt: t0)
        ..inbox = <ResidentAnnouncement>[_item(8, read: true), _item(7, read: true)];
      await notifier.refresh();
      await _tick(t);
      expect(notifier.cardAnnouncement, isNull);
      notifier.dispose();
    });

    testWidgets('noteAllRead ve clear kartı kaldırır', (t) async {
      final server = _Server()
        ..summary = _summary(unread: 1, latestId: 8, latestAt: t0)
        ..inbox = <ResidentAnnouncement>[_item(8)];
      final notifier = _make(server);
      await notifier.refresh();
      await _tick(t);
      expect(notifier.cardAnnouncement, isNotNull);
      notifier.noteAllRead(allSites: true);
      expect(notifier.cardAnnouncement, isNull);

      await notifier.refresh();
      await _tick(t);
      notifier.clear();
      expect(notifier.cardAnnouncement, isNull);
      notifier.dispose();
    });
  });
}
