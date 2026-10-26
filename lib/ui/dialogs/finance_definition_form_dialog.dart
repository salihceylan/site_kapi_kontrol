import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MaxLengthEnforcement;
import 'package:site_kapi_kontrol/models/finance.dart';
import 'package:site_kapi_kontrol/models/finance_funds.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/large_dialog_parts.dart';
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_errors.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_write_mixin.dart' show FinanceDiscardGuard;
import 'package:site_kapi_kontrol/ui/helpers/form_validation.dart';
import 'package:site_kapi_kontrol/ui/helpers/istanbul_time.dart';
import 'package:site_kapi_kontrol/ui/helpers/money.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/helpers/retry_lock.dart';
import 'package:site_kapi_kontrol/ui/helpers/text_length.dart';
import 'package:site_kapi_kontrol/ui/widgets/crm_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/fee_spec_form.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_4b_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_fund_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_parts.dart';

/// Tanım penceresi kapanırken döner.
class FinanceDefinitionOutcome {
  const FinanceDefinitionOutcome({required this.definition, required this.message});

  final FeeDefinition definition;
  final String message;
}

/// "Yeni Tanım" ve "Düzenle" penceresi (Platform Faz 4a).
///
/// - Alanlar: ad (en çok 80 karakter), tür (Aylık aidat / Tek seferlik), aylık vade günü (1-28), başlangıç ve
///   isteğe bağlı bitiş dönemi, dağıtım yöntemi + tutar / kategori haritası + hedef ([FeeSpecForm]).
/// - Düzenleme: tür ve başlangıç dönemi değişmez. HİÇ borçlandırılmamış tanımda dağıtım / tutar / hedef de
///   düzenlenir; borçlandırılmış tanımda yalnız ad, vade günü ve bitiş dönemi (geçmiş kayıtlar zaten değişmez)
///   ve kilitli alanlar açıklanır. Yalnız DEĞİŞEN alanlar gönderilir; değişiklik yoksa sunucuya gidilmez.
/// - İki kasa: "Kim öder" yerine "Kasa" seçilir — İşletme Projesi (Aidat) Hesabı (dairede oturan öder, kiracı varsa kiracı)
///   ya da Yatırım ve Demirbaş (Fon) Hesabı (malik öder). Varsayılan aylık aidatta Aidat Hesabı, tek seferlikte Fon Hesabı'dır
///   (kullanıcı dokunana kadar türe uyar). Gövdede yalnız `fund` gider (sunucu "kim öder"i ondan türetir). Borçlandırılmış
///   tanımda da değişebilir; yalnız SONRAKİ borçlandırmaları etkiler.
/// - Çift gönderim koruması (`_submitting`), gönderim sürerken geri tuşu kapatmaz; sunucu reddi pencerede
///   gösterilir ve pencere AÇIK kalır. Sonuç belirsizse (ağ / 5xx) kapanırken çağıran listeyi tazeler.
class FinanceDefinitionFormDialog extends StatefulWidget {
  const FinanceDefinitionFormDialog({
    super.key,
    required this.scope,
    this.definition,
    this.now,
    this.onRefreshNeeded,
  });

  final PeopleScope scope;

  /// Düzenlenen tanım; null ise yeni tanım.
  final FeeDefinition? definition;
  final DateTime Function()? now;
  final VoidCallback? onRefreshNeeded;

  static const int maxNameLength = 80;

  static Future<FinanceDefinitionOutcome?> show(
    BuildContext context, {
    required PeopleScope scope,
    FeeDefinition? definition,
    DateTime Function()? now,
    VoidCallback? onRefreshNeeded,
  }) {
    return showDialog<FinanceDefinitionOutcome>(
      context: context,
      barrierDismissible: false,
      builder: (_) => FinanceDefinitionFormDialog(
        scope: scope,
        definition: definition,
        now: now,
        onRefreshNeeded: onRefreshNeeded,
      ),
    );
  }

  @override
  State<FinanceDefinitionFormDialog> createState() => _FinanceDefinitionFormDialogState();
}

class _FinanceDefinitionFormDialogState extends State<FinanceDefinitionFormDialog> with FinanceDiscardGuard {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final GlobalKey<FeeSpecFormState> _specKey = GlobalKey<FeeSpecFormState>();
  late final TextEditingController _name = TextEditingController(
    text: widget.definition?.name ?? '',
  );
  final RetryLock _retry = RetryLock();

