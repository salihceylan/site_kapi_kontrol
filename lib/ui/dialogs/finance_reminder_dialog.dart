import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MaxLengthEnforcement;
import 'package:site_kapi_kontrol/models/reminder_models.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/crm_confirm_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/large_dialog_parts.dart';
import 'package:site_kapi_kontrol/ui/helpers/a11y_announce.dart';
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_4b_access.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_errors.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_write_mixin.dart';
import 'package:site_kapi_kontrol/ui/helpers/form_validation.dart';
import 'package:site_kapi_kontrol/ui/helpers/money.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/helpers/retry_lock.dart';
import 'package:site_kapi_kontrol/ui/helpers/text_length.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_4b_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart' show filledToneStyle;

/// "Borç Hatırlat" penceresi (Platform Faz 4b, Ö6): ton seç + isteğe bağlı not -> ÖNİZLEME (kaç daire / kişi, kaç kişiye
/// tutarlı, hariç tutulma nedenleri, elden takip sayısı; ADRES VE AD GÖSTERİLMEZ) -> ayrı onay -> gönder.
///
/// - Hatırlatma, tanıtım içermeyen bilgilendirme e-postasıdır: konu satırında tutar / ad / daire YOKTUR; tutar yalnız
///   DOĞRULANMIŞ gerçek hesap e-postasına yazılır (yanlış kişiye borç sızmasın). Not düz metindir (en çok 300 karakter).
/// - Çift gönderim koruması: onay tek dokunuşla tek istek; `idempotency_key` imzaya (ton + not + özet) bağlıdır.
/// - Önizleme ile gönderim arasında veri değişirse 409 `PREVIEW_STALE`: önizleme otomatik yenilenir, eski ve yeni sayılar
///   yazılır, yenileme sürerken / başarısızken onay KAPALIDIR. SMTP yapılandırılmamışsa gönderim yapılamaz (sunucu da
///   reddeder: `EMAIL_NOT_CONFIGURED`); günde en çok bir çalıştırma (`REMINDER_DAILY_LIMIT`).
class FinanceReminderDialog extends StatefulWidget {
  const FinanceReminderDialog({super.key, required this.scope, this.onRefreshNeeded});

  final PeopleScope scope;
  final VoidCallback? onRefreshNeeded;

  static const int maxNoteLength = 300;

  static Future<FinanceWriteOutcome?> show(
    BuildContext context, {
    required PeopleScope scope,
    VoidCallback? onRefreshNeeded,
  }) {
    return showDialog<FinanceWriteOutcome>(
      context: context,
      barrierDismissible: false,
      builder: (_) => FinanceReminderDialog(scope: scope, onRefreshNeeded: onRefreshNeeded),
    );
  }

  @override
  State<FinanceReminderDialog> createState() => _FinanceReminderDialogState();
}

class _FinanceReminderDialogState extends State<FinanceReminderDialog> with FinanceWriteMixin, FinanceDiscardGuard {
  @override
  String get keyPrefix => 'remind';

  @override
  Object? get keyOwner => widget.scope.authService;

  @override
  bool get closeLocked => submitting || _previewing || _asking;

  // Kaydedilmemiş veri: yazılmış not ya da değiştirilmiş ton.
  @override
  bool get hasUnsavedChanges => _note.text.trim().isNotEmpty || _tone != ReminderTone.friendly;

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _note = TextEditingController();
  ReminderTone _tone = ReminderTone.friendly;
  ReminderPreview? _preview;

  // Önizlemenin alındığı ton + not: kullanıcı bunları değiştirirse önizleme eskir.
  ReminderTone? _previewTone;
  String _previewNote = '';
  bool _previewing = false;
  bool _stale = false;
  ReminderPreview? _staleFrom;
  bool _asking = false;
  String? _notice;
  String? _previewError;
  bool _previewBusy = false; // REPORT_BUSY (503): önizleme yuvası dolu -> "Tekrar Dene" (otomatik yeniden deneme YOK)
  int _previewToken = 0;
  final RetryLock _previewRetry = RetryLock();

