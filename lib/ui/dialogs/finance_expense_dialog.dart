import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MaxLengthEnforcement;
import 'package:site_kapi_kontrol/models/cash_models.dart';
import 'package:site_kapi_kontrol/models/expense_analysis.dart';
import 'package:site_kapi_kontrol/models/expense_models.dart';
import 'package:site_kapi_kontrol/services/expense_attachments.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/crm_confirm_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/crm_pickers.dart' show CrmPickerField;
import 'package:site_kapi_kontrol/ui/dialogs/finance_supplier_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/large_dialog_parts.dart';
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
import 'package:site_kapi_kontrol/ui/widgets/crm_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_4b_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart' show filledToneStyle;
import 'package:site_kapi_kontrol/ui/widgets/money_field.dart';

/// "Gider Ekle" ve "Gideri Düzelt" penceresi (Platform Faz 4b, Ö3).
///
/// - Gider NAKİT esaslıdır: her gider bir hesaptan çıkar (hesap zorunlu; hesap yoksa açıklayıcı uyarı). KDV tutara
///   DAHİLDİR (isteğe bağlı bilgi, tutardan büyük olamaz). Tarih bugünden ileri ve 5 yıldan eski olamaz; kapalı aya
///   yazılamaz (sunucu doğrular).
/// - Çift kayıt önlemleri: `idempotency_key` veri imzasına bağlıdır (belirsiz sonuçtan sonra aynı veri = aynı anahtar);
///   aynı fatura numarası sunucuda reddedilir (`DUPLICATE_DOCUMENT_NO`); son 24 saatte aynı tutar / tarih / kategori
///   `DUPLICATE_EXPENSE` ile uyarılır ve yalnız bilinçli "Yine de kaydet" onayıyla (`allow_duplicate`) yazılır.
/// - Düzeltme ([correcting]): eski gider İPTAL edilir ve yeni gider yazılır (TEK işlemde; yarım kalmaz).
/// - Belge eki: [attachmentSource] verilmedikçe ek alanı GİZLİDİR (belge seçici / modül yoksa). Verilirse en çok 5 dosya
///   (PDF / JPG / PNG) gider kaydından SONRA yüklenir; yüklenemeyenler bildirilir (gider belgesiz de geçerlidir).
class FinanceExpenseDialog extends StatefulWidget {
  const FinanceExpenseDialog({
    super.key,
    required this.scope,
    this.correcting,
    this.attachmentSource,
    this.now,
    this.onRefreshNeeded,
  });

  final PeopleScope scope;
  final Expense? correcting;
  final ExpenseAttachmentSource? attachmentSource;
  final DateTime Function()? now;
  final VoidCallback? onRefreshNeeded;

  static const int maxDescriptionLength = 200;
  static const int maxDocumentNoLength = 40;
  static const int maxAttachments = 5;

  static Future<FinanceWriteOutcome?> show(
    BuildContext context, {
    required PeopleScope scope,
    Expense? correcting,
    ExpenseAttachmentSource? attachmentSource,
    DateTime Function()? now,
    VoidCallback? onRefreshNeeded,
  }) {
    return showDialog<FinanceWriteOutcome>(
      context: context,
      barrierDismissible: false,
      builder: (_) => FinanceExpenseDialog(
        scope: scope,
        correcting: correcting,
        attachmentSource: attachmentSource,
        now: now,
        onRefreshNeeded: onRefreshNeeded,
      ),
    );
  }

  @override
  State<FinanceExpenseDialog> createState() => _FinanceExpenseDialogState();
}

class _FinanceExpenseDialogState extends State<FinanceExpenseDialog> with FinanceWriteMixin, FinanceDiscardGuard {
  @override
  String get keyPrefix => 'exp';

  @override
  Object? get keyOwner => widget.scope.authService;

  @override
  bool get closeLocked => submitting || _asking || _uploading;

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final GlobalKey _accountKey = GlobalKey();
  final GlobalKey _categoryKey = GlobalKey();
  final TextEditingController _description = TextEditingController();
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _vat = TextEditingController();
  final TextEditingController _documentNo = TextEditingController();
  late final TextEditingController _date = TextEditingController(text: formatDateField(_today()));

  List<ExpenseCategory>? _categories;
  List<CashAccount>? _accounts;
  bool _loading = true;
  String? _loadError;
  int _loadToken = 0;

