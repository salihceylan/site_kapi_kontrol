import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/device_integrations_api.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_errors.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_4b_parts.dart' show FinanceSubmitError;

/// Kart Ödemesi (Aidat ve Finans'ın parçası): ödeme sağlayıcıları (iyzico, PayTR) "Yakında…" durumundadır; yalnız
/// komisyon bilgi notu kaydedilir (komisyon ödemeyi yapana yansıtılır, tahsilat YAPILMAZ).
///
/// Eskiden ayrı bir modüldü (`card_payments`, "Ödeme ve Kamera" ekranında); artık Finans ekranından açılır ve ayrı bir
/// modül açmayı gerektirmez. Yönetici ([PeopleScope.canWrite]) komisyon notunu düzenler, kurul üyesi salt okur.
/// Uçlar değişmedi (`/manager/sites/:siteCode/card-payments`).
class FinanceCardPaymentsDialog extends StatefulWidget {
  const FinanceCardPaymentsDialog({super.key, required this.scope, this.service});

  final PeopleScope scope;

  /// Testler içindir; null ise oturumdan kurulur.
  final DeviceIntegrationsService? service;

  static Future<void> show(
    BuildContext context, {
    required PeopleScope scope,
    DeviceIntegrationsService? service,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => FinanceCardPaymentsDialog(scope: scope, service: service),
    );
  }

  @override
  State<FinanceCardPaymentsDialog> createState() => _FinanceCardPaymentsDialogState();
}

class _FinanceCardPaymentsDialogState extends State<FinanceCardPaymentsDialog> {
  late final DeviceIntegrationsService _service =
      widget.service ?? DeviceIntegrationsService(authService: widget.scope.authService);

  PaymentOverview? _overview;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _notice;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final overview = await _service.payments(widget.scope.siteCode);
      if (!mounted) return;
      setState(() {
        _overview = overview;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = financeMessageOf(e, 'Kart ödemesi bilgileri yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.');
        _loading = false;
      });
    }
  }

  Future<void> _editCommission(PaymentProviderInfo provider) async {
    if (_saving) return;
    final saved = await showDialog<String>(
      context: context,
      builder: (_) => _CommissionNoteDialog(provider: provider),
    );
    if (saved == null || !mounted) return;
    setState(() {
      _saving = true;
      _error = null;
      _notice = null;
    });
    try {
      final overview = await _service.saveCommissionInfo(widget.scope.siteCode, provider.code, saved);
      if (!mounted) return;
      setState(() {
        _overview = overview;
        _saving = false;
        _notice = 'Bilgi kaydedildi.';
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = financeMessageOf(e, 'Bilgi kaydedilemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.');
      });
    }
  }

  Widget _soon(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text('Yakında…', style: Theme.of(context).textTheme.labelSmall),
    );
  }

  Widget _providerTile(BuildContext context, PaymentProviderInfo provider) {
    final note = (provider.commissionInfo ?? '').trim();
    return ListTile(
      key: ValueKey<String>('finance_card_provider_${provider.code}'),
      contentPadding: EdgeInsets.zero,
      title: Row(
        children: <Widget>[
          Flexible(child: Text(provider.name)),
          const SizedBox(width: AppSpace.sm),
          _soon(context),
        ],
      ),
      subtitle: Text(note.isEmpty ? 'Komisyon notu yok' : note),
      trailing: widget.scope.canWrite
          ? IconButton(
              tooltip: 'Komisyon notunu düzenle',
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              icon: const Icon(Icons.edit_rounded),
              onPressed: _saving ? null : () => _editCommission(provider),
            )
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final overview = _overview;
    return AppDialog(
      title: 'Kart Ödemesi',
      subtitle: widget.scope.siteName.trim().isEmpty ? null : widget.scope.siteName.trim(),
      icon: Icons.credit_card_rounded,
      actions: <Widget>[
        TextButton(
          key: const ValueKey<String>('finance_card_payments_close'),
          onPressed: () => popIfCurrent(context),
          child: const Text('Kapat'),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (_error != null)
            FinanceSubmitError(
              key: const ValueKey<String>('finance_card_payments_error'),
              message: _error!,
              action: overview == null
                  ? TextButton.icon(
                      onPressed: _loading ? null : () => unawaited(_load()),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Tekrar dene'),
                    )
                  : null,
            ),
          if (_loading)
            const Center(child: Padding(padding: EdgeInsets.all(AppSpace.lg), child: CircularProgressIndicator()))
          else if (overview != null) ...<Widget>[
            Text(overview.notice.isEmpty ? 'Kart ödeme komisyonu ödemeyi yapana yansıtılır.' : overview.notice),
            const SizedBox(height: AppSpace.sm),
            for (final provider in overview.providers) _providerTile(context, provider),
            const SizedBox(height: AppSpace.xs),
            const Text('Kartla ödeme henüz açık değil; sağlayıcı sözleşmesi tamamlanınca etkinleşecek.'),
            if (_notice != null) ...<Widget>[
              const SizedBox(height: AppSpace.sm),
              Text(_notice!, key: const ValueKey<String>('finance_card_payments_notice')),
            ],
          ],
        ],
      ),
    );
  }
}

/// Komisyon notu düzenleme penceresi: denetleyiciyi KENDİ yaşam döngüsünde tutar (kapanış animasyonu sürerken yok edilmez).
/// Kaydet metni olduğu gibi döndürür; kırpma ve 300 karakter sınırı sunucuda da uygulanır.
class _CommissionNoteDialog extends StatefulWidget {
  const _CommissionNoteDialog({required this.provider});

  final PaymentProviderInfo provider;

  @override
  State<_CommissionNoteDialog> createState() => _CommissionNoteDialogState();
}

class _CommissionNoteDialogState extends State<_CommissionNoteDialog> {
  late final TextEditingController _controller = TextEditingController(text: widget.provider.commissionInfo ?? '');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${widget.provider.name} komisyon bilgisi'),
      content: TextField(
        key: const ValueKey<String>('finance_card_payments_note_field'),
        controller: _controller,
        maxLength: 300,
        maxLines: 3,
        decoration: const InputDecoration(
          labelText: 'Not (isteğe bağlı)',
          helperText: 'Komisyon ödemeyi yapana yansıtılır.',
        ),
      ),
      actions: <Widget>[
        TextButton(onPressed: () => popIfCurrent(context), child: const Text('Vazgeç')),
        FilledButton(
          key: const ValueKey<String>('finance_card_payments_note_save'),
          onPressed: () => popIfCurrent(context, _controller.text),
          child: const Text('Kaydet'),
        ),
      ],
    );
  }
}
