import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/config/app_config.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/deep_link_service.dart';
import 'package:site_kapi_kontrol/services/door_widget_service.dart';
import 'package:site_kapi_kontrol/services/local_door_service.dart';
import 'package:site_kapi_kontrol/services/network_service.dart';
import 'package:site_kapi_kontrol/services/quick_actions_service.dart';
import 'package:site_kapi_kontrol/services/voice_door_service.dart';
import 'package:site_kapi_kontrol/styles/app_decorations.dart';
import 'package:site_kapi_kontrol/styles/app_theme.dart';
import 'package:site_kapi_kontrol/ui/design/login_hero.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/pages/home_page.dart';
import 'package:site_kapi_kontrol/ui/pages/login_page.dart';
import 'package:site_kapi_kontrol/ui/pages/no_internet_page.dart';
import 'package:site_kapi_kontrol/ui/widgets/dynamic_qr_pass_modal.dart';
import 'package:site_kapi_kontrol/ui/widgets/voice_control_modal.dart';

class MyApp extends StatefulWidget {
  const MyApp({super.key, this.networkCheckEnabled = true});

  final bool networkCheckEnabled;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  late final AuthService _authService;
  late final NetworkService _networkService;
  late final VoiceDoorService _voiceDoorService;
  late final QuickActionsService _quickActionsService;
  late final DeepLinkService _deepLinkService;

  /// Tek örnek: AuthService'in kullandığı örnekle aynıdır; yaşam döngüsü
  /// (pause/resume) bu asıl örneğe uygulanır.
  final LocalDoorService _localDoorService = LocalDoorService();

  bool _wasLoggedIn = false;
  int? _lastUserId;
  bool _doorConfirmOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _authService = AuthService(api: AuthApi(baseUrl: apiBaseUrl));
    _networkService = NetworkService(enabled: widget.networkCheckEnabled);
    _voiceDoorService = VoiceDoorService(authService: _authService);
    _quickActionsService = QuickActionsService();
    _deepLinkService = DeepLinkService();

    _authService.addListener(_onAuthChanged);

    final authInit = _authService.initialize();
    _networkService.initialize();
    DoorWidgetService.instance.initialize();
    unawaited(_localDoorService.startBeaconListener());

    _quickActionsService.initialize(_handleQuickAction);
    _deepLinkService.initialize(_handleDeepLinkAction);

