// Platform Faz 4a: sakin "Borcum" ekranı (MyFinanceView).
//
// AGENTS.md kural 6: 320x640 x2,0 ve 360x640 x1,5, açık + koyu tema; yükleniyor / boş / hata / dolu durumlar
// taşmaz. Para bütünlüğü ve gizlilik: YALNIZ GÖRÜNTÜLEME (yazma düğmesi yok); yönetici notu / kaydeden adı
// gösterilmez; hata, yükleme ve modül kapalı durumları asla "Borcunuz yok" demez; "Borcunuz yok" yalnız sunucu
// bakiyeyi gerçekten sıfır döndürdüğünde görünür. Eski / yavaş yanıt yenisini ezmez.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart' show InlineNotice;
import 'package:site_kapi_kontrol/ui/views/my_finance_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

import 'dialog_layout_harness.dart' show settleFor;
import 'finance_fixtures.dart';
import 'list_fixtures.dart';

Future<GlobalKey<MyFinanceViewState>> _pump(
  WidgetTester t,
  FinanceFakeAuth auth, {
  double width = 400,
  double height = 2400,
  double scale = 1.0,
  bool dark = false,
}) async {
  final key = GlobalKey<MyFinanceViewState>();
  await pumpList(
    t,
    MyFinanceView(key: key, authService: auth),
    width: width,
    height: height,
    scale: scale,
    dark: dark,
  );
  await settleFor(t, 100);
  await settleFor(t, 100);
  return key;
}

List<Map<String, dynamic>> _manyEntries(int count, {int apartmentId = 301}) => <Map<String, dynamic>>[
  for (var i = 0; i < count; i++)
    <String, dynamic>{
      ...finEntry(
        100 + i,
        apartmentId,
        amount: 10000 + i,
        entryDate: '2026-10-${(i % 28 + 1).toString().padLeft(2, '0')}',
        definitionName: 'Aylık aidat',
      ),
      'description': null,
      'reversal_reason': null,
      'created_by_name': null,
      'reversed_by_entry_id': null,
    },
];

