// Rezervasyon kararı penceresi (docs/PLATFORM_REZERVASYON.md `POST .../reservations/:id/decision`): onay, ret ve
// iptal. Ret ve iptalde gerekçe ZORUNLUDUR (rezervasyon sahibi görür); onayda not isteğe bağlıdır.
//
// Yetki kararını SUNUCU verir (kurul 403); pencereyi yalnız yazma yetkisi olan kullanıcıya liste açar. Çift
// gönderim: düğme gönderim sürerken kapalıdır ve geri tuşu pencereyi kapatmaz. Hata pencerenin içinde kalır,
// gerekçe korunur; 404 / 409'da kayıt başkasınca değişmiş olabilir (pencere kapanınca liste yenilenir); 429'da düğme
// `Retry-After` süresince kilitlenir.
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
import 'package:site_kapi_kontrol/ui/widgets/reservation_parts.dart';

class ReservationDecisionDialog extends StatefulWidget {
  const ReservationDecisionDialog({
    super.key,
    required this.service,
    required this.siteCode,
    required this.reservation,
    required this.action,
  });

  final ReservationService service;
  final int siteCode;
  final ReservationRecord reservation;

  /// `approve | reject | cancel`.
  final String action;

  /// Karar verilirse sunucunun döndürdüğü sonuçla kapanır; vazgeçilirse (ya da hata sonrası kapatılırsa) null.
  /// Çağıran, null dönse bile listeyi yeniden çekmelidir (kayıt başkasınca değişmiş olabilir).
  static Future<ReservationDecisionResult?> show(
    BuildContext context, {
    required ReservationService service,
    required int siteCode,
    required ReservationRecord reservation,
    required String action,
  }) {
    return showDialog<ReservationDecisionResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ReservationDecisionDialog(
        service: service,
        siteCode: siteCode,
        reservation: reservation,
        action: action,
      ),
    );
  }

  @override
  State<ReservationDecisionDialog> createState() =>
      _ReservationDecisionDialogState();
}

class _ReservationDecisionDialogState extends State<ReservationDecisionDialog> {
  late final ReservationDecisionController _c = ReservationDecisionController(
    service: widget.service,
    siteCode: widget.siteCode,
    reservation: widget.reservation,
  );
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final FocusNode _sendFocus = FocusNode(debugLabel: 'rez_decision_send');
  final RetryLock _retry = RetryLock();
  final TextEditingController _note = TextEditingController();
  bool _closing = false;

  bool get _noteRequired => widget.action != 'approve';

  String get _title => switch (widget.action) {
    'approve' => 'Rezervasyonu Onayla',
    'reject' => 'Rezervasyonu Reddet',
    _ => 'Rezervasyonu İptal Et',
  };

  String get _sendLabel => switch (widget.action) {
    'approve' => 'Onayla',
    'reject' => 'Reddet',
    _ => 'İptal Et',
  };

  IconData get _icon => switch (widget.action) {
    'approve' => Icons.check_circle_outline_rounded,
    'reject' => Icons.block_rounded,
    _ => Icons.cancel_outlined,
  };

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
    popIfCurrent<ReservationDecisionResult>(context);
  }

  Future<void> _submit() async {
    if (_c.busy || _retry.locked || _c.gone) return;
    if (!validateForm(_formKey)) return;
    FocusScope.of(context).unfocus();
    final ok = await _c.submit(widget.action, _note.text);
    if (!mounted) return;
    if (ok) {
      _closing = true;
      popIfCurrent<ReservationDecisionResult>(context, _c.result);
      return;
    }
    final error = _c.lastError;
    if (error != null) {
      final limited = _retry.lockIfRateLimited(error, () {
        if (mounted) setState(() {});
      });
      if (limited) setState(() {});
    }
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
        builder: (context, _) => AppDialog(
          title: _title,
          subtitle: widget.reservation.areaLabel,
          icon: _icon,
          tone: widget.action == 'approve' ? AppTone.success : AppTone.danger,
          actions: [
            TextButton(
              key: const ValueKey<String>('rez_decision_close'),
              onPressed: _c.busy ? null : _close,
              child: Text(_c.gone ? 'Kapat' : 'Vazgeç'),
            ),
            if (!_c.gone && !_c.moduleClosed)
              ElevatedButton(
                key: const ValueKey<String>('rez_decision_send'),
                focusNode: _sendFocus,
                onPressed: (_c.busy || _retry.locked) ? null : () => unawaited(_submit()),
                child: Text(_c.busy ? 'Gönderiliyor...' : _sendLabel),
              ),
          ],
          child: _content(context),
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final r = widget.reservation;
    if (_c.moduleClosed) {
      return const InlineNotice(
        key: ValueKey<String>('rez_decision_module_off'),
        tone: AppTone.warning,
        message: 'Rezervasyon ve Konsiyerj bu site için kapalı.',
      );
    }
    final requester = r.requester?.name.trim() ?? '';
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_c.actionError != null) CrmFormError(message: _c.actionError!, announce: true),
          if (_c.gone)
            const InlineNotice(
              key: ValueKey<String>('rez_decision_gone'),
              message:
                  'Rezervasyon bulunamadı ya da erişiminiz yok. Listeyi yenileyip tekrar deneyin.',
            )
          else ...[
            Text(reservationWhenText(r), style: th.titleSmall),
            if (requester.isNotEmpty) ...[
              const SizedBox(height: AppSpace.xs),
              Text('Rezervasyonu yapan: $requester', style: th.bodyMedium),
            ],
            const SizedBox(height: AppSpace.lg),
            TextFormField(
              key: const ValueKey<String>('rez_decision_note'),
              controller: _note,
              enabled: !_c.busy,
              minLines: 2,
              maxLines: 5,
              maxLength: kReservationDecisionNoteMax,
              maxLengthEnforcement: MaxLengthEnforcement.none,
              buildCounter:
                  (context, {required currentLength, required isFocused, maxLength}) =>
                      reservationCounter(context, _note.text.runes.length, kReservationDecisionNoteMax),
              textCapitalization: TextCapitalization.sentences,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: _noteRequired ? 'Gerekçe' : 'Not (isteğe bağlı)',
                helperText: _noteRequired
                    ? 'Gerekçeyi rezervasyon sahibi görür.'
                    : 'Notu rezervasyon sahibi görür.',
                alignLabelWithHint: true,
              ),
              validator: (value) {
                final length = (value ?? '').trim().runes.length;
                if (_noteRequired && length < 1) return 'Gerekçe boş olamaz.';
                if (length > kReservationDecisionNoteMax) {
                  return 'En çok $kReservationDecisionNoteMax karakter olabilir.';
                }
                return null;
              },
            ),
          ],
        ],
      ),
    );
  }
}
