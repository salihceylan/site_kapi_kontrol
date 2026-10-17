// Sakin kitlesinin hedef seçimi (Tüm site / Bloklar / Daireler) — belge yükleme ve düzenleme formları ortak
// kullanır (docs/PLATFORM_BELGELER.md A5, A7). Seçiciler `crm_pickers` üzerinden açılır (arama + sayfalı).
//
// Denetimli (controlled) bileşen: seçimi üst form tutar ([DocumentTargetSelection]); bu widget yalnız çizer ve
// değişiklikleri bildirir. Yükleme sürerken ([enabled] false) hiçbir etkileşim yoktur.
import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/apartment_crm.dart'
    show ApartmentSummary;
import 'package:site_kapi_kontrol/models/document_models.dart';
import 'package:site_kapi_kontrol/models/site_block_record.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/crm_pickers.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/widgets/crm_parts.dart';

/// Seçilmiş bir blok ya da daire (etiketiyle).
typedef DocumentPick = ({int id, String label});

/// Hedef seçimi: tür + seçilen bloklar / daireler.
@immutable
class DocumentTargetSelection {
  const DocumentTargetSelection({
    this.type = DocumentTargetType.site,
    this.blocks = const <DocumentPick>[],
    this.apartments = const <DocumentPick>[],
  });

  /// Sunucudaki hedeften kurar (düzenleme formu). Etiketi gelmeyen kimlikler "Seçili blok / daire" olur.
  factory DocumentTargetSelection.fromTarget(DocumentTarget target) {
    DocumentPick pick(int id, List<DocumentTargetItem> known, String fallback) {
      for (final item in known) {
        if (item.id == id && item.label.trim().isNotEmpty) {
          return (id: id, label: item.label.trim());
        }
      }
      return (id: id, label: fallback);
    }

    return DocumentTargetSelection(
      type: target.type,
      blocks: <DocumentPick>[
        for (final id in target.blockIds)
          pick(id, target.blocks, 'Seçili blok'),
      ],
      apartments: <DocumentPick>[
        for (final id in target.apartmentIds)
          pick(id, target.apartments, 'Seçili daire'),
      ],
    );
  }

  final DocumentTargetType type;
  final List<DocumentPick> blocks;
  final List<DocumentPick> apartments;

  /// Sunucudaki en çok öğe sayısı (blok ve daire için ayrı).
  static const int maxItems = 500;

  List<int> get blockIds => <int>[for (final b in blocks) b.id];
  List<int> get apartmentIds => <int>[for (final a in apartments) a.id];

  DocumentTargetSelection copyWith({
    DocumentTargetType? type,
    List<DocumentPick>? blocks,
    List<DocumentPick>? apartments,
  }) => DocumentTargetSelection(
    type: type ?? this.type,
    blocks: blocks ?? this.blocks,
    apartments: apartments ?? this.apartments,
  );

  /// Geçersizse Türkçe ileti (blok / daire türünde en az bir öğe); geçerliyse null.
  String? validate() {
    switch (type) {
      case DocumentTargetType.site:
        return null;
      case DocumentTargetType.blocks:
        return blocks.isEmpty ? 'En az bir blok seçin.' : null;
      case DocumentTargetType.apartments:
        return apartments.isEmpty ? 'En az bir daire seçin.' : null;
    }
  }

  DocumentTargetInput toInput() => DocumentTargetInput(
    type: type,
    blockIds: type == DocumentTargetType.blocks ? blockIds : const <int>[],
    apartmentIds: type == DocumentTargetType.apartments
        ? apartmentIds
        : const <int>[],
  );

  /// Kimlik kümesi eşitliği (düzenlemede "hedef değişti mi").
  bool sameAs(DocumentTargetSelection other) {
    if (type != other.type) return false;
    switch (type) {
      case DocumentTargetType.site:
        return true;
      case DocumentTargetType.blocks:
        return _sameIds(blockIds, other.blockIds);
      case DocumentTargetType.apartments:
        return _sameIds(apartmentIds, other.apartmentIds);
    }
  }

  static bool _sameIds(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    final set = a.toSet();
    return set.length == a.length && set.containsAll(b);
  }
}

class DocumentTargetSection extends StatefulWidget {
  const DocumentTargetSection({
    super.key,
    required this.scope,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.errorText,
  });

  final PeopleScope scope;
  final DocumentTargetSelection value;
  final ValueChanged<DocumentTargetSelection> onChanged;
  final bool enabled;

  /// Doğrulama hatası (form gönderilince üst form verir).
  final String? errorText;

  @override
  State<DocumentTargetSection> createState() => _DocumentTargetSectionState();
}

/// Blok araması için Türkçe uyumlu katlama: I / ı / İ / i aynı harf sayılır (Dart `toLowerCase` yerelden bağımsızdır:
/// "Iğdır Blok" için "ığdır" bulunmazdı).
String _foldSearch(String value) =>
    value.replaceAll('İ', 'i').replaceAll('I', 'i').replaceAll('ı', 'i').toLowerCase();

class _DocumentTargetSectionState extends State<DocumentTargetSection> {
  // Seçici pencereleri çift dokunuşta iki kez açılmasın.
  bool _picking = false;
  String? _limitError;
  List<SiteBlockRecord>? _blockCache;

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

