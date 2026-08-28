import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/styles/app_colors.dart';
import 'package:site_kapi_kontrol/styles/app_decorations.dart';

class ProfileView extends StatelessWidget {
  const ProfileView({
    super.key,
    required this.session,
    required this.formKey,
    required this.fullNameController,
    required this.emailController,
    required this.phoneController,
    required this.passwordController,
    required this.isSaving,
    required this.onSave,
  });

  final UserSession session;
  final GlobalKey<FormState> formKey;
  final TextEditingController fullNameController;
  final TextEditingController emailController;
  final TextEditingController phoneController;
  final TextEditingController passwordController;
  final bool isSaving;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: AppDecorations.glassCard,
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Kendi Bilgilerini Düzenle',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: fullNameController,
              decoration: const InputDecoration(labelText: 'Ad Soyad'),
              validator: (value) => (value ?? '').trim().length < 3
                  ? 'Ad Soyad en az 3 karakter olmalı.'
                  : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: emailController,
              decoration: const InputDecoration(labelText: 'E-posta'),
              validator: (value) {
                final text = (value ?? '').trim();
                return text.isEmpty || !text.contains('@')
                    ? 'Geçerli bir e-posta girin.'
                    : null;
              },
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: phoneController,
              decoration: const InputDecoration(
                labelText: 'Telefon (opsiyonel)',
              ),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Yeni Şifre (opsiyonel)',
              ),
              validator: (value) {
                final text = (value ?? '').trim();
                return text.isNotEmpty && text.length < 6
                    ? 'Şifre en az 6 karakter olmalı.'
                    : null;
              },
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: isSaving ? null : onSave,
                icon: isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(
                  isSaving ? 'Kaydediliyor...' : 'Profili Kaydet',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
