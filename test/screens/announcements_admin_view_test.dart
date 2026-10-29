// Platform Faz 3a: yönetici "Duyurular" ekranı (AnnouncementsAdminView) ve ayrıntı penceresi.
//
// AGENTS.md kural 6: 320x640 x2,0 ve 360x640 x1,5, açık + koyu tema; yükleniyor / boş / hata / dolu durumlar
// taşmaz. Kural 7: yenile düğmesi ve `reload()` (aşağı çekip yenileme) çalışır; işlem sonrası liste otomatik
// yenilenir. Yarış korumaları: art arda arama, süzgeç değişimi, site değişimi, çift dokunuş. Kurul üyesi
// SALT OKUNUR: yazma düğmesi ve alıcı adları yok, alıcı ve önizleme uçları hiç çağrılmaz.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsAction;
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/announcement.dart';
import 'package:site_kapi_kontrol/models/site_record.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart' show InlineNotice;
import 'package:site_kapi_kontrol/ui/design/buttons.dart' show PrimaryActionButton;
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/dialogs/announcement_form_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/announcement_manage_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/views/announcements_admin_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/announcement_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

import 'announcement_fixtures.dart';
import 'dialog_layout_harness.dart' show settleFor;
import 'list_fixtures.dart';
import 'people_fixtures.dart';

Future<GlobalKey<AnnouncementsAdminViewState>> _pump(
  WidgetTester t,
  AnnouncementFakeAuth auth, {
  double width = 400,
  double height = 1600,
  double scale = 1.0,
  bool dark = false,
  bool manage = true,
  List<PeopleSite> readOnly = const <PeopleSite>[],
}) async {
  final key = GlobalKey<AnnouncementsAdminViewState>();
  await pumpList(
    t,
    AnnouncementsAdminView(
      key: key,
      authService: auth,
      manageSites: manage,
      readOnlySites: readOnly,
    ),
    width: width,
    height: height,
    scale: scale,
    dark: dark,
  );
  // Önce siteler gelir, liste sonra kurulur ve kendi verisini çeker: iki aşama.
  await settleFor(t, 100);
  await settleFor(t, 100);
  return key;
}

Finder _card(String title) => find.widgetWithText(AnnouncementAdminCard, title);

Future<void> _open(WidgetTester t, String title) async {
  await tapFinder(t, _card(title));
  await settleFor(t);
}

Finder _inDialog(Finder f) => find.descendant(of: find.byType(AlertDialog), matching: f);

Finder _chip(String label) => find.widgetWithText(StatusChip, label);

/// En üstteki (onay) penceredeki düğmeye dokunur; arkadaki ayrıntı penceresinin aynı adlı düğmesine değil.
Future<void> _confirm(WidgetTester t, String label) async {
  final button = find.descendant(
    of: find.byType(AlertDialog).last,
    matching: find.text(label),
  );
  await tapFinder(t, button);
  await settleFor(t);
}

Future<void> _type(WidgetTester t, String key, String text) async {
  final field = find.byKey(ValueKey<String>(key));
  await t.ensureVisible(field);
  await t.pump();
  await t.enterText(field, text);
  await t.pump();
}

Future<void> _debounce(WidgetTester t) async {
  await t.pump(const Duration(milliseconds: 400));
  await t.pump();
}

/// 5 yayınlanmış duyuru (sayfalama testleri için).
AnnouncementFakeAuth _many({int count = 5}) {
  final auth = AnnouncementFakeAuth();
  for (var i = 1; i <= count; i++) {
    auth.rows[i] = annRow(
      i,
      title: 'Duyuru $i',
      publishedAt: DateTime.utc(2026, 10, 1).add(Duration(hours: i)),
    );
  }
  return auth;
}

const List<PeopleSite> _board = <PeopleSite>[PeopleSite(code: 12, name: 'Mavi Park')];

