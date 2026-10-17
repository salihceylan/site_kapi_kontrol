import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/receipt_models.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/finance_receipt_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/large_dialog_parts.dart' show DialogPanel;
import 'package:site_kapi_kontrol/ui/helpers/cursor_loader.dart';
import 'package:site_kapi_kontrol/ui/helpers/date_input.dart' show formatCrmDate;
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_4b_access.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_errors.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_export_sources.dart';
import 'package:site_kapi_kontrol/ui/helpers/istanbul_time.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/helpers/retry_lock.dart';
import 'package:site_kapi_kontrol/ui/widgets/cursor_list_body.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_4b_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/bulk_export_sheet.dart' show ExportSource;
import 'package:site_kapi_kontrol/ui/widgets/finance_parts.dart';

/// Makbuz listesi (Platform Faz 4b, Ö1): yönetici / kurul için sitenin makbuzları (arama + yıl), sakin için
/// "Makbuzlarım" (yalnız kendi dairesi). `before_id` imleçli sayfalama; hata asla "makbuz yok" demez.
///
/// - [apartmentId] verilirse yalnız o dairenin makbuzları (ekstreden açılınca).
/// - Yönetici ve kurul "Makbuz Doğrula" ile numara + doğrulama kodu denetleyebilir (hiçbir şey yazmaz).
/// - Süzgeç değişince eski yanıt yenisini ezmez (jeton); arama 350 ms geciktirilir.
class FinanceReceiptListDialog extends StatefulWidget {
  const FinanceReceiptListDialog({
    super.key,
    required this.scope,
    this.apartmentId,
    this.apartmentLabel,
    this.resident = false,
    this.now,
    this.onChanged,
    this.exportLauncher = defaultFinanceExportLauncher,
  });

  final PeopleScope scope;
  final int? apartmentId;
  final String? apartmentLabel;
  final bool resident;
  final DateTime Function()? now;
  final VoidCallback? onChanged;

  /// "Dışa Aktar" alt sayfasını açan işlev (yalnız yönetici; testler yakalamak için değiştirir).
  final FinanceExportLauncher exportLauncher;

  static Future<void> show(
    BuildContext context, {
    required PeopleScope scope,
    int? apartmentId,
    String? apartmentLabel,
    bool resident = false,
    DateTime Function()? now,
    VoidCallback? onChanged,
    FinanceExportLauncher exportLauncher = defaultFinanceExportLauncher,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => FinanceReceiptListDialog(
        scope: scope,
        apartmentId: apartmentId,
        apartmentLabel: apartmentLabel,
        resident: resident,
        now: now,
        onChanged: onChanged,
        exportLauncher: exportLauncher,
      ),
    );
  }

  @override
  State<FinanceReceiptListDialog> createState() => _FinanceReceiptListDialogState();
}

class _FinanceReceiptListDialogState extends State<FinanceReceiptListDialog> {
  final TextEditingController _search = TextEditingController();
  Timer? _timer;
  String _query = '';
  int? _year;
  String _lastSignature = '';
  bool _opening = false;

  late final CursorLoader<ReceiptSummary> _loader = CursorLoader<ReceiptSummary>(
    fetch: (before) async {
      final scope = widget.scope;
      final ReceiptPage page;
      if (widget.resident) {
        page = await scope.f4.run(
          (api, t) => api.listMyReceipts(token: t, apartmentId: widget.apartmentId, beforeId: before),
        );
      } else {
        page = await scope.f4Call(
          (api, t, s) => api.listReceipts(
            token: t,
            siteCode: s,
            apartmentId: widget.apartmentId,
            year: _year,
            query: _query,
            beforeId: before,
          ),
        );
      }
      return (items: page.items, next: page.nextBeforeId);
    },
    keyOf: (r) => r.id,
    notify: () {
      if (mounted) setState(() {});
    },
    isAlive: () => mounted,
    errorFallback: 'Makbuzlar yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
    moreErrorFallback: 'Daha fazla makbuz yüklenemedi. Tekrar deneyin.',
    messageOf: financeMessageOf,
  );

  int get _currentYear => istanbulNow(widget.now?.call()).year;

