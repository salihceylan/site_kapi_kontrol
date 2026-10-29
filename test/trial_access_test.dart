// Deneme erişim kodu (P2-27, karar K10): kod girişi biçimi, oturum modeli, API çağrısı ve AuthService akışı
// (kodla giriş, süre bilgisinin saklanması / /me ile korunması, süre dolumunda oturumun kapanması).
import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/helpers/trial_code_input.dart';
import 'package:site_kapi_kontrol/ui/widgets/trial_banner.dart';

const _storageKey = 'auth_session';

http.Response _json(Object body, [int status = 200]) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

Map<String, dynamic> _trialUser(DateTime expiresAt, {String role = 'site_manager'}) => {
      'id': 20099,
      'full_name': 'Deneme Kullanıcısı 7',
      'email': 'trial-aabbccddeeff0011@deneme.invalid',
      'login_name': null,
      'role': role,
      'is_active': true,
      'must_change_password': false,
      'trial_expires_at': expiresAt.toUtc().toIso8601String(),
      'trial_site_code': 4000000001,
    };

class _Harness {
  _Harness(this.service, this.requests);
  final AuthService service;
  final List<http.Request> requests;
}

_Harness _makeService(FutureOr<http.Response> Function(http.Request request) handler) {
  final requests = <http.Request>[];
  final client = MockClient((request) async {
    requests.add(request);
    return handler(request);
  });
  final service = AuthService(
    api: AuthApi(baseUrl: 'https://api.example.test', client: client, retryDelay: Duration.zero),
  );
  return _Harness(service, requests);
}

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 30));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
  });

  group('kod girişi biçimi', () {
    test('formatTrialCodeInput: büyük harf, tire / boşluk atılır, 4\'erli gruplar, en çok 12 karakter', () {
      expect(formatTrialCodeInput(''), '');
      expect(formatTrialCodeInput('abc'), 'ABC');
      expect(formatTrialCodeInput('abcd'), 'ABCD');
      expect(formatTrialCodeInput('abcde'), 'ABCD-E');
      expect(formatTrialCodeInput('abcd efgh jkmn'), 'ABCD-EFGH-JKMN');
      expect(formatTrialCodeInput('ABCD-EFGH-JKMN'), 'ABCD-EFGH-JKMN');
      expect(formatTrialCodeInput(' a-b.c/d  e_f(g)h jk+mn '), 'ABCD-EFGH-JKMN');
      expect(formatTrialCodeInput('ABCDEFGHJKMNPQRS'), 'ABCD-EFGH-JKMN', reason: '12 karakterden fazlası kesilir');
      expect(formatTrialCodeInput('23456789ABCD'), '2345-6789-ABCD');
    });

    test('isCompleteTrialCode: tire hariç tam 12 karakter', () {
      expect(isCompleteTrialCode(''), isFalse);
      expect(isCompleteTrialCode('ABCD-EFGH-JKM'), isFalse);
      expect(isCompleteTrialCode('ABCD-EFGH-JKMN'), isTrue);
      expect(isCompleteTrialCode('abcdefghjkmn'), isTrue);
      expect(isCompleteTrialCode('ABCD-EFGH-JKMNP'), isFalse);
    });

    test('TrialCodeInputFormatter yazarken biçimler ve imleci sona koyar', () {
      const formatter = TrialCodeInputFormatter();
      final result = formatter.formatEditUpdate(
        const TextEditingValue(text: 'ABC'),
        const TextEditingValue(text: 'abcde', selection: TextSelection.collapsed(offset: 5)),
      );
      expect(result.text, 'ABCD-E');
      expect(result.selection.baseOffset, 6);
      final pasted = formatter.formatEditUpdate(
        TextEditingValue.empty,
        const TextEditingValue(text: 'abcd efgh jkmn xyz'),
      );
      expect(pasted.text, 'ABCD-EFGH-JKMN');
    });
  });

  group('kalan süre metni', () {
    test('saat yukarı yuvarlanır: 72 saat verilen oturum "72 saat kaldı"', () {
      expect(trialRemainingLabel(const Duration(hours: 72)), 'Deneme - 72 saat kaldı');
      expect(trialRemainingLabel(const Duration(hours: 71, minutes: 59, seconds: 59)), 'Deneme - 72 saat kaldı');
      expect(trialRemainingLabel(const Duration(hours: 71)), 'Deneme - 71 saat kaldı');
      expect(trialRemainingLabel(const Duration(hours: 1, minutes: 1)), 'Deneme - 2 saat kaldı');
      expect(trialRemainingLabel(const Duration(hours: 1)), 'Deneme - 1 saat kaldı');
    });

    test('bir saatten az: dakika (yukarı yuvarlanır, "0 dakika" çıkmaz); sınırda "1 saat"', () {
      expect(trialRemainingLabel(const Duration(minutes: 59, seconds: 30)), 'Deneme - 1 saat kaldı');
      expect(trialRemainingLabel(const Duration(minutes: 59)), 'Deneme - 59 dakika kaldı');
      expect(trialRemainingLabel(const Duration(minutes: 30, seconds: 1)), 'Deneme - 31 dakika kaldı');
      expect(trialRemainingLabel(const Duration(seconds: 1)), 'Deneme - 1 dakika kaldı');
    });

    test('süre doldu', () {
      expect(trialRemainingLabel(Duration.zero), 'Deneme süresi doldu');
      expect(trialRemainingLabel(const Duration(seconds: -5)), 'Deneme süresi doldu');
    });
  });

  group('UserSession deneme alanı', () {
    test('normal oturum: trialExpiresAt null, JSON\'a yazılmaz (eski kayıtlarla uyumlu)', () {
      final session = UserSession(
        id: 5,
        fullName: 'Ali',
        email: 'ali@example.com',
        loginName: null,
        role: UserRole.individual,
        isActive: true,
        token: 't',
      );
      expect(session.isTrial, isFalse);
      expect(session.toJson().containsKey('trial_expires_at'), isFalse);
      final back = UserSession.fromJson(session.toJson());
      expect(back.trialExpiresAt, isNull);
      // eski sürümün kaydı (alan yok) hâlâ okunur
      expect(UserSession.fromJson(<String, dynamic>{
        'id': 5, 'full_name': 'Ali', 'email': 'a@b.c', 'login_name': null, 'role': 'individual', 'is_active': true, 'token': 'x',
      }).isTrial, isFalse);
    });

    test('deneme oturumu: bitiş anı JSON gidiş-dönüşünde korunur; copyWith(token) süreyi korur', () {
      final expires = DateTime.utc(2026, 11, 1, 10, 30);
      final session = UserSession(
        id: 20099,
        fullName: 'Deneme Kullanıcısı 7',
        email: 'trial-aa@deneme.invalid',
        loginName: null,
        role: UserRole.siteManager,
        isActive: true,
        token: 'tok',
        trialExpiresAt: expires,
      );
      expect(session.isTrial, isTrue);
      final back = UserSession.fromJson(jsonDecode(jsonEncode(session.toJson())) as Map<String, dynamic>);
      expect(back.trialExpiresAt!.toUtc(), expires);
      expect(back.isTrial, isTrue);
      expect(session.copyWith(token: 'yeni').trialExpiresAt, session.trialExpiresAt);
    });
  });

  group('AuthApi.redeemTrialCode', () {
    test('POST /auth/trial-access {code}; yanıttaki trial_expires_at oturuma yazılır', () async {
      final expires = DateTime.now().toUtc().add(const Duration(hours: 72));
      late http.Request seen;
      final api = AuthApi(
        baseUrl: 'https://api.example.test',
        client: MockClient((request) async {
          seen = request;
          return _json({'token': 'trial-token', 'user': _trialUser(expires), 'trial': {'session_hours': 72}});
        }),
      );
      final session = await api.redeemTrialCode(code: 'ABCD-EFGH-JKMN');
      expect(seen.method, 'POST');
      expect(seen.url.path, '/auth/trial-access');
      expect(jsonDecode(seen.body), {'code': 'ABCD-EFGH-JKMN'});
      expect(seen.headers['Authorization'], isNull, reason: 'kimliksiz uç');
      expect(session.token, 'trial-token');
      expect(session.role, UserRole.siteManager);
      expect(session.isTrial, isTrue);
      expect(session.trialExpiresAt!.difference(DateTime.now()).inHours, inInclusiveRange(70, 72));
    });

    test('hata kodları ApiException olarak gelir; oturumu kapatma sinyali DEĞİLDİR', () async {
      final api = AuthApi(
        baseUrl: 'https://api.example.test',
        client: MockClient((request) async => _json({'error': 'Bu deneme kodu daha önce kullanılmış.', 'code': 'TRIAL_CODE_USED'}, 401)),
      );
      await expectLater(
        api.redeemTrialCode(code: 'ABCD-EFGH-JKMN'),
        throwsA(isA<ApiException>()
            .having((e) => e.code, 'code', 'TRIAL_CODE_USED')
            .having((e) => e.message, 'message', contains('daha önce kullanılmış'))
            .having((e) => e.invalidatesSession, 'invalidatesSession', isFalse)),
      );
    });
  });

  group('AuthService deneme oturumu', () {
    test('loginWithTrialCode: başarıda oturum açılır, süre güvenli depoya yazılır; yeniden açılışta korunur', () async {
      final expires = DateTime.now().toUtc().add(const Duration(hours: 72));
      final h = _makeService((r) {
        if (r.url.path == '/auth/trial-access') {
          return _json({'token': 'trial-token', 'user': _trialUser(expires)});
        }
        return _json({'user': _trialUser(expires)});
      });
      await h.service.initialize();
      final error = await h.service.loginWithTrialCode(code: 'ABCD-EFGH-JKMN');
      expect(error, isNull);
      expect(h.service.isLoggedIn, isTrue);
      expect(h.service.session!.isTrial, isTrue);
      expect(h.service.session!.role, UserRole.siteManager);

      final stored = await const FlutterSecureStorage().read(key: _storageKey);
      expect(jsonDecode(stored!)['trial_expires_at'], isNotNull);
      expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
      h.service.dispose();

      // yeniden açılış: kayıtlı oturum süreyle birlikte yüklenir
      final h2 = _makeService((r) => _json({'user': _trialUser(expires)}));
      await h2.service.initialize();
      expect(h2.service.session!.isTrial, isTrue);
      expect(h2.service.session!.trialExpiresAt!.toUtc().millisecondsSinceEpoch ~/ 1000, expires.millisecondsSinceEpoch ~/ 1000);
      await _settle();
      h2.service.dispose();
    });

    test('hatalı / kullanılmış kod: hata mesajı döner, oturum AÇILMAZ', () async {
      final h = _makeService((r) => _json({'error': 'Bu deneme kodu daha önce kullanılmış. Her kod yalnızca bir kez kullanılabilir.', 'code': 'TRIAL_CODE_USED'}, 401));
      await h.service.initialize();
      final error = await h.service.loginWithTrialCode(code: 'ABCD-EFGH-JKMN');
      expect(error, contains('daha önce kullanılmış'));
      expect(h.service.isLoggedIn, isFalse);
      expect(await const FlutterSecureStorage().read(key: _storageKey), isNull);
      h.service.dispose();
    });

    test('hız sınırı (429) ve sunucuya ulaşılamama kullanıcıya anlaşılır metinle döner', () async {
      final limited = _makeService((r) => _json({'error': 'Çok fazla deneme kodu girişi. Biraz sonra tekrar deneyin.', 'retry_after_seconds': 600}, 429));
      await limited.service.initialize();
      expect(await limited.service.loginWithTrialCode(code: 'ABCD-EFGH-JKMN'), contains('Çok fazla deneme'));
      limited.service.dispose();

      final broken = _makeService((r) => throw http.ClientException('offline'));
      await broken.service.initialize();
      expect(await broken.service.loginWithTrialCode(code: 'ABCD-EFGH-JKMN'), isNotEmpty);
      expect(broken.service.isLoggedIn, isFalse);
      broken.service.dispose();
    });

    test('/me yenilemesi deneme süresini korur', () async {
      final expires = DateTime.now().toUtc().add(const Duration(hours: 40));
      final h = _makeService((r) {
        if (r.url.path == '/auth/trial-access') {
          return _json({'token': 'trial-token', 'user': _trialUser(DateTime.now().toUtc().add(const Duration(hours: 72)))});
        }
        return _json({'user': _trialUser(expires)});
      });
      await h.service.initialize();
      await h.service.loginWithTrialCode(code: 'ABCD-EFGH-JKMN');
      await h.service.refreshSession(force: true);
      await _settle();
      expect(h.service.session!.isTrial, isTrue);
      expect(h.service.session!.trialExpiresAt!.difference(DateTime.now()).inHours, inInclusiveRange(38, 40));
      h.service.dispose();
    });

    test('süre dolumu: sunucu 401 TRIAL_EXPIRED -> oturum kapanır, giriş ekranına açıklama bırakılır', () async {
      final h = _makeService((r) {
        if (r.url.path == '/auth/trial-access') {
          return _json({'token': 'trial-token', 'user': _trialUser(DateTime.now().toUtc().add(const Duration(hours: 1)))});
        }
        return _json({'error': 'Deneme süreniz doldu. Devam etmek için bizimle iletişime geçin.', 'code': 'TRIAL_EXPIRED'}, 401);
      });
      await h.service.initialize();
      await h.service.loginWithTrialCode(code: 'ABCD-EFGH-JKMN');
      expect(h.service.isLoggedIn, isTrue);
      await h.service.refreshSession(force: true);
      await _settle();
      expect(h.service.isLoggedIn, isFalse);
      expect(h.service.takeSessionNotice(), contains('Deneme süreniz doldu'));
      expect(await const FlutterSecureStorage().read(key: _storageKey), isNull);
      h.service.dispose();
    });

    test('kapsam dışı istek 403: oturum KAPANMAZ (kullanıcı demo sitede çalışmaya devam eder)', () async {
      final h = _makeService((r) {
        if (r.url.path == '/auth/trial-access') {
          return _json({'token': 'trial-token', 'user': _trialUser(DateTime.now().toUtc().add(const Duration(hours: 72)))});
        }
        if (r.url.path == '/me') {
          return _json({'user': _trialUser(DateTime.now().toUtc().add(const Duration(hours: 72)))});
        }
        return _json({'error': 'Bu işlem deneme hesabında kullanılamaz.', 'code': 'TRIAL_ACTION_DENIED'}, 403);
      });
      await h.service.initialize();
      await h.service.loginWithTrialCode(code: 'ABCD-EFGH-JKMN');
      final (doors, error) = await h.service.listMyDoors();
      expect(doors, isNull);
      expect(error, isNotNull);
      await _settle();
      expect(h.service.isLoggedIn, isTrue, reason: '403 oturumu düşürmez; /me ile doğrulanır');
      expect(h.service.session!.isTrial, isTrue);
      h.service.dispose();
    });
  });
}
