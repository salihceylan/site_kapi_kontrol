import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/cash_models.dart';
import 'package:site_kapi_kontrol/models/expense_models.dart';
import 'package:site_kapi_kontrol/models/finance_4b.dart';
import 'package:site_kapi_kontrol/models/receipt_models.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/large_dialog_parts.dart';
import 'package:site_kapi_kontrol/ui/helpers/a11y_announce.dart';
import 'package:site_kapi_kontrol/ui/helpers/date_input.dart';
import 'package:site_kapi_kontrol/ui/helpers/fund_text.dart';
import 'package:site_kapi_kontrol/ui/helpers/money.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

/// Faz 4b ekranlarının ortak görünüm parçaları (makbuz, kasa, gider). Kurallar 4a ile aynıdır:
/// - Tutar ekran okuyucuya sayı yığını değil "bin iki yüz elli lira" diye okunur; kart TEK birleşik etiketle okunur.
/// - Durum YALNIZ renkle belirtilmez: simge + metin birlikte.
/// - Metinler sarar (kırpılmaz); küçük ekranda (320 dp x 2,0) taşma yoktur.

/// "Etiket: değer" satırı. Dar alanda değer alt satıra iner; tutar için [money] verilirse [MoneyText] kullanılır.
class FinanceInfoRow extends StatelessWidget {
  const FinanceInfoRow({super.key, required this.label, this.value, this.money, this.emphasize = false});

  final String label;
  final String? value;
  final int? money;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final style = (emphasize ? th.titleMedium : th.bodyMedium)?.copyWith(fontWeight: FontWeight.w700);
    final Widget valueWidget = money != null
        ? MoneyText(money!, style: style, semanticPrefix: label)
        : Text(value ?? '-', style: style);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Wrap(
        spacing: AppSpace.sm,
        runSpacing: 2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(label, style: th.bodyMedium?.copyWith(color: p.textSecondary)),
          valueWidget,
        ],
      ),
    );
  }
}

/// Gönderim (kaydet / iptal / gönder) hatası kutusu: ekran okuyucuya duyurulur VE odak hata kutusuna alınır. Gönderimde alan
/// kilitlenip odak düştüğü için (klavye / ekran okuyucu kullanıcısı) hatayı bulmak için pencerenin başına dönmek gerekmesin.
class FinanceSubmitError extends StatefulWidget {
  const FinanceSubmitError({super.key, required this.message, this.action});

  final String message;

  /// İsteğe bağlı eylem (örn. "Tekrar Dene" düğmesi).
  final Widget? action;

  @override
  State<FinanceSubmitError> createState() => _FinanceSubmitErrorState();
}

class _FinanceSubmitErrorState extends State<FinanceSubmitError> {
  final FocusNode _focus = FocusNode(debugLabel: 'finance_submit_error');

  @override
  void initState() {
    super.initState();
    _take();
  }

  @override
  void didUpdateWidget(FinanceSubmitError oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message != widget.message) _take();
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _take() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Scrollable.ensureVisible(context, duration: Duration.zero, alignment: 0.0);
      announcePolite(context, spokenMoneyText(widget.message));
      _focus.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final action = widget.action;
    return Focus(
      focusNode: _focus,
      // Hata iletisinde tutar varsa ekran okuyucuya sayı yığını değil "bin iki yüz elli lira" okunur.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InlineNotice(message: widget.message, semanticsLabel: spokenMoneyText(widget.message)),
          if (action != null) ...[const SizedBox(height: AppSpace.sm), action],
          const SizedBox(height: AppSpace.md),
        ],
      ),
    );
  }
}

/// Son banka / kasa kontrolü özeti: "Son mutabakat 01.10.2026: tutuyor" / "...: fark -5,00 ₺" / "...: fark -5,00 ₺ (düzeltme hareketiyle giderildi)".
String reconciliationSummary(LastReconciliation r) {
  final date = formatCrmDate(r.asOfDate);
  if (r.differenceMinor == 0) return 'Son banka / kasa kontrolü $date: tutuyor';
  final diff = formatMinor(r.differenceMinor);
  return r.adjusted == true
      ? 'Son banka / kasa kontrolü $date: fark $diff (düzeltme hareketiyle giderildi)'
      : 'Son banka / kasa kontrolü $date: fark $diff';
}

