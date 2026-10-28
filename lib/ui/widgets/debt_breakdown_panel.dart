import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/finance.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/large_dialog_parts.dart';
import 'package:site_kapi_kontrol/ui/helpers/date_input.dart';
import 'package:site_kapi_kontrol/ui/helpers/fund_text.dart';
import 'package:site_kapi_kontrol/ui/helpers/money.dart';

/// Sakin "Borcum" kartındaki KALEM DÖKÜMÜ (P2-1): ödenmemiş her borç kaleminin KAYNAĞI (dönem, tür, hesap) ve varsa dayanağı
/// (Karar Defteri numarası / gerekçe), kalan tutarıyla. Varsayılan kapalı; "Borç kalemleri" düğmesiyle açılır (detay açılımı).
///
/// - Kalan tutarlar sunucunun bakiyeyi hesapladığı AYNI mahsuptan gelir (ödemeler en eski vadeli borçtan başlayarak düşer); ekran
///   kendi başına hesap yapmaz.
/// - Hiçbir yazma eylemi yoktur; yönetici notu / kaydeden adı gösterilmez (sunucu da göndermez).
/// - Kalem yoksa (borç yok ya da eski sunucu) hiçbir şey çizilmez ([hasContent]).
class DebtBreakdownPanel extends StatefulWidget {
  const DebtBreakdownPanel({super.key, required this.breakdown, this.keyPrefix = 'debt_breakdown', this.initiallyExpanded = false});

  final DebtBreakdown breakdown;

  /// Anahtar öneki (aynı ekranda birden çok kart/hesap için ayırt edici).
  final String keyPrefix;
  final bool initiallyExpanded;

  /// Çizilecek kalem var mı? (Çağıran, boşken ardındaki boşluğu da eklemesin diye sorar.)
  static bool hasContent(DebtBreakdown? breakdown) => breakdown != null && breakdown.items.isNotEmpty;

  @override
  State<DebtBreakdownPanel> createState() => _DebtBreakdownPanelState();
}

class _DebtBreakdownPanelState extends State<DebtBreakdownPanel> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final items = widget.breakdown.items;
    if (items.isEmpty) return const SizedBox.shrink();
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final prefix = widget.keyPrefix;
    return Column(
      key: ValueKey<String>(prefix),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: PrimaryActionButton(
            key: ValueKey<String>('${prefix}_toggle'),
            label: _expanded ? 'Borç kalemlerini gizle' : 'Borç kalemleri (${items.length})',
            icon: _expanded ? Icons.expand_less_rounded : Icons.list_alt_rounded,
            variant: AppButtonVariant.tonal,
            expand: false,
            onPressed: () => setState(() => _expanded = !_expanded),
          ),
        ),
        if (_expanded) ...[
          const SizedBox(height: AppSpace.sm),
          Text(
            'Ödemeler vadesi en eski borçtan başlayarak mahsup edilir; her kalemin kalan tutarı buna göredir.',
            key: ValueKey<String>('${prefix}_note'),
            style: th.bodySmall?.copyWith(color: p.textSecondary),
          ),
          const SizedBox(height: AppSpace.sm),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.sm),
              child: _ItemTile(key: ValueKey<String>('${prefix}_item_${item.entryId}'), item: item),
            ),
          if (widget.breakdown.truncated)
            Text(
              'Çok sayıda kalem olduğundan en eski vadeli ${items.length} kalem gösterilir.',
              key: ValueKey<String>('${prefix}_truncated'),
              style: th.bodySmall?.copyWith(color: p.textSecondary),
            ),
        ],
      ],
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({super.key, required this.item});

  final DebtBreakdownItem item;

  /// "Ekim 2026 • Ek borç • Fon Hesabı"
  static String _sourceText(DebtBreakdownItem item) {
    final parts = <String>[
      if (item.period != null) item.period!.label,
      item.type.label,
      if (item.fund != null) item.fund!.shortLabel,
    ];
    return parts.join(' • ');
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final secondary = th.bodySmall?.copyWith(color: p.textSecondary);
    final source = _sourceText(item);
    final partial = item.paidMinor > 0;
    final due = item.dueDate == null
        ? null
        : (item.overdue ? 'Vadesi geçti: ${formatCrmDate(item.dueDate)}' : 'Vade: ${formatCrmDate(item.dueDate)}');
    final basis = item.decision;
    final amountLine = partial
        ? 'Tutar ${formatMinor(item.amountMinor)} • Ödenen ${formatMinor(item.paidMinor)}'
        : 'Tutar ${formatMinor(item.amountMinor)}';

    final semantic = StringBuffer('${item.title}. $source. ');
    semantic.write('Kalan: ${moneySemanticLabel(item.remainingMinor)}. ');
    if (partial) semantic.write('Ödenen: ${moneySemanticLabel(item.paidMinor)}. ');
    if (due != null) semantic.write('$due. ');
    if (basis != null) semantic.write('Dayanak: ${basis.summary}.');

    return DialogPanel(
      tone: item.overdue ? AppTone.warning : null,
      child: Semantics(
        container: true,
        label: semantic.toString().trim(),
        child: ExcludeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (item.fund != null) ...[
                    Icon(fundIcon(item.fund!), size: 18, color: p.textSecondary),
                    const SizedBox(width: AppSpace.xs),
                  ],
                  Expanded(child: Text(item.title, style: th.titleSmall)),
                  const SizedBox(width: AppSpace.sm),
                  Flexible(
                    child: Text(
                      formatMinor(item.remainingMinor),
                      key: ValueKey<String>('debt_item_remaining_${item.entryId}'),
                      textAlign: TextAlign.end,
                      style: th.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
              if (source.isNotEmpty) Text(source, key: ValueKey<String>('debt_item_source_${item.entryId}'), style: secondary),
              Text(amountLine, style: secondary),
              if (due != null)
                Text(
                  due,
                  style: secondary?.copyWith(
                    color: item.overdue ? AppTone.warning.ink(p) : p.textSecondary,
                    fontWeight: item.overdue ? FontWeight.w700 : null,
                  ),
                ),
              if (basis != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpace.xs),
                  child: Text(
                    'Dayanak: ${basis.summary}',
                    key: ValueKey<String>('debt_item_basis_${item.entryId}'),
                    style: th.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
