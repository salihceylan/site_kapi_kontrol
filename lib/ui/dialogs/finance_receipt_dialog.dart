import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MaxLengthEnforcement;
import 'package:site_kapi_kontrol/models/receipt_models.dart';
import 'package:site_kapi_kontrol/services/pdf_finance_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/large_dialog_parts.dart';
import 'package:site_kapi_kontrol/ui/helpers/date_input.dart';
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_4b_access.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_errors.dart';
import 'package:site_kapi_kontrol/ui/helpers/idempotency.dart';
import 'package:site_kapi_kontrol/ui/helpers/money.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/helpers/retry_lock.dart';
import 'package:site_kapi_kontrol/ui/helpers/text_length.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_4b_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

/// Makbuz ayrıntısı + PDF (Platform Faz 4b, Ö1). Üç kullanıcı biçimi:
/// - Yönetici ([PeopleScope.canWrite]): **Yazdır / Paylaş** her basımda sunucuya `POST receipts/:id/print` ile bir
///   basım olayı yazar; ilk basım **ASIL**, sonrakiler **KOPYA (n)**. Hatalı makbuz **iptal** edilebilir (ödeme
///   değişmez; iptal makbuzu yeni numara alır).
/// - Kurul (canWrite false, resident false): yalnız okur; basım / iptal düğmesi YOKTUR.
/// - Sakin ([resident] true): kendi dairesinin makbuzu; basım HER ZAMAN "KOPYA" damgalıdır ve kayıt yazmaz.
///
/// Basım kaydı yazılamazsa (ağ / sunucu) PDF üretilmez ve "ASIL" damgası uydurulmaz; hata gösterilir. Çift dokunuş
/// koruması: işlem sürerken düğmeler pasiftir. Hata asla boş ekran bırakmaz ("Tekrar Dene").
class FinanceReceiptDialog extends StatefulWidget {
  const FinanceReceiptDialog({
    super.key,
    required this.scope,
    required this.receiptId,
    this.initialNumber,
    this.resident = false,
    this.justIssued = false,
    this.onChanged,
  });

  final PeopleScope scope;
  final int receiptId;

  /// Ayrıntı gelene kadar başlıkta görünen numara (listeden / tahsilat yanıtından).
  final String? initialNumber;
  final bool resident;

  /// Tahsilattan hemen sonra açıldı: "Makbuz ... düzenlendi" bildirimi gösterilir.
  final bool justIssued;

  /// Makbuz değişince (iptal) çağrılır.
  final VoidCallback? onChanged;

  static const int maxNoteLength = 200;

  static Future<void> show(
    BuildContext context, {
    required PeopleScope scope,
    required int receiptId,
    String? initialNumber,
    bool resident = false,
    bool justIssued = false,
    VoidCallback? onChanged,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => FinanceReceiptDialog(
        scope: scope,
        receiptId: receiptId,
        initialNumber: initialNumber,
        resident: resident,
        justIssued: justIssued,
        onChanged: onChanged,
      ),
    );
  }

  @override
  State<FinanceReceiptDialog> createState() => _FinanceReceiptDialogState();
}

class _FinanceReceiptDialogState extends State<FinanceReceiptDialog> {
  Receipt? _receipt;
  bool _loading = true;
  String? _error;
  int _token = 0;

  bool _busy = false;
  String? _busyAction;
  String? _actionError;
  int _printGeneration = 0;

  // Sunucuya YAZILMIŞ ama çıktısı (PDF) henüz teslim edilmemiş basımın kopya numarası. PDF hatasından sonra yeniden
  // deneme aynı basımı teslim eder (yeni kopya saymaz); aksi halde ASIL hiç teslim edilmeden tükenirdi.
  int? _recordedCopy;
  final IdempotencyKeys _keys = IdempotencyKeys('rcpt');
  final RetryLock _retry = RetryLock();

