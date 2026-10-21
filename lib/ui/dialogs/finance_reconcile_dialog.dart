import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MaxLengthEnforcement;
import 'package:site_kapi_kontrol/models/cash_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/crm_confirm_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/large_dialog_parts.dart';
import 'package:site_kapi_kontrol/ui/helpers/a11y_announce.dart';
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
import 'package:site_kapi_kontrol/ui/widgets/money_field.dart';

/// Mutabakat penceresi (Platform Faz 4b, Ö4): banka ekstresi / sayım bakiyesi girilir, sunucunun hesapladığı bakiyeyle
/// karşılaştırılır, FARK gösterilir; isteğe bağlı olarak fark bir düzeltme hareketi olarak AYNI işlemde yazılır.
///
/// - Hesaplanan bakiye pencere açılırken sunucudan TAZE okunur; okunamazsa mutabakat yapılamaz (hata + "Tekrar Dene").
///   Kayıt, bu bakiyeyi `expected_computed_minor` olarak bildirir: hesap bu arada değiştiyse sunucu 409
///   `RECONCILIATION_STALE` döner, yeni bakiye gösterilir ve kullanıcı farkı yeniden görüp onaylar (eski farkla yazılmaz).
/// - Mutabakat tarihi her zaman BUGÜNDÜR (geçmiş tarihli mutabakat bu pencerede yoktur).
/// - Fark sıfır değilse düzeltme isteğe bağlıdır; düzeltilmeyen fark kayıtlıdır ve raporlarda uyarı olarak görünür.
/// - Daha YENİ tarihli, düzeltmesi yazılmış bir mutabakat varken düzeltmeli kayıt 409 `RECONCILIATION_ORDER` alır: sunucu
///   iletisi gösterilir ve "Yalnız kayıt olarak gir" sunulur (aynı veriyle, düzeltme OLMADAN, yeni işlem anahtarıyla; farkın
///   düzeltilmeyeceği açıkça söylenir ve onay istenir).
class FinanceReconcileDialog extends StatefulWidget {
  const FinanceReconcileDialog({super.key, required this.scope, required this.account, this.now, this.onRefreshNeeded});

  final PeopleScope scope;
  final CashAccount account;
  final DateTime Function()? now;
  final VoidCallback? onRefreshNeeded;

  static const int maxNoteLength = 200;

  static Future<FinanceWriteOutcome?> show(
    BuildContext context, {
    required PeopleScope scope,
    required CashAccount account,
    DateTime Function()? now,
    VoidCallback? onRefreshNeeded,
  }) {
    return showDialog<FinanceWriteOutcome>(
      context: context,
      barrierDismissible: false,
      builder: (_) => FinanceReconcileDialog(scope: scope, account: account, now: now, onRefreshNeeded: onRefreshNeeded),
    );
  }

  @override
  State<FinanceReconcileDialog> createState() => _FinanceReconcileDialogState();
}

class _FinanceReconcileDialogState extends State<FinanceReconcileDialog> with FinanceWriteMixin, FinanceDiscardGuard {
  @override
  String get keyPrefix => 'recon';

  @override
  Object? get keyOwner => widget.scope.authService;

  @override
  bool get closeLocked => submitting;

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _statement = TextEditingController();
  final TextEditingController _note = TextEditingController();
  final TextEditingController _adjustNote = TextEditingController();

  int? _computed;
  bool _loading = true;
  String? _loadError;
  int _loadToken = 0;
  bool _negative = false;
  bool _adjust = false;
  AdjustmentReason? _reason;
  String? _reasonError;
  String? _staleNotice;
  bool _orderConflict = false;

  DateTime _today() {
    final wall = istanbulNow(widget.now?.call());
    return DateTime(wall.year, wall.month, wall.day);
  }

  @override
  void initState() {
    super.initState();
    unawaited(_loadComputed());
  }

  @override
  void dispose() {
    ++_loadToken;
    disposeWrite();
    _statement.dispose();
    _note.dispose();
    _adjustNote.dispose();
    super.dispose();
  }

  /// Hesaplanan (sunucu) bakiyeyi hesap listesinden tazeler.
  Future<void> _loadComputed() async {
    if (!mounted) return;
    final token = ++_loadToken;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final overview = await widget.scope.f4Call((api, t, s) => api.listAccounts(token: t, siteCode: s));
      if (!mounted || token != _loadToken) return;
      final match = overview.items.where((a) => a.id == widget.account.id).toList();
      if (match.isEmpty) {
        setState(() {
          _loading = false;
          _loadError = 'Hesap bulunamadı. Listeyi yenileyip tekrar deneyin.';
        });
        return;
      }
      setState(() {
        _computed = match.first.balanceMinor;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || token != _loadToken) return;
      setState(() {
        _loading = false;
        _computed = null;
        _loadError = financeMessageOf(e, 'Hesap bakiyesi okunamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.');
      });
    }
  }

