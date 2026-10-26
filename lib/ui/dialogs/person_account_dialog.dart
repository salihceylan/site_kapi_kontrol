import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart' show crmMessageOf;
import 'package:site_kapi_kontrol/ui/views/bulk_import_controller.dart' show generateUsernameFromFullName;

/// Kişiye kullanıcı adı ve geçici başlangıç şifresi (1234 veya PIN) tanımlama penceresi.
class PersonAccountDialog extends StatefulWidget {
  const PersonAccountDialog({
    super.key,
    required this.siteCode,
    required this.personId,
    required this.personName,
    this.initialEmail,
    this.initialUsername,
    this.hasAccount = false,
    required this.authService,
  });

  final int siteCode;
  final int personId;
  final String personName;
  final String? initialEmail;
  final String? initialUsername;
  final bool hasAccount;
  final AuthService authService;

  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    required int siteCode,
    required int personId,
    required String personName,
    String? initialEmail,
    String? initialUsername,
    bool hasAccount = false,
    required AuthService authService,
  }) {
    return showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PersonAccountDialog(
        siteCode: siteCode,
        personId: personId,
        personName: personName,
        initialEmail: initialEmail,
        initialUsername: initialUsername,
        hasAccount: hasAccount,
        authService: authService,
      ),
    );
  }

  @override
  State<PersonAccountDialog> createState() => _PersonAccountDialogState();
}

class _PersonAccountDialogState extends State<PersonAccountDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _loginNameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _emailController;

  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final defaultLogin = widget.initialUsername?.isNotEmpty == true
        ? widget.initialUsername!
        : generateUsernameFromFullName(widget.personName);

    _loginNameController = TextEditingController(text: defaultLogin);
    _passwordController = TextEditingController(text: '1234');
    _emailController = TextEditingController(text: widget.initialEmail ?? '');
  }

  @override
  void dispose() {
    _loginNameController.dispose();
    _passwordController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  void _generateRandomPin() {
    final rnd = math.Random();
    final pin = (1000 + rnd.nextInt(9000)).toString();
    setState(() {
      _passwordController.text = pin;
    });
    HapticFeedback.lightImpact();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final loginName = _loginNameController.text.trim().toLowerCase();
    final password = _passwordController.text.trim();
    final email = _emailController.text.trim();

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await widget.authService.provisionPersonAccount(
        widget.siteCode,
        widget.personId,
        loginName: loginName,
        password: password,
        email: email.isNotEmpty ? email : null,
      );

      if (!mounted) return;

      Navigator.of(context).pop(res);

      final returnedLogin = res['login_name']?.toString() ?? loginName;
      final returnedPass = res['temp_password']?.toString() ?? password;

      await AccountCredentialsIssuedDialog.show(
        context,
        personName: widget.personName,
        loginName: returnedLogin,
        password: returnedPass,
        isNew: res['is_new'] != false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = crmMessageOf(e, 'Hesap işlemi gerçekleştirilemedi.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;

    return AppDialog(
      title: widget.hasAccount ? 'Geçici Şifre / Hesap Güncelle' : 'Hesap ve Şifre Tanımla',
      subtitle: widget.personName,
      icon: Icons.key_rounded,
      tone: AppTone.primary,
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(),
          child: const Text('Vazgeç'),
        ),
        PrimaryActionButton(
          label: widget.hasAccount ? 'Şifreyi Güncelle' : 'Hesabı Tanımla ve Şifre Ver',
          icon: Icons.check_circle_rounded,
          onPressed: _loading ? null : _submit,
        ),
      ],
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null) ...[
              InlineNotice(tone: AppTone.danger, message: _error!),
              const SizedBox(height: AppSpace.md),
            ],
            TextFormField(
              controller: _loginNameController,
              decoration: const InputDecoration(
                labelText: 'Kullanıcı Adı *',
                hintText: 'ornek.kullanici',
                prefixIcon: Icon(Icons.alternate_email_rounded),
                helperText: 'Sakin bu kullanıcı adıyla giriş yapacaktır.',
              ),
              textInputAction: TextInputAction.next,
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'Kullanıcı adı boş bırakılamaz.';
                }
                if (v.trim().length < 3) {
                  return 'Kullanıcı adı en az 3 karakter olmalıdır.';
                }
                return null;
              },
            ),
            const SizedBox(height: AppSpace.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _passwordController,
                    decoration: const InputDecoration(
                      labelText: 'Geçici Şifre / PIN *',
                      hintText: '1234',
                      prefixIcon: Icon(Icons.password_rounded),
                      helperText: 'İlk girişte değiştirilmesi istenir.',
                    ),
                    textInputAction: TextInputAction.next,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Geçici şifre boş bırakılamaz.';
                      }
                      if (v.trim().length < 4) {
                        return 'Şifre en az 4 karakter olmalıdır.';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: OutlinedButton.icon(
                    onPressed: _loading ? null : _generateRandomPin,
                    icon: const Icon(Icons.casino_outlined, size: 16),
                    label: const Text('Rastgele PIN'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.md),
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'İletişim E-postası (İsteğe bağlı)',
                hintText: 'sakin@ornek.com',
                prefixIcon: Icon(Icons.email_outlined),
                helperText: 'Girilirse şifre sıfırlama vb. için kullanılabilir.',
              ),
            ),
            const SizedBox(height: AppSpace.lg),
            Container(
              padding: const EdgeInsets.all(AppSpace.md),
              decoration: BoxDecoration(
                color: p.surfaceMuted,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: p.border),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, size: 20, color: p.textSecondary),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: Text(
                      'Sakin bu kullanıcı adı ve şifreyle sisteme hemen giriş yapabilir. Güvenlik standardı gereği sakin ilk girişinde kendi kalıcı şifresini belirleyecektir.',
                      style: th.bodySmall?.copyWith(color: p.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
            if (_loading) ...[
              const SizedBox(height: AppSpace.md),
              const LinearProgressIndicator(),
            ],
          ],
        ),
      ),
    );
  }
}

