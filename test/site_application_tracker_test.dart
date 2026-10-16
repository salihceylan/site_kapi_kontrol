// Platform: site başvurusu durum izleyicisi (SiteApplicationTracker).
//
// Kurallar: hata ASLA "başvuru yok" demez; bekleyen yokken zamanlayıcı/ağ isteği yok; bekleyen varken ~30 sn
// yoklama; arka plandayken (isActive=false) ağ isteği yok; eski/yavaş yanıt yeni sonucu ezmez; onay olayı
// başvuru başına bir kez; dispose/clear sonrası gelen yanıt yok sayılır. Sanal zaman: testWidgets + pump.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/site_application.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/site_application_tracker.dart';

SiteApplication _app(
  int id, {
  String status = 'pending',
  DateTime? decidedAt,
}) => SiteApplication(
  id: id,
  status: status,
  siteName: 'Gül Sitesi',
  blockCount: 1,
  apartmentCount: 10,
  doorCount: 1,
  decidedAt: decidedAt,
);

MySiteApplications _mine({SiteApplication? pending, List<SiteApplication> items = const <SiteApplication>[]}) =>
    MySiteApplications(pending: pending, items: items);

class _Server {
  MySiteApplications state = const MySiteApplications();
  Object? error;
  int fetchCalls = 0;
  final List<int> cancelCalls = <int>[];
  Object? cancelError;
  final List<Completer<MySiteApplications>> gates = <Completer<MySiteApplications>>[];
  Completer<void>? cancelGate;
  bool gated = false;

  Future<MySiteApplications> fetch() {
    fetchCalls++;
    final failure = error;
    if (failure != null) return Future<MySiteApplications>.error(failure);
    if (gated) {
      final gate = Completer<MySiteApplications>();
      gates.add(gate);
      return gate.future;
    }
    return Future<MySiteApplications>.value(state);
  }

  Future<SiteApplication> cancel(int id) async {
    cancelCalls.add(id);
    await cancelGate?.future;
    final failure = cancelError;
    if (failure != null) throw failure;
    return _app(id, status: 'cancelled');
  }
}

SiteApplicationTracker _tracker(
  _Server server, {
  bool Function()? isActive,
  bool Function()? isEligible,
  DateTime Function()? now,
}) => SiteApplicationTracker(
  fetch: server.fetch,
  cancel: server.cancel,
  isActive: isActive,
  isEligible: isEligible,
  now: now,
);

Future<void> _elapse(WidgetTester t, Duration d) async {
  await t.pump(d);
  await t.pump();
}

