import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MaxLengthEnforcement;
import 'package:site_kapi_kontrol/models/finance.dart';
import 'package:site_kapi_kontrol/models/vehicle_record.dart' show crmDateParam;
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/crm_confirm_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/large_dialog_parts.dart';
import 'package:site_kapi_kontrol/ui/helpers/a11y_announce.dart';
import 'package:site_kapi_kontrol/ui/helpers/date_input.dart';
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_errors.dart';
import 'package:site_kapi_kontrol/ui/helpers/form_validation.dart';
import 'package:site_kapi_kontrol/ui/helpers/idempotency.dart';
import 'package:site_kapi_kontrol/ui/helpers/istanbul_time.dart';
import 'package:site_kapi_kontrol/ui/helpers/money.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/helpers/retry_lock.dart';
import 'package:site_kapi_kontrol/ui/helpers/text_length.dart';
import 'package:site_kapi_kontrol/ui/widgets/fee_spec_form.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_4b_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_account_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart' show filledToneStyle;

/// Borçlandırma / ek borç penceresi kapanırken döner.
class FinanceRunOutcome {
  const FinanceRunOutcome({required this.message});

  final String message;
}

enum _Stage { form, preview }

/// Gönderilecek girdilerin dondurulmuş kopyası: önizleme ile onay AYNI girdiyle yapılır. [signature] FORM
/// İÇERİĞİNİN imzasıdır (tanım + dönem / vade ya da ek borcun tüm alanları); önizlemenin toplamı, sayısı ve özeti
/// imzada YOKTUR (işlem anahtarı önizlemeler arasında değişmesin).
class _RunInputs {
  const _RunInputs({this.period, this.dueDate, this.charge, required this.signature});

  final FinancePeriod? period;
  final DateTime? dueDate;
  final ExtraChargeInput? charge;
  final String signature;
}

/// "Borçlandır" (tanım -> dönem -> ÖNİZLEME -> onay) ve "Ek Borç Ekle" (ad, tutar, dağıtım, hedef, vade ->
/// ÖNİZLEME -> onay) penceresi (Platform Faz 4a).
///
/// Para bütünlüğü:
/// - Önizleme HİÇBİR ŞEY yazmaz; liste (daire, kim öder, tutar), toplam ve eksik veri uyarısı gösterilir.
///   Onay, önizlemedeki toplam, daire sayısı ve içerik özetini (`preview_hash`) sunucuya bildirir; veri bu arada
///   değiştiyse sunucu 409 `PREVIEW_STALE` döner, hiçbir şey yazılmaz. O zaman önizleme OTOMATİK yenilenir:
///   yenileme sürerken ya da BAŞARISIZ olursa eski önizlemeyle onay KAPALIDIR ("Önizlemeyi Yenile" düğmesi
///   çıkar); yenilenince eski ve yeni toplam yazılır, duyurulur ve kullanıcı yeni toplamı görüp yeniden onaylar.
/// - Eksik verisi olan daire varsa sunucu `PREVIEW_INCOMPLETE` der: kullanıcı açıkça "eksik daireleri atla"
///   seçeneğini işaretlemeden onay açılmaz; atlanan dairelerin payı kalanlara yeniden paylaştırılıyorsa
///   (`redistributed`) bu onaydan ÖNCE yazılır. Bu dönem zaten borçlandırılmış / kapalıysa onay açılmaz.
/// - Onay düğmesi pasifken NEDEN düğmeyle ilişkilendirilir (ipucu + ekrandaki "Onaylamak için" satırı).
/// - `idempotency_key` FORM İÇERİĞİ İMZASINA bağlıdır ve önizlemeler arasında SIFIRLANMAZ: belirsiz sonuçtan
///   sonra "Geri -> Önizle -> Onayla" AYNI anahtarı kullanır, çift borç yazmaz. Yalnız form değişince yeni anahtar
///   gelir. Ek borçta aynı ek borç son 24 saatte yazıldıysa (önizleme `duplicate_of_run_id` ya da onayda 409
///   `DUPLICATE_CHARGE`) uyarı penceresi açılır; "Yine de ekle" bilinçli onayı yeni anahtar ve `allow_duplicate`
///   ile gider. Sunucu aynı anahtarı farklı bilgiyle bulursa (`IDEMPOTENCY_CONFLICT`) anahtar atılır ve hesapların
///   kontrol edilmesi istenir.
/// - Çift gönderim koruması (`_submitting`), gönderim sürerken geri tuşu kapatmaz; eski / yavaş önizleme
///   yanıtı yenisini ezmez (jeton). Sonuç belirsizse (ağ / 5xx) çağıran kapanırken listeyi tazeler.
class FinanceRunDialog extends StatefulWidget {
  const FinanceRunDialog.definition({
    super.key,
    required this.scope,
    required FeeDefinition this.definition,
    this.now,
    this.onRefreshNeeded,
  });

  const FinanceRunDialog.charge({
    super.key,
    required this.scope,
    this.now,
    this.onRefreshNeeded,
  }) : definition = null;

  final PeopleScope scope;

