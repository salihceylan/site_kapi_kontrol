// Platform Faz 4b, Ö3: "Giderler" sekmesi, gider formu (ekle / düzelt), gider ayrıntısı (iptal), tedarikçi seçici ve
// kategori / tedarikçi yönetimi.
//
// Taşma matrisi x açık-koyu; yükleniyor / hata / boş / dolu; kurul salt okur; çift kayıt önlemleri (işlem anahtarı,
// DUPLICATE_EXPENSE onayı, DUPLICATE_DOCUMENT_NO); düzeltme tek işlem; belge eki YOKSA gizli, varsa yükleme ilerlemesi ve
// kısmi başarısızlık; toplamlar yalnız sunucudan.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/expense_attachments.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart' show InlineNotice;
import 'package:site_kapi_kontrol/ui/dialogs/finance_catalog_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/views/finance_expenses_tab.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_4b_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart' show ListSkeleton;

import 'dialog_layout_harness.dart';
import 'finance_4b_fixtures.dart';
import 'finance_4b_harness.dart';
import 'finance_fixtures.dart';
import 'list_fixtures.dart' show pumpList;

final DateTime _now = DateTime.utc(2026, 10, 16, 9);

PeopleScope _scope(FinanceFakeAuth auth, {bool canWrite = true}) =>
    PeopleScope(authService: auth, siteCode: 11, siteName: 'Gül Sitesi', canWrite: canWrite);

Map<String, dynamic> _expense(
  int id, {
  String description = 'Eylül asansör bakımı',
  int amount = 250000,
  String date = '2026-10-05',
  int categoryId = 2,
  String category = 'Asansör bakım',
  int? supplierId,
  String? supplier,
  int accountId = 1,
  Map<String, dynamic>? voided,
  String docKind = 'none',
  String? docNo,
}) => <String, dynamic>{
  'id': id,
  'category_id': categoryId,
  'category_name': category,
  'supplier_id': supplierId,
  'supplier_name': supplier,
  'description': description,
  'amount_minor': amount,
  'vat_minor': null,
  'expense_date': date,
  'account_id': accountId,
  'document_kind': docKind,
  'document_no': docNo,
  'doc_norm': (docNo ?? '').toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), ''),
  'voided': voided,
  'corrects_expense_id': null,
};

FinanceFakeAuth _auth({bool accounts = true, bool expenses = true}) {
  final auth = FinanceFakeAuth.seeded();
  if (accounts) {
    auth.f4.accounts
      ..add(f4AccountJson(1, 'Nakit Kasa', balance: 1000000))
      ..add(f4AccountJson(2, 'Ziraat Bankası', kind: 'bank', balance: 5000000));
  }
  if (expenses) {
    auth.f4.expenses
      ..add(_expense(1, description: 'Elektrik faturası', amount: 123456, category: 'Elektrik', categoryId: 1, date: '2026-10-02', supplierId: 61, supplier: 'Enerji A.Ş.'))
      ..add(_expense(2, description: 'Asansör bakımı', amount: 250000, date: '2026-10-05'))
      ..add(_expense(3, description: 'Yanlış kayıt', amount: 5000, date: '2026-10-06', voided: <String, dynamic>{'at': '2026-10-07T08:00:00Z', 'reason': 'Çift kayıt', 'period': '2026-10'}));
    auth.f4.suppliers.add(<String, dynamic>{'id': 61, 'name': 'Enerji A.Ş.', 'tax_id': '1234567890', 'phone': '02121234567', 'note': null, 'is_active': true});
  }
  return auth;
}

