// Firma ve Sözleşme Takibi formlarının doğrulayıcıları (saf işlevler; form alanları ve birim testleri kullanır).
//
// Tarihler "GG.AA.YYYY" metnidir ([DateInputFormatter]; uygulamada Türkçe tarih seçici yoktur). Tutar [parseMoney]
// ile KESİN kuruşa çevrilir (virgül ondalık; sıfır serbest, negatif reddedilir). Uzunluklar kırpılmış metnin kod
// noktası sayısıdır (sunucuyla aynı birim). Hata yoksa null döner.
import 'package:site_kapi_kontrol/ui/helpers/date_input.dart';
import 'package:site_kapi_kontrol/ui/helpers/money.dart';
import 'package:site_kapi_kontrol/ui/helpers/text_length.dart';

/// Zorunlu serbest metin: boş olamaz, en çok [max] karakter.
String? contractRequiredText(
  String? value,
  int max, {
  String emptyMessage = 'Bu alan boş olamaz.',
}) {
  final length = trimmedCodePoints(value ?? '');
  if (length < 1) return emptyMessage;
  if (length > max) return 'En çok $max karakter olabilir.';
  return null;
}

/// İsteğe bağlı serbest metin: en çok [max] karakter.
String? contractOptionalText(String? value, int max) {
  if (trimmedCodePoints(value ?? '') > max) {
    return 'En çok $max karakter olabilir.';
  }
  return null;
}

/// Başlangıç tarihi: zorunlu, geçerli "GG.AA.YYYY".
/// Sunucunun kabul ettiği en küçük yıl (sözleşme tarihleri 1990-2100).
const int kContractMinYear = 1990;

String? _yearError(DateTime? date) =>
    date != null && date.year < kContractMinYear
        ? 'Tarih $kContractMinYear-$dateInputMaxYear arasında olmalı.'
        : null;

String? contractStartDateError(String? text) {
  if ((text ?? '').trim().isEmpty) return 'Başlangıç tarihini girin (GG.AA.YYYY).';
  return validateDateField(text) ?? _yearError(parseDateField(text));
}

/// Bitiş tarihi: boş serbest (süresiz sözleşme); doluysa geçerli ve başlangıçtan önce olmamalı (aynı gün olabilir).
String? contractEndDateError(String? endText, String? startText) {
  final value = (endText ?? '').trim();
  if (value.isEmpty) return null;
  final format = validateDateField(value);
  if (format != null) return format;
  final end = parseDateField(value);
  final year = _yearError(end);
  if (year != null) return year;
  final start = parseDateField(startText);
  if (end != null && start != null && end.isBefore(start)) {
    return 'Bitiş tarihi başlangıç tarihinden önce olamaz.';
  }
  return null;
}

/// Gün sayısı alanı (fesih bildirimi 0..365, hatırlatma 0..180): zorunlu, yalnız rakam, aralıkta.
String? contractDayCountError(String? text, {required int max}) {
  final value = (text ?? '').trim();
  if (value.isEmpty) return 'Gün sayısını girin (0-$max).';
  if (!RegExp(r'^\d+$').hasMatch(value)) {
    return 'Gün sayısını yalnız rakamla girin (0-$max).';
  }
  // Çok uzun rakam dizisi int'e sığmayabilir: önce uzunluk.
  if (value.length > 4 || int.parse(value) > max) {
    return 'En çok $max gün olabilir.';
  }
  return null;
}

/// Geçerli gün sayısı; geçersizse null.
int? parseContractDayCount(String? text, {required int max}) {
  if (contractDayCountError(text, max: max) != null) return null;
  return int.parse(text!.trim());
}

/// Tutar: boş serbest (belirtilmedi); doluysa sıfır ya da pozitif, en çok 2 ondalık ("1.250,50").
String? contractAmountError(String? text) =>
    validateMoneyInput(text, required: false, allowZero: true);

/// Alan metninden kuruş; boşsa ya da geçersizse null.
int? contractAmountFromField(String? text) {
  if ((text ?? '').trim().isEmpty) return null;
  return parseMoney(text, allowZero: true).minor;
}

final RegExp _emailPattern = RegExp(r'^[^\s@,;<>"()]+@[^\s@,;<>"()]+\.[^\s@,;<>"()]+$');

/// Firma e-postası: boş serbest; doluysa geçerli biçim ve en çok [max] karakter.
String? contractVendorEmailError(String? text, {int max = 254}) {
  final value = (text ?? '').trim();
  if (value.isEmpty) return null;
  if (value.runes.length > max) return 'En çok $max karakter olabilir.';
  if (!_emailPattern.hasMatch(value) || value.contains('..')) {
    return 'Geçerli bir e-posta adresi girin (örn. destek@firma.com).';
  }
  return null;
}

/// Firma telefonu: boş serbest; doluysa rakam, boşluk ve + ( ) - . / ile 3-20 hane (sabit hat, santral, 444 numarası ve
/// cep telefonu birlikte kabul edilir; sunucu kuralıyla aynı).
String? contractVendorPhoneError(String? text, {int max = 32}) {
  final value = (text ?? '').trim();
  if (value.isEmpty) return null;
  if (value.runes.length > max) return 'En çok $max karakter olabilir.';
  if (!RegExp(r'^[0-9+()\-./\s]+$').hasMatch(value)) {
    return 'Telefonu rakamla girin; yalnız boşluk ve + ( ) - . / kullanılabilir (örn. 0212 555 12 34).';
  }
  final digits = value.replaceAll(RegExp(r'\D'), '').length;
  if (digits < 3 || digits > 20) {
    return 'Telefon numarası 3-20 haneli olmalı.';
  }
  return null;
}

/// Firma vergi / kimlik numarası: boş serbest; doluysa harf, rakam, boşluk ve tire, en çok [max] karakter (sunucu
/// kuralıyla aynı).
String? contractVendorTaxNoError(String? text, {int max = 20}) {
  final value = (text ?? '').trim();
  if (value.isEmpty) return null;
  if (value.length > max) return 'En çok $max karakter olabilir.';
  if (!RegExp(r'^[0-9A-Za-z -]+$').hasMatch(value)) {
    return 'Vergi numarasında yalnız harf, rakam, boşluk ve tire kullanılabilir.';
  }
  return null;
}

/// `tel:` adresi için telefon metni ("+90 212 555 12 34" -> "+902125551234"); hane yoksa null.
String? contractDialable(String? phone) {
  final value = (phone ?? '').trim();
  if (value.isEmpty) return null;
  final plus = value.startsWith('+');
  final digits = value.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return null;
  return plus ? '+$digits' : digits;
}
