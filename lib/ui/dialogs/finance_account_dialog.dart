import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/finance.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/finance_payment_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/finance_reminder_exempt_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/finance_receipt_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/finance_receipt_flow.dart';
import 'package:site_kapi_kontrol/ui/dialogs/finance_receipt_list_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/finance_reverse_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/large_dialog_parts.dart';
import 'package:site_kapi_kontrol/ui/helpers/cursor_loader.dart';
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_4b_access.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_errors.dart';
import 'package:site_kapi_kontrol/ui/helpers/money.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/widgets/cursor_list_body.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_4b_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_account_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_fund_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_parts.dart';

/// Daire hesap ekstresi penceresi (Platform Faz 4a): güncel bakiye (borç / alacak simge + metinle), vadesi
/// geçen tutar, kim öder ve hareketler (en yeni üstte; "Daha fazla yükle" `before_id` imleciyle).
///
/// - Ters kayıtlar işaretlidir: iptal edilen kayıt "İptal edildi" rozeti ve üstü çizili tutarla, ters kayıt
///   "Ters kayıt" rozeti ve nedeniyle gösterilir. Silme YOKTUR.
/// - Yazma eylemleri (Tahsilat Ekle, Düzelt, İptal Et) YALNIZ [PeopleScope.canWrite] iken vardır; kurul üyesi
///   salt okur. Her yazmadan sonra ekstre yeniden okunur ve [onChanged] çağrılır (liste / özet tazelenir).
/// - Hata asla "borç yok / hareket yok" demez: bakiye okunamadıysa hata + "Tekrar Dene" gösterilir; eski /
///   yavaş yanıt yenisini ezmez ([CursorLoader] jetonu ve başlık sırası).
/// - Faz 4b: tahsilattan sonra makbuz penceresi açılır; makbuzu olan satırda "Makbuz MK-..." ve makbuzu olmayan
///   (otomatik düzenleme kapalıyken ya da eski) tahsilatta yönetici için "Makbuz Düzenle" vardır; "Makbuzlar" bu
///   dairenin makbuz listesini açar (kurul da okur); yönetici "Hatırlatmadan Muaf Tut" ile daireyi borç hatırlatmalarından
///   muaf tutar / muafiyeti kaldırır (spec §7).
/// - İki hesap (İP-1A): dairenin "Ev sahibi hesabı" ve "Kiracı hesabı" ayrıdır. Sunucu kiracı sekmesini istiyorsa
///   (`show_tenant_account`) iki sekme görünür ([Kiracı hesabı] [Ev sahibi hesabı]); bakiye ve hareketler yalnız seçili
///   hesabındır. İlk sekme sunucunun varsayılan tahsilat hesabıdır. Tahsilat / düzeltme penceresi seçili hesapla açılır.
///   Eski sunucuda ya da kiracısı hiç olmamış dairede sekme yoktur (tek hesap, eski görünüm).
/// - İki kasa: başlıkta kasa bazında açık borç / vadesi geçen / avans (seçili hesabın; sekmesiz dairede iki hesabın toplamı),
///   hareket satırlarında kasa rozeti ve tahsilat satırında kasalara dağılım gösterilir (sunucu `funds` göndermediyse
///   kırılım hiç çizilmez).
class FinanceAccountDialog extends StatefulWidget {
  const FinanceAccountDialog({
    super.key,
    required this.scope,
    required this.apartmentId,
    this.initialLabel = '',
    this.onChanged,
    this.now,
  });

  final PeopleScope scope;
  final int apartmentId;

  /// Ekstre gelene kadar başlıkta görünen daire adı (listeden).
  final String initialLabel;
  final VoidCallback? onChanged;
  final DateTime Function()? now;

  static Future<void> show(
    BuildContext context, {
    required PeopleScope scope,
    required int apartmentId,
    String initialLabel = '',
    VoidCallback? onChanged,
    DateTime Function()? now,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => FinanceAccountDialog(
        scope: scope,
        apartmentId: apartmentId,
        initialLabel: initialLabel,
        onChanged: onChanged,
        now: now,
      ),
    );
  }

