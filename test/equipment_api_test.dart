import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/services/equipment_api.dart';

void main() {
  test('formatKurus ve parseKurus tamsayı kuruş ile çalışır', () {
    expect(formatKurus(123450), '1.234,50 TL');
    expect(formatKurus(5), '0,05 TL');
    expect(formatKurus(-100), '-1,00 TL');
    expect(parseKurus('1.250,5'), 125050);
    expect(parseKurus('12'), 1200);
    expect(parseKurus('1,234'), isNull);
    expect(parseKurus('abc'), isNull);
  });

  test('varsayılan türler ve yıllık yasal kontrol', () {
    expect(equipmentKinds.length, 9);
    expect(equipmentKinds.firstWhere((k) => k.code == 'asansor').legalMonths, 12);
    expect(equipmentKindLabel('hidrofor'), 'Hidrofor');
    expect(equipmentKindLabel('ozel'), 'ozel');
    expect(intervalLabel(12), 'Yılda bir');
    expect(intervalLabel(3), '3 ayda bir');
  });

  test('teklif ve plan JSON eşlemesi', () {
    final q = EquipmentQuote.fromJson(<String, dynamic>{
      'id': 4,
      'topic': 'Asansör bakımı',
      'vendor_name': 'Yıldız',
      'amount_kurus': 250000,
      'status': 'open',
      'lowest': true,
      'expired': false,
    });
    expect(q.amountKurus, 250000);
    expect(q.lowest, isTrue);
    final p = MaintenancePlan.fromJson(<String, dynamic>{'id': 1, 'title': 'Yıllık', 'interval_months': 12, 'legal': true, 'next_due': '2026-12-01', 'days_left': -3});
    expect(p.legal, isTrue);
    expect(p.daysLeft, -3);
  });

  group('teklif karşılaştırma alanları ve sürümler (098 / 099)', () {
    test('eski sunucu yanıtı (yeni alan yok): varsayılanlar güvenli, açık teklif düzenlenebilir, revizyon yok', () {
      final q = EquipmentQuote.fromJson(<String, dynamic>{'id': 4, 'topic': 'Asansör', 'vendor_name': 'Y', 'amount_kurus': 250000, 'status': 'open'});
      expect(q.deliveryDays, isNull);
      expect(q.note, isNull);
      expect(q.vatIncluded, isNull);
      expect(q.vatLabel, 'KDV belirtilmedi');
      expect(q.deliveryLabel, isNull);
      expect(q.revisionNo, 1);
      expect(q.isRevision, isFalse);
      expect(q.hasHistory, isFalse);
      expect(q.versionCount, 1);
      expect(q.approvedVersion, isNull);
      expect(q.editable, isTrue, reason: 'eski sunucuda da açık teklif yerinde düzenlenebilir sayılır');
      expect(q.revisable, isFalse);
      expect(q.fastest, isFalse);
      expect(q.basisMixed, isFalse);
      final accepted = EquipmentQuote.fromJson(<String, dynamic>{'id': 5, 'topic': 'T', 'vendor_name': 'Y', 'amount_kurus': 1, 'status': 'accepted'});
      expect(accepted.editable, isFalse);
    });

    test('karşılaştırma alanları eşlenir: teslim süresi, kapsam / not, KDV esası, en hızlı, karışık esas', () {
      final q = EquipmentQuote.fromJson(<String, dynamic>{
        'id': 7,
        'topic': 'Kamera',
        'vendor_name': 'A',
        'amount_kurus': 500000,
        'status': 'open',
        'delivery_days': 14,
        'note': 'Kontrol + kontak seti',
        'vat_included': false,
        'fastest': true,
        'lowest': false,
        'basis_mixed': true,
      });
      expect(q.deliveryDays, 14);
      expect(q.deliveryLabel, '14 gün');
      expect(q.note, 'Kontrol + kontak seti');
      expect(q.vatIncluded, isFalse);
      expect(q.vatLabel, 'KDV hariç');
      expect(q.fastest, isTrue);
      expect(q.basisMixed, isTrue);
      expect(EquipmentQuote.fromJson(<String, dynamic>{'id': 8, 'vat_included': true}).vatLabel, 'KDV dahil');
      expect(EquipmentQuote.fromJson(<String, dynamic>{'id': 9, 'delivery_days': 0}).deliveryLabel, '0 gün');
    });

    test('sürüm bilgisi: önceki sürüme bağ, gerekçe, onaylı sürüm özeti (bekleyen revizyon)', () {
      final q = EquipmentQuote.fromJson(<String, dynamic>{
        'id': 12,
        'topic': 'Asansör bakımı',
        'vendor_name': 'Yıldız',
        'amount_kurus': 380000,
        'status': 'open',
        'revision_no': 2,
        'previous_id': 11,
        'revision_reason': 'Ek parça ihtiyacı',
        'version_count': 2,
        'has_history': true,
        'editable': true,
        'revisable': false,
        'approved_version': <String, dynamic>{
          'id': 11,
          'revision_no': 1,
          'amount_kurus': 320000,
          'decided_at': '2026-10-24T09:00:00.000Z',
          'accepted_as': 'contract',
          'expense_id': null,
          'contract_id': 501,
        },
      });
      expect(q.isRevision, isTrue);
      expect(q.hasHistory, isTrue);
      expect(q.previousId, 11);
      expect(q.revisionReason, 'Ek parça ihtiyacı');
      expect(q.versionCount, 2);
      expect(q.editable, isTrue);
      expect(q.revisable, isFalse);
      final approved = q.approvedVersion!;
      expect(approved.id, 11);
      expect(approved.revisionNo, 1);
      expect(approved.amountKurus, 320000);
      expect(approved.hasRecord, isTrue, reason: 'önceki sürüm sözleşmeye dönüşmüş: yeni sürümün kabulünde çift kayıt uyarısı');
      expect(approved.recordLabel, 'sözleşme');
      expect(const QuoteVersionRef(id: 1, revisionNo: 1, amountKurus: 1, expenseId: 3).recordLabel, 'gider');
      expect(const QuoteVersionRef(id: 1, revisionNo: 1, amountKurus: 1).hasRecord, isFalse);
    });

    test('sürüm geçmişi yanıtı eskiden yeniye eşlenir', () {
      final h = QuoteHistory.fromJson(<String, dynamic>{
        'items': <Map<String, dynamic>>[
          <String, dynamic>{'id': 11, 'topic': 'T', 'vendor_name': 'Y', 'amount_kurus': 320000, 'status': 'accepted', 'revision_no': 1, 'contract_id': 501},
          <String, dynamic>{'id': 12, 'topic': 'T', 'vendor_name': 'Y', 'amount_kurus': 380000, 'status': 'open', 'revision_no': 2, 'previous_id': 11, 'revision_reason': 'Ek parça'},
        ],
        'latest_id': 12,
        'approved_id': 11,
      });
      expect(h.items.map((x) => x.id), <int>[11, 12]);
      expect(h.items.last.previousId, 11);
      expect(h.latestId, 12);
      expect(h.approvedId, 11);
      expect(QuoteHistory.fromJson(const <String, dynamic>{}).items, isEmpty);
    });
  });
}
