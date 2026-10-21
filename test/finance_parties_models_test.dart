// İki hesap (İP-1A, karar G12): modellerdeki yeni alanlar ve ESKİ yanıt uyumu (sözleşme: docs/PLATFORM_FINANS.md "İki hesap
// (2026-10-21)"). Eski sunucu yeni alanları göndermez: ayrıştırma hata vermez, değerler null / boş olur ve ekran tek hesap gibi
// davranır. Para alanları kuruş tamsayıdır; bozuk zorunlu tutar sessiz 0 yapılmaz.
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/finance.dart';
import 'package:site_kapi_kontrol/models/late_fee_models.dart';
import 'package:site_kapi_kontrol/models/receipt_models.dart';
import 'package:site_kapi_kontrol/models/reminder_models.dart';
import 'package:site_kapi_kontrol/models/report_models.dart';

Map<String, dynamic> _entry({int id = 1, String kind = 'charge', int amount = 50000, Map<String, dynamic>? extra}) =>
    <String, dynamic>{
      'id': id,
      'kind': kind,
      'amount_minor': amount,
      'period': '2026-10',
      'entry_date': '2026-10-01',
      'payer_party': 'both',
      ...?extra,
    };

Map<String, dynamic> _buckets(int value) => <String, dynamic>{
  for (final b in AgingBucket.values) '${b.key}_minor': value,
};

