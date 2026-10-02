import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

class ProfileView extends StatelessWidget {
  const ProfileView({
    super.key,
    required this.session,
    required this.formKey,
    required this.fullNameController,
    required this.emailController,
    required this.phoneController,
    required this.passwordController,
    required this.currentPasswordController,
    required this.isSaving,
    required this.onSave,
  });

  final UserSession session;
  final GlobalKey<FormState> formKey;
  final TextEditingController fullNameController;
  final TextEditingController emailController;
  final TextEditingController phoneController;
  final TextEditingController passwordController;

  /// Şifre değiştirilirken sunucuya gönderilen mevcut şifre (current_password).
  final TextEditingController currentPasswordController;
  final bool isSaving;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return SizedBox(
      width: double.infinity,
      child: AppCard(
        padding: const EdgeInsets.all(18),
        child: Form(
          key: formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeader(title: 'Kendi Bilgilerini Düzenle'),
              const SizedBox(height: AppSpace.md),
              TextFormField(
                controller: fullNameController,
                decoration: const InputDecoration(labelText: 'Ad Soyad'),
                validator: (value) => (value ?? '').trim().length < 3
                    ? 'Ad Soyad en az 3 karakter olmalı.'
                    : null,
              ),
              const SizedBox(height: 10),
              // Değiştirilemez alan: kenarlık temanın `disabledBorder`ından gelir; metin okunur kalır
              // (devre dışı varsayılan rengi %38 opaklıktır).
              TextFormField(
                controller: emailController,
                enabled: false,
                style: TextStyle(color: p.textSecondary),
                decoration: InputDecoration(
                  labelText: 'E-posta (Değiştirilemez)',
                  filled: true,
                  fillColor: p.surfaceMuted,
                  suffixIcon: const Icon(Icons.lock_outline_rounded, size: 18),
                  helperText: 'E-posta adresi güvenlik nedeniyle değiştirilemez',
                  helperMaxLines: 2,
                ),
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
                controller: currentPasswordController,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: 'Mevcut Şifre',
                  helperText: 'Şifrenizi değiştirmek için zorunludur',
                  helperMaxLines: 2,
                ),
                validator: (value) {
                  final newPassword = passwordController.text.trim();
                  if (newPassword.isNotEmpty && (value ?? '').isEmpty) {
                    return 'Şifre değiştirmek için mevcut şifrenizi girin.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: passwordController,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
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
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Daire sakini (apartment_owner) için salt okunur hesap bilgileri. Sakin hesapları yönetici tarafından
/// yönetilir (kendi profilini güncelleyemez); "Profilim" menüsü boş sayfa yerine bu bilgileri gösterir.
class ResidentProfileView extends StatelessWidget {
  const ResidentProfileView({super.key, required this.session});

  final UserSession session;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final phone = (session.phoneNumber ?? '').trim();
    final loginName = (session.loginName ?? '').trim();
    final rows = <(String, String)>[
      ('Ad Soyad', session.fullName),
      if (loginName.isNotEmpty) ('Kullanıcı Adı', loginName),
      if (phone.isNotEmpty) ('Telefon', phone),
      ('Hesap Türü', session.role.label),
    ];

    return SizedBox(
      width: double.infinity,
      child: AppCard(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeader(title: 'Hesap Bilgilerim'),
            const SizedBox(height: 12),
            for (final (label, value) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(
                        label,
                        style: th.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 3,
                      child: Text(
                        value,
                        textAlign: TextAlign.end,
                        style: th.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 10),
            Text(
              'Daire sakini bilgileriniz site yöneticiniz tarafından yönetilir. '
              'Değişiklik için yöneticinizle iletişime geçin.',
              style: th.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
