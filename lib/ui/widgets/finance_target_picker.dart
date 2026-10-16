import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/apartment_crm.dart' show ApartmentSummary;
import 'package:site_kapi_kontrol/models/finance.dart';
import 'package:site_kapi_kontrol/models/site_block_record.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/crm_pickers.dart';
import 'package:site_kapi_kontrol/ui/helpers/a11y_announce.dart';
import 'package:site_kapi_kontrol/ui/helpers/focus_helpers.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/widgets/crm_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_parts.dart';

/// Hedefte seçilmiş bir blok ya da daire (etiketiyle).
typedef _Picked = ({int id, String label});

/// Aidat / ek borç hedefi seçici (Tüm site | Bloklar | Daireler). Duyuru formunun hedef seçicisiyle AYNI
/// kalıp ve aynı seçici pencereleri ([CrmPickerDialog], [showApartmentPicker]); sunucuya `target` olarak
/// [FeeTarget.toJson] gider.
///
/// - Kayıtlı bir tanımın hedefi yalnız kimliklerle gelir: bloklar site yapısından adlarıyla çözülür
///   (tek tek çıkarılabilir), çözülemeyen / daire kimlikleri "N daire" çipi olarak gösterilir ve toplu
///   "Seçimi temizle" ile yeniden seçilir.
/// - En çok [maxItems] öğe seçilebilir; seçici çift dokunuşta iki kez açılmaz.
/// - [validate] boş blok / daire seçimini reddeder ve hatayı alanın altında gösterir.
class FinanceTargetPicker extends StatefulWidget {
  const FinanceTargetPicker({
    super.key,
    required this.scope,
    this.initial = const FeeTarget(),
    this.enabled = true,
    this.onChanged,
  });

  final PeopleScope scope;
  final FeeTarget initial;
  final bool enabled;

  /// Seçim her değiştiğinde çağrılır (örn. önizlemeyi geçersiz kılmak için).
  final VoidCallback? onChanged;

  static const int maxItems = 500;

  @override
  State<FinanceTargetPicker> createState() => FinanceTargetPickerState();
}

class FinanceTargetPickerState extends State<FinanceTargetPicker> {
  late FeeTargetType _type = widget.initial.type;
  List<_Picked> _blocks = const <_Picked>[];
  List<_Picked> _apartments = const <_Picked>[];
  List<int> _keptBlockIds = const <int>[];
  List<int> _keptApartmentIds = const <int>[];
  List<SiteBlockRecord>? _blockCache;
  bool _picking = false;
  String? _error;
  final GlobalKey _errorKey = GlobalKey();

  // "Blok / Daire Ekle" düğmesini saran odak düğümü: çip çıkarılınca odak buraya taşınır.
  final FocusNode _addFocus = FocusNode(skipTraversal: true, canRequestFocus: false);

  @override
  void dispose() {
    _addFocus.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    // Sunucu etiketleri (`target.blocks` / `target.apartments`) kimlikle eşleşiyorsa kayıtlı seçim tek tek
    // çıkarılabilir çip olarak gelir; eşleşmeyen kimlikler (silinmiş blok / eski sunucu) "N blok / N daire" kalır.
    if (initial.type == FeeTargetType.blocks) {
      final known = <int>{for (final b in initial.blockItems) b.id};
      _blocks = <_Picked>[for (final b in initial.blockItems) (id: b.id, label: b.label)];
      _keptBlockIds = <int>[
        for (final id in initial.blockIds)
          if (!known.contains(id)) id,
      ];
      if (_keptBlockIds.isNotEmpty) _resolveBlockLabels();
    } else if (initial.type == FeeTargetType.apartments) {
      final known = <int>{for (final a in initial.apartmentItems) a.id};
      _apartments = <_Picked>[for (final a in initial.apartmentItems) (id: a.id, label: a.label)];
      _keptApartmentIds = <int>[
        for (final id in initial.apartmentIds)
          if (!known.contains(id)) id,
      ];
    }
  }

  List<int> get _blockIds => <int>[..._keptBlockIds, for (final b in _blocks) b.id];
  List<int> get _apartmentIds => <int>[..._keptApartmentIds, for (final a in _apartments) a.id];

  /// Seçili hedef (gönderime hazır).
  FeeTarget get target => FeeTarget(
    type: _type,
    blockIds: _type == FeeTargetType.blocks ? _blockIds : const <int>[],
    apartmentIds: _type == FeeTargetType.apartments ? _apartmentIds : const <int>[],
  );