  int? get _statementMinor {
    final minor = parseMoney(_statement.text, allowZero: true).minor;
    if (minor == null) return null;
    return _negative ? -minor : minor;
  }

  int? get _difference {
    final computed = _computed;
    final statement = _statementMinor;
    if (computed == null || statement == null) return null;
    return statement - computed;
  }

  /// "Yalnız kayıt olarak gir": RECONCILIATION_ORDER sonrası aynı veriyle, düzeltme OLMADAN yeniden gönderir (onayla).
  Future<void> _recordOnly() async {
    if (writeBlocked) return;
    final difference = _difference ?? 0;
    final text = 'Banka / kasa kontrolü yalnızca kayıt olarak girilecek: ${formatSignedMinor(difference)} tutarındaki fark DÜZELTİLMEYECEK '
        've hesap bakiyesi değişmeyecek. Fark raporlarda uyarı olarak görünür. Önce daha yeni tarihli kontrolün düzeltmesini '
        'gözden geçirmek isterseniz vazgeçin.';
    final ok = await confirmCrmAction(
      context,
      title: 'Fark düzeltilmeden kaydedilsin mi?',
      message: text,
      semanticMessage: spokenMoneyText(text),
      confirmLabel: 'Yalnız Kayıt Olarak Gir',
      icon: Icons.warning_amber_rounded,
    );
    if (!ok || !mounted) return;
    setState(() {
      markDirty();
      _adjust = false;
    });
    await _submit(recordOnly: true);
  }

  Future<void> _submit({bool recordOnly = false}) async {
    if (writeBlocked) return;
    final computed = _computed;
    final difference = _difference;
    _orderConflict = false;
    final ok = validateForm(
      _formKey,
      validateExtra: () {
        final needReason = !recordOnly && _adjust && (difference ?? 0) != 0;
        setState(() => _reasonError = needReason && _reason == null ? 'Düzeltme nedenini seçin.' : null);
        return computed != null && (!needReason || _reason != null);
      },
    );
    if (!ok || computed == null) {
      setState(() => submitError = kFixFieldsMessage);
      return;
    }
    final statement = _statementMinor!;
    final note = _note.text.trim();
    final adjusting = !recordOnly && _adjust && (difference ?? 0) != 0;
    final reason = adjusting ? _reason : null;
    final adjustNote = adjusting ? _adjustNote.text.trim() : '';
    final today = _today();
    await runWrite<ReconciliationResult>(
      signature:
          'recon|${widget.account.id}|$statement|$computed|${reason?.apiValue ?? '-'}|$adjustNote|$note',
      action: (key) => widget.scope.f4Call(
        (api, t, s) => api.reconcileAccount(
          token: t,
          siteCode: s,
          accountId: widget.account.id,
          asOfDate: today,
          statementBalanceMinor: statement,
          expectedComputedMinor: computed,
          note: note,
          adjustReason: reason,
          adjustNote: adjustNote,
          idempotencyKey: key,
        ),
      ),
      onSuccess: (result) {
        final diff = result.reconciliation.differenceMinor;
        final message = diff == 0
            ? 'Banka / kasa kontrolü kaydedildi: ${widget.account.name} bakiyesi ekstreyle tutuyor.'
            : (result.reconciliation.adjusted
                  ? 'Banka / kasa kontrolü kaydedildi: fark ${formatSignedMinor(diff)} düzeltme hareketiyle giderildi.'
                  : 'Banka / kasa kontrolü kaydedildi: fark ${formatSignedMinor(diff)} düzeltilmedi; raporlarda uyarı olarak görünür.');
        popIfCurrent(context, FinanceWriteOutcome(message));
      },
      failure: 'Banka / kasa kontrolü kaydedilemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
      onError: (e) {
        if (hasErrorCode(e, 'RECONCILIATION_ORDER')) {
          // Sunucu iletisi (ya da eşlenen Türkçe metin) gösterilir; "Yalnız kayıt olarak gir" eylemi sunulur.
          _orderConflict = true;
          return false;
        }
        if (!hasErrorCode(e, 'RECONCILIATION_STALE')) return false;
        // Hesap bu arada değişti: yeni hesaplanan bakiye gösterilir; kullanıcı farkı yeniden görüp onaylar.
        final fresh = ReconciliationStaleInfo.fromPayload(e is ApiException ? e.payload : null).computedMinor;
        final text = fresh == null
            ? 'Hesap bakiyesi siz bakarken değişti. Güncel bakiye yükleniyor; farkı yeniden kontrol edin.'
            : 'Hesap bakiyesi siz bakarken değişti. Güncel hesaplanan bakiye ${formatMinor(fresh)}; farkı yeniden kontrol edip onaylayın.';
        _staleNotice = text;
        if (fresh != null) {
          _computed = fresh;
        } else {
          unawaited(_loadComputed());
        }
        announcePolite(context, spokenMoneyText(text));
        return true;
      },
    );
  }

