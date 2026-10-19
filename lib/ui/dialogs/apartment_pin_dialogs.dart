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

/// "PIN'i Sıfırla" onayı. Onaylanırsa true.
Future<bool> confirmApartmentPinReset(
  BuildContext context, {
  required ApartmentRecord apartment,
}) {
  final hasEmail = (apartment.residentEmail ?? '').trim().isNotEmpty;
  return confirmCrmAction(
    context,
    title: 'PIN sıfırlansın mı?',
    message:
        '${apartment.label} daire hesabına yeni bir PIN verilir. Eski PIN artık çalışmaz ve bu hesapla açık '
        'oturumlar kapanır. ${hasEmail ? 'Yeni PIN ekranda bir kez gösterilir ve sakinin e-posta adresine de gönderilir.' : 'Yeni PIN yalnız ekranda bir kez gösterilir.'}',
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
    final loginName = (issue.apartment.residentLoginName ?? '').trim();
    final (AppTone mailTone, String mailMessage) = switch (issue
        .credentialsSent) {
      true => (AppTone.success, 'PIN sakinin e-posta adresine bir kez gönderildi.'),
      false => (
        AppTone.warning,
        "E-posta gönderilemedi. PIN'i sakine kendiniz iletin.",
      ),
      null => (
        AppTone.info,
        "Sakinin e-posta adresi yok. PIN'i sakine kendiniz iletin.",
      ),
    };

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
            label: 'PIN ${issue.pinCode.split('').join(' ')}',
            excludeSemantics: true,
            child: SelectableText(
              issue.pinCode,
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
