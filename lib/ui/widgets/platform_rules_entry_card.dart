import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/views/platform_rules_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

/// "Kurallar" giriş kartı (karar G11): kurallar tam sayfasını ([PlatformRulesScreen]) açar. Ağ isteği yapmaz (sayfa açılınca yükler).
///
/// - "Platform Ayarları" (süper kullanıcı): [siteCode] null, [canEdit] true -> platform geneli değerler değiştirilir.
/// - "Modüller" (seçili site): yönetici için [canEdit] false (salt okunur); süper kullanıcıda siteye özel değerler.
class PlatformRulesEntryCard extends StatelessWidget {
  const PlatformRulesEntryCard({super.key, required this.authService, required this.canEdit, this.siteCode, this.siteName});

  final AuthService authService;
  final bool canEdit;
  final int? siteCode;
  final String? siteName;

  String get _body {
    if (!canEdit) {
      return 'Sitenizde geçerli kurallar: gecikme tazminatı üst sınırı, işletme projesi süreleri ve saklama süreleri gibi. Yalnızca görüntülenir.';
    }
    if (siteCode != null) {
      return 'Bu sitede geçerli kurallar. Sitede değişebilen kurallar için siteye özel değer verilebilir.';
    }
    return 'Gecikme tazminatı üst sınırı, işletme projesi süreleri, ısınma payı, tahmin ve saklama süreleri. Değerler sınırlar içinde '
        'değiştirilir ve denetim kaydına yazılır.';
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    return AppCard(
      key: const ValueKey<String>('platform_rules_entry'),
      padding: listCardPadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'Kurallar', icon: Icons.rule_rounded),
          const SizedBox(height: AppSpace.sm),
          Text(_body, style: th.bodyMedium?.copyWith(color: context.palette.textSecondary)),
          const SizedBox(height: AppSpace.md),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: PrimaryActionButton(
              key: const ValueKey<String>('platform_rules_open'),
              label: canEdit ? 'Kuralları Aç' : 'Kuralları Görüntüle',
              icon: Icons.rule_rounded,
              variant: AppButtonVariant.tonal,
              expand: false,
              onPressed: () => PlatformRulesScreen.open(context, authService: authService, canEdit: canEdit, siteCode: siteCode, siteName: siteName),
            ),
          ),
        ],
      ),
    );
  }
}
