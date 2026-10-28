// Yönetici "Dekontlar" sekmesi (Dalga 2 / 2B, Finans ekranı): sakinlerin bildirdiği dekontlar "geçici kabul"tedir; buradan tek tek (karşılaştırma penceresi) ya da
// toplu onaylanır / iptal edilir. Toplu işlemde her bildirim ayrı işlemdir (en çok 50); önemli uyarısı olan bildirim toplu onaydan atlanır, tek tek incelenir.
// Kurul üyesi bu sekmeyi göremez (dekont kişisel veri içerir).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/cash_models.dart';
import 'package:site_kapi_kontrol/models/payment_notice.dart';
import 'package:site_kapi_kontrol/services/payment_notice_api.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/status_dot.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/payment_notice_manual_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/payment_notice_review_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/date_input.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_errors.dart';
import 'package:site_kapi_kontrol/ui/helpers/money.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

class PaymentNoticesView extends StatefulWidget {
  const PaymentNoticesView({super.key, required this.scope, this.onDataChanged, this.onAttention});

  final PeopleScope scope;

  /// Onay / iptal sonrası (özet ve öteki sekmeler tazelensin).
  final VoidCallback? onDataChanged;

  /// Bekleyen dekont sayısı değişince (sekme rozeti).
  final ValueChanged<int>? onAttention;

  @override
  State<PaymentNoticesView> createState() => PaymentNoticesViewState();
}

class PaymentNoticesViewState extends State<PaymentNoticesView> {
  static const List<(String, String)> _filters = <(String, String)>[('pending', 'İnceleniyor'), ('approved', 'Onaylanan'), ('rejected', 'İptal'), ('all', 'Tümü')];

  String _status = 'pending';
  List<PaymentNotice> _items = const <PaymentNotice>[];
  Map<String, int> _counts = const <String, int>{};
  bool _hasMore = false;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  final Set<int> _selected = <int>{};
  int _token = 0;

  PaymentNoticeService get _service => PaymentNoticeService.of(widget.scope.authService);

  @override
  void initState() {
    super.initState();
    unawaited(reload());
  }