void main() {
  group('taşma matrisi', () {
    listMatrix('tek daire: borç, vadesi geçen, sıradaki vade, hareketler', (t, w, h, s, dark) async {
      final auth = FinanceFakeAuth.seeded()..myFinanceItems = <Map<String, dynamic>>[finMyItem()];
      await _pump(t, auth, width: w, height: h, scale: s, dark: dark);
      expect(find.byType(MyFinanceCard), findsOneWidget);
      expect(find.text('Borç'), findsWidgets);
      expect(find.text('1.000,00 ₺'), findsOneWidget);
      expect(find.text('Vadesi geçen: 500,00 ₺'), findsOneWidget);
      expect(find.text('Sıradaki vade: 25.10.2026 • 500,00 ₺'), findsOneWidget);
      expect(find.text('Son hareketler'), findsOneWidget);
      expect(find.byType(LedgerEntryTile), findsOneWidget);
    });

    listMatrix('çok daire (iki site): toplam kartı + kartlar', (t, w, h, s, dark) async {
      final auth = FinanceFakeAuth.seeded()
        ..myFinanceItems = <Map<String, dynamic>>[
          finMyItem(),
          finMyItem(
            siteCode: 12,
            siteName: 'Mavi Park Evleri Çok Uzun Adlı Konut Yapı Kooperatifi',
            apartmentId: 502,
            label: 'Çok Uzun Bloklu Konut - 12',
            balance: -250000,
            overdue: 0,
            nextDueDate: null,
            nextDueMinor: null,
            recent: const <Map<String, dynamic>>[],
          ),
          finMyItem(apartmentId: 303, label: 'B Blok - 2', balance: 0, overdue: 0, nextDueDate: null, nextDueMinor: null),
        ];
      await _pump(t, auth, width: w, height: h, scale: s, dark: dark);
      expect(find.byKey(const ValueKey<String>('my_finance_totals')), findsOneWidget);
      expect(find.byType(MyFinanceCard), findsNWidgets(3));
    });

    listMatrix('yükleniyor / hata / boş / modül kapalı', (t, w, h, s, dark) async {
      final gate = Completer<void>();
      final loading = FinanceFakeAuth.seeded()..myFinanceGate = gate;
      await _pump(t, loading, width: w, height: h, scale: s, dark: dark);
      expect(find.byType(ListSkeleton), findsOneWidget);
      expect(find.textContaining('Borcunuz yok'), findsNothing);
      gate.complete();
      await settleFor(t);

      final failing = FinanceFakeAuth.seeded()..myFinanceError = ApiException('Sunucu hatası', statusCode: 500);
      await _pump(t, failing, width: w, height: h, scale: s, dark: dark);
      expect(find.byType(InlineNotice), findsWidgets);
      expect(find.text('Tekrar Dene'), findsOneWidget);
      expect(find.textContaining('Borcunuz yok'), findsNothing);

      final empty = FinanceFakeAuth.seeded();
      await _pump(t, empty, width: w, height: h, scale: s, dark: dark);
      expect(find.byKey(const ValueKey<String>('my_finance_none')), findsOneWidget);

      final off = FinanceFakeAuth.seeded()
        ..myFinanceError = ApiException('kapalı', statusCode: 403, code: 'MODULE_DISABLED');
      await _pump(t, off, width: w, height: h, scale: s, dark: dark);
      expect(find.byKey(const ValueKey<String>('my_finance_module_off')), findsOneWidget);
    });
  });

  group('bakiye durumları', () {
    testWidgets('borç / alacak / sıfır: simge + metin; "Borcunuz yok" YALNIZ sıfırken', (t) async {
      final debt = FinanceFakeAuth.seeded()..myFinanceItems = <Map<String, dynamic>>[finMyItem()];
      await _pump(t, debt);
      expect(find.text('Borcunuz yok.'), findsNothing);

      final credit = FinanceFakeAuth.seeded()
        ..myFinanceItems = <Map<String, dynamic>>[finMyItem(balance: -75050, overdue: 0, nextDueDate: null, nextDueMinor: null)];
      await _pump(t, credit);
      expect(find.text('Alacak'), findsOneWidget);
      expect(find.text('750,50 ₺'), findsOneWidget);
      expect(find.text('Borcunuz yok.'), findsNothing);

      final zero = FinanceFakeAuth.seeded()
        ..myFinanceItems = <Map<String, dynamic>>[finMyItem(balance: 0, overdue: 0, nextDueDate: null, nextDueMinor: null)];
      await _pump(t, zero);
      expect(find.text('Borç yok'), findsOneWidget);
      expect(find.text('Borcunuz yok.'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('my_finance_balance')), findsNothing);
    });

    testWidgets('vadesi geçen sıfırsa satır yok; vade yoksa "Sıradaki vade" yok', (t) async {
      final auth = FinanceFakeAuth.seeded()
        ..myFinanceItems = <Map<String, dynamic>>[
          finMyItem(overdue: 0, nextDueDate: null, nextDueMinor: null),
        ];
      await _pump(t, auth);
      expect(find.textContaining('Vadesi geçen'), findsNothing);
      expect(find.byKey(const ValueKey<String>('my_finance_next_due')), findsNothing);
    });

    testWidgets('çok daire: toplam borç ve toplam alacak ayrı toplanır (net değil)', (t) async {
      final auth = FinanceFakeAuth.seeded()
        ..myFinanceItems = <Map<String, dynamic>>[
          finMyItem(balance: 100000),
          finMyItem(apartmentId: 302, label: 'A Blok - 6', balance: -30000, overdue: 0, nextDueDate: null, nextDueMinor: null),
          finMyItem(apartmentId: 303, label: 'B Blok - 2', balance: 25050, overdue: 0, nextDueDate: null, nextDueMinor: null),
        ];
      await _pump(t, auth);
      final totals = find.byKey(const ValueKey<String>('my_finance_totals'));
      expect(find.descendant(of: totals, matching: find.text('Toplam borç 1.250,50 ₺')), findsOneWidget);
      expect(find.descendant(of: totals, matching: find.text('Toplam alacak 300,00 ₺')), findsOneWidget);
    });

    testWidgets('tek dairede toplam kartı yok', (t) async {
      final auth = FinanceFakeAuth.seeded()..myFinanceItems = <Map<String, dynamic>>[finMyItem()];
      await _pump(t, auth);
      expect(find.byKey(const ValueKey<String>('my_finance_totals')), findsNothing);
    });
  });

  group('hareketler ve gizlilik', () {
    testWidgets('yalnız görüntüleme: yazma düğmesi ve yönetici metni yok; "Online ödeme yakında" notu kalktı', (t) async {
      final auth = FinanceFakeAuth.seeded()..myFinanceItems = <Map<String, dynamic>>[finMyItem()];
      await _pump(t, auth);
      for (final text in const ['Tahsilat Ekle', 'Düzelt', 'İptal Et', 'Borçlandır', 'Ayı Kapat', 'Yeni Tanım']) {
        expect(find.text(text), findsNothing, reason: text);
      }
      expect(find.textContaining('Kaydeden:'), findsNothing);
      expect(find.textContaining('Neden:'), findsNothing);
      expect(find.byKey(const ValueKey<String>('my_finance_online_soon')), findsNothing);
      expect(find.text('Online ödeme yakında. Ödemelerinizi şimdilik site yönetimine yapabilirsiniz.'), findsNothing);
    });

    testWidgets('son hareketler ilk 5; "Tümünü göster" geri kalanını açar, "Daha az göster" kapatır', (t) async {
      final auth = FinanceFakeAuth.seeded()
        ..myFinanceItems = <Map<String, dynamic>>[finMyItem(recent: _manyEntries(12))];
      await _pump(t, auth);
      expect(find.byType(LedgerEntryTile), findsNWidgets(5));
      expect(find.text('Tümünü göster (7)'), findsOneWidget);
      await tapFinder(t, find.byKey(const ValueKey<String>('my_finance_toggle')));
      await settleFor(t);
      expect(find.byType(LedgerEntryTile), findsNWidgets(12));
      expect(find.text('Daha az göster'), findsOneWidget);
      await tapFinder(t, find.byKey(const ValueKey<String>('my_finance_toggle')));
      await settleFor(t);
      expect(find.byType(LedgerEntryTile), findsNWidgets(5));
    });

    testWidgets('hareket yoksa "Henüz hareket yok."', (t) async {
      final auth = FinanceFakeAuth.seeded()
        ..myFinanceItems = <Map<String, dynamic>>[finMyItem(recent: const <Map<String, dynamic>>[])];
      await _pump(t, auth);
      expect(find.text('Henüz hareket yok.'), findsOneWidget);
    });

    testWidgets('iptal edilen kayıt ve ters kayıt işaretli (neden sakine gösterilmez)', (t) async {
      final auth = FinanceFakeAuth.seeded()
        ..myFinanceItems = <Map<String, dynamic>>[
          finMyItem(
            recent: <Map<String, dynamic>>[
              <String, dynamic>{
                ...finEntry(7, 301, kind: 'reversal', amount: -50000, reverses: 2),
                'description': null,
                'reversal_reason': null,
                'created_by_name': null,
                'reversed_by_entry_id': null,
              },
              <String, dynamic>{
                ...finEntry(2, 301, amount: 50000, definitionName: 'Aylık aidat'),
                'description': null,
                'reversal_reason': null,
                'created_by_name': null,
                'reversed_by_entry_id': 7,
              },
            ],
          ),
        ];
      await _pump(t, auth);
      expect(find.text('Ters kayıt'), findsOneWidget);
      expect(find.text('İptal edildi'), findsOneWidget);
      expect(find.textContaining('Neden:'), findsNothing);
    });
  });

  group('yarışlar ve yenileme', () {
    testWidgets('reload() yeniden çeker; hata sonrası Tekrar Dene içerik getirir', (t) async {
      final auth = FinanceFakeAuth.seeded()
        ..myFinanceItems = <Map<String, dynamic>>[finMyItem()]
        ..myFinanceError = ApiException('Sunucu hatası', statusCode: 500);
      final key = await _pump(t, auth);
      expect(find.text('Sunucu hatası'), findsOneWidget);
      expect(find.textContaining('Borcunuz yok'), findsNothing);
      auth.myFinanceError = null;
      await tapFinder(t, find.text('Tekrar Dene'));
      await settleFor(t);
      expect(find.byType(MyFinanceCard), findsOneWidget);
      final calls = auth.myFinanceCalls;
      await key.currentState!.reload();
      await settleFor(t);
      expect(auth.myFinanceCalls, calls + 1);
    });

    testWidgets('yenileme hatası eski tutarı ekranda TUTMAZ (yanıltıcı olmasın)', (t) async {
      final auth = FinanceFakeAuth.seeded()..myFinanceItems = <Map<String, dynamic>>[finMyItem()];
      final key = await _pump(t, auth);
      expect(find.text('1.000,00 ₺'), findsOneWidget);
      auth.myFinanceError = ApiException('Sunucu hatası', statusCode: 500);
      await key.currentState!.reload();
      await settleFor(t);
      expect(find.text('1.000,00 ₺'), findsNothing);
      expect(find.text('Sunucu hatası'), findsOneWidget);
    });

    testWidgets('art arda yenilemede eski yanıt yenisini ezmez', (t) async {
      final auth = FinanceFakeAuth.seeded()..myFinanceItems = <Map<String, dynamic>>[finMyItem(balance: 100000)];
      final key = await _pump(t, auth);
      // Yavaş yenileme (eski bakiye anlık görüntüsü)...
      final slow = Completer<void>();
      auth.myFinanceGate = slow;
      unawaited(key.currentState!.reload());
      await t.pump();
      // ...bakiye değişti; yeni (hızlı) yenileme.
      auth.myFinanceItems = <Map<String, dynamic>>[
        finMyItem(balance: 0, overdue: 0, nextDueDate: null, nextDueMinor: null),
      ];
      auth.myFinanceGate = null;
      unawaited(key.currentState!.reload());
      await settleFor(t);
      expect(find.text('Borcunuz yok.'), findsOneWidget);
      slow.complete();
      await settleFor(t);
      expect(find.text('Borcunuz yok.'), findsOneWidget, reason: 'geç gelen ESKİ yanıt ezemez');
      expect(find.text('1.000,00 ₺'), findsNothing);
    });

    testWidgets('dispose sonrası gelen yanıt hata vermez', (t) async {
      final auth = FinanceFakeAuth.seeded()..myFinanceItems = <Map<String, dynamic>>[finMyItem()];
      final gate = Completer<void>();
      auth.myFinanceGate = gate;
      await _pump(t, auth);
      await t.pumpWidget(const SizedBox());
      gate.complete();
      await t.pump();
      expect(t.takeException(), isNull);
    });
  });

  group('erişilebilirlik ve ürün adı', () {
    testWidgets('kart tek birleşik ekran okuyucu etiketi: "Borç: bin lira"', (t) async {
      final handle = t.ensureSemantics();
      final auth = FinanceFakeAuth.seeded()..myFinanceItems = <Map<String, dynamic>>[finMyItem()];
      await _pump(t, auth);
      expect(find.bySemanticsLabel(RegExp(r'Borç: bin lira')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'Vadesi geçen: beş yüz lira')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Sıradaki vade: 25.10.2026, beş yüz lira')), findsOneWidget);
      handle.dispose();
    });

    test('finans dosyalarında "AHBU" / "JetPass" adı yok (ürün adı kuralı)', () {
      final files = <String>[
        'lib/models/finance.dart',
        'lib/ui/helpers/money.dart',
        'lib/ui/helpers/finance_errors.dart',
        'lib/ui/helpers/idempotency.dart',
        'lib/ui/views/finance_view.dart',
        'lib/ui/views/finance_balances_tab.dart',
        'lib/ui/views/finance_definitions_tab.dart',
        'lib/ui/views/finance_periods_tab.dart',
        'lib/ui/views/my_finance_view.dart',
        'lib/ui/dialogs/finance_account_dialog.dart',
        'lib/ui/dialogs/finance_definition_form_dialog.dart',
        'lib/ui/dialogs/finance_payment_dialog.dart',
        'lib/ui/dialogs/finance_reverse_dialog.dart',
        'lib/ui/dialogs/finance_run_dialog.dart',
        'lib/ui/widgets/finance_parts.dart',
        'lib/ui/widgets/finance_target_picker.dart',
        'lib/ui/widgets/fee_spec_form.dart',
        'lib/ui/widgets/money_field.dart',
      ];
      for (final path in files) {
        final source = File(path).readAsStringSync();
        expect(source.contains('AHBU'), isFalse, reason: path);
        expect(source.toLowerCase().contains('jetpass'), isFalse, reason: path);
        // Görünmez / yön denetim karakteri yok.
        for (final bad in const <int>[0x200B, 0x200E, 0x200F, 0x202A, 0x202B, 0x202C, 0x202D, 0x202E, 0x2066, 0x2067, 0x2068, 0x2069, 0xFEFF, 0x00A0]) {
          expect(source.runes.contains(bad), isFalse, reason: '$path: U+${bad.toRadixString(16)}');
        }
      }
    });
  });
  // ---------------------------------------------------------------------------------------------------
  // İnceleme düzeltmeleri (W10, W14): tutar okunuşu, kim öder bilgisi, yönetici notu ve kayıt numarası yok.
  // ---------------------------------------------------------------------------------------------------

  group('W10 / W14: sakin ekranı', () {
    testWidgets('toplam kartı tutarları okunuşla tek etiketle bildirir (rakam yığını değil)', (t) async {
      final auth = FinanceFakeAuth.seeded()
        ..myFinanceItems = <Map<String, dynamic>>[
          finMyItem(),
          finMyItem(
            siteCode: 12,
            siteName: 'Mavi Park',
            apartmentId: 502,
            label: 'C Blok - 1',
            balance: -250000,
            overdue: 0,
            nextDueDate: null,
            nextDueMinor: null,
            recent: const <Map<String, dynamic>>[],
          ),
        ];
      final handle = t.ensureSemantics();
      await _pump(t, auth);
      expect(
        find.bySemanticsLabel('Toplam borç: bin lira. Toplam alacak: iki bin beş yüz lira.'),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('sakin kapsamı: visible_from varsa başlangıç ayı notu görünür ve birleşik etikette okunur; yoksa not yok', (t) async {
      final auth = FinanceFakeAuth.seeded()
        ..myFinanceItems = <Map<String, dynamic>>[
          <String, dynamic>{...finMyItem(), 'visible_from': '2026-09'},
        ];
      final handle = t.ensureSemantics();
      await _pump(t, auth);
      const note = 'Kayıtlar Eylül 2026 ayından itibaren gösterilir; daha önceki dönem için site yönetiminize başvurun.';
      expect(find.byKey(const ValueKey<String>('my_finance_scope_note')), findsOneWidget);
      expect(find.text(note), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(RegExp.escape(note))), findsOneWidget);
      handle.dispose();

      final plain = FinanceFakeAuth.seeded()..myFinanceItems = <Map<String, dynamic>>[finMyItem()];
      await _pump(t, plain);
      expect(find.byKey(const ValueKey<String>('my_finance_scope_note')), findsNothing);
      expect(find.byKey(const ValueKey<String>('my_finance_offset_note')), findsNothing);
    });

    testWidgets('mahsup notu: offset_note true ise açıklama görünür ve birleşik etikette okunur', (t) async {
      final auth = FinanceFakeAuth.seeded()
        ..myFinanceItems = <Map<String, dynamic>>[
          <String, dynamic>{...finMyItem(), 'visible_from': '2026-09', 'offset_note': true},
        ];
      final handle = t.ensureSemantics();
      await _pump(t, auth);
      expect(find.byKey(const ValueKey<String>('my_finance_offset_note')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(RegExp.escape('vadesi en eski borçtan başlayarak mahsup edilir'))), findsOneWidget);
      handle.dispose();
    });

    testWidgets('daire kartının birleşik etiketi "kim öder" bilgisini de söyler', (t) async {
      final auth = FinanceFakeAuth.seeded()..myFinanceItems = <Map<String, dynamic>>[finMyItem()];
      final handle = t.ensureSemantics();
      await _pump(t, auth);
      expect(find.bySemanticsLabel(RegExp(r'Sıradaki vade: 25\.10\.2026, beş yüz lira\. Malik öder\.')), findsOneWidget);
      handle.dispose();
    });

    testWidgets('sunucu yönetici notu / iptal nedeni / kaydeden gönderse bile sakin görmez', (t) async {
      final entry = <String, dynamic>{
        ...finEntry(2, 301, amount: 50000, dueDate: '2026-10-25', definitionName: 'Aylık aidat'),
        'description': 'Yönetici notu: gizli',
        'reversal_reason': 'Gizli iptal nedeni',
        'created_by_name': 'Site Yöneticisi',
        'reversed_by_entry_id': null,
      };
      final tahsilat = <String, dynamic>{
        ...finEntry(7, 301, kind: 'payment', amount: -20000, method: 'cash'),
        'description': 'Yönetici notu: elden',
        'created_by_name': 'Site Yöneticisi',
        'reversed_by_entry_id': null,
      };
      final auth = FinanceFakeAuth.seeded()
        ..myFinanceItems = <Map<String, dynamic>>[
          finMyItem(recent: <Map<String, dynamic>>[entry, tahsilat]),
        ];
      await _pump(t, auth);
      expect(find.byType(LedgerEntryTile), findsNWidgets(2));
      expect(find.textContaining('Yönetici notu'), findsNothing);
      expect(find.textContaining('Gizli iptal nedeni'), findsNothing);
      expect(find.textContaining('Site Yöneticisi'), findsNothing);
      expect(find.textContaining('Neden:'), findsNothing);
    });

    testWidgets('ters kayıt satırı kayıt NUMARASI yazmaz; ilgili kaydın tarih ve tutarını yazar', (t) async {
      final original = <String, dynamic>{
        ...finEntry(2, 301, amount: 50000, entryDate: '2026-10-01', definitionName: 'Aylık aidat'),
        'reversed_by_entry_id': 9,
      };
      final reversal = <String, dynamic>{
        ...finEntry(9, 301, kind: 'reversal', amount: -50000, entryDate: '2026-10-05', reverses: 2),
        'reversed_by_entry_id': null,
      };
      final orphan = <String, dynamic>{
        ...finEntry(11, 301, kind: 'reversal', amount: -1000, entryDate: '2026-10-06', reverses: 4),
        'reversed_by_entry_id': null,
      };
      final auth = FinanceFakeAuth.seeded()
        ..myFinanceItems = <Map<String, dynamic>>[
          finMyItem(recent: <Map<String, dynamic>>[orphan, reversal, original]),
        ];
      await _pump(t, auth);
      expect(find.text('Şu kaydın ters kaydı: 01.10.2026 • 500,00 ₺'), findsOneWidget);
      expect(find.text('Ters kayıtla iptal edildi: 05.10.2026 • 500,00 ₺'), findsOneWidget);
      expect(find.text('Daha önceki bir kaydın ters kaydı'), findsOneWidget, reason: 'ilgili kayıt listede yoksa genel metin');
      expect(find.textContaining('#'), findsNothing);
      expect(find.textContaining('numaralı'), findsNothing);
    });
  });
  testWidgets('W11: Borcum 502 (metinsiz): teknik metin yok, Türkçe yedek var; "Borcunuz yok" demez', (t) async {
    final auth = FinanceFakeAuth.seeded()
      ..myFinanceError = ApiException('İşlem başarısız (502)', statusCode: 502, genericFallback: true);
    await _pump(t, auth);
    expect(find.text('Borç bilgisi yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.'), findsOneWidget);
    expect(find.textContaining('502'), findsNothing);
    expect(find.textContaining('Borcunuz yok'), findsNothing);
  });
}
