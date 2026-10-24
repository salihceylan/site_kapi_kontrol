import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/finance_home.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';

/// Finans sekmeleri (FinanceView kimlikleri; sekme çubuğundaki sıra farklı olabilir).
abstract final class FinanceHomeTab {
  static const int balances = 0;
  static const int definitions = 1;
  static const int periods = 2;
  static const int cash = 3;
  static const int expenses = 4;
  static const int reports = 5;
  static const int notices = 6;
  static const int charts = 7;
}

/// Yönetici ana sayfası dikkat barı: yalnız bekleyen iş varken (sayı > 0) koyu bar çizer; iş yoksa, veri
/// alınamazsa ya da yüklenirken HİÇBİR ŞEY çizmez (ekranda boşluk bile kalmaz).
///
/// Eskiden bu alanda "Bu ay" özeti (dört sayı, aylık döngü, son hareketler) vardı; yöneticiler anlamadığı için kaldırıldı
/// (2026-10-21). Rakamlar artık Finans > Grafikler sekmesindedir. Veri kaynağı `GET .../finance/home` `attention` alanıdır.
/// Birden çok sitede her sitenin işleri ayrı satır olur ve site adı yazılır.
class ManagerAttentionBar extends StatefulWidget {
  const ManagerAttentionBar({
    super.key,
    required this.sites,
    required this.fetch,
    required this.onOpenFinance,
  });

  /// Yazma yetkili finans siteleri.
  final List<PeopleSite> sites;
  final Future<FinanceHome> Function(int siteCode) fetch;

  /// Finans ekranını site ve sekmeyle açar.
  final void Function(int siteCode, int tab) onOpenFinance;

  @override
  State<ManagerAttentionBar> createState() => _ManagerAttentionBarState();
}

class _ManagerAttentionBarState extends State<ManagerAttentionBar> {
  /// Site kodu -> bekleyen işler (yalnız sayısı > 0 olanlar). Hata veren site listede yoktur.
  Map<int, List<FinanceHomeAttention>> _items = const <int, List<FinanceHomeAttention>>{};
  int _token = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(ManagerAttentionBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final before = oldWidget.sites.map((s) => s.code).toList();
    final now = widget.sites.map((s) => s.code).toList();
    if (before.length != now.length || !before.every(now.contains)) unawaited(_load());
  }

  @override
  void dispose() {
    ++_token;
    super.dispose();
  }

  Future<void> _load() async {
    final token = ++_token;
    final sites = widget.sites.toList(growable: false);
    final results = await Future.wait<List<FinanceHomeAttention>?>(
      sites.map((site) async {
        try {
          final home = await widget.fetch(site.code);
          return home.attention.where((a) => a.count > 0).toList(growable: false);
        } catch (_) {
          return null;
        }
      }),
    );
    if (!mounted || token != _token) return;
    setState(() {
      _items = <int, List<FinanceHomeAttention>>{
        for (final (i, site) in sites.indexed)
          if (results[i] != null && results[i]!.isNotEmpty) site.code: results[i]!,
      };
    });
  }

  static (String, int, String) _describe(FinanceHomeAttention a) {
    switch (a.key) {
      case 'unassigned_payments':
        return ('${a.count} tahsilat kasa / bankaya eşlenmedi', FinanceHomeTab.cash, 'Eşle');
      case 'bank_lines':
        return ('${a.count} banka hareketi onay bekliyor', FinanceHomeTab.cash, 'Eşle');
      case 'payment_notices':
        return ('${a.count} ödeme bildirimi onay bekliyor', FinanceHomeTab.notices, 'İncele');
      default:
        return ('${a.count} bekleyen iş var', FinanceHomeTab.balances, 'İncele');
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = <(PeopleSite, FinanceHomeAttention)>[
      for (final site in widget.sites)
        for (final a in _items[site.code] ?? const <FinanceHomeAttention>[]) (site, a),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();
    final th = Theme.of(context).textTheme;
    final dark = context.palette.isDark;
    final multi = widget.sites.length > 1;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.lg),
      child: DecoratedBox(
        key: const ValueKey<String>('month_attention_bar'),
        decoration: BoxDecoration(
          color: dark ? AppShowcaseColors.focusDark : AppShowcaseColors.focus,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: dark ? Border.all(color: AppTone.primary.hue, width: 1.5) : Border.all(color: AppShowcaseColors.focusBorder),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(
                  'Dikkat edilmesi gereken ${rows.length} iş var',
                  style: th.titleMedium?.copyWith(color: AppShowcaseColors.onFocus, fontWeight: FontWeight.w800),
                ),
              ),
              for (final (site, a) in rows)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpace.md),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          multi ? '${site.label}: ${_describe(a).$1}' : _describe(a).$1,
                          style: th.bodyLarge?.copyWith(color: AppShowcaseColors.onFocus),
                        ),
                      ),
                      const SizedBox(width: AppSpace.sm),
                      OutlinedButton(
                        key: ValueKey<String>('month_attention_${site.code}_${a.key}'),
                        style: OutlinedButton.styleFrom(
                          backgroundColor: AppShowcaseColors.onFocus,
                          foregroundColor: AppShowcaseColors.focus,
                          side: BorderSide.none,
                          shape: const StadiumBorder(),
                          padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.xs),
                          minimumSize: const Size(48, 48),
                        ),
                        onPressed: () => widget.onOpenFinance(site.code, _describe(a).$2),
                        child: Semantics(
                          label: '${multi ? '${site.label}: ' : ''}${_describe(a).$1}. ${_describe(a).$3}',
                          excludeSemantics: true,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _describe(a).$3,
                                style: const TextStyle(
                                  color: AppShowcaseColors.focus,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(
                                Icons.arrow_forward_rounded,
                                size: 16,
                                color: AppShowcaseColors.focus,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
