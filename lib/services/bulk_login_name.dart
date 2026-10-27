// Toplu yükleme: kullanıcı (giriş) adı kuralları — sunucudaki `bulk_import_login_names.js` ile AYNI vektörler.
//
// Şablonda «Kullanıcı Adı» sütunu yoktur: sistem her yeni hesap için Ad Soyad'dan bir ad önerir (sunucu belirler; sistemde ya da dosyada alınmışsa `_2`, `_3` ...),
// yönetici önizleme tablosunda değiştirebilir. Değişiklik, sunucudaki denetimi geçmeden kabul edilmez. Bu dosya yalnız BİÇİM kuralını ve tarayıcıda anında
// verilen ilk denetimi taşır; kullanılabilirliği (başka site / şehir dahil) yalnız sunucu bilir.

/// Kullanıcı adı en az / en çok uzunluk (sunucu: people_common.js LOGIN_NAME_MIN / LOGIN_NAME_MAX).
const int kLoginNameMin = 3;
const int kLoginNameMax = 40;

/// Kullanıcı adı tabanı üst sınırı: LOGIN_NAME_MAX (40) - «_NNN» benzersizlik eki payı. Sunucu AYNI sınırı uygular.
const int kLoginNameBaseMax = 36;

const Map<String, String> _turkishFold = <String, String>{
  'ç': 'c', 'Ç': 'c',
  'ğ': 'g', 'Ğ': 'g',
  'ı': 'i', 'I': 'i', 'İ': 'i',
  'ö': 'o', 'Ö': 'o',
  'ş': 's', 'Ş': 's',
  'ü': 'u', 'Ü': 'u',
};

String _foldTurkish(String text) {
  final out = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    final char = text[i];
    out.write(_turkishFold[char] ?? char);
  }
  return out.toString();
}

/// Ad soyad veya yazılan metinden kullanıcı adı tabanı. Sunucudaki `slugifyLoginName` ile AYNI kural: Türkçe harfler sadeleşir, küçük harf,
/// [a-z0-9] dışındaki her öbek tek nokta, baş/son nokta atılır, en çok 36 karakter; boşsa yedek (ya da «kullanici»).
/// [existing] verilirse çakışmada `_2`, `_3` ... eklenir (sunucudaki varyasyonla aynı biçim) ve ad kümeye eklenir.
///
/// Kişi hesabı penceresi (tek kişi için ad önerisi) bunu kullanır; toplu yüklemede adı SUNUCU verir.
String generateUsernameFromFullName(
  String fullName, {
  Set<String>? existing,
  String? fallback,
}) {
  var s = fullName.trim();
  if (s.isEmpty) {
    s = (fallback != null && fallback.trim().isNotEmpty) ? fallback.trim() : 'kullanici';
  }
  var clean = _foldTurkish(s).toLowerCase();
  clean = clean.replaceAll(RegExp(r'[^a-z0-9]+'), '.').replaceAll(RegExp(r'^\.+|\.+$'), '');
  if (clean.length > kLoginNameBaseMax) {
    clean = clean.substring(0, kLoginNameBaseMax).replaceAll(RegExp(r'\.+$'), '');
  }
  if (clean.isEmpty) {
    clean = 'kullanici';
  }
  if (existing == null) return clean;

  var candidate = clean;
  var counter = 2;
  while (existing.contains(candidate.toLowerCase())) {
    candidate = '${clean}_$counter';
    counter++;
  }
  existing.add(candidate.toLowerCase());
  return candidate;
}

/// Yazılan kullanıcı adının biçim hatası (yok = geçerli).
enum LoginNameFormatError { empty, tooShort, tooLong, chars }

/// Yöneticinin tabloya yazdığı ad: kırp, Türkçe harfler sadeleşir, küçük harf, boşluk öbeği nokta olur; sistem kuralı uygulanır (3-40 karakter, yalnız
/// [a-z0-9._-]). Sunucudaki `normalizeTypedLoginName` ile AYNI: `_` ve `-` KORUNUR (önerilen `ahmet.yilmaz_2` yazıldığı gibi kalır).
({String? value, LoginNameFormatError? error}) normalizeTypedLoginName(String raw) {
  final text = _foldTurkish(raw.trim()).toLowerCase().replaceAll(RegExp(r'\s+'), '.');
  if (text.isEmpty) return (value: null, error: LoginNameFormatError.empty);
  if (text.length < kLoginNameMin) return (value: text, error: LoginNameFormatError.tooShort);
  if (text.length > kLoginNameMax) return (value: text, error: LoginNameFormatError.tooLong);
  if (!RegExp(r'^[a-z0-9._-]+$').hasMatch(text)) return (value: text, error: LoginNameFormatError.chars);
  return (value: text, error: null);
}

/// Biçim hatasının kullanıcıya gösterilen metni (sunucudaki `loginNameReason` ile aynı).
String loginNameFormatMessage(LoginNameFormatError error) => switch (error) {
  LoginNameFormatError.empty => 'Kullanıcı adı boş olamaz.',
  LoginNameFormatError.tooShort => 'Kullanıcı adı en az $kLoginNameMin karakter olmalı.',
  LoginNameFormatError.tooLong => 'Kullanıcı adı en çok $kLoginNameMax karakter olabilir.',
  LoginNameFormatError.chars =>
    'Kullanıcı adında yalnız harf, rakam, nokta (.), alt çizgi (_) ve tire (-) olabilir; boşluk ve @ kullanılamaz.',
};

/// Eski şablonların «Kullanıcı Adı» sütun başlıkları (Türkçe katlanmış, noktalama sadeleşmiş): artık şablonda yoktur, dosyada bulunursa yok sayılır
/// ve yönetici bilgilendirilir.
const Set<String> kLegacyLoginNameHeaders = <String>{
  'kullanici adi',
  'giris adi',
  'username',
  'user name',
  'kullanici',
  'hesap adi',
};
