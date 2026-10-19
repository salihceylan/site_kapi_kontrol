import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:site_kapi_kontrol/models/apartment_pin_issue.dart';
import 'package:site_kapi_kontrol/models/apartment_record.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/crm_confirm_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';

/// Daire PIN'i (KVKK m.12): sunucu PIN'i saklamaz; PIN yalnız oluşturma / sıfırlama anında BİR KEZ gösterilir.

/// E-posta gönderimi yanıt süresinde bitmedi (sunucu beklemeden yanıtladı).
const String kApartmentPinMailPending =
    "E-posta gönderimi sürüyor; ulaşmazsa PIN'i yeniden sıfırlayın.";

/// "PIN'i Sıfırla" onayı. Onaylanırsa true.
///
/// Sakin parolasını kendisi belirlemişse ([ApartmentRecord.residentPinIssued] false) yönetici yeni PIN'i
/// GÖREMEZ: PIN yalnız sakinin e-posta adresine gider; adres yoksa yalnız süper kullanıcı sıfırlayabilir
/// (sunucu yöneticiye açıklamalı 409 döner).
Future<bool> confirmApartmentPinReset(
  BuildContext context, {
  required ApartmentRecord apartment,
}) {
  final email = (apartment.residentEmail ?? '').trim();
  final hasEmail = email.isNotEmpty;
  final String delivery;
  if (!apartment.residentPinIssued) {
    delivery = hasEmail
        ? 'Sakin şifresini kendisi belirlemiş: yeni PIN size gösterilmez, yalnız sakinin e-posta adresine ($email) gönderilir.'
        : 'Sakin şifresini kendisi belirlemiş ve e-posta adresi yok: PIN\'i yalnız süper kullanıcı sıfırlayabilir.';
  } else {
    delivery = hasEmail
        ? 'Yeni PIN ekranda bir kez gösterilir ve sakinin e-posta adresine ($email) de gönderilir.'
        : 'Yeni PIN yalnız ekranda bir kez gösterilir.';
  }
  return confirmCrmAction(
    context,
    title: 'PIN sıfırlansın mı?',
    message:
        '${apartment.label} daire hesabına yeni bir PIN verilir. Eski PIN artık çalışmaz; bu hesapla açık oturumlar, '
        'misafir geçişleri ve karekodlar kapanır. $delivery',
    confirmLabel: 'Sıfırla',
    cancelLabel: 'Vazgeç',
    icon: Icons.lock_reset_rounded,
    tone: AppTone.warning,
  );
}

/// Az önce verilen PIN'i BİR KEZ gösterir (kapatılınca yeniden gösterilemez). Yalnız e-postayla teslimde
/// ([ApartmentPinIssue.emailOnly]) PIN gösterilmez; yalnız gönderim durumu ve hedef adres yazılır.
class ApartmentPinIssuedDialog extends StatefulWidget {
  const ApartmentPinIssuedDialog({super.key, required this.issue});

  final ApartmentPinIssue issue;

  static Future<void> show(BuildContext context, ApartmentPinIssue issue) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ApartmentPinIssuedDialog(issue: issue),
    );
  }

  /// Gönderim durumu (ton, ileti). [ApartmentPinIssue.credentialsSent] null + adres dolu = gönderim sürüyor.
  static (AppTone, String) mailStatus(ApartmentPinIssue issue) {
    final email = issue.credentialsEmail;
    final shown = issue.pinCode != null;
    return switch (issue.credentialsSent) {
      true => (
        AppTone.success,
        shown
            ? 'PIN ${email ?? 'sakinin e-posta'} adresine bir kez gönderildi.'
            : 'Yeni PIN ${email ?? 'sakinin e-posta'} adresine gönderildi; güvenlik gereği burada gösterilmez.',
      ),
      false => (
        AppTone.warning,
        shown
            ? "E-posta ${email != null ? '($email) ' : ''}gönderilemedi. PIN'i sakine kendiniz iletin."
            : "E-posta ${email != null ? '($email) ' : ''}gönderilemedi ve PIN gösterilmez. Daha sonra PIN'i yeniden sıfırlayın.",
      ),
      null when email != null => (
        AppTone.info,
        'PIN $email adresine gönderiliyor. $kApartmentPinMailPending',
      ),
      null => (
        AppTone.info,
        "Sakinin e-posta adresi yok. PIN'i sakine kendiniz iletin.",
      ),
    };
  }

  @override
  State<ApartmentPinIssuedDialog> createState() =>
      _ApartmentPinIssuedDialogState();
}

class _ApartmentPinIssuedDialogState extends State<ApartmentPinIssuedDialog> {
  bool _copied = false;

  Future<void> _copy(String pin) async {
    await Clipboard.setData(ClipboardData(text: pin));
    if (!mounted) return;
    HapticFeedback.lightImpact();
    setState(() => _copied = true);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final issue = widget.issue;
    final pin = issue.pinCode;
    final loginName = (issue.apartment.residentLoginName ?? '').trim();
    final (mailTone, mailMessage) = ApartmentPinIssuedDialog.mailStatus(issue);

    return AppDialog(
      title: pin != null ? "Daire PIN'i" : 'PIN sıfırlandı',
      subtitle: issue.apartment.label,
      icon: pin != null ? Icons.pin_rounded : Icons.mark_email_read_outlined,
      tone: AppTone.violet,
      actions: [
        ElevatedButton(
          onPressed: () => popIfCurrent(context),
          child: const Text('Tamam'),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSpace.md),
          if (loginName.isNotEmpty) ...[
            Text('Kullanıcı adı', style: th.bodySmall),
            SelectableText(
              loginName,
              style: th.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: AppSpace.md),
          ],
          if (pin != null) ...[
            Text('PIN', style: th.bodySmall),
            Semantics(
              label: 'PIN ${pin.split('').join(' ')}',
              excludeSemantics: true,
              child: SelectableText(
                pin,
                style: th.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 6,
                  color: p.text,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () => _copy(pin),
                icon: Icon(
                  _copied ? Icons.check_rounded : Icons.copy_rounded,
                  size: 18,
                ),
                label: Text(_copied ? 'Kopyalandı' : 'Kopyala'),
              ),
            ),
            const SizedBox(height: AppSpace.sm),
            const InlineNotice(
              tone: AppTone.warning,
              icon: Icons.visibility_off_outlined,
              message:
                  "PIN yalnız şimdi gösterilir; güvenlik gereği saklanmaz. Unutulursa PIN'i sıfırlayın.",
            ),
          ] else
            const InlineNotice(
              tone: AppTone.info,
              icon: Icons.lock_person_outlined,
              message:
                  'Sakin şifresini kendisi belirlemişti: yeni PIN yalnız sakine gönderilir, yönetim göremez.',
            ),
          const SizedBox(height: AppSpace.sm),
          InlineNotice(tone: mailTone, message: mailMessage),
        ],
      ),
    );
  }
}
