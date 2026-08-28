import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/config/app_config.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/network_service.dart';
import 'package:site_kapi_kontrol/styles/app_decorations.dart';
import 'package:site_kapi_kontrol/styles/app_theme.dart';
import 'package:site_kapi_kontrol/ui/pages/home_page.dart';
import 'package:site_kapi_kontrol/ui/pages/login_page.dart';
import 'package:site_kapi_kontrol/ui/pages/no_internet_page.dart';

class MyApp extends StatefulWidget {
  const MyApp({super.key, this.networkCheckEnabled = true});

  final bool networkCheckEnabled;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final AuthService _authService;
  late final NetworkService _networkService;

  @override
  void initState() {
    super.initState();
    _authService = AuthService(api: AuthApi(baseUrl: apiBaseUrl));
    _networkService = NetworkService(enabled: widget.networkCheckEnabled);
    _authService.initialize();
    _networkService.initialize();
  }

  @override
  void dispose() {
    _authService.dispose();
    _networkService.dispose();
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
          home = HomePage(authService: _authService);
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
