import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/management_type.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

/// Yönetim türü seçici (site kurulum / ekleme diyalogları).
///
/// Faz 1: yalnız "Apartman ve Site" seçilebilir; diğer dördü "Yakında…" çipiyle devre dışıdır.
/// [onChanged] null ise seçici SALT OKUNURDUR (mevcut sitenin düzenlenmesi: tür sonradan
/// değiştirilemez): yalnız geçerli tür bir çip olarak gösterilir.
///
/// Taşma: etiket ve çip `Wrap` içindedir (sığmayınca alt satıra iner); satırlar en az 48 dp
/// yüksekliktedir ve büyük yazıda büyür. Üst öğe sınırlı genişlikte olmalıdır.
class ManagementTypeSelector extends StatelessWidget {
  const ManagementTypeSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final ManagementType value;

  /// null: salt okunur.
  final ValueChanged<ManagementType>? onChanged;

  /// Seçici başlığı.
  static const String title = 'Yönetim Türü';

  /// Devre dışı türlerin çipi.
  static const String comingSoonLabel = 'Yakında…';

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final onChanged = this.onChanged;

    if (onChanged == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: th.bodySmall),
          const SizedBox(height: AppSpace.xs),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.xs,
            children: [
              StatusChip(
                label: value.label,
                tone: AppTone.info,
                icon: Icons.category_rounded,
              ),
            ],
          ),
          const SizedBox(height: AppSpace.xs),
          Text('Yönetim türü site kurulduktan sonra değiştirilemez.', style: th.bodySmall),
        ],
      );
    }

    return Semantics(
      container: true,
      label: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: th.bodySmall),
          const SizedBox(height: AppSpace.xs),
          for (final type in ManagementType.values)
            _TypeRow(
              type: type,
              selected: type == value,
              onTap: type.selectable ? () => onChanged(type) : null,
              palette: p,
            ),
        ],
      ),
    );
  }
}

class _TypeRow extends StatelessWidget {
  const _TypeRow({
    required this.type,
    required this.selected,
    required this.onTap,
    required this.palette,
  });

  final ManagementType type;
  final bool selected;
  final VoidCallback? onTap;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final enabled = onTap != null;
    final ink = AppTone.primary.ink(palette);
    final labelStyle = th.bodyLarge?.copyWith(
      color: enabled ? palette.text : palette.textMuted,
      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
    );
    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      onTap: onTap,
      label: enabled ? type.label : '${type.label}, ${ManagementTypeSelector.comingSoonLabel}',
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
              child: Row(
                children: [
                  Icon(
                    selected
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 22,
                    color: selected
                        ? ink
                        : (enabled ? palette.textSecondary : palette.textMuted),
                  ),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: Wrap(
                      spacing: AppSpace.sm,
                      runSpacing: AppSpace.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(type.label, style: labelStyle),
                        if (!enabled)
                          const StatusChip(
                            label: ManagementTypeSelector.comingSoonLabel,
                            tone: AppTone.neutral,
                            icon: Icons.schedule_rounded,
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
    );
  }
}
