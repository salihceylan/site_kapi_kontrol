import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MaxLengthEnforcement;
import 'package:site_kapi_kontrol/models/cash_models.dart';
import 'package:site_kapi_kontrol/models/finance.dart';
import 'package:site_kapi_kontrol/models/vehicle_record.dart' show crmDateParam;
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/crm_pickers.dart';
import 'package:site_kapi_kontrol/ui/dialogs/large_dialog_parts.dart';
import 'package:site_kapi_kontrol/ui/helpers/a11y_announce.dart';
import 'package:site_kapi_kontrol/ui/helpers/date_input.dart';
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_4b_access.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_errors.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_write_mixin.dart' show FinanceDiscardGuard;
import 'package:site_kapi_kontrol/ui/helpers/focus_helpers.dart';
import 'package:site_kapi_kontrol/ui/helpers/form_validation.dart';
import 'package:site_kapi_kontrol/ui/helpers/idempotency.dart';
import 'package:site_kapi_kontrol/ui/helpers/istanbul_time.dart';
import 'package:site_kapi_kontrol/ui/helpers/money.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/helpers/retry_lock.dart';
import 'package:site_kapi_kontrol/ui/helpers/text_length.dart';
import 'package:site_kapi_kontrol/ui/widgets/crm_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_4b_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_account_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/money_field.dart';

/// Tahsilat penceresi kapanırken döner: sunucu yanıtı ve kullanıcıya gösterilecek kısa mesaj.
class FinancePaymentOutcome {
  const FinancePaymentOutcome({required this.result, required this.message});

  final LedgerWriteResult result;
  final String message;
}

/// "Tahsilat Ekle" ve "Tahsilatı Düzelt" penceresi (Platform Faz 4a).
///
/// - Alanlar: daire seçici, tutar (kuruşa KESİN çevrilir; yanında ayrıştırılan tutar gösterilir), tarih
///   (GG.AA.YYYY, İstanbul takvim günü; gelecek olamaz), yöntem (Nakit / Havale-EFT / Çek; seçilmeden
///   gönderilmez), açıklama (en çok 200 karakter, kod noktası sayımı).
/// - [correcting] verilirse düzeltme kipidir: eski tahsilat ters kayıtla iptal edilir, yeni tutar yeni kayıt
///   olarak yazılır (TEK işlemde); daire değiştirilemez.
/// - Çift gönderim koruması: `_submitting`, gönderim sürerken geri tuşu kapatmaz. `idempotency_key` verinin
///   (site, daire, tutar, tarih, yöntem) imzasına bağlıdır ve imza -> anahtar HARİTASINDA oturum boyunca tutulur
///   ([sessionIdempotencyKeys]): aynı veriyle yeniden deneme (pencere kapanıp açılsa, A -> B -> A gezinmesi olsa
///   bile) AYNI anahtarı kullanır, sonucu belirsiz istek çift kayıt yaratmaz. Açıklama imzada YOKTUR (yalnız metni
///   düzelten kullanıcı yeni anahtar almaz). Başarıdan sonra o imzanın anahtarı atılır: aynı tutarda ikinci
///   gerçek tahsilat yeni anahtar alır.
/// - Faz 4b: sitede aktif kasa / banka hesabı varsa HESAP seçimi ZORUNLUDUR (sunucu `ACCOUNT_REQUIRED`); yönteme göre
///   yalnız ÖNERİ yapılır (nakit -> kasa, havale / çek -> banka), kullanıcı değiştirebilir. Hesap listesi okunamazsa
///   uyarı + "Tekrar Dene" gösterilir ve sunucu gerekirse hesap ister. Başarıda düzenlenen makbuz yanıttaki
///   `receipt` ile sonuca eklenir. Düzeltmede hesap sorulmaz (sunucu eski ödemenin hesabını kullanır).
/// - Sunucu reddi (kapalı dönem vb.) Türkçe mesajla pencerede gösterilir ve pencere AÇIK kalır. Dönem bilgisi
///   yüklüyse ve seçilen ay kapalıysa tarih alanının altında bilgi amaçlı uyarı görünür (kesin karar sunucuda).
/// - İki hesap (İP-1A): iki hesaplı dairede "Daire hesabı" seçilir ([Kiracı hesabı] [Ev sahibi hesabı]); tahsilat yalnız
///   seçilen hesabın borcundan düşer. Başlangıç değeri [accountParty] (ekstrenin seçili sekmesi) ya da sunucunun varsayılan
///   tahsilat hesabıdır. [accountChoice] null ise (pencere ekstre dışından açıldı) daire seçilince sunucuya sorulur; hesap
///   bilgisi alınamazsa ya da tek hesaplı dairede seçim gösterilmez ve sunucu hesabı kendisi seçer (eski davranış).
///   Düzeltmede seçim eski tahsilatın hesabıyla başlar; değiştirilirse yeni tahsilat diğer hesaba yazılır (ters kayıt eski
///   hesapta kalır).
class FinancePaymentDialog extends StatefulWidget {
  const FinancePaymentDialog({
    super.key,
    required this.scope,
    this.apartmentId,
    this.apartmentLabel,
    this.correcting,
    this.now,
    this.onRefreshNeeded,
    this.accountParty,
    this.accountChoice,
  });

