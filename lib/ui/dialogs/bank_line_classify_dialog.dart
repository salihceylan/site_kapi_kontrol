// Daire dışı banka satırı: gelir/gider olarak ayır (Dalga 2 / 2C). Çıkan para: Gider, Banka masrafı, Aktarım, Yok say.
// Giren para: Faiz, Diğer gelir, Aktarım, Yok say. Kayıtlar mevcut gider / düzeltme / aktarım işlevleriyle yazılır; satırdan "Geri al" ile kaldırılır.
import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/bank_import.dart';
import 'package:site_kapi_kontrol/models/cash_models.dart';
import 'package:site_kapi_kontrol/models/expense_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/bank_import_api.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_4b_access.dart';
import 'package:site_kapi_kontrol/ui/helpers/money.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';

class BankLineClassifyDialog extends StatefulWidget {
  const BankLineClassifyDialog({super.key, required this.scope, required this.line});

  final PeopleScope scope;
  final BankLineItem line;

  /// Kaydedilirse true.
  static Future<bool> show(BuildContext context, {required PeopleScope scope, required BankLineItem line}) async {
    final r = await showDialog<bool>(context: context, barrierDismissible: false, builder: (_) => BankLineClassifyDialog(scope: scope, line: line));
    return r == true;
  }

  @override
  State<BankLineClassifyDialog> createState() => _BankLineClassifyDialogState();
}

class _BankLineClassifyDialogState extends State<BankLineClassifyDialog> {
  String? _kind;
  List<ExpenseCategory> _categories = const <ExpenseCategory>[];
  List<CashAccount> _accounts = const <CashAccount>[];
  int? _categoryId;
  int? _accountId;
  final TextEditingController _note = TextEditingController();
  bool _loading = false;
  bool _busy = false;
  String? _error;

  bool get _incoming => widget.line.incoming;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _choose(String kind) async {
    setState(() {
      _kind = kind;
      _error = null;
    });
    if (kind == 'expense' && _categories.isEmpty) {
      await _load(() async {
        final c = await widget.scope.f4Call((api, t, s) => api.listExpenseCategories(token: t, siteCode: s, active: true));
        if (mounted) setState(() => _categories = c);
      });
    }
    if (kind == 'transfer' && _accounts.isEmpty) {
      await _load(() async {
        final o = await widget.scope.f4Call((api, t, s) => api.listAccounts(token: t, siteCode: s));
        if (mounted) setState(() => _accounts = o.activeAccounts);
      });
    }
  }

  Future<void> _load(Future<void> Function() work) async {
    setState(() => _loading = true);
    try {
      await work();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _valid {
    switch (_kind) {
      case 'expense':
        return _categoryId != null;
      case 'transfer':
        return _accountId != null;
      case 'other_income':
        return _note.text.trim().isNotEmpty;
      case null:
        return false;
      default:
        return true;
    }
  }

  Future<void> _save() async {
    if (_busy || !_valid) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await BankImportService.of(widget.scope.authService).run(
        (api, token) => api.classifyLine(
          token: token,
          siteCode: widget.scope.siteCode,
          lineId: widget.line.id,
          kind: _kind!,
          categoryId: _kind == 'expense' ? _categoryId : null,
          transferAccountId: _kind == 'transfer' ? _accountId : null,
          note: _note.text.trim().isEmpty ? null : _note.text.trim(),
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
    final options = _incoming
        ? const <(String, String)>[('interest', 'Faiz geliri'), ('other_income', 'Diğer gelir'), ('transfer', 'Hesaplar arası aktarım'), ('ignore', 'Yok say')]
        : const <(String, String)>[('expense', 'Gider'), ('bank_fee', 'Banka masrafı'), ('transfer', 'Hesaplar arası aktarım'), ('ignore', 'Yok say')];
    return AlertDialog(
      title: const Text('Daire dışı satır'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${widget.line.valueDate}  ${formatSignedMinor(widget.line.amountMinor)}', style: Theme.of(context).textTheme.titleSmall),
              Text(widget.line.description),
              const SizedBox(height: AppSpace.md),
              Wrap(
                spacing: AppSpace.sm,
                children: [
                  for (final o in options)
                    ChoiceChip(key: ValueKey<String>('bank_cls_${o.$1}'), label: Text(o.$2), selected: _kind == o.$1, onSelected: _busy ? null : (_) => _choose(o.$1)),
                ],
              ),
              if (_loading) const Padding(padding: EdgeInsets.all(AppSpace.md), child: LinearProgressIndicator()),
              if (_kind == 'expense')
                DropdownButtonFormField<int>(
                  initialValue: _categoryId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Gider kategorisi *'),
                  items: [for (final c in _categories) DropdownMenuItem<int>(value: c.id, child: Text(c.name))],
                  onChanged: (v) => setState(() => _categoryId = v),
                ),
              if (_kind == 'transfer')
                DropdownButtonFormField<int>(
                  initialValue: _accountId,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: _incoming ? 'Hangi hesaptan geldi? *' : 'Hangi hesaba gitti? *'),
                  items: [for (final a in _accounts) if (a.id != widget.line.accountId) DropdownMenuItem<int>(value: a.id, child: Text(a.name))],
                  onChanged: (v) => setState(() => _accountId = v),
                ),
              if (_kind != null && _kind != 'ignore')
                TextField(
                  controller: _note,
                  maxLength: 200,
                  decoration: InputDecoration(labelText: _kind == 'other_income' ? 'Açıklama *' : 'Not (isteğe bağlı)'),
                  onChanged: (_) => setState(() {}),
                ),
              if (_error != null) Padding(padding: const EdgeInsets.only(top: AppSpace.sm), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(false), child: const Text('Vazgeç')),
        FilledButton(key: const ValueKey<String>('bank_cls_save'), onPressed: _valid && !_busy ? _save : null, child: const Text('Kaydet')),
      ],
    );
  }
}