    // Oturum hazır olmadan gelen deep link / kısayol eylemleri kuyruktadır;
    // AuthService.initialize tamamlanınca (oturum yüklenince) işlenir.
    unawaited(
      authInit.whenComplete(() {
        if (mounted) {
          _deepLinkService.markReady();
        }
      }),
    );
  }

  /// Oturum açılış/kapanış geçişlerini izler. Oturum kapanınca (ya da kullanıcı
  /// değişince) önceki kullanıcıya ait ses servisi kapı listesi, bekleyen eylemler
  /// ve yerel ağ önbelleği temizlenir.
  void _onAuthChanged() {
    final loggedIn = _authService.isLoggedIn;
    final userId = _authService.session?.id;

    final loggedOut = _wasLoggedIn && !loggedIn;
    final userChanged =
        _wasLoggedIn && loggedIn && _lastUserId != null && _lastUserId != userId;
    if (loggedOut || userChanged) {
      _voiceDoorService.clearSession();
      _deepLinkService.clearPending();
      _localDoorService.clearCache();
    }

    _wasLoggedIn = loggedIn;
    _lastUserId = userId;
  }

  Future<void> _handleQuickAction(String actionType) async {
    if (actionType == 'voice_open') {
      _deepLinkService.dispatch(
        const DeepLinkAction(type: DeepLinkActionType.triggerVoice),
      );
      return;
    }

    if (actionType.startsWith('open_door_')) {
      final doorIdStr = actionType.replaceFirst('open_door_', '');
      final doorId = int.tryParse(doorIdStr);
      if (doorId != null && doorId > 0) {
        // Kısayoldan kapı açma da deep link ile aynı onay yolundan geçer.
        _deepLinkService.dispatch(
          DeepLinkAction(
            type: DeepLinkActionType.openDoorById,
            doorId: doorId,
          ),
        );
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
        final currentRole = _authService.session?.role;
        if (currentRole != UserRole.apartmentOwner &&
            currentRole != UserRole.individual) {
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
      case DeepLinkActionType.openDoorByIndex:
      case DeepLinkActionType.openFirstDoor:
        await _openDoorFromLink(action);
        break;
      case DeepLinkActionType.showQrForDoor:
        await _showQrModalForAction(action);
        break;
    }
  }

  Future<List<DoorRecord>?> _loadMyDoors() async {
    final (doors, error) = await _authService.listMyDoors();
    if (doors == null) {
      _showFeedback(error ?? 'Kapılar alınamadı.');
      return null;
    }
    return doors;
  }

  Future<void> _showQrModalForAction(DeepLinkAction action) async {
    final doors = await _loadMyDoors();
    if (doors == null) return;

    final resolution = DeepLinkDoorResolver.resolve(action, doors);
    final target = resolution.door;
    if (resolution.status != DeepLinkDoorStatus.found || target == null) {
      await _voiceDoorService.speak('Kapı bulunamadı.');
      _showFeedback('Kapı bulunamadı.');
      return;
    }
    final context = _navigatorKey.currentContext;
    if (context != null && context.mounted) {
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => DynamicQrPassModal(
          door: target,
          authService: _authService,
        ),
      );
    }
  }

  /// Kapı AÇAN deep link / kısayol: kapı kullanıcının kendi kapıları içinde
  /// doğrulanır, belirsizse kullanıcıya seçtirilir ve HER durumda açmadan önce
  /// kullanıcıdan onay alınır (dışarıdan tetiklenen sessiz kapı açmayı önler).
  Future<void> _openDoorFromLink(DeepLinkAction action) async {
    final doors = await _loadMyDoors();
    if (doors == null) return;

    final resolution = DeepLinkDoorResolver.resolve(action, doors);
    final List<DoorRecord> candidates;
    switch (resolution.status) {
      case DeepLinkDoorStatus.found:
        candidates = <DoorRecord>[resolution.door!];
        break;
      case DeepLinkDoorStatus.ambiguous:
      case DeepLinkDoorStatus.multipleDoors:
        candidates = resolution.candidates;
        break;
      case DeepLinkDoorStatus.notFound:
        candidates = const <DoorRecord>[];
        break;
    }

    if (candidates.isEmpty) {
      const message = 'Kapı bulunamadı.';
      await _voiceDoorService.speak(message);
      _showFeedback(message);
      return;
    }

    final chosen = await _confirmDoorOpen(candidates);
    if (chosen == null) {
      return;
    }

    await _voiceDoorService.speak('${chosen.doorName} açılıyor.');
    final (status, error) =
        await _authService.openDoor(doorId: chosen.id, door: chosen);
    if (status != null && error == null) {
      _showFeedback('${chosen.doorName} açma komutu gönderildi.');
    } else {
      _showFeedback(error ?? 'Kapı açılamadı.');
    }
  }

  /// Tek aday: "Kapı açılsın mı?" onay penceresi. Birden çok aday: kullanıcı
  /// hangi kapıyı açacağını seçer (seçmek de onaydır). İptal/boşa dokunma -> null.
  Future<DoorRecord?> _confirmDoorOpen(List<DoorRecord> candidates) async {
    final context = _navigatorKey.currentContext;
    if (context == null || _doorConfirmOpen || candidates.isEmpty) {
      // Arayüz hazır değil ya da başka bir onay penceresi açık: GÜVENLİ taraf, açma.
      return null;
    }
    _doorConfirmOpen = true;
    try {
      if (candidates.length == 1) {
        final door = candidates.first;
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => DoorOpenConfirmDialog(door: door),
        );
        return confirmed == true ? door : null;
      }
      return await showDialog<DoorRecord>(
        context: context,
        builder: (dialogContext) =>
            DoorChooserDialog(candidates: candidates.take(12).toList()),
      );
    } finally {
      _doorConfirmOpen = false;
    }
  }

  void _showFeedback(String message) {
    final context = _navigatorKey.currentContext;
    if (context == null) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      SnackBar(
        content: Text(message, maxLines: 3, overflow: TextOverflow.ellipsis),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _localDoorService.resumeListening();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _localDoorService.pauseListening();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authService.removeListener(_onAuthChanged);
    _localDoorService.pauseListening();
    _authService.dispose();
    _networkService.dispose();
    _voiceDoorService.dispose();
    _deepLinkService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'Site Kapi Kontrol',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      builder: (context, child) {
        // Metin ölçeği en çok 2,0 (taşma testleri bu sınırda biter). Zemin gradyanının üstüne tek,
        // statik ışıma binilir: dinamik içeriği yok, kararlı durumda yeniden boyanmaz.
        return MediaQuery.withClampedTextScaling(
          maxScaleFactor: 2.0,
          child: Container(
            decoration: AppDecorations.pageBackground(context),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: context.palette.isDark
                    ? AppGradients.pageGlowDark
                    : AppGradients.pageGlowLight,
              ),
              child: child,
            ),
          ),
        );
      },
      home: AnimatedBuilder(
        animation: Listenable.merge([_authService, _networkService]),
        builder: (context, _) {
          final authReady = _authService.isReady;
          final networkReady = _networkService.isReady;
          if (!authReady) {
            return const StartupSplash();
          }
          if (_authService.isLoggedIn) {
            return HomePage(
              authService: _authService,
              voiceDoorService: _voiceDoorService,
              quickActionsService: _quickActionsService,
            );
          }
          if (!networkReady) {
            return const StartupSplash();
          }
          if (!_networkService.hasInternet) {
            return NoInternetPage(
              isChecking: _networkService.isChecking,
              onRetry: _networkService.refresh,
            );
          }
          return LoginPage(authService: _authService);
        },
      ),
    );
  }
}

