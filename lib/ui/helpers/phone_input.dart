import 'package:flutter/services.dart';

/// Türkiye telefon girişi: `+90` hazır gelir, kalan 10 hane 3-3-2-2 gruplanır ("+90 506 123 45 67").
/// Sunucu biçimi `+905061234567`'dir ([phoneToApi]).
///
/// İki tür alan vardır (tek uygulama, `mobileOnly` ile ayrılır):
///  - KİŞİSEL alanlar (kişi, sakin, hesap, profil): yalnız cep telefonu, ilk hane 5 ("+90 5XX XXX XX XX").
///  - İŞ / İLETİŞİM alanları (firma, tedarikçi, görevli, platform iletişimi): sabit hat da olur, ilk hane 2, 3, 4 veya 5
///    ("+90 XXX XXX XX XX", örn. +90 212 123 45 67). Çağıran `mobileOnly: false` verir.
///
/// [PhoneInputFormatter] alanı bu biçime zorlar, [validatePhoneInput] eksik / biçim dışı numarayı kaydettirmez.
const String phonePrefix = '+90';

/// Alanın başlangıç metni: `+90 ` hazır (kullanıcı yalnız 10 haneyi yazar).
const String phoneFieldSeed = '$phonePrefix ';

/// Yerel numaranın hane sayısı (+90'dan sonra). Fazlası girişte reddedilir.
const int phoneLocalDigitCount = 10;

/// Cep telefonu yerel numarası bu haneyle başlar (5XX).
const String phoneMobileLead = '5';

/// İş / iletişim alanında izin verilen ilk haneler: alan kodları (2, 3, 4) ve cep (5).
const String phoneAnyLeads = '2345';

/// Alan boşken görünen yer tutucu biçim (kişisel / cep).
const String phoneFieldHint = '+90 5__ ___ __ __';

/// Alan boşken görünen yer tutucu biçim (iş / iletişim: sabit hat da olur).
const String phoneFieldHintAny = '+90 2__ ___ __ __';

/// Biçim dışı numara için tek hata metni (kişisel / cep).
const String phoneFormatError = 'Telefonu +90 5XX XXX XX XX biçiminde girin (örn. +90 506 123 45 67).';

/// Biçim dışı numara için tek hata metni (iş / iletişim).
const String phoneFormatErrorAny = 'Telefonu +90 XXX XXX XX XX biçiminde girin (örn. +90 212 123 45 67).';

/// Alan türüne göre yer tutucu.
String phoneHint({bool mobileOnly = true}) => mobileOnly ? phoneFieldHint : phoneFieldHintAny;

/// Alan türüne göre hata metni.
String phoneErrorText({bool mobileOnly = true}) => mobileOnly ? phoneFormatError : phoneFormatErrorAny;

/// Yerel numaranın ilk hanesi alan türüne uyuyor mu (kişisel: 5; iş / iletişim: 2, 3, 4, 5)? Boş numara uymaz.
bool phoneLeadAllowed(String digits, {bool mobileOnly = true}) {
  if (digits.isEmpty) return false;
  final leads = mobileOnly ? phoneMobileLead : phoneAnyLeads;
  return leads.contains(digits[0]);
}

/// Metinden yerel haneleri çıkarır. Ülke kodu (`+90` / `0090` / `90`) YALNIZ BİR KEZ ve yalnız baştan,
/// ardından baştaki tek `0` (alan kodu öneki) soyulur. Fazla hane KIRPILMAZ: 10'dan uzun sonuç
/// [validatePhoneField] tarafından hata sayılır (yapıştırma kazalarında yanlış numara kaydolmaz).
String phoneLocalDigits(String? text) {
  final raw = (text ?? '').trim();
  if (raw.isEmpty) return '';
  var digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return '';
  if (raw.startsWith('+')) {
    // "+90 ..." (yazarken öneki alan korur).
    if (digits.startsWith('90')) digits = digits.substring(2);
  } else if (digits.startsWith('0090')) {
    digits = digits.substring(4);
  } else if (digits.startsWith('90') && digits.length > 10) {
    // Artı işaretsiz "905321234567": ülke kodu ancak numara 10 haneyi aşıyorsa ülke kodudur.
    digits = digits.substring(2);
  }
  if (digits.startsWith('0')) digits = digits.substring(1);
  return digits;
}

