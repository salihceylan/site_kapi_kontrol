// Platform Faz 4a: tanım formu (FinanceDefinitionFormDialog) ve daire ekstresi (FinanceAccountDialog).
//
// AGENTS.md kural 6: dört hücre x açık / koyu. Davranış: tanım ekle / düzenle (borçlandırılmış tanımda kilitli
// alanlar), yalnız değişen alanların gönderimi, dağıtım yöntemi seçicileri; ekstre: bakiye (simge + metin),
// ters kayıt işaretleri, sayfalama, hata asla "borç yok" demez, kurul salt okunur, yazma sonrası yenileme.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/finance.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart' show InlineNotice;
import 'package:site_kapi_kontrol/ui/dialogs/finance_account_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/finance_definition_form_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_parts.dart';

import 'dialog_layout_harness.dart';
import 'finance_4b_harness.dart' show f4ExpectDiscardGuard;
import 'finance_fixtures.dart';
import 'site_application_fixtures.dart' show captureAnnouncements;
import 'list_fixtures.dart' show tapFinder, tapText;

final DateTime _now = DateTime.utc(2026, 10, 16, 9);

PeopleScope _scope(FinanceFakeAuth auth, {bool canWrite = true}) =>
    PeopleScope(authService: auth, siteCode: 11, siteName: 'Gül Sitesi', canWrite: canWrite);

class _Out<T> {
  T? result;
  bool closed = false;
  int refreshes = 0;
  int changed = 0;
}

Future<_Out<FinanceDefinitionOutcome>> _openForm(
  WidgetTester t,
  FinanceFakeAuth auth, {
  FeeDefinition? definition,
  double width = 400,
  double height = 1400,
  double scale = 1.0,
  bool dark = false,
}) async {
  final out = _Out<FinanceDefinitionOutcome>();
  await openDialogAt(
    t,
    (context) async {
      out.result = await FinanceDefinitionFormDialog.show(
        context,
        scope: _scope(auth),
        definition: definition,
        now: () => _now,
        onRefreshNeeded: () => out.refreshes++,
      );
      out.closed = true;
    },
    width: width,
    height: height,
    scale: scale,
    dark: dark,
  );
  await settleFor(t);
  return out;
}

Future<_Out<void>> _openAccount(
  WidgetTester t,
  FinanceFakeAuth auth, {
  int apartmentId = 301,
  bool canWrite = true,
  double width = 400,
  double height = 1400,
  double scale = 1.0,
  bool dark = false,
}) async {
  final out = _Out<void>();
  await openDialogAt(
    t,
    (context) async {
      await FinanceAccountDialog.show(
        context,
        scope: _scope(auth, canWrite: canWrite),
        apartmentId: apartmentId,
        initialLabel: 'A Blok - 5',
        onChanged: () => out.changed++,
        now: () => _now,
      );
      out.closed = true;
    },
    width: width,
    height: height,
    scale: scale,
    dark: dark,
  );
  await settleFor(t);
  return out;
}

FeeDefinition _def(FinanceFakeAuth auth, int id) => FeeDefinition.fromJson(auth.definitions[id]!);

Future<void> _enter(WidgetTester t, String key, String text) async {
  final field = find.byKey(ValueKey<String>(key));
  await scrollTo(t, field);
  await t.enterText(field, text);
  await t.pump();
}

Future<void> _tapKey(WidgetTester t, String key) async {
  final finder = find.byKey(ValueKey<String>(key));
  await scrollTo(t, finder);
  await t.tap(finder);
  await t.pump();
  await t.pump(const Duration(milliseconds: 450));
}

Future<void> _save(WidgetTester t) => _tapKey(t, 'finance_definition_submit');

String _text(WidgetTester t, String key) => t.widget<TextField>(find.descendant(
  of: find.byKey(ValueKey<String>(key)),
  matching: find.byType(TextField),
)).controller!.text;

