import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MaxLengthEnforcement;
import 'package:site_kapi_kontrol/models/finance_funds.dart';
import 'package:site_kapi_kontrol/models/fund_models.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/finance_reason_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/large_dialog_parts.dart';
import 'package:site_kapi_kontrol/ui/helpers/cursor_loader.dart';
import 'package:site_kapi_kontrol/ui/helpers/date_input.dart';
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_4b_access.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_errors.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_write_mixin.dart';
import 'package:site_kapi_kontrol/ui/helpers/form_validation.dart';
import 'package:site_kapi_kontrol/ui/helpers/istanbul_time.dart';
import 'package:site_kapi_kontrol/ui/helpers/money.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/helpers/text_length.dart';
import 'package:site_kapi_kontrol/ui/widgets/cursor_list_body.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_4b_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_fund_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/money_field.dart';

/// "Kasalar Arası Aktarım" penceresi: bir kasadan diğerine bakiye aktarımı (açılış bölüşümü, kurul kararıyla aktarım).
/// Fiziksel hesap hareketi doğurmaz; yalnız İşletme Projesi (Aidat) Hesabı ile Yatırım ve Demirbaş (Fon) Hesabı bakiyesini
/// değiştirir. Çıkış kasası seçilir, giriş kasası diğeridir (aynı kasa seçilemez).
///
/// - Tarih bugünden ileri olamaz ve AÇIK ayda olmalıdır (sunucu doğrular: 409 `PERIOD_CLOSED`).
/// - Tutar çıkış kasasının bakiyesini aşıyorsa uyarılır (ENGELLENMEZ; bakiye eksiye düşer ve kartta uyarı çıkar).
///   Bakiyeler [summary]'den (açık özet) okunur; özet yoksa uyarı hiç gösterilmez.
/// - `idempotency_key` verinin imzasına bağlıdır: sonucu belirsiz kalan isteği aynı veriyle yeniden denemek çift aktarım
///   yazmaz; aynı anahtar farklı bilgiyle gönderilmişse (409 `IDEMPOTENCY_CONFLICT`) aktarım listesi kontrol ettirilir.
class FinanceFundTransferDialog extends StatefulWidget {
  const FinanceFundTransferDialog({super.key, required this.scope, this.summary, this.now, this.onRefreshNeeded});

  final PeopleScope scope;

  /// Açık kasa özeti (bakiye göstermek / aşım uyarısı için); null olabilir.
  final FundSummary? summary;
  final DateTime Function()? now;
  final VoidCallback? onRefreshNeeded;

  static const int maxDescriptionLength = 200;

  static Future<FinanceWriteOutcome?> show(
    BuildContext context, {
    required PeopleScope scope,
    FundSummary? summary,
    DateTime Function()? now,
    VoidCallback? onRefreshNeeded,
  }) {
    return showDialog<FinanceWriteOutcome>(
      context: context,
      barrierDismissible: false,
      builder: (_) => FinanceFundTransferDialog(scope: scope, summary: summary, now: now, onRefreshNeeded: onRefreshNeeded),
    );
  }

  @override
  State<FinanceFundTransferDialog> createState() => _FinanceFundTransferDialogState();
}

class _FinanceFundTransferDialogState extends State<FinanceFundTransferDialog> with FinanceWriteMixin, FinanceDiscardGuard {
  @override
  String get keyPrefix => 'fxfer';

  @override
  Object? get keyOwner => widget.scope.authService;

  @override
  bool get closeLocked => submitting;

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _description = TextEditingController();
  late final TextEditingController _date = TextEditingController(text: formatDateField(_today()));
  FinanceFund? _from;
  String? _fromError;

  DateTime _today() {
    final wall = istanbulNow(widget.now?.call());
    return DateTime(wall.year, wall.month, wall.day);
  }

  /// Giriş kasası: çıkış kasasının diğeri.
  FinanceFund? get _to => _from == null ? null : (_from == FinanceFund.operating ? FinanceFund.capital : FinanceFund.operating);

