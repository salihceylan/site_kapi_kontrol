import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/finance.dart';
import 'package:site_kapi_kontrol/models/person_record.dart' show crmApartmentTitle;
import 'package:site_kapi_kontrol/models/residency_relation.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/dialogs/large_dialog_parts.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/date_input.dart';
import 'package:site_kapi_kontrol/ui/helpers/istanbul_time.dart';
import 'package:site_kapi_kontrol/ui/helpers/money.dart';
import 'package:site_kapi_kontrol/ui/widgets/crm_parts.dart' show CrmFormError;
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

/// Aidat ve Finans ekranlarının ortak görünüm parçaları (Platform Faz 4a).
///
/// Kurallar (önceki fazların derslerinden):
/// - Borç / alacak YALNIZ renkle belirtilmez: simge + metin ("Borç", "Alacak", "Borç yok") birlikte kullanılır.
/// - Para metni ekran okuyucuya sayı yığını olarak değil "bin iki yüz elli lira" diye okunur
///   ([moneySemanticLabel]); görsel metin dışlanır, kart tek birleşik etiketle okunur (iki kez okunmaz).
/// - Metinler sarar (kırpılmaz); çipler [DialogMetaPill] ile sarar.

/// Bakiyenin yönü.
enum BalanceDirection { debt, credit, zero }

/// Bir bakiyenin görsel ve sözel tanımı. [minor] > 0 borç, < 0 alacak, 0 borç yok.
@immutable
class BalanceDescription {
  const BalanceDescription({
    required this.direction,
    required this.title,
    required this.amountText,
    required this.tone,
    required this.icon,
    required this.semanticLabel,
  });

  final BalanceDirection direction;

  /// "Borç", "Alacak" ya da "Borç yok".
  final String title;

  /// "1.250,00 ₺" (mutlak değer); sıfırda boş.
  final String amountText;
  final AppTone tone;
  final IconData icon;

  /// Ekran okuyucu: "Borç: bin iki yüz elli lira".
  final String semanticLabel;

  /// Rozet metni: "Borç 1.250,00 ₺" / "Alacak 50,00 ₺" / "Borç yok".
  String get badgeText => amountText.isEmpty ? title : '$title $amountText';
}

BalanceDescription describeBalance(int minor) {
  if (minor > 0) {
    return BalanceDescription(
      direction: BalanceDirection.debt,
      title: 'Borç',
      amountText: formatMinor(minor),
      tone: AppTone.danger,
      icon: Icons.arrow_circle_up_rounded,
      semanticLabel: 'Borç: ${moneySemanticLabel(minor)}',
    );
  }
  if (minor < 0) {
    return BalanceDescription(
      direction: BalanceDirection.credit,
      title: 'Alacak',
      amountText: formatMinor(-minor),
      tone: AppTone.success,
      icon: Icons.arrow_circle_down_rounded,
      semanticLabel: 'Alacak: ${moneySemanticLabel(-minor)}',
    );
  }
  return const BalanceDescription(
    direction: BalanceDirection.zero,
    title: 'Borç yok',
    amountText: '',
    tone: AppTone.neutral,
    icon: Icons.check_circle_outline_rounded,
    semanticLabel: 'Borç yok',
  );
}

/// Para metni: görsel "1.250,00 ₺", ekran okuyucuya "bin iki yüz elli lira". [semanticPrefix] ("Toplam borç")
/// okunuşun başına eklenir.
class MoneyText extends StatelessWidget {
  const MoneyText(
    this.minor, {
    super.key,
    this.style,
    this.signed = false,
    this.semanticPrefix,
    this.textAlign,
  });

  final int minor;
  final TextStyle? style;
  final bool signed;
  final String? semanticPrefix;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final base = style ?? Theme.of(context).textTheme.titleMedium;
    final prefix = semanticPrefix == null ? '' : '$semanticPrefix: ';
    return Semantics(
      label: '$prefix${moneySemanticLabel(minor)}',
      child: ExcludeSemantics(
        child: Text(
          signed ? formatSignedMinor(minor) : formatMinor(minor),
          textAlign: textAlign,
          style: base,
        ),
      ),
    );
  }
}

