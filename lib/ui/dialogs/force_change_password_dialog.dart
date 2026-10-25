import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/password_policy.dart';

/// İlk girişte veya geçici şifreyle/PIN ile oturum açıldığında zorunlu şifre değiştirme popup'ı.
class ForceChangePasswordDialog extends StatefulWidget {
  const ForceChangePasswordDialog({
    super.key,
    required this.session,
    required this.authService,
    required this.onPasswordChanged,
    required this.onLogout,
  });

  final UserSession session;
  final AuthService authService;
  final ValueChanged<UserSession> onPasswordChanged;
  final VoidCallback onLogout;

  static Future<void> show({
    required BuildContext context,
    required UserSession session,
    required AuthService authService,
    required ValueChanged<UserSession> onPasswordChanged,
    required VoidCallback onLogout,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: ForceChangePasswordDialog(
          session: session,
          authService: authService,
          onPasswordChanged: onPasswordChanged,
          onLogout: onLogout,
        ),
      ),
    );
  }

  @override
  State<ForceChangePasswordDialog> createState() => _ForceChangePasswordDialogState();
}

class _ForceChangePasswordDialogState extends State<ForceChangePasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isLoading) return;
    setState(() => _errorMessage = null);

    if (!_formKey.currentState!.validate()) {
      return;
    }

    final currentPass = _currentPasswordController.text.trim();
    final newPass = _newPasswordController.text.trim();
    final confirmPass = _confirmPasswordController.text.trim();

    if (newPass != confirmPass) {
      setState(() => _errorMessage = 'Yeni şifreler birbiriyle eşleşmiyor.');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final error = await widget.authService.updateMyProfile(
        fullName: widget.session.fullName,
        email: widget.session.email,
        password: newPass,
        currentPassword: currentPass,
      );

      if (!mounted) return;

      if (error != null) {
        setState(() {
          _isLoading = false;
          _errorMessage = error;
        });
        return;
      }

      final updated = widget.authService.session ?? widget.session.copyWith(mustChangePassword: false);
      widget.onPasswordChanged(updated);
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Şifreniz başarıyla güncellendi. Güvenle kullanmaya devam edebilirsiniz.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpace.xl),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: primaryColor.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.lock_reset_rounded, color: primaryColor, size: 28),
                    ),
                    const SizedBox(width: AppSpace.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Yeni Şifrenizi Belirleyin',
                            style: th.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'İlk Giriş Güvenlik Doğrulaması',
                            style: th.bodySmall?.copyWith(color: p.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpace.lg),
                AppCard(
                  level: 1,
                  padding: const EdgeInsets.all(AppSpace.md),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline_rounded, color: primaryColor, size: 20),
                      const SizedBox(width: AppSpace.sm),
                      Expanded(
                        child: Text(
                          'Yöneticiniz tarafından verilen geçici şifre/PIN ile giriş yaptınız. '
                          'Hesap güvenliğiniz için lütfen yeni ve güçlü bir şifre belirleyiniz.',
                          style: th.bodySmall?.copyWith(color: p.textSecondary, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: AppSpace.md),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: Colors.red, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: th.bodySmall?.copyWith(color: Colors.red, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: AppSpace.lg),
                TextFormField(
                  controller: _currentPasswordController,
                  obscureText: _obscureCurrent,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: 'Mevcut Geçici Şifre / PIN',
                    prefixIcon: const Icon(Icons.key_outlined),
                    suffixIcon: IconButton(
                      icon: Icon(_obscureCurrent ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _obscureCurrent = !_obscureCurrent),
                    ),
                    helperText: 'Yöneticinizden aldığınız ilk şifre veya PIN kodunuz',
                  ),
                  validator: (v) => (v ?? '').trim().isEmpty ? 'Mevcut geçici şifrenizi girin.' : null,
                ),
                const SizedBox(height: AppSpace.md),
                TextFormField(
                  controller: _newPasswordController,
                  obscureText: _obscureNew,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: 'Yeni Şifreniz',
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    suffixIcon: IconButton(
                      icon: Icon(_obscureNew ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _obscureNew = !_obscureNew),
                    ),
                    helperText: PasswordPolicy.hint,
                  ),
                  validator: (v) => PasswordPolicy.validate(
                    (v ?? '').trim(),
                    allowEmpty: false,
                    email: widget.session.email,
                    names: [widget.session.fullName],
                  ),
                ),
                const SizedBox(height: AppSpace.md),
                TextFormField(
                  controller: _confirmPasswordController,
                  obscureText: _obscureConfirm,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: 'Yeni Şifreniz (Tekrar)',
                    prefixIcon: const Icon(Icons.check_circle_outline_rounded),
                    suffixIcon: IconButton(
                      icon: Icon(_obscureConfirm ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                    ),
                  ),
                  validator: (v) {
                    if ((v ?? '').trim().isEmpty) return 'Şifrenizi tekrar girin.';
                    if ((v ?? '').trim() != _newPasswordController.text.trim()) {
                      return 'Şifreler eşleşmiyor.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSpace.xl),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _submit,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.check_rounded),
                    label: Text(_isLoading ? 'Kaydediliyor...' : 'Yeni Şifremi Kaydet ve Devam Et'),
                  ),
                ),
                const SizedBox(height: AppSpace.sm),
                TextButton.icon(
                  onPressed: _isLoading
                      ? null
                      : () {
                          Navigator.of(context, rootNavigator: true).pop();
                          widget.onLogout();
                        },
                  icon: const Icon(Icons.logout_rounded, size: 18),
                  label: const Text('Şimdi Değil, Oturumu Kapat'),
                  style: TextButton.styleFrom(
                    foregroundColor: p.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