  @override
  void initState() {
    super.initState();
    // Yönetici listesi büyük olabilir: varsayılan içinde bulunulan yıl. Sakin tüm makbuzlarını görür.
    _year = widget.resident ? null : _currentYear;
    _lastSignature = '|$_year';
    unawaited(_loader.reload());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _loader.dispose();
    _search.dispose();
    super.dispose();
  }

  void _apply() {
    _timer?.cancel();
    final next = _search.text.trim();
    final signature = '$next|$_year';
    if (signature == _lastSignature && (_loader.loading || (_loader.loadedOnce && _loader.error == null))) {
      return;
    }
    _lastSignature = signature;
    _query = next;
    _loader.reset();
    unawaited(_loader.reload());
  }

  void _selectYear(int? year) {
    if (year == _year) return;
    _year = year;
    _apply();
    setState(() {});
  }

  Future<void> _open(ReceiptSummary receipt) async {
    if (_opening) return;
    _opening = true;
    try {
      await FinanceReceiptDialog.show(
        context,
        scope: widget.scope,
        receiptId: receipt.id,
        initialNumber: receipt.number,
        resident: widget.resident,
        onChanged: () {
          widget.onChanged?.call();
          if (mounted) unawaited(_loader.reload());
        },
      );
    } finally {
      _opening = false;
    }
  }

  /// Ekrandaki UYGULANMIŞ süzgeçlerle (yıl, arama, daire) makbuz listesini dosyaya aktarır (yalnız yönetici).
  void _export() {
    if (_opening) return;
    final summary = <String>[
      _year == null ? 'Tüm yıllar' : '$_year yılı',
      if (_query.isNotEmpty) 'Arama: $_query',
      if (widget.apartmentLabel != null && widget.apartmentLabel!.isNotEmpty) widget.apartmentLabel!,
    ].join(' • ');
    final source = financeExportSource(
      scope: widget.scope,
      label: 'Makbuzlar',
      kind: 'finance_receipts',
      icon: Icons.receipt_long_rounded,
      filterSummary: summary,
      query: <String, String>{
        if (_year != null) 'year': '$_year',
        if (_query.isNotEmpty) 'q': _query,
        if (widget.apartmentId != null) 'apartment_id': '${widget.apartmentId}',
      },
    );
    unawaited(widget.exportLauncher(context, <ExportSource>[source]));
  }

  Future<void> _verify() async {
    if (_opening) return;
    _opening = true;
    try {
      await showDialog<void>(
        context: context,
        builder: (_) => FinanceReceiptVerifyDialog(scope: widget.scope),
      );
    } finally {
      _opening = false;
    }
  }

