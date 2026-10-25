// Platform: başvuranın site başvurusu durum kartı (SiteApplicationStatusCard).
//
// Bekleyen: "Site başvurunuz inceleniyor" + onaylı iptal (çift dokunuş korumalı); Reddedildi: gerekçe +
// "Yeniden başvur"; İptal; Onaylandı (yeni): "Hesabı yenile"; durum alınamadıysa hata + "Tekrar Dene" (asla
// "başvuru yok" değil). Taşma: 320x640 x2,0 ve 360x640 x1,5, açık + koyu tema; dokunma hedefleri >= 48 dp.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/site_application.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/site_application_tracker.dart';
import 'package:site_kapi_kontrol/ui/widgets/site_application_status_card.dart';

import '../design/harness.dart';
import 'dialog_layout_harness.dart';
import 'g4_test_support.dart';
import 'site_application_fixtures.dart';

class _Card {
  _Card(this.auth, this.tracker);

  final SiteApplicationFakeAuth auth;
  final SiteApplicationTracker tracker;
  final List<SiteApplication> reapplied = <SiteApplication>[];
  int accountRefreshes = 0;
  Completer<void>? reapplyGate;
  Completer<void>? accountGate;
}

SiteApplicationFakeAuth _auth() => SiteApplicationFakeAuth(role: UserRole.individual);

Future<_Card> _pump(
  WidgetTester t,
  SiteApplicationFakeAuth auth, {
  double width = 400,
  double height = 900,
  double scale = 1.0,
  bool dark = false,
  bool withAccountRefresh = true,
  bool load = true,
  bool showApproved = true,
  bool showLoadFailure = true,
  bool showReapplyOnRejected = true,
}) async {
  final tracker = SiteApplicationTracker(
    fetch: () => auth.getMySiteApplications(),
    cancel: (id) => auth.cancelSiteApplication(id),
  );
  final card = _Card(auth, tracker);
  await pumpAt(
    t,
    SiteApplicationStatusCard(
      tracker: tracker,
      onReapply: (previous) async {
        card.reapplied.add(previous);
        await card.reapplyGate?.future;
      },
      onRefreshAccount: withAccountRefresh
          ? () async {
              card.accountRefreshes++;
              await card.accountGate?.future;
            }
          : null,
      showApproved: showApproved,
      showLoadFailure: showLoadFailure,
      showReapplyOnRejected: showReapplyOnRejected,
    ),
    width: width,
    height: height,
    scale: scale,
    dark: dark,
  );
  if (load) {
    await tracker.ensureLoaded();
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
  }
  addTearDown(tracker.dispose);
  return card;
}

/// Zamanlayıcıları (yoklama) kapatır.
Future<void> _end(WidgetTester t, _Card card) async {
  await t.pumpWidget(const SizedBox());
  card.tracker.dispose();
}

