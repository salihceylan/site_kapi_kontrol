import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MaxLengthEnforcement;
import 'package:site_kapi_kontrol/models/finance.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/large_dialog_parts.dart';
import 'package:site_kapi_kontrol/ui/helpers/a11y_announce.dart';
import 'package:site_kapi_kontrol/ui/helpers/focus_helpers.dart';
import 'package:site_kapi_kontrol/ui/helpers/money.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/helpers/text_length.dart';
import 'package:site_kapi_kontrol/ui/widgets/crm_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_target_picker.dart';
import 'package:site_kapi_kontrol/ui/widgets/money_field.dart';

/// Formdan okunan dağıtım belirtimi: yöntem, m² türü, tutar (kuruş), kategori haritası (kuruş) ve hedef.
@immutable
class FeeSpec {
  const FeeSpec({
    required this.distribution,
    this.areaBasis,
    this.amountMinor,
    this.categoryAmounts = const <String, int>{},
    required this.target,
  });

  final FeeDistribution distribution;
  final AreaBasis? areaBasis;
  final int? amountMinor;
  final Map<String, int> categoryAmounts;
  final FeeTarget target;
}

class _CategoryRow {
  _CategoryRow({String name = '', String amount = ''})
    : name = TextEditingController(text: name),
      amount = TextEditingController(text: amount);

  final TextEditingController name;
  final TextEditingController amount;
  final FocusNode nameFocus = FocusNode();
  final Key key = UniqueKey();

  void dispose() {
    name.dispose();
    amount.dispose();
    nameFocus.dispose();
  }
}

/// Aidat / ek borç dağıtım alanları (Platform Faz 4a): dağıtım yöntemi seçici (eşit / sabit / kategori /
/// arsa payı / m²), m² türü, tutar, kategori haritası düzenleyicisi ve hedef seçici.
///
/// - Tutar alanının adı yönteme uyar: sabit "Daire başı tutar", diğerleri "Toplam tutar"; kategori yönteminde
///   tutar yerine kategori haritası (kategori adı + daire başı tutar) düzenlenir.
/// - Alanlar üst formun [Form]'una katılır (üst `validateForm` çalıştırır); kategori ve hedef kuralları
///   [validateExtras] ile ayrıca doğrulanır ve hata alanın altında görünür. [read] güvenli [FeeSpec] döner.
/// - Tutarlar KURUŞ tamsayıdır ([parseMoney]); kayan nokta yoktur.
class FeeSpecForm extends StatefulWidget {
  const FeeSpecForm({
    super.key,
    required this.scope,
    this.initialDistribution = FeeDistribution.fixed,
    this.initialAreaBasis = AreaBasis.gross,
    this.initialAmountMinor,
    this.initialCategoryAmounts = const <String, int>{},
    this.initialTarget = const FeeTarget(),
    this.enabled = true,
    this.onChanged,
    this.keyPrefix = 'fee_spec',
  });

  final PeopleScope scope;
  final FeeDistribution initialDistribution;
  final AreaBasis initialAreaBasis;
  final int? initialAmountMinor;
  final Map<String, int> initialCategoryAmounts;
  final FeeTarget initialTarget;
  final bool enabled;

  /// Alanlar değişince çağrılır (örn. önizlemeyi geçersiz kılmak için).
  final VoidCallback? onChanged;
  final String keyPrefix;

  /// Seçilebilir yöntemler (sıra ekrandaki sıradır).
  static const List<FeeDistribution> distributions = <FeeDistribution>[
    FeeDistribution.fixed,
    FeeDistribution.equal,
    FeeDistribution.category,
    FeeDistribution.landShare,
    FeeDistribution.area,
  ];

  static const int maxCategories = 30;
  static const int maxCategoryNameLength = 40;

  @override
  State<FeeSpecForm> createState() => FeeSpecFormState();
}

class FeeSpecFormState extends State<FeeSpecForm> {
  late FeeDistribution _distribution = widget.initialDistribution == FeeDistribution.unknown
      ? FeeDistribution.fixed
      : widget.initialDistribution;
  late AreaBasis _areaBasis = widget.initialAreaBasis;
  late final TextEditingController _amount = TextEditingController(
    text: widget.initialAmountMinor == null
        ? ''
        : formatMinor(widget.initialAmountMinor!, symbol: false),
  );
  final GlobalKey<FinanceTargetPickerState> _targetKey = GlobalKey<FinanceTargetPickerState>();
  late final List<_CategoryRow> _rows = <_CategoryRow>[
    for (final entry in widget.initialCategoryAmounts.entries)
      _CategoryRow(name: entry.key, amount: formatMinor(entry.value, symbol: false)),
  ];
  String? _categoryError;
  final GlobalKey _categoryErrorKey = GlobalKey();

  // "Kategori Ekle" düğmesini saran odak düğümü: son satır silinince odak bu düğmeye taşınır.
  final FocusNode _addFocus = FocusNode(skipTraversal: true, canRequestFocus: false);

  @override
  void initState() {
    super.initState();
    if (_distribution == FeeDistribution.category && _rows.isEmpty) _rows.add(_CategoryRow());
  }

