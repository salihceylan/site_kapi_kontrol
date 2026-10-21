import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/finance.dart';
import 'package:site_kapi_kontrol/models/finance_4b.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/large_dialog_parts.dart';
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_4b_access.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_errors.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_write_mixin.dart';
import 'package:site_kapi_kontrol/ui/helpers/form_validation.dart';
import 'package:site_kapi_kontrol/ui/helpers/istanbul_time.dart';
import 'package:site_kapi_kontrol/ui/helpers/money.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/widgets/crm_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_4b_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_settings_controller.dart';
import 'package:site_kapi_kontrol/ui/widgets/money_field.dart';

/// Finans ayarları penceresi (Platform Faz 4b): makbuz otomatik düzenleme, gecikme tazminatı ve borç hatırlatma ayarları.
/// Yalnız yönetici / süper kullanıcı değiştirir (kurul ayarları görmek için pencereyi açamaz).
///
/// - Kaydetme KISMİDİR ve `expected_settings_version` ile yapılır; başka biri ayarı bu arada değiştirdiyse sunucu 409
///   `SETTINGS_STALE` döner: güncel ayarlar yüklenir, form yeniden kurulur ve kullanıcı değişikliğini yeniden gözden
///   geçirip kaydeder (eski sürümle üstüne yazılmaz).
/// - Gecikme tazminatı ve hatırlatma, sistem bayrağı `finance.legal_ok` KAPALIYKEN açılamaz ("Hukuk onayı bekleniyor").
/// - Tazminat oranı sistem sınırını ([LateFeeSettings.maxRateBp], %5,00) aşamaz; oran / yöntem / ek gün yalnız SONRAKİ
///   hesaplamaları etkiler; başlangıç ayı yalnız hiç aktif çalıştırma yokken değişir.
class FinanceSettingsDialog extends StatefulWidget {
  const FinanceSettingsDialog({super.key, required this.scope, required this.controller, this.now});

  final PeopleScope scope;
  final FinanceSettingsController controller;
  final DateTime Function()? now;

  static Future<bool> show(
    BuildContext context, {
    required PeopleScope scope,
    required FinanceSettingsController controller,
    DateTime Function()? now,
  }) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => FinanceSettingsDialog(scope: scope, controller: controller, now: now),
    );
    return saved ?? false;
  }

  @override
  State<FinanceSettingsDialog> createState() => _FinanceSettingsDialogState();
}

class _FinanceSettingsDialogState extends State<FinanceSettingsDialog> with FinanceWriteMixin, FinanceDiscardGuard {
  @override
  String get keyPrefix => 'fset';

  @override
  bool get closeLocked => submitting;

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late FinanceSettings _base;
  String? _notice;

  late bool _autoIssue;
  late bool _lateEnabled;
  late LateFeeMethod _method;
  FinancePeriod? _start;
  final TextEditingController _rate = TextEditingController();
  final TextEditingController _grace = TextEditingController();
  late bool _remindersEnabled;
  final TextEditingController _minOverdue = TextEditingController();
  final TextEditingController _minDays = TextEditingController();
  final TextEditingController _minInterval = TextEditingController();
  final TextEditingController _maxConsecutive = TextEditingController();
  String? _startError;

  FinancePeriod get _currentPeriod => FinancePeriod.of(istanbulNow(widget.now?.call()));

  @override
  void initState() {
    super.initState();
    _base = widget.controller.settings!;
    _fill(_base);
  }

  void _fill(FinanceSettings s) {
    _autoIssue = s.receiptAutoIssue;
    _lateEnabled = s.lateFee.enabled;
    _method = s.lateFee.method;
    _start = s.lateFee.startPeriod;
    _rate.text = _rateText(s.lateFee.rateBp);
    _grace.text = '${s.lateFee.graceDays}';
    _remindersEnabled = s.reminders.enabled;
    _minOverdue.text = formatMinor(s.reminders.minOverdueMinor, symbol: false);
    _minDays.text = '${s.reminders.minDaysOverdue}';
    _minInterval.text = '${s.reminders.minIntervalDays}';
    _maxConsecutive.text = '${s.reminders.maxConsecutive}';
  }

  /// 500 -> "5,00"; 450 -> "4,50".
  static String _rateText(int bp) => '${bp ~/ 100},${(bp % 100).toString().padLeft(2, '0')}';