  String get _noteText => _note.text.trim();
  bool get _inputsChanged => _preview != null && (_previewTone != _tone || _previewNote != _noteText);

  @override
  void dispose() {
    ++_previewToken;
    _previewRetry.dispose();
    disposeWrite();
    _note.dispose();
    super.dispose();
  }

  Future<void> _requestPreview({ReminderPreview? staleFrom}) async {
    if (_previewing || submitting || _previewRetry.locked) return;
    if (!validateForm(_formKey)) {
      setState(() => _previewError = kFixFieldsMessage);
      return;
    }
    final token = ++_previewToken;
    final tone = _tone;
    final note = _noteText;
    setState(() {
      _previewing = true;
      _previewError = null;
      _previewBusy = false;
      _notice = null;
    });
    try {
      final preview = await widget.scope.f4Call((api, t, s) => api.previewReminders(token: t, siteCode: s, tone: tone));
      if (!mounted || token != _previewToken) return;
      String? notice;
      if (staleFrom != null) {
        notice =
            'Veriler değişti, önizleme yenilendi. Yeni sayılar: ${preview.apartmentCount} daire, ${preview.personCount} kişi; '
            'önceki: ${staleFrom.apartmentCount} daire, ${staleFrom.personCount} kişi. Kontrol edip yeniden onaylayın.';
      }
      setState(() {
        _preview = preview;
        _previewTone = tone;
        _previewNote = note;
        _previewing = false;
        _stale = false;
        _staleFrom = null;
        _notice = notice;
      });
      announcePolite(
        context,
        notice ?? 'Önizleme hazır: ${preview.apartmentCount} daire, ${preview.personCount} kişi.',
      );
    } catch (e) {
      if (!mounted || token != _previewToken) return;
      final limited = _previewRetry.lockIfRateLimited(e, () {
        if (mounted) setState(() {});
      });
      setState(() {
        _previewing = false;
        _previewBusy = hasErrorCode(e, 'REPORT_BUSY');
        _previewError = limited
            ? RetryLock.messageFor(e)
            : financeMessageOf(e, 'Önizleme alınamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.');
      });
    }
  }

  void _back() {
    if (submitting || _previewing) return;
    ++_previewToken;
    setState(() {
      _preview = null;
      _stale = false;
      _staleFrom = null;
      _notice = null;
      _previewError = null;
      submitError = null;
    });
  }

  bool _canConfirm(ReminderPreview p) =>
      p.hasRecipients &&
      p.smtpConfigured &&
      p.blockers.isEmpty &&
      p.previewHash != null &&
      !_stale &&
      !_inputsChanged;

  String? _blockedReason(ReminderPreview p) {
    if (_previewing) return 'Önizleme yenileniyor.';
    if (_stale) return 'Önizleme eskidi. Önce "Önizlemeyi Yenile" düğmesine basın.';
    if (_inputsChanged) return 'Ton ya da not değişti. Önce "Önizlemeyi Yenile" düğmesine basın.';
    if (!p.smtpConfigured) return 'E-posta gönderimi yapılandırılmamış.';
    if (!p.hasRecipients) return 'Hatırlatma gönderilecek kimse yok.';
    if (p.blockers.isNotEmpty) return 'Gönderim şu an yapılamaz (aşağıdaki nedene bakın).';
    if (p.previewHash == null) return 'Önizleme özeti okunamadı. Önizlemeyi yenileyin.';
    return null;
  }

