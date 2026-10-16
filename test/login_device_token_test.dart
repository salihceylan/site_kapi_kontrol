// Güvenilir cihaz belirteci (S-C): POST /auth/login yanıtındaki `device_token` saklanır ve sonraki girişlerde
// gövdede `device_token` olarak gönderilir. Depo (LoginDeviceTokenStore), AuthApi.login ve AuthService.login.
//
// Kurallar: eksik/boş/bozuk belirteçte giriş etkilenmez; belirteç tanımlayıcı başına saklanır; çıkış silmez;
// depolama hatası girişi bozmaz; kişisel veri (e-posta) düz metin saklanmaz.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/login_device_token_store.dart';

const String _tokenA = 'ldt1.eyJ1IjoxfQ.imzaA';
const String _tokenB = 'ldt1.eyJ1IjoxfQ.imzaB';

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: <String, String>{'content-type': 'application/json; charset=utf-8'},
);

Map<String, dynamic> _user({String email = 'ali@example.com', String? loginName}) => <String, dynamic>{
  'id': 5,
  'full_name': 'Ali Veli',
  'email': email,
  'login_name': loginName,
  'role': 'individual',
  'is_active': true,
};

/// Her çağrıda çökme taklidi yapan depo (`implements` + noSuchMethod: tüm üyeler fırlatır).
class _BrokenStorage implements FlutterSecureStorage {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('depolama kapalı');
}

class _Harness {
  _Harness(this.handler, {LoginDeviceTokenStore? store}) {
    service = AuthService(
      api: AuthApi(
        baseUrl: 'https://api.example.test',
        client: MockClient((request) async {
          requests.add(request);
          return handler(request);
        }),
        retryDelay: Duration.zero,
      ),
      deviceTokenStore: store ?? LoginDeviceTokenStore(),
    );
  }

  final FutureOr<http.Response> Function(http.Request request) handler;
  final List<http.Request> requests = <http.Request>[];
  late final AuthService service;

  List<http.Request> get logins => requests.where((r) => r.url.path == '/auth/login').toList();

