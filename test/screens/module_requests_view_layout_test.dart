// Platform Faz 1.1: "Modül Talepleri" ekranı (ModuleRequestsView, yalnız süper kullanıcı).
//
// AGENTS.md kural 6: 320x640 x2,0 ve 360x640 x1,5, açık + koyu tema; yükleniyor / boş / hata / dolu
// durumlar taşmaz. Kural 7: karardan sonra liste otomatik yeniden çekilir, yenile düğmesi ve
// `reload()` (aşağı çekip yenileme) çalışır. Yarış korumaları: yenileme / filtre değişimi sürmekte
// olan "Daha fazla yükle"yi geçersiz kılar ve düğme sıfırlanır; hata sonrası yeniden denemede iskelet.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/module_request.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/views/module_requests_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/module_request_card.dart';

import 'dialog_layout_harness.dart' show settleFor;
import 'list_fixtures.dart';
import 'modules_fixtures.dart';

List<ModuleRequest> _requests() => <ModuleRequest>[
  mdRequest(9),
  mdRequest(
    8,
    siteCode: 12,
    siteName: 'Çok Uzun Adlı Konut Yapı Kooperatifi Yaşam Sitesi',
    moduleCode: 'online_payment',
    moduleName: 'Online Tahsilat ve Banka Bağlantısı',
    note:
        'Sakinlerimizden kredi kartıyla aidat tahsil etmek istiyoruz; lütfen en kısa sürede tanımlayın.',
    requestedBy: 'Muhammet Alperen Yıldırım Kaya',
  ),
  mdRequest(7, moduleCode: 'metering', moduleName: 'Sayaç Okuma ve Faturalandırma', note: null),
  mdRequest(
    6,
    status: 'approved',
    decidedBy: 'Süper Yönetici',
    moduleCode: 'reservation',
    moduleName: 'Rezervasyon ve Konsiyerj',
  ),
  mdRequest(
    5,
    status: 'rejected',
    decidedBy: 'Süper Yönetici',
    decisionNote: 'Paket kapsamında değil',
    moduleCode: 'work_tracking',
    moduleName: 'İş Takibi',
  ),
  mdRequest(4, status: 'cancelled', moduleCode: 'announcements', moduleName: 'Duyuru ve Bildirim'),
];

Future<GlobalKey<ModuleRequestsViewState>> _pump(
  WidgetTester t,
  ModulesFakeAuth auth, {
  double width = 400,
  double height = 1800,
  double scale = 1.0,
  bool dark = false,
  VoidCallback? onChanged,
}) async {
  final key = GlobalKey<ModuleRequestsViewState>();
  await pumpList(
    t,
    ModuleRequestsView(key: key, authService: auth, onChanged: onChanged),
    width: width,
    height: height,
    scale: scale,
    dark: dark,
  );
  return key;
}

ModulesFakeAuth _auth() => ModulesFakeAuth()..adminRequests = _requests();

Finder _inDialog(Finder f) => find.descendant(of: find.byType(AppDialog), matching: f);