/// Mali bir iletiyi SnackBar olarak gösterir; ekran okuyucu tutarları "bin iki yüz elli lira" diye okur
/// ([spokenMoneyText]), görsel metin değişmez.
void showFinanceSnack(
  BuildContext context,
  String message, {
  AppSnackKind kind = AppSnackKind.success,
}) {
  final spoken = spokenMoneyText(message);
  AppSnack.show(
    context,
    message,
    kind: kind,
    semanticsLabel: spoken == message ? null : spoken,
  );
}

/// "A Blok / Daire 5" gibi tek metin (boş etikette "-").
String financeApartmentTitle(String? blockName, String label) =>
    crmApartmentTitle(blockName, label);

/// Takvim günü (DATE) ekranda "05.03.2026"; yoksa "-".
String financeDate(DateTime? day) => formatCrmDate(day);

/// Aylık tanımın vade günü metni: "Her ayın 15'i".
String dueDayText(int? day) => day == null ? 'Vade günü belirtilmemiş' : "Her ayın $day'i";

/// Dönem aralığı: "Ocak 2026 - süresiz" / "Ocak 2026 - Aralık 2026".
String periodRangeText(FinancePeriod? start, FinancePeriod? end) {
  if (start == null && end == null) return 'Dönem belirtilmemiş';
  final from = start?.label ?? '-';
  final to = end?.label ?? 'süresiz';
  return '$from - $to';
}

/// Tanımın tutar özeti: sabit "Daire başı 500,00 ₺", eşit / arsa payı / m² "Toplam 50.000,00 ₺", kategori
/// "Kategoriye göre (3 kategori)".
String definitionAmountText(FeeDefinition d) {
  switch (d.distribution) {
    case FeeDistribution.category:
      final count = d.categoryAmounts.length;
      return count == 0 ? 'Kategoriye göre' : 'Kategoriye göre ($count kategori)';
    case FeeDistribution.fixed:
      return d.amountMinor == null ? 'Tutar okunamadı' : 'Daire başı ${formatMinor(d.amountMinor!)}';
    case FeeDistribution.equal:
    case FeeDistribution.landShare:
    case FeeDistribution.area:
      return d.amountMinor == null ? 'Tutar okunamadı' : 'Toplam ${formatMinor(d.amountMinor!)}';
    case FeeDistribution.unknown:
      return 'Tutar bilinmiyor';
  }
}

// --- Özet kartı -------------------------------------------------------------------------------

/// Mali özet kartı (`GET .../summary`): toplam borç, toplam alacak, borçlu daire sayısı ve açık dönemin
/// borçlandırılan / tahsil edilen tutarı. Metrikler dar ekranda tek sütun, genişte iki sütundur.
class FinanceSummaryCard extends StatelessWidget {
  const FinanceSummaryCard({super.key, required this.summary});

