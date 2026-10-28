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

  test('iş kayıtları bölümü: kategori adı sitedeki addır (category_label, 100); yoksa varsayılan ad, yoksa anahtar', () {
    final withWorks = <String, dynamic>{
      ...json,
      'sections': <String, dynamic>{
        ...(json['sections'] as Map<String, dynamic>),
        'works': <String, dynamic>{
          'available': true,
          'total': 7,
          'done': 4,
          'photo_count': 2,
          'by_category': <dynamic>[
            <String, dynamic>{'category': 'ariza', 'category_label': 'Teknik arıza', 'total': 3, 'done': 2},
            <String, dynamic>{'category': 'bakim', 'total': 1, 'done': 1},
            <String, dynamic>{'category': 'k_su_kacagi', 'category_label': 'Su kaçağı', 'total': 3, 'done': 1},
            <String, dynamic>{'category': 'k_eski', 'total': 1, 'done': 0},
          ],
          'closed_items': <dynamic>[],
        },
      },
    };
    final lines = annualReportFinalLines(AnnualReport.fromJson(withWorks), 'works');
    expect(lines.any((l) => l.startsWith('Teknik arıza: 3 kayıt, 2 tamamlandı')), isTrue, reason: 'yeniden adlandırılmış varsayılan kategori');
    expect(lines.any((l) => l.startsWith('Bakım: 1 kayıt, 1 tamamlandı')), isTrue, reason: 'eski sunucu: varsayılan ad');
    expect(lines.any((l) => l.startsWith('Su kaçağı: 3 kayıt, 1 tamamlandı')), isTrue, reason: 'sitenin kategorisi');
    expect(lines.any((l) => l.startsWith('k_eski: 1 kayıt, 0 tamamlandı')), isTrue, reason: 'adı bilinmeyen anahtar anahtarla');
  });

  test('gelecek yıl artış yüzdesi baz puana çevrilir', () {
    expect(AnnualReportViewState.parseGrowthPercent('12,5'), 1250);
    expect(AnnualReportViewState.parseGrowthPercent('0'), 0);
    expect(AnnualReportViewState.parseGrowthPercent('-10'), -1000);
    expect(AnnualReportViewState.parseGrowthPercent('abc'), isNull);
    expect(AnnualReportViewState.parseGrowthPercent('501'), isNull);
  });
}
