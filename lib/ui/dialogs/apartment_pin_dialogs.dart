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

/// Sakin şifresini kendisi belirlemişse yönetici PIN'i sıfırlayamaz (sunucu 409 APARTMENT_PIN_RESET_NEEDS_SUPER ile aynı ileti).
const String kApartmentPinNeedsSuper =
    "Sakin şifresini kendisi belirlemiş. Bu durumda PIN'i yalnız süper kullanıcı sıfırlayabilir; sakin kendi şifresini uygulamadan değiştirebilir.";

/// "PIN'i Sıfırla" onayı. Onaylanırsa true.
///
/// Sıfırlamayı yapan PIN'i BİR KEZ görür. Sakin şifresini kendisi belirlemişse
/// ([ApartmentRecord.residentPinIssued] false) yalnız süper kullanıcı ([isSuper]) sıfırlayabilir; yönetici için bu
/// pencere açılmaz (false döner; daire satırındaki düğme zaten devre dışıdır ve [kApartmentPinNeedsSuper] yazar).
Future<bool> confirmApartmentPinReset(
  BuildContext context, {
  required ApartmentRecord apartment,
  required bool isSuper,
}) async {
  if (!apartment.residentPinIssued && !isSuper) return false;
  final email = (apartment.residentEmail ?? '').trim();
  final mail = email.isNotEmpty
      ? ' ve sakinin e-posta adresine ($email) de gönderilir'
      : '';
  final override = apartment.residentPinIssued
      ? ''
      : 'Sakin şifresini kendisi belirlemiş; süper kullanıcı olarak onun şifresinin yerine yeni PIN veriyorsunuz. ';
  return confirmCrmAction(
    context,
    title: 'PIN sıfırlansın mı?',
    message:
        '${apartment.label} daire hesabına yeni bir PIN verilir. Eski şifre artık çalışmaz; bu hesapla açık oturumlar, '
        'misafir geçişleri ve karekodlar kapanır. ${override}Yeni PIN size bir kez gösterilir$mail.',
    confirmLabel: 'Sıfırla',
    cancelLabel: 'Vazgeç',
    icon: Icons.lock_reset_rounded,
    tone: AppTone.warning,
  );
}

/// Az önce verilen PIN'i BİR KEZ gösterir (kapatılınca yeniden gösterilemez).
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
    return switch (issue.credentialsSent) {
      true => (
        AppTone.success,
        'PIN ${email ?? 'sakinin e-posta'} adresine bir kez gönderildi.',
      ),
      false => (
        AppTone.warning,
        "E-posta ${email != null ? '($email) ' : ''}gönderilemedi. PIN'i sakine kendiniz iletin.",
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

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.issue.pinCode));
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
      title: "Daire PIN'i",
      subtitle: issue.apartment.label,
      icon: Icons.pin_rounded,
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
              onPressed: _copy,
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
          const SizedBox(height: AppSpace.sm),
          InlineNotice(tone: mailTone, message: mailMessage),
        ],
      ),
    );
  }
}