  Future<void> _pickBlock() async {
    if (_picking) return;
    _picking = true;
    SiteBlockRecord? picked;
    try {
      final chosen = widget.value.blockIds.toSet();
      picked = await CrmPickerDialog.show<SiteBlockRecord>(
        context,
        CrmPickerDialog<SiteBlockRecord>(
          title: 'Blok Ekle',
          icon: Icons.domain_rounded,
          searchLabel: 'Blok ara',
          emptyTitle: 'Eklenecek blok bulunamadı.',
          fetch: (query, offset, limit) async {
            final blocks = await _loadBlocks();
            final q = _foldSearch(query.trim());
            final rows = blocks
                .where(
                  (b) =>
                      !chosen.contains(b.id) &&
                      (q.isEmpty || _foldSearch(b.blockName).contains(q)),
                )
                .toList();
            return (
              items: rows.skip(offset).take(limit).toList(),
              total: rows.length,
            );
          },
          keyOf: (b) => b.id,
          titleOf: (b) =>
              b.blockName.trim().isEmpty ? 'Adsız blok' : b.blockName.trim(),
        ),
      );
    } finally {
      _picking = false;
    }
    final block = picked;
    if (block == null || !mounted) return;
    if (widget.value.blockIds.contains(block.id)) return;
    if (widget.value.blocks.length >= DocumentTargetSelection.maxItems) {
      setState(() => _limitError = _tooMany);
      return;
    }
    setState(() => _limitError = null);
    widget.onChanged(
      widget.value.copyWith(
        blocks: <DocumentPick>[
          ...widget.value.blocks,
          (
            id: block.id,
            label: block.blockName.trim().isEmpty
                ? 'Adsız blok'
                : block.blockName.trim(),
          ),
        ],
      ),
    );
  }

  Future<void> _pickApartment() async {
    if (_picking) return;
    _picking = true;
    ApartmentSummary? picked;
    try {
      picked = await showApartmentPicker(
        context,
        widget.scope,
        title: 'Daire Ekle',
      );
    } finally {
      _picking = false;
    }
    final apartment = picked;
    if (apartment == null || !mounted) return;
    if (widget.value.apartmentIds.contains(apartment.id)) return;
    if (widget.value.apartments.length >= DocumentTargetSelection.maxItems) {
      setState(() => _limitError = _tooMany);
      return;
    }
    setState(() => _limitError = null);
    widget.onChanged(
      widget.value.copyWith(
        apartments: <DocumentPick>[
          ...widget.value.apartments,
          (id: apartment.id, label: apartment.fullLabel),
        ],
      ),
    );
  }

  static const String _tooMany =
      'En çok 500 öğe seçilebilir. Hedefi bölüp ayrı belgeler yükleyin.';

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final value = widget.value;
    final enabled = widget.enabled;
    final error = widget.errorText ?? _limitError;
    final isBlocks = value.type == DocumentTargetType.blocks;
    final isApartments = value.type == DocumentTargetType.apartments;
    final picks = isBlocks
        ? value.blocks
        : (isApartments ? value.apartments : const <DocumentPick>[]);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Hedef', style: th.titleSmall),
        const SizedBox(height: AppSpace.sm),
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          children: [
            for (final type in DocumentTargetType.values)
              ChoiceChip(
                key: ValueKey<String>('document_target_${type.apiValue}'),
                label: Text(type.label),
                selected: value.type == type,
                onSelected: enabled
                    ? (_) {
                        setState(() => _limitError = null);
                        widget.onChanged(value.copyWith(type: type));
                      }
                    : null,
              ),
          ],
        ),
        if (value.type == DocumentTargetType.site) ...[
          const SizedBox(height: AppSpace.sm),
          Text(
            'Sitedeki tüm aktif dairelerin güncel sakinleri görür.',
            style: th.bodySmall?.copyWith(color: p.textSecondary),
          ),
        ] else ...[
          const SizedBox(height: AppSpace.sm),
          if (picks.isNotEmpty) ...[
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.xs,
              children: [
                for (final pick in picks)
                  _PickedChip(
                    key: ValueKey<String>('document_pick_${pick.id}'),
                    label: pick.label,
                    onRemove: enabled
                        ? () {
                            setState(() => _limitError = null);
                            widget.onChanged(
                              isBlocks
                                  ? value.copyWith(
                                      blocks: value.blocks
                                          .where((b) => b.id != pick.id)
                                          .toList(),
                                    )
                                  : value.copyWith(
                                      apartments: value.apartments
                                          .where((a) => a.id != pick.id)
                                          .toList(),
                                    ),
                            );
                          }
                        : null,
                  ),
              ],
            ),
            const SizedBox(height: AppSpace.sm),
          ],
          PrimaryActionButton(
            key: ValueKey<String>(
              isBlocks ? 'document_add_block' : 'document_add_apartment',
            ),
            label: isBlocks ? 'Blok Ekle' : 'Daire Ekle',
            icon: Icons.add_rounded,
            variant: AppButtonVariant.outline,
            onPressed: enabled
                ? (isBlocks ? _pickBlock : _pickApartment)
                : null,
          ),
        ],
        if (error != null) ...[
          const SizedBox(height: AppSpace.sm),
          CrmFormError(message: error, reveal: false),
        ],
      ],
    );
  }
}

/// Hedefte seçili blok / daire çipi: ✕ düğmesi en az 48x48 dp dokunma hedefidir (ipucu etiketli); uzun etiket
/// sarar (kırpılmaz).
class _PickedChip extends StatelessWidget {
  const _PickedChip({super.key, required this.label, required this.onRemove});

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
              child: Text(
                label,
                style: th.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
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
