import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/ui/dialogs/finance_payment_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/finance_receipt_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';

/// Tahsilattan hemen sonra (Platform Faz 4b, Q1: her tahsilatta makbuz otomatik düzenlenir): sunucu yanıtında makbuz
/// varsa makbuz penceresini "düzenlendi" bildirimiyle açar. Makbuz yoksa (site ayarı kapalı ya da eski sunucu) hiçbir
/// şey yapmaz; uydurma makbuz gösterilmez. Yazma zaten tamamlanmıştır: pencere açılamasa da kayıt değişmez.
Future<void> openReceiptAfterPayment(
  BuildContext context, {
  required PeopleScope scope,
  required FinancePaymentOutcome outcome,
  VoidCallback? onChanged,
}) async {
  final ref = outcome.result.receipt;
  if (ref == null || ref.isCancelled || !context.mounted) return;
  await FinanceReceiptDialog.show(
    context,
    scope: scope,
    receiptId: ref.id,
    initialNumber: ref.number,
    justIssued: true,
    onChanged: onChanged,
  );
}
