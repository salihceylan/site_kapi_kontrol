import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/finance.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_parts.dart';

/// İki hesap (İP-1A, karar G12) ortak arayüz parçaları: hesap sekmeleri ve hesap seçimi (kasa seçimi: finance_fund_parts.dart).
///
/// Her dairenin ayrı bir "Ev sahibi hesabı" ve "Kiracı hesabı" vardır; bakiyeler birbirine karışmaz. Seçimler çiplerle
/// yapılır (uygulamadaki diğer sekme / seçim gruplarıyla aynı): seçili çip ekran okuyucuda "seçili" okunur, her çip en az
/// 48 dp dokunma hedefidir.

/// Sekme / seçim sırası: önce kiracı hesabı, sonra ev sahibi hesabı ([Kiracı hesabı] [Ev sahibi hesabı]).
const List<AccountParty> kAccountPartyOrder = <AccountParty>[AccountParty.tenant, AccountParty.owner];

IconData accountPartyIcon(AccountParty party) =>
    party == AccountParty.tenant ? Icons.key_rounded : Icons.home_work_rounded;

/// Ekstre penceresinin hesap sekmeleri. [totals] verilirse çipte hesabın bakiyesi de yazılır ("Kiracı hesabı • Borç 1.680,00 ₺").
class AccountPartyTabs extends StatelessWidget {
  const AccountPartyTabs({
    super.key,
    required this.selected,
    required this.onSelected,
    this.enabled = true,
    this.totals = const <AccountParty, AccountTotals?>{},
    this.keyPrefix = 'finance_account_tab',
  });

  final AccountParty selected;
  final ValueChanged<AccountParty> onSelected;
  final bool enabled;
  final Map<AccountParty, AccountTotals?> totals;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpace.sm,
      runSpacing: AppSpace.sm,
      children: [
        for (final party in kAccountPartyOrder)
          ChoiceChip(
            key: ValueKey<String>('${keyPrefix}_${party.apiValue}'),
            avatar: Icon(accountPartyIcon(party), size: 18),
            label: Text(_label(party)),
            selected: selected == party,
            onSelected: enabled ? (_) => onSelected(party) : null,
          ),
      ],
    );
  }

  String _label(AccountParty party) {
    final total = totals[party];
    return total == null ? party.label : '${party.label} • ${describeBalance(total.balanceMinor).badgeText}';
  }
}

/// Hesap seçimi: tahsilat penceresinde "Daire hesabı" ([allowAll] false) ya da raporlarda hesap süzgeci ([allowAll] true:
/// "Tüm hesaplar" = null). [note] seçimin altında açıklama olarak yazılır.
class AccountPartyChoice extends StatelessWidget {
  const AccountPartyChoice({
    super.key,
    required this.selected,
    required this.onSelected,
    this.enabled = true,
    this.title = 'Daire hesabı',
    this.note,
    this.allowAll = false,
    this.keyPrefix = 'finance_account_party',
  });

  final AccountParty? selected;
  final ValueChanged<AccountParty?> onSelected;
  final bool enabled;
  final String title;
  final String? note;
  final bool allowAll;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FinanceGroupTitle(title),
        const SizedBox(height: AppSpace.sm),
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          children: [
            if (allowAll)
              ChoiceChip(
                key: ValueKey<String>('${keyPrefix}_all'),
                label: const Text('Tüm hesaplar'),
                selected: selected == null,
                onSelected: enabled ? (_) => onSelected(null) : null,
              ),
            for (final party in kAccountPartyOrder)
              ChoiceChip(
                key: ValueKey<String>('${keyPrefix}_${party.apiValue}'),
                avatar: Icon(accountPartyIcon(party), size: 18),
                label: Text(party.label),
                selected: selected == party,
                onSelected: enabled ? (_) => onSelected(party) : null,
              ),
          ],
        ),
        if (note != null) ...[
          const SizedBox(height: AppSpace.xs),
          Text(note!, style: th.bodySmall?.copyWith(color: p.textSecondary)),
        ],
      ],
    );
  }
}
