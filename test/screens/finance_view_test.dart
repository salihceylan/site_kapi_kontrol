// Platform Faz 4a: yönetici "Finans" ekranı (FinanceView) ve sekmeleri (Daireler / Tanımlar / Dönemler).
//
// AGENTS.md kural 6: 320x640 x2,0 ve 360x640 x1,5, açık + koyu tema; yükleniyor / boş / hata / dolu durumlar
// taşmaz. Kural 7: yenile düğmesi ve `reload()` çalışır. Yarış korumaları: art arda arama, süzgeç, site
// değişimi. Kurul üyesi SALT OKUNUR (hiçbir yazma düğmesi yok). Modül kapalıysa sekme yerine bilgi. Hata asla
// "borç yok / daire yok / tanım yok" demez.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/finance.dart';
import 'package:site_kapi_kontrol/models/site_record.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart' show InlineNotice;
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/views/finance_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

import 'dialog_layout_harness.dart' show settleFor;
import 'finance_fixtures.dart';
import 'list_fixtures.dart';
import 'people_fixtures.dart';

final DateTime _now = DateTime.utc(2026, 10, 16, 9);

const UserRole _superRole = UserRole.superUser;

const List<PeopleSite> _manage = <PeopleSite>[PeopleSite(code: 11, name: 'Gül Sitesi', canWrite: true)];
const List<PeopleSite> _board = <PeopleSite>[PeopleSite(code: 11, name: 'Gül Sitesi')];

Future<GlobalKey<FinanceViewState>> _pump(
  WidgetTester t,
  FinanceFakeAuth auth, {
  List<PeopleSite> sites = _manage,
  bool manageAll = false,
  bool canReopen = false,
  VoidCallback? onOpenModules,
  double width = 400,
  double height = 2400,
  double scale = 1.0,
  bool dark = false,
}) async {
  final key = GlobalKey<FinanceViewState>();
  await pumpList(
    t,
    FinanceView(
      key: key,
      authService: auth,
      manageAllSites: manageAll,
      sites: sites,
      canReopen: canReopen,
      onOpenModules: onOpenModules,
      now: () => _now,
    ),
    width: width,
    height: height,
    scale: scale,
    dark: dark,
  );
  await settleFor(t, 100);
  await settleFor(t, 100);
  return key;
}

Future<void> _tab(WidgetTester t, int index) async {
  await tapFinder(t, find.byKey(ValueKey<String>('finance_tab_$index')));
  await settleFor(t);
}

Finder _card(String text) => find.widgetWithText(BalanceRowCard, text);

Future<void> _debounce(WidgetTester t) async {
  await t.pump(const Duration(milliseconds: 400));
  await t.pump();
}

