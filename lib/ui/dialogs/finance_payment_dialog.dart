import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MaxLengthEnforcement;
import 'package:site_kapi_kontrol/models/finance.dart';
import 'package:site_kapi_kontrol/models/vehicle_record.dart' show crmDateParam;
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/crm_pickers.dart';
import 'package:site_kapi_kontrol/ui/dialogs/large_dialog_parts.dart';
import 'package:site_kapi_kontrol/ui/helpers/date_input.dart';
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_errors.dart';
import 'package:site_kapi_kontrol/ui/helpers/form_validation.dart';
import 'package:site_kapi_kontrol/ui/helpers/idempotency.dart';
import 'package:site_kapi_kontrol/ui/helpers/istanbul_time.dart';
import 'package:site_kapi_kontrol/ui/helpers/money.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/helpers/retry_lock.dart';
import 'package:site_kapi_kontrol/ui/helpers/text_length.dart';
import 'package:site_kapi_kontrol/ui/widgets/crm_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/money_field.dart';

/// Tahsilat penceresi kapanırken döner: sunucu yanıtı ve kullanıcıya gösterilecek kısa mesaj.
class FinancePaymentOutcome {
  const FinancePaymentOutcome({required this.result, required this.message});

  final LedgerWriteResult result;
  final String message;
}

/// "Tahsilat Ekle" ve "Tahsilatı Düzelt" penceresi (Platform Faz 4a).
///
/// - Alanlar: daire seçici, tutar (kuruşa KESİN çevrilir; yanında ayrıştırılan tutar gösterilir), tarih
///   (GG.AA.YYYY, İstanbul takvim günü; gelecek olamaz), yöntem (Nakit / Havale-EFT / Çek; seçilmeden
///   gönderilmez), açıklama (en çok 200 karakter, kod noktası sayımı).
/// - [correcting] verilirse düzeltme kipidir: eski tahsilat ters kayıtla iptal edilir, yeni tutar yeni kayıt
///   olarak yazılır (TEK işlemde); daire değiştirilemez.
/// - Çift gönderim koruması: `_submitting`, gönderim sürerken geri tuşu kapatmaz. `idempotency_key` veri
///   imzasına bağlıdır: aynı veriyle yeniden denemede AYNI anahtar gider (sonucu belirsiz istek çift kayıt
///   yaratmaz); veri değişirse yeni anahtar üretilir.
/// - Sunucu reddi (kapalı dönem vb.) Türkçe mesajla pencerede gösterilir ve pencere AÇIK kalır.
class FinancePaymentDialog extends StatefulWidget {
  const FinancePaymentDialog({
    super.key,
    required this.scope,
    this.apartmentId,
    this.apartmentLabel,
    this.correcting,
    this.now,
    this.onRefreshNeeded,
  });

  final PeopleScope scope;

  /// Önceden seçili daire (ekstreden açılınca); null ise daire seçici gösterilir.
  final int? apartmentId;
  final String? apartmentLabel;

  /// Düzeltilen tahsilat; null ise yeni tahsilat.
  final LedgerEntry? correcting;

  /// Şimdiki zaman (tarih doğrulaması; testler içindir).
  final DateTime Function()? now;

  /// Sonuç BELİRSİZ kaldığında (ağ / 5xx) pencere kapanırken çağrılır: çağıran listeyi tazeler.
  final VoidCallback? onRefreshNeeded;

  static const int maxNoteLength = 200;

  static Future<FinancePaymentOutcome?> show(
    BuildContext context, {
    required PeopleScope scope,
    int? apartmentId,
    String? apartmentLabel,
    LedgerEntry? correcting,
    DateTime Function()? now,
    VoidCallback? onRefreshNeeded,
  }) {
    return showDialog<FinancePaymentOutcome>(
      context: context,
      barrierDismissible: false,
      builder: (_) => FinancePaymentDialog(
        scope: scope,
        apartmentId: apartmentId,
        apartmentLabel: apartmentLabel,
        correcting: correcting,
        now: now,
        onRefreshNeeded: onRefreshNeeded,
      ),
    );
  }

  @override
  State<FinancePaymentDialog> createState() => _FinancePaymentDialogState();
}

