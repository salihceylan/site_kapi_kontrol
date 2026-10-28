// İşletme projesi ayrıntısı: "Gider kategorisi bulunamadı" yönlendirmesi. Aidat ve Finans 079'dan beri temel modüldür; eski metin
// "(Aidat ve Finans modülü açık olmalı)" diyordu. DAVRANIŞ değişmez (kategori yoksa kalem girişi yine çizilmez); yalnız metin.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/budget_models.dart';
import 'package:site_kapi_kontrol/models/expense_models.dart';
import 'package:site_kapi_kontrol/services/budget_api.dart';
import 'package:site_kapi_kontrol/ui/views/budget_view.dart';

import 'dialog_layout_harness.dart' show settleFor;
import 'list_fixtures.dart' show pumpList;
import 'people_fixtures.dart' show PeopleFakeAuth;

class _FakeBudgetService extends BudgetService {
  _FakeBudgetService({required super.authService, this.categoryList = const <ExpenseCategory>[]})
    : super(api: BudgetApi(baseUrl: 'http://localhost'));

  final List<ExpenseCategory> categoryList;

  @override
  Future<BudgetDetail> get(int siteCode, int id) async => BudgetDetail.fromJson(<String, dynamic>{
    'project': <String, dynamic>{'id': id, 'year': 2027, 'title': '2027 yılı işletme projesi', 'status': 'taslak'},
    'items': <Map<String, dynamic>>[],
  });

  @override
  Future<List<ExpenseCategory>> categories(int siteCode) async => categoryList;
}

Future<void> _open(WidgetTester t, {List<ExpenseCategory> categories = const <ExpenseCategory>[]}) async {
  final auth = PeopleFakeAuth();
  await pumpList(
    t,
    SizedBox(
      height: 1800,
      child: BudgetDetailPage(
        service: _FakeBudgetService(authService: auth, categoryList: categories),
        site: const BudgetSite(code: 11, name: 'Gül Sitesi'),
        projectId: 7,
      ),
    ),
    width: 400,
    height: 2000,
    scale: 1.0,
    dark: false,
  );
  await settleFor(t, 200);
}

void main() {
  testWidgets('kategori yoksa: modül şartı değil, çözüm yolu (Finans > Giderler > Kategori ve Tedarikçiler) yazar', (t) async {
    await _open(t);
    final hint = find.byKey(const ValueKey<String>('budget_no_categories'));
    expect(hint, findsOneWidget);
    final text = t.widget<Text>(hint).data!;
    expect(text, startsWith('Gider kategorisi bulunamadı.'));
    expect(text, contains('Kategori ve Tedarikçiler'));
    expect(text.toLowerCase(), isNot(contains('modül')), reason: 'Aidat ve Finans temel modüldür; "modül açık olmalı" bayat');
    expect(find.text('Kalemleri kaydet'), findsOneWidget, reason: 'davranış aynı: düğme yine çizilir');
  });

  testWidgets('kategori varsa: ipucu çizilmez, her kategori için tutar kutusu çizilir', (t) async {
    await _open(
      t,
      categories: <ExpenseCategory>[
        ExpenseCategory.fromJson(<String, dynamic>{'id': 1, 'name': 'Asansör'}),
        ExpenseCategory.fromJson(<String, dynamic>{'id': 2, 'name': 'Temizlik'}),
      ],
    );
    expect(find.byKey(const ValueKey<String>('budget_no_categories')), findsNothing);
    expect(find.widgetWithText(TextField, 'Asansör'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Temizlik'), findsOneWidget);
  });
}
