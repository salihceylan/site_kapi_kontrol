import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
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
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Site Kapi Kontrol'),
      ),
      drawer: YanMenu(
        fullName: session.fullName,
        userEmail: session.email,
        roleLabel: session.role.label,
        onLogout: () => authService.logout(),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hos geldiniz, ${session.fullName}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text('E-posta: ${session.email}'),
            const SizedBox(height: 4),
            Text('Rol: ${session.role.label}'),
            const SizedBox(height: 20),
            Text(_roleDescription(session.role)),
          ],
        ),
      ),
    );
  }
}
