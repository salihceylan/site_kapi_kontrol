import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

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
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    const tone = AppTone.warning;
    // Dar ekranda (< 400 dp) yan boşluklar 16 dp: büyük yazıda içeriğe daha çok genişlik kalır.
    final hPad = MediaQuery.sizeOf(context).width < 400 ? AppSpace.lg : AppSpace.xl;

    return Scaffold(
      appBar: AppBar(title: const Text('Baglanti Gerekli')),
      body: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(hPad),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: AppCard(
              level: 2,
              padding: EdgeInsets.all(hPad),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // İkon karosu (dekoratif: durum aşağıdaki başlıkta okunur)
                  Center(
                    child: ExcludeSemantics(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: tone.tint(p),
                          borderRadius: BorderRadius.circular(AppRadius.lg),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpace.lg),
                          child: Icon(
                            Icons.wifi_off_rounded,
                            size: 40,
                            color: tone.ink(p),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpace.lg),
                  Semantics(
                    header: true,
                    child: Text(
                      'Internet baglantisi bulunamadi',
                      textAlign: TextAlign.center,
                      style: th.titleLarge,
                    ),
                  ),
                  const SizedBox(height: AppSpace.sm),
                  Text(
                    'Lutfen cihazinizda Wi-Fi veya mobil veriyi acin. Sonra tekrar deneyin.',
                    textAlign: TextAlign.center,
                    style: th.bodyMedium,
                  ),
                  const SizedBox(height: AppSpace.xl),
                  ElevatedButton.icon(
                    onPressed: isChecking ? null : onRetry,
                    // Kontrol sırasında düğme pasif (soluk zemin): beyaz çark görünmez olurdu.
                    icon: isChecking
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: p.textSecondary,
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
