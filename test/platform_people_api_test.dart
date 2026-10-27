// Platform Faz 2a (Kişi ve Daire Kayıtları): AuthApi / AuthService uçları (docs/PLATFORM_KISILER.md).
//
// MockClient ile: uç yolları, HTTP yöntemleri, gövdeler, sorgu parametreleri, Bearer başlığı, hata
// kodu -> Türkçe mesaj eşlemeleri. Sunucu gerekmez.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:site_kapi_kontrol/models/residency_relation.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

class _Recorder {
  final List<http.Request> requests = <http.Request>[];

  http.Request get last => requests.last;

  Map<String, dynamic> get lastBody => jsonDecode(last.body) as Map<String, dynamic>;
}

AuthApi _api(_Recorder rec, FutureOr<http.Response> Function(http.Request request) handler) {
  return AuthApi(
    baseUrl: 'https://api.example.test',
    client: MockClient((request) async {
      rec.requests.add(request);
      return handler(request);
    }),
    retryDelay: Duration.zero,
  );
}

Map<String, dynamic> _personBody({int id = 9}) => <String, dynamic>{
  'id': id,
  'full_name': 'Ayşe Yılmaz',
  'phone': '+905551112233',
  'email': 'ayse@example.com',
  'has_account': false,
  'is_active': true,
  'relations': <String>['owner'],
  'apartments': <Map<String, dynamic>>[
    <String, dynamic>{
      'apartment_id': 301,
      'label': 'A Blok - 5',
      'block_name': 'A Blok',
      'relation': 'owner',
    },
  ],
  'vehicle_count': 1,
  'note': null,
  'residencies': <Map<String, dynamic>>[],
  'vehicles': <Map<String, dynamic>>[],
};

