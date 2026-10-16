/// Parola ilkesi doğrulayıcısı (docs/PLATFORM_SATISA_HAZIRLIK.md §1.7).
///
/// Yeni, değişen ve sıfırlanan parola: en az [PasswordPolicy.minLength], en çok [PasswordPolicy.maxLength]
/// karakter (Unicode kod noktası); e-posta, e-postanın `@` öncesi kısmı ya da adla aynı olamaz; yaygın /
/// tahmin edilmesi kolay parolalar kabul edilmez. Sunucu aynı kuralı `400 {"code":"WEAK_PASSWORD","reason":…}`
/// ile uygular (`server/src/security/password_policy.js`); bu dosya sunucu algoritmasının BİREBİR Dart
/// karşılığıdır (aynı katlama, aynı listeler — bkz. password_policy_data.dart —, aynı örüntüler), böylece
/// istemci sunucunun kabul ettiği bir parolayı reddetmez. Tek bilinçli fark: sunucudaki NFKC normalleştirmesi
/// Dart'ta yoktur (yalnız uyumluluk biçimli nadir karakterleri etkiler). İstemci hatayı gönderimden ÖNCE,
/// eyleme dönük Türkçe iletiyle gösterir; sunucudan gelen `WEAK_PASSWORD` `reason` değeri de aynı iletilere
/// eşlenir ([PasswordPolicy.messageForServerCode]).
///
/// Uzunluk iki birimle sınırlıdır: en çok [PasswordPolicy.maxLength] kod noktası VE en çok
/// [PasswordPolicy.maxBytes] UTF-8 baytı. Sunucu bcrypt kullanır ve bcrypt girdinin yalnız ilk 72 BAYTINI özetler;
/// bayt sınırı olmasaydı 100 karakterlik Türkçe bir parolanın (200 bayt) 36. karakterden sonrası yok sayılır ve
/// kısaltılmış parola da girişi geçerdi. İhlal `too_long` nedenini verir (sunucuyla aynı ad).
///
/// Mevcut kullanıcıların eski parolaları girişte çalışmaya devam eder: bu sınıf yalnız YENİ parola
/// belirlenen formlarda kullanılır, giriş formunda KULLANILMAZ. Parolanın kendisi hiçbir iletiye, günlüğe
/// ya da hata metnine yazılmaz.
library;

import 'dart:convert';

import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/ui/helpers/password_policy_data.dart';

/// Parola ilkesi ihlal nedeni (sunucudaki `reason` değerleriyle aynı adlar).
enum PasswordIssue {
  required('required'),
  tooShort('too_short'),
  tooLong('too_long'),
  sameAsEmail('same_as_email'),
  sameAsName('same_as_name'),
  common('common');

  const PasswordIssue(this.serverReason);

  /// Sunucu yanıtındaki `reason` değeri.
  final String serverReason;

  /// `reason` metninden neden; bilinmiyorsa null.
  static PasswordIssue? fromServerReason(Object? reason) {
    for (final issue in values) {
      if (issue.serverReason == reason) return issue;
    }
    return null;
  }
}

abstract final class PasswordPolicy {
  static const int minLength = 8;
  static const int maxLength = 128;

  /// bcrypt'in özetlediği en çok bayt (UTF-8). Daha uzun parola `too_long` sayılır.
  static const int maxBytes = 72;

  /// Alan ipucu (hint/helper) metni.
  static const String hint = 'En az $minLength karakter';

  static const String requiredMessage = AuthApi.passwordRequiredMessage;
  static const String tooShortMessage = AuthApi.passwordTooShortMessage;
  static const String tooLongMessage = AuthApi.passwordTooLongMessage;
  static const String sameAsEmailMessage = AuthApi.passwordSameAsEmailMessage;
  static const String sameAsNameMessage = AuthApi.passwordSameAsNameMessage;
  static const String commonMessage = AuthApi.passwordCommonMessage;

  /// Sunucudan `WEAK_PASSWORD` geldiğinde (neden belirtilmemişse) gösterilen genel ileti.
  static const String weakFromServerMessage = AuthApi.weakPasswordMessage;

  /// [issue] için kullanıcıya gösterilen ileti.
  static String messageFor(PasswordIssue issue) {
    switch (issue) {
      case PasswordIssue.required:
        return requiredMessage;
      case PasswordIssue.tooShort:
        return tooShortMessage;
      case PasswordIssue.tooLong:
        return tooLongMessage;
      case PasswordIssue.sameAsEmail:
        return sameAsEmailMessage;
      case PasswordIssue.sameAsName:
        return sameAsNameMessage;
      case PasswordIssue.common:
        return commonMessage;
    }
  }

