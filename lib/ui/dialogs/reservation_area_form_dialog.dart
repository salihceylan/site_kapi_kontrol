// Ortak alan ekleme / düzenleme formu (docs/PLATFORM_REZERVASYON.md `POST|PATCH .../reservation-areas`): ad, açıklama,
// kapasite, dilim süresi, en az / en çok dilim, kaç gün önceden, onay modu, iptal süresi, kişi limitleri ve haftalık
// açık gün + saat aralıkları. Yalnız yönetici / süper kullanıcıya açılır (görevli ve kurul 403 alır; menüde düğme yok).
//
// Doğrulama sunucudakiyle aynı sınırları kullanır, ama KARARI sunucu verir (409 / 400 pencerede düz Türkçe gösterilir).
// Düzenlemede yalnız DEĞİŞEN alanlar gönderilir (mevcut rezervasyonlar etkilenmez). Çift gönderim: düğme gönderim
// sürerken kapalıdır ve geri tuşu pencereyi kapatmaz; hata pencerenin içinde kalır, girilenler korunur; 429'da düğme
// `Retry-After` süresince kilitlenir.
import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show
        FilteringTextInputFormatter,
        LengthLimitingTextInputFormatter,
        MaxLengthEnforcement,
        TextInputFormatter;
import 'package:site_kapi_kontrol/models/reservation_models.dart';
import 'package:site_kapi_kontrol/services/reservation_api.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/helpers/form_validation.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart'
    show crmMessageOf;
import 'package:site_kapi_kontrol/ui/helpers/retry_lock.dart';
import 'package:site_kapi_kontrol/ui/widgets/crm_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/reservation_parts.dart';

const int _kMaxRangesPerDay = 3;

/// Bir açık saat aralığının iki metin alanı.
class _HoursRange {
  _HoursRange(String start, String end)
    : start = TextEditingController(text: start),
      end = TextEditingController(text: end);

  final TextEditingController start;
  final TextEditingController end;

  void dispose() {
    start.dispose();
    end.dispose();
  }
}

class ReservationAreaFormDialog extends StatefulWidget {
  const ReservationAreaFormDialog({
    super.key,
    required this.service,
    required this.siteCode,
    this.area,
  });

  final ReservationService service;
  final int siteCode;

  /// null: yeni alan; dolu: düzenleme.
  final ReservationArea? area;

  /// Başarıda sunucunun döndürdüğü alanla kapanır; vazgeçilirse (ya da değişiklik yoksa) null.
  static Future<ReservationArea?> show(
    BuildContext context, {
    required ReservationService service,
    required int siteCode,
    ReservationArea? area,
  }) {
    return showDialog<ReservationArea>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ReservationAreaFormDialog(
        service: service,
        siteCode: siteCode,
        area: area,
      ),
    );
  }

  @override
  State<ReservationAreaFormDialog> createState() =>
      _ReservationAreaFormDialogState();
}

