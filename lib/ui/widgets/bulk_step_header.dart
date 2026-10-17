import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/views/bulk_import_controller.dart';

/// Sihirbaz adım göstergesi: renkli dilimler (dekoratif) + "Adım 2 / 5 · Dosya" başlığı.
///
/// Başlık TEK anlamsal başlıktır (canlı bölge): adım değişince ekran okuyucu yeni adımı okur ve [focusNode] ile
/// klavye / ekran okuyucu odağı oraya taşınır (kaydırma da başa döner; odak eski adımın düğmesinde kalmaz).
class BulkStepHeader extends StatelessWidget {
  const BulkStepHeader({super.key, required this.step, this.focusNode});

  final BulkStep step;
  final FocusNode? focusNode;

  static const List<String> labels = <String>['Tür', 'Dosya', 'Sütunlar', 'Önizleme', 'Sonuç'];

  static String titleOf(BulkStep step) =>
      'Adım ${step.index + 1} / ${labels.length} · ${labels[step.index]}';

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final title = titleOf(step);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExcludeSemantics(
          child: Row(
            children: [
              for (var i = 0; i < labels.length; i++) ...[
                if (i > 0) const SizedBox(width: AppSpace.xs),
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: i <= step.index ? AppTone.primary.hue : p.border,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: const SizedBox(height: 5),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpace.sm),
        Focus(
          focusNode: focusNode,
          child: Semantics(
            header: true,
            liveRegion: true,
            container: true,
            label: title,
            child: ExcludeSemantics(
              child: Text(
                title,
                key: const ValueKey<String>('bulk_step_title'),
                style: th.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