  Future<void> _confirm() async {
    final preview = _preview;
    if (preview == null || !_canConfirm(preview) || writeBlocked || _previewing || _asking) return;
    setState(() => _asking = true);
    final bool proceed;
    try {
      proceed = await confirmCrmAction(
        context,
        title: 'Hatırlatmaları gönder',
        message:
            '${preview.personCount} kişiye (${preview.apartmentCount} daire için) borç hatırlatma e-postası gönderilecek. '
            'Gönderim başlayınca geri alınamaz; yalnız henüz gönderilmemiş iletiler iptal edilebilir.',
        confirmLabel: 'Gönder',
        icon: Icons.send_rounded,
        tone: AppTone.warning,
      );
    } finally {
      if (mounted) setState(() => _asking = false);
    }
    if (!proceed || !mounted) return;
    final hash = preview.previewHash!;
    final tone = _previewTone ?? _tone;
    final note = _previewNote;
    await runWrite<ReminderSendResult>(
      signature: 'remind|${tone.apiValue}|$note|$hash',
      action: (key) => widget.scope.f4Call(
        (api, t, s) => api.sendReminders(
          token: t,
          siteCode: s,
          tone: tone,
          note: note,
          expectedHash: hash,
          expectedApartmentCount: preview.apartmentCount,
          expectedPersonCount: preview.personCount,
          idempotencyKey: key,
        ),
      ),
      onSuccess: (result) => popIfCurrent(
        context,
        FinanceWriteOutcome(
          result.created
              ? 'Hatırlatma gönderimi başlatıldı: ${preview.personCount} kişi, ${preview.apartmentCount} daire. İlerlemeyi Hatırlatma Geçmişi\'nden izleyebilirsiniz.'
              : 'Bu hatırlatma daha önce başlatılmıştı; mevcut çalıştırma gösteriliyor (çift gönderim yapılmadı).',
        ),
      ),
      failure: 'Hatırlatma gönderilemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
      onError: (e) {
        if (!hasErrorCode(e, 'PREVIEW_STALE')) {
          if (!financeOutcomeUncertain(e)) return false;
          // E-posta gönderimi: "kayıt" değil "gönderim" başlamış olabilir; aynı işlem anahtarıyla ikinci gönderim olmaz.
          submitError = financeWriteMessage(
            e,
            'Hatırlatma gönderilemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
            hint:
                'Gönderim başlamış olabilir. Aynı bilgilerle tekrar denerseniz ikinci kez gönderilmez; Hatırlatma Geçmişi\'nden de kontrol edebilirsiniz.',
          );
          return true;
        }
        _stale = true;
        _staleFrom = preview;
        widget.onRefreshNeeded?.call();
        unawaited(Future<void>.microtask(() => _requestPreview(staleFrom: preview)));
        return true;
      },
    );
  }

