import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/finance_refund.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/finance_refunds_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_4b_access.dart';
import 'package:site_kapi_kontrol/ui/helpers/money.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';

/// Bakiyeler sekmesindeki iade girişi (karar K4): onay bekleyen iade talebi varsa sayıyı ve toplamı yazan uyarı kartı ("İadeleri İncele"), her durumda da
/// "İade talepleri" düğmesi (geçmiş ve onaylı iadeyi geri alma buradan açılır). Bekleyen sayısı okunamazsa kart çizilmez ama düğme durur: şerit ana listeyi
/// engellemez ve "talep yok" diye yanlış güvence vermez (okunamayan sayı kendi yolundan, yönetici dikkat barından görünür). Kurul (salt okunur) listeyi açar;
/// onay / ret / geri alma düğmeleri pencerede yalnız yazma yetkisine çizilir.
class FinanceRefundsEntry extends StatefulWidget {
  const FinanceRefundsEntry({super.key, required this.scope, required this.onChanged, this.extraAction});

  final PeopleScope scope;

  /// Karar yazılınca çağrılır (üst liste tazelenir).
  final VoidCallback onChanged;

  /// "İade talepleri" düğmesinin yanına konan ikinci eylem (örn. "Devir bakiyesi"); aynı satırda sarar.
  final Widget? extraAction;

  @override
  State<FinanceRefundsEntry> createState() => _FinanceRefundsEntryState();
}

class _FinanceRefundsEntryState extends State<FinanceRefundsEntry> {
  RefundPage? _page;
  int _token = 0;
  bool _opening = false;

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
    try {
      final page = await widget.scope.f4Call((api, t, s) => api.listRefunds(token: t, siteCode: s, limit: 1));
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
      await FinanceRefundsDialog.show(context, scope: widget.scope, onChanged: widget.onChanged);
    } finally {
      _opening = false;
    }
    if (mounted) unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    final page = _page;
    final th = Theme.of(context).textTheme;
    final pending = page?.pendingCount ?? 0;
    final total = formatMinor(page?.pendingTotalMinor ?? 0);
    final text = '$pending sakin fazla ödemesinin iadesini istedi, toplam $total. İade yalnız sizin onayınızla yapılır.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (pending > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.md),
            child: AppCard(
              key: const ValueKey<String>('finance_refunds_banner'),
              tone: AppTone.warning,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(header: true, container: true, child: Text('İade talebi onay bekliyor', style: th.titleMedium)),
                  const SizedBox(height: AppSpace.xs),
                  Text(text, semanticsLabel: spokenMoneyText(text), style: th.bodyMedium),
                  const SizedBox(height: AppSpace.md),
                  PrimaryActionButton(
                    key: const ValueKey<String>('finance_refunds_banner_open'),
                    label: 'İadeleri İncele',
                    icon: Icons.currency_exchange_rounded,
                    variant: AppButtonVariant.tonal,
                    tone: AppTone.warning,
                    onPressed: _opening ? null : _open,
                  ),
                ],
              ),
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: [
              if (widget.extraAction != null) widget.extraAction!,
              OutlinedButton.icon(
                key: const ValueKey<String>('finance_refunds_button'),
                onPressed: _opening ? null : _open,
                icon: const Icon(Icons.currency_exchange_rounded),
                label: const Text('İade talepleri'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
