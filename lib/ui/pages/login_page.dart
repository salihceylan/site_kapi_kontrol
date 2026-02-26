import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.authService});

  final AuthService authService;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  UserRole _selectedRole = UserRole.superUser;
  bool _isLoginMode = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _fullNameController.dispose();
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(_isLoginMode ? 'Uyelik Girisi' : 'Yeni Uyelik'),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _isLoginMode ? 'Rol secip giris yapin' : 'Hesap olusturun',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                if (!_isLoginMode) ...[
                  TextFormField(
                    controller: _fullNameController,
                    decoration: const InputDecoration(labelText: 'Ad Soyad'),
                    validator: (value) {
                      if (!_isLoginMode && (value ?? '').trim().length < 3) {
                        return 'Ad Soyad en az 3 karakter olmali.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                ],
                DropdownButtonFormField<UserRole>(
                  value: _selectedRole,
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
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _isLoading ? null : _submit,
                  child: _isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
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
                const SizedBox(height: 12),
                const Text(
                  'API: --dart-define=API_BASE_URL=http://localhost:8080',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
