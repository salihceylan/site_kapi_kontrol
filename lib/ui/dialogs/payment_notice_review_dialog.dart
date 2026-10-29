// Yönetici karşılaştırma penceresi (Dalga 2 / 2B): solda dekont (görüntü ya da PDF'in ilk sayfası), sağda sakinin bildirdikleri, daire bilgisi ve uyarılar.
//
// Onay deftere tahsilat + makbuz yazar (dekont tarihiyle). Önemli uyarı varken onay, her biri işaretlenmeden AÇILMAZ. Yanlış daire: iptal edilir (neden "Yanlış daire"),
// tahsilat doğru daireye elle girilir. Dekontun ayı kapalıysa "Açık döneme yaz" ile bugünün tarihine işlenir; dekont tarihi açıklamada kalır.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/cash_models.dart';
import 'package:site_kapi_kontrol/models/finance.dart' show AccountParty;
import 'package:site_kapi_kontrol/models/finance_funds.dart';
import 'package:site_kapi_kontrol/models/payment_notice.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/payment_notice_api.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/date_input.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_4b_access.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_errors.dart';
import 'package:site_kapi_kontrol/ui/helpers/money.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/widgets/check_mark_panel.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_fund_choice_panel.dart';
import 'package:site_kapi_kontrol/ui/widgets/receipt_file_preview.dart';

/// Etkin kasa / banka hesapları (hata sessiz: liste boş kalır ve sunucu varsayılanı kullanır).
Future<List<CashAccount>> loadNoticeAccounts(PeopleScope scope) async {
  try {
    final overview = await scope.f4Call((api, t, s) => api.listAccounts(token: t, siteCode: s));
    return overview.activeAccounts;
  } catch (_) {
    return const <CashAccount>[];
  }
}

class PaymentNoticeReviewDialog extends StatefulWidget {
  const PaymentNoticeReviewDialog({super.key, required this.scope, required this.noticeId, this.accountsLoader = loadNoticeAccounts, this.fundChoiceLoader});

  final PeopleScope scope;
  final int noticeId;

  /// Kasa / banka hesapları yükleyicisi (testlerde sahte verilir).
  final Future<List<CashAccount>> Function(PeopleScope scope) accountsLoader;

  /// K3: İşletme / Fon hesabı bilgisi yükleyicisi (testlerde sahte verilir); null ise `GET payments/fund-choice`.
  final Future<FundChoiceInfo> Function({required int apartmentId, AccountParty? accountParty, int? amountMinor, DateTime? paidOn})? fundChoiceLoader;

  /// Karar verildiyse (onay / bağla / iptal) true.
  static Future<bool?> show(BuildContext context, PeopleScope scope, int noticeId) =>
      showDialog<bool>(context: context, builder: (_) => PaymentNoticeReviewDialog(scope: scope, noticeId: noticeId));

  @override
  State<PaymentNoticeReviewDialog> createState() => _PaymentNoticeReviewDialogState();
}

class _PaymentNoticeReviewDialogState extends State<PaymentNoticeReviewDialog> {
  NoticeDetail? _detail;
  String? _loadError;
  List<CashAccount> _accounts = const <CashAccount>[];
  final Set<String> _acknowledged = <String>{};
  String? _party;
  int? _accountId;
  bool _bookInOpen = false;
  bool _periodClosed = false;
  // K3: tahsilatın gireceği İşletme / Fon hesabı. İki türün de açık borcu varsa seçim ZORUNLU; tek türde önerilen hesap seçili gelir.
  FinanceFund? _fund;
  FundChoiceState _fundState = const FundChoiceState();
  FundChoiceInfo? _forcedFundInfo;
  bool _fundRequiredByServer = false;
  String? _fundError;
  bool _rejecting = false;
  String _reason = 'not_received';
  final _rejectNote = TextEditingController();
  bool _busy = false;
  String? _error;

