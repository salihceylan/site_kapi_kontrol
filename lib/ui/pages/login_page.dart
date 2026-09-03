import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/styles/app_colors.dart';
import 'package:site_kapi_kontrol/styles/app_decorations.dart';

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
  }

  Future<void> _loadSavedCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final remember = prefs.getBool(_rememberMeKey) ?? true;
      final savedId = prefs.getString(_savedIdentifierKey) ?? '';
      if (mounted) {
        setState(() {
          _rememberMe = remember;
          if (remember && savedId.isNotEmpty) {
            _identifierController.text = savedId;
          }
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final identifier = _identifierController.text.trim().toLowerCase();
    final password = _passwordController.text.trim();

    setState(() => _isLoading = true);
    final error = await widget.authService.login(
      email: identifier,
      password: password,
    );

    if (!mounted) {
      return;
    }

    setState(() => _isLoading = false);
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
    } else {
      // Başarılı girişte kullanıcı adını hatırla
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_rememberMeKey, _rememberMe);
        if (_rememberMe) {
          await prefs.setString(_savedIdentifierKey, identifier);
        } else {
          await prefs.remove(_savedIdentifierKey);
        }
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AHBU Giris')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Container(
              decoration: AppDecorations.glassCard,
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(22),
                        child: Image.asset(
                          'assets/images/app_logo.png',
                          width: 88,
                          height: 88,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'AHBU hesabınızla giriş yapın',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Yetkili olduğunuz siteler, kapılar ve menü işlemleri rolünüze göre açılır.',
                      style: TextStyle(color: AppColors.textMuted),
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _identifierController,
                      keyboardType: TextInputType.text,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: const InputDecoration(
                        labelText: 'E-posta veya Kullanıcı Adı',
                        hintText: 'örn: ornek@email.com veya ablokdaire1',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      validator: (value) {
                        final text = (value ?? '').trim();
                        if (text.isEmpty) {
                          return 'Lütfen e-posta veya kullanıcı adınızı girin.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: 'Şifre',
                        prefixIcon: const Icon(Icons.lock_outline),
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
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        SizedBox(
                          height: 24,
                          width: 24,
                          child: Checkbox(
                            value: _rememberMe,
                            onChanged: (val) {
                              setState(() => _rememberMe = val ?? true);
                            },
                            activeColor: AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setState(() => _rememberMe = !_rememberMe);
                            },
                            child: const Text(
                              'Beni Hatırla (Kullanıcı adını kaydet)',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.textDark,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _isLoading ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Giris Yap', style: TextStyle(fontSize: 16)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
