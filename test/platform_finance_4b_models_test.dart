// Platform Faz 4b (Finans devamı): model ayrıştırma testleri (docs/PLATFORM_FINANS_4B.md).
//
// Kurallar: tutarlar KURUŞ tamsayı; zorunlu tutar okunamazsa FormatException (sessiz 0 YOK); bilinmeyen sayım
// değerleri güvenli varsayılana düşer; sunucu alanları eksikse (eski sunucu) modeller çökmez.
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/audit_log.dart';
import 'package:site_kapi_kontrol/models/cash_models.dart';
import 'package:site_kapi_kontrol/models/expense_models.dart';
import 'package:site_kapi_kontrol/models/finance.dart';
import 'package:site_kapi_kontrol/models/finance_4b.dart';
import 'package:site_kapi_kontrol/models/late_fee_models.dart';
import 'package:site_kapi_kontrol/models/receipt_models.dart';
import 'package:site_kapi_kontrol/models/reminder_models.dart';
import 'package:site_kapi_kontrol/models/report_models.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart' show AppTone;
import 'package:site_kapi_kontrol/ui/views/audit_log_view.dart' show AuditLogView;
import 'package:site_kapi_kontrol/ui/widgets/audit_log_card.dart' show auditToneOf;

Map<String, dynamic> _entry({Object? receipt, Object? lateFee, int? lateFeeRunId, String? definitionName, String kind = 'payment'}) =>
    <String, dynamic>{
      'id': 5,
      'kind': kind,
      'amount_minor': -50000,
      'period': '2026-10',
      'entry_date': '2026-10-05',
      'receipt': ?receipt,
      'late_fee': ?lateFee,
      'late_fee_run_id': ?lateFeeRunId,
      'definition_name': ?definitionName,
    };

Map<String, dynamic> _bucketMap(int base) => <String, dynamic>{
  'not_due_minor': base,
  'd0_30_minor': base + 1,
  'd31_60_minor': base + 2,
  'd61_90_minor': base + 3,
  'd91_180_minor': base + 4,
  'd181_365_minor': base + 5,
  'd366_plus_minor': base + 6,
};