void main() {
  group('taşma matrisi', () {
    listMatrix('Daireler sekmesi: özet kartı, eylemler, bakiye kartları', (t, w, h, s, dark) async {
      final auth = FinanceFakeAuth.seeded();
      await _pump(t, auth, width: w, height: h, scale: s, dark: dark);
      expect(find.byType(FinanceSummaryCard), findsOneWidget);
      expect(find.byType(BalanceRowCard), findsNWidgets(3));
      expect(find.text('Tahsilat Ekle'), findsOneWidget);
      expect(find.text('Ek Borç Ekle'), findsOneWidget);
      for (final label in const ['Daireler', 'Tanımlar', 'Dönemler']) {
        expect(find.widgetWithText(ChoiceChip, label), findsOneWidget, reason: label);
      }
    });

    listMatrix('Tanımlar sekmesi: aktif + pasif kart, eylem düğmeleri', (t, w, h, s, dark) async {
      final auth = FinanceFakeAuth.seeded();
      await _pump(t, auth, width: w, height: h, scale: s, dark: dark);
      await _tab(t, 1);
      expect(find.byType(FeeDefinitionCard), findsNWidgets(2));
      expect(find.text('Yeni Tanım'), findsOneWidget);
      expect(find.text('Borçlandır'), findsOneWidget, reason: 'yalnız aktif tanımda');
      expect(find.text('Etkinleştir'), findsOneWidget, reason: 'pasif tanımda');
    });

    listMatrix('Dönemler sekmesi: açık ay + kapalı aylar', (t, w, h, s, dark) async {
      final auth = FinanceFakeAuth.seeded()..closedPeriods.addAll(<String>['2026-08', '2026-09']);
      await _pump(t, auth, width: w, height: h, scale: s, dark: dark, canReopen: true);
      await _tab(t, 2);
      expect(find.byKey(const ValueKey<String>('finance_open_period')), findsOneWidget);
      expect(find.text('Ekim 2026'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_closed_2026-09')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_closed_2026-08')), findsOneWidget);
    });

    listMatrix('yükleniyor: özet ve liste iskeleti; "borç yok / daire yok" yazılmaz', (t, w, h, s, dark) async {
      final auth = FinanceFakeAuth.seeded()
        ..summaryGate = Completer<void>()
        ..balanceGates.add(Completer<void>());
      await _pump(t, auth, width: w, height: h, scale: s, dark: dark);
      expect(find.byType(ListSkeleton), findsWidgets);
      expect(find.byType(BalanceRowCard), findsNothing);
      expect(find.byType(FinanceSummaryCard), findsNothing);
      expect(find.text('Bu sitede daire bulunamadı.'), findsNothing);
      expect(find.text('Borç yok'), findsNothing);
    });

    listMatrix('hata: özet ve liste için InlineNotice + Tekrar Dene', (t, w, h, s, dark) async {
      final auth = FinanceFakeAuth.seeded()
        ..summaryError = ApiException('Sunucu hatası', statusCode: 500)
        ..balancesError = ApiException('Liste hatası', statusCode: 500);
      await _pump(t, auth, width: w, height: h, scale: s, dark: dark);
      expect(find.byType(InlineNotice), findsNWidgets(2));
      expect(find.text('Tekrar Dene'), findsNWidgets(2));
      expect(find.byType(FinanceSummaryCard), findsNothing, reason: 'özet okunamadıysa uydurma sıfırlar gösterilmez');
      expect(find.byType(BalanceRowCard), findsNothing);
      expect(find.text('Bu sitede daire bulunamadı.'), findsNothing);
    });

    listMatrix('modül kapalı: sekmeler yerine bilgi + Modüller düğmesi', (t, w, h, s, dark) async {
      final auth = FinanceFakeAuth.seeded()..moduleEnabled = false;
      await _pump(t, auth, width: w, height: h, scale: s, dark: dark, onOpenModules: () {});
      expect(find.byKey(const ValueKey<String>('finance_module_off')), findsOneWidget);
      expect(find.text('Aidat ve Finans bu site için kapalı.'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_open_modules')), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Daireler'), findsNothing);
      expect(find.text('Tahsilat Ekle'), findsNothing);
    });

    listMatrix('kurul üyesi (salt okunur): not var, HİÇBİR yazma düğmesi yok', (t, w, h, s, dark) async {
      final auth = FinanceFakeAuth.seeded();
      await _pump(t, auth, sites: _board, width: w, height: h, scale: s, dark: dark);
      expect(find.byKey(const ValueKey<String>('finance_read_only_note')), findsOneWidget);
      expect(find.text('Yönetim kurulu üyesi olarak mali kayıtları yalnızca görüntüleyebilirsiniz.'), findsOneWidget);
      expect(find.text('Tahsilat Ekle'), findsNothing);
      expect(find.text('Ek Borç Ekle'), findsNothing);
      await _tab(t, 1);
      expect(find.text('Yeni Tanım'), findsNothing);
      expect(find.text('Borçlandır'), findsNothing);
      expect(find.text('Düzenle'), findsNothing);
      expect(find.text('Pasifleştir'), findsNothing);
      expect(find.text('Etkinleştir'), findsNothing);
      await _tab(t, 2);
      expect(find.text('Ayı Kapat'), findsNothing);
      expect(find.text('Yeniden Aç'), findsNothing);
    });
  });

  group('özet ve eylemler', () {
    testWidgets('özet kartı sunucu tutarlarını gösterir (kuruştan biçimlenir)', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _pump(t, auth);
      expect(auth.summaryCalls, 1);
      final card = find.byType(FinanceSummaryCard);
      expect(find.descendant(of: card, matching: find.text('Toplam borç')), findsOneWidget);
      expect(find.descendant(of: card, matching: find.text('1.000,00 ₺')), findsOneWidget);
      expect(find.descendant(of: card, matching: find.text('300,00 ₺')), findsOneWidget);
      expect(find.descendant(of: card, matching: find.text('Ekim 2026 borçlandırılan')), findsOneWidget);
      expect(find.descendant(of: card, matching: find.text('500,00 ₺')), findsOneWidget);
      expect(find.descendant(of: card, matching: find.text('Ekim 2026 tahsil edilen')), findsOneWidget);
      expect(find.descendant(of: card, matching: find.text('Borçlu daire')), findsOneWidget);
      expect(find.text('Açık dönem: Ekim 2026'), findsOneWidget);
    });

    testWidgets('Tahsilat Ekle: kayıt sonrası özet ve liste yenilenir, bildirim gösterilir', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _pump(t, auth);
      final summaryBefore = auth.summaryCalls;
      final balancesBefore = auth.balanceCalls.length;
      await tapFinder(t, find.byKey(const ValueKey<String>('finance_add_payment')));
      await settleFor(t);
      // Daire seçici -> 303, 750 TL nakit.
      await tapFinder(t, find.byKey(const ValueKey<String>('finance_payment_apartment')));
      await settleFor(t);
      await tapFinder(t, find.descendant(of: find.byType(AlertDialog).last, matching: find.text('B Blok - 2')));
      await settleFor(t);
      await t.enterText(find.byKey(const ValueKey<String>('finance_payment_amount')), '750');
      await t.pump();
      await tapFinder(t, find.byKey(const ValueKey<String>('finance_method_cash')));
      await tapFinder(t, find.byKey(const ValueKey<String>('finance_payment_submit')));
      await settleFor(t);

      expect(auth.paymentCalls.single['apartment_id'], 303);
      expect(auth.paymentCalls.single['amount_minor'], 75000);
      expect(auth.summaryCalls, greaterThan(summaryBefore));
      expect(auth.balanceCalls.length, greaterThan(balancesBefore));
      expect(find.textContaining('Tahsilat kaydedildi: 750,00 ₺.'), findsOneWidget, reason: 'bildirim');
      // 303 artık alacaklı.
      expect(find.descendant(of: _card('B Blok - 2'), matching: find.text('Alacak 750,00 ₺')), findsOneWidget);
    });

    testWidgets('Ek Borç Ekle: önizleme -> onay -> özet ve liste yenilenir', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _pump(t, auth);
      await tapFinder(t, find.byKey(const ValueKey<String>('finance_add_charge')));
      await settleFor(t);
      await t.enterText(find.byKey(const ValueKey<String>('finance_charge_name')), 'Boya');
      await t.pump();
      await tapFinder(t, find.byKey(const ValueKey<String>('charge_spec_dist_fixed')));
      await t.enterText(find.byKey(const ValueKey<String>('charge_spec_amount')), '100');
      await t.pump();
      await tapFinder(t, find.byKey(const ValueKey<String>('finance_run_preview')));
      await settleFor(t);
      await tapFinder(t, find.byKey(const ValueKey<String>('finance_run_confirm')));
      await settleFor(t);
      expect(auth.chargePostCalls.length, 1);
      expect(find.textContaining('Ek borç yazıldı: 3 daire, toplam 300,00 ₺.'), findsOneWidget);
      // 301: 1.000 + 100 = 1.100 borç.
      expect(find.descendant(of: _card('A Blok - 5'), matching: find.text('Borç 1.100,00 ₺')), findsOneWidget);
    });

    testWidgets('çift dokunuş: Tahsilat Ekle penceresi tek kez açılır', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _pump(t, auth);
      final button = find.byKey(const ValueKey<String>('finance_add_payment'));
      await t.ensureVisible(button);
      await t.pump();
      await t.tap(button);
      await t.tap(button, warnIfMissed: false);
      await settleFor(t);
      expect(find.byType(AlertDialog), findsOneWidget);
    });
  });

  group('Daireler sekmesi', () {
    testWidgets('bakiye kartı: simge + metin; vadesi geçen; malik / kiracı adı', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _pump(t, auth);
      final c301 = _card('A Blok - 5');
      expect(find.descendant(of: c301, matching: find.text('Borç 1.000,00 ₺')), findsOneWidget);
      expect(find.descendant(of: c301, matching: find.text('Vadesi geçen 500,00 ₺')), findsOneWidget);
      expect(find.descendant(of: c301, matching: find.text('Malik: Ayşe Yılmaz')), findsOneWidget);
      final c302 = _card('A Blok - 6');
      expect(find.descendant(of: c302, matching: find.text('Alacak 300,00 ₺')), findsOneWidget);
      expect(find.descendant(of: c302, matching: find.text('Kiracı: Mehmet Demir')), findsOneWidget);
      expect(find.descendant(of: _card('B Blok - 2'), matching: find.text('Borç yok')), findsOneWidget);
    });

    testWidgets('arama: 350 ms bekler, sorguya yazar; temizle düğmesi; sonuç yoksa süzgeçli boş durum', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _pump(t, auth);
      final field = find.byKey(const ValueKey<String>('finance_balances_search'));
      await t.enterText(field, 'mehmet');
      await t.pump(const Duration(milliseconds: 200));
      expect(auth.balanceCalls.length, 1, reason: 'bekleme dolmadan istek yok');
      await _debounce(t);
      await settleFor(t);
      expect(auth.balanceCalls.last.query, 'mehmet');
      expect(find.byType(BalanceRowCard), findsOneWidget);

      await t.enterText(field, 'yok böyle biri');
      await _debounce(t);
      await settleFor(t);
      expect(find.text('Bu arama ve süzgeç için daire bulunamadı.'), findsOneWidget);

      await t.tap(find.byTooltip('Aramayı temizle'));
      await settleFor(t);
      expect(find.byType(BalanceRowCard), findsNWidgets(3));
    });

    testWidgets('durum süzgeci: Borçlu / Alacaklı / Hepsi sunucuya status olarak gider', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _pump(t, auth);
      await tapFinder(t, find.byKey(const ValueKey<String>('finance_balance_filter_debtor')));
      await settleFor(t);
      expect(auth.balanceCalls.last.status, 'debtor');
      expect(find.byType(BalanceRowCard), findsOneWidget);
      await tapFinder(t, find.byKey(const ValueKey<String>('finance_balance_filter_credit')));
      await settleFor(t);
      expect(auth.balanceCalls.last.status, 'credit');
      expect(find.text('A Blok - 6'), findsOneWidget);
      await tapFinder(t, find.byKey(const ValueKey<String>('finance_balance_filter_all')));
      await settleFor(t);
      expect(auth.balanceCalls.last.status, 'all');
      expect(find.byType(BalanceRowCard), findsNWidgets(3));
    });

    testWidgets('hızlı art arda süzgeç: eski yanıt yenisini ezmez', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _pump(t, auth);
      final slow = Completer<void>();
      auth.balanceGates.add(slow); // sıradaki ilk istek (Borçlu) yavaş
      await tapFinder(t, find.byKey(const ValueKey<String>('finance_balance_filter_debtor')));
      await tapFinder(t, find.byKey(const ValueKey<String>('finance_balance_filter_credit')));
      await settleFor(t);
      expect(find.byType(BalanceRowCard), findsOneWidget);
      expect(find.text('A Blok - 6'), findsOneWidget, reason: 'Alacaklı sonucu');
      slow.complete();
      await settleFor(t);
      expect(find.text('A Blok - 6'), findsOneWidget, reason: 'geç gelen Borçlu yanıtı Alacaklı listesini ezmez');
      expect(find.text('A Blok - 5'), findsNothing);
    });

    testWidgets('sayfalama: "Daha fazla yükle" offset ile sonraki sayfayı ekler', (t) async {
      final auth = FinanceFakeAuth.seeded()..maxPage = 2;
      await _pump(t, auth);
      expect(find.byType(BalanceRowCard), findsNWidgets(2));
      await tapText(t, 'Daha fazla yükle');
      await settleFor(t);
      expect(auth.balanceCalls.last.offset, 2);
      expect(find.byType(BalanceRowCard), findsNWidgets(3));
      expect(find.text('Daha fazla yükle'), findsNothing);
    });

    testWidgets('hata sonrası Tekrar Dene içerik getirir; hata sırasında "daire yok" yazılmaz', (t) async {
      final auth = FinanceFakeAuth.seeded()..balancesError = ApiException('Liste hatası', statusCode: 500);
      await _pump(t, auth);
      expect(find.text('Liste hatası'), findsOneWidget);
      expect(find.text('Bu sitede daire bulunamadı.'), findsNothing);
      auth.balancesError = null;
      final retry = find.descendant(
        of: find.ancestor(of: find.text('Liste hatası'), matching: find.byType(InlineNotice)),
        matching: find.text('Tekrar Dene'),
      );
      await tapFinder(t, retry);
      await settleFor(t);
      expect(find.byType(BalanceRowCard), findsNWidgets(3));
    });

    testWidgets('daireye dokununca ekstre açılır; ekstreden tahsilat sonrası liste yenilenir', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _pump(t, auth);
      await tapFinder(t, _card('A Blok - 5'));
      await settleFor(t);
      expect(find.text('Hesap Ekstresi'), findsOneWidget);
      expect(auth.accountCalls.single.apartment, 301);
      final balancesBefore = auth.balanceCalls.length;
      await tapFinder(t, find.byKey(const ValueKey<String>('finance_account_add_payment')));
      await settleFor(t);
      await t.enterText(find.byKey(const ValueKey<String>('finance_payment_amount')), '1.000');
      await t.pump();
      await tapFinder(t, find.byKey(const ValueKey<String>('finance_method_transfer')));
      await tapFinder(t, find.byKey(const ValueKey<String>('finance_payment_submit')));
      await settleFor(t);
      expect(auth.balanceCalls.length, greaterThan(balancesBefore), reason: 'ekstredeki yazma listeyi tazeler');
    });

    testWidgets('çekip yenileme (reload) siteyi, özeti ve listeyi yeniden çeker', (t) async {
      final auth = FinanceFakeAuth.seeded();
      final key = await _pump(t, auth);
      final summary = auth.summaryCalls;
      final balances = auth.balanceCalls.length;
      await key.currentState!.reload();
      await settleFor(t);
      expect(auth.summaryCalls, greaterThan(summary));
      expect(auth.balanceCalls.length, greaterThan(balances));
    });
  });

  group('Tanımlar sekmesi', () {
    testWidgets('süzgeçler tür / durumu sorguya yazar; süzgeçli boş durum', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _pump(t, auth);
      await _tab(t, 1);
      expect(auth.definitionListCalls.last.kind, isNull);
      expect(auth.definitionListCalls.last.active, isNull);
      await tapFinder(t, find.byKey(const ValueKey<String>('finance_active_filter_passive')));
      await settleFor(t);
      expect(auth.definitionListCalls.last.active, false);
      expect(find.byType(FeeDefinitionCard), findsOneWidget);
      expect(find.text('Yönetim gideri'), findsOneWidget);
      await tapFinder(t, find.byKey(const ValueKey<String>('finance_kind_filter_one_time')));
      await settleFor(t);
      expect(auth.definitionListCalls.last.kind, FeeKind.oneTime);
      expect(find.text('Bu süzgeç için tanım bulunamadı.'), findsOneWidget);
    });

    testWidgets('kartta dağıtım, tutar, vade, hedef, son borçlandırma görünür', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _pump(t, auth);
      await _tab(t, 1);
      final aidat = find.byKey(const ValueKey<String>('fee_definition_1'));
      expect(find.descendant(of: aidat, matching: find.text('Aylık aidat')), findsNWidgets(2), reason: 'tür çipi + ad');
      expect(find.descendant(of: aidat, matching: find.textContaining('Sabit tutar • Daire başı 500,00 ₺')), findsOneWidget);
      expect(find.descendant(of: aidat, matching: find.textContaining("Her ayın 15'i")), findsOneWidget);
      expect(find.descendant(of: aidat, matching: find.text('Hedef: Tüm site')), findsOneWidget);
      expect(find.descendant(of: aidat, matching: find.text('Son borçlandırma: Eylül 2026')), findsOneWidget);
      expect(find.descendant(of: aidat, matching: find.text('Aktif')), findsOneWidget);
      final gider = find.byKey(const ValueKey<String>('fee_definition_2'));
      expect(find.descendant(of: gider, matching: find.text('Pasif')), findsOneWidget);
      expect(find.descendant(of: gider, matching: find.text('Henüz borçlandırılmadı')), findsOneWidget);
    });

    testWidgets('Yeni Tanım -> liste yenilenir', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _pump(t, auth);
      await _tab(t, 1);
      await tapFinder(t, find.byKey(const ValueKey<String>('finance_definition_create')));
      await settleFor(t);
      await t.enterText(find.byKey(const ValueKey<String>('finance_definition_name')), 'Yeni aidat');
      await t.pump();
      await t.enterText(find.byKey(const ValueKey<String>('def_spec_amount')), '750');
      await t.pump();
      await tapFinder(t, find.byKey(const ValueKey<String>('finance_definition_submit')));
      await settleFor(t);
      expect(auth.definitionCreateCalls.length, 1);
      expect(find.byType(FeeDefinitionCard), findsNWidgets(3));
      expect(find.text('Tanım eklendi.'), findsOneWidget);
    });

    testWidgets('Pasifleştir: onay penceresi, PATCH is_active:false; Vazgeç istek yapmaz; Etkinleştir onaysız', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _pump(t, auth);
      await _tab(t, 1);
      await tapFinder(t, find.byKey(const ValueKey<String>('fee_definition_toggle_1')));
      await settleFor(t);
      expect(find.text('Tanımı pasifleştir'), findsOneWidget);
      await tapText(t, 'Vazgeç');
      await settleFor(t);
      expect(auth.definitionUpdateCalls, isEmpty);

      await tapFinder(t, find.byKey(const ValueKey<String>('fee_definition_toggle_1')));
      await settleFor(t);
      await tapFinder(t, find.descendant(of: find.byType(AlertDialog).last, matching: find.text('Pasifleştir')));
      await settleFor(t);
      expect(auth.definitionUpdateCalls.single.fields, <String, Object?>{'is_active': false});
      expect(find.text('Tanım pasifleştirildi.'), findsOneWidget);
      expect(auth.definitions[1]!['is_active'], false);

      await tapFinder(t, find.byKey(const ValueKey<String>('fee_definition_toggle_2')));
      await settleFor(t);
      expect(auth.definitionUpdateCalls.last.fields, <String, Object?>{'is_active': true});
      expect(auth.definitions[2]!['is_active'], true);
    });

    testWidgets('Pasifleştirme hatası: mesaj gösterilir, kart değişmez', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _pump(t, auth);
      await _tab(t, 1);
      auth.finError = ApiException('Bu işlem için yetkiniz yok.', statusCode: 403, code: 'FORBIDDEN_ROLE');
      await tapFinder(t, find.byKey(const ValueKey<String>('fee_definition_toggle_2')));
      await settleFor(t);
      expect(find.text('Bu işlem için yetkiniz yok.'), findsOneWidget);
      expect(auth.definitions[2]!['is_active'], false);
    });

    testWidgets('Borçlandır -> pencere; tek seferlik ve borçlandırılmış tanımda "Borçlandır" yok', (t) async {
      final auth = FinanceFakeAuth.seeded()
        ..definitions[8] = finDefinition(8, name: 'Boya', kind: 'one_time', distribution: 'equal', amount: 90000, lastPosted: '2026-10');
      await _pump(t, auth);
      await _tab(t, 1);
      expect(find.byKey(const ValueKey<String>('fee_definition_post_8')), findsNothing,
          reason: 'tek seferlik tanım yalnız bir kez çalışır');
      expect(find.byKey(const ValueKey<String>('fee_definition_post_2')), findsNothing, reason: 'pasif tanım');
      await tapFinder(t, find.byKey(const ValueKey<String>('fee_definition_post_1')));
      await settleFor(t);
      expect(find.text('Borçlandır'), findsWidgets);
      expect(find.byKey(const ValueKey<String>('finance_period_label')), findsOneWidget);
    });

    testWidgets('liste hatası: Tekrar Dene; "tanım yok" yazılmaz', (t) async {
      final auth = FinanceFakeAuth.seeded()..definitionsError = ApiException('Tanım hatası', statusCode: 500);
      await _pump(t, auth);
      await _tab(t, 1);
      expect(find.text('Tanım hatası'), findsOneWidget);
      expect(find.text('Henüz tanım yok.'), findsNothing);
    });

    testWidgets('boş liste: Yeni Tanım yönlendirmesi (yazma yetkisi olanda)', (t) async {
      final auth = FinanceFakeAuth.seeded()..definitions.clear();
      await _pump(t, auth);
      await _tab(t, 1);
      expect(find.text('Henüz tanım yok.'), findsOneWidget);
      expect(find.textContaining('Yeni Tanım ile'), findsOneWidget);
    });
  });

  group('Dönemler sekmesi', () {
    testWidgets('Ayı Kapat: onay -> sunucunun bildirdiği AÇIK ay kapatılır -> liste ve özet yenilenir', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _pump(t, auth);
      await _tab(t, 2);
      final summary = auth.summaryCalls;
      await tapFinder(t, find.byKey(const ValueKey<String>('finance_close_period')));
      await settleFor(t);
      expect(find.text('Ekim 2026 ayını kapat'), findsOneWidget);
      await tapText(t, 'Vazgeç');
      await settleFor(t);
      expect(auth.periodCalls, isEmpty);

      await tapFinder(t, find.byKey(const ValueKey<String>('finance_close_period')));
      await settleFor(t);
      await tapFinder(t, find.descendant(of: find.byType(AlertDialog).last, matching: find.text('Ayı Kapat')));
      await settleFor(t);
      expect(auth.periodCalls, <String>['close 2026-10']);
      expect(find.text('Ekim 2026 kapatıldı.'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_closed_2026-10')), findsOneWidget);
      expect(find.text('Kasım 2026'), findsOneWidget, reason: 'yeni açık ay');
      expect(auth.summaryCalls, greaterThan(summary));
    });

    testWidgets('kapatma reddi (PERIOD_NOT_CLOSABLE): Türkçe mesaj, durum yeniden okunur', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _pump(t, auth);
      await _tab(t, 2);
      final before = auth.periodsGetCalls;
      auth.paymentError = ApiException(
        AuthApi.messageForErrorCode('PERIOD_NOT_CLOSABLE')!,
        statusCode: 409,
        code: 'PERIOD_NOT_CLOSABLE',
      );
      await tapFinder(t, find.byKey(const ValueKey<String>('finance_close_period')));
      await settleFor(t);
      await tapFinder(t, find.descendant(of: find.byType(AlertDialog).last, matching: find.text('Ayı Kapat')));
      await settleFor(t);
      expect(find.text(AuthApi.messageForErrorCode('PERIOD_NOT_CLOSABLE')!), findsOneWidget);
      expect(auth.periodsGetCalls, greaterThan(before));
    });

    testWidgets('Yeniden Aç: yalnız süper kullanıcıda ve yalnız EN SON kapalı ayda', (t) async {
      final auth = FinanceFakeAuth.seeded()..closedPeriods.addAll(<String>['2026-08', '2026-09']);
      await _pump(t, auth);
      await _tab(t, 2);
      expect(find.text('Yeniden Aç'), findsNothing, reason: 'yönetici yeniden açamaz');

      final superAuth = FinanceFakeAuth.seeded(role: _superRole)..closedPeriods.addAll(<String>['2026-08', '2026-09']);
      await _pump(t, superAuth, canReopen: true);
      await _tab(t, 2);
      expect(find.byKey(const ValueKey<String>('finance_reopen_2026-09')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_reopen_2026-08')), findsNothing, reason: 'yalnız en son');
      await tapFinder(t, find.byKey(const ValueKey<String>('finance_reopen_2026-09')));
      await settleFor(t);
      expect(find.text('Eylül 2026 ayını yeniden aç'), findsOneWidget);
      await tapFinder(t, find.descendant(of: find.byType(AlertDialog).last, matching: find.text('Yeniden Aç')));
      await settleFor(t);
      expect(superAuth.periodCalls, <String>['reopen 2026-09']);
      expect(find.text('Eylül 2026 yeniden açıldı.'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_closed_2026-09')), findsNothing);
    });

    testWidgets('dönem hatası: Tekrar Dene; "kapalı ay yok" yazılmaz', (t) async {
      final auth = FinanceFakeAuth.seeded()..periodsError = ApiException('Dönem hatası', statusCode: 500);
      await _pump(t, auth);
      await _tab(t, 2);
      expect(find.text('Dönem hatası'), findsOneWidget);
      expect(find.text('Henüz kapatılmış ay yok.'), findsNothing);
      auth.periodsError = null;
      await tapText(t, 'Tekrar Dene');
      await settleFor(t);
      expect(find.text('Henüz kapatılmış ay yok.'), findsOneWidget);
    });
  });

  group('modül kapalı ve site seçimi', () {
    testWidgets('modül kapalı: sekmeler yok, Modüller düğmesi geri çağrıyı çalıştırır', (t) async {
      var opened = 0;
      final auth = FinanceFakeAuth.seeded()..moduleEnabled = false;
      await _pump(t, auth, onOpenModules: () => opened++);
      await tapFinder(t, find.byKey(const ValueKey<String>('finance_open_modules')));
      expect(opened, 1);
    });

    testWidgets('modül açılınca (Yenile sonrası) sekmeler döner', (t) async {
      final auth = FinanceFakeAuth.seeded()..moduleEnabled = false;
      final key = await _pump(t, auth);
      expect(find.byKey(const ValueKey<String>('finance_module_off')), findsOneWidget);
      auth.moduleEnabled = true;
      await key.currentState!.reload();
      await settleFor(t);
      expect(find.byKey(const ValueKey<String>('finance_module_off')), findsNothing);
      expect(find.byType(FinanceSummaryCard), findsOneWidget);
    });

    testWidgets('iki site: seçici yalnız site adı gösterir (kod yok); değişince özet yeniden çekilir', (t) async {
      final auth = FinanceFakeAuth.seeded();
      final sites = <PeopleSite>[
        const PeopleSite(code: 11, name: 'Gül Sitesi', canWrite: true),
        const PeopleSite(code: 12, name: 'Mavi Park', canWrite: true),
      ];
      await _pump(t, auth, sites: sites);
      expect(find.text('Gül Sitesi'), findsOneWidget);
      expect(find.textContaining('(11)'), findsNothing);
      final summary = auth.summaryCalls;
      await tapFinder(t, find.byType(DropdownButtonFormField<int>));
      await tapFinder(t, find.text('Mavi Park').last);
      await settleFor(t);
      expect(auth.summaryCalls, greaterThan(summary));
      expect(auth.balanceCalls.last.site, 12);
    });

    testWidgets('site değişirken eski sitenin özet yanıtı yeni sitenin ekranına yazılmaz', (t) async {
      final auth = FinanceFakeAuth.seeded();
      final sites = <PeopleSite>[
        const PeopleSite(code: 11, name: 'Gül Sitesi', canWrite: true),
        const PeopleSite(code: 12, name: 'Mavi Park', canWrite: true),
      ];
      auth.summaryGate = Completer<void>();
      await _pump(t, auth, sites: sites);
      expect(find.byType(FinanceSummaryCard), findsNothing, reason: 'yanıt bekleniyor');
      // Yeni site seçilir; yeni özet de aynı kapıyı bekler. Kapı açılınca yalnız SON istek uygulanır.
      await tapFinder(t, find.byType(DropdownButtonFormField<int>));
      await tapFinder(t, find.text('Mavi Park').last);
      await t.pump();
      auth.summaryGate!.complete();
      await settleFor(t);
      expect(find.byType(FinanceSummaryCard), findsOneWidget);
    });

    testWidgets('hiç site yok: "Kayıtlı site bulunamadı."', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _pump(t, auth, sites: const <PeopleSite>[]);
      expect(find.text('Kayıtlı site bulunamadı.'), findsOneWidget);
      expect(find.byType(FinanceSummaryCard), findsNothing);
    });

    testWidgets('süper kullanıcı: tüm onaylı siteler listelenir ve yazma yetkisi vardır', (t) async {
      final auth = FinanceFakeAuth.seeded(role: _superRole);
      auth.sites = <SiteRecord>[
        pplSite(11, 'Gül Sitesi'),
        pplSite(12, 'Mavi Park'),
        pplSite(13, 'Onay Bekleyen', approval: 'pending'),
      ];
      await _pump(t, auth, sites: const <PeopleSite>[], manageAll: true);
      expect(auth.listSitesArgs.first.approval, 'approved');
      expect(find.text('Tahsilat Ekle'), findsOneWidget);
      await tapFinder(t, find.byType(DropdownButtonFormField<int>));
      expect(find.text('Mavi Park'), findsWidgets);
      expect(find.text('Onay Bekleyen'), findsNothing);
    });

    testWidgets('site listesi yüklenemezse hata + Tekrar Dene', (t) async {
      final auth = FinanceFakeAuth.seeded(role: _superRole)..listSitesError = ApiException('Siteler yüklenemedi', statusCode: 500);
      await _pump(t, auth, sites: const <PeopleSite>[], manageAll: true);
      expect(find.text('Siteler yüklenemedi'), findsOneWidget);
      expect(find.text('Kayıtlı site bulunamadı.'), findsNothing);
    });
  });
}