  /// Sunucu hata kodunu (+ varsa `reason`) ileti ile eşler; `WEAK_PASSWORD` değilse null.
  static String? messageForServerCode(String? code, {Object? reason}) =>
      code == 'WEAK_PASSWORD' ? AuthApi.weakPasswordMessageFor(reason) : null;

  /// [value] geçerliyse null, değilse kullanıcıya gösterilecek ileti.
  ///
  /// - [allowEmpty] true ise boş değer geçerlidir ("Yeni Şifre (opsiyonel)" alanı).
  /// - [email] ve [names]: parolanın aynısı olamayacağı değerler (ad, soyad, ad soyad, kullanıcı adı);
  ///   büyük/küçük harf, Türkçe harf ve boşluk/nokta/tire/alt çizgi farkı yok sayılır.
  /// - Boşluklar kırpılmaz: parola olduğu gibi değerlendirilir. Çağıran, sunucuya gönderdiği biçimi
  ///   (örn. `trim()`) buraya da verir.
  static String? validate(
    String? value, {
    bool allowEmpty = false,
    String? email,
    Iterable<String?> names = const <String?>[],
  }) {
    final password = value ?? '';
    if (password.isEmpty && allowEmpty) return null;
    final issue = evaluate(password, email: email, names: names);
    return issue == null ? null : messageFor(issue);
  }

  /// Parolayı sunucudaki sırayla değerlendirir; geçerliyse null, değilse ilk ihlal.
  static PasswordIssue? evaluate(
    String? value, {
    String? email,
    Iterable<String?> names = const <String?>[],
  }) {
    final password = value ?? '';
    if (password.isEmpty) return PasswordIssue.required;
    // Karakter sayımı Unicode kod noktasıdır (sunucu aynı birimi kullanır; emoji tek karakterdir).
    final length = password.runes.length;
    if (length < minLength) return PasswordIssue.tooShort;
    if (length > maxLength) return PasswordIssue.tooLong;
    // bcrypt ilk 72 baytı kullanır: çok baytlı harfler (ş, ğ, ı: 2 bayt; emoji: 4 bayt) bu sınıra daha çabuk varır.
    if (utf8.encode(password).length > maxBytes) return PasswordIssue.tooLong;

    final folded = fold(password);
    final compact = _withoutSeparators(folded);

    final mail = fold(email ?? '');
    if (mail.isNotEmpty) {
      final emails = <String>[mail];
      final at = mail.indexOf('@');
      if (at > 0) emails.add(mail.substring(0, at));
      if (emails.any((c) => c == folded || _withoutSeparators(c) == compact)) {
        return PasswordIssue.sameAsEmail;
      }
    }
    for (final name in names) {
      final candidate = fold(name ?? '');
      if (candidate.isNotEmpty && (candidate == folded || _withoutSeparators(candidate) == compact)) {
        return PasswordIssue.sameAsName;
      }
    }
    if (isCommon(password)) return PasswordIssue.common;
    return null;
  }

  /// Yaygın ya da tahmin edilmesi kolay parola mı? (sunucudaki `isCommonPassword` ile aynı kurallar)
  static bool isCommon(String password) {
    final folded = fold(password);
    if (folded.isEmpty) return false;
    // Ayırıcısız biçim ("sifre-123" -> "sifre123") ve sondaki yalnız-im eki atılmış biçim ("12345678!" -> "12345678").
    final compact = _withoutSeparators(folded);
    final noTrailingSymbols = compact.replaceFirst(_trailingSymbols, '');
    for (final candidate in <String>{folded, compact, noTrailingSymbols}) {
      if (candidate.isNotEmpty &&
          (kCommonPasswords.contains(candidate) ||
              kCommonPasswordBases.contains(candidate) ||
              _isTrivialPattern(candidate))) {
        return true;
      }
    }
    // "Yaygın sözcük + kısa rakam/im eki" ("Sifre2024!", "2024parola"): kök listedeyse ya da 7+ karakterlik bir
    // diziyse ("abcdefg1"). 6 karakterlik dizi + ek ("abcdef12") sunucuda kabul edilir; istemci de kabul eder.
    final base = compact.replaceFirst(_trailingFiller, '').replaceFirst(_leadingFiller, '');
    if (base.isNotEmpty && base != compact) {
      if (kCommonPasswordBases.contains(base) || kCommonPasswords.contains(base)) return true;
      if (base.length >= 7 && (_isSequence(base) || base.runes.toSet().length <= 1)) return true;
    }
    return false;
  }

