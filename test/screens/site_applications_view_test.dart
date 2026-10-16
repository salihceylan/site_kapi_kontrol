// Platform: süper kullanıcı "Site Başvuruları" ekranı (docs/PLATFORM_SITE_BASVURUSU.md).
//
// Liste: durum süzgeci, arama (350 ms), sayfalama, hata + "Tekrar Dene" (asla "başvuru yok" değil), yarış
// koruması. Ayrıntı penceresi: başvuran iletişimi, bloklar / kapılar, cihaz durumu, İstanbul saati; onay
// ("N bloklu M daireli site kurulacak, X site yöneticisi olacak"), red (gerekçe), çift gönderim, 409 / 429 /
// 404 / APPLICANT_UNAVAILABLE kalıpları. Taşma: 320x640 x2,0 ve 360x640 x1,5, açık + koyu tema.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/dialogs/site_application_detail_dialog.dart';
import 'package:site_kapi_kontrol/ui/views/site_applications_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/site_application_parts.dart';

import '../design/harness.dart';
import 'dialog_layout_harness.dart';
import 'g4_test_support.dart';
import 'site_application_fixtures.dart';

SiteApplicationFakeAuth _auth() => SiteApplicationFakeAuth(role: UserRole.superUser, myUserCode: 999);

SiteApplicationFakeAuth _seeded() {
  final auth = _auth();
  auth.seed([
    saRow(
      41,
      siteName: 'Gül Sitesi',
      deviceUid: 'ESP32_C3_ABC',
      note: 'Cihazı kutudan çıkardım, kurulum için hazırım.',
      address: 'Moda Cad. No 5',
      doors: ['Ana Giriş', 'Otopark'],
    ),
    saRow(
      40,
      siteName: 'Mavi Park Konutları',
      city: 'Ankara',
      district: 'Çankaya',
      applicantCode: 6,
      applicantName: 'Mehmet Demir',
      applicantEmail: 'mehmet@example.com',
      applicantRole: 'apartment_owner',
      blocks: [
        {'name': 'A Blok', 'apartment_count': 8},
      ],
      createdAt: DateTime.utc(2026, 10, 15, 21, 30),
    ),
    saRow(
      39,
      status: 'approved',
      siteName: 'Yeşil Vadi',
      applicantCode: 7,
      applicantName: 'Zeynep Kaya',
      decidedAt: DateTime.utc(2026, 10, 15, 12),
      decidedByName: 'Süper Yönetici',
      siteCode: 1239,
    ),
    saRow(
      38,
      status: 'rejected',
      siteName: 'Kuzey Evleri',
      applicantCode: 8,
      applicantName: 'Can Aksoy',
      decidedAt: DateTime.utc(2026, 10, 14, 12),
      decidedByName: 'Süper Yönetici',
      decisionNote: 'Adres bilgisi eksik.',
    ),
    saRow(37, status: 'cancelled', siteName: 'Vazgeçilen Site', applicantCode: 9, applicantName: 'Elif Çelik'),
  ]);
  return auth;
}

Future<void> _pump(
  WidgetTester t,
  SiteApplicationFakeAuth auth, {
  double width = 400,
  double height = 900,
  double scale = 1.0,
  bool dark = false,
  VoidCallback? onChanged,
  Key? key,
}) async {
  await pumpAt(
    t,
    SiteApplicationsView(key: key, authService: auth, onChanged: onChanged),
    width: width,
    height: height,
    scale: scale,
    dark: dark,
  );
  await t.pump();
  await t.pump(const Duration(milliseconds: 100));
}

Future<void> _tapFilter(WidgetTester t, String value) async {
  final chip = find.byKey(ValueKey<String>('site_application_filter_$value'));
  await t.ensureVisible(chip);
  await t.pump();
  await t.tap(chip);
  await settleFor(t, 100);
}

Future<void> _openDetail(WidgetTester t, String siteName) async {
  final card = find.widgetWithText(AppCard, siteName).first;
  await t.ensureVisible(card);
  await t.pump();
  await t.tap(card);
  await settleFor(t, 600);
}

Finder _inDialog(Finder f) => find.descendant(of: find.byType(AlertDialog).last, matching: f);

Future<void> _tapKey(WidgetTester t, String key) async {
  final f = find.byKey(ValueKey<String>(key));
  await scrollTo(t, f);
  await t.tap(f);
  await settleFor(t, 100);
}

/// Onay penceresinin "Onayla" düğmesi.
Future<void> _confirmApprove(WidgetTester t) async {
  await t.tap(find.widgetWithText(ElevatedButton, 'Onayla'));
  await settleFor(t, 700);
}

