import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/subscription_request.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
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
            children: [
              const IconTile(
                icon: Icons.mark_email_unread_rounded,
                size: 40,
                gap: AppSpace.md,
              ),
              Expanded(
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: AppSpace.sm,
                  runSpacing: AppSpace.xs,
                  children: [
                    Text(request.fullName, style: th.titleMedium),
                    InfoChip('Kod: ${request.id}'),
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
              OutlinedButton.icon(
                onPressed: busy ? null : onReject,
                style: dangerOutlineStyle(context),
                icon: const Icon(Icons.close_rounded, size: 18),
                label: const Text('Reddet'),
              ),
              FilledButton.icon(
                onPressed: busy ? null : onApprove,
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
            ],
          ),
        ],
      ),
    );
  }
}