  Map<String, dynamic> loginBody(int index) => jsonDecode(logins[index].body) as Map<String, dynamic>;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
  });

  group('LoginDeviceTokenStore', () {
    test('kaydet / oku: tanımlayıcı katlanır (büyük-küçük harf, boşluk)', () async {
      final store = LoginDeviceTokenStore();
      await store.save(<String?>['Ali@Example.com ', null, '  '], _tokenA);
      expect(await store.read('ali@example.com'), _tokenA);
      expect(await store.read('  ALI@EXAMPLE.COM'), _tokenA);
      expect(await store.read('baska@example.com'), isNull);
      expect(await store.read(null), isNull);
      expect(await store.read(''), isNull);
    });

    test('birden çok tanımlayıcı (e-posta + kullanıcı adı) aynı belirteci paylaşır', () async {
      final store = LoginDeviceTokenStore();
      await store.save(<String?>['ali@example.com', 'ali.veli'], _tokenA);
      expect(await store.read('ali.veli'), _tokenA);
      expect(await store.read('ali@example.com'), _tokenA);
    });

    test('e-posta düz metin saklanmaz (özet)', () async {
      final store = LoginDeviceTokenStore();
      await store.save(<String?>['ali@example.com'], _tokenA);
      final raw = await const FlutterSecureStorage().read(key: LoginDeviceTokenStore.storageKey);
      expect(raw, isNotNull);
      expect(raw, isNot(contains('ali@example.com')));
      expect(raw, isNot(contains('ali')));
      expect(raw, contains(_tokenA));
    });

    test('geçersiz belirteç yazılmaz ve okunmaz (boş, boşluk, ASCII dışı, 512+)', () async {
      final store = LoginDeviceTokenStore();
      for (final bad in <String>['', 'a b', 'tok\nen', 'tökén', 'x' * 513]) {
        await store.save(<String?>['ali@example.com'], bad);
      }
      expect(await store.read('ali@example.com'), isNull);
      expect(LoginDeviceTokenStore.isPlausibleToken('x' * 512), isTrue);
      expect(LoginDeviceTokenStore.isPlausibleToken(null), isFalse);

      // Depoya elle bozuk belirteç yazılırsa okuma onu vermez.
      await const FlutterSecureStorage().write(
        key: LoginDeviceTokenStore.storageKey,
        value: jsonEncode(<String, dynamic>{
          'x': <String, dynamic>{'t': 'bozuk belirteç', 'at': 1},
        }),
      );
      expect(await store.read('ali@example.com'), isNull);
    });

    test('bozuk JSON ve beklenmeyen biçim sessizce yok sayılır; sonra yazma onarır', () async {
      await const FlutterSecureStorage().write(key: LoginDeviceTokenStore.storageKey, value: '{bozuk');
      final store = LoginDeviceTokenStore();
      expect(await store.read('ali@example.com'), isNull);
      await store.save(<String?>['ali@example.com'], _tokenA);
      expect(await store.read('ali@example.com'), _tokenA);

      await const FlutterSecureStorage().write(key: LoginDeviceTokenStore.storageKey, value: '[1,2,3]');
      expect(await store.read('ali@example.com'), isNull);
    });

    test('en çok ${LoginDeviceTokenStore.maxEntries} kayıt: en eskisi atılır', () async {
      var clock = DateTime(2026, 10, 16);
      final store = LoginDeviceTokenStore(now: () => clock);
      for (var i = 0; i < LoginDeviceTokenStore.maxEntries + 3; i++) {
        clock = clock.add(const Duration(minutes: 1));
        await store.save(<String?>['kullanici$i@example.com'], 'tok$i');
      }
      expect(await store.read('kullanici0@example.com'), isNull);
      expect(await store.read('kullanici1@example.com'), isNull);
      expect(await store.read('kullanici2@example.com'), isNull);
      expect(await store.read('kullanici10@example.com'), 'tok10');
      expect(await store.read('kullanici3@example.com'), 'tok3');
    });

    test('clear tüm kayıtları siler; bozuk depo hata fırlatmaz', () async {
      final store = LoginDeviceTokenStore();
      await store.save(<String?>['ali@example.com'], _tokenA);
      await store.clear();
      expect(await store.read('ali@example.com'), isNull);

      final broken = LoginDeviceTokenStore(storage: _BrokenStorage());
      expect(await broken.read('ali@example.com'), isNull);
      await broken.save(<String?>['ali@example.com'], _tokenA);
      await broken.clear();
    });
  });

  group('AuthApi.login', () {
    AuthApi apiWith(FutureOr<http.Response> Function(http.Request) handler, List<http.Request> sink) => AuthApi(
      baseUrl: 'https://api.example.test',
      client: MockClient((request) async {
        sink.add(request);
        return handler(request);
      }),
      retryDelay: Duration.zero,
    );

    test('device_token gövdeye yalnız doluysa eklenir', () async {
      final seen = <http.Request>[];
      final api = apiWith((_) => _json(<String, dynamic>{'token': 't', 'user': _user()}), seen);
      await api.login(email: 'a@b.co', password: 'x');
      await api.login(email: 'a@b.co', password: 'x', deviceToken: '');
      await api.login(email: 'a@b.co', password: 'x', deviceToken: _tokenA);
      final bodies = seen.map((r) => jsonDecode(r.body) as Map<String, dynamic>).toList();
      expect(bodies[0].containsKey('device_token'), isFalse);
      expect(bodies[1].containsKey('device_token'), isFalse);
      expect(bodies[2]['device_token'], _tokenA);
      // Başlık kullanılmaz (gövde alanı yeterli).
      expect(seen.last.headers.containsKey('X-Device-Token'), isFalse);
    });

    test('yanıttaki device_token geri çağrıya verilir; eksik / null / boş / metin değil / çok uzun verilmez', () async {
      final received = <String>[];
      Future<void> loginWith(Object? deviceTokenField, {bool include = true}) {
        final api = apiWith(
          (_) => _json(<String, dynamic>{
            'token': 't',
            'user': _user(),
            if (include) 'device_token': deviceTokenField,
          }),
          <http.Request>[],
        );
        return api.login(email: 'a@b.co', password: 'x', onDeviceToken: received.add);
      }

      await loginWith(_tokenA);
      await loginWith('  $_tokenB  ');
      await loginWith(null, include: false);
      await loginWith(null);
      await loginWith('   ');
      await loginWith(12345);
      await loginWith(<String>['x']);
      await loginWith('x' * 513);
      expect(received, <String>[_tokenA, _tokenB]);
    });

    test('eski sunucu (geri çağrı verilmemiş) sorunsuz çalışır', () async {
      final api = apiWith((_) => _json(<String, dynamic>{'token': 't', 'user': _user(), 'device_token': _tokenA}), <http.Request>[]);
      final session = await api.login(email: 'a@b.co', password: 'x');
      expect(session.token, 't');
    });
  });

  group('AuthService.login', () {
    test('ilk girişte belirteç gönderilmez; gelen belirteç tüm tanımlayıcılar için saklanır', () async {
      final h = _Harness((r) => _json(<String, dynamic>{
        'token': 't1',
        'user': _user(loginName: 'ali.veli'),
        'device_token': _tokenA,
      }));
      expect(await h.service.login(email: 'Ali.Veli', password: 'x'), isNull);
      expect(h.loginBody(0).containsKey('device_token'), isFalse);

      final store = LoginDeviceTokenStore();
      expect(await store.read('ali.veli'), _tokenA, reason: 'girilen ad');
      expect(await store.read('ali@example.com'), _tokenA, reason: 'oturumun e-postası');
      h.service.dispose();
    });

    test('sonraki girişte saklı belirteç gövdede gönderilir; yeni değer eskisini günceller', () async {
      var issued = _tokenA;
      final h = _Harness((r) => _json(<String, dynamic>{'token': 't', 'user': _user(), 'device_token': issued}));
      await h.service.login(email: 'ali@example.com', password: 'x');
      issued = _tokenB;
      await h.service.login(email: 'ALI@example.com', password: 'x');
      expect(h.loginBody(1)['device_token'], _tokenA, reason: 'ikinci girişte birincinin belirteci gider');

      await h.service.login(email: 'ali@example.com', password: 'x');
      expect(h.loginBody(2)['device_token'], _tokenB, reason: 'yenilenen değer saklandı');
      h.service.dispose();
    });

    test('yanıtta device_token yoksa eski belirteç KORUNUR (silinmez)', () async {
      var include = true;
      final h = _Harness((r) => _json(<String, dynamic>{
        'token': 't',
        'user': _user(),
        if (include) 'device_token': _tokenA,
      }));
      await h.service.login(email: 'ali@example.com', password: 'x');
      include = false;
      await h.service.login(email: 'ali@example.com', password: 'x');
      await h.service.login(email: 'ali@example.com', password: 'x');
      expect(h.loginBody(2)['device_token'], _tokenA);
      h.service.dispose();
    });

    test('belirteç başka tanımlayıcıya GİTMEZ', () async {
      final h = _Harness((r) => _json(<String, dynamic>{'token': 't', 'user': _user(), 'device_token': _tokenA}));
      await h.service.login(email: 'ali@example.com', password: 'x');
      await h.service.login(email: 'baska@example.com', password: 'x');
      expect(h.loginBody(1).containsKey('device_token'), isFalse);
      h.service.dispose();
    });

    test('hatalı girişte (401) saklı belirteç değişmez ve gönderilmeye devam eder', () async {
      var fail = false;
      final h = _Harness((r) {
        if (fail) return _json(<String, dynamic>{'error': 'Hatalı', 'code': 'INVALID_CREDENTIALS'}, 401);
        return _json(<String, dynamic>{'token': 't', 'user': _user(), 'device_token': _tokenA});
      });
      await h.service.login(email: 'ali@example.com', password: 'x');
      fail = true;
      expect(await h.service.login(email: 'ali@example.com', password: 'yanlis'), isNotNull);
      expect(h.loginBody(1)['device_token'], _tokenA);
      fail = false;
      await h.service.login(email: 'ali@example.com', password: 'x');
      expect(h.loginBody(2)['device_token'], _tokenA);
      h.service.dispose();
    });

    test('ÇIKIŞ belirteci silmez (kilit koruması çıkış yapıp dönen sahip içindir)', () async {
      final h = _Harness((r) => _json(<String, dynamic>{'token': 't', 'user': _user(), 'device_token': _tokenA}));
      await h.service.login(email: 'ali@example.com', password: 'x');
      await h.service.logout();
      expect(await LoginDeviceTokenStore().read('ali@example.com'), _tokenA);
      await h.service.login(email: 'ali@example.com', password: 'x');
      expect(h.loginBody(1)['device_token'], _tokenA);
      h.service.dispose();
    });

    test('depolama çöküyorsa giriş yine başarılı olur', () async {
      final h = _Harness(
        (r) => _json(<String, dynamic>{'token': 't', 'user': _user(), 'device_token': _tokenA}),
        store: LoginDeviceTokenStore(storage: _BrokenStorage()),
      );
      expect(await h.service.login(email: 'ali@example.com', password: 'x'), isNull);
      expect(h.service.isLoggedIn, isTrue);
      expect(h.loginBody(0).containsKey('device_token'), isFalse);
      h.service.dispose();
    });

    test('hesap silme temizliği (secureStorage.deleteAll) belirteci de siler', () async {
      final h = _Harness((r) => _json(<String, dynamic>{'token': 't', 'user': _user(), 'device_token': _tokenA}));
      await h.service.login(email: 'ali@example.com', password: 'x');
      await const FlutterSecureStorage().deleteAll();
      expect(await LoginDeviceTokenStore().read('ali@example.com'), isNull);
      h.service.dispose();
    });
  });

  group('Parola değişimi: cihaz belirteci (PATCH /me ve daire üyesi şifre değiştirme)', () {
    // Giriş + parola değişimi uçlarını yanıtlayan sahte sunucu. `changeDeviceToken`: parola değişim yanıtındaki
    // device_token alanı ('<yok>' = alan hiç gönderilmez).
    const absent = '<yok>';

    ({_Harness harness, void Function(Object?) setChangeToken}) makeHarness({
      Object? initialChangeToken = _tokenB,
      LoginDeviceTokenStore? store,
      int patchStatus = 200,
    }) {
      Object? changeToken = initialChangeToken;
      final harness = _Harness((r) {
        if (r.url.path == '/auth/login') {
          return _json(<String, dynamic>{
            'token': 't1',
            'user': _user(loginName: 'ali.veli'),
            'device_token': _tokenA,
          });
        }
        if (r.url.path == '/me' && r.method == 'PATCH') {
          if (patchStatus != 200) {
            return _json(<String, dynamic>{'error': 'Mevcut şifre hatalı', 'code': 'CURRENT_PASSWORD_INVALID'}, patchStatus);
          }
          return _json(<String, dynamic>{
            'user': _user(loginName: 'ali.veli'),
            'token': 't2',
            if (changeToken != absent) 'device_token': changeToken,
          });
        }
        if (r.url.path.endsWith('/change-password')) {
          return _json(<String, dynamic>{
            'message': 'Şifre güncellendi',
            'token': 't3',
            if (changeToken != absent) 'device_token': changeToken,
          });
        }
        return _json(<String, dynamic>{'error': 'yok'}, 404);
      }, store: store);
      return (harness: harness, setChangeToken: (Object? value) => changeToken = value);
    }

    Future<String?> changePassword(_Harness h, {String password = 'Mavi-Kedi-2026'}) => h.service.updateMyProfile(
      fullName: 'Ali Veli',
      email: 'ali@example.com',
      password: password,
      currentPassword: 'eskiParola',
    );

    List<http.Request> patches(_Harness h) => h.requests.where((r) => r.url.path == '/me' && r.method == 'PATCH').toList();

    test('PATCH /me parola değişimi: kayıtlı belirteç X-Device-Token başlığı olarak gider, yenisi her tanımlayıcıya yazılır', () async {
      final m = makeHarness();
      final h = m.harness;
      await h.service.login(email: 'ali@example.com', password: 'x');
      expect(await changePassword(h), isNull);

      final request = patches(h).single;
      expect(request.headers['X-Device-Token'], _tokenA);
      final store = LoginDeviceTokenStore();
      expect(await store.read('ali@example.com'), _tokenB, reason: 'e-posta anahtarı');
      expect(await store.read('ali.veli'), _tokenB, reason: 'kullanıcı adı anahtarı');
      // Parola değişimi başarısı etkilenmedi: oturum yeni token'a geçti.
      expect(h.service.session?.token, 't2');
      // Sonraki giriş yeni belirteci gönderir.
      await h.service.login(email: 'ali.veli', password: 'x');
      expect(h.loginBody(1)['device_token'], _tokenB);
      h.service.dispose();
    });

    test('parola DEĞİŞMİYORSA başlık gönderilmez (ad / telefon güncellemesi)', () async {
      final h = makeHarness().harness;
      await h.service.login(email: 'ali@example.com', password: 'x');
      expect(await h.service.updateMyProfile(fullName: 'Ali V.', email: 'ali@example.com', phoneNumber: '5551112233'), isNull);
      expect(patches(h).single.headers.containsKey('X-Device-Token'), isFalse);
      h.service.dispose();
    });

    test('saklı belirteç yoksa başlık gönderilmez; yanıttaki yeni belirteç yine saklanır', () async {
      final h = makeHarness().harness;
      // Giriş yapılmadan kurulan oturum: doğrudan depo boşken parola değişimi.
      await h.service.login(email: 'ali@example.com', password: 'x');
      await LoginDeviceTokenStore().clear();
      expect(await changePassword(h), isNull);
      expect(patches(h).single.headers.containsKey('X-Device-Token'), isFalse);
      expect(await LoginDeviceTokenStore().read('ali@example.com'), _tokenB);
      h.service.dispose();
    });

    test('yanıtta device_token yoksa / bozuksa sessizce yok sayılır: eski belirteç korunur, parola değişimi başarılı', () async {
      final bad = <Object?>[absent, null, 12345, <String>['x'], '', '   ', 'x' * 513, 'boşluklu belirteç', 'tökén'];
      for (final value in bad) {
        FlutterSecureStorage.setMockInitialValues(<String, String>{});
        final m = makeHarness(initialChangeToken: value);
        final h = m.harness;
        await h.service.login(email: 'ali@example.com', password: 'x');
        expect(await changePassword(h), isNull, reason: 'değer: $value');
        expect(h.service.session?.token, 't2', reason: 'değer: $value');
        expect(await LoginDeviceTokenStore().read('ali@example.com'), _tokenA, reason: 'değer: $value');
        h.service.dispose();
      }
    });

    test('yanıttaki belirteç kırpılır (boşluklu gelirse)', () async {
      final h = makeHarness(initialChangeToken: '  $_tokenB  ').harness;
      await h.service.login(email: 'ali@example.com', password: 'x');
      await changePassword(h);
      expect(await LoginDeviceTokenStore().read('ali@example.com'), _tokenB);
      h.service.dispose();
    });

    test('hatalı mevcut şifre (400): ileti döner, belirteç değişmez; başlık yine gönderilmişti', () async {
      final h = makeHarness(patchStatus: 400).harness;
      await h.service.login(email: 'ali@example.com', password: 'x');
      expect(await changePassword(h), 'Mevcut şifreniz hatalı. Lütfen kontrol edip tekrar deneyin.');
      expect(patches(h).single.headers['X-Device-Token'], _tokenA);
      expect(await LoginDeviceTokenStore().read('ali@example.com'), _tokenA);
      h.service.dispose();
    });

    test('depolama çöküyorsa parola değişimi yine başarılı (belirteç saklanamaz, başlık gitmez)', () async {
      final h = makeHarness(store: LoginDeviceTokenStore(storage: _BrokenStorage())).harness;
      await h.service.login(email: 'ali@example.com', password: 'x');
      expect(await changePassword(h), isNull);
      expect(patches(h).single.headers.containsKey('X-Device-Token'), isFalse);
      expect(h.service.session?.token, 't2');
      h.service.dispose();
    });

    test('daire üyesi şifre değiştirme: başlık + yeni belirteç saklanır + token güncellenir', () async {
      final h = makeHarness().harness;
      await h.service.login(email: 'ali@example.com', password: 'x');
      final (ok, message) = await h.service.changeApartmentMemberPassword(
        apartmentId: 7,
        targetUserCode: 5,
        newPassword: 'Mavi-Kedi-2026',
        currentPassword: 'eskiParola',
      );
      expect(ok, isTrue);
      expect(message, 'Şifre güncellendi');
      final request = h.requests.singleWhere((r) => r.url.path.endsWith('/change-password'));
      expect(request.headers['X-Device-Token'], _tokenA);
      expect(await LoginDeviceTokenStore().read('ali@example.com'), _tokenB);
      expect(await LoginDeviceTokenStore().read('ali.veli'), _tokenB);
      expect(h.service.session?.token, 't3');
      h.service.dispose();
    });

    test('daire üyesi şifre değiştirme: alan yoksa eski belirteç korunur ve başarı etkilenmez', () async {
      final h = makeHarness(initialChangeToken: absent).harness;
      await h.service.login(email: 'ali@example.com', password: 'x');
      final (ok, _) = await h.service.changeApartmentMemberPassword(
        apartmentId: 7,
        targetUserCode: 5,
        newPassword: 'Mavi-Kedi-2026',
        currentPassword: 'eskiParola',
      );
      expect(ok, isTrue);
      expect(await LoginDeviceTokenStore().read('ali@example.com'), _tokenA);
      h.service.dispose();
    });

    group('AuthApi doğrudan', () {
      AuthApi apiWith(FutureOr<http.Response> Function(http.Request) handler, List<http.Request> sink) => AuthApi(
        baseUrl: 'https://api.example.test',
        client: MockClient((request) async {
          sink.add(request);
          return handler(request);
        }),
        retryDelay: Duration.zero,
      );

      test('updateMyProfile: başlık yalnız (parola var + makul belirteç) iken; geri çağrı yalnız geçerli değerle', () async {
        final seen = <http.Request>[];
        final received = <String>[];
        final api = apiWith(
          (_) => _json(<String, dynamic>{'user': _user(), 'token': 'yeni', 'device_token': _tokenB}),
          seen,
        );
        Future<void> call({String? password, String? deviceToken}) => api.updateMyProfile(
          token: 'tok',
          id: 5,
          role: UserRole.individual,
          isActive: true,
          fullName: 'Ali',
          password: password,
          currentPassword: password == null ? null : 'eski',
          deviceToken: deviceToken,
          onDeviceToken: received.add,
        );
        await call(password: 'Mavi-Kedi-2026', deviceToken: _tokenA);
        await call(deviceToken: _tokenA); // parola yok
        await call(password: 'Mavi-Kedi-2026'); // belirteç yok
        await call(password: 'Mavi-Kedi-2026', deviceToken: 'a b'); // makul değil
        await call(password: 'Mavi-Kedi-2026', deviceToken: ''); // boş
        expect(seen[0].headers['X-Device-Token'], _tokenA);
        expect(seen[0].headers['Authorization'], 'Bearer tok');
        expect(seen[1].headers.containsKey('X-Device-Token'), isFalse);
        expect(seen[2].headers.containsKey('X-Device-Token'), isFalse);
        expect(seen[3].headers.containsKey('X-Device-Token'), isFalse);
        expect(seen[4].headers.containsKey('X-Device-Token'), isFalse);
        expect(received, hasLength(5), reason: 'geçerli yanıt belirteci her çağrıda bildirilir');
        expect(received.toSet(), <String>{_tokenB});
      });

      test('geri çağrı istisna fırlatsa bile parola değişimi başarılı sayılır', () async {
        final api = apiWith(
          (_) => _json(<String, dynamic>{'user': _user(), 'token': 'yeni', 'device_token': _tokenB}),
          <http.Request>[],
        );
        final session = await api.updateMyProfile(
          token: 'tok',
          id: 5,
          role: UserRole.individual,
          isActive: true,
          password: 'Mavi-Kedi-2026',
          currentPassword: 'eski',
          onDeviceToken: (_) => throw StateError('depolama'),
        );
        expect(session.token, 'yeni');
      });

      test('changeApartmentMemberPassword: başlık + geri çağrı', () async {
        final seen = <http.Request>[];
        final received = <String>[];
        final api = apiWith((_) => _json(<String, dynamic>{'message': 'ok', 'token': 'n', 'device_token': _tokenB}), seen);
        final payload = await api.changeApartmentMemberPassword(
          token: 'tok',
          apartmentId: 7,
          targetUserCode: 5,
          newPassword: 'Mavi-Kedi-2026',
          currentPassword: 'eski',
          deviceToken: _tokenA,
          onDeviceToken: received.add,
        );
        expect(payload['message'], 'ok');
        expect(seen.single.headers['X-Device-Token'], _tokenA);
        expect(received, <String>[_tokenB]);
        await api.changeApartmentMemberPassword(
          token: 'tok',
          apartmentId: 7,
          targetUserCode: 5,
          newPassword: 'Mavi-Kedi-2026',
          currentPassword: 'eski',
        );
        expect(seen.last.headers.containsKey('X-Device-Token'), isFalse);
      });
    });
  });
}
