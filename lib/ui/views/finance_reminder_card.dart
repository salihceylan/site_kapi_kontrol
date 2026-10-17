import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/finance_reminder_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/finance_reminder_runs_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/large_dialog_parts.dart';
import 'package:site_kapi_kontrol/ui/helpers/money.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_settings_controller.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

/// Borç hatırlatma kartı (Daireler sekmesinin üstü; Platform Faz 4b, Ö6): özellik KULLANILABİLİRSE ayar özeti ve
/// **Borç Hatırlat** / **Muaf Daireler** / **Hatırlatma Geçmişi** düğmeleri; kullanılamıyorsa nedenini açıklayan pasif kart
/// ("Hukuk onayı bekleniyor" ya da "Bu sitede kapalı — Finans Ayarları'ndan açın"). Kurul yalnız geçmişi (sayılar) görür.
class FinanceReminderCard extends StatefulWidget {
  const FinanceReminderCard({
    super.key,
    required this.scope,
    required this.settings,
    required this.onOpenSettings,
    required this.onDataChanged,
  });

  final PeopleScope scope;
  final FinanceSettingsController settings;
  final VoidCallback onOpenSettings;
  final VoidCallback onDataChanged;

  @override
  State<FinanceReminderCard> createState() => _FinanceReminderCardState();
}

class _FinanceReminderCardState extends State<FinanceReminderCard> {
  bool _opening = false;

  bool get _canWrite => widget.scope.canWrite;

  Future<void> _guarded(Future<void> Function() open) async {
    if (_opening) return;
    _opening = true;
    try {
      await open();
    } finally {
      _opening = false;
    }
  }

  Future<void> _send() => _guarded(() async {
    final outcome = await FinanceReminderDialog.show(context, scope: widget.scope, onRefreshNeeded: widget.onDataChanged);
    if (outcome == null || !mounted) return;
    showFinanceSnack(context, outcome.message);
    widget.onDataChanged();
  });

  Future<void> _runs() => _guarded(() => FinanceReminderRunsDialog.show(context, scope: widget.scope, onChanged: widget.onDataChanged));

  Future<void> _exclusions() =>
      _guarded(() => FinanceReminderExclusionsDialog.show(context, scope: widget.scope, onChanged: widget.onDataChanged));

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.settings,
      builder: (context, _) {
        final controller = widget.settings;
        final availability = reminderAvailability(controller);
        final th = Theme.of(context).textTheme;
        final p = context.palette;
        if (availability != FeatureAvailability.ready) {
          return Column(
            key: const ValueKey<String>('finance_reminder_card'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FinanceFeatureGate(
                featureName: 'Borç hatırlatma',
                availability: availability,
                error: controller.error,
                canWrite: _canWrite,
                onRetry: controller.load,
                onOpenSettings: widget.onOpenSettings,
                compact: true,
              ),
              // Kapalıyken de GEÇMİŞ (daha önce gönderilmiş çalıştırmalar) okunabilir.
              if (availability == FeatureAvailability.disabled || availability == FeatureAvailability.legalPending)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    key: const ValueKey<String>('finance_reminder_history'),
                    onPressed: _runs,
                    icon: const Icon(Icons.history_rounded, size: 18),
                    label: const Text('Hatırlatma Geçmişi'),
                    style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  ),
                ),
            ],
          );
        }
        final s = controller.settings!.reminders;
        return AppCard(
          key: const ValueKey<String>('finance_reminder_card'),
          padding: listCardPadding(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const DialogSectionTitle(icon: Icons.mark_email_read_rounded, title: 'Borç hatırlatma'),
              const SizedBox(height: AppSpace.sm),
              Text(
                'En az ${formatMinor(s.minOverdueMinor)} ve ${s.minDaysOverdue} gün gecikmiş borç • ${s.minIntervalDays} günde bir • '
                'en çok ${s.maxConsecutive} ardışık hatırlatma',
                key: const ValueKey<String>('finance_reminder_settings_line'),
                semanticsLabel: spokenMoneyText(
                  'En az ${formatMinor(s.minOverdueMinor)} ve ${s.minDaysOverdue} gün gecikmiş borç • ${s.minIntervalDays} günde bir • en çok ${s.maxConsecutive} ardışık hatırlatma',
                ),
                style: th.bodyMedium,
              ),
              if (!s.smtpConfigured) ...[
                const SizedBox(height: AppSpace.sm),
                const InlineNotice(
                  key: ValueKey<String>('finance_reminder_card_no_smtp'),
                  tone: AppTone.info,
                  message: 'E-posta gönderimi bu sunucuda yapılandırılmamış; hatırlatma gönderilemez.',
                ),
              ],
              const SizedBox(height: AppSpace.sm),
              Text(
                'Her gönderim önce önizlenir ve onaylanır. İleti tanıtım içermez; tutar yalnız doğrulanmış hesap e-postasına yazılır.',
                style: th.bodySmall?.copyWith(color: p.textSecondary),
              ),
              const SizedBox(height: AppSpace.md),
              if (_canWrite) ...[
                PrimaryActionButton(
                  key: const ValueKey<String>('finance_reminder_send'),
                  label: 'Borç Hatırlat',
                  icon: Icons.send_rounded,
                  onPressed: _send,
                ),
                const SizedBox(height: AppSpace.sm),
                PrimaryActionButton(
                  key: const ValueKey<String>('finance_reminder_exclusions'),
                  label: 'Muaf Daireler',
                  icon: Icons.do_not_disturb_on_rounded,
                  variant: AppButtonVariant.tonal,
                  onPressed: _exclusions,
                ),
                const SizedBox(height: AppSpace.sm),
              ],
              PrimaryActionButton(
                key: const ValueKey<String>('finance_reminder_history'),
                label: 'Hatırlatma Geçmişi',
                icon: Icons.history_rounded,
                variant: AppButtonVariant.tonal,
                onPressed: _runs,
              ),
            ],
          ),
        );
      },
    );
  }
}
