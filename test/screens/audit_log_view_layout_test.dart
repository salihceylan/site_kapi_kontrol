// Platform modül sistemi Faz 1: "Denetim Kaydı" ekranı (AuditLogView).
//
// AGENTS.md kural 6: 320x640 x2,0 ve 360x640 x1,5, açık + koyu tema; yükleniyor / boş / hata / dolu
// durumlar taşmaz. Kural 7: yenile düğmesi ve `reload()` (aşağı çekip yenileme) çalışır; "Daha fazla
// yükle" sonraki sayfayı `before_id` ile ekler (aynı kayıt iki kez gösterilmez).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/audit_log.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/views/audit_log_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/audit_log_card.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';

import 'dialog_layout_harness.dart' show settleFor;
import 'list_fixtures.dart';
import 'modules_fixtures.dart';

List<AuditLogPage> _twoPages() => <AuditLogPage>[
  AuditLogPage(
    items: <AuditLogEntry>[
      mdAudit(9),
      mdAudit(
        8,
        action: 'staff_role.assigned',
        targetType: 'user',
        targetId: '42',
        details: const <String, dynamic>{'role': 'BOARD_MEMBER'},
        actor: 'Çok Uzun Adlı Bir Süper Kullanıcı Hesabı Sahibi',
        site: 'Çok Uzun Adlı Konut Yapı Kooperatifi Sitesi',
      ),
      mdAudit(7, action: 'module.enabled', details: const <String, dynamic>{'enabled': true}),
    ],
    nextBeforeId: 7,
  ),
  AuditLogPage(
    items: <AuditLogEntry>[
      mdAudit(7, action: 'module.enabled'), // yinelenen: tekrar gösterilmez
      mdAudit(6, action: 'staff_role.removed', targetType: 'user', targetId: '42',
          details: const <String, dynamic>{'role': 'STAFF'}),
      mdAudit(5, action: 'site.archived', targetType: 'site', targetId: '11'),
    ],
  ),
];

Future<GlobalKey<AuditLogViewState>> _pump(
  WidgetTester t,
  ModulesFakeAuth auth, {
  double width = 400,
  double height = 1600,
  double scale = 1.0,
  bool dark = false,
}) async {
  final key = GlobalKey<AuditLogViewState>();
  await pumpList(
    t,
    AuditLogView(key: key, authService: auth),
    width: width,
    height: height,
    scale: scale,
    dark: dark,
  );
  return key;
}

