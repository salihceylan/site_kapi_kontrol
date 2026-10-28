import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/platform_module.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

/// Modülün durum çipi: çekirdek -> "Her sitede açık", yakında -> "Yakında…", aksi halde "Açık" /
/// "Kapalı". Renk tek başına anlam taşımaz: çipin etiketi ve simgesi de farklıdır.
///
/// [requestMode] (site yöneticisi, Faz 1.1): modülü kendisi açmaz, talep eder; çipler "Tanımlı"
/// (açık), "Talep gönderildi" (bekleyen talep) ve "Tanımlı değil" olur.
({String label, AppTone tone, IconData icon}) moduleStatusOf(
  PlatformModule m, {
  bool requestMode = false,
}) {
  if (requestMode && m.toggleable) {
    // `enabled`, `requestStatus`'tan ÖNCELİKLİDİR: açık modülde (örn. süper kullanıcı doğrudan açtı,
    // bekleyen talep henüz kapanmadı) "Talep gönderildi" gösterilmez.
    if (m.enabled) {
      return (label: 'Tanımlı', tone: AppTone.success, icon: Icons.check_circle_rounded);
    }
    if (m.hasPendingRequest) {
      return (
        label: 'Talep gönderildi',
        tone: AppTone.info,
        icon: Icons.hourglass_top_rounded,
      );
    }
    return (label: 'Tanımlı değil', tone: AppTone.neutral, icon: Icons.block_rounded);
  }
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
    case PlatformModuleCodes.driveStorage:
      return Icons.folder_rounded;
    case PlatformModuleCodes.reservation:
      return Icons.event_available_rounded;
    case PlatformModuleCodes.workTracking:
      return Icons.assignment_turned_in_rounded;
    case PlatformModuleCodes.metering:
      return Icons.speed_rounded;
    case PlatformModuleCodes.onlinePayment:
      return Icons.payments_rounded;
    case PlatformModuleCodes.plateRecognition:
      return Icons.directions_car_rounded;
    case PlatformModuleCodes.contracts:
      return Icons.handshake_rounded;
    case PlatformModuleCodes.equipment:
      return Icons.build_circle_rounded;
    case PlatformModuleCodes.cctvLink:
      return Icons.videocam_rounded;
    default:
      return Icons.extension_rounded;
  }
}

/// Modül kartı: ad, açıklama, durum çipi ve (süper kullanıcıda, [PlatformModule.canToggle] ise) anahtar.
///
/// [requestMode] (site yöneticisi, Faz 1.1): anahtar YOKTUR; tanımlı olmayan modülde "Modül Talep Et",
/// bekleyen talebi olan modülde "Talebi Geri Çek" düğmesi çıkar ([onRequest] / [onCancelRequest]).
///
/// [busy] iken anahtar (ya da düğme) yerine küçük bir ilerleme göstergesi çıkar (düzen kaymaz).
/// [onToggle] null ise anahtar devre dışıdır. Taşma: ad ve açıklama sarar, çip tek satır + elips.
class ModuleCard extends StatelessWidget {
  const ModuleCard({
    super.key,
    required this.module,
    this.busy = false,
    this.onToggle,
    this.requestMode = false,
    this.onRequest,
    this.onCancelRequest,
  });

  final PlatformModule module;
  final bool busy;
  final ValueChanged<bool>? onToggle;
  final bool requestMode;
  final VoidCallback? onRequest;
  final VoidCallback? onCancelRequest;

  /// Önerilen modül çipi (F9; `PlatformModule.recommended`).
  static const String recommendedLabel = 'Bu tür için önerilir';

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final status = moduleStatusOf(module, requestMode: requestMode);

    // Süper kullanıcı: bekleyen talep varsa kartta ayrıca belirtilir.
    final showPendingChip = !requestMode && module.hasPendingRequest && !module.core;

    // Talep düğmesi (YALNIZ site yöneticisi; süper kullanıcıda gizli): yalnız `toggleable && !enabled`
    // modülde; bekleyen talep varsa "Talebi Geri Çek", yoksa "Modül Talep Et".
    Widget? requestAction;
    if (requestMode && module.toggleable && !module.enabled) {
      if (busy) {
        requestAction = const SizedBox(
          height: 48,
          child: Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          ),
        );
      } else if (module.hasPendingRequest) {
        requestAction = PrimaryActionButton(
          label: 'Talebi Geri Çek',
          icon: Icons.undo_rounded,
          variant: AppButtonVariant.outline,
          tone: AppTone.warning,
          expand: false,
          onPressed: onCancelRequest,
        );
      } else {
        requestAction = PrimaryActionButton(
          label: 'Modül Talep Et',
          icon: Icons.send_rounded,
          variant: AppButtonVariant.tonal,
          expand: false,
          onPressed: onRequest,
        );
      }
    }

    Widget? control;
    if (!requestMode && module.canToggle) {
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
                    Wrap(
                      spacing: AppSpace.sm,
                      runSpacing: AppSpace.xs,
                      children: [
                        StatusChip(
                          label: status.label,
                          tone: status.tone,
                          icon: status.icon,
                        ),
                        if (showPendingChip)
                          const StatusChip(
                            label: 'Bekleyen talep var',
                            tone: AppTone.info,
                            icon: Icons.hourglass_top_rounded,
                          ),
                        // F9: sitenin yönetim türü için sunucunun önerdiği modül (eski sunucuda alan yok = çip yok).
                        if (module.recommended)
                          const StatusChip(
                            label: ModuleCard.recommendedLabel,
                            tone: AppTone.primary,
                            icon: Icons.recommend_rounded,
                          ),
                      ],
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
          if (requestAction != null) ...[
            const SizedBox(height: AppSpace.md),
            Align(alignment: AlignmentDirectional.centerStart, child: requestAction),
          ],
        ],
      ),
    );
  }
}