  /// Borçlandırılan tanım; null ise ek borç kipi.
  final FeeDefinition? definition;
  final DateTime Function()? now;
  final VoidCallback? onRefreshNeeded;

  static const int maxNameLength = 80;
  static const int pageSize = 50;

  static Future<FinanceRunOutcome?> showDefinition(
    BuildContext context, {
    required PeopleScope scope,
    required FeeDefinition definition,
    DateTime Function()? now,
    VoidCallback? onRefreshNeeded,
  }) {
    return showDialog<FinanceRunOutcome>(
      context: context,
      barrierDismissible: false,
      builder: (_) => FinanceRunDialog.definition(
        scope: scope,
        definition: definition,
        now: now,
        onRefreshNeeded: onRefreshNeeded,
      ),
    );
  }

  static Future<FinanceRunOutcome?> showCharge(
    BuildContext context, {
    required PeopleScope scope,
    DateTime Function()? now,
    VoidCallback? onRefreshNeeded,
  }) {
    return showDialog<FinanceRunOutcome>(
      context: context,
      barrierDismissible: false,
      builder: (_) => FinanceRunDialog.charge(
        scope: scope,
        now: now,
        onRefreshNeeded: onRefreshNeeded,
      ),
    );
  }

  @override
  State<FinanceRunDialog> createState() => _FinanceRunDialogState();
}