  /// "4,5" / "4.50" / "5" -> baz puan (tamsayı); geçersizse null.
  static int? parseRateBp(String? text) {
    final match = RegExp(r'^(\d{1,2})(?:[.,](\d{1,2}))?$').firstMatch((text ?? '').trim());
    if (match == null) return null;
    final whole = int.parse(match.group(1)!);
    final frac = int.parse((match.group(2) ?? '').padRight(2, '0').substring(0, 2).padLeft(2, '0'));
    return whole * 100 + frac;
  }

  @override
  void dispose() {
    disposeWrite();
    _rate.dispose();
    _grace.dispose();
    _minOverdue.dispose();
    _minDays.dispose();
    _minInterval.dispose();
    _maxConsecutive.dispose();
    super.dispose();
  }

  bool get _startEditable => _base.lateFee.voidableRunId == null;
  bool get _lateLegalBlocked => _base.lateFee.legalOk == false;
  bool get _reminderLegalBlocked => _base.reminders.legalOk == false;

  int? _intOrNull(TextEditingController c) => int.tryParse(c.text.trim());

  FinanceSettingsPatch _patch() {
    final late = _base.lateFee;
    final rem = _base.reminders;
    final rate = parseRateBp(_rate.text);
    final grace = _intOrNull(_grace);
    final minOverdue = parseMoney(_minOverdue.text, allowZero: true).minor;
    final days = _intOrNull(_minDays);
    final interval = _intOrNull(_minInterval);
    final consecutive = _intOrNull(_maxConsecutive);
    return FinanceSettingsPatch(
      receiptAutoIssue: _autoIssue != _base.receiptAutoIssue ? _autoIssue : null,
      lateFeeEnabled: _lateEnabled != late.enabled ? _lateEnabled : null,
      lateFeeRateBp: rate != null && rate != late.rateBp ? rate : null,
      lateFeeMethod: _method != late.method ? _method : null,
      lateFeeGraceDays: grace != null && grace != late.graceDays ? grace : null,
      lateFeeStartPeriod: _startEditable && _start != null && _start != late.startPeriod ? _start : null,
      remindersEnabled: _remindersEnabled != rem.enabled ? _remindersEnabled : null,
      reminderMinOverdueMinor: minOverdue != null && minOverdue != rem.minOverdueMinor ? minOverdue : null,
      reminderMinDaysOverdue: days != null && days != rem.minDaysOverdue ? days : null,
      reminderMinIntervalDays: interval != null && interval != rem.minIntervalDays ? interval : null,
      reminderMaxConsecutive: consecutive != null && consecutive != rem.maxConsecutive ? consecutive : null,
    );
  }

  Future<void> _reloadAfterStale() async {
    await widget.controller.load();
    final fresh = widget.controller.settings;
    if (!mounted) return;
    if (fresh == null) {
      // Güncel ayarlar okunamadı: sessiz kalınmaz (eski sürümle kaydetmek yine 409 verir; kullanıcı nedenini bilsin).
      setState(
        () => submitError =
            'Ayarlar başka biri tarafından değiştirilmiş ve güncel ayarlar şu an yüklenemedi. İnternet bağlantınızı kontrol edip pencereyi kapatıp yeniden açın.',
      );
      return;
    }
    setState(() {
      _base = fresh;
      _fill(fresh);
      _notice = 'Ayarlar başka biri tarafından değiştirilmişti. Güncel ayarlar yüklendi; değişikliğinizi yeniden gözden geçirip kaydedin.';
    });
  }

