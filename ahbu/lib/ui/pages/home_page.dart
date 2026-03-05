import 'package:flutter/material.dart';
import 'package:ahbu/config/app_config.dart';
import 'package:ahbu/models/user_role.dart';
import 'package:ahbu/services/auth_service.dart';
import 'package:ahbu/services/mqtt_door_service.dart';
import 'package:ahbu/styles/app_colors.dart';
import 'package:ahbu/styles/app_decorations.dart';
import 'package:ahbu/ui/widgets/yan_menu.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.authService});

  final AuthService authService;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final MqttDoorService _doorService;

  @override
  void initState() {
    super.initState();
    _doorService = MqttDoorService(
      host: mqttHost,
      port: mqttPort,
      username: mqttAppUser,
      password: mqttAppPassword,
      siteId: mqttSiteId,
      doorId: mqttDoorId,
    );
    _doorService.connect();
  }

  @override
  void dispose() {
    _doorService.dispose();
    super.dispose();
  }

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

  Future<void> _openDoor() async {
    final session = widget.authService.session;
    if (session == null) {
      return;
    }

    final error = await _doorService.sendPulseCommand(
      requestedBy: session.email,
    );

    if (!mounted) {
      return;
    }

    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Kapi acma komutu gonderildi.')),
    );
  }

  String _doorStateText(bool? locked) {
    if (locked == null) {
      return 'Bilinmiyor';
    }
    return locked ? 'Kilitli' : 'Acik/Tetiklenmis';
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.authService.session!;

    return Scaffold(
      appBar: AppBar(title: const Text('AHBU')),
      drawer: YanMenu(
        fullName: session.fullName,
        userEmail: session.email,
        roleLabel: session.role.label,
        onLogout: () => widget.authService.logout(),
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
                    style: Theme.of(
                      context,
                    ).textTheme.titleLarge?.copyWith(fontSize: 28),
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
                  if (session.phoneNumber != null &&
                      session.phoneNumber!.isNotEmpty) ...[
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
            const SizedBox(height: 16),
            AnimatedBuilder(
              animation: _doorService,
              builder: (context, _) {
                final connectionText = _doorService.connected
                    ? 'Bagli'
                    : _doorService.connecting
                    ? 'Baglaniyor'
                    : 'Bagli degil';
                final stateText = _doorStateText(_doorService.doorLocked);

                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: AppDecorations.glassCard,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Kapi Kontrol',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.textDark,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text('MQTT: $connectionText'),
                      const SizedBox(height: 6),
                      Text('Kapi Durumu: $stateText'),
                      if (_doorService.lastUpdatedAt != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Son Guncelleme: ${_doorService.lastUpdatedAt!.toLocal()}',
                        ),
                      ],
                      if (_doorService.lastError != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _doorService.lastError!,
                          style: const TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      if (_doorService.lastEvent != null &&
                          _doorService.lastEvent!.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text('Son Event: ${_doorService.lastEvent}'),
                      ],
                      const SizedBox(height: 8),
                      Text('Cihaz: $esp32DeviceName'),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _doorService.commandEnabled
                              ? _openDoor
                              : null,
                          icon: const Icon(Icons.lock_open),
                          label: const Text('Kapi Ac'),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