  late FeeKind _kind = widget.definition?.kind ?? FeeKind.recurring;
  late int? _dueDay = widget.definition?.dueDay ?? (widget.definition == null ? 1 : null);
  late FinancePeriod _start = widget.definition?.startPeriod ?? _current;
  late bool _hasEnd = widget.definition?.endPeriod != null;
  late FinancePeriod _end = widget.definition?.endPeriod ?? _start.addMonths(11);

  // Kasa (eski "Kim öder"). Yeni tanımda kullanıcı seçmediyse tür değişince türün varsayılanına geçer.
  late FinanceFund _fund = widget.definition?.effectiveFund ?? ChargeParty.defaultFor(_kind).fund;
  bool _fundTouched = false;

  bool _submitting = false;
  bool _needsRefreshOnClose = false;
  String? _error;

  bool get _editing => widget.definition != null;

  @override
  bool get closeLocked => _submitting;

  /// Hiç borçlandırılmamış (ya da yeni) tanımda dağıtım / tutar / hedef düzenlenir.
  bool get _specEditable => !_editing || widget.definition!.neverPosted;

  FinancePeriod get _current => FinancePeriod.of(istanbulNow(widget.now?.call()));

  @override
  void dispose() {
    _retry.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || _retry.locked) return;
    // Alan hataları ve ek kurallar (kategori listesi, hedef) tek doğrulama + tek görünür kılma zinciriyle çalışır.
    final allOk = validateForm(
      _formKey,
      validateExtra: _specEditable ? () => _specKey.currentState?.validateExtras() ?? true : null,
      revealExtra: _specEditable ? () => _specKey.currentState?.revealFirstError() ?? false : null,
    );
    FeeSpec? spec;
    if (_specEditable) spec = _specKey.currentState?.read();
    if (!allOk || (_specEditable && spec == null)) {
      setState(() => _error = kFixFieldsMessage);
      return;
    }
    if (_hasEnd && _end < _start) {
      setState(() => _error = 'Bitiş dönemi başlangıçtan önce olamaz.');
      return;
    }
    final auth = widget.scope.authService;
    final siteCode = widget.scope.siteCode;
    final name = _name.text.trim();

