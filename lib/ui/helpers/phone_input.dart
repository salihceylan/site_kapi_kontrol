import 'package:flutter/services.dart';

/// Türkiye telefon girişi (Platform Faz 2a): `+90` hazır gelir, kalan 10 hane 3-3-2-2 gruplanır
/// ("+90 555 123 45 67"). Sunucu biçimi `+905551234567`'dir ([phoneToApi]).
///
/// NOT: kayıt sayfasında paylaşılabilir bir telefon alanı deseni yoktur (ham `TextFormField` +
/// düzenli ifade doğrulaması); bu yardımcı o boşluğu kapatır ve yalnız CRM diyaloglarında kullanılır.
const String phonePrefix = '+90';

/// Alanın başlangıç metni: `+90 ` hazır (kullanıcı yalnız 10 haneyi yazar).
const String phoneFieldSeed = '$phonePrefix ';

/// Metinden yerel 10 haneyi çıkarır. `+90`/`90` ülke kodu ve baştaki `0` atılır; en çok 10 hane.
String phoneLocalDigits(String? text) {
  final raw = (text ?? '').trim();
  if (raw.isEmpty) return '';
  var digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return '';
  if (raw.startsWith('+') || raw.startsWith('00')) {
    if (digits.startsWith('00')) digits = digits.substring(2);
    if (digits.startsWith('90')) digits = digits.substring(2);
  } else if (digits.startsWith('90') && digits.length > 10) {
    digits = digits.substring(2);
  } else if (digits.startsWith('0') && digits.length > 10) {
    digits = digits.substring(1);
  }
  if (digits.length > 10) digits = digits.substring(0, 10);
  return digits;
}

/// 3-3-2-2 gruplama: "5551234567" -> "555 123 45 67" (eksik hane varsa eldeki kadar).
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

/// Doğrulama: boş serbest; doluysa 10 hane olmalı ve 0 ile başlamamalı. Hata yoksa null.
String? validatePhoneField(String? text) {
  final digits = phoneLocalDigits(text);
  if (digits.isEmpty) return null;
  if (digits.length != 10 || digits.startsWith('0')) {
    return 'Telefon +90 ile 10 haneli olmalı (örn. 555 123 45 67).';
  }
  return null;
}

/// Yazarken `+90` önekini korur ve haneleri 3-3-2-2 gruplar. İmleç sona alınır (sondan yazım
/// yaygın durumdur; ortadan düzenlemede imleç gruplama sonrası sona gider).
class PhoneInputFormatter extends TextInputFormatter {
  const PhoneInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final formatted = formatPhoneField(newValue.text);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
