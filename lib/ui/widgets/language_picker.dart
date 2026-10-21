import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/services/locale_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

/// Profilim'de dil seçimi (Türkçe / English). Kapsam yoksa hiçbir şey çizmez.
class LanguagePicker extends StatelessWidget {
  const LanguagePicker({super.key});

  @override
  Widget build(BuildContext context) {
    final service = LocaleScope.maybeOf(context);
    if (service == null) {
      return const SizedBox.shrink();
    }
    final l = context.l10n;
    return AppCard(
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.languageTitle, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpace.sm),
          SegmentedButton<String>(
            key: const ValueKey<String>('dil_secici'),
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: 'tr', label: Text(l.languageTurkish)),
              ButtonSegment(value: 'en', label: Text(l.languageEnglish)),
            ],
            selected: {service.locale.languageCode},
            onSelectionChanged: (s) => service.setLocale(Locale(s.first)),
          ),
        ],
      ),
    );
  }
}
