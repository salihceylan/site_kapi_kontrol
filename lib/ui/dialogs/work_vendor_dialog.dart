// Firmaya yönlendir / firma bilgisini düzenle formu (docs/PLATFORM_IS_TAKIBI.md "Firmaya yönlendirme (111)").
//
// Bu pencere AĞ ÇAĞRISI YAPMAZ: doldurulmuş [WorkVendor] ile kapanır, vazgeçilirse null. Kaydı talep ayrıntısı
// gönderir (`PATCH`: yönlendirmede durum `firmada` + firma tek çağrıda) ve sunucu hatasını kendi penceresinde
// gösterir. Dış firmaya giriş / form yoktur: bilgileri yönetici ya da görevli elle girer.
//
// Alanlar sunucu sınırlarıyla aynıdır: firma adı 2-80 (zorunlu), yetkili en çok 80, telefon (isteğe bağlı), anlaşılan
// tutar (isteğe bağlı, TL; kuruşa çevrilir).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MaxLengthEnforcement;
import 'package:site_kapi_kontrol/models/work_tracking_models.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/contract_validation.dart';
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/helpers/form_validation.dart';
import 'package:site_kapi_kontrol/ui/helpers/money.dart';
import 'package:site_kapi_kontrol/ui/helpers/phone_input.dart';
import 'package:site_kapi_kontrol/ui/helpers/text_length.dart';
import 'package:site_kapi_kontrol/ui/widgets/crm_parts.dart';

/// Sunucu sınırları (`work_tracking_common.js`: VENDOR_NAME_MAX / VENDOR_CONTACT_MAX).
const int kWorkVendorNameMin = 2;
const int kWorkVendorNameMax = 80;
const int kWorkVendorContactMax = 80;

/// Firma adı: 2-80 karakter (boşluklar kırpılır).
String? workVendorNameError(String? value) {
  final length = trimmedCodePoints(value ?? '');
  if (length < 1) return 'Firma adını girin.';
  if (length < kWorkVendorNameMin) {
    return 'Firma adı en az $kWorkVendorNameMin karakter olmalı.';
  }
  if (length > kWorkVendorNameMax) {
    return 'En çok $kWorkVendorNameMax karakter olabilir.';
  }
  return null;
}

/// Anlaşılan tutar (isteğe bağlı): boş geçerlidir; doluysa sıfırdan büyük TL tutarı.
String? workVendorAmountError(String? value) =>
    validateMoneyInput(value, required: false);

/// Formdaki metinlerden [WorkVendor] kurar (tutar çözülemezse null tutar).
WorkVendor workVendorFromForm({
  required String name,
  required String contact,
  required String phone,
  required String amount,
}) {
  final parsed = amount.trim().isEmpty ? null : parseMoney(amount).minor;
  return WorkVendor(
    name: name.trim(),
    contact: contact.trim(),
    phone: phone.trim(),
    amountKurus: parsed,
  );
}

class WorkVendorDialog extends StatefulWidget {
  const WorkVendorDialog({super.key, this.initial, required this.referral});

  /// Mevcut firma (düzenleme ya da firmadan dönen işin yeniden yönlendirmesi); yoksa boş form.
  final WorkVendor? initial;

  /// true: "Firmaya yönlendir" (kayıtla birlikte iş `Firmada` durumuna geçer); false: yalnız firma bilgisi düzenlenir.
  final bool referral;

  /// Doldurulmuş firmayla kapanır; vazgeçilirse null.
  static Future<WorkVendor?> show(
    BuildContext context, {
    WorkVendor? initial,
    required bool referral,
  }) {
    return showDialog<WorkVendor>(
      context: context,
      barrierDismissible: false,
      builder: (_) => WorkVendorDialog(initial: initial, referral: referral),
    );
  }

  @override
  State<WorkVendorDialog> createState() => _WorkVendorDialogState();
}

