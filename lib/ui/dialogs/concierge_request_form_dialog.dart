// Yeni konsiyerj talebi formu (docs/PLATFORM_REZERVASYON.md `POST /app/concierge-requests`): kategori, not ve isteğe
// bağlı istenen zaman (İstanbul saatiyle gün + saat; en çok 90 gün sonrası). `diger` kategorisinde not zorunludur.
//
// Çift gönderim: düğme gönderim sürerken kapalıdır; gönderim sürerken geri tuşu pencereyi kapatmaz. Aynı veriyle
// yeniden gönderimde servis AYNI `idempotency_key`i kullanır (yanıtı kaybolan istek çift talep açmaz); veri değişince
// anahtar yenilenir. Hata pencerenin içinde kalır, metinler korunur; 429'da düğme `Retry-After` süresince
// kilitlenir. Not yazılmışsa yanlışlıkla kapanırken onay istenir.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MaxLengthEnforcement;
import 'package:site_kapi_kontrol/models/reservation_models.dart';
import 'package:site_kapi_kontrol/services/reservation_api.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/date_input.dart' show formatDateField;
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/helpers/form_validation.dart';
import 'package:site_kapi_kontrol/ui/helpers/istanbul_time.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart'
    show crmMessageOf;
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/helpers/retry_lock.dart';
import 'package:site_kapi_kontrol/ui/widgets/crm_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/reservation_parts.dart';

const int _kMaxDaysAhead = 90;

class ConciergeRequestFormDialog extends StatefulWidget {
  const ConciergeRequestFormDialog({
    super.key,
    required this.service,
    required this.sites,
    this.initialSiteCode,
    this.clock,
  });

  final ReservationService service;

  /// Talep açılabilecek (modül açık) siteler; en az bir tane.
  final List<PeopleSite> sites;
  final int? initialSiteCode;

  /// Test düzeneği: şimdiki an (varsayılan [DateTime.now]).
  final DateTime Function()? clock;

  /// Başarıda sunucunun döndürdüğü kayıtla kapanır; vazgeçilirse null.
  static Future<ConciergeCreateResult?> show(
    BuildContext context, {
    required ReservationService service,
    required List<PeopleSite> sites,
    int? initialSiteCode,
    DateTime Function()? clock,
  }) {
    return showDialog<ConciergeCreateResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ConciergeRequestFormDialog(
        service: service,
        sites: sites,
        initialSiteCode: initialSiteCode,
        clock: clock,
      ),
    );
  }

  @override
  State<ConciergeRequestFormDialog> createState() =>
      _ConciergeRequestFormDialogState();
}

