// Platform Faz 4a (Aidat ve Finans): modeller (lib/models/finance.dart; sözleşme docs/PLATFORM_FINANS.md).
//
// Ayrıştırma KATI-GÜVENLİdir: para alanı okunamazsa sessiz 0 yapılmaz (FormatException); bilinmeyen sayım
// değerleri `unknown` olur; sunucunun hem düz hem iç içe hedef alanları okunur; tutarlar kuruş tamsayıdır.
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/audit_log.dart';
import 'package:site_kapi_kontrol/models/finance.dart';
import 'package:site_kapi_kontrol/models/residency_relation.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/views/audit_log_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/audit_log_card.dart';

Map<String, dynamic> _entry({
  int id = 1,
  String kind = 'charge',
  Object? amount = 50000,
  Map<String, dynamic>? extra,
}) => <String, dynamic>{
  'id': id,
  'kind': kind,
  'amount_minor': amount,
  'period': '2026-10',
  'entry_date': '2026-10-01',
  'due_date': '2026-10-15',
  'description': 'Aidat',
  'method': null,
  'payer_party': 'owner',
  'definition_name': 'Aylık aidat',
  'reverses_entry_id': null,
  'reversed_by_entry_id': null,
  'reversal_reason': null,
  'created_by_name': 'Site Yöneticisi',
  'created_at': '2026-10-01T09:00:00.000Z',
  ...?extra,
};