Map<String, dynamic> _apartmentBody() => <String, dynamic>{
  'id': 301,
  'label': 'A Blok - 5',
  'block_id': 1,
  'block_name': 'A Blok',
  'floor': 2,
  'land_share': <String, dynamic>{'numerator': 35, 'denominator': 1000},
  'responsible_party': 'both',
  'owner': null,
  'tenant': null,
  'resident_count': 0,
  'current_residents': <dynamic>[],
  'past_residents': <dynamic>[],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AuthApi: kişiler', () {
    test('listPeople: GET /manager/sites/:siteCode/people, süzgeçler sorguya yazılır, boş arama atlanır', () async {
      final rec = _Recorder();
      final api = _api(rec, (r) => _json({
        'items': <Map<String, dynamic>>[_personBody()],
        'total': 41,
      }));

      final page = await api.listPeople(
        token: 'tok',
        siteCode: 7,
        query: '  Ayşe ',
        relation: ResidencyRelation.familyMember,
        status: 'all',
        apartmentId: 301,
        limit: 20,
        offset: 40,
      );
      expect(rec.last.method, 'GET');
      expect(rec.last.url.path, '/manager/sites/7/people');
      expect(rec.last.headers['Authorization'], 'Bearer tok');
      expect(rec.last.url.queryParameters, <String, String>{
        'q': 'Ayşe',
        'relation': 'family_member',
        'status': 'all',
        'apartment_id': '301',
        'limit': '20',
        'offset': '40',
      });
      expect(page.total, 41);
      expect(page.items.single.fullName, 'Ayşe Yılmaz');

      await api.listPeople(token: 'tok', siteCode: 7, query: '   ');
      expect(rec.last.url.queryParameters, <String, String>{'limit': '50', 'offset': '0'});
    });

    test('getPerson: GET /people/:id, PersonDetail ayrışır', () async {
      final rec = _Recorder();
      final api = _api(rec, (r) => _json(_personBody(id: 12)));
      final person = await api.getPerson(token: 'tok', siteCode: 7, personId: 12);
      expect(rec.last.method, 'GET');
      expect(rec.last.url.path, '/manager/sites/7/people/12');
      expect(person.id, 12);
    });

    test('createPerson: POST, yalnız dolu alanlar gider; ilişki ve tarih yalnız daire varken', () async {
      final rec = _Recorder();
      final api = _api(rec, (r) => _json(_personBody(), 201));

      await api.createPerson(
        token: 'tok',
        siteCode: 7,
        fullName: '  Ayşe Yılmaz ',
        phone: '+905551112233',
        email: ' ayse@example.com ',
        note: ' not ',
        apartmentId: 301,
        relation: ResidencyRelation.owner,
        moveInDate: DateTime(2024, 3, 5),
      );
      expect(rec.last.method, 'POST');
      expect(rec.last.url.path, '/manager/sites/7/people');
      expect(rec.lastBody, <String, dynamic>{
        'full_name': 'Ayşe Yılmaz',
        'phone': '+905551112233',
        'email': 'ayse@example.com',
        'note': 'not',
        'apartment_id': 301,
        'relation': 'owner',
        'move_in_date': '2024-03-05',
      });

      await api.createPerson(
        token: 'tok',
        siteCode: 7,
        fullName: 'Ali',
        phone: '',
        email: '  ',
        relation: ResidencyRelation.tenant,
        moveInDate: DateTime(2024, 3, 5),
      );
      expect(rec.lastBody, <String, dynamic>{'full_name': 'Ali'},
          reason: 'daire yokken ilişki ve tarih gönderilmez, boş alanlar atlanır');
    });

    test('createPerson: 201 dışındaki yanıt hata olur', () async {
      final api = _api(_Recorder(), (r) => _json(_personBody(), 200));
      await expectLater(
        api.createPerson(token: 'tok', siteCode: 7, fullName: 'Ali'),
        throwsA(isA<ApiException>()),
      );
    });

    test('updatePerson: PATCH, yalnız verilen alanlar; null temizlemek içindir', () async {
      final rec = _Recorder();
      final api = _api(rec, (r) => _json(_personBody()));
      await api.updatePerson(
        token: 'tok',
        siteCode: 7,
        personId: 9,
        fields: <String, Object?>{'note': null, 'is_active': false, 'phone': '+905324445566'},
      );
      expect(rec.last.method, 'PATCH');
      expect(rec.last.url.path, '/manager/sites/7/people/9');
      expect(rec.lastBody, <String, dynamic>{
        'note': null,
        'is_active': false,
        'phone': '+905324445566',
      });
    });
  });

  group('AuthApi: ilişkiler', () {
    test('addResidency: POST /people/:id/residencies (201), tarih isteğe bağlı', () async {
      final rec = _Recorder();
      final api = _api(rec, (r) => _json(_personBody(), 201));
      await api.addResidency(
        token: 'tok',
        siteCode: 7,
        personId: 9,
        apartmentId: 302,
        relation: ResidencyRelation.tenant,
        moveInDate: DateTime(2025, 1, 2),
      );
      expect(rec.last.method, 'POST');
      expect(rec.last.url.path, '/manager/sites/7/people/9/residencies');
      expect(rec.lastBody, <String, dynamic>{
        'apartment_id': 302,
        'relation': 'tenant',
        'move_in_date': '2025-01-02',
      });

      await api.addResidency(
        token: 'tok',
        siteCode: 7,
        personId: 9,
        apartmentId: 302,
        relation: ResidencyRelation.resident,
      );
      expect(rec.lastBody, <String, dynamic>{'apartment_id': 302, 'relation': 'resident'});
    });

    test('updateResidency: PATCH /residencies/:id; endResidency: POST /residencies/:id/end', () async {
      final rec = _Recorder();
      final api = _api(rec, (r) => _json(_personBody()));
      await api.updateResidency(
        token: 'tok',
        siteCode: 7,
        residencyId: 55,
        relation: ResidencyRelation.owner,
      );
      expect(rec.last.method, 'PATCH');
      expect(rec.last.url.path, '/manager/sites/7/residencies/55');
      expect(rec.lastBody, <String, dynamic>{'relation': 'owner'});

      await api.endResidency(
        token: 'tok',
        siteCode: 7,
        residencyId: 55,
        moveOutDate: DateTime(2026, 10, 1),
      );
      expect(rec.last.method, 'POST');
      expect(rec.last.url.path, '/manager/sites/7/residencies/55/end');
      expect(rec.lastBody, <String, dynamic>{'move_out_date': '2026-10-01'});

      await api.endResidency(token: 'tok', siteCode: 7, residencyId: 55);
      expect(rec.lastBody, isEmpty, reason: 'tarih verilmezse sunucu bugünü yazar');
    });
  });

  group('AuthApi: daireler, araçlar, geçmiş, kayıtlarım', () {
    test('listApartments / getApartment / updateApartment yolları ve gövdeler', () async {
      final rec = _Recorder();
      final api = _api(rec, (r) {
        if (r.url.path.endsWith('/apartments')) {
          return _json({'items': <Map<String, dynamic>>[_apartmentBody()], 'total': 1});
        }
        return _json(_apartmentBody());
      });

      final page = await api.listApartments(
        token: 'tok',
        siteCode: 7,
        blockId: 1,
        query: 'A Blok',
        limit: 10,
        offset: 20,
      );
      expect(rec.last.url.path, '/manager/sites/7/apartments');
      expect(rec.last.url.queryParameters, <String, String>{
        'block_id': '1',
        'q': 'A Blok',
        'limit': '10',
        'offset': '20',
      });
      expect(page.items.single.landShare!.label, '35/1000');

      final detail = await api.getApartment(token: 'tok', siteCode: 7, apartmentId: 301);
      expect(rec.last.url.path, '/manager/sites/7/apartments/301');
      expect(detail.floor, 2);

      await api.updateApartment(
        token: 'tok',
        siteCode: 7,
        apartmentId: 301,
        fields: <String, Object?>{
          'floor': 3,
          'gross_area_m2': 120.5,
          'land_share_numerator': 35,
          'land_share_denominator': 1000,
          'category': null,
          'responsible_party': 'owner',
        },
      );
      expect(rec.last.method, 'PATCH');
      expect(rec.last.url.path, '/manager/sites/7/apartments/301');
      expect(rec.lastBody, <String, dynamic>{
        'floor': 3,
        'gross_area_m2': 120.5,
        'land_share_numerator': 35,
        'land_share_denominator': 1000,
        'category': null,
        'responsible_party': 'owner',
      });
    });

    test('araçlar: listVehicles sorgusu, createVehicle (201, {vehicle}) ve removeVehicle (DELETE)', () async {
      final rec = _Recorder();
      final api = _api(rec, (r) {
        if (r.method == 'POST') {
          return _json({
            'vehicle': {'id': 4, 'plate': '34ABC123', 'plate_display': '34 ABC 123'},
          }, 201);
        }
        if (r.method == 'DELETE') return _json({'ok': true});
        return _json({
          'items': <Map<String, dynamic>>[
            {'id': 4, 'plate': '34ABC123'},
          ],
          'total': 1,
        });
      });

      final page = await api.listVehicles(
        token: 'tok',
        siteCode: 7,
        query: '34 ABC',
        personId: 9,
        limit: 25,
        offset: 25,
      );
      expect(rec.last.url.path, '/manager/sites/7/vehicles');
      expect(rec.last.url.queryParameters, <String, String>{
        'q': '34 ABC',
        'person_id': '9',
        'limit': '25',
        'offset': '25',
      });
      expect(page.items.single.plate, '34ABC123');

      final vehicle = await api.createVehicle(
        token: 'tok',
        siteCode: 7,
        personId: 9,
        plate: ' 34 abc 123 ',
        note: 'gri araç',
      );
      expect(rec.last.method, 'POST');
      expect(rec.last.url.path, '/manager/sites/7/vehicles');
      expect(rec.lastBody, <String, dynamic>{
        'person_id': 9,
        'plate': '34 abc 123',
        'note': 'gri araç',
      });
      expect(vehicle.displayPlate, '34 ABC 123');

      await api.createVehicle(token: 'tok', siteCode: 7, personId: 9, plate: '06XYZ789');
      expect(rec.lastBody, <String, dynamic>{'person_id': 9, 'plate': '06XYZ789'});

      await api.removeVehicle(token: 'tok', siteCode: 7, vehicleId: 4);
      expect(rec.last.method, 'DELETE');
      expect(rec.last.url.path, '/manager/sites/7/vehicles/4');
    });

    test('listHistory: hedef türü / numarası / imleç sorguya yazılır', () async {
      final rec = _Recorder();
      final api = _api(rec, (r) => _json({
        'items': <Map<String, dynamic>>[
          {
            'id': 9,
            'action': 'person.updated',
            'details': {
              'changes': [
                {'field': 'phone', 'from': 'a', 'to': 'b'},
              ],
            },
          },
        ],
        'next_before_id': 9,
      }));
      final page = await api.listHistory(
        token: 'tok',
        siteCode: 7,
        targetType: 'person',
        targetId: 9,
        limit: 30,
        beforeId: 50,
      );
      expect(rec.last.method, 'GET');
      expect(rec.last.url.path, '/manager/sites/7/history');
      expect(rec.last.url.queryParameters, <String, String>{
        'target_type': 'person',
        'target_id': '9',
        'limit': '30',
        'before_id': '50',
      });
      expect(page.nextBeforeId, 9);
      expect(page.items.single.changes.single.fieldLabel, 'Telefon');

      await api.listHistory(token: 'tok', siteCode: 7);
      expect(rec.last.url.queryParameters, <String, String>{'limit': '50'});
    });

    test('getMyRecords: GET /app/my-records, kayıt yoksa boş liste', () async {
      final rec = _Recorder();
      final api = _api(rec, (r) => _json({
        'records': <Map<String, dynamic>>[
          {
            'site_code': 7,
            'site_name': 'Gül Sitesi',
            'apartment_id': 301,
            'label': 'A Blok - 5',
            'relation': 'tenant',
            'move_in_date': '2024-03-05',
            'vehicles': <dynamic>[],
          },
        ],
      }));
      final records = await api.getMyRecords(token: 'tok');
      expect(rec.last.method, 'GET');
      expect(rec.last.url.path, '/app/my-records');
      expect(records.single.relation, ResidencyRelation.tenant);

      final empty = _api(rec, (r) => _json(<String, dynamic>{}));
      expect(await empty.getMyRecords(token: 'tok'), isEmpty);
    });
  });

  group('Hata kodu -> Türkçe mesaj (Kişi ve Daire Kayıtları)', () {
    const expected = <String, String>{
      'PERSON_EXISTS': 'Bu e-posta ile kayıtlı bir kişi zaten var.',
      'PERSON_HAS_ACCOUNT': 'Hesabı olan kişinin bilgileri kişinin kendi profilinden değişir.',
      'RELATION_TAKEN': 'Bu dairede bu ilişki için aktif bir kişi zaten var.',
      'APARTMENT_NOT_FOUND': 'Daire bulunamadı.',
      'PLATE_INVALID': 'Plaka biçimi geçersiz. Örnek: 34 ABC 123 (il kodu 01-81).',
      'PLATE_EXISTS': 'Bu plaka bu sitede zaten kayıtlı.',
      'FORBIDDEN_ROLE': 'Bu işlem için yetkiniz yok.',
    };

    test('sözleşmedeki 7 kodun metni birebir ve kısa', () {
      for (final entry in expected.entries) {
        final message = AuthApi.messageForErrorCode(entry.key);
        expect(message, entry.value, reason: entry.key);
        expect(message!.length, lessThan(140));
        expect(message.contains('_'), isFalse);
      }
    });

    test('HTTP yanıtından geçince ApiException.message Türkçe eşleme olur; oturum KAPANMAZ', () async {
      for (final entry in expected.entries) {
        final status = entry.key == 'FORBIDDEN_ROLE' ? 403 : (entry.key.endsWith('NOT_FOUND') ? 404 : 409);
        final api = _api(_Recorder(), (r) => _json({'error': 'sunucu metni', 'code': entry.key}, status));
        await expectLater(
          api.getPerson(token: 'tok', siteCode: 7, personId: 1),
          throwsA(
            isA<ApiException>()
                .having((e) => e.message, 'message', entry.value)
                .having((e) => e.code, 'code', entry.key)
                .having((e) => e.statusCode, 'status', status)
                .having((e) => e.invalidatesSession, 'invalidatesSession', isFalse),
          ),
          reason: entry.key,
        );
      }
    });

    test('429 ve INVALID_BODY / INVALID_QUERY yedek mesajı; metin gelirse sunucunun metni', () async {
      final tooMany = _api(_Recorder(), (r) => http.Response(
        jsonEncode({'error': 'Çok fazla kayıt işlemi. Biraz sonra tekrar deneyin.'}),
        429,
        headers: {'content-type': 'application/json; charset=utf-8', 'retry-after': '120'},
      ));
      await expectLater(
        tooMany.createPerson(token: 'tok', siteCode: 7, fullName: 'Ali'),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'status', 429)
            .having((e) => e.message, 'message', contains('Biraz sonra'))),
      );

      final badBody = _api(_Recorder(), (r) => _json({'code': 'INVALID_BODY'}, 400));
      await expectLater(
        badBody.updateApartment(token: 'tok', siteCode: 7, apartmentId: 1, fields: <String, Object?>{'floor': 9999}),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('geçersiz'))),
      );

      final withText = _api(
        _Recorder(),
        (r) => _json({'error': 'floor alanı geçersiz (-20 ile 500 arasında tam sayı).', 'code': 'INVALID_BODY'}, 400),
      );
      await expectLater(
        withText.updateApartment(token: 'tok', siteCode: 7, apartmentId: 1, fields: <String, Object?>{'floor': 9999}),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('floor alanı'))),
      );
    });

    test('ek hata kodları: sunucu metni varsa o gösterilir, yoksa genel Türkçe yedek mesaj', () async {
      const fallbacks = <String, (int, String)>{
        'PERSON_NOT_FOUND': (404, 'Kişi bulunamadı.'),
        'VEHICLE_NOT_FOUND': (404, 'Araç bulunamadı.'),
        'RESIDENCY_NOT_FOUND': (404, 'İlişki kaydı bulunamadı.'),
        'RESIDENCY_NOT_CURRENT': (409, 'Bu ilişki artık güncel değil.'),
        'RESIDENCY_EXISTS': (409, 'Kişi bu dairede zaten kayıtlı.'),
        'SITE_NOT_FOUND': (404, 'Site bulunamadı.'),
        'INVALID_SITE_CODE': (400, 'Site bulunamadı.'),
        'INVALID_QUERY': (400, 'Geçersiz sorgu. Süzgeçleri kontrol edip tekrar deneyin.'),
      };
      for (final entry in fallbacks.entries) {
        final (status, fallback) = entry.value;
        // Sunucu metni yok: genel Türkçe mesaj.
        final bare = _api(_Recorder(), (r) => _json({'code': entry.key}, status));
        await expectLater(
          bare.getPerson(token: 'tok', siteCode: 7, personId: 1),
          throwsA(isA<ApiException>()
              .having((e) => e.message, 'message', fallback)
              .having((e) => e.code, 'code', entry.key)),
          reason: entry.key,
        );
        // Sunucu metni var: onun metni gösterilir.
        final withText = _api(
          _Recorder(),
          (r) => _json({'error': 'Sunucudan gelen açıklama.', 'code': entry.key}, status),
        );
        await expectLater(
          withText.getPerson(token: 'tok', siteCode: 7, personId: 1),
          throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Sunucudan gelen açıklama.')),
          reason: entry.key,
        );
      }
      // Hiç bilinmeyen kod: genel Türkçe yedek.
      final unknown = _api(_Recorder(), (r) => _json({'code': 'BILINMEYEN_KOD'}, 409));
      await expectLater(
        unknown.getPerson(token: 'tok', siteCode: 7, personId: 1),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', 'İşlem başarısız (409)')),
      );
    });

    test('PERSON_EXISTS: person_id hata gövdesinden ApiException.payload ile okunur (yoksa null)', () async {
      final withId = _api(
        _Recorder(),
        (r) => _json({'error': 'x', 'code': 'PERSON_EXISTS', 'person_id': 12}, 409),
      );
      await expectLater(
        withId.createPerson(token: 'tok', siteCode: 7, fullName: 'Ali'),
        throwsA(isA<ApiException>()
            .having((e) => e.code, 'code', 'PERSON_EXISTS')
            .having((e) => e.payload?['person_id'], 'person_id', 12)
            .having((e) => e.message, 'message', 'Bu e-posta ile kayıtlı bir kişi zaten var.')),
      );
      final withoutId = _api(_Recorder(), (r) => _json({'code': 'PERSON_EXISTS'}, 409));
      await expectLater(
        withoutId.createPerson(token: 'tok', siteCode: 7, fullName: 'Ali'),
        throwsA(isA<ApiException>().having((e) => e.payload?['person_id'], 'person_id', isNull)),
      );
    });

    test('createPerson yanıtı: hesap türü ve credentials_sent ayrışır', () async {
      final api = _api(
        _Recorder(),
        (r) => _json({..._personBody(), 'account_kind': 'internal', 'has_account': true, 'credentials_sent': false}, 201),
      );
      final created = await api.createPerson(token: 'tok', siteCode: 7, fullName: 'Ali');
      expect(created.isInternalAccount, isTrue);
      expect(created.credentialsSent, isFalse);
    });

    test('F4: sunucu metninde alan adı jargonu varsa kullanıcıya genel Türkçe mesaj gösterilir', () async {
      const jargon = <String>[
        'gross_area_m2 alanı geçersiz (0\'dan büyük sayı).',
        'move_in_date alanı geçersiz tarih (YYYY-AA-GG).',
        'land_share alanı geçersiz: pay ve payda birlikte dolu olmalı.',
        'Tarih biçimi YYYY-AA-GG olmalı.',
        'full_name zorunludur (2-100 karakter).',
      ];
      for (final text in jargon) {
        for (final code in const <String>['INVALID_BODY', 'SOMETHING_ELSE']) {
          final api = _api(_Recorder(), (r) => _json({'error': text, 'code': code}, 400));
          await expectLater(
            api.updateApartment(token: 'tok', siteCode: 7, apartmentId: 1, fields: <String, Object?>{'floor': 1}),
            throwsA(isA<ApiException>()
                .having((e) => e.message, 'message', AuthApi.jargonFallbackMessage)
                .having((e) => e.code, 'code', code)),
            reason: '$code / $text',
          );
        }
      }
      expect(AuthApi.jargonFallbackMessage,
          'Girilen bilgilerde hata var. Alanları kontrol edip tekrar deneyin.');
      // Temiz Türkçe metin olduğu gibi kalır (tek sözcüklü alan adı "floor" jargon sayılmaz).
      for (final clean in const <String>[
        'floor alanı geçersiz (-20 ile 500 arasında tam sayı).',
        'Bu e-posta ile kayıtlı bir kişi zaten var.',
        'Geçiş Kontrol kapatılırsa telefondan kapı açma durur. Onaylıyor musunuz?',
      ]) {
        expect(AuthApi.sanitizeServerMessage(clean), clean);
      }
      expect(AuthApi.sanitizeServerMessage(null), isNull);
    });

    test('F16: updateResidency yalnız değişen alanı gönderir; tarih açıkça temizlenebilir', () async {
      final rec = _Recorder();
      final api = _api(rec, (r) => _json(_personBody()));
      await api.updateResidency(token: 'tok', siteCode: 7, residencyId: 5, clearMoveInDate: true);
      expect(rec.lastBody, <String, dynamic>{'move_in_date': null});
      await api.updateResidency(
        token: 'tok',
        siteCode: 7,
        residencyId: 5,
        moveInDate: DateTime(2024, 1, 2),
        clearMoveInDate: true,
      );
      expect(rec.lastBody, <String, dynamic>{'move_in_date': '2024-01-02'}, reason: 'tarih varsa temizleme yok');
      await api.updateResidency(token: 'tok', siteCode: 7, residencyId: 5, relation: ResidencyRelation.owner);
      expect(rec.lastBody, <String, dynamic>{'relation': 'owner'}, reason: 'tarih anahtarı hiç gitmez');
    });

    test('beklenmeyen gövde (vehicle yok) anlaşılır hata olur, ham TypeError sızmaz', () async {
      final api = _api(_Recorder(), (r) => _json(<String, dynamic>{}, 201));
      await expectLater(
        api.createVehicle(token: 'tok', siteCode: 7, personId: 1, plate: '34ABC123'),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('AuthService: Kişi ve Daire Kayıtları sarmalayıcıları', () {
    UserSession session0({UserRole role = UserRole.siteManager}) => UserSession(
      id: 5,
      fullName: 'Ali Veli',
      email: 'ali@example.com',
      loginName: null,
      role: role,
      isActive: true,
      token: 'tok-A',
    );

    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      FlutterSecureStorage.setMockInitialValues(<String, String>{});
    });

    Future<({AuthService service, _Recorder rec})> makeService(
      FutureOr<http.Response> Function(http.Request request) handler, {
      UserRole role = UserRole.siteManager,
    }) async {
      FlutterSecureStorage.setMockInitialValues(<String, String>{
        'auth_session': jsonEncode(session0(role: role).toJson()),
      });
      final rec = _Recorder();
      final service = AuthService(api: _api(rec, (r) {
        if (r.url.path == '/me') {
          return _json({
            'user': {
              'id': 5,
              'full_name': 'Ali Veli',
              'email': 'ali@example.com',
              'login_name': null,
              'role': role.apiValue,
              'is_active': true,
            },
          });
        }
        return handler(r);
      }));
      await service.initialize();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      rec.requests.clear();
      return (service: service, rec: rec);
    }

    test('tüm sarmalayıcılar oturum belirteciyle sözleşmedeki yollara gider', () async {
      final h = await makeService((r) {
        final path = r.url.path;
        if (path == '/app/my-records') return _json({'records': <dynamic>[]});
        if (path.endsWith('/history')) return _json({'items': <dynamic>[], 'next_before_id': null});
        if (path.endsWith('/vehicles') && r.method == 'GET') {
          return _json({'items': <dynamic>[], 'total': 0});
        }
        if (path.endsWith('/vehicles') && r.method == 'POST') {
          return _json({'vehicle': {'id': 1, 'plate': '34ABC123'}}, 201);
        }
        if (path.contains('/vehicles/')) return _json({'ok': true});
        if (path.endsWith('/apartments') && r.method == 'GET') {
          return _json({'items': <dynamic>[], 'total': 0});
        }
        if (path.contains('/apartments/')) return _json(_apartmentBody());
        if (path.endsWith('/people') && r.method == 'GET') {
          return _json({'items': <dynamic>[], 'total': 0});
        }
        if (r.method == 'POST' &&
            (path.endsWith('/people') || path.endsWith('/residencies'))) {
          return _json(_personBody(), 201);
        }
        return _json(_personBody());
      });
      final s = h.service;

      await s.listPeople(7, query: 'ali', relation: ResidencyRelation.owner, status: 'inactive');
      expect(h.rec.last.headers['Authorization'], 'Bearer tok-A');
      expect(h.rec.last.url.path, '/manager/sites/7/people');
      expect(h.rec.last.url.queryParameters['relation'], 'owner');
      expect(h.rec.last.url.queryParameters['status'], 'inactive');

      await s.getPerson(7, 9);
      expect(h.rec.last.url.path, '/manager/sites/7/people/9');

      await s.createPerson(7, fullName: 'Ali', apartmentId: 301, relation: ResidencyRelation.owner);
      expect(h.rec.last.method, 'POST');
      expect(h.rec.lastBody['relation'], 'owner');

      await s.updatePerson(7, 9, <String, Object?>{'note': 'x'});
      expect(h.rec.last.method, 'PATCH');
      expect(h.rec.lastBody, <String, dynamic>{'note': 'x'});

      await s.addResidency(7, 9, apartmentId: 302, relation: ResidencyRelation.tenant);
      expect(h.rec.last.url.path, '/manager/sites/7/people/9/residencies');

      await s.updateResidency(7, 55, relation: ResidencyRelation.familyMember);
      expect(h.rec.last.url.path, '/manager/sites/7/residencies/55');

      await s.endResidency(7, 55, moveOutDate: DateTime(2026, 10, 1));
      expect(h.rec.last.url.path, '/manager/sites/7/residencies/55/end');
      expect(h.rec.lastBody['move_out_date'], '2026-10-01');

      await s.listApartments(7, blockId: 2);
      expect(h.rec.last.url.queryParameters['block_id'], '2');
      await s.getApartment(7, 301);
      expect(h.rec.last.url.path, '/manager/sites/7/apartments/301');
      await s.updateApartment(7, 301, <String, Object?>{'category': '3+1'});
      expect(h.rec.lastBody, <String, dynamic>{'category': '3+1'});

      await s.listVehicles(7, query: '34');
      expect(h.rec.last.url.path, '/manager/sites/7/vehicles');
      final vehicle = await s.createVehicle(7, 9, '34 ABC 123', note: 'x');
      expect(vehicle.id, 1);
      expect(h.rec.lastBody['plate'], '34 ABC 123');
      await s.removeVehicle(7, 1);
      expect(h.rec.last.method, 'DELETE');

      await s.listHistory(7, targetType: 'apartment', targetId: 301, beforeId: 12);
      expect(h.rec.last.url.queryParameters['target_type'], 'apartment');
      expect(h.rec.last.url.queryParameters['before_id'], '12');

      expect(await s.getMyRecords(), isEmpty);
      expect(h.rec.last.url.path, '/app/my-records');
      for (final request in h.rec.requests) {
        expect(request.headers['Authorization'], 'Bearer tok-A');
      }
      s.dispose();
    });

    test('sunucu reddi ApiException olarak Türkçe mesajla fırlar (PLATE_EXISTS)', () async {
      final h = await makeService((r) => _json({'error': 'x', 'code': 'PLATE_EXISTS'}, 409));
      await expectLater(
        h.service.createVehicle(7, 9, '34ABC123'),
        throwsA(isA<ApiException>()
            .having((e) => e.message, 'message', 'Bu plaka bu sitede zaten kayıtlı.')
            .having((e) => e.statusCode, 'status', 409)),
      );
      h.service.dispose();
    });
  });
}