  @override
  State<FinanceAccountDialog> createState() => _FinanceAccountDialogState();
}

class _FinanceAccountDialogState extends State<FinanceAccountDialog> {
  AccountView? _header;
  int _headerSeq = 0;
  bool _opening = false;
  bool _issuing = false;
  String? _actionError;

  /// Seçili hesap sekmesi (İP-1A); null: tek hesap (eski sunucu / kiracı sekmesi yok) ya da ilk yanıt henüz gelmedi.
  AccountParty? _party;

  Future<AccountView> _get(int? before) => widget.scope.authService.getFinanceAccount(
    widget.scope.siteCode,
    widget.apartmentId,
    beforeId: before,
    accountParty: _party,
  );

  late final CursorLoader<LedgerEntry> _loader = CursorLoader<LedgerEntry>(
    fetch: (before) async {
      // Başlık yalnız İLK sayfadan ve yalnız EN SON isteğin yanıtından alınır (eski yanıt yenisini ezmez).
      final seq = before == null ? ++_headerSeq : _headerSeq;
      try {
        var view = await _get(before);
        if (before == null && _party == null && view.hasTwoAccounts) {
          // İki hesaplı daire: süzgeçsiz ilk yanıt yalnız sekme bilgisini verir; liste ve bakiye SEÇİLİ hesabındır
          // (hesaplar karışık gösterilmez). İlk sekme sunucunun varsayılan tahsilat hesabıdır.
          _party = view.defaultPaymentAccount ?? (view.hasCurrentTenant ? AccountParty.tenant : AccountParty.owner);
          view = await _get(null);
        }
        if (before == null && seq == _headerSeq && mounted) _header = view;
        return (items: view.items, next: view.nextBeforeId);
      } catch (_) {
        // İlk sayfa okunamadı: eski bakiye gösterilmez (yazmadan önceki tutar yanıltmasın).
        if (before == null && seq == _headerSeq && mounted) _header = null;
        rethrow;
      }
    },
    keyOf: (e) => e.id,
    notify: () {
      if (mounted) setState(() {});
    },
    isAlive: () => mounted,
    errorFallback: 'Ekstre yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
    moreErrorFallback: 'Daha fazla hareket yüklenemedi. Tekrar deneyin.',
    messageOf: financeMessageOf,
  );

  bool get _canWrite => widget.scope.canWrite;

  @override
  void initState() {
    super.initState();
    unawaited(_loader.reload());
  }

  @override
  void dispose() {
    ++_headerSeq;
    _loader.dispose();
    super.dispose();
  }

  void _afterChange(String? message) {
    widget.onChanged?.call();
    if (!mounted) return;
    if (message != null) showFinanceSnack(context, message);
    unawaited(_loader.reload());
  }

  /// Belirsiz sonuç / eskimiş kayıt: ekstre ve üst liste tazelenir (mesaj yok).
  void _refreshOnly() {
    widget.onChanged?.call();
    if (mounted) unawaited(_loader.reload());
  }

  /// Hesap sekmesi değişti: liste ve bakiye o hesabın ilk sayfasıyla yeniden okunur (eski hesabın uçuştaki yanıtı yok sayılır).
  void _selectParty(AccountParty party) {
    if (party == _party || _opening || _issuing) return;
    setState(() {
      _party = party;
      _actionError = null;
    });
    unawaited(_loader.reload());
  }

  /// Tahsilat penceresine verilen hesap bilgisi: iki hesaplı dairede seçim gösterilir (seçili sekmeyle başlar), tek hesapta yok.
  bool get _twoAccounts => _header?.hasTwoAccounts ?? false;

