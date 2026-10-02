import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

class InviteSiteManagerDialog extends StatefulWidget {
  const InviteSiteManagerDialog({
    super.key,
    required this.authService,
    required this.siteCode,
    required this.siteName,
  });

  final AuthService authService;
  final int siteCode;
  final String siteName;

  static Future<bool?> show(
    BuildContext context, {
    required AuthService authService,
    required int siteCode,
    required String siteName,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => InviteSiteManagerDialog(
        authService: authService,
        siteCode: siteCode,
        siteName: siteName,
      ),
    );
  }

  @override
  State<InviteSiteManagerDialog> createState() => _InviteSiteManagerDialogState();
}

class _InviteSiteManagerDialogState extends State<InviteSiteManagerDialog> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _fullNameController = TextEditingController();

  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _fullNameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final (success, message) = await widget.authService.inviteSiteManager(
      widget.siteCode,
      email: _emailController.text.trim(),
      fullName: _fullNameController.text.trim().isEmpty
          ? null
          : _fullNameController.text.trim(),
    );

    if (!mounted) return;

    setState(() {
      _isSubmitting = false;
    });

    if (success) {
      AppSnack.show(
        context,
        message ?? 'Yönetici daveti başarıyla iletildi.',
        kind: AppSnackKind.success,
      );
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _errorMessage = message ?? 'Davet gönderilirken bir hata oluştu.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: 'Yönetici Davet Et',
      subtitle: widget.siteName,
      icon: Icons.person_add_alt_1_rounded,
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(false),
          child: const Text('İptal'),
        ),
        ElevatedButton(
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Text('Davet Gönder'),
        ),
      ],
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const InlineNotice(
              tone: AppTone.info,
              message:
                  'Davet edilen kişi kayıtlıysa anında bu siteye yönetici olarak atanır. '
                  'Kayıtlı değilse e-posta adresine bir kayıt daveti gönderilir ve kaydolduğunda otomatik yönetici olur.',
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(
                labelText: 'E-posta Adresi *',
                hintText: 'ornek@eposta.com',
                prefixIcon: Icon(Icons.email_outlined),
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Lütfen e-posta adresi girin.';
                }
                final email = value.trim();
                final regex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
                if (!regex.hasMatch(email)) {
                  return 'Geçerli bir e-posta adresi girin.';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _fullNameController,
              decoration: const InputDecoration(
                labelText: 'Ad Soyad (İsteğe bağlı)',
                hintText: 'Ahmet Yılmaz',
                prefixIcon: Icon(Icons.badge_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 14),
              InlineNotice(message: _errorMessage!),
            ],
          ],
        ),
      ),
    );
  }
}