  final PeopleScope scope;

  /// Önceden seçili daire (ekstreden açılınca); null ise daire seçici gösterilir.
  final int? apartmentId;
  final String? apartmentLabel;

  /// Düzeltilen tahsilat; null ise yeni tahsilat.
  final LedgerEntry? correcting;

  /// Şimdiki zaman (tarih doğrulaması; testler içindir).
  final DateTime Function()? now;

  /// Sonuç BELİRSİZ kaldığında (ağ / 5xx) pencere kapanırken çağrılır: çağıran listeyi tazeler.
  final VoidCallback? onRefreshNeeded;

  /// İP-1A: başlangıçta seçili daire hesabı (ekstrenin sekmesi / düzeltilen tahsilatın hesabı).
  final AccountParty? accountParty;

  /// İP-1A: dairenin iki hesabı var mı (seçim gösterilsin mi)? null: bilinmiyor (daire seçilince sunucuya sorulur).
  final bool? accountChoice;

  static const int maxNoteLength = 200;

  static Future<FinancePaymentOutcome?> show(
    BuildContext context, {
    required PeopleScope scope,
    int? apartmentId,
    String? apartmentLabel,
    LedgerEntry? correcting,
    DateTime Function()? now,
    VoidCallback? onRefreshNeeded,
    AccountParty? accountParty,
    bool? accountChoice,
  }) {
    return showDialog<FinancePaymentOutcome>(
      context: context,
      barrierDismissible: false,
      builder: (_) => FinancePaymentDialog(
        scope: scope,
        apartmentId: apartmentId,
        apartmentLabel: apartmentLabel,
        correcting: correcting,
        now: now,
        onRefreshNeeded: onRefreshNeeded,
        accountParty: accountParty,
        accountChoice: accountChoice,
      ),
    );
  }

  @override
  State<FinancePaymentDialog> createState() => _FinancePaymentDialogState();
}

class _FinancePaymentDialogState extends State<FinancePaymentDialog> with FinanceDiscardGuard {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final GlobalKey _apartmentKey = GlobalKey();
  final GlobalKey _methodKey = GlobalKey();
  // Seçici ve yöntem çipleri odak düğümü almaz: sarmalayıcı düğümle altlarındaki ilk odaklanabilir öğeye gidilir.
  final FocusNode _apartmentFocus = FocusNode(skipTraversal: true, canRequestFocus: false);
  final FocusNode _methodFocus = FocusNode(skipTraversal: true, canRequestFocus: false);
  late final TextEditingController _amount = TextEditingController(
    text: widget.correcting == null
        ? ''
        : formatMinor(widget.correcting!.amountMinor.abs(), symbol: false),
  );
  late final TextEditingController _date = TextEditingController(
    text: formatDateField(widget.correcting?.entryDate ?? _today()),
  );
  late final TextEditingController _note = TextEditingController(
    text: widget.correcting?.description ?? '',
  );
  late PaymentMethod? _method = widget.correcting?.method;
  late ({int id, String label})? _apartment = widget.apartmentId == null
      ? null
      : (id: widget.apartmentId!, label: widget.apartmentLabel ?? 'Daire');
  late final IdempotencyKeys _keys = sessionIdempotencyKeys(widget.scope.authService, 'pay');
  final RetryLock _retry = RetryLock();

  // Faz 4b: kasa / banka hesabı seçimi (yalnız yeni tahsilatta).
  final GlobalKey _accountKey = GlobalKey();
  final FocusNode _accountFocus = FocusNode(skipTraversal: true, canRequestFocus: false);
  CashOverview? _cash;
  bool _cashLoading = false;
  String? _cashError;
  int? _accountId;
  bool _accountTouched = false;
  String? _accountError;
  int _cashToken = 0;

  // Düzeltmede hesap İSTEĞE BAĞLIDIR (eski ödemenin hesabı kullanılır); eski ödeme hesaba eşlenmemişse sunucu hesap ister
  // (ACCOUNT_REQUIRED): o zaman seçim zorunlu olur.
  bool _accountRequiredByServer = false;

