import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/subscription_request.dart';
import 'package:site_kapi_kontrol/styles/app_colors.dart';

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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x22FFFFFF), width: 1.2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x30000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.mark_email_unread_rounded, color: AppColors.accent, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  request.fullName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15.5,
                    color: Color(0xFFF8FAFC),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Kod: ${request.id}',
                  style: const TextStyle(color: AppColors.textMutedLight, fontSize: 11.5, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'E-posta: ${request.email}',
            style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 13),
          ),
          if (request.phoneNumber != null && request.phoneNumber!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Telefon: ${request.phoneNumber}',
              style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 13),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            'Talep Tarihi: $formattedCreatedAt',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: busy ? null : onReject,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.roseLight,
                  side: BorderSide(color: AppColors.rose.withValues(alpha: 0.4)),
                ),
                icon: const Icon(Icons.close_rounded, size: 18),
                label: const Text('Reddet'),
              ),
              FilledButton.icon(
                onPressed: busy ? null : onApprove,
                style: FilledButton.styleFrom(backgroundColor: AppColors.emerald),
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