  bool get _filtered => _query.isNotEmpty || (!widget.resident && _year != null);

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final year = _currentYear;
    final subtitle = widget.apartmentLabel;
    return AppDialog(
      title: widget.resident ? 'Makbuzlarım' : 'Makbuzlar',
      subtitle: subtitle == null || subtitle.isEmpty ? null : subtitle,
      icon: Icons.receipt_long_rounded,
      actions: [
        TextButton(
          key: const ValueKey<String>('finance_receipts_close'),
          onPressed: () => popIfCurrent(context),
          child: const Text('Kapat'),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!widget.resident) ...[
            TextField(
              key: const ValueKey<String>('finance_receipts_search'),
              controller: _search,
              textInputAction: TextInputAction.search,
              onChanged: (_) {
                _timer?.cancel();
                _timer = Timer(const Duration(milliseconds: 350), _apply);
                setState(() {});
              },
              onSubmitted: (_) => _apply(),
              decoration: InputDecoration(
                labelText: 'Makbuz ara',
                hintText: 'Makbuz no, daire veya ödeyen adı',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Aramayı temizle',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _search.clear();
                          _apply();
                          setState(() {});
                        },
                      ),
              ),
            ),
            const SizedBox(height: AppSpace.md),
            const FinanceGroupTitle('Yıl'),
            const SizedBox(height: AppSpace.sm),
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.sm,
              children: [
                for (final y in <int>[year, year - 1])
                  ChoiceChip(
                    key: ValueKey<String>('finance_receipts_year_$y'),
                    label: Text('$y'),
                    selected: _year == y,
                    onSelected: (_) => _selectYear(y),
                  ),
                ChoiceChip(
                  key: const ValueKey<String>('finance_receipts_year_all'),
                  label: const Text('Tümü'),
                  selected: _year == null,
                  onSelected: (_) => _selectYear(null),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.md),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.sm,
                children: [
                  PrimaryActionButton(
                    key: const ValueKey<String>('finance_receipts_verify'),
                    label: 'Makbuz Doğrula',
                    icon: Icons.verified_user_rounded,
                    variant: AppButtonVariant.tonal,
                    expand: false,
                    onPressed: _verify,
                  ),
                  // Dışa aktarma yalnız yönetici / süper kullanıcı içindir (kurul 403 alır).
                  if (widget.scope.canWrite)
                    PrimaryActionButton(
                      key: const ValueKey<String>('finance_receipts_export'),
                      label: 'Dışa Aktar',
                      icon: Icons.file_download_rounded,
                      variant: AppButtonVariant.tonal,
                      expand: false,
                      onPressed: _export,
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.md),
          ] else
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.md),
              child: Text(
                'Dairenize düzenlenen makbuzlar. Kendi cihazınızdan alacağınız çıktı "KOPYA" damgalı olur.',
                style: th.bodySmall?.copyWith(color: p.textSecondary),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  container: true,
                  child: Text('Makbuz listesi', style: th.titleMedium),
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
          CursorListBody<ReceiptSummary>(
            loader: _loader,
            emptyIcon: Icons.receipt_long_rounded,
            emptyTitle: _filtered ? 'Bu arama ve süzgeç için makbuz bulunamadı.' : 'Henüz makbuz düzenlenmemiş.',
            skeletonRows: 2,
            itemBuilder: (context, receipt) =>
                ReceiptTile(receipt: receipt, onTap: () => _open(receipt), showPayer: !widget.resident),
          ),
        ],
      ),
    );
  }
}

/// "Makbuz Doğrula": numara + doğrulama kodu -> geçerli / geçersiz (+ iptal durumu). HİÇBİR ŞEY YAZMAZ; kurul da
/// kullanabilir. Hatalı kod ile geçersiz sonuç "makbuz sahte" demez: yalnız bilgilerin kayıtla eşleşmediğini söyler.
class FinanceReceiptVerifyDialog extends StatefulWidget {
  const FinanceReceiptVerifyDialog({super.key, required this.scope});

  final PeopleScope scope;

  @override
  State<FinanceReceiptVerifyDialog> createState() => _FinanceReceiptVerifyDialogState();
}

