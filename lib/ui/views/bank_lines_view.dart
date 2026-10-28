// Eşleşmeyenler ekranı (Dalga 2 / 2C): kontrol edilecek (önerili) ve tanınmayan banka satırları, daireye işleme, toplu onay, gelir/gider olarak ayırma.
// Sayılar ve durumlar sunucudandır; istemci eşleme yapmaz. Hata durumunda eski liste "boş" gibi gösterilmez.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/bank_import.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/bank_import_api.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/bank_line_assign_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/bank_line_classify_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/bank_line_review_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/money.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/widgets/home_shortcut_button.dart';

class BankLinesView extends StatefulWidget {
  const BankLinesView({super.key, required this.scope});

  final PeopleScope scope;

  @override
  State<BankLinesView> createState() => _BankLinesViewState();
}

class _BankLinesViewState extends State<BankLinesView> {
  bool _done = false;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  List<BankLineItem> _lines = const <BankLineItem>[];
  int _token = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    ++_token;
    super.dispose();
  }

  BankImportService get _svc => BankImportService.of(widget.scope.authService);

  Future<void> _load() async {
    final token = ++_token;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final status = _done ? 'done' : 'attention';
      final lines = await _svc.run((api, t) => api.listLinesByStatus(token: t, siteCode: widget.scope.siteCode, status: status));
      if (!mounted || token != _token) return;
      setState(() {
        _lines = lines;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted || token != _token) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  void _toast(String text) => ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(text)));

  Future<void> _guard(Future<void> Function() work) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await work();
    } on ApiException catch (e) {
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted) unawaited(_load());
  }

  Future<void> _confirmOne(BankLineItem l) async {
    // K3: dairenin hem İşletme hem Fon borcu açıksa ödemenin hangisine işleneceğini yönetici seçer: hesap seçimi "Daireye işle" penceresindedir.
    if (l.note == kBankNoteFundChoice) {
      await _assign(l);
      return;
    }
    var needsFund = false;
    await _guard(() async {
      final r = await _svc.run((api, t) => api.confirmLines(token: t, siteCode: widget.scope.siteCode, lineIds: <int>[l.id]));
      if (r.failedCodes[l.id] == kBankNoteFundChoice) {
        needsFund = true;
        _toast('Bu dairede İşletme ve Fon borcu birlikte açık; ödemenin işleneceği hesabı seçin.');
      } else {
        _toast(r.failed > 0 ? 'Satır işlenemedi. "Daireye işle" ile elle deneyin.' : 'Satır işlendi.');
      }
    });
    if (needsFund && mounted) await _assign(l);
  }

  /// Toplu onay: hesap seçimi gereken satırlar (K3) toplu onaya alınmaz; tek tek onaylanır.
  Future<void> _confirmAll() {
    final suggested = _lines.where((l) => l.status == 'suggested' && l.apartmentId != null).toList();
    final ids = suggested.where((l) => l.note != kBankNoteFundChoice).map((l) => l.id).take(200).toList();
    final held = suggested.length - suggested.where((l) => l.note != kBankNoteFundChoice).length;
    if (ids.isEmpty) {
      if (held > 0) _toast('$held satır hesap (İşletme / Fon) seçimi gerektiriyor; tek tek onaylayın.');
      return Future<void>.value();
    }
    return _guard(() async {
      final r = await _svc.run((api, t) => api.confirmLines(token: t, siteCode: widget.scope.siteCode, lineIds: ids));
      final needFund = held + r.failedCodes.values.where((c) => c == kBankNoteFundChoice).length;
      final other = r.failed - r.failedCodes.values.where((c) => c == kBankNoteFundChoice).length;
      _toast(
        '${r.done} satır işlendi'
        '${needFund > 0 ? ', $needFund satır hesap (İşletme / Fon) seçimi gerektiriyor (tek tek onaylayın)' : ''}'
        '${other > 0 ? ', $other satır işlenemedi (elle bakın)' : ''}.',
      );
    });
  }

  /// C-26: önerilen satırları sırayla, tek tek gözden geçirip onaylar (toplu onaydan önce satır satır akış).
  Future<void> _reviewEach() async {
    final processed = await BankLineReviewDialog.show(context, scope: widget.scope, lines: _lines);
    if (!mounted) return;
    if (processed > 0) _toast('$processed satır işlendi.');
    unawaited(_load());
  }

  Future<void> _assign(BankLineItem l) async {
    if (await BankLineAssignDialog.show(context, scope: widget.scope, line: l)) {
      _toast('Satır işlendi.');
      unawaited(_load());
    }
  }

  Future<void> _classify(BankLineItem l) async {
    if (await BankLineClassifyDialog.show(context, scope: widget.scope, line: l)) {
      _toast('Satır ayrıldı.');
      unawaited(_load());
    }
  }

  Future<void> _undo(BankLineItem l) => _guard(() async {
    await _svc.run((api, t) => api.unclassifyLine(token: t, siteCode: widget.scope.siteCode, lineId: l.id));
    _toast('Geri alındı.');
  });

  static const Map<String, String> _classNames = <String, String>{
    'expense': 'Gider',
    'bank_fee': 'Banka masrafı',
    'interest': 'Faiz geliri',
    'other_income': 'Diğer gelir',
    'transfer': 'Aktarım',
    'ignore': 'Yok sayıldı',
  };

  Widget _tile(BankLineItem l) {
    final th = Theme.of(context).textTheme;
    final suggested = l.status == 'suggested' && l.apartmentId != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.md),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(l.valueDate, style: th.bodySmall)),
                Text(formatSignedMinor(l.amountMinor), style: th.titleSmall),
              ],
            ),
            if (l.counterpartyName != null) Text(l.counterpartyName!, style: th.bodyMedium),
            if (l.description.isNotEmpty) Text(l.description, style: th.bodySmall, maxLines: 3, overflow: TextOverflow.ellipsis),
            if (bankPeriodLabel(l.periodHint) != null) Text('Açıklamada dönem: ${bankPeriodLabel(l.periodHint)}', style: th.bodySmall),
            if (_done) Text('${_classNames[l.classification] ?? 'Ayrıldı'}${l.note != null ? ' · ${l.note}' : ''}', style: th.bodySmall),
            if (suggested) ...[
              const SizedBox(height: AppSpace.sm),
              Text('Öneri: ${l.apartmentLabel ?? 'Daire'}${l.party == 'tenant' ? ' (kiracı)' : l.party == 'owner' ? ' (ev sahibi)' : ''}', style: th.bodyMedium),
            ],
            if (l.note == kBankNoteReviewEach)
              Text('Güçlü eşleşme: tek tek gözden geçirmeniz istendi; kontrol edip onaylayın.', key: ValueKey<String>('bank_note_review_${l.id}'), style: th.bodySmall),
            if (l.note == kBankNoteFundChoice)
              Text(
                'Bu dairede İşletme Projesi (Aidat) Hesabı ve Yatırım ve Demirbaş (Fon) Hesabı için açık borç var; onaylarken ödemenin hangisine işleneceğini seçin.',
                key: ValueKey<String>('bank_note_fund_${l.id}'),
                style: th.bodySmall,
              ),
            if (l.note == 'PERIOD_CLOSED') Text('Bu tarihin dönemi kapalı; dönemi açıp tekrar deneyin.', style: th.bodySmall),
            if (l.note == 'POSSIBLE_DUPLICATE_PAYMENT') Text('Aynı tutar ve tarihte başka bir banka satırının tahsilatı var; çift tahsilat olmasın diye kontrol edin.', style: th.bodySmall),
            const SizedBox(height: AppSpace.sm),
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.xs,
              children: [
                if (_done)
                  OutlinedButton(key: ValueKey<String>('bank_undo_${l.id}'), onPressed: _busy ? null : () => _undo(l), child: const Text('Geri al'))
                else ...[
                  if (suggested && l.incoming)
                    FilledButton(
                      key: ValueKey<String>('bank_confirm_${l.id}'),
                      onPressed: _busy ? null : () => _confirmOne(l),
                      child: Text(l.note == kBankNoteFundChoice ? 'Hesabı seçerek onayla' : 'Onayla'),
                    ),
                  if (l.incoming) OutlinedButton(key: ValueKey<String>('bank_assign_${l.id}'), onPressed: _busy ? null : () => _assign(l), child: const Text('Daireye işle')),
                  OutlinedButton(key: ValueKey<String>('bank_classify_${l.id}'), onPressed: _busy ? null : () => _classify(l), child: const Text('Gelir/gider')),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canConfirmAll = !_done && widget.scope.canWrite && _lines.any((l) => l.status == 'suggested' && l.apartmentId != null);
    final canReviewEach = !_done && widget.scope.canWrite && reviewableBankLines(_lines).isNotEmpty;
    return Scaffold(
      // En derin ekran (Panel > Finans > Kasa > Banka dosyası > buradayız): üst çubukta tek dokunuşla ana sayfa (P1-13).
      appBar: AppBar(title: const Text('Banka Ödemeleri ve Daire Onayları'), actions: const <Widget>[HomeShortcutButton()]),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(AppSpace.lg),
          children: [
            SegmentedButton<bool>(
              segments: const <ButtonSegment<bool>>[
                ButtonSegment<bool>(value: false, label: Text('Bekleyenler')),
                ButtonSegment<bool>(value: true, label: Text('Gelir/gider olarak ayrılanlar')),
              ],
              selected: <bool>{_done},
              onSelectionChanged: (s) {
                setState(() => _done = s.first);
                unawaited(_load());
              },
            ),
            const SizedBox(height: AppSpace.md),
            if (canConfirmAll)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.md),
                child: Wrap(
                  spacing: AppSpace.sm,
                  runSpacing: AppSpace.sm,
                  children: [
                    if (canReviewEach)
                      FilledButton.icon(
                        key: const ValueKey<String>('bank_review_each'),
                        onPressed: _busy ? null : _reviewEach,
                        icon: const Icon(Icons.fact_check_rounded),
                        label: const Text('Tek tek gözden geçir'),
                      ),
                    OutlinedButton.icon(
                      key: const ValueKey<String>('bank_confirm_all'),
                      onPressed: _busy ? null : _confirmAll,
                      icon: const Icon(Icons.done_all_rounded),
                      label: const Text('Önerilen dairelerin hepsini onayla'),
                    ),
                  ],
                ),
              ),
            if (_loading) const Center(child: Padding(padding: EdgeInsets.all(AppSpace.xl), child: CircularProgressIndicator())),
            if (!_loading && _error != null) ...[
              Text(_error!),
              TextButton(onPressed: _load, child: const Text('Tekrar dene')),
            ],
            if (!_loading && _error == null && _lines.isEmpty) Padding(padding: const EdgeInsets.all(AppSpace.xl), child: Text(_done ? 'Henüz ayrılmış satır yok.' : 'Onay bekleyen banka hareketi bulunmuyor.', textAlign: TextAlign.center)),
            if (!_loading && _error == null) for (final l in _lines) _tile(l),
          ],
        ),
      ),
    );
  }
}