void main() {
  group('taşma matrisi', () {
    listMatrix('bekleyen talepler (uzun site / modül / isteyen / not)', (t, w, h, s, dark) async {
      await _pump(t, _auth(), width: w, height: h, scale: s, dark: dark);

      expect(find.text('Modül Talepleri'), findsOneWidget);
      expect(find.byType(ModuleRequestCard), findsNWidgets(3));
      expect(find.text('Onayla'), findsNWidgets(3));
      expect(find.text('Reddet'), findsNWidgets(3));
      expect(find.widgetWithText(StatusChip, 'Bekliyor'), findsNWidgets(3));
      expect(find.text('Durum filtresi'), findsOneWidget);
      expect(find.textContaining('Aidat takibi için gerekli'), findsOneWidget);
      expect(find.text('Site: Gül Sitesi (11)'), findsNWidgets(2));
      expect(find.text('İsteyen: Ayşe Yılmaz'), findsNWidgets(2));
      expect(find.text('15.10.2026 09:30'), findsNWidgets(3));
      expect(find.byTooltip('Yenile'), findsOneWidget);
      expect(find.text('3 bekleyen'), findsOneWidget);
    });

    listMatrix('boş durum', (t, w, h, s, dark) async {
      await _pump(t, ModulesFakeAuth(), width: w, height: h, scale: s, dark: dark);
      expect(find.byType(EmptyCard), findsOneWidget);
      expect(find.text('Bekleyen modül talebi yok.'), findsOneWidget);
      expect(find.text('Daha fazla yükle'), findsNothing);
    });

    listMatrix('yükleniyor', (t, w, h, s, dark) async {
      final auth = ModulesFakeAuth()..adminGate = Completer<void>();
      await _pump(t, auth, width: w, height: h, scale: s, dark: dark);
      expect(find.byType(ListSkeleton), findsOneWidget);
      expect(find.byType(ModuleRequestCard), findsNothing);
    });

    listMatrix('hata (InlineNotice + Tekrar Dene)', (t, w, h, s, dark) async {
      final auth = ModulesFakeAuth()
        ..adminError = ApiException('Bu işlem için süper kullanıcı yetkisi gerekir.');
      await _pump(t, auth, width: w, height: h, scale: s, dark: dark);
      expect(find.byType(InlineNotice), findsOneWidget);
      expect(find.text('Bu işlem için süper kullanıcı yetkisi gerekir.'), findsOneWidget);
      expect(find.text('Tekrar Dene'), findsOneWidget);
    });

    listMatrix('Tümü filtresi: karar bilgisi (karar veren, tarih, gerekçe) ve Daha fazla yükle', (
      t,
      w,
      h,
      s,
      dark,
    ) async {
      final auth = ModulesFakeAuth()
        ..adminRequests = <ModuleRequest>[
          for (var i = 60; i > 6; i--) mdRequest(i, status: 'cancelled'),
          ..._requests().where((r) => r.id <= 6),
        ];
      final key = GlobalKey<ModuleRequestsViewState>();
      await pumpList(
        t,
        ModuleRequestsView(key: key, authService: auth),
        width: w,
        height: h,
        scale: s,
        dark: dark,
      );
      // Varsayılan Bekleyen: 0 bekleyen -> boş. "Tümü"ne geç.
      await tapFinder(t, find.byType(DropdownButtonFormField<String>));
      await tapFinder(t, find.text('Tümü').last);
      await settleFor(t);
      expect(auth.adminCalls.last.status, 'all');
      expect(find.text('Daha fazla yükle'), findsOneWidget);
      expect(find.byType(ModuleRequestCard), findsNWidgets(50));
    });
  });

  group('süzgeç', () {
    testWidgets('ilk istek: status=pending, limit 50, before_id yok', (t) async {
      final auth = _auth();
      await _pump(t, auth);
      expect(auth.adminCalls, hasLength(1));
      expect(auth.adminCalls.single.status, 'pending');
      expect(auth.adminCalls.single.limit, 50);
      expect(auth.adminCalls.single.before, isNull);
    });

    testWidgets('Onaylanan / Reddedilen / Tümü: sunucuya status iletilir; karar bilgisi gösterilir, düğme yok', (t) async {
      final auth = _auth();
      await _pump(t, auth);

      Future<void> choose(String label) async {
        await tapFinder(t, find.byType(DropdownButtonFormField<String>));
        await tapFinder(t, find.text(label).last);
        await settleFor(t);
      }

      await choose('Onaylanan');
      expect(auth.adminCalls.last.status, 'approved');
      expect(find.byType(ModuleRequestCard), findsOneWidget);
      expect(find.widgetWithText(StatusChip, 'Onaylandı'), findsOneWidget);
      expect(find.text('Onayla'), findsNothing);
      expect(find.text('Reddet'), findsNothing);
      expect(find.textContaining('Onaylandı: Süper Yönetici'), findsOneWidget);
      expect(find.textContaining('Gerekçe'), findsNothing, reason: 'decision_note null olabilir');

      await choose('Reddedilen');
      expect(auth.adminCalls.last.status, 'rejected');
      expect(find.textContaining('Gerekçe: Paket kapsamında değil'), findsOneWidget);

      await choose('Tümü');
      expect(auth.adminCalls.last.status, 'all');
      expect(find.byType(ModuleRequestCard), findsNWidgets(6));
      expect(find.widgetWithText(StatusChip, 'Geri çekildi'), findsOneWidget);
      expect(find.text('Onayla'), findsNWidgets(3), reason: 'yalnız bekleyenlerde karar düğmeleri');
    });

    testWidgets('boş sonuç süzgeç metni; bekleyen sayacı süzgeçten bağımsız', (t) async {
      final auth = _auth();
      await _pump(t, auth);
      await tapFinder(t, find.byType(DropdownButtonFormField<String>));
      await tapFinder(t, find.text('Reddedilen').last);
      await settleFor(t);
      auth.adminRequests = <ModuleRequest>[mdRequest(9)];
      await tapFinder(t, find.byTooltip('Yenile'));
      await settleFor(t);
      expect(find.text('Bu filtre için modül talebi yok.'), findsOneWidget);
      expect(find.text('1 bekleyen'), findsOneWidget,
          reason: 'başlıktaki sayı pending_count: süzgeçten bağımsız');
    });
  });

  group('geri çekilen talep', () {
    testWidgets('"Karar veren" yazılmaz (decided_by geri çekenin adıdır); yalnız "Geri çekildi" ve tarih', (t) async {
      final auth = ModulesFakeAuth()
        ..adminRequests = <ModuleRequest>[
          mdRequest(
            3,
            status: 'cancelled',
            decidedBy: 'Ayşe Yılmaz',
            decisionNote: 'olmaması gereken not',
          ),
          mdRequest(2, status: 'approved', decidedBy: 'Süper Yönetici', decisionNote: 'Uygun'),
        ];
      await _pump(t, auth);
      await tapFinder(t, find.byType(DropdownButtonFormField<String>));
      await tapFinder(t, find.text('Tümü').last);
      await settleFor(t);

      expect(find.byType(ModuleRequestCard), findsNWidgets(2));
      expect(find.textContaining('Geri çekildi •'), findsOneWidget);
      expect(find.textContaining('Geri çekildi: Ayşe'), findsNothing);
      expect(find.textContaining('Karar veren'), findsNothing);
      expect(find.textContaining('olmaması gereken not'), findsNothing);
      // Onaylanan talepte karar veren ve gerekçe görünür.
      expect(find.textContaining('Onaylandı: Süper Yönetici'), findsOneWidget);
      expect(find.text('Gerekçe: Uygun'), findsOneWidget);
    });
  });

  group('karar', () {
    testWidgets('Onayla: onay penceresi -> Vazgeç istek yapmaz -> Onayla istek + otomatik yeniden çekme + onChanged', (t) async {
      final auth = _auth();
      final changed = <int>[];
      await _pump(t, auth, onChanged: () => changed.add(1));
      final callsBefore = auth.adminCalls.length;

      await tapFinder(t, find.text('Onayla').first);
      expect(find.text('Talep Onaylansın mı?'), findsOneWidget);
      expect(_inDialog(find.textContaining('Aidat ve Finans')), findsOneWidget);
      expect(_inDialog(find.textContaining('Gül Sitesi (11)')), findsOneWidget);
      await tapText(t, 'Vazgeç');
      expect(auth.decideCalls, isEmpty);
      expect(changed, isEmpty);

      await tapFinder(t, find.text('Onayla').first);
      await tapFinder(t, _inDialog(find.text('Onayla')));
      await settleFor(t);

      expect(auth.decideCalls, hasLength(1));
      expect(auth.decideCalls.single.id, 9);
      expect(auth.decideCalls.single.approve, isTrue);
      expect(auth.decideCalls.single.note, isNull);
      expect(find.text('Talep onaylandı. Modül siteye tanımlandı.'), findsOneWidget);
      expect(changed, hasLength(1), reason: 'çekmece rozeti için onChanged');
      expect(auth.adminCalls.length, greaterThan(callsBefore), reason: 'liste otomatik yeniden çekilir');
      expect(find.byType(ModuleRequestCard), findsNWidgets(2), reason: 'onaylanan bekleyenlerden düştü');
      expect(find.text('2 bekleyen'), findsOneWidget);
    });

    testWidgets('Reddet: gerekçe alanı; gerekçe kırpılıp iletilir; boşsa boş metin; Vazgeç istek yapmaz', (t) async {
      final auth = _auth();
      await _pump(t, auth);

      await tapFinder(t, find.text('Reddet').first);
      expect(find.text('Talep Reddedilsin mi?'), findsOneWidget);
      expect(find.text('Gerekçe (isteğe bağlı)'), findsOneWidget);
      await tapText(t, 'Vazgeç');
      expect(auth.decideCalls, isEmpty);

      await tapFinder(t, find.text('Reddet').first);
      await t.enterText(find.byType(TextField), '  Paket kapsamında değil  ');
      await tapFinder(t, _inDialog(find.text('Reddet')));
      await settleFor(t);
      expect(auth.decideCalls.single.approve, isFalse);
      expect(auth.decideCalls.single.note, 'Paket kapsamında değil');
      expect(find.text('Talep reddedildi.'), findsOneWidget);

      await tapFinder(t, find.text('Reddet').first);
      await tapFinder(t, _inDialog(find.text('Reddet')));
      await settleFor(t);
      expect(auth.decideCalls.last.note, '', reason: 'gerekçe isteğe bağlıdır');
    });

    testWidgets('sunucu reddi (REQUEST_NOT_PENDING): Türkçe mesaj, liste yeniden okunur, onChanged yine çağrılır', (t) async {
      final auth = _auth()
        ..decideError = ApiException(
          'Bu talep artık bekleyen durumda değil.',
          statusCode: 409,
          code: 'REQUEST_NOT_PENDING',
        );
      final changed = <int>[];
      await _pump(t, auth, onChanged: () => changed.add(1));
      final callsBefore = auth.adminCalls.length;

      await tapFinder(t, find.text('Onayla').first);
      await tapFinder(t, _inDialog(find.text('Onayla')));
      await settleFor(t);
      expect(find.text('Bu talep artık bekleyen durumda değil.'), findsOneWidget);
      expect(changed, hasLength(1));
      expect(auth.adminCalls.length, greaterThan(callsBefore));
      expect(find.byType(ModuleRequestCard), findsNWidgets(3));
    });

    testWidgets('onayda 409 MODULE_ALREADY_ENABLED: bilgi verilir, liste yenilenir, talep bekleyen kalır', (t) async {
      final auth = _auth()
        ..decideError = ApiException(
          'Bu modül zaten açık.',
          statusCode: 409,
          code: 'MODULE_ALREADY_ENABLED',
        );
      final changed = <int>[];
      await _pump(t, auth, onChanged: () => changed.add(1));
      final callsBefore = auth.adminCalls.length;

      await tapFinder(t, find.text('Onayla').first);
      await tapFinder(t, _inDialog(find.text('Onayla')));
      await settleFor(t);
      expect(find.text('Bu modül zaten açık.'), findsOneWidget);
      expect(auth.adminCalls.length, greaterThan(callsBefore));
      expect(changed, hasLength(1));
      expect(find.byType(ModuleRequestCard), findsNWidgets(3));
    });

    testWidgets('işlem sürerken kart ilerleme gösterir, çift karar gönderilmez; diğer kartlar etkilenmez', (t) async {
      final auth = _auth()..decideGate = Completer<void>();
      await _pump(t, auth);

      await tapFinder(t, find.text('Onayla').first);
      await tapFinder(t, _inDialog(find.text('Onayla')));
      expect(auth.decideCalls, hasLength(1));
      expect(find.text('Onayla'), findsNWidgets(2), reason: 'karar verilen kartın düğmeleri kalkar');
      expect(
        find.descendant(
          of: find.byType(ModuleRequestCard).first,
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );

      auth.decideGate!.complete();
      await settleFor(t);
      expect(auth.decideCalls, hasLength(1));
      expect(find.byType(ModuleRequestCard), findsNWidgets(2));
    });

    testWidgets('karar sürerken ekran kapansa da onChanged çağrılır (rozet bayat kalmaz)', (t) async {
      final auth = _auth()..decideGate = Completer<void>();
      final changed = <int>[];
      await _pump(t, auth, onChanged: () => changed.add(1));
      await tapFinder(t, find.text('Onayla').first);
      await tapFinder(t, _inDialog(find.text('Onayla')));

      await t.pumpWidget(const SizedBox());
      auth.decideGate!.complete();
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
      expect(changed, hasLength(1));
    });
  });

  group('sayfalama ve yarış korumaları', () {
    ModulesFakeAuth many() => ModulesFakeAuth()
      ..adminRequests = <ModuleRequest>[for (var i = 60; i > 0; i--) mdRequest(i)];

    testWidgets('Daha fazla yükle: before_id ile sonraki sayfa eklenir; son sayfada düğme kalkar', (t) async {
      final auth = many();
      await _pump(t, auth, height: 3000);
      expect(find.byType(ModuleRequestCard), findsNWidgets(50));
      expect(find.text('60 bekleyen'), findsOneWidget);

      await tapText(t, 'Daha fazla yükle');
      await settleFor(t);
      expect(auth.adminCalls.last.before, 11);
      expect(find.byType(ModuleRequestCard), findsNWidgets(60));
      expect(find.text('Daha fazla yükle'), findsNothing);
    });

    testWidgets('Daha fazla yükle hatası: mesaj + Tekrar Dene, liste kalır, tekrar denenince devam eder', (t) async {
      final auth = many();
      await _pump(t, auth, height: 3000);
      auth.adminError = ApiException('Sunucu yanıt vermedi, tekrar deneyin.');
      await tapText(t, 'Daha fazla yükle');
      await settleFor(t);
      expect(find.text('Sunucu yanıt vermedi, tekrar deneyin.'), findsOneWidget);
      expect(find.byType(ModuleRequestCard), findsNWidgets(50));

      auth.adminError = null;
      await tapText(t, 'Tekrar Dene');
      await settleFor(t);
      expect(find.byType(ModuleRequestCard), findsNWidgets(60));
    });

    testWidgets('Daha fazla yükle sürerken YENİLE: eski yanıt eklenmez, düğme sıfırlanır ve tıklanabilir', (t) async {
      final auth = many();
      await _pump(t, auth, height: 3000);
      final moreGate = Completer<void>();
      final reloadGate = Completer<void>();
      auth.adminGateQueue
        ..add(moreGate)
        ..add(reloadGate);

      await tapText(t, 'Daha fazla yükle');
      expect(t.widget<PrimaryActionButton>(find.byType(PrimaryActionButton)).loading, isTrue);
      await tapFinder(t, find.byTooltip('Yenile'));
      var button = t.widget<PrimaryActionButton>(find.byType(PrimaryActionButton));
      expect(button.loading, isFalse);
      expect(button.onPressed, isNull, reason: 'yenileme sürerken eski imleçle yeni sayfa istenmez');

      moreGate.complete(); // eski imleçli yanıt şimdi geliyor
      await settleFor(t);
      expect(find.byType(ModuleRequestCard), findsNWidgets(50), reason: 'eski sayfa eklenmez');

      reloadGate.complete();
      await settleFor(t);
      button = t.widget<PrimaryActionButton>(find.byType(PrimaryActionButton));
      expect(button.loading, isFalse);
      expect(button.onPressed, isNotNull);
      await tapText(t, 'Daha fazla yükle');
      await settleFor(t);
      expect(find.byType(ModuleRequestCard), findsNWidgets(60));
    });

    testWidgets('Daha fazla yükle sürerken FİLTRE değişimi: eski yanıt yok sayılır, düğme sıfırlanır', (t) async {
      final auth = many();
      await _pump(t, auth, height: 3000);
      final moreGate = Completer<void>();
      auth.adminGateQueue.add(moreGate);
      await tapText(t, 'Daha fazla yükle');

      await tapFinder(t, find.byType(DropdownButtonFormField<String>));
      await tapFinder(t, find.text('Tümü').last);
      await settleFor(t);
      expect(auth.adminCalls.last.status, 'all');
      expect(auth.adminCalls.last.before, isNull);

      moreGate.complete();
      await settleFor(t);
      expect(find.byType(ModuleRequestCard), findsNWidgets(50));
      final button = t.widget<PrimaryActionButton>(find.byType(PrimaryActionButton));
      expect(button.loading, isFalse);
      expect(button.onPressed, isNotNull);
    });

    testWidgets('hata sonrası Tekrar Dene sürerken iskelet gösterilir; yanıltıcı boş durum yanıp sönmez', (t) async {
      final auth = _auth()..adminError = ApiException('Sunucuya ulaşılamadı. İnternet bağlantınızı kontrol edin.');
      await _pump(t, auth);
      expect(find.text('Tekrar Dene'), findsOneWidget);

      auth.adminError = null;
      auth.adminGate = Completer<void>();
      await tapText(t, 'Tekrar Dene');
      expect(find.byType(ListSkeleton), findsOneWidget);
      expect(find.text('Bekleyen modül talebi yok.'), findsNothing);
      expect(find.byType(EmptyCard), findsNothing);

      auth.adminGate!.complete();
      await settleFor(t);
      expect(find.byType(ModuleRequestCard), findsNWidgets(3));
    });

    testWidgets('yenile düğmesi ve reload() ilk sayfayı yeniden çeker; liste ekranda kalır; süzgeç korunur', (t) async {
      final auth = _auth();
      final key = await _pump(t, auth);
      await tapFinder(t, find.byType(DropdownButtonFormField<String>));
      await tapFinder(t, find.text('Onaylanan').last);
      await settleFor(t);
      final callsBefore = auth.adminCalls.length;

      auth.adminGate = Completer<void>();
      await tapFinder(t, find.byTooltip('Yenile'));
      expect(auth.adminCalls.length, callsBefore + 1);
      expect(find.byType(ModuleRequestCard), findsOneWidget, reason: 'yenilemede mevcut liste kalır');
      expect(find.byType(ListSkeleton), findsNothing);
      auth.adminGate!.complete();
      await settleFor(t);

      auth.adminGate = null;
      await key.currentState!.reload();
      await settleFor(t);
      expect(auth.adminCalls.last.status, 'approved');
      expect(auth.adminCalls.length, callsBefore + 2);
    });
  });
}
