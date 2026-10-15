import 'package:flutter/services.dart';

/// Türkiye telefon girişi (Platform Faz 2a): `+90` hazır gelir, kalan 10 hane 3-3-2-2 gruplanır
/// ("+90 555 123 45 67"). Sunucu biçimi `+905551234567`'dir ([phoneToApi]).
///
/// NOT: kayıt sayfasında paylaşılabilir bir telefon alanı deseni yoktur (ham `TextFormField` +
/// düzenli ifade doğrulaması); bu yardımcı o boşluğu kapatır ve yalnız CRM diyaloglarında kullanılır.
const String phonePrefix = '+90';

/// Alanın başlangıç metni: `+90 ` hazır (kullanıcı yalnız 10 haneyi yazar).
const String phoneFieldSeed = '$phonePrefix ';

/// Alana yazılabilecek en çok yerel hane (fazlası girişte reddedilir; ondan azı ama 10'dan çoğu
/// doğrulama hatası olarak görünür, SESSİZCE KIRPILMAZ).
const int phoneMaxLocalDigits = 15;

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

/// Sunucuya gidecek değer: `+905551234567`; hane girilmediyse null (alan boş sayılır).
String? phoneToApi(String? text) {
  final digits = phoneLocalDigits(text);
  if (digits.isEmpty) return null;
  return '$phonePrefix$digits';
}

/// Doğrulama: boş serbest; doluysa tam 10 hane olmalı ve 0 ile başlamamalı (eksik ya da FAZLA hane
/// hatadır). Hata yoksa null.
String? validatePhoneField(String? text) {
  final digits = phoneLocalDigits(text);
  if (digits.isEmpty) return null;
  if (digits.length != 10 || digits.startsWith('0')) {
    return 'Telefon +90 ile 10 haneli olmalı (örn. 555 123 45 67).';
  }
  return null;
}

/// Yapıştırılan parça tam bir numara mı (ülke kodu ya da alan kodu öneki taşıyor)?
bool _looksLikeFullNumber(String inserted) {
  final trimmed = inserted.trim();
  if (trimmed.isEmpty) return false;
  if (trimmed.startsWith('+') || trimmed.startsWith('00')) return true;
  final digits = trimmed.replaceAll(RegExp(r'\D'), '');
  return digits.length >= 11 && (digits.startsWith('0') || digits.startsWith('90'));
}

/// Yazarken `+90` önekini korur ve haneleri 3-3-2-2 gruplar.
///
/// - Yazma / silme: imleç, kendisinden SONRAKİ hane sayısı korunarak yeniden konur (ortadan düzeltme
///   imleci sona atmaz).
/// - Yapıştırma: yapıştırılan parça ülke kodu ("+90", "0090", "90") ya da baştaki "0" taşıyan TAM bir
///   numaraysa alanın tüm içeriği o numarayla değişir ("+90 " alanına "+905321234567" yapıştırmak
///   "90905321234567" üretmez); aynı numarayı iki kez yapıştırmak da tek numara bırakır.
/// - 10'dan fazla hane sessizce kırpılmaz, görünür kalır ve doğrulama hatası verir; [phoneMaxLocalDigits]
///   üstü giriş reddedilir.
class PhoneInputFormatter extends TextInputFormatter {
  const PhoneInputFormatter();

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
    if (digits.length > phoneMaxLocalDigits) return oldValue;
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
