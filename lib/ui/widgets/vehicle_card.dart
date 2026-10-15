import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/vehicle_record.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

/// Araç satırı (Platform Faz 2a): plaka, sahibi, dairesi ve not. [onRemove] verilirse (yalnız yazma
/// yetkisi olanda) sağda "Aracı kaldır" düğmesi çıkar; salt okunur kurul üyesinde düğme yoktur.
///
/// Taşma: tüm metinler sarar; düğme 44 dp, metin kalan genişliği alır.
class VehicleCard extends StatelessWidget {
  const VehicleCard({super.key, required this.vehicle, this.onRemove, this.busy = false});

  final VehicleRecord vehicle;
  final VoidCallback? onRemove;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final secondary = th.bodyMedium?.copyWith(color: p.textSecondary);
    final person = vehicle.personName ?? '';
    final apartment = vehicle.apartmentLabel ?? '';
    final note = vehicle.note ?? '';

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
                Text(vehicle.displayPlate, style: th.titleMedium),
                if (person.isNotEmpty) Text(person, style: secondary),
                if (apartment.isNotEmpty) Text(apartment, style: secondary),
                if (note.isNotEmpty) Text(note, style: th.bodySmall),
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
                    tooltip: 'Aracı kaldır',
                    constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
        ],
      ),
    );
  }
}
