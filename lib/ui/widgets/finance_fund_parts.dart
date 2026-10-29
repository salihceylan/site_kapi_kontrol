import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/finance_funds.dart';
import 'package:site_kapi_kontrol/models/fund_models.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/large_dialog_parts.dart';
import 'package:site_kapi_kontrol/ui/helpers/date_input.dart';
import 'package:site_kapi_kontrol/ui/helpers/fund_text.dart';
import 'package:site_kapi_kontrol/ui/helpers/money.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_parts.dart';

/// İki kasa (İşletme Projesi (Aidat) Hesabı / Yatırım ve Demirbaş (Fon) Hesabı) ortak arayüz parçaları
/// (docs/PLATFORM_FINANS_KASALAR.md §6).
///
/// Kurallar:
/// - Kasa adları TEK kaynaktan gelir ([FinanceFund.label] / [FinanceFund.shortLabel]); formlarda ve kart başlıklarında TAM
///   ad, rozet ve dar listelerde kısa ad yazılır. Ev sahibi / kiracı daire hesaplarıyla ve nakit / banka hesaplarıyla
///   karışmasın diye "Hesap" sözcüğü yalnız kasa adının içinde geçer.
/// - Para tutarı ekran okuyucuya "bin iki yüz elli lira" diye okunur; kart tek birleşik etiketle okunur.
/// - Metinler sarar (kırpılmaz); seçim satırları en az 48 dp yüksekliktedir ve büyük yazıda büyür.

/// Kasa rozeti (kısa ad). Liste satırlarında ve kartlarda kullanılır; renk tek başına anlam taşımaz (simge + metin).
class FundPill extends StatelessWidget {
  const FundPill(this.fund, {super.key, this.prefix});

  final FinanceFund fund;

  /// Rozet metninin başına gelen sözcük ("Yalnız").
  final String? prefix;

  @override
  Widget build(BuildContext context) => DialogMetaPill(
    prefix == null ? fund.shortLabel : '$prefix ${fund.shortLabel}',
    tone: AppTone.info,
    icon: fundIcon(fund),
  );
}

/// "Kasa" seçimi (tanım, ek borç, tahsilat, gider ve kategori formları). Her seçenek bir satırdır: simge + TAM kasa adı +
/// açıklama; seçili satır ekran okuyucuda "seçili" okunur.
///
/// - [allowAuto] true iken ilk seçenek "Otomatik (en eski vade önce)" olur ve [selected] null o seçeneği gösterir
///   (tahsilat formu); false iken yalnız iki kasa vardır ve null seçili seçenek yoktur demektir.
/// - [noteFor] seçenek açıklamasını belirler (varsayılan: borcu kimin ödediği — "dairede oturan öder (kiracı varsa kiracı)"
///   / "malik öder").
///
/// Taşma: satır metni `Expanded` içinde sarar (kırpılmaz); üst öğe sınırlı genişlikte olmalıdır.
class FundChoice extends StatelessWidget {
  const FundChoice({
    super.key,
    required this.selected,
    required this.onSelected,
    this.enabled = true,
    this.title = 'Kasa',
    this.allowAuto = false,
    this.autoLabel = kFundAutoName,
    this.autoNote = 'borçlara en eski vadeden başlayarak dağıtılır',
    this.noteFor,
    this.footer,
    this.keyPrefix = 'finance_fund',
    this.errorText,
  });

  final FinanceFund? selected;
  final ValueChanged<FinanceFund?> onSelected;
  final bool enabled;
  final String title;
  final bool allowAuto;

  /// "Seçilmedi" satırının adı (varsayılan: "Otomatik (en eski vade önce)"); borçsuz hesapta "Hesap seçmeden" gibi daha doğru bir ad verilir.
  final String autoLabel;
  final String autoNote;
  final String Function(FinanceFund fund)? noteFor;

  /// Seçeneklerin altında yazılan açıklama (ör. "Seçim yalnız sonraki borçlandırmaları etkiler.").
  final String? footer;
  final String keyPrefix;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FinanceGroupTitle(title),
        const SizedBox(height: AppSpace.xs),
        if (allowAuto)
          _FundOptionRow(
            key: ValueKey<String>('${keyPrefix}_auto'),
            label: autoLabel,
            note: autoNote,
            icon: Icons.auto_awesome_rounded,
            selected: selected == null,
            enabled: enabled,
            onTap: () => onSelected(null),
          ),
        for (final fund in FinanceFund.values)
          _FundOptionRow(
            key: ValueKey<String>('${keyPrefix}_${fund.apiValue}'),
            label: fund.label,
            note: noteFor == null ? fund.payerNote : noteFor!(fund),
            icon: fundIcon(fund),
            selected: selected == fund,
            enabled: enabled,
            onTap: () => onSelected(fund),
          ),
        if (errorText != null) ...[
          const SizedBox(height: AppSpace.xs),
          Text(errorText!, style: th.bodySmall?.copyWith(color: AppTone.danger.ink(p))),
        ],
        if (footer != null) ...[
          const SizedBox(height: AppSpace.xs),
          Text(footer!, key: ValueKey<String>('${keyPrefix}_note'), style: th.bodySmall?.copyWith(color: p.textSecondary)),
        ],
      ],
    );
  }
}

