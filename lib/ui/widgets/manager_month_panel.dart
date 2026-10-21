import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/finance_home.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/status_dot.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/money.dart';

/// Finans sekmeleri (FinanceView sırası).
abstract final class FinanceHomeTab {
  static const int balances = 0;
  static const int definitions = 1;
  static const int periods = 2;
  static const int cash = 3;
  static const int expenses = 4;
  static const int reports = 5;
}

const List<String> _monthNames = <String>[
  'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran', 'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık', //
];

/// 'YYYY-AA' -> 'Ekim 2026'.
String monthTitleOf(String month) {
  final parts = month.split('-');
  final m = parts.length == 2 ? int.tryParse(parts[1]) : null;
  if (m == null || m < 1 || m > 12) return month;
  return '${_monthNames[m - 1]} ${parts[0]}';
}

/// Yönetici ana sayfası "Bu ay" paneli (G5): koyu dikkat barı, dört sayı, beş adımlı aylık döngü, son hareketler.
/// Veri alınamazsa "Bu ayın özeti alınamadı." gösterilir; hata hiçbir zaman 0 olarak gösterilmez.
class ManagerMonthPanel extends StatefulWidget {
  const ManagerMonthPanel({
    super.key,
    required this.sites,
    required this.fetch,
    required this.onOpenFinance,
    this.onOpenAnnouncements,
  });

  /// Yazma yetkili finans siteleri (tek site ise seçici görünmez).
  final List<PeopleSite> sites;
  final Future<FinanceHome> Function(int siteCode) fetch;

  /// Finans ekranını site ve sekmeyle açar.
  final void Function(int siteCode, int tab) onOpenFinance;
  final VoidCallback? onOpenAnnouncements;

  @override
  State<ManagerMonthPanel> createState() => _ManagerMonthPanelState();
}

class _ManagerMonthPanelState extends State<ManagerMonthPanel> {
  int? _siteCode;
  FinanceHome? _home;
  bool _failed = false;
  bool _loading = false;
  int _token = 0;

  @override
  void initState() {
    super.initState();
    _siteCode = widget.sites.isEmpty ? null : widget.sites.first.code;
    unawaited(_load());
  }