class _FinancePaymentDialogState extends State<FinancePaymentDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount = TextEditingController(
    text: widget.correcting == null
        ? ''
        : formatMinor(widget.correcting!.amountMinor.abs(), symbol: false),
  );
  late final TextEditingController _date = TextEditingController(
    text: formatDateField(widget.correcting?.entryDate ?? _today()),
  );
  late final TextEditingController _note = TextEditingController(
    text: widget.correcting?.description ?? '',
  );
  late PaymentMethod? _method = widget.correcting?.method;
  late ({int id, String label})? _apartment = widget.apartmentId == null
      ? null
      : (id: widget.apartmentId!, label: widget.apartmentLabel ?? 'Daire');
  final IdempotencyKeys _keys = IdempotencyKeys('pay');
  final RetryLock _retry = RetryLock();

  bool _submitting = false;
  bool _picking = false;
  bool _needsRefreshOnClose = false;
  String? _error;
  String? _apartmentError;
  String? _methodError;

  bool get _correcting => widget.correcting != null;

  DateTime _today() {
    final wall = istanbulNow(widget.now?.call());
    return DateTime(wall.year, wall.month, wall.day);
  }

  @override
  void dispose() {
    _retry.dispose();
    _amount.dispose();
    _date.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickApartment() async {
    if (_picking || _submitting) return;
    _picking = true;
    try {
      final picked = await showApartmentPicker(context, widget.scope);
      if (picked == null || !mounted) return;
      setState(() {
        _apartment = (id: picked.id, label: picked.fullLabel);
        _apartmentError = null;
      });
    } finally {
      _picking = false;
    }
  }

  String? _validateDate(String? value) {
    if ((value ?? '').trim().isEmpty) return 'Tahsilat tarihini girin.';
    final format = validateDateField(value);
    if (format != null) return format;
    final date = parseDateField(value)!;
    if (date.isAfter(_today())) return 'Tarih bugünden ileri olamaz.';
    return null;
  }

  Future<void> _submit() async {
    if (_submitting || _retry.locked) return;
    final fieldsOk = validateForm(_formKey);
    final apartment = _apartment;
    final method = _method;
    setState(() {
      _apartmentError = apartment == null ? 'Daire seçin.' : null;
      _methodError = method == null ? 'Tahsilat yöntemini seçin.' : null;
    });
    if (!fieldsOk || apartment == null || method == null) {
      setState(() => _error = kFixFieldsMessage);
      return;
    }
    final minor = parseMoney(_amount.text).minor;
    final date = parseDateField(_date.text);
    if (minor == null || date == null) {
      setState(() => _error = kFixFieldsMessage);
      return;
    }
    final note = _note.text.trim();
    final correcting = widget.correcting;
    // Veri imzası: aynı veriyle yeniden deneme AYNI anahtarı, değişen veri yeni anahtarı kullanır.
    final signature =
        '${correcting?.id ?? 0}|${apartment.id}|$minor|${crmDateParam(date)}|${method.apiValue}|$note';
    final key = _keys.keyFor(signature);

    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final auth = widget.scope.authService;
      final siteCode = widget.scope.siteCode;
      final LedgerWriteResult result;
      if (correcting == null) {
        result = await auth.recordFeePayment(
          siteCode,
          apartmentId: apartment.id,
          amountMinor: minor,
          entryDate: date,
          method: method,
          description: note,
          idempotencyKey: key,
        );
      } else {
        result = await auth.correctFinancePayment(
          siteCode,
          correcting.id,
          amountMinor: minor,
          entryDate: date,
          method: method,
          description: note,
          idempotencyKey: key,
        );
      }
      if (!mounted) return;
      _needsRefreshOnClose = false; // sonuçla kapanır: çağıran zaten günceller
      final balance = result.balanceMinor;
      final head = _correcting
          ? 'Tahsilat düzeltildi: ${formatMinor(minor)}.'
          : 'Tahsilat kaydedildi: ${formatMinor(minor)}.';
      popIfCurrent(
        context,
        FinancePaymentOutcome(
          result: result,
          message: balance == null ? head : '$head Güncel bakiye: ${describeBalance(balance).badgeText}.',
        ),
      );
    } catch (e) {
      if (financeOutcomeUncertain(e)) _needsRefreshOnClose = true;
      if (!mounted) return;
      final limited = _retry.lockIfRateLimited(e, () {
        if (mounted) setState(() {});
      });
      setState(() {
        _submitting = false;
        _error = limited
            ? RetryLock.messageFor(e)
            : financeWriteMessage(
                e,
                _correcting
                    ? 'Tahsilat düzeltilemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.'
                    : 'Tahsilat kaydedilemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
              );
      });
    }
  }

  void _notifyRefreshOnClose() {
    if (!_needsRefreshOnClose) return;
    _needsRefreshOnClose = false;
    widget.onRefreshNeeded?.call();
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final correcting = widget.correcting;
    return PopScope(
      // Gönderim sürerken geri tuşu pencereyi kapatmaz (işlem yarıda kalmış gibi görünmesin).
      canPop: !_submitting,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _notifyRefreshOnClose();
      },
      child: AppDialog(
        title: _correcting ? 'Tahsilatı Düzelt' : 'Tahsilat Ekle',
        subtitle: widget.scope.siteName.isEmpty ? null : widget.scope.siteName,
        icon: _correcting ? Icons.edit_rounded : Icons.payments_rounded,
        tone: AppTone.success,
        actions: [
          TextButton(
            onPressed: _submitting ? null : () => popIfCurrent(context),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            key: const ValueKey<String>('finance_payment_submit'),
            onPressed: (_submitting || _retry.locked) ? null : _submit,
            child: Text(_submitting ? 'Kaydediliyor...' : (_correcting ? 'Düzelt' : 'Kaydet')),
          ),
        ],
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) CrmFormError(message: _error!),
              if (correcting != null) ...[
                DialogPanel(
                  key: const ValueKey<String>('finance_payment_original'),
                  tone: AppTone.info,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const DialogSectionTitle(
                        icon: Icons.history_rounded,
                        title: 'Düzeltilen kayıt',
                        tone: AppTone.info,
                      ),
                      const SizedBox(height: AppSpace.sm),
                      Text(
                        '${formatCrmDate(correcting.entryDate)} • '
                        '${formatMinor(correcting.amountMinor.abs())}'
                        '${correcting.method == null ? '' : ' • ${correcting.method!.label}'}',
                        style: th.bodyMedium,
                      ),
                      const SizedBox(height: AppSpace.xs),
                      Text(
                        'Bu kayıt silinmez: ters kayıtla iptal edilir ve aşağıdaki bilgilerle yeni bir '
                        'tahsilat yazılır. İkisi tek işlemde yapılır.',
                        style: th.bodySmall?.copyWith(color: p.textSecondary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpace.md),
              ],
              CrmPickerField(
                key: const ValueKey<String>('finance_payment_apartment'),
                label: 'Daire',
                icon: Icons.apartment_rounded,
                value: _apartment?.label,
                placeholder: 'Daire seçmek için dokunun',
                errorText: _apartmentError,
                enabled: !_submitting && !_correcting && widget.apartmentId == null,
                onTap: _pickApartment,
              ),
              const SizedBox(height: AppSpace.md),
              MoneyFormField(
                key: const ValueKey<String>('finance_payment_amount_group'),
                fieldKey: const ValueKey<String>('finance_payment_amount'),
                controller: _amount,
                enabled: !_submitting,
                label: 'Tahsilat tutarı',
                helperText: 'Borçtan fazla ödeme alacak olarak görünür.',
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: AppSpace.md),
              TextFormField(
                key: const ValueKey<String>('finance_payment_date'),
                controller: _date,
                enabled: !_submitting,
                keyboardType: TextInputType.number,
                inputFormatters: const [DateInputFormatter()],
                autovalidateMode: AutovalidateMode.onUserInteraction,
                decoration: const InputDecoration(
                  labelText: 'Tahsilat tarihi',
                  hintText: 'GG.AA.YYYY',
                  prefixIcon: Icon(Icons.event_rounded),
                ),
                validator: _validateDate,
              ),
              const SizedBox(height: AppSpace.lg),
              Text('Yöntem', style: th.titleSmall),
              const SizedBox(height: AppSpace.sm),
              Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.sm,
                children: [
                  for (final method in PaymentMethod.values)
                    ChoiceChip(
                      key: ValueKey<String>('finance_method_${method.apiValue}'),
                      avatar: Icon(_methodIcon(method), size: 18),
                      label: Text(method.label),
                      selected: _method == method,
                      onSelected: _submitting
                          ? null
                          : (_) => setState(() {
                              _method = method;
                              _methodError = null;
                            }),
                    ),
                ],
              ),
              if (_methodError != null) ...[
                const SizedBox(height: AppSpace.sm),
                CrmFormError(message: _methodError!),
              ],
              const SizedBox(height: AppSpace.md),
              TextFormField(
                key: const ValueKey<String>('finance_payment_note'),
                controller: _note,
                enabled: !_submitting,
                minLines: 2,
                maxLines: 4,
                maxLength: FinancePaymentDialog.maxNoteLength,
                maxLengthEnforcement: MaxLengthEnforcement.none,
                buildCounter: (context, {required currentLength, required isFocused, maxLength}) =>
                    characterCounter(
                      context,
                      _note.text.trim().runes.length,
                      FinancePaymentDialog.maxNoteLength,
                    ),
                textCapitalization: TextCapitalization.sentences,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                decoration: const InputDecoration(
                  labelText: 'Açıklama (isteğe bağlı)',
                  alignLabelWithHint: true,
                  prefixIcon: Icon(Icons.notes_rounded),
                ),
                validator: (value) {
                  if (trimmedCodePoints(value ?? '') > FinancePaymentDialog.maxNoteLength) {
                    return 'Açıklama en çok ${FinancePaymentDialog.maxNoteLength} karakter olabilir.';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  static IconData _methodIcon(PaymentMethod method) => switch (method) {
    PaymentMethod.cash => Icons.payments_rounded,
    PaymentMethod.transfer => Icons.account_balance_rounded,
    PaymentMethod.cheque => Icons.receipt_rounded,
  };
}
