// Banka hesabı IBAN ve alıcı adı penceresi (Dalga 2 / 2A). Canlı TR IBAN denetimi (biçim + mod-97; sunucu yine denetler). Kayıt yeni bir SÜRÜMDÜR
// (eski değer silinmez); sakinler yeni hesaba öder, bu yüzden açık onay istenir. Çift gönderim kilitli; hata pencerede kalır.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/payment_info.dart';
import 'package:site_kapi_kontrol/services/finance_payment_api.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_errors.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';

class FinanceBankDetailsDialog extends StatefulWidget {
  const FinanceBankDetailsDialog({super.key, required this.scope, required this.accountId, required this.accountName, this.currentPayee});

  final PeopleScope scope;
  final int accountId;
  final String accountName;

  /// Varsa alıcı adı önerisi (örn. site adı).
  final String? currentPayee;

  /// Kaydedilirse başarı iletisini döner, vazgeçilirse null.
  static Future<String?> show(
    BuildContext context, {
    required PeopleScope scope,
    required int accountId,
    required String accountName,
    String? currentPayee,
  }) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => FinanceBankDetailsDialog(scope: scope, accountId: accountId, accountName: accountName, currentPayee: currentPayee),
    );
  }

  @override
  State<FinanceBankDetailsDialog> createState() => _FinanceBankDetailsDialogState();
}

class _FinanceBankDetailsDialogState extends State<FinanceBankDetailsDialog> {
  late final TextEditingController _iban = TextEditingController();
  late final TextEditingController _payee = TextEditingController(text: widget.currentPayee ?? widget.scope.siteName);
  bool _confirmed = false;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _iban.dispose();
    _payee.dispose();
    super.dispose();
  }

  String? get _ibanError {
    final text = _iban.text.trim();
    if (text.isEmpty) return null;
    return parseTrIban(text) == null ? 'IBAN geçersiz. TR ile başlayan 26 haneli bir IBAN girin.' : null;
  }

  bool get _valid => parseTrIban(_iban.text) != null && _payee.text.trim().length >= 2 && _payee.text.trim().length <= 70 && _confirmed;

  Future<void> _submit() async {
    if (_submitting || !_valid) return;
    final iban = parseTrIban(_iban.text)!;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await FinancePaymentService.of(widget.scope.authService).run(
        (api, token) => api.putBankDetails(
          token: token,
          siteCode: widget.scope.siteCode,
          accountId: widget.accountId,
          iban: iban,
          payeeName: _payee.text.trim(),
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop('Banka bilgisi kaydedildi: ${widget.accountName}.');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = financeWriteMessage(e, 'Banka bilgisi kaydedilemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.', hint: 'Kayıt oluşmuş olabilir; ekranı yenileyip kontrol edin.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_submitting,
      child: AlertDialog(
        title: Text('IBAN ve alıcı adı: ${widget.accountName}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const ValueKey<String>('bank_iban'),
                controller: _iban,
                enabled: !_submitting,
                autocorrect: false,
                textCapitalization: TextCapitalization.characters,
                keyboardType: TextInputType.visiblePassword,
                decoration: InputDecoration(labelText: 'IBAN', hintText: 'TR00 0000 0000 0000 0000 0000 00', errorText: _ibanError),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: AppSpace.md),
              TextField(
                key: const ValueKey<String>('bank_payee'),
                controller: _payee,
                enabled: !_submitting,
                maxLength: 70,
                decoration: const InputDecoration(labelText: 'Alıcı adı (hesap sahibi)'),
                onChanged: (_) => setState(() {}),
              ),
              CheckboxListTile(
                key: const ValueKey<String>('bank_confirm'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _confirmed,
                onChanged: _submitting ? null : (v) => setState(() => _confirmed = v == true),
                title: const Text('Bilgilerin doğruluğunu onaylıyorum. IBAN değişirse sakinler yeni hesaba öder.'),
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpace.sm),
                InlineNotice(key: const ValueKey<String>('bank_error'), message: _error!),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: _submitting ? null : () => Navigator.of(context).pop(), child: const Text('Vazgeç')),
          FilledButton(key: const ValueKey<String>('bank_save'), onPressed: _valid && !_submitting ? () => unawaited(_submit()) : null, child: Text(_submitting ? 'Kaydediliyor…' : 'Kaydet')),
        ],
      ),
    );
  }
}