  PaymentNoticeService get _service => PaymentNoticeService.of(widget.scope.authService);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _rejectNote.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final detail = await _service.run((api, token) => api.detail(token: token, siteCode: widget.scope.siteCode, id: widget.noticeId));
      final accounts = await widget.accountsLoader(widget.scope);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _accounts = accounts;
        _party = detail.notice.accountParty;
        if (accounts.length == 1) _accountId = accounts.first.id;
      });
    } catch (e) {
      if (mounted) setState(() => _loadError = financeMessageOf(e, 'Dekont yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.'));
    }
  }

  bool get _allAcknowledged => (_detail?.strongWarnings ?? const <NoticeWarning>[]).every((w) => _acknowledged.contains(w.code));

  Future<void> _run(Future<void> Function() action, String fallback) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = financeMessageOf(e, fallback);
        if (e is ApiException && e.code == 'NOTICE_PERIOD_CLOSED') _periodClosed = true;
        if (e is ApiException && e.code == 'NOTICE_WARNINGS_UNACKNOWLEDGED') unawaited(_load());
        // K3: iki türün de açık borcu var ve hesap seçilmedi (bilgi bayattı): sunucunun yetkili durumu panele işlenir, seçim istenir.
        if (e is ApiException && e.code == 'FUND_CHOICE_REQUIRED') {
          _forcedFundInfo = FundChoiceInfo.tryParse(e.payload?['fund_choice']);
          _fundRequiredByServer = true;
          _fundError = _fundMissingMessage;
        }
      });
    }
  }

  static const String _fundPendingMessage = 'İşletme / Fon hesabı bilgisi yükleniyor; birkaç saniye sonra yeniden deneyin.';
  static const String _fundMissingMessage = 'Ödemenin işleneceği İşletme / Fon hesabını seçin.';

  bool get _fundRequired => (_forcedFundInfo ?? _fundState.info)?.choiceRequired == true || _fundRequiredByServer;

  /// Daire hesabı değişti: önceki hesabın bilgisi / sunucu yanıtı geçmez.
  void _resetFundContext() {
    _forcedFundInfo = null;
    _fundRequiredByServer = false;
    _fundError = null;
  }

  Future<void> _approve() {
    // K3: bilgi yüklenirken gönderilmez (önerilen hesap seçili gelmeden onay kısıtsız giderdi); iki türlü borçta seçim olmadan gönderilmez.
    if (_fundState.loading) {
      setState(() => _error = _fundPendingMessage);
      return Future<void>.value();
    }
    if (_fundRequired && _fund == null) {
      setState(() {
        _error = null;
        _fundError = _fundMissingMessage;
      });
      return Future<void>.value();
    }
    return _run(
      () => _service.run(
        (api, token) => api.approve(
          token: token,
          siteCode: widget.scope.siteCode,
          id: widget.noticeId,
          accountId: _accountId,
          accountParty: _party,
          fund: _fund,
          bookInOpenPeriod: _bookInOpen,
          acknowledged: _acknowledged.toList(),
        ),
      ),
      'Onaylanamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.',
    );
  }

  Future<void> _reject() => _run(
    () => _service.run(
      (api, token) => api.reject(token: token, siteCode: widget.scope.siteCode, id: widget.noticeId, reasonCode: _reason, note: _rejectNote.text),
    ),
    'İptal edilemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
  );

  Future<void> _link(NoticeRecentPayment payment) => _run(
    () => _service.run((api, token) => api.link(token: token, siteCode: widget.scope.siteCode, id: widget.noticeId, ledgerEntryId: payment.id)),
    'Bağlanamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.',
  );

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    return AlertDialog(
      key: const ValueKey<String>('notice_review'),
      title: const Text('Dekont incelemesi'),
      content: SizedBox(
        width: 860,
        child: detail == null
            ? _loadError != null
                ? Column(mainAxisSize: MainAxisSize.min, children: [Text(_loadError!), TextButton(onPressed: _load, child: const Text('Tekrar dene'))])
                : const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()))
            : _body(context, detail),
      ),
      actions: [
        TextButton(key: const ValueKey<String>('notice_review_close'), onPressed: _busy ? null : () => Navigator.of(context).pop(false), child: const Text('Kapat')),
        if (detail != null && detail.notice.isPending) ...[
          if (_rejecting)
            PrimaryActionButton(
              key: const ValueKey<String>('notice_review_confirm_reject'),
              label: 'İptali onayla',
              icon: Icons.block_rounded,
              tone: AppTone.danger,
              expand: false,
              loading: _busy,
              onPressed: _busy ? null : _reject,
            )
          else ...[
            OutlinedButton(key: const ValueKey<String>('notice_review_reject'), onPressed: _busy ? null : () => setState(() => _rejecting = true), child: const Text('İptal et')),
            PrimaryActionButton(
              key: const ValueKey<String>('notice_review_approve'),
              label: 'Onayla - ${formatMinor(detail.notice.amountMinor)}',
              icon: Icons.check_circle_rounded,
              expand: false,
              loading: _busy,
              onPressed: _busy || !_allAcknowledged ? null : _approve,
            ),
          ],
        ],
      ],
    );
  }

  Widget _body(BuildContext context, NoticeDetail detail) {
    final left = _preview(detail.notice);
    final right = _details(context, detail);
    return LayoutBuilder(
      builder: (context, c) => SingleChildScrollView(
        child: c.maxWidth >= 720
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: left), const SizedBox(width: AppSpace.lg), Expanded(child: right)])
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [left, const SizedBox(height: AppSpace.lg), right]),
      ),
    );
  }

  Widget _preview(PaymentNotice n) {
    if (!n.hasFile) {
      return const Padding(
        padding: EdgeInsets.all(AppSpace.lg),
        child: Text('Bu kayıtta dosya yok (elden girilmiş makbuz).', key: ValueKey<String>('notice_no_file')),
      );
    }
    return ReceiptFilePreview(
      load: () => _service.run((api, token) => api.file(token: token, siteCode: widget.scope.siteCode, id: n.id)),
      isPdf: n.isPdf,
    );
  }

  Widget _row(String label, String value, {Key? key}) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 120, child: Text(label, style: th.bodySmall?.copyWith(color: p.textSecondary))),
          Expanded(child: Text(value, key: key, style: th.bodyMedium)),
        ],
      ),
    );
  }

  Widget _details(BuildContext context, NoticeDetail detail) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final n = detail.notice;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Sakinin bildirdikleri', style: th.titleSmall),
        const SizedBox(height: AppSpace.xs),
        _row('Daire', n.apartmentLabel),
        _row('Tutar', formatMinor(n.amountMinor), key: const ValueKey<String>('notice_review_amount')),
        _row('Ödeme tarihi', formatDateField(n.paidOn)),
        _row('Yöntem', kNoticeMethods[n.method] ?? n.method),
        if (n.senderName != null) _row('Gönderen', n.senderName!),
        if (n.senderIban != null) _row('Gönderen IBAN', n.senderIban!),
        if (n.description != null) _row('Açıklama', n.description!),
        if (n.note != null) _row('Not', n.note!),
        _row('Giriş', n.fromManager ? 'Yönetim (elden)' : 'Sakin'),
        const SizedBox(height: AppSpace.md),
        Text('Daire bilgisi', style: th.titleSmall),
        const SizedBox(height: AppSpace.xs),
        if (detail.people.isEmpty) const Text('Dairede kayıtlı kişi yok.') else for (final person in detail.people) _row(person.relationLabel, person.name),
        _row('Ev sahibi hesabı', formatMinor(detail.ownerBalanceMinor)),
        _row('Kiracı hesabı', formatMinor(detail.tenantBalanceMinor)),
        if (detail.recent.isNotEmpty) ...[
          const SizedBox(height: AppSpace.xs),
          Text('Son tahsilatlar', style: th.bodySmall?.copyWith(color: p.textSecondary)),
          for (final r in detail.recent)
            Row(
              children: [
                Expanded(child: Text('${formatCrmDate(r.date)}  ${formatMinor(r.amountMinor)}', style: th.bodyMedium)),
                if (n.isPending && detail.warnings.any((w) => w.code == 'POSSIBLE_DUPLICATE'))
                  TextButton(key: ValueKey<String>('notice_link_${r.id}'), onPressed: _busy ? null : () => _link(r), child: const Text('Bu tahsilata bağla')),
              ],
            ),
        ],
        if (detail.warnings.isNotEmpty) ...[
          const SizedBox(height: AppSpace.md),
          Text('Uyarılar', style: th.titleSmall),
          for (final w in detail.warnings)
            if (w.strong)
              CheckboxListTile(
                key: ValueKey<String>('notice_warning_${w.code}'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _acknowledged.contains(w.code),
                onChanged: _busy ? null : (v) => setState(() => v == true ? _acknowledged.add(w.code) : _acknowledged.remove(w.code)),
                title: Text(noticeWarningText(w), style: th.bodyMedium),
                subtitle: const Text('Gözden geçirdim'),
              )
            else
              ListTile(
                key: ValueKey<String>('notice_warning_${w.code}'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.info_outline_rounded),
                title: Text(noticeWarningText(w), style: th.bodyMedium),
              ),
        ],
        if (n.isPending && !_rejecting) ...[
          const SizedBox(height: AppSpace.md),
          Text('Nasıl işlensin?', style: th.titleSmall),
          const SizedBox(height: AppSpace.xs),
          DropdownButtonFormField<String>(
            key: const ValueKey<String>('notice_party'),
            initialValue: _party,
            decoration: const InputDecoration(labelText: 'Hangi hesaptan düşsün'),
            items: const [DropdownMenuItem(value: 'owner', child: Text('Ev sahibi hesabı')), DropdownMenuItem(value: 'tenant', child: Text('Kiracı hesabı'))],
            onChanged: _busy
                ? null
                : (v) => setState(() {
                    if (_party != v) _resetFundContext();
                    _party = v;
                  }),
          ),
          if (_party != n.accountParty)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.xs),
              child: Text('Sakin ${n.accountLabel.toLowerCase()} için bildirdi; hesap değişikliği kayda geçer.', style: th.bodySmall?.copyWith(color: p.textSecondary)),
            ),
          if (_accounts.isNotEmpty) ...[
            const SizedBox(height: AppSpace.sm),
            DropdownButtonFormField<int?>(
              key: const ValueKey<String>('notice_account'),
              initialValue: _accountId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Tahsilat hesabı (kasa / banka)'),
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text('Ayarlardaki sakin hesabı')),
                for (final a in _accounts) DropdownMenuItem<int?>(value: a.id, child: Text(a.name, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: _busy ? null : (v) => setState(() => _accountId = v),
            ),
          ],
          const SizedBox(height: AppSpace.sm),
          FundChoicePanel(
            key: const ValueKey<String>('notice_fund'),
            scope: widget.scope,
            apartmentId: n.apartmentId,
            accountParty: AccountParty.tryParse(_party),
            amountMinor: n.amountMinor,
            paidOn: n.paidOn,
            selected: _fund,
            enabled: !_busy,
            loader: widget.fundChoiceLoader,
            forcedInfo: _forcedFundInfo,
            errorText: _fundError,
            keyPrefix: 'notice_fund',
            onChanged: (value) => setState(() {
              _fund = value;
              _fundError = null;
            }),
            onStateChanged: (state) {
              if (mounted && state != _fundState) setState(() => _fundState = state);
            },
          ),
          if (_periodClosed)
            CheckboxListTile(
              key: const ValueKey<String>('notice_book_open'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _bookInOpen,
              onChanged: _busy ? null : (v) => setState(() => _bookInOpen = v == true),
              title: const Text('Açık döneme yaz'),
              subtitle: const Text('Tahsilat bugünün tarihiyle işlenir; dekont tarihi açıklamada kalır.'),
            ),
        ],
        if (_rejecting) ...[
          const SizedBox(height: AppSpace.md),
          Text('İptal nedeni (sakine gösterilir)', style: th.titleSmall),
          DropdownButtonFormField<String>(
            key: const ValueKey<String>('notice_reason'),
            initialValue: _reason,
            decoration: const InputDecoration(labelText: 'Neden'),
            items: [for (final e in kNoticeRejectReasons.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
            onChanged: _busy ? null : (v) => setState(() => _reason = v ?? 'other'),
          ),
          TextField(key: const ValueKey<String>('notice_reject_note'), controller: _rejectNote, enabled: !_busy, maxLength: 300, decoration: const InputDecoration(labelText: 'Not (isteğe bağlı)')),
          if (_reason == 'wrong_apartment')
            Text('Tahsilatı doğru daireye Tahsilat Ekle ile elle girin.', style: th.bodySmall?.copyWith(color: p.textSecondary)),
        ],
        if (!n.isPending) ...[
          const SizedBox(height: AppSpace.md),
          Text('Karar: ${n.status.label}${n.rejectReasonCode == null ? '' : ' (${kNoticeRejectReasons[n.rejectReasonCode] ?? ''})'}', style: th.titleSmall),
        ],
        // Kontrol izi (P2-20): onay / iptal kararından AYRI muhasebe kontrolü; karar akışını ve bu pencerenin kapanışını etkilemez.
        if (n.canBeChecked) ...[
          const SizedBox(height: AppSpace.md),
          CheckMarkPanel(
            key: ValueKey<String>('notice_check_${n.id}'),
            mark: n.checkMark,
            canWrite: widget.scope.canWrite,
            hint: 'Onay ya da iptal kararından ayrı, muhasebe kontrolü içindir.',
            onSet: () => _service.run((api, token) => api.setCheck(token: token, siteCode: widget.scope.siteCode, id: n.id)),
            onClear: () => _service.run((api, token) => api.clearCheck(token: token, siteCode: widget.scope.siteCode, id: n.id)),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: AppSpace.md),
          Text(_error!, key: const ValueKey<String>('notice_review_error'), style: th.bodyMedium?.copyWith(color: AppTone.danger.ink(p))),
        ],
      ],
    );
  }
}
