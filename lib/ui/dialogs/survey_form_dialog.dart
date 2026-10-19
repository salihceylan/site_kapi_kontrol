// Yeni anket formu (docs/PLATFORM_ANKET.md `POST /manager/sites/:siteCode/surveys`): başlık, soru, 2-10 seçenek
// (ekle / sil), hedef (tüm site / bloklar / daireler), anonim ve "daire başına tek oy" anahtarları, kapanış tarihi;
// "Taslak Kaydet" ya da "Yayınla" (publish: draft | now).
//
// Çift gönderim: düğmeler gönderim sürerken kapalıdır. Hata pencerenin içinde kalır, metinler korunur.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MaxLengthEnforcement;
import 'package:site_kapi_kontrol/models/apartment_crm.dart' show ApartmentSummary;
import 'package:site_kapi_kontrol/models/site_block_record.dart';
import 'package:site_kapi_kontrol/models/survey_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/survey_api.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart' show InlineNotice;
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/crm_pickers.dart' show showApartmentPicker;
import 'package:site_kapi_kontrol/ui/dialogs/dialog_parts.dart';
import 'package:site_kapi_kontrol/ui/helpers/date_input.dart' show formatDateField;
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart' show crmMessageOf;
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';

typedef _Picked = ({int id, String label});

class SurveyFormDialog extends StatefulWidget {
  const SurveyFormDialog({super.key, required this.service, required this.scope, this.clock});

  final SurveyService service;

  /// Site kapsamı (blok / daire seçicileri `authService` üzerinden).
  final PeopleScope scope;

  /// Test düzeneği: şimdiki an.
  final DateTime Function()? clock;

  /// Başarıda sunucunun döndürdüğü ayrıntıyla kapanır; vazgeçilirse null.
  static Future<SurveyDetail?> show(
    BuildContext context, {
    required SurveyService service,
    required PeopleScope scope,
    DateTime Function()? clock,
  }) {
    return showDialog<SurveyDetail>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SurveyFormDialog(service: service, scope: scope, clock: clock),
    );
  }

  @override
  State<SurveyFormDialog> createState() => _SurveyFormDialogState();
}

