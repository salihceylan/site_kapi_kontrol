// Rezervasyon yapma penceresi (docs/PLATFORM_REZERVASYON.md): gün -> boş saat (dilim) -> süre -> not -> gönder.
//
// Boş saatler sunucudan gelir (`availability`: dilim süresi, kapasite, dolu bilgisi); dolu dilim pasiftir. Onay modu
// `yonetici_onayli` ise "onay bekliyor" bilgisi gösterilir. Çift gönderim: düğme gönderim sürerken kapalıdır ve geri
// tuşu pencereyi kapatmaz; aynı seçimle yeniden gönderimde servis AYNI `idempotency_key`i kullanır. Hata pencerenin
// içinde kalır, seçim ve not korunur (409'da boş saatler tazelenir); 429'da düğme `Retry-After` süresince kilitlenir.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MaxLengthEnforcement;
import 'package:site_kapi_kontrol/models/reservation_models.dart';
import 'package:site_kapi_kontrol/services/reservation_api.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/helpers/form_validation.dart';
import 'package:site_kapi_kontrol/ui/helpers/retry_lock.dart';
import 'package:site_kapi_kontrol/ui/views/reservation_controllers.dart';
import 'package:site_kapi_kontrol/ui/widgets/crm_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/reservation_parts.dart';

class ReservationBookingDialog extends StatefulWidget {
  const ReservationBookingDialog({
    super.key,
    required this.service,
    required this.area,
  });

  final ReservationService service;
  final ReservationArea area;

  /// Başarıda sunucunun döndürdüğü kayıtla kapanır; vazgeçilirse null.
  static Future<ReservationCreateResult?> show(
    BuildContext context, {
    required ReservationService service,
    required ReservationArea area,
  }) {
    return showDialog<ReservationCreateResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ReservationBookingDialog(service: service, area: area),
    );
  }

  @override
  State<ReservationBookingDialog> createState() =>
      _ReservationBookingDialogState();
}