void main() {
  group('taşma matrisi', () {
    listMatrix('dolu görünüm (kayıtlar + Daha fazla yükle)', (t, w, h, s, dark) async {
      final auth = ModulesFakeAuth()..auditPages = _twoPages();
      await _pump(t, auth, width: w, height: h, scale: s, dark: dark);

      expect(find.text('Denetim Kaydı'), findsOneWidget);
      expect(find.byType(AuditLogCard), findsNWidgets(3));
      expect(find.text('Modül kapatıldı'), findsOneWidget);
      expect(find.text('Ek rol atandı'), findsOneWidget);
      expect(find.text('Modül açıldı'), findsOneWidget);
      expect(find.text('Geçiş Kontrol (JetPass)'), findsNWidgets(2));
      expect(find.text('Kullanıcı 42 • Yönetim Kurulu / Denetçi'), findsOneWidget);
      expect(find.text('Süper Yönetici • Süper Kullanıcı'), findsNWidgets(2));
      expect(find.text('Site: Gül Sitesi'), findsNWidgets(2));
      expect(find.text('15.10.2026 09:30'), findsNWidgets(3));
      expect(find.text('Daha fazla yükle'), findsOneWidget);
      expect(find.byTooltip('Yenile'), findsOneWidget);
      expect(find.text('Site filtresi'), findsOneWidget);
      expect(find.text('Eylem filtresi'), findsOneWidget);
    });

    listMatrix('boş durum', (t, w, h, s, dark) async {
      await _pump(t, ModulesFakeAuth(), width: w, height: h, scale: s, dark: dark);
      expect(find.byType(EmptyCard), findsOneWidget);
      expect(find.text('Henüz denetim kaydı yok.'), findsOneWidget);
      expect(find.text('Daha fazla yükle'), findsNothing);
    });

    listMatrix('yükleniyor', (t, w, h, s, dark) async {
      final auth = ModulesFakeAuth()..auditGate = Completer<void>();
      await _pump(t, auth, width: w, height: h, scale: s, dark: dark);
      expect(find.byType(ListSkeleton), findsOneWidget);
      expect(find.byType(AuditLogCard), findsNothing);
    });

    listMatrix('hata (InlineNotice + Tekrar Dene)', (t, w, h, s, dark) async {
      final auth = ModulesFakeAuth()
        ..auditError = ApiException('Bu işlem için süper kullanıcı yetkisi gerekir.');
      await _pump(t, auth, width: w, height: h, scale: s, dark: dark);
      expect(find.byType(InlineNotice), findsOneWidget);
      expect(find.text('Bu işlem için süper kullanıcı yetkisi gerekir.'), findsOneWidget);
      expect(find.text('Tekrar Dene'), findsOneWidget);
    });
  });

  group('davranış', () {
    testWidgets('ilk istek: limit 50, before_id yok, süzgeçsiz', (t) async {
      final auth = ModulesFakeAuth()..auditPages = _twoPages();
      await _pump(t, auth);
      expect(auth.auditCalls, hasLength(1));
      expect(auth.auditCalls.single.limit, 50);
      expect(auth.auditCalls.single.before, isNull);
      expect(auth.auditCalls.single.site, isNull);
    });

    testWidgets('Daha fazla yükle: before_id ile sonraki sayfa eklenir, yineleme atlanır, son sayfada düğme kalkar', (t) async {
      final auth = ModulesFakeAuth()..auditPages = _twoPages();
      await _pump(t, auth);
      expect(find.byType(AuditLogCard), findsNWidgets(3));

      await tapText(t, 'Daha fazla yükle');
      await settleFor(t);

      expect(auth.auditCalls.last.before, 7);
      expect(find.byType(AuditLogCard), findsNWidgets(5),
          reason: '3 + (3 - 1 yinelenen)');
      expect(find.text('Ek rol kaldırıldı'), findsOneWidget);
      expect(find.text('Diğer işlem'), findsOneWidget,
          reason: 'bilinmeyen eylem ham kodla değil "Diğer işlem" olarak görünür');
      expect(find.text('site.archived'), findsNothing);
      expect(find.text('Daha fazla yükle'), findsNothing);
    });

    testWidgets('Daha fazla yükle hatası: mesaj + Tekrar Dene, mevcut liste kalır, tekrar denenince devam eder', (t) async {
      final auth = ModulesFakeAuth()..auditPages = _twoPages();
      await _pump(t, auth);
      auth.auditError = ApiException('Sunucu yanıt vermedi, tekrar deneyin.');

      await tapText(t, 'Daha fazla yükle');
      await settleFor(t);
      expect(find.text('Sunucu yanıt vermedi, tekrar deneyin.'), findsOneWidget);
      expect(find.byType(AuditLogCard), findsNWidgets(3));
      expect(find.text('Daha fazla yükle'), findsOneWidget);

      auth.auditError = null;
      await tapText(t, 'Tekrar Dene');
      await settleFor(t);
      expect(find.byType(AuditLogCard), findsNWidgets(5));
      expect(find.text('Sunucu yanıt vermedi, tekrar deneyin.'), findsNothing);
    });

    testWidgets('site filtresi: seçilince kayıtlar o site için yeniden çekilir; boş sonuç uygun metin', (t) async {
      final auth = ModulesFakeAuth()..auditPages = _twoPages();
      await _pump(t, auth);
      expect(find.byType(AuditLogCard), findsNWidgets(3));

      auth.auditPages = <AuditLogPage>[const AuditLogPage()];
      await tapFinder(t, find.byType(DropdownButtonFormField<int>));
      await tapFinder(t, find.text('Mavi Park (12)'));
      await settleFor(t);

      expect(auth.auditCalls.last.site, 12);
      expect(auth.auditCalls.last.before, isNull);
      expect(find.byType(AuditLogCard), findsNothing);
      expect(find.text('Bu filtre için denetim kaydı yok.'), findsOneWidget);

      // "Tüm siteler"e dönünce süzgeç kalkar.
      auth.auditPages = _twoPages();
      await tapFinder(t, find.byType(DropdownButtonFormField<int>));
      await tapFinder(t, find.text('Tüm siteler').last);
      await settleFor(t);
      expect(auth.auditCalls.last.site, isNull);
      expect(find.byType(AuditLogCard), findsNWidgets(3));
    });

    testWidgets('yenile düğmesi ve reload() ilk sayfayı yeniden çeker; liste ekranda kalır', (t) async {
      final auth = ModulesFakeAuth()..auditPages = _twoPages();
      final key = await _pump(t, auth);
      expect(auth.auditCalls, hasLength(1));

      auth.auditGate = Completer<void>();
      await tapFinder(t, find.byTooltip('Yenile'));
      expect(auth.auditCalls, hasLength(2));
      expect(find.byType(AuditLogCard), findsNWidgets(3),
          reason: 'yenilemede mevcut liste kalır');
      expect(find.byType(ListSkeleton), findsNothing);
      auth.auditGate!.complete();
      await settleFor(t);

      auth.auditGate = null;
      await key.currentState!.reload();
      await settleFor(t);
      expect(auth.auditCalls, hasLength(3));
      expect(auth.auditCalls.last.before, isNull);
    });

    testWidgets('Daha fazla yükle sürerken YENİLE: eski yanıt eklenmez, düğme sıfırlanır ve tıklanabilir', (t) async {
      final auth = ModulesFakeAuth()..auditPages = _twoPages();
      await _pump(t, auth);
      final moreGate = Completer<void>();
      final reloadGate = Completer<void>();
      auth.auditGateQueue
        ..add(moreGate)
        ..add(reloadGate);

      await tapText(t, 'Daha fazla yükle');
      expect(t.widget<PrimaryActionButton>(find.byType(PrimaryActionButton)).loading, isTrue);

      await tapFinder(t, find.byTooltip('Yenile'));
      // Yenileme sürerken düğme pasif (eski imleçle yeni sayfa istenmez) ve dönmüyor.
      var button = t.widget<PrimaryActionButton>(find.byType(PrimaryActionButton));
      expect(button.loading, isFalse);
      expect(button.onPressed, isNull);

      moreGate.complete(); // ESKİ imleçli yanıt şimdi geliyor
      await settleFor(t);
      expect(find.byType(AuditLogCard), findsNWidgets(3), reason: 'eski sayfa listeye eklenmez');

      reloadGate.complete();
      await settleFor(t);
      button = t.widget<PrimaryActionButton>(find.byType(PrimaryActionButton));
      expect(button.loading, isFalse, reason: 'düğme sonsuza dek dönmez');
      expect(button.onPressed, isNotNull);
      expect(find.byType(AuditLogCard), findsNWidgets(3));

      // Yeniden tıklanabilir ve yeni imleçle çalışır.
      await tapText(t, 'Daha fazla yükle');
      await settleFor(t);
      expect(auth.auditCalls.last.before, 7);
      expect(find.byType(AuditLogCard), findsNWidgets(5));
    });

    testWidgets('Daha fazla yükle sürerken FİLTRE değişimi: eski yanıt yok sayılır, düğme sıfırlanır', (t) async {
      final auth = ModulesFakeAuth()..auditPages = _twoPages();
      await _pump(t, auth);
      final moreGate = Completer<void>();
      auth.auditGateQueue.add(moreGate);
      await tapText(t, 'Daha fazla yükle');

      auth.auditPages = _twoPages(); // süzgeçli yeni ilk sayfa
      await tapFinder(t, find.byType(DropdownButtonFormField<String>));
      await tapFinder(t, find.text('Modül kapatıldı').last);
      await settleFor(t);
      expect(auth.auditCalls.last.action, 'module.disabled');
      expect(auth.auditCalls.last.before, isNull);

      moreGate.complete(); // eski imleç (filtre öncesi)
      await settleFor(t);
      expect(find.byType(AuditLogCard), findsNWidgets(3));
      final button = t.widget<PrimaryActionButton>(find.byType(PrimaryActionButton));
      expect(button.loading, isFalse);
      expect(button.onPressed, isNotNull);
    });

    testWidgets('hata sonrası Tekrar Dene sürerken iskelet gösterilir; yanıltıcı boş durum yanıp sönmez', (t) async {
      final auth = ModulesFakeAuth()
        ..auditPages = _twoPages()
        ..auditError = ApiException('Sunucuya ulaşılamadı. İnternet bağlantınızı kontrol edin.');
      await _pump(t, auth);
      expect(find.text('Tekrar Dene'), findsOneWidget);

      auth.auditError = null;
      auth.auditGate = Completer<void>();
      await tapText(t, 'Tekrar Dene');
      expect(find.byType(ListSkeleton), findsOneWidget);
      expect(find.text('Henüz denetim kaydı yok.'), findsNothing);
      expect(find.byType(EmptyCard), findsNothing);
      expect(find.text('Tekrar Dene'), findsNothing);

      auth.auditGate!.complete();
      await settleFor(t);
      expect(find.byType(AuditLogCard), findsNWidgets(3));
    });

    testWidgets('eylem filtresi: seçenekler, sunucuya action iletilir, site filtresiyle birleşir, Tümü süzgeci kaldırır', (t) async {
      final auth = ModulesFakeAuth()..auditPages = _twoPages();
      await _pump(t, auth);
      expect(auth.auditCalls.single.action, isNull);

      await tapFinder(t, find.byType(DropdownButtonFormField<String>));
      for (final label in <String>[
        'Tümü',
        'Modül açıldı',
        'Modül kapatıldı',
        'Rol verildi',
        'Rol kaldırıldı',
      ]) {
        expect(find.text(label), findsWidgets, reason: label);
      }
      await tapFinder(t, find.text('Rol verildi').last);
      await settleFor(t);
      expect(auth.auditCalls.last.action, 'staff_role.assigned');
      expect(auth.auditCalls.last.site, isNull);

      // Site filtresiyle birleşir.
      await tapFinder(t, find.byType(DropdownButtonFormField<int>));
      await tapFinder(t, find.text('Mavi Park (12)'));
      await settleFor(t);
      expect(auth.auditCalls.last.action, 'staff_role.assigned');
      expect(auth.auditCalls.last.site, 12);

      // Boş sonuç: süzgeç metni.
      auth.auditPages = <AuditLogPage>[const AuditLogPage()];
      await tapFinder(t, find.byTooltip('Yenile'));
      await settleFor(t);
      expect(find.text('Bu filtre için denetim kaydı yok.'), findsOneWidget);

      // Tümü: eylem süzgeci kalkar (site filtresi sürer).
      await tapFinder(t, find.byType(DropdownButtonFormField<String>));
      await tapFinder(t, find.text('Tümü').last);
      await settleFor(t);
      expect(auth.auditCalls.last.action, isNull);
      expect(auth.auditCalls.last.site, 12);
    });

    testWidgets('yenileme (reload) seçili filtreleri korur', (t) async {
      final auth = ModulesFakeAuth()..auditPages = _twoPages();
      final key = await _pump(t, auth);
      await tapFinder(t, find.byType(DropdownButtonFormField<String>));
      await tapFinder(t, find.text('Modül açıldı').last);
      await settleFor(t);
      await key.currentState!.reload();
      await settleFor(t);
      expect(auth.auditCalls.last.action, 'module.enabled');
    });

    testWidgets('hata sonrası Tekrar Dene içerik getirir', (t) async {
      final auth = ModulesFakeAuth()
        ..auditPages = _twoPages()
        ..auditError = ApiException('Sunucuya ulaşılamadı. İnternet bağlantınızı kontrol edin.');
      await _pump(t, auth);
      expect(find.text('Tekrar Dene'), findsOneWidget);

      auth.auditError = null;
      await tapText(t, 'Tekrar Dene');
      await settleFor(t);
      expect(find.byType(AuditLogCard), findsNWidgets(3));
    });

    testWidgets('site listesi alınamazsa süzgeç gizlenir ama kayıtlar listelenir', (t) async {
      final auth = ModulesFakeAuth()
        ..auditPages = _twoPages()
        ..listSitesError = ApiException('Site listesi alınamadı.');
      await _pump(t, auth);
      expect(find.text('Site filtresi'), findsNothing);
      expect(find.text('Eylem filtresi'), findsOneWidget);
      expect(find.byType(AuditLogCard), findsNWidgets(3));
    });

    testWidgets('PrimaryActionButton yükleniyor durumunda "Daha fazla yükle" tekrar tıklanamaz', (t) async {
      final auth = ModulesFakeAuth()..auditPages = _twoPages();
      await _pump(t, auth);
      auth.auditGate = Completer<void>();
      await tapText(t, 'Daha fazla yükle');
      final button = t.widget<PrimaryActionButton>(find.byType(PrimaryActionButton));
      expect(button.loading, isTrue);
      expect(button.onPressed, isNull);
      expect(auth.auditCalls.where((c) => c.before != null), hasLength(1));
      auth.auditGate!.complete();
      await settleFor(t);
    });
  });
}