class _SurveyFormDialogState extends State<SurveyFormDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _title = TextEditingController();
  final TextEditingController _question = TextEditingController();
  final List<TextEditingController> _options = <TextEditingController>[
    TextEditingController(),
    TextEditingController(),
  ];

  SurveyTargetType _targetType = SurveyTargetType.site;
  List<_Picked> _blocks = const <_Picked>[];
  List<_Picked> _apartments = const <_Picked>[];
  bool _anonymous = true;
  bool _oneVotePerApartment = false;
  DateTime? _closesAt;
  bool _busy = false;
  String? _error;
  String? _targetError;
  List<SiteBlockRecord>? _blockCache;

  DateTime _now() => (widget.clock ?? DateTime.now)();

  @override
  void dispose() {
    _title.dispose();
    _question.dispose();
    for (final c in _options) {
      c.dispose();
    }
    super.dispose();
  }

  // --- Seçenekler -----------------------------------------------------------------------------

  void _addOption() {
    if (_options.length >= SurveyCreateRequest.maxOptions) return;
    setState(() => _options.add(TextEditingController()));
  }

  void _removeOption(int index) {
    if (_options.length <= SurveyCreateRequest.minOptions) return;
    final removed = _options.removeAt(index);
    setState(() {});
    // Kaldırılan denetleyici çerçeve bittikten sonra serbest bırakılır (alan hâlâ çizilmiş olabilir).
    WidgetsBinding.instance.addPostFrameCallback((_) => removed.dispose());
  }

  // --- Hedef ----------------------------------------------------------------------------------

  Future<List<SiteBlockRecord>> _loadBlocks() async {
    final cached = _blockCache;
    if (cached != null) return cached;
    final (structure, error) = await widget.scope.authService.getSiteStructure(siteCode: widget.scope.siteCode);
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
    List<SiteBlockRecord> blocks;
    try {
      blocks = await _loadBlocks();
    } catch (e) {
      if (!mounted) return;
      setState(() => _targetError = crmMessageOf(e, 'Bloklar yüklenemedi. Lütfen tekrar deneyin.'));
      return;
    }
    if (!mounted) return;
    final chosen = <int>{for (final b in _blocks) b.id};
    final remaining = blocks.where((b) => !chosen.contains(b.id)).toList(growable: false);
    if (remaining.isEmpty) {
      setState(() => _targetError = blocks.isEmpty ? 'Bu sitede tanımlı blok yok.' : 'Tüm bloklar zaten seçili.');
      return;
    }
    final picked = await showDialog<SiteBlockRecord>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Blok Seç'),
        children: [
          for (final b in remaining)
            SimpleDialogOption(
              key: ValueKey<String>('survey_block_pick_${b.id}'),
              onPressed: () => Navigator.of(dialogContext).pop(b),
              child: Text(b.blockName.trim().isEmpty ? 'Blok ${b.id}' : b.blockName.trim()),
            ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _blocks = <_Picked>[..._blocks, (id: picked.id, label: picked.blockName.trim())];
      _targetError = null;
    });
  }

  Future<void> _pickApartment() async {
    if (_apartments.length >= SurveyCreateRequest.maxTargetItems) {
      setState(() => _targetError = 'En çok ${SurveyCreateRequest.maxTargetItems} daire seçilebilir.');
      return;
    }
    final ApartmentSummary? picked = await showApartmentPicker(context, widget.scope);
    if (picked == null || !mounted) return;
    if (_apartments.any((a) => a.id == picked.id)) {
      setState(() => _targetError = 'Bu daire zaten seçili.');
      return;
    }
    setState(() {
      _apartments = <_Picked>[..._apartments, (id: picked.id, label: picked.fullLabel)];
      _targetError = null;
    });
  }

  String? _validateTarget() {
    switch (_targetType) {
      case SurveyTargetType.site:
        return null;
      case SurveyTargetType.blocks:
        return _blocks.isEmpty ? 'En az bir blok seçin.' : null;
      case SurveyTargetType.apartments:
        return _apartments.isEmpty ? 'En az bir daire seçin.' : null;
    }
  }

  // --- Kapanış --------------------------------------------------------------------------------

  Future<void> _pickClosesAt() async {
    final now = _now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _closesAt ?? today.add(const Duration(days: 7)),
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
      helpText: 'Kapanış günü',
    );
    if (picked == null || !mounted) return;
    // Seçilen günün sonu (23:59, yerel).
    setState(() => _closesAt = DateTime(picked.year, picked.month, picked.day, 23, 59));
  }

  // --- Gönderim -------------------------------------------------------------------------------

  Future<void> _submit({required bool publish}) async {
    if (_busy) return;
    final targetError = _validateTarget();
    final valid = _formKey.currentState?.validate() ?? false;
    setState(() => _targetError = targetError);
    if (!valid || targetError != null) return;
    final closesAt = _closesAt;
    if (closesAt != null && !closesAt.isAfter(_now())) {
      setState(() => _error = 'Kapanış tarihi gelecekte olmalı.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final request = SurveyCreateRequest(
      title: _title.text,
      question: _question.text,
      options: <String>[for (final c in _options) c.text.trim()],
      targetType: _targetType,
      blockIds: <int>[for (final b in _blocks) b.id],
      apartmentIds: <int>[for (final a in _apartments) a.id],
      anonymous: _anonymous,
      oneVotePerApartment: _oneVotePerApartment,
      closesAt: closesAt,
      publishNow: publish,
    );
    try {
      final detail = await widget.service.create(widget.scope.siteCode, request);
      if (!mounted) return;
      Navigator.of(context).pop(detail);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = crmMessageOf(e, 'Anket kaydedilemedi. Lütfen tekrar deneyin.');
      });
    }
  }

  String? _required(String? value, String label, int max) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return '$label boş olamaz.';
    if (text.length > max) return '$label en çok $max karakter olabilir.';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final closesAt = _closesAt;
    return PopScope(
      canPop: !_busy,
      child: AppDialog(
        title: 'Yeni Anket',
        subtitle: widget.scope.siteName.trim().isEmpty ? null : widget.scope.siteName.trim(),
        icon: Icons.poll_rounded,
        actions: [
          TextButton(
            key: const ValueKey<String>('survey_form_cancel'),
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            key: const ValueKey<String>('survey_form_draft'),
            onPressed: _busy ? null : () => unawaited(_submit(publish: false)),
            child: const Text('Taslak Kaydet'),
          ),
          FilledButton.icon(
            key: const ValueKey<String>('survey_form_publish'),
            onPressed: _busy ? null : () => unawaited(_submit(publish: true)),
            icon: const Icon(Icons.send_rounded, size: 18),
            label: const Text('Yayınla'),
          ),
        ],
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_error != null) ...[
                InlineNotice(key: const ValueKey<String>('survey_form_error'), tone: AppTone.danger, message: _error!),
                const SizedBox(height: AppSpace.md),
              ],
              TextFormField(
                key: const ValueKey<String>('survey_form_title'),
                controller: _title,
                enabled: !_busy,
                maxLength: SurveyCreateRequest.titleMax,
                maxLengthEnforcement: MaxLengthEnforcement.enforced,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Başlık', prefixIcon: Icon(Icons.title_rounded)),
                validator: (v) => _required(v, 'Başlık', SurveyCreateRequest.titleMax),
              ),
              const SizedBox(height: AppSpace.md),
              TextFormField(
                key: const ValueKey<String>('survey_form_question'),
                controller: _question,
                enabled: !_busy,
                maxLength: SurveyCreateRequest.questionMax,
                maxLengthEnforcement: MaxLengthEnforcement.enforced,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(labelText: 'Soru', alignLabelWithHint: true),
                validator: (v) => _required(v, 'Soru', SurveyCreateRequest.questionMax),
              ),
              const SizedBox(height: AppSpace.lg),
              Text('Seçenekler (${_options.length}/${SurveyCreateRequest.maxOptions})', style: th.titleSmall),
              const SizedBox(height: AppSpace.sm),
              for (var i = 0; i < _options.length; i++) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        key: ValueKey<String>('survey_form_option_$i'),
                        controller: _options[i],
                        enabled: !_busy,
                        maxLength: SurveyCreateRequest.optionMax,
                        maxLengthEnforcement: MaxLengthEnforcement.enforced,
                        decoration: InputDecoration(labelText: 'Seçenek ${i + 1}'),
                        validator: (v) => _required(v, 'Seçenek ${i + 1}', SurveyCreateRequest.optionMax),
                      ),
                    ),
                    IconButton(
                      key: ValueKey<String>('survey_form_option_remove_$i'),
                      tooltip: 'Seçeneği sil',
                      onPressed: _busy || _options.length <= SurveyCreateRequest.minOptions
                          ? null
                          : () => _removeOption(i),
                      icon: const Icon(Icons.remove_circle_outline_rounded),
                    ),
                  ],
                ),
              ],
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const ValueKey<String>('survey_form_option_add'),
                  onPressed: _busy || _options.length >= SurveyCreateRequest.maxOptions ? null : _addOption,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Seçenek ekle'),
                ),
              ),
              const SizedBox(height: AppSpace.lg),
              Text('Hedef kitle', style: th.titleSmall),
              const SizedBox(height: AppSpace.sm),
              Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.sm,
                children: [
                  for (final t in SurveyTargetType.values)
                    ChoiceChip(
                      key: ValueKey<String>('survey_form_target_${t.apiValue}'),
                      label: Text(t.label),
                      selected: _targetType == t,
                      onSelected: _busy
                          ? null
                          : (_) => setState(() {
                              _targetType = t;
                              _targetError = null;
                            }),
                    ),
                ],
              ),
              if (_targetType == SurveyTargetType.blocks) ...[
                const SizedBox(height: AppSpace.sm),
                _PickedChips(
                  items: _blocks,
                  keyPrefix: 'survey_form_block',
                  onRemove: _busy ? null : (id) => setState(() => _blocks = _blocks.where((b) => b.id != id).toList()),
                ),
                TextButton.icon(
                  key: const ValueKey<String>('survey_form_block_add'),
                  onPressed: _busy ? null : () => unawaited(_pickBlock()),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Blok ekle'),
                ),
              ],
              if (_targetType == SurveyTargetType.apartments) ...[
                const SizedBox(height: AppSpace.sm),
                _PickedChips(
                  items: _apartments,
                  keyPrefix: 'survey_form_apartment',
                  onRemove: _busy
                      ? null
                      : (id) => setState(() => _apartments = _apartments.where((a) => a.id != id).toList()),
                ),
                TextButton.icon(
                  key: const ValueKey<String>('survey_form_apartment_add'),
                  onPressed: _busy ? null : () => unawaited(_pickApartment()),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Daire ekle'),
                ),
              ],
              if (_targetError != null) ...[
                const SizedBox(height: AppSpace.xs),
                Text(
                  _targetError!,
                  key: const ValueKey<String>('survey_form_target_error'),
                  style: th.bodySmall?.copyWith(color: AppTone.danger.ink(p)),
                ),
              ],
              const SizedBox(height: AppSpace.lg),
              DialogToggleTile(
                key: const ValueKey<String>('survey_form_anonymous'),
                title: 'Anonim oylama',
                subtitle: _anonymous ? 'Kimin ne oy verdiği görünmez.' : 'Yönetici oy verenleri ve seçimlerini görür.',
                value: _anonymous,
                onChanged: _busy ? null : (v) => setState(() => _anonymous = v),
                onIcon: Icons.visibility_off_rounded,
                offIcon: Icons.badge_outlined,
                offTone: AppTone.warning,
              ),
              const SizedBox(height: AppSpace.sm),
              DialogToggleTile(
                key: const ValueKey<String>('survey_form_one_vote'),
                title: 'Daire başına tek oy',
                subtitle: 'Aynı dairede ikinci hesap oy kullanamaz.',
                value: _oneVotePerApartment,
                onChanged: _busy ? null : (v) => setState(() => _oneVotePerApartment = v),
                onIcon: Icons.home_rounded,
                offIcon: Icons.people_alt_outlined,
              ),
              const SizedBox(height: AppSpace.lg),
              Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    key: const ValueKey<String>('survey_form_closes'),
                    onPressed: _busy ? null : () => unawaited(_pickClosesAt()),
                    icon: const Icon(Icons.event_rounded, size: 18),
                    label: Text(closesAt == null ? 'Kapanış tarihi: yok' : 'Kapanış: ${formatDateField(closesAt)}'),
                  ),
                  if (closesAt != null)
                    TextButton(
                      key: const ValueKey<String>('survey_form_closes_clear'),
                      onPressed: _busy ? null : () => setState(() => _closesAt = null),
                      child: const Text('Kaldır'),
                    ),
                ],
              ),
              const SizedBox(height: AppSpace.xs),
              Text(
                'Kapanış tarihi yoksa anket siz kapatana kadar açık kalır.',
                style: th.bodySmall?.copyWith(color: p.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PickedChips extends StatelessWidget {
  const _PickedChips({required this.items, required this.keyPrefix, required this.onRemove});

  final List<_Picked> items;
  final String keyPrefix;
  final void Function(int id)? onRemove;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: AppSpace.sm,
      runSpacing: AppSpace.xs,
      children: [
        for (final item in items)
          InputChip(
            key: ValueKey<String>('${keyPrefix}_${item.id}'),
            label: Text(item.label.isEmpty ? '#${item.id}' : item.label, maxLines: 1, overflow: TextOverflow.ellipsis),
            onDeleted: onRemove == null ? null : () => onRemove!(item.id),
          ),
      ],
    );
  }
}