/// İçinde tutar geçen düz metin: görsel "2.500,00 ₺", ekran okuyucuya "iki bin beş yüz lira" (sayı yığını değil).
class FinanceSpokenText extends StatelessWidget {
  const FinanceSpokenText(this.text, {super.key, this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: spokenMoneyText(text),
      child: ExcludeSemantics(child: Text(text, style: style)),
    );
  }
}

// --- Makbuz -----------------------------------------------------------------------------------

/// Makbuz liste satırı: numara, durum, tutar, daire ve tarihler. Dokununca ayrıntı açılır.
class ReceiptTile extends StatelessWidget {
  const ReceiptTile({super.key, required this.receipt, required this.onTap, this.showPayer = true});

  final ReceiptSummary receipt;
  final VoidCallback onTap;
  final bool showPayer;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final r = receipt;
    final (String statusText, AppTone tone, IconData icon) = r.isCancellation
        ? ('İptal makbuzu', AppTone.warning, Icons.undo_rounded)
        : (r.isCancelled
              ? ('İptal edildi', AppTone.neutral, Icons.block_rounded)
              : ('Geçerli', AppTone.success, Icons.verified_rounded));
    final dates = <String>[
      if (r.paidOn != null) 'Tahsilat: ${formatCrmDate(r.paidOn)}',
      if (r.issuedOn != null) 'Düzenleme: ${formatCrmDate(r.issuedOn)}',
    ];
    final semantic = StringBuffer('Makbuz ${r.number}. $statusText. ${moneySemanticLabel(r.amountMinor)}.');
    if (r.apartmentLabel.isNotEmpty) semantic.write(' Daire ${r.apartmentLabel}.');
    for (final d in dates) {
      semantic.write(' $d.');
    }
    if (showPayer && r.payerName != null) semantic.write(' Ödeyen: ${r.payerName}.');
    return AppCard(
      key: ValueKey<String>('receipt_tile_${r.id}'),
      padding: listCardPadding(context),
      onTap: onTap,
      semanticLabel: semantic.toString(),
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.xs,
              children: [
                DialogMetaPill(statusText, tone: tone, icon: icon),
                if (r.apartmentLabel.isNotEmpty) DialogMetaPill(r.apartmentLabel),
              ],
            ),
            const SizedBox(height: AppSpace.sm),
            Text(r.number, style: th.titleMedium),
            Text(
              formatMinor(r.amountMinor),
              style: th.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                decoration: r.isCancelled ? TextDecoration.lineThrough : null,
              ),
            ),
            for (final d in dates) Text(d, style: th.bodySmall?.copyWith(color: p.textSecondary)),
            if (showPayer && r.payerName != null)
              Text('Ödeyen: ${r.payerName}', style: th.bodySmall?.copyWith(color: p.textSecondary)),
          ],
        ),
      ),
    );
  }
}

// --- Kasa / banka -------------------------------------------------------------------------------

IconData cashKindIcon(CashAccountKind kind) =>
    kind == CashAccountKind.bank ? Icons.account_balance_rounded : Icons.payments_rounded;

/// Kasa / banka hesap kartı: ad, tür, bakiye, son mutabakat ve uyarılar. Eylemler yalnız verildiğinde çizilir
/// (kurulda hiçbiri verilmez).
class CashAccountCard extends StatelessWidget {
  const CashAccountCard({
    super.key,
    required this.account,
    this.onOpen,
    this.onAdjust,
    this.onReconcile,
    this.onEdit,
    this.busy = false,
  });