  void _notify() {
    if (!needsRefreshOnClose) return;
    needsRefreshOnClose = false;
    widget.onRefreshNeeded?.call();
  }

  /// RECONCILIATION_ORDER eylemi: ne yapacağını ve sonucunu açıkça söyler.
  Widget _recordOnlyAction(BuildContext context, int? difference) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final info = difference == null || difference == 0
        ? 'Banka / kasa kontrolü yalnızca kayıt olarak girilir.'
        : 'Banka / kasa kontrolü yalnızca kayıt olarak girilir: ${formatSignedMinor(difference)} tutarındaki fark düzeltilmez ve raporlarda uyarı olarak görünür.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FinanceSpokenText(info, style: th.bodySmall?.copyWith(color: p.textSecondary)),
        const SizedBox(height: AppSpace.sm),
        PrimaryActionButton(
          key: const ValueKey<String>('finance_reconcile_record_only'),
          label: 'Yalnız kayıt olarak gir',
          icon: Icons.fact_check_rounded,
          variant: AppButtonVariant.tonal,
          onPressed: writeBlocked ? null : _recordOnly,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final computed = _computed;
    final difference = _difference;
    final Widget computedBox;
    if (_loading && computed == null) {
      computedBox = const DialogLoadingNote(text: 'Hesaplanan bakiye okunuyor...');
    } else if (computed == null) {
      computedBox = InlineNotice(
        key: const ValueKey<String>('finance_reconcile_load_error'),
        message: _loadError ?? 'Hesap bakiyesi okunamadı.',
        onRetry: _loadComputed,
      );
    } else {
      computedBox = DialogPanel(
        key: const ValueKey<String>('finance_reconcile_computed'),
        child: Semantics(
          container: true,
          label: 'Sistemde hesaplanan bakiye: ${moneySemanticLabel(computed)}',
          child: ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Sistemde hesaplanan bakiye', style: th.bodySmall?.copyWith(color: p.textSecondary)),
                Text(formatMinor(computed), style: th.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                Text('Tarih: bugün (${formatDateField(_today())})', style: th.bodySmall),
              ],
            ),
          ),
        ),
      );
    }
    return PopScope(
      canPop: canPopNow,
      onPopInvokedWithResult: (didPop, _) {
        handleBlockedPop(didPop);
        if (didPop) _notify();
      },
      child: AppDialog(
        title: 'Banka / kasa kontrolü',
        subtitle: widget.account.name,
        icon: Icons.fact_check_rounded,
        actions: [
          TextButton(
            onPressed: submitting ? null : requestClose,
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            key: const ValueKey<String>('finance_reconcile_submit'),
            onPressed: (writeBlocked || computed == null) ? null : _submit,
            child: Text(submitting ? 'Kaydediliyor...' : 'Kontrolü Kaydet'),
          ),
        ],
        child: Form(
          key: _formKey,
          onChanged: markDirty,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (submitError != null)
                FinanceSubmitError(
                  message: submitError!,
                  action: (_orderConflict && _adjust) ? _recordOnlyAction(context, difference) : null,
                ),
              if (_staleNotice != null) ...[
                InlineNotice(
                  key: const ValueKey<String>('finance_reconcile_stale'),
                  tone: AppTone.warning,
                  message: _staleNotice!,
                  semanticsLabel: spokenMoneyText(_staleNotice!),
                ),
                const SizedBox(height: AppSpace.md),
              ],
              Text(
                'Banka ekstresindeki ya da kasada saydığınız bakiyeyi girin; sistemdeki bakiyeyle karşılaştırılır.',
                style: th.bodyMedium,
              ),
              const SizedBox(height: AppSpace.md),
              computedBox,
              const SizedBox(height: AppSpace.md),
              MoneyFormField(
                key: const ValueKey<String>('finance_reconcile_statement_group'),
                fieldKey: const ValueKey<String>('finance_reconcile_statement'),
                controller: _statement,
                enabled: !submitting,
                label: 'Ekstre / sayım bakiyesi',
                allowZero: true,
                textInputAction: TextInputAction.done,
                onChanged: (_) => setState(() {}),
              ),
              Material(
                type: MaterialType.transparency,
                child: SwitchListTile(
                  key: const ValueKey<String>('finance_reconcile_negative'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Bakiye eksi (borçta)'),
                  value: _negative,
                  onChanged: submitting ? null : (v) => setState(() {
                    markDirty();
                    _negative = v;
                  }),
                ),
              ),
              if (difference != null) ...[
                const SizedBox(height: AppSpace.sm),
                _DifferenceBox(difference: difference),
              ],
              if (difference != null && difference != 0) ...[
                const SizedBox(height: AppSpace.md),
                Material(
                  type: MaterialType.transparency,
                  child: SwitchListTile(
                    key: const ValueKey<String>('finance_reconcile_adjust'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Farkı düzeltme hareketi olarak yaz'),
                    subtitle: const Text('Kapalıysa fark kaydedilir ama düzeltilmez; raporlarda uyarı olarak kalır.'),
                    value: _adjust,
                    onChanged: submitting ? null : (v) => setState(() {
                      markDirty();
                      _adjust = v;
                    }),
                  ),
                ),
                if (_adjust) ...[
                  const SizedBox(height: AppSpace.sm),
                  const FinanceGroupTitle('Düzeltme nedeni'),
                  const SizedBox(height: AppSpace.sm),
                  Wrap(
                    spacing: AppSpace.sm,
                    runSpacing: AppSpace.sm,
                    children: [
                      for (final reason in AdjustmentReason.values)
                        ChoiceChip(
                          key: ValueKey<String>('finance_reconcile_reason_${reason.apiValue}'),
                          label: Text(reason.label),
                          selected: _reason == reason,
                          onSelected: submitting
                              ? null
                              : (_) => setState(() {
                                  markDirty();
                                  _reason = reason;
                                  _reasonError = null;
                                }),
                        ),
                    ],
                  ),
                  if (_reasonError != null) ...[
                    const SizedBox(height: AppSpace.sm),
                    CrmFormError(message: _reasonError!, reveal: false),
                  ],
                  const SizedBox(height: AppSpace.md),
                  TextFormField(
                    key: const ValueKey<String>('finance_reconcile_adjust_note'),
                    controller: _adjustNote,
                    enabled: !submitting,
                    maxLength: FinanceReconcileDialog.maxNoteLength,
                    maxLengthEnforcement: MaxLengthEnforcement.none,
                    buildCounter: (context, {required currentLength, required isFocused, maxLength}) => characterCounter(
                      context,
                      trimmedCodePoints(_adjustNote.text),
                      FinanceReconcileDialog.maxNoteLength,
                    ),
                    textCapitalization: TextCapitalization.sentences,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: _reason == AdjustmentReason.other ? 'Düzeltme notu (zorunlu)' : 'Düzeltme notu (isteğe bağlı)',
                      prefixIcon: const Icon(Icons.notes_rounded),
                    ),
                    validator: (value) {
                      final length = trimmedCodePoints(value ?? '');
                      if (_adjust && _reason == AdjustmentReason.other && length < 1) {
                        return '"Diğer" nedeninde açıklama notu zorunludur.';
                      }
                      if (length > FinanceReconcileDialog.maxNoteLength) {
                        return 'Not en çok ${FinanceReconcileDialog.maxNoteLength} karakter olabilir.';
                      }
                      return null;
                    },
                  ),
                ],
              ],
              const SizedBox(height: AppSpace.md),
              TextFormField(
                key: const ValueKey<String>('finance_reconcile_note'),
                controller: _note,
                enabled: !submitting,
                maxLength: FinanceReconcileDialog.maxNoteLength,
                maxLengthEnforcement: MaxLengthEnforcement.none,
                buildCounter: (context, {required currentLength, required isFocused, maxLength}) =>
                    characterCounter(context, trimmedCodePoints(_note.text), FinanceReconcileDialog.maxNoteLength),
                textCapitalization: TextCapitalization.sentences,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Banka / kasa kontrolü notu (isteğe bağlı)',
                  prefixIcon: Icon(Icons.notes_rounded),
                ),
                validator: (value) => trimmedCodePoints(value ?? '') > FinanceReconcileDialog.maxNoteLength
                    ? 'Not en çok ${FinanceReconcileDialog.maxNoteLength} karakter olabilir.'
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fark kutusu: "Tutuyor" ya da işaretli fark (ekstre - sistem). Renk tek başına anlam taşımaz (simge + metin).
class _DifferenceBox extends StatelessWidget {
  const _DifferenceBox({required this.difference});

  final int difference;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final zero = difference == 0;
    final text = zero
        ? 'Fark yok: bakiye ekstreyle tutuyor.'
        : 'Fark: ${formatSignedMinor(difference)} (${difference > 0 ? 'ekstre sistemden fazla' : 'ekstre sistemden az'})';
    return DialogPanel(
      key: const ValueKey<String>('finance_reconcile_difference'),
      tone: zero ? AppTone.success : AppTone.warning,
      child: Semantics(
        container: true,
        liveRegion: true,
        label: spokenMoneyText(text),
        child: ExcludeSemantics(
          child: Row(
            children: [
              Icon(
                zero ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
                color: (zero ? AppTone.success : AppTone.warning).ink(context.palette),
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(child: Text(text, style: th.titleSmall)),
            ],
          ),
        ),
      ),
    );
  }
}
