import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/finance_home.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/money.dart';
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
    this.onOpenBankLines,
    this.onOpenLiabilityTransfer,
    this.onOpenRefunds,
  });

  /// Yazma yetkili finans siteleri.
  final List<PeopleSite> sites;
  final Future<FinanceHome> Function(int siteCode) fetch;

  /// Finans ekranını site ve sekmeyle açar.
  final void Function(int siteCode, int tab) onOpenFinance;

  /// Banka hareketleri ekranını (BankLinesView) doğrudan açar.
  final Future<void> Function(PeopleSite site)? onOpenBankLines;

  /// Malike devredilebilir kiracı borçları penceresini (K17: `tenant_debt_overdue_transfer` / `tenant_debt_pending_transfer`) doğrudan açar;
  /// verilmezse düğme Daireler sekmesine götürür (orada öneri şeridi aynı pencereyi açar).
  final Future<void> Function(PeopleSite site)? onOpenLiabilityTransfer;

  /// Onay bekleyen iade talepleri penceresini (K4: `refund_requests`) doğrudan açar; verilmezse düğme Daireler sekmesine götürür (orada iade girişi aynı pencereyi açar).
  final Future<void> Function(PeopleSite site)? onOpenRefunds;

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

  Future<void> reload() => _load();

  Future<void> _handleAction(PeopleSite site, FinanceHomeAttention a) async {
    if (a.key == 'bank_lines' && widget.onOpenBankLines != null) {
      await widget.onOpenBankLines!(site);
      if (mounted) unawaited(_load());
    } else if (_isLiabilityKey(a.key) && widget.onOpenLiabilityTransfer != null) {
      await widget.onOpenLiabilityTransfer!(site);
      if (mounted) unawaited(_load());
    } else if (a.key == 'refund_requests' && widget.onOpenRefunds != null) {
      await widget.onOpenRefunds!(site);
      if (mounted) unawaited(_load());
    } else {
      widget.onOpenFinance(site.code, _describe(a).$2);
    }
  }

  /// K17: kiracı borcu malike devredilebilir (gecikmede ya da kiracı çıkışında) dikkat satırları.
  static bool _isLiabilityKey(String key) => key == 'tenant_debt_overdue_transfer' || key == 'tenant_debt_pending_transfer';

  static (String, int, String) _describe(FinanceHomeAttention a) {
    switch (a.key) {
      case 'unassigned_payments':
        return ('${a.count} tahsilat kasa / banka hesabına eşlenmedi', FinanceHomeTab.cash, 'Hesaba Aktar');
      case 'bank_lines':
        return (
          'Bankadan gelen ${a.count} ödeme daireyle eşleştirilmeyi ve onayınızı bekliyor',
          FinanceHomeTab.cash,
          'İncele ve Onayla',
        );
      case 'payment_notices':
        return (
          'Sakinlerden gelen ${a.count} dekont / ödeme bildirimi onay bekliyor',
          FinanceHomeTab.notices,
          'Dekontları Gör',
        );
      case 'tenant_debt_overdue_transfer':
        // Sayı kesilmiş bir listeden çıktıysa "en az" yazılır (yönetici eksik sayıyı tam sanmasın).
        return (
          '${a.atLeast ? 'En az ' : ''}${a.count} dairede kiracının borcu gecikti; ev sahibine devredilebilir',
          FinanceHomeTab.balances,
          'Devri İncele',
        );
      case 'tenant_debt_pending_transfer':
        return (
          '${a.count} dairede kiracı ayrıldı, borcu kiracı hesabında duruyor; ev sahibine devredilebilir',
          FinanceHomeTab.balances,
          'Devri İncele',
        );
      case 'refund_requests':
        // K4: sakinin "Fazla ödememi iade et" talebi; iade YALNIZ yönetici onayıyla yapılır.
        return (
          '${a.count} iade talebi onayınızı bekliyor${a.totalMinor == null ? '' : ', toplam ${formatMinor(a.totalMinor!)}'}',
          FinanceHomeTab.balances,
          'İadeleri İncele',
        );
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
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final labelText = multi ? '${site.label}: ${_describe(a).$1}' : _describe(a).$1;
                      final button = OutlinedButton(
                        key: ValueKey<String>('month_attention_${site.code}_${a.key}'),
                        style: OutlinedButton.styleFrom(
                          backgroundColor: AppShowcaseColors.onFocus,
                          foregroundColor: AppShowcaseColors.focus,
                          side: BorderSide.none,
                          shape: const StadiumBorder(),
                          padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.xs),
                          minimumSize: const Size(48, 48),
                        ),
                        onPressed: () => _handleAction(site, a),
                        child: Semantics(
                          label: spokenMoneyText('${multi ? '${site.label}: ' : ''}${_describe(a).$1}. ${_describe(a).$3}'),
                          excludeSemantics: true,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  _describe(a).$3,
                                  style: const TextStyle(
                                    color: AppShowcaseColors.focus,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
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
                      );

                      if (constraints.maxWidth < 420) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              labelText,
                              semanticsLabel: spokenMoneyText(labelText),
                              style: th.bodyLarge?.copyWith(color: AppShowcaseColors.onFocus),
                            ),
                            const SizedBox(height: AppSpace.sm),
                            Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: button,
                            ),
                          ],
                        );
                      }

                      return Row(
                        children: [
                          Expanded(
                            child: Text(
                              labelText,
                              semanticsLabel: spokenMoneyText(labelText),
                              style: th.bodyLarge?.copyWith(color: AppShowcaseColors.onFocus),
                            ),
                          ),
                          const SizedBox(width: AppSpace.sm),
                          button,
                        ],
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}