class _ReservationAreaFormDialogState extends State<ReservationAreaFormDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final GlobalKey _hoursKey = GlobalKey();
  final GlobalKey _relationKey = GlobalKey();
  final FocusNode _sendFocus = FocusNode(debugLabel: 'area_form_send');
  final RetryLock _retry = RetryLock();

  late final TextEditingController _name = TextEditingController(text: widget.area?.name ?? '');
  late final TextEditingController _description = TextEditingController(text: widget.area?.description ?? '');
  late final TextEditingController _capacity = TextEditingController(text: '${widget.area?.capacity ?? 1}');
  late final TextEditingController _slot = TextEditingController(text: '${widget.area?.slotMinutes ?? 60}');
  late final TextEditingController _minSlots = TextEditingController(text: '${widget.area?.minSlots ?? 1}');
  late final TextEditingController _maxSlots = TextEditingController(text: '${widget.area?.maxSlots ?? 4}');
  late final TextEditingController _daysAhead = TextEditingController(text: '${widget.area?.maxDaysAhead ?? 14}');
  late final TextEditingController _cutoff = TextEditingController(text: '${widget.area?.cancelCutoffHours ?? 2}');
  late final TextEditingController _daily = TextEditingController(text: '${widget.area?.perUserDailyLimit ?? 2}');
  late final TextEditingController _weekly = TextEditingController(text: '${widget.area?.perUserWeeklyLimit ?? 5}');
  late ReservationApproval _approval = widget.area?.approvalMode ?? ReservationApproval.otomatik;

  final Map<int, List<_HoursRange>> _hours = <int, List<_HoursRange>>{
    for (var day = 1; day <= 7; day++) day: <_HoursRange>[],
  };
  final List<_HoursRange> _removed = <_HoursRange>[];

  bool _submitting = false;
  bool _closing = false;
  String? _error;
  String? _relationError;
  String? _hoursError;

  bool get _editing => widget.area != null;

  @override
  void initState() {
    super.initState();
    final area = widget.area;
    if (area == null) {
      // Yeni alanda her gün 09:00-22:00 önerilir; yönetici düzenler ya da siler.
      for (var day = 1; day <= 7; day++) {
        _hours[day]!.add(_HoursRange('09:00', '22:00'));
      }
    } else {
      for (final hours in area.weeklyHours) {
        _hours[hours.weekday]?.add(_HoursRange(hours.start, hours.end));
      }
    }
  }

  @override
  void dispose() {
    _retry.dispose();
    _sendFocus.dispose();
    for (final controller in <TextEditingController>[
      _name,
      _description,
      _capacity,
      _slot,
      _minSlots,
      _maxSlots,
      _daysAhead,
      _cutoff,
      _daily,
      _weekly,
    ]) {
      controller.dispose();
    }
    for (final ranges in _hours.values) {
      for (final range in ranges) {
        range.dispose();
      }
    }
    for (final range in _removed) {
      range.dispose();
    }
    super.dispose();
  }

  int? _int(TextEditingController controller) => int.tryParse(controller.text.trim());

  String? Function(String?) _intValidator(
    String label,
    int min,
    int max, {
    int? multipleOf,
  }) {
    return (value) {
      final n = int.tryParse((value ?? '').trim());
      if (n == null || n < min || n > max) {
        return '$label $min-$max arasında tam sayı olmalıdır.';
      }
      if (multipleOf != null && n % multipleOf != 0) {
        return '$label $multipleOf ve katları olmalıdır.';
      }
      return null;
    };
  }

  /// Formdaki tüm değerler (sunucu alan adlarıyla).
  Map<String, Object?> _values() {
    final description = _description.text.trim();
    return <String, Object?>{
      'name': _name.text.trim(),
      'description': description.isEmpty ? null : description,
      'capacity': _int(_capacity),
      'slot_minutes': _int(_slot),
      'min_slots': _int(_minSlots),
      'max_slots': _int(_maxSlots),
      'max_days_ahead': _int(_daysAhead),
      'approval_mode': _approval.apiValue,
      'cancel_cutoff_hours': _int(_cutoff),
      'per_user_daily_limit': _int(_daily),
      'per_user_weekly_limit': _int(_weekly),
      'weekly_hours': <Map<String, dynamic>>[
        for (var day = 1; day <= 7; day++)
          for (final range in _hours[day]!)
            ?_hoursJson(day, range),
      ],
    };
  }

  Map<String, dynamic>? _hoursJson(int day, _HoursRange range) {
    final start = hhmmToMinutes(range.start.text);
    final end = hhmmToMinutes(range.end.text, allow24: true);
    if (start == null || end == null) return null;
    return <String, dynamic>{
      'weekday': day,
      'start': minutesToHhmm(start),
      'end': minutesToHhmm(end),
    };
  }

  /// Düzenlemede yalnız değişen alanlar.
  Map<String, Object?> _changes(ReservationArea area) {
    final values = _values();
    final out = <String, Object?>{};
    void compare(String key, Object? current) {
      if (values[key] != current) out[key] = values[key];
    }

    compare('name', area.name);
    compare('description', area.description);
    compare('capacity', area.capacity);
    compare('slot_minutes', area.slotMinutes);
    compare('min_slots', area.minSlots);
    compare('max_slots', area.maxSlots);
    compare('max_days_ahead', area.maxDaysAhead);
    compare('approval_mode', area.approvalMode.apiValue);
    compare('cancel_cutoff_hours', area.cancelCutoffHours);
    compare('per_user_daily_limit', area.perUserDailyLimit);
    compare('per_user_weekly_limit', area.perUserWeeklyLimit);
    final hours = ReservationHours.listFrom(values['weekly_hours']);
    if (!listEquals(hours, area.weeklyHours)) out['weekly_hours'] = values['weekly_hours'];
    return out;
  }

  bool _validateExtras() {
    String? relation;
    String? hours;
    final min = _int(_minSlots);
    final max = _int(_maxSlots);
    final daily = _int(_daily);
    final weekly = _int(_weekly);
    final slot = _int(_slot);
    if (min != null && max != null && min > max) {
      relation = 'En az dilim, en çok dilimden büyük olamaz.';
    } else if (daily != null && weekly != null && daily > weekly) {
      relation = 'Günlük limit haftalık limitten büyük olamaz.';
    }
    outer:
    for (var day = 1; day <= 7; day++) {
      final dayName = reservationWeekdayLabel(day, long: true);
      final parsed = <(int, int)>[];
      for (final range in _hours[day]!) {
        final start = hhmmToMinutes(range.start.text);
        final end = hhmmToMinutes(range.end.text, allow24: true);
        // Biçimi bozuk saatleri alan doğrulayıcısı gösterir.
        if (start == null || end == null) continue;
        if (end <= start) {
          hours = '$dayName: kapanış saati açılıştan sonra olmalıdır.';
          break outer;
        }
        if (slot != null && slot > 0 && end - start < slot) {
          hours =
              '$dayName: her aralığa en az bir dilim (${reservationDurationText(slot)}) sığmalıdır.';
          break outer;
        }
        parsed.add((start, end));
      }
      parsed.sort((a, b) => a.$1.compareTo(b.$1));
      for (var i = 1; i < parsed.length; i++) {
        if (parsed[i].$1 < parsed[i - 1].$2) {
          hours = '$dayName: açık saat aralıkları çakışamaz.';
          break outer;
        }
      }
    }
    setState(() {
      _relationError = relation;
      _hoursError = hours;
    });
    return relation == null && hours == null;
  }

  bool _revealExtras() {
    final target = _relationError != null
        ? _relationKey.currentContext
        : (_hoursError != null ? _hoursKey.currentContext : null);
    if (target == null) return false;
    Scrollable.ensureVisible(target, duration: Duration.zero, alignment: 0.1);
    return true;
  }

  Future<void> _submit() async {
    if (_submitting || _retry.locked) return;
    if (!validateForm(
      _formKey,
      validateExtra: _validateExtras,
      revealExtra: _revealExtras,
    )) {
      setState(() => _error = kFixFieldsMessage);
      return;
    }
    final area = widget.area;
    final fields = area == null ? _values() : _changes(area);
    if (fields.isEmpty) {
      // Değişiklik yok: istek atılmaz.
      _closing = true;
      popIfCurrent<ReservationArea>(context);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final saved = area == null
          ? await widget.service.createArea(widget.siteCode, fields)
          : await widget.service.updateArea(widget.siteCode, area.id, fields);
      if (!mounted) return;
      _closing = true;
      popIfCurrent<ReservationArea>(context, saved);
    } catch (e) {
      if (!mounted) return;
      _retry.lockIfRateLimited(e, () {
        if (mounted) setState(() {});
      });
      setState(() {
        _submitting = false;
        _error = crmMessageOf(
          e,
          'Alan kaydedilemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
        );
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _sendFocus.requestFocus();
      });
    }
  }

  void _close() {
    if (_closing || _submitting) return;
    _closing = true;
    popIfCurrent<ReservationArea>(context);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: AppDialog(
        title: _editing ? 'Alanı Düzenle' : 'Yeni Alan',
        subtitle: _editing ? widget.area!.label : 'Ortak alan tanımı',
        icon: Icons.meeting_room_rounded,
        actions: [
          TextButton(
            key: const ValueKey<String>('area_form_close'),
            onPressed: _submitting ? null : _close,
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            key: const ValueKey<String>('area_form_send'),
            focusNode: _sendFocus,
            onPressed: (_submitting || _retry.locked) ? null : () => unawaited(_submit()),
            child: Text(_submitting ? 'Kaydediliyor...' : 'Kaydet'),
          ),
        ],
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) CrmFormError(message: _error!, announce: true),
              if (_editing) ...[
                const InlineNotice(
                  tone: AppTone.info,
                  message: 'Değişiklikler yeni rezervasyonlar için geçerlidir; mevcut rezervasyonlar etkilenmez.',
                ),
                const SizedBox(height: AppSpace.lg),
              ],
              TextFormField(
                key: const ValueKey<String>('area_form_name'),
                controller: _name,
                enabled: !_submitting,
                textCapitalization: TextCapitalization.sentences,
                maxLength: kAreaNameMax,
                maxLengthEnforcement: MaxLengthEnforcement.none,
                buildCounter:
                    (context, {required currentLength, required isFocused, maxLength}) =>
                        reservationCounter(context, _name.text.runes.length, kAreaNameMax),
                autovalidateMode: AutovalidateMode.onUserInteraction,
                textInputAction: TextInputAction.next,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Alan adı',
                  hintText: 'Örn. Spor salonu, Tenis kortu',
                  prefixIcon: Icon(Icons.title_rounded),
                ),
                validator: (value) {
                  final length = (value ?? '').trim().runes.length;
                  if (length < 1) return 'Alan adı boş olamaz.';
                  if (length > kAreaNameMax) return 'Alan adı en çok $kAreaNameMax karakter olabilir.';
                  return null;
                },
              ),
              const SizedBox(height: AppSpace.lg),
              TextFormField(
                key: const ValueKey<String>('area_form_description'),
                controller: _description,
                enabled: !_submitting,
                minLines: 2,
                maxLines: 5,
                maxLength: kAreaDescriptionMax,
                maxLengthEnforcement: MaxLengthEnforcement.none,
                buildCounter:
                    (context, {required currentLength, required isFocused, maxLength}) =>
                        reservationCounter(context, _description.text.runes.length, kAreaDescriptionMax),
                keyboardType: TextInputType.multiline,
                textCapitalization: TextCapitalization.sentences,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Açıklama (isteğe bağlı)',
                  alignLabelWithHint: true,
                ),
                validator: (value) {
                  final length = (value ?? '').trim().runes.length;
                  return length > kAreaDescriptionMax
                      ? 'Açıklama en çok $kAreaDescriptionMax karakter olabilir.'
                      : null;
                },
              ),
              const SizedBox(height: AppSpace.lg),
              _intField(
                keyName: 'area_form_capacity',
                controller: _capacity,
                label: 'Kapasite',
                helper: 'Aynı anda en çok kaç rezervasyon alınabilir',
                icon: Icons.groups_rounded,
                validator: _intValidator('Kapasite', 1, 100),
              ),
              _intField(
                keyName: 'area_form_slot',
                controller: _slot,
                label: 'Dilim süresi (dakika)',
                helper: 'Rezervasyon bu sürenin katları kadar alınır (15-480, 5 dakikanın katı)',
                icon: Icons.timelapse_rounded,
                validator: _intValidator('Dilim süresi', 15, 480, multipleOf: 5),
              ),
              _intField(
                keyName: 'area_form_min',
                controller: _minSlots,
                label: 'En az dilim',
                icon: Icons.unfold_less_rounded,
                validator: _intValidator('En az dilim', 1, 48),
              ),
              _intField(
                keyName: 'area_form_max',
                controller: _maxSlots,
                label: 'En çok dilim',
                icon: Icons.unfold_more_rounded,
                validator: _intValidator('En çok dilim', 1, 48),
              ),
              _intField(
                keyName: 'area_form_days',
                controller: _daysAhead,
                label: 'Kaç gün önceden',
                helper: 'Bugünden en çok kaç gün sonrası için rezervasyon yapılabilir',
                icon: Icons.event_rounded,
                validator: _intValidator('Gün sayısı', 1, 180),
              ),
              DropdownButtonFormField<ReservationApproval>(
                key: const ValueKey<String>('area_form_approval'),
                isExpanded: true,
                initialValue: _approval,
                dropdownColor: p.surface,
                style: th.bodyMedium?.copyWith(color: p.text),
                decoration: const InputDecoration(
                  labelText: 'Onay modu',
                  prefixIcon: Icon(Icons.fact_check_rounded),
                ),
                items: [
                  for (final mode in ReservationApproval.values)
                    DropdownMenuItem<ReservationApproval>(
                      value: mode,
                      child: Text(mode.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: _submitting
                    ? null
                    : (value) {
                        if (value != null) setState(() => _approval = value);
                      },
              ),
              const SizedBox(height: AppSpace.lg),
              _intField(
                keyName: 'area_form_cutoff',
                controller: _cutoff,
                label: 'İptal süresi (saat)',
                helper: 'Başlangıca bu kadar saatten az kalınca sakin iptal edemez (0 = son ana kadar)',
                icon: Icons.cancel_schedule_send_rounded,
                validator: _intValidator('İptal süresi', 0, 168),
              ),
              _intField(
                keyName: 'area_form_daily',
                controller: _daily,
                label: 'Günlük kişi limiti',
                helper: 'Bir kişi bir günde en çok kaç rezervasyon yapabilir',
                icon: Icons.person_rounded,
                validator: _intValidator('Günlük limit', 1, 20),
              ),
              _intField(
                keyName: 'area_form_weekly',
                controller: _weekly,
                label: 'Haftalık kişi limiti',
                helper: 'Bir kişi bir haftada en çok kaç rezervasyon yapabilir',
                icon: Icons.person_rounded,
                validator: _intValidator('Haftalık limit', 1, 100),
              ),
              if (_relationError != null)
                KeyedSubtree(
                  key: _relationKey,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: AppSpace.lg),
                    child: InlineNotice(
                      key: const ValueKey<String>('area_form_relation_error'),
                      message: _relationError!,
                    ),
                  ),
                ),
              _hoursSection(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _intField({
    required String keyName,
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required String? Function(String?) validator,
    String? helper,
  }) {
    // Sarmalayıcıya sabit anahtar: üstteki hata özeti / ilişki uyarısı eklenip kalkınca alanlar yeniden kurulmaz
    // (yoksa doğrulama hataları ve kullanıcı etkileşimi durumu kaybolurdu).
    return Padding(
      key: ValueKey<String>('${keyName}_pad'),
      padding: const EdgeInsets.only(bottom: AppSpace.lg),
      child: TextFormField(
        key: ValueKey<String>(keyName),
        controller: controller,
        enabled: !_submitting,
        keyboardType: TextInputType.number,
        inputFormatters: <TextInputFormatter>[
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(4),
        ],
        autovalidateMode: AutovalidateMode.onUserInteraction,
        onChanged: (_) {
          if (_relationError != null) setState(() => _relationError = null);
        },
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          helperMaxLines: 3,
          prefixIcon: Icon(icon),
        ),
        validator: validator,
      ),
    );
  }

  Widget _hoursSection(BuildContext context) {
    final th = Theme.of(context).textTheme;
    return KeyedSubtree(
      key: _hoursKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(header: true, child: Text('Haftalık açık saatler', style: th.titleSmall)),
          const SizedBox(height: AppSpace.xs),
          Text(
            'Her gün için en çok $_kMaxRangesPerDay aralık. Aralığı olmayan gün kapalıdır. Saatleri SS:DD yazın (kapanış için 24:00 de olur).',
            style: th.bodySmall?.copyWith(color: context.palette.textSecondary),
          ),
          for (var day = 1; day <= 7; day++) _dayBlock(context, day),
          if (_hoursError != null) ...[
            const SizedBox(height: AppSpace.md),
            InlineNotice(
              key: const ValueKey<String>('area_form_hours_error'),
              message: _hoursError!,
            ),
          ],
        ],
      ),
    );
  }

  Widget _dayBlock(BuildContext context, int day) {
    final th = Theme.of(context).textTheme;
    final ranges = _hours[day]!;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(reservationWeekdayLabel(day, long: true), style: th.titleSmall),
          if (ranges.isEmpty)
            Text(
              'Kapalı',
              key: ValueKey<String>('area_form_closed_$day'),
              style: th.bodySmall?.copyWith(color: context.palette.textSecondary),
            ),
          for (var i = 0; i < ranges.length; i++)
            KeyedSubtree(
              key: ObjectKey(ranges[i]),
              child: _rangeRow(context, day, i, ranges),
            ),
          if (ranges.length < _kMaxRangesPerDay)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                key: ValueKey<String>('area_form_add_$day'),
                onPressed: _submitting
                    ? null
                    : () => setState(() => ranges.add(_HoursRange('09:00', '22:00'))),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Aralık ekle'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _timeField(
    String keyName,
    TextEditingController controller,
    String label, {
    required bool allow24,
  }) {
    return TextFormField(
      key: ValueKey<String>(keyName),
      controller: controller,
      enabled: !_submitting,
      keyboardType: TextInputType.datetime,
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.allow(RegExp(r'[0-9:]')),
        LengthLimitingTextInputFormatter(5),
      ],
      autovalidateMode: AutovalidateMode.onUserInteraction,
      onChanged: (_) {
        if (_hoursError != null) setState(() => _hoursError = null);
      },
      decoration: InputDecoration(labelText: label, hintText: 'SS:DD'),
      validator: (value) =>
          hhmmToMinutes(value, allow24: allow24) == null ? 'SS:DD biçiminde yazın.' : null,
    );
  }

  Widget _rangeRow(BuildContext context, int day, int index, List<_HoursRange> ranges) {
    final range = ranges[index];
    final start = _timeField('area_form_${day}_${index}_start', range.start, 'Açılış', allow24: false);
    final end = _timeField('area_form_${day}_${index}_end', range.end, 'Kapanış', allow24: true);
    final remove = IconButton(
      key: ValueKey<String>('area_form_remove_${day}_$index'),
      tooltip: 'Aralığı sil',
      icon: const Icon(Icons.delete_outline_rounded),
      onPressed: _submitting
          ? null
          : () => setState(() {
              ranges.removeAt(index);
              _removed.add(range);
              _hoursError = null;
            }),
    );
    // Diyalog genişliği ekrana göre belirlenir; dar ekranda ya da büyük yazıda iki alan alt alta dizilir.
    // (`LayoutBuilder` kullanılmaz: kaydırılabilir diyalog içerik ölçülerini sorgular, LayoutBuilder buna izin vermez.)
    final narrow = MediaQuery.sizeOf(context).width < 480 || isLargeText(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.sm),
      child: narrow
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                start,
                const SizedBox(height: AppSpace.sm),
                end,
                Align(alignment: AlignmentDirectional.centerEnd, child: remove),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: start),
                const SizedBox(width: AppSpace.sm),
                Expanded(child: end),
                remove,
              ],
            ),
    );
  }
}