void main() {
  group('taşma matrisi', () {
    g4LayoutMatrix('liste: bekleyen kartlar, başlık, arama ve durum süzgeci', (t, w, h, s, dark) async {
      final auth = _seeded();
      await _pump(t, auth, width: w, height: h, scale: s, dark: dark);
      expect(find.text('Site Başvuruları'), findsWidgets);
      expect(find.byKey(const ValueKey<String>('site_applications_search')), findsOneWidget);
      for (final key in const ['pending', 'approved', 'rejected', 'cancelled', 'all']) {
        expect(find.byKey(ValueKey<String>('site_application_filter_$key')), findsOneWidget);
      }
      await scrollTo(t, find.text('Gül Sitesi'));
      expect(find.text('Gül Sitesi'), findsOneWidget);
      expect(find.text('Başvuran: Ayşe Yılmaz'), findsOneWidget);
      expect(find.text('2 blok • 30 daire • 2 kapı'), findsOneWidget);
      expect(find.text('Cihazlı'), findsOneWidget);
      expect(find.text('Mavi Park Konutları'), findsOneWidget);
      expect(find.text('Yeşil Vadi'), findsNothing, reason: 'varsayılan süzgeç: yalnız bekleyen');
    });

    g4LayoutMatrix('liste: Tümü süzgeci tüm durumları gösterir (renk tek başına anlam taşımaz)', (t, w, h, s, dark) async {
      final auth = _seeded();
      await _pump(t, auth, width: w, height: h, scale: s, dark: dark);
      await _tapFilter(t, 'all');
      for (final label in const ['Bekliyor', 'Onaylandı', 'Reddedildi', 'İptal edildi']) {
        await scrollTo(t, find.text(label).first);
        expect(find.text(label), findsWidgets, reason: label);
      }
      expect(find.text('Onaylandı: 15.10.2026 15:00'), findsOneWidget, reason: 'İstanbul saati (UTC+3)');
    });

    g4LayoutMatrix('ayrıntı penceresi: tüm bölümler ve eylemler', (t, w, h, s, dark) async {
      final auth = _seeded();
      await _pump(t, auth, width: w, height: h, scale: s, dark: dark);
      await _openDetail(t, 'Gül Sitesi');
      expect(auth.detailCalls, <int>[41]);
      for (final label in const ['Başvuran', 'Site', 'Cihaz', 'Başvuran notu', 'Süreç']) {
        await scrollTo(t, find.text(label).last);
        expect(find.text(label), findsWidgets, reason: label);
      }
      await scrollTo(t, find.byKey(const ValueKey<String>('site_application_action_reject')));
      expect(find.byKey(const ValueKey<String>('site_application_action_approve')), findsOneWidget);
    });

    g4LayoutMatrix('hata: "Tekrar Dene", boş durum sahte değil', (t, w, h, s, dark) async {
      final auth = _auth()..adminListError = ApiException('Sunucu yanıt vermedi, tekrar deneyin.');
      await _pump(t, auth, width: w, height: h, scale: s, dark: dark);
      await scrollTo(t, find.text('Tekrar Dene'));
      expect(find.text('Sunucu yanıt vermedi, tekrar deneyin.'), findsOneWidget);
      expect(find.text('Bekleyen site başvurusu yok.'), findsNothing);
    });
  });

  group('liste', () {
    testWidgets('varsayılan: yalnız bekleyen istenir; sayaç rozeti ve kart bilgileri', (t) async {
      final auth = _seeded();
      await _pump(t, auth);
      expect(auth.adminListCalls.single, (status: 'pending', query: '', limit: 30, offset: 0));
      expect(find.text('2 bekleyen'), findsOneWidget);
      expect(find.text('Başvuru: 16.10.2026 14:30'), findsOneWidget, reason: '11:30 UTC = 14:30 İstanbul');
      expect(find.text('Başvuru: 16.10.2026 00:30'), findsOneWidget, reason: '15 Ekim 21:30 UTC = 16 Ekim 00:30 İstanbul');
      expect(find.text('İstanbul / Kadıköy'), findsOneWidget);
      expect(find.text('Ankara / Çankaya'), findsOneWidget);
    });

    testWidgets('durum süzgeci sunucuya iletilir; aynı süzgeç tekrar seçilince yeniden çağrılmaz', (t) async {
      final auth = _seeded();
      await _pump(t, auth);
      await _tapFilter(t, 'approved');
      expect(auth.adminListCalls.last.status, 'approved');
      expect(find.text('Yeşil Vadi'), findsOneWidget);
      expect(find.text('Gül Sitesi'), findsNothing);
      final calls = auth.adminListCalls.length;
      await _tapFilter(t, 'approved');
      expect(auth.adminListCalls.length, calls);

      await _tapFilter(t, 'cancelled');
      expect(auth.adminListCalls.last.status, 'cancelled');
      expect(find.text('Vazgeçilen Site'), findsOneWidget);
      await _tapFilter(t, 'rejected');
      expect(find.text('Kuzey Evleri'), findsOneWidget);
      expect(find.text('Karar: ', skipOffstage: false), findsNothing);
    });

    testWidgets('arama: 350 ms bekler, tek istek; temizle düğmesi erişilebilir ve süzgeci sıfırlar', (t) async {
      final auth = _seeded();
      await _pump(t, auth);
      final search = find.byKey(const ValueKey<String>('site_applications_search'));
      await t.enterText(search, 'Mavi');
      await t.pump(const Duration(milliseconds: 200));
      expect(auth.adminListCalls, hasLength(1), reason: 'duraksama dolmadan istek yok');
      await t.pump(const Duration(milliseconds: 200));
      await t.pump();
      expect(auth.adminListCalls.last.query, 'Mavi');
      expect(find.text('Mavi Park Konutları'), findsOneWidget);
      expect(find.text('Gül Sitesi'), findsNothing);

      // Başvuran adıyla da aranır.
      await t.enterText(search, 'ayşe');
      await t.pump(const Duration(milliseconds: 400));
      await t.pump();
      expect(find.text('Gül Sitesi'), findsOneWidget);

      // Temizle düğmesi: ipucu var, ekran okuyucudan gizlenmez, en az 48 dp.
      final clear = find.byTooltip('Aramayı temizle');
      expect(clear, findsOneWidget);
      final size = t.getSize(clear);
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
      final handle = t.ensureSemantics();
      final data = t.getSemantics(clear).getSemanticsData();
      expect(data.tooltip, 'Aramayı temizle');
      expect(data.hasAction(SemanticsAction.tap), isTrue, reason: 'ekran okuyucudan etkinleştirilebilir');
      expect(data.flagsCollection.isButton, isTrue);
      handle.dispose();
      await t.tap(clear);
      await settleFor(t, 100);
      expect(auth.adminListCalls.last.query, '');
      expect(find.text('Mavi Park Konutları'), findsOneWidget);
    });

    testWidgets('aramada sonuç yok: süzgeçli boş durum; aynı sorgu (Enter + sayaç) iki kez gitmez', (t) async {
      final auth = _seeded();
      await _pump(t, auth);
      final search = find.byKey(const ValueKey<String>('site_applications_search'));
      await t.enterText(search, 'yokboylebirsey');
      await t.testTextInput.receiveAction(TextInputAction.search);
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      expect(find.text('Bu arama için başvuru bulunamadı.'), findsOneWidget);
      expect(auth.adminListCalls.where((c) => c.query == 'yokboylebirsey'), hasLength(1));
    });

    testWidgets('boş liste: ilk durum mesajı; süzgeçte süzgece özgü mesaj', (t) async {
      final auth = _auth();
      await _pump(t, auth);
      expect(find.text('Bekleyen site başvurusu yok.'), findsOneWidget);
      await _tapFilter(t, 'approved');
      expect(find.text('Onaylanan başvuru yok.'), findsOneWidget);
      await _tapFilter(t, 'rejected');
      expect(find.text('Reddedilen başvuru yok.'), findsOneWidget);
      await _tapFilter(t, 'cancelled');
      expect(find.text('İptal edilen başvuru yok.'), findsOneWidget);
      await _tapFilter(t, 'all');
      expect(find.text('Henüz site başvurusu yok.'), findsOneWidget);
    });

    testWidgets('hata: "başvuru yok" DEĞİL hata + Tekrar Dene; yeniden deneyince liste gelir', (t) async {
      final auth = _seeded()..adminListError = ApiException('Sunucu yanıt vermedi, tekrar deneyin.');
      await _pump(t, auth);
      expect(find.text('Sunucu yanıt vermedi, tekrar deneyin.'), findsOneWidget);
      expect(find.text('Bekleyen site başvurusu yok.'), findsNothing);
      expect(find.byType(SiteApplicationAdminCard), findsNothing);

      auth.adminListError = null;
      await t.tap(find.text('Tekrar Dene'));
      await settleFor(t, 100);
      expect(find.byType(SiteApplicationAdminCard), findsNWidgets(2));
      expect(find.text('Sunucu yanıt vermedi, tekrar deneyin.'), findsNothing);
    });

    testWidgets('yenileme hatası eski listeyi silmez ama hatayı gösterir', (t) async {
      final auth = _seeded();
      final key = GlobalKey<SiteApplicationsViewState>();
      await _pump(t, auth, key: key);
      auth.adminListError = ApiException('Bağlantı yok.');
      await key.currentState!.reload();
      await t.pump();
      expect(find.byType(SiteApplicationAdminCard), findsNWidgets(2), reason: 'eski liste korunur');
      expect(find.text('Bağlantı yok.'), findsOneWidget);
    });

    testWidgets('sayfalama: "Daha fazla yükle" offset ile devam eder, kopya eklemez, hata tekrar denenir', (t) async {
      final auth = _auth()..maxPage = 2;
      for (var i = 1; i <= 5; i++) {
        auth.seed([saRow(i, siteName: 'Site $i', applicantCode: 100 + i, applicantName: 'Kişi $i')]);
      }
      await _pump(t, auth, height: 3000);
      expect(find.byType(SiteApplicationAdminCard), findsNWidgets(2));
      expect(find.text('5 bekleyen'), findsOneWidget);

      await t.tap(find.text('Daha fazla yükle'));
      await settleFor(t, 100);
      expect(auth.adminListCalls.last, (status: 'pending', query: '', limit: 30, offset: 2));
      expect(find.byType(SiteApplicationAdminCard), findsNWidgets(4));

      auth.adminListError = ApiException('Daha fazla yüklenemedi.');
      await t.tap(find.text('Daha fazla yükle'));
      await settleFor(t, 100);
      expect(find.text('Daha fazla yüklenemedi.'), findsOneWidget);
      expect(find.byType(SiteApplicationAdminCard), findsNWidgets(4), reason: 'hata listeyi silmez');
      auth.adminListError = null;
      await t.tap(find.text('Tekrar Dene'));
      await settleFor(t, 100);
      expect(find.byType(SiteApplicationAdminCard), findsNWidgets(5));
      expect(find.text('Daha fazla yükle'), findsNothing);
    });

    testWidgets('yarış: yavaş eski arama yanıtı yeni sonucu ezmez', (t) async {
      final auth = _seeded();
      await _pump(t, auth);
      final slow = Completer<void>();
      auth.adminListGates
        ..add(slow) // 1. arama (yavaş)
        ..add(Completer<void>()..complete()); // 2. arama (hızlı)
      final search = find.byKey(const ValueKey<String>('site_applications_search'));
      await t.enterText(search, 'Gül');
      await t.pump(const Duration(milliseconds: 400));
      await t.enterText(search, 'Mavi');
      await t.pump(const Duration(milliseconds: 400));
      await t.pump();
      expect(find.text('Mavi Park Konutları'), findsOneWidget);

      slow.complete();
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      expect(find.text('Mavi Park Konutları'), findsOneWidget);
      expect(find.text('Gül Sitesi'), findsNothing, reason: 'eski yanıt yeni sonucu ezmedi');
    });

    testWidgets('sayfa kapanınca (dispose) gelen yanıt çökme yapmaz', (t) async {
      final auth = _seeded();
      final gate = Completer<void>();
      auth.adminListGates.add(gate);
      await pumpAt(t, SiteApplicationsView(authService: auth), width: 400, height: 900, scale: 1.0);
      await t.pumpWidget(const SizedBox());
      gate.complete();
      await t.pump();
      expect(t.takeException(), isNull);
    });
  });

  group('ayrıntı penceresi', () {
    testWidgets('başvuran iletişimi, site bilgisi, bloklar, kapılar, cihaz, not ve İstanbul saati', (t) async {
      final auth = _seeded();
      await _pump(t, auth, height: 1400);
      await _openDetail(t, 'Gül Sitesi');
      expect(auth.detailCalls, <int>[41]);

      Finder inDialog(String text) => _inDialog(find.text(text));
      expect(inDialog('Ayşe Yılmaz'), findsOneWidget);
      expect(inDialog('ayse@example.com'), findsOneWidget);
      expect(inDialog('+905551112233'), findsOneWidget);
      expect(inDialog('Bireysel Kullanıcı'), findsOneWidget);
      expect(inDialog('2 blok • 30 daire • 2 kapı'), findsOneWidget);
      expect(inDialog('Moda Cad. No 5'), findsOneWidget);
      expect(inDialog('A Blok • 10 daire'), findsOneWidget);
      expect(inDialog('B Blok • 20 daire'), findsOneWidget);
      expect(inDialog('Ana Giriş'), findsOneWidget);
      expect(
        _inDialog(find.textContaining('Başvuruda seçilen cihaz: ESP32_C3_ABC')),
        findsOneWidget,
      );
      expect(_inDialog(find.textContaining('1. kapıya bağlanır')), findsOneWidget);
      expect(inDialog('Cihazı kutudan çıkardım, kurulum için hazırım.'), findsOneWidget);
      expect(inDialog('Başvuru: 16.10.2026 14:30 (İstanbul saati)'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('site_application_action_approve')), findsOneWidget);
    });

    testWidgets('cihaz artık başvuranın değilse: cihazsız kurulacağı açıkça yazılır', (t) async {
      final auth = _auth()
        ..seed([saRow(41, deviceUid: 'ESP32_C3_ABC', deviceAvailable: false)]);
      await _pump(t, auth, height: 1400);
      await _openDetail(t, 'Gül Sitesi');
      expect(_inDialog(find.textContaining('artık başvuranın hesabında değil')), findsOneWidget);
      expect(_inDialog(find.textContaining('cihazsız kurulur')), findsOneWidget);
    });

    testWidgets('karara bağlanmış başvuruda cihaz uyarısı çıkmaz (onaydan sonra device_available false normaldir)', (t) async {
      final auth = _auth()
        ..seed([
          saRow(
            41,
            status: 'approved',
            deviceUid: 'ESP32_C3_ABC',
            deviceAvailable: false,
            decidedAt: DateTime.utc(2026, 10, 16, 12),
            decidedByName: 'Süper Yönetici',
          ),
        ]);
      await _pump(t, auth, height: 1400);
      await _tapFilter(t, 'approved');
      await _openDetail(t, 'Gül Sitesi');
      expect(_inDialog(find.text('Başvuruda seçilen cihaz: ESP32_C3_ABC')), findsOneWidget);
      expect(_inDialog(find.textContaining('cihazsız')), findsNothing);
      expect(_inDialog(find.textContaining('artık başvuranın hesabında değil')), findsNothing);
    });

    testWidgets('cihazsız başvuru: "Cihaz sonra eklenebilir" notu; karar verilmiş başvuruda eylem düğmesi yok', (t) async {
      final auth = _seeded();
      await _pump(t, auth, height: 1400);
      await _openDetail(t, 'Mavi Park Konutları');
      expect(_inDialog(find.textContaining('Cihaz seçilmedi')), findsOneWidget);
      await t.tap(find.text('Kapat'));
      await settleFor(t, 300);

      await _tapFilter(t, 'approved');
      await _openDetail(t, 'Yeşil Vadi');
      expect(find.byKey(const ValueKey<String>('site_application_action_approve')), findsNothing);
      expect(find.byKey(const ValueKey<String>('site_application_action_reject')), findsNothing);
      expect(_inDialog(find.textContaining('Onaylandı: Süper Yönetici')), findsOneWidget);
      expect(_inDialog(find.textContaining('Kurulan site kodu: 1239')), findsOneWidget);
      await t.tap(find.text('Kapat'));
      await settleFor(t, 300);

      await _tapFilter(t, 'rejected');
      await _openDetail(t, 'Kuzey Evleri');
      expect(_inDialog(find.text('Gerekçe: Adres bilgisi eksik.')), findsOneWidget);
    });

    testWidgets('başvuran hesabı silinmiş (applicant: null): "Silinmiş hesap" gösterilir, onay APPLICANT_UNAVAILABLE ile reddedilir', (t) async {
      final auth = _auth()
        ..applicantUnavailable = true
        ..seed([saRow(41, siteName: 'Hayalet Sitesi', deletedApplicant: true)]);
      await _pump(t, auth, height: 1400);
      expect(find.text('Başvuran: Silinmiş hesap'), findsOneWidget);
      await _openDetail(t, 'Hayalet Sitesi');
      expect(_inDialog(find.text('Silinmiş hesap')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('site_application_deleted_applicant')), findsOneWidget);
      expect(_inDialog(find.text('ayse@example.com')), findsNothing, reason: 'iletişim bilgisi yok');

      await _tapKey(t, 'site_application_action_approve');
      expect(find.textContaining('Başvuran site yöneticisi olacak.'), findsOneWidget);
      await _confirmApprove(t);
      expect(
        _inDialog(find.text('Başvuran hesap silinmiş ya da pasif; başvuru onaylanamaz.')),
        findsOneWidget,
      );
      // Reddetme yine mümkün.
      expect(find.byKey(const ValueKey<String>('site_application_action_reject')), findsOneWidget);
    });

    testWidgets('ayrıntı hatası: Tekrar Dene; 404 ise "artık yok" ve eylem yok, liste tazelenir', (t) async {
      final auth = _seeded();
      var changed = 0;
      await _pump(t, auth, height: 1400, onChanged: () => changed++);
      auth.detailError = ApiException('Sunucu yanıt vermedi, tekrar deneyin.');
      await _openDetail(t, 'Gül Sitesi');
      expect(_inDialog(find.text('Sunucu yanıt vermedi, tekrar deneyin.')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('site_application_action_approve')), findsNothing);
      auth.detailError = null;
      await t.tap(find.text('Tekrar Dene'));
      await settleFor(t, 300);
      expect(find.byKey(const ValueKey<String>('site_application_action_approve')), findsOneWidget);
      await t.tap(find.text('Kapat'));
      await settleFor(t, 300);

      auth.rows.remove(40);
      await _openDetail(t, 'Mavi Park Konutları');
      expect(_inDialog(find.textContaining('artık yok')), findsOneWidget);
      expect(find.text('Tekrar Dene'), findsNothing);
      expect(find.byKey(const ValueKey<String>('site_application_action_approve')), findsNothing);
      expect(changed, greaterThan(0), reason: 'rozet / liste tazelenir');
    });
  });

  group('onay', () {
    testWidgets('onay penceresi N bloklu M daireli site kurulacak, X site yöneticisi olacak der; onayla -> tek istek', (t) async {
      final auth = _seeded();
      var changed = 0;
      await _pump(t, auth, height: 1400, onChanged: () => changed++);
      await _openDetail(t, 'Gül Sitesi');
      await _tapKey(t, 'site_application_action_approve');
      expect(
        find.text(
          '"Gül Sitesi" için 2 bloklu 30 daireli site kurulacak, Ayşe Yılmaz site yöneticisi olacak. '
          'Uygunsa seçilen cihaz 1. kapıya bağlanacak.',
        ),
        findsOneWidget,
      );
      expect(auth.approveCalls, isEmpty, reason: 'onay penceresi açıkken istek yok');

      await _confirmApprove(t);
      expect(auth.approveCalls, <int>[41]);
      expect(find.byType(SiteApplicationDetailDialog), findsNothing, reason: 'başarıda pencere kapanır');
      expect(
        find.text('"Gül Sitesi" sitesi kuruldu; Ayşe Yılmaz artık site yöneticisi.'),
        findsOneWidget,
      );
      expect(find.text('Gül Sitesi'), findsNothing, reason: 'liste yenilendi: onaylanan bekleyenlerden düştü');
      expect(find.text('Mavi Park Konutları'), findsOneWidget);
      expect(changed, greaterThan(0), reason: 'çekmece rozeti tazelenir');
    });

    testWidgets('onay penceresi: cihaz başvuranın değilse cihazsız kurulacağı yazılır; sonuç iletisi de uyarır', (t) async {
      final auth = _auth()
        ..deviceAttached = false
        ..seed([saRow(41, deviceUid: 'ESP32_C3_ABC', deviceAvailable: false)]);
      await _pump(t, auth, height: 1400);
      await _openDetail(t, 'Gül Sitesi');
      await _tapKey(t, 'site_application_action_approve');
      expect(find.textContaining('site cihazsız kurulacak'), findsOneWidget);
      await _confirmApprove(t);
      expect(find.textContaining('Cihaz bağlanamadı, sonradan bağlanabilir.'), findsOneWidget);
    });

    testWidgets('onay penceresinde Vazgeç: istek yok, ayrıntı açık kalır', (t) async {
      final auth = _seeded();
      await _pump(t, auth, height: 1400);
      await _openDetail(t, 'Gül Sitesi');
      await _tapKey(t, 'site_application_action_approve');
      await t.tap(find.text('Vazgeç'));
      await settleFor(t, 300);
      expect(auth.approveCalls, isEmpty);
      expect(find.byType(SiteApplicationDetailDialog), findsOneWidget);
    });

    testWidgets('çift gönderim: onay sürerken düğmeler kilitli, geri tuşu pencereyi kapatmaz, tek istek', (t) async {
      final auth = _seeded()..decideGate = Completer<void>();
      await _pump(t, auth, height: 1400);
      await _openDetail(t, 'Gül Sitesi');
      await _tapKey(t, 'site_application_action_approve');
      await t.tap(find.widgetWithText(ElevatedButton, 'Onayla'));
      await settleFor(t, 100);
      expect(auth.approveCalls, <int>[41]);

      final approve = t.widget<PrimaryActionButton>(find.byKey(const ValueKey<String>('site_application_action_approve')));
      final reject = t.widget<PrimaryActionButton>(find.byKey(const ValueKey<String>('site_application_action_reject')));
      expect(approve.loading, isTrue);
      expect(approve.onPressed, isNull);
      expect(reject.onPressed, isNull, reason: 'öteki eylem de kilitli');
      final navigator = t.state<NavigatorState>(find.byType(Navigator).first);
      await navigator.maybePop();
      await t.pump();
      expect(find.byType(SiteApplicationDetailDialog), findsOneWidget,
          reason: 'işlem sürerken geri tuşu pencereyi kapatmaz');

      auth.decideGate!.complete();
      await settleFor(t, 700);
      expect(auth.approveCalls, <int>[41], reason: 'çift istek yok');
      expect(find.byType(SiteApplicationDetailDialog), findsNothing);
    });

    testWidgets('409 APPLICATION_NOT_PENDING (başka yönetici karar verdi): mesaj, ayrıntı yeniden okunur, eylemler kalkar', (t) async {
      final auth = _seeded();
      var changed = 0;
      await _pump(t, auth, height: 1400, onChanged: () => changed++);
      await _openDetail(t, 'Gül Sitesi');
      auth.serverDecide(41, 'rejected', note: 'Başka yönetici reddetti');
      await _tapKey(t, 'site_application_action_approve');
      await _confirmApprove(t);
      expect(_inDialog(find.text('Bu başvuru artık bekleyen durumda değil.')), findsOneWidget);
      expect(auth.detailCalls, hasLength(2), reason: 'ayrıntı sunucudan yeniden okundu');
      expect(find.byKey(const ValueKey<String>('site_application_action_approve')), findsNothing);
      expect(_inDialog(find.text('Gerekçe: Başka yönetici reddetti')), findsOneWidget);
      expect(changed, greaterThan(0));
    });

    testWidgets('409 APPLICANT_UNAVAILABLE: Türkçe mesaj; reddetme hâlâ mümkün', (t) async {
      final auth = _seeded()..applicantUnavailable = true;
      await _pump(t, auth, height: 1400);
      await _openDetail(t, 'Gül Sitesi');
      await _tapKey(t, 'site_application_action_approve');
      await _confirmApprove(t);
      expect(
        _inDialog(find.text('Başvuran hesap silinmiş ya da pasif; başvuru onaylanamaz.')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey<String>('site_application_action_reject')), findsOneWidget);
      final approve = t.widget<PrimaryActionButton>(find.byKey(const ValueKey<String>('site_application_action_approve')));
      expect(approve.onPressed, isNotNull, reason: 'kilit yalnız işlem sürerken');
    });

    testWidgets('429: eylemler retry-after kadar kilitlenir, süre dolunca açılır', (t) async {
      final auth = _seeded()
        ..decideError = ApiException(
          'Çok fazla istek gönderildi.',
          statusCode: 429,
          retryAfterSeconds: 20,
        );
      await _pump(t, auth, height: 1400);
      await _openDetail(t, 'Gül Sitesi');
      await _tapKey(t, 'site_application_action_approve');
      await _confirmApprove(t);
      expect(_inDialog(find.textContaining('Çok sık deneme yapıldı. 20 saniye sonra tekrar deneyin.')), findsOneWidget);
      var approve = t.widget<PrimaryActionButton>(find.byKey(const ValueKey<String>('site_application_action_approve')));
      var reject = t.widget<PrimaryActionButton>(find.byKey(const ValueKey<String>('site_application_action_reject')));
      expect(approve.onPressed, isNull);
      expect(reject.onPressed, isNull);

      await t.pump(const Duration(seconds: 21));
      approve = t.widget<PrimaryActionButton>(find.byKey(const ValueKey<String>('site_application_action_approve')));
      expect(approve.onPressed, isNotNull);
    });

    testWidgets('genel hata: dürüst Türkçe mesaj, pencere açık; ham istisna sızmaz', (t) async {
      final auth = _seeded()..decideError = StateError('ham ayrıntı');
      await _pump(t, auth, height: 1400);
      await _openDetail(t, 'Gül Sitesi');
      await _tapKey(t, 'site_application_action_approve');
      await _confirmApprove(t);
      expect(
        _inDialog(find.text('Başvuru onaylanamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.')),
        findsOneWidget,
      );
      expect(find.textContaining('ham ayrıntı'), findsNothing);
      expect(find.textContaining('StateError'), findsNothing);
    });
  });

  group('red', () {
    testWidgets('gerekçe isteğe bağlı: yazılan gerekçe iletilir; Vazgeç istek göndermez', (t) async {
      final auth = _seeded();
      var changed = 0;
      await _pump(t, auth, height: 1400, onChanged: () => changed++);
      await _openDetail(t, 'Gül Sitesi');
      await _tapKey(t, 'site_application_action_reject');
      expect(find.text('Başvuru reddedilsin mi?'), findsOneWidget);
      await t.tap(find.text('Vazgeç'));
      await settleFor(t, 300);
      expect(auth.rejectCalls, isEmpty);

      await _tapKey(t, 'site_application_action_reject');
      await t.enterText(
        find.byKey(const ValueKey<String>('site_application_reject_reason')),
        '  Adres eksik  ',
      );
      await t.tap(find.widgetWithText(ElevatedButton, 'Reddet'));
      await settleFor(t, 700);
      expect(auth.rejectCalls, [(id: 41, reason: 'Adres eksik')]);
      expect(find.text('Başvuru reddedildi.'), findsOneWidget);
      expect(find.byType(SiteApplicationDetailDialog), findsNothing);
      expect(changed, greaterThan(0));
    });

    testWidgets('gerekçesiz red: boş gerekçe iletilir (sunucu gövdeye koymaz)', (t) async {
      final auth = _seeded();
      await _pump(t, auth, height: 1400);
      await _openDetail(t, 'Gül Sitesi');
      await _tapKey(t, 'site_application_action_reject');
      await t.tap(find.widgetWithText(ElevatedButton, 'Reddet'));
      await settleFor(t, 700);
      expect(auth.rejectCalls, [(id: 41, reason: '')]);
    });

    testWidgets('300 karakteri aşan gerekçe sessizce KIRPILMAZ: hata gösterilir, Reddet kapalı', (t) async {
      final auth = _seeded();
      await _pump(t, auth, height: 1400);
      await _openDetail(t, 'Gül Sitesi');
      await _tapKey(t, 'site_application_action_reject');
      final field = find.byKey(const ValueKey<String>('site_application_reject_reason'));
      await t.enterText(field, 'a' * 320);
      await t.pump();
      expect(t.widget<EditableText>(find.descendant(of: field, matching: find.byType(EditableText))).controller.text.length, 320);
      expect(find.text('Gerekçe en çok 300 karakter olabilir.'), findsOneWidget);
      expect(t.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Reddet')).onPressed, isNull);
      await t.enterText(field, 'a' * 300);
      await t.pump();
      expect(find.text('Gerekçe en çok 300 karakter olabilir.'), findsNothing);
      expect(t.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Reddet')).onPressed, isNotNull);
    });

    testWidgets('red sırasında 409: Türkçe mesaj ve ayrıntı yeniden okunur', (t) async {
      final auth = _seeded();
      await _pump(t, auth, height: 1400);
      await _openDetail(t, 'Gül Sitesi');
      auth.serverDecide(41, 'approved');
      await _tapKey(t, 'site_application_action_reject');
      await t.tap(find.widgetWithText(ElevatedButton, 'Reddet'));
      await settleFor(t, 700);
      expect(_inDialog(find.text('Bu başvuru artık bekleyen durumda değil.')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('site_application_action_reject')), findsNothing);
    });
  });

  group('erişilebilirlik', () {
    testWidgets('kart tek birleşik etikettir (durum metinle de söylenir)', (t) async {
      final auth = _seeded();
      await _pump(t, auth);
      final handle = t.ensureSemantics();
      final card = find.widgetWithText(AppCard, 'Gül Sitesi').first;
      final data = t.getSemantics(card).getSemanticsData();
      expect(data.label, contains('Site başvurusu: Gül Sitesi'));
      expect(data.label, contains('Bekliyor'));
      expect(data.label, contains('Başvuran: Ayşe Yılmaz'));
      expect(data.label, contains('2 blok • 30 daire • 2 kapı'));
      handle.dispose();
    });

    testWidgets('durum rozetleri simge + etiketle ayrışır (yalnız renk değil)', (t) async {
      for (final status in const ['pending', 'approved', 'rejected', 'cancelled']) {
        final style = siteApplicationStatusStyle(status);
        expect(style.icon, isNotNull);
      }
      expect(
        {
          for (final s in const ['pending', 'approved', 'rejected', 'cancelled'])
            siteApplicationStatusStyle(s).icon,
        },
        hasLength(4),
        reason: 'her durumun simgesi farklı',
      );
    });
  });
}
