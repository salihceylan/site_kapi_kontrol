// Firma ve Sözleşme Takibi modelleri (lib/models/contract_models.dart), form doğrulayıcıları
// (lib/ui/helpers/contract_validation.dart) ve görüntü yardımcıları (lib/ui/widgets/contract_parts.dart).
//
// Kurallar: alan yok / bozuk ise güvenli varsayılan (çökme yok); bilinmeyen sabit değer en zararsız değere düşer; tutar
// metinden TAMSAYI KURUŞA çevrilir (kayan nokta yok); düzenleme gövdesi YALNIZ değişen alanları taşır.
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/audit_log.dart';
import 'package:site_kapi_kontrol/models/contract_models.dart';
import 'package:site_kapi_kontrol/ui/helpers/contract_validation.dart';
import 'package:site_kapi_kontrol/ui/widgets/contract_parts.dart';

import 'screens/contract_fixtures.dart';

void main() {
  group('Contract.fromJson', () {
    test('tam gövde ({contract} sarmalı): tüm alanlar', () {
      final c = Contract.fromJson(<String, dynamic>{
        'contract': ctContract(11, autoRenew: true, note: 'Not'),
      });
      expect(c.id, 11);
      expect(c.vendorId, 1);
      expect(c.vendorName, 'Yıldız Asansör Bakım Ltd. Şti.');
      expect(c.title, 'Asansör yıllık bakım sözleşmesi');
      expect(c.category, ContractCategory.asansor);
      expect(c.startDate, DateTime(2026, 1, 1));
      expect(c.endDate, DateTime(2026, 12, 31));
      expect(c.noticeDays, 30);
      expect(c.remindBeforeDays, 30);
      expect(c.amountMinor, 125000);
      expect(c.currency, 'TRY');
      expect(c.period, ContractPeriod.aylik);
      expect(c.autoRenew, isTrue);
      expect(c.status, ContractStatus.aktif);
      expect(c.state, ContractState.aktif);
      expect(c.daysLeft, 73);
      expect(c.noticeDeadline, DateTime(2026, 12, 1));
      expect(c.terminatedAt, isNull);
      expect(c.note, 'Not');
      expect(c.createdByName, 'Site Yöneticisi');
      expect(c.createdAt, DateTime.utc(2026, 9, 5, 8));
      expect(c.isTerminated, isFalse);
      expect(c.isOpenEnded, isFalse);
    });

    test('eksik alanlar: güvenli varsayılanlar, çökme yok', () {
      final c = Contract.fromJson(<String, dynamic>{'id': 5});
      expect(c.id, 5);
      expect(c.vendorId, 0);
      expect(c.displayVendor, 'İsimsiz firma');
      expect(c.displayTitle, 'Başlıksız sözleşme');
      expect(c.category, ContractCategory.diger);
      expect(c.startDate, isNull);
      expect(c.endDate, isNull);
      expect(c.isOpenEnded, isTrue);
      expect(c.noticeDays, 0);
      expect(c.amountMinor, isNull);
      expect(c.currency, 'TRY');
      expect(c.period, isNull);
      expect(c.autoRenew, isFalse);
      expect(c.status, ContractStatus.aktif);
      expect(c.state, ContractState.unknown);
      expect(c.daysLeft, isNull);
      expect(c.noticeDeadline, isNull);
      expect(c.note, isNull);
    });

    test('bilinmeyen sabitler ve metin sayılar', () {
      final c = Contract.fromJson(<String, dynamic>{
        'id': '7',
        'vendor_id': '3',
        'category': 'uzay',
        'period': 'haftalik',
        'status': 'askida',
        'state': 'bilinmez',
        'days_left': '-4',
        'notice_days': -5,
        'remind_before_days': '15',
        'auto_renew': 'true',
        'end_date': '2026-13-40',
        'start_date': '2026-02-03T00:00:00.000Z',
        'amount': 1250.5,
        'currency': 'usd',
        'terminated_at': 'bozuk',
      });
      expect(c.id, 7);
      expect(c.vendorId, 3);
      expect(c.category, ContractCategory.diger);
      expect(c.period, isNull);
      expect(c.status, ContractStatus.aktif);
      expect(c.state, ContractState.unknown);
      expect(c.daysLeft, -4);
      expect(c.noticeDays, 0);
      expect(c.remindBeforeDays, 15);
      expect(c.autoRenew, isTrue);
      expect(c.endDate, isNull);
      expect(c.startDate, DateTime(2026, 2, 3));
      expect(c.amountMinor, 125050);
      expect(c.currency, 'USD');
      expect(c.terminatedAt, isNull);
    });

    test('feshedilmiş: status / state / terminated_at', () {
      final c = Contract.fromJson(ctContract(15, status: 'feshedildi'));
      expect(c.status, ContractStatus.feshedildi);
      expect(c.state, ContractState.feshedildi);
      expect(c.isTerminated, isTrue);
      expect(c.terminatedAt, DateTime.utc(2026, 10, 10, 9, 30));
    });

    test('listFrom: kimliksiz ve harita olmayan öğeler atlanır', () {
      final list = Contract.listFrom(<Object?>[
        ctContract(1),
        <String, dynamic>{'id': 0},
        'metin',
        null,
        ctContract(2),
      ]);
      expect(list.map((c) => c.id), <int>[1, 2]);
      expect(Contract.listFrom(null), isEmpty);
      expect(Contract.listFrom(<String, dynamic>{}), isEmpty);
    });
  });

  group('tutar', () {
    test('contractAmountMinor: metin, sayı, virgül; bozuk -> null', () {
      expect(contractAmountMinor('1250.00'), 125000);
      expect(contractAmountMinor('1250'), 125000);
      expect(contractAmountMinor('1250,5'), 125050);
      expect(contractAmountMinor('0.00'), 0);
      expect(contractAmountMinor('999999999999.99'), 99999999999999);
      expect(contractAmountMinor(12), 1200);
      expect(contractAmountMinor(12.345), 1235);
      expect(contractAmountMinor('12.345'), 1234, reason: 'fazla ondalık kesilir');
      expect(contractAmountMinor(null), isNull);
      expect(contractAmountMinor(''), isNull);
      expect(contractAmountMinor('1.250,00'), isNull, reason: 'binlik ayırıcı sunucu biçimi değil');
      expect(contractAmountMinor('abc'), isNull);
      expect(contractAmountMinor(double.nan), isNull);
    });

    test('contractAmountWire: kuruş -> "1250.50"', () {
      expect(contractAmountWire(125050), '1250.50');
      expect(contractAmountWire(5), '0.05');
      expect(contractAmountWire(0), '0.00');
    });

    test('görüntü: Türkçe para biçimi ve dönem', () {
      final c = Contract.fromJson(ctContract(1, amount: '48000.50', period: 'yillik'));
      expect(contractAmountText(c), '48.000,50 ₺');
      expect(contractAmountWithPeriod(c), '48.000,50 ₺ / Yıllık');
      final none = Contract.fromJson(ctContract(2, amount: null, period: null));
      expect(contractAmountText(none), isNull);
      expect(contractAmountWithPeriod(none), 'Belirtilmedi');
    });
  });

  group('kalan gün metni', () {
    test('sunucu days_left: kaldı / bugün / önce bitti / süresiz', () {
      Contract with_(Object? days, {String? end = '2026-12-31'}) =>
          Contract.fromJson(<String, dynamic>{'id': 1, 'end_date': end, 'days_left': days});
      expect(contractRemainingText(with_(73)), '73 gün kaldı');
      expect(contractRemainingText(with_(0)), 'Bugün bitiyor');
      expect(contractRemainingText(with_(-19)), '19 gün önce bitti');
      expect(contractRemainingText(with_(null, end: null)), 'Süresiz');
    });

    test('days_left yoksa İstanbul gününe göre hesaplanır', () {
      final c = Contract.fromJson(<String, dynamic>{'id': 1, 'end_date': '2026-11-05'});
      expect(contractDaysLeft(c, today: DateTime(2026, 10, 19)), 17);
      expect(contractRemainingText(c, today: DateTime(2026, 11, 6)), '1 gün önce bitti');
    });
  });

  group('ContractVendor', () {
    test('{vendor} sarmalı ve tüm alanlar', () {
      final v = ContractVendor.fromJson(<String, dynamic>{
        'vendor': ctVendor(4, contact: 'Murat', phone: '0212', email: 'a@b.co', taxNo: '123', note: 'n', count: 3),
      });
      expect(v.id, 4);
      expect(v.category, ContractCategory.asansor);
      expect(v.contactName, 'Murat');
      expect(v.phone, '0212');
      expect(v.email, 'a@b.co');
      expect(v.taxNo, '123');
      expect(v.note, 'n');
      expect(v.isActive, isTrue);
      expect(v.contractCount, 3);
      expect(v.createdAt, DateTime.utc(2026, 9, 1, 8));
    });

    test('eksik / bozuk alanlar', () {
      final v = ContractVendor.fromJson(<String, dynamic>{
        'id': 2,
        'name': '  ',
        'category': 'yok',
        'contact_name': '',
        'contract_count': '-3',
        'is_active': 0,
      });
      expect(v.displayName, 'İsimsiz firma');
      expect(v.category, ContractCategory.diger);
      expect(v.contactName, isNull);
      expect(v.contractCount, 0);
      expect(v.isActive, isFalse);
      expect(ContractVendor.fromJson(<String, dynamic>{'id': 3}).isActive, isTrue);
    });

    test('listFrom: {items} ya da düz liste; kimliksiz atlanır', () {
      expect(
        ContractVendor.listFrom(<String, dynamic>{
          'items': <Object>[ctVendor(1), <String, dynamic>{'id': 0}],
        }).map((v) => v.id),
        <int>[1],
      );
      expect(ContractVendor.listFrom(<Object>[ctVendor(5)]).single.id, 5);
      expect(ContractVendor.listFrom(<String, dynamic>{}), isEmpty);
    });
  });

  group('sayfa ve özet', () {
    test('ContractPage: yalnız opak next_cursor; boş / null / eski next_before_id son sayfadır', () {
      final page = ContractPage.fromJson(<String, dynamic>{
        'items': <Object>[ctContract(1)],
        'next_cursor': 'WyIyMDI2LTEyLTMxIiwxXQ',
      });
      expect(page.items.single.id, 1);
      expect(page.nextCursor, 'WyIyMDI2LTEyLTMxIiwxXQ');
      expect(ContractPage.fromJson(<String, dynamic>{'next_cursor': ' '}).nextCursor, isNull);
      expect(ContractPage.fromJson(<String, dynamic>{'next_cursor': null}).nextCursor, isNull);
      expect(ContractPage.fromJson(<String, dynamic>{'next_before_id': 9}).nextCursor, isNull);
      expect(ContractPage.fromJson(<String, dynamic>{}).items, isEmpty);
    });

    test('ContractSummary: düz ya da {summary}; eksik / negatif 0', () {
      final flat = ContractSummary.fromJson(<String, dynamic>{
        'active': 2,
        'expiring_soon': '1',
        'expired': -3,
      });
      expect(flat.active, 2);
      expect(flat.expiringSoon, 1);
      expect(flat.expired, 0);
      expect(flat.terminated, 0);
      expect(flat.countOf(ContractState.yaklasiyor), 1);
      expect(flat.countOf(ContractState.unknown), 0);
      final wrapped = ContractSummary.fromJson(<String, dynamic>{
        'summary': <String, dynamic>{'terminated': 4},
      });
      expect(wrapped.terminated, 4);
    });
  });

  group('form gövdeleri', () {
    final original = Contract.fromJson(ctContract(11, note: 'Eski not'));

    ContractDraft draft({
      int vendorId = 1,
      String title = 'Asansör yıllık bakım sözleşmesi',
      DateTime? end,
      bool clearEnd = false,
      int? amount = 125000,
      ContractPeriod? period = ContractPeriod.aylik,
      String note = 'Eski not',
      int notice = 30,
    }) => ContractDraft(
      vendorId: vendorId,
      title: title,
      category: ContractCategory.asansor,
      startDate: DateTime(2026, 1, 1),
      endDate: clearEnd ? null : (end ?? DateTime(2026, 12, 31)),
      noticeDays: notice,
      remindBeforeDays: 30,
      amountMinor: amount,
      period: period,
      note: note,
    );

    test('yeni sözleşme: boş isteğe bağlı alanlar gönderilmez', () {
      final body = ContractDraft(
        vendorId: 2,
        title: '  Güvenlik  ',
        category: ContractCategory.guvenlik,
        startDate: DateTime(2026, 11, 1),
        noticeDays: 0,
        remindBeforeDays: 0,
        note: '   ',
      ).toCreateJson();
      expect(body, <String, dynamic>{
        'vendor_id': 2,
        'title': 'Güvenlik',
        'category': 'guvenlik',
        'start_date': '2026-11-01',
        'notice_days': 0,
        'remind_before_days': 0,
        'auto_renew': false,
      });
    });

    test('düzenleme: değişiklik yoksa boş; yalnız değişenler; temizlenenler null', () {
      expect(draft().toPatchJson(original), isEmpty);
      expect(draft(title: 'Yeni başlık', notice: 45).toPatchJson(original), <String, dynamic>{
        'title': 'Yeni başlık',
        'notice_days': 45,
      });
      expect(draft(clearEnd: true, amount: null, period: null, note: ' ').toPatchJson(original), <String, dynamic>{
        'end_date': null,
        'amount': null,
        'period': null,
        'note': null,
      });
      expect(draft(vendorId: 2, amount: 0).toPatchJson(original), <String, dynamic>{
        'vendor_id': 2,
        'amount': '0.00',
      });
    });

    test('firma: yeni gövde ve düzenleme farkı', () {
      const create = ContractVendorDraft(
        name: ' Mavi Havuz ',
        category: ContractCategory.havuz,
        phone: ' 444 1 444 ',
      );
      expect(create.toCreateJson(), <String, dynamic>{
        'name': 'Mavi Havuz',
        'category': 'havuz',
        'phone': '444 1 444',
      });
      final vendor = ContractVendor.fromJson(ctVendor(1, contact: 'Murat', email: 'a@b.co'));
      expect(
        ContractVendorDraft(
          name: vendor.name,
          category: vendor.category,
          contactName: 'Murat',
          email: 'a@b.co',
        ).toPatchJson(vendor),
        isEmpty,
      );
      expect(
        ContractVendorDraft(
          name: vendor.name,
          category: ContractCategory.teknikBakim,
          contactName: '',
          email: 'a@b.co',
          note: 'Yeni',
        ).toPatchJson(vendor),
        <String, dynamic>{'category': 'teknik_bakim', 'contact_name': null, 'note': 'Yeni'},
      );
    });
  });

  group('ContractSite', () {
    test('yalnız yönetici yazar; eşitlik erişim türünü içerir', () {
      expect(const ContractSite(code: 1, name: 'A').canWrite, isTrue);
      expect(const ContractSite(code: 1, name: 'A', access: ContractSiteAccess.board).canWrite, isFalse);
      expect(const ContractSite(code: 1, name: 'A', access: ContractSiteAccess.staff).canWrite, isFalse);
      expect(
        const ContractSite(code: 1, name: 'A'),
        isNot(const ContractSite(code: 1, name: 'A', access: ContractSiteAccess.staff)),
      );
      expect(const ContractSite(code: 1, name: ' ').label, 'İsimsiz site');
    });
  });

  group('doğrulayıcılar', () {
    test('başlangıç zorunlu ve geçerli tarih', () {
      expect(contractStartDateError(''), 'Başlangıç tarihini girin (GG.AA.YYYY).');
      expect(contractStartDateError('31.02.2026'), startsWith('Geçersiz tarih'));
      expect(contractStartDateError('2026-01-01'), startsWith('Tarihi GG.AA.YYYY'));
      expect(contractStartDateError('01.01.2026'), isNull);
      expect(contractStartDateError('01.01.1989'), 'Tarih 1990-2100 arasında olmalı.');
      expect(contractEndDateError('01.01.1950', ''), 'Tarih 1990-2100 arasında olmalı.');
    });

    test('bitiş: boş serbest; başlangıçtan önce olamaz; aynı gün olur', () {
      expect(contractEndDateError('', '01.11.2026'), isNull);
      expect(contractEndDateError('01.11.2026', '01.11.2026'), isNull);
      expect(contractEndDateError('31.10.2026', '01.11.2026'), 'Bitiş tarihi başlangıç tarihinden önce olamaz.');
      expect(contractEndDateError('31.10.2026', ''), isNull, reason: 'başlangıç geçersizse sıra denetlenmez');
      expect(contractEndDateError('32.10.2026', '01.11.2026'), startsWith('Geçersiz tarih'));
    });

    test('gün sayısı: 0..max, yalnız rakam, zorunlu', () {
      expect(contractDayCountError('0', max: 365), isNull);
      expect(contractDayCountError('365', max: 365), isNull);
      expect(contractDayCountError('366', max: 365), 'En çok 365 gün olabilir.');
      expect(contractDayCountError('181', max: 180), 'En çok 180 gün olabilir.');
      expect(contractDayCountError('99999999999999', max: 365), 'En çok 365 gün olabilir.');
      expect(contractDayCountError('', max: 180), 'Gün sayısını girin (0-180).');
      expect(contractDayCountError('-1', max: 180), 'Gün sayısını yalnız rakamla girin (0-180).');
      expect(contractDayCountError('3,5', max: 180), 'Gün sayısını yalnız rakamla girin (0-180).');
      expect(parseContractDayCount(' 45 ', max: 180), 45);
      expect(parseContractDayCount('500', max: 365), isNull);
    });

    test('tutar: boş serbest; sıfır olur; virgül ondalık; negatif ve 3 ondalık reddedilir', () {
      expect(contractAmountError(''), isNull);
      expect(contractAmountError('0'), isNull);
      expect(contractAmountError('1.250,50'), isNull);
      expect(contractAmountError('-5'), 'Tutar negatif olamaz.');
      expect(contractAmountError('12,345'), 'Kuruş en çok 2 basamak olabilir (örn. 1.250,50).');
      expect(contractAmountError('12a'), 'Tutarı rakamlarla girin (örn. 1.250,50).');
      expect(contractAmountFromField('1.250,50'), 125050);
      expect(contractAmountFromField('1250,5'), 125050);
      expect(contractAmountFromField('0'), 0);
      expect(contractAmountFromField(''), isNull);
      expect(contractAmountFromField('-1'), isNull);
    });

    test('metin uzunlukları kod noktasıyla', () {
      expect(contractRequiredText('  ', 10, emptyMessage: 'Boş'), 'Boş');
      expect(contractRequiredText('a' * 11, 10), 'En çok 10 karakter olabilir.');
      expect(contractRequiredText('😀' * 10, 10), isNull);
      expect(contractOptionalText('', 10), isNull);
      expect(contractOptionalText('a' * 11, 10), 'En çok 10 karakter olabilir.');
    });

    test('firma e-posta / telefon / vergi no (sunucu kuralları)', () {
      expect(contractVendorEmailError(''), isNull);
      expect(contractVendorEmailError('destek@firma.com'), isNull);
      expect(contractVendorEmailError('destek@'), isNotNull);
      expect(contractVendorEmailError('a..b@firma.com'), isNotNull);
      expect(contractVendorEmailError('a,b@firma.com'), isNotNull);
      expect(contractVendorPhoneError(''), isNull);
      expect(contractVendorPhoneError('0212 555 12 34'), isNull);
      expect(contractVendorPhoneError('444 1 444'), isNull);
      expect(contractVendorPhoneError('+90 (532) 111-22-33'), isNull);
      expect(contractVendorPhoneError('12'), 'Telefon numarası 3-20 haneli olmalı.');
      expect(contractVendorPhoneError('abc'), isNotNull);
      expect(contractVendorPhoneError('1' * 33), 'En çok 32 karakter olabilir.');
      expect(contractVendorTaxNoError(''), isNull);
      expect(contractVendorTaxNoError('1234567890'), isNull);
      expect(contractVendorTaxNoError('TR-12 34'), isNull);
      expect(contractVendorTaxNoError('12/34'), isNotNull);
      expect(contractVendorTaxNoError('1' * 21), 'En çok 20 karakter olabilir.');
    });

    test('tel: için arama metni', () {
      expect(contractDialable('+90 532 111 22 33'), '+905321112233');
      expect(contractDialable('0212 555 12 34'), '02125551234');
      expect(contractDialable('  '), isNull);
      expect(contractDialable('---'), isNull);
    });
  });

  group('denetim kaydı', () {
    test('eylem başlıkları (fesih / yeniden etkinleştirme / pasife alma ayrıntıdan)', () {
      expect(contractActionLabel('contract_vendor.created'), 'Firma eklendi');
      expect(contractActionLabel('contract_vendor.updated', <String, dynamic>{'fields': <String>['phone']}), 'Firma güncellendi');
      expect(contractActionLabel('contract_vendor.updated', <String, dynamic>{'is_active': false}), 'Firma pasife alındı');
      expect(contractActionLabel('contract_vendor.updated', <String, dynamic>{'is_active': true}), 'Firma etkinleştirildi');
      expect(contractActionLabel('contract.created'), 'Sözleşme eklendi');
      expect(contractActionLabel('contract.updated'), 'Sözleşme güncellendi');
      expect(contractActionLabel('contract.updated', <String, dynamic>{'from': 'aktif', 'to': 'feshedildi'}), 'Sözleşme feshedildi');
      expect(contractActionLabel('contract.updated', <String, dynamic>{'from': 'feshedildi', 'to': 'aktif'}), 'Sözleşme yeniden etkinleştirildi');
      expect(contractActionLabel('contract.deleted'), isNull);
    });

    test('AuditLogEntry: başlık, hedef numarası ve modül adı', () {
      final entry = AuditLogEntry.fromJson(<String, dynamic>{
        'id': 1,
        'action': 'contract.updated',
        'target_type': 'contract',
        'target_id': '11',
        'details': <String, dynamic>{'fields': <String>['status'], 'from': 'aktif', 'to': 'feshedildi'},
      });
      expect(entry.actionLabel, 'Sözleşme feshedildi');
      expect(entry.targetLabel, contains('Sözleşme'));
      expect(entry.targetLabel, contains('11'));
      final vendor = AuditLogEntry.fromJson(<String, dynamic>{
        'id': 2,
        'action': 'contract_vendor.created',
        'target_type': 'contract_vendor',
        'target_id': '4',
      });
      expect(vendor.actionLabel, 'Firma eklendi');
      expect(vendor.targetLabel, contains('Firma'));
      final module = AuditLogEntry.fromJson(<String, dynamic>{
        'id': 3,
        'action': 'module.enabled',
        'target_type': 'module',
        'target_id': 'contracts',
      });
      expect(module.targetLabel, 'Firma ve Sözleşme Takibi');
    });
  });
}
