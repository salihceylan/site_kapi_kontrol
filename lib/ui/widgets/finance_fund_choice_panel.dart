import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/finance.dart' show AccountParty;
import 'package:site_kapi_kontrol/models/finance_funds.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/large_dialog_parts.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_4b_access.dart';
import 'package:site_kapi_kontrol/ui/helpers/fund_text.dart';
import 'package:site_kapi_kontrol/ui/helpers/money.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_fund_parts.dart';

/// Tahsilatın gireceği İşletme / Fon hesabının seçimi (K3, karşılaştırma raporu P1-3): "Yazılım ödemeyi kendiliğinden bir hesaba
/// atamaz." Elle tahsilat, dekont onayı ve banka satırı pencereleri aynı parçayı kullanır; kural SUNUCUDADIR (iki türün de açık borcu
/// olan hesapta seçimsiz kayıt 400 `FUND_CHOICE_REQUIRED`), bu parça yalnız kullanıcıya önceden gösterir:
/// - İKİ türün de (İşletme + Fon) açık borcu varsa seçim ZORUNLUDUR: önceden seçili gelmez, "Otomatik" yoktur; otomatik dağıtımın ne yapacağı
///   yalnız bilgi olarak yazılır (tutar verildiyse).
/// - Yalnız BİR türün açık borcu varsa o hesap seçili gelir (önerilen); yönetici değiştirebilir.
/// - Açık borç yoksa seçim isteğe bağlıdır; seçilmezse tutar genel avans olur.
/// - Bilgi alınamazsa uyarı + "Tekrar Dene" yazılır ve kayıt engellenmez (sunucu gerekirse seçim ister: [forcedInfo]).
///
/// Bilgi sunucudan [scope] ile okunur ([load] true iken, daire / hesap değişince yeniden). [load] false iken (tahsilat DÜZELTME: asıl kayıt hâlâ
/// defterdedir, okunan durum yanıltır) sunucu bilgisi okunmaz; chooser eski kurallarla çizilir ve sunucu 400 verirse [forcedInfo] ile "zorunlu"ya geçilir.
///
/// Taşma yok: seçenek satırları [FundChoice] içinde sarar. Kasa sözcüğü kullanılmaz; adlar [FinanceFund.label] / [FinanceFund.shortLabel].
class FundChoicePanel extends StatefulWidget {
  const FundChoicePanel({
    super.key,
    required this.scope,
    required this.apartmentId,
    required this.selected,
    required this.onChanged,
    this.accountParty,
    this.amountMinor,
    this.paidOn,
    this.load = true,
    this.loader,
    this.forcedInfo,
    this.onStateChanged,
    this.enabled = true,
    this.errorText,
    this.keyPrefix = 'fund_choice',
    this.title = 'İşletme / Fon hesabı',
    this.legacyAllowAuto = true,
    this.legacyFooter,
  });

  final PeopleScope scope;

  /// Tahsilatın dairesi; null iken (daire henüz seçilmedi) parça çizilmez.
  final int? apartmentId;

  /// Seçili İşletme / Fon hesabı (null: seçilmedi).
  final FinanceFund? selected;
  final ValueChanged<FinanceFund?> onChanged;

  /// Daire hesabı (ev sahibi / kiracı); null ise sunucu tahsilat hesabını kendi kuralıyla seçer.
  final AccountParty? accountParty;

  /// Tahsilat tutarı (kuruş): iki türlü borçta otomatik dağıtım önerisini (yalnız bilgi) getirmek için. Değişince kısa gecikmeyle yenilenir.
  final int? amountMinor;
  final DateTime? paidOn;

  /// false: sunucu bilgisi okunmaz (tahsilat düzeltme); chooser [legacyAllowAuto] / [legacyFooter] ile çizilir.
  final bool load;

  /// Testlerde sahte yükleyici; verilmezse `GET payments/fund-choice`.
  final Future<FundChoiceInfo> Function({required int apartmentId, AccountParty? accountParty, int? amountMinor, DateTime? paidOn})? loader;

  /// Sunucunun 400 `FUND_CHOICE_REQUIRED` yanıtından okunan (yetkili) durum; verilirse yüklenen bilginin yerine geçer.
  final FundChoiceInfo? forcedInfo;

  /// Bilgi / yükleme durumu değişince üst pencereye bildirilir (kayıt öncesi doğrulama için).
  final ValueChanged<FundChoiceState>? onStateChanged;
  final bool enabled;
  final String? errorText;
  final String keyPrefix;
  final String title;

  /// [load] false iken "Otomatik" satırı sunulsun mu (kısıtlı asıl tahsilatta sunulmaz).
  final bool legacyAllowAuto;

