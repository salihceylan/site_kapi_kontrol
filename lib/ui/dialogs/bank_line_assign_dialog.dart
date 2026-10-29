// Banka satırını daireye işle (Dalga 2 / 2C): aynı pencerede daire + hesap (kiracı / ev sahibi) seçimi ve "Bu IBAN'ı kaydet".
// Aynı tutarda mevcut bir tahsilat varsa sunucu yeni kayıt açmaz, ona bağlar (çift işleme yok).
// K3 (P1-3): yazılım ödemeyi kendiliğinden İşletme / Fon hesabına atamaz. Dairenin hesabında İKİ türün de açık borcu varsa hangisine işleneceği
// burada SEÇİLİR (seçim olmadan "İşle" gönderilmez; sunucu da 400 FUND_CHOICE_REQUIRED ile reddeder); tek türde önerilen hesap seçili gelir.
import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/bank_import.dart';
import 'package:site_kapi_kontrol/models/finance.dart' show AccountParty;
import 'package:site_kapi_kontrol/models/finance_funds.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/bank_import_api.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/crm_pickers.dart';
import 'package:site_kapi_kontrol/ui/helpers/money.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_fund_choice_panel.dart';

class BankLineAssignDialog extends StatefulWidget {
  const BankLineAssignDialog({super.key, required this.scope, required this.line, this.fundChoiceLoader});

  final PeopleScope scope;
  final BankLineItem line;

  /// K3: İşletme / Fon hesabı bilgisi yükleyicisi (testlerde sahte verilir); null ise `GET payments/fund-choice`.
  final Future<FundChoiceInfo> Function({required int apartmentId, AccountParty? accountParty, int? amountMinor, DateTime? paidOn})? fundChoiceLoader;

  /// İşlenirse true.
  static Future<bool> show(
    BuildContext context, {
    required PeopleScope scope,
    required BankLineItem line,
    Future<FundChoiceInfo> Function({required int apartmentId, AccountParty? accountParty, int? amountMinor, DateTime? paidOn})? fundChoiceLoader,
  }) async {
    final r = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => BankLineAssignDialog(scope: scope, line: line, fundChoiceLoader: fundChoiceLoader),
    );
    return r == true;
  }

  @override
  State<BankLineAssignDialog> createState() => _BankLineAssignDialogState();
}

class _BankLineAssignDialogState extends State<BankLineAssignDialog> {
  int? _apartmentId;
  String? _label;
  String? _party;
  bool _saveIban = false;
  bool _busy = false;
  String? _error;

  // K3: tahsilatın gireceği İşletme / Fon hesabı.
  FinanceFund? _fund;
  FundChoiceState _fundState = const FundChoiceState();
  FundChoiceInfo? _forcedFundInfo;
  bool _fundRequiredByServer = false;
  String? _fundError;

  static const String _fundPendingMessage = 'İşletme / Fon hesabı bilgisi yükleniyor; birkaç saniye sonra yeniden deneyin.';
  static const String _fundMissingMessage = 'Ödemenin işleneceği İşletme / Fon hesabını seçin.';

  bool get _fundRequired => (_forcedFundInfo ?? _fundState.info)?.choiceRequired == true || _fundRequiredByServer;

  void _resetFundContext() {
    _forcedFundInfo = null;
    _fundRequiredByServer = false;
    _fundError = null;
  }

  @override
  void initState() {
    super.initState();
    _apartmentId = widget.line.apartmentId;
    _label = widget.line.apartmentLabel;
    _party = widget.line.party;
  }

  Future<void> _pick() async {
    final picked = await showApartmentPicker(context, widget.scope);
    if (picked == null || !mounted) return;
    setState(() {
      if (_apartmentId != picked.id) _resetFundContext();
      _apartmentId = picked.id;
      _label = picked.fullLabel;
    });
  }

