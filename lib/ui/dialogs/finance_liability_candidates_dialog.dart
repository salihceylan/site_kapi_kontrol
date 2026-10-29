import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/finance_liability.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/finance_liability_transfer_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/large_dialog_parts.dart';
import 'package:site_kapi_kontrol/ui/helpers/date_input.dart';
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_4b_access.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_errors.dart';
import 'package:site_kapi_kontrol/ui/helpers/money.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart' show ListSkeleton, listCardPadding;

/// Malike devredilebilir kiracı borcu olan daireler (karar K17: devir yalnız kiracı ÇIKIŞINDA değil GECİKMEDE de yönetici önüne açıkça
/// önerilir). Sunucu önerir (`GET .../liability-transfer/candidates`: vadesi gelmiş, ödenmemiş, tazminat olmayan kiracı borcu; büyük
/// tutar önce); yazılım KENDİLİĞİNDEN devretmez: daireye dokunulur, [FinanceLiabilityTransferDialog] önizleme + neden + onay ister.
///
/// - Hata asla "öneri yok" demez: okunamazsa neden yazılır ve "Tekrar Dene" çıkar.
/// - Liste kesilmişse (sunucu en çok 500 daire, en büyük tutarlar) bu açıkça yazılır.
/// - Malik kaydı olmayan daire listelenir ama devredilemez; nedeni (malik kaydı eklenmeli) yazılır.
/// - Bir daire devredilince ya da geri alınınca liste yeniden okunur ve [onChanged] çağrılır.
class FinanceLiabilityCandidatesDialog extends StatefulWidget {
  const FinanceLiabilityCandidatesDialog({super.key, required this.scope, this.onChanged});

  final PeopleScope scope;
  final VoidCallback? onChanged;

  static Future<void> show(BuildContext context, {required PeopleScope scope, VoidCallback? onChanged}) {
    return showDialog<void>(
      context: context,
      builder: (_) => FinanceLiabilityCandidatesDialog(scope: scope, onChanged: onChanged),
    );
  }

  @override
  State<FinanceLiabilityCandidatesDialog> createState() => _FinanceLiabilityCandidatesDialogState();
}

