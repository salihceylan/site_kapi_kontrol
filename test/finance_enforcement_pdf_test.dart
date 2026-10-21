// F8 icra dökümü: model ayrıştırma + PDF içeriği (bilgi alanı, gecikme tazminatı, avukat kontrolü notu).
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/enforcement_models.dart';
import 'package:site_kapi_kontrol/services/pdf_finance_service.dart';

import 'support/pdf_text_probe.dart';

Map<String, dynamic> _json() => <String, dynamic>{
  'site': <String, dynamic>{'name': 'Işık Sitesi'},
  'as_of': '2026-10-21',
  'note': 'Bu döküm bilgi amaçlıdır.',
  'accounts': <Map<String, dynamic>>[
    <String, dynamic>{
      'apartment_id': 5,
      'label': '3',
      'block_name': 'A',
      'account_party': 'tenant',
      'person_name': 'Çağla Şen',
      'principal_minor': 10000,
      'late_fee_minor': 300,
      'total_minor': 10300,
      'items': <Map<String, dynamic>>[
        <String, dynamic>{'name': 'Aidat', 'due_date': '2026-01-10', 'period': '2026-01-01', 'is_late_fee': false, 'remaining_minor': 10000, 'days_overdue': 284},
        <String, dynamic>{'name': 'Gecikme', 'due_date': '2026-02-10', 'period': '2026-02-01', 'is_late_fee': true, 'remaining_minor': 300, 'days_overdue': 253},
      ],
    },
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => PdfFinanceService.debugCompress = false);
  tearDown(() => PdfFinanceService.debugCompress = true);

  test('model: hesap anahtarı ve seçim süzgeci', () {
    final report = EnforcementReport.fromJson(_json());
    expect(report.accounts.single.key, '5:tenant');
    expect(report.accounts.single.items.length, 2);
    expect(report.only(<String>{'9:owner'}).accounts, isEmpty);
    expect(report.only(<String>{'5:tenant'}).accounts.length, 1);
  });

  test('PDF: kişi, kalemler, tazminat, bilgi alanı ve avukat notu', () async {
    final report = EnforcementReport.fromJson(_json());
    final bytes = await PdfFinanceService.generateEnforcementPdf(report: report, basisNote: '2026 işletme projesi', printedAt: DateTime.utc(2026, 10, 21));
    final text = extractPdfText(bytes);
    expect(text, contains('İcra Dökümü'));
    expect(text, contains('Kiracı hesabı'));
    expect(text, contains('Çağla Şen'));
    expect(text, contains('Gecikme tazminatı'));
    expect(text, contains('2026 işletme projesi'));
    expect(text, contains('Avukat kontrolü'));
    final blank = extractPdfText(await PdfFinanceService.generateEnforcementPdf(report: report, printedAt: DateTime.utc(2026, 10, 21)));
    expect(blank, contains('........'));
  });
}