/// Açılış / ara ekranı: oturum ya da ağ durumu henüz belli değilken marka logosu + ilerleme göstergesi.
/// Yalnız kompozisyon (eskiden tek başına bir çark); ekran seçim mantığı `home` içinde AYNIDIR.
/// Dar/alçak pencerede (ya da büyük yazıda) taşmaz, kaydırılır.
@visibleForTesting
class StartupSplash extends StatelessWidget {
  const StartupSplash({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LoginHero(),
              SizedBox(height: AppSpace.xl),
              CircularProgressIndicator(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Deep link / kısayoldan kapı açmadan önce gösterilen onay penceresi.
/// Uzun kapı/site adları taşmaz (maxLines + ellipsis, içerik kaydırılabilir).
@visibleForTesting
class DoorOpenConfirmDialog extends StatelessWidget {
  const DoorOpenConfirmDialog({required this.door});

  final DoorRecord door;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final siteName = door.siteName?.trim() ?? '';
    return AlertDialog(
      title: const Text(
        'Kapı açılsın mı?',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              door.doorName,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            if (siteName.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                siteName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
            ],
            const SizedBox(height: 12),
            Text(
              'Bu işlem bir bağlantı veya kısayol üzerinden başlatıldı. '
              'Yalnızca siz başlattıysanız onaylayın.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Kapıyı Aç'),
        ),
      ],
    );
  }
}

/// Birden çok kapı eşleştiğinde kullanıcıya seçtiren pencere (seçim = onay).
@visibleForTesting
class DoorChooserDialog extends StatelessWidget {
  const DoorChooserDialog({required this.candidates});

  final List<DoorRecord> candidates;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SimpleDialog(
      title: const Text(
        'Hangi kapı açılsın?',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      children: [
        for (final door in candidates)
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(door),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  door.doorName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if ((door.siteName ?? '').trim().isNotEmpty)
                  Text(
                    door.siteName!.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
          ),
        SimpleDialogOption(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Vazgeç'),
        ),
      ],
    );
  }
}