class _WorkVendorDialogState extends State<WorkVendorDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _name = TextEditingController(
    text: widget.initial?.name ?? '',
  );
  late final TextEditingController _contact = TextEditingController(
    text: widget.initial?.contact ?? '',
  );
  late final TextEditingController _phone = TextEditingController(
    text: servicePhoneInitial(widget.initial?.phone),
  );
  late final TextEditingController _amount = TextEditingController(
    text: widget.initial?.amountKurus == null
        ? ''
        : formatMinor(widget.initial!.amountKurus!, symbol: false),
  );
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _contact.dispose();
    _phone.dispose();
    _amount.dispose();
    super.dispose();
  }

  InputCounterWidgetBuilder _counter(TextEditingController controller, int max) =>
      (context, {required currentLength, required isFocused, maxLength}) =>
          characterCounter(context, trimmedCodePoints(controller.text), max);

  void _submit() {
    if (!validateForm(_formKey)) {
      setState(() => _error = kFixFieldsMessage);
      return;
    }
    final vendor = workVendorFromForm(
      name: _name.text,
      contact: _contact.text,
      phone: servicePhoneForSave(_phone.text, stored: widget.initial?.phone) ?? '',
      amount: _amount.text,
    );
    popIfCurrent<WorkVendor>(context, vendor);
  }

  @override
  Widget build(BuildContext context) {
    final referral = widget.referral;
    return AppDialog(
      title: referral ? 'Firmaya Yönlendir' : 'Firma Bilgisi',
      subtitle: 'İşi yapacak dış firmanın (taşeron) bilgileri',
      icon: Icons.business_center_rounded,
      actions: [
        TextButton(
          key: const ValueKey<String>('work_vendor_cancel'),
          onPressed: () => popIfCurrent<WorkVendor>(context),
          child: const Text('Vazgeç'),
        ),
        ElevatedButton(
          key: const ValueKey<String>('work_vendor_send'),
          onPressed: _submit,
          child: Text(referral ? 'Firmaya Yönlendir' : 'Kaydet'),
        ),
      ],
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null) CrmFormError(message: _error!, announce: true),
            if (referral) ...[
              const InlineNotice(
                key: ValueKey<String>('work_vendor_note'),
                tone: AppTone.info,
                icon: Icons.info_outline_rounded,
                message:
                    'İş "Firmada" durumuna alınır. Talebi açan sakin yalnız durumu görür; firma bilgileri ve tutar yönetimde kalır.',
              ),
              const SizedBox(height: AppSpace.md),
            ],
            TextFormField(
              key: const ValueKey<String>('work_vendor_name'),
              controller: _name,
              textCapitalization: TextCapitalization.words,
              maxLength: kWorkVendorNameMax,
              maxLengthEnforcement: MaxLengthEnforcement.none,
              buildCounter: _counter(_name, kWorkVendorNameMax),
              autovalidateMode: AutovalidateMode.onUserInteraction,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Firma adı',
                prefixIcon: Icon(Icons.business_rounded),
              ),
              validator: workVendorNameError,
            ),
            const SizedBox(height: AppSpace.md),
            TextFormField(
              key: const ValueKey<String>('work_vendor_contact'),
              controller: _contact,
              textCapitalization: TextCapitalization.words,
              maxLength: kWorkVendorContactMax,
              maxLengthEnforcement: MaxLengthEnforcement.none,
              buildCounter: _counter(_contact, kWorkVendorContactMax),
              autovalidateMode: AutovalidateMode.onUserInteraction,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Yetkili kişi (isteğe bağlı)',
                prefixIcon: Icon(Icons.person_rounded),
              ),
              validator: (v) => contractOptionalText(v, kWorkVendorContactMax),
            ),
            const SizedBox(height: AppSpace.md),
            TextFormField(
              key: const ValueKey<String>('work_vendor_phone'),
              controller: _phone,
              keyboardType: TextInputType.phone,
              inputFormatters: const [ServicePhoneInputFormatter()],
              autovalidateMode: AutovalidateMode.onUserInteraction,
              decoration: const InputDecoration(
                labelText: 'Telefon (isteğe bağlı)',
                hintText: phoneFieldHintAny,
                helperText:
                    'Sabit hat ya da cep: +90 XXX XXX XX XX. 444 gibi kısa numaralar olduğu gibi yazılır.',
                helperMaxLines: 3,
                prefixIcon: Icon(Icons.call_rounded),
              ),
              validator: (v) =>
                  validateServicePhoneInput(v, stored: widget.initial?.phone),
            ),
            const SizedBox(height: AppSpace.md),
            TextFormField(
              key: const ValueKey<String>('work_vendor_amount'),
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              autovalidateMode: AutovalidateMode.onUserInteraction,
              decoration: const InputDecoration(
                labelText: 'Anlaşılan tutar, TL (isteğe bağlı)',
                hintText: '1.250,00',
                prefixIcon: Icon(Icons.payments_outlined),
              ),
              validator: workVendorAmountError,
            ),
          ],
        ),
      ),
    );
  }
}