  final CashAccount account;
  final VoidCallback? onOpen;
  final VoidCallback? onAdjust;
  final VoidCallback? onReconcile;
  final VoidCallback? onEdit;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final a = account;
    final reconciliation = a.lastReconciliation;
    final reconText = reconciliation == null ? 'Henüz banka / kasa kontrolü yapılmadı' : reconciliationSummary(reconciliation);
    final semantic = StringBuffer('${a.kind.label}: ${a.name}. ${a.isActive ? 'Aktif' : 'Pasif'}.');
    semantic.write(' Bakiye: ${moneySemanticLabel(a.balanceMinor)}.');
    if (a.isNegative) semantic.write(' Uyarı: bakiye eksiye düşmüş.');
    semantic.write(' ${spokenMoneyText(reconText)}.');
    final hasActions = onOpen != null || onAdjust != null || onReconcile != null || onEdit != null;
    return AppCard(
      key: ValueKey<String>('cash_account_${a.id}'),
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
                      DialogMetaPill(a.kind.label, tone: AppTone.info, icon: cashKindIcon(a.kind)),
                      DialogMetaPill(
                        a.isActive ? 'Aktif' : 'Pasif',
                        tone: a.isActive ? AppTone.success : AppTone.neutral,
                        icon: a.isActive ? Icons.check_circle_rounded : Icons.pause_circle_rounded,
                      ),
                      if (a.isNegative)
                        const DialogMetaPill('Bakiye eksi', tone: AppTone.danger, icon: Icons.warning_amber_rounded),
                    ],
                  ),
                  const SizedBox(height: AppSpace.sm),
                  Text(a.name, style: th.titleMedium),
                  Text(
                    formatMinor(a.balanceMinor),
                    key: ValueKey<String>('cash_balance_${a.id}'),
                    style: th.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: a.isNegative ? AppTone.danger.ink(p) : null,
                    ),
                  ),
                  if (a.note != null) Text(a.note!, style: th.bodyMedium?.copyWith(color: p.textSecondary)),
                  const SizedBox(height: AppSpace.xs),
                  Text(
                    reconText,
                    style: th.bodySmall?.copyWith(
                      color: reconciliation != null && reconciliation.hasOpenDifference
                          ? AppTone.warning.ink(p)
                          : p.textSecondary,
                      fontWeight: reconciliation != null && reconciliation.hasOpenDifference
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (hasActions) ...[
            const SizedBox(height: AppSpace.sm),
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.xs,
              children: [
                if (onOpen != null)
                  TextButton.icon(
                    key: ValueKey<String>('cash_open_${a.id}'),
                    onPressed: busy ? null : onOpen,
                    icon: const Icon(Icons.list_alt_rounded, size: 18),
                    label: const Text('Hareketler'),
                    style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  ),
                if (onAdjust != null)
                  TextButton.icon(
                    key: ValueKey<String>('cash_adjust_${a.id}'),
                    onPressed: busy || !a.isActive ? null : onAdjust,
                    icon: const Icon(Icons.tune_rounded, size: 18),
                    label: const Text('Düzeltme'),
                    style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  ),
                if (onReconcile != null)
                  TextButton.icon(
                    key: ValueKey<String>('cash_reconcile_${a.id}'),
                    onPressed: busy ? null : onReconcile,
                    icon: const Icon(Icons.fact_check_rounded, size: 18),
                    label: const Text('Banka / kasa kontrolü'),
                    style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  ),
                if (onEdit != null)
                  TextButton.icon(
                    key: ValueKey<String>('cash_edit_${a.id}'),
                    onPressed: busy ? null : onEdit,
                    icon: const Icon(Icons.edit_rounded, size: 18),
                    label: const Text('Düzenle'),
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

/// Hesap hareketi satırı. Tutar İŞARETLİDİR (+ giriş, - çıkış); iptal edilen hareket üstü çizili.
class MovementTile extends StatelessWidget {
  const MovementTile({super.key, required this.movement});

  final AccountMovement movement;

  static (AppTone, IconData) _style(AccountMovement m) {
    if (m.isReversal) return (AppTone.warning, Icons.undo_rounded);
    switch (m.kind) {
      case MovementKind.collection:
        return (AppTone.success, Icons.payments_rounded);
      case MovementKind.expense:
        return (AppTone.danger, Icons.shopping_bag_rounded);
      case MovementKind.transferIn:
      case MovementKind.transferOut:
        return (AppTone.info, Icons.swap_horiz_rounded);
      case MovementKind.adjustment:
        return (AppTone.warning, Icons.tune_rounded);
      case MovementKind.opening:
        return (AppTone.neutral, Icons.flag_rounded);
      case MovementKind.reversal:
        return (AppTone.warning, Icons.undo_rounded);
      case MovementKind.refund:
        return (AppTone.danger, Icons.assignment_return_rounded);
      case MovementKind.unknown:
        return (AppTone.neutral, Icons.help_outline_rounded);
    }
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final m = movement;
    final (tone, icon) = _style(m);
    final reason = AdjustmentReason.tryParse(m.reasonCode);
    final semantic = StringBuffer('${m.kind.label}. ${formatCrmDate(m.movementDate)}.');
    semantic.write(' ${m.amountMinor >= 0 ? 'Giriş' : 'Çıkış'}: ${moneySemanticLabel(m.amountMinor.abs())}.');
    if (m.label != null) semantic.write(' ${m.label}.');
    if (reason != null) semantic.write(' ${reason.label}.');
    if (m.isReversed) semantic.write(' İptal edildi.');
    return DialogPanel(
      key: ValueKey<String>('movement_${m.id}'),
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
                children: [
                  DialogMetaPill(m.kind.label, tone: tone, icon: icon),
                  if (m.isReversed)
                    const DialogMetaPill('İptal edildi', tone: AppTone.neutral, icon: Icons.block_rounded),
                  if (reason != null) DialogMetaPill(reason.label),
                ],
              ),
              const SizedBox(height: AppSpace.sm),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: AppSpace.sm,
                children: [
                  Text(formatCrmDate(m.movementDate), style: th.titleSmall),
                  Text(
                    formatSignedMinor(m.amountMinor),
                    style: th.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      decoration: m.isReversed ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ],
              ),
              if (m.label != null) Text(m.label!, style: th.bodyMedium),
              if (m.note != null) Text(m.note!, style: th.bodyMedium?.copyWith(color: p.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }
}

// --- Gider -------------------------------------------------------------------------------------

/// Gider liste satırı: kategori, tedarikçi, açıklama, tutar, hesap, belge ve iptal durumu.
class ExpenseTile extends StatelessWidget {
  const ExpenseTile({super.key, required this.expense, required this.onTap});

  final Expense expense;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final e = expense;
    final semantic = StringBuffer('Gider: ${e.categoryName}. ${formatCrmDate(e.expenseDate)}.');
    semantic.write(' ${moneySemanticLabel(e.amountMinor)}.');
    if (e.supplierName != null) semantic.write(' Tedarikçi: ${e.supplierName}.');
    if (e.description.isNotEmpty) semantic.write(' ${e.description}.');
    if (e.accountName != null) semantic.write(' Hesap: ${e.accountName}.');
    if (e.fund != null) semantic.write(' Kasa: ${e.fund!.label}.');
    if (e.isVoided) semantic.write(' İptal edildi.');
    return AppCard(
      key: ValueKey<String>('expense_tile_${e.id}'),
      padding: listCardPadding(context),
      onTap: onTap,
      semanticLabel: semantic.toString(),
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.xs,
              children: [
                DialogMetaPill(e.categoryName.isEmpty ? 'Kategorisiz' : e.categoryName, tone: AppTone.info, icon: Icons.sell_rounded),
                if (e.fund != null) DialogMetaPill(e.fund!.shortLabel, tone: AppTone.info, icon: fundIcon(e.fund!)),
                if (e.isVoided)
                  const DialogMetaPill('İptal edildi', tone: AppTone.neutral, icon: Icons.block_rounded),
                if (e.documentsCount > 0)
                  DialogMetaPill('${e.documentsCount} belge', icon: Icons.attach_file_rounded),
              ],
            ),
            const SizedBox(height: AppSpace.sm),
            Text(
              e.description.isEmpty ? 'Açıklamasız gider' : e.description,
              style: th.titleMedium,
            ),
            Text(
              formatMinor(e.amountMinor),
              style: th.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                decoration: e.isVoided ? TextDecoration.lineThrough : null,
              ),
            ),
            Text(formatCrmDate(e.expenseDate), style: th.bodySmall?.copyWith(color: p.textSecondary)),
            if (e.supplierName != null)
              Text(e.supplierName!, style: th.bodyMedium?.copyWith(color: p.textSecondary)),
            if (e.accountName != null)
              Text('Hesap: ${e.accountName}', style: th.bodySmall?.copyWith(color: p.textSecondary)),
          ],
        ),
      ),
    );
  }
}

/// Kısa tarih aralığı metni ("01.10.2026 - 31.10.2026").
String financeDateRange(DateTime? from, DateTime? to) => '${formatCrmDate(from)} - ${formatCrmDate(to)}';

/// Para toplamı satırı: etiket + [MoneyText] (başlık stili).
class TotalPill extends StatelessWidget {
  const TotalPill({super.key, required this.label, required this.minor, this.tone = AppTone.info, this.icon});

  final String label;
  final int minor;
  final AppTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '$label: ${moneySemanticLabel(minor)}',
      child: ExcludeSemantics(child: DialogMetaPill('$label ${formatMinor(minor)}', tone: tone, icon: icon)),
    );
  }
}

