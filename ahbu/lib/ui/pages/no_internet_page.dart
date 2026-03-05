import 'package:flutter/material.dart';
import 'package:ahbu/styles/app_colors.dart';
import 'package:ahbu/styles/app_decorations.dart';

class NoInternetPage extends StatelessWidget {
  const NoInternetPage({
    super.key,
    required this.isChecking,
    required this.onRetry,
  });

  final bool isChecking;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Baglanti Gerekli')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Container(
              decoration: AppDecorations.glassCard,
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.wifi_off_rounded,
                    size: 48,
                    color: AppColors.textDark,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Internet baglantisi bulunamadi',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Lutfen cihazinizda Wi-Fi veya mobil veriyi acin. Sonra tekrar deneyin.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: isChecking ? null : onRetry,
                    icon: isChecking
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.refresh),
                    label: Text(
                      isChecking ? 'Kontrol Ediliyor...' : 'Tekrar Dene',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