  Future<void> _submit() async {
    if (writeBlocked) return;
    final startMissing = _lateEnabled && _start == null && _base.lateFee.startPeriod == null;
    final ok = validateForm(_formKey, validateExtra: () {
      setState(() => _startError = startMissing ? 'Tazminat için ilk hesaplanacak ayı (başlangıç ayı) seçin.' : null);
      return !startMissing;
    });
    if (!ok) {
      setState(() => submitError = kFixFieldsMessage);
      return;
    }
    if (_remindersEnabled) {
      // Sunucu sınırı: en düşük borç eşiği 1,00 ₺ (100 kuruş).
      final minor = parseMoney(_minOverdue.text, allowZero: true).minor;
      if (minor != null && minor < 100) {
        setState(() => submitError = 'En az vadesi geçmiş tutar en az 1,00 ₺ olmalıdır.');
        return;
      }
    }
    final patch = _patch();
    if (patch.isEmpty) {
      setState(() => submitError = 'Değişiklik yapmadınız.');
      return;
    }
    final version = _base.settingsVersion;
    final body = patch.toJson(version).toString();
    await runWrite<FinanceSettings?>(
      signature: 'settings|$version|$body',
      action: (_) => widget.scope.f4Call(
        (api, t, s) => api.updateSettings(token: t, siteCode: s, patch: patch, expectedVersion: version),
      ),
      onSuccess: (updated) async {
        if (updated != null) {
          widget.controller.apply(updated);
        } else {
          await widget.controller.load();
        }
        if (mounted) popIfCurrent(context, true);
      },
      failure: 'Ayarlar kaydedilemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
      onError: (e) {
        if (!hasErrorCode(e, 'SETTINGS_STALE')) {
          if (!financeOutcomeUncertain(e)) return false;
          // Ayar kaydı "kayıt oluşmuş olabilir" değil: değer yazılmış olabilir (çift kayıt kavramı yok).
          submitError = financeWriteMessage(
            e,
            'Ayarlar kaydedilemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
            hint: 'Ayarlar kaydedilmiş olabilir. Tekrar kaydetmeyi deneyebilir ya da pencereyi kapatıp ayarları kontrol edebilirsiniz.',
          );
          return true;
        }
        unawaited(_reloadAfterStale());
        submitError = null;
        return true;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final late = _base.lateFee;
    final maxRate = late.maxRateBp;
    return PopScope(
      canPop: canPopNow,
      onPopInvokedWithResult: (didPop, _) {
        handleBlockedPop(didPop);
        // Kayıt sonucu belirsiz kaldıysa (zaman aşımı vb.) ayar yazılmış olabilir: ekran sunucudan tazelenir.
        if (didPop && needsRefreshOnClose) {
          needsRefreshOnClose = false;
          unawaited(widget.controller.load());
        }
      },
      child: AppDialog(
        title: 'Finans Ayarları',
        subtitle: widget.scope.siteName.isEmpty ? null : widget.scope.siteName,
        icon: Icons.tune_rounded,
        actions: [
          TextButton(
            onPressed: submitting ? null : requestClose,
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            key: const ValueKey<String>('finance_settings_submit'),
            onPressed: writeBlocked ? null : _submit,
            child: Text(submitting ? 'Kaydediliyor...' : 'Kaydet'),
          ),
        ],
        child: Form(
          key: _formKey,
          onChanged: markDirty,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (submitError != null) FinanceSubmitError(message: submitError!),
              if (_notice != null) ...[
                InlineNotice(key: const ValueKey<String>('finance_settings_stale'), tone: AppTone.warning, message: _notice!),
                const SizedBox(height: AppSpace.md),
              ],
              // --- Makbuz ---
              const DialogSectionTitle(icon: Icons.receipt_long_rounded, title: 'Makbuz'),
              Material(
                type: MaterialType.transparency,
                child: SwitchListTile(
                  key: const ValueKey<String>('finance_settings_auto_receipt'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Tahsilatta makbuz otomatik düzenlensin'),
                  subtitle: const Text('Kapalıyken makbuz, ekstreden elle düzenlenir.'),
                  value: _autoIssue,
                  onChanged: submitting
                      ? null
                      : (v) => setState(() {
                          markDirty();
                          _autoIssue = v;
                        }),
                ),
              ),
              const Divider(),
              // --- Gecikme tazminatı ---
              const DialogSectionTitle(icon: Icons.gavel_rounded, title: 'Gecikme tazminatı', tone: AppTone.warning),
              if (_lateLegalBlocked)
                const Padding(
                  padding: EdgeInsets.only(top: AppSpace.sm),
                  child: InlineNotice(
                    key: ValueKey<String>('finance_settings_late_legal'),
                    tone: AppTone.warning,
                    message: 'Hukuk onayı bekleniyor. Gecikme tazminatı onay tamamlanana dek açılamaz.',
                  ),
                ),
              Material(
                type: MaterialType.transparency,
                child: SwitchListTile(
                  key: const ValueKey<String>('finance_settings_late_enabled'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Gecikme tazminatı kullanılsın'),
                  subtitle: const Text('Otomatik değildir: her ay önizlenir ve onaylanır.'),
                  value: _lateEnabled,
                  onChanged: (submitting || (_lateLegalBlocked && !late.enabled))
                      ? null
                      : (v) => setState(() {
                          markDirty();
                          _lateEnabled = v;
                        }),
                ),
              ),
              if (_lateEnabled) ...[
                const SizedBox(height: AppSpace.sm),
                TextFormField(
                  key: const ValueKey<String>('finance_settings_rate'),
                  controller: _rate,
                  enabled: !submitting,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  decoration: InputDecoration(
                    labelText: 'Aylık oran (%)',
                    prefixIcon: const Icon(Icons.percent_rounded),
                    helperText: 'En çok ${formatRateBp(maxRate)} (sistem sınırı). Oran, yöntem ve ek gün yalnız sonraki hesaplamaları etkiler.',
                    helperMaxLines: 4,
                  ),
                  validator: (value) {
                    final bp = parseRateBp(value);
                    if (bp == null) return 'Oranı yüzde olarak girin (örn. 5 ya da 4,5).';
                    if (bp > maxRate) return 'Oran ${formatRateBp(maxRate)} sistem sınırını aşamaz.';
                    return null;
                  },
                ),
                const SizedBox(height: AppSpace.md),
                const FinanceGroupTitle('Gün esası'),
                const SizedBox(height: AppSpace.sm),
                Wrap(
                  spacing: AppSpace.sm,
                  runSpacing: AppSpace.sm,
                  children: [
                    for (final method in LateFeeMethod.values)
                      ChoiceChip(
                        key: ValueKey<String>('finance_settings_method_${method.apiValue}'),
                        label: Text(method.label),
                        selected: _method == method,
                        onSelected: submitting
                            ? null
                            : (_) => setState(() {
                                markDirty();
                                _method = method;
                              }),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpace.md),
                TextFormField(
                  key: const ValueKey<String>('finance_settings_grace'),
                  controller: _grace,
                  enabled: !submitting,
                  keyboardType: TextInputType.number,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  decoration: const InputDecoration(
                    labelText: 'Vadeye ek gün (0-90)',
                    prefixIcon: Icon(Icons.hourglass_empty_rounded),
                    helperText: 'Vade gününü izleyen bu kadar gün gecikme sayılmaz.',
                    helperMaxLines: 3,
                  ),
                  validator: (v) {
                    final n = int.tryParse((v ?? '').trim());
                    return n == null || n < 0 || n > 90 ? 'Ek gün 0 ile 90 arasında olmalı.' : null;
                  },
                ),
                const SizedBox(height: AppSpace.md),
                _startPicker(context),
                const SizedBox(height: AppSpace.sm),
                Text(
                  'Oran ve yöntemin hukuka uygunluğunu hukuki danışmanlıkla doğrulayın; bu ekran hukuki görüş değildir.',
                  style: th.bodySmall?.copyWith(color: p.textSecondary),
                ),
              ],
              const Divider(),
              // --- Hatırlatma ---
              const DialogSectionTitle(icon: Icons.mark_email_read_rounded, title: 'Borç hatırlatma'),
              if (_reminderLegalBlocked)
                const Padding(
                  padding: EdgeInsets.only(top: AppSpace.sm),
                  child: InlineNotice(
                    key: ValueKey<String>('finance_settings_reminder_legal'),
                    tone: AppTone.warning,
                    message: 'Hukuk onayı bekleniyor. Borç hatırlatma onay tamamlanana dek açılamaz.',
                  ),
                ),
              if (!_base.reminders.smtpConfigured)
                const Padding(
                  padding: EdgeInsets.only(top: AppSpace.sm),
                  child: InlineNotice(
                    key: ValueKey<String>('finance_settings_smtp'),
                    tone: AppTone.info,
                    message: 'E-posta gönderimi bu sunucuda yapılandırılmamış; hatırlatma gönderilemez.',
                  ),
                ),
              Material(
                type: MaterialType.transparency,
                child: SwitchListTile(
                  key: const ValueKey<String>('finance_settings_reminders_enabled'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Borç hatırlatma kullanılsın'),
                  subtitle: const Text('E-posta ile bilgilendirme; her gönderim önizlenir ve onaylanır.'),
                  value: _remindersEnabled,
                  onChanged: (submitting || (_reminderLegalBlocked && !_base.reminders.enabled))
                      ? null
                      : (v) => setState(() {
                          markDirty();
                          _remindersEnabled = v;
                        }),
                ),
              ),
              if (_remindersEnabled) ...[
                const SizedBox(height: AppSpace.sm),
                MoneyFormField(
                  key: const ValueKey<String>('finance_settings_min_overdue_group'),
                  fieldKey: const ValueKey<String>('finance_settings_min_overdue'),
                  controller: _minOverdue,
                  enabled: !submitting,
                  label: 'En az vadesi geçmiş tutar',
                  helperText: 'Bu tutarın altındaki borçlar için hatırlatma gitmez (en az 1 lira).',
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: AppSpace.md),
                _intField('finance_settings_min_days', _minDays, 'En az gecikme günü (1-120)', 1, 120),
                const SizedBox(height: AppSpace.md),
                _intField('finance_settings_min_interval', _minInterval, 'İki hatırlatma arası en az gün (7-90)', 7, 90),
                const SizedBox(height: AppSpace.md),
                _intField('finance_settings_max_consecutive', _maxConsecutive, 'Ardışık hatırlatma sınırı (1-6)', 1, 6,
                    helper: 'Sınıra ulaşan daire "elden takip" listesine düşer; e-posta gitmez.'),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _intField(String key, TextEditingController controller, String label, int min, int max, {String? helper}) {
    return TextFormField(
      key: ValueKey<String>(key),
      controller: controller,
      enabled: !submitting,
      keyboardType: TextInputType.number,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      decoration: InputDecoration(labelText: label, helperText: helper, helperMaxLines: 3),
      validator: (v) {
        final n = int.tryParse((v ?? '').trim());
        return n == null || n < min || n > max ? 'Değer $min ile $max arasında olmalı.' : null;
      },
    );
  }

  Widget _startPicker(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final start = _start;
    final locked = !_startEditable;
    return DialogPanel(
      key: const ValueKey<String>('finance_settings_start'),
      tone: _startError != null ? AppTone.danger : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const DialogSectionTitle(icon: Icons.calendar_month_rounded, title: 'İlk hesaplanacak ay'),
          const SizedBox(height: AppSpace.sm),
          if (start == null)
            PrimaryActionButton(
              key: const ValueKey<String>('finance_settings_start_pick'),
              label: 'Başlangıç Ayını Seç',
              icon: Icons.event_rounded,
              variant: AppButtonVariant.tonal,
              expand: false,
              onPressed: submitting
                  ? null
                  : () => setState(() {
                      markDirty();
                      _start = _currentPeriod.previous;
                    }),
            )
          else
            Row(
              children: [
                IconButton(
                  key: const ValueKey<String>('finance_settings_start_prev'),
                  tooltip: 'Önceki ay',
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                  onPressed: (submitting || locked)
                      ? null
                      : () => setState(() {
                          markDirty();
                          _start = start.previous;
                        }),
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Expanded(
                  child: Semantics(
                    liveRegion: true,
                    child: Text(start.label, key: const ValueKey<String>('finance_settings_start_label'), textAlign: TextAlign.center, style: th.titleMedium),
                  ),
                ),
                IconButton(
                  key: const ValueKey<String>('finance_settings_start_next'),
                  tooltip: 'Sonraki ay',
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                  onPressed: (submitting || locked || start >= _currentPeriod)
                      ? null
                      : () => setState(() {
                          markDirty();
                          _start = start.next;
                        }),
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
          Text(
            locked
                ? 'Aktif bir tazminat çalıştırması var; başlangıç ayı değiştirilemez.'
                : 'Geçmişe yönelik sürpriz borç yazılmaması için zorunludur; bu aydan önceki aylar hesaplanmaz.',
            style: th.bodySmall?.copyWith(color: p.textSecondary),
          ),
          if (_startError != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.sm),
              child: CrmFormError(message: _startError!, reveal: false),
            ),
        ],
      ),
    );
  }
}
