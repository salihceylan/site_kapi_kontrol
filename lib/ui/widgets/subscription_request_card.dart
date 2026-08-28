import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/subscription_request.dart';
import 'package:site_kapi_kontrol/styles/app_colors.dart';
import 'package:site_kapi_kontrol/styles/app_decorations.dart';

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
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppDecorations.infoCard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            request.fullName,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 6),
          Text(request.email),
          const SizedBox(height: 4),
          Text('Kod: ${request.id}'),
          if (request.phoneNumber != null &&
              request.phoneNumber!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Telefon: ${request.phoneNumber}'),
          ],
          const SizedBox(height: 4),
          Text('Talep Tarihi: $formattedCreatedAt'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: busy ? null : onReject,
                icon: const Icon(Icons.close_rounded, size: 18),
                label: const Text('Reddet'),
              ),
              ElevatedButton.icon(
                onPressed: busy ? null : onApprove,
                icon: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
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
