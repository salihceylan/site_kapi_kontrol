// Telefon bildirimi (Faz 3b-B) ile duyuru özeti ilişkisi (B10 / K8): push yoklamanın YERİNE geçmez, onu tamamlar.
// Ön planda gelen bildirim özeti HEMEN çeker; "yeni duyuru" olayı yalnız sunucu özetinden üretilir (çift uyarı yok).
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/announcement.dart';
import 'package:site_kapi_kontrol/services/announcement_notifier.dart';

void main() {
  test('notePush: özet 20 sn beklemeden çekilir; push + yoklama aynı duyuru için TEK uyarı üretir', () async {
    var calls = 0;
    var latest = 1;
    final notifier = AnnouncementNotifier(
      fetchSummary: () async {
        calls++;
        return NotificationSummary(
          unreadAnnouncements: latest - 1,
          unreadUrgent: 0,
          latestAnnouncementId: latest,
          latestPublishedAt: DateTime.utc(2026, 10, 17, 9, latest),
        );
      },
      fetchInbox: () async => throw StateError('kullanılmaz'),
      fetchAnnouncement: (id) async => ResidentAnnouncement(id: id),
    );
    addTearDown(notifier.dispose);
    final alerts = <AnnouncementAlert>[];
    final sub = notifier.alerts.listen(alerts.add);
    addTearDown(sub.cancel);

    expect(await notifier.refresh(), isTrue); // taban çizgisi
    expect(alerts, isEmpty);

    latest = 2; // sunucuda yeni duyuru yayınlandı, push geldi
    expect(await notifier.notePush(), isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(calls, 2);
    expect(alerts, hasLength(1));
    expect(alerts.single.announcementId, 2);

    // Aynı duyuru için sonraki yoklama yeni uyarı ÜRETMEZ.
    expect(await notifier.refresh(), isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(alerts, hasLength(1));
  });

  test('kapatılmış bildirimcide notePush hiçbir şey yapmaz', () async {
    var calls = 0;
    final notifier = AnnouncementNotifier(
      fetchSummary: () async {
        calls++;
        return const NotificationSummary(unreadAnnouncements: 0, unreadUrgent: 0);
      },
      fetchInbox: () async => throw StateError('kullanılmaz'),
      fetchAnnouncement: (id) async => ResidentAnnouncement(id: id),
    );
    notifier.dispose();
    expect(await notifier.notePush(), isNull);
    expect(calls, 0);
  });
}
