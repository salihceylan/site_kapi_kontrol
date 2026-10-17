import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/finance.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/finance_receipt_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/finance_receipt_list_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_4b_access.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_errors.dart';
import 'package:site_kapi_kontrol/ui/helpers/istanbul_time.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_4b_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_parts.dart' show financeApartmentTitle;

/// Bir dairenin sakin tarafı için [PeopleScope] (yalnız okuma): site kodu dairenin sitesidir.
PeopleScope residentScopeOf(AuthService authService, MyFinanceApartment item) => PeopleScope(
  authService: authService,
  siteCode: item.siteCode,
  siteName: item.siteName,
  canWrite: false,
);

/// "Borcum" kartındaki Faz 4b eylemleri (sakin): **Makbuzlarım** (kendi dairesinin makbuzları) ve **Ekstre** PDF'i
/// (yazdır / paylaş; yılbaşından bugüne). Salt okuma: hiçbir şey yazmaz. PDF istemcide üretilir. Hata görünür kalır;
/// işlem sürerken düğmeler pasiftir (çift dokunuş yok).
class MyFinanceActions extends StatefulWidget {
  const MyFinanceActions({super.key, required this.authService, required this.item, this.now});

  final AuthService authService;
  final MyFinanceApartment item;
  final DateTime Function()? now;

  @override
  State<MyFinanceActions> createState() => _MyFinanceActionsState();
}

class _MyFinanceActionsState extends State<MyFinanceActions> {
  bool _busy = false;
  bool _opening = false;
  String? _error;

  PeopleScope get _scope => residentScopeOf(widget.authService, widget.item);

  String get _title => financeApartmentTitle(widget.item.blockName, widget.item.label);

  Future<void> _openReceipts() async {
    if (_busy || _opening) return;
    _opening = true;
    try {
      await FinanceReceiptListDialog.show(
        context,
        scope: _scope,
        apartmentId: widget.item.apartmentId,
        apartmentLabel: _title,
        resident: true,
        now: widget.now,
      );
    } finally {
      _opening = false;
    }
  }

  Future<void> _statement({required bool share}) async {
    if (_busy || _opening) return;
    final today = istanbulNow(widget.now?.call());
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final statement = await _scope.f4Call(
        (api, t, _) => api.getMyStatement(
          token: t,
          apartmentId: widget.item.apartmentId,
          from: DateTime(today.year, 1, 1),
          to: DateTime(today.year, today.month, today.day),
        ),
      );
      await FinancePdfActions.statement(statement, share: share);
      if (!mounted) return;
      setState(() => _busy = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = financeMessageOf(e, 'Ekstre hazırlanamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null) ...[
          FinanceSubmitError(key: const ValueKey<String>('my_finance_action_error'), message: _error!),
          const SizedBox(height: AppSpace.sm),
        ],
        Wrap(
          alignment: WrapAlignment.center,
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          children: [
            PrimaryActionButton(
              key: const ValueKey<String>('my_finance_receipts'),
              label: 'Makbuzlarım',
              icon: Icons.receipt_long_rounded,
              variant: AppButtonVariant.tonal,
              expand: false,
              onPressed: _busy ? null : _openReceipts,
            ),
            PrimaryActionButton(
              key: const ValueKey<String>('my_finance_statement_print'),
              label: 'Ekstreyi Yazdır',
              icon: Icons.print_rounded,
              variant: AppButtonVariant.tonal,
              expand: false,
              loading: _busy,
              onPressed: _busy ? null : () => _statement(share: false),
            ),
            PrimaryActionButton(
              key: const ValueKey<String>('my_finance_statement_share'),
              label: 'Ekstreyi Paylaş',
              icon: Icons.ios_share_rounded,
              variant: AppButtonVariant.tonal,
              expand: false,
              onPressed: _busy ? null : () => _statement(share: true),
            ),
          ],
        ),
      ],
    );
  }
}

/// Sakin ekstresinde makbuz satırından makbuz penceresi (yalnız okuma; basım "KOPYA" damgalı).
Future<void> openResidentReceipt(BuildContext context, AuthService authService, MyFinanceApartment item, ReceiptRef ref) {
  return FinanceReceiptDialog.show(
    context,
    scope: residentScopeOf(authService, item),
    receiptId: ref.id,
    initialNumber: ref.number,
    resident: true,
  );
}