    Map<String, Object?>? fields;
    FeeDefinitionInput? input;
    final initial = widget.definition;
    if (initial == null) {
      final s = spec!;
      input = FeeDefinitionInput(
        name: name,
        kind: _kind,
        distribution: s.distribution,
        areaBasis: s.areaBasis,
        amountMinor: s.amountMinor,
        categoryAmounts: s.categoryAmounts,
        dueDay: _kind == FeeKind.recurring ? _dueDay : null,
        // Tek seferlik tanımın dönemi yoktur (ay seçimi etkisizdi): kayıt ayı başlangıç sayılır.
        startPeriod: _kind == FeeKind.recurring ? _start : _current,
        endPeriod: _kind == FeeKind.recurring && _hasEnd ? _end : null,
        target: s.target,
        // Seçilen kasa AÇIKÇA gönderilir (sunucu "kim öder"i ondan türetir).
        fund: _fund,
      );
    } else {
      fields = _changedFields(initial, name, spec);
      if (fields.isEmpty) {
        popIfCurrent<FinanceDefinitionOutcome>(context);
        return;
      }
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final FeeDefinition result;
      if (input != null) {
        result = await auth.createFeeDefinition(siteCode, input);
      } else {
        result = await auth.updateFeeDefinition(siteCode, initial!.id, fields!);
      }
      if (!mounted) return;
      _needsRefreshOnClose = false;
      popIfCurrent(
        context,
        FinanceDefinitionOutcome(
          definition: result,
          message: initial == null ? 'Tanım eklendi.' : 'Tanım güncellendi.',
        ),
      );
    } catch (e) {
      if (financeOutcomeUncertain(e)) _needsRefreshOnClose = true;
      if (!mounted) return;
      final limited = _retry.lockIfRateLimited(e, () {
        if (mounted) setState(() {});
      });
      setState(() {
        _submitting = false;
        _error = limited
            ? RetryLock.messageFor(e)
            : financeWriteMessage(
                e,
                'Tanım kaydedilemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
                // Tanım eklemede işlem anahtarı yok: "çift kayıt oluşmaz" DENMEZ. Düzenleme (PATCH) tekrarında
                // zarar yoktur; ipucu yine de listeyi kontrol ettirir.
                hint: kFinanceUncertainDefinitionHint,
              );
      });
    }
  }

  /// Düzenlemede yalnız değişen alanlar. Borçlandırılmış tanımda dağıtım alanları HİÇ gönderilmez.
  Map<String, Object?> _changedFields(FeeDefinition initial, String name, FeeSpec? spec) {
    final fields = <String, Object?>{};
    if (name != initial.name.trim()) fields['name'] = name;
    // Kasa borçlandırılmış tanımda da değişir (yalnız sonraki borçlandırmalar).
    if (_fund != initial.effectiveFund) fields['fund'] = _fund.apiValue;
    if (initial.isRecurring) {
      if (_dueDay != null && _dueDay != initial.dueDay) fields['due_day'] = _dueDay;
      final end = _hasEnd ? _end : null;
      if (end != initial.endPeriod) fields['end_period'] = end?.toApi();
    }
    if (spec != null && initial.neverPosted && _specChanged(initial, spec)) {
      fields['distribution'] = spec.distribution.apiValue;
      
      if (spec.distribution.needsAmount) {
        fields['amount_minor'] = spec.amountMinor;
      }
      if (spec.distribution == FeeDistribution.category) {
        fields['category_amounts'] = spec.categoryAmounts;
      }
      fields['target'] = spec.target.toJson();
    }
    return fields;
  }

  static bool _specChanged(FeeDefinition initial, FeeSpec spec) {
    if (spec.distribution != initial.distribution) return true;
    if (spec.distribution.needsAmount && spec.amountMinor != initial.amountMinor) return true;
    if (spec.distribution == FeeDistribution.category &&
        !mapEquals(spec.categoryAmounts, initial.categoryAmounts)) {
      return true;
    }
    return spec.target != initial.target;
  }

  void _notifyRefreshOnClose() {
    if (!_needsRefreshOnClose) return;
    _needsRefreshOnClose = false;
    widget.onRefreshNeeded?.call();
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final initial = widget.definition;
    final recurring = _kind == FeeKind.recurring;
    return PopScope(
      canPop: canPopNow,
      onPopInvokedWithResult: (didPop, _) {
        handleBlockedPop(didPop);
        if (didPop) _notifyRefreshOnClose();
      },
      child: AppDialog(
        title: _editing ? 'Tanımı Düzenle' : 'Yeni Tanım',
        subtitle: widget.scope.siteName.isEmpty ? null : widget.scope.siteName,
        icon: _editing ? Icons.edit_rounded : Icons.post_add_rounded,
        actions: [
          TextButton(
            onPressed: _submitting ? null : requestClose,
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            key: const ValueKey<String>('finance_definition_submit'),
            onPressed: (_submitting || _retry.locked) ? null : _submit,
            child: Text(_submitting ? 'Kaydediliyor...' : 'Kaydet'),
          ),
        ],
        child: Form(
          key: _formKey,
          onChanged: markDirty,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) FinanceSubmitError(message: _error!),
              TextFormField(
                key: const ValueKey<String>('finance_definition_name'),
                controller: _name,
                enabled: !_submitting,
                textCapitalization: TextCapitalization.sentences,
                maxLength: FinanceDefinitionFormDialog.maxNameLength,
                maxLengthEnforcement: MaxLengthEnforcement.none,
                buildCounter: (context, {required currentLength, required isFocused, maxLength}) =>
                    characterCounter(
                      context,
                      _name.text.trim().runes.length,
                      FinanceDefinitionFormDialog.maxNameLength,
                    ),
                autovalidateMode: AutovalidateMode.onUserInteraction,
                decoration: const InputDecoration(
                  labelText: 'Tanım adı',
                  hintText: 'Örn. Aylık aidat',
                  prefixIcon: Icon(Icons.title_rounded),
                ),
                validator: (value) {
                  final length = trimmedCodePoints(value ?? '');
                  if (length < 1) return 'Tanım adını girin.';
                  if (length > FinanceDefinitionFormDialog.maxNameLength) {
                    return 'Ad en çok ${FinanceDefinitionFormDialog.maxNameLength} karakter olabilir.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: AppSpace.lg),
              const FinanceGroupTitle('Tür'),
              const SizedBox(height: AppSpace.sm),
              if (_editing)
                Wrap(
                  spacing: AppSpace.sm,
                  runSpacing: AppSpace.xs,
                  children: [
                    DialogMetaPill(_kind.label, tone: AppTone.info, icon: Icons.lock_outline_rounded),
                    if (initial?.startPeriod != null)
                      DialogMetaPill(
                        'Başlangıç: ${initial!.startPeriod!.label}',
                        icon: Icons.calendar_month_rounded,
                      ),
                  ],
                )
              else
                Wrap(
                  spacing: AppSpace.sm,
                  runSpacing: AppSpace.sm,
                  children: [
                    for (final kind in const [FeeKind.recurring, FeeKind.oneTime])
                      ChoiceChip(
                        key: ValueKey<String>('finance_kind_${kind.apiValue}'),
                        label: Text(kind.label),
                        selected: _kind == kind,
                        onSelected: _submitting
                            ? null
                            : (_) => setState(() {
                                markDirty();
                                _kind = kind;
                                if (!_fundTouched) _fund = ChargeParty.defaultFor(kind).fund;
                              }),
                      ),
                  ],
                ),
              if (_editing) ...[
                const SizedBox(height: AppSpace.xs),
                Text(
                  'Tür ve başlangıç dönemi sonradan değiştirilemez.',
                  style: th.bodySmall?.copyWith(color: p.textSecondary),
                ),
              ],
              if (recurring) ...[
                const SizedBox(height: AppSpace.md),
                DropdownButtonFormField<int>(
                  key: ValueKey<String>('finance_due_day_${_dueDay ?? 0}'),
                  isExpanded: true,
                  initialValue: _dueDay,
                  dropdownColor: p.surface,
                  style: th.bodyMedium?.copyWith(color: p.text),
                  decoration: const InputDecoration(
                    labelText: 'Aylık vade günü',
                    prefixIcon: Icon(Icons.event_rounded),
                  ),
                  items: [
                    for (var day = 1; day <= 28; day++)
                      DropdownMenuItem<int>(value: day, child: Text("Her ayın $day'i")),
                  ],
                  onChanged: _submitting
                      ? null
                      : (value) => setState(() {
                          markDirty();
                          _dueDay = value;
                        }),
                  validator: (value) => value == null ? 'Vade gününü seçin.' : null,
                ),
              ],
              if (!_editing && !recurring) ...[
                const SizedBox(height: AppSpace.xs),
                Text(
                  'Tek seferlik tanımın dönemi ve vade günü yoktur; vade tarihi borçlandırırken seçilir.',
                  key: const ValueKey<String>('finance_one_time_note'),
                  style: th.bodySmall?.copyWith(color: p.textSecondary),
                ),
              ],
              if (!_editing && recurring) ...[
                const SizedBox(height: AppSpace.md),
                _stepper(
                  context,
                  title: 'Başlangıç dönemi',
                  value: _start,
                  keyPrefix: 'finance_start',
                  onChanged: (value) => setState(() {
                    markDirty();
                    _start = value;
                    if (_end < _start) _end = _start;
                  }),
                ),
              ],
              if (recurring) ...[
                const SizedBox(height: AppSpace.sm),
                SwitchListTile(
                  key: const ValueKey<String>('finance_has_end'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Bitiş dönemi belirle'),
                  subtitle: const Text('Kapalıysa tanım süresizdir.'),
                  value: _hasEnd,
                  onChanged: _submitting
                      ? null
                      : (value) => setState(() {
                          markDirty();
                          _hasEnd = value;
                        }),
                ),
                if (_hasEnd)
                  _stepper(
                    context,
                    title: 'Bitiş dönemi',
                    value: _end,
                    keyPrefix: 'finance_end',
                    min: _start,
                    onChanged: (value) => setState(() {
                      markDirty();
                      _end = value;
                    }),
                  ),
              ],
              const SizedBox(height: AppSpace.lg),
              FundChoice(
                key: const ValueKey<String>('finance_definition_fund'),
                selected: _fund,
                enabled: !_submitting,
                keyPrefix: 'finance_def_fund',
                onSelected: (value) => setState(() {
                  if (value == null) return;
                  markDirty();
                  _fund = value;
                  _fundTouched = true;
                }),
              ),
              if (_editing && !_specEditable) ...[
                const SizedBox(height: AppSpace.xs),
                Text(
                  'Kasa değişikliği yalnız bundan sonraki borçlandırmalara uygulanır; yazılmış borçlar değişmez.',
                  key: const ValueKey<String>('finance_definition_fund_note'),
                  style: th.bodySmall?.copyWith(color: p.textSecondary),
                ),
              ],
              const SizedBox(height: AppSpace.lg),
              if (_specEditable)
                FeeSpecForm(
                  key: _specKey,
                  scope: widget.scope,
                  initialDistribution: initial?.distribution ?? FeeDistribution.fixed,
                  initialAreaBasis: initial?.areaBasis ?? AreaBasis.gross,
                  initialAmountMinor: initial?.amountMinor,
                  initialCategoryAmounts: initial?.categoryAmounts ?? const <String, int>{},
                  initialTarget: initial?.target ?? const FeeTarget(),
                  enabled: !_submitting,
                  onChanged: markDirty,
                  keyPrefix: 'def_spec',
                )
              else
                _lockedPanel(context, initial!),
            ],
          ),
        ),
      ),
    );
  }

  /// Borçlandırılmış tanımda kilitli dağıtım alanları: değerleri ve nedeni açıklanır.
  Widget _lockedPanel(BuildContext context, FeeDefinition d) {
    final th = Theme.of(context).textTheme;
    return DialogPanel(
      key: const ValueKey<String>('finance_definition_locked'),
      tone: AppTone.info,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const DialogSectionTitle(
            icon: Icons.lock_outline_rounded,
            title: 'Kilitli alanlar',
            tone: AppTone.info,
          ),
          const SizedBox(height: AppSpace.sm),
          Text(
            'Bu tanım borçlandırıldığı için dağıtım yöntemi, tutar ve hedef değiştirilemez; geçmiş kayıtlar '
            'zaten değişmez. Yalnızca ad, vade günü, bitiş dönemi ve kasa düzenlenir. Farklı bir tutar için '
            'yeni bir tanım ekleyip bunu pasifleştirin.',
            style: th.bodyMedium,
          ),
          const SizedBox(height: AppSpace.md),
          CrmInfoLine(label: 'Dağıtım', value: d.distribution.label),
          const SizedBox(height: AppSpace.sm),
          Builder(
            builder: (context) {
              final amount = definitionAmountText(d);
              final p = context.palette;
              // Tutar ekran okuyucuya "bin iki yüz elli lira" diye okunur.
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Tutar', style: th.bodySmall?.copyWith(color: p.textSecondary)),
                  Text(amount, semanticsLabel: spokenMoneyText(amount), style: th.bodyMedium),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpace.sm),
          CrmInfoLine(label: 'Hedef', value: d.target.summary),
        ],
      ),
    );
  }

  Widget _stepper(
    BuildContext context, {
    required String title,
    required FinancePeriod value,
    required String keyPrefix,
    required ValueChanged<FinancePeriod> onChanged,
    FinancePeriod? min,
  }) {
    final th = Theme.of(context).textTheme;
    return DialogPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DialogSectionTitle(icon: Icons.calendar_month_rounded, title: title),
          const SizedBox(height: AppSpace.sm),
          Row(
            children: [
              IconButton(
                key: ValueKey<String>('${keyPrefix}_prev'),
                tooltip: 'Önceki ay',
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                onPressed: (_submitting || (min != null && value <= min))
                    ? null
                    : () => onChanged(value.previous),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    value.label,
                    key: ValueKey<String>('${keyPrefix}_label'),
                    textAlign: TextAlign.center,
                    style: th.titleMedium,
                  ),
                ),
              ),
              IconButton(
                key: ValueKey<String>('${keyPrefix}_next'),
                tooltip: 'Sonraki ay',
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                onPressed: _submitting ? null : () => onChanged(value.next),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
