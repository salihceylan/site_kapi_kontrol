import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/finance.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/finance_late_fee_explain_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/large_dialog_parts.dart';
import 'package:site_kapi_kontrol/ui/helpers/date_input.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_errors.dart';
import 'package:site_kapi_kontrol/ui/helpers/money.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/my_finance_4b_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/pay_sheet.dart';
import 'package:site_kapi_kontrol/ui/widgets/payment_notice_status.dart';

/// Sakin "Borcum" ekranı (Platform Faz 4a, `finance` modülü): kendi dairelerinin toplam borcu / alacağı,
/// vadesi geçen tutar, sıradaki vade ve son hareketler. YALNIZ GÖRÜNTÜLEME: hiçbir yazma eylemi yoktur,
/// yönetici notu / kaydeden adı gösterilmez (sunucu da göndermez). Online ödeme yakında.
///
/// - Çok daireli kullanıcıda her daire ayrı kartta; birden çok daire varsa üstte toplam borç / alacak.
/// - Boş durum ("Borcunuz yok") YALNIZ sunucu bakiyeyi gerçekten sıfır döndürdüğünde gösterilir. Hata,
///   yükleme ve modül kapalı durumları ayrıdır ve ASLA "borç yok" demez; hesaba bağlı daire yoksa farklı bir
///   açıklama gösterilir.
/// - Eski / yavaş yanıt yenisini ezmez (jeton); dispose sonrası yanıt yok sayılır. [MyFinanceViewState.reload]
///   sayfa kabuğunun aşağı çekip yenilemesinden çağrılır.
/// - Faz 4b: her dairenin kartında **Makbuzlarım** ve **Ekstre** PDF'i; makbuzlu satırda "Makbuz MK-..." ve tazminat
///   satırında "Nasıl hesaplandı?" (hepsi salt okuma; sakin hiçbir şey yazmaz).
/// - İki hesap (İP-1A): kartın tutarları kişinin KENDİ hesabıdır (malik -> "Ev sahibi hesabı", kiracı -> "Kiracı hesabı") ve
///   hesabın adı yazılır. Borç sorumlusu "malik ve kiracı" olan dairede malik kiracı hesabını kartın altında SALT OKUNUR
///   ayrı bölümde görür; bu tutarlar kendi hesabına ve toplamlara eklenmez.
class MyFinanceView extends StatefulWidget {
  const MyFinanceView({super.key, required this.authService, this.now});

  final AuthService authService;

  /// Şimdiki zaman (ekstre PDF dönemi için; testler içindir).
  final DateTime Function()? now;

  @override
  State<MyFinanceView> createState() => MyFinanceViewState();
}

class MyFinanceViewState extends State<MyFinanceView> {
  MyFinance? _data;
  bool _loading = false;
  String? _error;
  bool _moduleOff = false;
  int _token = 0;

  @override
  void initState() {
    super.initState();
    unawaited(reload());
  }

  @override
  void dispose() {
    ++_token;
    super.dispose();
  }

