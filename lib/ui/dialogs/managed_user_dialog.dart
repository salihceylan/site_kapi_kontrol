import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/managed_user_account.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/styles/app_colors.dart';
import 'package:site_kapi_kontrol/ui/helpers/ui_helpers.dart';

class ManagedUserFormResult {
  const ManagedUserFormResult({
    required this.fullName,
    required this.email,
    required this.phoneNumber,
    required this.password,
    required this.isActive,
  });

  final String fullName;
  final String email;
  final String phoneNumber;
  final String password;
  final bool isActive;
}

class ManagedUserDialog extends StatefulWidget {
  const ManagedUserDialog({
    super.key,
    required this.role,
    required this.roleTitle,
    required this.user,
    required this.isSelf,
  });

  final UserRole role;
  final String roleTitle;
  final ManagedUserAccount? user;
  final bool isSelf;

  static Future<ManagedUserFormResult?> show(
    BuildContext context, {
    required UserRole role,
    required String roleTitle,
    ManagedUserAccount? user,
    required bool isSelf,
  }) {
    return showDialog<ManagedUserFormResult>(
      context: context,
      builder: (_) => ManagedUserDialog(
        role: role,
        roleTitle: roleTitle,
        user: user,
        isSelf: isSelf,
      ),
    );
  }

  @override
  State<ManagedUserDialog> createState() => _ManagedUserDialogState();
}

class _ManagedUserDialogState extends State<ManagedUserDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _fullNameController;
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;
  late final TextEditingController _passwordController;
  late bool _isActive;

  bool get _isEditing => widget.user != null;

  @override
  void initState() {
    super.initState();
    _fullNameController = TextEditingController(
      text: widget.user?.fullName ?? '',
    );
    _emailController = TextEditingController(text: widget.user?.email ?? '');
    _phoneController = TextEditingController(
      text: widget.user?.phoneNumber ?? '',
    );
    _passwordController = TextEditingController();
    _isActive = widget.user?.isActive ?? (widget.role == UserRole.superUser);
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    Navigator.of(context).pop(
      ManagedUserFormResult(
        fullName: _fullNameController.text.trim(),
        email: _emailController.text.trim().toLowerCase(),
        phoneNumber: _phoneController.text.trim(),
        password: _passwordController.text.trim(),
        isActive: _isActive,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: Text(
        _isEditing
            ? '${widget.roleTitle} Düzenle'
            : 'Yeni ${widget.roleTitle} Ekle',
      ),
      content: SizedBox(
        width: dialogWidthForScreen(context),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _fullNameController,
                  decoration: const InputDecoration(labelText: 'Ad Soyad'),
                  validator: (value) => (value ?? '').trim().length < 3
                      ? 'Ad Soyad en az 3 karakter olmalı.'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'E-posta'),
                  validator: (value) {
                    final text = (value ?? '').trim();
                    return text.isEmpty || !text.contains('@')
                        ? 'Geçerli bir e-posta girin.'
                        : null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Telefon (opsiyonel)',
                  ),
                  validator: (value) {
                    final text = (value ?? '').trim();
                    if (text.isEmpty) return null;
                    return RegExp(r'^\+?[0-9()\-\s]{10,20}$').hasMatch(text)
                        ? null
                        : 'Geçerli bir telefon numarası girin.';
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: _isEditing ? 'Yeni Şifre (opsiyonel)' : 'Şifre',
                  ),
                  validator: (value) {
                    final text = (value ?? '').trim();
                    if (!_isEditing && text.length < 6) {
                      return 'Şifre en az 6 karakter olmalı.';
                    }
                    if (_isEditing && text.isNotEmpty && text.length < 6) {
                      return 'Şifre en az 6 karakter olmalı.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                SwitchListTile.adaptive(
                  value: _isActive,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Aktif'),
                  subtitle: Text(
                    _isActive
                        ? 'Kullanıcı giriş yapabilir.'
                        : 'Kullanıcı giriş yapamaz.',
                  ),
                  onChanged: widget.isSelf
                      ? null
                      : (value) => setState(() => _isActive = value),
                ),
                if (widget.isSelf)
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Kendi süper kullanıcı hesabınızı burada pasif yapamazsınız.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('İptal'),
        ),
        ElevatedButton(onPressed: _submit, child: const Text('Kaydet')),
      ],
    );
  }
}