/// Hesap tanımlandıktan veya PIN sıfırlandıktan sonra sakine verilecek bilgileri gösteren modal.
class AccountCredentialsIssuedDialog extends StatefulWidget {
  const AccountCredentialsIssuedDialog({
    super.key,
    required this.personName,
    required this.loginName,
    required this.password,
    this.isNew = true,
  });

  final String personName;
  final String loginName;
  final String password;
  final bool isNew;

  static Future<void> show(
    BuildContext context, {
    required String personName,
    required String loginName,
    required String password,
    bool isNew = true,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AccountCredentialsIssuedDialog(
        personName: personName,
        loginName: loginName,
        password: password,
        isNew: isNew,
      ),
    );
  }

  @override
  State<AccountCredentialsIssuedDialog> createState() => _AccountCredentialsIssuedDialogState();
}

class _AccountCredentialsIssuedDialogState extends State<AccountCredentialsIssuedDialog> {
  bool _copied = false;

  String get _shareText => '''Site Yönetim Sistemi Giriş Bilgileriniz:
Kullanıcı Adı: ${widget.loginName}
Geçici Şifre: ${widget.password}
İlk girişinizde yeni kalıcı şifrenizi belirleyebilirsiniz.''';

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _shareText));
    if (!mounted) return;
    HapticFeedback.lightImpact();
    setState(() => _copied = true);
    AppSnack.show(context, 'Giriş bilgileri panoya kopyalandı.', kind: AppSnackKind.success);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;

    return AppDialog(
      title: widget.isNew ? 'Hesap Başarıyla Tanımlandı' : 'Şifre Başarıyla Güncellendi',
      subtitle: widget.personName,
      icon: Icons.check_circle_rounded,
      tone: AppTone.success,
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Tamam'),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSpace.sm),
          Container(
            padding: const EdgeInsets.all(AppSpace.md),
            decoration: BoxDecoration(
              color: p.surfaceMuted,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: p.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Kullanıcı Adı', style: th.bodySmall?.copyWith(color: p.textSecondary)),
                const SizedBox(height: AppSpace.xs),
                SelectableText(
                  widget.loginName,
                  style: th.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: p.text),
                ),
                const SizedBox(height: AppSpace.md),
                Text('Geçici Şifre (PIN)', style: th.bodySmall?.copyWith(color: p.textSecondary)),
                const SizedBox(height: AppSpace.xs),
                SelectableText(
                  widget.password,
                  style: th.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 4,
                    color: p.text,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.md),
          ElevatedButton.icon(
            onPressed: _copy,
            style: ElevatedButton.styleFrom(
              backgroundColor: p.action,
              foregroundColor: p.onAction,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: Icon(_copied ? Icons.check_rounded : Icons.copy_rounded, size: 18),
            label: Text(_copied ? 'Kopyalandı' : 'Sakine İletmek İçin Bilgileri Kopyala'),
          ),
          const SizedBox(height: AppSpace.md),
          const InlineNotice(
            tone: AppTone.info,
            icon: Icons.visibility_off_outlined,
            message: 'Bu şifre sakine verildikten sonra ilk girişte değiştirilecektir.',
          ),
        ],
      ),
    );
  }
}
