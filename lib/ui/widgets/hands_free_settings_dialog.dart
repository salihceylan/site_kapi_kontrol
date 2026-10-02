import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:site_kapi_kontrol/services/voice_door_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

class HandsFreeSettingsDialog extends StatefulWidget {
  const HandsFreeSettingsDialog({
    super.key,
    required this.voiceDoorService,
  });

  final VoiceDoorService voiceDoorService;

  static Future<void> show(
    BuildContext context, {
    required VoiceDoorService voiceDoorService,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => HandsFreeSettingsDialog(voiceDoorService: voiceDoorService),
    );
  }

  @override
  State<HandsFreeSettingsDialog> createState() => _HandsFreeSettingsDialogState();
}

class _HandsFreeSettingsDialogState extends State<HandsFreeSettingsDialog> {
  late bool _autoListen;

  @override
  void initState() {
    super.initState();
    _autoListen = widget.voiceDoorService.handsFreeAutoListen;
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    AppSnack.show(
      context,
      '$label panoya kopyalandı!',
      duration: const Duration(seconds: 2),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.85;
    final bodyStyle = th.bodySmall?.copyWith(color: p.textSecondary);

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: p.surfaceMuted,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 44,
            height: 5,
            decoration: BoxDecoration(
              color: p.textMuted.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const AppDialogHeader(
            title: 'Eller Serbest & Araba Modu',
            subtitle: 'Ekrana dokunmadan sesle veya kestirmelerle kapı açma',
            icon: Icons.directions_car_filled_rounded,
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              children: [
                // 1. Araba / Otomatik Dinleme Modu
                AppCard(
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '🚗 Araba / Açılışta Dinleme Modu',
                              style: th.titleMedium,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Uygulama açılır açılmaz butona basmanıza gerek kalmadan mikrofonu açar ve sesli komutunuzu dinler.',
                              style: bodyStyle,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Switch.adaptive(
                        value: _autoListen,
                        activeTrackColor: AppTone.primary.a,
                        onChanged: (val) {
                          setState(() => _autoListen = val);
                          widget.voiceDoorService.setHandsFreeAutoListen(val);
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 2. Siri Kestirmesi Rehberi
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildCardTitle(
                        Icons.mic_none_rounded,
                        AppTone.primary,
                        'Apple Siri ("Hey Siri")',
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Telefonunuz kilitliyken veya Apple CarPlay ekranındayken "Hey Siri, Kapıyı Aç" diyerek dokunmadan açabilirsiniz.',
                        style: bodyStyle,
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: p.surfaceMuted,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: p.border),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'sitekapi://open?doorIndex=1',
                                style: th.bodyMedium?.copyWith(
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.w600,
                                  color: AppTone.primary.ink(p),
                                ),
                              ),
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.copy_rounded,
                                size: 18,
                                color: p.textSecondary,
                              ),
                              tooltip: 'Kopyala',
                              onPressed: () => _copyToClipboard(
                                'sitekapi://open?doorIndex=1',
                                'Siri Kestirme URL',
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Kurulum: iPhone Kestirmeler (Shortcuts) uygulamasında yeni kestirme oluşturun ➡️ "URL Aç" eylemini seçin ➡️ Yukarıdaki bağlantıyı yapıştırın.',
                        style: bodyStyle?.copyWith(fontStyle: FontStyle.italic),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 3. Android & Google Asistan
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildCardTitle(
                        Icons.assistant_navigation,
                        AppTone.success,
                        'Google Asistan & Ana Ekran Kısayolları',
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Android ana ekranınızda uygulama simgesine basılı tutarak doğrudan kapıyı açabilir veya Google Asistan rutinlerine ekleyebilirsiniz.',
                        style: bodyStyle,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 4. NFC Araç Tutacağı Dokunuşu
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildCardTitle(
                        Icons.nfc_rounded,
                        AppTone.violet,
                        '🏷️ NFC Araç Tutacağı Etiketi',
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Arabanızın telefon tutacağına yapıştırılan standart bir NFC etiketine "sitekapi://open?doorIndex=1" bağlantısını yazarak, telefonu tutacağa koyduğunuz anda kapıyı temassız açabilirsiniz.',
                        style: bodyStyle,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 5. Güvenlik notu: bağlantı/kısayolla kapı açmak onay ister
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.verified_user_outlined,
                      size: 18,
                      color: p.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Güvenlik: Bağlantı, NFC veya kısayolla kapı açılırken uygulama her seferinde onayınızı ister. Birden çok kapınız varsa hangisini açacağınızı seçersiniz.',
                        style: bodyStyle,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Kart başlığı: ton zeminli ikon karosu + başlık (taşmayan; uzun başlık satır atlar).
  Widget _buildCardTitle(IconData icon, AppTone tone, String title) {
    final p = context.palette;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: tone.tint(p),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: tone.ink(p), size: 20),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
        ),
      ],
    );
  }
}