  // İP-1A: daire hesabı (ev sahibi / kiracı). Seçim yalnız iki hesaplı dairede gösterilir; aksi halde gövdede gönderilmez.
  final GlobalKey _partyKey = GlobalKey();
  final FocusNode _partyFocus = FocusNode(skipTraversal: true, canRequestFocus: false);
  late AccountParty? _party = widget.accountParty ?? widget.correcting?.accountParty;
  late bool _partyChoice = widget.accountChoice ?? false;
  bool _partyLoading = false;
  String? _partyError;
  int _partyToken = 0;

  bool _submitting = false;
  bool _picking = false;
  bool _needsRefreshOnClose = false;
  bool _dateOverflow = false;
  String? _error;
  String? _apartmentError;
  String? _methodError;
  FinancePeriods? _periods;

  bool get _correcting => widget.correcting != null;

  @override
  bool get closeLocked => _submitting;

  DateTime _today() {
    final wall = istanbulNow(widget.now?.call());
    return DateTime(wall.year, wall.month, wall.day);
  }

  @override
  void initState() {
    super.initState();
    unawaited(_loadPeriods());
    unawaited(_loadAccounts());
    // Hesap bilgisi verilmedi (ekstre dışından açıldı) ve daire hazır: iki hesaplı mı sunucuya sorulur.
    if (widget.accountChoice == null && widget.apartmentId != null) unawaited(_probeParties(widget.apartmentId!));
  }

  /// İP-1A: dairenin iki hesabı var mı ve varsayılan tahsilat hesabı ne (ekstrenin ilk satırı yeterli). Hata sessizdir:
  /// seçim gösterilmez ve sunucu hesabı kendisi seçer (eski istemcinin davranışı).
  Future<void> _probeParties(int apartmentId) async {
    final token = ++_partyToken;
    setState(() => _partyLoading = true);
    try {
      final view = await widget.scope.authService.getFinanceAccount(widget.scope.siteCode, apartmentId, limit: 1);
      if (!mounted || token != _partyToken) return;
      setState(() {
        _partyLoading = false;
        _partyChoice = view.hasTwoAccounts;
        _party = view.hasTwoAccounts ? (_party ?? view.defaultPaymentAccount) : null;
      });
    } catch (_) {
      if (!mounted || token != _partyToken) return;
      setState(() {
        _partyLoading = false;
        _partyChoice = false;
        _party = null;
      });
    }
  }

  @override
  void dispose() {
    ++_cashToken;
    ++_partyToken;
    _partyFocus.dispose();
    _accountFocus.dispose();
    _retry.dispose();
    _apartmentFocus.dispose();
    _methodFocus.dispose();
    _amount.dispose();
    _date.dispose();
    _note.dispose();
    super.dispose();
  }

  /// Kapalı ay uyarısı için dönem bilgisini yüklemeye çalışır; başarısızlık sessizdir (yalnız bilgilendirmedir,
  /// kesin karar kaydetme anında sunucudadır).
  Future<void> _loadPeriods() async {
    try {
      final periods = await widget.scope.authService.getFinancePeriods(widget.scope.siteCode);
      if (!mounted) return;
      setState(() => _periods = periods);
    } catch (_) {
      // Uyarı gösterilmez; kayıt yine denenebilir.
    }
  }

  /// Aktif kasa / banka hesapları.
  List<CashAccount> get _activeAccounts => _cash?.activeAccounts ?? const <CashAccount>[];

  static bool _openedBy(CashAccount account, DateTime? date) =>
      date == null || account.openingDate == null || !account.openingDate!.isAfter(date);

  /// Seçilen tarihte kullanılabilir hesaplar: aktif VE açılış tarihi tahsilat tarihinden önce ya da aynı gün (sunucu:
  /// `opening_date <= entry_date`; aksi halde BEFORE_OPENING_DATE).
  List<CashAccount> get _selectableAccounts {
    final date = parseDateField(_date.text);
    return <CashAccount>[
      for (final a in _activeAccounts)
        if (_openedBy(a, date)) a,
    ];
  }

  /// Tarihte açık (açılışı gelmiş) hesap var ama HEPSİ pasif: sunucu hesapsız tahsilatı da kabul etmez (ACCOUNT_INACTIVE).
  bool get _allAccountsInactiveForDate {
    final items = _cash?.items ?? const <CashAccount>[];
    final date = parseDateField(_date.text);
    final opened = items.where((a) => _openedBy(a, date)).toList();
    return opened.isNotEmpty && !opened.any((a) => a.isActive);
  }

  /// Yeni tahsilatta tarihte kullanılabilir hesap varsa hesap ZORUNLU (sunucu ACCOUNT_REQUIRED); tahsilat tarihi tüm hesapların
  /// açılışından ÖNCEYSE hesap sorulmaz (4a gibi hesapsız yazılır). Düzeltmede yalnız sunucu isterse zorunlu.
  bool get _accountRequired {
    if (_selectableAccounts.isEmpty) return false;
    return !_correcting || _accountRequiredByServer;
  }