  @override
  void dispose() {
    _amount.dispose();
    _addFocus.dispose();
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  void _changed() => widget.onChanged?.call();

  /// Kategori ve hedef kurallarını doğrular (alan düzeyi doğrulayıcıları üst `validateForm` çalıştırır).
  /// Hatalar alanın altında gösterilir. Geçerliyse true.
  bool validateExtras() {
    var ok = true;
    if (_distribution == FeeDistribution.category) {
      final problem = _categoryProblem();
      if (problem != _categoryError) setState(() => _categoryError = problem);
      if (problem != null) ok = false;
    }
    final targetOk = _targetKey.currentState?.validate() ?? true;
    return ok && targetOk;
  }

  /// Alan düzeyi hata yokken İLK ek hatayı (kategori listesi, sonra hedef) görünür kılar; gösterdiyse true.
  /// Hata bildirimleri kendilerini kaydırmaz: görünür kılma yalnız bu yolla (üst `validateForm` zinciri) olur.
  bool revealFirstError() {
    final categoryContext = _categoryError == null ? null : _categoryErrorKey.currentContext;
    if (categoryContext != null) {
      Scrollable.ensureVisible(categoryContext, alignment: 0.15, duration: Duration.zero);
      return true;
    }
    return _targetKey.currentState?.revealError() ?? false;
  }

  String? _categoryProblem() {
    if (_rows.isEmpty) return 'En az bir kategori ekleyin.';
    final seen = <String>{};
    for (final row in _rows) {
      final name = row.name.text.trim();
      if (name.isEmpty) continue; // alan düzeyi doğrulayıcı bildirir
      if (!seen.add(name.toLowerCase())) return 'Aynı kategori adı iki kez girilmiş.';
    }
    return null;
  }

  /// Formdaki geçerli belirtimi okur; geçersizse null (önce [validateExtras] ve üst `validateForm`).
  FeeSpec? read() {
    final target = _targetKey.currentState?.target ?? widget.initialTarget;
    int? amount;
    var categories = const <String, int>{};
    if (_distribution.needsAmount) {
      amount = parseMoney(_amount.text).minor;
      if (amount == null) return null;
    }
    if (_distribution == FeeDistribution.category) {
      final map = <String, int>{};
      for (final row in _rows) {
        final name = row.name.text.trim();
        final minor = parseMoney(row.amount.text).minor;
        if (name.isEmpty || minor == null) return null;
        map[name] = minor;
      }
      if (map.isEmpty || map.length != _rows.length) return null;
      categories = map;
    }
    return FeeSpec(
      distribution: _distribution,
      areaBasis: _distribution == FeeDistribution.area ? _areaBasis : null,
      amountMinor: amount,
      categoryAmounts: categories,
      target: target,
    );
  }

  void _selectDistribution(FeeDistribution value) {
    if (value == _distribution) return;
    setState(() {
      _distribution = value;
      _categoryError = null;
      if (value == FeeDistribution.category && _rows.isEmpty) _rows.add(_CategoryRow());
    });
    _changed();
  }

  void _addRow() {
    if (_rows.length >= FeeSpecForm.maxCategories) {
      setState(() => _categoryError = 'En çok ${FeeSpecForm.maxCategories} kategori eklenebilir.');
      return;
    }
    final row = _CategoryRow();
    setState(() {
      _categoryError = null;
      _rows.add(row);
    });
    _changed();
    // Odak yeni satırın ad alanına taşınır (klavye / ekran okuyucu kullanıcısı yeni satıra iner).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _rows.contains(row)) row.nameFocus.requestFocus();
    });
    announcePolite(context, 'Kategori satırı eklendi. Toplam ${_rows.length} satır.');
  }

  void _removeRow(_CategoryRow row) {
    final index = _rows.indexOf(row);
    setState(() {
      _rows.remove(row);
      _categoryError = null;
    });
    // Denetleyiciler bu çerçeve bittikten sonra atılır (alan hâlâ ağaçtadır).
    WidgetsBinding.instance.addPostFrameCallback((_) => row.dispose());
    _changed();
    // Silinen düğmenin odağı kaybolmasın: bir sonraki (yoksa önceki) satırın adına, hiç satır kalmadıysa
    // "Kategori Ekle" düğmesine taşınır.
    final next = _rows.isEmpty ? null : _rows[index.clamp(0, _rows.length - 1)];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (next != null && _rows.contains(next)) {
        next.nameFocus.requestFocus();
      } else {
        focusFirstWithin(_addFocus);
      }
    });
    announcePolite(context, 'Kategori satırı kaldırıldı. Kalan ${_rows.length} satır.');
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final prefix = widget.keyPrefix;
    final enabled = widget.enabled;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const FinanceGroupTitle('Dağıtım yöntemi'),
        const SizedBox(height: AppSpace.sm),
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          children: [
            for (final value in FeeSpecForm.distributions)
              ChoiceChip(
                key: ValueKey<String>('${prefix}_dist_${value.apiValue}'),
                label: Text(value.label),
                selected: _distribution == value,
                onSelected: enabled ? (_) => _selectDistribution(value) : null,
              ),
          ],
        ),
        const SizedBox(height: AppSpace.sm),
        Text(
          _distribution.description,
          key: ValueKey<String>('${prefix}_dist_help'),
          style: th.bodySmall?.copyWith(color: p.textSecondary),
        ),
        if (_distribution == FeeDistribution.area) ...[
          const SizedBox(height: AppSpace.md),
          const FinanceGroupTitle('Metrekare türü'),
          const SizedBox(height: AppSpace.sm),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: [
              for (final basis in AreaBasis.values)
                ChoiceChip(
                  key: ValueKey<String>('${prefix}_area_${basis.apiValue}'),
                  label: Text(basis.label),
                  selected: _areaBasis == basis,
                  onSelected: enabled
                      ? (_) {
                          setState(() => _areaBasis = basis);
                          _changed();
                        }
                      : null,
                ),
            ],
          ),
        ],
        if (_distribution.needsAmount) ...[
          const SizedBox(height: AppSpace.md),
          MoneyFormField(
            key: ValueKey<String>('${prefix}_amount_group'),
            fieldKey: ValueKey<String>('${prefix}_amount'),
            controller: _amount,
            enabled: enabled,
            label: _distribution.amountIsPerApartment ? 'Daire başı tutar' : 'Toplam tutar',
            onChanged: (_) => _changed(),
          ),
        ],
        if (_distribution == FeeDistribution.category) ...[
          const SizedBox(height: AppSpace.md),
          const FinanceGroupTitle('Kategori tutarları'),
          const SizedBox(height: AppSpace.xs),
          Text(
            'Kategori adı, dairelerin Kişiler > Daireler ekranındaki kategorisiyle aynı yazılmalıdır. '
            'Her kategori için daire başı tutarı girin.',
            style: th.bodySmall?.copyWith(color: p.textSecondary),
          ),
          const SizedBox(height: AppSpace.sm),
          for (var i = 0; i < _rows.length; i++) ...[
            _buildRow(context, i, _rows[i]),
            const SizedBox(height: AppSpace.sm),
          ],
          if (_categoryError != null)
            KeyedSubtree(
              key: _categoryErrorKey,
              child: CrmFormError(
                key: ValueKey<String>('${prefix}_category_error'),
                message: _categoryError!,
                // Görünür kılma işini üst form doğrulaması yapar ([revealFirstError]); iki kaydırma yarışmasın.
                reveal: false,
              ),
            ),
          Focus(
            focusNode: _addFocus,
            child: PrimaryActionButton(
              key: ValueKey<String>('${prefix}_add_category'),
              label: 'Kategori Ekle',
              icon: Icons.add_rounded,
              variant: AppButtonVariant.outline,
              onPressed: enabled ? _addRow : null,
            ),
          ),
        ],
        const SizedBox(height: AppSpace.lg),
        FinanceTargetPicker(
          key: _targetKey,
          scope: widget.scope,
          initial: widget.initialTarget,
          enabled: enabled,
          onChanged: _changed,
        ),
      ],
    );
  }

  Widget _buildRow(BuildContext context, int index, _CategoryRow row) {
    final prefix = widget.keyPrefix;
    final enabled = widget.enabled;
    return DialogPanel(
      key: row.key,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            key: ValueKey<String>('${prefix}_category_name_$index'),
            controller: row.name,
            focusNode: row.nameFocus,
            enabled: enabled,
            textInputAction: TextInputAction.next,
            maxLength: FeeSpecForm.maxCategoryNameLength,
            maxLengthEnforcement: MaxLengthEnforcement.none,
            buildCounter: (context, {required currentLength, required isFocused, maxLength}) =>
                characterCounter(context, row.name.text.runes.length, FeeSpecForm.maxCategoryNameLength),
            autovalidateMode: AutovalidateMode.onUserInteraction,
            onChanged: (_) => _changed(),
            decoration: InputDecoration(
              labelText: 'Kategori adı ${index + 1}',
              hintText: 'Örn. 3+1',
              prefixIcon: const Icon(Icons.category_rounded),
            ),
            validator: (value) {
              final length = trimmedCodePoints(value ?? '');
              if (length < 1) return 'Kategori adını girin.';
              if (length > FeeSpecForm.maxCategoryNameLength) {
                return 'Kategori adı en çok ${FeeSpecForm.maxCategoryNameLength} karakter olabilir.';
              }
              return null;
            },
          ),
          const SizedBox(height: AppSpace.sm),
          MoneyFormField(
            key: ValueKey<String>('${prefix}_category_amount_group_$index'),
            fieldKey: ValueKey<String>('${prefix}_category_amount_$index'),
            controller: row.amount,
            enabled: enabled,
            label: 'Daire başı tutar',
            onChanged: (_) => _changed(),
          ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton.icon(
              key: ValueKey<String>('${prefix}_category_remove_$index'),
              onPressed: enabled ? () => _removeRow(row) : null,
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              label: const Text('Kategoriyi kaldır'),
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 48),
                foregroundColor: AppTone.danger.ink(context.palette),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
