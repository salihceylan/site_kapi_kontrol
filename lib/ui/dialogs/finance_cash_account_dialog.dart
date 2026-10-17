import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MaxLengthEnforcement;
import 'package:site_kapi_kontrol/models/cash_models.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/large_dialog_parts.dart';
import 'package:site_kapi_kontrol/ui/helpers/date_input.dart';
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_4b_access.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_write_mixin.dart';
import 'package:site_kapi_kontrol/ui/helpers/form_validation.dart';
import 'package:site_kapi_kontrol/ui/helpers/istanbul_time.dart';
import 'package:site_kapi_kontrol/ui/helpers/money.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/helpers/text_length.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_4b_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/money_field.dart';

/// Kasa / banka hesabı ekleme ve düzenleme penceresi (Platform Faz 4b, Ö4).
///
/// - Yeni hesap: ad (1-60), tür (Kasa / Banka), isteğe bağlı not, AÇILIŞ bakiyesi ve tarihi. Açılış bilgileri sonradan
///   DEĞİŞMEZ (sunucu ilkesi); yanlış açılış için düzeltme hareketi kullanılır. En çok 20 hesap.
/// - Düzenleme: ad, not ve etkin / pasif. Pasifleştirmede bakiye sıfır değilse uyarılır (hesap bakiyesi kalır; pasif
///   hesaba yeni hareket yazılamaz).
/// - Çift gönderim koruması, işlem anahtarı (veri imzasına bağlı), hata pencerede kalır.
class FinanceCashAccountDialog extends StatefulWidget {
  const FinanceCashAccountDialog({super.key, required this.scope, this.account, this.now, this.onRefreshNeeded});

  final PeopleScope scope;

  /// Düzenlenen hesap; null ise yeni hesap.
  final CashAccount? account;
  final DateTime Function()? now;
  final VoidCallback? onRefreshNeeded;

  static const int maxNameLength = 60;
  static const int maxNoteLength = 200;

  static Future<FinanceWriteOutcome?> show(
    BuildContext context, {
    required PeopleScope scope,
    CashAccount? account,
    DateTime Function()? now,
    VoidCallback? onRefreshNeeded,
  }) {
    return showDialog<FinanceWriteOutcome>(
      context: context,
      barrierDismissible: false,
      builder: (_) => FinanceCashAccountDialog(scope: scope, account: account, now: now, onRefreshNeeded: onRefreshNeeded),
    );
  }

  @override
  State<FinanceCashAccountDialog> createState() => _FinanceCashAccountDialogState();
}

class _FinanceCashAccountDialogState extends State<FinanceCashAccountDialog> with FinanceWriteMixin, FinanceDiscardGuard {
  @override
  String get keyPrefix => 'acct';

  @override
  Object? get keyOwner => widget.scope.authService;

  @override
  bool get closeLocked => submitting;

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _name = TextEditingController(text: widget.account?.name ?? '');
  late final TextEditingController _note = TextEditingController(text: widget.account?.note ?? '');
  final TextEditingController _opening = TextEditingController();
  late final TextEditingController _date = TextEditingController(text: formatDateField(_today()));
  late CashAccountKind _kind = widget.account?.kind ?? CashAccountKind.cash;
  late bool _active = widget.account?.isActive ?? true;
  bool _openingNegative = false;

  bool get _editing => widget.account != null;

  DateTime _today() {
    final wall = istanbulNow(widget.now?.call());
    return DateTime(wall.year, wall.month, wall.day);
  }

