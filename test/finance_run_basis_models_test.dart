// Tahakkuk dayanağı (K2, P1-2) ve sakin kalem dökümü (P2-1) modelleri (sözleşme: docs/PLATFORM_FINANS_KARAR_BAGI.md).
// Kural: alan yoksa (eski sunucu) null/boş gelir ve ekran bölüm GÖSTERMEZ; para tamsayı kuruş; bozuk tutar sessizce 0 olmaz.
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/finance.dart';
import 'package:site_kapi_kontrol/models/finance_funds.dart';

Map<String, dynamic> _entry(Map<String, dynamic> extra) => <String, dynamic>{
  'id': 7,
  'kind': 'charge',
  'amount_minor': 100000,
  'period': '2026-10',
  'entry_date': '2026-10-01',
  'due_date': '2026-10-15',
  'definition_name': 'Asansör yenileme',
  ...extra,
};

Map<String, dynamic> _item(Map<String, dynamic> extra) => <String, dynamic>{
  'entry_id': 902,
  'type': 'one_time',
  'name': 'Asansör yenileme',
  'fund': 'capital',
  'period': '2026-10',
  'due_date': '2026-10-15',
  'overdue': true,
  'amount_minor': 100000,
  'remaining_minor': 93000,
  'decision': null,
  ...extra,
};