void main() {
  group('hesap ve "kim öder" sayımları', () {
    test('AccountParty: owner / tenant (büyük-küçük harf ve boşluk duyarsız); bilinmeyen ya da eksik null', () {
      expect(AccountParty.tryParse('owner'), AccountParty.owner);
      expect(AccountParty.tryParse(' Tenant '), AccountParty.tenant);
      expect(AccountParty.tryParse('both'), isNull);
      expect(AccountParty.tryParse(null), isNull);
      expect(AccountParty.tryParse(3), isNull);
      expect(AccountParty.owner.label, 'Ev sahibi hesabı');
      expect(AccountParty.tenant.label, 'Kiracı hesabı');
    });

    test('ChargeParty: occupant / owner; türe göre varsayılan (aylık dairede oturan, tek seferlik ev sahibi)', () {
      expect(ChargeParty.tryParse('occupant'), ChargeParty.occupant);
      expect(ChargeParty.tryParse('owner'), ChargeParty.owner);
      expect(ChargeParty.tryParse('tenant'), isNull);
      expect(ChargeParty.defaultFor(FeeKind.recurring), ChargeParty.occupant);
      expect(ChargeParty.defaultFor(FeeKind.oneTime), ChargeParty.owner);
      expect(ChargeParty.occupant.label, 'Dairede oturan');
      expect(ChargeParty.owner.label, 'Ev sahibi');
      expect(ChargeParty.occupant.description, isNotEmpty);
    });
  });

  group('defter, tanım, önizleme', () {
    test('LedgerEntry: account_party ve source_kind okunur; eski satırda null', () {
      final entry = LedgerEntry.fromJson(_entry(kind: 'payment', amount: -1500, extra: <String, dynamic>{'account_party': 'tenant', 'source_kind': 'bank_line'}));
      expect(entry.accountParty, AccountParty.tenant);
      expect(entry.sourceKind, 'bank_line');
      final old = LedgerEntry.fromJson(_entry());
      expect(old.accountParty, isNull);
      expect(old.sourceKind, isNull);
    });

    test('FeeDefinition: charge_party; yoksa etkin değer türe göre varsayılan', () {
      final withParty = FeeDefinition.fromJson(<String, dynamic>{'id': 1, 'kind': 'recurring', 'distribution': 'fixed', 'charge_party': 'owner'});
      expect(withParty.chargeParty, ChargeParty.owner);
      expect(withParty.effectiveChargeParty, ChargeParty.owner);
      final oldRecurring = FeeDefinition.fromJson(<String, dynamic>{'id': 2, 'kind': 'recurring', 'distribution': 'fixed'});
      expect(oldRecurring.chargeParty, isNull);
      expect(oldRecurring.effectiveChargeParty, ChargeParty.occupant);
      final oldOneTime = FeeDefinition.fromJson(<String, dynamic>{'id': 3, 'kind': 'one_time', 'distribution': 'equal'});
      expect(oldOneTime.effectiveChargeParty, ChargeParty.owner);
    });

    test('tanım ve ek borç gövdesi: charge_party yalnız seçildiyse gider (seçilmezse sunucu varsayılanı)', () {
      const target = FeeTarget();
      final def = FeeDefinitionInput(
        name: 'Aidat',
        kind: FeeKind.recurring,
        distribution: FeeDistribution.fixed,
        amountMinor: 100000,
        dueDay: 1,
        startPeriod: const FinancePeriod(2026, 10),
        target: target,
        chargeParty: ChargeParty.owner,
      ).toJson();
      expect(def['charge_party'], 'owner');
      final defDefault = FeeDefinitionInput(
        name: 'Aidat',
        kind: FeeKind.recurring,
        distribution: FeeDistribution.fixed,
        amountMinor: 100000,
        dueDay: 1,
        startPeriod: const FinancePeriod(2026, 10),
      ).toJson();
      expect(defDefault.containsKey('charge_party'), isFalse);
      const charge = ExtraChargeInput(name: 'Asansör', distribution: FeeDistribution.equal, amountMinor: 5000, chargeParty: ChargeParty.occupant);
      expect(charge.toJson()['charge_party'], 'occupant');
      const chargeDefault = ExtraChargeInput(name: 'Asansör', distribution: FeeDistribution.equal, amountMinor: 5000);
      expect(chargeDefault.toJson().containsKey('charge_party'), isFalse);
    });

    test('önizleme satırı: account_party; eski sunucuda null', () {
      final line = FeePreviewLine.fromJson(<String, dynamic>{'apartment_id': 7, 'amount_minor': 100, 'payer_party': 'both', 'account_party': 'tenant'});
      expect(line.accountParty, AccountParty.tenant);
      expect(FeePreviewLine.fromJson(<String, dynamic>{'apartment_id': 7, 'amount_minor': 100}).accountParty, isNull);
    });

    test('tahsilat yanıtı: account_balance_minor (hesap bakiyesi) + eski balance_minor (daire toplamı)', () {
      final result = LedgerWriteResult.fromJson(<String, dynamic>{
        'entry': _entry(kind: 'payment', amount: -50000, extra: <String, dynamic>{'account_party': 'tenant'}),
        'balance_minor': 183000,
        'account_balance_minor': 168000,
      });
      expect(result.balanceMinor, 183000);
      expect(result.accountBalanceMinor, 168000);
      expect(result.entry.accountParty, AccountParty.tenant);
      final old = LedgerWriteResult.fromJson(<String, dynamic>{'entry': _entry(kind: 'payment', amount: -1), 'balance_minor': 5});
      expect(old.accountBalanceMinor, isNull);
    });
  });

  group('yönetici: bakiye satırı ve hesap ekstresi', () {
    test('bakiye satırı: borç / alacak ayrı ve hesap kırılımı; eski sunucuda null', () {
      final row = BalanceRow.fromJson(<String, dynamic>{
        'apartment_id': 7,
        'label': 'Daire 1',
        'balance_minor': 158000,
        'overdue_minor': 156000,
        'debt_minor': 168000,
        'credit_minor': 10000,
        'accounts': <String, dynamic>{
          'owner': <String, dynamic>{'balance_minor': -10000, 'overdue_minor': 0},
          'tenant': <String, dynamic>{'balance_minor': 168000, 'overdue_minor': 156000},
        },
      });
      expect(row.debtMinor, 168000);
      expect(row.creditMinor, 10000);
      expect(row.ownerAccount!.balanceMinor, -10000);
      expect(row.tenantAccount!.overdueMinor, 156000);
      expect(row.hasTenantBalance, isTrue);
      final old = BalanceRow.fromJson(<String, dynamic>{'apartment_id': 7, 'balance_minor': 5});
      expect(old.debtMinor, isNull);
      expect(old.ownerAccount, isNull);
      expect(old.hasTenantBalance, isFalse);
    });

    test('hesap ekstresi: hesap süzgeci, iki hesap toplamı, kiracı sekmesi bayrağı, varsayılan tahsilat hesabı', () {
      final view = AccountView.fromJson(<String, dynamic>{
        'apartment': <String, dynamic>{'id': 7, 'label': 'Daire 1', 'responsible_party': 'both'},
        'balance_minor': 168000,
        'overdue_minor': 156000,
        'items': <Map<String, dynamic>>[_entry(extra: <String, dynamic>{'account_party': 'tenant'})],
        'account_party': 'tenant',
        'accounts': <String, dynamic>{
          'owner': <String, dynamic>{'balance_minor': -10000, 'overdue_minor': 0, 'entry_count': 5},
          'tenant': <String, dynamic>{'balance_minor': 168000, 'overdue_minor': 156000, 'entry_count': 6},
        },
        'show_tenant_account': true,
        'has_current_tenant': true,
        'default_payment_account': 'tenant',
      });
      expect(view.accountParty, AccountParty.tenant);
      expect(view.hasTwoAccounts, isTrue);
      expect(view.accountOf(AccountParty.owner)!.entryCount, 5);
      expect(view.accountOf(AccountParty.tenant)!.balanceMinor, 168000);
      expect(view.hasCurrentTenant, isTrue);
      expect(view.defaultPaymentAccount, AccountParty.tenant);
      expect(view.items.single.accountParty, AccountParty.tenant);
    });

    test('eski sunucu ekstresi (yeni alanlar yok): tek hesap gibi; kiracı sekmesi yok', () {
      final view = AccountView.fromJson(<String, dynamic>{
        'apartment': <String, dynamic>{'id': 7, 'label': 'Daire 1'},
        'balance_minor': 1000,
        'items': <Map<String, dynamic>>[],
      });
      expect(view.hasTwoAccounts, isFalse);
      expect(view.showTenantAccount, isFalse);
      expect(view.accountParty, isNull);
      expect(view.defaultPaymentAccount, isNull);
    });

    test('kiracı sekmesi bayrağı varken hesap toplamı eksikse iki sekme açılmaz (güvenli taraf)', () {
      final view = AccountView.fromJson(<String, dynamic>{
        'apartment': <String, dynamic>{'id': 7},
        'balance_minor': 1000,
        'show_tenant_account': true,
      });
      expect(view.hasTwoAccounts, isFalse);
    });
  });

  group('sakin: Borcum görünümleri', () {
    Map<String, dynamic> view(String party, String role, int balance) => <String, dynamic>{
      'account_party': party,
      'role': role,
      'balance_minor': balance,
      'overdue_minor': balance > 0 ? balance : 0,
      'next_due_date': null,
      'next_due_minor': null,
      'visible_from': null,
      'offset_note': false,
      'recent': <Map<String, dynamic>>[_entry(amount: balance > 0 ? balance : 1, extra: <String, dynamic>{'account_party': party})],
    };

    test('eski alanlar = KENDİ hesabı; salt okunur kiracı hesabı ayrı; kendi hesabı sayılan tutar salt okunuru içermez', () {
      final item = MyFinanceApartment.fromJson(<String, dynamic>{
        'site_code': 11,
        'apartment_id': 7,
        'balance_minor': 0,
        'overdue_minor': 0,
        'recent': <Map<String, dynamic>>[],
        'account_party': 'owner',
        'accounts': <Map<String, dynamic>>[view('owner', 'own', 0), view('tenant', 'read_only', 168000)],
      });
      expect(item.accountParty, AccountParty.owner);
      expect(item.ownAccount.accountParty, AccountParty.owner);
      expect(item.ownAccount.balanceMinor, 0);
      expect(item.ownAccount.isReadOnly, isFalse);
      expect(item.readOnlyAccounts, hasLength(1));
      expect(item.readOnlyAccounts.single.accountParty, AccountParty.tenant);
      expect(item.readOnlyAccounts.single.balanceMinor, 168000);
      expect(item.readOnlyAccounts.single.recent.single.accountParty, AccountParty.tenant);
    });

    test('eski sunucu yanıtı: görünüm listesi boş, kendi hesabı eski alanlardan, hesap bilgisi yok', () {
      final item = MyFinanceApartment.fromJson(<String, dynamic>{'site_code': 11, 'apartment_id': 7, 'balance_minor': 25000, 'overdue_minor': 5000});
      expect(item.accounts, isEmpty);
      expect(item.readOnlyAccounts, isEmpty);
      expect(item.ownAccount.balanceMinor, 25000);
      expect(item.ownAccount.overdueMinor, 5000);
      expect(item.ownAccount.accountParty, isNull);
    });

    test('görünümde bozuk tutar sessiz 0 yapılmaz (FormatException)', () {
      expect(
        () => MyFinanceApartment.fromJson(<String, dynamic>{
          'site_code': 11,
          'apartment_id': 7,
          'balance_minor': 0,
          'accounts': <Map<String, dynamic>>[<String, dynamic>{'account_party': 'owner', 'role': 'own', 'balance_minor': 'abc'}],
        }),
        throwsFormatException,
      );
    });
  });

  group('Faz 4b modelleri', () {
    test('yaşlandırma: hesap süzgeci ve hesap kırılımı (ev sahibi alacağı kiracı borcuna mahsup edilmez)', () {
      final report = AgingReport.fromJson(<String, dynamic>{
        'as_of': '2026-10-21',
        'account_party': 'tenant',
        'totals': <String, dynamic>{..._buckets(0), 'credit_minor': 0, 'total_overdue_minor': 156000},
        'items': <Map<String, dynamic>>[
          <String, dynamic>{
            'apartment_id': 7,
            'label': 'Daire 1',
            ..._buckets(0),
            'credit_minor': 10000,
            'total_overdue_minor': 156000,
            'account_party': null,
            'accounts': <String, dynamic>{
              'owner': <String, dynamic>{..._buckets(0), 'credit_minor': 10000, 'total_overdue_minor': 0},
              'tenant': <String, dynamic>{..._buckets(0), 'credit_minor': 0, 'total_overdue_minor': 156000},
            },
          },
        ],
        'total': 1,
      });
      expect(report.accountParty, AccountParty.tenant);
      final item = report.items.single;
      expect(item.accountParty, isNull);
      expect(item.accounts[AccountParty.owner]!.creditMinor, 10000);
      expect(item.accounts[AccountParty.tenant]!.totalOverdueMinor, 156000);
      expect(item.accounts[AccountParty.owner]!.isZero, isFalse);
    });

    test('yaşlandırma satırı eski sunucu: hesap kırılımı boş', () {
      final item = AgingItem.fromJson(<String, dynamic>{'apartment_id': 7, ..._buckets(0), 'credit_minor': 0, 'total_overdue_minor': 0});
      expect(item.accounts, isEmpty);
      expect(item.accountParty, isNull);
    });

    test('ekstre: hesap ve salt okunur rolü (sakin); eski sunucuda null / false', () {
      Map<String, dynamic> statement(Map<String, dynamic> extra) => <String, dynamic>{
        'apartment': <String, dynamic>{'id': 7, 'label': 'Daire 1'},
        'opening_balance_minor': 0,
        'closing_balance_minor': 168000,
        'totals': <String, dynamic>{'charged_minor': 0, 'paid_minor': 0, 'reversed_minor': 0},
        'items': <Map<String, dynamic>>[],
        ...extra,
      };
      final readOnly = ApartmentStatement.fromJson(statement(<String, dynamic>{'account_party': 'tenant', 'role': 'read_only'}));
      expect(readOnly.accountParty, AccountParty.tenant);
      expect(readOnly.readOnly, isTrue);
      final own = ApartmentStatement.fromJson(statement(<String, dynamic>{'account_party': 'owner', 'role': 'own'}));
      expect(own.readOnly, isFalse);
      final old = ApartmentStatement.fromJson(statement(const <String, dynamic>{}));
      expect(old.accountParty, isNull);
      expect(old.readOnly, isFalse);
    });

    test('makbuz özeti, tazminat satırı ve hatırlatma önizlemesi: hesap alanları', () {
      final receipt = ReceiptSummary.fromJson(<String, dynamic>{'id': 1, 'number': 'MK-2026-000001', 'amount_minor': 100, 'account_party': 'tenant'});
      expect(receipt.accountParty, AccountParty.tenant);
      expect(ReceiptSummary.fromJson(<String, dynamic>{'id': 1, 'number': 'MK-2026-000001', 'amount_minor': 100}).accountParty, isNull);
      final line = LateFeeLine.fromJson(<String, dynamic>{'apartment_id': 7, 'amount_minor': 500, 'account_party': 'owner'});
      expect(line.accountParty, AccountParty.owner);
      final preview = ReminderPreview.fromJson(<String, dynamic>{'apartment_count': 3, 'person_count': 4, 'account_count': 4});
      expect(preview.accountCount, 4);
      expect(ReminderPreview.fromJson(<String, dynamic>{'apartment_count': 3, 'person_count': 4}).accountCount, isNull);
    });

    test('ikinci inceleme: hatırlatma önizlemesinde elden takip öğeleri hesabıyla; eski sunucuda yalnız daire etiketleri', () {
      final preview = ReminderPreview.fromJson(<String, dynamic>{
        'apartment_count': 1,
        'person_count': 0,
        'account_count': 0,
        'hand_follow_up_count': 2,
        'hand_follow_up_apartments': <String>['A Blok - 5', 'A Blok - 5'],
        'hand_follow_up_accounts': <Object?>[
          <String, dynamic>{'label': 'A Blok - 5', 'account_party': 'owner'},
          <String, dynamic>{'label': 'A Blok - 5', 'account_party': 'tenant'},
          <String, dynamic>{'label': ' ', 'account_party': 'tenant'},
          'bozuk',
        ],
      });
      expect(preview.countsAccounts, isTrue);
      expect(preview.handFollowUpAccounts.map((i) => i.accountParty), <AccountParty?>[AccountParty.owner, AccountParty.tenant]);
      expect(preview.handFollowUpLabels, <String>['A Blok - 5 (Ev sahibi hesabı)', 'A Blok - 5 (Kiracı hesabı)']);
      final old = ReminderPreview.fromJson(<String, dynamic>{
        'apartment_count': 1,
        'person_count': 0,
        'hand_follow_up_count': 1,
        'hand_follow_up_apartments': <String>['A Blok - 5'],
      });
      expect(old.countsAccounts, isFalse);
      expect(old.handFollowUpAccounts, isEmpty);
      expect(old.handFollowUpLabels, <String>['A Blok - 5']);
      expect(const ReminderFollowUpItem(label: 'B Blok - 2').displayText, 'B Blok - 2', reason: 'hesabı bilinmeyen öğe yalnız etiket');
    });
  });
}