/// 3-3-2-2 gruplama: "5551234567" -> "555 123 45 67" (eksik hane varsa eldeki kadar; 10'dan fazla hane
/// kırpılmadan sona eklenir ki fazlalık kullanıcıya görünsün).
String groupPhoneDigits(String digits) {
  const groups = <int>[3, 3, 2, 2];
  final parts = <String>[];
  var index = 0;
  for (final size in groups) {
    if (index >= digits.length) break;
    final end = index + size > digits.length ? digits.length : index + size;
    parts.add(digits.substring(index, end));
    index = end;
  }
  if (index < digits.length) parts.add(digits.substring(index));
  return parts.join(' ');
}

/// Alanda görünen biçim: "+90 555 123 45 67" (hane yoksa yalnız "+90 ").
String formatPhoneField(String? text) {
  final digits = phoneLocalDigits(text);
  if (digits.isEmpty) return phoneFieldSeed;
  return '$phonePrefix ${groupPhoneDigits(digits)}';
}

/// Salt okunur gösterim: sunucudan gelen telefon ayrıştırılabiliyorsa gruplanır, aksi halde olduğu
/// gibi gösterilir (hesabı olan kişinin telefonu `users` tablosundan gelir ve serbest biçimli olabilir).
String formatPhoneDisplay(String? phone) {
  final raw = (phone ?? '').trim();
  if (raw.isEmpty) return '';
  final digits = phoneLocalDigits(raw);
  if (digits.length == 10 && RegExp(r'^[1-9]').hasMatch(digits)) {
    return '$phonePrefix ${groupPhoneDigits(digits)}';
  }
  return raw;
}

/// Düzenlenebilir alanın başlangıç metni: boşsa "+90 ", ayrıştırılabilen numara gruplanmış, ayrıştırılamayan
/// eski serbest değer OLDUĞU GİBİ (yabancı numara "+90" ile yeniden yazılmaz; dokunulmazsa aynen kalır).
String phoneFieldInitial(String? stored) {
  final raw = (stored ?? '').trim();
  return raw.isEmpty ? phoneFieldSeed : formatPhoneDisplay(raw);
}

/// Sunucuya gidecek değer: `+905551234567`; hane girilmediyse null (alan boş sayılır).
String? phoneToApi(String? text) {
  final digits = phoneLocalDigits(text);
  if (digits.isEmpty) return null;
  return '$phonePrefix$digits';
}

/// Doğrulama: boş serbest; doluysa tam 10 hane olmalı ve ilk hane alan türüne uymalı (kişisel: 5; iş / iletişim:
/// 2-5; eksik ya da FAZLA hane hatadır). Hata yoksa null.
String? validatePhoneField(String? text, {bool mobileOnly = true}) {
  final digits = phoneLocalDigits(text);
  if (digits.isEmpty) return null;
  if (digits.length != phoneLocalDigitCount || !phoneLeadAllowed(digits, mobileOnly: mobileOnly)) {
    return phoneErrorText(mobileOnly: mobileOnly);
  }
  return null;
}

/// [validatePhoneField]; ama alan başlangıç değeriyle aynıysa (eski sabit hat / serbest kayıt) hata vermez:
/// başka bir alanı düzeltmek isteyen yönetici eski numara yüzünden kaydedemez duruma düşmez.
String? validatePhoneInput(String? text, {String? stored, bool mobileOnly = true}) {
  if ((text ?? '').trim() == phoneFieldInitial(stored).trim()) return null;
  return validatePhoneField(text, mobileOnly: mobileOnly);
}

/// Kaydedilecek değer: alan başlangıçtaki gibiyse kayıtlı değer aynen (null/boş -> null), değiştiyse
/// [phoneToApi].
String? phoneForSave(String text, {String? stored}) {
  if (text.trim() == phoneFieldInitial(stored).trim()) {
    final raw = (stored ?? '').trim();
    return raw.isEmpty ? null : raw;
  }
  return phoneToApi(text);
}

/// Gruplu biçimle saklanan alanlar için (platform destek / iletişim telefonu yasal belgelere girer: "+90 212 123 45 67"):
/// alan başlangıçtaki gibiyse kayıtlı değer aynen, değiştiyse gruplu "+90 XXX XXX XX XX"; hane yoksa boş metin.
String phoneGroupedForSave(String text, {String? stored}) {
  if (text.trim() == phoneFieldInitial(stored).trim()) return (stored ?? '').trim();
  return phoneToApi(text) == null ? '' : formatPhoneField(text);
}