  @override
  void didUpdateWidget(ManagerMonthPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final code = _siteCode;
    if (code == null || !widget.sites.any((s) => s.code == code)) {
      _siteCode = widget.sites.isEmpty ? null : widget.sites.first.code;
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    ++_token;
    super.dispose();
  }

  Future<void> _load() async {
    final code = _siteCode;
    final token = ++_token;
    if (code == null) return;
    setState(() {
      _loading = true;
      _failed = false;
      _home = null;
    });
    try {
      final home = await widget.fetch(code);
      if (!mounted || token != _token) return;
      setState(() {
        _home = home;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || token != _token) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  void _open(int tab) {
    final code = _siteCode;
    if (code != null) widget.onOpenFinance(code, tab);
  }

  @override
  Widget build(BuildContext context) {
    if (_siteCode == null) return const SizedBox.shrink();
    final th = Theme.of(context).textTheme;
    final home = _home;
    return Column(
      key: const ValueKey<String>('manager_month_panel'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.sites.length > 1) ...[
          DropdownButtonFormField<int>(
            key: const ValueKey<String>('month_site_picker'),
            isExpanded: true,
            initialValue: _siteCode,
            decoration: const InputDecoration(labelText: 'Site', prefixIcon: Icon(Icons.apartment_rounded)),
            items: [
              for (final s in widget.sites) DropdownMenuItem<int>(value: s.code, child: Text(s.name, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (value) {
              if (value == null || value == _siteCode) return;
              _siteCode = value;
              unawaited(_load());
            },
          ),
          const SizedBox(height: AppSpace.md),
        ],
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(AppSpace.lg),
            child: Center(child: CircularProgressIndicator(semanticsLabel: 'Bu ayın özeti yükleniyor')),
          )
        else if (_failed || home == null)
          InlineNotice(
            key: const ValueKey<String>('month_error'),
            message: 'Bu ayın özeti alınamadı.',
            onRetry: () => unawaited(_load()),
          )
        else ...[
          if (home.attention.isNotEmpty) ...[
            _AttentionBar(items: home.attention, onOpen: _open),
            const SizedBox(height: AppSpace.lg),
          ],
          Semantics(
            header: true,
            child: Text('Bu ay · ${monthTitleOf(home.month)}', style: th.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: AppSpace.md),
          _NumbersGrid(numbers: home.numbers, onOpen: _open),
          const SizedBox(height: AppSpace.lg),
          _Cycle(steps: home.steps, onOpen: _open, onOpenAnnouncements: widget.onOpenAnnouncements),
          if (home.recent.isNotEmpty) ...[
            const SizedBox(height: AppSpace.lg),
            _Recent(items: home.recent),
          ],
        ],
        const SizedBox(height: AppSpace.lg),
      ],
    );
  }
}

class _AttentionBar extends StatelessWidget {
  const _AttentionBar({required this.items, required this.onOpen});

  final List<FinanceHomeAttention> items;
  final void Function(int tab) onOpen;

  static (String, int) _describe(FinanceHomeAttention a) {
    switch (a.key) {
      case 'unassigned_payments':
        return ('${a.count} tahsilat kasa / bankaya eşlenmedi', FinanceHomeTab.cash);
      default:
        return ('${a.count} bekleyen iş var', FinanceHomeTab.balances);
    }
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final dark = context.palette.isDark;
    return DecoratedBox(
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
                'Dikkat edilmesi gereken ${items.length} iş var',
                style: th.titleMedium?.copyWith(color: AppShowcaseColors.onFocus, fontWeight: FontWeight.w800),
              ),
            ),
            for (final a in items)
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.md),
                child: Row(
                  children: [
                    Expanded(child: Text(_describe(a).$1, style: th.bodyLarge?.copyWith(color: AppShowcaseColors.onFocus))),
                    const SizedBox(width: AppSpace.sm),
                    OutlinedButton(
                      key: ValueKey<String>('month_attention_${a.key}'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppShowcaseColors.onFocus,
                        side: const BorderSide(color: AppShowcaseColors.onFocus),
                        minimumSize: const Size(48, 48),
                      ),
                      onPressed: () => onOpen(_describe(a).$2),
                      child: Semantics(label: '${_describe(a).$1}. Eşle', excludeSemantics: true, child: const Text('Eşle')),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NumbersGrid extends StatelessWidget {
  const _NumbersGrid({required this.numbers, required this.onOpen});

  final FinanceHomeNumbers numbers;
  final void Function(int tab) onOpen;

  @override
  Widget build(BuildContext context) {
    final n = numbers;
    final rate = n.collectionRateBp;
    final cards = <Widget>[
      _NumberCard(
        cardKey: 'month_card_charged',
        title: 'Yazılan',
        value: formatMinor(n.chargedMinor),
        hint: n.lateFeeMinor > 0 ? '+ ${formatMinor(n.lateFeeMinor)} gecikme' : 'Bu ay yazılan borç',
        onTap: () => onOpen(FinanceHomeTab.reports),
      ),
      _NumberCard(
        cardKey: 'month_card_collected',
        title: 'Toplanan',
        value: formatMinor(n.collectedMinor),
        hint: rate == null ? 'Oran yok' : '%${(rate / 100).toStringAsFixed(rate % 100 == 0 ? 0 : 1)} toplandı',
        onTap: () => onOpen(FinanceHomeTab.reports),
      ),
      _NumberCard(
        cardKey: 'month_card_overdue',
        title: 'Geciken daire',
        value: '${n.overdueApartmentCount}',
        hint: '${n.apartmentCount} daireden',
        onTap: () => onOpen(FinanceHomeTab.reports),
      ),
      _NumberCard(
        cardKey: 'month_card_cash',
        title: 'Kasa + banka',
        value: n.cashTotalMinor == null ? 'Hesap yok' : formatMinor(n.cashTotalMinor!),
        hint: n.cashTotalMinor == null ? 'Kasa sekmesinden ekleyin' : '${n.cashAccountCount} hesap',
        onTap: () => onOpen(FinanceHomeTab.cash),
      ),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 720 ? 4 : 2;
        final w = (c.maxWidth - (cols - 1) * AppSpace.md) / cols;
        return Wrap(
          spacing: AppSpace.md,
          runSpacing: AppSpace.md,
          children: [for (final card in cards) SizedBox(width: w, child: card)],
        );
      },
    );
  }
}

class _NumberCard extends StatelessWidget {
  const _NumberCard({required this.cardKey, required this.title, required this.value, required this.hint, required this.onTap});

  final String cardKey;
  final String title;
  final String value;
  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    return AppCard(
      key: ValueKey<String>(cardKey),
      onTap: onTap,
      semanticLabel: '$title: $value. $hint',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: th.bodySmall?.copyWith(color: p.textSecondary, fontWeight: FontWeight.w700)),
          const SizedBox(height: AppSpace.xs),
          FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: th.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
          const SizedBox(height: AppSpace.xs),
          Text(hint, style: th.bodySmall?.copyWith(color: p.textSecondary), maxLines: 2, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

class _Cycle extends StatelessWidget {
  const _Cycle({required this.steps, required this.onOpen, required this.onOpenAnnouncements});

  final List<FinanceHomeStep> steps;
  final void Function(int tab) onOpen;
  final VoidCallback? onOpenAnnouncements;

  static const Map<String, String> _titles = <String, String>{
    'charge': 'Borç yaz',
    'notify': 'Haber ver',
    'match': 'Tahsilatları eşle',
    'expense': 'Giderleri gir',
    'report': 'Rapor al',
  };

  static String _statusText(FinanceHomeStep s) {
    switch (s.status) {
      case 'done':
        return 'Tamam';
      case 'partial':
        return s.total == null ? 'Kısmen' : '${s.done ?? 0}/${s.total} yazıldı';
      case 'setup':
        return s.key == 'match' ? 'Hesap tanımlı değil' : 'Önce tanım ekleyin';
      case 'unavailable':
        return 'Kullanılamıyor';
      default:
        return s.key == 'match' && (s.pending ?? 0) > 0 ? '${s.pending} kalem bekliyor' : 'Bekliyor';
    }
  }

  static AppTone _tone(String status) {
    switch (status) {
      case 'done':
        return AppTone.success;
      case 'partial':
      case 'todo':
        return AppTone.warning;
      default:
        return AppTone.neutral;
    }
  }

  (String, VoidCallback?) _action(FinanceHomeStep s) {
    switch (s.key) {
      case 'charge':
        return (s.status == 'setup' ? 'Tanım ekle' : 'Borç yaz', () => onOpen(FinanceHomeTab.definitions));
      case 'notify':
        return ('Duyuru yaz', onOpenAnnouncements);
      case 'match':
        return (s.status == 'setup' ? 'Hesap ekle' : 'Eşle', () => onOpen(FinanceHomeTab.cash));
      case 'expense':
        return ('Gider ekle', () => onOpen(FinanceHomeTab.expenses));
      default:
        return ('Rapor al', () => onOpen(FinanceHomeTab.reports));
    }
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final firstTodo = steps.indexWhere((s) => s.status != 'done' && s.status != 'unavailable');
    return AppCard(
      key: const ValueKey<String>('month_cycle'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(header: true, child: Text('Aylık döngü', style: th.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
          for (final (i, s) in steps.indexed)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.md),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      container: true,
                      label: '${i + 1}. ${_titles[s.key] ?? s.key}: ${_statusText(s)}',
                      excludeSemantics: true,
                      child: Row(
                        children: [
                          Text('${i + 1}. ', style: th.bodyMedium),
                          Expanded(child: Text(_titles[s.key] ?? s.key, style: th.bodyMedium?.copyWith(fontWeight: FontWeight.w700))),
                          StatusDot(label: _statusText(s), tone: _tone(s.status), maxLines: 2),
                        ],
                      ),
                    ),
                  ),
                  if (i == firstTodo && _action(s).$2 != null) ...[
                    const SizedBox(width: AppSpace.sm),
                    FilledButton(
                      key: ValueKey<String>('month_step_action_${s.key}'),
                      style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
                      onPressed: _action(s).$2,
                      child: Text(_action(s).$1),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Recent extends StatelessWidget {
  const _Recent({required this.items});

  final List<FinanceHomeMovement> items;

  static String _kindText(String kind) {
    switch (kind) {
      case 'payment':
        return 'Tahsilat';
      case 'payment_void':
        return 'Tahsilat iptali';
      case 'expense':
        return 'Gider';
      case 'expense_void':
        return 'Gider iptali';
      default:
        return 'Hareket';
    }
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    return AppCard(
      key: const ValueKey<String>('month_recent'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(header: true, child: Text('Son hareketler', style: th.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
          for (final m in items)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.md),
              child: Semantics(
                container: true,
                excludeSemantics: true,
                label: '${_kindText(m.kind)}, ${m.label}, ${m.amountMinor >= 0 ? '+' : '-'}${formatMinor(m.amountMinor.abs())}',
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${_kindText(m.kind)} · ${m.label}', style: th.bodyMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                          Text(m.date, style: th.bodySmall?.copyWith(color: p.textSecondary)),
                        ],
                      ),
                    ),
                    Text(
                      '${m.amountMinor >= 0 ? '+' : '-'}${formatMinor(m.amountMinor.abs())}',
                      style: th.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