  bool get _canPrintRecord => !widget.resident && widget.scope.canWrite;
  bool get _canOutput => widget.resident || widget.scope.canWrite;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    ++_token;
    _retry.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!mounted) return;
    final token = ++_token;
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final scope = widget.scope;
      final receipt = widget.resident
          ? await scope.f4.run((api, t) => api.getMyReceipt(token: t, receiptId: widget.receiptId))
          : await scope.f4Call(
              (api, t, s) => api.getReceipt(token: t, siteCode: s, receiptId: widget.receiptId),
            );
      if (!mounted || token != _token) return;
      setState(() {
        _receipt = receipt;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted || token != _token) return;
      if (silent) return; // sessiz yenileme başarısız: eldeki makbuz geçerli kalır
      setState(() {
        _loading = false;
        _error = financeMessageOf(e, 'Makbuz yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.');
      });
    }
  }

  Future<void> _output({required bool share}) async {
    final receipt = _receipt;
    if (receipt == null || _busy || _retry.locked || !_canOutput) return;
    setState(() {
      _busy = true;
      _busyAction = share ? 'share' : 'print';
      _actionError = null;
    });
    try {
      final String stamp;
      if (_canPrintRecord) {
        // Her yönetici basımı sunucuya yazılır; ASIL / KOPYA numarası sunucudan gelir (uydurulmaz).
        final int copy;
        final already = _recordedCopy;
        if (already != null) {
          copy = already;
        } else {
          final signature = 'print|${receipt.id}|$_printGeneration';
          final key = _keys.keyFor(signature);
          final int recorded = await widget.scope.f4Call(
            (api, t, s) => api.recordReceiptPrint(token: t, siteCode: s, receiptId: receipt.id, idempotencyKey: key),
          );
          _keys.clear(signature);
          _recordedCopy = recorded;
          copy = recorded;
        }
        stamp = receiptStampText(copy);
      } else {
        stamp = 'KOPYA';
      }
      await FinancePdfActions.receipt(receipt, stamp, share: share);
      // Çıktı teslim edildi: sıradaki basım YENİ bir olaydır (yeni anahtar, yeni kopya).
      if (_recordedCopy != null) {
        _recordedCopy = null;
        _printGeneration++;
      }
      if (!mounted) return;
      setState(() {
        _busy = false;
        _busyAction = null;
      });
      unawaited(_load(silent: true)); // basım sayısı tazelenir
    } catch (e) {
      if (!mounted) return;
      final limited = _retry.lockIfRateLimited(e, () {
        if (mounted) setState(() {});
      });
      final pendingRecorded = _recordedCopy != null;
      if (pendingRecorded) unawaited(_load(silent: true)); // kayıtlı basım sayısı görünsün
      setState(() {
        _busy = false;
        _busyAction = null;
        _actionError = limited
            ? RetryLock.messageFor(e)
            : (pendingRecorded
                  ? 'Basım kaydedildi ancak PDF hazırlanamadı. Tekrar deneyin; yeni bir kopya sayılmaz.'
                  : (_canPrintRecord
                        ? financeWriteMessage(
                            e,
                            'Makbuz hazırlanamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.',
                            hint: 'Basım kaydı oluşmuş olabilir; tekrar denemek yeni bir kopya sayılabilir.',
                          )
                        // Sakin basım kaydı yazmaz: "yeni kopya sayılır" ipucu yalnız kayıt yazan rollerde geçerli.
                        : financeMessageOf(
                            e,
                            'Makbuz hazırlanamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.',
                          )));
      });
    }
  }

  Future<void> _cancelReceipt() async {
    final receipt = _receipt;
    if (receipt == null || _busy) return;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ReceiptCancelDialog(scope: widget.scope, receipt: receipt),
    );
    if (ok != true || !mounted) return;
    widget.onChanged?.call();
    showFinanceSnack(context, 'Makbuz iptal edildi. İptal makbuzu düzenlendi.');
    unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    final receipt = _receipt;
    final Widget body;
    if (receipt == null) {
      body = _loading || _error == null
          ? const DialogRowsSkeleton(rows: 3, caption: 'Makbuz yükleniyor...')
          : InlineNotice(message: _error!, onRetry: _load);
    } else {
      body = _buildLoaded(context, receipt);
    }
    return AppDialog(
      title: 'Makbuz',
      subtitle: receipt?.number ?? widget.initialNumber,
      icon: Icons.receipt_long_rounded,
      tone: AppTone.success,
      actions: [
        TextButton(
          key: const ValueKey<String>('finance_receipt_close'),
          onPressed: () => popIfCurrent(context),
          child: const Text('Kapat'),
        ),
      ],
      child: body,
    );
  }

  Widget _buildLoaded(BuildContext context, Receipt r) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final cancelledOriginal = !r.isCancellation && r.isCancelled;
    final canCancel = widget.scope.canWrite && !widget.resident && !r.isCancellation && !r.isCancelled;
    final payer = receiptPayerText(r.payerParty, r.payerName);
    final semantic = StringBuffer('${r.kind.label} ${r.number}. ${moneySemanticLabel(r.amountMinor)}.');
    if (r.apartmentLabel.isNotEmpty) semantic.write(' Daire ${r.apartmentLabel}.');
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.justIssued) ...[
          InlineNotice(
            key: const ValueKey<String>('finance_receipt_issued'),
            tone: AppTone.success,
            message: 'Makbuz ${r.number} düzenlendi. Yazdırabilir ya da paylaşabilirsiniz.',
          ),
          const SizedBox(height: AppSpace.md),
        ],
        if (_actionError != null) ...[
          FinanceSubmitError(key: const ValueKey<String>('finance_receipt_error'), message: _actionError!),
        ],
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.xs,
          children: [
            DialogMetaPill(
              r.isCancellation ? 'İptal makbuzu' : 'Tahsilat makbuzu',
              tone: r.isCancellation ? AppTone.warning : AppTone.success,
              icon: r.isCancellation ? Icons.undo_rounded : Icons.receipt_long_rounded,
            ),
            if (cancelledOriginal)
              const DialogMetaPill('İptal edildi', tone: AppTone.neutral, icon: Icons.block_rounded),
            if (!r.isCancellation && !r.isCancelled)
              const DialogMetaPill('Geçerli', tone: AppTone.success, icon: Icons.verified_rounded),
          ],
        ),
        const SizedBox(height: AppSpace.md),
        DialogPanel(
          key: const ValueKey<String>('finance_receipt_summary'),
          child: Semantics(
            container: true,
            label: semantic.toString(),
            child: ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Makbuz No', style: th.bodySmall?.copyWith(color: p.textSecondary)),
                  Text(r.number, key: const ValueKey<String>('finance_receipt_number'), style: th.titleLarge),
                  const SizedBox(height: AppSpace.sm),
                  Text(
                    r.isCancellation ? 'İptal edilen tutar' : 'Tahsil edilen tutar',
                    style: th.bodySmall?.copyWith(color: p.textSecondary),
                  ),
                  Text(
                    formatMinor(r.amountMinor),
                    key: const ValueKey<String>('finance_receipt_amount'),
                    style: th.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  Text('Yazıyla: ${moneySemanticLabel(r.amountMinor)}', style: th.bodySmall),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        if (cancelledOriginal)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.md),
            child: InlineNotice(
              key: const ValueKey<String>('finance_receipt_cancelled'),
              tone: AppTone.warning,
              message: r.cancelledByNumber == null
                  ? 'Bu makbuz iptal edilmiştir.'
                  : 'Bu makbuz iptal edilmiştir. İptal makbuzu No ${r.cancelledByNumber}.',
            ),
          ),
        if (r.isCancellation)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.md),
            child: InlineNotice(
              key: const ValueKey<String>('finance_receipt_cancels'),
              tone: AppTone.warning,
              message:
                  '${r.cancelsNumber == null ? 'Bu makbuz daha önce düzenlenmiş bir makbuzu' : '${r.cancelsNumber} numaralı makbuzu'} '
                  'iptal eder. Neden: ${receiptCancelReasonLabel(r.cancelReasonCode)}.',
            ),
          ),
        FinanceInfoRow(label: 'Düzenleme tarihi', value: formatCrmDate(r.issuedOn)),
        FinanceInfoRow(label: 'Tahsilat tarihi', value: formatCrmDate(r.paidOn)),
        FinanceInfoRow(label: 'Daire', value: r.apartmentLabel.isEmpty ? '-' : r.apartmentLabel),
        FinanceInfoRow(label: 'Ödeyen', value: payer.isEmpty ? '-' : payer),
        FinanceInfoRow(label: 'Yöntem', value: r.method?.label ?? '-'),
        if (r.issuerName != null) FinanceInfoRow(label: 'Düzenleyen', value: r.issuerName),
        FinanceInfoRow(
          label: 'Doğrulama kodu',
          value: r.verificationCode.isEmpty ? '-' : formatVerificationCode(r.verificationCode),
        ),
        if (!widget.resident && widget.scope.canWrite)
          FinanceInfoRow(label: 'Basım sayısı', value: '${r.copyCount}'),
        const SizedBox(height: AppSpace.md),
        DialogPanel(
          key: const ValueKey<String>('finance_receipt_text'),
          tone: AppTone.info,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Sabit metin PDF ile AYNI kaynaktan: sunucu şablonu varsa o, yoksa paketli sürüm 1 metni.
              Text(r.template?.mahsupText ?? PdfFinanceService.mahsupText, style: th.bodySmall),
              if (r.cekince) ...[
                const SizedBox(height: AppSpace.xs),
                Text(r.template?.cekinceText ?? PdfFinanceService.cekinceText, style: th.bodySmall),
              ],
              const SizedBox(height: AppSpace.xs),
              Text(
                r.template?.disclaimerText ?? PdfFinanceService.ledgerDisclaimer,
                style: th.bodySmall?.copyWith(color: p.textSecondary),
              ),
            ],
          ),
        ),
        if (_canOutput) ...[
          const SizedBox(height: AppSpace.md),
          PrimaryActionButton(
            key: const ValueKey<String>('finance_receipt_print'),
            label: 'Yazdır',
            icon: Icons.print_rounded,
            loading: _busy && _busyAction == 'print',
            onPressed: (_busy || _retry.locked) ? null : () => _output(share: false),
          ),
          const SizedBox(height: AppSpace.sm),
          PrimaryActionButton(
            key: const ValueKey<String>('finance_receipt_share'),
            label: 'Paylaş (PDF)',
            icon: Icons.ios_share_rounded,
            variant: AppButtonVariant.tonal,
            loading: _busy && _busyAction == 'share',
            onPressed: (_busy || _retry.locked) ? null : () => _output(share: true),
          ),
          if (widget.resident)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.xs),
              child: Text(
                'Kendi cihazınızdan alınan çıktı "KOPYA" damgalıdır.',
                style: th.bodySmall?.copyWith(color: p.textSecondary),
              ),
            ),
        ],
        if (canCancel) ...[
          const SizedBox(height: AppSpace.sm),
          OutlinedButton.icon(
            key: const ValueKey<String>('finance_receipt_cancel'),
            style: dangerOutlineStyle(context),
            onPressed: _busy ? null : _cancelReceipt,
            icon: const Icon(Icons.block_rounded, size: 18),
            label: const Text('Makbuzu İptal Et'),
          ),
        ],
      ],
    );
  }

}