  Future<void> _addPayment() async {
    if (_opening) return;
    _opening = true;
    final FinancePaymentOutcome? outcome;
    try {
      outcome = await FinancePaymentDialog.show(
        context,
        scope: widget.scope,
        apartmentId: widget.apartmentId,
        apartmentLabel: _title,
        now: widget.now,
        onRefreshNeeded: _refreshOnly,
        accountParty: _twoAccounts ? _party : null,
        accountChoice: _twoAccounts,
      );
    } finally {
      _opening = false;
    }
    if (outcome == null) return;
    _afterChange(outcome.message);
    await _showReceipt(outcome);
  }

  /// Tahsilat sonrası makbuz penceresi (makbuz varsa).
  Future<void> _showReceipt(FinancePaymentOutcome outcome) async {
    if (!mounted || outcome.result.receipt == null) return;
    _opening = true;
    try {
      await openReceiptAfterPayment(context, scope: widget.scope, outcome: outcome, onChanged: _refreshOnly);
    } finally {
      _opening = false;
    }
  }

  Future<void> _openReceipt(LedgerEntry entry) async {
    final ref = entry.receipt;
    if (ref == null || _opening || _issuing) return;
    _opening = true;
    try {
      await FinanceReceiptDialog.show(
        context,
        scope: widget.scope,
        receiptId: ref.id,
        initialNumber: ref.number,
        onChanged: _refreshOnly,
      );
    } finally {
      _opening = false;
    }
  }

  Future<void> _openReceipts() async {
    if (_opening || _issuing) return;
    _opening = true;
    try {
      await FinanceReceiptListDialog.show(
        context,
        scope: widget.scope,
        apartmentId: widget.apartmentId,
        apartmentLabel: _title,
        now: widget.now,
        onChanged: _refreshOnly,
      );
    } finally {
      _opening = false;
    }
  }

  /// Daireyi borç hatırlatmalarından muaf tutar / muafiyeti kaldırır (spec §7; durum sunucudan okunur).
  Future<void> _openExempt() async {
    if (_opening || _issuing) return;
    _opening = true;
    final String? message;
    try {
      message = await FinanceReminderExemptDialog.show(
        context,
        scope: widget.scope,
        apartmentId: widget.apartmentId,
        apartmentLabel: _title,
      );
    } finally {
      _opening = false;
    }
    if (message == null || !mounted) return;
    widget.onChanged?.call();
    showFinanceSnack(context, message);
  }