class _FundOptionRow extends StatelessWidget {
  const _FundOptionRow({
    super.key,
    required this.label,
    required this.note,
    required this.icon,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final String note;
  final IconData icon;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final ink = AppTone.primary.ink(p);
    final base = th.bodyMedium?.copyWith(color: enabled ? p.text : p.textMuted);
    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      onTap: enabled ? onTap : null,
      // Not tutar taşıyabilir (aktarımda "bakiye 13.000,00 ₺"): ekran okuyucuya "on üç bin lira" diye okunur.
      label: spokenMoneyText('$label, $note'),
      child: ExcludeSemantics(
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(
                      selected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                      size: 22,
                      color: selected ? ink : (enabled ? p.textSecondary : p.textMuted),
                    ),
                  ),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: label,
                            style: base?.copyWith(fontWeight: selected ? FontWeight.w800 : FontWeight.w600),
                          ),
                          TextSpan(text: ' — $note', style: base?.copyWith(color: enabled ? p.textSecondary : p.textMuted)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bir daire hesabının kasa bazında durumu (daire ekstresi ve sakin "Borcum" ekranı): her kasa için açık borç, vadesi geçen
/// ve o kasaya kısıtlı avans; sıfır olmayan toplam avans ayrıca yazılır.
///
/// [hideZero] true iken (sakin ekranı) üç tutarı da sıfır olan kasa GÖSTERİLMEZ (kiracı yalnız Aidat Hesabı'nı, kiracılı
/// dairede malik yalnız Fon Hesabı'nı görür); hiçbir şey gösterilecek değilse parça hiç çizilmez. Yönetici ekstresi iki
/// kasayı da yazar.
class FundBreakdownPanel extends StatelessWidget {
  const FundBreakdownPanel({
    super.key,
    required this.breakdown,
    this.advanceMinor,
    this.hideZero = false,
    this.title = 'Kasalara göre durum',
    this.keyPrefix = 'fund_breakdown',
  });

  final FundBreakdown breakdown;

  /// Toplam avans (kasaya kısıtlı olanlar ve kısıtsız dahil); null / 0 ise yazılmaz.
  final int? advanceMinor;
  final bool hideZero;
  final String title;
  final String keyPrefix;

  /// Gösterilecek kasalar: [hideZero] iken sıfır olmayanlar, aksi halde ikisi de.
  static List<FinanceFund> shownFunds(FundBreakdown breakdown, {required bool hideZero}) => <FinanceFund>[
    for (final fund in FinanceFund.values)
      if (!hideZero || !breakdown.of(fund).isZero) fund,
  ];

  /// Parça bir şey çizecek mi? (Çağıran, boşken ardındaki boşluğu da eklemesin diye sorar.)
  static bool hasContent(FundBreakdown breakdown, int? advanceMinor, {required bool hideZero}) =>
      shownFunds(breakdown, hideZero: hideZero).isNotEmpty || (advanceMinor ?? 0) > 0;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final shown = shownFunds(breakdown, hideZero: hideZero);
    final advance = advanceMinor ?? 0;
    if (shown.isEmpty && advance <= 0) return const SizedBox.shrink();

    final semantic = StringBuffer('$title. ');
    for (final fund in shown) {
      semantic.write('${fund.label}: ${_semanticOf(breakdown.of(fund))} ');
    }
    if (advance > 0) semantic.write('Toplam avans: ${moneySemanticLabel(advance)}.');

    return Column(
      key: ValueKey<String>(keyPrefix),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          container: true,
          label: semantic.toString().trim(),
          child: ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: th.titleSmall),
                for (final fund in shown) ...[
                  const SizedBox(height: AppSpace.sm),
                  _row(context, fund, breakdown.of(fund)),
                ],
                if (advance > 0) ...[
                  const SizedBox(height: AppSpace.sm),
                  Text(
                    'Toplam avans: ${formatMinor(advance)}',
                    key: ValueKey<String>('${keyPrefix}_advance'),
                    style: th.bodyMedium?.copyWith(color: AppTone.success.ink(p), fontWeight: FontWeight.w700),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  static String _semanticOf(FundAmounts a) {
    final text = StringBuffer(a.balanceMinor > 0 ? 'Açık borç ${moneySemanticLabel(a.balanceMinor)}.' : 'Borç yok.');
    if (a.overdueMinor > 0) text.write(' Vadesi geçen ${moneySemanticLabel(a.overdueMinor)}.');
    if (a.advanceMinor > 0) text.write(' Avans ${moneySemanticLabel(a.advanceMinor)}.');
    return text.toString();
  }

  Widget _row(BuildContext context, FinanceFund fund, FundAmounts a) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    return Column(
      key: ValueKey<String>('${keyPrefix}_${fund.apiValue}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(fundIcon(fund), size: 18, color: p.textSecondary),
            ),
            const SizedBox(width: AppSpace.sm),
            Expanded(child: Text(fund.label, style: th.bodyMedium?.copyWith(fontWeight: FontWeight.w700))),
          ],
        ),
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                a.balanceMinor > 0 ? 'Açık borç: ${formatMinor(a.balanceMinor)}' : 'Borç yok',
                key: ValueKey<String>('${keyPrefix}_${fund.apiValue}_balance'),
                style: th.bodyMedium,
              ),
              if (a.overdueMinor > 0)
                Text(
                  'Vadesi geçen: ${formatMinor(a.overdueMinor)}',
                  key: ValueKey<String>('${keyPrefix}_${fund.apiValue}_overdue'),
                  style: th.bodyMedium?.copyWith(color: AppTone.warning.ink(p), fontWeight: FontWeight.w700),
                ),
              if (a.advanceMinor > 0)
                Text(
                  'Avans: ${formatMinor(a.advanceMinor)}',
                  key: ValueKey<String>('${keyPrefix}_${fund.apiValue}_advance'),
                  style: th.bodyMedium?.copyWith(color: AppTone.success.ink(p), fontWeight: FontWeight.w700),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Kasa dökümü satırı: tür rozeti, tarih, İŞARETLİ tutar (+ giriş, − çıkış) ve kaynak (daire, kategori, hesap, açıklama).
///
/// Tahsilatta yalnız daire etiketi vardır (kişi adı yok). Kart tek birleşik etiketle okunur; tutar okunuşla verilir.
class FundMovementTile extends StatelessWidget {
  const FundMovementTile({super.key, required this.movement});

  final FundMovement movement;

  static (AppTone, IconData) _style(FundMovementType type) => switch (type) {
    FundMovementType.collection => (AppTone.success, Icons.payments_rounded),
    FundMovementType.expense => (AppTone.danger, Icons.shopping_bag_rounded),
    FundMovementType.transferIn => (AppTone.info, Icons.call_received_rounded),
    FundMovementType.transferOut => (AppTone.info, Icons.call_made_rounded),
    FundMovementType.adjustment => (AppTone.warning, Icons.tune_rounded),
    FundMovementType.opening => (AppTone.neutral, Icons.flag_rounded),
    FundMovementType.unknown => (AppTone.neutral, Icons.help_outline_rounded),
  };

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final m = movement;
    final (tone, icon) = _style(m.type);
    // Aynı metin iki kez yazılmasın (kategori ile açıklama çoğu zaman aynıdır).
    final details = <String>[];
    for (final text in <String?>[m.apartmentLabel, m.category, m.accountName, m.label]) {
      final t = text?.trim();
      if (t != null && t.isNotEmpty && !details.contains(t)) details.add(t);
    }
    final semantic = StringBuffer('${m.type.label}. ${formatCrmDate(m.date)}. ');
    semantic.write('${m.amountMinor < 0 ? 'Çıkış' : 'Giriş'}: ${moneySemanticLabel(m.amountMinor.abs())}.');
    for (final d in details) {
      semantic.write(' $d.');
    }
    return DialogPanel(
      key: ValueKey<String>('fund_movement_${m.key}'),
      child: Semantics(
        container: true,
        label: semantic.toString(),
        child: ExcludeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.xs,
                children: [DialogMetaPill(m.type.label, tone: tone, icon: icon)],
              ),
              const SizedBox(height: AppSpace.sm),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: Text(formatCrmDate(m.date), style: th.titleSmall)),
                  const SizedBox(width: AppSpace.sm),
                  Flexible(
                    child: Text(
                      formatSignedMinor(m.amountMinor),
                      textAlign: TextAlign.end,
                      style: th.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
              for (final d in details) Text(d, style: th.bodyMedium?.copyWith(color: p.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }
}