void main() {
  group('LedgerEntry / LedgerWriteResult: makbuz ve tazminat işaretleri', () {
    test('makbuz özeti ayrıştırılır; numara year/no alanlarından da kurulur', () {
      final withNumber = LedgerEntry.fromJson(_entry(receipt: <String, dynamic>{'id': 9, 'number': 'MK-2026-000123', 'status': 'active'}));
      expect(withNumber.receipt!.number, 'MK-2026-000123');
      expect(withNumber.receipt!.isCancelled, isFalse);
      final composed = LedgerEntry.fromJson(_entry(receipt: <String, dynamic>{'id': 9, 'receipt_year': 2026, 'receipt_no': 7, 'status': 'cancelled'}));
      expect(composed.receipt!.number, 'MK-2026-000007');
      expect(composed.receipt!.isCancelled, isTrue);
    });

    test('makbuz yok / bozuksa null (uydurma numara yazılmaz)', () {
      expect(LedgerEntry.fromJson(_entry()).receipt, isNull);
      expect(LedgerEntry.fromJson(_entry(receipt: 'MK-1')).receipt, isNull);
      expect(LedgerEntry.fromJson(_entry(receipt: <String, dynamic>{'id': 3})).receipt, isNull, reason: 'numarasız');
      expect(LedgerEntry.fromJson(_entry(receipt: <String, dynamic>{'number': 'MK-2026-000001'})).receipt, isNull, reason: 'kimliksiz');
    });

    test('R13 P2-1: tazminat kalemi = kind charge + late_fee_run_id; ters kayıt ve elle açılmış aynı adlı borç tazminat DEĞİLDİR', () {
      expect(LedgerEntry.fromJson(_entry(kind: 'charge', lateFeeRunId: 4)).isLateFee, isTrue);
      expect(LedgerEntry.fromJson(_entry(kind: 'charge', lateFeeRunId: 4)).lateFeeRunId, 4);
      expect(LedgerEntry.fromJson(_entry(kind: 'charge', lateFee: true)).isLateFee, isTrue, reason: 'açık bayrak');
      expect(LedgerEntry.fromJson(_entry(kind: 'charge', lateFee: <String, dynamic>{'rate_bp': 500})).isLateFee, isTrue);
      // Sunucu tazminat kaleminin TERS kaydına da late_fee_run_id kopyalar: ters kayıt tazminat satırı sayılmaz.
      expect(LedgerEntry.fromJson(_entry(kind: 'reversal', lateFeeRunId: 4, definitionName: 'Gecikme tazminatı')).isLateFee, isFalse);
      expect(LedgerEntry.fromJson(_entry(kind: 'payment', lateFeeRunId: 4)).isLateFee, isFalse);
      // 4a'da elle açılmış "Gecikme tazminatı" adlı ek borç sunucu tazminatı değildir (açıklaması 404 verirdi).
      expect(LedgerEntry.fromJson(_entry(kind: 'charge', definitionName: 'Gecikme tazminatı')).isLateFee, isFalse);
      expect(LedgerEntry.fromJson(_entry(kind: 'charge', definitionName: 'Aylık aidat')).isLateFee, isFalse);
      expect(LedgerEntry.fromJson(_entry(kind: 'charge', lateFee: false, lateFeeRunId: 4)).isLateFee, isFalse, reason: 'açık false baskın');
      expect(LedgerEntry.fromJson(_entry(kind: 'charge')).isLateFee, isFalse);
    });

    test('LedgerWriteResult: yanıttaki receipt ve movement_id okunur; yoksa null (eski sunucu)', () {
      final r = LedgerWriteResult.fromJson(<String, dynamic>{
        'entry': _entry(),
        'balance_minor': 100,
        'receipt': <String, dynamic>{'id': 3, 'number': 'MK-2026-000010'},
        'movement_id': 77,
      });
      expect(r.receipt!.id, 3);
      expect(r.movementId, 77);
      final old = LedgerWriteResult.fromJson(<String, dynamic>{'entry': _entry()});
      expect(old.receipt, isNull);
      expect(old.movementId, isNull);
    });

    test('formatReceiptNumber: yıl 4, sıra en az 6 hane', () {
      expect(formatReceiptNumber(2026, 123), 'MK-2026-000123');
      expect(formatReceiptNumber(2026, 1234567), 'MK-2026-1234567');
    });
  });

  group('FinanceSettings', () {
    Map<String, dynamic> settings({Object? legalTop, Object? legalLate}) => <String, dynamic>{
      'settings_version': 4,
      'legal_ok': ?legalTop,
      'receipts': <String, dynamic>{'auto_issue': true},
      'late_fee': <String, dynamic>{
        'enabled': true,
        'rate_bp': 300,
        'max_rate_bp': 500,
        'method': 'daily_actual',
        'grace_days': 5,
        'start_period': '2026-08-01',
        'next_period': '2026-09',
        'voidable_run_id': 12,
        'legal_ok': ?legalLate,
      },
      'reminders': <String, dynamic>{
        'enabled': false,
        'min_overdue_minor': 7500,
        'min_days_overdue': 10,
        'min_interval_days': 21,
        'max_consecutive': 2,
        'smtp_configured': false,
      },
    };

    test('tüm alanlar okunur', () {
      final s = FinanceSettings.fromJson(settings());
      expect(s.settingsVersion, 4);
      expect(s.receiptAutoIssue, isTrue);
      expect(s.lateFee.enabled, isTrue);
      expect(s.lateFee.rateBp, 300);
      expect(s.lateFee.method, LateFeeMethod.dailyActual);
      expect(s.lateFee.graceDays, 5);
      expect(s.lateFee.startPeriod, const FinancePeriod(2026, 8));
      expect(s.lateFee.nextPeriod, const FinancePeriod(2026, 9));
      expect(s.lateFee.voidableRunId, 12);
      expect(s.reminders.minOverdueMinor, 7500);
      expect(s.reminders.smtpConfigured, isFalse);
    });

    test('hukuk bayrağı (legal_ok): yoksa null=bilinmiyor (engellenmez); false ise kullanılamaz', () {
      expect(FinanceSettings.fromJson(settings()).lateFee.legalOk, isNull);
      expect(FinanceSettings.fromJson(settings()).lateFee.usable, isTrue);
      final blocked = FinanceSettings.fromJson(settings(legalTop: false));
      expect(blocked.lateFee.legalOk, isFalse);
      expect(blocked.lateFee.usable, isFalse, reason: 'site ayarı açık olsa da sistem bayrağı kapalı');
      expect(blocked.reminders.usable, isFalse);
      final perBlock = FinanceSettings.fromJson(settings(legalTop: true, legalLate: false));
      expect(perBlock.lateFee.legalOk, isFalse, reason: 'blok içi bayrak baskındır');
    });

    test('settings_version okunamazsa FormatException', () {
      expect(() => FinanceSettings.fromJson(<String, dynamic>{}), throwsFormatException);
    });

    test('FinanceSettingsPatch: yalnız verilen alanlar, expected_settings_version ZORUNLU', () {
      const empty = FinanceSettingsPatch();
      expect(empty.isEmpty, isTrue);
      expect(empty.toJson(3), <String, dynamic>{'expected_settings_version': 3});
      final patch = FinanceSettingsPatch(
        receiptAutoIssue: false,
        lateFeeEnabled: true,
        lateFeeRateBp: 450,
        lateFeeMethod: LateFeeMethod.daily30,
        lateFeeGraceDays: 0,
        lateFeeStartPeriod: const FinancePeriod(2026, 9),
        reminderMinOverdueMinor: 10000,
      );
      expect(patch.isEmpty, isFalse);
      final json = patch.toJson(7);
      expect(json['expected_settings_version'], 7);
      expect(json['receipts'], <String, dynamic>{'auto_issue': false});
      expect(json['late_fee'], <String, dynamic>{
        'enabled': true,
        'rate_bp': 450,
        'method': 'daily_30',
        'grace_days': 0,
        'start_period': '2026-09',
      });
      expect(json['reminders'], <String, dynamic>{'min_overdue_minor': 10000});
    });

    test('oran metni tamsayı aritmetiğiyle: 500 -> %5,00; 450 -> %4,50; yüzde bp', () {
      expect(formatRateBp(500), '%5,00');
      expect(formatRateBp(450), '%4,50');
      expect(formatRateBp(5), '%0,05');
      expect(formatPercentBp(8765), '%87,65');
      expect(formatPercentBp(-250), '-%2,50');
    });
  });

  group('Makbuz', () {
    Map<String, dynamic> snapshot() => <String, dynamic>{
      'v': 1,
      'number': 'MK-2026-000123',
      'kind': 'collection',
      'issued_on': '2026-10-16',
      'paid_on': '2026-10-14',
      'amount_minor': 123456,
      'currency': 'TRY',
      'method': 'cash',
      'site': <String, dynamic>{'name': 'Gül Sitesi'},
      'apartment': <String, dynamic>{'label': 'A Blok - 5'},
      'payer': <String, dynamic>{'party': 'owner', 'name': 'Ayşe Yılmaz'},
      'issuer': <String, dynamic>{'name': 'Site Yöneticisi'},
      'cancels_number': null,
      'cancelled_by_number': null,
      'mahsup': 'oldest_due_first',
      'cekince': true,
      'template_version': 1,
      'verification_code': 'AB12CD34EF56',
    };

    test('iç içe snapshot + üst alanlar (copy_count, ledger_entry_id) birleşir', () {
      final r = Receipt.fromJson(<String, dynamic>{
        'id': 9,
        'status': 'active',
        'copy_count': 2,
        'ledger_entry_id': 55,
        'snapshot': snapshot(),
      });
      expect(r.id, 9);
      expect(r.number, 'MK-2026-000123');
      expect(r.amountMinor, 123456);
      expect(r.method, PaymentMethod.cash);
      expect(r.siteName, 'Gül Sitesi');
      expect(r.apartmentLabel, 'A Blok - 5');
      expect(r.payerName, 'Ayşe Yılmaz');
      expect(r.payerParty, 'owner');
      expect(r.issuerName, 'Site Yöneticisi');
      expect(r.verificationCode, 'AB12CD34EF56');
      expect(r.copyCount, 2);
      expect(r.nextCopyNumber, 3);
      expect(r.ledgerEntryId, 55);
      expect(r.cekince, isTrue);
      expect(r.isCancelled, isFalse);
      expect(r.issuedOn, DateTime(2026, 10, 16));
      expect(r.paidOn, DateTime(2026, 10, 14));
    });

    test('düz biçim ve sakin yanıtı (copy_count / ledger_entry_id yok) çalışır', () {
      final r = Receipt.fromJson(<String, dynamic>{'id': 9, ...snapshot()});
      expect(r.copyCount, 0);
      expect(r.nextCopyNumber, 1, reason: '1 = ASIL');
      expect(r.ledgerEntryId, isNull);
    });

    test('iptal edilmiş makbuz ve iptal makbuzu', () {
      final cancelled = Receipt.fromJson(<String, dynamic>{
        'id': 9,
        'status': 'cancelled',
        ...snapshot(),
        'cancelled_by_number': 'MK-2026-000124',
      });
      expect(cancelled.isCancelled, isTrue);
      expect(cancelled.cancelledByNumber, 'MK-2026-000124');
      final cancellation = Receipt.fromJson(<String, dynamic>{
        'id': 10,
        ...snapshot(),
        'number': 'MK-2026-000124',
        'kind': 'cancellation',
        'cancels_number': 'MK-2026-000123',
        'cancel_reason_code': 'issued_in_error',
      });
      expect(cancellation.isCancellation, isTrue);
      expect(cancellation.cancelsNumber, 'MK-2026-000123');
      expect(receiptCancelReasonLabel(cancellation.cancelReasonCode), 'Makbuz hatalı düzenlendi');
      expect(receiptCancelReasonLabel('payment_reversed'), 'Ödeme iptal edildi');
      expect(receiptCancelReasonLabel('payment_corrected'), 'Ödeme düzeltildi');
      expect(receiptCancelReasonLabel('bilinmeyen_kod'), 'İptal edildi', reason: 'ham kod gösterilmez');
    });

    test('tutar ya da numara okunamazsa FormatException (sessiz 0 yok)', () {
      expect(() => Receipt.fromJson(<String, dynamic>{'id': 1, ...snapshot()}..remove('amount_minor')), throwsFormatException);
      expect(() => Receipt.fromJson(<String, dynamic>{'id': 1, ...snapshot()}..remove('number')), throwsFormatException);
      expect(() => Receipt.fromJson(<String, dynamic>{'id': 1, ...snapshot(), 'amount_minor': 12.5}), throwsFormatException);
    });

    test('ReceiptSummary / ReceiptPage', () {
      final page = ReceiptPage.fromJson(<String, dynamic>{
        'items': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 9,
            'number': 'MK-2026-000123',
            'kind': 'collection',
            'status': 'active',
            'paid_on': '2026-10-14',
            'issued_on': '2026-10-16',
            'amount_minor': 123456,
            'apartment': <String, dynamic>{'id': 301, 'label': 'A Blok - 5'},
            'payer_name': 'Ayşe Yılmaz',
          },
          <String, dynamic>{
            'id': 10,
            'number': 'MK-2026-000124',
            'kind': 'cancellation',
            'status': null,
            'amount_minor': 123456,
            'apartment': <String, dynamic>{'id': 301, 'label': 'A Blok - 5'},
          },
        ],
        'next_before_id': 9,
      });
      expect(page.items, hasLength(2));
      expect(page.items[0].isCancelled, isFalse);
      expect(page.items[1].isCancellation, isTrue);
      expect(page.items[1].status, isNull);
      expect(page.nextBeforeId, 9);
      expect(() => ReceiptSummary.fromJson(<String, dynamic>{'id': 1, 'number': 'MK-2026-000001'}), throwsFormatException);
    });

    test('doğrulama sonucu: valid zorunlu', () {
      expect(ReceiptVerifyResult.fromJson(<String, dynamic>{'valid': true, 'status': 'active'}).valid, isTrue);
      expect(ReceiptVerifyResult.fromJson(<String, dynamic>{'valid': false}).status, isNull);
      expect(() => ReceiptVerifyResult.fromJson(<String, dynamic>{}), throwsFormatException);
    });

    test('ASIL / KOPYA damgası', () {
      expect(receiptStampText(1), 'ASIL');
      expect(receiptStampText(2), 'KOPYA (2)');
      expect(receiptStampText(5), 'KOPYA (5)');
    });
  });

  group('Kasa / banka', () {
    test('hesap listesi: negatif bakiye uyarısı, son mutabakat, eşlenmemiş tahsilat', () {
      final o = CashOverview.fromJson(<String, dynamic>{
        'items': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 1,
            'name': 'Nakit Kasa',
            'kind': 'cash',
            'note': null,
            'opening_balance_minor': 100000,
            'opening_date': '2026-01-01',
            'balance_minor': 250050,
            'is_active': true,
            'sort_order': 0,
            'last_reconciliation': <String, dynamic>{'as_of_date': '2026-10-01', 'difference_minor': -500},
          },
          <String, dynamic>{
            'id': 2,
            'name': 'Banka',
            'kind': 'bank',
            'opening_balance_minor': 0,
            'opening_date': '2026-01-01',
            'balance_minor': -1000,
            'is_active': false,
            'sort_order': 1,
            'last_reconciliation': null,
          },
        ],
        'total_balance_minor': 249050,
        'unassigned_payments': <String, dynamic>{'count': 3, 'total_minor': 150000},
      });
      expect(o.items, hasLength(2));
      expect(o.items[0].kind, CashAccountKind.cash);
      expect(o.items[0].lastReconciliation!.differenceMinor, -500);
      expect(o.items[1].isNegative, isTrue);
      expect(o.items[1].isActive, isFalse);
      expect(o.activeAccounts, hasLength(1));
      expect(o.totalBalanceMinor, 249050);
      expect(o.unassigned.any, isTrue);
      expect(o.unassigned.totalMinor, 150000);
    });

    test('bakiye okunamazsa FormatException (sessiz 0 yok)', () {
      expect(
        () => CashOverview.fromJson(<String, dynamic>{
          'items': <Map<String, dynamic>>[<String, dynamic>{'id': 1, 'name': 'x', 'kind': 'cash'}],
          'total_balance_minor': 0,
        }),
        throwsFormatException,
      );
      expect(() => CashOverview.fromJson(<String, dynamic>{'items': <dynamic>[]}), throwsFormatException);
    });

    test('hareket sayfası: üst düzey bakiye hesap üstverisine taşınır; işaretli tutar', () {
      final page = MovementPage.fromJson(<String, dynamic>{
        'account': <String, dynamic>{'id': 1, 'name': 'Nakit Kasa', 'kind': 'cash'},
        'balance_minor': 90000,
        'negative_balance': false,
        'items': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 8,
            'kind': 'expense',
            'amount_minor': -12000,
            'movement_date': '2026-10-10',
            'period': '2026-10',
            'label': 'Asansör bakımı',
            'reversed_by_movement_id': 9,
          },
          <String, dynamic>{
            'id': 9,
            'kind': 'reversal',
            'amount_minor': 12000,
            'movement_date': '2026-10-12',
            'reverses_movement_id': 8,
          },
        ],
        'next_before_id': 8,
      });
      expect(page.account!.balanceMinor, 90000);
      expect(page.items[0].amountMinor, -12000);
      expect(page.items[0].isReversed, isTrue);
      expect(page.items[1].isReversal, isTrue);
      expect(page.nextBeforeId, 8);
    });

    test('bilinmeyen hareket türü genel etikete düşer', () {
      final m = AccountMovement.fromJson(<String, dynamic>{'id': 1, 'kind': 'yeni_tur', 'amount_minor': 5});
      expect(m.kind, MovementKind.unknown);
      expect(m.kind.label, 'Hareket');
    });

    test('aktarım ve mutabakat', () {
      final t = TransferWriteResult.fromJson(<String, dynamic>{
        'transfer': <String, dynamic>{
          'id': 3,
          'from_account_id': 1,
          'to_account_id': 2,
          'amount_minor': 50000,
          'transfer_date': '2026-10-16',
        },
        'movements': <Map<String, dynamic>>[
          <String, dynamic>{'id': 20, 'kind': 'transfer_out', 'amount_minor': -50000},
          <String, dynamic>{'id': 21, 'kind': 'transfer_in', 'amount_minor': 50000},
        ],
      });
      expect(t.transfer.fromAccountId, 1);
      expect(t.movements, hasLength(2));
      expect(t.transfer.voided, isFalse);
      final voided = AccountTransfer.fromJson(<String, dynamic>{
        'id': 3,
        'amount_minor': 1,
        'voided': <String, dynamic>{'at': '2026-10-17T10:00:00Z'},
      });
      expect(voided.voided, isTrue);
      final rec = Reconciliation.fromJson(<String, dynamic>{
        'id': 4,
        'as_of_date': '2026-10-16',
        'statement_balance_minor': 100000,
        'computed_balance_minor': 99500,
        'difference_minor': 500,
        'adjustment_movement_id': 33,
      });
      expect(rec.differenceMinor, 500);
      expect(rec.adjusted, isTrue);
      expect(
        ReconciliationStaleInfo.fromPayload(<String, dynamic>{'computed_minor': 12345}).computedMinor,
        12345,
      );
      expect(ReconciliationStaleInfo.fromPayload(null).computedMinor, isNull);
    });

    test('toplu eşleme önizlemesi', () {
      final p = AssignPreview.fromJson(<String, dynamic>{
        'count': 4,
        'total_minor': 200000,
        'by_method': <Map<String, dynamic>>[
          <String, dynamic>{'method': 'cash', 'count': 3, 'total_minor': 150000},
          <String, dynamic>{'method': 'transfer', 'count': 1, 'total_minor': 50000},
        ],
        'preview_hash': 'abc',
      });
      expect(p.byMethod, hasLength(2));
      expect(p.previewHash, 'abc');
      expect(() => AssignPreview.fromJson(<String, dynamic>{'count': 1}), throwsFormatException);
    });
  });

  group('Gider', () {
    test('liste: iptal bilgisi, toplamlar, hesap adı; ayrıntıda ekler', () {
      final page = ExpensePage.fromJson(<String, dynamic>{
        'items': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 4,
            'category_name': 'Elektrik',
            'supplier_name': 'Enerji A.Ş.',
            'description': 'Eylül faturası',
            'amount_minor': 123456,
            'vat_minor': 20576,
            'expense_date': '2026-10-02',
            'account': <String, dynamic>{'id': 1, 'name': 'Nakit Kasa'},
            'document_kind': 'invoice',
            'document_no': 'F-123',
            'voided': null,
            'documents_count': 1,
            'documents': <Map<String, dynamic>>[
              <String, dynamic>{'id': 2, 'status': 'ready', 'display_name': 'fatura.pdf', 'mime_type': 'application/pdf', 'size_bytes': 1000, 'kind': 'invoice'},
            ],
          },
          <String, dynamic>{
            'id': 5,
            'category_name': 'Su',
            'description': 'Yanlış kayıt',
            'amount_minor': 5000,
            'expense_date': '2026-10-03',
            'account': <String, dynamic>{'id': 1, 'name': 'Nakit Kasa'},
            'voided': <String, dynamic>{'at': '2026-10-04T08:00:00Z', 'reason': 'Çift kayıt', 'period': '2026-10'},
          },
        ],
        'next_before_id': 4,
        'totals': <String, dynamic>{'active_minor': 123456, 'voided_minor': 5000},
      });
      expect(page.items[0].isVoided, isFalse);
      expect(page.items[0].accountName, 'Nakit Kasa');
      expect(page.items[0].documentKind, ExpenseDocumentKind.invoice);
      expect(page.items[0].vatMinor, 20576);
      expect(page.items[0].attachments.single.displayName, 'fatura.pdf');
      expect(page.items[1].isVoided, isTrue);
      expect(page.items[1].voided!.reason, 'Çift kayıt');
      expect(page.items[1].vatMinor, isNull);
      expect(page.totals!.activeMinor, 123456);
      expect(page.nextBeforeId, 4);
    });

    test('toplamlar gelmediyse null (sıfır DEĞİL); tutar okunamazsa FormatException', () {
      expect(ExpensePage.fromJson(<String, dynamic>{'items': <dynamic>[]}).totals, isNull);
      expect(
        () => Expense.fromJson(<String, dynamic>{'id': 1, 'description': 'x'}),
        throwsFormatException,
      );
    });

    test('ExpenseInput.toJson: kuruş, tarih, allow_duplicate yalnız true iken, boş belge no gitmez', () {
      final json = ExpenseInput(
        categoryId: 3,
        supplierId: 8,
        description: '  Asansör bakım  ',
        amountMinor: 250000,
        vatMinor: 41667,
        expenseDate: DateTime(2026, 10, 5),
        accountId: 1,
        documentKind: ExpenseDocumentKind.invoice,
        documentNo: '  F-9 ',
      ).toJson();
      expect(json, <String, dynamic>{
        'category_id': 3,
        'supplier_id': 8,
        'description': 'Asansör bakım',
        'amount_minor': 250000,
        'vat_minor': 41667,
        'expense_date': '2026-10-05',
        'account_id': 1,
        'document_kind': 'invoice',
        'document_no': 'F-9',
      });
      final minimal = ExpenseInput(
        categoryId: 1,
        description: 'x',
        amountMinor: 100,
        expenseDate: DateTime(2026, 1, 2),
        accountId: 2,
        documentNo: '   ',
        allowDuplicate: true,
      ).toJson();
      expect(minimal.containsKey('supplier_id'), isFalse);
      expect(minimal.containsKey('vat_minor'), isFalse);
      expect(minimal.containsKey('document_no'), isFalse);
      expect(minimal['allow_duplicate'], true);
      expect(minimal['document_kind'], 'none');
    });

    test('tedarikçi (kurulda gizli alanlar null), kategori', () {
      final s = Supplier.fromJson(<String, dynamic>{'id': 1, 'name': 'A', 'tax_id': null, 'phone': null, 'note': null});
      expect(s.taxId, isNull);
      expect(s.isActive, isTrue);
      final c = ExpenseCategory.fromJson(<String, dynamic>{'id': 2, 'name': 'Personel', 'is_system': true});
      expect(c.isSystem, isTrue);
      expect(c.isActive, isTrue);
    });

    test('yükleme bileti: yol zorunlu; var olan alanlar okunur', () {
      final t = ExpenseUploadTicket.fromJson(<String, dynamic>{
        'document': <String, dynamic>{'id': 7, 'status': 'uploading', 'display_name': 'fis.jpg'},
        'upload': <String, dynamic>{
          'method': 'PUT',
          'path': '/manager/sites/11/finance/expenses/4/documents/7/content',
          'content_type': 'application/octet-stream',
          'size': 2048,
          'max_bytes': 10485760,
          'expires_at': '2026-10-16T12:00:00Z',
        },
      });
      expect(t.document.isReady, isFalse);
      expect(t.size, 2048);
      expect(t.maxBytes, 10485760);
      expect(
        () => ExpenseUploadTicket.fromJson(<String, dynamic>{
          'document': <String, dynamic>{'id': 7},
          'upload': <String, dynamic>{'method': 'PUT'},
        }),
        throwsFormatException,
      );
    });

    test('existingExpenseIdOf', () {
      expect(existingExpenseIdOf(<String, dynamic>{'existing_expense_id': 12}), 12);
      expect(existingExpenseIdOf(null), isNull);
    });
  });

  group('Gecikme tazminatı', () {
    Map<String, dynamic> preview() => <String, dynamic>{
      'period': '2026-09',
      'expected_period': '2026-09',
      'window': <String, dynamic>{'from': '2026-09-01', 'to': '2026-09-30', 'days': 30},
      'settings': <String, dynamic>{'rate_bp': 500, 'method': 'daily_30', 'grace_days': 0, 'settings_version': 3},
      'total_minor': 12345,
      'apartment_count': 2,
      'lines': <Map<String, dynamic>>[
        <String, dynamic>{
          'apartment_id': 301,
          'label': 'A Blok - 5',
          'block_name': 'A Blok',
          'payer_party': 'owner',
          'amount_minor': 10000,
          'base_day_minor': 1200000,
          'peak_overdue_minor': 50000,
        },
        <String, dynamic>{
          'apartment_id': 302,
          'label': 'A Blok - 6',
          'payer_party': 'tenant',
          'amount_minor': 2345,
          'base_day_minor': 281400,
          'peak_overdue_minor': 20000,
        },
      ],
      'waived': <Map<String, dynamic>>[
        <String, dynamic>{'apartment_id': 303, 'label': 'B Blok - 2', 'computed_minor': 777},
      ],
      'inactive_skipped': <Map<String, dynamic>>[
        <String, dynamic>{'apartment_id': 304, 'label': 'B Blok - 3'},
      ],
      'zero_amount_count': 1,
      'preview_hash': 'h1',
      'can_post': true,
      'blockers': <String>[],
    };

    test('önizleme ayrıştırılır', () {
      final p = LateFeePreview.fromJson(preview());
      expect(p.period, const FinancePeriod(2026, 9));
      expect(p.window.days, 30);
      expect(p.params.rateBp, 500);
      expect(p.params.method, LateFeeMethod.daily30);
      expect(p.totalMinor, 12345);
      expect(p.lines, hasLength(2));
      expect(p.lines[0].baseDayMinor, 1200000);
      expect(p.lines[0].peakOverdueMinor, 50000);
      expect(p.waived.single.computedMinor, 777);
      expect(p.inactiveSkipped.single.label, 'B Blok - 3');
      expect(p.zeroAmountCount, 1);
      expect(p.canPost, isTrue);
      expect(p.previewHash, 'h1');
    });

    test('engeller ve Türkçe mesajları', () {
      final p = LateFeePreview.fromJson(<String, dynamic>{
        ...preview(),
        'can_post': false,
        'blockers': <String>['LATE_FEE_PERIOD_NOT_CLOSED', 'LATE_FEE_PERIOD_NOT_NEXT'],
      });
      expect(p.canPost, isFalse);
      expect(p.blockers, hasLength(2));
      expect(
        lateFeeBlockerMessage('LATE_FEE_PERIOD_NOT_CLOSED', period: const FinancePeriod(2026, 9)),
        'Önce Eylül 2026 dönemini kapatın. Tazminat yalnızca kapatılmış ay için hesaplanır.',
      );
      expect(
        lateFeeBlockerMessage('LATE_FEE_PERIOD_NOT_NEXT', expectedPeriod: const FinancePeriod(2026, 8)),
        contains('Ağustos 2026'),
      );
      expect(lateFeeBlockerMessage('YENI_KOD'), isNot(contains('YENI_KOD')), reason: 'ham kod gösterilmez');
    });

    test('toplam okunamazsa FormatException; can_post yoksa false (güvenli)', () {
      expect(() => LateFeePreview.fromJson(<String, dynamic>{...preview()}..remove('total_minor')), throwsFormatException);
      expect(LateFeePreview.fromJson(<String, dynamic>{...preview()}..remove('can_post')).canPost, isFalse);
    });

    test('çalıştırma listesi: net toplam, iptal durumu, sıradaki ay', () {
      final page = LateFeeRunPage.fromJson(<String, dynamic>{
        'items': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 12,
            'period': '2026-08',
            'status': 'active',
            'total_minor': 10000,
            'net_total_minor': 9000,
            'apartment_count': 3,
            'waived_count': 1,
            'params': <String, dynamic>{'rate_bp': 500, 'method': 'daily_actual', 'grace_days': 3, 'settings_version': 2},
            'posted_at': '2026-09-02T09:00:00Z',
            'posted_by_name': 'Yönetici',
          },
          <String, dynamic>{'id': 11, 'period': '2026-07', 'status': 'voided', 'total_minor': 5000, 'voided_at': '2026-08-20T10:00:00Z'},
        ],
        'total': 2,
        'next_period': '2026-09',
        'voidable_run_id': 12,
      });
      expect(page.items[0].netTotalMinor, 9000);
      expect(page.items[0].params.method, LateFeeMethod.dailyActual);
      expect(page.items[1].isVoided, isTrue);
      expect(page.nextPeriod, const FinancePeriod(2026, 9));
      expect(page.voidableRunId, 12);
    });

    test('yazma / iptal sonuçları ve sakin açıklaması', () {
      final post = LateFeePostResult.fromJson(<String, dynamic>{
        'run': <String, dynamic>{'id': 13, 'period': '2026-09', 'total_minor': 100, 'apartment_count': 1},
        'entries_count': 1,
      });
      expect(post.run.id, 13);
      expect(post.entriesCount, 1);
      final voided = LateFeeVoidResult.fromJson(<String, dynamic>{
        'run': <String, dynamic>{'id': 13, 'status': 'voided', 'total_minor': 100},
        'reversed_count': 1,
        'reversed_total_minor': 100,
      });
      expect(voided.reversedTotalMinor, 100);
      expect(() => LateFeePostResult.fromJson(<String, dynamic>{}), throwsFormatException);
      final explanation = LateFeeExplanation.fromJson(<String, dynamic>{
        'period': '2026-09',
        'rate_bp': 500,
        'method': 'daily_30',
        'grace_days': 0,
        'amount_minor': 10000,
        'base_day_minor': 1200000,
        'segments': <Map<String, dynamic>>[
          <String, dynamic>{'from': '2026-09-01', 'to': '2026-09-10', 'overdue_minor': 50000},
        ],
      });
      expect(explanation.segments.single.overdueMinor, 50000);
      expect(explanation.amountMinor, 10000);
    });
  });

  group('Hatırlatma', () {
    test('önizleme: adres / ad alanı yok, sayılar ve hariç nedenleri', () {
      final p = ReminderPreview.fromJson(<String, dynamic>{
        'apartment_count': 12,
        'person_count': 15,
        'with_amount_count': 9,
        'without_amount_count': 6,
        'no_address_count': 2,
        'skipped_pref_count': 1,
        'duplicate_count': 0,
        'capped_count': 3,
        'total_overdue_minor': 987654,
        'excluded': <String, dynamic>{'amount': 4, 'days': 2, 'interval': 1, 'consecutive': 1, 'exclusion': 1, 'no_recipient': 0},
        'hand_follow_up_count': 2,
        'sample_apartments': <String>['A Blok - 5', 'A Blok - 6'],
        'smtp_configured': true,
        'preview_hash': 'rh',
        'blockers': <String>[],
      });
      expect(p.hasRecipients, isTrue);
      expect(p.excluded.total, 9);
      expect(p.handFollowUpCount, 2);
      expect(p.sampleApartments, hasLength(2));
      expect(p.totalOverdueMinor, 987654);
      expect(p.previewHash, 'rh');
    });

    test('çalıştırma: iç içe ya da düz istatistik; iptal edilebilirlik', () {
      final nested = ReminderRun.fromJson(<String, dynamic>{
        'id': 3,
        'status': 'active',
        'tone': 'standard',
        'note': 'Not',
        'apartment_count': 10,
        'person_count': 12,
        'with_amount_count': 8,
        'stats': <String, dynamic>{'pending': 4, 'sent': 6, 'failed': 1, 'no_address': 1},
        'created_at': '2026-10-16T08:00:00Z',
      });
      expect(nested.tone, ReminderTone.standard);
      expect(nested.stats.sent, 6);
      expect(nested.stats.total, 12);
      expect(nested.canCancel, isTrue);
      final flat = ReminderRun.fromJson(<String, dynamic>{'id': 4, 'status': 'cancelled', 'sent': 2});
      expect(flat.stats.sent, 2);
      expect(flat.isCancelled, isTrue);
      expect(flat.canCancel, isFalse);
      expect(ReminderTone.fromApi('yok'), ReminderTone.friendly);
    });

    test('muafiyet satırı iç içe daire alanından okunur', () {
      final e = ReminderExclusion.fromJson(<String, dynamic>{
        'apartment': <String, dynamic>{'id': 301, 'label': 'A Blok - 5', 'block_name': 'A Blok'},
        'reason': 'Anlaşmazlık',
      });
      expect(e.apartmentId, 301);
      expect(e.label, 'A Blok - 5');
      expect(e.reason, 'Anlaşmazlık');
    });
  });

  group('Raporlar', () {
    test('yaşlandırma: kova, kredi ve toplam alanları okunur', () {
      final report = AgingReport.fromJson(<String, dynamic>{
        'site': <String, dynamic>{'name': 'Gül Sitesi'},
        'generated_at': '2026-10-16T09:00:00Z',
        'closed_through': '2026-09',
        'as_of': '2026-10-16',
        'totals': <String, dynamic>{
          ..._bucketMap(1000),
          'credit_minor': 500,
          'late_fee_outstanding_minor': 300,
          'total_overdue_minor': 4000,
        },
        'items': <Map<String, dynamic>>[
          <String, dynamic>{
            'apartment_id': 301,
            'label': 'A Blok - 5',
            'block_name': 'A Blok',
            'payer_party': 'owner',
            'owner_name': 'Ayşe Yılmaz',
            ..._bucketMap(0),
            'credit_minor': 0,
            'late_fee_outstanding_minor': 100,
            'total_overdue_minor': 21,
          },
        ],
        'total': 1,
      });
      expect(report.meta.siteName, 'Gül Sitesi');
      expect(report.meta.closedThrough, const FinancePeriod(2026, 9));
      expect(report.meta.isFinal(const FinancePeriod(2026, 9)), isTrue);
      expect(report.meta.isFinal(const FinancePeriod(2026, 10)), isFalse, reason: 'kesinleşmemiş');
      expect(report.totals[AgingBucket.d31to60], 1002);
      expect(report.totalOverdueMinor, 4000);
      expect(report.items.single.buckets[AgingBucket.d366plus], 6);
      expect(report.items.single.totalOverdueMinor, 21);
    });

    test('yaşlandırma: kova anahtarı eksikse FormatException (sessiz 0 yok)', () {
      final totals = <String, dynamic>{..._bucketMap(1), 'total_overdue_minor': 1}..remove('d61_90_minor');
      expect(
        () => AgingReport.fromJson(<String, dynamic>{'totals': totals, 'items': <dynamic>[]}),
        throwsFormatException,
      );
    });

    test('kapanış yoksa hiçbir ay kesinleşmiş sayılmaz', () {
      const meta = ReportMeta();
      expect(meta.isFinal(const FinancePeriod(2020, 1)), isFalse);
    });

    test('gelir-gider: aylar (months/items), kategori kırılımı aylardan türetilir, oran yoksa null', () {
      final report = IncomeExpenseReport.fromJson(<String, dynamic>{
        'from': '2026-08',
        'to': '2026-09',
        'months': <Map<String, dynamic>>[
          <String, dynamic>{
            'period': '2026-08',
            'charged_minor': 100000,
            'late_fee_minor': 0,
            'collected_minor': 80000,
            'expense_minor': 30000,
            'net_cash_minor': 50000,
            'collection_rate_bp': 8000,
            'expense_by_category': <Map<String, dynamic>>[
              <String, dynamic>{'category_name': 'Elektrik', 'total_minor': 20000},
              <String, dynamic>{'category_name': 'Su', 'total_minor': 10000},
            ],
          },
          <String, dynamic>{
            'period': '2026-09',
            'charged_minor': 0,
            'collected_minor': 0,
            'expense_minor': 5000,
            'net_cash_minor': -5000,
            'collection_rate_bp': null,
            'expense_by_category': <Map<String, dynamic>>[
              <String, dynamic>{'category_name': 'Elektrik', 'total_minor': 5000},
            ],
          },
        ],
      });
      expect(report.months, hasLength(2));
      expect(report.months[1].collectionRateBp, isNull);
      expect(report.chargedMinor, 100000);
      expect(report.netCashMinor, 45000);
      expect(report.expenseByCategory.firstWhere((c) => c.categoryName == 'Elektrik').totalMinor, 25000);
      final top = IncomeExpenseReport.fromJson(<String, dynamic>{
        'items': <Map<String, dynamic>>[
          <String, dynamic>{'period': '2026-08', 'charged_minor': 1, 'collected_minor': 1, 'expense_minor': 0, 'net_cash_minor': 1},
        ],
        'expense_by_category': <Map<String, dynamic>>[
          <String, dynamic>{'category_name': 'Diğer', 'total_minor': 7},
        ],
      });
      expect(top.months, hasLength(1));
      expect(top.expenseByCategory.single.totalMinor, 7);
    });

    test('kasa durumu: düzeltme ayrı satır; toplam zorunlu', () {
      final report = CashPositionReport.fromJson(<String, dynamic>{
        'as_of': '2026-10-16',
        'items': <Map<String, dynamic>>[
          <String, dynamic>{
            'account_id': 1,
            'name': 'Nakit Kasa',
            'kind': 'cash',
            'opening_minor': 100,
            'collections_minor': 200,
            'expenses_minor': -50,
            'transfers_in_minor': 0,
            'transfers_out_minor': -25,
            'adjustments_minor': -5,
            'reversals_minor': 10,
            'balance_minor': 230,
          },
        ],
        'totals': <String, dynamic>{'balance_minor': 230},
        'unassigned_payments': <String, dynamic>{'count': 0, 'total_minor': 0},
      });
      expect(report.items.single.adjustmentsMinor, -5);
      expect(report.totalBalanceMinor, 230);
      expect(report.unassigned.any, isFalse);
      expect(() => CashPositionReport.fromJson(<String, dynamic>{'items': <dynamic>[]}), throwsFormatException);
    });

    test('ekstre: kayan bakiye ve toplamlar', () {
      final s = ApartmentStatement.fromJson(<String, dynamic>{
        'apartment': <String, dynamic>{'id': 301, 'label': 'A Blok - 5', 'block_name': 'A Blok', 'responsible_party': 'owner'},
        'from': '2026-01-01',
        'to': '2026-10-16',
        'opening_balance_minor': 0,
        'closing_balance_minor': 40000,
        'items': <Map<String, dynamic>>[
          <String, dynamic>{..._entry(), 'kind': 'charge', 'amount_minor': 90000, 'running_balance_minor': 90000},
          <String, dynamic>{..._entry(), 'id': 6, 'running_balance_minor': 40000},
        ],
        'totals': <String, dynamic>{'charged_minor': 90000, 'late_fee_minor': 0, 'paid_minor': 50000, 'reversed_minor': 0},
        'overdue_minor': 40000,
      });
      expect(s.items[1].runningBalanceMinor, 40000);
      expect(s.closingBalanceMinor, 40000);
      expect(s.totals.paidMinor, 50000);
      expect(
        () => StatementItem.fromJson(<String, dynamic>{..._entry()}),
        throwsFormatException,
        reason: 'kayan bakiye zorunlu',
      );
    });

    test('kurul özeti: yanıtta olmayan bölüm null kalır (uydurma sıfır yok); uyarılar Türkçe', () {
      final r = BoardSummaryReport.fromJson(<String, dynamic>{
        'site': <String, dynamic>{'name': 'Gül Sitesi'},
        'from': '2026-01',
        'to': '2026-12',
        'collection': <String, dynamic>{
          'charged_minor': 1000000,
          'collected_minor': 900000,
          'collection_rate_bp': 9000,
        },
        'receivables': <String, dynamic>{
          'as_of': '2026-12-31',
          'total_overdue_minor': 100000,
          'debtor_count': 7,
          'debtor_ratio_bp': 1750,
          'aging': <Map<String, dynamic>>[
            <String, dynamic>{'bucket': 'd0_30', 'count': 3, 'total_minor': 40000},
          ],
        },
        'footer': 'Bu rapor noter onaylı karar defteri/yasal defterlerin yerine geçmez.',
        'warnings': <Map<String, dynamic>>[
          <String, dynamic>{'code': 'UNCLOSED_PAST_PERIODS'},
          <String, dynamic>{'code': 'ORTADA_YOK'},
        ],
      });
      expect(r.chargedMinor, 1000000);
      expect(r.debtTotalMinor, 100000, reason: 'sunucu anahtarı total_overdue_minor');
      expect(r.debtorRateBp, 1750, reason: 'sunucu anahtarı debtor_ratio_bp');
      expect(r.apartmentCount, isNull, reason: 'sunucu daire sayısını göndermez; uydurulmaz');
      expect(boardDebtorText(r.debtorCount!, r.apartmentCount, r.debtorRateBp), '7 (%17,50)');
      expect(boardDebtorText(7, 40, 1750), '7 / 40 (%17,50)');
      expect(boardDebtorText(7, null, null), '7');
      expect(r.meta.footer, contains('yasal defterlerin yerine geçmez'));
      expect(r.debtorCount, 7);
      expect(r.aging.single.label, '0-30 gün');
      expect(r.expenseTotalMinor, isNull, reason: 'gider bölümü yanıtta yok: sıfır gösterilmez');
      expect(r.cashTotalMinor, isNull);
      expect(r.debtors, isEmpty);
      expect(r.warnings[0].message, contains('kapatılmamış'));
      expect(r.warnings[1].message, isNot(contains('ORTADA_YOK')));
    });

    test('kurul özeti: eski anahtar adları (debt_total_minor / debtor_rate_bp) hâlâ okunur', () {
      final r = BoardSummaryReport.fromJson(<String, dynamic>{
        'receivables': <String, dynamic>{'debt_total_minor': 5, 'debtor_count': 1, 'apartment_count': 4, 'debtor_rate_bp': 2500},
      });
      expect(r.debtTotalMinor, 5);
      expect(r.debtorRateBp, 2500);
      expect(boardDebtorText(r.debtorCount!, r.apartmentCount, r.debtorRateBp), '1 / 4 (%25,00)');
    });

    test('kurul özeti: borçlu listesi yalnız verildiğinde', () {
      final r = BoardSummaryReport.fromJson(<String, dynamic>{
        'debtor_list': <Map<String, dynamic>>[
          <String, dynamic>{'label': 'A Blok - 5', 'total_minor': 50000},
        ],
      });
      expect(r.debtors.single.totalMinor, 50000);
    });
  });

  group('denetim kaydı etiketleri (finance.* Faz 4b)', () {
    const actions = <String, (String, AppTone, String)>{
      'finance.settings.updated': ('Finans ayarları güncellendi', AppTone.info, 'Finans ayarları'),
      'finance.receipt.issued': ('Makbuz düzenlendi', AppTone.success, 'Makbuz #12'),
      'finance.receipt.printed': ('Makbuz basımı kaydedildi', AppTone.info, 'Makbuz #12'),
      'finance.receipt.cancelled': ('Makbuz iptal edildi', AppTone.warning, 'Makbuz #12'),
      'finance.latefee.posted': ('Gecikme tazminatı yazıldı', AppTone.success, 'Tazminat çalıştırması #12'),
      'finance.latefee.voided': ('Gecikme tazminatı iptal edildi', AppTone.warning, 'Tazminat çalıştırması #12'),
      'finance.account.created': ('Kasa / banka hesabı eklendi', AppTone.success, 'Hesap #12'),
      'finance.account.updated': ('Kasa / banka hesabı güncellendi', AppTone.info, 'Hesap #12'),
      'finance.account.adjusted': ('Hesap düzeltmesi yapıldı', AppTone.info, 'Hesap #12'),
      'finance.transfer.created': ('Hesaplar arası aktarım yapıldı', AppTone.success, 'Aktarım #12'),
      'finance.transfer.voided': ('Hesaplar arası aktarım iptal edildi', AppTone.warning, 'Aktarım #12'),
      'finance.reconciliation.recorded': ('Hesap mutabakatı kaydedildi', AppTone.info, 'Mutabakat #12'),
      'finance.payments.assigned': ('Tahsilatlar hesaba eşlendi', AppTone.info, 'Tahsilat eşleme'),
      'finance.expense.created': ('Gider eklendi', AppTone.success, 'Gider #12'),
      'finance.expense.corrected': ('Gider düzeltildi', AppTone.info, 'Gider #12'),
      'finance.expense.voided': ('Gider iptal edildi', AppTone.warning, 'Gider #12'),
      'finance.expense.document_attached': ('Gider belgesi eklendi', AppTone.success, 'Gider #12'),
      'finance.expense.document_removed': ('Gider belgesi kaldırıldı', AppTone.neutral, 'Gider #12'),
      'finance.category.created': ('Gider kategorisi eklendi', AppTone.success, 'Gider kategorisi #12'),
      'finance.category.updated': ('Gider kategorisi güncellendi', AppTone.info, 'Gider kategorisi #12'),
      'finance.supplier.created': ('Tedarikçi eklendi', AppTone.success, 'Tedarikçi #12'),
      'finance.supplier.updated': ('Tedarikçi güncellendi', AppTone.info, 'Tedarikçi #12'),
      'finance.report.debtor_list': ('Borçlu listesi görüntülendi', AppTone.info, 'Rapor'),
      'finance.reminder.sent': ('Borç hatırlatma gönderildi', AppTone.success, 'Hatırlatma #12'),
      'finance.reminder.cancelled': ('Borç hatırlatma iptal edildi', AppTone.neutral, 'Hatırlatma #12'),
      'finance.reminder.exclusion_added': ('Daire hatırlatmadan muaf tutuldu', AppTone.info, 'Hatırlatma #12'),
      'finance.reminder.exclusion_removed': ('Hatırlatma muafiyeti kaldırıldı', AppTone.neutral, 'Hatırlatma #12'),
      'finance.legal_gate.updated': ('Finans hukuk onayı bayrağı güncellendi', AppTone.warning, 'Hukuk onayı bayrağı'),
    };

    test('her yeni eylemin Türkçe etiketi, tonu, hedef metni ve süzgeç satırı vardır', () {
      for (final entry in actions.entries) {
        final (label, tone, target) = entry.value;
        expect(financeActionLabel(entry.key), label, reason: entry.key);
        final log = AuditLogEntry.fromJson(<String, dynamic>{
          'id': 1,
          'action': entry.key,
          'target_type': 'finance',
          'target_id': '12',
          'details': <String, dynamic>{'note': 'gizli not', 'name': 'Ayşe'},
        });
        expect(log.actionLabel, label, reason: entry.key);
        expect(log.targetLabel, target, reason: entry.key);
        expect(auditToneOf(entry.key), tone, reason: entry.key);
        final filters = AuditLogView.actionFilters.where((f) => f.$1 == entry.key).toList();
        expect(filters, hasLength(1), reason: 'süzgeç: ${entry.key}');
        expect(filters.single.$2, label);
      }
      final values = AuditLogView.actionFilters.map((f) => f.$1).toList();
      expect(values.toSet().length, values.length, reason: 'süzgeç değerleri tekrarlanmaz');
    });

    test('4a eylemleri değişmedi', () {
      expect(financeActionLabel('finance.payment.recorded'), 'Tahsilat kaydedildi');
      expect(
        AuditLogEntry.fromJson(<String, dynamic>{'id': 1, 'action': 'finance.payment.recorded', 'target_type': 'finance', 'target_id': '12'}).targetLabel,
        'Tahsilat #12',
      );
      expect(financeActionLabel('finance.xyz'), isNull);
    });
  });

  group('belge bileti (upload) tekrar denemesi', () {
    test('upload: null + belge hazır = zaten yüklenmiş (ikinci yükleme yok)', () {
      final ticket = ExpenseUploadTicket.fromJson(<String, dynamic>{
        'document': <String, dynamic>{'id': 3, 'status': 'ready', 'display_name': 'fatura.pdf', 'size_bytes': 1200, 'kind': 'invoice'},
        'upload': null,
      });
      expect(ticket.alreadyStored, isTrue);
      expect(ticket.document.isReady, isTrue);
      expect(ticket.path, isEmpty);
    });

    test('upload: null + belge hâlâ yükleniyor = okunamadı (sessiz başarı yok)', () {
      expect(
        () => ExpenseUploadTicket.fromJson(<String, dynamic>{
          'document': <String, dynamic>{'id': 3, 'status': 'uploading', 'display_name': 'fatura.pdf', 'size_bytes': 1200},
          'upload': null,
        }),
        throwsFormatException,
      );
    });

    test('normal bilet: yol, boyut, üst sınır', () {
      final ticket = ExpenseUploadTicket.fromJson(<String, dynamic>{
        'document': <String, dynamic>{'id': 3, 'status': 'uploading', 'display_name': 'fatura.pdf', 'size_bytes': 1200},
        'upload': <String, dynamic>{
          'method': 'PUT',
          'path': '/manager/sites/11/finance/expenses/5/documents/3/content',
          'content_type': 'application/octet-stream',
          'size': 1200,
          'max_bytes': 10485760,
        },
      });
      expect(ticket.alreadyStored, isFalse);
      expect(ticket.path, '/manager/sites/11/finance/expenses/5/documents/3/content');
      expect(ticket.maxBytes, 10485760);
    });
  });

  group('makbuz doğrulama yanıtı (R10)', () {
    test('geçerli: eşleşen makbuzun özeti okunur', () {
      final r = ReceiptVerifyResult.fromJson(<String, dynamic>{
        'valid': true,
        'status': 'active',
        'number': 'MK-2026-000123',
        'amount_minor': 123456,
        'paid_on': '2026-10-14',
        'issued_on': '2026-10-16',
        'apartment_label': 'A Blok - 5',
      });
      expect((r.valid, r.status, r.number, r.amountMinor, r.apartmentLabel), (true, 'active', 'MK-2026-000123', 123456, 'A Blok - 5'));
      expect(r.paidOn, DateTime(2026, 10, 14));
      expect(r.issuedOn, DateTime(2026, 10, 16));
    });

    test('geçersiz: yalnız {valid:false,status:null}; özet alanları yok sayılır (sızıntı olmaz)', () {
      final r = ReceiptVerifyResult.fromJson(<String, dynamic>{'valid': false, 'status': null, 'number': 'MK-2026-000001', 'amount_minor': 5});
      expect(r.valid, isFalse);
      expect(r.number, isNull);
      expect(r.amountMinor, isNull);
    });
  });

  group('boş ay işareti (record_empty) modelleri', () {
    test('önizleme: empty alanı; yoksa false', () {
      expect(LateFeePreview.fromJson(<String, dynamic>{'total_minor': 0, 'apartment_count': 0, 'empty': true, 'can_post': true, 'preview_hash': 'h'}).empty, isTrue);
      expect(LateFeePreview.fromJson(<String, dynamic>{'total_minor': 0, 'apartment_count': 0, 'can_post': true}).empty, isFalse);
    });

    test('çalıştırma: empty alanı; eski sunucuda apartment_count 0 ise empty sayılır', () {
      expect(LateFeeRun.fromJson(<String, dynamic>{'id': 1, 'total_minor': 0, 'apartment_count': 0, 'empty': true}).empty, isTrue);
      expect(LateFeeRun.fromJson(<String, dynamic>{'id': 1, 'total_minor': 100, 'apartment_count': 2, 'empty': false}).empty, isFalse);
      expect(LateFeeRun.fromJson(<String, dynamic>{'id': 1, 'total_minor': 0, 'apartment_count': 0}).empty, isTrue);
      expect(LateFeeRun.fromJson(<String, dynamic>{'id': 1, 'total_minor': 100, 'apartment_count': 2}).empty, isFalse);
    });

    test('çalıştırma satırı: reversed (iptal edilen kalem) okunur; ödeyen yoksa null', () {
      final line = LateFeeLine.fromJson(<String, dynamic>{'apartment_id': 1, 'label': 'A Blok - 5', 'amount_minor': 10, 'reversed': true});
      expect(line.reversed, isTrue);
      expect(line.payerParty, isNull);
      expect(LateFeeLine.fromJson(<String, dynamic>{'apartment_id': 1, 'amount_minor': 10}).reversed, isFalse);
    });

    test('hatırlatma notu: bağlantı / alan adı / e-posta REDDEDİLİR (sunucu kuralıyla aynı); düz metin kabul', () {
      for (final bad in const ['https://x.test', 'bkz www.site.com', 'a@b.co', 'bilgi: odeme.com', 'HTTP://X', 'portal.tr']) {
        expect(reminderNoteHasLink(bad), isTrue, reason: bad);
      }
      for (final ok in const ['Lütfen ödemenizi kontrol ediniz.', 'Aidat 1.250,50 TL', 'Teşekkürler.', '']) {
        expect(reminderNoteHasLink(ok), isFalse, reason: ok);
      }
    });
  });

  group('R13 P1: kurul özeti SUNUCUNUN gerçek biçimiyle (finance_reports.js boardSummaryReport)', () {
    Map<String, dynamic> serverBoard({bool debtors = true}) => <String, dynamic>{
      'site': <String, dynamic>{'name': 'Gül Sitesi'},
      'generated_at': '2026-10-16T09:00:00.000Z',
      'closed_through': '2026-09',
      'currency': 'TRY',
      'footer': 'Bu rapor noter onaylı karar defteri/yasal defterlerin yerine geçmez.',
      'from': '2026-01',
      'to': '2026-10',
      'period_title': 'Ocak 2026 - Ekim 2026',
      'collection': <String, dynamic>{'charged_minor': 100, 'late_fee_minor': 0, 'collected_minor': 90, 'collection_rate_bp': 9000},
      'receivables': <String, dynamic>{
        'as_of': '2026-10-16',
        'total_overdue_minor': 250000,
        'debtor_count': 3,
        'debtor_ratio_bp': 1500,
        'aging': <Map<String, dynamic>>[
          <String, dynamic>{'bucket': 'not_due', 'count': 2, 'total_minor': 100000},
          <String, dynamic>{'bucket': 'd0_30', 'count': 3, 'total_minor': 250000},
        ],
      },
      'expenses': <String, dynamic>{'total_minor': 5, 'by_category': <Object?>[], 'top_items': <Object?>[]},
      'cash': <String, dynamic>{
        // Sunucu kurul özetinde YALNIZ bu alanları gönderir (hareket kırılımı YOK).
        'accounts': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 1,
            'name': 'Nakit Kasa',
            'kind': 'cash',
            'balance_minor': 249500,
            'last_reconciliation': <String, dynamic>{'as_of_date': '2026-09-30', 'difference_minor': -500},
          },
          <String, dynamic>{'id': 2, 'name': 'Ziraat', 'kind': 'bank', 'balance_minor': 1000, 'last_reconciliation': null},
        ],
        'total_balance_minor': 250500,
        'unassigned_payments': <String, dynamic>{'count': 0, 'total_minor': 0},
      },
      'late_fee': <String, dynamic>{'run_count': 1, 'total_minor': 7, 'waived_count': 0},
      'reminders': <String, dynamic>{'sent_count': 4},
      'warnings': <Object?>[],
      if (debtors)
        'debtor_list': <Map<String, dynamic>>[
          <String, dynamic>{'label': 'A Blok - 5', 'total_overdue_minor': 150000},
          <String, dynamic>{'label': 'B Blok - 2', 'total_overdue_minor': 100000},
        ],
    };

    test('kasa / banka hesabı olan sitenin özeti ayrıştırılır (hareket kırılımı alanları ZORUNLU değil)', () {
      final r = BoardSummaryReport.fromJson(serverBoard(debtors: false));
      expect(r.cashAccounts.map((a) => a.name), <String>['Nakit Kasa', 'Ziraat']);
      expect(r.cashAccounts.first.balanceMinor, 249500);
      expect(r.cashAccounts.first.lastReconciliation?.differenceMinor, -500);
      expect(r.cashAccounts.last.lastReconciliation, isNull);
      expect(r.cashTotalMinor, 250500);
    });

    test('include_debtor_list=true: borçlu listesi total_overdue_minor ile ayrıştırılır', () {
      final r = BoardSummaryReport.fromJson(serverBoard());
      expect(r.debtors.map((d) => d.label), <String>['A Blok - 5', 'B Blok - 2']);
      expect(r.debtors.map((d) => d.totalMinor), <int>[150000, 100000]);
    });

    test('vadesi gelmemiş kova, vadesi geçmiş toplamdan AYRI tutulur', () {
      final r = BoardSummaryReport.fromJson(serverBoard());
      expect(r.debtTotalMinor, 250000, reason: 'sunucu: yalnız vadesi geçmiş');
      expect(r.notDueMinor, 100000);
      expect(r.notDueCount, 2);
      expect(r.aging.where((a) => a.key != 'not_due').map((a) => a.key), <String>['d0_30']);
    });
  });
}