class _FinanceLiabilityCandidatesDialogState extends State<FinanceLiabilityCandidatesDialog> {
  LiabilityCandidatePage? _page;
  bool _loading = true;
  bool _opening = false;
  String? _error;
  int _token = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    ++_token;
    super.dispose();
  }

  Future<void> _load() async {
    final token = ++_token;
    setState(() {
      _loading = true;
      _error = null;
      _page = null; // yenilenirken eski tutarlar gösterilmez
    });
    try {
      final page = await widget.scope.f4Call((api, t, s) => api.listLiabilityCandidates(token: t, siteCode: s));
      if (!mounted || token != _token) return;
      setState(() {
        _page = page;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || token != _token) return;
      setState(() {
        _loading = false;
        _error = financeMessageOf(e, 'Devir önerileri yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.');
      });
    }
  }

  Future<void> _open(LiabilityCandidate candidate) async {
    if (_opening) return;
    _opening = true;
    try {
      await FinanceLiabilityTransferDialog.show(
        context,
        scope: widget.scope,
        apartmentId: candidate.apartmentId,
        apartmentLabel: candidate.title,
        onChanged: widget.onChanged,
      );
    } finally {
      _opening = false;
    }
    if (mounted) unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final page = _page;
    final Widget body;
    if (_loading) {
      body = const ListSkeleton(rows: 3);
    } else if (_error != null) {
      body = InlineNotice(key: const ValueKey<String>('finance_liability_candidates_error'), message: _error!, onRetry: _load);
    } else if (page == null || page.items.isEmpty) {
      body = const InlineNotice(
        key: ValueKey<String>('finance_liability_candidates_empty'),
        tone: AppTone.success,
        message: 'Malike devredilebilir gecikmiş kiracı borcu yok.',
      );
    } else {
      final total = formatMinor(page.totalMinor);
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Aşağıdaki dairelerde kiracı hesabında vadesi geçmiş, ödenmemiş borç var. Borç mutlaka tahsil edilir: kiracı vermezse ev sahibi öder. '
            'Devir kendiliğinden olmaz; daireyi açıp kalemleri inceler, nedenini yazarak onaylarsınız. İşlem kayıtlıdır ve geri alınabilir.',
            style: th.bodySmall?.copyWith(color: p.textSecondary),
          ),
          const SizedBox(height: AppSpace.md),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.xs,
            children: [
              DialogMetaPill('${page.count} daire', key: const ValueKey<String>('finance_liability_candidates_count'), icon: Icons.apartment_rounded),
              DialogMetaPill('Toplam $total', icon: Icons.account_balance_wallet_outlined),
            ],
          ),
          if (page.truncated) ...[
            const SizedBox(height: AppSpace.sm),
            const InlineNotice(
              key: ValueKey<String>('finance_liability_candidates_truncated'),
              tone: AppTone.warning,
              message: 'Liste en çok 500 daireyle sınırlıdır; en büyük tutarlar gösterilir. Devir yaptıkça kalan daireler görünür.',
            ),
          ],
          const SizedBox(height: AppSpace.md),
          for (final candidate in page.items)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.sm),
              child: _CandidateCard(candidate: candidate, enabled: !_opening, onTap: () => _open(candidate)),
            ),
        ],
      );
    }
    return AppDialog(
      title: 'Malike Devredilebilir Borçlar',
      subtitle: widget.scope.siteName.isEmpty ? null : widget.scope.siteName,
      icon: Icons.swap_horiz_rounded,
      tone: AppTone.warning,
      actions: [
        TextButton(
          key: const ValueKey<String>('finance_liability_candidates_close'),
          onPressed: () => popIfCurrent(context),
          child: const Text('Kapat'),
        ),
      ],
      child: body,
    );
  }
}

class _CandidateCard extends StatelessWidget {
  const _CandidateCard({required this.candidate, required this.enabled, required this.onTap});

  final LiabilityCandidate candidate;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final overdue = candidate.reason == LiabilityReason.overdue;
    final amount = formatMinor(candidate.totalMinor);
    final reasonText = overdue ? 'Gecikmiş borç' : 'Kiracı ayrıldı';
    final semantic = StringBuffer('Daire: ${candidate.title}. $reasonText. ${candidate.itemCount} kalem. Toplam ${spokenMoneyText(amount)}.');
    if (!candidate.canTransfer) semantic.write(' Malik kaydı yok, devredilemez.');
    return AppCard(
      key: ValueKey<String>('finance_liability_candidate_${candidate.apartmentId}'),
      padding: listCardPadding(context),
      onTap: enabled ? onTap : null,
      semanticLabel: semantic.toString(),
      // Dar ekranda ve büyük yazıda tutar başlığın yanına SIĞMAZ (Row taşardı): başlık, altında tutar, altında rozetler (hepsi sarar).
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(candidate.title, style: th.titleMedium),
            Text(amount, style: th.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: AppSpace.sm),
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.xs,
              children: [
                DialogMetaPill(reasonText, tone: overdue ? AppTone.warning : AppTone.info, icon: overdue ? Icons.schedule_rounded : Icons.logout_rounded),
                DialogMetaPill('${candidate.itemCount} kalem'),
                if (candidate.oldestDueDate != null) DialogMetaPill('En eski vade ${formatCrmDate(candidate.oldestDueDate)}'),
                if (!candidate.canTransfer) const DialogMetaPill('Malik kaydı yok', tone: AppTone.danger, icon: Icons.person_off_rounded),
              ],
            ),
            if (!candidate.canTransfer)
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.xs),
                child: Text('Devir için önce dairenin malik kaydını ekleyin.', style: th.bodySmall?.copyWith(color: p.textSecondary)),
              ),
          ],
        ),
      ),
    );
  }
}
