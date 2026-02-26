import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/config/app_config.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/pages/home_page.dart';
import 'package:site_kapi_kontrol/ui/pages/login_page.dart';

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final AuthService _authService;

  @override
  void initState() {
    super.initState();
    _authService = AuthService(api: AuthApi(baseUrl: apiBaseUrl));
    _authService.initialize();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _authService,
      builder: (context, _) {
        return MaterialApp(
          title: 'Site Kapi Kontrol',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          ),
          home: !_authService.isReady
              ? const Scaffold(body: Center(child: CircularProgressIndicator()))
              : _authService.isLoggedIn
              ? HomePage(authService: _authService)
              : LoginPage(authService: _authService),
        );
      },
    );
  }
}