class _FinanceRunDialogState extends State<FinanceRunDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final GlobalKey<FeeSpecFormState> _specKey = GlobalKey<FeeSpecFormState>();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _dueDate = TextEditingController();

  // Form içeriği imzası -> işlem anahtarı. Pencere ömrünce yaşar; önizlemeler arasında SIFIRLANMAZ.
  final IdempotencyKeys _keys = IdempotencyKeys('run');
  final RetryLock _retry = RetryLock();

  late FinancePeriod _period = _initialPeriod();
  _Stage _stage = _Stage.form;
  FeePreview? _preview;
  _RunInputs? _inputs;
  int _previewToken = 0;
  int _visible = FinanceRunDialog.pageSize;
  bool _previewing = false;
  bool _submitting = false;
  bool _asking = false;
  bool _skipMissing = false;
  bool _dueOverflow = false;

  // Sunucu "önizleme eskidi" dedi ve yenileme bitmedi / başarısız: eski önizlemeyle onay kapalıdır.
  // [_staleFrom]: eskiyen önizleme (yenilenince eski ve yeni toplam birlikte yazılır; elle yenilemede de korunur).
  bool _previewStale = false;
  FeePreview? _staleFrom;
  bool _needsRefreshOnClose = false;

  // Kullanıcının "Yine de ekle" dediği ek borç imzası: o imza için `allow_duplicate` gönderilir.
  String? _dupAllowedSignature;

  // İP-1A: ek borcun "Kim öder" seçimi (varsayılan ev sahibi; sunucu varsayılanıyla aynı olduğu için o zaman gönderilmez).
  ChargeParty _chargeParty = ChargeParty.owner;
  String? _error;
  String? _notice;
  String? _noticeSpoken;

  FeeDefinition? get _definition => widget.definition;
  bool get _isCharge => widget.definition == null;

  FinancePeriod get _currentPeriod => FinancePeriod.of(istanbulNow(widget.now?.call()));

  FinancePeriod _initialPeriod() {
    final def = widget.definition;
    final current = FinancePeriod.of(istanbulNow(widget.now?.call()));
    if (def == null) return current;
    final last = def.lastPostedPeriod;
    var base = last != null ? last.next : current;
    final min = _minPeriodOf(def, current);
    final max = _maxPeriodOf(def, current);
    if (base < min) base = min;
    if (base > max) base = max;
    return base;
  }

  static FinancePeriod _minPeriodOf(FeeDefinition def, FinancePeriod current) =>
      def.startPeriod ?? current.addMonths(-24);

  static FinancePeriod _maxPeriodOf(FeeDefinition def, FinancePeriod current) {
    final ahead = current.addMonths(12);
    final end = def.endPeriod;
    final max = end != null && end < ahead ? end : ahead;
    final min = _minPeriodOf(def, current);
    return max < min ? min : max;
  }

  @override
  void dispose() {
    ++_previewToken;
    _retry.dispose();
    _name.dispose();
    _dueDate.dispose();
    super.dispose();
  }

  // --- Önizleme --------------------------------------------------------------------------------

  DateTime? get _dueDateValue => parseDateField(_dueDate.text);

  /// Formu doğrular ve girdileri dondurur; geçersizse null. Alan hataları ve ek kurallar (kategori listesi,
  /// hedef) TEK doğrulama + TEK görünür kılma zinciriyle çalışır.
  _RunInputs? _collect() {
    final allOk = validateForm(
      _formKey,
      validateExtra: () => _specKey.currentState?.validateExtras() ?? true,
      revealExtra: () => _specKey.currentState?.revealFirstError() ?? false,
    );
    final spec = _specKey.currentState;
    if (!allOk) {
      setState(() => _error = kFixFieldsMessage);
      return null;
    }
    final due = _dueDateValue;
    if (!_isCharge) {
      final def = _definition!;
      if (def.isRecurring) {
        return _RunInputs(
          period: _period,
          signature: 'def:${def.id}|${_period.toApi()}',
        );
      }
      return _RunInputs(
        dueDate: due,
        signature: 'def:${def.id}|${due == null ? '' : crmDateParam(due)}',
      );
    }
    final read = spec?.read();
    if (read == null) {
      setState(() => _error = kFixFieldsMessage);
      return null;
    }
    final charge = ExtraChargeInput(
      name: _name.text.trim(),
      distribution: read.distribution,
      areaBasis: read.areaBasis,
      amountMinor: read.amountMinor,
      categoryAmounts: read.categoryAmounts,
      target: read.target,
      dueDate: due,
      chargeParty: _chargeParty == ChargeParty.owner ? null : _chargeParty,
    );
    return _RunInputs(charge: charge, signature: 'charge:${jsonEncode(charge.toJson())}');
  }

  /// Önizlemeyi alır. [reuse] verilirse form yeniden doğrulanmaz (onay sonrası yenileme). [staleFrom] verilirse
  /// bu yenileme `PREVIEW_STALE` sonrasıdır: başarıda eski ve yeni toplam yazılır ve duyurulur. [notice] başka
  /// yenileme nedenlerinde (eksik veri, dönem kapandı...) gösterilen açıklamadır.
  Future<void> _requestPreview({_RunInputs? reuse, String? notice, FeePreview? staleFrom}) async {
    if (_previewing || _submitting) return;
    final inputs = reuse ?? _collect();
    if (inputs == null) return;
    final token = ++_previewToken;
    setState(() {
      _previewing = true;
      _error = null;
      _notice = null;
      _noticeSpoken = null;
    });
    try {
      final auth = widget.scope.authService;
      final siteCode = widget.scope.siteCode;
      final FeePreview preview;
      if (inputs.charge != null) {
        preview = await auth.previewExtraCharge(siteCode, inputs.charge!);
      } else {
        preview = await auth.previewFeeRun(
          siteCode,
          _definition!.id,
          period: inputs.period,
          dueDate: inputs.dueDate,
        );
      }
      // Eski / yavaş yanıt yeni sonucu ezmez; pencere kapandıysa yok sayılır.
      if (!mounted || token != _previewToken) return;
      final String? shown = staleFrom != null ? _staleNotice(staleFrom, preview) : notice;
      setState(() {
        _preview = preview;
        _inputs = inputs;
        _stage = _Stage.preview;
        _previewing = false;
        _previewStale = false;
        _staleFrom = null;
        _skipMissing = false;
        _visible = FinanceRunDialog.pageSize;
        _notice = shown;
        _noticeSpoken = shown == null ? null : spokenMoneyText(shown);
      });
      announcePolite(
        context,
        shown != null
            ? spokenMoneyText(shown)
            : 'Önizleme hazır: ${preview.apartmentCount} daire, toplam ${moneySemanticLabel(preview.totalMinor)}.',
      );
    } catch (e) {
      if (!mounted || token != _previewToken) return;
      final limited = _retry.lockIfRateLimited(e, () {
        if (mounted) setState(() {});
      });
      setState(() {
        _previewing = false;
        // Yenileme başarısız: "önizleme yenilendi" DENMEZ; eski önizlemeyle onay kapalı kalır (_previewStale).
        _error = limited
            ? RetryLock.messageFor(e)
            : financeMessageOf(
                e,
                staleFrom != null || _previewStale
                    ? 'Önizleme yenilenemedi. İnternet bağlantınızı kontrol edip önizlemeyi yenileyin.'
                    : 'Önizleme alınamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.',
              );
      });
    }
  }

  /// `PREVIEW_STALE` sonrası yenilenen önizlemenin açıklaması: eski ve yeni toplam.
  String _staleNotice(FeePreview before, FeePreview now) {
    return 'Veriler değişti, önizleme yenilendi. Yeni toplam ${formatMinor(now.totalMinor)} '
        '(${now.apartmentCount} daire); önceki toplam ${formatMinor(before.totalMinor)} '
        '(${before.apartmentCount} daire) idi. Kontrol edip yeniden onaylayın.';
  }

  /// Eski önizleme geçersiz: onay kapanır ve önizleme yeniden alınır (elle "Önizlemeyi Yenile" de buraya gelir).
  void _refreshPreview({String? notice}) {
    final inputs = _inputs;
    if (inputs == null) return;
    unawaited(_requestPreview(reuse: inputs, notice: notice, staleFrom: _staleFrom));
  }

  void _backToForm() {
    if (_submitting) return;
    ++_previewToken;
    setState(() {
      _stage = _Stage.form;
      _preview = null;
      _inputs = null;
      _previewing = false;
      _previewStale = false;
      _staleFrom = null;
      _error = null;
      _notice = null;
      _noticeSpoken = null;
    });
  }

  // --- Onay ------------------------------------------------------------------------------------

  bool _canConfirm(FeePreview preview) =>
      !_previewStale &&
      !preview.alreadyPosted &&
      !preview.closed &&
      preview.lines.isNotEmpty &&
      (!preview.hasMissingData || _skipMissing);

  /// Onay düğmesi pasifken nedeni; onaylanabiliyorsa null.
  String? _confirmBlockedReason(FeePreview preview) {
    if (_previewing) return 'Önizleme yenileniyor.';
    if (_submitting) return null;
    if (_previewStale) return 'Önizleme eskidi. Önce "Önizlemeyi Yenile" düğmesine basın.';
    if (preview.alreadyPosted) return 'Bu tanım bu dönem için zaten borçlandırılmış.';
    if (preview.closed) return 'Bu dönem kapalı.';
    if (preview.lines.isEmpty) return 'Borçlandırılacak daire yok.';
    if (preview.hasMissingData && !_skipMissing) {
      return '"Eksik bilgili daireleri atla" seçeneğini işaretleyin ya da eksikleri tamamlayıp önizlemeyi yenileyin.';
    }
    if (_retry.locked) return 'Çok sık deneme yapıldı; biraz bekleyin.';
    return null;
  }

  Future<void> _confirm() async {
    // Önizleme yenilenirken (PREVIEW_STALE sonrası) eski önizlemeyle onay verilmez.
    if (_submitting || _previewing || _asking || _retry.locked) return;
    final preview = _preview;
    final inputs = _inputs;
    if (preview == null || inputs == null || !_canConfirm(preview)) return;
    // Ek borçta önizleme aynı ek borcun yakın zamanda yazıldığını bildirdiyse bilinçli onay istenir.
    if (_isCharge && preview.duplicateOfRunId != null && _dupAllowedSignature != inputs.signature) {
      if (!await _askDuplicate(null) || !mounted) return;
      _dupAllowedSignature = inputs.signature;
    }
    await _post(preview, inputs);
  }

  /// "Aynı ek borç kısa süre önce kaydedilmiş" uyarısı + ayrı, bilinçli "Yine de ekle" onayı.
  Future<bool> _askDuplicate(DuplicateChargeInfo? info) async {
    setState(() => _asking = true);
    try {
      final postedAt = info?.postedAt;
      return await confirmCrmAction(
        context,
        title: 'Aynı ek borç daha önce kaydedilmiş',
        message:
            'Aynı ek borç kısa süre önce kaydedilmiş görünüyor. Önce daire hesaplarını kontrol edin.'
            '${postedAt == null ? '' : '\nÖnceki kayıt: ${formatIstanbulDateTime(postedAt)}.'}'
            '\n\nYine de aynı borcu bir kez daha eklemek istiyor musunuz?',
        confirmLabel: 'Yine de ekle',
        cancelLabel: 'Vazgeç',
        icon: Icons.warning_amber_rounded,
        tone: AppTone.danger,
      );
    } finally {
      if (mounted) setState(() => _asking = false);
    }
  }

  Future<void> _post(FeePreview preview, _RunInputs inputs) async {
    // "Yine de ekle" ayrı bir amaçtır: farklı imza = farklı anahtar (önceki, kaydedilmiş olabilecek isteğin
    // yeniden oynatılması "yine de ekle" sayılmaz).
    final allowDuplicate = _isCharge && _dupAllowedSignature == inputs.signature;
    final keySignature = allowDuplicate ? '${inputs.signature}|dup' : inputs.signature;
    final key = _keys.keyFor(keySignature);
    setState(() {
      _submitting = true;
      _error = null;
      _notice = null;
      _noticeSpoken = null;
    });
    try {
      final auth = widget.scope.authService;
      final siteCode = widget.scope.siteCode;
      final FeePostResult result;
      if (inputs.charge != null) {
        result = await auth.postExtraCharge(
          siteCode,
          inputs.charge!,
          expectedTotalMinor: preview.totalMinor,
          expectedApartmentCount: preview.apartmentCount,
          expectedHash: preview.previewHash,
          skipMissing: _skipMissing,
          allowDuplicate: allowDuplicate,
          idempotencyKey: key,
        );
      } else {
        result = await auth.postFeeRun(
          siteCode,
          _definition!.id,
          period: inputs.period,
          dueDate: inputs.dueDate,
          expectedTotalMinor: preview.totalMinor,
          expectedApartmentCount: preview.apartmentCount,
          expectedHash: preview.previewHash,
          skipMissing: _skipMissing,
          idempotencyKey: key,
        );
      }
      // Yazma tamamlandı: anahtar atılır (form kapanır; aynı içerikle yeni bir açılış yeni anahtar alır).
      _keys.clear(keySignature);
      if (!mounted) return;
      _needsRefreshOnClose = false;
      final count = result.apartmentCount ?? (result.entriesCount > 0 ? result.entriesCount : preview.apartmentCount);
      final total = result.totalMinor ?? preview.totalMinor;
      popIfCurrent(
        context,
        FinanceRunOutcome(
          message: _isCharge
              ? 'Ek borç yazıldı: $count daire, toplam ${formatMinor(total)}.'
              : '${_definition!.name.trim().isEmpty ? 'Aidat' : _definition!.name.trim()}: '
                    '$count daireye toplam ${formatMinor(total)} borç yazıldı.',
        ),
      );
    } catch (e) {
      if (financeOutcomeUncertain(e)) _needsRefreshOnClose = true;
      if (!mounted) return;
      final limited = _retry.lockIfRateLimited(e, () {
        if (mounted) setState(() {});
      });
      if (hasErrorCode(e, 'PERIOD_ALREADY_POSTED') || hasErrorCode(e, 'DEFINITION_INACTIVE')) {
        // Tanım listesi eskimiştir (son borçlandırma / pasif): kapanırken tazelenir.
        _needsRefreshOnClose = true;
      }

      // Aynı ek borç son 24 saatte yazılmış: uyarı + ayrı bilinçli onay.
      if (hasErrorCode(e, 'DUPLICATE_CHARGE') && !limited) {
        setState(() => _submitting = false);
        final proceed = await _askDuplicate(duplicateChargeInfoOf(e));
        if (proceed && mounted) {
          _dupAllowedSignature = inputs.signature;
          await _post(preview, inputs);
        }
        return;
      }

      // Sunucu bu anahtarı farklı bilgiyle zaten kullanmış (yazma yapılmış olabilir): anahtar atılır, hesapların
      // kontrol edilmesi istenir. Sonraki deneme yeni anahtar alır; gerçek bir tekrar DUPLICATE_CHARGE ile yakalanır.
      if (hasErrorCode(e, 'IDEMPOTENCY_CONFLICT')) {
        _keys.clear(keySignature);
        _needsRefreshOnClose = true;
      }

      final refresh = hasErrorCode(e, 'PREVIEW_STALE') ||
          hasErrorCode(e, 'PREVIEW_INCOMPLETE') ||
          hasErrorCode(e, 'PERIOD_ALREADY_POSTED') ||
          hasErrorCode(e, 'PERIOD_CLOSED');
      if (refresh && !limited) {
        // Önizleme eskidi ya da durum değişti: eski önizlemeyle onay KAPANIR, önizleme yeniden alınır.
        final stale = hasErrorCode(e, 'PREVIEW_STALE');
        setState(() {
          _submitting = false;
          _previewStale = true;
          if (stale) _staleFrom = preview;
        });
        _refreshPreview(notice: stale ? null : financeMessageOf(e, 'Veriler değişti. Önizlemeyi kontrol edin.'));
        return;
      }
      setState(() {
        _submitting = false;
        _error = limited
            ? RetryLock.messageFor(e)
            : financeWriteMessage(
                e,
                'Borçlandırma yapılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.',
              );
      });
    }
  }

  void _notifyRefreshOnClose() {
    if (!_needsRefreshOnClose) return;
    _needsRefreshOnClose = false;
    widget.onRefreshNeeded?.call();
  }

  // --- Görünüm ---------------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final preview = _stage == _Stage.preview ? _preview : null;
    final canConfirm = preview != null && _canConfirm(preview);
    final blocked = preview == null ? null : _confirmBlockedReason(preview);
    final busy = _submitting || _previewing || _asking;
    final title = _isCharge
        ? 'Ek Borç Ekle'
        : (_definition!.isRecurring ? 'Borçlandır' : 'Tek Seferlik Borçlandır');
    final confirmDisabled = !canConfirm || busy || _retry.locked;
    Widget confirmButton = ElevatedButton(
      key: const ValueKey<String>('finance_run_confirm'),
      style: filledToneStyle(context),
      onPressed: confirmDisabled ? null : _confirm,
      child: Text(_submitting ? 'Yazılıyor...' : 'Onayla ve Borçlandır'),
    );
    if (preview != null && confirmDisabled && blocked != null) {
      // Pasif düğmenin NEDENİ düğmeyle TEK anlamsal düğümde okunur (etiket + ipucu) ve uzun basınca / üzerine
      // gelince görünür (tooltip anlamsal ağaca ikinci kez girmez).
      confirmButton = Semantics(
        container: true,
        excludeSemantics: true,
        button: true,
        enabled: false,
        label: 'Onayla ve Borçlandır',
        hint: blocked,
        child: Tooltip(message: blocked, excludeFromSemantics: true, child: confirmButton),
      );
    }
    return PopScope(
      canPop: !_submitting,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _notifyRefreshOnClose();
      },
      child: AppDialog(
        title: title,
        subtitle: _isCharge
            ? (widget.scope.siteName.isEmpty ? null : widget.scope.siteName)
            : (_definition!.name.trim().isEmpty ? null : _definition!.name.trim()),
        icon: _isCharge ? Icons.add_card_rounded : Icons.playlist_add_check_rounded,
        actions: preview == null
            ? [
                TextButton(
                  onPressed: _previewing ? null : () => popIfCurrent(context),
                  child: const Text('Vazgeç'),
                ),
                ElevatedButton(
                  key: const ValueKey<String>('finance_run_preview'),
                  onPressed: (_previewing || _retry.locked) ? null : () => _requestPreview(),
                  child: Text(_previewing ? 'Hesaplanıyor...' : 'Önizle'),
                ),
              ]
            : [
                TextButton(
                  onPressed: busy ? null : () => popIfCurrent(context),
                  child: const Text('Vazgeç'),
                ),
                TextButton(
                  key: const ValueKey<String>('finance_run_back'),
                  onPressed: busy ? null : _backToForm,
                  child: const Text('Geri'),
                ),
                confirmButton,
              ],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null) FinanceSubmitError(message: _error!),
            // Önizleme gösterilirken form AĞAÇTA kalır (girilen değerler korunur, "Geri" ile dönülür) ama yer
            // kaplamaz VE odaklanamaz: Offstage tek başına klavye / ekran okuyucu odağını kapatmaz.
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
    final def = _definition;
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_isCharge) ...[
            Text(
              'Tek seferlik bir borç yazılır. Önce önizleme gösterilir; onaylamadan hiçbir şey kaydedilmez.',
              style: th.bodySmall?.copyWith(color: p.textSecondary),
            ),
            const SizedBox(height: AppSpace.md),
            TextFormField(
              key: const ValueKey<String>('finance_charge_name'),
              controller: _name,
              enabled: !_previewing,
              textCapitalization: TextCapitalization.sentences,
              maxLength: FinanceRunDialog.maxNameLength,
              maxLengthEnforcement: MaxLengthEnforcement.none,
              buildCounter: (context, {required currentLength, required isFocused, maxLength}) =>
                  characterCounter(context, _name.text.trim().runes.length, FinanceRunDialog.maxNameLength),
              autovalidateMode: AutovalidateMode.onUserInteraction,
              decoration: const InputDecoration(
                labelText: 'Borç adı',
                hintText: 'Örn. Asansör yenileme',
                prefixIcon: Icon(Icons.title_rounded),
              ),
              validator: (value) {
                final length = trimmedCodePoints(value ?? '');
                if (length < 1) return 'Borç adını girin.';
                if (length > FinanceRunDialog.maxNameLength) {
                  return 'Ad en çok ${FinanceRunDialog.maxNameLength} karakter olabilir.';
                }
                return null;
              },
            ),
            const SizedBox(height: AppSpace.lg),
            FeeSpecForm(
              key: _specKey,
              scope: widget.scope,
              initialDistribution: FeeDistribution.equal,
              enabled: !_previewing,
              keyPrefix: 'charge_spec',
            ),
            const SizedBox(height: AppSpace.lg),
            ChargePartyChoice(
              key: const ValueKey<String>('finance_charge_party_group'),
              selected: _chargeParty,
              enabled: !_previewing,
              onSelected: (value) => setState(() => _chargeParty = value),
            ),
            const SizedBox(height: AppSpace.md),
            _dueDateField(optionalHint: 'Boşsa kayıt günü vade sayılır.'),
          ] else if (def!.isRecurring) ...[
            _periodStepper(context, def),
            const SizedBox(height: AppSpace.sm),
            _chargePartyNote(context, def),
          ] else ...[
            Text(
              'Tek seferlik tanım yalnız bir kez borçlandırılabilir.',
              style: th.bodySmall?.copyWith(color: p.textSecondary),
            ),
            const SizedBox(height: AppSpace.sm),
            _chargePartyNote(context, def),
            const SizedBox(height: AppSpace.md),
            _dueDateField(optionalHint: 'Boşsa kayıt günü vade sayılır.'),
          ],
          const SizedBox(height: AppSpace.md),
          Text(
            'Önizle düğmesi hiçbir şey kaydetmez; onaydan önce daire listesini ve toplamı göreceksiniz.',
            style: th.bodySmall?.copyWith(color: p.textSecondary),
          ),
        ],
      ),
    );
  }

  /// İP-1A: tanımın "Kim öder" bilgisi (tanımda değiştirilir; borçlandırma penceresinde yalnız bilgi). Önizleme satırları
  /// her dairenin hangi hesaba yazılacağını gösterir.
  Widget _chargePartyNote(BuildContext context, FeeDefinition def) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final party = def.effectiveChargeParty;
    return Text(
      'Kim öder: ${party.label}. ${party.description}',
      key: const ValueKey<String>('finance_run_charge_party'),
      style: th.bodySmall?.copyWith(color: p.textSecondary),
    );
  }

  /// Yazarken 8 rakamdan fazlası eklenemez: sessiz reddetme olmasın, uyarı gösterilir ve duyurulur.
  void _onDueRejected() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _dueOverflow = true);
      announcePolite(context, 'Tarih en çok 8 rakamdır. Fazla rakam eklenmedi.');
    });
  }

  Widget _dueDateField({required String optionalHint}) {
    final p = context.palette;
    return TextFormField(
      key: const ValueKey<String>('finance_run_due_date'),
      controller: _dueDate,
      enabled: !_previewing,
      keyboardType: TextInputType.number,
      inputFormatters: [DateInputFormatter(onRejected: _onDueRejected)],
      autovalidateMode: AutovalidateMode.onUserInteraction,
      onChanged: (_) => setState(() => _dueOverflow = false),
      decoration: InputDecoration(
        labelText: 'Vade tarihi (isteğe bağlı)',
        hintText: 'GG.AA.YYYY',
        helperText: _dueOverflow
            ? 'Tarih en çok 8 rakamdır (GG.AA.YYYY); fazla rakam eklenmedi.'
            : optionalHint,
        helperMaxLines: 3,
        helperStyle: _dueOverflow
            ? TextStyle(color: AppTone.warning.ink(p), fontWeight: FontWeight.w700)
            : null,
        prefixIcon: const Icon(Icons.event_rounded),
      ),
      validator: validateDateField,
    );
  }

  Widget _periodStepper(BuildContext context, FeeDefinition def) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final min = _minPeriodOf(def, _currentPeriod);
    final max = _maxPeriodOf(def, _currentPeriod);
    final last = def.lastPostedPeriod;
    return DialogPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const DialogSectionTitle(icon: Icons.calendar_month_rounded, title: 'Dönem'),
          const SizedBox(height: AppSpace.sm),
          Row(
            children: [
              IconButton(
                key: const ValueKey<String>('finance_period_prev'),
                tooltip: 'Önceki ay',
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                onPressed: (_previewing || _period <= min)
                    ? null
                    : () => setState(() => _period = _period.previous),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    _period.label,
                    key: const ValueKey<String>('finance_period_label'),
                    textAlign: TextAlign.center,
                    style: th.titleMedium,
                  ),
                ),
              ),
              IconButton(
                key: const ValueKey<String>('finance_period_next'),
                tooltip: 'Sonraki ay',
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                onPressed: (_previewing || _period >= max)
                    ? null
                    : () => setState(() => _period = _period.next),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.xs),
          Text(
            last == null
                ? 'Bu tanım henüz borçlandırılmadı.'
                : 'Son borçlandırılan dönem: ${last.label}.',
            style: th.bodySmall?.copyWith(color: p.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview(BuildContext context, FeePreview preview, String? blocked) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final shown = preview.lines.length < _visible ? preview.lines.length : _visible;
    final remaining = preview.lines.length - shown;
    final summaryLabel = [
      'Önizleme',
      if (preview.period != null) 'Dönem: ${preview.period!.label}',
      '${preview.apartmentCount} daire',
      'Toplam borç: ${moneySemanticLabel(preview.totalMinor)}',
    ].join('. ');
    // Zaten borçlandırıldı / kapalı / boş durumlarının kendi bildirimi var; "Onaylamak için" satırı yalnız
    // kullanıcının ELİNDE bir çözüm olan iki durumda yazılır (önizleme eski, eksik veri onayı).
    final showBlockedLine = blocked != null &&
        !_previewing &&
        (_previewStale || (preview.hasMissingData && !_skipMissing));
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_notice != null) ...[
          InlineNotice(
            key: const ValueKey<String>('finance_run_notice'),
            tone: AppTone.warning,
            message: _notice!,
            semanticsLabel: _noticeSpoken,
          ),
          const SizedBox(height: AppSpace.md),
        ],
        // Özet TEK birleşik etiketle okunur (başlık, dönem, sayı ve toplam iki kez okunmasın).
        DialogPanel(
          key: const ValueKey<String>('finance_run_summary'),
          child: Semantics(
            container: true,
            label: summaryLabel,
            child: ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const DialogSectionTitle(icon: Icons.fact_check_rounded, title: 'Önizleme'),
                  const SizedBox(height: AppSpace.sm),
                  if (preview.period != null)
                    Text('Dönem: ${preview.period!.label}', style: th.bodyMedium),
                  Text(
                    '${preview.apartmentCount} daire',
                    key: const ValueKey<String>('finance_run_count'),
                    style: th.bodyMedium,
                  ),
                  const SizedBox(height: AppSpace.xs),
                  Text(
                    formatMinor(preview.totalMinor),
                    key: const ValueKey<String>('finance_run_total'),
                    style: th.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  Text('Toplam borç', style: th.bodySmall?.copyWith(color: p.textSecondary)),
                ],
              ),
            ),
          ),
        ),
        if (_previewStale && !_previewing) ...[
          const SizedBox(height: AppSpace.md),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: PrimaryActionButton(
              key: const ValueKey<String>('finance_run_refresh'),
              label: 'Önizlemeyi Yenile',
              icon: Icons.refresh_rounded,
              variant: AppButtonVariant.tonal,
              expand: false,
              onPressed: (_submitting || _retry.locked) ? null : () => _refreshPreview(),
            ),
          ),
        ],
        if (showBlockedLine) ...[
          const SizedBox(height: AppSpace.sm),
          Text(
            'Onaylamak için: $blocked',
            key: const ValueKey<String>('finance_run_blocked_reason'),
            style: th.bodySmall?.copyWith(color: p.textSecondary, fontWeight: FontWeight.w600),
          ),
        ],
        if (preview.alreadyPosted) ...[
          const SizedBox(height: AppSpace.md),
          const InlineNotice(
            key: ValueKey<String>('finance_run_already_posted'),
            message: 'Bu tanım bu dönem için zaten borçlandırılmış. Aynı ay ikinci kez borçlandırılamaz.',
          ),
        ],
        if (preview.closed) ...[
          const SizedBox(height: AppSpace.md),
          const InlineNotice(
            key: ValueKey<String>('finance_run_closed'),
            message:
                'Bu dönem kapatılmış; kapalı döneme borç yazılamaz. Kapalı ayı yalnızca süper kullanıcı yeniden açabilir.',
          ),
        ],
        if (_isCharge && preview.duplicateOfRunId != null) ...[
          const SizedBox(height: AppSpace.md),
          const InlineNotice(
            key: ValueKey<String>('finance_run_duplicate'),
            tone: AppTone.warning,
            message:
                'Aynı ek borç kısa süre önce kaydedilmiş görünüyor. Önce daire hesaplarını kontrol edin.',
          ),
        ],
        if (preview.redistributed) ...[
          const SizedBox(height: AppSpace.md),
          InlineNotice(
            key: const ValueKey<String>('finance_run_redistributed'),
            tone: AppTone.warning,
            message: preview.skippedCount > 0
                ? 'Eksik bilgili ${preview.skippedCount} daire hariç tutuldu; tutar kalan dairelere yeniden paylaştırılır.'
                : 'Eksik bilgili daireler hariç tutuldu; tutar kalan dairelere yeniden paylaştırılır.',
          ),
        ],
        if (preview.hasMissingData) ...[
          const SizedBox(height: AppSpace.md),
          _buildMissing(context, preview),
        ],
        if (preview.zeroAmountCount > 0) ...[
          const SizedBox(height: AppSpace.md),
          InlineNotice(
            key: const ValueKey<String>('finance_run_zero'),
            tone: AppTone.info,
            message:
                '${preview.zeroAmountCount} daireye pay sıfır kuruş düştüğü için borç yazılmayacak.',
          ),
        ],
        if (preview.lines.isEmpty && !preview.alreadyPosted && !preview.closed) ...[
          const SizedBox(height: AppSpace.md),
          const InlineNotice(
            key: ValueKey<String>('finance_run_empty'),
            tone: AppTone.info,
            message: 'Borçlandırılacak daire bulunamadı. Hedefi ve daire bilgilerini kontrol edin.',
          ),
        ],
        if (preview.lines.isNotEmpty) ...[
          const SizedBox(height: AppSpace.md),
          Semantics(header: true, container: true, child: Text('Daire listesi', style: th.titleSmall)),
          const SizedBox(height: AppSpace.xs),
          for (var i = 0; i < shown; i++) FeePreviewLineTile(line: preview.lines[i]),
          if (remaining > 0)
            Align(
              alignment: Alignment.center,
              child: PrimaryActionButton(
                key: const ValueKey<String>('finance_run_more'),
                label: 'Daha fazla göster ($remaining)',
                icon: Icons.expand_more_rounded,
                variant: AppButtonVariant.tonal,
                expand: false,
                onPressed: () => setState(() => _visible += FinanceRunDialog.pageSize),
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildMissing(BuildContext context, FeePreview preview) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    const shownMax = 10;
    final missing = preview.missingData;
    return DialogPanel(
      key: const ValueKey<String>('finance_run_missing'),
      tone: AppTone.warning,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DialogSectionTitle(
            icon: Icons.warning_amber_rounded,
            title: '${missing.length} dairenin bilgisi eksik',
            tone: AppTone.warning,
          ),
          const SizedBox(height: AppSpace.sm),
          Text(
            'Bu dairelere borç yazılamaz. Eksikleri Kişiler > Daireler ekranından tamamlayıp önizlemeyi '
            'yenileyebilir ya da bu daireleri atlayarak devam edebilirsiniz.',
            style: th.bodyMedium,
          ),
          const SizedBox(height: AppSpace.sm),
          for (final item in missing.take(shownMax))
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.xs),
              child: Text(
                // Blok adı da yazılır (aynı numaralı daire farklı bloklarda olabilir).
                '${financeApartmentTitle(item.blockName, item.label.trim().isEmpty ? 'Daire' : item.label.trim())}: '
                '${financeMissingReason(item.reason, code: item.reasonCode)}',
                style: th.bodyMedium?.copyWith(color: p.text),
              ),
            ),
          if (missing.length > shownMax)
            Text('ve ${missing.length - shownMax} daire daha', style: th.bodySmall),
          // Opak panel zemini üstünde ListTile mürekkep sıçraması görünmez olurdu: saydam Material araya girer.
          Material(
            type: MaterialType.transparency,
            child: SwitchListTile(
              key: const ValueKey<String>('finance_skip_missing'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Eksik bilgili daireleri atla'),
              subtitle: const Text('İşaretlemezseniz onay verilemez.'),
              value: _skipMissing,
              onChanged: _submitting ? null : (value) => setState(() => _skipMissing = value),
            ),
          ),
        ],
      ),
    );
  }
}
