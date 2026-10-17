import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/finance_4b.dart';
import 'package:site_kapi_kontrol/models/late_fee_models.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/large_dialog_parts.dart';
import 'package:site_kapi_kontrol/ui/helpers/date_input.dart';
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_4b_access.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_errors.dart';
import 'package:site_kapi_kontrol/ui/helpers/money.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart' show ListSkeleton;

/// Sakin için "Gecikme tazminatı nasıl hesaplandı?" penceresi (Platform Faz 4b, Ö2): "Borcum" ekstresindeki tazminat
/// satırından açılır. Oran, gün esası, vadeye ek gün, gün-tutar toplamı ve gecikmiş tutar dilimleri SUNUCUNUN verdiği
/// değerlerdir; istemci tutarı yeniden hesaplamaz. Yükleme hatası "açıklama yok" demez ("Tekrar Dene").
class FinanceLateFeeExplainDialog extends StatefulWidget {
  const FinanceLateFeeExplainDialog({super.key, required this.scope, required this.entryId});

  final PeopleScope scope;
  final int entryId;

  static Future<void> show(BuildContext context, {required PeopleScope scope, required int entryId}) {
    return showDialog<void>(
      context: context,
      builder: (_) => FinanceLateFeeExplainDialog(scope: scope, entryId: entryId),
    );
  }

  @override
  State<FinanceLateFeeExplainDialog> createState() => _FinanceLateFeeExplainDialogState();
}

class _FinanceLateFeeExplainDialogState extends State<FinanceLateFeeExplainDialog> {
  LateFeeExplanation? _data;
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
    setState(() => _error = null);
    try {
      final data = await widget.scope.f4Call((api, t, s) => api.getMyLateFeeExplanation(token: t, entryId: widget.entryId));
      if (!mounted || token != _token) return;
      setState(() => _data = data);
    } catch (e) {
      if (!mounted || token != _token) return;
      setState(() {
        _data = null;
        _error = financeMessageOf(e, 'Açıklama yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final Widget body;
    if (data != null) {
      body = _buildBody(context, data);
    } else if (_error != null) {
      body = InlineNotice(key: const ValueKey<String>('finance_latefee_explain_error'), message: _error!, onRetry: _load);
    } else {
      body = const ListSkeleton(rows: 2);
    }
    return AppDialog(
      title: 'Gecikme Tazminatı',
      subtitle: data?.period?.label,
      icon: Icons.help_outline_rounded,
      actions: [
        TextButton(
          key: const ValueKey<String>('finance_latefee_explain_close'),
          onPressed: () => popIfCurrent(context),
          child: const Text('Kapat'),
        ),
      ],
      child: body,
    );
  }

  Widget _buildBody(BuildContext context, LateFeeExplanation data) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final lines = <String>[
      'Oran: ${formatRateBp(data.rateBp)} aylık.',
      'Gün esası: ${data.method.label}.',
      'Vadeye ek gün: ${data.graceDays}.',
      if (data.baseDayMinor != null) 'Ay içinde gecikmiş tutarların gün toplamı: ${formatMinor(data.baseDayMinor!)} (tutar x gün).',
      for (final s in data.segments)
        '${formatCrmDate(s.from)} - ${formatCrmDate(s.to)}: gecikmiş ${formatMinor(s.overdueMinor)}',
    ];
    final summary = 'Bu ay için gecikme tazminatı: ${formatMinor(data.amountMinor)}.';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          container: true,
          label: spokenMoneyText(summary),
          child: ExcludeSemantics(
            child: Text(
              formatMinor(data.amountMinor),
              key: const ValueKey<String>('finance_latefee_explain_amount'),
              style: th.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
        ),
        const SizedBox(height: AppSpace.xs),
        Text(
          'Vadesi geçmiş borcunuz için, geciken günlere göre hesaplanan gecikme tazminatıdır.',
          style: th.bodyMedium,
        ),
        const SizedBox(height: AppSpace.md),
        DialogPanel(
          key: const ValueKey<String>('finance_latefee_explain_panel'),
          child: Semantics(
            container: true,
            label: spokenMoneyText(lines.join(' ')),
            child: ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const DialogSectionTitle(icon: Icons.calculate_rounded, title: 'Nasıl hesaplandı?'),
                  const SizedBox(height: AppSpace.sm),
                  for (final line in lines) Padding(padding: const EdgeInsets.only(bottom: 2), child: Text(line, style: th.bodySmall)),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpace.sm),
        Text(
          'Tazminat bu değerlerden site yönetimi sisteminde hesaplanır. Bir yanlışlık olduğunu düşünüyorsanız site yönetimiyle iletişime geçin.',
          style: th.bodySmall?.copyWith(color: p.textSecondary),
        ),
      ],
    );
  }
}