void main() {
  testWidgets('başvuru yok: bir kez okur, bekleyen olmadığı için zamanlayıcı kurmaz ve tekrar sormaz', (t) async {
    final server = _Server();
    final tracker = _tracker(server);
    await tracker.ensureLoaded();
    expect(tracker.hasLoaded, isTrue);
    expect(tracker.latest, isNull);
    expect(tracker.error, isNull);
    expect(tracker.isPolling, isFalse);

    await _elapse(t, const Duration(minutes: 5));
    expect(server.fetchCalls, 1, reason: 'bekleyen yokken yoklama yok');
    tracker.dispose();
  });

  testWidgets('ensureLoaded: yeni veriyi yeniden sormaz, bayat veriyi yeniler', (t) async {
    var now = DateTime(2026, 10, 16, 12);
    final server = _Server();
    final tracker = _tracker(server, now: () => now);
    await tracker.ensureLoaded();
    await tracker.ensureLoaded();
    expect(server.fetchCalls, 1);
    now = now.add(const Duration(minutes: 2));
    await tracker.ensureLoaded();
    expect(server.fetchCalls, 2, reason: '1 dakikadan eski veri yenilenir');
    tracker.dispose();
  });

  testWidgets('bekleyen başvuru: ~30 sn yoklanır; onaylanınca durur ve onay olayı BİR kez gelir', (t) async {
    final server = _Server()..state = _mine(pending: _app(5), items: [_app(5)]);
    final tracker = _tracker(server);
    final approvals = <int>[];
    final sub = tracker.approvals.listen((a) => approvals.add(a.id));

    await tracker.ensureLoaded();
    expect(tracker.pending!.id, 5);
    expect(tracker.isPolling, isTrue);

    await _elapse(t, const Duration(seconds: 30));
    expect(server.fetchCalls, 2);
    await _elapse(t, const Duration(seconds: 30));
    expect(server.fetchCalls, 3);
    expect(approvals, isEmpty);

    server.state = _mine(items: [_app(5, status: 'approved', decidedAt: DateTime.now())]);
    await _elapse(t, const Duration(seconds: 30));
    expect(server.fetchCalls, 4);
    expect(tracker.pending, isNull);
    expect(tracker.latest!.isApproved, isTrue);
    expect(approvals, <int>[5]);
    expect(tracker.isPolling, isFalse, reason: 'bekleyen kalmadı: yoklama durur');

    await _elapse(t, const Duration(minutes: 3));
    expect(server.fetchCalls, 4);
    await tracker.refresh();
    expect(approvals, <int>[5], reason: 'aynı onay için ikinci olay yok');

    unawaited(sub.cancel());
    tracker.dispose();
  });

  testWidgets('çok eski onay olay üretmez; kararı olmayan onay olay üretir', (t) async {
    final now = DateTime(2026, 10, 16, 12);
    final old = _Server()
      ..state = _mine(items: [_app(3, status: 'approved', decidedAt: now.subtract(const Duration(days: 8)))]);
    final oldTracker = _tracker(old, now: () => now);
    final oldEvents = <int>[];
    final oldSub = oldTracker.approvals.listen((a) => oldEvents.add(a.id));
    await oldTracker.ensureLoaded();
    await t.pump();
    expect(oldEvents, isEmpty);

    final undated = _Server()..state = _mine(items: [_app(4, status: 'approved')]);
    final undatedTracker = _tracker(undated, now: () => now);
    final events = <int>[];
    final sub = undatedTracker.approvals.listen((a) => events.add(a.id));
    await undatedTracker.ensureLoaded();
    await t.pump();
    expect(events, <int>[4]);

    unawaited(oldSub.cancel());
    unawaited(sub.cancel());
    oldTracker.dispose();
    undatedTracker.dispose();
  });

  testWidgets('HATA "başvuru yok" DEMEZ: veri null kalır, hata mesajı dolar, geri çekilmeyle yeniden dener', (t) async {
    final server = _Server()..error = ApiException('Sunucu yanıt vermedi, tekrar deneyin.');
    final tracker = _tracker(server);
    await tracker.ensureLoaded();
    expect(tracker.hasLoaded, isFalse, reason: 'bilinmiyor; "başvuru yok" değil');
    expect(tracker.latest, isNull);
    expect(tracker.error, 'Sunucu yanıt vermedi, tekrar deneyin.');
    expect(tracker.isPolling, isTrue, reason: 'durum bilinmiyorsa yeniden denenir');

    await _elapse(t, const Duration(seconds: 30));
    expect(server.fetchCalls, 2);
    // Üstel geri çekilme: sonraki deneme 60 sn sonra.
    await _elapse(t, const Duration(seconds: 30));
    expect(server.fetchCalls, 2);
    server.error = null;
    server.state = _mine(pending: _app(8));
    await _elapse(t, const Duration(seconds: 30));
    expect(server.fetchCalls, 3);
    expect(tracker.hasLoaded, isTrue);
    expect(tracker.error, isNull);
    expect(tracker.pending!.id, 8);
    tracker.dispose();
  });

  testWidgets('yoklama hatası önceki durumu SİLMEZ; hata görünür, bekleyen kalır', (t) async {
    final server = _Server()..state = _mine(pending: _app(5));
    final tracker = _tracker(server);
    await tracker.ensureLoaded();
    expect(tracker.pending!.id, 5);

    server.error = ApiException('Bağlantı yok');
    await _elapse(t, const Duration(seconds: 30));
    expect(tracker.pending!.id, 5, reason: 'önceki başarılı veri korunur');
    expect(tracker.error, 'Bağlantı yok');

    server.error = null;
    await tracker.refresh();
    expect(tracker.error, isNull);
    tracker.dispose();
  });

  testWidgets('ApiException dışı hata genel Türkçe metne çevrilir (ham istisna sızmaz)', (t) async {
    final server = _Server()..error = StateError('ham ayrıntı');
    final tracker = _tracker(server);
    await tracker.refresh();
    expect(tracker.error, isNotNull);
    expect(tracker.error!.contains('ham ayrıntı'), isFalse);
    expect(tracker.error!.contains('StateError'), isFalse);
    expect(tracker.error, startsWith('Site başvuru durumu alınamadı'));
    tracker.dispose();
  });

  testWidgets('arka planda (isActive=false) ağ isteği yok; öne gelince yoklama sürer', (t) async {
    var active = false;
    final server = _Server()..state = _mine(pending: _app(5));
    final tracker = _tracker(server, isActive: () => active);
    await tracker.ensureLoaded();
    expect(server.fetchCalls, 1, reason: 'ilk okuma görünür ekran içindir');

    await _elapse(t, const Duration(minutes: 3));
    expect(server.fetchCalls, 1, reason: 'görünür değilken yoklama turları atlanır');

    active = true;
    await _elapse(t, const Duration(seconds: 30));
    expect(server.fetchCalls, 2);
    tracker.dispose();
  });

  testWidgets('eski/yavaş yanıt yeni sonucu ezmez', (t) async {
    final server = _Server()..gated = true;
    final tracker = _tracker(server);
    final first = tracker.refresh(); // yavaş
    final second = tracker.refresh(); // yeni
    expect(server.gates, hasLength(2));

    server.gates[1].complete(_mine(pending: _app(9)));
    expect(await second, isTrue);
    expect(tracker.pending!.id, 9);

    server.gates[0].complete(_mine(items: [_app(1, status: 'rejected')]));
    expect(await first, isNull, reason: 'eski yanıt yok sayılır');
    expect(tracker.pending!.id, 9, reason: 'yeni sonuç ezilmedi');
    tracker.dispose();
  });

  testWidgets('dispose ve clear sonrası gelen yanıt yok sayılır; clear durumu sıfırlar', (t) async {
    final server = _Server()..gated = true;
    final tracker = _tracker(server);
    final inFlight = tracker.refresh();
    tracker.clear();
    server.gates.single.complete(_mine(pending: _app(5)));
    expect(await inFlight, isNull);
    expect(tracker.hasLoaded, isFalse, reason: 'eski kullanıcının yanıtı sızmaz');
    expect(tracker.loading, isFalse);

    final again = tracker.refresh();
    tracker.dispose();
    server.gates.last.complete(_mine(pending: _app(6)));
    expect(await again, isNull);
    expect(tracker.hasLoaded, isFalse);
  });

  testWidgets('uygun olmayan rol: ağ isteği yok', (t) async {
    final server = _Server()..state = _mine(pending: _app(5));
    final tracker = _tracker(server, isEligible: () => false);
    await tracker.ensureLoaded();
    expect(await tracker.refresh(), isNull);
    expect(server.fetchCalls, 0);
    expect(tracker.isPolling, isFalse);
    tracker.dispose();
  });

  testWidgets('iptal: başarıda bekleyen kalkar, iptal kaydı görünür, yoklama durur; durum sunucudan doğrulanır', (t) async {
    final server = _Server()..state = _mine(pending: _app(5), items: [_app(5)]);
    final tracker = _tracker(server);
    await tracker.ensureLoaded();
    expect(tracker.isPolling, isTrue);

    // İptalden sonra sunucu gerçek durumu bildirir.
    server.state = _mine(items: [_app(5, status: 'cancelled')]);
    final result = await tracker.cancelPending();
    await t.pump();
    expect(result!.isCancelled, isTrue);
    expect(server.cancelCalls, <int>[5]);
    expect(tracker.pending, isNull);
    expect(tracker.latest!.isCancelled, isTrue);
    expect(tracker.cancelError, isNull);
    expect(tracker.cancelling, isFalse);
    expect(tracker.isPolling, isFalse);
    expect(server.fetchCalls, 2, reason: 'iptaldan sonra durum sunucudan yeniden okunur');
    tracker.dispose();
  });

  testWidgets('iptal çift dokunuş: uçuştayken ikinci çağrı yok sayılır', (t) async {
    final server = _Server()..state = _mine(pending: _app(5));
    final tracker = _tracker(server);
    await tracker.ensureLoaded();
    server.cancelGate = Completer<void>();

    final first = tracker.cancelPending();
    expect(tracker.cancelling, isTrue);
    final second = await tracker.cancelPending();
    expect(second, isNull);
    expect(server.cancelCalls, <int>[5], reason: 'tek iptal isteği');

    server.cancelGate!.complete();
    await first;
    await t.pump();
    tracker.dispose();
  });

  testWidgets('iptal hatası: bekleyen kalır, Türkçe hata gösterilir; 409 ise durum yeniden okunur', (t) async {
    final server = _Server()..state = _mine(pending: _app(5));
    final tracker = _tracker(server);
    await tracker.ensureLoaded();

    server.cancelError = ApiException('Bu başvuru artık bekleyen durumda değil.', statusCode: 409, code: 'APPLICATION_NOT_PENDING');
    // Başka yerden karar verilmiş: sunucu artık reddedilmiş diyor.
    server.state = _mine(items: [_app(5, status: 'rejected')]);
    final result = await tracker.cancelPending();
    await t.pump();
    expect(result, isNull);
    expect(tracker.cancelError, 'Bu başvuru artık bekleyen durumda değil.');
    expect(tracker.latest!.isRejected, isTrue, reason: 'durum sunucudan yeniden okundu');
    expect(tracker.pending, isNull);
    tracker.dispose();
  });

  testWidgets('iptal sürerken gelen eski yoklama yanıtı iptal sonucunu ezmez', (t) async {
    final server = _Server()..state = _mine(pending: _app(5));
    final tracker = _tracker(server);
    await tracker.ensureLoaded();

    server.gated = true;
    final stale = tracker.refresh(); // iptalden ÖNCE başladı, hâlâ "bekleyen" diyecek
    server.cancelGate = Completer<void>();
    final cancel = tracker.cancelPending();
    server.cancelGate!.complete();
    await cancel;
    server.gates[0].complete(_mine(pending: _app(5)));
    expect(await stale, isNull);
    // İptal sonrası yeniden okuma da kapıdadır; sunucu artık "iptal" diyor.
    server.gated = false;
    server.state = _mine(items: [_app(5, status: 'cancelled')]);
    server.gates[1].complete(_mine(items: [_app(5, status: 'cancelled')]));
    await t.pump();
    expect(tracker.pending, isNull);
    expect(tracker.latest!.isCancelled, isTrue);
    tracker.dispose();
  });
}
