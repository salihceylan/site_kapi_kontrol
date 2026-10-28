// Platform Faz 3b-A: "Belgeler" ekranı bütünleşik akışları (DocumentsView): yönetim <-> sakin görünüm seçici,
// yükleme / silme sonrası listenin OTOMATİK yenilenmesi (AGENTS.md kural 7), çift dokunuş korumaları.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';
import 'package:site_kapi_kontrol/services/document_file_share.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/views/document_admin_view.dart';
import 'package:site_kapi_kontrol/ui/views/document_resident_view.dart';
import 'package:site_kapi_kontrol/ui/views/document_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/document_parts.dart';

import 'dialog_layout_harness.dart' show settleFor;
import 'document_fixtures.dart';
import 'list_fixtures.dart';

const PeopleSite _write = PeopleSite(
  code: 11,
  name: 'Gül Sitesi',
  canWrite: true,
);
const PeopleSite _read = PeopleSite(code: 11, name: 'Gül Sitesi');

Finder _key(String key) => find.byKey(ValueKey<String>(key));

Future<GlobalKey<DocumentsViewState>> _pump(
  WidgetTester t,
  DocumentFakeAuth auth,
  FakeDocumentService service, {
  bool all = false,
  List<PeopleSite> manage = const <PeopleSite>[],
  bool resident = false,
  List<PeopleSite> residentSites = const <PeopleSite>[],
  FakeDocumentPicker? picker,
  DocumentFileSharer? sharer,
  double width = 400,
  double height = 2400,
  double scale = 1.0,
  bool dark = false,
}) async {
  final key = GlobalKey<DocumentsViewState>();
  await pumpList(
    t,
    DocumentsView(
      key: key,
      authService: auth,
      service: service,
      manageAllSites: all,
      manageSites: manage,
      showResident: resident,
      residentSites: residentSites,
      picker: picker ?? FakeDocumentPicker(),
      sharer: sharer,
    ),
    width: width,
    height: height,
    scale: scale,
    dark: dark,
  );
  await settleFor(t, 100);
  await settleFor(t, 100);
  await settleFor(t, 100);
  return key;
}