  @override
  void dispose() {
    disposeWrite();
    _name.dispose();
    _note.dispose();
    _opening.dispose();
    _date.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (writeBlocked) return;
    if (!validateForm(_formKey)) {
      setState(() => submitError = kFixFieldsMessage);
      return;
    }
    final name = _name.text.trim();
    final note = _note.text.trim();
    final scope = widget.scope;
    if (_editing) {
      final a = widget.account!;
      final fields = <String, Object?>{
        if (name != a.name) 'name': name,
        if (note != (a.note ?? '')) 'note': note,
        if (_active != a.isActive) 'is_active': _active,
      };
      if (fields.isEmpty) {
        setState(() => submitError = 'Değişiklik yapmadınız.');
        return;
      }
      await runWrite<CashAccount>(
        signature: 'edit|${a.id}|$name|$note|$_active',
        action: (_) => scope.f4Call(
          (api, t, s) => api.updateAccount(token: t, siteCode: s, accountId: a.id, fields: fields),
        ),
        onSuccess: (updated) {
          popIfCurrent(
            context,
            FinanceWriteOutcome(
              _active == a.isActive ? 'Hesap güncellendi: ${updated.name}.' : (_active ? 'Hesap etkinleştirildi: ${updated.name}.' : 'Hesap pasifleştirildi: ${updated.name}.'),
            ),
          );
        },
        failure: 'Hesap güncellenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
      );
      return;
    }
    final openingAbs = parseMoney(_opening.text, allowZero: true).minor ?? 0;
    final opening = _openingNegative ? -openingAbs : openingAbs;
    final date = parseDateField(_date.text)!;
    await runWrite<CashAccount>(
      signature: 'new|${name.toLowerCase()}|${_kind.apiValue}|$opening|${formatDateField(date)}|$note',
      action: (key) => scope.f4Call(
        (api, t, s) => api.createAccount(
          token: t,
          siteCode: s,
          name: name,
          kind: _kind,
          note: note,
          openingBalanceMinor: opening,
          openingDate: date,
          idempotencyKey: key,
        ),
      ),
      onSuccess: (created) {
        popIfCurrent(context, FinanceWriteOutcome('Hesap eklendi: ${created.name}.'));
      },
      failure: 'Hesap eklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
    );
  }

