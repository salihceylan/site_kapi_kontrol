// Banka dosyası sütun eşleme penceresi (Dalga 2 / 2C). Başlık imzası kayıtlı profille uyuşmazsa açılır; seçim hesap başına profil olarak saklanır.
import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/services/bank_statement_reader.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

class BankMappingDialog extends StatefulWidget {
  const BankMappingDialog({super.key, required this.table, required this.initial});

  final BankTable table;
  final BankMapping initial;

  /// Onaylanırsa eşleme, vazgeçilirse null.
  static Future<BankMapping?> show(BuildContext context, {required BankTable table, required BankMapping initial}) {
    return showDialog<BankMapping>(
      context: context,
      barrierDismissible: false,
      builder: (_) => BankMappingDialog(table: table, initial: initial),
    );
  }

  @override
  State<BankMappingDialog> createState() => _BankMappingDialogState();
}

class _BankMappingDialogState extends State<BankMappingDialog> {
  late BankMapping _m = widget.initial;
  bool _split = false;

  @override
  void initState() {
    super.initState();
    _split = widget.initial.amount == null && (widget.initial.debit != null || widget.initial.credit != null);
  }

  List<DropdownMenuItem<int?>> get _items => <DropdownMenuItem<int?>>[
    const DropdownMenuItem<int?>(value: null, child: Text('— yok —')),
    for (var i = 0; i < widget.table.headers.length; i++)
      DropdownMenuItem<int?>(value: i, child: Text(widget.table.headers[i].trim().isEmpty ? 'Sütun ${i + 1}' : widget.table.headers[i], overflow: TextOverflow.ellipsis)),
  ];

  Widget _row(String label, int? value, ValueChanged<int?> onChanged, {bool required = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: DropdownButtonFormField<int?>(
        key: ValueKey<String>('bank_map_$label'),
        initialValue: value,
        isExpanded: true,
        items: _items,
        decoration: InputDecoration(labelText: required ? '$label *' : label),
        onChanged: onChanged,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sample = widget.table.rows.isEmpty ? null : widget.table.rows.first.cells.map((c) => c?.toString() ?? '').join(' | ');
    return AlertDialog(
      title: const Text('Sütunları eşleyin'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Dosyanızdaki sütunların ne olduğunu seçin. Bir kez seçtiğinizde bu hesap için hatırlanır.'),
              if (sample != null) Padding(padding: const EdgeInsets.symmetric(vertical: AppSpace.sm), child: Text('Örnek satır: $sample', style: Theme.of(context).textTheme.bodySmall)),
              _row('Tarih', _m.date, (v) => setState(() => _m = _m.copyWith(date: () => v)), required: true),
              _row('Açıklama', _m.description, (v) => setState(() => _m = _m.copyWith(description: () => v))),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Borç ve alacak ayrı sütunlarda'),
                value: _split,
                onChanged: (v) => setState(() {
                  _split = v;
                  _m = v ? _m.copyWith(amount: () => null) : _m.copyWith(debit: () => null, credit: () => null);
                }),
              ),
              if (_split) ...[
                _row('Borç (çıkan)', _m.debit, (v) => setState(() => _m = _m.copyWith(debit: () => v))),
                _row('Alacak (giren)', _m.credit, (v) => setState(() => _m = _m.copyWith(credit: () => v))),
              ] else ...[
                _row('Tutar', _m.amount, (v) => setState(() => _m = _m.copyWith(amount: () => v)), required: true),
                _row('Borç/Alacak göstergesi (B/A)', _m.indicator, (v) => setState(() => _m = _m.copyWith(indicator: () => v))),
              ],
              _row('Bakiye', _m.balance, (v) => setState(() => _m = _m.copyWith(balance: () => v))),
              _row('Gönderen / karşı taraf', _m.name, (v) => setState(() => _m = _m.copyWith(name: () => v))),
              _row('Karşı IBAN', _m.iban, (v) => setState(() => _m = _m.copyWith(iban: () => v))),
              _row('Dekont no / referans', _m.reference, (v) => setState(() => _m = _m.copyWith(reference: () => v))),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Vazgeç')),
        FilledButton(
          key: const ValueKey<String>('bank_map_ok'),
          onPressed: _m.isComplete ? () => Navigator.of(context).pop(_m) : null,
          child: const Text('Devam'),
        ),
      ],
    );
  }
}