Future<GlobalKey<FinanceExpensesTabState>> _pumpTab(
  WidgetTester t,
  FinanceFakeAuth auth, {
  bool canWrite = true,
  ExpenseAttachmentSource? source,
  VoidCallback? onChanged,
  double width = 400,
  double height = 2400,
  double scale = 1.0,
  bool dark = false,
}) async {
  final key = GlobalKey<FinanceExpensesTabState>();
  await pumpList(
    t,
    FinanceExpensesTab(
      key: key,
      scope: _scope(auth, canWrite: canWrite),
      onDataChanged: onChanged ?? () {},
      attachmentSource: source,
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

class _FakeSource extends ExpenseAttachmentSource {
  _FakeSource(this.files);

  final List<PickedExpenseFile> files;
  int calls = 0;
  int? lastMax;

  @override
  Future<List<PickedExpenseFile>> pick(BuildContext context, {required int maxCount}) async {
    calls++;
    lastMax = maxCount;
    return files;
  }
}

PickedExpenseFile _file(String name, {int size = 3}) =>
    PickedExpenseFile(name: name, bytes: Uint8List(size));

Future<void> _fillValidExpense(WidgetTester t, {String amount = '1.250,50', bool pickAccount = true}) async {
  await f4Tap(t, 'finance_expense_category_0');
  await t.pump(const Duration(milliseconds: 300));
  await t.tap(find.text('Elektrik').last);
  await t.pump();
  await t.pump(const Duration(milliseconds: 450));
  await f4Enter(t, 'finance_expense_description', 'Ekim ayı elektrik');
  await f4Enter(t, 'finance_expense_amount', amount);
  if (pickAccount) await f4Tap(t, 'finance_expense_account_1');
}

void main() {
  group('Giderler sekmesi: taşma matrisi', () {
    f4Matrix('dolu: toplamlar, süzgeçler, satırlar (geçerli + iptal edilmiş)', (t, w, h, s, dark) async {
      final auth = _auth();
      await _pumpTab(t, auth, width: w, height: h, scale: s, dark: dark);
      await f4TapText(t, 'Hepsi');
      await settleFor(t);
      expect(find.byType(ExpenseTile), findsNWidgets(3));
      expect(find.byKey(const ValueKey<String>('finance_expense_totals')), findsOneWidget);
      expect(find.text('İptal edildi'), findsWidgets);
      await scrollTo(t, find.byKey(const ValueKey<String>('finance_expense_add')));
      expect(find.byKey(const ValueKey<String>('finance_expense_catalog')), findsOneWidget);
    });

    f4Matrix('yükleniyor: iskelet; toplam ve "gider yok" yazılmaz', (t, w, h, s, dark) async {
      final auth = _auth();
      auth.f4.expensesGate = Completer<void>();
      await _pumpTab(t, auth, width: w, height: h, scale: s, dark: dark);
      expect(find.byType(ListSkeleton), findsWidgets);
      expect(find.byKey(const ValueKey<String>('finance_expense_totals')), findsNothing);
      expect(find.text('Bu dönemde gider kaydı yok.'), findsNothing);
      auth.f4.expensesGate!.complete();
      await settleFor(t);
    });

    f4Matrix('hata: InlineNotice + Tekrar Dene; sıfır toplam / boş durum yok', (t, w, h, s, dark) async {
      final auth = _auth();
      auth.f4.expensesError = ApiException('x', statusCode: 500);
      await _pumpTab(t, auth, width: w, height: h, scale: s, dark: dark);
      expect(find.byType(InlineNotice), findsWidgets);
      expect(find.text('Tekrar Dene'), findsWidgets);
      expect(find.byKey(const ValueKey<String>('finance_expense_totals')), findsNothing);
      expect(find.text('Bu dönemde gider kaydı yok.'), findsNothing);
    });

    f4Matrix('boş: açıklayıcı durum', (t, w, h, s, dark) async {
      final auth = _auth(expenses: false);
      await _pumpTab(t, auth, width: w, height: h, scale: s, dark: dark);
      expect(find.text('Bu dönemde gider kaydı yok.'), findsOneWidget);
      expect(find.text('İlk gideri "Gider Ekle" ile kaydedin.'), findsOneWidget);
    });

    f4Matrix('kurul: salt okur (Gider Ekle yok); kategori / tedarikçi listesi ve ayrıntı açılır', (t, w, h, s, dark) async {
      final auth = _auth();
      await _pumpTab(t, auth, canWrite: false, width: w, height: h, scale: s, dark: dark);
      expect(find.byKey(const ValueKey<String>('finance_expense_add')), findsNothing);
      expect(find.byKey(const ValueKey<String>('finance_expense_catalog')), findsOneWidget);
      expect(find.byType(ExpenseTile), findsNWidgets(2));
    });
  });

  group('Giderler sekmesi: süzgeç ve toplamlar', () {
    testWidgets('varsayılan: bu ay + geçerli; toplam yalnız sunucudan (iptal edilen hariç)', (t) async {
      final auth = _auth();
      await _pumpTab(t, auth);
      final call = auth.f4.expenseListCalls.first;
      expect(call['from'], '2026-10-01');
      expect(call['to'], '2026-10-31');
      expect(call['status'], 'active');
      expect(find.byType(ExpenseTile), findsNWidgets(2));
      expect(find.text('Geçerli gider 3.734,56 ₺'), findsOneWidget);
      expect(find.textContaining('İptal edilen 50'), findsNothing, reason: 'iptal toplamı yalnız süzgeç "geçerli" dışındayken');
    });

    testWidgets('dönem / durum / kategori / hesap süzgeçleri sorguya yazılır; eski yanıt yenisini ezmez', (t) async {
      final auth = _auth();
      await _pumpTab(t, auth);
      await f4Tap(t, 'finance_expense_period_lastMonth');
      expect(auth.f4.expenseListCalls.last['from'], '2026-09-01');
      expect(auth.f4.expenseListCalls.last['to'], '2026-09-30');
      await f4Tap(t, 'finance_expense_period_thisYear');
      expect(auth.f4.expenseListCalls.last['from'], '2026-01-01');
      expect(auth.f4.expenseListCalls.last['to'], '2026-12-31');
      await f4Tap(t, 'finance_expense_period_all');
      expect(auth.f4.expenseListCalls.last['from'], isNull);
      await f4Tap(t, 'finance_expense_status_voided');
      expect(auth.f4.expenseListCalls.last['status'], 'voided');
      expect(find.byType(ExpenseTile), findsOneWidget);
      expect(find.text('İptal edilen 50,00 ₺'), findsOneWidget);
    });

    testWidgets('arama gecikmeli (350 ms); eski yanıt yenisini ezmez', (t) async {
      final auth = _auth();
      await _pumpTab(t, auth);
      final before = auth.f4.expenseListCalls.length;
      await f4Enter(t, 'finance_expense_search', 'Elektrik');
      expect(auth.f4.expenseListCalls.length, before);
      await t.pump(const Duration(milliseconds: 400));
      await settleFor(t);
      expect(auth.f4.expenseListCalls.last['q'], 'Elektrik');
      expect(find.byType(ExpenseTile), findsOneWidget);
    });

    testWidgets('süzgeç listeleri (kategori / hesap) okunamazsa uyarı + Tekrar Dene; liste yine de çalışır', (t) async {
      final auth = _auth();
      auth.f4.categoriesError = ApiException('x', statusCode: 500);
      await _pumpTab(t, auth);
      expect(find.byKey(const ValueKey<String>('finance_expense_filter_error')), findsOneWidget);
      expect(find.byType(ExpenseTile), findsNWidgets(2));
    });

    testWidgets('sayfalama: Daha fazla yükle imleçle ikinci sayfayı ekler', (t) async {
      final auth = _auth();
      auth.f4.expensePageSize = 1;
      await _pumpTab(t, auth);
      expect(find.byType(ExpenseTile), findsOneWidget);
      await f4TapText(t, 'Daha fazla yükle');
      await settleFor(t);
      expect(find.byType(ExpenseTile), findsNWidgets(2));
      expect(auth.f4.expenseListCalls.last['before_id'], 2);
    });

    testWidgets('ekran okuyucu: gider satırı tutarı okunuşla tek etiketle okunur', (t) async {
      final handle = t.ensureSemantics();
      final auth = _auth();
      await _pumpTab(t, auth);
      expect(
        find.bySemanticsLabel(RegExp('Gider: Elektrik.*bin iki yüz otuz dört lira elli altı kuruş.*Enerji A.Ş.')),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  group('Gider ekle', () {
    testWidgets('boş gönderim doğrulanır; yükleme bitmeden form çizilmez', (t) async {
      final auth = _auth();
      await _pumpTab(t, auth);
      await f4Tap(t, 'finance_expense_add');
      await f4Tap(t, 'finance_expense_submit');
      expect(find.text('Gider kategorisini seçin.'), findsOneWidget);
      expect(find.text('Gider açıklamasını girin.'), findsOneWidget);
      expect(find.text('Tutarı girin.'), findsOneWidget);
      expect(find.text('Giderin çıkacağı hesabı seçin.'), findsOneWidget);
      expect(auth.f4.callCount('createExpense'), 0);
    });

    testWidgets('kaydet: tutar kuruşa, tarih İstanbul bugünü, hesap, anahtar; liste ve toplam yenilenir, hesap bakiyesi düşer', (t) async {
      final auth = _auth();
      var changed = 0;
      await _pumpTab(t, auth, onChanged: () => changed++);
      await f4Tap(t, 'finance_expense_add');
      await _fillValidExpense(t);
      await f4Enter(t, 'finance_expense_vat', '208,42');
      await f4Tap(t, 'finance_expense_doc_invoice');
      await f4Enter(t, 'finance_expense_document_no', ' F-2026/55 ');
      await f4Tap(t, 'finance_expense_submit');
      await settleFor(t);
      final call = auth.f4.expenseCalls.single;
      expect(call['amount_minor'], 125050);
      expect(call['vat_minor'], 20842);
      expect(call['expense_date'], '2026-10-16');
      expect(call['account_id'], 1);
      expect(call['category_id'], 1);
      expect(call['document_kind'], 'invoice');
      expect(call['document_no'], 'F-2026/55');
      expect((call['key'] as String).length, lessThanOrEqualTo(64));
      expect(changed, 1);
      expect(find.text('Gider kaydedildi: 1.250,50 ₺ (Elektrik).'), findsOneWidget);
      expect(find.byType(ExpenseTile), findsNWidgets(3));
      expect(auth.f4.accounts.first['balance_minor'], 1000000 - 125050);
    });

    testWidgets('KDV tutardan büyük olamaz; tarih bugünden ileri / 5 yıldan eski olamaz', (t) async {
      final auth = _auth();
      await _pumpTab(t, auth);
      await f4Tap(t, 'finance_expense_add');
      await _fillValidExpense(t, amount: '100');
      await f4Enter(t, 'finance_expense_vat', '150');
      await f4Enter(t, 'finance_expense_date_group', '01.01.2099');
      await f4Tap(t, 'finance_expense_submit');
      expect(find.text('KDV tutarı gider tutarından büyük olamaz.'), findsOneWidget);
      expect(find.text('Tarih bugünden ileri olamaz.'), findsOneWidget);
      await f4Enter(t, 'finance_expense_date_group', '01.01.2015');
      await f4Tap(t, 'finance_expense_submit');
      expect(find.text('Tarih bugünden en fazla 5 yıl öncesi olabilir.'), findsOneWidget);
      expect(auth.f4.callCount('createExpense'), 0);
    });

    testWidgets('hesap yoksa açıklayıcı uyarı; kaydet pasif', (t) async {
      final auth = _auth(accounts: false);
      await _pumpTab(t, auth);
      await f4Tap(t, 'finance_expense_add');
      expect(find.byKey(const ValueKey<String>('finance_expense_no_account')), findsOneWidget);
      final submit = t.widget<ElevatedButton>(find.byKey(const ValueKey<String>('finance_expense_submit')));
      expect(submit.onPressed, isNull);
    });

    testWidgets('tek aktif hesap ön seçilir; kategori / hesap yüklenemezse Tekrar Dene', (t) async {
      final auth = _auth();
      auth.f4.accounts.removeLast();
      await _pumpTab(t, auth);
      await f4Tap(t, 'finance_expense_add');
      expect(t.widget<ChoiceChip>(find.byKey(const ValueKey<String>('finance_expense_account_1'))).selected, isTrue);
    });

    testWidgets('yükleme hatası: form yerine uyarı; Tekrar Dene formu açar', (t) async {
      final auth = _auth();
      await _pumpTab(t, auth);
      auth.f4.categoriesError = ApiException('x', statusCode: 500);
      await f4Tap(t, 'finance_expense_add');
      expect(find.byKey(const ValueKey<String>('finance_expense_description')), findsNothing);
      expect(find.text('Tekrar Dene'), findsWidgets);
      auth.f4.categoriesError = null;
      await f4TapInDialog(t, 'Tekrar Dene');
      await settleFor(t);
      expect(find.byKey(const ValueKey<String>('finance_expense_description')), findsOneWidget);
    });

    testWidgets('DUPLICATE_EXPENSE: uyarı penceresi; Vazgeç hiçbir şey yazmaz; "Yine de kaydet" allow_duplicate ile yazar', (t) async {
      final auth = _auth();
      await _pumpTab(t, auth);
      await f4Tap(t, 'finance_expense_add');
      await f4Tap(t, 'finance_expense_category_0');
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(find.text('Asansör bakım').last);
      await t.pump();
      await t.pump(const Duration(milliseconds: 450));
      await f4Enter(t, 'finance_expense_description', 'Aynı bakım');
      await f4Enter(t, 'finance_expense_amount', '2.500,00');
      await f4Enter(t, 'finance_expense_date_group', '05.10.2026');
      await f4Tap(t, 'finance_expense_account_1');
      await f4Tap(t, 'finance_expense_submit');
      await settleFor(t);
      expect(find.text('Aynı gider daha önce kaydedilmiş'), findsOneWidget);
      expect(auth.f4.expenses.length, 3, reason: 'henüz yazılmadı');
      await f4TapInDialog(t, 'Vazgeç');
      expect(auth.f4.expenses.length, 3);
      await f4Tap(t, 'finance_expense_submit');
      await settleFor(t);
      await f4TapInDialog(t, 'Yine de kaydet');
      await settleFor(t);
      expect(auth.f4.expenses.length, 4);
      final calls = auth.f4.expenseCalls;
      expect(calls.last['allow_duplicate'], true);
      expect(calls.last['key'], isNot(calls.first['key']), reason: '"yine de" ayrı bir amaçtır: yeni anahtar');
    });

    testWidgets('DUPLICATE_DOCUMENT_NO: Türkçe hata, pencere açık; PERIOD_CLOSED açık mesaj', (t) async {
      final auth = _auth();
      auth.f4.expenses.add(_expense(9, supplierId: 61, supplier: 'Enerji A.Ş.', docKind: 'invoice', docNo: 'F-1', amount: 111));
      await _pumpTab(t, auth);
      await f4Tap(t, 'finance_expense_add');
      await _fillValidExpense(t, amount: '300');
      await f4Tap(t, 'finance_expense_supplier');
      await f4Tap(t, 'finance_supplier_61');
      await f4Tap(t, 'finance_expense_doc_invoice');
      await f4Enter(t, 'finance_expense_document_no', 'f 1');
      await f4Tap(t, 'finance_expense_submit');
      expect(find.text('Bu tedarikçiden aynı belge numarasıyla iptal edilmemiş bir gider zaten var.'), findsOneWidget);
      auth.f4.closedMonths.add('2026-10');
      await f4Enter(t, 'finance_expense_document_no', 'F-77');
      await f4Tap(t, 'finance_expense_submit');
      expect(find.textContaining('Bu dönem kapatılmış'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_expense_submit')), findsOneWidget);
    });

    testWidgets('belirsiz sonuçtan sonra AYNI veri = AYNI anahtar (çift gider yok); çift dokunuş tek istek', (t) async {
      final auth = _auth();
      await _pumpTab(t, auth);
      await f4Tap(t, 'finance_expense_add');
      await _fillValidExpense(t);
      auth.f4.expenseWriteError = ApiException('x', statusCode: 502);
      await f4Tap(t, 'finance_expense_submit');
      expect(find.textContaining('Kayıt oluşmuş olabilir'), findsOneWidget);
      auth.f4.expenseWriteError = null;
      auth.f4.expenseWriteGate = Completer<void>();
      final submit = find.byKey(const ValueKey<String>('finance_expense_submit'));
      await scrollTo(t, submit);
      await t.tap(submit);
      await t.pump();
      await t.tap(submit, warnIfMissed: false);
      await t.pump();
      auth.f4.expenseWriteGate!.complete();
      await settleFor(t);
      final keys = auth.f4.expenseCalls.map((c) => c['key']).toList();
      expect(keys, hasLength(2), reason: 'ilk hata + tek yeniden deneme');
      expect(keys[0], keys[1]);
      expect(auth.f4.expenses.where((e) => e['description'] == 'Ekim ayı elektrik'), hasLength(1));
    });

    testWidgets('tedarikçi seçici: ara, seç, tedarikçisiz, yeni tedarikçi ekle', (t) async {
      final auth = _auth();
      await _pumpTab(t, auth);
      await f4Tap(t, 'finance_expense_add');
      await f4Tap(t, 'finance_expense_supplier');
      expect(find.byKey(const ValueKey<String>('finance_supplier_61')), findsOneWidget);
      await f4Enter(t, 'finance_supplier_search', 'yok-boyle');
      await t.pump(const Duration(milliseconds: 400));
      await settleFor(t);
      expect(find.text('Bu aramaya uyan tedarikçi bulunamadı.'), findsOneWidget);
      await f4Tap(t, 'finance_supplier_add');
      await f4Enter(t, 'finance_supplier_name', 'Yeni Temizlik Ltd.');
      await f4Enter(t, 'finance_supplier_tax', '123');
      await f4Tap(t, 'finance_supplier_submit');
      expect(find.text('Numara 10 ya da 11 rakam olmalı.'), findsOneWidget);
      await f4Enter(t, 'finance_supplier_tax', '1234567890');
      await f4Tap(t, 'finance_supplier_submit');
      await settleFor(t);
      expect(find.text('Yeni Temizlik Ltd.'), findsWidgets, reason: 'seçici kapandı, tedarikçi seçildi');
      expect(auth.f4.suppliers.last['tax_id'], '1234567890');
    });

    f4Matrix('gider formu taşmaz (klavye açık değil)', (t, w, h, s, dark) async {
      final auth = _auth();
      await _pumpTab(t, auth, width: w, height: h, scale: s, dark: dark);
      await f4Tap(t, 'finance_expense_add');
      expect(find.byKey(const ValueKey<String>('finance_expense_description')), findsOneWidget);
      await f4Tap(t, 'finance_expense_doc_receipt');
      await scrollTo(t, find.byKey(const ValueKey<String>('finance_expense_document_no')));
      await f4Tap(t, 'finance_expense_submit');
      expect(find.text('Gider kategorisini seçin.'), findsOneWidget);
    });

    testWidgets('klavye açıkken Kaydet düğmesi görünür kalır (320x640 x2,0)', (t) async {
      final auth = _auth();
      await _pumpTab(t, auth, width: 320, height: 640, scale: 2.0);
      await f4Tap(t, 'finance_expense_add');
      t.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(t.view.resetViewInsets);
      await t.pump();
      await f4Enter(t, 'finance_expense_description', 'x');
      final rect = t.getRect(find.byKey(const ValueKey<String>('finance_expense_submit')));
      expect(rect.bottom, lessThanOrEqualTo(640 - 300 + 1), reason: 'eylem düğmesi klavyenin altında kalmaz');
    });
  });

  group('Belge eki', () {
    testWidgets('belge seçici verilmezse ek alanı GİZLİ', (t) async {
      final auth = _auth();
      await _pumpTab(t, auth);
      await f4Tap(t, 'finance_expense_add');
      expect(find.byKey(const ValueKey<String>('finance_expense_attachments')), findsNothing);
      expect(find.text('Belge Ekle'), findsNothing);
    });

    testWidgets('seçici varsa: kişisel veri uyarısı, yalnız PDF/JPG/PNG, en çok 5; kayıttan sonra yüklenir', (t) async {
      final auth = _auth();
      final source = _FakeSource(<PickedExpenseFile>[_file('fatura.pdf'), _file('foto.JPG'), _file('virus.exe')]);
      await _pumpTab(t, auth, source: source);
      await f4Tap(t, 'finance_expense_add');
      expect(find.byKey(const ValueKey<String>('finance_expense_attachments')), findsOneWidget);
      expect(find.textContaining('Kimlik numarası ve IBAN'), findsOneWidget);
      await f4Tap(t, 'finance_expense_add_file');
      expect(source.lastMax, 5);
      expect(find.text('fatura.pdf'), findsOneWidget);
      expect(find.text('foto.JPG'), findsOneWidget);
      expect(find.text('virus.exe'), findsNothing);
      expect(find.textContaining('Eklenmeyen: virus.exe'), findsOneWidget);
      await _fillValidExpense(t);
      await f4Tap(t, 'finance_expense_submit');
      await settleFor(t);
      expect(auth.f4.uploads, 2);
      expect(find.textContaining('2 belge eklendi.'), findsOneWidget);
    });

    testWidgets('bazı belgeler yüklenemezse gider yine kaydedilir ve kısmi başarısızlık bildirilir', (t) async {
      final auth = _auth();
      final source = _FakeSource(<PickedExpenseFile>[_file('a.pdf')]);
      auth.f4.documentError = f4Coded('DOCUMENT_STORAGE_NOT_CONFIGURED', 503);
      await _pumpTab(t, auth, source: source);
      await f4Tap(t, 'finance_expense_add');
      await f4Tap(t, 'finance_expense_add_file');
      await _fillValidExpense(t);
      await f4Tap(t, 'finance_expense_submit');
      await settleFor(t);
      expect(auth.f4.expenses.any((e) => e['description'] == 'Ekim ayı elektrik'), isTrue, reason: 'gider belgesiz de geçerli');
      expect(find.textContaining('0 belge eklendi, 1 belge yüklenemedi (a.pdf)'), findsOneWidget);
    });
  });

  group('Gider ayrıntısı, düzeltme ve iptal', () {
    Future<void> openDetail(WidgetTester t, FinanceFakeAuth auth, {bool canWrite = true, int id = 2, ExpenseAttachmentSource? source}) async {
      await _pumpTab(t, auth, canWrite: canWrite, source: source);
      await f4Tap(t, 'expense_tile_$id');
      await settleFor(t);
    }

    f4Matrix('ayrıntı: dolu ve iptal edilmiş gider taşmaz', (t, w, h, s, dark) async {
      final auth = _auth();
      await _pumpTab(t, auth, width: w, height: h, scale: s, dark: dark);
      await f4TapText(t, 'Hepsi');
      await settleFor(t);
      await f4Tap(t, 'expense_tile_3');
      await settleFor(t);
      expect(find.byKey(const ValueKey<String>('finance_expense_detail_voided')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_expense_void')), findsNothing, reason: 'iptal edilen tekrar iptal edilemez');
      expect(find.byKey(const ValueKey<String>('finance_expense_correct')), findsNothing);
    });

    testWidgets('ayrıntı hata: boş ekran yok, Tekrar Dene', (t) async {
      final auth = _auth();
      await _pumpTab(t, auth);
      auth.f4.expensesError = ApiException('x', statusCode: 500);
      await f4Tap(t, 'expense_tile_2');
      await settleFor(t);
      expect(find.text('Tekrar Dene'), findsWidgets);
      expect(find.byKey(const ValueKey<String>('finance_expense_detail_amount')), findsNothing);
    });

    testWidgets('kurul: ayrıntıyı okur, düzelt / iptal düğmesi yok', (t) async {
      final auth = _auth();
      await openDetail(t, auth, canWrite: false);
      expect(find.byKey(const ValueKey<String>('finance_expense_detail_amount')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_expense_void')), findsNothing);
      expect(find.byKey(const ValueKey<String>('finance_expense_correct')), findsNothing);
    });

    testWidgets('iptal: neden zorunlu; ayna hareket bakiyeyi geri artırır; satır iptal edilmiş görünür', (t) async {
      final auth = _auth();
      await openDetail(t, auth);
      await f4Tap(t, 'finance_expense_void');
      await f4Tap(t, 'finance_reason_confirm');
      expect(find.text('Neden girin.'), findsOneWidget);
      await f4Enter(t, 'finance_reason_text', 'Çift kayıt');
      await f4Tap(t, 'finance_reason_confirm');
      await settleFor(t);
      expect(auth.f4.expenses.firstWhere((e) => e['id'] == 2)['voided'], isNotNull);
      expect(find.byKey(const ValueKey<String>('finance_expense_detail_voided')), findsOneWidget);
      expect(find.textContaining('Neden: Çift kayıt'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_expense_void')), findsNothing);
    });

    testWidgets('iptal reddi: EXPENSE_ALREADY_VOIDED Türkçe, pencere açık', (t) async {
      final auth = _auth();
      await openDetail(t, auth);
      auth.f4.expenses.firstWhere((e) => e['id'] == 2)['voided'] = <String, dynamic>{'at': '2026-10-16T09:00:00Z', 'reason': 'x', 'period': '2026-10'};
      await f4Tap(t, 'finance_expense_void');
      await f4Enter(t, 'finance_reason_text', 'Neden');
      await f4Tap(t, 'finance_reason_confirm');
      expect(find.text('Bu gider zaten iptal edilmiş. Listeyi yenileyip kontrol edin.'), findsOneWidget);
      // R14: hata sonrası odak hata iletisine gelir (alan gönderim sırasında pasifti; odak kaybolmaz).
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'finance_submit_error');
    });

    testWidgets('R15: gider iptali — aynı neden AYNI anahtar; neden değişince YENİ anahtar (aynı anahtar farklı gövdeyle gitmez)', (t) async {
      final auth = _auth();
      await openDetail(t, auth);
      auth.f4.expenseWriteError = ApiException('İşlem başarısız (502)', statusCode: 502, genericFallback: true);
      await f4Tap(t, 'finance_expense_void');
      await f4Enter(t, 'finance_reason_text', 'Yanlış fatura');
      await f4Tap(t, 'finance_reason_confirm');
      await f4Tap(t, 'finance_reason_confirm');
      await f4Enter(t, 'finance_reason_text', 'Çift kayıt');
      await f4Tap(t, 'finance_reason_confirm');
      final keys = auth.f4.writes.where((w) => w['op'] == 'voidExpense').map((w) => w['key']).toList();
      expect(keys, hasLength(3));
      expect(keys[1], keys[0]);
      expect(keys[2], isNot(keys[0]));
    });

    testWidgets('R15: aynı adlı ve aynı boyutlu İKİ farklı dosya aynı yükleme anahtarını paylaşmaz; yeniden seçilince anahtar sabit', (t) async {
      final auth = _auth();
      final source = _FakeSource(<PickedExpenseFile>[
        PickedExpenseFile(name: 'fatura.pdf', bytes: Uint8List.fromList(<int>[1, 2, 3])),
        PickedExpenseFile(name: 'fatura.pdf', bytes: Uint8List.fromList(<int>[4, 5, 6])),
        PickedExpenseFile(name: 'fatura.pdf', bytes: Uint8List.fromList(<int>[4, 5, 6])),
      ]);
      await openDetail(t, auth, source: source);
      await f4Tap(t, 'finance_expense_detail_add_file');
      await settleFor(t);
      final keys = auth.f4.writes.where((w) => w['op'] == 'createExpenseDocument').map((w) => w['key']).toList();
      expect(keys, hasLength(3));
      expect(keys.toSet(), hasLength(3), reason: 'içerik ya da sıra farkı: üç ayrı anahtar (hiçbiri "zaten yüklendi" sayılmaz)');
      expect(auth.f4.uploads, 3);
    });

    testWidgets('düzelt: form eski değerlerle dolu; iptal + yeni gider TEK işlemde; yeni gider reddedilirse eski gider İPTAL EDİLMEZ', (t) async {
      final auth = _auth();
      await openDetail(t, auth);
      await f4Tap(t, 'finance_expense_correct');
      expect(find.byKey(const ValueKey<String>('finance_expense_original')), findsOneWidget);
      expect(t.widget<TextFormField>(find.byKey(const ValueKey<String>('finance_expense_amount'))).controller!.text, '2.500,00');
      expect(t.widget<TextFormField>(find.byKey(const ValueKey<String>('finance_expense_description'))).controller!.text, 'Asansör bakımı');
      await f4Enter(t, 'finance_expense_amount', '2.600,00');
      await f4Tap(t, 'finance_expense_account_1');
      // Yeni gider reddedilir (kapalı ay): eski gider da iptal olmamalı.
      auth.f4.closedMonths.add('2026-10');
      await f4Tap(t, 'finance_expense_submit');
      expect(find.textContaining('Bu dönem kapatılmış'), findsOneWidget);
      expect(auth.f4.expenses.firstWhere((e) => e['id'] == 2)['voided'], isNull, reason: 'yarım kalmaz');
      auth.f4.closedMonths.clear();
      await f4Tap(t, 'finance_expense_submit');
      await settleFor(t);
      expect(auth.f4.expenses.firstWhere((e) => e['id'] == 2)['voided'], isNotNull);
      expect(auth.f4.expenses.last['corrects_expense_id'], 2);
      expect(auth.f4.expenses.last['amount_minor'], 260000);
      expect(find.textContaining('Gider düzeltildi: 2.600,00 ₺'), findsOneWidget);
    });

    testWidgets('ekler listelenir; seçici verilmişse Belge Ekle çalışır', (t) async {
      final auth = _auth();
      auth.f4.expenseDocuments[2] = <Map<String, dynamic>>[
        <String, dynamic>{'id': 5, 'status': 'ready', 'display_name': 'fatura.pdf', 'kind': 'invoice', 'size_bytes': 100},
      ];
      final source = _FakeSource(<PickedExpenseFile>[_file('yeni.png')]);
      await openDetail(t, auth, source: source);
      expect(find.text('fatura.pdf • Fatura'), findsOneWidget);
      await f4Tap(t, 'finance_expense_detail_add_file');
      await settleFor(t);
      expect(auth.f4.uploads, 1);
      expect(find.text('yeni.png • Fotoğraf'), findsOneWidget);
    });
  });

  group('R14: kaydedilmemiş veri koruması (Vazgeç / geri tuşu)', () {
    testWidgets('gider ekle: yazılmış veri varken Vazgeç / geri tuşu onay sorar; hiçbir şey yazılmaz', (t) async {
      final auth = _auth();
      await _pumpTab(t, auth);
      await f4ExpectDiscardGuard(
        t,
        markerKey: 'finance_expense_submit',
        open: () async {
          await f4Tap(t, 'finance_expense_add');
          await settleFor(t);
        },
        edit: () async => f4Enter(t, 'finance_expense_description', 'Ekim ayı elektrik'),
      );
      expect(auth.f4.callCount('createExpense'), 0);
    });

    testWidgets('tedarikçi penceresi: yazılmış veri varken onay sorar', (t) async {
      final auth = _auth();
      await _pumpTab(t, auth);
      await f4ExpectDiscardGuard(
        t,
        markerKey: 'finance_supplier_submit',
        open: () async {
          if (find.byKey(const ValueKey<String>('finance_catalog_tab_suppliers')).evaluate().isEmpty) {
            await f4Tap(t, 'finance_expense_catalog');
            await settleFor(t);
          }
          await f4Tap(t, 'finance_catalog_tab_suppliers');
          await settleFor(t);
          await f4Tap(t, 'finance_catalog_supplier_edit_61');
          await settleFor(t);
        },
        edit: () async => f4Enter(t, 'finance_supplier_phone', '05551112233'),
      );
      expect(auth.f4.writes.where((w) => w['op'] == 'updateSupplier'), isEmpty);
    });
  });

  group('Kategori ve tedarikçi yönetimi', () {
    Future<void> openCatalog(WidgetTester t, FinanceFakeAuth auth, {bool canWrite = true}) async {
      await _pumpTab(t, auth, canWrite: canWrite);
      await f4Tap(t, 'finance_expense_catalog');
      await settleFor(t);
    }

    testWidgets('kategoriler listelenir (hazır / pasif rozet); ekleme doğrulanır ve yazılır', (t) async {
      final auth = _auth();
      await openCatalog(t, auth);
      expect(find.byKey(const ValueKey<String>('finance_category_1')), findsOneWidget);
      expect(find.text('Hazır kategori'), findsWidgets);
      expect(find.text('Pasif'), findsOneWidget);
      await f4Tap(t, 'finance_category_add');
      expect(find.text('Kategori adını girin.'), findsOneWidget);
      await f4Enter(t, 'finance_category_name', 'Boya badana');
      await f4Tap(t, 'finance_category_add');
      await settleFor(t);
      expect(auth.f4.categories.any((c) => c['name'] == 'Boya badana'), isTrue);
      expect(find.byKey(const ValueKey<String>('finance_category_40')), findsOneWidget);
    });

    testWidgets('kategori adı çakışması Türkçe hata; kategori pasifleştirilir', (t) async {
      final auth = _auth();
      await openCatalog(t, auth);
      await f4Enter(t, 'finance_category_name', 'elektrik');
      await f4Tap(t, 'finance_category_add');
      expect(find.text('Bu adla başka bir kategori var.'), findsOneWidget);
      await f4Tap(t, 'finance_category_edit_2');
      await f4Tap(t, 'finance_category_save');
      expect(find.text('Değişiklik yapmadınız.'), findsOneWidget);
      await f4Tap(t, 'finance_category_active');
      await f4Tap(t, 'finance_category_save');
      await settleFor(t);
      expect(auth.f4.categories.firstWhere((c) => c['id'] == 2)['is_active'], false);
    });

    testWidgets('kategori listesi hatası: "kategori yok" yazılmaz', (t) async {
      final auth = _auth();
      auth.f4.categoriesError = ApiException('x', statusCode: 500);
      await openCatalog(t, auth);
      expect(find.text('Henüz kategori yok.'), findsNothing);
      expect(find.text('Tekrar Dene'), findsWidgets);
    });

    testWidgets('tedarikçiler: listele, düzenle (yalnız değişen alan), pasifleştir', (t) async {
      final auth = _auth();
      await openCatalog(t, auth);
      await f4Tap(t, 'finance_catalog_tab_suppliers');
      await settleFor(t);
      expect(find.byKey(const ValueKey<String>('finance_catalog_supplier_61')), findsOneWidget);
      expect(find.text('Vergi / T.C. no: 1234567890'), findsOneWidget);
      await f4Tap(t, 'finance_catalog_supplier_edit_61');
      await f4Tap(t, 'finance_supplier_submit');
      expect(find.text('Değişiklik yapmadınız.'), findsOneWidget);
      await f4Enter(t, 'finance_supplier_phone', '05551112233');
      await f4Tap(t, 'finance_supplier_submit');
      await settleFor(t);
      final write = auth.f4.writes.firstWhere((w) => w['op'] == 'updateSupplier');
      expect(write['phone'], '05551112233');
      expect(write.containsKey('name'), isFalse);
    });

    testWidgets('kurul: ekleme / düzenleme yok', (t) async {
      final auth = _auth();
      await openCatalog(t, auth, canWrite: false);
      expect(find.byKey(const ValueKey<String>('finance_category_add')), findsNothing);
      expect(find.byKey(const ValueKey<String>('finance_category_edit_1')), findsNothing);
      await f4Tap(t, 'finance_catalog_tab_suppliers');
      await settleFor(t);
      expect(find.byKey(const ValueKey<String>('finance_catalog_supplier_add')), findsNothing);
    });

    f4Matrix('katalog penceresi taşmaz', (t, w, h, s, dark) async {
      final auth = _auth();
      await _pumpTab(t, auth, width: w, height: h, scale: s, dark: dark);
      await f4Tap(t, 'finance_expense_catalog');
      await settleFor(t);
      expect(find.byType(FinanceCatalogDialog), findsOneWidget);
      await f4Tap(t, 'finance_catalog_tab_suppliers');
      await settleFor(t);
    });
  });
}
