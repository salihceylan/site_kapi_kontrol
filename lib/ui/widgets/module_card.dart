import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/platform_module.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

/// Modülün durum çipi: çekirdek -> "Her sitede açık", yakında -> "Yakında…", aksi halde "Açık" /
/// "Kapalı". Renk tek başına anlam taşımaz: çipin etiketi ve simgesi de farklıdır.
({String label, AppTone tone, IconData icon}) moduleStatusOf(PlatformModule m) {
  if (m.core) {
    return (
      label: 'Her sitede açık',
      tone: AppTone.info,
      icon: Icons.verified_rounded,
    );
  }
  if (!m.isAvailable) {
    return (
      label: 'Yakında…',
      tone: AppTone.neutral,
      icon: Icons.schedule_rounded,
    );
  }
  return m.enabled
      ? (label: 'Açık', tone: AppTone.success, icon: Icons.check_circle_rounded)
      : (label: 'Kapalı', tone: AppTone.warning, icon: Icons.pause_circle_rounded);
}

IconData moduleIconOf(String code) {
  switch (code) {
    case PlatformModuleCodes.doorControl:
      return Icons.door_front_door_rounded;
    case PlatformModuleCodes.people:
      return Icons.groups_rounded;
    case PlatformModuleCodes.announcements:
      return Icons.campaign_rounded;
    case PlatformModuleCodes.finance:
      return Icons.account_balance_wallet_rounded;
    case PlatformModuleCodes.reservation:
      return Icons.event_available_rounded;
    case PlatformModuleCodes.workTracking:
      return Icons.assignment_turned_in_rounded;
    case PlatformModuleCodes.metering:
      return Icons.speed_rounded;
    case PlatformModuleCodes.onlinePayment:
      return Icons.payments_rounded;
    default:
      return Icons.extension_rounded;
  }
}

/// Modül kartı: ad, açıklama, durum çipi ve (yalnız açılıp kapatılabilen modüllerde) anahtar.
///
/// [busy] iken anahtar yerine küçük bir ilerleme göstergesi çıkar (aynı boyut: düzen kaymaz).
/// [onToggle] null ise anahtar devre dışıdır. Taşma: ad ve açıklama sarar, çip tek satır + elips.
class ModuleCard extends StatelessWidget {
  const ModuleCard({
    super.key,
    required this.module,
    this.busy = false,
    this.onToggle,
  });

  final PlatformModule module;
  final bool busy;
  final ValueChanged<bool>? onToggle;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final status = moduleStatusOf(module);

    Widget? control;
    if (module.toggleable) {
      control = busy
          ? const SizedBox(
              width: 52,
              height: 48,
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ),
            )
          : Semantics(
              label: '${module.name} anahtarı',
              child: Switch(value: module.enabled, onChanged: onToggle),
            );
    }

    return AppCard(
      padding: listCardPadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconTile(
                icon: moduleIconOf(module.code),
                tone: module.enabled || module.core
                    ? AppTone.success
                    : AppTone.neutral,
                gap: AppSpace.md,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(module.name, style: th.titleMedium),
                    const SizedBox(height: AppSpace.xs),
                    StatusChip(
                      label: status.label,
                      tone: status.tone,
                      icon: status.icon,
                    ),
                  ],
                ),
              ),
              if (control != null) ...[
                const SizedBox(width: AppSpace.sm),
                control,
              ],
            ],
          ),
          if (module.description.isNotEmpty) ...[
            const SizedBox(height: AppSpace.sm),
            Text(
              module.description,
              style: th.bodyMedium?.copyWith(color: p.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}
