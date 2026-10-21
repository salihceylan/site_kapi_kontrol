import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/annual_report.dart';
import 'package:site_kapi_kontrol/ui/views/annual_report_view.dart';

void main() {
  final json = <String, dynamic>{
    'year': 2025,
    'draft': <String, dynamic>{'edits': <String, dynamic>{'general': 'Özel metin', 'works': '  '}, 'growth_bp': 2500, 'saved': true, 'updated_at': null},
    'sections': <String, dynamic>{
      'general': <String, dynamic>{'available': true, 'site_name': 'Güneş Sitesi', 'block_count': 2, 'apartment_count': 40},
      'finance': <String, dynamic>{
        'available': true,
        'income_minor': 100000,
        'expense_minor': 80000,
        'net_minor': 20000,
        'expense_by_category': <dynamic>[],
        'budget': null,
      },
      'contracts': <String, dynamic>{'available': false},
      'maintenance': <String, dynamic>{'available': true, 'work_items': <String, dynamic>{'total': 3, 'done': 2}, 'contracts': <dynamic>[]},
    },
  };

  test('rapor JSON ayrıştırılır, boş düzenleme atılır', () {
    final r = AnnualReport.fromJson(json);
    expect(r.year, 2025);
    expect(r.growthBp, 2500);
    expect(r.saved, isTrue);
    expect(r.edits.keys, <String>['general']);
  });

  test('bölüm satırları: modül kapalı, sistem taslağı ve düzenleme önceliği', () {
    final r = AnnualReport.fromJson(json);
    expect(annualReportFinalLines(r, 'general'), <String>['Özel metin']);
    expect(annualReportFinalLines(r, 'contracts').single, contains('kapalı'));
    expect(annualReportFinalLines(r, 'finance').first, contains('1.000,00'));
    expect(annualReportFinalLines(r, 'finance').last, contains('bütçe'));
    expect(annualReportFinalLines(r, 'maintenance').last, contains('Yakında'));
    expect(annualReportFinalLines(r, 'works').single, contains('kapalı'));
  });

  test('gelecek yıl artış yüzdesi baz puana çevrilir', () {
    expect(AnnualReportViewState.parseGrowthPercent('12,5'), 1250);
    expect(AnnualReportViewState.parseGrowthPercent('0'), 0);
    expect(AnnualReportViewState.parseGrowthPercent('-10'), -1000);
    expect(AnnualReportViewState.parseGrowthPercent('abc'), isNull);
    expect(AnnualReportViewState.parseGrowthPercent('501'), isNull);
  });
}