  /// Tarih değişince artık kullanılamayan hesap seçimi bırakılır.
  void _syncAccountToDate() {
    final selectable = _selectableAccounts;
    if (_accountId != null && !selectable.any((a) => a.id == _accountId)) {
      _accountId = null;
      _accountTouched = false;
    }
    if (_accountId == null && selectable.length == 1 && !_correcting) _accountId = selectable.first.id;
    if (_accountId == null && !_correcting) _suggestAccount();
  }

  Future<void> _loadAccounts() async {
    if (!mounted) return;
    final token = ++_cashToken;
    setState(() {
      _cashLoading = true;
      _cashError = null;
    });
    try {
      final overview = await widget.scope.f4Call((api, t, s) => api.listAccounts(token: t, siteCode: s));
      if (!mounted || token != _cashToken) return;
      setState(() {
        _cash = overview;
        _cashLoading = false;
        final active = _selectableAccounts;
        if (_accountId != null && !active.any((a) => a.id == _accountId)) _accountId = null;
        // Düzeltmede hesap önceden seçilmez (eski ödemenin hesabı kullanılır); yeni tahsilatta tek hesap ön seçilir.
        if (!_correcting) {
          if (_accountId == null && active.length == 1) _accountId = active.first.id;
          if (_accountId == null) _suggestAccount();
        }
      });
    } catch (e) {
      if (!mounted || token != _cashToken) return;
      setState(() {
        _cashLoading = false;
        _cashError = financeMessageOf(
          e,
          'Kasa ve banka hesapları yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
        );
      });
    }
  }

  /// Yönteme göre ÖNERİ (kullanıcı kendisi seçtiyse dokunulmaz): nakit -> kasa, havale / çek -> banka.
  void _suggestAccount() {
    if (_accountTouched || _correcting) return; // düzeltmede hesap önerilmez (eski ödemenin hesabı kullanılır)
    final method = _method;
    final active = _selectableAccounts;
    if (method == null || active.isEmpty) return;
    final wanted = method == PaymentMethod.cash ? CashAccountKind.cash : CashAccountKind.bank;
    for (final account in active) {
      if (account.kind == wanted) {
        _accountId = account.id;
        return;
      }
    }
  }

  Future<void> _pickApartment() async {
    if (_picking || _submitting) return;
    _picking = true;
    try {
      final picked = await showApartmentPicker(context, widget.scope);
      if (picked == null || !mounted) return;
      markDirty();
      final changed = _apartment?.id != picked.id;
      setState(() {
        _apartment = (id: picked.id, label: picked.fullLabel);
        _apartmentError = null;
        if (changed) {
          // Daire değişti: önceki dairenin hesap seçimi geçmez; yeni dairenin hesapları sorulur.
          _party = null;
          _partyChoice = false;
          _partyError = null;
        }
      });
      if (changed) unawaited(_probeParties(picked.id));
    } finally {
      _picking = false;
    }
  }

  String? _validateDate(String? value) {
    if ((value ?? '').trim().isEmpty) return 'Tahsilat tarihini girin.';
    final format = validateDateField(value);
    if (format != null) return format;
    final date = parseDateField(value)!;
    final today = _today();
    if (date.isAfter(today)) return 'Tarih bugünden ileri olamaz.';
    // Sunucu sınırı: tarih bugünden en fazla 5 yıl öncesi olabilir (29 Şubat -> 28 Şubat).
    final oldest = DateTime(today.year - 5, today.month, today.month == 2 && today.day == 29 ? 28 : today.day);
    if (date.isBefore(oldest)) return 'Tarih bugünden en fazla 5 yıl öncesi olabilir.';
    return null;
  }

  /// Seçilen tarihin ayı kapalıysa (dönem bilgisi yüklüyse) bilgi amaçlı uyarı; yoksa null.
  String? _closedMonthWarning() {
    final through = _periods?.closedThrough;
    final date = parseDateField(_date.text);
    if (through == null || date == null) return null;
    if (FinancePeriod.of(date) > through) return null;
    return 'Bu ay kapatılmış olabilir. Kapalı aya tahsilat eklenemez; tarihi kontrol edin.';
  }

