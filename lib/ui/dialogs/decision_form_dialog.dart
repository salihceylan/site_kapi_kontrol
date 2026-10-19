// Karar formu: yeni taslak (`POST /manager/sites/:siteCode/decisions`) ya da taslak düzenleme (`PATCH`, yalnız değişen
// alanlar). Toplantı türü, toplantı tarihi (GG.AA.YYYY; İngilizce tarih seçici YOK), başlık, karar metni (en çok 10.000
// karakter, sayaçlı), katılanlar, oylama sonucu, isteğe bağlı oy sayıları ve "Sakinler de görsün" anahtarı.
// Düzeltme kararında (`supersedes`) değiştirilen kararın numarası gösterilir ve `supersedes_id` gönderilir.
//
// Çift gönderim: düğmeler gönderim sürerken kapalıdır. Hata pencerenin içinde kalır, metinler korunur; sunucunun
// `INVALID_FIELD {field}` yanıtı ilgili alanın altında gösterilir.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter, MaxLengthEnforcement;
import 'package:site_kapi_kontrol/models/decision_models.dart';
import 'package:site_kapi_kontrol/services/decision_book_api.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart' show InlineNotice;
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/dialog_parts.dart';
import 'package:site_kapi_kontrol/ui/helpers/date_input.dart';
import 'package:site_kapi_kontrol/ui/helpers/istanbul_time.dart' show istanbulNow;
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart' show crmMessageOf;
import 'package:site_kapi_kontrol/ui/helpers/ui_helpers.dart' show dialogWidthForScreen;

class DecisionFormDialog extends StatefulWidget {
  const DecisionFormDialog({
    super.key,
    required this.service,
    required this.site,
    this.initial,
    this.supersedes,
    this.clock,
  });

  final DecisionBookService service;
  final DecisionSite site;

  /// Düzenlenen taslak; null ise yeni karar.
  final Decision? initial;

  /// Düzeltme kararı: değiştirilecek KESİN karar (yalnız yeni kararda).
  final Decision? supersedes;

  /// Test düzeneği: şimdiki an.
  final DateTime Function()? clock;

  /// Başarıda sunucunun döndürdüğü kararla kapanır; vazgeçilirse ya da değişiklik yoksa null.
  static Future<Decision?> show(
    BuildContext context, {
    required DecisionBookService service,
    required DecisionSite site,
    Decision? initial,
    Decision? supersedes,
    DateTime Function()? clock,
  }) {
    return showDialog<Decision>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DecisionFormDialog(
        service: service,
        site: site,
        initial: initial,
        supersedes: supersedes,
        clock: clock,
      ),
    );
  }

  @override
  State<DecisionFormDialog> createState() => _DecisionFormDialogState();
}

