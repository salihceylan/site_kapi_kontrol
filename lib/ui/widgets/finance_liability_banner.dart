import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/finance_liability.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/finance_liability_candidates_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_4b_access.dart';
import 'package:site_kapi_kontrol/ui/helpers/money.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';

/// Daireler sekmesinin üstündeki öneri şeridi (karar K17): kiracı borcu gecikmiş ya da kiracısı ayrılmış, malike devredilebilir daire
/// varsa sayıyı ve toplamı yazar ve "Devri İncele" ile [FinanceLiabilityCandidatesDialog]'u açar. Yalnız YAZMA yetkisi olan yöneticiye
/// çizilir (kurul yalnız okur). Öneri yoksa, okunamazsa ya da yüklenirken HİÇBİR ŞEY çizilmez: şerit ana listeyi engellemez ve
/// "öneri yok" diye yanlış bir güvence vermez (okunamayan öneri kendi yolundan, yönetici dikkat barından görünür).
class FinanceLiabilityBanner extends StatefulWidget {
  const FinanceLiabilityBanner({super.key, required this.scope, required this.onChanged});

  final PeopleScope scope;

  /// Devir ya da geri alma yazılınca çağrılır (üst liste tazelenir).
  final VoidCallback onChanged;

  @override
  State<FinanceLiabilityBanner> createState() => _FinanceLiabilityBannerState();
}

class _FinanceLiabilityBannerState extends State<FinanceLiabilityBanner> {
  LiabilityCandidatePage? _page;
  int _token = 0;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    if (widget.scope.canWrite) unawaited(_load());
  }

  @override
  void dispose() {
    ++_token;
    super.dispose();
  }

  Future<void> _load() async {
    final token = ++_token;
    try {
      final page = await widget.scope.f4Call((api, t, s) => api.listLiabilityCandidates(token: t, siteCode: s));
      if (!mounted || token != _token) return;
      setState(() => _page = page);
    } catch (_) {
      if (!mounted || token != _token) return;
      setState(() => _page = null);
    }
  }

  Future<void> _open() async {
    if (_opening) return;
    _opening = true;
    try {
      await FinanceLiabilityCandidatesDialog.show(context, scope: widget.scope, onChanged: widget.onChanged);
    } finally {
      _opening = false;
    }
    if (mounted) unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    final page = _page;
    if (!widget.scope.canWrite || page == null || page.items.isEmpty) return const SizedBox.shrink();
    final th = Theme.of(context).textTheme;
    final total = formatMinor(page.totalMinor);
    final text =
        '${page.truncated ? 'En az ' : ''}${page.count} dairede kiracının vadesi geçmiş (ya da kiracısı ayrılmış) borcu var, toplam $total. '
        'Kiracı ödemezse borç ev sahibine devredilebilir.';
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.md),
      child: AppCard(
        key: const ValueKey<String>('finance_liability_banner'),
        tone: AppTone.warning,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(header: true, container: true, child: Text('Malike devredilebilir borç', style: th.titleMedium)),
            const SizedBox(height: AppSpace.xs),
            Text(text, semanticsLabel: spokenMoneyText(text), style: th.bodyMedium),
            const SizedBox(height: AppSpace.md),
            PrimaryActionButton(
              key: const ValueKey<String>('finance_liability_banner_open'),
              label: 'Devri İncele',
              icon: Icons.swap_horiz_rounded,
              variant: AppButtonVariant.tonal,
              tone: AppTone.warning,
              onPressed: _opening ? null : _open,
            ),
          ],
        ),
      ),
    );
  }
}
