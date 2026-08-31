import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/config/app_config.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/deep_link_service.dart';
import 'package:site_kapi_kontrol/services/network_service.dart';
import 'package:site_kapi_kontrol/services/quick_actions_service.dart';
import 'package:site_kapi_kontrol/services/voice_door_service.dart';
import 'package:site_kapi_kontrol/styles/app_decorations.dart';
import 'package:site_kapi_kontrol/styles/app_theme.dart';
import 'package:site_kapi_kontrol/ui/pages/home_page.dart';
import 'package:site_kapi_kontrol/ui/pages/login_page.dart';
import 'package:site_kapi_kontrol/ui/pages/no_internet_page.dart';
import 'package:site_kapi_kontrol/ui/widgets/voice_control_modal.dart';

class MyApp extends StatefulWidget {
  const MyApp({super.key, this.networkCheckEnabled = true});

  final bool networkCheckEnabled;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  late final AuthService _authService;
  late final NetworkService _networkService;
  late final VoiceDoorService _voiceDoorService;
  late final QuickActionsService _quickActionsService;
  late final DeepLinkService _deepLinkService;

  @override
  void initState() {
    super.initState();
    _authService = AuthService(api: AuthApi(baseUrl: apiBaseUrl));
    _networkService = NetworkService(enabled: widget.networkCheckEnabled);
    _voiceDoorService = VoiceDoorService(authService: _authService);
    _quickActionsService = QuickActionsService();
    _deepLinkService = DeepLinkService();

    _authService.initialize();
    _networkService.initialize();

    _quickActionsService.initialize(_handleQuickAction);
    _deepLinkService.initialize(_handleDeepLinkAction);
  }

  Future<void> _handleQuickAction(String actionType) async {
    if (!_authService.isLoggedIn) {
      return;
    }
    if (actionType == 'voice_open') {
      if (_authService.session?.role != UserRole.apartmentOwner) {
        return;
      }
      final context = _navigatorKey.currentContext;
      if (context != null) {
        VoiceControlModal.show(context, voiceService: _voiceDoorService);
      } else {
        await _voiceDoorService.startListening();
      }
      return;
    }

    if (actionType.startsWith('open_door_')) {
      final doorIdStr = actionType.replaceFirst('open_door_', '');
      final doorId = int.tryParse(doorIdStr);
      if (doorId != null) {
        await _triggerDoorOpenById(doorId);
      }
    }
  }

  Future<void> _handleDeepLinkAction(DeepLinkAction action) async {
    if (!_authService.isLoggedIn) {
      await _voiceDoorService.speak('Lütfen önce uygulamaya giriş yapın.');
      return;
    }

    switch (action.type) {
      case DeepLinkActionType.triggerVoice:
        if (_authService.session?.role != UserRole.apartmentOwner) {
          return;
        }
        final context = _navigatorKey.currentContext;
        if (context != null) {
          VoiceControlModal.show(context, voiceService: _voiceDoorService);
        } else {
          await _voiceDoorService.startListening();
        }
        break;
      case DeepLinkActionType.openDoorById:
        if (action.doorId != null) {
          await _triggerDoorOpenById(action.doorId!);
        }
        break;
      case DeepLinkActionType.openDoorByIndex:
        if (action.doorIndex != null) {
          await _triggerDoorOpenByIndex(action.doorIndex!);
        }
        break;
      case DeepLinkActionType.openFirstDoor:
        await _triggerPrimaryDoorOpen();
        break;
    }
  }

  Future<void> _triggerDoorOpenById(int doorId) async {
    final (doors, _) = await _authService.listMyDoors();
    final target = doors?.where((d) => d.id == doorId).firstOrNull;
    if (target == null) {
      await _voiceDoorService.speak('Kapı bulunamadı.');
      return;
    }
    await _voiceDoorService.speak('${target.doorName} açılıyor.');
    await _authService.openDoor(doorId: target.id, door: target);
  }

  Future<void> _triggerDoorOpenByIndex(int doorIndex) async {
    final (doors, _) = await _authService.listMyDoors();
    final target = doors?.where((d) => d.doorIndex == doorIndex).firstOrNull;
    if (target == null) {
      await _voiceDoorService.speak('$doorIndex numaralı kapı bulunamadı.');
      return;
    }
    await _voiceDoorService.speak('${target.doorName} açılıyor.');
    await _authService.openDoor(doorId: target.id, door: target);
  }

  Future<void> _triggerPrimaryDoorOpen() async {
    final (doors, _) = await _authService.listMyDoors();
    final target = doors?.firstOrNull;
    if (target == null) {
      await _voiceDoorService.speak('Yetkili kapı bulunamadı.');
      return;
    }
    await _voiceDoorService.speak('${target.doorName} açılıyor.');
    await _authService.openDoor(doorId: target.id, door: target);
  }

  @override
  void dispose() {
    _authService.dispose();
    _networkService.dispose();
    _voiceDoorService.dispose();
    _deepLinkService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_authService, _networkService]),
      builder: (context, _) {
        final authReady = _authService.isReady;
        final networkReady = _networkService.isReady;
        Widget home;
        if (!authReady) {
          home = const Scaffold(body: Center(child: CircularProgressIndicator()));
        } else if (_authService.isLoggedIn) {
          home = HomePage(
            authService: _authService,
            voiceDoorService: _voiceDoorService,
            quickActionsService: _quickActionsService,
          );
        } else if (!networkReady) {
          home = const Scaffold(body: Center(child: CircularProgressIndicator()));
        } else if (!_networkService.hasInternet) {
          home = NoInternetPage(
            isChecking: _networkService.isChecking,
            onRetry: _networkService.refresh,
          );
        } else {
          home = LoginPage(authService: _authService);
        }

        return MaterialApp(
          navigatorKey: _navigatorKey,
          title: 'Site Kapi Kontrol',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          builder: (context, child) {
            return Container(
              decoration: AppDecorations.pageBackground,
              child: child,
            );
          },
          home: home,
        );
      },
    );
  }
}