  /// Boş blok / daire seçimini reddeder; hatayı gösterir. Geçerliyse true.
  bool validate() {
    final problem = switch (_type) {
      FeeTargetType.site => null,
      FeeTargetType.blocks => _blockIds.isEmpty ? 'En az bir blok seçin.' : null,
      FeeTargetType.apartments => _apartmentIds.isEmpty ? 'En az bir daire seçin.' : null,
    };
    if (problem != _error) setState(() => _error = problem);
    return problem == null;
  }

  /// Hedef hatası görünürse kaydırıp görünür kılar (true). Hata bildirimi kendini kaydırmaz: görünür kılma
  /// yalnız üst form doğrulama zincirinden ya da bu çağrıdan olur (iki kaydırma yarışmasın).
  bool revealError() {
    final errorContext = _error == null ? null : _errorKey.currentContext;
    if (errorContext == null) return false;
    Scrollable.ensureVisible(errorContext, alignment: 0.15, duration: Duration.zero);
    return true;
  }

  void _showError(String message) {
    setState(() => _error = message);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) revealError();
    });
  }

  Future<List<SiteBlockRecord>> _loadBlocks() async {
    final cached = _blockCache;
    if (cached != null) return cached;
    final (structure, error) = await widget.scope.authService.getSiteStructure(
      siteCode: widget.scope.siteCode,
    );
    if (structure == null) {
      throw ApiException(
        (error ?? '').trim().isEmpty
            ? 'Bloklar yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.'
            : error!,
      );
    }
    return _blockCache = structure.blocks;
  }

  /// Kayıtlı blok kimliklerini adlarıyla tek tek çıkarılabilir seçime çevirir; çözülemezse "N blok" kalır.
  Future<void> _resolveBlockLabels() async {
    try {
      final blocks = await _loadBlocks();
      if (!mounted) return;
      final names = <int, String>{for (final b in blocks) b.id: b.blockName.trim()};
      if (_keptBlockIds.any((id) => (names[id] ?? '').isEmpty)) return;
      setState(() {
        _blocks = <_Picked>[
          for (final id in _keptBlockIds) (id: id, label: names[id]!),
          ..._blocks,
        ];
        _keptBlockIds = const <int>[];
      });
    } catch (_) {
      // Etiketsiz devam: "N blok" çipi gösterilir.
    }
  }

  void _changed() => widget.onChanged?.call();

  void _selectType(FeeTargetType type) {
    if (type == _type) return;
    setState(() {
      _type = type;
      _error = null;
    });
    _changed();
  }

  Future<void> _pickBlock() async {
    if (_picking) return;
    _picking = true;
    SiteBlockRecord? picked;
    try {
      picked = await CrmPickerDialog.show<SiteBlockRecord>(
        context,
        CrmPickerDialog<SiteBlockRecord>(
          title: 'Blok Ekle',
          icon: Icons.domain_rounded,
          searchLabel: 'Blok ara',
          emptyTitle: 'Eklenecek blok bulunamadı.',
          fetch: (query, offset, limit) async {
            final blocks = await _loadBlocks();
            final q = query.trim().toLowerCase();
            final chosen = _blockIds.toSet();
            final rows = blocks
                .where(
                  (b) =>
                      !chosen.contains(b.id) &&
                      (q.isEmpty || b.blockName.toLowerCase().contains(q)),
                )
                .toList();
            return (items: rows.skip(offset).take(limit).toList(), total: rows.length);
          },
          keyOf: (b) => b.id,
          titleOf: (b) => b.blockName.trim().isEmpty ? 'Adsız blok' : b.blockName.trim(),
        ),
      );
    } finally {
      _picking = false;
    }
    final block = picked;
    if (block == null || !mounted || _blockIds.contains(block.id)) return;
    if (_blockIds.length >= FinanceTargetPicker.maxItems) {
      _showError(_tooMany);
      return;
    }
    setState(() {
      _error = null;
      _blocks = <_Picked>[
        ..._blocks,
        (id: block.id, label: block.blockName.trim().isEmpty ? 'Adsız blok' : block.blockName.trim()),
      ];
    });
    _changed();
  }

  Future<void> _pickApartment() async {
    if (_picking) return;
    _picking = true;
    ApartmentSummary? picked;
    try {
      picked = await showApartmentPicker(context, widget.scope, title: 'Daire Ekle');
    } finally {
      _picking = false;
    }
    final apartment = picked;
    if (apartment == null || !mounted || _apartmentIds.contains(apartment.id)) return;
    if (_apartmentIds.length >= FinanceTargetPicker.maxItems) {
      _showError(_tooMany);
      return;
    }
    setState(() {
      _error = null;
      _apartments = <_Picked>[..._apartments, (id: apartment.id, label: apartment.fullLabel)];
    });
    _changed();
  }

  static const String _tooMany = 'En çok 500 öğe seçilebilir. Hedefi bölüp ayrı kayıtlar oluşturun.';

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const FinanceGroupTitle('Hedef'),
        const SizedBox(height: AppSpace.sm),
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          children: [
            for (final type in FeeTargetType.values)
              ChoiceChip(
                key: ValueKey<String>('finance_target_${type.apiValue}'),
                label: Text(type.label),
                selected: _type == type,
                onSelected: widget.enabled ? (_) => _selectType(type) : null,
              ),
          ],
        ),
        if (_type == FeeTargetType.blocks)
          ..._section(
            context,
            picks: _blocks,
            keptIds: _keptBlockIds,
            noun: 'blok',
            addLabel: 'Blok Ekle',
            addKey: 'finance_add_block',
            onAdd: _pickBlock,
            onRemove: (id) {
              setState(() => _blocks = _blocks.where((b) => b.id != id).toList());
              _afterRemove('blok');
            },
            onClearKept: () {
              setState(() => _keptBlockIds = const <int>[]);
              _changed();
            },
          ),
        if (_type == FeeTargetType.apartments)
          ..._section(
            context,
            picks: _apartments,
            keptIds: _keptApartmentIds,
            noun: 'daire',
            addLabel: 'Daire Ekle',
            addKey: 'finance_add_apartment',
            onAdd: _pickApartment,
            onRemove: (id) {
              setState(() => _apartments = _apartments.where((a) => a.id != id).toList());
              _afterRemove('daire');
            },
            onClearKept: () {
              setState(() => _keptApartmentIds = const <int>[]);
              _changed();
            },
          ),
        if (_type == FeeTargetType.site) ...[
          const SizedBox(height: AppSpace.sm),
          Text(
            'Sitedeki tüm aktif dairelere uygulanır.',
            style: th.bodySmall?.copyWith(color: p.textSecondary),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: AppSpace.sm),
          KeyedSubtree(
            key: _errorKey,
            child: CrmFormError(message: _error!, reveal: false),
          ),
        ],
      ],
    );
  }

  /// Çip çıkarıldı: silinen düğmenin odağı kaybolmasın, "Ekle" düğmesine taşınır.
  void _afterRemove(String noun) {
    _changed();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) focusFirstWithin(_addFocus);
    });
    announcePolite(context, 'Seçili $noun hedeften çıkarıldı.');
  }

  List<Widget> _section(
    BuildContext context, {
    required List<_Picked> picks,
    required List<int> keptIds,
    required String noun,
    required String addLabel,
    required String addKey,
    required Future<void> Function() onAdd,
    required void Function(int id) onRemove,
    required VoidCallback onClearKept,
  }) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    return [
      const SizedBox(height: AppSpace.sm),
      if (keptIds.isNotEmpty) ...[
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.xs,
          children: [Chip(label: Text('${keptIds.length} $noun'))],
        ),
        const SizedBox(height: AppSpace.xs),
        Text(
          'Kayıtlı seçim tek tek çıkarılamaz; yeniden seçmek için "Seçimi temizle" kullanın.',
          style: th.bodySmall?.copyWith(color: p.textSecondary),
        ),
        TextButton.icon(
          key: ValueKey<String>('${addKey}_clear'),
          onPressed: widget.enabled ? onClearKept : null,
          icon: const Icon(Icons.layers_clear_rounded, size: 18),
          label: const Text('Seçimi temizle'),
          style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
        ),
      ],
      if (picks.isNotEmpty) ...[
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.xs,
          children: [
            for (final pick in picks)
              _TargetChip(
                key: ValueKey<String>('finance_pick_${pick.id}'),
                label: pick.label,
                onRemove: widget.enabled ? () => onRemove(pick.id) : null,
              ),
          ],
        ),
        const SizedBox(height: AppSpace.sm),
      ],
      Focus(
        focusNode: _addFocus,
        child: PrimaryActionButton(
          key: ValueKey<String>(addKey),
          label: addLabel,
          icon: Icons.add_rounded,
          variant: AppButtonVariant.outline,
          onPressed: widget.enabled ? onAdd : null,
        ),
      ),
    ];
  }
}

/// Hedefte seçili blok / daire çipi: ✕ düğmesi en az 48x48 dp dokunma hedefidir; uzun etiket sarar.
class _TargetChip extends StatelessWidget {
  const _TargetChip({super.key, required this.label, required this.onRemove});

  final String label;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: p.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Padding(
              padding: const EdgeInsetsDirectional.only(
                start: AppSpace.md,
                top: AppSpace.sm,
                bottom: AppSpace.sm,
              ),
              child: Text(label, style: th.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            ),
          ),
          IconButton(
            tooltip: '$label hedeften çıkar',
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            icon: const Icon(Icons.close_rounded, size: 18),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}