/// Yapıştırılan parça tam bir numara mı (ülke kodu ya da alan kodu öneki taşıyor)?
bool _looksLikeFullNumber(String inserted) {
  final trimmed = inserted.trim();
  if (trimmed.isEmpty) return false;
  if (trimmed.startsWith('+') || trimmed.startsWith('00')) return true;
  final digits = trimmed.replaceAll(RegExp(r'\D'), '');
  return digits.length >= 11 && (digits.startsWith('0') || digits.startsWith('90'));
}

/// Alanı "+90 XXX XXX XX XX" biçimine zorlar: `+90` öneki silinemez, haneler 3-3-2-2 gruplanır.
///
/// - En çok 10 hane: fazlasını ekleyen giriş (yazma / yapıştırma) reddedilir, alan değişmez.
/// - İlk hane: [mobileOnly] (varsayılan) iken 5; değilken 2, 3, 4 veya 5. Boş ya da uygun haneyle başlayan alan uygun
///   olmayan bir haneyle başlayamaz (giriş reddedilir). Eski kayıttan gelen uygun olmayan başlangıçlı değer (örn. kişisel
///   alanda sabit hat) silinip düzeltilebilir (kısaltan giriş her zaman kabul).
/// - Yazma / silme: imleç, kendisinden SONRAKİ hane sayısı korunarak yeniden konur (ortadan düzeltme
///   imleci sona atmaz).
/// - Yapıştırma: yapıştırılan parça ülke kodu ("+90", "0090", "90") ya da baştaki "0" taşıyan TAM bir
///   numaraysa alanın tüm içeriği o numarayla değişir ("+90 " alanına "+905321234567" yapıştırmak
///   "90905321234567" üretmez); aynı numarayı iki kez yapıştırmak da tek numara bırakır.
class PhoneInputFormatter extends TextInputFormatter {
  const PhoneInputFormatter({this.mobileOnly = true});

  /// true: yalnız cep (ilk hane 5); false: sabit hat da olur (ilk hane 2-5).
  final bool mobileOnly;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text == oldValue.text) return newValue;

    // Sona eklenen parça (yapıştırma): yeni metin eski metinle başlıyorsa kalan kısım. Ortadan ekleme /
    // silme / tüm metni değiştirme bu dala girmez (aşağıda yeni metnin kendisi işlenir).
    final inserted = newValue.text.startsWith(oldValue.text)
        ? newValue.text.substring(oldValue.text.length)
        : '';
    final newText = newValue.text;

    final String source;
    final bool replacedAll;
    if (inserted.length >= 2 && _looksLikeFullNumber(inserted)) {
      source = inserted;
      replacedAll = true;
    } else {
      source = newText;
      replacedAll = false;
    }

    final digits = phoneLocalDigits(source);
    final before = phoneLocalDigits(oldValue.text);
    if (digits.length > phoneLocalDigitCount && digits.length >= before.length) return oldValue;
    if (digits.isNotEmpty &&
        !phoneLeadAllowed(digits, mobileOnly: mobileOnly) &&
        (before.isEmpty || phoneLeadAllowed(before, mobileOnly: mobileOnly))) {
      return oldValue;
    }
    final formatted = formatPhoneField(source);
    if (replacedAll) {
      return TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    }

    // İmleç: kendisinden sonraki hane sayısı korunur.
    final caret = newValue.selection.isValid
        ? newValue.selection.end.clamp(0, newText.length)
        : newText.length;
    final digitsAfter = RegExp(r'\d').allMatches(newText.substring(caret)).length;
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: _caretFor(formatted, digitsAfter)),
    );
  }

  /// [formatted] içinde kendisinden sonra [digitsAfter] hane kalan konum (öneki ("+90 ") aşmaz).
  static int _caretFor(String formatted, int digitsAfter) {
    var remaining = digitsAfter;
    for (var i = formatted.length; i > phoneFieldSeed.length; i--) {
      if (remaining == 0) return i;
      if (RegExp(r'\d').hasMatch(formatted[i - 1])) remaining--;
    }
    return phoneFieldSeed.length;
  }
}

// ---------------------------------------------------------------------------------------------------------------
// Servis telefonu (faydalı telefon, firma, tedarikçi): kısa / özel numara ISTISNASI
// ---------------------------------------------------------------------------------------------------------------

