import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:site_kapi_kontrol/services/voice_door_service.dart';
import 'package:site_kapi_kontrol/styles/app_colors.dart';

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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label panoya kopyalandı!'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.85;
    final cardBg = isDark ? const Color(0xFF0F172A).withValues(alpha: 0.6) : Colors.white;
    final cardBorder = Border.all(color: isDark ? const Color(0x22FFFFFF) : Colors.black.withValues(alpha: 0.06));
    final mutedText = isDark ? const Color(0xFFCBD5E1) : AppColors.textMuted;

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surface : AppColors.surfaceLight,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 44,
            height: 5,
            decoration: BoxDecoration(
              color: isDark ? Colors.white24 : Colors.black26,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.directions_car_filled_rounded,
                    color: AppColors.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Eller Serbest & Araba Modu',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Ekrana dokunmadan sesle veya kestirmelerle kapı açma',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: mutedText,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 24),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              children: [
                // 1. Araba / Otomatik Dinleme Modu
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(18),
                    border: cardBorder,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '🚗 Araba / Açılışta Dinleme Modu',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Uygulama açılır açılmaz butona basmanıza gerek kalmadan mikrofonu açar ve sesli komutunuzu dinler.',
                              style: TextStyle(
                                color: mutedText,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Switch.adaptive(
                        value: _autoListen,
                        activeTrackColor: AppColors.primary,
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
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(18),
                    border: cardBorder,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.mic_none_rounded,
                              color: Colors.blue,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Apple Siri ("Hey Siri")',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Telefonunuz kilitliyken veya Apple CarPlay ekranındayken "Hey Siri, Kapıyı Aç" diyerek dokunmadan açabilirsiniz.',
                        style: TextStyle(
                          color: mutedText,
                          fontSize: 12.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1E293B) : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDark ? const Color(0x33FFFFFF) : Colors.black.withValues(alpha: 0.04),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'sitekapi://open?doorIndex=1',
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                  color: isDark ? const Color(0xFF93C5FD) : Colors.black87,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.copy_rounded,
                                size: 18,
                                color: isDark ? const Color(0xFFCBD5E1) : Colors.black54,
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
                        style: TextStyle(
                          color: isDark ? const Color(0xFF94A3B8) : Colors.grey.shade700,
                          fontSize: 11.5,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 3. Android & Google Asistan
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(18),
                    border: cardBorder,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.assistant_navigation,
                              color: Colors.green,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Google Asistan & Ana Ekran Kısayolları',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Android ana ekranınızda uygulama simgesine basılı tutarak doğrudan kapıyı açabilir veya Google Asistan rutinlerine ekleyebilirsiniz.',
                        style: TextStyle(
                          color: mutedText,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 4. NFC Araç Tutacağı Dokunuşu
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(18),
                    border: cardBorder,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.purple.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.nfc_rounded,
                              color: Colors.purple,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              '🏷️ NFC Araç Tutacağı Etiketi',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Arabanızın telefon tutacağına yapıştırılan standart bir NFC etiketine "sitekapi://open?doorIndex=1" bağlantısını yazarak, telefonu tutacağa koyduğunuz anda kapıyı temassız açabilirsiniz.',
                        style: TextStyle(
                          color: mutedText,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

