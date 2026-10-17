// Belge formlarının ortak alanları (yükleme ve düzenleme): kategori çipleri ve kitle seçimi.
import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/document_models.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

/// Kategori seçimi: çipler sarar; seçili olan işaretlidir.
class DocumentCategoryField extends StatelessWidget {
  const DocumentCategoryField({
    super.key,
    required this.value,
    required this.onChanged,
    this.keyPrefix = 'document_upload_category_',
    this.enabled = true,
  });

  final DocumentCategory value;
  final ValueChanged<DocumentCategory> onChanged;
  final String keyPrefix;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Kategori', style: th.titleSmall),
        const SizedBox(height: AppSpace.sm),
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          children: [
            for (final category in DocumentCategory.values)
              ChoiceChip(
                key: ValueKey<String>('$keyPrefix${category.apiValue}'),
                label: Text(category.label),
                selected: value == category,
                onSelected: enabled ? (_) => onChanged(category) : null,
              ),
          ],
        ),
      ],
    );
  }
}

/// Kitle seçimi ("Kimler görebilir?"): üç seçenek, varsayılan seçili olmayabilir ([value] null). Hata metni
/// canlı bölgedir.
class DocumentAudienceField extends StatelessWidget {
  const DocumentAudienceField({
    super.key,
    required this.value,
    required this.onChanged,
    this.errorText,
    this.keyPrefix = 'document_upload_audience_',
    this.enabled = true,
  });

  final DocumentAudience? value;
  final ValueChanged<DocumentAudience> onChanged;
  final String? errorText;
  final String keyPrefix;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text('Kimler görebilir?', style: th.titleSmall),
        ),
        const SizedBox(height: AppSpace.sm),
        for (final audience in DocumentAudience.choices) ...[
          DocumentAudienceOption(
            key: ValueKey<String>('$keyPrefix${audience.apiValue}'),
            audience: audience,
            selected: value == audience,
            onTap: enabled ? () => onChanged(audience) : null,
          ),
          const SizedBox(height: AppSpace.sm),
        ],
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.xs),
            child: Semantics(
              liveRegion: true,
              child: Text(
                errorText!,
                key: ValueKey<String>('${keyPrefix}error'),
                style: th.bodySmall?.copyWith(
                  color: AppTone.danger.ink(p),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Kitle seçeneği: radyo benzeri satır (başlık + açıklama); en az 48 dp; ekran okuyucu "seçili" der.
class DocumentAudienceOption extends StatelessWidget {
  const DocumentAudienceOption({
    super.key,
    required this.audience,
    required this.selected,
    required this.onTap,
  });

  final DocumentAudience audience;
  final bool selected;

  /// null ise seçenek devre dışıdır.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    const tone = AppTone.primary;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      selected: selected,
      button: true,
      enabled: onTap != null,
      // Dokunma eylemi anlam düğümünde olmalı: ExcludeSemantics altındaki InkWell'in eylemi görünmez
      // (Switch Access / Voice Access / anlam eylemi bu satırı etkinleştiremezdi).
      onTap: onTap,
      label: '${audience.label}. ${audience.description}',
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Ink(
            decoration: BoxDecoration(
              color: selected
                  ? Color.alphaBlend(tone.tint(p), p.surface)
                  : p.surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: selected ? tone.hue : p.border,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.md),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 24),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      selected
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_unchecked_rounded,
                      size: 22,
                      color: selected ? tone.ink(p) : p.textSecondary,
                    ),
                    const SizedBox(width: AppSpace.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(audience.label, style: th.titleSmall),
                          Text(
                            audience.description,
                            style: th.bodySmall?.copyWith(
                              color: p.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