class _ReservationBookingDialogState extends State<ReservationBookingDialog> {
  late final ReservationBookingController _c = ReservationBookingController(
    service: widget.service,
    area: widget.area,
  );
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final FocusNode _sendFocus = FocusNode(debugLabel: 'rez_booking_send');
  final RetryLock _retry = RetryLock();
  final TextEditingController _note = TextEditingController();
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    unawaited(_c.load());
  }

  @override
  void dispose() {
    _retry.dispose();
    _sendFocus.dispose();
    _note.dispose();
    _c.dispose();
    super.dispose();
  }

  void _close() {
    if (_closing || _c.busy) return;
    _closing = true;
    popIfCurrent<ReservationCreateResult>(context);
  }

  Future<void> _submit() async {
    if (_c.busy || _retry.locked) return;
    if (!validateForm(_formKey)) return;
    FocusScope.of(context).unfocus();
    final ok = await _c.submit(_note.text);
    if (!mounted) return;
    if (ok) {
      _closing = true;
      popIfCurrent<ReservationCreateResult>(context, _c.created);
      return;
    }
    final error = _c.lastError;
    if (error != null) {
      final limited = _retry.lockIfRateLimited(error, () {
        if (mounted) setState(() {});
      });
      if (limited) setState(() {});
    }
    // Hata sonrası odak Gönder düğmesine (klavye / ekran okuyucu kullanıcısı hatayı kaçırmasın).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _sendFocus.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: ListenableBuilder(
        listenable: _c,
        builder: (context, _) {
          final blocked = _c.moduleClosed || _c.areaClosed;
          return AppDialog(
            title: 'Rezervasyon Yap',
            subtitle: widget.area.label,
            icon: Icons.event_available_rounded,
            actions: [
              TextButton(
                key: const ValueKey<String>('rez_booking_close'),
                onPressed: _c.busy ? null : _close,
                child: const Text('Vazgeç'),
              ),
              if (!blocked)
                ElevatedButton(
                  key: const ValueKey<String>('rez_booking_send'),
                  focusNode: _sendFocus,
                  onPressed: (_c.busy || _retry.locked) ? null : () => unawaited(_submit()),
                  child: Text(_c.busy ? 'Gönderiliyor...' : 'Rezervasyon Yap'),
                ),
            ],
            child: _content(context),
          );
        },
      ),
    );
  }

  Widget _content(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final area = widget.area;
    if (_c.moduleClosed) {
      return const InlineNotice(
        key: ValueKey<String>('rez_booking_module_off'),
        tone: AppTone.warning,
        message: 'Rezervasyon ve Konsiyerj bu site için kapalı.',
      );
    }
    if (_c.areaClosed) {
      return const InlineNotice(
        key: ValueKey<String>('rez_booking_area_closed'),
        tone: AppTone.warning,
        message: 'Bu alan artık rezerve edilemiyor. Listeyi yenileyip tekrar deneyin.',
      );
    }
    final availability = _c.availability;
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_c.actionError != null) CrmFormError(message: _c.actionError!, announce: true),
          InlineNotice(
            key: const ValueKey<String>('rez_approval_note'),
            tone: AppTone.info,
            message: area.approvalMode == ReservationApproval.yoneticiOnayli
                ? 'Bu alanda rezervasyonlar yönetici onayına gönderilir. Onaylanana kadar durumu "Onay bekliyor" görünür ve seçtiğiniz saat sizin için ayrılmış sayılır.'
                : 'Bu alanda rezervasyonunuz seçtiğiniz anda onaylanır.',
          ),
          const SizedBox(height: AppSpace.md),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.xs,
            children: [
              InfoChip('Dilim: ${reservationDurationText(area.slotMinutes)}'),
              InfoChip(
                area.minSlots == area.maxSlots
                    ? '${area.minSlots} dilim'
                    : '${area.minSlots}-${area.maxSlots} dilim',
              ),
              if (area.capacity > 1) InfoChip('Kapasite: ${area.capacity}'),
              if (area.cancelCutoffHours > 0)
                InfoChip('Başlangıçtan ${area.cancelCutoffHours} saat öncesine kadar iptal'),
            ],
          ),
          const SizedBox(height: AppSpace.lg),
          if (_c.loadError != null)
            InlineNotice(
              key: const ValueKey<String>('rez_booking_load_error'),
              message: _c.loadError!,
              onRetry: _c.load,
            )
          else if (availability == null)
            const ListSkeleton(rows: 2, inCard: true)
          else ...[
            _dayPicker(context, th),
            const SizedBox(height: AppSpace.lg),
            _slotPicker(context, th),
          ],
          const SizedBox(height: AppSpace.lg),
          TextFormField(
            key: const ValueKey<String>('rez_note'),
            controller: _note,
            enabled: !_c.busy,
            minLines: 1,
            maxLines: 3,
            maxLength: kReservationNoteMax,
            maxLengthEnforcement: MaxLengthEnforcement.none,
            buildCounter:
                (context, {required currentLength, required isFocused, maxLength}) =>
                    reservationCounter(context, _note.text.runes.length, kReservationNoteMax),
            textCapitalization: TextCapitalization.sentences,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Not (isteğe bağlı)',
              hintText: 'Örn. doğum günü, 8 kişi',
              prefixIcon: Icon(Icons.notes_rounded),
            ),
            validator: (value) {
              final length = (value ?? '').trim().runes.length;
              return length > kReservationNoteMax
                  ? 'Not en çok $kReservationNoteMax karakter olabilir.'
                  : null;
            },
          ),
        ],
      ),
    );
  }

  String _dayLabel(AvailabilityDay day) {
    if (day.slots.isEmpty) return '${day.shortLabel} · Kapalı';
    if (!day.slots.any((slot) => slot.available)) return '${day.shortLabel} · Dolu';
    return day.shortLabel;
  }

  Widget _dayPicker(BuildContext context, TextTheme th) {
    final days = _c.days;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(header: true, child: Text('Gün seçin', style: th.titleSmall)),
        const SizedBox(height: AppSpace.sm),
        if (days.isEmpty)
          Text(
            'Bu aralıkta rezerve edilebilecek gün yok.',
            key: const ValueKey<String>('rez_no_days'),
            style: th.bodyMedium,
          )
        else
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: [
              for (final day in days)
                ChoiceChip(
                  key: ValueKey<String>('rez_day_${day.date}'),
                  label: Text(_dayLabel(day)),
                  selected: _c.selectedDate == day.date,
                  onSelected: _c.busy ? null : (_) => _c.selectDate(day.date),
                ),
            ],
          ),
        if (_c.hasPreviousWindow || _c.hasNextWindow) ...[
          const SizedBox(height: AppSpace.sm),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.xs,
            children: [
              if (_c.hasPreviousWindow)
                TextButton.icon(
                  key: const ValueKey<String>('rez_prev_window'),
                  onPressed: (_c.busy || _c.loading) ? null : () => unawaited(_c.goToWindow(-1)),
                  icon: const Icon(Icons.chevron_left_rounded),
                  label: const Text('Önceki günler'),
                ),
              if (_c.hasNextWindow)
                TextButton.icon(
                  key: const ValueKey<String>('rez_next_window'),
                  onPressed: (_c.busy || _c.loading) ? null : () => unawaited(_c.goToWindow(1)),
                  icon: const Icon(Icons.chevron_right_rounded),
                  label: const Text('Sonraki günler'),
                ),
            ],
          ),
        ],
        if (_c.loading) ...[
          const SizedBox(height: AppSpace.sm),
          Text('Boş saatler yükleniyor...', style: th.bodySmall),
        ],
      ],
    );
  }

  String _slotLabel(int index, AvailabilitySlot slot) {
    if (!slot.available) return '${slot.rangeText} · Dolu';
    if (!_c.isSelectable(index)) return '${slot.rangeText} · Süre yetmiyor';
    if (slot.capacity > 1) return '${slot.rangeText} · ${slot.capacity - slot.booked} boş';
    return slot.rangeText;
  }

  Widget _slotPicker(BuildContext context, TextTheme th) {
    final slots = _c.daySlots;
    final selected = _c.selectedSlot;
    final area = widget.area;
    final maxCount = selected == null ? 0 : _c.maxCountFrom(selected);
    final summary = _c.summary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(header: true, child: Text('Saat seçin', style: th.titleSmall)),
        const SizedBox(height: AppSpace.sm),
        if (_c.selectedDate == null)
          Text('Önce bir gün seçin.', style: th.bodyMedium)
        else if (slots.isEmpty)
          Text(
            'Bu gün için uygun saat yok (alan kapalı ya da saatler geçti).',
            key: const ValueKey<String>('rez_no_slots'),
            style: th.bodyMedium,
          )
        else
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: [
              for (var i = 0; i < slots.length; i++)
                ChoiceChip(
                  key: ValueKey<String>('rez_slot_$i'),
                  label: Text(_slotLabel(i, slots[i])),
                  selected: selected != null && i >= selected && i < selected + _c.slotCount,
                  onSelected: (_c.busy || !_c.isSelectable(i)) ? null : (_) => _c.selectSlot(i),
                ),
            ],
          ),
        if (selected != null && maxCount > area.minSlots) ...[
          const SizedBox(height: AppSpace.md),
          DropdownButtonFormField<int>(
            key: ValueKey<String>('rez_slot_count_${selected}_${_c.slotCount}'),
            isExpanded: true,
            initialValue: _c.slotCount,
            dropdownColor: context.palette.surface,
            style: th.bodyMedium?.copyWith(color: context.palette.text),
            decoration: const InputDecoration(
              labelText: 'Süre',
              prefixIcon: Icon(Icons.timelapse_rounded),
            ),
            items: [
              for (var n = area.minSlots; n <= maxCount; n++)
                DropdownMenuItem<int>(
                  value: n,
                  child: Text(
                    '$n dilim (${reservationDurationText(n * area.slotMinutes)})',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: _c.busy
                ? null
                : (value) {
                    if (value != null) _c.setSlotCount(value);
                  },
          ),
        ],
        if (summary != null) ...[
          const SizedBox(height: AppSpace.md),
          Semantics(
            liveRegion: true,
            child: Text(
              'Seçiminiz: $summary',
              key: const ValueKey<String>('rez_summary'),
              style: th.titleSmall,
            ),
          ),
        ],
      ],
    );
  }
}
