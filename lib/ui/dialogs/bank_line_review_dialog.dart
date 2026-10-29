// Banka satırlarını TEK TEK gözden geçir (C-26): önerilen dairesi olan satırlar sırayla gösterilir; her biri için Onayla / Atla. Toplu onaydan ÖNCE
// satır satır inceleme akışıdır: yükleme sırasında "güçlü eşleşmeleri de tek tek gözden geçir" seçilmişse (ya da kontrol edilecek satırlar için) kullanılır.
// K3 (P1-3): iki türün de (İşletme / Fon) açık borcu olan dairede hesap bu adımda SEÇİLİR; tek türde önerilen hesap seçili gelir. Onay,
// "Daireye işle" ile aynı uçtan geçer (satırın önerilen dairesi + hesabı + seçilen İşletme / Fon hesabı). Atlanan satır beklemeye devam eder.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/bank_import.dart';
import 'package:site_kapi_kontrol/models/finance.dart' show AccountParty;
import 'package:site_kapi_kontrol/models/finance_funds.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/bank_import_api.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/money.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_fund_choice_panel.dart';

/// İncelenecek satırlar: önerilen dairesi olan, gelen paralı, bekleyen satırlar.
List<BankLineItem> reviewableBankLines(Iterable<BankLineItem> lines) => <BankLineItem>[
  for (final l in lines)
    if (l.status == 'suggested' && l.apartmentId != null && l.incoming) l,
];

class BankLineReviewDialog extends StatefulWidget {
  const BankLineReviewDialog({super.key, required this.scope, required this.lines, this.fundChoiceLoader});

  final PeopleScope scope;
  final List<BankLineItem> lines;

  /// K3: İşletme / Fon hesabı bilgisi yükleyicisi (testlerde sahte verilir); null ise `GET payments/fund-choice`.
  final Future<FundChoiceInfo> Function({required int apartmentId, AccountParty? accountParty, int? amountMinor, DateTime? paidOn})? fundChoiceLoader;

  /// Kapanışta işlenen satır sayısını döner (0: hiçbiri).
  static Future<int> show(
    BuildContext context, {
    required PeopleScope scope,
    required List<BankLineItem> lines,
    Future<FundChoiceInfo> Function({required int apartmentId, AccountParty? accountParty, int? amountMinor, DateTime? paidOn})? fundChoiceLoader,
  }) async {
    final r = await showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (_) => BankLineReviewDialog(scope: scope, lines: reviewableBankLines(lines), fundChoiceLoader: fundChoiceLoader),
    );
    return r ?? 0;
  }

  @override
  State<BankLineReviewDialog> createState() => _BankLineReviewDialogState();
}

class _BankLineReviewDialogState extends State<BankLineReviewDialog> {
  int _index = 0;
  int _done = 0;
  int _skipped = 0;
  bool _busy = false;
  String? _error;

  FinanceFund? _fund;
  FundChoiceState _fundState = const FundChoiceState();
  FundChoiceInfo? _forcedFundInfo;
  bool _fundRequiredByServer = false;
  String? _fundError;

  static const String _fundPendingMessage = 'İşletme / Fon hesabı bilgisi yükleniyor; birkaç saniye sonra yeniden deneyin.';
  static const String _fundMissingMessage = 'Ödemenin işleneceği İşletme / Fon hesabını seçin.';

  bool get _finished => _index >= widget.lines.length;
  BankLineItem get _line => widget.lines[_index];
  bool get _fundRequired => (_forcedFundInfo ?? _fundState.info)?.choiceRequired == true || _fundRequiredByServer;

  void _next() {
    setState(() {
      _index += 1;
      _error = null;
      _fund = null;
      _fundState = const FundChoiceState();
      _forcedFundInfo = null;
      _fundRequiredByServer = false;
      _fundError = null;
    });
  }

  void _skip() {
    if (_busy) return;
    _skipped += 1;
    _next();
  }

