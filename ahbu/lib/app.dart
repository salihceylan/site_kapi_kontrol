import 'package:flutter/material.dart';
import 'package:ahbu/config/app_config.dart';
import 'package:ahbu/services/auth_api.dart';
import 'package:ahbu/services/auth_service.dart';
import 'package:ahbu/services/network_service.dart';
import 'package:ahbu/styles/app_decorations.dart';
import 'package:ahbu/styles/app_theme.dart';
import 'package:ahbu/ui/pages/home_page.dart';
import 'package:ahbu/ui/pages/login_page.dart';
import 'package:ahbu/ui/pages/no_internet_page.dart';

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
        return MaterialApp(
          title: 'AHBU',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          builder: (context, child) {
            return Container(
              decoration: AppDecorations.pageBackground,
              child: child,
            );
          },
          home: (!_authService.isReady || !_networkService.isReady)
              ? const Scaffold(body: Center(child: CircularProgressIndicator()))
              : !_networkService.hasInternet
              ? NoInternetPage(
                  isChecking: _networkService.isChecking,
                  onRetry: _networkService.refresh,
                )
              : _authService.isLoggedIn
              ? HomePage(authService: _authService)
              : LoginPage(authService: _authService),
        );
      },
    );
  }
}
