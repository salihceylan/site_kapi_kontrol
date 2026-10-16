// Parola ilkesi doğrulayıcısı (lib/ui/helpers/password_policy.dart) ve sunucu uyumu.
//
// Sunucu (server/src/security/password_policy.js) ile BİREBİR aynı karar vermelidir: istemci, sunucunun kabul
// ettiği bir parolayı reddetmemeli (ve tersi). Düğüm (node) kuruluysa aynı parola kümesi sunucu modülünden
// geçirilip sonuçlar karşılaştırılır; liste dosyaları sunucu kaynağıyla senkron mu denetlenir.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/ui/helpers/password_policy.dart';
import 'package:site_kapi_kontrol/ui/helpers/password_policy_data.dart';

const String _serverFile = 'server/src/security/password_policy.js';

String? _msg(String? value, {String? email, List<String?> names = const <String?>[], bool allowEmpty = false}) =>
    PasswordPolicy.validate(value, email: email, names: names, allowEmpty: allowEmpty);

void main() {
  group('Uzunluk', () {
    test('boş: zorunlu; allowEmpty ile geçerli', () {
      expect(_msg(''), PasswordPolicy.requiredMessage);
      expect(_msg(null), PasswordPolicy.requiredMessage);
      expect(_msg('', allowEmpty: true), isNull);
      expect(_msg('  ', allowEmpty: true), isNotNull, reason: 'yalnız boşluk dolu sayılır ve çok kısadır');
    });

    test('7 karakter çok kısa, 8 karakter geçerli (kod noktası sayımı: emoji tek karakter)', () {
      expect(_msg('Ab1-xyz'), PasswordPolicy.tooShortMessage);
      expect(_msg('Ab1-xyzQ'), isNull);
      // 4 emoji = 4 karakter (UTF-16'da 8): kısa sayılmalı.
      final emoji = String.fromCharCodes(<int>[0x1F600, 0x1F601, 0x1F602, 0x1F603]);
      expect(_msg(emoji), PasswordPolicy.tooShortMessage);
      final eight = String.fromCharCodes(<int>[0x1F600, 0x1F601, 0x1F602, 0x1F603, 0x1F604, 0x1F605, 0x1F606, 0x1F607]);
      expect(_msg(eight), isNull);
    });

    // Tekrarsız, yaygın olmayan deterministik test dizgeleri.
    const asciiAlphabet = 'Kq7vXm2Zp9Lw4Tb8Rn5Yc3Hd6Fs';
    String ascii(int n) => List<String>.generate(n, (i) => asciiAlphabet[(i * 7 + i ~/ 5) % asciiAlphabet.length]).join();
    const turkish = 'şğüöçıİŞĞÜÖÇabcdefmnrt';
    String turkishText(int n) => List<String>.generate(n, (i) => turkish[(i * 5 + i ~/ 3) % turkish.length]).join();

    test('bayt sınırı: ASCII 72 karakter (72 bayt) geçerli, 73 çok uzun', () {
      expect(PasswordPolicy.maxBytes, 72);
      expect(_msg(ascii(72)), isNull);
      expect(_msg(ascii(73)), PasswordPolicy.tooLongMessage);
      expect(PasswordPolicy.evaluate(ascii(73)), PasswordIssue.tooLong);
    });

    test('bayt sınırı: 2 baytlı Türkçe harfler — 36 geçerli, 37 çok uzun; kod noktası sayısı 128\'in altında olsa da', () {
      // 36 iki baytlı harf = tam 72 bayt.
      final exactly = List<String>.generate(36, (i) => 'şğüöçıİŞĞÜÖÇ'[(i * 5) % 11]).join();
      expect(exactly.runes.length, 36);
      expect(_msg(exactly), isNull, reason: 'tam 72 bayt');
      expect(_msg('$exactlyş'), PasswordPolicy.tooLongMessage, reason: '74 bayt');
    });

    test('bayt sınırı: rapordaki örnek — 100 karakterlik Türkçe parola reddedilir', () {
      // Kod noktası sayısı 100 (< 128) ama 200 bayt: bcrypt ilk 72 baytı kullanırdı (ilk 36 harf aynı kalır).
      final long = turkishText(100);
      expect(long.runes.length, 100);
      expect(PasswordPolicy.evaluate(long), PasswordIssue.tooLong);
      expect(PasswordPolicy.evaluate('ş' * 100), PasswordIssue.tooLong);
    });

    test('bayt sınırı: karışık sınır değerleri (ASCII + 2 baytlı)', () {
      final head = ascii(70);
      expect(_msg('$headş'), isNull, reason: '70 + 2 = 72 bayt');
      expect(_msg('${ascii(71)}ş'), PasswordPolicy.tooLongMessage, reason: '71 + 2 = 73 bayt');
    });

    test('bayt sınırı: emoji 4 bayt — 18 geçerli, 19 çok uzun', () {
      final emoji18 = String.fromCharCodes(List<int>.generate(18, (i) => 0x1F600 + i * 3));
      expect(emoji18.runes.length, 18);
      expect(_msg(emoji18), isNull, reason: '18 x 4 = 72 bayt');
      expect(_msg('$emoji18${String.fromCharCode(0x1F680)}'), PasswordPolicy.tooLongMessage);
    });

    test('kod noktası sınırı da sürer: 129 karakter her zaman çok uzun', () {
      expect(PasswordPolicy.evaluate('x' * 129), PasswordIssue.tooLong);
      expect(PasswordPolicy.evaluate(ascii(129)), PasswordIssue.tooLong);
    });

    test('ileti iki sınırı da söyler (sunucu iletisiyle aynı bilgi)', () {
      expect(PasswordPolicy.tooLongMessage, contains('128'));
      expect(PasswordPolicy.tooLongMessage, contains('72'));
    });

    test('eşik sabitleri ileti metinleriyle tutarlı', () {
      expect(PasswordPolicy.tooShortMessage, contains('${PasswordPolicy.minLength}'));
      expect(PasswordPolicy.tooLongMessage, contains('${PasswordPolicy.maxLength}'));
      expect(PasswordPolicy.hint, contains('${PasswordPolicy.minLength}'));
    });
  });

  group('E-posta ve ad ile aynı olamaz', () {
    test('e-posta, e-posta yerel kısmı, büyük/küçük harf ve Türkçe harf farkı', () {
      expect(_msg('ali.yilmaz@example.com', email: 'ali.yilmaz@example.com'), PasswordPolicy.sameAsEmailMessage);
      expect(_msg('ALI.YILMAZ@EXAMPLE.COM', email: 'ali.yilmaz@example.com'), PasswordPolicy.sameAsEmailMessage);
      expect(_msg('mehmetyilmaz', email: 'mehmetyilmaz@example.com'), PasswordPolicy.sameAsEmailMessage);
      expect(_msg('mehmet.yilmaz', email: 'mehmetyilmaz@example.com'), PasswordPolicy.sameAsEmailMessage,
          reason: 'noktalama/ayırıcı farkı yok sayılır (sunucuyla aynı)');
      expect(_msg('Mavi-Kedi-2026', email: 'ali@example.com'), isNull);
    });

    test('ad, soyad, ad soyad: Türkçe katlama ve boşluk farkı yok sayılır', () {
      const names = <String?>['Şükrü', 'Çağlayan', 'Şükrü Çağlayan'];
      expect(_msg('sukrucaglayan', names: names), PasswordPolicy.sameAsNameMessage);
      expect(_msg('ŞÜKRÜ ÇAĞLAYAN', names: names), PasswordPolicy.sameAsNameMessage);
      expect(_msg('sukru caglayan', names: names), PasswordPolicy.sameAsNameMessage);
      expect(_msg('Mavi-Kedi-2026', names: names), isNull);
    });
  });

  group('Yaygın ve tahmin edilebilir parolalar', () {
    test('yaygın liste, Türkçe katlama (İ/ı/ş/ğ/ü/ö/ç) ve kısa ek', () {
      for (final bad in <String>[
        '12345678',
        'password',
        'Password1',
        'Password123!',
        'QWERTY123',
        'Fenerbahçe1907',
        'FENERBAHCE1907',
        'GALATASARAY',
        'İstanbul34',
        'ISTANBUL34',
        'şifre1234',
        'SIFRE-1234',
        'parola123',
        'Sifre2024!',
        '2024parola',
        'aaaaaaaa',
        'abababab',
        '12121212',
        '20242024',
        '15031990',
        '19900315',
        'abcdefgh',
        'qwertyui',
        '87654321',
        'abcdefg1',
      ]) {
        expect(PasswordPolicy.isCommon(bad), isTrue, reason: bad);
        expect(_msg(bad), PasswordPolicy.commonMessage, reason: bad);
      }
    });

    test('sunucunun kabul ettiği parolalar istemcide de geçerlidir (ör. abcdef12)', () {
      for (final good in <String>[
        'abcdef12',
        'Mavi-Kedi-2026',
        'correct horse battery',
        'kırmızı Balon 77!',
        'Zorlu_Yol_Ayrımı',
        'x7Qp-9Lm2',
        'sabah-kahvesi-demli',
        'E2eYeni!2345', // e2e yürüyüşünün kayıt parolası
      ]) {
        expect(PasswordPolicy.isCommon(good), isFalse, reason: good);
        expect(_msg(good), isNull, reason: good);
      }
    });

    test('Türkçe katlama: İ/I/ı -> i, ş/ğ/ü/ö/ç -> ASCII', () {
      expect(PasswordPolicy.fold('İSTANBUL ŞĞÜÖÇ ıI'), 'istanbul sguoc ii');
      expect(PasswordPolicy.fold('  Çağrı  '), 'cagri');
    });
  });

  group('Sunucu hatası eşleme', () {
    test('WEAK_PASSWORD + reason -> özel ileti; reason yoksa / bilinmiyorsa genel ileti', () {
      expect(PasswordPolicy.messageForServerCode('WEAK_PASSWORD', reason: 'too_short'), PasswordPolicy.tooShortMessage);
      expect(PasswordPolicy.messageForServerCode('WEAK_PASSWORD', reason: 'too_long'), PasswordPolicy.tooLongMessage);
      expect(PasswordPolicy.messageForServerCode('WEAK_PASSWORD', reason: 'same_as_email'),
          PasswordPolicy.sameAsEmailMessage);
      expect(PasswordPolicy.messageForServerCode('WEAK_PASSWORD', reason: 'same_as_name'),
          PasswordPolicy.sameAsNameMessage);
      expect(PasswordPolicy.messageForServerCode('WEAK_PASSWORD', reason: 'common'), PasswordPolicy.commonMessage);
      expect(PasswordPolicy.messageForServerCode('WEAK_PASSWORD', reason: 'required'), PasswordPolicy.requiredMessage);
      expect(PasswordPolicy.messageForServerCode('WEAK_PASSWORD'), PasswordPolicy.weakFromServerMessage);
      expect(PasswordPolicy.messageForServerCode('WEAK_PASSWORD', reason: 'yeni_bilinmeyen'),
          PasswordPolicy.weakFromServerMessage);
      expect(PasswordPolicy.messageForServerCode('BAŞKA_KOD'), isNull);
    });

    test('AuthApi.messageForErrorCode WEAK_PASSWORD yanıtının reason alanını kullanır', () {
      expect(
        AuthApi.messageForErrorCode('WEAK_PASSWORD', payload: <String, dynamic>{'reason': 'common'}),
        PasswordPolicy.commonMessage,
      );
      expect(AuthApi.messageForErrorCode('WEAK_PASSWORD', payload: <String, dynamic>{}), AuthApi.weakPasswordMessage);
      expect(AuthApi.messageForErrorCode('WEAK_PASSWORD'), AuthApi.weakPasswordMessage);
    });

    test('PasswordIssue adları sunucu reason değerleriyle birebir', () {
      expect(PasswordIssue.values.map((i) => i.serverReason).toSet(), <String>{
        'required',
        'too_short',
        'too_long',
        'same_as_email',
        'same_as_name',
        'common',
      });
      expect(PasswordIssue.fromServerReason('common'), PasswordIssue.common);
      expect(PasswordIssue.fromServerReason('nope'), isNull);
    });
  });

  group('Sunucu uyumu (node varsa)', () {
    final serverFile = File(_serverFile);

    test('yerleşik listeler sunucu kaynağıyla aynı', () {
      if (!serverFile.existsSync()) {
        markTestSkipped('sunucu kaynağı yok');
        return;
      }
      final source = serverFile.readAsStringSync();
      Set<String> extract(String name) {
        final match = RegExp('const $name = new Set\\(\\[(.*?)\\]\\);', dotAll: true).firstMatch(source);
        expect(match, isNotNull, reason: name);
        final body = match!.group(1)!.split('\n').map((l) => l.replaceAll(RegExp(r'//.*$'), '')).join('\n');
        return RegExp(r"'([^']+)'").allMatches(body).map((m) => m.group(1)!).toSet();
      }

      expect(kCommonPasswords, extract('COMMON_PASSWORDS'),
          reason: 'password_policy_data.dart sunucu listesinden üretilmeli (bkz. dosya başlığı)');
      expect(kCommonPasswordBases, extract('COMMON_BASES'));
    });

    test('aynı parola kümesinde istemci ve sunucu aynı nedeni verir', () async {
      if (!serverFile.existsSync()) {
        markTestSkipped('sunucu kaynağı yok');
        return;
      }
      // (parola, e-posta, ad listesi)
      final cases = <List<Object?>>[
        <Object?>['', null, <String>[]],
        <Object?>['kisa1', null, <String>[]],
        <Object?>['Ab1-xyzQ', null, <String>[]],
        <Object?>['abcdef12', null, <String>[]],
        <Object?>['abcdefg1', null, <String>[]],
        <Object?>['12345678', null, <String>[]],
        <Object?>['Password1', null, <String>[]],
        <Object?>['Password123!', null, <String>[]],
        <Object?>['Fenerbahçe1907', null, <String>[]],
        <Object?>['İstanbul34', null, <String>[]],
        <Object?>['SIFRE-1234', null, <String>[]],
        <Object?>['2024parola', null, <String>[]],
        <Object?>['aaaaaaaa', null, <String>[]],
        <Object?>['abababab', null, <String>[]],
        <Object?>['20242024', null, <String>[]],
        <Object?>['15031990', null, <String>[]],
        <Object?>['19900315', null, <String>[]],
        <Object?>['qwertyui', null, <String>[]],
        <Object?>['87654321', null, <String>[]],
        <Object?>['Mavi-Kedi-2026', null, <String>[]],
        <Object?>['correct horse battery', null, <String>[]],
        <Object?>['kırmızı Balon 77!', null, <String>[]],
        <Object?>['x7Qp-9Lm2', null, <String>[]],
        <Object?>['E2eYeni!2345', null, <String>[]],
        <Object?>['ali.yilmaz@example.com', 'ali.yilmaz@example.com', <String>[]],
        <Object?>['ALI.YILMAZ@EXAMPLE.COM', 'ali.yilmaz@example.com', <String>[]],
        <Object?>['mehmetyilmaz', 'mehmetyilmaz@example.com', <String>[]],
        <Object?>['mehmet.yilmaz', 'mehmetyilmaz@example.com', <String>[]],
        <Object?>['sukrucaglayan', null, <String>['Şükrü', 'Çağlayan', 'Şükrü Çağlayan']],
        <Object?>['ŞÜKRÜ ÇAĞLAYAN', null, <String>['Şükrü', 'Çağlayan', 'Şükrü Çağlayan']],
        <Object?>['Mavi-Kedi-2026', 'ali@example.com', <String>['Ali', 'Veli', 'Ali Veli']],
        <Object?>['x' * 129, null, <String>[]],
        <Object?>['ab' * 64, null, <String>[]],
        // bcrypt 72 BAYT sınırı (sunucuyla aynı karar vermeli).
        <Object?>['K' * 72, null, <String>[]],
        <Object?>['Kq7vXm2Zp9' * 7 + 'Lw', null, <String>[]],
        <Object?>['Kq7vXm2Zp9' * 7 + 'Lw4', null, <String>[]],
        <Object?>['ş' * 100, null, <String>[]],
        <Object?>['şğüöçıİŞĞÜÖÇ' * 3, null, <String>[]],
        <Object?>['şğüöçıİŞĞÜÖÇ' * 3 + 'ş', null, <String>[]],
        <Object?>['şğüöçıİŞĞÜÖÇabcdefmnrt' * 3, null, <String>[]],
        <Object?>[String.fromCharCodes(List<int>.generate(18, (i) => 0x1F600 + i * 3)), null, <String>[]],
        <Object?>[String.fromCharCodes(List<int>.generate(19, (i) => 0x1F600 + i * 3)), null, <String>[]],
      ];
      final script = '''
import { evaluatePassword } from 'file:///${serverFile.absolute.path.replaceAll('\\', '/')}';
let raw = '';
for await (const chunk of process.stdin) raw += chunk;
const cases = JSON.parse(raw);
const out = cases.map(([password, email, names]) => {
  const verdict = evaluatePassword(password, { email: email ?? undefined, names });
  return verdict.ok ? null : verdict.reason;
});
process.stdout.write(JSON.stringify(out));
''';
      ProcessResult result;
      try {
        final process = await Process.start('node', <String>['--input-type=module', '-e', script]);
        process.stdin.write(jsonEncode(cases));
        await process.stdin.close();
        final stdout = await process.stdout.transform(utf8.decoder).join();
        final stderr = await process.stderr.transform(utf8.decoder).join();
        final code = await process.exitCode;
        result = ProcessResult(process.pid, code, stdout, stderr);
      } on ProcessException {
        markTestSkipped('node kurulu değil');
        return;
      }
      expect(result.exitCode, 0, reason: '${result.stderr}');
      final serverReasons = (jsonDecode(result.stdout as String) as List).cast<String?>();
      for (var i = 0; i < cases.length; i++) {
        final password = cases[i][0] as String;
        final email = cases[i][1] as String?;
        final names = (cases[i][2] as List).cast<String>();
        final client = PasswordPolicy.evaluate(password, email: email, names: names);
        expect(client?.serverReason, serverReasons[i], reason: 'parola #$i (${password.length} karakter)');
      }
    });
  });
}