class _ConciergeRequestFormDialogState
    extends State<ConciergeRequestFormDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final GlobalKey _whenKey = GlobalKey();
  final FocusNode _sendFocus = FocusNode(debugLabel: 'cnc_form_send');
  final RetryLock _retry = RetryLock();
  final TextEditingController _note = TextEditingController();

  late int _siteCode = _initialSite();
  ConciergeCategory _category = ConciergeCategory.paketTeslim;
  DateTime? _date;
  TimeOfDay? _time;
  String? _whenError;

  bool _submitting = false;
  bool _closing = false;
  String? _error;

  int _initialSite() {
    final wanted = widget.initialSiteCode;
    if (wanted != null && widget.sites.any((s) => s.code == wanted)) {
      return wanted;
    }
    return widget.sites.first.code;
  }

  DateTime _now() => (widget.clock?.call() ?? DateTime.now()).toUtc();

  /// İstanbul takvimine göre bugün (yalnız gün).
  DateTime _today() {
    final wall = istanbulNow(_now());
    return DateTime(wall.year, wall.month, wall.day);
  }

  @override
  void dispose() {
    _retry.dispose();
    _sendFocus.dispose();
    _note.dispose();
    super.dispose();
  }

  bool get _dirty => _note.text.trim().isNotEmpty;

  /// Seçilen gün + saat İstanbul saatidir; gönderilen an UTC'dir.
  DateTime? get _requestedFor {
    final date = _date;
    final time = _time;
    if (date == null || time == null) return null;
    return istanbulInstantOf(date, time.hour, time.minute);
  }

  Future<void> _pickDate() async {
    final today = _today();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? today,
      firstDate: today,
      lastDate: today.add(const Duration(days: _kMaxDaysAhead)),
      helpText: 'İstenen gün',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _date = DateTime(picked.year, picked.month, picked.day);
      _whenError = null;
    });
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time ?? const TimeOfDay(hour: 9, minute: 0),
      helpText: 'İstenen saat',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _time = picked;
      _whenError = null;
    });
  }

  void _clearWhen() {
    setState(() {
      _date = null;
      _time = null;
      _whenError = null;
    });
  }

  bool _validateWhen() {
    String? error;
    final requested = _requestedFor;
    if ((_date == null) != (_time == null)) {
      error =
          'İstenen zaman için hem gün hem saat seçin ya da ikisini de boş bırakın.';
    } else if (requested != null) {
      final now = _now();
      if (requested.isBefore(now)) {
        error = 'İstenen zaman geçmişte olamaz.';
      } else if (requested.isAfter(now.add(const Duration(days: _kMaxDaysAhead)))) {
        error = 'İstenen zaman en fazla $_kMaxDaysAhead gün sonrası olabilir.';
      }
    }
    setState(() => _whenError = error);
    return error == null;
  }

  bool _revealWhen() {
    final context = _whenKey.currentContext;
    if (_whenError != null && context != null) {
      Scrollable.ensureVisible(context, duration: Duration.zero, alignment: 0.1);
      return true;
    }
    return false;
  }

  Future<void> _submit() async {
    if (_submitting || _retry.locked) return;
    if (!validateForm(
      _formKey,
      validateExtra: _validateWhen,
      revealExtra: _revealWhen,
    )) {
      setState(() => _error = kFixFieldsMessage);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });
    final request = ConciergeCreateRequest(
      siteCode: _siteCode,
      category: _category,
      note: _note.text,
      requestedFor: _requestedFor,
    );
    try {
      final result = await widget.service.createRequest(request);
      if (!mounted) return;
      _closing = true;
      popIfCurrent<ConciergeCreateResult>(context, result);
    } catch (e) {
      if (!mounted) return;
      _retry.lockIfRateLimited(e, () {
        if (mounted) setState(() {});
      });
      setState(() {
        _submitting = false;
        _error = crmMessageOf(
          e,
          'Talep gönderilemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
        );
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _sendFocus.requestFocus();
      });
    }
  }

  Future<void> _requestClose() async {
    if (_closing || _submitting) return;
    if (_dirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AppDialog(
          title: 'Talep silinsin mi?',
          icon: Icons.help_outline_rounded,
          tone: AppTone.warning,
          actions: [
            TextButton(
              key: const ValueKey<String>('cnc_form_keep'),
              onPressed: () => popIfCurrent(dialogContext, false),
              child: const Text('Yazmaya Dön'),
            ),
            ElevatedButton(
              key: const ValueKey<String>('cnc_form_discard'),
              onPressed: () => popIfCurrent(dialogContext, true),
              child: const Text('Vazgeç ve Kapat'),
            ),
          ],
          child: Text(
            'Yazdıklarınız gönderilmedi.',
            style: Theme.of(dialogContext).textTheme.bodyMedium,
          ),
        ),
      );
      if (discard != true || !mounted) return;
    }
    _closing = true;
    popIfCurrent<ConciergeCreateResult>(context);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final date = _date;
    final time = _time;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_requestClose());
      },
      child: AppDialog(
        title: 'Yeni Konsiyerj Talebi',
        subtitle: 'Paket, misafir hazırlığı, temizlik, taşıma',
        icon: Icons.room_service_rounded,
        actions: [
          TextButton(
            key: const ValueKey<String>('cnc_form_close'),
            onPressed: _submitting ? null : () => unawaited(_requestClose()),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            key: const ValueKey<String>('cnc_form_send'),
            focusNode: _sendFocus,
            onPressed: (_submitting || _retry.locked) ? null : _submit,
            child: Text(_submitting ? 'Gönderiliyor...' : 'Gönder'),
          ),
        ],
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) CrmFormError(message: _error!, announce: true),
              if (widget.sites.length > 1) ...[
                DropdownButtonFormField<int>(
                  key: ValueKey<String>('cnc_form_site_$_siteCode'),
                  isExpanded: true,
                  initialValue: _siteCode,
                  dropdownColor: p.surface,
                  style: th.bodyMedium?.copyWith(color: p.text),
                  decoration: const InputDecoration(
                    labelText: 'Site',
                    prefixIcon: Icon(Icons.apartment_rounded),
                  ),
                  items: [
                    for (final site in widget.sites)
                      DropdownMenuItem<int>(
                        value: site.code,
                        child: Text(
                          site.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: _submitting
                      ? null
                      : (value) {
                          if (value != null) setState(() => _siteCode = value);
                        },
                ),
                const SizedBox(height: AppSpace.lg),
              ],
              DropdownButtonFormField<ConciergeCategory>(
                key: const ValueKey<String>('cnc_form_category'),
                isExpanded: true,
                initialValue: _category,
                dropdownColor: p.surface,
                style: th.bodyMedium?.copyWith(color: p.text),
                decoration: const InputDecoration(
                  labelText: 'Kategori',
                  prefixIcon: Icon(Icons.category_rounded),
                ),
                items: [
                  for (final category in ConciergeCategory.values)
                    DropdownMenuItem<ConciergeCategory>(
                      value: category,
                      child: Text(
                        category.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: _submitting
                    ? null
                    : (value) {
                        if (value != null) setState(() => _category = value);
                      },
              ),
              const SizedBox(height: AppSpace.lg),
              TextFormField(
                key: const ValueKey<String>('cnc_form_note'),
                controller: _note,
                enabled: !_submitting,
                minLines: 2,
                maxLines: 6,
                maxLength: kConciergeNoteMax,
                maxLengthEnforcement: MaxLengthEnforcement.none,
                buildCounter:
                    (context, {required currentLength, required isFocused, maxLength}) =>
                        reservationCounter(context, _note.text.runes.length, kConciergeNoteMax),
                keyboardType: TextInputType.multiline,
                textCapitalization: TextCapitalization.sentences,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: _category == ConciergeCategory.diger
                      ? 'Açıklama'
                      : 'Not (isteğe bağlı)',
                  hintText: 'Örn. kapıda bekleyen paket, 2. kat',
                  alignLabelWithHint: true,
                ),
                validator: (value) {
                  final length = (value ?? '').trim().runes.length;
                  if (_category == ConciergeCategory.diger && length < 1) {
                    return 'Diğer talepler için açıklama yazın.';
                  }
                  if (length > kConciergeNoteMax) {
                    return 'Not en çok $kConciergeNoteMax karakter olabilir.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: AppSpace.lg),
              KeyedSubtree(
                key: _whenKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Semantics(
                      header: true,
                      child: Text('İstenen zaman (isteğe bağlı)', style: th.titleSmall),
                    ),
                    const SizedBox(height: AppSpace.xs),
                    Text(
                      'İşin yapılmasını istediğiniz gün ve saat (İstanbul saati).',
                      style: th.bodySmall?.copyWith(color: p.textSecondary),
                    ),
                    const SizedBox(height: AppSpace.sm),
                    Wrap(
                      spacing: AppSpace.sm,
                      runSpacing: AppSpace.sm,
                      children: [
                        OutlinedButton.icon(
                          key: const ValueKey<String>('cnc_form_date'),
                          onPressed: _submitting ? null : () => unawaited(_pickDate()),
                          icon: const Icon(Icons.event_rounded, size: 18),
                          label: Text(date == null ? 'Gün seç' : formatDateField(date)),
                        ),
                        OutlinedButton.icon(
                          key: const ValueKey<String>('cnc_form_time'),
                          onPressed: _submitting ? null : () => unawaited(_pickTime()),
                          icon: const Icon(Icons.schedule_rounded, size: 18),
                          label: Text(
                            time == null
                                ? 'Saat seç'
                                : '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                          ),
                        ),
                        if (date != null || time != null)
                          TextButton(
                            key: const ValueKey<String>('cnc_form_clear_when'),
                            onPressed: _submitting ? null : _clearWhen,
                            child: const Text('Temizle'),
                          ),
                      ],
                    ),
                    if (_whenError != null) ...[
                      const SizedBox(height: AppSpace.xs),
                      Text(
                        _whenError!,
                        key: const ValueKey<String>('cnc_form_when_error'),
                        style: th.bodySmall?.copyWith(color: AppTone.danger.ink(p)),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
