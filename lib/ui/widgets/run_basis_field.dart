import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/decision_models.dart';
import 'package:site_kapi_kontrol/models/finance.dart';
import 'package:site_kapi_kontrol/services/decision_book_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/large_dialog_parts.dart';
import 'package:site_kapi_kontrol/ui/helpers/date_input.dart';
import 'package:site_kapi_kontrol/ui/helpers/text_length.dart';

/// Tahakkuk dayanağının girilen değeri (K2): Karar Defteri kaydı ([decisionId]) ya da serbest metin gerekçe ([reason]).
@immutable
class RunBasisValue {
  const RunBasisValue({this.decisionId, this.reason});

  const RunBasisValue.empty() : this();

  final int? decisionId;
  final String? reason;

  @override
  bool operator ==(Object other) => other is RunBasisValue && other.decisionId == decisionId && other.reason == reason;

  @override
  int get hashCode => Object.hash(decisionId, reason);
}

/// Fon (demirbaş) tahakkukunun DAYANAĞI (K2, P1-2): Karar Defteri modülü AÇIK sitede kesinleşmiş bir karar seçilir
/// ([RunBasisMode.decision]), KAPALI sitede serbest metin gerekçe yazılır ([RunBasisMode.reason]). Seçim/yazım her değiştiğinde
/// [onChanged] çağrılır; değer geçerli değilken ([isBasisValid] false) çağıran onayı kapatır.
///
/// - Kararlar `GET .../decisions?status=kesin` ile yüklenir (en yeni 100; sunucu yalnız bu sitenin kararlarını verir). Yükleme,
///   hata (Tekrar Dene) ve boş durumları ayrıdır; boşken kullanıcıya önce Karar Defteri'nde karar eklemesi söylenir.
/// - Gerekçe sakinlerin Borcum ekranındaki borç dökümünde GÖRÜNÜR: alan altında bu açıkça yazılır (yönetici notu sanılmasın).
class RunBasisField extends StatefulWidget {
  const RunBasisField({
    super.key,
    required this.authService,
    required this.siteCode,
    required this.requirement,
    required this.onChanged,
    this.enabled = true,
    this.initial = const RunBasisValue.empty(),
    this.service,
  });

  final AuthService authService;
  final int siteCode;
  final DecisionRequirement requirement;
  final ValueChanged<RunBasisValue> onChanged;
  final bool enabled;
  final RunBasisValue initial;

  /// Test düzeneği: verilmezse [AuthService]'ten kurulur.
  final DecisionBookService? service;

  /// Listelenen en fazla karar sayısı (sunucu üst sınırı 200).
  static const int pageSize = 100;

  /// Girilen değer bu gereksinim için geçerli mi?
  static bool isBasisValid(DecisionRequirement requirement, RunBasisValue value) {
    switch (requirement.mode) {
      case RunBasisMode.decision:
        return value.decisionId != null;
      case RunBasisMode.reason:
        final length = trimmedCodePoints(value.reason ?? '');
        return length >= requirement.reasonMin && length <= requirement.reasonMax;
      case RunBasisMode.none:
        return true;
    }
  }

  /// Onay düğmesi pasifken kullanıcıya söylenen neden; geçerliyse null.
  static String? blockedReason(DecisionRequirement requirement, RunBasisValue value) {
    if (isBasisValid(requirement, value)) return null;
    switch (requirement.mode) {
      case RunBasisMode.decision:
        return 'Dayanak olarak Karar Defteri\'nden bir karar seçin.';
      case RunBasisMode.reason:
        return 'Borcun dayanağını (gerekçe) yazın.';
      case RunBasisMode.none:
        return null;
    }
  }

  @override
  State<RunBasisField> createState() => _RunBasisFieldState();
}

class _RunBasisFieldState extends State<RunBasisField> {
  late final DecisionBookService _service = widget.service ?? DecisionBookService(authService: widget.authService);
  final TextEditingController _reason = TextEditingController();

  List<Decision> _decisions = const <Decision>[];
  bool _loading = false;
  bool _more = false;
  String? _error;
  int? _selected;
  int _token = 0;

  RunBasisMode get _mode => widget.requirement.mode;

  @override
  void initState() {
    super.initState();
    _selected = widget.initial.decisionId;
    _reason.text = widget.initial.reason ?? '';
    if (_mode == RunBasisMode.decision) {
      _loading = true;
      unawaited(_fetch());
    }
  }

  @override
  void dispose() {
    ++_token;
    _reason.dispose();
    super.dispose();
  }

  /// "Tekrar Dene": yükleme durumuna geçip yeniden okur.
  Future<void> _load() {
    setState(() {
      _loading = true;
      _error = null;
    });
    return _fetch();
  }

  Future<void> _fetch() async {
    final token = ++_token;
    try {
      final page = await _service.listManaged(widget.siteCode, status: 'kesin', limit: RunBasisField.pageSize);
      if (!mounted || token != _token) return;
      final items = <Decision>[
        for (final item in page.items)
          // Sunucu süzgeci yok sayarsa bile yalnız KESİN (numaralı) kararlar seçilebilir.
          if (item.isFinal && item.numberLabel != null) item,
      ];
      setState(() {
        _decisions = items;
        _more = page.next != null;
        _loading = false;
        // Seçili karar listede yoksa (silinmiş / süzülmüş) seçim bırakılır.
        if (_selected != null && !items.any((d) => d.id == _selected)) _selected = null;
      });
      _emit();
    } catch (_) {
      if (!mounted || token != _token) return;
      setState(() {
        _loading = false;
        _error = 'Karar Defteri kayıtları yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.';
      });
    }
  }

