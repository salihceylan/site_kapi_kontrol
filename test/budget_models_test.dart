import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/budget_models.dart';
import 'package:site_kapi_kontrol/services/pdf_budget_service.dart';
import 'package:site_kapi_kontrol/services/pdf_font_set.dart';
import 'package:site_kapi_kontrol/ui/views/budget_view.dart';

void main() {
  test('BudgetListResult: dikkat sayacı ve proje alanları okunur', () {
    final r = BudgetListResult.fromJson(<String, dynamic>{
      'items': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 7,
          'year': 2027,
          'title': 'Bütçe',
          'status': 'teblig',
          'is_provisional': true,
          'provisional_until': '2026-11-08',
          'provisional_remaining_days': 18,
          'notified_at': '2026-10-20',
          'objection_days': 7,
          'objection_ends': '2026-10-27',
          'item_count': 3,
          'total_minor': 1200000,
        },
      ],
      'attention': <String, dynamic>{
        'provisional': <String, dynamic>{'remaining_days': 18, 'title': 'Bütçe'},
      },
    });
    expect(r.projects.single.status, BudgetStatus.teblig);
    expect(r.projects.single.remainingDays, 18);
    expect(r.projects.single.totalMinor, 1200000);
    expect(r.provisionalRemainingDays, 18);
  });

  test('BudgetListResult: açık geçici proje yoksa sayaç null', () {
    final r = BudgetListResult.fromJson(<String, dynamic>{'items': <Object>[], 'attention': <String, dynamic>{'provisional': null}});
    expect(r.provisionalRemainingDays, isNull);
  });

  test('budgetRemainingText', () {
    expect(budgetRemainingText(18), 'Geçici proje: son 18 gün');
    expect(budgetRemainingText(0), 'Geçici proje süresi doldu');
  });

  test('PDF dosya adı ASCII ve PDF baytları üretilir', () async {
    expect(PdfBudgetService.fileName('Gül Sitesi', 2027), startsWith('Isletme_Projesi_'));
    final comparison = BudgetComparison.fromJson(<String, dynamic>{
      'project': <String, dynamic>{'id': 1, 'year': 2027, 'title': 'T', 'status': 'taslak'},
      'rows': <Map<String, dynamic>>[
        <String, dynamic>{'category_name': 'Asansör', 'planned_minor': 1000, 'actual_minor': 1500, 'variance_minor': 500, 'used_pct': 150.0},
      ],
      'totals': <String, dynamic>{'category_name': 'Toplam', 'planned_minor': 1000, 'actual_minor': 1500, 'variance_minor': 500, 'used_pct': 150.0},
    });
    final bytes = await PdfBudgetService.generate(siteName: 'Gül Sitesi', comparison: comparison, fonts: PdfFontSet.helvetica);
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });
}
