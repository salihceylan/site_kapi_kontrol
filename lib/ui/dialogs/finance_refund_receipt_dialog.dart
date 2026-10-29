import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/finance_refund.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/large_dialog_parts.dart';
import 'package:site_kapi_kontrol/ui/helpers/date_input.dart';
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/helpers/money.dart';

/// İade makbuzu görünümü (karar K4): onaylanan iadenin numarası (IA-yıl-sıra), tarihi, tutarı, ödenen kişi, çıkış yapılan Hesap, yöntem ve doğrulama kodu.
/// Yalnız OKUR (sunucu değişmez anlık görüntü tutar; TCKN / telefon / adres / bakiye / serbest not içermez). Geri alınan iadenin makbuzu "İptal edildi" yazar.
/// Hem yönetici (iade listesi) hem sakin (Borcum) kullanır; PDF yoktur.
class FinanceRefundReceiptDialog extends StatelessWidget {
  const FinanceRefundReceiptDialog({super.key, required this.refund});

  final RefundRequest refund;

  static Future<void> show(BuildContext context, {required RefundRequest refund}) {
    return showDialog<void>(context: context, builder: (_) => FinanceRefundReceiptDialog(refund: refund));
  }

  static String methodLabel(String? method) => switch (method) {
    'cash' => 'Nakit',
    'transfer' => 'Havale / EFT',
    'cheque' => 'Çek',
    _ => '-',
  };

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final receipt = refund.receipt;
    final amount = formatMinor(refund.amountMinor);
    final rows = <(String, String)>[
      if (receipt != null) ...[
        ('Düzenlenme tarihi', formatCrmDate(receipt.issuedOn)),
        ('Ödeme tarihi', formatCrmDate(receipt.paidOn ?? refund.payDate)),
        ('Daire', receipt.apartmentLabel ?? refund.apartmentLabel),
        if (receipt.payeeName != null) ('İade edilen', receipt.payeeName!),
        if (receipt.fromAccountName != null) ('Ödenen hesap', receipt.fromAccountName!),
        ('Yöntem', methodLabel(receipt.method)),
        if (receipt.issuerName != null) ('Düzenleyen', receipt.issuerName!),
        if (receipt.verificationCode != null) ('Doğrulama kodu', receipt.verificationCode!),
      ],
    ];
    return AppDialog(
      title: 'İade Makbuzu',
      subtitle: receipt?.siteName,
      icon: Icons.receipt_long_rounded,
      tone: receipt?.cancelled == true ? AppTone.danger : AppTone.success,
      actions: [
        TextButton(
          key: const ValueKey<String>('finance_refund_receipt_close'),
          onPressed: () => popIfCurrent(context),
          child: const Text('Kapat'),
        ),
      ],
      child: receipt == null
          ? Text('Bu iade için makbuz düzenlenmemiş.', key: const ValueKey<String>('finance_refund_receipt_none'), style: th.bodyMedium)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(receipt.number, key: const ValueKey<String>('finance_refund_receipt_number'), style: th.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                Text(amount, semanticsLabel: moneySemanticLabel(refund.amountMinor), style: th.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                if (receipt.cancelled) ...[
                  const SizedBox(height: AppSpace.sm),
                  const Wrap(
                    children: [DialogMetaPill('İptal edildi: iade geri alındı', key: ValueKey<String>('finance_refund_receipt_cancelled'), tone: AppTone.danger, icon: Icons.block_rounded)],
                  ),
                ],
                const SizedBox(height: AppSpace.md),
                for (final (label, value) in rows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpace.sm),
                    child: Semantics(
                      container: true,
                      label: '$label: $value',
                      child: ExcludeSemantics(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(label, style: th.bodySmall?.copyWith(color: p.textSecondary)),
                            Text(value, style: th.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
