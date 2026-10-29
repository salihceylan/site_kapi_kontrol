import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MaxLengthEnforcement;
import 'package:site_kapi_kontrol/models/finance.dart';
import 'package:site_kapi_kontrol/models/finance_refund.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_4b_access.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_write_mixin.dart';
import 'package:site_kapi_kontrol/ui/helpers/form_validation.dart';
import 'package:site_kapi_kontrol/ui/helpers/money.dart';
import 'package:site_kapi_kontrol/ui/helpers/text_length.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_4b_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/money_field.dart';
import 'package:site_kapi_kontrol/ui/widgets/my_finance_4b_parts.dart';

/// Sakin "Fazla ödememi iade et" talebi (karar K4): fazla ödeme varsayılan olarak ALACAK kalır ve sonraki borçtan düşer; sakin isterse iadesini talep eder, iade
/// SİTE YÖNETİMİNİN ONAYIYLA yapılır (talep bir karar değildir). Tutar en çok [availableMinor] (Borcum'da görünen alacak eksi bekleyen talepler) olabilir; sunucu aynı sınırı
/// yeniden sınar. İşlem anahtarı veri imzasına bağlıdır: sonucu belirsiz kalan istek aynı veriyle yeniden denenirse çift talep açılmaz. Başarıda [RefundRequest] ile kapanır.
class MyRefundRequestDialog extends StatefulWidget {
  const MyRefundRequestDialog({super.key, required this.authService, required this.item, required this.availableMinor});

  final AuthService authService;
  final MyFinanceApartment item;

  /// İstenebilecek en çok tutar (kuruş), pozitif.
  final int availableMinor;

  static Future<RefundRequest?> show(
    BuildContext context, {
    required AuthService authService,
    required MyFinanceApartment item,
    required int availableMinor,
  }) {
    return showDialog<RefundRequest>(
      context: context,
      barrierDismissible: false,
      builder: (_) => MyRefundRequestDialog(authService: authService, item: item, availableMinor: availableMinor),
    );
  }

  @override
  State<MyRefundRequestDialog> createState() => _MyRefundRequestDialogState();
}

class _MyRefundRequestDialogState extends State<MyRefundRequestDialog> with FinanceWriteMixin {
  static const int _noteMax = 200;

  @override
  String get keyPrefix => 'rfn-req';

  @override
  Object? get keyOwner => widget.authService;

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount = TextEditingController(text: formatMinor(widget.availableMinor, symbol: false));
  final TextEditingController _note = TextEditingController();

  @override
  void dispose() {
    disposeWrite();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (writeBlocked) return;
    if (!validateForm(_formKey)) {
      setState(() => submitError = kFixFieldsMessage);
      return;
    }
    final minor = parseMoney(_amount.text, maxMinor: widget.availableMinor).minor;
    if (minor == null) {
      setState(() => submitError = 'İade tutarı alacağınızdan (${formatMinor(widget.availableMinor)}) fazla olamaz.');
      return;
    }
    final note = _note.text.trim();
    final scope = residentScopeOf(widget.authService, widget.item);
    await runWrite<RefundRequest>(
      signature: '${widget.item.apartmentId}|$minor|$note',
      action: (key) => scope.f4Call(
        (api, t, _) => api.createMyRefundRequest(
          token: t,
          apartmentId: widget.item.apartmentId,
          amountMinor: minor,
          note: note.isEmpty ? null : note,
          idempotencyKey: key,
        ),
      ),
      onSuccess: (refund) => popIfCurrent(context, refund),
      failure: 'İade talebi gönderilemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final available = formatMinor(widget.availableMinor);
    final party = widget.item.accountParty;
    return PopScope(
      canPop: !submitting,
      child: AppDialog(
        title: 'Fazla Ödememi İade Et',
        subtitle: party?.label,
        icon: Icons.currency_exchange_rounded,
        tone: AppTone.info,
        actions: [
          TextButton(
            key: const ValueKey<String>('my_refund_cancel'),
            onPressed: submitting ? null : () => popIfCurrent(context),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            key: const ValueKey<String>('my_refund_submit'),
            onPressed: writeBlocked ? null : _submit,
            child: Text(submitting ? 'Gönderiliyor...' : 'İade Talep Et'),
          ),
        ],
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (submitError != null) FinanceSubmitError(key: const ValueKey<String>('my_refund_error'), message: submitError!),
              Text(
                'Fazla ödemeniz alacak olarak kalır ve sonraki borçlarınızdan düşer. İsterseniz iadesini talep edebilirsiniz; '
                'iade site yönetiminin onayıyla yapılır, talebiniz onaylanmadan önce geri çekebilirsiniz.',
                style: th.bodyMedium,
              ),
              const SizedBox(height: AppSpace.sm),
              Text(
                'İstenebilecek en çok tutar: $available',
                semanticsLabel: spokenMoneyText('İstenebilecek en çok tutar: $available'),
                key: const ValueKey<String>('my_refund_available'),
                style: th.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: AppSpace.md),
              MoneyFormField(
                key: const ValueKey<String>('my_refund_amount_group'),
                fieldKey: const ValueKey<String>('my_refund_amount'),
                controller: _amount,
                label: 'İade tutarı',
                enabled: !submitting,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: AppSpace.md),
              TextFormField(
                key: const ValueKey<String>('my_refund_note'),
                controller: _note,
                enabled: !submitting,
                minLines: 1,
                maxLines: 3,
                maxLength: _noteMax,
                maxLengthEnforcement: MaxLengthEnforcement.none,
                buildCounter: (context, {required currentLength, required isFocused, maxLength}) =>
                    characterCounter(context, trimmedCodePoints(_note.text), _noteMax),
                textCapitalization: TextCapitalization.sentences,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Not (isteğe bağlı)',
                  helperText: 'Yönetime iletmek istediğiniz kısa not. IBAN gibi banka bilgilerini buraya yazmayın.',
                  helperMaxLines: 3,
                  alignLabelWithHint: true,
                  prefixIcon: Icon(Icons.notes_rounded),
                ),
                validator: (value) =>
                    trimmedCodePoints(value ?? '') > _noteMax ? 'Not en çok $_noteMax karakter olabilir.' : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
