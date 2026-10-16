import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/money.dart';

/// Tutar giriş alanı (Platform Faz 4a). "1.250,50" biçimini KESİN olarak kuruşa çevirir ([parseMoney]):
/// virgül ya da nokta ondalık olabilir, 3 ve üstü ondalık, negatif, boş, sıfır ve aşırı büyük tutar
/// REDDEDİLİR (sessiz yuvarlama / kırpma yok). Yazarken alanın altında ayrıştırılan tutar gösterilir
/// ("Girilen tutar: 1.250,50 ₺"), böylece yanlış anlaşılan ayırıcı gönderimden ÖNCE fark edilir.
///
/// Klavye sayısaldır; yapıştırılan metinden yalnız rakam, nokta, virgül, boşluk, artı/eksi ve "₺" korunur
/// (eksi işareti bilerek korunur: doğrulayıcı "negatif olamaz" der, sessizce işaret düşürülmez).
///
/// DİKKAT: [key] ZORUNLUDUR. İçindeki `TextFormField` durumlu olduğundan, anahtarsız kullanılırsa üst `Column`
/// çocuk listesi değiştiğinde (örn. doğrulama özeti eklenince) eleman yeniden kurulur ve alanın doğrulama hatası
/// kaybolur (Flutter anahtarsız ara çocukları yeniden kullanmaz).
class MoneyFormField extends StatelessWidget {
  const MoneyFormField({
    required Key super.key,
    required this.controller,
    required this.label,
    this.fieldKey,
    this.enabled = true,
    this.required = true,
    this.allowZero = false,
    this.maxMinor = kMaxMoneyMinor,
    this.helperText,
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
    this.showPreview = true,
  });

  final TextEditingController controller;
  final String label;

  /// İçteki `TextFormField`ın anahtarı (testler ve kaydırma için).
  final Key? fieldKey;
  final bool enabled;
  final bool required;
  final bool allowZero;
  final int maxMinor;
  final String? helperText;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool showPreview;

  /// Girişten izin verilen karakterler.
  static final RegExp allowed = RegExp('[0-9.,+\\-−₺ ]');

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          key: fieldKey,
          controller: controller,
          enabled: enabled,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textInputAction: textInputAction,
          onChanged: onChanged,
          onFieldSubmitted: onSubmitted,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.allow(allowed),
            LengthLimitingTextInputFormatter(24),
          ],
          autovalidateMode: AutovalidateMode.onUserInteraction,
          decoration: InputDecoration(
            labelText: label,
            hintText: '1.250,50',
            suffixText: kMoneySymbol,
            prefixIcon: const Icon(Icons.payments_rounded),
            helperText: helperText,
            helperMaxLines: 4,
          ),
          validator: (value) => validateMoneyInput(
            value,
            required: required,
            maxMinor: maxMinor,
            allowZero: allowZero,
          ),
        ),
        if (showPreview)
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              final parsed = parseMoney(value.text, maxMinor: maxMinor, allowZero: allowZero);
              final minor = parsed.minor;
              if (minor == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: AppSpace.xs, left: AppSpace.md),
                child: Semantics(
                  label: 'Girilen tutar: ${moneySemanticLabel(minor)}',
                  child: ExcludeSemantics(
                    child: Text(
                      'Girilen tutar: ${formatMinor(minor)}',
                      key: const ValueKey<String>('money_preview'),
                      style: th.bodySmall?.copyWith(
                        color: p.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}