  @override
  void dispose() {
    disposeWrite();
    _amount.dispose();
    _description.dispose();
    _date.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (writeBlocked) return;
    final ok = validateForm(
      _formKey,
      validateExtra: () {
        setState(() => _fromError = _from == null ? 'Para çıkacak kasayı seçin.' : null);
        return _from != null;
      },
    );
    if (!ok) {
      setState(() => submitError = kFixFieldsMessage);
      return;
    }
    final from = _from!;
    final to = _to!;
    final minor = parseMoney(_amount.text).minor!;
    final date = parseDateField(_date.text)!;
    final description = _description.text.trim();
    await runWrite<FundTransfer>(
      signature: 'fxfer|${from.apiValue}|${to.apiValue}|$minor|${formatDateField(date)}|$description',
      action: (key) => widget.scope.f4Call(
        (api, t, s) => api.createFundTransfer(
          token: t,
          siteCode: s,
          fromFund: from,
          toFund: to,
          amountMinor: minor,
          transferDate: date,
          description: description,
          idempotencyKey: key,
        ),
      ),
      onSuccess: (_) => popIfCurrent(
        context,
        FinanceWriteOutcome('Aktarım yapıldı: ${formatMinor(minor)} (${from.shortLabel} → ${to.shortLabel}).'),
      ),
      failure: 'Aktarım yapılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.',
      onError: (e) {
        // Genel "daire hesaplarını kontrol edin" metni burada yanıltıcıdır: aktarım listesi kontrol ettirilir.
        if (!hasErrorCode(e, 'IDEMPOTENCY_CONFLICT')) return false;
        setState(() {
          submitError =
              'Bu aktarım daha önce farklı bilgilerle gönderilmiş görünüyor. Önce Kasalar Arası Aktarım Listesi\'ni kontrol edin.';
        });
        return true;
      },
    );
  }