  /// Makbuzu olmayan tahsilat için makbuz düzenler (sunucuda idempotent: aktif makbuz varsa onu döndürür).
  Future<void> _issueReceipt(LedgerEntry entry) async {
    if (_opening || _issuing) return;
    setState(() {
      _issuing = true;
      _actionError = null;
    });
    try {
      final result = await widget.scope.f4Call((api, t, s) => api.issueReceipt(token: t, siteCode: s, entryId: entry.id));
      if (!mounted) return;
      setState(() => _issuing = false);
      widget.onChanged?.call();
      unawaited(_loader.reload());
      _opening = true;
      try {
        await FinanceReceiptDialog.show(
          context,
          scope: widget.scope,
          receiptId: result.receipt.id,
          initialNumber: result.receipt.number,
          justIssued: result.created,
          onChanged: _refreshOnly,
        );
      } finally {
        _opening = false;
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _issuing = false;
        _actionError = financeWriteMessage(
          e,
          'Makbuz düzenlenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
          hint: kFinanceUncertainStateHint,
        );
      });
      // Durum değişmiş olabilir (makbuz başkası tarafından düzenlenmiş vb.): ekstre yeniden okunur.
      unawaited(_loader.reload());
    }
  }

  Future<void> _correct(LedgerEntry entry) async {
    if (_opening) return;
    _opening = true;
    final FinancePaymentOutcome? outcome;
    try {
      outcome = await FinancePaymentDialog.show(
        context,
        scope: widget.scope,
        apartmentId: widget.apartmentId,
        apartmentLabel: _title,
        correcting: entry,
        now: widget.now,
        onRefreshNeeded: _refreshOnly,
        // İP-1A: düzeltme eski tahsilatın hesabıyla başlar; iki hesaplı dairede diğer hesaba taşınabilir
        accountParty: _twoAccounts ? (entry.accountParty ?? _party) : null,
        accountChoice: _twoAccounts,
      );
    } finally {
      _opening = false;
    }
    if (outcome == null) return;
    _afterChange(outcome.message);
    await _showReceipt(outcome);
  }

  Future<void> _reverse(LedgerEntry entry) async {
    if (_opening) return;
    _opening = true;
    final FinanceReverseOutcome? outcome;
    try {
      outcome = await FinanceReverseDialog.show(
        context,
        scope: widget.scope,
        entry: entry,
        apartmentLabel: _title,
        onRefreshNeeded: _refreshOnly,
      );
    } finally {
      _opening = false;
    }
    if (outcome != null) _afterChange(outcome.message);
  }

  /// Makbuz düzenlenebilir tahsilat: iptal edilmemiş, ters kayıt olmayan ve AKTİF makbuzu bulunmayan ödeme. Makbuzu
  /// "hatalı düzenlendi" diye iptal edilmiş ödeme için yeni makbuz düzenlenebilir (iptal penceresinin vaadi; sunucu izin verir).
  static bool _canIssueReceipt(LedgerEntry e) =>
      e.kind == LedgerKind.payment && !e.isOpeningCredit && !e.isReversal && !e.isReversed && (e.receipt == null || e.receipt!.isCancelled);

  String get _title {
    final header = _header;
    if (header != null) {
      final text = financeApartmentTitle(header.apartment.blockName, header.apartment.label);
      if (text != '-') return text;
    }
    final initial = widget.initialLabel.trim();
    return initial.isEmpty ? 'Daire' : initial;
  }

  @override
  Widget build(BuildContext context) {
    final header = _header;
    final related = <int, LedgerEntry>{for (final item in _loader.items) item.id: item};
    return AppDialog(
      title: 'Hesap Ekstresi',
      subtitle: _title,
      icon: Icons.receipt_long_rounded,
      actions: [
        TextButton(
          onPressed: () => popIfCurrent(context),
          child: const Text('Kapat'),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (header != null && header.hasTwoAccounts && _party != null) ...[
            AccountPartyTabs(
              key: const ValueKey<String>('finance_account_tabs'),
              selected: _party!,
              onSelected: _selectParty,
              enabled: !_opening && !_issuing,
              totals: <AccountParty, AccountTotals?>{
                AccountParty.owner: header.ownerAccount,
                AccountParty.tenant: header.tenantAccount,
              },
            ),
            const SizedBox(height: AppSpace.md),
          ],
          if (header != null) _buildHeader(context, header),
          if (header != null && _canWrite) ...[
            const SizedBox(height: AppSpace.md),
            PrimaryActionButton(
              key: const ValueKey<String>('finance_account_add_payment'),
              label: 'Tahsilat Ekle',
              icon: Icons.add_card_rounded,
              onPressed: _addPayment,
            ),
          ],
          if (header != null) ...[
            const SizedBox(height: AppSpace.sm),
            PrimaryActionButton(
              key: const ValueKey<String>('finance_account_receipts'),
              label: 'Makbuzlar',
              icon: Icons.receipt_long_rounded,
              variant: AppButtonVariant.tonal,
              onPressed: _opening || _issuing ? null : _openReceipts,
            ),
          ],
          if (header != null && _canWrite) ...[
            const SizedBox(height: AppSpace.sm),
            PrimaryActionButton(
              key: const ValueKey<String>('finance_account_reminder_exempt'),
              label: 'Hatırlatmadan Muaf Tut',
              icon: Icons.do_not_disturb_on_rounded,
              variant: AppButtonVariant.tonal,
              onPressed: _opening || _issuing ? null : _openExempt,
            ),
          ],
          if (_actionError != null) ...[
            const SizedBox(height: AppSpace.md),
            FinanceSubmitError(key: const ValueKey<String>('finance_account_action_error'), message: _actionError!),
          ],
          const SizedBox(height: AppSpace.md),
          Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  container: true,
                  child: Text('Hareketler', style: Theme.of(context).textTheme.titleMedium),
                ),
              ),
              IconButton(
                tooltip: 'Yenile',
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                onPressed: _loader.loading ? null : () => unawaited(_loader.reload()),
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          // Bakiye henüz okunamadıysa hata gövdede gösterilir; hareket listesi bakiye olmadan "hareket yok"
          // demez (CursorListBody hata / yükleme durumunu boş durumdan önce çizer).
          CursorListBody<LedgerEntry>(
            loader: _loader,
            emptyIcon: Icons.receipt_long_rounded,
            emptyTitle: 'Bu dairede henüz mali hareket yok.',
            skeletonRows: 2,
            itemBuilder: (context, entry) => Padding(
              padding: EdgeInsets.zero,
              child: LedgerEntryTile(
                entry: entry,
                showActor: _canWrite,
                // Yönetici notları (açıklama, iptal nedeni) yalnız yazma yetkisi olan ekranda; kurul görmez.
                showNotes: _canWrite,
                related: related,
                actionsEnabled: !_opening && !_issuing,
                onCorrect: _canWrite && entry.canCorrect ? () => _correct(entry) : null,
                onReverse: _canWrite && entry.canReverse ? () => _reverse(entry) : null,
                onOpenReceipt: entry.receipt == null ? null : () => _openReceipt(entry),
                onIssueReceipt: _canWrite && _canIssueReceipt(entry) ? () => _issueReceipt(entry) : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, AccountView header) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final balance = describeBalance(header.balanceMinor);
    final overdue = header.overdueMinor;
    // İki hesaplı dairede bakiye seçili hesabındır: hangi hesap olduğu açıkça yazılır ve okunur.
    final party = header.hasTwoAccounts ? (header.accountParty ?? _party) : null;
    final summary = Semantics(
      container: true,
      label:
          '${party == null ? '' : '${party.label}. '}'
          '${balance.semanticLabel}.'
          '${overdue != null && overdue > 0 ? ' Vadesi geçen: ${moneySemanticLabel(overdue)}.' : ''}'
          ' ${payerPartyLabel(header.apartment.responsibleParty)}.',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (party != null)
              Text(
                party.label,
                key: const ValueKey<String>('finance_account_party_label'),
                style: th.bodySmall?.copyWith(color: p.textSecondary, fontWeight: FontWeight.w700),
              ),
            Row(
              children: [
                Icon(balance.icon, color: balance.tone.ink(p)),
                const SizedBox(width: AppSpace.sm),
                Expanded(child: Text(balance.title, style: th.titleMedium)),
              ],
            ),
            if (balance.amountText.isNotEmpty)
              Text(
                balance.amountText,
                key: const ValueKey<String>('finance_account_balance'),
                style: th.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
            if (overdue != null && overdue > 0) ...[
              const SizedBox(height: AppSpace.xs),
              Text(
                'Vadesi geçen: ${formatMinor(overdue)}',
                style: th.bodyMedium?.copyWith(
                  color: AppTone.warning.ink(p),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: AppSpace.xs),
            Text(
              payerPartyLabel(header.apartment.responsibleParty),
              style: th.bodySmall?.copyWith(color: p.textSecondary),
            ),
          ],
        ),
      ),
    );
    return DialogPanel(
      key: const ValueKey<String>('finance_account_header'),
      tone: balance.direction == BalanceDirection.debt ? AppTone.danger : null,
      child: header.funds == null
          ? summary
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                summary,
                // İki kasa: kasa bazında durum (kendi birleşik etiketiyle okunur; yukarıdaki etiketin dışında).
                const SizedBox(height: AppSpace.md),
                FundBreakdownPanel(
                  breakdown: header.funds!,
                  advanceMinor: header.advanceMinor,
                  keyPrefix: 'finance_account_funds',
                ),
              ],
            ),
    );
  }
}