  Future<void> _approve() async {
    if (_busy || _finished) return;
    if (_fundState.loading) {
      setState(() => _error = _fundPendingMessage);
      return;
    }
    if (_fundRequired && _fund == null) {
      setState(() {
        _error = null;
        _fundError = _fundMissingMessage;
      });
      return;
    }
    final line = _line;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await BankImportService.of(widget.scope.authService).run(
        (api, token) => api.assignLine(
          token: token,
          siteCode: widget.scope.siteCode,
          lineId: line.id,
          apartmentId: line.apartmentId!,
          party: line.party,
          fund: _fund,
        ),
      );
      if (!mounted) return;
      _done += 1;
      setState(() => _busy = false);
      _next();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
        if (e.code == 'FUND_CHOICE_REQUIRED') {
          _forcedFundInfo = FundChoiceInfo.tryParse(e.payload?['fund_choice']);
          _fundRequiredByServer = true;
          _fundError = _fundMissingMessage;
        }
      });
    }
  }

  Widget _summary(BuildContext context) {
    final th = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Gözden geçirme bitti.', key: const ValueKey<String>('bank_review_finished'), style: th.titleSmall),
        const SizedBox(height: AppSpace.sm),
        Text('$_done satır işlendi, $_skipped satır atlandı (beklemeye devam eder).'),
      ],
    );
  }

  Widget _step(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final line = _line;
    final partyText = line.party == 'tenant' ? ' (kiracı)' : (line.party == 'owner' ? ' (ev sahibi)' : '');
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(line.valueDate, style: th.bodySmall)),
            Text(formatSignedMinor(line.amountMinor), style: th.titleSmall),
          ],
        ),
        if (line.counterpartyName != null) Text(line.counterpartyName!, style: th.bodyMedium),
        if (line.description.isNotEmpty) Text(line.description, style: th.bodySmall, maxLines: 3, overflow: TextOverflow.ellipsis),
        const SizedBox(height: AppSpace.sm),
        Text('Öneri: ${line.apartmentLabel ?? 'Daire'}$partyText', key: const ValueKey<String>('bank_review_suggestion'), style: th.bodyMedium),
        if (line.note == 'REVIEW_EACH') Text('Güçlü eşleşme; tek tek onayınız istendi.', style: th.bodySmall),
        if (line.note == 'POSSIBLE_DUPLICATE_PAYMENT') Text('Aynı tutar ve tarihte başka bir banka satırının tahsilatı var; çift tahsilat olmasın diye kontrol edin.', style: th.bodySmall),
        const SizedBox(height: AppSpace.md),
        FundChoicePanel(
          // satır değişince panel baştan kurulur (önceki satırın hesabı / seçimi geçmez)
          key: ValueKey<String>('bank_review_fund_${line.id}'),
          scope: widget.scope,
          apartmentId: line.apartmentId,
          accountParty: AccountParty.tryParse(line.party),
          amountMinor: line.amountMinor > 0 ? line.amountMinor : null,
          paidOn: DateTime.tryParse(line.valueDate),
          selected: _fund,
          enabled: !_busy,
          loader: widget.fundChoiceLoader,
          forcedInfo: _forcedFundInfo,
          errorText: _fundError,
          keyPrefix: 'bank_review_fund',
          onChanged: (value) => setState(() {
            _fund = value;
            _fundError = null;
          }),
          onStateChanged: (state) {
            if (mounted && state != _fundState) setState(() => _fundState = state);
          },
        ),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: AppSpace.sm), child: Text(_error!, key: const ValueKey<String>('bank_review_error'), style: TextStyle(color: Theme.of(context).colorScheme.error))),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.lines.length;
    final finished = _finished;
    return AlertDialog(
      key: const ValueKey<String>('bank_review'),
      title: Text(total == 0 ? 'Tek tek gözden geçir' : (finished ? 'Tek tek gözden geçir' : 'Tek tek gözden geçir (${_index + 1} / $total)')),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: total == 0
              ? const Text('Gözden geçirilecek önerili satır yok.', key: ValueKey<String>('bank_review_empty'))
              : (finished ? _summary(context) : _step(context)),
        ),
      ),
      actions: [
        if (total == 0 || finished)
          FilledButton(key: const ValueKey<String>('bank_review_close'), onPressed: () => Navigator.of(context).pop(_done), child: const Text('Kapat'))
        else ...[
          TextButton(key: const ValueKey<String>('bank_review_close'), onPressed: _busy ? null : () => Navigator.of(context).pop(_done), child: const Text('Kapat')),
          OutlinedButton(key: const ValueKey<String>('bank_review_skip'), onPressed: _busy ? null : _skip, child: const Text('Atla')),
          FilledButton(key: const ValueKey<String>('bank_review_approve'), onPressed: _busy ? null : () => unawaited(_approve()), child: Text(_busy ? 'İşleniyor…' : 'Onayla')),
        ],
      ],
    );
  }
}
