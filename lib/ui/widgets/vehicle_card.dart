import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/vehicle_record.dart';
import 'package:site_kapi_kontrol/ui/design/license_plate.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

/// Araç satırı (Platform Faz 2a): plaka, sahibi, dairesi ve (yalnız [showNote] iken) not. [onRemove]
/// verilirse (yalnız yazma yetkisi olanda) sağda "{plaka} plakalı aracı kaldır" düğmesi çıkar; salt
/// okunur kurul üyesinde düğme ve not yoktur.
///
/// Taşma: tüm metinler sarar; düğme 48 dp, metin kalan genişliği alır.
class VehicleCard extends StatelessWidget {
  const VehicleCard({
    super.key,
    required this.vehicle,
    this.onRemove,
    this.busy = false,
    this.showNote = false,
    this.showSource = false,
  });

  final VehicleRecord vehicle;

  /// "Ekleyen: Daire yöneticisi (Ad) / Site yönetimi" satırı (yönetici Araçlar ekranı: kaydı kimin yaptığı).
  final bool showSource;

  /// Araç notu yönetime özeldir: yalnız yazma yetkisi olanda true (kurul üyesi notu görmez).
  final bool showNote;
  final VoidCallback? onRemove;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final secondary = th.bodyMedium?.copyWith(color: p.textSecondary);
    final person = vehicle.personName ?? '';
    final apartment = vehicle.apartmentLabel ?? '';
    final note = showNote ? (vehicle.note ?? '') : '';

    return AppCard(
      padding: listCardPadding(context),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const IconTile(
            icon: Icons.directions_car_rounded,
            tone: AppTone.info,
            gap: AppSpace.md,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LicensePlateBadge(plate: vehicle.displayPlate),
                const SizedBox(height: AppSpace.xs),
                if (person.isNotEmpty) Text(person, style: secondary),
                if (apartment.isNotEmpty) Text(apartment, style: secondary),
                if (note.isNotEmpty) Text(note, style: th.bodySmall),
                if (showSource) Text('Ekleyen: ${vehicle.sourceLabel}', style: th.bodySmall?.copyWith(color: p.textSecondary)),
              ],
            ),
          ),
          if (onRemove != null)
            busy
                ? const Padding(
                    padding: EdgeInsets.all(AppSpace.md),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    onPressed: onRemove,
                    tooltip: '${vehicle.displayPlate} plakalı aracı kaldır',
                    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
        ],
      ),
    );
  }
}
