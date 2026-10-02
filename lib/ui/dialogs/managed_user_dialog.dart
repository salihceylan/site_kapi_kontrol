import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/managed_user_account.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

class ManagedUserFormResult {
  const ManagedUserFormResult({
    required this.fullName,
    required this.email,
    required this.phoneNumber,
    required this.password,
    required this.isActive,
    this.role,
    this.emailVerified,
  });

  final String fullName;
  final String email;
  final String phoneNumber;
  final String password;
  final bool isActive;
  final UserRole? role;
  final bool? emailVerified;
}

class ManagedUserDialog extends StatefulWidget {
  const ManagedUserDialog({
    super.key,
    required this.role,
    required this.roleTitle,
    required this.user,
    required this.isSelf,
    this.allowRoleSelection = false,
  });

  final UserRole role;
  final String roleTitle;
  final ManagedUserAccount? user;
  final bool isSelf;
  final bool allowRoleSelection;

  static Future<ManagedUserFormResult?> show(
    BuildContext context, {
    required UserRole role,
    required String roleTitle,
    ManagedUserAccount? user,
    required bool isSelf,
    bool allowRoleSelection = false,
  }) {
    return showDialog<ManagedUserFormResult>(
      context: context,
      builder: (_) => ManagedUserDialog(
        role: role,
        roleTitle: roleTitle,
        user: user,
        isSelf: isSelf,
        allowRoleSelection: allowRoleSelection,
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
  late bool _emailVerified;
  late UserRole _selectedRole;

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
    _emailVerified = widget.user?.emailVerified ?? true;
    _selectedRole = widget.user?.role ?? widget.role;
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
        role: widget.allowRoleSelection ? _selectedRole : null,
        emailVerified: _emailVerified,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return AppDialog(
      title: _isEditing
          ? '${widget.roleTitle} Düzenle'
          : 'Yeni ${widget.roleTitle} Ekle',
      icon: Icons.manage_accounts_rounded,
      tone: widget.role.tone,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('İptal'),
        ),
        ElevatedButton(onPressed: _submit, child: const Text('Kaydet')),
      ],
      child: Form(
        key: _formKey,
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
              enabled: !_isEditing,
              style: TextStyle(
                color: _isEditing ? p.textSecondary : null,
              ),
              decoration: InputDecoration(
                labelText: _isEditing ? 'E-posta (Değiştirilemez)' : 'E-posta',
                filled: _isEditing,
                fillColor: _isEditing ? p.surfaceMuted : null,
                suffixIcon: _isEditing ? const Icon(Icons.lock_outline_rounded, size: 18) : null,
                helperText: _isEditing ? 'E-posta adresi güvenlik nedeniyle değiştirilemez' : null,
              ),
              validator: (value) {
                if (_isEditing) return null;
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
            if (widget.allowRoleSelection) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<UserRole>(
                isExpanded: true,
                initialValue: _selectedRole,
                decoration: const InputDecoration(labelText: 'Kullanıcı Rolü'),
                items: UserRole.values.map((r) {
                  return DropdownMenuItem(
                    value: r,
                    child: Text(r.label, overflow: TextOverflow.ellipsis),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _selectedRole = val);
                  }
                },
              ),
            ],
            // Şifre alanı yalnızca YENİ kullanıcı eklerken gösterilir. Kendi hesabını düzenleyen
            // kullanıcı için de gizlidir: sunucu bu uçta kendi şifre değişimini (mevcut şifre
            // doğrulaması olmadığından) reddeder; değişiklik "Profilim" ekranından yapılır.
            if (!_isEditing) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Şifre'),
                validator: (value) {
                  final text = (value ?? '').trim();
                  if (text.length < 6) {
                    return 'Şifre en az 6 karakter olmalı.';
                  }
                  return null;
                },
              ),
            ] else ...[
              const SizedBox(height: 12),
              InlineNotice(
                tone: AppTone.info,
                icon: Icons.lock_outline_rounded,
                message: widget.isSelf
                    ? 'Güvenlik gereği kendi şifrenizi buradan değiştiremezsiniz. '
                        'Şifrenizi "Profilim" ekranından, mevcut şifrenizle değiştirin.'
                    : 'Güvenlik gereği kullanıcı şifresini yalnızca kendi hesabından değiştirebilir.',
              ),
            ],
            const SizedBox(height: 12),
            SwitchListTile.adaptive(
              value: _isActive,
              contentPadding: EdgeInsets.zero,
              title: const Text('Hesap Aktif'),
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
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Kendi süper kullanıcı hesabınızı burada pasif yapamazsınız.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 8),
            SwitchListTile.adaptive(
              value: _emailVerified,
              contentPadding: EdgeInsets.zero,
              title: const Text('E-Posta Doğrulandı'),
              subtitle: Text(
                _emailVerified
                    ? 'E-posta doğrulama şartı sağlanmış.'
                    : 'E-posta henüz doğrulanmamış.',
              ),
              onChanged: (value) => setState(() => _emailVerified = value),
            ),
          ],
        ),
      ),
    );
  }
}

