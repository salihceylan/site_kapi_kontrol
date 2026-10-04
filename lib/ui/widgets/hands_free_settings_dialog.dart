import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:site_kapi_kontrol/services/voice_door_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/icon_orb.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

/// "Eller Serbest & Araba Modu" alt sayfası: açılışta dinleme anahtarı ve üç kısayol rehberi kartı.
///
/// Görünüm: başlık şeridi [AppDialogHeader] (cilalı küre), her kartın başlığında cilalı ton küresi
/// ([IconOrb]; ton anlam taşır: info dinleme, primary Siri, success Google, violet NFC), anahtar satırı
/// tam satır dokunulur ve ekran okuyucuya başlık + açıklamayla birlikte okunur ([SwitchListTile],
/// >= 56 dp), güvenlik notu [InlineNotice]. Hepsi durağandır (ticker yok). Metinler ve davranış AYNIDIR.
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
          const SizedBox(height: AppSpace.md),
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
              padding: const EdgeInsets.fromLTRB(
                AppSpace.lg,
                AppSpace.lg,
                AppSpace.lg,
                AppSpace.xl,
              ),
              children: [
                // 1. Araba / Otomatik Dinleme Modu: tam satır dokunulan anahtar (SwitchListTile)
                AppCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpace.lg,
                    vertical: AppSpace.xs,
                  ),
                  child: SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    // Üç satırlı düzen: küre ve anahtar üstte hizalanır (uzun metinde ortada kalmaz).
                    isThreeLine: true,
                    secondary: const IconOrb(
                      icon: Icons.hearing_rounded,
                      tone: AppTone.info,
                      size: 36,
                      shape: IconOrbShape.squircle,
                    ),
                    title: Text(
                      '🚗 Araba / Açılışta Dinleme Modu',
                      style: th.titleMedium,
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: AppSpace.xs),
                      child: Text(
                        'Uygulama açılır açılmaz butona basmanıza gerek kalmadan mikrofonu açar ve sesli komutunuzu dinler.',
                        style: bodyStyle,
                      ),
                    ),
                    value: _autoListen,
                    activeTrackColor: AppTone.primary.a,
                    onChanged: (val) {
                      setState(() => _autoListen = val);
                      widget.voiceDoorService.setHandsFreeAutoListen(val);
                    },
                  ),
                ),
                const SizedBox(height: AppSpace.lg),

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
                      const SizedBox(height: AppSpace.sm),
                      Text(
                        'Telefonunuz kilitliyken veya Apple CarPlay ekranındayken "Hey Siri, Kapıyı Aç" diyerek dokunmadan açabilirsiniz.',
                        style: bodyStyle,
                      ),
                      const SizedBox(height: AppSpace.md),
                      Container(
                        padding: const EdgeInsets.all(AppSpace.md),
                        decoration: BoxDecoration(
                          color: p.surfaceMuted,
                          borderRadius: BorderRadius.circular(AppRadius.sm),
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
                      const SizedBox(height: AppSpace.sm),
                      Text(
                        'Kurulum: iPhone Kestirmeler (Shortcuts) uygulamasında yeni kestirme oluşturun ➡️ "URL Aç" eylemini seçin ➡️ Yukarıdaki bağlantıyı yapıştırın.',
                        style: bodyStyle?.copyWith(fontStyle: FontStyle.italic),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpace.lg),

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
                      const SizedBox(height: AppSpace.sm),
                      Text(
                        'Android ana ekranınızda uygulama simgesine basılı tutarak doğrudan kapıyı açabilir veya Google Asistan rutinlerine ekleyebilirsiniz.',
                        style: bodyStyle,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpace.lg),

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
                      const SizedBox(height: AppSpace.sm),
                      Text(
                        'Arabanızın telefon tutacağına yapıştırılan standart bir NFC etiketine "sitekapi://open?doorIndex=1" bağlantısını yazarak, telefonu tutacağa koyduğunuz anda kapıyı temassız açabilirsiniz.',
                        style: bodyStyle,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpace.lg),

                // 5. Güvenlik notu: bağlantı/kısayolla kapı açmak onay ister
                const InlineNotice(
                  tone: AppTone.info,
                  icon: Icons.verified_user_outlined,
                  message:
                      'Güvenlik: Bağlantı, NFC veya kısayolla kapı açılırken uygulama her seferinde onayınızı ister. Birden çok kapınız varsa hangisini açacağınızı seçersiniz.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Kart başlığı: cilalı ton küresi ([IconOrb], 36 dp) + başlık (taşmayan; uzun başlık satır atlar).
  Widget _buildCardTitle(IconData icon, AppTone tone, String title) {
    return Row(
      children: [
        IconOrb(icon: icon, tone: tone, size: 36, shape: IconOrbShape.squircle),
        const SizedBox(width: AppSpace.md),
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
      ],
    );
  }
}
