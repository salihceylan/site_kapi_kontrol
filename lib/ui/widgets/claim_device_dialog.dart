import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/pages/qr_scan_page.dart';

/// "Cihaz Sahiplen" diyaloğu: kutu QR kodu taratma ya da seri no/UID ile elle ekleme.
///
/// Görünüm: [AppDialogHeader] (cilalı küre), birincil eylem [PrimaryActionButton] (cilalı, dolu), elle
/// girişin gönderme düğmesi ikincil (tonal), hata [InlineNotice]. İstek sürerken birincil düğme
/// "yükleniyor" durumuna geçer (düzen sıçramaz; iş sürerken dönen gösterge). Başarıda hafif haptik +
/// başarı bildirimi. Metinler ve davranış AYNIDIR.
class ClaimDeviceDialog extends StatefulWidget {
  const ClaimDeviceDialog({
    super.key,
    required this.authService,
  });

  final AuthService authService;

  static Future<String?> show(BuildContext context, AuthService authService) {
    return showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => ClaimDeviceDialog(authService: authService),
    );
  }

  @override
  State<ClaimDeviceDialog> createState() => _ClaimDeviceDialogState();
}

class _ClaimDeviceDialogState extends State<ClaimDeviceDialog> {
  final _uidController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  bool _isManualInput = false;

  @override
  void dispose() {
    _uidController.dispose();
    super.dispose();
  }

  Future<void> _submitClaim(String deviceInput) async {
    final clean = deviceInput.trim();
    if (clean.isEmpty) {
      setState(() {
        _errorMessage = 'Lütfen geçerli bir cihaz QR kodu veya Seri No giriniz.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final res = await widget.authService.claimDevice(deviceInput: clean);
      if (!mounted) return;

      final message = res['message'] as String? ?? 'Cihaz başarıyla hesabınıza bağlandı!';
      // Onay anı: hafif haptik + kısa başarı bildirimi.
      HapticFeedback.lightImpact();
      AppSnack.show(context, message, kind: AppSnackKind.success);
      final claimedUid = res['device']?['device_uid']?.toString() ?? clean;
      Navigator.of(context).pop(claimedUid);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.message;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Cihaz sahiplenme sırasında bir hata oluştu.';
        _isLoading = false;
      });
    }
  }

  Future<void> _scanQr() async {
    final scanned = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const QrScanPage(
          title: 'Kutu QR Kodunu Tara',
          instructionText: 'Cihaz ambalaj kutusundaki QR kodu kameraya gösterin.',
        ),
      ),
    );

    if (scanned != null && scanned.trim().isNotEmpty) {
      await _submitClaim(scanned);
    }
  }

  /// Elle giriş formunun açılış süresi: 200 ms; hareket azaltmada 1 ms. SIFIR süre KULLANILMAZ:
  /// `AnimatedSize` süre sıfırken kendi `performLayout`'u içinde yeniden yerleşim ister (bkz.
  /// `DoorLogsAccordion._foldDuration`); 1 ms görsel olarak anındadır.
  static Duration _revealDuration(BuildContext context) =>
      AppMotion.reduced(context) ? const Duration(milliseconds: 1) : AppMotion.base;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.xl),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Başlık & İkon
              const AppDialogHeader(
                title: 'Cihaz Sahiplen',
                subtitle: 'Ambalaj kutusundaki QR kod ile bağlayın',
                icon: Icons.qr_code_scanner_rounded,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpace.xl, AppSpace.sm, AppSpace.xl, AppSpace.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Hata Bildirimi
                    if (_errorMessage != null) ...[
                      InlineNotice(message: _errorMessage!),
                      const SizedBox(height: 16),
                    ],

                    // Yükleniyor Durumu: birincil düğme yerinde "yükleniyor" (düzen sıçramaz)
                    if (_isLoading)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpace.sm),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const PrimaryActionButton(
                              label: 'Kutu QR Kodunu Tara',
                              icon: Icons.camera_alt_rounded,
                              onPressed: null,
                              loading: true,
                            ),
                            const SizedBox(height: AppSpace.md),
                            Text(
                              'Cihaz kontrol ediliyor ve hesabınıza bağlanıyor...',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: p.textSecondary),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      )
                    else ...[
                      // Ana Buton: Kutu QR Tara
                      PrimaryActionButton(
                        label: 'Kutu QR Kodunu Tara',
                        icon: Icons.camera_alt_rounded,
                        onPressed: _scanQr,
                      ),
                      const SizedBox(height: 14),

                      // Alternatif: Elle Giriş Geçişi
                      Center(
                        child: TextButton.icon(
                          onPressed: () {
                            setState(() {
                              _isManualInput = !_isManualInput;
                            });
                          },
                          icon: Icon(
                            _isManualInput ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_rounded,
                            size: 18,
                          ),
                          label: Text(
                            _isManualInput ? 'Elle Girişi Kapat' : 'Seri No / UID ile Elle Ekle',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),

                      // Elle Giriş Formu: yumuşak açılır (200 ms; hareket azaltmada anında)
                      AnimatedSize(
                        duration: _revealDuration(context),
                        curve: AppMotion.standard,
                        alignment: Alignment.topCenter,
                        child: _isManualInput
                            ? Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const SizedBox(height: 10),
                                  TextField(
                                    controller: _uidController,
                                    textCapitalization: TextCapitalization.characters,
                                    decoration: const InputDecoration(
                                      hintText: 'Örn: 00861A0D5020',
                                      labelText: 'Cihaz UID / Seri Numarası',
                                      prefixIcon: Icon(Icons.developer_board_rounded, size: 20),
                                    ),
                                    onSubmitted: (val) => _submitClaim(val),
                                  ),
                                  const SizedBox(height: 12),
                                  // İkincil eylem (birincil: kutu QR kodu): tonal
                                  PrimaryActionButton(
                                    label: 'Cihazı Hesaba Bağla',
                                    icon: Icons.link_rounded,
                                    variant: AppButtonVariant.tonal,
                                    onPressed: () => _submitClaim(_uidController.text),
                                  ),
                                ],
                              )
                            : const SizedBox(width: double.infinity),
                      ),
                    ],

                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => Navigator.of(context).pop(null),
                        child: const Text('Vazgeç'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