  @override
  void didUpdateWidget(PaymentNoticesView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scope.siteCode != widget.scope.siteCode) unawaited(reload());
  }

  Future<void> reload() async {
    final token = ++_token;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await _service.run((api, t) => api.list(token: t, siteCode: widget.scope.siteCode, status: _status));
      if (!mounted || token != _token) return;
      setState(() {
        _items = page.items;
        _counts = page.counts;
        _hasMore = page.hasMore;
        _loading = false;
        _selected.removeWhere((id) => !page.items.any((n) => n.id == id && n.isPending));
      });
      widget.onAttention?.call(page.counts['pending'] ?? 0);
    } catch (e) {
      if (!mounted || token != _token) return;
      setState(() {
        _loading = false;
        _error = financeMessageOf(e, 'Dekontlar yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.');
      });
    }
  }

  Future<void> _more() async {
    if (_loadingMore || _items.isEmpty) return;
    setState(() => _loadingMore = true);
    try {
      final page = await _service.run((api, t) => api.list(token: t, siteCode: widget.scope.siteCode, status: _status, beforeId: _items.last.id));
      if (!mounted) return;
      setState(() {
        _items = [..._items, ...page.items];
        _hasMore = page.hasMore;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        _error = financeMessageOf(e, 'Daha fazla yüklenemedi.');
      });
    }
  }

  void _changed() {
    widget.onDataChanged?.call();
    unawaited(reload());
  }

  Future<void> _open(PaymentNotice n) async {
    final changed = await PaymentNoticeReviewDialog.show(context, widget.scope, n.id);
    if (changed == true) _changed();
  }

  Future<void> _manual() async {
    final created = await PaymentNoticeManualDialog.show(context, widget.scope);
    if (created == true) _changed();
  }

  int get _selectedTotal => _items.where((n) => _selected.contains(n.id)).fold(0, (sum, n) => sum + n.amountMinor);

  Future<void> _bulkApprove() async {
    final accounts = await loadNoticeAccounts(widget.scope);
    if (!mounted) return;
    int? accountId = accounts.length == 1 ? accounts.first.id : null;
    final ids = _selected.toList();
    final total = _selectedTotal;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          key: const ValueKey<String>('notice_bulk_approve_dialog'),
          title: Text('${ids.length} dekont onaylansın mı?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Toplam ${formatMinor(total)} tahsilat ve makbuz oluşur. Önemli uyarısı olan dekontlar ile dairesinde İşletme ve Fon borcu birlikte açık olanlar '
                '(ödemenin hesabını siz seçersiniz) atlanır; onları tek tek inceleyin.',
              ),
              if (accounts.isNotEmpty) ...[
                const SizedBox(height: AppSpace.md),
                DropdownButtonFormField<int?>(
                  initialValue: accountId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Tahsilat hesabı (kasa / banka)'),
                  items: [
                    const DropdownMenuItem<int?>(value: null, child: Text('Ayarlardaki sakin hesabı')),
                    for (final CashAccount a in accounts) DropdownMenuItem<int?>(value: a.id, child: Text(a.name, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => setLocal(() => accountId = v),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Vazgeç')),
            FilledButton(key: const ValueKey<String>('notice_bulk_approve_confirm'), onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Onayla')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    await _runBulk(() => _service.run((api, t) => api.bulkApprove(token: t, siteCode: widget.scope.siteCode, ids: ids, accountId: accountId)), 'onaylandı');
  }

  Future<void> _bulkReject() async {
    final ids = _selected.toList();
    var reason = 'not_received';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          key: const ValueKey<String>('notice_bulk_reject_dialog'),
          title: Text('${ids.length} dekont iptal edilsin mi?'),
          content: DropdownButtonFormField<String>(
            initialValue: reason,
            decoration: const InputDecoration(labelText: 'İptal nedeni (sakinlere gösterilir)'),
            items: [for (final e in kNoticeRejectReasons.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
            onChanged: (v) => setLocal(() => reason = v ?? 'other'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Vazgeç')),
            FilledButton(key: const ValueKey<String>('notice_bulk_reject_confirm'), onPressed: () => Navigator.of(ctx).pop(true), child: const Text('İptal et')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    await _runBulk(() => _service.run((api, t) => api.bulkReject(token: t, siteCode: widget.scope.siteCode, ids: ids, reasonCode: reason)), 'iptal edildi');
  }

  Future<void> _runBulk(Future<List<NoticeBulkResult>> Function() call, String verb) async {
    try {
      final results = await call();
      if (!mounted) return;
      final failed = results.where((r) => !r.ok).toList();
      final okCount = results.length - failed.length;
      _selected.clear();
      _changed();
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          key: const ValueKey<String>('notice_bulk_result'),
          title: Text('$okCount dekont $verb'),
          content: failed.isEmpty
              ? const Text('Tüm işlemler tamamlandı.')
              : SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${failed.length} dekont işlenemedi; tek tek inceleyin:'),
                      const SizedBox(height: AppSpace.sm),
                      for (final r in failed) Text('- ${_labelOf(r.id)}: ${PaymentNoticeApi.noticeErrorMessage(r.code) ?? r.message ?? 'işlenemedi'}'),
                    ],
                  ),
                ),
          actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Tamam'))],
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _error = financeMessageOf(e, 'Toplu işlem yapılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.'));
    }
  }

  String _labelOf(int id) {
    for (final n in _items) {
      if (n.id == id) return '${n.apartmentLabel} ${formatMinor(n.amountMinor)}';
    }
    return 'Dekont $id';
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    if (!widget.scope.canWrite) {
      return const EmptyCard(icon: Icons.lock_outline_rounded, title: 'Dekontları yalnız yönetici görür.', message: 'Dekontlar kişisel veri içerir; kurul üyeleri görüntüleyemez.');
    }
    final pendingCount = _counts['pending'] ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final f in _filters)
              ChoiceChip(
                key: ValueKey<String>('notice_filter_${f.$1}'),
                label: Text(f.$1 == 'pending' && pendingCount > 0 ? '${f.$2} ($pendingCount)' : f.$2),
                selected: _status == f.$1,
                onSelected: (_) {
                  setState(() {
                    _status = f.$1;
                    _selected.clear();
                  });
                  unawaited(reload());
                },
              ),
            PrimaryActionButton(
              key: const ValueKey<String>('notice_manual_open'),
              label: 'Elden giriş',
              icon: Icons.add_card_rounded,
              variant: AppButtonVariant.tonal,
              expand: false,
              onPressed: _manual,
            ),
          ],
        ),
        const SizedBox(height: AppSpace.md),
        if (_selected.isNotEmpty)
          AppCard(
            key: const ValueKey<String>('notice_bulk_bar'),
            child: Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                PrimaryActionButton(
                  key: const ValueKey<String>('notice_bulk_approve'),
                  label: 'Seçilenleri onayla (${_selected.length}) - ${formatMinor(_selectedTotal)}',
                  icon: Icons.done_all_rounded,
                  expand: false,
                  onPressed: _bulkApprove,
                ),
                OutlinedButton(key: const ValueKey<String>('notice_bulk_reject'), onPressed: _bulkReject, child: const Text('Seçilenleri iptal et')),
                TextButton(onPressed: () => setState(_selected.clear), child: const Text('Seçimi temizle')),
              ],
            ),
          ),
        if (_selected.isNotEmpty) const SizedBox(height: AppSpace.md),
        if (_error != null) InlineNotice(message: _error!, onRetry: reload),
        if (_loading && _items.isEmpty)
          const ListSkeleton(rows: 3)
        else if (_items.isEmpty && _error == null)
          EmptyCard(
            key: const ValueKey<String>('notice_empty'),
            icon: Icons.receipt_long_rounded,
            title: _status == 'pending' ? 'İncelenecek dekont yok.' : 'Bu durumda dekont yok.',
            message: 'Sakinler "Öde" sayfasından dekont gönderdiğinde burada görünür. Bu özellik Finans Ayarları > Ödeme bilgisi bölümünden açılır.',
          )
        else
          for (final n in _items)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.sm),
              child: AppCard(
                key: ValueKey<String>('notice_card_${n.id}'),
                child: Row(
                  children: [
                    if (n.isPending)
                      Checkbox(
                        key: ValueKey<String>('notice_select_${n.id}'),
                        value: _selected.contains(n.id),
                        onChanged: (v) => setState(() => v == true ? _selected.add(n.id) : _selected.remove(n.id)),
                      ),
                    Expanded(
                      child: InkWell(
                        key: ValueKey<String>('notice_open_${n.id}'),
                        onTap: () => _open(n),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(n.apartmentLabel, style: th.titleSmall),
                              Text(formatMinor(n.amountMinor), style: th.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                              Text(
                                [
                                  formatCrmDate(n.paidOn),
                                  if (n.senderName != null) n.senderName!,
                                  n.fromManager ? 'Elden giriş' : (n.origin == 'resident_share' ? 'Paylaşımla' : 'Uygulamadan'),
                                  if (!n.hasFile) 'dosyasız',
                                ].join(' - '),
                                style: th.bodySmall?.copyWith(color: p.textSecondary),
                              ),
                              StatusDot(
                                label: n.status.label,
                                tone: switch (n.status) {
                                  NoticeStatus.approved => AppTone.success,
                                  NoticeStatus.pending => AppTone.warning,
                                  NoticeStatus.rejected => AppTone.danger,
                                  _ => AppTone.neutral,
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded),
                  ],
                ),
              ),
            ),
        if (_hasMore)
          Align(
            child: PrimaryActionButton(
              key: const ValueKey<String>('notice_more'),
              label: 'Daha fazla göster',
              variant: AppButtonVariant.tonal,
              expand: false,
              loading: _loadingMore,
              onPressed: _more,
            ),
          ),
      ],
    );
  }
}
