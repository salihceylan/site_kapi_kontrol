import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:site_kapi_kontrol/models/subscription_request.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/icon_orb.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

class SubscriptionRequestCard extends StatelessWidget {
  const SubscriptionRequestCard({
    super.key,
    required this.request,
    required this.busy,
    required this.formattedCreatedAt,
    required this.onApprove,
    required this.onReject,
  });

  final SubscriptionRequest request;
  final bool busy;
  final String formattedCreatedAt;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;

    return AppCard(
      padding: listCardPadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Dekoratif posta rozeti; büyük yazıda metne yer kalsın diye gizlenir.
              if (!isLargeText(context)) ...[
                const IconOrb(
                  icon: Icons.mark_email_unread_rounded,
                  tone: AppTone.info,
                  size: 48,
                  shape: IconOrbShape.squircle,
                ),
                const SizedBox(width: AppSpace.md),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(request.fullName, style: th.titleMedium),
                    const SizedBox(height: AppSpace.xs),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: AppSpace.sm,
                      runSpacing: AppSpace.xs,
                      children: [
                        const StatusChip(
                          label: 'Onay Bekliyor',
                          tone: AppTone.warning,
                        ),
                        InfoChip('Kod: ${request.id}'),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          Text('E-posta: ${request.email}', style: th.bodyMedium),
          if (request.phoneNumber != null && request.phoneNumber!.isNotEmpty) ...[
            const SizedBox(height: AppSpace.xs),
            Text('Telefon: ${request.phoneNumber}', style: th.bodyMedium),
          ],
          const SizedBox(height: AppSpace.xs),
          Text('Talep Tarihi: $formattedCreatedAt', style: th.bodySmall),
          const SizedBox(height: AppSpace.lg),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: [
              // Birincil eylem dolu (tema cilası) ve önde; ret ikincil: danger kenarlı.
              FilledButton.icon(
                onPressed: busy
                    ? null
                    : () {
                        HapticFeedback.lightImpact();
                        onApprove();
                      },
                style: filledToneStyle(context, tone: AppTone.success),
                icon: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_rounded, size: 18),
                label: const Text('Onayla'),
              ),
              OutlinedButton.icon(
                onPressed: busy ? null : onReject,
                style: dangerOutlineStyle(context),
                icon: const Icon(Icons.close_rounded, size: 18),
                label: const Text('Reddet'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
