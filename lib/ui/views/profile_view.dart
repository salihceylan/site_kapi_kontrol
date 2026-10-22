import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/password_policy.dart';
import 'package:site_kapi_kontrol/ui/widgets/account_privacy_section.dart';
import 'package:site_kapi_kontrol/ui/widgets/language_picker.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/managed_user_card.dart';
import 'package:site_kapi_kontrol/ui/widgets/my_records_section.dart';
import 'package:site_kapi_kontrol/ui/widgets/notification_prefs_section.dart';
import 'package:site_kapi_kontrol/ui/widgets/search_visibility_section.dart';

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
    this.authService,
    this.showNotificationPrefs = false,
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

  /// Verilirse formun altında "Kayıtlarım" bölümü (kişi / daire kayıtlarım, salt okunur) gösterilir.
  final AuthService? authService;

  /// true (ve [authService] verilmişse): "Bildirim Tercihleri" bölümü (duyuru alabilen roller). Platform
  /// Faz 3a.
  final bool showNotificationPrefs;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    // Üstte kimlik özeti (hero), altında düzenleme formu: iki kardeş kart (kart-içinde-kart yok).
    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ProfileHero(session: session),
          const SizedBox(height: AppSpace.lg),
          AppCard(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: Form(
              key: formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionHeader(title: 'Kendi Bilgilerini Düzenle'),
                  const SizedBox(height: AppSpace.lg),
                  TextFormField(
                    controller: fullNameController,
                    decoration: const InputDecoration(labelText: 'Ad Soyad'),
                    validator: (value) => (value ?? '').trim().length < 3
                        ? 'Ad Soyad en az 3 karakter olmalı.'
                        : null,
                  ),
                  const SizedBox(height: AppSpace.md),
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
                      suffixIcon: const Icon(
                        Icons.lock_outline_rounded,
                        size: 18,
                      ),
                      helperText:
                          'E-posta adresi güvenlik nedeniyle değiştirilemez',
                      helperMaxLines: 2,
                    ),
                  ),
                  const SizedBox(height: AppSpace.md),
                  TextFormField(
                    controller: phoneController,
                    decoration: const InputDecoration(
                      labelText: 'Telefon (opsiyonel)',
                    ),
                  ),
                  // Kimlik alanları ile şifre değiştirme alanları ayrı gruplar.
                  const Divider(height: AppSpace.xl),
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
                  const SizedBox(height: AppSpace.md),
                  TextFormField(
                    controller: passwordController,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      labelText: 'Yeni Şifre (opsiyonel)',
                      helperText: PasswordPolicy.hint,
                    ),
                    validator: (value) => PasswordPolicy.validate(
                      (value ?? '').trim(),
                      allowEmpty: true,
                      email: emailController.text.trim(),
                      names: <String>[fullNameController.text],
                    ),
                  ),
                  const SizedBox(height: AppSpace.lg),
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
          const SizedBox(height: AppSpace.lg),
          const LanguagePicker(),
          if (authService != null) ...[
            const SizedBox(height: AppSpace.lg),
            MyRecordsSection(authService: authService!),
            const SizedBox(height: AppSpace.lg),
            SearchVisibilitySection(authService: authService!),
          ],
          if (authService != null && showNotificationPrefs) ...[
            const SizedBox(height: AppSpace.lg),
            NotificationPrefsSection(authService: authService!),
          ],
          if (authService != null) ...[
            const SizedBox(height: AppSpace.lg),
            AccountPrivacySection(authService: authService!),
          ],
        ],
      ),
    );
  }
}

/// Profil üst kartı (ekranın tek hero öğesi): rol tonunda büyük cilalı avatar ([UserRoleOrb], glow'lu),
/// ad, e-posta ve rol rozeti. Ad ve e-posta kırpılmadan sarar (en çok 3 / 2 satır); avatar büyük
/// yazıda (>= 1,75x) gizlenir.
class _ProfileHero extends StatelessWidget {
  const _ProfileHero({required this.session});

  final UserSession session;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final role = session.role;

    return AppCard(
      level: 2,
      padding: listCardPadding(context),
      child: Row(
        children: [
          UserRoleOrb(role: role, size: 64, glow: true, gap: AppSpace.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  session.fullName,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: th.titleLarge,
                ),
                const SizedBox(height: AppSpace.xs),
                Text(
                  session.email,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: th.bodyMedium,
                ),
                const SizedBox(height: AppSpace.sm),
                UserBadge(label: role.label, tone: role.tone),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Daire sakini (apartment_owner) için salt okunur hesap bilgileri. Sakin hesapları yönetici tarafından
/// yönetilir (kendi profilini güncelleyemez); "Profilim" menüsü boş sayfa yerine bu bilgileri gösterir.
class ResidentProfileView extends StatelessWidget {
  const ResidentProfileView({
    super.key,
    required this.session,
    this.authService,
    this.showNotificationPrefs = false,
    this.onOpenDebt,
  });

  final UserSession session;

  /// Verilirse hesap kartının altında "Kayıtlarım" bölümü (daire, ilişki, araç; salt okunur) gösterilir.
  final AuthService? authService;

  /// true (ve [authService] verilmişse): "Bildirim Tercihleri" bölümü (Platform Faz 3a).
  final bool showNotificationPrefs;

  /// Hesap silme engelinde "Borcum'a git" (ana sayfa Borcum menüsüne geçer).
  final VoidCallback? onOpenDebt;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final phone = (session.phoneNumber ?? '').trim();
    final loginName = (session.loginName ?? '').trim();
    final rows = <(String, String, AppTone?)>[
      ('Ad Soyad', session.fullName, null),
      if (loginName.isNotEmpty) ('Kullanıcı Adı', loginName, null),
      if (phone.isNotEmpty) ('Telefon', phone, null),
      ('Hesap Türü', session.role.label, session.role.tone),
    ];

    final card = SizedBox(
      width: double.infinity,
      child: AppCard(
        level: 2,
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                UserRoleOrb(
                  role: session.role,
                  size: 56,
                  glow: true,
                  gap: AppSpace.lg,
                ),
                const Expanded(child: SectionHeader(title: 'Hesap Bilgilerim')),
              ],
            ),
            const SizedBox(height: AppSpace.md),
            for (final (label, value, tone) in rows)
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
                      // Hesap türü rozet; dar ekran / büyük yazıda diğer satırlar gibi düz metin.
                      child: tone != null && !badgesAsText(context)
                          ? Align(
                              alignment: Alignment.centerRight,
                              child: StatusChip(label: value, tone: tone),
                            )
                          : Text(
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
    final service = authService;
    if (service == null) return card;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        card,
        const SizedBox(height: AppSpace.lg),
        MyRecordsSection(authService: service, showWhenEmpty: true),
        const SizedBox(height: AppSpace.lg),
        SearchVisibilitySection(authService: service),
        if (showNotificationPrefs) ...[
          const SizedBox(height: AppSpace.lg),
          NotificationPrefsSection(authService: service),
        ],
        const SizedBox(height: AppSpace.lg),
        AccountPrivacySection(authService: service, onOpenDebt: onOpenDebt),
      ],
    );
  }
}
