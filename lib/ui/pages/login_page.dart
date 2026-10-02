import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:site_kapi_kontrol/config/app_config.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/login_hero.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/pages/register_individual_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.authService});

  final AuthService authService;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  static const String _savedIdentifierKey = 'saved_login_identifier';
  static const String _rememberMeKey = 'remember_login_credentials';

  final _formKey = GlobalKey<FormState>();
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _rememberMe = true;

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
    // Oturum sunucu tarafında sonlandırıldıysa (süre dolumu, parola değişimi, hesap pasif)
    // kullanıcı nedenini görsün.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final notice = widget.authService.takeSessionNotice();
      if (notice == null || notice.trim().isEmpty) return;
      AppSnack.show(
        context,
        notice,
        kind: AppSnackKind.warning,
        duration: const Duration(seconds: 6),
        maxLines: 8,
      );
    });
  }

  Future<void> _loadSavedCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final remember = prefs.getBool(_rememberMeKey) ?? true;
      final savedIdentifier = prefs.getString(_savedIdentifierKey);

      if (mounted) {
        setState(() {
          _rememberMe = remember;
          if (remember && savedIdentifier != null && savedIdentifier.trim().isNotEmpty) {
            _identifierController.text = savedIdentifier.trim();
          }
        });
      }
    } catch (_) {
      // Ignore prefs error
    }
  }

  Future<void> _saveCredentials(String identifier) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_rememberMeKey, _rememberMe);
      if (_rememberMe) {
        await prefs.setString(_savedIdentifierKey, identifier.trim());
      } else {
        await prefs.remove(_savedIdentifierKey);
      }
    } catch (_) {
      // Ignore prefs error
    }
  }

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }

    setState(() => _isLoading = true);

    final identifier = _identifierController.text.trim();
    final password = _passwordController.text;

    final errorMessage = await widget.authService.login(
      email: identifier,
      password: password,
    );

    if (mounted) {
      setState(() => _isLoading = false);

      if (errorMessage != null) {
        AppSnack.show(context, errorMessage, kind: AppSnackKind.error, maxLines: 8);
      } else {
        await _saveCredentials(identifier);
      }
    }
  }

  Future<void> _showForgotPasswordDialog() async {
    final initialEmail = _identifierController.text.contains('@')
        ? _identifierController.text.trim()
        : '';
    final emailController = TextEditingController(text: initialEmail);
    final formKey = GlobalKey<FormState>();
    bool isSubmitting = false;
    String? dialogError;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final p = context.palette;
            return AppDialog(
              title: 'Şifremi Unuttum',
              icon: Icons.lock_reset_rounded,
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.of(ctx).pop(),
                  style: TextButton.styleFrom(foregroundColor: p.textSecondary),
                  child: const Text('İptal'),
                ),
                ElevatedButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) return;
                          setDialogState(() {
                            isSubmitting = true;
                            dialogError = null;
                          });

                          final error = await widget.authService.forgotPassword(
                            email: emailController.text.trim(),
                          );

                          if (!mounted || !ctx.mounted) return;

                          if (error != null) {
                            setDialogState(() {
                              isSubmitting = false;
                              dialogError = error;
                            });
                          } else {
                            Navigator.of(ctx).pop();
                            if (!mounted) return;
                            AppSnack.show(
                              context,
                              'Bu e-posta adresiyle kayıtlı bir hesap varsa şifre sıfırlama bağlantısı gönderildi. Lütfen gelen kutunuzu (ve gereksiz klasörünü) kontrol ediniz.',
                              kind: AppSnackKind.success,
                              duration: const Duration(seconds: 5),
                              maxLines: 10,
                            );
                          }
                        },
                  // Gönderirken düğme pasif (soluk zemin): beyaz çark görünmez olurdu.
                  child: isSubmitting
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: p.textSecondary),
                        )
                      : const Text('Bağlantı Gönder'),
                ),
              ],
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Kayıtlı e-posta adresinizi giriniz. Hesap bulunursa şifrenizi yenileyebileceğiniz güvenli bir sıfırlama bağlantısı bu adrese gönderilir.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: AppSpace.lg),
                    if (dialogError != null) ...[
                      InlineNotice(message: dialogError!),
                      const SizedBox(height: AppSpace.md),
                    ],
                    TextFormField(
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'E-posta Adresi',
                        hintText: 'ornek@email.com',
                        prefixIcon: Icon(Icons.mail_outline_rounded),
                      ),
                      validator: (val) {
                        final text = (val ?? '').trim();
                        if (text.isEmpty) {
                          return 'Lütfen e-posta adresinizi girin.';
                        }
                        if (!text.contains('@') || !text.contains('.')) {
                          return 'Geçerli bir e-posta adresi girin.';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    // Dar ekranda (< 400 dp) yan boşluklar 16 dp: büyük yazıda içeriğe daha çok genişlik kalır.
    final hPad = MediaQuery.sizeOf(context).width < 400 ? AppSpace.lg : AppSpace.xl;

    // Sayfa zemini kökte (lib/app.dart builder) tek kez boyanır: burada ikinci zemin YOK.
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: hPad, vertical: AppSpace.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AppCard(
                level: 2,
                padding: EdgeInsets.symmetric(horizontal: hPad, vertical: AppSpace.xxl),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Logo + başlık
                      const LoginHero(
                        title: 'AHBU Giriş',
                        subtitle: 'Akıllı Kapı & Site Otomasyon Paneli',
                      ),
                      const SizedBox(height: AppSpace.xl),

                      // E-posta / Kullanıcı Adı
                      TextFormField(
                        controller: _identifierController,
                        keyboardType: TextInputType.text,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: const InputDecoration(
                          labelText: 'E-posta veya Kullanıcı Adı',
                          hintText: 'ornek@email.com veya daire1',
                          prefixIcon: Icon(Icons.person_outline_rounded),
                        ),
                        validator: (value) {
                          final text = (value ?? '').trim();
                          if (text.isEmpty) {
                            return 'Lütfen e-posta veya kullanıcı adınızı girin.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: AppSpace.lg),

                      // Şifre Alanı
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          labelText: 'Şifre',
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                            ),
                            onPressed: () {
                              setState(() => _obscurePassword = !_obscurePassword);
                            },
                          ),
                        ),
                        validator: (value) {
                          final text = (value ?? '').trim();
                          if (text.isEmpty) {
                            return 'Lütfen şifrenizi girin.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: AppSpace.md),

                      // Beni Hatırla: tüm satır dokunma alanı, ekran okuyucuya tek öğe (kutu + etiket).
                      MergeSemantics(
                        child: InkWell(
                          onTap: () {
                            setState(() => _rememberMe = !_rememberMe);
                          },
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          child: Row(
                            children: [
                              Checkbox(
                                value: _rememberMe,
                                onChanged: (val) {
                                  setState(() => _rememberMe = val ?? true);
                                },
                              ),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
                                  child: Text(
                                    'Beni Hatırla (Kullanıcı adını kaydet)',
                                    style: th.bodyMedium,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _isLoading ? null : _showForgotPasswordDialog,
                          child: const Text(
                            'Şifremi Unuttum?',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpace.sm),

                      // Giriş Yap: yüklenirken etiket yerine çark gösterilir (tıklama kapalı).
                      PrimaryActionButton(
                        label: 'Giriş Yap',
                        onPressed: _isLoading ? null : _submit,
                        loading: _isLoading,
                      ),
                      const SizedBox(height: AppSpace.lg),
                      Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text('Hesabınız yok mu? ', style: th.bodyMedium),
                          TextButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => RegisterIndividualPage(
                                    authService: widget.authService,
                                  ),
                                ),
                              );
                            },
                            child: const Text(
                              'Yeni Hesap Oluştur',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpace.sm),
                      Text(
                        AppConfig.versionDisplay,
                        textAlign: TextAlign.center,
                        style: th.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
