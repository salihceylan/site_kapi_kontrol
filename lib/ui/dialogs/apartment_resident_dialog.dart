import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/apartment_record.dart';
import 'package:site_kapi_kontrol/ui/helpers/ui_helpers.dart';

class ApartmentResidentFormResult {
  const ApartmentResidentFormResult({
    required this.fullName,
    required this.loginName,
    required this.email,
    required this.password,
    required this.phoneNumber,
    required this.isActive,
  });

  final String fullName;
  final String loginName;
  final String email;
  final String password;
  final String phoneNumber;
  final bool isActive;
}

class ApartmentResidentDialog extends StatefulWidget {
  const ApartmentResidentDialog({
    super.key,
    required this.apartment,
  });

  final ApartmentRecord apartment;

  static Future<ApartmentResidentFormResult?> show(
    BuildContext context, {
    required ApartmentRecord apartment,
  }) {
    return showDialog<ApartmentResidentFormResult>(
      context: context,
      builder: (_) => ApartmentResidentDialog(apartment: apartment),
    );
  }

  @override
  State<ApartmentResidentDialog> createState() =>
      _ApartmentResidentDialogState();
}

class _ApartmentResidentDialogState extends State<ApartmentResidentDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _fullNameController;
  late final TextEditingController _loginNameController;
  late final TextEditingController _emailController;
  late final TextEditingController _passwordController;
  late final TextEditingController _phoneController;
  late bool _isActive;

  @override
  void initState() {
    super.initState();
    _fullNameController = TextEditingController(
      text: widget.apartment.residentFullName ?? '',
    );
    _loginNameController = TextEditingController(
      text: widget.apartment.residentLoginName ?? '',
    );
    _emailController = TextEditingController(
      text: widget.apartment.residentEmail ?? '',
    );
    _passwordController = TextEditingController(
      text: widget.apartment.residentPinCode ?? '',
    );
    _phoneController = TextEditingController(
      text: widget.apartment.residentPhoneNumber ?? '',
    );
    _isActive = widget.apartment.residentIsActive ?? widget.apartment.isActive;
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _loginNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    Navigator.of(context).pop(
      ApartmentResidentFormResult(
        fullName: _fullNameController.text.trim(),
        loginName: _loginNameController.text.trim().toLowerCase(),
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
        phoneNumber: _phoneController.text.trim(),
        isActive: _isActive,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: Text('Daire Kullanıcı Ayarı - ${widget.apartment.label}'),
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
                  controller: _loginNameController,
                  decoration: const InputDecoration(labelText: 'Kullanıcı Adı'),
                  validator: (value) {
                    final text = (value ?? '').trim();
                    if (text.length < 3) {
                      return 'Kullanıcı adı en az 3 karakter olmalı.';
                    }
                    return RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(text)
                        ? null
                        : 'Sadece harf, rakam, nokta, alt çizgi ve tire kullanın.';
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Daire Sakini E-postası',
                    helperText: 'Mail gönderimi için opsiyonel.',
                  ),
                  validator: (value) {
                    final text = (value ?? '').trim();
                    if (text.isEmpty) return null;
                    return text.contains('@')
                        ? null
                        : 'Geçerli e-posta girin.';
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passwordController,
                  decoration: const InputDecoration(labelText: 'Şifre / PIN'),
                  keyboardType: TextInputType.number,
                  validator: (value) =>
                      RegExp(r'^\d{4}$').hasMatch((value ?? '').trim())
                          ? null
                          : 'PIN 4 haneli sayısal olmalı.',
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () {
                      final randomPin =
                          (1000 + (math.Random().nextInt(9000))).toString();
                      _passwordController.text = randomPin;
                    },
                    icon: const Icon(Icons.password_outlined, size: 18),
                    label: const Text('Rastgele PIN'),
                  ),
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
                SwitchListTile.adaptive(
                  value: _isActive,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Aktif'),
                  subtitle: Text(
                    _isActive
                        ? 'Daire kullanıcısı giriş yapabilir.'
                        : 'Daire kullanıcısı askıda kalır.',
                  ),
                  onChanged: (value) => setState(() => _isActive = value),
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