void main() {
  group('taşma matrisi', () {
    listMatrix('liste: dolu görünüm (durum rozeti, acil işareti, okunma, e-posta, hedef)', (t, w, h, s, dark) async {
      final auth = AnnouncementFakeAuth.seeded();
      await _pump(t, auth, width: w, height: h, scale: s, dark: dark);

      expect(find.byType(AnnouncementAdminCard), findsNWidgets(4));
      // Sıra: taslak / zamanlanmış üstte, sonra yayın zamanına göre yeni -> eski.
      final order = [
        for (final card in t.widgetList<AnnouncementAdminCard>(find.byType(AnnouncementAdminCard)))
          card.announcement.id,
      ];
      expect(order, <int>[40, 39, 41, 38]);
      expect(find.text('Asansör bakımı'), findsOneWidget);
      expect(_chip('Yayında'), findsOneWidget);
      expect(_chip('Taslak'), findsOneWidget);
      expect(_chip('Zamanlanmış'), findsOneWidget);
      expect(_chip('Geri çekildi'), findsOneWidget);
      expect(_chip('Acil'), findsOneWidget);
      expect(find.text('Okunma: 1/3'), findsNWidgets(2), reason: 'yayında ve geri çekilmiş duyuru');
      expect(find.text('Okunma: 0/0'), findsNothing, reason: 'taslakta okunma sayısı gösterilmez');
      expect(find.text('E-posta da gönderilir'), findsOneWidget);
      expect(find.text('Hedef: Tüm site'), findsNWidgets(3));
      expect(find.text('Hedef: Bloklar'), findsOneWidget);
      expect(find.text('Yayınlandı: 16.10.2026 00:30'), findsOneWidget, reason: '21:30 UTC = 00:30 İstanbul');
      expect(find.text('Yayın zamanı: 20.11.2026 14:30'), findsOneWidget);
      expect(find.text('Yeni Duyuru'), findsOneWidget);
      expect(find.text('Duyuru ara'), findsOneWidget);
      for (final label in const ['Hepsi', 'Taslak', 'Zamanlanmış', 'Yayında', 'Geri çekildi']) {
        expect(find.widgetWithText(ChoiceChip, label), findsOneWidget, reason: label);
      }
      expect(find.byTooltip('Yenile'), findsOneWidget);
    });

    listMatrix('liste: yükleniyor', (t, w, h, s, dark) async {
      final auth = AnnouncementFakeAuth.seeded()..announcementListGates.add(Completer<void>());
      await _pump(t, auth, width: w, height: h, scale: s, dark: dark);
      expect(find.byType(ListSkeleton), findsOneWidget);
      expect(find.byType(AnnouncementAdminCard), findsNothing);
      expect(find.text('Henüz duyuru yok.'), findsNothing);
    });

    listMatrix('liste: boş', (t, w, h, s, dark) async {
      await _pump(t, AnnouncementFakeAuth(), width: w, height: h, scale: s, dark: dark);
      expect(find.byType(EmptyCard), findsOneWidget);
      expect(find.text('Henüz duyuru yok.'), findsOneWidget);
      expect(find.text('Yeni Duyuru ile sakinlere ilk duyuruyu gönderebilirsiniz.'), findsOneWidget);
    });

    listMatrix('liste: hata (InlineNotice + Tekrar Dene), "duyuru yok" yazmaz', (t, w, h, s, dark) async {
      final auth = AnnouncementFakeAuth.seeded()
        ..announcementListError = ApiException('Bu işlem için yetkiniz yok.', statusCode: 403, code: 'FORBIDDEN_ROLE');
      await _pump(t, auth, width: w, height: h, scale: s, dark: dark);
      expect(find.byType(InlineNotice), findsOneWidget);
      expect(find.text('Bu işlem için yetkiniz yok.'), findsOneWidget);
      expect(find.text('Tekrar Dene'), findsOneWidget);
      expect(find.text('Henüz duyuru yok.'), findsNothing);
      expect(find.byType(AnnouncementAdminCard), findsNothing);
    });

    listMatrix('çok uzun tek sözcüklü başlık / metin / etiket: kart, ayrıntı ve düzenleme formu taşmaz', (t, w, h, s, dark) async {
      final auth = AnnouncementFakeAuth()
        ..rows[60] = annRow(
          60,
          title: 'U' * 118,
          body: 'V' * 900,
          importance: 'urgent',
          sendEmail: true,
          targetType: 'blocks',
          blockIds: const <int>[1, 2],
          labels: <String>['Çok Uzun İsimli Güzelyalı Yeşilvadi Konutları A Blok', 'B' * 80],
          editedAt: DateTime.utc(2026, 10, 16, 6),
        );
      await _pump(t, auth, width: w, height: h, scale: s, dark: dark);
      expect(find.byType(AnnouncementAdminCard), findsOneWidget);
      // Kart ekrandan yüksek olabilir (uzun tek sözcük): üst kenarına yakın bir noktaya dokunulur.
      await t.ensureVisible(find.byType(AnnouncementAdminCard));
      await t.pump();
      await t.tapAt(t.getTopLeft(find.byType(AnnouncementAdminCard)) + const Offset(24, 24));
      await t.pump();
      await settleFor(t);
      expect(find.byType(AlertDialog), findsOneWidget);
      await tapFinder(t, find.byKey(const ValueKey<String>('announcement_action_edit')));
      await settleFor(t);
      expect(find.byType(AnnouncementFormDialog), findsOneWidget);
    });

    listMatrix('kurul üyesi: HİÇBİR yazma düğmesi yok, salt okunur bilgi bandı var', (t, w, h, s, dark) async {
      final auth = AnnouncementFakeAuth.seeded(role: UserRole.apartmentOwner)..boardReadOnly = true;
      await _pump(
        t,
        auth,
        width: w,
        height: h,
        scale: s,
        dark: dark,
        manage: false,
        readOnly: const <PeopleSite>[PeopleSite(code: 11, name: 'Gül Sitesi')],
      );
      expect(find.byType(AnnouncementAdminCard), findsNWidgets(4));
      expect(find.text('Yeni Duyuru'), findsNothing);
      expect(
        find.text('Yönetim kurulu üyesi olarak duyuruları yalnızca görüntüleyebilirsiniz. Alıcı adları görünmez.'),
        findsOneWidget,
      );
      expect(auth.listSitesCalls, 0, reason: 'kurul üyesi yönetim site listesini çağırmaz');
    });

    listMatrix('ayrıntı penceresi: yayınlanmış duyuru (okunma, e-posta özeti, eylemler)', (t, w, h, s, dark) async {
      final auth = AnnouncementFakeAuth.seeded();
      await _pump(t, auth, width: w, height: h, scale: s, dark: dark);
      await _open(t, 'Asansör bakımı');

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(_inDialog(find.text('Yarın 10:00-12:00 arası asansör hizmet vermeyecek.')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('announcement_read_ratio')), findsOneWidget);
      expect(find.text('1/3 kişi okudu'), findsOneWidget);
      expect(find.text('Düzenlendi: 16.10.2026 09:00'), findsOneWidget, reason: '06:00 UTC = 09:00 İstanbul');
      expect(find.byKey(const ValueKey<String>('announcement_email_summary')), findsOneWidget);
      expect(find.text('1 gönderildi'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('announcement_action_edit')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('announcement_action_withdraw')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('announcement_action_publish')), findsNothing);
      expect(find.byKey(const ValueKey<String>('announcement_action_delete')), findsOneWidget, reason: 'yayındaki duyuru da silinebilir (yumuşak)');
      expect(find.text('Alıcılar'), findsOneWidget);
    });
  });

  group('süzgeç, arama, sayfalama', () {
    testWidgets('durum süzgeci sorguya yazılır ve listeyi daraltır; aynı süzgeç tekrar seçilince istek yok', (t) async {
      final auth = AnnouncementFakeAuth.seeded();
      await _pump(t, auth);
      expect(auth.announcementListCalls.single.status, 'all');

      await tapFinder(t, find.byKey(const ValueKey<String>('announcement_filter_published')));
      await settleFor(t);
      expect(auth.announcementListCalls.last.status, 'published');
      expect(find.byType(AnnouncementAdminCard), findsOneWidget);
      expect(find.text('Asansör bakımı'), findsOneWidget);

      final calls = auth.announcementListCalls.length;
      await tapFinder(t, find.byKey(const ValueKey<String>('announcement_filter_published')));
      await settleFor(t);
      expect(auth.announcementListCalls.length, calls);

      await tapFinder(t, find.byKey(const ValueKey<String>('announcement_filter_draft')));
      await settleFor(t);
      expect(find.byType(AnnouncementAdminCard), findsOneWidget);
      expect(find.text('Aidat hatırlatması'), findsOneWidget);
    });

    testWidgets('arama duraksayınca çalışır; boş sonuç "kayıt yok" değil süzgeç mesajı yazar', (t) async {
      final auth = AnnouncementFakeAuth.seeded();
      await _pump(t, auth);
      await _type(t, 'announcements_search', 'bahçe');
      expect(auth.announcementListCalls.length, 1, reason: 'gecikme dolmadan istek yok');
      await _debounce(t);
      await settleFor(t);
      expect(auth.announcementListCalls.last.query, 'bahçe');
      expect(find.byType(AnnouncementAdminCard), findsOneWidget);
      expect(find.text('Bahçe düzenlemesi'), findsOneWidget);

      await _type(t, 'announcements_search', 'yok böyle bir şey');
      await _debounce(t);
      await settleFor(t);
      expect(find.text('Bu arama ve süzgeç için duyuru bulunamadı.'), findsOneWidget);
      expect(find.text('Henüz duyuru yok.'), findsNothing);

      await tapFinder(t, find.byTooltip('Aramayı temizle'));
      await settleFor(t);
      expect(find.byType(AnnouncementAdminCard), findsNWidgets(4));
    });

    testWidgets('hızlı art arda aramada eski yanıt yenisini ezmez', (t) async {
      final auth = AnnouncementFakeAuth.seeded();
      await _pump(t, auth);
      final slow = Completer<void>();
      auth.announcementListGates
        ..add(slow) // ilk arama (yavaş)
        ..add(Completer<void>()..complete()); // ikinci arama (hızlı)
      await _type(t, 'announcements_search', 'asansör');
      await _debounce(t);
      await _type(t, 'announcements_search', 'bahçe');
      await _debounce(t);
      await settleFor(t);
      expect(find.text('Bahçe düzenlemesi'), findsOneWidget);

      slow.complete(); // eski yanıt şimdi gelir
      await settleFor(t);
      expect(find.text('Bahçe düzenlemesi'), findsOneWidget);
      expect(find.text('Asansör bakımı'), findsNothing, reason: 'eski aramanın sonucu yenisini ezmedi');
    });

    testWidgets('sayfalama: "Daha fazla yükle" sonraki sayfayı ekler; toplam sayaçta görünür', (t) async {
      final auth = _many(count: 5)..maxPage = 2;
      await _pump(t, auth);
      expect(find.byType(AnnouncementAdminCard), findsNWidgets(2));
      expect(find.text('Daha fazla yükle'), findsOneWidget);

      await tapText(t, 'Daha fazla yükle');
      await settleFor(t);
      expect(find.byType(AnnouncementAdminCard), findsNWidgets(4));
      expect(auth.announcementListCalls.last.offset, 2);
      await tapText(t, 'Daha fazla yükle');
      await settleFor(t);
      expect(find.byType(AnnouncementAdminCard), findsNWidgets(5));
      expect(find.text('Daha fazla yükle'), findsNothing);
    });

    testWidgets('yenile düğmesi ve reload() listeyi yeniden çeker', (t) async {
      final auth = AnnouncementFakeAuth.seeded();
      final key = await _pump(t, auth);
      final before = auth.announcementListCalls.length;
      auth.rows[50] = annRow(50, title: 'Sonradan eklendi', status: 'draft');

      await tapFinder(t, find.byTooltip('Yenile'));
      await settleFor(t);
      expect(auth.announcementListCalls.length, before + 1);
      expect(find.text('Sonradan eklendi'), findsOneWidget);

      auth.rows[51] = annRow(51, title: 'Çekip yenilenen', status: 'draft');
      await key.currentState!.reload();
      await settleFor(t);
      expect(find.text('Çekip yenilenen'), findsOneWidget);
    });

    testWidgets('yenileme hatası mevcut listeyi silmez; "Tekrar Dene" ile düzelir', (t) async {
      final auth = AnnouncementFakeAuth.seeded();
      await _pump(t, auth);
      auth.announcementListError = ApiException('Sunucu yanıt vermedi, tekrar deneyin.');
      await tapFinder(t, find.byTooltip('Yenile'));
      await settleFor(t);
      expect(find.text('Sunucu yanıt vermedi, tekrar deneyin.'), findsOneWidget);
      expect(find.byType(AnnouncementAdminCard), findsNWidgets(4), reason: 'eski liste korunur');

      auth.announcementListError = null;
      await tapText(t, 'Tekrar Dene');
      await settleFor(t);
      expect(find.text('Sunucu yanıt vermedi, tekrar deneyin.'), findsNothing);
    });
  });

  group('site seçimi', () {
    testWidgets('tek sitede açılır liste yerine site çipi; site yoksa "Kayıtlı site bulunamadı."', (t) async {
      await _pump(t, AnnouncementFakeAuth.seeded());
      expect(find.text('Site'), findsNothing);
      expect(find.text('Gül Sitesi'), findsWidgets);
      await _pump(t, AnnouncementFakeAuth(sites: const []));
      expect(find.text('Kayıtlı site bulunamadı.'), findsOneWidget);
    });

    testWidgets('site değişince eski sitenin yavaş yanıtı yeni sitenin ekranına yazılamaz', (t) async {
      final auth = AnnouncementFakeAuth.seeded()
        ..sites = <SiteRecord>[pplSite(11, 'Gül Sitesi'), pplSite(12, 'Mavi Park')];
      await _pump(t, auth);
      expect(find.byType(AnnouncementAdminCard), findsNWidgets(4));
      expect(find.text('Site'), findsOneWidget);

      // Gül Sitesi listesi yeniden çekiliyor (yanıt yavaş: istek anındaki 4 duyuruyu taşır)...
      final slow = Completer<void>();
      auth.announcementListGates.add(slow);
      await tapFinder(t, find.byTooltip('Yenile'));
      await settleFor(t);

      // ... kullanıcı bu arada Mavi Park'a geçer.
      auth.rows
        ..clear()
        ..[90] = annRow(90, title: 'Mavi Park duyurusu', status: 'draft');
      await t.ensureVisible(find.byType(DropdownButtonFormField<int>));
      await t.tap(find.byType(DropdownButtonFormField<int>));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      // G18d: seçicide yalnız site ADI görünür; site kodu "(12)" yazılmaz.
      expect(find.textContaining('(12)'), findsNothing);
      expect(find.textContaining('(11)'), findsNothing);
      await t.tap(find.text('Mavi Park').last);
      await t.pump();
      await t.pump(const Duration(milliseconds: 450));
      await settleFor(t);
      expect(auth.announcementListCalls.last.site, 12);
      expect(find.text('Mavi Park duyurusu'), findsOneWidget);

      slow.complete();
      await settleFor(t);
      expect(find.text('Asansör bakımı'), findsNothing, reason: 'eski sitenin geç yanıtı yeni ekrana yazılamaz');
      expect(find.byType(AnnouncementAdminCard), findsOneWidget);
      expect(find.text('Mavi Park duyurusu'), findsOneWidget);
    });
  });

  group('site seçici etiketi (G18d)', () {
    testWidgets('aynı adlı siteler sıra numarasıyla ayrılır; site kodu hiçbir yerde yazılmaz', (t) async {
      final auth = AnnouncementFakeAuth.seeded()
        ..sites = <SiteRecord>[pplSite(11, 'Gül Sitesi'), pplSite(12, 'Gül Sitesi'), pplSite(13, 'Mavi Park')];
      await _pump(t, auth);
      expect(find.text('Gül Sitesi (1)'), findsWidgets);
      await t.tap(find.byType(DropdownButtonFormField<int>));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('Gül Sitesi (1)'), findsWidgets);
      expect(find.text('Gül Sitesi (2)'), findsOneWidget);
      expect(find.text('Mavi Park'), findsOneWidget);
      for (final code in const ['(11)', '(12)', '(13)']) {
        expect(find.text('Gül Sitesi $code'), findsNothing, reason: code);
        expect(find.text('Mavi Park $code'), findsNothing, reason: code);
      }
    });
  });

  group('ayrıntı penceresi', () {
    testWidgets('yükleniyor iskeleti, hata + Tekrar Dene (boş pencere çizilmez)', (t) async {
      final auth = AnnouncementFakeAuth.seeded()..announcementDetailGate = Completer<void>();
      await _pump(t, auth);
      await tapFinder(t, _card('Asansör bakımı'));
      await settleFor(t);
      expect(find.text('Duyuru yükleniyor...'), findsOneWidget);
      auth
        ..announcementDetailGate!.complete()
        ..announcementDetailGate = null;
      await settleFor(t);
      expect(find.text('Duyuru yükleniyor...'), findsNothing);

      // Hata: ayrıntı alınamıyor.
      await tapText(t, 'Kapat');
      auth.announcementDetailError = ApiException('Duyuru yüklenemedi (deneme).');
      await _open(t, 'Asansör bakımı');
      expect(find.text('Duyuru yüklenemedi (deneme).'), findsOneWidget);
      expect(find.text('Tekrar Dene'), findsOneWidget);
      expect(find.text('Metin'), findsNothing);
      auth.announcementDetailError = null;
      await tapText(t, 'Tekrar Dene');
      await settleFor(t);
      expect(find.text('Metin'), findsOneWidget);
    });

    testWidgets('alıcılar sekmesi: Okumayanlar varsayılan; Okuyanlar, arama ve hesabı olmayan kişi', (t) async {
      final auth = AnnouncementFakeAuth.seeded();
      await _pump(t, auth);
      await _open(t, 'Asansör bakımı');
      expect(auth.recipientCalls, isEmpty, reason: 'sekme açılmadan alıcılar çekilmez');

      await tapFinder(t, find.byKey(const ValueKey<String>('announcement_tab_recipients')));
      await settleFor(t);
      expect(auth.recipientCalls.single.read, 'false');
      expect(find.text('Okumayanlar (2)'), findsOneWidget);
      expect(find.text('Okuyanlar (1)'), findsOneWidget);
      expect(find.text('Mehmet Demir'), findsOneWidget);
      expect(find.text('Zeynep Kaya'), findsOneWidget);
      expect(find.text('Hesabı yok'), findsOneWidget);
      expect(find.text('Hesabı olmadığı için uygulamada göremez'), findsOneWidget);
      expect(find.text('Ayşe Yılmaz'), findsNothing);

      await tapFinder(t, find.byKey(const ValueKey<String>('recipients_read')));
      await settleFor(t);
      expect(auth.recipientCalls.last.read, 'true');
      expect(find.text('Ayşe Yılmaz'), findsOneWidget);
      expect(find.text('Okudu: 16.10.2026 08:15'), findsOneWidget, reason: '05:15 UTC = 08:15 İstanbul');
      expect(find.text('E-posta gönderildi'), findsOneWidget);

      await tapFinder(t, find.byKey(const ValueKey<String>('recipients_unread')));
      await settleFor(t);
      await _type(t, 'recipients_search', 'zeynep');
      await _debounce(t);
      await settleFor(t);
      expect(auth.recipientCalls.last.query, 'zeynep');
      expect(find.text('Zeynep Kaya'), findsOneWidget);
      expect(find.text('Mehmet Demir'), findsNothing);
    });

    testWidgets('alıcılar hatası "alıcı yok" demez; Tekrar Dene ile düzelir', (t) async {
      final auth = AnnouncementFakeAuth.seeded()..recipientsError = ApiException('Alıcılar şu an alınamadı.');
      await _pump(t, auth);
      await _open(t, 'Asansör bakımı');
      await tapFinder(t, find.byKey(const ValueKey<String>('announcement_tab_recipients')));
      await settleFor(t);
      expect(find.text('Alıcılar şu an alınamadı.'), findsOneWidget);
      expect(find.text('Okumayan alıcı yok.'), findsNothing);
      auth.recipientsError = null;
      await tapText(t, 'Tekrar Dene');
      await settleFor(t);
      expect(find.text('Mehmet Demir'), findsOneWidget);
    });

    testWidgets('taslakta alıcılar sekmesi yok; Düzenle / Şimdi Yayınla / Sil var, Geri Çek yok', (t) async {
      final auth = AnnouncementFakeAuth.seeded();
      await _pump(t, auth);
      await _open(t, 'Aidat hatırlatması');
      expect(find.byKey(const ValueKey<String>('announcement_tab_recipients')), findsNothing);
      expect(find.byKey(const ValueKey<String>('announcement_action_edit')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('announcement_action_publish')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('announcement_action_delete')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('announcement_action_withdraw')), findsNothing);
      expect(find.text('Taslak, henüz yayınlanmadı.'), findsOneWidget);
    });

    testWidgets('geri çekilmiş duyuruda yalnız Sil var (yumuşak silme metni)', (t) async {
      final auth = AnnouncementFakeAuth.seeded();
      await _pump(t, auth);
      await _open(t, 'Yanlış duyuru');
      expect(find.byKey(const ValueKey<String>('announcement_action_edit')), findsNothing);
      expect(find.byKey(const ValueKey<String>('announcement_action_publish')), findsNothing);
      expect(find.byKey(const ValueKey<String>('announcement_action_withdraw')), findsNothing);
      expect(find.byKey(const ValueKey<String>('announcement_action_delete')), findsOneWidget);
      expect(find.textContaining('Geri çekildi (yayın zamanı:'), findsOneWidget);
      await tapFinder(t, find.byKey(const ValueKey<String>('announcement_action_delete')));
      await settleFor(t);
      expect(find.textContaining('yasal saklama süresince saklanır'), findsOneWidget);
    });

    testWidgets('zamanlanmış duyuruda yayın zamanı İstanbul saatiyle yazılır', (t) async {
      final auth = AnnouncementFakeAuth.seeded();
      await _pump(t, auth);
      await _open(t, 'Bahçe düzenlemesi');
      expect(find.text('Zamanlanmış: 20.11.2026 14:30 (İstanbul saati)'), findsOneWidget);
    });
  });

  group('eylemler', () {
    testWidgets('Şimdi Yayınla: kitle önizlemesi + onay; vazgeçilirse yayınlanmaz, onaylanırsa yayınlanır', (t) async {
      final auth = AnnouncementFakeAuth.seeded();
      await _pump(t, auth);
      await _open(t, 'Aidat hatırlatması');

      await tapFinder(t, find.byKey(const ValueKey<String>('announcement_action_publish')));
      await settleFor(t);
      expect(auth.previewCalls.single.target, <String, dynamic>{
        'type': 'blocks',
        'block_ids': <int>[1],
      });
      expect(find.text('48 kişiye ulaşır'), findsOneWidget);
      expect(find.text('Yayını onayla'), findsOneWidget);

      await tapText(t, 'Vazgeç');
      await settleFor(t);
      expect(auth.announcementPublishCalls, isEmpty);
      expect(auth.rows[40]!['status'], 'draft');

      await tapFinder(t, find.byKey(const ValueKey<String>('announcement_action_publish')));
      await settleFor(t);
      await tapText(t, 'Yayınla');
      await settleFor(t);
      expect(auth.announcementPublishCalls, <int>[40]);
      expect(auth.rows[40]!['status'], 'published');
      expect(find.text('Duyuru yayınlandı. 3 kişiye ulaştı.'), findsOneWidget);
      expect(_chip('Yayında'), findsWidgets);
      expect(find.byKey(const ValueKey<String>('announcement_action_withdraw')), findsOneWidget);
    });

    testWidgets('Şimdi Yayınla: kitle yoksa yayınlanmaz, açıklayıcı mesaj gösterilir', (t) async {
      final auth = AnnouncementFakeAuth.seeded()
        ..audience = <String, dynamic>{
          'people': 0,
          'apartments': 0,
          'with_account': 0,
          'with_email': 0,
          'without_email': 0,
        }
        ..audienceRecipients = <Map<String, dynamic>>[];
      await _pump(t, auth);
      await _open(t, 'Aidat hatırlatması');
      await tapFinder(t, find.byKey(const ValueKey<String>('announcement_action_publish')));
      await settleFor(t);
      expect(find.text('Seçilen hedefte duyuruyu alacak kimse yok. Önce hedefi düzenleyin.'), findsOneWidget);
      expect(auth.announcementPublishCalls, isEmpty);
      expect(find.text('Yayını onayla'), findsNothing);
    });

    testWidgets('çift dokunuş: yayın isteği tek kez gider', (t) async {
      final auth = AnnouncementFakeAuth.seeded()..announcementWriteGate = Completer<void>();
      await _pump(t, auth);
      await _open(t, 'Aidat hatırlatması');
      await tapFinder(t, find.byKey(const ValueKey<String>('announcement_action_publish')));
      await settleFor(t);
      await tapText(t, 'Yayınla');
      await settleFor(t);
      expect(auth.announcementPublishCalls, <int>[40]);

      // İstek sürerken eylem düğmeleri kilitli: ikinci dokunuş yeni istek açmaz.
      final publish = find.byKey(const ValueKey<String>('announcement_action_publish'));
      await t.ensureVisible(publish);
      await t.pump();
      await t.tap(publish, warnIfMissed: false);
      await t.pump();
      expect(auth.announcementPublishCalls.length, 1);
      expect(auth.previewCalls.length, 1);

      // Eylem sürerken Kapat kilitli ve geri tuşu pencereyi kapatmaz (sonuç listeye yansıtılsın).
      final close = t.widget<TextButton>(find.widgetWithText(TextButton, 'Kapat'));
      expect(close.onPressed, isNull);
      await t.binding.handlePopRoute();
      await t.pump();
      expect(find.byType(AnnouncementManageDialog), findsOneWidget);

      auth.announcementWriteGate!.complete();
      await settleFor(t);
      expect(auth.announcementPublishCalls.length, 1);
      expect(find.byType(AnnouncementManageDialog), findsOneWidget);
      expect(t.widget<TextButton>(find.widgetWithText(TextButton, 'Kapat')).onPressed, isNotNull);
    });

    testWidgets('onay penceresinde çift dokunuş alttaki ayrıntı penceresini de kapatmaz', (t) async {
      final auth = AnnouncementFakeAuth.seeded();
      await _pump(t, auth);
      await _open(t, 'Asansör bakımı');
      await tapFinder(t, find.byKey(const ValueKey<String>('announcement_action_withdraw')));
      await settleFor(t);
      final confirm = find.descendant(of: find.byType(AlertDialog).last, matching: find.text('Geri Çek'));
      await t.tap(confirm);
      await t.tap(confirm, warnIfMissed: false); // aynı karede ikinci dokunuş
      await settleFor(t);
      expect(auth.announcementWithdrawCalls, <int>[41], reason: 'geri çekme tek kez');
      expect(find.byType(AnnouncementManageDialog), findsOneWidget, reason: 'ikinci pop alttaki pencereyi kapatmadı');
    });

    testWidgets('durum uyuşmazlığı (başka yönetici yayınlamış): Türkçe mesaj + ayrıntı yeniden okunur', (t) async {
      final auth = AnnouncementFakeAuth.seeded();
      await _pump(t, auth);
      await _open(t, 'Aidat hatırlatması');
      // Dialog açıkken başka bir yönetici yayınladı.
      auth.rows[40]!['status'] = 'published';
      await tapFinder(t, find.byKey(const ValueKey<String>('announcement_action_publish')));
      await settleFor(t);
      await tapText(t, 'Yayınla');
      await settleFor(t);
      expect(find.text('Duyurunun durumu değişmiş. Listeyi yenileyip tekrar deneyin.'), findsOneWidget);
      // Ayrıntı sunucudan yeniden okundu: artık yayınlanmış görünür.
      expect(find.byKey(const ValueKey<String>('announcement_action_withdraw')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('announcement_action_publish')), findsNothing);
    });

    testWidgets('Geri Çek: onay penceresi; vazgeçilirse çekilmez, onaylanırsa geri alınamayacağı söylenir', (t) async {
      final auth = AnnouncementFakeAuth.seeded();
      await _pump(t, auth);
      await _open(t, 'Asansör bakımı');
      await tapFinder(t, find.byKey(const ValueKey<String>('announcement_action_withdraw')));
      await settleFor(t);
      expect(find.text('Duyuruyu geri çek'), findsOneWidget);
      expect(find.textContaining('geri alınamaz'), findsOneWidget);
      await _confirm(t, 'Vazgeç');
      expect(auth.announcementWithdrawCalls, isEmpty);

      await tapFinder(t, find.byKey(const ValueKey<String>('announcement_action_withdraw')));
      await settleFor(t);
      await _confirm(t, 'Geri Çek');
      expect(auth.announcementWithdrawCalls, <int>[41]);
      expect(find.text('Duyuru geri çekildi.'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('announcement_action_withdraw')), findsNothing);
    });

    testWidgets('Sil: onaylanınca pencere kapanır ve liste yenilenir; vazgeçilirse kalır', (t) async {
      final auth = AnnouncementFakeAuth.seeded();
      await _pump(t, auth);
      await _open(t, 'Aidat hatırlatması');
      await tapFinder(t, find.byKey(const ValueKey<String>('announcement_action_delete')));
      await settleFor(t);
      await _confirm(t, 'Vazgeç');
      expect(auth.announcementDeleteCalls, isEmpty);
      expect(find.byType(AlertDialog), findsOneWidget);

      await tapFinder(t, find.byKey(const ValueKey<String>('announcement_action_delete')));
      await settleFor(t);
      await _confirm(t, 'Sil');
      expect(auth.announcementDeleteCalls, <int>[40]);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Duyuru silindi.'), findsOneWidget);
      expect(find.text('Aidat hatırlatması'), findsNothing);
      expect(find.byType(AnnouncementAdminCard), findsNWidgets(3));
    });

    testWidgets('Düzenle: form açılır, başlık değişince ayrıntı ve liste güncellenir', (t) async {
      final auth = AnnouncementFakeAuth.seeded();
      await _pump(t, auth);
      await _open(t, 'Aidat hatırlatması');
      await tapFinder(t, find.byKey(const ValueKey<String>('announcement_action_edit')));
      await settleFor(t);
      expect(find.byType(AnnouncementFormDialog), findsOneWidget);
      await _type(t, 'announcement_title', 'Aidat son gün');
      await tapText(t, 'Taslağı Kaydet');
      await settleFor(t);
      expect(auth.announcementUpdateCalls.single.fields, <String, Object?>{'title': 'Aidat son gün'});
      expect(find.byType(AnnouncementFormDialog), findsNothing);
      expect(find.text('Taslak kaydedildi.'), findsOneWidget);
      expect(find.text('Aidat son gün'), findsWidgets);
    });
  });

  group('atomik düzenleme + yayın', () {
    testWidgets('Düzenle + Şimdi yayınla başarısızsa hiçbir değişiklik kaydedilmez; ayrıntı eski başlığı korur', (t) async {
      final auth = AnnouncementFakeAuth.seeded();
      await _pump(t, auth);
      await _open(t, 'Aidat hatırlatması');
      await tapFinder(t, find.byKey(const ValueKey<String>('announcement_action_edit')));
      await settleFor(t);
      await _type(t, 'announcement_title', 'Aidat son gün');
      await tapFinder(t, find.byKey(const ValueKey<String>('announcement_mode_now')));
      await settleFor(t);
      auth.audienceRecipients = <Map<String, dynamic>>[];
      await _confirm(t, 'Yayınla'); // formun "Yayınla" düğmesi
      await _confirm(t, 'Yayınla'); // kitle onayı
      expect(find.text('Seçilen hedefte duyuruyu alacak kimse yok. Hedefi değiştirin.'), findsOneWidget);
      expect(auth.announcementUpdateCalls.single.fields, <String, Object?>{
        'title': 'Aidat son gün',
        'publish': 'now',
      });

      await _confirm(t, 'Vazgeç');
      expect(find.byType(AnnouncementFormDialog), findsNothing);
      expect(auth.rows[40]!['title'], 'Aidat hatırlatması');
      expect(find.text('Aidat hatırlatması'), findsWidgets);
      expect(find.byKey(const ValueKey<String>('announcement_action_publish')), findsOneWidget, reason: 'hâlâ taslak');
    });
  });

  group('404 ve hız sınırı', () {
    testWidgets('duyuru başka yönetici tarafından silinmiş: "Bu duyuru artık yok", eski içerik / eylemler kalkar, liste tazelenir', (t) async {
      final auth = AnnouncementFakeAuth.seeded();
      await _pump(t, auth);
      await _open(t, 'Aidat hatırlatması');
      auth.rows.remove(40);
      final listCalls = auth.announcementListCalls.length;

      await tapFinder(t, find.byKey(const ValueKey<String>('announcement_action_publish')));
      await settleFor(t);
      await _confirm(t, 'Yayınla');
      expect(find.text('Bu duyuru artık yok. Başka bir yönetici silmiş olabilir; liste yenilendi.'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('announcement_action_publish')), findsNothing);
      expect(find.byKey(const ValueKey<String>('announcement_action_edit')), findsNothing);
      expect(find.text('Tekrar Dene'), findsNothing, reason: 'olmayan duyuruyu yeniden denemenin anlamı yok');
      expect(auth.announcementListCalls.length, greaterThan(listCalls), reason: 'liste tazelendi');

      await tapText(t, 'Kapat');
      await settleFor(t);
      expect(find.text('Aidat hatırlatması'), findsNothing);
    });

    testWidgets('429: Türkçe "çok sık deneme" mesajı + eylem düğmeleri retry_after süresince kilitli', (t) async {
      final auth = AnnouncementFakeAuth.seeded()
        ..announcementWriteError = ApiException(
          'Çok fazla duyuru işlemi. Biraz sonra tekrar deneyin.',
          statusCode: 429,
          retryAfterSeconds: 20,
        );
      await _pump(t, auth);
      await _open(t, 'Asansör bakımı');
      await tapFinder(t, find.byKey(const ValueKey<String>('announcement_action_withdraw')));
      await settleFor(t);
      await _confirm(t, 'Geri Çek');
      expect(find.text('Çok sık deneme yapıldı. 20 saniye sonra tekrar deneyin.'), findsOneWidget);

      InkWell inkOf(String key) => t.widget<InkWell>(
        find.descendant(of: find.byKey(ValueKey<String>(key)), matching: find.byType(InkWell)).first,
      );
      // Kilitli düğmeler (PrimaryActionButton: onPressed null -> InkWell.onTap null).
      expect(inkOf('announcement_action_edit').onTap, isNull);
      expect(inkOf('announcement_action_withdraw').onTap, isNull);

      await t.pump(const Duration(seconds: 21));
      expect(inkOf('announcement_action_withdraw').onTap, isNotNull);
      auth.announcementWriteError = null;
      await tapFinder(t, find.byKey(const ValueKey<String>('announcement_action_withdraw')));
      await settleFor(t);
      await _confirm(t, 'Geri Çek');
      expect(auth.announcementWithdrawCalls.length, 2);
      expect(auth.rows[41]!['status'], 'withdrawn');
    });

    testWidgets('alıcı satırında güncel daire yoksa "—" (ekran okuyucuya "Güncel dairesi yok") yazılır', (t) async {
      final semantics = t.ensureSemantics();
      final auth = AnnouncementFakeAuth.seeded();
      auth.rows[41]!['recipients'] = <Map<String, dynamic>>[
        annRecipient(2, 'Taşınmış Kişi', apartments: const <String>[]),
      ];
      await _pump(t, auth);
      await _open(t, 'Asansör bakımı');
      await tapFinder(t, find.byKey(const ValueKey<String>('announcement_tab_recipients')));
      await settleFor(t);
      expect(find.text('Taşınmış Kişi'), findsOneWidget);
      expect(find.text('—'), findsOneWidget);
      expect(find.bySemanticsLabel('Güncel dairesi yok'), findsOneWidget);
      semantics.dispose();
    });
  });

  group('kurul üyesi (salt okunur)', () {
    testWidgets('ayrıntıda yazma düğmesi, alıcılar sekmesi ve oluşturan adı YOK; alıcı / önizleme uçları çağrılmaz', (t) async {
      final auth = AnnouncementFakeAuth.seeded(role: UserRole.apartmentOwner)..boardReadOnly = true;
      await _pump(
        t,
        auth,
        manage: false,
        readOnly: const <PeopleSite>[PeopleSite(code: 11, name: 'Gül Sitesi')],
      );
      await _open(t, 'Asansör bakımı');
      // Gerçek sunucu davranışı (redactForBoard): kurul + 3 alıcı (< 5) -> okunma / e-posta sayıları GİZLİ.
      expect(find.byKey(const ValueKey<String>('announcement_read_hidden')), findsOneWidget);
      expect(_inDialog(find.text('Okunma: —')), findsOneWidget);
      expect(find.textContaining('Gizli: küçük hedef'), findsWidgets);
      expect(find.text('Alıcı sayısı: 3'), findsOneWidget);
      expect(find.text('1/3 kişi okudu'), findsNothing);
      expect(find.text('0/3 kişi okudu'), findsNothing);
      expect(find.textContaining('Okuyan:'), findsNothing);
      expect(find.byKey(const ValueKey<String>('announcement_read_ratio')), findsNothing);
      expect(find.byKey(const ValueKey<String>('announcement_email_summary')), findsNothing);
      // İçerik görünür.
      expect(find.text('Yarın 10:00-12:00 arası asansör hizmet vermeyecek.'), findsWidgets);
      // Yazma ve alıcı adları yok.
      for (final key in const [
        'announcement_action_edit',
        'announcement_action_publish',
        'announcement_action_withdraw',
        'announcement_action_delete',
        'announcement_tab_recipients',
      ]) {
        expect(find.byKey(ValueKey<String>(key)), findsNothing, reason: key);
      }
      expect(find.text('Oluşturan'), findsNothing);
      expect(find.text('Site Yöneticisi'), findsNothing);
      expect(find.text('Ayşe Yılmaz'), findsNothing);
      expect(auth.recipientCalls, isEmpty);
      expect(auth.previewCalls, isEmpty);
    });

    testWidgets('G3: kurul + 5 ve daha çok alıcı: sayılar görünür (gizleme yalnız 1-4 alıcıda)', (t) async {
      final auth = AnnouncementFakeAuth.seeded(role: UserRole.apartmentOwner)..boardReadOnly = true;
      auth.rows[41]!['recipients'] = <Map<String, dynamic>>[
        annRecipient(1, 'Ayşe Yılmaz', readAt: DateTime.utc(2026, 10, 16, 5, 15), emailStatus: 'sent'),
        annRecipient(2, 'Mehmet Demir', readAt: DateTime.utc(2026, 10, 16, 6)),
        annRecipient(3, 'Zeynep Kaya'),
        annRecipient(4, 'Ali Veli'),
        annRecipient(5, 'Fatma Öz'),
      ];
      await _pump(
        t,
        auth,
        manage: false,
        readOnly: const <PeopleSite>[PeopleSite(code: 11, name: 'Gül Sitesi')],
      );
      await _open(t, 'Asansör bakımı');
      expect(find.byKey(const ValueKey<String>('announcement_read_hidden')), findsNothing);
      expect(find.text('2/5 kişi okudu'), findsOneWidget);
      expect(find.text('Okuyan: 2 • Okumayan: 3'), findsOneWidget);
      expect(auth.recipientCalls, isEmpty);
    });

    testWidgets('G3: yönetici küçük hedefte de sayıları görür (gizleme yalnız kurul içindir)', (t) async {
      final auth = AnnouncementFakeAuth.seeded();
      await _pump(t, auth);
      await _open(t, 'Asansör bakımı');
      expect(find.text('1/3 kişi okudu'), findsOneWidget);
      expect(find.text('Okuyan: 1 • Okumayan: 2'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('announcement_read_hidden')), findsNothing);
    });

    testWidgets('G3: liste kartında gizli okunma "Okunma: —" olur, "0/3" yazılmaz; ekran okuyucu etiketi gizliyi söyler', (t) async {
      final semantics = t.ensureSemantics();
      final auth = AnnouncementFakeAuth.seeded(role: UserRole.apartmentOwner)..boardReadOnly = true;
      await _pump(
        t,
        auth,
        manage: false,
        readOnly: const <PeopleSite>[PeopleSite(code: 11, name: 'Gül Sitesi')],
      );
      expect(find.text('Okunma: —'), findsWidgets);
      expect(find.textContaining('Okunma: 0/'), findsNothing);
      expect(find.textContaining('Okunma: 1/'), findsNothing);
      expect(
        find.bySemanticsLabel(RegExp('Okunma sayısı gizli \\(küçük hedef\\), toplam 3 alıcı')),
        findsWidgets,
      );
      semantics.dispose();
    });

    testWidgets('sunucu kurulda oluşturan adını gönderse bile (savunmacı) gösterilmez', (t) async {
      final auth = AnnouncementFakeAuth.seeded(role: UserRole.apartmentOwner);
      await _pump(
        t,
        auth,
        manage: false,
        readOnly: const <PeopleSite>[PeopleSite(code: 11, name: 'Gül Sitesi')],
      );
      await _open(t, 'Asansör bakımı');
      expect(auth.rows[41]!['created_by_name'], 'Site Yöneticisi');
      expect(find.text('Site Yöneticisi'), findsNothing);
      expect(find.text('Oluşturan'), findsNothing);
    });

    testWidgets('hem yönetici hem başka sitede kurul: yönetilen sitede yazma var, kurul sitesinde yok', (t) async {
      final auth = AnnouncementFakeAuth.seeded()
        ..sites = <SiteRecord>[pplSite(11, 'Gül Sitesi')];
      await _pump(t, auth, readOnly: _board);
      expect(find.text('Yeni Duyuru'), findsOneWidget);
      expect(find.text('Site'), findsOneWidget, reason: 'iki site: seçici');
    });
  });

  group('doğrudan pencere', () {
    testWidgets('ayrıntı yüklenirken başlık liste satırından gelir', (t) async {
      final auth = AnnouncementFakeAuth.seeded()..announcementDetailGate = Completer<void>();
      final scope = PeopleScope(authService: auth, siteCode: 11, siteName: 'Gül Sitesi', canWrite: true);
      await pumpList(
        t,
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => AnnouncementManageDialog.show(
              context,
              scope: scope,
              announcementId: 41,
              initialTitle: 'Liste başlığı',
            ),
            child: const Text('Aç'),
          ),
        ),
        width: 400,
        height: 800,
        scale: 1.0,
        dark: false,
      );
      await tapText(t, 'Aç');
      expect(find.text('Liste başlığı'), findsOneWidget);
      expect(find.text('Duyuru yükleniyor...'), findsOneWidget);
      auth.announcementDetailGate!.complete();
      await settleFor(t);
      expect(find.text('Asansör bakımı'), findsWidgets);
    });

    test('durum rozeti tonu ve simgesi: yayında yeşil, geri çekildi uyarı, zamanlanmış saat simgesi', () {
      expect(AnnouncementStatusChip.toneOf(AnnouncementStatus.published).name, 'success');
      expect(AnnouncementStatusChip.toneOf(AnnouncementStatus.withdrawn).name, 'warning');
      expect(AnnouncementStatusChip.iconOf(AnnouncementStatus.scheduled), Icons.schedule_rounded);
    });
  });

  group('inceleme düzeltmeleri: uzun başlık, anlam ağacı, çift dokunuş, düzenleme sayısı', () {
    const longTitle =
        'Sitemizin tüm bloklarında yapılacak yıllık periyodik asansör bakım ve kontrol çalışmaları hakkında önemli bilgilendirme';

    testWidgets('G11: uzun başlık ayrıntıda gövdenin başında SEÇİLEBİLİR tam metin olarak da bulunur (2,0 yazıda taşmaz)', (t) async {
      final auth = AnnouncementFakeAuth.seeded();
      auth.rows[50] = annRow(50, title: longTitle, publishedAt: DateTime.utc(2026, 10, 16, 8));
      await _pump(t, auth, width: 320, height: 640, scale: 2.0);
      await _open(t, longTitle);
      final full = find.byKey(const ValueKey<String>('announcement_full_title'));
      expect(full, findsOneWidget);
      expect(t.widget<SelectableText>(full).data, longTitle);
      expect(t.takeException(), isNull);
    });

    testWidgets('G11: kısa başlıkta tekrar eden başlık bloğu YOK', (t) async {
      final auth = AnnouncementFakeAuth.seeded();
      await _pump(t, auth);
      await _open(t, 'Asansör bakımı');
      expect(find.byKey(const ValueKey<String>('announcement_full_title')), findsNothing);
    });

    testWidgets('G11: liste kartında başlık en çok 3 satır; tam başlık ekran okuyucu etiketinde', (t) async {
      final semantics = t.ensureSemantics();
      final auth = AnnouncementFakeAuth.seeded();
      auth.rows[50] = annRow(50, title: longTitle, publishedAt: DateTime.utc(2026, 10, 16, 8));
      await _pump(t, auth, width: 320, height: 640, scale: 2.0);
      final titleText = t.widget<Text>(
        find.descendant(of: _card(longTitle), matching: find.text(longTitle)),
      );
      expect(titleText.maxLines, 3);
      expect(titleText.overflow, TextOverflow.ellipsis);
      expect(
        semanticLabels(t).where((l) => l.contains(longTitle)),
        hasLength(1),
        reason: 'tam başlık kartın TEK etiketinde, kesilmeden',
      );
      semantics.dispose();
    });

    testWidgets('G12: kart ekran okuyucuya TEK kez okunur (etiket + içerik çift okunmaz)', (t) async {
      final semantics = t.ensureSemantics();
      final auth = AnnouncementFakeAuth.seeded();
      await _pump(t, auth);
      final labels = semanticLabels(t);
      for (final title in const ['Asansör bakımı', 'Aidat hatırlatması', 'Bahçe düzenlemesi', 'Yanlış duyuru']) {
        expect(labels.where((l) => l.contains(title)), hasLength(1), reason: title);
      }
      final card = labels.singleWhere((l) => l.contains('Asansör bakımı'));
      expect(card, contains('Acil'));
      expect(card, contains('Yayında'));
      expect(card, contains('1 kişi okudu, toplam 3 alıcı'));
      expect(card, contains('E-posta da gönderilir'));
      // Kart bir düğmedir: dokunma eylemi korunur.
      final node = t.getSemantics(_card('Asansör bakımı'));
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      semantics.dispose();
    });

    testWidgets('G15: karta çift dokunuş iki ayrıntı penceresi açmaz', (t) async {
      final auth = AnnouncementFakeAuth.seeded();
      await _pump(t, auth);
      // Aynı karede iki dokunuş (kare çizilmeden): ikinci çağrı koruma bayrağıyla yok sayılır.
      final onTap = t.widget<AnnouncementAdminCard>(_card('Asansör bakımı')).onTap;
      onTap();
      onTap();
      await settleFor(t);
      expect(find.byType(AnnouncementManageDialog), findsOneWidget);
      await tapText(t, 'Kapat');
      expect(find.byType(AnnouncementManageDialog), findsNothing, reason: 'tek Kapat tüm pencereyi kapatır');
    });

    testWidgets('G15: "Yeni Duyuru"ya çift dokunuş iki form açmaz', (t) async {
      final auth = AnnouncementFakeAuth.seeded();
      await _pump(t, auth);
      final onPressed = t
          .widget<PrimaryActionButton>(find.byKey(const ValueKey<String>('announcement_create')))
          .onPressed!;
      onPressed();
      onPressed();
      await settleFor(t);
      expect(find.byType(AnnouncementFormDialog), findsOneWidget);
      await tapText(t, 'Vazgeç');
      expect(find.byType(AnnouncementFormDialog), findsNothing);
    });

    testWidgets('G20: sunucu edit_count gönderir: 1 kez -> "Düzenlendi: ...", 3 kez -> "(3 kez düzenlendi)"', (t) async {
      final auth = AnnouncementFakeAuth.seeded();
      await _pump(t, auth);
      await _open(t, 'Asansör bakımı');
      expect(find.textContaining('Düzenlendi: '), findsOneWidget);
      expect(find.textContaining('kez düzenlendi'), findsNothing);
      await tapText(t, 'Kapat');

      auth.rows[41]!['edit_count'] = 3;
      await _open(t, 'Asansör bakımı');
      expect(find.textContaining('(3 kez düzenlendi)'), findsOneWidget);
    });
  });

}