  final FinanceSummary summary;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final period = summary.openPeriod;
    final metrics = <_Metric>[
      _Metric(
        'Toplam borç',
        summary.debtTotalMinor,
        Icons.arrow_circle_up_rounded,
        AppTone.danger,
      ),
      _Metric(
        'Toplam alacak',
        summary.creditTotalMinor,
        Icons.arrow_circle_down_rounded,
        AppTone.success,
      ),
      if (summary.chargedMinor != null)
        _Metric(
          period == null ? 'Bu dönem borçlandırılan' : '${period.label} borçlandırılan',
          summary.chargedMinor!,
          Icons.receipt_long_rounded,
          AppTone.info,
        ),
      if (summary.collectedMinor != null)
        _Metric(
          period == null ? 'Bu dönem tahsil edilen' : '${period.label} tahsil edilen',
          summary.collectedMinor!,
          Icons.payments_rounded,
          AppTone.success,
        ),
    ];
    return AppCard(
      key: const ValueKey<String>('finance_summary_card'),
      padding: listCardPadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('Mali durum', style: th.titleMedium)),
            ],
          ),
          if (period != null) ...[
            const SizedBox(height: AppSpace.xs),
            Text('Açık dönem: ${period.label}', style: th.bodySmall?.copyWith(color: p.textSecondary)),
          ],
          const SizedBox(height: AppSpace.md),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 420 ? 2 : 1;
              final width = (constraints.maxWidth - AppSpace.md * (columns - 1)) / columns;
              return Wrap(
                spacing: AppSpace.md,
                runSpacing: AppSpace.md,
                children: [
                  for (final metric in metrics)
                    SizedBox(width: width, child: _MetricTile(metric)),
                  SizedBox(
                    width: width,
                    child: _CountTile(
                      label: 'Borçlu daire',
                      count: summary.debtorCount,
                      icon: Icons.apartment_rounded,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Metric {
  const _Metric(this.label, this.minor, this.icon, this.tone);

  final String label;
  final int minor;
  final IconData icon;
  final AppTone tone;
}

class _MetricTile extends StatelessWidget {
  const _MetricTile(this.metric);

  final _Metric metric;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    // Etiket + tutar TEK birleşik etiketle okunur (etiket iki kez okunmasın).
    return Semantics(
      container: true,
      label: '${metric.label}: ${moneySemanticLabel(metric.minor)}',
      child: ExcludeSemantics(
        child: DialogPanel(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(metric.icon, size: 22, color: metric.tone.ink(p)),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(metric.label, style: th.bodySmall?.copyWith(color: p.textSecondary)),
                    Text(
                      formatMinor(metric.minor),
                      style: th.titleMedium?.copyWith(fontWeight: FontWeight.w800),
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

class _CountTile extends StatelessWidget {
  const _CountTile({required this.label, required this.count, required this.icon});

  final String label;
  final int count;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    return DialogPanel(
      child: Semantics(
        label: '$label: $count',
        container: true,
        child: ExcludeSemantics(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 22, color: AppTone.primary.ink(p)),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: th.bodySmall?.copyWith(color: p.textSecondary)),
                    Text('$count', style: th.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
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

// --- Daire bakiye kartı -----------------------------------------------------------------------

/// Daire bakiye listesi kartı (Daireler sekmesi): daire etiketi, malik / kiracı adı, bakiye rozeti ve
/// vadesi geçmiş tutar. Dokununca ekstre açılır ([onTap]).
class BalanceRowCard extends StatelessWidget {
  const BalanceRowCard({super.key, required this.row, required this.onTap});

  final BalanceRow row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final title = financeApartmentTitle(row.blockName, row.label);
    final balance = describeBalance(row.balanceMinor);
    final overdue = row.overdueMinor;
    final hasOverdue = overdue != null && overdue > 0;
    final names = <String>[
      if (row.ownerName != null) 'Malik: ${row.ownerName}',
      if (row.tenantName != null) 'Kiracı: ${row.tenantName}',
    ];
    // İP-1A: kiracı hesabında hareket varsa iki hesap AYRI gösterilir (toplam bakiye yanıltır: bir hesabın alacağı diğerinin
    // borcunu kapatmaz). Kiracı hesabı boşsa eski tek rozet (ev sahibi hesabı = toplam) kalır.
    final accounts = <(AccountParty, AccountTotals)>[
      if (row.hasTenantBalance && row.ownerAccount != null && row.tenantAccount != null) ...[
        (AccountParty.tenant, row.tenantAccount!),
        (AccountParty.owner, row.ownerAccount!),
      ],
    ];
    final semantic = StringBuffer('Daire: $title.');
    if (accounts.isEmpty) {
      semantic.write(' ${balance.semanticLabel}.');
    } else {
      for (final (party, totals) in accounts) {
        semantic.write(' ${party.label}: ${describeBalance(totals.balanceMinor).semanticLabel}.');
      }
    }
    if (hasOverdue) semantic.write(' Vadesi geçen: ${moneySemanticLabel(overdue)}.');
    for (final name in names) {
      semantic.write(' $name.');
    }
    return AppCard(
      padding: listCardPadding(context),
      onTap: onTap,
      semanticLabel: semantic.toString(),
      child: ExcludeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const IconTile(icon: Icons.apartment_rounded, gap: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: th.titleMedium),
                  for (final name in names)
                    Text(name, style: th.bodyMedium?.copyWith(color: p.textSecondary)),
                  const SizedBox(height: AppSpace.sm),
                  Wrap(
                    spacing: AppSpace.sm,
                    runSpacing: AppSpace.xs,
                    children: [
                      if (accounts.isEmpty)
                        DialogMetaPill(balance.badgeText, tone: balance.tone, icon: balance.icon)
                      else
                        for (final (party, totals) in accounts)
                          DialogMetaPill(
                            '${party.label}: ${describeBalance(totals.balanceMinor).badgeText}',
                            key: ValueKey<String>('balance_row_${row.apartmentId}_${party.apiValue}'),
                            tone: describeBalance(totals.balanceMinor).tone,
                            icon: describeBalance(totals.balanceMinor).icon,
                          ),
                      if (hasOverdue)
                        DialogMetaPill(
                          'Vadesi geçen ${formatMinor(overdue)}',
                          tone: AppTone.warning,
                          icon: Icons.schedule_rounded,
                        ),
                    ],
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

// --- Defter satırı ----------------------------------------------------------------------------

/// Hareket (defter satırı) görünümü: tür rozeti, tarih, işaretli tutar, açıklama, ters kayıt işareti.
///
/// - Borç (+): "Borca eklendi"; tahsilat (-): "Borçtan düşüldü"; ters kayıt: kendi işaretine göre.
/// - İptal edilmiş kayıt: tutar üstü çizili + "İptal edildi" rozeti. Ters kayıt: "Ters kayıt" rozeti ve neden.
/// - [showActor] true iken kaydı yapan kişi gösterilir (yalnız yönetici; sakin ucunda zaten gelmez).
/// - [showNotes] true iken yönetici notları (tahsilat açıklaması, iptal nedeni) çizilir. VARSAYILAN false:
///   sakin ve kurul ekranları, sunucu göndermiş olsa bile bu notları göstermez.
/// - [related]: aynı ekstredeki kayıtlar (kimliğe göre). Ters kayıt / iptal edilen kayıt satırı, kayıt NUMARASI
///   yerine ilgili kaydın tarihi ve tutarını yazar; kayıt listede yoksa numarasız genel metin kullanılır.
/// - [onCorrect] / [onReverse] yalnız yönetici içindir (kurul / sakinde null).
/// - Faz 4b: [onOpenReceipt] makbuzu olan satırda "Makbuz MK-..." düğmesini, [onIssueReceipt] makbuzu olmayan tahsilatta
///   (yalnız yönetici) "Makbuz Düzenle" düğmesini, [onExplainLateFee] sakin ekranında gecikme tazminatı satırında
///   "Nasıl hesaplandı?" düğmesini çizer. Gecikme tazminatı satırı rozetle işaretlidir.
class LedgerEntryTile extends StatelessWidget {
  const LedgerEntryTile({
    super.key,
    required this.entry,
    this.showActor = false,
    this.showNotes = false,
    this.related = const <int, LedgerEntry>{},
    this.onCorrect,
    this.onReverse,
    this.actionsEnabled = true,
    this.onOpenReceipt,
    this.onIssueReceipt,
    this.onExplainLateFee,
  });

  final LedgerEntry entry;
  final bool showActor;
  final bool showNotes;
  final Map<int, LedgerEntry> related;
  final VoidCallback? onCorrect;
  final VoidCallback? onReverse;
  final bool actionsEnabled;
  final VoidCallback? onOpenReceipt;
  final VoidCallback? onIssueReceipt;
  final VoidCallback? onExplainLateFee;

  /// "05.10.2026 • 500,00 ₺" (tarih ve tutar); kayıt bilinmiyorsa null.
  static String? _brief(LedgerEntry? e) =>
      e == null ? null : '${formatCrmDate(e.entryDate)} • ${formatMinor(e.amountMinor.abs())}';

  /// Ters kayıt satırı: hangi kaydı tersine çevirdiği (numara gösterilmez).
  String? _reversesText() {
    if (entry.reversesEntryId == null) return null;
    final brief = _brief(related[entry.reversesEntryId]);
    return brief == null ? 'Daha önceki bir kaydın ters kaydı' : 'Şu kaydın ters kaydı: $brief';
  }

  /// İptal edilen kayıt satırı: hangi ters kayıtla iptal edildiği (numara gösterilmez).
  String? _reversedByText() {
    if (entry.reversedByEntryId == null) return null;
    final brief = _brief(related[entry.reversedByEntryId]);
    return brief == null ? 'Ters kayıtla iptal edildi' : 'Ters kayıtla iptal edildi: $brief';
  }

  static (AppTone, IconData) _style(LedgerEntry e) {
    if (e.isReversal) return (AppTone.warning, Icons.undo_rounded);
    switch (e.kind) {
      case LedgerKind.charge:
        return (AppTone.danger, Icons.receipt_long_rounded);
      case LedgerKind.payment:
        return (AppTone.success, Icons.payments_rounded);
      case LedgerKind.reversal:
        return (AppTone.warning, Icons.undo_rounded);
      case LedgerKind.unknown:
        return (AppTone.neutral, Icons.help_outline_rounded);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final secondary = th.bodyMedium?.copyWith(color: p.textSecondary);
    final e = entry;
    final (tone, icon) = _style(e);
    final kindLabel = e.isReversal ? LedgerKind.reversal.label : e.kind.label;
    final effect = e.amountMinor > 0 ? 'Borca eklendi' : (e.amountMinor < 0 ? 'Borçtan düşüldü' : '');
    // Yönetici notları yalnız yazma yetkisi olan ekranda ([showNotes]); sakin / kurul sunucu göndermiş olsa bile
    // not görmez. Not yoksa başlık yalnız tanım adıdır.
    final note = showNotes ? e.description : null;
    final reason = showNotes ? e.reversalReason : null;
    final title = <String>[
      if (e.definitionName != null) e.definitionName!,
      if (e.definitionName == null && note != null) note,
    ].join(' ');
    final reversesText = _reversesText();
    final reversedByText = _reversedByText();
    final canAct = actionsEnabled && (onCorrect != null || onReverse != null);
    final hasExtraActions = (onOpenReceipt != null && e.receipt != null) ||
        (onIssueReceipt != null && (e.receipt == null || e.receipt!.isCancelled)) ||
        (onExplainLateFee != null && e.isLateFee);

    final semantic = StringBuffer('$kindLabel. ${formatCrmDate(e.entryDate)}.');
    if (e.isReversed) semantic.write(' İptal edildi.');
    semantic.write(' ${e.amountMinor > 0 ? 'Borç artar' : 'Borç azalır'}: ${moneySemanticLabel(e.amountMinor.abs())}.');
    if (e.isLateFee) semantic.write(' Gecikme tazminatı.');
    final receipt = e.receipt;
    if (receipt != null) semantic.write(' Makbuz ${receipt.number}${receipt.isCancelled ? ', iptal edildi' : ''}.');
    if (title.isNotEmpty) semantic.write(' $title.');
    if (e.method != null) semantic.write(' ${e.method!.label}.');
    if (reversesText != null) semantic.write(' ${spokenMoneyText(reversesText)}.');
    if (reversedByText != null) semantic.write(' ${spokenMoneyText(reversedByText)}.');
    if (reason != null) semantic.write(' Neden: $reason.');

    return DialogPanel(
      key: ValueKey<String>('ledger_entry_${e.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            container: true,
            label: semantic.toString(),
            child: ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: AppSpace.sm,
                    runSpacing: AppSpace.xs,
                    children: [
                      DialogMetaPill(kindLabel, tone: tone, icon: icon),
                      if (e.isReversed)
                        const DialogMetaPill(
                          'İptal edildi',
                          tone: AppTone.neutral,
                          icon: Icons.block_rounded,
                        ),
                      if (e.method != null) DialogMetaPill(e.method!.label),
                      if (e.isLateFee)
                        const DialogMetaPill('Gecikme tazminatı', tone: AppTone.warning, icon: Icons.gavel_rounded),
                    ],
                  ),
                  const SizedBox(height: AppSpace.sm),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(formatCrmDate(e.entryDate), style: th.titleSmall),
                      ),
                      const SizedBox(width: AppSpace.sm),
                      Flexible(
                        child: Text(
                          formatSignedMinor(e.amountMinor),
                          textAlign: TextAlign.end,
                          style: th.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            decoration: e.isReversed ? TextDecoration.lineThrough : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (effect.isNotEmpty) Text(effect, style: th.bodySmall?.copyWith(color: p.textSecondary)),
                  if (title.isNotEmpty) ...[
                    const SizedBox(height: AppSpace.xs),
                    Text(title, style: th.bodyMedium),
                  ],
                  if (e.definitionName != null && note != null) Text(note, style: secondary),
                  if (e.period != null) Text('Dönem: ${e.period!.label}', style: secondary),
                  if (e.dueDate != null) Text('Vade: ${formatCrmDate(e.dueDate)}', style: secondary),
                  if (reversesText != null) Text(reversesText, style: secondary),
                  if (reversedByText != null) Text(reversedByText, style: secondary),
                  if (reason != null) Text('Neden: $reason', style: secondary),
                  if (e.payerParty != null) Text(payerPartyLabel(e.payerParty!), style: secondary),
                  if (showActor && e.createdByName != null)
                    Text(
                      'Kaydeden: ${e.createdByName}${e.createdAt == null ? '' : ' • ${formatIstanbulDateTime(e.createdAt)}'}',
                      style: th.bodySmall?.copyWith(color: p.textSecondary),
                    ),
                ],
              ),
            ),
          ),
          if (canAct || hasExtraActions) ...[
            const SizedBox(height: AppSpace.sm),
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.xs,
              children: [
                if (onOpenReceipt != null && receipt != null)
                  TextButton.icon(
                    key: ValueKey<String>('ledger_receipt_${e.id}'),
                    onPressed: actionsEnabled ? onOpenReceipt : null,
                    icon: Icon(receipt.isCancelled ? Icons.receipt_long_outlined : Icons.receipt_long_rounded, size: 18),
                    label: Text('Makbuz ${receipt.number}'),
                    style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  ),
                if (onIssueReceipt != null && (receipt == null || receipt.isCancelled))
                  TextButton.icon(
                    key: ValueKey<String>('ledger_issue_receipt_${e.id}'),
                    onPressed: actionsEnabled ? onIssueReceipt : null,
                    icon: const Icon(Icons.note_add_rounded, size: 18),
                    label: const Text('Makbuz Düzenle'),
                    style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  ),
                if (onExplainLateFee != null && e.isLateFee)
                  TextButton.icon(
                    key: ValueKey<String>('ledger_latefee_explain_${e.id}'),
                    onPressed: actionsEnabled ? onExplainLateFee : null,
                    icon: const Icon(Icons.help_outline_rounded, size: 18),
                    label: const Text('Nasıl hesaplandı?'),
                    style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  ),
                if (canAct && onCorrect != null)
                  TextButton.icon(
                    key: ValueKey<String>('ledger_correct_${e.id}'),
                    onPressed: actionsEnabled ? onCorrect : null,
                    icon: const Icon(Icons.edit_rounded, size: 18),
                    label: const Text('Düzelt'),
                    style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  ),
                if (canAct && onReverse != null)
                  TextButton.icon(
                    key: ValueKey<String>('ledger_reverse_${e.id}'),
                    onPressed: actionsEnabled ? onReverse : null,
                    icon: const Icon(Icons.undo_rounded, size: 18),
                    label: const Text('İptal Et'),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(48, 48),
                      foregroundColor: AppTone.danger.ink(p),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// --- Tanım kartı ------------------------------------------------------------------------------

/// Aidat / ek borç tanımı kartı. Eylemler ([onPost], [onEdit], [onToggleActive]) yalnız yazma yetkisi
/// olanda verilir; kurul üyesinde hiçbiri çizilmez.
class FeeDefinitionCard extends StatelessWidget {
  const FeeDefinitionCard({
    super.key,
    required this.definition,
    this.onPost,
    this.onEdit,
    this.onToggleActive,
    this.busy = false,
    this.busyLabel,
    this.actionsEnabled = true,
    this.errorText,
  });

  final FeeDefinition definition;
  final VoidCallback? onPost;
  final VoidCallback? onEdit;
  final VoidCallback? onToggleActive;
  final bool busy;

  /// Verilirse (örn. "Güncelleniyor...") ve [busy] iken "Pasifleştir / Etkinleştir" düğmesi bu etiketle ve
  /// dönen göstergeyle çizilir: meşgul durumu yalnız pasiflikle değil görsel + anlamsal olarak da bildirilir.
  final String? busyLabel;

  /// false: liste güncel değil (yenileme başarısız); eylem düğmeleri görünür ama pasiftir.
  final bool actionsEnabled;

  /// Bu tanım üzerindeki son eylemin hatası (kartın içinde, eylem düğmelerinin üstünde gösterilir).
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final secondary = th.bodyMedium?.copyWith(color: p.textSecondary);
    final d = definition;
    final name = d.name.trim().isEmpty ? 'Adsız tanım' : d.name.trim();
    final last = d.lastPostedPeriod;
    // Tek seferlik tanımın dönemi yoktur (ay seçimi etkisizdi); vadesi borçlandırılırken belirlenir.
    final schedule = d.isRecurring
        ? '${dueDayText(d.dueDay)} • ${periodRangeText(d.startPeriod, d.endPeriod)}'
        : (d.kind == FeeKind.oneTime ? 'Vade: borçlandırılırken belirlenir' : null);
    final hasActions = onPost != null || onEdit != null || onToggleActive != null;

    final semantic = StringBuffer('Tanım: $name. ${d.kind.label}. ${d.isActive ? 'Aktif' : 'Pasif'}.');
    semantic.write(' ${d.distribution.label}. ${spokenMoneyText(definitionAmountText(d))}.');
    semantic.write(' Hedef: ${d.target.summary}.');
    semantic.write(last == null ? ' Henüz borçlandırılmadı.' : ' Son borçlandırma: ${last.label}.');
    final disabled = busy || !actionsEnabled;

    return AppCard(
      key: ValueKey<String>('fee_definition_${d.id}'),
      padding: listCardPadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            container: true,
            label: semantic.toString(),
            child: ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: AppSpace.sm,
                    runSpacing: AppSpace.xs,
                    children: [
                      DialogMetaPill(
                        d.kind.label,
                        tone: AppTone.info,
                        icon: d.isRecurring ? Icons.event_repeat_rounded : Icons.looks_one_rounded,
                      ),
                      DialogMetaPill(
                        d.isActive ? 'Aktif' : 'Pasif',
                        tone: d.isActive ? AppTone.success : AppTone.neutral,
                        icon: d.isActive ? Icons.check_circle_rounded : Icons.pause_circle_rounded,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpace.sm),
                  Text(name, style: th.titleMedium),
                  const SizedBox(height: AppSpace.xs),
                  Text(
                    '${d.distribution.label} • ${definitionAmountText(d)}'
                    '${d.distribution == FeeDistribution.area && d.areaBasis != null ? ' (${d.areaBasis!.label})' : ''}',
                    style: th.bodyMedium,
                  ),
                  if (schedule != null) Text(schedule, style: secondary),
                  Text('Hedef: ${d.target.summary}', style: secondary),
                  Text(
                    last == null ? 'Henüz borçlandırılmadı' : 'Son borçlandırma: ${last.label}',
                    style: secondary,
                  ),
                ],
              ),
            ),
          ),
          if (errorText != null) ...[
            const SizedBox(height: AppSpace.sm),
            CrmFormError(
              key: ValueKey<String>('fee_definition_error_${d.id}'),
              message: errorText!,
              announce: true,
            ),
          ],
          if (hasActions) ...[
            const SizedBox(height: AppSpace.sm),
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.xs,
              children: [
                if (onPost != null)
                  TextButton.icon(
                    key: ValueKey<String>('fee_definition_post_${d.id}'),
                    onPressed: disabled ? null : onPost,
                    icon: const Icon(Icons.playlist_add_check_rounded, size: 18),
                    label: const Text('Borçlandır'),
                    style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  ),
                if (onEdit != null)
                  TextButton.icon(
                    key: ValueKey<String>('fee_definition_edit_${d.id}'),
                    onPressed: disabled ? null : onEdit,
                    icon: const Icon(Icons.edit_rounded, size: 18),
                    label: const Text('Düzenle'),
                    style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  ),
                if (onToggleActive != null)
                  TextButton.icon(
                    key: ValueKey<String>('fee_definition_toggle_${d.id}'),
                    onPressed: disabled ? null : onToggleActive,
                    icon: busy && busyLabel != null
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            d.isActive
                                ? Icons.pause_circle_outline_rounded
                                : Icons.play_circle_outline_rounded,
                            size: 18,
                          ),
                    label: Text(
                      busy && busyLabel != null
                          ? busyLabel!
                          : (d.isActive ? 'Pasifleştir' : 'Etkinleştir'),
                    ),
                    style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Önizleme satırı: daire etiketi, kim öder ve tutar. Yer yetiyorsa tutar satırın sağ ucundadır; dar ekranda ya da
/// büyük yazıda (örn. 320 dp x 2,0) tutar daire adının ALTINA iner (gerçek `Wrap`: sığmayan öğe alt satıra geçer) ve
/// kırpılmaz. Pencere içerik ölçüsü (IntrinsicHeight) kullandığı için `LayoutBuilder` kullanılmaz.
class FeePreviewLineTile extends StatelessWidget {
  const FeePreviewLineTile({super.key, required this.line});

  final FeePreviewLine line;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final title = financeApartmentTitle(line.blockName, line.label);
    // İP-1A: sunucu borcun yazılacağı hesabı verdiyse o yazılır ("Kiracı hesabı"); eski sunucuda "kim öder" etiketi.
    final who = line.accountParty?.label ?? payerPartyLabel(line.payerParty);
    return Semantics(
      container: true,
      label: '$title. $who. ${moneySemanticLabel(line.amountMinor)}.',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.start,
            spacing: AppSpace.sm,
            runSpacing: AppSpace.xs,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: th.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                  Text(
                    who,
                    style: th.bodySmall?.copyWith(color: p.textSecondary),
                  ),
                ],
              ),
              Text(
                formatMinor(line.amountMinor),
                style: th.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Kim öder" çipi (malik / kiracı / ikisi).
class PayerPartyChip extends StatelessWidget {
  const PayerPartyChip(this.party, {super.key});

  final ResponsibleParty party;

  @override
  Widget build(BuildContext context) =>
      InfoChip(payerPartyLabel(party), tone: AppTone.info);
}

/// Seçenek grubu başlığı ("Tür", "Durum", "Yöntem"): ekran okuyucuda başlık olarak gezilebilir.
class FinanceGroupTitle extends StatelessWidget {
  const FinanceGroupTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      container: true,
      child: Text(text, style: Theme.of(context).textTheme.titleSmall),
    );
  }
}
