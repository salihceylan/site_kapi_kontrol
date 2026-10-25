import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/residency_relation.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/apartment_edit_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/large_dialog_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

/// "Kişi Ekle / Düzenle" penceresindeki genişletilebilir "Daire bilgileri" bölümü: seçilen (ya da kişinin tek)
/// dairesinin kat, tip (kategori), brüt / net m², arsa payı ve borç sorumlusu alanları. Alanlar dairenin mevcut
/// değerleriyle dolu gelir; doğrulama ve "yalnız değişenler" farkı [ApartmentFieldsDraft] ile "Daireyi
/// Düzenle" penceresiyle AYNIDIR. Hepsi isteğe bağlıdır (dairede zaten kayıtlı olabilir).
///
/// Kapalıyken alanlar ağaçta YOKTUR; kaydetme doğrulaması bu yüzden alan widget'larına değil [draft] üzerine
/// kuruludur ([ApartmentFieldsDraft.validateAll]).
class ApartmentInfoSection extends StatelessWidget {
  const ApartmentInfoSection({
    super.key,
    required this.draft,
    required this.apartmentLabel,
    required this.expanded,
    required this.onToggle,
    required this.onPartyChanged,
    this.loading = false,
    this.loadError,
    this.onRetry,
    this.enabled = true,
  });

  final ApartmentFieldsDraft draft;

  /// "A Blok / Daire 5" gibi seçili dairenin adı.
  final String apartmentLabel;
  final bool expanded;
  final VoidCallback onToggle;
  final ValueChanged<ResponsibleParty> onPartyChanged;
  final bool loading;
  final String? loadError;
  final VoidCallback? onRetry;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    return DialogPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: expanded,
            child: InkWell(
              key: const ValueKey<String>('person_apt_toggle'),
              onTap: onToggle,
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Row(
                  children: [
                    Icon(Icons.home_work_rounded, color: p.textSecondary),
                    const SizedBox(width: AppSpace.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Daire bilgileri', style: th.titleSmall),
                          Text(
                            '$apartmentLabel • kat, tip, arsa payı, borç sorumlusu',
                            style: th.bodySmall?.copyWith(
                              color: p.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpace.sm),
                    ExpandChevron(expanded: expanded),
                  ],
                ),
              ),
            ),
          ),
          ExpandableSection(
            expanded: expanded,
            child: Padding(
              padding: const EdgeInsets.only(top: AppSpace.md),
              child: _body(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    if (loading) {
      return Row(
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Text(
              'Daire bilgileri yükleniyor...',
              style: th.bodyMedium?.copyWith(color: p.textSecondary),
            ),
          ),
        ],
      );
    }
    final error = loadError;
    if (error != null) {
      return InlineNotice(message: error, onRetry: onRetry);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          key: const ValueKey<String>('person_apt_floor'),
          controller: draft.floor,
          enabled: enabled,
          keyboardType: const TextInputType.numberWithOptions(signed: true),
          decoration: const InputDecoration(
            labelText: 'Kat',
            prefixIcon: Icon(Icons.layers_rounded),
          ),
          validator: ApartmentFieldsDraft.validateFloor,
        ),
        const SizedBox(height: AppSpace.md),
        TextFormField(
          key: const ValueKey<String>('person_apt_category'),
          controller: draft.category,
          enabled: enabled,
          maxLength: ApartmentEditDialog.maxCategoryLength,
          decoration: const InputDecoration(
            labelText: 'Tip (kategori)',
            hintText: 'Örn. 3+1, Dükkan',
            prefixIcon: Icon(Icons.category_rounded),
            counterText: '',
          ),
        ),
        const SizedBox(height: AppSpace.md),

        TextFormField(
          key: const ValueKey<String>('person_apt_numerator'),
          controller: draft.numerator,
          enabled: enabled,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Arsa payı - pay',
            helperText: 'Örn. 35/1000 için 35',
            prefixIcon: Icon(Icons.pie_chart_rounded),
          ),
          validator: ApartmentFieldsDraft.validateNumerator,
        ),
        const SizedBox(height: AppSpace.md),
        TextFormField(
          key: const ValueKey<String>('person_apt_denominator'),
          controller: draft.denominator,
          enabled: enabled,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Arsa payı - payda',
            helperText: 'Örn. 35/1000 için 1000',
            prefixIcon: Icon(Icons.pie_chart_outline_rounded),
          ),
          validator: ApartmentFieldsDraft.validateDenominator,
        ),
        const SizedBox(height: AppSpace.md),
        DropdownButtonFormField<ResponsibleParty>(
          key: const ValueKey<String>('person_apt_party'),
          isExpanded: true,
          initialValue: draft.party,
          dropdownColor: p.surface,
          style: th.bodyLarge?.copyWith(color: p.text),
          decoration: const InputDecoration(
            labelText: 'Borç sorumlusu',
            helperText: 'Borç ve bildirimler kime gitsin',
            prefixIcon: Icon(Icons.notifications_active_rounded),
          ),
          items: [
            for (final party in ResponsibleParty.values)
              DropdownMenuItem<ResponsibleParty>(
                value: party,
                child: Text(
                  party.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: enabled
              ? (value) {
                  if (value != null) onPartyChanged(value);
                }
              : null,
        ),
      ],
    );
  }
}
