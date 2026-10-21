import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

/// Modüller ekranındaki eski "Ek Roller" bölümünün yerine geçen yönlendirme kartı: yönetim kadrosu artık
/// Kişiler > Kadro sekmesinde ve kişi kartındaki "Görev ver" ile yönetilir. Ağ isteği yapmaz.
class TeamRedirectCard extends StatelessWidget {
  const TeamRedirectCard({super.key});

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    return AppCard(
      key: const ValueKey<String>('team_redirect_card'),
      padding: listCardPadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'Yönetim Kadrosu', icon: Icons.badge_rounded),
          const SizedBox(height: AppSpace.sm),
          Text(
            'Kurul üyesi, denetçi, kapıcı, teknik görevli ve danışma görevleri artık Kişiler ekranında: kişinin kartından '
            '"Görev ver" deyin, tüm kadroyu "Kadro" sekmesinde görün.',
            style: th.bodyMedium?.copyWith(color: context.palette.textSecondary),
          ),
        ],
      ),
    );
  }
}
