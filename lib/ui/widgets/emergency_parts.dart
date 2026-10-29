// Acil durum ekranının parçaları (sade stil, docs/TASARIM_DILI.md): 112 kartı, çağrı kutusu, hızlı düğme, "aramada söyleyin" bloğu ve soru listesi.
// Renkler yalnız palet ve ton; dinamik metin esnek (AGENTS.md kural 6). Hiçbir parça "arandı" demez: kuru modda yalnız numara ve kopyala vardır.
import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/emergency_models.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/icon_orb.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

/// Kuru mod kutusu: büyük numara (seçilip kopyalanabilir) + "Numarayı kopyala". Arama düğmesi YOKTUR.
class EmergencyNumberBox extends StatelessWidget {
  const EmergencyNumberBox({super.key, required this.number, required this.onCopy, this.copyKey});

  final String number;
  final VoidCallback onCopy;
  final Key? copyKey;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: p.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              label: 'Numara $number',
              excludeSemantics: true,
              child: SelectableText(
                number,
                textAlign: TextAlign.center,
                style: th.headlineMedium?.copyWith(fontWeight: FontWeight.w800, color: p.text),
              ),
            ),
            const SizedBox(height: AppSpace.sm),
            OutlinedButton.icon(
              key: copyKey,
              onPressed: onCopy,
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: const Text('Numarayı kopyala'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sayfanın başındaki 112 kartı: büyük arama düğmesi (kuru modda yerine numara kutusu).
class EmergencyHeroCard extends StatelessWidget {
  const EmergencyHeroCard({super.key, required this.dry, required this.onCall, required this.onCopy});

  final bool dry;
  final VoidCallback onCall;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    return AppCard(
      tone: AppTone.danger,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const IconOrb(icon: Icons.emergency_rounded, tone: AppTone.danger),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(header: true, child: Text('112 Acil Çağrı Merkezi', style: th.titleMedium)),
                    const SizedBox(height: AppSpace.xs),
                    Text(
                      'Polis, ambulans ve itfaiye için tek numara.',
                      style: th.bodyMedium?.copyWith(color: p.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          if (dry)
            EmergencyNumberBox(
              number: kEmergencyNumber,
              onCopy: onCopy,
              copyKey: const ValueKey<String>('emergency_copy_112'),
            )
          else
            ConstrainedBox(
              // Büyük düğme: en az 72 dp; büyük yazıda içeriğiyle uzar (sabit yükseklik yok).
              constraints: const BoxConstraints(minHeight: 72),
              child: PrimaryActionButton(
                key: const ValueKey<String>('emergency_call_112'),
                label: '112\'yi ara',
                icon: Icons.call_rounded,
                tone: AppTone.danger,
                onPressed: onCall,
              ),
            ),
        ],
      ),
    );
  }
}

/// Aranacak numara kartı (asansör bakım firması, yangında 112 ...): ad, numara, "Ara" ve "Numarayı kopyala". [dry] iken yalnız kopyala.
class EmergencyCallTile extends StatelessWidget {
  const EmergencyCallTile({
    super.key,
    required this.icon,
    required this.title,
    required this.number,
    required this.dry,
    required this.callLabel,
    required this.onCall,
    required this.onCopy,
    this.subtitle,
    this.tone = AppTone.primary,
    this.filled = true,
    this.callKey,
    this.copyKey,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String number;
  final bool dry;
  final String callLabel;
  final VoidCallback onCall;
  final VoidCallback onCopy;

  /// Arama düğmesinin tonu (112: danger; bakım firması: primary).
  final AppTone tone;

  /// Arama düğmesi dolu mu (sayfadaki asıl eylem) yoksa ikincil mi.
  final bool filled;
  final Key? callKey;
  final Key? copyKey;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconOrb(icon: icon, tone: tone == AppTone.danger ? AppTone.danger : AppTone.primary),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: th.titleSmall),
                    if (subtitle != null) Text(subtitle!, style: th.bodyMedium?.copyWith(color: p.textSecondary)),
                    const SizedBox(height: AppSpace.xs),
                    SelectableText(number, style: th.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: p.text)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: [
              if (!dry)
                PrimaryActionButton(
                  key: callKey,
                  label: callLabel,
                  icon: Icons.call_rounded,
                  tone: tone,
                  variant: filled ? AppButtonVariant.filled : AppButtonVariant.tonal,
                  expand: false,
                  onPressed: onCall,
                ),
              OutlinedButton.icon(
                key: copyKey,
                onPressed: onCopy,
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('Numarayı kopyala'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Hızlı düğme (Yangın, Asansör arızası): seçilince altta o senaryonun ayrıntısı açılır; yeniden dokunmak kapatır.
class EmergencyQuickTile extends StatelessWidget {
  const EmergencyQuickTile({
    super.key,
    required this.icon,
    required this.title,
    required this.tone,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final AppTone tone;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    return AppCard(
      selected: selected,
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpace.md),
      child: Row(
        children: [
          IconOrb(icon: icon, tone: tone, size: 40),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Text(
              title,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: th.titleSmall?.copyWith(fontWeight: selected ? FontWeight.w800 : FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Aramada söyleyin": ilk cümle + site adı + adres (seçilip kopyalanabilir). Adres yoksa dürüstçe söyler ve [missingHint] gösterir.
class EmergencyAddressBlock extends StatelessWidget {
  const EmergencyAddressBlock({
    super.key,
    required this.sayLine,
    required this.siteName,
    required this.address,
    required this.missingHint,
    required this.onCopyAddress,
  });

  final String sayLine;
  final String? siteName;
  final String? address;

  /// Adres kayıtlı değilken gösterilen yönlendirme (yönetici ve diğerleri için farklıdır).
  final String missingHint;
  final VoidCallback onCopyAddress;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final addressText = address;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: p.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(header: true, child: Text('Aramada söyleyin', style: th.labelLarge?.copyWith(color: p.textMuted))),
            const SizedBox(height: AppSpace.xs),
            SelectableText(
              key: const ValueKey<String>('emergency_say_line'),
              '"$sayLine"',
              style: th.titleMedium,
            ),
            const SizedBox(height: AppSpace.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(Icons.location_on_outlined, size: 20, color: p.textSecondary),
                ),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (siteName != null)
                        SelectableText(
                          key: const ValueKey<String>('emergency_site_name'),
                          siteName!,
                          style: th.bodyLarge?.copyWith(fontWeight: FontWeight.w700, color: p.text),
                        ),
                      if (addressText != null)
                        SelectableText(
                          key: const ValueKey<String>('emergency_address'),
                          addressText,
                          style: th.bodyLarge?.copyWith(color: p.text),
                        )
                      else
                        Text(
                          key: const ValueKey<String>('emergency_address_missing'),
                          missingHint,
                          style: th.bodyMedium?.copyWith(color: p.textSecondary),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.sm),
            Text(
              'Blok, kat ve daire numaranızı da söyleyin.',
              style: th.bodySmall?.copyWith(color: p.textSecondary),
            ),
            if (addressText != null)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  key: const ValueKey<String>('emergency_copy_address'),
                  onPressed: onCopyAddress,
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: const Text('Adresi kopyala'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Numaralı liste (çağrı merkezinin ya da bakım firmasının sorabilecekleri; aramadan önce yapılacaklar).
class EmergencyNumberedList extends StatelessWidget {
  const EmergencyNumberedList({super.key, required this.items, this.bullet = false});

  final List<String> items;

  /// true: numara yerine madde işareti.
  final bool bullet;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, item) in items.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 24,
                  child: Text(
                    bullet ? '•' : '${i + 1}.',
                    style: th.bodyMedium?.copyWith(color: p.textSecondary, fontWeight: FontWeight.w700),
                  ),
                ),
                Expanded(child: Text(item, style: th.bodyMedium?.copyWith(color: p.text))),
              ],
            ),
          ),
      ],
    );
  }
}