/// Faydalı telefon listesindeki acil / kısa / özel numaralar (112, 185) ile firma çağrı hatları (444 1 234) "+90 + 10 hane"
/// biçimine sığmaz.
/// KISA NUMARA: yalnız rakam, boşluk ve tireden oluşur (artı yok) ve 3-7 haneden ibarettir; "444" ile başlayan
/// 444'lü hatlar (7 hane) bu kapsamdadır. Bunlar olduğu gibi kabul edilir; diğer her şey "+90" iş / iletişim kuralına
/// (sabit hat ya da cep, 10 hane) uyar. YALNIZ Kadro > Faydalı telefon, sözleşme firması ve tedarikçi telefonlarında kullanılır
/// (görevli, platform iletişimi ve kişisel alanlar kısa numara kabul etmez).
bool isShortServiceNumber(String? text) {
  final raw = (text ?? '').trim();
  if (raw.isEmpty || !RegExp(r'^[\d\s\-]+$').hasMatch(raw)) return false;
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  return digits.length >= 3 && digits.length <= 7;
}

/// Servis telefonu alanının başlangıç metni: boşsa BOŞ (kısa numara da yazılabilsin diye "+90 " hazır gelmez),
/// kısa numara olduğu gibi, diğerleri [phoneFieldInitial] gibi.
String servicePhoneInitial(String? stored) {
  final raw = (stored ?? '').trim();
  if (raw.isEmpty) return '';
  if (isShortServiceNumber(raw)) return raw;
  return phoneFieldInitial(raw);
}

/// Servis telefonu doğrulaması: boş ya da kısa numara serbest; başlangıç değeriyle aynıysa (eski serbest kayıt) hata yok;
/// değilse iş / iletişim kuralı ([validatePhoneField] `mobileOnly: false`).
String? validateServicePhoneInput(String? text, {String? stored}) {
  final value = (text ?? '').trim();
  if (value.isEmpty || isShortServiceNumber(value)) return null;
  if (value == servicePhoneInitial(stored).trim()) return null;
  return validatePhoneField(value, mobileOnly: false);
}

/// Servis telefonunun kaydedilecek değeri: kısa numara yazıldığı gibi (boşluklar teke indirilir), alan başlangıçtaki gibiyse
/// kayıtlı değer aynen, diğerleri `+905321234567`; boşsa null.
String? servicePhoneForSave(String text, {String? stored}) {
  final value = text.trim();
  if (value.isEmpty) return null;
  if (isShortServiceNumber(value)) return value.replaceAll(RegExp(r'\s+'), ' ');
  if (value == servicePhoneInitial(stored).trim()) {
    final raw = (stored ?? '').trim();
    return raw.isEmpty ? null : raw;
  }
  return phoneToApi(value);
}

/// Servis telefonu alanının giriş denetleyicisi: kısa numara olabileceği sürece (artı yok, en çok 7 hane) yazılanı olduğu
/// gibi bırakır (yalnız rakam / boşluk / tire), numara kısa numara olamayacak kadar uzayınca ya da "+" ile başlayınca
/// [PhoneInputFormatter] (`mobileOnly: false`) devralır ve alan "+90 XXX XXX XX XX" olur. "+90" biçimindeki alan silinerek boşaltılırsa
/// yeniden kısa numara yazılabilir.
class ServicePhoneInputFormatter extends TextInputFormatter {
  const ServicePhoneInputFormatter();

  static const PhoneInputFormatter _full = PhoneInputFormatter(mobileOnly: false);

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text == oldValue.text) return newValue;
    final text = newValue.text;
    if (text.isEmpty) return newValue; // tümünü silmek her zaman serbest
    final formattedMode = oldValue.text.trimLeft().startsWith('+') || text.trimLeft().startsWith('+');
    if (formattedMode) {
      final result = _full.formatEditUpdate(oldValue, newValue);
      // Silerek boşaltma: yalnız "+90 " kalırsa alan tümüyle boşalır (kısa numara yeniden yazılabilsin).
      if (text.length < oldValue.text.length && result.text == phoneFieldSeed) {
        return const TextEditingValue(text: '', selection: TextSelection.collapsed(offset: 0));
      }
      return result;
    }
    if (!RegExp(r'^[\d\s\-]*$').hasMatch(text)) return oldValue;
    final digits = text.replaceAll(RegExp(r'\D'), '');
    if (digits.length <= 7) return newValue;
    // Kısa numara olamayacak kadar uzadı: "+90" biçimine geçer (ilk hane / 10 hane kuralları [PhoneInputFormatter]'da).
    // Reddedilirse (uygun olmayan ilk hane) alan yazılmadan önceki haliyle kalır.
    final converted = _full.formatEditUpdate(const TextEditingValue(), newValue);
    return converted.text.isEmpty ? oldValue : converted;
  }
}