  int? _categoryId;
  Supplier? _supplier;

  // Gider türü (R1): öneri önseçili gelir; kullanıcı dokunursa o gönderilir, dokunmazsa sunucu öneriyi yazar.
  ExpenseNature? _nature;
  bool _natureTouched = false;
  String? _natureReason;
  int _suggestToken = 0;
  String? _supplierHint;
  int? _accountId;
  ExpenseDocumentKind _docKind = ExpenseDocumentKind.none;
  final List<PickedExpenseFile> _files = <PickedExpenseFile>[];
  String? _categoryError;
  String? _accountError;
  String? _filesError;

  String? _dupAllowedSignature;
  bool _asking = false;
  bool _uploading = false;
  String? _uploadProgress;

  bool get _correcting => widget.correcting != null;

  DateTime _today() {
    final wall = istanbulNow(widget.now?.call());
    return DateTime(wall.year, wall.month, wall.day);
  }

  DateTime get _oldest {
    final today = _today();
    return DateTime(today.year - 5, today.month, today.month == 2 && today.day == 29 ? 28 : today.day);
  }

  @override
  void initState() {
    super.initState();
    final e = widget.correcting;
    if (e != null) {
      _description.text = e.description;
      _amount.text = formatMinor(e.amountMinor, symbol: false);
      if (e.vatMinor != null) _vat.text = formatMinor(e.vatMinor!, symbol: false);
      _date.text = formatDateField(e.expenseDate);
      _docKind = e.documentKind;
      _documentNo.text = e.documentNo ?? '';
      _accountId = e.accountId;
      _nature = e.nature;
      _natureReason = e.nature == null ? null : 'Asıl giderin türü korunur.';
    }
    unawaited(_load());
  }

