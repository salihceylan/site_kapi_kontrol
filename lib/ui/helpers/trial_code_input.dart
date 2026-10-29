// Deneme erişim kodu girişi (P2-27, karar K10): kod 12 karakterdir ve XXXX-XXXX-XXXX biçiminde gösterilir.
import 'package:flutter/services.dart';

/// Kodun tire hariç uzunluğu (sunucu `TRIAL_CODE_LENGTH` ile aynı).
const int kTrialCodeLength = 12;

/// Girilen metni kod biçimine çevirir: büyük harf, harf / rakam dışı her şey atılır (tire, boşluk), en çok 12 karakter,
/// 4'erli gruplar tire ile ayrılır. Yapıştırılan "abcd efgh jkmn" ya da "ABCD-EFGH-JKMN" aynı sonucu verir.
String formatTrialCodeInput(String raw) {
  final cleaned = raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  final limited = cleaned.length > kTrialCodeLength ? cleaned.substring(0, kTrialCodeLength) : cleaned;
  final buffer = StringBuffer();
  for (var i = 0; i < limited.length; i++) {
    if (i > 0 && i % 4 == 0) buffer.write('-');
    buffer.write(limited[i]);
  }
  return buffer.toString();
}

/// 12 karakter girildi mi (biçimli ya da ham)?
bool isCompleteTrialCode(String text) =>
    text.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '').length == kTrialCodeLength;

/// Yazarken büyük harfe çevirir ve tireleri kendisi koyar.
class TrialCodeInputFormatter extends TextInputFormatter {
  const TrialCodeInputFormatter();

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final text = formatTrialCodeInput(newValue.text);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