/// Oran etiketi için tek yerden: "%87,65" (baz puan) ya da yoksa "-".
String percentOrDash(int? bp) => bp == null ? '-' : formatPercentBp(bp);

// --- Tarih alanı --------------------------------------------------------------------------------

/// GG.AA.YYYY tarih giriş alanı (Faz 4b pencerelerinin ortağı). 8 rakamdan fazlası sessizce kırpılmaz: uyarı
/// gösterilir ve duyurulur. [minDate] / [maxDate] dışı tarih sunucuya gitmeden reddedilir (sunucu yine de doğrular).
class FinanceDateField extends StatefulWidget {
  const FinanceDateField({
    required Key super.key,
    required this.controller,
    required this.label,
    this.enabled = true,
    this.required = true,
    this.minDate,
    this.maxDate,
    this.maxMessage = 'Tarih bugünden ileri olamaz.',
    this.minMessage,
    this.helperText,
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final bool enabled;
  final bool required;
  final DateTime? minDate;
  final DateTime? maxDate;
  final String maxMessage;
  final String? minMessage;
  final String? helperText;
  final ValueChanged<DateTime?>? onChanged;

  @override
  State<FinanceDateField> createState() => _FinanceDateFieldState();
}

class _FinanceDateFieldState extends State<FinanceDateField> {
  bool _overflow = false;

  String? _validate(String? value) {
    if ((value ?? '').trim().isEmpty) return widget.required ? '${widget.label} girin.' : null;
    final format = validateDateField(value);
    if (format != null) return format;
    final date = parseDateField(value)!;
    final max = widget.maxDate;
    if (max != null && date.isAfter(max)) return widget.maxMessage;
    final min = widget.minDate;
    if (min != null && date.isBefore(min)) {
      return widget.minMessage ?? '${widget.label} ${formatDateField(min)} tarihinden önce olamaz.';
    }
    return null;
  }

  void _rejected() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _overflow = true);
      announcePolite(context, 'Tarih en çok 8 rakamdır. Fazla rakam eklenmedi.');
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return TextFormField(
      controller: widget.controller,
      enabled: widget.enabled,
      keyboardType: TextInputType.number,
      inputFormatters: [DateInputFormatter(onRejected: _rejected)],
      autovalidateMode: AutovalidateMode.onUserInteraction,
      onChanged: (text) {
        if (_overflow) setState(() => _overflow = false);
        widget.onChanged?.call(parseDateField(text));
      },
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: 'GG.AA.YYYY',
        helperText: _overflow
            ? 'Tarih en çok 8 rakamdır (GG.AA.YYYY); fazla rakam eklenmedi.'
            : (widget.helperText ?? 'Gün.Ay.Yıl biçiminde yazın (GG.AA.YYYY).'),
        helperMaxLines: 3,
        helperStyle: _overflow ? TextStyle(color: AppTone.warning.ink(p), fontWeight: FontWeight.w700) : null,
        prefixIcon: const Icon(Icons.event_rounded),
      ),
      validator: _validate,
    );
  }
}