  @override
  void dispose() {
    ++_loadToken;
    disposeWrite();
    _description.dispose();
    _amount.dispose();
    _vat.dispose();
    _documentNo.dispose();
    _date.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    final token = ++_loadToken;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final scope = widget.scope;
      final categories = await scope.f4Call(
        (api, t, s) => api.listExpenseCategories(token: t, siteCode: s, active: true),
      );
      final overview = await scope.f4Call((api, t, s) => api.listAccounts(token: t, siteCode: s));
      Supplier? previous;
      String? hint;
      final e = widget.correcting;
      if (e != null && _supplier == null && (e.supplierId != null || e.supplierName != null)) {
        // Düzeltmede önceki tedarikçi kimlik / ad eşlemesiyle yeniden bulunur; bulunamazsa kullanıcıya söylenir.
        final page = await scope.f4Call(
          (api, t, s) => api.listSuppliers(token: t, siteCode: s, query: e.supplierName, active: true, limit: 20),
        );
        for (final s in page.items) {
          if (s.id == e.supplierId || (e.supplierId == null && s.name.toLowerCase() == (e.supplierName ?? '').toLowerCase())) {
            previous = s;
            break;
          }
        }
        if (previous == null) hint = 'Önceki tedarikçi (${e.supplierName ?? 'bilinmiyor'}) bulunamadı. Gerekirse yeniden seçin.';
      }
      if (!mounted || token != _loadToken) return;
      setState(() {
        _categories = categories;
        _accounts = overview.activeAccounts;
        _loading = false;
        if (e != null && _categoryId == null) {
          for (final c in categories) {
            if (c.id == e.categoryId || (e.categoryId == null && c.name == e.categoryName)) _categoryId = c.id;
          }
        }
        if (_accountId != null && !overview.activeAccounts.any((a) => a.id == _accountId)) _accountId = null;
        if (_accountId == null && overview.activeAccounts.length == 1) _accountId = overview.activeAccounts.first.id;
        _supplier ??= previous;
        _supplierHint = hint;
      });
    } catch (e) {
      if (!mounted || token != _loadToken) return;
      setState(() {
        _loading = false;
        _loadError = financeMessageOf(
          e,
          'Kategori ve hesap bilgileri yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
        );
      });
    }
  }

  /// Kategori / tedarikçi değişince öneriyi getirir (kullanıcı türe dokunduysa dokunmaz). Hata sessizdir: tür seçimi yine yapılabilir.
  Future<void> _refreshSuggestion() async {
    final categoryId = _categoryId;
    if (categoryId == null || _natureTouched) return;
    final token = ++_suggestToken;
    final date = parseDateField(_date.text) ?? _today();
    try {
      final s = await widget.scope.f4Call(
        (api, t, site) => api.getNatureSuggestion(token: t, siteCode: site, categoryId: categoryId, supplierId: _supplier?.id, expenseDate: date),
      );
      if (!mounted || token != _suggestToken || _natureTouched) return;
      setState(() {
        _nature = s.nature;
        _natureReason = 'Öneri: ${s.nature.label.toLowerCase()} — ${s.reasonText}';
      });
    } catch (_) {
      // öneri alınamadı: kullanıcı türü elle seçebilir
    }
  }

  Widget _natureField(TextTheme th) {
    return Column(
      key: const ValueKey<String>('finance_expense_nature'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Gider türü', style: th.labelLarge),
        const SizedBox(height: AppSpace.xs),
        SegmentedButton<ExpenseNature>(
          showSelectedIcon: false,
          emptySelectionAllowed: true,
          segments: [
            for (final n in ExpenseNature.values) ButtonSegment<ExpenseNature>(value: n, label: Text(n.label), tooltip: n.label),
          ],
          selected: _nature == null ? <ExpenseNature>{} : <ExpenseNature>{_nature!},
          onSelectionChanged: submitting
              ? null
              : (set) {
                  if (set.isEmpty) return;
                  markDirty();
                  setState(() {
                    _nature = set.first;
                    _natureTouched = true;
                    _natureReason = 'Seçiminiz kullanılacak.';
                  });
                },
        ),
        if (_natureReason != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.xs),
            child: Text(_natureReason!, key: const ValueKey<String>('finance_expense_nature_reason'), style: th.bodySmall),
          ),
      ],
    );
  }

  Future<void> _pickSupplier() async {
    if (submitting) return;
    final choice = await FinanceSupplierPickerDialog.show(context, scope: widget.scope);
    if (choice == null || !mounted) return;
    markDirty();
    setState(() {
      _supplier = choice.supplier;
      _supplierHint = null;
    });
    unawaited(_refreshSuggestion());
  }

  Future<void> _pickFiles() async {
    final source = widget.attachmentSource;
    if (source == null || submitting) return;
    final room = FinanceExpenseDialog.maxAttachments - _files.length;
    if (room <= 0) return;
    final picked = await source.pick(context, maxCount: room);
    if (!mounted || picked.isEmpty) return;
    final rejected = picked.where((f) => !f.isAllowedType).map((f) => f.name).toList();
    markDirty();
    setState(() {
      _files.addAll(picked.where((f) => f.isAllowedType).take(room));
      _filesError = rejected.isEmpty
          ? null
          : 'Yalnızca PDF, JPG ve PNG eklenebilir. Eklenmeyen: ${rejected.join(', ')}.';
    });
  }

  bool _validateChoices() {
    final accounts = _accounts ?? const <CashAccount>[];
    setState(() {
      _categoryError = _categoryId == null ? 'Gider kategorisini seçin.' : null;
      _accountError = accounts.isNotEmpty && _accountId == null ? 'Giderin çıkacağı hesabı seçin.' : null;
    });
    return _categoryId != null && accounts.isNotEmpty && _accountId != null;
  }

  void _reveal(BuildContext formContext) {
    if (revealFirstInvalidField(formContext)) return;
    final key = _categoryError != null ? _categoryKey : (_accountError != null ? _accountKey : null);
    final target = key?.currentContext;
    if (target != null) Scrollable.ensureVisible(target, alignment: 0.15, duration: Duration.zero);
  }

  Future<void> _submit() async {
    if (writeBlocked || _asking || _uploading) return;
    final ok = validateForm(_formKey, validateExtra: _validateChoices, reveal: _reveal);
    if (!ok) {
      setState(() => submitError = kFixFieldsMessage);
      return;
    }
    final minor = parseMoney(_amount.text).minor!;
    final vat = _vat.text.trim().isEmpty ? null : parseMoney(_vat.text, allowZero: true).minor;
    final date = parseDateField(_date.text)!;
    final documentNo = _docKind == ExpenseDocumentKind.none ? null : _documentNo.text.trim();
    final input = ExpenseInput(
      categoryId: _categoryId!,
      supplierId: _supplier?.id,
      description: _description.text.trim(),
      amountMinor: minor,
      vatMinor: vat,
      expenseDate: date,
      accountId: _accountId!,
      documentKind: _docKind,
      documentNo: documentNo,
      nature: _natureTouched ? _nature : null,
    );
    final base =
        '${widget.correcting?.id ?? 0}|${input.categoryId}|${input.supplierId ?? 0}|${input.description}|$minor|${vat ?? -1}|'
        '${formatDateField(date)}|${input.accountId}|${_docKind.apiValue}|${documentNo ?? ''}|${input.nature?.apiValue ?? ''}';
    await _write(input, base);
  }

  Future<void> _write(ExpenseInput input, String base) async {
    final allow = _dupAllowedSignature == base;
    final effective = allow
        ? ExpenseInput(
            categoryId: input.categoryId,
            supplierId: input.supplierId,
            description: input.description,
            amountMinor: input.amountMinor,
            vatMinor: input.vatMinor,
            expenseDate: input.expenseDate,
            accountId: input.accountId,
            documentKind: input.documentKind,
            documentNo: input.documentNo,
            allowDuplicate: true,
            nature: input.nature,
          )
        : input;
    final scope = widget.scope;
    final correcting = widget.correcting;
    await runWrite<Expense>(
      signature: allow ? '$base|dup' : base,
      action: (key) async {
        if (correcting != null) {
          final result = await scope.f4Call(
            (api, t, s) => api.correctExpense(token: t, siteCode: s, expenseId: correcting.id, input: effective, idempotencyKey: key),
          );
          return result.expense;
        }
        final result = await scope.f4Call(
          (api, t, s) => api.createExpense(token: t, siteCode: s, input: effective, idempotencyKey: key),
        );
        return result.expense;
      },
      onSuccess: (expense) async {
        var message = correcting != null
            ? 'Gider düzeltildi: ${formatMinor(expense.amountMinor)} (${expense.categoryName}).'
            : 'Gider kaydedildi: ${formatMinor(expense.amountMinor)} (${expense.categoryName}).';
        if (_files.isNotEmpty) {
          message = '$message ${await _uploadFiles(expense.id)}';
        }
        if (mounted) popIfCurrent(context, FinanceWriteOutcome(message));
      },
      failure: correcting != null
          ? 'Gider düzeltilemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.'
          : 'Gider kaydedilemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
      onError: (e) {
        if (!hasErrorCode(e, 'DUPLICATE_EXPENSE')) return false;
        // Aynı gider yakın zamanda kaydedilmiş: bilinçli onay istenir (otomatik tekrar yok).
        unawaited(Future<void>.microtask(() => _askDuplicate(input, base)));
        return true;
      },
    );
  }

  Future<void> _askDuplicate(ExpenseInput input, String base) async {
    if (!mounted) return;
    setState(() => _asking = true);
    final bool proceed;
    try {
      proceed = await confirmCrmAction(
        context,
        title: 'Aynı gider daha önce kaydedilmiş',
        message:
            'Aynı tutar, tarih ve kategoriyle bir gider son 24 saatte kaydedilmiş görünüyor. Önce gider listesini '
            'kontrol edin. Gerçekten ikinci bir gider ise devam edebilirsiniz.',
        confirmLabel: 'Yine de kaydet',
        icon: Icons.warning_amber_rounded,
        tone: AppTone.danger,
      );
    } finally {
      if (mounted) setState(() => _asking = false);
    }
    if (!proceed || !mounted) return;
    _dupAllowedSignature = base;
    await _write(input, base);
  }

  Future<String> _uploadFiles(int expenseId) async {
    setState(() {
      _uploading = true;
      _uploadProgress = null;
    });
    try {
      final service = widget.scope.f4;
      final files = List<PickedExpenseFile>.of(_files);
      final signatures = expenseUploadSignatures(expenseId, files);
      final results = await uploadExpenseFiles(
        service: service,
        siteCode: widget.scope.siteCode,
        expenseId: expenseId,
        files: files,
        keyFor: (file) => keys.keyFor(signatures[file]!),
        onProgress: (i, n) {
          if (mounted) setState(() => _uploadProgress = 'Belge yükleniyor ($i/$n)...');
        },
        isCancelled: () => !mounted,
      );
      final failed = results.where((r) => !r.ok).toList();
      for (final r in results.where((r) => r.ok)) {
        keys.clear(signatures[r.file]!);
      }
      if (failed.isEmpty) return '${results.length} belge eklendi.';
      return '${results.length - failed.length} belge eklendi, ${failed.length} belge yüklenemedi '
          '(${failed.map((r) => r.file.name).join(', ')}). Gider ayrıntısından yeniden ekleyebilirsiniz.';
    } finally {
      if (mounted) {
        setState(() {
          _uploading = false;
          _uploadProgress = null;
        });
      }
    }
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
    final busy = submitting || _asking || _uploading;
    final accounts = _accounts;
    final noAccount = accounts != null && accounts.isEmpty;
    final ready = !_loading && _loadError == null && _categories != null && accounts != null;
    return PopScope(
      canPop: canPopNow,
      onPopInvokedWithResult: (didPop, _) {
        handleBlockedPop(didPop);
        if (didPop) _notify();
      },
      child: AppDialog(
        title: _correcting ? 'Gideri Düzelt' : 'Gider Ekle',
        subtitle: widget.scope.siteName.isEmpty ? null : widget.scope.siteName,
        icon: Icons.shopping_bag_rounded,
        actions: [
          TextButton(
            onPressed: busy ? null : requestClose,
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            key: const ValueKey<String>('finance_expense_submit'),
            style: filledToneStyle(context),
            onPressed: (busy || retry.locked || !ready || noAccount) ? null : _submit,
            child: Text(busy ? (_uploading ? 'Belgeler yükleniyor...' : 'Kaydediliyor...') : (_correcting ? 'Düzelt' : 'Kaydet')),
          ),
        ],
        child: !ready
            ? (_loading
                  ? const DialogRowsSkeleton(rows: 3, caption: 'Kategori ve hesaplar yükleniyor...')
                  : InlineNotice(message: _loadError ?? 'Bilgiler yüklenemedi.', onRetry: _load))
            : Form(
                key: _formKey,
                onChanged: markDirty,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (submitError != null) FinanceSubmitError(message: submitError!),
                    if (_correcting) ...[
                      DialogPanel(
                        key: const ValueKey<String>('finance_expense_original'),
                        tone: AppTone.info,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const DialogSectionTitle(icon: Icons.history_rounded, title: 'Düzeltilen gider', tone: AppTone.info),
                            const SizedBox(height: AppSpace.sm),
                            Text(
                              '${widget.correcting!.description} • ${formatMinor(widget.correcting!.amountMinor)}',
                              semanticsLabel: spokenMoneyText('${widget.correcting!.description} • ${formatMinor(widget.correcting!.amountMinor)}'),
                              style: th.bodyMedium,
                            ),
                            const SizedBox(height: AppSpace.xs),
                            Text(
                              'Bu gider silinmez: iptal edilir ve aşağıdaki bilgilerle yeni bir gider yazılır. '
                              'İkisi tek işlemde yapılır.',
                              style: th.bodySmall?.copyWith(color: p.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpace.md),
                    ],
                    if (noAccount) ...[
                      const InlineNotice(
                        key: ValueKey<String>('finance_expense_no_account'),
                        tone: AppTone.warning,
                        message:
                            'Gider kaydı için bir kasa ya da banka hesabı gerekir. Önce Kasa sekmesinden bir hesap ekleyin.',
                      ),
                      const SizedBox(height: AppSpace.md),
                    ],
                    KeyedSubtree(
                      key: _categoryKey,
                      child: DropdownButtonFormField<int>(
                        key: ValueKey<String>('finance_expense_category_${_categoryId ?? 0}'),
                        isExpanded: true,
                        initialValue: _categoryId,
                        dropdownColor: p.surface,
                        style: th.bodyMedium?.copyWith(color: p.text),
                        decoration: InputDecoration(
                          labelText: 'Kategori',
                          prefixIcon: const Icon(Icons.sell_rounded),
                          errorText: _categoryError,
                          errorMaxLines: 3,
                        ),
                        items: [
                          for (final c in _categories!)
                            DropdownMenuItem<int>(
                              value: c.id,
                              child: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                            ),
                        ],
                        onChanged: busy
                            ? null
                            : (v) {
                            setState(() {
                                markDirty();
                                _categoryId = v;
                                _categoryError = null;
                              });
                              unawaited(_refreshSuggestion());
                            },
                      ),
                    ),
                    const SizedBox(height: AppSpace.md),
                    _natureField(th),
                    const SizedBox(height: AppSpace.md),
                    CrmPickerField(
                      key: const ValueKey<String>('finance_expense_supplier'),
                      label: 'Tedarikçi (isteğe bağlı)',
                      icon: Icons.storefront_rounded,
                      value: _supplier?.name,
                      placeholder: 'Tedarikçi seçmek için dokunun',
                      enabled: !busy,
                      onTap: _pickSupplier,
                      onClear: _supplier == null
                          ? null
                          : () => setState(() {
                              markDirty();
                              _supplier = null;
                            }),
                    ),
                    if (_supplierHint != null)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpace.xs),
                        child: Text(_supplierHint!, style: th.bodySmall?.copyWith(color: AppTone.warning.ink(p))),
                      ),
                    const SizedBox(height: AppSpace.md),
                    TextFormField(
                      key: const ValueKey<String>('finance_expense_description'),
                      controller: _description,
                      enabled: !busy,
                      minLines: 1,
                      maxLines: 3,
                      maxLength: FinanceExpenseDialog.maxDescriptionLength,
                      maxLengthEnforcement: MaxLengthEnforcement.none,
                      buildCounter: (context, {required currentLength, required isFocused, maxLength}) => characterCounter(
                        context,
                        trimmedCodePoints(_description.text),
                        FinanceExpenseDialog.maxDescriptionLength,
                      ),
                      textCapitalization: TextCapitalization.sentences,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Açıklama',
                        hintText: 'Örn. Eylül ayı asansör bakımı',
                        alignLabelWithHint: true,
                        prefixIcon: Icon(Icons.notes_rounded),
                      ),
                      validator: (value) {
                        final length = trimmedCodePoints(value ?? '');
                        if (length < 1) return 'Gider açıklamasını girin.';
                        if (length > FinanceExpenseDialog.maxDescriptionLength) {
                          return 'Açıklama en çok ${FinanceExpenseDialog.maxDescriptionLength} karakter olabilir.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: AppSpace.md),
                    MoneyFormField(
                      key: const ValueKey<String>('finance_expense_amount_group'),
                      fieldKey: const ValueKey<String>('finance_expense_amount'),
                      controller: _amount,
                      enabled: !busy,
                      label: 'Gider tutarı',
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: AppSpace.md),
                    TextFormField(
                      key: const ValueKey<String>('finance_expense_vat'),
                      controller: _vat,
                      enabled: !busy,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      decoration: const InputDecoration(
                        labelText: 'KDV tutarı (isteğe bağlı)',
                        suffixText: kMoneySymbol,
                        prefixIcon: Icon(Icons.percent_rounded),
                        helperText: 'KDV, gider tutarına DAHİLDİR; yalnız bilgi amaçlıdır.',
                        helperMaxLines: 3,
                      ),
                      validator: (value) {
                        if ((value ?? '').trim().isEmpty) return null;
                        final parsed = parseMoney(value, allowZero: true);
                        if (parsed.minor == null) return parsed.message;
                        final total = parseMoney(_amount.text).minor;
                        if (total != null && parsed.minor! > total) return 'KDV tutarı gider tutarından büyük olamaz.';
                        return null;
                      },
                    ),
                    const SizedBox(height: AppSpace.md),
                    FinanceDateField(
                      key: const ValueKey<String>('finance_expense_date_group'),
                      controller: _date,
                      label: 'Gider tarihi',
                      enabled: !busy,
                      maxDate: _today(),
                      minDate: _oldest,
                      minMessage: 'Tarih bugünden en fazla 5 yıl öncesi olabilir.',
                    ),
                    const SizedBox(height: AppSpace.lg),
                    KeyedSubtree(
                      key: _accountKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const FinanceGroupTitle('Çıkacağı hesap'),
                          const SizedBox(height: AppSpace.sm),
                          Wrap(
                            spacing: AppSpace.sm,
                            runSpacing: AppSpace.sm,
                            children: [
                              for (final a in accounts)
                                ChoiceChip(
                                  key: ValueKey<String>('finance_expense_account_${a.id}'),
                                  avatar: Icon(cashKindIcon(a.kind), size: 18),
                                  label: Text(a.name),
                                  selected: _accountId == a.id,
                                  onSelected: busy
                                      ? null
                                      : (_) => setState(() {
                                          markDirty();
                                          _accountId = a.id;
                                          _accountError = null;
                                        }),
                                ),
                            ],
                          ),
                          if (_accountError != null) ...[
                            const SizedBox(height: AppSpace.sm),
                            CrmFormError(message: _accountError!, reveal: false),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpace.lg),
                    const FinanceGroupTitle('Belge türü'),
                    const SizedBox(height: AppSpace.sm),
                    Wrap(
                      spacing: AppSpace.sm,
                      runSpacing: AppSpace.sm,
                      children: [
                        for (final kind in ExpenseDocumentKind.values)
                          ChoiceChip(
                            key: ValueKey<String>('finance_expense_doc_${kind.apiValue}'),
                            label: Text(kind.label),
                            selected: _docKind == kind,
                            onSelected: busy
                                ? null
                                : (_) => setState(() {
                                    markDirty();
                                    _docKind = kind;
                                  }),
                          ),
                      ],
                    ),
                    if (_docKind != ExpenseDocumentKind.none) ...[
                      const SizedBox(height: AppSpace.md),
                      TextFormField(
                        key: const ValueKey<String>('finance_expense_document_no'),
                        controller: _documentNo,
                        enabled: !busy,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        decoration: const InputDecoration(
                          labelText: 'Belge / fatura no (isteğe bağlı)',
                          prefixIcon: Icon(Icons.tag_rounded),
                          helperText: 'Aynı tedarikçiden aynı numara ikinci kez girilemez.',
                          helperMaxLines: 3,
                        ),
                        validator: (value) => trimmedCodePoints(value ?? '') > FinanceExpenseDialog.maxDocumentNoLength
                            ? 'Belge no en çok ${FinanceExpenseDialog.maxDocumentNoLength} karakter olabilir.'
                            : null,
                      ),
                    ],
                    if (widget.attachmentSource != null) ...[
                      const SizedBox(height: AppSpace.lg),
                      _buildAttachments(context, busy),
                    ],
                    if (_uploadProgress != null) ...[
                      const SizedBox(height: AppSpace.md),
                      DialogLoadingNote(text: _uploadProgress!),
                    ],
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildAttachments(BuildContext context, bool busy) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    return Column(
      key: const ValueKey<String>('finance_expense_attachments'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const FinanceGroupTitle('Belge eki (isteğe bağlı)'),
        const SizedBox(height: AppSpace.xs),
        Text(
          'En çok 5 dosya (PDF, JPG, PNG). Kimlik numarası ve IBAN gibi bilgileri karartın; telefon fotoğrafları konum '
          'bilgisi içerebilir.',
          style: th.bodySmall?.copyWith(color: p.textSecondary),
        ),
        const SizedBox(height: AppSpace.sm),
        for (var i = 0; i < _files.length; i++)
          DialogPanel(
            key: ValueKey<String>('finance_expense_file_$i'),
            child: Row(
              children: [
                const Icon(Icons.attach_file_rounded, size: 18),
                const SizedBox(width: AppSpace.sm),
                Expanded(child: Text(_files[i].name, style: th.bodyMedium)),
                IconButton(
                  tooltip: '${_files[i].name} dosyasını çıkar',
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                  onPressed: busy
                      ? null
                      : () => setState(() {
                          markDirty();
                          _files.removeAt(i);
                        }),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
        if (_filesError != null) ...[
          const SizedBox(height: AppSpace.sm),
          CrmFormError(message: _filesError!, reveal: false),
        ],
        if (_files.length < FinanceExpenseDialog.maxAttachments)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: PrimaryActionButton(
              key: const ValueKey<String>('finance_expense_add_file'),
              label: 'Belge Ekle',
              icon: Icons.upload_file_rounded,
              variant: AppButtonVariant.tonal,
              expand: false,
              onPressed: busy ? null : _pickFiles,
            ),
          ),
      ],
    );
  }
}
