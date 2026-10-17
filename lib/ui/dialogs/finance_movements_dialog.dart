import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/cash_models.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/large_dialog_parts.dart';
import 'package:site_kapi_kontrol/ui/helpers/cursor_loader.dart';
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_4b_access.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_errors.dart';
import 'package:site_kapi_kontrol/ui/helpers/money.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/widgets/cursor_list_body.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_4b_parts.dart';

/// Hesap hareketleri penceresi (Platform Faz 4b, Ö4): güncel bakiye (sunucu toplamı) + hareketler (yeniden eskiye,
/// `before_id` imleciyle sayfalı). Hareketler silinmez / değişmez: iptaller ters hareketle görünür. Bakiye eksiyse
/// uyarılır (engellenmez; kayıtlar eksik olabilir). Hata asla "hareket yok / bakiye 0" demez; eski yanıt yenisini
/// ezmez.
class FinanceMovementsDialog extends StatefulWidget {
  const FinanceMovementsDialog({super.key, required this.scope, required this.account});

  final PeopleScope scope;
  final CashAccount account;

  static Future<void> show(BuildContext context, {required PeopleScope scope, required CashAccount account}) {
    return showDialog<void>(
      context: context,
      builder: (_) => FinanceMovementsDialog(scope: scope, account: account),
    );
  }

  @override
  State<FinanceMovementsDialog> createState() => _FinanceMovementsDialogState();
}

class _FinanceMovementsDialogState extends State<FinanceMovementsDialog> {
  MovementPage? _header;
  int _headerSeq = 0;

  late final CursorLoader<AccountMovement> _loader = CursorLoader<AccountMovement>(
    fetch: (before) async {
      // Bakiye yalnız İLK sayfadan ve yalnız EN SON isteğin yanıtından alınır (eski yanıt yenisini ezmez).
      final seq = before == null ? ++_headerSeq : _headerSeq;
      try {
        final page = await widget.scope.f4Call(
          (api, t, s) => api.listMovements(token: t, siteCode: s, accountId: widget.account.id, beforeId: before),
        );
        if (before == null && seq == _headerSeq && mounted) _header = page;
        return (items: page.items, next: page.nextBeforeId);
      } catch (_) {
        // İlk sayfa okunamadı: eski bakiye gösterilmez.
        if (before == null && seq == _headerSeq && mounted) _header = null;
        rethrow;
      }
    },
    keyOf: (m) => m.id,
    notify: () {
      if (mounted) setState(() {});
    },
    isAlive: () => mounted,
    errorFallback: 'Hareketler yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
    moreErrorFallback: 'Daha fazla hareket yüklenemedi. Tekrar deneyin.',
    messageOf: financeMessageOf,
  );

  @override
  void initState() {
    super.initState();
    unawaited(_loader.reload());
  }

  @override
  void dispose() {
    ++_headerSeq;
    _loader.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final header = _header;
    return AppDialog(
      title: 'Hesap Hareketleri',
      subtitle: widget.account.name,
      icon: Icons.list_alt_rounded,
      actions: [
        TextButton(
          key: const ValueKey<String>('finance_movements_close'),
          onPressed: () => popIfCurrent(context),
          child: const Text('Kapat'),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (header != null)
            DialogPanel(
              key: const ValueKey<String>('finance_movements_header'),
              tone: header.negativeBalance || header.balanceMinor < 0 ? AppTone.danger : null,
              child: Semantics(
                container: true,
                label: 'Güncel bakiye: ${moneySemanticLabel(header.balanceMinor)}.',
                child: ExcludeSemantics(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Güncel bakiye', style: th.bodySmall?.copyWith(color: p.textSecondary)),
                      Text(
                        formatMinor(header.balanceMinor),
                        key: const ValueKey<String>('finance_movements_balance'),
                        style: th.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      if (header.negativeBalance || header.balanceMinor < 0)
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpace.xs),
                          child: Text(
                            'Bakiye eksiye düşmüş. Kayıtlar eksik olabilir; hareketleri ve açılış bakiyesini kontrol edin.',
                            style: th.bodySmall?.copyWith(color: AppTone.danger.ink(p), fontWeight: FontWeight.w700),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: AppSpace.md),
          Row(
            children: [
              Expanded(
                child: Semantics(header: true, container: true, child: Text('Hareketler', style: th.titleMedium)),
              ),
              IconButton(
                tooltip: 'Yenile',
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                onPressed: _loader.loading ? null : () => unawaited(_loader.reload()),
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          CursorListBody<AccountMovement>(
            loader: _loader,
            emptyIcon: Icons.list_alt_rounded,
            emptyTitle: 'Bu hesapta henüz hareket yok.',
            skeletonRows: 2,
            itemBuilder: (context, movement) => MovementTile(movement: movement),
          ),
        ],
      ),
    );
  }
}
