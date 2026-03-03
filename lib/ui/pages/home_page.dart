import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/styles/app_colors.dart';
import 'package:site_kapi_kontrol/styles/app_decorations.dart';
import 'package:site_kapi_kontrol/ui/widgets/yan_menu.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.authService});

  final AuthService authService;

  String _roleDescription(UserRole role) {
    switch (role) {
      case UserRole.superUser:
        return 'Tum siteleri ve kullanicilari yonetebilirsiniz.';
      case UserRole.siteManager:
        return 'Kendi apartman/site ayarlarini yonetebilirsiniz.';
      case UserRole.apartmentOwner:
        return 'Kendi daire islemlerinizi takip edebilirsiniz.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = authService.session!;

    return Scaffold(
      appBar: AppBar(title: const Text('Site Kapi Kontrol')),
      drawer: YanMenu(
        fullName: session.fullName,
        userEmail: session.email,
        roleLabel: session.role.label,
        onLogout: () => authService.logout(),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(22),
              decoration: AppDecorations.glassCard,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Hos Geldiniz',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    session.fullName,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontSize: 28,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text('Rol: ${session.role.label}'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: AppDecorations.infoCard,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Profil Bilgisi',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text('E-posta: ${session.email}'),
                  if (session.phoneNumber != null && session.phoneNumber!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('Telefon: ${session.phoneNumber}'),
                  ],
                  if (session.createdAt != null) ...[
                    const SizedBox(height: 8),
                    Text('Kayit Tarihi: ${session.createdAt!.toLocal()}'),
                  ],
                  const SizedBox(height: 8),
                  Text(_roleDescription(session.role)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