class _FinanceReceiptVerifyDialogState extends State<FinanceReceiptVerifyDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _number = TextEditingController();
  final TextEditingController _code = TextEditingController();
  final RetryLock _retry = RetryLock();
  bool _checking = false;
  String? _error;
  ReceiptVerifyResult? _result;
  int _token = 0;

  @override
  void dispose() {
    ++_token;
    _retry.dispose();
    _number.dispose();
    _code.dispose();
    super.dispose();
  }

  String? _validateNumber(String? value) {
    final text = (value ?? '').trim().toUpperCase();
    if (text.isEmpty) return 'Makbuz numarasını girin.';
    if (!RegExp(r'^MK-\d{4}-\d{6,}$').hasMatch(text)) return 'Numara MK-2026-000123 biçiminde olmalı.';
    return null;
  }

  String? _validateCode(String? value) {
    final text = (value ?? '').replaceAll(RegExp(r'[\s-]'), '');
    if (text.isEmpty) return 'Doğrulama kodunu girin.';
    if (!RegExp(r'^[A-Za-z0-9]{12}$').hasMatch(text)) return 'Kod 12 harf ya da rakamdan oluşur.';
    return null;
  }

  Future<void> _check() async {
    if (_checking || _retry.locked) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final token = ++_token;
    FocusScope.of(context).unfocus();
    setState(() {
      _checking = true;
      _error = null;
      _result = null;
    });
    try {
      final number = _number.text.trim().toUpperCase();
      final code = _code.text.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
      final result = await widget.scope.f4Call(
        (api, t, s) => api.verifyReceipt(token: t, siteCode: s, number: number, code: code),
      );
      if (!mounted || token != _token) return;
      setState(() {
        _checking = false;
        _result = result;
      });
    } catch (e) {
      if (!mounted || token != _token) return;
      final limited = _retry.lockIfRateLimited(e, () {
        if (mounted) setState(() {});
      });
      setState(() {
        _checking = false;
        _error = limited
            ? RetryLock.messageFor(e)
            : financeMessageOf(e, 'Doğrulama yapılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return AppDialog(
      title: 'Makbuz Doğrula',
      icon: Icons.verified_user_rounded,
      actions: [
        TextButton(
          onPressed: () => popIfCurrent(context),
          child: const Text('Kapat'),
        ),
        ElevatedButton(
          key: const ValueKey<String>('finance_verify_submit'),
          onPressed: (_checking || _retry.locked) ? null : _check,
          child: Text(_checking ? 'Denetleniyor...' : 'Doğrula'),
        ),
      ],
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null) FinanceSubmitError(message: _error!),
            Text(
              'Makbuz üzerindeki numarayı ve doğrulama kodunu girin. Bilgiler sunucudaki kayıtla karşılaştırılır; '
              'hiçbir şey değişmez.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpace.md),
            TextFormField(
              key: const ValueKey<String>('finance_verify_number'),
              controller: _number,
              enabled: !_checking,
              textCapitalization: TextCapitalization.characters,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              decoration: const InputDecoration(
                labelText: 'Makbuz numarası',
                hintText: 'MK-2026-000123',
                prefixIcon: Icon(Icons.tag_rounded),
              ),
              validator: _validateNumber,
            ),
            const SizedBox(height: AppSpace.md),
            TextFormField(
              key: const ValueKey<String>('finance_verify_code'),
              controller: _code,
              enabled: !_checking,
              textCapitalization: TextCapitalization.characters,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              decoration: const InputDecoration(
                labelText: 'Doğrulama kodu',
                hintText: 'AB12-CD34-EF56',
                prefixIcon: Icon(Icons.pin_rounded),
              ),
              validator: _validateCode,
              onFieldSubmitted: (_) => _check(),
            ),
            if (result != null) ...[
              const SizedBox(height: AppSpace.md),
              InlineNotice(
                key: ValueKey<String>('finance_verify_result_${result.valid}'),
                tone: result.valid
                    ? (result.status == 'cancelled' || result.status == 'cancellation' ? AppTone.warning : AppTone.success)
                    : AppTone.danger,
                message: result.valid
                    ? (result.status == 'cancelled'
                          ? 'Bu makbuz kayıtlarla eşleşiyor ancak İPTAL EDİLMİŞ.'
                          : result.status == 'cancellation'
                          ? 'Bu belge kayıtlarla eşleşiyor: bir makbuzu iptal eden İPTAL MAKBUZUDUR.'
                          : 'Bu makbuz kayıtlarla eşleşiyor ve geçerli.')
                    : 'Girilen numara ve kod kayıtlarla eşleşmiyor. Bilgileri kontrol edin.',
              ),
              // Geçerli sonuçta sunucu eşleşen makbuzun özetini de verir: elindeki belgeyle karşılaştırılabilsin.
              if (result.valid && result.number != null) ...[
                const SizedBox(height: AppSpace.sm),
                DialogPanel(
                  key: const ValueKey<String>('finance_verify_details'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FinanceInfoRow(label: 'Makbuz No', value: result.number),
                      if (result.amountMinor != null) FinanceInfoRow(label: 'Tutar', money: result.amountMinor),
                      if (result.apartmentLabel != null) FinanceInfoRow(label: 'Daire', value: result.apartmentLabel),
                      if (result.paidOn != null) FinanceInfoRow(label: 'Tahsilat tarihi', value: formatCrmDate(result.paidOn)),
                      if (result.issuedOn != null) FinanceInfoRow(label: 'Düzenleme tarihi', value: formatCrmDate(result.issuedOn)),
                    ],
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