  void _notify() {
    if (!needsRefreshOnClose) return;
    needsRefreshOnClose = false;
    widget.onRefreshNeeded?.call();
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final summary = widget.summary;
    final from = _from;
    final to = _to;
    final minor = parseMoney(_amount.text).minor;
    final fromBalance = from == null || summary == null ? null : summary.of(from).balanceMinor;
    return PopScope(
      canPop: canPopNow,
      onPopInvokedWithResult: (didPop, _) {
        handleBlockedPop(didPop);
        if (didPop) _notify();
      },
      child: AppDialog(
        title: 'Kasalar Arası Aktarım',
        subtitle: widget.scope.siteName.isEmpty ? null : widget.scope.siteName,
        icon: Icons.swap_vert_rounded,
        actions: [
          TextButton(
            onPressed: submitting ? null : requestClose,
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            key: const ValueKey<String>('finance_fund_transfer_submit'),
            onPressed: writeBlocked ? null : _submit,
            child: Text(submitting ? 'Aktarılıyor...' : 'Aktar'),
          ),
        ],
        child: Form(
          key: _formKey,
          onChanged: markDirty,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (submitError != null) FinanceSubmitError(message: submitError!),
              FundChoice(
                key: const ValueKey<String>('finance_fund_transfer_from_group'),
                title: 'Çıkış kasası (para buradan çıkar)',
                selected: _from,
                enabled: !submitting,
                keyPrefix: 'finance_fund_transfer_from',
                noteFor: (fund) => summary == null ? fund.payerNote : 'bakiye ${formatMinor(summary.of(fund).balanceMinor)}',
                errorText: _fromError,
                onSelected: (value) => setState(() {
                  markDirty();
                  _from = value;
                  _fromError = null;
                }),
              ),
              if (to != null) ...[
                const SizedBox(height: AppSpace.sm),
                Semantics(
                  container: true,
                  label: 'Giriş kasası: ${to.label}',
                  child: ExcludeSemantics(
                    child: Row(
                      key: const ValueKey<String>('finance_fund_transfer_to'),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.arrow_downward_rounded, size: 20, color: p.textSecondary),
                        const SizedBox(width: AppSpace.sm),
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(text: 'Giriş kasası: ', style: th.bodyMedium?.copyWith(color: p.textSecondary)),
                                TextSpan(text: to.label, style: th.bodyMedium?.copyWith(fontWeight: FontWeight.w800)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: AppSpace.md),
              MoneyFormField(
                key: const ValueKey<String>('finance_fund_transfer_amount_group'),
                fieldKey: const ValueKey<String>('finance_fund_transfer_amount'),
                controller: _amount,
                enabled: !submitting,
                label: 'Aktarım tutarı',
                textInputAction: TextInputAction.next,
                onChanged: (_) => setState(() {}),
              ),
              if (from != null && fromBalance != null && minor != null && minor > fromBalance) ...[
                const SizedBox(height: AppSpace.sm),
                InlineNotice(
                  key: const ValueKey<String>('finance_fund_transfer_exceeds'),
                  tone: AppTone.warning,
                  message:
                      'Bu tutar ${from.label} bakiyesini (${formatMinor(fromBalance)}) aşıyor; kasa eksiye düşer. Kayıtları kontrol edin.',
                  semanticsLabel: spokenMoneyText(
                    'Bu tutar ${from.label} bakiyesini (${formatMinor(fromBalance)}) aşıyor; kasa eksiye düşer. Kayıtları kontrol edin.',
                  ),
                ),
              ],
              const SizedBox(height: AppSpace.md),
              FinanceDateField(
                key: const ValueKey<String>('finance_fund_transfer_date_group'),
                controller: _date,
                label: 'Aktarım tarihi',
                enabled: !submitting,
                maxDate: _today(),
              ),
              const SizedBox(height: AppSpace.md),
              TextFormField(
                key: const ValueKey<String>('finance_fund_transfer_description'),
                controller: _description,
                enabled: !submitting,
                minLines: 1,
                maxLines: 3,
                maxLength: FinanceFundTransferDialog.maxDescriptionLength,
                maxLengthEnforcement: MaxLengthEnforcement.none,
                buildCounter: (context, {required currentLength, required isFocused, maxLength}) => characterCounter(
                  context,
                  trimmedCodePoints(_description.text),
                  FinanceFundTransferDialog.maxDescriptionLength,
                ),
                textCapitalization: TextCapitalization.sentences,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Açıklama (isteğe bağlı)',
                  hintText: 'Örn. Kurul kararı: asansör yenileme için fon aktarımı',
                  alignLabelWithHint: true,
                  prefixIcon: Icon(Icons.notes_rounded),
                ),
                validator: (value) => trimmedCodePoints(value ?? '') > FinanceFundTransferDialog.maxDescriptionLength
                    ? 'Açıklama en çok ${FinanceFundTransferDialog.maxDescriptionLength} karakter olabilir.'
                    : null,
              ),
              const SizedBox(height: AppSpace.sm),
              Text(
                'Aktarım nakit ya da banka hesaplarında hareket yazmaz; yalnız iki kasanın bakiyesini değiştirir. Yanlışsa '
                'silinmez: Kasalar Arası Aktarım Listesi\'nden gerekçeyle ters çevrilir.',
                style: th.bodySmall?.copyWith(color: p.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Kasalar Arası Aktarım Listesi": son aktarımlar (yeniden eskiye). Yazma yetkisi olan, ters çevrilmemiş asıl aktarımı
/// GEREKÇELİ onayla ters çevirebilir (silinmez; yönleri değişmiş, bugün tarihli ters aktarım yazılır). Kurul listeyi okur,
/// ters çevirme düğmesi görmez. Hata asla "aktarım yok" demez.
class FinanceFundTransfersDialog extends StatefulWidget {
  const FinanceFundTransfersDialog({super.key, required this.scope, this.onChanged});

  final PeopleScope scope;
  final VoidCallback? onChanged;

  static Future<void> show(BuildContext context, {required PeopleScope scope, VoidCallback? onChanged}) {
    return showDialog<void>(
      context: context,
      builder: (_) => FinanceFundTransfersDialog(scope: scope, onChanged: onChanged),
    );
  }

  @override
  State<FinanceFundTransfersDialog> createState() => _FinanceFundTransfersDialogState();
}

class _FinanceFundTransfersDialogState extends State<FinanceFundTransfersDialog> {
  bool _opening = false;

  late final CursorLoader<FundTransfer> _loader = CursorLoader<FundTransfer>(
    fetch: (before) async {
      final page = await widget.scope.f4Call((api, t, s) => api.listFundTransfers(token: t, siteCode: s, beforeId: before));
      return (items: page.items, next: page.nextBeforeId);
    },
    keyOf: (t) => t.id,
    notify: () {
      if (mounted) setState(() {});
    },
    isAlive: () => mounted,
    errorFallback: 'Aktarımlar yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
    moreErrorFallback: 'Daha fazla aktarım yüklenemedi. Tekrar deneyin.',
    messageOf: financeMessageOf,
  );

  @override
  void initState() {
    super.initState();
    unawaited(_loader.reload());
  }

  @override
  void dispose() {
    _loader.dispose();
    super.dispose();
  }

  Future<void> _reverse(FundTransfer transfer) async {
    if (_opening) return;
    _opening = true;
    try {
      final text =
          '${formatMinor(transfer.amountMinor)} tutarındaki aktarım ters çevrilir: ${transfer.toFund.shortLabel} → ${transfer.fromFund.shortLabel} '
          'yönünde bugün tarihli bir ters aktarım yazılır. Asıl kayıt silinmez.';
      final done = await FinanceReasonDialog.show(
        context,
        title: 'Aktarımı Ters Çevir',
        subtitle: '${transfer.fromFund.shortLabel} → ${transfer.toFund.shortLabel}',
        message: text,
        semanticMessage: spokenMoneyText(text),
        confirmLabel: 'Ters Çevir',
        reasonLabel: 'Gerekçe',
        signatureBase: 'fxfer-rev|${transfer.id}',
        keyPrefix: 'fxfer-r',
        keyOwner: widget.scope.authService,
        onUncertain: () {
          widget.onChanged?.call();
          if (mounted) unawaited(_loader.reload());
        },
        failure: 'Aktarım ters çevrilemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
        action: (reason, key) async {
          await widget.scope.f4Call(
            (api, t, s) => api.reverseFundTransfer(token: t, siteCode: s, transferId: transfer.id, reason: reason, idempotencyKey: key),
          );
        },
      );
      if (!mounted) return;
      if (done) {
        widget.onChanged?.call();
        showFinanceSnack(context, 'Aktarım ters çevrildi.');
        unawaited(_loader.reload());
      }
    } finally {
      _opening = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    return AppDialog(
      title: 'Kasalar Arası Aktarım Listesi',
      icon: Icons.swap_vert_rounded,
      actions: [
        TextButton(
          key: const ValueKey<String>('finance_fund_transfers_close'),
          onPressed: () => popIfCurrent(context),
          child: const Text('Kapat'),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(header: true, container: true, child: Text('Aktarımlar', style: th.titleMedium)),
              ),
              IconButton(
                tooltip: 'Yenile',
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                onPressed: _loader.loading ? null : () => unawaited(_loader.reload()),
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          CursorListBody<FundTransfer>(
            loader: _loader,
            emptyIcon: Icons.swap_vert_rounded,
            emptyTitle: 'Henüz kasalar arası aktarım yapılmamış.',
            skeletonRows: 2,
            itemBuilder: (context, transfer) => FundTransferTile(
              transfer: transfer,
              showActor: widget.scope.canWrite,
              onReverse: widget.scope.canWrite && transfer.canReverse ? () => _reverse(transfer) : null,
              busy: _opening,
            ),
          ),
        ],
      ),
    );
  }
}

/// Aktarım satırı: yön, tutar, tarih, açıklama ve ters çevirme durumu (ters çevrilmiş / ters aktarım + gerekçe).
class FundTransferTile extends StatelessWidget {
  const FundTransferTile({super.key, required this.transfer, this.showActor = false, this.onReverse, this.busy = false});

  final FundTransfer transfer;

  /// Kaydeden adı yalnız yazma yetkisi olan ekranda gösterilir (kurulda sunucu zaten göndermez).
  final bool showActor;
  final VoidCallback? onReverse;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final t = transfer;
    final route = '${t.fromFund.shortLabel} → ${t.toFund.shortLabel}';
    final semantic = StringBuffer('Kasalar arası aktarım: $route. ${moneySemanticLabel(t.amountMinor)}. ${formatCrmDate(t.transferDate)}.');
    if (t.description != null) semantic.write(' ${t.description}.');
    if (t.isReversal) semantic.write(' Ters aktarım.');
    if (t.isReversed) semantic.write(' Ters çevrildi.');
    if (t.reversalReason != null) semantic.write(' Gerekçe: ${t.reversalReason}.');
    return DialogPanel(
      key: ValueKey<String>('fund_transfer_${t.id}'),
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
                  if (t.isReversal || t.isReversed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpace.xs),
                      child: Wrap(
                        spacing: AppSpace.sm,
                        runSpacing: AppSpace.xs,
                        children: [
                          if (t.isReversal) const DialogMetaPill('Ters aktarım', tone: AppTone.warning, icon: Icons.undo_rounded),
                          if (t.isReversed)
                            const DialogMetaPill('Ters çevrildi', tone: AppTone.neutral, icon: Icons.block_rounded),
                        ],
                      ),
                    ),
                  Text(route, style: th.titleSmall),
                  Text(
                    formatMinor(t.amountMinor),
                    style: th.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      decoration: t.isReversed ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  Text(formatCrmDate(t.transferDate), style: th.bodySmall?.copyWith(color: p.textSecondary)),
                  if (t.description != null) Text(t.description!, style: th.bodyMedium),
                  if (t.reversalReason != null)
                    Text(
                      'Gerekçe: ${t.reversalReason}',
                      key: ValueKey<String>('fund_transfer_reason_${t.id}'),
                      style: th.bodyMedium?.copyWith(color: p.textSecondary),
                    ),
                  if (showActor && t.createdByName != null)
                    Text(
                      'Kaydeden: ${t.createdByName}${t.createdAt == null ? '' : ' • ${formatIstanbulDateTime(t.createdAt)}'}',
                      style: th.bodySmall?.copyWith(color: p.textSecondary),
                    ),
                ],
              ),
            ),
          ),
          if (onReverse != null) ...[
            const SizedBox(height: AppSpace.sm),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                key: ValueKey<String>('fund_transfer_reverse_${t.id}'),
                onPressed: busy ? null : onReverse,
                icon: const Icon(Icons.undo_rounded, size: 18),
                label: const Text('Ters Çevir'),
                style: TextButton.styleFrom(minimumSize: const Size(48, 48), foregroundColor: AppTone.danger.ink(p)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