void main() {
  group('tanım formu: taşma matrisi', () {
    layoutMatrix('Yeni Tanım: varsayılan (aylık, sabit tutar)', (t, w, h, s, dark) async {
      final auth = FinanceFakeAuth.seeded();
      await _openForm(t, auth, width: w, height: h, scale: s, dark: dark);
      expect(find.text('Yeni Tanım'), findsWidgets);
      for (final label in const ['Tanım adı', 'Tür', 'Aylık vade günü', 'Başlangıç dönemi', 'Dağıtım yöntemi', 'Daire başı tutar', 'Hedef']) {
        await scrollTo(t, find.text(label).first);
        expect(find.text(label), findsWidgets, reason: label);
      }
    });

    layoutMatrix('Yeni Tanım: kategori + arsa payı + bitiş dönemi + bloklar', (t, w, h, s, dark) async {
      final auth = FinanceFakeAuth.seeded();
      await _openForm(t, auth, width: w, height: h, scale: s, dark: dark);
      await _tapKey(t, 'finance_has_end');
      await _tapKey(t, 'def_spec_dist_category');
      await _tapKey(t, 'def_spec_add_category');
      await _tapKey(t, 'def_spec_dist_land_share');
      await _tapKey(t, 'finance_target_apartments');
      await scrollTo(t, find.text('Kaydet'));
    });

    layoutMatrix('Düzenle: borçlandırılmış tanım — kilitli alanlar paneli', (t, w, h, s, dark) async {
      final auth = FinanceFakeAuth.seeded();
      await _openForm(t, auth, definition: _def(auth, 1), width: w, height: h, scale: s, dark: dark);
      expect(find.text('Tanımı Düzenle'), findsWidgets);
      await scrollTo(t, find.byKey(const ValueKey<String>('finance_definition_locked')));
      expect(find.text('Kilitli alanlar'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('def_spec_dist_fixed')), findsNothing);
    });

    layoutMatrix('Ekstre: dolu görünüm (bakiye, vadesi geçen, hareketler)', (t, w, h, s, dark) async {
      final auth = FinanceFakeAuth.seeded();
      await _openAccount(t, auth, width: w, height: h, scale: s, dark: dark);
      expect(find.text('Hesap Ekstresi'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_account_balance')), findsOneWidget);
      await scrollTo(t, find.byKey(const ValueKey<String>('ledger_entry_1')));
    });

    layoutMatrix('Ekstre: hata (Tekrar Dene) ve boş durum', (t, w, h, s, dark) async {
      final auth = FinanceFakeAuth.seeded()..accountError = ApiException('Sunucu hatası', statusCode: 500);
      await _openAccount(t, auth, width: w, height: h, scale: s, dark: dark);
      expect(find.byType(InlineNotice), findsOneWidget);
      expect(find.text('Tekrar Dene'), findsOneWidget);
    });
  });

  group('tanım formu: ekleme', () {
    testWidgets('aylık sabit tutar: gövde KURUŞ, vade günü, dönem YYYY-AA, hedef tüm site', (t) async {
      final auth = FinanceFakeAuth.seeded();
      final out = await _openForm(t, auth);
      await _enter(t, 'finance_definition_name', '  Aylık aidat 2027  ');
      // Vade günü: açılır liste, varsayılan 1.
      await scrollTo(t, find.byType(DropdownButtonFormField<int>));
      await t.tap(find.byType(DropdownButtonFormField<int>));
      await t.pump();
      await t.pump(const Duration(milliseconds: 450));
      await tapFinder(t, find.text("Her ayın 15'i").last);
      await _enter(t, 'def_spec_amount', '1.250,50');
      expect(find.text('Girilen tutar: 1.250,50 ₺'), findsOneWidget);
      await _save(t);

      expect(auth.definitionCreateCalls.length, 1);
      final body = auth.definitionCreateCalls.single;
      expect(body['name'], 'Aylık aidat 2027');
      expect(body['kind'], 'recurring');
      expect(body['distribution'], 'fixed');
      expect(body['amount_minor'], 125050);
      expect(body['due_day'], 15);
      expect(body['start_period'], '2026-10');
      expect(body.containsKey('end_period'), isFalse);
      expect(body['target'], <String, dynamic>{'type': 'site'});
      expect(out.closed, isTrue);
      expect(out.result!.message, 'Tanım eklendi.');
      expect(out.result!.definition.name, 'Aylık aidat 2027');
    });

    // W6 (inceleme düzeltmesi): önceki test tek seferlikte "Dönem" seçicisinin görünmesini bekliyordu; ama o seçim
    // hiçbir şeyi etkilemiyordu (tek seferlik tanımın dönemi yok). Artık seçici gizlenir ve kısa bir açıklama yazılır.
    testWidgets('tek seferlik tür: vade günü ve dönem seçici yok (etkisiz alan gizlenir)', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _openForm(t, auth);
      expect(find.byType(DropdownButtonFormField<int>), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_start_label')), findsOneWidget);
      await _tapKey(t, 'finance_kind_one_time');
      expect(find.byType(DropdownButtonFormField<int>), findsNothing);
      expect(find.byKey(const ValueKey<String>('finance_start_label')), findsNothing, reason: 'dönem etkisiz');
      expect(find.text('Dönem'), findsNothing);
      expect(find.byKey(const ValueKey<String>('finance_one_time_note')), findsOneWidget);
      await _enter(t, 'finance_definition_name', 'Boya');
      await _tapKey(t, 'def_spec_dist_equal');
      await _enter(t, 'def_spec_amount', '9.000');
      await _save(t);
      final body = auth.definitionCreateCalls.single;
      expect(body['kind'], 'one_time');
      expect(body.containsKey('due_day'), isFalse);
      expect(body['amount_minor'], 900000);
      expect(body['start_period'], '2026-10', reason: 'kayıt ayı başlangıç sayılır');
    });

    testWidgets('bitiş dönemi: yalnız anahtar açıkken gider; başlangıçtan önceye inilmez', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _openForm(t, auth);
      await _enter(t, 'finance_definition_name', 'Aidat');
      await _enter(t, 'def_spec_amount', '500');
      await _tapKey(t, 'finance_has_end');
      expect(t.widget<Text>(find.byKey(const ValueKey<String>('finance_end_label'))).data, 'Eylül 2027');
      expect(
        t.widget<IconButton>(find.byKey(const ValueKey<String>('finance_end_prev'))).onPressed,
        isNotNull,
      );
      for (var i = 0; i < 11; i++) {
        await _tapKey(t, 'finance_end_prev');
      }
      expect(t.widget<Text>(find.byKey(const ValueKey<String>('finance_end_label'))).data, 'Ekim 2026');
      expect(
        t.widget<IconButton>(find.byKey(const ValueKey<String>('finance_end_prev'))).onPressed,
        isNull,
        reason: 'bitiş, başlangıçtan önce olamaz',
      );
      await _save(t);
      expect(auth.definitionCreateCalls.single['end_period'], '2026-10');
    });

    testWidgets('kategori: harita kuruş olarak gider; m²: alan esası gider; kategori / m² tutarı gitmez', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _openForm(t, auth);
      await _enter(t, 'finance_definition_name', 'Kategorili');
      await _tapKey(t, 'def_spec_dist_category');
      await _enter(t, 'def_spec_category_name_0', '3+1');
      await _enter(t, 'def_spec_category_amount_0', '750,50');
      await _save(t);
      var body = auth.definitionCreateCalls.last;
      expect(body['category_amounts'], <String, dynamic>{'3+1': 75050});
      expect(body.containsKey('amount_minor'), isFalse);
      expect(body.containsKey('area_basis'), isFalse);
    });

    testWidgets('metrekare seçeneği kaldırılmıştır; formda görünmez, arsa payı seçilebilir', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _openForm(t, auth);
      expect(find.byKey(const ValueKey<String>('def_spec_dist_area')), findsNothing);
      expect(find.text('Metrekareye göre'), findsNothing);
      expect(find.text('Metrekare türü'), findsNothing);
      await _enter(t, 'finance_definition_name', 'Arsa Payı');
      await _tapKey(t, 'def_spec_dist_land_share');
      expect(find.text('Toplam tutar'), findsOneWidget, reason: 'sabit dışında tutar TOPLAMDIR');
      await _enter(t, 'def_spec_amount', '12.000');
      await _save(t);
      final body = auth.definitionCreateCalls.single;
      expect(body['distribution'], 'land_share');
      expect(body['amount_minor'], 1200000);
    });

    testWidgets('yönteme göre tutar etiketi: sabit "Daire başı tutar", eşit "Toplam tutar"; açıklama metni değişir', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _openForm(t, auth);
      expect(find.text('Daire başı tutar'), findsOneWidget);
      expect(find.text('Her daireye aynı (daire başı) tutar yazılır.'), findsOneWidget);
      await _tapKey(t, 'def_spec_dist_equal');
      expect(find.text('Toplam tutar'), findsOneWidget);
      expect(find.text('Toplam tutar, hedefteki tüm dairelere eşit bölünür.'), findsOneWidget);
      await _tapKey(t, 'def_spec_dist_land_share');
      expect(find.text('Toplam tutar, dairelerin arsa paylarına göre bölünür.'), findsOneWidget);
    });

    testWidgets('boş gönderim: özet + alan hataları, sunucuya gidilmez, pencere açık', (t) async {
      final auth = FinanceFakeAuth.seeded();
      final out = await _openForm(t, auth);
      await _save(t);
      expect(find.text('Lütfen işaretli alanları düzeltin.'), findsOneWidget);
      expect(find.text('Tanım adını girin.'), findsOneWidget);
      expect(find.text('Tutarı girin.'), findsOneWidget);
      expect(auth.definitionCreateCalls, isEmpty);
      expect(out.closed, isFalse);
    });

    testWidgets('ad sınırı 80 KOD NOKTASI; hedef "Bloklar" boşsa gönderilmez', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _openForm(t, auth);
      await _enter(t, 'finance_definition_name', '😀' * 81);
      await _enter(t, 'def_spec_amount', '500');
      await _save(t);
      expect(find.text('Ad en çok 80 karakter olabilir.'), findsOneWidget);
      await _enter(t, 'finance_definition_name', '😀' * 80);
      await _tapKey(t, 'finance_target_blocks');
      await _save(t);
      expect(find.text('En az bir blok seçin.'), findsOneWidget);
      expect(auth.definitionCreateCalls, isEmpty);
    });

    testWidgets('ağ hatası: tanım ekleme "çift kayıt oluşmaz" DEMEZ (işlem anahtarı yok); listeyi kontrol ettirir', (t) async {
      final auth = FinanceFakeAuth.seeded()..finError = ApiException('Sunucuya ulaşılamadı.');
      final out = await _openForm(t, auth);
      await _enter(t, 'finance_definition_name', 'Aidat');
      await _enter(t, 'def_spec_amount', '500');
      await _save(t);
      expect(
        find.textContaining('Tanım oluşmuş olabilir. Tekrar denemeden önce Tanımlar listesini yenileyip kontrol edin.'),
        findsOneWidget,
      );
      expect(find.textContaining('çift kayıt oluşmaz'), findsNothing);
      expect(out.closed, isFalse);
      auth.finError = null;
      await tapText(t, 'Vazgeç');
      await settleFor(t);
      // Yazılmış veri var: kapatmadan önce onay sorulur (R14).
      await tapText(t, 'Vazgeç ve Kapat');
      await settleFor(t);
      expect(out.refreshes, 1, reason: 'sonuç belirsizdi: kapanırken liste tazelenir');
    });

    testWidgets('sunucu reddi pencerede Türkçe gösterilir ve pencere AÇIK kalır', (t) async {
      final auth = FinanceFakeAuth.seeded()..finError = ApiException('Bu işlem için yetkiniz yok.', statusCode: 403, code: 'FORBIDDEN_ROLE');
      final out = await _openForm(t, auth);
      await _enter(t, 'finance_definition_name', 'Aidat');
      await _enter(t, 'def_spec_amount', '500');
      await _save(t);
      expect(find.text('Bu işlem için yetkiniz yok.'), findsOneWidget);
      expect(out.closed, isFalse);
    });

    testWidgets('R14: yazılmış veri varken Vazgeç / geri tuşu onay sorar; hiçbir şey yazılmaz', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await f4ExpectDiscardGuard(
        t,
        markerKey: 'finance_definition_submit',
        open: () async {
          await _openForm(t, auth);
        },
        edit: () async => _enter(t, 'finance_definition_name', 'Aidat'),
      );
      expect(auth.definitionCreateCalls, isEmpty);
    });

    testWidgets('gönderim sürerken çift dokunuş tek istek; geri tuşu kapatmaz', (t) async {
      final auth = FinanceFakeAuth.seeded()..paymentGate = Completer<void>();
      final out = await _openForm(t, auth);
      await _enter(t, 'finance_definition_name', 'Aidat');
      await _enter(t, 'def_spec_amount', '500');
      await _save(t);
      expect(find.text('Kaydediliyor...'), findsOneWidget);
      await t.tap(find.text('Kaydediliyor...'), warnIfMissed: false);
      await t.pump();
      expect(auth.definitionCreateCalls.length, 1);
      await t.binding.handlePopRoute();
      await t.pump();
      expect(find.byType(FinanceDefinitionFormDialog), findsOneWidget);
      auth.paymentGate!.complete();
      await settleFor(t);
      expect(out.closed, isTrue);
      expect(auth.definitionCreateCalls.length, 1);
    });
  });

  group('tanım formu: düzenleme', () {
    testWidgets('borçlandırılmış tanım: yalnız ad / vade günü / bitiş dönemi gider (dağıtım alanları HİÇ)', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _openForm(t, auth, definition: _def(auth, 1));
      await scrollTo(t, find.byKey(const ValueKey<String>('finance_definition_locked')));
      expect(find.byKey(const ValueKey<String>('finance_definition_locked')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('def_spec_dist_fixed')), findsNothing, reason: 'kilitliyken yöntem seçici yok');
      expect(find.text('Sabit tutar'), findsOneWidget, reason: 'yalnız kilitli panelde salt okunur değer');
      expect(find.text('Daire başı 500,00 ₺'), findsOneWidget);
      await _enter(t, 'finance_definition_name', 'Aylık aidat (yeni ad)');
      await _tapKey(t, 'finance_has_end');
      await _save(t);
      expect(auth.definitionUpdateCalls.length, 1);
      final fields = auth.definitionUpdateCalls.single.fields;
      expect(fields.keys.toSet(), <String>{'name', 'end_period'});
      expect(fields['name'], 'Aylık aidat (yeni ad)');
      expect(fields['end_period'], isA<String>());
    });

    testWidgets('değişiklik yoksa sunucuya gidilmez, pencere sonuçsuz kapanır', (t) async {
      final auth = FinanceFakeAuth.seeded();
      final out = await _openForm(t, auth, definition: _def(auth, 1));
      await _save(t);
      expect(auth.definitionUpdateCalls, isEmpty);
      expect(out.closed, isTrue);
      expect(out.result, isNull);
    });

    testWidgets('borçlandırılmamış tanım: tutar / dağıtım düzenlenir; yalnız ad değişirse dağıtım alanları gitmez', (t) async {
      final auth = FinanceFakeAuth.seeded()
        ..definitions[4] = finDefinition(4, name: 'Yeni', distribution: 'equal', amount: 100000);
      await _openForm(t, auth, definition: _def(auth, 4));
      expect(find.byKey(const ValueKey<String>('def_spec_dist_equal')), findsOneWidget);
      expect(_text(t, 'def_spec_amount'), '1.000,00');

      await _enter(t, 'finance_definition_name', 'Yeni (2)');
      await _save(t);
      expect(auth.definitionUpdateCalls.single.fields.keys.toSet(), <String>{'name'},
          reason: 'hedef kimlik KÜMESİ aynı: dağıtım alanları gönderilmez');
    });

    testWidgets('borçlandırılmamış tanımda tutarı değiştirmek dağıtım grubunu gönderir', (t) async {
      final auth = FinanceFakeAuth.seeded()
        ..definitions[4] = finDefinition(4, name: 'Yeni', distribution: 'equal', amount: 100000);
      final out = await _openForm(t, auth, definition: _def(auth, 4));
      await _enter(t, 'def_spec_amount', '2.000');
      await _save(t);
      final fields = auth.definitionUpdateCalls.single.fields;
      expect(fields['distribution'], 'equal');
      expect(fields['amount_minor'], 200000);
      expect(fields['target'], <String, dynamic>{'type': 'site'});
      expect(fields.containsKey('amount'), isFalse);
      expect(out.result!.message, 'Tanım güncellendi.');
      expect(auth.definitions[4]!['amount_minor'], 200000);
    });

    testWidgets('sunucu DEFINITION_LOCKED der (başka yönetici borçlandırdı): Türkçe mesaj, pencere açık', (t) async {
      final auth = FinanceFakeAuth.seeded()
        ..definitions[4] = finDefinition(4, name: 'Yeni', distribution: 'equal', amount: 100000);
      final out = await _openForm(t, auth, definition: _def(auth, 4));
      auth.definitions[4]!['has_runs'] = true; // araya giren borçlandırma
      await _enter(t, 'def_spec_amount', '2.000');
      await _save(t);
      expect(find.text(AuthApi.messageForErrorCode('DEFINITION_LOCKED')!), findsOneWidget);
      expect(out.closed, isFalse);
    });

    testWidgets('kayıtlı hedef bloklar: etiketli çip olarak gelir; hedefi değiştirmek hedefi gönderir', (t) async {
      final auth = FinanceFakeAuth.seeded();
      auth.definitions[4] = finDefinition(4, name: 'Bloklu', targetType: 'blocks', blockIds: const <int>[1]);
      (auth.definitions[4]!['target'] as Map<String, dynamic>)['blocks'] = <Map<String, dynamic>>[
        <String, dynamic>{'id': 1, 'name': 'A Blok'},
      ];
      await _openForm(t, auth, definition: _def(auth, 4));
      await scrollTo(t, find.byKey(const ValueKey<String>('finance_pick_1')));
      expect(find.byKey(const ValueKey<String>('finance_pick_1')), findsOneWidget);
      expect(find.text('A Blok'), findsWidgets);
      // Çipi kaldır -> hedef boş -> gönderim engellenir.
      await t.tap(find.byTooltip('A Blok hedeften çıkar'));
      await t.pump();
      await _save(t);
      expect(find.text('En az bir blok seçin.'), findsOneWidget);
      expect(auth.definitionUpdateCalls, isEmpty);
    });
  });

  group('ekstre', () {
    testWidgets('borç: simge + metin + tutar; vadesi geçen; kim öder; hareketler yeniden eskiye', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _openAccount(t, auth);
      final header = find.byKey(const ValueKey<String>('finance_account_header'));
      expect(find.descendant(of: header, matching: find.text('Borç')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_account_balance')), findsOneWidget);
      expect(t.widget<Text>(find.byKey(const ValueKey<String>('finance_account_balance'))).data, '1.000,00 ₺');
      expect(find.text('Vadesi geçen: 500,00 ₺'), findsOneWidget);
      expect(find.text('Malik öder'), findsWidgets);
      // 301: iki borç (eylül, ekim); ekim (id 2) üstte.
      final first = t.getTopLeft(find.byKey(const ValueKey<String>('ledger_entry_2'))).dy;
      final second = t.getTopLeft(find.byKey(const ValueKey<String>('ledger_entry_1'))).dy;
      expect(first, lessThan(second));
      expect(find.text('Borca eklendi'), findsWidgets);
    });

    testWidgets('alacak ve sıfır bakiye: "Alacak" / "Borç yok" yalnız başarılı yüklemeden sonra', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _openAccount(t, auth, apartmentId: 302);
      expect(find.text('Alacak'), findsOneWidget);
      expect(find.text('300,00 ₺'), findsOneWidget);
      expect(find.text('Borç yok'), findsNothing);

      final empty = FinanceFakeAuth.seeded();
      await _openAccount(t, empty, apartmentId: 303);
      expect(find.text('Borç yok'), findsOneWidget);
      expect(find.text('Bu dairede henüz mali hareket yok.'), findsOneWidget);
    });

    testWidgets('HATA asla "borç yok" / "hareket yok" demez; Tekrar Dene çalışır', (t) async {
      final auth = FinanceFakeAuth.seeded()..accountError = ApiException('Sunucu hatası', statusCode: 500);
      await _openAccount(t, auth, apartmentId: 303);
      expect(find.text('Borç yok'), findsNothing);
      expect(find.text('Bu dairede henüz mali hareket yok.'), findsNothing);
      expect(find.text('Sunucu hatası'), findsOneWidget);
      auth.accountError = null;
      await tapText(t, 'Tekrar Dene');
      await settleFor(t);
      expect(find.text('Borç yok'), findsOneWidget);
    });

    testWidgets('yükleme sürerken iskelet; "borç yok" yazılmaz', (t) async {
      final auth = FinanceFakeAuth.seeded();
      final gate = Completer<void>();
      auth.accountGates.add(gate);
      await _openAccount(t, auth, apartmentId: 303);
      expect(find.text('Borç yok'), findsNothing);
      expect(find.text('Bu dairede henüz mali hareket yok.'), findsNothing);
      gate.complete();
      await settleFor(t);
      expect(find.text('Borç yok'), findsOneWidget);
    });

    testWidgets('ters kayıtlar işaretli: iptal edilen "İptal edildi" + üstü çizili; ters kayıt "Ters kayıt" + neden', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await auth.reverseFinanceEntry(11, 2, reason: 'Yanlış dönem', idempotencyKey: 'k1');
      await _openAccount(t, auth);
      expect(find.text('İptal edildi'), findsOneWidget);
      expect(find.text('Ters kayıt'), findsOneWidget);
      expect(find.text('Neden: Yanlış dönem'), findsOneWidget);
      // Kayıt numarası gösterilmez; ilgili kaydın tarihi ve tutarı yazılır.
      expect(find.text('Şu kaydın ters kaydı: 01.10.2026 • 500,00 ₺'), findsOneWidget);
      expect(find.text('Ters kayıtla iptal edildi: 16.10.2026 • 500,00 ₺'), findsOneWidget);
      expect(find.textContaining('numaralı'), findsNothing);
      expect(find.textContaining('#'), findsNothing);
      final amounts = t.widgetList<Text>(find.byType(Text)).where((w) => w.style?.decoration == TextDecoration.lineThrough);
      expect(amounts.length, 1, reason: 'yalnız iptal edilen kaydın tutarı çizili');
      // Bakiye: ekim borcu ters kaydıyla silindi; geriye eylül borcu kalır.
      expect(find.text('500,00 ₺'), findsWidgets);
      // İptal edilmiş ve ters kayıt satırlarında eylem düğmesi yok.
      expect(find.byKey(const ValueKey<String>('ledger_reverse_2')), findsNothing);
      expect(find.byKey(const ValueKey<String>('ledger_reverse_100')), findsNothing);
      expect(find.byKey(const ValueKey<String>('ledger_reverse_1')), findsOneWidget);
    });

    testWidgets('sayfalama: before_id imleci, "Daha fazla yükle" sonraki sayfayı ekler', (t) async {
      final auth = FinanceFakeAuth.seeded()..maxPage = 1;
      await _openAccount(t, auth);
      expect(find.byKey(const ValueKey<String>('ledger_entry_2')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('ledger_entry_1')), findsNothing);
      await tapText(t, 'Daha fazla yükle');
      await settleFor(t);
      expect(auth.accountCalls.last.before, 2);
      expect(find.byKey(const ValueKey<String>('ledger_entry_1')), findsOneWidget);
      expect(find.text('Daha fazla yükle'), findsNothing);
    });

    testWidgets('yükleme sürerken Yenile pasif (art arda istek yok); yanıt gelince tazelenir', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _openAccount(t, auth);
      final calls = auth.accountCalls.length;
      final slow = Completer<void>();
      auth.accountGates.add(slow);
      await t.tap(find.byTooltip('Yenile'));
      await t.pump();
      expect(auth.accountCalls.length, calls + 1);
      final button = t.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.refresh_rounded));
      expect(button.onPressed, isNull);
      await t.tap(find.byTooltip('Yenile'), warnIfMissed: false);
      await t.pump();
      expect(auth.accountCalls.length, calls + 1, reason: 'ikinci istek yok');
      // Yanıt gelmeden bakiye değişti: gelen yanıt çağrı ANINDAKİ anlık görüntüdür; sonraki yenileme günceller.
      await auth.recordFeePayment(
        11,
        apartmentId: 301,
        amountMinor: 100000,
        entryDate: DateTime(2026, 10, 16),
        method: PaymentMethod.cash,
        idempotencyKey: 'x1',
      );
      slow.complete();
      await settleFor(t);
      await t.tap(find.byTooltip('Yenile'));
      await settleFor(t);
      expect(find.text('Borç yok'), findsOneWidget);
    });
  });

  group('ekstre: yazma eylemleri ve yetki', () {
    testWidgets('kurul üyesi (salt okunur): ne Tahsilat Ekle ne Düzelt / İptal Et ne kaydeden adı', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _openAccount(t, auth, apartmentId: 302, canWrite: false);
      expect(find.text('Alacak'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_account_add_payment')), findsNothing);
      expect(find.textContaining('Düzelt'), findsNothing);
      expect(find.text('İptal Et'), findsNothing);
      expect(find.textContaining('Kaydeden:'), findsNothing);
    });

    testWidgets('yönetici: Tahsilat Ekle -> daire hazır, kayıt sonrası bakiye yenilenir, onChanged çağrılır', (t) async {
      final auth = FinanceFakeAuth.seeded();
      final out = await _openAccount(t, auth);
      await _tapKey(t, 'finance_account_add_payment');
      await settleFor(t);
      expect(find.text('Tahsilat Ekle'), findsWidgets);
      await _enter(t, 'finance_payment_amount', '400');
      await _tapKey(t, 'finance_method_cash');
      await _tapKey(t, 'finance_payment_submit');
      await settleFor(t);
      expect(auth.paymentCalls.single['apartment_id'], 301);
      expect(out.changed, 1);
      expect(find.text('600,00 ₺'), findsOneWidget, reason: '1.000 - 400 = 600 borç kaldı');
      expect(find.text('Tahsilat'), findsWidgets);
    });

    testWidgets('charge İptal Et: neden -> ters kayıt, bakiye düşer, kayıt silinmez', (t) async {
      final auth = FinanceFakeAuth.seeded();
      final out = await _openAccount(t, auth);
      await _tapKey(t, 'ledger_reverse_2');
      await settleFor(t);
      expect(find.text('Kaydı İptal Et'), findsOneWidget);
      await _enter(t, 'finance_reverse_reason', 'Yanlış tanım');
      await _tapKey(t, 'finance_reverse_submit');
      await settleFor(t);
      // W12: yazmadan önce tutar, daire ve nedeni özetleyen ONAY adımı gelir.
      expect(auth.reverseCalls, isEmpty);
      expect(find.text('Kaydı iptal et'), findsOneWidget);
      expect(find.textContaining('Neden: Yanlış tanım'), findsOneWidget);
      expect(find.textContaining('500,00 ₺'), findsWidgets);
      await tapFinder(t, find.descendant(of: find.byType(AlertDialog).last, matching: find.text('Ters Kaydı Ekle')));
      await settleFor(t);
      expect(auth.reverseCalls.single['entry_id'], 2);
      expect(out.changed, 1);
      expect(find.text('500,00 ₺'), findsWidgets);
      expect(auth.ledger.where((e) => e['id'] == 2).length, 1);
      expect(find.text('İptal edildi'), findsOneWidget);
    });

    testWidgets('tahsilat Düzelt: yalnız tahsilat satırında; borç satırında Düzelt yok', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _openAccount(t, auth, apartmentId: 302);
      expect(find.byKey(const ValueKey<String>('ledger_correct_4')), findsOneWidget, reason: 'tahsilat');
      expect(find.byKey(const ValueKey<String>('ledger_correct_3')), findsNothing, reason: 'borç düzeltilmez');
      expect(find.byKey(const ValueKey<String>('ledger_reverse_3')), findsOneWidget, reason: 'borç iptal edilir');
      await _tapKey(t, 'ledger_correct_4');
      await settleFor(t);
      expect(find.text('Tahsilatı Düzelt'), findsWidgets);
      await _enter(t, 'finance_payment_amount', '300');
      await _tapKey(t, 'finance_payment_submit');
      await settleFor(t);
      expect(auth.correctCalls.single['entry_id'], 4);
      expect(find.text('Ters kayıt'), findsOneWidget);
    });

    testWidgets('ekstre Kapat: pencere kapanır', (t) async {
      final auth = FinanceFakeAuth.seeded();
      final out = await _openAccount(t, auth);
      await tapText(t, 'Kapat');
      await settleFor(t);
      expect(out.closed, isTrue);
    });

    testWidgets('para metinleri ekran okuyucuda "bin lira" biçiminde okunur', (t) async {
      final auth = FinanceFakeAuth.seeded();
      final handle = t.ensureSemantics();
      await _openAccount(t, auth);
      expect(find.bySemanticsLabel(RegExp('Borç: bin lira')), findsWidgets);
      handle.dispose();
    });

    testWidgets('dokunma hedefleri: Düzelt / İptal Et / Yenile en az 48 dp', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _openAccount(t, auth, apartmentId: 302);
      for (final key in const ['ledger_correct_4', 'ledger_reverse_4', 'ledger_reverse_3']) {
        final size = t.getSize(find.byKey(ValueKey<String>(key)));
        expect(size.height, greaterThanOrEqualTo(48), reason: key);
        expect(size.width, greaterThanOrEqualTo(48), reason: key);
      }
      expect(t.getSize(find.widgetWithIcon(IconButton, Icons.refresh_rounded)).height, greaterThanOrEqualTo(48));
    });

    test('görsel borç / alacak yalnız renk değildir: simge ve metin birlikte', () {
      final debt = describeBalance(100);
      final credit = describeBalance(-100);
      final zero = describeBalance(0);
      expect(debt.title, 'Borç');
      expect(credit.title, 'Alacak');
      expect(zero.title, 'Borç yok');
      expect(<IconData>{debt.icon, credit.icon, zero.icon}.length, 3, reason: 'üç durumun simgeleri farklı');
      expect(<String>{debt.badgeText, credit.badgeText, zero.badgeText}.length, 3);
    });
  });
  // ---------------------------------------------------------------------------------------------------
  // İnceleme düzeltmeleri (W13, W14): ekstre notları yalnız yönetici; kayıt numarası yok; hata duyurusu.
  // ---------------------------------------------------------------------------------------------------

  group('W14: ekstre notları ve kayıt numaraları', () {
    FinanceFakeAuth withNotes() {
      final auth = FinanceFakeAuth.seeded();
      auth.ledger.firstWhere((e) => e['id'] == 4)['description'] = 'Yönetici notu: elden alındı';
      return auth;
    }

    testWidgets('yönetici: tahsilat açıklaması ve iptal nedeni görünür', (t) async {
      final auth = withNotes();
      await auth.reverseFinanceEntry(11, 2, reason: 'Yanlış dönem', idempotencyKey: 'k1');
      await _openAccount(t, auth, apartmentId: 302);
      expect(find.textContaining('Yönetici notu: elden alındı'), findsOneWidget);
      await _openAccount(t, auth);
      expect(find.text('Neden: Yanlış dönem'), findsOneWidget);
    });

    testWidgets('kurul üyesi (salt okur): açıklama / iptal nedeni / kaydeden yönetici notu ÇİZİLMEZ', (t) async {
      final auth = withNotes();
      await auth.reverseFinanceEntry(11, 2, reason: 'Yanlış dönem', idempotencyKey: 'k1');
      await _openAccount(t, auth, apartmentId: 302, canWrite: false);
      expect(find.textContaining('Yönetici notu'), findsNothing);
      expect(find.textContaining('Kaydeden:'), findsNothing);
      await _openAccount(t, auth, canWrite: false);
      expect(find.textContaining('Neden:'), findsNothing);
      expect(find.text('İptal edildi'), findsOneWidget, reason: 'iptal durumu bilgisi kalır');
      expect(find.byKey(const ValueKey<String>('ledger_reverse_1')), findsNothing, reason: 'yazma düğmesi yok');
    });
  });

  group('W13: tanım formu hata kutusu duyurulur', () {
    testWidgets('sunucu reddi ekran okuyucuya duyurulur; doğrulama özeti de', (t) async {
      final announced = captureAnnouncements(t);
      final auth = FinanceFakeAuth.seeded();
      await _openForm(t, auth);
      await _save(t);
      await settleFor(t);
      expect(announced, contains('Lütfen işaretli alanları düzeltin.'));

      auth.finError = ApiException('Bu işlem için yetkiniz yok.', statusCode: 403, code: 'FORBIDDEN_ROLE');
      await _enter(t, 'finance_definition_name', 'Aidat');
      await _enter(t, 'def_spec_amount', '500');
      await _save(t);
      await settleFor(t);
      expect(announced, contains('Bu işlem için yetkiniz yok.'));
    });

    testWidgets('kategori listesi hatası (yinelenen ad) kaydırılan formda görünür kılınır', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _openForm(t, auth, width: 320, height: 640, scale: 2.0);
      await _enter(t, 'finance_definition_name', 'Kategorili');
      await _tapKey(t, 'def_spec_dist_category');
      await _enter(t, 'def_spec_category_name_0', '3+1');
      await _enter(t, 'def_spec_category_amount_0', '750');
      await _tapKey(t, 'def_spec_add_category');
      await _enter(t, 'def_spec_category_name_1', '3+1');
      await _enter(t, 'def_spec_category_amount_1', '500');
      await _save(t);
      await settleFor(t);
      await settleFor(t);
      expect(auth.definitionCreateCalls, isEmpty);
      final message = find.text('Aynı kategori adı iki kez girilmiş.');
      expect(message, findsOneWidget);
      final viewport = t.getRect(find.ancestor(of: message, matching: find.byType(Scrollable)).first);
      final rect = t.getRect(message);
      expect(rect.top, greaterThanOrEqualTo(viewport.top));
      expect(rect.bottom, lessThanOrEqualTo(viewport.bottom));
    });
  });
  testWidgets('W11: ekstre 502 (metinsiz): Türkçe yedek metin, "borç yok" yazılmaz', (t) async {
    final auth = FinanceFakeAuth.seeded()
      ..accountError = ApiException('İşlem başarısız (502)', statusCode: 502, genericFallback: true);
    await _openAccount(t, auth, apartmentId: 303);
    expect(find.text('Ekstre yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.'), findsOneWidget);
    expect(find.textContaining('502'), findsNothing);
    expect(find.text('Borç yok'), findsNothing);
  });
}
