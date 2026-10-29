import 'package:flutter/material.dart';

/// Ana sayfa kabuğunda yaşayan bir ekranı (Kişiler, Modüller, Finans ...) tam sayfa rota olarak açar.
///
/// Ana sayfa bu ekranları kaydırılan, ortalanmış (en çok 1100 dp) gövdede ve "aşağı çekip yenile" ile çizer; aynı düzen
/// burada kurulur, böylece kurulum sihirbazı ekranları YENİDEN YAZMADAN aynen kullanır. [onRefresh] verilirse aşağı çekince
/// çağrılır (ekranın `reload()` işlevi). Geri tuşu rotayı kapatır; ekranlar kendi durumunu rotayla birlikte atar.
Future<T?> pushSetupScreen<T>(
  BuildContext context, {
  required String title,
  required WidgetBuilder builder,
  Future<void> Function()? onRefresh,
}) {
  return Navigator.of(context).push<T>(
    MaterialPageRoute<T>(
      builder: (routeContext) => Scaffold(
        appBar: AppBar(
          title: Text(title),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final horizontalPadding = constraints.maxWidth < 600 ? 16.0 : 20.0;
              final scroll = SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(horizontalPadding, 10.0, horizontalPadding, 56.0),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1100),
                    child: builder(context),
                  ),
                ),
              );
              if (onRefresh == null) return scroll;
              return RefreshIndicator(onRefresh: onRefresh, child: scroll);
            },
          ),
        ),
      ),
    ),
  );
}
