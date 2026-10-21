import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/finance.dart';
import 'package:site_kapi_kontrol/models/finance_4b.dart';
import 'package:site_kapi_kontrol/models/late_fee_models.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/finance_late_fee_dialog.dart' show LateFeeBreakdownText;
import 'package:site_kapi_kontrol/ui/dialogs/large_dialog_parts.dart';
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_4b_access.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_errors.dart';
import 'package:site_kapi_kontrol/ui/helpers/money.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/widgets/crm_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_parts.dart';

/// Bir tazminat çalıştırmasının satırları (Platform Faz 4b, Ö2): daire, kim öder, tutar ve "nasıl hesaplandı" dökümü.
/// Yönetici ve kurul görür (kişi adı yok: yalnız daire etiketi). Hata asla "satır yok" demez.
class FinanceLateFeeLinesDialog extends StatefulWidget {
  const FinanceLateFeeLinesDialog({super.key, required this.scope, required this.run});

  final PeopleScope scope;
  final LateFeeRun run;

  static Future<void> show(BuildContext context, {required PeopleScope scope, required LateFeeRun run}) {
    return showDialog<void>(
      context: context,
      builder: (_) => FinanceLateFeeLinesDialog(scope: scope, run: run),
    );
  }

  @override
  State<FinanceLateFeeLinesDialog> createState() => _FinanceLateFeeLinesDialogState();
}

class _FinanceLateFeeLinesDialogState extends State<FinanceLateFeeLinesDialog> {
  // İP-1A: aynı dairenin iki hesabı iki satırdır; satırlar daire + hesap anahtarıyla ayrılır ([LateFeeLine.lineKey]).
  final Set<String> _explained = <String>{};

  late final PagedLoader<LateFeeLine> _loader = PagedLoader<LateFeeLine>(
    fetch: (offset, limit) async {
      final page = await widget.scope.f4Call(
        (api, t, s) => api.listLateFeeRunLines(token: t, siteCode: s, runId: widget.run.id, limit: limit, offset: offset),
      );
      return (items: page.items, total: page.total);
    },
    keyOf: (l) => l.lineKey,
    notify: () {
      if (mounted) setState(() {});
    },
    isAlive: () => mounted,
    errorFallback: 'Satırlar yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
    messageOf: financeMessageOf,
  );

  @override
  void initState() {
    super.initState();
    unawaited(_loader.reload());
  }

  @override
  void dispose() {
    _loader.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final run = widget.run;
    return AppDialog(
      title: 'Tazminat Satırları',
      subtitle: run.period?.label,
      icon: Icons.list_alt_rounded,
      actions: [
        TextButton(
          key: const ValueKey<String>('finance_latefee_lines_close'),
          onPressed: () => popIfCurrent(context),
          child: const Text('Kapat'),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${run.apartmentCount} daire • toplam ${formatMinor(run.totalMinor)} • ${formatRateBp(run.params.rateBp)} aylık, ${run.params.method.label}',
            semanticsLabel: spokenMoneyText(
              '${run.apartmentCount} daire • toplam ${formatMinor(run.totalMinor)} • ${formatRateBp(run.params.rateBp)} aylık, ${run.params.method.label}',
            ),
            style: th.bodyMedium,
          ),
          const SizedBox(height: AppSpace.md),
          CrmListBody<LateFeeLine>(
            loader: _loader,
            emptyIcon: Icons.list_alt_rounded,
            emptyTitle: 'Bu çalıştırmada satır yok.',
            skeletonRows: 2,
            hideItemsOnError: true,
            itemBuilder: (context, line) {
              final title = financeApartmentTitle(line.blockName, line.label);
              final expanded = _explained.contains(line.lineKey);
              final payer = line.payerParty;
              final account = line.accountParty;
              return DialogPanel(
                key: ValueKey<String>('finance_latefee_run_line_${line.lineKey}'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Semantics(
                      container: true,
                      label: '$title. ${account == null ? '' : '${account.label}. '}${payer == null ? '' : '${payerPartyLabel(payer)}. '}Tazminat: ${moneySemanticLabel(line.amountMinor)}.${line.reversed ? ' İptal edildi.' : ''}',
                      child: ExcludeSemantics(
                        child: Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          spacing: AppSpace.sm,
                          runSpacing: AppSpace.xs,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(title, style: th.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                                if (account != null) Text(account.label, style: th.bodySmall?.copyWith(color: p.textSecondary)),
                                if (payer != null) Text(payerPartyLabel(payer), style: th.bodySmall?.copyWith(color: p.textSecondary)),
                              ],
                            ),
                            Text(
                              formatMinor(line.amountMinor),
                              style: th.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                decoration: line.reversed ? TextDecoration.lineThrough : null,
                              ),
                            ),
                            if (line.reversed)
                              const DialogMetaPill('İptal edildi', tone: AppTone.neutral, icon: Icons.block_rounded),
                          ],
                        ),
                      ),
                    ),
                    TextButton.icon(
                      key: ValueKey<String>('finance_latefee_run_explain_${line.lineKey}'),
                      onPressed: () => setState(() {
                        if (expanded) {
                          _explained.remove(line.lineKey);
                        } else {
                          _explained.add(line.lineKey);
                        }
                      }),
                      icon: Icon(expanded ? Icons.expand_less_rounded : Icons.help_outline_rounded, size: 18),
                      label: Text(expanded ? 'Dökümü gizle' : 'Nasıl hesaplandı?'),
                      style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                    ),
                    if (expanded) LateFeeBreakdownText(line: line, params: run.params, window: const LateFeeWindow()),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