  Future<void> reload() async {
    if (!mounted) return;
    final token = ++_token;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.authService.getMyFinance();
      if (!mounted || token != _token) return;
      setState(() {
        _data = data;
        _loading = false;
        _moduleOff = false;
      });
    } catch (e) {
      if (!mounted || token != _token) return;
      setState(() {
        _loading = false;
        // Eski tutar gösterilmez: hata durumunda yalnız hata + "Tekrar Dene".
        _data = null;
        if (isFinanceModuleDisabled(e)) {
          _moduleOff = true;
        } else {
          _error = financeMessageOf(
            e,
            'Borç bilgisi yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final data = _data;
    final Widget content;
    if (_moduleOff) {
      content = const EmptyCard(
        key: ValueKey<String>('my_finance_module_off'),
        icon: Icons.account_balance_wallet_rounded,
        tone: AppTone.warning,
        title: 'Borç takibi şu an kapalı.',
        message: 'Site yönetimi Aidat ve Finans özelliğini açtığında borç durumunuz burada görünür.',
      );
    } else if (data == null) {
      content = _loading || _error == null
          ? const ListSkeleton(rows: 2)
          : InlineNotice(message: _error!, onRetry: reload);
    } else if (data.items.isEmpty) {
      content = const EmptyCard(
        key: ValueKey<String>('my_finance_none'),
        icon: Icons.apartment_rounded,
        title: 'Borç takibi yapılan bir daireniz görünmüyor.',
        message:
            'Hesabınıza bağlı ve borcu görüntülenebilir bir daire bulunamadı. Bir sorun olduğunu '
            'düşünüyorsanız site yönetimiyle iletişime geçin.',
      );
    } else {
      content = _buildItems(context, data);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageHeaderCard(title: 'Borcum', icon: Icons.account_balance_wallet_rounded),
        const SizedBox(height: AppSpace.sm),
        Text(
          'Dairenizin güncel borç ve alacak durumunu, vadeleri ve son hareketleri buradan görebilirsiniz.',
          style: th.bodyMedium,
        ),
        const SizedBox(height: AppSpace.md),
        content,
      ],
    );
  }

  Widget _buildItems(BuildContext context, MyFinance data) {
    final multi = data.items.length > 1;
    var debt = 0;
    var credit = 0;
    for (final item in data.items) {
      if (item.balanceMinor > 0) debt += item.balanceMinor;
      if (item.balanceMinor < 0) credit += -item.balanceMinor;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (multi) ...[
          _TotalsCard(debtMinor: debt, creditMinor: credit),
          const SizedBox(height: AppSpace.md),
        ],
        for (final item in data.items)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.md),
            child: MyFinanceCard(
              key: ValueKey<String>('my_finance_${item.siteCode}_${item.apartmentId}'),
              item: item,
              showSite: multi || item.siteName.trim().isNotEmpty,
              authService: widget.authService,
              now: widget.now,
            ),
          ),
      ],
    );
  }
}

class _TotalsCard extends StatelessWidget {
  const _TotalsCard({required this.debtMinor, required this.creditMinor});

