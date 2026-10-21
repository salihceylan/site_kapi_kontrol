// Platform Faz 4a: yönetici "Finans" ekranı (FinanceView) ve sekmeleri (Daireler / Tanımlar / Dönemler).
//
// AGENTS.md kural 6: 320x640 x2,0 ve 360x640 x1,5, açık + koyu tema; yükleniyor / boş / hata / dolu durumlar
// taşmaz. Kural 7: yenile düğmesi ve `reload()` çalışır. Yarış korumaları: art arda arama, süzgeç, site
// değişimi. Kurul üyesi SALT OKUNUR (hiçbir yazma düğmesi yok). Modül kapalıysa sekme yerine bilgi. Hata asla
// "borç yok / daire yok / tanım yok" demez.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsRole;
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/finance.dart';
import 'package:site_kapi_kontrol/models/site_record.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart' show InlineNotice;
import 'package:site_kapi_kontrol/ui/design/buttons.dart' show PrimaryActionButton;
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/views/finance_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

import 'dialog_layout_harness.dart' show settleFor;
import 'finance_fixtures.dart';
import 'list_fixtures.dart';
import 'site_application_fixtures.dart' show captureAnnouncements;
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
      // Açık ay hem kart başlığında hem "Kapatılacak ay" seçicisinde yazılıdır.
      expect(find.text('Ekim 2026'), findsWidgets);
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
    // W1 (inceleme düzeltmesi): önceki test HER ZAMAN sunucunun açık ayını (bu ayı) kapatıyordu; bir ay kapanınca
    // ondan önceki tüm aylar da kapandığı için bu, geçen ayın kayıtlarını sessizce donduruyordu. Artık kapatılacak ay
    // `closable` listesinden SEÇİLİR (varsayılan: bir önceki ay) ve onay "X ve öncesi" der.
    testWidgets('Ayı Kapat: ay `closable` listesinden seçilir (varsayılan bir önceki ay); onay "X ve öncesi" der', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _pump(t, auth);
      await _tab(t, 2);
      final summary = auth.summaryCalls;
      expect(find.byKey(const ValueKey<String>('finance_close_choice_2026-09_12')), findsOneWidget,
          reason: 'varsayılan seçim: bir önceki ay (Eylül)');
      expect(
        find.text('Eylül 2026 seçilirse bu aya kadar açık olan aylar birlikte kapanır; bu aylara kayıt eklenemez.'),
        findsOneWidget,
      );
      await tapFinder(t, find.byKey(const ValueKey<String>('finance_close_period')));
      await settleFor(t);
      expect(find.text('Eylül 2026 ayını kapat'), findsOneWidget);
      expect(find.textContaining('Eylül 2026 seçilirse bu aya kadar açık olan aylar birlikte kapanır'), findsWidgets);
      await tapText(t, 'Vazgeç');
      await settleFor(t);
      expect(auth.periodCalls, isEmpty);

      await tapFinder(t, find.byKey(const ValueKey<String>('finance_close_period')));
      await settleFor(t);
      await tapFinder(t, find.descendant(of: find.byType(AlertDialog).last, matching: find.text('Ayı Kapat')));
      await settleFor(t);
      expect(auth.periodCalls, <String>['close 2026-09']);
      expect(find.text('Eylül 2026 kapatıldı.'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_closed_2026-09')), findsOneWidget);
      expect(auth.summaryCalls, greaterThan(summary));
      // Sıralı kapatma: şimdi yalnız bir sonraki ay (Ekim) kapatılabilir.
      expect(find.byKey(const ValueKey<String>('finance_close_choice_2026-10_1')), findsOneWidget);
    });

    testWidgets('Ayı Kapat: başka bir ay seçilebilir; onay seçilen ayı ve öncesini söyler', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _pump(t, auth);
      await _tab(t, 2);
      await tapFinder(t, find.byType(DropdownButtonFormField<FinancePeriod>));
      await tapFinder(t, find.text('Ağustos 2026').last);
      await settleFor(t);
      expect(find.text('Ağustos 2026 seçilirse bu aya kadar açık olan aylar birlikte kapanır; bu aylara kayıt eklenemez.'),
          findsOneWidget);
      await tapFinder(t, find.byKey(const ValueKey<String>('finance_close_period')));
      await settleFor(t);
      expect(find.text('Ağustos 2026 ayını kapat'), findsOneWidget);
      await tapFinder(t, find.descendant(of: find.byType(AlertDialog).last, matching: find.text('Ayı Kapat')));
      await settleFor(t);
      expect(auth.periodCalls, <String>['close 2026-08']);
      expect(auth.closedThrough, '2026-08');
      expect(auth.isClosed('2026-07'), isTrue, reason: 'ondan önceki tüm aylar da kapalı sayılır');
    });

    testWidgets('`closable` boşsa: "şu an kapatılabilecek dönem yok" açıklaması, kapatma düğmesi yok', (t) async {
      final auth = FinanceFakeAuth.seeded()..closedPeriods.add('2026-10');
      await _pump(t, auth);
      await _tab(t, 2);
      expect(find.byKey(const ValueKey<String>('finance_nothing_closable')), findsOneWidget);
      expect(find.textContaining('Kapatılabilecek ay yok'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_close_period')), findsNothing);
      expect(find.byType(DropdownButtonFormField<FinancePeriod>), findsNothing);
    });

    testWidgets('`closable` alanı yoksa (eski sunucu): eski davranış, açık ay kapatılır', (t) async {
      final auth = FinanceFakeAuth.seeded()..omitClosable = true;
      await _pump(t, auth);
      await _tab(t, 2);
      expect(find.byType(DropdownButtonFormField<FinancePeriod>), findsNothing);
      await tapFinder(t, find.byKey(const ValueKey<String>('finance_close_period')));
      await settleFor(t);
      expect(find.text('Ekim 2026 ayını kapat'), findsOneWidget);
    });

    testWidgets('kapalı ay kuralı: kapalı aya (ve öncesine) yazma 409 PERIOD_CLOSED', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await auth.closeFinancePeriod(11, const FinancePeriod(2026, 9));
      expect(auth.isClosed('2026-08'), isTrue);
      await expectLater(
        auth.recordFeePayment(
          11,
          apartmentId: 301,
          amountMinor: 100,
          entryDate: DateTime(2026, 8, 20),
          method: PaymentMethod.cash,
          idempotencyKey: 'k-old',
        ),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'PERIOD_CLOSED')),
      );
      // Sıralı kapatma: Eylül kapalıyken Ağustos'u ya da Kasım'ı kapatamazsın.
      await expectLater(
        auth.closeFinancePeriod(11, const FinancePeriod(2026, 8)),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'PERIOD_NOT_CLOSABLE')),
      );
      await expectLater(
        auth.closeFinancePeriod(11, const FinancePeriod(2026, 11)),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'PERIOD_NOT_CLOSABLE')),
      );
      expect(auth.closableMonths, <String>['2026-10']);
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

  // ---------------------------------------------------------------------------------------------------
  // İnceleme düzeltmeleri (W6, W7, W9, W10, W15, W17): sekmeler, eylem hataları, odak ve anlamsal ağaç.
  // ---------------------------------------------------------------------------------------------------

  group('W6: yenileme başarısızsa eski veri ve eylemler', () {
    testWidgets('Daireler: yenileme hatasında ESKİ bakiyeler gizlenir; hata + Tekrar Dene; düzelince geri gelir',
        (t) async {
      final auth = FinanceFakeAuth.seeded();
      final key = await _pump(t, auth);
      expect(find.byType(BalanceRowCard), findsNWidgets(3));
      auth.balancesError = ApiException('Sunucuya ulaşılamadı.');
      await key.currentState!.reload();
      await settleFor(t);
      expect(find.byType(BalanceRowCard), findsNothing, reason: 'eski tutarlar hata uyarısıyla gösterilmez');
      expect(find.text('Sunucuya ulaşılamadı.'), findsOneWidget);
      expect(find.text('Bu sitede daire bulunamadı.'), findsNothing);
      auth.balancesError = null;
      await tapText(t, 'Tekrar Dene');
      await settleFor(t);
      expect(find.byType(BalanceRowCard), findsNWidgets(3));
    });

    testWidgets('Tanımlar: liste yenilenemedi -> eski liste kalır ama Borçlandır / Düzenle / Pasifleştir PASİF', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _pump(t, auth);
      await _tab(t, 1);
      TextButton post() => t.widget<TextButton>(find.byKey(const ValueKey<String>('fee_definition_post_1')));
      expect(post().onPressed, isNotNull);
      auth.definitionsError = ApiException('Tanım hatası', statusCode: 500);
      await tapFinder(t, find.byTooltip('Yenile').last);
      await settleFor(t);
      expect(find.text('Tanım hatası'), findsOneWidget);
      expect(find.byType(FeeDefinitionCard), findsNWidgets(2), reason: 'tanımlar yapılandırmadır; liste görünür kalır');
      expect(post().onPressed, isNull);
      expect(t.widget<TextButton>(find.byKey(const ValueKey<String>('fee_definition_edit_1'))).onPressed, isNull);
      expect(t.widget<TextButton>(find.byKey(const ValueKey<String>('fee_definition_toggle_1'))).onPressed, isNull);
      auth.definitionsError = null;
      await tapText(t, 'Tekrar Dene');
      await settleFor(t);
      expect(post().onPressed, isNotNull);
    });

    testWidgets('Dönemler: liste yenilenemedi -> Ayı Kapat ve Yeniden Aç PASİF', (t) async {
      final auth = FinanceFakeAuth.seeded(role: _superRole)..closedPeriods.add('2026-08');
      await _pump(t, auth, canReopen: true);
      await _tab(t, 2);
      PrimaryActionButton closeButton() =>
          t.widget<PrimaryActionButton>(find.byKey(const ValueKey<String>('finance_close_period')));
      expect(closeButton().onPressed, isNotNull);
      auth.periodsError = ApiException('Dönem hatası', statusCode: 500);
      await tapFinder(t, find.byTooltip('Yenile').last);
      await settleFor(t);
      expect(find.text('Dönem hatası'), findsOneWidget);
      expect(closeButton().onPressed, isNull);
      expect(t.widget<TextButton>(find.byKey(const ValueKey<String>('finance_reopen_2026-08'))).onPressed, isNull);
      expect(t.widget<DropdownButtonFormField<FinancePeriod>>(find.byType(DropdownButtonFormField<FinancePeriod>)).onChanged,
          isNull);
    });

    testWidgets('tek seferlik tanım kartı "Dönem" yerine "Vade" der', (t) async {
      final auth = FinanceFakeAuth.seeded()
        ..definitions[8] = finDefinition(8, name: 'Boya', kind: 'one_time', distribution: 'equal', amount: 90000);
      await _pump(t, auth);
      await _tab(t, 1);
      final card = find.byKey(const ValueKey<String>('fee_definition_8'));
      expect(find.descendant(of: card, matching: find.textContaining('Dönem:')), findsNothing);
      // Kart birleşik anlamsal etiketle okunur; görsel metin orada yazılıdır.
      expect(find.descendant(of: card, matching: find.text('Vade: borçlandırılırken belirlenir')), findsOneWidget);
    });
  });

  group('W9: eylem hatası eylemin yapıldığı kartta; meşgul durumu', () {
    testWidgets('Pasifleştirme hatası o tanımın KARTINDA görünür ve duyurulur', (t) async {
      final announced = captureAnnouncements(t);
      final auth = FinanceFakeAuth.seeded();
      await _pump(t, auth);
      await _tab(t, 1);
      auth.finError = ApiException('Bu işlem için yetkiniz yok.', statusCode: 403, code: 'FORBIDDEN_ROLE');
      await tapFinder(t, find.byKey(const ValueKey<String>('fee_definition_toggle_2')));
      await settleFor(t);
      final card = find.byKey(const ValueKey<String>('fee_definition_2'));
      expect(find.descendant(of: card, matching: find.text('Bu işlem için yetkiniz yok.')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey<String>('fee_definition_1')),
          matching: find.text('Bu işlem için yetkiniz yok.')), findsNothing);
      expect(announced, contains('Bu işlem için yetkiniz yok.'));
    });

    testWidgets('Etkinleştirme sürerken düğmede dönen gösterge + "Güncelleniyor..." (görsel ve anlamsal), pasif', (t) async {
      final auth = FinanceFakeAuth.seeded()..paymentGate = Completer<void>();
      await _pump(t, auth);
      await _tab(t, 1);
      await tapFinder(t, find.byKey(const ValueKey<String>('fee_definition_toggle_2')));
      await t.pump();
      final toggle = find.byKey(const ValueKey<String>('fee_definition_toggle_2'));
      expect(find.descendant(of: toggle, matching: find.text('Güncelleniyor...')), findsOneWidget);
      expect(find.descendant(of: toggle, matching: find.byType(CircularProgressIndicator)), findsOneWidget);
      expect(t.widget<TextButton>(toggle).onPressed, isNull);
      auth.paymentGate!.complete();
      await settleFor(t);
      expect(find.text('Güncelleniyor...'), findsNothing);
    });

    testWidgets('Ay kapatma hatası açık ay kartında görünür ve duyurulur', (t) async {
      final announced = captureAnnouncements(t);
      final auth = FinanceFakeAuth.seeded()
        ..paymentError = ApiException(
          AuthApi.messageForErrorCode('PERIOD_NOT_CLOSABLE')!,
          statusCode: 409,
          code: 'PERIOD_NOT_CLOSABLE',
        );
      await _pump(t, auth);
      await _tab(t, 2);
      await tapFinder(t, find.byKey(const ValueKey<String>('finance_close_period')));
      await settleFor(t);
      await tapFinder(t, find.descendant(of: find.byType(AlertDialog).last, matching: find.text('Ayı Kapat')));
      await settleFor(t);
      final open = find.byKey(const ValueKey<String>('finance_open_period'));
      expect(find.descendant(of: open, matching: find.byKey(const ValueKey<String>('finance_close_error'))),
          findsOneWidget);
      expect(announced, contains(AuthApi.messageForErrorCode('PERIOD_NOT_CLOSABLE')!));
    });

    testWidgets('Yeniden Aç hatası kapalı ay kartında görünür; sürerken "Yeniden açılıyor..."', (t) async {
      final announced = captureAnnouncements(t);
      final auth = FinanceFakeAuth.seeded(role: _superRole)
        ..closedPeriods.add('2026-09')
        ..paymentGate = Completer<void>();
      await _pump(t, auth, canReopen: true);
      await _tab(t, 2);
      await tapFinder(t, find.byKey(const ValueKey<String>('finance_reopen_2026-09')));
      await settleFor(t);
      await tapFinder(t, find.descendant(of: find.byType(AlertDialog).last, matching: find.text('Yeniden Aç')));
      await t.pump();
      final reopen = find.byKey(const ValueKey<String>('finance_reopen_2026-09'));
      expect(find.descendant(of: reopen, matching: find.text('Yeniden açılıyor...')), findsOneWidget);
      expect(find.descendant(of: reopen, matching: find.byType(CircularProgressIndicator)), findsOneWidget);
      expect(t.widget<TextButton>(reopen).onPressed, isNull);
      auth.paymentGate!.complete();
      await settleFor(t);

      // İkinci deneme: sunucu reddeder -> hata o kartın içinde.
      auth.paymentGate = null;
      auth.closedPeriods
        ..clear()
        ..addAll(<String>['2026-08', '2026-09']);
      await tapFinder(t, find.byTooltip('Yenile').last);
      await settleFor(t);
      auth.finError = ApiException(
        AuthApi.messageForErrorCode('PERIOD_NOT_REOPENABLE')!,
        statusCode: 409,
        code: 'PERIOD_NOT_REOPENABLE',
      );
      await tapFinder(t, find.byKey(const ValueKey<String>('finance_reopen_2026-09')));
      await settleFor(t);
      await tapFinder(t, find.descendant(of: find.byType(AlertDialog).last, matching: find.text('Yeniden Aç')));
      await settleFor(t);
      final closed = find.byKey(const ValueKey<String>('finance_closed_2026-09'));
      expect(find.descendant(of: closed, matching: find.byKey(const ValueKey<String>('finance_reopen_error_2026-09'))),
          findsOneWidget);
      expect(announced, contains(AuthApi.messageForErrorCode('PERIOD_NOT_REOPENABLE')!));
    });
  });

  group('W7 / W17: sekmeler', () {
    testWidgets('görünmeyen sekmenin alanları klavye / ekran okuyucu odağına GİRMEZ; sekme değişince açılır', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _pump(t, auth);
      await _tab(t, 1);
      EditableText search() => t.widget<EditableText>(find.descendant(
        of: find.byKey(const ValueKey<String>('finance_balances_search'), skipOffstage: false),
        matching: find.byType(EditableText, skipOffstage: false),
        skipOffstage: false,
      ));
      final hidden = search().focusNode;
      hidden.requestFocus();
      await t.pump();
      expect(hidden.hasFocus, isFalse, reason: 'Offstage sekmedeki arama alanı odak alamaz');
      await _tab(t, 0);
      final shown = search().focusNode;
      shown.requestFocus();
      await t.pump();
      expect(shown.hasFocus, isTrue);
    });

    testWidgets('sekme çipleri "sekme" rolü ve seçili durumuyla okunur', (t) async {
      final auth = FinanceFakeAuth.seeded();
      final handle = t.ensureSemantics();
      await _pump(t, auth);
      final first = t.getSemantics(find.byKey(const ValueKey<String>('finance_tab_0')));
      final second = t.getSemantics(find.byKey(const ValueKey<String>('finance_tab_1')));
      expect(first.getSemanticsData().role, SemanticsRole.tab);
      expect(second.getSemanticsData().role, SemanticsRole.tab);
      expect(first.getSemanticsData().label, 'Daireler');
      expect(first, isSemantics(label: 'Daireler', isSelected: true, hasTapAction: true, isButton: true,
          isEnabled: true, hasEnabledState: true, isFocusable: true, hasSelectedState: true));
      expect(second, isSemantics(label: 'Tanımlar', isSelected: false, hasTapAction: true, isButton: true,
          isEnabled: true, hasEnabledState: true, isFocusable: true, hasSelectedState: true));
      handle.dispose();
    });

    testWidgets('Tür / Durum / Yöntem grup başlıkları başlık (header) olarak okunur', (t) async {
      final auth = FinanceFakeAuth.seeded();
      final handle = t.ensureSemantics();
      await _pump(t, auth);
      expect(t.getSemantics(find.text('Durum').first), isSemantics(label: 'Durum', isHeader: true));
      await _tab(t, 1);
      expect(t.getSemantics(find.text('Tür')), isSemantics(label: 'Tür', isHeader: true));
      handle.dispose();
    });

    testWidgets('uzun site adı seçicide kısalır ama tam ad ipucunda (tooltip) bulunur; boş ad teknik kod göstermez',
        (t) async {
      final auth = FinanceFakeAuth.seeded();
      final sites = <PeopleSite>[
        const PeopleSite(code: 11, name: 'Mavi Park Evleri Çok Uzun Adlı Konut Yapı Kooperatifi Sitesi', canWrite: true),
        const PeopleSite(code: 12, name: '', canWrite: true),
      ];
      await _pump(t, auth, sites: sites, width: 320, scale: 2.0);
      expect(find.byTooltip('Mavi Park Evleri Çok Uzun Adlı Konut Yapı Kooperatifi Sitesi'), findsWidgets);
      await tapFinder(t, find.byType(DropdownButtonFormField<int>));
      expect(find.text('İsimsiz site'), findsWidgets);
      expect(find.textContaining('Site 12'), findsNothing, reason: 'teknik site kodu gösterilmez');
    });

    testWidgets('site yoksa metin "Finans" sözcüğünü tekrarlamaz', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _pump(t, auth, sites: const <PeopleSite>[]);
      expect(find.text('Aidat ve Finans modülü açık bir siteye bağlı olduğunuzda burada görünür.'), findsOneWidget);
      expect(find.textContaining('Finans, Aidat ve Finans'), findsNothing);
    });
  });

  group('W10: tutarlar ekran okuyucuda okunuşla', () {
    testWidgets('mali özet kartı: etiket + tutar TEK birleşik etiketle okunur', (t) async {
      final auth = FinanceFakeAuth.seeded();
      final handle = t.ensureSemantics();
      await _pump(t, auth);
      expect(find.bySemanticsLabel('Toplam borç: bin lira'), findsOneWidget);
      expect(find.bySemanticsLabel('Toplam alacak: üç yüz lira'), findsOneWidget);
      // Eskiden etiket ayrıca bir de yalnız etiket olarak okunuyordu (çift okuma).
      expect(find.bySemanticsLabel('Toplam borç'), findsNothing);
      handle.dispose();
    });

    testWidgets('tahsilat başarı bildirimi (SnackBar) tutarı okunuşla bildirir; görsel metin değişmez', (t) async {
      final auth = FinanceFakeAuth.seeded();
      final handle = t.ensureSemantics();
      await _pump(t, auth);
      await tapFinder(t, find.byKey(const ValueKey<String>('finance_add_payment')));
      await settleFor(t);
      await tapFinder(t, find.byKey(const ValueKey<String>('finance_payment_apartment')));
      await settleFor(t);
      await tapFinder(t, find.descendant(of: find.byType(AlertDialog).last, matching: find.text('B Blok - 2')));
      await settleFor(t);
      await t.enterText(find.byKey(const ValueKey<String>('finance_payment_amount')), '750');
      await t.pump();
      await tapFinder(t, find.byKey(const ValueKey<String>('finance_method_cash')));
      await tapFinder(t, find.byKey(const ValueKey<String>('finance_payment_submit')));
      await settleFor(t);
      expect(find.textContaining('Tahsilat kaydedildi: 750,00 ₺.'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Tahsilat kaydedildi: yedi yüz elli lira')), findsOneWidget);
      handle.dispose();
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
  group('W11: sunucu metin vermezse (502) Türkçe yedek metin; teknik metin GÖRÜNMEZ', () {
    ApiException bare() => ApiException('İşlem başarısız (502) (Hata kodu: x1)', statusCode: 502, genericFallback: true);

    testWidgets('özet, bakiyeler, tanımlar ve dönemler', (t) async {
      final auth = FinanceFakeAuth.seeded()
        ..summaryError = bare()
        ..balancesError = bare()
        ..definitionsError = bare()
        ..periodsError = bare();
      await _pump(t, auth);
      expect(find.text('Mali özet yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.'), findsOneWidget);
      expect(find.text('Bakiyeler yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.'), findsOneWidget);
      await _tab(t, 1);
      expect(find.text('Tanımlar yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.'), findsOneWidget);
      await _tab(t, 2);
      expect(find.text('Dönemler yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.'), findsOneWidget);
      expect(find.textContaining('502'), findsNothing);
      expect(find.textContaining('Hata kodu'), findsNothing);
      expect(find.textContaining('İşlem başarısız'), findsNothing);
    });

    testWidgets('sunucunun kendi Türkçe metni korunur (yedek yalnız metin yoksa)', (t) async {
      final auth = FinanceFakeAuth.seeded()..summaryError = ApiException('Mali özet hazırlanamıyor.', statusCode: 500);
      await _pump(t, auth);
      expect(find.text('Mali özet hazırlanamıyor.'), findsOneWidget);
    });
  });
}
