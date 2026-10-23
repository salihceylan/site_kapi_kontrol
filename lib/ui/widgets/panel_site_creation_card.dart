import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/brand/brand_scope.dart';
import 'package:site_kapi_kontrol/services/site_application_tracker.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

/// Hiçbir daireye ait olmayan, site yöneticisi ve süper kullanıcı olmayan kullanıcıların
/// ana panelde (Dashboard) doğrudan yeni site oluşturma sürecini başlatmasını sağlayan kart.
class PanelSiteCreationCard extends StatelessWidget {
  const PanelSiteCreationCard({
    super.key,
    required this.onStartSetup,
    this.tracker,
  });

  final VoidCallback onStartSetup;
  final SiteApplicationTracker? tracker;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpace.lg),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTone.primary.a.withValues(alpha: 0.12),
            AppTone.primary.a.withValues(alpha: 0.04),
          ],
        ),
        border: Border.all(
          color: AppTone.primary.a.withValues(alpha: 0.35),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: AppTone.primary.a.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTone.primary.a.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppTone.primary.a.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Icon(
                    Icons.domain_add_rounded,
                    color: AppTone.primary.a,
                    size: 26,
                  ),
                ),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              'Yeni Site Oluştur',
                              style: th.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: p.text,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: AppSpace.sm),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppTone.primary.a.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'YÖNETİCİ OLUN',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: AppTone.primary.a,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Henüz kayıtlı bir daireniz bulunmuyor. Kendi sitenizi veya apartmanınızı sisteme tanımlayarak dijital site yönetimini hemen başlatabilirsiniz.',
                        style: th.bodySmall?.copyWith(
                          color: p.textMuted,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.md),
            Wrap(
              spacing: AppSpace.md,
              runSpacing: AppSpace.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: onStartSetup,
                  icon: const Icon(Icons.add_business_rounded, size: 18),
                  label: const Text(
                    'Site Kurulumunu Başlat',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTone.primary.a,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 2,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