void main() {
  group('görünüm seçimi', () {
    listMatrix('hiçbir yetki yok: açıklayıcı boş durum', (
      t,
      w,
      h,
      s,
      dark,
    ) async {
      final auth = DocumentFakeAuth();
      await _pump(
        t,
        auth,
        FakeDocumentService(authService: auth),
        width: w,
        height: h,
        scale: s,
        dark: dark,
      );
      expect(find.text('Belge bulunamadı.'), findsOneWidget);
      expect(find.text('Dosya Deposu'), findsOneWidget);
    });

    listMatrix('yalnız yönetim: seçici yok', (t, w, h, s, dark) async {
      final auth = DocumentFakeAuth();
      await _pump(
        t,
        auth,
        seededDocuments(auth),
        manage: const <PeopleSite>[_write],
        width: w,
        height: h,
        scale: s,
        dark: dark,
      );
      expect(find.byType(DocumentAdminView), findsOneWidget);
      expect(_key('documents_mode_manage'), findsNothing);
    });

    testWidgets(
      'hem yönetim hem sakin: seçici çıkar; varsayılan yönetim; geçiş sakin görünümünü kurar',
      (t) async {
        final auth = DocumentFakeAuth();
        final service = seededDocuments(auth, board: true);
        await _pump(
          t,
          auth,
          service,
          manage: const <PeopleSite>[_read],
          resident: true,
          residentSites: const <PeopleSite>[_read],
        );
        expect(find.byType(DocumentAdminView), findsOneWidget);
        expect(_key('documents_mode_manage'), findsOneWidget);
        expect(_key('documents_mode_resident'), findsOneWidget);
        expect(service.mineCalls, isEmpty);

        await tapFinder(t, _key('documents_mode_resident'));
        await settleFor(t);
        expect(find.byType(DocumentResidentView), findsOneWidget);
        expect(find.byType(DocumentAdminView), findsNothing);
        expect(service.mineCalls, isNotEmpty);

        await tapFinder(t, _key('documents_mode_manage'));
        await settleFor(t);
        expect(find.byType(DocumentAdminView), findsOneWidget);
      },
    );

    testWidgets('reload() görünen görünümü yeniler (çekip yenileme)', (
      t,
    ) async {
      final auth = DocumentFakeAuth();
      final service = seededDocuments(auth);
      final key = await _pump(
        t,
        auth,
        service,
        manage: const <PeopleSite>[_write],
      );
      final before = service.listCalls.length;
      await key.currentState!.reload();
      await settleFor(t);
      expect(service.listCalls.length, greaterThan(before));

      final residentService = residentDocuments(auth);
      final residentKey = await _pump(t, auth, residentService, resident: true);
      final mineBefore = residentService.mineCalls.length;
      await residentKey.currentState!.reload();
      await settleFor(t);
      expect(residentService.mineCalls.length, greaterThan(mineBefore));
    });

    testWidgets(
      'yönetim görünümünden sakine geçerken süzgeçler birbirine sızmaz',
      (t) async {
        final auth = DocumentFakeAuth();
        final service = seededDocuments(auth);
        await _pump(
          t,
          auth,
          service,
          manage: const <PeopleSite>[_write],
          resident: true,
          residentSites: const <PeopleSite>[_write],
        );
        await tapFinder(t, _key('document_category_contract'));
        await settleFor(t);
        expect(service.listCalls.last.category, 'contract');
        await tapFinder(t, _key('documents_mode_resident'));
        await settleFor(t);
        expect(
          service.mineCalls.last.category,
          isNull,
          reason: 'sakin görünümü kendi süzgecini sıfırdan kurar',
        );
      },
    );
  });

  group('işlem sonrası otomatik yenileme (kural 7)', () {
    testWidgets(
      'yükleme sonrası: bildirim + liste yenilenir + kota çubuğu güncellenir',
      (t) async {
        final auth = DocumentFakeAuth();
        final service = seededDocuments(auth);
        final picker = FakeDocumentPicker([
          fakeSource('Yeni Plan.pdf', size: 3 * 1024 * 1024),
        ]);
        await _pump(
          t,
          auth,
          service,
          manage: const <PeopleSite>[_write],
          picker: picker,
        );
        expect(find.byType(DocumentAdminCard), findsNWidgets(3));
        expect(find.text('42 MB / 200 MB'), findsOneWidget);

        await tapFinder(t, _key('document_create'));
        await settleFor(t);
        await tapFinder(t, _key('document_upload_pick'));
        await settleFor(t);
        await tapFinder(t, _key('document_upload_audience_residents'));
        await tapFinder(t, _key('document_upload_submit'));
        await settleFor(t);
        await settleFor(t);
        await settleFor(t);
        await settleFor(t);

        expect(find.text('Belge yüklendi.'), findsOneWidget);
        expect(find.byType(DocumentAdminCard), findsNWidgets(4));
        expect(
          find.text('Yeni Plan'),
          findsOneWidget,
          reason: 'başlık dosya adından önerilmişti',
        );
        expect(
          find.text('45 MB / 200 MB'),
          findsOneWidget,
          reason: 'kullanım yeniden okundu',
        );
      },
    );

    testWidgets(
      'silme sonrası: bildirim + belge listeden kalkar; Silinenler\'de görünür',
      (t) async {
        final auth = DocumentFakeAuth();
        final service = seededDocuments(auth);
        await _pump(t, auth, service, manage: const <PeopleSite>[_write]);
        await tapFinder(
          t,
          find.widgetWithText(DocumentAdminCard, 'Yönetici Sözleşmesi'),
        );
        await settleFor(t);
        await settleFor(t);
        await tapFinder(t, _key('document_detail_delete'));
        await settleFor(t);
        await tapFinder(t, _key('document_confirm_ok'));
        await settleFor(t);
        await settleFor(t);
        await settleFor(t);

        expect(
          find.text(
            'Belge silindi. Silinenler listesinden geri yükleyebilirsiniz.',
          ),
          findsOneWidget,
        );
        expect(find.byType(DocumentAdminCard), findsNWidgets(2));
        expect(find.text('Yönetici Sözleşmesi'), findsNothing);
        await tapFinder(t, _key('document_status_deleted'));
        await settleFor(t);
        expect(find.text('Yönetici Sözleşmesi'), findsOneWidget);
        expect(
          find.byType(DocumentAdminCard),
          findsNWidgets(2),
          reason: 'eski silinmiş belge + yeni silinen',
        );
      },
    );

    testWidgets('geri yükleme sonrası: Silinenler boşalır, Yayında\'ya döner', (
      t,
    ) async {
      final auth = DocumentFakeAuth();
      final service = seededDocuments(auth);
      await _pump(t, auth, service, manage: const <PeopleSite>[_write]);
      await tapFinder(t, _key('document_status_deleted'));
      await settleFor(t);
      await tapFinder(
        t,
        find.widgetWithText(DocumentAdminCard, 'Eski Duyuru Afişi'),
      );
      await settleFor(t);
      await settleFor(t);
      await tapFinder(t, _key('document_detail_restore'));
      await settleFor(t);
      await settleFor(t);
      await settleFor(t);
      expect(find.text('Belge geri yüklendi.'), findsOneWidget);
      expect(find.text('Silinmiş belge yok.'), findsOneWidget);
    });

    testWidgets(
      'düzenleme sonrası liste başlığı güncellenir (ayrıntı penceresi açıkken bile)',
      (t) async {
        final auth = DocumentFakeAuth();
        final service = seededDocuments(auth);
        await _pump(t, auth, service, manage: const <PeopleSite>[_write]);
        await tapFinder(
          t,
          find.widgetWithText(DocumentAdminCard, 'Kurul Toplantı Tutanağı'),
        );
        await settleFor(t);
        await settleFor(t);
        await tapFinder(t, _key('document_detail_edit'));
        await settleFor(t);
        await t.enterText(_key('document_edit_title'), 'Genel Kurul Tutanağı');
        await t.pump();
        await tapFinder(t, _key('document_edit_save'));
        await settleFor(t);
        await settleFor(t);
        await settleFor(t);
        expect(find.text('Belge güncellendi.'), findsOneWidget);
        // Ayrıntı penceresi (başlık) ve arkadaki liste kartı aynı yeni başlığı taşır.
        expect(find.text('Genel Kurul Tutanağı'), findsWidgets);
        expect(
          find.widgetWithText(DocumentAdminCard, 'Genel Kurul Tutanağı'),
          findsOneWidget,
          reason: 'liste kartı gerçekten yeni başlığa güncellendi',
        );
        expect(find.text('Kurul Toplantı Tutanağı'), findsNothing);
      },
    );
  });

  group('çift dokunuş', () {
    testWidgets(
      '"Belge Yükle" art arda iki kez dokunulunca tek pencere açılır',
      (t) async {
        final auth = DocumentFakeAuth();
        final service = seededDocuments(auth);
        await _pump(t, auth, service, manage: const <PeopleSite>[_write]);
        final button = _key('document_create');
        await t.ensureVisible(button);
        await t.pump();
        await t.tap(button);
        await t.tap(button, warnIfMissed: false);
        await settleFor(t);
        await settleFor(t);
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.text('Belge Yükle'), findsWidgets);
      },
    );

    testWidgets(
      'kart art arda iki kez dokunulunca tek ayrıntı penceresi açılır',
      (t) async {
        final auth = DocumentFakeAuth();
        final service = seededDocuments(auth);
        await _pump(t, auth, service, manage: const <PeopleSite>[_write]);
        final card = find.widgetWithText(DocumentAdminCard, 'Site Yönetmeliği');
        await t.ensureVisible(card);
        await t.pump();
        await t.tap(card);
        await t.tap(card, warnIfMissed: false);
        await settleFor(t);
        await settleFor(t);
        expect(find.byType(AlertDialog), findsOneWidget);
      },
    );

    testWidgets('sakin: Aç / Kaydet art arda iki kez dokunulunca tek indirme', (
      t,
    ) async {
      final auth = DocumentFakeAuth();
      final service = residentDocuments(auth);
      final shared = <ShareParams>[];
      final sharer = DocumentFileSharer(
        shareFn: (p) async {
          shared.add(p);
          return const ShareResult('', ShareResultStatus.success);
        },
        cleanupDelay: Duration.zero,
        sweepStaleOnShare: false,
      );
      await _pump(t, auth, service, resident: true, sharer: sharer);
      final gate = Completer<void>();
      service.downloadGates.add(gate);
      final open = _key('document_open_2');
      await t.ensureVisible(open);
      await t.pump();
      await t.tap(open);
      await t.tap(open, warnIfMissed: false);
      await settleFor(t);
      gate.complete();
      await settleFor(t);
      await settleFor(t);
      expect(service.mineDownloadCalls, <int>[2]);
      expect(shared, hasLength(1));
    });
  });
}