/// "Makbuzu İptal Et" onay penceresi: neden sabit (`issued_in_error`), isteğe bağlı kısa not.
class _ReceiptCancelDialog extends StatefulWidget {
  const _ReceiptCancelDialog({required this.scope, required this.receipt});

  final PeopleScope scope;
  final Receipt receipt;

  @override
  State<_ReceiptCancelDialog> createState() => _ReceiptCancelDialogState();
}

class _ReceiptCancelDialogState extends State<_ReceiptCancelDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _note = TextEditingController();
  final IdempotencyKeys _keys = IdempotencyKeys('rcpt-c');
  final RetryLock _retry = RetryLock();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _retry.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || _retry.locked) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final note = _note.text.trim();
    final signature = 'cancel|${widget.receipt.id}|$note';
    final key = _keys.keyFor(signature);
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.scope.f4Call(
        (api, t, s) => api.cancelReceipt(
          token: t,
          siteCode: s,
          receiptId: widget.receipt.id,
          note: note,
          idempotencyKey: key,
        ),
      );
      _keys.clear(signature);
      if (!mounted) return;
      popIfCurrent(context, true);
    } catch (e) {
      if (!mounted) return;
      if (hasErrorCode(e, 'IDEMPOTENCY_CONFLICT')) _keys.clear(signature);
      final limited = _retry.lockIfRateLimited(e, () {
        if (mounted) setState(() {});
      });
      setState(() {
        _submitting = false;
        _error = limited
            ? RetryLock.messageFor(e)
            : financeWriteMessage(e, 'Makbuz iptal edilemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    return PopScope(
      canPop: !_submitting,
      child: AppDialog(
        title: 'Makbuzu İptal Et',
        subtitle: widget.receipt.number,
        icon: Icons.block_rounded,
        tone: AppTone.danger,
        actions: [
          TextButton(
            onPressed: _submitting ? null : () => popIfCurrent(context, false),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            key: const ValueKey<String>('finance_receipt_cancel_confirm'),
            style: filledToneStyle(context, tone: AppTone.danger),
            onPressed: (_submitting || _retry.locked) ? null : _submit,
            child: Text(_submitting ? 'İptal ediliyor...' : 'Makbuzu İptal Et'),
          ),
        ],
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) FinanceSubmitError(message: _error!),
              Text(
                'Ödeme değişmez; yalnızca bu makbuz geçersiz sayılır ve yeni numaralı bir iptal makbuzu '
                'düzenlenir. Daha sonra, hesap ekstresindeki "Makbuz Düzenle" ile aynı ödeme için yeni bir makbuz düzenleyebilirsiniz.',
                style: th.bodyMedium,
              ),
              const SizedBox(height: AppSpace.md),
              TextFormField(
                key: const ValueKey<String>('finance_receipt_cancel_note'),
                controller: _note,
                enabled: !_submitting,
                minLines: 2,
                maxLines: 4,
                maxLength: FinanceReceiptDialog.maxNoteLength,
                maxLengthEnforcement: MaxLengthEnforcement.none,
                buildCounter: (context, {required currentLength, required isFocused, maxLength}) =>
                    characterCounter(context, trimmedCodePoints(_note.text), FinanceReceiptDialog.maxNoteLength),
                textCapitalization: TextCapitalization.sentences,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                decoration: InputDecoration(
                  labelText: 'Not (isteğe bağlı)',
                  alignLabelWithHint: true,
                  prefixIcon: const Icon(Icons.notes_rounded),
                  helperText: 'Not yalnızca yönetim kayıtlarında görünür.',
                  helperStyle: TextStyle(color: p.textSecondary),
                ),
                validator: (value) => trimmedCodePoints(value ?? '') > FinanceReceiptDialog.maxNoteLength
                    ? 'Not en çok ${FinanceReceiptDialog.maxNoteLength} karakter olabilir.'
                    : null,
                onChanged: (_) => _refreshCounter(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Sayaç yeniden çizilsin diye (buildCounter controller'ı dinlemez).
  void _refreshCounter() {
    if (mounted) setState(() {});
  }
}