void main() {
  group('taşma matrisi', () {
    g4LayoutMatrix('bekleyen: kart, özet, iptal düğmesi', (t, w, h, s, dark) async {
      final auth = _auth()..seed([saRow(7, siteName: 'Çok Uzun Bir Site Adı Konutları Sitesi', note: 'x')]);
      final card = await _pump(t, auth, width: w, height: h, scale: s, dark: dark);
      expect(find.text('Site başvurunuz inceleniyor'), findsOneWidget);
      await scrollTo(t, find.byKey(const ValueKey<String>('site_application_cancel')));
      expect(find.text('Başvuruyu iptal et'), findsOneWidget);
      await _end(t, card);
    });

    g4LayoutMatrix('reddedildi: uzun gerekçe ve yeniden başvur', (t, w, h, s, dark) async {
      final auth = _auth()
        ..seed([
          saRow(
            7,
            status: 'rejected',
            decisionNote: 'Başvurunuzdaki adres bilgisi eksik olduğu için site kaydı oluşturulamadı; lütfen açık adresi yazıp yeniden başvurun.',
            decidedAt: DateTime.utc(2026, 10, 16, 8),
          ),
        ]);
      final card = await _pump(t, auth, width: w, height: h, scale: s, dark: dark);
      expect(find.text('Site başvurunuz reddedildi'), findsOneWidget);
      await scrollTo(t, find.byKey(const ValueKey<String>('site_application_reapply')));
      expect(find.textContaining('adres bilgisi eksik'), findsOneWidget);
      await _end(t, card);
    });

    g4LayoutMatrix('iptal edildi ve onaylandı kartları', (t, w, h, s, dark) async {
      final cancelled = _auth()..seed([saRow(7, status: 'cancelled')]);
      var card = await _pump(t, cancelled, width: w, height: h, scale: s, dark: dark);
      expect(find.text('Site başvurunuzu iptal ettiniz'), findsOneWidget);
      await _end(t, card);

      final approved = _auth()..seed([saRow(8, status: 'approved', decidedAt: DateTime.now())]);
      card = await _pump(t, approved, width: w, height: h, scale: s, dark: dark);
      expect(find.text('Site başvurunuz onaylandı'), findsOneWidget);
      await scrollTo(t, find.byKey(const ValueKey<String>('site_application_refresh_account')));
      await _end(t, card);
    });

    g4LayoutMatrix('durum alınamadı: hata + Tekrar Dene', (t, w, h, s, dark) async {
      final auth = _auth()..mineError = ApiException('Sunucu yanıt vermedi, tekrar deneyin.');
      final card = await _pump(t, auth, width: w, height: h, scale: s, dark: dark);
      await scrollTo(t, find.text('Tekrar Dene'));
      expect(find.text('Sunucu yanıt vermedi, tekrar deneyin.'), findsOneWidget);
      await _end(t, card);
    });
  });

  group('durumlar', () {
    testWidgets('başvuru yok: kart hiç çizilmez', (t) async {
      final card = await _pump(t, _auth());
      expect(find.byType(Card), findsNothing);
      expect(find.text('Site başvurunuz inceleniyor'), findsNothing);
      expect(find.text('Site başvurunuz reddedildi'), findsNothing);
      await _end(t, card);
    });

    testWidgets('bekleyen: site adı, yapı, İstanbul saati; rozet ve düğmeler', (t) async {
      final auth = _auth()
        ..seed([saRow(7, siteName: 'Gül Sitesi', createdAt: DateTime.utc(2026, 10, 16, 21, 30))]);
      final card = await _pump(t, auth);
      expect(find.text('Site başvurunuz inceleniyor'), findsOneWidget);
      expect(find.text('Bekliyor'), findsOneWidget, reason: 'renk tek başına anlam taşımaz: etiket');
      expect(find.text('Gül Sitesi'), findsOneWidget);
      expect(find.text('2 blok • 30 daire • 1 kapı'), findsOneWidget);
      expect(find.text('Başvuru: 17.10.2026 00:30'), findsOneWidget, reason: '21:30 UTC = ertesi gün 00:30 İstanbul');
      expect(find.textContaining('Süper kullanıcı onayladığında site yöneticisi olacaksınız.'), findsOneWidget);
      expect(find.text('Başvuruyu iptal et'), findsOneWidget);
      expect(card.tracker.isPolling, isTrue, reason: 'bekleyen başvuru yoklanır');
      // Dokunma hedefi >= 48 dp.
      final size = t.getSize(find.byKey(const ValueKey<String>('site_application_cancel')));
      expect(size.height, greaterThanOrEqualTo(48));
      await _end(t, card);
    });

    testWidgets('iptal: onay penceresi -> Vazgeç istek göndermez', (t) async {
      final auth = _auth()..seed([saRow(7)]);
      final card = await _pump(t, auth);
      await t.tap(find.byKey(const ValueKey<String>('site_application_cancel')));
      await settleFor(t, 400);
      expect(find.text('Başvuru iptal edilsin mi?'), findsOneWidget);
      expect(find.textContaining('"Gül Sitesi" site başvurunuz iptal edilecek'), findsOneWidget);
      await t.tap(find.text('Vazgeç'));
      await settleFor(t, 400);
      expect(auth.cancelCalls, isEmpty);
      expect(find.text('Site başvurunuz inceleniyor'), findsOneWidget);
      await _end(t, card);
    });

    testWidgets('iptal onayı: istek gider, kart "iptal ettiniz"e döner, yoklama durur, ileti gösterilir', (t) async {
      final auth = _auth()..seed([saRow(7)]);
      final card = await _pump(t, auth);
      await t.tap(find.byKey(const ValueKey<String>('site_application_cancel')));
      await settleFor(t, 400);
      await t.tap(find.widgetWithText(ElevatedButton, 'Başvuruyu İptal Et'));
      await settleFor(t, 500);
      expect(auth.cancelCalls, <int>[7]);
      expect(find.text('Site başvurunuzu iptal ettiniz'), findsOneWidget);
      expect(find.text('Site başvurunuz inceleniyor'), findsNothing);
      expect(find.text('Başvurunuz iptal edildi.'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('site_application_reapply')), findsOneWidget);
      expect(card.tracker.isPolling, isFalse);
      await _end(t, card);
    });

    testWidgets('iptal çift dokunuş: istek sürerken düğme kilitli, tek istek', (t) async {
      final auth = _auth()
        ..seed([saRow(7)])
        ..cancelGate = Completer<void>();
      final card = await _pump(t, auth);
      await t.tap(find.byKey(const ValueKey<String>('site_application_cancel')));
      await settleFor(t, 400);
      await t.tap(find.widgetWithText(ElevatedButton, 'Başvuruyu İptal Et'));
      await settleFor(t, 100);
      expect(auth.cancelCalls, <int>[7]);
      expect(find.text('İptal ediliyor...'), findsOneWidget);
      final button = t.widget<OutlinedButton>(find.byKey(const ValueKey<String>('site_application_cancel')));
      expect(button.onPressed, isNull, reason: 'istek sürerken ikinci dokunuş etkisiz');

      auth.cancelGate!.complete();
      await settleFor(t, 500);
      expect(auth.cancelCalls, <int>[7]);
      await _end(t, card);
    });

    testWidgets('iptal hatası: Türkçe hata kartta görünür, bekleyen kalır; ham istisna sızmaz', (t) async {
      final auth = _auth()
        ..seed([saRow(7)])
        ..cancelError = StateError('ham ayrıntı');
      final card = await _pump(t, auth);
      await t.tap(find.byKey(const ValueKey<String>('site_application_cancel')));
      await settleFor(t, 400);
      await t.tap(find.widgetWithText(ElevatedButton, 'Başvuruyu İptal Et'));
      await settleFor(t, 500);
      expect(find.text('Başvuru iptal edilemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.'), findsOneWidget);
      expect(find.textContaining('ham ayrıntı'), findsNothing);
      expect(find.text('Site başvurunuz inceleniyor'), findsOneWidget);
      await _end(t, card);
    });

    testWidgets('başka yerden karar verilmiş (409): mesaj + güncel durum görünür', (t) async {
      final auth = _auth()..seed([saRow(7)]);
      final card = await _pump(t, auth);
      auth.serverDecide(7, 'rejected', note: 'Eksik bilgi');
      await t.tap(find.byKey(const ValueKey<String>('site_application_cancel')));
      await settleFor(t, 400);
      await t.tap(find.widgetWithText(ElevatedButton, 'Başvuruyu İptal Et'));
      await settleFor(t, 500);
      expect(find.text('Site başvurunuz reddedildi'), findsOneWidget, reason: 'durum sunucudan yeniden okundu');
      expect(find.text('Gerekçe: Eksik bilgi'), findsOneWidget);
      await _end(t, card);
    });

    testWidgets('reddedildi: gerekçe, karar zamanı; Yeniden başvur geri çağrısı önceki başvuruyla; çift dokunuş tek çağrı', (t) async {
      final auth = _auth()
        ..seed([
          saRow(
            7,
            status: 'rejected',
            siteName: 'Gül Sitesi',
            decisionNote: 'Adres eksik',
            decidedAt: DateTime.utc(2026, 10, 16, 8),
          ),
        ]);
      final card = await _pump(t, auth);
      card.reapplyGate = Completer<void>();
      expect(find.text('Site başvurunuz reddedildi'), findsOneWidget);
      expect(find.text('Reddedildi'), findsOneWidget);
      expect(find.text('Gerekçe: Adres eksik'), findsOneWidget);
      expect(find.text('Karar: 16.10.2026 11:00'), findsOneWidget);

      final reapply = find.byKey(const ValueKey<String>('site_application_reapply'));
      await t.tap(reapply);
      await t.pump();
      expect(t.widget<ElevatedButton>(reapply).onPressed, isNull, reason: 'form açılırken ikinci dokunuş etkisiz');
      expect(card.reapplied, hasLength(1));
      expect(card.reapplied.single.id, 7);
      expect(card.reapplied.single.siteName, 'Gül Sitesi');
      card.reapplyGate!.complete();
      await t.pump();
      expect(t.widget<ElevatedButton>(reapply).onPressed, isNotNull);
      await _end(t, card);
    });

    testWidgets('reddedildi (panel varsayılanı): yeniden başvur düğmesi gizlenir, Anladım düğmesi kartı kapatır', (t) async {
      final auth = _auth()
        ..seed([
          saRow(
            7,
            status: 'rejected',
            siteName: 'Gül Sitesi',
            decisionNote: 'Adres eksik',
            decidedAt: DateTime.utc(2026, 10, 16, 8),
          ),
        ]);
      final card = await _pump(t, auth, showReapplyOnRejected: false);
      expect(find.text('Site başvurunuz reddedildi'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('site_application_reapply')), findsNothing,
          reason: 'panelde yeniden başvur düğmesi gösterilmez');
      final dismiss = find.byKey(const ValueKey<String>('site_application_dismiss_rejected'));
      expect(dismiss, findsOneWidget);
      await t.tap(dismiss);
      await t.pump();
      expect(find.text('Site başvurunuz reddedildi'), findsNothing, reason: 'kapatılınca kart kaybolur');
      expect(card.tracker.isRejectedConsumed(7), isTrue);
      await _end(t, card);
    });

    testWidgets('reddedildi, gerekçe yok: "Gerekçe belirtilmedi."', (t) async {
      final auth = _auth()..seed([saRow(7, status: 'rejected')]);
      final card = await _pump(t, auth);
      expect(find.text('Gerekçe belirtilmedi.'), findsOneWidget);
      await _end(t, card);
    });

    testWidgets('iptal edildi: kısa kart ve Yeniden başvur', (t) async {
      final auth = _auth()..seed([saRow(7, status: 'cancelled')]);
      final card = await _pump(t, auth);
      expect(find.text('Site başvurunuzu iptal ettiniz'), findsOneWidget);
      expect(find.text('İptal edildi'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey<String>('site_application_reapply')));
      await t.pump();
      expect(card.reapplied.single.id, 7);
      await _end(t, card);
    });

    testWidgets('onaylandı (yakın zamanda): Hesabı yenile; çok eski onay kartı çizilmez', (t) async {
      final auth = _auth()..seed([saRow(7, status: 'approved', decidedAt: DateTime.now())]);
      final card = await _pump(t, auth);
      expect(find.text('Site başvurunuz onaylandı'), findsOneWidget);
      card.accountGate = Completer<void>();
      final button = find.byKey(const ValueKey<String>('site_application_refresh_account'));
      await t.tap(button);
      await t.pump();
      expect(card.accountRefreshes, 1);
      expect(t.widget<OutlinedButton>(button).onPressed, isNull, reason: 'yenileme sürerken kilitli');
      card.accountGate!.complete();
      await t.pump();
      await _end(t, card);

      final old = _auth()
        ..seed([saRow(8, status: 'approved', decidedAt: DateTime.now().subtract(const Duration(days: 10)))]);
      final oldCard = await _pump(t, old);
      expect(find.text('Site başvurunuz onaylandı'), findsNothing);
      await _end(t, oldCard);
    });

    testWidgets('onaylandı, hesap yenileme eylemi verilmemişse düğme yok', (t) async {
      final auth = _auth()..seed([saRow(7, status: 'approved', decidedAt: DateTime.now())]);
      final card = await _pump(t, auth, withAccountRefresh: false);
      expect(find.text('Site başvurunuz onaylandı'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('site_application_refresh_account')), findsNothing);
      await _end(t, card);
    });
  });

  group('hata dürüstlüğü', () {
    testWidgets('durum alınamadı: "başvuru yok" DEĞİL, hata + Tekrar Dene; sonra düzelir', (t) async {
      final auth = _auth()
        ..seed([saRow(7)])
        ..mineError = ApiException('Sunucu yanıt vermedi, tekrar deneyin.');
      final card = await _pump(t, auth);
      expect(find.text('Sunucu yanıt vermedi, tekrar deneyin.'), findsOneWidget);
      expect(find.text('Site başvurunuz inceleniyor'), findsNothing);
      expect(find.text('Tekrar Dene'), findsOneWidget);

      auth.mineError = null;
      await t.tap(find.text('Tekrar Dene'));
      await settleFor(t, 100);
      expect(find.text('Site başvurunuz inceleniyor'), findsOneWidget);
      expect(find.text('Sunucu yanıt vermedi, tekrar deneyin.'), findsNothing);
      await _end(t, card);
    });

    testWidgets('bekleyen varken yoklama hatası kartı SİLMEZ; uyarı + Tekrar Dene görünür', (t) async {
      final auth = _auth()..seed([saRow(7)]);
      final card = await _pump(t, auth);
      auth.mineError = ApiException('Bağlantı yok.');
      await t.pump(const Duration(seconds: 31));
      await t.pump();
      expect(find.text('Site başvurunuz inceleniyor'), findsOneWidget);
      expect(find.textContaining('Bağlantı yok.'), findsOneWidget);
      expect(find.textContaining('Gösterilen başvuru bilgisi eski olabilir'), findsOneWidget);
      expect(find.text('Tekrar Dene'), findsOneWidget);
      await _end(t, card);
    });

    // B2: hata her durumda dürüstçe görünür (yalnız bekleyen kartta değil).
    for (final status in const ['rejected', 'cancelled']) {
      testWidgets('B2: önceki veri ($status kartı) varken yenileme hatası -> kartın üstünde "Tekrar Dene" uyarısı', (t) async {
        final auth = _auth()..seed([saRow(7, status: status, decisionNote: 'Eksik')]);
        final card = await _pump(t, auth);
        expect(find.text('Tekrar Dene'), findsNothing);
        auth.mineError = ApiException('Bağlantı yok.');
        await card.tracker.refresh();
        await t.pump();
        expect(find.textContaining('Bağlantı yok.'), findsOneWidget);
        expect(find.text('Tekrar Dene'), findsOneWidget);
        expect(find.byKey(const ValueKey<String>('site_application_reapply')), findsOneWidget, reason: 'kart silinmez');

        auth.mineError = null;
        await t.tap(find.text('Tekrar Dene'));
        await settleFor(t, 100);
        expect(find.text('Tekrar Dene'), findsNothing);
        await _end(t, card);
      });
    }

    testWidgets('B2: başvuru yokken (boş durum) yenileme hatası da görünür: sessiz kalmaz', (t) async {
      final auth = _auth();
      final card = await _pump(t, auth);
      auth.mineError = ApiException('Bağlantı yok.');
      await card.tracker.refresh();
      await t.pump();
      expect(find.textContaining('Bağlantı yok.'), findsOneWidget);
      expect(find.text('Tekrar Dene'), findsOneWidget);
      await _end(t, card);
    });

    testWidgets('B2: başvuru gönderildi ama durum yenilenemedi -> "alındı, durum yenilenemedi" bilgisi, yeniden deneme sürer', (t) async {
      final auth = _auth();
      final card = await _pump(t, auth);
      auth.mineError = ApiException('Bağlantı yok.');
      await card.tracker.noteSubmitted();
      await t.pump();
      expect(find.textContaining('Başvurunuz alındı, ancak durum yenilenemedi'), findsOneWidget);
      expect(find.text('Tekrar Dene'), findsOneWidget);
      expect(card.tracker.isPolling, isTrue);

      auth.mineError = null;
      auth.seed([saRow(7)]);
      await t.pump(const Duration(seconds: 61));
      await t.pump();
      expect(find.text('Site başvurunuz inceleniyor'), findsOneWidget);
      expect(find.textContaining('durum yenilenemedi'), findsNothing);
      await _end(t, card);
    });

    testWidgets('B2: gönderim sonrası doğrulama sürerken "durum kontrol ediliyor" bilgisi (liveRegion bildirimi)', (t) async {
      final auth = _auth()..seed([saRow(7)]);
      final card = await _pump(t, auth);
      final gate = Completer<void>();
      auth.mineGates.add(gate);
      unawaited(card.tracker.noteSubmitted());
      await t.pump();
      expect(find.textContaining('Başvuru durumu kontrol ediliyor'), findsOneWidget);
      gate.complete();
      await t.pump();
      await t.pump();
      expect(find.textContaining('kontrol ediliyor'), findsNothing);
      await _end(t, card);
    });

    testWidgets('B17: tanınmayan / eksik durum -> kısıtlı kart, HİÇBİR eylem yok, ham kod yok', (t) async {
      final auth = _auth()
        ..seed([
          <String, dynamic>{...saRow(7), 'status': 'on_hold'},
        ]);
      final card = await _pump(t, auth);
      expect(find.text('Site başvurunuz'), findsOneWidget);
      expect(find.text('Durum bilinmiyor'), findsOneWidget);
      expect(find.textContaining('on_hold'), findsNothing);
      expect(find.byKey(const ValueKey<String>('site_application_cancel')), findsNothing);
      expect(find.byKey(const ValueKey<String>('site_application_reapply')), findsNothing);
      expect(find.byKey(const ValueKey<String>('site_application_refresh_account')), findsNothing);
      expect(card.tracker.pending, isNull, reason: 'bekleyen sayılmadı');
      await _end(t, card);
    });

    testWidgets('B18: yönetici panosunda (showApproved: false) onaylı kart görünmez', (t) async {
      final auth = _auth()..seed([saRow(7, status: 'approved', decidedAt: DateTime.now())]);
      final card = await _pump(t, auth, showApproved: false);
      expect(find.text('Site başvurunuz onaylandı'), findsNothing);
      await _end(t, card);
    });

    testWidgets('B18: onay tüketildi (yenileme sonrası rol hâlâ başvuran) -> kart KALKAR', (t) async {
      final auth = _auth()..seed([saRow(7, status: 'approved', decidedAt: DateTime.now())]);
      final card = await _pump(t, auth);
      expect(find.text('Site başvurunuz onaylandı'), findsOneWidget);
      card.tracker.consumeApproval(7);
      await t.pump();
      expect(find.text('Site başvurunuz onaylandı'), findsNothing);
      expect(find.byKey(const ValueKey<String>('site_application_refresh_account')), findsNothing);
      await _end(t, card);
    });

    testWidgets('showLoadFailure: false (yönetici panosu) durum HİÇ alınamazsa sessiz kalır; veri varken uyarı yine görünür', (t) async {
      final auth = _auth()..mineError = ApiException('Bağlantı yok.');
      final card = await _pump(t, auth, showLoadFailure: false);
      expect(find.textContaining('Bağlantı yok.'), findsNothing);
      auth.mineError = null;
      auth.seed([saRow(7)]);
      await card.tracker.refresh();
      await t.pump();
      expect(find.text('Site başvurunuz inceleniyor'), findsOneWidget);
      auth.mineError = ApiException('Bağlantı yok.');
      await card.tracker.refresh();
      await t.pump();
      expect(find.textContaining('Bağlantı yok.'), findsOneWidget);
      await _end(t, card);
    });

    testWidgets('B6: iptal sonrası odak yeni kartın başlığına taşınır ve iptal DUYURULUR', (t) async {
      final announced = captureAnnouncements(t);
      final auth = _auth()..seed([saRow(7)]);
      final card = await _pump(t, auth);
      await t.tap(find.byKey(const ValueKey<String>('site_application_cancel')));
      await settleFor(t, 400);
      await t.tap(find.widgetWithText(ElevatedButton, 'Başvuruyu İptal Et'));
      await settleFor(t, 600);
      expect(find.text('Site başvurunuzu iptal ettiniz'), findsOneWidget);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'site_application_card_title');
      expect(announced, contains('Başvurunuz iptal edildi.'));
      await _end(t, card);
    });

    testWidgets('B6: "Hesabı yenile" meşgulken etiket "Hesap yenileniyor..." olur (canlı bölge)', (t) async {
      final auth = _auth()..seed([saRow(7, status: 'approved', decidedAt: DateTime.now())]);
      final card = await _pump(t, auth);
      card.accountGate = Completer<void>();
      await t.tap(find.byKey(const ValueKey<String>('site_application_refresh_account')));
      await t.pump();
      expect(find.text('Hesap yenileniyor...'), findsOneWidget);
      expect(find.text('Hesabı yenile'), findsNothing);
      card.accountGate!.complete();
      await t.pump();
      expect(find.text('Hesabı yenile'), findsOneWidget);
      await _end(t, card);
    });

    testWidgets('yoklama: bekleyen onaylanınca kart kendiliğinden "onaylandı"ya döner (sayfa yenilenmeden)', (t) async {
      final auth = _auth()..seed([saRow(7)]);
      final card = await _pump(t, auth);
      expect(find.text('Site başvurunuz inceleniyor'), findsOneWidget);
      auth.serverDecide(7, 'approved');
      await t.pump(const Duration(seconds: 31));
      await t.pump();
      expect(find.text('Site başvurunuz onaylandı'), findsOneWidget);
      expect(card.tracker.isPolling, isFalse);
      await _end(t, card);
    });
  });
}