class _DecisionFormDialogState extends State<DecisionFormDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _date;
  late final TextEditingController _title;
  late final TextEditingController _body;
  late final TextEditingController _attendees;
  late final TextEditingController _votesFor;
  late final TextEditingController _votesAgainst;
  late final TextEditingController _votesAbstain;

  late DecisionMeetingType _meetingType;
  late DecisionVoteResult _voteResult;
  late bool _residents;
  bool _busy = false;
  bool _dateOverflow = false;
  String? _error;
  String? _voteError;

  /// Sunucunun `INVALID_FIELD` yanıtı: alan adı -> metin (alan değişince silinir).
  final Map<String, String> _fieldErrors = <String, String>{};

  bool get _isEdit => widget.initial != null;

  DateTime _today() {
    final now = istanbulNow(widget.clock?.call());
    return DateTime(now.year, now.month, now.day);
  }

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _meetingType = initial?.meetingType ?? widget.supersedes?.meetingType ?? DecisionMeetingType.yonetimKurulu;
    final vote = initial?.voteResult ?? DecisionVoteResult.kabul;
    _voteResult = vote == DecisionVoteResult.unknown ? DecisionVoteResult.kabul : vote;
    _residents = initial?.isVisibleToResidents ?? false;
    _date = TextEditingController(text: formatDateField(initial?.meetingDate ?? _today()));
    _title = TextEditingController(text: initial?.title ?? '');
    _body = TextEditingController(text: initial?.body ?? '');
    _attendees = TextEditingController(text: initial?.attendees ?? '');
    _votesFor = TextEditingController(text: initial?.votesFor?.toString() ?? '');
    _votesAgainst = TextEditingController(text: initial?.votesAgainst?.toString() ?? '');
    _votesAbstain = TextEditingController(text: initial?.votesAbstain?.toString() ?? '');
  }

  @override
  void dispose() {
    for (final c in <TextEditingController>[_date, _title, _body, _attendees, _votesFor, _votesAgainst, _votesAbstain]) {
      c.dispose();
    }
    super.dispose();
  }

  // --- Doğrulama ------------------------------------------------------------------------------

  String? _required(String? value, String label, int max) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return '$label boş olamaz.';
    if (text.length > max) return '$label en çok $max karakter olabilir.';
    return null;
  }

  String? _validateDate(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return 'Toplantı tarihini girin (GG.AA.YYYY).';
    final format = validateDateField(text);
    if (format != null) return format;
    final day = parseDateField(text)!;
    if (day.isBefore(DateTime(DecisionInput.meetingDateMinYear))) {
      return 'Toplantı tarihi 01.01.${DecisionInput.meetingDateMinYear} tarihinden önce olamaz.';
    }
    if (day.isAfter(_today().add(const Duration(days: DecisionInput.meetingDateMaxAheadDays)))) {
      return 'Toplantı tarihi bir yıldan daha ileri olamaz.';
    }
    return null;
  }

  /// Boş = girilmedi (null); doluysa 0..[DecisionInput.votesMax] tam sayı.
  String? _validateVotes(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return null;
    final n = int.tryParse(text);
    if (n == null || n < 0 || n > DecisionInput.votesMax) return '0 ile ${DecisionInput.votesMax} arası';
    return null;
  }

  int? _votes(TextEditingController c) {
    final text = c.text.trim();
    return text.isEmpty ? null : int.tryParse(text);
  }

  void _clearFieldError(String field) {
    if (_fieldErrors.remove(field) != null) setState(() {});
  }

  // --- Gönderim -------------------------------------------------------------------------------

  Future<void> _submit() async {
    if (_busy) return;
    _fieldErrors.clear();
    final valid = _formKey.currentState?.validate() ?? false;
    final voteError = <TextEditingController>[_votesFor, _votesAgainst, _votesAbstain].any((c) => _validateVotes(c.text) != null)
        ? 'Oy sayıları 0 ile ${DecisionInput.votesMax} arasında tam sayı olmalıdır.'
        : null;
    setState(() => _voteError = voteError);
    if (!valid || voteError != null) return;
    final input = DecisionInput(
      meetingType: _meetingType,
      meetingDate: parseDateField(_date.text)!,
      title: _title.text,
      body: _body.text,
      attendees: _attendees.text,
      voteResult: _voteResult,
      votesFor: _votes(_votesFor),
      votesAgainst: _votes(_votesAgainst),
      votesAbstain: _votes(_votesAbstain),
      visibility: _residents ? DecisionVisibility.sakinler : DecisionVisibility.yonetim,
      supersedesId: _isEdit ? null : widget.supersedes?.id,
    );
    final initial = widget.initial;
    Map<String, Object?>? changes;
    if (initial != null) {
      changes = input.diff(initial);
      if (changes.isEmpty) {
        Navigator.of(context).pop();
        return;
      }
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final saved = initial == null
          ? await widget.service.create(widget.site.code, input)
          : await widget.service.update(widget.site.code, initial.id, changes!);
      if (!mounted) return;
      Navigator.of(context).pop(saved);
    } catch (e) {
      if (!mounted) return;
      final message = crmMessageOf(e, 'Karar kaydedilemedi. Lütfen tekrar deneyin.');
      final field = decisionInvalidField(e);
      setState(() {
        _busy = false;
        _error = message;
        if (field != null) _fieldErrors[field] = message;
      });
    }
  }

  // --- Görünüm --------------------------------------------------------------------------------

  Widget _votesField(String field, TextEditingController controller, String label) => TextFormField(
    key: ValueKey<String>('decision_form_$field'),
    controller: controller,
    enabled: !_busy,
    keyboardType: TextInputType.number,
    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    maxLength: 6,
    buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
    forceErrorText: _fieldErrors[field],
    onChanged: (_) => _clearFieldError(field),
    decoration: InputDecoration(labelText: label),
    validator: _validateVotes,
  );

  /// Üç oy alanı: geniş pencerede yan yana, dar ekranda / büyük yazıda alt alta. (AlertDialog iç ölçü hesapladığı için
  /// LayoutBuilder kullanılamaz; karar pencere genişliğinden verilir.)
  Widget _votesFields(BuildContext context) {
    final fields = <Widget>[
      _votesField('votes_for', _votesFor, 'Kabul'),
      _votesField('votes_against', _votesAgainst, 'Ret'),
      _votesField('votes_abstain', _votesAbstain, 'Çekimser'),
    ];
    final wide = dialogWidthForScreen(context) >= 360 && MediaQuery.textScalerOf(context).scale(1) < 1.3;
    if (wide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < fields.length; i++) ...[
            if (i > 0) const SizedBox(width: AppSpace.sm),
            Expanded(child: fields[i]),
          ],
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < fields.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpace.sm),
          fields[i],
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final supersedes = _isEdit ? null : widget.supersedes;
    final supersedesId = _isEdit ? widget.initial!.supersedesId : supersedes?.id;
    final supersedesLabel = _isEdit ? widget.initial!.supersedesLabel : supersedes?.numberLabel;
    return PopScope(
      canPop: !_busy,
      child: AppDialog(
        key: const ValueKey<String>('decision_form'),
        title: _isEdit ? 'Taslağı Düzenle' : (supersedes != null ? 'Düzeltme Kararı' : 'Yeni Karar'),
        subtitle: widget.site.label,
        icon: Icons.gavel_rounded,
        actions: [
          TextButton(
            key: const ValueKey<String>('decision_form_cancel'),
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: const Text('Vazgeç'),
          ),
          FilledButton.icon(
            key: const ValueKey<String>('decision_form_save'),
            onPressed: _busy ? null : () => unawaited(_submit()),
            icon: const Icon(Icons.save_rounded, size: 18),
            label: Text(_isEdit ? 'Kaydet' : 'Taslak Olarak Kaydet'),
          ),
        ],
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_error != null) ...[
                InlineNotice(key: const ValueKey<String>('decision_form_error'), tone: AppTone.danger, message: _error!),
                const SizedBox(height: AppSpace.md),
              ],
              if (supersedesId != null) ...[
                InlineNotice(
                  key: const ValueKey<String>('decision_form_supersedes'),
                  tone: AppTone.info,
                  icon: Icons.swap_horiz_rounded,
                  message:
                      'Bu karar ${supersedesLabel ?? 'önceki'} sayılı kararı değiştirir. Kesinleşince eski karar '
                      '"değiştirildi" olarak işaretlenir.',
                ),
                const SizedBox(height: AppSpace.md),
              ],
              if (!_isEdit) ...[
                Text(
                  'Karar taslak olarak kaydedilir; kesinleştirene kadar düzenleyebilir ya da silebilirsiniz.',
                  style: th.bodySmall?.copyWith(color: p.textSecondary),
                ),
                const SizedBox(height: AppSpace.md),
              ],
              Text('Toplantı türü', style: th.titleSmall),
              const SizedBox(height: AppSpace.sm),
              Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.sm,
                children: [
                  for (final t in DecisionMeetingType.values)
                    ChoiceChip(
                      key: ValueKey<String>('decision_form_type_${t.apiValue}'),
                      label: Text(t.label),
                      selected: _meetingType == t,
                      onSelected: _busy
                          ? null
                          : (_) => setState(() {
                              _meetingType = t;
                              _fieldErrors.remove('meeting_type');
                            }),
                    ),
                ],
              ),
              if (_fieldErrors['meeting_type'] != null) ...[
                const SizedBox(height: AppSpace.xs),
                Text(_fieldErrors['meeting_type']!, style: th.bodySmall?.copyWith(color: AppTone.danger.ink(p))),
              ],
              const SizedBox(height: AppSpace.lg),
              TextFormField(
                key: const ValueKey<String>('decision_form_date'),
                controller: _date,
                enabled: !_busy,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  DateInputFormatter(onRejected: () => setState(() => _dateOverflow = true)),
                ],
                forceErrorText: _fieldErrors['meeting_date'],
                onChanged: (_) {
                  _clearFieldError('meeting_date');
                  if (_dateOverflow) setState(() => _dateOverflow = false);
                },
                decoration: InputDecoration(
                  labelText: 'Toplantı tarihi',
                  hintText: 'GG.AA.YYYY',
                  helperText: _dateOverflow
                      ? 'Tarih en çok 8 rakamdır (GG.AA.YYYY); fazla rakam eklenmedi.'
                      : 'Gün.Ay.Yıl biçiminde yazın (GG.AA.YYYY).',
                  helperMaxLines: 3,
                  prefixIcon: const Icon(Icons.event_rounded),
                ),
                validator: _validateDate,
              ),
              const SizedBox(height: AppSpace.md),
              TextFormField(
                key: const ValueKey<String>('decision_form_title'),
                controller: _title,
                enabled: !_busy,
                maxLength: DecisionInput.titleMax,
                maxLengthEnforcement: MaxLengthEnforcement.enforced,
                textInputAction: TextInputAction.next,
                forceErrorText: _fieldErrors['title'],
                onChanged: (_) => _clearFieldError('title'),
                decoration: const InputDecoration(labelText: 'Başlık', prefixIcon: Icon(Icons.title_rounded)),
                validator: (v) => _required(v, 'Başlık', DecisionInput.titleMax),
              ),
              const SizedBox(height: AppSpace.md),
              TextFormField(
                key: const ValueKey<String>('decision_form_body'),
                controller: _body,
                enabled: !_busy,
                maxLength: DecisionInput.bodyMax,
                maxLengthEnforcement: MaxLengthEnforcement.enforced,
                minLines: 4,
                maxLines: 12,
                keyboardType: TextInputType.multiline,
                forceErrorText: _fieldErrors['body'],
                onChanged: (_) => _clearFieldError('body'),
                decoration: const InputDecoration(labelText: 'Karar metni', alignLabelWithHint: true),
                validator: (v) => _required(v, 'Karar metni', DecisionInput.bodyMax),
              ),
              const SizedBox(height: AppSpace.md),
              TextFormField(
                key: const ValueKey<String>('decision_form_attendees'),
                controller: _attendees,
                enabled: !_busy,
                maxLength: DecisionInput.attendeesMax,
                maxLengthEnforcement: MaxLengthEnforcement.enforced,
                minLines: 1,
                maxLines: 4,
                keyboardType: TextInputType.multiline,
                forceErrorText: _fieldErrors['attendees'],
                onChanged: (_) => _clearFieldError('attendees'),
                decoration: const InputDecoration(
                  labelText: 'Katılanlar',
                  helperText: 'İsteğe bağlı. Toplantıya katılanların adları.',
                  helperMaxLines: 2,
                  alignLabelWithHint: true,
                  prefixIcon: Icon(Icons.groups_rounded),
                ),
              ),
              const SizedBox(height: AppSpace.lg),
              Text('Oylama sonucu', style: th.titleSmall),
              const SizedBox(height: AppSpace.sm),
              Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.sm,
                children: [
                  for (final r in DecisionVoteResult.known)
                    ChoiceChip(
                      key: ValueKey<String>('decision_form_vote_${r.apiValue}'),
                      label: Text(r.label),
                      selected: _voteResult == r,
                      onSelected: _busy
                          ? null
                          : (_) => setState(() {
                              _voteResult = r;
                              _fieldErrors.remove('vote_result');
                            }),
                    ),
                ],
              ),
              if (_fieldErrors['vote_result'] != null) ...[
                const SizedBox(height: AppSpace.xs),
                Text(_fieldErrors['vote_result']!, style: th.bodySmall?.copyWith(color: AppTone.danger.ink(p))),
              ],
              const SizedBox(height: AppSpace.md),
              Text('Oy sayıları (isteğe bağlı)', style: th.titleSmall),
              const SizedBox(height: AppSpace.sm),
              _votesFields(context),
              if (_voteError != null) ...[
                const SizedBox(height: AppSpace.xs),
                Text(
                  _voteError!,
                  key: const ValueKey<String>('decision_form_votes_error'),
                  style: th.bodySmall?.copyWith(color: AppTone.danger.ink(p)),
                ),
              ],
              const SizedBox(height: AppSpace.lg),
              DialogToggleTile(
                key: const ValueKey<String>('decision_form_visibility'),
                title: 'Sakinler de görsün',
                subtitle: _residents
                    ? 'Kesinleşince sakinler "Kararlar" ekranında görür.'
                    : 'Yalnız yönetim ve kurul üyeleri görür.',
                value: _residents,
                onChanged: _busy
                    ? null
                    : (v) => setState(() {
                        _residents = v;
                        _fieldErrors.remove('visibility');
                      }),
                onIcon: Icons.groups_rounded,
                offIcon: Icons.lock_outline_rounded,
                onTone: AppTone.info,
              ),
              if (_fieldErrors['visibility'] != null) ...[
                const SizedBox(height: AppSpace.xs),
                Text(_fieldErrors['visibility']!, style: th.bodySmall?.copyWith(color: AppTone.danger.ink(p))),
              ],
              const SizedBox(height: AppSpace.md),
              Text(
                kDecisionLegalNotice,
                key: const ValueKey<String>('decision_form_legal'),
                style: th.bodySmall?.copyWith(color: p.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
