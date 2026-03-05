import 'package:flutter/material.dart';
import 'package:ahbu/models/user_role.dart';
import 'package:ahbu/services/auth_service.dart';
import 'package:ahbu/styles/app_colors.dart';
import 'package:ahbu/styles/app_decorations.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.authService});

  final AuthService authService;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  UserRole _selectedRole = UserRole.superUser;
  bool _isLoginMode = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _fullNameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    setState(() => _isLoading = true);

    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text.trim();
    String? error;

    if (_isLoginMode) {
      error = await widget.authService.login(
        email: email,
        password: password,
        role: _selectedRole,
      );
    } else {
      error = await widget.authService.register(
        fullName: _fullNameController.text.trim(),
        phoneNumber: _phoneController.text.trim(),
        email: email,
        password: password,
        role: _selectedRole,
      );
    }

    if (!mounted) {
      return;
    }

    setState(() => _isLoading = false);

    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isLoginMode ? 'Uyelik Girisi' : 'Yeni Uyelik'),
      ),
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
                    Text(
                      _isLoginMode
                          ? 'Rol secip giris yapin'
                          : 'Hesap olusturun',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Mavi temali guvenli giris paneli',
                      style: TextStyle(color: AppColors.textMuted),
                    ),
                    const SizedBox(height: 20),
                    if (!_isLoginMode) ...[
                      TextFormField(
                        controller: _fullNameController,
                        decoration: const InputDecoration(
                          labelText: 'Ad Soyad',
                        ),
                        validator: (value) {
                          if (!_isLoginMode &&
                              (value ?? '').trim().length < 3) {
                            return 'Ad Soyad en az 3 karakter olmali.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Telefon Numarasi',
                        ),
                        validator: (value) {
                          final text = (value ?? '').trim();
                          if (text.isEmpty) {
                            return 'Telefon numarasi zorunlu.';
                          }
                          if (!RegExp(
                            r'^\+?[0-9()\-\s]{10,20}$',
                          ).hasMatch(text)) {
                            return 'Gecerli bir telefon numarasi girin.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                    ],
                    DropdownButtonFormField<UserRole>(
                      initialValue: _selectedRole,
                      decoration: const InputDecoration(labelText: 'Rol'),
                      items: UserRole.values
                          .map(
                            (role) => DropdownMenuItem<UserRole>(
                              value: role,
                              child: Text(role.label),
                            ),
                          )
                          .toList(),
                      onChanged: (role) {
                        if (role != null) {
                          setState(() => _selectedRole = role);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: 'E-posta'),
                      validator: (value) {
                        final text = (value ?? '').trim();
                        if (text.isEmpty || !text.contains('@')) {
                          return 'Gecerli bir e-posta girin.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'Sifre'),
                      validator: (value) {
                        if ((value ?? '').trim().length < 6) {
                          return 'Sifre en az 6 karakter olmali.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 18),
                    ElevatedButton(
                      onPressed: _isLoading ? null : _submit,
                      child: _isLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(_isLoginMode ? 'Giris Yap' : 'Kayit Ol'),
                    ),
                    TextButton(
                      onPressed: _isLoading
                          ? null
                          : () => setState(() => _isLoginMode = !_isLoginMode),
                      child: Text(
                        _isLoginMode
                            ? 'Hesabin yok mu? Kayit ol.'
                            : 'Hesabin var mi? Giris yap.',
                      ),
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
