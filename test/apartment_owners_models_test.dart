// Çoklu malik (104): tüm malikler kayıtlı + TEK hesap muhatabı. Modeller (eski sunucu uyumu dahil), servis uçları (yol / yöntem / gövde),
// geçmiş etiketleri ve Dairem rol etiketi.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:site_kapi_kontrol/models/apartment_crm.dart';
import 'package:site_kapi_kontrol/models/apartment_management.dart';
import 'package:site_kapi_kontrol/models/history_item.dart';
import 'package:site_kapi_kontrol/models/residency_relation.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/apartment_management_api.dart';

import 'screens/people_fixtures.dart';

Map<String, dynamic> _resident(int id, int person, String name, {bool? holder, String relation = 'owner'}) => <String, dynamic>{
  'residency_id': id,
  'person_id': person,
  'full_name': name,
  'relation': relation,
  'move_in_date': '2024-03-05',
  'has_account': false,
  'is_account_holder': ?holder,
};

Map<String, dynamic> _card({List<Map<String, dynamic>>? owners, List<Map<String, dynamic>>? current, Map<String, dynamic>? owner, int? ownerCount}) =>
    <String, dynamic>{
      'id': 301,
      'label': 'A Blok - 5',
      'block_id': 1,
      'block_name': 'A Blok',
      'responsible_party': 'both',
      'owner': owner,
      'tenant': null,
      'resident_count': (current ?? const <Map<String, dynamic>>[]).length,
      'owners': ?owners,
      'owner_count': ?ownerCount,
      'current_residents': current ?? const <Map<String, dynamic>>[],
      'past_residents': const <Map<String, dynamic>>[],
    };