  void _emit() {
    widget.onChanged(
      _mode == RunBasisMode.decision
          ? RunBasisValue(decisionId: _selected)
          : RunBasisValue(reason: _reason.text.trim().isEmpty ? null : _reason.text.trim()),
    );
  }

  static String _decisionLabel(Decision d) {
    final date = d.meetingDate == null ? '' : ' • ${formatCrmDate(d.meetingDate)}';
    final title = d.title.trim().isEmpty ? '' : ' • ${d.title.trim()}';
    return '${d.displayNumber}$title$date';
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final decisionMode = _mode == RunBasisMode.decision;
    return DialogPanel(
      key: const ValueKey<String>('run_basis_panel'),
      tone: AppTone.info,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const DialogSectionTitle(icon: Icons.gavel_rounded, title: 'Borcun dayanağı', tone: AppTone.info),
          const SizedBox(height: AppSpace.sm),
          Text(
            decisionMode
                ? 'Yatırım ve Demirbaş (Fon) Hesabı\'na borç yazmak için Karar Defteri\'nde kesinleşmiş bir karara dayanılmalıdır.'
                : 'Karar Defteri bu sitede kapalı. Yatırım ve Demirbaş (Fon) Hesabı\'na borç yazmak için borcun dayanağını '
                      '(örn. karar tarihi ve numarası) kısaca yazın.',
            key: const ValueKey<String>('run_basis_intro'),
            style: th.bodyMedium,
          ),
          const SizedBox(height: AppSpace.md),
          if (decisionMode) _decisionPicker(context) else _reasonField(context, th, p),
        ],
      ),
    );
  }

  Widget _decisionPicker(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    if (_loading) {
      return Row(
        key: const ValueKey<String>('run_basis_loading'),
        children: [
          const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: AppSpace.sm),
          Expanded(child: Text('Kararlar yükleniyor...', style: th.bodyMedium)),
        ],
      );
    }
    if (_error != null) {
      return InlineNotice(key: const ValueKey<String>('run_basis_error'), message: _error!, onRetry: _load);
    }
    if (_decisions.isEmpty) {
      return const InlineNotice(
        key: ValueKey<String>('run_basis_empty'),
        tone: AppTone.warning,
        message:
            'Seçilebilecek kesinleşmiş karar yok. Önce Karar Defteri\'nde ilgili kararı ekleyip kesinleştirin, sonra buraya dönün.',
      );
    }
    final selected = _decisions.where((d) => d.id == _selected).firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<int>(
          key: const ValueKey<String>('run_basis_decision'),
          isExpanded: true,
          initialValue: _selected,
          dropdownColor: p.surface,
          style: th.bodyLarge?.copyWith(color: p.text),
          decoration: const InputDecoration(labelText: 'Karar', prefixIcon: Icon(Icons.gavel_rounded)),
          items: [
            for (final d in _decisions)
              DropdownMenuItem<int>(
                value: d.id,
                child: Text(_decisionLabel(d), maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: widget.enabled
              ? (value) {
                  setState(() => _selected = value);
                  _emit();
                }
              : null,
        ),
        if (selected != null) ...[
          const SizedBox(height: AppSpace.xs),
          Text(
            [
              selected.meetingType.label,
              if (selected.voteResult != DecisionVoteResult.unknown) selected.voteResult.label,
            ].join(' • '),
            key: const ValueKey<String>('run_basis_selected_note'),
            style: th.bodySmall?.copyWith(color: p.textSecondary),
          ),
        ],
        const SizedBox(height: AppSpace.xs),
        Text(
          _more
              ? 'En yeni ${RunBasisField.pageSize} karar listelenir. Daha eski bir karar için Karar Defteri\'ni kullanın.'
              : 'Karar numarası sakinlerin Borcum ekranındaki borç dökümünde görünür.',
          style: th.bodySmall?.copyWith(color: p.textSecondary),
        ),
      ],
    );
  }

  Widget _reasonField(BuildContext context, TextTheme th, AppPalette p) {
    final requirement = widget.requirement;
    return TextFormField(
      key: const ValueKey<String>('run_basis_reason'),
      controller: _reason,
      enabled: widget.enabled,
      minLines: 2,
      maxLines: 4,
      textCapitalization: TextCapitalization.sentences,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      onChanged: (_) {
        setState(() {});
        _emit();
      },
      decoration: InputDecoration(
        labelText: 'Gerekçe',
        hintText: 'Örn. Yönetim kurulunun 14.10.2026 tarihli ve 6 sayılı kararı',
        prefixIcon: const Icon(Icons.notes_rounded),
        helperText: 'Bu gerekçe sakinlerin Borcum ekranındaki borç dökümünde görünür.',
        helperMaxLines: 3,
        counterText: '${trimmedCodePoints(_reason.text)}/${requirement.reasonMax}',
      ),
      validator: (value) {
        final length = trimmedCodePoints(value ?? '');
        if (length < requirement.reasonMin) return 'Gerekçe en az ${requirement.reasonMin} karakter olmalı.';
        if (length > requirement.reasonMax) return 'Gerekçe en çok ${requirement.reasonMax} karakter olabilir.';
        return null;
      },
    );
  }
}