  /// Karşılaştırma için katlama (sunucudaki `foldForComparison`): kırp + `İ/I` -> `i` + küçük harf +
  /// Türkçe harfler ASCII karşılığına (ı -> i, ş -> s, ğ -> g, ü -> u, ö -> o, ç -> c; â, î, û da).
  /// "Fenerbahçe1907" ve "fenerbahce1907" aynı kabul edilir.
  static String fold(String value) {
    final buffer = StringBuffer();
    for (final rune in value.trim().runes) {
      final ch = String.fromCharCode(rune);
      final lower = (ch == 'İ' || ch == 'I') ? 'i' : ch.toLowerCase();
      buffer.write(_trFold[lower] ?? lower);
    }
    // Birleşik nokta (U+0307) "i̇" ayrıştırmasından kalabilir.
    return String.fromCharCodes(buffer.toString().runes.where((c) => c != 0x307));
  }

  static const Map<String, String> _trFold = <String, String>{
    'ı': 'i',
    'ş': 's',
    'ğ': 'g',
    'ü': 'u',
    'ö': 'o',
    'ç': 'c',
    'â': 'a',
    'î': 'i',
    'û': 'u',
  };

  // Sunucu ile aynı düzenli ifadeler.
  static final RegExp _separators = RegExp(r'[\s._-]+');
  static final RegExp _trailingFiller = RegExp(r'[0-9!._\-*@#$%+?,;:]{1,6}$');
  static final RegExp _leadingFiller = RegExp(r'^[0-9!._\-*@#$%+?,;:]{1,4}');
  static final RegExp _trailingSymbols = RegExp(r'[!._\-*@#$%+?,;:]+$');

  static String _withoutSeparators(String value) => value.replaceAll(_separators, '');

  static const List<String> _sequenceSources = <String>[
    '01234567890',
    'abcdefghijklmnopqrstuvwxyz',
    'qwertyuiopasdfghjklzxcvbnm',
    'qwertyuiopgusdfghjklsizxcvbnmoc', // Türkçe Q klavye (katlanmış)
    'qazwsxedcrfvtgbyhnujmikolp',
    '1qaz2wsx3edc4rfv5tgb6yhn7ujm8ik9ol0p',
    '1q2w3e4r5t6y7u8i9o0p',
  ];

  static bool _isSequence(String folded) {
    for (final source in _sequenceSources) {
      if (source.contains(folded)) return true;
      final reversed = String.fromCharCodes(source.runes.toList().reversed);
      if (reversed.contains(folded)) return true;
    }
    return false;
  }

  /// "abcabcabc", "12121212", "20242024": 1-4 karakterlik parçanın tekrarı.
  static bool _isRepeatedChunk(String folded) {
    final chars = folded.runes.toList();
    for (var size = 1; size <= 4; size++) {
      if (chars.length % size != 0 || chars.length ~/ size < 2) continue;
      final chunk = String.fromCharCodes(chars.sublist(0, size));
      if (chunk * (chars.length ~/ size) == folded) return true;
    }
    return false;
  }

  /// 8 rakamlı doğum tarihi biçimleri: GGAAYYYY / YYYYAAGG (1900-2099).
  static bool _isDateLike(String folded) {
    if (!RegExp(r'^\d{8}$').hasMatch(folded)) return false;
    bool day(int d) => d >= 1 && d <= 31;
    bool month(int m) => m >= 1 && m <= 12;
    bool year(int y) => y >= 1900 && y <= 2099;
    final a = <int>[
      int.parse(folded.substring(0, 2)),
      int.parse(folded.substring(2, 4)),
      int.parse(folded.substring(4)),
    ];
    if (day(a[0]) && month(a[1]) && year(a[2])) return true;
    final b = <int>[
      int.parse(folded.substring(0, 4)),
      int.parse(folded.substring(4, 6)),
      int.parse(folded.substring(6)),
    ];
    return year(b[0]) && month(b[1]) && day(b[2]);
  }

  static bool _isTrivialPattern(String candidate) {
    if (candidate.length < 4) return false;
    return candidate.runes.toSet().length <= 1 ||
        _isRepeatedChunk(candidate) ||
        _isSequence(candidate) ||
        _isDateLike(candidate);
  }
}