void main() {
  group('DecisionRequirement', () {
    test('Fon + modül açık: karar; kapalı: gerekçe; işletme: yok', () {
      final decision = DecisionRequirement.tryParse(<String, dynamic>{
        'required': true,
        'mode': 'decision',
        'module_enabled': true,
        'reason_min': 3,
        'reason_max': 300,
      })!;
      expect([decision.isRequired, decision.mode, decision.moduleEnabled], [true, RunBasisMode.decision, true]);
      final reason = DecisionRequirement.tryParse(<String, dynamic>{'required': true, 'mode': 'reason', 'module_enabled': false})!;
      expect([reason.isRequired, reason.mode, reason.moduleEnabled, reason.reasonMin, reason.reasonMax], [true, RunBasisMode.reason, false, 3, 300]);
      final none = DecisionRequirement.tryParse(<String, dynamic>{'required': false, 'mode': 'none'})!;
      expect([none.isRequired, none.mode], [false, RunBasisMode.none]);
    });

    test('alan yoksa / bozuksa null; zorunlu ama modu bilinmeyen en güvenli girdiyi (gerekçe) ister', () {
      expect(DecisionRequirement.tryParse(null), isNull);
      expect(DecisionRequirement.tryParse('x'), isNull);
      expect(DecisionRequirement.tryParse(<String, dynamic>{'required': true, 'mode': 'yeni_bir_kip'})!.mode, RunBasisMode.reason);
      expect(DecisionRequirement.tryParse(<String, dynamic>{'required': false, 'mode': 'yeni_bir_kip'})!.mode, RunBasisMode.none);
    });

    test('FeePreview.decisionRequirement önizleme yanıtından okunur; eski sunucuda null', () {
      final base = <String, dynamic>{'total_minor': 300000, 'apartment_count': 3, 'lines': <dynamic>[]};
      expect(FeePreview.fromJson(base).decisionRequirement, isNull);
      final withRequirement = FeePreview.fromJson(<String, dynamic>{
        ...base,
        'decision_requirement': <String, dynamic>{'required': true, 'mode': 'decision', 'module_enabled': true},
      });
      expect(withRequirement.decisionRequirement!.mode, RunBasisMode.decision);
    });
  });

  group('LedgerDecision / LedgerEntry.decision', () {
    test('karar + başlık + gerekçe özeti; yalnız gerekçe; boşsa null', () {
      final both = LedgerDecision.tryParse(<String, dynamic>{'id': 77, 'number_label': '2026/4', 'title': 'Asansör yenileme', 'reason': 'Ek not'})!;
      expect(both.summary, 'Karar 2026/4 · Asansör yenileme · Ek not');
      expect(both.id, 77);
      final numberOnly = LedgerDecision.tryParse(<String, dynamic>{'number_label': '2026/6', 'title': null, 'reason': null})!;
      expect(numberOnly.summary, 'Karar 2026/6');
      final reasonOnly = LedgerDecision.tryParse(<String, dynamic>{'number_label': null, 'reason': 'Yönetim kurulu 3 Ekim'})!;
      expect(reasonOnly.summary, 'Gerekçe: Yönetim kurulu 3 Ekim');
      expect(LedgerDecision.tryParse(<String, dynamic>{'number_label': null, 'title': 'Yalnız başlık', 'reason': null}), isNull);
      expect(LedgerDecision.tryParse(null), isNull);
      expect(LedgerDecision.tryParse('x'), isNull);
    });

    test('LedgerEntry.fromJson dayanağı okur; yoksa null (işletme hesabı, tahsilat, eski sunucu)', () {
      expect(LedgerEntry.fromJson(_entry(<String, dynamic>{})).decision, isNull);
      final entry = LedgerEntry.fromJson(_entry(<String, dynamic>{
        'decision': <String, dynamic>{'number_label': '2026/4', 'title': 'Asansör yenileme', 'reason': null},
      }));
      expect(entry.decision!.numberLabel, '2026/4');
      expect(entry.decision!.summary, 'Karar 2026/4 · Asansör yenileme');
    });
  });

  group('ExtraChargeInput dayanağı', () {
    const base = ExtraChargeInput(name: ' Asansör ', distribution: FeeDistribution.equal, amountMinor: 1000, fund: FinanceFund.capital);

    test('dayanak yoksa gövdede alan YOK (önizleme ve eski sunucu); verilince karar kimliği ve kırpılmış gerekçe gider', () {
      final plain = base.toJson();
      expect(plain.containsKey('decision_id'), isFalse);
      expect(plain.containsKey('decision_reason'), isFalse);
      final withDecision = base.withBasis(decisionId: 77).toJson();
      expect(withDecision['decision_id'], 77);
      expect(withDecision.containsKey('decision_reason'), isFalse);
      final withReason = base.withBasis(decisionReason: '  Kurul kararı  ').toJson();
      expect(withReason['decision_reason'], 'Kurul kararı');
      expect(withReason.containsKey('decision_id'), isFalse);
      expect(base.withBasis(decisionReason: '   ').toJson().containsKey('decision_reason'), isFalse);
    });

    test('withBasis diğer alanları AYNEN korur (kasa, tutar, hedef, vade)', () {
      final due = DateTime(2026, 11, 15);
      final input = ExtraChargeInput(
        name: 'Boya',
        distribution: FeeDistribution.fixed,
        amountMinor: 250,
        dueDate: due,
        fund: FinanceFund.operating,
      );
      final json = input.withBasis(decisionId: 5).toJson();
      expect(json['name'], 'Boya');
      expect(json['distribution'], 'fixed');
      expect(json['amount_minor'], 250);
      expect(json['fund'], 'operating');
      expect(json['due_date'], '2026-11-15');
      expect(json['decision_id'], 5);
    });
  });

  group('DebtBreakdown (kalem dökümü)', () {
    test('kalem: dönem, tür, hesap, vade, kalan; ödenen = tutar - kalan; karar numarası ve gerekçe', () {
      final item = DebtBreakdownItem.fromJson(_item(<String, dynamic>{
        'decision': <String, dynamic>{'number_label': '2026/4', 'title': 'Asansör yenileme', 'reason': null},
      }));
      expect(item.entryId, 902);
      expect(item.type, DebtItemType.oneTime);
      expect(item.fund, FinanceFund.capital);
      expect(item.period!.label, 'Ekim 2026');
      expect(item.overdue, isTrue);
      expect(item.amountMinor, 100000);
      expect(item.remainingMinor, 93000);
      expect(item.paidMinor, 7000);
      expect(item.title, 'Asansör yenileme');
      expect(item.decision!.summary, 'Karar 2026/4 · Asansör yenileme');
    });

    test('ad yoksa tür adı başlık olur; bilinmeyen tür "Diğer borç"', () {
      expect(DebtBreakdownItem.fromJson(_item(<String, dynamic>{'name': null, 'type': 'opening'})).title, 'Devir bakiyesi');
      expect(DebtBreakdownItem.fromJson(_item(<String, dynamic>{'name': '  ', 'type': 'late_fee'})).title, 'Gecikme tazminatı');
      expect(DebtBreakdownItem.fromJson(_item(<String, dynamic>{'name': null, 'type': 'monthly'})).title, 'Aylık borç');
      expect(DebtBreakdownItem.fromJson(_item(<String, dynamic>{'name': null, 'type': 'yeni'})).type, DebtItemType.other);
    });

    test('bozuk/eksik tutar SESSİZCE 0 olmaz (FormatException); kalem listesi kuruş toplamı', () {
      expect(() => DebtBreakdownItem.fromJson(_item(<String, dynamic>{'remaining_minor': 'abc'})), throwsFormatException);
      expect(() => DebtBreakdownItem.fromJson(_item(<String, dynamic>{'amount_minor': null})), throwsFormatException);
      final breakdown = DebtBreakdown.tryParse(<String, dynamic>{
        'items': <dynamic>[_item(<String, dynamic>{}), _item(<String, dynamic>{'entry_id': 903, 'remaining_minor': 50000})],
        'truncated': true,
      })!;
      expect(breakdown.items.length, 2);
      expect(breakdown.totalRemainingMinor, 143000);
      expect(breakdown.truncated, isTrue);
    });

    test('alan yoksa null (eski sunucu: bölüm çizilmez, "borç yok" DENMEZ); MyFinanceApartment hem üst düzeyde hem hesapta okur', () {
      expect(DebtBreakdown.tryParse(null), isNull);
      final apartmentJson = <String, dynamic>{
        'site_code': 11,
        'apartment_id': 301,
        'balance_minor': 143000,
        'breakdown': <String, dynamic>{'items': <dynamic>[_item(<String, dynamic>{})], 'truncated': false},
        'accounts': <dynamic>[
          <String, dynamic>{
            'account_party': 'owner',
            'role': 'own',
            'balance_minor': 143000,
            'breakdown': <String, dynamic>{'items': <dynamic>[_item(<String, dynamic>{})], 'truncated': false},
          },
        ],
      };
      final apartment = MyFinanceApartment.fromJson(apartmentJson);
      expect(apartment.breakdown!.items.single.remainingMinor, 93000);
      expect(apartment.accounts.single.breakdown!.items.single.remainingMinor, 93000);
      expect(apartment.ownAccount.breakdown!.items.single.entryId, 902);
      final legacy = MyFinanceApartment.fromJson(<String, dynamic>{'site_code': 11, 'apartment_id': 301, 'balance_minor': 0});
      expect(legacy.breakdown, isNull);
      expect(legacy.ownAccount.breakdown, isNull);
    });
  });
}
