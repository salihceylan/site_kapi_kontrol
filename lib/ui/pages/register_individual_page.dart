import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/pages/verify_email_code_page.dart';

class RegisterIndividualPage extends StatefulWidget {
  const RegisterIndividualPage({
    super.key,
    required this.authService,
  });

  final AuthService authService;

  @override
  State<RegisterIndividualPage> createState() => _RegisterIndividualPageState();
}

class _RegisterIndividualPageState extends State<RegisterIndividualPage> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text.trim();

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final error = await widget.authService.registerIndividual(
      firstName: firstName,
      lastName: lastName,
      email: email,
      password: password,
    );

    if (!mounted) return;

    setState(() => _isLoading = false);

    if (error != null) {
      setState(() => _errorMessage = error);
    } else {
      // 4 Haneli Kod Doğrulama Ekranına Yönlendir
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => VerifyEmailCodePage(
            authService: widget.authService,
            email: email,
            fullName: '$firstName $lastName',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    // Dar ekranda (< 400 dp) yan boşluklar 16 dp: büyük yazıda içeriğe daha çok genişlik kalır.
    final hPad = MediaQuery.sizeOf(context).width < 400 ? AppSpace.lg : AppSpace.xl;

    // Sayfa zemini kökte (lib/app.dart builder) tek kez boyanır: Scaffold şeffaf kalır.
    return Scaffold(
      appBar: AppBar(
        title: const Text('Yeni Hesap Oluştur'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: hPad, vertical: AppSpace.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: AppCard(
                level: 2,
                padding: EdgeInsets.symmetric(horizontal: hPad, vertical: AppSpace.xl),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Başlık
                      Semantics(
                        header: true,
                        child: Text(
                          'Kayıt Ol',
                          textAlign: TextAlign.center,
                          style: th.headlineMedium,
                        ),
                      ),
                      const SizedBox(height: AppSpace.xs),
                      Text(
                        'Kapı kontrol ve site üyelik hesabınızı oluşturun',
                        textAlign: TextAlign.center,
                        style: th.bodyMedium,
                      ),
                      const SizedBox(height: AppSpace.xl),

                      // Hata Mesajı
                      if (_errorMessage != null) ...[
                        InlineNotice(message: _errorMessage!),
                        const SizedBox(height: AppSpace.lg),
                      ],

                      // Ad & Soyad: geniş kartta yan yana, telefonda ve büyük yazıda alt alta
                      // (yan yana iki alan metne yalnız birkaç karakterlik yer bırakırdı).
                      LayoutBuilder(
                        builder: (context, box) {
                          final textScale = MediaQuery.textScalerOf(context).scale(16) / 16;
                          final sideBySide = box.maxWidth >= 380 && textScale <= 1.15;
                          final fieldWidth = sideBySide
                              ? ((box.maxWidth - AppSpace.md) / 2).floorToDouble()
                              : box.maxWidth;
                          return Wrap(
                            spacing: AppSpace.md,
                            runSpacing: AppSpace.lg,
                            children: [
                              SizedBox(
                                width: fieldWidth,
                                child: TextFormField(
                                  controller: _firstNameController,
                                  textCapitalization: TextCapitalization.words,
                                  decoration: const InputDecoration(
                                    labelText: 'Ad',
                                    hintText: 'Adınız',
                                    prefixIcon: Icon(Icons.person_outline_rounded, size: 20),
                                  ),
                                  validator: (val) {
                                    if (val == null || val.trim().isEmpty) {
                                      return 'Ad gerekli';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                              SizedBox(
                                width: fieldWidth,
                                child: TextFormField(
                                  controller: _lastNameController,
                                  textCapitalization: TextCapitalization.words,
                                  decoration: const InputDecoration(
                                    labelText: 'Soyad',
                                    hintText: 'Soyadınız',
                                    prefixIcon: Icon(Icons.badge_outlined, size: 20),
                                  ),
                                  validator: (val) {
                                    if (val == null || val.trim().isEmpty) {
                                      return 'Soyad gerekli';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: AppSpace.lg),

                      // E-posta
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'E-Posta',
                          hintText: 'ornek@email.com',
                          prefixIcon: Icon(Icons.email_outlined, size: 20),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'E-posta adresi zorunludur';
                          }
                          if (!val.contains('@') || !val.contains('.')) {
                            return 'Geçerli bir e-posta adresi giriniz';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: AppSpace.lg),

                      // Şifre
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          labelText: 'Şifre',
                          hintText: 'En az 6 karakter',
                          prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                              size: 20,
                            ),
                            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                          ),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Şifre zorunludur';
                          }
                          if (val.trim().length < 6) {
                            return 'Şifre en az 6 karakter olmalıdır';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: AppSpace.lg),

                      // Şifre Tekrar
                      TextFormField(
                        controller: _confirmPasswordController,
                        obscureText: _obscureConfirmPassword,
                        decoration: InputDecoration(
                          labelText: 'Şifre Tekrar',
                          hintText: 'Şifrenizi tekrar giriniz',
                          prefixIcon: const Icon(Icons.lock_reset_rounded, size: 20),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureConfirmPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                              size: 20,
                            ),
                            onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                          ),
                        ),
                        validator: (val) {
                          if (val != _passwordController.text) {
                            return 'Şifreler birbiriyle eşleşmiyor';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: AppSpace.xl),

                      // Kayıt Ol: yüklenirken etiket yerine çark gösterilir (tıklama kapalı).
                      PrimaryActionButton(
                        label: 'Kayıt Ol',
                        onPressed: _isLoading ? null : _submit,
                        loading: _isLoading,
                      ),
                      const SizedBox(height: AppSpace.lg),

                      // Zaten Hesabım Var (Wrap: dar ekranda / büyük yazıda taşmadan alt satıra iner)
                      Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text('Zaten bir hesabınız var mı? ', style: th.bodyMedium),
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text(
                              'Giriş Yapın',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
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
