import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/management_terms.dart';
import 'package:site_kapi_kontrol/models/management_type.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

/// Yönetim türü seçici (site kurulum / ekleme diyalogları).
///
/// Beş tür de seçilebilir. Her satırda türün tek cümlelik açıklaması ([ManagementTypeInfo.summary]) ve
/// terimleri varsayılandan farklıysa kısa terim özeti ("Daire → Ofis, Sakin → Firma") gösterilir (F9).
/// [types] sunucudan (`GET /app/management-types`) gelen tanımlardır; null / eksik türde yerleşik tanım
/// ([ManagementTypeInfo.builtIn]) kullanılır, eski sunucuyla aynı görünür.
/// [onChanged] null ise seçici SALT OKUNURDUR (mevcut sitenin düzenlenmesi: tür sonradan
/// değiştirilemez): yalnız geçerli tür bir çip olarak gösterilir.
///
/// Taşma: etiket ve çip `Wrap` içindedir (sığmayınca alt satıra iner); açıklama satırları sarar;
/// satırlar en az 48 dp yüksekliktedir ve büyük yazıda büyür. Üst öğe sınırlı genişlikte olmalıdır.
class ManagementTypeSelector extends StatelessWidget {
  const ManagementTypeSelector({
    super.key,
    required this.value,
    required this.onChanged,
    this.types,
  });

  final ManagementType value;

  /// null: salt okunur.
  final ValueChanged<ManagementType>? onChanged;

  /// Sunucudan gelen tür tanımları; null ise yerleşik tanımlar.
  final List<ManagementTypeInfo>? types;

  /// Seçici başlığı.
  static const String title = 'Yönetim Türü';

  /// Devre dışı türlerin çipi.
  static const String comingSoonLabel = 'Yakında…';

  /// Salt okunur açıklama.
  static const String lockedNote = 'Yönetim türü site kurulduktan sonra değiştirilemez.';

  ManagementTypeInfo _info(ManagementType type) {
    final list = types;
    if (list != null) {
      for (final info in list) {
        if (info.type == type) return info;
      }
    }
    return ManagementTypeInfo.builtIn(type);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final onChanged = this.onChanged;

    if (onChanged == null) {
      final info = _info(value);
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
          // F9: tür terimleri (yalnız varsayılandan farklıysa; apartman/sitede satır yok).
          if (!info.terms.isDefault) ...[
            Text(
              info.terms.changeSummary,
              style: th.bodySmall?.copyWith(color: p.textSecondary),
            ),
            const SizedBox(height: AppSpace.xs),
          ],
          Text(lockedNote, style: th.bodySmall),
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
              info: _info(type),
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
    required this.info,
    required this.selected,
    required this.onTap,
    required this.palette,
  });

  final ManagementType type;
  final ManagementTypeInfo info;
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
    final noteStyle = th.bodySmall?.copyWith(color: palette.textSecondary);
    final termStyle = th.bodySmall?.copyWith(color: palette.textMuted);
    final termSummary = info.terms.changeSummary;
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(
                      selected
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_unchecked_rounded,
                      size: 22,
                      color: selected
                          ? ink
                          : (enabled ? palette.textSecondary : palette.textMuted),
                    ),
                  ),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
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
                        // F9: tek cümlelik tür açıklaması + terim özeti (yalnız farklıysa). Sarar, kesilmez.
                        if (info.summary.isNotEmpty) Text(info.summary, style: noteStyle),
                        if (termSummary.isNotEmpty) Text(termSummary, style: termStyle),
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