  void _notify() {
    if (!needsRefreshOnClose) return;
    needsRefreshOnClose = false;
    widget.onRefreshNeeded?.call();
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    final busy = submitting || _previewing || _asking;
    final canConfirm = preview != null && _canConfirm(preview) && !busy && !retry.locked;
    final blocked = preview == null ? null : _blockedReason(preview);
    Widget confirmButton = ElevatedButton(
      key: const ValueKey<String>('finance_reminder_confirm'),
      style: filledToneStyle(context),
      onPressed: canConfirm ? _confirm : null,
      child: Text(submitting ? 'Gönderiliyor...' : 'Onayla ve Gönder'),
    );
    if (preview != null && !canConfirm && blocked != null && !busy) {
      confirmButton = Semantics(
        container: true,
        excludeSemantics: true,
        button: true,
        enabled: false,
        label: 'Onayla ve Gönder',
        hint: blocked,
        child: Tooltip(message: blocked, excludeFromSemantics: true, child: confirmButton),
      );
    }
    return PopScope(
      canPop: canPopNow,
      onPopInvokedWithResult: (didPop, _) {
        handleBlockedPop(didPop);
        if (didPop) _notify();
      },
      child: AppDialog(
        title: 'Borç Hatırlat',
        subtitle: widget.scope.siteName.isEmpty ? null : widget.scope.siteName,
        icon: Icons.mark_email_read_rounded,
        actions: preview == null
            ? [
                TextButton(
                  onPressed: _previewing ? null : requestClose,
                  child: const Text('Vazgeç'),
                ),
                ElevatedButton(
                  key: const ValueKey<String>('finance_reminder_preview'),
                  onPressed: (_previewing || _previewRetry.locked) ? null : () => _requestPreview(),
                  child: Text(_previewing ? 'Hesaplanıyor...' : 'Önizle'),
                ),
              ]
            : [
                TextButton(
                  onPressed: busy ? null : requestClose,
                  child: const Text('Vazgeç'),
                ),
                TextButton(
                  key: const ValueKey<String>('finance_reminder_back'),
                  onPressed: busy ? null : _back,
                  child: const Text('Geri'),
                ),
                confirmButton,
              ],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (submitError != null) FinanceSubmitError(message: submitError!),
            if (_previewError != null)
              FinanceSubmitError(
                message: _previewError!,
                action: _previewBusy
                    ? Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          key: const ValueKey<String>('finance_reminder_preview_retry'),
                          onPressed: (_previewing || _previewRetry.locked)
                              ? null
                              : () => _requestPreview(staleFrom: _stale ? _staleFrom : null),
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: const Text('Tekrar Dene'),
                          style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                        ),
                      )
                    : null,
              ),
            // Önizleme sırasında form AĞAÇTA kalır (girdiler korunur) ama görünmez ve odaklanamaz.
            ExcludeFocus(
              excluding: preview != null,
              child: Offstage(offstage: preview != null, child: _buildForm(context)),
            ),
            if (preview != null) _buildPreview(context, preview, blocked),
          ],
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Vadesi geçmiş borcu olan dairelerin sorumlularına bilgilendirme e-postası gönderilir. İleti tanıtım içermez; '
            'konu satırında tutar, ad ya da daire yazmaz. Önce önizleme gösterilir.',
            style: th.bodyMedium,
          ),
          const SizedBox(height: AppSpace.md),
          const FinanceGroupTitle('Ton'),
          const SizedBox(height: AppSpace.sm),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: [
              for (final tone in ReminderTone.values)
                ChoiceChip(
                  key: ValueKey<String>('finance_reminder_tone_${tone.apiValue}'),
                  label: Text(tone.label),
                  selected: _tone == tone,
                  onSelected: (submitting || _previewing) ? null : (_) => setState(() => _tone = tone),
                ),
            ],
          ),
          const SizedBox(height: AppSpace.xs),
          Text(_tone.description, style: th.bodySmall?.copyWith(color: p.textSecondary)),
          const SizedBox(height: AppSpace.md),
          TextFormField(
            key: const ValueKey<String>('finance_reminder_note'),
            controller: _note,
            enabled: !_previewing && !submitting,
            minLines: 2,
            maxLines: 4,
            maxLength: FinanceReminderDialog.maxNoteLength,
            maxLengthEnforcement: MaxLengthEnforcement.none,
            buildCounter: (context, {required currentLength, required isFocused, maxLength}) =>
                characterCounter(context, trimmedCodePoints(_note.text), FinanceReminderDialog.maxNoteLength),
            textCapitalization: TextCapitalization.sentences,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Ek not (isteğe bağlı)',
              alignLabelWithHint: true,
              prefixIcon: Icon(Icons.notes_rounded),
              helperText:
                  'Düz metin olarak iletinin sonuna eklenir; bağlantı, alan adı ya da e-posta adresi yazılamaz. İkna, baskı ya da tehdit dili kullanmayın.',
              helperMaxLines: 3,
            ),
            validator: (value) {
              if (trimmedCodePoints(value ?? '') > FinanceReminderDialog.maxNoteLength) {
                return 'Not en çok ${FinanceReminderDialog.maxNoteLength} karakter olabilir.';
              }
              if (reminderNoteHasLink(value ?? '')) return 'Not bağlantı, alan adı ya da e-posta adresi içeremez.';
              return null;
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPreview(BuildContext context, ReminderPreview preview, String? blocked) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final summary =
        'Önizleme. ${preview.apartmentCount} daire. ${preview.personCount} kişi. ${preview.withAmountCount} kişiye tutarlı ileti, '
        '${preview.withoutAmountCount} kişiye tutarsız ileti.';
    final showBlockedLine = blocked != null && !_previewing && (_stale || _inputsChanged);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_notice != null) ...[
          InlineNotice(key: const ValueKey<String>('finance_reminder_notice'), tone: AppTone.warning, message: _notice!),
          const SizedBox(height: AppSpace.md),
        ],
        DialogPanel(
          key: const ValueKey<String>('finance_reminder_summary'),
          child: Semantics(
            container: true,
            label: summary,
            child: ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const DialogSectionTitle(icon: Icons.fact_check_rounded, title: 'Önizleme'),
                  const SizedBox(height: AppSpace.sm),
                  Text('${preview.apartmentCount} daire', key: const ValueKey<String>('finance_reminder_apartments'), style: th.titleMedium),
                  Text('${preview.personCount} kişi', key: const ValueKey<String>('finance_reminder_people'), style: th.titleMedium),
                  Text(
                    '${preview.withAmountCount} kişiye tutarlı, ${preview.withoutAmountCount} kişiye tutarsız ileti gider.',
                    key: const ValueKey<String>('finance_reminder_amounts'),
                    style: th.bodyMedium,
                  ),
                  if (preview.totalOverdueMinor != null)
                    Text(
                      'Toplam vadesi geçmiş: ${formatMinor(preview.totalOverdueMinor!)}',
                      style: th.bodySmall?.copyWith(color: p.textSecondary),
                    ),
                ],
              ),
            ),
          ),
        ),
        if (_stale && !_previewing || _inputsChanged && !_previewing) ...[
          const SizedBox(height: AppSpace.md),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: PrimaryActionButton(
              key: const ValueKey<String>('finance_reminder_refresh'),
              label: 'Önizlemeyi Yenile',
              icon: Icons.refresh_rounded,
              variant: AppButtonVariant.tonal,
              expand: false,
              onPressed: (submitting || _previewRetry.locked) ? null : () => _requestPreview(staleFrom: _stale ? _staleFrom : null),
            ),
          ),
        ],
        if (_previewing) ...[
          const SizedBox(height: AppSpace.md),
          const DialogLoadingNote(text: 'Önizleme yenileniyor...'),
        ],
        if (showBlockedLine) ...[
          const SizedBox(height: AppSpace.sm),
          Text(
            'Onaylamak için: $blocked',
            key: const ValueKey<String>('finance_reminder_blocked_reason'),
            style: th.bodySmall?.copyWith(color: p.textSecondary, fontWeight: FontWeight.w600),
          ),
        ],
        if (!preview.smtpConfigured) ...[
          const SizedBox(height: AppSpace.md),
          const InlineNotice(
            key: ValueKey<String>('finance_reminder_no_smtp'),
            tone: AppTone.warning,
            message: 'E-posta gönderimi bu sunucuda yapılandırılmamış; hatırlatma gönderilemez.',
          ),
        ],
        for (final code in preview.blockers) ...[
          const SizedBox(height: AppSpace.md),
          InlineNotice(
            key: ValueKey<String>('finance_reminder_blocker_$code'),
            tone: AppTone.warning,
            message: _blockerText(code),
          ),
        ],
        if (!preview.hasRecipients && preview.smtpConfigured && preview.blockers.isEmpty) ...[
          const SizedBox(height: AppSpace.md),
          const InlineNotice(
            key: ValueKey<String>('finance_reminder_no_recipients'),
            tone: AppTone.info,
            message: 'Şu an hatırlatma gönderilecek kimse yok. Eşik ve aralık ayarlarını Finans Ayarları\'ndan gözden geçirebilirsiniz.',
          ),
        ],
        const SizedBox(height: AppSpace.md),
        _breakdown(context, preview),
        if (preview.sampleApartments.isNotEmpty) ...[
          const SizedBox(height: AppSpace.md),
          Semantics(header: true, container: true, child: Text('Örnek daireler', style: th.titleSmall)),
          const SizedBox(height: AppSpace.xs),
          Text(
            preview.sampleApartments.join(', ') + (preview.apartmentCount > preview.sampleApartments.length ? ' ...' : ''),
            key: const ValueKey<String>('finance_reminder_samples'),
            style: th.bodySmall,
          ),
        ],
      ],
    );
  }

  Widget _breakdown(BuildContext context, ReminderPreview preview) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final rows = <(String, int)>[
      ('Adresi olmayan kişi', preview.noAddressCount),
      ('E-posta tercihi kapalı / abonelikten çıkmış kişi', preview.skippedPrefCount),
      ('Aynı adrese zaten gidecek (tekrar)', preview.duplicateCount),
      ('Yedi günlük adres sınırına takılan', preview.cappedCount),
      ('Tutarı eşiğin altında kalan daire', preview.excluded.amount),
      ('Gecikme günü eşiğin altında kalan daire', preview.excluded.days),
      ('Son hatırlatmadan beri yeterli süre geçmemiş daire', preview.excluded.interval),
      ('Ardışık hatırlatma sınırına ulaşan daire', preview.excluded.consecutive),
      ('Muaf listesindeki daire', preview.excluded.exclusion),
      ('Alıcısı bulunamayan daire', preview.excluded.noRecipient),
    ].where((r) => r.$2 > 0).toList();
    return DialogPanel(
      key: const ValueKey<String>('finance_reminder_breakdown'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(header: true, container: true, child: Text('Gönderilmeyenler', style: th.titleSmall)),
          const SizedBox(height: AppSpace.xs),
          if (rows.isEmpty && preview.handFollowUpCount == 0)
            Text('Hariç tutulan yok.', style: th.bodySmall?.copyWith(color: p.textSecondary))
          else
            for (final r in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text('${r.$1}: ${r.$2}', style: th.bodySmall),
              ),
          if (preview.handFollowUpCount > 0) ...[
            const SizedBox(height: AppSpace.xs),
            Text(
              'Elden takip: ${preview.handFollowUpCount} daire ardışık hatırlatma sınırına ulaştı; e-posta gitmez, '
              'yönetimce elden takip edilmelidir.'
              '${preview.handFollowUpApartments.isEmpty ? '' : ' (${preview.handFollowUpApartments.join(', ')}${preview.handFollowUpCount > preview.handFollowUpApartments.length ? ' ...' : ''})'}',
              key: const ValueKey<String>('finance_reminder_hand_follow_up'),
              style: th.bodySmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ],
      ),
    );
  }

  String _blockerText(String code) {
    switch (code) {
      case 'REMINDERS_DISABLED':
        return 'Borç hatırlatma bu site için kapalı. Finans Ayarları\'ndan açın.';
      case 'REMINDER_DAILY_LIMIT':
        return 'Bugün zaten bir hatırlatma gönderildi. Günde en çok bir çalıştırma yapılabilir.';
      case 'EMAIL_NOT_CONFIGURED':
        return 'E-posta gönderimi yapılandırılmamış; hatırlatma gönderilemez.';
      case 'NO_REMINDER_RECIPIENTS':
        return 'Hatırlatma gönderilecek kimse yok.';
      case 'LEGAL_APPROVAL_REQUIRED':
        return 'Hukuk onayı bekleniyor. Borç hatırlatma onay tamamlanana dek kullanılamaz.';
      default:
        return 'Hatırlatma şu an gönderilemez.';
    }
  }
}