  /// Yazılırken 8 rakamdan fazlası eklenemez: sessiz reddetme olmasın, uyarı gösterilir ve duyurulur.
  void _onDateRejected() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _dateOverflow = true);
      announcePolite(context, 'Tarih en çok 8 rakamdır. Fazla rakam eklenmedi.');
    });
  }

  /// Daire / yöntem seçimi eksikse hatayı alanın altında gösterir; ikisi de tamamsa true.
  bool _validateChoices() {
    final accountMissing = _accountRequired && _accountId == null;
    final partyMissing = _partyChoice && _party == null;
    setState(() {
      _apartmentError = _apartment == null ? 'Daire seçin.' : null;
      _methodError = _method == null ? 'Tahsilat yöntemini seçin.' : null;
      _accountError = accountMissing ? 'Tahsilatın gireceği hesabı seçin.' : null;
      _partyError = partyMissing ? 'Tahsilatın yazılacağı daire hesabını seçin.' : null;
    });
    return _apartment != null && _method != null && !accountMissing && !partyMissing;
  }

  bool _showAndFocus(GlobalKey key, FocusNode focus) {
    final target = key.currentContext;
    if (target == null) return false;
    Scrollable.ensureVisible(target, alignment: 0.15, duration: Duration.zero);
    focusFirstWithin(focus);
    return true;
  }

  /// Ekrandaki sıraya göre İLK sorunu görünür kılar: daire, sonra alan hataları (tutar, tarih), sonra yöntem.
  void _revealFirstProblem(BuildContext formContext) {
    if (_apartmentError != null && _showAndFocus(_apartmentKey, _apartmentFocus)) return;
    if (_partyError != null && _showAndFocus(_partyKey, _partyFocus)) return;
    if (revealFirstInvalidField(formContext)) return;
    if (_methodError != null && _showAndFocus(_methodKey, _methodFocus)) return;
    if (_accountError != null) _showAndFocus(_accountKey, _accountFocus);
  }

  Future<void> _submit() async {
    if (_submitting || _retry.locked) return;
    final fieldsOk = validateForm(
      _formKey,
      validateExtra: _validateChoices,
      reveal: _revealFirstProblem,
    );
    final apartment = _apartment;
    final method = _method;
    if (!fieldsOk || apartment == null || method == null) {
      setState(() => _error = kFixFieldsMessage);
      return;
    }
    final minor = parseMoney(_amount.text).minor;
    final date = parseDateField(_date.text);
    if (minor == null || date == null) {
      setState(() => _error = kFixFieldsMessage);
      return;
    }
    final note = _note.text.trim();
    final correcting = widget.correcting;
    // Veri imzası: aynı veriyle yeniden deneme AYNI anahtarı, değişen veri yeni anahtarı kullanır. Açıklama
    // imzada YOKTUR (yalnız metni düzeltmek yeni kayıt anahtarı üretmez).
    final useAccounts = _accountId != null && _selectableAccounts.any((a) => a.id == _accountId);
    final accountId = useAccounts ? _accountId : null;
    // İP-1A: daire hesabı yalnız seçim gösterildiyse gider (aksi halde sunucu seçer); imzada yer alır (farklı hesap = yeni anahtar).
    final party = _partyChoice ? _party : null;
    final signature =
        '${widget.scope.siteCode}|${correcting?.id ?? 0}|${apartment.id}|$minor|${crmDateParam(date)}|${method.apiValue}|${accountId ?? 0}'
        '${party == null ? '' : '|${party.apiValue}'}';
    final key = _keys.keyFor(signature);

    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final auth = widget.scope.authService;
      final siteCode = widget.scope.siteCode;
      final LedgerWriteResult result;
      if (correcting == null && useAccounts) {
        // Hesap seçimli tahsilat (Faz 4b): kayıt + hesap hareketi + makbuz TEK işlemde.
        result = await widget.scope.f4Call(
          (api, t, s) => api.recordPayment(
            token: t,
            siteCode: s,
            apartmentId: apartment.id,
            amountMinor: minor,
            entryDate: date,
            method: method,
            description: note,
            accountId: accountId,
            idempotencyKey: key,
            accountParty: party,
          ),
        );
      } else if (correcting != null && useAccounts) {
        // Düzeltme + hesap seçildi (eski ödeme hesaba eşlenmemişti ya da hesap değişiyor): hesap gövdede gider.
        result = await widget.scope.f4Call(
          (api, t, s) => api.correctPayment(
            token: t,
            siteCode: s,
            entryId: correcting.id,
            amountMinor: minor,
            entryDate: date,
            method: method,
            description: note,
            accountId: accountId,
            idempotencyKey: key,
            accountParty: party,
          ),
        );
      } else if (correcting == null) {
        result = await auth.recordFeePayment(
          siteCode,
          apartmentId: apartment.id,
          amountMinor: minor,
          entryDate: date,
          method: method,
          description: note,
          idempotencyKey: key,
          accountParty: party,
        );
      } else {
        result = await auth.correctFinancePayment(
          siteCode,
          correcting.id,
          amountMinor: minor,
          entryDate: date,
          method: method,
          description: note,
          idempotencyKey: key,
          accountParty: party,
        );
      }
      // Yazma tamamlandı: bu imzanın anahtarı atılır (aynı tutardaki sonraki gerçek tahsilat yeni anahtar alır).
      _keys.clear(signature);
      if (!mounted) return;
      _needsRefreshOnClose = false; // sonuçla kapanır: çağıran zaten günceller
      final balance = result.balanceMinor;
      final head = _correcting
          ? 'Tahsilat düzeltildi: ${formatMinor(minor)}.'
          : 'Tahsilat kaydedildi: ${formatMinor(minor)}.';
      // İP-1A: iki hesaplı dairede tahsilatın yazıldığı HESABIN bakiyesi yazılır (iki hesabın toplamı yanıltıcıdır).
      final paidParty = result.entry.accountParty;
      final accountBalance = result.accountBalanceMinor;
      final String message;
      if (_partyChoice && paidParty != null && accountBalance != null) {
        message = '$head ${paidParty.label}: ${describeBalance(accountBalance).badgeText}.';
      } else {
        message = balance == null ? head : '$head Güncel bakiye: ${describeBalance(balance).badgeText}.';
      }
      popIfCurrent(context, FinancePaymentOutcome(result: result, message: message));
    } catch (e) {
      if (financeOutcomeUncertain(e)) _needsRefreshOnClose = true;
      // Sunucu aynı anahtarı farklı bilgiyle zaten kaydetmiş: bu imzanın anahtarı atılır; kayıt oluşmuş olabilir,
      // liste kapanırken tazelenir ve kullanıcıya hesabı kontrol etmesi söylenir.
      if (hasErrorCode(e, 'IDEMPOTENCY_CONFLICT')) {
        _keys.clear(signature);
        _needsRefreshOnClose = true;
      }
      // Sunucu hesap istiyor ama liste henüz yüklenmemişti / pasif hesap seçilmişti: hesaplar yeniden okunur.
      if (hasErrorCode(e, 'ACCOUNT_REQUIRED') || hasErrorCode(e, 'ACCOUNT_INACTIVE')) {
        if (_correcting && hasErrorCode(e, 'ACCOUNT_REQUIRED')) _accountRequiredByServer = true;
        unawaited(_loadAccounts());
      }
      if (!mounted) return;
      final limited = _retry.lockIfRateLimited(e, () {
        if (mounted) setState(() {});
      });
      setState(() {
        _submitting = false;
        _error = limited
            ? RetryLock.messageFor(e)
            : financeWriteMessage(
                e,
                _correcting
                    ? 'Tahsilat düzeltilemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.'
                    : 'Tahsilat kaydedilemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
              );
      });
    }
  }

  void _notifyRefreshOnClose() {
    if (!_needsRefreshOnClose) return;
    _needsRefreshOnClose = false;
    widget.onRefreshNeeded?.call();
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final correcting = widget.correcting;
    final closedWarning = _closedMonthWarning();
    return PopScope(
      // Gönderim sürerken geri tuşu pencereyi kapatmaz (işlem yarıda kalmış gibi görünmesin).
      canPop: canPopNow,
      onPopInvokedWithResult: (didPop, _) {
        handleBlockedPop(didPop);
        if (didPop) _notifyRefreshOnClose();
      },
      child: AppDialog(
        title: _correcting ? 'Tahsilatı Düzelt' : 'Tahsilat Ekle',
        subtitle: widget.scope.siteName.isEmpty ? null : widget.scope.siteName,
        icon: _correcting ? Icons.edit_rounded : Icons.payments_rounded,
        tone: AppTone.success,
        actions: [
          TextButton(
            onPressed: _submitting ? null : requestClose,
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            key: const ValueKey<String>('finance_payment_submit'),
            onPressed: (_submitting || _retry.locked) ? null : _submit,
            child: Text(_submitting ? 'Kaydediliyor...' : (_correcting ? 'Düzelt' : 'Kaydet')),
          ),
        ],
        child: Form(
          key: _formKey,
          onChanged: markDirty,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) FinanceSubmitError(message: _error!),
              if (correcting != null) ...[
                DialogPanel(
                  key: const ValueKey<String>('finance_payment_original'),
                  tone: AppTone.info,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const DialogSectionTitle(
                        icon: Icons.history_rounded,
                        title: 'Düzeltilen kayıt',
                        tone: AppTone.info,
                      ),
                      const SizedBox(height: AppSpace.sm),
                      Builder(
                        builder: (context) {
                          final summary =
                              '${formatCrmDate(correcting.entryDate)} • '
                              '${formatMinor(correcting.amountMinor.abs())}'
                              '${correcting.method == null ? '' : ' • ${correcting.method!.label}'}';
                          // Tutar ekran okuyucuya "bin iki yüz elli lira" diye okunur.
                          return Text(
                            summary,
                            semanticsLabel: spokenMoneyText(summary),
                            style: th.bodyMedium,
                          );
                        },
                      ),
                      const SizedBox(height: AppSpace.xs),
                      Text(
                        'Bu kayıt silinmez: ters kayıtla iptal edilir ve aşağıdaki bilgilerle yeni bir '
                        'tahsilat yazılır. İkisi tek işlemde yapılır.',
                        style: th.bodySmall?.copyWith(color: p.textSecondary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpace.md),
              ],
              KeyedSubtree(
                key: _apartmentKey,
                child: Focus(
                  focusNode: _apartmentFocus,
                  child: CrmPickerField(
                    key: const ValueKey<String>('finance_payment_apartment'),
                    label: 'Daire',
                    icon: Icons.apartment_rounded,
                    value: _apartment?.label,
                    placeholder: 'Daire seçmek için dokunun',
                    errorText: _apartmentError,
                    enabled: !_submitting && !_correcting && widget.apartmentId == null,
                    onTap: _pickApartment,
                  ),
                ),
              ),
              if (_partyLoading && !_partyChoice) ...[
                const SizedBox(height: AppSpace.sm),
                const DialogLoadingNote(text: 'Daire hesapları yükleniyor...'),
              ],
              if (_partyChoice) ...[
                const SizedBox(height: AppSpace.md),
                KeyedSubtree(
                  key: _partyKey,
                  child: Focus(
                    focusNode: _partyFocus,
                    child: AccountPartyChoice(
                      key: const ValueKey<String>('finance_payment_party'),
                      selected: _party,
                      enabled: !_submitting,
                      keyPrefix: 'finance_payment_party',
                      note: _correcting
                          ? 'Düzeltilen tahsilat seçilen hesaba yazılır; eski kaydın ters kaydı kendi hesabında kalır.'
                          : 'Tahsilat yalnız seçilen hesabın borcundan düşer; iki hesap birbirine karışmaz.',
                      onSelected: (value) => setState(() {
                        if (value == null) return;
                        markDirty();
                        _party = value;
                        _partyError = null;
                      }),
                    ),
                  ),
                ),
                if (_partyError != null) ...[
                  const SizedBox(height: AppSpace.sm),
                  CrmFormError(message: _partyError!, reveal: false),
                ],
              ],
              const SizedBox(height: AppSpace.md),
              MoneyFormField(
                key: const ValueKey<String>('finance_payment_amount_group'),
                fieldKey: const ValueKey<String>('finance_payment_amount'),
                controller: _amount,
                enabled: !_submitting,
                label: 'Tahsilat tutarı',
                helperText: 'Borçtan fazla ödeme alacak olarak görünür.',
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: AppSpace.md),
              TextFormField(
                key: const ValueKey<String>('finance_payment_date'),
                controller: _date,
                enabled: !_submitting,
                keyboardType: TextInputType.number,
                inputFormatters: [DateInputFormatter(onRejected: _onDateRejected)],
                autovalidateMode: AutovalidateMode.onUserInteraction,
                onChanged: (_) => setState(() {
                  _dateOverflow = false;
                  _syncAccountToDate();
                }),
                decoration: InputDecoration(
                  labelText: 'Tahsilat tarihi',
                  hintText: 'GG.AA.YYYY',
                  helperText: _dateOverflow
                      ? 'Tarih en çok 8 rakamdır (GG.AA.YYYY); fazla rakam eklenmedi.'
                      : 'Gün.Ay.Yıl biçiminde yazın (GG.AA.YYYY).',
                  helperMaxLines: 3,
                  helperStyle: _dateOverflow
                      ? TextStyle(color: AppTone.warning.ink(p), fontWeight: FontWeight.w700)
                      : null,
                  prefixIcon: const Icon(Icons.event_rounded),
                ),
                validator: _validateDate,
              ),
              if (closedWarning != null) ...[
                const SizedBox(height: AppSpace.sm),
                InlineNotice(
                  key: const ValueKey<String>('finance_payment_closed_month'),
                  tone: AppTone.warning,
                  message: closedWarning,
                ),
              ],
              const SizedBox(height: AppSpace.lg),
              const FinanceGroupTitle('Yöntem'),
              const SizedBox(height: AppSpace.sm),
              KeyedSubtree(
                key: _methodKey,
                child: Focus(
                  focusNode: _methodFocus,
                  child: Wrap(
                    spacing: AppSpace.sm,
                    runSpacing: AppSpace.sm,
                    children: [
                      for (final method in PaymentMethod.values)
                        ChoiceChip(
                          key: ValueKey<String>('finance_method_${method.apiValue}'),
                          avatar: Icon(_methodIcon(method), size: 18),
                          label: Text(method.label),
                          selected: _method == method,
                          onSelected: _submitting
                              ? null
                              : (_) => setState(() {
                                  markDirty();
                                  _method = method;
                                  _methodError = null;
                                  _suggestAccount();
                                }),
                        ),
                    ],
                  ),
                ),
              ),
              if (_methodError != null) ...[
                const SizedBox(height: AppSpace.sm),
                CrmFormError(message: _methodError!, reveal: false),
              ],
              ..._buildAccountSection(context),
              const SizedBox(height: AppSpace.md),
              TextFormField(
                key: const ValueKey<String>('finance_payment_note'),
                controller: _note,
                enabled: !_submitting,
                minLines: 2,
                maxLines: 4,
                maxLength: FinancePaymentDialog.maxNoteLength,
                maxLengthEnforcement: MaxLengthEnforcement.none,
                buildCounter: (context, {required currentLength, required isFocused, maxLength}) =>
                    characterCounter(
                      context,
                      _note.text.trim().runes.length,
                      FinancePaymentDialog.maxNoteLength,
                    ),
                textCapitalization: TextCapitalization.sentences,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                decoration: const InputDecoration(
                  labelText: 'Açıklama (isteğe bağlı)',
                  alignLabelWithHint: true,
                  prefixIcon: Icon(Icons.notes_rounded),
                ),
                validator: (value) {
                  if (trimmedCodePoints(value ?? '') > FinancePaymentDialog.maxNoteLength) {
                    return 'Açıklama en çok ${FinancePaymentDialog.maxNoteLength} karakter olabilir.';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildAccountSection(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    if (_cashLoading && _cash == null) {
      return const [
        SizedBox(height: AppSpace.lg),
        DialogLoadingNote(text: 'Kasa ve banka hesapları yükleniyor...'),
      ];
    }
    if (_cashError != null && _cash == null) {
      return [
        const SizedBox(height: AppSpace.lg),
        InlineNotice(
          key: const ValueKey<String>('finance_payment_accounts_error'),
          tone: AppTone.warning,
          message: _cashError!,
          onRetry: _loadAccounts,
        ),
      ];
    }
    final active = _selectableAccounts;
    if (_allAccountsInactiveForDate) {
      return const [
        SizedBox(height: AppSpace.lg),
        InlineNotice(
          key: ValueKey<String>('finance_payment_accounts_inactive'),
          tone: AppTone.warning,
          message:
              'Tüm kasa ve banka hesapları pasif. Tahsilat girmek için önce Kasa bölümünden bir hesabı yeniden etkinleştirin.',
        ),
      ];
    }
    if (active.isEmpty) {
      // Tarih tüm hesapların açılışından önceyse tahsilat hesaba işlenmez (4a gibi); kullanıcı nedenini bilsin.
      if (_activeAccounts.isEmpty) return const <Widget>[];
      return const [
        SizedBox(height: AppSpace.lg),
        InlineNotice(
          key: ValueKey<String>('finance_payment_before_opening'),
          tone: AppTone.info,
          message: 'Seçilen tarih kasa / banka hesaplarının açılış tarihinden önce; bu tahsilat bir hesaba işlenmeyecek.',
        ),
      ];
    }
    return [
      const SizedBox(height: AppSpace.lg),
      const FinanceGroupTitle('Hesap'),
      const SizedBox(height: AppSpace.xs),
      Text(
        _correcting && !_accountRequiredByServer
            ? 'İsteğe bağlı: eski tahsilat bir hesaba işlenmişse aynı hesap kullanılır. İşlenmemişse yeni tahsilat için hesap seçin.'
            : 'Tahsilat seçtiğiniz kasa ya da banka hesabına işlenir.',
        style: th.bodySmall?.copyWith(color: p.textSecondary),
      ),
      const SizedBox(height: AppSpace.sm),
      KeyedSubtree(
        key: _accountKey,
        child: Focus(
          focusNode: _accountFocus,
          child: Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: [
              for (final account in active)
                ChoiceChip(
                  key: ValueKey<String>('finance_payment_account_${account.id}'),
                  avatar: Icon(cashKindIcon(account.kind), size: 18),
                  label: Text(account.name),
                  selected: _accountId == account.id,
                  onSelected: _submitting
                      ? null
                      : (_) => setState(() {
                          // Düzeltmede seçili çipe yeniden dokunmak seçimi kaldırır (hesap isteğe bağlı).
                          markDirty();
                          final unselect = _correcting && !_accountRequiredByServer && _accountId == account.id;
                          _accountId = unselect ? null : account.id;
                          _accountTouched = true;
                          _accountError = null;
                        }),
                ),
            ],
          ),
        ),
      ),
      if (_accountError != null) ...[
        const SizedBox(height: AppSpace.sm),
        CrmFormError(message: _accountError!, reveal: false),
      ],
    ];
  }

  static IconData _methodIcon(PaymentMethod method) => switch (method) {
    PaymentMethod.cash => Icons.payments_rounded,
    PaymentMethod.transfer => Icons.account_balance_rounded,
    PaymentMethod.cheque => Icons.receipt_rounded,
  };
}