  final int debtMinor;
  final int creditMinor;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    return AppCard(
      key: const ValueKey<String>('my_finance_totals'),
      padding: listCardPadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(header: true, container: true, child: Text('Tüm dairelerim', style: th.titleMedium)),
          const SizedBox(height: AppSpace.sm),
          // Tutarlar ekran okuyucuya "bin iki yüz elli lira" diye okunur; görsel çipler okunuştan dışlanır.
          Semantics(
            container: true,
            label:
                'Toplam borç: ${moneySemanticLabel(debtMinor)}. '
                'Toplam alacak: ${moneySemanticLabel(creditMinor)}.',
            child: ExcludeSemantics(
              child: Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.xs,
                children: [
                  DialogMetaPill(
                    'Toplam borç ${formatMinor(debtMinor)}',
                    tone: AppTone.danger,
                    icon: Icons.arrow_circle_up_rounded,
                  ),
                  DialogMetaPill(
                    'Toplam alacak ${formatMinor(creditMinor)}',
                    tone: AppTone.success,
                    icon: Icons.arrow_circle_down_rounded,
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

/// Sakinin bir dairesinin mali durumu: site / daire, bakiye (borç / alacak / borç yok), vadesi geçen tutar,
/// sıradaki vade ve son hareketler (ilk 5; "Tümünü göster" ile 30'a kadar).
class MyFinanceCard extends StatefulWidget {
  const MyFinanceCard({super.key, required this.item, this.showSite = false, this.authService, this.now});

  final MyFinanceApartment item;
  final bool showSite;

  /// Verilirse Faz 4b eylemleri (makbuzlar, ekstre PDF, tazminat açıklaması) çizilir; verilmezse yalnız 4a görünümü.
  final AuthService? authService;
  final DateTime Function()? now;

  static const int collapsedCount = 5;

  @override
  State<MyFinanceCard> createState() => _MyFinanceCardState();
}

class _MyFinanceCardState extends State<MyFinanceCard> {
  bool _expanded = false;
  bool _opening = false;

  Future<void> _openReceipt(ReceiptRef ref) async {
    final auth = widget.authService;
    if (auth == null || _opening) return;
    _opening = true;
    try {
      await openResidentReceipt(context, auth, widget.item, ref);
    } finally {
      _opening = false;
    }
  }

  Future<void> _explainLateFee(LedgerEntry entry) async {
    final auth = widget.authService;
    if (auth == null || _opening) return;
    _opening = true;
    try {
      await FinanceLateFeeExplainDialog.show(context, scope: residentScopeOf(auth, widget.item), entryId: entry.id);
    } finally {
      _opening = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final item = widget.item;
    final balance = describeBalance(item.balanceMinor);
    final overdue = item.overdueMinor;
    final hasOverdue = overdue != null && overdue > 0;
    final title = financeApartmentTitle(item.blockName, item.label);
    final site = item.siteName.trim();
    final recent = item.recent;
    final shown = _expanded || recent.length <= MyFinanceCard.collapsedCount
        ? recent
        : recent.take(MyFinanceCard.collapsedCount).toList();
    final hidden = recent.length - shown.length;

    final semantic = StringBuffer(widget.showSite && site.isNotEmpty ? '$site. ' : '');
    semantic.write('Daire: $title.');
    if (item.accountParty != null) semantic.write(' ${_ownAccountText(item.accountParty!)}.');
    semantic.write(' ${balance.semanticLabel}.');
    if (hasOverdue) semantic.write(' Vadesi geçen: ${moneySemanticLabel(overdue)}.');
    if (item.nextDueDate != null) {
      semantic.write(' Sıradaki vade: ${formatCrmDate(item.nextDueDate)}');
      if (item.nextDueMinor != null) semantic.write(', ${moneySemanticLabel(item.nextDueMinor!)}');
      semantic.write('.');
    }
    // Kim öder bilgisi görsel çipte var; birleşik etikette de okunmalı (çip okunuştan dışlanıyor).
    if (item.payerParty != null) semantic.write(' ${payerPartyLabel(item.payerParty!)}.');
    if (item.visibleFrom != null) semantic.write(' ${myFinanceScopeNote(item.visibleFrom!)}');
    if (item.offsetNote) semantic.write(' ${myFinanceOffsetNote()}');

    return AppCard(
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
                  if (widget.showSite && site.isNotEmpty)
                    Text(site, style: th.bodySmall?.copyWith(color: p.textSecondary)),
                  Text(title, style: th.titleMedium),
                  if (item.accountParty != null)
                    Text(
                      _ownAccountText(item.accountParty!),
                      key: const ValueKey<String>('my_finance_account_party'),
                      style: th.bodySmall?.copyWith(color: p.textSecondary, fontWeight: FontWeight.w700),
                    ),
                  const SizedBox(height: AppSpace.md),
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
                      key: const ValueKey<String>('my_finance_balance'),
                      style: th.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  if (balance.direction == BalanceDirection.zero)
                    Text(
                      'Borcunuz yok.',
                      key: const ValueKey<String>('my_finance_no_debt'),
                      style: th.bodyMedium,
                    ),
                  if (hasOverdue) ...[
                    const SizedBox(height: AppSpace.xs),
                    Text(
                      'Vadesi geçen: ${formatMinor(overdue)}',
                      style: th.bodyMedium?.copyWith(
                        color: AppTone.warning.ink(p),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  if (item.nextDueDate != null) ...[
                    const SizedBox(height: AppSpace.xs),
                    Text(
                      item.nextDueMinor == null
                          ? 'Sıradaki vade: ${formatCrmDate(item.nextDueDate)}'
                          : 'Sıradaki vade: ${formatCrmDate(item.nextDueDate)} • ${formatMinor(item.nextDueMinor!)}',
                      key: const ValueKey<String>('my_finance_next_due'),
                      style: th.bodyMedium,
                    ),
                  ],
                  if (item.payerParty != null) ...[
                    const SizedBox(height: AppSpace.sm),
                    Wrap(children: [PayerPartyChip(item.payerParty!)]),
                  ],
                  // Sakin kapsamı: önceki malikin / kiracının kayıtları gösterilmez; başlangıç ayı açıkça yazılır.
                  if (item.visibleFrom != null) ...[
                    const SizedBox(height: AppSpace.sm),
                    Text(
                      myFinanceScopeNote(item.visibleFrom!),
                      key: const ValueKey<String>('my_finance_scope_note'),
                      style: th.bodySmall?.copyWith(color: p.textSecondary),
                    ),
                  ],
                  if (item.offsetNote) ...[
                    const SizedBox(height: AppSpace.xs),
                    Text(
                      myFinanceOffsetNote(),
                      key: const ValueKey<String>('my_finance_offset_note'),
                      style: th.bodySmall?.copyWith(color: p.textSecondary),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpace.md),
          Semantics(header: true, container: true, child: Text('Son hareketler', style: th.titleSmall)),
          const SizedBox(height: AppSpace.sm),
          if (recent.isEmpty)
            Text(
              'Henüz hareket yok.',
              key: const ValueKey<String>('my_finance_no_entries'),
              style: th.bodyMedium?.copyWith(color: p.textSecondary),
            )
          else ...[
            for (final entry in shown)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.sm),
                child: LedgerEntryTile(
                  entry: entry,
                  // Sakin yönetici notu görmez (açıklama, iptal nedeni); ters kayıt satırı için aynı listedeki
                  // kayıtlar verilir.
                  related: {for (final e in recent) e.id: e},
                  onOpenReceipt: widget.authService == null || entry.receipt == null ? null : () => _openReceipt(entry.receipt!),
                  onExplainLateFee: widget.authService == null || !entry.isLateFee ? null : () => _explainLateFee(entry),
                ),
              ),
            if (hidden > 0 || _expanded && recent.length > MyFinanceCard.collapsedCount)
              Align(
                alignment: Alignment.center,
                child: PrimaryActionButton(
                  key: const ValueKey<String>('my_finance_toggle'),
                  label: _expanded ? 'Daha az göster' : 'Tümünü göster ($hidden)',
                  icon: _expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                  variant: AppButtonVariant.tonal,
                  expand: false,
                  onPressed: () => setState(() => _expanded = !_expanded),
                ),
              ),
          ],
          if (widget.authService != null && item.balanceMinor > 0) ...[
            const SizedBox(height: AppSpace.md),
            PrimaryActionButton(
              key: const ValueKey<String>('my_finance_pay'),
              label: 'Öde',
              icon: Icons.payments_rounded,
              onPressed: () => unawaited(
                PaySheet.show(
                  context,
                  authService: widget.authService!,
                  apartmentId: item.apartmentId,
                  amountMinor: item.balanceMinor,
                  accountLabel: item.accountParty?.label,
                ),
              ),
            ),
          ],
          if (widget.authService != null) ...[
            const SizedBox(height: AppSpace.md),
            MyFinanceActions(authService: widget.authService!, item: item, now: widget.now),
            PaymentNoticeStatusLine(authService: widget.authService!, apartmentId: item.apartmentId),
          ],
          // İP-1A: salt okunur kiracı hesabı (borç sorumlusu "malik ve kiracı" olan dairede malike); kendi hesabından AYRI.
          for (final account in item.readOnlyAccounts) ...[
            const SizedBox(height: AppSpace.lg),
            _ReadOnlyAccountSection(
              key: ValueKey<String>('my_finance_ro_${account.accountParty?.apiValue ?? 'hesap'}'),
              item: item,
              account: account,
              authService: widget.authService,
              now: widget.now,
              onOpenReceipt: _openReceipt,
              onExplainLateFee: _explainLateFee,
            ),
          ],
        ],
      ),
    );
  }
}

String _ownAccountText(AccountParty party) => 'Kendi hesabınız: ${party.label}';

/// Salt okunur hesap bölümü (İP-1A): başlık, açıklama, bakiye / vadesi geçen / sıradaki vade ve son hareketler (ilk 5,
/// "Tümünü göster"); ekstre PDF'i bu hesabın görünümüyle. Hiçbir yazma eylemi yoktur.
class _ReadOnlyAccountSection extends StatefulWidget {
  const _ReadOnlyAccountSection({
    super.key,
    required this.item,
    required this.account,
    this.authService,
    this.now,
    required this.onOpenReceipt,
    required this.onExplainLateFee,
  });

  final MyFinanceApartment item;
  final MyFinanceAccount account;
  final AuthService? authService;
  final DateTime Function()? now;
  final Future<void> Function(ReceiptRef ref) onOpenReceipt;
  final Future<void> Function(LedgerEntry entry) onExplainLateFee;

  @override
  State<_ReadOnlyAccountSection> createState() => _ReadOnlyAccountSectionState();
}

class _ReadOnlyAccountSectionState extends State<_ReadOnlyAccountSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final account = widget.account;
    final label = account.accountParty?.label ?? 'Diğer hesap';
    final balance = describeBalance(account.balanceMinor);
    final overdue = account.overdueMinor;
    final hasOverdue = overdue != null && overdue > 0;
    final recent = account.recent;
    final shown = _expanded || recent.length <= MyFinanceCard.collapsedCount
        ? recent
        : recent.take(MyFinanceCard.collapsedCount).toList();
    final hidden = recent.length - shown.length;
    final prefix = 'my_finance_ro_${account.accountParty?.apiValue ?? 'hesap'}';

    final semantic = StringBuffer('$label, salt okunur. ${balance.semanticLabel}.');
    if (hasOverdue) semantic.write(' Vadesi geçen: ${moneySemanticLabel(overdue)}.');
    if (account.nextDueDate != null) {
      semantic.write(' Sıradaki vade: ${formatCrmDate(account.nextDueDate)}');
      if (account.nextDueMinor != null) semantic.write(', ${moneySemanticLabel(account.nextDueMinor!)}');
      semantic.write('.');
    }
    semantic.write(' $myFinanceReadOnlyNote');
    if (account.visibleFrom != null) semantic.write(' ${myFinanceScopeNote(account.visibleFrom!)}');
    if (account.offsetNote) semantic.write(' ${myFinanceOffsetNote()}');

    return DialogPanel(
      tone: AppTone.info,
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
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(label, key: ValueKey<String>('${prefix}_title'), style: th.titleSmall),
                      const DialogMetaPill('Salt okunur', tone: AppTone.info, icon: Icons.visibility_rounded),
                    ],
                  ),
                  const SizedBox(height: AppSpace.xs),
                  Text(myFinanceReadOnlyNote, style: th.bodySmall?.copyWith(color: p.textSecondary)),
                  const SizedBox(height: AppSpace.sm),
                  Text(
                    balance.badgeText,
                    key: ValueKey<String>('${prefix}_balance'),
                    style: th.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  if (hasOverdue)
                    Text(
                      'Vadesi geçen: ${formatMinor(overdue)}',
                      style: th.bodyMedium?.copyWith(color: AppTone.warning.ink(p), fontWeight: FontWeight.w700),
                    ),
                  if (account.nextDueDate != null)
                    Text(
                      account.nextDueMinor == null
                          ? 'Sıradaki vade: ${formatCrmDate(account.nextDueDate)}'
                          : 'Sıradaki vade: ${formatCrmDate(account.nextDueDate)} • ${formatMinor(account.nextDueMinor!)}',
                      style: th.bodyMedium,
                    ),
                  if (account.visibleFrom != null)
                    Text(myFinanceScopeNote(account.visibleFrom!), style: th.bodySmall?.copyWith(color: p.textSecondary)),
                  if (account.offsetNote)
                    Text(myFinanceOffsetNote(), style: th.bodySmall?.copyWith(color: p.textSecondary)),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpace.sm),
          if (recent.isEmpty)
            Text('Bu hesapta hareket yok.', key: ValueKey<String>('${prefix}_empty'), style: th.bodyMedium?.copyWith(color: p.textSecondary))
          else ...[
            for (final entry in shown)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.sm),
                child: LedgerEntryTile(
                  entry: entry,
                  related: {for (final e in recent) e.id: e},
                  onOpenReceipt: widget.authService == null || entry.receipt == null ? null : () => widget.onOpenReceipt(entry.receipt!),
                  onExplainLateFee: widget.authService == null || !entry.isLateFee ? null : () => widget.onExplainLateFee(entry),
                ),
              ),
            if (hidden > 0 || _expanded && recent.length > MyFinanceCard.collapsedCount)
              Align(
                alignment: Alignment.center,
                child: PrimaryActionButton(
                  key: ValueKey<String>('${prefix}_toggle'),
                  label: _expanded ? 'Daha az göster' : 'Tümünü göster ($hidden)',
                  icon: _expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                  variant: AppButtonVariant.tonal,
                  expand: false,
                  onPressed: () => setState(() => _expanded = !_expanded),
                ),
              ),
          ],
          if (widget.authService != null && account.accountParty != null) ...[
            const SizedBox(height: AppSpace.sm),
            MyFinanceActions(
              key: ValueKey<String>('${prefix}_actions'),
              authService: widget.authService!,
              item: widget.item,
              now: widget.now,
              accountParty: account.accountParty,
              showReceipts: false,
              keyPrefix: prefix,
            ),
          ],
        ],
      ),
    );
  }
}
