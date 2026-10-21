// Banka satırını daireye işle (Dalga 2 / 2C): aynı pencerede daire + hesap (kiracı / ev sahibi) seçimi ve "Bu IBAN'ı kaydet".
// Aynı tutarda mevcut bir tahsilat varsa sunucu yeni kayıt açmaz, ona bağlar (çift işleme yok).
import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/bank_import.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/bank_import_api.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/crm_pickers.dart';
import 'package:site_kapi_kontrol/ui/helpers/money.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';

class BankLineAssignDialog extends StatefulWidget {
  const BankLineAssignDialog({super.key, required this.scope, required this.line});

  final PeopleScope scope;
  final BankLineItem line;

  /// İşlenirse true.
  static Future<bool> show(BuildContext context, {required PeopleScope scope, required BankLineItem line}) async {
    final r = await showDialog<bool>(context: context, barrierDismissible: false, builder: (_) => BankLineAssignDialog(scope: scope, line: line));
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
      _apartmentId = picked.id;
      _label = picked.fullLabel;
    });
  }

  Future<void> _save() async {
    if (_busy || _apartmentId == null) return;
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
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
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
                onSelectionChanged: _busy ? null : (s) => setState(() => _party = s.first),
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