void main() {
  group('ApartmentOwner / ApartmentOwnersView', () {
    test('sunucu yanıtı: muhatap bayrağı, hesap, giriş tarihi; sınır ve ekleme izni', () {
      final view = ApartmentOwnersView.fromJson(<String, dynamic>{
        'apartment_id': 301,
        'label': 'A Blok - 5',
        'owner_limit': 3,
        'account_holder_residency_id': 11,
        'owners': <Map<String, dynamic>>[
          <String, dynamic>{'residency_id': 11, 'person_id': 1, 'full_name': 'Ayşe Yılmaz', 'is_account_holder': true, 'has_account': true, 'move_in_date': '2024-01-15'},
          <String, dynamic>{'residency_id': 12, 'person_id': 2, 'full_name': 'Ali Yılmaz', 'is_account_holder': false, 'has_account': false, 'move_in_date': null},
        ],
      });
      expect(view.apartmentId, 301);
      expect(view.owners, hasLength(2));
      expect(view.owners.first.isAccountHolder, isTrue);
      expect(view.owners.first.hasAccount, isTrue);
      expect(view.owners.first.moveInDate, DateTime(2024, 1, 15));
      expect(view.owners.last.isAccountHolder, isFalse);
      expect(view.accountHolderResidencyId, 11);
      expect(view.ownerLimit, 3);
      expect(view.canAddMore, isTrue);
      expect(ApartmentOwnersView.fromJson(<String, dynamic>{'apartment_id': 1, 'owner_limit': 2, 'owners': view.owners.map((o) => <String, dynamic>{'residency_id': o.residencyId, 'person_id': o.personId}).toList()}).canAddMore, isFalse);
    });

    test('alan yoksa güvenli varsayılan (eski / bozuk yanıt çökmez)', () {
      final view = ApartmentOwnersView.fromJson(<String, dynamic>{});
      expect(view.owners, isEmpty);
      expect(view.accountHolderResidencyId, isNull);
      expect(view.ownerLimit, 10);
      final owner = ApartmentOwner.fromJson(<String, dynamic>{'residency_id': '7', 'person_id': 8});
      expect(owner.residencyId, 7);
      expect(owner.fullName, '');
      expect(owner.isAccountHolder, isFalse);
    });
  });

  group('ApartmentDetail: malikler', () {
    test('yeni sunucu: owners listesi okunur, muhatap başta; ownerCount sunucudan', () {
      final detail = ApartmentDetail.fromJson(_card(
        owner: <String, dynamic>{'person_id': 1, 'full_name': 'Ayşe Yılmaz'},
        ownerCount: 2,
        owners: <Map<String, dynamic>>[
          <String, dynamic>{'residency_id': 11, 'person_id': 1, 'full_name': 'Ayşe Yılmaz', 'is_account_holder': true},
          <String, dynamic>{'residency_id': 12, 'person_id': 2, 'full_name': 'Ali Yılmaz', 'is_account_holder': false},
        ],
        current: <Map<String, dynamic>>[
          _resident(11, 1, 'Ayşe Yılmaz', holder: true),
          _resident(12, 2, 'Ali Yılmaz', holder: false),
        ],
      ));
      expect(detail.owners.map((o) => o.fullName), <String>['Ayşe Yılmaz', 'Ali Yılmaz']);
      expect(detail.ownerCount, 2);
      expect(detail.hasMultipleOwners, isTrue);
      expect(detail.owner?.personId, 1, reason: 'owner alanı (eski istemci) hesap muhatabı');
      expect(detail.currentResidents.first.isAccountHolder, isTrue);
      expect(detail.currentResidents.last.isAccountHolder, isFalse);
    });

    test('ESKİ sunucu (owners yok): güncel sakinlerden türetilir; tek malik muhatap sayılır, çoklu malikte owner alanı muhatap', () {
      final single = ApartmentDetail.fromJson(_card(
        owner: <String, dynamic>{'person_id': 1, 'full_name': 'Ayşe Yılmaz'},
        current: <Map<String, dynamic>>[_resident(11, 1, 'Ayşe Yılmaz'), _resident(21, 5, 'Veli', relation: 'tenant')],
      ));
      expect(single.owners, hasLength(1));
      expect(single.owners.single.isAccountHolder, isTrue);
      expect(single.ownerCount, 1);
      expect(single.hasMultipleOwners, isFalse);

      final multi = ApartmentDetail.fromJson(_card(
        owner: <String, dynamic>{'person_id': 2, 'full_name': 'Ali Yılmaz'},
        current: <Map<String, dynamic>>[_resident(11, 1, 'Ayşe Yılmaz'), _resident(12, 2, 'Ali Yılmaz')],
      ));
      expect(multi.owners.map((o) => o.fullName), <String>['Ali Yılmaz', 'Ayşe Yılmaz'], reason: 'owner ile aynı kişi muhatap, başa gelir');
      expect(multi.owners.first.isAccountHolder, isTrue);
      expect(multi.owners.last.isAccountHolder, isFalse);

      final empty = ApartmentDetail.fromJson(_card(current: <Map<String, dynamic>>[_resident(21, 5, 'Veli', relation: 'tenant')]));
      expect(empty.owners, isEmpty);
      expect(empty.ownerCount, 0);
    });

    test('özet: owner_count alanı yoksa owner doluysa 1, değilse 0', () {
      final withOwner = ApartmentSummary.fromJson(<String, dynamic>{
        'id': 1,
        'owner': <String, dynamic>{'person_id': 1, 'full_name': 'A'},
      });
      expect(withOwner.ownerCount, 1);
      expect(ApartmentSummary.fromJson(<String, dynamic>{'id': 1}).ownerCount, 0);
      expect(ApartmentSummary.fromJson(<String, dynamic>{'id': 1, 'owner_count': 3}).ownerCount, 3);
    });
  });

  group('etiketler', () {
    test('geçmiş: çoklu malik eylemleri Türkçe başlık alır', () {
      expect(peopleActionLabel('apartment.owner_added'), 'Malik eklendi');
      expect(peopleActionLabel('apartment.owner_removed'), 'Malik çıkarıldı');
      expect(peopleActionLabel('apartment.account_holder_changed'), 'Hesap muhatabı değişti');
    });

    test('Dairem: co_owner rolü "Ortak malik"; bilinmeyen rol Sakin', () {
      MyApartment of(String role) => MyApartment.fromJson(<String, dynamic>{'apartment_id': 1, 'site_code': 1, 'my_role': role});
      expect(of('co_owner').roleLabel, 'Ortak malik');
      expect(of('owner').roleLabel, 'Malik');
      expect(of('baska').roleLabel, 'Sakin');
    });

    test('ResidencyRelation değişmedi: malik hâlâ owner (eski istemci "Malik" gösterir)', () {
      expect(ResidencyRelation.fromApi('owner').label, 'Malik');
    });
  });

  group('ApartmentManagementService: çoklu malik uçları (gerçek HTTP katmanı, sahte istemci)', () {
    late List<http.Request> requests;
    late ApartmentManagementService service;

    Map<String, dynamic> viewJson() => <String, dynamic>{
      'apartment_id': 301,
      'label': 'A Blok - 5',
      'account_holder_residency_id': 11,
      'owner_limit': 10,
      'owners': <Map<String, dynamic>>[
        <String, dynamic>{'residency_id': 11, 'person_id': 1, 'full_name': 'Ayşe Yılmaz', 'is_account_holder': true},
      ],
    };

    setUp(() {
      requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        return http.Response(jsonEncode(viewJson()), 200, headers: <String, String>{'content-type': 'application/json'});
      });
      service = ApartmentManagementService(
        authService: PeopleFakeAuth(),
        api: ApartmentManagementApi(baseUrl: 'http://localhost', client: client),
      );
    });

    test('listele: GET .../owners, yetki başlığı', () async {
      final view = await service.apartmentOwners(11, 301);
      expect(view.owners.single.fullName, 'Ayşe Yılmaz');
      final r = requests.single;
      expect(r.method, 'GET');
      expect(r.url.path, '/manager/sites/11/apartments/301/owners');
      expect(r.headers['Authorization'], 'Bearer tok');
    });

    test('kayıtlı kişiyi ekle: POST, person_id; make_account_holder yalnız true iken', () async {
      await service.addApartmentOwner(11, 301, personId: 7);
      var body = jsonDecode(requests.last.body) as Map<String, dynamic>;
      expect(requests.last.method, 'POST');
      expect(requests.last.url.path, '/manager/sites/11/apartments/301/owners');
      expect(body, <String, dynamic>{'person_id': 7});
      await service.addApartmentOwner(11, 301, personId: 7, makeAccountHolder: true);
      body = jsonDecode(requests.last.body) as Map<String, dynamic>;
      expect(body, <String, dynamic>{'person_id': 7, 'make_account_holder': true});
    });

    test('yeni kişiyi ekle: person { full_name, boş olmayan telefon / e-posta }', () async {
      await service.addApartmentOwner(11, 301, fullName: 'Ali Veli', phone: '+905061234567', email: '');
      final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
      expect(body, <String, dynamic>{
        'person': <String, dynamic>{'full_name': 'Ali Veli', 'phone': '+905061234567'},
      });
    });

    test('muhatap değiştir: PUT .../owners/account-holder { residency_id }', () async {
      await service.setAccountHolder(11, 301, 12);
      final r = requests.single;
      expect(r.method, 'PUT');
      expect(r.url.path, '/manager/sites/11/apartments/301/owners/account-holder');
      expect(jsonDecode(r.body), <String, dynamic>{'residency_id': 12});
    });

    test('malik çıkar: POST .../owners/:id/remove; yeni muhatap yalnız verilirse gövdede', () async {
      await service.removeApartmentOwner(11, 301, 12);
      expect(requests.last.method, 'POST');
      expect(requests.last.url.path, '/manager/sites/11/apartments/301/owners/12/remove');
      expect(jsonDecode(requests.last.body), <String, dynamic>{});
      await service.removeApartmentOwner(11, 301, 11, newAccountHolderResidencyId: 12);
      expect(jsonDecode(requests.last.body), <String, dynamic>{'new_account_holder_residency_id': 12});
    });

    test('sunucu reddi Türkçe ApiException olur (kod ve yük korunur); mutasyon yeniden denenmez', () async {
      var calls = 0;
      final failing = ApartmentManagementService(
        authService: PeopleFakeAuth(),
        api: ApartmentManagementApi(
          baseUrl: 'http://localhost',
          client: MockClient((request) async {
            calls++;
            return http.Response(
              jsonEncode(<String, dynamic>{
                'error': 'Bu kişi hesap muhatabı. Çıkarmadan önce yeni hesap muhatabını seçin.',
                'code': 'ACCOUNT_HOLDER_REQUIRED',
                'owners': <Map<String, dynamic>>[<String, dynamic>{'residency_id': 11}],
              }),
              409,
              headers: <String, String>{'content-type': 'application/json'},
            );
          }),
        ),
      );
      await expectLater(
        failing.removeApartmentOwner(11, 301, 11),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', 'ACCOUNT_HOLDER_REQUIRED')
              .having((e) => e.statusCode, 'status', 409)
              .having((e) => e.message, 'message', contains('hesap muhatabı'))
              .having((e) => (e.payload?['owners'] as List).length, 'owners', 1),
        ),
      );
      expect(calls, 1, reason: 'yeniden deneme yok');
    });
  });
}