  Future<void> _save() async {
    if (_busy || _apartmentId == null) return;
    // K3: bilgi yüklenirken gönderilmez (önerilen hesap seçili gelmeden işleme kısıtsız giderdi); iki türlü borçta seçim olmadan gönderilmez.
    if (_fundState.loading) {
      setState(() => _error = _fundPendingMessage);
      return;
    }
    if (_fundRequired && _fund == null) {
      setState(() {
        _error = null;
        _fundError = _fundMissingMessage;
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await BankImportService.of(widget.scope.authService).run(
        (api, token) => api.assignLine(
          token: token,
          siteCode: widget.scope.siteCode,
          lineId: widget.line.id,
          apartmentId: _apartmentId!,
          party: _party,
          saveIban: _saveIban,
          fund: _fund,
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
          // sunucu iki türlü borç nedeniyle seçim istedi (bilgi bayattı): yetkili durum panele işlenir
          if (e.code == 'FUND_CHOICE_REQUIRED') {
            _forcedFundInfo = FundChoiceInfo.tryParse(e.payload?['fund_choice']);
            _fundRequiredByServer = true;
            _fundError = _fundMissingMessage;
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final iban = widget.line.counterpartyIban;
    return AlertDialog(
      title: const Text('Daireye işle'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${widget.line.valueDate}  ${formatSignedMinor(widget.line.amountMinor)}', style: Theme.of(context).textTheme.titleSmall),
              if (widget.line.counterpartyName != null) Text(widget.line.counterpartyName!),
              Text(widget.line.description),
              const SizedBox(height: AppSpace.md),
              OutlinedButton.icon(
                key: const ValueKey<String>('bank_assign_pick'),
                onPressed: _busy ? null : _pick,
                icon: const Icon(Icons.apartment_rounded),
                label: Text(_label ?? 'Daire seçin'),
              ),
              const SizedBox(height: AppSpace.sm),
              SegmentedButton<String?>(
                segments: const <ButtonSegment<String?>>[
                  ButtonSegment<String?>(value: null, label: Text('Otomatik')),
                  ButtonSegment<String?>(value: 'tenant', label: Text('Kiracı')),
                  ButtonSegment<String?>(value: 'owner', label: Text('Ev sahibi')),
                ],
                selected: <String?>{_party},
                onSelectionChanged: _busy
                    ? null
                    : (s) => setState(() {
                        if (_party != s.first) _resetFundContext();
                        _party = s.first;
                      }),
              ),
              const SizedBox(height: AppSpace.md),
              FundChoicePanel(
                key: const ValueKey<String>('bank_assign_fund'),
                scope: widget.scope,
                apartmentId: _apartmentId,
                accountParty: AccountParty.tryParse(_party),
                amountMinor: widget.line.amountMinor > 0 ? widget.line.amountMinor : null,
                paidOn: DateTime.tryParse(widget.line.valueDate),
                selected: _fund,
                enabled: !_busy,
                loader: widget.fundChoiceLoader,
                forcedInfo: _forcedFundInfo,
                errorText: _fundError,
                keyPrefix: 'bank_assign_fund',
                onChanged: (value) => setState(() {
                  _fund = value;
                  _fundError = null;
                }),
                onStateChanged: (state) {
                  if (mounted && state != _fundState) setState(() => _fundState = state);
                },
              ),
              if (iban != null)
                CheckboxListTile(
                  key: const ValueKey<String>('bank_assign_save_iban'),
                  contentPadding: EdgeInsets.zero,
                  value: _saveIban,
                  onChanged: _busy ? null : (v) => setState(() => _saveIban = v == true),
                  title: const Text('Bu IBAN\'ı kaydet'),
                  subtitle: Text('$iban bu daireye bağlanır; sonraki dosyalarda otomatik tanınır.'),
                ),
              if (_error != null) Padding(padding: const EdgeInsets.only(top: AppSpace.sm), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(false), child: const Text('Vazgeç')),
        FilledButton(key: const ValueKey<String>('bank_assign_save'), onPressed: _apartmentId == null || _busy ? null : _save, child: const Text('İşle')),
      ],
    );
  }
}