  void _notify() {
    if (!needsRefreshOnClose) return;
    needsRefreshOnClose = false;
    widget.onRefreshNeeded?.call();
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final account = widget.account;
    final deactivating = _editing && !_active && account!.isActive && account.balanceMinor != 0;
    return PopScope(
      canPop: canPopNow,
      onPopInvokedWithResult: (didPop, _) {
        handleBlockedPop(didPop);
        if (didPop) _notify();
      },
      child: AppDialog(
        title: _editing ? 'Hesabı Düzenle' : 'Hesap Ekle',
        subtitle: widget.scope.siteName.isEmpty ? null : widget.scope.siteName,
        icon: Icons.account_balance_rounded,
        actions: [
          TextButton(
            onPressed: submitting ? null : requestClose,
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            key: const ValueKey<String>('finance_account_submit'),
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
              TextFormField(
                key: const ValueKey<String>('finance_account_name'),
                controller: _name,
                enabled: !submitting,
                textCapitalization: TextCapitalization.sentences,
                maxLength: FinanceCashAccountDialog.maxNameLength,
                maxLengthEnforcement: MaxLengthEnforcement.none,
                buildCounter: (context, {required currentLength, required isFocused, maxLength}) =>
                    characterCounter(context, trimmedCodePoints(_name.text), FinanceCashAccountDialog.maxNameLength),
                autovalidateMode: AutovalidateMode.onUserInteraction,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Hesap adı',
                  hintText: 'Örn. Nakit Kasa, Ziraat Bankası',
                  prefixIcon: Icon(Icons.badge_rounded),
                ),
                validator: (value) {
                  final length = trimmedCodePoints(value ?? '');
                  if (length < 1) return 'Hesap adını girin.';
                  if (length > FinanceCashAccountDialog.maxNameLength) {
                    return 'Ad en çok ${FinanceCashAccountDialog.maxNameLength} karakter olabilir.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: AppSpace.md),
              if (!_editing) ...[
                const FinanceGroupTitle('Tür'),
                const SizedBox(height: AppSpace.sm),
                Wrap(
                  spacing: AppSpace.sm,
                  runSpacing: AppSpace.sm,
                  children: [
                    for (final kind in const [CashAccountKind.cash, CashAccountKind.bank])
                      ChoiceChip(
                        key: ValueKey<String>('finance_account_kind_${kind.apiValue}'),
                        avatar: Icon(cashKindIcon(kind), size: 18),
                        label: Text(kind.label),
                        selected: _kind == kind,
                        onSelected: submitting
                            ? null
                            : (_) => setState(() {
                                markDirty();
                                _kind = kind;
                              }),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpace.md),
              ] else ...[
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: DialogMetaPill(widget.account!.kind.label, tone: AppTone.info, icon: cashKindIcon(widget.account!.kind)),
                ),
                const SizedBox(height: AppSpace.md),
              ],
              TextFormField(
                key: const ValueKey<String>('finance_account_note'),
                controller: _note,
                enabled: !submitting,
                minLines: 1,
                maxLines: 3,
                maxLength: FinanceCashAccountDialog.maxNoteLength,
                maxLengthEnforcement: MaxLengthEnforcement.none,
                buildCounter: (context, {required currentLength, required isFocused, maxLength}) =>
                    characterCounter(context, trimmedCodePoints(_note.text), FinanceCashAccountDialog.maxNoteLength),
                textCapitalization: TextCapitalization.sentences,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Not (isteğe bağlı)',
                  alignLabelWithHint: true,
                  prefixIcon: Icon(Icons.notes_rounded),
                ),
                validator: (value) => trimmedCodePoints(value ?? '') > FinanceCashAccountDialog.maxNoteLength
                    ? 'Not en çok ${FinanceCashAccountDialog.maxNoteLength} karakter olabilir.'
                    : null,
              ),
              if (!_editing) ...[
                const SizedBox(height: AppSpace.md),
                MoneyFormField(
                  key: const ValueKey<String>('finance_account_opening_group'),
                  fieldKey: const ValueKey<String>('finance_account_opening'),
                  controller: _opening,
                  enabled: !submitting,
                  label: 'Açılış bakiyesi',
                  required: false,
                  allowZero: true,
                  helperText: 'Boş bırakırsanız sıfır olur. Açılış bilgisi sonradan değiştirilemez.',
                  textInputAction: TextInputAction.next,
                ),
                Material(
                  type: MaterialType.transparency,
                  child: SwitchListTile(
                    key: const ValueKey<String>('finance_account_opening_negative'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Açılış bakiyesi eksi (hesap borçlu)'),
                    subtitle: const Text('Kredili ya da eksi bakiyeyle açılan hesap için.'),
                    value: _openingNegative,
                    onChanged: submitting
                        ? null
                        : (value) => setState(() {
                            markDirty();
                            _openingNegative = value;
                          }),
                  ),
                ),
                const SizedBox(height: AppSpace.md),
                FinanceDateField(
                  key: const ValueKey<String>('finance_account_opening_date_group'),
                  controller: _date,
                  label: 'Açılış tarihi',
                  enabled: !submitting,
                  maxDate: _today(),
                  maxMessage: 'Açılış tarihi bugünden ileri olamaz.',
                  helperText: 'Bu tarihten önceki tahsilat ve giderler bu hesaba yazılamaz.',
                ),
              ] else ...[
                const SizedBox(height: AppSpace.md),
                Material(
                  type: MaterialType.transparency,
                  child: SwitchListTile(
                    key: const ValueKey<String>('finance_account_active'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Hesap aktif'),
                    subtitle: const Text('Pasif hesaba yeni tahsilat, gider ya da aktarım yazılamaz.'),
                    value: _active,
                    onChanged: submitting
                        ? null
                        : (value) => setState(() {
                            markDirty();
                            _active = value;
                          }),
                  ),
                ),
                if (deactivating) ...[
                  const SizedBox(height: AppSpace.sm),
                  InlineNotice(
                    key: const ValueKey<String>('finance_account_deactivate_warning'),
                    tone: AppTone.warning,
                    message:
                        'Bu hesabın bakiyesi ${formatMinor(widget.account!.balanceMinor)}. Pasifleştirince bakiye '
                        'silinmez; önce aktarım ya da düzeltmeyle sıfırlamanız önerilir.',
                    semanticsLabel: spokenMoneyText(
                      'Bu hesabın bakiyesi ${formatMinor(widget.account!.balanceMinor)}. Pasifleştirince bakiye '
                      'silinmez; önce aktarım ya da düzeltmeyle sıfırlamanız önerilir.',
                    ),
                  ),
                ],
              ],
              const SizedBox(height: AppSpace.sm),
              Text(
                'Hesaplar kasa / banka bakiyesini tutar; tahsilat ve giderler seçilen hesaba işlenir.',
                style: th.bodySmall?.copyWith(color: p.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
