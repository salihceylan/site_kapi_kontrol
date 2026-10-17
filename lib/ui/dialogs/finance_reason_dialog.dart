import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MaxLengthEnforcement;
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_write_mixin.dart';
import 'package:site_kapi_kontrol/ui/helpers/form_validation.dart';
import 'package:site_kapi_kontrol/ui/helpers/text_length.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_4b_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart' show filledToneStyle;

/// Nedenli onay penceresi (Platform Faz 4b): aktarım iptali, gider iptali, tazminat çalıştırması iptali gibi GERİ
/// ALINMAZ (ters kayıt yazan) işlemler. Neden zorunludur (1-[maxLength] karakter, kod noktasıyla sayılır); onay işlemi
/// pencerede çalışır: hata pencerede kalır, çift dokunuş korunur, sonuç belirsizse aynı neden = aynı işlem anahtarı.
/// Başarıda `true` döner.
class FinanceReasonDialog extends StatefulWidget {
  const FinanceReasonDialog({
    super.key,
    required this.title,
    this.subtitle,
    required this.message,
    required this.confirmLabel,
    required this.signatureBase,
    required this.action,
    required this.failure,
    this.reasonLabel = 'Neden',
    this.maxLength = 200,
    this.icon = Icons.undo_rounded,
    this.tone = AppTone.danger,
    this.keyPrefix = 'rsn',
    this.semanticMessage,
    this.keyOwner,
    this.onUncertain,
  });

  final String title;
  final String? subtitle;
  final String message;
  final String? semanticMessage;
  final String confirmLabel;

  /// Anahtarı belirleyen sabit kısım (hedef kimliği); neden metni imzaya eklenir.
  final String signatureBase;

  /// `(neden, işlem anahtarı)` ile işlemi yapar; hata fırlatırsa pencerede gösterilir.
  final Future<void> Function(String reason, String key) action;
  final String failure;
  final String reasonLabel;
  final int maxLength;
  final IconData icon;
  final AppTone tone;
  final String keyPrefix;

  /// Oturum nesnesi (örn. `scope.authService`): verilirse işlem anahtarı oturum boyunca yaşar.
  final Object? keyOwner;

  /// Sonuç BELİRSİZ kaldıysa (ağ / 5xx) pencere kapanırken çağrılır: çağıran listeyi tazeler (iptal yazılmış olabilir).
  final VoidCallback? onUncertain;

  static Future<bool> show(
    BuildContext context, {
    required String title,
    String? subtitle,
    required String message,
    String? semanticMessage,
    required String confirmLabel,
    required String signatureBase,
    required Future<void> Function(String reason, String key) action,
    required String failure,
    String reasonLabel = 'Neden',
    int maxLength = 200,
    IconData icon = Icons.undo_rounded,
    AppTone tone = AppTone.danger,
    String keyPrefix = 'rsn',
    Object? keyOwner,
    VoidCallback? onUncertain,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => FinanceReasonDialog(
        title: title,
        subtitle: subtitle,
        message: message,
        semanticMessage: semanticMessage,
        confirmLabel: confirmLabel,
        signatureBase: signatureBase,
        action: action,
        failure: failure,
        reasonLabel: reasonLabel,
        maxLength: maxLength,
        icon: icon,
        tone: tone,
        keyPrefix: keyPrefix,
        keyOwner: keyOwner,
        onUncertain: onUncertain,
      ),
    );
    return result ?? false;
  }

  @override
  State<FinanceReasonDialog> createState() => _FinanceReasonDialogState();
}

class _FinanceReasonDialogState extends State<FinanceReasonDialog> with FinanceWriteMixin {
  @override
  String get keyPrefix => widget.keyPrefix;

  @override
  Object? get keyOwner => widget.keyOwner;

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _reason = TextEditingController();

  @override
  void dispose() {
    disposeWrite();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (writeBlocked) return;
    if (!validateForm(_formKey)) {
      setState(() => submitError = kFixFieldsMessage);
      return;
    }
    final reason = _reason.text.trim();
    await runWrite<void>(
      signature: '${widget.signatureBase}|$reason',
      action: (key) => widget.action(reason, key),
      onSuccess: (_) => popIfCurrent(context, true),
      failure: widget.failure,
    );
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    return PopScope(
      canPop: !submitting,
      onPopInvokedWithResult: (didPop, _) {
        // Sonuç belirsiz kaldıysa (zaman aşımı vb.) iptal yazılmış olabilir: çağıran listeyi tazeler.
        if (didPop && needsRefreshOnClose) {
          needsRefreshOnClose = false;
          widget.onUncertain?.call();
        }
      },
      child: AppDialog(
        title: widget.title,
        subtitle: widget.subtitle,
        icon: widget.icon,
        tone: widget.tone,
        actions: [
          TextButton(
            key: const ValueKey<String>('finance_reason_cancel'),
            onPressed: submitting ? null : () => popIfCurrent(context, false),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            key: const ValueKey<String>('finance_reason_confirm'),
            style: filledToneStyle(context, tone: widget.tone),
            onPressed: writeBlocked ? null : _submit,
            child: Text(submitting ? 'İşleniyor...' : widget.confirmLabel),
          ),
        ],
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (submitError != null) FinanceSubmitError(message: submitError!),
              Text(widget.message, semanticsLabel: widget.semanticMessage, style: th.bodyMedium),
              const SizedBox(height: AppSpace.md),
              TextFormField(
                key: const ValueKey<String>('finance_reason_text'),
                controller: _reason,
                enabled: !submitting,
                minLines: 2,
                maxLines: 4,
                maxLength: widget.maxLength,
                maxLengthEnforcement: MaxLengthEnforcement.none,
                buildCounter: (context, {required currentLength, required isFocused, maxLength}) =>
                    characterCounter(context, trimmedCodePoints(_reason.text), widget.maxLength),
                textCapitalization: TextCapitalization.sentences,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: widget.reasonLabel,
                  alignLabelWithHint: true,
                  prefixIcon: const Icon(Icons.notes_rounded),
                ),
                validator: (value) {
                  final length = trimmedCodePoints(value ?? '');
                  if (length < 1) return '${widget.reasonLabel} girin.';
                  if (length > widget.maxLength) {
                    return '${widget.reasonLabel} en çok ${widget.maxLength} karakter olabilir.';
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
}