void main() {
  group('financeMinor: kuruş okuma', () {
    test('tamsayı, tam değerli sayı ve rakam metni kabul edilir', () {
      expect(financeMinor(125050), 125050);
      expect(financeMinor(-125050), -125050);
      expect(financeMinor(0), 0);
      expect(financeMinor(125050.0), 125050);
      expect(financeMinor('125050'), 125050);
      expect(financeMinor(' -50 '), -50);
      expect(financeMinor('9007199254740991'), 9007199254740991);
    });

    test('kesirli, bozuk, boş ve güvenli sınır dışı değer null (sessiz 0 YOK)', () {
      expect(financeMinor(12.5), isNull);
      expect(financeMinor(double.nan), isNull);
      expect(financeMinor(double.infinity), isNull);
      expect(financeMinor('12,5'), isNull);
      expect(financeMinor('abc'), isNull);
      expect(financeMinor(''), isNull);
      expect(financeMinor(null), isNull);
      expect(financeMinor(true), isNull);
      expect(financeMinor('9007199254740993'), isNull);
      expect(financeMinor(<int>[1]), isNull);
    });
  });

  group('FinancePeriod', () {
    test('YYYY-AA, YYYY-AA-GG ve zaman damgası okunur; bozuk değer null', () {
      expect(FinancePeriod.tryParse('2026-10'), const FinancePeriod(2026, 10));
      expect(FinancePeriod.tryParse('2026-10-01'), const FinancePeriod(2026, 10));
      expect(FinancePeriod.tryParse('2026-10-01T00:00:00.000Z'), const FinancePeriod(2026, 10));
      expect(FinancePeriod.tryParse(null), isNull);
      expect(FinancePeriod.tryParse(''), isNull);
      expect(FinancePeriod.tryParse('2026-13'), isNull);
      expect(FinancePeriod.tryParse('2026-00'), isNull);
      expect(FinancePeriod.tryParse('Ekim'), isNull);
    });

    test('ay aritmetiği yıl sınırını aşar; API biçimi YYYY-AA; etiket Türkçe', () {
      const dec = FinancePeriod(2026, 12);
      expect(dec.next, const FinancePeriod(2027, 1));
      expect(const FinancePeriod(2027, 1).previous, dec);
      expect(dec.addMonths(14), const FinancePeriod(2028, 2));
      expect(dec.addMonths(-12), const FinancePeriod(2025, 12));
      expect(const FinancePeriod(2026, 3).toApi(), '2026-03');
      expect(const FinancePeriod(2026, 10).label, 'Ekim 2026');
      expect(const FinancePeriod(2026, 1).label, 'Ocak 2026');
      expect(const FinancePeriod(2026, 10).firstDay, DateTime(2026, 10, 1));
    });

    test('karşılaştırma ve eşitlik', () {
      expect(const FinancePeriod(2026, 9) < const FinancePeriod(2026, 10), isTrue);
      expect(const FinancePeriod(2027, 1) > const FinancePeriod(2026, 12), isTrue);
      expect(const FinancePeriod(2026, 10) <= const FinancePeriod(2026, 10), isTrue);
      expect(const FinancePeriod(2026, 10) >= const FinancePeriod(2026, 11), isFalse);
      expect(const FinancePeriod(2026, 10).hashCode, const FinancePeriod(2026, 10).hashCode);
      final sorted = <FinancePeriod>[
        const FinancePeriod(2026, 10),
        const FinancePeriod(2025, 12),
        const FinancePeriod(2026, 2),
      ]..sort();
      expect(sorted.map((p) => p.toApi()), <String>['2025-12', '2026-02', '2026-10']);
    });
  });

  group('sayımlar', () {
    test('bilinmeyen tür / dağıtım unknown olur ve eylem sunulmaz', () {
      expect(FeeKind.fromApi('recurring'), FeeKind.recurring);
      expect(FeeKind.fromApi('one_time'), FeeKind.oneTime);
      expect(FeeKind.fromApi('weekly'), FeeKind.unknown);
      expect(FeeKind.fromApi(null), FeeKind.unknown);
      expect(FeeDistribution.fromApi('land_share'), FeeDistribution.landShare);
      expect(FeeDistribution.fromApi('Equal'), FeeDistribution.equal);
      expect(FeeDistribution.fromApi('random'), FeeDistribution.unknown);
      final d = FeeDefinition.fromJson(<String, dynamic>{'id': 1, 'kind': 'x', 'distribution': 'y'});
      expect(d.isKnown, isFalse);
    });

    test('dağıtım: tutar daire başı mı toplam mı', () {
      expect(FeeDistribution.fixed.amountIsPerApartment, isTrue);
      expect(FeeDistribution.equal.amountIsPerApartment, isFalse);
      expect(FeeDistribution.category.needsAmount, isFalse);
      expect(FeeDistribution.area.needsAmount, isTrue);
      for (final value in FeeDistribution.values) {
        if (value == FeeDistribution.unknown) continue;
        expect(value.label, isNotEmpty);
        expect(value.description, isNotEmpty);
      }
    });

    test('tahsilat yöntemi, defter türü ve m² esası', () {
      expect(PaymentMethod.tryParse('transfer'), PaymentMethod.transfer);
      expect(PaymentMethod.tryParse('card'), isNull);
      expect(PaymentMethod.cash.label, 'Nakit');
      expect(PaymentMethod.transfer.label, 'Havale / EFT');
      expect(LedgerKind.fromApi('reversal'), LedgerKind.reversal);
      expect(LedgerKind.fromApi('x'), LedgerKind.unknown);
      expect(AreaBasis.tryParse('net'), AreaBasis.net);
      expect(AreaBasis.tryParse('foo'), isNull);
      expect(payerPartyLabel(ResponsibleParty.owner), 'Malik öder');
      expect(payerPartyLabel(ResponsibleParty.tenant), 'Kiracı öder');
      expect(payerPartyLabel(ResponsibleParty.both), 'Malik ve kiracı');
    });
  });

  group('FeeTarget', () {
    test('düz alanlar ve iç içe hedef aynı sonucu verir; etiketler okunur', () {
      final flat = FeeTarget.fromJson(<String, dynamic>{
        'target_type': 'blocks',
        'target_block_ids': <int>[2, 1],
        'target_apartment_ids': <int>[],
      });
      final nested = FeeTarget.fromJson(<String, dynamic>{
        'target': <String, dynamic>{
          'type': 'blocks',
          'block_ids': <int>[1, 2],
          'apartment_ids': <int>[],
          'blocks': <Map<String, dynamic>>[
            <String, dynamic>{'id': 1, 'name': 'A Blok'},
            <String, dynamic>{'id': 2, 'name': 'B Blok'},
          ],
          'apartments': <Map<String, dynamic>>[],
        },
      });
      expect(flat.type, FeeTargetType.blocks);
      expect(nested.type, FeeTargetType.blocks);
      expect(nested.blockItems.map((e) => e.label), <String>['A Blok', 'B Blok']);
      expect(flat, nested, reason: 'kimlik KÜMESİ eşitliği (sıra / etiket önemsiz)');
      expect(flat.hashCode, nested.hashCode);
    });

    test('toJson yalnız türe uyan kimlikleri taşır; özet metni', () {
      expect(const FeeTarget().toJson(), <String, dynamic>{'type': 'site'});
      expect(
        const FeeTarget(type: FeeTargetType.blocks, blockIds: <int>[1, 2], apartmentIds: <int>[9]).toJson(),
        <String, dynamic>{'type': 'blocks', 'block_ids': <int>[1, 2]},
      );
      expect(
        const FeeTarget(type: FeeTargetType.apartments, apartmentIds: <int>[5]).toJson(),
        <String, dynamic>{'type': 'apartments', 'apartment_ids': <int>[5]},
      );
      expect(const FeeTarget().summary, 'Tüm site');
      expect(const FeeTarget(type: FeeTargetType.blocks, blockIds: <int>[1, 2]).summary, '2 blok');
      expect(const FeeTarget(type: FeeTargetType.apartments).summary, 'Seçili daire yok');
    });

    test('farklı kümeler eşit değildir', () {
      expect(
        const FeeTarget(type: FeeTargetType.blocks, blockIds: <int>[1, 2]) ==
            const FeeTarget(type: FeeTargetType.blocks, blockIds: <int>[1, 3]),
        isFalse,
      );
      expect(const FeeTarget() == const FeeTarget(type: FeeTargetType.blocks), isFalse);
    });
  });

  group('FeeDefinition', () {
    test('tam tanım: tutar, kategori haritası, hedef, dönemler, has_runs', () {
      final d = FeeDefinition.fromJson(<String, dynamic>{
        'id': 7,
        'name': 'Aylık aidat',
        'kind': 'recurring',
        'distribution': 'category',
        'area_basis': null,
        'amount_minor': null,
        'category_amounts': <String, dynamic>{'3+1': 75000, '2+1': '50000'},
        'due_day': 15,
        'start_period': '2026-01',
        'end_period': null,
        'target_type': 'site',
        'target_block_ids': <int>[],
        'target_apartment_ids': <int>[],
        'is_active': true,
        'has_runs': true,
        'last_posted_period': '2026-09',
      });
      expect(d.id, 7);
      expect(d.kind, FeeKind.recurring);
      expect(d.distribution, FeeDistribution.category);
      expect(d.amountMinor, isNull);
      expect(d.categoryAmounts, <String, int>{'3+1': 75000, '2+1': 50000});
      expect(d.dueDay, 15);
      expect(d.startPeriod, const FinancePeriod(2026, 1));
      expect(d.endPeriod, isNull);
      expect(d.lastPostedPeriod, const FinancePeriod(2026, 9));
      expect(d.hasRuns, isTrue);
      expect(d.neverPosted, isFalse);
      expect(d.isKnown, isTrue);
      expect(d.isRecurring, isTrue);
    });

    test('neverPosted: has_runs önceliklidir; yoksa son borçlandırma dönemine bakılır', () {
      expect(FeeDefinition.fromJson(<String, dynamic>{'id': 1, 'has_runs': false, 'last_posted_period': '2026-09'}).neverPosted, isTrue);
      expect(FeeDefinition.fromJson(<String, dynamic>{'id': 1, 'has_runs': true}).neverPosted, isFalse);
      expect(FeeDefinition.fromJson(<String, dynamic>{'id': 1}).neverPosted, isTrue);
      expect(FeeDefinition.fromJson(<String, dynamic>{'id': 1, 'last_posted_period': '2026-09'}).neverPosted, isFalse);
    });

    test('eksik / bozuk alanlarda güvenli varsayılan; tutar okunamazsa null (0 değil)', () {
      final d = FeeDefinition.fromJson(<String, dynamic>{'id': 3, 'amount_minor': 'abc', 'is_active': 'evet'});
      expect(d.amountMinor, isNull);
      expect(d.isActive, isTrue);
      expect(d.name, '');
      expect(d.categoryAmounts, isEmpty);
      expect(d.target.type, FeeTargetType.site);
    });
  });

  group('istek gövdeleri', () {
    test('FeeDefinitionInput: sabit tutar -> amount_minor; kategori ve alan esası ALANLARI GİTMEZ', () {
      final json = const FeeDefinitionInput(
        name: '  Aylık aidat  ',
        kind: FeeKind.recurring,
        distribution: FeeDistribution.fixed,
        amountMinor: 123456,
        dueDay: 15,
        startPeriod: FinancePeriod(2026, 10),
      ).toJson();
      expect(json, <String, dynamic>{
        'name': 'Aylık aidat',
        'kind': 'recurring',
        'distribution': 'fixed',
        'amount_minor': 123456,
        'due_day': 15,
        'start_period': '2026-10',
        'target': <String, dynamic>{'type': 'site'},
      });
      expect(json.containsKey('amount'), isFalse);
      expect(json['amount_minor'], isA<int>());
    });

    test('FeeDefinitionInput: kategori -> category_amounts, tutar yok; m² -> area_basis', () {
      final category = const FeeDefinitionInput(
        name: 'K',
        kind: FeeKind.recurring,
        distribution: FeeDistribution.category,
        amountMinor: 999,
        categoryAmounts: <String, int>{'3+1': 75000},
        dueDay: 1,
        startPeriod: FinancePeriod(2026, 1),
        endPeriod: FinancePeriod(2026, 12),
      ).toJson();
      expect(category.containsKey('amount_minor'), isFalse);
      expect(category['category_amounts'], <String, int>{'3+1': 75000});
      expect(category['end_period'], '2026-12');
      expect(category.containsKey('area_basis'), isFalse);

      final area = const FeeDefinitionInput(
        name: 'M',
        kind: FeeKind.oneTime,
        distribution: FeeDistribution.area,
        areaBasis: AreaBasis.net,
        amountMinor: 1000000,
        categoryAmounts: <String, int>{'x': 1},
        startPeriod: FinancePeriod(2026, 10),
      ).toJson();
      expect(area['area_basis'], 'net');
      expect(area['amount_minor'], 1000000);
      expect(area.containsKey('category_amounts'), isFalse);
      expect(area.containsKey('due_day'), isFalse);
    });

    test('ExtraChargeInput: amount_minor, hedef ve vade (YYYY-AA-GG)', () {
      final json = ExtraChargeInput(
        name: ' Asansör ',
        distribution: FeeDistribution.landShare,
        amountMinor: 12000000,
        target: const FeeTarget(type: FeeTargetType.blocks, blockIds: <int>[1]),
        dueDate: DateTime(2026, 11, 5),
      ).toJson();
      expect(json, <String, dynamic>{
        'name': 'Asansör',
        'distribution': 'land_share',
        'amount_minor': 12000000,
        'target': <String, dynamic>{'type': 'blocks', 'block_ids': <int>[1]},
        'due_date': '2026-11-05',
      });
    });
  });

  group('önizleme', () {
    test('satırlar, eksik veri, bayraklar, sıfır tutar sayısı', () {
      final p = FeePreview.fromJson(<String, dynamic>{
        'period': '2026-10',
        'definition_id': 7,
        'total_minor': 150000,
        'apartment_count': 2,
        'lines': <Map<String, dynamic>>[
          <String, dynamic>{
            'apartment_id': 301,
            'label': 'A Blok - 5',
            'block_name': 'A Blok',
            'payer_party': 'owner',
            'amount_minor': 100000,
          },
          <String, dynamic>{
            'apartment_id': 302,
            'label': 'A Blok - 6',
            'block_name': 'A Blok',
            'payer_party': 'tenant',
            'amount_minor': 50000,
          },
        ],
        'missing_data': <Map<String, dynamic>>[
          <String, dynamic>{
            'apartment_id': 303,
            'label': 'B Blok - 2',
            'reason': 'Arsa payı tanımsız',
            'reason_code': 'land_share_missing',
          },
        ],
        'zero_amount_count': 1,
        'already_posted': false,
        'closed': true,
      });
      expect(p.period, const FinancePeriod(2026, 10));
      expect(p.totalMinor, 150000);
      expect(p.apartmentCount, 2);
      expect(p.lines.map((l) => l.amountMinor), <int>[100000, 50000]);
      expect(p.lines.first.payerParty, ResponsibleParty.owner);
      expect(p.hasMissingData, isTrue);
      expect(p.missingData.single.reasonCode, 'land_share_missing');
      expect(p.zeroAmountCount, 1);
      expect(p.alreadyPosted, isFalse);
      expect(p.closed, isTrue);
    });

    test('toplam okunamazsa FormatException (uydurma 0 YOK)', () {
      expect(
        () => FeePreview.fromJson(<String, dynamic>{'apartment_count': 0, 'lines': <dynamic>[]}),
        throwsFormatException,
      );
      expect(
        () => FeePreview.fromJson(<String, dynamic>{
          'total_minor': 100,
          'lines': <Map<String, dynamic>>[
            <String, dynamic>{'apartment_id': 1, 'amount_minor': 'x'},
          ],
        }),
        throwsFormatException,
      );
    });

    test('eksik veri nedeni: kod önce, sonra anahtar sözcük; teknik kod ham gösterilmez', () {
      expect(financeMissingReason('', code: 'land_share_missing'), 'Arsa payı tanımlı değil.');
      expect(financeMissingReason('', code: 'area_missing'), 'Metrekare bilgisi tanımlı değil.');
      expect(financeMissingReason('', code: 'category_missing'), 'Kategori tanımlı değil.');
      expect(financeMissingReason('', code: 'category_amount_missing'), 'Kategorisi için tutar belirlenmemiş.');
      expect(financeMissingReason('Arsa payı tanımsız'), 'Arsa payı tanımlı değil.');
      expect(financeMissingReason('Alan (m²) tanımsız'), 'Metrekare bilgisi tanımlı değil.');
      expect(financeMissingReason('Kategori tanımsız'), 'Kategori tanımlı değil.');
      expect(financeMissingReason('weird_internal_code'), 'Gerekli daire bilgisi eksik.');
      expect(financeMissingReason(''), 'Gerekli daire bilgisi eksik.');
      expect(financeMissingReason('Bilgi eksik'), 'Bilgi eksik');
    });

    test('FeePostResult: run özeti ve entries_count', () {
      final r = FeePostResult.fromJson(<String, dynamic>{
        'run': <String, dynamic>{'id': 9, 'total_minor': '150000', 'apartment_count': 2},
        'entries_count': 2,
      });
      expect(r.runId, 9);
      expect(r.totalMinor, 150000);
      expect(r.apartmentCount, 2);
      expect(r.entriesCount, 2);
    });
  });

  group('LedgerEntry', () {
    test('alanlar ve tarihler (DATE takvim günü, zaman damgası UTC)', () {
      final e = LedgerEntry.fromJson(_entry());
      expect(e.kind, LedgerKind.charge);
      expect(e.amountMinor, 50000);
      expect(e.period, const FinancePeriod(2026, 10));
      expect(e.entryDate, DateTime(2026, 10, 1));
      expect(e.dueDate, DateTime(2026, 10, 15));
      expect(e.payerParty, ResponsibleParty.owner);
      expect(e.createdAt, DateTime.utc(2026, 10, 1, 9));
      expect(e.definitionName, 'Aylık aidat');
    });

    test('iptal / düzeltme yetkisi: ters kayıt ve iptal edilmiş kayıt iptal edilemez; yalnız tahsilat düzeltilir', () {
      final charge = LedgerEntry.fromJson(_entry());
      final payment = LedgerEntry.fromJson(_entry(kind: 'payment', amount: -50000));
      final reversal = LedgerEntry.fromJson(
        _entry(kind: 'reversal', amount: -50000, extra: <String, dynamic>{'reverses_entry_id': 1}),
      );
      final reversed = LedgerEntry.fromJson(
        _entry(extra: <String, dynamic>{'reversed_by_entry_id': 5}),
      );
      expect(charge.canReverse, isTrue);
      expect(charge.canCorrect, isFalse, reason: 'borç düzeltilmez, iptal edilir');
      expect(payment.canReverse, isTrue);
      expect(payment.canCorrect, isTrue);
      expect(reversal.isReversal, isTrue);
      expect(reversal.canReverse, isFalse);
      expect(reversed.isReversed, isTrue);
      expect(reversed.canReverse, isFalse);
      expect(reversed.canCorrect, isFalse);
      expect(LedgerEntry.fromJson(_entry(kind: 'zzz')).canReverse, isFalse);
    });

    test('tutar okunamazsa FormatException (sessiz 0 YOK)', () {
      expect(() => LedgerEntry.fromJson(_entry(amount: null)), throwsFormatException);
      expect(() => LedgerEntry.fromJson(_entry(amount: 'iki yüz')), throwsFormatException);
      expect(() => LedgerEntry.fromJson(_entry(amount: 12.5)), throwsFormatException);
    });

    test('LedgerWriteResult: entry zorunlu; düzeltmede reversal da gelir; bakiye yoksa null', () {
      final r = LedgerWriteResult.fromJson(<String, dynamic>{
        'reversal': _entry(id: 8, kind: 'reversal', amount: 50000),
        'entry': _entry(id: 9, kind: 'payment', amount: -40000),
        'balance_minor': -30000,
      });
      expect(r.entry.id, 9);
      expect(r.reversal!.id, 8);
      expect(r.balanceMinor, -30000);
      expect(LedgerWriteResult.fromJson(<String, dynamic>{'entry': _entry()}).balanceMinor, isNull);
      expect(() => LedgerWriteResult.fromJson(<String, dynamic>{'balance_minor': 1}), throwsFormatException);
    });
  });

  group('hesaplar', () {
    test('BalanceRow: bakiye zorunlu (0 uydurulmaz); vadesi geçen yoksa null', () {
      final row = BalanceRow.fromJson(<String, dynamic>{
        'apartment_id': 301,
        'label': 'A Blok - 5',
        'block_name': 'A Blok',
        'balance_minor': 100000,
        'overdue_minor': 50000,
        'owner_name': 'Ayşe Yılmaz',
        'tenant_name': null,
      });
      expect(row.balanceMinor, 100000);
      expect(row.overdueMinor, 50000);
      expect(row.ownerName, 'Ayşe Yılmaz');
      expect(row.tenantName, isNull);
      expect(
        BalanceRow.fromJson(<String, dynamic>{'apartment_id': 1, 'balance_minor': -5}).overdueMinor,
        isNull,
      );
      expect(() => BalanceRow.fromJson(<String, dynamic>{'apartment_id': 1}), throwsFormatException);
      expect(
        () => BalanceRow.fromJson(<String, dynamic>{'apartment_id': 1, 'balance_minor': null}),
        throwsFormatException,
      );
    });

    test('BalancePage: toplamlar ve total', () {
      final page = BalancePage.fromJson(<String, dynamic>{
        'items': <Map<String, dynamic>>[
          <String, dynamic>{'apartment_id': 1, 'balance_minor': 5},
        ],
        'total': 12,
        'totals': <String, dynamic>{'debt_minor': 700, 'credit_minor': 200},
      });
      expect(page.items.length, 1);
      expect(page.total, 12);
      expect(page.debtTotalMinor, 700);
      expect(page.creditTotalMinor, 200);
      expect(BalancePage.fromJson(<String, dynamic>{}).items, isEmpty);
    });

    test('AccountView: daire, bakiye, hareketler ve imleç', () {
      final view = AccountView.fromJson(<String, dynamic>{
        'apartment': <String, dynamic>{
          'id': 301,
          'label': 'A Blok - 5',
          'block_name': 'A Blok',
          'responsible_party': 'tenant',
        },
        'balance_minor': -2500,
        'overdue_minor': 0,
        'items': <Map<String, dynamic>>[_entry()],
        'next_before_id': 77,
      });
      expect(view.apartment.responsibleParty, ResponsibleParty.tenant);
      expect(view.balanceMinor, -2500);
      expect(view.overdueMinor, 0);
      expect(view.items.length, 1);
      expect(view.nextBeforeId, 77);
      expect(() => AccountView.fromJson(<String, dynamic>{'items': <dynamic>[]}), throwsFormatException);
    });

    test('FinancePeriods: kapalı aylar yeniden eskiye sıralanır', () {
      final p = FinancePeriods.fromJson(<String, dynamic>{
        'closed_through': '2026-09',
        'items': <Map<String, dynamic>>[
          <String, dynamic>{'period': '2026-08', 'closed_at': '2026-09-01T08:00:00Z', 'closed_by_name': 'Ali'},
          <String, dynamic>{'period': '2026-09', 'closed_at': '2026-10-01T08:00:00Z', 'closed_by_name': null},
          <String, dynamic>{'period': 'bozuk'},
        ],
        'open_period': '2026-10',
      });
      expect(p.closedThrough, const FinancePeriod(2026, 9));
      expect(p.openPeriod, const FinancePeriod(2026, 10));
      expect(p.items.map((i) => i.period.toApi()), <String>['2026-09', '2026-08']);
      expect(p.items.last.closedByName, 'Ali');
      expect(FinancePeriods.fromJson(<String, dynamic>{}).items, isEmpty);
    });

    test('FinanceSummary: zorunlu toplamlar; net dönem tutarları işaretini korur', () {
      final s = FinanceSummary.fromJson(<String, dynamic>{
        'currency': 'TRY',
        'open_period': '2026-10',
        'balance_total_minor': 150000,
        'debt_total_minor': 250000,
        'credit_total_minor': 100000,
        'debtor_count': 3,
        'this_period': <String, dynamic>{'charged_minor': 400000, 'collected_minor': -5000},
      });
      expect(s.balanceTotalMinor, 150000);
      expect(s.debtTotalMinor, 250000);
      expect(s.creditTotalMinor, 100000);
      expect(s.debtorCount, 3);
      expect(s.chargedMinor, 400000);
      expect(s.collectedMinor, -5000);
      expect(s.openPeriod, const FinancePeriod(2026, 10));
      expect(
        () => FinanceSummary.fromJson(<String, dynamic>{'balance_total_minor': 1, 'debt_total_minor': 1}),
        throwsFormatException,
      );
    });

    test('MyFinance: kendi daireleri; yönetici notu / ad yok (null); vade alanları', () {
      final m = MyFinance.fromJson(<String, dynamic>{
        'items': <Map<String, dynamic>>[
          <String, dynamic>{
            'site_code': 11,
            'site_name': 'Gül Sitesi',
            'apartment_id': 301,
            'label': 'A Blok - 5',
            'block_name': 'A Blok',
            'currency': 'TRY',
            'balance_minor': 100000,
            'overdue_minor': 50000,
            'next_due_date': '2026-10-25',
            'next_due_minor': 50000,
            'payer_party': 'owner',
            'recent': <Map<String, dynamic>>[
              _entry(extra: <String, dynamic>{'description': null, 'created_by_name': null}),
            ],
          },
        ],
      });
      final item = m.items.single;
      expect(item.balanceMinor, 100000);
      expect(item.nextDueDate, DateTime(2026, 10, 25));
      expect(item.nextDueMinor, 50000);
      expect(item.payerParty, ResponsibleParty.owner);
      expect(item.recent.single.createdByName, isNull);
      expect(item.recent.single.description, isNull);
      expect(MyFinance.fromJson(<String, dynamic>{}).items, isEmpty);
      expect(
        () => MyFinance.fromJson(<String, dynamic>{
          'items': <Map<String, dynamic>>[
            <String, dynamic>{'apartment_id': 1},
          ],
        }),
        throwsFormatException,
        reason: 'bakiye okunamazsa "borç yok" uydurulmaz',
      );
    });
  });

  group('denetim kaydı etiketleri (finance.*)', () {
    const actions = <String, String>{
      'finance.definition.created': 'Aidat tanımı eklendi',
      'finance.definition.updated': 'Aidat tanımı güncellendi',
      'finance.definition.deactivated': 'Aidat tanımı pasifleştirildi',
      'finance.run.posted': 'Aidat borçlandırıldı',
      'finance.charge.posted': 'Ek borç yazıldı',
      'finance.payment.recorded': 'Tahsilat kaydedildi',
      'finance.entry.reversed': 'Mali kayıt iptal edildi',
      'finance.entry.corrected': 'Tahsilat düzeltildi',
      'finance.period.closed': 'Mali dönem kapatıldı',
      'finance.period.reopened': 'Mali dönem yeniden açıldı',
    };

    test('her eylemin Türkçe etiketi vardır ve kayıt etiketiyle süzgeç etiketi aynıdır', () {
      for (final entry in actions.entries) {
        expect(financeActionLabel(entry.key), entry.value, reason: entry.key);
        expect(
          AuditLogEntry.fromJson(<String, dynamic>{'id': 1, 'action': entry.key}).actionLabel,
          entry.value,
          reason: entry.key,
        );
        final filters = AuditLogView.actionFilters.where((f) => f.$1 == entry.key).toList();
        expect(filters, hasLength(1), reason: 'süzgeç: ${entry.key}');
        expect(filters.single.$2, entry.value);
      }
      expect(financeActionLabel('finance.xyz'), isNull);
      expect(
        AuditLogEntry.fromJson(<String, dynamic>{'id': 2, 'action': 'finance.xyz'}).actionLabel,
        'Diğer işlem',
      );
      final values = AuditLogView.actionFilters.map((f) => f.$1).toList();
      expect(values.toSet().length, values.length, reason: 'süzgeç değerleri tekrarlanmaz');
    });

    test('hedef etiketi numara ya da dönemdir; açıklama / kişi adı gösterilmez', () {
      String? label(String action, String? id) => AuditLogEntry.fromJson(<String, dynamic>{
        'id': 1,
        'action': action,
        'target_type': 'finance',
        'target_id': id,
        'details': <String, dynamic>{'note': 'gizli not', 'name': 'Ayşe'},
      }).targetLabel;
      expect(label('finance.definition.created', '7'), 'Aidat tanımı #7');
      expect(label('finance.run.posted', '9'), 'Borçlandırma #9');
      expect(label('finance.charge.posted', '9'), 'Ek borç #9');
      expect(label('finance.payment.recorded', '12'), 'Tahsilat #12');
      expect(label('finance.entry.reversed', '12'), 'Mali kayıt #12');
      expect(label('finance.entry.corrected', '12'), 'Mali kayıt #12');
      expect(label('finance.period.closed', '2026-10'), 'Dönem: Ekim 2026');
      expect(label('finance.period.reopened', '2026-10-01'), 'Dönem: Ekim 2026');
      expect(label('finance.payment.recorded', null), isNull);
      expect(label('finance.payment.recorded', ''), isNull);
    });

    test('kart tonları: ekleme success, iptal / kapatma warning, düzeltme / güncelleme / açma info', () {
      for (final a in <String>[
        'finance.definition.created',
        'finance.run.posted',
        'finance.charge.posted',
        'finance.payment.recorded',
      ]) {
        expect(auditToneOf(a), AppTone.success, reason: a);
      }
      for (final a in <String>[
        'finance.definition.deactivated',
        'finance.entry.reversed',
        'finance.period.closed',
      ]) {
        expect(auditToneOf(a), AppTone.warning, reason: a);
      }
      for (final a in <String>[
        'finance.definition.updated',
        'finance.entry.corrected',
        'finance.period.reopened',
      ]) {
        expect(auditToneOf(a), AppTone.info, reason: a);
      }
    });
  });
}