  /// [load] false iken seçeneklerin altındaki açıklama.
  final String? legacyFooter;

  @override
  State<FundChoicePanel> createState() => _FundChoicePanelState();
}

/// [FundChoicePanel]'in dışarıya bildirdiği durum.
@immutable
class FundChoiceState {
  const FundChoiceState({this.info, this.loading = false, this.failed = false});

  final FundChoiceInfo? info;
  final bool loading;
  final bool failed;

  /// İki türün de açık borcu var: seçim zorunlu.
  bool get required => info?.choiceRequired == true;

  @override
  bool operator ==(Object other) => other is FundChoiceState && other.info == info && other.loading == loading && other.failed == failed;

  @override
  int get hashCode => Object.hash(info, loading, failed);
}

class _FundChoicePanelState extends State<FundChoicePanel> {
  FundChoiceInfo? _info;
  bool _loading = false;
  bool _failed = false;
  bool _touched = false;
  int _token = 0;
  Timer? _debounce;

  FundChoiceInfo? get _effective => widget.forcedInfo ?? _info;

  @override
  void initState() {
    super.initState();
    if (widget.load && widget.apartmentId != null) {
      _later(() => unawaited(_load()));
    }
  }

  @override
  void didUpdateWidget(FundChoicePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final contextChanged = oldWidget.apartmentId != widget.apartmentId || oldWidget.accountParty != widget.accountParty;
    if (contextChanged) {
      // Yeni daire / hesap: eski bilgi ve eski seçim geçmez; bekleyen yanıt atılır.
      ++_token;
      _debounce?.cancel();
      _touched = false;
      _info = null;
      _failed = false;
      _loading = false;
      _later(() {
        // Seçim yeni bağlamda geçmez. Sıfırlama ve yükleme SIRAYLA yapılır: yanıt sıfırlamadan önce gelip önerinin üzerine yazılmasın.
        if (widget.load && widget.selected != null) widget.onChanged(null);
        if (widget.load && widget.apartmentId != null) {
          unawaited(_load());
        } else {
          _notify();
        }
      });
    } else if (oldWidget.forcedInfo != widget.forcedInfo) {
      _later(_notify);
    } else if (widget.load && oldWidget.amountMinor != widget.amountMinor && _info?.choiceRequired == true) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 600), () {
        if (mounted) unawaited(_load(silent: true));
      });
    }
  }

  @override
  void dispose() {
    ++_token;
    _debounce?.cancel();
    super.dispose();
  }

  /// Çerçeve içinde (build sırasında) üst pencerenin setState'ini tetiklememek için bir sonraki kareye ertelenir.
  void _later(VoidCallback action) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) action();
    });
  }

  void _notify() {
    widget.onStateChanged?.call(FundChoiceState(info: _effective, loading: _loading, failed: _failed));
  }

  Future<FundChoiceInfo> _fetch(int apartmentId) {
    final loader = widget.loader;
    if (loader != null) {
      return loader(apartmentId: apartmentId, accountParty: widget.accountParty, amountMinor: widget.amountMinor, paidOn: widget.paidOn);
    }
    return widget.scope.f4Call(
      (api, token, siteCode) => api.getFundChoice(
        token: token,
        siteCode: siteCode,
        apartmentId: apartmentId,
        accountParty: widget.accountParty,
        amountMinor: widget.amountMinor,
        paidOn: widget.paidOn,
      ),
    );
  }

  Future<void> _load({bool silent = false}) async {
    final apartmentId = widget.apartmentId;
    if (apartmentId == null || !mounted) return;
    final token = ++_token;
    if (!silent) {
      setState(() {
        _loading = true;
        _failed = false;
      });
      _notify();
    }
    try {
      final info = await _fetch(apartmentId);
      if (!mounted || token != _token) return;
      setState(() {
        _info = info;
        _loading = false;
        _failed = false;
      });
      // Tek türün açık borcu varsa önerilen hesap seçili gelir (kullanıcı kendisi seçtiyse dokunulmaz). Bağlam değişiminde eski seçim
      // yukarıda sıfırlanmıştır; bu yüzden `widget.selected` (henüz yeniden kurulmamış olabilir) koşula katılmaz.
      final suggested = info.suggestedFund;
      if (!_touched && suggested != null && widget.forcedInfo == null) widget.onChanged(suggested);
      _notify();
    } catch (_) {
      if (!mounted || token != _token) return;
      setState(() {
        _loading = false;
        _failed = !silent || _info == null;
      });
      _notify();
    }
  }

  String _openNote(FundChoiceInfo info, FinanceFund fund) {
    final open = info.openOf(fund);
    return open > 0 ? 'açık borç ${formatMinor(open)}' : 'açık borç yok';
  }

  @override
  Widget build(BuildContext context) {
    final info = _effective;
    if (widget.load && widget.apartmentId == null && info == null) return const SizedBox.shrink();
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    if (_loading && info == null) {
      return DialogLoadingNote(key: ValueKey<String>('${widget.keyPrefix}_loading'), text: 'İşletme / Fon hesabı bilgisi yükleniyor...');
    }
    final required = info?.choiceRequired == true;
    final noDebt = info != null && !info.hasOpenDebt;
    final suggested = info?.suggestedFund;
    // "Seçmeden" satırı yalnız seçimin zorunlu OLMADIĞI ve önerinin de bulunmadığı durumlarda sunulur: borçsuz hesap, bilgi alınamadı ya da
    // düzeltme (legacy). Tek türde ve iki türde yazılım kendiliğinden atamasın diye sunulmaz.
    final allowAuto = info == null ? (_failed || widget.legacyAllowAuto) : noDebt;
    final String? footer;
    if (info == null) {
      footer = widget.legacyFooter;
    } else if (required) {
      footer = null;
    } else if (suggested != null) {
      footer = 'Açık borç yalnız ${suggested.shortLabel} için; bu hesap seçili geldi, isterseniz değiştirebilirsiniz.';
    } else {
      footer = 'Açık borç yok. Hesap seçmezseniz tutar genel avans olarak kalır ve sonraki borca mahsup edilir.';
    }
    final proposal = info?.proposal;
    return Column(
      key: ValueKey<String>(widget.keyPrefix),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_failed && info == null) ...[
          InlineNotice(
            key: ValueKey<String>('${widget.keyPrefix}_failed'),
            tone: AppTone.warning,
            message: 'İşletme / Fon hesabı bilgisi alınamadı. Yine de kaydedebilirsiniz; iki hesapta da açık borç varsa kayıt sırasında seçim istenir.',
            onRetry: widget.load ? () => unawaited(_load()) : null,
          ),
          const SizedBox(height: AppSpace.sm),
        ],
        if (required && info != null) ...[
          InlineNotice(
            key: ValueKey<String>('${widget.keyPrefix}_required'),
            tone: AppTone.warning,
            message:
                'Bu daire hesabında hem ${FinanceFund.operating.shortLabel} (${formatMinor(info.openOperatingMinor)}) hem '
                '${FinanceFund.capital.shortLabel} (${formatMinor(info.openCapitalMinor)}) için açık borç var. '
                'Ödemenin hangisine işleneceğini siz seçin; yazılım kendiliğinden atamaz.',
            semanticsLabel: spokenMoneyText(
              'Bu daire hesabında hem ${FinanceFund.operating.shortLabel} (${formatMinor(info.openOperatingMinor)}) hem '
              '${FinanceFund.capital.shortLabel} (${formatMinor(info.openCapitalMinor)}) için açık borç var. '
              'Ödemenin hangisine işleneceğini siz seçin; yazılım kendiliğinden atamaz.',
            ),
          ),
          const SizedBox(height: AppSpace.sm),
        ],
        FundChoice(
          key: ValueKey<String>('${widget.keyPrefix}_choice'),
          title: widget.title,
          selected: widget.selected,
          enabled: widget.enabled,
          allowAuto: allowAuto,
          autoLabel: noDebt ? 'Hesap seçmeden (genel avans)' : kFundAutoName,
          autoNote: noDebt ? 'açık borç yok; tutar avans olarak kalır' : 'borçlara en eski vadeden başlayarak dağıtılır',
          keyPrefix: widget.keyPrefix,
          noteFor: (fund) => info == null ? 'yalnız bu hesabın borçlarına uygulanır; fazlası avans olur' : _openNote(info, fund),
          footer: footer,
          errorText: widget.errorText,
          onSelected: (value) {
            _touched = true;
            widget.onChanged(value);
          },
        ),
        if (required && proposal != null) ...[
          const SizedBox(height: AppSpace.xs),
          Text(
            'Bilgi: otomatik dağıtım en eski borçtan başlayarak ${fundSplitText(proposal)} olurdu. '
            'Tutarı iki hesaba bölmek için iki ayrı tahsilat girin.',
            key: ValueKey<String>('${widget.keyPrefix}_proposal'),
            style: th.bodySmall?.copyWith(color: p.textSecondary),
            semanticsLabel: spokenMoneyText(
              'Bilgi: otomatik dağıtım en eski borçtan başlayarak ${fundSplitText(proposal)} olurdu. '
              'Tutarı iki hesaba bölmek için iki ayrı tahsilat girin.',
            ),
          ),
        ],
      ],
    );
  }
}
