// Platform Faz 2a (Kişi ve Daire Kayıtları): modeller ve giriş yardımcıları.
//
// Alan yok / bozuk ise güvenli varsayılan; DATE alanı saat dilimi kaymasından etkilenmez; telefon,
// tarih ve plaka girişi sunucu kurallarıyla aynıdır.
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/apartment_crm.dart';
import 'package:site_kapi_kontrol/models/audit_log.dart';
import 'package:site_kapi_kontrol/models/history_item.dart';
import 'package:site_kapi_kontrol/models/person_record.dart';
import 'package:site_kapi_kontrol/models/residency_relation.dart';
import 'package:site_kapi_kontrol/models/vehicle_record.dart';
import 'package:site_kapi_kontrol/ui/dialogs/vehicle_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/date_input.dart';
import 'package:site_kapi_kontrol/ui/helpers/phone_input.dart';
import 'package:site_kapi_kontrol/ui/widgets/crm_parts.dart';

void main() {
  group('ResidencyRelation / ResponsibleParty', () {
    test('Türkçe etiketler ve sunucu değerleri', () {
      expect(<String>[for (final r in ResidencyRelation.values) r.label], <String>[
        'Malik',
        'Kiracı',
        'Aile Üyesi',
        'Sakin',
      ]);
      expect(<String>[for (final r in ResidencyRelation.values) r.apiValue], <String>[
        'owner',
        'tenant',
        'family_member',
        'resident',
      ]);
      expect(<String>[for (final r in ResponsibleParty.values) r.label], <String>[
        'Malik',
        'Kiracı',
        'İkisi',
      ]);
    });

    test('yalnız malik ve kiracı tekil (RELATION_TAKEN) ilişkilerdir', () {
      expect(ResidencyRelation.owner.isExclusive, isTrue);
      expect(ResidencyRelation.tenant.isExclusive, isTrue);
      expect(ResidencyRelation.familyMember.isExclusive, isFalse);
      expect(ResidencyRelation.resident.isExclusive, isFalse);
    });

    test('bilinmeyen / eksik değer güvenli varsayılana düşer', () {
      expect(ResidencyRelation.fromApi('bilinmeyen'), ResidencyRelation.resident);
      expect(ResidencyRelation.fromApi(null), ResidencyRelation.resident);
      expect(ResidencyRelation.fromApi(42), ResidencyRelation.resident);
      expect(ResidencyRelation.fromApi(' OWNER '), ResidencyRelation.owner);
      expect(ResidencyRelation.tryParse('x'), isNull);
      expect(ResponsibleParty.fromApi('x'), ResponsibleParty.both);
      expect(ResponsibleParty.fromApi(null), ResponsibleParty.both);
      expect(ResponsibleParty.fromApi('tenant'), ResponsibleParty.tenant);
    });
  });

  group('ayrıştırma yardımcıları', () {
    test('crmDate: takvim günü olduğu gibi okunur (saat dilimi kayması yok)', () {
      expect(crmDate('2024-03-05'), DateTime(2024, 3, 5));
      expect(crmDate('2024-03-05T21:00:00.000Z'), DateTime(2024, 3, 5),
          reason: 'saat kısmı yok sayılır: bir gün kaymaz');
      expect(crmDate('bozuk'), isNull);
      expect(crmDate(null), isNull);
      expect(crmDate('2024-13-40'), isNull);
    });

    test('crmDateParam: YYYY-AA-GG', () {
      expect(crmDateParam(DateTime(2024, 3, 5)), '2024-03-05');
      expect(crmDateParam(DateTime(999, 1, 2)), '0999-01-02');
    });

    test('sayılar metin ya da sayı gelebilir; bozuksa varsayılan', () {
      expect(crmInt('12'), 12);
      expect(crmInt(null), 0);
      expect(crmInt('x', 7), 7);
      expect(crmIntOrNull('x'), isNull);
      expect(crmDoubleOrNull('120.50'), 120.5);
      expect(crmDoubleOrNull('120,5'), 120.5);
      expect(crmDoubleOrNull(null), isNull);
      expect(crmText('   '), isNull);
      expect(crmText(' a '), 'a');
    });

    test('crmApartmentTitle: blok adı etikette varsa tekrar edilmez', () {
      expect(crmApartmentTitle('A Blok', 'A Blok - 5'), 'A Blok - 5');
      expect(crmApartmentTitle('A Blok', '5'), 'A Blok / 5');
      expect(crmApartmentTitle(null, '5'), '5');
      expect(crmApartmentTitle('', ''), '-');
      expect(crmApartmentTitle('A Blok', ''), 'A Blok');
    });
  });

  group('kişi modelleri', () {
    test('PersonSummary: eksik alanlarda güvenli varsayılan', () {
      final p = PersonSummary.fromJson(const <String, dynamic>{'id': 4});
      expect(p.id, 4);
      expect(p.fullName, '');
      expect(p.phone, isNull);
      expect(p.hasAccount, isFalse);
      expect(p.isActive, isTrue, reason: 'alan yoksa aktif sayılır');
      expect(p.relations, isEmpty);
      expect(p.apartments, isEmpty);
      expect(p.vehicleCount, 0);
    });

    test('PersonSummary: ilişkiler tekrarsız, bilinmeyen değer atılır, daire etiketi ayrışır', () {
      final p = PersonSummary.fromJson(const <String, dynamic>{
        'id': 1,
        'full_name': 'Ayşe Yılmaz',
        'phone': '+905551112233',
        'has_account': true,
        'is_active': false,
        'relations': <String>['owner', 'owner', 'tenant', 'uzaylı'],
        'apartments': <Map<String, dynamic>>[
          <String, dynamic>{
            'apartment_id': 301,
            'label': 'A Blok - 5',
            'block_name': 'A Blok',
            'relation': 'owner',
          },
        ],
        'vehicle_count': '2',
      });
      expect(p.relations, <ResidencyRelation>[ResidencyRelation.owner, ResidencyRelation.tenant]);
      expect(p.hasAccount, isTrue);
      expect(p.isActive, isFalse);
      expect(p.apartments.single.fullLabel, 'A Blok - 5');
      expect(p.apartments.single.relation, ResidencyRelation.owner);
      expect(p.vehicleCount, 2);
    });

    test('PersonDetail: geçmiş dahil ilişkiler güncel / eski olarak ayrılır; araç sayısı araç listesinden', () {
      final d = PersonDetail.fromJson(const <String, dynamic>{
        'id': 2,
        'full_name': 'Mehmet Demir',
        'note': 'Not',
        'created_at': '2026-09-01T10:00:00Z',
        'user_code': 702,
        'residencies': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 1,
            'apartment_id': 302,
            'label': 'A Blok - 6',
            'block_name': 'A Blok',
            'relation': 'tenant',
            'is_current': true,
            'move_in_date': '2024-03-05',
            'move_out_date': null,
          },
          <String, dynamic>{
            'id': 2,
            'apartment_id': 303,
            'label': 'B Blok - 2',
            'relation': 'tenant',
            'is_current': false,
            'move_in_date': '2022-01-01',
            'move_out_date': '2024-02-29',
          },
        ],
        'vehicles': <Map<String, dynamic>>[
          <String, dynamic>{'id': 9, 'plate': '34ABC123', 'plate_display': '34 ABC 123'},
        ],
      });
      expect(d.currentResidencies, hasLength(1));
      expect(d.pastResidencies.single.moveOutDate, DateTime(2024, 2, 29));
      expect(d.currentResidencies.single.moveInDate, DateTime(2024, 3, 5));
      expect(d.vehicles.single.displayPlate, '34 ABC 123');
      expect(d.vehicleCount, 1);
      expect(d.userCode, 702);
      expect(d.createdAt, isNotNull);
    });

    test('PersonDetail: user_code yoksa null (yönetici dışı yanıt)', () {
      final d = PersonDetail.fromJson(const <String, dynamic>{'id': 3});
      expect(d.userCode, isNull);
      expect(d.residencies, isEmpty);
      expect(d.vehicles, isEmpty);
      expect(d.note, isNull);
    });

    test('PersonPage: items yoksa boş, total yoksa kayıt sayısı', () {
      expect(PersonPage.fromJson(const <String, dynamic>{}).items, isEmpty);
      final page = PersonPage.fromJson(const <String, dynamic>{
        'items': <Map<String, dynamic>>[
          <String, dynamic>{'id': 1},
          <String, dynamic>{'id': 2},
        ],
      });
      expect(page.total, 2);
      expect(PersonPage.fromJson(const <String, dynamic>{'items': <dynamic>[], 'total': 40}).total, 40);
    });
  });

  group('daire modelleri', () {
    test('ApartmentSummary: alanlar, arsa payı ve malik / kiracı', () {
      final a = ApartmentSummary.fromJson(const <String, dynamic>{
        'id': 301,
        'label': 'A Blok - 5',
        'block_id': 1,
        'block_name': 'A Blok',
        'floor': 2,
        'category': '3+1',
        'gross_area_m2': '120.50',
        'net_area_m2': 100,
        'land_share': <String, dynamic>{'numerator': 35, 'denominator': 1000},
        'responsible_party': 'tenant',
        'owner': <String, dynamic>{'person_id': 1, 'full_name': 'Ayşe Yılmaz'},
        'tenant': null,
        'resident_count': 2,
      });
      expect(a.fullLabel, 'A Blok - 5');
      expect(a.floor, 2);
      expect(a.grossAreaM2, 120.5);
      expect(a.netAreaM2, 100.0);
      expect(a.landShare, const LandShare(35, 1000));
      expect(a.landShare!.label, '35/1000');
      expect(a.responsibleParty, ResponsibleParty.tenant);
      expect(a.owner!.fullName, 'Ayşe Yılmaz');
      expect(a.tenant, isNull);
      expect(a.residentCount, 2);
    });

    test('ApartmentSummary: eksik alanlarda güvenli varsayılan (borç muhatabı "İkisi")', () {
      final a = ApartmentSummary.fromJson(const <String, dynamic>{'id': 1});
      expect(a.floor, isNull);
      expect(a.landShare, isNull);
      expect(a.responsibleParty, ResponsibleParty.both);
      expect(a.owner, isNull);
      expect(a.residentCount, 0);
    });

    test('LandShare: bozuk kesir (payda 0, eksik alan) null olur; geçerlilik kuralı', () {
      expect(LandShare.fromJson(const <String, dynamic>{'numerator': 1, 'denominator': 0}), isNull);
      expect(LandShare.fromJson(const <String, dynamic>{'numerator': 1}), isNull);
      expect(LandShare.fromJson('x'), isNull);
      expect(LandShare.isValid(35, 1000), isTrue);
      expect(LandShare.isValid(0, 1), isTrue);
      expect(LandShare.isValid(1001, 1000), isFalse, reason: 'pay paydayı aşamaz');
      expect(LandShare.isValid(1, 0), isFalse);
      expect(LandShare.isValid(null, 5), isFalse);
      expect(LandShare.isValid(-1, 5), isFalse);
    });

    test('ApartmentDetail: güncel ve geçmiş sakinler; sakin sayısı yoksa güncel sakinlerden', () {
      final d = ApartmentDetail.fromJson(const <String, dynamic>{
        'id': 301,
        'label': 'A Blok - 5',
        'current_residents': <Map<String, dynamic>>[
          <String, dynamic>{
            'residency_id': 1,
            'person_id': 1,
            'full_name': 'Ayşe Yılmaz',
            'relation': 'owner',
            'move_in_date': '2024-03-05',
            'has_account': true,
          },
        ],
        'past_residents': <Map<String, dynamic>>[
          <String, dynamic>{
            'residency_id': 2,
            'person_id': 3,
            'full_name': 'Zeynep Kaya',
            'relation': 'family_member',
            'move_in_date': '2023-01-01',
            'move_out_date': '2025-01-31',
          },
        ],
      });
      expect(d.currentResidents.single.relation, ResidencyRelation.owner);
      expect(d.currentResidents.single.hasAccount, isTrue);
      expect(d.pastResidents.single.moveOutDate, DateTime(2025, 1, 31));
      expect(d.residentCount, 1);
    });

    test('MyRecord: etiket, ilişki, giriş tarihi ve araçlar; kayıt yoksa boş liste', () {
      final r = MyRecord.fromJson(const <String, dynamic>{
        'site_code': 11,
        'site_name': 'Gül Sitesi',
        'apartment_id': 301,
        'label': 'A Blok - 5',
        'block_name': 'A Blok',
        'relation': 'tenant',
        'move_in_date': '2024-03-05',
        'vehicles': <Map<String, dynamic>>[
          <String, dynamic>{'id': 1, 'plate': '34ABC123'},
        ],
      });
      expect(r.fullLabel, 'A Blok - 5');
      expect(r.relation, ResidencyRelation.tenant);
      expect(r.moveInDate, DateTime(2024, 3, 5));
      expect(r.vehicles.single.displayPlate, '34ABC123',
          reason: 'görüntüleme biçimi yoksa normalize plaka');
      expect(MyRecord.listFrom(null), isEmpty);
      expect(MyRecord.listFrom('x'), isEmpty);
    });
  });

  group('araç ve geçmiş', () {
    test('VehicleRecord: eksik alanlar güvenli; plaka görüntüleme biçimi', () {
      final v = VehicleRecord.fromJson(const <String, dynamic>{
        'id': 1,
        'plate': '34ABC123',
        'plate_display': '34 ABC 123',
        'person_name': 'Ayşe',
      });
      expect(v.displayPlate, '34 ABC 123');
      expect(v.isActive, isTrue);
      expect(v.note, isNull);
      expect(VehiclePage.fromJson(const <String, dynamic>{}).items, isEmpty);
      expect(VehicleRecord.listFrom(<dynamic>['x', <String, dynamic>{'id': 2, 'plate': 'A'}]),
          hasLength(1), reason: 'Map olmayan öğe atılır');
    });

    test('HistoryItem: eylem etiketi, değişen alanlar ve bilinmeyen eylem ham adıyla', () {
      final item = HistoryItem.fromJson(const <String, dynamic>{
        'id': 7,
        'action': 'person.updated',
        'created_at': '2026-10-15T09:30:00Z',
        'actor_name': 'Site Yöneticisi',
        'actor_role': 'site_manager',
        'target_type': 'person',
        'target_id': '1',
        'details': <String, dynamic>{
          'changes': <Map<String, dynamic>>[
            <String, dynamic>{'field': 'phone', 'from': null, 'to': '+905324445566'},
            <String, dynamic>{'field': 'ozel_alan', 'from': 'a', 'to': 'b'},
            <String, dynamic>{'field': ''},
          ],
        },
      });
      expect(item.actionLabel, 'Kişi bilgisi güncellendi');
      expect(item.changes, hasLength(2), reason: 'alan adsız satır atılır');
      expect(item.changes.first.summary, 'Telefon: - → +905324445566');
      expect(item.changes.first.hasValues, isTrue);
      expect(item.changes.last.fieldLabel, 'ozel_alan', reason: 'bilinmeyen alan ham adıyla');
      expect(HistoryItem.fromJson(const <String, dynamic>{'id': 1, 'action': 'x.y'}).actionLabel, 'x.y');
    });

    test('peopleActionLabel: tüm Faz 2a eylemleri Türkçe; denetim kaydı da aynı etiketi kullanır', () {
      const actions = <String, String>{
        'person.created': 'Kişi eklendi',
        'person.updated': 'Kişi bilgisi güncellendi',
        'person.deactivated': 'Kişi pasifleştirildi',
        'residency.added': 'İlişki eklendi',
        'residency.updated': 'İlişki güncellendi',
        'residency.ended': 'Taşındı',
        'apartment.updated': 'Daire bilgisi güncellendi',
        'vehicle.added': 'Araç eklendi',
        'vehicle.removed': 'Araç kaldırıldı',
      };
      actions.forEach((action, label) {
        expect(peopleActionLabel(action), label, reason: action);
        expect(
          AuditLogEntry(id: 1, action: action).actionLabel,
          label,
          reason: 'AuditLogEntry.actionLabel $action',
        );
      });
      expect(peopleActionLabel('module.enabled'), isNull);
      final entry = AuditLogEntry(id: 1, action: 'vehicle.added', targetType: 'vehicle', targetId: '9');
      expect(entry.targetLabel, 'Araç #9');
      expect(AuditLogEntry(id: 1, action: 'person.created', targetType: 'person', targetId: '3').targetLabel,
          'Kişi #3');
      expect(AuditLogEntry(id: 1, action: 'apartment.updated', targetType: 'apartment').targetLabel, isNull);
    });

    test('HistoryPage: sonraki sayfa imleci', () {
      final page = HistoryPage.fromJson(const <String, dynamic>{
        'items': <Map<String, dynamic>>[
          <String, dynamic>{'id': 9, 'action': 'person.created'},
        ],
        'next_before_id': 9,
      });
      expect(page.hasMore, isTrue);
      expect(page.nextBeforeId, 9);
      expect(HistoryPage.fromJson(const <String, dynamic>{'items': <dynamic>[]}).hasMore, isFalse);
    });
  });

  group('telefon girişi (+90, 3-3-2-2)', () {
    test('formatPhoneField: ön ek hazır, haneler 3-3-2-2 gruplanır', () {
      expect(formatPhoneField(null), '+90 ');
      expect(formatPhoneField(''), '+90 ');
      expect(formatPhoneField('5'), '+90 5');
      expect(formatPhoneField('555'), '+90 555');
      expect(formatPhoneField('5551'), '+90 555 1');
      expect(formatPhoneField('555123'), '+90 555 123');
      expect(formatPhoneField('55512345'), '+90 555 123 45');
      expect(formatPhoneField('5551234567'), '+90 555 123 45 67');
    });

    test('biçim farkları aynı numarayı verir (0555, 90555, +90 555, parantezli)', () {
      for (final input in const <String>[
        '05551234567',
        '905551234567',
        '+905551234567',
        '+90 555 123 45 67',
        '0 (555) 123-45-67',
        '5551234567',
      ]) {
        expect(phoneToApi(input), '+905551234567', reason: input);
        expect(formatPhoneField(input), '+90 555 123 45 67', reason: input);
      }
    });

    test('fazla hane kesilir; yazarken öneki silmek öneki geri getirir', () {
      expect(formatPhoneField('555123456789'), '+90 555 123 45 67');
      expect(formatPhoneField('+90'), '+90 ');
      expect(formatPhoneField('+90 55'), '+90 55');
    });

    test('phoneToApi: boş alan null; validatePhoneField', () {
      expect(phoneToApi('+90 '), isNull);
      expect(phoneToApi(null), isNull);
      expect(validatePhoneField('+90 '), isNull, reason: 'telefon isteğe bağlı');
      expect(validatePhoneField(''), isNull);
      expect(validatePhoneField('+90 555 123'), isNotNull, reason: 'eksik hane');
      expect(validatePhoneField('+90 055 123 45 67'), isNotNull, reason: '0 ile başlayamaz');
      expect(validatePhoneField('+90 555 123 45 67'), isNull);
    });

    test('formatPhoneDisplay: ayrıştırılabilirse gruplar, değilse olduğu gibi', () {
      expect(formatPhoneDisplay('+905551234567'), '+90 555 123 45 67');
      expect(formatPhoneDisplay('0212 555 1'), '0212 555 1');
      expect(formatPhoneDisplay(null), '');
    });

    test('PhoneInputFormatter: yazarken biçimler', () {
      const f = PhoneInputFormatter();
      var v = f.formatEditUpdate(TextEditingValue.empty, const TextEditingValue(text: '5'));
      expect(v.text, '+90 5');
      v = f.formatEditUpdate(v, const TextEditingValue(text: '+90 5551'));
      expect(v.text, '+90 555 1');
      expect(v.selection.baseOffset, v.text.length);
    });
  });

  group('tarih girişi (GG.AA.YYYY)', () {
    test('parseDateField: gerçek tarih; taşan gün ve sınır dışı yıl reddedilir', () {
      expect(parseDateField('05.03.2024'), DateTime(2024, 3, 5));
      expect(parseDateField('29.02.2024'), DateTime(2024, 2, 29));
      expect(parseDateField('29.02.2023'), isNull);
      expect(parseDateField('31.04.2024'), isNull);
      expect(parseDateField('00.01.2024'), isNull);
      expect(parseDateField('01.13.2024'), isNull);
      expect(parseDateField('01.01.1899'), isNull);
      expect(parseDateField('01.01.2101'), isNull);
      expect(parseDateField('1.1.2024'), isNull);
      expect(parseDateField(''), isNull);
      expect(parseDateField(null), isNull);
    });

    test('validateDateField: boş serbest, bozuk hata', () {
      expect(validateDateField(''), isNull);
      expect(validateDateField('  '), isNull);
      expect(validateDateField('05.03.2024'), isNull);
      expect(validateDateField('31.02.2024'), isNotNull);
      expect(validateDateField('abc'), isNotNull);
    });

    test('formatCrmDate / formatDateField', () {
      expect(formatCrmDate(DateTime(2024, 3, 5)), '05.03.2024');
      expect(formatCrmDate(null), '-');
      expect(formatDateField(null), '');
    });

    test('DateInputFormatter: rakamlardan noktalı biçim, en çok 8 rakam', () {
      const f = DateInputFormatter();
      expect(f.formatEditUpdate(TextEditingValue.empty, const TextEditingValue(text: '0')).text, '0');
      expect(f.formatEditUpdate(TextEditingValue.empty, const TextEditingValue(text: '050')).text, '05.0');
      expect(f.formatEditUpdate(TextEditingValue.empty, const TextEditingValue(text: '05032024')).text,
          '05.03.2024');
      expect(f.formatEditUpdate(TextEditingValue.empty, const TextEditingValue(text: '050320249999')).text,
          '05.03.2024');
      expect(f.formatEditUpdate(TextEditingValue.empty, const TextEditingValue(text: '05.03.2024')).text,
          '05.03.2024');
      expect(f.formatEditUpdate(TextEditingValue.empty, const TextEditingValue(text: '12.')).text, '12');
    });
  });

  group('plaka girişi', () {
    test('normalizePlateInput: sunucu kuralı (A-Z0-9, 5-10 karakter, boşluk / tire atılır)', () {
      expect(normalizePlateInput('34 ABC 123'), '34ABC123');
      expect(normalizePlateInput('34-abc-123'), '34ABC123');
      expect(normalizePlateInput('06 XY 12'), '06XY12');
      expect(normalizePlateInput('1234'), isNull, reason: '5 karakterden kısa');
      expect(normalizePlateInput('34ABC1234567'), isNull, reason: '10 karakterden uzun');
      expect(normalizePlateInput('34 ÇAB 123'), isNull, reason: 'Türkçe harf geçersiz');
      expect(normalizePlateInput(''), isNull);
      expect(normalizePlateInput(null), isNull);
    });
  });

  group('sunucu düzeltmeleri (hesap türü, giriş bilgisi, geçmiş, kayıtlarım)', () {
    test('account_kind: internal yalnız hesabı olan kişide dahili sayılır; alan yoksa null (eski sunucu)', () {
      final internal = PersonSummary.fromJson(const <String, dynamic>{
        'id': 1,
        'has_account': true,
        'account_kind': 'internal',
      });
      expect(internal.accountKind, 'internal');
      expect(internal.isInternalAccount, isTrue);

      final registered = PersonSummary.fromJson(const <String, dynamic>{
        'id': 2,
        'has_account': true,
        'account_kind': 'registered',
      });
      expect(registered.isInternalAccount, isFalse);

      final legacy = PersonSummary.fromJson(const <String, dynamic>{'id': 3, 'has_account': true});
      expect(legacy.accountKind, isNull);
      expect(legacy.isInternalAccount, isFalse, reason: 'alan yoksa tüm kimlik alanları salt okunur');

      final none = PersonSummary.fromJson(const <String, dynamic>{
        'id': 4,
        'has_account': false,
        'account_kind': 'internal',
      });
      expect(none.isInternalAccount, isFalse, reason: 'hesap yoksa dahili sayılmaz');

      final detail = PersonDetail.fromJson(const <String, dynamic>{
        'id': 5,
        'has_account': true,
        'account_kind': 'internal',
      });
      expect(detail.isInternalAccount, isTrue, reason: 'ayrıntı da hesap türünü taşır');
    });

    test('credentials_sent: true / false / alan yok (null)', () {
      expect(PersonDetail.fromJson(const <String, dynamic>{'id': 1, 'credentials_sent': true}).credentialsSent,
          isTrue);
      expect(PersonDetail.fromJson(const <String, dynamic>{'id': 1, 'credentials_sent': false}).credentialsSent,
          isFalse);
      expect(PersonDetail.fromJson(const <String, dynamic>{'id': 1}).credentialsSent, isNull);
      expect(PersonDetail.fromJson(const <String, dynamic>{'id': 1, 'credentials_sent': null}).credentialsSent,
          isNull);
    });

    test('geçmiş: değer yoksa "Alan güncellendi", değer varsa "Alan: eski → yeni"', () {
      final changes = FieldChange.listFrom(const <dynamic>[
        <String, dynamic>{'field': 'phone', 'changed': true},
        <String, dynamic>{'field': 'email', 'changed': true},
        <String, dynamic>{'field': 'note', 'changed': true},
        <String, dynamic>{'field': 'full_name', 'from': 'Ayşe', 'to': 'Ayşe Yıldız'},
        <String, dynamic>{'field': 'floor', 'from': 2, 'to': 3},
        <String, dynamic>{'field': 'category', 'from': null, 'to': '3+1'},
      ]);
      expect(changes.map((c) => c.summary).toList(), <String>[
        'Telefon güncellendi',
        'E-posta güncellendi',
        'Not güncellendi',
        'Ad Soyad: Ayşe → Ayşe Yıldız',
        'Kat: 2 → 3',
        'Kategori: - → 3+1',
      ]);
      expect(changes.first.hasValues, isFalse);
    });

    test('geçmiş: sistem kaydı (actor_role system / details.auto) otomatik sayılır', () {
      final byRole = HistoryItem.fromJson(const <String, dynamic>{
        'id': 1,
        'action': 'person.deactivated',
        'actor_name': 'Sistem',
        'actor_role': 'system',
      });
      expect(byRole.isAutomatic, isTrue);
      final byFlag = HistoryItem.fromJson(const <String, dynamic>{
        'id': 2,
        'action': 'person.deactivated',
        'actor_role': 'site_manager',
        'details': <String, dynamic>{'auto': true},
      });
      expect(byFlag.isAutomatic, isTrue);
      final manual = HistoryItem.fromJson(const <String, dynamic>{
        'id': 3,
        'action': 'person.updated',
        'actor_role': 'site_manager',
      });
      expect(manual.isAutomatic, isFalse);
    });

    test('kayıtlarım: araç notu yok sayılır; plaka kalır', () {
      final record = MyRecord.fromJson(const <String, dynamic>{
        'apartment_id': 1,
        'label': 'A Blok - 5',
        'vehicles': <Map<String, dynamic>>[
          <String, dynamic>{'id': 1, 'plate': '34ABC123', 'note': 'gizli not'},
        ],
      });
      expect(record.vehicles.single.note, isNull);
      expect(record.vehicles.single.plate, '34ABC123');
      // Yönetici araç listesi notu korur.
      expect(VehicleRecord.fromJson(const <String, dynamic>{'id': 1, 'plate': 'X', 'note': 'n'}).note, 'n');
    });

    test('silinmiş hesap sentineli olduğu gibi gösterilir', () {
      final p = PersonSummary.fromJson(const <String, dynamic>{'id': 9, 'full_name': 'Silinmiş hesap'});
      expect(p.fullName, 'Silinmiş hesap');
    });
  });

  test('formatNumber: tam sayı yalın, küsurat virgülle', () {
    expect(formatNumber(120), '120');
    expect(formatNumber(120.5), '120,5');
    expect(formatNumber(99.25), '99,25');
    expect(formatNumber(0.5), '0,5');
  });
}
